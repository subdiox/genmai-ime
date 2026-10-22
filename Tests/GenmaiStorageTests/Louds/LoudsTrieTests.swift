// Port of mozc/src/storage/louds/louds_trie_test.cc (3.35.6354).

import Testing

@testable import GenmaiStorage

private struct CallbackArgs {
  var key: [UInt8]
  var prefixLen: Int
  var trie: LoudsTrie
  var node: LoudsTrie.Node
}

private func traverse(_ trie: LoudsTrie, _ key: [UInt8]) -> LoudsTrie.Node {
  var node = LoudsTrie.Node()
  _ = trie.traverse(key, &node)
  return node
}

struct LoudsTrieCacheSizeParam: Sendable, CustomTestStringConvertible {
  var loudsLb0CacheSize: Int
  var loudsLb1CacheSize: Int
  var loudsSelect0CacheSize: Int
  var loudsSelect1CacheSize: Int
  var termvecLb1CacheSize: Int

  init(_ lb0: Int, _ lb1: Int, _ s0: Int, _ s1: Int, _ termLb1: Int) {
    loudsLb0CacheSize = lb0
    loudsLb1CacheSize = lb1
    loudsSelect0CacheSize = s0
    loudsSelect1CacheSize = s1
    termvecLb1CacheSize = termLb1
  }

  var testDescription: String {
    "(\(loudsLb0CacheSize), \(loudsLb1CacheSize), \(loudsSelect0CacheSize), "
      + "\(loudsSelect1CacheSize), \(termvecLb1CacheSize))"
  }
}

private let kParams: [LoudsTrieCacheSizeParam] = {
  var params: [LoudsTrieCacheSizeParam] = []
  for a in 0...1 {
    for b in 0...1 {
      for c in 0...1 {
        for d in 0...1 {
          for e in 0...1 {
            params.append(.init(a, b, c, d, e))
          }
        }
      }
    }
  }
  params.append(.init(2, 2, 2, 2, 2))
  params.append(.init(8, 8, 8, 8, 8))
  params.append(.init(1024, 1024, 1024, 1024, 1024))
  return params
}()

private func openTrie(_ builder: LoudsTrieBuilder, _ param: LoudsTrieCacheSizeParam) -> (
  LoudsTrie, ImageBuffer
) {
  let image = ImageBuffer(builder.image)
  let trie = LoudsTrie()
  trie.open(
    image.pointer, param.loudsLb0CacheSize, param.loudsLb1CacheSize,
    param.loudsSelect0CacheSize, param.loudsSelect1CacheSize, param.termvecLb1CacheSize)
  return (trie, image)
}

