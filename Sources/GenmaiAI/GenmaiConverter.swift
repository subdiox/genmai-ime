// Concurrency-safe entry points of the genmai converter: `GenmaiConverter` (an actor owning the decoder: the MLX
// model or the Core ML model) and `GenmaiIncrementalConverter` (port of the Python reference
// `IncrementalConverter`).

import CoreML
import Foundation
import MLX
import Synchronization

/// The genmai converter. All decoder work happens on this actor (MLX arrays and Core ML states are not Sendable).
/// Loading takes about a second, so create it off the main actor (e.g. in a detached task). Every conversion
/// method checks for task cancellation between decode steps and throws `CancellationError`.
public actor GenmaiConverter {
  /// MLX evaluates on a process-wide default stream that must not be used from two threads at once. Every
  /// converter (there may briefly be two, e.g. while a model is reloaded or in tests) takes this lock around
  /// its MLX work; each operation is synchronous, so the lock is never held across a suspension point. Core ML
  /// converters take it too, so that `busyStats` counts their work the same way.
  static let mlxLock = Mutex(())

  /// Total time spent doing MLX work (inside `mlxLock`) by all converters of the process, and the number of
  /// operations (diagnostics: background cost per keystroke in `genmai-cli session-eval`).
  public struct BusyStats: Sendable, Equatable {
    public var seconds: Double = 0
    public var operations: Int = 0
  }

  private static let busy = Mutex(BusyStats())
  /// Whether an MLX model was ever loaded: until then MLX (and Metal) stay untouched, so that a process running the
  /// Core ML model does not pay for them.
  private static let mlxUsed = Atomic(false)

  public static var busyStats: BusyStats { busy.withLock { $0 } }

  /// Runs `body` while holding `mlxLock` and adds its duration to `busyStats`.
  static func withMLX<T>(_ body: () throws -> T) rethrows -> T {
    try mlxLock.withLock { _ in
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

  private let model: any GenmaiDecoder
  public nonisolated let loadSeconds: Double
  /// Bytes of the MLX model's weights in memory (0 for Core ML).
  public nonisolated let weightBytes: Int
  /// Bits per weight of the MLX model's quantized linear layers; nil for bf16 weights and Core ML.
  public nonisolated let quantizationBits: Int?
  public nonisolated let tokenizer: GenmaiTokenizer
  /// Whether the decoder is the MLX model (MLX's buffer cache and the diagnostics below apply).
  public nonisolated let usesMLX: Bool

  /// The directory the IME loads the model from: `~/Library/Application Support/Genmai/model`
  /// (installed by the config dialog, `genmai-cli install` or Tools/prepare_genmai_model.sh).
  public static var defaultModelDirectory: URL {
    URL.applicationSupportDirectory.appending(path: "Genmai/model", directoryHint: .isDirectory)
  }

  public init(directory: URL = GenmaiConverter.defaultModelDirectory) throws {
    Self.mlxUsed.store(true, ordering: .relaxed)
    let m = try Self.mlxLock.withLock { _ in try GenmaiModel(directory: directory) }
    model = m
    loadSeconds = m.loadSeconds
    weightBytes = m.weightBytes
    quantizationBits = m.quantizationBits
    tokenizer = m.tokenizer
    usesMLX = true
  }

  /// Loads the Core ML model in `coreMLDirectory` (`GenmaiCoreMLModel`). The first load on a Mac compiles the
  /// model for the Neural Engine (seconds); the system caches that.
  public init(coreMLDirectory: URL, computeUnits: MLComputeUnits = .cpuAndNeuralEngine) async throws {
    let m = try await GenmaiCoreMLModel.load(directory: coreMLDirectory, computeUnits: computeUnits)
    model = m
    loadSeconds = m.loadSeconds
    weightBytes = 0
    quantizationBits = nil
    tokenizer = m.tokenizer
    usesMLX = false
  }

  /// Loads the model in `directory`: the Core ML model if it has `genmai_coreml.json`, else the MLX model.
  public static func load(directory: URL) async throws -> GenmaiConverter {
    if FileManager.default.fileExists(atPath: directory.appending(path: GenmaiCoreMLModel.configFileName).path) {
      return try await GenmaiConverter(coreMLDirectory: directory)
    }
    return try GenmaiConverter(directory: directory)
  }

  /// Pre-compiles the common decode steps of the MLX model (a few hundred ms), or runs one conversion on Core ML,
  /// so that the first conversion is fast.
  public func warmup() {
    Self.withMLX {
      if let m = model as? GenmaiModel {
        m.warmup()
      } else {
        _ = try? model.convert("きょうはいいてんきですね", context: "あ")
      }
    }
  }

  /// Converts `reading` (hiragana) after `context` (left context; the last 500 characters are used).
  /// Returns up to `options.beams` candidates, best first; `score` is the total log-probability.
  public func convert(_ reading: String, context: String = "", options: GenmaiOptions = .init()) throws
    -> [GenmaiCandidate]
  {
    try Self.withMLX { try model.convert(reading, context: context, options: options) }
  }

  /// Diagnostics: see `GenmaiModel.debugLogProbs` (MLX only; empty on Core ML).
  public func debugLogProbs(_ reading: String, context: String = "", continuation: [Int32] = []) -> [[Float]] {
    Self.withMLX {
      (model as? GenmaiModel)?.debugLogProbs(reading, context: context, continuation: continuation) ?? []
    }
  }

  /// Beam across one chunk (see `GenmaiDecoder.extend`).
  public func extend(_ hyps: [GenmaiCandidate], part: String, context: String = "", options: GenmaiOptions = .init())
    throws -> [GenmaiCandidate]
  {
    try Self.withMLX { try model.extend(hyps, part: part, context: context, options: options) }
  }

  /// One beam search per left context (see `GenmaiDecoder.genBatch`).
  public func genBatch(
    _ reading: String, contexts: [String], beams: Int = 5, minRatio: Double = 0,
    reusePromptKV: Bool = true, draft: Bool = false, draftMargin: Float = 2
  ) throws
    -> [[GenmaiCandidate]]
  {
    try Self.withMLX {
      try model.genBatch(
        reading, contexts: contexts, beams: beams, minRatio: minRatio, reusePromptKV: reusePromptKV,
        draft: draft, draftMargin: draftMargin, bound: nil)
    }
  }

  /// Output tokens accepted from drafts / decode steps run so far (diagnostics).
  public var draftStats: (accepted: Int, decodeSteps: Int) {
    (model.draftTokensAccepted, model.decodeSteps)
  }

  /// MLX memory of the process: arrays in use, the buffer cache, the peak of arrays in use and the cache limit
  /// (diagnostics). MLX trims the cache to the limit at its next allocation.
  public static var memoryStats: (active: Int, cache: Int, peak: Int, cacheLimit: Int) {
    (Memory.activeMemory, Memory.cacheMemory, Memory.peakMemory, Memory.cacheLimit)
  }

  /// Returns MLX's cached buffers to the system (the input method calls this when typing has paused for a
  /// while); the model, the prompt KV cache and the drafts stay. Returns the cache size right after (0). Nothing
  /// to do on Core ML.
  @discardableResult
  public func releaseCachedMemory() -> Int {
    guard usesMLX else { return 0 }
    return Self.withMLX {
      Memory.clearCache()
      return Memory.cacheMemory
    }
  }

  /// Returns MLX's cached buffers to the system when no converter needs them any more (AI conversion turned
  /// off, or another model loaded: the buffers of the released model end up in the cache). Nothing to do if MLX
  /// was never used.
  public static func releaseUnusedMemory() {
    guard mlxUsed.load(ordering: .relaxed) else { return }
    withMLX { Memory.clearCache() }
  }

  /// Drops the prompt KV cache and the drafts of the model (tests).
  public func clearPromptCache() {
    Self.withMLX { model.clearPromptCache() }
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
    let all = GenmaiModel.split(reading, chunk: options.chunk)
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
      let all = GenmaiModel.split(reading, chunk: options.chunk)
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
