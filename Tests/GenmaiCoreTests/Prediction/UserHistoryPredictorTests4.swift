// Port of mozc/src/prediction/user_history_predictor_test.cc (3.35.6354),
// part 4 (PunctuationLink .. GuessRevertedValueOffset). See
// UserHistoryPredictorTests.swift for the conventions.

import Foundation
import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private typealias Fixture = UserHistoryPredictorTestFixture

private func part4Find(_ value: String, _ results: [PredictionResult]) -> Int? {
  Fixture.findCandidateByValue(value, results)
}

@Suite(.scopedConfigEnvironment) struct UserHistoryPredictorTestPart4 {
  @Test func punctuationLink() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()
    RequestTestUtil.fillMobileRequest(&f.request)
    let segmentsProxy = SegmentsProxy()
    var results: [PredictionResult] = []

    do {
      let convreq1 = f.setUpInputForConversion("ございます", segmentsProxy)
      segmentsProxy.addCandidate(0, "ございます")
      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

      let convreq2 = f.setUpInputForConversionWithHistory(
        "!", "ございます", "ございます", segmentsProxy)
      segmentsProxy.addCandidate(1, "！")
      predictor.finish(convreq2, segmentsProxy.makeLearningResults(), kRevertId)

      segmentsProxy.clear()
      let convreq3 = f.setUpInputForSuggestion("ございま", segmentsProxy)
      results = predictor.predict(convreq3)
      #expect(!results.isEmpty)
      #expect(results.first?.value == "ございます")
      #expect(part4Find("ございます！", results) == nil)

      // Zero query from "ございます" -> "！"
      segmentsProxy.clear()
      // Output of SetupInputForConversion is not used here.
      _ = f.setUpInputForConversion("ございます", segmentsProxy)
      segmentsProxy.addCandidate(0, "ございます")
      let convreq4 = f.setUpInputForSuggestionWithHistory(
        "", "ございます", "ございます", segmentsProxy)
      results = predictor.predict(convreq4)
      #expect(!results.isEmpty)
      #expect(results.first?.value == "！")
    }

    predictor.clearAllHistory()

    do {
      let convreq1 = f.setUpInputForConversion("!", segmentsProxy)
      segmentsProxy.addCandidate(0, "！")
      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

      let convreq2 = f.setUpInputForSuggestionWithHistory("ございます", "!", "！", segmentsProxy)
      segmentsProxy.addCandidate(1, "ございます")
      predictor.finish(convreq2, segmentsProxy.makeLearningResults(), kRevertId)

      // Zero query from "！" -> no suggestion
      segmentsProxy.clear()
      let convreq3 = f.setUpInputForSuggestionWithHistory("", "!", "！", segmentsProxy)
      results = predictor.predict(convreq3)
      #expect(results.isEmpty)
    }

    predictor.clearAllHistory()

    do {
      let convreq1 = f.setUpInputForConversion("ございます!", segmentsProxy)
      segmentsProxy.addCandidate(0, "ございます！")

      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)
      segmentsProxy.setHistoryType(0)

      segmentsProxy.addSegment("よろしくおねがいします")
      segmentsProxy.addCandidate(1, "よろしくお願いします")
      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

      // Zero query from "！" -> no suggestion
      segmentsProxy.clear()
      let convreq2 = f.setUpInputForConversion("!", segmentsProxy)
      segmentsProxy.addCandidate(0, "！")
      segmentsProxy.setHistoryType(0)
      segmentsProxy.addSegment("")  // empty request
      results = predictor.predict(convreq2)
      #expect(results.isEmpty)

