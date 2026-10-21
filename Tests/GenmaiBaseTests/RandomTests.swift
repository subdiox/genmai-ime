// Port of mozc/src/base/random_test.cc (3.35.6354).

import Testing
@testable import GenmaiBase

private func containsSameValues<C: Collection>(_ buf: C) -> Bool where C.Element: Equatable {
  let first = buf.first!
  return buf.allSatisfy { $0 == first }
}

@Suite struct TestRandom {
  @Test func seed() {
    do {
      var r0 = Random(seed: 0)
      var r1 = Random(seed: 0)
      #expect(r0.utf8String(100, 0, 256) == r1.utf8String(100, 0, 256))
    }
    do {
      var r0 = Random(seed: 0)
      var r1 = Random(seed: 0)
      #expect(r0.byteString(100) == r1.byteString(100))
    }
  }

  @Test func urbg() {
    var r = Random()
    let buf = (0..<1024).map { _ in UInt32.random(in: .min ... .max, using: &r) }
    #expect(!containsSameValues(buf))
  }

  @Test func utf8String() {
    var r = Random()
    #expect(r.utf8String(0, 0, 0).isEmpty)

    // Sufficiently large so it's highly unlikely to have only one value.
    let len = 1024
    let lo: UInt32 = 0x1000
    let hi: UInt32 = 0x7000
    let s = r.utf8String(len, lo, hi)
    let codepoints = s.unicodeScalars.map(\.value)
    #expect(codepoints.count == len)
    #expect(!containsSameValues(codepoints))
    #expect(codepoints.allSatisfy { lo <= $0 && $0 <= hi })
  }

  @Test func utf8StringRandomLen() {
    var r = Random()
    let lo: UInt32 = 0x1000
    let hi: UInt32 = 0x7000
    for len in [1, 2, 100] {
      let s = r.utf8StringRandomLen(len, lo, hi)
      let outLen = s.unicodeScalars.count
      #expect(outLen >= 1)
      #expect(outLen <= len)
    }

    let kCount = 100
    let kLenMax = 256
    var resultSizes: [Int] = []
    for _ in 0..<kCount {
      let s = r.utf8StringRandomLen(kLenMax, lo, hi)
      let len = s.unicodeScalars.count
      #expect(len >= 1)
      #expect(len <= kLenMax)
      resultSizes.append(len)
    }
    #expect(resultSizes.contains { $0 < kLenMax })
  }

  @Test func byteString() {
    var r = Random()
    #expect(r.byteString(0).isEmpty)
    let size = 1024
    let s = r.byteString(size)
    #expect(s.count == size)
    #expect(!containsSameValues(s))
  }
}
