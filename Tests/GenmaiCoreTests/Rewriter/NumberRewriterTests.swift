// Port of mozc/src/rewriter/number_rewriter_test.cc (3.35.6354).
//
// testing::TestWithTempUserProfile + CharacterFormManager::ClearHistory() in
// SetUp/TearDown become the `.scopedConfigEnvironment` trait (fresh
// task-local CharacterFormManager per test). The parameterized
// NumberStyleLearningTest uses Swift Testing arguments.

import Foundation
import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private let kKanjiDescription = "漢数字"
private let kArabicDescription = "数字"
private let kOldKanjiDescription = "大字"
private let kMaruNumberDescription = "丸数字"
private let kRomanCapitalDescription = "ローマ数字(大文字)"
private let kRomanNoCapitalDescription = "ローマ数字(小文字)"
private let kSuperscriptDescription = "上付き文字"
private let kSubscriptDescription = "下付き文字"

private func findValue(_ segment: Segment, _ value: String) -> Bool {
  for i in 0..<segment.candidatesSize where segment.candidate(i).value.bytesEqual(value) {
    return true
  }
  return false
}

private func setupSegments(
  _ posMatcher: PosMatcher, _ candidateValue: String, _ segments: Segments
) -> Segment {
  segments.clear()
  let segment = segments.pushBackSegment()
  let candidate = segment.addCandidate()
  candidate.lid = posMatcher.getNumberId()
  candidate.rid = posMatcher.getNumberId()
  candidate.value = candidateValue
  candidate.contentValue = candidateValue
  return segment
}

private func hasDescription(_ segment: Segment, _ description: String) -> Bool {
  for i in 0..<segment.candidatesSize
  where segment.candidate(i).description.bytesEqual(description) {
    return true
  }
  return false
}

// Find candidate id
private func findCandidateId(_ segment: Segment, _ value: String) -> Int? {
  for i in 0..<segment.candidatesSize where segment.candidate(i).value.bytesEqual(value) {
    return i
  }
  return nil
}

private struct ExpectResult {
  let value: String
  let contentValue: String
  let description: String
  init(_ value: String, _ contentValue: String, _ description: String) {
    self.value = value
    self.contentValue = contentValue
    self.description = description
  }
}

private func expectResults(
  _ seg: Segment, _ expected: [ExpectResult], sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(seg.candidatesSize == expected.count, sourceLocation: sourceLocation)
  for i in 0..<min(expected.count, seg.candidatesSize) {
    #expect(seg.candidate(i).value == expected[i].value, "i = \(i)", sourceLocation: sourceLocation)
    #expect(
      seg.candidate(i).contentValue == expected[i].contentValue, "i = \(i)",
      sourceLocation: sourceLocation)
    #expect(
      seg.candidate(i).description == expected[i].description, "i = \(i)",
      sourceLocation: sourceLocation)
  }
}

private struct NumberRewriterTestFixture {
  let posMatcher: PosMatcher
  let defaultRequest = ConversionRequest()
  private let dataManager: MockDataManager

  init() throws {
    dataManager = try ConverterCoreTestSupport.mockDataManager()
    posMatcher = PosMatcher(dataManager.getPosMatcherData())
  }

  func createNumberRewriter() -> NumberRewriter {
    NumberRewriter(dataManager.getCounterSuffixSortedArray(), posMatcher)
  }
}

// Creates Segments which have one conversion segment.
// The number candidate will be inserted at the `base_pos`.
private func prepareNumberSegments(
  _ segmentKey: String, _ numberValue: String, _ basePos: Int, _ posMatcher: PosMatcher
) -> Segments {
  let segments = Segments()
  do {
    let seg = segments.addSegment()
    seg.setKey(segmentKey)
    for i in 0..<basePos {
      let c = seg.addCandidate()
      c.key = segmentKey
      c.contentKey = c.key
      c.value = "placeholder\(i)"
      c.contentValue = c.value
    }
    let c = seg.addCandidate()
    c.key = segmentKey
    c.contentKey = c.key
    c.value = numberValue
    c.contentValue = c.value
    c.lid = posMatcher.getNumberId()
    c.rid = posMatcher.getNumberId()
  }

  return segments
}

private func learnNumberStyle(
  _ request: ConversionRequest, _ posMatcher: PosMatcher, _ rewriter: NumberRewriter
) throws {
  let segments = prepareNumberSegments("3000", "3000", 3, posMatcher)
  _ = rewriter.rewrite(request, segments)
  try #require(segments.conversionSegmentsSize == 1)
  let seg = segments.conversionSegment(0)
  try #require(seg.candidatesSize > 9)
  try #require(seg.candidate(3).style == .defaultStyle)
  try #require(seg.candidate(3).value == "3000")
  try #require(seg.candidate(4).style == .numberKanjiArabic)
  try #require(seg.candidate(4).value == "三〇〇〇")
  try #require(seg.candidate(5).style == .defaultStyle)
  try #require(seg.candidate(5).value == "３０００")
  try #require(seg.candidate(6).style == .numberSeparatedArabicHalfwidth)
  try #require(seg.candidate(6).value == "3,000")
  try #require(seg.candidate(7).style == .numberSeparatedArabicFullwidth)
  try #require(seg.candidate(7).value == "３，０００")

  segments.mutableConversionSegment(0).moveCandidate(6, 0)
  segments.mutableConversionSegment(0).setSegmentType(.fixedValue)
  rewriter.finish(request, segments)
}

@Suite(
  .scopedConfigEnvironment,
  .enabled(if: ConverterCoreTestSupport.hasMockData, ConverterCoreTestSupport.mockDataMissing))
struct NumberRewriterTests {
  @Test func basicTest() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()

    let segments = Segments()
    let seg = segments.pushBackSegment()
    let candidate = seg.addCandidate()
    candidate.lid = f.posMatcher.getNumberId()
    candidate.rid = f.posMatcher.getNumberId()
    candidate.value = "012"
    candidate.contentValue = "012"
    candidate.key = "012"
    candidate.contentKey = "012"

    #expect(numberRewriter.rewrite(f.defaultRequest, segments))

