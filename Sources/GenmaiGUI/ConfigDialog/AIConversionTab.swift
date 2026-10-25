// The "AI" tab of the config dialog (not part of Mozc): AI conversion with the local genmai model.
// Settings live in ai_conversion.json (AIConversionSettings), not in the Mozc Config proto.

import Foundation
import GenmaiClient
import SwiftUI

/// English / Japanese strings of the AI tab (Mozc's Qt translations do not have them).
public enum AIStrings {
  public enum Key: CaseIterable, Sendable {
    case tab, sectionAI, enable, explanation, sectionSettings, timeout, candidates, sectionModel, modelInstalled,
      modelInstalledUnknown, modelNotInstalled,
      modelUpToDate, download, update, downloadNote, downloading, verifying, installing, cancel, installFailed,
      remove, removeConfirm, removeFailed, checkingLatest, latestFailed, retry, size, sizeSmall, sizeMedium,
      sizeNote, checkAgain, saveFailed, milliseconds
  }

  static let english: [Key: String] = [
    .tab: "AI",
    .sectionAI: "AI conversion",
    .enable: "Use AI conversion",
    .explanation:
      "Converts with a local language model (genmai) in addition to the dictionary-based conversion and puts its result first when it differs. Your input is never sent over the network. Turned off, only the dictionary-based conversion is used.",
    .sectionSettings: "Settings",
    .timeout: "Maximum wait at the conversion key",
    .candidates: "Number of AI candidates",
    .sectionModel: "Model",
    .modelInstalled: "%@ %@ is installed.",
    .modelInstalledUnknown: "A model is installed (version unknown).",
    .modelNotInstalled: "No model is installed.",
    .size: "Model",
    .sizeSmall: "Small (%@, about %d MB of memory)",
    .sizeMedium: "Medium (%@, about %d MB of memory)",
    .sizeNote:
      "The medium model converts more accurately. The small model needs less memory and converts faster. The memory is what AI conversion adds to the input method while converting.",
    .modelUpToDate: "%@ %@ is the latest version.",
    .download: "Download %@ %@",
    .update: "Update to %@ %@",
    .downloadNote:
      "Downloads %@ from Hugging Face (%@) and installs it into the model folder. Only the model is downloaded; your input is never sent.",
    .downloading: "Downloading… %@ of %@",
    .verifying: "Verifying the download…",
    .installing: "Installing…",
    .cancel: "Cancel",
    .installFailed: "Could not install the model: %@",
    .checkingLatest: "Checking for the latest model…",
    .latestFailed: "Could not check for the latest model: %@",
    .retry: "Retry",
    .remove: "Remove Model…",
    .removeConfirm:
      "Remove the AI model from %@? AI conversion stops working until you download the model again (the settings are kept).",
    .removeFailed: "Could not remove the model: %@",
    .checkAgain: "Check again",
    .saveFailed: "Failed to save the AI conversion settings.",
    .milliseconds: "%d ms",
  ]

  static let japanese: [Key: String] = [
    .tab: "AI",
    .sectionAI: "AI 変換",
    .enable: "AI 変換を使う",
    .explanation:
      "辞書を用いた変換に加えてローカルの言語モデル (genmai) で変換し、結果が異なる場合はそれを第一候補にします。入力内容がネットワークに送信されることはありません。オフにすると辞書を用いた変換だけを使います。",
    .sectionSettings: "設定",
    .timeout: "変換キーでの最大待ち時間",
    .candidates: "AI 候補の数",
    .sectionModel: "モデル",
    .modelInstalled: "%1$@ %2$@ がインストールされています。",
    .modelInstalledUnknown: "モデルがインストールされています（バージョン不明）。",
    .modelNotInstalled: "モデルがインストールされていません。",
    .size: "モデル",
    .sizeSmall: "Small（%@、メモリ約 %d MB）",
    .sizeMedium: "Medium（%@、メモリ約 %d MB）",
    .sizeNote: "Medium のほうが正確に変換します。Small はメモリが少なく、変換も速くなります。メモリは、変換中に AI 変換が入力メソッドに加える使用量の目安です。",
    .modelUpToDate: "%1$@ %2$@ は最新版です。",
    .download: "%1$@ %2$@ をダウンロード",
    .update: "%1$@ %2$@ にアップデート",
    .downloadNote:
      "Hugging Face (%2$@) から %1$@ をダウンロードしてモデルのフォルダにインストールします。ダウンロードするのはモデルだけで、入力内容が送信されることはありません。",
    .downloading: "ダウンロード中… %@ / %@",
    .verifying: "ダウンロードを検証中…",
    .installing: "インストール中…",
    .cancel: "キャンセル",
    .installFailed: "モデルをインストールできませんでした: %@",
    .checkingLatest: "最新のモデルを確認中…",
    .latestFailed: "最新のモデルを確認できませんでした: %@",
    .retry: "再試行",
    .remove: "モデルを削除…",
    .removeConfirm: "%@ から AI モデルを削除しますか? もう一度ダウンロードするまで AI 変換は使えなくなります (設定はそのまま残ります)。",
    .removeFailed: "モデルを削除できませんでした: %@",
    .checkAgain: "再確認",
    .saveFailed: "AI 変換の設定を保存できませんでした。",
    .milliseconds: "%d ミリ秒",
  ]

