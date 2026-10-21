// Port of mozc/src/prediction/dictionary_predictor_test.cc (3.35.6354),
// part 2 (aggregation tests with the mock dictionary). Part 1 is in
// DictionaryPredictorTests.swift.

import Foundation
import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private let U = Attribute.unigram
private let B = Attribute.bigram
private let R = Attribute.realtimeConversion
private let RT = Attribute.realtimeTop
private let P = Attribute.partiallyKeyConsumed
private let S = Attribute.suffixDictionary
private let E = Attribute.english
private let TC = Attribute.typingCorrection
private let SK = Attribute.singleKanji
private let NONE = Token.Attribute.none

private struct SimpleSuffixToken {
  let key: String
  let value: String
}

private let kSuffixTokens = [SimpleSuffixToken(key: "いか", value: "以下")]

private final class TestSuffixDictionary: DictionaryInterface, @unchecked Sendable {
  func hasKey(_ key: String) -> Bool { false }
  func hasValue(_ value: String) -> Bool { false }

  func lookupPredictive(_ key: String, callback: any DictionaryCallback) {
    lookupPredictive(key, options: ConversionOptions(), callback: callback)
  }

  func lookupPredictive(
    _ key: String, options: ConversionOptions, callback: any DictionaryCallback
  ) {
    var token = Token()
    for suffixToken in kSuffixTokens {
      if !key.isEmpty && !suffixToken.key.hasBytePrefix(key) {
        continue
      }
      switch callback.onKey(suffixToken.key) {
      case .traverseDone:
        return
      case .traverseNextKey:
        continue
      case .traverseCull:
        fatalError("Culling is not supported.")
      default:
        break
      }
      token.key = suffixToken.key
      token.value = suffixToken.value
      token.cost = 1000
      token.lid = 0
      token.rid = 0
      if callback.onToken(token.key, token.key, token) == .traverseDone {
        break
      }
    }
  }

  func lookupPrefix(_ key: String, options: ConversionOptions, callback: any DictionaryCallback) {}
  func lookupExact(_ key: String, options: ConversionOptions, callback: any DictionaryCallback) {}
  func lookupReverse(_ str: String, options: ConversionOptions, callback: any DictionaryCallback) {
  }
}

private enum Platform: Sendable, CustomTestStringConvertible {
  case desktop, mobile
  var testDescription: String { self == .desktop ? "DESKTOP" : "MOBILE" }
}

private struct EnglishPredictionTestEntry: Sendable, CustomTestStringConvertible {
  let name: String
  let inputMode: TransliterationType
  let key: String
  let expectedPrefix: String
  let expectedValues: [String]
  var testDescription: String { name }
}

private let kEnglishPredictionTestEntries: [EnglishPredictionTestEntry] = [
  EnglishPredictionTestEntry(
    name: "HALF_ASCII_lower_case", inputMode: .halfAscii, key: "conv", expectedPrefix: "conv",
    expectedValues: ["converge", "converged", "convergent"]),
  EnglishPredictionTestEntry(
    name: "HALF_ASCII_upper_case", inputMode: .halfAscii, key: "CONV", expectedPrefix: "CONV",
    expectedValues: ["CONVERGE", "CONVERGED", "CONVERGENT"]),
  EnglishPredictionTestEntry(
    name: "HALF_ASCII_capitalized", inputMode: .halfAscii, key: "Conv", expectedPrefix: "Conv",
    expectedValues: ["Converge", "Converged", "Convergent"]),
  EnglishPredictionTestEntry(
    name: "FULL_ASCII_lower_case", inputMode: .fullAscii, key: "conv", expectedPrefix: "ｃｏｎｖ",
    expectedValues: ["ｃｏｎｖｅｒｇｅ", "ｃｏｎｖｅｒｇｅｄ", "ｃｏｎｖｅｒｇｅｎｔ"]),
  EnglishPredictionTestEntry(
    name: "FULL_ASCII_upper_case", inputMode: .fullAscii, key: "CONV", expectedPrefix: "ＣＯＮＶ",
    expectedValues: ["ＣＯＮＶＥＲＧＥ", "ＣＯＮＶＥＲＧＥＤ", "ＣＯＮＶＥＲＧＥＮＴ"]),
  EnglishPredictionTestEntry(
    name: "FULL_ASCII_capitalized", inputMode: .fullAscii, key: "Conv", expectedPrefix: "Ｃｏｎｖ",
    expectedValues: ["Ｃｏｎｖｅｒｇｅ", "Ｃｏｎｖｅｒｇｅｄ", "Ｃｏｎｖｅｒｇｅｎｔ"]),
]

private func makeQuery(_ key: String, _ type: TypeCorrectedQuery.CorrectionType)
  -> TypeCorrectedQuery
{
  TypeCorrectedQuery(correction: key, type: type, score: 0, bias: 0)
}

@Suite(
  .enabled(if: predictionMockDataAvailable, "mock_genmai.data is missing"), .scopedConfigEnvironment)
struct DictionaryPredictorTestPart2 {
  var f = DPFixture()

  @Test mutating func onOffTest() throws {
    let dp = try DPT.createPredictorWithMockData()
    do {
      // turn off
      f.config.useDictionarySuggest = false
      f.config.useRealtimeConversion = false

      let convreq = f.createSuggestionConversionRequest("ぐーぐるあ")
      #expect(dp.aggregateResultsForTesting(convreq).isEmpty)
    }
    do {
      // turn on
      f.config.useDictionarySuggest = true
      let convreq = f.createSuggestionConversionRequest("ぐーぐるあ")
      #expect(!dp.aggregateResultsForTesting(convreq).isEmpty)
    }
    do {
      // empty query
      let convreq = f.createSuggestionConversionRequest("")
      #expect(dp.aggregateResultsForTesting(convreq).isEmpty)
    }
  }

  @Test mutating func partialSuggestion() throws {
    let dp = try DPT.createPredictorWithMockData()

    f.config.useDictionarySuggest = true
    f.config.useRealtimeConversion = true
    // turn on mobile mode
    f.request.mixedConversion = true

    let convreq = f.createConversionRequest(DPFixture.options(.partialSuggestion), "ぐーぐるあ")
    #expect(!dp.aggregateResultsForTesting(convreq).isEmpty)
  }

  @Test mutating func partialSuggestionWithRealtimeConversion() throws {
    let dp = try DPT.createPredictorWithMockData()

    f.config.useDictionarySuggest = true
    f.config.useRealtimeConversion = true
    // turn on mobile mode
    f.request.mixedConversion = true

    f.composer.reset()
    f.composer.setPreeditTextForTestOnly("ぐーぐるあ")
    f.composer.moveCursorLeft()

    let convreq = f.createConversionRequest(
      DPFixture.options(.partialSuggestion, useActualConverterForRealtimeConversion: true),
      "ぐーぐる", false /* init composer */)

    var result = PredictionResult()
    result.key = "ぐーぐる"
    result.value = "グーグル"
    result.attributes = R
    dp.mockDecoder.decodeHandler = { _ in [result] }

    let results = dp.aggregateResultsForTesting(convreq)
    #expect((DPT.getMergedTypes(results) & R) != 0)
  }

  @Test mutating func bigramTest() throws {
    let dp = try DPT.createPredictorWithMockData()

    f.config.useDictionarySuggest = true

    // history is "グーグル"
    f.initHistory("ぐーぐる", "グーグル")

    // "グーグルアドセンス" will be returned.
    let convreq = f.createSuggestionConversionRequest("あ")
    let results = dp.aggregateResultsForTesting(convreq)
    #expect((B | DPT.getMergedTypes(results)) != 0)
  }

  @Test mutating func bigramTestWithZeroQuery() throws {
    let dp = try DPT.createPredictorWithMockData()

    f.config.useDictionarySuggest = true
    f.request.zeroQuerySuggestion = true

    // history is "グーグル"
    f.initHistory("ぐーぐる", "グーグル")

    let convreq = f.createSuggestionConversionRequest("")
    let results = dp.aggregateResultsForTesting(convreq)
    #expect((B | DPT.getMergedTypes(results)) != 0)
  }

  @Test mutating func bigramTestWithZeroQueryFilterMode() throws {
    let dp = try DPT.createPredictorWithMockData()

    f.config.useDictionarySuggest = true
    f.request.zeroQuerySuggestion = true

    // history is "グーグル"
    f.initHistory("ぐーぐる", "グーグル")

    let convreq = f.createSuggestionConversionRequest("")
    let results = dp.aggregateResultsForTesting(convreq)
    #expect((B & DPT.getMergedTypes(results)) == 0)
  }

