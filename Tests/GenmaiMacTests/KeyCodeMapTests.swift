// Port of mozc/src/mac/KeyCodeMap_test.mm (3.35.6354).
//
// The C++ compares TextFormat debug strings; here the expected KeyEvent messages are built directly.

import AppKit
import Carbon
import GenmaiClient
import GenmaiProtocol
import Testing

@testable import GenmaiMac

private struct TestCase {
  let title: String
  let characters: String?
  let unmodCharacters: String?
  let flags: NSEvent.ModifierFlags
  let keyCode: Int
  let expected: KeyEvent
}

private func key(
  code: Character? = nil, special: Genmai_Commands_KeyEvent.SpecialKey? = nil,
  modifiers: [Genmai_Commands_KeyEvent.ModifierKey] = [], keyString: String? = nil
) -> KeyEvent {
  var event = KeyEvent()
  if let code {
    event.keyCode = code.unicodeScalars.first.map { UInt32($0.value) } ?? 0
  }
  if let special {
    event.specialKey = special
  }
  event.modifierKeys = modifiers
  if let keyString {
    event.keyString = keyString
  }
  return event
}

@MainActor
private func createKeyEvent(
  _ map: KeyCodeMap, _ characters: String?, _ unmodCharacters: String?,
  _ flags: NSEvent.ModifierFlags, _ keyCode: Int, _ genmaiKeyEvent: inout KeyEvent
) -> Bool {
  // if the key event is just pressing modifiers, the type should be NSFlagsChanged.
  let type: KeyEventData.EventType =
    characters == nil && unmodCharacters == nil ? .flagsChanged : .keyDown
  let chars = characters ?? ""
  let unmod = unmodCharacters ?? chars
  let event = KeyEventData(
    type: type, characters: chars, charactersIgnoringModifiers: unmod, modifierFlags: flags,
    keyCode: UInt16(keyCode))
  return map.getGenmaiKeyCodeFromKeyEvent(event, &genmaiKeyEvent)
}

