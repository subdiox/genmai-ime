// Tests of the config dialog's AI tab (not part of Mozc): ai_conversion.json load / save with the dialog
// buttons, reset, the model status line and the strings.

import Foundation
import GenmaiClient
import Synchronization
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
    #expect(!model.hasPendingChanges)

    model.aiValues.enabled = true
    #expect(model.hasPendingChanges)
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

  /// Fake model files (as `AIModelStatus.check` sees an installed model).
  nonisolated static func makeModel(in directory: URL, info: GenmaiModelInfo? = nil) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for f in AIModelStatus.requiredFiles + ["genmai.mlmodelc"] {
      try Data().write(to: directory.appending(path: f))
    }
    try info?.save(to: directory)
  }

  @Test func modelStatus() throws {
    let dir = TempDir()
    let model = ConfigDialogModel(client: ConfigDialogMockClient(), aiSettingsURL: dir.settings)
    model.aiValues.modelDirectory = dir.url.path
    #expect(!model.aiModelStatus().isFound)
    #expect(AIStrings.modelStatus(model.aiModelStatus(), language: .english) == "No model is installed.")
    #expect(AIStrings.rowStatus(model.aiModelStatus(), diskSize: nil, language: .english) == "Not installed")
    try Self.makeModel(in: dir.url)
    model.refreshAIModelStatus()
    #expect(model.aiModelStatus().isFound)
    #expect(model.aiModelStatus().needsInstall(Self.release))  // no genmai_model.json
    #expect(
      AIStrings.modelStatus(model.aiModelStatus(), language: .japanese) == "モデルがインストールされています（バージョン不明）。")
    try Self.release.info.save(to: dir.url)
    model.refreshAIModelStatus()
    // The folder is not shown: it is managed by the installer.
    #expect(
      AIStrings.modelStatus(model.aiModelStatus(), language: .japanese) == "genmai-310M 0.2.0 がインストールされています。")
    #expect(model.aiModelDiskSizes[.medium] != nil)
    #expect(
      AIStrings.rowStatus(model.aiModelStatus(), diskSize: 283_000_000, language: .english)
        == "Version 0.2.0 installed (283 MB on disk)")
    #expect(AIStrings.rowTitle(.small, language: .japanese) == "Small（genmai-90M）")
  }

  nonisolated static let release = GenmaiModelRelease(
    info: GenmaiModelInfo(version: "0.2.0", repository: "subdiox/genmai-310M", revision: "v0.2.0"),
    files: [
      .init(name: "config.json", size: 10, checksum: .gitBlob("00")),
      .init(name: "tokenizer.json", size: 20, checksum: .gitBlob("00")),
      .init(name: "model-coreml.zip", size: 1000, checksum: .sha256("00")),
    ])
  nonisolated static let smallRelease = GenmaiModelRelease(
    info: GenmaiModelInfo(version: "0.1.1", repository: "subdiox/genmai-90M", revision: "v0.1.1"),
    files: release.files)

  @Test func looksUpTheLatestReleases() async {
    let dir = TempDir()
    let model = ConfigDialogModel(client: ConfigDialogMockClient(), aiSettingsURL: dir.settings)
    #expect(model.aiModelLatest[.medium] == nil)
    model.aiModelReleaseFetcher = { _ in throw AIModelInstallError.download("release list", status: 503) }
    await model.checkLatestAIModels()
    #expect(model.aiModelLatest[.medium] == .failed("downloading release list failed (HTTP 503)"))
    model.installAIModel(.medium)  // nothing to install
    #expect(model.aiModelInstall == .idle)
    model.aiModelReleaseFetcher = { $0 == .small ? Self.smallRelease : Self.release }
    await model.checkLatestAIModels()
    #expect(model.aiModelLatest[.medium] == .available(Self.release))
    #expect(model.aiModelLatest[.small] == .available(Self.smallRelease))
    // not looked up again unless forced
    model.aiModelReleaseFetcher = { _ in throw CancellationError() }
    await model.checkLatestAIModels()
    #expect(model.aiModelLatest[.medium] == .available(Self.release))
    await model.checkLatestAIModel(.medium, force: true)
    #expect(model.aiModelLatest[.medium] != .available(Self.release))
    #expect(model.aiModelLatest[.small] == .available(Self.smallRelease))
  }

  /// Both models can be installed; each has its own directory (only the overridden one is written here).
  @Test func installsEachModelIntoItsDirectoryAndTellsTheIMEToReload() async throws {
    let dir = TempDir()
    let client = ConfigDialogMockClient()
    let model = ConfigDialogModel(client: client, aiSettingsURL: dir.settings)
    model.aiValues.modelDirectory = dir.url.appending(path: "medium").path
    model.aiModelReleaseFetcher = { $0 == .small ? Self.smallRelease : Self.release }
    await model.checkLatestAIModels()
    #expect(model.aiModelStatus(.medium).needsInstall(Self.release))
    let installed = Mutex<[URL]>([])
    model.aiModelInstaller = { release, directory, progress in
      progress(.downloading(received: 500, total: 1000))
      progress(.installing)
      progress(.preparing)
      try Self.makeModel(in: directory, info: release.info)
      installed.withLock { $0.append(directory) }
    }
    model.installAIModel(.medium)
    #expect(model.aiModelInstall.isRunning)
    #expect(model.aiModelInstallSize == .medium)
    model.installAIModel(.small)  // one at a time
    while model.aiModelInstall.isRunning { await Task.yield() }
    #expect(model.aiModelInstall == .idle)
    #expect(model.aiModelStatus(.medium) == .found(model.aiValues.resolvedModelDirectory, info: Self.release.info))
    #expect(!model.aiModelStatus(.medium).needsInstall(Self.release))
    #expect(!model.aiModelStatus(.small).isFound)
    #expect(client.reloadCount == 1)
    // the small model (not overridden) would go into its own directory
    #expect(installed.withLock { $0 } == [dir.url.appending(path: "medium", directoryHint: .isDirectory)])
    #expect(AIConversionSettings().modelDirectory(for: .small).lastPathComponent == "genmai-90M")
    #expect(AIStrings.releaseText(.download, Self.smallRelease, language: .english) == "Download genmai-90M 0.1.1")
    #expect(AIStrings.installPhase(.preparing, language: .japanese).hasPrefix("Neural Engine 用に"))
  }

  @Test func failedOrCancelledInstallation() async throws {
    let dir = TempDir()
    let client = ConfigDialogMockClient()
    let model = ConfigDialogModel(client: client, aiSettingsURL: dir.settings)
    model.aiValues.modelDirectory = dir.url.path
    model.aiModelReleaseFetcher = { _ in Self.release }
    await model.checkLatestAIModel(.medium)
    model.aiModelInstaller = { _, _, _ in throw AIModelInstallError.download("model-coreml.zip", status: 404) }
    model.installAIModel(.medium)
    while model.aiModelInstall.isRunning { await Task.yield() }
    #expect(model.aiModelInstall == .failed("downloading model-coreml.zip failed (HTTP 404)"))
    #expect(client.reloadCount == 0)

    model.aiModelInstaller = { _, _, _ in try await Task.sleep(for: .seconds(60)) }
    model.installAIModel(.medium)
    #expect(model.aiModelInstall.isRunning)
    model.cancelAIModelInstall()
    while model.aiModelInstall.isRunning { await Task.yield() }
    #expect(model.aiModelInstall == .idle)
    #expect(!model.aiModelStatus().isFound)
    #expect(client.reloadCount == 0)
  }

  @Test func removesOnlyTheChosenModelsFiles() throws {
    let dir = TempDir()
    let client = ConfigDialogMockClient()
    let model = ConfigDialogModel(client: client, aiSettingsURL: dir.settings)
    let modelDir = dir.url.appending(path: "model")
    model.aiValues.modelDirectory = modelDir.path
    try Self.makeModel(in: modelDir, info: Self.release.info)
    try Data().write(to: modelDir.appending(path: "notes.txt"))
    model.refreshAIModelStatus()
    #expect(model.aiModelStatus().isFound)

    model.removeAIModel(.medium)
    #expect(model.pendingMessage?.kind == .question)
    #expect(model.pendingMessage?.text.contains("genmai-310M") == true)
    #expect(model.aiModelStatus().isFound)  // nothing happens before the answer
    model.performRemoveAIModel(.medium)
    #expect(!model.aiModelStatus().isFound)
    #expect(client.reloadCount == 1)
    #expect(try FileManager.default.contentsOfDirectory(atPath: modelDir.path) == ["notes.txt"])

    // an otherwise empty model directory is removed too
    try FileManager.default.removeItem(at: modelDir.appending(path: "notes.txt"))
    try Self.makeModel(in: modelDir)
    model.refreshAIModelStatus()
    model.performRemoveAIModel(.medium)
    #expect(!FileManager.default.fileExists(atPath: modelDir.path))
  }

  @Test func removeIsOfferedOnlyForAnInstalledModel() {
    let dir = TempDir()
    let model = ConfigDialogModel(client: ConfigDialogMockClient(), aiSettingsURL: dir.settings)
    model.aiValues.modelDirectory = dir.url.appending(path: "none").path
    model.removeAIModel(.medium)
    #expect(model.pendingMessage == nil)
  }

  @Test func installStrings() {
    let downloading = AIStrings.installPhase(.downloading(received: 0, total: 1_000_000_000), language: .english)
    #expect(downloading.hasPrefix("Downloading… "))
    let note = AIStrings.downloadNote(Self.release, language: .japanese)
    #expect(note.contains("subdiox/genmai-310M"))
    #expect(AIStrings.sizeName(.small, language: .japanese) == "Small（genmai-90M、メモリ約 90 MB）")
    #expect(AIStrings.sizeName(.medium, language: .english) == "Medium (genmai-310M, about 150 MB of memory)")
    #expect(AIStrings.modelStatus(.found(URL(filePath: "/x"), info: nil), language: .japanese).contains("不明"))
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
