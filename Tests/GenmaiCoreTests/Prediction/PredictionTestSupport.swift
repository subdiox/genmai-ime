// Test support for the prediction tests: engine::Modules / ModulesPresetBuilder
// (mozc/src/engine/modules.cc) as far as the prediction code needs them, the
// gmock helpers InvokeCallbackWithKeyValues / InvokeCallbackWithTokens, and
// test doubles (MockRealtimeDecoder, MockSingleKanjiDictionary,
// MockSupplementalModel).

import Foundation
import GenmaiBase
import GenmaiProtocol
import GenmaiStorage
import Testing

@testable import GenmaiCore

/// engine::Modules built by ModulesPresetBuilder().Preset*(...).Build(data).
final class PredictionTestModules: PredictionModules, UserHistoryPredictorModules,
  @unchecked Sendable
{
  let dataManager: DataManager
  let posMatcher: PosMatcher
  let userDictionary: any UserDictionaryInterface
  let dictionary: any DictionaryInterface
  let suffixDictionary: any DictionaryInterface
  let connector: Connector
  let segmenter: Segmenter
  let suggestionFilter: SuggestionFilter
  let singleKanjiDictionary: SingleKanjiDictionary
  let zeroQueryDict: ZeroQueryDict
  let zeroQueryNumberDict: ZeroQueryDict
  var supplementalModel: any PredictionSupplementalModel
  private var userHistoryStorage: UserHistoryStorage?

  init(
    _ dataManager: DataManager, dictionary: (any DictionaryInterface)? = nil,
    suffixDictionary: (any DictionaryInterface)? = nil,
    singleKanjiDictionary: SingleKanjiDictionary? = nil,
    supplementalModel: (any PredictionSupplementalModel)? = nil
  ) throws {
    self.dataManager = dataManager
    let posMatcher = PosMatcher(dataManager.getPosMatcherData())
    self.posMatcher = posMatcher
    let userPosData = dataManager.getUserPosData()
    let userDictionary = UserDictionary(
      UserPos(userPosData.tokenArray, userPosData.stringArray), posMatcher)
    self.userDictionary = userDictionary
    if let dictionary {
      self.dictionary = dictionary
    } else {
      let sysdic = try SystemDictionary.Builder(image: dataManager.getSystemDictionaryData()).build()
      let valueDic = ValueDictionary(posMatcher, sysdic.valueTrie)
      self.dictionary = DictionaryImpl(sysdic, valueDic, userDictionary, posMatcher)
    }
    if let suffixDictionary {
      self.suffixDictionary = suffixDictionary
    } else {
      let d = dataManager.getSuffixDictionaryData()
      self.suffixDictionary = SuffixDictionary(d.keyArray, d.valueArray, d.tokenArray)
    }
    connector = try Connector.create(dataManager.getConnectorData())
    segmenter = Segmenter(dataManager: dataManager)
    suggestionFilter = try SuggestionFilter.create(dataManager.getSuggestionFilterData())
    self.singleKanjiDictionary =
      singleKanjiDictionary ?? SingleKanjiDictionary(dataManager.getSingleKanjiRewriterData())
    let zq = dataManager.getZeroQueryData()
    zeroQueryDict = ZeroQueryDict(zq.tokenArray, zq.stringArray)
    zeroQueryNumberDict = ZeroQueryDict(zq.numberTokenArray, zq.numberStringArray)
    self.supplementalModel = supplementalModel ?? PredictionSupplementalModelStub()
  }

  static func mock(
    dictionary: (any DictionaryInterface)? = nil,
    suffixDictionary: (any DictionaryInterface)? = nil,
    singleKanjiDictionary: SingleKanjiDictionary? = nil,
    supplementalModel: (any PredictionSupplementalModel)? = nil
  ) throws -> PredictionTestModules {
    try PredictionTestModules(
      MockDataManager(), dictionary: dictionary, suffixDictionary: suffixDictionary,
      singleKanjiDictionary: singleKanjiDictionary, supplementalModel: supplementalModel)
  }

  /// nil when Data/genmai.data is missing.
  static func oss() throws -> PredictionTestModules? {
    guard FileManager.default.fileExists(atPath: OssDataManager.defaultDataPath) else { return nil }
    return try PredictionTestModules(OssDataManager())
  }

  // ConverterModules
  func getPosMatcher() -> PosMatcher { posMatcher }
  func getUserDictionary() -> any UserDictionaryInterface { userDictionary }
  func getSupplementalModel() -> any ConverterSupplementalModel { supplementalModel }

  // PredictionModules
  func getDataManager() -> DataManager { dataManager }
  func getConnector() -> Connector { connector }
  func getSegmenter() -> Segmenter { segmenter }
  func getDictionary() -> any DictionaryInterface { dictionary }
  func getSuffixDictionary() -> any DictionaryInterface { suffixDictionary }
  func getSuggestionFilter() -> SuggestionFilter { suggestionFilter }
  func getSingleKanjiDictionary() -> SingleKanjiDictionary { singleKanjiDictionary }
  func getZeroQueryDict() -> ZeroQueryDict { zeroQueryDict }
  func getZeroQueryNumberDict() -> ZeroQueryDict { zeroQueryNumberDict }

  // UserHistoryPredictorModules
  func getUserHistoryStorage() -> UserHistoryStorage {
    if let userHistoryStorage { return userHistoryStorage }
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("prediction_test_\(UUID().uuidString).db").path
    let storage = UserHistoryStorage(path)
    userHistoryStorage = storage
    return storage
  }
  func getUserHistorySupplementalModel() -> any UserHistorySupplementalModel { supplementalModel }
}

