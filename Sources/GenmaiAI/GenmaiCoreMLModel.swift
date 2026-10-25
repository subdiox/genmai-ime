// genmai model on Core ML (Neural Engine): the shared beam search (`GenmaiDecoder`) over a stateful Core ML model.
//
// The model directory holds `genmai.mlpackage` (or a compiled `genmai.mlmodelc`), `genmai_coreml.json`,
// `tokenizer.json` and `config.json`. The package has two functions sharing one `MLState`:
// - "prefill": `ids` (1, C) written to prompt slots start ..< start + C (`pos` (1, C) position ids, `mask` (C, P)
//   additive over the prompt slots); returns the log-probs after each of the C tokens;
// - "decode": `tok` (B, 1) at position `pos` (1,), written to output slots t * B + r (selected by `wsel` (S*B, B)
//   one-hot and `keep` (S*B, 1); a blend, because a dynamic slice update of a state runs on the CPU and splits the
//   Neural Engine graph); `pmask` (1, P) and `smask` (B, S*B) additive.
// Beam reordering does not copy the cache: each row attends to its ancestors' output slots through `smask`. The
// state keeps the last prompt, so a prompt that shares a token prefix with it only prefills the new tail.
//
// A large model is split into `chunks` packages `genmai_0.mlpackage` ... (a package with the weights of more than
// ~12 layers of genmai-310M does not load on the Neural Engine), each with the same two functions for its layers
// and its own state; chunk 0 takes the tokens, the others the previous chunk's `hidden` output, and the last one
// returns the log-probs.
//
// The B rows hold one search, so the contexts of a batch are searched one after another; `GenmaiSearchBound` stops
// those that cannot change the result of an `extend`. Drafts are
// verified by prefilling them after the prompt: the accepted tokens' KV stays in the prompt slots.

import CoreML
import Foundation

/// `genmai_coreml.json`: the static shapes the package was converted with.
public struct GenmaiCoreMLConfig: Sendable, Codable {
  public static let supportedFormat = "genmai-coreml-1"
  public var format: String
  /// P: prompt KV slots (the longest prompt, with its draft).
  public var promptSlots: Int
  /// S: output KV slots per row (the most decode steps).
  public var outputSteps: Int
  /// B: rows decoded per step (the widest beam).
  public var rows: Int
  /// C: prompt tokens per prefill call.
  public var prefillChunk: Int
  /// Packages the layers are split into (nil: 1, `genmai.mlpackage`).
  public var chunks: Int?

  enum CodingKeys: String, CodingKey {
    case format
    case promptSlots = "prompt_slots"
    case outputSteps = "output_steps"
    case rows
    case prefillChunk = "prefill_chunk"
    case chunks
  }

  /// The packages' base names: "genmai", or "genmai_0", "genmai_1", ...
  public var packageNames: [String] {
    let n = chunks ?? 1
    return n == 1 ? ["genmai"] : (0..<n).map { "genmai_\($0)" }
  }
}

public final class GenmaiCoreMLModel: GenmaiDecoder {
  public static let configFileName = "genmai_coreml.json"

  public let config: GenmaiCoreMLConfig
  public let tokenizer: GenmaiTokenizer
  /// Seconds spent loading (compiling the package if needed, loading both functions).
  public let loadSeconds: Double
  public private(set) var promptTokensPrefilled = 0
  public private(set) var promptTokensReused = 0
  public private(set) var draftTokensAccepted = 0
  /// Decode calls (one per step of each search).
  public private(set) var decodeSteps = 0
  /// Seconds spent in prefill / decode calls of the model (diagnostics).
  public private(set) var prefillSeconds = 0.0
  public private(set) var decodeSeconds = 0.0

  /// Per chunk: the two functions and the state they share.
  private let prefillModels: [MLModel]
  private let decodeModels: [MLModel]
  private let states: [MLState]
  private let eos: Int32
  private let vocabSize: Int
  /// The tokens whose KV is in the prompt slots [0, cached.count).
  private var cached: [Int32] = []
  private var draftStore = GenmaiDraftStore()
  // Input arrays, allocated once and overwritten before each call (the providers hold them).
  private let prefillIDs, prefillPos, prefillStart, prefillMask: MLMultiArray
  private let prefillInput: MLDictionaryFeatureProvider
  private let decodeTok, decodePos, decodePMask, decodeSMask: MLMultiArray
  /// Per decode step t: the inputs with `wsel` / `keep` placing the rows at slots t * B + r.
  private let decodeInputs: [MLDictionaryFeatureProvider]
  private let decodeSelections: [(wsel: MLMultiArray, keep: MLMultiArray)]

