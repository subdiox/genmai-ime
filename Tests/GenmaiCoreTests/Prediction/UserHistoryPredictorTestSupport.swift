// Test support for UserHistoryPredictorTests (the fixture part of
// mozc/src/prediction/user_history_predictor_test.cc, 3.35.6354).
//
// Mapping from the C++ fixture:
// - engine::ModulesPresetBuilder().PresetDictionary(MockDictionary)
//   .Build(MockDataManager) -> `UserHistoryTestModules` (MockDictionary,
//   real UserDictionary / UserHistoryStorage / Segmenter / Connector built from
//   the mock data set, a supplemental model stub or `MockSupplementalModel`).
// - MockRealtimeDecoder -> `MockRealtimeDecoder` (closure-based).
// - SegmentsProxy -> `SegmentsProxy` (class). `history_result()` is passed to
//   ConversionRequest as a *view* (`HistoryResultView`), like C++
//   SetHistoryResultView: changes made to the proxy after building the
//   request (e.g. PrependHistory) are visible to the request.
// - The C++ ConversionRequest also keeps *views* of request_, config_ and
//   context_; the Swift ConversionRequest copies them, so tests that modify
//   them after building a request rebuild the request.
// - InsertEntry/AppendEntry return `Entry*`; here they return `EntryRef`, a
//   wrapper of the entry's snapshot handle (which holds no lock).

import Foundation
import GenmaiBase
import GenmaiProtocol
import GenmaiStorage
import Synchronization
import Testing

@testable import GenmaiCore

let kRevertId: UInt32 = 1234

/// engine::MockSupplementalModel (only the methods UserHistoryPredictor uses).
final class MockSupplementalModel: UserHistorySupplementalModel {
  var correctCompositionHandler: ((ConversionRequest) -> [TypeCorrectedQuery]?)?
  var getReadingAlignmentHandler: ((String, String) -> [(String, String)])?
  private(set) var correctCompositionCalls = 0

  func correctComposition(_ request: ConversionRequest) -> [TypeCorrectedQuery]? {
    correctCompositionCalls += 1
    return correctCompositionHandler?(request) ?? nil
  }

  func getReadingAlignment(_ surface: String, _ reading: String) -> [(String, String)] {
    getReadingAlignmentHandler?(surface, reading) ?? []
  }
}

/// MockRealtimeDecoder.
final class MockRealtimeDecoder: UserHistoryRealtimeDecoder {
  var decodeSuffixHandler: ((ConversionRequest, UInt16, String) -> PredictionResult?)?
  private(set) var decodeSuffixCalls = 0

  func decodeSuffix(_ request: ConversionRequest, _ prefixRid: UInt16, _ suffix: String)
    -> PredictionResult?
  {
    decodeSuffixCalls += 1
    return decodeSuffixHandler?(request, prefixRid, suffix) ?? nil
  }
}

/// The parts of engine::Modules used by UserHistoryPredictor.
final class UserHistoryTestModules: UserHistoryPredictorModules {
  let dataManager: DataManager
  let posMatcher: PosMatcher
  let userDictionary: any UserDictionaryInterface
  let dictionary: any DictionaryInterface
  let storage: UserHistoryStorage
  let segmenter: Segmenter
  let connector: Connector
  let supplementalModel: any UserHistorySupplementalModel

  init(
    dictionary: any DictionaryInterface = MockDictionary(),
    supplementalModel: any UserHistorySupplementalModel = UserHistorySupplementalModelStub()
  ) throws {
    let dataManager = try ConverterCoreTestSupport.mockDataManager()
    self.dataManager = dataManager
    let posMatcher = PosMatcher(dataManager.getPosMatcherData())
    self.posMatcher = posMatcher
    let userPosData = dataManager.getUserPosData()
    self.userDictionary = UserDictionary(
      UserPos(userPosData.tokenArray, userPosData.stringArray), posMatcher, PredictionTestUserDictionary.emptyFile())
    self.dictionary = dictionary
    self.storage = UserHistoryStorage()
    self.segmenter = Segmenter(dataManager: dataManager)
    self.connector = try ConverterCoreTestSupport.mockConnector()
    self.supplementalModel = supplementalModel
  }

