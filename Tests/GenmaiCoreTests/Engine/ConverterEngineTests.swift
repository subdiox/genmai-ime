// Port of the tests of mozc/src/converter/converter_test.cc (3.35.6354) that
// need the real engine (engine::Modules, Engine / MockDataEngineFactory,
// prediction::Predictor, Rewriter). They were deferred from
// Tests/GenmaiCoreTests/Converter/ConverterTests.swift until the engine port.
//
// Deviations from C++:
// - gMock's MockUserDictionary is the hand-written MockUserDictionary of the
//   dictionary tests (handlers instead of EXPECT_CALL).
// - DEFAULT_PREDICTOR and MOBILE_PREDICTOR both create prediction::Predictor
//   (as in C++; the request decides the behavior).
// - Every test runs with a temporary user profile and a scoped
//   CharacterFormManager (TestWithTempUserProfile).

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private typealias UserEntry = Genmai_UserDictionary_UserDictionary.Entry
private typealias PosType = Genmai_UserDictionary_UserDictionary.PosType

private final class EngineStubPredictor: PredictorInterface {
  func predict(_ request: ConversionRequest) -> [PredictionResult] {
    let key = request.key()
    if key.isEmpty {
      return []
    }
    var result = PredictionResult()
    result.key = key
    result.value = key
    return [result]
  }

  func getPredictorName() -> String { "StubPredictor" }
}

private final class EngineStubRewriter: RewriterInterface {
  func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool { true }
}

private enum PredictorType {
  case stubPredictor
  case defaultPredictor
  case mobilePredictor
}

private struct UserDefinedEntry {
  let key: String
  let value: String
  let pos: PosType
  init(_ key: String, _ value: String, _ pos: PosType) {
    self.key = key
    self.value = value
    self.pos = pos
  }
}

/// Runs `body` with a temporary user profile and a scoped character form
/// manager.
private func withTestProfile<R>(_ body: () throws -> R) rethrows -> R {
  try SystemUtil.withTempUserProfile { _ in
    try CharacterFormManager.withScopedManagerForTesting { try body() }
  }
}

private func convReq(_ key: String, _ requestType: RequestType) -> ConversionRequest {
  var composer = Composer()
  composer.setPreeditTextForTestOnly(key)
  return ConversionRequestBuilder().setComposer(composer).setRequestType(requestType).build()
}

private func createConverter(
  _ modules: Modules, _ rewriter: any RewriterInterface, _ predictorType: PredictorType
) -> Converter {
  Converter(
    modules,
    { _ in ImmutableConverter(modules) },
    { _, converter, immutableConverter in
      if predictorType == .stubPredictor {
        return EngineStubPredictor()
      }
      return Predictor(modules, converter, immutableConverter)
    },
    { _ in rewriter })
}

private func createConverterWithUserDefinedEntries(
  _ userDefinedEntries: [UserDefinedEntry], _ predictorType: PredictorType
) throws -> Converter {
  let dataManager = try MockDataManager.create()
  let posMatcher = PosMatcher(dataManager.getPosMatcherData())
  let userPosData = dataManager.getUserPosData()
  let userDictionary = UserDictionary(
    UserPos(userPosData.tokenArray, userPosData.stringArray), posMatcher)
  do {
    var storage = Genmai_UserDictionary_UserDictionaryStorage()
    var dictionary = Genmai_UserDictionary_UserDictionary()
    for userEntry in userDefinedEntries {
      var entry = UserEntry()
      entry.key = userEntry.key
      entry.value = userEntry.value
      entry.pos = userEntry.pos
      dictionary.entries.append(entry)
    }
    storage.dictionaries.append(dictionary)
    userDictionary.load(storage)
  }

  let modules = try ModulesPresetBuilder()
    .presetPosMatcher(posMatcher)
    .presetUserDictionary(userDictionary)
    .build(dataManager)

  return createConverter(modules, EngineStubRewriter(), predictorType)
}

private func createEngine() throws -> Engine {
  try Engine.createEngine(MockDataManager.create())
}

private func findCandidateByValue(_ value: String, _ segment: Segment) -> Bool {
  getCandidateIndexByValue(value, segment) != -1
}

private func getCandidateIndexByValue(_ value: String, _ segment: Segment) -> Int {
  for i in 0..<segment.candidatesSize {
    if segment.candidate(i).value.bytesEqual(value) {
      return i
    }
  }
  return -1  // not found
}

