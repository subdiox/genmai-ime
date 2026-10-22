// The AI conversion hook (not part of Mozc).
//
// GenmaiCore and GenmaiSession stay pure Mozc. The hook is attached from the outside, at two points:
// 1. `AugmentedEngine` wraps the Mozc `Engine` (`EngineInterface`) that `SessionHandler` is created with, and
//    gives every session an `EngineConverter` over an `AugmentingConverter`, a forwarding decorator of Mozc's
//    `ConverterInterface`. `startConversion` (the conversion key) is augmented: after Mozc converted, the AI result
//    (if ready) is merged into Mozc's segments (`AIConversionMerger`). Suggestion / prediction
//    (`startPrediction`, `startPredictionWithPreviousSuggestion`) gets the ready AI conversion of the whole
//    composition as its first candidate (`augmentSuggestion`). Everything else (resize, focus, commit, learning)
//    goes to Mozc unchanged.
// 2. `SessionHandlerBackend.evalCommand` reports every command to the hook (`willEvaluate` / `didEvaluate`): the
//    hook tracks the active session, its left context (IMK surrounding text + the text committed in the
//    session), and starts background pre-conversion of the composition after each keystroke.
// With AI conversion disabled, both points only forward: the IME behaves exactly like Mozc.
//
// Threading: Mozc's evalCommand is synchronous on the main actor and never waits for the model: the model work
// runs on the cooperative pool (the augmenter's actors, speculatively after every keystroke), and the
// conversion key only uses a result that is already there (`ConversionAugmenter.readyResult`). Waiting for a
// result that is still being computed happens *before* the key is evaluated, asynchronously:
// `conversionWait(for:)` returns a task (bounded by the timeout) that the caller awaits before sending the
// conversion key (the input controller queues the key and the keys after it meanwhile; `sendKey(_:via:)` does it
// for in-process clients such as the evaluation and tests). No thread is ever blocked.
//
// The speculative AI conversion of a keystroke usually finishes after Mozc answered that keystroke. To show it in
// the suggestion window anyway, `suggestionUpdate()` returns a task that finishes when the result for the active
// composition arrives; the input controller then re-requests the suggestion for the unchanged composition
// (MOVE_CURSOR to the current cursor position) and updates only the candidate window.

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import Synchronization

public final class AIConversionHook: Sendable {
  /// The left context passed to the model is at most this many characters.
  public static let maxContextLength = 500

  public let augmenter: any ConversionAugmenter

  /// What happened at the last conversion key (diagnostics, self test, evaluation).
  public struct ConversionRecord: Sendable, Equatable {
    public var reading: String
    public var context: String
    public var texts: [String]
    /// Time spent waiting for the AI result before the conversion key was evaluated (`conversionWait`).
    public var waited: Duration
    /// The AI result was not ready at the conversion key (not awaited, or not finished within the timeout).
    public var timedOut: Bool
    public var error: String?
    public var outcome: AIConversionMerger.Outcome
    /// AI candidates dropped by the reading check.
    public var unreadable: [String] = []
  }

  struct SessionState {
    /// Text before the cursor reported by the application (IMK surrounding text), when available.
    var surrounding = ""
    /// Text committed in this session since `surrounding` was taken (or since the field / context was reset).
    var committed = ""
    /// The last composition handed to `prepare`.
    var lastReading = ""
    /// The last AI suggestion shown (`reading` in preedit form → the text on top), kept on screen until the AI
    /// result for the extended composition is ready.
    var lastSuggestion: Suggestion?
  }

  struct Suggestion {
    var reading: String
    var text: String
  }

  struct State {
    var settings = AIConversionSettings()
    var sessions: [UInt64: SessionState] = [:]
    var activeSession: UInt64 = 0
    var pendingSurrounding: String?
    var lastConversion: ConversionRecord?
    /// The AI texts put on top at the last conversion of each session.
    var aiSegments: [UInt64: [AIConversionMerger.Piece]] = [:]
    /// AI texts the user replaced by another candidate (most recent last); not proposed as the top again.
    var rejected: [AIConversionMerger.Piece] = []
    /// The last wait started by `conversionWait`.
    var lastWait: WaitRecord?
  }

  struct WaitRecord {
    var reading: String
    var context: String
    var waited: Duration = .zero
    var error: String?
  }

  /// Number of remembered rejected AI texts.
  static let maxRejected = 1000

  private let state = Mutex(State())

