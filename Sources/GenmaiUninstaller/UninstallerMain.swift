// Port of mozc/src/mac/Uninstaller/Uninstaller_main.mm (3.35.6354).
//
// The C++ runs InitGenmai and loads Dialogs.xib with a
// DialogsController owner. The port is a SwiftUI app with one window showing DialogsView; the app quits when
// the window is closed (like Cancel). The bundle (UninstallGenmai.app) is assembled by
// Tools/make_uninstaller_bundle.sh and installed in /Applications/Genmai by Tools/make_installer_pkg.sh.

import AppKit
import SwiftUI

final class UninstallerAppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct UninstallerApp: App {
  @NSApplicationDelegateAdaptor(UninstallerAppDelegate.self) private var appDelegate
  @State private var controller = DialogsController(
    uninstaller: Uninstaller(layout: .installed, runner: AppleScriptPrivilegedCommandRunner()))

  var body: some Scene {
    Window(UninstallerStrings.confirm(.current).title, id: "uninstaller") {
      DialogsView(controller: controller)
    }
    .windowResizability(.contentSize)
    .defaultPosition(.center)
  }
}
