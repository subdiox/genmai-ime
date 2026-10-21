// Shared plumbing for the SwiftUI dialogs (replaces QDialog accept()/reject() and the window helpers of
// gui/base: singleton_window_helper, window_title_modifier).

import SwiftUI

/// Closes the window hosting the dialog. The host (GenmaiTool) installs it; `QDialog::accept/reject` map to it.
public struct CloseDialogAction: Sendable {
  private let action: @MainActor @Sendable () -> Void

  public init(_ action: @escaping @MainActor @Sendable () -> Void) {
    self.action = action
  }

  @MainActor public func callAsFunction() { action() }
}

extension EnvironmentValues {
  /// The action that closes the hosting dialog window. Defaults to a no-op (previews, tests).
  @Entry public var closeDialog = CloseDialogAction {}
}

/// Presents modal alerts the way QMessageBox::{information,warning,critical,question} does.
/// Dialog view models expose `pendingMessage` and the views attach `.genmaiMessageAlert($model.pendingMessage)`.
public struct GUIMessage: Identifiable, Sendable, Equatable {
  public enum Kind: Sendable, Equatable {
    case information
    case warning
    case critical
    /// Yes/No question; `onYes` runs when accepted.
    case question
  }

  public let id = UUID()
  public var kind: Kind
  public var title: String
  public var text: String
  public var onYes: (@MainActor @Sendable () -> Void)?

  public init(
    kind: Kind, title: String, text: String, onYes: (@MainActor @Sendable () -> Void)? = nil
  ) {
    self.kind = kind
    self.title = title
    self.text = text
    self.onYes = onYes
  }

  public static func == (lhs: GUIMessage, rhs: GUIMessage) -> Bool { lhs.id == rhs.id }
}

extension View {
  /// Shows `message` as an alert while it is non-nil.
  public func genmaiMessageAlert(_ message: Binding<GUIMessage?>) -> some View {
    modifier(GUIMessageAlertModifier(message: message))
  }
}

private struct GUIMessageAlertModifier: ViewModifier {
  @Binding var message: GUIMessage?

  func body(content: Content) -> some View {
    content.alert(
      message?.title ?? "",
      isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } }),
      presenting: message
    ) { message in
      if message.kind == .question {
        // QMessageBox::Yes / No are translated by Qt itself (qtbase_ja), not by Mozc's .qtts files.
        Button(GUILanguage.current == .japanese ? "はい" : "Yes") { message.onYes?() }
        Button(GUILanguage.current == .japanese ? "いいえ" : "No", role: .cancel) {}
      } else {
        Button("OK") {}
      }
    } message: { message in
      Text(verbatim: message.text)
    }
  }
}
