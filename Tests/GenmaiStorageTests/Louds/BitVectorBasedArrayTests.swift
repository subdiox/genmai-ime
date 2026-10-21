// Port of mozc/src/storage/louds/bit_vector_based_array_test.cc (3.35.6354).

import Testing
@testable import GenmaiStorage

@Suite struct BitVectorBasedArrayTest {
  @Test func get() {
    let kTestData: [(element: [UInt8], expectedElement: [UInt8])] = [
      ([], [0, 0, 0, 0]),
      (bytes("a"), bytes("a") + [0, 0, 0]),
      (bytes("b"), bytes("b") + [0, 0, 0]),
      (bytes("c"), bytes("c") + [0, 0, 0]),
      (bytes("d"), bytes("d") + [0, 0, 0]),
      (bytes("abcdefg"), bytes("abcdefg") + [0]),
      (bytes("mozc"), bytes("mozc")),
      (bytes("google-japanese-input"), bytes("google-japanese-input") + [0]),
      (bytes("abcdefg"), bytes("abcdefg") + [0]),  // Test for storing a same element.
      (bytes("testdata"), bytes("testdata")),
      (bytes("another-test-data"), bytes("another-test-data") + [0]),
    ]

    let builder = BitVectorBasedArrayBuilder()
    for data in kTestData {
      builder.add(data.element)
    }
    builder.setSize(4, 2)
    builder.build()

    let image = ImageBuffer(builder.image)
    var array = BitVectorBasedArray()
    array.open(image.pointer)
    for (i, data) in kTestData.enumerated() {
      let result = array.get(i)
      #expect(Array(result) == data.expectedElement)
    }

    array.close()
  }
}
