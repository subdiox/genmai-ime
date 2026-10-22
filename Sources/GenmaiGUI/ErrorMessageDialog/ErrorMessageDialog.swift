// Port of mozc/src/gui/error_message_dialog/error_message_dialog.{h,cc} (3.35.6354).
//
// The fatal error message box whose OK button is disabled for the first 3 seconds
// (DeleyedMessageDialogHandler). The layout is a native alert (app icon with a caution badge, headline, message,
// full-width button) instead of Qt's QMessageBox; the messages are Genmai's wording (`ErrorMessageStrings`).

import AppKit
import SwiftUI

/// English / Japanese strings of the error dialog.
enum ErrorMessageStrings {
  enum Key: CaseIterable, Sendable {
    case windowTitle, headline, ok, serverTimeout, serverBrokenMessage, serverVersionMismatch, serverShutdown,
      serverFatal, rendererVersionMismatch, rendererFatal
  }

  static let english: [Key: String] = [
    .windowTitle: "\(kProductNameInEnglish) Error",
    .headline: "\(kProductNameInEnglish) Encountered a Problem",
    .ok: "OK",
    .serverTimeout: "The conversion engine isn’t responding. Quit and reopen the app you’re typing in.",
    .serverBrokenMessage:
      "\(kProductNameInEnglish) is connected to an incompatible conversion engine. Restart your Mac to use \(kProductNameInEnglish). If the problem persists, uninstall \(kProductNameInEnglish) and install it again.",
    .serverVersionMismatch:
      "The conversion engine was updated. Quit and reopen the app you’re typing in to use the new engine. If the problem persists, restart your Mac.",
    .serverShutdown: "The conversion engine quit unexpectedly. Restarting it…",
    .serverFatal: "The conversion engine can’t start. Restart your Mac.",
    .rendererVersionMismatch:
      "The candidate window was updated. Quit and reopen the app you’re typing in to use the new candidate window. If the problem persists, restart your Mac.",
    .rendererFatal: "The candidate window can’t start. Restart your Mac.",
  ]

  static let japanese: [Key: String] = [
    .windowTitle: "\(kProductNameInEnglish) エラー",
    .headline: "\(kProductNameInEnglish) で問題が発生しました",
    .ok: "OK",
    .serverTimeout: "変換エンジンが応答していません。入力中のアプリケーションを終了して、もう一度開いてください。",
    .serverBrokenMessage:
      "互換性のない変換エンジンに接続しています。\(kProductNameInEnglish) を使うには Mac を再起動してください。問題が解決しない場合は、\(kProductNameInEnglish) をアンインストールしてから、もう一度インストールしてください。",
    .serverVersionMismatch:
      "変換エンジンがアップデートされました。新しい変換エンジンを使うには、入力中のアプリケーションを終了して、もう一度開いてください。問題が解決しない場合は Mac を再起動してください。",
    .serverShutdown: "変換エンジンが予期せず終了しました。再起動しています…",
    .serverFatal: "変換エンジンを起動できません。Mac を再起動してください。",
    .rendererVersionMismatch:
      "候補ウィンドウがアップデートされました。新しい候補ウィンドウを使うには、入力中のアプリケーションを終了して、もう一度開いてください。問題が解決しない場合は Mac を再起動してください。",
    .rendererFatal: "候補ウィンドウを起動できません。Mac を再起動してください。",
  ]

  static func text(_ key: Key, language: GUILanguage = .current) -> String {
    let table = language == .japanese ? japanese : english
    return table[key] ?? english[key] ?? ""
  }
}

public enum ErrorMessageDialog {
  /// The message for `--error_type`, or nil for an unknown type (Show() does nothing then).
  public static func message(forErrorType errorType: String, language: GUILanguage = .current)
    -> String?
  {
    let key: ErrorMessageStrings.Key
    switch errorType {
    case "server_timeout": key = .serverTimeout
    case "server_broken_message": key = .serverBrokenMessage
    case "server_version_mismatch": key = .serverVersionMismatch
    case "server_shutdown": key = .serverShutdown
    case "server_fatal": key = .serverFatal
    case "renderer_version_mismatch": key = .rendererVersionMismatch
    case "renderer_fatal": key = .rendererFatal
    default: return nil
    }
    return ErrorMessageStrings.text(key, language: language)
  }

  /// The window title.
  public static func title(language: GUILanguage = .current) -> String {
    ErrorMessageStrings.text(.windowTitle, language: language)
  }

  /// kDisableInterval of DeleyedMessageDialogHandler.
  public static let disableInterval: Duration = .milliseconds(3000)
}

public struct ErrorMessageDialogView: View {
  let message: String
  @State private var isOKEnabled = false
  @Environment(\.closeDialog) private var closeDialog

  public init(message: String) {
    self.message = message
  }

  public var body: some View {
    VStack(spacing: 0) {
      ErrorMessageIcon()
        .padding(.bottom, 14)
      Text(verbatim: ErrorMessageStrings.text(.headline))
        .font(.headline)
        .padding(.bottom, 6)
      Text(verbatim: message)
        .font(.callout)
        .padding(.bottom, 20)
      Button {
        closeDialog()
      } label: {
        Text(verbatim: ErrorMessageStrings.text(.ok))
          .frame(maxWidth: .infinity)
      }
      .controlSize(.large)
      .keyboardShortcut(.defaultAction)
      .disabled(!isOKEnabled)
    }
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
    .padding(20)
    .frame(width: 300)
    .navigationTitle(ErrorMessageDialog.title())
    .task {
      try? await Task.sleep(for: ErrorMessageDialog.disableInterval)
      isOKEnabled = true
    }
  }
}

/// The app icon with a caution badge, like a critical NSAlert.
struct ErrorMessageIcon: View {
  private let icon = NSApplication.shared.applicationIconImage ?? NSImage()

  var body: some View {
    Image(nsImage: icon)
      .resizable()
      .frame(width: 64, height: 64)
      .overlay(alignment: .bottomTrailing) {
        Image(systemName: "exclamationmark.triangle.fill")
          .symbolRenderingMode(.multicolor)
          .font(.system(size: 26))
          .offset(x: 4, y: 4)
      }
      .accessibilityHidden(true)
  }
}
