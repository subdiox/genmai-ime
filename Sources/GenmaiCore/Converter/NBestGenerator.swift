// Port of mozc/src/converter/nbest_generator.{h,cc} (3.35.6354).

import GenmaiBase

/// `mozc::NBestGenerator<TConnector>`: A* N-best enumeration of the paths
/// between two nodes of a Viterbi-searched lattice.
///
/// The C++ template is instantiated for `CachingConnector<true/false>`; here
/// the connector is a `CachingConnector` whose `hasBonus` decides the same.
/// The agenda is a binary heap driven by exact ports of libc++'s
/// `std::push_heap` / `std::pop_heap` so that elements with equal f(x) are
/// popped in the same order as the C++ implementation (the oracle is built
/// with libc++).
public final class NBestGenerator {
  public enum BoundaryCheckMode: Sendable {
    // Boundary check mode.
    // For the case like;
    //   Candidate edge:      |  candidate  |
    //   Nodes:        |Node A|Node B|Node C|Node D|

    // For normal conversion.
    //  Candidate boundary is strictly same as inner boundary.
    // A-B: Should be the boundary
    // B-C: Should not be the boundary
    // C-D: Should be the boundary
    case strict

    // For resegmented segment.
    //  Check mid point only.
    // A-B: Don't care
    // B-C: Should not be the boundary
    // C-D: Don't care
    case onlyMid

    // For Realtime conversion ("私の名前は中野です").
    //  Check only for candidate edge.
    // A-B: Should be the boundary
    // B-C: Don't care
    // C-D: Should be the boundary
    case onlyEdge
  }

  /// `CandidateMode` bit flags.
  public enum CandidateMode {
    public static let candidateModeNone: UInt32 = 0
    /// Fill inner segment boundary info
    public static let fillInnerSegmentInfo: UInt32 = 1 << 0
    /// Make a candidate for the first inner segment boudnary
    /// for the given node path.
    public static let buildFromOnlyFirstInnerSegment: UInt32 = 1 << 1
  }

  public struct Options: Sendable {
    public var boundaryMode: BoundaryCheckMode = .strict
    public var candidateMode: UInt32 = CandidateMode.candidateModeNone

    public init(boundaryMode: BoundaryCheckMode = .strict, candidateMode: UInt32 = CandidateMode.candidateModeNone) {
      self.boundaryMode = boundaryMode
      self.candidateMode = candidateMode
    }
  }

  private enum BoundaryCheckResult {
    case valid
    case validWeakConnected  // Valid but should get penalty.
    case invalid
  }

  private struct QueueElement {
    unowned let node: Node
    /// Index of the next element in `arena`, or -1.
    let next: Int32
    /// f(x) = h(x) + g(x): cost function for A* search
    let fx: Int32
    /// g(x): current cost
    /// After the search, |gx| should contain the candidates' cost.
    /// Please refer to the comment in NBestGenerator.next() for more detail on
    /// the candidates' cost.
    let gx: Int32
    /// transition cost part of g(x).
    /// Do not take the transition costs to edge nodes.
    let structureGx: Int32
    let wGx: Int32
  }

  private static let kArenaChunkSize = 512
  private static let kCostDiff: Int32 = 3453  // log prob of 1/1000

  // References to relevant modules.
  private let userDictionary: any UserDictionaryInterface
  private let segmenter: Segmenter
  private let connector: CachingConnector
  private let posMatcher: PosMatcher
  private let lattice: Lattice

  private unowned var beginNode: Node? = nil
  private unowned var endNode: Node? = nil

  /// The agenda: a heap of indices into `arena`.
  private var agenda: [Int32] = []
  private var arena: [QueueElement] = []
  private var topNodes: [Node] = []
  private let filter: CandidateFilter
  private var viterbiResultChecked = false
  private var options = Options()

  private var badCandidates: [Candidate] = []

