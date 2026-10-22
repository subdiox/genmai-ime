// Port of mozc/src/converter/key_corrector_test.cc (3.35.6354).

import Testing

@testable import GenmaiCore

@Suite struct KeyCorrectorTests {
  private let invalid = KeyCorrector.invalidPosition()

  @Test func keyCorrectorBasicTest() {
    #expect(!KeyCorrector.isValidPosition(KeyCorrector.invalidPosition()))
    #expect(KeyCorrector.isInvalidPosition(KeyCorrector.invalidPosition()))

    do {
      let corrector = KeyCorrector("", .kana, 0)
      #expect(corrector.mode == .kana)
      #expect(!corrector.isAvailable())
    }
    do {
      let corrector = KeyCorrector("", .roman, 0)
      #expect(corrector.mode == .roman)
      #expect(!corrector.isAvailable())
    }
    do {
      let corrector = KeyCorrector("てすと", .roman, 0)
      #expect(corrector.isAvailable())
      #expect(corrector.originalKey == "てすと")
    }
  }

  @Test func keyCorrectorKanaTest() {
    let corrector = KeyCorrector("みんあであそぼう", .kana, 0)
    #expect(!corrector.isAvailable())
    #expect(corrector.correctedKey == "")
    #expect(corrector.originalKey == "")
    #expect(corrector.getCorrectedPosition(0) == invalid)
    #expect(corrector.getOriginalPosition(0) == invalid)
  }

  @Test(arguments: [
    ("ん", "ん"),
    ("かん", "かん"),
    ("かに", "かに"),
    ("かｍ", "かｍ"),
    ("みんあであそぼう", "みんなであそぼう"),
    // don't rewrite 1st "ん"
    ("んあであそぼう", "んあであそぼう"),
    ("こんかいのみんあはこんんでた", "こんかいのみんなはこんでた"),
    ("みんあみんいみんうみんえみんおみんんか", "みんなみんにみんぬみんねみんのみんか"),
    ("こんんにちは", "こんにちは"),
    ("こんんいちは", "こんにちは"),
    ("しぜんんお", "しぜんの"),
    ("あんんんたい", "あんんんたい"),
    ("せにょう", "せんよう"),
    ("せにゃうせにゅうせにょう", "せんやうせんゆうせんよう"),
    ("こんんにちはせにょう", "こんにちはせんよう"),
    ("おんあのここんいちは", "おんなのここんにちは"),
    ("きっって", "きって"),
    ("きっっって", "きっっって"),
    ("きっっっ", "きっっっ"),
    ("っっ", "っっ"),
    ("しｍばし", "しんばし"),
    ("しｍはししｍぱしー", "しｍはししんぱしー"),
    ("ちゅごく", "ちゅうごく"),
    ("きゅきゅしゃ", "きゅうきゅうしゃ"),
  ])
  func keyCorrectorRomanTest(input: String, expected: String) {
    let corrector = KeyCorrector(input, .roman, 0)
    #expect(corrector.isAvailable())
    #expect(corrector.correctedKey == expected)
    #expect(corrector.originalKey == input)
  }

  @Test func keyCorrectorRomanPositionTest() {
    do {
      let corrector = KeyCorrector("みんあであそぼう", .roman, 0)
      #expect(corrector.isAvailable())
      #expect(corrector.correctedKey == "みんなであそぼう")
      for pos in [0, 1, 3, 6, 9, 12] {
        #expect(corrector.getCorrectedPosition(pos) == pos)
        #expect(corrector.getOriginalPosition(pos) == pos)
      }
      #expect(corrector.getCorrectedPosition(30) == invalid)
      #expect(corrector.getOriginalPosition(30) == invalid)
    }
    do {
      let corrector = KeyCorrector("こんんにちは", .roman, 0)
      #expect(corrector.isAvailable())
      #expect(corrector.correctedKey == "こんにちは")

      #expect(corrector.getCorrectedPosition(0) == 0)
      #expect(corrector.getCorrectedPosition(1) == invalid)
      #expect(corrector.getCorrectedPosition(3) == invalid)
      #expect(corrector.getCorrectedPosition(6) == invalid)
      #expect(corrector.getCorrectedPosition(9) == 6)
      #expect(corrector.getCorrectedPosition(12) == 9)
      #expect(corrector.getCorrectedPosition(30) == invalid)

      #expect(corrector.getOriginalPosition(0) == 0)
      #expect(corrector.getOriginalPosition(1) == invalid)
      #expect(corrector.getOriginalPosition(3) == invalid)
      #expect(corrector.getOriginalPosition(6) == 9)
      #expect(corrector.getOriginalPosition(9) == 12)
      #expect(corrector.getOriginalPosition(12) == 15)
      #expect(corrector.getOriginalPosition(30) == invalid)
    }
    do {
      let corrector = KeyCorrector("こんんにちはせにょう", .roman, 0)
      #expect(corrector.isAvailable())
      #expect(corrector.correctedKey == "こんにちはせんよう")

      #expect(corrector.getCorrectedPosition(0) == 0)
      #expect(corrector.getCorrectedPosition(3) == invalid)
      #expect(corrector.getCorrectedPosition(9) == 6)
      #expect(corrector.getCorrectedPosition(12) == 9)
      #expect(corrector.getCorrectedPosition(24) == 21)
      #expect(corrector.getCorrectedPosition(27) == 24)

      #expect(corrector.getOriginalPosition(0) == 0)
      #expect(corrector.getOriginalPosition(3) == invalid)
      #expect(corrector.getOriginalPosition(6) == 9)
      #expect(corrector.getOriginalPosition(24) == 27)
      #expect(corrector.getOriginalPosition(21) == 24)
    }
  }

