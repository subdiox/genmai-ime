// Tests of the welcome window's model (not part of Mozc).

import Foundation
import GenmaiClient
import Testing

@testable import GenmaiGUI

@MainActor
@Suite struct WelcomeModelTests {
  final class TempDir {
    let url = FileManager.default.temporaryDirectory.appending(path: "welcome-\(UUID())")
    var settings: URL { url.appending(path: AIConversionSettings.fileName) }
    var model: URL { url.appending(path: "model") }
    init() { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: url) }
  }

  nonisolated static let release = GenmaiModelRelease(
    info: GenmaiModelInfo(version: "0.1.0", repository: "subdiox/genmai-310M", revision: "v0.1.0"),
    files: [
      .init(name: "config.json", size: 10, checksum: .gitBlob("00")),
      .init(name: "tokenizer.json", size: 20, checksum: .gitBlob("00")),
      .init(name: "model-8bit.safetensors", size: 1000, checksum: .sha256("00")),
    ])

  @Test func enablingAIInstallsTheModelAndTurnsItOn() async throws {
    let dir = TempDir()
    try AIConversionSettings(modelDirectory: dir.model.path).save(to: dir.settings)
    let client = ConfigDialogMockClient()
    let model = WelcomeModel(client: client, settingsURL: dir.settings)
    #expect(model.aiState == .off)
    model.releaseFetcher = { size in
      #expect(size == .medium)
      return Self.release
    }
    model.installer = { release, directory, progress in
      progress(.downloading(received: 500, total: 1000))
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for f in AIModelStatus.requiredFiles {
        try Data().write(to: directory.appending(path: f))
      }
    }
    model.enableAI()
    #expect(model.aiState == .checking)
    while model.aiState != .enabled {
      if case .failed(let m) = model.aiState {
        Issue.record("failed: \(m)")
        return
      }
      await Task.yield()
    }
    #expect(AIConversionSettings.load(from: dir.settings).enabled)
    #expect(client.reloadCount == 1)
    // Opening it again shows AI as on.
    #expect(WelcomeModel(client: client, settingsURL: dir.settings).aiState == .enabled)
  }

  @Test func failureIsShownAndAIStaysOff() async throws {
    let dir = TempDir()
    try AIConversionSettings(modelDirectory: dir.model.path).save(to: dir.settings)
    let model = WelcomeModel(client: ConfigDialogMockClient(), settingsURL: dir.settings)
    model.releaseFetcher = { _ in throw AIModelInstallError.download("release list", status: 503) }
    model.enableAI()
    while model.aiState == .checking { await Task.yield() }
    #expect(model.aiState == .failed("downloading release list failed (HTTP 503)"))
    #expect(!AIConversionSettings.load(from: dir.settings).enabled)
  }

  @Test func markerFile() {
    let dir = TempDir()
    #expect(!GenmaiWelcome.wasShown(profile: dir.url.path))
    GenmaiWelcome.markShown(profile: dir.url.path)
    #expect(GenmaiWelcome.wasShown(profile: dir.url.path))
  }

  @Test func strings() {
    for key in WelcomeStrings.Key.allCases {
      #expect(WelcomeStrings.english[key] != nil, "\(key)")
      #expect(WelcomeStrings.japanese[key] != nil, "\(key)")
    }
    #expect(WelcomeStrings.text(.title, language: .japanese) == "Genmai へようこそ")
  }
}
