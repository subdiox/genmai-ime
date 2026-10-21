// Port of mozc/src/renderer/window_util_test.cc (3.35.6354).

import Testing

@testable import GenmaiRenderer

@Suite struct WindowUtilTests {
  let workingArea = Rect(0, 0, 200, 100)
  let windowSize = Size(10, 20)
  let zeroPointOffset = Point(1, -2)

  func verifyMainWindowWithPreeditRect(
    _ preeditLeft: Int, _ preeditTop: Int, _ preeditWidth: Int, _ preeditHeight: Int,
    _ expectedLeft: Int, _ expectedTop: Int, _ message: Comment,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let preeditRect = Rect(preeditLeft, preeditTop, preeditWidth, preeditHeight)
    let result = WindowUtil.getWindowRectForMainWindowFromPreeditRect(
      preeditRect, windowSize, zeroPointOffset, workingArea)
    #expect(result.left == expectedLeft, message, sourceLocation: sourceLocation)
    #expect(result.top == expectedTop, message, sourceLocation: sourceLocation)
  }

  func verifyMainWindowWithTargetPoint(
    _ x: Int, _ y: Int, _ expectedLeft: Int, _ expectedTop: Int, _ message: Comment,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let result = WindowUtil.getWindowRectForMainWindowFromTargetPoint(
      Point(x, y), windowSize, zeroPointOffset, workingArea)
    #expect(result.left == expectedLeft, message, sourceLocation: sourceLocation)
    #expect(result.top == expectedTop, message, sourceLocation: sourceLocation)
  }

  func verifyMainWindowWithTargetPointAndPreedit(
    vertical: Bool, _ x: Int, _ y: Int, _ preeditLeft: Int, _ preeditTop: Int, _ preeditWidth: Int,
    _ preeditHeight: Int, _ expectedLeft: Int, _ expectedTop: Int, _ message: Comment,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let preeditRect = Rect(preeditLeft, preeditTop, preeditWidth, preeditHeight)
    let result = WindowUtil.getWindowRectForMainWindowFromTargetPointAndPreedit(
      Point(x, y), preeditRect, windowSize, zeroPointOffset, workingArea, vertical)
    #expect(result.left == expectedLeft, message, sourceLocation: sourceLocation)
    #expect(result.top == expectedTop, message, sourceLocation: sourceLocation)
  }

  func verifyCascadingWindow(
    _ rowLeft: Int, _ rowTop: Int, _ rowWidth: Int, _ rowHeight: Int, _ expectedLeft: Int,
    _ expectedTop: Int, _ message: Comment, sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let result = WindowUtil.getWindowRectForCascadingWindow(
      Rect(rowLeft, rowTop, rowWidth, rowHeight), windowSize, zeroPointOffset, workingArea)
    #expect(result.left == expectedLeft, message, sourceLocation: sourceLocation)
    #expect(result.top == expectedTop, message, sourceLocation: sourceLocation)
  }

  func verifyInfolistWindow(
    _ infolistWidth: Int, _ infolistHeight: Int, _ candidateLeft: Int, _ candidateTop: Int,
    _ candidateWidth: Int, _ candidateHeight: Int, _ expectedLeft: Int, _ expectedTop: Int,
    _ message: Comment, sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let result = WindowUtil.getWindowRectForInfolistWindow(
      Size(infolistWidth, infolistHeight),
      Rect(candidateLeft, candidateTop, candidateWidth, candidateHeight), workingArea)
    #expect(result.left == expectedLeft, message, sourceLocation: sourceLocation)
    #expect(result.top == expectedTop, message, sourceLocation: sourceLocation)
  }

