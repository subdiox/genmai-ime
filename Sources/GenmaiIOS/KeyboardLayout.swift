// Not in Mozc (the Gboard client that drives ios_engine is not open source): the keys of the iOS keyboard.
//
// A character key sends `tap` (or the text of a flick) to the engine with `IosEngine.sendKey`; the composer's
// toggle / flick tables (data/preedit/toggle_flick-*.tsv, flick-*.tsv, qwerty_mobile-*.tsv, selected by
// `IosEngine.setMobileRequest`) turn them into kana. In the toggle tables the key's first character toggles
// (あ → い → う ... on repeated taps) and a flick sends the character itself; "*" is the 小゛゜ (a/A) key,
// "[" / "]" / "`" its flicks (dakuten / handakuten / small). The other keys are `KeyboardFunction`s.

/// A flick direction of a 12-key key.
public enum FlickDirection: CaseIterable, Sendable {
  case left
  case up
  case right
  case down
}

/// What a flick of a 12-key key sends.
public struct FlickOutput: Hashable, Sendable {
  /// Shown in the flick guide.
  public let label: String
  /// Sent to the engine.
  public let text: String

  public init(_ text: String, label: String? = nil) {
    self.text = text
    self.label = label ?? text
  }
}

/// A character key: tapped it sends `tap`; on the 12-key layout it can be flicked.
public struct CharacterKey: Hashable, Sendable, Identifiable {
  public var id: String { label }
  /// Shown on the key.
  public let label: String
  /// Sent on tap.
  public let tap: String
  public let flicks: [FlickDirection: FlickOutput]

  public init(_ label: String, tap: String? = nil, flicks: [FlickDirection: FlickOutput] = [:]) {
    self.label = label
    self.tap = tap ?? label
    self.flicks = flicks
  }

  /// A 12-key key whose flicks (left, up, right, down) send the characters themselves.
  static func flick(
    _ label: String, tap: String? = nil, _ left: String?, _ up: String?, _ right: String?,
    _ down: String? = nil
  ) -> CharacterKey {
    var flicks: [FlickDirection: FlickOutput] = [:]
    for (direction, text) in zip(FlickDirection.allCases, [left, up, right, down]) {
      if let text {
        flicks[direction] = FlickOutput(text)
      }
    }
    return CharacterKey(label, tap: tap, flicks: flicks)
  }

  /// The text sent for a flick in `direction` (nil: the key has none; the tap is not sent either).
  public func text(for direction: FlickDirection?) -> String? {
    guard let direction else { return tap }
    return flicks[direction]?.text
  }
}

/// The non-character keys.
public enum KeyboardFunction: Hashable, Sendable {
  case backspace
  /// Space, or the conversion key while composing.
  case space
  case enter
  /// UNDO_OR_REWIND: reverse toggle while composing, undo of the last commit otherwise.
  case undo
  case cursorLeft
  case cursorRight
  /// The 12 keys' "^_^" (without a composition): the emoticons, as the candidates of the reading かおもじ.
  case kaomoji
  /// The 12 keys' "→": ends the toggle of the last kana (the next tap of its key starts a new one), otherwise moves
  /// the cursor right.
  case advance
  /// Shows the keys of an input mode.
  case inputMode(IosEngine.InputMode)
  /// Shift of the QWERTY keyboard (alphabet mode).
  case shift
  /// The system's "next keyboard" key (UIInputViewController.handleInputModeList).
  case nextKeyboard
}

/// The kana keyboard layouts.
public enum KanaLayout: String, CaseIterable, Codable, Sendable {
  /// 12 keys with toggle input and flicks.
  case twelveKeys = "12keys"
  /// Romaji on a QWERTY keyboard.
  case qwerty

  /// The layout name for `IosEngine.setMobileRequest`.
  public func engineLayoutName(flickOnly: Bool, qwertyAlphabet: Bool) -> String {
    switch self {
    case .twelveKeys:
      switch (flickOnly, qwertyAlphabet) {
      case (false, false): "12KEYS"
      case (false, true): "12KEYS_QWERTY"
      case (true, false): "12KEYS_FLICKONLY"
      case (true, true): "12KEYS_FLICKONLY_QWERTY"
      }
    case .qwerty: "QWERTY_JA"
    }
  }
}

