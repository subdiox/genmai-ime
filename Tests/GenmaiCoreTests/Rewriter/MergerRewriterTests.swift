// Port of mozc/src/rewriter/merger_rewriter_test.cc (3.35.6354).

import GenmaiProtocol
import Testing

@testable import GenmaiCore

@Suite struct MergerRewriterTests {
  private final class Buffer {
    var value = ""
  }

  // Tests in which order methods of each instance should be called
  // and what value should be returned.
  private final class TestRewriter: RewriterInterface {
    private let buffer: Buffer
    private let name: String
    private let returnValue: Bool
    private var capabilityValue: Rewriter.CapabilityType

    init(
      _ buffer: Buffer, _ name: String, _ returnValue: Bool,
      _ capability: Rewriter.CapabilityType = .conversion
    ) {
      self.buffer = buffer
      self.name = name
      self.returnValue = returnValue
      self.capabilityValue = capability
    }

    func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
      buffer.value += name + ".Rewrite();"
      return returnValue
    }

    func setCapability(_ capability: Rewriter.CapabilityType) { capabilityValue = capability }

    func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType { capabilityValue }

    func focus(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int) -> Bool {
      buffer.value += name + ".Focus();"
      return returnValue
    }

    func finish(_ request: ConversionRequest, _ segments: Segments) {
      buffer.value += name + ".Finish();"
    }

    func revert(_ segments: Segments) {
      buffer.value += name + ".Revert();"
    }

    func sync() -> Bool {
      buffer.value += name + ".Sync();"
      return returnValue
    }

    func reload() -> Bool {
      buffer.value += name + ".Reload();"
      return returnValue
    }

