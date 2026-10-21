// Port of mozc/src/prediction/handwriting_decoder_test.cc (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private func findResultByKeyValue(
  _ results: [PredictionResult], _ key: String, _ value: String
) -> Bool {
  results.contains { $0.key.bytesEqual(key) && $0.value.bytesEqual(value) && !$0.removed }
}

private func compositionEvent(_ s: String, _ probability: Double)
  -> Genmai_Commands_SessionCommand.CompositionEvent
{
  var e = Genmai_Commands_SessionCommand.CompositionEvent()
  e.compositionString = s
  e.probability = probability
  return e
}

private func reverseResult(_ key: String, _ value: String) -> PredictionResult {
  var result = PredictionResult()
  result.key = key
  result.value = value
  return result
}

@Suite(.enabled(if: predictionMockDataAvailable, "mock_genmai.data is missing"))
struct HandwritingDecoderTests {
  var config = PT.config()
  var request = Genmai_Commands_Request()
  var composer: Composer
  let realtimeDecoder = PredictionMockRealtimeDecoder()

  init() {
    composer = Composer(PT.tableFromFile("system://12keys-hiragana.tsv"), request, config)
  }

  private func makeDecoder(_ dict: MockDictionary) throws -> HandwritingDecoder {
    let modules = try PredictionTestModules.mock(dictionary: dict)
    return HandwritingDecoder(modules, realtimeDecoder)
  }

  private func createPredictionRequest(_ key: String) -> ConversionRequest {
    ConversionRequestBuilder()
      .setComposer(composer)
      .setRequest(request)
      .setConfig(config)
      .setKey(key)
      .setRequestType(.prediction)
      .build()
  }

  /// `EXPECT_CALL(ReverseDecode(Truly(...))).WillOnce(Return({result}))`.
  private func expectReverseDecode(_ key: String, _ result: PredictionResult) {
    var called = 0
    realtimeDecoder.reverseDecodeHandler = { request in
      #expect(request.requestType() == .reverseConversion)
      #expect(request.key() == key)
      called += 1
      #expect(called == 1)
      return [result]
    }
  }

  @Test func nonHandwritingRequestReturnsEmpty() throws {
    let decoder = try makeDecoder(MockDictionary())
    let request = ConversionRequest()
    #expect(decoder.decode(request).isEmpty)
  }

  @Test mutating func handwriting() throws {
    let kCostOffset: Int32 = 3000

    // Handwriting request
    RequestTestUtil.fillMobileRequestForHandwriting(&request)
    request.decoderExperimentParams.maxCompositionEventToProcess = 1
    request.decoderExperimentParams.handwritingConversionCandidateCostOffset = kCostOffset
    composer.reset()
    composer.setCompositionsForHandwriting([
      compositionEvent("かん字じ典", 0.99), compositionEvent("かlv字じ典", 0.01),
    ])

    // reverse conversion
    expectReverseDecode("かん字じ典", reverseResult("かん字じ典", "かんじじてん"))

    let dict = KeyedMockDictionary()
    dict.exact.on(
      "かんじじてん",
      kv: [
        ("かんじじてん", "漢字辞典"),
        ("かんじじてん", "漢字字典"),
        ("かんじじてん", "感じじてん"),
        ("かんじじてん", "幹事時点"),
        ("かんじじてん", "換字字典"),
        ("かんじじてん", "換字自転"),
        ("かんじじてん", "換字じてん"),
      ])
    let decoder = try makeDecoder(dict.mock)

    let results = decoder.decode(createPredictionRequest("かん字じ典"))
    #expect(results.count >= 5)

    // composition from handwriting output
    #expect(findResultByKeyValue(results, "かんじじてん", "かん字じ典"))
    #expect(findResultByKeyValue(results, "かlv字じ典", "かlv字じ典"))
    // look-up results
    #expect(findResultByKeyValue(results, "かんじじてん", "漢字辞典"))
    #expect(findResultByKeyValue(results, "かんじじてん", "漢字字典"))
    #expect(findResultByKeyValue(results, "かんじじてん", "換字字典"))

    for result in results {
      if result.value == "かん字じ典" {
        // Top recognition result
        #expect(result.wcost == 0)
      } else if result.key == "かんじじてん" {
        #expect(result.wcost >= Int(kCostOffset))
      }
    }
  }

  @Test mutating func handwritingT13N() throws {
    // Handwriting request
    RequestTestUtil.fillMobileRequestForHandwriting(&request)
    request.decoderExperimentParams.maxCompositionEventToProcess = 1
    composer.reset()
    composer.setCompositionsForHandwriting([
      compositionEvent("キた", 0.99), compositionEvent("もた", 0.01),
    ])

    // reverse conversion
    expectReverseDecode("キた", reverseResult("きた", "きた"))  // T13N key can be looked up

    let dict = KeyedMockDictionary()
    dict.exact.on("きた", kv: [("きた", "きた"), ("きた", "北")])
    let decoder = try makeDecoder(dict.mock)

    let results = decoder.decode(createPredictionRequest("キタ"))

    #expect(results.count >= 2)
    // composition from handwriting output
    #expect(findResultByKeyValue(results, "きた", "キた"))
    #expect(findResultByKeyValue(results, "もた", "もた"))
  }

  @Test mutating func handwritingNoHiragana() throws {
    // Handwriting request
    RequestTestUtil.fillMobileRequestForHandwriting(&request)
    request.decoderExperimentParams.maxCompositionEventToProcess = 1
    composer.reset()
    composer.setCompositionsForHandwriting([compositionEvent("南", 0.9)])

    // reverse conversion will not be called
    let dict = MockDictionary()
    let decoder = try makeDecoder(dict)

    let results = decoder.decode(createPredictionRequest("南"))
    #expect(realtimeDecoder.reverseDecodeCount == 0)
    #expect(dict.calls["LookupPredictive", default: 0] == 0)
    #expect(dict.calls["LookupExact", default: 0] == 0)
    #expect(results.count >= 1)
    // composition from handwriting output
    #expect(findResultByKeyValue(results, "南", "南"))
  }

  @Test mutating func handwritingRealtime() throws {
    // Handwriting request
    RequestTestUtil.fillMobileRequestForHandwriting(&request)
    request.decoderExperimentParams.maxCompositionEventToProcess = 1
    composer.reset()
    composer.setCompositionsForHandwriting([compositionEvent("ばらが", 0.9)])

    // Reverse conversion
    expectReverseDecode("ばらが", reverseResult("ばらが", "ばらが"))

    let dict = KeyedMockDictionary()
    dict.exact.on("ばらが", kv: [("ばらが", "薔薇が")])
    let decoder = try makeDecoder(dict.mock)

    let results = decoder.decode(createPredictionRequest("ばらが"))
    #expect(results.count >= 1)
    #expect(findResultByKeyValue(results, "ばらが", "薔薇が"))
  }
}
