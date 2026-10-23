// The settings window keeps its size whichever pane is shown (the app's window follows the preferred content
// size).

import AppKit
import SwiftUI
import Testing

@testable import GenmaiGUI

@MainActor
@Suite struct ConfigDialogSizeTests {
  @Test func sizeDoesNotDependOnThePane() {
    var sizes: [String] = []
    for pane in SettingsPane.allCases {
      let view = ConfigDialogView(model: ConfigDialogModel(client: ConfigDialogMockClient()), pane: pane)
      let hosting = NSHostingController(rootView: view)
      hosting.sizingOptions = [.preferredContentSize]
      let window = NSWindow(contentViewController: hosting)
      window.layoutIfNeeded()
      sizes.append("\(hosting.preferredContentSize)")
      window.close()
    }
    // The height includes the toolbar on some macOS versions (620 + 32 on macOS 26), so only the width is
    // compared with the ideal size.
    #expect(Set(sizes).count == 1, "\(sizes)")
    #expect(sizes.first?.hasPrefix("(\(ConfigDialogView.idealSize.width), ") == true, "\(sizes)")
  }
}
