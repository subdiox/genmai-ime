// Port of mozc/src/session/key_event_transformer_test.cc (3.35.6354).

import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import Testing

@testable import GenmaiSession

/// IsKeyEventTransformerEq: nil on success, failure message otherwise.
private func isKeyEventTransformerEq(_ x: KeyEventTransformer, _ y: KeyEventTransformer)
  -> String?
{
  if x.table.count != y.table.count {
    return "Table size differs"
  }
  for (key, event) in x.table {
    guard let other = y.table[key] else {
      return "Key doesn't exist in RHS: key = \(key)"
    }
    if event != other {
      return "Value mismatch for key = \(key)"
    }
  }
  if x.numpadCharacterForm != y.numpadCharacterForm {
    return
      "numpad_character_form is different: \(x.numpadCharacterForm) vs \(y.numpadCharacterForm)"
  }
  return nil
}

private func testNumpadTransformation(
  _ table: KeyEventTransformer, _ input: Genmai_Commands_KeyEvent.SpecialKey,
  _ expectedKeyCode: Character, _ expectedKeyString: String,
  _ expectedStyle: Genmai_Commands_KeyEvent.InputStyle,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  var keyEvent = Genmai_Commands_KeyEvent()
  keyEvent.specialKey = input
  #expect(table.transformKeyEvent(&keyEvent), sourceLocation: sourceLocation)

  guard keyEvent.hasKeyCode, keyEvent.hasKeyString, !keyEvent.hasSpecialKey else {
    Issue.record("unexpected key event: \(keyEvent)", sourceLocation: sourceLocation)
    return
  }
  #expect(keyEvent.keyCode == expectedKeyCode.asciiValue.map(UInt32.init), sourceLocation: sourceLocation)
  #expect(keyEvent.keyString == expectedKeyString, sourceLocation: sourceLocation)
  #expect(keyEvent.inputStyle == expectedStyle, sourceLocation: sourceLocation)
}

private func testKanaTransformation(
  _ table: KeyEventTransformer, _ keyString: String, _ expectedKeyCode: Character,
  _ expectedKeyString: String, sourceLocation: SourceLocation = #_sourceLocation
) {
  var keyEvent = Genmai_Commands_KeyEvent()
  keyEvent.keyString = keyString

  if keyString == expectedKeyString {
    // Should not transform key_event.
    #expect(!table.transformKeyEvent(&keyEvent), sourceLocation: sourceLocation)
    return
  }

  guard table.transformKeyEvent(&keyEvent) else {
    Issue.record("not transformed: \(keyString)", sourceLocation: sourceLocation)
    return
  }
  guard keyEvent.hasKeyString, !keyEvent.hasSpecialKey else {
    Issue.record("unexpected key event: \(keyString)", sourceLocation: sourceLocation)
    return
  }
  #expect(keyEvent.keyString == expectedKeyString, "\(keyString)", sourceLocation: sourceLocation)
  #expect(
    keyEvent.keyCode == expectedKeyCode.asciiValue.map(UInt32.init), "\(keyString)",
    sourceLocation: sourceLocation)
}

@Suite struct KeyEventTransformerTests {
  @Test func numpad() {
    var table = KeyEventTransformer()

    do {  // "Separator to Enter"
      var keyEvent = Genmai_Commands_KeyEvent()
      keyEvent.specialKey = .separator
      #expect(table.transformKeyEvent(&keyEvent))

      #expect(keyEvent.hasSpecialKey)
      #expect(!keyEvent.hasKeyCode)
      #expect(keyEvent.specialKey == .enter)
    }

    do {  // NUMPAD_INPUT_MODE
      var config = Genmai_Config_Config()
      config.numpadCharacterForm = .numpadInputMode
      table.reloadConfig(config)
      testNumpadTransformation(table, .numpad0, "0", "０", .followMode)
      testNumpadTransformation(table, .equals, "=", "＝", .followMode)
    }

    do {  // NUMPAD_FULL_WIDTH
      var config = Genmai_Config_Config()
      config.numpadCharacterForm = .numpadFullWidth
      table.reloadConfig(config)
      testNumpadTransformation(table, .numpad0, "0", "０", .asIs)
      testNumpadTransformation(table, .equals, "=", "＝", .asIs)
    }

    do {  // NUMPAD_HALF_WIDTH
      var config = Genmai_Config_Config()
      config.numpadCharacterForm = .numpadHalfWidth
      table.reloadConfig(config)
      testNumpadTransformation(table, .numpad0, "0", "0", .asIs)
      testNumpadTransformation(table, .equals, "=", "=", .asIs)
    }

    do {  // NUMPAD_DIRECT_INPUT
      var config = Genmai_Config_Config()
      config.numpadCharacterForm = .numpadDirectInput
      table.reloadConfig(config)
      testNumpadTransformation(table, .numpad0, "0", "0", .directInput)
      testNumpadTransformation(table, .equals, "=", "=", .directInput)
    }
  }