  func getPosMatcher() -> PosMatcher { posMatcher }
  func getUserDictionary() -> any UserDictionaryInterface { userDictionary }
  func getUserHistoryStorage() -> UserHistoryStorage { storage }
  func getUserHistorySupplementalModel() -> any UserHistorySupplementalModel { supplementalModel }
  func getSegmenter() -> Segmenter { segmenter }
  func getConnector() -> Connector { connector }
  func getDictionary() -> any DictionaryInterface { dictionary }
}

/// A lock-free reference to an entry in the storage (C++ `Entry*`).
final class EntryRef {
  let snapshot: UserHistoryStorage.EntrySnapshot

  init(_ snapshot: UserHistoryStorage.EntrySnapshot) {
    self.snapshot = snapshot
  }

  var entry: UserHistoryPredictor.Entry {
    get { snapshot.entry }
    set { snapshot.entry = newValue }
  }
}

/// A view of SegmentsProxy::history_result() (C++ SetHistoryResultView).
final class HistoryResultView: ConversionRequestHistoryResult, PredictionHistoryResultConvertible {
  private let box: HistoryResultBox

  init(_ box: HistoryResultBox) {
    self.box = box
  }

  var historyPredictionResult: PredictionResult { box.result }

  func historySuffixKeyAndValue(_ size: Int) -> (key: String, value: String) {
    historyPredictionResult.historySuffixKeyAndValue(size)
  }
  var historyInnerSegmentsSize: Int { historyPredictionResult.historyInnerSegmentsSize }
  var historyRid: Int { historyPredictionResult.historyRid }
  var historyCost: Int { historyPredictionResult.historyCost }
}

/// The history result of a `SegmentsProxy`, shared with its views.
final class HistoryResultBox: Sendable {
  private let value = Mutex(PredictionResult())

  var result: PredictionResult {
    get { value.withLock { $0 } }
    set { value.withLock { $0 = newValue } }
  }
}

/// Needs to call UpdateHistoryResult() to update history_result_.
/// The reference of history_result_ is shared by ConversionRequest.
final class SegmentsProxy {
  private struct Segment {
    var key = ""
    var results: [PredictionResult] = []
    var isHistory = false
  }

  private var segments: [Segment] = []
  private let historyBox = HistoryResultBox()
  var historyResult: PredictionResult { historyBox.result }

  init() {}

  /// The view passed to ConversionRequest (SetHistoryResultView).
  var historyResultView: HistoryResultView { HistoryResultView(historyBox) }

  func addSegment(_ key: String) {
    var segment = Segment()
    segment.key = key
    segments.append(segment)
    updateHistoryResult()
  }

  func makeSegments(_ key: String) {
    segments.removeAll()
    addSegment(key)
    updateHistoryResult()
  }

  func addCandidate(_ segmentIndex: Int, _ value: String) {
    var result = PredictionResult()
    result.key = segments[segmentIndex].key
    result.value = value
    segments[segmentIndex].results.append(result)
    updateHistoryResult()
  }

  func setCandidate(_ segmentIndex: Int, _ candidateIndex: Int, _ value: String) {
    segments[segmentIndex].results[candidateIndex].value = value
    updateHistoryResult()
  }

  /// MutableCandidate(): mutates the candidate in place.
  func mutateCandidate(
    _ segmentIndex: Int, _ candidateIndex: Int, _ body: (inout PredictionResult) -> Void
  ) {
    body(&segments[segmentIndex].results[candidateIndex])
    updateHistoryResult()
  }

  func candidate(_ segmentIndex: Int, _ candidateIndex: Int) -> PredictionResult {
    segments[segmentIndex].results[candidateIndex]
  }

