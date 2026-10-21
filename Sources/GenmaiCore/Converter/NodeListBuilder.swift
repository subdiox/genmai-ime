// Port of mozc/src/converter/node_list_builder.h (3.35.6354).

/// Spatial cost penalty per modification. We are going to
/// use the moderate penalty to increase the coverage, and re-calculate
/// the actual penalty with new typing correction module.
/// Per-modification penalty allows to recompute the added penalty
/// from the actual output of key by counting different characters.
@inline(__always)
public func getPerExpansionSpatialCostPenalty() -> Int32 {
  let kPerExpansionSpatialCostPenalty: Int32 = 2500
  return kPerExpansionSpatialCostPenalty
}

@inline(__always)
public func getSpatialCostPenalty(_ numExpanded: Int) -> Int32 {
  Int32(truncatingIfNeeded: numExpanded) &* getPerExpansionSpatialCostPenalty()
}

/// Provides basic functionality for building a list of nodes.
///
/// Implements every `DictionaryCallback` requirement so that subclasses can
/// `override` them (see the protocol-default dispatch pitfall in CLAUDE.md).
open class BaseNodeListBuilder: DictionaryCallback {
  public let allocator: NodeAllocator
  public let limit: Int
  public private(set) var penalty: Int32 = 0
  public private(set) var result: [Node] = []

  public init(_ allocator: NodeAllocator, _ limit: Int) {
    self.allocator = allocator
    self.limit = limit
    result.reserveCapacity(64)
  }

  open func onKey(_ key: String) -> DictionaryCallbackResult { .traverseContinue }

  /// Determines a penalty for tokens of this (key, actual_key) pair.
  open func onActualKey(_ key: String, _ actualKey: String, _ numExpanded: Int)
    -> DictionaryCallbackResult
  {
    penalty = getSpatialCostPenalty(numExpanded)
    return .traverseContinue
  }

  /// Creates a new node and prepends it to the current list.
  open func onToken(_ key: String, _ actualKey: String, _ token: Token) -> DictionaryCallbackResult {
    let newNode = newNodeFromToken(token)
    appendToResult(newNode)
    return result.count > limit ? .traverseDone : .traverseContinue
  }

  open func isKanaModifierInsensitiveConversion() -> Bool { false }

  /// `result_view()`.
  public var resultView: [Node] { result }

  public func newNodeFromToken(_ token: Token) -> Node {
    let newNode = allocator.newNode()
    newNode.initFromToken(token)
    newNode.wcost &+= penalty
    if penalty > 0 { newNode.attributes |= Node.Attribute.keyExpanded }
    return newNode
  }

  public func appendToResult(_ node: Node) {
    result.append(node)
  }
}

/// Implements key filtering rule for LookupPrefix().
open class NodeListBuilderForLookupPrefix: BaseNodeListBuilder {
  public let minKeyLength: Int

  public init(_ allocator: NodeAllocator, _ limit: Int, _ minKeyLength: Int) {
    self.minKeyLength = minKeyLength
    super.init(allocator, limit)
  }

  open override func onKey(_ key: String) -> DictionaryCallbackResult {
    key.utf8.count < minKeyLength ? .traverseNextKey : .traverseContinue
  }
}
