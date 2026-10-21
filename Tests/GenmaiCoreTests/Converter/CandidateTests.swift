// Port of mozc/src/converter/candidate_test.cc (3.35.6354).

import Testing
@testable import GenmaiCore

@Suite struct CandidateTests {
  @Test func isValid() {
    let c = Candidate()
    c.key = "key"
    c.value = "value"

    // Valid inner_segment_boundary.
    #expect(!buildInnerSegmentBoundary([(1, 3, 1, 3), (2, 2, 1, 1)], c.key, c.value).isEmpty)

    // Invalid inner_segment_boundary.
    #expect(buildInnerSegmentBoundary([(1, 1, 1, 1), (2, 2, 2, 2), (3, 3, 1, 1)], c.key, c.value).isEmpty)
  }

  @Test func functionalKey() {
    let candidate = Candidate()

    candidate.key = "testfoobar"
    candidate.contentKey = "test"
    #expect(candidate.functionalKey == "foobar")

    candidate.key = "testfoo"
    candidate.contentKey = "test"
    #expect(candidate.functionalKey == "foo")

    // This is unexpected key/context_key.
    // This method doesn't check the prefix part.
    candidate.key = "abcdefg"
    candidate.contentKey = "test"
    #expect(candidate.functionalKey == "efg")

    candidate.key = "test"
    candidate.contentKey = "test"
    #expect(candidate.functionalKey == "")

    candidate.key = "test"
    candidate.contentKey = "testfoobar"
    #expect(candidate.functionalKey == "")

    candidate.key = ""
    candidate.contentKey = ""
    #expect(candidate.functionalKey == "")
  }

  @Test func functionalValue() {
    let candidate = Candidate()

    candidate.value = "testfoobar"
    candidate.contentValue = "test"
    #expect(candidate.functionalValue == "foobar")

    candidate.value = "testfoo"
    candidate.contentValue = "test"
    #expect(candidate.functionalValue == "foo")

    // This is unexpected value/context_value.
    // This method doesn't check the prefix part.
    candidate.value = "abcdefg"
    candidate.contentValue = "test"
    #expect(candidate.functionalValue == "efg")

    candidate.value = "test"
    candidate.contentValue = "test"
    #expect(candidate.functionalValue == "")

    candidate.value = "test"
    candidate.contentValue = "testfoobar"
    #expect(candidate.functionalValue == "")

    candidate.value = ""
    candidate.contentValue = ""
    #expect(candidate.functionalValue == "")
  }

  @Test func innerSegmentIterator() {
    do {
      // For empty inner_segment_boundary, the initial state is done.
      let candidate = Candidate()
      candidate.key = "testfoobar"
      candidate.value = "redgreenblue"
      #expect(candidate.innerSegments().size == 1)
      for iter in candidate.innerSegments() {
        #expect(iter.key == candidate.key)
        #expect(iter.value == candidate.value)
        #expect(iter.contentKey == candidate.key)
        #expect(iter.contentValue == candidate.value)
      }
    }
    do {
      //           key: test | foobar
      //         value:  red | greenblue
      //   content key: test | foo
      // content value:  red | green
      let candidate = Candidate()
      candidate.key = "testfoobar"
      candidate.value = "redgreenblue"
      candidate.innerSegmentBoundary = buildInnerSegmentBoundary(
        [(4, 3, 4, 3), (6, 9, 3, 5)], candidate.key, candidate.value)
      let segs = Array(candidate.innerSegments())
      #expect(segs.map { String($0.key) } == ["test", "foobar"])
      #expect(segs.map { String($0.value) } == ["red", "greenblue"])
      #expect(segs.map { String($0.contentKey) } == ["test", "foo"])
      #expect(segs.map { String($0.contentValue) } == ["red", "green"])
      #expect(segs.map { String($0.functionalKey) } == ["", "bar"])
      #expect(segs.map { String($0.functionalValue) } == ["", "blue"])
    }
  }

  @Test func effectiveConvertedSegmentCount() {
    let candidate = Candidate()

    // By default, converted_segment_count is 1.
    #expect(candidate.convertedSegmentCount == 1)
    #expect(candidate.effectiveConvertedSegmentCount == 1)

    // Even if explicitly set to 0, effective_converted_segment_count clamps to 1.
    candidate.convertedSegmentCount = 0
    #expect(candidate.effectiveConvertedSegmentCount == 1)

    // Values >= 1 are preserved as-is.
    candidate.convertedSegmentCount = 2
    #expect(candidate.effectiveConvertedSegmentCount == 2)

    candidate.convertedSegmentCount = 10
    #expect(candidate.effectiveConvertedSegmentCount == 10)
  }

  // Swift-only: DebugString format.
  @Test func debugString() {
    let c = Candidate(key: "k", value: "v", cost: 10, wcost: 3, structureCost: 1, lid: 5, rid: 6)
    c.attributes = Attribute.bestCandidate | Attribute.userDictionary
    #expect(
      c.debugString()
        == "(key=k ckey=k val=v cval=v cost=10 scost=1 wcost=3 lid=5 rid=6 attributes=0000001000000001 consumed_key_size=0 converted_segment_count=1)\n"
    )
  }
}