  func pushBackInnerSegmentBoundary(
    _ segmentIndex: Int, _ candidateIndex: Int, _ keyLen: Int, _ valueLen: Int,
    _ contentKeyLen: Int, _ contentValueLen: Int
  ) {
    segments[segmentIndex].results[candidateIndex].innerSegmentBoundary.append(
      encodedLengths(keyLen, valueLen, contentKeyLen, contentValueLen))
    updateHistoryResult()
  }

  func addCandidateWithDescription(_ segmentIndex: Int, _ value: String, _ desc: String) {
    var result = PredictionResult()
    result.value = value
    result.key = segments[segmentIndex].key
    result.description = desc
    segments[segmentIndex].results.append(result)
    updateHistoryResult()
  }

  func moveCandidate(_ segmentIndex: Int, _ src: Int, _ dst: Int) {
    // std::rotate(it_new, it_old, it_old + 1): moves results[src] to dst.
    let moved = segments[segmentIndex].results.remove(at: src)
    segments[segmentIndex].results.insert(moved, at: dst)
    updateHistoryResult()
  }

  func prependHistory(_ key: String, _ value: String) {
    var segment = Segment()
    segment.key = key
    segment.isHistory = true
    var result = PredictionResult()
    result.key = key
    result.value = value
    segment.results.append(result)
    segments.insert(segment, at: 0)
    updateHistoryResult()
  }

  func setHistoryType(_ segmentIndex: Int) {
    segments[segmentIndex].isHistory = true
    updateHistoryResult()
  }

  func popBackSegment() {
    if !segments.isEmpty { segments.removeLast() }
    updateHistoryResult()
  }

  func clearConversionSegments() {
    while let last = segments.last {
      if last.isHistory { break }
      segments.removeLast()
    }
    updateHistoryResult()
  }

  var key: String {
    for segment in segments where !segment.isHistory {
      return segment.key
    }
    return ""
  }

  func makeLearningResults() -> [PredictionResult] {
    makeResults(false)  // is_history
  }

  func clear() { segments.removeAll() }

  private func makeResults(_ isHistory: Bool) -> [PredictionResult] {
    var results: [PredictionResult] = []
    if segments.isEmpty { return results }

    var subSegments: [Segment] = []
    for segment in segments {
      if segment.isHistory != isHistory { continue }
      if segment.results.isEmpty { return results }
      subSegments.append(segment)
    }

    if subSegments.count == 1 {
      return subSegments[0].results
    } else {
      var result = PredictionResult()
      for segment in subSegments {
        let topResult = segment.results[0]
        result.key += topResult.key
        result.value += topResult.value
        result.description += topResult.description
        if topResult.innerSegmentBoundary.isEmpty {
          result.innerSegmentBoundary.append(
            encodedLengths(
              topResult.key.utf8.count, topResult.value.utf8.count, topResult.key.utf8.count,
              topResult.value.utf8.count))
        } else {
          result.innerSegmentBoundary.append(contentsOf: topResult.innerSegmentBoundary)
        }
      }
      results.append(result)
    }

    return results
  }

  private func updateHistoryResult() {
    // C++ takes front() of a possibly empty vector (UB); use the default.
    historyBox.result = makeResults(true).first ?? PredictionResult()  // is_history
  }
}

/// UserHistoryPredictorTest fixture (SetUp/TearDown + helpers). Create it
/// inside the `.scopedConfigEnvironment` scope (temporary user profile).
final class UserHistoryPredictorTestFixture {
  var composer: Composer
  let table: Table
  var config = Genmai_Config_Config()
  var request = Genmai_Commands_Request()
  var context = Genmai_Commands_Context()

  struct DataAndPredictor {
    let modules: UserHistoryTestModules
    let realtimeDecoder: MockRealtimeDecoder
    let predictor: UserHistoryPredictor
  }

  private(set) var dataAndPredictor: DataAndPredictor

