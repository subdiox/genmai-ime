// Port of mozc/src/client/client_interface.h (3.35.6354).
//
// The C++ client talks to mozc_server over IPC. The Swift port runs the converter in-process, so the
// IPC-specific parts (IPC client factory, server launcher, timeouts, version checks) collapse into no-ops in
// the concrete clients, but the interface keeps them so callers can be ported one to one.
//
// C++ `bool Foo(..., Output* output)` becomes `func foo(...) -> Output?` (`nil` == `false`).

import GenmaiProtocol

public typealias KeyEvent = Genmai_Commands_KeyEvent
public typealias SessionCommand = Genmai_Commands_SessionCommand
public typealias Output = Genmai_Commands_Output
public typealias Context = Genmai_Commands_Context
public typealias Capability = Genmai_Commands_Capability
public typealias Config = Genmai_Config_Config

/// Mirrors `ClientInterface`. All UI code runs on the main actor, so the protocol is main-actor isolated.
@MainActor
public protocol GenmaiClientProtocol: AnyObject {
  /// Returns true if the current thread is running inside a valid run level.
  func isValidRunLevel() -> Bool

  /// Returns true if the connection is alive (always true in-process).
  func ensureConnection() -> Bool

  /// Returns true if the session id is valid; re-issues one otherwise.
  func ensureSession() -> Bool

  /// Checks protocol/product version (no-op in-process).
  func checkVersionOrRestartServer() -> Bool

  // `context == nil` corresponds to passing `commands::Context::default_instance()` in C++ (the input then
  // has no context field); a non-nil context, even an empty one, is copied into the input.
  func sendKey(_ key: KeyEvent, context: Context?) -> Output?
  func testSendKey(_ key: KeyEvent, context: Context?) -> Output?
  func sendCommand(_ command: SessionCommand, context: Context?) -> Output?

  /// Returns true if the key is consumed in the direct mode.
  func isDirectModeCommand(_ key: KeyEvent) -> Bool

  func getConfig() -> Config?
  @discardableResult func setConfig(_ config: Config) -> Bool

  @discardableResult func clearUserHistory() -> Bool
  @discardableResult func clearUserPrediction() -> Bool
  @discardableResult func shutdown() -> Bool
  @discardableResult func syncData() -> Bool
  /// Reloads server data (user dictionary, prediction data, config).
  @discardableResult func reload() -> Bool
  @discardableResult func cleanup() -> Bool
  func reset()
  func pingServer() -> Bool
  @discardableResult func noOperation() -> Bool
  func enableCascadingWindow(_ enable: Bool)
  func setSuppressErrorDialog(_ suppress: Bool)
  func setClientCapability(_ capability: Capability)

  /// Launches mozc tool. `mode` is e.g. "config_dialog", "dictionary_tool".
  @discardableResult func launchTool(mode: String, extraArg: String) -> Bool
  /// Launches mozc_tool for `output.launchToolMode`; returns false for NO_TOOL / no value.
  @discardableResult func launchToolWithProtoBuf(_ output: Output) -> Bool
  @discardableResult func openBrowser(_ url: String) -> Bool
}

extension GenmaiClientProtocol {
  // The non-virtual convenience overloads of ClientInterface.
  public func sendKey(_ key: KeyEvent) -> Output? { sendKey(key, context: nil) }
  public func testSendKey(_ key: KeyEvent) -> Output? { testSendKey(key, context: nil) }
  public func sendCommand(_ command: SessionCommand) -> Output? { sendCommand(command, context: nil) }
}

/// Mirrors `SendCommandInterface` (used by the renderer to send mouse clicks back).
@MainActor
public protocol SendCommandInterface: AnyObject {
  @discardableResult func sendCommand(_ command: SessionCommand) -> Output?
}

/// Launches the tool app (GenmaiTool.app). Abstracted so that the IME and tests can replace it.
@MainActor
public protocol ToolLauncher: AnyObject {
  /// `mode` is the mozc_tool mode ("config_dialog", "dictionary_tool", "word_register_dialog",
  /// "about_dialog", "error_message_dialog", ...). `environment` is merged into the tool's environment.
  @discardableResult func launchTool(mode: String, extraArg: String, environment: [String: String]) -> Bool
}

/// Mirrors `mozc::kWordRegisterEnvironmentName` (base/const.h).
public let kWordRegisterEnvironmentName = "default_entry_of_word_register"

/// Tool modes understood by GenmaiTool (gui/tool/mozc_tool_libmain.cc).
public enum ToolMode: String, CaseIterable, Sendable {
  case configDialog = "config_dialog"
  case dictionaryTool = "dictionary_tool"
  case wordRegisterDialog = "word_register_dialog"
  case aboutDialog = "about_dialog"
  case errorMessageDialog = "error_message_dialog"
  /// Not in Mozc: the update dialog (opened from the IME's update notification).
  case updateDialog = "update_dialog"
  /// Not in Mozc: the welcome window (opened once by the installer).
  case welcome

  /// Maps `Output.LaunchToolMode` to the tool mode string (client/client.cc LaunchToolWithProtoBuf).
  public init?(_ mode: Output.ToolMode) {
    switch mode {
    case .configDialog: self = .configDialog
    case .dictionaryTool: self = .dictionaryTool
    case .wordRegisterDialog: self = .wordRegisterDialog
    default: return nil
    }
  }
}
