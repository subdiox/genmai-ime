// Port of mozc/src/gui/error_message_dialog/error_message_dialog.{h,cc} (3.35.6354).
//
// The fatal error message box whose OK button is disabled for the first 3 seconds
// (DeleyedMessageDialogHandler).

import SwiftUI

public enum ErrorMessageDialog {
  /// The message for `--error_type`, or nil for an unknown type (Show() does nothing then).
  public static func message(forErrorType errorType: String, language: GUILanguage = .current)
    -> String?
  {
    // defining all literal messages inside Show() method for easy i18n/i10n
    let source: String
    switch errorType {
    case "server_timeout":
      source = "Conversion engine is not responding. Please restart this application."
    case "server_broken_message":
      source =
        "Connecting to an incompatible conversion engine. Please restart your computer to enable [ProductName]. If this problem persists, please uninstall [ProductName] and install it again."
    case "server_version_mismatch":
      source =
        "Conversion engine has been upgraded. Please restart this application to enable conversion engine. If the problem persists, please restart your computer."
    case "server_shutdown":
      source = "Conversion engine is killed unexceptionally. Restarting the engine..."
    case "server_fatal":
      source = "Cannot start conversion engine. Please restart your computer."
    case "renderer_version_mismatch":
      source =
        "Candidate window renderer has been upgraded. Please restart this application to enable new candidate window renderer. If the problem persists, please restart your computer."
    case "renderer_fatal":
      source = "Cannot start candidate window renderer. Please restart your computer."
    default:
      return nil
    }
    return tr("QObject", source, language: language)
  }

  public static func title(language: GUILanguage = .current) -> String {
    tr("QObject", "[ProductName] Fatal Error", language: language)
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
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "exclamationmark.octagon.fill")
          .font(.largeTitle)
          .foregroundStyle(.red)
          .accessibilityHidden(true)
        Text(verbatim: message)
          .fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        Spacer()
        Button("OK") { closeDialog() }
          .keyboardShortcut(.defaultAction)
          .disabled(!isOKEnabled)
      }
    }
    .padding(20)
    .frame(width: 420)
    .navigationTitle(ErrorMessageDialog.title())
    .task {
      try? await Task.sleep(for: ErrorMessageDialog.disableInterval)
      isOKEnabled = true
    }
  }
}