  /// Try to enumerate N-best results between begin_node and end_node.
  public init(
    _ userDictionary: any UserDictionaryInterface, _ segmenter: Segmenter, _ connector: CachingConnector,
    _ posMatcher: PosMatcher, _ lattice: Lattice, _ suggestionFilter: any SuggestionFilterProtocol
  ) {
    self.userDictionary = userDictionary
    self.segmenter = segmenter
    self.connector = connector
    self.posMatcher = posMatcher
    self.lattice = lattice
    self.filter = CandidateFilter(userDictionary, posMatcher, suggestionFilter)
    if !lattice.hasLattice {
      GenmaiLog.error("lattice is not available")
      return
    }
    agenda.reserveCapacity(Self.kArenaChunkSize)
    arena.reserveCapacity(Self.kArenaChunkSize)
  }

  /// Reset the iterator status.
  public func reset(_ beginNode: Node, _ endNode: Node, _ options: Options) {
    agenda.removeAll(keepingCapacity: true)
    arena.removeAll(keepingCapacity: true)
    topNodes.removeAll(keepingCapacity: true)
    filter.reset()
    viterbiResultChecked = false
    self.options = options

    self.beginNode = beginNode
    self.endNode = endNode

    for node in lattice.beginNodes(Int(endNode.beginPos)) {
      if node === endNode
        || (node.lid != endNode.lid
          // node->cost can be smaller than end_node_->cost
          && abs(Int(node.cost) - Int(endNode.cost)) <= Int(Self.kCostDiff)
          && node.prev !== endNode.prev)
      {
        // Push "EOS" nodes.
        // Note:
        // node->cost contains nodes' word cost.
        // The word cost part will be adjusted as marginalized cost in Next().
        agendaPush(createNewElement(node, -1, node.cost, 0, 0, 0))
      }
    }
  }

  /// Set candidates.
  public func setCandidates(
    _ options: ConversionOptions, _ originalKey: some StringProtocol, _ expandSize: Int, _ segment: Segment
  ) {
    if !lattice.hasLattice {
      GenmaiLog.error("Must create lattice in advance")
      return
    }

    let originalKey = String(originalKey)
    while segment.candidatesSize < expandSize {
      let candidate = segment.pushBackCandidate()

      // if Next() returns false, no more entries are generated.
      if !next(options, originalKey, candidate) {
        segment.popBackCandidate()
        break
      }
    }
    #if DEBUG
      // Append moved bad_candidates_ to segment.removed_candidates_for_debug_.
      segment.removedCandidatesForDebug.append(contentsOf: badCandidates)
      badCandidates.removeAll()
    #endif
  }

  // MARK: - Agenda (libc++ heap algorithms)

  /// `QueueElement::Comparator`: q1.fx > q2.fx.
  @inline(__always)
  private func comp(_ a: Int32, _ b: Int32) -> Bool {
    arena[Int(a)].fx > arena[Int(b)].fx
  }

  /// libc++ `std::__sift_up`.
  private func siftUp(_ len: Int) {
    var len = len
    if len > 1 {
      len = (len - 2) / 2
      var ptr = len
      var last = agenda.count - 1
      if comp(agenda[ptr], agenda[last]) {
        let t = agenda[last]
        repeat {
          agenda[last] = agenda[ptr]
          last = ptr
          if len == 0 {
            break
          }
          len = (len - 1) / 2
          ptr = len
        } while comp(agenda[ptr], t)
        agenda[last] = t
      }
    }
  }

  /// `std::push_heap` after push_back.
  private func agendaPush(_ element: Int32) {
    agenda.append(element)
    siftUp(agenda.count)
  }

  /// libc++ `std::__floyd_sift_down`; returns the hole.
  private func floydSiftDown(_ len: Int) -> Int {
    var hole = 0
    var childI = 0
    var child = 0
    while true {
      childI += child + 1
      child = 2 * child + 1
      if child + 1 < len && comp(agenda[childI], agenda[childI + 1]) {
        // right-child exists and is greater than left-child
        childI += 1
        child += 1
      }
      // move hole down
      agenda[hole] = agenda[childI]
      hole = childI
      // if hole is now a leaf, we're done
      if child > (len - 2) / 2 {
        return hole
      }
    }
  }