  @Test func mainWindow() {
    verifyMainWindowWithPreeditRect(50, 50, 20, 5, 49, 57, "Preedit is in the middle of the window")
    verifyMainWindowWithPreeditRect(198, 50, 20, 5, 190, 57, "On the right edge")
    verifyMainWindowWithPreeditRect(-5, 50, 20, 5, 0, 57, "On the left edge")
    // If the candidate window across the bottom edge, it appears above
    // the preedit.
    verifyMainWindowWithPreeditRect(50, 92, 20, 5, 49, 70, "On the bottom edge")
    verifyMainWindowWithPreeditRect(50, 110, 20, 5, 49, 80, "Under the bottom edge")
    verifyMainWindowWithPreeditRect(50, -10, 20, 5, 49, 0, "On the top edge")

    verifyMainWindowWithTargetPoint(50, 55, 49, 57, "Preedit is in the middle of the window")
    verifyMainWindowWithTargetPoint(198, 55, 190, 57, "On the right edge")
    verifyMainWindowWithTargetPoint(-5, 55, 0, 57, "On the left edge")
    verifyMainWindowWithTargetPoint(50, 97, 49, 80, "On the bottom edge")
    verifyMainWindowWithTargetPoint(50, 115, 49, 80, "Under the bottom edge")
    verifyMainWindowWithTargetPoint(50, -5, 49, 0, "On the top edge")

    verifyMainWindowWithTargetPointAndPreedit(
      vertical: false, 50, 55, 50, 50, 20, 5, 49, 57, "Preedit is in the middle of the window")
    verifyMainWindowWithTargetPointAndPreedit(
      vertical: false, 198, 55, 198, 50, 20, 5, 190, 57, "On the right edge")
    verifyMainWindowWithTargetPointAndPreedit(
      vertical: false, 50, -5, 50, -10, 20, 5, 49, 0, "On the top edge")
    verifyMainWindowWithTargetPointAndPreedit(
      vertical: false, 50, 55, 0, 50, 100, 5, 49, 57, "Preedit width is the same to client area")
    // If the candidate window across the bottom edge, it appears above
    // the preedit.
    verifyMainWindowWithTargetPointAndPreedit(
      vertical: false, 50, 97, 50, 92, 20, 5, 49, 70, "On the bottom edge")
    verifyMainWindowWithTargetPointAndPreedit(
      vertical: false, 50, 115, 50, 110, 20, 5, 49, 80, "Under the bottom edge")
    verifyMainWindowWithTargetPointAndPreedit(
      vertical: false, 50, -5, 50, -10, 20, 5, 49, 0, "On the top edge")

    verifyMainWindowWithTargetPointAndPreedit(
      vertical: true, 50, 55, 50, 50, 20, 5, 70, 55, "Preedit is in the middle of the window")
    verifyMainWindowWithTargetPointAndPreedit(
      vertical: true, 50, 198, 50, 198, 5, 20, 55, 80, "On the bottom edge")
    verifyMainWindowWithTargetPointAndPreedit(
      vertical: true, -50, 50, -50, 50, 5, 20, 0, 50, "On the left edge")
    verifyMainWindowWithTargetPointAndPreedit(
      vertical: true, 50, 55, 50, 0, 20, 100, 70, 55, "Preedit height is the same to client area")
    // If the candidate window across the right edge, it appears in the left of
    // the preedit.
    verifyMainWindowWithTargetPointAndPreedit(
      vertical: true, 192, 50, 192, 50, 5, 20, 182, 50, "On the right edge")
    verifyMainWindowWithTargetPointAndPreedit(
      vertical: true, 215, 50, 210, 50, 5, 20, 190, 50, "Under the right edge")
    verifyMainWindowWithTargetPointAndPreedit(
      vertical: true, -5, 50, -10, 50, 5, 20, 0, 50, "On the left edge")
  }

  @Test func cascadingWindow() {
    verifyCascadingWindow(50, 50, 20, 5, 69, 52, "Selected row is in the middle of the window")
    // If the cascading window across the right edge, it appears the
    // left side of the main window.
    verifyCascadingWindow(178, 50, 20, 5, 169, 52, "On the right edge")
    verifyCascadingWindow(-30, 50, 20, 5, 0, 52, "On the left edge")
    verifyCascadingWindow(50, 92, 20, 5, 69, 80, "On the bottom edge")
    verifyCascadingWindow(50, -20, 20, 5, 69, 0, "On the top edge")
  }

  @Test func infolistWindow() {
    verifyInfolistWindow(10, 20, 20, 30, 11, 12, 31, 30, "Right of the candidate window")
    verifyInfolistWindow(10, 10, 160, 30, 40, 12, 150, 30, "Left of the candidate window")
    verifyInfolistWindow(10, 20, 20, 85, 11, 12, 31, 80, "On the bottom edge")
  }

  @Test func monitorErrors() {
    // Error! monitor doesn't have width nor height.
    let workingArea = Rect(0, 0, 0, 0)
    let windowSize = Size(10, 20)
    let zeroPointOffset = Point(1, -2)
    let preeditRect = Rect(50, 50, 20, 5)
    let targetPoint = Point(preeditRect.left, preeditRect.bottom)

    var result = WindowUtil.getWindowRectForMainWindowFromPreeditRect(
      preeditRect, windowSize, zeroPointOffset, workingArea)
    // It doesn't apply edge across processing.
    #expect(result.left == 49)
    #expect(result.top == 57)

    result = WindowUtil.getWindowRectForMainWindowFromTargetPoint(
      targetPoint, windowSize, zeroPointOffset, workingArea)
    #expect(result.left == 49)
    #expect(result.top == 57)

    // Same as cascading window.
    result = WindowUtil.getWindowRectForCascadingWindow(
      preeditRect, windowSize, zeroPointOffset, workingArea)
    #expect(result.left == 69)
    #expect(result.top == 52)

    // Same as infolist window.
    let candidateRect = Rect(50, 32, 20, 5)
    result = WindowUtil.getWindowRectForInfolistWindow(windowSize, candidateRect, workingArea)
    #expect(result.left == 70)
    #expect(result.top == 32)
  }
}
