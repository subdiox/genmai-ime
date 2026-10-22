// End-to-end tests of the IME logic (not a port of a C++ test).
//
// `GenmaiInputController` (everything GenmaiImkInputController does) is driven with real key events
// (`KeyEventData` as built from NSEvent: virtual key code + characters) through `KeyCodeMap`, an
// `InProcessClient` and the real conversion server (`SessionHandlerBackend`: Engine with the OSS data set +
// SessionHandler). The text client and the renderer are recording doubles. Each test runs with a temporary
// user profile and a fresh ConfigHandler / CharacterFormManager, so the user's data is never touched.

import AppKit
import Carbon
import Foundation
import GenmaiBase
import GenmaiClient
import GenmaiCore
import GenmaiProtocol
import GenmaiRenderer
import GenmaiSession
import Testing

@testable import GenmaiMac

/// US / JIS (kana layout) virtual key codes of the printable keys used below.
private let kKeyCodes: [Character: Int] = [
  "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
  "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
  "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
  "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
  "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
  "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
  "-": kVK_ANSI_Minus, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period,
]

private var ossDataAvailable: Bool {
  FileManager.default.fileExists(atPath: OssDataManager.defaultDataPath)
}

/// Runs `body` with a temporary user profile and fresh config / character form singletons.
@MainActor
private func withIMEEnvironment(_ body: @MainActor () async throws -> Void) async throws {
  try await SystemUtil.withTempUserProfile { _ in
    try await ConfigHandler.withScopedHandlerForTesting {
      try await CharacterFormManager.withScopedManagerForTesting {
        try await body()
      }
    }
  }
}

@MainActor
final class IMEFixture {
  let backend: SessionHandlerBackend
  let client: InProcessClient
  let textClient = MockTextInputClient()
  let renderer = MockRenderer()
  let toolLauncher = MockAppLauncher()
  let controller: GenmaiInputController
  private(set) var committed: [String] = []
  private var lastInsertCount = 0

  init() throws {
    backend = SessionHandlerBackend()
    try #require(backend.isAvailable, "the OSS engine failed to load: \(String(describing: backend.loadError))")
    client = InProcessClient.make(backend: backend)
    textClient.bundleID = "com.example.TextEdit"
    let textClient = self.textClient
    controller = GenmaiInputController(
      genmaiClient: client, renderer: renderer, currentClient: { textClient }, toolLauncher: toolLauncher,
      urlOpener: { _ in }, selectionRangeFallback: { NSRange(location: NSNotFound, length: 0) },
      now: { 0 }, frontmostWindow: { nil })
    controller.activateServer(textClient)
    // The user selects "Hiragana" in the input menu.
    controller.setValue(kHiraganaModeId, client: textClient)
  }

  /// The marked text the application shows.
  var marked: String { controller.composedString.string }

  /// The candidate window the renderer was asked to show (after the delayed update ran).
  func candidateWindow() async -> Genmai_Commands_CandidateWindow? {
    await controller.waitForPendingCandidateUpdates()
    let command = renderer.calledCommand
    guard command.visible, !command.output.candidateWindow.candidate.isEmpty else { return nil }
    return command.output.candidateWindow
  }

  func candidateValues() async -> [String] {
    await candidateWindow()?.candidate.map(\.value) ?? []
  }

  @discardableResult
  func press(_ keyCode: Int, _ characters: String = "", modifiers: NSEvent.ModifierFlags = []) -> Bool {
    let event = KeyEventData(
      type: .keyDown, characters: characters, charactersIgnoringModifiers: characters,
      modifierFlags: modifiers, keyCode: UInt16(keyCode))
    let consumed = controller.handleEvent(event, client: textClient)
    recordInsertion()
    return consumed
  }

  /// Types `text` on the US layout (or the JIS kana layout in kana input mode).
  @discardableResult
  func type(_ text: String) -> [Bool] {
    text.map { c in
      let keyCode = kKeyCodes[c]!
      return press(keyCode, String(c))
    }
  }

  @discardableResult func space() -> Bool { press(kVK_Space, " ") }
  @discardableResult func enter() -> Bool { press(kVK_Return, "\r") }
  @discardableResult func escape() -> Bool { press(kVK_Escape, "\u{1b}") }
  @discardableResult func backspace() -> Bool { press(kVK_Delete, "\u{7f}") }
  @discardableResult func down() -> Bool { press(kVK_DownArrow, "\u{f701}") }
  @discardableResult func function(_ keyCode: Int) -> Bool { press(keyCode, "\u{f709}") }