@Suite struct LoudsTrieTest {
  @Test(arguments: kParams)
  func nodeBasedApis(_ param: LoudsTrieCacheSizeParam) throws {
    // Create the following trie (* stands for non-terminal nodes):
    //
    //        *          Key   ID
    //     a/   \b       ---------
    //    0      *       a     0
    //  a/ \b     \d     aa    1
    //  1   2      3     ab    2
    //    c/ \d          bd    3
    //    *   4          abd   4
    //   d|              abcd  5
    //    5
    let builder = LoudsTrieBuilder()
    builder.add("a")
    builder.add("aa")
    builder.add("ab")
    builder.add("abcd")
    builder.add("abd")
    builder.add("bd")
    builder.build()

    let (trie, image) = openTrie(builder, param)
    defer { withExtendedLifetime(image) {} }

    // Walk the trie in BFS order and check properties at each node.

    // Root node
    let root = LoudsTrie.Node()
    try #require(trie.isValidNode(root))
    #expect(!trie.isTerminalNode(root))
    do {
      var node = LoudsTrie.Node()
      #expect(trie.traverse(bytes(""), &node))
      #expect(node == root)
    }

    // There's no right sibling for root.
    #expect(!trie.isValidNode(LoudsTrie.moveToNextSibling(root)))

    // Terminal node for "a".
    let nodeA = trie.moveToFirstChild(root)
    try #require(trie.isValidNode(nodeA))
    try #require(trie.isTerminalNode(nodeA))
    #expect(trie.getEdgeLabelToParentNode(nodeA) == UInt8(ascii: "a"))
    #expect(trie.getKeyIdOfTerminalNode(nodeA) == 0)
    #expect(trie.getTerminalNodeFromKeyId(0) == nodeA)
    #expect(trie.restoreKeyString(keyId: 0) == bytes("a"))
    do {
      var node = LoudsTrie.Node()
      #expect(trie.moveToChildByLabel(UInt8(ascii: "a"), &node))
      #expect(node == nodeA)
    }
    do {
      var node = LoudsTrie.Node()
      #expect(trie.traverse(bytes("a"), &node))
      #expect(node == nodeA)
    }

    // Non-terminal node for "b".
    let nodeB = LoudsTrie.moveToNextSibling(nodeA)
    try #require(trie.isValidNode(nodeB))
    #expect(!trie.isTerminalNode(nodeB))
    #expect(trie.getEdgeLabelToParentNode(nodeB) == UInt8(ascii: "b"))
    do {
      var node = LoudsTrie.Node()
      #expect(trie.moveToChildByLabel(UInt8(ascii: "b"), &node))
      #expect(node == nodeB)
    }
    do {
      var node = LoudsTrie.Node()
      #expect(trie.traverse(bytes("b"), &node))
      #expect(node == nodeB)
    }

    // There's no right sibling for "b".
    #expect(!trie.isValidNode(LoudsTrie.moveToNextSibling(nodeB)))

    // Terminal node (leaf) for "aa".
    let nodeAa = trie.moveToFirstChild(nodeA)
    try #require(trie.isValidNode(nodeAa))
    try #require(trie.isTerminalNode(nodeAa))
    #expect(trie.getEdgeLabelToParentNode(nodeAa) == UInt8(ascii: "a"))
    #expect(trie.getKeyIdOfTerminalNode(nodeAa) == 1)
    #expect(trie.getTerminalNodeFromKeyId(1) == nodeAa)
    #expect(trie.restoreKeyString(keyId: 1) == bytes("aa"))
    do {
      var node = nodeA
      #expect(trie.moveToChildByLabel(UInt8(ascii: "a"), &node))
      #expect(node == nodeAa)
    }
    do {
      var node = LoudsTrie.Node()
      #expect(trie.traverse(bytes("aa"), &node))
      #expect(node == nodeAa)
    }

    // There's no child for "aa".
    #expect(!trie.isValidNode(trie.moveToFirstChild(nodeAa)))

    // Terminal node for "ab".
    let nodeAb = LoudsTrie.moveToNextSibling(nodeAa)
    try #require(trie.isValidNode(nodeAb))
    try #require(trie.isTerminalNode(nodeAb))
    #expect(trie.getEdgeLabelToParentNode(nodeAb) == UInt8(ascii: "b"))
    #expect(trie.getKeyIdOfTerminalNode(nodeAb) == 2)
    #expect(trie.getTerminalNodeFromKeyId(2) == nodeAb)
    #expect(trie.restoreKeyString(keyId: 2) == bytes("ab"))
    do {
      var node = nodeA
      #expect(trie.moveToChildByLabel(UInt8(ascii: "b"), &node))
      #expect(node == nodeAb)
    }
    do {
      var node = LoudsTrie.Node()
      #expect(trie.traverse(bytes("ab"), &node))
      #expect(node == nodeAb)
    }

    // There's no right sibling for "ab".
    #expect(!trie.isValidNode(LoudsTrie.moveToNextSibling(nodeAb)))

    // Terminal node (leaf) for "bd".
    let nodeBd = trie.moveToFirstChild(nodeB)
    try #require(trie.isValidNode(nodeBd))
    try #require(trie.isTerminalNode(nodeBd))
    #expect(trie.getEdgeLabelToParentNode(nodeBd) == UInt8(ascii: "d"))
    #expect(trie.getKeyIdOfTerminalNode(nodeBd) == 3)
    #expect(trie.getTerminalNodeFromKeyId(3) == nodeBd)
    #expect(trie.restoreKeyString(keyId: 3) == bytes("bd"))
    do {
      var node = nodeB
      #expect(trie.moveToChildByLabel(UInt8(ascii: "d"), &node))
      #expect(node == nodeBd)
    }
    do {
      var node = LoudsTrie.Node()
      #expect(trie.traverse(bytes("bd"), &node))
      #expect(node == nodeBd)
    }

    // There is no child nor right sibling for "bd".
    #expect(!trie.isValidNode(trie.moveToFirstChild(nodeBd)))
    #expect(!trie.isValidNode(LoudsTrie.moveToNextSibling(nodeBd)))

    // Non-terminal node for "abc".
    let nodeAbc = trie.moveToFirstChild(nodeAb)
    try #require(trie.isValidNode(nodeAbc))
    #expect(!trie.isTerminalNode(nodeAbc))
    #expect(trie.getEdgeLabelToParentNode(nodeAbc) == UInt8(ascii: "c"))
    do {
      var node = nodeAb
      #expect(trie.moveToChildByLabel(UInt8(ascii: "c"), &node))
      #expect(node == nodeAbc)
    }
    do {
      var node = LoudsTrie.Node()
      #expect(trie.traverse(bytes("abc"), &node))
      #expect(node == nodeAbc)
    }

    // Terminal node (leaf) for "abd".
    let nodeAbd = LoudsTrie.moveToNextSibling(nodeAbc)
    try #require(trie.isValidNode(nodeAbd))
    try #require(trie.isTerminalNode(nodeAbd))
    #expect(trie.getEdgeLabelToParentNode(nodeAbd) == UInt8(ascii: "d"))
    #expect(trie.getKeyIdOfTerminalNode(nodeAbd) == 4)
    #expect(trie.getTerminalNodeFromKeyId(4) == nodeAbd)
    #expect(trie.restoreKeyString(keyId: 4) == bytes("abd"))
    do {
      var node = nodeAb
      #expect(trie.moveToChildByLabel(UInt8(ascii: "d"), &node))
      #expect(node == nodeAbd)
    }
    do {
      var node = LoudsTrie.Node()
      #expect(trie.traverse(bytes("abd"), &node))
      #expect(node == nodeAbd)
    }

    // There is no child nor right sibling for "abd".
    #expect(!trie.isValidNode(trie.moveToFirstChild(nodeAbd)))
    #expect(!trie.isValidNode(LoudsTrie.moveToNextSibling(nodeAbd)))

    // Terminal node (leaf) for "abcd".
    let nodeAbcd = trie.moveToFirstChild(nodeAbc)
    try #require(trie.isValidNode(nodeAbcd))
    try #require(trie.isTerminalNode(nodeAbcd))
    #expect(trie.getEdgeLabelToParentNode(nodeAbcd) == UInt8(ascii: "d"))
    #expect(trie.getKeyIdOfTerminalNode(nodeAbcd) == 5)
    #expect(trie.getTerminalNodeFromKeyId(5) == nodeAbcd)
    #expect(trie.restoreKeyString(keyId: 5) == bytes("abcd"))
    do {
      var node = nodeAbc
      #expect(trie.moveToChildByLabel(UInt8(ascii: "d"), &node))
      #expect(node == nodeAbcd)
    }
    do {
      var node = LoudsTrie.Node()
      #expect(trie.traverse(bytes("abcd"), &node))
      #expect(node == nodeAbcd)
    }

    // There is no child nor right sibling for "abcd".
    #expect(!trie.isValidNode(trie.moveToFirstChild(nodeAbcd)))
    #expect(!trie.isValidNode(LoudsTrie.moveToNextSibling(nodeAbcd)))

    // Try moving to non-existing nodes by a label.
    do {
      var node = LoudsTrie.Node()
      #expect(!trie.moveToChildByLabel(UInt8(ascii: "x"), &node))
      #expect(!trie.isValidNode(node))
    }

    // Traverse for some non-existing keys.
    do {
      var node = LoudsTrie.Node()
      #expect(!trie.traverse(bytes("x"), &node))
      #expect(!trie.traverse(bytes("xyz"), &node))
    }
  }

