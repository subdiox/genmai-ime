// Port of mozc/src/rewriter/fortune_rewriter_test.cc (3.35.6354).

import Testing
@testable import GenmaiCore

@Suite struct FortuneRewriterTests {
  private static func addSegment(_ key: String, _ value: String, _ segments: Segments) {
    segments.clear()
    let seg = segments.pushBackSegment()
    seg.setKey(key)
    let candidate = seg.addCandidate()
    candidate.value = key
    candidate.contentKey = key
    candidate.contentValue = value
  }

  private static func hasFortune(_ segments: Segments) -> Bool {
    precondition(segments.segmentsSize == 1)
    for i in 0..<segments.segment(0).candidatesSize {
      let candidate = segments.segment(0).candidate(i)
      if candidate.description == "今日の運勢" {
        // has valid value?
        if ["大吉", "吉", "中吉", "小吉", "末吉", "凶"].contains(candidate.value) {
          return true
        }
      }
    }
    return false
  }

  @Test func basicTest() {
    let fortuneRewriter = FortuneRewriter()
    let request = ConversionRequest()

    let segments = Segments()
    Self.addSegment("test", "test", segments)
    _ = fortuneRewriter.rewrite(request, segments)
    #expect(!Self.hasFortune(segments))

    Self.addSegment("おみくじ", "test", segments)
    _ = fortuneRewriter.rewrite(request, segments)
    #expect(Self.hasFortune(segments))
  }

  // Swift only: the injected level generator decides the fortune.
  @Test func injectedLevelGenerator() {
    let fortuneRewriter = FortuneRewriter(levelGenerator: { 0 })
    let segments = Segments()
    Self.addSegment("おみくじ", "test", segments)
    #expect(fortuneRewriter.rewrite(ConversionRequest(), segments))
    #expect(segments.segment(0).candidate(1).value == "大吉")
  }
}
