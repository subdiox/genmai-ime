// Port of mozc/src/rewriter/emoticon_rewriter_test.cc (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import Testing
@testable import GenmaiCore

@Suite(.enabled(if: R2RewriterTestSupport.hasMockData, R2RewriterTestSupport.mockDataMissing))
struct EmoticonRewriterTests {
  private static func initSegment(_ key: String, _ value: String, _ segments: Segments) {
    segments.clear()
    let seg = segments.pushBackSegment()
    seg.setKey(key)
    let candidate = seg.addCandidate()
    candidate.value = key
    candidate.contentKey = key
    candidate.contentValue = value

    // Fills other default candidates.
    for i in 0..<100 {
      let candidate = seg.addCandidate()
      candidate.value = "value\(i)"
      candidate.key = "key\(i)"
    }
  }

  private static func getEmoticonIndex(_ segments: Segments) -> Int {
    precondition(segments.segmentsSize == 1)
    for i in 0..<segments.segment(0).candidatesSize {
      let candidate = segments.segment(0).candidate(i)
      if candidate.description.hasBytePrefix("顔文字") {
        return i
      }
    }
    return -1
  }

  private static func hasEmoticon(_ segments: Segments) -> Bool {
    getEmoticonIndex(segments) >= 0
  }

  private func makeRewriter() throws -> EmoticonRewriter {
    EmoticonRewriter(try R2RewriterTestSupport.mockDataManager().getEmoticonRewriterData())
  }

  @Test func basicTest() throws {
    let emoticonRewriter = try makeRewriter()

    var config = ConfigHandler.defaultConfig()
    do {
      config.useEmoticonConversion = true
      let request = ConversionRequestBuilder().setConfig(config).build()

      let segments = Segments()
      Self.initSegment("test", "test", segments)
      _ = emoticonRewriter.rewrite(request, segments)
      #expect(!Self.hasEmoticon(segments))

      Self.initSegment("かお", "test", segments)
      _ = emoticonRewriter.rewrite(request, segments)
      #expect(Self.hasEmoticon(segments))
      #expect(Self.getEmoticonIndex(segments) > 6)

      Self.initSegment("かおもじ", "test", segments)
      _ = emoticonRewriter.rewrite(request, segments)
      #expect(Self.hasEmoticon(segments))
      #expect(Self.getEmoticonIndex(segments) > 6)

      Self.initSegment("にこにこ", "test", segments)
      _ = emoticonRewriter.rewrite(request, segments)
      #expect(Self.hasEmoticon(segments))
      #expect(Self.getEmoticonIndex(segments) <= 6)

      Self.initSegment("ふくわらい", "test", segments)
      _ = emoticonRewriter.rewrite(request, segments)
      #expect(Self.hasEmoticon(segments))
      #expect(Self.getEmoticonIndex(segments) <= 6)
    }

    do {
      config.useEmoticonConversion = false
      let request = ConversionRequestBuilder().setConfig(config).build()

      let segments = Segments()
      for key in ["test", "かお", "かおもじ", "にこにこ", "ふくわらい"] {
        Self.initSegment(key, "test", segments)
        _ = emoticonRewriter.rewrite(request, segments)
        #expect(!Self.hasEmoticon(segments), "\(key)")
      }
    }
  }

  @Test func randomTest() throws {
    let emoticonRewriter = try makeRewriter()

    var config = ConfigHandler.defaultConfig()
    config.useEmoticonConversion = true
    let request = ConversionRequestBuilder().setConfig(config).build()

    var variants = Set<[UInt8]>()
    for _ in 0..<100 {
      let segments = Segments()
      Self.initSegment("ふくわらい", "test", segments)
      _ = emoticonRewriter.rewrite(request, segments)
      #expect(Self.hasEmoticon(segments))
      // random candidate is inserted at 4-th position.
      variants.insert(Array(segments.segment(0).candidate(4).value.utf8))
    }
    #expect(variants.count > 1)
  }

  @Test func mobileEnvironmentTest() throws {
    let emoticonRewriter = try makeRewriter()
    var request = Genmai_Commands_Request()
    do {
      request.mixedConversion = true
      let convreq = ConversionRequestBuilder().setRequest(request).build()
      #expect(emoticonRewriter.capability(convreq) == .all)
    }
    do {
      request.mixedConversion = false
      let convreq = ConversionRequestBuilder().setRequest(request).build()
      #expect(emoticonRewriter.capability(convreq) == .conversion)
    }
  }
}
