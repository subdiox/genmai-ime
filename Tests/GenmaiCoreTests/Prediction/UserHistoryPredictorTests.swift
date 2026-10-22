// Port of mozc/src/prediction/user_history_predictor_test.cc (3.35.6354),
// part 1 (UserHistoryPredictorTest .. DescriptionTest). The fixture lives in
// UserHistoryPredictorTestSupport.swift; the remaining tests are in
// UserHistoryPredictorTests2..4.swift.
//
// Each C++ TEST_F is a test of a `.scopedConfigEnvironment` suite (temporary
// user profile, fresh ConfigHandler / CharacterFormManager) that creates a
// `UserHistoryPredictorTestFixture` (SetUp; TearDown runs in its deinit).
// Tests are skipped when the mock data set is missing.

import Foundation
import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

@Suite(.scopedConfigEnvironment) struct UserHistoryPredictorTest {
  @Test func userHistoryPredictorTest() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    do {
      let predictor = f.getUserHistoryPredictor()
      await predictor.wait()

      var results: [PredictionResult] = []

      // Nothing happen
      do {
        let segmentsProxy = SegmentsProxy()
        let convreq = f.setUpInputForSuggestion("てすと", segmentsProxy)
        results = predictor.predict(convreq)
        #expect(results.isEmpty)
        #expect(results.count == 0)
      }

      // Nothing happen
      do {
        let segmentsProxy = SegmentsProxy()
        let convreq = f.setUpInputForSuggestion("てすと", segmentsProxy)
        results = predictor.predict(convreq)
        #expect(results.isEmpty)
        #expect(results.count == 0)
      }

      // Insert two items
      do {
        let segmentsProxy = SegmentsProxy()
        let convreq1 = f.setUpInputForSuggestion("わたしのなまえはなかのです", segmentsProxy)
        segmentsProxy.addCandidate(0, "私の名前は中野です")
        predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

        segmentsProxy.clear()
        let convreq2 = f.setUpInputForSuggestion("わたしの", segmentsProxy)
        results = predictor.predict(convreq2)
        #expect(!results.isEmpty)
        #expect(results.first?.value == "私の名前は中野です")

        segmentsProxy.clear()
        let convreq3 = f.setUpInputForSuggestion("わたしの", segmentsProxy)
        results = predictor.predict(convreq3)
        #expect(!results.isEmpty)
        #expect(results.first?.value == "私の名前は中野です")
      }

      // Insert without learning (nothing happen).
      do {
        let noLearningLevels: [Genmai_Config_Config.HistoryLearningLevel] = [.readOnly, .noHistory]
        for level in noLearningLevels {
          f.config.historyLearningLevel = level

          let segmentsProxy = SegmentsProxy()
          let convreq1 = f.setUpInputForSuggestion("こんにちはさようなら", segmentsProxy)
          segmentsProxy.addCandidate(0, "今日はさようなら")
          predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

          segmentsProxy.clear()
          let convreq2 = f.setUpInputForSuggestion("こんにちは", segmentsProxy)
          results = predictor.predict(convreq2)
          #expect(results.isEmpty)
          let convreq3 = f.setUpInputForSuggestion("こんにちは", segmentsProxy)
          results = predictor.predict(convreq3)
          #expect(results.isEmpty)
        }
        f.config.historyLearningLevel = .defaultHistory
      }

      // sync
      predictor.sync()
      try? await Task.sleep(for: .seconds(0.5))
    }

