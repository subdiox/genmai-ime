// Port of mozc/src/rewriter/symbol_rewriter_test.cc (3.35.6354).
//
// Note that these tests are using default symbol dictionary.
// Test result can be changed if symbol dictionary is modified.

import GenmaiBase
import GenmaiProtocol
import Testing
@testable import GenmaiCore

@Suite(.enabled(if: R2RewriterTestSupport.hasMockData, R2RewriterTestSupport.mockDataMissing))
struct SymbolRewriterTests {
  private static func addSegment(_ key: String, _ value: String, _ segments: Segments) {
    let seg = segments.pushBackSegment()
    seg.setKey(key)
    let candidate = seg.addCandidate()
    candidate.value = value
    candidate.contentKey = key
    candidate.contentValue = value
  }

  private static func addCandidate(_ value: String, _ segment: Segment) {
    let candidate = segment.addCandidate()
    candidate.value = value
    candidate.contentKey = segment.key
    candidate.contentValue = value
  }

  private static func hasCandidateAndDescription(
    _ segments: Segments, _ index: Int, _ key: String, _ description: String
  ) -> Bool {
    precondition(segments.segmentsSize > index)
    let checkDescription = !description.isEmpty

    for candidate in segments.segment(index).candidates where candidate.value.bytesEqual(key) {
      if checkDescription {
        return candidate.description.bytesEqual(description)
      } else {
        return true
      }
    }
    return false
  }

  private static func getCandidateIndex(_ segments: Segments, _ index: Int, _ key: String) -> Int {
    R2RewriterTestSupport.rankOfValue(segments.segment(index), key) ?? -1
  }

  private static func hasCandidate(_ segments: Segments, _ index: Int, _ value: String) -> Bool {
    hasCandidateAndDescription(segments, index, value, "")
  }

  private func makeRewriter() throws -> SymbolRewriter {
    SymbolRewriter(try R2RewriterTestSupport.mockDataManager().getSymbolRewriterData())
  }

