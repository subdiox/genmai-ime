// Port of mozc/src/session/session_handler.{h,cc} (3.35.6354).
//
// Session Handler of Mozc server.
// Migrated from ipc/interpreter and session/session_manager
//
// Swift notes:
// - The absl flags (--timeout, --max_session_size, ...) are
//   `SessionHandler.flags` (process-wide, lock-protected).
// - `shared_ptr<const Config>` identity checks are value comparisons.
// - The session watch dog needs a client; `startWatchDog(client:)` takes one
//   (see SessionWatchDog.swift). Process liveness checks use kill(pid, 0).
// - `evalCommand` never blocks: SYNC_DATA, SHUTDOWN and RELOAD_AND_WAIT do not
//   wait for the engine (engine_->Wait()); callers await `waitForEngine()`.
//   The engine's background tasks run one at a time in order, so later
//   commands still see their effects in order.

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import GenmaiStorage
import Synchronization

/// The absl flags defined in session_handler.cc.
public struct SessionHandlerFlags: Sendable {
  /// server timeout. if sessions get empty for "timeout", shutdown message is
  /// automatically emitted
  public var timeout: Int32 = -1
  /// maximum sessions size. if size of sessions reaches to "max_session_size",
  /// oldest session is removed
  public var maxSessionSize: Int32 = 64
  /// minimum interval (sec) for create session
  public var createSessionMinInterval: Int32 = 0
  /// watch dog timer intaval (sec)
  public var watchDogInterval: Int32 = 180
  /// remove session if it is not accessed for "last_command_timeout" sec
  public var lastCommandTimeout: Int32 = 3600
  /// remove session if it is not accessed for "last_create_session_timeout"
  /// sec after create session command
  public var lastCreateSessionTimeout: Int32 = 300
  /// Launch server with restricted setting
  public var restricted = false

  public init() {}
}

private func isApplicationAlive(_ session: Session) -> Bool {
  let info = session.applicationInfo
  // When the thread/process's current status is unknown, i.e.,
  // if IsThreadAlive/IsProcessAlive functions failed to know the
  // status of the thread/process, return true just in case.
  // Here, we want to kill the session only when the target thread/process
  // are terminated with 100% probability. Otherwise, it's better to do
  // nothing to prevent any side effects.
  if info.hasProcessID {
    // Process::IsProcessAlive(pid, default_result = true)
    let pid = pid_t(truncatingIfNeeded: info.processID)
    if pid == 0 {
      return true
    }
    if kill(pid, 0) == 0 {
      return true
    }
    return errno != ESRCH
  }
  return true
}

public final class SessionHandler {
  private static let flagsStorage = Mutex(SessionHandlerFlags())

  @TaskLocal static var taskLocalFlags: SessionHandlerFlags?

  /// The session_handler absl flags (task-local override first).
  public static var flags: SessionHandlerFlags {
    get { taskLocalFlags ?? flagsStorage.withLock { $0 } }
    set { flagsStorage.withLock { $0 = newValue } }
  }

  /// TESTONLY: runs `body` with `flags` installed for the current task only
  /// (absl::FlagSaver + absl::SetFlag in C++ tests).
  public static func withFlagsForTesting<R>(
    _ flags: SessionHandlerFlags, _ body: () throws -> R
  ) rethrows -> R {
    try $taskLocalFlags.withValue(flags, operation: body)
  }

  nonisolated(nonsending) public static func withFlagsForTesting<R>(
    _ flags: SessionHandlerFlags, _ body: nonisolated(nonsending) () async throws -> R
  ) async rethrows -> R {
    try await $taskLocalFlags.withValue(flags, operation: body)
  }

  typealias SessionMap = LruCache<SessionID, Session?>
  typealias SessionElement = SessionMap.Element

  private var sessionMap: SessionMap
  private var sessionWatchDog: SessionWatchDog?
  private var isAvailable = false
  private var maxSessionSize: UInt32 = 0
  private var lastSessionEmptyTime = Date.distantPast
  private var lastCleanupTime = Date.distantPast
  private var lastCreateSessionTime = Date.distantPast

  private var engineImpl: (any EngineInterface)?
  private let tableManager: TableManager

