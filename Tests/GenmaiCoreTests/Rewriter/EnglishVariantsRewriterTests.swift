// Port of mozc/src/rewriter/english_variants_rewriter_test.cc (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import Testing
@testable import GenmaiCore

@Suite(.enabled(if: R2RewriterTestSupport.hasMockData, R2RewriterTestSupport.mockDataMissing))
struct EnglishVariantsRewriterTests {
  let posMatcher: PosMatcher
  let rewriter: EnglishVariantsRewriter

  init() throws {
    posMatcher = try R2RewriterTestSupport.mockPosMatcher()
    rewriter = EnglishVariantsRewriter(posMatcher)
  }

  private func addCandidate(
    _ seg: Segment, key: String, value: String, contentKey: String? = nil,
    contentValue: String? = nil
  ) -> Candidate {
    let c = seg.addCandidate()
    c.contentKey = contentKey ?? key
    c.key = key
    c.value = value
    c.contentValue = contentValue ?? value
    c.attributes &= ~Attribute.noVariantsExpansion
    return c
  }

  private func spaceInsertionRequest() -> ConversionRequest {
    var request = Genmai_Commands_Request()
    request.decoderExperimentParams.englishVariationSpaceInsertionMode = 1
    return ConversionRequestBuilder().setRequest(request).build()
  }

  @Test func expandEnglishVariants() {
    var variants: [String] = []

    #expect(rewriter.expandEnglishVariants("foo", &variants))
    #expect(variants == ["Foo", "FOO"])

    #expect(rewriter.expandEnglishVariants("Bar", &variants))
    #expect(variants == ["bar", "BAR"])

    #expect(rewriter.expandEnglishVariants("HOGE", &variants))
    #expect(variants == ["hoge", "Hoge"])

    #expect(!rewriter.expandEnglishVariants("Foo Bar", &variants))

    #expect(rewriter.expandEnglishVariants("iPhone", &variants))
    #expect(variants == ["iphone"])

    #expect(rewriter.expandEnglishVariants("MeCab", &variants))
    #expect(variants == ["mecab"])

    #expect(!rewriter.expandEnglishVariants("グーグル", &variants))
  }

  @Test func expandSpacePrefixedVariants() {
    do {
      var variants: [String] = []

      #expect(rewriter.expandSpacePrefixedVariants("Watch", &variants))
      #expect(variants == [" Watch"])

      variants.removeAll()
      #expect(!rewriter.expandSpacePrefixedVariants(" Watch", &variants))
      #expect(variants.isEmpty)

      variants.removeAll()
      #expect(!rewriter.expandSpacePrefixedVariants("", &variants))
      #expect(variants.isEmpty)
    }
    do {
      var variants = ["PIXEL", "pixel"]
      #expect(rewriter.expandSpacePrefixedVariants("Pixel", &variants))
      #expect(variants == [" Pixel", "PIXEL", " PIXEL", "pixel", " pixel"])
    }
  }