enum PredictionTestPaths {
  /// Repository root, located from this file.
  static let repoRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()

  static let oracleDir = repoRoot.appendingPathComponent("Tests/Fixtures/oracle")
}

// MARK: - Dictionary callback helpers

enum PT {

  /// `InvokeCallbackWithKeyValues`.
  static func invokeCallbackWithKeyValues(
    _ kvList: [(String, String)], _ tokenAttribute: Token.AttributesBitfield = Token.Attribute.none,
    _ callback: any DictionaryCallback
  ) {
    for (key, value) in kvList {
      if callback.onKey(key) != .traverseContinue
        || callback.onActualKey(key, key, 0) != .traverseContinue
      {
        return
      }
      var token = Token(key: key, value: value)
      token.cost = MockDictionary.kDefaultCost
      token.lid = UInt16(MockDictionary.kDefaultPosId)
      token.rid = UInt16(MockDictionary.kDefaultPosId)
      token.attributes = tokenAttribute
      if callback.onToken(key, key, token) != .traverseContinue {
        return
      }
    }
  }

  /// `InvokeCallbackWithTokens`.
  static func invokeCallbackWithTokens(_ tokens: [Token], _ callback: any DictionaryCallback) {
    for token in tokens {
      if callback.onKey(token.key) != .traverseContinue
        || callback.onActualKey(token.key, token.key, 0) != .traverseContinue
      {
        return
      }
      if callback.onToken(token.key, token.key, token) != .traverseContinue {
        return
      }
    }
  }

  static func makeToken(
    _ key: String, _ value: String, _ cost: Int, _ lid: Int, _ rid: Int,
    _ attributes: Token.AttributesBitfield
  ) -> Token {
    var token = Token(key: key, value: value)
    token.cost = cost
    token.lid = UInt16(lid)
    token.rid = UInt16(rid)
    token.attributes = attributes
    return token
  }

}

/// Per-key behavior of a MockDictionary method (gmock
/// `EXPECT_CALL(mock, Lookup*(StrEq(key), _, _)).WillRepeatedly(...)`).
/// Later registrations take precedence, as in gmock.
final class KeyedLookup: @unchecked Sendable {
  private var entries: [([UInt8], (any DictionaryCallback) -> Void)] = []
  private(set) var calledKeys: [String] = []
  /// Action for keys without a keyed entry (`Lookup*(_, _, _)`).
  var anyKey: ((String, any DictionaryCallback) -> Void)?

  /// `Mock::VerifyAndClearExpectations`.
  func clear() {
    entries.removeAll()
    anyKey = nil
  }

  func on(_ key: String, _ action: @escaping (any DictionaryCallback) -> Void) {
    entries.append((Array(key.utf8), action))
  }

  func on(
    _ key: String, kv: [(String, String)],
    _ attribute: Token.AttributesBitfield = Token.Attribute.none
  ) {
    on(key) { PT.invokeCallbackWithKeyValues(kv, attribute, $0) }
  }

  func on(_ key: String, tokens: [Token]) {
    on(key) { PT.invokeCallbackWithTokens(tokens, $0) }
  }

  var handler: (String, ConversionOptions, any DictionaryCallback) -> Void {
    { [self] key, _, callback in
      calledKeys.append(key)
      let k = Array(key.utf8)
      if let entry = entries.last(where: { $0.0 == k }) {
        entry.1(callback)
      } else {
        anyKey?(key, callback)
      }
    }
  }
}

/// A MockDictionary with keyed predictive / prefix / exact lookups.
final class KeyedMockDictionary {
  let mock = MockDictionary()
  let predictive = KeyedLookup()
  let prefix = KeyedLookup()
  let exact = KeyedLookup()

  init() {
    mock.lookupPredictiveHandler = predictive.handler
    mock.lookupPrefixHandler = prefix.handler
    mock.lookupExactHandler = exact.handler
  }
}

// MARK: - Test doubles

