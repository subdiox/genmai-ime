// Port of mozc/src/converter/reverse_converter_test.cc (3.35.6354).

import GenmaiBase
import Testing

@testable import GenmaiCore

@Suite("ReverseConverter")
struct ReverseConverterTests {
  @Test func reverseConvert() throws {
    let immutableConverter = try TestModules.mock().makeImmutableConverter()
    let reverseConverter = ReverseConverter(immutableConverter)

    let kHonKanji = "本"
    let kHonHiragana = "ほん"
    let kMuryouKanji = "無料"
    let kMuryouHiragana = "むりょう"
    let kFullWidthSpace = "　"  // full-width space

    /// Converts `input` and returns the top values of the conversion
    /// segments.
    func convert(_ input: String) -> [String]? {
      let segments = Segments()
      segments.addSegment().setKey(input)
      guard reverseConverter.reverseConvert(input, segments) else { return nil }
      return segments.conversionSegments.map {
        $0.candidatesSize > 0 ? $0.candidate(0).value : "<none>"
      }
    }

    // Test for single Kanji character.
    #expect(convert(kHonKanji) == [kHonHiragana])
    // Test for multi-Kanji character.
    #expect(convert(kMuryouKanji) == [kMuryouHiragana])
    // Test for multi terms separated by a space.
    #expect(convert(kHonKanji + " " + kMuryouKanji) == [kHonHiragana, " ", kMuryouHiragana])
    // Test for multi terms separated by multiple spaces.
    #expect(convert(kHonKanji + "   " + kMuryouKanji) == [kHonHiragana, "   ", kMuryouHiragana])
    // Test for leading white spaces.
    #expect(convert("  " + kHonKanji) == ["  ", kHonHiragana])
    // Test for trailing white spaces.
    #expect(convert(kMuryouKanji + "  ") == [kMuryouHiragana, "  "])
    // Test for multi terms separated by a full-width space.
    #expect(
      convert(kHonKanji + kFullWidthSpace + kMuryouKanji)
        == [kHonHiragana, kFullWidthSpace, kMuryouHiragana])
    // Test for multi terms separated by two full-width spaces.
    let kFullWidthSpace2 = kFullWidthSpace + kFullWidthSpace
    #expect(
      convert(kHonKanji + kFullWidthSpace2 + kMuryouKanji)
        == [kHonHiragana, kFullWidthSpace2, kMuryouHiragana])
    // Test for multi terms separated by the mix of full- and half-width
    // spaces.
    let kFullWidthSpaceMix = kFullWidthSpace + " "
    #expect(
      convert(kHonKanji + kFullWidthSpaceMix + kMuryouKanji)
        == [kHonHiragana, kFullWidthSpaceMix, kMuryouHiragana])

    // Test for math expressions; see b/9398304.
    do {
      let kInputHalf = "365*24*60*60*1000="
      let segments = Segments()
      segments.addSegment().setKey(kInputHalf)
      #expect(reverseConverter.reverseConvert(kInputHalf, segments))
      try #require(segments.segmentsSize == 1)
      try #require(segments.conversionSegment(0).candidatesSize == 1)
      #expect(segments.conversionSegment(0).candidate(0).value == kInputHalf)

      // Test for full-width characters.
      let kInputFull = "３６５＊２４＊６０＊６０＊１０００＝"
      segments.clear()
      segments.addSegment().setKey(kInputFull)
      #expect(reverseConverter.reverseConvert(kInputFull, segments))
      try #require(segments.segmentsSize == 1)
      try #require(segments.conversionSegment(0).candidatesSize == 1)
      #expect(segments.conversionSegment(0).candidate(0).value == kInputHalf)
    }
  }
}
