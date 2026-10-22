// Port of mozc/src/mac/Uninstaller/Uninstaller.{h,mm} (3.35.6354).
//
// The uninstaller asks for administrator rights, removes the installed files with `/bin/rm -rf` one path at a
// time (stopping at the first failure), reports the result and offers to restart the computer. The C++'s
// +doUninstall: (delete, then one modal dialog per outcome) is UninstallerController's single-window flow.
//
// Deviations from C++:
// - Privileges: like the C++, administrator rights come from Authorization Services (AuthorizationCopyRights
//   with kAuthorizationRightExecute: the system's own dialog, which offers Touch ID) and `/bin/rm` runs as root
//   through AuthorizationExecuteWithPrivileges. That call has been deprecated since macOS 10.7 (Swift marks it
//   unavailable, so it is looked up with dlsym); the only replacement is a privileged helper (SMAppService daemon
//   + XPC) that the user first has to allow in System Settings › Login Items, far too heavy for a one-shot
//   uninstaller. A cancelled or denied authorization is the C++'s auth error, any other failure the uninstall
//   error. Only installations outside the home folder need it: a per-user installation (~/Library/Input
//   Methods, Installer's "Install for me only") is removed without administrator rights. The runner is
//   injectable (`PrivilegedCommandRunner`) so tests run the generated command unprivileged against a temporary
//   directory.
// - Paths (kRemovePaths): adapted to this port's install layout (Tools/make_installer_pkg.sh) and bundle id
//   io.github.subdiox.genmai.inputmethod.Japanese, which was chosen so that the Swift port and the C++ Mozc
//   (/Library/Input Methods/Mozc.app, /Applications/Mozc) can be installed side by side:
//     /Library/Input Methods/Genmai.app   (C++: /Library/Input Methods/Mozc.app; all users)
//     /Applications/Genmai                (C++: /Applications/Mozc; only 0.1.0 installed it)
//     ~/Library/Input Methods/Genmai.app  (this user only, or a development copy from Tools/make_ime_bundle.sh)
//   each only if it is there, and the bundles only if their CFBundleIdentifier is this port's, so the C++ Mozc
//   is never removed. The LaunchAgents plists of the converter / renderer are n/a: the Swift IME runs both
//   in-process and installs no LaunchAgents. Like the C++, the user's profile (~/Library/Application Support/
//   Genmai) is kept.
// - MacUtil::RemovePrelauncherLoginItem is n/a (the in-process design has no prelauncher login item).
// - RunReboot: the C++ runs /sbin/reboot as root (with a TODO to "use OS-specific API instead"). The port asks
//   loginwindow for a normal restart (the `restart` Apple event, kAERestart), which lets other apps save
//   their documents and needs no privileges.
// - The uninstall survey and the Keystone ticket removal are not ported (the OSS build does neither).

