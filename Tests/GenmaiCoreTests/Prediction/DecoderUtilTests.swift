// Port of mozc/src/prediction/decoder_util_test.cc (3.35.6354).

import GenmaiBase
import Testing

@testable import GenmaiCore

struct DecoderUtilTests {
  @Test func getCandidateCutoffThreshold() {
    #expect(DecoderUtil.getCandidateCutoffThreshold(.prediction) == kPredictionMaxResultsSize)
    #expect(
      DecoderUtil.getCandidateCutoffThreshold(.partialPrediction) == kPredictionMaxResultsSize)
    #expect(DecoderUtil.getCandidateCutoffThreshold(.suggestion) == kSuggestionMaxResultsSize)
    #expect(
      DecoderUtil.getCandidateCutoffThreshold(.partialSuggestion) == kSuggestionMaxResultsSize)
  }

  @Test func resultsSizeAdjuster() {
    let request = ConversionRequestBuilder().setRequestType(.suggestion).build()
    var results = PT.results(10)

    do {
      let adjuster = ResultsSizeAdjuster(request, results)
      #expect(adjuster.cutoffThreshold == kSuggestionMaxResultsSize)
      for _ in 0..<300 {
        results.append(PredictionResult())
      }
      // Added 300 results (>= 256 cutoff threshold).
      adjuster.adjustSize(&results)
    }
    // Should be rolled back to 10.
    #expect(results.count == 10)

    do {
      let adjuster = ResultsSizeAdjuster(request, results)
      for _ in 0..<50 {
        results.append(PredictionResult())
      }
      #expect(adjuster.getAddedResults(results).count == 50)
      adjuster.adjustSize(&results)
    }
    // Not exceeding cutoff threshold, size is kept.
    #expect(results.count == 60)
  }

  @Test func isNoisyNumberToken() {
    var token = Token()
    // Non-number key
    token.key = "とうきょう"
    token.value = "東京"
    #expect(!DecoderUtil.isNoisyNumberToken("とうきょう", 15, token))

    // Key is "1"
    token.key = "10がつ"
    token.value = "10月"
    #expect(DecoderUtil.isNoisyNumberToken("1", 1, token))

    token.key = "1じ"
    token.value = "12時"
    #expect(DecoderUtil.isNoisyNumberToken("1", 1, token))

    token.key = "101ぴきわんちゃん"
    token.value = "101匹わんちゃん"
    #expect(DecoderUtil.isNoisyNumberToken("101", 3, token))

    token.key = "1"
    token.value = "1"
    #expect(!DecoderUtil.isNoisyNumberToken("1", 1, token))

    token.key = "1がつ"
    token.value = "1月"
    #expect(!DecoderUtil.isNoisyNumberToken("1", 1, token))
  }

  @Test func predictiveLookupCallback() {
    let kZipCodeId = 100
    let kUnknownId = 200
    let subsequentChars = ["き", "ん"]

    let callback = PredictiveLookupCallback(
      Attribute.unigram, 10, 3, subsequentChars, kZipCodeId, kUnknownId)

    // Test OnKey
    #expect(callback.onKey("あん") == .traverseContinue)
    #expect(callback.onKey("あさ") == .traverseNextKey)

    // Test OnActualKey
    #expect(callback.onActualKey("あん", "あん", 2) == .traverseContinue)

    // Test OnToken
    var token = Token()
    token.key = "あん"
    token.value = "案"
    token.cost = 1000
    token.lid = 1
    token.rid = 1

    #expect(callback.onToken("あん", "あん", token) == .traverseContinue)
    let results = callback.results
    try? #require(results.count == 1)
    #expect(results[0].key == "あん")
    #expect(results[0].value == "案")
    #expect(results[0].wcost > 1000)  // Spatial cost penalty added
  }

  @Test func weekdayHelpers() {
    #expect(DecoderUtil.isStandaloneParenthesizedWeekday("(水)"))
    #expect(DecoderUtil.isStandaloneParenthesizedWeekday(" (水) "))
    #expect(DecoderUtil.isStandaloneParenthesizedWeekday("　（日）　"))
    #expect(!DecoderUtil.isStandaloneParenthesizedWeekday("水曜日"))
    #expect(!DecoderUtil.isStandaloneParenthesizedWeekday("9/16 (水)"))

    #expect(DecoderUtil.isRedundantForWeekdayPrediction("("))
    #expect(DecoderUtil.isRedundantForWeekdayPrediction(" （ "))
    #expect(DecoderUtil.isRedundantForWeekdayPrediction("()"))
    #expect(DecoderUtil.isRedundantForWeekdayPrediction(" (水)"))
    #expect(DecoderUtil.isRedundantForWeekdayPrediction("水曜"))
    #expect(DecoderUtil.isRedundantForWeekdayPrediction("水曜日"))
    #expect(!DecoderUtil.isRedundantForWeekdayPrediction("には"))

    #expect(DecoderUtil.endsWithWeekdayExpression("9/16 (水)"))
    #expect(DecoderUtil.endsWithWeekdayExpression("9月16日（水） "))
    #expect(DecoderUtil.endsWithWeekdayExpression("水曜日　"))
    #expect(!DecoderUtil.endsWithWeekdayExpression("9/16"))
    #expect(!DecoderUtil.endsWithWeekdayExpression("9月16日"))
  }
}
