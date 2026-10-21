// Swift-only support for the port of mozc/src/data_manager/ (3.35.6354).
//
// The C++ DataManager hands out `absl::string_view` / `absl::Span<const T>`
// views into the memory-mapped data set and relies on the DataManager (which
// owns the Mmap) outliving every consumer. In Swift the views carry a
// reference to the backing storage (`owner`, e.g. the `Mmap`), so a section
// stays valid as long as any view of it is alive. No bytes are copied.

import Foundation
import GenmaiBase

/// A zero-copy view of a block of bytes (C++ `absl::string_view` over binary
/// data). Keeps `owner` (the memory-mapped file or an owned buffer) alive.
///
/// `@unchecked Sendable`: the viewed memory is immutable (read-only mmap or an
/// owned copy that is never written after creation).
public struct DataView: RandomAccessCollection, @unchecked Sendable {
  public typealias Index = Int
  public typealias Element = UInt8

  /// The viewed bytes. Valid while this view (or another reference to
  /// `owner`) is alive.
  public let bytes: UnsafeRawBufferPointer
  /// The object that owns the memory (e.g. `Mmap`), or nil for static data.
  public let owner: AnyObject?

  /// An empty view (C++ `absl::string_view()` / `""`).
  public static let empty = DataView()

  public init() {
    bytes = UnsafeRawBufferPointer(start: nil, count: 0)
    owner = nil
  }

  /// Wraps memory owned by `owner`. The caller guarantees that the memory is
  /// valid while `owner` is alive.
  public init(bytes: UnsafeRawBufferPointer, owner: AnyObject?) {
    self.bytes = bytes
    self.owner = owner
  }

  /// A view of the whole memory-mapped file.
  public init(_ mmap: Mmap) {
    self.init(bytes: mmap.buffer, owner: mmap)
  }

  /// Creates a view over an owned, 64-byte aligned copy of `bytes`.
  public init(copying bytes: some Collection<UInt8>) {
    let storage = DataBuffer(bytes)
    self.init(bytes: storage.bytes, owner: storage)
  }

  /// Creates a view over an owned copy of the UTF-8 bytes of `string`.
  public init(copying string: String) {
    self.init(copying: Array(string.utf8))
  }

  public var startIndex: Int { 0 }
  public var endIndex: Int { bytes.count }
  public var count: Int { bytes.count }
  public var isEmpty: Bool { bytes.isEmpty }

  public subscript(i: Int) -> UInt8 { bytes[i] }

  /// The start address (C++ `data()`), nil for an empty view without memory.
  public var baseAddress: UnsafeRawPointer? { bytes.baseAddress }

  /// `absl::ClippedSubstr(view, offset, length)`: the sub-view clipped to the
  /// bounds of this view.
  public func clippedSubstr(_ offset: Int, _ length: Int = Int.max) -> DataView {
    let start = Swift.min(Swift.max(offset, 0), count)
    let len = Swift.min(Swift.max(length, 0), count - start)
    if bytes.baseAddress == nil {
      return self
    }
    return DataView(bytes: UnsafeRawBufferPointer(rebasing: bytes[start..<(start + len)]), owner: owner)
  }

  /// Sub-view `[offset, offset + length)`; the range must be in bounds.
  public func slice(_ offset: Int, _ length: Int) -> DataView {
    precondition(offset >= 0 && length >= 0 && offset + length <= count, "DataView.slice out of range")
    if bytes.baseAddress == nil {
      return self
    }
    return DataView(bytes: UnsafeRawBufferPointer(rebasing: bytes[offset..<(offset + length)]), owner: owner)
  }

