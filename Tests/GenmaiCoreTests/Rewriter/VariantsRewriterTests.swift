// Port of mozc/src/rewriter/variants_rewriter_test.cc (3.35.6354).
//
// Deviations from C++:
// - The fixture (TestWithTempUserProfile + CharacterFormManager reset) is
//   `withFixture`, which also installs a fresh task-local CharacterFormManager
//   so that tests can run in parallel.

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private typealias Config = Genmai_Config_Config

private struct Fixture {
  let posMatcher: PosMatcher
  let manager: CharacterFormManager

  func createVariantsRewriter() -> VariantsRewriter { VariantsRewriter(posMatcher) }
}

private func withFixture(_ body: (Fixture) throws -> Void) throws {
  let dataManager = try MockDataManager()
  try withExtendedLifetime(dataManager) {
    let posMatcher = PosMatcher(dataManager.getPosMatcherData())
    try SystemUtil.withTempUserProfile { _ in
      let manager = CharacterFormManager()
      // Reset()
      manager.setDefaultRule()
      manager.clearHistory()
      try CharacterFormManager.withScopedManagerForTesting(manager) {
        try body(Fixture(posMatcher: posMatcher, manager: manager))
      }
    }
  }
}

private func initSegmentsForAlphabetRewrite(_ value: String, _ segments: Segments) {
  let segment = segments.pushBackSegment()
  segment.setKey(value)
  let candidate = segment.addCandidate()
  candidate.key = value
  candidate.contentKey = value
  candidate.value = value
  candidate.contentValue = value
}

private func makeCandidate(_ value: String, _ contentKey: String, description: String = "")
  -> Candidate
{
  let candidate = Candidate()
  candidate.value = value
  candidate.contentValue = candidate.value
  candidate.contentKey = contentKey
  candidate.description = description
  return candidate
}

@Suite(
  "VariantsRewriter",
  .enabled(if: MockDataManager.defaultDataPath != nil, "mock_genmai.data is not built"))
struct VariantsRewriterTests {
  @Test func rewriteTest() throws {
    try withFixture { f in
      let rewriter = f.createVariantsRewriter()
      let segments = Segments()
      let request = ConversionRequest()
      let manager = CharacterFormManager.getCharacterFormManager()

      let seg = segments.pushBackSegment()

      do {
        let candidate = seg.addCandidate()
        candidate.value = "あいう"
        candidate.contentValue = "あいう"
        #expect(!rewriter.rewrite(request, segments))
        seg.clearCandidates()
      }

      do {
        let candidate = seg.addCandidate()
        candidate.value = "012"
        candidate.contentValue = "012"
        manager.setCharacterForm("012", .fullWidth)

        #expect(rewriter.rewrite(request, segments))
        #expect(seg.candidatesSize == 2)
        #expect(seg.candidate(0).value == "０１２")
        #expect(seg.candidate(0).contentValue == "０１２")
        #expect(seg.candidate(1).value == "012")
        #expect(seg.candidate(1).contentValue == "012")
        seg.clearCandidates()
      }

      do {
        let candidate = seg.addCandidate()
        candidate.value = "012"
        candidate.contentValue = "012"
        candidate.attributes |= Attribute.noVariantsExpansion
        manager.setCharacterForm("012", .fullWidth)

        #expect(!rewriter.rewrite(request, segments))
        #expect(seg.candidatesSize == 1)
        seg.clearCandidates()
      }

      do {
        let candidate = seg.addCandidate()
        candidate.value = "Google"
        candidate.contentValue = "Google"
        manager.setCharacterForm("abc", .fullWidth)

        #expect(rewriter.rewrite(request, segments))
        #expect(seg.candidatesSize == 2)
        #expect(seg.candidate(0).value == "Ｇｏｏｇｌｅ")
        #expect(seg.candidate(0).contentValue == "Ｇｏｏｇｌｅ")
        #expect(seg.candidate(1).value == "Google")
        #expect(seg.candidate(1).contentValue == "Google")
        seg.clearCandidates()
      }

      do {
        let candidate = seg.addCandidate()
        candidate.value = "@"
        candidate.contentValue = "@"
        manager.setCharacterForm("@", .fullWidth)

        #expect(rewriter.rewrite(request, segments))
        #expect(seg.candidatesSize == 2)
        #expect(seg.candidate(0).value == "＠")
        #expect(seg.candidate(0).contentValue == "＠")
        #expect(seg.candidate(1).value == "@")
        #expect(seg.candidate(1).contentValue == "@")
        seg.clearCandidates()
      }

      do {
        let candidate = seg.addCandidate()
        candidate.value = "グーグル"
        candidate.contentValue = "グーグル"
        manager.setCharacterForm("アイウ", .fullWidth)

        #expect(!rewriter.rewrite(request, segments))
        seg.clearCandidates()
      }

      do {
        let candidate = seg.addCandidate()
        candidate.value = "グーグル"
        candidate.contentValue = "グーグル"
        manager.addConversionRule("アイウ", .halfWidth)

        #expect(rewriter.rewrite(request, segments))
        #expect(seg.candidatesSize == 2)
        #expect(seg.candidate(0).value == "ｸﾞｰｸﾞﾙ")
        #expect(seg.candidate(0).contentValue == "ｸﾞｰｸﾞﾙ")
        #expect(seg.candidate(1).value == "グーグル")
        #expect(seg.candidate(1).contentValue == "グーグル")
        seg.clearCandidates()
      }
    }
  }

