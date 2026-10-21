// Port of mozc/src/prediction/predictor_test.cc (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private final class CheckCandSizeDictionaryPredictor: PredictorInterface, @unchecked Sendable {
  private let expectedCandSize: Int

  init(_ expectedCandSize: Int) { self.expectedCandSize = expectedCandSize }

  func predict(_ request: ConversionRequest) -> [PredictionResult] {
    #expect(request.options().maxDictionaryPredictionCandidatesSize == expectedCandSize)
    return PT.results(1)
  }

  func getPredictorName() -> String { "CheckCandSizeDictionaryPredictor" }
}

private final class CheckCandSizeUserHistoryPredictor: PredictorInterface, @unchecked Sendable {
  private let expectedCandSize: Int
  private let expectedCandSizeForZeroQuery: Int

  init(_ expectedCandSize: Int, _ expectedCandSizeForZeroQuery: Int) {
    self.expectedCandSize = expectedCandSize
    self.expectedCandSizeForZeroQuery = expectedCandSizeForZeroQuery
  }

  func predict(_ request: ConversionRequest) -> [PredictionResult] {
    #expect(request.options().maxUserHistoryPredictionCandidatesSize == expectedCandSize)
    #expect(
      request.options().maxUserHistoryPredictionCandidatesSizeForZeroQuery
        == expectedCandSizeForZeroQuery)
    return PT.results(1)
  }

  func getPredictorName() -> String { "CheckCandSizeUserHistoryPredictor" }
}

private final class NullPredictor: PredictorInterface, @unchecked Sendable {
  private let returnValue: Bool
  private(set) var predictCalled = false

  init(_ ret: Bool) { returnValue = ret }

  func predict(_ request: ConversionRequest) -> [PredictionResult] {
    predictCalled = true
    return PT.results(returnValue ? 1 : 0)
  }

  func clear() { predictCalled = false }

  func getPredictorName() -> String { "NullPredictor" }
}

private final class MockPredictor: PredictorInterface, @unchecked Sendable {
  var predictHandler: ((ConversionRequest) -> [PredictionResult])?
  var convertHandler: ((ConversionRequest) -> [PredictionResult])?
  private(set) var predictCount = 0
  private(set) var convertCount = 0

  func predict(_ request: ConversionRequest) -> [PredictionResult] {
    predictCount += 1
    return predictHandler?(request) ?? []
  }

  func convert(_ request: ConversionRequest) -> [PredictionResult] {
    convertCount += 1
    return convertHandler?(request) ?? []
  }

  func getPredictorName() -> String { "MockPredictor" }
}

private func addCandidate(
  _ key: String, _ value: String, _ lid: UInt16, _ rid: UInt16, _ cost: Int,
  _ results: inout [PredictionResult]
) {
  var result = PredictionResult()
  result.key = key
  result.value = value
  result.lid = lid
  result.rid = rid
  result.cost = cost
  result.wcost = cost
  results.append(result)
}

@Suite(.enabled(if: predictionMockDataAvailable, "mock_genmai.data is missing"))
struct MixedDecodingPredictorTests {
  var config = PT.config()
  var request: Genmai_Commands_Request
  var composer: Composer
  let modules: PredictionTestModules
  var context = Genmai_Commands_Context()

  init() throws {
    var request = Genmai_Commands_Request()
    RequestTestUtil.fillMobileRequest(&request)
    self.request = request
    composer = Composer(request, config)
    modules = try PredictionTestModules.mock(dictionary: MockDictionary())
  }

  func createConversionRequest(_ requestType: RequestType) -> ConversionRequest {
    var options = ConversionOptions()
    options.requestType = requestType
    return ConversionRequestBuilder()
      .setComposer(composer)
      .setRequestView(request)
      .setContextView(context)
      .setConfigView(config)
      .setOptions(options)
      .build()
  }

  @Test func callPredictorsForMobileSuggestion() {
    let predictor = Predictor(
      modules, CheckCandSizeDictionaryPredictor(200), CheckCandSizeUserHistoryPredictor(3, 4))
    #expect(!predictor.predict(createConversionRequest(.suggestion)).isEmpty)
  }

  @Test func callPredictorsForMobilePartialSuggestion() {
    let predictor = Predictor(
      modules, CheckCandSizeDictionaryPredictor(200),
      // We don't call history predictor
      CheckCandSizeUserHistoryPredictor(-1, -1))
    #expect(!predictor.predict(createConversionRequest(.partialSuggestion)).isEmpty)
  }

  @Test func callPredictorsForMobilePrediction() {
    let predictor = Predictor(
      modules, CheckCandSizeDictionaryPredictor(200), CheckCandSizeUserHistoryPredictor(3, 4))
    #expect(!predictor.predict(createConversionRequest(.prediction)).isEmpty)
  }

