// Port of mozc/src/composer/key_parser_test.cc (3.35.6354).

import GenmaiProtocol
import Testing

@testable import GenmaiCore

private typealias KeyEvent = Genmai_Commands_KeyEvent

private func m(_ keys: Genmai_Commands_KeyEvent.ModifierKey...) -> UInt32 {
  keys.reduce(0) { $0 | UInt32($1.rawValue) }
}

private func ch(_ c: Unicode.Scalar) -> UInt32 { c.value }

@Suite struct KeyParserTest {
  @Test func keyCode() {
    var keyEvent = KeyEvent()

    #expect(KeyParser.parseKey("a", &keyEvent))
    #expect(keyEvent.keyCode == ch("a"))

    keyEvent = KeyEvent()
    #expect(KeyParser.parseKey("A", &keyEvent))
    #expect(keyEvent.keyCode == ch("A"))

    // "あ" (not half width)
    let kHiraganaA: UInt32 = 0x3042
    keyEvent = KeyEvent()
    #expect(KeyParser.parseKey("あ", &keyEvent))
    #expect(keyEvent.keyCode == kHiraganaA)
  }

  @Test func modifierKeys() {
    let kTestData: [(String, UInt32)] = [
      ("ctrl", m(.ctrl)),
      ("leftctrl", m(.ctrl, .leftCtrl)),
      ("rightctrl", m(.ctrl, .rightCtrl)),
      ("alt", m(.alt)),
      ("leftalt", m(.alt, .leftAlt)),
      ("rightalt", m(.alt, .rightAlt)),
      ("shift", m(.shift)),
      ("leftshift", m(.shift, .leftShift)),
      ("rightshift", m(.shift, .rightShift)),
      ("caps", m(.caps)),
      ("keydown", m(.keyDown)),
      ("keyup", m(.keyUp)),
      ("SHIFT", m(.shift)),
    ]

    for (name, modifiers) in kTestData {
      var keyEvent = KeyEvent()
      #expect(KeyParser.parseKey(name, &keyEvent), "\(name)")
      #expect(KeyEventUtil.getModifiers(keyEvent) == modifiers, "\(name)")
    }
  }

  @Test func multipleModifierKeys() {
    var keyEvent = KeyEvent()
    #expect(KeyParser.parseKey("LeftCtrl RightCtrl", &keyEvent))
    #expect(keyEvent.modifierKeys.count == 3)
    #expect(KeyEventUtil.getModifiers(keyEvent) == m(.ctrl, .leftCtrl, .rightCtrl))
  }

  @Test func specialKeys() {
    let kTestData: [(String, KeyEvent.SpecialKey)] = [
      ("on", .on),
      ("off", .off),
      ("left", .left),
      ("down", .down),
      ("up", .up),
      ("right", .right),
      ("enter", .enter),
      ("return", .enter),
      ("esc", .escape),
      ("escape", .escape),
      ("delete", .del),
      ("del", .del),
      ("bs", .backspace),
      ("backspace", .backspace),
      ("henkan", .henkan),
      ("muhenkan", .muhenkan),
      ("kana", .kana),
      ("hiragana", .kana),
      ("katakana", .katakana),
      ("eisu", .eisu),
      ("home", .home),
      ("end", .end),
      ("space", .space),
      ("ascii", .textInput),
      ("textinput", .textInput),
      ("tab", .tab),
      ("pageup", .pageUp),
      ("pagedown", .pageDown),
      ("insert", .insert),
      ("hankaku", .hankaku),
      ("zenkaku", .hankaku),
      ("hankaku/zenkaku", .hankaku),
      ("kanji", .kanji),
      ("f1", .f1),
      ("f2", .f2),
      ("f3", .f3),
      ("f4", .f4),
      ("f5", .f5),
      ("f6", .f6),
      ("f7", .f7),
      ("f8", .f8),
      ("f9", .f9),
      ("f10", .f10),
      ("f11", .f11),
      ("f12", .f12),
      ("f13", .f13),
      ("f14", .f14),
      ("f15", .f15),
      ("f16", .f16),
      ("f17", .f17),
      ("f18", .f18),
      ("f19", .f19),
      ("f20", .f20),
      ("f21", .f21),
      ("f22", .f22),
      ("f23", .f23),
      ("f24", .f24),
      ("numpad0", .numpad0),
      ("numpad1", .numpad1),
      ("numpad2", .numpad2),
      ("numpad3", .numpad3),
      ("numpad4", .numpad4),
      ("numpad5", .numpad5),
      ("numpad6", .numpad6),
      ("numpad7", .numpad7),
      ("numpad8", .numpad8),
      ("numpad9", .numpad9),
      ("multiply", .multiply),
      ("add", .add),
      ("separator", .separator),
      ("subtract", .subtract),
      ("decimal", .decimal),
      ("divide", .divide),
      ("equals", .equals),
      ("comma", .comma),
      ("on", .on),
    ]

    for (name, specialKey) in kTestData {
      var keyEvent = KeyEvent()
      #expect(KeyParser.parseKey(name, &keyEvent), "\(name)")
      #expect(keyEvent.specialKey == specialKey, "\(name)")
    }
  }