  @Test func rewriteTestManyCandidates() throws {
    try withFixture { f in
      let rewriter = f.createVariantsRewriter()
      let segments = Segments()
      let request = ConversionRequest()
      let seg = segments.pushBackSegment()

      do {
        for i in 0..<10 {
          let candidate1 = seg.addCandidate()
          candidate1.value = String(i)
          candidate1.contentValue = String(i)
          let candidate2 = seg.addCandidate()
          candidate2.contentKey = "ぐーぐる"
          candidate2.key = "ぐーぐる"
          candidate2.value = "ぐーぐる"
          candidate2.contentValue = "ぐーぐる"
        }

        #expect(rewriter.rewrite(request, segments))
        #expect(seg.candidatesSize == 30)

        for i in 0..<10 {
          #expect(seg.candidate(3 * i + 1).value == String(i))
          #expect(seg.candidate(3 * i + 1).contentValue == String(i))
          let fullWidth = Japanese.halfWidthToFullWidth(seg.candidate(3 * i + 1).value)
          #expect(seg.candidate(3 * i).value == fullWidth)
          #expect(seg.candidate(3 * i).contentValue == fullWidth)
          #expect(seg.candidate(3 * i + 2).value == "ぐーぐる")
          #expect(seg.candidate(3 * i + 2).contentValue == "ぐーぐる")
        }
      }

      do {
        seg.clear()

        for i in 0..<10 {
          let candidate1 = seg.addCandidate()
          candidate1.contentKey = "ぐーぐる"
          candidate1.key = "ぐーぐる"
          candidate1.value = "ぐーぐる"
          candidate1.contentValue = "ぐーぐる"
          let candidate2 = seg.addCandidate()
          candidate2.value = String(i)
          candidate2.contentValue = String(i)
        }

        #expect(rewriter.rewrite(request, segments))
        #expect(seg.candidatesSize == 30)

        for i in 0..<10 {
          #expect(seg.candidate(3 * i + 2).value == String(i))
          #expect(seg.candidate(3 * i + 2).contentValue == String(i))
          let fullWidth = Japanese.halfWidthToFullWidth(seg.candidate(3 * i + 2).value)
          #expect(seg.candidate(3 * i + 1).value == fullWidth)
          #expect(seg.candidate(3 * i + 1).contentValue == fullWidth)
          #expect(seg.candidate(3 * i).value == "ぐーぐる")
          #expect(seg.candidate(3 * i).contentValue == "ぐーぐる")
        }
      }
    }
  }

  @Test func setDescriptionForCandidate() throws {
    try withFixture { f in
      let pm = f.posMatcher
      let full = VariantsRewriter.kFullWidth
      let half = VariantsRewriter.kHalfWidth
      do {
        let candidate = makeCandidate("HalfASCII", "halfascii")
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        // "アルファベット"
        #expect(candidate.description == VariantsRewriter.kAlphabet)
      }
      do {
        let candidate = makeCandidate("ＦｕｌｌＡＳＣＩＩ", "fullascii")
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        // "[全] アルファベット"
        #expect(candidate.description == "\(full) \(VariantsRewriter.kAlphabet)")
      }
      // Ensure SetDescriptionForCandidate rebuilds description even when the
      // candidate already carries NO_EXTRA_DESCRIPTION (e.g. when called from
      // UserSegmentHistoryRewriter after candidate copying; b/3493644).
      // (The C++ test has this block twice.)
      for _ in 0..<2 {
        let candidate = makeCandidate("ＦｕｌｌＡＳＣＩＩ", "fullascii")
        candidate.attributes = Attribute.noExtraDescription
        candidate.description = ""
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        #expect(candidate.description == "\(full) \(VariantsRewriter.kAlphabet)")
        #expect(candidate.attributes & Attribute.noExtraDescription != 0)
      }
      do {
        let candidate = makeCandidate("コギトエルゴスム", "こぎとえるごすむ")
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        // "カタカナ"
        #expect(candidate.description == VariantsRewriter.kKatakana)
      }
      do {
        let candidate = makeCandidate("ｺｷﾞﾄｴﾙｺﾞｽﾑ", "こぎとえるごすむ")
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        // "[半] カタカナ"
        #expect(candidate.description == "\(half) \(VariantsRewriter.kKatakana)")
      }
      do {
        let candidate = makeCandidate("123", "123")
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        // "数字"
        #expect(candidate.description == VariantsRewriter.kNumber)
      }
      do {
        let candidate = makeCandidate("１２３", "123")
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        // "[全] 数字"
        #expect(candidate.description == "\(full) \(VariantsRewriter.kNumber)")
      }
      // containing symbols
      do {
        let candidate = makeCandidate("Half ASCII", "half ascii")
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        #expect(candidate.description == VariantsRewriter.kAlphabet)
      }
      do {
        let candidate = makeCandidate("Half!ASCII!", "half!ascii!")
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        #expect(candidate.description == VariantsRewriter.kAlphabet)
      }
      do {
        let candidate = makeCandidate("CD-ROM", "しーでぃーろむ")
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        #expect(candidate.description == VariantsRewriter.kAlphabet)
      }
      do {
        let candidate = makeCandidate("コギト・エルゴ・スム", "こぎとえるごすむ")
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        #expect(candidate.description == VariantsRewriter.kKatakana)
      }
      do {
        let candidate = makeCandidate("!@#", "!@#")
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        #expect(candidate.description == half)
      }
      do {
        let candidate = makeCandidate("「ＡＢＣ」", "[ABC]")
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        // "[全] アルファベット"
        #expect(candidate.description == "\(full) \(VariantsRewriter.kAlphabet)")
      }
      do {
        let candidate = makeCandidate("\\", "えん")
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        #expect(candidate.description == "[半] バックスラッシュ")
      }
      do {
        let candidate = makeCandidate("＼", "ばっくすらっしゅ")  // Full-width backslash
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        #expect(candidate.description == "[全] バックスラッシュ")
      }
      do {
        let candidate = makeCandidate("¥", "えん")  // Half-width yen-symbol
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        #expect(candidate.description == "[半] 円記号")
      }
      do {
        let candidate = makeCandidate("￥", "えん")  // Full-width yen-symbol
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        #expect(candidate.description == "[全] 円記号")
      }
      do {
        let candidate = makeCandidate("~", "~")  // Tilde
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        #expect(candidate.description == "[半] チルダ")
      }
      do {
        // An emoji character of mouse face.
        let candidate = makeCandidate("🐭", "ねずみ", description: "絵文字")
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        #expect(candidate.description == "絵文字")
      }
      do {
        // A symbol representing "パーセント".
        let candidate = makeCandidate("㌫", "ぱーせんと", description: "単位")
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        #expect(candidate.description == "単位")
      }
      do {
        // Minus sign.
        let candidate = makeCandidate("−", "まいなす", description: "マイナス")
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        #expect(candidate.description == "[全] マイナス")
      }
      // Mixed-script words with numbers or alphabets
      do {
        let candidate = makeCandidate("4時", "よじ")
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        #expect(candidate.description == "")
      }
      do {
        let candidate = makeCandidate("４時", "よじ")
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        #expect(candidate.description == full)
      }
      do {
        let candidate = makeCandidate("Tシャツ", "てぃーしゃつ")
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        #expect(candidate.description == "")
      }
      do {
        let candidate = makeCandidate("Ｔシャツ", "てぃーしゃつ")
        VariantsRewriter.setDescriptionForCandidate(pm, candidate)
        #expect(candidate.description == full)
      }
    }
  }

