// Port of mozc/src/renderer/window_util.{h,cc} (3.35.6354).

public enum WindowUtil {
  /// Returns the appropriate candidate window position in the screen
  /// coordinate.  `zeroPointOffset` is the point in the candidate
  /// window which should be aligned to the preedit.
  /// `workingArea` is the available area in the current monitor.  If
  /// caller fails to obtain `workingArea`, set its width or height as
  /// 0.  Then it doesn't care the monitor.
  public static func getWindowRectForMainWindowFromPreeditRect(
    _ preeditRect: Rect, _ windowSize: Size, _ zeroPointOffset: Point, _ workingArea: Rect
  ) -> Rect {
    let preeditBottomLeft = Point(preeditRect.left, preeditRect.bottom)
    return getWindowRectForMainWindowFromPreeditRectHorizontal(
      preeditBottomLeft, preeditRect, windowSize, zeroPointOffset, workingArea)
  }

  /// Returns the appropriate candidate window position in the screen
  /// coordinate.  `zeroPointOffset` is the point in the candidate
  /// window which should be aligned to the target point.
  public static func getWindowRectForMainWindowFromTargetPoint(
    _ targetPoint: Point, _ windowSize: Size, _ zeroPointOffset: Point, _ workingArea: Rect
  ) -> Rect {
    var windowRect = Rect(targetPoint, windowSize)
    windowRect.origin.x -= zeroPointOffset.x
    windowRect.origin.y -= zeroPointOffset.y

    // If monitor_rect has erroneous value, it returns window_rect.
    if workingArea.height == 0 || workingArea.width == 0 {
      return windowRect
    }

    if workingArea.bottom < windowRect.bottom {
      windowRect.origin.y -= (windowRect.bottom - workingArea.bottom)
    }

    if windowRect.top < workingArea.top {
      windowRect.origin.y += (workingArea.top - windowRect.top)
    }

    if workingArea.right < windowRect.right {
      windowRect.origin.x -= (windowRect.right - workingArea.right)
    }

    if windowRect.left < workingArea.left {
      windowRect.origin.x += (workingArea.left - windowRect.left)
    }

    return windowRect
  }

  /// Returns the appropriate candidate window position in the screen
  /// coordinate.  `zeroPointOffset` is the point in the candidate
  /// window which should be aligned to the preedit.
  public static func getWindowRectForMainWindowFromTargetPointAndPreedit(
    _ targetPoint: Point, _ preeditRect: Rect, _ windowSize: Size, _ zeroPointOffset: Point,
    _ workingArea: Rect, _ vertical: Bool
  ) -> Rect {
    if vertical {
      return getWindowRectForMainWindowFromPreeditRectVertical(
        targetPoint, preeditRect, windowSize, zeroPointOffset, workingArea)
    }
    return getWindowRectForMainWindowFromPreeditRectHorizontal(
      targetPoint, preeditRect, windowSize, zeroPointOffset, workingArea)
  }

  /// Returns the appropriate cascading window position in the screen
  /// coordinate.  `zeroPointOffset` is the point in the cascading
  /// window which should be aligned to the selected row in the
  /// candidate window.
  public static func getWindowRectForCascadingWindow(
    _ selectedRow: Rect, _ windowSize: Size, _ zeroPointOffset: Point, _ workingArea: Rect
  ) -> Rect {
    let rowTopRight = Point(selectedRow.right, selectedRow.top)

    var windowRect = Rect(rowTopRight, windowSize)
    windowRect.origin.x -= zeroPointOffset.x
    windowRect.origin.y -= zeroPointOffset.y

    if workingArea.height == 0 || workingArea.width == 0 {
      return windowRect
    }

    // If the working area right to the specified candidate window does not have
    // enough horizontal space to display the cascading window,
    // put the cascading window left to the candidate window.
    if workingArea.right < windowRect.right {
      windowRect.origin.x -= (windowRect.width + selectedRow.width)
      // We add zero_point_offset.x twice to keep the same distance
      // left of the selected_row.
      windowRect.origin.x += zeroPointOffset.x * 2
    }

    if workingArea.bottom < windowRect.bottom {
      windowRect.origin.y -= (windowRect.bottom - workingArea.bottom)
    }

    if windowRect.top < workingArea.top {
      windowRect.origin.y += (workingArea.top - windowRect.top)
    }

    if windowRect.left < workingArea.left {
      windowRect.origin.x += (workingArea.left - windowRect.left)
    }

    return windowRect
  }

