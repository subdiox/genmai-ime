// Port of mozc/src/mac/mozc_imk_input_controller_test.mm (3.35.6354).
//
// The C++ sleeps between key taps; the Swift controller takes an injectable clock instead.

import AppKit
import Carbon
import GenmaiClient
import GenmaiProtocol
import GenmaiRenderer
import Testing

@testable import GenmaiMac

@MainActor
final class ControllerFixture {
  /// What the controller's callbacks change (the opened URLs) and read (the clock).
  final class Environment {
    var openURLCount = 0
    var time: TimeInterval = 1000
  }

  let mockClient = MockTextInputClient()
  var mockGenmaiClient = MockGenmaiClient()
  var mockRenderer = MockRenderer()
  let toolLauncher = MockAppLauncher()
  let environment = Environment()
  var controller: GenmaiInputController

  var openURLCount: Int {
    get { environment.openURLCount }
    set { environment.openURLCount = newValue }
  }

  var time: TimeInterval {
    get { environment.time }
    set { environment.time = newValue }
  }

  init() {
    controller = Self.makeController(
      mockGenmaiClient, mockRenderer, mockClient: mockClient, toolLauncher: toolLauncher, environment: environment)
  }

  func setUpController() {
    mockGenmaiClient = MockGenmaiClient()
    mockRenderer = MockRenderer()
    controller = Self.makeController(
      mockGenmaiClient, mockRenderer, mockClient: mockClient, toolLauncher: toolLauncher, environment: environment)
  }

  private static func makeController(
    _ genmaiClient: MockGenmaiClient, _ renderer: MockRenderer, mockClient: MockTextInputClient,
    toolLauncher: MockAppLauncher, environment: Environment
  ) -> GenmaiInputController {
    GenmaiInputController(
      genmaiClient: genmaiClient, renderer: renderer,
      currentClient: { mockClient }, toolLauncher: toolLauncher,
      urlOpener: { _ in environment.openURLCount += 1 },
      selectionRangeFallback: { NSRange(location: NSNotFound, length: 0) },
      now: { environment.time },
      frontmostWindow: { nil })
  }

  func resetClientBundleIdentifier(_ newBundleID: String) {
    mockClient.bundleID = newBundleID
    setUpController()
  }

  @discardableResult
  func sendKeyEvent(_ keyCode: Int) -> Bool {
    let event = KeyEventData(
      type: .keyDown, characters: " ", charactersIgnoringModifiers: " ", modifierFlags: [],
      keyCode: UInt16(keyCode))
    return controller.handleEvent(event, client: mockClient)
  }

  func sleep(_ seconds: TimeInterval) { time += seconds }
}

private func makeSegment(
  _ annotation: Genmai_Commands_Preedit.Segment.Annotation, _ value: String, _ length: UInt32
) -> Genmai_Commands_Preedit.Segment {
  var segment = Genmai_Commands_Preedit.Segment()
  segment.annotation = annotation
  segment.value = value
  segment.valueLength = length
  return segment
}

/// Because preedit has NSMarkedClauseSegment attribute which has to
/// change for each call of creating preedit, we can't use simple
/// isEqualToAttributedString method.
private func comparePreedit(_ expected: NSAttributedString, _ actual: NSAttributedString) -> Bool {
  if expected.length != actual.length || expected.string != actual.string {
    return false
  }
  let knownAttributeNames: Set<NSAttributedString.Key> = [
    .underlineStyle, .underlineColor, .markedClauseSegment,
  ]
  var cursor = 0
  while cursor < expected.length {
    var expectedRange = NSRange(location: NSNotFound, length: NSNotFound)
    var actualRange = NSRange(location: NSNotFound, length: NSNotFound)
    let expectedAttributes = expected.attributes(at: cursor, effectiveRange: &expectedRange)
    let actualAttributes = actual.attributes(at: cursor, effectiveRange: &actualRange)
    // false if attribute over different range.
    if expectedRange != actualRange {
      return false
    }
    // Check attributes for underlines
    guard let expectedUnderline = expectedAttributes[.underlineStyle] as? Int,
      let actualUnderline = actualAttributes[.underlineStyle] as? Int,
      expectedUnderline == actualUnderline
    else {
      return false
    }
    // Check if it contains unknown attributes
    if !Set(expectedAttributes.keys).isSubset(of: knownAttributeNames)
      || !Set(actualAttributes.keys).isSubset(of: knownAttributeNames)
    {
      return false
    }
    cursor += expectedRange.length
  }
  return true
}

