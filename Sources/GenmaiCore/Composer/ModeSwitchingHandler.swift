// Port of mozc/src/composer/mode_switching_handler.{h,cc} (3.35.6354).
//
// Simple word patterns matcher which will be used in composer objects
// for auto swtiching input mode.

public enum ModeSwitchingHandler {
  public enum ModeSwitching: Int, Sendable {
    case noChange
    case revertToPreviousMode
    case preferredAlphanumeric
    case halfAlphanumeric
    case fullAlphanumeric
  }

  public struct Rule: Sendable, Equatable {
    /// |display_mode| affects the existing composition the user typed.
    public var displayMode: ModeSwitching
    /// |input_mode| affects current input mode to be used for the user's new
    /// typing.
    public var inputMode: ModeSwitching

    public init(displayMode: ModeSwitching, inputMode: ModeSwitching) {
      self.displayMode = displayMode
      self.inputMode = inputMode
    }
  }

  /// Returns a Rule for the current preedit. |key| is the string which the user
  /// actually typed. display_mode and input_mode are stored rules controlling
  /// the composer. Returns NO_CHANGE if the key doesn't match the stored rules.
  public static func getModeSwitchingRule(_ key: some StringProtocol) -> Rule {
    let k = Array(key.utf8)
    func eq(_ s: String) -> Bool { k == Array(s.utf8) }
    if eq("google") || eq("Google") || eq("Chrome") || eq("chrome") || eq("Android")
      || eq("android")
    {
      return Rule(displayMode: .preferredAlphanumeric, inputMode: .revertToPreviousMode)
    }

    if eq("http") || eq("www.") || eq("\\\\") {
      return Rule(displayMode: .halfAlphanumeric, inputMode: .halfAlphanumeric)
    }

    if isDriveLetter(key) {
      return Rule(displayMode: .halfAlphanumeric, inputMode: .halfAlphanumeric)
    }

    return Rule(displayMode: .noChange, inputMode: .noChange)
  }

  /// Matcher to Windows drive letters like "C:\".
  /// TODO(team): This static method is internal use only.  It's public for
  /// testing purpose.
  public static func isDriveLetter(_ key: some StringProtocol) -> Bool {
    let k = Array(key.utf8)
    guard k.count == 3 else { return false }
    let c = k[0]
    let isAlpha = (0x41...0x5A).contains(c) || (0x61...0x7A).contains(c)
    return isAlpha && k[1] == UInt8(ascii: ":") && k[2] == UInt8(ascii: "\\")
  }
}
