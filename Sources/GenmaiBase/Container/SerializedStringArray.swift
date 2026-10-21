// Port of mozc/src/base/container/serialized_string_array.{h,cc} (3.35.6354).

import Foundation

/// Immutable array of strings serialized in binary image.  This class is used
/// to serialize arrays of strings to byte sequence, and access the serialized
/// array, in such a way that no deserialization is required at runtime, which
/// is different from protobuf's repeated string field.
///
/// * Prerequisite
/// Little endian is assumed.
///
/// * Serialized data creation
/// To create a binary image, use SerializedStringArray.serializeToBuffer() or
/// build_tools/serialized_string_array_builder.py.
///
/// * Array access
/// At runtime, we can access array contents just by loading a binary image,
/// e.g., from a file, onto memory. (The Swift port uses unaligned loads, so the
/// 4-byte alignment of the C++ version is not required.)
///
/// * Binary format
/// The former block of size 4 + 8 * N bytes is an array of uint32_t (in little
/// endian order) storing the array size and offset and length of each string.
/// These data can be used to extract strings from the latter block.
///
/// +=====================================================================+
/// | Number of elements N in array  (4 byte)                             |
/// +---------------------------------------------------------------------+
/// | Byte offset of string[0]  (4 byte)                                  |
/// + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
/// | Byte length of string[0]  (4 byte, excluding terminating '\0')      |
/// +---------------------------------------------------------------------+
/// |                      .                                              |
/// +---------------------------------------------------------------------+
/// | Byte offset of string[N - 1]  (4 byte)                              |
/// + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
/// | Byte length of string[N - 1]  (4 byte, excluding terminating '\0')  |
/// +=====================================================================+
/// | string[0]  (Variable length)                                        |
/// + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
/// | '\0'       (1 byte)                                                 |
/// +---------------------------------------------------------------------+
/// |                      .                                              |
/// +---------------------------------------------------------------------+
/// | string[N - 1]  (Variable length)                                    |
/// + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
/// | '\0'           (1 byte)                                             |
/// +=====================================================================+
///
/// Memory: the array is a view over `data`, like the C++ class over an
/// `absl::string_view`. The memory must outlive the array unless an `owner`
/// object keeping it alive is given (e.g. the memory-mapped data set), or the
/// array was created with `init?(bytes:)`, which owns a copy.
///
/// `@unchecked Sendable`: the viewed memory is immutable (read-only mmapped or
/// owned copy).
public struct SerializedStringArray: RandomAccessCollection, @unchecked Sendable {
  public typealias Index = Int
  public typealias Element = String

  private var data_ = UnsafeRawBufferPointer(start: nil, count: 0)
  private var owner: AnyObject?

  /// Constructs an empty array.
  public init() {}

  /// Initializes the array from an owned copy of `bytes`. Returns nil when the
  /// data is invalid.
  public init?(bytes: [UInt8]) {
    let storage = OwnedBytes(bytes)
    if !initialize(storage.bytes, owner: storage) {
      return nil
    }
  }

  /// Initializes the array from given memory block.  Returns false when the
  /// data is invalid. (C++ `Init`.)
  @discardableResult
  public mutating func initialize(_ data: UnsafeRawBufferPointer, owner: AnyObject? = nil) -> Bool {
    if SerializedStringArray.verifyData(data) {
      data_ = data
      self.owner = owner
      return true
    }
    clear()
    return false
  }

  /// Initializes the array from given memory block without verifying data.
  public mutating func set(_ data: UnsafeRawBufferPointer, owner: AnyObject? = nil) {
    assert(SerializedStringArray.verifyData(data))
    data_ = data
    self.owner = owner
  }

  /// The number of elements.
  public var size: Int {
    // The first 4 bytes of data stores the number of elements in this array
    // in little endian order.
    if data_.isEmpty { return 0 }
    return Int(UInt32(littleEndian: data_.loadUnaligned(fromByteOffset: 0, as: UInt32.self)))
  }

  public var count: Int { size }
  public var isEmpty: Bool { size == 0 }
  public var startIndex: Int { 0 }
  public var endIndex: Int { size }

  /// The underlying memory block.
  public var data: UnsafeRawBufferPointer { data_ }

  /// The owner of the memory block, if any.
  public var dataOwner: AnyObject? { owner }

  public mutating func clear() {
    data_ = UnsafeRawBufferPointer(start: nil, count: 0)
    owner = nil
  }

  public mutating func swap(_ other: inout SerializedStringArray) {
    Swift.swap(&self, &other)
  }

  private func offsetAt(_ index: Int) -> Int {
    Int(UInt32(littleEndian: data_.loadUnaligned(fromByteOffset: 4 + 8 * index, as: UInt32.self)))
  }

  private func lengthAt(_ index: Int) -> Int {
    Int(UInt32(littleEndian: data_.loadUnaligned(fromByteOffset: 8 + 8 * index, as: UInt32.self)))
  }

  /// Returns the bytes of the i-th string (without copying).
  public func bytes(at i: Int) -> UnsafeRawBufferPointer {
    let offset = offsetAt(i)
    return UnsafeRawBufferPointer(rebasing: data_[offset..<(offset + lengthAt(i))])
  }

  /// Returns the i-th string (decoded as UTF-8).
  public subscript(i: Int) -> String {
    String(decoding: bytes(at: i), as: UTF8.self)
  }