  /// `std::pop_heap` + pop_back (libc++ implementation).
  private func agendaPop() {
    let len = agenda.count
    if len > 1 {
      let top = agenda[0]  // create a hole at first
      var hole = floydSiftDown(len)
      let last = len - 1
      if hole == last {
        agenda[hole] = top
      } else {
        agenda[hole] = agenda[last]
        hole += 1
        agenda[last] = top
        // __sift_up(first, hole, comp, hole - first)
        siftUpRange(hole)
      }
    }
    agenda.removeLast()
  }

  /// libc++ `std::__sift_up(first, first + end, comp, end)`.
  private func siftUpRange(_ end: Int) {
    var len = end
    if len > 1 {
      len = (len - 2) / 2
      var ptr = len
      var last = end - 1
      if comp(agenda[ptr], agenda[last]) {
        let t = agenda[last]
        repeat {
          agenda[last] = agenda[ptr]
          last = ptr
          if len == 0 {
            break
          }
          len = (len - 1) / 2
          ptr = len
        } while comp(agenda[ptr], t)
        agenda[last] = t
      }
    }
  }

  /// Create queue element from arena
  @inline(__always)
  private func createNewElement(
    _ node: Node, _ next: Int32, _ fx: Int32, _ gx: Int32, _ structureGx: Int32, _ wGx: Int32
  ) -> Int32 {
    arena.append(QueueElement(node: node, next: next, fx: fx, gx: gx, structureGx: structureGx, wGx: wGx))
    return Int32(arena.count - 1)
  }

  // MARK: - Candidates

  private static func isBetweenAlphabetKeys(_ left: Node, _ right: Node) -> Bool {
    guard let l = left.key.utf8.last, let r = right.key.utf8.first else { return false }
    return isAsciiAlpha(l) && isAsciiAlpha(r)
  }

  @inline(__always)
  private static func isAsciiAlpha(_ c: UInt8) -> Bool {
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
  }

  private func makeCandidate(
    _ candidate: Candidate, _ cost: Int32, _ structureCost: Int32, _ wcost: Int32, _ nodes: [Node]
  ) {
    guard let firstNode = nodes.first, let lastNode = nodes.last else {
      preconditionFailure("a candidate has at least one node")
    }
    candidate.clear()
    candidate.lid = firstNode.lid
    candidate.rid = lastNode.rid
    candidate.cost = cost
    candidate.structureCost = structureCost
    candidate.wcost = wcost

    var isFunctional = false
    for node in nodes {
      if !isFunctional && !posMatcher.isFunctional(node.lid) {
        candidate.contentKey += node.key
        candidate.contentValue += node.value
      } else {
        isFunctional = true
      }
      candidate.key += node.key
      candidate.value += node.value

      if node.constrainedPrev != nil || node.next?.constrainedPrev === node {
        // If result has constrained_node, set CONTEXT_SENSITIVE.
        // If a node has constrained node, the node is generated by
        //  a) compound node and resegmented via personal name resegmentation
        //  b) compound-based reranking.
        candidate.attributes |= Attribute.contextSensitive
      }
      if node.attributes & Node.Attribute.spellingCorrection != 0 {
        candidate.attributes |= Attribute.spellingCorrection
      }
      if node.attributes & Node.Attribute.noVariantsExpansion != 0 {
        candidate.attributes |= Attribute.noVariantsExpansion
      }
      if node.attributes & Node.Attribute.userDictionary != 0 {
        candidate.attributes |= Attribute.userDictionary
      }
      if node.attributes & Node.Attribute.suffixDictionary != 0 {
        candidate.attributes |= Attribute.suffixDictionary
      }
      if node.attributes & Node.Attribute.keyExpanded != 0 {
        candidate.attributes |= Attribute.keyExpandedInDictionary
      }
    }

    if candidate.contentKey.isEmpty || candidate.contentValue.isEmpty {
      candidate.contentKey = candidate.key
      candidate.contentValue = candidate.value
    }

    candidate.innerSegmentBoundary = []
    // For realtime conversion.
    if options.candidateMode & CandidateMode.fillInnerSegmentInfo != 0 {
      fillInnerSegmentInfo(nodes, candidate)
    }
  }