  /// The opt-in debug log (`debug_log` in the settings).
  public let debugLog: AIConversionDebugLog

  struct ReadingCheckState {
    /// The engine's data set (set by `AugmentedEngine`).
    var dataManager: DataManager?
    var checker: AIReadingChecker?
    var task: Task<Void, Never>?
  }

  /// The reading check of AI candidates, built in the background from the engine's system dictionary once AI
  /// conversion is enabled. Until it is ready, candidates are not checked.
  private let readingCheck = Mutex(ReadingCheckState())

  public init(
    augmenter: any ConversionAugmenter, settings: AIConversionSettings = AIConversionSettings(),
    debugLog: AIConversionDebugLog = AIConversionDebugLog()
  ) {
    self.augmenter = augmenter
    self.debugLog = debugLog
    apply(settings)
  }

  // MARK: - Settings

  public var settings: AIConversionSettings { state.withLock { $0.settings } }

  public var isEnabled: Bool { settings.enabled }

  public func apply(_ settings: AIConversionSettings) {
    let s = settings.sanitized
    state.withLock { $0.settings = s }
    debugLog.configure(enabled: s.enabled && s.debugLog)
    augmenter.configure(s)
    startReadingCheckIfNeeded()
  }

  // MARK: - Reading check

  /// The data set whose system dictionary the reading check uses (called by `AugmentedEngine`).
  func attachReadingCheckData(_ dataManager: DataManager) {
    readingCheck.withLock { $0.dataManager = dataManager }
    startReadingCheckIfNeeded()
  }

  private func startReadingCheckIfNeeded() {
    let s = settings
    guard s.enabled, s.readingCheck else { return }
    readingCheck.withLock { r in
      guard r.checker == nil, r.task == nil, let dataManager = r.dataManager else { return }
      r.task = Task.detached { [weak self] in
        let checker: AIReadingChecker?
        do {
          checker = try AIReadingChecker(dataManager: dataManager)
        } catch {
          GenmaiLog.error("AI reading check unavailable: \(error)")
          checker = nil
        }
        self?.readingCheck.withLock { $0.checker = checker }
      }
    }
  }

  /// Waits until the reading check is built (evaluation, tests); returns at once if it is not being built.
  public func waitForReadingCheck() async {
    await readingCheck.withLock { $0.task }?.value
  }

