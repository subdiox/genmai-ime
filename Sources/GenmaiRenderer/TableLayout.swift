// Port of mozc/src/renderer/table_layout.{h,cc} (3.35.6354).

import GenmaiBase

/// The minimum height of the indicator in the VScrollBar.
private let kMinimumIndicatorHeight = 1

public final class TableLayout: TableLayoutInterface {
  private var columnWidthList: [Int] = []
  private var totalSize = Size()  // this value is valid only when the layout is frozen.
  private var minimumFooterSize = Size(0, 0)
  private var minimumHeaderSize = Size(0, 0)

  private var ensureWidthFromColumn = 0
  private var ensureWidthToColumn = 0
  private var ensureWidth = 0

  public private(set) var numberOfRows = 1
  public private(set) var numberOfColumns = 1
  private var windowBorderPixels = 1
  private var rowRectPaddingPixels = 0
  private var rowHeight = 1  // this value includes (row_rect_padding * 2)
  private var vscrollWidthPixels = 0

  private var layoutFrozen = false

  public init() {}

  // ------------------------------------------------------------------------
  // Initializations
  // ------------------------------------------------------------------------

  /// Reset layout freeze and initialize the number of rows and columns.
  public func initialize(numRows: Int, numColumns: Int) {
    numberOfRows = numRows
    numberOfColumns = numColumns

    layoutFrozen = false
    windowBorderPixels = 0
    minimumFooterSize = Size(0, 0)
    minimumHeaderSize = Size(0, 0)
    rowRectPaddingPixels = 0
    rowHeight = 0
    vscrollWidthPixels = 0

    columnWidthList = Array(repeating: 0, count: numColumns)

    totalSize = Size()
  }

  // ------------------------------------------------------------------------
  // Add layout element
  // ------------------------------------------------------------------------

  public func setVScrollBar(_ widthInPixels: Int) {
    if layoutFrozen {
      GenmaiLog.error("Layout already frozen")
      return
    }
    vscrollWidthPixels = widthInPixels
  }

  public func setWindowBorder(_ widthInPixels: Int) {
    if layoutFrozen {
      GenmaiLog.error("Layout already frozen")
      return
    }
    windowBorderPixels = widthInPixels
  }

  public func setRowRectPadding(_ widthPixels: Int) {
    if layoutFrozen {
      GenmaiLog.error("Layout already frozen")
      return
    }
    rowRectPaddingPixels = widthPixels
  }

  /// Ensure the cell size is same to or larger than the specified size.
  /// - size.width affects cells within the specified column.
  /// - size.height affects all cells.
  /// You should not call this function when the layout is frozen.
  public func ensureCellSize(_ column: Int, _ size: Size) {
    if layoutFrozen {
      GenmaiLog.error("Layout already frozen")
      return
    }
    assert(0 <= column && column < columnWidthList.count)
    columnWidthList[column] = max(columnWidthList[column], size.width)
    rowHeight = max(rowHeight, size.height + rowRectPaddingPixels * 2)
  }

  /// Ensure the total width from "from_column" to "to_width" is at
  /// least "width" or larger.  If total width is smaller than the
  /// "width", the last column (== "to_column") will extend.  If this
  /// method is called twice, parameters specified by the second call
  /// will be used.  Note that "to_column" should be bigger than
  /// "from_column".  Otherwise, the call will be ignored.
  public func ensureColumnsWidth(_ fromColumn: Int, _ toColumn: Int, _ width: Int) {
    ensureWidthFromColumn = fromColumn
    ensureWidthToColumn = toColumn
    ensureWidth = width
  }

  /// Ensure the size of header/footer is same to or larger than the
  /// specified size.
  public func ensureFooterSize(_ sizeInPixels: Size) {
    if layoutFrozen {
      GenmaiLog.error("Layout already frozen")
      return
    }
    minimumFooterSize.height = max(minimumFooterSize.height, sizeInPixels.height)
    minimumFooterSize.width = max(minimumFooterSize.width, sizeInPixels.width)
  }

  public func ensureHeaderSize(_ sizeInPixels: Size) {
    if layoutFrozen {
      GenmaiLog.error("Layout already frozen")
      return
    }
    minimumHeaderSize.height = max(minimumHeaderSize.height, sizeInPixels.height)
    minimumHeaderSize.width = max(minimumHeaderSize.width, sizeInPixels.width)
  }

  // ------------------------------------------------------------------------
  // Layout status
  // ------------------------------------------------------------------------

  /// Fix the layout and calculate the total size.
  public func freezeLayout() {
    if layoutFrozen {
      GenmaiLog.error("Layout already frozen")
      return
    }

    // extends necessary column for EnsureColumnsWidth()
    if ensureWidthFromColumn >= 0 && ensureWidthFromColumn < numberOfColumns
      && ensureWidthToColumn > ensureWidthFromColumn && ensureWidthToColumn < numberOfColumns
      && ensureWidth > 0
    {
      var ensuredRangeWidth = 0
      for i in ensureWidthFromColumn...ensureWidthToColumn {
        ensuredRangeWidth += columnWidthList[i]
      }
      if ensuredRangeWidth < ensureWidth {
        columnWidthList[ensureWidthToColumn] += (ensureWidth - ensuredRangeWidth)
      }
    }

    let allCellWidth = columnWidthList.reduce(0, +)

    let tableWidth =
      rowRectPaddingPixels * 2  // padding left and right
      + allCellWidth  // sum of all cell
      + vscrollWidthPixels  // scrollbar width

    // contetnt width is determined as the maximum of
    // { table width, header width, footer width }
    let contentWidth = max(tableWidth, max(minimumFooterSize.width, minimumHeaderSize.width))

    let width =
      contentWidth  // total content width
      + windowBorderPixels * 2  // border left and right

    let allCellHeight = rowHeight * numberOfRows

    let height =
      windowBorderPixels * 2  // border top and bottom
      + minimumHeaderSize.height  // header height
      + allCellHeight  // sum of all cell
      + minimumFooterSize.height  // footer height

    totalSize = Size(width, height)
    layoutFrozen = true
  }

