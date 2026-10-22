// Port of mozc/src/converter/debug_util_test.cc (3.35.6354).

import Testing

@testable import GenmaiCore

@Suite struct DebugUtilTests {
  @Test func dumpNodesEmpty() {
    let lattice = Lattice()
    lattice.setKey("")
    let dump = dumpNodes(lattice)
    #expect(!dump.isEmpty)
    // The header and BOS node should be output.
    #expect(dump.contains("BOS"))
  }

  @Test func dumpNodesSimple() {
    let lattice = Lattice()
    lattice.setKey("a")

    let n1 = lattice.newNode()
    n1.key = "a"
    n1.value = "A"
    n1.beginPos = 0
    n1.endPos = 1
    lattice.insert(0, n1)

    let dump = dumpNodes(lattice)
    #expect(!dump.isEmpty)
    #expect(dump.contains("BOS"))
    #expect(dump.contains("\ta\tA\t"))
  }

  // Swift-only: exact format and id assignment order.
  @Test func dumpNodesFormat() {
    let lattice = Lattice()
    lattice.setKey("a")
    let n1 = lattice.newNode()
    n1.key = "a"
    n1.value = "A"
    lattice.insert(0, n1)
    n1.prev = lattice.bosNode
    n1.next = lattice.eosNode
    let expected = """
      id\tkey\tvalue\tbegin_pos\tend_pos\tlid\trid\twcost\tcost\tbnext\tenext\tprev\tnext
      1\t\tBOS\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0
      2\t\tPOS\t0\t0\t0\t0\t0\t0\t3\t0\t0\t4
      4\t\tPOS\t1\t1\t0\t0\t0\t0\t5\t0\t0\t0
      3\ta\tA\t0\t1\t0\t0\t0\t0\t0\t0\t1\t5
      5\t\tEOS\t1\t1\t0\t0\t0\t0\t0\t0\t0\t0

      """
    #expect(dumpNodes(lattice) == expected)
  }
}