  @Test func rewriteTest() {
    // T13N
    do {
      let segments = Segments()
      let request = ConversionRequest()
      let seg = segments.pushBackSegment()
      _ = addCandidate(seg, key: "ぐーぐる", value: "Google")

      #expect(seg.candidatesSize == 1)
      #expect(seg.candidate(0).value == "Google")
      #expect(seg.candidate(0).contentValue == "Google")
      #expect(rewriter.rewrite(request, segments))
      #expect(seg.candidatesSize == 3)
      #expect(seg.candidate(0).value == "Google")
      #expect(seg.candidate(0).contentValue == "Google")
      #expect(seg.candidate(1).value == "google")
      #expect(seg.candidate(1).contentValue == "google")
      #expect(seg.candidate(2).value == "GOOGLE")
      #expect(seg.candidate(2).contentValue == "GOOGLE")
    }

    // 'Google Japan'
    do {
      let segments = Segments()
      let conversionRequest = spaceInsertionRequest()
      let seg1 = segments.pushBackSegment()
      let seg2 = segments.pushBackSegment()
      _ = addCandidate(seg1, key: "ぐーぐる", value: "Google")
      _ = addCandidate(seg2, key: "じゃぱん", value: "Japan")
      #expect(seg1.candidatesSize == 1)
      #expect(seg2.candidatesSize == 1)
      #expect(rewriter.rewrite(conversionRequest, segments))
      #expect(seg1.candidatesSize == 3)
      #expect(seg1.candidates.map(\.value) == ["Google", "google", "GOOGLE"])
      #expect(seg1.candidates.map(\.contentValue) == ["Google", "google", "GOOGLE"])
      #expect(seg2.candidatesSize == 6)
      let expected = ["Japan", " Japan", "japan", " japan", "JAPAN", " JAPAN"]
      #expect(seg2.candidates.map(\.value) == expected)
      #expect(seg2.candidates.map(\.contentValue) == expected)
    }

    // '<NO CANDIDATE> Japan'
    do {
      let segments = Segments()
      let conversionRequest = spaceInsertionRequest()
      let seg1 = segments.pushBackSegment()
      let seg2 = segments.pushBackSegment()
      // When seg1 has no candidates, seg2 will not be expanded.
      _ = addCandidate(seg2, key: "じゃぱん", value: "Japan")
      #expect(seg1.candidatesSize == 0)
      #expect(seg2.candidatesSize == 1)
      #expect(rewriter.rewrite(conversionRequest, segments))
      #expect(seg1.candidatesSize == 0)
      #expect(seg2.candidatesSize == 3)
      #expect(seg2.candidates.map(\.value) == ["Japan", "japan", "JAPAN"])
      #expect(seg2.candidates.map(\.contentValue) == ["Japan", "japan", "JAPAN"])
    }

    // 'ぐーぐるJapan'
    do {
      let segments = Segments()
      let conversionRequest = spaceInsertionRequest()
      let seg1 = segments.pushBackSegment()
      let seg2 = segments.pushBackSegment()
      // When seg1 is not an English word, seg2 will not be expanded.
      _ = addCandidate(seg1, key: "ぐーぐる", value: "ぐーぐる")
      _ = addCandidate(seg2, key: "じゃぱん", value: "Japan")
      #expect(seg1.candidatesSize == 1)
      #expect(seg1.candidate(0).value == "ぐーぐる")
      #expect(rewriter.rewrite(conversionRequest, segments))
      #expect(seg2.candidatesSize == 3)
      #expect(seg2.candidates.map(\.value) == ["Japan", "japan", "JAPAN"])
      #expect(seg2.candidates.map(\.contentValue) == ["Japan", "japan", "JAPAN"])
    }

    do {
      let segments = Segments()
      let request = ConversionRequest()
      let seg = segments.pushBackSegment()
      seg.clear()

      for i in 0..<10 {
        let candidate1 = seg.addCandidate()
        candidate1.value = String(i)
        candidate1.contentValue = String(i)
        _ = addCandidate(seg, key: "ぐーぐる", value: "Google")
      }

      #expect(rewriter.rewrite(request, segments))
      #expect(seg.candidatesSize == 40)

      for i in 0..<10 {
        #expect(seg.candidate(4 * i).value == String(i))
        #expect(seg.candidate(4 * i).contentValue == String(i))
        #expect(seg.candidate(4 * i + 1).value == "Google")
        #expect(seg.candidate(4 * i + 1).contentValue == "Google")
        #expect(seg.candidate(4 * i + 2).value == "google")
        #expect(seg.candidate(4 * i + 2).contentValue == "google")
        #expect(seg.candidate(4 * i + 3).value == "GOOGLE")
        #expect(seg.candidate(4 * i + 3).contentValue == "GOOGLE")
      }
    }
  }

  @Test func regression3242753() {
    let segments = Segments()
    let request = ConversionRequest()
    let seg = segments.pushBackSegment()

    // Multi-word English candidate should not be expanded.
    // NO_VARIANTS_EXPANSION is passed to the candidate only.
    _ = addCandidate(seg, key: "まいけるじゃくそん", value: "Michael Jackson")

    #expect(seg.candidatesSize == 1)
    #expect(rewriter.rewrite(request, segments))
    #expect(seg.candidatesSize == 1)
    #expect(seg.candidate(0).value == "Michael Jackson")
    #expect(seg.candidate(0).contentValue == "Michael Jackson")
    #expect((seg.candidate(0).attributes & Attribute.noVariantsExpansion) != 0)
  }

  @Test func regression5137299() {
    let segments = Segments()
    let request = ConversionRequest()
    let seg = segments.pushBackSegment()

    do {
      let candidate = addCandidate(seg, key: "ぐーぐる", value: "Google")
      candidate.attributes |= Attribute.noVariantsExpansion
      #expect(seg.candidatesSize == 1)
      #expect(!rewriter.rewrite(request, segments))
      #expect(seg.candidatesSize == 1)
    }

    do {
      seg.clearCandidates()
      let candidate = addCandidate(seg, key: "ぐーぐる", value: "Google")
      candidate.attributes |= Attribute.noVariantsExpansion
      candidate.attributes |= Attribute.userDictionary

      #expect(seg.candidatesSize == 1)
      #expect(rewriter.rewrite(request, segments))
      #expect(seg.candidatesSize == 3)
      #expect(seg.candidates.map(\.value) == ["Google", "google", "GOOGLE"])
      #expect(seg.candidates.map(\.contentValue) == ["Google", "google", "GOOGLE"])
    }
  }

