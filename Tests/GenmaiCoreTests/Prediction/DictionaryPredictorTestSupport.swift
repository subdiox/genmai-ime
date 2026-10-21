// Test fixture of mozc/src/prediction/dictionary_predictor_test.cc
// (3.35.6354): MockAggregator, MockDataAndPredictor, the CreateResult*
// helpers and the DictionaryPredictorTest fixture.

import Foundation
import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

/// `MockAggregator`: DictionaryPredictor whose aggregation is mocked.
final class DPMockAggregator: DictionaryPredictor, @unchecked Sendable {
  var aggregateResultsForDesktopHandler: ((ConversionRequest) -> [PredictionResult])?
  var aggregateResultsForMixedConversionHandler: ((ConversionRequest) -> [PredictionResult])?

  override func aggregateResultsForDesktop(_ request: ConversionRequest) -> [PredictionResult] {
    aggregateResultsForDesktopHandler?(request) ?? []
  }

  override func aggregateResultsForMixedConversion(_ request: ConversionRequest)
    -> [PredictionResult]
  {
    aggregateResultsForMixedConversionHandler?(request) ?? []
  }
}

/// Helper class to hold dictionary data and predictor objects.
final class MockDataAndPredictor {
  private(set) var mockAggregator: DPMockAggregator?
  private(set) var mockDecoder: PredictionMockRealtimeDecoder
  private(set) var modules: PredictionTestModules
  private(set) var dictionary: KeyedMockDictionary?
  private(set) var singleKanjiDictionary: PredictionMockSingleKanjiDictionary?
  private(set) var predictor: DictionaryPredictor

  init(_ supplementalModel: (any PredictionSupplementalModel)? = nil) throws {
    mockDecoder = PredictionMockRealtimeDecoder()
    modules = try PredictionTestModules.mock(supplementalModel: supplementalModel)
    let aggregator = DPMockAggregator(modules, mockDecoder)
    mockAggregator = aggregator
    predictor = aggregator
  }

  /// Initializes predictor with the given suffix_dictionary and
  /// supplemental_model using the real aggregation pipeline.
  func initialize(
    _ suffixDictionary: (any DictionaryInterface)? = nil,
    _ supplementalModel: (any PredictionSupplementalModel)? = nil
  ) throws {
    let dictionary = KeyedMockDictionary()
    self.dictionary = dictionary
    let singleKanjiDictionary = PredictionMockSingleKanjiDictionary()
    self.singleKanjiDictionary = singleKanjiDictionary
    mockDecoder = PredictionMockRealtimeDecoder()
    modules = try PredictionTestModules.mock(
      dictionary: dictionary.mock, suffixDictionary: suffixDictionary,
      singleKanjiDictionary: singleKanjiDictionary, supplementalModel: supplementalModel)
    mockAggregator = nil
    predictor = DictionaryPredictor(modules, mockDecoder)
  }

  var aggregator: DPMockAggregator { mockAggregator! }
  var mockDictionary: KeyedMockDictionary { dictionary! }
  var connector: Connector { modules.getConnector() }
  var posMatcher: PosMatcher { modules.getPosMatcher() }

  // DictionaryPredictorTestPeer
  func aggregateResultsForTesting(_ request: ConversionRequest) -> [PredictionResult] {
    request.request().mixedConversion
      ? predictor.aggregateResultsForMixedConversion(request)
      : predictor.aggregateResultsForDesktop(request)
  }

  func aggregateBigram(_ request: ConversionRequest, _ results: inout [PredictionResult]) {
    predictor.dictionaryDecoder.aggregateBigram(request, &results)
  }

  func aggregateZeroQuery(_ request: ConversionRequest, _ results: inout [PredictionResult]) {
    results.append(contentsOf: predictor.zeroQueryDecoder.decode(request))
  }

  func aggregateEnglish(_ request: ConversionRequest, _ results: inout [PredictionResult]) {
    results.append(contentsOf: predictor.englishDecoder.decode(request))
  }
}

enum DPT {
  static func createResult4(
    _ key: String, _ value: String, _ types: PredictionTypes,
    _ tokenAttrs: Token.AttributesBitfield
  ) -> PredictionResult {
    var result = PredictionResult()
    result.key = key
    result.value = value
    result.setTypesAndTokenAttributes(types, tokenAttrs)
    return result
  }

