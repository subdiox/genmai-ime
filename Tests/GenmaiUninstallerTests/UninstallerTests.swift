// Tests of the uninstaller logic (mac/Uninstaller has no C++ test). Nothing here touches the real install
// locations or asks for privileges: the layout points at a temporary directory and the deletion command is
// run unprivileged by /bin/sh (`ShellCommandRunner`), or recorded by a double.

import Foundation
import GenmaiBase
import Testing

@testable import GenmaiUninstaller

/// A temporary "/" and "~" with the installed files of the port (and of the C++ Mozc, which must survive).
struct FakeInstall {
  let root: URL
  let layout: UninstallerLayout

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appending(path: "GenmaiUninstallerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    layout = UninstallerLayout(
      systemRoot: root.appending(path: "root", directoryHint: .isDirectory),
      homeDirectory: root.appending(path: "home", directoryHint: .isDirectory))
  }

  func url(_ relative: String, home: Bool = false) -> URL {
    (home ? layout.homeDirectory : layout.systemRoot).appending(path: relative)
  }

  func makeBundle(_ relative: String, identifier: String, home: Bool = false) throws {
    let contents = url(relative, home: home).appending(path: "Contents")
    try FileManager.default.createDirectory(
      at: contents.appending(path: "MacOS"), withIntermediateDirectories: true)
    let plist = try PropertyListSerialization.data(
      fromPropertyList: ["CFBundleIdentifier": identifier], format: .xml, options: 0)
    try plist.write(to: contents.appending(path: "Info.plist"))
    try Data("binary".utf8).write(to: contents.appending(path: "MacOS/GenmaiIME"))
  }

  func makeFile(_ relative: String, home: Bool = false) throws {
    let file = url(relative, home: home)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: file)
  }

  func exists(_ relative: String, home: Bool = false) -> Bool {
    FileManager.default.fileExists(atPath: url(relative, home: home).path(percentEncoded: false))
  }

  /// The port as installed by the .pkg, a manual install in ~, and files that are not ours.
  func populate() throws {
    try makeBundle("Library/Input Methods/Genmai.app", identifier: UninstallerLayout.kBundleIdentifier)
    try makeBundle(
      "Applications/Genmai/UninstallGenmai.app",
      identifier: "io.github.subdiox.genmai.inputmethod.Japanese.Uninstaller")
    try makeFile("Applications/Genmai/.localized/ja.strings")
    try makeBundle(
      "Library/Input Methods/Genmai.app", identifier: UninstallerLayout.kBundleIdentifier, home: true)
    // The C++ Mozc and its LaunchAgents, and the user's profile.
    try makeBundle("Library/Input Methods/Mozc.app", identifier: "org.mozc.inputmethod.Japanese")
    try makeBundle("Applications/Mozc/UninstallMozc.app", identifier: "org.mozc.inputmethod.Japanese.Uninstaller")
    try makeFile("Library/LaunchAgents/org.mozc.inputmethod.Japanese.Converter.plist")
    try makeFile("Library/Application Support/Mozc/config1.db", home: true)
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }
}

/// Runs the privileged command as the current user with /bin/sh (only ever against a temporary directory).
@MainActor
final class ShellCommandRunner: PrivilegedCommandRunner {
  private(set) var commands: [String] = []

  func run(_ shellCommand: String) -> PrivilegedCommandResult {
    commands.append(shellCommand)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", shellCommand]
    do {
      try process.run()
    } catch {
      return .failed(error.localizedDescription)
    }
    process.waitUntilExit()
    return process.terminationStatus == 0 ? .success : .failed("exit \(process.terminationStatus)")
  }
}

/// Returns a fixed result without running anything.
@MainActor
final class FixedCommandRunner: PrivilegedCommandRunner {
  let result: PrivilegedCommandResult
  private(set) var commands: [String] = []

  init(_ result: PrivilegedCommandResult) {
    self.result = result
  }

  func run(_ shellCommand: String) -> PrivilegedCommandResult {
    commands.append(shellCommand)
    return result
  }
}

/// Answers every dialog immediately and records which ones were shown.
@MainActor
final class RecordingDialogs: UninstallerDialogs {
  enum Report: Equatable {
    case authError
    case uninstallSuccess
    case uninstallError
  }

  var answer: Bool
  private(set) var reports: [Report] = []

  init(answer: Bool) {
    self.answer = answer
  }

  func reportAuthError() async -> Bool {
    reports.append(.authError)
    return answer
  }

  func reportUninstallSuccess() async -> Bool {
    reports.append(.uninstallSuccess)
    return answer
  }

  func reportUninstallError() async -> Bool {
    reports.append(.uninstallError)
    return answer
  }
}

@MainActor
final class Counter {
  var count = 0
}

