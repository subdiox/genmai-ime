// Port of mozc/src/rewriter/unicode_rewriter_test.cc (3.35.6354).
//
// The C++ fixture creates a mock-data Engine that the tests never use; it is
// omitted.

import Foundation
import GenmaiProtocol
import Testing

@testable import GenmaiCore

@Suite struct UnicodeRewriterTests {
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

  private static func firstByte(_ s: String) -> UInt8? { s.utf8.first }

  @Test func unicodeConversionTest() {
    let segments = Segments()
    let rewriter = UnicodeRewriter()

    let kCodepointUtf8Data: [(codepoint: String, utf8: String)] = [
      // Hiragana
      ("U+3042", "あ"),
      ("U+3044", "い"),
      ("U+3046", "う"),
      ("U+3048", "え"),
      ("U+304A", "お"),

      // Katakana
      ("U+30A2", "ア"),
      ("U+30A4", "イ"),
      ("U+30A6", "ウ"),
      ("U+30A8", "エ"),
      ("U+30AA", "オ"),

      // half-Katakana
      ("U+FF71", "ｱ"),
      ("U+FF72", "ｲ"),
      ("U+FF73", "ｳ"),
      ("U+FF74", "ｴ"),
      ("U+FF75", "ｵ"),

      // CJK
      ("U+611B", "愛"),
      ("U+690D", "植"),
      ("U+7537", "男"),

      // Other types (Oriya script)
      ("U+0B00", "\u{0B00}"),
      ("U+0B01", "\u{0B01}"),
      ("U+0B02", "\u{0B02}"),

      // Other types (Arabic)
      ("U+0600", "\u{0600}"),
      ("U+0601", "\u{0601}"),
      ("U+0602", "\u{0602}"),

      // Latin-1 support
      ("U+00A0", "\u{00A0}"),  // " " (nbsp)
      ("U+00A1", "¡"),
    ]

    let kGenmaiUnsupportedUtf8 = [
      // Control characters
      "U+0000",
      "U+001F",
      "U+007F",
      "U+0080",
      "U+009F",
      // Out of Unicode
      "U+110000",
      // Bidirectional text
      "U+200E",
      "U+202D",
    ]

    // All ascii code would be accepted.
    for ascii in UInt32(0x20)..<0x7F {
      let codepoint = String(format: "U+00%02X", ascii)
      Self.initSegments(codepoint, codepoint, segments)
      let request = ConversionRequestBuilder().setKey(codepoint).build()
      #expect(rewriter.rewrite(request, segments))
      #expect(Self.firstByte(segments.segment(0).candidate(0).value) == UInt8(ascii))
      #expect(segments.segment(0).candidate(0).attributes & Attribute.noModification != 0)
    }

    // Mozc accepts Japanese characters
    for item in kCodepointUtf8Data {
      let codepoint = item.codepoint
      Self.initSegments(codepoint, codepoint, segments)
      let request = ConversionRequestBuilder().setKey(codepoint).build()
      #expect(rewriter.rewrite(request, segments))
      #expect(Self.containCandidate(segments, item.utf8), "\(codepoint)")
      #expect(segments.segment(0).candidate(0).attributes & Attribute.noModification != 0)
    }

    // Mozc does not accept other characters
    for item in kGenmaiUnsupportedUtf8 {
      Self.initSegments(item, item, segments)
      let request = ConversionRequestBuilder().setKey(item).build()
      #expect(!rewriter.rewrite(request, segments), "\(item)")
    }

    // Invalid style input
    for invalidKey in ["U+123456789ABCDEF0", "U+12345678", "U+XYZ", "12345", "U12345"] {
      Self.initSegments(invalidKey, invalidKey, segments)
      let request = ConversionRequestBuilder().setKey(invalidKey).build()
      #expect(!rewriter.rewrite(request, segments), "\(invalidKey)")
    }
  }

