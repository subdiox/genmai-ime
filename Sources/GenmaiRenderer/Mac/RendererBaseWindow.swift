// Port of mozc/src/renderer/mac/RendererBaseWindow.{h,mm} (3.35.6354).
//
// The borderless, non-activating NSPanel that hosts a SwiftUI view (CandidateView / InfolistView).

import AppKit
import GenmaiProtocol
import SwiftUI

/// NSHostingView that accepts the first click: the panel never becomes key, so without this the first
/// click on a candidate would only activate the window.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
public class RendererBaseWindow {
  public private(set) var window: NSPanel?
  private var windowLevel: NSWindow.Level = .popUpMenu

  public init() {}

  /// Creates the content view; overridden by CandidateWindow / InfolistWindow (-ResetView).
  func makeContentView() -> NSView {
    NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
  }

  /// The window background (NSColor.whiteColor in the C++; the style's background with dark styles).
  var backgroundColor: NSColor { .white }

  /// The content view draws its own (rounded, translucent) background: the panel is clear and its shadow follows
  /// the content.
  var isTransparent: Bool { false }

  func initWindow() {
    if window != nil {
      return
    }
    let styleMask: NSWindow.StyleMask = [.utilityWindow, .docModalWindow, .nonactivatingPanel]
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: styleMask,
      backing: .buffered, defer: true)
    panel.contentView = makeContentView()
    panel.displaysWhenScreenProfileChanges = true
    panel.isFloatingPanel = true
    panel.worksWhenModal = true
    if isTransparent {
      panel.backgroundColor = .clear
      panel.isOpaque = false
      panel.hasShadow = true
    } else {
      panel.backgroundColor = backgroundColor
    }
    panel.isReleasedWhenClosed = false
    panel.level = windowLevel
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.orderOut(nil)
    window = panel
  }

  public func getWindowSize() -> Size {
    guard let window else { return Size(0, 0) }
    let rect = window.frame
    return Size(Int(rect.size.width), Int(rect.size.height))
  }

  public func hide() {
    window?.orderOut(nil)
  }

  public func show() {
    if window == nil {
      initWindow()
    }
    window?.orderFront(nil)
    if isTransparent {
      window?.invalidateShadow()
    }
  }

  public var isVisible: Bool { window?.isVisible ?? false }

  public func moveWindow(_ point: NSPoint) {
    guard let window else { return }
    var rect = window.frame
    rect.origin = point
    window.setFrame(rect, display: false)
  }

  public func resizeWindow(_ width: Int, _ height: Int) {
    guard let window else { return }
    var rect = window.frame
    rect.size = NSSize(width: width, height: height)
    window.setFrame(rect, display: false)
    if isTransparent {
      window.invalidateShadow()
    }
  }

  /// Sets the position and the size at once (no intermediate frame on screen).
  func setFrame(_ rect: NSRect) {
    guard let window else { return }
    if window.frame != rect {
      window.setFrame(rect, display: false)
      if isTransparent {
        window.invalidateShadow()
      }
    }
  }

  public func setWindowLevel(_ level: NSWindow.Level) {
    if windowLevel != level {
      windowLevel = level
      window?.level = level
    }
  }

  func updateBackgroundColor() {
    if !isTransparent {
      window?.backgroundColor = backgroundColor
    }
  }
}
