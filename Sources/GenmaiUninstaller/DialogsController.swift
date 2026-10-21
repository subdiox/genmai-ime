// Port of mozc/src/mac/Uninstaller/DialogsController.{h,mm} (3.35.6354).
//
// The C++ owns four NSWindows from Dialogs.xib and shows the result dialogs with -[NSApp runModalForWindow:].
// The port keeps one window (DialogsView) whose content is the current dialog; the report* methods suspend
// until the user presses a button, which replaces the nested modal run loop (stopModalWithCode:).

import AppKit
import Observation

@MainActor
@Observable
final class DialogsController: UninstallerDialogs {
  /// The dialog on screen. The four xib windows are mutually exclusive, so they are one enum.
  enum Dialog: Equatable {
    case confirm
    /// After OK in the confirmation dialog (the C++ hides confirmDialog_ while the password prompt and the
    /// deletion run); the confirmation is kept on screen with its buttons disabled.
    case uninstalling
    case authError
    case uninstallSucceeded
    case uninstallError
  }

  /// ModalResult.
  enum ModalResult {
    case ok
    case cancel
  }

  private(set) var dialog: Dialog = .confirm
  let language: UninstallerLanguage
  private let uninstaller: Uninstaller
  private let terminate: @MainActor () -> Void
  @ObservationIgnored private var modalContinuation: CheckedContinuation<ModalResult, Never>?

  init(
    uninstaller: Uninstaller, language: UninstallerLanguage = .current,
    terminate: @escaping @MainActor () -> Void = { NSApplication.shared.terminate(nil) }
  ) {
    self.uninstaller = uninstaller
    self.language = language
    self.terminate = terminate
  }

  var strings: UninstallerDialogStrings {
    switch dialog {
    case .confirm, .uninstalling: UninstallerStrings.confirm(language)
    case .authError: UninstallerStrings.authError(language)
    case .uninstallSucceeded: UninstallerStrings.uninstallSucceeded(language)
    case .uninstallError: UninstallerStrings.uninstallError(language)
    }
  }

  /// True while a button press would have no effect (the deletion is running).
  var isBusy: Bool { dialog == .uninstalling }

  /// waitForModalWindow: — returns result != DIALOG_CANCEL.
  private func waitForModalWindow(_ dialog: Dialog) async -> Bool {
    self.dialog = dialog
    let result = await withCheckedContinuation { modalContinuation = $0 }
    self.dialog = .uninstalling
    return result != .cancel
  }

  func reportAuthError() async -> Bool { await waitForModalWindow(.authError) }
  func reportUninstallSuccess() async -> Bool { await waitForModalWindow(.uninstallSucceeded) }
  func reportUninstallError() async -> Bool { await waitForModalWindow(.uninstallError) }

  /// cancel: (the confirmation dialog's Cancel button).
  func cancel() {
    terminate()
  }

  /// runUninstall: (the confirmation dialog's OK button).
  func runUninstall() async {
    guard dialog == .confirm else {
      return
    }
    dialog = .uninstalling
    // Let the window redraw with disabled buttons before the password prompt blocks the main thread.
    await Task.yield()
    await uninstaller.doUninstall(self)
    terminate()
  }

  /// dialogOK: — OK / "Restart now".
  func dialogOK() { stopModal(.ok) }

  /// dialogCancel: — "Later".
  func dialogCancel() { stopModal(.cancel) }

  private func stopModal(_ result: ModalResult) {
    guard let continuation = modalContinuation else {
      return
    }
    modalContinuation = nil
    continuation.resume(returning: result)
  }
}