  // config_, request_, and key_map_manager_ are shared with the sessions and
  // updated dynamically via the setter methods.
  private(set) var request: Genmai_Commands_Request
  private(set) var config: Genmai_Config_Config
  private(set) var keyMapManager: KeyMapManager

  private var bitgen = SystemRandomNumberGenerator()

  public init(_ engine: (any EngineInterface)?) {
    engineImpl = engine
    isAvailable = false
    maxSessionSize = 0
    lastSessionEmptyTime = Clock.getAbslTime()
    lastCleanupTime = Date.distantPast
    lastCreateSessionTime = Date.distantPast
    tableManager = TableManager()
    request = Genmai_Commands_Request()
    config = ConfigHandler.getSharedConfig()
    keyMapManager = KeyMapManager(config)

    if SessionHandler.flags.restricted {
      // --restricted is almost always specified when mozc_client is inside Job.
      // The typical case is Startup processes on Vista.
      // On Vista, StartUp processes are in Job for 60 seconds. In order
      // to launch new mozc_server inside sandbox, we set the timeout
      // to be 60sec. Client application hopefully relaunch mozc_server.
      var flags = SessionHandler.flags
      flags.timeout = 60
      flags.maxSessionSize = 8
      flags.watchDogInterval = 15
      flags.lastCreateSessionTimeout = 60
      flags.lastCommandTimeout = 60
      SessionHandler.flags = flags  // (a task-local override takes precedence)
    }

    // Allow [2..128] sessions.
    maxSessionSize = UInt32(min(max(SessionHandler.flags.maxSessionSize, 2), 128))
    sessionMap = SessionMap(Int(maxSessionSize))

    if engineImpl == nil {
      return
    }

    // Everything is OK.
    isAvailable = true
  }

  /// Returns true if SessionHandle is available.
  public func getIsAvailable() -> Bool { isAvailable }

  public var engine: any EngineInterface { engineImpl! }

  public func getDataVersion() -> String { engine.getDataVersion() }

  /// Starts watch dog timer to cleanup sessions.
  public func startWatchDog(client: (any SessionWatchDogClient)? = nil) {
    if sessionWatchDog == nil {
      sessionWatchDog = SessionWatchDog(
        .seconds(Int64(SessionHandler.flags.watchDogInterval)), client, CPUStats())
    }
  }

  /// Update sessions if ConfigHandler::GetSharedConfig() is updated
  /// or `request` is not null. This method doesn't reload the sessions.
  private func updateSessions(_ newRequest: Genmai_Commands_Request? = nil) {
    let currentConfig = ConfigHandler.getSharedConfig()

    let isConfigUpdated = currentConfig != config
    let isKeyManagerUpdated =
      isConfigUpdated && !KeyMapManager.isSameKeyMapManagerApplicable(config, currentConfig)

    if isConfigUpdated {
      config = currentConfig
    }

    if let newRequest {
      request = newRequest
    }

    if isKeyManagerUpdated {
      keyMapManager = KeyMapManager(config)
    }

    let table = tableManager.getTable(request, config)

    for element in sessionMap {
      guard let session = element.value else {
        continue
      }
      session.setConfig(config)
      session.setKeyMapManager(keyMapManager)
      session.setRequest(request)
      session.setTable(table)
    }

    if isConfigUpdated {
      CharacterFormManager.getCharacterFormManager().reloadConfig(config)
    }
  }

  /// Syncs internal data to local file system. C++ also waits for the sync to
  /// finish (engine_->Wait()); evalCommand is synchronous and never blocks, so
  /// callers that need the data on disk await `waitForEngine()` afterwards.
  private func syncData(_ command: inout Genmai_Commands_Command) -> Bool {
    engine.sync()
    return true
  }

  private func shutdown(_ command: inout Genmai_Commands_Command) -> Bool {
    _ = syncData(&command)
    isAvailable = false
    return true
  }

  /// Reloads all the sessions.
  /// Before that, UpdateSessions() is called to update them.
  private func reload(_ command: inout Genmai_Commands_Command) -> Bool {
    updateSessions()
    engine.reload()
    return true
  }

  /// Reloads. C++ also waits for the reloader (engine_->ReloadAndWait());
  /// callers await `waitForEngine()` afterwards (see syncData).
  private func reloadAndWait(_ command: inout Genmai_Commands_Command) -> Bool {
    updateSessions()
    engine.reload()
    return true
  }