  @Test func setDescriptionForTransliteration() throws {
    try withFixture { f in
      let pm = f.posMatcher
      do {
        let candidate = makeCandidate("HalfASCII", "halfascii")
        VariantsRewriter.setDescriptionForTransliteration(pm, candidate)
        // "アルファベット"
        #expect(candidate.description == VariantsRewriter.kAlphabet)
      }
      do {
        let candidate = makeCandidate("!@#", "!@#")
        VariantsRewriter.setDescriptionForTransliteration(pm, candidate)
        // "[半]"
        #expect(candidate.description == VariantsRewriter.kHalfWidth)
      }
      do {
        let candidate = makeCandidate("「ＡＢＣ」", "[ABC]")
        VariantsRewriter.setDescriptionForTransliteration(pm, candidate)
        // "[全] アルファベット"
        #expect(
          candidate.description == "\(VariantsRewriter.kFullWidth) \(VariantsRewriter.kAlphabet)")
      }
      do {
        // A symbol representing "パーセント".
        let candidate = makeCandidate("㌫", "ぱーせんと", description: "単位")
        VariantsRewriter.setDescriptionForTransliteration(pm, candidate)
        #expect(candidate.description == "単位")
      }
      do {
        // Minus sign.
        let candidate = makeCandidate("−", "まいなす", description: "マイナス")
        VariantsRewriter.setDescriptionForTransliteration(pm, candidate)
        #expect(candidate.description == "[全] マイナス")
      }
    }
  }

  @Test func setDescriptionForPrediction() throws {
    try withFixture { f in
      let pm = f.posMatcher
      let cases: [(String, String)] = [
        ("HalfASCII", "halfascii"),
        // containing symbols
        ("Half ASCII", "half ascii"),
        ("Half!ASCII!", "half!ascii!"),
        ("CD-ROM", "しーでぃーろむ"),
        ("!@#", "!@#"),
        ("「ＡＢＣ」", "[ABC]"),
        // A symbol representing "パーセント".
        ("㌫", "ぱーせんと"),
        // Minus sign.
        ("−", "まいなす"),
      ]
      for (value, contentKey) in cases {
        let candidate = makeCandidate(value, contentKey)
        VariantsRewriter.setDescriptionForPrediction(pm, candidate)
        #expect(candidate.description == "", "\(value)")
      }
    }
  }

  @Test func getFormTypesFromStringPair() {
    typealias Pair = (Util.FormType, Util.FormType)
    let kUnknownForm: Pair = (.unknownForm, .unknownForm)
    func get(_ a: String, _ b: String) -> Pair {
      VariantsRewriter.getFormTypesFromStringPair(a, b)
    }
    #expect(get("", "") == kUnknownForm)
    #expect(get("abc", "ab") == kUnknownForm)
    #expect(get("abc", "abc") == kUnknownForm)
    #expect(get("12", "12") == kUnknownForm)
    #expect(get("あいう", "あいう") == kUnknownForm)
    #expect(get("アイウ", "アイウ") == kUnknownForm)
    #expect(get("愛", "恋") == kUnknownForm)

    let kHalfFullPair: Pair = (.halfWidth, .fullWidth)
    let kFullHalfPair: Pair = (.fullWidth, .halfWidth)

    #expect(get("ABC", "ＡＢＣ") == kHalfFullPair)
    #expect(get("ａｂｃ", "abc") == kFullHalfPair)
    #expect(get("おばQ", "おばＱ") == kHalfFullPair)
    #expect(get("よろしくヨロシク", "よろしくﾖﾛｼｸ") == kFullHalfPair)
    #expect(get("よろしくグーグル", "よろしくｸﾞｰｸﾞﾙ") == kFullHalfPair)
    // semi voice sound mark
    #expect(get("カッパよろしくグーグル", "ｶｯﾊﾟよろしくｸﾞｰｸﾞﾙ") == kFullHalfPair)
    #expect(get("ヨロシクＱ", "ﾖﾛｼｸQ") == kFullHalfPair)
    // // mixed
    #expect(get("ヨロシクQ", "ﾖﾛｼｸＱ") == kUnknownForm)
    #expect(get("京都Qぐーぐる", "京都Ｑぐーぐる") == kHalfFullPair)
  }

  @Test func rewriteForConversion() throws {
    try withFixture { f in
      let characterFormManager = CharacterFormManager.getCharacterFormManager()
      let rewriter = f.createVariantsRewriter()
      let request = ConversionRequest()
      do {
        let segments = Segments()
        initSegmentsForAlphabetRewrite("abc", segments)
        #expect(rewriter.rewrite(request, segments))
        #expect(segments.segmentsSize == 1)
        #expect(segments.segment(0).candidatesSize == 2)

        #expect(characterFormManager.getConversionCharacterForm("abc") == .fullWidth)

        #expect(segments.segment(0).candidate(0).value == "ａｂｃ")
        #expect(segments.segment(0).candidate(1).value == "abc")
      }
      do {
        characterFormManager.setCharacterForm("abc", .halfWidth)
        let segments = Segments()
        initSegmentsForAlphabetRewrite("abc", segments)
        #expect(rewriter.rewrite(request, segments))
        #expect(segments.segmentsSize == 1)
        #expect(segments.segment(0).candidatesSize == 2)

        #expect(characterFormManager.getConversionCharacterForm("abc") == .halfWidth)

        #expect(segments.segment(0).candidate(0).value == "abc")
        #expect(segments.segment(0).candidate(1).value == "ａｂｃ")
      }
      do {
        let segments = Segments()
        do {
          let segment = segments.pushBackSegment()
          segment.setKey("~")
          let candidate = segment.addCandidate()
          candidate.key = "~"
          candidate.contentKey = "~"
          candidate.value = "〜"
          candidate.contentValue = "〜"
          candidate.description = "波ダッシュ"
        }
        #expect(rewriter.rewrite(request, segments))
        #expect(segments.segmentsSize == 1)
        #expect(segments.segment(0).candidatesSize == 2)

        #expect(characterFormManager.getConversionCharacterForm("~") == .fullWidth)

        #expect(segments.segment(0).candidate(0).value == "〜")
        #expect(segments.segment(0).candidate(0).description == "[全] 波ダッシュ")
        #expect(segments.segment(0).candidate(1).value == "~")
        #expect(segments.segment(0).candidate(1).description == "[半] チルダ")
      }
    }
  }

  @Test func rewriteForPrediction() throws {
    try withFixture { f in
      let characterFormManager = CharacterFormManager.getCharacterFormManager()
      let rewriter = f.createVariantsRewriter()
      let request = ConversionRequestBuilder().setRequestType(.prediction).build()
      do {
        let segments = Segments()
        initSegmentsForAlphabetRewrite("abc", segments)
        #expect(rewriter.rewrite(request, segments))
        #expect(segments.segmentsSize == 1)
        #expect(segments.segment(0).candidatesSize == 2)

        #expect(characterFormManager.getConversionCharacterForm("abc") == .fullWidth)

        #expect(segments.segment(0).candidate(0).value == "ａｂｃ")
        #expect(segments.segment(0).candidate(1).value == "abc")
      }
      do {
        characterFormManager.setCharacterForm("abc", .halfWidth)
        let segments = Segments()
        initSegmentsForAlphabetRewrite("abc", segments)
        #expect(rewriter.rewrite(request, segments))
        #expect(segments.segmentsSize == 1)
        #expect(segments.segment(0).candidatesSize == 2)

        #expect(characterFormManager.getConversionCharacterForm("abc") == .halfWidth)

        #expect(segments.segment(0).candidate(0).value == "abc")
        #expect(segments.segment(0).candidate(1).value == "ａｂｃ")
      }
    }
  }

  @Test func rewriteForMixedConversion() throws {
    try withFixture { f in
      let characterFormManager = CharacterFormManager.getCharacterFormManager()
      let rewriter = f.createVariantsRewriter()
      var request = Genmai_Commands_Request()
      request.mixedConversion = true  // Request mixed conversion.
      let convRequest = ConversionRequestBuilder()
        .setRequest(request)
        .setRequestType(.suggestion)
        .build()
      do {
        let segments = Segments()
        initSegmentsForAlphabetRewrite("abc", segments)
        #expect(rewriter.rewrite(convRequest, segments))
        #expect(segments.segmentsSize == 1)
        #expect(segments.segment(0).candidatesSize == 2)
        #expect(characterFormManager.getConversionCharacterForm("abc") == .fullWidth)
        #expect(segments.segment(0).candidate(0).value == "ａｂｃ")
        #expect(segments.segment(0).candidate(1).value == "abc")
      }
      do {
        characterFormManager.setCharacterForm("abc", .halfWidth)
        let segments = Segments()
        initSegmentsForAlphabetRewrite("abc", segments)
        #expect(rewriter.rewrite(convRequest, segments))
        #expect(segments.segmentsSize == 1)
        #expect(segments.segment(0).candidatesSize == 2)
        #expect(characterFormManager.getConversionCharacterForm("abc") == .halfWidth)
        #expect(segments.segment(0).candidate(0).value == "abc")
        #expect(segments.segment(0).candidate(1).value == "ａｂｃ")
      }
      do {
        // Test for candidate with inner segment boundary.
        // The test case is based on b/116826494.
        characterFormManager.setCharacterForm("0", .halfWidth)

        let segments = Segments()

        let segment = segments.pushBackSegment()
        segment.setKey("さんえん")

        let candidate = segment.addCandidate()
        candidate.key = "さんえん"
        candidate.contentKey = candidate.key
        candidate.value = "３円"  // Full-width three.
        candidate.contentValue = candidate.value
        candidate.innerSegmentBoundary = buildInnerSegmentBoundary(
          [(6, 3, 6, 3), (6, 3, 6, 3)], candidate.key, candidate.value)

        #expect(rewriter.rewrite(convRequest, segments))

        try #require(segments.segmentsSize == 1)
        try #require(segments.segment(0).candidatesSize == 2)

        // Since the character form preference is set to Config::HALF_WIDTH, the
        // half-width variant comes first.
        let half = segments.segment(0).candidate(0)
        #expect(half.key == "さんえん")
        #expect(half.value == "3円")
        try #require(half.innerSegmentBoundary.count == 2)
        #expect(
          half.innerSegmentBoundary
            == buildInnerSegmentBoundary([(6, 1, 6, 1), (6, 3, 6, 3)], half.key, half.value))

        let full = segments.segment(0).candidate(1)
        #expect(full.key == "さんえん")
        #expect(full.value == "３円")
        try #require(full.innerSegmentBoundary.count == 2)
        #expect(
          full.innerSegmentBoundary
            == buildInnerSegmentBoundary([(6, 3, 6, 3), (6, 3, 6, 3)], full.key, full.value))
      }
    }
  }

  @Test func rewriteForPartialSuggestion() throws {
    try withFixture { f in
      let characterFormManager = CharacterFormManager.getCharacterFormManager()
      #expect(characterFormManager.getConversionCharacterForm("0") == .fullWidth)
      let rewriter = f.createVariantsRewriter()
      var request = Genmai_Commands_Request()
      request.mixedConversion = true  // Request mixed conversion.
      let convRequest = ConversionRequestBuilder()
        .setRequest(request)
        .setRequestType(.suggestion)
        .build()
      do {
        let segments = Segments()

        let segment = segments.pushBackSegment()
        segment.setKey("3えん")

        let candidate = segment.addCandidate()
        candidate.key = "3"
        candidate.contentKey = candidate.key
        candidate.value = "３"  // Full-width three.
        candidate.contentValue = candidate.value
        candidate.consumedKeySize = 1
        candidate.attributes |= Attribute.partiallyKeyConsumed
        candidate.attributes |= Attribute.autoPartialSuggestion

        #expect(rewriter.rewrite(convRequest, segments))

        #expect(segments.segmentsSize == 1)
        #expect(segments.segment(0).candidatesSize == 2)

        for i in 0..<segments.segment(0).candidatesSize {
          let cand = segments.segment(0).candidate(i)
          #expect(cand.consumedKeySize == 1)
          #expect(cand.attributes & Attribute.partiallyKeyConsumed != 0)
          #expect(cand.attributes & Attribute.autoPartialSuggestion != 0)
        }
      }
    }
  }

  @Test func rewriteForSuggestion() throws {
    try withFixture { f in
      let characterFormManager = CharacterFormManager.getCharacterFormManager()
      let rewriter = f.createVariantsRewriter()
      let request = ConversionRequestBuilder().setRequestType(.suggestion).build()
      do {
        let segments = Segments()
        initSegmentsForAlphabetRewrite("abc", segments)
        #expect(rewriter.rewrite(request, segments))
        #expect(segments.segmentsSize == 1)
        #expect(segments.segment(0).candidatesSize == 1)

        #expect(characterFormManager.getConversionCharacterForm("abc") == .fullWidth)

        #expect(segments.segment(0).candidate(0).value == "ａｂｃ")
      }
      do {
        characterFormManager.setCharacterForm("abc", .halfWidth)
        let segments = Segments()
        initSegmentsForAlphabetRewrite("abc", segments)
        #expect(rewriter.rewrite(request, segments))
        #expect(segments.segmentsSize == 1)
        #expect(segments.segment(0).candidatesSize == 1)

        #expect(characterFormManager.getConversionCharacterForm("abc") == .halfWidth)

        #expect(segments.segment(0).candidate(0).value == "abc")
      }
      do {
        let segments = Segments()
        let segment = segments.pushBackSegment()
        let candidate = segment.addCandidate()
        candidate.value = "1,000"
        candidate.contentValue = "1,000"
        candidate.style = .numberSeparatedArabicFullwidth
        #expect(rewriter.rewrite(request, segments))
        try #require(segments.segmentsSize == 1)
        try #require(segments.segment(0).candidatesSize == 1)
        let rewrittenCandidate = segments.segment(0).candidate(0)
        #expect(rewrittenCandidate.value == "１，０００")
        #expect(rewrittenCandidate.style == .numberSeparatedArabicFullwidth)
      }
      do {
        // Test for candidate with inner segment boundary.
        let segments = Segments()

        let segment = segments.pushBackSegment()
        segment.setKey("まじ!")

        let candidate = segment.addCandidate()
        candidate.key = "まじ!"
        candidate.contentKey = candidate.key
        candidate.value = "マジ!"
        candidate.contentValue = candidate.value
        candidate.innerSegmentBoundary = buildInnerSegmentBoundary(
          [
            (6, 6, 6, 6),  // 6 bytes for "まじ"
            (1, 1, 1, 1),  // 1 byte for "!"
          ], candidate.key, candidate.value)

        #expect(rewriter.rewrite(request, segments))
        try #require(segments.segmentsSize == 1)
        try #require(segments.segment(0).candidatesSize == 1)

        let rewrittenCandidate = segments.segment(0).candidate(0)
        #expect(rewrittenCandidate.value == "マジ！")  // "マジ！" (full-width)
        #expect(rewrittenCandidate.contentValue == "マジ！")  // "マジ！" (full-width)
        #expect(
          rewrittenCandidate.innerSegmentBoundary
            == buildInnerSegmentBoundary(
              [
                // key="まじ", value="マジ", ckey="まじ", cvalue="マジ"
                (6, 6, 6, 6),
                // key="!", value="！", ckey="!", cvalue="！".
                // Values are converted to full-width.
                (1, 3, 1, 3),  // 1 byte for "!"
              ], rewrittenCandidate.key, rewrittenCandidate.value))
      }
    }
  }

  @Test func capability() throws {
    try withFixture { f in
      let rewriter = f.createVariantsRewriter()
      let request = ConversionRequest()
      #expect(rewriter.capability(request) == .all)
    }
  }

  @Test func learningLevel() throws {
    try withFixture { f in
      let rewriter = f.createVariantsRewriter()
      let manager = CharacterFormManager.getCharacterFormManager()
      var config = Config()
      config.historyLearningLevel = .noHistory
      let request = ConversionRequestBuilder().setConfig(config).build()

      let segments = Segments()

      let segment = segments.pushBackSegment()
      segment.setKey("いちにさん")
      segment.setSegmentType(.fixedValue)

      let cand = segment.addCandidate()
      cand.key = "いちにさん"
      cand.contentKey = cand.key

      // Half-width number with style.
      cand.value = "123"
      cand.contentValue = cand.value
      cand.style = .numberSeparatedArabicHalfwidth
      #expect(manager.getConversionCharacterForm("0") != .halfWidth)
      rewriter.finish(request, segments)
      #expect(manager.getConversionCharacterForm("0") != .halfWidth)
    }
  }

  @Test func finish() throws {
    try withFixture { f in
      let rewriter = f.createVariantsRewriter()
      let manager = CharacterFormManager.getCharacterFormManager()
      let request = ConversionRequest()

      let segments = Segments()

      let segment = segments.pushBackSegment()
      segment.setKey("いちにさん")
      segment.setSegmentType(.fixedValue)

      let cand = segment.addCandidate()
      cand.key = "いちにさん"
      cand.contentKey = cand.key

      // Half-width number with style.
      cand.value = "123"
      cand.contentValue = cand.value
      cand.style = .numberSeparatedArabicHalfwidth
      rewriter.finish(request, segments)
      #expect(manager.getConversionCharacterForm("0") == .halfWidth)

      // Full-width number with style.
      cand.value = "１２３"
      cand.contentValue = cand.value
      cand.style = .numberSeparatedArabicFullwidth
      rewriter.finish(request, segments)
      #expect(manager.getConversionCharacterForm("0") == .fullWidth)

      // Half-width number expression with description.
      cand.value = "3時"
      cand.contentValue = cand.value
      cand.style = .defaultStyle
      cand.description = VariantsRewriter.kHalfWidth
      rewriter.finish(request, segments)
      #expect(manager.getConversionCharacterForm("0") == .halfWidth)

      // Full-width number expression with description.
      cand.value = "３時"
      cand.contentValue = cand.value
      cand.style = .defaultStyle
      cand.description = VariantsRewriter.kFullWidth
      rewriter.finish(request, segments)
      #expect(manager.getConversionCharacterForm("0") == .fullWidth)

      // Half-width number expression without description (mixed-form: half-width
      // digit + full-width kanji).
      cand.value = "3時"
      cand.contentValue = cand.value
      cand.style = .defaultStyle
      cand.description = ""
      rewriter.finish(request, segments)
      #expect(manager.getConversionCharacterForm("0") == .halfWidth)

      // Separated Arabic and Arabic+Kanji numbers with NO_VARIANTS_EXPANSION (e.g.,
      // reranked by NumberRewriter).
      cand.value = "１，２３４"
      cand.contentValue = cand.value
      cand.style = .numberSeparatedArabicFullwidth
      cand.attributes = Attribute.noVariantsExpansion
      rewriter.finish(request, segments)
      #expect(manager.getConversionCharacterForm("0") == .fullWidth)

      cand.value = "1,234"
      cand.contentValue = cand.value
      cand.style = .numberSeparatedArabicHalfwidth
      cand.attributes = Attribute.noVariantsExpansion
      rewriter.finish(request, segments)
      #expect(manager.getConversionCharacterForm("0") == .halfWidth)

      cand.value = "１万"
      cand.contentValue = cand.value
      cand.style = .numberArabicAndKanjiFullwidth
      cand.attributes = Attribute.noVariantsExpansion
      rewriter.finish(request, segments)
      #expect(manager.getConversionCharacterForm("0") == .fullWidth)

      cand.value = "1万"
      cand.contentValue = cand.value
      cand.style = .numberArabicAndKanjiHalfwidth
      cand.attributes = Attribute.noVariantsExpansion
      rewriter.finish(request, segments)
      #expect(manager.getConversionCharacterForm("0") == .halfWidth)

      // Realtime conversion candidate expanded by RewriteTopCandidateForSuggestion
      // (NO_VARIANTS_EXPANSION cleared).
      manager.setCharacterForm("0", .fullWidth)
      cand.value = "2日"
      cand.contentValue = cand.value
      cand.style = .defaultStyle
      cand.attributes = Attribute.realtimeConversion | Attribute.noExtraDescription
      rewriter.finish(request, segments)
      #expect(manager.getConversionCharacterForm("0") == .halfWidth)

      // Unexpanded realtime conversion candidate (still has NO_VARIANTS_EXPANSION,
      // e.g. 2nd realtime candidate or fallback after NumberRewriter Kanji
      // insertion) should not update character form.
      manager.setCharacterForm("0", .fullWidth)
      cand.value = "石の上にも3年"
      cand.contentValue = cand.value
      cand.style = .defaultStyle
      cand.attributes = Attribute.realtimeConversion | Attribute.noVariantsExpansion
      rewriter.finish(request, segments)
      #expect(manager.getConversionCharacterForm("0") == .fullWidth)

      // User dictionary candidate should not update character form.
      manager.setCharacterForm("A", .fullWidth)
      cand.value = "Google"
      cand.contentValue = cand.value
      cand.style = .defaultStyle
      cand.attributes = Attribute.realtimeConversion | Attribute.userDictionary
      rewriter.finish(request, segments)
      #expect(manager.getConversionCharacterForm("A") == .fullWidth)

      // Incognito mode must not update character form (b/566072209).
      manager.setCharacterForm("0", .fullWidth)
      cand.value = "123"
      cand.contentValue = cand.value
      cand.style = .defaultStyle
      cand.attributes = 0
      do {
        var incognitoOptions = ConversionOptions()
        incognitoOptions.incognitoMode = true
        let incognitoReq = ConversionRequestBuilder().setOptions(incognitoOptions).build()
        rewriter.finish(incognitoReq, segments)
        #expect(manager.getConversionCharacterForm("0") == .fullWidth)
      }

      // Desktop suggestion commit (mixed_conversion = false, request_type =
      // SUGGESTION) must update character form for committed FIXED_VALUE segments.
      do {
        var desktopReq = Genmai_Commands_Request()
        desktopReq.mixedConversion = false
        let suggestionCommitReq = ConversionRequestBuilder()
          .setRequest(desktopReq)
          .setRequestType(.suggestion)
          .build()
        rewriter.finish(suggestionCommitReq, segments)
        #expect(manager.getConversionCharacterForm("0") == .halfWidth)
      }

      // Trailing ASCII whitespace in candidate.value should be stripped before
      // learning.
      manager.setCharacterForm("A", .fullWidth)
      cand.value = "abc "
      cand.contentValue = cand.value
      cand.attributes = 0
      rewriter.finish(request, segments)
      #expect(manager.getConversionCharacterForm("A") == .halfWidth)

      // Guard test: ensure Finish() continues to learn character form only from
      // the committed candidate at index 0, even when unselected n-best candidates
      // (index > 0) of the opposite character form are present in the segment.
      manager.setCharacterForm("0", .fullWidth)
      cand.value = "１２３"
      cand.contentValue = cand.value
      cand.attributes = 0
      let unselectedCand = segment.addCandidate()
      unselectedCand.value = "123"
      unselectedCand.contentValue = unselectedCand.value
      unselectedCand.attributes = 0
      rewriter.finish(request, segments)
      #expect(manager.getConversionCharacterForm("0") == .fullWidth)
    }
  }

  @Test func rewriteMixedScriptWordTest() throws {
    try withFixture { f in
      let rewriter = f.createVariantsRewriter()
      let manager = CharacterFormManager.getCharacterFormManager()
      let request = ConversionRequest()

      func makeSegments(_ value: String) -> (Segments, Segment) {
        let segments = Segments()
        let seg = segments.pushBackSegment()
        let cand = seg.addCandidate()
        cand.key = "てぃーしゃつ"
        cand.value = value
        cand.contentKey = cand.key
        cand.contentValue = cand.value
        return (segments, seg)
      }

      // Test case 1: Alphabet preference is HALF_WIDTH (default).
      do {
        manager.setDefaultRule()
        manager.setCharacterForm("A", .halfWidth)
        manager.setCharacterForm("ア", .fullWidth)

        // 1a: Input segment has "Tシャツ" (already preferred form).
        do {
          let (segments, seg) = makeSegments("Tシャツ")
          #expect(rewriter.rewrite(request, segments))
          try #require(seg.candidatesSize == 2)
          // Primary: "Tシャツ", has [半] description in expanded pair.
          #expect(seg.candidate(0).value == "Tシャツ")
          #expect(seg.candidate(0).description == VariantsRewriter.kHalfWidth)
          // Secondary: "Ｔシャツ", has [全] description.
          #expect(seg.candidate(1).value == "Ｔシャツ")
          #expect(seg.candidate(1).description == VariantsRewriter.kFullWidth)
        }

        // 1b: Input segment has "Ｔシャツ" (opposite form).
        do {
          let (segments, seg) = makeSegments("Ｔシャツ")
          #expect(rewriter.rewrite(request, segments))
          try #require(seg.candidatesSize == 2)
          // Primary (rewritten to preferred form): "Tシャツ", has [半].
          #expect(seg.candidate(0).value == "Tシャツ")
          #expect(seg.candidate(0).description == VariantsRewriter.kHalfWidth)
          // Secondary: "Ｔシャツ", has [全].
          #expect(seg.candidate(1).value == "Ｔシャツ")
          #expect(seg.candidate(1).description == VariantsRewriter.kFullWidth)
        }
      }

      // Test case 2: Alphabet preference is FULL_WIDTH.
      do {
        manager.setDefaultRule()
        manager.setCharacterForm("A", .fullWidth)
        manager.setCharacterForm("ア", .fullWidth)

        let (segments, seg) = makeSegments("Tシャツ")
        #expect(rewriter.rewrite(request, segments))
        try #require(seg.candidatesSize == 2)
        // Primary: "Ｔシャツ", has [全] description.
        #expect(seg.candidate(0).value == "Ｔシャツ")
        #expect(seg.candidate(0).description == VariantsRewriter.kFullWidth)
        // Secondary: "Tシャツ", has [半] description in expanded pair.
        #expect(seg.candidate(1).value == "Tシャツ")
        #expect(seg.candidate(1).description == VariantsRewriter.kHalfWidth)
      }
    }
  }

  @Test func rewriteTopCandidateForMixedConversionTest() throws {
    try withFixture { f in
      let rewriter = f.createVariantsRewriter()
      let manager = CharacterFormManager.getCharacterFormManager()

      var clientRequest = Genmai_Commands_Request()
      clientRequest.mixedConversion = true
      clientRequest.decoderExperimentParams.suppressRealtimeConversionWithConverter = true
      let request = ConversionRequestBuilder().setRequest(clientRequest).build()

      let segments = Segments()
      let seg = segments.pushBackSegment()

      // Case 1: Top candidate has REALTIME_CONVERSION and NO_VARIANTS_EXPANSION.
      // With CharacterFormManager set to FULL_WIDTH, primary candidate "１２３" is
      // inserted at index 0 and secondary candidate "123" is preserved at index 1.
      do {
        manager.setCharacterForm("0", .fullWidth)

        let top = seg.addCandidate()
        top.value = "123"
        top.contentValue = "123"
        top.attributes |= (Attribute.realtimeConversion | Attribute.noVariantsExpansion)

        let second = seg.addCandidate()
        second.value = "456"
        second.contentValue = "456"
        second.attributes |= Attribute.noVariantsExpansion

        #expect(rewriter.rewrite(request, segments))
        #expect(seg.candidatesSize == 3)
        #expect(seg.candidate(0).value == "１２３")
        #expect(seg.candidate(0).contentValue == "１２３")
        #expect(seg.candidate(0).description == "")
        #expect(seg.candidate(0).attributes & Attribute.realtimeConversion != 0)
        #expect(seg.candidate(0).attributes & Attribute.noExtraDescription != 0)
        #expect(seg.candidate(0).attributes & Attribute.noVariantsExpansion == 0)
        #expect(seg.candidate(1).value == "123")
        #expect(seg.candidate(1).contentValue == "123")
        #expect(seg.candidate(1).attributes & Attribute.noVariantsExpansion == 0)
        #expect(seg.candidate(2).value == "456")
        #expect(seg.candidate(2).attributes & Attribute.noVariantsExpansion != 0)

        seg.clearCandidates()
      }

      // Case 2: Already matches primary form -> no rewrite.
      do {
        manager.setCharacterForm("0", .halfWidth)

        let top = seg.addCandidate()
        top.value = "123"
        top.contentValue = "123"
        top.attributes |= (Attribute.realtimeConversion | Attribute.noVariantsExpansion)

        #expect(!rewriter.rewrite(request, segments))
        #expect(seg.candidatesSize == 1)
        #expect(seg.candidate(0).value == "123")

        seg.clearCandidates()
      }

      // Case 3: Flag is OFF -> no rewrite even if form differs.
      do {
        manager.setCharacterForm("0", .fullWidth)

        var requestFlagOff = Genmai_Commands_Request()
        requestFlagOff.mixedConversion = true
        requestFlagOff.decoderExperimentParams.suppressRealtimeConversionWithConverter = false
        let reqOff = ConversionRequestBuilder().setRequest(requestFlagOff).build()

        let top = seg.addCandidate()
        top.value = "123"
        top.contentValue = "123"
        top.attributes |= (Attribute.realtimeConversion | Attribute.noVariantsExpansion)

        #expect(!rewriter.rewrite(reqOff, segments))
        #expect(seg.candidatesSize == 1)
        #expect(seg.candidate(0).value == "123")

        seg.clearCandidates()
      }

      // Case 4: Compound with inner segment boundary (e.g. "あと2つ").
      do {
        manager.setCharacterForm("0", .fullWidth)

        let top = seg.addCandidate()
        top.key = "あとふたつ"
        top.value = "あと2つ"
        top.contentKey = top.key
        top.contentValue = top.value
        top.attributes |= (Attribute.realtimeConversion | Attribute.noVariantsExpansion)
        // Inner segments: "あと" (6B), "2" (1B), "つ" (3B)
        var builder = InnerSegmentBoundaryBuilder()
        builder.add(6, 6, 6, 6)
        builder.add(6, 1, 6, 1)
        builder.add(3, 3, 3, 3)
        top.innerSegmentBoundary = builder.build(top.key, top.value)

        #expect(rewriter.rewrite(request, segments))
        #expect(seg.candidatesSize == 2)
        #expect(seg.candidate(0).value == "あと２つ")
        #expect(seg.candidate(1).value == "あと2つ")
        let innerValues = seg.candidate(0).innerSegments().map { String($0.value) }
        #expect(innerValues == ["あと", "２", "つ"])

        seg.clearCandidates()
      }

      // Case 5: Desktop suggestion (mixed_conversion = false).
      do {
        manager.setCharacterForm("0", .fullWidth)

        var desktopRequest = Genmai_Commands_Request()
        desktopRequest.mixedConversion = false
        desktopRequest.decoderExperimentParams.suppressRealtimeConversionWithConverter = true
        let req = ConversionRequestBuilder()
          .setRequest(desktopRequest)
          .setRequestType(.suggestion)
          .build()

        let top = seg.addCandidate()
        top.value = "123"
        top.contentValue = "123"
        top.attributes |= (Attribute.realtimeConversion | Attribute.noVariantsExpansion)

        #expect(rewriter.rewrite(req, segments))
        #expect(seg.candidatesSize == 2)
        #expect(seg.candidate(0).value == "１２３")
        #expect(seg.candidate(1).value == "123")

        seg.clearCandidates()
      }

      // Case 6: Empty segment (candidates_size() == 0) -> returns false.
      do {
        #expect(!rewriter.rewrite(request, segments))
      }

      // Case 7: Candidate without REALTIME_CONVERSION attribute -> not rewritten.
      do {
        manager.setCharacterForm("0", .fullWidth)

        let top = seg.addCandidate()
        top.value = "123"
        top.contentValue = "123"
        top.attributes |= Attribute.noVariantsExpansion

        #expect(!rewriter.rewrite(request, segments))
        #expect(seg.candidate(0).value == "123")

        seg.clearCandidates()
      }

      // Case 8: Candidate with no character form alternatives (e.g. hiragana) ->
      // GenerateAlternatives returns false.
      do {
        let top = seg.addCandidate()
        top.key = "あいう"
        top.value = "あいう"
        top.contentKey = "あいう"
        top.contentValue = "あいう"
        top.attributes |= (Attribute.realtimeConversion | Attribute.noVariantsExpansion)

        #expect(!rewriter.rewrite(request, segments))
        #expect(seg.candidate(0).value == "あいう")

        seg.clearCandidates()
      }

      // Case 9: PARTIAL_SUGGESTION and PARTIAL_PREDICTION are excluded from
      // RewriteTopCandidateForSuggestion.
      do {
        manager.setCharacterForm("0", .fullWidth)

        for reqType: RequestType in [.partialSuggestion, .partialPrediction] {
          let partialReq = ConversionRequestBuilder()
            .setRequest(clientRequest)
            .setRequestType(reqType)
            .build()

          let top = seg.addCandidate()
          top.value = "123"
          top.contentValue = "123"
          top.attributes |= (Attribute.realtimeConversion | Attribute.noVariantsExpansion)

          #expect(!rewriter.rewrite(partialReq, segments))
          #expect(seg.candidate(0).value == "123")

          seg.clearCandidates()
        }
      }

      // Case 10: Candidate at index 0 already rewritten by NumberRewriter (marked
      // with NO_EXTRA_DESCRIPTION).
      // - If index 0 has no character form variants ("石の上にも三年"), no third
      //   candidate ("石の上にも３年") is inserted, keeping 2 candidates.
      // - If index 0 has alphabet variants ("wikipediaを三年使う"), index 0 is
      //   updated in-place to "ｗｉｋｉｐｅｄｉａを三年使う", keeping 2 candidates.
      do {
        manager.setCharacterForm("0", .fullWidth)
        manager.setCharacterForm("A", .fullWidth)

        let kanjiCand = seg.addCandidate()
        kanjiCand.key = "いしのうえにもさんねん"
        kanjiCand.value = "石の上にも三年"
        kanjiCand.contentKey = kanjiCand.key
        kanjiCand.contentValue = kanjiCand.value
        kanjiCand.attributes |=
          (Attribute.realtimeConversion | Attribute.noVariantsExpansion
            | Attribute.noExtraDescription)

        let arabicCand = seg.addCandidate()
        arabicCand.key = "いしのうえにもさんねん"
        arabicCand.value = "石の上にも3年"
        arabicCand.contentKey = arabicCand.key
        arabicCand.contentValue = arabicCand.value
        arabicCand.attributes |= (Attribute.realtimeConversion | Attribute.noVariantsExpansion)

        #expect(!rewriter.rewrite(request, segments))
        try #require(seg.candidatesSize == 2)
        #expect(seg.candidate(0).value == "石の上にも三年")
        #expect(seg.candidate(1).value == "石の上にも3年")

        seg.clearCandidates()

        // Mixed alphabet + Kanji number ("wikipediaを三年使う" at [0],
        // "wikipediaを3年使う" at [1]):
        let mixedTop = seg.addCandidate()
        mixedTop.key = "wikipediaを3ねんつかう"
        mixedTop.value = "wikipediaを三年使う"
        mixedTop.contentKey = mixedTop.key
        mixedTop.contentValue = mixedTop.value
        mixedTop.attributes |=
          (Attribute.realtimeConversion | Attribute.noVariantsExpansion
            | Attribute.noExtraDescription)
        var builder = InnerSegmentBoundaryBuilder()
        builder.add(
          "wikipediaを".utf8.count, "wikipediaを".utf8.count, "wikipedia".utf8.count,
          "wikipedia".utf8.count)
        builder.add("3ねん".utf8.count, "三年".utf8.count, "3ねん".utf8.count, "三年".utf8.count)
        builder.add("つかう".utf8.count, "使う".utf8.count, "つかう".utf8.count, "使う".utf8.count)
        mixedTop.innerSegmentBoundary = builder.build(mixedTop.key, mixedTop.value)

        let mixedFallback = seg.addCandidate()
        mixedFallback.key = "wikipediaを3ねんつかう"
        mixedFallback.value = "wikipediaを3年使う"
        mixedFallback.contentKey = mixedFallback.key
        mixedFallback.contentValue = mixedFallback.value
        mixedFallback.attributes |=
          (Attribute.realtimeConversion | Attribute.noVariantsExpansion)

        #expect(rewriter.rewrite(request, segments))
        try #require(seg.candidatesSize == 2)
        #expect(seg.candidate(0).value == "ｗｉｋｉｐｅｄｉａを三年使う")
        // NO_VARIANTS_EXPANSION is cleared on the in-place updated candidate so
        // that VariantsRewriter::Finish() can learn its character form.
        #expect(seg.candidate(0).attributes & Attribute.noVariantsExpansion == 0)
        #expect(seg.candidate(1).value == "wikipediaを3年使う")
        #expect(seg.candidate(1).attributes & Attribute.noVariantsExpansion != 0)

        seg.clearCandidates()
      }

      // Case 11: Candidate whose inner_segment_boundary has a stale byte length
      // (e.g. "2日" (4 bytes) normalized to "２日" (6 bytes) without updating
      // inner_segment_boundary). VariantsRewriter must ignore the inconsistent
      // boundary rather than slicing "日" in the middle of its UTF-8 sequence.
      do {
        manager.setCharacterForm("0", .fullWidth)

        let top = seg.addCandidate()
        top.key = "ふつか"
        top.value = "２日"
        top.contentKey = "ふつか"
        top.contentValue = "２日"
        top.attributes |= (Attribute.realtimeConversion | Attribute.noVariantsExpansion)
        top.innerSegmentBoundary = buildInnerSegmentBoundary([(9, 4, 9, 4)], "ふつか", "2日")

        #expect(!rewriter.rewrite(request, segments))
        try #require(seg.candidatesSize == 1)
        #expect(seg.candidate(0).value == "２日")
        #expect(seg.candidate(0).contentValue == "２日")

        seg.clearCandidates()
      }
    }
  }
}
