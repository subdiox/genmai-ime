// Port of mozc/src/rewriter/small_letter_rewriter_test.cc (3.35.6354).
//
// The C++ fixture creates a mock-data Engine that the tests never use; it is
// omitted.

import GenmaiProtocol
import Testing
@testable import GenmaiCore

@Suite struct SmallLetterRewriterTests {
  private static func addSegment(_ key: String, _ value: String, _ segments: Segments) {
    let seg = segments.addSegment()
    let candidate = seg.addCandidate()
    seg.setKey(key)
    candidate.contentKey = key
    candidate.value = value
    candidate.contentValue = value
  }

  private static func initSegments(_ key: String, _ value: String, _ segments: Segments) {
    segments.clear()
    addSegment(key, value, segments)
  }

  private static func containCandidate(_ segments: Segments, _ candidate: String) -> Bool {
    let segment = segments.segment(0)
    for i in 0..<segment.candidatesSize where candidate.bytesEqual(segment.candidate(i).value) {
      return true
    }
    return false
  }

  @Test func scriptConversionTest() {
    let segments = Segments()
    let rewriter = SmallLetterRewriter()

    let kInputOutputData: [(input: String, output: String)] = [
      // Superscript
      ("^123", "¹²³"),
      ("^4", "⁴"),
      ("^56789", "⁵⁶⁷⁸⁹"),
      ("^2^+^(^3^-^1^)^=", "²⁺⁽³⁻¹⁾⁼"),

      // Subscript
      ("_123", "₁₂₃"),
      ("_4", "₄"),
      ("_56789", "₅₆₇₈₉"),
      ("_2_+_(_3_-_1_)_=", "₂₊₍₃₋₁₎₌"),

      // Math Formula
      ("x^2+y^2=z^2", "x²+y²=z²"),

      // Chemical Formula
      ("Na_2CO_3", "Na₂CO₃"),
      ("C_6H_12O_6", "C₆H₁₂O₆"),
      ("(NH_4)_2CO_3", "(NH₄)₂CO₃"),
      ("2Na_2CO_3", "2Na₂CO₃"),
      ("2H_2O", "2H₂O"),
      ("O^2^-", "O²⁻"),

      // Others
      ("O^2-", "O²-"),
      ("O^X_2", "O^X₂"),
      ("_2O^", "₂O^"),
      ("あ^2", "あ²"),
    ]

    let kGenmaiUnsupportedInput = [
      // Roman alphabet superscript
      "^n",
      "^x",
      "^a",
      // Roman alphabet subscript
      "_m",
      "_y",
      "_b",

      // Multibyte characters
      "_あ",
      "_⏰",

      // Formula without explicit prefix is not supported
      "H2O",
      "Na+",
      "NH4+",
      "C2O42-",
      "AKB48",

      // Others
      "あ^あ",
      "x^^x",
    ]

    // Test behavior for each test cases in kInputOutputData.
    for item in kInputOutputData {
      Self.initSegments(item.input, item.input, segments)
      let request = ConversionRequestBuilder().setKey(item.input).build()
      #expect(rewriter.rewrite(request, segments), "\(item.input)")
      #expect(Self.containCandidate(segments, item.output), "\(item.input)")
    }

    // Mozc does not accept some superscript/subscript supported in Unicode
    for item in kGenmaiUnsupportedInput {
      Self.initSegments(item, item, segments)
      let request = ConversionRequestBuilder().setKey(item).build()
      #expect(!rewriter.rewrite(request, segments), "\(item)")
    }

    let kInvalidInput = ["^", "_", "12345", "^^12345"]
    for invalidInput in kInvalidInput {
      Self.initSegments("^", "^", segments)
      let request = ConversionRequestBuilder().setKey(invalidInput).build()
      #expect(!rewriter.rewrite(request, segments), "\(invalidInput)")
    }
  }

  @Test func multipleSegment() throws {
    let rewriter = SmallLetterRewriter()

    do {
      // Multiple segments (flag = false).
      let segments = Segments()
      Self.initSegments("^123", "^123", segments)
      Self.addSegment("45", "45", segments)
      Self.addSegment("6", "6", segments)
      let request = ConversionRequestBuilder().setKey("^123456").build()
      let resizeRequest = try #require(rewriter.checkResizeSegmentsRequest(request, segments))
      #expect(resizeRequest.segmentIndex == 0)
      #expect(resizeRequest.segmentSizes[0] == 7)
      #expect(resizeRequest.segmentSizes[1] == 0)
      #expect(!rewriter.rewrite(request, segments))
    }

    do {
      // Multiple segments are combined (flag = true).
      let segments = Segments()
      Self.initSegments("^123", "^123", segments)
      Self.addSegment("45", "45", segments)
      Self.addSegment("6", "6", segments)
      var requestProto = Genmai_Commands_Request()
      requestProto.decoderExperimentParams.enableMultiSegmentCandidate = true
      let request = ConversionRequestBuilder().setRequest(requestProto).setKey("^123456").build()
      #expect(rewriter.checkResizeSegmentsRequest(request, segments) == nil)
      #expect(rewriter.rewrite(request, segments))
      #expect(Self.containCandidate(segments, "¹²³⁴⁵⁶"))
      let seg = segments.conversionSegment(0)
      #expect(seg.candidate(0).value == "¹²³⁴⁵⁶")
      #expect(seg.candidate(0).convertedSegmentCount == 3)
    }

    do {
      // If the segments is already resized, returns false.
      let segments = Segments()
      Self.initSegments("^123", "^123", segments)
      Self.addSegment("^123", "^123", segments)
      segments.setResized(true)
      let request = ConversionRequestBuilder().setKey("^123").build()
      #expect(rewriter.checkResizeSegmentsRequest(request, segments) == nil)
    }

    do {
      // History segment has to be ignored.
      // In this case 1st segment is HISTORY
      // so this rewriting returns true.
      let segments = Segments()
      Self.initSegments("^123", "^123", segments)
      Self.addSegment("^123", "^123", segments)
      segments.setResized(true)
      segments.mutableSegment(0).setSegmentType(.history)
      let request = ConversionRequestBuilder().setKey("^123").build()
      #expect(rewriter.checkResizeSegmentsRequest(request, segments) == nil)
      #expect(rewriter.rewrite(request, segments))
      #expect(segments.conversionSegment(0).candidate(1).value == "¹²³")
    }
  }
}
