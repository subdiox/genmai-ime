// The in-process replacement of mozc_server (server/mozc_server.cc + session/session_server.cc, 3.35.6354).
//
// Not a one-to-one port: the C++ server process owns an Engine and a SessionHandler and answers the IPC
// requests of every client. The Swift IME owns one `SessionHandlerBackend` per process: it creates the
// Engine (the OSS data set, `OssDataManager.defaultDataPath`, i.e. Contents/Resources/genmai.data of the app
// bundle) and a `SessionHandler`, and evaluates the `commands::Input` messages of all `InProcessClient`s
// (one per input controller, each with its own session) synchronously on the main actor. Engine and
// SessionHandler are not Sendable; they never leave the main actor.
//
// Server-side duties of mozc_server that remain:
// - the session watch dog (`startWatchDog()`), which periodically sends CLEANUP (deletes idle sessions and
//   syncs the user history / learning data to disk);
// - SYNC_DATA when the IME is deactivated / quits (`syncData()`, async: the session handler does not wait for
//   the engine, so it awaits the engine's background tasks);
// - RELOAD when GenmaiApp changed the config or the user dictionary (`reload()`; the config file is re-read
//   first because the Genmai app wrote it from another process).
// If the data set cannot be loaded, `evalCommand` returns nil (the C++ IPC call failed): the clients then
// report a fatal server status and every key is passed through to the application.
//
// Not in Mozc: an optional `AIConversionHook` (AIConversion/AIConversionHook.swift). The engine is then wrapped
// in `AugmentedEngine` and every command is reported to the hook before and after evaluation; without a hook
// (or with AI conversion disabled in its settings) the backend is plain Mozc.

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import GenmaiSession

@MainActor
public final class SessionHandlerBackend: SessionBackend {
  /// The error of the engine creation, if the data set failed to load.
  public private(set) var loadError: (any Error)?
  /// The time it took to create the engine (data set mmap + converter/predictor/rewriter setup).
  public private(set) var engineLoadTime: Duration = .zero

  private var handler: SessionHandler?
  /// The Mozc engine (also when it is wrapped in `AugmentedEngine`); awaited by `syncData()`.
  private var engine: Engine?
  private var watchDogClient: WatchDogClient?
  /// The AI conversion hook, if the IME was built with it.
  public let aiHook: AIConversionHook?

  /// Creates the engine with `engineFactory` (default: the OSS data set) and the session handler.
  public init(
    engineFactory: () throws -> Engine = { try OssEngineFactory.create() }, aiHook: AIConversionHook? = nil
  ) {
    self.aiHook = aiHook
    let start = ContinuousClock.now
    do {
      let engine = try engineFactory()
      self.engine = engine
      if let aiHook {
        handler = SessionHandler(AugmentedEngine(engine, hook: aiHook))
      } else {
        handler = SessionHandler(engine)
      }
    } catch {
      loadError = error
      GenmaiLog.error("Failed to create the conversion engine: \(error)")
    }
    engineLoadTime = ContinuousClock.now - start
  }

  /// True if the engine loaded and the session handler accepts commands.
  public var isAvailable: Bool { handler?.getIsAvailable() ?? false }

  /// The data version of the loaded data set ("" when unavailable).
  public var dataVersion: String { isAvailable ? handler?.getDataVersion() ?? "" : "" }

  /// `SessionHandler::EvalCommand`. Returns nil when the handler is unavailable.
  public func evalCommand(_ input: Input) -> Output? {
    guard let handler else {
      return nil
    }
    var command = Genmai_Commands_Command()
    command.input = input
    aiHook?.willEvaluate(input)
    if !handler.evalCommand(&command) {
      // The handler became unavailable (SHUTDOWN or a broken engine).
      aiHook?.didEvaluate(input, nil)
      return nil
    }
    aiHook?.didEvaluate(input, command.output)
    return command.output
  }

  // MARK: - Server-side commands (no session needed)

  @discardableResult
  private func call(_ type: Input.CommandType) -> Bool {
    var input = Input()
    input.type = type
    return evalCommand(input) != nil
  }

  /// Re-reads the config file written by GenmaiApp and reloads the sessions, the user dictionary and the
  /// learning data (RELOAD). The learning data is synced first so that RELOAD (which reads it back from
  /// disk) does not drop what was learned since the last sync.
  @discardableResult
  public func reload() -> Bool {
    call(.syncData)
    ConfigHandler.reload()
    aiHook?.reloadSettings()
    return call(.reload)
  }

  /// Writes the learning data to disk and waits for it (SYNC_DATA, then the engine's background tasks; the
  /// wait suspends, it does not block the main thread). Cheap when nothing changed.
  @discardableResult
  public func syncData() async -> Bool {
    guard call(.syncData) else { return false }
    await engine?.wait()
    return true
  }

  @discardableResult
  public func cleanup() -> Bool { call(.cleanup) }

  @discardableResult
  public func clearUserHistory() -> Bool { call(.clearUserHistory) }

  @discardableResult
  public func clearUserPrediction() -> Bool { call(.clearUserPrediction) }

  /// Starts the session watch dog. CLEANUP is sent every `SessionHandler.flags.watchDogInterval` seconds
  /// (180 by default) when the CPU is not busy.
  public func startWatchDog() {
    guard let handler, watchDogClient == nil else { return }
    let client = WatchDogClient { [weak self] in
      Task { @MainActor in self?.cleanup() }
    }
    watchDogClient = client
    handler.startWatchDog(client: client)
  }
}

/// The watch dog runs on a background task; it schedules CLEANUP on the main actor and returns at once
/// (the C++ watch dog waits for the IPC reply, but nothing depends on the result).
private final class WatchDogClient: SessionWatchDogClient {
  private let onCleanup: @Sendable () -> Void

  init(onCleanup: @escaping @Sendable () -> Void) {
    self.onCleanup = onCleanup
  }

  func setTimeout(_ timeout: Duration) {}

  func cleanup() -> Bool {
    onCleanup()
    return true
  }

  func reset() {}

  func pingServer() -> Bool { true }
}

extension InProcessClient {
  /// A client with its own session on `backend`.
  public static func make(
    backend: any SessionBackend, toolLauncher: (any AppLauncher)? = nil,
    browserOpener: @escaping @MainActor (String) -> Bool = { _ in false }
  ) -> InProcessClient {
    InProcessClient(
      backend: backend,
      initialConfig: ConfigHandler.getCopiedConfig(),
      toolLauncher: toolLauncher,
      browserOpener: browserOpener)
  }
}
