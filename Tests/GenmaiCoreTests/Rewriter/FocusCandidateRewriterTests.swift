// Port of mozc/src/rewriter/focus_candidate_rewriter_test.cc (3.35.6354).

import GenmaiBase
import Testing

@testable import GenmaiCore

private func addCandidate(_ segment: Segment, _ value: String) {
  let c = segment.addCandidate()
  c.value = value
  c.contentValue = value
}

private func addCandidateWithContentValue(
  _ segment: Segment, _ value: String, _ contentValue: String
) {
  let c = segment.addCandidate()
  c.value = value
  c.contentValue = contentValue
}

private func makeSegments(_ count: Int) -> (Segments, [Segment]) {
  let segments = Segments()
  var seg: [Segment] = []
  for _ in 0..<count {
    seg.append(segments.addSegment())
  }
  return (segments, seg)
}

private func setIds(_ c: Candidate, _ lid: UInt16, _ rid: UInt16) {
  c.lid = lid
  c.rid = rid
}

@Suite(.enabled(if: ConverterCoreTestSupport.hasMockData, ConverterCoreTestSupport.mockDataMissing))
struct FocusCandidateRewriterTests {
  private let rewriter: any RewriterInterface

  init() throws {
    let dm = try ConverterCoreTestSupport.mockDataManager()
    rewriter = FocusCandidateRewriter(
      dm.getCounterSuffixSortedArray(), PosMatcher(dm.getPosMatcherData()))
  }

  private func makeBracketSegments() -> (Segments, [Segment]) {
    let (segments, seg) = makeSegments(4)
    addCandidate(seg[0], "｢")
    addCandidate(seg[0], "(")
    addCandidate(seg[0], "[")
    addCandidate(seg[0], "{")
    addCandidate(seg[1], "テスト")
    addCandidate(seg[1], "てすと")
    addCandidate(seg[2], "です")
    addCandidate(seg[2], "デス")
    addCandidate(seg[3], "｣")
    addCandidate(seg[3], ")")
    addCandidate(seg[3], "]")
    addCandidate(seg[3], "}")
    return (segments, seg)
  }

  private func makeNestSegments() -> (Segments, [Segment]) {
    let (segments, seg) = makeSegments(7)
    for i in [0, 2] {
      addCandidate(seg[i], "｢")
      addCandidate(seg[i], "(")
      addCandidate(seg[i], "[")
      addCandidate(seg[i], "{")
    }
    addCandidate(seg[1], "テスト1")
    addCandidate(seg[3], "テスト2")
    for i in [4, 6] {
      addCandidate(seg[i], "｣")
      addCandidate(seg[i], ")")
      addCandidate(seg[i], "]")
      addCandidate(seg[i], "}")
    }
    addCandidate(seg[5], "テスト3")
    return (segments, seg)
  }

  @Test func focusCandidateRewriterInvalidQuery() {
    let (segments, _) = makeBracketSegments()

    // invalid queries
    #expect(!rewriter.focus(segments, 5, 0))
    #expect(!rewriter.focus(segments, 0, 10))
    #expect(!rewriter.focus(segments, 1, 0))
    #expect(!rewriter.focus(segments, 2, 0))
  }

  @Test func focusCandidateRewriterLeftToRight() {
    let (segments, seg) = makeBracketSegments()

    #expect(rewriter.focus(segments, 0, 0))
    #expect(seg[3].candidate(0).contentValue == "｣")

    #expect(rewriter.focus(segments, 0, 1))
    #expect(seg[3].candidate(0).contentValue == ")")

    #expect(rewriter.focus(segments, 0, 2))
    #expect(seg[3].candidate(0).contentValue == "]")

    #expect(rewriter.focus(segments, 0, 3))
    #expect(seg[3].candidate(0).contentValue == "}")

    #expect(rewriter.focus(segments, 0, 0))
    #expect(seg[3].candidate(0).contentValue == "｣")
  }

