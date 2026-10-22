// Port of mozc/src/rewriter/single_kanji_rewriter_test.cc (3.35.6354).
//
// The C++ fixture builds `engine::Modules` from the mock data manager; the
// Swift tests build the `PosMatcher` and `SingleKanjiDictionary` (what
// `Modules::GetPosMatcher()` / `GetSingleKanjiDictionary()` return) directly
// from `MockDataManager`, since engine/modules is not ported yet.

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

@Suite(.enabled(if: R2RewriterTestSupport.hasMockData, R2RewriterTestSupport.mockDataMissing))
struct SingleKanjiRewriterTests {
  let posMatcher: PosMatcher
  let singleKanjiDictionary: SingleKanjiDictionary
  let defaultRequest = ConversionRequest()

  init() throws {
    let dataManager = try R2RewriterTestSupport.mockDataManager()
    posMatcher = PosMatcher(dataManager.getPosMatcherData())
    singleKanjiDictionary = SingleKanjiDictionary(dataManager.getSingleKanjiRewriterData())
  }

  private func createSingleKanjiRewriter() -> SingleKanjiRewriter {
    SingleKanjiRewriter(posMatcher, singleKanjiDictionary)
  }

  private static func initSegments(_ key: String, _ value: String, _ segments: Segments) {
    let segment = segments.addSegment()
    segment.setKey(key)

    let candidate = segment.addCandidate()
    candidate.key = key
    candidate.contentKey = key
    candidate.value = value
    candidate.contentValue = value
  }

  /// Bytewise: "\u{FA19}" and "\u{795E}" are canonically equivalent.
  private static func contains(_ segments: Segments, _ word: String) -> Bool {
    segments.segment(0).candidates.contains { $0.value.bytesEqual(word) }
  }

  private static func convReq(_ request: Genmai_Commands_Request, _ type: RequestType)
    -> ConversionRequest
  {
    ConversionRequestBuilder().setRequest(request).setRequestType(type).build()
  }

  @Test func capabilityTest() {
    let rewriter = createSingleKanjiRewriter()
    var request = Genmai_Commands_Request()
    request.mixedConversion = false
    let convreq = Self.convReq(request, .conversion)
    #expect(rewriter.capability(convreq) == .conversion)
  }

  @Test func setKeyTest() {
    let rewriter = createSingleKanjiRewriter()

    let segments = Segments()
    let segment = segments.addSegment()
    let kKey = "あ"
    segment.setKey(kKey)
    let candidate = segment.addCandidate()
    // First candidate may be inserted by other rewriters.
    candidate.key = "strange key"
    candidate.contentKey = "starnge key"
    candidate.value = "starnge value"
    candidate.contentValue = "strange value"

    #expect(segment.candidatesSize == 1)
    _ = rewriter.rewrite(defaultRequest, segments)
    #expect(segment.candidatesSize > 1)
    for i in 1..<segment.candidatesSize {
      #expect(segment.candidate(i).key == kKey)
    }
  }

  @Test func mobileEnvironmentTest() {
    var request = Genmai_Commands_Request()
    let rewriter = createSingleKanjiRewriter()
    do {
      request.mixedConversion = true
      let convreq = Self.convReq(request, .conversion)
      #expect(rewriter.capability(convreq) == .all)
    }
    do {
      request.mixedConversion = false
      let convreq = Self.convReq(request, .conversion)
      #expect(rewriter.capability(convreq) == .conversion)
    }
  }

  @Test func nounPrefixTest() {
    let rewriter = createSingleKanjiRewriter()

    let segments = Segments()
    let segment1 = segments.addSegment()

    segment1.setKey("み")
    var candidate1 = segment1.addCandidate()

    candidate1.key = "み"
    candidate1.contentKey = "見"
    candidate1.value = "見"
    candidate1.contentValue = "見"

    #expect(segment1.candidatesSize == 1)
    _ = rewriter.rewrite(defaultRequest, segments)

    #expect(segment1.candidate(0).value == "未")

    let segment2 = segments.addSegment()

    segment2.setKey("こうたい")
    let candidate2 = segment2.addCandidate()

    candidate2.key = "こうたい"
    candidate2.contentKey = "後退"
    candidate2.value = "後退"

    candidate2.lid = posMatcher.getContentWordWithConjugationId()
    candidate2.rid = posMatcher.getContentWordWithConjugationId()

    candidate1 = segment1.mutableCandidate(0)
    candidate1.assign(from: Candidate())
    candidate1.key = "み"
    candidate1.contentKey = "見"
    candidate1.value = "見"
    candidate1.contentValue = "見"

    _ = rewriter.rewrite(defaultRequest, segments)
    #expect(segment1.candidate(0).value == "見")

    // Only applied when right word's POS is noun.
    candidate2.lid = posMatcher.getContentNounId()
    candidate2.rid = posMatcher.getContentNounId()

    _ = rewriter.rewrite(defaultRequest, segments)
    #expect(segment1.candidate(0).value == "未")

    #expect(segment1.candidate(0).lid == posMatcher.getNounPrefixId())
    #expect(segment1.candidate(0).rid == posMatcher.getNounPrefixId())
  }

