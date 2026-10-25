// Tests of the uninstaller logic (mac/Uninstaller has no C++ test). Nothing here touches the real install
// locations or asks for privileges: the layout points at a temporary directory and the deletion command is
// run unprivileged by /bin/sh (`ShellCommandRunner`), or recorded by a double. The controller tests drive the
// window's phases without showing it.

import AppKit
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

  @Test func authorizationScript() {
    let script = AuthorizationPrivilegedCommandRunner.script(for: Uninstaller.deleteCommand(for: ["/x"]))
    #expect(script == "/bin/rm -rf '/x'; echo genmai-uninstaller-exit:$?")
    #expect(AuthorizationPrivilegedCommandRunner.exitStatus(in: "genmai-uninstaller-exit:0\n") == 0)
    #expect(
      AuthorizationPrivilegedCommandRunner.exitStatus(in: "rm: x: Permission denied\ngenmai-uninstaller-exit:1\n") == 1)
    #expect(AuthorizationPrivilegedCommandRunner.exitStatus(in: "") == nil)
    #expect(AuthorizationPrivilegedCommandRunner.kAuthorizationErrors.contains(errAuthorizationCanceled))
  }

  @Test func perUserInstallNeedsNoAuthorization() async throws {
    let install = try FakeInstall()
    defer { install.remove() }
    try install.makeBundle(
      "Library/Input Methods/Genmai.app", identifier: UninstallerLayout.kBundleIdentifier, home: true)
    let runner = FixedCommandRunner(.authorizationFailed)
    let controller = UninstallerController(
      uninstaller: Uninstaller(layout: install.layout, runner: runner), language: .english, icon: NSImage(),
      terminate: {})
    #expect(controller.items.map(\.kind) == [.userInputMethod])
    #expect(!controller.needsAuthorization)
    await controller.uninstall()
    #expect(controller.phase == .succeeded)
    #expect(runner.commands.isEmpty)
    #expect(!install.exists("Library/Input Methods/Genmai.app", home: true))
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

  @Test func deleteFilesStopsAtTheFirstFailure() throws {
    let install = try FakeInstall()
    defer { install.remove() }
    try install.populate()
    // Make /Library/Input Methods read-only: removing Genmai.app fails, so the per-user copy stays.
    let inputMethods = install.url("Library/Input Methods")
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: inputMethods.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: inputMethods.path) }

    let uninstaller = Uninstaller(layout: install.layout, runner: ShellCommandRunner())
    guard case .failed = uninstaller.deleteFiles() else {
      Issue.record("expected a failure")
      return
    }
    #expect(install.exists("Library/Input Methods/Genmai.app"))
    #expect(install.exists("Library/Input Methods/Genmai.app", home: true))
  }

  @Test func removeItemsDescribeEachPath() throws {
    let install = try FakeInstall()
    defer { install.remove() }
    try install.populate()
    let items = install.layout.removeItems()
    #expect(items.map(\.kind) == [.inputMethod, .userInputMethod])
    #expect(items.map(\.path) == install.layout.removePaths())
    #expect(
      RemoveItem(kind: .inputMethod, path: "/Library/Input Methods/Genmai.app/").displayPath
        == "/Library/Input Methods/Genmai.app")
    let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
    #expect(
      RemoveItem(kind: .userInputMethod, path: home + "Library/Input Methods/Genmai.app/").displayPath
        == "~/Library/Input Methods/Genmai.app")
  }

  @Test func strings() {
    let english = UninstallerStrings(.english)
    let japanese = UninstallerStrings(.japanese)
    #expect(english.windowTitle == "Uninstall Genmai")
    #expect(japanese.windowTitle == "Genmaiのアンインストール")
    #expect(english.uninstall == "Uninstall…")
    #expect(japanese.uninstall == "アンインストール…")
    #expect(english.logOutNow == "Log Out Now")
    #expect(japanese.logOutNow == "今すぐログアウト")
    #expect(japanese.later == "後で")
    #expect(japanese.keptNote.contains("再インストール"))
    for strings in [english, japanese] {
      for text in [
        strings.confirmMessage(needsAuthorization: true), strings.confirmMessage(needsAuthorization: false),
        strings.succeededMessage, strings.removalFailedMessage,
      ] {
        #expect(!text.contains("Mozc") && !text.contains("Google") && !text.contains("..."))
      }
    }
  }
}

