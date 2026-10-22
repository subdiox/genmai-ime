// Port of mozc/src/storage/louds/louds_test.cc (3.35.6354).

import Testing

@testable import GenmaiStorage

private func makeSequence(_ s: String) -> [UInt8] {
  var seq: [UInt8] = []
  var bitLen = 0
  for c in s.utf8 {
    if bitLen % 8 == 0 {
      seq.append(0)
    }
    switch c {
    case UInt8(ascii: "0"):
      seq[seq.count - 1] >>= 1
    case UInt8(ascii: "1"):
      seq[seq.count - 1] = (seq[seq.count - 1] >> 1) | 0x80
    default:
      continue
    }
    bitLen += 1
  }
  // Add padding so that seq.size() % 4 == 0.
  let reminder = seq.count % 4
  if reminder != 0 {
    for _ in 0..<(4 - reminder) {
      seq.append(0)
    }
  }
  return seq
}

private func expectLeaf(
  _ louds: Louds, _ node: Louds.Node, sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(louds.isValidNode(node), sourceLocation: sourceLocation)
  var tmp = node
  louds.moveToFirstChild(&tmp)
  #expect(!louds.isValidNode(tmp), sourceLocation: sourceLocation)
}

private func expectNoSibling(
  _ louds: Louds, _ node: Louds.Node, sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(louds.isValidNode(node), sourceLocation: sourceLocation)
  var tmp = node
  Louds.moveToNextSibling(&tmp)
  #expect(!louds.isValidNode(tmp), sourceLocation: sourceLocation)
}

struct LoudsCacheSizeParam: Sendable, CustomTestStringConvertible {
  var bitvecLb0CacheSize: Int
  var bitvecLb1CacheSize: Int
  var select0CacheSize: Int
  var select1CacheSize: Int

  init(_ lb0: Int, _ lb1: Int, _ s0: Int, _ s1: Int) {
    bitvecLb0CacheSize = lb0
    bitvecLb1CacheSize = lb1
    select0CacheSize = s0
    select1CacheSize = s1
  }

  var testDescription: String {
    "(\(bitvecLb0CacheSize), \(bitvecLb1CacheSize), \(select0CacheSize), \(select1CacheSize))"
  }
}

private let kLoudsParams: [LoudsCacheSizeParam] = [
  .init(0, 0, 0, 0), .init(0, 0, 0, 1), .init(0, 0, 1, 0), .init(0, 0, 1, 1),
  .init(0, 1, 0, 0), .init(0, 1, 0, 1), .init(0, 1, 1, 0), .init(0, 1, 1, 1),
  .init(1, 0, 0, 0), .init(1, 0, 0, 1), .init(1, 0, 1, 0), .init(1, 0, 1, 1),
  .init(1, 1, 0, 0), .init(1, 1, 0, 1), .init(1, 1, 1, 0), .init(1, 1, 1, 1),
  .init(2, 2, 2, 2), .init(8, 8, 8, 8), .init(1024, 1024, 1024, 1024),
]

@Suite struct LoudsTest {
  @Test(arguments: kLoudsParams)
  func basic(_ param: LoudsCacheSizeParam) {
    // Test with the trie illustrated in Louds.swift.
    let kSeq = ImageBuffer(makeSequence("10 110 0 110 0 0"))
    var louds = Louds()
    louds.initialize(
      kSeq.pointer, kSeq.count, param.bitvecLb0CacheSize, param.bitvecLb1CacheSize,
      param.select0CacheSize, param.select1CacheSize)

    // root -> 2 -> 3 -> 4 -> 5
    do {
      var node = Louds.Node()
      #expect(Louds.isRoot(node))
      expectNoSibling(louds, node)
      #expect(node.nodeId == 1)

      louds.moveToFirstChild(&node)
      expectLeaf(louds, node)
      #expect(node.nodeId == 2)

      Louds.moveToNextSibling(&node)
      expectNoSibling(louds, node)
      #expect(node.nodeId == 3)

      louds.moveToFirstChild(&node)
      expectLeaf(louds, node)
      #expect(node.nodeId == 4)

      Louds.moveToNextSibling(&node)
      expectLeaf(louds, node)
      expectNoSibling(louds, node)
      #expect(node.nodeId == 5)
    }

    // 4 -> 3 -> 1
    do {
      var node = Louds.Node()
      louds.initNodeFromNodeId(4, &node)
      expectLeaf(louds, node)
      #expect(node.nodeId == 4)

      louds.moveToParent(&node)
      #expect(node.nodeId == 3)

      louds.moveToParent(&node)
      #expect(node.nodeId == 1)
      #expect(Louds.isRoot(node))
    }
    withExtendedLifetime(kSeq) {}
  }
}