import AppKit
import Foundation
import Security
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

  /// /Applications/Genmai, where the 0.1.0 package put the uninstaller (later versions keep it inside the input
  /// method bundle).
  var applicationsFolder: URL {
    systemRoot.appending(path: "Applications/\(Self.kProductName)", directoryHint: .isDirectory)
  }

  /// The per-user installation (Installer's "Install for me only", or a copy of Tools/make_ime_bundle.sh's
  /// bundle); the system-wide location is `inputMethodBundle`.
  var manualInstallCandidates: [URL] {
    [homeDirectory.appending(path: "Library/Input Methods/\(Self.kProductName).app", directoryHint: .isDirectory)]
  }

  /// kRemovePaths: the input method installed for all users and the applications folder of an old version (both
  /// need administrator rights), then the input method installed for this user; each only if it is there.
  func removeItems() -> [RemoveItem] {
    var items: [RemoveItem] = []
    if Self.bundleIdentifier(at: inputMethodBundle) == Self.kBundleIdentifier {
      items.append(RemoveItem(kind: .inputMethod, path: inputMethodBundle.path(percentEncoded: false)))
    }
    if FileManager.default.fileExists(atPath: applicationsFolder.path(percentEncoded: false)) {
      items.append(RemoveItem(kind: .applicationsFolder, path: applicationsFolder.path(percentEncoded: false)))
    }
    for candidate in manualInstallCandidates
    where Self.bundleIdentifier(at: candidate) == Self.kBundleIdentifier {
      items.append(RemoveItem(kind: .userInputMethod, path: candidate.path(percentEncoded: false)))
    }
    return items
  }

  func removePaths() -> [String] { removeItems().map(\.path) }

  /// The user profile (settings, learning data, user dictionary; the AI model in `model/`).
  var profileDirectory: URL {
    homeDirectory.appending(path: "Library/Application Support/\(Self.kProductName)", directoryHint: .isDirectory)
  }

  /// Downloads of the model and app installers.
  var cachesDirectory: URL {
    homeDirectory.appending(path: "Library/Caches/\(Self.kProductName)", directoryHint: .isDirectory)
  }

  /// The user's data by kind, for the kinds that have files (the user chooses which ones to remove too). Files of
  /// the profile that belong to no other kind count as settings.
  func userDataItems() -> [UserDataItem] {
    let fm = FileManager.default
    let profileFiles = (try? fm.contentsOfDirectory(atPath: profileDirectory.path(percentEncoded: false))) ?? []
    func inProfile(_ names: [String]) -> [URL] { names.map { profileDirectory.appending(path: $0) } }
    var paths: [UserDataKind: [URL]] = [:]
    paths[.aiModel] = inProfile(profileFiles.filter { $0 == "model" }) + [cachesDirectory]
    paths[.userDictionary] = inProfile(profileFiles.filter { $0.hasPrefix("user_dictionary") })
    paths[.learning] = inProfile(profileFiles.filter { UserDataKind.learningFiles.contains($0) || $0.hasPrefix("ai_debug.log") })
    let classified = Set(paths.values.joined().map(\.lastPathComponent))
    paths[.settings] = inProfile(profileFiles.filter { !classified.contains($0) })
    return UserDataKind.allCases.compactMap { kind in
      let existing = (paths[kind] ?? []).filter { fm.fileExists(atPath: $0.path(percentEncoded: false)) }
      guard !existing.isEmpty else { return nil }
      return UserDataItem(
        kind: kind, paths: existing.map { $0.path(percentEncoded: false) },
        size: existing.reduce(0) { $0 + Self.allocatedSize(of: $1) })
    }
  }

  /// Removes the user data of `kinds` (as the user; no administrator rights needed). With every kind the profile
  /// and caches folders go entirely.
  func removeUserData(_ kinds: Set<UserDataKind>) throws {
    let items = userDataItems()
    let fm = FileManager.default
    if !items.isEmpty && Set(items.map(\.kind)).isSubset(of: kinds) {
      for directory in [profileDirectory, cachesDirectory] where fm.fileExists(atPath: directory.path(percentEncoded: false)) {
        try fm.removeItem(at: directory)
      }
      return
    }
    for item in items where kinds.contains(item.kind) {
      for path in item.paths where fm.fileExists(atPath: path) {
        try fm.removeItem(atPath: path)
      }
    }
  }

  /// Bytes of the file, or of everything in the folder.
  static func allocatedSize(of url: URL) -> Int64 {
    let fm = FileManager.default
    var isDirectory: ObjCBool = false
    guard fm.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) else { return 0 }
    guard isDirectory.boolValue else {
      return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0 ?? 0) } ?? 0
    }
    var total: Int64 = 0
    for case let file as URL in fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) ?? .init() {
      total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
    return total
  }

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

/// The kinds of user data the uninstaller can remove as well (each one optional).
enum UserDataKind: CaseIterable, Sendable, Hashable {
  /// `model/` in the profile and the download caches.
  case aiModel
  case userDictionary
  /// Conversion learning (user history, segment and boundary learning) and the AI debug log.
  case learning
  /// Everything else in the profile (config, AI and update settings).
  case settings

  static let removedByDefault: Set<UserDataKind> = [.aiModel]

  /// The learning files of the profile (Mozc's storage names).
  static let learningFiles: Set<String> = [".history.db", "segment.db", "boundary.db", ".encrypt_key.db"]
}

/// The user data of one kind: the existing paths and their size.
struct UserDataItem: Sendable, Equatable, Hashable {
  var kind: UserDataKind
  var paths: [String]
  var size: Int64
}