  private static let masked = Float16(-1e4)

  public static func load(directory: URL, computeUnits: MLComputeUnits = .cpuAndNeuralEngine) async throws
    -> GenmaiCoreMLModel
  {
    let start = Date()
    let configURL = directory.appending(path: configFileName)
    guard FileManager.default.fileExists(atPath: configURL.path) else { throw GenmaiError.missingFile(configURL) }
    let config = try JSONDecoder().decode(GenmaiCoreMLConfig.self, from: Data(contentsOf: configURL))
    guard config.format == GenmaiCoreMLConfig.supportedFormat else {
      throw GenmaiError.badModel("unsupported Core ML format \(config.format)")
    }
    var prefill: [MLModel] = []
    var decode: [MLModel] = []
    for name in config.packageNames {
      var modelURL = directory.appending(path: "\(name).mlmodelc")
      if !FileManager.default.fileExists(atPath: modelURL.path) {
        let package = directory.appending(path: "\(name).mlpackage")
        guard FileManager.default.fileExists(atPath: package.path) else { throw GenmaiError.missingFile(package) }
        modelURL = try await MLModel.compileModel(at: package)
      }
      func function(_ name: String) throws -> MLModel {
        let c = MLModelConfiguration()
        c.computeUnits = computeUnits
        c.functionName = name
        return try MLModel(contentsOf: modelURL, configuration: c)
      }
      prefill.append(try function("prefill"))
      decode.append(try function("decode"))
    }
    let tokenizer = try GenmaiTokenizer(url: directory.appending(path: "tokenizer.json"))
    let modelConfig = try JSONDecoder().decode(
      GenmaiConfig.self, from: Data(contentsOf: directory.appending(path: "config.json")))
    return try GenmaiCoreMLModel(
      config: config, tokenizer: tokenizer, vocabSize: modelConfig.vocabSize, prefill: prefill, decode: decode,
      loadSeconds: Date().timeIntervalSince(start))
  }

  private init(
    config: GenmaiCoreMLConfig, tokenizer: GenmaiTokenizer, vocabSize: Int, prefill: [MLModel], decode: [MLModel],
    loadSeconds: Double
  ) throws {
    self.config = config
    self.tokenizer = tokenizer
    self.vocabSize = vocabSize
    self.prefillModels = prefill
    self.decodeModels = decode
    self.states = decode.map { $0.makeState() }
    self.eos = tokenizer.eosTokenID
    self.loadSeconds = loadSeconds
    let b = config.rows
    let c = config.prefillChunk
    let p = config.promptSlots
    let slots = config.outputSteps * b
    prefillIDs = try Self.array([1, c], .int32)
    prefillPos = try Self.array([1, c], .int32)
    prefillStart = try Self.array([1], .int32)
    prefillMask = try Self.array([c, p], .float16)
    prefillInput = try MLDictionaryFeatureProvider(dictionary: [
      "ids": prefillIDs, "pos": prefillPos, "start": prefillStart, "mask": prefillMask,
    ])
    decodeTok = try Self.array([b, 1], .int32)
    decodePos = try Self.array([1], .int32)
    decodePMask = try Self.array([1, p], .float16)
    decodeSMask = try Self.array([b, slots], .float16)
    var inputs: [MLDictionaryFeatureProvider] = []
    var selections: [(wsel: MLMultiArray, keep: MLMultiArray)] = []
    for t in 0..<config.outputSteps {
      var wsel = [Float16](repeating: 0, count: slots * b)
      var keep = [Float16](repeating: 1, count: slots)
      for r in 0..<b {
        wsel[(t * b + r) * b + r] = 1
        keep[t * b + r] = 0
      }
      let wselArray = try Self.array([slots, b], .float16)
      let keepArray = try Self.array([slots, 1], .float16)
      Self.write(wsel, to: wselArray)
      Self.write(keep, to: keepArray)
      selections.append((wselArray, keepArray))
      inputs.append(
        try MLDictionaryFeatureProvider(dictionary: [
          "tok": decodeTok, "pos": decodePos, "wsel": wselArray, "keep": keepArray, "pmask": decodePMask,
          "smask": decodeSMask,
        ]))
    }
    decodeInputs = inputs
    decodeSelections = selections
  }

