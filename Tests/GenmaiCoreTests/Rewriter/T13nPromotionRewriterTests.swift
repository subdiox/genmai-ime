// Port of mozc/src/rewriter/t13n_promotion_rewriter_test.cc (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

@Suite(.enabled(if: ConverterCoreTestSupport.hasMockData, ConverterCoreTestSupport.mockDataMissing))
struct T13nPromotionRewriterTests {
  private static func addCandidateWithValue(_ value: String, _ segment: Segment) {
    let candidate = segment.addCandidate()
    candidate.key = segment.key
    candidate.contentKey = segment.key
    candidate.value = value
    candidate.contentValue = value
  }

  // Returns -1 if not found.
  private static func getCandidateIndexByValue(_ value: String, _ segment: Segment) -> Int {
    for i in 0..<segment.candidatesSize {
      if segment.candidate(i).value.bytesEqual(value) {
        return i
      }
    }
    return -1
  }

  /// The test fixture (SetUp()).
  private final class Fixture {
    let t13nRewriter: TransliterationRewriter
    var composer: Composer
    var mobileRequest: Genmai_Commands_Request

    init() throws {
      t13nRewriter = TransliterationRewriter(try ConverterCoreTestSupport.mockPosMatcher())
      composer = Composer()
      mobileRequest = Genmai_Commands_Request()
      RequestTestUtil.fillMobileRequest(&mobileRequest)
      composer.setRequest(mobileRequest)
    }

    func createMobileConversionRequest() -> ConversionRequest {
      ConversionRequestBuilder()
        .setComposer(composer)
        .setRequest(mobileRequest)
        .build()
    }
  }

  @Test func capability() throws {
    let f = try Fixture()
    let rewriter = T13nPromotionRewriter()

    // Mobile
    let mobileConvRequest = f.createMobileConversionRequest()
    #expect(rewriter.capability(mobileConvRequest) == .all)

    // Desktop
    let defaultConvRequest = ConversionRequest()
    #expect(rewriter.capability(defaultConvRequest) == .notAvailable)
  }

  @Test func promoteKatakanaFromT13N() throws {
    let f = try Fixture()
    let rewriter = T13nPromotionRewriter()

    let segments = Segments()
    f.composer.setInputMode(.hiragana)
    f.composer.setPreeditTextForTestOnly("きょう")
    let segment = segments.pushBackSegment()
    segment.setKey("きょう")
    for v in ["今日", "きょう", "強", "教", "凶", "卿"] {
      Self.addCandidateWithValue(v, segment)
    }

    #expect(Self.getCandidateIndexByValue("キョウ", segment) == -1)

    let mobileConvRequest = f.createMobileConversionRequest()
    #expect(f.t13nRewriter.rewrite(mobileConvRequest, segments))
    #expect(Self.getCandidateIndexByValue("キョウ", segment) == -1)

    #expect(rewriter.rewrite(mobileConvRequest, segments))
    #expect(Self.getCandidateIndexByValue("キョウ", segment) == 5)
  }

  @Test func promoteKatakanaFromT13NForFewCandidates() throws {
    let f = try Fixture()
    let rewriter = T13nPromotionRewriter()

    let segments = Segments()
    f.composer.setInputMode(.hiragana)
    f.composer.setPreeditTextForTestOnly("きょう")
    let segment = segments.pushBackSegment()
    segment.setKey("きょう")
    for v in ["今日", "きょう", "強"] {
      Self.addCandidateWithValue(v, segment)
    }

    #expect(Self.getCandidateIndexByValue("キョウ", segment) == -1)

    let mobileConvRequest = f.createMobileConversionRequest()
    #expect(f.t13nRewriter.rewrite(mobileConvRequest, segments))
    #expect(Self.getCandidateIndexByValue("キョウ", segment) == -1)

    #expect(rewriter.rewrite(mobileConvRequest, segments))
    #expect(Self.getCandidateIndexByValue("キョウ", segment) == 3)
  }