  public static func text(_ key: Key, language: GUILanguage = .current) -> String {
    let table = language == .japanese ? japanese : english
    return GUIUtil.replaceString(table[key] ?? english[key] ?? "")
  }

  /// The model status line: which model and release is installed (the folder is managed by the installer and not
  /// shown).
  public static func modelStatus(_ status: AIModelStatus, language: GUILanguage = .current) -> String {
    switch status {
    case .found(_, let info?):
      return String(format: text(.modelInstalled, language: language), modelName(info), info.version)
    case .found(_, nil):
      return text(.modelInstalledUnknown, language: language)
    case .missing:
      return text(.modelNotInstalled, language: language)
    }
  }

  /// "genmai-90M" (the repository's name for a model this version does not know).
  public static func modelName(_ info: GenmaiModelInfo) -> String {
    info.size?.modelName ?? String(info.repository.split(separator: "/").last ?? "")
  }

  /// The model picker's item: "Small (genmai-90M, about 90 MB of memory)".
  public static func sizeName(_ size: AIModelSize, language: GUILanguage = .current) -> String {
    switch size {
    case .small: String(format: text(.sizeSmall, language: language), size.modelName, size.memoryMegabytes)
    case .medium: String(format: text(.sizeMedium, language: language), size.modelName, size.memoryMegabytes)
    }
  }

  /// A button title (`.download` / `.update`) or status line (`.modelUpToDate`) about `release`.
  public static func releaseText(_ key: Key, _ release: GenmaiModelRelease, language: GUILanguage = .current)
    -> String
  {
    String(format: text(key, language: language), modelName(release.info), release.info.version)
  }

  /// What the running installation is doing.
  public static func installPhase(_ phase: AIModelInstaller.Phase, language: GUILanguage = .current) -> String {
    switch phase {
    case .downloading(let received, let total):
      return String(format: text(.downloading, language: language), bytes(received), bytes(total))
    case .verifying:
      return text(.verifying, language: language)
    case .installing:
      return text(.installing, language: language)
    }
  }

  /// The explanation under the download button.
  public static func downloadNote(_ release: GenmaiModelRelease, language: GUILanguage = .current) -> String {
    String(format: text(.downloadNote, language: language), bytes(release.downloadSize), release.info.repository)
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

}

struct AIConversionTab: View {
  @Bindable var model: ConfigDialogModel

  var body: some View {
    Form {
      SettingsPaneHeader(pane: .ai)
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
      } header: {
        Text(verbatim: AIStrings.text(.sectionSettings))
      }
      .disabled(!model.aiValues.enabled)
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Picker(selection: $model.aiValues.modelSize) {
            ForEach(AIModelSize.allCases, id: \.self) { size in
              Text(verbatim: AIStrings.sizeName(size)).tag(size)
            }
          } label: {
            Text(verbatim: AIStrings.text(.size))
          }
          .disabled(model.aiModelInstall.isRunning)
          Text(verbatim: AIStrings.text(.sizeNote))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        AIModelStatusRow(status: model.aiModelStatus) {
          model.refreshAIModelStatus()
          Task { await model.checkLatestAIModel(force: true) }
        }
        AIModelInstallRow(model: model)
      } header: {
        Text(verbatim: AIStrings.text(.sectionModel))
      }
    }
    .formStyle(.grouped)
    .task(id: model.aiValues.modelSize) { await model.checkLatestAIModel() }
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
      Text(verbatim: AIStrings.modelStatus(status))
        .fixedSize(horizontal: false, vertical: true)
      Spacer()
      Button(AIStrings.text(.checkAgain), action: checkAgain)
    }
  }
}

/// Download / update of the newest model release from Hugging Face, with its progress.
struct AIModelInstallRow: View {
  let model: ConfigDialogModel

  var body: some View {
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
      AIModelLatestRow(model: model)
      if case .failed(let message) = model.aiModelInstall {
        Text(verbatim: String(format: AIStrings.text(.installFailed), message))
          .font(.callout)
          .foregroundStyle(.red)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
      if model.aiModelStatus.isFound {
        Button(AIStrings.text(.remove), role: .destructive) { model.removeAIModel() }
      }
    }
  }
}

/// What the newest release is and whether to download it.
struct AIModelLatestRow: View {
  let model: ConfigDialogModel

  var body: some View {
    switch model.aiModelLatest {
    case .unknown, .checking:
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
        Text(verbatim: AIStrings.text(.checkingLatest))
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    case .failed(let message):
      HStack(alignment: .firstTextBaseline) {
        Text(verbatim: String(format: AIStrings.text(.latestFailed), message))
          .font(.callout)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
        Spacer()
        Button(AIStrings.text(.retry)) {
          Task { await model.checkLatestAIModel(force: true) }
        }
      }
    case .available(let release):
      if model.aiModelStatus.needsInstall(release) {
        VStack(alignment: .leading, spacing: 6) {
          // "Update" only for a newer release of the installed model; another model is downloaded
          let update = model.aiModelStatus.installedSize == release.info.size
          Button(AIStrings.releaseText(update ? .update : .download, release)) {
            model.installAIModel()
          }
          Text(verbatim: AIStrings.downloadNote(release))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      } else {
        Text(verbatim: AIStrings.releaseText(.modelUpToDate, release))
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
  }
}
