// Port of mozc/src/storage/louds/louds_trie.{h,cc} (3.35.6354).
//
// Keys are byte sequences (edge labels are bytes; Mozc's system dictionary
// stores codec-encoded, non-UTF-8 keys). The key-taking APIs are generic over
// `Sequence<UInt8>` / `Collection<UInt8>` (pass `string.utf8` for a String)
// and are @inlinable so callers get specialized code. Node-moving methods take
// the node `inout` (C++ `Node*`), with value-returning overloads as in C++.
//
// The image is an immutable `Data` (typically a slice of a memory-mapped file,
// so nothing is copied). The opened structure is an immutable object held in a
// Mutex; open() / close() replace it. Readers take it once per call.

import Foundation
import GenmaiBase
import Synchronization

/// LOUDS-based trie. A final class (C++ LoudsTrie is non-copyable and is
/// passed by reference, e.g. to the PrefixSearch callback).
public final class LoudsTrie: Sendable {
  /// The max depth of the trie.
  public static let kMaxDepth = 256

  /// This type stores a traversal state.
  public typealias Node = Louds.Node

  /// The opened data structure (immutable).
  @usableFromInline
  final class Structure: Sendable {
    /// Tree structure representation by LOUDS.
    let louds: Louds

    /// Bit-vector to represent whether each node in LOUDS tree is terminal.
    /// This bit vector doesn't include "super root" in the LOUDS.
    /// In other words, id=1 in louds_ corresponds to id=0 in
    /// terminal_bit_vector_, id=10 in louds_ corresponds to id=9 in
    /// terminal_bit_vector_, and so on.
    /// TODO(noriyukit): Simplify the id-mapping by introducing a bit for the
    /// super root in this bit vector.
    let terminalBitVector: SimpleSuccinctBitVectorIndex

    /// A sequence of characters, annotated to each edge.
    /// This array also doesn't have an entry for super root.
    /// In other words, id=2 in louds_ corresponds to edge_character_[1].
    let edgeCharacter: Data

    /// The structure of a trie that is not open.
    static let empty = Structure()

    init(
      louds: Louds = Louds(), terminalBitVector: SimpleSuccinctBitVectorIndex = .init(), edgeCharacter: Data = Data()
    ) {
      self.louds = louds
      self.terminalBitVector = terminalBitVector
      self.edgeCharacter = edgeCharacter
    }

    @inline(__always)
    func edgeLabel(_ node: Node) -> UInt8 {
      edgeCharacter.span[node.nodeId - 1]
    }

    @inline(__always)
    @usableFromInline func isTerminalNode(_ node: Node) -> Bool {
      terminalBitVector.get(node.nodeId - 1) != 0
    }

    @usableFromInline func moveToChildByLabel(_ label: UInt8, _ node: inout Node) -> Bool {
      let edges = edgeCharacter.span
      louds.moveToFirstChild(&node)
      while louds.isValidNode(node) {
        if edges[node.nodeId - 1] == label {
          return true
        }
        Louds.moveToNextSibling(&node)
      }
      return false
    }

    /// The key bytes that reach to |node|.
    func restoreKeyString(_ node: Node) -> [UInt8] {
      // Climb up the trie to the root and collect the labels backward.
      var key: [UInt8] = []
      forEachLabelToRoot(node) { key.append($0) }
      key.reverse()
      return key
    }

    /// Calls `body` with the edge labels from |node| up to the root (the key bytes, last byte first).
    @inline(__always)
    func forEachLabelToRoot(_ node: Node, _ body: (UInt8) -> Void) {
      let edges = edgeCharacter.span
      var node = node
      while !Louds.isRoot(node) {
        body(edges[node.nodeId - 1])
        louds.moveToParent(&node)
      }
    }
  }

  /// The opened structure, replaced by open() / close(). A Mutex rather than an atomic reference:
  /// `AtomicLazyReference` is not specialized across modules and its loads cost a runtime metadata lookup each
  /// (2.7x slower reverse lookups); an uncontended lock is a few nanoseconds.
  private let structure = Mutex(Structure.empty)

  /// The current structure (taken once per operation).
  @usableFromInline
  var current: Structure {
    structure.withLock { $0 }
  }

  private func replaceStructure(_ newStructure: Structure) {
    structure.withLock { $0 = newStructure }
  }

  public init() {}