  // Check that previous candidate never be shown at the current candidate.
  @Test mutating func regression3042706() throws {
    let dp = try DPT.createPredictorWithMockData()

    f.config.useDictionarySuggest = true

    // history is "きょうと/京都"
    f.initHistory("きょうと", "京都")

    let convreq = f.createSuggestionConversionRequest("だい")
    let results = dp.aggregateResultsForTesting(convreq)
    #expect((R | DPT.getMergedTypes(results)) != 0)
    for r in results {
      #expect(!r.value.hasBytePrefix("京都"))
      #expect(r.key.hasBytePrefix("だい"))
    }
  }

  @Test(arguments: [Platform.desktop, Platform.mobile])
  private mutating func triggerConditions(_ platform: Platform) throws {
    let isMobile = platform == .mobile

    let dp = try DPT.createPredictorWithMockData()

    f.config.useDictionarySuggest = true
    f.config.useRealtimeConversion = false
    if isMobile {
      RequestTestUtil.fillMobileRequest(&f.request)
    }

    // Set up realtime conversion.
    do {
      var result = PredictionResult()
      result.key = "test"
      result.value = "test"
      result.attributes = R
      dp.mockDecoder.decodeHandler = { _ in [result] }
    }

    // Keys of normal lengths.
    do {
      // Unigram is triggered in suggestion and prediction if key length (in
      // UTF8 character count) is long enough.
      f.composer.setInputMode(.hiragana)
      let convreq = f.createSuggestionConversionRequest("ぐーぐる")
      let results = dp.aggregateResultsForTesting(convreq)
      #expect(DPT.getMergedTypes(results) == DPT.addDefaultPredictionTypes(U, isMobile))
    }

    // Short keys.
    do {
      if isMobile {
        // Unigram is triggered even if key length is short.
        f.composer.setInputMode(.hiragana)
        let suggestionConvreq = f.createSuggestionConversionRequest("てす")
        let results1 = dp.aggregateResultsForTesting(suggestionConvreq)
        #expect(DPT.getMergedTypes(results1) == (U | R | P))

        let predictionConvreq = f.createPredictionConversionRequest("てす")
        let results2 = dp.aggregateResultsForTesting(predictionConvreq)
        #expect(DPT.getMergedTypes(results2) == (U | R | P))
      } else {
        // Unigram is not triggered for SUGGESTION if key length is short.
        f.composer.setInputMode(.hiragana)
        let suggestionConvreq = f.createSuggestionConversionRequest("てす")
        #expect(dp.aggregateResultsForTesting(suggestionConvreq).isEmpty)
        let predictionConvreq = f.createPredictionConversionRequest("てす")
        let results = dp.aggregateResultsForTesting(predictionConvreq)
        #expect(DPT.getMergedTypes(results) == U)
      }
    }

    // Zipcode-like keys.
    do {
      f.composer.setInputMode(.hiragana)
      let convreq = f.createSuggestionConversionRequest("0123")
      #expect(dp.aggregateResultsForTesting(convreq).isEmpty)
    }

    // History is short => UNIGRAM
    do {
      f.initHistory("A", "A")
      f.composer.setInputMode(.hiragana)
      let convreq = f.createSuggestionConversionRequest("てすとだ")
      let results = dp.aggregateResultsForTesting(convreq)
      #expect(DPT.getMergedTypes(results) == DPT.addDefaultPredictionTypes(U, isMobile))
    }

    // Both history and current segment are long => UNIGRAM or BIGRAM
    do {
      f.initHistory("これは", "これは")
      f.composer.setInputMode(.hiragana)
      let convreq = f.createSuggestionConversionRequest("てすとだ")
      let results = dp.aggregateResultsForTesting(convreq)
      #expect(DPT.getMergedTypes(results) == DPT.addDefaultPredictionTypes(U | B, isMobile))
    }

    // Current segment is short
    do {
      if isMobile {
        // For mobile, UNIGRAM and REALTIME are added to BIGRAM.
        f.initHistory("てすとだよ", "テストだよ")
        f.composer.setInputMode(.hiragana)
        let convreq = f.createSuggestionConversionRequest("てす")
        let results = dp.aggregateResultsForTesting(convreq)
        #expect(DPT.getMergedTypes(results) == (U | B | R | P))
      } else {
        // No UNIGRAM.
        f.initHistory("てすとだよ", "テストだよ")
        f.composer.setInputMode(.hiragana)
        let convreq = f.createSuggestionConversionRequest("てす")
        let results = dp.aggregateResultsForTesting(convreq)
        #expect(DPT.getMergedTypes(results) == B)
      }
    }

    // Typing correction shouldn't be appended.
    do {
      f.composer.setInputMode(.hiragana)
      let convreq = f.createSuggestionConversionRequest("ｐはよう")
      let results = dp.aggregateResultsForTesting(convreq)
      #expect((TC & DPT.getMergedTypes(results)) == 0)
    }

    // When romaji table is qwerty mobile => ENGLISH is included depending on
    // the language aware input setting.
    do {
      let origInputMode = f.composer.getInputMode()
      let origTable = f.request.specialRomanjiTable
      let origLangAware = f.request.languageAwareInput
      let origUseDictionarySuggest = f.config.useDictionarySuggest

      f.composer.setInputMode(.hiragana)
      f.config.useDictionarySuggest = true

      // The case where romaji table is set to qwerty.  ENGLISH is turned on if
      // language aware input is enabled.
      let qwertyTables: [Genmai_Commands_Request.SpecialRomanjiTable] = [
        .qwertyMobileToHiragana, .qwertyMobileToHalfwidthascii,
      ]
      let otherTables: [Genmai_Commands_Request.SpecialRomanjiTable] = [
        .flickToHalfwidthascii, .flickToHiragana, .godanToHalfwidthascii, .godanToHiragana,
        .notouchToHalfwidthascii, .notouchToHiragana, .toggleFlickToHalfwidthascii,
        .toggleFlickToHiragana, .twelveKeysToHalfwidthascii, .twelveKeysToHiragana,
      ]
      // The case where romaji table is not qwerty.  ENGLISH is turned off
      // regardless of language aware input setting.
      for table in qwertyTables + otherTables {
        f.config.useDictionarySuggest = origUseDictionarySuggest
        f.request.languageAwareInput = origLangAware
        f.request.specialRomanjiTable = origTable
        f.composer.setInputMode(origInputMode)

        f.request.specialRomanjiTable = table

        // Language aware input is default: No English prediction.
        f.request.languageAwareInput = .defaultLanguageAwareBehavior
        let convreq1 = f.createSuggestionConversionRequest("てすとだよ")
        var results = dp.aggregateResultsForTesting(convreq1)
        #expect((DPT.getMergedTypes(results) & E) == 0)

        // Language aware input is off: No English prediction.
        f.request.languageAwareInput = .noLanguageAwareInput
        let convreq2 = f.createSuggestionConversionRequest("てすとだよ")
        results = dp.aggregateResultsForTesting(convreq2)
        #expect((DPT.getMergedTypes(results) & E) == 0)

        // Language aware input is on: English prediction is included (only
        // for raw inputs in the dictionary; "てすとだよ" has none).
        f.request.languageAwareInput = .languageAwareSuggestion
        let convreq3 = f.createSuggestionConversionRequest("てすとだよ")
        results = dp.aggregateResultsForTesting(convreq3)
        #expect((DPT.getMergedTypes(results) & E) == 0)
      }
    }
  }