  /// The AI texts in the conversion character form, without empty and duplicate ones, and without those that do
  /// not read as `key` (the conversion key, hiragana) when the reading check is on. `dropped`: the texts the check
  /// removed.
  func candidateTexts(_ raw: [String], key: String, settings: AIConversionSettings) -> (texts: [String], dropped: [String]) {
    let forms = CharacterFormManager.getCharacterFormManager()
    var seen = Set<String>()
    let texts = raw.map { forms.convertConversionString($0) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    guard settings.readingCheck, let checker = readingCheck.withLock({ $0.checker }) else {
      return (texts, [])
    }
    let kept = checker.filter(texts, reading: key)
    return (kept, texts.filter { !kept.contains($0) })
  }

  /// Re-reads `ai_conversion.json` (on the reload notification from GenmaiTool).
  public func reloadSettings() {
    apply(AIConversionSettings.load())
  }

  public var lastConversion: ConversionRecord? { state.withLock { $0.lastConversion } }

  // MARK: - Session tracking (called by SessionHandlerBackend around evalCommand, main actor)

  /// The text before the insertion point of the focused field (up to `maxContextLength` characters), read by
  /// the input controller at the start of a composition. Applies to the session of the next command.
  public func noteSurroundingText(_ text: String) {
    state.withLock { $0.pendingSurrounding = text }
  }

  public func willEvaluate(_ input: Input) {
    switch input.type {
    case .sendKey, .testSendKey, .sendCommand:
      break
    default:
      // CREATE_SESSION (sent lazily right before the first key), server commands, ...
      return
    }
    state.withLock { s in
      s.activeSession = input.id
      var session = s.sessions[input.id] ?? SessionState()
      if input.type == .sendCommand && input.command.type == .resetContext {
        session = SessionState()
      }
      if let pending = s.pendingSurrounding {
        s.pendingSurrounding = nil
        session.surrounding = Self.suffix(pending)
        session.committed = ""
      } else if input.hasContext && input.context.hasPrecedingText {
        // Clients without the extended surrounding text (Mozc's own 20-character preceding_text).
        let preceding = input.context.precedingText
        let current = session.surrounding + session.committed
        if preceding.isEmpty {
          session = SessionState(lastReading: session.lastReading)
        } else if !current.hasSuffix(preceding) {
          session.surrounding = Self.suffix(preceding)
          session.committed = ""
        }
      }
      s.sessions[input.id] = session
    }
  }

  public func didEvaluate(_ input: Input, _ output: Output?) {
    let sessionID = input.type == .createSession ? (output?.id ?? input.id) : input.id
    if input.type == .deleteSession {
      _ = state.withLock { $0.sessions.removeValue(forKey: sessionID) }
      return
    }
    guard let output else { return }
    let prepareRequest: (String, String)? = state.withLock { s in
      var prepareRequest: (String, String)?
      var session = s.sessions[sessionID] ?? SessionState()
      if output.hasResult && !output.result.value.isEmpty {
        session.committed = Self.suffix(session.committed + output.result.value)
      }
      let reading = Self.compositionReading(output)
      if reading.isEmpty {
        session.lastReading = ""
        session.lastSuggestion = nil
      } else if reading != session.lastReading {
        session.lastReading = reading
        if s.settings.enabled {
          prepareRequest = (reading, Self.suffix(session.surrounding + session.committed))
        }
      }
      s.sessions[sessionID] = session
      return prepareRequest
    }
    if let (reading, context) = prepareRequest, augmenter.isReady {
      augmenter.prepare(reading: reading, context: context)
    }
  }

  /// The left context of `sessionID` (the active session by default).
  public func context(for sessionID: UInt64? = nil) -> String {
    state.withLock { s in
      let session = s.sessions[sessionID ?? s.activeSession] ?? SessionState()
      return Self.suffix(session.surrounding + session.committed)
    }
  }

  static func suffix(_ text: String) -> String {
    text.count <= maxContextLength ? text : String(text.suffix(maxContextLength))
  }

  /// The hiragana of a composition (no conversion in progress), without the pending romaji at its end; "" while
  /// converting / predicting or when there is no preedit.
  static func isRomajiLetter(_ s: Unicode.Scalar) -> Bool {
    switch s.value {
    case 0x41...0x5A, 0x61...0x7A, 0xFF21...0xFF3A, 0xFF41...0xFF5A: true
    default: false
    }
  }

  static func compositionReading(_ output: Output) -> String {
    guard output.hasPreedit, !output.preedit.segment.isEmpty,
      !output.preedit.segment.contains(where: { $0.annotation == .highlight })
    else {
      return ""
    }
    var text = output.preedit.segment.map(\.value).joined()
    // Romaji still being typed: pending Latin letters (full-width in the default preedit form: かいｓ).
    var pending = ""
    while let last = text.unicodeScalars.last, isRomajiLetter(last) {
      pending.unicodeScalars.insert(text.unicodeScalars.removeLast(), at: pending.unicodeScalars.startIndex)
    }
    // A pending "n" is converted as ん by the conversion key (Mozc's conversion query): speculate on that.
    if (pending == "n" || pending == "ｎ") && !text.isEmpty {
      text += "ん"
    }
    return text
  }

  // MARK: - Conversion (called by AugmentingConverter inside evalCommand)

  /// Waits for the AI conversion of the segments Mozc just made and merges it into them.
  func augmentConversion(_ request: ConversionRequest, _ segments: Segments, _ converter: any ConverterInterface) {
    let settings = self.settings
    guard settings.enabled, request.requestType() == .conversion, segments.conversionSegmentsSize > 0,
      augmenter.isReady
    else {
      return
    }
    let key = (0..<segments.conversionSegmentsSize).map { segments.conversionSegment($0).key }.joined()
    // The model reads the composition as displayed (preedit character form: "？", "（", as in its training
    // data; also what `prepare` saw) and its output gets Mozc's conversion character form, like Mozc's own
    // candidates (VariantsRewriter).
    let reading = CharacterFormManager.getCharacterFormManager().convertPreeditString(key)
    let context = conversionContext(segments)
    // Never wait here (main thread): a result still in flight was awaited before this key (`conversionWait`).
    let ready = augmenter.readyResult(reading: reading, context: context, maxResults: settings.candidateCount)
    // The wait (if any) that `conversionWait` did for this key; used once.
    let wait = state.withLock { s in
      defer { s.lastWait = nil }
      return s.lastWait.flatMap { $0.reading == reading && $0.context == context ? $0 : nil }
    }
    var record = ConversionRecord(
      reading: reading, context: context, texts: [], waited: wait?.waited ?? .zero, timedOut: false,
      error: nil, outcome: AIConversionMerger.Outcome())
    switch ready {
    case nil:
      if let error = wait?.error {
        record.error = error
      } else {
        record.timedOut = true
      }
    case let raw?:
      let (texts, dropped) = candidateTexts(raw, key: key, settings: settings)
      record.texts = texts
      record.unreadable = dropped
      let rejected = Set(state.withLock { $0.rejected })
      record.outcome = AIConversionMerger.apply(
        texts, to: segments, request: request, converter: converter, maxCandidates: settings.candidateCount,
        rejected: { rejected.contains($0) })
    }
    let finished = record
    state.withLock {
      $0.lastConversion = finished
      $0.aiSegments[$0.activeSession] = finished.outcome.aiSegments
    }
    if debugLog.isEnabled {
      let source: AIConversionDebugLog.Source =
        record.error != nil ? .error : record.timedOut ? .timeout : wait != nil ? .awaited : .ready
      let info = augmenter.resultInfo(reading: reading, context: context)
      var note = "waited=\(Int(AIConversionDebugLog.milliseconds(record.waited)))ms"
      if let info { note += info.exact ? " exact" : " draft" }
      if record.outcome.keptLearned > 0 { note += " keptLearned=\(record.outcome.keptLearned)" }
      if record.outcome.keptUserWords > 0 { note += " keptUserWords=\(record.outcome.keptUserWords)" }
      if !record.unreadable.isEmpty { note += " unreadable=\(record.unreadable)" }
      if let error = record.error { note += " error=\(error)" }
      note += " segments=" + (0..<segments.conversionSegmentsSize).map { segments.conversionSegment($0).key }
        .joined(separator: "|")
      debugLog.write(
        AIConversionDebugLog.Event(
          source: source, reading: reading, context: context, latency: info?.latency ?? record.waited,
          texts: record.texts, shown: Self.topValue(segments), note: note))
    }
  }

  /// The left context of a conversion: the session's (surrounding text + committed text), else Mozc's history.
  func conversionContext(_ segments: Segments) -> String {
    let context = self.context()
    return context.isEmpty ? Self.suffix(segments.historyValue()) : context
  }

  /// The joined top candidates of the conversion segments (what the preedit shows).
  static func topValue(_ segments: Segments) -> String {
    (0..<segments.conversionSegmentsSize).map {
      let segment = segments.conversionSegment($0)
      return segment.candidatesSize > 0 ? segment.candidate(0).value : segment.key
    }.joined()
  }

  // MARK: - Suggestion (called by AugmentingConverter inside evalCommand)

  /// Puts what the conversion key would show now (Mozc's conversion of the composition with the ready AI result
  /// merged, exactly as `augmentConversion` does it) first in Mozc's suggestion / prediction (marked "AI" unless it
  /// already was Mozc's first suggestion), so that
  /// the suggestion window shows the AI result while typing and SPACE gives the same text. Nothing changes when
  /// the AI result for the composition is not ready, for partial suggestion / prediction (cursor inside the
  /// composition) and for multi-segment results. Costs one Mozc conversion (a few ms) when a result is ready.
  func augmentSuggestion(_ request: ConversionRequest, _ segments: Segments, _ converter: any ConverterInterface) {
    let type = request.requestType()
    guard type == .suggestion || type == .prediction, segments.conversionSegmentsSize == 1, augmenter.isReady
    else {
      return
    }
    let settings = self.settings
    guard settings.enabled else { return }
    // The conversion key converts the composition's conversion query (not the prediction query, which drops a
    // pending romaji consonant); without a ready result for it there is nothing the conversion key would show.
    let key = request.composer().getQueryForConversion()
    let forms = CharacterFormManager.getCharacterFormManager()
    let reading = forms.convertPreeditString(key)
    guard !reading.isEmpty else { return }
    let context = conversionContext(segments)
    guard let raw = augmenter.readyResult(reading: reading, context: context, maxResults: settings.candidateCount)
    else {
      keepLastSuggestion(reading: reading, context: context, segments)
      return
    }
    let (texts, dropped) = candidateTexts(raw, key: key, settings: settings)
    guard !texts.isEmpty else { return }
    var options = ConversionRequest.Options()
    options.enableUserHistoryForConversion = request.options().enableUserHistoryForConversion
    options.requestType = .conversion
    let conversionRequest = ConversionRequestBuilder().setConversionRequestView(request).setOptions(options)
      .setKey(key).build()
    let conversion = segments.copy()
    conversion.clearConversionSegments()
    guard converter.startConversion(conversionRequest, conversion), conversion.conversionSegmentsSize > 0 else {
      return
    }
    let rejected = Set(state.withLock { $0.rejected })
    let outcome = AIConversionMerger.apply(
      texts, to: conversion, request: conversionRequest, converter: converter,
      maxCandidates: settings.candidateCount, rejected: { rejected.contains($0) })
    let shown = Self.topValue(conversion)
    state.withLock { s in
      s.sessions[s.activeSession]?.lastSuggestion = Suggestion(reading: reading, text: shown)
    }
    let segment = segments.mutableConversionSegment(0)
    let engineTop = segment.candidatesSize > 0 ? segment.candidate(0).value : ""
    if shown != engineTop {
      // Marked like the conversion's AI candidates (not when Mozc's suggestion already agrees); committing it
      // teaches Mozc like a user choice.
      AIConversionMerger.promote(shown, in: segment, to: 0)
      segment.mutableCandidate(0).attributes |= Attribute.reranked
    }
    if debugLog.isEnabled {
      let info = augmenter.resultInfo(reading: reading, context: context)
      var note = type == .suggestion ? "suggestion" : "prediction"
      if shown == engineTop { note += " same-as-engine-suggestion" }
      if outcome.keptLearned > 0 { note += " keptLearned=\(outcome.keptLearned)" }
      if outcome.keptUserWords > 0 { note += " keptUserWords=\(outcome.keptUserWords)" }
      if !dropped.isEmpty { note += " unreadable=\(dropped)" }
      debugLog.write(
        AIConversionDebugLog.Event(
          source: info?.exact == true ? .refine : .suggestion, reading: reading, context: context,
          latency: info?.latency, texts: texts, shown: shown, note: note))
    }
  }

  /// Until the AI result for `reading` is ready (it arrives 30-60 ms after the keystroke, then the input
  /// controller refreshes the suggestion), the last AI suggestion stays on top, extended by the kana typed since
  /// (母は歯を折っ + た), so that the AI row does not disappear and come back on every keystroke. It reads as the
  /// whole composition, so selecting it commits a complete text. Nothing is shown after deleting characters.
  private func keepLastSuggestion(reading: String, context: String, _ segments: Segments) {
    guard let last = state.withLock({ s in s.sessions[s.activeSession]?.lastSuggestion }),
      reading.hasPrefix(last.reading)
    else {
      return
    }
    let text = last.text + reading.dropFirst(last.reading.count)
    let segment = segments.mutableConversionSegment(0)
    let engineTop = segment.candidatesSize > 0 ? segment.candidate(0).value : ""
    if text != engineTop {
      AIConversionMerger.promote(text, in: segment, to: 0)
    }
    if debugLog.isEnabled {
      debugLog.write(
        AIConversionDebugLog.Event(
          source: .suggestion, reading: reading, context: context, latency: nil, texts: [], shown: text,
          note: "kept from \(last.reading)"))
    }
  }

  /// If the AI result for the active session's composition is still being computed (or refined), a task that
  /// finishes when it is there: true if the suggestion should be re-requested (a new top-1). nil when AI
  /// conversion is off or nothing is in flight. The caller checks that the composition did not change meanwhile.
  public func suggestionUpdate() -> Task<Bool, Never>? {
    guard augmenter.isReady else { return nil }
    let request: (String, String)? = state.withLock { s in
      guard s.settings.enabled, let session = s.sessions[s.activeSession], !session.lastReading.isEmpty else {
        return nil
      }
      return (session.lastReading, Self.suffix(session.surrounding + session.committed))
    }
    guard let (reading, context) = request else { return nil }
    return augmenter.resultUpdate(reading: reading, context: context)
  }

  /// Called before Mozc finishes (commits) a conversion: an AI text the user replaced is remembered, so that
  /// the AI does not override the user's choice (which Mozc learns) next time.
  func willFinishConversion(_ segments: Segments) {
    var committed: [String: String] = [:]
    for i in 0..<segments.conversionSegmentsSize {
      let segment = segments.conversionSegment(i)
      if segment.candidatesSize > 0 {
        committed[segment.key] = segment.candidate(0).value
      }
    }
    let values = committed
    state.withLock { s in
      guard let pieces = s.aiSegments.removeValue(forKey: s.activeSession), !pieces.isEmpty else { return }
      for piece in pieces {
        guard let value = values[piece.key] else { continue }
        s.rejected.removeAll { $0 == piece }
        if value != piece.value {
          s.rejected.append(piece)
          if s.rejected.count > Self.maxRejected {
            s.rejected.removeFirst(s.rejected.count - Self.maxRejected)
          }
        }
      }
    }
  }

  // MARK: - Waiting for an AI result in flight (before the conversion key is evaluated)

  /// Keys that start a conversion during composition (Mozc's default keymaps): SPACE and HENKAN without
  /// modifiers.
  static func isConversionKey(_ key: KeyEvent) -> Bool {
    key.hasSpecialKey && (key.specialKey == .space || key.specialKey == .henkan) && key.modifierKeys.isEmpty
      && !key.hasKeyCode
  }

  /// If `key` will convert the active session's composition and the AI result for it is not ready yet, a task
  /// that finishes when the result is ready or after `timeout_ms` (whichever comes first). The caller awaits it
  /// and then evaluates the key, which picks the result up without waiting. nil: evaluate the key right away.
  public func conversionWait(for key: KeyEvent) -> Task<Void, Never>? {
    guard Self.isConversionKey(key), augmenter.isReady else { return nil }
    let request: (String, String, AIConversionSettings)? = state.withLock { s in
      guard s.settings.enabled, let session = s.sessions[s.activeSession], !session.lastReading.isEmpty else {
        return nil
      }
      return (session.lastReading, Self.suffix(session.surrounding + session.committed), s.settings)
    }
    guard let (reading, context, settings) = request,
      augmenter.readyResult(reading: reading, context: context, maxResults: settings.candidateCount) == nil
    else { return nil }
    let augmenter = self.augmenter
    return Task.detached { [weak self] in
      let start = ContinuousClock.now
      // The first of: the result (or its error), the timeout. On timeout the conversion is cancelled but not
      // awaited (it stops at its next decode step; a long prefill cannot be interrupted).
      enum Event { case done(String?), timeout }
      let (events, sink) = AsyncStream<Event>.makeStream()
      let work = Task.detached {
        do {
          _ = try await augmenter.convert(reading: reading, context: context, maxResults: settings.candidateCount)
          sink.yield(.done(nil))
        } catch {
          sink.yield(.done("\(error)"))
        }
      }
      let timer = Task.detached {
        try? await Task.sleep(for: settings.timeout)
        sink.yield(.timeout)
      }
      var error: String?
      for await event in events {
        if case .done(let e) = event {
          error = e
        } else {
          work.cancel()
        }
        break
      }
      timer.cancel()
      sink.finish()
      let record = WaitRecord(reading: reading, context: context, waited: ContinuousClock.now - start, error: error)
      self?.state.withLock { $0.lastWait = record }
    }
  }

  /// Sends `key` through `client`, awaiting the AI result first if `key` is a conversion key whose result is
  /// still in flight (in-process clients: evaluation, self test, tests; the input controller queues keys itself).
  @MainActor
  public func sendKey(_ key: KeyEvent, context: Context? = nil, via client: any GenmaiClientProtocol) async -> Output? {
    if let wait = conversionWait(for: key) {
      await wait.value
    }
    return client.sendKey(key, context: context)
  }
}

// MARK: - Engine / converter decorators

/// Forwards every `EngineInterface` call to the Mozc engine; session converters get the AI hook.
public final class AugmentedEngine: EngineInterface {
  public let base: any EngineInterface
  private let converterProvider: () -> any ConverterInterface
  public let hook: AIConversionHook

