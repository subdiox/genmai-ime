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

  /// The viewed bytes (`startIndex` is always 0). Shares the backing memory.
  public let data: Data
  /// The backing memory, for the pointer-based APIs (see `PinnedBytes`).
  private let pinned: PinnedBytes?
  /// Offset of `data` in `pinned`.
  private let pinnedOffset: Int

  /// An empty view (C++ `absl::string_view()` / `""`).
  public static let empty = DataView()

  public init() {
    data = Data()
    pinned = nil
    pinnedOffset = 0
  }

  private init(_ pinned: PinnedBytes, offset: Int, count: Int) {
    self.pinned = pinned
    pinnedOffset = offset
    data = pinned.makeData(offset, count)
  }

  /// A view of the whole memory-mapped file.
  public init(_ mmap: Mmap) {
    let pinned = PinnedBytes(mmap)
    self.init(pinned, offset: 0, count: pinned.count)
  }

  /// Creates a view over an owned, 64-byte aligned copy of `bytes`.
  public init(copying bytes: some Collection<UInt8>) {
    let pinned = PinnedBytes(copying: bytes)
    self.init(pinned, offset: 0, count: pinned.count)
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
    guard let pinned else {
      return self
    }
    return DataView(pinned, offset: pinnedOffset + start, count: len)
  }

  /// Sub-view `[offset, offset + length)`; the range must be in bounds.
  public func slice(_ offset: Int, _ length: Int) -> DataView {
    precondition(offset >= 0 && length >= 0 && offset + length <= count, "DataView.slice out of range")
    guard let pinned else {
      return self
    }
    return DataView(pinned, offset: pinnedOffset + offset, count: length)
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

  // MARK: Pointer-based interop

  // The pointer-based APIs of GenmaiBase / GenmaiStorage (`SerializedStringArray.set`, `LoudsTrie.open`,
  // `BitVectorBasedArray`, `ExistenceFilter.read`, `Mmap.maybeMLock`) take raw pointers into the image. Until they
  // take `Data`, these members hand out the backing memory. The memory stays valid while `owner` is alive.

  /// The viewed bytes as a raw buffer (valid while `owner` is alive).
  public var bytes: UnsafeRawBufferPointer {
    pinned?.bytes(pinnedOffset, count) ?? UnsafeRawBufferPointer(start: nil, count: 0)
  }

  /// The start address (C++ `data()`), nil for an empty view without memory.
  public var baseAddress: UnsafeRawPointer? { bytes.baseAddress }

  /// The object that keeps the backing memory alive, nil for an empty view.
  public var owner: AnyObject? { pinned }

  /// Byte offset of `element` (a buffer inside this view, e.g. from
  /// `BitVectorBasedArray.get`) from the start of this view.
  public func byteOffset(of element: UnsafeRawBufferPointer) -> Int {
    guard let start = element.baseAddress, let base = baseAddress else {
      return 0
    }
    return start - base
  }

  /// The address of byte `offset` modulo `alignment` (the address of an empty
  /// view is 0).
  public func misalignment(of offset: Int = 0, to alignment: Int) -> Int {
    (Int(bitPattern: baseAddress) &+ offset) % alignment
  }

  /// True if the start address is a multiple of `alignment`.
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

/// The backing memory of `DataView`s: a memory-mapped file or an owned,
/// 64-byte aligned copy.
///
/// The only place where the views touch raw memory: `Data` cannot wrap memory
/// it does not own without a pointer, and the pointer-based APIs of
/// GenmaiBase / GenmaiStorage need a stable address (a small `Data` is stored
/// inline, so its address is not stable). `@unchecked Sendable`: the memory is
/// immutable (read-only mmap, or a copy that is never written after `init`)
/// and freed only in `deinit`.
private final class PinnedBytes: @unchecked Sendable {
  private let base: UnsafeRawBufferPointer
  /// The mapped file, or nil when `base` is owned (allocated in `init`).
  private let mmap: Mmap?

  init(_ mmap: Mmap) {
    base = mmap.buffer
    self.mmap = mmap
  }

  init(copying bytes: some Collection<UInt8>) {
    let n = bytes.count
    let storage = UnsafeMutableRawBufferPointer.allocate(byteCount: Swift.max(n, 1), alignment: 64)
    let copied: Void? = bytes.withContiguousStorageIfAvailable { src in
      storage.copyMemory(from: UnsafeRawBufferPointer(src))
    }
    if copied == nil {
      var i = 0
      for b in bytes {
        storage[i] = b
        i += 1
      }
    }
    base = UnsafeRawBufferPointer(rebasing: storage[0..<n])
    mmap = nil
  }

  deinit {
    if mmap == nil {
      base.deallocate()
    }
  }

  var count: Int { base.count }

  func bytes(_ offset: Int, _ count: Int) -> UnsafeRawBufferPointer {
    UnsafeRawBufferPointer(rebasing: base[offset..<(offset + count)])
  }

  /// A `Data` over `[offset, offset + count)` without copying; it keeps this
  /// object alive.
  func makeData(_ offset: Int, _ count: Int) -> Data {
    guard count > 0, let start = base.baseAddress else {
      return Data()
    }
    return Data(
      bytesNoCopy: UnsafeMutableRawPointer(mutating: start + offset), count: count,
      deallocator: .custom { [self] _, _ in withExtendedLifetime(self) {} })
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

  // MARK: Pointer-based interop (see DataView)

  /// The typed memory (valid while `owner` is alive).
  public var buffer: UnsafeBufferPointer<T> { Bits.makeAlignedConstSpan(view.bytes, as: T.self) }

  /// The object that keeps the memory alive.
  public var owner: AnyObject? { view.owner }
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