  init() async throws {
    request = Genmai_Commands_Request()
    config = ConfigHandler.defaultConfig()
    config.useTypingCorrection = true
    table = Table()
    composer = Composer(table, request, config)
    dataAndPredictor = try await Self.createDataAndPredictor()
  }

  deinit {
    request = Genmai_Commands_Request()
    let charFormManager = CharacterFormManager.getCharacterFormManager()
    charFormManager.setDefaultRule()
    charFormManager.clearHistory()
  }

  static func createDataAndPredictor(
    dictionary: any DictionaryInterface = MockDictionary(),
    supplementalModel: any UserHistorySupplementalModel = UserHistorySupplementalModelStub()
  ) async throws -> DataAndPredictor {
    let modules = try UserHistoryTestModules(
      dictionary: dictionary, supplementalModel: supplementalModel)
    let realtimeDecoder = MockRealtimeDecoder()
    let predictor = UserHistoryPredictor(modules, realtimeDecoder)
    await predictor.wait()
    return DataAndPredictor(
      modules: modules, realtimeDecoder: realtimeDecoder, predictor: predictor)
  }

  func createConversionRequestWithOptions(
    _ options: ConversionRequest.Options, _ segmentsProxy: SegmentsProxy
  ) -> ConversionRequest {
    ConversionRequestBuilder()
      .setComposer(composer)
      .setRequestView(request)
      .setContextView(context)
      .setConfigView(config)
      .setOptions(options)
      .setHistoryResultView(segmentsProxy.historyResultView)
      .setKey(segmentsProxy.key)
      .build()
  }

  func createConversionRequest(_ segmentsProxy: SegmentsProxy) -> ConversionRequest {
    var options = ConversionRequest.Options()
    options.maxUserHistoryPredictionCandidatesSize = 10
    options.maxUserHistoryPredictionCandidatesSizeForZeroQuery = 10
    return ConversionRequestBuilder()
      .setComposer(composer)
      .setRequestView(request)
      .setContextView(context)
      .setConfigView(config)
      .setOptions(options)
      .setHistoryResultView(segmentsProxy.historyResultView)
      .setKey(segmentsProxy.key)
      .build()
  }

  func getUserHistoryPredictor() -> UserHistoryPredictor {
    dataAndPredictor.predictor
  }

  func getUserHistoryPredictorWithClearedHistory() -> UserHistoryPredictor {
    let predictor = dataAndPredictor.predictor
    predictor.clearAllHistory()
    return predictor
  }

  func getUserDictionary() -> any UserDictionaryInterface {
    dataAndPredictor.modules.getUserDictionary()
  }

  func isSuggested(_ predictor: UserHistoryPredictor, _ key: String, _ value: String) -> Bool {
    var composer = Composer()
    composer.setPreeditTextForTestOnly(key)
    let segmentsProxy = SegmentsProxy()
    segmentsProxy.makeSegments(key)
    let conversionRequest = ConversionRequestBuilder()
      .setComposer(composer)
      .setHistoryResultView(segmentsProxy.historyResultView)
      .setRequestType(.suggestion)
      .build()
    let results = predictor.predict(conversionRequest)
    return !results.isEmpty && Self.findCandidateByValue(value, results) != nil
  }

  func isPredicted(_ predictor: UserHistoryPredictor, _ key: String, _ value: String) -> Bool {
    var composer = Composer()
    composer.setPreeditTextForTestOnly(key)
    let segmentsProxy = SegmentsProxy()
    segmentsProxy.makeSegments(key)

    let conversionRequest = ConversionRequestBuilder()
      .setComposer(composer)
      .setHistoryResultView(segmentsProxy.historyResultView)
      .setRequestType(.prediction)
      .build()
    let results = predictor.predict(conversionRequest)
    return !results.isEmpty && Self.findCandidateByValue(value, results) != nil
  }

  func isSuggestedAndPredicted(_ predictor: UserHistoryPredictor, _ key: String, _ value: String)
    -> Bool
  {
    isSuggested(predictor, key, value) && isPredicted(predictor, key, value)
  }

