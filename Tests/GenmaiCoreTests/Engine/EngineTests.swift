// Port of mozc/src/engine/engine_test.cc (3.35.6354).
//
// Deviations from C++:
// - EngineReloadRequest.magic_number is a proto string; the OSS magic number
//   "\xEFMOZC\r\n" is written as "\u{EF}MOZC\r\n" (see DataLoader).
// - The data sets are Data/mock_genmai.data and Data/genmai.data; the tests are
//   disabled when they are missing.
// - Every test runs with a temporary user profile.
// - MaybeReloadEngine does not wait for the data loader (C++ does with
//   SetAlwaysWaitForTesting(true)); the tests await `waitForDataLoader()`
//   before it instead.

import Foundation
import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private final class SupplementalModelForTesting: SupplementalModelStub, @unchecked Sendable {
  private(set) var loadAsyncCount = 0
  private(set) var clearOldModelsCount = 0
  private(set) var lastRequest = Genmai_EngineReloadRequest()

  override func loadAsync(_ request: Genmai_EngineReloadRequest) -> Bool {
    loadAsyncCount += 1
    lastRequest = request
    return true
  }

  override func clearOldModels() { clearOldModelsCount += 1 }
}

private let kMockMagicNumber = "MOCK"
private let kOssMagicNumber = "\u{EF}MOZC\r\n"
private let kMiddlePriority: Int32 = 50

enum EngineTestSupport {
  static var hasData: Bool { DataManagerTestSupport.hasMockData && DataManagerTestSupport.hasOssData }

  static var mockDataPath: String { MockDataManager.defaultDataPath ?? "" }
  static var ossDataPath: String { OssDataManager.defaultDataPath }

  static func request(_ path: String, _ magic: String, _ priority: Int32) -> Genmai_EngineReloadRequest {
    var request = Genmai_EngineReloadRequest()
    request.filePath = path
    request.magicNumber = magic
    request.priority = priority
    return request
  }
}

@Suite(.serialized, .enabled(if: EngineTestSupport.hasData, "genmai.data / mock_genmai.data is missing"))
struct EngineTests {
  let mockRequest = EngineTestSupport.request(
    EngineTestSupport.mockDataPath, kMockMagicNumber, kMiddlePriority)
  let ossRequest = EngineTestSupport.request(
    EngineTestSupport.ossDataPath, kOssMagicNumber, kMiddlePriority)
  let invalidPathRequest = EngineTestSupport.request(
    DataManagerTestSupport.sourcePath("data_manager", "invalid", "genmai.data"), kOssMagicNumber,
    kMiddlePriority)
  let invalidDataRequest = EngineTestSupport.request(
    EngineTestSupport.mockDataPath, kOssMagicNumber, kMiddlePriority)
  let mockVersion: String
  let ossVersion: String

  init() throws {
    mockVersion = try DataManager.createFromFile(
      mockRequest.filePath, magic: DataLoader.magicNumberBytes(mockRequest.magicNumber)
    ).getDataVersion()
    ossVersion = try DataManager.createFromFile(
      ossRequest.filePath, magic: DataLoader.magicNumberBytes(ossRequest.magicNumber)
    ).getDataVersion()
  }

  private func makeEngine() -> Engine {
    Engine.createEngine()
  }

  @Test func reloadModulesTest() async throws {
    try SystemUtil.withTempUserProfile { _ in
      let engine = makeEngine()
      let modules = try Modules.create(MockDataManager())
      try engine.reloadModules(modules)
    }
  }

  /// Tests the interaction with DataLoader for successful Engine reload
  /// event.
  @Test func dataLoadSuccessfulScenarioTest() async {
    await SystemUtil.withTempUserProfile { _ in
      let engine = makeEngine()
      var response = Genmai_EngineReloadResponse()

      // The engine is not updated yet.
      #expect(engine.getDataVersion() != mockVersion)

      // The engine is updated with the request.
      #expect(engine.sendEngineReloadRequest(mockRequest))
      await engine.waitForDataLoader()
      #expect(engine.maybeReloadEngine(&response))
      #expect(engine.getDataVersion() == mockVersion)

      // The engine is not updated with the same request.
      #expect(!engine.sendEngineReloadRequest(mockRequest))
      await engine.waitForDataLoader()
      #expect(!engine.maybeReloadEngine(&response))
      #expect(engine.getDataVersion() == mockVersion)
    }
  }