  /// Bytewise three-way comparison of the i-th string with `key`.
  public func compare(at i: Int, with key: some StringProtocol) -> Int {
    Strings.compareBytes(bytes(at: i), key.utf8)
  }

  /// std::lower_bound(begin(), end(), key) with bytewise comparison.
  public func lowerBound(_ key: some StringProtocol) -> Int {
    lowerBound(in: 0..<size, key)
  }

  /// std::lower_bound over the given index range with bytewise comparison.
  public func lowerBound(in range: Range<Int>, _ key: some StringProtocol) -> Int {
    var first = range.lowerBound
    var count = range.count
    while count > 0 {
      let step = count / 2
      let it = first + step
      if compare(at: it, with: key) < 0 {
        first = it + 1
        count -= step + 1
      } else {
        count = step
      }
    }
    return first
  }

  /// std::upper_bound(begin(), end(), key) with bytewise comparison.
  public func upperBound(_ key: some StringProtocol) -> Int {
    upperBound(in: 0..<size, key)
  }

  /// std::upper_bound over the given index range with bytewise comparison.
  public func upperBound(in range: Range<Int>, _ key: some StringProtocol) -> Int {
    var first = range.lowerBound
    var count = range.count
    while count > 0 {
      let step = count / 2
      let it = first + step
      if compare(at: it, with: key) <= 0 {
        first = it + 1
        count -= step + 1
      } else {
        count = step
      }
    }
    return first
  }

  /// std::binary_search with bytewise comparison.
  public func binarySearch(_ key: some StringProtocol) -> Bool {
    let lb = lowerBound(key)
    return lb != size && compare(at: lb, with: key) == 0
  }

  /// Checks if the data is a valid array image.
  public static func verifyData(_ data: UnsafeRawBufferPointer) -> Bool {
    if data.count < 4 {
      // Array size is missing
      return false
    }
    func u32(_ i: Int) -> Int {
      Int(UInt32(littleEndian: data.loadUnaligned(fromByteOffset: 4 * i, as: UInt32.self)))
    }
    let size = u32(0)

    let minRequiredDataSize = 4 + (4 + 4) * size
    if data.count < minRequiredDataSize {
      // Lack of data.
      return false
    }

    var prevStrEnd = minRequiredDataSize
    for i in 0..<size {
      let offset = u32(2 * i + 1)
      let len = u32(2 * i + 2)
      if offset < prevStrEnd {
        // Invalid offset for string i
        return false
      }
      if len >= data.count || offset > data.count - len {
        // Invalid length for string i
        return false
      }
      if data[offset + len] != 0 {
        // string[i] is not null-terminated
        return false
      }
      prevStrEnd = offset + len + 1
    }

    return true
  }

  public static func verifyData(_ data: [UInt8]) -> Bool {
    data.withUnsafeBytes { verifyData($0) }
  }

  /// Creates a byte image of |strs|.
  public static func serializeToBuffer<S: StringProtocol>(_ strs: [S]) -> [UInt8] {
    let headerByteSize = 4 * (1 + 2 * strs.count)

    // Calculate the offsets of each string.
    var offsets: [Int] = []
    offsets.reserveCapacity(strs.count)
    var currentOffset = headerByteSize  // The offset for first string.
    for s in strs {
      offsets.append(currentOffset)
      // The next string is written after terminating '\0', so increment one
      // byte in addition to the string byte length.
      currentOffset += s.utf8.count + 1
    }

    // At this point, |current_offset| is the byte length of the whole binary
    // image.
    var buffer = [UInt8](repeating: 0, count: currentOffset)
    func put(_ value: Int, _ at: Int) {
      let v = UInt32(value).littleEndian
      withUnsafeBytes(of: v) { b in
        for k in 0..<4 { buffer[at + k] = b[k] }
      }
    }
    put(strs.count, 0)
    for (i, s) in strs.enumerated() {
      // Fill offset and length.
      put(offsets[i], 4 * (2 * i + 1))
      put(s.utf8.count, 4 * (2 * i + 2))
      // Copy string buffer at the calculated offset.  Guarantee that the
      // buffer is null-terminated.
      var p = offsets[i]
      for c in s.utf8 {
        buffer[p] = c
        p += 1
      }
      buffer[p] = 0
    }
    return buffer
  }

  /// Writes the byte image of |strs| to `filepath`.
  public static func serializeToFile<S: StringProtocol>(_ strs: [S], _ filepath: String) throws {
    let data = serializeToBuffer(strs)
    try Data(data).write(to: URL(fileURLWithPath: filepath))
  }
}

/// A heap copy of bytes, 8-byte aligned.
final class OwnedBytes: @unchecked Sendable {
  let buffer: UnsafeMutableRawBufferPointer

  init(_ bytes: [UInt8]) {
    let buf = UnsafeMutableRawBufferPointer.allocate(byteCount: max(bytes.count, 1), alignment: 8)
    bytes.withUnsafeBytes { src in
      if let base = src.baseAddress, let dst = buf.baseAddress {
        dst.copyMemory(from: base, byteCount: src.count)
      }
    }
    buffer = buf
    byteCount = bytes.count
  }

  private let byteCount: Int

  var bytes: UnsafeRawBufferPointer {
    UnsafeRawBufferPointer(rebasing: buffer[0..<byteCount])
  }

  deinit {
    buffer.deallocate()
  }
}
