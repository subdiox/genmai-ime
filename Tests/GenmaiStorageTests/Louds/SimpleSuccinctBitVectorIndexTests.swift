// Port of mozc/src/storage/louds/simple_succinct_bit_vector_index_test.cc
// (3.35.6354).

import Foundation
import Testing

@testable import GenmaiStorage

struct BitVectorCacheSizeParam: Sendable, CustomTestStringConvertible {
  var first: Int
  var second: Int
  init(_ first: Int, _ second: Int) {
    self.first = first
    self.second = second
  }
  var testDescription: String { "(\(first), \(second))" }
}

private let kParams: [BitVectorCacheSizeParam] = [
  .init(0, 0), .init(0, 1), .init(1, 0), .init(1, 1), .init(2, 2), .init(8, 8), .init(1024, 1024),
]

@Suite struct SimpleSuccinctBitVectorIndexTest {
  @Test(arguments: kParams)
  func rank(_ param: BitVectorCacheSizeParam) {
    let kData = Data([0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0xFF])
    var bitVector = SimpleSuccinctBitVectorIndex()

    bitVector.initialize(kData, 8, param.first, param.second)
    #expect(bitVector.num0Bits == 32)
    #expect(bitVector.num1Bits == 32)
    #expect(bitVector.rank0(0) == 0)
    #expect(bitVector.rank1(0) == 0)

    for i in 1...16 {
      #expect(bitVector.rank0(i) == i, "\(i)")
      #expect(bitVector.rank1(i) == 0, "\(i)")
    }

    for i in 17...32 {
      #expect(bitVector.rank0(i) == 16, "\(i)")
      #expect(bitVector.rank1(i) == i - 16, "\(i)")
    }

    for i in 33...48 {
      #expect(bitVector.rank0(i) == i - 16, "\(i)")
      #expect(bitVector.rank1(i) == 16, "\(i)")
    }

    for i in 49...64 {
      #expect(bitVector.rank0(i) == 32, "\(i)")
      #expect(bitVector.rank1(i) == i - 32, "\(i)")
    }
  }

  @Test(arguments: kParams)
  func select(_ param: BitVectorCacheSizeParam) {
    let kData = Data([0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0xFF])
    var bitVector = SimpleSuccinctBitVectorIndex()

    bitVector.initialize(kData, 8, param.first, param.second)
    #expect(bitVector.num0Bits == 32)
    #expect(bitVector.num1Bits == 32)

    for i in 1...16 {
      #expect(bitVector.select0(i) == i - 1, "\(i)")
    }
    for i in 17...32 {
      #expect(bitVector.select0(i) == i + 15, "\(i)")
    }
    for i in 1...16 {
      #expect(bitVector.select1(i) == i + 15, "\(i)")
    }
    for i in 17...32 {
      #expect(bitVector.select1(i) == i + 31, "\(i)")
    }
  }

