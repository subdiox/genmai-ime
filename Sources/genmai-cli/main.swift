// genmai-cli: model installation, conversion, evaluation and diagnostics for GenmaiAI.
//
//   genmai-cli install [--size small|medium] [--tag vX.Y.Z] [destination dir]
//       downloads the newest model release this IME can run (or the given tag) from Hugging Face and installs it
//       like the config dialog does (default: medium, into the IME's model directory)
//   genmai-cli convert [--model DIR] [--context TEXT] [--beams N] <reading>...
//   genmai-cli eval [--model DIR] --tag TAG [--beams 5] [--incremental] [--out-dir DIR] <eval set>...
//       eval sets: anco-format .json (query / answer / left_context) or ime_v1 .jsonl (reading / positives /
//       left_context / id), like the Python evaluator; writes <out-dir>/gen_<TAG>_c40_<name>.json
//       in gen_eval format and prints top-1 accuracy (exact match) and latency (median / p90 / max).
//       --incremental replays the reading one character at a time through GenmaiIncrementalConverter, like
//       the Python evaluator's --incremental: latency is the conversion key only. --every-key also converts the whole
//       prefix after every character (the IME's speculation; "background" = those conversions).
//       --no-kv-reuse disables the prompt KV cache (GenmaiOptions.reusePromptKV); --draft [--draft-margin M] enables
//       draft-and-verify decoding (GenmaiOptions.draft).
//   genmai-cli compare <ours.json> <reference.json>
//       per-item parity: identical top-1 / identical n-best (texts) / max score difference.
//   genmai-cli dict-hints [--data FILE] [--jobs N] <in.jsonl> <out.jsonl>
//       Mozc's conversion and dictionary proper nouns for each reading (AIDictionaryHinter), for training data.
//   genmai-cli session-eval [--timeout-ms N] [--settle none|chunks|idle] [--errors] [--out-dir DIR] <anco set.json>...
//       types the readings through the IME session layer (SessionHandlerBackend) with AI conversion off and on
//       and reports top-1 accuracy and conversion-key latency (see SessionEval.swift).
//   --model DIR (or GENMAI_MODEL_DIR) overrides the default model directory (~/Library/Application Support/Genmai/
//   model, a Core ML model as installed or written by Tools/coreml/genmai_coreml.py); --units ane|cpu|gpu|all picks
//   Core ML's compute units (default ane: CPU and Neural Engine).

import CoreML
import Foundation
import GenmaiAI
import GenmaiBase
import GenmaiClient
import GenmaiCore
import Synchronization

func fail(_ msg: String) -> Never {
  FileHandle.standardError.write(Data((msg + "\n").utf8))
  exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
  fail(
    "usage: genmai-cli install|prepare|quantize|convert|eval|compare|session-eval ... (see Sources/genmai-cli/main.swift)"
  )
}
args.removeFirst()

@MainActor func option(_ name: String) -> String? {
  guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
  let v = args[i + 1]
  args.removeSubrange(i...(i + 1))
  return v
}

@MainActor func flag(_ name: String) -> Bool {
  guard let i = args.firstIndex(of: name) else { return false }
  args.remove(at: i)
  return true
}

@MainActor func modelDirectory() -> URL {
  if let m = option("--model") { return URL(filePath: m) }
  if let e = ProcessInfo.processInfo.environment["GENMAI_MODEL_DIR"] { return URL(filePath: e) }
  return GenmaiConverter.defaultModelDirectory
}

@MainActor func loadConverter() async -> GenmaiConverter {
  let units: MLComputeUnits =
    switch option("--units") ?? "ane" {
    case "cpu": .cpuOnly
    case "gpu": .cpuAndGPU
    case "ane": .cpuAndNeuralEngine
    case "all": .all
    default: fail("--units: cpu, gpu, ane or all")
    }
  let dir = modelDirectory()
  do {
    let c = try await GenmaiConverter(directory: dir, computeUnits: units)
    let t = Date()
    await c.warmup()
    print(
      String(
        format: "model %@: load %.2f s, warmup %.2f s, footprint %.1f MB", dir.path, c.loadSeconds,
        Date().timeIntervalSince(t), physicalFootprintMB().current))
    return c
  } catch {
    fail("cannot load \(dir.path): \(error)")
  }
}

