// Tests of the update UI model (not part of Mozc).

import Foundation
import GenmaiClient
import Testing

@testable import GenmaiGUI

@MainActor
@Suite struct GenmaiUpdateModelTests {
  final class TempDir {
    let url = FileManager.default.temporaryDirectory.appending(path: "update-ui-\(UUID())")
    var settings: URL { url.appending(path: GenmaiUpdateSettings.fileName) }
    init() { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: url) }
  }

  nonisolated static let release = GenmaiAppRelease(
    version: "0.2.0", tag: "v0.2.0", pageURL: URL(string: "https://example.com/r")!, notes: "**new**",
    package: .init(name: "Genmai-0.2.0.pkg", url: URL(string: "https://example.com/p.pkg")!, size: 1000, sha256: nil))

  @Test func checksAndRecordsTheCheck() async {
    let dir = TempDir()
    let model = GenmaiUpdateModel(settingsURL: dir.settings, currentVersion: "0.1.0")
    model.fetcher = { Self.release }
    await model.checkIfAutomatic()
    #expect(model.latest == .available(Self.release))
    #expect(model.availableRelease == Self.release)
    #expect(GenmaiUpdateSettings.load(from: dir.settings).lastCheck != nil)

    let current = GenmaiUpdateModel(settingsURL: dir.settings, currentVersion: "0.2.0")
    current.fetcher = { Self.release }
    await current.check()
    #expect(current.latest == .upToDate("0.2.0"))
    current.fetcher = { nil }
    await current.check()
    #expect(current.latest == .upToDate("0.2.0"))
    current.fetcher = { throw GenmaiUpdateError.download("release list", status: 403) }
    await current.check()
    #expect(current.latest == .failed("downloading the release list failed (HTTP 403)"))
  }

  @Test func automaticCheckSetting() async {
    let dir = TempDir()
    let model = GenmaiUpdateModel(settingsURL: dir.settings, currentVersion: "0.1.0")
    #expect(model.automaticCheck)
    model.automaticCheck = false
    #expect(!GenmaiUpdateSettings.load(from: dir.settings).automaticCheck)
    model.fetcher = { Self.release }
    await model.checkIfAutomatic()
    #expect(model.latest == .unknown)
    model.skip(Self.release)
    #expect(GenmaiUpdateSettings.load(from: dir.settings) == GenmaiUpdateSettings(automaticCheck: false, skippedVersion: "0.2.0"))
  }

  @Test func downloadsAndOpensTheInstaller() async {
    let dir = TempDir()
    let model = GenmaiUpdateModel(settingsURL: dir.settings, currentVersion: "0.1.0")
    model.fetcher = { Self.release }
    await model.check()
    let package = dir.url.appending(path: "Genmai-0.2.0.pkg")
    model.downloader = { release, progress in
      progress(500, release.package.size)
      return package
    }
    var opened: [URL] = []
    model.openInstaller = { opened.append($0); return true }
    model.installUpdate()
    #expect(model.install == .downloading(received: 0, total: 1000))
    while case .downloading = model.install { await Task.yield() }
    #expect(model.install == .opened)
    #expect(opened == [package])

    model.downloader = { _, _ in throw GenmaiUpdateError.damaged("Genmai-0.2.0.pkg") }
    model.installUpdate()
    while case .downloading = model.install { await Task.yield() }
    #expect(model.install == .failed("Genmai-0.2.0.pkg is damaged (size or checksum mismatch)"))
  }

  @Test func cancel() async {
    let dir = TempDir()
    let model = GenmaiUpdateModel(settingsURL: dir.settings, currentVersion: "0.1.0")
    model.fetcher = { Self.release }
    await model.check()
    model.downloader = { _, _ in
      try await Task.sleep(for: .seconds(60))
      return URL(filePath: "/")
    }
    model.installUpdate()
    model.cancelInstall()
    while case .downloading = model.install { await Task.yield() }
    #expect(model.install == .idle)
  }

  @Test func strings() {
    for key in UpdateStrings.Key.allCases {
      #expect(UpdateStrings.english[key] != nil, "\(key)")
      #expect(UpdateStrings.japanese[key] != nil, "\(key)")
    }
    #expect(String(format: UpdateStrings.text(.available, language: .japanese), "0.2.0") == "Genmai 0.2.0 が利用可能です。")
    #expect(UpdateStrings.downloading(received: 0, total: 0, language: .japanese).hasPrefix("ダウンロード中… "))
    #expect(String(UpdateDialogView.notes("**new**").characters) == "new")
  }
}
