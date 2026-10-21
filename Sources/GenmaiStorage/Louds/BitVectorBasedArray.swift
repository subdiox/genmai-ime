// Port of mozc/src/storage/louds/bit_vector_based_array.{h,cc} (3.35.6354).
//
// get() returns the element as an UnsafeRawBufferPointer into the image (C++
// returns a pointer and writes the length to an out parameter).

/// Implementation of an array of variable length of data by using bit vector
/// supporting Rank/Select operations.
public struct BitVectorBasedArray: @unchecked Sendable {
  // @unchecked Sendable: `data` points into the caller-owned immutable image.

  // Select1 is not used, so cache is unnecessary.
  private static let kLb0CacheSize = 1024
  private static let kLb1CacheSize = 0

  private var index = SimpleSuccinctBitVectorIndex()
  private var baseLength = 0
  private var stepLength = 0
  private var data: UnsafeRawPointer?

  public init() {}

  public mutating func open(_ image: UnsafeRawPointer) {
    let indexLength = Int(UInt32(littleEndian: image.loadUnaligned(fromByteOffset: 0, as: UInt32.self)))
    let baseLength = Int(UInt32(littleEndian: image.loadUnaligned(fromByteOffset: 4, as: UInt32.self)))
    let stepLength = Int(UInt32(littleEndian: image.loadUnaligned(fromByteOffset: 8, as: UInt32.self)))
    // Check 0 padding.
    precondition(image.loadUnaligned(fromByteOffset: 12, as: UInt32.self) == 0)
    let image = image + 16

    index.initialize(image, indexLength, Self.kLb0CacheSize, Self.kLb1CacheSize)
    self.baseLength = baseLength
    self.stepLength = stepLength
    data = image + indexLength
  }

  public mutating func close() {
    index.reset()
    baseLength = 0
    stepLength = 0
    data = nil
  }

  /// Returns the element (pointer and length).
  /// Note: the result may contain '\0' chars, or may NOT be '\0'-terminated.
  public func get(_ index: Int) -> UnsafeRawBufferPointer {
    let bitIndex = self.index.select0(index + 1)
    let dataIndex = baseLength * index + stepLength * self.index.rank1(bitIndex)
    // Linear search.
    var i = bitIndex + 1
    while self.index.get(i) != 0 {
      i += 1
    }
    let length = baseLength + stepLength * (i - bitIndex - 1)
    return UnsafeRawBufferPointer(start: data.unsafelyUnwrapped + dataIndex, count: length)
  }
}
