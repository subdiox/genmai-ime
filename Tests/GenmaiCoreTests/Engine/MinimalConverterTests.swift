// Tests of mozc/src/engine/minimal_converter.{h,cc} (3.35.6354) and the engine
// factories (oss_engine_factory.h, eval_engine_factory.{h,cc},
// mock_data_engine_factory.{h,cc}). Mozc has no tests of its own for these
// files; these are Swift-only.

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

struct MinimalConverterTests {
  private func conversionRequest(_ key: String, _ type: RequestType)
    -> ConversionRequest
  {
    var composer = Composer(Genmai_Commands_Request(), ConfigHandler.defaultConfig())
    composer.setPreeditTextForTestOnly(key)
    var options = ConversionOptions()
    options.requestType = type
    return ConversionRequestBuilder().setComposer(composer).setOptions(options).build()
  }

  @Test func addsAsIsCandidate() {
    let converter = createMinimalConverter()
    let segments = Segments()
    #expect(converter.startConversion(conversionRequest("あいう", .conversion), segments))
    #expect(segments.segmentsSize == 1)
    let candidate = segments.segment(0).candidate(0)
    #expect(candidate.key == "あいう")
    #expect(candidate.value == "あいう")
    #expect(candidate.contentKey == "あいう")
    #expect(candidate.contentValue == "あいう")
    #expect(candidate.lid == 0 && candidate.rid == 0 && candidate.cost == 0)

    #expect(converter.startPrediction(conversionRequest("かき", .prediction), segments))
    #expect(segments.segmentsSize == 1)
    #expect(segments.segment(0).candidate(0).value == "かき")
  }

  @Test func emptyKeyFails() {
    let converter = createMinimalConverter()
    let segments = Segments()
    #expect(!converter.startConversion(conversionRequest("", .conversion), segments))
    #expect(!converter.startReverseConversion(segments, "漢字"))
    #expect(converter.commitSegmentValue(segments, 0, 0))
    #expect(converter.focusSegmentValue(segments, 0, 0))
    #expect(converter.reconstructHistory(segments, "前"))
  }
}

@Suite(.enabled(if: EngineTestSupport.hasData, "genmai.data / mock_genmai.data is missing"))
struct EngineFactoryTests {
  @Test func ossEngineFactory() throws {
    try SystemUtil.withTempUserProfile { _ in
      let engine = try EngineFactory.create()
      #expect(engine.getDataVersion() == (try OssDataManager.create().getDataVersion()))
    }
  }

  @Test func mockDataEngineFactory() throws {
    try SystemUtil.withTempUserProfile { _ in
      let engine = try MockDataEngineFactory.create()
      #expect(engine.getDataVersion() == (try MockDataManager.create().getDataVersion()))
    }
  }

  @Test func evalEngineFactory() throws {
    try SystemUtil.withTempUserProfile { _ in
      let engine = try createEvalEngine(EngineTestSupport.ossDataPath, "oss")
      #expect(engine.getDataVersion() == (try OssDataManager.create().getDataVersion()))
      #expect(throws: (any Error).self) {
        try createEvalEngine("file_does_not_exist", "oss")
      }
    }
  }
}
