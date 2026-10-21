// Port of mozc/src/base/bits.h (3.35.6354).
//
// Functions to manipulate bits and bytes. The C++ templates over iterators are
// replaced with functions over raw pointers / raw buffers and byte offsets.
// All loads are unaligned-safe. Apple platforms are little endian, so the
// "native byte order" is little endian.

public enum Bits {
  /// Reverses the byte order of the given integer value (std::byteswap).
  public static func byteswap<T: FixedWidthInteger>(_ n: T) -> T {
    n.byteSwapped
  }

  /// Loads a value of type T from `pointer` with the native byte order.
  public static func loadUnaligned<T: FixedWidthInteger>(
    _ pointer: UnsafeRawPointer, as type: T.Type = T.self
  ) -> T {
    pointer.loadUnaligned(as: T.self)
  }

  /// Loads a value of type T at `offset` of `buffer` with the native byte
  /// order.
  public static func loadUnaligned<T: FixedWidthInteger>(
    _ buffer: UnsafeRawBufferPointer, _ offset: Int, as type: T.Type = T.self
  ) -> T {
    precondition(offset >= 0 && offset + MemoryLayout<T>.size <= buffer.count)
    return buffer.loadUnaligned(fromByteOffset: offset, as: T.self)
  }

  /// Loads a value of type T at `offset` of `bytes` with the native byte order.
  public static func loadUnaligned<T: FixedWidthInteger>(
    _ bytes: [UInt8], _ offset: Int, as type: T.Type = T.self
  ) -> T {
    bytes.withUnsafeBytes { loadUnaligned($0, offset, as: T.self) }
  }

  /// LoadUnalignedAdvance() advances the offset in addition to
  /// LoadUnaligned() to point to the element immediately after the loaded
  /// value.
  public static func loadUnalignedAdvance<T: FixedWidthInteger>(
    _ buffer: UnsafeRawBufferPointer, _ offset: inout Int, as type: T.Type = T.self
  ) -> T {
    let result: T = loadUnaligned(buffer, offset)
    offset += MemoryLayout<T>.size
    return result
  }

  /// Loads a little-endian value of type T at `offset` of `buffer`.
  public static func loadLittleEndian<T: FixedWidthInteger>(
    _ buffer: UnsafeRawBufferPointer, _ offset: Int, as type: T.Type = T.self
  ) -> T {
    T(littleEndian: loadUnaligned(buffer, offset, as: T.self))
  }

  /// Stores a value of sizeof(T) to `pointer` with the native byte order.
  /// Returns a pointer pointing the byte immediately after the stored value.
  @discardableResult
  public static func storeUnaligned<T: FixedWidthInteger>(
    _ value: T, _ pointer: UnsafeMutableRawPointer
  ) -> UnsafeMutableRawPointer {
    pointer.storeBytes(of: value, as: T.self)
    return pointer + MemoryLayout<T>.size
  }

  /// Stores a value of sizeof(T) at `offset` of `buffer` with the native byte
  /// order. Returns the offset immediately after the stored value.
  @discardableResult
  public static func storeUnaligned<T: FixedWidthInteger>(
    _ value: T, _ buffer: UnsafeMutableRawBufferPointer, _ offset: Int
  ) -> Int {
    precondition(offset >= 0 && offset + MemoryLayout<T>.size <= buffer.count)
    buffer.storeBytes(of: value, toByteOffset: offset, as: T.self)
    return offset + MemoryLayout<T>.size
  }

  /// Stores a value of sizeof(T) at `offset` of `bytes` with the native byte
  /// order. Returns the offset immediately after the stored value.
  @discardableResult
  public static func storeUnaligned<T: FixedWidthInteger>(
    _ value: T, _ bytes: inout [UInt8], _ offset: Int
  ) -> Int {
    bytes.withUnsafeMutableBytes { storeUnaligned(value, $0, offset) }
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
