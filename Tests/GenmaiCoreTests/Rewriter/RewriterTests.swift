// Port of mozc/src/rewriter/rewriter_test.cc (3.35.6354).
//
// The C++ fixture builds engine::Modules from the MockDataManager; here
// `RewriterTestModules` wraps the converter tests' TestModules. Each test runs
// in a temporary user profile (testing::TestWithTempUserProfile) with an
// isolated CharacterFormManager (the C++ TearDown resets the singleton).

import GenmaiBase
import GenmaiProtocol
import Testing
@testable import GenmaiCore

/// engine::Modules for the rewriter tests.
final class RewriterTestModules: RewriterModules, @unchecked Sendable {
  let base: TestModules
  let singleKanjiDictionary: SingleKanjiDictionary

  init(_ base: TestModules) {
    self.base = base
    singleKanjiDictionary = SingleKanjiDictionary(base.dataManager.getSingleKanjiRewriterData())
  }

  static func mock() throws -> RewriterTestModules { RewriterTestModules(try TestModules.mock()) }

  func getDataManager() -> DataManager { base.dataManager }
  func getDictionary() -> any DictionaryInterface { base.dictionary }
  func getPosMatcher() -> PosMatcher { base.posMatcher }
  func getPosGroup() -> PosGroup { base.posGroup }
  func getSingleKanjiDictionary() -> SingleKanjiDictionary { singleKanjiDictionary }
  func getReadingAlignmentSupplementalModel() -> (any ReadingAlignmentSupplementalModel)? { nil }
}

@Suite(.enabled(if: MockDataManager.defaultDataPath != nil, "mock_genmai.data is missing"))
struct RewriterTests {
  private static func commandCandidatesSize(_ segment: Segment) -> Int {
    var result = 0
    for i in 0..<segment.candidatesSize
    where segment.candidate(i).attributes & Attribute.commandCandidate != 0 {
      result += 1
    }
    return result
  }

  /// SetUp / TearDown of the C++ fixture.
  private static func withFixture(
    _ body: (RewriterTestModules, CharacterFormManager) throws -> Void
  ) throws {
    try SystemUtil.withTempUserProfile { _ in
      let manager = CharacterFormManager()
      try CharacterFormManager.withScopedManagerForTesting(manager) {
        let modules = try RewriterTestModules.mock()
        try body(modules, manager)
      }
    }
  }

  // Command rewriter should be disabled on Android build. b/5851240
  @Test func commandRewriterAvailability() throws {
    try Self.withFixture { modules, _ in
      let rewriter: any RewriterInterface = RewriterImpl(modules)
      let segments = Segments()
      let request = ConversionRequest()
      let seg = segments.pushBackSegment()

      do {
        let candidate = seg.addCandidate()
        seg.setKey("こまんど")
        candidate.value = "コマンド"
        #expect(rewriter.rewrite(request, segments))
        #expect(Self.commandCandidatesSize(seg) == 2)
        seg.clearCandidates()
      }

      do {
        let candidate = seg.addCandidate()
        seg.setKey("さじぇすと")
        candidate.value = "サジェスト"
        #expect(rewriter.rewrite(request, segments))
        #expect(Self.commandCandidatesSize(seg) == 1)
        seg.clearCandidates()
      }
    }
  }

  @Test func emoticonsAboveSymbols() throws {
    try Self.withFixture { modules, _ in
      let rewriter: any RewriterInterface = RewriterImpl(modules)
      let kKey = "かおもじ"
      let kEmoticon = "^^;"
      let kSymbol = "☹"  // A platform-dependent symbol

      let request = ConversionRequest()
      let segments = Segments()
      let seg = segments.pushBackSegment()
      let candidate = seg.addCandidate()
      seg.setKey(kKey)
      candidate.value = kKey
      #expect(seg.candidatesSize == 1)
      #expect(rewriter.rewrite(request, segments))
      #expect(1 < seg.candidatesSize)

      var emoticonIndex = -1
      var symbolIndex = -1
      for i in 0..<seg.candidatesSize {
        if seg.candidate(i).value.bytesEqual(kEmoticon) {
          emoticonIndex = i
        } else if seg.candidate(i).value.bytesEqual(kSymbol) {
          symbolIndex = i
        }
      }
      #expect(emoticonIndex != -1)
      #expect(symbolIndex != -1)
      #expect(emoticonIndex < symbolIndex)
    }
  }

