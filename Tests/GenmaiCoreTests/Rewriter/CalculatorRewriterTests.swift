// Port of mozc/src/rewriter/calculator_rewriter_test.cc (3.35.6354).

import GenmaiProtocol
import Testing

@testable import GenmaiCore

@Suite struct CalculatorRewriterTests {
  private static func addCandidate(_ key: String, _ value: String, _ segment: Segment) {
    let candidate = segment.addCandidate()
    candidate.value = value
    candidate.contentValue = value
    candidate.contentKey = key
  }

  private static func addSegment(_ key: String, _ value: String, _ segments: Segments) {
    let segment = segments.pushBackSegment()
    segment.setKey(key)
    addCandidate(key, value, segment)
  }

  private static func setSegment(_ key: String, _ value: String, _ segments: Segments) {
    segments.clear()
    addSegment(key, value, segments)
  }

  private static let kCalculationDescription = "計算結果"

  private static func containsCalculatedResult(_ candidate: Candidate) -> Bool {
    candidate.description.contains(kCalculationDescription)
  }

  /// If the segment has a candidate which was inserted by CalculatorRewriter,
  /// then return its index. Otherwise return -1.
  private static func getIndexOfCalculatedCandidate(_ segments: Segments) -> Int {
    precondition(segments.segmentsSize >= 1)
    for i in 0..<segments.segment(0).candidatesSize
    where containsCalculatedResult(segments.segment(0).candidate(i)) {
      return i
    }
    return -1
  }

  private static func convReq(
    _ config: Genmai_Config_Config, _ request: Genmai_Commands_Request, _ key: String = ""
  ) -> ConversionRequest {
    ConversionRequestBuilder().setConfig(config).setRequest(request).setKey(key).build()
  }

  private var request = Genmai_Commands_Request()
  private var config: Genmai_Config_Config = {
    var c = ConfigHandler.defaultConfig()
    c.useCalculator = true
    return c
  }()

  @Test func insertCandidateTest() {
    let calculatorRewriter = CalculatorRewriter()

    do {
      let segment = Segment()
      segment.setKey("key")
      // Insertion should be failed if segment has no candidate beforehand
      #expect(!calculatorRewriter.insertCandidate("key", "value", 1, 0, segment))
    }

    let expected = Candidate()
    expected.value = "value"
    expected.key = "key"
    expected.contentKey = "key"
    expected.contentValue = "value"
    expected.attributes = Attribute.noLearning | Attribute.noVariantsExpansion
    expected.description = Self.kCalculationDescription

    // Test insertion at each position of candidates list
    for i in 0...2 {
      let segment = Segment()
      segment.setKey("key")
      Self.addCandidate("key", "test", segment)
      Self.addCandidate("key", "test2", segment)

      #expect(calculatorRewriter.insertCandidate("key", "value", 1, i, segment))
      #expect(segment.candidatesSize > i)
      #expect(equalsCandidate(segment.candidate(i), expected) == nil)
    }
  }

  // CalculatorRewriter should convert an expression which is separated to
  // multiple conversion segments. This test verifies it.
  @Test func separatedSegmentsTest() throws {
    let calculatorRewriter = CalculatorRewriter()

    do {
      // Flag is false (default): Rewrite returns false,
      // CheckResizeSegmentsRequest returns resize request.
      let segments = Segments()
      Self.addSegment("1", "1", segments)
      Self.addSegment("+", "+", segments)
      Self.addSegment("1", "1", segments)
      Self.addSegment("=", "=", segments)

      let convreq = Self.convReq(config, request, "1+1=")
      #expect(!calculatorRewriter.rewrite(convreq, segments))

      let resizeRequest = try #require(
        calculatorRewriter.checkResizeSegmentsRequest(convreq, segments))
      #expect(resizeRequest.segmentIndex == 0)
      #expect(resizeRequest.segmentSizes[0] == 4)
    }

