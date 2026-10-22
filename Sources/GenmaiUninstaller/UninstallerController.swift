// Port of mozc/src/mac/Uninstaller/DialogsController.{h,mm} and +[Uninstaller doUninstall:] (3.35.6354).
//
// The C++ shows four xib windows in turn (confirmation, then one modal dialog per outcome). The port is one
// window whose content follows `phase`: confirm → removing → succeeded (restart now / later) or failed (try
// again / quit). Unlike the C++, which quits after an error, a failed or cancelled authorization can be retried.

import AppKit
import Observation

@MainActor
@Observable
final class UninstallerController {
  enum Failure: Equatable {
    /// GetPrevilegeRights failed: the password prompt was cancelled or the password was wrong.
    case authorization
    /// /bin/rm failed (the C++'s uninstallErrorDialog_).
    case removal
  }

  enum Phase: Equatable {
    case confirm
    /// The password prompt and the deletion (the main thread is blocked by NSAppleScript meanwhile).
    case removing
    case succeeded
    case failed(Failure)
  }

  private(set) var phase: Phase = .confirm
  let strings: UninstallerStrings
  /// What will be removed, for the confirmation (the deletion re-reads the layout).
  let items: [RemoveItem]
  @ObservationIgnored let icon: NSImage
  private let uninstaller: Uninstaller
  private let terminate: @MainActor () -> Void

  init(
    uninstaller: Uninstaller, language: UninstallerLanguage = .current,
    icon: NSImage = NSApplication.shared.applicationIconImage,
    terminate: @escaping @MainActor () -> Void = { NSApplication.shared.terminate(nil) }
  ) {
    self.uninstaller = uninstaller
    self.strings = UninstallerStrings(language)
    self.items = uninstaller.layout.removeItems()
    self.icon = icon
    self.terminate = terminate
  }

  var isBusy: Bool { phase == .removing }

  /// cancel: / Quit / Later.
  func close() {
    terminate()
  }

  /// runUninstall: (the confirmation's button) and Try Again.
  func uninstall() async {
    switch phase {
    case .confirm, .failed:
      break
    case .removing, .succeeded:
      return
    }
    phase = .removing
    // Let the window draw the progress before the password prompt blocks the main thread.
    try? await Task.sleep(for: .milliseconds(100))
    switch uninstaller.deleteFiles() {
    case .success:
      phase = .succeeded
    case .authorizationFailed:
      phase = .failed(.authorization)
    case .failed:
      phase = .failed(.removal)
    }
  }

  /// "Restart now" (RunReboot), then quit.
  func restartNow() {
    guard phase == .succeeded else {
      return
    }
    _ = uninstaller.reboot()
    terminate()
  }
}
