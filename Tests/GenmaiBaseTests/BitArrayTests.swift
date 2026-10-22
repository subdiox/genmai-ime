// Port of mozc/src/base/container/bitarray_test.cc (3.35.6354).

import Testing

@testable import GenmaiBase

@Suite struct BitArrayTest {
  @Test func bitArraySizeTest() {
    do {
      let array = BitArray(0)
      #expect(array.size == 0)
      #expect(array.arraySize == 4)
    }
    do {
      let array = BitArray(5)
      #expect(array.size == 5)
      #expect(array.arraySize == 4)
    }
    do {
      let array = BitArray(32)
      #expect(array.size == 32)
      #expect(array.arraySize == 8)
    }
    do {
      let array = BitArray(100)
      #expect(array.size == 100)
      #expect(array.arraySize == 16)
    }
  }

  @Test func bitArrayTest() {
    let kBitArraySize = [1, 2, 10, 32, 64, 100, 1000, 1024, 10000]
    var gen = SystemRandomNumberGenerator()

    for size in kBitArraySize {
      // set array
      var array = BitArray(size)
      #expect(array.size == size)
      var target = [Int](repeating: 0, count: size)
      for j in 0..<size {
        let v = Bool.random(using: &gen)
        if v {
          target[j] = 1
          array.set(j)
        } else {
          target[j] = 0
          array.clear(j)
        }
      }

      let data = array.bytes
      #expect(data.count == array.arraySize)

      // verify
      for j in 0..<size {
        #expect(BitArray.getValue(data, j) == (target[j] != 0))
        #expect(array.get(j) == (target[j] != 0))
      }

      var array2 = BitArray(0)
      array.swap(&array2)
      #expect(array2.bytes == data)
      #expect(array.size == 0)
      #expect(array2.size == size)
    }
  }
}
