// The "AI" tab of the config dialog (not part of Mozc): AI conversion with the local genmai model.
// Settings live in ai_conversion.json (AIConversionSettings), not in the Mozc Config proto.

import Foundation
import GenmaiClient
import SwiftUI

/// English / Japanese strings of the AI tab (Mozc's Qt translations do not have them).
public enum AIStrings {
  public enum Key: CaseIterable, Sendable {
    case tab, sectionAI, enable, explanation, sectionSettings, timeout, candidates, modelDirectory,
      modelDirectoryPlaceholder, sectionModel, modelFound, modelMissing, modelVersion, modelVersionUnknown,
      modelUpToDate, download, update, downloadNote, downloading, verifying, converting, cancel, installFailed,
      checkAgain, saveFailed, milliseconds
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
    .modelVersion: "Version: genmai %@",
    .modelVersionUnknown: "Version: unknown (not installed from a release)",
    .modelUpToDate: "genmai %@ is the latest version.",
    .download: "Download genmai %@",
    .update: "Update to genmai %@",
    .downloadNote:
      "Downloads %@ from Hugging Face (%@) and installs it into the model folder (%@ on disk). Only the model is downloaded; your input is never sent.",
    .downloading: "Downloading… %@ of %@",
    .verifying: "Verifying the download…",
    .converting: "Installing…",
    .cancel: "Cancel",
    .installFailed: "Could not install the model: %@",
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
    .modelVersion: "バージョン: genmai %@",
    .modelVersionUnknown: "バージョン: 不明 (リリースからインストールされていません)",
    .modelUpToDate: "genmai %@ は最新版です。",
    .download: "genmai %@ をダウンロード",
    .update: "genmai %@ にアップデート",
    .downloadNote:
      "Hugging Face (%2$@) から %1$@ をダウンロードしてモデルのフォルダにインストールします (ディスク上は %3$@)。ダウンロードするのはモデルだけで、入力内容が送信されることはありません。",
    .downloading: "ダウンロード中… %@ / %@",
    .verifying: "ダウンロードを検証中…",
    .converting: "インストール中…",
    .cancel: "キャンセル",
    .installFailed: "モデルをインストールできませんでした: %@",
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
    case .found(let url, _):
      return String(format: text(.modelFound, language: language), url.path)
    case .missing(let url, let files):
      return String(format: text(.modelMissing, language: language), url.path, files.joined(separator: ", "))
    }
  }

  /// The installed version line (nil when no model is found).
  public static func modelVersion(_ status: AIModelStatus, language: GUILanguage = .current) -> String? {
    guard case .found(_, let info) = status else { return nil }
    guard let info else { return text(.modelVersionUnknown, language: language) }
    return String(format: text(.modelVersion, language: language), info.version)
  }

  /// What the running installation is doing.
  public static func installPhase(_ phase: AIModelInstaller.Phase, language: GUILanguage = .current) -> String {
    switch phase {
    case .downloading(let received, let total):
      return String(format: text(.downloading, language: language), bytes(received), bytes(total))
    case .verifying:
      return text(.verifying, language: language)
    case .converting:
      return text(.converting, language: language)
    }
  }

  /// The explanation under the download button.
  public static func downloadNote(_ release: GenmaiModelRelease = .current, language: GUILanguage = .current) -> String {
    // The converted weights are half the size of the downloaded fp32 file.
    String(
      format: text(.downloadNote, language: language), bytes(release.downloadSize), release.info.repository,
      bytes(release.downloadSize / 2))
  }

  static func bytes(_ count: Int64) -> String {
    count.formatted(.byteCount(style: .file))
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
        .disabled(model.aiModelInstall.isRunning)
      } header: {
        Text(verbatim: AIStrings.text(.sectionSettings))
      }
      .disabled(!model.aiValues.enabled)
      Section {
        AIModelStatusRow(status: model.aiModelStatus) { model.refreshAIModelStatus() }
        AIModelInstallRow(model: model)
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
        if let version = AIStrings.modelVersion(status) {
          Text(verbatim: version)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      Button(AIStrings.text(.checkAgain), action: checkAgain)
    }
  }
}

/// Download / update of the model from Hugging Face, with its progress.
struct AIModelInstallRow: View {
  let model: ConfigDialogModel

  var body: some View {
    let release = GenmaiModelRelease.current
    switch model.aiModelInstall {
    case .running(let phase):
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: AIStrings.installPhase(phase))
            .monospacedDigit()
          if case .downloading(let received, let total) = phase {
            ProgressView(value: Double(received), total: Double(max(total, 1)))
          } else {
            ProgressView()
              .progressViewStyle(.linear)
          }
        }
        Button(AIStrings.text(.cancel)) { model.cancelAIModelInstall() }
      }
    case .idle, .failed:
      if model.aiModelStatus.needsInstall(release) {
        VStack(alignment: .leading, spacing: 6) {
          Button(String(format: AIStrings.text(model.aiModelStatus.isFound ? .update : .download), release.info.version)) {
            model.installAIModel()
          }
          Text(verbatim: AIStrings.downloadNote(release))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          if case .failed(let message) = model.aiModelInstall {
            Text(verbatim: String(format: AIStrings.text(.installFailed), message))
              .font(.callout)
              .foregroundStyle(.red)
              .textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      } else {
        Text(verbatim: String(format: AIStrings.text(.modelUpToDate), release.info.version))
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
  }
}