  @Test mutating func triggerConditionsLatinInputMode() throws {
    let dp = try DPT.createPredictorWithMockData()

    let kTestCases: [(Platform, TransliterationType)] = [
      (.desktop, .halfAscii),
      (.desktop, .fullAscii),
      (.mobile, .halfAscii),
      (.mobile, .fullAscii),
    ]

    for (platform, inputMode) in kTestCases {
      ConfigHandler.getDefaultConfig(&f.config)
      // Resets to default value.
      f.request = Genmai_Commands_Request()
      let isMobile = platform == .mobile
      if isMobile {
        RequestTestUtil.fillMobileRequest(&f.request)
      }

      // Implementation note: SetUpInputForSuggestion() resets the state of
      // composer. So we have to call SetInputMode() after this method.
      f.composer.setInputMode(inputMode)

      f.config.useDictionarySuggest = true

      // Input mode is Latin(HALF_ASCII or FULL_ASCII) => ENGLISH
      f.config.useRealtimeConversion = false
      let convreq1 = f.createSuggestionConversionRequest("hel")
      var results = dp.aggregateResultsForTesting(convreq1)
      #expect(DPT.getMergedTypes(results) == DPT.addDefaultPredictionTypes(E, isMobile))

      f.config.useRealtimeConversion = true
      let convreq2 = f.createSuggestionConversionRequest("hel")
      results = dp.aggregateResultsForTesting(convreq2)
      #expect(DPT.getMergedTypes(results) == DPT.addDefaultPredictionTypes(E | R, isMobile))

      // When dictionary suggest is turned off, English prediction should be
      // disabled.
      f.config.useDictionarySuggest = false
      let convreq3 = f.createSuggestionConversionRequest("hel")
      #expect(dp.aggregateResultsForTesting(convreq3).isEmpty)

      // Has realtime results for PARTIAL_SUGGESTION request.
      f.config.useDictionarySuggest = true
      let partialSuggestionConvreq = f.createConversionRequest(
        DPFixture.options(.partialSuggestion), "hel")
      results = dp.aggregateResultsForTesting(partialSuggestionConvreq)
      #expect(DPT.getMergedTypes(results) == R)
    }
  }

  @Test mutating func aggregateUnigramCandidate() throws {
    let dp = try DPT.createPredictorWithMockData()

    let kKey = "ぐーぐるあ"

    let convreq = f.createSuggestionConversionRequest(kKey)
    var results: [PredictionResult] = []
    dp.predictor.aggregateUnigram(convreq, &results)
    #expect(!results.isEmpty)

    for result in results {
      #expect(result.getPredictionTypesForTesting() == U)
      #expect(result.key.hasBytePrefix(kKey))
    }
  }

