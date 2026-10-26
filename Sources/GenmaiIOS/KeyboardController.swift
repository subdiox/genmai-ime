// Not in Mozc (the Gboard client is not open source): the keyboard extension's client of `IosEngine`.
//
// It turns key presses into engine calls and applies each `commands::Output` to the text field, like the IMK
// input controller does on macOS: the result is committed, the preedit becomes the field's marked text, keys the
// engine did not consume get their default action (delete, newline, space, cursor movement), and the candidates
// (`all_candidate_words`, the mobile candidate list) are published for the candidate bar. A key of a toggle table
// that leaves the preedit toggleable keeps toggling until another key: as on the iOS kana keyboard there is no
// timeout, and "→" (`advance`) sends STOP_KEY_TOGGLING (`maybeCreateNewChunk`) so that the next tap on the same key
// starts a new character.
//
// AI conversion (the engine's `AIConversionHook`, as on macOS): a conversion key whose AI result is still in flight
// waits for it (`conversionWait`, bounded by the timeout) before it is sent, and the keys typed meanwhile follow in
// order; a result that arrives after the candidates were shown refreshes them (MOVE_CURSOR to the end re-runs the
// suggestion, `suggestionUpdate`).
//
// UIKit stays outside: the text field is a `KeyboardTextDocument` (UITextDocumentProxy in the extension, a fake
// in tests), so this file builds and is tested on macOS.

import Foundation
import GenmaiBase
import GenmaiClient
import GenmaiCore
import GenmaiProtocol
import Observation

/// The text field the keyboard types into (the subset of UITextDocumentProxy the keyboard uses).
@MainActor
public protocol KeyboardTextDocument: AnyObject {
  func insertText(_ text: String)
  func deleteBackward()
  /// Replaces the marked text (or inserts it at the cursor); `selectedRange` is in UTF-16 units of `text`.
  func setMarkedText(_ text: String, selectedRange: NSRange)
  /// Fixes the marked text as ordinary text.
  func unmarkText()
  func adjustTextPosition(byCharacterOffset offset: Int)
  /// The text before the cursor (nil if unknown), the left context of the AI conversion.
  var precedingText: String? { get }
}

/// A candidate of the candidate bar.
public struct KeyboardCandidate: Identifiable, Equatable, Sendable {
  /// The candidate id for SUBMIT_CANDIDATE.
  public let id: Int32
  public let value: String
  /// The annotation's description ("[全]カタカナ", ...); "" if none.
  public let description: String
}

@MainActor
@Observable
public final class KeyboardController {

  public private(set) var settings: KeyboardSettings
  public private(set) var inputMode: IosEngine.InputMode = .hiragana
  /// The preedit (composition or conversion) shown as marked text.
  public private(set) var preedit = ""
  public private(set) var candidates: [KeyboardCandidate] = []
  /// The highlighted candidate during conversion.
  public private(set) var focusedCandidateID: Int32?
  /// Shift of the QWERTY alphabet keys (one letter).
  public private(set) var isShifted = false
  /// The key (its text) whose kana the next tap of the same key toggles: the system keyboard keeps it highlighted
  /// until the toggle ends (never with flick only, where nothing toggles).
  public private(set) var togglingKey: String?

  @ObservationIgnored public let engine: IosEngine
  @ObservationIgnored public weak var document: (any KeyboardTextDocument)?
  /// The marked text last set in the document and its cursor (in characters).
  @ObservationIgnored private var markedText = ""
  @ObservationIgnored private var markedCursor = 0
  /// The last kana can still toggle.
  @ObservationIgnored private var isToggling = false
  /// The key being sent, for `togglingKey`.
  @ObservationIgnored private var sendingKey: String?
  @ObservationIgnored private var isActive = false
  /// Actions held back while the conversion key waits for the AI result.
  @ObservationIgnored private var queued: [() -> Void] = []
  @ObservationIgnored private var isWaitingForAI = false
  @ObservationIgnored private var suggestionRefresh: Task<Void, Never>?
  /// Counts the outputs applied; a refresh scheduled for an older one is dropped.
  @ObservationIgnored private var outputGeneration = 0

