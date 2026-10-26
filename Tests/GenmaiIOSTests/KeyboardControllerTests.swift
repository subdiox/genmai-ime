import Foundation
import GenmaiBase
import GenmaiClient
import GenmaiCore
import GenmaiProtocol
import Testing

@testable import GenmaiIOS

/// A text field: the committed text before the cursor and the marked text.
@MainActor
final class FakeTextDocument: KeyboardTextDocument {
  var text = ""
  var marked = ""
  var cursorMoves: [Int] = []
  var precedingText: String? { text }

  func insertText(_ text: String) {
    self.text += text
    marked = ""
  }

  func deleteBackward() {
    if !marked.isEmpty {
      marked.removeLast()
    } else if !text.isEmpty {
      text.removeLast()
    }
  }

  func setMarkedText(_ text: String, selectedRange: NSRange) {
    marked = text
  }

  func unmarkText() {
    text += marked
    marked = ""
  }

  func adjustTextPosition(byCharacterOffset offset: Int) {
    cursorMoves.append(offset)
  }
}

@MainActor
@Suite(.enabled(if: MockDataManager.defaultDataPath != nil, "mock_genmai.data is missing"))
struct KeyboardControllerTests {
  private func withController(
    _ settings: KeyboardSettings = KeyboardSettings(),
    _ body: (KeyboardController, FakeTextDocument) throws -> Void
  ) throws {
    let dataFilePath = try #require(MockDataManager.defaultDataPath)
    try SystemUtil.withTempUserProfile { _ in
      // SET_CONFIG changes the config handler: keep it to this test.
      try ConfigHandler.withScopedHandlerForTesting {
        let controller = KeyboardController(engine: IosEngine(dataFilePath: dataFilePath))
        let document = FakeTextDocument()
        controller.document = document
        controller.activate(settings: settings)
        try body(controller, document)
      }
    }
  }

  @Test func refreshSuggestionKeepsToggling() throws {
    try withController { controller, document in
      controller.input("あ")
      // what a late AI result does: re-run the suggestion (a plain MOVE_CURSOR would end the toggle)
      let output = try #require(controller.engine.refreshSuggestion(cursor: 1))
      #expect(output.consumed)
      controller.input("あ")
      #expect(document.marked == "い")
    }
  }

  @Test func advanceEndsToggle() throws {
    try withController { controller, document in
      controller.input("あ")
      controller.perform(.advance)
      #expect(controller.togglingKey == nil)
      controller.input("あ")
      #expect(document.marked == "ああ")
    }
  }

  @Test func flickOnlyDoesNotToggle() throws {
    try withController(KeyboardSettings(flickOnly: true)) { controller, document in
      controller.input("あ")
      controller.input("あ")
      #expect(document.marked == "ああ")
      // nothing toggles, so no key stays highlighted after the tap
      #expect(controller.togglingKey == nil)
    }
  }

  @Test func toggleInput() throws {
    try withController { controller, document in
      controller.input("あ")
      #expect(document.marked == "あ")
      #expect(controller.togglingKey == "あ")
      controller.input("あ")
      #expect(document.marked == "い")
      controller.input("か")
      #expect(document.marked == "いか")
      #expect(controller.togglingKey == "か")
      // After "→" the same key starts a new character.
      controller.perform(.advance)
      #expect(controller.togglingKey == nil)
      controller.input("か")
      #expect(document.marked == "いかか")
      #expect(controller.isComposing)
    }
  }

  @Test func flickAndModifier() throws {
    try withController { controller, document in
      controller.input("つ")  // a flick of the た key
      controller.input("*")  // 小゛゜
      #expect(document.marked == "っ")
      controller.input("は")
      controller.input("]")  // handakuten flick
      #expect(document.marked == "っぱ")
    }
  }

  @Test func undoRewindsToggle() throws {
    try withController { controller, document in
      controller.input("あ")
      controller.input("あ")
      controller.input("あ")
      #expect(document.marked == "う")
      controller.perform(.undo)
      #expect(document.marked == "い")
    }
  }

  @Test func enterCommitsComposition() throws {
    try withController { controller, document in
      controller.input("あ")
      controller.perform(.enter)
      #expect(document.text == "あ")
      #expect(document.marked.isEmpty)
      #expect(!controller.isComposing)
    }
  }

  @Test func keysWithoutCompositionGetTheirDefaultAction() throws {
    try withController { controller, document in
      document.text = "abc"
      controller.perform(.backspace)
      #expect(document.text == "ab")
      controller.perform(.enter)
      #expect(document.text == "ab\n")
      controller.perform(.space)
      #expect(document.text == "ab\n ")
      controller.perform(.cursorLeft)
      #expect(document.cursorMoves == [-1])
    }
  }

  @Test func backspaceInComposition() throws {
    try withController { controller, document in
      controller.input("あ")
      controller.input("か")
      controller.perform(.backspace)
      #expect(document.marked == "あ")
      controller.perform(.backspace)
      #expect(document.marked.isEmpty)
      #expect(document.text.isEmpty)
      #expect(!controller.isComposing)
    }
  }

  @Test func conversionAndCandidateSelection() throws {
    try withController { controller, document in
      controller.input("か")
      #expect(controller.focusedCandidateID == nil)
      controller.perform(.space)
      #expect(!controller.candidates.isEmpty)
      let candidate = try #require(controller.candidates.first)
      #expect(controller.focusedCandidateID == candidate.id)
      controller.selectCandidate(candidate.id)
      #expect(document.text == candidate.value)
      #expect(document.marked.isEmpty)
    }
  }

  @Test func alphabetMode() throws {
    try withController { controller, document in
      controller.perform(.inputMode(.alphabet))
      #expect(controller.inputMode == .alphabet)
      controller.input("a")
      controller.input("a")
      #expect(document.marked == "b")
      controller.input("*")
      #expect(document.marked == "B")
      controller.perform(.inputMode(.hiragana))
      controller.input("あ")
      controller.perform(.enter)
      #expect(document.text == "Bあ")
    }
  }

  @Test func qwertyRomaji() throws {
    var settings = KeyboardSettings()
    settings.kanaLayout = .qwerty
    try withController(settings) { controller, document in
      for letter in ["k", "a", "n", "a", "-"] {
        controller.input(letter)
      }
      #expect(document.marked == "かなー")
      controller.commitComposition()
      #expect(document.text == "かなー")
    }
  }

  @Test func settingsRoundTrip() throws {
    try SystemUtil.withTempUserProfile { _ in
      #expect(KeyboardSettings.load() == KeyboardSettings())
      let settings = KeyboardSettings(kanaLayout: .qwerty, flickOnly: true, qwertyAlphabet: true, haptics: false)
      try settings.save()
      #expect(KeyboardSettings.load() == settings)
      #expect(settings.engineLayoutName == "QWERTY_JA")
      #expect(KeyboardSettings(flickOnly: true, qwertyAlphabet: true).engineLayoutName == "12KEYS_FLICKONLY_QWERTY")
    }
  }

  @Test func toolCommandQueue() throws {
    try SystemUtil.withTempUserProfile { _ in
      #expect(ToolCommandQueue.take().isEmpty)
      ToolCommandQueue.post("reload")
      ToolCommandQueue.post("clear_user_history")
      ToolCommandQueue.post("reload")
      #expect(ToolCommandQueue.take() == ["reload", "clear_user_history"])
      #expect(ToolCommandQueue.take().isEmpty)
    }
  }
}
