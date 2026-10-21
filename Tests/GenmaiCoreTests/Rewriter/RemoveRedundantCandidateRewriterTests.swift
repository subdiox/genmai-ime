// Port of mozc/src/rewriter/remove_redundant_candidate_rewriter_test.cc (3.35.6354).

import GenmaiProtocol
import Testing
@testable import GenmaiCore

@Suite struct RemoveRedundantCandidateRewriterTests {
  @Test func removeTest() {
    let rewriter = RemoveRedundantCandidateRewriter()
    let segments = Segments()
    let segment = segments.addSegment()
    segment.setKey("a")
    let candidate = segment.addCandidate()
    candidate.key = "a"
    candidate.value = "a"
    let defaultRequest = ConversionRequest()
    #expect(rewriter.rewrite(defaultRequest, segments))
    #expect(segment.candidatesSize == 0)
  }

  @Test func noRemoveTest() {
    let rewriter = RemoveRedundantCandidateRewriter()
    let segments = Segments()
    let segment = segments.addSegment()
    segment.setKey("a")
    let candidate = segment.addCandidate()
    candidate.key = "a"
    candidate.value = "aa"
    let defaultRequest = ConversionRequest()
    #expect(!rewriter.rewrite(defaultRequest, segments))
    #expect(segment.candidatesSize == 1)
  }

  @Test func capabilityTest() {
    let rewriter = RemoveRedundantCandidateRewriter()
    var request = Genmai_Commands_Request()
    do {
      let convreq = ConversionRequestBuilder().setRequest(request).build()
      #expect(rewriter.capability(convreq) == .notAvailable)
    }
    do {
      request.mixedConversion = true
      let convreq = ConversionRequestBuilder().setRequest(request).build()
      #expect(rewriter.capability(convreq) == .all)
    }
  }
}