@MainActor
@Suite struct GenmaiInputControllerTests {
  @Test func updateComposedString() {
    let f = ControllerFixture()
    // If preedit is nullptr, it still calls setMarkedText, with an empty string.
    f.controller.updateComposedString(nil)
    #expect(f.controller.composedString.isEqual(to: NSAttributedString(string: "")))

    // If preedit has some data, it returns a data with highlighting information
    var preedit = Genmai_Commands_Preedit()
    // UNDERLINE segment
    preedit.segment.append(makeSegment(.underline, "a", 1))
    // Second segment is HIGHLIGHT
    preedit.segment.append(makeSegment(.highlight, "bc", 2))
    // Third segment is NONE annotation but it seems same as UNDERLINE at this time
    preedit.segment.append(makeSegment(.none, "def", 2))

    let highlightAttributes = GenmaiInputController.defaultMarkAttributes(
      Int32(kTSMHiliteSelectedConvertedText))
    let underlineAttributes = GenmaiInputController.defaultMarkAttributes(Int32(kTSMHiliteConvertedText))
    let expected = NSMutableAttributedString(string: "abcdef")
    expected.addAttributes(underlineAttributes, range: NSRange(location: 0, length: 1))
    expected.addAttributes(highlightAttributes, range: NSRange(location: 1, length: 2))
    expected.addAttributes(underlineAttributes, range: NSRange(location: 3, length: 3))
    f.controller.updateComposedString(preedit)
    #expect(comparePreedit(expected, f.controller.composedString))
    // The marked text is sent to the client.
    #expect(f.mockClient.markedText?.string == "abcdef")
  }

  @Test func clearCandidates() {
    let f = ControllerFixture()
    f.controller.clearCandidates()
    #expect(f.mockRenderer.execCommandCounter == 1)
    // After clearing candidates, the candidate window has to be invisible.
    #expect(!f.mockRenderer.calledCommand.visible)
  }

  @Test func updateCandidates() async {
    let f = ControllerFixture()
    // When output is null, same as ClearCandidate
    f.controller.updateCandidates(nil)
    await f.controller.waitForPendingCandidateUpdates()
    #expect(f.mockRenderer.execCommandCounter == 1)
    #expect(!f.mockRenderer.calledCommand.visible)
    #expect(f.mockClient.getCounter("attributesForCharacterIndex:lineHeightRectangle:") == 0)

    // create an output
    var output = Output()
    // a candidate has to have at least a candidate
    output.candidateWindow.focusedIndex = 0
    output.candidateWindow.size = 1
    var candidate = Genmai_Commands_CandidateWindow.Candidate()
    candidate.index = 0
    candidate.value = "abc"
    output.candidateWindow.candidate.append(candidate)

    // setup the cursor position
    f.mockClient.expectedCursor = NSRect(x: 50, y: 50, width: 1, height: 10)
    f.mockClient.expectedAttributes = ["IMKBaseline": NSValue(point: NSPoint(x: 50, y: 718))]
    f.controller.updateCandidates(output)
    await f.controller.waitForPendingCandidateUpdates()
    #expect(f.mockClient.getCounter("attributesForCharacterIndex:lineHeightRectangle:") == 1)
    var rendererCommand = f.controller.rendererCommand
    #expect(f.mockRenderer.execCommandCounter == 2)
    #expect(rendererCommand.visible)
    let preeditRectangle = rendererCommand.preeditRectangle
    #expect(preeditRectangle.left == 50)
    #expect(preeditRectangle.top == 708)
    #expect(preeditRectangle.right == 51)
    #expect(preeditRectangle.bottom == 718)

    // reshow the candidate window again -- but cursor position has changed.
    f.mockClient.expectedCursor = NSRect(x: 60, y: 50, width: 1, height: 10)
    f.controller.updateCandidates(output)
    await f.controller.waitForPendingCandidateUpdates()
    // Does not change: not call again
    #expect(f.mockClient.getCounter("attributesForCharacterIndex:lineHeightRectangle:") == 1)
    #expect(f.mockRenderer.execCommandCounter == 3)
    rendererCommand = f.controller.rendererCommand
    #expect(rendererCommand.visible)
    // Does not change the position
    #expect(rendererCommand.preeditRectangle == preeditRectangle)

    // Then update without candidate entries -- goes invisible.
    f.controller.updateCandidates(Output())
    await f.controller.waitForPendingCandidateUpdates()
    #expect(f.mockClient.getCounter("attributesForCharacterIndex:lineHeightRectangle:") == 1)
    #expect(f.mockRenderer.execCommandCounter == 4)
    #expect(!f.controller.rendererCommand.visible)
  }