/// Calls back with a user dictionary token (InvokeCallbackWithUserDictionaryToken).
private func invokeCallbackWithUserDictionaryToken(
  _ key: String, _ value: String, _ callback: any DictionaryCallback
) {
  let token = Token(
    key: key, value: value, cost: MockDictionary.kDefaultCost,
    lid: UInt16(MockDictionary.kDefaultPosId), rid: UInt16(MockDictionary.kDefaultPosId),
    attributes: Token.Attribute.userDictionary)
  _ = callback.onToken(key, key, token)
}

private func multiSegmentRequest() -> Genmai_Commands_Request {
  var request = Genmai_Commands_Request()
  request.decoderExperimentParams.enableMultiSegmentCandidate = true
  return request
}

@Suite(.enabled(if: DataManagerTestSupport.hasMockData, "mock_genmai.data is missing"))
struct ConverterEngineTests {
  @Test func startSuggestion() throws {
    try withTestProfile {
      var clientRequest = Genmai_Commands_Request()
      clientRequest.mixedConversion = true

      let engine = try MockDataEngineFactory.create()
      let converter = engine.getConverter()

      let kShi = "し"

      let table = Table()
      table.addRule("si", kShi, "")
      table.addRule("shi", kShi, "")
      let config = Genmai_Config_Config()

      for (input, expected) in [("shi", "shi"), ("si", "si")] {
        var composer = Composer(table, clientRequest, config)

        composer.insertCharacter(input)

        var options = ConversionOptions()
        options.requestType = .suggestion
        let segments = Segments()
        let request = ConversionRequestBuilder()
          .setComposer(composer)
          .setRequestView(clientRequest)
          .setConfigView(config)
          .setHistoryResult(ConverterUtil.historySegmentsToResult(segments))
          .setOptions(options)
          .build()

        #expect(converter.startPrediction(request, segments))
        #expect(segments.segmentsSize == 1)
        try #require(
          segments.segment(0).metaCandidatesSize >= TransliterationType.halfAscii.rawValue)
        #expect(
          segments.segment(0).metaCandidate(TransliterationType.halfAscii.rawValue).value
            == expected)
      }
    }
  }

  @Test func startPartialPrediction() throws {
    try withTestProfile {
      let engine = try MockDataEngineFactory.create()
      let converter = engine.getConverter()
      let segments = Segments()
      #expect(converter.startPrediction(convReq("わたしは", .partialPrediction), segments))
      #expect(segments.segmentsSize == 1)
      #expect(segments.segment(0).candidate(0).value == "私は")
      #expect(segments.segment(0).candidate(0).contentValue == "私")
      #expect(segments.segment(0).candidate(0).key == "わたしは")
      #expect(segments.segment(0).candidate(0).contentKey == "わたし")
    }
  }

  @Test func startPartialSuggestion() throws {
    try withTestProfile {
      let engine = try MockDataEngineFactory.create()
      let converter = engine.getConverter()
      let segments = Segments()
      #expect(converter.startPrediction(convReq("わたしは", .partialSuggestion), segments))
      #expect(segments.segmentsSize == 1)
      #expect(segments.segment(0).candidate(0).value == "私は")
      #expect(segments.segment(0).candidate(0).contentValue == "私")
      #expect(segments.segment(0).candidate(0).key == "わたしは")
      #expect(segments.segment(0).candidate(0).contentKey == "わたし")
    }
  }

  @Test func startPartialPredictionMobile() throws {
    try withTestProfile {
      let engine = try createEngine()
      let converter = engine.getConverter()
      let segments = Segments()
      #expect(converter.startPrediction(convReq("わたしは", .partialPrediction), segments))
      #expect(segments.segmentsSize == 1)
      #expect(segments.segment(0).candidate(0).value == "私は")
      #expect(segments.segment(0).candidate(0).contentValue == "私")
      #expect(segments.segment(0).candidate(0).key == "わたしは")
      #expect(segments.segment(0).candidate(0).contentKey == "わたし")
    }
  }

  @Test func startPartialSuggestionMobile() throws {
    try withTestProfile {
      let engine = try createEngine()
      let converter = engine.getConverter()
      let segments = Segments()
      #expect(converter.startPrediction(convReq("わたしは", .partialSuggestion), segments))
      #expect(segments.segmentsSize == 1)
      #expect(segments.segment(0).candidate(0).value == "私は")
      #expect(segments.segment(0).candidate(0).contentValue == "私")
      #expect(segments.segment(0).candidate(0).key == "わたしは")
      #expect(segments.segment(0).candidate(0).contentKey == "わたし")
    }
  }

  @Test func variantExpansionForSuggestion() throws {
    try withTestProfile {
      // Create Converter with mock user dictionary
      let mockUserDictionary = MockUserDictionary()
      mockUserDictionary.lookupPredictiveHandler = { key, callback in
        if key == "てすと" {
          invokeCallbackWithUserDictionaryToken("てすと", "<>!?", callback)
        }
      }
      mockUserDictionary.lookupPrefixHandler = { key, callback in
        if key == "てすとの" {
          invokeCallbackWithUserDictionaryToken("てすと", "<>!?", callback)
        }
      }

      let modules = try ModulesPresetBuilder()
        .presetUserDictionary(mockUserDictionary)
        .build(MockDataManager.create())

      let converter = Converter(
        modules,
        { _ in ImmutableConverter(modules) },
        { _, converter, immutableConverter in Predictor(modules, converter, immutableConverter) },
        { _ in RewriterImpl(modules) })

      let segments = Segments()
      do {
        // Dictionary suggestion
        #expect(converter.startPrediction(convReq("てすと", .suggestion), segments))
        #expect(segments.conversionSegmentsSize == 1)
        #expect(1 <= segments.conversionSegment(0).candidatesSize)
        #expect(findCandidateByValue("<>!?", segments.conversionSegment(0)))
        #expect(!findCandidateByValue("＜＞！？", segments.conversionSegment(0)))
      }
      do {
        // Realtime conversion
        segments.clear()
        #expect(converter.startPrediction(convReq("てすとの", .suggestion), segments))
        #expect(segments.conversionSegmentsSize == 1)
        #expect(1 <= segments.conversionSegment(0).candidatesSize)
        #expect(findCandidateByValue("<>!?の", segments.conversionSegment(0)))
        #expect(!findCandidateByValue("＜＞！？の", segments.conversionSegment(0)))
      }
    }
  }

  @Test func userEntryInMobilePrediction() throws {
    try withTestProfile {
      let userDefinedEntries = [UserDefinedEntry("てすと", "google", .noPos)]

      var request = Genmai_Commands_Request()
      var config = Genmai_Config_Config()
      ConfigHandler.getDefaultConfig(&config)
      let table = Table()
      var composer = Composer(table, request, config)
      RequestTestUtil.fillMobileRequest(&request)

      let converter = try createConverterWithUserDefinedEntries(
        userDefinedEntries, .mobilePredictor)

      do {
        composer.setPreeditTextForTestOnly("てすとが")
        var options = ConversionOptions()
        options.requestType = .prediction
        let segments = Segments()
        let conversionRequest = ConversionRequestBuilder()
          .setComposer(composer)
          .setRequestView(request)
          .setConfigView(config)
          .setHistoryResult(ConverterUtil.historySegmentsToResult(segments))
          .setOptions(options)
          .build()
        #expect(converter.startPrediction(conversionRequest, segments))
        try #require(segments.segmentsSize == 1)
        #expect(findCandidateByValue("googleが", segments.segment(0)))
      }
    }
  }

  @Test func userEntryShouldBePromotedMobilePrediction() throws {
    try withTestProfile {
      // "哀" is not in the test dictionary
      let userDefinedEntries = [UserDefinedEntry("あい", "哀", .noun)]

      let converter = try createConverterWithUserDefinedEntries(
        userDefinedEntries, .mobilePredictor)

      do {
        let segments = Segments()
        #expect(converter.startPrediction(convReq("あい", .prediction), segments))
        try #require(segments.conversionSegmentsSize == 1)
        try #require(1 < segments.conversionSegment(0).candidatesSize)

        // "哀" should be the top result for the key "あい".
        var firstAiIndex = -1
        for i in 0..<segments.conversionSegment(0).candidatesSize {
          if segments.conversionSegment(0).candidate(i).key == "あい" {
            firstAiIndex = i
            break
          }
        }
        try #require(firstAiIndex != -1)
        #expect(segments.conversionSegment(0).candidate(firstAiIndex).value == "哀")
      }
    }
  }

  @Test func suppressionEntryShouldBePrioritizedPrediction() throws {
    try withTestProfile {
      // "哀" is not in the test dictionary
      let userDefinedEntries = [
        UserDefinedEntry("あい", "哀", .noun),
        UserDefinedEntry("あい", "哀", .suppressionWord),
      ]

      for type in [PredictorType.defaultPredictor, .mobilePredictor] {
        let converter = try createConverterWithUserDefinedEntries(userDefinedEntries, type)
        let segments = Segments()
        #expect(converter.startPrediction(convReq("あい", .prediction), segments))
        try #require(segments.conversionSegmentsSize == 1)
        try #require(1 < segments.conversionSegment(0).candidatesSize)
        #expect(!findCandidateByValue("哀", segments.conversionSegment(0)))
      }
    }
  }

  @Test func abbreviationShouldBeIndependentPrediction() throws {
    try withTestProfile {
      let userDefinedEntries = [UserDefinedEntry("じゅ", "Google+", .abbreviation)]

      for type in [PredictorType.defaultPredictor, .mobilePredictor] {
        let converter = try createConverterWithUserDefinedEntries(userDefinedEntries, type)
        let segments = Segments()
        #expect(converter.startPrediction(convReq("じゅうじか", .prediction), segments))
        try #require(segments.conversionSegmentsSize == 1)
        #expect(!findCandidateByValue("Google+うじか", segments.conversionSegment(0)))
      }
    }
  }

  @Test func rewriterShouldRespectDefaultCandidates() throws {
    try withTestProfile {
      let engine = try createEngine()
      let converter = engine.getConverter()

      var config = Genmai_Config_Config()
      ConfigHandler.getDefaultConfig(&config)
      var request = Genmai_Commands_Request()
      RequestTestUtil.fillMobileRequest(&request)
      let table = Table()
      var composer = Composer(table, request, config)
      composer.setPreeditTextForTestOnly("あい")
      let segments = Segments()

      var options = ConversionOptions()
      options.requestType = .prediction
      let conversionRequest = ConversionRequestBuilder()
        .setComposer(composer)
        .setRequestView(request)
        .setConfigView(config)
        .setHistoryResult(ConverterUtil.historySegmentsToResult(segments))
        .setOptions(options)
        .build()

      // Remember user history 3 times after getting the top candidate
      var topCandidate = ""
      var seen: Set<String> = []
      for i in 0..<4 {
        segments.clear()
        #expect(converter.startPrediction(conversionRequest, segments))
        let segment = segments.conversionSegment(0)
        if i == 0 {
          topCandidate = segment.candidate(0).value
          seen.insert(topCandidate)
          continue
        }

        for index in 0..<segment.candidatesSize {
          let inserted = seen.insert(segment.candidate(index).value).inserted
          if inserted {
            try #require(converter.commitSegmentValue(segments, 0, index))
            break
          }
        }
        converter.finishConversion(conversionRequest, segments)
      }

      segments.clear()
      #expect(converter.startPrediction(conversionRequest, segments))

      var defaultCandidateIndex = -1
      for i in 0..<segments.conversionSegment(0).candidatesSize {
        if segments.conversionSegment(0).candidate(i).value == topCandidate {
          defaultCandidateIndex = i
          break
        }
      }
      try #require(defaultCandidateIndex != -1)
      #expect(defaultCandidateIndex <= 3)
    }
  }

  @Test func doNotPromotePrefixOfSingleEntryForEnrichPartialCandidates() throws {
    try withTestProfile {
      let engine = try createEngine()
      let converter = engine.getConverter()

      var request = Genmai_Commands_Request()
      var config = Genmai_Config_Config()
      ConfigHandler.getDefaultConfig(&config)
      let table = Table()
      var composer = Composer(table, request, config)
      RequestTestUtil.fillMobileRequest(&request)
      composer.setPreeditTextForTestOnly("おつかれ")

      var options = ConversionOptions()
      options.requestType = .prediction
      let conversionRequest = ConversionRequestBuilder()
        .setComposer(composer)
        .setRequestView(request)
        .setConfigView(config)
        .setOptions(options)
        .build()

      let segments = Segments()

      #expect(converter.startPrediction(conversionRequest, segments))

      let oIndex = getCandidateIndexByValue("お", segments.conversionSegment(0))
      let otsukareIndex = getCandidateIndexByValue("お疲れ", segments.conversionSegment(0))
      #expect(otsukareIndex != -1)
      #expect(oIndex == -1 || otsukareIndex < oIndex)
    }
  }

  @Test func doNotAddOverlappingNodesForPrediction() throws {
    try withTestProfile {
      let engine = try createEngine()
      let converter = engine.getConverter()
      var request = Genmai_Commands_Request()
      var config = Genmai_Config_Config()
      ConfigHandler.getDefaultConfig(&config)
      let table = Table()
      var composer = Composer(table, request, config)
      RequestTestUtil.fillMobileRequest(&request)
      let posMatcher = PosMatcher(
        engine.getModulesForTesting().getDataManager().getPosMatcherData())
      var options = ConversionOptions()
      options.requestType = .prediction
      options.createPartialCandidates = true

      let segments = Segments()
      // History segment.
      do {
        let segment = segments.addSegment()
        segment.setKey("に")
        segment.setSegmentType(.history)
        let candidate = segment.addCandidate()
        candidate.key = "に"
        candidate.value = "に"
        // Hack: Get POS for "助詞".
        // The POS group of the test dictionary entries, "に" and "にて" should
        // be the same to trigger overlapping lookup.
        candidate.lid = posMatcher.getAcceptableParticleAtBeginOfSegmentId()
      }
      composer.setPreeditTextForTestOnly("てはい")

      let conversionRequest = ConversionRequestBuilder()
        .setComposer(composer)
        .setRequestView(request)
        .setConfigView(config)
        .setHistoryResult(ConverterUtil.historySegmentsToResult(segments))
        .setOptions(options)
        .build()

      #expect(converter.startPrediction(conversionRequest, segments))
      #expect(!findCandidateByValue("て廃", segments.conversionSegment(0)))
    }
  }

  @Test func integrationWithCalculatorRewriter() throws {
    try withTestProfile {
      let engine = try MockDataEngineFactory.create()
      let converter = engine.getConverter()

      do {
        // Default (enable_multi_segment_candidate = false).
        let segments = Segments()
        let convreq = ConversionRequestBuilder().setKey("1+1=").build()
        try #require(converter.startConversion(convreq, segments))
        #expect(segments.conversionSegmentsSize == 1)
        #expect(segments.conversionSegment(0).candidate(0).value == "2")
      }

      do {
        // enable_multi_segment_candidate = true.
        let segments = Segments()
        let convreq = ConversionRequestBuilder().setRequest(multiSegmentRequest()).setKey("1+1=")
          .build()
        try #require(converter.startConversion(convreq, segments))
        #expect(segments.conversionSegmentsSize == 4)
        #expect(segments.conversionSegment(0).candidate(0).value == "2")
        #expect(segments.conversionSegment(0).candidate(0).convertedSegmentCount == 4)
      }
    }
  }

  @Test func integrationWithDateRewriter() throws {
    try withTestProfile {
      let dictionary = MockDictionary()
      // Since DateRewriter is not used in some build targets, the test needs
      // to explicitly add it to the converter.
      let converter = createConverter(
        try Modules.create(MockDataManager.create()), DateRewriter(dictionary), .stubPredictor)

      do {
        // Default (enable_multi_segment_candidate = false):
        // Multi-segment is merged into 1 segment via CheckResizeSegmentsRequest.
        let segments = Segments()
        let convreq = ConversionRequestBuilder().setKey("へいせい30ねん").build()
        try #require(converter.startConversion(convreq, segments))
        #expect(segments.conversionSegmentsSize == 1)
        #expect(findCandidateByValue("2018年", segments.conversionSegment(0)))
      }

      do {
        // enable_multi_segment_candidate = true:
        // Multi-segment candidates are generated directly across segments.
        let segments = Segments()
        let convreq = ConversionRequestBuilder().setRequest(multiSegmentRequest())
          .setKey("へいせい30ねん").build()
        try #require(converter.startConversion(convreq, segments))
        #expect(segments.conversionSegmentsSize >= 1)
        #expect(findCandidateByValue("2018年", segments.conversionSegment(0)))
      }

      do {
        let segments = Segments()
        let convreq = ConversionRequestBuilder().setKey("794ねん").build()
        try #require(converter.startConversion(convreq, segments))
        #expect(segments.conversionSegmentsSize == 1)
        #expect(findCandidateByValue("延暦13年", segments.conversionSegment(0)))
      }
    }
  }

  @Test func integrationWithSymbolRewriter() throws {
    try withTestProfile {
      let engine = try MockDataEngineFactory.create()
      let converter = engine.getConverter()

      do {
        // Default (enable_multi_segment_candidate = false).
        let segments = Segments()
        let convreq = ConversionRequestBuilder().setKey("ー>").build()
        try #require(converter.startConversion(convreq, segments))
        #expect(segments.conversionSegmentsSize == 1)
        #expect(findCandidateByValue("→", segments.conversionSegment(0)))
      }

      do {
        // enable_multi_segment_candidate = true.
        let segments = Segments()
        let convreq = ConversionRequestBuilder().setRequest(multiSegmentRequest()).setKey("ー>")
          .build()
        try #require(converter.startConversion(convreq, segments))
        #expect(segments.conversionSegmentsSize == 2)
        let index = getCandidateIndexByValue("→", segments.conversionSegment(0))
        try #require(index != -1)
        #expect(segments.conversionSegment(0).candidate(index).convertedSegmentCount == 2)
      }
    }
  }

  @Test func integrationWithUnicodeRewriter() throws {
    try withTestProfile {
      let engine = try MockDataEngineFactory.create()
      let converter = engine.getConverter()

      do {
        // Default (enable_multi_segment_candidate = false).
        let segments = Segments()
        let convreq = ConversionRequestBuilder().setKey("U+3042").build()
        try #require(converter.startConversion(convreq, segments))
        #expect(segments.conversionSegmentsSize == 1)
        #expect(findCandidateByValue("あ", segments.conversionSegment(0)))
      }

      do {
        // enable_multi_segment_candidate = true.
        let segments = Segments()
        let convreq = ConversionRequestBuilder().setRequest(multiSegmentRequest())
          .setKey("U+3042").build()
        try #require(converter.startConversion(convreq, segments))
        #expect(segments.conversionSegmentsSize == 3)
        let index = getCandidateIndexByValue("あ", segments.conversionSegment(0))
        try #require(index != -1)
        #expect(segments.conversionSegment(0).candidate(index).convertedSegmentCount == 3)
      }
    }
  }

  @Test func integrationWithSmallLetterRewriter() throws {
    try withTestProfile {
      let engine = try MockDataEngineFactory.create()
      let converter = engine.getConverter()

      do {
        // Default (enable_multi_segment_candidate = false).
        let segments = Segments()
        let convreq = ConversionRequestBuilder().setKey("^123").build()
        try #require(converter.startConversion(convreq, segments))
        #expect(segments.conversionSegmentsSize == 1)
        #expect(findCandidateByValue("¹²³", segments.conversionSegment(0)))
      }

      do {
        // enable_multi_segment_candidate = true.
        let segments = Segments()
        let convreq = ConversionRequestBuilder().setRequest(multiSegmentRequest()).setKey("^123")
          .build()
        try #require(converter.startConversion(convreq, segments))
        #expect(segments.conversionSegmentsSize == 2)
        let index = getCandidateIndexByValue("¹²³", segments.conversionSegment(0))
        try #require(index != -1)
        #expect(segments.conversionSegment(0).candidate(index).convertedSegmentCount == 2)
      }
    }
  }

  @Test func applyUserHistoryToConversionE2ETest() throws {
    try withTestProfile {
      let modules = try Modules.create(MockDataManager.create())
      let rewriter = RewriterImpl(modules)
      let converter = createConverter(modules, rewriter, .defaultPredictor)

      var requestProto = Genmai_Commands_Request()
      requestProto.decoderExperimentParams.disableLegacyRewriterInAllConversionMode =
        Rewriter.LegacyRewriterType.disableUserSegmentHistory
        | Rewriter.LegacyRewriterType.disableUserBoundaryHistory

      let kKey = "わたしのなまえ"

      do {
        var composer = Composer()
        composer.setPreeditTextForTestOnly(kKey)
        let convreq = ConversionRequestBuilder()
          .setComposer(composer)
          .setRequest(requestProto)
          .setRequestType(.conversion)
          .build()

        let segments = Segments()
        #expect(converter.startConversion(convreq, segments))
        #expect(segments.conversionSegmentsSize > 0)

        segments.mutableConversionSegment(0).setSegmentType(.fixedValue)
        converter.finishConversion(convreq, segments)
      }

      do {
        var composer = Composer()
        composer.setPreeditTextForTestOnly(kKey)
        let convreq = ConversionRequestBuilder()
          .setComposer(composer)
          .setRequest(requestProto)
          .setRequestType(.conversion)
          .build()

        let segments = Segments()
        #expect(converter.startConversion(convreq, segments))
        try #require(segments.conversionSegmentsSize > 0)
      }
    }
  }
}
