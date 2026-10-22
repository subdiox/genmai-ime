// Port of mozc/src/rewriter/rewriter_util_test.cc (3.35.6354).

import Testing

@testable import GenmaiCore

@Suite struct RewriterUtilTests {
  private static func addCandidate(_ key: String, _ value: String, _ segment: Segment) {
    let candidate = segment.pushBackCandidate()
    candidate.key = key
    candidate.value = value
  }

  @Test func calculateInsertPositionTestUserHistory() {
    let segment = Segment()
    for i in 0..<5 {
      Self.addCandidate("key\(i)", "value\(i)", segment)
    }
    for i in 0..<3 {
      segment.mutableCandidate(i).attributes = Attribute.userHistoryPrediction
    }
    #expect(RewriterUtil.calculateInsertPosition(segment, 0) == 3)
    #expect(RewriterUtil.calculateInsertPosition(segment, 1) == 4)
    #expect(RewriterUtil.calculateInsertPosition(segment, 2) == 5)
    #expect(RewriterUtil.calculateInsertPosition(segment, 3) == 5)
  }

  @Test func calculateInsertPositionTestNoUserHistory() {
    let segment = Segment()
    for i in 0..<5 {
      Self.addCandidate("key\(i)", "value\(i)", segment)
    }
    #expect(RewriterUtil.calculateInsertPosition(segment, 0) == 0)
    #expect(RewriterUtil.calculateInsertPosition(segment, 1) == 1)
    #expect(RewriterUtil.calculateInsertPosition(segment, 5) == 5)
    #expect(RewriterUtil.calculateInsertPosition(segment, 6) == 5)
  }
}
