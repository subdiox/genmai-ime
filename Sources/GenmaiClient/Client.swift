// Port of mozc/src/client/client.{h,cc} (3.35.6354).
//
// The C++ `Client` serializes `commands::Input` and sends it to mozc_server over IPC. The Swift port runs the
// session layer in the same process: `InProcessClient` builds exactly the same `Input` messages
// (CREATE_SESSION with capability / application info, SEND_KEY, TEST_SEND_KEY, SEND_COMMAND, GET_CONFIG, ...)
// and hands them to a `SessionBackend` (`SessionHandlerBackend`, which wraps GenmaiSession's
// `SessionHandler::EvalCommand`). The session id bookkeeping and the history playback (used when the session is
// lost and re-created) are kept; the IPC/version/server-launch states are reduced to "backend available" or
// "fatal".

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import GenmaiSession

public typealias Input = Genmai_Commands_Input

/// The in-process replacement of the IPC server: evaluates one `commands::Input`.
/// Mirrors `SessionHandlerInterface::EvalCommand(commands::Command*)`.
@MainActor
public protocol SessionBackend: AnyObject, Sendable {
  /// Returns the output for `input`, or nil if the backend failed (the C++ IPC call failed).
  func evalCommand(_ input: Input) -> Output?
}

/// Extracts the sorted keys that are handled in the direct (IME off) mode from the config
/// (`KeyInfoUtil::ExtractSortedDirectModeKeys`, injectable for tests).
public typealias DirectModeKeysExtractor = @MainActor (Config) -> [KeyInformation]

@MainActor
public final class InProcessClient: GenmaiClientProtocol {
  enum ServerStatus: Int, Comparable {
    case serverUnknown = 0
    case serverShutdown
    case serverInvalidSession
    case serverOk
    case serverTimeout
    case serverVersionMismatch
    case serverBrokenMessage
    case serverFatal

    static func < (lhs: ServerStatus, rhs: ServerStatus) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  static let kMaxPlayBackSize = 512  // size of maximum history

  private let backend: any SessionBackend
  private let directModeKeysExtractor: DirectModeKeysExtractor
  private let toolLauncher: (any ToolLauncher)?
  private let browserOpener: @MainActor (String) -> Bool

  private(set) var id: UInt64 = 0
  private(set) var serverStatus: ServerStatus = .serverUnknown
  private var clientCapability = Capability()
  private var preferences: Config?
  private var request: Genmai_Commands_Request?
  private var directModeKeys: [KeyInformation]
  private(set) var historyInputs: [Input] = []
  private var lastMode: Genmai_Commands_CompositionMode = .direct

  public init(
    backend: any SessionBackend,
    initialConfig: Config,
    directModeKeysExtractor: @escaping DirectModeKeysExtractor = { KeyInfoUtil.extractSortedDirectModeKeys($0) },
    toolLauncher: (any ToolLauncher)? = nil,
    browserOpener: @escaping @MainActor (String) -> Bool = { _ in false }
  ) {
    self.backend = backend
    self.directModeKeysExtractor = directModeKeysExtractor
    self.toolLauncher = toolLauncher
    self.browserOpener = browserOpener
    // Initialize direct_mode_keys_
    self.directModeKeys = directModeKeysExtractor(initialConfig)
  }

  deinit {
    // Client::~Client deletes the session. deinit is not isolated, so the deletion is scheduled on the
    // main actor (the backend outlives the clients).
    let id = self.id
    let backend = self.backend
    if id != 0 {
      Task { @MainActor in
        var input = Input()
        input.id = id
        input.type = .deleteSession
        _ = backend.evalCommand(input)
      }
    }
  }

  /// Re-extracts the direct mode keys, e.g. after another process (GenmaiTool) changed the keymap.
  public func updateDirectModeKeys(_ config: Config) {
    directModeKeys = directModeKeysExtractor(config)
  }

  // MARK: - Session management

  public func isValidRunLevel() -> Bool { RunLevel.isValidClientRunLevel() }

  public func ensureConnection() -> Bool {
    switch serverStatus {
    case .serverOk, .serverInvalidSession:
      return true
    case .serverFatal, .serverTimeout, .serverBrokenMessage, .serverVersionMismatch:
      serverStatus = .serverFatal
      return false
    case .serverShutdown, .serverUnknown:
      // StartServer(): the in-process backend is always available.
      serverStatus = .serverInvalidSession
      return true
    }
  }

