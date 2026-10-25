// The genmai beam search. A decoder (`GenmaiCoreMLModel`, Core ML on the Neural Engine) implements `genBatch` (one
// beam search per left context, with drafts and prompt KV reuse) and `logProbs`; the chunked conversion on top of
// it (`gen`, `extend`, `convert`), scoring a given text, the drafts and how a search ends are shared (a port of the
// Python reference decoder of the training code).

import Foundation

/// Lets a decoder stop the searches of an `extend` early (searches decoded one after another, not as one batch):
/// context g continues the hypothesis (`prefixes[g]`, score `offsets[g]`), and only the best `keep` distinct texts
/// of the whole batch are kept. Log-probs only decrease, so once `keep` texts are found, a search whose rows are all
/// below the last of them cannot add anything; the kept candidates are the same as without the bound.
public struct GenmaiSearchBound: Sendable {
  public var prefixes: [String]
  public var offsets: [Double]
  public var keep: Int

  public init(prefixes: [String], offsets: [Double], keep: Int) {
    self.prefixes = prefixes
    self.offsets = offsets
    self.keep = keep
  }

  /// The score of the `keep`-th best distinct text among `candidates` (full texts and scores), -inf while there are
  /// fewer: a candidate below it is not among the best `keep`.
  public func floor(_ candidates: [GenmaiCandidate]) -> Double {
    let kept = GenmaiSearch.best(candidates, keep)
    return kept.count < keep ? -.infinity : kept[keep - 1].score
  }
}

/// A genmai decoder: the model behind `GenmaiConverter`. Not Sendable; used from one actor at a time.
public protocol GenmaiDecoder: AnyObject {
  var tokenizer: GenmaiTokenizer { get }
  /// Seconds spent loading the model.
  var loadSeconds: Double { get }
  /// Diagnostics: output tokens accepted from drafts, decode steps, prompt tokens prefilled / reused.
  var draftTokensAccepted: Int { get }
  var decodeSteps: Int { get }
  var promptTokensPrefilled: Int { get }
  var promptTokensReused: Int { get }

  /// Independent beam searches for one reading under several left contexts. Returns, per context, the candidates
  /// (text, sum log-prob) best first; with `bound`, a context's list may miss candidates that cannot be among the
  /// best `bound.keep` of the batch. Throws `CancellationError` (checked between decode steps).
  ///
  /// Shared semantics (`GenmaiSearch`): max_new = 1.3 * reading + 8; prompts longer than the decoder's limit keep
  /// BOS + their tail; with `minRatio`, EOS is forbidden until the output has `minRatio * reading` tokens; with
  /// `draft`, the draft of each context (`GenmaiDraftStore`) is verified after its prompt and the longest prefix
  /// accepted by every context (`GenmaiDraftStore.accept`) starts all searches; a search stops once `beams`
  /// hypotheses ended; a single-context search stores its best output as the draft of its context (also when
  /// cancelled).
  func genBatch(
    _ reading: String, contexts: [String], beams: Int, minRatio: Double, reusePromptKV: Bool, draft: Bool,
    draftMargin: Float, bound: GenmaiSearchBound?
  ) throws -> [[GenmaiCandidate]]

  /// The log-prob of each token of `continuation` after `prompt` (prompt ids from `GenmaiPrompt.ids`); nil if they do
  /// not fit into the decoder's prompt (a long prompt keeps BOS + its tail first).
  func logProbs(of continuation: [Int32], after prompt: [Int32]) throws -> [Float]?

  /// Drops the prompt KV cache and the drafts (tests, memory pressure).
  func clearPromptCache()
}

extension GenmaiDecoder {
  public func gen(_ reading: String, context: String = "", beams: Int = 5, minRatio: Double = 0) throws
    -> [GenmaiCandidate]
  {
    try genBatch(
      reading, contexts: [context], beams: beams, minRatio: minRatio, reusePromptKV: true, draft: false,
      draftMargin: 2, bound: nil)[0]
  }

  /// Beam across one chunk: decode `part` after every hypothesis and keep the best `beams`.
  public func extend(_ hyps: [GenmaiCandidate], part: String, context: String = "", options: GenmaiOptions = .init())
    throws -> [GenmaiCandidate]
  {
    let outs = try genBatch(
      part, contexts: hyps.map { context + $0.text },
      beams: hyps.count == 1 ? options.beams : options.chunkBeams, minRatio: options.minRatio,
      reusePromptKV: options.reusePromptKV, draft: options.draft, draftMargin: options.draftMargin,
      bound: GenmaiSearchBound(prefixes: hyps.map(\.text), offsets: hyps.map(\.score), keep: options.beams))
    var next: [GenmaiCandidate] = []
    for (h, o) in zip(hyps, outs) {
      for c in o { next.append(GenmaiCandidate(text: h.text + c.text, score: h.score + c.score)) }
    }
    return GenmaiSearch.best(next, options.beams)
  }

  /// The model's score of `text` as the output for `reading` after `context`, as a candidate's score (sum of the
  /// log-probs of its tokens and EOS); nil if it does not fit. For a reading of one chunk (`split`).
  public func score(_ text: String, reading: String, context: String = "") throws -> Double? {
    let prompt = GenmaiPrompt.ids(tokenizer, reading: reading, context: context)
    guard let lps = try logProbs(of: tokenizer.encode(text) + [tokenizer.eosTokenID], after: prompt) else {
      return nil
    }
    return lps.reduce(0) { $0 + Double($1) }
  }