  @Test func combination() {
    var keyEvent = KeyEvent()

    #expect(KeyParser.parseKey("LeftShift CTRL a", &keyEvent))
    #expect(keyEvent.keyCode == ch("a"))
    #expect(KeyEventUtil.getModifiers(keyEvent) == m(.leftShift, .shift, .ctrl))

    #expect(KeyParser.parseKey("rightalt On", &keyEvent))
    #expect(keyEvent.specialKey == .on)
    #expect(KeyEventUtil.getModifiers(keyEvent) == m(.rightAlt, .alt))

    #expect(KeyParser.parseKey("SHIFT on a", &keyEvent))
    #expect(keyEvent.keyCode == ch("a"))
    #expect(keyEvent.specialKey == .on)
    #expect(KeyEventUtil.getModifiers(keyEvent) == m(.shift))

    #expect(KeyParser.parseKey("alt a", &keyEvent))
    #expect(keyEvent.keyCode == ch("a"))
    #expect(!keyEvent.hasSpecialKey)
    #expect(KeyEventUtil.getModifiers(keyEvent) == m(.alt))

    // meta and hyper are identical to alt.
    #expect(KeyParser.parseKey("a meta hyper", &keyEvent))
    #expect(keyEvent.keyCode == ch("a"))
    #expect(!keyEvent.hasSpecialKey)
    #expect(KeyEventUtil.getModifiers(keyEvent) == m(.alt))

    // multiple keys are not supported.
    #expect(!KeyParser.parseKey("a alt z", &keyEvent))

    // multiple special keys are not supported.
    #expect(!KeyParser.parseKey("muhenkan backspace", &keyEvent))
  }