@MainActor
@Suite struct KeyCodeMapTests {
  // Test for romaji typing
  @Test func normaKeyEvent() {
    let testCases = [
      TestCase(
        title: "normal a", characters: "a", unmodCharacters: nil, flags: [], keyCode: kVK_ANSI_A,
        expected: key(code: "a")),
      TestCase(
        title: "\\S-a", characters: "A", unmodCharacters: "a", flags: .shift, keyCode: kVK_ANSI_A,
        expected: key(code: "A")),
      TestCase(
        title: "\\C-a", characters: "\u{01}", unmodCharacters: "a", flags: .control, keyCode: kVK_ANSI_A,
        expected: key(code: "a", modifiers: [.ctrl])),
      TestCase(
        title: "\\S-C-a", characters: "a", unmodCharacters: nil, flags: [.control, .shift], keyCode: kVK_ANSI_A,
        expected: key(code: "a", modifiers: [.shift, .ctrl])),
      TestCase(
        title: "Tab key", characters: "\u{09}", unmodCharacters: nil, flags: [], keyCode: kVK_Tab,
        expected: key(special: .tab)),
      TestCase(
        title: "\\S-Tab", characters: "\u{09}", unmodCharacters: nil, flags: .shift, keyCode: kVK_Tab,
        expected: key(special: .tab, modifiers: [.shift])),
      TestCase(
        title: "function key", characters: "\u{10}", unmodCharacters: nil, flags: [], keyCode: kVK_F1,
        expected: key(special: .f1)),
      TestCase(
        title: "tenkey", characters: "0", unmodCharacters: nil, flags: [], keyCode: kVK_ANSI_Keypad0,
        expected: key(special: .numpad0)),
    ]
    let map = KeyCodeMap()
    for testCase in testCases {
      var event = KeyEvent()
      #expect(
        createKeyEvent(map, testCase.characters, testCase.unmodCharacters, testCase.flags, testCase.keyCode, &event))
      #expect(event == testCase.expected, Comment(rawValue: testCase.title))
    }
  }

  // Test for kana typing
  @Test func kanaEvent() {
    let testCases = [
      TestCase(
        title: "a -> ち", characters: "a", unmodCharacters: nil, flags: [], keyCode: kVK_ANSI_A,
        expected: key(code: "a", keyString: "ち")),
      TestCase(
        title: "yen mark", characters: "¥", unmodCharacters: nil, flags: [], keyCode: kVK_JIS_Yen,
        expected: key(code: "\\", keyString: "ー")),
      TestCase(
        title: "\\S-2 -> ふ", characters: "@", unmodCharacters: "2", flags: .shift, keyCode: kVK_ANSI_2,
        expected: key(code: "@", keyString: "ふ")),
      TestCase(
        title: "\\C-a -> \\C-a", characters: "\u{01}", unmodCharacters: "a", flags: .control, keyCode: kVK_ANSI_A,
        expected: key(code: "a", modifiers: [.ctrl], keyString: "ち")),
      TestCase(
        title: "\\S-0 -> を", characters: "0", unmodCharacters: nil, flags: .shift, keyCode: kVK_ANSI_0,
        expected: key(code: "0", keyString: "を")),
      TestCase(
        title: "yen mark -> ー", characters: "￥", unmodCharacters: nil, flags: [], keyCode: kVK_JIS_Yen,
        expected: key(keyString: "ー")),
      TestCase(
        title: "underscore -> ろ", characters: "_", unmodCharacters: nil, flags: [], keyCode: kVK_JIS_Underscore,
        expected: key(code: "_", keyString: "ろ")),
      TestCase(
        title: "@ -> ゛ in JIS keyboard", characters: "@", unmodCharacters: nil, flags: [],
        keyCode: kVK_ANSI_LeftBracket, expected: key(code: "@", keyString: "゛")),
      TestCase(
        title: "[ -> ゛ in US keyboard", characters: "[", unmodCharacters: nil, flags: [], keyCode: kVK_ANSI_LeftBracket,
        expected: key(code: "[", keyString: "゛")),
    ]
    let map = KeyCodeMap()
    map.inputMode = .kana
    for testCase in testCases {
      var event = KeyEvent()
      #expect(
        createKeyEvent(map, testCase.characters, testCase.unmodCharacters, testCase.flags, testCase.keyCode, &event))
      #expect(event == testCase.expected, Comment(rawValue: testCase.title))
    }
  }

  // Test for modifier key events
  @Test func modifiers() {
    let map = KeyCodeMap()
    var event = KeyEvent()
    // Press shift key
    #expect(!createKeyEvent(map, nil, nil, .shift, kVK_Shift, &event))

    // Release the shift key -> emit Shift-key event
    event = KeyEvent()
    #expect(createKeyEvent(map, nil, nil, [], kVK_Shift, &event))
    #expect(event == key(modifiers: [.shift]))

    // Press shift key
    event = KeyEvent()
    #expect(!createKeyEvent(map, nil, nil, .shift, kVK_Shift, &event))

    // Press control key
    event = KeyEvent()
    #expect(!createKeyEvent(map, nil, nil, [.shift, .control], kVK_Control, &event))

    // Release shift key
    event = KeyEvent()
    #expect(!createKeyEvent(map, nil, nil, .control, kVK_Control, &event))

    // Release control key -> emit Control + Shift
    event = KeyEvent()
    #expect(createKeyEvent(map, nil, nil, [], kVK_Control, &event))
    #expect(event == key(modifiers: [.shift, .ctrl]))

    // Press control key
    event = KeyEvent()
    #expect(!createKeyEvent(map, nil, nil, .control, kVK_Control, &event))

    // Press a -> emit \C-a
    event = KeyEvent()
    #expect(createKeyEvent(map, "a", nil, .control, kVK_ANSI_A, &event))
    #expect(event == key(code: "a", modifiers: [.ctrl]))

    // Release control key -> Doesn't emit any key events
    event = KeyEvent()
    #expect(!createKeyEvent(map, nil, nil, [], kVK_Control, &event))
  }

  // Swift-only: a real NSEvent goes through KeyEventData unchanged.
  @Test func fromNSEvent() throws {
    let nsEvent = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .shift, timestamp: 0, windowNumber: 0,
        context: nil, characters: "A", charactersIgnoringModifiers: "a", isARepeat: false,
        keyCode: UInt16(kVK_ANSI_A)))
    let data = KeyEventData(nsEvent)
    #expect(data.type == .keyDown)
    #expect(data.characters == "A")
    #expect(KeyCodeMap().getGenmaiKeyEvent(data) == key(code: "A"))
  }

  @Test func commandKeyIsIgnored() {
    var event = KeyEvent()
    #expect(!createKeyEvent(KeyCodeMap(), "c", nil, .command, kVK_ANSI_C, &event))
  }

  @Test func modeSwitchingKey() {
    let map = KeyCodeMap()
    let eisu = KeyEventData(
      type: .keyDown, characters: " ", charactersIgnoringModifiers: " ", modifierFlags: [],
      keyCode: UInt16(kVK_JIS_Eisu))
    let kana = KeyEventData(
      type: .keyDown, characters: " ", charactersIgnoringModifiers: " ", modifierFlags: [],
      keyCode: UInt16(kVK_JIS_Kana))
    let a = KeyEventData(
      type: .keyDown, characters: "a", charactersIgnoringModifiers: "a", modifierFlags: [], keyCode: UInt16(kVK_ANSI_A))
    #expect(map.isModeSwitchingKey(eisu))
    #expect(map.isModeSwitchingKey(kana))
    #expect(!map.isModeSwitchingKey(a))
  }
}
