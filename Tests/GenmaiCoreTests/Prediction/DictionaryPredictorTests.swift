// Port of mozc/src/prediction/dictionary_predictor_test.cc (3.35.6354),
// part 1 (cost / rerank / filter tests with MockAggregator). Part 2 is in
// DictionaryPredictorTests2.swift.

import Foundation
import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private let kUnigram = Attribute.unigram
private let kBigram = Attribute.bigram
private let kRealtime = Attribute.realtimeConversion
private let kRealtimeTop = Attribute.realtimeTop
private let kPartial = Attribute.partiallyKeyConsumed
private let kSuffix = Attribute.suffixDictionary
private let kTypingCorrection = Attribute.typingCorrection
private let kSingleKanji = Attribute.singleKanji
private let kNoAttribute = Token.Attribute.none
private let kSpellingCorrection = Token.Attribute.spellingCorrection
private let kUserDictionary = Token.Attribute.userDictionary

@Suite(
  .enabled(if: predictionMockDataAvailable, "mock_genmai.data is missing"), .scopedConfigEnvironment)
struct DictionaryPredictorTest {
  var f = DPFixture()

  @Test func isAggressiveSuggestion() {
    // "ただしい",
    // "ただしいけめんにかぎる",
    #expect(
      DictionaryPredictor.isAggressiveSuggestion(
        4,  // query_len
        11,  // key_len
        6000,  // cost
        true,  // is_suggestion
        20))  // total_candidates_size

    // cost <= 4000
    #expect(!DictionaryPredictor.isAggressiveSuggestion(4, 11, 4000, true, 20))

    // not suggestion
    #expect(!DictionaryPredictor.isAggressiveSuggestion(4, 11, 4000, false, 20))

    // total_candidates_size is small
    #expect(!DictionaryPredictor.isAggressiveSuggestion(4, 11, 4000, true, 5))

    // query_length = 5
    #expect(!DictionaryPredictor.isAggressiveSuggestion(5, 11, 6000, true, 20))

    // "それでも",
    // "それでもぼくはやっていない",
    #expect(DictionaryPredictor.isAggressiveSuggestion(4, 13, 6000, true, 20))