  /// Not in C++: waits for the engine's background tasks (the waiting part of
  /// SYNC_DATA, SHUTDOWN and RELOAD_AND_WAIT; engine_->Wait()). Suspends; no
  /// thread is blocked.
  @discardableResult
  public func waitForEngine() async -> Bool {
    await engine.wait()
  }

  private func clearUserHistory(_ command: inout Genmai_Commands_Command) -> Bool {
    engine.clearUserHistory()
    return true
  }

  private func clearUserPrediction(_ command: inout Genmai_Commands_Command) -> Bool {
    engine.clearUserPrediction()
    return true
  }

  private func addUserHistory(_ command: inout Genmai_Commands_Command) -> Bool {
    let userHistoryData = command.input.userHistoryData
    return engine.addUserHistory(userHistoryData.key, userHistoryData.value)
  }

  private func getConfig(_ command: inout Genmai_Commands_Command) -> Bool {
    command.output.config = ConfigHandler.getCopiedConfig()
    // Ensure the on-memory config is same as the locally stored one
    // because the local data could be changed by sync.
    updateSessions()
    return true
  }

  private func setConfig(_ command: inout Genmai_Commands_Command) -> Bool {
    if !command.input.hasConfig {
      GenmaiLog.warning("config is empty")
      return false
    }

    command.output.config = command.input.config
    maybeUpdateConfig(&command)

    return true
  }

  /// Updates all the sessions by UpdateSessions() with given |request|.
  private func setRequest(_ command: inout Genmai_Commands_Command) -> Bool {
    if !command.input.hasRequest {
      GenmaiLog.warning("request is empty")
      return false
    }
    updateSessions(command.input.request)
    return true
  }

  @discardableResult
  public func evalCommand(_ command: inout Genmai_Commands_Command) -> Bool {
    engineImpl?.clearOldSupplementalModels()
    if !isAvailable {
      GenmaiLog.error("SessionHandler is not available.")
      return false
    }

    var evalSucceeded = false

    switch command.input.type {
    case .createSession:
      evalSucceeded = createSession(&command)
    case .deleteSession:
      evalSucceeded = deleteSession(&command)
    case .sendKey:
      evalSucceeded = sendKey(&command)
    case .testSendKey:
      evalSucceeded = testSendKey(&command)
    case .sendCommand:
      evalSucceeded = sendCommand(&command)
    case .syncData:
      evalSucceeded = syncData(&command)
    case .clearUserHistory:
      evalSucceeded = clearUserHistory(&command)
    case .clearUserPrediction:
      evalSucceeded = clearUserPrediction(&command)
    case .getConfig:
      evalSucceeded = getConfig(&command)
    case .setConfig:
      evalSucceeded = setConfig(&command)
    case .setRequest:
      evalSucceeded = setRequest(&command)
    case .shutdown:
      evalSucceeded = shutdown(&command)
    case .reload:
      evalSucceeded = reload(&command)
    case .reloadAndWait:
      evalSucceeded = reloadAndWait(&command)
    case .cleanup:
      evalSucceeded = cleanup(&command)
    case .addUserHistory:
      evalSucceeded = addUserHistory(&command)
    case .sendEngineReloadRequest:
      evalSucceeded = sendEngineReloadRequest(&command)
    case .noOperation:
      evalSucceeded = noOperation(&command)
    case .reloadSupplementalModel:
      evalSucceeded = reloadSupplementalModel(&command)
    case .getServerVersion:
      evalSucceeded = getServerVersion(&command)
    default:
      evalSucceeded = false
    }

    if evalSucceeded {
      if command.input.type != .createSession {
        // Fill a session ID even if command->input() doesn't have a id to ensure
        // that response size should not be 0, which causes disconnection of IPC.
        command.output.id = command.input.id
      }
    } else {
      command.output.id = 0
      command.output.errorCode = .sessionFailure
    }

    return isAvailable
  }

  /// NewSession returns new Session.
  public func newSession() -> Session {
    // Session doesn't take the ownership of engine.
    Session(engine)
  }

  /// Updates the config, if the |command| contains the config.
  private func maybeUpdateConfig(_ command: inout Genmai_Commands_Command) {
    if !command.output.hasConfig {
      return
    }

    ConfigHandler.setConfig(command.output.config)
    _ = reload(&command)
  }