/// Makes a controller over a fake install whose deletion returns `result`, counting log-outs and quits.
@MainActor
struct ControllerFixture {
  let runner: FixedCommandRunner
  let terminated = Counter()
  let logOuts = Counter()
  let controller: UninstallerController

  init(_ result: PrivilegedCommandResult, language: UninstallerLanguage = .english) throws {
    let runner = FixedCommandRunner(result)
    let logOuts = self.logOuts
    let terminated = self.terminated
    // Installed for all users: removing it needs the (fake) authorization.
    let install = try FakeInstall()
    try install.makeBundle("Library/Input Methods/Genmai.app", identifier: UninstallerLayout.kBundleIdentifier)
    var uninstaller = Uninstaller(layout: install.layout, runner: runner)
    uninstaller.logOut = {
      logOuts.count += 1
      return true
    }
    self.runner = runner
    controller = UninstallerController(
      uninstaller: uninstaller, language: language, icon: NSImage(), terminate: { terminated.count += 1 })
  }
}

@MainActor
@Suite struct UninstallerControllerTests {
  @Test func cancelTerminatesWithoutUninstalling() throws {
    let fixture = try ControllerFixture(.success)
    #expect(fixture.controller.phase == .confirm)
    #expect(fixture.controller.items.map(\.kind) == [.inputMethod])
    #expect(fixture.controller.needsAuthorization)
    fixture.controller.close()
    #expect(fixture.terminated.count == 1)
    #expect(fixture.runner.commands.isEmpty)
  }

  @Test(arguments: [true, false])
  func successOffersLogOut(logOutNow: Bool) async throws {
    let install = try FakeInstall()
    defer { install.remove() }
    try install.populate()
    let terminated = Counter()
    let logOuts = Counter()
    var uninstaller = Uninstaller(layout: install.layout, runner: ShellCommandRunner())
    uninstaller.logOut = {
      logOuts.count += 1
      return true
    }
    let controller = UninstallerController(
      uninstaller: uninstaller, language: .japanese, icon: NSImage(), terminate: { terminated.count += 1 })
    await controller.uninstall()
    #expect(controller.phase == .succeeded)
    #expect(!install.exists("Library/Input Methods/Genmai.app"))
    #expect(terminated.count == 0)
    if logOutNow {
      controller.logOutNow()
    } else {
      controller.close()  // "後で"
    }
    #expect(logOuts.count == (logOutNow ? 1 : 0))
    #expect(terminated.count == 1)
  }

  @Test func authorizationFailureDeletesNothingAndCanBeRetried() async throws {
    let fixture = try ControllerFixture(.authorizationFailed)
    await fixture.controller.uninstall()
    #expect(fixture.controller.phase == .failed(.authorization))
    #expect(fixture.runner.commands.count == 1)
    // Logging out is only offered after a success.
    fixture.controller.logOutNow()
    #expect(fixture.logOuts.count == 0)
    #expect(fixture.terminated.count == 0)
    await fixture.controller.uninstall()  // Try Again
    #expect(fixture.runner.commands.count == 2)
    fixture.controller.close()  // Quit
    #expect(fixture.terminated.count == 1)
  }

  @Test func commandFailureReportsRemovalError() async throws {
    let fixture = try ControllerFixture(.failed("rm"))
    await fixture.controller.uninstall()
    #expect(fixture.controller.phase == .failed(.removal))
    #expect(fixture.logOuts.count == 0)
    #expect(fixture.terminated.count == 0)
  }

  @Test func uninstallRunsOnceAfterSuccess() async throws {
    let fixture = try ControllerFixture(.success)
    await fixture.controller.uninstall()
    await fixture.controller.uninstall()
    #expect(fixture.runner.commands.count == 1)
  }
}

// MARK: - User data

@MainActor
@Suite struct UninstallerUserDataTests {
  /// A profile like the IME writes: settings, learning, user dictionary, the AI model and a download cache.
  static func makeProfile(_ install: FakeInstall) throws {
    let profile = "Library/Application Support/Genmai/"
    for name in [
      "config1.db", "ai_conversion.json", "update.json", ".config_dialog..lock", "user_dictionary.db", ".history.db",
      "segment.db", "boundary.db", ".encrypt_key.db", "ai_debug.log", "models/genmai-310M/genmai_coreml.json",
      "models/genmai-310M/config.json",
    ] {
      try install.makeFile(profile + name, home: true)
    }
    try install.makeFile("Library/Caches/Genmai/download/v1.0.0/model-coreml.zip", home: true)
  }

