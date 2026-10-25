// Concurrency-safe entry points of the genmai converter: `GenmaiConverter` (an actor owning the Core ML decoder,
// `GenmaiCoreMLModel`) and `GenmaiIncrementalConverter` (port of the Python reference `IncrementalConverter`).

import CoreML
import Foundation
import Synchronization

/// The genmai converter. All decoder work happens on this actor (Core ML states are not Sendable). Loading takes
/// about a second (the first load after an installation compiles the model for the Neural Engine, ~20 s), so create
/// it off the main actor (e.g. in a detached task). Every conversion method checks for task cancellation between
/// decode steps and throws `CancellationError`.
public actor GenmaiConverter {
  /// Serializes the decoder work of all converters of the process (there may briefly be two, e.g. while a model is
  /// reloaded or in tests) and measures it; each operation is synchronous, so the lock is never held across a
  /// suspension point.
  static let workLock = Mutex(())

  /// Total time spent in decoder work (inside `workLock`) by all converters of the process, and the number of
  /// operations (diagnostics: background cost per keystroke in `genmai-cli session-eval`).
  public struct BusyStats: Sendable, Equatable {
    public var seconds: Double = 0
    public var operations: Int = 0
  }

  private static let busy = Mutex(BusyStats())

  public static var busyStats: BusyStats { busy.withLock { $0 } }

  /// Runs `body` while holding `workLock` and adds its duration to `busyStats`.
  static func measured<T>(_ body: () throws -> T) rethrows -> T {
    try workLock.withLock { _ in
      let start = ContinuousClock.now
      defer {
        let (s, a) = (ContinuousClock.now - start).components
        let d = Double(s) + Double(a) / 1e18
        busy.withLock {
          $0.seconds += d
          $0.operations += 1
        }
      }
      return try body()
    }
  }

  private let model: GenmaiCoreMLModel
  public nonisolated let loadSeconds: Double
  public nonisolated let tokenizer: GenmaiTokenizer

  /// Loads the Core ML model in `directory` (`GenmaiCoreMLModel`). The first load on a Mac compiles the model for
  /// the Neural Engine; the system caches that.
  public init(
    directory: URL, computeUnits: MLComputeUnits = .cpuAndNeuralEngine
  )
    async throws
  {
    let m = try await GenmaiCoreMLModel.load(directory: directory, computeUnits: computeUnits)
    model = m
    loadSeconds = m.loadSeconds
    tokenizer = m.tokenizer
  }

  /// Runs one conversion, so that the first conversion the user waits for is fast.
  public func warmup() {
    Self.measured { _ = try? model.convert("きょうはいいてんきですね", context: "あ") }
  }

  /// Converts `reading` (hiragana) after `context` (left context; the last 500 characters are used).
  /// Returns up to `options.beams` candidates, best first; `score` is the total log-probability.
  public func convert(_ reading: String, context: String = "", options: GenmaiOptions = .init()) throws
    -> [GenmaiCandidate]
  {
    try Self.measured { try model.convert(reading, context: context, options: options) }
  }

  /// The model's scores of `texts` as outputs for `reading` (one chunk) after `context` (see `GenmaiCoreMLModel.score`);
  /// nil for a text that does not fit.
  public func score(_ texts: [String], reading: String, context: String = "") throws -> [Double?] {
    try Self.measured { try texts.map { try model.score($0, reading: reading, context: context) } }
  }

  /// Beam across one chunk (see `GenmaiCoreMLModel.extend`).
  public func extend(_ hyps: [GenmaiCandidate], part: String, context: String = "", options: GenmaiOptions = .init())
    throws -> [GenmaiCandidate]
  {
    try Self.measured { try model.extend(hyps, part: part, context: context, options: options) }
  }

  /// One beam search per left context (see `GenmaiCoreMLModel.genBatch`).
  public func genBatch(
    _ reading: String, contexts: [String], beams: Int = 5, minRatio: Double = 0,
    reusePromptKV: Bool = true, draft: Bool = false, draftMargin: Float = 2
  ) throws
    -> [[GenmaiCandidate]]
  {
    try Self.measured {
      try model.genBatch(
        reading, contexts: contexts, beams: beams, minRatio: minRatio, reusePromptKV: reusePromptKV,
        draft: draft, draftMargin: draftMargin, bound: nil)
    }
  }

  /// Output tokens accepted from drafts / decode steps run so far (diagnostics).
  public var draftStats: (accepted: Int, decodeSteps: Int) {
    (model.draftTokensAccepted, model.decodeSteps)
  }

  /// Drops the prompt KV cache and the drafts of the model (tests).
  public func clearPromptCache() {
    Self.measured { model.clearPromptCache() }
  }

  /// Prompt tokens prefilled / taken from the prompt KV cache so far (diagnostics).
  public var promptTokenStats: (prefilled: Int, reused: Int) {
    (model.promptTokensPrefilled, model.promptTokensReused)
  }
}