  public init(engine: IosEngine, settings: KeyboardSettings = KeyboardSettings()) {
    self.engine = engine
    self.settings = settings
  }

  public var isComposing: Bool { !preedit.isEmpty }

  /// Whether the engine loaded its data set (false: every key gets its default action only).
  public var isEngineAvailable: Bool { engine.backend.isAvailable }

  // MARK: - Lifecycle

  /// Called when the keyboard appears: runs the commands the Genmai app queued, applies `settings` and the
  /// config, and creates the session (once).
  public func activate(settings: KeyboardSettings) {
    for command in ToolCommandQueue.take() {
      engine.backend.handleToolCommand(command)
    }
    var command = Genmai_Commands_Command()
    var config = Genmai_Config_Config()
    IosEngine.fillMobileConfig(&config)
    engine.setConfig(config, &command)
    if !isActive || settings != self.settings {
      self.settings = settings
      engine.setMobileRequest(settings.engineLayoutName, &command)
      inputMode = .hiragana
      isShifted = false
    }
    if engine.sessionId == 0 {
      engine.createSession(&command)
      engine.backend.startWatchDog()
    }
    isActive = true
  }

  /// Called when the keyboard disappears: commits the composition and writes the learning data.
  public func deactivate() async {
    commitComposition()
    isActive = false
    await engine.backend.syncData()
  }

  /// The keyboard moved to another text field (or came back): the composition is committed and the context
  /// reset.
  public func documentChangedExternally() {
    commitComposition()
    var command = Genmai_Commands_Command()
    engine.resetContext(&command)
  }

  // MARK: - Keys

  /// A character key (its tap or flick text).
  public func input(_ text: String) {
    run { self.performInput(text) }
  }

  private func performInput(_ text: String) {
    var key = text
    if isShifted {
      key = text.uppercased()
      isShifted = false
    }
    if !isComposing {
      // a composition starts: the text before it is its left context (later, the marked text is part of it)
      engine.precedingText = document?.precedingText
    }
    var command = Genmai_Commands_Command()
    guard engine.sendKey(key, &command) else {
      document?.insertText(key)
      return
    }
    sendingKey = key
    apply(command.output, unconsumed: { $0.insertText(key) })
    sendingKey = nil
  }

  public func perform(_ function: KeyboardFunction) {
    if function == .space, isComposing, !isWaitingForAI, let wait = conversionWait() {
      // the conversion key: the AI result is awaited first (the keys typed meanwhile wait behind it)
      isWaitingForAI = true
      Task {
        await wait.value
        self.isWaitingForAI = false
        self.performFunction(.space)
        self.drainQueue()
      }
      return
    }
    run { self.performFunction(function) }
  }

  private func performFunction(_ function: KeyboardFunction) {
    switch function {
    case .backspace:
      sendSpecialKey(.backspace) { $0.deleteBackward() }
    case .space:
      sendSpecialKey(.space) { $0.insertText(" ") }
    case .enter:
      sendSpecialKey(.enter) { $0.insertText("\n") }
    case .cursorLeft:
      sendSpecialKey(.virtualLeft) { $0.adjustTextPosition(byCharacterOffset: -1) }
    case .cursorRight:
      sendSpecialKey(.virtualRight) { $0.adjustTextPosition(byCharacterOffset: 1) }
    case .kaomoji:
      guard !isComposing else { return }
      var event = Genmai_Commands_SessionCommand.CompositionEvent()
      event.compositionString = "かおもじ"
      event.probability = 1
      var command = Genmai_Commands_SessionCommand()
      command.type = .updateComposition
      command.compositionEvents = [event]
      var result = Genmai_Commands_Command()
      if engine.sendSessionCommand(command, &result) {
        apply(result.output, unconsumed: nil)
        // the emoticon rewriter lists the emoticons for the conversion of かおもじ
        sendSpecialKey(.space) { _ in }
      }
    case .advance:
      if isToggling {
        stopKeyToggling()
      } else {
        performFunction(.cursorRight)
      }
    case .undo:
      var command = Genmai_Commands_Command()
      if engine.undoOrRewind(&command) {
        apply(command.output, unconsumed: nil)
      }
    case .inputMode(let mode):
      if engine.switchInputMode(mode) {
        inputMode = mode
      }
      isShifted = false
    case .shift:
      isShifted.toggle()
    case .nextKeyboard:
      break  // handled by the extension
    }
  }