  @Test func userSegmentHistoryAndVariantsRewriterIntegration() throws {
    try Self.withFixture { modules, manager in
      let rewriter = RewriterImpl(modules, useHistoryRewriter: true)

      manager.setDefaultRule()
      manager.clearHistory()
      manager.addConversionRule("0", .fullWidth)

      let request = ConversionRequest()

      let segments = Segments()
      var seg = segments.pushBackSegment()
      seg.setKey("ふつか")

      // Step 1: Learn "2日" (half-width '2') for "ふつか".
      do {
        let c0 = seg.addCandidate()
        c0.key = "ふつか"
        c0.contentKey = "ふつか"
        c0.value = "二日"
        c0.contentValue = "二日"

        let c1 = seg.addCandidate()
        c1.key = "ふつか"
        c1.contentKey = "ふつか"
        c1.value = "2日"
        c1.contentValue = "2日"

        seg.moveCandidate(1, 0)
        seg.mutableCandidate(0).attributes |= Attribute.reranked
        seg.setSegmentType(.fixedValue)

        rewriter.finish(request, segments)
      }

      // Step 2: Rewrite "ふつか".
      // USHR promotes "2日", and VariantsRewriter immediately normalizes it to
      // "２日" according to user preference, updates inner_segment_boundary, and
      // expands alternatives.
      do {
        segments.clear()
        seg = segments.pushBackSegment()
        seg.setKey("ふつか")

        let c0 = seg.addCandidate()
        c0.key = "ふつか"
        c0.contentKey = "ふつか"
        c0.value = "二日"
        c0.contentValue = "二日"

        let c1 = seg.addCandidate()
        c1.key = "ふつか"
        c1.contentKey = "ふつか"
        c1.value = "2日"
        c1.contentValue = "2日"
        c1.innerSegmentBoundary = buildInnerSegmentBoundary(
          [("ふつか".utf8.count, "2日".utf8.count, "ふつか".utf8.count, "2日".utf8.count)],
          c1.key, c1.value)

        #expect(rewriter.rewrite(request, segments))
        try #require(seg.candidatesSize > 0)
        let top = seg.candidate(0)
        #expect(top.value == "２日")
        #expect(top.contentValue == "２日")
        #expect(
          top.innerSegmentBoundary
            == buildInnerSegmentBoundary(
              [("ふつか".utf8.count, "２日".utf8.count, "ふつか".utf8.count, "２日".utf8.count)],
              "ふつか", "２日"))
      }
    }
  }

  @Test func zipcodeCandidatesDescription() throws {
    try Self.withFixture { modules, _ in
      let rewriter: any RewriterInterface = RewriterImpl(modules)
      let request = ConversionRequest()
      let segments = Segments()
      let seg = segments.pushBackSegment()
      seg.setKey("107-0052")
      let candidate = seg.addCandidate()
      candidate.key = "107-0052"
      candidate.contentKey = "107-0052"
      candidate.value = "東京都港区赤坂"
      candidate.contentValue = "東京都港区赤坂"
      candidate.lid = modules.getPosMatcher().getZipcodeId()
      candidate.rid = modules.getPosMatcher().getZipcodeId()

      #expect(rewriter.rewrite(request, segments))
      var foundZipcodeCandidate = false
      for i in 0..<seg.candidatesSize where seg.candidate(i).description == "郵便番号と住所" {
        foundZipcodeCandidate = true
        break
      }
      #expect(foundZipcodeCandidate)
    }
  }

  @Test func preservesNoVariantsExpansionThroughPipeline() throws {
    try Self.withFixture { modules, manager in
      let rewriter = RewriterImpl(modules, useHistoryRewriter: true)

      manager.setDefaultRule()
      manager.clearHistory()
      // Set default rule for alphabet to FULL_WIDTH.
      manager.addConversionRule("A", .fullWidth)

      let request = ConversionRequest()
      let segments = Segments()
      var seg = segments.pushBackSegment()
      seg.setKey("ぐーぐる")

      // Step 1: Learn "Google" with NO_VARIANTS_EXPANSION.
      do {
        let c0 = seg.addCandidate()
        c0.key = "ぐーぐる"
        c0.contentKey = "ぐーぐる"
        c0.value = "グーグル"
        c0.contentValue = "グーグル"

        let c1 = seg.addCandidate()
        c1.key = "ぐーぐる"
        c1.contentKey = "ぐーぐる"
        c1.value = "Google"
        c1.contentValue = "Google"
        c1.attributes |= Attribute.noVariantsExpansion

        seg.moveCandidate(1, 0)
        seg.mutableCandidate(0).attributes |= Attribute.reranked
        seg.setSegmentType(.fixedValue)

        rewriter.finish(request, segments)
      }

      // Step 2: Rewrite "ぐーぐる".
      // Even though alphabet preference is FULL_WIDTH, promoted "Google" must
      // retain NO_VARIANTS_EXPANSION and NOT be converted to full-width
      // "Ｇｏｏｇｌｅ".
      do {
        segments.clear()
        seg = segments.pushBackSegment()
        seg.setKey("ぐーぐる")

        let c0 = seg.addCandidate()
        c0.key = "ぐーぐる"
        c0.contentKey = "ぐーぐる"
        c0.value = "グーグル"
        c0.contentValue = "グーグル"

        let c1 = seg.addCandidate()
        c1.key = "ぐーぐる"
        c1.contentKey = "ぐーぐる"
        c1.value = "Google"
        c1.contentValue = "Google"
        c1.attributes |= Attribute.noVariantsExpansion

        #expect(rewriter.rewrite(request, segments))
        try #require(seg.candidatesSize > 0)
        let top = seg.candidate(0)
        #expect(top.value == "Google")
        #expect(top.attributes & Attribute.noVariantsExpansion != 0)
      }
    }
  }
}
