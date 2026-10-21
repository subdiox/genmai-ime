// Port of mozc/src/prediction/user_history_predictor_test.cc (3.35.6354),
// part 2 (UserHistoryPredictorRevertTest .. PrivacySensitiveMultiSegmentsTest).
// See UserHistoryPredictorTests.swift for the conventions.

import Foundation
import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private struct Part2PrivacySensitiveTestData {
  let isSensitive: Bool
  let scenarioDescription: String
  let input: String
  let output: String
}

private let kPart2Sensitive = true
private let kPart2NonSensitive = false

private let kPart2NonSensitiveCases: [Part2PrivacySensitiveTestData] = [
  .init(
    isSensitive: kPart2NonSensitive,  // We might want to revisit this behavior
    scenarioDescription:
      "Type privacy sensitive number but it is committed as full-width number by mistake.",
    input: "0007", output: "０００７"),
  .init(
    isSensitive: kPart2NonSensitive, scenarioDescription: "Type a ZIP number.", input: "100-0001",
    output: "東京都千代田区千代田"),
  .init(
    isSensitive: kPart2NonSensitive,  // We might want to revisit this behavior
    scenarioDescription:
      "Type privacy sensitive number but the result contains one or more non-ASCII character such as full-width dash.",
    input: "1111-1111", output: "1111－1111"),
  .init(
    isSensitive: kPart2NonSensitive,  // We might want to revisit this behavior
    scenarioDescription: "User dictionary contains a credit card number.", input: "かーどばんごう",
    output: "0000-0000-0000-0000"),
  .init(
    isSensitive: kPart2NonSensitive,  // We might want to revisit this behavior
    scenarioDescription: "User dictionary contains a credit card number.", input: "かーどばんごう",
    output: "0000000000000000"),
  .init(
    isSensitive: kPart2NonSensitive,  // We might want to revisit this behavior
    scenarioDescription: "User dictionary contains privacy sensitive information.",
    input: "ぱすわーど", output: "ywwz1sxm"),
  .init(
    isSensitive: kPart2NonSensitive,  // We might want to revisit this behavior
    scenarioDescription:
      "Input privacy sensitive text by Roman-input mode by mistake and then hit F10 key to convert it to half-alphanumeric text. In this case we assume all the alphabetical characters are consumed by Roman-input rules.",
    input: "いあ1ぼ3ぅ", output: "ia1bo3xu"),
  .init(
    isSensitive: kPart2NonSensitive,
    scenarioDescription: "Katakana to English transliteration.",  // http://b/4394325
    input: "おれんじ", output: "Orange"),
  .init(
    isSensitive: kPart2NonSensitive,
    scenarioDescription:
      "Input a very common English word which should be included in our system dictionary by Roman-input mode by mistake and then hit F10 key to convert it to half-alphanumeric text.",
    input: "おらんげ", output: "orange"),
  .init(
    isSensitive: kPart2NonSensitive, scenarioDescription: "Input a password-like text.",
    input: "123abc!", output: "123abc!"),
  .init(
    isSensitive: kPart2NonSensitive,
    scenarioDescription:
      "Input privacy sensitive text by Roman-input mode by mistake and then hit F10 key to convert it to half-alphanumeric text. In this case, there may remain one or more alphabetical characters, which have not been consumed by Roman-input rules.",
    input: "yっwz1sxm", output: "ywwz1sxm"),
  .init(
    isSensitive: kPart2NonSensitive,
    scenarioDescription:
      "Type a very common English word all in lower case which should be included in our system dictionary without capitalization.",
    input: "variable", output: "variable"),
  .init(
    isSensitive: kPart2NonSensitive,
    scenarioDescription:
      "Type a very common English word all in upper case whose lower case should be included in our system dictionary.",
    input: "VARIABLE", output: "VARIABLE"),
  .init(
    isSensitive: kPart2NonSensitive,
    scenarioDescription:
      "Type a very common English word with capitalization whose lower case should be included in our system dictionary.",
    input: "Variable", output: "Variable"),
  .init(
    isSensitive: kPart2NonSensitive,  // We might want to revisit this behavior
    scenarioDescription:
      "Type a very common English word with random capitalization, which should be treated as case SENSITIVE.",
    input: "vArIaBle", output: "vArIaBle"),
  .init(
    isSensitive: kPart2NonSensitive,
    scenarioDescription:
      "Type an English word in lower case but only its upper case form is stored in dictionary.",
    input: "upper", output: "upper"),
  .init(
    isSensitive: kPart2Sensitive,  // We might want to revisit this behavior
    scenarioDescription: "Type just a number.", input: "2398402938402934",
    output: "2398402938402934"),
  .init(
    isSensitive: kPart2NonSensitive,  // We might want to revisit this behavior
    scenarioDescription:
      "Type a common English word which might be included in our system dictionary with number postfix.",
    input: "Orange10000", output: "Orange10000"),
]

private func part2RemoveLastCodepointCharacter(_ input: String) -> String {
  let codepointCount = Util.charsLen(input)
  if codepointCount == 0 {
    return ""
  }

  var codepointProcessed = 0
  var output = ""
  for c in ConstChar32Iterator(input) {
    if codepointProcessed >= codepointCount - 1 { break }
    Util.codepointToUtf8Append(c, &output)
    codepointProcessed += 1
  }
  return output
}

private struct Part2Command {
  enum CommandType {
    case lookup
    case insert
    case sync
    case wait
  }
  var type: CommandType = .lookup
  var key = ""
  var value = ""
}

@Suite(.scopedConfigEnvironment) struct UserHistoryPredictorTestPart2 {
  private typealias Fixture = UserHistoryPredictorTestFixture

