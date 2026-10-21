// Port of mozc/src/base/coordinates.h (3.35.6354).
//
// base/coordinates.h is only used by the renderer and the IME, so it lives in GenmaiRenderer.

public struct Point: Equatable, Hashable, Sendable {
  public var x: Int
  public var y: Int

  public init(_ x: Int = 0, _ y: Int = 0) {
    self.x = x
    self.y = y
  }
}

public struct Size: Equatable, Hashable, Sendable {
  public var width: Int
  public var height: Int

  public init(_ width: Int = 0, _ height: Int = 0) {
    self.width = width
    self.height = height
  }
}

public struct Rect: Equatable, Hashable, Sendable {
  public var origin = Point()
  public var size = Size()

  public init() {}

  public init(_ x: Int, _ y: Int, _ width: Int, _ height: Int) {
    origin = Point(x, y)
    size = Size(width, height)
  }

  public init(_ origin: Point, _ size: Size) {
    self.origin = origin
    self.size = size
  }

  // Accessors
  public var width: Int { size.width }
  public var height: Int { size.height }
  public var left: Int { origin.x }
  public var top: Int { origin.y }
  public var right: Int { origin.x + size.width }
  public var bottom: Int { origin.y + size.height }

  // Other methods
  public mutating func deflateRect(_ l: Int, _ t: Int, _ r: Int, _ b: Int) {
    origin.x += l
    origin.y += t
    size.width -= l + r
    size.height -= t + b
  }

  public mutating func deflateRect(_ x: Int, _ y: Int) { deflateRect(x, y, x, y) }
  public mutating func deflateRect(_ s: Size) { deflateRect(s.width, s.height) }

  /// Returns true if the right side is less than or equal to the coordinate
  /// of the left side, or the coordinate of the bottom side is less than or
  /// equal to the coordinate of the top side.
  /// This behaviour is compatible to the IsRectEmpty API
  public var isRectEmpty: Bool { size.width <= 0 || size.height <= 0 }

  public func ptrInRect(_ p: Point) -> Bool {
    p.x >= origin.x && p.x <= origin.x + size.width && p.y >= origin.y
      && p.y <= origin.y + size.height
  }
}