  @Test func openLink() {
    let f = ControllerFixture()
    #expect(f.openURLCount == 0)
    f.controller.openLink(URL(validLiteral: "http://www.example.com/"))
    // openURL is invoked
    #expect(f.openURLCount == 1)
    // Change to the unsecure bundle ID
    f.resetClientBundleIdentifier("com.apple.securityagent")
    // The counter does not change during the initialization
    #expect(f.openURLCount == 1)
    f.controller.openLink(URL(validLiteral: "http://www.example.com/"))
    // openURL is not invoked
    #expect(f.openURLCount == 1)
  }

  @Test func switchModeToDirect() {
    let f = ControllerFixture()
    // setup the IME status
    f.controller.mode = .hiragana
    var preedit = Genmai_Commands_Preedit()
    preedit.segment.append(makeSegment(.underline, "abcdef", 6))
    f.controller.updateComposedString(preedit)
    var output = Output()
    output.result.type = .string
    output.result.value = "foo"
    f.mockGenmaiClient.sendKeyHandler = { key in
      key.hasSpecialKey && key.specialKey == .off ? output : nil
    }

    f.controller.switchMode(.direct, client: f.mockClient)
    #expect(f.mockGenmaiClient.sendKeyCalls.count == 1)
    #expect(f.controller.mode == .direct)
    #expect(f.mockClient.getCounter("insertText:replacementRange:") == 1)
    #expect(f.mockClient.insertedText == "foo")
    #expect(f.controller.composedString.length == 0)
    #expect(!f.controller.rendererCommand.visible)
  }

  @Test func switchMode() throws {
    let f = ControllerFixture()
    // When a mode changes from DIRECT, it should invoke "ON" command beforehand.
    f.mockGenmaiClient.sendKeyHandler = { _ in Output() }
    f.mockGenmaiClient.sendCommandHandler = { _ in Output() }

    f.controller.mode = .direct
    f.controller.switchMode(.hiragana, client: f.mockClient)
    #expect(f.controller.mode == .hiragana)
    #expect(f.mockGenmaiClient.sendKeyCalls.count == 1)
    #expect(f.mockGenmaiClient.sendKeyCalls[0].key.specialKey == .on)
    var actualCommand = try #require(f.mockGenmaiClient.sendCommandCalls.last).command
    #expect(actualCommand.type == .switchCompositionMode)
    #expect(actualCommand.compositionMode == .hiragana)

    // Switch from HIRAGANA to KATAKANA.  Just sending mode switching command.
    f.controller.mode = .hiragana
    f.controller.switchMode(.halfKatakana, client: f.mockClient)
    #expect(f.controller.mode == .halfKatakana)
    actualCommand = try #require(f.mockGenmaiClient.sendCommandCalls.last).command
    #expect(actualCommand.type == .switchCompositionMode)
    #expect(actualCommand.compositionMode == .halfKatakana)
    #expect(f.mockGenmaiClient.sendCommandCalls.count == 2)
    #expect(f.mockGenmaiClient.sendKeyCalls.count == 1)

    // going to same mode does not cause sendcommand
    f.controller.switchMode(.halfKatakana, client: f.mockClient)
    #expect(f.controller.mode == .halfKatakana)
    #expect(f.mockGenmaiClient.sendCommandCalls.count == 2)
  }

