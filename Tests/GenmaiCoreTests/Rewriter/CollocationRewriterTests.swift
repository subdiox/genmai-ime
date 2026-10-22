// Port of mozc/src/rewriter/collocation_rewriter_test.cc (3.35.6354).

import Testing

@testable import GenmaiCore

// TODO(team): Introduce dependency injection for checking collocation entries
// instead of using actual bloom filter, which have false positives.
@Suite(.enabled(if: ConverterCoreTestSupport.hasMockData, ConverterCoreTestSupport.mockDataMissing))
struct CollocationRewriterTests {
  // Helper data structures to define test cases.
  // Used to generate converter::Candidate.
  fileprivate struct CandidateData {
    let key: String
    let contentKey: String
    let value: String
    let contentValue: String
    let cost: Int32
    let lid: UInt16
    let rid: UInt16

    init(
      _ key: String, _ contentKey: String, _ value: String, _ contentValue: String, _ cost: Int32,
      _ lid: UInt16, _ rid: UInt16
    ) {
      self.key = key
      self.contentKey = contentKey
      self.value = value
      self.contentValue = contentValue
      self.cost = cost
      self.lid = lid
      self.rid = rid
    }
  }

  // Used to generate Segment.
  fileprivate struct SegmentData {
    let key: String
    let candidates: [CandidateData]
    init(_ key: String, _ candidates: [CandidateData]) {
      self.key = key
      self.candidates = candidates
    }
  }

  private let posMatcher: PosMatcher
  private let collocationRewriter: CollocationRewriter

