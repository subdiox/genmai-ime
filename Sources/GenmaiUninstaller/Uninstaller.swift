// Port of mozc/src/mac/Uninstaller/Uninstaller.{h,mm} (3.35.6354).
//
// The uninstaller asks for administrator rights, removes the installed files with `/bin/rm -rf` one path at a
// time (stopping at the first failure), reports the result and offers to restart the computer. The C++'s
// +doUninstall: (delete, then one modal dialog per outcome) is UninstallerController's single-window flow.
//
// Deviations from C++:
// - Privileges: the C++ obtains an AuthorizationRef (AuthorizationCopyRights with kAuthorizationRightExecute)
//   and runs /bin/rm through AuthorizationExecuteWithPrivileges, which has been deprecated since macOS 10.7 and
//   has no in-process replacement short of a privileged helper (SMAppService daemon + XPC), which is far too
//   heavy for a one-shot uninstaller. The port runs the same `/bin/rm -rf <path>` commands, chained with `&&`
//   so the first failure stops the rest like the C++ loop, as one AppleScript
//   `do shell script "..." with administrator privileges` (NSAppleScript, in process, so the system password
//   prompt names this app). Authorization and execution therefore happen in one step; a cancelled or denied
//   authorization (AppleScript errors -128, -60005, -60006, -60007) is reported as the C++'s auth error, any
//   other failure as the uninstall error. The runner is injectable (`PrivilegedCommandRunner`) so tests run
//   the generated command unprivileged against a temporary directory.
// - Paths (kRemovePaths): adapted to this port's install layout (Tools/make_installer_pkg.sh) and bundle id
//   io.github.subdiox.genmai.inputmethod.Japanese, which was chosen so that the Swift port and the C++ Mozc
//   (/Library/Input Methods/Mozc.app, /Applications/Mozc) can be installed side by side:
//     /Library/Input Methods/Genmai.app   (C++: /Library/Input Methods/Mozc.app)
//     /Applications/Genmai                (C++: /Applications/Mozc, holds this uninstaller)
//   plus a manually installed bundle from Tools/make_ime_bundle.sh (~/Library/Input Methods/Genmai.app), but
//   only if its CFBundleIdentifier is this port's, so the C++ Mozc is never removed. The LaunchAgents plists of the converter / renderer are n/a: the Swift IME runs both
//   in-process and installs no LaunchAgents. Like the C++, the user's profile (~/Library/Application Support/
//   Genmai) is kept.
// - MacUtil::RemovePrelauncherLoginItem is n/a (the in-process design has no prelauncher login item).
// - RunReboot: the C++ runs /sbin/reboot as root (with a TODO to "use OS-specific API instead"). The port asks
//   loginwindow for a normal restart (the `restart` Apple event, kAERestart), which lets other apps save
//   their documents and needs no privileges.
// - The uninstall survey and the Keystone ticket removal are not ported (the OSS build does neither).

import AppKit
import Foundation
import GenmaiBase

/// Where the port's files are installed. `systemRoot` / `homeDirectory` exist so that tests can point the
/// uninstaller at a temporary directory; the app uses `.installed`.
struct UninstallerLayout: Sendable, Equatable {
  /// CFBundleIdentifier of the Swift IME bundle (Tools/make_ime_bundle.sh).
  static let kBundleIdentifier = "io.github.subdiox.genmai.inputmethod.Japanese"
  /// PRODUCT_NAME of the Swift bundle: the IME is installed as <product>.app and the uninstaller in
  /// /Applications/<product> (the C++ uses "Mozc" for both).
  static let kProductName = "Genmai"

  var systemRoot: URL
  var homeDirectory: URL