  @Test func switchDisplayMode() {
    let f = ControllerFixture()
    #expect(f.mockClient.selectedMode.isEmpty)
    #expect(f.controller.mode == .direct)
    f.controller.switchDisplayMode()
    #expect(f.mockClient.getCounter("selectInputMode:") == 1)
    #expect(f.mockClient.selectedMode == "com.apple.inputmethod.Roman")

    // Does not change the display mode for MS Word.
    f.resetClientBundleIdentifier("com.microsoft.Word")
    f.controller.switchMode(.hiragana, client: f.mockClient)
    #expect(f.controller.mode == .hiragana)
    f.controller.switchDisplayMode()
    // still remains 1 and display mode does not change.
    #expect(f.mockClient.getCounter("selectInputMode:") == 1)
    #expect(f.mockClient.selectedMode == "com.apple.inputmethod.Roman")
  }

  @Test func commitText() {
    let f = ControllerFixture()
    f.controller.replacementRange = NSRange(location: 0, length: 1)
    f.controller.commitText("foo", client: f.mockClient)

    #expect(f.mockClient.getCounter("insertText:replacementRange:") == 1)
    #expect(f.mockClient.insertedText == "foo")
    // location has to be cleared after the commit.
    #expect(f.controller.replacementRange.location == NSNotFound)
  }

  @Test func handleConfig() {
    let f = ControllerFixture()
    var config = Config()
    config.preeditMethod = .kana
    config.yenSignCharacter = .backslash
    config.useJapaneseLayout = true
    f.mockGenmaiClient.config = config

    f.controller.handleConfig()
    #expect(f.controller.keyCodeMap.inputMode == .kana)
    #expect(f.controller.yenSignCharacter == .backslash)
    #expect(f.mockClient.getCounter("overrideKeyboardWithKeyboardNamed:") == 1)
    #expect(f.mockClient.overriddenLayout == "com.apple.keylayout.US")
  }

  @Test func doubleTapKanaReconvert() {
    let f = ControllerFixture()
    // tap (short) tap -> emit undo command
    f.controller.mode = .hiragana

    // set attributedString for Reconvert
    f.mockClient.attributedString = NSAttributedString(string: "abcde")
    f.mockClient.expectedRange = NSRange(location: 1, length: 3)

    // Send Kana-key.
    // Because of special hack for Eisu/Kana keys, it returns YES.
    #expect(f.sendKeyEvent(kVK_JIS_Kana))
    // Check if it did not send keys or commands.
    #expect(f.mockGenmaiClient.sendKeyCalls.isEmpty)
    #expect(f.mockGenmaiClient.sendCommandCalls.isEmpty)

    // Sleep less than DoubleTapInterval (sec)
    f.sleep(kDoubleTapInterval / 2)

    // Send Kana-key.
    f.mockGenmaiClient.sendCommandHandler = { _ in Output() }
    #expect(f.sendKeyEvent(kVK_JIS_Kana))
    // Check if it sent an undo command.
    #expect(f.mockGenmaiClient.sendCommandCalls.count == 1)
    let actualCommand = f.mockGenmaiClient.sendCommandCalls[0].command
    #expect(actualCommand.type == .convertReverse)
    #expect(actualCommand.text == "bcd")
  }

  @Test func doubleTapKanaUndo() {
    let f = ControllerFixture()
    // tap (short) tap -> emit undo command
    f.controller.mode = .hiragana

    // set expectedRange for Undo
    f.mockClient.expectedRange = NSRange(location: 1, length: 0)

    #expect(f.sendKeyEvent(kVK_JIS_Kana))
    #expect(f.mockGenmaiClient.sendCommandCalls.isEmpty)

    f.sleep(kDoubleTapInterval / 2)

    f.mockGenmaiClient.sendCommandHandler = { _ in Output() }
    #expect(f.sendKeyEvent(kVK_JIS_Kana))
    #expect(f.mockGenmaiClient.sendCommandCalls.map(\.command.type) == [.undo])
  }

  @Test func doubleTapKanaUndoTimeOver() {
    let f = ControllerFixture()
    // tap (long) tap -> don't emit undo command
    f.controller.mode = .hiragana
    f.mockClient.expectedRange = NSRange(location: 1, length: 0)

    #expect(f.sendKeyEvent(kVK_JIS_Kana))
    // Sleep more than DoubleTapInterval (sec)
    f.sleep(kDoubleTapInterval * 2)
    #expect(f.sendKeyEvent(kVK_JIS_Kana))
    #expect(f.mockGenmaiClient.sendCommandCalls.isEmpty)
  }

