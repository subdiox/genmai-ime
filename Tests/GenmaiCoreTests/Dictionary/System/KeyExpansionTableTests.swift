// Port of mozc/src/dictionary/system/key_expansion_table_test.cc (3.35.6354).

import Testing

@testable import GenmaiCore

@Suite struct KeyExpansionTableTests {
  @Test func test() {
    var table = KeyExpansionTable()
    table.add("b", "d")
    let a = UInt8(ascii: "a")
    let b = UInt8(ascii: "b")
    let c = UInt8(ascii: "c")
    let d = UInt8(ascii: "d")

    #expect(table.expandKey(a).isHit(a))
    #expect(!table.expandKey(a).isHit(b))
    #expect(!table.expandKey(a).isHit(c))
    #expect(!table.expandKey(a).isHit(d))

    #expect(!table.expandKey(b).isHit(a))
    #expect(table.expandKey(b).isHit(b))
    #expect(!table.expandKey(b).isHit(c))
    #expect(table.expandKey(b).isHit(d))

    #expect(!table.expandKey(c).isHit(a))
    #expect(!table.expandKey(c).isHit(b))
    #expect(table.expandKey(c).isHit(c))
    #expect(!table.expandKey(c).isHit(d))

    #expect(!table.expandKey(d).isHit(a))
    #expect(!table.expandKey(d).isHit(b))
    #expect(!table.expandKey(d).isHit(c))
    #expect(table.expandKey(d).isHit(d))
  }

  // Swift-only: the identity matrix covers all 256 labels.
  @Test func defaultInstanceIsIdentity() {
    let table = KeyExpansionTable.defaultInstance
    for i in 0..<256 {
      for j in [0, 1, 63, 64, 127, 128, 200, 255] {
        #expect(table.expandKey(UInt8(i)).isHit(UInt8(j)) == (i == j))
      }
    }
  }
}
