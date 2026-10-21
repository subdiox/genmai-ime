// Test helpers for GenmaiStorageTests (not a port of a C++ file).

/// Owns a stable copy of a binary image so that tests can hand out raw
/// pointers that outlive a single withUnsafeBytes closure (the C++ tests pass
/// `builder.image().data()`).
final class ImageBuffer {
  let buffer: UnsafeMutableRawBufferPointer

  init(_ bytes: [UInt8]) {
    let buffer = UnsafeMutableRawBufferPointer.allocate(
      byteCount: max(bytes.count, 1), alignment: 8)
    buffer.initializeMemory(as: UInt8.self, repeating: 0)
    bytes.withUnsafeBytes { src in
      if src.count > 0 {
        buffer.baseAddress!.copyMemory(from: src.baseAddress!, byteCount: src.count)
      }
    }
    self.buffer = buffer
    count = bytes.count
  }

  let count: Int

  var pointer: UnsafeRawPointer { UnsafeRawPointer(buffer.baseAddress!) }
  var raw: UnsafeRawBufferPointer { UnsafeRawBufferPointer(start: buffer.baseAddress!, count: count) }

  deinit {
    buffer.deallocate()
  }
}

/// The UTF-8 bytes of `s`.
func bytes(_ s: some StringProtocol) -> [UInt8] {
  Array(s.utf8)
}