  @Test func singleAndDoubleTapKanaUndo() {
    let f = ControllerFixture()
    // tap (long) tap (short) tap -> emit once
    f.controller.mode = .hiragana
    f.mockClient.expectedRange = NSRange(location: 1, length: 0)

    #expect(f.sendKeyEvent(kVK_JIS_Kana))
    f.sleep(kDoubleTapInterval * 2)
    #expect(f.sendKeyEvent(kVK_JIS_Kana))
    #expect(f.mockGenmaiClient.sendCommandCalls.isEmpty)

    f.sleep(kDoubleTapInterval / 2)
    f.mockGenmaiClient.sendCommandHandler = { _ in Output() }
    #expect(f.sendKeyEvent(kVK_JIS_Kana))
    #expect(f.mockGenmaiClient.sendCommandCalls.map(\.command.type) == [.undo])
  }

  @Test func tripleTapKanaUndo() {
    let f = ControllerFixture()
    // tap (short) tap (short) tap -> emit twice
    f.controller.mode = .hiragana
    f.mockClient.expectedRange = NSRange(location: 1, length: 0)

    #expect(f.sendKeyEvent(kVK_JIS_Kana))
    #expect(f.mockGenmaiClient.sendCommandCalls.isEmpty)

    f.mockGenmaiClient.sendCommandHandler = { _ in Output() }
    f.sleep(kDoubleTapInterval / 2)
    #expect(f.sendKeyEvent(kVK_JIS_Kana))
    f.sleep(kDoubleTapInterval / 2)
    #expect(f.sendKeyEvent(kVK_JIS_Kana))
    #expect(f.mockGenmaiClient.sendCommandCalls.map(\.command.type) == [.undo, .undo])
  }

  @Test func quadrupleTapKanaUndo() {
    let f = ControllerFixture()
    // tap (short) tap (short) tap (short) tap -> emit thrice
    f.controller.mode = .hiragana
    f.mockClient.expectedRange = NSRange(location: 1, length: 0)

    #expect(f.sendKeyEvent(kVK_JIS_Kana))
    f.mockGenmaiClient.sendCommandHandler = { _ in Output() }
    for _ in 0..<3 {
      f.sleep(kDoubleTapInterval / 2)
      #expect(f.sendKeyEvent(kVK_JIS_Kana))
    }
    #expect(f.mockGenmaiClient.sendCommandCalls.map(\.command.type) == [.undo, .undo, .undo])
  }

  @Test func doubleTapEisuCommitRawText() {
    let f = ControllerFixture()
    // Send Eisu-key.
    // Because of special hack for Eisu/Kana keys, it returns YES.
    #expect(f.sendKeyEvent(kVK_JIS_Eisu))
    #expect(f.mockGenmaiClient.sendCommandCalls.isEmpty)

    f.sleep(kDoubleTapInterval / 2)

    f.mockGenmaiClient.sendCommandHandler = { _ in Output() }
    #expect(f.sendKeyEvent(kVK_JIS_Eisu))
    #expect(f.mockGenmaiClient.sendCommandCalls.map(\.command.type) == [.commitRawText])
  }

  @Test func fillSurroundingContext() {
    let f = ControllerFixture()
    f.mockClient.attributedString = NSAttributedString(string: "abcde")
    f.mockClient.expectedRange = NSRange(location: 2, length: 1)
    var context = Context()
    f.controller.fillSurroundingContext(&context, client: f.mockClient)
    #expect(context.precedingText == "ab")
    #expect(f.mockClient.getCounter("selectedRange") == 1)
    #expect(f.mockClient.getCounter("markedRange") == 0)

    f.mockClient.attributedString = NSAttributedString(string: "012345678901234567890abcde")

    f.mockClient.expectedRange = NSRange(location: 1, length: 0)
    f.controller.fillSurroundingContext(&context, client: f.mockClient)
    #expect(context.precedingText == "0")
    #expect(f.mockClient.getCounter("selectedRange") == 2)
    #expect(f.mockClient.getCounter("markedRange") == 0)

    f.mockClient.expectedRange = NSRange(location: 22, length: 1)
    f.controller.fillSurroundingContext(&context, client: f.mockClient)
    #expect(context.precedingText == "2345678901234567890a")
    #expect(f.mockClient.getCounter("selectedRange") == 3)
    #expect(f.mockClient.getCounter("markedRange") == 0)

    f.mockClient.attributedString = NSAttributedString(string: "012abc345")
    var preedit = Genmai_Commands_Preedit()
    preedit.segment.append(makeSegment(.highlight, "abc", 3))
    f.controller.updateComposedString(preedit)
    f.mockClient.expectedRange = NSRange(location: 3, length: 3)
    f.controller.fillSurroundingContext(&context, client: f.mockClient)
    #expect(context.precedingText == "012")
    #expect(f.mockClient.getCounter("selectedRange") == 4)
    #expect(f.mockClient.getCounter("markedRange") == 0)
  }

