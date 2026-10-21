// Port of mozc/src/converter/segments_matchers_test.cc (3.35.6354).

import Testing
@testable import GenmaiCore

@Suite struct SegmentsMatchersTests {
  private func makeCandidate(_ key: String, _ value: String) -> Candidate {
    let cand = Candidate()
    cand.key = key
    cand.value = value
    return cand
  }

  private func makeSegment(_ key: String, _ values: [String]) -> Segment {
    let seg = Segment()
    seg.setKey(key)
    for val in values {
      let cand = seg.addCandidate()
      cand.key = key
      cand.value = val
    }
    return seg
  }

  @Test func equalsCandidateTest() {
    let x = makeCandidate("key_x", "value_x")
    let y = makeCandidate("key_y", "value_y")
    #expect(equalsCandidate(x, x) == nil)
    #expect(equalsCandidate(x, y) != nil)

    // Partially different.
    let z = makeCandidate("key_x", "value_z")
    #expect(equalsCandidate(x, z) != nil)
  }

  @Test func equalsSegmentTest() {
    let x = makeSegment("key", ["value"])
    let y = makeSegment("key", ["value1", "value2"])
    #expect(equalsSegment(x, x) == nil)
    #expect(equalsSegment(x, y) != nil)
  }

  @Test func candidatesAreArrayTest() {
    let x = makeSegment("key", ["value1", "value2"])
    #expect(candidatesAreArray(x, [valueIs("value1"), keyIs("key")]))
  }

  @Test func candidatesAreArrayWithCustomMatcher() {
    let x = makeSegment("key", ["value1", "value2"])
    #expect(candidatesAreArray(x, [keyAndValueAre("key", "value1"), keyAndValueAre("key", "value2")]))
  }

  @Test func hasSingleCandidateTest() {
    let x = makeSegment("key", ["value"])
    let y = makeSegment("key", ["value1", "value2"])
    #expect(hasSingleCandidate(x, valueIs("value")))
    #expect(!hasSingleCandidate(y, valueIs("value1")))
  }

  @Test func containsCandidateTest() {
    let x = makeSegment("key", ["value1", "value2", "value3"])
    #expect(containsCandidate(x, valueIs("value1")))
    #expect(containsCandidate(x, valueIs("value2")))
    #expect(containsCandidate(x, valueIs("value3")))
    #expect(!containsCandidate(x, valueIs("value4")))
  }

  @Test func equalsSegmentsTest() {
    let x = Segments()
    x.addSegment().assign(from: makeSegment("key1", ["value1", "value2"]))

    let y = Segments()
    y.addSegment().assign(from: makeSegment("key1", ["value1_1", "value1_2"]))
    y.addSegment().assign(from: makeSegment("key2", ["value2_1", "value2_2", "value2_3"]))

    #expect(equalsSegments(x, x) == nil)
    #expect(equalsSegments(x, y) != nil)
  }
}