/// The character keys of each keyboard, row by row.
public enum KeyboardKeys {
  // Toggle sequences and flicks follow data/preedit/toggle_flick-hiragana_intuitive.tsv.
  public static let kana: [[CharacterKey]] = [
    [
      .flick("あ", "い", "う", "え", "お"), .flick("か", "き", "く", "け", "こ"), .flick("さ", "し", "す", "せ", "そ"),
    ],
    [
      .flick("た", "ち", "つ", "て", "と"), .flick("な", "に", "ぬ", "ね", "の"), .flick("は", "ひ", "ふ", "へ", "ほ"),
    ],
    [
      .flick("ま", "み", "む", "め", "も"), .flick("や", "（", "ゆ", "）", "よ"), .flick("ら", "り", "る", "れ", "ろ"),
    ],
    [
      CharacterKey(
        "小゛゜", tap: "*",
        flicks: [
          .left: FlickOutput("`", label: "小"), .up: FlickOutput("[", label: "゛"), .right: FlickOutput("]", label: "゜"),
        ]
      ),
      .flick("わ", "を", "ん", "ー"), .flick("、。?!", tap: "、", "。", "？", "！"),
    ],
  ]

  // data/preedit/toggle_flick-halfwidthascii_ios.tsv
  public static let alphabet: [[CharacterKey]] = [
    [
      .flick("@#/&_", tap: "@", "#", "/", "&", "_"), .flick("ABC", tap: "a", "b", "c", nil),
      .flick("DEF", tap: "d", "e", "f", nil),
    ],
    [
      .flick("GHI", tap: "g", "h", "i", nil), .flick("JKL", tap: "j", "k", "l", nil),
      .flick("MNO", tap: "m", "n", "o", nil),
    ],
    [
      .flick("PQRS", tap: "p", "q", "r", "s"), .flick("TUV", tap: "t", "u", "v", nil),
      .flick("WXYZ", tap: "w", "x", "y", "z"),
    ],
    [
      CharacterKey("a/A", tap: "*"), .flick("'\"()", tap: "'", "\"", "(", ")"), .flick(".,?!", tap: ".", ",", "?", "!"),
    ],
  ]

  // data/preedit/toggle_flick-number.tsv
  public static let number: [[CharacterKey]] = [
    [.flick("1", "☆", "♪", "→"), .flick("2", "¥", "$", "€"), .flick("3", "%", "゜", "#")],
    [.flick("4", "○", "*", "・"), .flick("5", "+", "×", "÷"), .flick("6", "<", "=", ">")],
    [.flick("7", "「", "」", ":"), .flick("8", "〒", "々", "〆"), .flick("9", "^", "|", "\\")],
    [.flick("()[]", tap: "(", ")", "[", "]"), .flick("0", "〜", "…", nil), .flick(".,-/", tap: ".", ",", "-", "/")],
  ]

  /// QWERTY letters (data/preedit/qwerty_mobile-hiragana.tsv turns them into kana; "-" is ー).
  public static func qwerty(kana: Bool, uppercase: Bool) -> [[CharacterKey]] {
    let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    var keys = rows.map { row in
      row.map { letter in
        let text = uppercase ? String(letter).uppercased() : String(letter)
        return CharacterKey(text)
      }
    }
    if kana {
      keys[1].append(CharacterKey("ー", tap: "-"))
    }
    return keys
  }

  /// Digits and symbols of the QWERTY keyboard.
  public static let qwertySymbols: [[CharacterKey]] = [
    "1234567890".map { CharacterKey(String($0)) },
    ["-", "/", ":", ";", "(", ")", "¥", "&", "@", "\""].map { CharacterKey($0) },
    [".", ",", "?", "!", "'", "*", "#"].map { CharacterKey($0) },
  ]
}