@MainActor
@Suite struct UninstallerTests {
  @Test func installedLayoutPaths() {
    let layout = UninstallerLayout(
      systemRoot: URL(fileURLWithPath: "/"), homeDirectory: URL(fileURLWithPath: "/Users/nobody"))
    #expect(layout.inputMethodBundle.path(percentEncoded: false) == "/Library/Input Methods/Genmai.app/")
    #expect(layout.applicationsFolder.path(percentEncoded: false) == "/Applications/Genmai/")
    #expect(
      layout.manualInstallCandidates.map { $0.path(percentEncoded: false) } == [
        "/Users/nobody/Library/Input Methods/Genmai.app/"
      ])
  }

  @Test func removePathsSelectsOnlyThisPortsManualInstalls() throws {
    let install = try FakeInstall()
    defer { install.remove() }
    try install.populate()
    let paths = install.layout.removePaths()
    #expect(
      paths == [
        install.layout.inputMethodBundle.path(percentEncoded: false),
        install.layout.applicationsFolder.path(percentEncoded: false),
        install.url("Library/Input Methods/Genmai.app/", home: true).path(percentEncoded: false),
      ])
    // The C++ Mozc's /Library/Input Methods/Mozc.app has another bundle id.
    #expect(!paths.contains(install.url("Library/Input Methods/Mozc.app/").path(percentEncoded: false)))
    #expect(
      UninstallerLayout.bundleIdentifier(at: install.url("Library/Input Methods/Mozc.app"))
        == "org.mozc.inputmethod.Japanese")
    #expect(UninstallerLayout.bundleIdentifier(at: install.url("Library/Input Methods/None.app")) == nil)
  }

  @Test func shellQuoting() {
    #expect(Uninstaller.shellQuoted("/Library/Input Methods/A.app") == "'/Library/Input Methods/A.app'")
    #expect(Uninstaller.shellQuoted("it's") == #"'it'\''s'"#)
    #expect(
      Uninstaller.deleteCommand(for: ["/a b", "/c"]) == "/bin/rm -rf '/a b' && /bin/rm -rf '/c'")
  }

  @Test func appleScriptSource() {
    let command = Uninstaller.deleteCommand(for: [#"/x "y" \z"#])
    #expect(
      AppleScriptPrivilegedCommandRunner.source(for: command)
        == #"do shell script "/bin/rm -rf '/x \"y\" \\z'" with administrator privileges"#)
    #expect(AppleScriptPrivilegedCommandRunner.kAuthorizationErrorNumbers.contains(-128))
    #expect(AppleScriptPrivilegedCommandRunner.kAuthorizationErrorNumbers.contains(-60006))
  }

  @Test func deleteFilesRemovesThePortAndKeepsEverythingElse() throws {
    let install = try FakeInstall()
    defer { install.remove() }
    try install.populate()
    let runner = ShellCommandRunner()
    let uninstaller = Uninstaller(layout: install.layout, runner: runner)
    #expect(uninstaller.deleteFiles() == .success)
    #expect(runner.commands.count == 1)

    #expect(!install.exists("Library/Input Methods/Genmai.app"))
    #expect(!install.exists("Applications/Genmai"))
    #expect(!install.exists("Library/Input Methods/Genmai.app", home: true))
    // Not ours: the C++ Mozc, its LaunchAgents and folder, and the user profile.
    #expect(install.exists("Library/Input Methods/Mozc.app/Contents/MacOS/GenmaiIME"))
    #expect(install.exists("Applications/Mozc/UninstallMozc.app"))
    #expect(install.exists("Library/LaunchAgents/org.mozc.inputmethod.Japanese.Converter.plist"))
    #expect(install.exists("Library/Application Support/Mozc/config1.db", home: true))
    #expect(install.exists("Library/Input Methods"))

    // rm -rf of paths that are already gone succeeds (uninstalling twice).
    #expect(uninstaller.deleteFiles() == .success)
  }

  @Test func deleteFilesStopsAtTheFirstFailure() async throws {
    let install = try FakeInstall()
    defer { install.remove() }
    try install.populate()
    // Make /Library/Input Methods read-only: removing Genmai.app fails, so /Applications/Genmai stays.
    let inputMethods = install.url("Library/Input Methods")
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: inputMethods.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: inputMethods.path) }

    let dialogs = RecordingDialogs(answer: true)
    let reboots = Counter()
    var uninstaller = Uninstaller(layout: install.layout, runner: ShellCommandRunner())
    uninstaller.reboot = {
      reboots.count += 1
      return true
    }
    await uninstaller.doUninstall(dialogs)
    #expect(dialogs.reports == [.uninstallError])
    #expect(reboots.count == 0)
    #expect(install.exists("Library/Input Methods/Genmai.app"))
    #expect(install.exists("Applications/Genmai/UninstallGenmai.app"))
  }

  @Test(arguments: [true, false])
  func successOffersRestart(restartNow: Bool) async throws {
    let install = try FakeInstall()
    defer { install.remove() }
    try install.populate()
    let dialogs = RecordingDialogs(answer: restartNow)
    let reboots = Counter()
    var uninstaller = Uninstaller(layout: install.layout, runner: ShellCommandRunner())
    uninstaller.reboot = {
      reboots.count += 1
      return true
    }
    await uninstaller.doUninstall(dialogs)
    #expect(dialogs.reports == [.uninstallSuccess])
    #expect(reboots.count == (restartNow ? 1 : 0))
    #expect(!install.exists("Library/Input Methods/Genmai.app"))
  }

  @Test func authorizationFailureDeletesNothing() async throws {
    let dialogs = RecordingDialogs(answer: true)
    let reboots = Counter()
    let runner = FixedCommandRunner(.authorizationFailed)
    var uninstaller = Uninstaller(layout: try FakeInstall().layout, runner: runner)
    uninstaller.reboot = {
      reboots.count += 1
      return true
    }
    await uninstaller.doUninstall(dialogs)
    #expect(dialogs.reports == [.authError])
    #expect(reboots.count == 0)
    #expect(runner.commands.count == 1)
  }

  @Test func commandFailureReportsUninstallError() async throws {
    let dialogs = RecordingDialogs(answer: true)
    let uninstaller = Uninstaller(layout: try FakeInstall().layout, runner: FixedCommandRunner(.failed("rm")))
    await uninstaller.doUninstall(dialogs)
    #expect(dialogs.reports == [.uninstallError])
  }

  @Test func strings() {
    #expect(UninstallerStrings.confirm(.english).message == "Are you sure you want to uninstall Genmai?")
    #expect(UninstallerStrings.confirm(.japanese).message == "Genmaiを削除してもよろしいですか？")
    #expect(UninstallerStrings.confirm(.japanese).title == "確認")
    #expect(UninstallerStrings.uninstallSucceeded(.english).okButton == "Restart now")
    #expect(UninstallerStrings.uninstallSucceeded(.english).cancelButton == "Later")
    #expect(UninstallerStrings.uninstallSucceeded(.japanese).okButton == "再起動")
    #expect(UninstallerStrings.uninstallSucceeded(.japanese).cancelButton == "後で")
    #expect(UninstallerStrings.authError(.japanese).title == "認証の失敗")
    #expect(UninstallerStrings.authError(.english).cancelButton == nil)
    #expect(UninstallerStrings.uninstallError(.english).message == "Uninstallation failed.  Please try again.")
  }
}