  @Test(arguments: kParams)
  func hasKey(_ param: LoudsTrieCacheSizeParam) {
    let builder = LoudsTrieBuilder()
    builder.add("a")
    builder.add("abc")
    builder.add("abcd")
    builder.add("ae")
    builder.add("aecd")
    builder.add("b")
    builder.add("bcx")
    builder.build()

    let (trie, image) = openTrie(builder, param)
    defer { withExtendedLifetime(image) {} }

    #expect(trie.hasKey("a".utf8))
    #expect(trie.hasKey("abc".utf8))
    #expect(trie.hasKey("abcd".utf8))
    #expect(trie.hasKey("ae".utf8))
    #expect(trie.hasKey("aecd".utf8))
    #expect(trie.hasKey("b".utf8))
    #expect(trie.hasKey("bcx".utf8))
    #expect(!trie.hasKey("".utf8))
    #expect(!trie.hasKey("ab".utf8))
    #expect(!trie.hasKey("aa".utf8))
    #expect(!trie.hasKey("aec".utf8))
    #expect(!trie.hasKey("aecx".utf8))
    #expect(!trie.hasKey("aecdf".utf8))
    #expect(!trie.hasKey("abcdefghi".utf8))
    #expect(!trie.hasKey("bc".utf8))
    #expect(!trie.hasKey("bca".utf8))
    #expect(!trie.hasKey("bcxyz".utf8))
  }