  @Test(arguments: kParams)
  func pattern1(_ param: BitVectorCacheSizeParam) {
    // Repeat the bit pattern '0b10101010'.
    let data = Data([UInt8](repeating: 0xAA, count: 1024))

    var bitVector = SimpleSuccinctBitVectorIndex()
    bitVector.initialize(data, data.count, param.first, param.second)
    #expect(bitVector.num0Bits == 4 * 1024)
    #expect(bitVector.num1Bits == 4 * 1024)

    // Collect mismatches instead of emitting thousands of expectations.
    var failures: [String] = []
    func check(_ actual: Int, _ expected: Int, _ what: String) {
      if actual != expected { failures.append("\(what): \(actual) != \(expected)") }
    }
    for i in 0..<1024 {
      check(bitVector.rank0(i * 8), i * 4, "rank0 \(i)")
      check(bitVector.rank0(i * 8 + 1), i * 4 + 1, "rank0 \(i)")
      check(bitVector.rank0(i * 8 + 2), i * 4 + 1, "rank0 \(i)")
      check(bitVector.rank0(i * 8 + 3), i * 4 + 2, "rank0 \(i)")
      check(bitVector.rank0(i * 8 + 4), i * 4 + 2, "rank0 \(i)")
      check(bitVector.rank0(i * 8 + 5), i * 4 + 3, "rank0 \(i)")
      check(bitVector.rank0(i * 8 + 6), i * 4 + 3, "rank0 \(i)")
      check(bitVector.rank0(i * 8 + 7), i * 4 + 4, "rank0 \(i)")

      check(bitVector.rank1(i * 8), i * 4, "rank1 \(i)")
      check(bitVector.rank1(i * 8 + 1), i * 4, "rank1 \(i)")
      check(bitVector.rank1(i * 8 + 2), i * 4 + 1, "rank1 \(i)")
      check(bitVector.rank1(i * 8 + 3), i * 4 + 1, "rank1 \(i)")
      check(bitVector.rank1(i * 8 + 4), i * 4 + 2, "rank1 \(i)")
      check(bitVector.rank1(i * 8 + 5), i * 4 + 2, "rank1 \(i)")
      check(bitVector.rank1(i * 8 + 6), i * 4 + 3, "rank1 \(i)")
      check(bitVector.rank1(i * 8 + 7), i * 4 + 3, "rank1 \(i)")
    }

    for i in 0..<(1024 * 4) {
      check(bitVector.select0(i + 1), i * 2, "select0 \(i)")
      check(bitVector.select1(i + 1), i * 2 + 1, "select1 \(i)")
    }
    #expect(failures.isEmpty, "\(failures.prefix(10))")
  }

  @Test(arguments: kParams)
  func pattern2(_ param: BitVectorCacheSizeParam) {
    // Repeat the bit pattern '0b11001100'.
    let data = Data([UInt8](repeating: 0xCC, count: 1024))

    var bitVector = SimpleSuccinctBitVectorIndex()
    bitVector.initialize(data, data.count, param.first, param.second)
    #expect(bitVector.num0Bits == 4 * 1024)
    #expect(bitVector.num1Bits == 4 * 1024)

    var failures: [String] = []
    func check(_ actual: Int, _ expected: Int, _ what: String) {
      if actual != expected { failures.append("\(what): \(actual) != \(expected)") }
    }
    for i in 0..<1024 {
      check(bitVector.rank0(i * 8), i * 4, "rank0 \(i)")
      check(bitVector.rank0(i * 8 + 1), i * 4 + 1, "rank0 \(i)")
      check(bitVector.rank0(i * 8 + 2), i * 4 + 2, "rank0 \(i)")
      check(bitVector.rank0(i * 8 + 3), i * 4 + 2, "rank0 \(i)")
      check(bitVector.rank0(i * 8 + 4), i * 4 + 2, "rank0 \(i)")
      check(bitVector.rank0(i * 8 + 5), i * 4 + 3, "rank0 \(i)")
      check(bitVector.rank0(i * 8 + 6), i * 4 + 4, "rank0 \(i)")
      check(bitVector.rank0(i * 8 + 7), i * 4 + 4, "rank0 \(i)")

      check(bitVector.rank1(i * 8), i * 4, "rank1 \(i)")
      check(bitVector.rank1(i * 8 + 1), i * 4, "rank1 \(i)")
      check(bitVector.rank1(i * 8 + 2), i * 4, "rank1 \(i)")
      check(bitVector.rank1(i * 8 + 3), i * 4 + 1, "rank1 \(i)")
      check(bitVector.rank1(i * 8 + 4), i * 4 + 2, "rank1 \(i)")
      check(bitVector.rank1(i * 8 + 5), i * 4 + 2, "rank1 \(i)")
      check(bitVector.rank1(i * 8 + 6), i * 4 + 2, "rank1 \(i)")
      check(bitVector.rank1(i * 8 + 7), i * 4 + 3, "rank1 \(i)")
    }

    for i in 0..<(1024 * 4) {
      check(bitVector.select0(i + 1), (i * 2) - (i % 2), "select0 \(i)")
      check(bitVector.select1(i + 1), (i * 2 + 1) + ((i + 1) % 2), "select1 \(i)")
    }
    #expect(failures.isEmpty, "\(failures.prefix(10))")
  }
}
