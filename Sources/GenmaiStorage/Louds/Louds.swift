// Port of mozc/src/storage/louds/louds.{h,cc} (3.35.6354).
//
// C++ `Init` is `initialize` here (`init` is reserved in Swift). Node-moving
// methods take the node `inout` (C++ `Node*`). The bit image is a `Data`
// (C++: a pointer to caller-owned memory).

import Foundation

/// Implementation of the Level-Ordered Unary Degree Sequence (LOUDS).
///
/// LOUDS represents a tree structure using a bit sequence.  A node having N
/// children is represented by N 1's and one trailing 0.  For example, "110"
/// represents a node with 2 children, while "0" represents a leaf.  The bit
/// sequence starts with the representation of super-root, "10", and is
/// followed by representations of nodes in order of breadth first manner; see
/// the following example:
///
///              0 (super root)
///              |
///              1 (root)
///            /   \
///           2     3
///                / \
///               4   5
///
///  Node:  0   1    2  3    4  5
/// LOUDS:  10  110  0  110  0  0
///
/// This type provides basic APIs to traverse a tree structure.  Performance
/// critical methods are inlined.
public struct Louds: Sendable {
  /// Represents and stores location (tree node) for tree traversal.  By
  /// storing instances of this type, traversal state can be restored.  This
  /// type is copy-efficient.
  public struct Node: Equatable, Hashable, Sendable {
    // Default instance represents the root node (not the super-root).
    @usableFromInline var edgeIndex = 0
    public internal(set) var nodeId = 1

    public init() {}
  }

  private var index = SimpleSuccinctBitVectorIndex()
  private var select0CacheSize = 0
  private var select1CacheSize = 0
  // select_cache_[0, select0_cache_size) holds the Select0 cache, followed by
  // the Select1 cache (select1_cache_ptr_ in C++).
  private var selectCache: [Int] = []

  public init() {}

  /// Initializes this LOUDS from bit array.  To improve the performance of
  /// downward traversal (i.e., from root to leaves), set
  /// |bitvec_lb0_cache_size| and |select0_cache_size| to larger values.  On
  /// the other hand, to improve the performance of upward traversal (i.e.,
  /// from leaves to the root), set |bitvec_lb1_cache_size| and
  /// |select1_cache_size| to larger values.
  public mutating func initialize(
    _ image: Data, _ length: Int, _ bitvecLb0CacheSize: Int,
    _ bitvecLb1CacheSize: Int, _ select0CacheSize: Int, _ select1CacheSize: Int
  ) {
    index.initialize(image, length, bitvecLb0CacheSize, bitvecLb1CacheSize)

    // Cap the cache sizes.
    var select0CacheSize = select0CacheSize
    var select1CacheSize = select1CacheSize
    if select0CacheSize > index.num0Bits {
      select0CacheSize = index.num0Bits
    }
    if select1CacheSize > index.num1Bits {
      select1CacheSize = index.num1Bits
    }

    // Initialize Select0 and Select1 cache for speed.  In LOUDS traversal,
    // nodes close to the root are frequently accessed.  Thus, we precompute
    // select0 and select1 values for such nodes.  Since node IDs are assigned
    // in BFS order, the nodes close to the root are assigned smaller IDs.
    // Hence, a simple array can be used for the mapping from ID to cached
    // value.
    self.select0CacheSize = select0CacheSize
    self.select1CacheSize = select1CacheSize
    let cacheSize = select0CacheSize + select1CacheSize
    if cacheSize == 0 {
      selectCache = []
      return
    }
    var cache = [Int](repeating: 0, count: cacheSize)

    if select0CacheSize > 0 {
      // Precompute Select0(i) + 1 for i in (0, select0_cache_size).
      cache[0] = 0
      for i in 1..<select0CacheSize {
        cache[i] = index.select0(i) + 1
      }
    }

    if select1CacheSize > 0 {
      // Precompute Select1(i) for i in (0, select1_cache_size).
      cache[select0CacheSize] = 0
      for i in 1..<select1CacheSize {
        cache[select0CacheSize + i] = index.select1(i)
      }
    }
    selectCache = cache
  }

  /// Explicitly clears the internal bit array.
  public mutating func reset() {
    index.reset()
    selectCache = []
    select0CacheSize = 0
    select1CacheSize = 0
  }

  // APIs for traversal.

  /// Initializes a Node instance from node ID.
  /// Note: to get the root node, just allocate a default Node instance.
  @inline(__always)
  public func initNodeFromNodeId(_ nodeId: Int, _ node: inout Node) {
    node.nodeId = nodeId
    node.edgeIndex =
      nodeId < select1CacheSize ? selectCache[select0CacheSize + nodeId] : index.select1(nodeId)
  }

  /// Returns true if the given node is the root.
  @inline(__always)
  public static func isRoot(_ node: Node) -> Bool { node.nodeId == 1 }

  /// Moves the given node to its first (most left) child.  If |node| is a
  /// leaf, the resulting node becomes invalid.  For example, in the above
  /// diagram of tree, moves are as follows:
  ///   * node 1 -> node 2
  ///   * node 3 -> node 4
  ///   * node 4 -> invalid node
  /// REQUIRES: |node| is valid.
  @inline(__always)
  public func moveToFirstChild(_ node: inout Node) {
    node.edgeIndex =
      node.nodeId < select0CacheSize ? selectCache[node.nodeId] : index.select0(node.nodeId) + 1
    node.nodeId = node.edgeIndex - node.nodeId + 1
  }

  /// Moves the given node to its next (right) sibling.  If there's no sibling
  /// for |node|, the resulting node becomes invalid. For example, in the above
  /// diagram of tree, moves are as follows:
  ///   * node 1 -> invalid node
  ///   * node 2 -> node 3
  ///   * node 5 -> invalid node
  /// REQUIRES: |node| is valid.
  @inline(__always)
  public static func moveToNextSibling(_ node: inout Node) {
    node.edgeIndex += 1
    node.nodeId += 1
  }

  /// Moves the given node to its unique parent.  For example, in the above
  /// diagram of tree, moves are as follows:
  ///   * node 2 -> node 1
  ///   * node 3 -> node 1
  ///   * node 5 -> node 3
  /// REQUIRES: |node| is valid and not root.
  @inline(__always)
  public func moveToParent(_ node: inout Node) {
    node.nodeId = node.edgeIndex - node.nodeId + 1
    node.edgeIndex =
      node.nodeId < select1CacheSize
      ? selectCache[select0CacheSize + node.nodeId] : index.select1(node.nodeId)
  }

  /// Returns true if |node| is in a valid state.
  @inline(__always)
  public func isValidNode(_ node: Node) -> Bool {
    index.get(node.edgeIndex) != 0
  }
}
