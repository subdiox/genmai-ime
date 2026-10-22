// Port of mozc/src/rewriter/user_dictionary_rewriter_test.cc (3.35.6354).

import GenmaiBase
import Testing

@testable import GenmaiCore

private func addCandidate(_ value: String, _ isUserDictionary: Bool, _ segments: Segments) {
  let seg: Segment
  if segments.segmentsSize == 0 {
    seg = segments.pushBackSegment()
    seg.setKey("test")
  } else {
    seg = segments.mutableSegment(0)
  }
  let candidate = seg.addCandidate()
  candidate.key = value
  candidate.contentKey = value
  candidate.value = value
  candidate.contentValue = value
  if isUserDictionary {
    candidate.attributes |= Attribute.userDictionary
  }
}

private func getCandidates(_ segments: Segments) -> String {
  precondition(segments.segmentsSize == 1)
  let seg = segments.segment(0)
  var results: [String] = []
  for i in 0..<seg.candidatesSize {
    results.append(seg.candidate(i).value)
  }
  return results.joined(separator: " ")
}

/// Builds segments from candidates "1".."5" with the given user dictionary flags.
private func makeSegments(_ flags: [Bool]) -> Segments {
  let segments = Segments()
  for (i, flag) in flags.enumerated() {
    addCandidate(String(i + 1), flag, segments)
  }
  return segments
}

@Suite struct UserDictionaryRewriterTests {
  @Test func rewriteTest() {
    SystemUtil.withTempUserProfile { _ in
      let rewriter = UserDictionaryRewriter()
      let request = ConversionRequest()

      do {
        let segments = makeSegments([false, false, false, false, false])
        #expect(!rewriter.rewrite(request, segments))
        #expect(getCandidates(segments) == "1 2 3 4 5")
      }

      do {
        let segments = makeSegments([true, false, false, false, false])
        #expect(!rewriter.rewrite(request, segments))
        #expect(getCandidates(segments) == "1 2 3 4 5")
      }

      do {
        let segments = makeSegments([false, true, false, false, false])
        #expect(!rewriter.rewrite(request, segments))
        #expect(getCandidates(segments) == "1 2 3 4 5")
      }

      do {
        let segments = makeSegments([false, false, true, false, false])
        #expect(rewriter.rewrite(request, segments))
        #expect(getCandidates(segments) == "1 3 2 4 5")
      }
      do {
        let segments = makeSegments([false, false, true, true, false])
        #expect(rewriter.rewrite(request, segments))
        #expect(getCandidates(segments) == "1 3 4 2 5")
      }
      do {
        let segments = makeSegments([false, true, true, true, false])
        #expect(!rewriter.rewrite(request, segments))
        #expect(getCandidates(segments) == "1 2 3 4 5")
      }
      do {
        let segments = makeSegments([true, true, true, true, true])
        #expect(!rewriter.rewrite(request, segments))
        #expect(getCandidates(segments) == "1 2 3 4 5")
      }
      do {
        let segments = makeSegments([true, false, false, true, false])
        #expect(rewriter.rewrite(request, segments))
        #expect(getCandidates(segments) == "1 4 2 3 5")
      }
    }
  }
}