  private func recordInsertion() {
    let count = textClient.getCounter("insertText:replacementRange:")
    if count != lastInsertCount, let text = textClient.insertedText {
      committed.append(text)
    }
    lastInsertCount = count
  }
}

@MainActor
@Suite(.serialized, .enabled(if: ossDataAvailable, "Data/genmai.data is missing (run Tools/build_oracle.sh)"))
struct IMEIntegrationTests {
  @Test func convertAndCommitSentence() async throws {
    try await withIMEEnvironment {
      let ime = try IMEFixture()
      #expect(ime.controller.mode == .hiragana)
      #expect(ime.type("kyouhahayamenikaerimasu").allSatisfy { $0 })
      #expect(ime.marked == "きょうははやめにかえります")
      #expect(ime.committed.isEmpty)

      #expect(ime.space())
      #expect(ime.marked == "今日は早めに帰ります")
      // The focused segment is highlighted (thick underline), the others are underlined.
      let style = ime.controller.composedString.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int
      #expect(style == NSUnderlineStyle.thick.rawValue)

      // The second space opens the candidate window of the first segment.
      #expect(ime.space())
      let window = try #require(await ime.candidateWindow())
      #expect(window.candidate.count > 3)
      #expect(window.candidate.map(\.value).contains("今日は"))
      #expect(window.category == .conversion)
      // Back to the first candidate and commit.
      _ = ime.press(kVK_UpArrow, "\u{f700}")
      #expect(ime.marked == "今日は早めに帰ります")
      #expect(ime.enter())
      #expect(ime.committed == ["今日は早めに帰ります"])
      #expect(ime.marked.isEmpty)
      #expect(await ime.candidateWindow() == nil)
    }
  }

  @Test func cancelAndBackspace() async throws {
    try await withIMEEnvironment {
      let ime = try IMEFixture()
      ime.type("aiueo")
      #expect(ime.marked == "あいうえお")
      #expect(ime.backspace())
      #expect(ime.marked == "あいうえ")
      #expect(ime.escape())
      #expect(ime.marked.isEmpty)
      #expect(ime.committed.isEmpty)

      // Cancel during conversion goes back to the composition.
      ime.type("henkan")
      #expect(ime.space())
      #expect(ime.marked == "変換")
      #expect(ime.escape())
      // The pending "n" is displayed as typed again (as in Mozc).
      #expect(ime.marked == "へんかｎ")
      #expect(ime.escape())
      #expect(ime.marked.isEmpty)
      // Nothing to cancel: the key goes to the application.
      #expect(!ime.escape())
      #expect(ime.committed.isEmpty)
    }
  }

  @Test func functionKeyTransliterations() async throws {
    try await withIMEEnvironment {
      let ime = try IMEFixture()
      ime.type("nihongo")
      #expect(ime.function(kVK_F7))
      #expect(ime.marked == "ニホンゴ")
      #expect(ime.function(kVK_F6))
      #expect(ime.marked == "にほんご")
      #expect(ime.function(kVK_F8))
      #expect(ime.marked == "ﾆﾎﾝｺﾞ")
      #expect(ime.function(kVK_F9))
      #expect(ime.marked == "ｎｉｈｏｎｇｏ")
      #expect(ime.function(kVK_F10))
      #expect(ime.marked == "nihongo")
      #expect(ime.enter())
      #expect(ime.committed == ["nihongo"])
    }
  }

  @Test func suggestionWhileTyping() async throws {
    try await withIMEEnvironment {
      let ime = try IMEFixture()
      ime.type("arigat")
      ime.type("ou")
      #expect(ime.marked == "ありがとう")
      let window = try #require(await ime.candidateWindow())
      #expect(window.category == .suggestion)
      #expect(window.candidate.map(\.value).contains("ありがとうございます"))
      // Tab / Down moves into the predictions.
      #expect(ime.press(kVK_Tab, "\t"))
      let prediction = try #require(await ime.candidateWindow())
      #expect(prediction.category == .prediction)
      #expect(ime.escape())
      #expect(ime.escape())
      #expect(ime.marked.isEmpty)
    }
  }