  @Test func promoteKatakana() throws {
    let f = try Fixture()
    let rewriter = T13nPromotionRewriter()

    let segments = Segments()
    f.composer.setInputMode(.hiragana)
    f.composer.setPreeditTextForTestOnly("きょう")
    let segment = segments.pushBackSegment()
    segment.setKey("きょう")
    for v in ["今日", "きょう", "強", "教", "凶", "卿", "京", "キョウ"] {
      Self.addCandidateWithValue(v, segment)
    }

    let katakanaIndex = Self.getCandidateIndexByValue("キョウ", segment)
    #expect(katakanaIndex == 7)

    let katakanaCandidate = segment.mutableCandidate(katakanaIndex)
    katakanaCandidate.lid = 1
    katakanaCandidate.rid = 1

    let mobileConvRequest = f.createMobileConversionRequest()
    #expect(f.t13nRewriter.rewrite(mobileConvRequest, segments))

    #expect(rewriter.rewrite(mobileConvRequest, segments))

    let promotedIndex = Self.getCandidateIndexByValue("キョウ", segment)
    // Make sure that the existing candidate was promoted.
    #expect(promotedIndex == 5)
    #expect(segment.candidate(promotedIndex).lid == 1)
    #expect(segment.candidate(promotedIndex).rid == 1)
  }

  @Test func promoteKatakanaOffset() throws {
    let f = try Fixture()
    let rewriter = T13nPromotionRewriter()

    let segments = Segments()
    f.composer.setInputMode(.hiragana)
    f.composer.setPreeditTextForTestOnly("きょう")
    let segment = segments.pushBackSegment()
    segment.setKey("きょう")
    for v in ["今日", "きょう", "強", "教", "凶", "卿", "京", "キョウ"] {
      Self.addCandidateWithValue(v, segment)
    }

    let katakanaIndex = Self.getCandidateIndexByValue("キョウ", segment)
    #expect(katakanaIndex == 7)

    let mobileConvRequest = f.createMobileConversionRequest()
    #expect(f.t13nRewriter.rewrite(mobileConvRequest, segments))

    do {
      f.mobileRequest.decoderExperimentParams.katakanaPromotionOffset = -1
      // Not promoted
      let convRequest = f.createMobileConversionRequest()
      #expect(!rewriter.rewrite(convRequest, segments))
    }
    do {
      f.mobileRequest.decoderExperimentParams.katakanaPromotionOffset = 6
      let convRequest = f.createMobileConversionRequest()
      #expect(rewriter.rewrite(convRequest, segments))
      let promotedIndex = Self.getCandidateIndexByValue("キョウ", segment)
      #expect(promotedIndex == 6)
    }
    do {
      f.mobileRequest.decoderExperimentParams.katakanaPromotionOffset = 1
      let convRequest = f.createMobileConversionRequest()
      #expect(rewriter.rewrite(convRequest, segments))
      let promotedIndex = Self.getCandidateIndexByValue("キョウ", segment)
      #expect(promotedIndex == 1)
    }
    do {
      f.mobileRequest.decoderExperimentParams.katakanaPromotionOffset = 0
      let convRequest = f.createMobileConversionRequest()
      #expect(rewriter.rewrite(convRequest, segments))
      let promotedIndex = Self.getCandidateIndexByValue("キョウ", segment)
      #expect(promotedIndex == 0)
    }
  }

  @Test func katakanaIsAlreadyRankedHigh() throws {
    let f = try Fixture()
    let rewriter = T13nPromotionRewriter()

    let segments = Segments()
    f.composer.setInputMode(.hiragana)
    f.composer.setPreeditTextForTestOnly("きょう")
    let segment = segments.pushBackSegment()
    segment.setKey("きょう")
    for v in ["今日", "きょう", "キョウ", "強", "教", "凶", "卿"] {
      Self.addCandidateWithValue(v, segment)
    }

    #expect(Self.getCandidateIndexByValue("キョウ", segment) == 2)

    let mobileConvRequest = f.createMobileConversionRequest()
    #expect(f.t13nRewriter.rewrite(mobileConvRequest, segments))

    #expect(!rewriter.rewrite(mobileConvRequest, segments))
    #expect(Self.getCandidateIndexByValue("キョウ", segment) == 2)
  }

