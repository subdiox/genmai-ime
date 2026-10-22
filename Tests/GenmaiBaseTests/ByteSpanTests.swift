// Tests of the safe little-endian byte helpers (not part of Mozc).

import Foundation
import Testing

@testable import GenmaiBase

@Suite struct ByteSpanTests {
  @Test func loads() {
    let bytes: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x80, 0x3F]
    let span = Data(bytes).span
    #expect(span.loadLittleEndian(UInt16.self, at: 0) == 0x0201)
    #expect(span.loadLittleEndian(UInt32.self, at: 0) == 0x0403_0201)
    #expect(span.loadLittleEndian(UInt32.self, at: 1) == 0xFF04_0302)
    #expect(span.loadLittleEndian(Int32.self, at: 4) == -1)
    #expect(span.loadLittleEndian(UInt64.self, at: 0) == 0xFFFF_FFFF_0403_0201)
    #expect(span.loadFloat(at: 8) == 1.0)
    #expect(bytes.loadLittleEndian(UInt32.self, at: 1) == 0xFF04_0302)
  }

  @Test func stores() {
    var bytes: [UInt8] = []
    bytes.appendLittleEndian(UInt32(0x0403_0201))
    bytes.appendLittleEndian(Int16(-2))
    #expect(bytes == [0x01, 0x02, 0x03, 0x04, 0xFE, 0xFF])
    bytes.storeLittleEndian(UInt16(0xBBAA), at: 1)
    #expect(bytes == [0x01, 0xAA, 0xBB, 0x04, 0xFE, 0xFF])
    var data = Data()
    data.appendLittleEndian(UInt32(7))
    #expect(Array(data) == [7, 0, 0, 0])
  }
}