  init() throws {
    let dataManager = try ConverterCoreTestSupport.mockDataManager()
    posMatcher = PosMatcher(dataManager.getPosMatcherData())
    collocationRewriter = try #require(
      CollocationRewriter.create(posMatcher, dataManager.getCollocationData()))
  }

  // Makes a segment from SegmentData.
  private static func makeSegment(_ data: SegmentData, _ segment: Segment) {
    segment.setKey(data.key)
    for candData in data.candidates {
      let cand = segment.addCandidate()
      cand.key = candData.key
      cand.contentKey = candData.contentKey
      cand.value = candData.value
      cand.contentValue = candData.contentValue
      cand.cost = candData.cost
      cand.lid = candData.lid
      cand.rid = candData.rid
    }
  }

  // Makes a segments from SegmentsData.
  private static func makeSegments(_ data: [SegmentData], _ segments: Segments) {
    segments.clear()
    for segData in data {
      makeSegment(segData, segments.addSegment())
    }
  }

  private func rewrite(_ segments: Segments) -> Bool {
    let request = ConversionRequest()
    return collocationRewriter.rewrite(request, segments)
  }

  // Returns the concatenated string of top candidates.
  private static func getTopValue(_ segments: Segments) -> String {
    var result = ""
    for segment in segments.conversionSegments {
      result += segment.candidate(0).value
    }
    return result
  }

  private func kaitaiCands(feedCost: Int32 = 0) -> [CandidateData] {
    let id = posMatcher.getUnknownId()
    let kKaitaiHiragana = "かいたい"
    return [
      CandidateData(kKaitaiHiragana, kKaitaiHiragana, "買いたい", "買いたい", 0, id, id),
      CandidateData(kKaitaiHiragana, kKaitaiHiragana, "解体", "解体", 0, id, id),
      CandidateData(kKaitaiHiragana, kKaitaiHiragana, "飼いたい", "飼いたい", feedCost, id, id),
    ]
  }

  private func nekowoCands() -> [CandidateData] {
    let id = posMatcher.getUnknownId()
    return [
      CandidateData("ねこを", "ねこ", "ネコを", "ネコを", 0, id, id),
      CandidateData("ねこを", "ねこ", "猫を", "猫を", 0, id, id),
    ]
  }

  @Test func nekowoKaitai() {
    // Make the following Segments:
    // "ねこを" | "かいたい"
    // --------------------
    // "ネコを" | "買いたい"
    // "猫を"   | "解体"
    //         | "飼いたい"
    let segments = Segments()
    Self.makeSegments(
      [SegmentData("ねこを", nekowoCands()), SegmentData("かいたい", kaitaiCands())], segments)

    // "猫を飼いたい" should be promoted.
    #expect(rewrite(segments))
    #expect(Self.getTopValue(segments) == "猫を飼いたい", "\(segments.debugString())")
  }

  @Test func magurowoKaitai() {
    // Make the following Segments:
    // "まぐろを" | "かいたい"
    // --------------------
    // "マグロを" | "買いたい"
    // "鮪を"    | "解体"
    //          | "飼いたい"
    let id = posMatcher.getUnknownId()
    let kMagurowoCands = [
      CandidateData("まぐろを", "まぐろ", "マグロを", "マグロ", 0, id, id),
      CandidateData("まぐろを", "まぐろ", "鮪を", "鮪", 0, id, id),
    ]
    let segments = Segments()
    Self.makeSegments(
      [SegmentData("まぐろを", kMagurowoCands), SegmentData("かいたい", kaitaiCands())], segments)

    // "マグロを解体" should be promoted.
    #expect(rewrite(segments))
    #expect(Self.getTopValue(segments) == "マグロを解体", "\(segments.debugString())")
  }

  @Test func crossOverAdverbSegment() {
    // "ねこを"    | "ネコを" "猫を"
    // "すごく"    | "すごく"
    // "かいたい"  | "買いたい" "解体" "飼いたい"
    let kSugoku = "すごく"
    let adverbId = posMatcher.getAdverbId()
    let kSugokuCands = [CandidateData(kSugoku, kSugoku, kSugoku, kSugoku, 0, adverbId, adverbId)]
    let segments = Segments()
    Self.makeSegments(
      [
        SegmentData("ねこを", nekowoCands()), SegmentData(kSugoku, kSugokuCands),
        SegmentData("かいたい", kaitaiCands()),
      ], segments)

    // "猫を飼いたい" should be promoted.
    #expect(rewrite(segments))
    #expect(Self.getTopValue(segments) == "猫をすごく飼いたい", "\(segments.debugString())")
  }

  @Test func doNotCrossOverNonAdverbSegment() {
    // "ねこを"    | "ネコを" "猫を"
    // "すごく"    | "すごく"
    // "かいたい"  | "買いたい" "解体" "飼いたい"
    let id = posMatcher.getUnknownId()
    let kSugoku = "すごく"
    let kSugokuCands = [CandidateData(kSugoku, kSugoku, kSugoku, kSugoku, 0, id, id)]
    let segments = Segments()
    Self.makeSegments(
      [
        SegmentData("ねこを", nekowoCands()), SegmentData(kSugoku, kSugokuCands),
        SegmentData("かいたい", kaitaiCands()),
      ], segments)

    #expect(!rewrite(segments))
    #expect(Self.getTopValue(segments) != "猫をすごく飼いたい", "\(segments.debugString())")
  }

  @Test func doNotPromoteHighCostCandidate() {
    // Actually, we want to test for the collocation entries that are NOT in the
    // data sources, but will be judged as existing entry due to false positive.
    // However, we can not expect which entry will be false positive, so here
    // we use the existing entry for this test.

    // Make the following Segments:
    // "ねこを" | "かいたい"
    // --------------------
    // "ネコを" | "買いたい"
    // "猫を"   | "解体"
    //         | "飼いたい" (high cost)
    let segments = Segments()
    Self.makeSegments(
      [SegmentData("ねこを", nekowoCands()), SegmentData("かいたい", kaitaiCands(feedCost: 10000))],
      segments)

    // "猫を飼いたい" should NOT be promoted.
    #expect(!rewrite(segments))
    #expect(Self.getTopValue(segments) != "猫を飼いたい", "\(segments.debugString())")
  }

  @Test func immuneToInvalidSegments() {
    let kUnkId = posMatcher.getUnknownId()
    let kSegments = [
      SegmentData("ねこを", [CandidateData("ねこを", "ねこ", "猫", "猫を", 0, kUnkId, kUnkId)]),
      SegmentData(
        "かいたい", [CandidateData("かいたい", "かいたい", "飼いたい", "飼いたい", 0, kUnkId, kUnkId)]),
    ]

    do {
      let segments = Segments()
      Self.makeSegments(kSegments, segments)
      // If there's a fixed segment, rewrite fails.
      segments.mutableSegment(0).setSegmentType(.fixedValue)
      #expect(!rewrite(segments))
    }
    do {
      let segments = Segments()
      Self.makeSegments(kSegments, segments)
      // If there's a segment with no candidates, rewrite fails.
      segments.mutableSegment(0).clearCandidates()
      #expect(!rewrite(segments))
    }
  }

  @Test func removeNumber() {
    // Rule: "周回っ", "周回って"
    let id = posMatcher.getUnknownId()

    do {
      // "いっしゅう" | "まわって"
      // --------------------
      // "一週" | "回って"
      // "一周" |
      let kLeftCands = [
        CandidateData("いっしゅう", "いっしゅう", "一週", "一週", 0, id, id),
        CandidateData("いっしゅう", "いっしゅう", "一周", "一周", 0, id, id),
      ]
      let kRightCands = [CandidateData("まわって", "まわっ", "回って", "回っ", 0, id, id)]
      let segments = Segments()
      Self.makeSegments(
        [SegmentData("いっしゅう", kLeftCands), SegmentData("まわって", kRightCands)], segments)

      // "一周回って" should be promoted.
      #expect(rewrite(segments))
      #expect(Self.getTopValue(segments) == "一周回って", "\(segments.debugString())")
    }

    do {
      // "しゅう" | "いっかいって"
      // --------------------
      // "週" | "一回って"
      // "周" |
      let kLeftCands = [
        CandidateData("しゅう", "しゅう", "週", "週", 0, id, id),
        CandidateData("しゅう", "しゅう", "周", "周", 0, id, id),
      ]
      let kRightCands = [CandidateData("いっかいって", "いっかい", "一回って", "一回", 0, id, id)]
      let segments = Segments()
      Self.makeSegments(
        [SegmentData("しゅう", kLeftCands), SegmentData("いっかいって", kRightCands)], segments)

      // "周一回って" should NOT be promoted.
      #expect(!rewrite(segments))
      #expect(Self.getTopValue(segments) == "週一回って", "\(segments.debugString())")
    }
  }
}
