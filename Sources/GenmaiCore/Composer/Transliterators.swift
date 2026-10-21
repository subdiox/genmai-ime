// Port of mozc/src/composer/transliterators.{h,cc} (3.35.6354).

import GenmaiBase

/// Result of TransliteratorInterface::Split (the four output strings).
public struct TransliteratorSplit: Sendable, Equatable {
  public var rawLhs = ""
  public var rawRhs = ""
  public var convertedLhs = ""
  public var convertedRhs = ""
  /// The bool returned by Split(): false if fall back strings were used.
  public var result = false

  public init() {}
}

/// composer::internal::TransliteratorInterface.
///
/// Stateless transliteration rule exposed as a pair of functions.
public struct TransliteratorInterface: Sendable {
  /// Return the transliterated string of either raw or converted.
  /// Determination of which argument is used depends on the
  /// implementation.
  ///
  /// Expected usage examples:
  /// - HalfKatakanaTransliterator("a", "あ") => "ｱ"
  /// - FullAsciiTransliterator("a", "あ") => "ａ"
  public let transliterate: @Sendable (_ raw: String, _ converted: String) -> String

  /// Split raw and converted strings based on the transliteration
  /// rule.  If raw or converted could not be deterministically split,
  /// fall back strings are fill and false is returned.  The first
  /// argument, position, is in character (rather than byte).
  ///
  /// Expected usage examples:
  /// - HiraganaTransliterator(1, "kk", "っk") => true
  ///   (raw_lhs, raw_rhs) => ("k", "k")
  ///   (conv_lhs, conv_rhs) => ("っ", "k")
  /// - HalfKatakanaTransliterator(1, "zu", "ず") => false
  ///   (raw_lhs, raw_rhs) => ("す", "゛")  fall back strings.
  ///   (conv_lhs, conv_rhs) => ("す", "゛")
  public let split: @Sendable (_ position: Int, _ raw: String, _ converted: String) -> TransliteratorSplit
}

private func splitPrimaryString(
  _ position: Int, _ primary: String, _ secondary: String,
  _ primaryLhs: inout String, _ primaryRhs: inout String,
  _ secondaryLhs: inout String, _ secondaryRhs: inout String
) -> Bool {
  primaryLhs = String(Util.utf8SubString(primary, 0, position))
  primaryRhs = String(Util.utf8SubString(primary, position))

  // Set fallback strings.
  secondaryLhs = primaryLhs
  secondaryRhs = primaryRhs

  // If secondary and primary have the same suffix like "ttk" and "っtk",
  // Separation of primary can be more intelligent.

  if secondary.utf8.count < primaryRhs.utf8.count {
    // If the size of suffix of primary is greater than the whole size
    // of secondary, it must not a "ttk" and "っtk" case.
    return false
  }

  // Position on the secondary string, where secondary and primary have the
  // same suffix.
  let secondaryPosition = secondary.utf8.count - primaryRhs.utf8.count

  // Check if the secondary and primary have the same suffix.
  if secondaryPosition != ComposerBytes.rfind(secondary, primaryRhs) {
    return false
  }

  secondaryRhs = primaryRhs
  secondaryLhs = ComposerBytes.substr(secondary, 0, secondaryPosition)
  return true
}

private func splitRawImpl(_ position: Int, _ raw: String, _ converted: String) -> TransliteratorSplit {
  var r = TransliteratorSplit()
  r.result = splitPrimaryString(
    position, raw, converted, &r.rawLhs, &r.rawRhs, &r.convertedLhs, &r.convertedRhs)
  return r
}

private func splitConvertedImpl(_ position: Int, _ raw: String, _ converted: String)
  -> TransliteratorSplit
{
  var r = TransliteratorSplit()
  r.result = splitPrimaryString(
    position, converted, raw, &r.convertedLhs, &r.convertedRhs, &r.rawLhs, &r.rawRhs)
  return r
}

private func halfKatakanaToHiragana(_ halfKatakana: String) -> String {
  let fullKatakana = Japanese.halfWidthKatakanaToFullWidthKatakana(halfKatakana)
  return Japanese.katakanaToHiragana(fullKatakana)
}

private func halfKatakanaTransliterate(_ raw: String, _ converted: String) -> String {
  let katakanaOutput = Japanese.hiraganaToKatakana(converted)
  return Japanese.fullWidthToHalfWidth(katakanaOutput)
}