  @Test func keyCorrectorRomanCorrectedPrefixTest() {
    do {
      let corrector = KeyCorrector("てすと", .roman, 0)
      #expect(corrector.isAvailable())
      // same as the original key
      for pos in 0..<4 {
        #expect(corrector.getCorrectedPrefix(pos).isEmpty)
      }
    }
    do {
      let corrector = KeyCorrector("みんあであそぼう", .roman, 0)
      #expect(corrector.isAvailable())
      #expect(corrector.correctedKey == "みんなであそぼう")
      #expect(corrector.getCorrectedPrefix(0) == "みんなであそぼう")
      #expect(corrector.getCorrectedPrefix(3) == "んなであそぼう")
      #expect(corrector.getCorrectedPrefix(6) == "なであそぼう")
      #expect(corrector.getCorrectedPrefix(9) == "")
    }
    do {
      let corrector = KeyCorrector("こんんにちは", .roman, 0)
      #expect(corrector.isAvailable())
      #expect(corrector.correctedKey == "こんにちは")
      #expect(corrector.getCorrectedPrefix(0) == "こんにちは")
      #expect(corrector.getCorrectedPrefix(3).isEmpty)
      #expect(corrector.getCorrectedPrefix(6).isEmpty)
      #expect(corrector.getCorrectedPrefix(9).isEmpty)
    }
    do {
      let corrector = KeyCorrector("こんんにちはせにょう", .roman, 0)
      #expect(corrector.isAvailable())
      #expect(corrector.correctedKey == "こんにちはせんよう")
      #expect(corrector.getCorrectedPrefix(0) == "こんにちはせんよう")
      #expect(corrector.getCorrectedPrefix(3).isEmpty)
      #expect(corrector.getCorrectedPrefix(6).isEmpty)
      #expect(corrector.getCorrectedPrefix(9) == "にちはせんよう")
    }
  }

  @Test func keyCorrectorRomanGetOriginalOffsetTest() {
    do {
      let corrector = KeyCorrector("てすと", .roman, 0)
      #expect(corrector.isAvailable())
      #expect(corrector.getOriginalOffset(0, 3) == 3)
      #expect(corrector.getOriginalOffset(0, 6) == 6)
      #expect(corrector.getOriginalOffset(0, 9) == 9)
      #expect(corrector.getOriginalOffset(3, 3) == 3)
      #expect(corrector.getOriginalOffset(3, 6) == 6)
    }
    do {
      let corrector = KeyCorrector("みんあ", .roman, 0)
      #expect(corrector.isAvailable())
      #expect(corrector.getOriginalOffset(0, 3) == 3)
      #expect(corrector.getOriginalOffset(0, 6) == 6)
      #expect(corrector.getOriginalOffset(0, 9) == 9)
    }
    do {
      let corrector = KeyCorrector("きっって", .roman, 0)
      #expect(corrector.isAvailable())
      #expect(corrector.getOriginalOffset(0, 9) == 12)
    }
    do {
      let corrector = KeyCorrector("こんんにちは", .roman, 0)
      #expect(corrector.isAvailable())
      #expect(corrector.correctedKey == "こんにちは")
      #expect(corrector.getOriginalOffset(0, 3) == invalid)
      #expect(corrector.getOriginalOffset(0, 6) == 9)
      #expect(corrector.getOriginalOffset(0, 9) == 12)
      #expect(corrector.getOriginalOffset(3, 3) == invalid)
      #expect(corrector.getOriginalOffset(3, 6) == invalid)
      #expect(corrector.getOriginalOffset(6, 3) == invalid)
      #expect(corrector.getOriginalOffset(9, 3) == 3)
      #expect(corrector.getOriginalOffset(9, 6) == 6)
    }
  }

  // Check if UCS4 is supported. b/3386634
  @Test func ucs4IsAvailable() {
    #expect(KeyCorrector("𠮟", .roman, 0).isAvailable())  // UCS4 char in UTF8
    #expect(KeyCorrector("こ", .roman, 0).isAvailable())  // UCS2 char in UTF8
  }

  @Test func ucs4Test() {
    let corrector = KeyCorrector("😁みんあ", .roman, 0)
    #expect(corrector.isAvailable())
    #expect(corrector.getOriginalOffset(0, 7) == 7)
    #expect(corrector.getOriginalOffset(0, 10) == 10)
    #expect(corrector.getOriginalOffset(0, 13) == 13)
  }

  // Should not rewrite the character which is at the beginning of current input
  @Test func bug3046266Test() {
    let corrector = KeyCorrector("かんあか", .roman, 6)  // history_size = 6
    #expect(corrector.isAvailable())
    // same as the original key
    for pos in 0..<4 {
      #expect(corrector.getCorrectedPrefix(pos).isEmpty)
    }
  }

  // Swift-only.
  @Test func correctedCostPenalty() {
    #expect(KeyCorrector.getCorrectedCostPenalty("こんんにちは") == 0)
    #expect(KeyCorrector.getCorrectedCostPenalty("きっって") == 0)
    #expect(KeyCorrector.getCorrectedCostPenalty("みんなで") == 3000)
  }
}
