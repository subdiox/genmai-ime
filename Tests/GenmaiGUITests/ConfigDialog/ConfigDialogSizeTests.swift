// The config dialog keeps its size when the tab changes (GenmaiTool's window follows the preferred content size).

import AppKit
import SwiftUI
import Testing

@testable import GenmaiGUI

@MainActor
@Suite struct ConfigDialogSizeTests {
  static func tabView(in view: NSView) -> NSTabView? {
    if let t = view as? NSTabView { return t }
    for v in view.subviews {
      if let t = tabView(in: v) { return t }
    }
    return nil
  }

  @Test func sizeDoesNotDependOnTheSelectedTab() throws {
    let hosting = NSHostingController(rootView: ConfigDialogView(model: ConfigDialogModel(client: ConfigDialogMockClient())))
    hosting.sizingOptions = [.preferredContentSize]
    let window = NSWindow(contentViewController: hosting)
    defer { window.close() }
    window.layoutIfNeeded()
    let tabs = try #require(Self.tabView(in: hosting.view))
    #expect(tabs.numberOfTabViewItems == 7)
    var sizes: [CGSize] = []
    for i in 0..<tabs.numberOfTabViewItems {
      tabs.selectTabViewItem(at: i)
      window.layoutIfNeeded()
      sizes.append(hosting.preferredContentSize)
    }
    #expect(Set(sizes.map { "\($0)" }) == ["\(ConfigDialogView.idealSize)"], "\(sizes)")
  }
}
