// The session backend used by the GenmaiApp process (config dialog, dictionary tool, word register, ...).
//
// In C++ the tools talk to mozc_server over IPC (GET_CONFIG / SET_CONFIG / RELOAD / CLEAR_USER_HISTORY ...).
// The Swift IME has no server process: the Genmai app reads and writes the config file through `ConfigHandler`
// directly and asks the IME process to reload via a distributed notification (`kReloadNotificationName`),
// which the IME answers by calling `reload()` on its backend.
//
// Session commands (the word register dialog's reverse conversion: SEND_KEY ON, CONVERT_REVERSE, REVERT) go to
// an engine of the app's own (`SessionHandlerBackend`, created on first use). That engine never learns
// anything (the dialog only reverts), so it never writes the learning data the IME owns.

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol

/// Posted by the Genmai app process after it changed shared data (config, user dictionary).
/// The `object` is the command name ("reload", "clear_user_history", "clear_user_prediction").
public let kReloadNotificationName = Notification.Name("io.github.subdiox.genmai.inputmethod.Japanese.Reload")

@MainActor
public final class AppSessionBackend: SessionBackend {
  private let notify: @MainActor (String) -> Void
  private let sessionBackendFactory: @MainActor () -> any SessionBackend
  private var sessionBackend: (any SessionBackend)?

  public init(
    notify: @escaping @MainActor (String) -> Void = AppSessionBackend.postDistributedNotification,
    sessionBackendFactory: @escaping @MainActor () -> any SessionBackend = { SessionHandlerBackend() }
  ) {
    self.notify = notify
    self.sessionBackendFactory = sessionBackendFactory
  }

  private func session() -> any SessionBackend {
    if let sessionBackend {
      return sessionBackend
    }
    let backend = sessionBackendFactory()
    sessionBackend = backend
    return backend
  }

  public static func postDistributedNotification(_ command: String) {
    DistributedNotificationCenter.default().postNotificationName(
      kReloadNotificationName, object: command, userInfo: nil, deliverImmediately: true)
  }

  /// A client for the Genmai app process.
  public static func makeClient() -> InProcessClient {
    InProcessClient(
      backend: AppSessionBackend(),
      initialConfig: ConfigHandler.getCopiedConfig(),
      directModeKeysExtractor: { _ in [] })
  }

  public func evalCommand(_ input: Input) -> Output? {
    switch input.type {
    case .createSession, .deleteSession, .sendKey, .testSendKey, .sendCommand:
      return session().evalCommand(input)
    default:
      break
    }
    var output = Output()
    output.id = input.id
    output.errorCode = .sessionSuccess
    switch input.type {
    case .getConfig:
      output.config = ConfigHandler.getCopiedConfig()
    case .setConfig:
      ConfigHandler.setConfig(input.config)
      notify("reload")
    case .reload:
      ConfigHandler.reload()
      notify("reload")
    case .clearUserHistory:
      notify("clear_user_history")
    case .clearUserPrediction:
      notify("clear_user_prediction")
    default:
      break
    }
    return output
  }
}