  /// `engine`: the Mozc engine. Its converter is wrapped in `AugmentingConverter` for every new session.
  public init(_ engine: Engine, hook: AIConversionHook) {
    base = engine
    converterProvider = { engine.getConverter() }
    self.hook = hook
    if let dataManager = engine.getDataManager() {
      hook.attachReadingCheckData(dataManager)
    }
  }

  public func createEngineConverter() -> any EngineConverterInterface {
    EngineConverter(AugmentingConverter(converterProvider(), hook: hook))
  }

  public func getDataVersion() -> String { base.getDataVersion() }
  public func reload() -> Bool { base.reload() }
  public func sync() -> Bool { base.sync() }
  public func wait() async -> Bool { await base.wait() }
  public func reloadAndWait() async -> Bool { await base.reloadAndWait() }
  public func clearUserHistory() -> Bool { base.clearUserHistory() }
  public func clearUserPrediction() -> Bool { base.clearUserPrediction() }
  public func addUserHistory(_ key: String, _ value: String) -> Bool { base.addUserHistory(key, value) }
  public func getPosList() -> [String] { base.getPosList() }
  public func maybeReloadEngine(_ response: inout Genmai_EngineReloadResponse) -> Bool {
    base.maybeReloadEngine(&response)
  }
  public func clearOldSupplementalModels() { base.clearOldSupplementalModels() }
  public func sendEngineReloadRequest(_ request: Genmai_EngineReloadRequest) -> Bool {
    base.sendEngineReloadRequest(request)
  }
  public func sendSupplementalModelReloadRequest(_ request: Genmai_EngineReloadRequest) -> Bool {
    base.sendSupplementalModelReloadRequest(request)
  }
}

/// Mozc's converter plus the AI hook on `startConversion` (conversion key) and `startPrediction` (suggestion).
public final class AugmentingConverter: ConverterInterface {
  public let base: any ConverterInterface
  let hook: AIConversionHook

