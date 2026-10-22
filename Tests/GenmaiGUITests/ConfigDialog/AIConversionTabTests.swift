// Tests of the config dialog's AI tab (not part of Mozc): ai_conversion.json load / save with the dialog
// buttons, reset, the model status line and the strings.

import Foundation
import GenmaiClient
import Testing

@testable import GenmaiGUI

@MainActor
@Suite struct AIConversionTabTests {
  /// A temporary directory with an `ai_conversion.json` path in it.
  final class TempDir {
    let url = FileManager.default.temporaryDirectory.appending(path: "ai-tab-\(UUID())")
    var settings: URL { url.appending(path: AIConversionSettings.fileName) }
    init() { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: url) }
  }

  @Test func loadsEditsAndSavesWithTheConfig() throws {
    let dir = TempDir()
    try AIConversionSettings(enabled: false, timeoutMilliseconds: 500, candidateCount: 3).save(to: dir.settings)
    let client = ConfigDialogMockClient()
    let model = ConfigDialogModel(client: client, aiSettingsURL: dir.settings)
    #expect(model.aiValues.timeoutMilliseconds == 500)
    #expect(model.aiValues.candidateCount == 3)
    #expect(!model.applyEnabled)

    model.aiValues.enabled = true
    #expect(model.applyEnabled)
    model.apply()
    #expect(AIConversionSettings.load(from: dir.settings).enabled)
    // SET_CONFIG is still sent: that is what makes the IME reload (and re-read the AI settings).
    #expect(client.setConfigCalls.count == 1)
  }

  @Test func unchangedSettingsAreNotWritten() {
    let dir = TempDir()
    let model = ConfigDialogModel(client: ConfigDialogMockClient(), aiSettingsURL: dir.settings)
    #expect(model.aiValues == AIConversionSettings())
    model.apply()
    #expect(!FileManager.default.fileExists(atPath: dir.settings.path))
  }

  @Test func resetToDefaultsDisablesAI() throws {
    let dir = TempDir()
    try AIConversionSettings(enabled: true, timeoutMilliseconds: 1000).save(to: dir.settings)
    let model = ConfigDialogModel(client: ConfigDialogMockClient(), aiSettingsURL: dir.settings)
    model.performResetToDefaults()
    #expect(model.aiValues == AIConversionSettings())
    #expect(model.accept())
    #expect(AIConversionSettings.load(from: dir.settings) == AIConversionSettings())
  }

  @Test func modelDirectoryAndStatus() throws {
    let dir = TempDir()
    let model = ConfigDialogModel(client: ConfigDialogMockClient(), aiSettingsURL: dir.settings)
    model.aiModelDirectoryText = "  \(dir.url.path)  "
    #expect(model.aiValues.modelDirectory == dir.url.path)
    #expect(!model.aiModelStatus.isFound)
    let status = AIStrings.modelStatus(model.aiModelStatus, language: .english)
    #expect(status.hasPrefix("Model not found: \(dir.url.path)"))
    #expect(status.contains("model.safetensors"))
    for f in AIModelStatus.requiredFiles {
      try Data().write(to: dir.url.appending(path: f))
    }
    model.refreshAIModelStatus()
    #expect(model.aiModelStatus.isFound)
    #expect(model.aiModelStatus.needsInstall())  // no genmai_model.json
    #expect(AIStrings.modelStatus(model.aiModelStatus, language: .japanese).hasPrefix("モデルが見つかりました"))
    model.aiModelDirectoryText = ""
    #expect(model.aiValues.modelDirectory == nil)
    #expect(model.aiValues.resolvedModelDirectory == AIConversionSettings.defaultModelDirectory)
  }

  @Test func installsTheModelAndTellsTheIMEToReload() async throws {
    let dir = TempDir()
    let client = ConfigDialogMockClient()
    let model = ConfigDialogModel(client: client, aiSettingsURL: dir.settings)
    model.aiModelDirectoryText = dir.url.path
    #expect(model.aiModelStatus.needsInstall())
    let (phases, continuation) = AsyncStream<AIModelInstaller.Phase>.makeStream()
    model.aiModelInstaller = { directory, progress in
      progress(.downloading(received: 500, total: 1000))
      progress(.converting)
      for f in AIModelStatus.requiredFiles {
        try Data().write(to: directory.appending(path: f))
      }
      try GenmaiModelRelease.current.info.save(to: directory)
      continuation.finish()
    }
    model.installAIModel()
    #expect(model.aiModelInstall.isRunning)
    for await _ in phases {}
    while model.aiModelInstall.isRunning { await Task.yield() }
    #expect(model.aiModelInstall == .idle)
    #expect(model.aiModelStatus == .found(model.aiValues.resolvedModelDirectory, info: GenmaiModelRelease.current.info))
    #expect(!model.aiModelStatus.needsInstall())
    #expect(client.reloadCount == 1)
    #expect(AIStrings.modelVersion(model.aiModelStatus, language: .english) == "Version: genmai \(GenmaiModelRelease.current.info.version)")
  }

  @Test func failedOrCancelledInstallation() async throws {
    let dir = TempDir()
    let client = ConfigDialogMockClient()
    let model = ConfigDialogModel(client: client, aiSettingsURL: dir.settings)
    model.aiModelDirectoryText = dir.url.path
    model.aiModelInstaller = { _, _ in throw AIModelInstallError.download("model.safetensors", status: 404) }
    model.installAIModel()
    while model.aiModelInstall.isRunning { await Task.yield() }
    #expect(model.aiModelInstall == .failed("downloading model.safetensors failed (HTTP 404)"))
    #expect(client.reloadCount == 0)

    model.aiModelInstaller = { _, _ in try await Task.sleep(for: .seconds(60)) }
    model.installAIModel()
    #expect(model.aiModelInstall.isRunning)
    model.cancelAIModelInstall()
    while model.aiModelInstall.isRunning { await Task.yield() }
    #expect(model.aiModelInstall == .idle)
    #expect(!model.aiModelStatus.isFound)
    #expect(client.reloadCount == 0)
  }

  @Test func installStrings() {
    let downloading = AIStrings.installPhase(.downloading(received: 0, total: 1_000_000_000), language: .english)
    #expect(downloading.hasPrefix("Downloading… "))
    let note = AIStrings.downloadNote(language: .japanese)
    #expect(note.contains("subdiox/genmai"))
    #expect(AIStrings.modelVersion(.missing(URL(filePath: "/x"), missingFiles: []), language: .english) == nil)
    #expect(AIStrings.modelVersion(.found(URL(filePath: "/x"), info: nil), language: .japanese)?.contains("不明") == true)
  }

  @Test func everyStringIsTranslated() {
    for key in AIStrings.Key.allCases {
      #expect(AIStrings.english[key] != nil, "\(key)")
      #expect(AIStrings.japanese[key] != nil, "\(key)")
    }
    #expect(AIStrings.text(.enable, language: .japanese) == "AI 変換を使う")
    #expect(!AIStrings.text(.explanation, language: .english).contains("[ProductName]"))
  }

  @Test func pickerItems() {
    #expect(ConfigDialogModel.aiTimeoutItems.contains(AIConversionSettings.defaultTimeoutMilliseconds))
    #expect(ConfigDialogModel.aiCandidatePickerItems.map(\.0) == Array(AIConversionSettings.candidateCountRange))
  }
}