  @Test func kana() {
    var table = KeyEventTransformer()

    do {  // Punctuation
      let kFullKuten = "、"
      let kFullTouten = "。"
      let kFullComma = "，"
      let kFullPeriod = "．"

      do {  // TOUTEN_KUTEN
        var config = Genmai_Config_Config()
        config.punctuationMethod = .toutenKuten
        table.reloadConfig(config)
        testKanaTransformation(table, kFullKuten, ",", kFullKuten)
        testKanaTransformation(table, kFullTouten, ".", kFullTouten)
      }
      do {  // COMMA_PERIOD
        var config = Genmai_Config_Config()
        config.punctuationMethod = .commaPeriod
        table.reloadConfig(config)
        testKanaTransformation(table, kFullKuten, ",", kFullComma)
        testKanaTransformation(table, kFullTouten, ".", kFullPeriod)
      }
      do {  // TOUTEN_PERIOD
        var config = Genmai_Config_Config()
        config.punctuationMethod = .toutenPeriod
        table.reloadConfig(config)
        testKanaTransformation(table, kFullKuten, ",", kFullKuten)
        testKanaTransformation(table, kFullTouten, ".", kFullPeriod)
      }
      do {  // COMMA_KUTEN
        var config = Genmai_Config_Config()
        config.punctuationMethod = .commaKuten
        table.reloadConfig(config)
        testKanaTransformation(table, kFullKuten, ",", kFullComma)
        testKanaTransformation(table, kFullTouten, ".", kFullTouten)
      }
    }

    do {  // Symbol
      let kFullLeftSquareBracket = "［"
      let kFullRightSquareBracket = "］"
      let kFullLeftCornerBracket = "「"
      let kFullRightCornerBracket = "」"
      let kFullSlash = "／"
      let kFullMiddleDot = "・"

      do {  // CORNER_BRACKET_MIDDLE_DOT
        var config = Genmai_Config_Config()
        config.symbolMethod = .cornerBracketMiddleDot
        table.reloadConfig(config)
        testKanaTransformation(table, kFullLeftCornerBracket, "[", kFullLeftCornerBracket)
        testKanaTransformation(table, kFullRightCornerBracket, "]", kFullRightCornerBracket)
        testKanaTransformation(table, kFullMiddleDot, "/", kFullMiddleDot)
      }
      do {  // SQUARE_BRACKET_SLASH
        var config = Genmai_Config_Config()
        config.symbolMethod = .squareBracketSlash
        table.reloadConfig(config)
        testKanaTransformation(table, kFullLeftCornerBracket, "[", kFullLeftSquareBracket)
        testKanaTransformation(table, kFullRightCornerBracket, "]", kFullRightSquareBracket)
        testKanaTransformation(table, kFullMiddleDot, "/", kFullSlash)
      }
      do {  // CORNER_BRACKET_SLASH
        var config = Genmai_Config_Config()
        config.symbolMethod = .cornerBracketSlash
        table.reloadConfig(config)
        testKanaTransformation(table, kFullLeftCornerBracket, "[", kFullLeftCornerBracket)
        testKanaTransformation(table, kFullRightCornerBracket, "]", kFullRightCornerBracket)
        testKanaTransformation(table, kFullMiddleDot, "/", kFullSlash)
      }
      do {  // SQUARE_BRACKET_MIDDLE_DOT
        var config = Genmai_Config_Config()
        config.symbolMethod = .squareBracketMiddleDot
        table.reloadConfig(config)
        testKanaTransformation(table, kFullLeftCornerBracket, "[", kFullLeftSquareBracket)
        testKanaTransformation(table, kFullRightCornerBracket, "]", kFullRightSquareBracket)
        testKanaTransformation(table, kFullMiddleDot, "/", kFullMiddleDot)
      }
    }
  }

  @Test func copy() {
    var x = KeyEventTransformer()

    var config = Genmai_Config_Config()
    config.punctuationMethod = .commaPeriod
    x.reloadConfig(config)

    let y = x
    #expect(isKeyEventTransformerEq(x, y) == nil)

    var z = KeyEventTransformer()
    #expect(isKeyEventTransformerEq(x, z) != nil)
    z = x
    #expect(isKeyEventTransformerEq(x, z) == nil)
  }
}
