// Port of mozc/src/transliteration/transliteration_test.cc (3.35.6354).

import Testing

@testable import GenmaiCore

@Suite struct T13nTest {
  private func check(_ predicate: (TransliterationType) -> Bool, trueFor: Set<TransliterationType>) {
    for type in TransliterationType.allCases {
      #expect(predicate(type) == trueFor.contains(type), "\(type)")
    }
  }

  @Test func isInFullAsciiTypes() {
    check(
      T13n.isInFullAsciiTypes,
      trueFor: [.fullAscii, .fullAsciiUpper, .fullAsciiLower, .fullAsciiCapitalized])
  }

  @Test func isInHalfAsciiTypes() {
    check(
      T13n.isInHalfAsciiTypes,
      trueFor: [.halfAscii, .halfAsciiUpper, .halfAsciiLower, .halfAsciiCapitalized])
  }

  @Test func isInHiraganaTypes() {
    check(T13n.isInHiraganaTypes, trueFor: [.hiragana])
  }

  @Test func isInHalfKatakanaTypes() {
    check(T13n.isInHalfKatakanaTypes, trueFor: [.halfKatakana])
  }

  @Test func isInFullKatakanaTypes() {
    check(T13n.isInFullKatakanaTypes, trueFor: [.fullKatakana])
  }

  @Test func toggleFullAsciiTypes() {
    #expect(T13n.toggleFullAsciiTypes(.hiragana) == .fullAscii)
    #expect(T13n.toggleFullAsciiTypes(.fullAscii) == .fullAsciiUpper)
    #expect(T13n.toggleFullAsciiTypes(.fullAsciiUpper) == .fullAsciiLower)
    #expect(T13n.toggleFullAsciiTypes(.fullAsciiLower) == .fullAsciiCapitalized)
    #expect(T13n.toggleFullAsciiTypes(.fullAsciiCapitalized) == .fullAscii)
  }

  @Test func toggleHalfAsciiTypes() {
    #expect(T13n.toggleHalfAsciiTypes(.hiragana) == .halfAscii)
    #expect(T13n.toggleHalfAsciiTypes(.halfAscii) == .halfAsciiUpper)
    #expect(T13n.toggleHalfAsciiTypes(.halfAsciiUpper) == .halfAsciiLower)
    #expect(T13n.toggleHalfAsciiTypes(.halfAsciiLower) == .halfAsciiCapitalized)
    #expect(T13n.toggleHalfAsciiTypes(.halfAsciiCapitalized) == .halfAscii)
  }
}