  private func lookupSession(_ id: SessionID) -> Session? {
    guard let element = sessionMap.mutableLookup(id) else { return nil }
    return element.value
  }

  private func sendKey(_ command: inout Genmai_Commands_Command) -> Bool {
    let id = command.input.id
    guard let session = lookupSession(id) else {
      GenmaiLog.warning("SessionID \(id) is not available")
      return false
    }
    session.sendKey(&command)
    maybeUpdateConfig(&command)
    return true
  }

  private func testSendKey(_ command: inout Genmai_Commands_Command) -> Bool {
    let id = command.input.id
    guard let session = lookupSession(id) else {
      GenmaiLog.warning("SessionID \(id) is not available")
      return false
    }
    session.testSendKey(&command)
    return true
  }

  private func sendCommand(_ command: inout Genmai_Commands_Command) -> Bool {
    let id = command.input.id
    guard let session = lookupSession(id) else {
      GenmaiLog.warning("SessionID \(id) is not available")
      return false
    }
    session.sendCommand(&command)
    maybeUpdateConfig(&command)
    return true
  }

  /// Replaces engine_ with a new instance if it is ready.
  private func maybeReloadEngine(_ command: inout Genmai_Commands_Command) {
    if sessionMap.size > 0 {
      // Some sessions still use the current engine_.
      return
    }

    var engineReloadResponse = Genmai_EngineReloadResponse()
    if !engine.maybeReloadEngine(&engineReloadResponse) {
      // Engine is not reloaded. output.engine_reload_response must be empty.
      return
    }

    GenmaiLog.info("Engine reloaded")
    command.output.engineReloadResponse = engineReloadResponse
    tableManager.clearCaches()
  }

  private func getServerVersion(_ command: inout Genmai_Commands_Command) -> Bool {
    command.output.serverVersion.genmaiVersion = Version.getGenmaiVersion()
    command.output.serverVersion.dataVersion = engine.getDataVersion()
    return true
  }

  private func createSession(_ command: inout Genmai_Commands_Command) -> Bool {
    // prevent DOS attack
    // don't allow CreateSession in very short period.
    let createSessionMinimumInterval = max(
      Duration.zero,
      min(Duration.seconds(Int64(SessionHandler.flags.createSessionMinInterval)), .seconds(10)))

    let currentTime = Clock.getAbslTime()
    let createSessionInterval = currentTime - lastCreateSessionTime
    // `create_session_interval` can be negative if a user modifies their system
    // clock.
    if lastCreateSessionTime != Date.distantPast && createSessionInterval >= .zero
      && createSessionInterval < createSessionMinimumInterval
    {
      return false
    }

    lastCreateSessionTime = currentTime

    // if session map is FULL, remove the oldest item from the LRU
    if sessionMap.size >= Int(maxSessionSize) {
      guard let oldestElement = sessionMap.tail else {
        GenmaiLog.error("oldest SessionElement is NULL")
        return false
      }
      oldestElement.value = nil
      _ = sessionMap.erase(oldestElement.key)
    }

    // CreateSession is called on a relatively safer timing to reload engine_.
    maybeReloadEngine(&command)

    let session = newSession()

    if command.input.hasCapability {
      session.setClientCapability(command.input.capability)
    }

    if command.input.hasApplicationInfo {
      session.setApplicationInfo(command.input.applicationInfo)
    }

    let newId = createNewSessionID()
    let element = sessionMap.insert(newId)
    element.value = session
    command.output.id = newId

    // The created session has not been fully initialized yet.
    // SetConfig() will complete the initialization by setting information
    // (e.g., config, request, keymap, ...) to all the sessions,
    // including the newly created one.
    updateSessions()

    // session is not empty.
    lastSessionEmptyTime = Date.distantPast

    return true
  }

  private func deleteSession(_ command: inout Genmai_Commands_Command) -> Bool {
    _ = deleteSessionID(command.input.id)
    engine.sync()
    return true
  }