  @Test func callPredictorsForMobilePartialPrediction() {
    let predictor = Predictor(
      modules, CheckCandSizeDictionaryPredictor(200), CheckCandSizeUserHistoryPredictor(3, 4))
    #expect(!predictor.predict(createConversionRequest(.partialPrediction)).isEmpty)
  }

  @Test func callPredictForRequestMobile() {
    let predictor1 = MockPredictor()
    let predictor2 = MockPredictor()
    let results = PT.results(2)
    predictor1.predictHandler = { _ in results }
    predictor2.predictHandler = { _ in results }

    let predictor = Predictor(modules, predictor1, predictor2)
    #expect(!predictor.predict(createConversionRequest(.suggestion)).isEmpty)
    #expect(predictor1.predictCount <= 1)
    #expect(predictor2.predictCount <= 1)
  }

  @Test func fillPos() {
    let mockDictionaryPredictor = MockPredictor()
    let mockHistoryPredictor = MockPredictor()

    var predictorResults: [PredictionResult] = []
    let historyResults: [PredictionResult] = []
    addCandidate("key", "value", 0, 0, 1, &predictorResults)
    addCandidate("key", "value", 2, 3, 100, &predictorResults)
    mockHistoryPredictor.predictHandler = { _ in historyResults }
    mockDictionaryPredictor.predictHandler = { _ in predictorResults }

    let predictor = Predictor(modules, mockDictionaryPredictor, mockHistoryPredictor)

    let results = predictor.predict(createConversionRequest(.suggestion))

    #expect(results.count == 2)
    let result = results[0]
    #expect(result.key == "key")
    #expect(result.value == "value")
    // lid and rid are filled from another result.
    #expect(result.lid == 2)
    #expect(result.rid == 3)
    // cost is not changed.
    #expect(result.cost == 1)
  }

  @Test func mixCandidates() {
    func predict(_ predictorResults: [PredictionResult], _ historyResults: [PredictionResult])
      -> [PredictionResult]
    {
      let mockDictionaryPredictor = MockPredictor()
      let mockHistoryPredictor = MockPredictor()
      mockHistoryPredictor.predictHandler = { _ in historyResults }
      mockDictionaryPredictor.predictHandler = { _ in predictorResults }

      let predictor = Predictor(modules, mockDictionaryPredictor, mockHistoryPredictor)
      return predictor.predict(createConversionRequest(.suggestion))
    }

    func isTopNoDeletable(
      _ predictorResults: [PredictionResult], _ historyResults: [PredictionResult]
    ) -> Bool {
      let expectedSize = predictorResults.count + historyResults.count
      let results = predict(predictorResults, historyResults)
      #expect(results.count == expectedSize)
      return (results[0].attributes & Attribute.noDeletable) != 0
    }

    do {
      var predictorResults = PT.results(3)
      var historyResults = PT.results(1)
      predictorResults[0].key = "key"
      historyResults[0].key = "key"
      predictorResults[0].value = "value"
      historyResults[0].value = "value"
      #expect(isTopNoDeletable(predictorResults, historyResults))
    }

    do {
      var predictorResults = PT.results(3)
      var historyResults = PT.results(1)
      predictorResults[0].key = "key"
      historyResults[0].key = "key"
      // different value.
      predictorResults[0].value = "value1"
      historyResults[0].value = "value2"
      #expect(!isTopNoDeletable(predictorResults, historyResults))
    }

    do {
      // history size is > 1.
      var predictorResults = PT.results(3)
      var historyResults = PT.results(2)
      predictorResults[0].key = "key"
      historyResults[0].key = "key"
      predictorResults[0].value = "value"
      historyResults[0].value = "value"
      #expect(!isTopNoDeletable(predictorResults, historyResults))
    }

    do {
      // history top has WEAK_USER_HISTORY_PREDICTION attribute.
      var predictorResults = PT.results(1)
      var historyResults = PT.results(1)
      predictorResults[0].value = "dic_value"
      historyResults[0].value = "history_value"
      historyResults[0].attributes |= Attribute.weakUserHistoryPrediction
      let mixedResults = predict(predictorResults, historyResults)

      // swapped.
      #expect(mixedResults[0].value == "dic_value")
      #expect(mixedResults[1].value == "history_value")
    }
  }