  @Test func multipleSegment() throws {
    let rewriter = UnicodeRewriter()

    do {
      // Multiple segments to be combined (flag = false).
      let segments = Segments()
      Self.initSegments("U+0", "U+0", segments)
      Self.addSegment("02", "02", segments)
      Self.addSegment("0", "0", segments)
      let request = ConversionRequestBuilder().setKey("U+0020").build()
      let resizeRequest = try #require(rewriter.checkResizeSegmentsRequest(request, segments))
      #expect(resizeRequest.segmentIndex == 0)
      #expect(resizeRequest.segmentSizes[0] == 6)
      #expect(resizeRequest.segmentSizes[1] == 0)
      #expect(!rewriter.rewrite(request, segments))
    }

    do {
      // Multiple segments to be combined (flag = true).
      let segments = Segments()
      Self.initSegments("U+0", "U+0", segments)
      Self.addSegment("02", "02", segments)
      Self.addSegment("0", "0", segments)
      var requestProto = Genmai_Commands_Request()
      requestProto.decoderExperimentParams.enableMultiSegmentCandidate = true
      let request = ConversionRequestBuilder().setRequest(requestProto).setKey("U+0020").build()
      #expect(rewriter.checkResizeSegmentsRequest(request, segments) == nil)
      #expect(rewriter.rewrite(request, segments))
      #expect(Self.firstByte(segments.conversionSegment(0).candidate(0).value) == 0x20)
      #expect(segments.conversionSegment(0).candidate(0).convertedSegmentCount == 3)
    }

    do {
      // The segments is already resized.
      let segments = Segments()
      Self.initSegments("U+0", "U+0", segments)
      Self.addSegment("02", "02", segments)
      Self.addSegment("0", "0", segments)
      segments.setResized(true)
      let request = ConversionRequestBuilder().setKey("U+0020").build()
      #expect(rewriter.checkResizeSegmentsRequest(request, segments) == nil)
    }

    do {
      // The size of segments is one (flag = false).
      let segments = Segments()
      Self.initSegments("U+0020", "U+0020", segments)
      let request = ConversionRequestBuilder().setKey("U+0020").build()
      #expect(rewriter.checkResizeSegmentsRequest(request, segments) == nil)
      #expect(rewriter.rewrite(request, segments))
      #expect(Self.firstByte(segments.conversionSegment(0).candidate(0).value) == 0x20)
      #expect(segments.conversionSegment(0).candidate(0).convertedSegmentCount == 1)
    }

    do {
      // The size of segments is one (flag = true).
      let segments = Segments()
      Self.initSegments("U+0020", "U+0020", segments)
      var requestProto = Genmai_Commands_Request()
      requestProto.decoderExperimentParams.enableMultiSegmentCandidate = true
      let request = ConversionRequestBuilder().setRequest(requestProto).setKey("U+0020").build()
      #expect(rewriter.checkResizeSegmentsRequest(request, segments) == nil)
      #expect(rewriter.rewrite(request, segments))
      #expect(Self.firstByte(segments.conversionSegment(0).candidate(0).value) == 0x20)
      #expect(segments.conversionSegment(0).candidate(0).convertedSegmentCount == 1)
    }

    do {
      // History segment has to be ignored.
      let segments = Segments()
      Self.initSegments("U+0", "U+0", segments)
      Self.addSegment("02", "02", segments)
      Self.addSegment("0", "0", segments)
      segments.mutableSegment(0).setSegmentType(.history)
      let request = ConversionRequestBuilder().setKey("020").build()
      #expect(rewriter.checkResizeSegmentsRequest(request, segments) == nil)
      #expect(!rewriter.rewrite(request, segments))
    }

    do {
      // History segment has to be ignored.
      // In this case 1st segment is HISTORY
      // so this rewriting returns true.
      let segments = Segments()
      Self.initSegments("U+0020", "U+0020", segments)
      Self.addSegment("U+0020", "U+0020", segments)
      segments.setResized(true)
      segments.mutableSegment(0).setSegmentType(.history)
      let request = ConversionRequestBuilder().setKey("U+0020").build()
      #expect(rewriter.checkResizeSegmentsRequest(request, segments) == nil)
      #expect(rewriter.rewrite(request, segments))
      #expect(Self.firstByte(segments.conversionSegment(0).candidate(0).value) == 0x20)
    }
  }

  @Test func rewriteToUnicodeCharFormat() {
    let rewriter = UnicodeRewriter()
    let defaultRequest = Genmai_Commands_Request()
    let defaultConfig = Genmai_Config_Config()
    do {  // Typical case
      var composer = Composer(defaultRequest, defaultConfig)
      composer.setSourceText("A")
      let request = ConversionRequestBuilder().setComposer(composer).build()

      let segments = Segments()
      Self.addSegment("A", "A", segments)

      #expect(rewriter.rewrite(request, segments))
      #expect(Self.containCandidate(segments, "U+0041"))
    }

    do {  // If source_text is not set, this rewrite is not triggered.
      let composer = Composer(defaultRequest, defaultConfig)
      let request = ConversionRequestBuilder().setComposer(composer).build()

      let segments = Segments()
      Self.addSegment("A", "A", segments)

      #expect(!rewriter.rewrite(request, segments))
      #expect(!Self.containCandidate(segments, "U+0041"))
    }

    do {  // If source_text is not a single character, this rewrite is not
      // triggered.
      var composer = Composer(defaultRequest, defaultConfig)
      composer.setSourceText("AB")
      let request = ConversionRequestBuilder().setComposer(composer).build()

      let segments = Segments()
      Self.addSegment("AB", "AB", segments)

      #expect(!rewriter.rewrite(request, segments))
    }

    do {  // Multibyte character is also supported.
      var composer = Composer(defaultRequest, defaultConfig)
      composer.setSourceText("愛")
      let request = ConversionRequestBuilder().setComposer(composer).build()

      let segments = Segments()
      Self.addSegment("あい", "愛", segments)

      #expect(rewriter.rewrite(request, segments))
      #expect(Self.containCandidate(segments, "U+611B"))
    }
  }
}