  private func addGoogleTrio(_ seg: Segment) {
    for value in ["GOOGLE", "グーグル", "google"] {
      let candidate = seg.addCandidate()
      candidate.contentKey = "ぐーぐる"
      candidate.key = "ぐーぐる"
      candidate.value = value
      candidate.contentValue = value
    }
  }

  @Test func doNotAddDuplicatedCandidates() {
    let segments = Segments()
    let request = ConversionRequest()
    let seg = segments.pushBackSegment()
    addGoogleTrio(seg)

    #expect(seg.candidatesSize == 3)
    #expect(rewriter.rewrite(request, segments))
    #expect(seg.candidatesSize == 4)  // Kana, lower, upper, capitalized
  }

  @Test func keepRank() throws {
    let segments = Segments()
    let request = ConversionRequest()
    let seg = segments.pushBackSegment()
    addGoogleTrio(seg)

    #expect(seg.candidatesSize == 3)
    #expect(rewriter.rewrite(request, segments))

    let upperRank = try #require(R2RewriterTestSupport.rankOfValue(seg, "GOOGLE"))
    let lowerRank = try #require(R2RewriterTestSupport.rankOfValue(seg, "google"))
    let capitalizedRank = try #require(R2RewriterTestSupport.rankOfValue(seg, "Google"))
    let kanaRank = try #require(R2RewriterTestSupport.rankOfValue(seg, "グーグル"))
    #expect(upperRank < lowerRank)
    #expect(kanaRank < lowerRank)
    #expect(lowerRank < capitalizedRank)
  }

  @Test func expandEnglishEntry() {
    // Fix variants
    let segments = Segments()
    let request = ConversionRequest()
    let seg = segments.pushBackSegment()
    _ = addCandidate(seg, key: "google", value: "Google")

    #expect(seg.candidatesSize == 1)
    #expect(rewriter.rewrite(request, segments))
    #expect(seg.candidatesSize == 1)
    #expect(seg.candidate(0).value == "Google")
    #expect(seg.candidate(0).contentValue == "Google")
    #expect((seg.candidate(0).attributes & Attribute.noVariantsExpansion) != 0)
  }

  @Test func doNotExpandUpperCaseProperNouns() {
    let segments = Segments()
    let request = ConversionRequest()
    let seg = segments.pushBackSegment()
    let candidate = addCandidate(seg, key: "なさ", value: "NASA")
    candidate.lid = posMatcher.getUniqueNounId()
    candidate.rid = posMatcher.getUniqueNounId()

    #expect(rewriter.rewrite(request, segments))
    #expect(seg.candidatesSize == 1)
    #expect(seg.candidate(0).value == "NASA")
    #expect((seg.candidate(0).attributes & Attribute.noVariantsExpansion) != 0)
  }

  @Test func properNouns() throws {
    let segments = Segments()
    let request = ConversionRequest()
    let seg = segments.pushBackSegment()
    let candidate = addCandidate(seg, key: "ぐーぐる", value: "google")
    candidate.lid = posMatcher.getUniqueNounId()
    candidate.rid = posMatcher.getUniqueNounId()

    #expect(rewriter.rewrite(request, segments))
    try #require(seg.candidatesSize == 3)
    #expect(seg.candidate(0).value == "google")
    #expect(seg.candidate(1).value == "Google")
    #expect(seg.candidate(2).value == "GOOGLE")
    for i in 0..<3 {
      #expect((seg.candidate(i).attributes & Attribute.noVariantsExpansion) != 0)
    }
  }

  @Test func fillConsumedKeySize() {
    let segments = Segments()
    let request = ConversionRequest()
    let seg = segments.pushBackSegment()

    let kKey = "なさ"
    do {
      let candidate = seg.addCandidate()
      candidate.contentKey = kKey
      candidate.key = kKey
      candidate.contentValue = "nasa"
      candidate.value = "nasa"
      candidate.consumedKeySize = UInt32(kKey.utf8.count)
      candidate.attributes |= Attribute.partiallyKeyConsumed
    }

    #expect(rewriter.rewrite(request, segments))
    #expect(seg.candidatesSize > 1)
    for c in seg.candidates {
      #expect((c.attributes & Attribute.partiallyKeyConsumed) != 0)
      #expect(c.consumedKeySize == UInt32(kKey.utf8.count))
    }
  }

  @Test func mobileEnvironmentTest() {
    var request = Genmai_Commands_Request()
    do {
      request.mixedConversion = true
      let convreq = ConversionRequestBuilder().setRequest(request).build()
      #expect(rewriter.capability(convreq) == .all)
    }
    do {
      request.mixedConversion = false
      let convreq = ConversionRequestBuilder().setRequest(request).build()
      #expect(rewriter.capability(convreq) == .conversion)
    }
  }
}
