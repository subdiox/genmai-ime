// Port of mozc/src/converter/lattice_test.cc (3.35.6354).

import Testing
@testable import GenmaiCore

@Suite struct LatticeTests {
  @Test func latticeTest() {
    let lattice = Lattice()
    #expect(lattice.key == "")
    #expect(!lattice.hasLattice)

    lattice.setKey("this is a test")
    #expect(lattice.hasLattice)

    #expect(lattice.bosNode.nodeType == .bosNode)
    #expect(lattice.eosNode.nodeType == .eosNode)
    #expect(lattice.eosNode.beginPos == 14)
  }

  @Test func newNodeTest() {
    let lattice = Lattice()
    let node = lattice.newNode()
    #expect(node.lid == 0)
    #expect(node.rid == 0)
  }

  @Test func insertTest() {
    let lattice = Lattice()
    lattice.setKey("test")

    do {
      let node = lattice.newNode()
      node.value = "ho"
      node.key = "es"
      lattice.insert(1, node)

      #expect(lattice.beginNodes(1).first === node)
      #expect(lattice.endNodes(3).first === node)
    }
    do {
      let node = lattice.newNode()
      node.value = "o"
      node.key = "s"
      lattice.insert(2, node)

      #expect(lattice.beginNodes(2).first === node)
      #expect(lattice.endNodes(3).count == 2)
    }
  }

  // Swift-only: the allocator reuses nodes in allocation order after setKey.
  @Test func nodeAllocatorReuse() {
    let lattice = Lattice()
    lattice.setKey("ab")
    let bos = lattice.bosNode
    let n = lattice.newNode()
    n.key = "a"
    n.wcost = 10
    #expect(lattice.nodeAllocator.allocatedCount == 3)
    lattice.setKey("abc")
    #expect(lattice.bosNode === bos)
    #expect(lattice.nodeAllocator.allocatedCount == 2)
    let m = lattice.newNode()
    #expect(m === n)
    #expect(m.key == "" && m.wcost == 0)
  }

  @Test func debugStringTest() {
    let lattice = Lattice()
    #expect(lattice.debugString() == "")
    lattice.setKey("a")
    let node = lattice.newNode()
    node.key = "a"
    node.value = "A"
    node.lid = 1
    node.rid = 2
    node.wcost = 100
    lattice.insert(0, node)
    node.cost = 150
    node.prev = lattice.bosNode
    lattice.eosNode.prev = node
    lattice.eosNode.cost = 200
    #expect(
      lattice.debugString()
        == "[con:0][lid:0]\"BOS\"[wcost:0][cost:0][rid:0][con:50][lid:1]\"A\"[wcost:100][cost:150][rid:2][con:50][lid:0]\"EOS\"[wcost:0][cost:200][rid:0]"
    )
  }

  @Test func scopedInserter() {
    let lattice = Lattice()
    lattice.setKey("ab")
    let node = lattice.newNode()
    node.key = "a"
    lattice.withNodeInserter { inserter in
      #expect(!inserter.isInserted)
      inserter.insert(0, node)
      #expect(inserter.isInserted)
      #expect(lattice.beginNodes(0).isEmpty)
    }
    #expect(lattice.beginNodes(0).first === node)
  }
}
