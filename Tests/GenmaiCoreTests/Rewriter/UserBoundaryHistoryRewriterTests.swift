// Port of mozc/src/rewriter/user_boundary_history_rewriter_test.cc (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

// Creates a segment that contains a single candidate whose key and value are
// set to `text`.
private func makeSegment(_ text: String, _ type: Segment.SegmentType, _ segment: Segment) {
  segment.setKey(text)
  segment.setSegmentType(type)
  let cand = segment.addCandidate()
  cand.key = text
  cand.contentKey = cand.key
  cand.value = cand.key
  cand.contentValue = cand.key
}

// Creates a simple segments.
private func makeSegments(_ segmentsTexts: [String], _ type: Segment.SegmentType) -> Segments {
  let segments = Segments()
  for text in segmentsTexts {
    makeSegment(text, type, segments.addSegment())
  }
  return segments
}

private struct UserBoundaryHistoryRewriterFixture {
  var config = ConfigHandler.defaultConfig()

  mutating func setIncognito(_ incognito: Bool) { config.incognitoMode = incognito }

  mutating func setLearningLevel(_ level: Genmai_Config_Config.HistoryLearningLevel) {
    config.historyLearningLevel = level
  }

  func createConversionRequest() -> ConversionRequest {
    ConversionRequestBuilder().setConfig(config).build()
  }

  func createConversionRequest(enableUserHistoryForConversion: Bool) -> ConversionRequest {
    var options = ConversionRequest.Options()
    options.enableUserHistoryForConversion = enableUserHistoryForConversion
    return ConversionRequestBuilder().setConfig(config).setOptions(options).build()
  }
}

/// TestWithTempUserProfile + TearDown (clears the history).
private func withFixture(_ body: (inout UserBoundaryHistoryRewriterFixture) throws -> Void) rethrows {
  try SystemUtil.withTempUserProfile { _ in
    var fixture = UserBoundaryHistoryRewriterFixture()
    try body(&fixture)
    UserBoundaryHistoryRewriter().clear()
  }
}

struct UserBoundaryHistoryRewriterTests {
  @Test func createFile() {
    withFixture { _ in
      let rewriter = UserBoundaryHistoryRewriter()
      let historyFile = FileUtil.joinPath(SystemUtil.getUserProfileDirectory(), "boundary.db")
      #expect(FileUtil.fileExistsOK(historyFile))
      withExtendedLifetime(rewriter) {}
    }
  }

  // Test if the rewriter can learn the splitting position at which user
  // explicitly resized segments.
  @Test func splitSegmentByHistory() throws {
    try withFixture { f in
      f.setIncognito(false)
      f.setLearningLevel(.defaultHistory)
      let convreq = f.createConversionRequest()

      let rewriter = UserBoundaryHistoryRewriter()
      do {
        // Suppose that a user splits the segment ["たんぽぽ"] into
        // ["たん", "ぽぽ"]. Let the rewriter learn this split.
        let segments = makeSegments(["たん", "ぽぽ"], .fixedValue)
        // This field needs to be set to indicate that user resized this segments.
        segments.setResized(true)
        rewriter.finish(convreq, segments)
      }
      do {
        // Verify if ["たんぽぽ"] is split into ["たん", "ぽぽ"]. Since the actual
        // split is handled by the underlying converter, we verify that
        // ResizeSegment() is called with the length array [2, 2, 0, 0, 0, 0, 0, 0].
        let segments = makeSegments(["たんぽぽ"], .free)
        let resizeRequest = try #require(rewriter.checkResizeSegmentsRequest(convreq, segments))
        #expect(resizeRequest.segmentIndex == 0)
        #expect(resizeRequest.segmentSizes == [2, 2, 0, 0, 0, 0, 0, 0])
      }
    }
  }

  // Test if the rewriter can learn the joining key for which user explicitly
  // resized segments.
  @Test func joinSegmentsByHistory() throws {
    try withFixture { f in
      f.setIncognito(false)
      f.setLearningLevel(.defaultHistory)
      let convreq = f.createConversionRequest()

      let rewriter = UserBoundaryHistoryRewriter()
      do {
        // Suppose that a user joins the segment ["たん", "ぽぽ"] to
        // ["たんぽぽ"]. Let the rewriter learn this.
        let segments = makeSegments(["たんぽぽ"], .fixedValue)
        segments.setResized(true)
        rewriter.finish(convreq, segments)
      }
      do {
        // Verify if ["たん", "ぽぽ"] is joined to ["たんぽぽ"].
        let segments = makeSegments(["たん", "ぽぽ"], .free)
        let resizeRequest = try #require(rewriter.checkResizeSegmentsRequest(convreq, segments))
        #expect(resizeRequest.segmentIndex == 0)
        #expect(resizeRequest.segmentSizes == [4, 0, 0, 0, 0, 0, 0, 0])
      }
    }
  }