  /// Opens the binary image and constructs the data structure.  The first four
  /// cache sizes are passed to the underlying LOUDS.  See Louds.swift for more
  /// information of cache size.  The last one is passed to the underlying
  /// terminal bit vector. `image` shares its memory (no copy).
  @discardableResult
  public func open(
    _ image: Data, _ loudsLb0CacheSize: Int = 0, _ loudsLb1CacheSize: Int = 0,
    _ loudsSelect0CacheSize: Int = 0, _ loudsSelect1CacheSize: Int = 0,
    _ termvecLb1CacheSize: Int = 0
  ) -> Bool {
    // Reads a binary image data, which is compatible with rx.
    // The format is as follows:
    // [trie size: little endian 4byte int]
    // [terminal size: little endian 4byte int]
    // [num bits for each character annotated to an edge:
    //  little endian 4 byte int. Currently, this class supports only 8-bits]
    // [edge character image size: little endian 4 byte int]
    // [trie image: "trie size" bytes]
    // [terminal image: "terminal size" bytes]
    // [edge character image: "edge character image size" bytes]
    //
    // Here, "terminal" means "the node is one of the end of a word."
    // For example, if we have a trie for "aa" and "aaa", the trie looks like:
    //         [0]
    //        a/
    //       [1]
    //      a/
    //     [2]
    //    a/
    //   [3]
    // In this case, [0] and [1] are not terminal (as the original words
    // contains neither "" nor "a"), and [2] and [3] are terminal.
    let header = image.span
    let loudsSize = Int(header.loadLittleEndian(UInt32.self, at: 0))
    let terminalSize = Int(header.loadLittleEndian(UInt32.self, at: 4))
    let numCharacterBits = Int(header.loadLittleEndian(UInt32.self, at: 8))
    let edgeCharacterSize = Int(header.loadLittleEndian(UInt32.self, at: 12))
    precondition(numCharacterBits == 8)
    precondition(edgeCharacterSize > 0)

    let loudsImage = image.dropFirst(16)
    let terminalImage = loudsImage.dropFirst(loudsSize)
    let edgeCharacter = terminalImage.dropFirst(terminalSize).prefix(edgeCharacterSize)

    var louds = Louds()
    louds.initialize(
      loudsImage, loudsSize, loudsLb0CacheSize, loudsLb1CacheSize, loudsSelect0CacheSize,
      loudsSelect1CacheSize)
    var terminalBitVector = SimpleSuccinctBitVectorIndex()
    terminalBitVector.initialize(
      terminalImage, terminalSize,
      0,  // Select0 is not carried out.
      termvecLb1CacheSize)
    let opened = Structure(louds: louds, terminalBitVector: terminalBitVector, edgeCharacter: edgeCharacter)
    replaceStructure(opened)

    return true
  }

  /// Destructs the internal data structure explicitly.
  public func close() {
    replaceStructure(Structure.empty)
  }

  // Generic APIs for tree traversal, some of which are delegated from Louds;
  // see Louds.swift.

  /// Returns true if |node| is in a valid state (returns true both for
  /// terminal and non-terminal nodes).
  @inline(__always)
  public func isValidNode(_ node: Node) -> Bool { current.louds.isValidNode(node) }

  /// Returns true if |node| is a terminal node.
  @inline(__always)
  public func isTerminalNode(_ node: Node) -> Bool {
    current.isTerminalNode(node)
  }

  /// Returns the label of the edge from |node|'s parent (predecessor) to
  /// |node|.
  @inline(__always)
  public func getEdgeLabelToParentNode(_ node: Node) -> UInt8 {
    current.edgeLabel(node)
  }

  /// Computes the ID of key that reaches to |node|.
  /// REQUIRES: |node| is a terminal node.
  @inline(__always)
  public func getKeyIdOfTerminalNode(_ node: Node) -> Int {
    current.terminalBitVector.rank1(node.nodeId - 1)
  }

  /// Initializes a node corresponding to |key_id|.
  /// REQUIRES: |key_id| is a valid ID.
  public func getTerminalNodeFromKeyId(_ keyId: Int, _ node: inout Node) {
    let structure = current
    let nodeId = structure.terminalBitVector.select1(keyId + 1) + 1
    structure.louds.initNodeFromNodeId(nodeId, &node)
  }

  public func getTerminalNodeFromKeyId(_ keyId: Int) -> Node {
    var node = Node()
    getTerminalNodeFromKeyId(keyId, &node)
    return node
  }

  /// Restores the key bytes that reach to |node|.
  public func restoreKeyString(_ node: Node) -> [UInt8] {
    current.restoreKeyString(node)
  }

  /// Restores the key bytes for |key_id| (empty for a negative ID).
  public func restoreKeyString(keyId: Int) -> [UInt8] {
    // TODO(noriyukit): Check if it's necessary to handle negative IDs.
    keyId < 0 ? [] : restoreKeyString(getTerminalNodeFromKeyId(keyId))
  }

  // Methods for moving node exported from Louds; see Louds.swift.
  @inline(__always)
  public func moveToFirstChild(_ node: inout Node) { current.louds.moveToFirstChild(&node) }

  @inline(__always)
  public func moveToFirstChild(_ node: Node) -> Node {
    var node = node
    moveToFirstChild(&node)
    return node
  }

  @inline(__always)
  public static func moveToNextSibling(_ node: inout Node) { Louds.moveToNextSibling(&node) }

  @inline(__always)
  public static func moveToNextSibling(_ node: Node) -> Node {
    var node = node
    moveToNextSibling(&node)
    return node
  }