  static var installed: UninstallerLayout {
    UninstallerLayout(
      systemRoot: URL(fileURLWithPath: "/"),
      homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
  }

  /// /Library/Input Methods/Genmai.app (installed by the .pkg).
  var inputMethodBundle: URL {
    systemRoot.appending(path: "Library/Input Methods/\(Self.kProductName).app", directoryHint: .isDirectory)
  }

  /// /Applications/Genmai (the uninstaller and the folder's .localized names, installed by the .pkg).
  var applicationsFolder: URL {
    systemRoot.appending(path: "Applications/\(Self.kProductName)", directoryHint: .isDirectory)
  }

  /// The bundle that Tools/make_ime_bundle.sh tells the user to copy by hand (the system-wide location is
  /// `inputMethodBundle`).
  var manualInstallCandidates: [URL] {
    [homeDirectory.appending(path: "Library/Input Methods/\(Self.kProductName).app", directoryHint: .isDirectory)]
  }

  /// kRemovePaths: the fixed install locations, then any manually installed bundle of this port.
  func removeItems() -> [RemoveItem] {
    var items = [
      RemoveItem(kind: .inputMethod, path: inputMethodBundle.path(percentEncoded: false)),
      RemoveItem(kind: .applicationsFolder, path: applicationsFolder.path(percentEncoded: false)),
    ]
    for candidate in manualInstallCandidates
    where Self.bundleIdentifier(at: candidate) == Self.kBundleIdentifier {
      items.append(RemoveItem(kind: .manualInputMethod, path: candidate.path(percentEncoded: false)))
    }
    return items
  }

  func removePaths() -> [String] { removeItems().map(\.path) }

  /// Reads CFBundleIdentifier from <bundle>/Contents/Info.plist (not through Bundle, which caches).
  static func bundleIdentifier(at bundle: URL) -> String? {
    let plist = bundle.appending(path: "Contents/Info.plist")
    guard let data = try? Data(contentsOf: plist),
      let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    else {
      return nil
    }
    return dictionary["CFBundleIdentifier"] as? String
  }
}

/// One path the uninstaller removes, with what it is (shown in the confirmation).
struct RemoveItem: Sendable, Equatable, Hashable {
  enum Kind: Sendable, Equatable, Hashable {
    /// /Library/Input Methods/Genmai.app.
    case inputMethod
    /// /Applications/Genmai (holds this uninstaller).
    case applicationsFolder
    /// ~/Library/Input Methods/Genmai.app.
    case manualInputMethod
  }

  var kind: Kind
  var path: String

  /// The path for display: no trailing slash, the home directory as ~.
  var displayPath: String {
    var path = path
    if path.count > 1, path.hasSuffix("/") {
      path.removeLast()
    }
    return (path as NSString).abbreviatingWithTildeInPath
  }
}

/// The outcome of running a command with administrator rights.
enum PrivilegedCommandResult: Sendable, Equatable {
  case success
  /// GetPrevilegeRights failed: the user cancelled or the password was wrong.
  case authorizationFailed
  /// The command itself failed (the message is logged).
  case failed(String)
}

/// Runs a /bin/sh command line as root. Replaces AuthorizationCopyRights + AuthorizationExecuteWithPrivileges.
@MainActor
protocol PrivilegedCommandRunner {
  func run(_ shellCommand: String) -> PrivilegedCommandResult
}

/// `do shell script "<command>" with administrator privileges` through NSAppleScript.
struct AppleScriptPrivilegedCommandRunner: PrivilegedCommandRunner {
  /// AppleScript / Authorization Services errors that mean "no rights were granted".
  static let kAuthorizationErrorNumbers: Set<Int> = [
    -128,  // userCanceledErr
    -60005,  // errAuthorizationDenied
    -60006,  // errAuthorizationCanceled
    -60007,  // errAuthorizationInteractionNotAllowed
  ]

  static func source(for shellCommand: String) -> String {
    "do shell script \"\(appleScriptEscaped(shellCommand))\" with administrator privileges"
  }

  /// Escapes `string` for an AppleScript string literal.
  static func appleScriptEscaped(_ string: String) -> String {
    string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
  }

  func run(_ shellCommand: String) -> PrivilegedCommandResult {
    guard let script = NSAppleScript(source: Self.source(for: shellCommand)) else {
      return .failed("cannot compile the AppleScript")
    }
    var error: NSDictionary?
    _ = script.executeAndReturnError(&error)
    guard let error else {
      return .success
    }
    let number = (error[NSAppleScript.errorNumber] as? Int) ?? 0
    if Self.kAuthorizationErrorNumbers.contains(number) {
      return .authorizationFailed
    }
    return .failed((error[NSAppleScript.errorMessage] as? String) ?? "AppleScript error \(number)")
  }
}

@MainActor
struct Uninstaller {
  var layout: UninstallerLayout
  var runner: any PrivilegedCommandRunner
  var reboot: @MainActor () -> Bool = { Uninstaller.requestRestart() }

  /// Quotes `string` for /bin/sh.
  static func shellQuoted(_ string: String) -> String {
    "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  /// DeleteFiles's command line: `/bin/rm -rf <path>` per path, stopping at the first failure.
  static func deleteCommand(for paths: [String]) -> String {
    paths.map { "/bin/rm -rf \(shellQuoted($0))" }.joined(separator: " && ")
  }

  /// GetPrevilegeRights + DeleteFiles.
  func deleteFiles() -> PrivilegedCommandResult {
    let paths = layout.removePaths()
    let result = runner.run(Self.deleteCommand(for: paths))
    if case .failed(let message) = result {
      NSLog("Failed to remove path: %@", message)
    }
    return result
  }

  /// RunReboot: asks loginwindow to restart (kAERestart), like Apple menu > Restart.
  static func requestRestart() -> Bool {
    let source = "tell application \"loginwindow\" to «event aevtrrst»"
    var error: NSDictionary?
    _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
    if let error {
      NSLog("Failed to restart: %@", error)
      return false
    }
    return true
  }
}