  @Test func checkResizeSegmentsRequestTest() throws {
    let symbolRewriter = try makeRewriter()

    do {
      // Two segments should be resized to one segment (i.e. "ー>") (flag =
      // false).
      let segments = Segments()
      Self.addSegment("ー", "test", segments)
      Self.addSegment(">", "test", segments)
      let request = ConversionRequestBuilder().setKey("ー>").build()
      let resizeRequest = try #require(
        symbolRewriter.checkResizeSegmentsRequest(request, segments))
      #expect(resizeRequest.segmentIndex == 0)
      #expect(resizeRequest.segmentSizes[0] == 2)
    }
    do {
      // Two segments with flag = true (multi-segment candidate).
      let segments = Segments()
      Self.addSegment("ー", "test", segments)
      Self.addSegment(">", "test", segments)
      var requestProto = Genmai_Commands_Request()
      requestProto.decoderExperimentParams.enableMultiSegmentCandidate = true
      let request = ConversionRequestBuilder().setRequest(requestProto).setKey("ー>").build()
      #expect(symbolRewriter.checkResizeSegmentsRequest(request, segments) == nil)
      #expect(symbolRewriter.rewrite(request, segments))
      #expect(Self.hasCandidate(segments, 0, "→"))
      let seg = segments.conversionSegment(0)
      var found = false
      for candidate in seg.candidates where candidate.value.bytesEqual("→") {
        #expect(candidate.convertedSegmentCount == 2)
        found = true
        break
      }
      #expect(found)
    }
    do {
      // Already resized.
      let segments = Segments()
      Self.addSegment("ー", "test", segments)
      Self.addSegment(">", "test", segments)
      segments.setResized(true)
      let request = ConversionRequestBuilder().setKey("ー>").build()
      #expect(symbolRewriter.checkResizeSegmentsRequest(request, segments) == nil)
    }
    do {
      // Single segment.
      let segments = Segments()
      Self.addSegment("ー>", "test", segments)
      let request = ConversionRequestBuilder().setKey("ー>").build()
      #expect(symbolRewriter.rewrite(request, segments))
      #expect(Self.hasCandidate(segments, 0, "→"))
    }
    do {
      // No applicable symbols.
      let segments = Segments()
      Self.addSegment("ー", "test", segments)
      Self.addSegment("ー", "test", segments)
      let request = ConversionRequestBuilder().setKey("ーー").build()
      #expect(symbolRewriter.checkResizeSegmentsRequest(request, segments) == nil)
    }
  }

  @Test func triggerRewriteEachTest() throws {
    let symbolRewriter = try makeRewriter()
    let request = ConversionRequest()
    let segments = Segments()
    Self.addSegment("ー", "test", segments)
    Self.addSegment(">", "test", segments)
    #expect(symbolRewriter.rewriteEachCandidate(request, segments))
    #expect(segments.segmentsSize == 2)
    #expect(Self.hasCandidate(segments, 0, "―"))
    #expect(!Self.hasCandidate(segments, 0, "→"))
    #expect(Self.hasCandidate(segments, 1, "〉"))
  }

  @Test func rareSymbolTest() throws {
    let symbolRewriter = try makeRewriter()
    let request = ConversionRequest()
    let kCandidatesSize = 100
    do {
      let segments = Segments()
      Self.addSegment("あ", "あ", segments)
      for _ in 0..<kCandidatesSize {
        Self.addCandidate("test", segments.mutableSegment(0))
      }
      #expect(symbolRewriter.rewrite(request, segments))
      #expect(Self.hasCandidateAndDescription(segments, 0, "\u{1B002}", "安の変体仮名"))
      #expect(Self.hasCandidateAndDescription(segments, 0, "\u{1B003}", "愛の変体仮名"))
      #expect(!Self.hasCandidateAndDescription(segments, 0, "\u{1B007}", "伊の変体仮名"))

      // Kana variants are put at bottom.
      #expect(Self.getCandidateIndex(segments, 0, "\u{1B002}") > kCandidatesSize)
      #expect(Self.getCandidateIndex(segments, 0, "\u{1B003}") > kCandidatesSize)
    }
    do {
      let segments = Segments()
      Self.addSegment("いぇ", "いぇ", segments)
      #expect(symbolRewriter.rewrite(request, segments))
      #expect(Self.hasCandidateAndDescription(segments, 0, "\u{1B001}", "江の変体仮名"))
      #expect(Self.hasCandidateAndDescription(segments, 0, "\u{1B121}", "変体仮名"))
    }
    do {
      let segments = Segments()
      Self.addSegment("いぬ", "いぬ", segments)
      for _ in 0..<kCandidatesSize {
        Self.addCandidate("test", segments.mutableSegment(0))
      }
      #expect(symbolRewriter.rewrite(request, segments))
      #expect(Self.getCandidateIndex(segments, 0, "\u{130E1}") > kCandidatesSize)
    }
  }

  @Test func triggerRewriteDescriptionTest() throws {
    let symbolRewriter = try makeRewriter()
    let request = ConversionRequest()
    let segments = Segments()
    Self.addSegment("したつき", "test", segments)
    #expect(symbolRewriter.rewriteEachCandidate(request, segments))
    #expect(segments.segmentsSize == 1)
    #expect(Self.hasCandidateAndDescription(segments, 0, "₍", "下付き文字(始め丸括弧)"))
  }

  @Test func insertAfterSingleKanjiAndT13n() throws {
    let symbolRewriter = try makeRewriter()
    let request = ConversionRequest()
    let segments = Segments()
    Self.addSegment("てん", "てん", segments)
    let seg = segments.mutableSegment(0)
    // Add 15 single-kanji and transliterated candidates
    for value in [
      "点", "転", "天", "てん", "テン", "展", "店", "典", "添", "填", "顛", "辿", "纏", "甜", "貼",
    ] {
      Self.addCandidate(value, seg)
    }

    #expect(symbolRewriter.rewrite(request, segments))
    #expect(segments.segment(0).candidatesSize > 16)
    for i in 0..<16 {
      let value = segments.segment(0).candidate(i).value
      #expect(!Util.isScriptType(value, .unknownScript), "\(i): \(value)")
    }
  }

  @Test func insertSymbolsPositionMobileSymbolKey() throws {
    let symbolRewriter = try makeRewriter()
    var commandRequest = Genmai_Commands_Request()
    RequestTestUtil.fillMobileRequest(&commandRequest)
    let request = ConversionRequestBuilder().setRequest(commandRequest).build()

    let segments = Segments()
    Self.addSegment("%", "%", segments)  // segments from symbol key.
    let seg = segments.mutableSegment(0)
    // Add predictive candidates.
    Self.addCandidate("%引き", seg)
    Self.addCandidate("%増し", seg)
    Self.addCandidate("%台", seg)
    Self.addCandidate("%超え", seg)

    #expect(symbolRewriter.rewrite(request, segments))
    #expect(segments.segment(0).candidatesSize > 5)
    // Full width should be inserted with high ranking.
    #expect(segments.segment(0).candidate(1).value == "％")
  }

  @Test func insertSymbolsPositionMobileAlphabetKey() throws {
    let symbolRewriter = try makeRewriter()
    var commandRequest = Genmai_Commands_Request()
    RequestTestUtil.fillMobileRequest(&commandRequest)
    let request = ConversionRequestBuilder().setRequest(commandRequest).build()

    let segments = Segments()
    Self.addSegment("a", "app", segments)  // segments from alphabet key.
    let seg = segments.mutableSegment(0)
    // Add predictive candidates.
    Self.addCandidate("apple", seg)
    Self.addCandidate("align", seg)
    Self.addCandidate("andy", seg)
    Self.addCandidate("at", seg)

    #expect(symbolRewriter.rewrite(request, segments))
    #expect(segments.segment(0).candidatesSize > 5)  // Symbols were added
    // Should keep top candidates.
    #expect(segments.segment(0).candidate(0).value == "app")
    #expect(segments.segment(0).candidate(1).value == "apple")
    #expect(segments.segment(0).candidate(2).value == "align")
  }

  @Test func setKey() throws {
    let symbolRewriter = try makeRewriter()
    let segments = Segments()
    let request = ConversionRequest()

    let segment = segments.pushBackSegment()
    let kKey = "てん"
    segment.setKey(kKey)
    let candidate = segment.addCandidate()
    candidate.key = "strange key"
    candidate.value = "strange value"
    candidate.contentKey = "strange key"
    candidate.contentValue = "strange value"
    #expect(segment.candidatesSize == 1)
    #expect(symbolRewriter.rewrite(request, segments))
    #expect(segment.candidatesSize > 1)
    for i in 1..<segment.candidatesSize {
      #expect(segment.candidate(i).key == kKey)
    }
  }

  @Test func mobileEnvironmentTest() throws {
    var request = Genmai_Commands_Request()
    let symbolRewriter = try makeRewriter()
    do {
      request.mixedConversion = true
      let convreq = ConversionRequestBuilder().setRequest(request).build()
      #expect(symbolRewriter.capability(convreq) == .all)
    }
    do {
      request.mixedConversion = false
      let convreq = ConversionRequestBuilder().setRequest(request).build()
      #expect(symbolRewriter.capability(convreq) == .conversion)
    }
  }

  @Test func expandSpace() throws {
    let symbolRewriter = try makeRewriter()
    let segments = Segments()
    let request = ConversionRequest()

    let segment = segments.pushBackSegment()
    segment.setKey(" ")
    let candidate = segment.addCandidate()
    candidate.key = " "
    candidate.value = " "
    candidate.contentKey = " "
    candidate.contentValue = " "
    candidate.innerSegmentBoundary = buildInnerSegmentBoundary(
      [(1, 1, 1, 1)], candidate.key, candidate.value)

    #expect(symbolRewriter.rewrite(request, segments))
    #expect(2 <= segment.candidatesSize)

    let cand0 = segment.candidate(0)
    #expect(cand0.key == " ")
    #expect(cand0.value == " ")
    #expect(cand0.contentKey == " ")
    #expect(cand0.contentValue == " ")
    try #require(cand0.innerSegmentBoundary.count == 1)

    let kFullWidthSpace = "　"
    let cand1 = segment.candidate(1)
    #expect(cand1.key == " ")
    #expect(cand1.value == kFullWidthSpace)
    #expect(cand1.contentKey == " ")
    #expect(cand1.contentValue == kFullWidthSpace)
    #expect(cand1.innerSegmentBoundary.isEmpty)
  }

  @Test func invalidSizeOfSegments() throws {
    let symbolRewriter = try makeRewriter()

    // Valid case: segment size is 1.
    do {
      let segments = Segments()
      let request = ConversionRequest()

      // 1 segment. There are symbols assigned to "ぎりしゃ".
      Self.addSegment("ぎりしゃ", "test", segments)
      #expect(symbolRewriter.rewrite(request, segments))
    }

    // Invalid case: segment size is not 1.
    do {
      let segments = Segments()
      let request = ConversionRequest()

      // 0 segments.
      #expect(!symbolRewriter.rewrite(request, segments))

      // 2 segments. When enable_multi_segment_candidate is false,
      // segments are evaluated individually and request.key() ("おんがく")
      // is not used. Since neither "おん" nor "がく" is a symbol on its own,
      // Rewrite() returns false.
      Self.addSegment("おん", "test", segments)
      Self.addSegment("がく", "test", segments)
      #expect(!symbolRewriter.rewrite(request, segments))
    }
  }

  @Test func caseNormalizationTest() throws {
    let symbolRewriter = try makeRewriter()
    let request = ConversionRequest()

    // "tm" (half-width lower) is not defined in symbol.tsv, but it should be
    // automatically generated and registered by
    // gen_symbol_rewriter_dictionary_main.
    // "ＴＭ" (full-width upper) and "ｔｍ" (full-width lower) should also be
    // automatically registered.
    for key in ["tm", "ＴＭ", "ｔｍ"] {
      let segments = Segments()
      Self.addSegment(key, key, segments)
      #expect(symbolRewriter.rewrite(request, segments), "\(key)")
      #expect(Self.hasCandidate(segments, 0, "™"), "\(key)")
    }
  }
}
