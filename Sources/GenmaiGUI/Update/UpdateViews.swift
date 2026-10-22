// The "Updates" section of the config dialog (tab "Misc") and the update dialog (not part of Mozc).

import Foundation
import GenmaiClient
import SwiftUI

/// English / Japanese strings of the update UI (Mozc's Qt translations do not have them).
public enum UpdateStrings {
  public enum Key: CaseIterable, Sendable {
    case section, automaticCheck, currentVersion, checkNow, checking, upToDate, available, install, downloading,
      cancel, installerOpened, checkFailed, installFailed, skip, later, releaseNotes, dialogTitle
  }

  static let english: [Key: String] = [
    .section: "Updates",
    .automaticCheck: "Check for updates automatically",
    .currentVersion: "Current version: %@",
    .checkNow: "Check Now",
    .checking: "Checking for updates…",
    .upToDate: "[ProductName] is up to date.",
    .available: "[ProductName] %@ is available.",
    .install: "Download and Install",
    .downloading: "Downloading… %@ of %@",
    .cancel: "Cancel",
    .installerOpened: "The installer is open. Follow its steps to finish the update.",
    .checkFailed: "Could not check for updates: %@",
    .installFailed: "Could not download the update: %@",
    .skip: "Skip This Version",
    .later: "Later",
    .releaseNotes: "Release notes",
    .dialogTitle: "[ProductName] Update",
  ]

  static let japanese: [Key: String] = [
    .section: "アップデート",
    .automaticCheck: "アップデートを自動的に確認する",
    .currentVersion: "現在のバージョン: %@",
    .checkNow: "今すぐ確認",
    .checking: "アップデートを確認中…",
    .upToDate: "[ProductName] は最新版です。",
    .available: "[ProductName] %@ が利用可能です。",
    .install: "ダウンロードしてインストール",
    .downloading: "ダウンロード中… %1$@ / %2$@",
    .cancel: "キャンセル",
    .installerOpened: "インストーラを開きました。画面の指示に従ってアップデートを完了してください。",
    .checkFailed: "アップデートを確認できませんでした: %@",
    .installFailed: "アップデートをダウンロードできませんでした: %@",
    .skip: "このバージョンをスキップ",
    .later: "あとで",
    .releaseNotes: "リリースノート",
    .dialogTitle: "[ProductName] のアップデート",
  ]

  public static func text(_ key: Key, language: GUILanguage = .current) -> String {
    let table = language == .japanese ? japanese : english
    return GUIUtil.replaceString(table[key] ?? english[key] ?? "")
  }

  static func downloading(received: Int64, total: Int64, language: GUILanguage = .current) -> String {
    String(
      format: text(.downloading, language: language), received.formatted(.byteCount(style: .file)),
      total.formatted(.byteCount(style: .file)))
  }
}

/// The config dialog's section: automatic checks, the current version and the update state.
struct UpdateSection: View {
  @Bindable var update: GenmaiUpdateModel

  var body: some View {
    Section {
      Toggle(isOn: $update.automaticCheck) { Text(verbatim: UpdateStrings.text(.automaticCheck)) }
      UpdateStatusView(update: update)
    } header: {
      Text(verbatim: UpdateStrings.text(.section))
    }
    .task { await update.checkIfAutomatic() }
  }
}

/// The version line, the result of the last check and the download.
struct UpdateStatusView: View {
  let update: GenmaiUpdateModel
  /// False in the update dialog, which has its own button row.
  var showsInstallButton = true

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text(verbatim: String(format: UpdateStrings.text(.currentVersion), update.currentVersion))
          .textSelection(.enabled)
        Spacer()
        Button(UpdateStrings.text(.checkNow)) { Task { await update.check() } }
          .disabled(update.latest == .checking || update.install != .idle && update.install != .opened)
      }
      UpdateLatestView(update: update)
      UpdateInstallView(update: update, showsInstallButton: showsInstallButton)
    }
  }
}

struct UpdateLatestView: View {
  let update: GenmaiUpdateModel

  var body: some View {
    switch update.latest {
    case .unknown:
      EmptyView()
    case .checking:
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
        Text(verbatim: UpdateStrings.text(.checking))
          .foregroundStyle(.secondary)
      }
      .font(.callout)
    case .upToDate:
      Label {
        Text(verbatim: UpdateStrings.text(.upToDate))
      } icon: {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
      }
      .font(.callout)
    case .failed(let message):
      Text(verbatim: String(format: UpdateStrings.text(.checkFailed), message))
        .font(.callout)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    case .available(let release):
      HStack(alignment: .firstTextBaseline) {
        Label {
          Text(verbatim: String(format: UpdateStrings.text(.available), release.version))
        } icon: {
          Image(systemName: "arrow.down.circle.fill")
            .foregroundStyle(.blue)
        }
        Link(UpdateStrings.text(.releaseNotes), destination: release.pageURL)
      }
      .font(.callout)
    }
  }
}

struct UpdateInstallView: View {
  let update: GenmaiUpdateModel
  let showsInstallButton: Bool

  var body: some View {
    switch update.install {
    case .downloading(let received, let total):
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: UpdateStrings.downloading(received: received, total: total))
            .monospacedDigit()
            .font(.callout)
          ProgressView(value: Double(received), total: Double(max(total, 1)))
        }
        Button(UpdateStrings.text(.cancel)) { update.cancelInstall() }
      }
    case .opened:
      Text(verbatim: UpdateStrings.text(.installerOpened))
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    case .idle, .failed:
      if showsInstallButton, update.availableRelease != nil {
        Button(UpdateStrings.text(.install)) { update.installUpdate() }
      }
      if case .failed(let message) = update.install {
        Text(verbatim: String(format: UpdateStrings.text(.installFailed), message))
          .font(.callout)
          .foregroundStyle(.red)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

/// The update dialog (app screen update_dialog): checks when shown and offers the newest release with its notes.
public struct UpdateDialogView: View {
  @State private var update: GenmaiUpdateModel
  @Environment(\.closeDialog) private var closeDialog

  public init(update: GenmaiUpdateModel = GenmaiUpdateModel()) {
    _update = State(initialValue: update)
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Image(nsImage: NSApplication.shared.applicationIconImage)
          .resizable()
          .frame(width: 64, height: 64)
          .accessibilityHidden(true)
        Text(verbatim: UpdateStrings.text(.dialogTitle))
          .font(.title2)
          .accessibilityAddTraits(.isHeader)
      }
      UpdateStatusView(update: update, showsInstallButton: false)
      if let release = update.availableRelease, !release.notes.isEmpty {
        ScrollView {
          Text(Self.notes(release.notes))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .frame(minHeight: 120, maxHeight: 240)
        .background(.background, in: .rect(cornerRadius: 6))
      }
      HStack {
        if let release = update.availableRelease, update.install == .idle {
          Button(UpdateStrings.text(.skip)) {
            update.skip(release)
            closeDialog()
          }
        }
        Spacer()
        Button(UpdateStrings.text(.later)) { closeDialog() }
          .keyboardShortcut(.cancelAction)
        if update.availableRelease != nil, update.install == .idle {
          Button(UpdateStrings.text(.install)) { update.installUpdate() }
            .keyboardShortcut(.defaultAction)
        }
      }
    }
    .padding(20)
    .frame(width: 480)
    .task { await update.check() }
  }

  /// Release notes are Markdown; inline formatting is kept, line breaks are preserved.
  static func notes(_ markdown: String) -> AttributedString {
    (try? AttributedString(
      markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(markdown)
  }
}