  @Test func noInsertWhenIncognito() {
    withFixture { f in
      f.setLearningLevel(.defaultHistory)

      let rewriter = UserBoundaryHistoryRewriter()
      do {
        // History should not be learned during incognito mode.
        f.setIncognito(true)
        let convreq = f.createConversionRequest()
        let segments = makeSegments(["たん", "ぽぽ"], .fixedValue)
        segments.setResized(true)
        rewriter.finish(convreq, segments)
      }
      do {
        // Turn off the incognito mode. ResizeSegment() should not be called.
        f.setIncognito(false)
        let convreq = f.createConversionRequest()
        let segments = makeSegments(["たんぽぽ"], .free)
        #expect(rewriter.checkResizeSegmentsRequest(convreq, segments) == nil)
      }
    }
  }

  @Test func noInsertWhenReadOnly() {
    withFixture { f in
      f.setIncognito(false)

      let rewriter = UserBoundaryHistoryRewriter()
      do {
        // History should not be learned in read only mode.
        f.setLearningLevel(.readOnly)
        let convreq = f.createConversionRequest()
        let segments = makeSegments(["たん", "ぽぽ"], .fixedValue)
        segments.setResized(true)
        rewriter.finish(convreq, segments)
      }
      do {
        // Enable learning again. ResizeSegment() should not be called.
        f.setLearningLevel(.defaultHistory)
        let convreq = f.createConversionRequest()
        let segments = makeSegments(["たんぽぽ"], .free)
        #expect(rewriter.checkResizeSegmentsRequest(convreq, segments) == nil)
      }
    }
  }

  @Test func noInsertWhenDisableUserHistory() {
    withFixture { f in
      f.setIncognito(false)
      f.setLearningLevel(.defaultHistory)

      let rewriter = UserBoundaryHistoryRewriter()
      do {
        // History should not be learned when user history is disabled.
        let convreq = f.createConversionRequest(enableUserHistoryForConversion: false)
        let segments = makeSegments(["たん", "ぽぽ"], .fixedValue)
        segments.setResized(true)
        rewriter.finish(convreq, segments)
      }
      do {
        // Enable learning again. ResizeSegment() should not be called.
        let convreq = f.createConversionRequest(enableUserHistoryForConversion: true)
        let segments = makeSegments(["たんぽぽ"], .free)
        #expect(rewriter.checkResizeSegmentsRequest(convreq, segments) == nil)
      }
    }
  }

  @Test func noInsertWhenNotResized() {
    withFixture { f in
      f.setIncognito(false)
      f.setLearningLevel(.defaultHistory)
      let convreq = f.createConversionRequest()

      let rewriter = UserBoundaryHistoryRewriter()
      do {
        // History should not be learned when sements is not resized.
        let segments = makeSegments(["たん", "ぽぽ"], .fixedValue)
        segments.setResized(false)  // Not resized!
        rewriter.finish(convreq, segments)
      }
      do {
        // ResizeSegment() should not be called.
        let segments = makeSegments(["たんぽぽ"], .free)
        #expect(rewriter.checkResizeSegmentsRequest(convreq, segments) == nil)
      }
    }
  }

  @Test func noRewriteAfterClear() {
    withFixture { f in
      f.setIncognito(false)
      f.setLearningLevel(.defaultHistory)
      let convreq = f.createConversionRequest()

      let rewriter = UserBoundaryHistoryRewriter()
      do {
        // History IS learned.
        let segments = makeSegments(["たん", "ぽぽ"], .fixedValue)
        segments.setResized(true)
        rewriter.finish(convreq, segments)
      }
      do {
        // ResizeSegment() should not be called after clearing the history.
        rewriter.clear()
        let segments = makeSegments(["たんぽぽ"], .free)
        #expect(rewriter.checkResizeSegmentsRequest(convreq, segments) == nil)
      }
    }
  }

  @Test func noRewriteWhenIncognito() {
    withFixture { f in
      f.setIncognito(false)
      f.setLearningLevel(.defaultHistory)

      let rewriter = UserBoundaryHistoryRewriter()
      do {
        // History IS learned.
        let convreq = f.createConversionRequest()
        let segments = makeSegments(["たん", "ぽぽ"], .fixedValue)
        segments.setResized(true)
        rewriter.finish(convreq, segments)
      }
      do {
        // ResizeSegment() should not be called in incognito mode even after the
        // rewriter learned the history.
        f.setIncognito(true)
        let convreq = f.createConversionRequest()
        let segments = makeSegments(["たんぽぽ"], .free)
        #expect(rewriter.checkResizeSegmentsRequest(convreq, segments) == nil)
      }
    }
  }

