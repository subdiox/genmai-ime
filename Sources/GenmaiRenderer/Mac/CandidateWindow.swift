// Port of mozc/src/renderer/mac/CandidateWindow.{h,mm} (3.35.6354). The panel is transparent: CandidateView
// draws its own rounded glass background and the window server shadow follows it.

import AppKit
import GenmaiProtocol
import GenmaiClient
import SwiftUI

@MainActor
public final class CandidateWindow: RendererBaseWindow {
  public let model = CandidateViewModel()

  override func makeContentView() -> NSView {
    FirstMouseHostingView(rootView: CandidateView(model: model))
  }

  public func setSendCommandInterface(_ sendCommandInterface: (any SendCommandInterface)?) {
    model.commandSender = sendCommandInterface
  }

  public func getTableLayout() -> TableLayout { model.tableLayout }

  public func setCandidateWindow(_ candidateWindow: CandidateWindowMessage) {
    if candidateWindow.candidate.isEmpty {
      return
    }
    if window == nil {
      initWindow()
    }
    model.setCandidateWindow(candidateWindow)
    layoutSize = model.updateLayout()
  }

  /// The size of the new content. The frame changes only in `place` / `applyLayoutSize`, in one step with the
  /// position: resizing first (Cocoa keeps the bottom-left corner) and moving afterwards showed the window
  /// growing upwards for a moment on every update.
  private var layoutSize: Size?

  override public func getWindowSize() -> Size {
    layoutSize ?? super.getWindowSize()
  }

  /// Moves the window to `origin` (Cocoa coordinates) with the size of the current content.
  func place(_ origin: NSPoint) {
    let size = getWindowSize()
    setFrame(NSRect(origin: origin, size: NSSize(width: size.width, height: size.height)))
  }

  /// Applies the size of the current content where the window is (no preedit rectangle to align with).
  func applyLayoutSize() {
    let size = getWindowSize()
    resizeWindow(size.width, size.height)
  }
}