struct EvalItem {
  var query: String
  var answers: [String]
  var context: String
  var id: String
}

/// A JSON string or number as text (the item ids of the evaluation sets are either).
struct JSONScalarText: Decodable, CustomStringConvertible {
  var description: String

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let string = try? container.decode(String.self) {
      description = string
    } else if let int = try? container.decode(Int.self) {
      description = String(int)
    } else {
      description = String(try container.decode(Double.self))
    }
  }
}

/// A line of an AJIMEE-style .jsonl set.
private struct JSONLItem: Decodable {
  var reading: String
  var positives: [String]
  var leftContext: String?
  var id: JSONScalarText

  enum CodingKeys: String, CodingKey {
    case reading, positives, id
    case leftContext = "left_context"
  }
}

/// An item of a .json set.
private struct JSONItem: Decodable {
  var query: String
  var answer: [String]
  var leftContext: String?

  enum CodingKeys: String, CodingKey {
    case query, answer
    case leftContext = "left_context"
  }
}

func loadSet(_ path: String) throws -> [EvalItem] {
  let data = try Data(contentsOf: URL(filePath: path))
  let decoder = JSONDecoder()
  if path.hasSuffix(".jsonl") {
    return try String(decoding: data, as: UTF8.self).split(separator: "\n").map { line in
      let r = try decoder.decode(JSONLItem.self, from: Data(line.utf8))
      return EvalItem(query: r.reading, answers: r.positives, context: r.leftContext ?? "", id: r.id.description)
    }
  }
  return try decoder.decode([JSONItem].self, from: data).map { x in
    EvalItem(query: x.query, answers: x.answer, context: x.leftContext ?? "", id: x.query)
  }
}

/// The result file of `eval` (and of the Python reference): per item its n-best list.
struct EvalResultFile: Decodable {
  struct Output: Decodable {
    var text: String
    var score: Double
  }

  struct Item: Decodable {
    var id: JSONScalarText
    var query: String
    var outputs: [Output]?
    var answers: [String]?
  }

  var items: [Item]
}

func percentile(_ xs: [Double], _ p: Double) -> Double {
  let s = xs.sorted()
  return s[min(s.count - 1, Int(Double(s.count) * p))]
}

func median(_ xs: [Double]) -> Double {
  let s = xs.sorted()
  let n = s.count
  return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
}

func prefix(_ s: String, _ n: Int) -> String {
  String(String.UnicodeScalarView(s.unicodeScalars.prefix(n)))
}

