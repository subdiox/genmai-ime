// Port of mozc/src/prediction/result_filter_test.cc (3.35.6354).

import GenmaiBase
import GenmaiStorage
import Testing

@testable import GenmaiCore

struct ResultFilterTests {
  @Test func getMissSpelledPosition() {
    #expect(ResultFilter.getMissSpelledPosition("", "") == 0)
    #expect(ResultFilter.getMissSpelledPosition("れみおめろん", "レミオロメン") == 3)
    #expect(ResultFilter.getMissSpelledPosition("とーとばっく", "トートバッグ") == 5)
    #expect(ResultFilter.getMissSpelledPosition("おーすとりらあ", "オーストラリア") == 4)
    #expect(ResultFilter.getMissSpelledPosition("おーすとりあ", "おーすとらりあ") == 4)
    #expect(ResultFilter.getMissSpelledPosition("じきそうしょう", "時期尚早") == 7)
  }

  @Test func removeRedundantResultsTest() {
    let kResults: [(String, String, Int)] = [
      ("とうきょう", "東京", 100),
      ("とうきょう", "TOKYO", 200),
      ("とうきょうと", "東京都", 110),
      ("とうきょう", "東京", 120),
      ("とうきょう", "TOKYO", 120),
      ("とうきょうわん", "東京湾", 120),
      ("とうきょうえき", "東京駅", 130),
      ("とうきょうべい", "東京ベイ", 140),
      ("とうきょうゆき", "東京行", 150),
      ("とうきょうしぶ", "東京支部", 160),
      ("とうきょうてん", "東京店", 170),
      ("とうきょうがす", "東京ガス", 180),
      ("とうきょう!", "東京!", 1100),
      ("とうきょう!?", "東京!?", 1200),
      ("とうきょう", "東京❤", 1300),
      // "とうきょう → 東京宇" is not an actual word, but an emulation of
      // "さかい → (堺, 堺井)" and "いずみ → (泉, 泉水)".
      ("とうきょう", "東京宇", 1400),
    ]

    var results: [PredictionResult] = []
    for (key, value, cost) in kResults {
      var result = PredictionResult()
      result.key = key
      result.value = value
      result.wcost = cost
      results.append(result)
    }

    ResultFilter.removeRedundantResults(&results)

    func findResultByValue(_ results: [PredictionResult], _ value: String) -> Bool {
      results.contains { $0.value.bytesEqual(value) && !$0.removed }
    }

    #expect(findResultByValue(results, "東京"))
    #expect(findResultByValue(results, "東京宇"))

    var prefixCount = 0
    for result in results where result.value.hasBytePrefix("東京") {
      prefixCount += 1
    }
    // Should not have same prefix candidates a lot.
    #expect(prefixCount <= 11)
    // Candidates that predict symbols should not be handled as the redundant
    // candidates.
    let kExpected = ["東京", "TOKYO", "東京!", "東京!?", "東京❤"]
    for i in 0..<kExpected.count {
      #expect(results[i].value == kExpected[i])
    }
  }

  @Test func selectSuggestionFilterStrategies() {
    // A normal candidate.
    var kTokyo = PredictionResult()
    kTokyo.key = "とうきょう"
    kTokyo.value = "東京"
    // A next word prediction.
    var kNwp = PredictionResult()
    kNwp.key = ""
    kNwp.value = "東京"

    let kSkipFilter = ResultFilter.kSkipFilter
    let kByValue = ResultFilter.kFilterByValue
    let kByHistAndValue =
      ResultFilter.kFilterByValue | ResultFilter.kFilterByHistoryAndValue
      | ResultFilter.kFilterByNwp

    let kTestCases: [(PredictionResult, String, String, Bool, UInt32)] = [
      // Exact candidates without history value.
      (kTokyo, "とうきょう", "", false, kByValue),
      (kTokyo, "とうきょう", "", true, kSkipFilter),
      // Exact candidates with history value.
      (kTokyo, "とうきょう", "西", false, kByValue),
      (kTokyo, "とうきょう", "西", true, kSkipFilter),
      // Completion candidates without history value.
      (kTokyo, "とう", "", false, kByValue),
      (kTokyo, "とう", "", true, kByValue),
      // Completion candidates with history value.
      (kTokyo, "とう", "西", false, kByValue),
      (kTokyo, "とう", "西", true, kByValue),
      // Next word prediction without history value.
      (kNwp, "", "", false, kByHistAndValue),
      (kNwp, "", "", true, kByHistAndValue),
      // Next word prediction with history value.
      (kNwp, "", "西", false, kByHistAndValue),
      (kNwp, "", "西", true, kByHistAndValue),
    ]
    for (result, requestKey, historyValue, includeExactKey, expected) in kTestCases {
      #expect(
        expected
          == ResultFilter.selectSuggestionFilterStrategies(
            result, requestKey, historyValue, includeExactKey))
    }
  }

  @Test(.enabled(if: predictionMockDataAvailable, "mock_genmai.data is missing"))
  func shouldRemoveWithNwpSuggestionFilter() throws {
    var builder = ExistenceFilterBuilder.createOptimal(1024, 1)
    // Entries in SuggestionFilter are stored in lowercase.
    builder.insert("<nwp>京都")
    let suggestionFilter = SuggestionFilter(builder.build())
    // C++ uses a default (empty) Connector; GetTransitionCost is not called.
    let connector = try Connector.create(MockDataManager.create().getConnectorData())

    func result(_ key: String, _ value: String) -> PredictionResult {
      var r = PredictionResult()
      r.key = key
      r.value = value
      return r
    }

    // "<NWP>京都" is suppressed during NWP, while still allowed during normal
    // conversion when the user explicitly types the reading.
    let history = result("ひがし", "東")
    let nwpReq = ConversionRequestBuilder().setHistoryResult(history).build()
    let nwpFilter = ResultFilter(nwpReq, connector, suggestionFilter)
    #expect(nwpFilter.shouldRemove(result("", "京都"), 0))
    #expect(!nwpFilter.shouldRemove(result("", "東京"), 0))

    let convReq = ConversionRequestBuilder().setKey("きょうと").build()
    let convFilter = ResultFilter(convReq, connector, suggestionFilter)
    #expect(!convFilter.shouldRemove(result("きょうと", "京都"), 0))
  }
}