  @Test func insertionPositionTest() {
    let rewriter = createSingleKanjiRewriter()

    let segments = Segments()
    let segment = segments.addSegment()

    segment.setKey("あ")
    for i in 0..<10 {
      let candidate = segment.addCandidate()
      candidate.key = segment.key
      candidate.contentKey = segment.key
      candidate.value = "cand\(i)"
      candidate.contentValue = candidate.value
    }

    #expect(segment.candidatesSize == 10)
    #expect(rewriter.rewrite(defaultRequest, segments))
    #expect(10 < segment.candidatesSize)  // Some candidates were inserted.

    for i in 0..<10 {
      // First 10 candidates have not changed.
      #expect(segment.candidate(i).value == "cand\(i)")
    }
  }

  @Test func addDescriptionTest() {
    let rewriter = createSingleKanjiRewriter()

    let segments = Segments()

    func initSegment() -> Segment {
      segments.clear()
      let segment = segments.addSegment()

      segment.setKey("あ")
      let candidate = segment.addCandidate()
      candidate.key = segment.key
      candidate.contentKey = segment.key
      candidate.value = "亞"  // variant of "亜".
      candidate.contentValue = candidate.value
      return segment
    }

    // desktop
    do {
      let segment = initSegment()
      #expect(segment.candidatesSize == 1)
      #expect(segment.candidate(0).description.isEmpty)
      #expect(rewriter.rewrite(defaultRequest, segments))
      #expect(1 < segment.candidatesSize)  // Some candidates were inserted.
      #expect(segment.candidate(0).description == "亜の旧字体")
    }

    // Only sets the description in mixed conversion mode.
    do {
      var request = Genmai_Commands_Request()
      RequestTestUtil.fillMobileRequest(&request)
      let segment = initSegment()
      let convreq = Self.convReq(request, .prediction)
      #expect(segment.candidatesSize == 1)
      #expect(segment.candidate(0).description.isEmpty)
      #expect(rewriter.rewrite(convreq, segments))
      #expect(segment.candidatesSize == 1)  // No candidates were inserted.
      #expect(segment.candidate(0).description == "亜の旧字体")
    }
  }

  @Test func triggerConditionForPrediction() throws {
    let rewriter = createSingleKanjiRewriter()

    do {
      let segments = Segments()
      Self.initSegments("あ", "あ", segments)

      var request = Genmai_Commands_Request()
      RequestTestUtil.fillMobileRequest(&request)
      let convreq = Self.convReq(request, .prediction)
      try #require(rewriter.capability(convreq).contains(.prediction))
      #expect(rewriter.rewrite(convreq, segments))
    }

    do {
      let segments = Segments()
      Self.initSegments("あ", "あ", segments)

      var request = Genmai_Commands_Request()
      RequestTestUtil.fillMobileRequestWithHardwareKeyboard(&request)
      let convreq = Self.convReq(request, .prediction)
      try #require(!rewriter.capability(convreq).contains(.prediction))
    }

    do {
      let segments = Segments()
      Self.initSegments("あ", "あ", segments)

      var request = Genmai_Commands_Request()
      RequestTestUtil.fillMobileRequestWithHardwareKeyboard(&request)
      let convreq = Self.convReq(request, .conversion)
      try #require(rewriter.capability(convreq).contains(.conversion))
      #expect(rewriter.rewrite(convreq, segments))
    }
  }

  @Test func noVariationTest() {
    let rewriter = createSingleKanjiRewriter()

    let segments = Segments()
    Self.initSegments("かみ", "神", segments)  // U+795E

    var request = Genmai_Commands_Request()
    request.decoderExperimentParams.variationCharacterTypes = UInt32(
      Genmai_Commands_DecoderExperimentParams.VariationCharacterType.noVariation.rawValue)
    let svsConvreq = Self.convReq(request, .conversion)

    #expect(segments.segment(0).candidatesSize == 1)
    #expect(rewriter.rewrite(svsConvreq, segments))
    #expect(!Self.contains(segments, "\u{795E}\u{FE00}"))  // 神︀ SVS character.
    #expect(Self.contains(segments, "\u{FA19}"))  // 神 CJK compat ideograph.
  }

  @Test func svsVariationTest() {
    let rewriter = createSingleKanjiRewriter()

    let segments = Segments()
    Self.initSegments("かみ", "神", segments)  // U+795E

    var request = Genmai_Commands_Request()
    request.decoderExperimentParams.variationCharacterTypes = UInt32(
      Genmai_Commands_DecoderExperimentParams.VariationCharacterType.svsJapanese.rawValue)
    let svsConvreq = Self.convReq(request, .conversion)

    #expect(segments.segment(0).candidatesSize == 1)
    #expect(rewriter.rewrite(svsConvreq, segments))
    #expect(Self.contains(segments, "\u{795E}\u{FE00}"))  // 神︀ SVS character.
    #expect(!Self.contains(segments, "\u{FA19}"))  // 神 CJK compat ideograph.
  }

  @Test func emptySegments() {
    let rewriter = createSingleKanjiRewriter()
    let segments = Segments()
    #expect(segments.conversionSegmentsSize == 0)
    #expect(!rewriter.rewrite(defaultRequest, segments))
  }

  @Test func emptyCandidates() {
    let rewriter = createSingleKanjiRewriter()
    let segments = Segments()
    let segment = segments.addSegment()
    segment.setKey("み")

    #expect(segments.conversionSegmentsSize == 1)
    #expect(segments.conversionSegment(0).candidatesSize == 0)
    #expect(!rewriter.rewrite(defaultRequest, segments))
  }
}