  static func createResult5(
    _ key: String, _ value: String, _ wcost: Int, _ types: PredictionTypes,
    _ tokenAttrs: Token.AttributesBitfield
  ) -> PredictionResult {
    var result = createResult4(key, value, types, tokenAttrs)
    result.wcost = wcost
    return result
  }

  static func createResult6(
    _ key: String, _ value: String, _ wcost: Int, _ cost: Int, _ types: PredictionTypes,
    _ tokenAttrs: Token.AttributesBitfield
  ) -> PredictionResult {
    var result = createResult5(key, value, wcost, types, tokenAttrs)
    result.cost = cost
    return result
  }

  static func pushBackInnerSegmentBoundary(
    _ keyLen: Int, _ valueLen: Int, _ contentKeyLen: Int, _ contentValueLen: Int,
    _ result: inout PredictionResult
  ) {
    result.innerSegmentBoundary.append(
      encodeLengths(keyLen, valueLen, contentKeyLen, contentValueLen)!)
  }

  static func findCandidateByKeyValue(
    _ results: [PredictionResult], _ key: String, _ value: String
  ) -> Bool {
    results.contains { $0.key.bytesEqual(key) && $0.value.bytesEqual(value) && !$0.removed }
  }

  static func findCandidateByValue(_ results: [PredictionResult], _ value: String) -> Bool {
    results.contains { $0.value.bytesEqual(value) && !$0.removed }
  }

  static func getMergedTypes(_ results: [PredictionResult]) -> PredictionTypes {
    var merged: PredictionTypes = 0
    for result in results {
      merged |= result.getPredictionTypesForTesting()
    }
    return merged
  }

  static func addDefaultPredictionTypes(_ types: PredictionTypes, _ isMobile: Bool)
    -> PredictionTypes
  {
    if !isMobile {
      return types
    }
    return types | Attribute.realtimeConversion | Attribute.partiallyKeyConsumed
  }

  static func rank(_ results: [PredictionResult], _ value: String) -> Int {
    results.firstIndex { $0.value.bytesEqual(value) } ?? -1
  }

  static func addWordsToMockDic(_ dict: KeyedMockDictionary) {
    let p = dict.predictive
    let x = dict.prefix
    p.on(
      "ぐーぐるあ",
      kv: [
        ("ぐーぐるあどせんす", "グーグルアドセンス"),
        ("ぐーぐるあどわーず", "グーグルアドワーズ"),
      ])
    p.on(
      "ぐーぐる",
      kv: [
        ("ぐーぐるあどせんす", "グーグルアドセンス"),
        ("ぐーぐるあどわーず", "グーグルアドワーズ"),
      ])
    x.on("ぐーぐる", kv: [("ぐーぐる", "グーグル")])
    x.on("ぐーぐ", kv: [("ぐー", "グー")])
    x.on("あどせんす", kv: [("あどせんす", "アドセンス")])
    x.on("てすと", kv: [("てすと", "テスト")])
    p.on("てす", kv: [("てすと", "テスト")])
    p.on("てすとだ", kv: [("てすとだよ", "テストだよ")])
    x.on("て", kv: [("て", "テスト")])
    // Bigram entry of "これは|テストだよ”
    p.on("これはてすとだ", kv: [("これはてすとだよ", "これはテストだよ")])
    // Previous context must exist in the dictionary when bigram is triggered.
    x.on("これは", kv: [("これは", "これは")])
    p.on("てすとだよてす", kv: [("てすとだよてすと", "テストだよテスト")])
    x.on("てすとだよ", kv: [("てすとだよ", "テストだよ")])

    // SpellingCorrection entry
    p.on(
      "かぷりちょうざ", kv: [("かぷりちょーざ", "カプリチョーザ")], Token.Attribute.spellingCorrection)

    // user dictionary entry
    p.on("ゆーざー", kv: [("ゆーざー", "ユーザー")], Token.Attribute.userDictionary)

    // Some English entries
    p.on(
      "conv",
      kv: [
        ("converge", "converge"),
        ("converged", "converged"),
        ("convergent", "convergent"),
      ])
    p.on("con", kv: [("contraction", "contraction"), ("control", "control")])
    p.on("hel", kv: [("hello", "hello")])
    // Prefix lookup doesn't allow the prefix match, e.g. "he" -> "h" by
    // default, so add Hiragana values to let prefix-lookup return
    // some results.
    x.on("he", kv: [("はろー", "はろー")])
  }

