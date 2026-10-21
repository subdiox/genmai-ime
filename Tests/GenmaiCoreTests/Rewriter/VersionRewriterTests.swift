// Port of mozc/src/rewriter/version_rewriter_test.cc (3.35.6354).

import GenmaiProtocol
import Testing
@testable import GenmaiCore

@Suite struct VersionRewriterTests {
  private static let kDummyDataVersion = "dataversion"

  private static func addSegment(_ key: String, _ value: String, _ segments: Segments) {
    let segment = segments.pushBackSegment()
    segment.setKey(key)
    addCandidate(key, value, segment)
  }

  private static func addCandidate(_ key: String, _ value: String, _ segment: Segment) {
    let candidate = segment.addCandidate()
    candidate.value = value
    candidate.contentValue = value
    candidate.contentKey = key
  }

  private static func findCandidateWithPrefix(_ prefix: String, _ segments: Segments) -> Bool {
    for segment in segments.all {
      for j in 0..<segment.candidatesSize where segment.candidate(j).value.hasBytePrefix(prefix) {
        return true
      }
    }
    return false
  }

  @Test func capabilityTest() {
    // Default request.
    let request = ConversionRequest()
    let rewriter = VersionRewriter(Self.kDummyDataVersion)
    #expect(rewriter.capability(request) == .conversion)
  }

  @Test func mobileEnvironmentTest() {
    var request = Genmai_Commands_Request()
    let rewriter = VersionRewriter(Self.kDummyDataVersion)
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

  @Test func rewriteTestVersion() {
    // OSS (non GOOGLE_JAPANESE_INPUT_BUILD) branding.
    let kVersionPrefixExpected = "Genmai-"
    let kVersionPrefixUnexpected = "GoogleJapaneseInput-"

    let versionRewriter = VersionRewriter(Self.kDummyDataVersion)

    let request = ConversionRequest()
    do {
      let segments = Segments()
      Self.addSegment("ばーじょん", "バージョン", segments)

      #expect(versionRewriter.rewrite(request, segments))
      #expect(Self.findCandidateWithPrefix(kVersionPrefixExpected, segments))
      #expect(!Self.findCandidateWithPrefix(kVersionPrefixUnexpected, segments))
    }
    do {
      let segments = Segments()
      Self.addSegment("Version", "Version", segments)

      #expect(versionRewriter.rewrite(request, segments))
      #expect(Self.findCandidateWithPrefix(kVersionPrefixExpected, segments))
      #expect(!Self.findCandidateWithPrefix(kVersionPrefixUnexpected, segments))
    }
  }
}