  /// Commits the candidate `id` of the candidate bar.
  public func selectCandidate(_ id: Int32) {
    run {
      var command = Genmai_Commands_Command()
      if self.engine.submitCandidate(id, &command) {
        self.apply(command.output, unconsumed: nil)
      }
    }
  }

  // MARK: - AI conversion

  /// Runs `action` now, or after the conversion key that waits for the AI result.
  private func run(_ action: @escaping () -> Void) {
    if isWaitingForAI {
      queued.append(action)
    } else {
      action()
    }
  }

  private func drainQueue() {
    while !isWaitingForAI, !queued.isEmpty {
      queued.removeFirst()()
    }
  }

  /// The AI hook's wait for the conversion key (SPACE) of the current composition; nil: send it now.
  private func conversionWait() -> Task<Void, Never>? {
    var key = Genmai_Commands_KeyEvent()
    key.specialKey = .space
    return engine.backend.aiHook?.conversionWait(for: key)
  }

  /// After a suggestion: when the AI result for the composition arrives later with a new top, the suggestion is
  /// requested again (MOVE_CURSOR to the end changes nothing but the candidates).
  private func scheduleSuggestionRefresh(_ output: Genmai_Commands_Output) {
    suggestionRefresh?.cancel()
    guard Self.canRefreshSuggestion(output), let update = engine.backend.aiHook?.suggestionUpdate() else { return }
    let generation = outputGeneration
    let preedit = output.preedit
    suggestionRefresh = Task {
      guard await update.value, !Task.isCancelled, generation == self.outputGeneration, !self.isWaitingForAI
      else { return }
      self.refreshSuggestion(preedit)
    }
  }

  private func refreshSuggestion(_ preedit: Genmai_Commands_Preedit) {
    // the engine restores the composer afterwards, so the last kana keeps toggling (the output's preedit says it
    // does not: compare without that flag)
    guard let output = engine.refreshSuggestion(cursor: preedit.cursor), output.consumed, !output.hasResult
    else { return }
    var shown = output.preedit
    shown.isToggleable = preedit.isToggleable
    guard shown == preedit else { return }
    var result = Genmai_Commands_Command()
    result.output = output
    outputGeneration += 1
    updateCandidates(result.output)
    // the exact (refined) conversion may still replace the fast one after a typing pause
    scheduleSuggestionRefresh(result.output)
  }

  /// A composition with suggestions and the cursor at its end.
  static func canRefreshSuggestion(_ output: Genmai_Commands_Output) -> Bool {
    guard output.consumed, !output.hasResult, !output.preedit.segment.isEmpty,
      !output.allCandidateWords.candidates.isEmpty, output.allCandidateWords.category != .conversion
    else { return false }
    let length = output.preedit.segment.reduce(0) { $0 + $1.value.unicodeScalars.count }
    return Int(output.preedit.cursor) == length
  }

  /// Waits for a scheduled suggestion refresh (tests).
  func waitForSuggestionRefresh() async {
    await suggestionRefresh?.value
  }

  /// Commits the composition as it is shown (SUBMIT).
  public func commitComposition() {
    isToggling = false
    togglingKey = nil
    queued.removeAll()
    guard isComposing else { return }
    var command = Genmai_Commands_Command()
    if engine.submit(&command) {
      apply(command.output, unconsumed: nil)
    }
  }

