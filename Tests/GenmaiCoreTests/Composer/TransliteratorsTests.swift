// Port of mozc/src/composer/transliterators_test.cc (3.35.6354).

import Testing

@testable import GenmaiCore

@Suite(.scopedConfigEnvironment) struct TransliteratorsTest {
  @Test func conversionStringSelector() {
    let t12r = Transliterators.getTransliterator(.conversionString)
    #expect(t12r.transliterate("zu", "ず") == "ず")
    #expect(t12r.transliterate("kk", "っk") == "っk")

    var s = TransliteratorSplit()
    s = t12r.split(1, "zu", "ず")
    #expect(s.result)
    #expect(s.rawLhs == "zu")
    #expect(s.rawRhs == "")
    #expect(s.convertedLhs == "ず")
    #expect(s.convertedRhs == "")

    s = t12r.split(1, "kk", "っk")
    #expect(s.result)
    #expect(s.rawLhs == "k")
    #expect(s.rawRhs == "k")
    #expect(s.convertedLhs == "っ")
    #expect(s.convertedRhs == "k")

    // Ideally "kkk" should be separated into "っ" and "っk", but it's
    // not implemented yet.
    s = t12r.split(1, "kkk", "っっk")
    #expect(!s.result)
    #expect(s.rawLhs == "っ")
    #expect(s.rawRhs == "っk")
    #expect(s.convertedLhs == "っ")
    #expect(s.convertedRhs == "っk")
  }

  @Test func rawStringSelector() {
    let t12r = Transliterators.getTransliterator(.rawString)
    #expect(t12r.transliterate("zu", "ず") == "zu")
    #expect(t12r.transliterate("kk", "っk") == "kk")

    var s = TransliteratorSplit()
    s = t12r.split(1, "zu", "ず")
    #expect(!s.result)
    #expect(s.rawLhs == "z")
    #expect(s.rawRhs == "u")
    #expect(s.convertedLhs == "z")
    #expect(s.convertedRhs == "u")

    s = t12r.split(1, "kk", "っk")
    #expect(s.result)
    #expect(s.rawLhs == "k")
    #expect(s.rawRhs == "k")
    #expect(s.convertedLhs == "っ")
    #expect(s.convertedRhs == "k")
  }

  @Test func hiraganaTransliterator() {
    let t12r = Transliterators.getTransliterator(.hiragana)
    #expect(t12r.transliterate("zu", "ず") == "ず")
    // Half width "k" is transliterated into full width "ｋ".
    #expect(t12r.transliterate("kk", "っk") == "っｋ")

    var s = TransliteratorSplit()
    s = t12r.split(1, "zu", "ず")
    #expect(s.result)
    #expect(s.rawLhs == "zu")
    #expect(s.rawRhs == "")
    #expect(s.convertedLhs == "ず")
    #expect(s.convertedRhs == "")

    s = t12r.split(1, "kk", "っk")
    #expect(s.result)
    #expect(s.rawLhs == "k")
    #expect(s.rawRhs == "k")
    #expect(s.convertedLhs == "っ")
    #expect(s.convertedRhs == "k")

    // Ideally "kkk" should be separated into "っ" and "っk", but it's
    // not implemented yet.
    s = t12r.split(1, "kkk", "っっk")
    #expect(!s.result)
    #expect(s.rawLhs == "っ")
    #expect(s.rawRhs == "っk")
    #expect(s.convertedLhs == "っ")
    #expect(s.convertedRhs == "っk")

    // "　"(full-width space), "　"(full-width space)
    #expect(t12r.transliterate(" ", "　") == "　")
    // " "(half-width space), "　"(full-width space)
    #expect(t12r.transliterate(" ", " ") == "　")
  }