  private func fillInnerSegmentInfo(_ nodes: [Node], _ candidate: Candidate) {
    var keyLen = nodes[0].key.utf8.count
    var valueLen = nodes[0].value.utf8.count
    var contentKeyLen = keyLen
    var contentValueLen = valueLen
    var isContentBoundary = false
    if posMatcher.isFunctional(nodes[0].rid) {
      isContentBoundary = true
      contentKeyLen = 0
      contentValueLen = 0
    }

    var builder = InnerSegmentBoundaryBuilder()

    for i in 1..<max(1, nodes.count) {
      let lnode = nodes[i - 1]
      let rnode = nodes[i]
      let kMultipleSegments = false
      if segmenter.isBoundary(lnode, rnode, kMultipleSegments) {
        // Keep the consistency with the above logic for candidate.content_*.
        if contentKeyLen == 0 || contentValueLen == 0 {
          contentKeyLen = keyLen
          contentValueLen = valueLen
        }
        builder.add(keyLen, valueLen, contentKeyLen, contentValueLen)
        keyLen = 0
        valueLen = 0
        contentKeyLen = 0
        contentValueLen = 0
        isContentBoundary = false
      }
      keyLen += rnode.key.utf8.count
      valueLen += rnode.value.utf8.count
      if isContentBoundary {
        continue
      }
      // Set boundary only after content nouns or pronouns.  For example,
      // "走った" is formed as
      //     "走っ" (content word) + "た" (functional).
      // Since the content word is incomplete, we don't want to learn "走っ".
      if (posMatcher.isContentNoun(lnode.rid) || posMatcher.isPronoun(lnode.rid))
        && posMatcher.isFunctional(rnode.lid)
      {
        isContentBoundary = true
      } else {
        contentKeyLen += rnode.key.utf8.count
        contentValueLen += rnode.value.utf8.count
      }
    }

    // Keep the consistency with the above logic for candidate.content_*.
    if contentKeyLen == 0 || contentValueLen == 0 {
      contentKeyLen = keyLen
      contentValueLen = valueLen
    }

    builder.add(keyLen, valueLen, contentKeyLen, contentValueLen)
    candidate.innerSegmentBoundary = builder.build(candidate.key, candidate.value)
  }

  private func makeCandidateFromElement(
    _ options: ConversionOptions, _ originalKey: String, _ elementIndex: Int32, _ candidate: Candidate
  ) -> CandidateFilter.ResultType {
    var nodes: [Node] = []
    let element = arena[Int(elementIndex)]

    if element.next < 0 {
      return .badCandidate
    }
    if self.options.candidateMode & CandidateMode.buildFromOnlyFirstInnerSegment != 0 {
      var elm = arena[Int(element.next)]
      while elm.next >= 0 {
        let nextElm = arena[Int(elm.next)]
        nodes.append(elm.node)
        if Self.isBetweenAlphabetKeys(elm.node, nextElm.node) {
          return .badCandidate
        }
        if segmenter.isBoundary(elm.node, nextElm.node, false) {
          break
        }
        elm = nextElm
      }

      // Does not contain the transition cost to the right
      let cost = element.gx &- elm.gx
      let structureCost = element.structureGx &- elm.structureGx
      let wcost = element.wGx &- elm.wGx
      makeCandidate(candidate, cost, structureCost, wcost, nodes)
    } else {
      var elm = arena[Int(element.next)]
      while elm.next >= 0 {
        nodes.append(elm.node)
        elm = arena[Int(elm.next)]
      }
      makeCandidate(candidate, element.gx, element.structureGx, element.wGx, nodes)
    }

    return filter.filterCandidate(options, originalKey, candidate, topNodes, nodes)
  }