  @Test func userHistoryPredictorRevertTest() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()
    withScopedClockMock(Date(unixSeconds: 1)) { _ in
      var results: [PredictionResult] = []

      let segmentsProxy = SegmentsProxy()
      let segmentsProxy2 = SegmentsProxy()
      let convreq1 = f.setUpInputForConversion("わたしのなまえはなかのです", segmentsProxy)
      segmentsProxy.addCandidate(0, "私の名前は中野です")

      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

      // Before Revert, Suggest works
      let convreq2 = f.setUpInputForSuggestion("わたしの", segmentsProxy2)
      results = predictor.predict(convreq2)
      #expect(!results.isEmpty)
      #expect(results.first?.value == "私の名前は中野です")

      // Call revert here
      predictor.revert(kRevertId)

      segmentsProxy.clear()
      let convreq3 = f.setUpInputForSuggestion("わたしの", segmentsProxy)

      results = predictor.predict(convreq3)
      #expect(results.isEmpty)
      #expect(results.count == 0)
    }
  }

  @Test func userHistoryPredictorRevertFreqTest() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    let kKey = "わたしのなまえはなかのです"
    let kValue = "私の名前は中野です"

    let segmentsProxy = SegmentsProxy()
    let convreq1 = f.setUpInputForConversion(kKey, segmentsProxy)
    segmentsProxy.addCandidate(0, kValue)

    func freqEq(_ expectedFreq: UInt32, sourceLocation: SourceLocation = #_sourceLocation) {
      let entry = predictor.storage.mutableLookup(kKey, kValue)
      if expectedFreq == 0 {
        #expect(
          entry.isNull || entry.entry.suggestionFreq == expectedFreq,
          sourceLocation: sourceLocation)
      } else {
        #expect(!entry.isNull, sourceLocation: sourceLocation)
        if entry.isNull { return }
        #expect(entry.entry.suggestionFreq == expectedFreq, sourceLocation: sourceLocation)
      }
    }

    freqEq(0)

    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), 1)
    freqEq(1)

    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), 2)
    freqEq(2)

    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), 3)
    freqEq(3)

    predictor.revert(3)
    freqEq(2)

    predictor.revert(2)
    freqEq(1)

    predictor.revert(1)
    freqEq(0)
  }

  @Test func userHistoryPredictorClearTest() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictor()
    await predictor.wait()

    // input "testtest" 10 times
    for _ in 0..<10 {
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForConversion("testtest", segmentsProxy)
      segmentsProxy.addCandidate(0, "テストテスト")
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }

    predictor.clearAllHistory()

    do {
      let segmentsProxy = SegmentsProxy()
      let convreq1 = f.setUpInputForSuggestion("t", segmentsProxy)
      let results = predictor.predict(convreq1)
      #expect(results.isEmpty)
    }

    // input "testtest" 1 time
    for _ in 0..<1 {
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForConversion("testtest", segmentsProxy)
      segmentsProxy.addCandidate(0, "テストテスト")
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }

    // frequency is cleared as well.
    do {
      let segmentsProxy = SegmentsProxy()
      let convreq1 = f.setUpInputForSuggestion("t", segmentsProxy)
      let results = predictor.predict(convreq1)
      #expect(!results.isEmpty)
    }
  }

  @Test func userHistoryPredictorTrailingPunctuation() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    let segmentsProxy = SegmentsProxy()
    var results: [PredictionResult] = []

    let convreq1 = f.setUpInputForConversion("わたしのなまえはなかのです", segmentsProxy)

    segmentsProxy.addCandidate(0, "私の名前は中野です")
    segmentsProxy.addSegment("。")
    segmentsProxy.addCandidate(1, "。")

    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

    segmentsProxy.clear()
    let convreq2 = f.setUpInputForPrediction("わたしの", segmentsProxy)
    results = predictor.predict(convreq2)
    #expect(!results.isEmpty)
    #expect(results.count == 1)
    #expect(results.first?.value == "私の名前は中野です")

    segmentsProxy.clear()
    let convreq3 = f.setUpInputForSuggestion("わたしの", segmentsProxy)

    results = predictor.predict(convreq3)
    #expect(!results.isEmpty)
    #expect(results.count == 1)
    #expect(results.first?.value == "私の名前は中野です")
  }

  @Test func trailingPunctuationMobile() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()
    RequestTestUtil.fillMobileRequest(&f.request)
    let segmentsProxy = SegmentsProxy()

    // [query, whether the query is remembered]
    let kTestCase: [(String, Bool)] = [
      ("です。", false), ("です", true), ("hello,", false),
      ("hello", true), ("123,", true), ("+@#!,", true),
    ]

    for (query, expected) in kTestCase {
      let convreq1 = f.setUpInputForConversion(query, segmentsProxy)
      segmentsProxy.addCandidate(0, query)
      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

      segmentsProxy.clear()
      let convreq2 = f.setUpInputForPrediction(
        String(Util.utf8SubString(query, 0, 2)), segmentsProxy)
      let results = predictor.predict(convreq2)
      #expect(results.isEmpty == !expected, "\(query)")
    }
  }

  @Test func historyToPunctuation() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    let segmentsProxy = SegmentsProxy()
    var results: [PredictionResult] = []

    // Scenario 1: A user have committed "亜" by prediction and then commit "。".
    // Then, the unigram "亜" is learned but the bigram "亜。" shouldn't.
    let convreq1 = f.setUpInputForPrediction("あ", segmentsProxy)
    segmentsProxy.addCandidate(0, "亜")
    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)
    segmentsProxy.setHistoryType(0)

    segmentsProxy.addSegment("。")
    segmentsProxy.addCandidate(1, "。")
    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

    segmentsProxy.clear()
    let convreq2 = f.setUpInputForPrediction("あ", segmentsProxy)  // "あ"
    results = predictor.predict(convreq2)
    try #require(!results.isEmpty)
    #expect(results[0].value == "亜")

    segmentsProxy.clear()

    // Scenario 2: the opposite case to Scenario 1, i.e., "。亜".  Nothing is
    // suggested from symbol "。".
    let convreq3 = f.setUpInputForPrediction("。", segmentsProxy)
    segmentsProxy.addCandidate(0, "。")
    predictor.finish(convreq3, segmentsProxy.makeLearningResults(), kRevertId)
    segmentsProxy.setHistoryType(0)

    segmentsProxy.addSegment("あ")
    segmentsProxy.addCandidate(1, "亜")
    predictor.finish(convreq3, segmentsProxy.makeLearningResults(), kRevertId)

    segmentsProxy.clear()
    let convreq4 = f.setUpInputForPrediction("。", segmentsProxy)  // "。"
    results = predictor.predict(convreq4)
    #expect(results.isEmpty)

    segmentsProxy.clear()

    // Scenario 3: If the history segment looks like a sentence and committed
    // value is a punctuation, the concatenated entry is also learned.
    let convreq5 = f.setUpInputForPrediction("おつかれさまです", segmentsProxy)
    segmentsProxy.addCandidate(0, "お疲れ様です")
    predictor.finish(convreq5, segmentsProxy.makeLearningResults(), kRevertId)
    segmentsProxy.setHistoryType(0)

    segmentsProxy.addSegment("。")
    segmentsProxy.addCandidate(1, "。")
    predictor.finish(convreq5, segmentsProxy.makeLearningResults(), kRevertId)

    segmentsProxy.clear()
    let convreq6 = f.setUpInputForPrediction("おつかれ", segmentsProxy)
    results = predictor.predict(convreq6)
    try #require(results.count == 1)
    #expect(results[0].value == "お疲れ様です")
  }

  @Test func userHistoryPredictorPrecedingPunctuation() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    let segmentsProxy = SegmentsProxy()
    var results: [PredictionResult] = []

    let convreq1 = f.setUpInputForConversion("。", segmentsProxy)

    segmentsProxy.addCandidate(0, "。")
    segmentsProxy.addSegment("わたしのなまえはなかのです")
    segmentsProxy.addCandidate(1, "私の名前は中野です")

    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

    segmentsProxy.clear()
    let convreq2 = f.setUpInputForPrediction("わたしの", segmentsProxy)

    results = predictor.predict(convreq2)
    #expect(!results.isEmpty)
    #expect(results.count == 1)
    #expect(results.first?.value == "私の名前は中野です")

    segmentsProxy.clear()
    let convreq3 = f.setUpInputForSuggestion("わたしの", segmentsProxy)
    results = predictor.predict(convreq3)
    #expect(!results.isEmpty)
    #expect(results.count == 1)
    #expect(results.first?.value == "私の名前は中野です")
  }

  @Test func startsWithPunctuations() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictor()
    let kTestCases: [(String, Bool)] = [
      ("。", false), ("、", false), ("？", false),
      ("！", false), ("あああ", true),
    ]

    for (firstChar, expectedResult) in kTestCases {
      await predictor.wait()
      predictor.clearAllHistory()

      let segmentsProxy = SegmentsProxy()
      var results: [PredictionResult] = []
      do {
        // Learn from two segments
        let convreq = f.setUpInputForConversion(firstChar, segmentsProxy)
        segmentsProxy.addCandidate(0, firstChar)
        segmentsProxy.addSegment("てすとぶんしょう")
        segmentsProxy.addCandidate(1, "テスト文章")
        predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
      }
      segmentsProxy.clear()
      do {
        // Learn from one segment
        let convreq = f.setUpInputForConversion(firstChar + "てすとぶんしょう", segmentsProxy)
        segmentsProxy.addCandidate(0, firstChar + "テスト文章")
        predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
      }
      segmentsProxy.clear()
      do {
        // Suggestion
        let convreq = f.setUpInputForSuggestion(firstChar, segmentsProxy)
        segmentsProxy.addCandidate(0, firstChar)
        results = predictor.predict(convreq)
        #expect(!results.isEmpty == expectedResult, "Suggest from \(firstChar)")
      }
      segmentsProxy.clear()
      do {
        // Prediction
        let convreq = f.setUpInputForPrediction(firstChar, segmentsProxy)
        results = predictor.predict(convreq)
        #expect(!results.isEmpty == expectedResult, "Predict from \(firstChar)")
      }
    }
  }

  @Test func zeroQuerySuggestionTest() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    f.request.zeroQuerySuggestion = true
    f.request.mixedConversion = true

    var nonZeroQueryRequest = Genmai_Commands_Request()
    nonZeroQueryRequest.zeroQuerySuggestion = false
    let context = Genmai_Commands_Context()
    let segmentsProxy = SegmentsProxy()
    var results: [PredictionResult] = []

    // No history segments
    segmentsProxy.clear()
    let convreq = f.setUpInputForSuggestion("", segmentsProxy)
    results = predictor.predict(convreq)
    #expect(results.isEmpty)

    do {
      segmentsProxy.clear()

      let convreq1 = f.setUpInputForConversion("たろうは", segmentsProxy)
      segmentsProxy.addCandidate(0, "太郎は")
      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

      let convreq2 = f.setUpInputForConversionWithHistory(
        "はなこに", "たろうは", "太郎は", segmentsProxy)
      segmentsProxy.addCandidate(1, "花子に")
      predictor.finish(convreq2, segmentsProxy.makeLearningResults(), kRevertId)

      let convreq3 = f.setUpInputForConversionWithHistory(
        "きょうと", "たろうは", "太郎は", segmentsProxy)
      segmentsProxy.addCandidate(1, "京都")
      try? await Task.sleep(for: .seconds(2))
      predictor.finish(convreq3, segmentsProxy.makeLearningResults(), kRevertId)

      let convreq4 = f.setUpInputForConversionWithHistory(
        "おおさか", "たろうは", "太郎は", segmentsProxy)
      segmentsProxy.addCandidate(1, "大阪")
      try? await Task.sleep(for: .seconds(2))
      predictor.finish(convreq4, segmentsProxy.makeLearningResults(), kRevertId)

      // Zero query suggestion is disabled.
      _ = f.setUpInputForSuggestionWithHistory("", "たろうは", "太郎は", segmentsProxy)
      // convreq5 is not zero query suggestion unlike other convreqs.
      let convreq5 = ConversionRequestBuilder()
        .setComposer(f.composer)
        .setRequestView(nonZeroQueryRequest)
        .setContextView(context)
        .setConfigView(f.config)
        .build()
      results = predictor.predict(convreq5)
      #expect(results.isEmpty)

      let convreq6 = f.setUpInputForSuggestionWithHistory("", "たろうは", "太郎は", segmentsProxy)
      results = predictor.predict(convreq6)
      #expect(!results.isEmpty)
      // last-pushed segment is "大阪"
      #expect(results.first?.value == "大阪")
      #expect(results.first?.key == "おおさか")

      for key in ["は", "た", "き", "お"] {
        let convreq = f.setUpInputForSuggestionWithHistory(key, "たろうは", "太郎は", segmentsProxy)
        results = predictor.predict(convreq)
        #expect(!results.isEmpty, "\(key)")
      }
    }

    predictor.clearAllHistory()

    do {
      segmentsProxy.clear()
      let convreq1 = f.setUpInputForConversion("たろうは", segmentsProxy)
      segmentsProxy.addCandidate(0, "太郎は")

      segmentsProxy.addSegment("はなこに")
      segmentsProxy.addCandidate(1, "花子に")
      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

      segmentsProxy.clear()
      _ = f.setUpInputForSuggestion("たろうは", segmentsProxy)
      segmentsProxy.addCandidate(0, "太郎は")
      segmentsProxy.setHistoryType(0)

      // Zero query suggestion is disabled.
      let nonZeroQueryConvreq = ConversionRequestBuilder()
        .setRequestView(nonZeroQueryRequest)
        .setContextView(context)
        .setConfigView(f.config)
        .setHistoryResultView(segmentsProxy.historyResultView)
        .setRequestType(.suggestion)
        .build()

      segmentsProxy.addSegment("")  // empty request
      #expect(predictor.predict(nonZeroQueryConvreq).isEmpty)

      func convreq() -> ConversionRequest {
        f.composer.reset()
        f.composer.setPreeditTextForTestOnly(segmentsProxy.key)
        var options = ConversionRequest.Options()
        options.requestType = .suggestion
        return f.createConversionRequestWithOptions(options, segmentsProxy)
      }

      segmentsProxy.popBackSegment()
      segmentsProxy.addSegment("")  // empty request
      results = predictor.predict(convreq())
      #expect(!results.isEmpty)

      segmentsProxy.popBackSegment()
      segmentsProxy.addSegment("は")
      results = predictor.predict(convreq())
      #expect(!results.isEmpty)

      segmentsProxy.popBackSegment()
      segmentsProxy.addSegment("た")
      results = predictor.predict(convreq())
      #expect(!results.isEmpty)
    }
  }

  @Test func zeroQueryPreferenceTest() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    try withScopedClockMock(Date(unixSeconds: 1)) { clock in
      let predictor = f.getUserHistoryPredictorWithClearedHistory()

      f.request.zeroQuerySuggestion = true
      f.request.mixedConversion = true

      let segmentsProxy = SegmentsProxy()
      var results: [PredictionResult] = []

      func convertUnigram(_ key1: String, _ value1: String) {
        let convreq1 = f.setUpInputForConversion(key1, segmentsProxy)
        segmentsProxy.addCandidate(0, value1)
        predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)
      }

      func convertBigram(_ key1: String, _ value1: String, _ key2: String, _ value2: String) {
        let convreq1 = f.setUpInputForConversion(key1, segmentsProxy)
        segmentsProxy.addCandidate(0, value1)
        predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)
        clock.advance(.seconds(10))
        let convreq2 = f.setUpInputForConversionWithHistory(key2, key1, value1, segmentsProxy)
        segmentsProxy.addCandidate(1, value2)
        predictor.finish(convreq2, segmentsProxy.makeLearningResults(), kRevertId)
        clock.advance(.seconds(10))
      }

      do {
        predictor.clearAllHistory()

        // Fixes https://b/453507817
        convertBigram("おおさか", "大阪", "だいがく", "大学")
        convertBigram("きょうと", "京都", "だいがく", "大学")
        convertBigram("おおさか", "大阪", "ちゅうがく", "中学")
        convertBigram("きょうと", "京都", "だいがく", "大学")

        let convreq = f.setUpInputForSuggestionWithHistory("", "おおさか", "大阪", segmentsProxy)
        results = predictor.predict(convreq)
        try #require(results.count == 2)
        #expect(results[0].value == "中学")
        #expect(results[1].value == "大学")

        // This unigram timestamp is not considered.
        clock.advance(.seconds(3600))
        convertUnigram("だいがく", "大学")

        // Prefers the actual bigram.
        convertBigram("おおさか", "大阪", "こうこう", "高校")

        results = predictor.predict(convreq)
        try #require(results.count == 3)
        #expect(results[0].value == "高校")
        #expect(results[1].value == "中学")
        #expect(results[2].value == "大学")
      }

      // NWP is generated from bigram and unigram.
      // The preferences are determined by the LRU principle.
      do {
        predictor.clearAllHistory()

        convertBigram("とうきょう", "東京", "だいがく", "大学")
        clock.advance(.seconds(3600))
        convertUnigram("とうきょうたわー", "東京タワー")

        let convreq = f.setUpInputForSuggestionWithHistory("", "とうきょう", "東京", segmentsProxy)
        results = predictor.predict(convreq)
        try #require(results.count == 2)
        #expect(results[0].value == "タワー")
        #expect(results[1].value == "大学")

        // Unigram timestamp doesn't affect the bigram preference.
        convertUnigram("だいがく", "大学")
        try #require(results.count == 2)
        #expect(results[0].value == "タワー")
        #expect(results[1].value == "大学")
      }

      do {
        predictor.clearAllHistory()

        convertUnigram("とうきょうたわー", "東京タワー")
        clock.advance(.seconds(3600))
        convertBigram("とうきょう", "東京", "だいがく", "大学")

        let convreq = f.setUpInputForSuggestionWithHistory("", "とうきょう", "東京", segmentsProxy)
        results = predictor.predict(convreq)
        try #require(results.count == 2)
        #expect(results[0].value == "大学")
        #expect(results[1].value == "タワー")
      }
    }
  }

  @Test func multiSegmentsMultiInput() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    let segmentsProxy = SegmentsProxy()
    var results: [PredictionResult] = []

    let convreq1 = f.setUpInputForConversion("たろうは", segmentsProxy)
    segmentsProxy.addCandidate(0, "太郎は")
    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)
    segmentsProxy.setHistoryType(0)

    segmentsProxy.addSegment("はなこに")
    segmentsProxy.addCandidate(1, "花子に")
    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)
    segmentsProxy.setHistoryType(1)

    segmentsProxy.clearConversionSegments()
    segmentsProxy.addSegment("むずかしい")
    segmentsProxy.addCandidate(2, "難しい")
    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)
    segmentsProxy.setHistoryType(2)

    segmentsProxy.clearConversionSegments()
    segmentsProxy.addSegment("ほんを")
    segmentsProxy.addCandidate(3, "本を")
    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)
    segmentsProxy.setHistoryType(3)

    segmentsProxy.clearConversionSegments()
    segmentsProxy.addSegment("よませた")
    segmentsProxy.addCandidate(4, "読ませた")
    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

    func expectSuggest(_ key: String, _ nonEmpty: Bool, _ loc: SourceLocation = #_sourceLocation) {
      segmentsProxy.clear()
      let convreq = f.setUpInputForSuggestion(key, segmentsProxy)
      results = predictor.predict(convreq)
      #expect(results.isEmpty == !nonEmpty, "\(key)", sourceLocation: loc)
    }

    expectSuggest("た", true)  // "たろう"
    expectSuggest("たろうは", true)
    expectSuggest("ろうは", false)
    expectSuggest("たろうははな", true)
    expectSuggest("はなこにむ", true)
    expectSuggest("むずかし", true)
    expectSuggest("はなこにむずかしいほ", true)
    expectSuggest("ほんをよま", true)

    try? await Task.sleep(for: .seconds(1))

    // Add new entry "たろうはよしこに/太郎は良子に"
    segmentsProxy.clear()
    let convreq10 = f.setUpInputForConversion("たろうは", segmentsProxy)
    segmentsProxy.addCandidate(0, "太郎は")
    predictor.finish(convreq10, segmentsProxy.makeLearningResults(), kRevertId)
    segmentsProxy.setHistoryType(0)

    segmentsProxy.addSegment("よしこに")
    segmentsProxy.addCandidate(1, "良子に")
    predictor.finish(convreq10, segmentsProxy.makeLearningResults(), kRevertId)
    segmentsProxy.setHistoryType(1)

    segmentsProxy.clear()
    let convreq11 = f.setUpInputForSuggestion("たろうは", segmentsProxy)
    results = predictor.predict(convreq11)
    #expect(!results.isEmpty)
    #expect(results.first?.value == "太郎は良子に")

    segmentsProxy.clear()
    for isMobile in [true, false] {
      f.request.mixedConversion = isMobile
      let convreq12 = f.setUpInputForSuggestion("たろうははなこに", segmentsProxy)
      results = predictor.predict(convreq12)
      #expect(!results.isEmpty)
      if isMobile {
        #expect(results.first?.value == "太郎は花子に")
      } else {
        #expect(results.first?.value == "太郎は花子に難しい")
      }
    }
  }

  @Test func multiSegmentsSingleInput() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    let segmentsProxy = SegmentsProxy()
    var results: [PredictionResult] = []

    let convreq1 = f.setUpInputForConversion("たろうは", segmentsProxy)
    segmentsProxy.addCandidate(0, "太郎は")

    segmentsProxy.addSegment("はなこに")
    segmentsProxy.addCandidate(1, "花子に")

    segmentsProxy.addSegment("むずかしい")
    segmentsProxy.addCandidate(2, "難しい")

    segmentsProxy.addSegment("ほんを")
    segmentsProxy.addCandidate(3, "本を")

    segmentsProxy.addSegment("よませた")
    segmentsProxy.addCandidate(4, "読ませた")

    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

    func expectSuggest(_ key: String, _ nonEmpty: Bool, _ loc: SourceLocation = #_sourceLocation) {
      segmentsProxy.clear()
      let convreq = f.setUpInputForSuggestion(key, segmentsProxy)
      results = predictor.predict(convreq)
      #expect(results.isEmpty == !nonEmpty, "\(key)", sourceLocation: loc)
    }

    expectSuggest("たろうは", true)
    expectSuggest("た", true)  // たろうは
    expectSuggest("たろうははな", true)
    expectSuggest("ろうははな", false)
    expectSuggest("はなこにむ", true)
    expectSuggest("むずかし", true)
    expectSuggest("はなこにむずかしいほ", true)
    expectSuggest("ほんをよま", true)

    try? await Task.sleep(for: .seconds(1))

    // Add new entry "たろうはよしこに/太郎は良子に"
    segmentsProxy.clear()
    let convreq10 = f.setUpInputForConversion("たろうは", segmentsProxy)
    segmentsProxy.addCandidate(0, "太郎は")
    predictor.finish(convreq10, segmentsProxy.makeLearningResults(), kRevertId)
    segmentsProxy.setHistoryType(0)

    segmentsProxy.addSegment("よしこに")
    segmentsProxy.addCandidate(1, "良子に")
    predictor.finish(convreq10, segmentsProxy.makeLearningResults(), kRevertId)
    segmentsProxy.setHistoryType(1)

    segmentsProxy.clear()
    let convreq11 = f.setUpInputForSuggestion("たろうは", segmentsProxy)
    results = predictor.predict(convreq11)
    #expect(!results.isEmpty)
    #expect(results.first?.value == "太郎は良子に")

    for isMobile in [true, false] {
      f.request.mixedConversion = isMobile
      let convreq12 = f.setUpInputForSuggestion("たろうははなこに", segmentsProxy)
      results = predictor.predict(convreq12)
      #expect(!results.isEmpty)
      if isMobile {
        #expect(results.first?.value == "太郎は花子に")
      } else {
        #expect(results.first?.value == "太郎は花子に難しい")
      }
    }
  }

  private func addSegments(_ segmentsProxy: SegmentsProxy, _ pairs: [(String, String)]) {
    // pairs[0] is the already-added first segment's candidate value.
    for (i, (key, value)) in pairs.enumerated() {
      if i > 0 { segmentsProxy.addSegment(key) }
      segmentsProxy.addCandidate(i, value)
    }
  }

  @Test func regression2843371Case1() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    let segmentsProxy = SegmentsProxy()

    let convreq1 = f.setUpInputForConversion("とうきょう", segmentsProxy)
    addSegments(
      segmentsProxy, [("とうきょう", "東京"), ("は", "は"), ("にほんです", "日本です"), ("。", "。")])

    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

    segmentsProxy.clear()

    try? await Task.sleep(for: .seconds(1))

    let convreq2 = f.setUpInputForConversion("らーめん", segmentsProxy)
    addSegments(
      segmentsProxy, [("らーめん", "ラーメン"), ("は", "は"), ("めんるいです", "麺類です"), ("。", "。")])

    predictor.finish(convreq2, segmentsProxy.makeLearningResults(), kRevertId)

    segmentsProxy.clear()

    let convreq3 = f.setUpInputForSuggestion("とうきょうは", segmentsProxy)
    let results = predictor.predict(convreq3)
    #expect(!results.isEmpty)
    #expect(results.first?.value == "東京は日本です")
  }

  @Test func regression2843371Case2() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    let segmentsProxy = SegmentsProxy()

    let convreq1 = f.setUpInputForConversion("えど", segmentsProxy)
    addSegments(
      segmentsProxy,
      [
        ("えど", "江戸"), ("(", "("), ("とうきょう", "東京"), (")", ")"), ("は", "は"),
        ("えぞ", "蝦夷"), ("(", "("), ("ほっかいどう", "北海道"), (")", ")"),
        ("ではない", "ではない"), ("。", "。"),
      ])

    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

    segmentsProxy.clear()

    let convreq2 = f.setUpInputForSuggestion("えど(", segmentsProxy)
    var results = predictor.predict(convreq2)
    #expect(!results.isEmpty)
    #expect(results.first?.value == "江戸(東京")

    results = predictor.predict(convreq2)
    #expect(!results.isEmpty)

    #expect(results.first?.value == "江戸(東京")
  }

  @Test func regression2843371Case3() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    let segmentsProxy = SegmentsProxy()

    let convreq1 = f.setUpInputForConversion("「", segmentsProxy)
    addSegments(
      segmentsProxy,
      [("「", "「"), ("やま", "山"), ("」", "」"), ("は", "は"), ("たかい", "高い"), ("。", "。")])

    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

    try? await Task.sleep(for: .seconds(2))

    segmentsProxy.clear()

    let convreq2 = f.setUpInputForConversion("「", segmentsProxy)
    addSegments(
      segmentsProxy,
      [("「", "「"), ("うみ", "海"), ("」", "」"), ("は", "は"), ("ふかい", "深い"), ("。", "。")])

    predictor.finish(convreq2, segmentsProxy.makeLearningResults(), kRevertId)

    segmentsProxy.clear()

    let convreq3 = f.setUpInputForSuggestion("「やま」は", segmentsProxy)
    let results = predictor.predict(convreq3)
    #expect(!results.isEmpty)

    #expect(results.first?.value == "「山」は高い")
  }

  @Test func regression2843775() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    let segmentsProxy = SegmentsProxy()

    let convreq1 = f.setUpInputForConversion("そうです", segmentsProxy)
    segmentsProxy.addCandidate(0, "そうです")

    segmentsProxy.addSegment("。よろしくおねがいします")
    segmentsProxy.addCandidate(1, "。よろしくお願いします")

    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

    segmentsProxy.clear()

    let convreq2 = f.setUpInputForSuggestion("そうです", segmentsProxy)
    let results = predictor.predict(convreq2)
    #expect(!results.isEmpty)

    // Do not allow the bigram connecting to punctuation.
    #expect(results.first?.value == "そうです")
  }

  @Test func duplicateString() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    let segmentsProxy = SegmentsProxy()

    let convreq1 = f.setUpInputForConversion("らいおん", segmentsProxy)
    addSegments(
      segmentsProxy,
      [
        ("らいおん", "ライオン"), ("（", "（"), ("もうじゅう", "猛獣"), ("）と", "）と"),
        ("ぞうりむし", "ゾウリムシ"), ("（", "（"), ("びせいぶつ", "微生物"), ("）", "）"),
      ])

    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

    segmentsProxy.clear()

    let convreq2 = f.setUpInputForSuggestion("ぞうりむし", segmentsProxy)
    var results = predictor.predict(convreq2)
    #expect(!results.isEmpty)

    for result in results {
      #expect(!part2ByteContains(result.value, "猛獣"))  // "猛獣" should not be found
    }

    segmentsProxy.clear()

    let convreq3 = f.setUpInputForSuggestion("らいおん", segmentsProxy)
    results = predictor.predict(convreq3)
    #expect(!results.isEmpty)

    for result in results {
      #expect(!part2ByteContains(result.value, "ライオン（微生物"))
    }
  }

  @Test func syncTest() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictor()
    await predictor.wait()

    var commands = [Part2Command](repeating: Part2Command(), count: 10000)
    for i in 0..<commands.count {
      commands[i].key = "\(UInt32(i))key"
      commands[i].value = "\(UInt32(i))value"
      let n = Int.random(in: 0..<100)
      if n == 0 {
        commands[i].type = .wait
      } else if n < 10 {
        commands[i].type = .sync
      } else if n < 50 {
        commands[i].type = .insert
      } else {
        commands[i].type = .lookup
      }
    }

    // Kind of stress test
    let segmentsProxy = SegmentsProxy()
    for command in commands {
      switch command.type {
      case .sync:
        predictor.sync()
      case .wait:
        await predictor.wait()
      case .insert:
        segmentsProxy.clear()
        let convreq = f.setUpInputForConversion(command.key, segmentsProxy)
        segmentsProxy.addCandidate(0, command.value)
        predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
      case .lookup:
        segmentsProxy.clear()
        let convreq = f.setUpInputForSuggestion(command.key, segmentsProxy)
        _ = predictor.predict(convreq)
      }
    }
    await predictor.wait()
  }

  @Test func getMatchTypeTest() async {
    typealias MatchType = UserHistoryPredictor.MatchType
    #expect(UserHistoryPredictor.getMatchType("test", "") == MatchType.noMatch)

    #expect(UserHistoryPredictor.getMatchType("", "") == MatchType.noMatch)

    #expect(UserHistoryPredictor.getMatchType("", "test") == MatchType.leftEmptyMatch)

    #expect(UserHistoryPredictor.getMatchType("foo", "bar") == MatchType.noMatch)

    #expect(UserHistoryPredictor.getMatchType("foo", "foo") == MatchType.exactMatch)

    #expect(UserHistoryPredictor.getMatchType("foo", "foobar") == MatchType.leftPrefixMatch)

    #expect(UserHistoryPredictor.getMatchType("foobar", "foo") == MatchType.rightPrefixMatch)
  }

  @Test func getScore() async {
    typealias Entry = UserHistoryPredictor.Entry
    // latest value has higher score.
    do {
      var entry1 = Entry()
      var entry2 = Entry()

      entry1.key = "abc"
      entry1.value = "ABC"
      entry1.lastAccessTime = 10

      entry2.key = "foo"
      entry2.value = "ABC"
      entry2.lastAccessTime = 20

      #expect(UserHistoryPredictor.getScore(entry2) > UserHistoryPredictor.getScore(entry1))
    }

    // shorter value has higher score.
    do {
      var entry1 = Entry()
      var entry2 = Entry()

      entry1.key = "abc"
      entry1.value = "ABC"
      entry1.lastAccessTime = 10

      entry2.key = "foo"
      entry2.value = "ABCD"
      entry2.lastAccessTime = 10

      #expect(UserHistoryPredictor.getScore(entry1) > UserHistoryPredictor.getScore(entry2))
    }

    // bigram boost makes the entry stronger
    do {
      var entry1 = Entry()
      var entry2 = Entry()

      entry1.key = "abc"
      entry1.value = "ABC"
      entry1.lastAccessTime = 10

      entry2.key = "foo"
      entry2.value = "ABC"
      entry2.lastAccessTime = 10
      entry2.attributes = UserHistoryPredictor.Attribute.bigramBoost

      #expect(UserHistoryPredictor.getScore(entry2) > UserHistoryPredictor.getScore(entry1))
    }

    // bigram boost makes the entry stronger
    do {
      var entry1 = Entry()
      var entry2 = Entry()

      entry1.key = "abc"
      entry1.value = "ABCD"
      entry1.lastAccessTime = 10
      entry1.attributes = UserHistoryPredictor.Attribute.bigramBoost

      entry2.key = "foo"
      entry2.value = "ABC"
      entry2.lastAccessTime = 50

      #expect(UserHistoryPredictor.getScore(entry1) > UserHistoryPredictor.getScore(entry2))
    }
  }

  @Test func isValidEntry() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictor()

    var entry = UserHistoryPredictor.Entry()

    #expect(predictor.isValidEntry(entry))

    entry.key = "key"
    entry.value = "value"

    #expect(predictor.isValidEntry(entry))
    #expect(predictor.isValidEntryIgnoringRemovedField(entry))

    entry.removed = true
    #expect(!predictor.isValidEntry(entry))
    #expect(predictor.isValidEntryIgnoringRemovedField(entry))

    entry.removed = false
    #expect(predictor.isValidEntry(entry))
    #expect(predictor.isValidEntryIgnoringRemovedField(entry))

    entry.removed = true
    #expect(!predictor.isValidEntry(entry))
    #expect(predictor.isValidEntryIgnoringRemovedField(entry))

    entry = UserHistoryPredictor.Entry()
    #expect(predictor.isValidEntry(entry))
    #expect(predictor.isValidEntryIgnoringRemovedField(entry))

    entry = UserHistoryPredictor.Entry()
    entry.key = "key"
    entry.value = "value"
    entry.description_p = "絵文字"
    #expect(predictor.isValidEntry(entry))
    #expect(predictor.isValidEntryIgnoringRemovedField(entry))

    // An android pua emoji. It is obsolete and should return false.
    entry.value = Util.codepointToUtf8(0xFE000)
    #expect(!predictor.isValidEntry(entry))
    #expect(!predictor.isValidEntryIgnoringRemovedField(entry))

    // Set up suppression dictionary
    do {
      var storage = Genmai_UserDictionary_UserDictionaryStorage()
      var dic = Genmai_UserDictionary_UserDictionary()
      var e = Genmai_UserDictionary_UserDictionary.Entry()
      e.key = "foo"
      e.value = "bar"
      e.pos = .suppressionWord
      dic.entries.append(e)
      storage.dictionaries.append(dic)
      f.getUserDictionary().load(storage)
      await f.getUserDictionary().waitForReloader()
    }

    entry.key = "key"
    entry.value = "value"
    #expect(predictor.isValidEntry(entry))
    #expect(predictor.isValidEntryIgnoringRemovedField(entry))

    entry.key = "foo"
    entry.value = "bar"
    #expect(!predictor.isValidEntry(entry))
    #expect(!predictor.isValidEntryIgnoringRemovedField(entry))
  }

  @Test func entryPriorityQueueTest() async {
    typealias EntryPriorityQueue = UserHistoryPredictor.EntryPriorityQueue
    // removed automatically
    let kSize = 10000
    do {
      let queue = EntryPriorityQueue()
      for i in 0..<10000 {
        #expect(queue.newEntry() == i)
      }
    }

    do {
      let queue = EntryPriorityQueue()
      var expected: [Int] = []
      for i in 0..<kSize {
        let entry = queue.newEntry()
        queue[entry].key = "test\(i)"
        queue[entry].value = "test\(i)"
        queue[entry].lastAccessTime = UInt64(i + 1000)
        expected.append(entry)
        #expect(queue.push(entry))
      }

      var n = kSize - 1
      while true {
        guard let entry = queue.pop() else {
          break
        }
        #expect(entry == expected[n])
        n -= 1
      }
      #expect(n == -1)
    }

    do {
      let queue = EntryPriorityQueue()
      for _ in 0..<5 {
        let entry = queue.newEntry()
        queue[entry].key = "test"
        queue[entry].value = "test"
        queue.push(entry)
      }
      #expect(queue.size == 1)

      for _ in 0..<5 {
        let entry = queue.newEntry()
        queue[entry].key = "foo"
        queue[entry].value = "bar"
        queue.push(entry)
      }

      #expect(queue.size == 2)
    }
  }

  @Test func privacySensitiveTest() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictor()
    var results: [PredictionResult] = []

    for data in kPart2NonSensitiveCases {
      predictor.clearAllHistory()

      let description = data.scenarioDescription
      let input = data.input
      let output = data.output
      let partialInput = part2RemoveLastCodepointCharacter(input)
      let expectSensitive = data.isSensitive
      let comment: Comment = "\(description) input: \(input) output: \(output)"

      // Initial commit.
      do {
        let segmentsProxy = SegmentsProxy()
        let convreq = f.setUpInputForConversion(input, segmentsProxy)
        segmentsProxy.addCandidate(0, output)
        predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
      }

      // TODO(yukawa): Refactor the scenario runner below by making
      //     some utility functions.

      // Check suggestion
      do {
        let segmentsProxy = SegmentsProxy()
        let convreq1 = f.setUpInputForSuggestion(partialInput, segmentsProxy)
        results = predictor.predict(convreq1)
        #expect(results.isEmpty == expectSensitive, comment)
        segmentsProxy.clear()
        let convreq2 = f.setUpInputForPrediction(input, segmentsProxy)
        results = predictor.predict(convreq2)
        #expect(results.isEmpty == expectSensitive, comment)
      }

      // Check Prediction
      do {
        let segmentsProxy = SegmentsProxy()
        let convreq1 = f.setUpInputForPrediction(partialInput, segmentsProxy)
        results = predictor.predict(convreq1)
        #expect(results.isEmpty == expectSensitive, comment)
        segmentsProxy.clear()
        let convreq2 = f.setUpInputForPrediction(input, segmentsProxy)
        results = predictor.predict(convreq2)
        #expect(results.isEmpty == expectSensitive, comment)
      }
    }
  }

  @Test func privacySensitiveMultiSegmentsTest() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictor()
    await predictor.wait()
    var results: [PredictionResult] = []

    // If a password-like input consists of multiple segments, it is not
    // considered to be privacy sensitive when the input is committed.
    // Currently this is a known issue.
    do {
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForConversion("123", segmentsProxy)
      segmentsProxy.addSegment("abc!")
      segmentsProxy.addCandidate(0, "123")
      segmentsProxy.addCandidate(1, "abc!")
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }

    do {
      let segmentsProxy = SegmentsProxy()
      let convreq1 = f.setUpInputForSuggestion("123abc", segmentsProxy)
      results = predictor.predict(convreq1)
      #expect(!results.isEmpty)
      segmentsProxy.clear()
      let convreq2 = f.setUpInputForSuggestion("123abc!", segmentsProxy)
      results = predictor.predict(convreq2)
      #expect(!results.isEmpty)
    }

    do {
      let segmentsProxy = SegmentsProxy()
      let convreq1 = f.setUpInputForPrediction("123abc", segmentsProxy)
      results = predictor.predict(convreq1)
      #expect(!results.isEmpty)
      segmentsProxy.clear()
      let convreq2 = f.setUpInputForPrediction("123abc!", segmentsProxy)
      results = predictor.predict(convreq2)
      #expect(!results.isEmpty)
    }
  }
}

private func part2ByteContains(_ s: String, _ needle: String) -> Bool {
  let h = Array(s.utf8)
  let n = Array(needle.utf8)
  if n.isEmpty { return true }
  if n.count > h.count { return false }
  for i in 0...(h.count - n.count) where h[i..<(i + n.count)].elementsEqual(n) {
    return true
  }
  return false
}
