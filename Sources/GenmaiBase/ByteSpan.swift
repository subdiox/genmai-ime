// Safe reads and writes of little-endian values in byte buffers (not part of Mozc).
//
// The C++ reads its binary data (data set sections, dictionaries, LOUDS tries, the connection matrix, ...) through
// raw pointers. The port reads it through `Span<UInt8>` (bounds-checked, no unsafe API): a memory-mapped `Data`
// gives one with `data.span` (back-deployed; `Array.span` needs macOS 26, so arrays are read with their own
// subscripts below). Values are composed from their bytes; the compiler turns that into a single load. Apple
// platforms are little endian.

import Foundation

extension Span where Element == UInt8 {
  /// The little-endian value of type `T` at byte `offset` (traps when it does not fit).
  @inlinable
  public func loadLittleEndian<T: FixedWidthInteger>(_ type: T.Type = T.self, at offset: Int) -> T {
    let size = MemoryLayout<T>.size
    let bytes = extracting(offset..<(offset + size))
    var value: UInt64 = 0
    for i in 0..<size {
      value |= UInt64(bytes[i]) << (8 * UInt64(i))
    }
    return T(truncatingIfNeeded: value)
  }

  /// The little-endian `Float` at byte `offset`.
  @inlinable
  public func loadFloat(at offset: Int) -> Float {
    Float(bitPattern: loadLittleEndian(UInt32.self, at: offset))
  }
}

extension Array where Element == UInt8 {
  /// The little-endian value of type `T` at byte `offset` (traps when it does not fit).
  @inlinable
  public func loadLittleEndian<T: FixedWidthInteger>(_ type: T.Type = T.self, at offset: Int) -> T {
    var value: UInt64 = 0
    for i in 0..<MemoryLayout<T>.size {
      value |= UInt64(self[offset + i]) << (8 * UInt64(i))
    }
    return T(truncatingIfNeeded: value)
  }

  /// Appends `value` in little-endian byte order.
  @inlinable
  public mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
    let bits = UInt64(truncatingIfNeeded: value)
    for i in 0..<MemoryLayout<T>.size {
      append(UInt8(truncatingIfNeeded: bits >> (8 * UInt64(i))))
    }
  }

  /// Writes `value` in little-endian byte order at byte `offset` (traps when it does not fit).
  @inlinable
  public mutating func storeLittleEndian<T: FixedWidthInteger>(_ value: T, at offset: Int) {
    let bits = UInt64(truncatingIfNeeded: value)
    for i in 0..<MemoryLayout<T>.size {
      self[offset + i] = UInt8(truncatingIfNeeded: bits >> (8 * UInt64(i)))
    }
  }
}

extension Data {
  /// Appends `value` in little-endian byte order.
  @inlinable
  public mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
    let bits = UInt64(truncatingIfNeeded: value)
    for i in 0..<MemoryLayout<T>.size {
      append(UInt8(truncatingIfNeeded: bits >> (8 * UInt64(i))))
    }
  }
}
