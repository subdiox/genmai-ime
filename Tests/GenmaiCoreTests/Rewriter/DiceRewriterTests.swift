// Port of mozc/src/rewriter/dice_rewriter_test.cc (3.35.6354).

import Testing

@testable import GenmaiCore

@Suite struct DiceRewriterTests {
  private static let kDescription = "出た目の数"
  private static let kKey = "さいころ"
  private static let kPageSize = 9

  private static func addCandidate(_ key: String, _ value: String, _ segment: Segment) {
    let candidate = segment.addCandidate()
    candidate.value = value
    candidate.contentValue = value
    candidate.contentKey = key
  }

  private static func addSegment(_ key: String, _ segments: Segments) {
    let segment = segments.pushBackSegment()
    segment.setKey(key)
  }

  private static func makeSegments(
    _ segments: Segments, _ key: String, _ numSegment: Int, _ numDummyCandidate: Int
  ) {
    segments.clear()
    addSegment(key, segments)
    for _ in 1..<max(1, numSegment) {
      addSegment(key, segments)
    }
    let segment = segments.mutableSegment(0)
    for _ in 0..<numDummyCandidate {
      addCandidate("test_key", "test_value", segment)
    }
  }

  private static func countDiceNumber(_ segment: Segment) -> Int {
    var count = 0
    for i in 0..<segment.candidatesSize where segment.candidate(i).description == kDescription {
      count += 1
    }
    return count
  }

  private static func hasValidValue(_ candidate: Candidate) -> Bool {
    ["1", "2", "3", "4", "5", "6"].contains(candidate.value)
  }

  private static func getDiceNumberIndex(_ segment: Segment) -> Int {
    for i in 0..<segment.candidatesSize where segment.candidate(i).description == kDescription {
      return i
    }
    return segment.candidatesSize
  }

  @Test func insertTest() {
    let diceRewriter = DiceRewriter()
    let segments = Segments()
    let request = ConversionRequest()

    // Check a dice number index with some mock candidates.
    for candidatesSize in 1...Self.kPageSize {
      Self.makeSegments(segments, Self.kKey, 1, candidatesSize)
      #expect(diceRewriter.rewrite(request, segments))
      #expect(segments.segmentsSize == 1)
      let segment = segments.conversionSegment(0)
      #expect(Self.countDiceNumber(segment) == 1)

      let diceNumberIndex = Self.getDiceNumberIndex(segment)
      #expect(1 <= diceNumberIndex)
      #expect(Self.kPageSize > diceNumberIndex)

      #expect(Self.hasValidValue(segment.candidate(diceNumberIndex)))
    }
  }

  // Test cases for no insertions.
  @Test func ignoringTest() {
    let diceRewriter = DiceRewriter()
    let segments = Segments()
    let request = ConversionRequest()

    // Candidates size is 0.
    Self.makeSegments(segments, Self.kKey, 1, 0)
    #expect(!diceRewriter.rewrite(request, segments))

    // Segments key is not matched.
    Self.makeSegments(segments, "dice", 1, 1)
    #expect(!diceRewriter.rewrite(request, segments))

    // Segments size is more than 1.
    Self.makeSegments(segments, Self.kKey, 2, 1)
    #expect(!diceRewriter.rewrite(request, segments))
  }

  // Swift only: the injected face generator decides the value.
  @Test func injectedFaceGenerator() {
    let diceRewriter = DiceRewriter(faceGenerator: { 4 })
    let segments = Segments()
    Self.makeSegments(segments, Self.kKey, 1, 3)
    #expect(diceRewriter.rewrite(ConversionRequest(), segments))
    let segment = segments.conversionSegment(0)
    #expect(Self.getDiceNumberIndex(segment) == 3)
    #expect(segment.candidate(3).value == "4")
  }
}
