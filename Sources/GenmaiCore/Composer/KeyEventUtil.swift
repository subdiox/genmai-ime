// Port of mozc/src/composer/key_event_util.{h,cc} (3.35.6354).
//
// Utilities for commands::KeyEvent.

import GenmaiBase
import GenmaiProtocol

public typealias KeyInformation = UInt64

private typealias KeyEvent = Genmai_Commands_KeyEvent

private func mask(_ keys: Genmai_Commands_KeyEvent.ModifierKey...) -> UInt32 {
  keys.reduce(0) { $0 | UInt32($1.rawValue) }
}

private let kAltMask = mask(.alt, .leftAlt, .rightAlt)
private let kCtrlMask = mask(.ctrl, .leftCtrl, .rightCtrl)
private let kShiftMask = mask(.shift, .leftShift, .rightShift)
private let kCapsMask = mask(.caps)

private func ignore(_ modifiers: UInt32, _ modifiersToBeIgnored: UInt32) -> UInt32 {
  modifiers & ~modifiersToBeIgnored
}

private func any(_ modifiersToBeTested: UInt32, _ modifiersToBeQueried: UInt32) -> Bool {
  (modifiersToBeTested & modifiersToBeQueried) != 0
}

private func none(_ modifiersToBeTested: UInt32, _ modifiersToBeQueried: UInt32) -> Bool {
  !any(modifiersToBeTested, modifiersToBeQueried)
}

// C isupper / islower in the "C" locale.
private func isUpper(_ c: UInt32) -> Bool { 0x41 <= c && c <= 0x5A }
private func isLower(_ c: UInt32) -> Bool { 0x61 <= c && c <= 0x7A }

/// This is pure static class.
public enum KeyEventUtil {
  public static func getModifiers(_ keyEvent: Genmai_Commands_KeyEvent) -> UInt32 {
    var modifiers: UInt32 = 0
    if keyEvent.hasModifiers {
      modifiers = keyEvent.modifiers
    } else {
      for key in keyEvent.modifierKeys {
        modifiers |= UInt32(key.rawValue)
      }
    }
    return modifiers
  }

  /// |Modifiers(16bit)|SpecialKey(16bit)|Unicode(32bit)|
  public static func getKeyInformation(_ keyEvent: Genmai_Commands_KeyEvent, _ key: inout KeyInformation)
    -> Bool
  {
    let modifierKeys = UInt16(truncatingIfNeeded: getModifiers(keyEvent))
    let specialKey =
      keyEvent.hasSpecialKey
      ? UInt16(truncatingIfNeeded: keyEvent.specialKey.rawValue)
      : UInt16(KeyEvent.SpecialKey.noSpecialkey.rawValue)
    let keyCode: UInt32 = keyEvent.hasKeyCode ? keyEvent.keyCode : 0

    // Make sure the translation from the obsolete specification.
    // key_code should no longer contain control characters.
    if 0 < keyCode && keyCode <= 32 {
      return false
    }

    key =
      (KeyInformation(modifierKeys) << 48) | (KeyInformation(specialKey) << 32)
      | KeyInformation(keyCode)

    return true
  }

  /// Normalizes given key event for key command looking-up. This function does
  /// - remove commands::KeyEvent::CAPS from the modifier keys
  /// - revert the flip of alphabetical key code caused by CapsLock
  /// so that shortcut keys can be used as if CapsLock was not enabled. b/5627459
  /// In addition, this function removes left / right specified modifiers.
  public static func normalizeModifiers(
    _ keyEvent: Genmai_Commands_KeyEvent, _ newKeyEvent: inout Genmai_Commands_KeyEvent
  ) {
    // CTRL (or ALT, SHIFT) should be set on modifier_keys when
    // LEFT (or RIGHT) ctrl is set.
    // LEFT_CTRL (or others) is not handled on Japanese, so we remove these.
    let kIgnorableModifierMask = mask(
      .caps, .leftAlt, .rightAlt, .leftCtrl, .rightCtrl, .leftShift, .rightShift)

    removeModifiers(keyEvent, kIgnorableModifierMask, &newKeyEvent)

    // Reverts the flip of alphabetical key events caused by CapsLock.
    let originalModifiers = getModifiers(keyEvent)
    if (originalModifiers & UInt32(KeyEvent.ModifierKey.caps.rawValue)) != 0 && keyEvent.hasKeyCode {
      let keyCode = keyEvent.keyCode
      if 0x41 <= keyCode && keyCode <= 0x5A {  // 'A' <= key_code <= 'Z'
        newKeyEvent.keyCode = keyCode + (0x61 - 0x41)
      } else if 0x61 <= keyCode && keyCode <= 0x7A {  // 'a' <= key_code <= 'z'
        newKeyEvent.keyCode = keyCode - (0x61 - 0x41)
      }
    }
  }