    expectResults(
      seg,
      [
        ExpectResult("012", "012", ""),
        ExpectResult("〇一二", "〇一二", kKanjiDescription),
        ExpectResult("０１２", "０１２", kArabicDescription),
        ExpectResult("十二", "十二", kKanjiDescription),
        ExpectResult("壱拾弐", "壱拾弐", kOldKanjiDescription),
        ExpectResult("Ⅻ", "Ⅻ", kRomanCapitalDescription),
        ExpectResult("ⅻ", "ⅻ", kRomanNoCapitalDescription),
        ExpectResult("⑫", "⑫", kMaruNumberDescription),
        ExpectResult("0xc", "0xc", "16進数"),
        ExpectResult("014", "014", "8進数"),
        ExpectResult("0b1100", "0b1100", "2進数"),
      ])
    seg.clearCandidates()
  }

  @Test func requestType() throws {
    let f = try NumberRewriterTestFixture()
    let testDataList: [(RequestType, Int)] = [
      (.conversion, 11),  // 11 comes from BasicTest
      (.reverseConversion, 8),
      (.prediction, 8),
      (.suggestion, 8),
    ]

    let numberRewriter = f.createNumberRewriter()

    for (requestType, expectedCandidateNumber) in testDataList {
      let segments = Segments()
      let seg = segments.pushBackSegment()
      let candidate = seg.addCandidate()
      candidate.lid = f.posMatcher.getNumberId()
      candidate.rid = f.posMatcher.getNumberId()
      candidate.value = "012"
      candidate.contentValue = "012"
      let request = ConversionRequestBuilder().setRequestType(requestType).build()
      #expect(numberRewriter.rewrite(request, segments))
      #expect(seg.candidatesSize == expectedCandidateNumber)
    }
  }

  @Test func basicTestWithSuffix() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()

    let segments = Segments()
    let seg = segments.pushBackSegment()
    let candidate = seg.addCandidate()
    candidate.lid = f.posMatcher.getNumberId()
    candidate.rid = f.posMatcher.getNumberId()
    candidate.value = "012が"
    candidate.contentValue = "012"
    candidate.key = "012が"
    candidate.contentKey = "012"

    #expect(numberRewriter.rewrite(f.defaultRequest, segments))

    expectResults(
      seg,
      [
        ExpectResult("012が", "012", ""),
        ExpectResult("〇一二が", "〇一二", kKanjiDescription),
        ExpectResult("０１２が", "０１２", kArabicDescription),
        ExpectResult("十二が", "十二", kKanjiDescription),
        ExpectResult("壱拾弐が", "壱拾弐", kOldKanjiDescription),
        ExpectResult("Ⅻが", "Ⅻ", kRomanCapitalDescription),
        ExpectResult("ⅻが", "ⅻ", kRomanNoCapitalDescription),
        ExpectResult("⑫が", "⑫", kMaruNumberDescription),
        ExpectResult("0xcが", "0xc", "16進数"),
        ExpectResult("014が", "014", "8進数"),
        ExpectResult("0b1100が", "0b1100", "2進数"),
      ])

    seg.clearCandidates()
  }

  @Test func basicTestWithNumberSuffix() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()

    let segments = Segments()
    let seg = segments.pushBackSegment()
    let candidate = seg.addCandidate()
    candidate.lid = f.posMatcher.getNumberId()
    candidate.rid = f.posMatcher.getCounterSuffixWordId()
    candidate.value = "十五個"
    candidate.contentValue = "十五個"

    #expect(numberRewriter.rewrite(f.defaultRequest, segments))

    expectResults(
      seg,
      [
        ExpectResult("十五個", "十五個", ""),
        ExpectResult("15個", "15個", ""),
      ])
    seg.clearCandidates()
  }

  @Test func testWithMultipleNumberSuffix() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()

    let segments = Segments()
    let seg = segments.pushBackSegment()
    var candidate = seg.addCandidate()
    candidate.lid = f.posMatcher.getNumberId()
    candidate.rid = f.posMatcher.getCounterSuffixWordId()
    candidate.value = "十五回"
    candidate.contentValue = "十五回"
    candidate = seg.addCandidate()
    candidate.lid = f.posMatcher.getNumberId()
    candidate.rid = f.posMatcher.getCounterSuffixWordId()
    candidate.value = "十五階"
    candidate.contentValue = "十五階"

    #expect(numberRewriter.rewrite(f.defaultRequest, segments))

    expectResults(
      seg,
      [
        ExpectResult("十五回", "十五回", ""),
        ExpectResult("15回", "15回", ""),
        ExpectResult("十五階", "十五階", ""),
        ExpectResult("15階", "15階", ""),
      ])

    seg.clearCandidates()
  }

  @Test func specialFormBoundaries() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()
    let segments = Segments()

    // Roman numerals don't have zeros.
    var seg = setupSegments(f.posMatcher, "0", segments)
    #expect(numberRewriter.rewrite(f.defaultRequest, segments))
    #expect(!hasDescription(seg, kRomanCapitalDescription))
    #expect(!hasDescription(seg, kRomanNoCapitalDescription))
    // "0" has a circled number, superscripts and subscripts.
    #expect(hasDescription(seg, kMaruNumberDescription))
    #expect(hasDescription(seg, kSuperscriptDescription))
    #expect(hasDescription(seg, kSubscriptDescription))

    // "1" has special forms.
    seg = setupSegments(f.posMatcher, "1", segments)
    #expect(numberRewriter.rewrite(f.defaultRequest, segments))
    #expect(hasDescription(seg, kMaruNumberDescription))
    #expect(hasDescription(seg, kRomanCapitalDescription))
    #expect(hasDescription(seg, kRomanNoCapitalDescription))
    #expect(hasDescription(seg, kSuperscriptDescription))
    #expect(hasDescription(seg, kSubscriptDescription))

    // "12" has every special forms except superscript and subscript.
    seg = setupSegments(f.posMatcher, "12", segments)
    #expect(numberRewriter.rewrite(f.defaultRequest, segments))
    #expect(hasDescription(seg, kMaruNumberDescription))
    #expect(hasDescription(seg, kRomanCapitalDescription))
    #expect(hasDescription(seg, kRomanNoCapitalDescription))
    #expect(!hasDescription(seg, kSuperscriptDescription))
    #expect(!hasDescription(seg, kSubscriptDescription))

    // "13" doesn't have roman forms.
    seg = setupSegments(f.posMatcher, "13", segments)
    #expect(numberRewriter.rewrite(f.defaultRequest, segments))
    #expect(hasDescription(seg, kMaruNumberDescription))
    #expect(!hasDescription(seg, kRomanCapitalDescription))
    #expect(!hasDescription(seg, kRomanNoCapitalDescription))

    // "50" has circled numerics.
    seg = setupSegments(f.posMatcher, "50", segments)
    #expect(numberRewriter.rewrite(f.defaultRequest, segments))
    #expect(hasDescription(seg, kMaruNumberDescription))
    #expect(!hasDescription(seg, kRomanCapitalDescription))
    #expect(!hasDescription(seg, kRomanNoCapitalDescription))

    // "51" doesn't have special forms.
    seg = setupSegments(f.posMatcher, "51", segments)
    #expect(numberRewriter.rewrite(f.defaultRequest, segments))
    #expect(!hasDescription(seg, kMaruNumberDescription))
    #expect(!hasDescription(seg, kRomanCapitalDescription))
    #expect(!hasDescription(seg, kRomanNoCapitalDescription))
    #expect(!hasDescription(seg, kSuperscriptDescription))
    #expect(!hasDescription(seg, kSubscriptDescription))
  }

  @Test func oneOfCandidatesIsEmpty() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()

    let segments = Segments()
    let seg = segments.pushBackSegment()
    let firstCandidate = seg.addCandidate()

    // this candidate should be skipped
    firstCandidate.value = ""
    firstCandidate.contentValue = firstCandidate.value

    let secondCandidate = seg.addCandidate()

    secondCandidate.value = "0"
    secondCandidate.lid = f.posMatcher.getNumberId()
    secondCandidate.rid = f.posMatcher.getNumberId()
    secondCandidate.contentValue = secondCandidate.value
    secondCandidate.key = "0"
    secondCandidate.contentKey = "0"

    #expect(numberRewriter.rewrite(f.defaultRequest, segments))

    try #require(seg.candidatesSize >= 5)
    #expect(seg.candidate(0).value == "")
    #expect(seg.candidate(0).contentValue == "")
    #expect(seg.candidate(0).description == "")

    #expect(seg.candidate(1).value == "0")
    #expect(seg.candidate(1).contentValue == "0")
    #expect(seg.candidate(1).description == "")

    #expect(seg.candidate(2).value == "〇")
    #expect(seg.candidate(2).contentValue == "〇")
    #expect(seg.candidate(2).description == kKanjiDescription)

    #expect(seg.candidate(3).value == "０")
    #expect(seg.candidate(3).contentValue == "０")
    #expect(seg.candidate(3).description == kArabicDescription)

    #expect(seg.candidate(4).value == "零")
    #expect(seg.candidate(4).contentValue == "零")
    #expect(seg.candidate(4).description == kOldKanjiDescription)

    seg.clearCandidates()
  }

  @Test func rewriteDoesNotHappen() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()

    let segments = Segments()
    let seg = segments.pushBackSegment()
    let candidate = seg.addCandidate()

    candidate.value = "タンポポ"
    candidate.contentValue = candidate.value

    // Number rewrite should not occur
    #expect(!numberRewriter.rewrite(f.defaultRequest, segments))

    // Number of candidates should be maintained
    #expect(seg.candidatesSize == 1)

    seg.clearCandidates()
  }

  @Test func numberIsZero() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()

    let segments = Segments()
    let seg = segments.pushBackSegment()
    let candidate = seg.addCandidate()
    candidate.lid = f.posMatcher.getNumberId()
    candidate.rid = f.posMatcher.getNumberId()
    candidate.value = "0"
    candidate.contentValue = "0"
    candidate.key = "0"
    candidate.contentKey = "0"

    #expect(numberRewriter.rewrite(f.defaultRequest, segments))

    expectResults(
      seg,
      [
        ExpectResult("0", "0", ""),
        ExpectResult("〇", "〇", kKanjiDescription),
        ExpectResult("０", "０", kArabicDescription),
        ExpectResult("零", "零", kOldKanjiDescription),
        ExpectResult("⓪", "⓪", kMaruNumberDescription),
        ExpectResult("⁰", "⁰", kSuperscriptDescription),
        ExpectResult("₀", "₀", kSubscriptDescription),
      ])

    seg.clearCandidates()
  }

  @Test func numberIsZeroZero() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()

    let segments = Segments()
    let seg = segments.pushBackSegment()
    let candidate = seg.addCandidate()
    candidate.lid = f.posMatcher.getNumberId()
    candidate.rid = f.posMatcher.getNumberId()
    candidate.value = "00"
    candidate.contentValue = "00"
    candidate.key = "00"
    candidate.contentKey = "00"

    #expect(numberRewriter.rewrite(f.defaultRequest, segments))

    expectResults(
      seg,
      [
        ExpectResult("00", "00", ""),
        ExpectResult("〇〇", "〇〇", kKanjiDescription),
        ExpectResult("００", "００", kArabicDescription),
        ExpectResult("零", "零", kOldKanjiDescription),
        ExpectResult("⓪", "⓪", kMaruNumberDescription),
        ExpectResult("⁰", "⁰", kSuperscriptDescription),
        ExpectResult("₀", "₀", kSubscriptDescription),
      ])

    seg.clearCandidates()
  }

  @Test func numberIs19Digit() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()

    let segments = Segments()
    let seg = segments.pushBackSegment()
    let candidate = seg.addCandidate()
    candidate.lid = f.posMatcher.getNumberId()
    candidate.rid = f.posMatcher.getNumberId()
    candidate.value = "1000000000000000000"
    candidate.contentValue = "1000000000000000000"
    candidate.key = "1000000000000000000"
    candidate.contentKey = "1000000000000000000"

    #expect(numberRewriter.rewrite(f.defaultRequest, segments))

    expectResults(
      seg,
      [
        ExpectResult("1000000000000000000", "1000000000000000000", ""),
        ExpectResult(
          "一〇〇〇〇〇〇〇〇〇〇〇〇〇〇〇〇〇〇", "一〇〇〇〇〇〇〇〇〇〇〇〇〇〇〇〇〇〇",
          kKanjiDescription),
        ExpectResult(
          "１００００００００００００００００００", "１００００００００００００００００００",
          kArabicDescription),
        ExpectResult(
          "1,000,000,000,000,000,000", "1,000,000,000,000,000,000", kArabicDescription),
        ExpectResult(
          "１，０００，０００，０００，０００，０００，０００",
          "１，０００，０００，０００，０００，０００，０００",
          kArabicDescription),
        ExpectResult("100京", "100京", kArabicDescription),
        ExpectResult("１００京", "１００京", kArabicDescription),
        ExpectResult("百京", "百京", kKanjiDescription),
        ExpectResult("壱百京", "壱百京", kOldKanjiDescription),
        ExpectResult("0xde0b6b3a7640000", "0xde0b6b3a7640000", "16進数"),
        ExpectResult("067405553164731000000", "067405553164731000000", "8進数"),
        ExpectResult(
          "0b110111100000101101101011001110100111011001000000000000000000",
          "0b110111100000101101101011001110100111011001000000000000000000",
          "2進数"),
      ])

    seg.clearCandidates()
  }

  @Test func numberIsGreaterThanUInt64Max() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()

    let segments = Segments()
    let seg = segments.pushBackSegment()
    let candidate = seg.addCandidate()
    candidate.lid = f.posMatcher.getNumberId()
    candidate.rid = f.posMatcher.getNumberId()
    candidate.value = "18446744073709551616"  // 2^64
    candidate.contentValue = "18446744073709551616"
    candidate.key = "18446744073709551616"
    candidate.contentKey = "18446744073709551616"

    #expect(numberRewriter.rewrite(f.defaultRequest, segments))

    expectResults(
      seg,
      [
        ExpectResult("18446744073709551616", "18446744073709551616", ""),
        ExpectResult(
          "一八四四六七四四〇七三七〇九五五一六一六", "一八四四六七四四〇七三七〇九五五一六一六",
          kKanjiDescription),
        ExpectResult(
          "１８４４６７４４０７３７０９５５１６１６", "１８４４６７４４０７３７０９５５１６１６",
          kArabicDescription),
        ExpectResult(
          "18,446,744,073,709,551,616", "18,446,744,073,709,551,616", kArabicDescription),
        ExpectResult(
          "１８，４４６，７４４，０７３，７０９，５５１，６１６",
          "１８，４４６，７４４，０７３，７０９，５５１，６１６",
          kArabicDescription),
        ExpectResult(
          "1844京6744兆737億955万1616", "1844京6744兆737億955万1616", kArabicDescription),
        ExpectResult(
          "１８４４京６７４４兆７３７億９５５万１６１６",
          "１８４４京６７４４兆７３７億９５５万１６１６", kArabicDescription),
        ExpectResult(
          "千八百四十四京六千七百四十四兆七百三十七億九百五十五万千六百十六",
          "千八百四十四京六千七百四十四兆七百三十七億九百五十五万千六百十六",
          kKanjiDescription),
        ExpectResult(
          "壱阡八百四拾四京六阡七百四拾四兆七百参拾七億九百五拾五萬壱阡六百壱拾六",
          "壱阡八百四拾四京六阡七百四拾四兆七百参拾七億九百五拾五萬壱阡六百壱拾六",
          kOldKanjiDescription),
      ])

    seg.clearCandidates()
  }

  @Test func numberIsGoogol() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()

    let segments = Segments()
    let seg = segments.pushBackSegment()
    let candidate = seg.addCandidate()
    candidate.lid = f.posMatcher.getNumberId()
    candidate.rid = f.posMatcher.getNumberId()

    // 10^100 as "100000 ... 0"
    let input = "1" + String(repeating: "0", count: 100)

    candidate.key = input
    candidate.contentKey = input
    candidate.value = input
    candidate.contentValue = input

    #expect(numberRewriter.rewrite(f.defaultRequest, segments))

    try #require(seg.candidatesSize == 6)

    #expect(seg.candidate(0).value == input)
    #expect(seg.candidate(0).contentValue == input)
    #expect(seg.candidate(0).description == "")

    // 10^100 as "一〇〇〇〇〇 ... 〇"
    let expected2 = "一" + String(repeating: "〇", count: 100)
    #expect(seg.candidate(1).value == expected2)
    #expect(seg.candidate(1).contentValue == expected2)
    #expect(seg.candidate(1).description == kKanjiDescription)

    // 10^100 as "１０００００ ... ０"
    let expected3 = "１" + String(repeating: "０", count: 100)
    #expect(seg.candidate(2).value == expected3)
    #expect(seg.candidate(2).contentValue == expected3)
    #expect(seg.candidate(2).description == kArabicDescription)

    // 10,000, ... ,000
    let expected1 = "10" + String(repeating: ",000", count: 100 / 3)
    #expect(seg.candidate(3).value == expected1)
    #expect(seg.candidate(3).contentValue == expected1)
    #expect(seg.candidate(3).description == kArabicDescription)

    // "１０，０００， ... ，０００"
    let expected4 = "１０" + String(repeating: "，０００", count: 100 / 3)
    #expect(seg.candidate(4).value == expected4)
    #expect(seg.candidate(4).contentValue == expected4)
    #expect(seg.candidate(4).description == kArabicDescription)

    #expect(seg.candidate(5).value == "Googol")
    #expect(seg.candidate(5).contentValue == "Googol")
    #expect(seg.candidate(5).description == "")

    seg.clearCandidates()
  }

  @Test func rankingForKanjiCandidate() throws {
    // If kanji candidate is higher before we rewrite segments,
    // kanji should have higher raking.
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()

    let segments = Segments()
    do {
      let segment = segments.addSegment()
      segment.setKey("さんびゃく")
      var candidate = segment.addCandidate()
      candidate = segment.addCandidate()
      candidate.lid = f.posMatcher.getNumberId()
      candidate.rid = f.posMatcher.getNumberId()
      candidate.key = "さんびゃく"
      candidate.value = "三百"
      candidate.contentValue = "三百"
    }

    #expect(numberRewriter.rewrite(f.defaultRequest, segments))
    #expect(segments.segmentsSize != 0)
    let kanjiPos = findCandidateId(segments.segment(0), "三百")
    let arabicPos = findCandidateId(segments.segment(0), "300")
    #expect(kanjiPos != nil)
    #expect(arabicPos != nil)
    #expect((kanjiPos ?? 0) < (arabicPos ?? 0))
  }

  @Test func modifyExsistingRanking() throws {
    // Modify existing ranking even if the converter returns unusual results
    // due to dictionary noise, etc.
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()

    let segments = Segments()
    do {
      let segment = segments.addSegment()
      segment.setKey("さんびゃく")
      var candidate = segment.addCandidate()
      candidate.lid = f.posMatcher.getNumberId()
      candidate.rid = f.posMatcher.getNumberId()
      candidate.key = "さんびゃく"
      candidate.value = "参百"
      candidate.contentValue = "参百"

      candidate = segment.addCandidate()
      candidate.lid = f.posMatcher.getNumberId()
      candidate.rid = f.posMatcher.getNumberId()
      candidate.key = "さんびゃく"
      candidate.value = "三百"
      candidate.contentValue = "三百"
    }

    #expect(numberRewriter.rewrite(f.defaultRequest, segments))
    #expect(segments.segmentsSize != 0)
    let kanjiPos = findCandidateId(segments.segment(0), "三百")
    let oldKanjiPos = findCandidateId(segments.segment(0), "参百")
    #expect(kanjiPos != nil)
    #expect(oldKanjiPos != nil)
    #expect((kanjiPos ?? 0) < (oldKanjiPos ?? 0))
  }

  @Test func eraseExistingCandidates() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()

    let segments = Segments()
    do {
      let segment = segments.addSegment()
      segment.setKey("いち")
      var candidate = segment.addCandidate()
      candidate.lid = f.posMatcher.getUnknownId()  // Not number POS
      candidate.rid = f.posMatcher.getUnknownId()
      candidate.key = "いち"
      candidate.contentKey = "いち"
      candidate.value = "壱"
      candidate.contentValue = "壱"

      candidate = segment.addCandidate()
      candidate.lid = f.posMatcher.getNumberId()  // Number POS
      candidate.rid = f.posMatcher.getNumberId()
      candidate.key = "いち"
      candidate.contentKey = "いち"
      candidate.value = "一"
      candidate.contentValue = "一"
    }

    #expect(numberRewriter.rewrite(f.defaultRequest, segments))

    // "一" becomes the base candidate, instead of "壱"
    let basePos = findCandidateId(segments.segment(0), "一")
    #expect(basePos == 0)

    // Daiji will be inserted with new correct POS ids.
    let daijiPos = try #require(findCandidateId(segments.segment(0), "壱"))
    #expect(daijiPos > 0)
    #expect(f.posMatcher.getNumberId() == segments.segment(0).candidate(daijiPos).lid)
    #expect(f.posMatcher.getNumberId() == segments.segment(0).candidate(daijiPos).rid)
  }

  @Test func separatedArabicsTest() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()

    // Expected data to succeed tests.
    let kSuccess: [[String]] = [
      ["1000", "1,000", "１，０００"],
      ["12345678", "12,345,678", "１２，３４５，６７８"],
      ["1234.5", "1,234.5", "１，２３４．５"],
    ]

    for success in kSuccess {
      let segments = Segments()
      let seg = segments.pushBackSegment()
      let candidate = seg.addCandidate()
      candidate.lid = f.posMatcher.getNumberId()
      candidate.rid = f.posMatcher.getNumberId()
      candidate.key = success[0]
      candidate.contentKey = success[0]
      candidate.value = success[0]
      candidate.contentValue = success[0]

      #expect(numberRewriter.rewrite(f.defaultRequest, segments))
      #expect(findValue(segments.segment(0), success[1]), "Input : \(success[0])")
      #expect(findValue(segments.segment(0), success[2]), "Input : \(success[0])")
    }

    // Expected data to fail tests.
    let kFail: [[String]] = [
      ["123", ",123", "，１２３"],
      ["999", ",999", "，９９９"],
      ["0000", "0,000", "０，０００"],
    ]

    for fail in kFail {
      let segments = Segments()
      let seg = segments.pushBackSegment()
      let candidate = seg.addCandidate()
      candidate.lid = f.posMatcher.getNumberId()
      candidate.rid = f.posMatcher.getNumberId()
      candidate.key = fail[0]
      candidate.contentKey = fail[0]
      candidate.value = fail[0]
      candidate.contentValue = fail[0]

      #expect(numberRewriter.rewrite(f.defaultRequest, segments))
      #expect(!findValue(segments.segment(0), fail[1]), "Input : \(fail[0])")
      #expect(!findValue(segments.segment(0), fail[2]), "Input : \(fail[0])")
    }
  }

  // Consider the case where user dictionaries contain following entry.
  // - Reading: "はやぶさ"
  // - Value: "8823"
  // - POS: GeneralNoun (not *Number*)
  // In this case, NumberRewriter should not clear
  // converter::Attribute::USER_DICTIONARY bit in the base candidate.
  @Test func preserveUserDictionaryAttribute() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()
    do {
      let segments = Segments()
      do {
        let seg = segments.pushBackSegment()
        let candidate = seg.addCandidate()
        candidate.lid = f.posMatcher.getGeneralNounId()
        candidate.rid = f.posMatcher.getGeneralNounId()
        candidate.key = "はやぶさ"
        candidate.contentKey = candidate.key
        candidate.value = "8823"
        candidate.contentValue = candidate.value
        candidate.cost = 5925
        candidate.wcost = 5000
        candidate.attributes = Attribute.userDictionary | Attribute.noVariantsExpansion
      }

      #expect(numberRewriter.rewrite(f.defaultRequest, segments))
      var baseCandidateFound = false
      do {
        let segment = segments.segment(0)
        for i in 0..<segment.candidatesSize {
          let candidate = segment.candidate(i)
          if candidate.value == "8823" && (candidate.attributes & Attribute.userDictionary) != 0 {
            baseCandidateFound = true
            break
          }
        }
      }
      #expect(baseCandidateFound)
    }
  }

  @Test func duplicateCandidateTest() throws {
    // To reproduce issue b/6714268.
    let f = try NumberRewriterTestFixture()
    var request = Genmai_Commands_Request()
    let rewriter = f.createNumberRewriter()

    do {
      request.mixedConversion = true
      let convreq = ConversionRequestBuilder().setRequest(request).build()
      #expect(rewriter.capability(convreq) == .all)
    }

    do {
      request.mixedConversion = false
      let convreq = ConversionRequestBuilder().setRequest(request).build()
      #expect(rewriter.capability(convreq) == .conversion)
    }
  }

  @Test func nonNumberNounTest() throws {
    // Test if "百舌鳥" is not rewritten to "100舌鳥", etc.
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()
    let segments = Segments()
    let segment = segments.pushBackSegment()
    segment.setKey("")
    let cand = segment.addCandidate()
    cand.key = "もず"
    cand.contentKey = cand.key
    cand.value = "百舌鳥"
    cand.contentValue = cand.value
    cand.lid = f.posMatcher.getGeneralNounId()
    cand.rid = f.posMatcher.getGeneralNounId()
    #expect(!numberRewriter.rewrite(f.defaultRequest, segments))
  }

  @Test func rewriteArabicNumberTest() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()
    let segments = Segments()
    let segment = segments.pushBackSegment()
    segment.setKey("いち")
    let kCandList: [(String, UInt16)] = [
      ("1", f.posMatcher.getNumberId()),
      ("一", f.posMatcher.getNumberId()),
      ("位置", f.posMatcher.getGeneralNounId()),
      ("イチ", f.posMatcher.getGeneralNounId()),
      ("壱", f.posMatcher.getGeneralNounId()),
    ]

    for (value, posId) in kCandList {
      let cand = segment.addCandidate()
      cand.key = "いち"
      cand.contentKey = cand.key
      cand.value = value
      cand.contentValue = cand.value
      cand.lid = posId
      cand.rid = posId
    }
    #expect(numberRewriter.rewrite(f.defaultRequest, segments))
    try #require(segment.candidatesSize > 1)
    #expect(segment.candidate(0).value == "一")
    #expect(segment.candidate(1).value == "位置")
  }

  @Test func rewriteForPartialSuggestion_b16765535() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()

    let segments = Segments()
    do {
      let seg = segments.pushBackSegment()
      let candidate = seg.addCandidate()
      candidate.lid = f.posMatcher.getNumberId()
      candidate.rid = f.posMatcher.getNumberId()
      candidate.key = "090"
      candidate.value = "090"
      candidate.contentKey = "090"
      candidate.contentValue = "090"
      candidate.attributes = Attribute.partiallyKeyConsumed | Attribute.noSuggestLearning
      candidate.consumedKeySize = 3
    }
    do {
      let seg = segments.pushBackSegment()
      let candidate = seg.addCandidate()
      candidate.key = "-"
      candidate.value = "-"
      candidate.contentKey = "-"
      candidate.contentValue = "-"
    }
    #expect(numberRewriter.rewrite(f.defaultRequest, segments))

    try #require(segments.conversionSegmentsSize == 2)
    let seg = segments.conversionSegment(0)
    try #require(2 <= seg.candidatesSize)
    for i in 0..<seg.candidatesSize {
      let candidate = seg.candidate(i)
      #expect(candidate.attributes & Attribute.partiallyKeyConsumed != 0)
      #expect(candidate.attributes & Attribute.noSuggestLearning != 0)
    }
  }

  @Test func rewriteForPartialSuggestion_b19470020() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()

    let segments = Segments()
    do {
      let seg = segments.pushBackSegment()
      seg.setKey("ひとりひとぱっく")
      let candidate = seg.addCandidate()
      candidate.lid = f.posMatcher.getNumberId()
      candidate.rid = f.posMatcher.getNumberId()
      candidate.key = "ひとり"
      candidate.value = "一人"
      candidate.contentKey = "ひとり"
      candidate.contentValue = "一人"
      candidate.attributes = Attribute.partiallyKeyConsumed
      candidate.consumedKeySize = 3
    }
    #expect(numberRewriter.rewrite(f.defaultRequest, segments))

    try #require(segments.conversionSegmentsSize == 1)
    let seg = segments.conversionSegment(0)
    try #require(2 <= seg.candidatesSize)
    var foundHalfwidth = false
    for i in 0..<seg.candidatesSize {
      let candidate = seg.candidate(i)
      if candidate.value != "1人" {
        continue
      }
      foundHalfwidth = true
      #expect(candidate.consumedKeySize == 3)
      #expect(candidate.attributes & Attribute.partiallyKeyConsumed != 0)
    }
    #expect(foundHalfwidth)
  }

  @Test func rewritePhonePrefix_b16668386() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()

    let segments = Segments()
    let seg = segments.pushBackSegment()
    let candidate = seg.addCandidate()
    candidate.lid = f.posMatcher.getNumberId()
    candidate.rid = f.posMatcher.getGeneralSymbolId()
    candidate.key = "090-"
    candidate.value = "090-"
    candidate.contentKey = "090-"
    candidate.contentValue = "090-"

    #expect(!numberRewriter.rewrite(f.defaultRequest, segments))
  }

  @Test func rewriteFromPhoneticNumber() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()

    let segments = Segments()
    do {
      let seg = segments.pushBackSegment()
      seg.setKey("じゅうまん")
      let candidate = seg.addCandidate()
      candidate.lid = f.posMatcher.getNumberId()
      candidate.rid = f.posMatcher.getNumberId()
      candidate.key = "じゅうまん"
      candidate.contentKey = "じゅうまん"
      candidate.value = "10万"
      candidate.contentValue = "10万"
    }
    #expect(numberRewriter.rewrite(f.defaultRequest, segments))

    try #require(segments.conversionSegmentsSize == 1)
    #expect(containsCandidate(segments.conversionSegment(0), valueIs("100000")))
  }

  @Test func doNotGenerateLongCandidatesForPhoneticNumber() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()

    let segments = Segments()
    do {
      let seg = segments.pushBackSegment()
      seg.setKey("ひゃくまん")
      let candidate = seg.addCandidate()
      candidate.lid = f.posMatcher.getNumberId()
      candidate.rid = f.posMatcher.getNumberId()
      candidate.key = "ひゃくまん"
      candidate.contentKey = "ひゃくまん"
      candidate.value = "100万"
      candidate.contentValue = "100万"
    }
    #expect(!numberRewriter.rewrite(f.defaultRequest, segments))
  }

  @Test func numberStyleLearningNotEnabledInIncognito() throws {
    let f = try NumberRewriterTestFixture()
    let rewriter = f.createNumberRewriter()
    var request = Genmai_Commands_Request()
    request.isIncognitoMode = true
    let convreq = ConversionRequestBuilder().setRequest(request).build()
    try learnNumberStyle(convreq, f.posMatcher, rewriter)

    do {
      let newSegments = prepareNumberSegments("2000", "2000", 3, f.posMatcher)
      _ = rewriter.rewrite(convreq, newSegments)
      try #require(newSegments.conversionSegmentsSize == 1)
      try #require(newSegments.conversionSegment(0).candidatesSize > 3)
      // Learned style should not be applied in incognito mode.
      #expect(newSegments.conversionSegment(0).candidate(3).value != "2,000")
    }
  }

  // NumberStyleLearningTestForRequest/NumberStyleLearningTest.NumberRewriterTest
  @Test(arguments: [0, 1, 2])
  func numberStyleLearningTest(_ param: Int) throws {
    var request = Genmai_Commands_Request()
    switch param {
    case 1: RequestTestUtil.fillMobileRequest(&request)
    case 2: RequestTestUtil.fillMobileRequestWithHardwareKeyboard(&request)
    default: break
    }
    let f = try NumberRewriterTestFixture()
    let rewriter = f.createNumberRewriter()
    let convreq = ConversionRequestBuilder().setRequest(request).build()

    try learnNumberStyle(convreq, f.posMatcher, rewriter)

    do {
      let newSegments = prepareNumberSegments("2000", "2000", 3, f.posMatcher)
      _ = rewriter.rewrite(convreq, newSegments)
      try #require(newSegments.conversionSegmentsSize == 1)
      let seg = newSegments.conversionSegment(0)
      try #require(seg.candidatesSize > 6)
      // Learned style should be applied.
      try #require(seg.candidate(3).style == .numberSeparatedArabicHalfwidth)
      try #require(seg.candidate(3).value == "2,000")
      try #require(seg.candidate(3).attributes & Attribute.noVariantsExpansion != 0)

      try #require(seg.candidate(4).style == .defaultStyle)
      try #require(seg.candidate(4).value == "2000")
      try #require(seg.candidate(5).style == .numberKanjiArabic)
      try #require(seg.candidate(5).value == "二〇〇〇")
      try #require(seg.candidate(6).style == .defaultStyle)
      try #require(seg.candidate(6).value == "２０００")
      try #require(seg.candidate(7).style == .numberSeparatedArabicFullwidth)
      try #require(seg.candidate(7).value == "２，０００")
    }

    do {
      // Should not apply the learned number style for the multiple segments.
      let newSegments = prepareNumberSegments("2000", "2000", 3, f.posMatcher)
      let seg = newSegments.addSegment()
      seg.setKey("かい")
      let c = seg.addCandidate()
      c.key = "かい"
      c.contentKey = c.key
      c.value = "回"
      c.contentValue = c.value
      _ = rewriter.rewrite(convreq, newSegments)
      try #require(newSegments.conversionSegmentsSize == 2)
      try #require(newSegments.conversionSegment(0).candidatesSize > 3)
      #expect(newSegments.conversionSegment(0).candidate(3).value != "2,000")
    }
  }

  @Test func noModification() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()
    let segments = Segments()
    let seg = segments.pushBackSegment()
    for i in 0..<3 {
      let candidate = seg.addCandidate()
      candidate.lid = f.posMatcher.getGeneralNounId()
      candidate.rid = f.posMatcher.getGeneralNounId()
      candidate.key = "さん"
      candidate.contentKey = candidate.key
      candidate.value = "3"
      candidate.contentValue = candidate.value
      candidate.cost = 5925
      candidate.wcost = 5000
      if i == 0 {
        candidate.attributes = Attribute.noModification
      }
    }

    #expect(seg.candidatesSize == 3)
    #expect(numberRewriter.rewrite(f.defaultRequest, segments))
    #expect(seg.candidate(0).value == "3")
    #expect(seg.candidatesSize > 3)
  }

  @Test func rewriteMultipleTimes() throws {
    let f = try NumberRewriterTestFixture()
    let numberRewriter = f.createNumberRewriter()
    let segments = Segments()
    let seg = segments.pushBackSegment()
    seg.setKey("１２")

    let candidate = seg.addCandidate()
    candidate.lid = f.posMatcher.getGeneralNounId()
    candidate.rid = f.posMatcher.getGeneralNounId()
    candidate.key = "１２"
    candidate.contentKey = candidate.key
    candidate.value = "１２"
    candidate.contentValue = candidate.value
    candidate.cost = 5925
    candidate.wcost = 5000

    let expected = [
      "12", "一二", "１２", "十二", "壱拾弐", "Ⅻ", "ⅻ", "⑫", "0xc", "014", "0b1100",
    ]
    #expect(numberRewriter.rewrite(f.defaultRequest, segments))
    #expect(seg.candidates.map(\.value) == expected)

    // Rewriting multiple times should not change the result.
    #expect(!numberRewriter.rewrite(f.defaultRequest, segments))
    #expect(seg.candidates.map(\.value) == expected)
  }

  @Test func numberStyleLearningExplicitHalfWidth() throws {
    let f = try NumberRewriterTestFixture()
    let rewriter = f.createNumberRewriter()
    CharacterFormManager.getCharacterFormManager().clearHistory()

    var config = Genmai_Config_Config()
    var rule = Genmai_Config_Config.CharacterFormRule()
    rule.group = "0"
    rule.conversionCharacterForm = .halfWidth
    config.characterFormRules.append(rule)
    let request = ConversionRequestBuilder().setConfig(config).build()

    // Commit full-width separated candidate: "１，２３４"
    let segments = Segments()
    let seg = segments.pushBackSegment()
    seg.setKey("1234")
    let candidate = seg.addCandidate()
    candidate.value = "１，２３４"
    candidate.contentValue = "１，２３４"
    candidate.contentKey = "1234"
    candidate.lid = f.posMatcher.getNumberId()
    candidate.rid = f.posMatcher.getNumberId()
    candidate.style = .numberSeparatedArabicFullwidth
    seg.setSegmentType(.fixedValue)
    rewriter.finish(request, segments)

    // Next time 1234 is converted, half-width separated "1,234" is reranked to
    // top due to explicit HALF_WIDTH rule.
    let newSegments = prepareNumberSegments("1234", "1234", 0, f.posMatcher)
    #expect(rewriter.rewrite(request, newSegments))
    #expect(newSegments.conversionSegment(0).candidate(0).value == "1,234")

    // Commit full-width Arabic+Kanji candidate: "１万"
    seg.setKey("10000")
    candidate.value = "１万"
    candidate.contentValue = "１万"
    candidate.contentKey = "10000"
    candidate.style = .numberArabicAndKanjiFullwidth
    rewriter.finish(request, segments)

    // Next time 10000 is converted, half-width Arabic+Kanji "1万" is reranked
    // to top due to explicit HALF_WIDTH rule. Short number 123 falls back to
    // "123".
    let kanjiSegments = prepareNumberSegments("10000", "10000", 0, f.posMatcher)
    #expect(rewriter.rewrite(request, kanjiSegments))
    #expect(kanjiSegments.conversionSegment(0).candidate(0).value == "1万")

    let shortSegments = prepareNumberSegments("123", "123", 0, f.posMatcher)
    #expect(rewriter.rewrite(request, shortSegments))
    #expect(shortSegments.conversionSegment(0).candidate(0).value == "123")
  }

  @Test func numberStyleLearningExplicitFullWidth() throws {
    let f = try NumberRewriterTestFixture()
    let rewriter = f.createNumberRewriter()
    CharacterFormManager.getCharacterFormManager().clearHistory()

    var config = Genmai_Config_Config()
    var rule = Genmai_Config_Config.CharacterFormRule()
    rule.group = "0"
    rule.conversionCharacterForm = .fullWidth
    config.characterFormRules.append(rule)
    let request = ConversionRequestBuilder().setConfig(config).build()

    // Commit half-width separated candidate: "1,234"
    let segments = Segments()
    let seg = segments.pushBackSegment()
    seg.setKey("1234")
    let candidate = seg.addCandidate()
    candidate.value = "1,234"
    candidate.contentValue = "1,234"
    candidate.contentKey = "1234"
    candidate.lid = f.posMatcher.getNumberId()
    candidate.rid = f.posMatcher.getNumberId()
    candidate.style = .numberSeparatedArabicHalfwidth
    seg.setSegmentType(.fixedValue)
    rewriter.finish(request, segments)

    // Next time 1234 is converted, full-width separated "１，２３４" is
    // reranked to top due to explicit FULL_WIDTH rule.
    let newSegments = prepareNumberSegments("1234", "1234", 0, f.posMatcher)
    #expect(rewriter.rewrite(request, newSegments))
    #expect(newSegments.conversionSegment(0).candidate(0).value == "１，２３４")

    // Commit half-width Arabic+Kanji candidate: "1万"
    seg.setKey("10000")
    candidate.value = "1万"
    candidate.contentValue = "1万"
    candidate.contentKey = "10000"
    candidate.style = .numberArabicAndKanjiHalfwidth
    rewriter.finish(request, segments)

    // Next time 10000 is converted, full-width Arabic+Kanji "１万" is reranked
    // to top due to explicit FULL_WIDTH rule. Short number 123 falls back to
    // "１２３".
    let kanjiSegments = prepareNumberSegments("10000", "10000", 0, f.posMatcher)
    #expect(rewriter.rewrite(request, kanjiSegments))
    #expect(kanjiSegments.conversionSegment(0).candidate(0).value == "１万")

    let shortSegments = prepareNumberSegments("123", "123", 0, f.posMatcher)
    #expect(rewriter.rewrite(request, shortSegments))
    #expect(shortSegments.conversionSegment(0).candidate(0).value == "１２３")
  }

  @Test func rewriteTopCandidateForSuggestion() throws {
    let f = try NumberRewriterTestFixture()
    let rewriter = f.createNumberRewriter()
    var protoRequest = Genmai_Commands_Request()
    protoRequest.decoderExperimentParams.suppressRealtimeConversionWithConverter = true
    let request = ConversionRequestBuilder()
      .setRequest(protoRequest)
      .setRequestType(.suggestion)
      .build()

    let segments = Segments()
    let seg = segments.pushBackSegment()
    seg.setKey("かいしからにしゅうかん")

    let cand = seg.addCandidate()
    cand.key = "かいしからにしゅうかん"
    cand.value = "開始から2週間"
    cand.contentKey = "かいしからにしゅうかん"
    cand.contentValue = "開始から2週間"
    cand.lid = f.posMatcher.getGeneralNounId()
    cand.rid = f.posMatcher.getGeneralNounId()
    cand.attributes |= Attribute.realtimeConversion
    var builder = InnerSegmentBoundaryBuilder()
    builder.add(
      "かいしから".utf8.count, "開始から".utf8.count, "かいし".utf8.count, "開始".utf8.count)
    builder.add(
      "にしゅうかん".utf8.count, "2週間".utf8.count, "にしゅうかん".utf8.count, "2週間".utf8.count)
    cand.innerSegmentBoundary = builder.build(cand.key, cand.value)

    #expect(rewriter.rewrite(request, segments))
    try #require(seg.candidatesSize >= 2)
    #expect(seg.candidate(0).value == "開始から二週間")
    #expect(seg.candidate(1).value == "開始から2週間")

    // Rewriting multiple times should be idempotent.
    #expect(!rewriter.rewrite(request, segments))
    #expect(seg.candidate(0).value == "開始から二週間")
  }

  @Test func numberSuffixNoDuplicateWhenArabicAlreadyExists() throws {
    let f = try NumberRewriterTestFixture()
    let rewriter = f.createNumberRewriter()
    var req = Genmai_Commands_Request()
    req.decoderExperimentParams.suppressRealtimeConversionWithConverter = true
    let request = ConversionRequestBuilder()
      .setRequest(req)
      .setRequestType(.suggestion)
      .build()

    let segments = Segments()
    let seg = segments.pushBackSegment()
    seg.setKey("100えんのにほんしゅ")

    let cand = seg.addCandidate()
    cand.key = "100えんのにほんしゅ"
    cand.value = "100円の日本酒"
    cand.contentKey = "100えん"
    cand.contentValue = "100円"
    cand.lid = f.posMatcher.getGeneralNounId()
    cand.rid = f.posMatcher.getGeneralNounId()
    cand.attributes |= Attribute.realtimeConversion
    var builder = InnerSegmentBoundaryBuilder()
    builder.add(
      "100えんの".utf8.count, "100円の".utf8.count, "100えん".utf8.count, "100円".utf8.count)
    builder.add(
      "にほんしゅ".utf8.count, "日本酒".utf8.count, "にほんしゅ".utf8.count, "日本酒".utf8.count)
    cand.innerSegmentBoundary = builder.build(cand.key, cand.value)

    // RewriteTopCandidateForSuggestion does not rewrite when key starts with
    // ASCII digits ("100"), and RewriteOneSegment should not duplicate
    // "100円の日本酒".
    #expect(!rewriter.rewrite(request, segments))
    #expect(seg.candidatesSize == 1)
    #expect(seg.candidate(0).value == "100円の日本酒")
  }

  @Test func updateCandidateClearsStaleInnerSegmentBoundary() throws {
    let f = try NumberRewriterTestFixture()
    let rewriter = f.createNumberRewriter()
    var req = Genmai_Commands_Request()
    req.decoderExperimentParams.suppressRealtimeConversionWithConverter = true
    let request = ConversionRequestBuilder()
      .setRequest(req)
      .setRequestType(.suggestion)
      .build()

    let segments = Segments()
    let seg = segments.pushBackSegment()
    seg.setKey("にから")

    let cand = seg.addCandidate()
    cand.key = "にから"
    cand.value = "2から"
    cand.contentKey = "に"
    cand.contentValue = "2"
    cand.lid = f.posMatcher.getNumberId()
    cand.rid = f.posMatcher.getGeneralNounId()
    cand.attributes |= Attribute.realtimeConversion
    var builder = InnerSegmentBoundaryBuilder()
    builder.add("にから".utf8.count, "2から".utf8.count, "に".utf8.count, "2".utf8.count)
    cand.innerSegmentBoundary = builder.build(cand.key, cand.value)

    #expect(rewriter.rewrite(request, segments))
    try #require(seg.candidatesSize >= 3)
    #expect(seg.candidate(0).value == "二から")
    #expect(seg.candidate(0).innerSegmentBoundary.isEmpty)
    #expect(seg.candidate(1).value == "弐から")
    #expect(seg.candidate(2).value == "2から")
  }

  @Test func rememberNumberStyleForCompoundAndKanjiNumbers() throws {
    let f = try NumberRewriterTestFixture()
    let rewriter = f.createNumberRewriter()
    let manager = CharacterFormManager.getCharacterFormManager()
    manager.clearHistory()

    let segments = Segments()
    let seg = segments.pushBackSegment()
    seg.setKey("123から")
    seg.setSegmentType(.fixedValue)

    let cand = seg.addCandidate()
    cand.key = "123から"
    cand.contentKey = "123"
    cand.value = "123から"
    cand.contentValue = "123"
    cand.lid = f.posMatcher.getNumberId()
    cand.rid = f.posMatcher.getNumberId()
    cand.style = .defaultStyle

    func expectStored(
      _ form: Genmai_Config_Config.CharacterForm, _ style: NumberUtil.NumberString.Style,
      sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
      let stored = try #require(manager.getLastNumberStyle(), sourceLocation: sourceLocation)
      #expect(stored.form == form, sourceLocation: sourceLocation)
      #expect(stored.style == style, sourceLocation: sourceLocation)
    }

    rewriter.finish(f.defaultRequest, segments)
    try expectStored(.halfWidth, .defaultStyle)

    // Number + counter where content_value includes the counter ("2日") has
    // mixed character form and non-number script type; it should not
    // overwrite LastNumberStyle with FULL_WIDTH.
    cand.key = "2か"
    cand.contentKey = "2か"
    cand.value = "2日"
    cand.contentValue = "2日"
    rewriter.finish(f.defaultRequest, segments)
    try expectStored(.halfWidth, .defaultStyle)

    // Unstyled Kanji number ("二") with DEFAULT_STYLE should not overwrite
    // LastNumberStyle with {FULL_WIDTH, DEFAULT_STYLE}.
    cand.key = "に"
    cand.contentKey = "に"
    cand.value = "二"
    cand.contentValue = "二"
    rewriter.finish(f.defaultRequest, segments)
    try expectStored(.halfWidth, .defaultStyle)

    // Phonetic Kanji number ("に" -> "二") with NUMBER_KANJI style (set by
    // SetNumberInfoToExistingCandidates during Rewrite) should not overwrite
    // LastNumberStyle either.
    cand.key = "に"
    cand.contentKey = "に"
    cand.value = "二"
    cand.contentValue = "二"
    cand.style = .numberKanji
    rewriter.finish(f.defaultRequest, segments)
    try expectStored(.halfWidth, .defaultStyle)

    // Digit key converted to NUMBER_ARABIC_AND_KANJI_HALFWIDTH ("10000" ->
    // "1万") has mixed character form (UNKNOWN_FORM), but should still be
    // recorded with HALF_WIDTH form.
    cand.key = "10000"
    cand.contentKey = "10000"
    cand.value = "1万"
    cand.contentValue = "1万"
    cand.style = .numberArabicAndKanjiHalfwidth
    rewriter.finish(f.defaultRequest, segments)
    try expectStored(.halfWidth, .numberArabicAndKanjiHalfwidth)

    // When LastNumberStyle is {FULL_WIDTH, DEFAULT_STYLE}, rewriting a number
    // candidate with a functional suffix ("123から") should rerank
    // "１２３から" to the top based on content_value.
    manager.setLastNumberStyle(
      CharacterFormManager.NumberFormStyle(form: .fullWidth, style: .defaultStyle))
    let suffixSegments = Segments()
    let suffixSeg = suffixSegments.pushBackSegment()
    suffixSeg.setKey("123から")
    let suffixCand = suffixSeg.addCandidate()
    suffixCand.key = "123から"
    suffixCand.contentKey = "123"
    suffixCand.value = "123から"
    suffixCand.contentValue = "123"
    suffixCand.lid = f.posMatcher.getNumberId()
    suffixCand.rid = f.posMatcher.getNumberId()
    #expect(rewriter.rewrite(f.defaultRequest, suffixSegments))
    #expect(suffixSeg.candidate(0).value == "１２３から")
  }

  @Test func rerankShortNumbersAfterSeparatedOrArabicKanjiStyle() throws {
    let f = try NumberRewriterTestFixture()
    let rewriter = f.createNumberRewriter()
    let manager = CharacterFormManager.getCharacterFormManager()
    manager.clearHistory()

    func commit(
      _ key: String, _ value: String, _ style: NumberUtil.NumberString.Style
    ) {
      let segments = Segments()
      let seg = segments.pushBackSegment()
      seg.setKey(key)
      seg.setSegmentType(.fixedValue)
      let cand = seg.addCandidate()
      cand.key = key
      cand.contentKey = key
      cand.value = value
      cand.contentValue = value
      cand.lid = f.posMatcher.getNumberId()
      cand.rid = f.posMatcher.getNumberId()
      cand.style = style
      rewriter.finish(f.defaultRequest, segments)
    }

    func rewriteTop(_ number: String) -> Candidate {
      let segments = prepareNumberSegments(number, number, 0, f.posMatcher)
      #expect(rewriter.rewrite(f.defaultRequest, segments))
      return segments.conversionSegment(0).candidate(0)
    }

    // Commit "１，２３４" (NUMBER_SEPARATED_ARABIC_FULLWIDTH).
    commit("1234", "１，２３４", .numberSeparatedArabicFullwidth)
    // Next 3-digit number ("123") has no comma-separated candidate; it should
    // fall back to full-width DEFAULT_STYLE ("１２３").
    #expect(rewriteTop("123").value == "１２３")

    // Commit "1,234" (NUMBER_SEPARATED_ARABIC_HALFWIDTH).
    commit("1234", "1,234", .numberSeparatedArabicHalfwidth)
    // Next 3-digit number ("123") should fall back to half-width DEFAULT_STYLE
    // ("123").
    #expect(rewriteTop("123").value == "123")

    // Commit "１万" (NUMBER_ARABIC_AND_KANJI_FULLWIDTH).
    commit("10000", "１万", .numberArabicAndKanjiFullwidth)
    // Next 3-digit number ("123") should fall back to full-width DEFAULT_STYLE
    // ("１２３").
    #expect(rewriteTop("123").value == "１２３")

    // Commit "1万" (NUMBER_ARABIC_AND_KANJI_HALFWIDTH).
    commit("10000", "1万", .numberArabicAndKanjiHalfwidth)
    // Next 3-digit number ("123") should fall back to half-width DEFAULT_STYLE
    // ("123").
    #expect(rewriteTop("123").value == "123")

    // Commit "①" (NUMBER_CIRCLED).
    commit("1", "①", .numberCircled)
    // Next 3-digit number ("100") has no circled candidate; RerankCandidates
    // should not attach NO_VARIANTS_EXPANSION to the top candidate so
    // VariantsRewriter can normalize its character form.
    #expect(rewriteTop("100").attributes & Attribute.noVariantsExpansion == 0)
  }
}