  /// Scan all sessions and find and delete session which is either
  /// (a) The session is not activated for 60min
  /// (b) The session is created but not accessed for 5min
  /// (c) application is already terminated.
  /// Also, if timeout is enabled, shutdown server if there is
  /// no active session and client doesn't send any conversion
  /// request to the server for FLAGS_timeout sec.
  private func cleanup(_ command: inout Genmai_Commands_Command) -> Bool {
    let currentTime = Clock.getAbslTime()
    let flags = SessionHandler.flags

    // suspend/hibernation may happen
    var suspendTime = Duration.zero
    if lastCleanupTime != Date.distantPast, let sessionWatchDog,
      (currentTime - lastCleanupTime) > sessionWatchDog.interval * 2
    {
      suspendTime = currentTime - lastCleanupTime - sessionWatchDog.interval
      GenmaiLog.warning("server went to suspend mode for \(suspendTime)")
    }

    // allow [1..600] sec. default: 300
    let createSessionTimeout =
      suspendTime
      + max(.seconds(1), min(Duration.seconds(Int64(flags.lastCreateSessionTimeout)), .seconds(600)))

    // allow [10..7200] sec. default 3600
    let lastCommandTimeout =
      suspendTime
      + max(.seconds(10), min(Duration.seconds(Int64(flags.lastCommandTimeout)), .seconds(7200)))

    var removeIds: [SessionID] = []
    for element in sessionMap {
      guard let session = element.value else { continue }
      if !isApplicationAlive(session) {
        removeIds.append(element.key)
      } else if session.lastCommandTime == Date.distantPast {
        // no command is executed
        if (currentTime - session.createSessionTime) >= createSessionTimeout {
          removeIds.append(element.key)
        }
      } else {  // some commands are executed already
        if (currentTime - session.lastCommandTime) >= lastCommandTimeout {
          removeIds.append(element.key)
        }
      }
    }

    for id in removeIds {
      _ = deleteSessionID(id)
    }

    // Sync all data. This is a regression bug fix http://b/3033708
    engine.sync()

    // timeout is enabled.
    // (absl::InfinitePast() makes the difference infinite in C++.)
    if flags.timeout > 0
      && (currentTime - lastSessionEmptyTime)
        >= suspendTime + .seconds(Int64(flags.timeout))
    {
      _ = shutdown(&command)
    }

    lastCleanupTime = currentTime

    return true
  }

  private func sendEngineReloadRequest(_ command: inout Genmai_Commands_Command) -> Bool {
    if !command.input.hasEngineReloadRequest {
      return false
    }
    if !engine.sendEngineReloadRequest(command.input.engineReloadRequest) {
      return false
    }
    command.output.engineReloadResponse.status = .accepted
    return true
  }

  private func noOperation(_ command: inout Genmai_Commands_Command) -> Bool { true }

  private func reloadSupplementalModel(_ command: inout Genmai_Commands_Command) -> Bool {
    if !command.input.hasEngineReloadRequest {
      return false
    }
    if !engine.sendSupplementalModelReloadRequest(command.input.engineReloadRequest) {
      return false
    }
    command.output.engineReloadResponse.status = .accepted
    return true
  }

  /// Create Random Session ID in order to make the session id unpredictable
  private func createNewSessionID() -> SessionID {
    while true {
      // don't allow id == 0, as it is reserved for "invalid id"
      let id = SessionID.random(in: 1...SessionID.max, using: &bitgen)
      if !sessionMap.hasKey(id) {
        return id
      }

      GenmaiLog.warning("Session ID \(id) is already used. retry")
    }
  }

  private func deleteSessionID(_ id: SessionID) -> Bool {
    guard let element = sessionMap.mutableLookup(id), element.value != nil else {
      if id != 0 {
        GenmaiLog.warning("cannot find SessionID \(id)")
      }
      return false
    }
    element.value = nil

    _ = sessionMap.erase(id)  // remove from LRU

    // if session gets empty, save the timestamp
    if lastSessionEmptyTime == Date.distantPast && sessionMap.size == 0 {
      lastSessionEmptyTime = Clock.getAbslTime()
    }

    return true
  }

  // MARK: - Test peers (KeyMapManagerAccessorTestPeer etc.)

  var keyMapManagerForTesting: KeyMapManager { keyMapManager }
  var configForTesting: Genmai_Config_Config { config }
  var requestForTesting: Genmai_Commands_Request { request }
  var sessionCountForTesting: Int { sessionMap.size }
}