switch command {
case "install":
  let tag = option("--tag")
  guard let size = AIModelSize(rawValue: option("--size") ?? AIModelSize.default.rawValue) else {
    fail("--size must be one of \(AIModelSize.allCases.map(\.rawValue).joined(separator: ", "))")
  }
  let release: GenmaiModelRelease
  do {
    if let tag {
      release = try await GenmaiModelRelease.fetch(repository: size.repository, tag: tag)
    } else {
      release = try await GenmaiModelRelease.latest(repository: size.repository)
    }
  } catch {
    fail("cannot look up the model release: \(error)")
  }
  let dst = args.first.map { URL(filePath: $0) } ?? GenmaiConverter.defaultModelDirectory
  print(
    "installing \(size.modelName) \(release.info.version) (\(release.info.repository)@\(release.info.revision))"
      + " into \(dst.path)")
  let last = Mutex<String>("")
  do {
    let t = Date()
    try await AIModelInstaller.install(release, to: dst) { phase in
      let line: String
      switch phase {
      case .downloading(let received, let total):
        line = String(format: "downloading %.0f%%", Double(received) / Double(max(total, 1)) * 100)
      case .verifying:
        line = "verifying"
      case .installing:
        line = "installing"
      }
      let changed = last.withLock { l in
        defer { l = line }
        return l != line
      }
      if changed { print(line) }
    }
    print(String(format: "installed in %.1f s", Date().timeIntervalSince(t)))
    let c = try await GenmaiConverter(directory: dst)
    print("check:", try await c.convert("きょうはいいてんきですね").first?.text ?? "-")
  } catch {
    fail("install failed: \(error)")
  }

case "convert":
  let ctx = option("--context") ?? ""
  guard let beams = Int(option("--beams") ?? "5") else { fail("--beams needs a number") }
  let c = await loadConverter()
  for reading in args {
    let t = Date()
    let r = try await c.convert(reading, context: ctx, options: GenmaiOptions(beams: beams))
    print(String(format: "%@  (%.0f ms)", reading, Date().timeIntervalSince(t) * 1000))
    for x in r { print(String(format: "  %8.3f  %@", x.score, x.text)) }
  }

case "eval":
  guard let tag = option("--tag") else { fail("eval needs --tag") }
  guard let beams = Int(option("--beams") ?? "5") else { fail("--beams needs a number") }
  let outDir = URL(filePath: option("--out-dir") ?? ".")
  let incremental = flag("--incremental")
  let everyKey = flag("--every-key")
  let c = await loadConverter()
  var opt = GenmaiOptions(beams: beams)
  if flag("--no-kv-reuse") { opt.reusePromptKV = false }
  if let m = option("--draft-margin").flatMap(Float.init) { opt.draftMargin = m }
  if flag("--draft") { opt.draft = true }
  for path in args {
    let name = String(URL(filePath: path).lastPathComponent.split(separator: ".")[0])
    let items: [EvalItem]
    do { items = try loadSet(path) } catch { fail("cannot read \(path): \(error)") }
    var out: [[String: Any]] = []
    var ts: [Double] = []
    var bg: [Double] = []
    var hits = 0
    for x in items {
      let hyps: [GenmaiCandidate]
      let t: Date
      if everyKey {
        // the IME's speculation: the whole composition is converted after every keystroke
        let inc = GenmaiIncrementalConverter(converter: c, context: x.context, options: opt)
        let n = x.query.unicodeScalars.count
        for i in 1..<max(n, 1) {
          let t0 = Date()
          _ = try await inc.convert(prefix(x.query, i))
          bg.append(Date().timeIntervalSince(t0) * 1000)
        }
        t = Date()
        hyps = try await inc.convert(x.query)
      } else if incremental {
        let inc = GenmaiIncrementalConverter(converter: c, context: x.context, options: opt)
        let n = x.query.unicodeScalars.count
        for i in 1..<max(n, 1) {
          let t0 = Date()
          if try await inc.update(prefix(x.query, i)) > 0 {
            bg.append(Date().timeIntervalSince(t0) * 1000)
          }
        }
        t = Date()
        hyps = try await inc.convert(x.query)
      } else {
        t = Date()
        hyps = try await c.convert(x.query, context: x.context, options: opt)
      }
      ts.append(Date().timeIntervalSince(t) * 1000)
      if let top = hyps.first, x.answers.contains(top.text) { hits += 1 }
      out.append([
        "query": x.query, "answers": x.answers, "id": x.id, "latency_ms": ts.last ?? 0,
        "outputs": hyps.map { ["text": $0.text, "score": $0.score] as [String: Any] },
      ])
    }
    let json: [String: Any] = ["n_best": beams, "execution_time": ts.reduce(0, +) / 1000, "items": out]
    let file = outDir.appending(path: "gen_\(tag)_c40_\(name).json")
    try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .withoutEscapingSlashes]).write(to: file)
    print(
      String(
        format: "%@: top1 (exact) %.1f%%  latency median %.0f ms p90 %.0f ms max %.0f ms  (n=%d)",
        name, Double(hits) / Double(items.count) * 100, median(ts), percentile(ts, 0.9), ts.max() ?? 0,
        items.count))
    if !bg.isEmpty {
      print(
        String(
          format: "  background %@ while typing: %d (median %.1f ms, mean %.1f, max %.0f ms)",
          everyKey ? "conversions" : "chunk conversions", bg.count, median(bg),
          bg.reduce(0, +) / Double(bg.count), bg.max() ?? 0))
    }
    let (pre, re) = await c.promptTokenStats
    let (acc, steps) = await c.draftStats
    let fp = physicalFootprintMB()
    print(
      "  so far: prompt tokens prefilled \(pre), reused from the KV cache \(re); output tokens accepted from drafts \(acc), decode steps \(steps)"
    )
    print(String(format: "  footprint %.1f MB (peak %.1f MB)", fp.current, fp.peak))
  }

