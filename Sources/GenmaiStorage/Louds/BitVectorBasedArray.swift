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
  /// The address of the element data when the image was opened from raw
  /// memory (0 otherwise); only for `get(_:)`, which returns raw memory.
  private var rawElementsAddress = 0

  public init() {}

  /// Opens the image (header, bit vector and the element data).
  public mutating func open(_ image: Data) {
    let indexLength = openIndex(image)
    data = image.dropFirst(16 + indexLength)
    rawElementsAddress = 0
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
    rawElementsAddress = 0
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
    if rawElementsAddress != 0 {
      // Opened from raw memory: copy the (small) element.
      return Data(get(index))
    }
    let range = range(index)
    let start = data.startIndex + range.lowerBound
    return data[start..<(start + range.count)]
  }
}

// MARK: - Raw pointer interface (kept for callers that still pass raw memory)

extension BitVectorBasedArray {
  /// Opens the image at `image`, which the caller keeps alive and unchanged
  /// while the array is used (as in C++). The memory is shared, not copied.
  ///
  /// Raw pointers are needed here because the caller passes memory it owns;
  /// prefer `open(_: Data)`.
  public mutating func open(_ image: UnsafeRawPointer) {
    let mutableImage = UnsafeMutableRawPointer(mutating: image)
    let indexLength = Int(UInt32(littleEndian: image.loadUnaligned(as: UInt32.self)))
    _ = openIndex(Data(bytesNoCopy: mutableImage, count: 16 + indexLength, deallocator: .none))
    // The image size is not passed, so the element data is only read through
    // get(_:) (raw memory, as in C++).
    data = Data()
    rawElementsAddress = Int(bitPattern: image + 16 + indexLength)
  }

  /// Returns the element as raw memory inside the image given to
  /// `open(_: UnsafeRawPointer)` (valid while that memory is). Prefer
  /// `element(_:)`.
  public func get(_ index: Int) -> UnsafeRawBufferPointer {
    let range = range(index)
    guard let base = UnsafeRawPointer(bitPattern: rawElementsAddress) else {
      preconditionFailure("get(_:) needs an image opened with open(_: UnsafeRawPointer); use element(_:)")
    }
    return UnsafeRawBufferPointer(start: base + range.lowerBound, count: range.count)
  }
}