  // TEST(LoudsTrieTest, ExactSearch) in C++ (not parameterized).
  @Test func exactSearch() {
    let builder = LoudsTrieBuilder()
    builder.add("a")
    builder.add("abc")
    builder.add("abcd")
    builder.add("ae")
    builder.add("aecd")
    builder.add("b")
    builder.add("bcx")

    builder.build()
    let image = ImageBuffer(builder.image)
    let trie = LoudsTrie()
    trie.open(image.pointer)

    #expect(trie.exactSearch("a".utf8) == builder.getId("a"))
    #expect(trie.exactSearch("abc".utf8) == builder.getId("abc"))
    #expect(trie.exactSearch("abcd".utf8) == builder.getId("abcd"))
    #expect(trie.exactSearch("ae".utf8) == builder.getId("ae"))
    #expect(trie.exactSearch("aecd".utf8) == builder.getId("aecd"))
    #expect(trie.exactSearch("b".utf8) == builder.getId("b"))
    #expect(trie.exactSearch("bcx".utf8) == builder.getId("bcx"))
    #expect(trie.exactSearch("".utf8) == -1)
    #expect(trie.exactSearch("ab".utf8) == -1)
    #expect(trie.exactSearch("aa".utf8) == -1)
    #expect(trie.exactSearch("aec".utf8) == -1)
    #expect(trie.exactSearch("aecx".utf8) == -1)
    #expect(trie.exactSearch("aecdf".utf8) == -1)
    #expect(trie.exactSearch("abcdefghi".utf8) == -1)
    #expect(trie.exactSearch("bc".utf8) == -1)
    #expect(trie.exactSearch("bca".utf8) == -1)
    #expect(trie.exactSearch("bcxyz".utf8) == -1)
    trie.close()
    withExtendedLifetime(image) {}
  }

  @Test(arguments: kParams)
  func prefixSearch(_ param: LoudsTrieCacheSizeParam) throws {
    let builder = LoudsTrieBuilder()
    builder.add("aa")
    builder.add("ab")
    builder.add("abc")
    builder.add("abcd")
    builder.add("abd")
    builder.add("ebd")
    builder.add([0x01, 0xFF])
    builder.add([0x01, 0xFF, 0xFF])
    builder.build()

    let (trie, image) = openTrie(builder, param)
    defer { withExtendedLifetime(image) {} }

    func run(_ key: [UInt8]) -> [CallbackArgs] {
      var actual: [CallbackArgs] = []
      trie.prefixSearch(key) { key, prefixLen, trie, node in
        actual.append(CallbackArgs(key: key, prefixLen: prefixLen, trie: trie, node: node))
      }
      return actual
    }

    do {
      let kKey = bytes("abc")
      let actual = run(kKey)

      try #require(actual.count == 2)

      // "ab"
      #expect(actual[0].key == kKey)
      #expect(actual[0].prefixLen == 2)
      #expect(actual[0].trie === trie)
      #expect(actual[0].node == traverse(trie, bytes("ab")))

      // "abc"
      #expect(actual[1].key == kKey)
      #expect(actual[1].prefixLen == 3)
      #expect(actual[1].trie === trie)
      #expect(actual[1].node == traverse(trie, bytes("abc")))
    }
    do {
      let kKey = bytes("abxxxxxxx")
      let actual = run(kKey)

      try #require(actual.count == 1)

      // "ab"
      #expect(actual[0].key == kKey)
      #expect(actual[0].prefixLen == 2)
      #expect(actual[0].trie === trie)
      #expect(actual[0].node == traverse(trie, bytes("ab")))
    }
    do {
      // Make sure that it works for non-ascii characters too.
      let kKey: [UInt8] = [0x01, 0xFF, 0xFF]
      let actual = run(kKey)

      try #require(actual.count == 2)

      // "\x01\xFF"
      #expect(actual[0].key == kKey)
      #expect(actual[0].prefixLen == 2)
      #expect(actual[0].trie === trie)
      #expect(actual[0].node == traverse(trie, [0x01, 0xFF]))

      // "\x01\xFF\xFF"
      #expect(actual[1].key == kKey)
      #expect(actual[1].prefixLen == 3)
      #expect(actual[1].trie === trie)
      #expect(actual[1].node == traverse(trie, [0x01, 0xFF, 0xFF]))
    }
    do {
      let actual = run(bytes("xyz"))
      #expect(actual.isEmpty)
    }
  }

  @Test(arguments: kParams)
  func restoreKeyString(_ param: LoudsTrieCacheSizeParam) {
    let builder = LoudsTrieBuilder()
    builder.add("aa")
    builder.add("ab")
    builder.add("abc")
    builder.add("abcd")
    builder.add("abcde")
    builder.add("abcdef")
    builder.add("abcea")
    builder.add("abcef")
    builder.add("abd")
    builder.add("ebd")
    builder.build()

    let (trie, image) = openTrie(builder, param)
    defer { withExtendedLifetime(image) {} }

    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: LoudsTrie.kMaxDepth + 1)
    defer { buffer.deallocate() }
    func restore(_ id: Int) -> [UInt8] { Array(trie.restoreKeyString(id, buffer)) }
    for word in ["aa", "ab", "abc", "abcd", "abcde", "abcdef", "abcea", "abcef", "abd", "ebd"] {
      #expect(restore(builder.getId(word)) == bytes(word))
    }
    #expect(restore(-1) == [])
    trie.close()
  }
}
