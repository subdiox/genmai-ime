// Port of mozc/src/prediction/single_kanji_decoder_test.cc (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private func findResultByKey(_ results: [PredictionResult], _ key: String) -> Bool {
  results.contains { $0.key.bytesEqual(key) && !$0.removed }
}

@Suite(.enabled(if: predictionMockDataAvailable, "mock_genmai.data is missing"))
struct SingleKanjiDecoderTests {
  let modules: PredictionTestModules
  var composer: Composer
  var config: Genmai_Config_Config
  var request: Genmai_Commands_Request

  init() throws {
    modules = try PredictionTestModules.mock()
    request = Genmai_Commands_Request()
    RequestTestUtil.fillMobileRequest(&request)
    config = PT.config()
    composer = Composer(Table.getSharedDefaultTable(), request, config)
  }

  private func createConversionRequest() -> ConversionRequest {
    var options = ConversionOptions()
    options.requestType = .prediction
    return ConversionRequestBuilder()
      .setComposer(composer)
      .setRequestView(request)
      .setConfigView(config)
      .setOptions(options)
      .build()
  }

  private var posMatcher: PosMatcher { modules.getPosMatcher() }

  private func aggregator() -> SingleKanjiDecoder {
    SingleKanjiDecoder(posMatcher, modules.getSingleKanjiDictionary())
  }

  @Test mutating func noResult() {
    composer.setPreeditTextForTestOnly("ん")
    let results = aggregator().decode(createConversionRequest())
    #expect(results.isEmpty)
  }

  @Test mutating func noResultForHardwareKeyboard() {
    composer.setPreeditTextForTestOnly("あけぼのの")
    RequestTestUtil.fillMobileRequestWithHardwareKeyboard(&request)
    let results = aggregator().decode(createConversionRequest())
    #expect(results.count == 0)
  }

  @Test mutating func resultsFromPrefix() {
    composer.setPreeditTextForTestOnly("あけぼのの")
    let results = aggregator().decode(createConversionRequest())
    #expect(results.count > 1)
    #expect(findResultByKey(results, "あけぼの"))
    #expect(findResultByKey(results, "あけ"))
    for i in 0..<results.count {
      if results[i].key == "あけぼの" {
        #expect(results[i].wcost == i)
      } else {
        #expect(results[i].wcost > i)  // Cost offset should be added
      }
    }
  }

  @Test mutating func result() throws {
    composer.setPreeditTextForTestOnly("あけぼの")
    let results = aggregator().decode(createConversionRequest())
    try #require(results.count > 1)
    let result = results[0]
    #expect(result.key == "あけぼの")
    #expect((result.attributes & Attribute.singleKanji) != 0)
    #expect(result.lid == posMatcher.getGeneralSymbolId())
    #expect(result.rid == posMatcher.getGeneralSymbolId())
    #expect((result.attributes & Attribute.partiallyKeyConsumed) == 0)
    #expect(result.consumedKeySize == 0)
  }

  @Test mutating func prefixResult() throws {
    composer.setPreeditTextForTestOnly("あけぼのの")
    let results = aggregator().decode(createConversionRequest())
    try #require(results.count > 1)
    let result = results[0]
    #expect(result.key == "あけぼの")
    #expect((result.attributes & Attribute.singleKanji) != 0)
    #expect(result.lid == posMatcher.getGeneralSymbolId())
    #expect(result.rid == posMatcher.getGeneralSymbolId())
    #expect((result.attributes & Attribute.partiallyKeyConsumed) != 0)
    #expect(Int(result.consumedKeySize) == Util.charsLen("あけぼの"))
  }

  @Test mutating func noPrefixResult() {
    request.autoPartialSuggestion = false
    composer.setPreeditTextForTestOnly("あけぼのの")
    let results = aggregator().decode(createConversionRequest())
    #expect(results.count == 0)  // No "あけぼの"
  }

  @Test mutating func svsVariation() {
    composer.setPreeditTextForTestOnly("かみ")
    request.decoderExperimentParams.variationCharacterTypes = UInt32(
      Genmai_Commands_DecoderExperimentParams.VariationCharacterType.svsJapanese.rawValue)
    let results = aggregator().decode(createConversionRequest())
    #expect(results.count > 1)

    func contains(_ value: String) -> Bool {
      results.contains { $0.value.bytesEqual(value) }
    }
    #expect(contains("\u{795E}\u{FE00}"))  // 神︀ SVS character.
    #expect(!contains("\u{FA19}"))  // 神 CJK compat ideograph.
  }
}