  private func sendSpecialKey(
    _ key: Genmai_Commands_KeyEvent.SpecialKey, unconsumed: @escaping (any KeyboardTextDocument) -> Void
  ) {
    var command = Genmai_Commands_Command()
    guard engine.sendSpecialKey(key, &command) else {
      if let document { unconsumed(document) }
      return
    }
    apply(command.output, unconsumed: unconsumed)
  }

  // MARK: - Output

  private func apply(_ output: Genmai_Commands_Output, unconsumed: ((any KeyboardTextDocument) -> Void)?) {
    isToggling = false
    togglingKey = nil
    outputGeneration += 1
    if !output.consumed {
      if let unconsumed, let document {
        unconsumed(document)
      }
      return
    }
    if output.hasDeletionRange {
      applyDeletionRange(output.deletionRange)
    }
    if output.hasResult, output.result.type == .string, !output.result.value.isEmpty {
      commit(output.result.value)
    }
    updatePreedit(output.preedit)
    updateCandidates(output)
    scheduleSuggestionRefresh(output)
    if output.preedit.isToggleable {
      isToggling = true
      togglingKey = sendingKey
    }
    if output.hasCallback, output.callback.hasSessionCommand {
      // The session asks the client to send a command (e.g. UNDO after a "Ctrl Backspace").
      var command = Genmai_Commands_Command()
      if engine.sendSessionCommand(output.callback.sessionCommand, &command) {
        var callbackOutput = command.output
        callbackOutput.clearCallback()
        apply(callbackOutput, unconsumed: nil)
      }
    }
  }

  private func commit(_ text: String) {
    guard let document else { return }
    if markedText.isEmpty {
      document.insertText(text)
    } else {
      // Replace the marked text with the result and fix it.
      document.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0))
      document.unmarkText()
      markedText = ""
      markedCursor = 0
    }
  }

  private func updatePreedit(_ preedit: Genmai_Commands_Preedit) {
    let text = preedit.segment.map(\.value).joined()
    let cursor = Int(preedit.cursor)
    self.preedit = text
    guard text != markedText || cursor != markedCursor, let document else { return }
    if text.isEmpty {
      document.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
      document.unmarkText()
    } else {
      // The preedit cursor counts characters (code points); the selected range is UTF-16.
      let location = String(String.UnicodeScalarView(text.unicodeScalars.prefix(cursor))).utf16.count
      document.setMarkedText(text, selectedRange: NSRange(location: location, length: 0))
    }
    markedText = text
    markedCursor = cursor
  }

  private func updateCandidates(_ output: Genmai_Commands_Output) {
    let list = output.allCandidateWords
    candidates = list.candidates.map { word in
      KeyboardCandidate(id: word.id, value: word.value, description: word.annotation.description_p)
    }
    // Set during conversion (the conversion key moves it).
    if list.hasFocusedIndex, Int(list.focusedIndex) < candidates.count {
      focusedCandidateID = candidates[Int(list.focusedIndex)].id
    } else {
      focusedCandidateID = nil
    }
  }

  /// UNDO of a commit: the committed text before the cursor is deleted (the preedit comes back in the output).
  private func applyDeletionRange(_ range: Genmai_Commands_DeletionRange) {
    guard let document, range.length > 0 else { return }
    let move = Int(range.offset) + Int(range.length)
    if move != 0 {
      document.adjustTextPosition(byCharacterOffset: move)
    }
    for _ in 0..<range.length {
      document.deleteBackward()
    }
  }

  /// Ends the toggle of the last kana ("→").
  private func stopKeyToggling() {
    isToggling = false
    togglingKey = nil
    var command = Genmai_Commands_Command()
    if engine.maybeCreateNewChunk(&command) {
      apply(command.output, unconsumed: nil)
    }
  }
}