  @Test mutating func lookupUnigramCandidateForMixedConversion() throws {
    let dp = try DPT.createPredictorWithMockData()

    let kHiraganaA = "あ"
    let kHiraganaAA = "ああ"
    let kCost = MockDictionary.kDefaultCost
    let kPosId = MockDictionary.kDefaultPosId
    let kUnknownId = Int(dp.posMatcher.getUnknownId())

    var aTokens = [
      // A system dictionary entry "a".
      PT.makeToken(kHiraganaA, "a", kCost, kPosId, kPosId, NONE)
    ]
    // System dictionary entries "a0", ..., "a9", which are detected as
    // redundant by MaybeRedundant(); see dictionary_predictor.cc.
    for i in 0..<10 {
      aTokens.append(PT.makeToken(kHiraganaA, "a\(i)", kCost, kPosId, kPosId, NONE))
    }
    // A user dictionary entry "aaa".  MaybeRedundant() detects this entry as
    // redundant but it should not be filtered in prediction.
    aTokens.append(
      PT.makeToken(kHiraganaA, "aaa", kCost, kPosId, kPosId, Token.Attribute.userDictionary))
    aTokens.append(
      PT.makeToken(kHiraganaAA, "bbb", 0, kUnknownId, kUnknownId, Token.Attribute.userDictionary))
    let aaTokens = [
      PT.makeToken(kHiraganaAA, "bbb", 0, kUnknownId, kUnknownId, Token.Attribute.userDictionary)
    ]

    dp.mockDictionary.predictive.on(kHiraganaA, tokens: aTokens)
    dp.mockDictionary.predictive.on(kHiraganaAA, tokens: aaTokens)

    f.config.useDictionarySuggest = true
    f.config.useRealtimeConversion = false
    _ = f.table.loadFromFile("system://12keys-hiragana.tsv")

    func isUserDictionaryResult(_ res: PredictionResult) -> Bool {
      (res.attributes & Attribute.userDictionary) != 0
    }

    do {
      // Test prediction from input あ.
      PT.insertInputSequence(kHiraganaA, &f.composer)

      var results: [PredictionResult] = []
      let convreq = f.createPredictionConversionRequest(kHiraganaA, false /* init_composer */)
      dp.predictor.aggregateUnigram(convreq, &results)

      // Check if "aaa" is not filtered.
      #expect(
        results.contains {
          $0.key == kHiraganaA && $0.value == "aaa" && isUserDictionaryResult($0)
        })

      // "bbb" is looked up from input "あ" but it will be filtered because it
      // is from user dictionary with unknown POS ID.
      #expect(
        !results.contains {
          $0.key == kHiraganaAA && $0.value == "bbb" && isUserDictionaryResult($0)
        })
    }

    do {
      // Test prediction from input ああ.
      f.composer.reset()
      PT.insertInputSequence(kHiraganaAA, &f.composer)

      var results: [PredictionResult] = []
      let convreq = f.createPredictionConversionRequest(kHiraganaAA, false /* init_composer */)
      dp.predictor.aggregateUnigram(convreq, &results)

      // Check if "aaa" is not found as its key is あ.
      #expect(
        !results.contains {
          $0.key == kHiraganaA && $0.value == "aaa" && isUserDictionaryResult($0)
        })

      // Unlike the above case for "あ", "bbb" is now found because input key
      // is exactly "ああ".
      #expect(
        results.contains {
          $0.key == kHiraganaAA && $0.value == "bbb" && isUserDictionaryResult($0)
        })
    }
  }

  // We are not sure what should we suggest after the end of sentence for now.
  // However, we decided to show zero query suggestion rather than stopping
  // zero query completely. Users may be confused if they cannot see
  // suggestion window only after the certain conditions.
  // TODO(toshiyuki): Show useful zero query suggestions after EOS.
  @Test(.disabled("DISABLED_ in C++")) mutating func mobileZeroQueryAfterEOS() throws {
    let dp = try DPT.createPredictorWithMockData()
    let posMatcher = dp.posMatcher

    let kTestcases: [(String, String, UInt16, Bool)] = [
      ("ですよね｡", "ですよね。", posMatcher.getEOSSymbolId(), false),
      ("｡", "。", posMatcher.getEOSSymbolId(), false),
      ("まるいち", "①", posMatcher.getEOSSymbolId(), false),
      ("そう", "そう", posMatcher.getGeneralNounId(), true),
      ("そう!", "そう！", posMatcher.getGeneralNounId(), false),
      ("むすめ。", "娘。", posMatcher.getUniqueNounId(), true),
    ]

    RequestTestUtil.fillMobileRequest(&f.request)

    for (key, value, rid, expectedResult) in kTestcases {
      f.initHistory(key, value, rid)
      let convreq = f.createPredictionConversionRequest("")
      let results = dp.aggregateResultsForTesting(convreq)
      #expect(!results.isEmpty == expectedResult)
    }
  }

  @Test mutating func aggregateBigramPrediction() throws {
    let dp = try DPT.createPredictorWithMockData()

    do {
      // history is "グーグル"
      let kHistoryKey = "ぐーぐる"
      let kHistoryValue = "グーグル"

      f.initHistory(kHistoryKey, kHistoryValue)

      var results: [PredictionResult] = []

      let convreq = f.createSuggestionConversionRequest("あ")
      dp.aggregateBigram(convreq, &results)
      #expect(!results.isEmpty)

      for result in results {
        // "グーグルアドセンス", "グーグル", "アドセンス"
        // are in the dictionary.
        if result.value == "アドセンス" {
          #expect(!result.removed)
        } else {
          #expect(result.removed)
        }
        #expect(result.getPredictionTypesForTesting() == B)
        #expect(!result.key.hasBytePrefix(kHistoryKey))
        #expect(!result.value.hasBytePrefix(kHistoryValue))
        #expect(result.key.hasBytePrefix("あ"))
        #expect(result.value.hasBytePrefix("ア"))
      }
    }

    do {
      let kHistoryKey = "てす"
      let kHistoryValue = "テス"

      f.initHistory(kHistoryKey, kHistoryValue)

      var results: [PredictionResult] = []

      let convreq = f.createSuggestionConversionRequest("あ")
      dp.aggregateBigram(convreq, &results)
      #expect(results.isEmpty)
    }
  }

  // Zero query bigram is deprecated and disabled.
  // Keep this test to confirm that no suggestions are shown.
  @Test mutating func aggregateZeroQueryBigramPrediction() throws {
    let dp = try DPT.createPredictorWithMockData()
    RequestTestUtil.fillMobileRequest(&f.request)

    do {
      // history is "グーグル"
      f.initHistory("ぐーぐる", "グーグル")

      var results: [PredictionResult] = []

      let convreq = f.createSuggestionConversionRequest("")
      dp.aggregateBigram(convreq, &results)
      #expect(results.isEmpty)
    }

    do {
      let kHistory = "ありがとう"

      let mock = dp.mockDictionary
      mock.prefix.on(kHistory, kv: [(kHistory, kHistory)])
      mock.predictive.on(
        kHistory,
        kv: [
          ("ありがとうございます", "ありがとうございます"),
          ("ありがとうございます", "ありがとう御座います"),
          ("ありがとうございました", "ありがとうございました"),
          ("ありがとうございました", "ありがとう御座いました"),

          ("ございます", "ございます"),
          ("ございます", "御座います"),
          // ("ございました", "ございました") is not in the dictionary.
          ("ございました", "御座いました"),

          // Word less than 10.
          ("ありがとうね", "ありがとうね"),
          ("ね", "ね"),
        ])
      mock.mock.hasKeyHandler = { key in
        key.bytesEqual("ございます") || key.bytesEqual("ございました")
      }

      f.initHistory(kHistory, kHistory)

      var results: [PredictionResult] = []

      let convreq = f.createSuggestionConversionRequest("")
      dp.aggregateBigram(convreq, &results)
      #expect(results.isEmpty)
    }
  }

  @Test mutating func aggregateZeroQueryPredictionLatinInputMode() throws {
    let dp = try DPT.createPredictorWithMockData()
    RequestTestUtil.fillMobileRequest(&f.request)

    let cases: [(String, Bool)] = [
      // No history
      ("", false),
      ("when", false),
      // We can input numbers from Latin input mode.
      ("12", true),
      // We can input some symbols from Latin input mode.
      ("@", true),
    ]
    for (history, expectResults) in cases {
      // Zero query
      f.composer.setInputMode(.halfAscii)
      f.initHistory(history, history)

      var results: [PredictionResult] = []
      let convreq = f.createSuggestionConversionRequest("")
      dp.aggregateZeroQuery(convreq, &results)
      #expect(results.isEmpty == !expectResults, "history: \(history)")
    }
  }

  @Test mutating func getRealtimeCandidateMaxSize() throws {
    _ = try DPT.createPredictorWithMockData()

    // GetRealtimeCandidateMaxSize has some heuristics so here we test
    // following conditions.
    // - The result must be equal or less than kMaxSize;
    // - If mixed_conversion is the same, the result of SUGGESTION is
    //        equal or less than PREDICTION.
    // - If mixed_conversion is the same, the result of PARTIAL_SUGGESTION is
    //        equal or less than PARTIAL_PREDICTION.
    // - Partial version has equal or greater than non-partial version.

    let kMaxSize = 100

    f.request = Genmai_Commands_Request()
    let suggestionConvreqNoMixed = f.createConversionRequest(
      DPFixture.options(.suggestion, maxDictionaryPredictionCandidatesSize: kMaxSize))
    let predictionConvreqNoMixed = f.createPredictionConversionRequest("")

    RequestTestUtil.fillMobileRequest(&f.request)
    let suggestionConvreqMixed = f.createConversionRequest(
      DPFixture.options(.suggestion, maxDictionaryPredictionCandidatesSize: kMaxSize))
    let predictionConvreqMixed = f.createPredictionConversionRequest("")

    func size(_ r: ConversionRequest) -> Int { DictionaryPredictor.getRealtimeCandidateMaxSize(r) }

    // non-partial, non-mixed-conversion
    let predictionNoMixed = size(predictionConvreqNoMixed)
    #expect(kMaxSize >= predictionNoMixed)

    let suggestionNoMixed = size(suggestionConvreqNoMixed)
    #expect(kMaxSize >= suggestionNoMixed)
    #expect(suggestionNoMixed <= predictionNoMixed)

    // non-partial, mixed-conversion
    let predictionMixed = size(predictionConvreqMixed)
    #expect(kMaxSize >= predictionMixed)

    let suggestionMixed = size(suggestionConvreqMixed)
    #expect(kMaxSize >= suggestionMixed)

    // partial, non-mixed-conversion
    f.request = Genmai_Commands_Request()
    let partialSuggestionConvreqNoMixed = f.createConversionRequest(
      DPFixture.options(.partialSuggestion))
    let partialPredictionConvreqNoMixed = f.createConversionRequest(
      DPFixture.options(.partialPrediction))

    RequestTestUtil.fillMobileRequest(&f.request)
    let partialSuggestionConvreqMixed = f.createConversionRequest(
      DPFixture.options(.partialSuggestion))
    let partialPredictionConvreqMixed = f.createConversionRequest(
      DPFixture.options(.partialPrediction))

    let partialPredictionNoMixed = size(partialPredictionConvreqNoMixed)
    #expect(kMaxSize >= partialPredictionNoMixed)

    let partialSuggestionNoMixed = size(partialSuggestionConvreqNoMixed)
    #expect(kMaxSize >= partialSuggestionNoMixed)
    #expect(partialSuggestionNoMixed <= partialPredictionNoMixed)

    // partial, mixed-conversion
    let partialPredictionMixed = size(partialPredictionConvreqMixed)
    #expect(kMaxSize >= partialPredictionMixed)

    let partialSuggestionMixed = size(partialSuggestionConvreqMixed)
    #expect(kMaxSize >= partialSuggestionMixed)
    #expect(partialSuggestionMixed <= partialPredictionMixed)

    #expect(partialPredictionNoMixed >= predictionNoMixed)
    #expect(partialPredictionMixed >= predictionMixed)
    #expect(partialSuggestionNoMixed >= suggestionNoMixed)
    #expect(partialSuggestionMixed >= suggestionMixed)
  }

  @Test mutating func getRealtimeCandidateMaxSizeForMixed() throws {
    _ = try DPT.createPredictorWithMockData()

    let kMaxSize = 100
    func size(_ r: ConversionRequest) -> Int { DictionaryPredictor.getRealtimeCandidateMaxSize(r) }

    RequestTestUtil.fillMobileRequest(&f.request)  // enables mixed conversion.
    let suggestionShortConvreq = f.createConversionRequest(
      DPFixture.options(.suggestion, maxDictionaryPredictionCandidatesSize: kMaxSize), "short")
    let predictionShortConvreq = f.createConversionRequest(
      DPFixture.options(.prediction, maxDictionaryPredictionCandidatesSize: kMaxSize), "short")

    // for short key, try to provide many results as possible
    let shortSuggestionMixed = size(suggestionShortConvreq)
    #expect(kMaxSize >= shortSuggestionMixed)

    let shortPredictionMixed = size(predictionShortConvreq)
    #expect(kMaxSize >= shortPredictionMixed)

    let suggestionLongConvreq = f.createConversionRequest(
      DPFixture.options(.suggestion, maxDictionaryPredictionCandidatesSize: kMaxSize),
      "long_request_key")
    let predictionLongConvreq = f.createConversionRequest(
      DPFixture.options(.prediction, maxDictionaryPredictionCandidatesSize: kMaxSize),
      "long_request_key")

    let longSuggestionMixed = size(suggestionLongConvreq)
    #expect(kMaxSize >= longSuggestionMixed)
    #expect(shortSuggestionMixed > longSuggestionMixed)

    let longPredictionMixed = size(predictionLongConvreq)
    #expect(kMaxSize >= longPredictionMixed)
    #expect(kMaxSize > longPredictionMixed + longSuggestionMixed)
    #expect(shortPredictionMixed > longPredictionMixed)
  }

  @Test mutating func aggregateRealtimeConversion() throws {
    let dp = try MockDataAndPredictor()
    try dp.initialize()

    let kKey = "わたしのなまえはなかのです"

    for candidatesSize in [10, 20] {
      for useActualConverter in [false, true] {
        do {
          var results = PT.results(1)
          results[0].key = kKey
          results[0].value = "私の名前は中野です"
          results[0].attributes = R | RT | Attribute.noVariantsExpansion
          let expected = results
          dp.mockDecoder.decodeHandler = { request in
            if request.options().maxConversionCandidatesSize == candidatesSize
              && request.options().useActualConverterForRealtimeConversion == useActualConverter
            {
              return expected
            }
            return []
          }
        }

        let convreq = f.createSuggestionConversionRequest(kKey)
        var results: [PredictionResult] = []
        dp.predictor.aggregateRealtime(convreq, candidatesSize, useActualConverter, &results)
        try #require(results.count == 1)
        #expect(results[0].getPredictionTypesForTesting() == R | RT)
        #expect(results[0].key == kKey)
        #expect((results[0].attributes & Attribute.noVariantsExpansion) != 0)
      }
    }
  }

  @Test mutating func aggregateSuffixPrediction() throws {
    let dp = try MockDataAndPredictor()
    try dp.initialize(TestSuffixDictionary(), nil)

    f.request.zeroQuerySuggestion = true

    // history is "グーグル"
    let kHistoryKey = "ぐーぐる"
    let kHistoryValue = "グーグル"

    // Since SuffixDictionary only returns for key "い", the result
    // should be empty for "あ".
    var results: [PredictionResult] = []
    f.initHistory(kHistoryKey, kHistoryValue)
    let convreq1 = f.createSuggestionConversionRequest("あ")
    dp.aggregateZeroQuery(convreq1, &results)
    #expect(results.isEmpty)

    // Candidates generated by AggregateSuffixPrediction from nonempty
    // key should have SUFFIX type.
    results.removeAll()
    f.initHistory(kHistoryKey, kHistoryValue)
    f.composer.reset()
    let convreq2 = f.createSuggestionConversionRequest("い")
    dp.aggregateZeroQuery(convreq2, &results)
    #expect(!results.isEmpty)
    #expect((DPT.getMergedTypes(results) & S) != 0)
    for result in results {
      #expect(result.getPredictionTypesForTesting() == S)
    }
  }

  @Test mutating func aggregateZeroQuerySuffixPrediction() throws {
    let dp = try MockDataAndPredictor()
    try dp.initialize(TestSuffixDictionary(), nil)

    RequestTestUtil.fillMobileRequest(&f.request)

    // history is "グーグル"
    f.initHistory("ぐーぐる", "グーグル")

    do {
      var results: [PredictionResult] = []

      // Candidates generated by AggregateZeroQuerySuffixPrediction should
      // have SUFFIX type.
      let convreq = f.createSuggestionConversionRequest("", false /* init_composer */)
      dp.aggregateZeroQuery(convreq, &results)
      #expect(!results.isEmpty)
      for result in results {
        #expect(result.getPredictionTypesForTesting() == S)
      }
    }
    do {
      // If the feature is disabled and `results` is nonempty, nothing should
      // be generated.
      f.request.decoderExperimentParams.disableZeroQuerySuffixPrediction = true
      var results = [PredictionResult()]
      let convreq = f.createSuggestionConversionRequest("")
      dp.aggregateZeroQuery(convreq, &results)
      #expect(results.count == 1)
    }
    do {
      // Suffix entries should be aggregated for handwriting
      f.request.isHandwriting = true
      var results = [PredictionResult()]
      let convreq = f.createSuggestionConversionRequest("")
      dp.aggregateZeroQuery(convreq, &results)
      #expect(!results.isEmpty)
    }
  }

  @Test(arguments: kEnglishPredictionTestEntries)
  private mutating func aggregateEnglishPrediction(_ entry: EnglishPredictionTestEntry) throws {
    let dp = try DPT.createPredictorWithMockData()

    _ = f.table.loadFromFile("system://romanji-hiragana.tsv")
    f.composer.reset()
    f.composer.setInputMode(entry.inputMode)
    PT.insertInputSequence(entry.key, &f.composer)

    var results: [PredictionResult] = []

    let convreq = f.createPredictionConversionRequest(entry.key, false /* init_composer */)
    dp.aggregateEnglish(convreq, &results)

    var values = Set<String>()
    for result in results {
      #expect(result.getPredictionTypesForTesting() == E)
      #expect(
        result.value.hasBytePrefix(entry.expectedPrefix),
        "\(result.value) doesn't start with \(entry.expectedPrefix)")
      values.insert(result.value)
    }
    for expectedValue in entry.expectedValues {
      #expect(values.contains(expectedValue), "\(expectedValue) isn't in the results")
    }
  }

  @Test mutating func aggregateExtendedTypeCorrectingPrediction() throws {
    let mock = PredictionMockSupplementalModel()

    let expected = [
      makeQuery("よろしく", .correction),
      makeQuery("よろざく", [.correction, .kanaModifierInsentiveOnly]),
      makeQuery("よろさくです", .completion),
      makeQuery("よろしくです", [.correction, .completion]),
      makeQuery("よろざくです", [.correction, .completion, .kanaModifierInsentiveOnly]),
    ]

    var called = 0
    mock.correctCompositionHandler = { _ in
      called += 1
      return expected
    }

    let dp = try DPT.createPredictorWithMockData(nil, mock)

    f.config.useTypingCorrection = true

    f.initHistory("ほんじつは", "本日は")
    let convreq = f.createPredictionConversionRequest("よろさく")
    let results = dp.predictor.aggregateTypingCorrectedResultsForMixedConversion(convreq)
    #expect(called == 1)

    try #require(results.count == 5)
    for i in 0..<results.count {
      #expect(results[i].key == expected[i].correction)
      if i == 2 {
        // "よろさくです" is COMPLETION only.
        #expect((results[i].attributes & TC) == 0)
      } else {
        #expect((results[i].attributes & TC) != 0)
      }
    }
  }

  @Test mutating func aggregateExtendedTypeCorrectingPredictionWithCharacterForm() throws {
    let mock = PredictionMockSupplementalModel()

    var expected = [makeQuery("よろしく!", .correction)]
    let expected1 = expected
    mock.correctCompositionHandler = { _ in expected1 }

    var dp = try DPT.createPredictorWithMockData(nil, mock)

    f.config.useTypingCorrection = true

    f.initHistory("", "")

    let convreq = f.createPredictionConversionRequest("よろさく!")
    let results = dp.predictor.aggregateTypingCorrectedResultsForMixedConversion(convreq)

    try #require(results.count == 1)

    #expect(results[0].key == expected[0].correction)
    #expect(results[0].value == "よろしく！")  // default is full width.

    // Verify that inner_segment_boundary is also updated when the character
    // form normalization changes the byte length of `value` (e.g. "2日" ->
    // "２日").
    CharacterFormManager.getCharacterFormManager().setCharacterForm("0", .fullWidth)
    expected = [makeQuery("ふつか", .correction)]
    let expected2 = expected
    let mock2 = PredictionMockSupplementalModel()
    mock2.correctCompositionHandler = { _ in expected2 }
    dp = try DPT.createPredictorWithMockData(nil, mock2)
    dp.mockDecoder.decodeHandler = { req in
      var result = PredictionResult()
      result.key = req.key()
      result.value = "2日"
      result.attributes = R
      result.innerSegmentBoundary = buildInnerSegmentBoundary(
        [(result.key.utf8.count, result.value.utf8.count, result.key.utf8.count,
          result.value.utf8.count)],
        result.key, result.value)
      return [result]
    }
    let results2 = dp.predictor.aggregateTypingCorrectedResultsForMixedConversion(
      f.createPredictionConversionRequest("ふつか"))
    try #require(results2.count == 1)
    #expect(results2[0].value == "２日")
    #expect(
      results2[0].innerSegmentBoundary
        == buildInnerSegmentBoundary(
          [("ふつか".utf8.count, "２日".utf8.count, "ふつか".utf8.count, "２日".utf8.count)],
          "ふつか", "２日"))
    CharacterFormManager.getCharacterFormManager().setDefaultRule()
    CharacterFormManager.getCharacterFormManager().clearHistory()
  }

  @Test mutating func aggregateExtendedTypeCorrectingWithNumberDecoder() throws {
    let mock = PredictionMockSupplementalModel()
    let expected = [makeQuery("にじゅうご", .correction)]
    mock.correctCompositionHandler = { _ in expected }

    let dp = try DPT.createPredictorWithMockData(nil, mock)

    f.config.useTypingCorrection = true

    f.initHistory("", "")

    let convreq = f.createPredictionConversionRequest("にしゆうこ")
    let results = dp.predictor.aggregateTypingCorrectedResultsForMixedConversion(convreq)
    try #require(results.count == 2)
    #expect(results[1].value == "２５")  // default is full width.
  }

  @Test mutating func zeroQuerySuggestionAfterNumbers() throws {
    let dp = try DPT.createPredictorWithMockData()
    let posMatcher = dp.posMatcher

    f.request.zeroQuerySuggestion = true

    do {
      let kExpectedValue = "月"
      f.initHistory("12", "12")
      var results: [PredictionResult] = []
      let convreq = f.createSuggestionConversionRequest("")
      dp.aggregateZeroQuery(convreq, &results)
      #expect(!results.isEmpty)

      var target: PredictionResult?
      for result in results {
        #expect(result.getPredictionTypesForTesting() == S)
        if result.value == kExpectedValue {
          target = result
          break
        }
      }
      let t = try #require(target)
      #expect(t.value == kExpectedValue)
      #expect(t.lid == posMatcher.getCounterSuffixWordId())
      #expect(t.rid == posMatcher.getCounterSuffixWordId())
    }

    do {
      let kExpectedValue = "個"
      f.initHistory("66050713", "66050713")  // A random number
      var results: [PredictionResult] = []
      let convreq = f.createSuggestionConversionRequest("")
      dp.aggregateZeroQuery(convreq, &results)
      #expect(!results.isEmpty)

      var found = false
      for result in results {
        #expect(result.getPredictionTypesForTesting() == S)
        if result.value == kExpectedValue {
          found = true
          break
        }
      }
      #expect(found)
    }
  }

  @Test mutating func triggerNumberZeroQuerySuggestion() throws {
    let dp = try DPT.createPredictorWithMockData()
    let posMatcher = dp.posMatcher

    let kTestCases: [(String, String, String, Bool)] = [
      ("12", "12", "月", true), ("12", "１２", "月", true),
      ("12", "壱拾弐", "月", false), ("12", "十二", "月", false),
      ("12", "一二", "月", false), ("12", "Ⅻ", "月", false),
      ("あか", "12", "月", true),  // T13N
      ("あか", "１２", "月", true),  // T13N
      ("じゅう", "10", "時", true), ("じゅう", "１０", "時", true),
      ("じゅう", "十", "時", false), ("じゅう", "拾", "時", false),
    ]

    for (historyKey, historyValue, findSuffixValue, expectedResult) in kTestCases {
      f.initHistory(historyKey, historyValue)
      var results: [PredictionResult] = []
      f.request.zeroQuerySuggestion = true
      let convreq = f.createSuggestionConversionRequest("", false /* init composer */)
      dp.aggregateZeroQuery(convreq, &results)
      #expect(!results.isEmpty)

      var found = false
      for result in results {
        #expect(result.getPredictionTypesForTesting() == S)
        if result.value == findSuffixValue && result.lid == posMatcher.getCounterSuffixWordId() {
          found = true
          break
        }
      }
      #expect(found == expectedResult, "\(historyValue)")
    }
  }

  @Test mutating func getNumberHistoryWithPrecedingText() throws {
    let dp = try DPT.createPredictorWithMockData()
    let posMatcher = dp.posMatcher

    // No history but has preceding text.
    f.initHistory("", "")
    f.composer.reset()

    var context = Genmai_Commands_Context()
    context.precedingText = "12"

    f.request.zeroQuerySuggestion = true

    // Manually build ConversionRequest with context
    var options = ConversionOptions()
    options.requestType = .suggestion
    let convreq = ConversionRequestBuilder()
      .setComposer(f.composer)
      .setRequest(f.request)
      .setConfig(f.config)
      .setOptions(options)
      .setHistoryResultView(f.historyResult)
      .setContext(context)
      .setKey("")
      .build()

    var results: [PredictionResult] = []
    dp.aggregateZeroQuery(convreq, &results)
    #expect(!results.isEmpty)

    let found = results.contains {
      ($0.attributes & S) != 0 && $0.value == "月" && $0.lid == posMatcher.getCounterSuffixWordId()
    }
    #expect(found)
  }

  @Test mutating func triggerZeroQuerySuggestion() throws {
    let dp = try DPT.createPredictorWithMockData()

    let kTestCases: [(String, String, String, Int)] = [
      ("@", "@", "gmail.com", 0),
      ("username@", "username@", "gmail.com", 0),  // Special treatment for email
      ("@", "@", "yahoo.co.jp", 1),
      ("@", "@", "docomo.ne.jp", 2),
      ("!", "!", "?", -1),
    ]

    for (historyKey, historyValue, findValue, expectedRank) in kTestCases {
      f.initHistory(historyKey, historyValue)
      var results: [PredictionResult] = []
      f.request.zeroQuerySuggestion = true
      let convreq = f.createSuggestionConversionRequest("", false /* init_composer */)
      dp.aggregateZeroQuery(convreq, &results)
      #expect(!results.isEmpty)

      var rank = -1
      for i in 0..<results.count {
        let result = results[i]
        #expect(result.getPredictionTypesForTesting() == S)
        if result.value == findValue && result.lid == 0 /* EOS */ {
          rank = i
          break
        }
      }
      #expect(rank == expectedRank, "\(historyValue)")
    }
  }

  @Test mutating func zipCodeRequest() throws {
    let dp = try DPT.createPredictorWithMockData()

    let kTestCases: [(Bool, String, Bool)] = [
      (true, "", false),  // No ZeroQuery entry
      (true, "000", false), (true, "---", false),
      (true, "0124-", false), (true, "012-0", false),
      (true, "0124-0", true),  // key length >= 6
      (true, "012-3456", true),  // key length >= 6
      (true, "ABC", true), (true, "０１２-０", true),

      (false, "", false),  // No ZeroQuery entry
      (false, "000", true), (false, "---", true),
      (false, "0124-", true), (false, "012-0", true),
      (false, "0124-0", true), (false, "012-3456", true),
      (false, "ABC", true), (false, "０１２-０", true),
    ]

    for (isSuggestion, key, shouldAggregate) in kTestCases {
      let convreq =
        isSuggestion
        ? f.createSuggestionConversionRequest(key) : f.createPredictionConversionRequest(key)
      let results = dp.aggregateResultsForTesting(convreq)
      let hasResult = !results.isEmpty
      #expect(hasResult == shouldAggregate, "\(key)")
    }
  }

  @Test mutating func mobileZipcodeEntries() throws {
    let dp = try DPT.createPredictorWithMockData()
    RequestTestUtil.fillMobileRequest(&f.request)

    let posMatcher = dp.posMatcher
    let mock = dp.mockDictionary
    let token = PT.makeToken(
      "101-0001", "東京都千代田", 100 /* cost */, Int(posMatcher.getZipcodeId()),
      Int(posMatcher.getZipcodeId()), NONE)
    // InvokeCallbackWithOneToken
    mock.predictive.on("101-000") { _ = $0.onToken("101-0001", "101-0001", token) }
    mock.predictive.on("101-0001") { _ = $0.onToken("101-0001", "101-0001", token) }
    do {
      let convreq = f.createPredictionConversionRequest("101-000")
      let results = dp.aggregateResultsForTesting(convreq)
      #expect(!DPT.findCandidateByValue(results, "東京都千代田"))
    }
    do {
      // Aggregate zip code entries only for exact key match.
      let convreq = f.createPredictionConversionRequest("101-0001")
      let results = dp.aggregateResultsForTesting(convreq)
      #expect(DPT.findCandidateByValue(results, "東京都千代田"))
    }
  }

  @Test mutating func realtimeConversionStartingWithAlphabets() throws {
    let dp = try DPT.createPredictorWithMockData()

    // turn on real-time conversion
    f.config.useDictionarySuggest = false
    f.config.useRealtimeConversion = true

    let kKey = "PCてすと"
    let kExpectedSuggestionValues = ["PCテスト", "PCてすと"]

    do {
      var results = PT.results(2)
      results[0].key = kKey
      results[0].value = "PCテスト"
      results[0].attributes = R
      results[1].key = kKey
      results[1].value = "PCてすと"
      results[1].attributes = R
      let expected = results
      dp.mockDecoder.decodeHandler = { request in
        #expect(request.key() == kKey)
        return expected
      }
    }

    var results: [PredictionResult] = []
    let convreq = f.createSuggestionConversionRequest(kKey)
    dp.predictor.aggregateRealtime(convreq, 10, false, &results)
    try #require(results.count == 2)

    #expect(results[0].getPredictionTypesForTesting() == R)
    #expect(results[1].getPredictionTypesForTesting() == R)
    #expect(results[0].value == kExpectedSuggestionValues[0])
    #expect(results[1].value == kExpectedSuggestionValues[1])
  }

  @Test mutating func realtimeConversionWithSpellingCorrection() throws {
    let dp = try DPT.createPredictorWithMockData()

    // turn on real-time conversion
    f.config.useDictionarySuggest = false
    f.config.useRealtimeConversion = true

    let kCapriHiragana = "かぷりちょうざ"

    // No realtime conversion result
    dp.mockDecoder.decodeHandler = { _ in [] }
    var results: [PredictionResult] = []
    let convreq1 = f.createConversionRequest(
      DPFixture.options(.suggestion, useActualConverterForRealtimeConversion: false),
      kCapriHiragana)
    dp.predictor.aggregateUnigram(convreq1, &results)
    try #require(!results.isEmpty)
    #expect((results[0].attributes & Attribute.spellingCorrection) != 0)  // From unigram

    results.removeAll()

    let kKeyWithDe = "かぷりちょうざで"
    let kExpectedSuggestionValueWithDe = "カプリチョーザで"
    do {
      var result = PredictionResult()
      result.key = kKeyWithDe
      result.value = kExpectedSuggestionValueWithDe
      result.attributes = R | Attribute.spellingCorrection
      dp.mockDecoder.decodeHandler = { request in
        request.key() == kKeyWithDe ? [result] : []
      }
    }

    let convreq2 = f.createSuggestionConversionRequest(kKeyWithDe)
    dp.predictor.aggregateRealtime(convreq2, 1, false, &results)
    try #require(results.count == 1)
    #expect(results[0].getPredictionTypesForTesting() == R)
    #expect((results[0].attributes & Attribute.spellingCorrection) != 0)
    #expect(results[0].value == kExpectedSuggestionValueWithDe)
  }

  @Test mutating func propagateUserDictionaryAttribute() throws {
    let dp = try DPT.createPredictorWithMockData()

    f.config.useDictionarySuggest = true
    f.config.useRealtimeConversion = true

    do {
      // No realtime conversion result
      dp.mockDecoder.decodeHandler = { _ in [] }

      let convreq = f.createSuggestionConversionRequest("ゆーざー")
      let results = dp.aggregateResultsForTesting(convreq)
      try #require(!results.isEmpty)
      #expect(results[0].value == "ユーザー")
      #expect((results[0].attributes & Attribute.userDictionary) != 0)
    }

    let kKey = "ゆーざーの"
    let kValue = "ユーザーの"
    do {
      var result = PredictionResult()
      result.key = kKey
      result.value = kValue
      result.attributes = Attribute.userDictionary
      dp.mockDecoder.decodeHandler = { request in request.key() == kKey ? [result] : [] }
    }

    do {
      let convreq = f.createSuggestionConversionRequest(kKey)
      let results = dp.aggregateResultsForTesting(convreq)
      try #require(!results.isEmpty)
      #expect(results[0].value == kValue)
      #expect((results[0].attributes & Attribute.userDictionary) != 0)
    }
  }

  @Test mutating func enrichPartialCandidates() throws {
    let dp = try DPT.createPredictorWithMockData()
    RequestTestUtil.fillMobileRequest(&f.request)

    let convreq = f.createPredictionConversionRequest("ぐーぐる")
    let results = dp.aggregateResultsForTesting(convreq)
    #expect((DPT.getMergedTypes(results) & P) != 0)
  }

  @Test mutating func prefixCandidates() throws {
    let dp = try DPT.createPredictorWithMockData()
    RequestTestUtil.fillMobileRequest(&f.request)

    let convreq = f.createPredictionConversionRequest("ぐーぐるあ")
    let results = dp.aggregateResultsForTesting(convreq)
    #expect((DPT.getMergedTypes(results) & P) != 0)
    for r in results where (r.attributes & P) != 0 {
      #expect((r.attributes & Attribute.partiallyKeyConsumed) != 0)
      #expect(r.consumedKeySize != 0)
    }
  }

  @Test mutating func candidatesFromUserDictionary() throws {
    let dp = try DPT.createPredictorWithMockData()
    let posMatcher = dp.posMatcher

    RequestTestUtil.fillMobileRequest(&f.request)

    do {
      let mock = dp.mockDictionary
      mock.predictive.clear()
      mock.prefix.clear()
      let tokens = [
        // Suggest-only (only for exact key) USER DICTIONARY entry
        PT.makeToken(
          "しょーとかっと", "ショートカット", 0, Int(posMatcher.getUnknownId()),
          Int(posMatcher.getUnknownId()), Token.Attribute.userDictionary),
        // Normal USER DICTIONARY entry
        PT.makeToken(
          "しょーとかっと", "しょうとかっと", 0, Int(posMatcher.getGeneralNounId()),
          Int(posMatcher.getGeneralNounId()), Token.Attribute.userDictionary),
      ]
      mock.predictive.anyKey = { _, callback in PT.invokeCallbackWithTokens(tokens, callback) }
    }

    do {
      let convreq = f.createPredictionConversionRequest("しょーとか")
      let results = dp.aggregateResultsForTesting(convreq)
      #expect((DPT.getMergedTypes(results) & U) != 0)
      #expect(DPT.findCandidateByValue(results, "しょうとかっと"))
      #expect(!DPT.findCandidateByValue(results, "ショートカット"))
    }
    do {
      let convreq = f.createPredictionConversionRequest("しょーとかっと")
      let results = dp.aggregateResultsForTesting(convreq)
      #expect((DPT.getMergedTypes(results) & U) != 0)
      #expect(DPT.findCandidateByValue(results, "しょうとかっと"))
      #expect(DPT.findCandidateByValue(results, "ショートカット"))
    }
  }

  @Test mutating func numberDecoderCandidates() throws {
    let dp = try DPT.createPredictorWithMockData()
    RequestTestUtil.fillMobileRequest(&f.request)

    let convreq = f.createPredictionConversionRequest("よんじゅうごかい")
    let results = dp.aggregateResultsForTesting(convreq)
    let result = try #require(results.first { $0.value == "45" && !$0.removed })
    #expect((result.attributes & Attribute.partiallyKeyConsumed) != 0)
    #expect((result.attributes & Attribute.noSuggestLearning) != 0)
  }

  @Test mutating func doNotPredictNoisyNumberEntries() throws {
    let dp = try DPT.createPredictorWithMockData()
    RequestTestUtil.fillMobileRequest(&f.request)

    dp.mockDictionary.predictive.on(
      "1",
      kv: [
        ("1", "一"),
        ("1じ", "一時"),
        ("1じ", "1時"),
        ("10じ", "10時"),
        ("10じ", "十時"),
        ("1じすぎ", "1時過ぎ"),
        ("19じ", "19時"),
      ])

    f.composer.setInputMode(.halfAscii)

    let convreq = f.createPredictionConversionRequest("1")
    let results = dp.aggregateResultsForTesting(convreq)
    #expect(!DPT.findCandidateByValue(results, "10時"))
    #expect(!DPT.findCandidateByValue(results, "十時"))
    #expect(!DPT.findCandidateByValue(results, "1時過ぎ"))
    #expect(!DPT.findCandidateByValue(results, "19時"))

    #expect(DPT.findCandidateByValue(results, "一"))
    #expect(DPT.findCandidateByValue(results, "一時"))
    #expect(DPT.findCandidateByValue(results, "1時"))
  }

  @Test mutating func singleKanji() throws {
    let dp = try DPT.createPredictorWithMockData()
    RequestTestUtil.fillMobileRequest(&f.request)

    dp.singleKanjiDictionary!.lookupKanjiEntriesHandler = { _, _ in ["手"] }

    let convreq = f.createPredictionConversionRequest("てすと")
    let results = dp.aggregateResultsForTesting(convreq)
    #expect((DPT.getMergedTypes(results) & SK) != 0)
    for result in results where (result.attributes & SK) == 0 {
      #expect(Util.charsLen(result.value) > 1)
    }
  }

  @Test mutating func singleKanjiForMobileHardwareKeyboard() throws {
    let dp = try DPT.createPredictorWithMockData()
    RequestTestUtil.fillMobileRequestWithHardwareKeyboard(&f.request)

    var called = 0
    dp.singleKanjiDictionary!.lookupKanjiEntriesHandler = { _, _ in
      called += 1
      return []
    }

    let convreq = f.createPredictionConversionRequest("てすと")
    let results = dp.aggregateResultsForTesting(convreq)
    #expect((DPT.getMergedTypes(results) & SK) == 0)
    #expect(called == 0)
  }

  @Test mutating func handwriting() throws {
    let dp = try DPT.createPredictorWithMockData()
    let mockDict = dp.mockDictionary
    let kCostOffset: Int32 = 3000

    // Handwriting request
    RequestTestUtil.fillMobileRequestForHandwriting(&f.request)
    f.request.decoderExperimentParams.maxCompositionEventToProcess = 1
    f.request.decoderExperimentParams.handwritingConversionCandidateCostOffset = kCostOffset
    f.composer.reset()
    f.composer.setCompositionsForHandwriting(
      DPFixture.compositionEvents([("かん字じ典", 0.99), ("かlv字じ典", 0.01)]))

    // reverse conversion
    do {
      var result = PredictionResult()
      result.key = "かん字じ典"
      result.value = "かんじじてん"
      var called = 0
      dp.mockDecoder.reverseDecodeHandler = { request in
        #expect(request.requestType() == .reverseConversion && request.key() == "かん字じ典")
        called += 1
        #expect(called == 1)
        return [result]
      }
    }

    mockDict.exact.on(
      "かんじじてん",
      kv: [
        ("かんじじてん", "漢字辞典"),
        ("かんじじてん", "漢字字典"),
        ("かんじじてん", "感じじてん"),
        ("かんじじてん", "幹事時点"),
        ("かんじじてん", "換字字典"),
        ("かんじじてん", "換字自転"),
        ("かんじじてん", "換字じてん"),
      ])

    let convreq = f.createPredictionConversionRequest("かん字じ典", false /* init_composer */)
    let results = dp.aggregateResultsForTesting(convreq)
    #expect((DPT.getMergedTypes(results) & U) != 0)

    #expect(results.count >= 5)
    // composition from handwriting output
    #expect(DPT.findCandidateByKeyValue(results, "かんじじてん", "かん字じ典"))
    #expect(DPT.findCandidateByKeyValue(results, "かlv字じ典", "かlv字じ典"))
    // look-up results
    #expect(DPT.findCandidateByKeyValue(results, "かんじじてん", "漢字辞典"))
    #expect(DPT.findCandidateByKeyValue(results, "かんじじてん", "漢字字典"))
    #expect(DPT.findCandidateByKeyValue(results, "かんじじてん", "換字字典"))

    for result in results {
      if result.value == "かん字じ典" {
        // Top recognition result
        #expect(result.wcost == 0)
      } else if result.key == "かんじじてん" {
        #expect(result.wcost >= Int(kCostOffset))
      }
    }
  }

  @Test mutating func handwritingT13N() throws {
    let dp = try DPT.createPredictorWithMockData()
    let mockDict = dp.mockDictionary
    // Handwriting request
    RequestTestUtil.fillMobileRequestForHandwriting(&f.request)
    f.request.decoderExperimentParams.maxCompositionEventToProcess = 1
    f.composer.reset()
    f.composer.setCompositionsForHandwriting(
      DPFixture.compositionEvents([("キた", 0.99), ("もた", 0.01)]))

    // reverse conversion
    do {
      var result = PredictionResult()
      result.key = "きた"  // T13N key can be looked up
      result.value = "きた"
      dp.mockDecoder.reverseDecodeHandler = { request in
        #expect(request.requestType() == .reverseConversion && request.key() == "キた")
        return [result]
      }
    }

    mockDict.exact.on("きた", kv: [("きた", "きた"), ("きた", "北")])

    let convreq = f.createPredictionConversionRequest("キタ", false /* init composer */)
    let results = dp.aggregateResultsForTesting(convreq)
    #expect((DPT.getMergedTypes(results) & U) != 0)

    #expect(results.count >= 2)
    // composition from handwriting output
    #expect(DPT.findCandidateByKeyValue(results, "きた", "キた"))
    #expect(DPT.findCandidateByKeyValue(results, "もた", "もた"))
    // No "きた", "北"
  }

  @Test mutating func handwritingNoHiragana() throws {
    let dp = try DPT.createPredictorWithMockData()
    let mockDict = dp.mockDictionary

    // Handwriting request
    RequestTestUtil.fillMobileRequestForHandwriting(&f.request)
    f.request.decoderExperimentParams.maxCompositionEventToProcess = 1
    f.composer.reset()
    f.composer.setCompositionsForHandwriting(DPFixture.compositionEvents([("南", 0.9)]))

    let convreq = f.createPredictionConversionRequest("南", false /* init_composer */)
    let predictiveBefore = mockDict.mock.calls["LookupPredictive", default: 0]
    let exactBefore = mockDict.mock.calls["LookupExact", default: 0]
    let results = dp.aggregateResultsForTesting(convreq)
    // reverse conversion will not be called
    #expect(dp.mockDecoder.reverseDecodeCount == 0)
    #expect(mockDict.mock.calls["LookupPredictive", default: 0] == predictiveBefore)
    #expect(mockDict.mock.calls["LookupExact", default: 0] == exactBefore)
    #expect((DPT.getMergedTypes(results) & U) != 0)
    #expect(results.count >= 1)
    // composition from handwriting output
    #expect(DPT.findCandidateByKeyValue(results, "南", "南"))
  }

  @Test mutating func handwritingRealtime() throws {
    let dp = try DPT.createPredictorWithMockData()
    // Handwriting request
    RequestTestUtil.fillMobileRequestForHandwriting(&f.request)
    f.request.decoderExperimentParams.maxCompositionEventToProcess = 1
    f.composer.reset()
    f.composer.setCompositionsForHandwriting(DPFixture.compositionEvents([("ばらが", 0.9)]))

    // Decode is called instead of ReverseDecode.
    do {
      var result = PredictionResult()
      result.key = "ばらが"
      result.value = "薔薇が"
      var called = 0
      dp.mockDecoder.decodeHandler = { request in
        if request.requestType() == .prediction && request.key() == "ばらが" {
          called += 1
          #expect(called == 1)
          return [result]
        }
        return []
      }
    }

    let convreq = f.createPredictionConversionRequest("ばらが", false /* init_composer */)
    let results = dp.aggregateResultsForTesting(convreq)
    #expect((DPT.getMergedTypes(results) & U) != 0)

    #expect(results.count >= 2)
    // composition from handwriting output
    #expect(DPT.findCandidateByKeyValue(results, "ばらが", "ばらが"))
    #expect(DPT.findCandidateByKeyValue(results, "ばらが", "薔薇が"))
  }

  @Test mutating func aggregateZeroQueryWithPrecedingText() throws {
    let dp = try DPT.createPredictorWithMockData()

    // No history but has preceding text "@".
    f.initHistory("", "")
    f.composer.reset()

    var context = Genmai_Commands_Context()
    context.precedingText = "@"

    f.request.zeroQuerySuggestion = true
    RequestTestUtil.fillMobileRequest(&f.request)

    let convreq = ConversionRequestBuilder()
      .setComposer(f.composer)
      .setRequest(f.request)
      .setConfig(f.config)
      .setContext(context)
      .setKey("")
      .build()

    var results: [PredictionResult] = []
    dp.aggregateZeroQuery(convreq, &results)
    #expect(!results.isEmpty)

    // "@" -> "gmail.com" should be found in zero_query_dict_
    #expect(DPT.findCandidateByValue(results, "gmail.com"))
  }

  @Test mutating func zeroQuerySuffixSkipWithoutHistory() throws {
    let dp = try MockDataAndPredictor()
    try dp.initialize(TestSuffixDictionary(), nil)

    RequestTestUtil.fillMobileRequest(&f.request)

    // rid == 0, so suffix dictionary should be skipped.
    f.initHistory("key", "value", 0)
    f.request.zeroQuerySuggestion = true

    var context = Genmai_Commands_Context()
    context.precedingText = "東京"

    let convreq = ConversionRequestBuilder()
      .setComposer(f.composer)
      .setRequest(f.request)
      .setConfig(f.config)
      .setContext(context)
      .setKey("")
      .build()

    var results: [PredictionResult] = []
    dp.aggregateZeroQuery(convreq, &results)

    // results should NOT have candidates from TestSuffixDictionary ("以下")
    #expect(!DPT.findCandidateByValue(results, "以下"))
  }
}
