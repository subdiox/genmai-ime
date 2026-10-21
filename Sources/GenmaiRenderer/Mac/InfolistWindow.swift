// Port of mozc/src/renderer/mac/InfolistWindow.{h,mm} (3.35.6354).
//
// NSTimer-based DelayShow / DelayHide are replaced by a cancellable main-actor Task.

import AppKit
import GenmaiProtocol
import SwiftUI

@MainActor
public final class InfolistWindow: RendererBaseWindow {
  public let model: InfolistViewModel
  private var lastTimer: Task<Void, Never>?
  private var visible = false

  public init(style: RendererStyle) {
    model = InfolistViewModel(style: style)
    super.init()
  }

  override func makeContentView() -> NSView {
    FirstMouseHostingView(rootView: InfolistView(model: model))
  }

  override var isTransparent: Bool { true }

  public func setStyle(_ style: RendererStyle) {
    model.setStyle(style)
    updateBackgroundColor()
  }

  public func setCandidateWindow(_ candidateWindow: CandidateWindowMessage) {
    if candidateWindow.candidate.isEmpty {
      return
    }
    if window == nil {
      initWindow()
    }
    model.setCandidateWindow(candidateWindow)
    let size = model.updateLayout()
    resizeWindow(Int(size.width), Int(size.height))
  }

  /// Hides the window after `delay` milliseconds.
  public func delayHide(_ delay: Int) {
    visible = false
    schedule(delay)
  }

  /// Shows the window after `delay` milliseconds.
  public func delayShow(_ delay: Int) {
    visible = true
    schedule(delay)
  }

  private func schedule(_ delay: Int) {
    lastTimer?.cancel()
    lastTimer = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(delay))
      guard !Task.isCancelled else { return }
      self?.onTimer()
    }
  }

  public override func hide() {
    super.hide()
    visible = false
  }

  public override func show() {
    super.show()
    visible = true
  }

  func onTimer() {
    if visible {
      show()
    } else {
      hide()
    }
    lastTimer = nil
  }
}
