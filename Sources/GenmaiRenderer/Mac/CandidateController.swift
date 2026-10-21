// Port of mozc/src/renderer/mac/CandidateController.{h,mm} (3.35.6354).
//
// Differences from the C++:
// - Runs in the IME process (no mozc_renderer process / NSConnection; see RendererInterface.swift).
// - Picks the light or dark RendererStyle (renderer_style.textproto / renderer_style_dark.textproto) from the
//   effective appearance for the infolist window; the C++ mac renderer always uses the light style.
// - The candidate windows have their own design (CandidateView.swift, system colors) instead of the
//   RendererStyle look.

import AppKit
import GenmaiClient
import GenmaiProtocol

private let kHideWindowDelay = 500  // msec
private let kWindowMargin = 10  // pixel

/// In Cocoa's coordinate system the origin point is left-bottom and the Y-axis
/// points up. But in Mozc's coordinate system the Y-axis points down. So we use
/// originPointInCocoaCoord and rectInGenmaiCoord to convert the coordinate system.
func originPointInCocoaCoord(_ rect: Rect) -> NSPoint {
  NSPoint(x: rect.left, y: -rect.bottom)
}

func rectInGenmaiCoord(_ rect: NSRect) -> Rect {
  Rect(
    Int(rect.origin.x), Int(-rect.origin.y - rect.size.height), Int(rect.size.width),
    Int(rect.size.height))
}

/// Find the display including the specified point and if it fails to
/// find it, pick up the nearest display.  Returns the geometry of the
/// found display.
func getNearestDisplayRect(_ rect: Rect, screens: [NSRect]) -> Rect {
  let point = originPointInCocoaCoord(rect)
  var nearestDistance = CGFloat(Float.greatestFiniteMagnitude)
  var resultRect = NSRect.zero
  for screenRect in screens {
    var distance: CGFloat = 0
    if point.x < screenRect.origin.x {
      distance += screenRect.origin.x - point.x
    } else if point.x > screenRect.origin.x + screenRect.size.width {
      distance += point.x - screenRect.origin.x - screenRect.size.width
    }
    if point.y < screenRect.origin.y {
      distance += screenRect.origin.y - point.y
    } else if point.y > screenRect.origin.y + screenRect.size.height {
      distance += point.y - screenRect.origin.y - screenRect.size.height
    }
    if distance < nearestDistance {
      nearestDistance = distance
      resultRect = screenRect
    }
  }
  return rectInGenmaiCoord(resultRect)
}

/// Returns the height of the base screen.
func getBaseScreenHeight(screens: [NSRect]) -> Int {
  var baseFrame = NSRect.zero
  for frame in screens {
    baseFrame = frame
    if frame.origin.x == 0 && frame.origin.y == 0 {
      break
    }
  }
  return Int(baseFrame.size.height)
}

@MainActor
public final class CandidateController: RendererInterface {
  private let candidateWindow: CandidateWindow
  private let cascadingWindow: CandidateWindow
  private let infolistWindow: InfolistWindow
  private var command = RendererCommand()
  private var theme: RendererStyleHandler.ColorTheme
  private let screenFrames: @MainActor () -> [NSRect]
  private let themeProvider: @MainActor () -> RendererStyleHandler.ColorTheme