  /// Converts `reading` (hiragana) after the left `context`; long readings are split at punctuation and the
  /// beam continues across chunks. Best first.
  public func convert(_ reading: String, context: String = "", options: GenmaiOptions = .init()) throws
    -> [GenmaiCandidate]
  {
    var hyps = [GenmaiCandidate(text: "", score: 0)]
    for c in GenmaiSearch.split(reading, chunk: options.chunk) {
      hyps = try extend(hyps, part: c, context: context, options: options)
    }
    return hyps
  }
}

/// Helpers of the shared beam search.
public enum GenmaiSearch {
  /// Python `list.sort` is stable; Swift's `sort` is not guaranteed to be.
  static func stableSorted<T>(_ a: [T], by less: (T, T) -> Bool) -> [T] {
    a.enumerated().sorted { x, y in
      if less(x.element, y.element) { return true }
      if less(y.element, x.element) { return false }
      return x.offset < y.offset
    }.map(\.element)
  }

  /// gen_eval --chunk splitting: punctuation-ended parts merged greedily up to `chunk` characters. When the
  /// reading only grows, every group but the last is final (see `GenmaiIncrementalConverter`).
  public static func split(_ reading: String, chunk: Int = 40) -> [String] {
    let u = Array(reading.unicodeScalars)
    if chunk <= 0 || u.count <= chunk { return [reading] }
    let punct: Set<Unicode.Scalar> = ["、", "。", "，", "．", "！", "？", "!", "?"]
    var raw: [[Unicode.Scalar]] = []
    var cur: [Unicode.Scalar] = []
    for c in u {
      cur.append(c)
      if punct.contains(c) {
        raw.append(cur)
        cur = []
      }
    }
    if !cur.isEmpty { raw.append(cur) }
    var parts: [[Unicode.Scalar]] = []
    for p in raw {
      if let last = parts.last, last.count + p.count <= chunk {
        parts[parts.count - 1] += p
      } else {
        parts.append(p)
      }
    }
    return parts.map { String(String.UnicodeScalarView($0)) }
  }

  /// The best `count` candidates with distinct texts (stable for equal scores).
  public static func best(_ candidates: [GenmaiCandidate], _ count: Int) -> [GenmaiCandidate] {
    var seen = Set<String>()
    return Array(
      stableSorted(candidates) { $0.score > $1.score }.filter { seen.insert($0.text).inserted }
        .prefix(count))
  }

  /// The output tokens a search may produce for a reading.
  public static func maxNewTokens(_ reading: String) -> Int {
    Int(Double(reading.unicodeScalars.count) * 1.3) + 8
  }

  /// One search's candidates: the ended hypotheses (and, if fewer than `beams` ended, the live ones), best first,
  /// at most `beams`, texts cut at the first newline, duplicates dropped.
  static func candidates(
    done: [(seq: [Int32], score: Float)], seqs: [[Int32]], scores: [Float], beams b: Int, eos: Int32,
    tokenizer: GenmaiTokenizer
  ) -> [GenmaiCandidate] {
    var all = done
    if all.count < b {
      for j in 0..<b where seqs[j].last != eos && scores[j].isFinite {
        all.append((seqs[j], scores[j]))
      }
    }
    var res: [GenmaiCandidate] = []
    var seen = Set<String>()
    for (sq, sc) in stableSorted(all, by: { $0.score > $1.score }).prefix(b) {
      var t = tokenizer.decode(sq.filter { $0 != eos })
      if let nl = t.firstIndex(of: "\n") { t = String(t[..<nl]) }
      if seen.insert(t).inserted {
        res.append(GenmaiCandidate(text: t, score: Double(sc)))
      }
    }
    return res
  }

  /// The best output of a search: its best ended hypothesis, else its first row.
  static func bestSequence(done: [(seq: [Int32], score: Float)], seqs: [[Int32]], eos: Int32) -> [Int32] {
    (stableSorted(done) { $0.score > $1.score }.first?.seq ?? seqs.first ?? []).filter { $0 != eos }
  }
}

/// The drafts of draft-and-verify decoding: the best output of recent searches, keyed by their left context (most
/// recent last).
struct GenmaiDraftStore {
  static let maxDrafts = 16
  /// Draft tokens verified per search at most.
  static let maxDraftTokens = 128

  private var drafts: [(context: String, tokens: [Int32])] = []

  /// The draft for a search after `context` producing at most `maxNew` tokens.
  func tokens(for context: String, maxNew: Int) -> [Int32] {
    Array((drafts.last { $0.context == context }?.tokens ?? []).prefix(min(Self.maxDraftTokens, maxNew - 2)))
  }

  mutating func store(_ context: String, _ tokens: [Int32]) {
    drafts.removeAll { $0.context == context }
    guard !tokens.isEmpty else { return }
    drafts.append((context, tokens))
    if drafts.count > Self.maxDrafts {
      drafts.removeFirst(drafts.count - Self.maxDrafts)
    }
  }

  mutating func clear() {
    drafts = []
  }

  /// Verifies `draft` against the log-probs after the prompt and after each draft token (`top2(a)`: the two best
  /// tokens after the first a draft tokens): a token is accepted while it is the argmax by at least `margin`.
  /// Returns the running log-prob sums: element a = sum of the first a accepted tokens' log-probs (count =
  /// accepted + 1).
  static func accept(
    _ draft: [Int32], margin: Float, top2: (Int) -> (best: (token: Int32, logp: Float), second: Float)
  ) -> [Float] {
    var sums: [Float] = [0]
    while sums.count - 1 < draft.count {
      let a = sums.count - 1
      let t = top2(a)
      guard t.best.token == draft[a], t.best.logp - t.second >= margin else { break }
      sums.append(sums[a] + t.best.logp)
    }
    return sums
  }
}