    // reload
    do {
      let predictor = f.getUserHistoryPredictor()
      await predictor.wait()
      let segmentsProxy = SegmentsProxy()
      var results: [PredictionResult] = []

      // turn off
      do {
        let segmentsProxy = SegmentsProxy()
        f.config.useHistorySuggest = false

        let convreq1 = f.setUpInputForSuggestion("わたしの", segmentsProxy)
        results = predictor.predict(convreq1)
        #expect(results.isEmpty)

        f.config.useHistorySuggest = true
        f.config.incognitoMode = true

        let convreq2 = f.setUpInputForSuggestion("わたしの", segmentsProxy)
        results = predictor.predict(convreq2)
        #expect(results.isEmpty)

        f.config.incognitoMode = false
        f.config.historyLearningLevel = .noHistory

        let convreq3 = f.setUpInputForSuggestion("わたしの", segmentsProxy)
        results = predictor.predict(convreq3)
        #expect(results.isEmpty)
      }

      // turn on
      do {
        f.config = ConfigHandler.defaultConfig()
      }

      // reproduced
      do {
        // Prediction

        let convreq1 = f.setUpInputForSuggestion("わたしの", segmentsProxy)
        results = predictor.predict(convreq1)
        #expect(!results.isEmpty)
        #expect(results.first?.value == "私の名前は中野です")

        segmentsProxy.clear()
        let convreq2 = f.setUpInputForSuggestion("わたしの", segmentsProxy)
        results = predictor.predict(convreq2)
        #expect(!results.isEmpty)
        #expect(results.first?.value == "私の名前は中野です")

        // Exact Match
        segmentsProxy.clear()
        let convreq3 = f.setUpInputForSuggestion("わたしのなまえはなかのです", segmentsProxy)
        results = predictor.predict(convreq3)
        #expect(!results.isEmpty)
        #expect(results.first?.value == "私の名前は中野です")

        segmentsProxy.clear()
        let convreq4 = f.setUpInputForSuggestion("わたしのなまえはなかのです", segmentsProxy)
        results = predictor.predict(convreq4)
        #expect(!results.isEmpty)
        #expect(results.first?.value == "私の名前は中野です")
      }

      do {
        // Conversion
        // Partial match
        let convreq1 = f.setUpInputForConversion("わたしの", segmentsProxy)
        results = predictor.convert(convreq1)
        #expect(results.isEmpty)

        // Exact Match
        segmentsProxy.clear()
        let convreq2 = f.setUpInputForConversion("わたしのなまえはなかのです", segmentsProxy)
        results = predictor.convert(convreq2)
        #expect(!results.isEmpty)
        #expect(results.first?.value == "私の名前は中野です")
      }

      segmentsProxy.clear()
      let convreq5 = f.setUpInputForSuggestion("こんにちはさようなら", segmentsProxy)
      results = predictor.predict(convreq5)
      #expect(results.isEmpty)

      segmentsProxy.clear()
      let convreq6 = f.setUpInputForSuggestion("こんにちはさようなら", segmentsProxy)
      results = predictor.predict(convreq6)
      #expect(results.isEmpty)

      // Read only mode should show suggestion.
      do {
        f.config.historyLearningLevel = .readOnly
        let convreq1 = f.setUpInputForSuggestion("わたしの", segmentsProxy)
        results = predictor.predict(convreq1)
        #expect(!results.isEmpty)
        #expect(results.first?.value == "私の名前は中野です")

        segmentsProxy.clear()
        let convreq2 = f.setUpInputForSuggestion("わたしの", segmentsProxy)
        results = predictor.predict(convreq2)
        #expect(!results.isEmpty)
        #expect(results.first?.value == "私の名前は中野です")
        f.config.historyLearningLevel = .defaultHistory
      }

      // clear
      predictor.clearAllHistory()
    }

