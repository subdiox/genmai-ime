// Port of mozc/src/base/container/flat_set_test.cc (3.35.6354).
//
// FlatSetDeathTest (duplicate entries hit LOG(FATAL)) is not ported: Swift
// Testing cannot test fatalError in-process.

import Testing

@testable import GenmaiBase

@Suite struct FlatSetTest {
  @Test func contains() {
    let kSet = FlatSet<String>(byteOrdered: [
      "one",
      "three",
      "five",
    ])

    #expect(!kSet.contains("zero"))
    #expect(kSet.contains("one"))
    #expect(!kSet.contains("two"))
    #expect(kSet.contains("three"))
    #expect(!kSet.contains("four"))
    #expect(kSet.contains("five"))
    #expect(!kSet.contains("six"))
  }

  @Test func customCompare() {
    let kSet = FlatSet<String>(
      [
        "one",
        "three",
        "five",
      ], by: { $0.compareBytes($1) > 0 })

    #expect(!kSet.contains("zero"))
    #expect(kSet.contains("one"))
    #expect(!kSet.contains("two"))
    #expect(kSet.contains("three"))
    #expect(!kSet.contains("four"))
    #expect(kSet.contains("five"))
    #expect(!kSet.contains("six"))
  }

  @Test func singleElement() {
    let kSet = FlatSet<Int>([42])

    #expect(kSet.contains(42))
    #expect(!kSet.contains(0))
  }
}