  @Test func promoteKatakanaForMultiSegments() throws {
    let f = try Fixture()
    let rewriter = T13nPromotionRewriter()

    let segments = Segments()
    f.composer.setInputMode(.hiragana)
    f.composer.setPreeditTextForTestOnly("きょうははれ")
    var segment = segments.pushBackSegment()
    segment.setKey("きょうは")
    for v in ["今日は", "きょうは", "強は", "教は", "凶は", "卿は"] {
      Self.addCandidateWithValue(v, segment)
    }

    segment = segments.pushBackSegment()
    segment.setKey("はれ")
    for v in ["晴れ", "腫れ", "晴", "貼れ", "張れ", "脹れ"] {
      Self.addCandidateWithValue(v, segment)
    }

    let mobileConvRequest = f.createMobileConversionRequest()
    #expect(f.t13nRewriter.rewrite(mobileConvRequest, segments))

    #expect(Self.getCandidateIndexByValue("キョウハ", segments.conversionSegment(0)) == -1)
    #expect(Self.getCandidateIndexByValue("ハレ", segments.conversionSegment(1)) == -1)

    #expect(rewriter.rewrite(mobileConvRequest, segments))
    #expect(Self.getCandidateIndexByValue("キョウハ", segments.conversionSegment(0)) == 5)
    #expect(Self.getCandidateIndexByValue("ハレ", segments.conversionSegment(1)) == 5)
  }

  @Test func promoteLatinT13n() throws {
    let f = try Fixture()
    let rewriter = T13nPromotionRewriter()

    let segments = Segments()
    let segment = segments.pushBackSegment()
    segment.setKey("go")
    f.composer.setInputMode(.halfAscii)
    f.composer.setPreeditTextForTestOnly("go")
    for v in ["google", "golden", "goodness", "governor", "goalkeeper", "gorgeous"] {
      Self.addCandidateWithValue(v, segment)
    }

    let mobileConvRequest = f.createMobileConversionRequest()
    #expect(f.t13nRewriter.rewrite(mobileConvRequest, segments))

    #expect(Self.getCandidateIndexByValue("go", segments.conversionSegment(0)) == -1)

    #expect(rewriter.rewrite(mobileConvRequest, segments))
    let seg0 = segments.conversionSegment(0)
    #expect(Self.getCandidateIndexByValue("go", seg0) <= 3)
    #expect(Self.getCandidateIndexByValue("GO", seg0) <= 4)
    #expect(Self.getCandidateIndexByValue("Go", seg0) <= 5)
    #expect(Self.getCandidateIndexByValue("ｇｏ", seg0) <= 6)
    #expect(Self.getCandidateIndexByValue("ＧＯ", seg0) <= 7)
    #expect(Self.getCandidateIndexByValue("Ｇｏ", seg0) <= 8)
  }

  @Test func promoteLatinT13nSkipExisting() throws {
    let f = try Fixture()
    let rewriter = T13nPromotionRewriter()

    let segments = Segments()
    let segment = segments.pushBackSegment()
    segment.setKey("go")
    f.composer.setInputMode(.halfAscii)
    f.composer.setPreeditTextForTestOnly("go")
    for v in [
      "go", "ｇｏ", "google", "golden", "goodness", "governor", "goalkeeper", "gorgeous",
    ] {
      Self.addCandidateWithValue(v, segment)
    }

    let mobileConvRequest = f.createMobileConversionRequest()
    #expect(f.t13nRewriter.rewrite(mobileConvRequest, segments))
    #expect(rewriter.rewrite(mobileConvRequest, segments))
    let seg0 = segments.conversionSegment(0)
    #expect(seg0.candidate(1).value == "ｇｏ")
    for i in 2..<seg0.candidatesSize {
      // No dup T13N candidates
      #expect(seg0.candidate(i).value != "ｇｏ")
    }
  }

  @Test func promoteNumberT13n() throws {
    let f = try Fixture()
    let rewriter = T13nPromotionRewriter()

    let segments = Segments()
    let segment = segments.pushBackSegment()
    segment.setKey("12")
    f.composer.setInputMode(.halfAscii)
    f.composer.setPreeditTextForTestOnly("12")
    for v in ["12日", "12月", "1/2", "12個"] {
      Self.addCandidateWithValue(v, segment)
    }

    let mobileConvRequest = f.createMobileConversionRequest()
    #expect(f.t13nRewriter.rewrite(mobileConvRequest, segments))

    #expect(Self.getCandidateIndexByValue("１２", segments.conversionSegment(0)) == -1)

    #expect(rewriter.rewrite(mobileConvRequest, segments))
    #expect(Self.getCandidateIndexByValue("１２", segments.conversionSegment(0)) <= 4)
  }
}