    // nothing happen
    for _ in 0..<2 {
      let predictor = f.getUserHistoryPredictor()
      await predictor.wait()
      let segmentsProxy = SegmentsProxy()

      // reproduced
      let convreq1 = f.setUpInputForSuggestion("わたしの", segmentsProxy)
      var results = predictor.predict(convreq1)
      #expect(results.isEmpty)

      let convreq2 = f.setUpInputForSuggestion("わたしの", segmentsProxy)
      results = predictor.predict(convreq2)
      #expect(results.isEmpty)
    }
  }

  @Test func removeUnselectedHistoryPrediction() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    RequestTestUtil.fillMobileRequest(&f.request)

    let predictor = f.getUserHistoryPredictorWithClearedHistory()
    await predictor.wait()

    var results: [PredictionResult] = []

    func makeSegments(_ results: [PredictionResult], _ segmentsProxy: SegmentsProxy) {
      for result in results {
        segmentsProxy.addCandidate(0, result.value)
      }
    }

    func insertTarget() {
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForPrediction("わたしの", segmentsProxy)
      segmentsProxy.addCandidate(0, "私の")
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }

    func findTarget() -> Int? {
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForPrediction("わたしの", segmentsProxy)
      results = predictor.predict(convreq)
      #expect(!results.isEmpty)
      return UserHistoryPredictorTestFixture.findCandidateByValue("私の", results)
    }

    // Returns true if the target is found.
    func selectTarget() {
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForPrediction("わたしの", segmentsProxy)
      results = predictor.predict(convreq)
      #expect(!results.isEmpty)
      #expect(UserHistoryPredictorTestFixture.findCandidateByValue("私の", results) != nil)
      makeSegments(results, segmentsProxy)
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }

    func selectOther() {
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForPrediction("わたしの", segmentsProxy)
      results = predictor.predict(convreq)
      #expect(!results.isEmpty)
      #expect(UserHistoryPredictorTestFixture.findCandidateByValue("私の", results) != nil)
      makeSegments(results, segmentsProxy)
      if let find = UserHistoryPredictorTestFixture.findCandidateByValue("わたしの", results) {
        segmentsProxy.moveCandidate(0, find, 0)
      } else {
        segmentsProxy.addCandidate(0, "わたしの")
        segmentsProxy.moveCandidate(0, 1, 0)
      }
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)  // Select "わたしの"
    }

    func inputOtherKey() {
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForPrediction("てすと", segmentsProxy)
      results = predictor.predict(convreq)
      makeSegments(results, segmentsProxy)
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }

    // min selected ratio threshold is 0.05

    do {
      insertTarget()
      for _ in 0..<20 {
        #expect(findTarget() != nil)
        selectOther()
      }
      // select: 1, shown: 1+20, ratio: 1/21 < 0.05
      #expect(findTarget() == nil)  // **
    }

    do {
      insertTarget()
      for _ in 0..<19 {
        #expect(findTarget() != nil)
        selectOther()
      }
      // select: 1, shown 1+19, ratio: 1/20 >= 0.05
      #expect(findTarget() != nil)

      // other key does not matter
      for _ in 0..<20 {
        inputOtherKey()
      }
      #expect(findTarget() != nil)

      selectTarget()  // select: 2, shown 1+19+1, ratio: 2/21 >= 0.05
      for _ in 0..<20 {
        #expect(findTarget() != nil)
        selectOther()
      }
      // select: 2, shown: 1+19+1+20, ratio: 2/41 < 0.05
      #expect(findTarget() == nil)  // **

      predictor.revert(kRevertId)
      #expect(findTarget() != nil)
    }
  }

  // We did not support such Segments which has multiple segments and
  // has type != CONVERSION.
  // To support such Segments, this test case is created separately.
  @Test func userHistoryPredictorTestSuggestion() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    // Register input histories via Finish method.
    do {
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForSuggestion("かまた", segmentsProxy)
      segmentsProxy.addCandidate(0, "火魔汰")
      segmentsProxy.addSegment("ま")
      segmentsProxy.addCandidate(1, "摩")
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)

      // All added items must be suggestion entries.
      predictor.storage.forEachEntry { fp, entry in
        #expect(entry.suggestionFreq == 1)
        return true
      }
    }

    // Obtain input histories via Predict method.
    do {
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForSuggestion("かま", segmentsProxy)
      let results = predictor.predict(convreq)
      #expect(!results.isEmpty)
      var expectedCandidates = Set<String>()
      expectedCandidates.insert("火魔汰")
      // We can get this entry even if Segmtnts's type is not CONVERSION.
      expectedCandidates.insert("火魔汰摩")
      for result in results {
        #expect(expectedCandidates.remove(result.value) != nil, "\(result.value)")
      }
    }
  }

  @Test func userHistoryPredictorPreprocessInput() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    do {
      // Commit can be triggered by space in alphanumeric keyboard layout.
      // In this case, trailing white space is included to the key and value.
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForSuggestion("android ", segmentsProxy)
      segmentsProxy.addCandidate(0, "android ")
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }

    do {
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForSuggestion("androi", segmentsProxy)
      let results = predictor.predict(convreq)
      #expect(!results.isEmpty)
      // Preprocessed value should be learned.
      #expect(UserHistoryPredictorTestFixture.findCandidateByValue("android", results) != nil)
      #expect(UserHistoryPredictorTestFixture.findCandidateByValue("android ", results) == nil)
    }
  }

  @Test func descriptionTest() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    // Release build behavior (no " History" debug suffix).
    let kDescription = "テスト"

    var results: [PredictionResult] = []

    do {
      let predictor = f.getUserHistoryPredictor()
      await predictor.wait()

      // Insert two items
      do {
        let segmentsProxy = SegmentsProxy()
        let convreq = f.setUpInputForConversion("わたしのなまえはなかのです", segmentsProxy)
        segmentsProxy.addCandidateWithDescription(0, "私の名前は中野です", kDescription)
        predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)

        let convreq1 = f.setUpInputForSuggestion("わたしの", segmentsProxy)
        results = predictor.predict(convreq1)
        #expect(!results.isEmpty)
        #expect(results.first?.value == "私の名前は中野です")
        #expect(results.first?.description == kDescription)

        segmentsProxy.clear()
        let convreq2 = f.setUpInputForPrediction("わたしの", segmentsProxy)
        results = predictor.predict(convreq2)
        #expect(!results.isEmpty)
        #expect(results.first?.value == "私の名前は中野です")
        #expect(results.first?.description == kDescription)
      }

      // sync
      predictor.sync()
      await predictor.wait()
    }

    // reload
    do {
      let predictor = f.getUserHistoryPredictor()
      await predictor.wait()
      let segmentsProxy = SegmentsProxy()

      // turn off
      do {
        let segmentsProxy = SegmentsProxy()
        f.config.useHistorySuggest = false
        await predictor.wait()

        let convreq1 = f.setUpInputForSuggestion("わたしの", segmentsProxy)
        results = predictor.predict(convreq1)
        #expect(results.isEmpty)

        f.config.useHistorySuggest = true
        f.config.incognitoMode = true

        let convreq2 = f.setUpInputForSuggestion("わたしの", segmentsProxy)
        results = predictor.predict(convreq2)
        #expect(results.isEmpty)
      }

      // turn on
      do {
        f.config = ConfigHandler.defaultConfig()
        await predictor.wait()
      }

      // reproduced
      let convreq1 = f.setUpInputForSuggestion("わたしの", segmentsProxy)
      results = predictor.predict(convreq1)
      #expect(!results.isEmpty)
      #expect(results.first?.value == "私の名前は中野です")
      #expect(results.first?.description == kDescription)

      segmentsProxy.clear()
      let convreq2 = f.setUpInputForPrediction("わたしの", segmentsProxy)
      results = predictor.predict(convreq2)
      #expect(!results.isEmpty)
      #expect(results.first?.value == "私の名前は中野です")
      #expect(results.first?.description == kDescription)

      // Exact Match
      segmentsProxy.clear()
      let convreq3 = f.setUpInputForSuggestion("わたしのなまえはなかのです", segmentsProxy)
      results = predictor.predict(convreq3)
      #expect(!results.isEmpty)
      #expect(results.first?.value == "私の名前は中野です")
      #expect(results.first?.description == kDescription)

      segmentsProxy.clear()
      let convreq4 = f.setUpInputForSuggestion("わたしのなまえはなかのです", segmentsProxy)
      results = predictor.predict(convreq4)
      #expect(!results.isEmpty)
      #expect(results.first?.value == "私の名前は中野です")
      #expect(results.first?.description == kDescription)

      // clear
      predictor.clearAllHistory()
    }

    // nothing happen
    for _ in 0..<2 {
      let predictor = f.getUserHistoryPredictor()
      await predictor.wait()
      let segmentsProxy = SegmentsProxy()

      // reproduced
      let convreq1 = f.setUpInputForSuggestion("わたしの", segmentsProxy)
      results = predictor.predict(convreq1)
      #expect(results.isEmpty)

      let convreq2 = f.setUpInputForPrediction("わたしの", segmentsProxy)
      results = predictor.predict(convreq2)
      #expect(results.isEmpty)
    }
  }
}