  @Test func getSpecialKeyString() {
    // Strings are defined in gui/config_dialog/keybinding_editor.cc
    #expect(KeyEvent.SpecialKey.numSpecialkeys.rawValue == 78)
    #expect(KeyParser.getSpecialKeyString(.on) == "on")
    #expect(KeyParser.getSpecialKeyString(.off) == "off")
    #expect(KeyParser.getSpecialKeyString(.left) == "left")
    #expect(KeyParser.getSpecialKeyString(.down) == "down")
    #expect(KeyParser.getSpecialKeyString(.up) == "up")
    #expect(KeyParser.getSpecialKeyString(.right) == "right")
    #expect(KeyParser.getSpecialKeyString(.enter) == "enter")
    #expect(KeyParser.getSpecialKeyString(.escape) == "escape")
    #expect(KeyParser.getSpecialKeyString(.del) == "delete")
    #expect(KeyParser.getSpecialKeyString(.backspace) == "backspace")
    #expect(KeyParser.getSpecialKeyString(.henkan) == "henkan")
    #expect(KeyParser.getSpecialKeyString(.muhenkan) == "muhenkan")
    #expect(KeyParser.getSpecialKeyString(.kana) == "hiragana")
    #expect(KeyParser.getSpecialKeyString(.katakana) == "katakana")
    #expect(KeyParser.getSpecialKeyString(.eisu) == "eisu")
    #expect(KeyParser.getSpecialKeyString(.home) == "home")
    #expect(KeyParser.getSpecialKeyString(.end) == "end")
    #expect(KeyParser.getSpecialKeyString(.space) == "space")
    #expect(KeyParser.getSpecialKeyString(.textInput) == "textinput")
    #expect(KeyParser.getSpecialKeyString(.tab) == "tab")
    #expect(KeyParser.getSpecialKeyString(.pageUp) == "pageup")
    #expect(KeyParser.getSpecialKeyString(.pageDown) == "pagedown")
    #expect(KeyParser.getSpecialKeyString(.insert) == "insert")
    #expect(KeyParser.getSpecialKeyString(.hankaku) == "hankaku/zenkaku")
    #expect(KeyParser.getSpecialKeyString(.kanji) == "kanji")
    #expect(KeyParser.getSpecialKeyString(.f1) == "f1")
    #expect(KeyParser.getSpecialKeyString(.f2) == "f2")
    #expect(KeyParser.getSpecialKeyString(.f3) == "f3")
    #expect(KeyParser.getSpecialKeyString(.f4) == "f4")
    #expect(KeyParser.getSpecialKeyString(.f5) == "f5")
    #expect(KeyParser.getSpecialKeyString(.f6) == "f6")
    #expect(KeyParser.getSpecialKeyString(.f7) == "f7")
    #expect(KeyParser.getSpecialKeyString(.f8) == "f8")
    #expect(KeyParser.getSpecialKeyString(.f9) == "f9")
    #expect(KeyParser.getSpecialKeyString(.f10) == "f10")
    #expect(KeyParser.getSpecialKeyString(.f11) == "f11")
    #expect(KeyParser.getSpecialKeyString(.f12) == "f12")
    #expect(KeyParser.getSpecialKeyString(.f13) == "f13")
    #expect(KeyParser.getSpecialKeyString(.f14) == "f14")
    #expect(KeyParser.getSpecialKeyString(.f15) == "f15")
    #expect(KeyParser.getSpecialKeyString(.f16) == "f16")
    #expect(KeyParser.getSpecialKeyString(.f17) == "f17")
    #expect(KeyParser.getSpecialKeyString(.f18) == "f18")
    #expect(KeyParser.getSpecialKeyString(.f19) == "f19")
    #expect(KeyParser.getSpecialKeyString(.f20) == "f20")
    #expect(KeyParser.getSpecialKeyString(.f21) == "f21")
    #expect(KeyParser.getSpecialKeyString(.f22) == "f22")
    #expect(KeyParser.getSpecialKeyString(.f23) == "f23")
    #expect(KeyParser.getSpecialKeyString(.f24) == "f24")
    #expect(KeyParser.getSpecialKeyString(.numpad0) == "numpad0")
    #expect(KeyParser.getSpecialKeyString(.numpad1) == "numpad1")
    #expect(KeyParser.getSpecialKeyString(.numpad2) == "numpad2")
    #expect(KeyParser.getSpecialKeyString(.numpad3) == "numpad3")
    #expect(KeyParser.getSpecialKeyString(.numpad4) == "numpad4")
    #expect(KeyParser.getSpecialKeyString(.numpad5) == "numpad5")
    #expect(KeyParser.getSpecialKeyString(.numpad6) == "numpad6")
    #expect(KeyParser.getSpecialKeyString(.numpad7) == "numpad7")
    #expect(KeyParser.getSpecialKeyString(.numpad8) == "numpad8")
    #expect(KeyParser.getSpecialKeyString(.numpad9) == "numpad9")
    #expect(KeyParser.getSpecialKeyString(.multiply) == "multiply")
    #expect(KeyParser.getSpecialKeyString(.add) == "add")
    #expect(KeyParser.getSpecialKeyString(.separator) == "separator")
    #expect(KeyParser.getSpecialKeyString(.subtract) == "subtract")
    #expect(KeyParser.getSpecialKeyString(.decimal) == "decimal")
    #expect(KeyParser.getSpecialKeyString(.divide) == "divide")
    #expect(KeyParser.getSpecialKeyString(.equals) == "equals")
    #expect(KeyParser.getSpecialKeyString(.comma) == "comma")
    #expect(KeyParser.getSpecialKeyString(.clear) == "clear")
    #expect(KeyParser.getSpecialKeyString(.virtualLeft) == "virtualleft")
    #expect(KeyParser.getSpecialKeyString(.virtualRight) == "virtualright")
    #expect(KeyParser.getSpecialKeyString(.virtualEnter) == "virtualenter")
    #expect(KeyParser.getSpecialKeyString(.virtualUp) == "virtualup")
    #expect(KeyParser.getSpecialKeyString(.virtualDown) == "virtualdown")
    #expect(KeyParser.getSpecialKeyString(.imeAction) == "imeaction")
    #expect(KeyParser.getSpecialKeyString(.undefinedKey) == "undefinedkey")
  }
}
