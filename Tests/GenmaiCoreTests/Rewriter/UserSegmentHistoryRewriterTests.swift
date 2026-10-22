// Port of mozc/src/rewriter/user_segment_history_rewriter_test.cc (3.35.6354).
//
// The C++ fixture (TestWithTempUserProfile + global CharacterFormManager +
// global clock mock) is replaced by task-local scopes so that tests can run in
// parallel: each test runs inside `SystemUtil.withTempUserProfile`,
// `CharacterFormManager.withScopedManagerForTesting` and, where the C++ test
// installs a ClockMock, `Clock.withClock`.

import Foundation
import GenmaiBase
import GenmaiProtocol
import GenmaiStorage
import Testing

@testable import GenmaiCore

private let kCandidatesSize = 20

private func initSegments(_ segments: Segments, _ size: Int, _ candidateSize: Int = kCandidatesSize) {
  segments.clear()
  for i in 0..<size {
    let segment = segments.addSegment()
    segment.setKey("segment" + String(UInt32(i)))
    for j in 0..<candidateSize {
      let c = segment.addCandidate()
      c.contentKey = segment.key
      c.contentValue = "candidate" + String(UInt32(j))
      c.value = c.contentValue
      if j == 0 {
        c.attributes |= Attribute.bestCandidate
      }
    }
    precondition(segment.candidatesSize == candidateSize)
  }
  precondition(segments.segmentsSize == size)
}

private func appendCandidateSuffix(
  _ segment: Segment, _ index: Int, _ suffix: String, _ lid: UInt16, _ rid: UInt16
) {
  segment.setKey(segment.key + suffix)
  segment.mutableCandidate(index).value += suffix
  segment.mutableCandidate(index).lid = lid
  segment.mutableCandidate(index).rid = rid
}

private func appendCandidateSuffixWithLid(
  _ segment: Segment, _ index: Int, _ suffix: String, _ lid: UInt16
) {
  // if lid == 0 and rid == 0, we assume that candidate is t13n.
  // we set 1 as rid to avoid this.
  appendCandidateSuffix(segment, index, suffix, lid, 1)
}

/// `segment->move_candidate(n, 0)` + RERANKED + FIXED_VALUE (the common
/// "user selected the n-th candidate" pattern in the C++ tests).
private func selectCandidate(_ segment: Segment, _ n: Int) {
  segment.moveCandidate(n, 0)
  segment.mutableCandidate(0).attributes |= Attribute.reranked
  segment.setSegmentType(.fixedValue)
}

private func hasAttr(_ c: Candidate, _ attr: UInt32) -> Bool { c.attributes & attr != 0 }

private final class Fixture {
  let mockDataManager: DataManager
  let posMatcher: PosMatcher
  let posGroup: PosGroup
  var config = Genmai_Config_Config()
  var request = Genmai_Commands_Request()

  init() throws {
    mockDataManager = try MockDataManager.create()
    posMatcher = PosMatcher(mockDataManager.getPosMatcherData())
    posGroup = PosGroup(mockDataManager.getPosGroupData())
    ConfigHandler.getDefaultConfig(&config)
    for i in 0..<config.characterFormRules.count {
      let group = config.characterFormRules[i].group
      if group == "0" || group == "A" || group == "(){}[]" {
        config.characterFormRules[i].preeditCharacterForm = .halfWidth
        config.characterFormRules[i].conversionCharacterForm = .halfWidth
      }
    }
    CharacterFormManager.getCharacterFormManager().reloadConfig(config)
    CharacterFormManager.getCharacterFormManager().clearHistory()
  }

  func createNumberRewriter() -> NumberRewriter {
    NumberRewriter(mockDataManager.getCounterSuffixSortedArray(), posMatcher)
  }

  func createUserSegmentHistoryRewriter() -> UserSegmentHistoryRewriter {
    UserSegmentHistoryRewriter(posMatcher, posGroup)
  }

  func setNumberForm(_ form: Genmai_Config_Config.CharacterForm) {
    for i in 0..<config.characterFormRules.count {
      if config.characterFormRules[i].group == "0" {
        config.characterFormRules[i].conversionCharacterForm = form
      }
    }
    CharacterFormManager.getCharacterFormManager().reloadConfig(config)
    if form != .lastForm {
      #expect(CharacterFormManager.getCharacterFormManager().getConversionCharacterForm("0") == form)
    }
  }

  func createConversionRequest() -> ConversionRequest {
    ConversionRequestBuilder().setConfig(config).setRequest(request).build()
  }
}

private func withFixture(_ body: (Fixture) throws -> Void) throws {
  try SystemUtil.withTempUserProfile { _ in
    try CharacterFormManager.withScopedManagerForTesting {
      try body(try Fixture())
    }
  }
}

private func withClockMock(_ body: (ClockMock) throws -> Void) rethrows {
  let clock = ClockMock(Date(timeIntervalSince1970: 0))
  try Clock.withClock(clock) { try body(clock) }
}

@Suite("UserSegmentHistoryRewriter")
struct UserSegmentHistoryRewriterTests {
  @Test func createFile() throws {
    try withFixture { f in
      let rewriter = f.createUserSegmentHistoryRewriter()
      _ = rewriter
      let historyFile = FileUtil.joinPath(SystemUtil.getUserProfileDirectory(), "/segment.db")
      #expect(FileUtil.fileExistsOK(historyFile))
    }
  }

  @Test func invalidInputsTest() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()
      segments.clear()