      // Zero query from "ございます！" -> no suggestion
      segmentsProxy.clear()
      let convreq3 = f.setUpInputForConversion("ございます!", segmentsProxy)
      segmentsProxy.addCandidate(0, "ございます！")
      segmentsProxy.setHistoryType(0)
      segmentsProxy.addSegment("")  // empty request
      results = predictor.predict(convreq3)
      #expect(results.isEmpty)
    }

    predictor.clearAllHistory()

    do {
      let convreq1 = f.setUpInputForConversion("ございます", segmentsProxy)
      segmentsProxy.addCandidate(0, "ございます")
      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

      let convreq2 = f.setUpInputForConversionWithHistory(
        "!よろしくおねがいします", "ございます", "ございます", segmentsProxy)
      segmentsProxy.addCandidate(1, "！よろしくお願いします")
      predictor.finish(convreq2, segmentsProxy.makeLearningResults(), kRevertId)

      segmentsProxy.clear()
      let convreq3 = f.setUpInputForSuggestion("ございま", segmentsProxy)
      results = predictor.predict(convreq3)
      #expect(!results.isEmpty)
      #expect(results.first?.value == "ございます")
      #expect(part4Find("ございます！よろしくお願いします", results) == nil)

      // Zero query from "ございます" -> no suggestion
      let convreq4 = f.setUpInputForConversionWithHistory(
        "", "ございます", "ございます", segmentsProxy)
      segmentsProxy.addSegment("")  // empty request
      results = predictor.predict(convreq4)
      #expect(results.isEmpty)
    }
  }

  @Test func punctuationLinkDesktop() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()
    let segmentsProxy = SegmentsProxy()
    var results: [PredictionResult] = []

    do {
      let convreq1 = f.setUpInputForConversion("ございます", segmentsProxy)
      segmentsProxy.addCandidate(0, "ございます")

      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)
      segmentsProxy.setHistoryType(0)

      segmentsProxy.addSegment("!")
      segmentsProxy.addCandidate(1, "！")
      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

      segmentsProxy.clear()
      let convreq2 = f.setUpInputForSuggestion("ございま", segmentsProxy)
      results = predictor.predict(convreq2)
      #expect(!results.isEmpty)
      #expect(results.first?.value == "ございます")
      #expect(part4Find("ございます！", results) == nil)

      segmentsProxy.clear()
      let convreq3 = f.setUpInputForSuggestion("ございます", segmentsProxy)
      results = predictor.predict(convreq3)
      #expect(!results.isEmpty)
      #expect(results.first?.value == "ございます")
      #expect(part4Find("ございます！", results) == nil)
    }

    predictor.clearAllHistory()

    do {
      let convreq1 = f.setUpInputForConversion("!", segmentsProxy)
      segmentsProxy.addCandidate(0, "！")

      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)
      segmentsProxy.setHistoryType(0)

      segmentsProxy.addSegment("よろしくおねがいします")
      segmentsProxy.addCandidate(1, "よろしくお願いします")
      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

      segmentsProxy.clear()
      let convreq2 = f.setUpInputForSuggestion("!", segmentsProxy)
      results = predictor.predict(convreq2)
      #expect(results.isEmpty)
    }

    predictor.clearAllHistory()

    do {
      // Ends with punctuation.
      let convreq1 = f.setUpInputForConversion("ございます!", segmentsProxy)
      segmentsProxy.addCandidate(0, "ございます！")

      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)
      segmentsProxy.setHistoryType(0)

      segmentsProxy.addSegment("よろしくおねがいします")
      segmentsProxy.addCandidate(1, "よろしくお願いします")
      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

      segmentsProxy.clear()
      let convreq2 = f.setUpInputForSuggestion("ございます", segmentsProxy)
      results = predictor.predict(convreq2)
      #expect(results.isEmpty)

      segmentsProxy.clear()
      let convreq3 = f.setUpInputForSuggestion("ございます!", segmentsProxy)
      results = predictor.predict(convreq3)
      #expect(results.isEmpty)
    }

    predictor.clearAllHistory()

    do {
      let convreq1 = f.setUpInputForConversion("ございます", segmentsProxy)
      segmentsProxy.addCandidate(0, "ございます")

      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)
      segmentsProxy.setHistoryType(0)

      segmentsProxy.addSegment("!よろしくおねがいします")
      segmentsProxy.addCandidate(1, "！よろしくお願いします")
      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

      segmentsProxy.clear()
      let convreq2 = f.setUpInputForSuggestion("ございます", segmentsProxy)
      results = predictor.predict(convreq2)
      #expect(!results.isEmpty)
      #expect(results.first?.value == "ございます")
      #expect(part4Find("ございます！", results) == nil)
      #expect(part4Find("ございます！よろしくお願いします", results) == nil)
    }

    predictor.clearAllHistory()

    do {
      let convreq1 = f.setUpInputForConversion("よろしくおねがいします", segmentsProxy)
      segmentsProxy.addCandidate(0, "よろしくお願いします")

      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)
      segmentsProxy.setHistoryType(0)

      segmentsProxy.addSegment("!")
      segmentsProxy.addCandidate(1, "！")
      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

      segmentsProxy.clear()
      let convreq2 = f.setUpInputForSuggestion("よろしくおねがいします", segmentsProxy)
      results = predictor.predict(convreq2)
      #expect(!results.isEmpty)
      #expect(part4Find("よろしくお願いします", results) != nil)
    }
  }

  @Test func entriesAreDeletedAtSync() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    for i in 0..<12000 {
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForConversion("わたしのなまえ\(i)", segmentsProxy)
      segmentsProxy.addCandidate(0, "私の名前\(i)")
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }

    predictor.sync()
    await predictor.wait()

    func hasKey(_ key: String) -> Bool {
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForPrediction(key, segmentsProxy)
      return !predictor.predict(convreq).isEmpty
    }

    #expect(!hasKey("わたしのなまえ0"))  // too old
    #expect(hasKey("わたしのなまえ11000"))
  }

  @Test func futureTimestamp() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    // Test the case where history has "future" timestamps.
    withScopedClockMock(Date(unixSeconds: 10000)) { clock in
      let predictor = f.getUserHistoryPredictorWithClearedHistory()

      // Let the predictor learn "私の名前は中野です".
      let segmentsProxy = SegmentsProxy()
      var results: [PredictionResult] = []
      let convreq1 = f.setUpInputForConversion("わたしのなまえはなかのです", segmentsProxy)
      segmentsProxy.addCandidate(0, "私の名前は中野です")
      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

      // Verify that "私の名前は中野です" is predicted.
      segmentsProxy.clear()
      let convreq2 = f.setUpInputForPrediction("わたしの", segmentsProxy)
      results = predictor.predict(convreq2)
      #expect(!results.isEmpty)
      #expect(part4Find("私の名前は中野です", results) != nil)

      // Now, go back to the past.
      clock.setTime(Date(unixSeconds: 1))

      // Verify that "私の名前は中野です" is predicted without crash.
      segmentsProxy.clear()
      let convreq3 = f.setUpInputForPrediction("わたしの", segmentsProxy)
      results = predictor.predict(convreq3)
      #expect(!results.isEmpty)
      #expect(part4Find("私の名前は中野です", results) != nil)
    }
  }

  @Test func maxPredictionCandidatesSize() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()
    let segmentsProxy = SegmentsProxy()
    var results: [PredictionResult] = []
    for value in ["てすと", "テスト", "Test"] {
      let convreq = f.setUpInputForPrediction("てすと", segmentsProxy)
      segmentsProxy.addCandidate(0, value)
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }
    do {
      var options1 = ConversionRequest.Options()
      options1.requestType = .suggestion
      options1.maxUserHistoryPredictionCandidatesSize = 2
      let convreq1 = f.createConversionRequestWithOptions(options1, segmentsProxy)
      segmentsProxy.makeSegments("てすと")

      results = predictor.predict(convreq1)
      #expect(!results.isEmpty)
      #expect(results.count == 2)

      var options2 = ConversionRequest.Options()
      options2.requestType = .prediction
      options2.maxUserHistoryPredictionCandidatesSize = 2
      let convreq2 = f.createConversionRequestWithOptions(options2, segmentsProxy)
      segmentsProxy.makeSegments("てすと")
      results = predictor.predict(convreq2)
      #expect(!results.isEmpty)
      #expect(results.count == 2)
    }
    // [max candidates size, expected size]; only 3 candidates in user history.
    for (size, expected) in [(3, 3), (4, 3)] {
      f.setUpInput("てすと", segmentsProxy)
      var options1 = ConversionRequest.Options()
      options1.requestType = .suggestion
      options1.maxUserHistoryPredictionCandidatesSize = size
      let convreq1 = f.createConversionRequestWithOptions(options1, segmentsProxy)
      results = predictor.predict(convreq1)
      #expect(!results.isEmpty)
      #expect(results.count == expected)

      f.setUpInput("てすと", segmentsProxy)
      var options2 = ConversionRequest.Options()
      options2.requestType = .prediction
      options2.maxUserHistoryPredictionCandidatesSize = size
      let convreq2 = f.createConversionRequestWithOptions(options2, segmentsProxy)
      results = predictor.predict(convreq2)
      #expect(!results.isEmpty)
      #expect(results.count == expected)
    }
  }

  @Test func maxPredictionCandidatesSizeForZeroQuery() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()
    RequestTestUtil.fillMobileRequest(&f.request)
    let segmentsProxy = SegmentsProxy()
    var results: [PredictionResult] = []

    let convreq = f.setUpInputForPrediction("てすと", segmentsProxy)
    do {
      segmentsProxy.addCandidate(0, "てすと")
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
      segmentsProxy.setHistoryType(0)
    }
    do {
      segmentsProxy.addSegment("かお")
      segmentsProxy.addCandidate(1, "😀")
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }
    do {
      segmentsProxy.setCandidate(1, 0, "😎")
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }
    do {
      segmentsProxy.setCandidate(1, 0, "😂")
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }

    func makeOptions(_ type: RequestType) -> ConversionRequest.Options {
      var options = ConversionRequest.Options()
      options.requestType = type
      options.maxUserHistoryPredictionCandidatesSize = 2
      options.maxUserHistoryPredictionCandidatesSizeForZeroQuery = 3
      return options
    }

    // normal prediction candidates size
    for type in [RequestType.suggestion, .prediction] {
      f.setUpInput("かお", segmentsProxy)
      let convreq1 = f.createConversionRequestWithOptions(makeOptions(type), segmentsProxy)
      results = predictor.predict(convreq1)
      #expect(!results.isEmpty)
      #expect(results.count == 2)
    }

    // prediction candidates for zero query
    for type in [RequestType.suggestion, .prediction] {
      f.setUpInput("", segmentsProxy)
      segmentsProxy.prependHistory("てすと", "てすと")
      let convreq1 = f.createConversionRequestWithOptions(makeOptions(type), segmentsProxy)
      results = predictor.predict(convreq1)
      #expect(!results.isEmpty)
      #expect(results.count == 3)
    }
  }

  @Test func typingCorrection() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let mock = MockSupplementalModel()
    let data = try await Fixture.createDataAndPredictor(supplementalModel: mock)
    let predictor = data.predictor
    await predictor.wait()

    withScopedClockMock(Date(unixSeconds: 1)) { clock in
      let segmentsProxy = SegmentsProxy()
      var results: [PredictionResult] = []

      for (key, value) in [("がっこう", "学校"), ("がっこう", "ガッコウ"), ("かっこう", "格好")] {
        clock.advance(.seconds(3600))
        let convreq = f.setUpInputForPrediction(key, segmentsProxy)
        segmentsProxy.addCandidate(0, value)
        predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
      }

      f.request.decoderExperimentParams.typingCorrectionApplyUserHistorySize = 1

      let convreq1 = f.setUpInputForSuggestion("がっこ", segmentsProxy)
      results = predictor.predict(convreq1)
      #expect(!results.isEmpty)

      // No typing correction.
      let convreq2 = f.setUpInputForSuggestion("かつこ", segmentsProxy)
      results = predictor.predict(convreq2)
      #expect(results.isEmpty)

      var expected: [TypeCorrectedQuery] = []
      func addExpected(_ key: String) {
        expected.append(TypeCorrectedQuery(correction: key, type: .correction, score: 1.0, bias: 0.0))
      }

      // かつこ -> がっこ and かっこ
      addExpected("がっこ")
      addExpected("かっこ")
      let expectedQueries = expected
      mock.correctCompositionHandler = { _ in expectedQueries }

      // set_typing_correction_apply_user_history_size=0
      f.request.decoderExperimentParams.typingCorrectionApplyUserHistorySize = 0
      let convreq3 = f.setUpInputForSuggestion("かつこ", segmentsProxy)
      results = predictor.predict(convreq3)
      #expect(results.isEmpty)

      // set_typing_correction_apply_user_history_size=1
      f.request.decoderExperimentParams.typingCorrectionApplyUserHistorySize = 1
      let convreq4 = f.setUpInputForSuggestion("かつこ", segmentsProxy)
      results = predictor.predict(convreq4)
      #expect(!results.isEmpty)
      #expect(results.count == 2)
      if results.count == 2 {
        #expect(results[0].value == "ガッコウ")
        #expect(results[1].value == "学校")
      }

      // set_typing_correction_apply_user_history_size=2
      f.request.decoderExperimentParams.typingCorrectionApplyUserHistorySize = 2
      let convreq5 = f.setUpInputForSuggestion("かつこ", segmentsProxy)
      results = predictor.predict(convreq5)
      #expect(!results.isEmpty)
      #expect(results.count == 3)
      if results.count == 3 {
        #expect(results[0].value == "格好")
        #expect(results[1].value == "ガッコウ")
        #expect(results[2].value == "学校")
      }

      // ::testing::Mock::VerifyAndClearExpectations(mock_ptr);
      mock.correctCompositionHandler = nil
      let convreq6 = f.setUpInputForSuggestion("かつこ", segmentsProxy)
      results = predictor.predict(convreq6)
      #expect(results.isEmpty)
    }
  }

  @Test func maxCharCoverage() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()
    let segmentsProxy = SegmentsProxy()

    for value in ["てすと", "テスト", "Test"] {
      let convreq = f.setUpInputForPrediction("てすと", segmentsProxy)
      segmentsProxy.addCandidate(0, value)
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }

    // [max_char_coverage, expected_candidate_size]
    let kTestCases: [(Int32, Int)] = [
      (1, 1), (2, 1), (3, 1), (4, 1), (5, 1), (6, 2),
      (7, 2), (8, 2), (9, 2), (10, 3), (11, 3),
    ]

    for (coverage, candidatesSize) in kTestCases {
      f.request.decoderExperimentParams.userHistoryPredictionMaxCharCoverage = coverage
      segmentsProxy.makeSegments("てすと")
      var options = ConversionRequest.Options()
      options.requestType = .suggestion
      let convreq = f.createConversionRequestWithOptions(options, segmentsProxy)

      let results = predictor.predict(convreq)
      #expect(!results.isEmpty)
      #expect(results.count == candidatesSize, "coverage: \(coverage)")
    }
  }

  @Test func removeRedundantCandidates() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    // pass the input candidates and expected (filtered) candidates.
    func runTest(_ candidates: [String], _ expected: [String]) {
      withScopedClockMock(Date(unixSeconds: 1)) { clock in
        let predictor = f.getUserHistoryPredictorWithClearedHistory()
        let segmentsProxy = SegmentsProxy()
        // Insert in reverse order to emulate LRU.
        for candidate in candidates.reversed() {
          clock.advance(.seconds(3600))
          let convreq = f.setUpInputForPrediction("とうき", segmentsProxy)
          segmentsProxy.addCandidate(0, candidate)
          predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
        }
        segmentsProxy.makeSegments("とうき")
        var options = ConversionRequest.Options()
        options.requestType = .suggestion
        options.maxUserHistoryPredictionCandidatesSize = 10
        let convreq = f.createConversionRequestWithOptions(options, segmentsProxy)
        let results = predictor.predict(convreq)
        #expect(!results.isEmpty)
        #expect(results.map(\.value) == expected, "\(candidates)")
      }
    }

    // filter long and replace short entries.
    runTest(["東京は", "東京", "大阪", "大阪は"], ["東京", "大阪"])
    runTest(["東京", "東京は", "大阪は", "大阪"], ["東京", "大阪"])
    runTest(["東京駅", "東京", "大阪", "大阪駅"], ["東京駅", "東京", "大阪", "大阪駅"])
    runTest(["東京", "東京駅", "大阪駅", "大阪"], ["東京", "東京駅", "大阪駅", "大阪"])
    runTest(["東京は", "東京", "大阪", "大阪駅"], ["東京", "大阪", "大阪駅"])
    runTest(["東京", "東京は", "大阪駅", "大阪"], ["東京", "大阪駅", "大阪"])
  }

  @Test func numberCounterSuffixPrecedingHistory() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()
    let segmentsProxy = SegmentsProxy()

    // 1. Commit "3" -> "3", then commit "かい" -> "階" (preceded by number).
    do {
      let convreqNum = f.setUpInputForPrediction("3", segmentsProxy)
      segmentsProxy.addCandidate(0, "3")
      predictor.finish(convreqNum, segmentsProxy.makeLearningResults(), kRevertId)

      let convreqKai = f.setUpInputForPrediction("かい", segmentsProxy)
      segmentsProxy.addCandidate(0, "階")
      segmentsProxy.prependHistory("3", "3")
      predictor.finish(convreqKai, segmentsProxy.makeLearningResults(), kRevertId + 1)

      let entry = predictor.storage.lookup("かい", "階")
      try #require(!entry.isNull)
      #expect(entry.entry.entryFlags & UserHistoryPredictor.EntryFlag.leftNumber != 0)
    }

    // Sleep 1 second to ensure different last_access_time.
    try? await Task.sleep(for: .seconds(1))

    // 2. Commit "かい" -> "会" (non-counter homophone) without preceding number,
    // so "会" is more recent in LRU and does NOT have ENTRY_FLAG_LEFT_NUMBER.
    do {
      let convreq = f.setUpInputForPrediction("かい", segmentsProxy)
      segmentsProxy.addCandidate(0, "会")
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId + 2)

      let entry = predictor.storage.lookup("かい", "会")
      try #require(!entry.isNull)
      #expect(entry.entry.entryFlags & UserHistoryPredictor.EntryFlag.leftNumber == 0)
    }

    // 3. Commit "5" -> "5" (pure number).
    do {
      let convreq = f.setUpInputForPrediction("5", segmentsProxy)
      segmentsProxy.addCandidate(0, "5")
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId + 3)
    }

    // 4. Query "かい" with history "5" -> "5".
    // "階" should be boosted with BIGRAM attribute and ranked above "会",
    // even though "会" was used more recently.
    do {
      let convreq = f.setUpInputForPredictionWithHistory("かい", "5", "5", segmentsProxy)
      let results = predictor.predict(convreq)
      try #require(!results.isEmpty)
      #expect(results[0].value == "階")
      #expect(results[0].attributes & Attribute.bigram != 0)

      // "会" should not have BIGRAM attribute.
      if let kai = results.first(where: { $0.value == "会" }) {
        #expect(kai.attributes & Attribute.bigram == 0)
      }
    }

    // 5. Zero-query suggestion after "5".
    // "階" should be suggested as zero query because it is a counter suffix,
    // whereas "会" should not be suggested.
    do {
      f.request.zeroQuerySuggestion = true
      f.request.mixedConversion = true
      let convreq = f.setUpInputForSuggestionWithHistory("", "5", "5", segmentsProxy)
      let results = predictor.predict(convreq)
      let floor = try #require(results.first(where: { $0.value == "階" }))
      #expect(floor.value == "階")
      #expect(floor.attributes & Attribute.bigram != 0)

      #expect(results.first(where: { $0.value == "会" }) == nil)
    }

    // 6. When preceding history is NOT a number (e.g. "東京"),
    // "会" should be ranked #1 (due to recency) and "階" should NOT have BIGRAM
    // attribute.
    do {
      let convreqTokyo = f.setUpInputForPrediction("とうきょう", segmentsProxy)
      segmentsProxy.addCandidate(0, "東京")
      predictor.finish(convreqTokyo, segmentsProxy.makeLearningResults(), kRevertId + 4)

      let convreq = f.setUpInputForPredictionWithHistory("かい", "とうきょう", "東京", segmentsProxy)
      let results = predictor.predict(convreq)
      try #require(!results.isEmpty)
      #expect(results[0].value == "会")

      if let floor = results.first(where: { $0.value == "階" }) {
        #expect(floor.attributes & Attribute.bigram == 0)
      }
    }

    // 7. When there is NO preceding history at all (isolated query),
    // it also falls back to simple LRU: "会" (#1) > "階" (#2).
    do {
      let convreq = f.setUpInputForPrediction("かい", segmentsProxy)
      let results = predictor.predict(convreq)
      try #require(results.count >= 2)
      #expect(results[0].value == "会")
      #expect(results[1].value == "階")
      #expect(results[0].attributes & Attribute.bigram == 0)
      #expect(results[1].attributes & Attribute.bigram == 0)
    }
  }

  @Test func bracketPairLearning() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()
    let segmentsProxy = SegmentsProxy()

    // 1. Commit open bracket "「" -> "『".
    do {
      let convreq = f.setUpInputForPrediction("「", segmentsProxy)
      segmentsProxy.addCandidate(0, "『")
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }

    // 2. Predict for close bracket "」" -> "』" should be suggested.
    do {
      let convreq = f.setUpInputForPrediction("」", segmentsProxy)
      let results = predictor.predict(convreq)
      try #require(!results.isEmpty)
      #expect(results[0].key == "」")
      #expect(results[0].value == "』")
    }

    // 3. Revert open bracket -> close bracket should also be removed.
    do {
      predictor.revert(kRevertId)
      let convreq = f.setUpInputForPrediction("」", segmentsProxy)
      let results = predictor.predict(convreq)
      #expect(results.first(where: { $0.key == "」" && $0.value == "』" }) == nil)
    }
  }

  @Test func multiSegmentWeakCandidateWithinFirstSegment() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    f.request.decoderExperimentParams.disableLegacyRewriterMode = 1
    let predictor = f.getUserHistoryPredictorWithClearedHistory()
    let segmentsProxy = SegmentsProxy()
    do {
      let convreq = f.setUpInputForPrediction("きょうはいった", segmentsProxy)
      segmentsProxy.addCandidate(0, "今日は言った")
      // "きょうは, 今日は"
      segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 12, 9, 9, 6)
      // "いった, 言った"
      segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 9, 9, 6, 6)
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }

    func suggest(_ key: String) -> [PredictionResult] {
      segmentsProxy.makeSegments(key)
      var options = ConversionRequest.Options()
      options.requestType = .suggestion
      options.maxUserHistoryPredictionCandidatesSize = 10
      let convreq = f.createConversionRequestWithOptions(options, segmentsProxy)
      return predictor.predict(convreq)
    }

    // 1. In desktop mode (mixed_conversion = false), WEAK is NOT set.
    do {
      f.request.mixedConversion = false
      let results = suggest("きょうは")
      let it = try #require(results.first(where: { $0.value == "今日は言った" }))
      #expect(it.attributes & Attribute.weakUserHistoryPrediction == 0)
    }

    // 2. In mobile mode (mixed_conversion = true), query "きょうは" (within 1st
    // segment): "今日は言った" must have WEAK attribute.
    do {
      f.request.mixedConversion = true
      let results = suggest("きょうは")
      if let it = results.first(where: { $0.value == "今日は言った" }) {
        #expect(it.attributes & Attribute.weakUserHistoryPrediction != 0)
      }
    }

    // 2. Query "きょうはい" (across 1st segment into last segment):
    // "今日は言った" must NOT have WEAK attribute.
    do {
      let results = suggest("きょうはい")
      let it = try #require(results.first(where: { $0.value == "今日は言った" }))
      #expect(it.attributes & Attribute.weakUserHistoryPrediction == 0)
    }

    // 3. Test 3-segment entry: "今日は駅に行った" ("きょうは|えきに|いった")
    do {
      let convreq3 = f.setUpInputForPrediction("きょうはえきにいった", segmentsProxy)
      segmentsProxy.addCandidate(0, "今日は駅に行った")
      // "きょうは, 今日は"
      segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 12, 9, 9, 6)
      // "えきに, 駅に"
      segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 9, 6, 6, 3)
      // "いった, 行った"
      segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 9, 9, 6, 6)
      predictor.finish(convreq3, segmentsProxy.makeLearningResults(), kRevertId)

      // Query "きょうはえきに" (ends at 2nd segment): WEAK.
      let resultsSeg2 = suggest("きょうはえきに")
      if let it2 = resultsSeg2.first(where: { $0.value == "今日は駅に行った" }) {
        #expect(it2.attributes & Attribute.weakUserHistoryPrediction != 0)
      }

      // Query "きょうはえきにい" (reaches 3rd segment): NOT WEAK.
      let resultsSeg3 = suggest("きょうはえきにい")
      let it3 = try #require(resultsSeg3.first(where: { $0.value == "今日は駅に行った" }))
      #expect(it3.attributes & Attribute.weakUserHistoryPrediction == 0)
    }

    // 4. Zero-query prediction (request.key().empty()): Multi-segment bigram
    // history must NOT have WEAK attribute.
    do {
      let kinou = Fixture.insertEntry(predictor, "きのう", "昨日")
      let kyouwaItta = Fixture.appendEntry(predictor, "きょうはいった", "今日は言った", kinou)
      kyouwaItta.entry.suggestionFreq = 2
      kyouwaItta.entry.innerSegmentBoundary.append(encodeLengths(12, 9, 9, 6)!)
      kyouwaItta.entry.innerSegmentBoundary.append(encodeLengths(9, 9, 6, 6)!)

      f.request.zeroQuerySuggestion = true
      let convreqZero = f.setUpInputForSuggestionWithHistory("", "きのう", "昨日", segmentsProxy)
      segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 9, 6, 9, 6)
      let resultsZero = predictor.predict(convreqZero)
      let itZero = try #require(resultsZero.first(where: { $0.value == "今日は言った" }))
      #expect(itZero.attributes & Attribute.weakUserHistoryPrediction == 0)
    }
  }

  @Test func contentValueZeroQuery() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    // Remember 私の名前は中野です
    let segmentsProxy = SegmentsProxy()
    do {
      let convreq = f.setUpInputForPrediction("わたしのなまえはなかのです", segmentsProxy)
      segmentsProxy.addCandidate(0, "私の名前は中野です")
      // "わたしの, 私の", "わたし, 私"
      segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 12, 6, 9, 3)
      // "なまえは, 名前は", "なまえ, 名前"
      segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 12, 9, 9, 6)
      // "なかのです, 中野です", "なかの, 中野"
      segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 15, 12, 9, 6)
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }

    // Zero query from content values. suffix is suggested.
    let kZeroQueryTest: [(String, String, String)] = [
      ("わたし", "私", "の"),
      ("なまえ", "名前", "は"),
      ("なかの", "中野", "です"),
      ("わたしの", "私の", "名前"),
      ("なまえは", "名前は", "中野"),
    ]
    for (histKey, histValue, _) in kZeroQueryTest {
      segmentsProxy.clear()
      let convreq1 = f.setUpInputForConversion(histKey, segmentsProxy)
      segmentsProxy.addCandidate(0, histValue)
      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)
      segmentsProxy.setHistoryType(0)
      f.request.zeroQuerySuggestion = true
      let convreq2 = f.setUpInputForSuggestionWithHistory("", histKey, histValue, segmentsProxy)
      let results = predictor.predict(convreq2)
      #expect(!results.isEmpty, "\(histKey)")
    }

    // Bigram History.
    // (C++ sets mixed_conversion after building the request, which sees it
    // through its request view; the Swift request copies, so it is set first.)
    do {
      segmentsProxy.clear()
      f.request.mixedConversion = true
      let convreq1 = f.setUpInputForSuggestion("", segmentsProxy)
      segmentsProxy.prependHistory("の", "の")
      segmentsProxy.prependHistory("わたし", "私")
      var results = predictor.predict(convreq1)
      try #require(!results.isEmpty)
      #expect(results[0].value == "名前")

      segmentsProxy.clear()
      let convreq2 = f.setUpInputForSuggestion("", segmentsProxy)
      segmentsProxy.prependHistory("は", "は")
      segmentsProxy.prependHistory("なまえ", "名前")
      results = predictor.predict(convreq2)
      try #require(!results.isEmpty)
      #expect(results[0].value == "中野")
    }
  }

  @Test func guessRevertedValueOffset() async {
    func runTest(_ revertedValue: String, _ leftContext: String) -> Int32 {
      UserHistoryPredictor.guessRevertedValueOffset(revertedValue, leftContext)
    }

    // Invalid input.
    #expect(runTest("abc", "") == 0)
    #expect(runTest("", "abc") == 0)
    #expect(runTest("", "") == 0)

    #expect(runTest("xyz", "") == 0)
    #expect(runTest("xyz", "x") == 1)
    #expect(runTest("xyz", "xy") == 2)
    #expect(runTest("xyz", "xyz") == 3)
    #expect(runTest("xyz", "xyzX") == 0)

    // Real Japanese test set.
    #expect(runTest("渋谷駅", "停車駅は渋谷駅") == 9)
    #expect(runTest("渋谷駅", "停車駅は渋谷") == 6)
    #expect(runTest("渋谷駅", "停車駅は渋") == 3)
    #expect(runTest("渋谷駅", "停車駅は") == 0)
    #expect(runTest("渋谷駅", "停車駅") == 0)
  }
}