// Always uses a converted string rather than a raw string.
private let kConversionString = TransliteratorInterface(
  transliterate: { _, converted in converted },
  split: { splitConvertedImpl($0, $1, $2) })

// Always uses a raw string rather than a converted string.
private let kRawString = TransliteratorInterface(
  transliterate: { raw, _ in raw },
  split: { splitRawImpl($0, $1, $2) })

private let kHiragana = TransliteratorInterface(
  transliterate: { _, converted in
    let full = Japanese.halfWidthToFullWidth(converted)
    return CharacterFormManager.getCharacterFormManager().convertPreeditString(full)
  },
  split: { splitConvertedImpl($0, $1, $2) })

private let kFullKatakana = TransliteratorInterface(
  transliterate: { _, converted in
    let t13n = Japanese.hiraganaToKatakana(converted)
    let full = Japanese.halfWidthToFullWidth(t13n)
    return CharacterFormManager.getCharacterFormManager().convertPreeditString(full)
  },
  split: { splitConvertedImpl($0, $1, $2) })

private let kHalfKatakana = TransliteratorInterface(
  transliterate: { raw, converted in halfKatakanaTransliterate(raw, converted) },
  split: { position, raw, converted in
    let halfKatakana = halfKatakanaTransliterate(raw, converted)
    let hk = splitConvertedImpl(position, raw, halfKatakana)
    var r = TransliteratorSplit()
    if hk.result {
      r.rawLhs = hk.rawLhs
      r.rawRhs = hk.rawRhs
    } else {
      r.rawLhs = halfKatakanaToHiragana(hk.rawLhs)
      r.rawRhs = halfKatakanaToHiragana(hk.rawRhs)
    }
    r.convertedLhs = halfKatakanaToHiragana(hk.convertedLhs)
    r.convertedRhs = halfKatakanaToHiragana(hk.convertedRhs)
    r.result = hk.result
    return r
  })

private let kHalfAscii = TransliteratorInterface(
  transliterate: { raw, converted in
    let input = raw.isEmpty ? converted : raw
    return Japanese.fullWidthAsciiToHalfWidthAscii(input)
  },
  split: { splitRawImpl($0, $1, $2) })

private let kFullAscii = TransliteratorInterface(
  transliterate: { raw, converted in
    let input = raw.isEmpty ? converted : raw
    return Japanese.halfWidthAsciiToFullWidthAscii(input)
  },
  split: { splitRawImpl($0, $1, $2) })

/// Factory class providing basic TransliteratorInterface instances.
public enum Transliterators {
  public enum Transliterator: Int, Sendable, CaseIterable, CustomStringConvertible {
    /// Always uses a converted string rather than a raw string.
    /// This should be used as default value.
    case conversionString = 0
    /// Always uses a raw string rather than a converted string.
    case rawString
    /// Returns hiragana.
    case hiragana
    /// Returns full katakana.
    case fullKatakana
    /// Returns half katakana.
    case halfKatakana
    /// Returns full ascii.
    case fullAscii
    /// Returns half ascii.
    case halfAscii
    /// Special transliterator.
    /// Use locally assigned transliterator.
    /// Many methods don't accept this value.
    case local

    /// NUM_OF_TRANSLITERATOR
    public static let numOfTransliterator = 8

    /// Same as the C++ `AbslStringify` (the integer value).
    public var description: String { String(rawValue) }
  }

  /// Return a singleton instance of a TransliteratorInterface.
  /// LOCAL transliterator is not accepted.
  public static func getTransliterator(_ transliterator: Transliterator) -> TransliteratorInterface {
    switch transliterator {
    case .conversionString:
      return kConversionString
    case .rawString:
      return kRawString
    case .hiragana:
      return kHiragana
    case .fullKatakana:
      return kFullKatakana
    case .halfKatakana:
      return kHalfKatakana
    case .fullAscii:
      return kFullAscii
    case .halfAscii:
      return kHalfAscii
    default:
      GenmaiLog.error("Unexpected transliterator: \(transliterator)")
      // As fallback.
      return kConversionString
    }
  }

  public static func splitRaw(_ position: Int, _ raw: String, _ converted: String)
    -> TransliteratorSplit
  {
    splitRawImpl(position, raw, converted)
  }

  public static func splitConverted(_ position: Int, _ raw: String, _ converted: String)
    -> TransliteratorSplit
  {
    splitConvertedImpl(position, raw, converted)
  }
}