  // MARK: Swift-only tests of paths the C++ test does not cover.

  @Test func directModeKeyIsNotSent() {
    let f = ControllerFixture()
    let a = KeyEventData(
      type: .keyDown, characters: "a", charactersIgnoringModifiers: "a", modifierFlags: [],
      keyCode: UInt16(kVK_ANSI_A))
    #expect(!f.controller.handleEvent(a, client: f.mockClient))
    #expect(f.mockGenmaiClient.sendKeyCalls.isEmpty)
  }

  @Test func yenSignInDirectMode() {
    let f = ControllerFixture()
    var config = Config()
    config.yenSignCharacter = .backslash
    f.mockGenmaiClient.config = config
    f.controller.handleConfig()
    let yen = KeyEventData(
      type: .keyDown, characters: "¥", charactersIgnoringModifiers: "¥", modifierFlags: [],
      keyCode: UInt16(kVK_JIS_Yen))
    #expect(f.controller.handleEvent(yen, client: f.mockClient))
    #expect(f.mockClient.insertedText == "\\")
  }

  @Test func handleEventSendsKeyWithContext() {
    let f = ControllerFixture()
    f.controller.mode = .hiragana
    f.mockClient.attributedString = NSAttributedString(string: "xyz")
    f.mockClient.expectedRange = NSRange(location: 3, length: 0)
    var output = Output()
    output.consumed = true
    output.mode = .hiragana
    output.preedit.segment = [makeSegment(.underline, "あ", 1)]
    output.preedit.cursor = 1
    f.mockGenmaiClient.sendKeyHandler = { _ in output }
    let a = KeyEventData(
      type: .keyDown, characters: "a", charactersIgnoringModifiers: "a", modifierFlags: [],
      keyCode: UInt16(kVK_ANSI_A))
    #expect(f.controller.handleEvent(a, client: f.mockClient))
    let call = f.mockGenmaiClient.sendKeyCalls[0]
    #expect(call.key.keyCode == 97)
    #expect(call.key.mode == .hiragana)
    #expect(call.context?.precedingText == "xyz")
    #expect(f.controller.composedString.string == "あ")
    #expect(f.controller.originalString == "a")
    #expect(f.controller.selectionRange() == NSRange(location: 1, length: 0))
  }

  /// Not in Mozc: a conversion key whose AI result is in flight is queued (no thread blocks) together with the
  /// keys typed during the wait; they are sent in order when the wait is over, or right away when another
  /// request (commit) comes first.
  @Test func aiConversionGateQueuesKeysInOrder() async {
    let f = ControllerFixture()
    f.controller.mode = .hiragana
    var output = Output()
    output.consumed = true
    output.mode = .hiragana
    f.mockGenmaiClient.sendKeyHandler = { _ in output }
    let (stream, release) = AsyncStream<Void>.makeStream()
    let gateTask = Task { for await _ in stream { break } }
    f.controller.aiConversionGate = { key in key.specialKey == .space ? gateTask : nil }
    func key(_ code: Int, _ c: String) -> KeyEventData {
      KeyEventData(
        type: .keyDown, characters: c, charactersIgnoringModifiers: c, modifierFlags: [], keyCode: UInt16(code))
    }
    #expect(f.controller.handleEvent(key(kVK_ANSI_A, "a"), client: f.mockClient))
    #expect(f.controller.handleEvent(key(kVK_Space, " "), client: f.mockClient))
    #expect(f.controller.handleEvent(key(kVK_ANSI_I, "i"), client: f.mockClient))
    #expect(f.mockGenmaiClient.sendKeyCalls.count == 1)  // SPACE and i wait
    release.yield()
    await gateTask.value
    for _ in 0..<100 where f.mockGenmaiClient.sendKeyCalls.count < 3 {
      await Task.yield()
    }
    let calls = f.mockGenmaiClient.sendKeyCalls
    #expect(calls.count == 3)
    #expect(calls.count == 3 && calls[1].key.specialKey == .space && calls[2].key.keyCode == 105)

    // A commit while keys are queued sends them first, without waiting.
    let (stream2, _) = AsyncStream<Void>.makeStream()
    let pending = Task { for await _ in stream2 { break } }
    f.controller.aiConversionGate = { key in key.specialKey == .space ? pending : nil }
    #expect(f.controller.handleEvent(key(kVK_Space, " "), client: f.mockClient))
    #expect(f.mockGenmaiClient.sendKeyCalls.count == 3)
    f.controller.flushQueuedKeys()
    #expect(f.mockGenmaiClient.sendKeyCalls.count == 4)
    pending.cancel()
  }