  /// Iterator:
  /// Can obtain N-best results by calling next() in sequence.
  private func next(_ options: ConversionOptions, _ originalKey: String, _ candidate: Candidate) -> Bool {
    // |cost| and |structure_cost| are calculated as follows:
    //
    // Example:
    // |left_node| => |node1| => |node2| => |node3| => |right_node|.
    // |node1| .. |node3| consists of a candidate.
    //
    // cost = (left_node->cost - begin_node_->cost) +
    //        trans(left_node, node1) + node1->wcost +
    //        trans(node1,     node2) + node2->wcost +
    //        trans(node2,     node3) + node3->wcost +
    //        trans(node3, rigt_node) +
    //        (right_node->cost - end_node_->cost)
    // structure_cost = trans(node1, node2) + trans(node2, node3);
    // wcost = node1->wcost +
    //        trans(node1,     node2) + node2->wcost +
    //        trans(node2,     node3) + node3->wcost
    //
    // Here (left_node->cost - begin_node_->cost) and
    //      (right_node->cost - end_node->cost) act as an approximation
    // of marginalized costs of the candidate |node1| .. |node3|.
    // "marginalized cost" means that how likely the left_node or right_node
    // are selected by taking the all paths encoded in the lattice.
    // These approximated costs are exactly 0 when taking Viterbi-best
    // path.

    // Insert Viterbi best result here to make sure that
    // the top result is Viterbi best result.
    if !viterbiResultChecked {
      viterbiResultChecked = true
      // Use CandidateFilter so that filter is initialized with the
      // Viterbi-best path.
      switch insertTopResult(options, originalKey, candidate) {
      case .goodCandidate:
        return true
      case .stopEnumeration:
        return false
      // Viterbi best result was tried to be inserted but reverted.
      case .badCandidate:
        #if DEBUG
          badCandidates.append(candidate.copy())
        #endif
      }
    }

    guard let beginNode, let endNode else {
      preconditionFailure("reset() sets the begin and end nodes")
    }

    let kMaxTrial = 500
    var numTrials = 0

    while !agenda.isEmpty {
      let topIndex = agenda[0]
      agendaPop()
      let top = arena[Int(topIndex)]
      let rnode = top.node

      if numTrials > kMaxTrial {  // too many trials
        return false
      }
      numTrials += 1

      // reached to the goal.
      if rnode.endPos == beginNode.endPos {
        let filterResult = makeCandidateFromElement(options, originalKey, topIndex, candidate)
        switch filterResult {
        case .goodCandidate:
          return true
        case .stopEnumeration:
          return false
        case .badCandidate:
          #if DEBUG
            badCandidates.append(candidate.copy())
          #endif
        }
        continue
      }

      var bestLeftElm: Int32 = -1
      let isRightEdge = rnode.beginPos == endNode.beginPos
      let isLeftEdge = rnode.beginPos == beginNode.endPos

      // is_edge is true if current lnode/rnode has same boundary as
      // begin/end node regardless of its value.
      let isEdge = isRightEdge || isLeftEdge

      for lnode in lattice.endNodes(Int(rnode.beginPos)) {
        // is_invalid_position is true if the lnode's location is invalid
        //  1.   |<-- begin_node_-->|
        //                    |<--lnode-->|  <== overlapped.
        //
        //  2.   |<-- begin_node_-->|
        //         |<--lnode-->|    <== exceeds begin_node.
        // This case can't be happened because the |rnode| is always at just
        // right of the |lnode|. By avoiding case1, this can't be happen.
        //  2'.  |<-- begin_node_-->|
        //         |<--lnode-->||<--rnode-->|
        let isValidPosition = !(lnode.beginPos < beginNode.endPos && beginNode.endPos < lnode.endPos)
        if !isValidPosition {
          continue
        }

        // If left_node is left edge, there is a cost-based constraint.
        let isValidCost = (lnode.cost &- beginNode.cost) <= Self.kCostDiff
        if isLeftEdge && !isValidCost {
          continue
        }

        // We can omit the search for the node which has the
        // same rid with |begin_node_| because:
        //  1. |begin_node_| is the part of the best route.
        //  2. The cost diff of 'LEFT_EDGE' is decided only by
        //     transition_cost for lnode.
        // Actually, checking for each rid once is enough.
        let canOmitSearch = lnode.rid == beginNode.rid && lnode !== beginNode
        if isLeftEdge && canOmitSearch {
          continue
        }

        let boundaryResult = boundaryCheck(lnode, rnode, isEdge)
        if boundaryResult == .invalid {
          continue
        }

        // We can expand candidates from |rnode| to |lnode|.
        let transitionCost = Int32(truncatingIfNeeded: getTransitionCost(lnode, rnode))

        // How likely the costs get increased after expanding rnode.
        var costDiff: Int32 = 0
        var structureCostDiff: Int32 = 0
        var wcostDiff: Int32 = 0

        if isRightEdge {
          // use |rnode->cost - end_node_->cost| is an approximation
          // of marginalized word cost.
          costDiff = transitionCost &+ (rnode.cost &- endNode.cost)
          structureCostDiff = 0
          wcostDiff = 0
        } else if isLeftEdge {
          // use |lnode->cost - begin_node_->cost| is an approximation
          // of marginalized word cost.
          costDiff = transitionCost &+ rnode.wcost &+ (lnode.cost &- beginNode.cost)
          structureCostDiff = 0
          wcostDiff = rnode.wcost
        } else {
          // use rnode->wcost.
          costDiff = transitionCost &+ rnode.wcost
          structureCostDiff = transitionCost
          wcostDiff = transitionCost &+ rnode.wcost
        }

        if boundaryResult == .validWeakConnected {
          let kWeakConnectedPenalty: Int32 = 3453  // log prob of 1/1000
          costDiff &+= kWeakConnectedPenalty
          structureCostDiff &+= kWeakConnectedPenalty / 2
          wcostDiff &+= kWeakConnectedPenalty / 2
        }

        let gx = costDiff &+ top.gx
        // |lnode->cost| is heuristics function of A* search, h(x).
        // After Viterbi search, we already know an exact value of h(x).
        // f(x) = h(x) + g(x): cost for the path
        let fx = lnode.cost &+ gx
        let structureGx = structureCostDiff &+ top.structureGx
        let wGx = wcostDiff &+ top.wGx
        if isLeftEdge {
          // We only need to only 1 left node here.
          // Even if expand all left nodes, all the |value| part should
          // be identical. Here, we simply use the best left edge node.
          // This hack reduces the number of redundant calls of pop().
          if bestLeftElm < 0 || arena[Int(bestLeftElm)].fx > fx {
            bestLeftElm = createNewElement(lnode, topIndex, fx, gx, structureGx, wGx)
          }
        } else {
          agendaPush(createNewElement(lnode, topIndex, fx, gx, structureGx, wGx))
        }
      }

      if bestLeftElm >= 0 {
        agendaPush(bestLeftElm)
      }
    }

    return false
  }