      let convreq = f.createConversionRequest()
      #expect(!rewriter.rewrite(convreq, segments))
      rewriter.finish(convreq, segments)
    }
  }

  @Test func incognitoModeTest() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      do {
        f.config.incognitoMode = false
        let convreq1 = f.createConversionRequest()
        initSegments(segments, 1)
        selectCandidate(segments.mutableSegment(0), 2)
        rewriter.finish(convreq1, segments)
        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq1, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate2")

        f.config.incognitoMode = true
        initSegments(segments, 1)
        let convreq2 = f.createConversionRequest()
        _ = rewriter.rewrite(convreq2, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate0")
      }

      do {
        rewriter.clear()  // clear history
        f.config.incognitoMode = true
        let convreq = f.createConversionRequest()
        initSegments(segments, 1)
        selectCandidate(segments.mutableSegment(0), 2)
        rewriter.finish(convreq, segments)
        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate0")
      }
    }
  }

  @Test func configTest() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      do {
        f.config.historyLearningLevel = .defaultHistory
        let convreq1 = f.createConversionRequest()
        initSegments(segments, 1)
        selectCandidate(segments.mutableSegment(0), 2)
        rewriter.finish(convreq1, segments)
        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq1, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate2")

        f.config.historyLearningLevel = .noHistory
        let convreq2 = f.createConversionRequest()
        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq2, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate0")

        f.config.historyLearningLevel = .readOnly
        let convreq3 = f.createConversionRequest()
        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq3, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate2")
      }

      do {
        f.config.historyLearningLevel = .noHistory
        let convreq = f.createConversionRequest()
        initSegments(segments, 1)
        selectCandidate(segments.mutableSegment(0), 2)
        rewriter.finish(convreq, segments)
        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate0")
      }
    }
  }

  @Test func disableTest() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()
      var optionsTrue = ConversionRequest.Options()
      optionsTrue.enableUserHistoryForConversion = true
      var optionsFalse = ConversionRequest.Options()
      optionsFalse.enableUserHistoryForConversion = false
      let convreqHistTrue = ConversionRequestBuilder()
        .setConfig(f.config).setRequest(f.request).setOptions(optionsTrue).build()
      let convreqHistFalse = ConversionRequestBuilder()
        .setConfig(f.config).setRequest(f.request).setOptions(optionsFalse).build()

      do {
        initSegments(segments, 1)
        selectCandidate(segments.mutableSegment(0), 2)
        rewriter.finish(convreqHistTrue, segments)
        initSegments(segments, 1)
        _ = rewriter.rewrite(convreqHistTrue, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate2")

        initSegments(segments, 1)
        _ = rewriter.rewrite(convreqHistFalse, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate0")

        initSegments(segments, 1)
        _ = rewriter.rewrite(convreqHistTrue, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate2")
      }

      do {
        initSegments(segments, 1)
        selectCandidate(segments.mutableSegment(0), 2)
        rewriter.finish(convreqHistFalse, segments)
        initSegments(segments, 1)
        _ = rewriter.rewrite(convreqHistFalse, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate0")
      }
    }
  }

  @Test func basicTest() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()
      let ushr = Attribute.userSegmentHistoryRewriter

      rewriter.clear()

      do {
        let convreq = f.createConversionRequest()
        initSegments(segments, 2)

        selectCandidate(segments.mutableSegment(0), 2)
        rewriter.finish(convreq, segments)
        initSegments(segments, 2)
        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value == "candidate2")
        #expect(hasAttr(segments.segment(0).candidate(0), ushr))
        #expect(segments.segment(1).candidate(0).value == "candidate0")
        #expect(!hasAttr(segments.segment(1).candidate(0), ushr))

        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate2")
        #expect(hasAttr(segments.segment(0).candidate(0), ushr))
        selectCandidate(segments.mutableSegment(0), 1)
        rewriter.finish(convreq, segments)

        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value == "candidate0")
        #expect(!hasAttr(segments.segment(0).candidate(0), ushr))

        initSegments(segments, 2)
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate2")
        #expect(hasAttr(segments.segment(0).candidate(0), ushr))
        #expect(segments.segment(1).candidate(0).value == "candidate0")
        #expect(!hasAttr(segments.segment(1).candidate(0), ushr))
        selectCandidate(segments.mutableSegment(1), 3)
        rewriter.finish(convreq, segments)

        initSegments(segments, 2)
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate2")
        #expect(hasAttr(segments.segment(0).candidate(0), ushr))
        #expect(segments.segment(1).candidate(0).value == "candidate3")
        #expect(hasAttr(segments.segment(1).candidate(0), ushr))
      }

      rewriter.clear()
      do {
        let convreq = f.createConversionRequest()
        initSegments(segments, 2)

        selectCandidate(segments.mutableSegment(0), 2)
        rewriter.finish(convreq, segments)
        initSegments(segments, 2)
        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value == "candidate2")
        #expect(hasAttr(segments.segment(0).candidate(0), ushr))
        #expect(segments.segment(1).candidate(0).value == "candidate0")
        #expect(!hasAttr(segments.segment(1).candidate(0), ushr))

        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate2")
        #expect(hasAttr(segments.segment(0).candidate(0), ushr))

        // back to the original
        selectCandidate(segments.mutableSegment(0), 1)
        rewriter.finish(convreq, segments)

        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate0")
        #expect(!hasAttr(segments.segment(0).candidate(0), ushr))
      }
    }
  }

  // Test for Issue 2155278
  @Test func sequenceTest() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      rewriter.clear()

      withClockMock { clock in
        let convreq = f.createConversionRequest()
        initSegments(segments, 1)

        selectCandidate(segments.mutableSegment(0), 2)
        #expect(segments.segment(0).candidate(0).value == "candidate2")
        rewriter.finish(convreq, segments)  // learn "candidate2"

        // Next timestamp of learning should be newer than previous learning.
        clock.advance(.seconds(1))

        initSegments(segments, 2)
        segments.mutableSegment(0).moveCandidate(2, 0)
        segments.mutableSegment(0).setSegmentType(.history)
        segments.mutableSegment(1).setKey(segments.segment(0).key)
        #expect(segments.historySegmentsSize == 1)
        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value == "candidate2")
        #expect(segments.segment(1).candidate(0).value == "candidate2")
        // 2 0 1 3 4 ..

        selectCandidate(segments.mutableSegment(1), 3)
        #expect(segments.segment(1).candidate(0).value == "candidate3")
        rewriter.finish(convreq, segments)  // learn "candidate3"

        clock.advance(.seconds(1))

        initSegments(segments, 3)
        segments.mutableSegment(0).moveCandidate(2, 0)
        segments.mutableSegment(0).setSegmentType(.history)
        segments.mutableSegment(1).moveCandidate(3, 0)
        segments.mutableSegment(1).setSegmentType(.history)
        segments.mutableSegment(1).setKey(segments.segment(0).key)
        segments.mutableSegment(2).setKey(segments.segment(0).key)
        #expect(segments.historySegmentsSize == 2)
        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value == "candidate2")
        #expect(segments.segment(1).candidate(0).value == "candidate3")
        #expect(segments.segment(2).candidate(0).value == "candidate3")
        // 3 2 0 1 4 ..

        selectCandidate(segments.mutableSegment(2), 1)
        #expect(segments.segment(2).candidate(0).value == "candidate2")
        rewriter.finish(convreq, segments)  // learn "candidate2"

        clock.advance(.seconds(1))

        initSegments(segments, 4)
        segments.mutableSegment(0).moveCandidate(2, 0)
        segments.mutableSegment(0).setSegmentType(.history)
        segments.mutableSegment(1).moveCandidate(3, 0)
        segments.mutableSegment(1).setSegmentType(.history)
        segments.mutableSegment(1).setKey(segments.segment(0).key)
        segments.mutableSegment(2).moveCandidate(2, 0)
        segments.mutableSegment(2).setSegmentType(.history)
        segments.mutableSegment(2).setKey(segments.segment(0).key)
        segments.mutableSegment(3).setKey(segments.segment(0).key)
        #expect(segments.historySegmentsSize == 3)
        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value == "candidate2")
        #expect(segments.segment(1).candidate(0).value == "candidate3")
        #expect(segments.segment(2).candidate(0).value == "candidate2")
        #expect(segments.segment(3).candidate(0).value == "candidate2")
        // 2 3 0 1 4 ..
      }
    }
  }

  @Test func dupTest() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      rewriter.clear()

      withClockMock { clock in
        let convreq = f.createConversionRequest()
        initSegments(segments, 1)
        selectCandidate(segments.mutableSegment(0), 4)
        rewriter.finish(convreq, segments)
        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq, segments)

        // restored
        // 4,0,1,2,3,5,...
        #expect(segments.segment(0).candidate(0).value == "candidate4")
        selectCandidate(segments.mutableSegment(0), 4)
        clock.advance(.seconds(1))
        rewriter.finish(convreq, segments)
        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq, segments)

        // 3,4,0,1,2,5
        #expect(segments.segment(0).candidate(0).value == "candidate3")
        #expect(segments.segment(0).candidate(1).value == "candidate4")
        selectCandidate(segments.mutableSegment(0), 4)
        clock.advance(.seconds(1))
        rewriter.finish(convreq, segments)
        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value == "candidate2")
        #expect(segments.segment(0).candidate(1).value == "candidate3")
        #expect(segments.segment(0).candidate(2).value == "candidate4")
      }
    }
  }

  @Test func learningType() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      for (attr, expected) in [
        (Attribute.noLearning, "candidate0"),
        (Attribute.noHistoryLearning, "candidate0"),
        (Attribute.noSuggestLearning, "candidate2"),
      ] {
        let convreq = f.createConversionRequest()
        rewriter.clear()
        initSegments(segments, 1)
        selectCandidate(segments.mutableSegment(0), 2)
        segments.mutableSegment(0).mutableCandidate(0).attributes |= attr
        rewriter.finish(convreq, segments)
        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == expected)
      }
    }
  }

  @Test func contextSensitive() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      rewriter.clear()
      do {
        let convreq = f.createConversionRequest()
        initSegments(segments, 2)
        selectCandidate(segments.mutableSegment(0), 2)
        segments.mutableSegment(0).mutableCandidate(0).attributes |= Attribute.contextSensitive
        rewriter.finish(convreq, segments)
        initSegments(segments, 2)
        _ = rewriter.rewrite(convreq, segments)

        // fire if two segments
        #expect(segments.segment(0).candidate(0).value == "candidate2")
        // not fire if single segment
        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate0")
      }

      // learn in single segment
      rewriter.clear()
      do {
        let convreq = f.createConversionRequest()
        initSegments(segments, 1)
        selectCandidate(segments.mutableSegment(0), 2)
        segments.mutableSegment(0).mutableCandidate(0).attributes |= Attribute.contextSensitive
        rewriter.finish(convreq, segments)

        // fire if even in single segment
        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate2")

        // not fire if two segments
        initSegments(segments, 2)
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate0")
      }
    }
  }

  @Test func contentValueLearning() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      rewriter.clear()
      do {
        let convreq = f.createConversionRequest()
        initSegments(segments, 1)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 0, ":all", 0)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 2, ":all", 0)
        selectCandidate(segments.mutableSegment(0), 2)

        rewriter.finish(convreq, segments)

        initSegments(segments, 1)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 0, ":all", 0)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 2, ":all", 0)

        _ = rewriter.rewrite(convreq, segments)

        // exact match
        #expect(segments.segment(0).candidate(0).value == "candidate2:all")

        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq, segments)

        // content value only:
        // in both learning/applying phase, lid and suffix are the same
        // as those of top candidates.
        #expect(segments.segment(0).candidate(0).value == "candidate2")

        initSegments(segments, 1)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 0, ":other", 0)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 2, ":other", 0)

        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value == "candidate2:other")
      }

      // In learning phase, lid is different
      rewriter.clear()
      do {
        let convreq = f.createConversionRequest()
        initSegments(segments, 1)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 0, ":all", 0)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 2, ":all", 1)
        selectCandidate(segments.mutableSegment(0), 2)
        rewriter.finish(convreq, segments)
        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate0")
      }

      // In learning phase, suffix (functional value) is different
      rewriter.clear()
      do {
        let convreq = f.createConversionRequest()
        initSegments(segments, 1)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 0, "", 0)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 2, ":other", 1)
        selectCandidate(segments.mutableSegment(0), 2)
        rewriter.finish(convreq, segments)
        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate0")
      }

      // In apply phase, lid is different
      rewriter.clear()
      do {
        let convreq = f.createConversionRequest()
        initSegments(segments, 1)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 0, ":all", 0)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 2, ":all", 0)
        selectCandidate(segments.mutableSegment(0), 2)
        rewriter.finish(convreq, segments)
        initSegments(segments, 1)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 0, ":other", 0)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 2, ":other", 1)
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate0:other")
      }

      // In apply phase, suffix (functional value) is different
      rewriter.clear()
      do {
        let convreq = f.createConversionRequest()
        initSegments(segments, 1)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 0, ":all", 0)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 2, ":all", 0)
        selectCandidate(segments.mutableSegment(0), 2)
        rewriter.finish(convreq, segments)
        initSegments(segments, 1)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 0, "", 0)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 2, ":other", 0)
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate0")
      }
    }
  }

  @Test func replaceableTest() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      rewriter.clear()
      do {
        let convreq = f.createConversionRequest()
        initSegments(segments, 2)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 0, ":all", 0)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 2, ":all", 0)
        selectCandidate(segments.mutableSegment(0), 2)

        rewriter.finish(convreq, segments)

        initSegments(segments, 1)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 0, ":all", 0)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 2, ":all", 0)

        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value == "candidate2:all")

        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq, segments)
      }

      rewriter.clear()
      do {
        let convreq = f.createConversionRequest()
        initSegments(segments, 1)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 0, ":all", 0)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 2, ":all", 0)
        selectCandidate(segments.mutableSegment(0), 2)

        rewriter.finish(convreq, segments)

        initSegments(segments, 2)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 0, ":all", 0)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 2, ":all", 0)

        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value == "candidate2:all")

        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq, segments)
      }

      // (learn segments, learn lid of candidate2, apply segments, apply lid)
      let cases: [(Int, UInt16, Int, UInt16)] = [
        (2, 1, 1, 0),
        (2, 0, 1, 1),
        (1, 1, 2, 0),
        (1, 0, 2, 1),
      ]
      for (learnSize, learnLid, applySize, applyLid) in cases {
        rewriter.clear()
        let convreq = f.createConversionRequest()
        initSegments(segments, learnSize)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 0, ":all", 0)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 2, ":all", learnLid)
        selectCandidate(segments.mutableSegment(0), 2)
        rewriter.finish(convreq, segments)
        initSegments(segments, applySize)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 0, ":all", 0)
        appendCandidateSuffixWithLid(segments.mutableSegment(0), 2, ":all", applyLid)
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate0:all")
      }
    }
  }

  @Test func notReplaceableForDifferentId() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      rewriter.clear()
      do {
        let convreq = f.createConversionRequest()
        initSegments(segments, 2)
        appendCandidateSuffix(segments.mutableSegment(0), 0, ":all", 1, 1)
        appendCandidateSuffix(segments.mutableSegment(0), 2, ":all", 200, 300)
        selectCandidate(segments.mutableSegment(0), 2)

        rewriter.finish(convreq, segments)

        initSegments(segments, 2)
        appendCandidateSuffix(segments.mutableSegment(0), 0, ":all", 1, 1)
        appendCandidateSuffix(segments.mutableSegment(0), 2, ":all", 200, 300)
        segments.mutableSegment(1).mutableCandidate(0).value = "not_same_as_before"

        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value != "candidate2:all")
      }
    }
  }

  @Test func replaceableForSameId() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      rewriter.clear()
      do {
        let convreq = f.createConversionRequest()
        initSegments(segments, 2)
        appendCandidateSuffix(segments.mutableSegment(0), 0, ":all", 1, 1)
        appendCandidateSuffix(segments.mutableSegment(0), 2, ":all", 1, 1)
        selectCandidate(segments.mutableSegment(0), 2)

        rewriter.finish(convreq, segments)

        initSegments(segments, 2)
        appendCandidateSuffix(segments.mutableSegment(0), 0, ":all", 1, 1)
        appendCandidateSuffix(segments.mutableSegment(0), 2, ":all", 1, 1)
        segments.mutableSegment(1).mutableCandidate(0).value = "not_same_as_before"

        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value == "candidate2:all")
      }
    }
  }

  @Test func replaceableT13NTest() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      rewriter.clear()
      do {
        let convreq = f.createConversionRequest()
        initSegments(segments, 2)
        appendCandidateSuffix(segments.mutableSegment(0), 0, ":all", 1, 1)
        // Prepare candidate2 as T13N candidate.
        appendCandidateSuffix(segments.mutableSegment(0), 2, ":all", 0, 0)
        selectCandidate(segments.mutableSegment(0), 2)

        rewriter.finish(convreq, segments)

        initSegments(segments, 2)
        appendCandidateSuffix(segments.mutableSegment(0), 0, ":all", 1, 1)
        appendCandidateSuffix(segments.mutableSegment(0), 2, ":all", 0, 0)
        segments.mutableSegment(1).mutableCandidate(0).value = "not_same_as_before"

        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value == "candidate2:all")
      }

      rewriter.clear()
      do {
        let setUpSegments = {
          initSegments(segments, 2)
          appendCandidateSuffix(segments.mutableSegment(0), 0, "", 1, 1)
          // Prepare candidate2 as T13N candidate (lid, rid != 0)
          let c = segments.mutableSegment(0).mutableCandidate(2)
          c.value = "ひらがな"
          c.contentValue = "ひらがな"
          c.lid = 10
          c.rid = 10
        }
        let convreq = f.createConversionRequest()

        setUpSegments()
        selectCandidate(segments.mutableSegment(0), 2)

        rewriter.finish(convreq, segments)

        setUpSegments()
        segments.mutableSegment(1).mutableCandidate(0).value = "not_same_as_before"

        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value == "ひらがな")
      }
    }
  }

  @Test func leftRightNumber() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      rewriter.clear()

      do {
        let convreq = f.createConversionRequest()
        initSegments(segments, 2)

        segments.mutableSegment(0).mutableCandidate(0).value = "1234"
        segments.mutableSegment(1).moveCandidate(2, 0)
        segments.mutableSegment(1).mutableCandidate(0).attributes |= Attribute.reranked
        segments.mutableSegment(1).mutableCandidate(0).attributes |= Attribute.contextSensitive
        segments.mutableSegment(1).setSegmentType(.fixedValue)
        rewriter.finish(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "1234")
        #expect(segments.segment(1).candidate(0).value == "candidate2")

        initSegments(segments, 2)
        // different num.
        segments.mutableSegment(0).mutableCandidate(0).value = "5678"
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "5678")
        #expect(segments.segment(1).candidate(0).value == "candidate2")
      }

      do {
        let convreq = f.createConversionRequest()
        initSegments(segments, 2)

        segments.mutableSegment(1).mutableCandidate(0).value = "1234"
        segments.mutableSegment(0).moveCandidate(2, 0)
        segments.mutableSegment(0).mutableCandidate(0).attributes |= Attribute.reranked
        segments.mutableSegment(0).mutableCandidate(0).attributes |= Attribute.contextSensitive
        segments.mutableSegment(0).setSegmentType(.fixedValue)
        rewriter.finish(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate2")
        #expect(segments.segment(1).candidate(0).value == "1234")

        initSegments(segments, 2)
        // different num.
        segments.mutableSegment(1).mutableCandidate(0).value = "5678"
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate2")
        #expect(segments.segment(1).candidate(0).value == "5678")
      }
    }
  }

  @Test func backetMatching() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      rewriter.clear()

      do {
        let convreq = f.createConversionRequest()
        initSegments(segments, 1)
        let candidate = segments.mutableSegment(0).insertNewCandidate(2)
        candidate.value = "("
        candidate.contentValue = "("
        candidate.contentKey = "("
        selectCandidate(segments.mutableSegment(0), 2)
        rewriter.finish(convreq, segments)
      }

      do {
        let convreq = f.createConversionRequest()
        initSegments(segments, 1)
        let candidate = segments.mutableSegment(0).insertNewCandidate(2)
        candidate.value = ")"
        candidate.contentValue = ")"
        candidate.contentKey = ")"

        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value == ")")
      }
    }
  }

  // issue 2262691
  @Test func multipleLearning() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      rewriter.clear()

      for (key, value) in [("key1", "value1"), ("key2", "value2")] {
        let convreq = f.createConversionRequest()
        initSegments(segments, 1)
        segments.mutableSegment(0).setKey(key)
        let candidate = segments.mutableSegment(0).insertNewCandidate(2)
        candidate.value = value
        candidate.contentValue = value
        candidate.contentKey = key
        selectCandidate(segments.mutableSegment(0), 2)
        rewriter.finish(convreq, segments)
      }

      do {
        let convreq = f.createConversionRequest()
        initSegments(segments, 1)
        segments.mutableSegment(0).setKey("key1")
        var candidate = segments.mutableSegment(0).insertNewCandidate(2)
        candidate.value = "value2"
        candidate.contentValue = "value2"
        candidate.contentKey = "key2"
        candidate = segments.mutableSegment(0).insertNewCandidate(3)
        candidate.value = "value1"
        candidate.contentValue = "value1"
        candidate.contentKey = "key1"

        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value == "value1")
      }
    }
  }

  // MARK: - Number tests (with NumberRewriter)

  /// Learns one number candidate (segment with a single candidate at index 0)
  /// through NumberRewriter.finish + UserSegmentHistoryRewriter.finish.
  private static func learnNumber(
    _ f: Fixture, _ segments: Segments, _ rewriter: UserSegmentHistoryRewriter,
    _ numberRewriter: NumberRewriter?, key: String, value: String, contentValue: String? = nil,
    style: NumberUtil.NumberString.Style, reranked: Bool
  ) {
    let convreq = f.createConversionRequest()
    segments.clear()
    segments.addSegment()
    segments.mutableSegment(0).setKey(key)
    let candidate = segments.mutableSegment(0).insertNewCandidate(0)
    candidate.value = value
    candidate.contentValue = contentValue ?? value
    candidate.contentKey = key
    candidate.lid = f.posMatcher.getNumberId()
    candidate.rid = f.posMatcher.getNumberId()
    candidate.style = style
    if reranked {
      segments.mutableSegment(0).mutableCandidate(0).attributes |= Attribute.reranked
    }
    segments.mutableSegment(0).setSegmentType(.fixedValue)
    numberRewriter?.finish(convreq, segments)
    rewriter.finish(convreq, segments)
  }

  /// Sets up a single number segment `key` with a plain candidate.
  private static func setUpNumberSegment(_ f: Fixture, _ segments: Segments, _ key: String) {
    segments.mutableSegment(0).setKey(key)
    let candidate = segments.mutableSegment(0).insertNewCandidate(0)
    candidate.value = key
    candidate.contentValue = key
    candidate.contentKey = key
    candidate.lid = f.posMatcher.getNumberId()
    candidate.rid = f.posMatcher.getNumberId()
  }

  @Test func numberSpecial() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()
      let numberRewriter = f.createNumberRewriter()

      rewriter.clear()

      Self.learnNumber(
        f, segments, rewriter, numberRewriter, key: "12", value: "⑫", style: .numberCircled,
        reranked: true)

      do {
        let convreq = f.createConversionRequest()
        segments.clear()
        segments.addSegment()
        Self.setUpNumberSegment(f, segments, "14")
        #expect(numberRewriter.rewrite(convreq, segments))
        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value == "⑭")
      }
    }
  }

  @Test func numberHalfWidth() throws {
    try withFixture { f in
      f.setNumberForm(.halfWidth)
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()
      let numberRewriter = f.createNumberRewriter()

      rewriter.clear()

      // full-width for separated number
      Self.learnNumber(
        f, segments, rewriter, numberRewriter, key: "1234", value: "１，２３４",
        style: .numberSeparatedArabicFullwidth, reranked: false)

      do {
        let convreq = f.createConversionRequest()
        segments.clear()
        segments.addSegment()
        Self.setUpNumberSegment(f, segments, "1234")

        #expect(numberRewriter.rewrite(convreq, segments))
        _ = rewriter.rewrite(convreq, segments)

        #expect("1,234" == segments.segment(0).candidate(0).value)
      }
    }
  }

  @Test func numberFullWidth() throws {
    try withFixture { f in
      f.setNumberForm(.fullWidth)
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()
      let numberRewriter = f.createNumberRewriter()

      rewriter.clear()

      // half-width for separated number
      Self.learnNumber(
        f, segments, rewriter, numberRewriter, key: "1234", value: "1,234",
        contentValue: "1,2344", style: .numberSeparatedArabicHalfwidth, reranked: false)

      do {
        let convreq = f.createConversionRequest()
        segments.clear()
        segments.addSegment()
        Self.setUpNumberSegment(f, segments, "1234")
        #expect(numberRewriter.rewrite(convreq, segments))
        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value == "１，２３４")
      }
    }
  }

  @Test func numberNoSeparated() throws {
    try withFixture { f in
      f.setNumberForm(.halfWidth)
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()
      let numberRewriter = f.createNumberRewriter()

      rewriter.clear()

      // learn kanji
      Self.learnNumber(
        f, segments, rewriter, numberRewriter, key: "10", value: "十", style: .numberKanji,
        reranked: false)
      // learn separated
      Self.learnNumber(
        f, segments, rewriter, numberRewriter, key: "1234", value: "1,234",
        style: .numberSeparatedArabicHalfwidth, reranked: false)

      do {
        let convreq = f.createConversionRequest()
        initSegments(segments, 1)
        Self.setUpNumberSegment(f, segments, "9")
        #expect(numberRewriter.rewrite(convreq, segments))
        _ = rewriter.rewrite(convreq, segments)

        // 9, not "九"
        #expect(segments.segment(0).candidate(0).value == "9")
      }
    }
  }

  @Test func numberKanji() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()
      let numberRewriter = f.createNumberRewriter()

      rewriter.clear()

      Self.learnNumber(
        f, segments, rewriter, numberRewriter, key: "12", value: "十二", style: .numberKanji,
        reranked: false)

      do {
        let convreq = f.createConversionRequest()
        segments.clear()
        segments.addSegment()
        Self.setUpNumberSegment(f, segments, "14")

        #expect(numberRewriter.rewrite(convreq, segments))
        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value == "十四")
      }
    }
  }

  @Test func numberKanjiArabic() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()
      let numberRewriter = f.createNumberRewriter()

      rewriter.clear()

      Self.learnNumber(
        f, segments, rewriter, numberRewriter, key: "1200", value: "一二〇〇",
        style: .numberKanjiArabic, reranked: false)

      do {
        let convreq = f.createConversionRequest()
        segments.clear()
        segments.addSegment()
        Self.setUpNumberSegment(f, segments, "3400")

        #expect(numberRewriter.rewrite(convreq, segments))
        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value == "三四〇〇")
      }
    }
  }

  @Test func numberFullWidthArabic() throws {
    try withFixture { f in
      f.setNumberForm(.lastForm)
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()
      let numberRewriter = f.createNumberRewriter()

      rewriter.clear()

      Self.learnNumber(
        f, segments, rewriter, numberRewriter, key: "12", value: "１２", style: .defaultStyle,
        reranked: false)

      do {
        let convreq = f.createConversionRequest()
        segments.clear()
        segments.addSegment()
        Self.setUpNumberSegment(f, segments, "14")

        #expect(numberRewriter.rewrite(convreq, segments))
        _ = rewriter.rewrite(convreq, segments)

        #expect(segments.segment(0).candidate(0).value == "１４")
      }
    }
  }

  @Test func numberMultipleSegmentsIgnored() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()
      let numberRewriter = f.createNumberRewriter()

      rewriter.clear()

      Self.learnNumber(
        f, segments, rewriter, numberRewriter, key: "12", value: "十二", style: .numberKanji,
        reranked: false)

      do {
        let convreq = f.createConversionRequest()
        let segments = Segments()
        let seg1 = segments.addSegment()
        seg1.setKey("2")
        let c1 = seg1.addCandidate()
        c1.key = "2"
        c1.contentKey = "2"
        c1.value = "2"
        c1.contentValue = "2"
        c1.lid = f.posMatcher.getNumberId()
        c1.rid = f.posMatcher.getNumberId()

        let seg2 = segments.addSegment()
        seg2.setKey("かい")
        let c2 = seg2.addCandidate()
        c2.key = "かい"
        c2.contentKey = "かい"
        c2.value = "階"
        c2.contentValue = "階"

        #expect(numberRewriter.rewrite(convreq, segments))
        _ = rewriter.rewrite(convreq, segments)

        // The top candidate of segment 0 remains "2", not rotated to "二"
        #expect(segments.segment(0).candidate(0).value == "2")
      }
    }
  }

  // UserSegmentHistoryNumberTest (TEST_P over NumberStyleLearningTestForRequest)
  @Test(arguments: [0, 1, 2])
  func userSegmentHistoryNumberTest(_ param: Int) throws {
    var request = Genmai_Commands_Request()
    switch param {
    case 1: RequestTestUtil.fillMobileRequest(&request)
    case 2: RequestTestUtil.fillMobileRequestWithHardwareKeyboard(&request)
    default: break
    }
    try withFixture { f in
      let convreq = ConversionRequestBuilder().setConfig(f.config).setRequest(request).build()

      f.setNumberForm(.fullWidth)
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()
      let numberRewriter = f.createNumberRewriter()

      rewriter.clear()

      do {
        segments.clear()
        segments.addSegment()
        segments.mutableSegment(0).setKey("1234")
        let candidate = segments.mutableSegment(0).insertNewCandidate(0)
        candidate.value = "1,234"
        candidate.contentValue = "1,234"
        candidate.contentKey = "1234"
        candidate.lid = f.posMatcher.getNumberId()
        candidate.rid = f.posMatcher.getNumberId()
        candidate.style = .numberSeparatedArabicHalfwidth
        segments.mutableSegment(0).setSegmentType(.fixedValue)
        rewriter.finish(convreq, segments)  // learn kanji
      }

      do {
        // This rewriter does not handle number candidate
        segments.clear()
        segments.addSegment()
        Self.setUpNumberSegment(f, segments, "9")
        #expect(numberRewriter.rewrite(convreq, segments))
        _ = rewriter.rewrite(convreq, segments)

        // 9, not "九"
        #expect(segments.segment(0).candidate(0).value == "9")
      }
    }
  }

  // MARK: - Regressions and others

  @Test func regression2459519() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      rewriter.clear()

      withClockMock { clock in
        let convreq = f.createConversionRequest()
        initSegments(segments, 1)
        selectCandidate(segments.mutableSegment(0), 2)
        rewriter.finish(convreq, segments)

        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate2")
        #expect(segments.segment(0).candidate(1).value == "candidate0")

        selectCandidate(segments.mutableSegment(0), 1)
        clock.advance(.seconds(1))
        rewriter.finish(convreq, segments)

        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate0")
        #expect(segments.segment(0).candidate(1).value == "candidate2")

        selectCandidate(segments.mutableSegment(0), 1)
        clock.advance(.seconds(1))
        rewriter.finish(convreq, segments)

        initSegments(segments, 1)
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).value == "candidate2")
        #expect(segments.segment(0).candidate(1).value == "candidate0")
      }
    }
  }

  @Test func regression2459520() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      rewriter.clear()

      let convreq = f.createConversionRequest()
      initSegments(segments, 2)
      selectCandidate(segments.mutableSegment(0), 2)
      selectCandidate(segments.mutableSegment(1), 3)
      rewriter.finish(convreq, segments)

      initSegments(segments, 2)
      _ = rewriter.rewrite(convreq, segments)
      #expect(segments.segment(0).candidate(0).value == "candidate2")
      #expect(segments.segment(1).candidate(0).value == "candidate3")
    }
  }

  @Test func puntuationsTest() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      let id = f.posMatcher.getJapanesePunctuationsId()

      rewriter.clear()

      let convreq = f.createConversionRequest()
      initSegments(segments, 2)
      segments.mutableSegment(1).setKey(".")
      for i in 1..<kCandidatesSize {
        segments.mutableSegment(1).mutableCandidate(i).lid = id
        segments.mutableSegment(1).mutableCandidate(i).rid = id
        segments.mutableSegment(1).mutableCandidate(i).value = "."
      }
      selectCandidate(segments.mutableSegment(1), 2)
      rewriter.finish(convreq, segments)

      initSegments(segments, 2)
      segments.mutableSegment(1).setKey(".")
      for i in 1..<kCandidatesSize {
        segments.mutableSegment(1).mutableCandidate(i).lid = id
        segments.mutableSegment(1).mutableCandidate(i).rid = id
        segments.mutableSegment(1).mutableCandidate(i).value = "."
      }

      // Punctuation is not remembered
      _ = rewriter.rewrite(convreq, segments)
      #expect(segments.segment(1).candidate(0).value == "candidate0")
    }
  }

  @Test func regression3264619() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      // Too big candidates
      let convreq = f.createConversionRequest()
      initSegments(segments, 2, 1024)
      selectCandidate(segments.mutableSegment(0), 512)
      rewriter.finish(convreq, segments)
      initSegments(segments, 2, 1024)
      _ = rewriter.rewrite(convreq, segments)

      #expect(segments.segment(0).candidate(0).value == "candidate512")
      #expect(segments.segment(1).candidate(0).value == "candidate0")
    }
  }

  @Test func randomTest() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      withClockMock { clock in
        rewriter.clear()
        for _ in 0..<5 {
          let convreq = f.createConversionRequest()
          initSegments(segments, 1)
          let n = Int.random(in: 0..<10)
          let expected = segments.segment(0).candidate(n).value
          selectCandidate(segments.mutableSegment(0), n)
          #expect(segments.segment(0).candidate(0).value == expected)
          rewriter.finish(convreq, segments)
          initSegments(segments, 1)
          _ = rewriter.rewrite(convreq, segments)
          #expect(segments.segment(0).candidate(0).value == expected)
          clock.advance(.seconds(1))  // update LRU timer
        }
      }
    }
  }

  @Test func promotionWithWidthInvariantKey() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      // Step 1: Learn half-width "abc".
      do {
        let convreq = f.createConversionRequest()
        segments.clear()
        initSegments(segments, 1, 2)
        segments.mutableSegment(0).setKey("abc")
        let candidate = segments.mutableSegment(0).mutableCandidate(1)
        candidate.value = "abc"
        candidate.contentValue = "abc"
        candidate.contentKey = "abc"
        candidate.description = "[半] アルファベット"
        selectCandidate(segments.mutableSegment(0), 1)
        rewriter.finish(convreq, segments)
      }

      // Step 2: Rewrite with full-width "ａｂｃ".
      // USHR promotes the full-width candidate based on half-width learning,
      // without altering candidate form or description (deferred to
      // VariantsRewriter).
      do {
        let convreq = f.createConversionRequest()
        segments.clear()
        initSegments(segments, 1, 2)
        segments.mutableSegment(0).setKey("abc")
        let candidate = segments.mutableSegment(0).mutableCandidate(1)
        candidate.value = "ａｂｃ"
        candidate.contentValue = "ａｂｃ"
        candidate.contentKey = "abc"
        candidate.description = "[全] アルファベット"
        _ = rewriter.rewrite(convreq, segments)
        #expect(segments.segment(0).candidate(0).contentValue == "ａｂｃ")
        #expect(segments.segment(0).candidate(0).description == "[全] アルファベット")
        rewriter.finish(convreq, segments)
      }
    }
  }

  @Test func metaCandidatesTransliterationDeduplication() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      // Step 1: Learn half-width "aiu" for "あいう".
      do {
        let convreq = f.createConversionRequest()
        segments.clear()
        initSegments(segments, 1, 2)
        segments.mutableSegment(0).setKey("あいう")
        let candidate = segments.mutableSegment(0).mutableCandidate(1)
        candidate.value = "aiu"
        candidate.contentValue = "aiu"
        candidate.contentKey = "あいう"
        selectCandidate(segments.mutableSegment(0), 1)
        rewriter.finish(convreq, segments)
      }

      // Step 2: Rewrite "あいう" with meta candidates containing both
      // half-width and full-width transliterations.
      do {
        let convreq = f.createConversionRequest()
        segments.clear()
        initSegments(segments, 1, 2)
        let seg = segments.mutableSegment(0)
        seg.setKey("あいう")
        seg.mutableCandidate(0).value = "あいう"
        seg.mutableCandidate(0).contentValue = "あいう"
        seg.mutableCandidate(1).value = "アイウ"
        seg.mutableCandidate(1).contentValue = "アイウ"

        for _ in 0..<TransliterationType.numT13nTypes {
          let mc = seg.addMetaCandidate()
          mc.key = "あいう"
          mc.contentKey = "あいう"
        }
        seg.mutableMetaCandidate(TransliterationType.halfAscii.rawValue).value = "aiu"
        seg.mutableMetaCandidate(TransliterationType.halfAscii.rawValue).contentValue = "aiu"
        seg.mutableMetaCandidate(TransliterationType.fullAscii.rawValue).value = "ａｉｕ"
        seg.mutableMetaCandidate(TransliterationType.fullAscii.rawValue).contentValue = "ａｉｕ"

        _ = rewriter.rewrite(convreq, segments)

        // Only one ASCII transliteration candidate ("aiu") should be promoted
        // to index 0, and not duplicated with "ａｉｕ".
        #expect(seg.candidatesSize == 3)
        #expect(seg.candidate(0).value == "aiu")
        #expect(seg.candidate(1).value != "ａｉｕ")
      }
    }
  }

  @Test func preserveNoVariantsExpansionOnPromotion() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      // Step 1: Learn "Google" with NO_VARIANTS_EXPANSION (e.g. from
      // EnglishVariantsRewriter).
      do {
        let convreq = f.createConversionRequest()
        segments.clear()
        initSegments(segments, 1, 2)
        segments.mutableSegment(0).setKey("ぐーぐる")
        let candidate = segments.mutableSegment(0).mutableCandidate(1)
        candidate.value = "Google"
        candidate.contentValue = "Google"
        candidate.contentKey = "ぐーぐる"
        candidate.attributes |= Attribute.noVariantsExpansion
        selectCandidate(segments.mutableSegment(0), 1)
        rewriter.finish(convreq, segments)
      }

      // Step 2: Rewrite "ぐーぐる".
      do {
        let convreq = f.createConversionRequest()
        segments.clear()
        initSegments(segments, 1, 2)
        let seg = segments.mutableSegment(0)
        seg.setKey("ぐーぐる")
        seg.mutableCandidate(0).value = "グーグル"
        seg.mutableCandidate(0).contentValue = "グーグル"
        seg.mutableCandidate(1).value = "Google"
        seg.mutableCandidate(1).contentValue = "Google"
        seg.mutableCandidate(1).attributes |= Attribute.noVariantsExpansion

        _ = rewriter.rewrite(convreq, segments)

        #expect(seg.candidate(0).value == "Google")
        #expect(hasAttr(seg.candidate(0), Attribute.noVariantsExpansion))
      }
    }
  }

  @Test func supportInnerSegmentsOnLearning() throws {
    try withFixture { f in
      RequestTestUtil.fillMobileRequest(&f.request)
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      do {
        segments.clear()
        initSegments(segments, 1, 2)
        let kKey = "わたしのなまえはなかのです"
        let kValue = "私の名前は中野です"
        segments.mutableSegment(0).setKey(kKey)
        let candidate = segments.mutableSegment(0).mutableCandidate(1)

        candidate.value = kValue
        candidate.contentValue = kValue
        candidate.key = kKey
        candidate.contentKey = kKey
        candidate.innerSegmentBoundary = buildInnerSegmentBoundary(
          [
            (12, 6, 9, 3),  // "わたしの, 私の", "わたし, 私"
            (12, 9, 9, 6),  // "なまえは, 名前は", "なまえ, 名前"
            (15, 12, 9, 6),  // "なかのです, 中野です", "なかの, 中野"
          ], candidate.key, candidate.value)
        candidate.lid = 10
        candidate.rid = 20

        selectCandidate(segments.mutableSegment(0), 1)

        let defaultMobileConvreq = f.createConversionRequest()
        do {
          let learningSegments = UserSegmentHistoryRewriter.makeLearningSegmentsFromInnerSegments(
            defaultMobileConvreq, segments)
          #expect(learningSegments.segmentsSize == 3)
          #expect(learningSegments.segment(0).key == "わたしの")
          #expect(learningSegments.segment(0).candidate(0).key == "わたしの")
          #expect(learningSegments.segment(0).candidate(0).value == "私の")
          #expect(learningSegments.segment(0).candidate(0).contentKey == "わたし")
          #expect(learningSegments.segment(0).candidate(0).contentValue == "私")
          #expect(learningSegments.segment(0).candidate(0).lid == 10)
          #expect(learningSegments.segment(0).candidate(0).rid == 10)
          #expect(learningSegments.segment(0).segmentType == .fixedValue)

          #expect(learningSegments.segment(1).key == "なまえは")
          #expect(learningSegments.segment(1).candidate(0).key == "なまえは")
          #expect(learningSegments.segment(1).candidate(0).value == "名前は")
          #expect(learningSegments.segment(1).candidate(0).contentKey == "なまえ")
          #expect(learningSegments.segment(1).candidate(0).contentValue == "名前")
          #expect(learningSegments.segment(1).candidate(0).lid == 0)
          #expect(learningSegments.segment(1).candidate(0).rid == 0)
          #expect(learningSegments.segment(1).segmentType == .fixedValue)

          #expect(learningSegments.segment(2).key == "なかのです")
          #expect(learningSegments.segment(2).candidate(0).key == "なかのです")
          #expect(learningSegments.segment(2).candidate(0).value == "中野です")
          #expect(learningSegments.segment(2).candidate(0).contentKey == "なかの")
          #expect(learningSegments.segment(2).candidate(0).contentValue == "中野")
          #expect(learningSegments.segment(2).candidate(0).lid == 20)
          #expect(learningSegments.segment(2).candidate(0).rid == 20)
          #expect(learningSegments.segment(2).segmentType == .fixedValue)
        }

        rewriter.finish(defaultMobileConvreq, segments)
      }

      do {
        // Inner segment boundary with size 1 may have better information.
        segments.clear()
        initSegments(segments, 1, 2)
        let kKey = "わたしの"
        let kValue = "私の"
        segments.mutableSegment(0).setKey(kKey)
        let candidate = segments.mutableSegment(0).mutableCandidate(1)

        candidate.value = kValue
        candidate.contentValue = kValue
        candidate.key = kKey
        candidate.contentKey = kKey
        // "わたしの, 私の", "わたし, 私"
        candidate.innerSegmentBoundary = buildInnerSegmentBoundary(
          [(12, 6, 9, 3)], candidate.key, candidate.value)
        candidate.lid = 10
        candidate.rid = 10

        selectCandidate(segments.mutableSegment(0), 1)

        let defaultMobileConvreq = f.createConversionRequest()
        do {
          let learningSegments = UserSegmentHistoryRewriter.makeLearningSegmentsFromInnerSegments(
            defaultMobileConvreq, segments)
          #expect(learningSegments.segmentsSize == 1)
          #expect(learningSegments.segment(0).key == "わたしの")
          #expect(learningSegments.segment(0).candidate(0).key == "わたしの")
          #expect(learningSegments.segment(0).candidate(0).value == "私の")
          #expect(learningSegments.segment(0).candidate(0).contentKey == "わたし")
          #expect(learningSegments.segment(0).candidate(0).contentValue == "私")
          #expect(learningSegments.segment(0).candidate(0).lid == 10)
          #expect(learningSegments.segment(0).candidate(0).rid == 10)
          #expect(learningSegments.segment(0).segmentType == .fixedValue)
        }

        rewriter.finish(defaultMobileConvreq, segments)
      }

      do {
        segments.clear()
        initSegments(segments, 1, 2)
        segments.mutableSegment(0).setKey("なかの")
        var candidate = segments.mutableSegment(0).mutableCandidate(0)
        candidate.value = "中埜"
        candidate.contentValue = "中埜"
        candidate.contentKey = "なかの"
        candidate.contentKey = "なかの"

        candidate = segments.mutableSegment(0).mutableCandidate(1)
        candidate.value = "中野"
        candidate.contentValue = "中野"
        candidate.contentKey = "なかの"
        candidate.contentKey = "なかの"

        let defaultMobileConvreq = f.createConversionRequest()
        #expect(rewriter.rewrite(defaultMobileConvreq, segments))
        #expect(segments.segment(0).candidate(0).value == "中野")
      }
    }
  }

  @Test func revert() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()

      do {
        initSegments(segments, 1, 2)
        segments.mutableSegment(0).setKey("abc")
        let candidate = segments.mutableSegment(0).mutableCandidate(1)
        candidate.value = "ａｂｃ"
        candidate.contentValue = "ａｂｃ"
        candidate.contentKey = "abc"
        selectCandidate(segments.mutableSegment(0), 1)
        let convreq = f.createConversionRequest()
        segments.setRevertId(10)
        rewriter.finish(convreq, segments)
      }

      rewriter.revert(segments)

      do {
        segments.clear()
        initSegments(segments, 1, 2)
        segments.mutableSegment(0).setKey("abc")
        let candidate = segments.mutableSegment(0).mutableCandidate(1)
        candidate.value = "ａｂｃ"
        candidate.contentValue = "ａｂｃ"
        candidate.contentKey = "abc"
        candidate.contentKey = "abc"
        let convreq = f.createConversionRequest()
        #expect(!rewriter.rewrite(convreq, segments))
      }
    }
  }

  @Test func widthInvariantHistoryMatchingPreservesInnerSegmentBoundary() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()
      rewriter.clear()

      let convreq = f.createConversionRequest()

      // Learn "２日" (full-width) for "ふつか".
      do {
        initSegments(segments, 1, 2)
        segments.mutableSegment(0).setKey("ふつか")
        let candidate = segments.mutableSegment(0).mutableCandidate(1)
        candidate.key = "ふつか"
        candidate.contentKey = "ふつか"
        candidate.value = "２日"
        candidate.contentValue = "２日"
        selectCandidate(segments.mutableSegment(0), 1)
        rewriter.finish(convreq, segments)
      }

      // Rewrite a segment where "2日" (half-width) has an
      // inner_segment_boundary. USHR matches width-invariantly and promotes
      // "2日" to top, without modifying its value or boundary (normalization
      // is deferred to VariantsRewriter).
      do {
        segments.clear()
        initSegments(segments, 1, 2)
        segments.mutableSegment(0).setKey("ふつか")
        let candidate = segments.mutableSegment(0).mutableCandidate(1)
        candidate.key = "ふつか"
        candidate.contentKey = "ふつか"
        candidate.value = "2日"
        candidate.contentValue = "2日"
        let boundary = [("ふつか".utf8.count, "2日".utf8.count, "ふつか".utf8.count, "2日".utf8.count)]
        candidate.innerSegmentBoundary = buildInnerSegmentBoundary(
          boundary, candidate.key, candidate.value)

        #expect(rewriter.rewrite(convreq, segments))
        let top = segments.segment(0).candidate(0)
        #expect(top.value == "2日")
        #expect(top.contentValue == "2日")
        #expect(top.innerSegmentBoundary == buildInnerSegmentBoundary(boundary, "ふつか", "2日"))
      }
    }
  }

  // Not in the C++ test: checks the on-disk value encoding of the bit-field
  // structs so that segment.db stays interoperable with C++ Mozc.
  @Test func persistedValueLayout() throws {
    try withFixture { f in
      let segments = Segments()
      let rewriter = f.createUserSegmentHistoryRewriter()
      let convreq = f.createConversionRequest()
      initSegments(segments, 1)
      selectCandidate(segments.mutableSegment(0), 2)
      rewriter.finish(convreq, segments)
      _ = rewriter.sync()

      let storage = LruStorage()
      #expect(storage.open(ConfigFileStream.getFileName("user://segment.db")))
      #expect(storage.valueSize == 4)
      #expect(storage.size == 20000)
      #expect(storage.seed == 0xf28d_efe3)
      // KeyTriggerValue: candidates_size (20) in the top byte.
      #expect(storage.lookupAsString("segment0") == [0, 0, 0, 20])
      // FeatureValue: feature_type bit = 1.
      #expect(storage.lookupAsString("S\tsegment0\tcandidate2") == [1, 0, 0, 0])
      #expect(storage.lookupAsString("C\tsegment0\tcandidate2") == [1, 0, 0, 0])
    }
  }
}