  @Test func demoteWeakUserHistoryTest() {
    let convreq = createConversionRequest(.suggestion)
    // sets WEAK_USER_HISTORY_PREDICTION attributes to
    // the results[index], and call DemoteWeakUserHistory.
    func demote(_ index: [Int]) -> String {
      var results = PT.results(5)
      for i in 0..<results.count {
        results[i].value = String(i)
      }
      for i in index {
        results[i].attributes |= Attribute.weakUserHistoryPrediction
      }
      Predictor.demoteWeakUserHistory(convreq, &results)
      return results.map(\.value).joined(separator: ",")
    }

    #expect(demote([]) == "0,1,2,3,4")
    #expect(demote([0]) == "1,0,2,3,4")
    #expect(demote([0, 1]) == "2,0,1,3,4")
    #expect(demote([0, 1, 2]) == "3,0,1,2,4")
    #expect(demote([0, 1, 2, 3]) == "4,0,1,2,3")
    #expect(demote([0, 2]) == "1,0,2,3,4")
    #expect(demote([0, 2, 3]) == "1,0,2,3,4")
    #expect(demote([0, 3]) == "1,0,2,3,4")
    #expect(demote([1]) == "0,1,2,3,4")
    #expect(demote([1, 2]) == "0,1,2,3,4")
    #expect(demote([1, 2, 3]) == "0,1,2,3,4")
  }

  @Test mutating func mixCandidatesWithWeakUserHistoryTest() throws {
    let predictor = Predictor(modules, NullPredictor(true), NullPredictor(true))
    // Case 1: Top history candidate is Non-weak ("今日は"), second is Weak
    // ("今日は言った"). Position 0 is already protected by "今日は", so
    // "今日は言った" remains at position 1 ahead of dictionary homophones.
    do {
      composer.setPreeditTextForTestOnly("きょうは")
      let convreq = createConversionRequest(.suggestion)

      var historyResults = PT.results(2)
      historyResults[0].key = "きょうは"
      historyResults[0].value = "今日は"
      historyResults[0].attributes |= Attribute.userHistoryPrediction

      historyResults[1].key = "きょうはいった"
      historyResults[1].value = "今日は言った"
      historyResults[1].attributes |=
        (Attribute.userHistoryPrediction | Attribute.weakUserHistoryPrediction)

      var dictionaryResults = PT.results(2)
      dictionaryResults[0].key = "きょうは"
      dictionaryResults[0].value = "教は"
      dictionaryResults[1].key = "きょうは"
      dictionaryResults[1].value = "京は"

      let results = predictor.mixCandidates(convreq, historyResults, dictionaryResults)

      try #require(results.count == 4)
      #expect(results[0].value == "今日は")
      #expect(results[1].value == "今日は言った")
      #expect(results[2].value == "教は")
      #expect(results[3].value == "京は")
    }

    // Case 2: Top history candidate is Weak ("今日は駅に行った"). Only the
    // first non-weak candidate ("今日は駅に") is promoted to position 0,
    // preserving "今日は駅に行った" at position 1 ahead of other dictionary
    // homophones.
    do {
      composer.setPreeditTextForTestOnly("きょうはえきに")
      let convreq = createConversionRequest(.suggestion)

      var historyResults = PT.results(1)
      historyResults[0].key = "きょうはえきにいった"
      historyResults[0].value = "今日は駅に行った"
      historyResults[0].attributes |=
        (Attribute.userHistoryPrediction | Attribute.weakUserHistoryPrediction)

      var dictionaryResults = PT.results(2)
      dictionaryResults[0].key = "きょうはえきに"
      dictionaryResults[0].value = "今日は駅に"
      dictionaryResults[1].key = "きょうはえきに"
      dictionaryResults[1].value = "今日は液に"

      let results = predictor.mixCandidates(convreq, historyResults, dictionaryResults)

      try #require(results.count == 3)
      #expect(results[0].value == "今日は駅に")
      #expect(results[1].value == "今日は駅に行った")
      #expect(results[2].value == "今日は液に")
    }
  }

  @Test mutating func mixCandidatesFiltersStandaloneWeekdayFromUserHistory() throws {
    let predictor = Predictor(modules, NullPredictor(true), NullPredictor(true))

    request.decoderExperimentParams.enableWeekdayZeroQueryPrediction = true
    composer.reset()
    context.precedingText = "9/16 (水)"
    let convreq = createConversionRequest(.prediction)
    try #require(convreq.isZeroQuerySuggestion())

    var historyResults = PT.results(2)
    historyResults[0].key = "すい"
    historyResults[0].value = " (水)"
    historyResults[0].attributes |= Attribute.userHistoryPrediction
    historyResults[1].key = "の"
    historyResults[1].value = "の"
    historyResults[1].attributes |= Attribute.userHistoryPrediction

    var dictionaryResults = PT.results(2)
    dictionaryResults[0].key = "すい"
    dictionaryResults[0].value = " (水)"
    dictionaryResults[1].key = "に"
    dictionaryResults[1].value = "に"

    let results = predictor.mixCandidates(convreq, historyResults, dictionaryResults)

    try #require(results.count == 2)
    #expect(results[0].value == "の")
    #expect(results[1].value == "に")
  }
}