  /// Moves |node| to its child connected by the edge with |label|.  If
  /// there's no edge having |label|, |node| becomes invalid and false is
  /// returned.
  public func moveToChildByLabel(_ label: UInt8, _ node: inout Node) -> Bool {
    current.moveToChildByLabel(label, &node)
  }

  /// Traverses a trie for |key|, starting from |node|, and modifies |node| to
  /// the destination terminal node.  Here, |node| is not necessarily the root.
  /// Returns false if there's no node reachable by |key|.
  @inlinable
  public func traverse(_ key: some Sequence<UInt8>, _ node: inout Node) -> Bool {
    let structure = current
    for c in key {
      if !structure.moveToChildByLabel(c, &node) {
        return false
      }
    }
    return true
  }

  // Higher level APIs.

  /// Returns true if |key| is in this trie.
  @inlinable
  public func hasKey(_ key: some Sequence<UInt8>) -> Bool {
    var node = Node()  // Root
    return traverse(key, &node) && isTerminalNode(node)
  }

  /// Searches this trie for the key that exactly matches the given key.
  /// Returns -1 if such key doesn't exist.
  /// NOTE: When you only need to check if |key| is in this trie, use hasKey()
  /// method, which is more efficient.
  @inlinable
  public func exactSearch(_ key: some Sequence<UInt8>) -> Int {
    var node = Node()  // Root
    if traverse(key, &node) && isTerminalNode(node) {
      return getKeyIdOfTerminalNode(node)
    }
    return -1
  }

  /// Runs a functor for the prefixes of |key| that exist in the trie.
  /// |callback| has the following signature:
  ///
  ///   (key, prefixLen, trie, node)
  ///
  /// where
  ///   key: The original input key (i.e., the same as the input |key|).
  ///   prefixLen: The length of prefix (in bytes), i.e., key.prefix(prefixLen)
  ///              is the matched prefix.
  ///   trie: This trie.
  ///   node: The location information, from which key ID can be recovered by
  ///         LoudsTrie.getKeyIdOfTerminalNode() method.
  @inlinable
  public func prefixSearch<K: Collection<UInt8>>(
    _ key: K, _ callback: (_ key: K, _ prefixLen: Int, _ trie: LoudsTrie, _ node: Node) throws -> Void
  ) rethrows {
    let structure = current
    var node = Node()
    var i = 0
    for c in key {
      if !structure.moveToChildByLabel(c, &node) {
        return
      }
      i += 1  // Increment here for next loop and call |callback|.
      if structure.isTerminalNode(node) {
        try callback(key, i, self, node)
      }
    }
  }
}

// MARK: - Raw pointer interface (kept for callers that still pass raw memory)

extension LoudsTrie {
  /// Opens the image at `image`, which the caller keeps alive and unchanged
  /// until close() (as in C++). The memory is shared, not copied.
  ///
  /// Raw pointers are needed here because the caller passes memory it owns;
  /// prefer `open(_: Data, ...)`.
  @discardableResult
  public func open(
    _ image: UnsafeRawPointer, _ loudsLb0CacheSize: Int = 0, _ loudsLb1CacheSize: Int = 0,
    _ loudsSelect0CacheSize: Int = 0, _ loudsSelect1CacheSize: Int = 0,
    _ termvecLb1CacheSize: Int = 0
  ) -> Bool {
    func header(_ i: Int) -> Int {
      Int(UInt32(littleEndian: image.loadUnaligned(fromByteOffset: 4 * i, as: UInt32.self)))
    }
    let size = 16 + header(0) + header(1) + header(3)
    let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: image), count: size, deallocator: .none)
    return open(
      data, loudsLb0CacheSize, loudsLb1CacheSize, loudsSelect0CacheSize, loudsSelect1CacheSize,
      termvecLb1CacheSize)
  }

  /// Restores the key string that reaches to |node| into |buf|, which needs
  /// kMaxDepth + 1 bytes. The returned buffer points to a piece of |buf| and
  /// is followed by '\0'. Prefer `restoreKeyString(_:) -> [UInt8]`.
  public func restoreKeyString(_ node: Node, _ buf: UnsafeMutablePointer<UInt8>)
    -> UnsafeBufferPointer<UInt8>
  {
    let bufEnd = buf + Self.kMaxDepth
    bufEnd.pointee = 0
    var start = bufEnd
    current.forEachLabelToRoot(node) {
      start -= 1
      start.pointee = $0
    }
    return UnsafeBufferPointer(start: start, count: bufEnd - start)
  }

  /// Restores the key string corresponding to |key_id| into |buf|; see above.
  public func restoreKeyString(_ keyId: Int, _ buf: UnsafeMutablePointer<UInt8>)
    -> UnsafeBufferPointer<UInt8>
  {
    // TODO(noriyukit): Check if it's necessary to handle negative IDs.
    keyId < 0
      ? UnsafeBufferPointer(start: buf, count: 0)
      : restoreKeyString(getTerminalNodeFromKeyId(keyId), buf)
  }
}