  @Test func noRewriteWhenNoHistory() {
    withFixture { f in
      f.setIncognito(false)
      f.setLearningLevel(.defaultHistory)

      let rewriter = UserBoundaryHistoryRewriter()
      do {
        // History IS learned.
        let convreq = f.createConversionRequest()
        let segments = makeSegments(["たん", "ぽぽ"], .fixedValue)
        segments.setResized(true)
        rewriter.finish(convreq, segments)
      }
      do {
        // ResizeSegment() should not be called when history is disabled in config
        // even after the rewriter learned the history.
        f.setLearningLevel(.noHistory)
        let convreq = f.createConversionRequest()
        let segments = makeSegments(["たんぽぽ"], .free)
        #expect(rewriter.checkResizeSegmentsRequest(convreq, segments) == nil)
      }
    }
  }

  @Test func noRewriteWhenDisabledUserHistory() {
    withFixture { f in
      f.setIncognito(false)
      f.setLearningLevel(.defaultHistory)

      let rewriter = UserBoundaryHistoryRewriter()
      do {
        // History IS learned.
        let convreq = f.createConversionRequest(enableUserHistoryForConversion: true)
        let segments = makeSegments(["たん", "ぽぽ"], .fixedValue)
        segments.setResized(true)
        rewriter.finish(convreq, segments)
      }
      do {
        // ResizeSegment() should not be called when history is disabled in request
        // even after the rewriter learned the history.
        let convreq = f.createConversionRequest(enableUserHistoryForConversion: false)
        let segments = makeSegments(["たんぽぽ"], .free)
        #expect(rewriter.checkResizeSegmentsRequest(convreq, segments) == nil)
      }
    }
  }

  @Test func noRewriteWhenAlreadyResized() {
    withFixture { f in
      f.setIncognito(false)
      f.setLearningLevel(.defaultHistory)

      let rewriter = UserBoundaryHistoryRewriter()
      do {
        // History IS learned.
        let convreq = f.createConversionRequest()
        let segments = makeSegments(["たん", "ぽぽ"], .fixedValue)
        segments.setResized(true)
        rewriter.finish(convreq, segments)
      }
      do {
        // ResizeSegment() should not be called when the input segment is already
        // resized by the user.
        let convreq = f.createConversionRequest()
        let segments = makeSegments(["たんぽぽ"], .free)
        segments.setResized(true)
        #expect(rewriter.checkResizeSegmentsRequest(convreq, segments) == nil)
      }
    }
  }

  @Test func failureOfSplitIsNotFatal() throws {
    try withFixture { f in
      f.setIncognito(false)
      f.setLearningLevel(.defaultHistory)

      let rewriter = UserBoundaryHistoryRewriter()
      do {  // Register the segment boundaries with Finish.
        let convreq = f.createConversionRequest()
        var segments = makeSegments(["たん", "ぽぽ"], .fixedValue)
        segments.setResized(true)
        rewriter.finish(convreq, segments)

        segments = makeSegments(["わた", "げ"], .fixedValue)
        segments.setResized(true)
        rewriter.finish(convreq, segments)
      }
      do {  // "たんぽぽ" is resized to ["たん", "ぽぽ"].
        let convreq = f.createConversionRequest()
        let segments = makeSegments(["たんぽぽ", "わたげ"], .free)
        let resizeRequest = try #require(rewriter.checkResizeSegmentsRequest(convreq, segments))
        #expect(resizeRequest.segmentIndex == 0)
        #expect(resizeRequest.segmentSizes == [2, 2, 0, 0, 0, 0, 0, 0])
      }
      do {  // "たんざく" is skipped and "わたげ" is resized to ["わた", "げ"].
        let convreq = f.createConversionRequest()
        let segments = makeSegments(["たんざく", "わたげ"], .free)
        let resizeRequest = try #require(rewriter.checkResizeSegmentsRequest(convreq, segments))
        #expect(resizeRequest.segmentIndex == 1)
        #expect(resizeRequest.segmentSizes == [2, 1, 0, 0, 0, 0, 0, 0])
      }
      do {  // ["たん", "ぽぽ"] is skipped and "わたげ" is resized to ["わた", "げ"].
        let convreq = f.createConversionRequest()
        let segments = makeSegments(["たん", "ぽぽ", "わたげ"], .free)
        let resizeRequest = try #require(rewriter.checkResizeSegmentsRequest(convreq, segments))
        #expect(resizeRequest.segmentIndex == 2)
        #expect(resizeRequest.segmentSizes == [2, 1, 0, 0, 0, 0, 0, 0])
      }
      do {  // All segments are skipped.
        let convreq = f.createConversionRequest()
        let segments = makeSegments(["たん", "ぽぽ", "わた", "げ"], .free)
        #expect(rewriter.checkResizeSegmentsRequest(convreq, segments) == nil)
      }
    }
  }
}
