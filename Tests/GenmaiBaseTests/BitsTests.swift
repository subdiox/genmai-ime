// Port of mozc/src/base/bits_test.cc (3.35.6354).

import Testing

@testable import GenmaiBase

@Suite struct BitsTest {
  @Test func loadUnaligned() {
    let kArray: [UInt8] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    #expect(Bits.loadUnaligned(kArray, 2, as: UInt8.self) == 2)
    #expect(Bits.hostToLittle(Bits.loadUnaligned(kArray, 1, as: UInt16.self)) == 0x0201)
    #expect(Bits.hostToLittle(Bits.loadUnaligned(kArray, 5, as: UInt32.self)) == 0x0807_0605)
    #expect(Bits.hostToLittle(Bits.loadUnaligned(kArray, 3, as: UInt64.self)) == 0xa09_0807_0605_0403)

    kArray.withUnsafeBytes { sv in
      var iter = 1
      #expect(Bits.hostToLittle(Bits.loadUnalignedAdvance(sv, &iter, as: UInt32.self)) == 0x0403_0201)
      #expect(Bits.hostToLittle(Bits.loadUnalignedAdvance(sv, &iter, as: UInt32.self)) == 0x0807_0605)
      #expect(iter == 1 + 2 * MemoryLayout<UInt32>.size)
      #expect(Bits.loadLittleEndian(sv, 1, as: UInt32.self) == 0x0403_0201)
    }

    do {
      let vec: [UInt16] = [0x1234, 0x5678, 0x9abc, 0xdef0]
      vec.withUnsafeBytes { buf in
        var iter = 0
        #expect(Bits.hostToNet(Bits.loadUnalignedAdvance(buf, &iter, as: UInt32.self)) == 0x3412_7856)
        #expect(Bits.hostToNet(Bits.loadUnalignedAdvance(buf, &iter, as: UInt32.self)) == 0xbc9a_f0de)
        #expect(iter / MemoryLayout<UInt16>.size == 4)
      }
    }
  }

  @Test func storeAndLoadUnaligned() {
    var buf = [UInt8](repeating: 0xff, count: 12)

    #expect(Bits.storeUnaligned(UInt16(42), &buf, 0) == MemoryLayout<UInt16>.size)
    #expect(Bits.loadUnaligned(buf, 0, as: UInt16.self) == 42)
    #expect(buf[2...].allSatisfy { $0 == 0xff })

    buf = [UInt8](repeating: 0xff, count: 12)
    var iter = Bits.storeUnaligned(Bits.hostToLittle(UInt32(0x3141_5926)), &buf, 5)
    #expect(Bits.loadUnaligned(buf, 5, as: UInt32.self) == 0x3141_5926)
    #expect(buf == [0xff, 0xff, 0xff, 0xff, 0xff, 0x26, 0x59, 0x41, 0x31, 0xff, 0xff, 0xff])
    #expect(iter == 5 + MemoryLayout<UInt32>.size)

    buf = [UInt8](repeating: 0xff, count: 12)
    iter = Bits.storeUnaligned(Bits.hostToNet(UInt64(0x0123_4567_89ab_cdef)), &buf, 3)
    #expect(buf == [0xff, 0xff, 0xff, 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, 0xff])
    #expect(iter == 3 + MemoryLayout<UInt64>.size)

    var array32: [UInt32] = [0, 0]
    array32.withUnsafeMutableBytes { raw in
      let next = Bits.storeUnaligned(UInt32(123), raw.baseAddress!)
      #expect(next == raw.baseAddress! + 4)
    }
    #expect(array32 == [123, 0])
  }

  @Test func byteSwap() {
    #expect(Bits.byteswap(UInt8(0x37)) == 0x37)
    let u16: UInt16 = 0x1234
    #expect(Bits.byteswap(u16) == 0x3412)
    #expect(Bits.byteswap(Bits.byteswap(u16)) == u16)
    let i16: Int16 = 0x1234
    #expect(Bits.byteswap(i16) == 0x3412)
    let u32: UInt32 = 0x1234_5678
    #expect(Bits.byteswap(u32) == 0x7856_3412)
    #expect(Bits.byteswap(Bits.byteswap(u32)) == u32)
    let i32: Int32 = 0x1234_5678
    #expect(Bits.byteswap(i32) == 0x7856_3412)
    let u64: UInt64 = 0x1234_5678_90ab_cdef
    #expect(Bits.byteswap(u64) == 0xefcd_ab90_7856_3412)
    #expect(Bits.byteswap(Bits.byteswap(u64)) == u64)
    let i64: Int64 = 0x1234_5678_90ab_cdef
    #expect(Bits.byteswap(i64) == Int64(bitPattern: 0xefcd_ab90_7856_3412))
  }

  struct Data {
    var a: UInt32
    var b: UInt32
    var c: UInt16
    var d: UInt16
  }

  @Test func makeAlignedConstSpan() {
    #expect(MemoryLayout<Data>.size == 12)
    #expect(MemoryLayout<Data>.offset(of: \Data.a)! % MemoryLayout<UInt32>.alignment == 0)
    #expect(MemoryLayout<Data>.offset(of: \Data.b)! % MemoryLayout<UInt32>.alignment == 0)
    #expect(MemoryLayout<Data>.offset(of: \Data.c)! % MemoryLayout<UInt16>.alignment == 0)
    #expect(MemoryLayout<Data>.offset(of: \Data.d)! % MemoryLayout<UInt16>.alignment == 0)

    var input: [Data] = []
    for i in 0..<4 {
      let i32 = UInt32(i)
      input.append(Data(a: 4 * i32, b: 4 * i32 + 1, c: UInt16(4 * i + 2), d: UInt16(4 * i + 3)))
    }

    // An aligned copy of the bytes.
    let buf = UnsafeMutableRawBufferPointer.allocate(
      byteCount: MemoryLayout<Data>.stride * input.count, alignment: 16)
    defer { buf.deallocate() }
    input.withUnsafeBytes { buf.copyMemory(from: $0) }
    let s = UnsafeRawBufferPointer(buf)
    func sub(_ pos: Int, _ len: Int) -> UnsafeRawBufferPointer {
      UnsafeRawBufferPointer(rebasing: s[pos..<min(pos + len, s.count)])
    }

    // Unaligned.
    #expect(Bits.makeAlignedConstSpan(sub(1, 12), as: Data.self).isEmpty)
    #expect(Bits.makeAlignedConstSpan(sub(2, 12), as: Data.self).isEmpty)

    // Invalid size
    #expect(Bits.makeAlignedConstSpan(sub(1, 10), as: Data.self).isEmpty)

    // Too short.
    #expect(Bits.makeAlignedConstSpan(sub(0, 2), as: Data.self).isEmpty)

    // Aligned
    #expect(!Bits.makeAlignedConstSpan(sub(12, 12), as: Data.self).isEmpty)
    #expect(!Bits.makeAlignedConstSpan(sub(12, 24), as: Data.self).isEmpty)
    #expect(!Bits.makeAlignedConstSpan(sub(24, 24), as: Data.self).isEmpty)

    let output = Bits.makeAlignedConstSpan(s, as: Data.self)
    #expect(!output.isEmpty)
    #expect(output.count == input.count)
    for i in 0..<output.count {
      #expect(input[i].a == output[i].a)
      #expect(input[i].b == output[i].b)
      #expect(input[i].c == output[i].c)
      #expect(input[i].d == output[i].d)
    }
  }
}