  public func ensureSession() -> Bool {
    if !ensureConnection() {
      return false
    }
    if serverStatus == .serverOk {
      return true
    }
    if !createSession() {
      _ = ensureConnection()
      return false
    }
    // Call SET_REQUEST if request_ is not nullptr.
    if let request {
      var input = Input()
      input.id = id
      input.type = .setRequest
      input.request = request
      _ = call(input)
    }
    serverStatus = .serverOk
    return true
  }

  public func checkVersionOrRestartServer() -> Bool {
    var input = Input()
    input.type = .noOperation
    if call(input) == nil {
      return ensureConnection()
    }
    return true
  }

  private func createSession() -> Bool {
    id = 0
    var input = Input()
    input.type = .createSession
    input.capability = clientCapability
    input.applicationInfo.processID = UInt32(ProcessInfo.processInfo.processIdentifier)
    input.applicationInfo.threadID = 0
    guard let output = call(input) else {
      return false
    }
    if output.errorCode != .sessionSuccess {
      serverStatus = .serverInvalidSession
      return false
    }
    id = output.id
    return true
  }

  @discardableResult
  public func deleteSession() -> Bool {
    if id == 0 {
      return true
    }
    var input = Input()
    initInput(&input)
    input.type = .deleteSession
    if call(input) == nil {
      return false
    }
    id = 0
    return true
  }

  // MARK: - Commands

  public func sendKey(_ key: KeyEvent, context: Context?) -> Output? {
    var input = Input()
    input.type = .sendKey
    input.key = key
    // If the pointer of |context| is not the default_instance, update the data.
    if let context {
      input.context = context
    }
    return ensureCallCommand(&input)
  }

  public func testSendKey(_ key: KeyEvent, context: Context?) -> Output? {
    var input = Input()
    input.type = .testSendKey
    // If the pointer of |context| is not the default_instance, update the data.
    if let context {
      input.context = context
    }
    input.key = key
    return ensureCallCommand(&input)
  }

  public func sendCommand(_ command: SessionCommand, context: Context?) -> Output? {
    var input = Input()
    input.type = .sendCommand
    input.command = command
    // If the pointer of |context| is not the default_instance, update the data.
    if let context {
      input.context = context
    }
    return ensureCallCommand(&input)
  }

  private func ensureCallCommand(_ input: inout Input) -> Output? {
    if !ensureSession() {
      return nil
    }
    initInput(&input)
    var output = call(input)
    if output != nil, output?.id != input.id {
      // Session id is void. re-issue session id.
      serverStatus = .serverInvalidSession
    }
    if serverStatus >= .serverTimeout {
      return nil
    }
    if serverStatus == .serverShutdown || serverStatus == .serverInvalidSession {
      guard ensureSession() else { return nil }
      // playback the history to restore the previous state.
      playbackHistory()
      initInput(&input)
      output = call(input)
      if output == nil {
        historyInputs.append(input)
        resetHistory()
        return nil
      }
    }
    guard let output else { return nil }
    pushHistory(input, output)
    return output
  }

  public func isDirectModeCommand(_ key: KeyEvent) -> Bool {
    KeyInfoUtil.containsKey(directModeKeys, key)
  }

  public func getConfig() -> Config? {
    var input = Input()
    initInput(&input)
    input.type = .getConfig
    guard let output = call(input), output.hasConfig else {
      return nil
    }
    return output.config
  }

  public func setConfig(_ config: Config) -> Bool {
    var input = Input()
    initInput(&input)
    input.type = .setConfig
    input.config = config
    if call(input) == nil {
      return false
    }
    directModeKeys = directModeKeysExtractor(config)
    return true
  }

  public func clearUserHistory() -> Bool { callCommand(.clearUserHistory) }
  public func clearUserPrediction() -> Bool { callCommand(.clearUserPrediction) }
  public func shutdown() -> Bool { callCommand(.shutdown) }
  public func syncData() -> Bool { callCommand(.syncData) }
  public func reload() -> Bool { callCommand(.reload) }
  public func cleanup() -> Bool { callCommand(.cleanup) }
  public func noOperation() -> Bool { callCommand(.noOperation) }