  @discardableResult
  static func insertEntry(_ predictor: UserHistoryPredictor, _ key: String, _ value: String)
    -> EntryRef
  {
    let fp = UserHistoryStorage.fingerprint(key, value)
    let e = predictor.storage.insert(fp)
    e.entry.key = key
    e.entry.value = value
    e.entry.removed = false
    e.entry.suggestionFreq = 1
    e.entry.lastAccessTime = 1
    return EntryRef(e)
  }

  @discardableResult
  static func appendEntry(
    _ predictor: UserHistoryPredictor, _ key: String, _ value: String, _ prev: EntryRef
  ) -> EntryRef {
    prev.entry.nextEntryFps.append(UserHistoryStorage.fingerprint(key, value))
    return insertEntry(predictor, key, value)
  }

  static func isConnected(_ prev: UserHistoryPredictor.Entry, _ next: UserHistoryPredictor.Entry)
    -> Bool
  {
    let fp = UserHistoryStorage.fingerprint(next)
    return prev.nextEntryFps.contains(fp)
  }

  /// Helper function to create a test case for bigram history deletion.
  /// Returns (japaneseinput, japanese, input).
  func initHistoryJapaneseInput(_ predictor: UserHistoryPredictor) -> (EntryRef, EntryRef, EntryRef) {
    // Make the history for ("japaneseinput", "JapaneseInput"). It's assumed
    // that this sentence consists of two segments, "japanese" and "input". So,
    // the following history entries are constructed:
    //   ("japaneseinput", "JapaneseInput")  // Unigram
    //   ("japanese", "Japanese") --- ("input", "Input")  // Bigram chain
    let japaneseinput = Self.insertEntry(predictor, "japaneseinput", "JapaneseInput")
    let japanese = Self.insertEntry(predictor, "japanese", "Japanese")
    let input = Self.appendEntry(predictor, "input", "Input", japanese)

    // Check the predictor functionality for the above history structure.
    #expect(isSuggestedAndPredicted(predictor, "japan", "Japanese"))
    #expect(isSuggestedAndPredicted(predictor, "japan", "JapaneseInput"))
    #expect(isSuggestedAndPredicted(predictor, "input", "Input"))
    return (japaneseinput, japanese, input)
  }

  /// Helper function to create a test case for trigram history deletion.
  /// Returns (japaneseinputmethod, japanese, input, method).
  func initHistoryJapaneseInputMethod(_ predictor: UserHistoryPredictor) -> (
    EntryRef, EntryRef, EntryRef, EntryRef
  ) {
    // Make the history for ("japaneseinputmethod", "JapaneseInputMethod"). It's
    // assumed that this sentence consists of three segments, "japanese",
    // "input" and "method". So, the following history entries are constructed:
    //   ("japaneseinputmethod", "JapaneseInputMethod")  // Unigram
    //   ("japanese", "Japanese") -- ("input", "Input") -- ("method", "Method")
    let japaneseinputmethod = Self.insertEntry(
      predictor, "japaneseinputmethod", "JapaneseInputMethod")
    let japanese = Self.insertEntry(predictor, "japanese", "Japanese")
    let input = Self.appendEntry(predictor, "input", "Input", japanese)
    let method = Self.appendEntry(predictor, "method", "Method", input)

    // Check the predictor functionality for the above history structure.
    #expect(isSuggestedAndPredicted(predictor, "japan", "Japanese"))
    #expect(isSuggestedAndPredicted(predictor, "japan", "JapaneseInput"))
    #expect(isSuggestedAndPredicted(predictor, "japan", "JapaneseInputMethod"))
    #expect(isSuggestedAndPredicted(predictor, "inpu", "Input"))
    #expect(isSuggestedAndPredicted(predictor, "inpu", "InputMethod"))
    #expect(isSuggestedAndPredicted(predictor, "meth", "Method"))
    return (japaneseinputmethod, japanese, input, method)
  }

