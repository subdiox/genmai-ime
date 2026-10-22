// Port of mozc/src/rewriter/zipcode_rewriter_test.cc (3.35.6354).

import GenmaiProtocol
import Testing

@testable import GenmaiCore

@Suite struct ZipcodeRewriterTests {
  private enum SegmentType {
    case zipcode
    case nonZipcode
  }

  private static func addSegment(
    _ key: String, _ value: String, _ type: SegmentType, _ posMatcher: PosMatcher,
    _ segments: Segments
  ) {
    segments.clear()
    let seg = segments.pushBackSegment()
    seg.setKey(key)
    let candidate = seg.addCandidate()
    candidate.value = key
    candidate.contentKey = key
    candidate.contentValue = value

    if type == .zipcode {
      candidate.lid = posMatcher.getZipcodeId()
      candidate.rid = posMatcher.getZipcodeId()
    }
  }

  private static func hasZipcodeAndAddress(_ segments: Segments, _ expected: String) -> Bool {
    precondition(segments.segmentsSize == 1)
    for i in 0..<segments.segment(0).candidatesSize {
      let candidate = segments.segment(0).candidate(i)
      if candidate.description == "郵便番号と住所" && candidate.contentValue.bytesEqual(expected) {
        return true
      }
    }
    return false
  }

  @Test(.enabled(if: MockDataManager.defaultDataPath != nil, "mock_genmai.data is missing"))
  func basicTest() throws {
    let posMatcher = PosMatcher(try MockDataManager.create().getPosMatcherData())
    let zipcodeRewriter = ZipcodeRewriter(posMatcher)

    let kZipcode = "107-0052"
    let kAddress = "東京都港区赤坂"
    var config = Genmai_Config_Config()

    do {
      let request = ConversionRequestBuilder().setConfig(config).build()
      let segments = Segments()
      Self.addSegment("test", "test", .nonZipcode, posMatcher, segments)
      #expect(!zipcodeRewriter.rewrite(request, segments))
    }

    do {
      config.spaceCharacterForm = .fundamentalHalfWidth
      let request = ConversionRequestBuilder().setConfig(config).build()
      let segments = Segments()
      Self.addSegment(kZipcode, kAddress, .zipcode, posMatcher, segments)
      _ = zipcodeRewriter.rewrite(request, segments)
      #expect(Self.hasZipcodeAndAddress(segments, kZipcode + " " + kAddress))
    }

    do {
      config.spaceCharacterForm = .fundamentalFullWidth
      let request = ConversionRequestBuilder().setConfig(config).build()
      let segments = Segments()
      Self.addSegment(kZipcode, kAddress, .zipcode, posMatcher, segments)
      _ = zipcodeRewriter.rewrite(request, segments)
      // full-width space
      #expect(Self.hasZipcodeAndAddress(segments, kZipcode + "　" + kAddress))
    }
  }
}