  /// A composition answered with Mozc's suggestion window (cursor at the end).
  static func suggestionOutput(_ reading: String, _ first: String) -> Output {
    var output = Output()
    output.consumed = true
    output.mode = .hiragana
    output.status.mode = .hiragana
    output.status.comebackMode = .hiragana
    output.preedit.segment.append(makeSegment(.underline, reading, UInt32(reading.unicodeScalars.count)))
    output.preedit.cursor = UInt32(reading.unicodeScalars.count)
    output.candidateWindow.category = .suggestion
    var candidate = Genmai_Commands_CandidateWindow.Candidate()
    candidate.value = first
    candidate.index = 0
    output.candidateWindow.candidate.append(candidate)
    return output
  }

  /// Not in Mozc: when the AI result of the composition arrives after the key was answered, the suggestion is
  /// re-requested (MOVE_CURSOR to the cursor position) and only the candidate window is updated.
  @Test func aiSuggestionRefreshUpdatesOnlyTheCandidateWindow() async {
    let f = ControllerFixture()
    f.controller.mode = .hiragana
    f.mockGenmaiClient.sendKeyHandler = { _ in Self.suggestionOutput("かき", "柿") }
    f.mockGenmaiClient.sendCommandHandler = { _ in Self.suggestionOutput("かき", "牡蠣") }
    let (stream, release) = AsyncStream<Void>.makeStream()
    let update = Task { () -> Bool in
      for await _ in stream { break }
      return true
    }
    var asked = 0
    f.controller.aiSuggestionUpdate = {
      asked += 1
      return asked == 1 ? update : nil
    }
    let key = KeyEventData(
      type: .keyDown, characters: "i", charactersIgnoringModifiers: "i", modifierFlags: [],
      keyCode: UInt16(kVK_ANSI_I))
    #expect(f.controller.handleEvent(key, client: f.mockClient))
    await f.controller.waitForPendingCandidateUpdates()
    #expect(f.mockRenderer.calledCommand.output.candidateWindow.candidate.first?.value == "柿")
    let marked = f.mockClient.markedText
    release.yield()
    await f.controller.waitForAISuggestionRefresh()
    await f.controller.waitForPendingCandidateUpdates()
    let commands = f.mockGenmaiClient.sendCommandCalls.map(\.command)
    #expect(commands.map(\.type) == [.moveCursor])
    #expect(commands.first?.cursorPosition == 2)
    #expect(f.mockRenderer.calledCommand.output.candidateWindow.candidate.first?.value == "牡蠣")
    #expect(marked != nil && f.mockClient.markedText === marked)  // the preedit was not set again
    #expect(asked == 2)  // asked again after the refresh (an exact result may follow)
  }