  @Test func userHistoryLearning() async throws {
    try await withIMEEnvironment {
      let ime = try IMEFixture()
      ime.type("kisya")
      #expect(ime.space())
      let first = ime.marked
      #expect(ime.space())  // opens the window, focus on the 2nd candidate
      let window = try #require(await ime.candidateWindow())
      let values = window.candidate.map(\.value)
      #expect(values.count >= 3)
      #expect(values.first == first)
      // Pick a candidate that is not the top one (the third, to be different from the default 2nd).
      #expect(ime.space())
      let chosen = ime.marked
      #expect(chosen != first)
      #expect(ime.enter())
      #expect(ime.committed == [chosen])

      // The same reading now converts to the learned word first.
      ime.type("kisya")
      #expect(ime.space())
      #expect(ime.marked == chosen)
      #expect(ime.enter())
      #expect(ime.committed == [chosen, chosen])

      // The learning survives SYNC_DATA + RELOAD (written to and read back from the temporary profile).
      #expect(await ime.backend.syncData())
      #expect(ime.backend.reload())
      ime.type("kisya")
      #expect(ime.space())
      #expect(ime.marked == chosen)
      #expect(ime.escape())
      #expect(ime.escape())
    }
  }

  @Test func inputModes() async throws {
    try await withIMEEnvironment {
      let ime = try IMEFixture()
      // Katakana mode.
      ime.controller.setValue(kKatakanaModeId, client: ime.textClient)
      #expect(ime.controller.mode == .fullKatakana)
      ime.type("kana")
      #expect(ime.marked == "カナ")
      #expect(ime.enter())
      #expect(ime.committed == ["カナ"])

      // Full-width alphanumeric.
      ime.controller.setValue(kFullWidthRomanModeId, client: ime.textClient)
      ime.type("abc")
      #expect(ime.marked == "ａｂｃ")
      #expect(ime.enter())
      #expect(ime.committed.last == "ａｂｃ")

      // Roman (direct): keys go to the application.
      ime.controller.setValue(kRomanModeId, client: ime.textClient)
      #expect(ime.controller.mode == .direct)
      #expect(ime.type("abc") == [false, false, false])
      #expect(ime.marked.isEmpty)

      // Back to Hiragana by the KANA key (handled by the controller itself).
      #expect(ime.press(kVK_JIS_Kana, ""))
      #expect(ime.controller.mode == .hiragana)
      ime.type("a")
      #expect(ime.marked == "あ")
      // EISU switches to half alphanumeric within the composition.
      _ = ime.press(kVK_JIS_Eisu, "")
      #expect(ime.controller.mode == .halfAscii)
      ime.type("b")
      #expect(ime.marked == "あb")
      #expect(ime.enter())
      #expect(ime.committed.last == "あb")
    }
  }

  @Test func kanaInput() async throws {
    try await withIMEEnvironment {
      let ime = try IMEFixture()
      var config = try #require(ime.client.getConfig())
      config.preeditMethod = .kana
      #expect(ime.client.setConfig(config))
      ime.controller.handleConfig()
      #expect(ime.controller.keyCodeMap.inputMode == .kana)
      // JIS kana layout: T = か, U = な, 3 = あ.
      ime.type("tu3")
      #expect(ime.marked == "かなあ")
      #expect(ime.backspace())
      #expect(ime.space())
      #expect(ime.marked == "仮名" || ime.marked == "かな")
      #expect(ime.enter())
      #expect(ime.committed.count == 1)
    }
  }

  @Test func reloadNotificationAndDirectModeKeys() async throws {
    try await withIMEEnvironment {
      let ime = try IMEFixture()
      // GenmaiApp writes the config file and posts RELOAD: the server re-reads it.
      var config = ConfigHandler.getCopiedConfig()
      config.incognitoMode = true
      ConfigHandler.setConfig(config)
      #expect(ime.backend.reload())
      #expect(ime.client.getConfig()?.incognitoMode == true)
      // The default (Kotoeri) keymap turns the IME on with the Kanji / ON keys in the direct mode.
      var on = KeyEvent()
      on.specialKey = .on
      #expect(ime.client.isDirectModeCommand(on))
      var a = KeyEvent()
      a.keyCode = UInt32(UInt8(ascii: "a"))
      #expect(!ime.client.isDirectModeCommand(a))
    }
  }
}