  /// Helper function for next(). Checks node boundary conditions.
  private func boundaryCheck(_ lnode: Node, _ rnode: Node, _ isEdge: Bool) -> BoundaryCheckResult {
    // Special case, no boundary check
    if rnode.nodeType == .conNode || lnode.nodeType == .conNode {
      return .valid
    }

    // We don't want to connect alphabet keys within a segment.
    // If "eupho" is not in the dictionary, "eupho" as an as-is fallback is
    // expected rather than "EUpho" (EU + pho).
    if !isEdge && Self.isBetweenAlphabetKeys(lnode, rnode) {
      return .invalid
    }

    switch options.boundaryMode {
    case .strict:
      return checkStrict(lnode, rnode, isEdge)
    case .onlyMid:
      return checkOnlyMid(lnode, rnode, isEdge)
    case .onlyEdge:
      return checkOnlyEdge(lnode, rnode, isEdge)
    }
  }

  private func checkOnlyMid(_ lnode: Node, _ rnode: Node, _ isEdge: Bool) -> BoundaryCheckResult {
    // is_boundary is true if there is a grammar-based boundary
    // between lnode and rnode
    let isBoundary = lnode.nodeType == .hisNode || segmenter.isBoundary(lnode, rnode, false)
    if !isEdge && isBoundary {
      // There is a boundary within the segment.
      return .invalid
    }

    if isEdge && !isBoundary {
      // Here is not the boundary gramatically, but segmented by
      // other reason.
      return .validWeakConnected
    }

    return .valid
  }

  private func checkOnlyEdge(_ lnode: Node, _ rnode: Node, _ isEdge: Bool) -> BoundaryCheckResult {
    // is_boundary is true if there is a grammar-based boundary
    // between lnode and rnode
    let isBoundary = lnode.nodeType == .hisNode || segmenter.isBoundary(lnode, rnode, true)
    if isEdge != isBoundary {
      // on the edge, have a boundary.
      // not on the edge, not the case.
      return .invalid
    } else {
      return .valid
    }
  }