  @Test func focusCandidateRewriterRightToLeft() {
    let (segments, seg) = makeBracketSegments()

    // right to left
    #expect(rewriter.focus(segments, 3, 0))
    #expect(seg[0].candidate(0).contentValue == "｢")

    #expect(rewriter.focus(segments, 3, 1))
    #expect(seg[0].candidate(0).contentValue == "(")

    #expect(rewriter.focus(segments, 3, 2))
    #expect(seg[0].candidate(0).contentValue == "[")

    #expect(rewriter.focus(segments, 3, 3))
    #expect(seg[0].candidate(0).contentValue == "{")

    #expect(rewriter.focus(segments, 3, 0))
    #expect(seg[0].candidate(0).contentValue == "｢")
  }

  @Test func focusCandidateRewriterLeftToRightNest() {
    let (segments, seg) = makeNestSegments()

    #expect(rewriter.focus(segments, 0, 0))
    #expect(seg[6].candidate(0).contentValue == "｣")
    #expect(seg[4].candidate(0).contentValue == "｣")

    #expect(rewriter.focus(segments, 0, 1))
    #expect(seg[6].candidate(0).contentValue == ")")
    #expect(seg[4].candidate(0).contentValue == "｣")

    #expect(rewriter.focus(segments, 2, 0))
    #expect(seg[6].candidate(0).contentValue == ")")
    #expect(seg[4].candidate(0).contentValue == "｣")

    #expect(rewriter.focus(segments, 2, 1))
    #expect(seg[6].candidate(0).contentValue == ")")
    #expect(seg[4].candidate(0).contentValue == ")")
  }

  @Test func focusCandidateRewriterRightToLeftNest() {
    let (segments, seg) = makeNestSegments()

    #expect(rewriter.focus(segments, 6, 0))
    #expect(seg[0].candidate(0).contentValue == "｢")
    #expect(seg[2].candidate(0).contentValue == "｢")

    #expect(rewriter.focus(segments, 6, 1))
    #expect(seg[0].candidate(0).contentValue == "(")
    #expect(seg[2].candidate(0).contentValue == "｢")

    #expect(rewriter.focus(segments, 4, 0))
    #expect(seg[0].candidate(0).contentValue == "(")
    #expect(seg[2].candidate(0).contentValue == "｢")

    #expect(rewriter.focus(segments, 4, 1))
    #expect(seg[0].candidate(0).contentValue == "(")
    #expect(seg[2].candidate(0).contentValue == "(")
  }

  @Test func focusCandidateRewriterMetaCandidate() {
    let (segments, seg) = makeSegments(3)
    let numTypes = TransliterationType.numT13nTypes
    let halfKatakana = TransliterationType.halfKatakana.rawValue

    func setMetaCandidates(_ segment: Segment, _ value: String, _ halfValue: String) {
      #expect(segment.metaCandidatesSize == 0)
      var metaCands: [Candidate] = []
      for _ in 0..<numTypes {
        let c = Candidate()
        c.value = value
        c.contentValue = value
        metaCands.append(c)
      }
      metaCands[halfKatakana].value = halfValue
      metaCands[halfKatakana].contentValue = halfValue
      segment.metaCandidates = metaCands
      #expect(segment.metaCandidatesSize == numTypes)
    }

    // set key
    seg[0].setKey("「")
    // set meta candidates
    setMetaCandidates(seg[0], "「", "｢")
    #expect(seg[0].metaCandidate(halfKatakana).contentValue == "｢")
    addCandidate(seg[0], "｢")
    addCandidate(seg[0], "(")
    addCandidate(seg[0], "[")
    addCandidate(seg[0], "{")

    addCandidate(seg[1], "テスト1")

    // set key
    seg[2].setKey("」")
    // set meta candidates
    setMetaCandidates(seg[2], "」", "｣")
    #expect(seg[2].metaCandidate(halfKatakana).contentValue == "｣")
    addCandidate(seg[2], "｣")
    addCandidate(seg[2], ")")
    addCandidate(seg[2], "]")
    addCandidate(seg[2], "}")

    let halfIndex = -halfKatakana - 1
    #expect(rewriter.focus(segments, 0, halfIndex))
    #expect(seg[0].candidate(0).contentValue == "｢")
    #expect(seg[2].candidate(0).contentValue == "｣")

    let validIndex = -(numTypes - 1) - 1
    #expect(rewriter.focus(segments, 0, validIndex))
    let invalidIndex = -numTypes - 1
    #expect(!rewriter.focus(segments, 0, invalidIndex))
  }