/// One path the uninstaller removes, with what it is (shown in the confirmation).
struct RemoveItem: Sendable, Equatable, Hashable {
  enum Kind: Sendable, Equatable, Hashable {
    /// /Library/Input Methods/Genmai.app.
    case inputMethod
    /// /Applications/Genmai of an old version.
    case applicationsFolder
    /// ~/Library/Input Methods/Genmai.app.
    case userInputMethod
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

/// Runs a /bin/sh command line as root.
@MainActor
protocol PrivilegedCommandRunner {
  func run(_ shellCommand: String) -> PrivilegedCommandResult
}

/// GetPrevilegeRights + AuthorizationExecuteWithPrivileges, like the C++: the system's authorization dialog (with
/// Touch ID), then `/bin/sh -c <command>` as root.
struct AuthorizationPrivilegedCommandRunner: PrivilegedCommandRunner {
  /// Authorization Services errors that mean "no rights were granted".
  static let kAuthorizationErrors: Set<OSStatus> = [
    errAuthorizationDenied, errAuthorizationCanceled, errAuthorizationInteractionNotAllowed,
  ]
  /// Printed after the command with its exit status (AuthorizationExecuteWithPrivileges does not report it).
  static let exitMarker = "genmai-uninstaller-exit:"

  /// The command line run as root: the command, then its exit status.
  static func script(for shellCommand: String) -> String {
    "\(shellCommand); echo \(exitMarker)$?"
  }

  /// The exit status in the command's output, nil if it is missing.
  static func exitStatus(in output: String) -> Int32? {
    guard let range = output.range(of: exitMarker, options: .backwards) else { return nil }
    return Int32(output[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private typealias ExecuteWithPrivileges = @convention(c) (
    AuthorizationRef, UnsafePointer<CChar>, AuthorizationFlags, UnsafePointer<UnsafeMutablePointer<CChar>?>,
    UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
  ) -> OSStatus

  func run(_ shellCommand: String) -> PrivilegedCommandResult {
    var authorization: AuthorizationRef?
    guard AuthorizationCreate(nil, nil, [], &authorization) == errAuthorizationSuccess, let authorization else {
      return .failed("AuthorizationCreate failed")
    }
    defer { AuthorizationFree(authorization, [.destroyRights]) }
    let status = kAuthorizationRightExecute.withCString { name in
      var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
      return withUnsafeMutablePointer(to: &item) { items in
        var rights = AuthorizationRights(count: 1, items: items)
        return AuthorizationCopyRights(
          authorization, &rights, nil, [.interactionAllowed, .extendRights, .preAuthorize], nil)
      }
    }
    if Self.kAuthorizationErrors.contains(status) {
      return .authorizationFailed
    }
    guard status == errAuthorizationSuccess else {
      return .failed("AuthorizationCopyRights: \(status)")
    }
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "AuthorizationExecuteWithPrivileges") else {
      return .failed("AuthorizationExecuteWithPrivileges is not available")
    }
    let execute = unsafeBitCast(symbol, to: ExecuteWithPrivileges.self)
    var pipe: UnsafeMutablePointer<FILE>?
    let words: [String] = ["-c", Self.script(for: shellCommand)]
    let arguments: [UnsafeMutablePointer<CChar>?] = words.map { strdup($0) }
    defer { arguments.forEach { free($0) } }
    let argv: [UnsafeMutablePointer<CChar>?] = arguments + [nil]
    let result = argv.withUnsafeBufferPointer { buffer in
      execute(authorization, "/bin/sh", [], buffer.baseAddress!, &pipe)
    }
    if Self.kAuthorizationErrors.contains(result) {
      return .authorizationFailed
    }
    guard result == errAuthorizationSuccess, let pipe else {
      return .failed("AuthorizationExecuteWithPrivileges: \(result)")
    }
    // The command's output until it exits (the pipe closes).
    var output = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = fread(&buffer, 1, buffer.count, pipe)
      if count <= 0 { break }
      output.append(contentsOf: buffer[0..<count])
    }
    fclose(pipe)
    let text = String(decoding: output, as: UTF8.self)
    return Self.exitStatus(in: text) == 0 ? .success : .failed(text)
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

  /// GetPrevilegeRights + DeleteFiles: the paths outside the home folder as root (one authorization), then the
  /// user's own ones without rights. Nothing is removed if the authorization is refused.
  func deleteFiles() -> PrivilegedCommandResult {
    let home = layout.homeDirectory.standardizedFileURL.path(percentEncoded: false)
    let paths = layout.removePaths()
    let system = paths.filter { !$0.hasPrefix(home) }
    if !system.isEmpty {
      let result = runner.run(Self.deleteCommand(for: system))
      if result != .success {
        if case .failed(let message) = result {
          NSLog("Failed to remove path: %@", message)
        }
        return result
      }
    }
    for path in paths where path.hasPrefix(home) && FileManager.default.fileExists(atPath: path) {
      do {
        try FileManager.default.removeItem(atPath: path)
      } catch {
        NSLog("Failed to remove path: %@", "\(error)")
        return .failed("\(error)")
      }
    }
    return .success
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
