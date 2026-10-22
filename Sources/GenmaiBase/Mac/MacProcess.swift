// Port of mozc/src/base/mac/mac_process.{h,mm} (3.35.6354).
//
// Deviations from C++:
// - The C++ launches per-mode wrapper apps (ConfigDialog.app,
//   DictionaryTool.app, ...) from the server directory and passes the mode /
//   error type through the FLAGS_mode / FLAGS_error_type environment
//   variables. The Swift bundle ships a single GenmaiApp.app
//   (SystemUtil.getAppPath()) that takes `--mode=<mode>` and
//   `--error_type=<type>` arguments, so LaunchGenmaiTool opens that app with
//   those arguments (a new instance per launch, like the separate C++ apps).
//   The IME itself uses GenmaiMac.MacAppLauncher, which follows the same
//   convention.
// - -[NSWorkspace launchApplication:] is deprecated; openApplication(at:...)
//   is asynchronous, so the result only says whether the app exists.

import Foundation

#if canImport(AppKit)
  import AppKit
#endif

public enum MacProcess {
  private static let kFileSchema = "file://"

  /// Opens `url` with the default browser (NSWorkspace openURL).
  public static func openBrowserForMac(_ url: String) -> Bool {
    let nsURL: URL?
    if url.hasPrefix(kFileSchema) {
      // for making URL from "file://...", use fileURLWithPath
      nsURL = URL(fileURLWithPath: String(url.dropFirst(kFileSchema.count)))
    } else {
      nsURL = URL(string: url)
    }
    guard let nsURL else {
      GenmaiLog.error("NSURL is not initialized")
      return false
    }
    #if canImport(AppKit)
      return NSWorkspace.shared.open(nsURL)
    #else
      return false
    #endif
  }

  /// Launches the application bundle at `path` (without arguments).
  public static func openApplication(_ path: String) -> Bool {
    openApplication(path, arguments: [])
  }

  static func openApplication(_ path: String, arguments: [String]) -> Bool {
    #if canImport(AppKit)
      guard FileManager.default.fileExists(atPath: path) else {
        return false
      }
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.arguments = arguments
      configuration.createsNewApplicationInstance = !arguments.isEmpty
      NSWorkspace.shared.openApplication(
        at: URL(fileURLWithPath: path), configuration: configuration
      ) { _, error in
        if let error {
          GenmaiLog.error("failed to launch \(path): \(error.localizedDescription)")
        }
      }
      return true
    #else
      return false
    #endif
  }

  private static func openGenmaiAppInternal(_ toolName: String, _ errorType: String) -> Bool {
    let toolPath = SystemUtil.getAppPath()
    if toolPath.isEmpty {
      return false
    }
    var arguments = ["--mode=\(toolName)"]
    if !errorType.isEmpty {
      // --error_type is used where --mode is "error_message_dialog".
      arguments.append("--error_type=\(errorType)")
    }
    return openApplication(toolPath, arguments: arguments)
  }

  /// Launches GenmaiApp in mode `toolName` ("config_dialog", "dictionary_tool",
  /// "word_register_dialog", "about_dialog", ...).
  public static func openGenmaiApp(_ toolName: String) -> Bool {
    openGenmaiAppInternal(toolName, "")
  }

  /// Launches the error message dialog of GenmaiApp.
  public static func launchErrorMessageDialog(_ errorType: String) -> Bool {
    openGenmaiAppInternal("error_message_dialog", errorType)
  }
}