  @Test func focusCandidateRewriterNumber() {
    let (segments, seg) = makeSegments(7)

    // set key
    seg[0].setKey("2")
    addCandidate(seg[0], "2")
    addCandidate(seg[0], "２")
    addCandidate(seg[0], "ニ")
    addCandidate(seg[0], "弐")

    seg[0].mutableCandidate(2).style = .numberKanji
    seg[0].mutableCandidate(3).style = .numberOldKanji

    addCandidate(seg[1], "テスト1")

    // set key
    seg[2].setKey("3")
    addCandidate(seg[2], "3")
    addCandidate(seg[2], "３")
    addCandidate(seg[2], "三")
    addCandidate(seg[2], "参")

    seg[2].mutableCandidate(2).style = .numberKanji
    seg[2].mutableCandidate(3).style = .numberOldKanji

    seg[3].setKey("4")
    addCandidate(seg[3], "4")
    addCandidate(seg[3], "４")
    addCandidate(seg[3], "四")
    seg[3].mutableCandidate(2).style = .numberKanji

    addCandidate(seg[4], "テスト1")
    addCandidate(seg[5], "テスト1")

    seg[6].setKey("4")
    addCandidate(seg[6], "4")
    addCandidate(seg[6], "４")
    addCandidate(seg[6], "四")

    seg[6].mutableCandidate(2).style = .numberKanji

    #expect(rewriter.focus(segments, 0, 0))
    #expect(seg[0].candidate(0).contentValue == "2")
    #expect(seg[2].candidate(0).contentValue == "3")
    #expect(seg[3].candidate(0).contentValue == "4")

    #expect(rewriter.focus(segments, 0, 1))
    #expect(seg[2].candidate(0).contentValue == "３")
    #expect(seg[3].candidate(0).contentValue == "４")

    #expect(seg[6].candidate(0).contentValue == "4")  // far from

    #expect(rewriter.focus(segments, 0, 2))
    #expect(seg[2].candidate(0).contentValue == "三")
    #expect(seg[3].candidate(0).contentValue == "四")

    #expect(seg[6].candidate(0).contentValue == "4")  // far from

    #expect(rewriter.focus(segments, 0, 3))
    #expect(seg[2].candidate(0).contentValue == "参")
    #expect(seg[6].candidate(0).contentValue == "4")  // far from
  }

  // Bug #4596846: Non-number characters are changed to numbers
  @Test func dontChangeNonNumberSegment() {
    let (segments, seg) = makeSegments(2)

    // set key
    seg[0].setKey("1")
    addCandidate(seg[0], "1")
    addCandidate(seg[0], "１")
    addCandidate(seg[1], "語")
    addCandidate(seg[1], "５")

    // Should not change a segment that doesn't have a number as its first
    // candidate.
    #expect(!rewriter.focus(segments, 0, 1))
    #expect(seg[1].candidate(0).contentValue != "５")
  }

  @Test func focusCandidateRewriterSuffix() {
    do {
      let (segments, seg) = makeSegments(6)

      seg[0].setKey("2")
      addCandidate(seg[0], "2")

      seg[1].setKey("かい")
      addCandidate(seg[1], "回")
      addCandidate(seg[1], "階")

      seg[2].setKey("3")
      addCandidate(seg[2], "3")

      seg[3].setKey("かい")
      addCandidate(seg[3], "回")
      addCandidate(seg[3], "階")

      seg[4].setKey("4")
      addCandidate(seg[4], "4")

      seg[5].setKey("かい")
      addCandidate(seg[5], "回")
      addCandidate(seg[5], "階")

      #expect(rewriter.focus(segments, 1, 1))
      #expect(seg[3].candidate(0).contentValue == "階")
      #expect(seg[5].candidate(0).contentValue == "階")
    }

    // No Number (the C++ test has this block twice).
    for _ in 0..<2 {
      let (segments, seg) = makeSegments(3)

      seg[0].setKey("かい")
      addCandidate(seg[0], "回")
      addCandidate(seg[0], "階")

      seg[1].setKey("3")
      addCandidate(seg[1], "3")

      seg[2].setKey("かい")
      addCandidate(seg[2], "回")
      addCandidate(seg[2], "階")
      #expect(!rewriter.focus(segments, 0, 1))
    }

    // No number
    do {
      let (segments, seg) = makeSegments(3)

      seg[0].setKey("2")
      addCandidate(seg[0], "2")

      seg[1].setKey("かい")
      addCandidate(seg[1], "回")
      addCandidate(seg[1], "階")
      seg[2].setKey("かい")
      addCandidate(seg[2], "回")
      addCandidate(seg[2], "階")

      #expect(!rewriter.focus(segments, 1, 1))
    }
  }