  func setUpInput(_ key: String, _ segmentsProxy: SegmentsProxy) {
    composer.reset()
    composer.setPreeditTextForTestOnly(key)
    // TODO(taku): `SetPreeditTextForTestOnly` changes the input mode to Latin
    // when key is empty. This behavior is not intended.
    if key.isEmpty { composer.setInputMode(.hiragana) }
    segmentsProxy.makeSegments(key)
  }

  func setUpInputForSuggestion(_ key: String, _ segmentsProxy: SegmentsProxy) -> ConversionRequest {
    setUpInput(key, segmentsProxy)
    var options = ConversionRequest.Options()
    options.requestType = .suggestion
    return createConversionRequestWithOptions(options, segmentsProxy)
  }

  func setUpInputForSuggestionWithHistory(
    _ key: String, _ histKey: String, _ histValue: String, _ segmentsProxy: SegmentsProxy
  ) -> ConversionRequest {
    let convreq = setUpInputForSuggestion(key, segmentsProxy)
    segmentsProxy.prependHistory(histKey, histValue)
    return convreq
  }

  func setUpInputForPrediction(_ key: String, _ segmentsProxy: SegmentsProxy) -> ConversionRequest {
    setUpInput(key, segmentsProxy)
    var options = ConversionRequest.Options()
    options.requestType = .prediction
    return createConversionRequestWithOptions(options, segmentsProxy)
  }

  func setUpInputForPredictionWithHistory(
    _ key: String, _ histKey: String, _ histValue: String, _ segmentsProxy: SegmentsProxy
  ) -> ConversionRequest {
    let convreq = setUpInputForPrediction(key, segmentsProxy)
    segmentsProxy.prependHistory(histKey, histValue)
    return convreq
  }

  func setUpInputForConversion(_ key: String, _ segmentsProxy: SegmentsProxy) -> ConversionRequest {
    setUpInput(key, segmentsProxy)
    var options = ConversionRequest.Options()
    options.requestType = .conversion
    return createConversionRequestWithOptions(options, segmentsProxy)
  }

  func setUpInputForConversionWithHistory(
    _ key: String, _ histKey: String, _ histValue: String, _ segmentsProxy: SegmentsProxy
  ) -> ConversionRequest {
    let convreq = setUpInputForConversion(key, segmentsProxy)
    segmentsProxy.prependHistory(histKey, histValue)
    return convreq
  }

  func initSegmentsFromInputSequence(_ text: String, _ segmentsProxy: SegmentsProxy)
    -> ConversionRequest
  {
    for ch in text.unicodeScalars {
      var key = Genmai_Commands_KeyEvent()
      let codepoint = ch.value
      if codepoint <= 0x7F {  // IsAscii, w is unsigned.
        key.keyCode = codepoint
      } else {
        key.keyCode = UInt32(UInt8(ascii: "?"))
        key.keyString = String(ch)
      }
      _ = composer.insertCharacterKeyEvent(key)
    }

    let query = composer.getQueryForPrediction()
    segmentsProxy.addSegment(query)

    var options = ConversionRequest.Options()
    options.requestType = .prediction
    return createConversionRequestWithOptions(options, segmentsProxy)
  }

  static func findCandidateByValue(_ value: String, _ results: [PredictionResult]) -> Int? {
    for i in 0..<results.count {
      if results[i].value.bytesEqual(value) {
        return i
      }
    }
    return nil
  }

  static func getKeyValueWithBoundary(_ result: PredictionResult) -> String {
    var v: [String] = []
    for iter in result.innerSegments() {
      v.append("\(iter.key),\(iter.value),\(iter.contentKey),\(iter.contentValue)")
    }
    return v.joined(separator: "|")
  }
}

/// Skips (returns nil) when the mock data set is missing.
func makeUserHistoryPredictorTestFixture() async throws -> UserHistoryPredictorTestFixture? {
  guard ConverterCoreTestSupport.hasMockData else { return nil }
  return try await UserHistoryPredictorTestFixture()
}
