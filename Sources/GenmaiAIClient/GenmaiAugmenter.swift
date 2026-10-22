// The genmai model as the IME's `ConversionAugmenter` (not part of Mozc).
//
// Loads `GenmaiConverter` in the background when AI conversion is enabled, keeps one
// `GenmaiIncrementalConverter` per left context (a few recent ones), pre-converts the finished chunks of the
// composition and speculatively converts the whole composition after every keystroke (`prepare`; latest wins),
// so that the conversion key (`convert`) finds its result ready or in flight.

import Foundation
import GenmaiAI
import GenmaiClient
import Synchronization

public final class GenmaiAugmenter: ConversionAugmenter {
  /// Number of recent left contexts whose incremental state is kept.
  static let maxIncrementalStates = 4
  /// Number of recent speculative results kept (backspace, retyping).
  static let maxCachedResults = 8

  struct State {
    var status: AIConversionStatus = .disabled
    var directory: URL?
    /// `AIModelStatus.identity` of the loaded weights: a model replaced by the installer is loaded again.
    var modelIdentity: String?
    var options = GenmaiOptions()
    var generation = 0
    var loadTask: Task<Void, Never>?
    /// Pre-conversion of the finished chunks of the composition.
    var prepare: Preparation?
    /// The latest speculative conversion of the whole composition.
    var speculation: Speculation?
    /// Finished speculative conversions, most recent last.
    var cache: [Cached] = []
    var lastSource: ConvertSource?

    mutating func cancelAll() {
      prepare?.task.cancel()
      prepare = nil
      speculation?.cancel()
      speculation = nil
      cache = []
    }

    func cached(_ reading: String, _ context: String) -> [String]? {
      entry(reading, context)?.texts
    }

    func entry(_ reading: String, _ context: String) -> Cached? {
      cache.last { $0.reading == reading && $0.context == context }
    }
  }

  struct Preparation {
    var context: String
    /// The groups that are final for the reading it was started for.
    var groups: [String]
    var task: Task<Void, Never>
  }

  struct Speculation {
    var reading: String
    var context: String
    /// The fast conversion (draft-and-verify; nil when cancelled or failed).
    var task: Task<[String]?, Never>
    /// The exact conversion that replaces its result in the cache when the user pauses (n-best not tied to the
    /// draft prefix).
    var refine: Task<Void, Never>

    func cancel() {
      task.cancel()
      refine.cancel()
    }
  }

  struct Cached {
    var reading: String
    var context: String
    var texts: [String]
    /// Model time of the conversion.
    var latency: Duration
    /// The exact conversion (refine), not the draft-and-verify speculation.
    var exact: Bool
  }

  /// Where the result of the last `convert` came from (diagnostics, evaluation).
  public enum ConvertSource: String, Sendable {
    /// The speculative conversion had already finished: no model work at the conversion key.
    case ready
    /// The speculative conversion of this reading was running and was awaited.
    case awaited
    /// Converted at the conversion key.
    case converted
    /// Not awaited (the key was evaluated without waiting) and not ready: Mozc's result was used (evaluation).
    case notReady = "not-ready"
  }

  public var lastConvertSource: ConvertSource? { state.withLock { $0.lastSource } }

  /// Typing pause after which the fast speculative result is replaced by an exact conversion.
  static let refineDelay: Duration = .milliseconds(400)
  /// Candidates kept by a speculative conversion.
  static let speculationResults = 10

  private let state = Mutex(State())
  private let core = Core()

  public init() {}

  public var status: AIConversionStatus { state.withLock { $0.status } }

  /// Seconds the last model load took (load + warm-up), for diagnostics.
  public var lastLoadSeconds: Double { loadSecondsValue.withLock { $0 } }
  private let loadSecondsValue = Mutex(0.0)

  public func configure(_ settings: AIConversionSettings) {
    let directory = settings.resolvedModelDirectory
    let identity = AIModelStatus.identity(directory)
    let options = GenmaiOptions(beams: max(5, settings.candidateCount))
    let core = self.core
    state.withLock { s in
      if !settings.enabled {
        guard s.status != .disabled else { return }
        s.generation += 1
        s.loadTask?.cancel()
        s.loadTask = nil
        s.cancelAll()
        s.status = .disabled
        s.directory = nil
        s.modelIdentity = nil
        Task.detached { await core.unload() }
        return
      }
      if s.directory == directory, s.modelIdentity == identity, s.options == options,
        s.status == .ready || s.status == .loading
      {
        return
      }
      s.generation += 1
      let generation = s.generation
      s.loadTask?.cancel()
      s.cancelAll()
      s.directory = directory
      s.modelIdentity = identity
      s.options = options
      s.status = .loading
      s.loadTask = Task.detached { [weak self] in
        let start = Date()
        let result: AIConversionStatus
        do {
          try await core.load(directory: directory, options: options)
          result = .ready
        } catch {
          result = .failed("\(error)")
        }
        guard let self else { return }
        self.loadSecondsValue.withLock { $0 = Date().timeIntervalSince(start) }
        self.state.withLock { s in
          if s.generation == generation {
            s.status = result
          }
        }
      }
    }
  }

