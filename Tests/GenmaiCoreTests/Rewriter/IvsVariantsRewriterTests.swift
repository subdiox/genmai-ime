// Port of mozc/src/rewriter/ivs_variants_rewriter_test.cc (3.35.6354).

import GenmaiBase
import Testing

@testable import GenmaiCore

@Suite struct IvsVariantsRewriterTests {
  @Test func expandIvsVariantsWithSegment_singleCandidate() {
    let rewriter = IvsVariantsRewriter()
    let segments = Segments()
    let request = ConversionRequest()

    // value == content_value
    do {
      let seg = segments.pushBackSegment()
      let candidate = seg.addCandidate()
      candidate.key = "かつらぎし"
      candidate.contentKey = "かつらぎし"
      candidate.value = "葛城市"
      candidate.contentValue = "葛城市"

      #expect(rewriter.rewrite(request, segments))
      #expect(seg.candidatesSize == 2)
      // The original candidate comes first.
      #expect(seg.candidate(0).key.bytesEqual("かつらぎし"))
      #expect(seg.candidate(0).contentKey.bytesEqual("かつらぎし"))
      #expect(seg.candidate(0).value.bytesEqual("葛城市"))
      #expect(seg.candidate(0).contentValue.bytesEqual("葛城市"))
      // Then an IVS candidate comes next.
      #expect(seg.candidate(1).key.bytesEqual("かつらぎし"))
      #expect(seg.candidate(1).contentKey.bytesEqual("かつらぎし"))
      #expect(seg.candidate(1).value.bytesEqual("葛\u{E0100}城市"))
      #expect(seg.candidate(1).contentValue.bytesEqual("葛\u{E0100}城市"))
      #expect(seg.candidate(1).description.bytesEqual("環境依存(IVS) 正式字体"))
    }
    // value != content_value
    // No deciated description.
    do {
      let seg = segments.pushBackSegment()
      let candidate = seg.addCandidate()
      candidate.key = "ぎおんの"
      candidate.contentKey = "ぎおん"
      candidate.value = "祇園の"
      candidate.contentValue = "祇園"

      #expect(rewriter.rewrite(request, segments))
      #expect(seg.candidatesSize == 2)
      // The original candidate comes first.
      #expect(seg.candidate(0).key.bytesEqual("ぎおんの"))
      #expect(seg.candidate(0).contentKey.bytesEqual("ぎおん"))
      #expect(seg.candidate(0).value.bytesEqual("祇園の"))
      #expect(seg.candidate(0).contentValue.bytesEqual("祇園"))
      // Then an IVS candidate comes next.
      #expect(seg.candidate(1).key.bytesEqual("ぎおんの"))
      #expect(seg.candidate(1).contentKey.bytesEqual("ぎおん"))
      #expect(seg.candidate(1).value.bytesEqual("祇\u{E0100}園の"))
      #expect(seg.candidate(1).contentValue.bytesEqual("祇\u{E0100}園"))
      #expect(seg.candidate(1).description.bytesEqual("環境依存(IVS) 礻"))
    }
  }

  @Test func expandIvsVariantsWithSegment_noMatching() {
    let rewriter = IvsVariantsRewriter()
    let segments = Segments()
    let request = ConversionRequest()

    // content_key doesn't match.
    do {
      let seg = segments.pushBackSegment()
      let candidate = seg.addCandidate()
      candidate.key = "かつらぎし"
      candidate.contentKey = "かつらぎし？"
      candidate.value = "葛城市"
      candidate.contentValue = "葛城市"

      #expect(!rewriter.rewrite(request, segments))
    }
    // content_value doesn't match.
    do {
      let seg = segments.pushBackSegment()
      let candidate = seg.addCandidate()
      candidate.key = "かつらぎし"
      candidate.contentKey = "かつらぎし"
      candidate.value = "葛城市"
      candidate.contentValue = "葛城市？"

      #expect(!rewriter.rewrite(request, segments))
    }
    // content_key/value needs exact match.
    do {
      let seg = segments.pushBackSegment()
      let candidate = seg.addCandidate()
      candidate.key = "かつらぎしりつとしょかん"
      candidate.contentKey = "かつらぎしりつとしょかん"
      candidate.value = "葛城市立図書館"
      candidate.contentValue = "葛城市市立図書館"

      #expect(!rewriter.rewrite(request, segments))
    }
  }

  @Test func expandIvsVariantsWithSegment_multipleCandidate() {
    let rewriter = IvsVariantsRewriter()
    let segments = Segments()
    let request = ConversionRequest()
    let seg = segments.pushBackSegment()

    func add(_ key: String, _ value: String) {
      let candidate = seg.addCandidate()
      candidate.key = key
      candidate.contentKey = key
      candidate.value = value
      candidate.contentValue = value
    }
    // IVS 1
    add("かつらぎし", "葛城市")
    // Non-IVS 1
    add("いか", "くコ:彡")
    // IVS 2
    add("ぎおん", "祇園")
    // Non-IVS 2
    add("たこ", "Ｃ:。ミ")

    #expect(rewriter.rewrite(request, segments))
    #expect(seg.candidatesSize == 6)
    #expect(seg.candidate(0).value.bytesEqual("葛城市"))
    #expect(seg.candidate(1).value.bytesEqual("葛\u{E0100}城市"))
    #expect(seg.candidate(2).value.bytesEqual("くコ:彡"))
    #expect(seg.candidate(3).value.bytesEqual("祇園"))
    #expect(seg.candidate(4).value.bytesEqual("祇\u{E0100}園"))
    #expect(seg.candidate(5).value.bytesEqual("Ｃ:。ミ"))
  }
}