  private func checkStrict(_ lnode: Node, _ rnode: Node, _ isEdge: Bool) -> BoundaryCheckResult {
    // is_boundary is true if there is a grammar-based boundary
    // between lnode and rnode
    let isBoundary = lnode.nodeType == .hisNode || segmenter.isBoundary(lnode, rnode, false)

    if isEdge != isBoundary {
      // on the edge, have a boundary.
      // not on the edge, not the case.
      return .invalid
    } else {
      return .valid
    }
  }

  private func makeCandidateFromBestPath(_ candidate: Candidate) -> Bool {
    topNodes.removeAll(keepingCapacity: true)
    var totalWcost: Int32 = 0
    guard let beginNode, let endNode, let firstNode = beginNode.next else {
      preconditionFailure("reset() sets the begin and end nodes of a linked path")
    }
    var node = beginNode.next
    while let n = node, n !== endNode {
      if n !== firstNode {
        if let prevNode = topNodes.last, Self.isBetweenAlphabetKeys(prevNode, n) {
          return false
        }
        totalWcost &+= n.wcost
      }
      topNodes.append(n)
      node = n.next
    }

    guard let lastNode = endNode.prev else {
      preconditionFailure("the end node is on the best path")
    }
    // |cost| includes transition cost to left and right segments
    let cost = (endNode.cost &- endNode.wcost) &- beginNode.cost
    // |structure_cost|: transition cost between nodes in segments
    let structureCost = lastNode.cost &- firstNode.cost &- totalWcost
    // |wcost|: nodes cost without transition costs
    let wcost = lastNode.cost &- firstNode.cost &+ firstNode.wcost

    makeCandidate(candidate, cost, structureCost, wcost, topNodes)
    return true
  }

  private func makePrefixCandidateFromBestPath(_ candidate: Candidate) {
    topNodes.removeAll(keepingCapacity: true)
    var totalExtraWcost: Int32 = 0  // wcost sum excepting the first node
    guard let beginNode, let endNode, let firstNode = beginNode.next else {
      preconditionFailure("reset() sets the begin and end nodes of a linked path")
    }
    var prevNode = beginNode
    var node = beginNode.next
    while let n = node, n !== endNode {
      if prevNode !== beginNode && segmenter.isBoundary(prevNode, n, false) {
        break
      }
      topNodes.append(n)
      if n !== firstNode {
        totalExtraWcost &+= n.wcost
      }
      prevNode = n
      node = n.next
    }

    guard let lastNode = topNodes.last else {
      preconditionFailure("the best path has at least one node")
    }

    // Prefix candidate's |cost| does not include the transition cost
    // to right segments / nodes.
    let cost = lastNode.cost

    let structureCost = lastNode.cost &- firstNode.cost &- totalExtraWcost

    // |wcost|: nodes cost without transition costs
    let wcost = lastNode.cost &- firstNode.cost &+ firstNode.wcost

    makeCandidate(candidate, cost, structureCost, wcost, topNodes)
  }

  private func insertTopResult(_ options: ConversionOptions, _ originalKey: String, _ candidate: Candidate)
    -> CandidateFilter.ResultType
  {
    if self.options.candidateMode & CandidateMode.buildFromOnlyFirstInnerSegment != 0 {
      makePrefixCandidateFromBestPath(candidate)
    } else {
      if !makeCandidateFromBestPath(candidate) {
        return .stopEnumeration
      }
    }
    if options.requestType == .suggestion {
      candidate.attributes |= Attribute.realtimeConversion
    }

    return filter.filterCandidate(options, originalKey, candidate, topNodes, topNodes)
  }

  private func getTransitionCost(_ lnode: Node, _ rnode: Node) -> Int {
    let kInvalidPenaltyCost = 100000
    if let constrainedPrev = rnode.constrainedPrev, lnode !== constrainedPrev {
      return kInvalidPenaltyCost
    }
    connector.resetCacheIfNecessary(rnode.lid)
    return connector.getTransitionCost(lnode.rid, rnode.lid)
  }
}
