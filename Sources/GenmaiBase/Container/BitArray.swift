// Port of mozc/src/base/container/bitarray.h (3.35.6354).

public struct BitArray: Sendable, Equatable {
  private var array: [UInt32]
  /// Returns the number of bit(s).
  public private(set) var size: Int

  /// Specify the size of bit vector
  public init(_ size: Int) {
    array = [UInt32](repeating: 0, count: 1 + (size >> 5))
    self.size = size
  }

  /// Gets true/false of |index|
  public func get(_ index: Int) -> Bool {
    ((array[index >> 5] >> UInt32(index & 0x1F)) & 1) != 0
  }

  /// Sets the bit at |index| to true.
  public mutating func set(_ index: Int) {
    array[index >> 5] |= 1 << UInt32(index & 0x1F)
  }

  /// Sets the bit at |index| to false.
  public mutating func clear(_ index: Int) {
    array[index >> 5] &= ~(1 << UInt32(index & 0x1F))
  }

  /// Returns the body of bit vector as little-endian bytes (the C++ `array()`
  /// on a little-endian host).
  public var bytes: [UInt8] {
    var result: [UInt8] = []
    result.reserveCapacity(arraySize)
    for word in array {
      withUnsafeBytes(of: word.littleEndian) { result.append(contentsOf: $0) }
    }
    return result
  }

  /// Returns the required buffer size for saving the bit vector.
  public var arraySize: Int { MemoryLayout<UInt32>.size * (1 + (size >> 5)) }

  /// Immutable accessor.
  public static func getValue(_ array: UnsafeRawBufferPointer, _ index: Int) -> Bool {
    ((array[index >> 3] >> UInt8(index & 0x7)) & 1) != 0
  }

  /// Immutable accessor.
  public static func getValue(_ array: [UInt8], _ index: Int) -> Bool {
    ((array[index >> 3] >> UInt8(index & 0x7)) & 1) != 0
  }

  public mutating func swap(_ other: inout BitArray) {
    Swift.swap(&self, &other)
  }
}