  /// Waits until a load started by `configure` has finished (tests, the self test, evaluation).
  public func waitUntilLoaded() async {
    let task = state.withLock { $0.loadTask }
    await task?.value
  }

  /// Called after every composition change. Two kinds of background work:
  /// - the finished chunks (all groups but the last, see `GenmaiIncrementalConverter`) are pre-converted; this
  ///   work stays valid while the user keeps typing, so it is only cancelled when an edit changes those groups;
  /// - the whole composition is converted speculatively right away (latest wins: the previous speculation is
  ///   cancelled, which stops it at its next decode step, and the new one starts once it has unwound, so at
  ///   most one runs and one waits). Finished results are cached, so the conversion key usually finds its
  ///   result ready or in flight.
  public func prepare(reading: String, context: String) {
    state.withLock { s in
      guard s.status == .ready else { return }
      startSpeculation(&s, reading: reading, context: context)
    }
  }

  /// Starts (or keeps) the chunk pre-conversion and the speculation for `reading`; returns the speculation task,
  /// nil if the result is cached.
  @discardableResult
  private func startSpeculation(_ s: inout State, reading: String, context: String) -> Task<[String]?, Never>? {
    let core = self.core
    // chunk pre-conversion
    let groups = Array(GenmaiModel.split(reading, chunk: s.options.chunk).dropLast())
    if let p = s.prepare, p.context == context, groups.starts(with: p.groups) {
      if p.groups != groups {
        let previous = p.task
        s.prepare = Preparation(
          context: context, groups: groups,
          task: Task.detached {
            await previous.value
            guard !Task.isCancelled else { return }
            _ = try? await core.prepare(reading: reading, context: context)
          })
      }
    } else {
      let previous = s.prepare?.task
      previous?.cancel()
      s.prepare = Preparation(
        context: context, groups: groups,
        task: Task.detached {
          await previous?.value
          guard !Task.isCancelled else { return }
          _ = try? await core.prepare(reading: reading, context: context)
        })
    }
    // speculation of the whole composition
    if s.cached(reading, context) != nil {
      if let sp = s.speculation, sp.reading != reading || sp.context != context {
        sp.cancel()
      }
      return nil
    }
    if let sp = s.speculation, sp.reading == reading, sp.context == context {
      return sp.task
    }
    let previous = s.speculation
    previous?.cancel()
    let chunks = s.prepare?.task
    let generation = s.generation
    let store: @Sendable ([String], Duration, Bool) -> Void = { [weak self] texts, latency, exact in
      self?.state.withLock { s in
        guard s.generation == generation else { return }
        s.cache.removeAll { $0.reading == reading && $0.context == context }
        s.cache.append(Cached(reading: reading, context: context, texts: texts, latency: latency, exact: exact))
        if s.cache.count > GenmaiAugmenter.maxCachedResults {
          s.cache.removeFirst(s.cache.count - GenmaiAugmenter.maxCachedResults)
        }
      }
    }
    let task = Task.detached { () -> [String]? in
      // a cancelled job unwinds within one decode step
      _ = await previous?.task.value
      await previous?.refine.value
      guard !Task.isCancelled else { return nil }
      await chunks?.value  // the finished chunks are shared, convert them once
      guard !Task.isCancelled else { return nil }
      let start = ContinuousClock.now
      guard
        let texts = try? await core.convert(
          reading: reading, context: context, maxResults: GenmaiAugmenter.speculationResults, draft: true)
      else { return nil }
      store(texts, ContinuousClock.now - start, false)
      return texts
    }
    let refine = Task.detached {
      guard await task.value != nil, !Task.isCancelled else { return }
      // only once typing pauses (a keystroke cancels this)
      do { try await Task.sleep(for: GenmaiAugmenter.refineDelay) } catch { return }
      let start = ContinuousClock.now
      if let texts = try? await core.convert(
        reading: reading, context: context, maxResults: GenmaiAugmenter.speculationResults, draft: false)
      {
        store(texts, ContinuousClock.now - start, true)
      }
    }
    s.speculation = Speculation(reading: reading, context: context, task: task, refine: refine)
    return task
  }

  /// Waits for the background work started by the last `prepare` (evaluation): the pre-conversion of the
  /// finished chunks, and with `speculation` also the speculative conversion of the whole composition.
  public func waitForPreparation(speculation: Bool = false) async {
    let (prepare, spec) = state.withLock { ($0.prepare?.task, $0.speculation) }
    await prepare?.value
    if speculation {
      _ = await spec?.task.value
      await spec?.refine.value
    }
  }