case "compare":
  guard args.count == 2 else { fail("usage: genmai-cli compare <ours.json> <reference.json>") }
  func items(_ p: String) throws -> [String: [EvalResultFile.Output]] {
    let j = try JSONDecoder().decode(EvalResultFile.self, from: Data(contentsOf: URL(filePath: p)))
    var d: [String: [EvalResultFile.Output]] = [:]
    for x in j.items { d["\(x.id)\u{0}\(x.query)"] = x.outputs }
    return d
  }
  let a = try items(args[0])
  let b = try items(args[1])
  var n = 0
  var top1 = 0
  var all = 0
  var sameSet = 0
  var maxDiff = 0.0
  var diffs: [String] = []
  for (k, ob) in b.sorted(by: { $0.key < $1.key }) {
    guard let oa = a[k] else { continue }
    n += 1
    let ta = oa.map(\.text)
    let tb = ob.map(\.text)
    if ta.first == tb.first { top1 += 1 } else { diffs.append(k) }
    if ta == tb {
      all += 1
      for (x, y) in zip(oa, ob) {
        maxDiff = max(maxDiff, abs(x.score - y.score))
      }
    }
    if Set(ta) == Set(tb) { sameSet += 1 }
  }
  print(
    String(
      format:
        "items %d: top-1 identical %d (%.1f%%), n-best identical %d (%.1f%%), same n-best set %d; max |score diff| on identical lists %.4f",
      n, top1, Double(top1) / Double(max(n, 1)) * 100, all, Double(all) / Double(max(n, 1)) * 100, sameSet, maxDiff))
  for k in diffs.prefix(20) {
    let q = k.split(separator: "\u{0}").last.map(String.init) ?? k
    let fa = (a[k] ?? []).prefix(2).map { "\($0.text) \(String(format: "%.3f", $0.score))" }
    let fb = (b[k] ?? []).prefix(2).map { "\($0.text) \(String(format: "%.3f", $0.score))" }
    print("  \(q)\n    swift:  \(fa)\n    python: \(fb)")
  }