  public init(
    screenFrames: @escaping @MainActor () -> [NSRect] = { NSScreen.screens.map(\.frame) },
    themeProvider: @escaping @MainActor () -> RendererStyleHandler.ColorTheme =
      CandidateController.systemTheme
  ) {
    self.screenFrames = screenFrames
    self.themeProvider = themeProvider
    theme = themeProvider()
    let style = RendererStyleHandler.getRendererStyle(theme)
    candidateWindow = CandidateWindow()
    cascadingWindow = CandidateWindow()
    infolistWindow = InfolistWindow(style: style)
    candidateWindow.setWindowLevel(.popUpMenu)
    // Cascading window should be over the normal candidate window.
    cascadingWindow.setWindowLevel(NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1))
    // Infolist window should be under the normal candidate window.
    infolistWindow.setWindowLevel(NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1))
  }

  /// Dark when the effective appearance of the app is a dark one.
  public static func systemTheme() -> RendererStyleHandler.ColorTheme {
    let appearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
    return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
  }

  public func activate() -> Bool {
    // Do nothing
    true
  }

  public func isAvailable() -> Bool { true }

  public func setSendCommandInterface(_ sendCommandInterface: (any SendCommandInterface)?) {
    candidateWindow.setSendCommandInterface(sendCommandInterface)
    cascadingWindow.setSendCommandInterface(sendCommandInterface)
  }

  private func updateThemeIfNeeded() {
    let newTheme = themeProvider()
    guard newTheme != theme else { return }
    theme = newTheme
    infolistWindow.setStyle(RendererStyleHandler.getRendererStyle(theme))
  }

  public func execCommand(_ newCommand: RendererCommand) -> Bool {
    if newCommand.type != .update {
      return false
    }
    command = newCommand

    if !command.visible {
      candidateWindow.hide()
      cascadingWindow.hide()
      infolistWindow.hide()
      return true
    }

    updateThemeIfNeeded()
    let output = command.output
    candidateWindow.setCandidateWindow(output.candidateWindow)

    var cascadingVisible = false
    if output.hasCandidateWindow && output.candidateWindow.hasSubCandidateWindow {
      cascadingWindow.setCandidateWindow(output.candidateWindow.subCandidateWindow)
      cascadingVisible = true
    }

    var infolistVisible = false
    if output.hasCandidateWindow && output.candidateWindow.hasUsages
      && !output.candidateWindow.usages.information.isEmpty
    {
      infolistWindow.setCandidateWindow(output.candidateWindow)
      infolistVisible = true
    }

    alignWindows()
    candidateWindow.show()
    if cascadingVisible {
      cascadingWindow.show()
    } else {
      cascadingWindow.hide()
    }

    if infolistVisible && !cascadingVisible {
      let window = output.candidateWindow
      if window.hasFocusedIndex && !window.candidate.isEmpty {
        let focusedRow = Int(window.focusedIndex) - Int(window.candidate[0].index)
        if window.candidate.count >= focusedRow && window.candidate.indices.contains(focusedRow)
          && window.candidate[focusedRow].hasInformationID
        {
          infolistWindow.delayShow(Int(window.usages.delay))
        } else {
          infolistWindow.delayHide(kHideWindowDelay)
        }
      } else {
        infolistWindow.delayHide(kHideWindowDelay)
      }
    } else {
      // Hide infolist window immediately.
      infolistWindow.hide()
    }

    return true
  }

  /// The composition start (preedit rectangle origin) and whether the candidate window went above it.
  private var placement: CandidatePlacement?

  /// Relocate windows to prevent overlaps.
  private func alignWindows() {
    // If candidate window is not visible, we do nothing for aligning.
    if !command.hasPreeditRectangle {
      candidateWindow.applyLayoutSize()
      return
    }
    let screens = screenFrames()
    let preeditRectangle = command.preeditRectangle
    let preeditSize = Size(
      Int(preeditRectangle.right - preeditRectangle.left),
      Int(preeditRectangle.bottom - preeditRectangle.top))
    // The origin point of command_.preedit_rectangle() is the left-top of the
    // base screen which is set in GenmaiImkInputController. So we minus the height of the screen here.
    var preeditRect = Rect(
      Point(Int(preeditRectangle.left), Int(preeditRectangle.top) - getBaseScreenHeight(screens: screens)),
      preeditSize)

    // This is a hacky way to check vertical writing.
    let isVertical = preeditSize.height < preeditSize.width

    // Expand the rect size to make a margin to the candidate window.
    if isVertical {
      // Adjust the margin to the candidate window in the right side.
      preeditRect.deflateRect(0, 0, -kWindowMargin, 0)  // (dx, dy, dw, dh)
    } else {
      // Adjust the margin to the candidate window in the upper side.
      preeditRect.deflateRect(0, -kWindowMargin, 0, 0)  // (dx, dy, dw, dh)
    }

    // Find out the nearest display.
    let displayRect = getNearestDisplayRect(preeditRect, screens: screens)

    // Align candidate window.
    // Initialize the position.  We use (left, bottom) of preedit as
    // the top-left position of the window because we want to show the
    // window just below of the preedit.
    let candidateLayout = candidateWindow.getTableLayout()
    let candidateZeroPoint = Point(candidateLayout.getColumnRect(ColumnType.candidate.rawValue).left, 0)

    let targetPoint = Point(preeditRect.left, preeditRect.bottom)
    var candidateRect = WindowUtil.getWindowRectForMainWindowFromTargetPointAndPreedit(
      targetPoint, preeditRect, candidateWindow.getWindowSize(), candidateZeroPoint, displayRect,
      isVertical)
    if !isVertical {
      let placed = CandidatePlacement.keepSide(
        candidateRect, preeditRect: preeditRect, displayRect: displayRect, previous: placement)
      candidateRect = placed.rect
      placement = placed.placement
    }
    candidateWindow.place(originPointInCocoaCoord(candidateRect))

    // Align infolist window
    let infolistRect = WindowUtil.getWindowRectForInfolistWindow(
      infolistWindow.getWindowSize(), candidateRect, displayRect)
    infolistWindow.moveWindow(originPointInCocoaCoord(infolistRect))

    // If there is no need to show cascading window, we just finish the
    // function here.
    let output = command.output
    if !output.hasCandidateWindow || output.candidateWindow.candidate.isEmpty
      || !output.candidateWindow.hasSubCandidateWindow
    {
      return
    }

    // Fix cascading window position
    // 1. starting position is at the focused row
    let window = output.candidateWindow
    let focusedRow = Int(window.focusedIndex) - Int(window.candidate[0].index)
    guard focusedRow >= 0 && focusedRow < candidateLayout.numberOfRows else { return }
    var focusedRect = candidateLayout.getRowRect(focusedRow)
    // move the focused_rect to the monitor's coordinates
    focusedRect.origin.x += candidateRect.origin.x
    focusedRect.origin.y += candidateRect.origin.y
    // focused_rect doesn't have the width for scroll bar
    focusedRect.size.width += candidateLayout.getVScrollBarRect().width

    let cascadingRect = WindowUtil.getWindowRectForCascadingWindow(
      focusedRect, cascadingWindow.getWindowSize(), Point(0, 0), displayRect)
    cascadingWindow.moveWindow(originPointInCocoaCoord(cascadingRect))
  }
}

/// Not in Mozc: while the same composition continues (same preedit origin), the candidate window stays on the
/// side of the preedit it was put on. Mozc puts it above only when it does not fit below, so near the bottom of
/// the screen a window whose row count changes (suggestions while typing) jumped between above and below.
/// It goes back below only when it would not fit above.
struct CandidatePlacement: Equatable {
  var anchor: Point
  var above: Bool

  /// `rect`: Mozc's placement (Mozc coordinates); `previous`: the placement of the last update.
  static func keepSide(_ rect: Rect, preeditRect: Rect, displayRect: Rect, previous: CandidatePlacement?)
    -> (rect: Rect, placement: CandidatePlacement)
  {
    var rect = rect
    var above = rect.bottom <= preeditRect.top
    if let previous, previous.anchor == preeditRect.origin, previous.above, !above {
      var aboveRect = rect
      aboveRect.origin.y = preeditRect.top - rect.height
      if displayRect.height == 0 || aboveRect.top >= displayRect.top {
        rect = aboveRect
        above = true
      }
    }
    return (rect, CandidatePlacement(anchor: preeditRect.origin, above: above))
  }
}