  public func reset() {
    serverStatus = .serverUnknown
  }

  public func pingServer() -> Bool {
    var input = Input()
    initInput(&input)
    input.type = .noOperation
    return backend.evalCommand(input) != nil
  }

  public func enableCascadingWindow(_ enable: Bool) {
    if preferences == nil {
      preferences = Config()
    }
    preferences?.useCascadingWindow = enable
  }

  public func setSuppressErrorDialog(_ suppress: Bool) {}

  public func setClientCapability(_ capability: Capability) {
    clientCapability = capability
  }

  /// Mirrors `Client::InitRequestForSvsJapanese`.
  public func initRequestForSvsJapanese(_ useSvs: Bool) {
    var request = Genmai_Commands_Request()
    let params = Genmai_Commands_DecoderExperimentParams()
    var variationTypes = params.variationCharacterTypes
    let svs = UInt32(Genmai_Commands_DecoderExperimentParams.VariationCharacterType.svsJapanese.rawValue)
    if useSvs {
      variationTypes |= svs
    } else {
      variationTypes &= ~svs
    }
    request.decoderExperimentParams.variationCharacterTypes = variationTypes
    self.request = request
  }

  public func launchTool(mode: String, extraArg: String) -> Bool {
    if !isValidRunLevel() {
      return false
    }
    // Validate |mode|.
    let kModeMaxSize = 32
    if mode.isEmpty || mode.utf8.count >= kModeMaxSize {
      return false
    }
    return toolLauncher?.launchTool(mode: mode, extraArg: extraArg, environment: [:]) ?? false
  }

  public func launchToolWithProtoBuf(_ output: Output) -> Bool {
    guard output.hasLaunchToolMode, let mode = ToolMode(output.launchToolMode) else {
      return false
    }
    // TODO(nona): extends output message to support extra argument.
    return launchTool(mode: mode.rawValue, extraArg: "")
  }

  public func openBrowser(_ url: String) -> Bool {
    if !isValidRunLevel() {
      return false
    }
    return browserOpener(url)
  }

  // MARK: - Internals

  private func callCommand(_ type: Input.CommandType) -> Bool {
    var input = Input()
    initInput(&input)
    input.type = type
    return call(input) != nil
  }

  private func call(_ input: Input) -> Output? {
    // don't repeat Call() if the status is either
    // SERVER_FATAL, SERVER_TIMEOUT, or SERVER_BROKEN_MESSAGE
    if serverStatus >= .serverTimeout {
      return nil
    }
    guard let output = backend.evalCommand(input) else {
      // server crash
      if serverStatus != .serverUnknown {
        serverStatus = .serverShutdown
      }
      return nil
    }
    return output
  }

  private func initInput(_ input: inout Input) {
    input.id = id
    if let preferences {
      input.config = preferences
    }
  }

  private func playbackHistory() {
    if historyInputs.count >= Self.kMaxPlayBackSize {
      resetHistory()
      return
    }
    for i in historyInputs.indices {
      historyInputs[i].id = id
      if call(historyInputs[i]) == nil {
        break
      }
    }
  }

  private func pushHistory(_ input: Input, _ output: Output) {
    if !output.hasConsumed || !output.consumed {
      // Do not remember unconsumed input.
      return
    }
    // Update mode
    if output.hasMode {
      lastMode = output.mode
    }
    // don't insert a new input when history_inputs_.size()
    // reaches to the maximum size. This prevents DOS attack.
    if historyInputs.count < Self.kMaxPlayBackSize {
      historyInputs.append(input)
    }
    // found context boundary.
    if input.type == .sendKey && output.hasResult {
      resetHistory()
    }
  }

  /// Clear the history and push IMEOn command for initialize session.
  private func resetHistory() {
    historyInputs.removeAll()
    // On Mac, we should send ON key at the first of each input session
    // excepting the very first session, because when the session is restored,
    // its state is direct.
    if lastMode != .direct {
      var input = Input()
      input.type = .sendKey
      input.key.specialKey = .on
      input.key.mode = lastMode
      historyInputs.append(input)
    }
  }
}