    // cost <= 4000
    #expect(!DictionaryPredictor.isAggressiveSuggestion(4, 13, 4000, true, 20))
  }

  @Test func removeMissSpelledCandidates() throws {
    let reqLen1 = ConversionRequestBuilder().setKey("1").build()
    let reqLen3 = ConversionRequestBuilder().setKey("111").build()

    do {
      var results = [
        DPT.createResult4("ばっく", "バッグ", kUnigram, kSpellingCorrection),
        DPT.createResult4("ばっぐ", "バッグ", kUnigram, kNoAttribute),
        DPT.createResult4("ばっく", "バッく", kUnigram, kNoAttribute),
      ]
      DictionaryPredictor.removeMissSpelledCandidates(reqLen1, &results)

      try #require(results.count == 3)
      #expect(results[0].removed)
      #expect(!results[1].removed)
      #expect(results[2].removed)
      #expect(results[0].getPredictionTypesForTesting() == kUnigram)
      #expect(results[1].getPredictionTypesForTesting() == kUnigram)
      #expect(results[2].getPredictionTypesForTesting() == kUnigram)
    }
    do {
      var results = [
        DPT.createResult4("ばっく", "バッグ", kUnigram, kSpellingCorrection),
        DPT.createResult4("てすと", "テスト", kUnigram, kNoAttribute),
      ]
      DictionaryPredictor.removeMissSpelledCandidates(reqLen1, &results)

      try #require(results.count == 2)
      #expect(!results[0].removed)
      #expect(!results[1].removed)
      #expect(results[0].getPredictionTypesForTesting() == kUnigram)
      #expect(results[1].getPredictionTypesForTesting() == kUnigram)
    }
    do {
      var results = [
        DPT.createResult4("ばっく", "バッグ", kUnigram, kSpellingCorrection),
        DPT.createResult4("ばっく", "バック", kUnigram, kNoAttribute),
      ]
      DictionaryPredictor.removeMissSpelledCandidates(reqLen1, &results)

      try #require(results.count == 2)
      #expect(results[0].removed)
      #expect(results[1].removed)
    }
    do {
      var results = [
        DPT.createResult4("ばっく", "バッグ", kUnigram, kSpellingCorrection),
        DPT.createResult4("ばっく", "バック", kUnigram, kNoAttribute),
      ]
      DictionaryPredictor.removeMissSpelledCandidates(reqLen3, &results)

      try #require(results.count == 2)
      #expect(!results[0].removed)
      #expect(results[1].removed)
      #expect(results[0].getPredictionTypesForTesting() == kUnigram)
      #expect(results[1].getPredictionTypesForTesting() == kUnigram)
    }
  }

  @Test func getLMCost() throws {
    let dp = try MockDataAndPredictor()
    let connector = dp.connector

    var result = PredictionResult()
    result.wcost = 64

    for rid in 0..<100 {
      for lid in 0..<100 {
        result.lid = UInt16(lid)
        let c1 = connector.getTransitionCost(UInt16(rid), result.lid)
        let c2 = connector.getTransitionCost(0, result.lid)
        result.attributes = kSuffix
        #expect(dp.predictor.getLMCost(result, rid) == c1 + result.wcost)

        result.attributes = kRealtime
        #expect(dp.predictor.getLMCost(result, rid) == min(c1, c2) + result.wcost)
      }
    }
  }

  @Test mutating func setPredictionCostForMixedConversion() throws {
    let dp = try MockDataAndPredictor()

    var results = [
      DPT.createResult4("てすと", "てすと", kUnigram, kNoAttribute),
      DPT.createResult4("てすと", "テスト", kUnigram, kNoAttribute),
      DPT.createResult4("てすとてすと", "テストテスト", kUnigram, kNoAttribute),
    ]

    let convreq = f.createConversionRequest(.prediction, "てすと")
    dp.predictor.setPredictionCostForMixedConversion(convreq, &results)

    #expect(results.count == 3)
    #expect(results[0].value == "てすと")
    #expect(results[1].value == "テスト")
    #expect(results[2].value == "テストテスト")
    #expect(results[2].cost > results[0].cost)
    #expect(results[2].cost > results[1].cost)
  }

  @Test mutating func setLMCostForUserDictionaryWord() throws {
    let dp = try MockDataAndPredictor()

    let kAikaHiragana = "あいか"
    let kAikaKanji = "愛佳"

    do {
      // Cost of words in user dictionary should be decreased.
      let kOriginalWordCost = 10000
      var results = [DPT.createResult5(kAikaHiragana, kAikaKanji, kOriginalWordCost, kUnigram, kUserDictionary)]

      let convreq = f.createConversionRequest(.prediction, kAikaHiragana)
      dp.predictor.setPredictionCostForMixedConversion(convreq, &results)

      #expect(results.count == 1)
      #expect(results[0].value == kAikaKanji)
      #expect(kOriginalWordCost > results[0].cost)
      #expect(1 <= results[0].cost)
    }

    do {
      // Cost of words in user dictionary should not be decreased to below 1.
      let kOriginalWordCost = 10
      var results = [DPT.createResult5(kAikaHiragana, kAikaKanji, kOriginalWordCost, kUnigram, kUserDictionary)]

      let convreq = f.createConversionRequest(.prediction, kAikaHiragana)
      dp.predictor.setPredictionCostForMixedConversion(convreq, &results)

      #expect(results.count == 1)
      #expect(results[0].value == kAikaKanji)
      #expect(kOriginalWordCost > results[0].cost)
      #expect(1 <= results[0].cost)
    }

    do {
      // Cost of general symbols should not be decreased.
      let kOriginalWordCost = 10000
      var results = [DPT.createResult5(kAikaHiragana, kAikaKanji, kOriginalWordCost, kUnigram, kUserDictionary)]
      try #require(results.count == 1)
      results[0].lid = dp.posMatcher.getGeneralSymbolId()
      results[0].rid = results[0].lid

      let convreq = f.createConversionRequest(.prediction, kAikaHiragana)
      dp.predictor.setPredictionCostForMixedConversion(convreq, &results)

      #expect(results.count == 1)
      #expect(results[0].value == kAikaKanji)
      #expect(kOriginalWordCost <= results[0].cost)
    }

    do {
      // Cost of words not in user dictionary should not be decreased.
      let kOriginalWordCost = 10000
      var results = [DPT.createResult5(kAikaHiragana, kAikaKanji, kOriginalWordCost, kUnigram, kNoAttribute)]

      let convreq = f.createConversionRequest(.prediction, kAikaHiragana)
      dp.predictor.setPredictionCostForMixedConversion(convreq, &results)

      #expect(results.count == 1)
      #expect(results[0].value == kAikaKanji)
      #expect(results[0].cost == kOriginalWordCost)
    }
  }

  @Test mutating func suggestSpellingCorrection() throws {
    let dp = try MockDataAndPredictor()
    dp.aggregator.aggregateResultsForDesktopHandler = { _ in
      [
        DPT.createResult5("あぼがど", "アボカド", 500, kUnigram, kSpellingCorrection),
        DPT.createResult5("あぼがど", "アボガド", 500, kUnigram, kNoAttribute),
      ]
    }

    let convreq = f.createConversionRequest(.prediction, "あぼがど")
    let results = dp.predictor.predict(convreq)

    #expect(DPT.findCandidateByValue(results, "アボカド"))
  }

  @Test mutating func doNotSuggestSpellingCorrectionBeforeMismatch() throws {
    let dp = try MockDataAndPredictor()
    dp.aggregator.aggregateResultsForDesktopHandler = { _ in
      [
        DPT.createResult5("あぼがど", "アボカド", 500, kUnigram, kSpellingCorrection),
        DPT.createResult5("あぼがど", "アボガド", 500, kUnigram, kNoAttribute),
      ]
    }

    let convreq = f.createConversionRequest(.prediction, "あぼが")
    let results = dp.predictor.predict(convreq)

    #expect(!DPT.findCandidateByValue(results, "アボカド"))
  }

  @Test mutating func mobileZeroQuery() throws {
    let dp = try MockDataAndPredictor()
    dp.aggregator.aggregateResultsForMixedConversionHandler = { _ in
      [
        DPT.createResult5("", "", 500, kBigram, kNoAttribute),
        DPT.createResult5("いん", "院", 600, kBigram, kNoAttribute),
        DPT.createResult5("せい", "生", 600, kBigram, kNoAttribute),
        DPT.createResult5("やきゅう", "野球", 1000, kBigram, kNoAttribute),
        DPT.createResult5("じゅけん", "受験", 1000, kBigram, kNoAttribute),
        DPT.createResult5("にゅうし", "入試", 1000, kBigram, kNoAttribute),
        DPT.createResult5("にゅうしせんたー", "入試センター", 2000, kBigram, kNoAttribute),
      ]
    }

    f.initHistory("だいがく", "大学")
    f.prependHistory("とうきょう", "東京")  // not used

    RequestTestUtil.fillMobileRequest(&f.request)
    let convreq = f.createConversionRequest(.prediction, "")
    let results = dp.predictor.predict(convreq)

    #expect(DPT.findCandidateByKeyValue(results, "にゅうし", "入試"))
    #expect(DPT.findCandidateByKeyValue(results, "にゅうしせんたー", "入試センター"))
  }

  @Test mutating func predictivePenaltyForBigramResults() throws {
    let dp = try MockDataAndPredictor()
    dp.aggregator.aggregateResultsForMixedConversionHandler = { _ in
      [
        DPT.createResult5("にゅうし", "入試", 3000, kBigram, kNoAttribute),
        DPT.createResult5("にゅうしせんたー", "入試センター", 4000, kBigram, kNoAttribute),
        DPT.createResult5("にゅうしせんたーしけんたいさく", "入試センター試験対策", 5000, kBigram, kNoAttribute),
        DPT.createResult5("にゅうし", "乳歯", 2000, kUnigram, kNoAttribute),
      ]
    }

    f.initHistory("だいがく", "大学")
    f.prependHistory("とうきょう", "東京")  // not used

    RequestTestUtil.fillMobileRequest(&f.request)
    let convreq = f.createConversionRequest(.prediction, "にゅうし")
    let results = dp.predictor.predict(convreq)

    #expect(DPT.rank(results, "乳歯") < DPT.rank(results, "入試センター試験対策"))
  }

  @Test mutating func propagateAttributes() throws {
    let dp = try MockDataAndPredictor()

    // Exact key will not be filtered in mobile request
    RequestTestUtil.fillMobileRequest(&f.request)

    // Small prefix penalty
    do {
      var result = PredictionResult()
      result.cost = 10
      dp.mockDecoder.decodeHandler = { _ in [result] }
    }

    func getTopResult(_ aggregatorResult: PredictionResult) -> PredictionResult? {
      dp.aggregator.aggregateResultsForMixedConversionHandler = { _ in [aggregatorResult] }
      let convreq = f.createConversionRequest(.prediction, "てすと")
      return dp.predictor.predict(convreq).first
    }

    do {
      // PREFIX: consumed_key_size
      var result = DPT.createResult5("てす", "てす", 50, kPartial, kNoAttribute)
      result.consumedKeySize = UInt32(Util.charsLen("てす"))

      let c = try #require(getTopResult(result))
      #expect(c.value == "てす")
      #expect(c.getBehavioralAttributes() == Attribute.partiallyKeyConsumed | Attribute.autoPartialSuggestion)
      #expect(c.consumedKeySize == 2)
    }
    do {
      // REALTIME_TOP
      let result = DPT.createResult5("てすと", "リアルタイムトップ", 100, kRealtimeTop | kRealtime, kNoAttribute)

      let c = try #require(getTopResult(result))
      #expect(c.value == "リアルタイムトップ")
      #expect(c.getBehavioralAttributes() == Attribute.realtimeConversion | Attribute.noVariantsExpansion)
    }
    do {
      // REALTIME: inner_segment_boundary
      var result = DPT.createResult5("てすと", "リアルタイム", 100, kRealtime, kNoAttribute)
      result.innerSegmentBoundary = buildInnerSegmentBoundary(
        [
          ("てす".utf8.count, "リアル".utf8.count, "て".utf8.count, "リア".utf8.count),
          ("と".utf8.count, "タイム".utf8.count, "と".utf8.count, "タイム".utf8.count),
        ], result.key, result.value)
      let c = try #require(getTopResult(result))
      #expect(c.value == "リアルタイム")
      #expect(c.getBehavioralAttributes() == Attribute.realtimeConversion)
      #expect(c.innerSegmentBoundary.count == 2)
    }
    do {
      // SPELLING_CORRECTION
      let result = DPT.createResult5("てすと", "SPELLING_CORRECTION", 300, kUnigram, kSpellingCorrection)

      let c = try #require(getTopResult(result))
      #expect(c.value == "SPELLING_CORRECTION")
      #expect(c.getBehavioralAttributes() == Attribute.spellingCorrection)
    }
    do {
      // TYPING_CORRECTION
      let result = DPT.createResult5("てすと", "TYPING_CORRECTION", 300, kTypingCorrection, kNoAttribute)

      let c = try #require(getTopResult(result))
      #expect(c.value == "TYPING_CORRECTION")
      #expect(c.getBehavioralAttributes() == Attribute.typingCorrection)
    }
    do {
      // USER_DICTIONARY
      let result = DPT.createResult5("てすと", "ユーザー辞書", 300, kUnigram, kUserDictionary)

      let c = try #require(getTopResult(result))
      #expect(c.value == "ユーザー辞書")
      #expect(
        c.getBehavioralAttributes()
          == Attribute.userDictionary | Attribute.noModification | Attribute.noVariantsExpansion)
    }
    do {
      // removed
      var result = DPT.createResult5("てすと", "REMOVED", 300, kBigram, kNoAttribute)
      result.removed = true

      #expect(getTopResult(result) == nil)
    }
  }

  @Test mutating func mergeAttributesForDebug() throws {
    let dp = try MockDataAndPredictor()

    var results = [
      DPT.createResult4("a0", "A0", kRealtime, kNoAttribute),
      DPT.createResult4("a1", "A1", kRealtime, kNoAttribute),
      DPT.createResult4("a2", "A2", kRealtime, kNoAttribute),
      DPT.createResult4("a3", "A3", kRealtime, kNoAttribute),
      DPT.createResult4("a0", "A0", kSuffix, kNoAttribute),
      DPT.createResult4("a1", "A1", kSuffix, kNoAttribute),
      DPT.createResult4("a2", "A2", kSuffix, kNoAttribute),
      DPT.createResult4("a3", "A3", kSuffix, kNoAttribute),
    ]

    results.shuffle()

    // Enables debug mode.
    f.config.verboseLevel = 1
    let convreq = f.createConversionRequest(.suggestion, "test")
    results = dp.predictor.rerankAndFilterResults(convreq, results)

    for result in results {
      #expect(result.description == "RS")
    }
  }

  @Test mutating func propagateResultCosts() throws {
    let dp = try MockDataAndPredictor()

    let kTestSize = 20
    var results = PT.results(kTestSize)
    for i in 0..<kTestSize {
      results[i].key = String(UnicodeScalar(UInt8(ascii: "a") + UInt8(i)))
      results[i].value = String(UnicodeScalar(UInt8(ascii: "A") + UInt8(i)))
      results[i].wcost = i
      results[i].cost = i + 1000
      results[i].setTypesAndTokenAttributes(kRealtime, kNoAttribute)
    }
    results.shuffle()

    let convreq = f.createConversionRequestWithOptions(
      DPFixture.options(.suggestion, maxDictionaryPredictionCandidatesSize: kTestSize), "test")

    results = dp.predictor.rerankAndFilterResults(convreq, results)

    try #require(kTestSize == results.count)
    for i in 0..<results.count {
      #expect(results[i].cost == i + 1000)
    }
  }

  @Test mutating func predictNCandidates() throws {
    let dp = try MockDataAndPredictor()

    let kTotalCandidateSize = 100
    let kLowCostCandidateSize = 5
    var results = PT.results(kTotalCandidateSize)
    for i in 0..<kTotalCandidateSize {
      results[i].key = String(UnicodeScalar(UInt8(ascii: "a") + UInt8(i)))
      results[i].value = String(UnicodeScalar(UInt8(ascii: "A") + UInt8(i)))
      results[i].wcost = i
      results[i].setTypesAndTokenAttributes(kRealtime, kNoAttribute)
      if i < kLowCostCandidateSize {
        results[i].cost = i + 1000
      } else {
        results[i].cost = i + PredictionResult.invalidCost
      }
    }
    results.shuffle()

    let convreq = f.createConversionRequestWithOptions(
      DPFixture.options(
        .suggestion, maxDictionaryPredictionCandidatesSize: kLowCostCandidateSize + 1), "test")

    results = dp.predictor.rerankAndFilterResults(convreq, results)

    try #require(kLowCostCandidateSize == results.count)
    for i in 0..<results.count {
      #expect(results[i].cost == i + 1000)
    }
  }

  @Test mutating func suggestFilteredwordForExactMatchOnMobile() throws {
    let dp = try MockDataAndPredictor()
    // turn on mobile mode
    RequestTestUtil.fillMobileRequest(&f.request)

    dp.aggregator.aggregateResultsForMixedConversionHandler = { _ in
      [
        DPT.createResult5("ふぃるたーたいしょう", "フィルター対象", 100, kUnigram, kNoAttribute),
        DPT.createResult5("ふぃるたーたいしょう", "フィルター大将", 200, kUnigram, kNoAttribute),
      ]
    }

    // Note: The suggestion filter entry "フィルター" for test is not
    // appropriate here, as Katakana entry will be added by real time
    // conversion. Here, we want to confirm the behavior including unigram
    // prediction.
    let convreq1 = f.createConversionRequest(.suggestion, "ふぃるたーたいしょう")
    var results = dp.predictor.predict(convreq1)
    #expect(DPT.findCandidateByValue(results, "フィルター対象"))
    #expect(DPT.findCandidateByValue(results, "フィルター大将"))

    // However, filtered word should not be the top.
    #expect(results.first?.value == "フィルター大将")

    // Should not be there for non-exact suggestion.
    let convreq2 = f.createConversionRequest(.suggestion, "ふぃるたーたいし")
    results = dp.predictor.predict(convreq2)
    #expect(!DPT.findCandidateByValue(results, "フィルター対象"))
  }

  @Test mutating func suppressFilteredwordForExactMatch() throws {
    let dp = try MockDataAndPredictor()

    dp.aggregator.aggregateResultsForDesktopHandler = { _ in
      [
        DPT.createResult5("ふぃるたーたいしょう", "フィルター対象", 100, kUnigram, kNoAttribute),
        DPT.createResult5("ふぃるたーたいしょう", "フィルター大将", 200, kUnigram, kNoAttribute),
      ]
    }

    let convreq = f.createConversionRequest(.suggestion, "ふぃるたーたいしょう")
    let results = dp.predictor.predict(convreq)
    #expect(!DPT.findCandidateByValue(results, "フィルター対象"))
  }

  @Test mutating func doNotFilterExactUnigramOnMobile() throws {
    let dp = try MockDataAndPredictor()
    RequestTestUtil.fillMobileRequest(&f.request)

    var aggregated: [PredictionResult] = []
    for i in 0..<30 {
      // Exact entries
      aggregated.append(DPT.createResult5("てすと", "\(i)テストE", 5000 + i, kUnigram, kNoAttribute))
      // Predictive entries
      aggregated.append(DPT.createResult5("てすとて", "\(i)テストP", 100 + i, kUnigram, kNoAttribute))
    }
    dp.aggregator.aggregateResultsForMixedConversionHandler = { _ in aggregated }

    let convreq = f.createConversionRequestWithOptions(
      DPFixture.options(.prediction, maxDictionaryPredictionCandidatesSize: 100), "てすと")
    let results = dp.predictor.predict(convreq)
    let exactCount = results.filter { $0.value.contains("テストE") }.count
    #expect(exactCount == 30)
  }

  @Test mutating func doNotFilterUnigrmsForHandwriting() throws {
    let dp = try MockDataAndPredictor()

    // Destkop doesn't support handwriting.
    RequestTestUtil.fillMobileRequest(&f.request)

    // Fill handwriting request and composer
    f.request.zeroQuerySuggestion = true
    f.request.mixedConversion = true
    f.request.kanaModifierInsensitiveConversion = false
    f.request.autoPartialSuggestion = false
    f.composer.setCompositionsForHandwriting(DPFixture.compositionEvents([("かん字", 1.0)]))

    var aggregated: [PredictionResult] = []
    for i in 0..<10 {
      // Exact entries
      aggregated.append(DPT.createResult5("かん字", "\(i)漢字E", 5000 + i, kUnigram, kNoAttribute))
    }
    for i in 0..<10 {
      // Keys can be longer than the segment key
      aggregated.append(DPT.createResult5("かんじよみ", "\(i)漢字E", 5000 + i, kUnigram, kNoAttribute))
    }
    dp.aggregator.aggregateResultsForMixedConversionHandler = { _ in aggregated }

    let convreqForPrediction = f.createConversionRequestWithOptions(
      DPFixture.options(.prediction, maxDictionaryPredictionCandidatesSize: 100), "かん字")
    let results = dp.predictor.predict(convreqForPrediction)
    let exactCount = results.filter { $0.value.contains("漢字E") }.count
    #expect(exactCount == 20)
  }

  @Test mutating func doNotFilterZeroQueryCandidatesOnMobile() throws {
    let dp = try MockDataAndPredictor()
    RequestTestUtil.fillMobileRequest(&f.request)

    // Entries for zero query
    var aggregated: [PredictionResult] = []
    for i in 0..<10 {
      aggregated.append(DPT.createResult5("てすと", "\(i)テストS", 100, kSuffix, kNoAttribute))
    }
    dp.aggregator.aggregateResultsForMixedConversionHandler = { _ in aggregated }

    f.initHistory("わたし", "私")
    let convreq = f.createConversionRequest(.prediction, "")
    let results = dp.predictor.predict(convreq)
    #expect(results.count == 10)
  }

  @Test mutating func doNotFilterOneSegmentRealtimeCandidatesOnMobile() throws {
    let dp = try MockDataAndPredictor()
    // turn on mobile mode
    RequestTestUtil.fillMobileRequest(&f.request)

    var aggregated: [PredictionResult] = []
    func add(
      _ key: String, _ value: String, _ wcost: Int, _ types: PredictionTypes,
      _ b: (Int, Int, Int, Int)
    ) {
      var r = DPT.createResult5(key, value, wcost, types, kNoAttribute)
      DPT.pushBackInnerSegmentBoundary(b.0, b.1, b.2, b.3, &r)
      aggregated.append(r)
    }
    add("かった", "買った", 300, kRealtimeTop | kRealtime, (9, 9, 9, 9))
    add("かった", "飼った", 1000, kRealtime, (9, 9, 9, 9))
    add("かつた", "勝田", 1001, kRealtime, (9, 6, 9, 6))
    add("かつた", "勝太", 1002, kRealtime, (9, 6, 9, 6))
    add("かつた", "鹿田", 1003, kRealtime, (9, 6, 9, 6))
    add("かつた", "かつた", 1004, kRealtime, (9, 9, 9, 9))
    add("かった", "刈った", 1005, kRealtime, (9, 9, 9, 9))
    add("かった", "勝った", 1006, kRealtime, (9, 9, 9, 9))
    dp.aggregator.aggregateResultsForMixedConversionHandler = { _ in aggregated }

    let convreq = f.createConversionRequest(.prediction, "かつた")
    let results = dp.predictor.predict(convreq)
    #expect(results.count >= 8)
  }

  @Test mutating func fixSRealtimeTopCandidatesCostOnMobile() throws {
    let dp = try MockDataAndPredictor()
    // turn on mobile mode
    RequestTestUtil.fillMobileRequest(&f.request)

    var aggregated: [PredictionResult] = []
    func add(
      _ key: String, _ value: String, _ wcost: Int, _ types: PredictionTypes,
      _ b: (Int, Int, Int, Int)
    ) {
      var r = DPT.createResult5(key, value, wcost, types, kNoAttribute)
      DPT.pushBackInnerSegmentBoundary(b.0, b.1, b.2, b.3, &r)
      aggregated.append(r)
    }
    add("かった", "買った", 1002, kRealtimeTop | kRealtime, (9, 9, 9, 9))
    add("かった", "飼った", 1000, kRealtime, (9, 9, 9, 9))
    add("かつた", "勝田", 1001, kRealtime, (9, 6, 9, 6))
    dp.aggregator.aggregateResultsForMixedConversionHandler = { _ in aggregated }

    let convreq = f.createConversionRequest(.prediction, "かった")
    let results = dp.predictor.predict(convreq)
    #expect(results.first?.value == "買った")
  }

  @Test mutating func singleKanjiCost() throws {
    let dp = try MockDataAndPredictor()
    // turn on mobile mode
    RequestTestUtil.fillMobileRequest(&f.request)

    var aggregated = [
      DPT.createResult5("さか", "坂", 400, kRealtime, kNoAttribute),
      DPT.createResult5("さが", "佐賀", 500, kRealtime, kNoAttribute),
      DPT.createResult5("さか", "咲か", 2000, kUnigram, kNoAttribute),
      DPT.createResult5("さか", "阪", 2500, kUnigram, kNoAttribute),
      DPT.createResult5("さか", "サカ", 10000, kUnigram, kNoAttribute),
      DPT.createResult5("さがす", "探す", 300, kUnigram, kNoAttribute),
      DPT.createResult5("さがし", "探し", 3000, kUnigram, kNoAttribute),
      DPT.createResult5("さかい", "堺", 800, kUnigram, kNoAttribute),
      DPT.createResult5("さか", "坂", 9000, kUnigram, kNoAttribute),
      DPT.createResult5("さか", "逆", 0, kSingleKanji, kNoAttribute),
      DPT.createResult5("さか", "坂", 1, kSingleKanji, kNoAttribute),
      DPT.createResult5("さか", "酒", 2, kSingleKanji, kNoAttribute),
      DPT.createResult5("さか", "栄", 3, kSingleKanji, kNoAttribute),
      DPT.createResult5("さか", "盛", 4, kSingleKanji, kNoAttribute),
      DPT.createResult5("さ", "差", 1000, kSingleKanji, kNoAttribute),
      DPT.createResult5("さ", "佐", 1001, kSingleKanji, kNoAttribute),
    ]
    for i in aggregated.indices {
      if aggregated[i].attributes == kSingleKanji {
        aggregated[i].lid = dp.posMatcher.getGeneralSymbolId()
        aggregated[i].rid = dp.posMatcher.getGeneralSymbolId()
      } else {
        aggregated[i].lid = dp.posMatcher.getGeneralNounId()
        aggregated[i].rid = dp.posMatcher.getGeneralNounId()
      }
    }
    let input = aggregated
    dp.aggregator.aggregateResultsForMixedConversionHandler = { _ in input }

    let convreq = f.createConversionRequest(.prediction, "さか")
    let results = dp.predictor.predict(convreq)
    func rank(_ v: String) -> Int { DPT.rank(results, v) }
    #expect(rank("佐") != -1)
    #expect(rank("佐") < results.count - 1)
    #expect(rank("坂") < rank("逆"))
    #expect(rank("咲か") < rank("逆"))
    #expect(rank("阪") < rank("逆"))
    #expect(rank("逆") < rank("差"))
  }

  @Test mutating func singleKanjiFallbackOffsetCost() throws {
    let dp = try MockDataAndPredictor()
    // turn on mobile mode
    RequestTestUtil.fillMobileRequest(&f.request)

    var aggregated = [
      DPT.createResult5("ああ", "ああ", 5000, kUnigram, kNoAttribute),
      DPT.createResult5("ああ", "アア", 4500, kUnigram, kNoAttribute),
      DPT.createResult5("ああ", "吁", 0, kSingleKanji, kNoAttribute),
      DPT.createResult5("ああ", "咨", 1, kSingleKanji, kNoAttribute),
      DPT.createResult5("ああ", "噫", 2, kSingleKanji, kNoAttribute),
      DPT.createResult5("あ", "亜", 1000, kSingleKanji, kNoAttribute),
      DPT.createResult5("あ", "亞", 1001, kSingleKanji, kNoAttribute),
    ]
    for i in aggregated.indices {
      if aggregated[i].attributes == kSingleKanji {
        aggregated[i].lid = dp.posMatcher.getGeneralSymbolId()
        aggregated[i].rid = dp.posMatcher.getGeneralSymbolId()
      } else {
        aggregated[i].lid = dp.posMatcher.getGeneralNounId()
        aggregated[i].rid = dp.posMatcher.getGeneralNounId()
      }
    }
    let input = aggregated
    dp.aggregator.aggregateResultsForMixedConversionHandler = { _ in input }

    let convreq = f.createConversionRequest(.prediction, "ああ")
    let results = dp.predictor.predict(convreq)
    try #require(results.count == 7)
    try #require(results[0].value == "アア")
    try #require(results[1].value == "ああ")
  }

  @Test mutating func dedup() throws {
    let dp = try MockDataAndPredictor()
    // turn on mobile mode
    RequestTestUtil.fillMobileRequest(&f.request)

    let kSize = 5
    var results: [PredictionResult] = []
    for i in 0..<kSize {
      results.append(DPT.createResult6("test", "value\(i)", 0, i, kRealtime, kNoAttribute))
      results.append(DPT.createResult6("test", "value\(i)", 0, kSize + i, kPartial, kNoAttribute))
      results.append(DPT.createResult6("test", "value\(i)", 0, 2 * kSize + i, kTypingCorrection, kNoAttribute))
      results.append(DPT.createResult6("test", "value\(i)", 0, 3 * kSize + i, kUnigram, kNoAttribute))
    }

    let convreq = f.createConversionRequest(.prediction, "test")
    results = dp.predictor.rerankAndFilterResults(convreq, results)
    #expect(results.count == kSize)
  }

  @Test mutating func typingCorrectionResultsLimit() throws {
    let dp = try MockDataAndPredictor()

    // turn on mobile mode
    RequestTestUtil.fillMobileRequest(&f.request)

    var results = [
      DPT.createResult6("tc_key0", "tc_value0", 0, 0, kTypingCorrection, kNoAttribute),
      DPT.createResult6("tc_key0", "tc_value1", 0, 1, kTypingCorrection, kNoAttribute),
      DPT.createResult6("tc_key0", "tc_value2", 0, 2, kTypingCorrection, kNoAttribute),
      DPT.createResult6("tc_key1", "tc_value3", 0, 3, kTypingCorrection, kNoAttribute),
      DPT.createResult6("tc_key1", "tc_value4", 0, 4, kTypingCorrection, kNoAttribute),
      DPT.createResult6("tc_key1", "tc_value5", 0, 5, kTypingCorrection, kNoAttribute),
      DPT.createResult6("tc_key1", "tc_value6", 0, 6, kTypingCorrection, kNoAttribute),
    ]

    let convreq = f.createConversionRequest(.prediction, "original_key")
    results = dp.predictor.rerankAndFilterResults(convreq, results)

    #expect(results.count == 3)
    #expect(DPT.findCandidateByValue(results, "tc_value0"))
    #expect(DPT.findCandidateByValue(results, "tc_value1"))
    #expect(DPT.findCandidateByValue(results, "tc_value2"))
  }

  @Test mutating func sortResult() throws {
    let dp = try MockDataAndPredictor()
    // turn on mobile mode
    RequestTestUtil.fillMobileRequest(&f.request)

    var results = [
      DPT.createResult6("test", "テストＡ", 0, 10, kUnigram, kNoAttribute),
      DPT.createResult6("test", "テストＢ", 0, 100, kUnigram, kNoAttribute),
      DPT.createResult6("test", "テスト０００", 0, 1, kUnigram, kNoAttribute),
      DPT.createResult6("test", "テスト００", 0, 1, kUnigram, kNoAttribute),
      DPT.createResult6("test", "テスト１０", 0, 1, kUnigram, kNoAttribute),
      DPT.createResult6("test", "テスト０", 0, 1, kUnigram, kNoAttribute),
      DPT.createResult6("test", "テスト１", 0, 1, kUnigram, kNoAttribute),
    ]
    let convreq = f.createConversionRequest(.prediction, "test")
    results = dp.predictor.rerankAndFilterResults(convreq, results)

    try #require(results.count == 7)
    try #require(results[0].value == "テスト０")  // cost:1
    try #require(results[1].value == "テスト１")  // cost:1
    try #require(results[2].value == "テスト００")  // cost:1
    try #require(results[3].value == "テスト１０")  // cost:1
    try #require(results[4].value == "テスト０００")  // cost:1
    try #require(results[5].value == "テストＡ")  // cost:10
    try #require(results[6].value == "テストＢ")  // cost:100
  }

  @Test mutating func setCostForRealtimeTopCandidate() throws {
    let dp = try MockDataAndPredictor()

    dp.aggregator.aggregateResultsForDesktopHandler = { _ in
      [
        DPT.createResult5("あいう", "会いう", 100, kRealtimeTop | kRealtime, kNoAttribute),
        DPT.createResult5("あいうえ", "会いうえ", 1000, kRealtime, kNoAttribute),
      ]
    }

    f.request.mixedConversion = false
    let convreq = f.createConversionRequestWithOptions(
      DPFixture.options(.suggestion, useActualConverterForRealtimeConversion: true), "あいう")

    let results = dp.predictor.predict(convreq)
    #expect(results.count == 2)
    #expect(results.first?.value == "会いう")
  }

  @Test mutating func invalidPrefixCandidate() throws {
    let dp = try MockDataAndPredictor()

    // Exact key will not be filtered in mobile request
    RequestTestUtil.fillMobileRequest(&f.request)

    do {
      var result = PredictionResult()
      result.key = "ーひー"
      result.value = "ーひー"
      result.key = "ーひー"
      result.cost = 0
      dp.mockDecoder.decodeHandler = { _ in [result] }
    }

    dp.aggregator.aggregateResultsForDesktopHandler = { _ in
      [
        DPT.createResult6("こ", "子", 0, 10, kPartial, kNoAttribute),
        DPT.createResult6("こーひー", "コーヒー", 0, 100, kUnigram, kNoAttribute),
        DPT.createResult6("こーひー", "珈琲", 0, 200, kUnigram, kNoAttribute),
        DPT.createResult6("こーひー", "coffee", 0, 300, kUnigram, kNoAttribute),
      ]
    }

    let convreq = f.createConversionRequest(.prediction, "こーひー")
    let results = dp.predictor.predict(convreq)
    #expect(!DPT.findCandidateByValue(results, "子"))
  }

  @Test mutating func aggregateTypingCorrectedResultsTest() throws {
    let supplementalModel = PredictionMockSupplementalModel()
    supplementalModel.correctCompositionHandler = { _ in
      [
        TypeCorrectedQuery(correction: "とうきょう", type: [.correction, .completion], score: 0, bias: 0),
        TypeCorrectedQuery(correction: "とうきょう", type: .completion, score: 0, bias: 0),
      ]
    }
    let dp = try MockDataAndPredictor(supplementalModel)
    dp.mockDecoder.decodeHandler = PredictionMockRealtimeDecoder.decodeImpl

    f.config.useTypingCorrection = true

    // 0.8 900
    do {
      let convreq = f.createConversionRequest(.prediction, "とあきよう")
      let results = dp.predictor.aggregateTypingCorrectedResultsForMixedConversion(convreq)
      #expect(results.count == 2)
    }

    // disable typing correction.
    do {
      f.config.useTypingCorrection = false
      let convreq = f.createConversionRequest(.prediction, "とあきよう")
      let results = dp.predictor.aggregateTypingCorrectedResultsForMixedConversion(convreq)
      #expect(results.isEmpty)
    }
  }

  @Test mutating func rescoring() throws {
    let supplementalModel = PredictionMockSupplementalModel()
    supplementalModel.rescoreResultsHandler = { _, results in
      for i in results.indices { results[i].cost = 100 }
    }

    let dp = try MockDataAndPredictor(supplementalModel)
    dp.aggregator.aggregateResultsForDesktopHandler = { _ in
      [
        DPT.createResult5("こーひー", "コーヒー", 500, kUnigram, kNoAttribute),
        DPT.createResult5("こーひー", "珈琲", 600, kUnigram, kNoAttribute),
        DPT.createResult5("こーひー", "coffee", 700, kUnigram, kNoAttribute),
      ]
    }

    let convreq = f.createConversionRequest(.prediction, "こーひー")
    let results = dp.predictor.predict(convreq)

    try #require(results.count == 3)
    #expect(results.map(\.cost) == [100, 100, 100])
  }

  @Test mutating func doNotRescoreHandwriting() throws {
    // Use StrictMock to make sure that RescoreResults(), PostCorrect() are not
    // be called
    let supplementalModel = PredictionMockSupplementalModel()
    let dp = try MockDataAndPredictor(supplementalModel)

    // Fill handwriting config, request and composer
    f.config.useTypingCorrection = false
    f.request.zeroQuerySuggestion = true
    f.request.mixedConversion = false
    f.request.kanaModifierInsensitiveConversion = false
    f.request.autoPartialSuggestion = false
    f.composer.setCompositionsForHandwriting(DPFixture.compositionEvents([("かん字", 1.0)]))

    dp.aggregator.aggregateResultsForDesktopHandler = { _ in
      [
        DPT.createResult5("かんじ", "かん字", 0, kUnigram, kNoAttribute),
        DPT.createResult5("かんじ", "漢字", 500, kUnigram, kNoAttribute),
      ]
    }

    let convreq = f.createConversionRequest(.prediction, "かんじ")
    _ = dp.predictor.predict(convreq)
    // StrictMock: no call is made to the supplemental model.
    #expect(supplementalModel.calls.isEmpty, "\(supplementalModel.calls)")
  }

  @Test mutating func doNotApplyPostCorrection() throws {
    let supplementalModel = PredictionMockSupplementalModel()
    let dp = try MockDataAndPredictor(supplementalModel)

    f.config.useTypingCorrection = false

    dp.aggregator.aggregateResultsForDesktopHandler = { _ in
      [
        DPT.createResult5("かんじ", "かん字", 0, kUnigram, kNoAttribute),
        DPT.createResult5("かんじ", "漢字", 500, kUnigram, kNoAttribute),
      ]
    }

    let convreq = f.createConversionRequest(.prediction, "かんじ")
    _ = dp.predictor.predict(convreq)
  }

  @Test mutating func maybeGetPreviousTopResultTest() throws {
    let dp = try MockDataAndPredictor()
    let peer = dp.predictor

    // Result for しがこ (Initialize the prev_top).
    let initTop = DPT.createResult4("しがこ", "志賀湖", kUnigram, kNoAttribute)

    // Result for しがこう
    var preTop = DPT.createResult4("しがこうげん", "志賀高原", kUnigram, kNoAttribute)

    // Result for しがこうげ. Inconsistent with prev top.
    var curTop = DPT.createResult4("しがこうげ", "子が原", kUnigram, kNoAttribute)

    // Result for しがこうげ, but already consistent with the prev_top.
    var curAlreadyConsintentTop = DPT.createResult4("しがこうげんすきー", "志賀高原スキー", kUnigram, kNoAttribute)

    preTop.cost = 1000
    curTop.cost = 500
    curAlreadyConsintentTop.cost = 500

    func createRequest(_ key: String) -> ConversionRequest {
      f.createConversionRequest(.suggestion, key)
    }
    func setMaxDiff(_ v: Int32) {
      f.request.decoderExperimentParams.candidateConsistencyCostMaxDiff = v
    }

    // max diff is zero. No insertion happens.
    do {
      setMaxDiff(0)
      #expect(peer.maybeGetPreviousTopResult(initTop, createRequest("しが")) == nil)
      #expect(peer.maybeGetPreviousTopResult(preTop, createRequest("しがこう")) == nil)
      #expect(peer.maybeGetPreviousTopResult(preTop, createRequest("しがこうげ")) == nil)
    }

    // max diff is 2000.
    do {
      setMaxDiff(2000)
      #expect(peer.maybeGetPreviousTopResult(initTop, createRequest("しが")) == nil)
      #expect(peer.maybeGetPreviousTopResult(preTop, createRequest("しがこう")) == nil)
      let result = peer.maybeGetPreviousTopResult(curTop, createRequest("しがこうげ"))
      #expect(result != nil)
      #expect(result?.value == "志賀高原")
    }

    // top is partial
    do {
      #expect(peer.maybeGetPreviousTopResult(initTop, createRequest("しが")) == nil)
      #expect(peer.maybeGetPreviousTopResult(preTop, createRequest("しがこう")) == nil)
      var curTopPrefix = curTop
      curTopPrefix.attributes |= kPartial
      #expect(peer.maybeGetPreviousTopResult(curTopPrefix, createRequest("しがこうげ")) == nil)
    }

    // Already consistent.
    do {
      #expect(peer.maybeGetPreviousTopResult(initTop, createRequest("しが")) == nil)
      #expect(peer.maybeGetPreviousTopResult(preTop, createRequest("しがこう")) == nil)
      #expect(
        peer.maybeGetPreviousTopResult(curAlreadyConsintentTop, createRequest("しがこうげ")) == nil)
    }

    // max diff is 200 -> not inserted
    do {
      setMaxDiff(200)
      #expect(peer.maybeGetPreviousTopResult(initTop, createRequest("しが")) == nil)
      #expect(peer.maybeGetPreviousTopResult(preTop, createRequest("しがこう")) == nil)
      #expect(peer.maybeGetPreviousTopResult(curTop, createRequest("しがこうげ")) == nil)
    }

    // No insertion happens when typing backspaces.
    do {
      setMaxDiff(2000)
      #expect(peer.maybeGetPreviousTopResult(curTop, createRequest("しがこうげ")) == nil)
      #expect(peer.maybeGetPreviousTopResult(preTop, createRequest("しがこう")) == nil)
      #expect(peer.maybeGetPreviousTopResult(initTop, createRequest("しが")) == nil)
    }

    // No insertion happens for zero-query suggestion or right after
    // zero-query suggestion, or when key length does not increase.
    do {
      setMaxDiff(2000)
      #expect(peer.maybeGetPreviousTopResult(preTop, createRequest("しがこう")) == nil)

      // Same request key length -> not inserted.
      #expect(peer.maybeGetPreviousTopResult(curTop, createRequest("しがこう")) == nil)

      // Zero-query suggestion -> not inserted and resets state.
      var nwpTop = DPT.createResult4("", "高原", Attribute.supplementalModel, kNoAttribute)
      nwpTop.cost = 500
      #expect(peer.maybeGetPreviousTopResult(nwpTop, createRequest("")) == nil)
      #expect(peer.maybeGetPreviousTopResult(preTop, createRequest("")) == nil)
      #expect(peer.maybeGetPreviousTopResult(nwpTop, createRequest("")) == nil)

      // First input after zero-query suggestion -> not inserted.
      #expect(peer.maybeGetPreviousTopResult(curTop, createRequest("しがこうげ")) == nil)
    }

    // RerankAndFilterResults skips removed candidates and deduplicates
    // prev_top_result.
    do {
      setMaxDiff(2000)

      var results1 = [preTop]
      results1 = peer.rerankAndFilterResults(createRequest("しがこう"), results1)
      try #require(results1.count == 1)
      #expect(results1[0].value == "志賀高原")

      var removedTop = DPT.createResult4("しが", "滋賀", kBigram, kNoAttribute)
      removedTop.cost = 1
      removedTop.removed = true

      var results2 = [removedTop, curTop, preTop]
      results2 = peer.rerankAndFilterResults(createRequest("しがこうげ"), results2)
      try #require(results2.count == 2)
      #expect(results2[0].value == "志賀高原")
      #expect(results2[1].value == "子が原")
    }

    // When all candidates are filtered out, prev_top state is not updated.
    // The stale prev_top is promoted only when it is still consistent with
    // the current top key (prefix match), and never for an unrelated key.
    do {
      setMaxDiff(2000)

      // "しがこう" -> 志賀高原 (しがこうげん) is stored as prev_top.
      var results1 = [preTop]
      results1 = peer.rerankAndFilterResults(createRequest("しがこう"), results1)
      try #require(results1.count == 1)
      #expect(results1[0].value == "志賀高原")

      // "しがこうげ" -> every candidate is removed. No state update happens.
      var removedTop = curTop
      removedTop.removed = true
      var results2 = [removedTop]
      results2 = peer.rerankAndFilterResults(createRequest("しがこうげ"), results2)
      #expect(results2.isEmpty)

      // "しがこうげん" -> 志賀高原 is still promoted since its key starts with
      // the current top key "しがこうげ".
      var results3 = [curTop]
      results3 = peer.rerankAndFilterResults(createRequest("しがこうげん"), results3)
      try #require(results3.count == 2)
      #expect(results3[0].value == "志賀高原")
      #expect(results3[1].value == "子が原")

      // "あいうえおかきく" (longer key) -> the stale 志賀高原 is never promoted
      // for an unrelated key.
      var otherTop = DPT.createResult4("あいう", "愛鵜", kUnigram, kNoAttribute)
      otherTop.cost = 500
      var results4 = [otherTop]
      results4 = peer.rerankAndFilterResults(createRequest("あいうえおかきく"), results4)
      try #require(results4.count == 1)
      #expect(results4[0].value == "愛鵜")
    }
  }

  @Test mutating func filterNwpSuffixCandidates() throws {
    let dp = try MockDataAndPredictor()
    let connector = dp.connector
    RequestTestUtil.fillMobileRequest(&f.request)
    let kThreshold: Int32 = 1000
    f.request.decoderExperimentParams.suffixNwpTransitionCostThreshold = kThreshold

    do {
      var result = PredictionResult()
      result.key = "てすと"
      result.value = "テスト"
      result.attributes = kSuffix
      result.cost = 1000
      result.lid = dp.posMatcher.getGeneralNounId()
      result.rid = dp.posMatcher.getGeneralNounId()
      let aggregated = [result]
      dp.aggregator.aggregateResultsForMixedConversionHandler = { _ in aggregated }
    }

    let testIds = [
      dp.posMatcher.getGeneralNounId(),
      dp.posMatcher.getGeneralSymbolId(),
      dp.posMatcher.getFunctionalId(),
      dp.posMatcher.getAdverbId(),
      dp.posMatcher.getCounterSuffixWordId(),
    ]

    for id in testIds {
      f.initHistory("こみっと", "コミット")
      f.historyResult.rid = id
      let convreq = f.createConversionRequestWithOptions(
        DPFixture.options(.prediction, maxDictionaryPredictionCandidatesSize: 100), "")
      if connector.getTransitionCost(id, dp.posMatcher.getGeneralNounId()) > Int(kThreshold) {
        #expect(dp.predictor.predict(convreq).isEmpty)
      } else {
        let results = dp.predictor.predict(convreq)
        #expect(results.count == 1)
        #expect(results.first?.value == "テスト")
      }
    }
  }
}
