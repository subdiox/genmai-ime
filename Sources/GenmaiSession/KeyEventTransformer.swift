// Port of mozc/src/session/key_event_transformer.{h,cc} (3.35.6354).
//
// Transform key event accoding to config.

import GenmaiBase
import GenmaiCore
import GenmaiProtocol

public struct KeyEventTransformer: Sendable {
  public typealias Table = [String: Genmai_Commands_KeyEvent]

  public private(set) var table: Table = [:]
  public private(set) var numpadCharacterForm: Genmai_Config_Config.NumpadCharacterForm = .numpadInputMode

  public init() {
    reloadConfig(ConfigHandler.defaultConfig())
  }

  /// Updates the transform table accoding to config.
  public mutating func reloadConfig(_ config: Genmai_Config_Config) {
    numpadCharacterForm = config.numpadCharacterForm

    table.removeAll()
    let punctuation = config.punctuationMethod
    if punctuation == .commaPeriod || punctuation == .commaKuten {
      var keyEvent = Genmai_Commands_KeyEvent()
      keyEvent.keyCode = UInt32(UInt8(ascii: ","))
      keyEvent.keyString = "，"
      emplace("、", keyEvent)
    }
    if punctuation == .commaPeriod || punctuation == .toutenPeriod {
      var keyEvent = Genmai_Commands_KeyEvent()
      keyEvent.keyCode = UInt32(UInt8(ascii: "."))
      keyEvent.keyString = "．"
      emplace("。", keyEvent)
    }

    let symbol = config.symbolMethod
    if symbol == .squareBracketSlash || symbol == .squareBracketMiddleDot {
      do {
        var keyEvent = Genmai_Commands_KeyEvent()
        keyEvent.keyCode = UInt32(UInt8(ascii: "["))
        keyEvent.keyString = "［"
        emplace("「", keyEvent)
      }
      do {
        var keyEvent = Genmai_Commands_KeyEvent()
        keyEvent.keyCode = UInt32(UInt8(ascii: "]"))
        keyEvent.keyString = "］"
        emplace("」", keyEvent)
      }
    }
    if symbol == .squareBracketSlash || symbol == .cornerBracketSlash {
      var keyEvent = Genmai_Commands_KeyEvent()
      keyEvent.keyCode = UInt32(UInt8(ascii: "/"))
      keyEvent.keyString = "／"
      emplace("・", keyEvent)
    }
  }

  /// map::emplace: does not overwrite an existing entry.
  private mutating func emplace(_ key: String, _ value: Genmai_Commands_KeyEvent) {
    if table[key] == nil {
      table[key] = value
    }
  }

  /// Transforms key event accoding to transform table.
  /// We should update table using ReloadConfig() before calling a this function.
  @discardableResult
  public func transformKeyEvent(_ keyEvent: inout Genmai_Commands_KeyEvent) -> Bool {
    if transformKeyEventForNumpad(&keyEvent) {
      return true
    }
    if transformKeyEventForKana(&keyEvent) {
      return true
    }
    return false
  }

  /// Transform the key event base on the rule.  This function is used
  /// for special treatment with numpad keys.
  private func transformKeyEventForNumpad(_ keyEvent: inout Genmai_Commands_KeyEvent) -> Bool {
    if !KeyEventUtil.isNumpadKey(keyEvent) {
      return false
    }

    do {
      let keyEventOrigin = keyEvent
      KeyEventUtil.normalizeNumpadKey(keyEventOrigin, &keyEvent)
    }

    // KeyEvent::SEPARATOR is transformed to Enter.
    if keyEvent.hasSpecialKey {
      return true
    }

    var isFullWidth = true
    switch numpadCharacterForm {
    case .numpadInputMode:
      isFullWidth = true
      keyEvent.inputStyle = .followMode
    case .numpadFullWidth:
      isFullWidth = true
      keyEvent.inputStyle = .asIs
    case .numpadHalfWidth:
      isFullWidth = false
      keyEvent.inputStyle = .asIs
    case .numpadDirectInput:
      isFullWidth = false
      keyEvent.inputStyle = .directInput
    @unknown default:
      GenmaiLog.error("Unknown numpad character form value.")
      // Use the same behavior with NUMPAD_HALF_WIDTH as a fallback.
      isFullWidth = false
      keyEvent.inputStyle = .asIs
    }

    // All key event except for KeyEvent::SEPARATOR should have key code
    // and its value should represent a ASCII character since it is generated
    // from numpad key.
    let keyCode = keyEvent.keyCode
    let halfWidthKeyString = String(UnicodeScalar(UInt8(truncatingIfNeeded: keyCode)))

    if isFullWidth {
      keyEvent.keyString = Japanese.halfWidthAsciiToFullWidthAscii(halfWidthKeyString)
    } else {
      keyEvent.keyString = halfWidthKeyString
    }

    return true
  }

  /// Transform symbols for Kana input.  Character transformation for
  /// Romanji input is performed in preedit/table.cc
  private func transformKeyEventForKana(_ keyEvent: inout Genmai_Commands_KeyEvent) -> Bool {
    if !keyEvent.hasKeyString {
      return false
    }
    if !keyEvent.modifierKeys.isEmpty {
      return false
    }
    if keyEvent.hasModifiers && keyEvent.modifiers != 0 {
      return false
    }

    guard let transformed = table[keyEvent.keyString] else {
      return false
    }

    keyEvent = transformed
    return true
  }
}