  /// A refresh is dropped when anything happened meanwhile (here: another key), and not even requested when no
  /// suggestion window is shown (conversion).
  @Test func staleAISuggestionRefreshIsIgnored() async {
    let f = ControllerFixture()
    f.controller.mode = .hiragana
    f.mockGenmaiClient.sendKeyHandler = { _ in Self.suggestionOutput("かき", "柿") }
    f.mockGenmaiClient.sendCommandHandler = { _ in Self.suggestionOutput("かき", "牡蠣") }
    let (stream, release) = AsyncStream<Void>.makeStream()
    let update = Task { () -> Bool in
      for await _ in stream { break }
      return true
    }
    var asked = 0
    f.controller.aiSuggestionUpdate = {
      asked += 1
      return asked == 1 ? update : nil
    }
    func key(_ code: Int, _ c: String) -> KeyEventData {
      KeyEventData(
        type: .keyDown, characters: c, charactersIgnoringModifiers: c, modifierFlags: [], keyCode: UInt16(code))
    }
    #expect(f.controller.handleEvent(key(kVK_ANSI_I, "i"), client: f.mockClient))
    #expect(f.controller.handleEvent(key(kVK_ANSI_K, "k"), client: f.mockClient))
    release.yield()
    _ = await update.value
    for _ in 0..<20 { await Task.yield() }
    #expect(f.mockGenmaiClient.sendCommandCalls.isEmpty)

    // Conversion (no suggestion window): no refresh is requested.
    var converted = Self.suggestionOutput("かき", "柿")
    converted.candidateWindow.category = .conversion
    f.mockGenmaiClient.sendKeyHandler = { _ in converted }
    let before = asked
    #expect(f.controller.handleEvent(key(kVK_Space, " "), client: f.mockClient))
    #expect(asked == before)
    #expect(f.mockGenmaiClient.sendCommandCalls.isEmpty)
  }

  @Test func openAppFromOutput() {
    let f = ControllerFixture()
    f.mockClient.attributedString = NSAttributedString(string: "単語")
    f.mockClient.expectedRange = NSRange(location: 0, length: 2)
    var output = Output()
    output.consumed = true
    output.launchToolMode = .wordRegisterDialog
    f.controller.processOutput(output, client: f.mockClient)
    #expect(f.toolLauncher.launches.count == 1)
    #expect(f.toolLauncher.launches[0].mode == "word_register_dialog")
    #expect(f.toolLauncher.launches[0].environment[kWordRegisterEnvironmentName] == "単語")

    output.launchToolMode = .configDialog
    f.controller.processOutput(output, client: f.mockClient)
    #expect(f.toolLauncher.launches.last?.mode == "config_dialog")
  }

  @Test func commitComposition() {
    let f = ControllerFixture()
    var preedit = Genmai_Commands_Preedit()
    preedit.segment.append(makeSegment(.underline, "かな", 2))
    f.controller.updateComposedString(preedit)
    f.mockGenmaiClient.sendCommandHandler = { _ in Output() }
    f.controller.commitComposition(f.mockClient)
    #expect(f.mockClient.insertedText == "かな")
    #expect(f.mockGenmaiClient.sendCommandCalls.map(\.command.type) == [.submit])
    #expect(f.controller.composedString.length == 0)
  }

  @Test func rendererReceiverForwardsCommands() throws {
    let f = ControllerFixture()
    let receiver = RendererReceiver()
    receiver.setCurrentController(f.controller)
    f.mockGenmaiClient.sendCommandHandler = { _ in Output() }
    var command = SessionCommand()
    command.type = .selectCandidate
    command.id = 3
    receiver.sendData(try command.serializedData())
    #expect(f.mockGenmaiClient.sendCommandCalls.map(\.command) == [command])

    var output = Output()
    output.result.type = .string
    output.result.value = "結果"
    receiver.outputResult(try output.serializedData())
    #expect(f.mockClient.insertedText == "結果")
  }

  @Test func modeIDs() {
    #expect(getCompositionMode(kHiraganaModeId) == .hiragana)
    #expect(getCompositionMode(kKatakanaModeId) == .fullKatakana)
    #expect(getCompositionMode(kHalfWidthKanaModeId) == .halfKatakana)
    #expect(getCompositionMode(kFullWidthRomanModeId) == .fullAscii)
    #expect(getCompositionMode(kRomanModeId) == .halfAscii)
    #expect(getCompositionMode("") == .direct)
    for mode in [CompositionMode.hiragana, .fullKatakana, .halfKatakana, .fullAscii, .halfAscii] {
      #expect(getCompositionMode(getModeId(mode)) == mode)
    }
    #expect(getModeId(.direct) == kRomanModeId)
  }
}
