// Test double of GenmaiClientProtocol for the config dialog tests (client/client_mock.h).

import GenmaiClient
import GenmaiProtocol

@MainActor
final class ConfigDialogMockClient: GenmaiClientProtocol {
  var config: Genmai_Config_Config?
  var setConfigResult = true
  var clearUserHistoryResult = true
  var clearUserPredictionResult = true
  private(set) var setConfigCalls: [Genmai_Config_Config] = []
  private(set) var clearUserHistoryCount = 0
  private(set) var clearUserPredictionCount = 0
  private(set) var launchedTools: [String] = []
  private(set) var reloadCount = 0

  init(config: Genmai_Config_Config? = Genmai_Config_Config()) {
    self.config = config
  }

  func isValidRunLevel() -> Bool { true }
  func ensureConnection() -> Bool { true }
  func ensureSession() -> Bool { true }
  func checkVersionOrRestartServer() -> Bool { true }
  func sendKey(_ key: KeyEvent, context: Context?) -> Output? { nil }
  func testSendKey(_ key: KeyEvent, context: Context?) -> Output? { nil }
  func sendCommand(_ command: SessionCommand, context: Context?) -> Output? { nil }
  func isDirectModeCommand(_ key: KeyEvent) -> Bool { false }
  func getConfig() -> Config? { config }
  func setConfig(_ config: Config) -> Bool {
    setConfigCalls.append(config)
    if setConfigResult {
      self.config = config
    }
    return setConfigResult
  }
  func clearUserHistory() -> Bool {
    clearUserHistoryCount += 1
    return clearUserHistoryResult
  }
  func clearUserPrediction() -> Bool {
    clearUserPredictionCount += 1
    return clearUserPredictionResult
  }
  func shutdown() -> Bool { true }
  func syncData() -> Bool { true }
  func reload() -> Bool {
    reloadCount += 1
    return true
  }
  func cleanup() -> Bool { true }
  func reset() {}
  func pingServer() -> Bool { true }
  func noOperation() -> Bool { true }
  func enableCascadingWindow(_ enable: Bool) {}
  func setSuppressErrorDialog(_ suppress: Bool) {}
  func setClientCapability(_ capability: Capability) {}
  func openApp(mode: String, extraArg: String) -> Bool {
    launchedTools.append(mode)
    return true
  }
  func openAppWithProtoBuf(_ output: Output) -> Bool { false }
  func openBrowser(_ url: String) -> Bool { false }
}
