// Port of mozc/src/renderer/table_layout_test.cc (3.35.6354).

import Testing

@testable import GenmaiRenderer

private func expectSizeEq(
  _ width: Int, _ height: Int, _ actual: Size, sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(actual.width == width, sourceLocation: sourceLocation)
  #expect(actual.height == height, sourceLocation: sourceLocation)
}

private func expectRectEq(
  _ left: Int, _ top: Int, _ width: Int, _ height: Int, _ actual: Rect,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(actual.origin.x == left, sourceLocation: sourceLocation)
  #expect(actual.origin.y == top, sourceLocation: sourceLocation)
  #expect(actual.width == width, sourceLocation: sourceLocation)
  #expect(actual.height == height, sourceLocation: sourceLocation)
}

@Suite struct TableLayoutTests {
  @Test func allElement() {
    let kWindowBorder = 1
    let kNumberOfRow = 10
    let kHeaderHeight = 9
    let kFooterHeight = 13
    let kVSCrollBarWidth = 11
    let kRowRectPadding = 2

    let layout = TableLayout()
    layout.initialize(numRows: kNumberOfRow, numColumns: kNumberOfColumns)
    layout.setVScrollBar(kVSCrollBarWidth)
    layout.setRowRectPadding(kRowRectPadding)
    layout.setWindowBorder(kWindowBorder)

    let kGap1 = Size(5, 0)

    layout.ensureHeaderSize(Size(0, kHeaderHeight))
    layout.ensureFooterSize(Size(0, kFooterHeight))

    layout.ensureCellSize(ColumnType.gap1.rawValue, kGap1)
    for row in 0..<kNumberOfRow {
      let candidate = Size(row + 1, 10)
      let description = Size(15, 5)
      layout.ensureCellSize(ColumnType.candidate.rawValue, candidate)
      layout.ensureCellSize(ColumnType.description.rawValue, description)
    }

    layout.freezeLayout()

    expectSizeEq(47, 164, layout.getTotalSize())
    expectRectEq(1, 1, 45, 9, layout.getHeaderRect())
    expectRectEq(1, 150, 45, 13, layout.getFooterRect())
    expectRectEq(35, 10, 11, 140, layout.getVScrollBarRect())
    expectRectEq(1, 24, 34, 14, layout.getRowRect(1))
    expectRectEq(8, 10, 10, 140, layout.getColumnRect(ColumnType.candidate.rawValue))
    expectRectEq(3, 26, 0, 10, layout.getCellRect(1, ColumnType.shortcut.rawValue))
    // Although the specified cell with of column 1 is 2, the actual layout
    // width of this cell is 10 because of the width of column 9.
    expectRectEq(8, 26, 10, 10, layout.getCellRect(1, ColumnType.candidate.rawValue))
    expectRectEq(18, 26, 15, 10, layout.getCellRect(1, ColumnType.description.rawValue))
  }

  @Test func allElementWithMinimumFooterWidth() {
    let kWindowBorder = 1
    let kNumberOfRow = 10
    let kHeaderHeight = 9
    let kFooterHeight = 13
    let kFooterWidth = 100
    let kVSCrollBarWidth = 11
    let kRowRectPadding = 2

    let layout = TableLayout()
    layout.initialize(numRows: kNumberOfRow, numColumns: kNumberOfColumns)
    layout.setVScrollBar(kVSCrollBarWidth)
    layout.setRowRectPadding(kRowRectPadding)
    layout.setWindowBorder(kWindowBorder)

    let kGap1 = Size(5, 0)

    layout.ensureHeaderSize(Size(0, kHeaderHeight))
    layout.ensureFooterSize(Size(kFooterWidth, kFooterHeight))

    layout.ensureCellSize(ColumnType.gap1.rawValue, kGap1)
    for row in 0..<kNumberOfRow {
      layout.ensureCellSize(ColumnType.candidate.rawValue, Size(row + 1, 10))
      layout.ensureCellSize(ColumnType.description.rawValue, Size(15, 5))
    }

    layout.freezeLayout()

    // Although the maximum width of cells are 10 + 15 = 25,
    // the expected window width is 102 because of footer width.
    expectSizeEq(102, 164, layout.getTotalSize())
    expectRectEq(1, 1, 100, 9, layout.getHeaderRect())
    expectRectEq(1, 150, 100, 13, layout.getFooterRect())
    expectRectEq(90, 10, 11, 140, layout.getVScrollBarRect())
    expectRectEq(1, 24, 89, 14, layout.getRowRect(1))
    expectRectEq(8, 10, 10, 140, layout.getColumnRect(ColumnType.candidate.rawValue))
    expectRectEq(3, 26, 0, 10, layout.getCellRect(1, ColumnType.shortcut.rawValue))
    expectRectEq(8, 26, 10, 10, layout.getCellRect(1, ColumnType.candidate.rawValue))
    expectRectEq(18, 26, 15, 10, layout.getCellRect(1, ColumnType.description.rawValue))
  }

