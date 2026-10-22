// Swift-only support for the port of mozc/src/data_manager/ (3.35.6354).
//
// The C++ DataManager hands out `absl::string_view` / `absl::Span<const T>`
// views into the memory-mapped data set and relies on the DataManager (which
// owns the Mmap) outliving every consumer. In Swift a view holds a `Data` over
// the backing memory (no copy) whose deallocator keeps the memory alive, so a
// section stays valid as long as any view of it is alive. The bytes are read
// through `data.span` (bounds-checked) with the helpers of
// GenmaiBase/ByteSpan.swift.

import Foundation
import GenmaiBase

/// A zero-copy view of a block of bytes (C++ `absl::string_view` over binary
/// data).
///
/// Read the bytes with `data.span` (indices start at 0); take the span once per
/// loop, not per element.
public struct DataView: RandomAccessCollection, Sendable {
  public typealias Index = Int
  public typealias Element = UInt8

  /// The viewed bytes: a slice of the whole buffer (the mapped file or the
  /// copy) that shares its memory. Its indices are those of the whole buffer
  /// (`data.startIndex` is the offset of this view in it), so read it through
  /// `data.span` (indices from 0) or the members of this view.
  public let data: Data

  /// An empty view (C++ `absl::string_view()` / `""`).
  public static let empty = DataView()

  public init() {
    data = Data()
  }

  private init(slice: Data) {
    data = slice
  }

  /// A view of the whole memory-mapped file.
  public init(_ mmap: Mmap) {
    data = mmap.data
  }

  /// Creates a view over an owned copy of `bytes`.
  public init(copying bytes: some Collection<UInt8>) {
    data = Data(bytes)
  }

  /// Creates a view over an owned copy of the UTF-8 bytes of `string`.
  public init(copying string: String) {
    self.init(copying: Array(string.utf8))
  }

  public var startIndex: Int { 0 }
  public var endIndex: Int { data.count }
  public var count: Int { data.count }
  public var isEmpty: Bool { data.isEmpty }

  public subscript(i: Int) -> UInt8 { data.span[i] }

  /// `absl::ClippedSubstr(view, offset, length)`: the sub-view clipped to the
  /// bounds of this view.
  public func clippedSubstr(_ offset: Int, _ length: Int = Int.max) -> DataView {
    let start = Swift.min(Swift.max(offset, 0), count)
    let len = Swift.min(Swift.max(length, 0), count - start)
    let base = data.startIndex + start
    return DataView(slice: data[base..<(base + len)])
  }

  /// Sub-view `[offset, offset + length)`; the range must be in bounds.
  public func slice(_ offset: Int, _ length: Int) -> DataView {
    precondition(offset >= 0 && length >= 0 && offset + length <= count, "DataView.slice out of range")
    let base = data.startIndex + offset
    return DataView(slice: data[base..<(base + length)])
  }

  /// Little-endian unaligned load (C++ `LoadUnaligned<T>`).
  @inline(__always)
  public func load<T: FixedWidthInteger>(fromByteOffset offset: Int, as type: T.Type = T.self) -> T {
    data.span.loadLittleEndian(T.self, at: offset)
  }

  /// `MakeAlignedConstSpan<T>(view)`: a typed view, or an empty one when the
  /// data is misaligned or its size is not a multiple of `T`'s size.
  public func span<T: FixedWidthInteger>(_ type: T.Type = T.self) -> DataSpan<T> {
    let size = MemoryLayout<T>.size
    guard isAligned(to: MemoryLayout<T>.alignment), count >= size, count % size == 0 else {
      // misaligned data is passed. returns an empty span.
      return DataSpan()
    }
    return DataSpan(self)
  }

  /// The bytes decoded as UTF-8 (invalid sequences are replaced by U+FFFD).
  public var string: String {
    String(decoding: data, as: UTF8.self)
  }

  /// `starts_with` on bytes.
  public func starts(with prefix: some Collection<UInt8>) -> Bool {
    if prefix.count > count { return false }
    let bytes = data.span
    var i = 0
    for b in prefix {
      if bytes[i] != b { return false }
      i += 1
    }
    return true
  }

  /// Copies the bytes into an array.
  public var array: [UInt8] { [UInt8](data) }

  /// Byte offset of `subview` (a view inside this one, e.g. from `slice`) from
  /// the start of this view (C++ `subview.data() - data()`).
  public func byteOffset(of subview: DataView) -> Int {
    subview.data.startIndex - data.startIndex
  }

  // MARK: Alignment

  // The C++ checks the alignment of pointers into the data set (`MakeAlignedConstSpan`, the connection matrix,
  // the dictionary file). The whole buffer of a view starts at an aligned address (a mapped file starts on a page
  // boundary; a copy is a fresh allocation), so the alignment of a byte is that of its offset in the whole
  // buffer, which is `data.startIndex + offset`. The values are read with unaligned-safe loads either way.

  /// The offset of byte `offset` in the whole buffer modulo `alignment` (the
  /// misalignment of its address in C++).
  public func misalignment(of offset: Int = 0, to alignment: Int) -> Int {
    (data.startIndex + offset) % alignment
  }

  /// True if the start of the view is aligned to `alignment`.
  public func isAligned(to alignment: Int) -> Bool {
    misalignment(to: alignment) == 0
  }
}

extension DataView: Equatable {
  /// Byte content equality (C++ `absl::string_view::operator==`).
  public static func == (lhs: DataView, rhs: DataView) -> Bool {
    lhs.data == rhs.data
  }
}

/// A zero-copy typed view (C++ `absl::Span<const T>` created by
/// `MakeAlignedConstSpan`). Elements are stored in little endian.
public struct DataSpan<T: FixedWidthInteger>: RandomAccessCollection, Sendable {
  public typealias Index = Int
  public typealias Element = T

  /// The viewed bytes.
  public let view: DataView

  public init() {
    view = .empty
  }

  init(_ view: DataView) {
    self.view = view
  }

  public var startIndex: Int { 0 }
  public var endIndex: Int { count }
  public var count: Int { view.count / MemoryLayout<T>.size }
  public var isEmpty: Bool { count == 0 }

  @inline(__always)
  public subscript(i: Int) -> T {
    view.data.span.loadLittleEndian(T.self, at: i * MemoryLayout<T>.size)
  }

  /// The elements copied into an array (for hot lookups of small tables).
  public var array: [T] {
    let bytes = view.data.span
    let size = MemoryLayout<T>.size
    var result: [T] = []
    result.reserveCapacity(count)
    for i in 0..<count {
      result.append(bytes.loadLittleEndian(T.self, at: i * size))
    }
    return result
  }
}

extension SerializedStringArray {
  /// `SerializedStringArray::Init(view)` for a `DataView` (no copy).
  @discardableResult
  public mutating func initialize(_ view: DataView) -> Bool {
    initialize(view.data)
  }

  /// `SerializedStringArray::Set(view)` for a `DataView` (no copy).
  public mutating func set(_ view: DataView) {
    set(view.data)
  }

  /// `SerializedStringArray::VerifyData(view)` for a `DataView`.
  public static func verifyData(_ view: DataView) -> Bool {
    verifyData(view.data)
  }

  /// Creates and initializes an array over `view`; nil when the data is
  /// invalid.
  public init?(_ view: DataView) {
    self.init()
    if !initialize(view) {
      return nil
    }
  }
}