    do {
      // Flag is true: Rewrite returns true, CheckResizeSegmentsRequest returns
      // std::nullopt.
      let segments = Segments()
      Self.addSegment("1", "1", segments)
      Self.addSegment("+", "+", segments)
      Self.addSegment("1", "1", segments)
      Self.addSegment("=", "=", segments)

      var requestProto = request
      requestProto.decoderExperimentParams.enableMultiSegmentCandidate = true
      let convreq = Self.convReq(config, requestProto, "1+1=")
      #expect(calculatorRewriter.checkResizeSegmentsRequest(convreq, segments) == nil)

      #expect(calculatorRewriter.rewrite(convreq, segments))
      let index = Self.getIndexOfCalculatedCandidate(segments)
      try #require(index != -1)
      #expect(segments.segment(0).candidate(index).value == "2")
      #expect(segments.segment(0).candidate(index).convertedSegmentCount == 4)
    }
  }

  // CalculatorRewriter should convert an expression starting with '='.
  @Test func expressionStartingWithEqualTest() throws {
    let calculatorRewriter = CalculatorRewriter()
    let request = ConversionRequestBuilder().setKey("=1+1").build()

    let segments = Segments()
    Self.setSegment("=1+1", "=1+1", segments)
    _ = calculatorRewriter.rewrite(request, segments)
    let index = Self.getIndexOfCalculatedCandidate(segments)
    try #require(index != -1)
    #expect(segments.segment(0).candidate(index).value == "2")
    #expect(Self.containsCalculatedResult(segments.segment(0).candidate(index + 1)))
    // CalculatorRewriter should append the result to the side '=' exists.
    #expect(segments.segment(0).candidate(index + 1).value == "2=1+1")
  }

  // Verify the description of calculator candidate.
  @Test func descriptionCheckTest() throws {
    let kExpression = "５・（８／４）ー７％３＋６＾−１＊９＝"
    // Expected description
    let description = Self.kCalculationDescription

    let calculatorRewriter = CalculatorRewriter()

    let segments = Segments()
    Self.addSegment(kExpression, kExpression, segments)

    let convreq = Self.convReq(config, request, kExpression)
    _ = calculatorRewriter.rewrite(convreq, segments)
    let index = Self.getIndexOfCalculatedCandidate(segments)
    try #require(index != -1)

    #expect(segments.segment(0).candidate(index).description == description)
    #expect(Self.containsCalculatedResult(segments.segment(0).candidate(index + 1)))
  }

  @Test func configTest() throws {
    var config = self.config
    let calculatorRewriter = CalculatorRewriter()
    do {
      let segments = Segments()
      Self.addSegment("1", "1", segments)
      Self.addSegment("+", "+", segments)
      Self.addSegment("1", "1", segments)
      Self.addSegment("=", "=", segments)
      config.useCalculator = true
      var requestProto = request
      requestProto.decoderExperimentParams.enableMultiSegmentCandidate = true
      let convreq = Self.convReq(config, requestProto, "1+1=")
      #expect(calculatorRewriter.rewrite(convreq, segments))
      let index = Self.getIndexOfCalculatedCandidate(segments)
      try #require(index != -1)
      #expect(segments.segment(0).candidate(index).value == "2")
      #expect(segments.segment(0).candidate(index).convertedSegmentCount == 4)
    }

    do {
      let segments = Segments()
      Self.addSegment("1", "1", segments)
      Self.addSegment("+", "+", segments)
      Self.addSegment("1", "1", segments)
      Self.addSegment("=", "=", segments)
      config.useCalculator = false
      let convreq = Self.convReq(config, request, "1+1=")
      #expect(!calculatorRewriter.rewrite(convreq, segments))
      #expect(calculatorRewriter.checkResizeSegmentsRequest(convreq, segments) == nil)
    }
  }

  @Test func mobileEnvironmentTest() {
    var request = self.request
    let rewriter = CalculatorRewriter()
    do {
      request.mixedConversion = true
      let convreq = Self.convReq(config, request)
      #expect(rewriter.capability(convreq) == .all)
    }
    do {
      request.mixedConversion = false
      let convreq = Self.convReq(config, request)
      #expect(rewriter.capability(convreq) == .conversion)
    }
  }

  @Test func emptyKeyTest() {
    var config = self.config
    let calculatorRewriter = CalculatorRewriter()
    do {
      let segments = Segments()
      Self.addSegment("", "1", segments)
      config.useCalculator = true
      let convreq = Self.convReq(config, request, "")
      #expect(!calculatorRewriter.rewrite(convreq, segments))
    }
  }
}