  @Test func numberAndSuffixCompound() {
    let kNounId: UInt16 = 1939
    let kParallelMarkerYa: UInt16 = 290

    // Test for reranking of number compound pattern:
    do {
      // Test scenario: Construct the following segments:
      //           Seg 0       Seg 1
      //        | "いっかい" | "にかい" |
      // cand 0 | "一階"    | "2階"   |
      // cand 1 | "一回"    | "二階"   |
      // cand 2 |          | "二回"   |
      //
      // Then, focusing on (Seg 0, cand 1) should move "二回" in Seg 1 to the top.
      let (segments, seg) = makeSegments(2)
      seg[0].setKey("いっかい")
      addCandidate(seg[0], "一階")
      addCandidate(seg[0], "一回")

      seg[1].setKey("にかい")
      addCandidate(seg[1], "2階")
      addCandidate(seg[1], "二階")
      addCandidate(seg[1], "二回")

      #expect(rewriter.focus(segments, 0, 1))
      #expect(seg[1].candidate(0).value == "二回")
    }
    // Test for reranking of number compound + parallel marker pattern:
    // http://mozcsuorg.appspot.com/#issue/49
    do {
      // Test scenario: Similar to the above case, but construct the following
      // segments with parallel marker:
      //           Seg 0       Seg 1
      //        | "いっかいや" | "にかい" |
      // cand 0 | "一階や"    | "2階"    |
      // cand 1 | "一回や"    | "二階"   |
      // cand 2 |            | "二回"   |
      //
      // Then, focusing on (Seg 0, cand 1) should move "二回" in Seg 1 to the top.
      let (segments, seg) = makeSegments(2)

      seg[0].setKey("いっかいや")

      addCandidateWithContentValue(seg[0], "一階や", "一階")
      setIds(seg[0].mutableCandidate(0), kNounId, kParallelMarkerYa)

      addCandidateWithContentValue(seg[0], "一回や", "一回")
      setIds(seg[0].mutableCandidate(1), kNounId, kParallelMarkerYa)

      seg[1].setKey("にかい")
      addCandidate(seg[1], "2階")
      setIds(seg[1].mutableCandidate(0), kNounId, kNounId)
      addCandidate(seg[1], "二階")
      setIds(seg[1].mutableCandidate(1), kNounId, kNounId)
      addCandidate(seg[1], "二回")
      setIds(seg[1].mutableCandidate(2), kNounId, kNounId)

      #expect(rewriter.focus(segments, 0, 1))
      #expect(seg[1].candidate(0).value == "二回")
    }
    // Test for reranking of number compound + parallel marker pattern for 3
    // segments.
    do {
      // Test scenario: Similar to the above case, but construct the following
      // segments with parallel marker:
      //           Seg 0       Seg 1      Seg 2
      //        | "いっかいや" | "にかいや" | "さんかい"
      // cand 0 | "一階や"    | "2階や"    | "参回"
      // cand 1 | "一回や"    | "二階や"   | "3階"
      // cand 2 |            | "二回や"   | "三回"
      //
      // Then, focusing on (Seg 0, cand 1) should move "二回や" in Seg 1 and "三回
      // " in Seg 2 to the top of each segment.
      let (segments, seg) = makeSegments(3)

      seg[0].setKey("いっかいや")

      addCandidateWithContentValue(seg[0], "一階や", "一階")
      setIds(seg[0].mutableCandidate(0), kNounId, kParallelMarkerYa)

      addCandidateWithContentValue(seg[0], "一回や", "一回")
      setIds(seg[0].mutableCandidate(1), kNounId, kParallelMarkerYa)

      seg[1].setKey("にかいや")
      addCandidateWithContentValue(seg[1], "2階や", "2階")
      setIds(seg[1].mutableCandidate(0), kNounId, kParallelMarkerYa)
      addCandidateWithContentValue(seg[1], "二階や", "二階")
      setIds(seg[1].mutableCandidate(1), kNounId, kParallelMarkerYa)
      addCandidateWithContentValue(seg[1], "二回や", "二回")
      setIds(seg[1].mutableCandidate(2), kNounId, kParallelMarkerYa)

      seg[2].setKey("さんかいや")
      addCandidate(seg[2], "参回")
      setIds(seg[2].mutableCandidate(0), kNounId, kNounId)
      addCandidate(seg[2], "3階")
      setIds(seg[2].mutableCandidate(1), kNounId, kNounId)
      addCandidate(seg[2], "三回")
      setIds(seg[2].mutableCandidate(2), kNounId, kNounId)

      #expect(rewriter.focus(segments, 0, 1))
      #expect(seg[1].candidate(0).value == "二回や")
      #expect(seg[2].candidate(0).value == "三回")
    }
    // Test case where two number segments are too far to be rewritten.
    do {
      // Test scenario: Similar to the above case, but construct the following
      // segments with parallel marker:
      //           Seg 0       Seg 1 Seg 2   Seg 3 Seg 4
      //        | "いっかいや" | "あ" | "あ" | "あ" | "にかい"
      // cand 0 | "一階や"    | "あ" | "あ" | "あ" | "2階"
      // cand 1 | "一回や"    |      |     |      | "二回"
      //
      // Then, focusing on (Seg 0, cand 1) cannot move "二回" in Seg 3 to the top.
      let (segments, seg) = makeSegments(5)

      seg[0].setKey("いっかいや")

      addCandidateWithContentValue(seg[0], "一階や", "一階")
      setIds(seg[0].mutableCandidate(0), kNounId, kParallelMarkerYa)

      addCandidateWithContentValue(seg[0], "一回や", "一回")
      setIds(seg[0].mutableCandidate(1), kNounId, kParallelMarkerYa)

      for i in 1...3 {
        seg[i].setKey("あ")
        addCandidate(seg[i], "あ")
        setIds(seg[i].mutableCandidate(0), kNounId, kNounId)
      }

      seg[4].setKey("にかい")
      addCandidate(seg[4], "2階")
      setIds(seg[4].mutableCandidate(0), kNounId, kNounId)
      addCandidate(seg[4], "二回")
      setIds(seg[4].mutableCandidate(0), kNounId, kNounId)

      #expect(!rewriter.focus(segments, 0, 1))
    }
    // Test for the case where we shouldn't rewrite.
    do {
      // Test scenario: Similar to the above cases, but construct the following
      // segments with particles へ and は:
      //           Seg 0       Seg 1        Seg 2
      //        | "いっかいへは" | "にかい" | "いった"
      // cand 0 | "一階へは"    | "二回"   | "行った"
      // cand 1 | "一回へは"    | "ニ階"   |
      // cand 2 |              | "2回"   |
      //
      // Here, "一階へは" has the following structure:
      // "一階(noun)" + "へ(格助詞)" + "は(係助詞)"
      // For this case, focusing on (Seg 0, cand 1) should not move "二階" in Seg
      // 1 to the top.
      let (segments, seg) = makeSegments(3)

      let kKakariJoshiHa: UInt16 = 299
      let kIkuTaSetsuzoku: UInt16 = 1501
      let kJodoushiTa: UInt16 = 161

      seg[0].setKey("いっかいへは")

      addCandidateWithContentValue(seg[0], "一階へは", "一階")
      setIds(seg[0].mutableCandidate(0), kNounId, kKakariJoshiHa)

      addCandidateWithContentValue(seg[0], "一回へは", "一回")
      setIds(seg[0].mutableCandidate(1), kNounId, kKakariJoshiHa)

      seg[1].setKey("にかい")
      addCandidate(seg[1], "二回")
      setIds(seg[1].mutableCandidate(0), kNounId, kNounId)
      addCandidate(seg[1], "二階")
      setIds(seg[1].mutableCandidate(1), kNounId, kNounId)
      addCandidate(seg[1], "2階")
      setIds(seg[1].mutableCandidate(2), kNounId, kNounId)

      seg[2].setKey("いった")
      addCandidate(seg[2], "行った")
      setIds(seg[2].mutableCandidate(0), kIkuTaSetsuzoku, kJodoushiTa)

      #expect(!rewriter.focus(segments, 0, 1))
    }
  }
}