  /// Little-endian unaligned load (C++ `LoadUnaligned<T>`).
  @inline(__always)
  public func load<T: FixedWidthInteger>(fromByteOffset offset: Int, as type: T.Type = T.self) -> T {
    T(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: T.self))
  }

  /// `MakeAlignedConstSpan<T>(view)`: a typed view, or an empty one when the
  /// data is misaligned or its size is not a multiple of `T`'s size.
  public func span<T: FixedWidthInteger>(_ type: T.Type = T.self) -> DataSpan<T> {
    DataSpan(Bits.makeAlignedConstSpan(bytes, as: T.self), owner: owner)
  }

  /// The bytes decoded as UTF-8 (invalid sequences are replaced by U+FFFD).
  public var string: String {
    String(decoding: bytes, as: UTF8.self)
  }

  /// `starts_with` on bytes.
  public func starts(with prefix: some Collection<UInt8>) -> Bool {
    if prefix.count > count { return false }
    var i = 0
    for b in prefix {
      if bytes[i] != b { return false }
      i += 1
    }
    return true
  }

  /// Copies the bytes into an array.
  public var array: [UInt8] { Array(bytes) }
}

extension DataView: Equatable {
  /// Byte content equality (C++ `absl::string_view::operator==`).
  public static func == (lhs: DataView, rhs: DataView) -> Bool {
    if lhs.count != rhs.count { return false }
    if lhs.count == 0 { return true }
    return memcmp(lhs.bytes.baseAddress!, rhs.bytes.baseAddress!, lhs.count) == 0
  }
}

/// A zero-copy typed view (C++ `absl::Span<const T>` created by
/// `MakeAlignedConstSpan`). Elements are stored in little endian.
///
/// `@unchecked Sendable`: the viewed memory is immutable.
public struct DataSpan<T: FixedWidthInteger>: RandomAccessCollection, @unchecked Sendable {
  public typealias Index = Int
  public typealias Element = T

  /// The typed memory. Valid while this span (or another reference to
  /// `owner`) is alive.
  public let buffer: UnsafeBufferPointer<T>
  public let owner: AnyObject?

  public init() {
    buffer = UnsafeBufferPointer(start: nil, count: 0)
    owner = nil
  }

  public init(_ buffer: UnsafeBufferPointer<T>, owner: AnyObject?) {
    self.buffer = buffer
    self.owner = owner
  }

  public var startIndex: Int { 0 }
  public var endIndex: Int { buffer.count }
  public var count: Int { buffer.count }
  public var isEmpty: Bool { buffer.isEmpty }

  @inline(__always)
  public subscript(i: Int) -> T { T(littleEndian: buffer[i]) }
}

/// Owned, 64-byte aligned heap copy of bytes used as the owner of a
/// `DataView` that is not backed by a file.
public final class DataBuffer: @unchecked Sendable {
  private let storage: UnsafeMutableRawBufferPointer
  private let byteCount: Int

  public init(_ bytes: some Collection<UInt8>) {
    let n = bytes.count
    let storage = UnsafeMutableRawBufferPointer.allocate(byteCount: Swift.max(n, 1), alignment: 64)
    let copied: Void? = bytes.withContiguousStorageIfAvailable { src in
      if let base = src.baseAddress, n > 0 {
        storage.baseAddress!.copyMemory(from: base, byteCount: n)
      }
    }
    if copied == nil {
      var i = 0
      for b in bytes {
        storage[i] = b
        i += 1
      }
    }
    self.storage = storage
    byteCount = n
  }

  public var bytes: UnsafeRawBufferPointer {
    UnsafeRawBufferPointer(rebasing: storage[0..<byteCount])
  }

  deinit {
    storage.deallocate()
  }
}

extension SerializedStringArray {
  /// `SerializedStringArray::Init(view)` for a `DataView`; keeps the view's
  /// owner alive.
  @discardableResult
  public mutating func initialize(_ view: DataView) -> Bool {
    initialize(view.bytes, owner: view.owner)
  }

  /// `SerializedStringArray::Set(view)` for a `DataView`.
  public mutating func set(_ view: DataView) {
    set(view.bytes, owner: view.owner)
  }

  /// `SerializedStringArray::VerifyData(view)` for a `DataView`.
  public static func verifyData(_ view: DataView) -> Bool {
    verifyData(view.bytes)
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