  /// Tests situations to handle multiple new requests.
  @Test func dataUpdateSuccessfulScenarioTest() async {
    await SystemUtil.withTempUserProfile { _ in
      let engine = makeEngine()
      var response = Genmai_EngineReloadResponse()

      // Send a request, and update the engine.
      #expect(engine.sendEngineReloadRequest(mockRequest))
      await engine.waitForDataLoader()
      #expect(engine.maybeReloadEngine(&response))
      #expect(engine.getDataVersion() == mockVersion)

      // Send another request, and update the engine again.
      #expect(engine.sendEngineReloadRequest(ossRequest))
      await engine.waitForDataLoader()
      #expect(engine.maybeReloadEngine(&response))
      #expect(engine.getDataVersion() == ossVersion)
      #expect(response.status == .reloaded)
    }
  }

  /// Tests the interaction with DataLoader in the situation where requested
  /// data is broken.
  @Test func reloadInvalidDataTest() async {
    await SystemUtil.withTempUserProfile { _ in
      let engine = makeEngine()
      #expect(engine.sendEngineReloadRequest(invalidPathRequest))

      // The new request is performed, but it returns invalid data.
      var response = Genmai_EngineReloadResponse()
      await engine.waitForDataLoader()
      #expect(!engine.maybeReloadEngine(&response))

      // Sends the same request again, but the request is already marked as
      // unregistered.
      #expect(!engine.sendEngineReloadRequest(invalidPathRequest))
      await engine.waitForDataLoader()
      #expect(!engine.maybeReloadEngine(&response))
    }
  }

  /// Tests the rollback scenario.
  @Test func rollbackDataTest() async {
    await SystemUtil.withTempUserProfile { _ in
      let engine = makeEngine()
      // Sends multiple requests three times.
      #expect(engine.sendEngineReloadRequest(mockRequest))
      #expect(engine.sendEngineReloadRequest(invalidPathRequest))
      #expect(engine.sendEngineReloadRequest(invalidDataRequest))

      // The last two requests are invalid. The first request is immediately
      // used as a fallback.
      var response = Genmai_EngineReloadResponse()
      await engine.waitForDataLoader()
      #expect(engine.maybeReloadEngine(&response))
      #expect(response.request.filePath == mockRequest.filePath)

      // DataVersion comes from the first request (i.e. mock_request_).
      #expect(engine.getDataVersion() == mockVersion)
    }
  }

  @Test func supplementalModelReloadTest() async throws {
    try SystemUtil.withTempUserProfile { _ in
      let engine = makeEngine()
      // Requests sent while converter_ is nullptr are deferred, keeping the
      // latest.
      #expect(engine.sendSupplementalModelReloadRequest(mockRequest))
      #expect(engine.sendSupplementalModelReloadRequest(ossRequest))
      engine.clearOldSupplementalModels()

      let supplementalModel = SupplementalModelForTesting()
      let modules = try ModulesPresetBuilder()
        .presetSupplementalModel(supplementalModel)
        .build(MockDataManager())
      try engine.reloadModules(modules)

      // The pending latest request is loaded upon converter_ initialization.
      #expect(supplementalModel.loadAsyncCount == 1)
      #expect(supplementalModel.lastRequest.filePath == ossRequest.filePath)

      // Subsequent requests after converter_ is initialized are loaded
      // immediately.
      #expect(engine.sendSupplementalModelReloadRequest(mockRequest))
      #expect(supplementalModel.loadAsyncCount == 2)
      #expect(supplementalModel.lastRequest.filePath == mockRequest.filePath)
      engine.clearOldSupplementalModels()
      #expect(supplementalModel.clearOldModelsCount == 1)
    }
  }

  // MARK: - Swift only

  /// Engine without modules uses the minimal converter and the default data
  /// version.
  @Test func uninitializedEngineUsesMinimalConverter() async {
    let engine = Engine.createEngine()
    #expect(engine.getDataVersion() == "0.0.0")
    #expect(engine.getPosList().isEmpty)
    #expect(!engine.reload())
    #expect(!engine.sync())
    #expect(!(await engine.wait()))
    #expect(engine.clearUserHistory())
    #expect(!engine.clearUserPrediction())
    #expect(!engine.addUserHistory("きょう", "今日"))
    #expect(engine.getConverterImpl() == nil)
  }

  @Test func createEngineFromDataManager() async throws {
    try await SystemUtil.withTempUserProfile { _ in
      let engine = try Engine.createEngine(MockDataManager())
      #expect(engine.getDataVersion() == mockVersion)
      #expect(!engine.getPosList().isEmpty)
      #expect(engine.getConverterImpl() != nil)
      #expect(await engine.reloadAndWait())
      #expect(engine.sync())
      #expect(engine.clearUserPrediction())
      _ = engine.createEngineConverter()
    }
  }
}