  public func readyResult(reading: String, context: String, maxResults: Int) -> [String]? {
    state.withLock { s in
      guard s.status == .ready else { return nil }
      return s.cached(reading, context).map { Array($0.prefix(maxResults)) }
    }
  }

  public func resultUpdate(reading: String, context: String) -> Task<Bool, Never>? {
    state.withLock { s -> Task<Bool, Never>? in
      guard s.status == .ready, let sp = s.speculation, sp.reading == reading, sp.context == context else {
        return nil
      }
      let before = s.entry(reading, context)
      if before?.exact == true {
        return nil  // refined already: nothing more will come
      }
      let work: Task<Void, Never>
      if before == nil {
        let task = sp.task
        work = Task.detached { _ = await task.value }
      } else {
        work = sp.refine
      }
      let previousTop = before?.texts.first
      return Task.detached { [weak self] in
        await work.value
        guard let self else { return false }
        let top = self.state.withLock { $0.cached(reading, context)?.first }
        return top != nil && top != previousTop
      }
    }
  }

  public func resultInfo(reading: String, context: String) -> AIResultInfo? {
    state.withLock { s in s.entry(reading, context).map { AIResultInfo(latency: $0.latency, exact: $0.exact) } }
  }

  public func convert(reading: String, context: String, maxResults: Int) async throws -> [String] {
    enum Plan {
      case cached([String])
      case await(Task<[String]?, Never>)
      case notReady
    }
    let plan: Plan = state.withLock { s in
      guard s.status == .ready else { return .notReady }
      if let texts = s.cached(reading, context) {
        s.lastSource = .ready
        return .cached(texts)
      }
      if let sp = s.speculation, sp.reading == reading, sp.context == context {
        s.lastSource = .awaited
        return .await(sp.task)
      }
      // Not prepared (e.g. the last keystroke's reading differs): convert now, through the same latest-wins
      // chain so that stale work is cancelled first.
      s.lastSource = .converted
      guard let task = startSpeculation(&s, reading: reading, context: context) else {
        return .cached(s.cached(reading, context) ?? [])
      }
      return .await(task)
    }
    switch plan {
    case .cached(let texts):
      return Array(texts.prefix(maxResults))
    case .await(let task):
      let texts = await withTaskCancellationHandler {
        await task.value
      } onCancel: {
        task.cancel()
      }
      if let texts {
        return Array(texts.prefix(maxResults))
      }
    case .notReady:
      break
    }
    // The speculation was cancelled (a newer composition) or failed: convert directly.
    try Task.checkCancellation()
    return try await core.convert(reading: reading, context: context, maxResults: maxResults)
  }

  /// The model owner.
  actor Core {
    private var converter: GenmaiConverter?
    private var options = GenmaiOptions()
    private var incrementals: [(context: String, converter: GenmaiIncrementalConverter)] = []

    func load(directory: URL, options: GenmaiOptions) async throws {
      converter = nil
      incrementals = []
      let c = try GenmaiConverter(directory: directory)
      try Task.checkCancellation()
      await c.warmup()
      try Task.checkCancellation()
      converter = c
      self.options = options
    }

    func unload() {
      converter = nil
      incrementals = []
    }

    private func incremental(_ context: String) throws -> GenmaiIncrementalConverter {
      guard let converter else {
        throw CancellationError()
      }
      if let i = incrementals.firstIndex(where: { $0.context == context }) {
        let entry = incrementals.remove(at: i)
        incrementals.append(entry)
        return entry.converter
      }
      let created = GenmaiIncrementalConverter(converter: converter, context: context, options: options)
      incrementals.append((context, created))
      if incrementals.count > GenmaiAugmenter.maxIncrementalStates {
        incrementals.removeFirst()
      }
      return created
    }

    func prepare(reading: String, context: String) async throws {
      try await incremental(context).update(reading)
    }

    func convert(reading: String, context: String, maxResults: Int, draft: Bool = false) async throws -> [String] {
      var fast = options
      fast.draft = true
      let candidates = try await incremental(context).convert(reading, lastGroup: draft ? fast : nil)
      var seen = Set<String>()
      return candidates.map(\.text).filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(maxResults).map { $0 }
    }
  }
}

extension AIConversionHook {
  /// The IME's hook: the genmai augmenter with the settings from `ai_conversion.json`.
  public static func makeGenmai(settings: AIConversionSettings = AIConversionSettings.load()) -> AIConversionHook {
    AIConversionHook(augmenter: GenmaiAugmenter(), settings: settings)
  }

  /// The genmai augmenter of a hook made by `makeGenmai`.
  public var genmai: GenmaiAugmenter? { augmenter as? GenmaiAugmenter }
}
