// Port of mozc/src/composer/composition_input.{h,cc} (3.35.6354).

import GenmaiBase
import GenmaiProtocol

public struct CompositionInput: Sendable, Equatable {
  public typealias ProbableKeyEvent = Genmai_Commands_KeyEvent.ProbableKeyEvent
  public typealias ProbableKeyEvents = [ProbableKeyEvent]

  public var raw = ""
  public var conversion = ""
  public var probableKeyEvents: ProbableKeyEvents = []
  public var isNewInput = false
  public private(set) var isAsis = false

  public init() {}

  /// Initializes with KeyEvent.
  /// If KeyEvent has a special key (e.g. Henkan),
  /// it is used as an input of a command key. (e.g. "{henkan}").
  public mutating func initialize(
    _ table: Table, _ keyEvent: Genmai_Commands_KeyEvent, _ isNewInput: Bool
  ) -> Bool {
    if keyEvent.hasKeyCode {
      raw = Util.codepointToUtf8(keyEvent.keyCode)
    } else if keyEvent.hasKeyString {
      raw = keyEvent.keyString
    } else if keyEvent.hasSpecialKey {
      raw = table.parseSpecialKey(
        "{" + KeyParser.getSpecialKeyString(keyEvent.specialKey) + "}")
    } else {
      GenmaiLog.warning("input is empty")
      return false
    }

    if keyEvent.hasKeyString {
      conversion = keyEvent.keyString
    }
    if !keyEvent.probableKeyEvent.isEmpty {
      probableKeyEvents = keyEvent.probableKeyEvent
    }
    self.isNewInput = isNewInput
    isAsis = (keyEvent.inputStyle == .asIs || keyEvent.inputStyle == .directInput)
    return true
  }

  public mutating func initFromRaw(_ raw: String, _ isNewInput: Bool) {
    self.raw = raw
    self.isNewInput = isNewInput
  }

  public mutating func initFromRawAndConv(_ raw: String, _ conversion: String, _ isNewInput: Bool) {
    self.raw = raw
    self.conversion = conversion
    self.isNewInput = isNewInput
  }

  public mutating func clear() {
    raw = ""
    conversion = ""
    probableKeyEvents = []
    isNewInput = false
    isAsis = false
  }

  public var isEmpty: Bool {
    raw.isEmpty && conversion.isEmpty
  }

  public mutating func clearRaw() { raw = "" }
  public mutating func clearConversion() { conversion = "" }
}