  @Test func classifiesTheProfile() throws {
    let install = try FakeInstall()
    defer { install.remove() }
    #expect(install.layout.userDataItems().isEmpty)
    try Self.makeProfile(install)
    let items = install.layout.userDataItems()
    #expect(items.map(\.kind) == [.aiModel, .userDictionary, .learning, .settings])
    func names(_ kind: UserDataKind) -> Set<String> {
      Set(items.first { $0.kind == kind }!.paths.map { URL(filePath: $0).lastPathComponent })
    }
    #expect(names(.aiModel) == ["models", "Genmai"])  // the profile's models folder and ~/Library/Caches/Genmai
    #expect(names(.userDictionary) == ["user_dictionary.db"])
    #expect(names(.learning) == [".history.db", "segment.db", "boundary.db", ".encrypt_key.db", "ai_debug.log"])
    #expect(names(.settings) == ["config1.db", "ai_conversion.json", "update.json", ".config_dialog..lock"])
    #expect(items.allSatisfy { $0.size > 0 })
  }

  @Test func byDefaultOnlyTheAIModelIsRemoved() async throws {
    let install = try FakeInstall()
    defer { install.remove() }
    try install.populate()
    try Self.makeProfile(install)
    let controller = UninstallerController(
      uninstaller: Uninstaller(layout: install.layout, runner: ShellCommandRunner()), language: .english,
      icon: NSImage(), terminate: {})
    #expect(controller.selectedUserData == [.aiModel])
    await controller.uninstall()
    #expect(controller.phase == .succeeded)
    #expect(!install.exists("Library/Application Support/Genmai/model", home: true))
    #expect(!install.exists("Library/Caches/Genmai", home: true))
    #expect(install.exists("Library/Application Support/Genmai/user_dictionary.db", home: true))
    #expect(install.exists("Library/Application Support/Genmai/segment.db", home: true))
    #expect(install.exists("Library/Application Support/Genmai/config1.db", home: true))
  }

  @Test func chosenKindsAreRemoved() async throws {
    let install = try FakeInstall()
    defer { install.remove() }
    try install.populate()
    try Self.makeProfile(install)
    let controller = UninstallerController(
      uninstaller: Uninstaller(layout: install.layout, runner: ShellCommandRunner()), language: .english,
      icon: NSImage(), terminate: {})
    controller.selectedUserData = [.learning]
    await controller.uninstall()
    #expect(!install.exists("Library/Application Support/Genmai/.history.db", home: true))
    #expect(!install.exists("Library/Application Support/Genmai/ai_debug.log", home: true))
    #expect(install.exists("Library/Application Support/Genmai/models/genmai-310M/genmai_coreml.json", home: true))
    #expect(install.exists("Library/Application Support/Genmai/user_dictionary.db", home: true))
  }

  @Test func everythingChosenRemovesTheFolders() throws {
    let install = try FakeInstall()
    defer { install.remove() }
    try Self.makeProfile(install)
    try install.layout.removeUserData(Set(UserDataKind.allCases))
    #expect(!install.exists("Library/Application Support/Genmai", home: true))
    #expect(!install.exists("Library/Caches/Genmai", home: true))
    #expect(install.layout.userDataItems().isEmpty)
  }

  @Test func nothingIsRemovedWithoutAuthorization() async throws {
    let install = try FakeInstall()
    defer { install.remove() }
    try install.makeBundle("Library/Input Methods/Genmai.app", identifier: UninstallerLayout.kBundleIdentifier)
    try Self.makeProfile(install)
    let controller = UninstallerController(
      uninstaller: Uninstaller(layout: install.layout, runner: FixedCommandRunner(.authorizationFailed)),
      language: .english, icon: NSImage(), terminate: {})
    controller.selectedUserData = Set(UserDataKind.allCases)
    await controller.uninstall()
    #expect(controller.phase == .failed(.authorization))
    #expect(install.exists("Library/Application Support/Genmai/models/genmai-310M/genmai_coreml.json", home: true))
    #expect(install.exists("Library/Application Support/Genmai/config1.db", home: true))
  }

  @Test func strings() {
    for language in [UninstallerLanguage.english, .japanese] {
      let strings = UninstallerStrings(language)
      for kind in UserDataKind.allCases {
        #expect(!strings.userDataName(kind).isEmpty)
        #expect(!strings.userDataDetail(kind).isEmpty)
      }
    }
    #expect(UninstallerStrings(.japanese).userDataName(.userDictionary) == "ユーザー辞書")
  }
}