  public init(_ base: any ConverterInterface, hook: AIConversionHook) {
    self.base = base
    self.hook = hook
  }

  public func startConversion(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    guard base.startConversion(request, segments) else {
      return false
    }
    hook.augmentConversion(request, segments, base)
    return true
  }

  public func startReverseConversion(_ segments: Segments, _ key: String) -> Bool {
    base.startReverseConversion(segments, key)
  }
  public func startPrediction(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    let result = base.startPrediction(request, segments)
    if result {
      hook.augmentSuggestion(request, segments, base)
    }
    return result
  }
  public func startPredictionWithPreviousSuggestion(
    _ request: ConversionRequest, _ previousSegment: Segment, _ segments: Segments
  ) -> Bool {
    let result = base.startPredictionWithPreviousSuggestion(request, previousSegment, segments)
    if result {
      hook.augmentSuggestion(request, segments, base)
    }
    return result
  }
  public func prependCandidates(_ request: ConversionRequest, _ segment: Segment, _ segments: Segments) {
    base.prependCandidates(request, segment, segments)
  }
  public func finishConversion(_ request: ConversionRequest, _ segments: Segments) {
    hook.willFinishConversion(segments)
    base.finishConversion(request, segments)
  }
  public func cancelConversion(_ segments: Segments) { base.cancelConversion(segments) }
  public func resetConversion(_ segments: Segments) { base.resetConversion(segments) }
  public func revertConversion(_ segments: Segments) { base.revertConversion(segments) }
  public func deleteCandidateFromHistory(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int)
    -> Bool
  {
    base.deleteCandidateFromHistory(segments, segmentIndex, candidateIndex)
  }
  public func reconstructHistory(_ segments: Segments, _ precedingText: String) -> Bool {
    base.reconstructHistory(segments, precedingText)
  }
  public func commitSegmentValue(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int) -> Bool {
    base.commitSegmentValue(segments, segmentIndex, candidateIndex)
  }
  public func commitPartialSuggestionSegmentValue(
    _ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int, _ currentSegmentKey: String,
    _ newSegmentKey: String
  ) -> Bool {
    base.commitPartialSuggestionSegmentValue(
      segments, segmentIndex, candidateIndex, currentSegmentKey, newSegmentKey)
  }
  public func focusSegmentValue(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int) -> Bool {
    base.focusSegmentValue(segments, segmentIndex, candidateIndex)
  }
  public func commitSegments(_ segments: Segments, _ candidateIndex: [Int]) -> Bool {
    base.commitSegments(segments, candidateIndex)
  }
  public func resizeSegment(
    _ segments: Segments, _ request: ConversionRequest, _ segmentIndex: Int, _ offsetLength: Int
  ) -> Bool {
    base.resizeSegment(segments, request, segmentIndex, offsetLength)
  }
  public func resizeSegments(
    _ segments: Segments, _ request: ConversionRequest, _ startSegmentIndex: Int, _ newSizeArray: [UInt8]
  ) -> Bool {
    base.resizeSegments(segments, request, startSegmentIndex, newSizeArray)
  }
  public func commitContext(_ request: ConversionRequest) { base.commitContext(request) }
}