  @Test func ensureCellsWidth() {
    let layout = TableLayout()
    layout.initialize(numRows: 1, numColumns: 4)
    for i in 0..<4 {
      layout.ensureCellSize(i, Size(10, 10))
    }
    layout.ensureColumnsWidth(1, 2, 100)
    layout.freezeLayout()

    expectSizeEq(120, 10, layout.getTotalSize())
    expectRectEq(0, 0, 10, 10, layout.getColumnRect(0))
    expectRectEq(10, 0, 10, 10, layout.getColumnRect(1))
    expectRectEq(20, 0, 90, 10, layout.getColumnRect(2))
    expectRectEq(110, 0, 10, 10, layout.getColumnRect(3))
  }

  @Test func ensureCellsWidthCallTwice() {
    let layout = TableLayout()
    layout.initialize(numRows: 1, numColumns: 4)
    for i in 0..<4 {
      layout.ensureCellSize(i, Size(10, 10))
    }
    layout.ensureColumnsWidth(1, 2, 100)
    layout.ensureColumnsWidth(0, 1, 100)
    layout.freezeLayout()

    expectSizeEq(120, 10, layout.getTotalSize())
    expectRectEq(0, 0, 10, 10, layout.getColumnRect(0))
    expectRectEq(10, 0, 90, 10, layout.getColumnRect(1))
    expectRectEq(100, 0, 10, 10, layout.getColumnRect(2))
    expectRectEq(110, 0, 10, 10, layout.getColumnRect(3))
  }

  @Test func vScrollIndicatorPositions() {
    let layout = TableLayout()
    // Set the size to 100.
    layout.initialize(numRows: 1, numColumns: 1)
    layout.ensureCellSize(0, Size(1, 100))
    layout.setVScrollBar(10)
    layout.freezeLayout()

    let kCandidatesTotal = 15
    let vscrollBarRect = layout.getVScrollBarRect()
    expectRectEq(1, 0, 10, 100, layout.getVScrollBarRect())

    var indicatorRect = layout.getVScrollIndicatorRect(0, 5, kCandidatesTotal)
    #expect(indicatorRect.left == vscrollBarRect.left)
    #expect(indicatorRect.right == vscrollBarRect.right)
    #expect(indicatorRect.top == 0)
    #expect(indicatorRect.bottom == Int(100.0 * 6 / 15 + 0.5))

    indicatorRect = layout.getVScrollIndicatorRect(5, 10, kCandidatesTotal)
    #expect(indicatorRect.left == vscrollBarRect.left)
    #expect(indicatorRect.right == vscrollBarRect.right)
    #expect(indicatorRect.top == Int(100.0 * 5 / 15 + 0.5))
    #expect(indicatorRect.bottom == Int(100.0 * 11 / 15 + 0.5))

    indicatorRect = layout.getVScrollIndicatorRect(10, 14, kCandidatesTotal)
    #expect(indicatorRect.left == vscrollBarRect.left)
    #expect(indicatorRect.right == vscrollBarRect.right)
    #expect(indicatorRect.top == Int(100.0 * 10 / 15 + 0.5))
    #expect(indicatorRect.bottom == 100)
  }

  @Test func vScrollVerySmallIndicator() {
    let layout = TableLayout()
    layout.initialize(numRows: 1, numColumns: 1)
    layout.ensureCellSize(0, Size(1, 100))
    layout.setVScrollBar(10)
    layout.freezeLayout()

    let kCandidatesTotal = 200
    expectRectEq(1, 0, 10, 100, layout.getVScrollBarRect())
    expectRectEq(1, 0, 10, 1, layout.getVScrollIndicatorRect(0, 1, kCandidatesTotal))
    expectRectEq(1, 99, 10, 1, layout.getVScrollIndicatorRect(199, 199, kCandidatesTotal))
  }

  @Test func layoutFreeze() {
    let layout = TableLayout()
    layout.initialize(numRows: 1, numColumns: 1)
    #expect(!layout.isLayoutFrozen)
    layout.freezeLayout()
    #expect(layout.isLayoutFrozen)
    layout.initialize(numRows: 1, numColumns: 1)
    #expect(!layout.isLayoutFrozen)
  }
}