  @Test func fullKatakanaTransliterator() {
    let t12r = Transliterators.getTransliterator(.fullKatakana)
    #expect(t12r.transliterate("zu", "ず") == "ズ")
    // Half width "k" is transliterated into full width "ｋ".
    #expect(t12r.transliterate("kk", "っk") == "ッｋ")

    var s = TransliteratorSplit()
    s = t12r.split(1, "zu", "ず")
    #expect(s.result)
    #expect(s.rawLhs == "zu")
    #expect(s.rawRhs == "")
    #expect(s.convertedLhs == "ず")
    #expect(s.convertedRhs == "")

    s = t12r.split(1, "kk", "っk")
    #expect(s.result)
    #expect(s.rawLhs == "k")
    #expect(s.rawRhs == "k")
    #expect(s.convertedLhs == "っ")
    #expect(s.convertedRhs == "k")

    // "　"(full-width space), "　"(full-width space)
    #expect(t12r.transliterate(" ", "　") == "　")
    // " "(half-width space), "　"(full-width space)
    #expect(t12r.transliterate(" ", " ") == "　")
  }

  @Test func halfKatakanaTransliterator() {
    let t12r = Transliterators.getTransliterator(.halfKatakana)
    #expect(t12r.transliterate("zu", "ず") == "ｽﾞ")
    // Half width "k" remains in the current implementation (can be changed).
    #expect(t12r.transliterate("kk", "っk") == "ｯk")

    var s = TransliteratorSplit()
    // "ｽﾞ" is split to "ｽ" and "ﾞ".
    s = t12r.split(1, "zu", "ず")
    #expect(!s.result)
    #expect(s.rawLhs == "す")
    #expect(s.rawRhs == "゛")
    #expect(s.convertedLhs == "す")
    #expect(s.convertedRhs == "゛")

    s = t12r.split(2, "zu", "ず")
    #expect(s.result)
    #expect(s.rawLhs == "zu")
    #expect(s.rawRhs == "")
    #expect(s.convertedLhs == "ず")
    #expect(s.convertedRhs == "")

    s = t12r.split(1, "kk", "っk")
    #expect(s.result)
    #expect(s.rawLhs == "k")
    #expect(s.rawRhs == "k")
    #expect(s.convertedLhs == "っ")
    #expect(s.convertedRhs == "k")

    // "　"(full-width space), "　"(half-width space)
    #expect(t12r.transliterate(" ", "　") == " ")
    // " "(half-width space), "　"(half-width space)
    #expect(t12r.transliterate(" ", " ") == " ")
  }

  @Test func halfAsciiTransliterator() {
    let t12r = Transliterators.getTransliterator(.halfAscii)
    #expect(t12r.transliterate("zu", "ず") == "zu")
    #expect(t12r.transliterate("kk", "っk") == "kk")

    var s = TransliteratorSplit()
    s = t12r.split(1, "zu", "ず")
    #expect(!s.result)
    #expect(s.rawLhs == "z")
    #expect(s.rawRhs == "u")
    #expect(s.convertedLhs == "z")
    #expect(s.convertedRhs == "u")

    s = t12r.split(1, "kk", "っk")
    #expect(s.result)
    #expect(s.rawLhs == "k")
    #expect(s.rawRhs == "k")
    #expect(s.convertedLhs == "っ")
    #expect(s.convertedRhs == "k")

    // "　"(full-width space), "　"(half-width space)
    #expect(t12r.transliterate(" ", "　") == " ")
    // " "(half-width space), "　"(half-width space)
    #expect(t12r.transliterate(" ", " ") == " ")
  }

  @Test func fullAsciiTransliterator() {
    let t12r = Transliterators.getTransliterator(.fullAscii)
    #expect(t12r.transliterate("zu", "ず") == "ｚｕ")
    #expect(t12r.transliterate("kk", "っk") == "ｋｋ")

    var s = TransliteratorSplit()
    s = t12r.split(1, "zu", "ず")
    #expect(!s.result)
    #expect(s.rawLhs == "z")
    #expect(s.rawRhs == "u")
    #expect(s.convertedLhs == "z")
    #expect(s.convertedRhs == "u")

    s = t12r.split(1, "kk", "っk")
    #expect(s.result)
    #expect(s.rawLhs == "k")
    #expect(s.rawRhs == "k")
    #expect(s.convertedLhs == "っ")
    #expect(s.convertedRhs == "k")

    // "　"(full-width space), "　"(full-width space)
    #expect(t12r.transliterate(" ", "　") == "　")
    // " "(half-width space), "　"(full-width space)
    #expect(t12r.transliterate(" ", " ") == "　")
  }

}
