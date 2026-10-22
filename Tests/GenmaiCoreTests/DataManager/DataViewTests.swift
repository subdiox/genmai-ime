// Tests of DataView / DataSpan (Swift-only support for the port of mozc/src/data_manager/). The `span` test is
// the port of MakeAlignedConstSpan in mozc/src/base/bits_test.cc (3.35.6354), on a typed view of
// little-endian integers instead of a reinterpreted struct.

import Foundation
import GenmaiBase
import Testing

@testable import GenmaiCore

@Suite struct DataViewTest {
  /// 12 little-endian UInt32 values 0, 1, ..., 11.
  private static let view: DataView = {
    var bytes: [UInt8] = []
    for i in 0..<12 {
      bytes.appendLittleEndian(UInt32(i))
    }
    return DataView(copying: bytes)
  }()

  @Test func makeAlignedConstSpan() {
    let s = Self.view
    // Unaligned.
    #expect(s.slice(1, 12).span(UInt32.self).isEmpty)
    #expect(s.slice(2, 12).span(UInt32.self).isEmpty)
    #expect(s.slice(1, 12).span(UInt16.self).isEmpty)
    #expect(!s.slice(2, 12).span(UInt16.self).isEmpty)

    // Invalid size.
    #expect(s.slice(0, 10).span(UInt32.self).isEmpty)

    // Too short.
    #expect(s.slice(0, 2).span(UInt32.self).isEmpty)

    // Aligned.
    #expect(!s.slice(12, 12).span(UInt32.self).isEmpty)
    #expect(!s.slice(12, 24).span(UInt32.self).isEmpty)
    #expect(!s.slice(24, 24).span(UInt32.self).isEmpty)

    let output = s.span(UInt32.self)
    #expect(output.count == 12)
    #expect(Array(output) == (0..<12).map { UInt32($0) })
    #expect(output.array == (0..<12).map { UInt32($0) })
    // A sub-view reads from its own start.
    #expect(Array(s.slice(8, 8).span(UInt32.self)) == [2, 3])
    #expect(s.slice(8, 8).span(UInt64.self)[0] == 2 | 3 << 32)
  }

  @Test func subviews() {
    let s = Self.view
    let sub = s.slice(8, 16)
    #expect(sub.count == 16)
    #expect(sub[0] == 2)
    #expect(sub.load(fromByteOffset: 4, as: UInt32.self) == 3)
    #expect(s.byteOffset(of: sub) == 8)
    #expect(s.byteOffset(of: sub.slice(4, 4)) == 12)
    #expect(sub.misalignment(of: 1, to: 4) == 1)
    #expect(sub.isAligned(to: 8))
    #expect(!s.slice(4, 4).isAligned(to: 8))
    #expect(sub.clippedSubstr(12, 100).count == 4)
    #expect(sub.clippedSubstr(100).isEmpty)
    #expect(sub.array == Array(s.array[8..<24]))
    #expect(sub == DataView(copying: Array(s.array[8..<24])))
    #expect(sub.starts(with: [2, 0, 0, 0, 3]))
  }

  @Test func viewsShareTheBuffer() {
    // A sub-view's `data` is a slice of the whole buffer (no copy).
    let sub = Self.view.slice(4, 8)
    #expect(sub.data.startIndex == 4)
    #expect(sub.data.span.loadLittleEndian(UInt32.self, at: 0) == 1)
  }
}
