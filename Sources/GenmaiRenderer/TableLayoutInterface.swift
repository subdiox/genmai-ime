// Port of mozc/src/renderer/table_layout_interface.h (3.35.6354).

/// Calculates the layout of a table (candidate window): rows x columns of cells, a header, a footer, a
/// vertical scroll bar and the window border. See TableLayout for the semantics of each method.
public protocol TableLayoutInterface: AnyObject {
  func initialize(numRows: Int, numColumns: Int)
  func setVScrollBar(_ widthInPixels: Int)
  func setWindowBorder(_ widthInPixels: Int)
  func setRowRectPadding(_ widthPixels: Int)
  func ensureCellSize(_ column: Int, _ size: Size)
  func ensureColumnsWidth(_ fromColumn: Int, _ toColumn: Int, _ width: Int)
  func ensureFooterSize(_ sizeInPixels: Size)
  func ensureHeaderSize(_ sizeInPixels: Size)
  func freezeLayout()
  var isLayoutFrozen: Bool { get }
  func getCellRect(_ row: Int, _ column: Int) -> Rect
  func getTotalSize() -> Size
  func getHeaderRect() -> Rect
  func getFooterRect() -> Rect
  func getVScrollBarRect() -> Rect
  func getVScrollIndicatorRect(_ beginIndex: Int, _ endIndex: Int, _ candidatesTotal: Int) -> Rect
  func getRowRect(_ row: Int) -> Rect
  func getColumnRect(_ column: Int) -> Rect
  var numberOfRows: Int { get }
  var numberOfColumns: Int { get }
}
