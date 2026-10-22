// Port of mozc/src/base/bits.h (3.35.6354).
//
// Functions to manipulate bits and bytes. The C++ templates over iterators are
// replaced with functions over `Span<UInt8>` / `[UInt8]` and byte offsets.
// All loads are unaligned-safe. Apple platforms are little endian, so the
// "native byte order" is little endian.

public enum Bits {
  /// Reverses the byte order of the given integer value (std::byteswap).
  public static func byteswap<T: FixedWidthInteger>(_ n: T) -> T {
    n.byteSwapped
  }

  /// Loads a value of type T at `offset` of `bytes` with the native byte
  /// order (little endian on Apple platforms).
  public static func loadUnaligned<T: FixedWidthInteger>(
    _ bytes: Span<UInt8>, _ offset: Int, as type: T.Type = T.self
  ) -> T {
    bytes.loadLittleEndian(T.self, at: offset)
  }

  /// Loads a value of type T at `offset` of `bytes` with the native byte order.
  public static func loadUnaligned<T: FixedWidthInteger>(
    _ bytes: [UInt8], _ offset: Int, as type: T.Type = T.self
  ) -> T {
    bytes.loadLittleEndian(T.self, at: offset)
  }

  /// LoadUnalignedAdvance() advances the offset in addition to
  /// LoadUnaligned() to point to the element immediately after the loaded
  /// value.
  public static func loadUnalignedAdvance<T: FixedWidthInteger>(
    _ bytes: Span<UInt8>, _ offset: inout Int, as type: T.Type = T.self
  ) -> T {
    let result: T = loadUnaligned(bytes, offset)
    offset += MemoryLayout<T>.size
    return result
  }

  /// Loads a little-endian value of type T at `offset` of `bytes`.
  public static func loadLittleEndian<T: FixedWidthInteger>(
    _ bytes: Span<UInt8>, _ offset: Int, as type: T.Type = T.self
  ) -> T {
    bytes.loadLittleEndian(T.self, at: offset)
  }

  /// Stores a value of sizeof(T) at `offset` of `bytes` with the native byte
  /// order. Returns the offset immediately after the stored value.
  @discardableResult
  public static func storeUnaligned<T: FixedWidthInteger>(
    _ value: T, _ bytes: inout [UInt8], _ offset: Int
  ) -> Int {
    precondition(offset >= 0 && offset + MemoryLayout<T>.size <= bytes.count)
    bytes.storeLittleEndian(value, at: offset)
    return offset + MemoryLayout<T>.size
  }

  /// HostToNet changes the host byte order value to the network byte order.
  public static func hostToNet<T: FixedWidthInteger>(_ n: T) -> T { n.bigEndian }

  /// NetToHost changes the network byte order value to the host byte order.
  public static func netToHost<T: FixedWidthInteger>(_ n: T) -> T { T(bigEndian: n) }

  /// HostToLittle changes the host byte order value to the little endian
  /// order.
  public static func hostToLittle<T: FixedWidthInteger>(_ n: T) -> T { n.littleEndian }

  /// LittleToHost changes the little endian byte order to the host byte order.
  public static func littleToHost<T: FixedWidthInteger>(_ n: T) -> T { T(littleEndian: n) }

  /// Returns a typed buffer over data. Returns an empty buffer when the data
  /// has an invalid alignment or size (MakeAlignedConstSpan).
  /// The result is valid only while `data` is.
  ///
  /// Unsafe by nature (reinterprets raw memory as `T`; Swift has no safe way to view bytes as an arbitrary
  /// struct). Kept only for GenmaiCore's `DataView`; new code reads fields with `Span<UInt8>.loadLittleEndian`.
  public static func makeAlignedConstSpan<T>(_ data: UnsafeRawBufferPointer, as type: T.Type = T.self)
    -> UnsafeBufferPointer<T>
  {
    guard let base = data.baseAddress,
      Int(bitPattern: base) % MemoryLayout<T>.alignment == 0,
      data.count >= MemoryLayout<T>.size,
      data.count % MemoryLayout<T>.stride == 0
    else {
      // misaligned data is passed. returns an empty span.
      return UnsafeBufferPointer(start: nil, count: 0)
    }
    return UnsafeBufferPointer(
      start: base.assumingMemoryBound(to: T.self), count: data.count / MemoryLayout<T>.stride)
  }
}
