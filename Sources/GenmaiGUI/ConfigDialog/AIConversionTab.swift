// The "AI" tab of the config dialog (not part of Mozc): AI conversion with the local genmai model.
// Settings live in ai_conversion.json (AIConversionSettings), not in the Mozc Config proto.

import Foundation
import GenmaiClient
import SwiftUI

/// English / Japanese strings of the AI tab (Mozc's Qt translations do not have them).
public enum AIStrings {
  public enum Key: CaseIterable, Sendable {
    case tab, sectionAI, enable, explanation, sectionSettings, timeout, candidates, modelDirectory,
      modelDirectoryPlaceholder, sectionModel, modelFound, modelMissing, modelHowTo, checkAgain, saveFailed,
      milliseconds
  }

  static let english: [Key: String] = [
    .tab: "AI",
    .sectionAI: "AI conversion",
    .enable: "Use AI conversion",
    .explanation:
      "Converts with a local language model (genmai) in addition to Genmai and puts its result first when it differs. Your input is never sent over the network. Turned off, [ProductName] converts exactly as before.",
    .sectionSettings: "Settings",
    .timeout: "Maximum wait at the conversion key",
    .candidates: "Number of AI candidates",
    .modelDirectory: "Model folder",
    .modelDirectoryPlaceholder: "Default",
    .sectionModel: "Model",
    .modelFound: "Model found: %@",
    .modelMissing: "Model not found: %@ (missing %@)",
    .modelHowTo: "Prepare it with Tools/prepare_genmai_model.sh in the genmai-ime repository.",
    .checkAgain: "Check again",
    .saveFailed: "Failed to save the AI conversion settings.",
    .milliseconds: "%d ms",
  ]

  static let japanese: [Key: String] = [
    .tab: "AI",
    .sectionAI: "AI 変換",
    .enable: "AI 変換を使う",
    .explanation:
      "Genmai に加えてローカルの言語モデル (genmai) で変換し、結果が異なる場合はそれを第一候補にします。入力内容がネットワークに送信されることはありません。オフにすると [ProductName] は従来どおりに変換します。",
    .sectionSettings: "設定",
    .timeout: "変換キーでの最大待ち時間",
    .candidates: "AI 候補の数",
    .modelDirectory: "モデルのフォルダ",
    .modelDirectoryPlaceholder: "既定",
    .sectionModel: "モデル",
    .modelFound: "モデルが見つかりました: %@",
    .modelMissing: "モデルが見つかりません: %@ (%@ がありません)",
    .modelHowTo: "genmai-ime リポジトリの Tools/prepare_genmai_model.sh で準備してください。",
    .checkAgain: "再確認",
    .saveFailed: "AI 変換の設定を保存できませんでした。",
    .milliseconds: "%d ミリ秒",
  ]

  public static func text(_ key: Key, language: GUILanguage = .current) -> String {
    let table = language == .japanese ? japanese : english
    return GUIUtil.replaceString(table[key] ?? english[key] ?? "")
  }

  /// The model status line.
  public static func modelStatus(_ status: AIModelStatus, language: GUILanguage = .current) -> String {
    switch status {
    case .found(let url):
      return String(format: text(.modelFound, language: language), url.path)
    case .missing(let url, let files):
      return String(format: text(.modelMissing, language: language), url.path, files.joined(separator: ", "))
    }
  }
}

extension ConfigDialogModel {
  static let aiTimeoutItems: [Int] = [100, 200, 300, 500, 1000, 2000]

  static var aiTimeoutPickerItems: [(Int, String)] {
    aiTimeoutItems.map { ($0, String(format: AIStrings.text(.milliseconds), $0)) }
  }

  static var aiCandidatePickerItems: [(Int, String)] {
    AIConversionSettings.candidateCountRange.map { ($0, "\($0)") }
  }

  /// The model folder text field: "" = the default folder.
  public var aiModelDirectoryText: String {
    get { aiValues.modelDirectory ?? "" }
    set {
      let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
      aiValues.modelDirectory = trimmed.isEmpty ? nil : trimmed
    }
  }
}

struct AIConversionTab: View {
  @Bindable var model: ConfigDialogModel

  var body: some View {
    Form {
      Section {
        ConfigToggle(label: AIStrings.text(.enable), isOn: $model.aiValues.enabled)
        Text(verbatim: AIStrings.text(.explanation))
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } header: {
        Text(verbatim: AIStrings.text(.sectionAI))
      }
      Section {
        ConfigPicker(
          label: AIStrings.text(.timeout), selection: $model.aiValues.timeoutMilliseconds,
          items: ConfigDialogModel.aiTimeoutPickerItems)
        ConfigPicker(
          label: AIStrings.text(.candidates), selection: $model.aiValues.candidateCount,
          items: ConfigDialogModel.aiCandidatePickerItems)
        TextField(
          text: $model.aiModelDirectoryText,
          prompt: Text(verbatim: AIStrings.text(.modelDirectoryPlaceholder))
        ) {
          Text(verbatim: AIStrings.text(.modelDirectory))
        }
      } header: {
        Text(verbatim: AIStrings.text(.sectionSettings))
      }
      .disabled(!model.aiValues.enabled)
      Section {
        AIModelStatusRow(status: model.aiModelStatus) { model.refreshAIModelStatus() }
      } header: {
        Text(verbatim: AIStrings.text(.sectionModel))
      }
    }
    .formStyle(.grouped)
  }
}

struct AIModelStatusRow: View {
  let status: AIModelStatus
  let checkAgain: () -> Void

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Image(systemName: status.isFound ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        .foregroundStyle(status.isFound ? .green : .orange)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(verbatim: AIStrings.modelStatus(status))
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
        if !status.isFound {
          Text(verbatim: AIStrings.text(.modelHowTo))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer()
      Button(AIStrings.text(.checkAgain), action: checkAgain)
    }
  }
}