case "propose":
  // propose [--model DIR] [--data FILE] [--weight W] [--proposal-weights W,...] <reading or set.json>...
  // The dictionary's proposals in the AI conversion (AIDictionaryScorer.propose / rerank). For a reading: the
  // model's candidates and the proposals (P) with model score, dictionary cost and score + W × (-cost / 500), the
  // dictionary's best path and the result. For an evaluation set: top-1 accuracy (exact) without proposals and with
  // them for each proposal weight (one-shot conversions, readings of one chunk get proposals as in the IME).
  let dataPath = option("--data") ?? OssDataManager.defaultDataPath
  let weight = option("--weight").flatMap(Double.init) ?? AIConversionSettings.defaultDictionaryWeight
  let proposalWeights = (option("--proposal-weights") ?? "0.2,0.5,1,1.5,2,3").split(separator: ",").compactMap {
    Double($0)
  }
  let scorer: AIDictionaryScorer
  do { scorer = try AIDictionaryScorer(dataManager: try OssDataManager.create(path: dataPath)) } catch {
    fail("cannot load \(dataPath): \(error)")
  }
  let c = await loadConverter()
  // the model's candidates + the unscored proposals, their scores, the proposals
  func candidates(_ reading: String, _ context: String) async throws -> ([String], [Double], [String]) {
    let r = try await c.convert(reading, context: context)
    var texts = r.map(\.text)
    var scores = r.map(\.score)
    guard GenmaiSearch.split(reading, chunk: GenmaiOptions().chunk).count == 1 else { return (texts, scores, []) }
    let proposals = scorer.propose(reading: reading, texts: texts)
    let unscored = proposals.filter { !texts.contains($0) }
    for (t, sc) in zip(unscored, try await c.score(unscored, reading: reading, context: context)) {
      if let sc {
        texts.append(t)
        scores.append(sc)
      }
    }
    return (texts, scores, proposals)
  }
  for arg in args {
    if arg.hasSuffix(".json") || arg.hasSuffix(".jsonl") {
      var hits = [Int](repeating: 0, count: proposalWeights.count + 1)
      var inPool = 0  // the answer among the candidates and proposals (the best any reranking can do)
      let items = try loadSet(arg)
      for x in items {
        let (texts, scores, proposals) = try await candidates(x.query, x.context)
        if texts.contains(where: x.answers.contains) { inPool += 1 }
        for (k, pw) in ([nil] + proposalWeights.map { Optional($0) }).enumerated() {
          let top = scorer.rerank(
            texts, scores: scores, reading: x.query, weight: weight, proposals: pw == nil ? [] : proposals,
            proposalWeight: pw
          ).first
          if let top, x.answers.contains(top) { hits[k] += 1 }
        }
      }
      var line = "\(URL(filePath: arg).lastPathComponent) (\(items.count)): in pool \(inPool), no proposals \(hits[0])"
      for (pw, h) in zip(proposalWeights, hits.dropFirst()) { line += "  p=\(pw) \(h)" }
      print(line)
      continue
    }
    let (texts, scores, proposals) = try await candidates(arg, "")
    let top =
      scorer.rerank(
        texts, scores: scores, reading: arg, weight: weight, proposals: proposals,
        proposalWeight: proposalWeights.first
      ).first ?? ""
    print("\(arg) → \(top)")
    if let path = scorer.bestPath(arg) {
      print("  path: \(path.text), proper nouns: \(path.properNouns.map(\.surface))")
    }
    for (t, sc) in zip(texts, scores) {
      let cost = scorer.cost(t, reading: arg)
      let combined = cost.map { sc - weight * Double($0) / AIDictionaryScorer.costPerNat }
      print(
        String(
          format: "  %@ %8.3f %7@ %8@  %@", proposals.contains(t) ? "P" : " ", sc, cost.map(String.init) ?? "-",
          combined.map { String(format: "%.3f", $0) } ?? "-", t))
    }
  }

case "rescore":
  // rescore [--data FILE] [--weights 0,0.25,...] <gen_*.json>...: top-1 accuracy of the n-best lists of `eval`
  // reordered by AIDictionaryScorer (model score + weight × Mozc's dictionary score) for each weight.
  let dataPath = option("--data") ?? OssDataManager.defaultDataPath
  let weights = (option("--weights") ?? "0,0.1,0.2,0.3,0.5,0.75,1,1.5,2").split(separator: ",").compactMap {
    Double($0)
  }
  let scorer: AIDictionaryScorer
  do { scorer = try AIDictionaryScorer(dataManager: try OssDataManager.create(path: dataPath)) } catch {
    fail("cannot load \(dataPath): \(error)")
  }
  let verbose = flag("--verbose")
  for path in args {
    let file = try JSONDecoder().decode(EvalResultFile.self, from: Data(contentsOf: URL(filePath: path)))
    if verbose, let w = weights.last {
      // the items whose top-1 the reordering changes, with each text's score and dictionary cost
      for x in file.items {
        let outputs = x.outputs ?? []
        let reranked = scorer.rerank(outputs.map(\.text), scores: outputs.map(\.score), reading: x.query, weight: w)
        guard let top = reranked.first, top != outputs.first?.text else { continue }
        let mark = { (t: String) in (x.answers ?? []).contains(t) ? "✓" : "✗" }
        print("\(x.query)  \(mark(outputs.first?.text ?? ""))→\(mark(top))")
        for o in outputs {
          let c = scorer.cost(o.text, reading: x.query).map(String.init) ?? "-"
          print(String(format: "    %7.3f  %6@  %@", o.score, c, o.text))
        }
      }
    }
    var line = URL(filePath: path).lastPathComponent + ":"
    for w in weights {
      var hits = 0
      var changed = 0
      for x in file.items {
        let outputs = x.outputs ?? []
        let texts = outputs.map(\.text)
        let reranked = scorer.rerank(texts, scores: outputs.map(\.score), reading: x.query, weight: w)
        if let top = reranked.first, (x.answers ?? []).contains(top) { hits += 1 }
        if reranked.first != texts.first { changed += 1 }
      }
      line += String(format: "  w=%g %d/%d (%d changed)", w, hits, file.items.count, changed)
    }
    print(line)
  }

