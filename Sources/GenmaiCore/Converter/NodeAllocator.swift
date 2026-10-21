// Port of mozc/src/converter/node_allocator.h (3.35.6354).

/// `mozc::NodeAllocator`: hands out nodes owned by this allocator.
///
/// The C++ version is an `Arena<Node>`. Here the allocator keeps every node it
/// created in allocation order; `free()` makes them all reusable (they are
/// re-initialized by the next `newNode()` calls, in the same order), which
/// avoids per-node heap allocation across conversions. As in C++, nodes must
/// not be used after `free()`.
public final class NodeAllocator {
  private var nodes: [Node] = []
  private var used = 0

  public init() {
    nodes.reserveCapacity(1024)
  }

  public func newNode() -> Node {
    if used < nodes.count {
      let node = nodes[used]
      used += 1
      node.initialize()
      return node
    }
    let node = Node()
    nodes.append(node)
    used += 1
    return node
  }

  /// Frees all nodes allocated by newNode().
  public func free() {
    used = 0
  }

  /// The number of nodes allocated since the last `free()`.
  public var allocatedCount: Int { used }
}
