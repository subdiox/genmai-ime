// Port of MacProcess::LaunchGenmaiTool / LaunchErrorMessageDialog (mozc/src/base/mac/mac_process.mm,
// 3.35.6354).
//
// The C++ launches ConfigDialog.app / DictionaryTool.app / ... (thin wrappers of GenmaiTool.app) from the
// server directory and passes the mode through environment variables. The Swift bundle ships a single
// tool app (GenmaiTool, installed as Genmai.app) in Genmai.app/Contents/Resources; the mode is passed as `--mode=<mode>` (plus
// `--error_type=<type>` for the error dialog) and extra environment variables (the word register text).

import AppKit
import GenmaiBase
import GenmaiClient

@MainActor
public final class MacToolLauncher: ToolLauncher {
  private let toolURL: URL

  /// - Parameter toolURL: the tool app. Defaults to Contents/Resources/Genmai.app of the main bundle.
  public init(toolURL: URL? = nil) {
    self.toolURL =
      toolURL ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/" + GenmaiConst.kGenmaiTool)
  }

  @discardableResult
  public func launchTool(mode: String, extraArg: String, environment: [String: String]) -> Bool {
    let configuration = NSWorkspace.OpenConfiguration()
    var arguments = ["--mode=\(mode)"]
    if !extraArg.isEmpty {
      arguments.append(extraArg)
    }
    configuration.arguments = arguments
    configuration.environment = environment
    // Each tool mode runs in its own process (GenmaiTool keeps one window per mode).
    configuration.createsNewApplicationInstance = true
    configuration.activates = true
    guard FileManager.default.fileExists(atPath: toolURL.path) else {
      return false
    }
    NSWorkspace.shared.openApplication(at: toolURL, configuration: configuration) { _, error in
      if let error {
        NSLog("Genmai: failed to launch GenmaiTool (%@): %@", mode, error.localizedDescription)
      }
    }
    return true
  }

  /// MacProcess::LaunchErrorMessageDialog.
  @discardableResult
  public func launchErrorMessageDialog(_ errorType: String) -> Bool {
    launchTool(
      mode: ToolMode.errorMessageDialog.rawValue, extraArg: "--error_type=\(errorType)",
      environment: [:])
  }
}