case "dict-hints":
  // dict-hints [--data FILE] [--jobs N] <in.jsonl> <out.jsonl>: the dictionary hints (AIDictionaryHinter) of each
  // line's "reading", for training data: {"id", "reading", "h1" (Mozc's conversion), "segments", "proper_nouns"}
  // per line, in input order. Default data set: Data/genmai_extended.data (what the IME bundles).
  let dataPath =
    option("--data")
    ?? URL(filePath: OssDataManager.defaultDataPath).deletingLastPathComponent().appending(path: "genmai_extended.data")
    .path
  let jobs = option("--jobs").flatMap(Int.init) ?? ProcessInfo.processInfo.activeProcessorCount
  guard args.count == 2 else { fail("usage: genmai-cli dict-hints [--data FILE] [--jobs N] <in.jsonl> <out.jsonl>") }
  var rows: [[String: Any]] = []
  for line in try String(contentsOf: URL(filePath: args[0]), encoding: .utf8).split(whereSeparator: \.isNewline) {
    guard let row = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], row["reading"] is String
    else { fail("no \"reading\" in: \(line)") }
    rows.append(row)
  }
  let readings = rows.compactMap { $0["reading"] as? String }
  // a fresh profile: no user dictionary, no learning
  let profile = FileManager.default.temporaryDirectory.appending(path: "genmai-dict-hints-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: profile) }
  SystemUtil.setUserProfileDirectory(profile.path)
  let start = Date()
  let sliceSize = (readings.count + jobs - 1) / max(jobs, 1)
  let slices = stride(from: 0, to: readings.count, by: max(sliceSize, 1)).map {
    Array(readings[$0..<min($0 + sliceSize, readings.count)])
  }
  var hints = [[AIDictionaryHints]](repeating: [], count: slices.count)
  do {
    try await withThrowingTaskGroup(of: (Int, [AIDictionaryHints]).self) { group in
      for (i, slice) in slices.enumerated() {
        group.addTask {
          let dataManager = try OssDataManager.create(path: dataPath)
          let hinter = try AIDictionaryHinter(engine: try Engine.createEngine(dataManager), dataManager: dataManager)
          return (i, slice.map { hinter.hints(reading: $0) })
        }
      }
      for try await (i, h) in group { hints[i] = h }
    }
  } catch {
    fail("cannot load \(dataPath): \(error)")
  }
  var out = Data()
  for (row, h) in zip(rows, hints.joined()) {
    var o: [String: Any] = [
      "reading": row["reading"] ?? "", "h1": h.segments.joined(), "segments": h.segments,
      "proper_nouns": h.properNouns,
    ]
    o["id"] = row["id"]
    out += try JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes])
    out += Data("\n".utf8)
  }
  try out.write(to: URL(filePath: args[1]))
  let seconds = Date().timeIntervalSince(start)
  print(
    String(
      format: "%d readings in %.1f s (%.0f / s, %d jobs) with %@", rows.count, seconds,
      Double(rows.count) / seconds, slices.count, dataPath))

case "session-eval":
  await runSessionEval(args)

default:
  fail("unknown command \(command)")
}