  private static func array(_ shape: [Int], _ type: MLMultiArrayDataType) throws -> MLMultiArray {
    try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: type)
  }

  // MLMultiArray exposes its storage only through raw pointers; these two copy whole contiguous arrays (allocated
  // by `array`, or model outputs) in and out of Swift arrays of the matching scalar type.
  private static func write<T>(_ scalars: [T], to a: MLMultiArray) {
    a.withUnsafeMutableBytes { dst, _ in
      scalars.withUnsafeBytes { src in dst.copyMemory(from: UnsafeRawBufferPointer(rebasing: src.prefix(dst.count))) }
    }
  }

  private static func logProbs(_ out: any MLFeatureProvider) throws -> [Float] {
    guard let a = out.featureValue(for: "logp")?.multiArrayValue, a.dataType == .float32 else {
      throw GenmaiError.badModel("no float32 logp output")
    }
    var res = [Float](repeating: 0, count: a.count)
    a.withUnsafeBytes { src in res.withUnsafeMutableBytes { $0.copyMemory(from: src) } }
    return res
  }

  public func clearPromptCache() {
    cached = []
    draftStore.clear()
  }

  // MARK: - Model calls

  /// Makes the prompt slots hold the KV of `ids` (prefilling from the first token that differs from the cached
  /// prompt, or from `outputsFrom` if that is earlier) and returns the log-probs after the tokens at
  /// outputsFrom ..< ids.count (none without `outputsFrom`; then nothing is computed if the KV is already there).
  private func prefill(_ ids: [Int32], outputsFrom: Int? = nil) throws -> [[Float]] {
    let n = ids.count
    if outputsFrom == nil && cached.starts(with: ids) { return [] }
    let started = Date()
    defer { prefillSeconds += Date().timeIntervalSince(started) }
    let p = config.promptSlots
    let c = config.prefillChunk
    var common = 0
    while common < min(n, cached.count) && ids[common] == cached[common] { common += 1 }
    var s = min(common, outputsFrom ?? n)
    promptTokensReused += s
    promptTokensPrefilled += n - s
    cached = Array(ids.prefix(s))  // the slots from s on change below
    var rows: [[Float]] = []
    while s < n {
      // the last chunk ends at slot P at most; recomputing earlier slots writes the same values
      let s0 = min(s, p - c)
      var x = [Int32](repeating: 0, count: c)
      var pos = [Int32](repeating: 0, count: c)
      var mask = [Float16](repeating: Self.masked, count: c * p)
      for j in 0..<c {
        let slot = s0 + j
        if slot < n { x[j] = ids[slot] }
        pos[j] = Int32(slot)
        for k in 0...slot { mask[j * p + k] = 0 }
      }
      Self.write(x, to: prefillIDs)
      Self.write(pos, to: prefillPos)
      Self.write([Int32(s0)], to: prefillStart)
      Self.write(mask, to: prefillMask)
      let lp = try Self.logProbs(
        run(prefillModels, prefillInput) {
          ["hidden": $0, "start": self.prefillStart, "mask": self.prefillMask]
        })
      if let from = outputsFrom, max(s, from) < min(n, s0 + c) {
        for slot in max(s, from)..<min(n, s0 + c) {
          rows.append(Array(lp[((slot - s0) * vocabSize)..<((slot - s0 + 1) * vocabSize)]))
        }
      }
      s = s0 + c
    }
    cached = ids
    return rows
  }

  public func logProbs(of continuation: [Int32], after prompt: [Int32]) throws -> [Float]? {
    let room = config.promptSlots - continuation.count
    guard !prompt.isEmpty, !continuation.isEmpty, room >= 2 else { return nil }
    let p = prompt.count > room ? [prompt[0]] + prompt.suffix(room - 1) : prompt
    // rows after the prompt's last token and each continuation token but the last
    let rows = try prefill(p + continuation, outputsFrom: p.count - 1)
    return zip(rows, continuation).map { $0[Int($1)] }
  }

  /// One decode step of all rows; returns (B * V) log-probs.
  private func decode(_ toks: [Int32], position: Int, step: Int, smask: [Float16]) throws -> [Float] {
    let started = Date()
    defer { decodeSeconds += Date().timeIntervalSince(started) }
    decodeSteps += 1
    Self.write(toks, to: decodeTok)
    Self.write([Int32(position)], to: decodePos)
    Self.write(smask, to: decodeSMask)
    let selection = decodeSelections[step]
    return try Self.logProbs(
      run(decodeModels, decodeInputs[step]) {
        [
          "hidden": $0, "wsel": selection.wsel, "keep": selection.keep, "pmask": self.decodePMask,
          "smask": self.decodeSMask,
        ]
      })
  }

  /// Runs `models` (one per chunk, each with its state): the first on `input`, each later one on the previous
  /// one's `hidden` output (`next` builds its inputs).
  private func run(
    _ models: [MLModel], _ input: any MLFeatureProvider, next: (MLMultiArray) -> [String: MLMultiArray]
  ) throws -> any MLFeatureProvider {
    var out = try models[0].prediction(from: input, using: states[0])
    for k in models.indices.dropFirst() {
      guard let hidden = out.featureValue(for: "hidden")?.multiArrayValue else {
        throw GenmaiError.badModel("no hidden output in chunk \(k - 1)")
      }
      out = try models[k].prediction(
        from: try MLDictionaryFeatureProvider(dictionary: next(hidden).mapValues { MLFeatureValue(multiArray: $0) }),
        using: states[k])
    }
    return out
  }

  // MARK: - Beam search

  public func genBatch(
    _ reading: String, contexts: [String], beams b: Int = 5, minRatio: Double = 0, reusePromptKV: Bool = true,
    draft: Bool = false, draftMargin: Float = 2, bound: GenmaiSearchBound? = nil
  ) throws -> [[GenmaiCandidate]] {
    try Task.checkCancellation()
    guard !contexts.isEmpty else { return [] }
    guard b <= config.rows else { throw GenmaiError.badModel("beam width \(b) > \(config.rows) rows") }
    if !reusePromptKV { cached = [] }
    let groupCount = contexts.count
    let maxNew = GenmaiSearch.maxNewTokens(reading)
    let minLen = Int(Double(reading.unicodeScalars.count) * minRatio)
    let draftTokens = contexts.map { draft ? draftStore.tokens(for: $0, maxNew: maxNew) : [] }
    let prompts = zip(contexts, draftTokens).map { context, d in
      var ids = GenmaiPrompt.ids(tokenizer, reading: reading, context: context)
      // BOS + the prompt's tail, so that the prompt and its draft fit into the prompt slots
      let limit = config.promptSlots - d.count
      if ids.count > limit { ids = [ids[0]] + ids.suffix(limit - 1) }
      return ids
    }

    // Draft verification: the longest prefix accepted by every context starts all searches.
    var start = 0
    var prefixScores = [Float](repeating: 0, count: groupCount)
    var firstLogProbs: [[Float]?] = Array(repeating: nil, count: groupCount)
    if draftTokens.contains(where: { !$0.isEmpty }) {
      var sums: [[Float]] = []
      var rows: [[[Float]]] = []
      for g in 0..<groupCount {
        let r = try prefill(prompts[g] + draftTokens[g], outputsFrom: prompts[g].count - 1)
        sums.append(GenmaiDraftStore.accept(draftTokens[g], margin: draftMargin) { Self.top2(r[$0]) })
        rows.append(r)
        try Task.checkCancellation()
      }
      start = sums.map { $0.count - 1 }.min() ?? 0
      for g in 0..<groupCount {
        prefixScores[g] = sums[g][start]
        firstLogProbs[g] = rows[g][start]
      }
      draftTokensAccepted += start * groupCount
    }

    var results: [[GenmaiCandidate]] = []
    var collected: [GenmaiCandidate] = []  // the batch's candidates as full texts (with `bound`)
    for g in 0..<groupCount {
      let offset = bound?.offsets[g] ?? 0
      let floor = bound?.floor(collected) ?? -.infinity
      if offset < floor {  // its continuations score lower still
        results.append([])
        continue
      }
      let res = try search(
        prompt: prompts[g], accepted: Array(draftTokens[g].prefix(start)), firstLogProbs: firstLogProbs[g],
        prefixScore: prefixScores[g], beams: b, maxNew: maxNew, minLen: minLen, offset: offset, floor: floor,
        draftContext: groupCount == 1 ? contexts[0] : nil)
      results.append(res)
      if let bound {
        collected += res.map { GenmaiCandidate(text: bound.prefixes[g] + $0.text, score: offset + $0.score) }
      }
    }
    return results
  }

  /// The best token and log-prob of a row, and the second best log-prob.
  private static func top2(_ row: [Float]) -> (best: (token: Int32, logp: Float), second: Float) {
    var best = (token: Int32(0), logp: -Float.infinity)
    var second = -Float.infinity
    for (i, x) in row.enumerated() {
      if x > best.logp {
        second = best.logp
        best = (Int32(i), x)
      } else if x > second {
        second = x
      }
    }
    return (best, second)
  }

  /// One context's search after `prompt` and the `accepted` draft tokens (`firstLogProbs`: the log-probs after
  /// them if the draft verification computed them). The search stops early once every live row's score + `offset`
  /// is below `floor`. With `draftContext`, its best output becomes the draft of that context (also when
  /// cancelled).
  private func search(
    prompt: [Int32], accepted: [Int32], firstLogProbs: [Float]?, prefixScore: Float, beams b: Int, maxNew: Int,
    minLen: Int, offset: Double, floor: Double, draftContext: String?
  ) throws -> [GenmaiCandidate] {
    let rows = config.rows
    let steps = config.outputSteps
    let start = accepted.count
    let ids = prompt + accepted
    var lp: [Float]
    if let firstLogProbs {
      _ = try prefill(ids)
      lp = firstLogProbs
    } else {
      lp = try prefill(ids, outputsFrom: ids.count - 1)[0]
    }
    Self.write((0..<config.promptSlots).map { $0 < ids.count ? Float16(0) : Self.masked }, to: decodePMask)
    if minLen > 0 && start + 1 < minLen { lp[Int(eos)] = -.infinity }

    var toks = [Int32](repeating: 0, count: rows)
    var scores = [Float](repeating: -.infinity, count: rows)
    for (i, t) in Self.topK(lp, b).enumerated() {
      toks[i] = Int32(t)
      scores[i] = lp[t] + prefixScore
    }
    var seqs: [[Int32]] = toks.map { accepted + [$0] }
    var history: [[Int]] = Array(repeating: [], count: rows)  // output slots of each row's earlier tokens
    var done: [(seq: [Int32], score: Float)] = (0..<b).compactMap { toks[$0] == eos ? (seqs[$0], scores[$0]) : nil }
    defer {
      if let draftContext {
        draftStore.store(draftContext, GenmaiSearch.bestSequence(done: done, seqs: seqs, eos: eos))
      }
    }

    for i in start..<max(start, maxNew - 1) {
      if done.count >= b { break }
      let live = (0..<rows).filter { scores[$0].isFinite && toks[$0] != eos }
      if live.allSatisfy({ offset + Double(scores[$0]) < floor }) { break }
      try Task.checkCancellation()
      let step = i - start
      guard step < steps else { break }  // output slots exhausted
      let base = step * rows
      var smask = [Float16](repeating: Self.masked, count: rows * steps * rows)
      for r in 0..<rows {
        for k in history[r] { smask[r * steps * rows + k] = 0 }
        smask[r * steps * rows + base + r] = 0
      }
      let out = try decode(toks, position: prompt.count + i, step: step, smask: smask)
      let banEOS = i + 2 < minLen
      var best: [(score: Float, index: Int)] = []
      for r in live {
        for v in 0..<vocabSize where !(banEOS && v == Int(eos)) {
          let s = scores[r] + out[r * vocabSize + v]
          if best.count < b || s > best[best.count - 1].score {
            let at = best.firstIndex { s > $0.score } ?? best.count
            best.insert((s, r * vocabSize + v), at: at)
            if best.count > b { best.removeLast() }
          }
        }
      }
      var newToks = [Int32](repeating: 0, count: rows)
      var newScores = [Float](repeating: -.infinity, count: rows)
      var newSeqs: [[Int32]] = Array(repeating: [], count: rows)
      var newHistory: [[Int]] = Array(repeating: [], count: rows)
      for (j, c) in best.enumerated() {
        let src = c.index / vocabSize
        newToks[j] = Int32(c.index % vocabSize)
        newScores[j] = c.score
        newSeqs[j] = seqs[src] + [newToks[j]]
        newHistory[j] = history[src] + [base + src]
      }
      (toks, scores, seqs, history) = (newToks, newScores, newSeqs, newHistory)
      for j in 0..<b where toks[j] == eos && scores[j].isFinite {
        done.append((seqs[j], scores[j]))
      }
    }
    return GenmaiSearch.candidates(
      done: done, seqs: seqs, scores: scores, beams: b, eos: eos, tokenizer: tokenizer)
  }

  /// Indices of the `k` largest values, largest first.
  private static func topK(_ a: [Float], _ k: Int) -> [Int] {
    var best: [Int] = []
    for (i, x) in a.enumerated() where best.count < k || x > a[best[best.count - 1]] {
      let at = best.firstIndex { x > a[$0] } ?? best.count
      best.insert(i, at: at)
      if best.count > k { best.removeLast() }
    }
    return best
  }
}