  /// Returns the appropriate infolist window position in the screen
  /// coordinate.  `windowSize` is the size of the infolist window.
  /// `candidateRect` is the rect of the candidate window.
  public static func getWindowRectForInfolistWindow(
    _ windowSize: Size, _ candidateRect: Rect, _ workingArea: Rect
  ) -> Rect {
    var infolistPos = Point()

    if workingArea.height == 0 || workingArea.width == 0 {
      infolistPos.x = candidateRect.left + candidateRect.width
      infolistPos.y = candidateRect.top
      return Rect(infolistPos, windowSize)
    }
    if candidateRect.left + candidateRect.width + windowSize.width > workingArea.right {
      infolistPos.x = candidateRect.left - windowSize.width
    } else {
      infolistPos.x = candidateRect.left + candidateRect.width
    }
    if candidateRect.top + windowSize.height > workingArea.bottom {
      infolistPos.y = workingArea.bottom - windowSize.height
    } else {
      infolistPos.y = candidateRect.top
    }
    return Rect(infolistPos, windowSize)
  }

  // MARK: - Private

  private static func getWindowRectForMainWindowFromPreeditRectHorizontal(
    _ targetPoint: Point, _ preeditRect: Rect, _ windowSize: Size, _ zeroPointOffset: Point,
    _ workingArea: Rect
  ) -> Rect {
    var windowRect = Rect(targetPoint, windowSize)
    windowRect.origin.x -= zeroPointOffset.x
    windowRect.origin.y -= zeroPointOffset.y

    // If monitor_rect has erroneous value, it returns window_rect.
    if workingArea.height == 0 || workingArea.width == 0 {
      return windowRect
    }

    // If the working area below the preedit does not have enough vertical space
    // to display the candidate window, put the candidate window above
    // the preedit.
    if workingArea.bottom < windowRect.bottom {
      windowRect.origin.y -= (windowRect.height + preeditRect.height)
      // We add zero_point_offset.y twice to keep the same distance
      // above the preedit_rect.
      windowRect.origin.y += zeroPointOffset.y * 2
    }

    if workingArea.bottom < windowRect.bottom {
      windowRect.origin.y -= (windowRect.bottom - workingArea.bottom)
    }

    if windowRect.top < workingArea.top {
      windowRect.origin.y += (workingArea.top - windowRect.top)
    }

    if workingArea.right < windowRect.right {
      windowRect.origin.x -= (windowRect.right - workingArea.right)
    }

    if windowRect.left < workingArea.left {
      windowRect.origin.x += (workingArea.left - windowRect.left)
    }

    return windowRect
  }

  private static func getWindowRectForMainWindowFromPreeditRectVertical(
    _ targetPoint: Point, _ preeditRect: Rect, _ windowSize: Size, _ zeroPointOffset: Point,
    _ workingArea: Rect
  ) -> Rect {
    var windowRect = Rect(targetPoint, windowSize)

    // Currently |zero_point_offset| is ignored because the candidate renderer
    // has not supported vertical writing.

    // Since |target_point| is pointing the upper-left of the preedit, move the
    // candidate window to the right side of the preedit.
    windowRect.origin.x += preeditRect.width

    // If monitor_rect has erroneous value, it returns window_rect.
    if workingArea.height == 0 || workingArea.width == 0 {
      return windowRect
    }

    if workingArea.right < windowRect.right {
      windowRect.origin.x -= (windowRect.width + preeditRect.width)
    }

    if workingArea.right < windowRect.right {
      windowRect.origin.x -= (windowRect.right - workingArea.right)
    }

    if windowRect.left < workingArea.left {
      windowRect.origin.x += (workingArea.left - windowRect.left)
    }

    if workingArea.bottom < windowRect.bottom {
      windowRect.origin.y -= (windowRect.bottom - workingArea.bottom)
    }

    if windowRect.top < workingArea.top {
      windowRect.origin.y += (workingArea.top - windowRect.top)
    }

    return windowRect
  }
}
