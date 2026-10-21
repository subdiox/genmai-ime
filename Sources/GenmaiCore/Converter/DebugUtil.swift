// Port of mozc/src/converter/debug_util.{h,cc} (3.35.6354).

/// Dumps all nodes in the given lattice in TSV format.
/// The output format includes id, key, value, begin_pos, end_pos, lid, rid,
/// wcost, cost, bnext, enext, prev, and next for each node.
///
/// Node ids are assigned in the order nodes are first referenced, as in C++.
public func dumpNodes(_ lattice: Lattice) -> String {
  // Map from Node identity to a unique ID (nil is 0).
  var nodeIdMap: [ObjectIdentifier: UInt32] = [:]

  // Returns a unique ID for the given node.
  func nodeId(_ node: Node?) -> UInt32 {
    guard let node else { return 0 }
    let key = ObjectIdentifier(node)
    if let id = nodeIdMap[key] {
      return id
    }
    let id = UInt32(nodeIdMap.count + 1)  // +1 for the nullptr entry.
    nodeIdMap[key] = id
    return id
  }

  func bnextId(_ node: Node) -> UInt32 {
    let beginNodes = lattice.beginNodes(Int(node.beginPos))
    // If the node is a POS node, returns the first begin node.
    if node.key.isEmpty && node.value == "POS" {
      return nodeId(beginNodes[0])
    }
    var i = 0
    while i + 1 < beginNodes.count {
      if beginNodes[i] === node {
        return nodeId(beginNodes[i + 1])
      }
      i += 1
    }
    return 0
  }

  func enextId(_ node: Node) -> UInt32 {
    let endNodes = lattice.endNodes(Int(node.endPos))
    var i = 1
    while i < endNodes.count {
      if endNodes[i] === node {
        return nodeId(endNodes[i - 1])
      }
      i += 1
    }
    return 0
  }

  // Returns a string representation of the given node in TSV.
  // Arguments are evaluated left to right as in absl::StrCat.
  func dumpNode(_ node: Node) -> String {
    var s = "\(nodeId(node))\t\(node.key)\t\(node.value)\t\(node.beginPos)\t\(node.endPos)"
    s += "\t\(node.lid)\t\(node.rid)\t\(node.wcost)\t\(node.cost)"
    s += "\t\(bnextId(node))"
    s += "\t\(enextId(node))"
    s += "\t\(nodeId(node.prev))"
    s += "\t\(nodeId(node.next))\n"
    return s
  }

  // Output header.
  var output = [
    "id", "key", "value", "begin_pos", "end_pos", "lid", "rid", "wcost", "cost", "bnext", "enext", "prev",
    "next",
  ].joined(separator: "\t")
  output += "\n"

  // Output BOS node.
  output += dumpNode(lattice.bosNode)

  // Make position nodes.
  let keySize = lattice.key.utf8.count
  var posNodes: [Node] = []
  for i in 0...keySize {
    if lattice.beginNodes(i).isEmpty {
      continue
    }
    let posNode = Node()
    posNode.beginPos = UInt16(truncatingIfNeeded: i)
    posNode.endPos = UInt16(truncatingIfNeeded: i)
    posNode.value = "POS"
    posNodes.append(posNode)
  }
  if posNodes.count > 1 {
    for i in 0..<(posNodes.count - 1) {
      posNodes[i].next = posNodes[i + 1]
    }
  }

  // Output position nodes.
  for posNode in posNodes {
    output += dumpNode(posNode)
  }

  // Output nodes.
  for i in 0...keySize {
    let nodes = lattice.beginNodes(i)
    if nodes.isEmpty {
      continue
    }
    for node in nodes {
      output += dumpNode(node)
    }
  }
  // Keep the position nodes alive while their unowned links are used.
  withExtendedLifetime(posNodes) {}
  return output
}
