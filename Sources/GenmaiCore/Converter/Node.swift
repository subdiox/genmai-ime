// Port of mozc/src/converter/node.h (3.35.6354).

/// `mozc::Node`: a lattice node.
///
/// A final class: C++ code links nodes by raw pointers (`prev`, `next`,
/// `constrained_prev`) and compares them by identity. The links are
/// `unowned(unsafe)` like the C++ raw pointers (no reference counting in the
/// Viterbi / N-best hot loops); nodes are owned by a `NodeAllocator` (or by
/// the caller for nodes created directly), which must outlive every link.
public final class Node {
  public enum NodeType: UInt8, Sendable {
    case norNode  // normal node
    case bosNode  // BOS (beginning of sentence)
    case eosNode  // EOS (end of sentence)
    case conNode  // constrained node
    case hisNode  // history node
  }

  /// `Node::Attribute` bit flags of `attributes`.
  public enum Attribute {
    public static let defaultAttribute: UInt16 = 0
    // SYSTEM_DICTIONARY is deleted.
    public static let userDictionary: UInt16 = 1 << 1  // User dictionary
    public static let noVariantsExpansion: UInt16 = 1 << 2  // No need to expand full/half
    public static let startsWithParticle: UInt16 = 1 << 4  // User input starts with particle
    public static let spellingCorrection: UInt16 = 1 << 5  // "Did you mean"
    // PARTIALY_KEY_CONSUMED is deleted.
    public static let suffixDictionary: UInt16 = 1 << 8  // Suffix dictionary
    public static let keyExpanded: UInt16 = 1 << 9  // Keys are expanded.
  }

  /// prev and next are linking pointers to connect minimum cost path
  /// in the lattice. In other words, we can think the doubly-linked list
  /// with prev/next represents the minimum cost path.
  public unowned(unsafe) var prev: Node? = nil
  public unowned(unsafe) var next: Node? = nil

  /// if it is not nil, transition cost
  /// from constrained_prev to current node is defined,
  /// other transition is set to be infinite
  public unowned(unsafe) var constrainedPrev: Node? = nil

  public var rid: UInt16 = 0
  public var lid: UInt16 = 0

  /// The lattice positions of this node.
  /// lattice.beginNodes(beginPos) contains the array of Node starting at
  /// `beginPos`.
  public var beginPos: UInt16 = 0

  /// lattice.endNodes(endPos) contains the array of Node ending at `endPos`.
  public var endPos: UInt16 = 0

  /// wcost: word cost for the node; it may be changed after lookup
  /// cost: the total cost between BOS and the node
  public var wcost: Int32 = 0
  public var cost: Int32 = 0

  public var nodeType: NodeType = .norNode

  /// Bit field of Attribute. 16 bit is enough as the
  /// biggest value is KEY_EXPANDED = 1 << 9.
  public var attributes: UInt16 = 0

  /// key: The user input.
  /// value: The surface form of the word.
  public var key: String = ""
  public var value: String = ""

  public init() {}

  @inline(__always)
  public func initialize() {
    prev = nil
    next = nil
    constrainedPrev = nil
    rid = 0
    lid = 0
    beginPos = 0
    endPos = 0
    nodeType = .norNode
    wcost = 0
    cost = 0
    attributes = 0
    key = ""
    value = ""
  }

  public func initFromToken(_ token: Token) {
    prev = nil
    next = nil
    constrainedPrev = nil
    rid = token.rid
    lid = token.lid
    beginPos = 0
    endPos = 0
    nodeType = .norNode
    wcost = Int32(truncatingIfNeeded: token.cost)
    cost = 0
    attributes = 0
    if token.attributes & Token.Attribute.spellingCorrection != 0 {
      attributes |= Attribute.spellingCorrection
    }
    if token.attributes & Token.Attribute.suffixDictionary != 0 {
      attributes |= Attribute.suffixDictionary
    }
    if token.attributes & Token.Attribute.userDictionary != 0 {
      attributes |= Attribute.userDictionary
      attributes |= Attribute.noVariantsExpansion
    }
    key = token.key
    value = token.value
  }

  /// Copies all fields (C++ `*node = other`).
  public func assign(from other: Node) {
    prev = other.prev
    next = other.next
    constrainedPrev = other.constrainedPrev
    rid = other.rid
    lid = other.lid
    beginPos = other.beginPos
    endPos = other.endPos
    wcost = other.wcost
    cost = other.cost
    nodeType = other.nodeType
    attributes = other.attributes
    key = other.key
    value = other.value
  }
}