    func clear() { buffer.value += name + ".Clear();" }
  }

  private static func convReq(_ requestType: RequestType) -> ConversionRequest {
    ConversionRequestBuilder().setRequestType(requestType).build()
  }

  @Test func rewrite() {
    let callResult = Buffer()
    let merger = MergerRewriter()
    let segments = Segments()
    let request = ConversionRequest()

    merger.addRewriter(TestRewriter(callResult, "a", false))
    merger.addRewriter(TestRewriter(callResult, "b", false))
    merger.addRewriter(TestRewriter(callResult, "c", false))
    #expect(!merger.rewrite(request, segments))
    #expect(callResult.value == "a.Rewrite();b.Rewrite();c.Rewrite();")
    merger.addRewriter(TestRewriter(callResult, "d", true))
    callResult.value = ""
    #expect(merger.rewrite(request, segments))
    #expect(callResult.value == "a.Rewrite();b.Rewrite();c.Rewrite();d.Rewrite();")
  }

  @Test func rewriteSuggestion() {
    let callResult = Buffer()
    let merger = MergerRewriter()
    let segments = Segments()
    let request = Self.convReq(.suggestion)

    merger.addRewriter(TestRewriter(callResult, "a", true, .suggestion))

    #expect(segments.conversionSegmentsSize == 0)
    let segment = segments.pushBackSegment()
    #expect(segments.conversionSegmentsSize == 1)

    #expect(segment.candidatesSize == 0)
    _ = segment.pushBackCandidate()
    _ = segment.pushBackCandidate()
    _ = segment.pushBackCandidate()
    _ = segment.pushBackCandidate()
    #expect(segment.candidatesSize == 4)
    #expect(request.config().suggestionsSize == 3)

    #expect(merger.rewrite(request, segments))
    #expect(callResult.value == "a.Rewrite();")

    #expect(segment.candidatesSize == 3)
  }

  @Test func rewriteSuggestionWithMixedConversion() {
    let callResult = Buffer()
    let merger = MergerRewriter()
    let segments = Segments()

    // Initialize a ConversionRequest with mixed_conversion == true, which
    // should result that the merger rewriter does not trim exceeded suggestions.
    var commandsRequest = Genmai_Commands_Request()
    commandsRequest.mixedConversion = true
    let request = ConversionRequestBuilder().setRequest(commandsRequest)
      .setRequestType(.suggestion).build()
    #expect(request.request().mixedConversion)

    merger.addRewriter(TestRewriter(callResult, "a", true, .suggestion))

    #expect(segments.conversionSegmentsSize == 0)
    let segment = segments.pushBackSegment()
    #expect(segments.conversionSegmentsSize == 1)

    #expect(segment.candidatesSize == 0)
    _ = segment.pushBackCandidate()
    _ = segment.pushBackCandidate()
    _ = segment.pushBackCandidate()
    _ = segment.pushBackCandidate()
    #expect(segment.candidatesSize == 4)
    #expect(request.config().suggestionsSize == 3)

    #expect(merger.rewrite(request, segments))
    #expect(callResult.value == "a.Rewrite();")

    // If mixed_conversion is true, the suggestions are not deleted.
    #expect(segment.candidatesSize == 4)
  }

  @Test func rewriteCheckTest() {
    let callResult = Buffer()
    let merger = MergerRewriter()
    let segments = Segments()
    merger.addRewriter(TestRewriter(callResult, "a", false, .conversion))
    merger.addRewriter(TestRewriter(callResult, "b", false, .suggestion))
    merger.addRewriter(TestRewriter(callResult, "c", false, .prediction))
    merger.addRewriter(TestRewriter(callResult, "d", false, [.prediction, .conversion]))
    merger.addRewriter(TestRewriter(callResult, "e", false, .all))

    #expect(!merger.rewrite(Self.convReq(.conversion), segments))
    #expect(callResult.value == "a.Rewrite();d.Rewrite();e.Rewrite();")
    callResult.value = ""

    #expect(!merger.rewrite(Self.convReq(.prediction), segments))
    #expect(callResult.value == "c.Rewrite();d.Rewrite();e.Rewrite();")
    callResult.value = ""

    #expect(!merger.rewrite(Self.convReq(.suggestion), segments))
    #expect(callResult.value == "b.Rewrite();e.Rewrite();")
    callResult.value = ""

    #expect(!merger.rewrite(Self.convReq(.partialSuggestion), segments))
    #expect(callResult.value == "b.Rewrite();e.Rewrite();")
    callResult.value = ""

    #expect(!merger.rewrite(Self.convReq(.partialPrediction), segments))
    #expect(callResult.value == "c.Rewrite();d.Rewrite();e.Rewrite();")
    callResult.value = ""
  }

  @Test func focus() {
    let callResult = Buffer()
    let merger = MergerRewriter()
    merger.addRewriter(TestRewriter(callResult, "a", false))
    merger.addRewriter(TestRewriter(callResult, "b", false))
    merger.addRewriter(TestRewriter(callResult, "c", false))
    // C++ passes nullptr segments.
    #expect(!merger.focus(Segments(), 0, 0))
    #expect(callResult.value == "a.Focus();b.Focus();c.Focus();")
    merger.addRewriter(TestRewriter(callResult, "d", true))
    callResult.value = ""
    #expect(merger.focus(Segments(), 0, 0))
    #expect(callResult.value == "a.Focus();b.Focus();c.Focus();d.Focus();")
  }

  @Test func finish() {
    let callResult = Buffer()
    let request = ConversionRequest()
    let segments = Segments()
    let merger = MergerRewriter()
    merger.addRewriter(TestRewriter(callResult, "a", false))
    merger.addRewriter(TestRewriter(callResult, "b", false))
    merger.addRewriter(TestRewriter(callResult, "c", false))
    merger.finish(request, segments)
    #expect(callResult.value == "a.Finish();b.Finish();c.Finish();")
  }

  @Test func revert() {
    let callResult = Buffer()
    let segments = Segments()
    let merger = MergerRewriter()
    merger.addRewriter(TestRewriter(callResult, "a", false))
    merger.addRewriter(TestRewriter(callResult, "b", false))
    merger.addRewriter(TestRewriter(callResult, "c", false))
    merger.revert(segments)
    #expect(callResult.value == "a.Revert();b.Revert();c.Revert();")
  }

  @Test func sync() {
    let callResult = Buffer()
    let merger = MergerRewriter()
    merger.addRewriter(TestRewriter(callResult, "a", false))
    merger.addRewriter(TestRewriter(callResult, "b", false))
    merger.addRewriter(TestRewriter(callResult, "c", false))
    #expect(!merger.sync())
    #expect(callResult.value == "a.Sync();b.Sync();c.Sync();")
    merger.addRewriter(TestRewriter(callResult, "d", true))
    callResult.value = ""
    #expect(merger.sync())
    #expect(callResult.value == "a.Sync();b.Sync();c.Sync();d.Sync();")
  }

  @Test func reload() {
    let callResult = Buffer()
    let merger = MergerRewriter()
    merger.addRewriter(TestRewriter(callResult, "a", false))
    merger.addRewriter(TestRewriter(callResult, "b", false))
    merger.addRewriter(TestRewriter(callResult, "c", false))
    #expect(!merger.reload())
    #expect(callResult.value == "a.Reload();b.Reload();c.Reload();")
    merger.addRewriter(TestRewriter(callResult, "d", true))
    callResult.value = ""
    #expect(merger.reload())
    #expect(callResult.value == "a.Reload();b.Reload();c.Reload();d.Reload();")
  }

  @Test func clear() {
    let callResult = Buffer()
    let merger = MergerRewriter()
    merger.addRewriter(TestRewriter(callResult, "a", false))
    merger.addRewriter(TestRewriter(callResult, "b", false))
    merger.addRewriter(TestRewriter(callResult, "c", false))
    merger.clear()
    #expect(callResult.value == "a.Clear();b.Clear();c.Clear();")
    merger.addRewriter(TestRewriter(callResult, "d", true))
    callResult.value = ""
    merger.clear()
    #expect(callResult.value == "a.Clear();b.Clear();c.Clear();d.Clear();")
  }
}
