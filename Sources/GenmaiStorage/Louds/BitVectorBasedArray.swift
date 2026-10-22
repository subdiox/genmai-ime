// Port of mozc/src/storage/louds/bit_vector_based_array.{h,cc} (3.35.6354).
//
// The image is an immutable `Data` (typically a slice of a memory-mapped file,
// so nothing is copied). element(_:) returns the element as a `Data` slice of
// the image (C++ returns a pointer and writes the length to an out parameter).

import Foundation
import GenmaiBase

/// Implementation of an array of variable length of data by using bit vector
/// supporting Rank/Select operations.
public struct BitVectorBasedArray: Sendable {
  // Select1 is not used, so cache is unnecessary.
  private static let kLb0CacheSize = 1024
  private static let kLb1CacheSize = 0

  private var index = SimpleSuccinctBitVectorIndex()
  private var baseLength = 0
  private var stepLength = 0
  private var data = Data()
  /// The offset of the element data in the image.
  private var dataOffset = 0

  public init() {}

  /// Opens the image (header, bit vector and the element data).
  public mutating func open(_ image: Data) {
    let indexLength = openIndex(image)
    data = image.dropFirst(16 + indexLength)
    dataOffset = 16 + indexLength
  }

  /// Reads the header and initializes the bit vector. Returns its length.
  private mutating func openIndex(_ image: Data) -> Int {
    let header = image.span
    let indexLength = Int(header.loadLittleEndian(UInt32.self, at: 0))
    let baseLength = Int(header.loadLittleEndian(UInt32.self, at: 4))
    let stepLength = Int(header.loadLittleEndian(UInt32.self, at: 8))
    // Check 0 padding.
    precondition(header.loadLittleEndian(UInt32.self, at: 12) == 0)

    index.initialize(image.dropFirst(16), indexLength, Self.kLb0CacheSize, Self.kLb1CacheSize)
    self.baseLength = baseLength
    self.stepLength = stepLength
    return indexLength
  }

  public mutating func close() {
    index.reset()
    baseLength = 0
    stepLength = 0
    data = Data()
    dataOffset = 0
  }

  /// Returns the byte range of the element in the element data.
  private func range(_ index: Int) -> Range<Int> {
    let bitIndex = self.index.select0(index + 1)
    let dataIndex = baseLength * index + stepLength * self.index.rank1(bitIndex)
    // Linear search.
    var i = bitIndex + 1
    while self.index.get(i) != 0 {
      i += 1
    }
    let length = baseLength + stepLength * (i - bitIndex - 1)
    return dataIndex..<(dataIndex + length)
  }

  /// Returns the element (a slice of the image; its indices are those of the
  /// image, use `.span` or iterate it).
  /// Note: the result may contain '\0' chars, or may NOT be '\0'-terminated.
  public func element(_ index: Int) -> Data {
    let range = range(index)
    let start = data.startIndex + range.lowerBound
    return data[start..<(start + range.count)]
  }

  /// Returns the byte range of the element in the image given to `open(_:)`
  /// (C++ `Get(index, &length) - image`).
  public func byteRange(_ index: Int) -> Range<Int> {
    let range = range(index)
    return (dataOffset + range.lowerBound)..<(dataOffset + range.upperBound)
  }
}