@MainActor
@Suite struct DialogsControllerTests {
  @Test func cancelTerminatesWithoutUninstalling() throws {
    let runner = FixedCommandRunner(.success)
    let terminated = Counter()
    let controller = DialogsController(
      uninstaller: Uninstaller(layout: try FakeInstall().layout, runner: runner), language: .english,
      terminate: { terminated.count += 1 })
    #expect(controller.dialog == .confirm)
    #expect(controller.strings.title == "Uninstall")
    controller.cancel()
    #expect(terminated.count == 1)
    #expect(runner.commands.isEmpty)
  }

  @Test func successDialogWaitsForTheUser() async throws {
    let runner = FixedCommandRunner(.success)
    let terminated = Counter()
    let reboots = Counter()
    var uninstaller = Uninstaller(layout: try FakeInstall().layout, runner: runner)
    uninstaller.reboot = {
      reboots.count += 1
      return true
    }
    let controller = DialogsController(
      uninstaller: uninstaller, language: .japanese, terminate: { terminated.count += 1 })
    let task = Task { await controller.runUninstall() }
    while controller.dialog != .uninstallSucceeded {
      await Task.yield()
    }
    #expect(controller.strings.title == "削除の完了")
    #expect(terminated.count == 0)
    controller.dialogCancel()  // "後で"
    await task.value
    #expect(reboots.count == 0)
    #expect(terminated.count == 1)
    #expect(runner.commands.count == 1)
  }

  @Test func authErrorDialogThenTerminate() async throws {
    let terminated = Counter()
    let controller = DialogsController(
      uninstaller: Uninstaller(layout: try FakeInstall().layout, runner: FixedCommandRunner(.authorizationFailed)),
      language: .english, terminate: { terminated.count += 1 })
    let task = Task { await controller.runUninstall() }
    while controller.dialog != .authError {
      await Task.yield()
    }
    #expect(controller.strings.message.hasPrefix("Authentication failed."))
    controller.dialogOK()
    await task.value
    #expect(terminated.count == 1)
  }
}