@Suite(.enabled(if: predictionMockDataAvailable, "mock_genmai.data is missing"))
struct PredictorTests {
  var config = PT.config()
  let request = Genmai_Commands_Request()
  let composer: Composer
  let modules: PredictionTestModules
  let context = Genmai_Commands_Context()
  let historyResult = PredictionResult()

  init() throws {
    composer = Composer(request, config)
    modules = try PredictionTestModules.mock(dictionary: MockDictionary())
  }

  func createConversionRequest(_ requestType: RequestType) -> ConversionRequest {
    var options = ConversionOptions()
    options.requestType = requestType
    return ConversionRequestBuilder()
      .setComposer(composer)
      .setRequestView(request)
      .setContextView(context)
      .setConfigView(config)
      .setHistoryResultView(historyResult)
      .setOptions(options)
      .build()
  }

  @Test func allPredictorsReturnTrue() {
    _ = Predictor(modules, NullPredictor(true), NullPredictor(true))
    _ = createConversionRequest(.suggestion)
  }

  @Test func mixedReturnValue() {
    let predictor = Predictor(modules, NullPredictor(true), NullPredictor(false))
    #expect(!predictor.predict(createConversionRequest(.suggestion)).isEmpty)
  }

  @Test func allPredictorsReturnFalse() {
    let predictor = Predictor(modules, NullPredictor(false), NullPredictor(false))
    #expect(predictor.predict(createConversionRequest(.suggestion)).isEmpty)
  }

  @Test func callPredictorsForSuggestion() {
    var defaultConfig = Genmai_Config_Config()
    ConfigHandler.getDefaultConfig(&defaultConfig)
    let suggestionsSize = Int(defaultConfig.suggestionsSize)
    let predictor = Predictor(
      modules,
      // -1 as UserHistoryPredictor returns 1 result.
      CheckCandSizeDictionaryPredictor(suggestionsSize - 1),
      CheckCandSizeUserHistoryPredictor(suggestionsSize, suggestionsSize))
    #expect(!predictor.predict(createConversionRequest(.suggestion)).isEmpty)
  }

  @Test func callPredictorsForPrediction() {
    let kPredictionSize = 100
    let predictor = Predictor(
      modules,
      // -1 as UserHistoryPredictor returns 1 result.
      CheckCandSizeDictionaryPredictor(kPredictionSize - 1),
      CheckCandSizeUserHistoryPredictor(kPredictionSize, kPredictionSize))
    #expect(!predictor.predict(createConversionRequest(.prediction)).isEmpty)
  }

  @Test func callPredictForRequest() {
    let predictor1 = MockPredictor()
    let predictor2 = MockPredictor()
    let results = PT.results(1)
    predictor1.predictHandler = { _ in results }
    predictor2.predictHandler = { _ in results }

    let predictor = Predictor(modules, predictor1, predictor2)
    #expect(!predictor.predict(createConversionRequest(.suggestion)).isEmpty)
    #expect(predictor1.predictCount <= 1)
    #expect(predictor2.predictCount <= 1)
  }

  @Test mutating func disableAllSuggestion() {
    let pred1 = NullPredictor(true)  // Keep the reference
    let pred2 = NullPredictor(true)  // Keep the reference
    let predictor = Predictor(modules, pred1, pred2)
    config.presentationMode = true
    let convreq1 = createConversionRequest(.suggestion)

    #expect(predictor.predict(convreq1).isEmpty)
    #expect(!pred1.predictCalled)
    #expect(!pred2.predictCalled)

    config.presentationMode = false
    let convreq2 = createConversionRequest(.suggestion)
    #expect(!predictor.predict(convreq2).isEmpty)
    #expect(pred1.predictCalled)
    #expect(pred2.predictCalled)
  }

  @Test func convertNotConvertRequest() {
    let predictor1 = MockPredictor()
    let predictor2 = MockPredictor()

    let predictor = Predictor(modules, predictor1, predictor2)
    #expect(predictor.convert(createConversionRequest(.suggestion)).isEmpty)
    #expect(predictor1.convertCount == 0)
    #expect(predictor2.convertCount == 0)
  }

  @Test func convertConvertRequest() throws {
    let predictor1 = MockPredictor()
    let predictor2 = MockPredictor()

    var expectedResults = PT.results(1)
    expectedResults[0].value = "conversion_result"
    predictor2.convertHandler = { _ in expectedResults }

    let predictor = Predictor(modules, predictor1, predictor2)
    let results = predictor.convert(createConversionRequest(.conversion))
    #expect(predictor1.convertCount == 0)
    #expect(predictor2.convertCount == 1)
    try #require(results.count == 1)
    #expect(results[0].value == "conversion_result")
  }
}