  /// Normalizes a numpad key to a normal key (e.g. NUMPAD0 => '0')
  public static func normalizeNumpadKey(
    _ keyEvent: Genmai_Commands_KeyEvent, _ newKeyEvent: inout Genmai_Commands_KeyEvent
  ) {
    newKeyEvent = keyEvent

    if !isNumpadKey(newKeyEvent) {
      return
    }
    let numpadKey = newKeyEvent.specialKey

    // KeyEvent::SEPARATOR is transformed to Enter.
    if numpadKey == .separator {
      newKeyEvent.specialKey = .enter
      return
    }

    newKeyEvent.clearSpecialKey()

    // Handles number keys
    if KeyEvent.SpecialKey.numpad0.rawValue <= numpadKey.rawValue
      && numpadKey.rawValue <= KeyEvent.SpecialKey.numpad9.rawValue
    {
      newKeyEvent.keyCode = UInt32(0x30 + (numpadKey.rawValue - KeyEvent.SpecialKey.numpad0.rawValue))
      return
    }

    let newKeyCode: UInt8
    switch numpadKey {
    case .multiply:
      newKeyCode = UInt8(ascii: "*")
    case .add:
      newKeyCode = UInt8(ascii: "+")
    case .subtract:
      newKeyCode = UInt8(ascii: "-")
    case .decimal:
      newKeyCode = UInt8(ascii: ".")
    case .divide:
      newKeyCode = UInt8(ascii: "/")
    case .equals:
      newKeyCode = UInt8(ascii: "=")
    case .comma:
      newKeyCode = UInt8(ascii: ",")
    default:
      GenmaiLog.error("Unexpected numpad key: \(numpadKey)")
      return
    }

    newKeyEvent.keyCode = UInt32(newKeyCode)
  }

  /// Removes modifier keys which are specified by |remove_modifiers|.
  public static func removeModifiers(
    _ keyEvent: Genmai_Commands_KeyEvent, _ removeModifiers: UInt32,
    _ newKeyEvent: inout Genmai_Commands_KeyEvent
  ) {
    var removeModifiers = removeModifiers
    newKeyEvent = keyEvent

    if hasAlt(removeModifiers) {
      removeModifiers |= mask(.leftAlt, .rightAlt)
    }
    if hasCtrl(removeModifiers) {
      removeModifiers |= mask(.leftCtrl, .rightCtrl)
    }
    if hasShift(removeModifiers) {
      removeModifiers |= mask(.leftShift, .rightShift)
    }

    newKeyEvent.modifierKeys = []
    for modKey in keyEvent.modifierKeys {
      if (removeModifiers & UInt32(modKey.rawValue)) == 0 {
        newKeyEvent.modifierKeys.append(modKey)
      }
    }
  }

  /// Returns a fallback keyevent generated from key_event. In the
  /// current implementation, if the input key_event does not contains
  /// any special keys or modifier keys, that printable key will be replaced
  /// with the ASCII special key.
  public static func maybeGetKeyStub(_ keyEvent: Genmai_Commands_KeyEvent, _ key: inout KeyInformation)
    -> Bool
  {
    // If any modifier keys were pressed, this function does nothing.
    if getModifiers(keyEvent) != 0 {
      return false
    }

    // No stub rule is supported for special keys yet.
    if keyEvent.hasSpecialKey {
      return false
    }

    // Check if both key_code and key_string are invalid.
    if (!keyEvent.hasKeyCode || keyEvent.keyCode <= 32)
      && (!keyEvent.hasKeyString || keyEvent.keyString.isEmpty)
    {
      return false
    }

    var stubKeyEvent = Genmai_Commands_KeyEvent()
    stubKeyEvent.specialKey = .textInput
    if !getKeyInformation(stubKeyEvent, &key) {
      return false
    }

    return true
  }

