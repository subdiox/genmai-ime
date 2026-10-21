// Port of mozc/src/converter/lattice.{h,cc} (3.35.6354).

/// `mozc::Lattice`. Positions are UTF-8 byte offsets into `key`.
public final class Lattice {
  public let nodeAllocator = NodeAllocator()

  public private(set) var key: String = ""
  private var beginNodesStorage: [[Node]] = []
  private var endNodesStorage: [[Node]] = []

  public init() {}

  /// set key and initializes lattice with key.
  /// overrides `bosId` to change the left context id.
  /// Note that `bosId` must be in the valid range.
  public func setKey(_ key: String, bosId: UInt16 = 0) {
    clear()
    self.key = key
    let size = key.utf8.count
    beginNodesStorage = [[Node]](repeating: [], count: size + 1)
    endNodesStorage = [[Node]](repeating: [], count: size + 1)
    for i in 0...size {
      beginNodesStorage[i].reserveCapacity(32)
      endNodesStorage[i].reserveCapacity(32)
    }

    let bosNode = Self.initBOSNode(newNode(), 0, bosId)
    let eosNode = Self.initEOSNode(newNode(), UInt16(truncatingIfNeeded: size))

    endNodesStorage[0].append(bosNode)
    beginNodesStorage[size].append(eosNode)
  }

  /// allocate new node.
  @inline(__always)
  public func newNode() -> Node { nodeAllocator.newNode() }

  /// return the array of nodes starting with `pos`.
  @inline(__always)
  public func beginNodes(_ pos: Int) -> [Node] { beginNodesStorage[pos] }

  /// return the array of nodes ending with `pos`.
  @inline(__always)
  public func endNodes(_ pos: Int) -> [Node] { endNodesStorage[pos] }

  /// return bos node.
  public var bosNode: Node { endNodesStorage[0][0] }

  /// return eos node.
  public var eosNode: Node { beginNodesStorage[key.utf8.count][0] }

  /// inset one node to the position `pos`.
  public func insert(_ pos: Int, _ node: Node) {
    let endPos = min(node.key.utf8.count + pos, key.utf8.count)
    node.beginPos = UInt16(truncatingIfNeeded: pos)
    node.endPos = UInt16(truncatingIfNeeded: endPos)
    node.prev = nil
    node.next = nil
    node.cost = 0
    beginNodesStorage[pos].append(node)
    endNodesStorage[endPos].append(node)
  }

  /// inset multiple nodes to the position `pos`.
  public func insert(_ pos: Int, _ nodes: [Node]) {
    beginNodesStorage[pos].reserveCapacity(beginNodesStorage[pos].count + nodes.count)
    for node in nodes {
      insert(pos, node)
    }
  }

  /// return true if this instance has a valid lattice.
  public var hasLattice: Bool { !beginNodesStorage.isEmpty }

  /// Dump the best path and the path that contains the designated string.
  public func debugString() -> String {
    if !hasLattice {
      return ""
    }
    var nodeVector: [Node] = []
    var node: Node? = eosNode
    while let n = node {
      nodeVector.append(n)
      node = n.prev
    }

    var os = ""
    var prevNode: Node? = nil
    for node in nodeVector.reversed() {
      os += "[con:\(Int(node.cost) - Int(prevNode?.cost ?? 0) - Int(node.wcost))]"
      os += "[lid:\(node.lid)]"
      os += "\"\(node.value)\""
      os += "[wcost:\(node.wcost)]"
      os += "[cost:\(node.cost)]"
      os += "[rid:\(node.rid)]"
      prevNode = node
    }
    return os
  }

  /// clear all lattice and nodes allocated with newNode method
  /// Only called via setKey().
  private func clear() {
    key = ""
    beginNodesStorage.removeAll()
    endNodesStorage.removeAll()
    nodeAllocator.free()
  }

  private static func initBOSNode(_ bosNode: Node, _ position: UInt16, _ bosId: UInt16) -> Node {
    bosNode.rid = bosId  // 0 is reserved for EOS/BOS
    bosNode.lid = 0
    bosNode.key = ""
    bosNode.value = "BOS"
    bosNode.nodeType = .bosNode
    bosNode.wcost = 0
    bosNode.cost = 0
    bosNode.beginPos = position
    bosNode.endPos = position
    return bosNode
  }

  private static func initEOSNode(_ eosNode: Node, _ position: UInt16) -> Node {
    eosNode.rid = 0  // 0 is reserved for EOS/BOS
    eosNode.lid = 0
    eosNode.key = ""
    eosNode.value = "EOS"
    eosNode.nodeType = .eosNode
    eosNode.wcost = 0
    eosNode.cost = 0
    eosNode.beginPos = position
    eosNode.endPos = position
    return eosNode
  }
}

/// `ScopedLatticeNodeInserter`: collects nodes and inserts them in a batch.
/// Adding a node while iterating through the node list of a position is
/// generally unsafe in C++; the C++ class inserts in its destructor. Swift has
/// no scoped destructors, so call `flush()` (or use
/// `Lattice.withNodeInserter(_:)`).
///
///     lattice.withNodeInserter { inserter in
///       for node in lattice.beginNodes(pos) {
///         inserter.insert(pos, newNode)
///       }
///     }
public final class ScopedLatticeNodeInserter {
  private let lattice: Lattice
  private var inserted: [(Int, Node)] = []

  public init(_ lattice: Lattice) {
    self.lattice = lattice
  }

  public var isInserted: Bool { !inserted.isEmpty }

  public func insert(_ pos: Int, _ node: Node) { inserted.append((pos, node)) }

  /// Inserts the collected nodes (the C++ destructor).
  public func flush() {
    for (pos, node) in inserted {
      lattice.insert(pos, node)
    }
    inserted.removeAll()
  }
}

extension Lattice {
  /// Runs `body` with a `ScopedLatticeNodeInserter` and inserts its nodes
  /// afterwards.
  public func withNodeInserter<R>(_ body: (ScopedLatticeNodeInserter) throws -> R) rethrows -> R {
    let inserter = ScopedLatticeNodeInserter(self)
    defer { inserter.flush() }
    return try body(inserter)
  }
}