  public var isLayoutFrozen: Bool { layoutFrozen }

  // ------------------------------------------------------------------------
  // Get component rects
  // ------------------------------------------------------------------------

  /// Get the rect which is bounding the specified cell.
  /// This rect does not include RowRectPadding.
  public func getCellRect(_ row: Int, _ column: Int) -> Rect {
    if !layoutFrozen {
      GenmaiLog.error("Layout is not frozen yet")
      return Rect()
    }
    assert(0 <= row && row < numberOfRows)
    assert(0 <= column && column < columnWidthList.count)

    let widthOfLeftCells = columnWidthList[0..<column].reduce(0, +)

    let left =
      windowBorderPixels  // border left
      + rowRectPaddingPixels  // row padding left
      + widthOfLeftCells  // left cells

    let heightOfUpperCells = rowHeight * row

    let top =
      windowBorderPixels  // border top
      + minimumHeaderSize.height  // header height
      + heightOfUpperCells  // upper cells

    let width = columnWidthList[column]

    var rect = Rect(left, top, width, rowHeight)

    // deflate top and bottom since row_height_ includes the padding
    rect.deflateRect(0, rowRectPaddingPixels, 0, rowRectPaddingPixels)

    return rect
  }

  public func getTotalSize() -> Size {
    if !layoutFrozen {
      GenmaiLog.error("Layout is not frozen yet")
      return Size()
    }
    return totalSize
  }

  public func getHeaderRect() -> Rect {
    if !layoutFrozen {
      GenmaiLog.error("Layout is not frozen yet")
      return Rect()
    }
    let width =
      totalSize.width  // total width
      - windowBorderPixels * 2  // border left and rigth
    return Rect(windowBorderPixels, windowBorderPixels, width, minimumHeaderSize.height)
  }

  public func getFooterRect() -> Rect {
    if !layoutFrozen {
      GenmaiLog.error("Layout is not frozen yet")
      return Rect()
    }
    let top =
      totalSize.height  // total width
      - minimumFooterSize.height  // footer height
      - windowBorderPixels  // border bottom
    let width =
      totalSize.width  // total width
      - windowBorderPixels * 2  // border left and right
    return Rect(windowBorderPixels, top, width, minimumFooterSize.height)
  }

  public func getVScrollBarRect() -> Rect {
    if !layoutFrozen {
      GenmaiLog.error("Layout is not frozen yet")
      return Rect()
    }
    let left =
      totalSize.width  // total width
      - windowBorderPixels  // border right
      - vscrollWidthPixels  // vscroll width
    let top =
      windowBorderPixels  // border top
      + minimumHeaderSize.height  // header height
    let height =
      totalSize.height  // total height
      - windowBorderPixels * 2  // border top and bottom
      - minimumHeaderSize.height  // header height
      - minimumFooterSize.height  // footer height
    return Rect(left, top, vscrollWidthPixels, height)
  }

  public func getVScrollIndicatorRect(_ beginIndex: Int, _ endIndex: Int, _ candidatesTotal: Int)
    -> Rect
  {
    let vscrollRect = getVScrollBarRect()

    let scrollBarHeight = Float(vscrollRect.height) / Float(candidatesTotal)
    let top = Float(vscrollRect.top) + scrollBarHeight * Float(beginIndex)
    let bottom = Float(vscrollRect.top) + scrollBarHeight * Float(endIndex + 1)

    // add 0.5f to round up
    var roundedTop = Int(top + 0.5)
    var roundedHeight = Int(bottom - top + 0.5)

    if roundedHeight < kMinimumIndicatorHeight {
      roundedHeight = kMinimumIndicatorHeight
    }
    if roundedTop + roundedHeight > vscrollRect.bottom {
      roundedTop = vscrollRect.bottom - roundedHeight
    }

    return Rect(Point(vscrollRect.left, roundedTop), Size(vscrollRect.width, roundedHeight))
  }

  /// Get the rect which is bounding the specified row.
  /// This rect includes RowRectPadding.
  public func getRowRect(_ row: Int) -> Rect {
    if !layoutFrozen {
      GenmaiLog.error("Layout is not frozen yet")
      return Rect()
    }
    assert(0 <= row && row < numberOfRows)

    let top =
      windowBorderPixels  // border top
      + minimumHeaderSize.height  // header height
      + rowHeight * row  // upper cells

    let width =
      totalSize.width  // total width
      - windowBorderPixels * 2  // border left and right
      - vscrollWidthPixels  // vscroll width

    return Rect(windowBorderPixels, top, width, rowHeight)
  }

  /// Get specified column rect.
  /// This rect includes RowRectPadding.
  public func getColumnRect(_ column: Int) -> Rect {
    if !layoutFrozen {
      GenmaiLog.error("Layout is not frozen yet")
      return Rect()
    }
    assert(0 <= column && column < columnWidthList.count)

    let widthOfLeftCells = columnWidthList[0..<column].reduce(0, +)

    let left =
      windowBorderPixels  // border left
      + rowRectPaddingPixels  // padding left
      + widthOfLeftCells  // left cells

    let top =
      windowBorderPixels  // border top
      + minimumHeaderSize.height  // header height

    let width = columnWidthList[column]

    let height = rowHeight * numberOfRows

    return Rect(left, top, width, height)
  }
}
