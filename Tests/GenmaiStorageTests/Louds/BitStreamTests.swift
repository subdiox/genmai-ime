// Port of mozc/src/storage/louds/bit_stream_test.cc (3.35.6354).

import Testing

@testable import GenmaiStorage

@Suite struct BitStreamTest {
  @Test func pattern1() {
    var bitStream = BitStream()
    for i in 0..<128 {
      bitStream.pushBit(0)
      bitStream.pushBit(1)
      #expect(bitStream.numBits == 2 * (i + 1))
      #expect(bitStream.byteSize == i / 4 + 1)
    }

    #expect(bitStream.image == [UInt8](repeating: 0xAA, count: 32))
  }

  @Test func pattern2() {
    var bitStream = BitStream()
    for i in 0..<128 {
      bitStream.pushBit(0)
      bitStream.pushBit(0)
      bitStream.pushBit(1)
      bitStream.pushBit(1)
      #expect(bitStream.numBits == 4 * (i + 1))
      #expect(bitStream.byteSize == i / 2 + 1)
    }

    #expect(bitStream.image == [UInt8](repeating: 0xCC, count: 64))
  }

  @Test func fillPadding32() {
    var bitStream = BitStream()

    bitStream.fillPadding32()
    #expect(bitStream.image == [])

    bitStream.pushBit(1)
    bitStream.fillPadding32()
    #expect(bitStream.image == [0x01, 0x00, 0x00, 0x00])
  }

  @Test func pushInt32() {
    var image: [UInt8] = []
    var expected = [UInt8](repeating: 0, count: 4)
    GenmaiStorage.pushInt32(0, &image)
    #expect(image == expected)

    expected += [UInt8](repeating: 0xff, count: 4)

    GenmaiStorage.pushInt32(0xffff_ffff, &image)
    #expect(image == expected)

    expected += [0x78, 0x56, 0x34, 0x12]
    GenmaiStorage.pushInt32(0x1234_5678, &image)
    #expect(image == expected)
  }
}
