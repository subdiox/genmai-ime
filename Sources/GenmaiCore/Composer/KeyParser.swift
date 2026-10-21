// Port of mozc/src/composer/key_parser.{h,cc} (3.35.6354).
//
// Parser of key events

import GenmaiBase
import GenmaiProtocol

private typealias KeyEvent = Genmai_Commands_KeyEvent

private let kModifierKeyMap: [String: [Genmai_Commands_KeyEvent.ModifierKey]] = [
  "ctrl": [.ctrl],
  "control": [.ctrl],
  "alt": [.alt],
  "option": [.alt],
  "meta": [.alt],
  "super": [.alt],
  "hyper": [.alt],
  "shift": [.shift],
  "caps": [.caps],
  "keydown": [.keyDown],
  "keyup": [.keyUp],
  "leftctrl": [.ctrl, .leftCtrl],
  "rightctrl": [.ctrl, .rightCtrl],
  "leftalt": [.alt, .leftAlt],
  "rightalt": [.alt, .rightAlt],
  "leftshift": [.shift, .leftShift],
  "rightshift": [.shift, .rightShift],
]

private let kSpecialKeyMap: [String: Genmai_Commands_KeyEvent.SpecialKey] = [
  "on": .on,
  "off": .off,
  "left": .left,
  "down": .down,
  "up": .up,
  "right": .right,
  "enter": .enter,
  "return": .enter,
  "esc": .escape,
  "escape": .escape,
  "delete": .del,
  "del": .del,
  "bs": .backspace,
  "backspace": .backspace,
  "henkan": .henkan,
  "muhenkan": .muhenkan,
  "kana": .kana,
  "hiragana": .kana,
  "katakana": .katakana,
  "eisu": .eisu,
  "home": .home,
  "end": .end,
  "space": .space,
  "ascii": .textInput,  // deprecated
  "textinput": .textInput,
  "tab": .tab,
  "pageup": .pageUp,
  "pagedown": .pageDown,
  "insert": .insert,
  "hankaku": .hankaku,
  "zenkaku": .hankaku,
  "hankaku/zenkaku": .hankaku,
  "kanji": .kanji,

  "f1": .f1,
  "f2": .f2,
  "f3": .f3,
  "f4": .f4,
  "f5": .f5,
  "f6": .f6,
  "f7": .f7,
  "f8": .f8,
  "f9": .f9,
  "f10": .f10,
  "f11": .f11,
  "f12": .f12,
  "f13": .f13,
  "f14": .f14,
  "f15": .f15,
  "f16": .f16,
  "f17": .f17,
  "f18": .f18,
  "f19": .f19,
  "f20": .f20,
  "f21": .f21,
  "f22": .f22,
  "f23": .f23,
  "f24": .f24,

  "numpad0": .numpad0,
  "numpad1": .numpad1,
  "numpad2": .numpad2,
  "numpad3": .numpad3,
  "numpad4": .numpad4,
  "numpad5": .numpad5,
  "numpad6": .numpad6,
  "numpad7": .numpad7,
  "numpad8": .numpad8,
  "numpad9": .numpad9,

  "multiply": .multiply,
  "add": .add,
  "separator": .separator,
  "subtract": .subtract,
  "decimal": .decimal,
  "divide": .divide,
  "equals": .equals,
  "comma": .comma,
  "clear": .clear,

  "virtualleft": .virtualLeft,
  "virtualright": .virtualRight,
  "virtualenter": .virtualEnter,
  "virtualup": .virtualUp,
  "virtualdown": .virtualDown,

  "imeaction": .imeAction,

  // Meant to be used for any other special keys.
  "undefinedkey": .undefinedKey,
]

