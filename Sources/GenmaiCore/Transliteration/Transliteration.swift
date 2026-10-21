// Port of mozc/src/transliteration/transliteration.{h,cc} (3.35.6354).
//
// Libraries for transliterations.

/// transliteration::TransliterationType. Raw values match the C++ enum.
public enum TransliterationType: Int, Sendable, CaseIterable {
  /// "ひらがな"
  case hiragana = 0
  /// "カタカナ"
  case fullKatakana
  /// "ascII"
  case halfAscii
  /// "ASCII"
  case halfAsciiUpper
  /// "ascii"
  case halfAsciiLower
  /// "Ascii"
  case halfAsciiCapitalized
  /// "ａｓｃＩＩ"
  case fullAscii
  /// "ＡＳＣＩＩ"
  case fullAsciiUpper
  /// "ａｓｃｉｉ"
  case fullAsciiLower
  /// "Ａｓｃｉｉ"
  case fullAsciiCapitalized
  /// "ｶﾀｶﾅ"
  case halfKatakana

  /// NUM_T13N_TYPES
  public static let numT13nTypes = 11
}

/// transliteration::Transliterations.
public typealias Transliterations = [String]

/// transliteration::TransliterationTypeArray.
public let transliterationTypeArray: [TransliterationType] = [
  .hiragana, .fullKatakana, .halfAscii, .halfAsciiUpper,
  .halfAsciiLower, .halfAsciiCapitalized, .fullAscii, .fullAsciiUpper,
  .fullAsciiLower, .fullAsciiCapitalized, .halfKatakana,
]

public enum T13n {
  /// Return true if the prefix of the type starts with FULL_ASCII.
  public static func isInFullAsciiTypes(_ type: TransliterationType) -> Bool {
    type == .fullAscii || type == .fullAsciiUpper || type == .fullAsciiLower
      || type == .fullAsciiCapitalized
  }

  /// Return true if the prefix of the type starts with HALF_ASCII.
  public static func isInHalfAsciiTypes(_ type: TransliterationType) -> Bool {
    type == .halfAscii || type == .halfAsciiUpper || type == .halfAsciiLower
      || type == .halfAsciiCapitalized
  }

  /// Return true if the prefix of the type starts with HIRAGANA.
  public static func isInHiraganaTypes(_ type: TransliterationType) -> Bool {
    type == .hiragana
  }

  /// Return true if the prefix of the type starts with FULL_KATAKANA.
  public static func isInFullKatakanaTypes(_ type: TransliterationType) -> Bool {
    type == .fullKatakana
  }

  /// Return true if the prefix of the type starts with HALF_KATAKANA.
  public static func isInHalfKatakanaTypes(_ type: TransliterationType) -> Bool {
    type == .halfKatakana
  }

  /// Return one of full ascii types toggling the current type.
  public static func toggleFullAsciiTypes(_ currentType: TransliterationType) -> TransliterationType {
    switch currentType {
    case .fullAscii: return .fullAsciiUpper
    case .fullAsciiUpper: return .fullAsciiLower
    case .fullAsciiLower: return .fullAsciiCapitalized
    default: return .fullAscii
    }
  }

  /// Return one of half ascii types toggling the current type.
  public static func toggleHalfAsciiTypes(_ currentType: TransliterationType) -> TransliterationType {
    switch currentType {
    case .halfAscii: return .halfAsciiUpper
    case .halfAsciiUpper: return .halfAsciiLower
    case .halfAsciiLower: return .halfAsciiCapitalized
    default: return .halfAscii
    }
  }
}
