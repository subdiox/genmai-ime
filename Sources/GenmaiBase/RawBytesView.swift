// Raw-pointer views of immutable bytes, for compatibility APIs only (not part of Mozc).
//
// The port reads binary data through `Data` / `Span<UInt8>`. A few APIs still exchange raw pointers with
// GenmaiCore (whose `DataView` hands memory-mapped sections around as `UnsafeRawBufferPointer`, and which reads
// strings through `SerializedStringArray.bytes(at:)`). Swift has no safe way to give out a pointer into a `Data`
// or to wrap foreign memory in one, so those conversions live in this one small wrapper and nowhere else. New code
// uses `Data` and `Span`.

import Foundation

/// An immutable byte range with a stable address, plus the object that keeps it alive.
///
/// `@unchecked Sendable`: the bytes are never written (read-only maps, or an immutable `Data` held by `owner`),
/// and `owner` is only retained, never used.
public struct RawBytesView: @unchecked Sendable {
  /// The bytes. Valid while this view (or another reference to `owner`) is alive.
  public let buffer: UnsafeRawBufferPointer
  /// Keeps the memory alive.
  public let owner: AnyObject?

  /// An empty view.
  public init() {
    buffer = UnsafeRawBufferPointer(start: nil, count: 0)
    owner = nil
  }

  /// Borrows memory owned by the caller: it must stay valid while `owner` is alive (or forever when `owner` is
  /// nil, e.g. static data).
  public init(borrowing buffer: UnsafeRawBufferPointer, owner: AnyObject?) {
    self.buffer = buffer
    self.owner = owner
  }

  /// A view of the bytes of `data`, which the view keeps alive.
  public init(_ data: Data) {
    // `Data` keeps up to 14 bytes inline (inside the value itself, so their address is not stable); larger
    // contents live in a heap or mapped storage object whose address does not change while the `Data` is not
    // mutated. Small contents are therefore copied into a padded, out-of-line `Data` first.
    var stable = data
    let count = data.count
    if count <= Self.inlineLimit {
      stable = Data(data)
      stable.append(contentsOf: [UInt8](repeating: 0, count: Self.inlineLimit + 1 - count))
    }
    let box = DataBox(stable)
    let base = box.data.withUnsafeBytes { $0.baseAddress }
    buffer = UnsafeRawBufferPointer(start: base, count: count)
    owner = box
  }

  /// The bytes as `Data`, without copying; the `Data` keeps `owner` alive.
  public var data: Data {
    guard let base = buffer.baseAddress, !buffer.isEmpty else { return Data() }
    if let box = owner as? DataBox, box.data.count == buffer.count {
      return box.data
    }
    let owner = self.owner
    return Data(
      bytesNoCopy: UnsafeMutableRawPointer(mutating: base), count: buffer.count,
      deallocator: .custom { _, _ in withExtendedLifetime(owner) {} })
  }

  /// A larger bound than `Data`'s inline capacity (14 bytes on 64-bit platforms).
  private static let inlineLimit = 64
}

/// Holds an immutable `Data` so that raw views into it stay valid.
private final class DataBox: Sendable {
  let data: Data
  init(_ data: Data) { self.data = data }
}
