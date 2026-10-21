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
    #expect(AIStrings.modelStatus(model.aiModelStatus, language: .japanese).hasPrefix("モデルが見つかりました"))
    model.aiModelDirectoryText = ""
    #expect(model.aiValues.modelDirectory == nil)
    #expect(model.aiValues.resolvedModelDirectory == AIConversionSettings.defaultModelDirectory)
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