  static func addDefaultImplToMockRealtimeDecoder(_ mock: PredictionMockRealtimeDecoder) {
    mock.decodeHandler = PredictionMockRealtimeDecoder.decodeImpl
    mock.reverseDecodeHandler = PredictionMockRealtimeDecoder.decodeImpl
  }

  static func createPredictorWithMockData(
    _ suffixDictionary: (any DictionaryInterface)? = nil,
    _ supplementalModel: (any PredictionSupplementalModel)? = nil
  ) throws -> MockDataAndPredictor {
    let ret = try MockDataAndPredictor()
    try ret.initialize(suffixDictionary, supplementalModel)
    addWordsToMockDic(ret.mockDictionary)
    addDefaultImplToMockRealtimeDecoder(ret.mockDecoder)
    return ret
  }
}

/// The DictionaryPredictorTest fixture (request / config / composer /
/// context / history result and the request builders).
struct DPFixture {
  var request = Genmai_Commands_Request()
  var config = PT.config()
  let table = Table()
  var composer: Composer
  var context = Genmai_Commands_Context()
  var historyResult = PredictionResult()

  init() {
    composer = Composer(table, request, config)
  }

  mutating func prependHistory(_ key: String, _ value: String) {
    historyResult.value = value + historyResult.value
    historyResult.key = key + historyResult.key
  }

  mutating func initHistory(_ key: String, _ value: String, _ rid: UInt16 = 1) {
    historyResult.key = key
    historyResult.value = value
    historyResult.rid = rid
  }

  mutating func createConversionRequestWithOptions(
    _ options: ConversionOptions, _ key: String = "", _ initComposer: Bool = false
  ) -> ConversionRequest {
    if initComposer {
      composer.reset()
      composer.setPreeditTextForTestOnly(key)
    }
    return ConversionRequestBuilder()
      .setComposer(composer)
      .setRequestView(request)
      .setContextView(context)
      .setConfigView(config)
      .setOptions(options)
      .setHistoryResultView(historyResult)
      .setKey(key)
      .build()
  }

  mutating func createConversionRequest(
    _ options: ConversionOptions, _ key: String = "", _ initComposer: Bool = true
  ) -> ConversionRequest {
    createConversionRequestWithOptions(options, key, initComposer)
  }

  mutating func createConversionRequest(_ requestType: RequestType, _ key: String = "")
    -> ConversionRequest
  {
    var options = ConversionOptions()
    options.requestType = requestType
    return createConversionRequestWithOptions(options, key)
  }

  mutating func createSuggestionConversionRequest(_ key: String, _ initComposer: Bool = true)
    -> ConversionRequest
  {
    var options = ConversionOptions()
    options.requestType = .suggestion
    return createConversionRequest(options, key, initComposer)
  }

  mutating func createPredictionConversionRequest(_ key: String, _ initComposer: Bool = true)
    -> ConversionRequest
  {
    var options = ConversionOptions()
    options.requestType = .prediction
    return createConversionRequest(options, key, initComposer)
  }

  static func options(
    _ requestType: RequestType, maxDictionaryPredictionCandidatesSize: Int? = nil,
    useActualConverterForRealtimeConversion: Bool? = nil
  ) -> ConversionOptions {
    var options = ConversionOptions()
    options.requestType = requestType
    if let maxDictionaryPredictionCandidatesSize {
      options.maxDictionaryPredictionCandidatesSize = maxDictionaryPredictionCandidatesSize
    }
    if let useActualConverterForRealtimeConversion {
      options.useActualConverterForRealtimeConversion = useActualConverterForRealtimeConversion
    }
    return options
  }

  static func compositionEvents(_ events: [(String, Double)])
    -> [Genmai_Commands_SessionCommand.CompositionEvent]
  {
    events.map { s, p in
      var e = Genmai_Commands_SessionCommand.CompositionEvent()
      e.compositionString = s
      e.probability = p
      return e
    }
  }
}
