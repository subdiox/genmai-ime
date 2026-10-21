// Port of mozc/src/base/strings/japanese.{h,cc} (3.35.6354).

/// `mozc::japanese`: Japanese utilities for character form transliteration.
public enum Japanese {
  private static func convert(_ rule: JapaneseRule, _ input: some StringProtocol) -> String {
    JapaneseInternal.convertUsingDoubleArray(rule, input)
  }

  public static func hiraganaToKatakana(_ input: some StringProtocol) -> String {
    convert(JapaneseInternal.hiraganaToKatakana, input)
  }

  public static func hiraganaToHalfwidthKatakana(_ input: some StringProtocol) -> String {
    // combine two rules
    fullWidthKatakanaToHalfWidthKatakana(hiraganaToKatakana(input))
  }

  public static func hiraganaToRomanji(_ input: some StringProtocol) -> String {
    convert(JapaneseInternal.hiraganaToRomanji, input)
  }

  public static func halfWidthAsciiToFullWidthAscii(_ input: some StringProtocol) -> String {
    convert(JapaneseInternal.halfwidthasciiToFullwidthascii, input)
  }

  public static func fullWidthAsciiToHalfWidthAscii(_ input: some StringProtocol) -> String {
    convert(JapaneseInternal.fullwidthasciiToHalfwidthascii, input)
  }

  public static func hiraganaToFullwidthRomanji(_ input: some StringProtocol) -> String {
    halfWidthAsciiToFullWidthAscii(hiraganaToRomanji(input))
  }

  public static func romanjiToHiragana(_ input: some StringProtocol) -> String {
    convert(JapaneseInternal.romanjiToHiragana, input)
  }

  public static func katakanaToHiragana(_ input: some StringProtocol) -> String {
    convert(JapaneseInternal.katakanaToHiragana, input)
  }

  public static func halfWidthKatakanaToFullWidthKatakana(_ input: some StringProtocol) -> String {
    convert(JapaneseInternal.halfwidthkatakanaToFullwidthkatakana, input)
  }

  public static func fullWidthKatakanaToHalfWidthKatakana(_ input: some StringProtocol) -> String {
    convert(JapaneseInternal.fullwidthkatakanaToHalfwidthkatakana, input)
  }

  public static func fullWidthToHalfWidth(_ input: some StringProtocol) -> String {
    fullWidthKatakanaToHalfWidthKatakana(fullWidthAsciiToHalfWidthAscii(input))
  }

  public static func halfWidthToFullWidth(_ input: some StringProtocol) -> String {
    halfWidthKatakanaToFullWidthKatakana(halfWidthAsciiToFullWidthAscii(input))
  }

  // TODO(tabata): Add another function to split voice mark
  // of some UNICODE only characters (required to display
  // and commit for old clients)
  public static func normalizeVoicedSoundMark(_ input: some StringProtocol) -> String {
    convert(JapaneseInternal.normalizeVoicedSound, input)
  }

  /// Returns alignment as (romanji piece, hiragana piece) pairs.
  public static func alignRomanjiToHiragana(_ input: some StringProtocol) -> [(String, String)] {
    JapaneseInternal.alignUsingDoubleArray(JapaneseInternal.romanjiToHiragana, input)
  }

  /// Returns alignment as (hiragana piece, romanji piece) pairs.
  public static func alignHiraganaToRomanji(_ input: some StringProtocol) -> [(String, String)] {
    JapaneseInternal.alignUsingDoubleArray(JapaneseInternal.hiraganaToRomanji, input)
  }
}