/// Converts finished chunks while the user is still typing, so that the conversion key only has to decode the
/// last chunk. Results are identical to `GenmaiConverter.convert` on the final reading: with left-to-right greedy
/// grouping, every group except the last can no longer change once a later group has started.
///
/// Call `update(_:)` after each keystroke (from a background task; cancel it when the next keystroke arrives —
/// already converted groups are kept) and `convert(_:)` on the conversion key. Edits that change an already
/// converted group drop the cached state from that group on. The left context is fixed per instance (one
/// instance per composition).
public actor GenmaiIncrementalConverter {
  public let converter: GenmaiConverter
  public let context: String
  public let options: GenmaiOptions
  private var groups: [String] = []
  /// states[k] = hypotheses after the first k groups.
  private var states: [[GenmaiCandidate]] = [[GenmaiCandidate(text: "", score: 0)]]
  /// Bumped whenever `groups` / `states` are truncated, so that an `update` resumed after a suspension does not
  /// append a state computed from a stale prefix (actor reentrancy).
  private var generation = 0

  public init(converter: GenmaiConverter, context: String = "", options: GenmaiOptions = .init()) {
    self.converter = converter
    self.context = context
    self.options = options
  }

  /// Number of groups converted so far.
  public var convertedGroups: Int { groups.count }

  private func sync(_ final: [String]) {
    var k = 0
    while k < groups.count && k < final.count && groups[k] == final[k] { k += 1 }
    if k < groups.count {
      groups.removeSubrange(k...)
      states.removeSubrange((k + 1)...)
      generation += 1
    }
  }

  /// Converts every group that is final for this reading and not converted yet; returns the number done.
  @discardableResult
  public func update(_ reading: String) async throws -> Int {
    let all = GenmaiSearch.split(reading, chunk: options.chunk)
    let final = Array(all.dropLast())
    sync(final)
    var n = 0
    while groups.count < final.count {
      let k = groups.count
      let g = final[k]
      let gen = generation
      let next = try await converter.extend(states[k], part: g, context: context, options: options)
      // another call may have changed the state while this one was suspended
      guard gen == generation, groups.count == k else { return n }
      states.append(next)
      groups.append(g)
      n += 1
    }
    return n
  }

  /// The conversion of the full `reading` (converts any pending final groups first). `lastGroup` overrides the
  /// options of the last group's search (e.g. draft-and-verify for a speculative conversion while typing; the
  /// final groups always use `options`).
  public func convert(_ reading: String, lastGroup: GenmaiOptions? = nil) async throws -> [GenmaiCandidate] {
    while true {
      try await update(reading)
      let all = GenmaiSearch.split(reading, chunk: options.chunk)
      let k = all.count - 1
      guard groups.count == k, Array(all.prefix(k)) == groups else { continue }
      let last = lastGroup ?? options
      // A draft (speculative) search continues only the best hypothesis of the earlier groups: with all of
      // them it decodes beams × beams rows (~1 s for a 40-character chunk after a 500-character context).
      let hyps = last.draft ? Array(states[k].prefix(1)) : states[k]
      return try await converter.extend(hyps, part: all[k], context: context, options: last)
    }
  }
}