// KeyEvent::SpecialKey_Name(), i.e. the proto enum value names.
private let kSpecialKeyNames: [Genmai_Commands_KeyEvent.SpecialKey: String] = [
  .noSpecialkey: "NO_SPECIALKEY", .digit: "DIGIT", .on: "ON", .off: "OFF", .space: "SPACE",
  .enter: "ENTER", .left: "LEFT", .right: "RIGHT", .up: "UP", .down: "DOWN", .escape: "ESCAPE",
  .del: "DEL", .backspace: "BACKSPACE", .henkan: "HENKAN", .muhenkan: "MUHENKAN", .kana: "KANA",
  .home: "HOME", .end: "END", .tab: "TAB", .f1: "F1", .f2: "F2", .f3: "F3", .f4: "F4", .f5: "F5",
  .f6: "F6", .f7: "F7", .f8: "F8", .f9: "F9", .f10: "F10", .f11: "F11", .f12: "F12",
  .pageUp: "PAGE_UP", .pageDown: "PAGE_DOWN", .insert: "INSERT", .f13: "F13", .f14: "F14",
  .f15: "F15", .f16: "F16", .f17: "F17", .f18: "F18", .f19: "F19", .f20: "F20", .f21: "F21",
  .f22: "F22", .f23: "F23", .f24: "F24", .eisu: "EISU", .numpad0: "NUMPAD0",
  .numpad1: "NUMPAD1", .numpad2: "NUMPAD2", .numpad3: "NUMPAD3", .numpad4: "NUMPAD4",
  .numpad5: "NUMPAD5", .numpad6: "NUMPAD6", .numpad7: "NUMPAD7", .numpad8: "NUMPAD8",
  .numpad9: "NUMPAD9", .multiply: "MULTIPLY", .add: "ADD", .separator: "SEPARATOR",
  .subtract: "SUBTRACT", .decimal: "DECIMAL", .divide: "DIVIDE", .equals: "EQUALS",
  .textInput: "TEXT_INPUT", .hankaku: "HANKAKU", .kanji: "KANJI", .katakana: "KATAKANA",
  .capsLock: "CAPS_LOCK", .undefinedKey: "UNDEFINED_KEY", .comma: "COMMA", .clear: "CLEAR",
  .virtualLeft: "VIRTUAL_LEFT", .virtualRight: "VIRTUAL_RIGHT", .virtualEnter: "VIRTUAL_ENTER",
  .virtualUp: "VIRTUAL_UP", .virtualDown: "VIRTUAL_DOWN", .imeAction: "IME_ACTION",
  .numSpecialkeys: "NUM_SPECIALKEYS",
]

public enum KeyParser {
  public static func parseKey(_ keyString: some StringProtocol, _ keyEvent: inout Genmai_Commands_KeyEvent)
    -> Bool
  {
    let keys = splitAllowEmptyBytes(keyString, 0x20).filter { !$0.isEmpty }  // SkipEmpty
    if keys.isEmpty {
      GenmaiLog.error("keys is empty")
      return false
    }
    return parseKeyVector(keys, &keyEvent)
  }

  public static func parseKeyVector(_ keys: [String], _ keyEvent: inout Genmai_Commands_KeyEvent) -> Bool {
    keyEvent = Genmai_Commands_KeyEvent()
    var modifiersSet = Set<Genmai_Commands_KeyEvent.ModifierKey>()

    for key in keys {
      if Util.charsLen(key) == 1 {
        if keyEvent.hasKeyCode {
          // Multiple keys are not supported.
          return false
        }
        keyEvent.keyCode = Util.utf8ToCodepoint(key)
        continue
      }

      var lowerKey = key
      Util.lowerString(&lowerKey)

      if let modifierKeys = kModifierKeyMap[lowerKey], !modifierKeys.isEmpty {
        for modifierKey in modifierKeys {
          modifiersSet.insert(modifierKey)
        }
        continue
      }
      if let specialKey = kSpecialKeyMap[lowerKey] {
        if keyEvent.hasSpecialKey {
          // Multiple special keys are not supported.
          return false
        }
        keyEvent.specialKey = specialKey
        continue
      }
      GenmaiLog.error("Unknown key: \(key)")
      return false
    }

    // absl::btree_set iterates in ascending order of the enum value.
    for modifier in modifiersSet.sorted(by: { $0.rawValue < $1.rawValue }) {
      keyEvent.modifierKeys.append(modifier)
    }

    return true
  }

  /// Returns corresponding string of SpecialKey (e.g. PAGE_UP → pageup).
  public static func getSpecialKeyString(_ key: Genmai_Commands_KeyEvent.SpecialKey) -> String {
    // Handles exceptional rules that cannot convert from the enum value.
    switch key {
    case .del:
      return "delete"
    case .kana:
      return "hiragana"
    case .hankaku:
      return "hankaku/zenkaku"
    default:
      // Do nothing.
      break
    }

    // Transforms the enum value in string by removing '_' and using lower case.
    // e.g. "PAGE_UP" -> "pageup".
    var name = kSpecialKeyNames[key] ?? ""
    // Idiom to remove '_' from `name` (e.g. "PAGE_UP" -> "PAGEUP").
    name.removeAll { $0 == "_" }
    Util.lowerString(&name)
    return name
  }
}
