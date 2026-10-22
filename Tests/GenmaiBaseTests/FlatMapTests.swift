// Port of mozc/src/base/container/flat_map_test.cc (3.35.6354).

import Testing

@testable import GenmaiBase

@Suite struct FlatMapTest {
  @Test func findOrNull() {
    let kMap = FlatMap<Int, String>([
      (1, "one"),
      (3, "three"),
      (5, "five"),
    ])

    #expect(kMap.findOrNull(0) == nil)
    #expect(kMap.findOrNull(1) == "one")
    #expect(kMap.findOrNull(2) == nil)
    #expect(kMap.findOrNull(3) == "three")
    #expect(kMap.findOrNull(4) == nil)
    #expect(kMap.findOrNull(5) == "five")
    #expect(kMap.findOrNull(6) == nil)
  }

  @Test func customCompare() {
    let kMap = FlatMap<Int, String>(
      [
        (1, "one"),
        (3, "three"),
        (5, "five"),
      ], by: { $0 > $1 })

    #expect(kMap.findOrNull(0) == nil)
    #expect(kMap.findOrNull(1) == "one")
    #expect(kMap.findOrNull(2) == nil)
    #expect(kMap.findOrNull(3) == "three")
    #expect(kMap.findOrNull(4) == nil)
    #expect(kMap.findOrNull(5) == "five")
    #expect(kMap.findOrNull(6) == nil)
  }

  @Test func byteOrderedStringKeys() {
    // "が" (U+304C) and "か\u{3099}" are canonically equivalent in Swift but
    // different keys in C++.
    let kMap = FlatMap<String, Int>(byteOrdered: [("が", 1), ("か\u{3099}", 2)])
    #expect(kMap.findOrNull("が") == 1)
    #expect(kMap.findOrNull("か\u{3099}") == 2)
    #expect(kMap.findOrNull("か") == nil)
  }
}