  public static func hasAlt(_ modifiers: UInt32) -> Bool { any(modifiers, kAltMask) }
  public static func hasCtrl(_ modifiers: UInt32) -> Bool { any(modifiers, kCtrlMask) }
  public static func hasShift(_ modifiers: UInt32) -> Bool { any(modifiers, kShiftMask) }
  public static func hasCaps(_ modifiers: UInt32) -> Bool { any(modifiers, kCapsMask) }

  // These functions doesn't consider CAPS.
  public static func isAlt(_ modifiers: UInt32) -> Bool {
    if !hasAlt(modifiers) {
      return false
    }
    return none(ignore(modifiers, kCapsMask), ~kAltMask)
  }

  public static func isCtrl(_ modifiers: UInt32) -> Bool {
    if !hasCtrl(modifiers) {
      return false
    }
    return none(ignore(modifiers, kCapsMask), ~kCtrlMask)
  }

  public static func isShift(_ modifiers: UInt32) -> Bool {
    if !hasShift(modifiers) {
      return false
    }
    return none(ignore(modifiers, kCapsMask), ~kShiftMask)
  }

  public static func isAltCtrl(_ modifiers: UInt32) -> Bool {
    if !hasAlt(modifiers) || !hasCtrl(modifiers) {
      return false
    }
    return none(ignore(modifiers, kCapsMask), ~(kAltMask | kCtrlMask))
  }

  public static func isAltShift(_ modifiers: UInt32) -> Bool {
    if !hasAlt(modifiers) || !hasShift(modifiers) {
      return false
    }
    return none(ignore(modifiers, kCapsMask), ~(kAltMask | kShiftMask))
  }

  public static func isCtrlShift(_ modifiers: UInt32) -> Bool {
    if !hasCtrl(modifiers) || !hasShift(modifiers) {
      return false
    }
    return none(ignore(modifiers, kCapsMask), ~(kCtrlMask | kShiftMask))
  }

  public static func isAltCtrlShift(_ modifiers: UInt32) -> Bool {
    if !hasAlt(modifiers) || !hasCtrl(modifiers) || !hasShift(modifiers) {
      return false
    }
    let kAltCtrlShiftMask = kAltMask | kCtrlMask | kShiftMask
    return none(ignore(modifiers, kCapsMask), ~kAltCtrlShiftMask)
  }

  public static func isLowerAlphabet(_ keyEvent: Genmai_Commands_KeyEvent) -> Bool {
    if !keyEvent.hasKeyCode {
      return false
    }

    let keyCode = keyEvent.keyCode
    let modifierKeys = getModifiers(keyEvent)
    let changeCase = (hasShift(modifierKeys) != hasCaps(modifierKeys))

    if changeCase {
      return isUpper(keyCode)
    } else {
      return isLower(keyCode)
    }
  }

  public static func isUpperAlphabet(_ keyEvent: Genmai_Commands_KeyEvent) -> Bool {
    if !keyEvent.hasKeyCode {
      return false
    }

    let keyCode = keyEvent.keyCode
    let modifierKeys = getModifiers(keyEvent)
    let changeCase = (hasShift(modifierKeys) != hasCaps(modifierKeys))

    if changeCase {
      return isLower(keyCode)
    } else {
      return isUpper(keyCode)
    }
  }

  public static func isNumpadKey(_ keyEvent: Genmai_Commands_KeyEvent) -> Bool {
    if !keyEvent.hasSpecialKey {
      return false
    }

    let specialKey = keyEvent.specialKey
    if KeyEvent.SpecialKey.numpad0.rawValue <= specialKey.rawValue
      && specialKey.rawValue <= KeyEvent.SpecialKey.equals.rawValue
    {
      return true
    }
    if specialKey == .comma {
      return true
    }
    return false
  }
}