/// `MockRealtimeDecoder`: decode / reverseDecode / decodeSuffix can be
/// replaced by closures; the call counts are recorded.
final class PredictionMockRealtimeDecoder: RealtimeDecoder, @unchecked Sendable {
  var decodeHandler: ((ConversionRequest) -> [PredictionResult])?
  var reverseDecodeHandler: ((ConversionRequest) -> [PredictionResult])?
  private(set) var decodeCount = 0
  private(set) var reverseDecodeCount = 0

  override init() { super.init() }

  override init(
    _ immutableConverter: any ImmutableConverterInterface, _ converter: any ConverterInterface
  ) {
    super.init(immutableConverter, converter)
  }

  override func decode(_ request: ConversionRequest) -> [PredictionResult] {
    decodeCount += 1
    return decodeHandler?(request) ?? []
  }

  override func reverseDecode(_ request: ConversionRequest) -> [PredictionResult] {
    reverseDecodeCount += 1
    return reverseDecodeHandler?(request) ?? []
  }

  /// `MockRealtimeDecoder::DecodeImpl`.
  static func decodeImpl(_ request: ConversionRequest) -> [PredictionResult] {
    var result = PredictionResult()
    result.key = request.key()
    result.value = request.key()
    result.attributes = Attribute.realtimeConversion
    return [result]
  }
}

/// `MockSingleKanjiDictionary`.
final class PredictionMockSingleKanjiDictionary: SingleKanjiDictionary, @unchecked Sendable {
  var lookupKanjiEntriesHandler: ((String, Bool) -> [String])?

  override func lookupKanjiEntries(_ key: String, _ useSvs: Bool) -> [String] {
    lookupKanjiEntriesHandler?(key, useSvs) ?? []
  }
}

/// `engine::MockSupplementalModel`.
final class PredictionMockSupplementalModel: PredictionSupplementalModel, @unchecked Sendable {
  var isAvailableHandler: (() -> Bool)?
  var correctCompositionHandler: ((ConversionRequest) -> [TypeCorrectedQuery]?)?
  var populateTypeCorrectedQueryHandler: ((ConversionRequest, inout [PredictionResult]) -> Void)?
  var postCorrectHandler: ((ConversionRequest, inout [PredictionResult]) -> Void)?
  var rescoreResultsHandler: ((ConversionRequest, inout [PredictionResult]) -> Void)?
  var predictHandler: ((ConversionRequest, inout [PredictionResult]) -> Bool)?
  var decodeEnglishHandler: ((ConversionRequest, inout [PredictionResult]) -> Bool)?
  private(set) var calls: [String: Int] = [:]

  private func record(_ name: String) { calls[name, default: 0] += 1 }

  func isAvailable() -> Bool {
    record("IsAvailable")
    return isAvailableHandler?() ?? false
  }

  func correctComposition(_ request: ConversionRequest) -> [TypeCorrectedQuery]? {
    record("CorrectComposition")
    return correctCompositionHandler?(request) ?? nil
  }

  func populateTypeCorrectedQuery(_ request: ConversionRequest, _ results: inout [PredictionResult]) {
    record("PopulateTypeCorrectedQuery")
    populateTypeCorrectedQueryHandler?(request, &results)
  }

  func postCorrect(_ request: ConversionRequest, _ results: inout [PredictionResult]) {
    record("PostCorrect")
    postCorrectHandler?(request, &results)
  }

  func rescoreResults(_ request: ConversionRequest, _ results: inout [PredictionResult]) {
    record("RescoreResults")
    rescoreResultsHandler?(request, &results)
  }

  func predict(_ request: ConversionRequest, _ results: inout [PredictionResult]) -> Bool {
    record("Predict")
    return predictHandler?(request, &results) ?? false
  }

  func getReadingAlignment(_ surface: String, _ reading: String) -> [(String, String)] { [] }

  func decodeEnglish(_ request: ConversionRequest, _ results: inout [PredictionResult]) -> Bool {
    record("DecodeEnglish")
    return decodeEnglishHandler?(request, &results) ?? false
  }
}

// MARK: - Composer helpers

extension PT {

  /// `InsertInputSequence`: inserts `text` as key events.
  static func insertInputSequence(_ text: String, _ composer: inout Composer) {
    for scalar in text.unicodeScalars {
      var key = Genmai_Commands_KeyEvent()
      if scalar.value <= 0x7F {
        key.keyCode = scalar.value
      } else {
        key.keyCode = UInt32(UInt8(ascii: "?"))
        key.keyString = String(scalar)
      }
      composer.insertCharacterKeyEvent(key)
    }
  }

  static func config() -> Genmai_Config_Config {
    var config = Genmai_Config_Config()
    ConfigHandler.getDefaultConfig(&config)
    return config
  }

  static func tableFromFile(_ path: String) -> Table {
    let table = Table()
    _ = table.loadFromFile(path)
    return table
  }

  static func results(_ n: Int) -> [PredictionResult] {
    Array(repeating: PredictionResult(), count: n)
  }

}

let predictionMockDataAvailable = DataManagerTestSupport.hasMockData
