// Not in Mozc: CandidatePlacement keeps the candidate window on one side of the preedit while typing.

import Testing

@testable import GenmaiRenderer

@Suite struct CandidatePlacementTests {
  let display = Rect(0, 0, 200, 100)
  let preedit = Rect(10, 70, 50, 10)

  func genmaiRect(_ size: Size) -> Rect {
    WindowUtil.getWindowRectForMainWindowFromTargetPointAndPreedit(
      Point(preedit.left, preedit.bottom), preedit, size, Point(0, 0), display, false)
  }

  @Test func staysAboveWhenTheWindowShrinks() {
    // Too tall to fit below: Mozc puts it above.
    let tall = CandidatePlacement.keepSide(
      genmaiRect(Size(40, 30)), preeditRect: preedit, displayRect: display, previous: nil)
    #expect(tall.placement.above)
    #expect(tall.rect.bottom <= preedit.top)
    // One row less fits below, but the window stays above.
    let short = genmaiRect(Size(40, 15))
    #expect(short.top >= preedit.bottom)
    let kept = CandidatePlacement.keepSide(short, preeditRect: preedit, displayRect: display, previous: tall.placement)
    #expect(kept.placement.above)
    #expect(kept.rect.top == preedit.top - 15)
    #expect(kept.rect.left == short.left)
  }

  @Test func newCompositionUsesGenmaisPlacement() {
    let above = CandidatePlacement(anchor: preedit.origin, above: true)
    let other = Rect(80, 70, 50, 10)
    let rect = WindowUtil.getWindowRectForMainWindowFromTargetPointAndPreedit(
      Point(other.left, other.bottom), other, Size(40, 15), Point(0, 0), display, false)
    let placed = CandidatePlacement.keepSide(rect, preeditRect: other, displayRect: display, previous: above)
    #expect(!placed.placement.above)
    #expect(placed.rect == rect)
  }

  @Test func goesBelowWhenItDoesNotFitAbove() {
    let high = Rect(10, 10, 50, 10)
    let previous = CandidatePlacement(anchor: high.origin, above: true)
    let rect = WindowUtil.getWindowRectForMainWindowFromTargetPointAndPreedit(
      Point(high.left, high.bottom), high, Size(40, 30), Point(0, 0), display, false)
    let placed = CandidatePlacement.keepSide(rect, preeditRect: high, displayRect: display, previous: previous)
    #expect(!placed.placement.above)
    #expect(placed.rect == rect)
  }
}
