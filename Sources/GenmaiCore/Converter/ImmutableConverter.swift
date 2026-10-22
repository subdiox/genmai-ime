// Port of mozc/src/converter/immutable_converter.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - engine::Modules is not part of the converter port: the constructor takes
//   the modules it reads (dictionary, suffix dictionary, user dictionary,
//   connector, segmenter, POS matcher, POS group, suggestion filter).
// - `CachingConnector<kHasBonus>` is a runtime flag of `CachingConnector`, so
//   the templated helpers take a `CachingConnector`.
// - `Convert(options, segments)` uses a fresh Lattice per call (the C++
//   thread_local lattice reuse on Apple platforms is a pure optimization).
// - Private methods used by the C++ test peer are `internal`.

import GenmaiBase

private let kMaxSegmentsSize = 256
private let kMaxCharLength = 1024
private let kMaxCharLengthForReverseConversion = 600  // 200 chars in UTF8
private let kMaxCost: Int32 = 32767
private let kMinCost: Int32 = -32767
private let kDefaultNumberCost: Int32 = 3000
private let kMaxNodesSize = 8192

private final class KeyCorrectedNodeListBuilder: BaseNodeListBuilder {
  private let pos: Int
  private let originalLookupKey: String
  private let keyCorrector: KeyCorrector

  init(_ pos: Int, _ originalLookupKey: String, _ keyCorrector: KeyCorrector, _ allocator: NodeAllocator) {
    self.pos = pos
    self.originalLookupKey = originalLookupKey
    self.keyCorrector = keyCorrector
    super.init(allocator, kMaxNodesSize)
  }

  override func onToken(_ key: String, _ actualKey: String, _ token: Token) -> DictionaryCallbackResult {
    let offset = keyCorrector.getOriginalOffset(pos, token.key.utf8.count)
    if !KeyCorrector.isValidPosition(offset) || offset == 0 {
      return .traverseNextKey
    }
    let node = newNodeFromToken(token)
    node.key = String(originalLookupKey.byteSubstring(from: pos, length: offset))
    node.wcost &+= Int32(truncatingIfNeeded: KeyCorrector.getCorrectedCostPenalty(node.key))
    appendToResult(node)
    return .traverseContinue
  }
}

private func insertCorrectedNodes(
  _ pos: Int, _ key: String, _ options: ConversionOptions, _ keyCorrector: KeyCorrector?,
  _ dictionary: any DictionaryInterface, _ lattice: Lattice
) {
  guard let keyCorrector else {
    return
  }
  let prefix = keyCorrector.getCorrectedPrefix(pos)
  if prefix.isEmpty {
    return
  }
  let builder = KeyCorrectedNodeListBuilder(pos, key, keyCorrector, lattice.nodeAllocator)
  dictionary.lookupPrefix(String(prefix), options: options, callback: builder)
  lattice.insert(pos, builder.resultView)
}

@inline(__always)
private func isNumber(_ c: UInt8) -> Bool { c >= 0x30 && c <= 0x39 }

/// True if the first byte of `s` is an ASCII digit (false for "").
@inline(__always)
private func startsWithNumber(_ s: String) -> Bool { s.utf8.first.map(isNumber) ?? false }

/// True if the last byte of `s` is an ASCII digit (false for "").
@inline(__always)
private func endsWithNumber(_ s: String) -> Bool { s.utf8.last.map(isNumber) ?? false }

private func containsWhiteSpacesOnly(_ s: some StringProtocol) -> Bool {
  for c in s.unicodeScalars {
    switch c.value {
    case 0x09,  // TAB
      0x20,  // Half-width space
      0x3000:  // Full-width space
      break
    default:
      return false
    }
  }
  return true
}

/// <number, suffix>
private func decomposeNumberAndSuffix(_ input: String) -> (Substring, Substring) {
  let bytes = input.utf8
  var n = 0
  for b in bytes {
    if !isNumber(b) { break }
    n += 1
  }
  return (input.byteSubstring(from: 0, length: n), input.byteSubstring(from: n))
}

/// <prefix, number>
private func decomposePrefixAndNumber(_ input: String) -> (Substring, Substring) {
  let bytes = Array(input.utf8)
  var prefixLen = bytes.count
  while prefixLen > 0 && isNumber(bytes[prefixLen - 1]) {
    prefixLen -= 1
  }
  return (input.byteSubstring(from: 0, length: prefixLen), input.byteSubstring(from: prefixLen))
}

private func normalizeHistorySegments(_ segments: Segments) {
  for segment in segments.historySegments {
    if segment.candidatesSize == 0 {
      continue
    }

    let c = segment.mutableCandidate(0)
    let originalKeySize = c.key.utf8.count
    let originalValueSize = c.value.utf8.count
    let originalContentKeySize = c.contentKey.utf8.count
    let originalContentValueSize = c.contentValue.utf8.count
    let historyKey = (c.key.utf8.count > segment.key.utf8.count) ? c.key : segment.key
    let value = c.value
    let contentValue = c.contentValue
    let contentKey = c.contentKey
    var key = JapaneseUtil.fullWidthAsciiToHalfWidthAscii(historyKey)
    c.value = JapaneseUtil.fullWidthAsciiToHalfWidthAscii(value)
    c.contentValue = JapaneseUtil.fullWidthAsciiToHalfWidthAscii(contentValue)
    c.contentKey = JapaneseUtil.fullWidthAsciiToHalfWidthAscii(contentKey)
    c.key = key
    segment.setKey(key)

    // Ad-hoc rewrite for Numbers
    // Since number candidate is generative, i.e., any number can be
    // written by users, we normalize the value here. normalzied number
    // is used for the ranking tweaking based on history
    if key.utf8.count > 1 && key.bytesEqual(c.value) && key.bytesEqual(c.contentValue)
      && key.bytesEqual(c.key) && key.bytesEqual(c.contentKey)
      && Util.getScriptType(key) == .number && endsWithNumber(key)
    {
      key = String(decoding: key.utf8.suffix(1), as: UTF8.self)  // use the last digit only
      segment.setKey(key)
      c.value = key
      c.contentValue = key
      c.contentKey = key
    }
    if c.key.utf8.count != originalKeySize || c.value.utf8.count != originalValueSize
      || c.contentKey.utf8.count != originalContentKeySize
      || c.contentValue.utf8.count != originalContentValueSize
    {
      c.innerSegmentBoundary.removeAll()
    }
  }
}

/// Returns the vector of the inner segment's key.
private func getBoundaryInfo(_ c: Candidate) -> [Substring] {
  var ret: [Substring] = []
  for iter in c.innerSegments() {
    ret.append(iter.getKey())
  }
  return ret
}

private func boundaryInfoEqual(_ a: [Substring], _ b: [Substring]) -> Bool {
  a.count == b.count && zip(a, b).allSatisfy { $0.bytesEqual($1) }
}

/// Input is a list of FIRST_INNER_SEGMENT candidate, which is the first
/// segment of each n-best path.
/// Basic idea is that we can filter a candidate when we already added the
/// candidate with the same key and there is a cost gap
///
/// Example:
///   segment key: "わたしのなまえは"
///   candidates: {{"わたしの", "私の"}, {"わたしの", "渡しの"}, {"わたし",
///   "渡し"}}
/// Here,"渡しの" will be filtered if there is a cost gap from "私の"
private final class FirstInnerSegmentCandidateChecker {
  private let targetSegment: Segment
  private let costMaxDiff: Int
  private var minCost: Int? = nil
  private let trie = Trie<Bool>()

  init(_ targetSegment: Segment, _ costMaxDiff: Int) {
    self.targetSegment = targetSegment
    self.costMaxDiff = costMaxDiff
  }

  func isGoodCandidate(_ c: Candidate) -> Bool {
    if c.key.utf8.count != targetSegment.key.utf8.count && isPrefixAdded(c.value) {
      // Filter a candidate if its prefix is already added unless it is the
      // single segment candidate.
      return false
    }

    if let minCost, Int(c.cost) - minCost > costMaxDiff {
      return false
    }

    return true
  }

  func addEntry(_ c: Candidate) {
    let kPlaceholderValue = true
    trie.addEntry(c.value, kPlaceholderValue)

    if Util.containsScriptType(c.value, .kanji) {
      // Do not use non-kanji entry's cost. Sometimes it is too small.
      if let minCost {
        self.minCost = min(minCost, Int(c.cost))
      } else {
        minCost = Int(c.cost)
      }
    }
  }

  /// Returns true if the prefix of value has already added
  private func isPrefixAdded(_ value: String) -> Bool {
    var data: Bool? = nil
    var keyLength = 0
    return trie.longestMatch(value, &data, &keyLength)
  }
}

// Reasonably big cost. Cannot use INT_MAX because a new cost will be
// calculated based on kVeryBigCost.
private let kVeryBigCost = Int(Int32.max >> 2)

/// Runs viterbi algorithm at position |pos|.
/// |right_boundary| is the boundary of the current segment.
@inline(__always)
private func viterbiInternal(
  _ conn: CachingConnector, _ pos: Int, _ rightBoundary: Int, _ lattice: Lattice
) {
  let endNodes = lattice.endNodes(pos)
  for rnode in lattice.beginNodes(pos) {
    if Int(rnode.endPos) > rightBoundary {
      // Invalid rnode.
      rnode.prev = nil
      continue
    }

    conn.resetCacheIfNecessary(rnode.lid)

    if let constrainedPrev = rnode.constrainedPrev {
      // Constrained node.
      if constrainedPrev.prev == nil {
        rnode.prev = nil
      } else {
        rnode.prev = constrainedPrev
        rnode.cost = Int32(
          truncatingIfNeeded: Int(constrainedPrev.cost) + Int(rnode.wcost)
            + conn.getTransitionCost(constrainedPrev.rid, rnode.lid))
      }
      continue
    }

    // Find a valid node which connects to the rnode with minimum cost.
    var bestCost = kVeryBigCost
    var bestNode: Node? = nil
    for lnode in endNodes {
      if lnode.prev == nil {
        // Invalid lnode.
        continue
      }

      let cost = Int(lnode.cost) + conn.getTransitionCost(lnode.rid, rnode.lid)
      if cost < bestCost {
        bestCost = cost
        bestNode = lnode
      }
    }

    rnode.prev = bestNode
    rnode.cost = Int32(truncatingIfNeeded: bestCost + Int(rnode.wcost))
  }
}

// Mapping from lnode's rid to (cost, Node) of best way/cost, and vice versa.
// Note that, the average number of lid/rid variation is less than 30 in
// most cases. So, in order to avoid too many allocations for internal
// nodes of std::map, we use vector of key-value pairs.
private struct BestEntry {
  var first: Int
  var cost: Int
  var node: Node?
}

private func lowerBound(_ bestMap: [BestEntry], _ key: Int) -> Int {
  var lo = 0
  var hi = bestMap.count
  while lo < hi {
    let mid = (lo + hi) / 2
    if bestMap[mid].first < key {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  return lo
}

private func predictionViterbiInternalImpl(
  _ connector: CachingConnector, _ pos: Int, _ calcEndPos: Int, _ lattice: Lattice,
  _ lbest: inout [BestEntry], _ rbest: inout [BestEntry]
) {
  lbest.removeAll(keepingCapacity: true)
  let kInvalidCost = Int(Int32.max)

  for lnode in lattice.endNodes(pos) {
    let rid = Int(lnode.rid)
    let iter = lowerBound(lbest, rid)
    if iter == lbest.count || lbest[iter].first != rid {
      lbest.insert(BestEntry(first: rid, cost: Int(lnode.cost), node: lnode), at: iter)
    } else if Int(lnode.cost) < lbest[iter].cost {
      lbest[iter].cost = Int(lnode.cost)
      lbest[iter].node = lnode
    }
  }

  if lbest.isEmpty {
    return
  }

  rbest.removeAll(keepingCapacity: true)
  let beginNodes = lattice.beginNodes(pos)
  for rnode in beginNodes {
    if Int(rnode.endPos) > calcEndPos {
      continue
    }
    let lid = Int(rnode.lid)
    let iter = lowerBound(rbest, lid)
    if iter == rbest.count || rbest[iter].first != lid {
      rbest.insert(BestEntry(first: lid, cost: kInvalidCost, node: nil), at: iter)
    }
  }

  if rbest.isEmpty {
    return
  }

  for r in 0..<rbest.count {
    connector.resetCacheIfNecessary(UInt16(rbest[r].first))
    for l in 0..<lbest.count {
      let cost =
        lbest[l].cost
        + connector.getTransitionCost(UInt16(lbest[l].first), UInt16(rbest[r].first))
      if cost < rbest[r].cost {
        rbest[r].cost = cost
        rbest[r].node = lbest[l].node
      }
    }
  }

  for rnode in beginNodes {
    if Int(rnode.endPos) > calcEndPos {
      continue
    }
    let lid = Int(rnode.lid)
    let iter = lowerBound(rbest, lid)
    if iter == rbest.count || rbest[iter].first != lid || rbest[iter].node == nil {
      continue
    }

    rnode.cost = Int32(truncatingIfNeeded: rbest[iter].cost + Int(rnode.wcost))
    rnode.prev = rbest[iter].node
  }
}

public final class ImmutableConverter: ImmutableConverterInterface, Sendable {
  enum InsertCandidatesType {
    case multiSegments  // Normal conversion ("私の|名前は|中野です")
    case singleSegment  // Realtime conversion ("私の名前は中野です")
    // Insert only first segment for n-best path
    // ここでは着物を脱ぐ
    // ここで履物を脱ぐ
    // → ここでは, ここで
    case firstInnerSegment
  }

  private let dictionary: any DictionaryInterface
  private let suffixDictionary: any DictionaryInterface
  private let userDictionary: any UserDictionaryInterface
  private let connector: Connector
  private let segmenter: Segmenter
  private let posMatcher: PosMatcher
  private let posGroup: PosGroup
  private let suggestionFilter: any SuggestionFilterProtocol

  // Cache for POS ids.
  private let firstNameId: UInt16
  private let lastNameId: UInt16
  private let numberId: UInt16
  private let unknownId: UInt16

  // Cache for transition cost.
  private let lastToFirstNameTransitionCost: Int

  public init(
    dictionary: any DictionaryInterface,
    suffixDictionary: any DictionaryInterface,
    userDictionary: any UserDictionaryInterface,
    connector: Connector,
    segmenter: Segmenter,
    posMatcher: PosMatcher,
    posGroup: PosGroup,
    suggestionFilter: any SuggestionFilterProtocol
  ) {
    self.dictionary = dictionary
    self.suffixDictionary = suffixDictionary
    self.userDictionary = userDictionary
    self.connector = connector
    self.segmenter = segmenter
    self.posMatcher = posMatcher
    self.posGroup = posGroup
    self.suggestionFilter = suggestionFilter
    firstNameId = posMatcher.getFirstNameId()
    lastNameId = posMatcher.getLastNameId()
    numberId = posMatcher.getNumberId()
    unknownId = posMatcher.getUnknownId()
    lastToFirstNameTransitionCost = connector.getTransitionCost(lastNameId, firstNameId)
  }

  @inline(__always)
  private func getCost(_ lnode: Node, _ rnode: Node) -> Int {
    let kInvalidPenaltyCost = 100000
    if let constrainedPrev = rnode.constrainedPrev, lnode !== constrainedPrev {
      return kInvalidPenaltyCost
    }
    return connector.getTransitionCost(lnode.rid, rnode.lid) + Int(rnode.wcost)
  }

  func insertDummyCandidates(_ segment: Segment, _ expandSize: Int) {
    var lastCandidate: Candidate? =
      segment.candidatesSize == 0 ? nil : segment.mutableCandidate(segment.candidatesSize - 1)

    // Insert a dummy candidate whose content_value is katakana.
    // If functional_key() is empty, no need to make a dummy candidate.
    if segment.candidatesSize > 0 && segment.candidatesSize < expandSize
      && !segment.candidate(0).functionalKey.isEmpty
      && Util.getScriptType(segment.candidate(0).contentKey) == .hiragana,
      let last = lastCandidate
    {
      // Use last_candidate as a reference of cost.
      // Use top_candidate as a refarence of lid/rid and key/value.
      let top = segment.mutableCandidate(0)
      let newCandidate = segment.addCandidate()

      newCandidate.assign(from: top)
      newCandidate.contentValue = JapaneseUtil.hiraganaToKatakana(segment.candidate(0).contentKey)
      newCandidate.value = newCandidate.contentValue + top.functionalValue
      newCandidate.cost = last.cost &+ 1
      newCandidate.wcost = last.wcost &+ 1
      newCandidate.structureCost = last.structureCost &+ 1
      newCandidate.attributes = 0
      // We cannot copy inner_segment_boundary; see b/8109381.
      newCandidate.innerSegmentBoundary.removeAll()
      lastCandidate = newCandidate
    }

    // Insert a dummy hiragana candidate.
    if segment.candidatesSize == 0
      || (segment.candidatesSize < expandSize && Util.getScriptType(segment.key) == .hiragana)
    {
      let newCandidate = segment.addCandidate()

      if let last = lastCandidate {
        newCandidate.assign(from: last)
        // We cannot copy inner_segment_boundary; see b/8109381.
        newCandidate.innerSegmentBoundary.removeAll()
      }
      newCandidate.key = segment.key
      newCandidate.value = segment.key
      newCandidate.contentKey = segment.key
      newCandidate.contentValue = segment.key
      if let last = lastCandidate {
        newCandidate.cost = last.cost &+ 1
        newCandidate.wcost = last.wcost &+ 1
        newCandidate.structureCost = last.structureCost &+ 1
      }
      newCandidate.attributes = 0
      lastCandidate = newCandidate
      // One character hiragana/katakana will cause side effect.
      // Type "し" and choose "シ". After that, "しました" will become "シました".
      if Util.charsLen(newCandidate.key) <= 1 {
        newCandidate.attributes |= Attribute.contextSensitive
      }
    }

    // Insert a dummy katakana candidate.
    let katakanaValue = JapaneseUtil.hiraganaToKatakana(segment.key)
    if segment.candidatesSize > 0 && segment.candidatesSize < expandSize
      && Util.getScriptType(katakanaValue) == .katakana,
      let last = lastCandidate
    {
      let newCandidate = segment.addCandidate()
      newCandidate.key = segment.key
      newCandidate.value = katakanaValue
      newCandidate.contentKey = segment.key
      newCandidate.contentValue = katakanaValue
      newCandidate.cost = last.cost &+ 1
      newCandidate.wcost = last.wcost &+ 1
      newCandidate.structureCost = last.structureCost &+ 1
      newCandidate.lid = last.lid
      newCandidate.rid = last.rid
      if Util.charsLen(newCandidate.key) <= 1 {
        newCandidate.attributes |= Attribute.contextSensitive
      }
    }
  }

  private func applyResegmentRules(_ pos: Int, _ lattice: Lattice) {
    if resegmentArabicNumberAndSuffix(pos, lattice) {
      return
    }

    if resegmentPrefixAndArabicNumber(pos, lattice) {
      return
    }

    if resegmentPersonalName(pos, lattice) {
      return
    }
  }

  // Currently, only arabic_number + suffix patterns are resegmented
  // TODO(taku): consider kanji number into consideration
  private func resegmentArabicNumberAndSuffix(_ pos: Int, _ lattice: Lattice) -> Bool {
    lattice.withNodeInserter { inserter in
      for compoundNode in lattice.beginNodes(pos) {
        if !compoundNode.value.isEmpty && !compoundNode.key.isEmpty
          && posMatcher.isNumber(compoundNode.lid) && !posMatcher.isNumber(compoundNode.rid)
          && startsWithNumber(compoundNode.value) && startsWithNumber(compoundNode.key)
        {
          let (numberValue, suffixValue) = decomposeNumberAndSuffix(compoundNode.value)
          let (numberKey, suffixKey) = decomposeNumberAndSuffix(compoundNode.key)

          if suffixValue.isEmpty || suffixKey.isEmpty {
            continue
          }

          // not compatible
          if !numberValue.bytesEqual(numberKey) {
            // LOG(WARNING) << "Incompatible key/value number pair";
            continue
          }

          // do -1 so that resegmented nodes are boosted
          // over compound node.
          let wcost = max(compoundNode.wcost / 2 - 1, 0)

          let numberNode = lattice.newNode()
          numberNode.key = String(numberKey)
          numberNode.value = String(numberValue)
          numberNode.lid = compoundNode.lid
          numberNode.rid = 0  // 0 to 0 transition cost is 0
          numberNode.wcost = wcost
          numberNode.nodeType = .norNode

          // insert number into the lattice
          inserter.insert(pos, numberNode)

          let suffixNode = lattice.newNode()
          suffixNode.key = String(suffixKey)
          suffixNode.value = String(suffixValue)
          suffixNode.lid = 0
          suffixNode.rid = compoundNode.rid
          suffixNode.wcost = wcost
          suffixNode.nodeType = .norNode

          suffixNode.constrainedPrev = numberNode

          // insert suffix into the lattice
          inserter.insert(pos + numberNode.key.utf8.count, suffixNode)
        }
      }
      return inserter.isInserted
    }
  }

  private func resegmentPrefixAndArabicNumber(_ pos: Int, _ lattice: Lattice) -> Bool {
    lattice.withNodeInserter { inserter in
      for compoundNode in lattice.beginNodes(pos) {
        // Unlike ResegmentArabicNumberAndSuffix, we don't
        // check POS as words ending with Arabic numbers are pretty rare.
        if compoundNode.value.utf8.count > 1 && compoundNode.key.utf8.count > 1
          && !startsWithNumber(compoundNode.value) && !startsWithNumber(compoundNode.key)
          && endsWithNumber(compoundNode.value) && endsWithNumber(compoundNode.key)
        {
          let (prefixValue, numberValue) = decomposePrefixAndNumber(compoundNode.value)
          let (prefixKey, numberKey) = decomposePrefixAndNumber(compoundNode.key)

          if prefixValue.isEmpty || prefixKey.isEmpty {
            continue
          }

          // not compatible
          if !numberValue.bytesEqual(numberKey) {
            // LOG(WARNING) << "Incompatible key/value number pair";
            continue
          }

          // do -1 so that resegmented nodes are boosted
          // over compound node.
          let wcost = max(compoundNode.wcost / 2 - 1, 0)

          let prefixNode = lattice.newNode()
          prefixNode.key = String(prefixKey)
          prefixNode.value = String(prefixValue)
          prefixNode.lid = compoundNode.lid
          prefixNode.rid = 0  // 0 to 0 transition cost is 0
          prefixNode.wcost = wcost
          prefixNode.nodeType = .norNode

          // insert number into the lattice
          inserter.insert(pos, prefixNode)

          let numberNode = lattice.newNode()
          numberNode.key = String(numberKey)
          numberNode.value = String(numberValue)
          numberNode.lid = 0
          numberNode.rid = compoundNode.rid
          numberNode.wcost = wcost
          numberNode.nodeType = .norNode

          numberNode.constrainedPrev = prefixNode

          // insert number into the lattice
          inserter.insert(pos + prefixNode.key.utf8.count, numberNode)
        }
      }
      return inserter.isInserted
    }
  }

  private func resegmentPersonalName(_ pos: Int, _ lattice: Lattice) -> Bool {
    lattice.withNodeInserter { inserter in
      let beginNodes = lattice.beginNodes(pos)
      // find a combination of last_name and first_name, e.g. "田中麗奈".
      for compoundNode in beginNodes {
        // left word is last name and right word is first name
        if compoundNode.lid != lastNameId || compoundNode.rid != firstNameId {
          continue
        }

        let len = Util.charsLen(compoundNode.value)

        // Don't resegment one-word last_name/first_name like 林健,
        // as it would deliver side effect.
        if len <= 2 {
          continue
        }

        // Don't resegment if the value is katakana
        if Util.getScriptType(compoundNode.value) == .katakana {
          continue
        }

        // Do constrained Viterbi search inside the compound "田中麗奈".
        // Constraints:
        // 1. Concats of last_name and first_name should be "田中麗奈"
        // 2. consisting of two words (last_name and first_name)
        // 3. Segment-boundary exist between the two words.
        // 4.a Either (a) POS of lnode is last_name or (b) POS of rnode is
        //     fist_name (len >= 4)
        // 4.b Both (a) POS of lnode is last_name and (b) POS of rnode is
        //     fist_name (len == 3)
        var bestLastNameNode: Node? = nil
        var bestFirstNameNode: Node? = nil
        var bestCost = 0x7FFF_FFFF
        let compoundValueSize = compoundNode.value.utf8.count
        for lnode in beginNodes {
          // lnode(last_name) is a prefix of compound, Constraint 1.
          if compoundValueSize > lnode.value.utf8.count
            && compoundNode.key.utf8.count > lnode.key.utf8.count
            && compoundNode.value.hasBytePrefix(lnode.value)
          {
            // rnode(first_name) is a suffix of compound, Constraint 1.
            for rnode in lattice.beginNodes(pos + lnode.key.utf8.count) {
              if lnode.value.utf8.count + rnode.value.utf8.count == compoundValueSize
                && (lnode.value + rnode.value).bytesEqual(compoundNode.value)
                && segmenter.isBoundary(lnode, rnode, false)
              {  // Constraint 3.
                let cost = Int(lnode.wcost) + getCost(lnode, rnode)
                if cost < bestCost {  // choose the smallest ones
                  bestLastNameNode = lnode
                  bestFirstNameNode = rnode
                  bestCost = cost
                }
              }
            }
          }
        }

        // No valid first/last names are found
        guard let bestFirstNameNode, let bestLastNameNode else {
          continue
        }

        // Constraint 4.a
        if len >= 4
          && (bestLastNameNode.lid != lastNameId && bestFirstNameNode.rid != firstNameId)
        {
          continue
        }

        // Constraint 4.b
        if len == 3
          && (bestLastNameNode.lid != lastNameId || bestFirstNameNode.rid != firstNameId)
        {
          continue
        }

        // Insert LastName and FirstName as independent nodes.
        // Duplications will be removed in nbest enumerations.
        // word costs are calculated from compound node by assuming that
        // transition cost is 0.
        //
        // last_name_cost + transition_cost + first_name_cost == compound_cost
        // last_name_cost == first_name_cost
        // i.e.,
        // last_name_cost = first_name_cost =
        // (compound_cost - transition_cost) / 2;
        // do -1 so that resegmented nodes are boosted over compound node.
        let wcost = Int32(
          truncatingIfNeeded: max((Int(compoundNode.wcost) - lastToFirstNameTransitionCost) / 2 - 1, 0))

        let lastNameNode = lattice.newNode()
        lastNameNode.key = bestLastNameNode.key
        lastNameNode.value = bestLastNameNode.value
        lastNameNode.lid = compoundNode.lid
        lastNameNode.rid = lastNameId
        lastNameNode.wcost = wcost
        lastNameNode.nodeType = .norNode

        // insert last_name into the lattice
        inserter.insert(pos, lastNameNode)

        let firstNameNode = lattice.newNode()
        firstNameNode.key = bestFirstNameNode.key
        firstNameNode.value = bestFirstNameNode.value
        firstNameNode.lid = firstNameId
        firstNameNode.rid = compoundNode.rid
        firstNameNode.wcost = wcost
        firstNameNode.nodeType = .norNode

        firstNameNode.constrainedPrev = lastNameNode

        // insert first_name into the lattice
        inserter.insert(pos + lastNameNode.key.utf8.count, firstNameNode)
      }
      return inserter.isInserted
    }
  }

  private func lookup(
    _ beginPos: Int, _ options: ConversionOptions, _ isReverse: Bool, _ lattice: Lattice
  ) -> [Node] {
    let key = lattice.key
    let keySubstr = String(key.byteSubstring(from: min(beginPos, key.utf8.count)))

    let builder = BaseNodeListBuilder(lattice.nodeAllocator, kMaxNodesSize)
    if isReverse {
      dictionary.lookupReverse(keySubstr, options: options, callback: builder)
    } else {
      dictionary.lookupPrefix(keySubstr, options: options, callback: builder)
    }
    addCharacterTypeBasedNodes(keySubstr, lattice, builder)

    return builder.result
  }

  private func addCharacterTypeBasedNodes(
    _ keySubstr: String, _ lattice: Lattice, _ builder: BaseNodeListBuilder
  ) {
    let scalars = keySubstr.unicodeScalars
    var it = scalars.startIndex
    precondition(it != scalars.endIndex)
    let codepoint = Char32(scalars[it].value)

    let firstScriptType = Util.getScriptType(codepoint)
    let firstFormType = Util.getFormType(codepoint)

    // Add 1 character node. It can be either UnknownId or NumberId.
    do {
      let newNode = lattice.newNode()
      if firstScriptType == .number {
        newNode.lid = numberId
        newNode.rid = numberId
      } else {
        newNode.lid = unknownId
        newNode.rid = unknownId
      }

      newNode.wcost = kMaxCost
      let firstChar = String(scalars[it])
      newNode.value = firstChar
      newNode.key = firstChar
      newNode.nodeType = .norNode
      builder.appendToResult(newNode)

      if firstScriptType == .number {
        newNode.wcost = kDefaultNumberCost
        return
      }

      if firstScriptType != .alphabet && firstScriptType != .katakana {
        return
      }
    }  // scope out |new_node|

    // group by same char type
    var numChar = 1
    it = scalars.index(after: it)
    while it != scalars.endIndex {
      let nextCodepoint = Char32(scalars[it].value)
      if firstScriptType != Util.getScriptType(nextCodepoint)
        || firstFormType != Util.getFormType(nextCodepoint)
      {
        break
      }
      it = scalars.index(after: it)
      numChar += 1
    }

    if numChar > 1 {
      let newNode = lattice.newNode()
      if firstScriptType == .number {
        newNode.lid = numberId
        newNode.rid = numberId
      } else {
        newNode.lid = unknownId
        newNode.rid = unknownId
      }
      newNode.wcost = kMaxCost / 2
      let keySubstrUpToIt = String(keySubstr[keySubstr.startIndex..<it])
      newNode.value = keySubstrUpToIt
      newNode.key = keySubstrUpToIt
      newNode.nodeType = .norNode
      builder.appendToResult(newNode)
    }
  }

  private func makeCachingConnector(_ options: ConversionOptions) -> CachingConnector {
    if options.particleOmissionTransitionCostBonus == 0 {
      return CachingConnector(hasBonus: false, connector, 0, posMatcher)
    } else {
      return CachingConnector(
        hasBonus: true, connector, options.particleOmissionTransitionCostBonus, posMatcher)
    }
  }

  func viterbi(_ options: ConversionOptions, _ segments: Segments, _ lattice: Lattice) -> Bool {
    let key = lattice.key

    // Process BOS.
    do {
      let bosNode = lattice.bosNode

      let rightBoundary = segments.segment(0).key.utf8.count
      for rnode in lattice.beginNodes(0) {
        if Int(rnode.endPos) > rightBoundary {
          // Invalid rnode.
          continue
        }

        rnode.prev = bosNode
        rnode.cost = Int32(
          truncatingIfNeeded: Int(bosNode.cost) + connector.getTransitionCost(bosNode.rid, rnode.lid)
            + Int(rnode.wcost))
      }
    }

    var leftBoundary = 0

    do {
      let conn = makeCachingConnector(options)
      // Specialization for the first segment.
      // Don't run on the left boundary (the connection with BOS node),
      // because it is already run above.
      do {
        let rightBoundary = leftBoundary + segments.segment(0).key.utf8.count
        var pos = leftBoundary + 1
        while pos < rightBoundary {
          viterbiInternal(conn, pos, rightBoundary, lattice)
          pos += 1
        }
        leftBoundary = rightBoundary
      }
      // The condition to break is in the loop.
      for segment in segments.all.dropFirst() {
        // Run Viterbi for each position the segment.
        let rightBoundary = leftBoundary + segment.key.utf8.count
        var pos = leftBoundary
        while pos < rightBoundary {
          viterbiInternal(conn, pos, rightBoundary, lattice)
          pos += 1
        }
        leftBoundary = rightBoundary
      }
    }

    // Process EOS.
    do {
      let eosNode = lattice.eosNode

      leftBoundary = key.utf8.count - (segments.all.last?.key.utf8.count ?? 0)
      // Find a valid node which connects to the rnode with minimum cost.
      var bestCost = kVeryBigCost
      var bestNode: Node? = nil
      for lnode in lattice.endNodes(key.utf8.count) {
        if lnode.prev == nil {
          // Invalid lnode.
          continue
        }

        let cost = Int(lnode.cost) + connector.getTransitionCost(lnode.rid, eosNode.lid)
        if cost < bestCost {
          bestCost = cost
          bestNode = lnode
        }
      }

      eosNode.prev = bestNode
      eosNode.cost = Int32(truncatingIfNeeded: bestCost + Int(eosNode.wcost))
    }

    return traverseBackward(lattice)
  }

  /// Traverse the node from end to begin.
  private func traverseBackward(_ lattice: Lattice) -> Bool {
    var node = lattice.eosNode
    var prev: Node? = nil
    while let p = node.prev {
      prev = p
      p.next = node
      node = p
    }

    if lattice.bosNode !== prev {
      // LOG(WARNING) << "cannot make lattice";
      return false
    }

    return true
  }

  // faster Viterbi algorithm for prediction
  //
  // Run simple Viterbi algorithm with contracting the same lid and rid.
  // Because the original Viterbi has speciall nodes, we should take it
  // consideration.
  // 1. CONNECTED nodes: are normal nodes.
  // 2. WEAK_CONNECTED nodes: don't occur in prediction, so we do not have to
  //    consider about them.
  // 3. NOT_CONNECTED nodes: occur when they are between history nodes and
  //    normal nodes.
  // For NOT_CONNECTED nodes, we should run Viterbi for history nodes first,
  // and do it for normal nodes second. The function "PredictionViterbiSub"
  // runs Viterbi for positions between calc_begin_pos and calc_end_pos,
  // inclusive.
  //
  // We cannot apply this function in suggestion because in suggestion there
  // are WEAK_CONNECTED nodes and this function is not designed for them.
  private func predictionViterbi(
    _ options: ConversionOptions, _ segments: Segments, _ lattice: Lattice
  ) -> Bool {
    let keyLength = lattice.key.utf8.count
    var historyLength = 0
    for segment in segments.historySegments {
      historyLength += segment.key.utf8.count
    }
    predictionViterbiInternal(options, 0, historyLength, lattice)
    predictionViterbiInternal(options, historyLength, keyLength, lattice)

    return traverseBackward(lattice)
  }

  private func predictionViterbiInternal(
    _ options: ConversionOptions, _ calcBeginPos: Int, _ calcEndPos: Int, _ lattice: Lattice
  ) {
    var lbest: [BestEntry] = []
    var rbest: [BestEntry] = []
    lbest.reserveCapacity(128)
    rbest.reserveCapacity(128)

    let conn = makeCachingConnector(options)
    var pos = calcBeginPos
    while pos <= calcEndPos {
      predictionViterbiInternalImpl(conn, pos, calcEndPos, lattice, &lbest, &rbest)
      pos += 1
    }
  }

  func makeLattice(_ options: ConversionOptions, _ segments: Segments, _ lattice: Lattice) -> Bool {
    if segments.segmentsSize >= kMaxSegmentsSize {
      // LOG(WARNING) << "too many segments";
      return false
    }

    normalizeHistorySegments(segments)

    let isReverse = options.requestType == .reverseConversion

    let isPrediction = options.requestType == .suggestion || options.requestType == .prediction

    // In suggestion mode, ImmutableConverter will not accept
    // multiple-segments. The result always consists of one segment.
    if isReverse || isPrediction {
      let conversionSegments = segments.conversionSegments
      if conversionSegments.count != 1 || conversionSegments.first?.segmentType != .free {
        // LOG(WARNING) << "ImmutableConverter doesn't support constrained requests";
        return false
      }
    }

    // Make the conversion key.
    var conversionKey = ""
    for segment in segments.conversionSegments {
      conversionKey += segment.key
    }
    let maxCharLen = isReverse ? kMaxCharLengthForReverseConversion : kMaxCharLength
    if conversionKey.isEmpty || conversionKey.utf8.count >= maxCharLen {
      // LOG(WARNING) << "Conversion key is empty or too long: " << conversion_key;
      return false
    }

    // Make the history key.
    var historyKey = ""
    for segment in segments.historySegments {
      historyKey += segment.key
    }
    // Check if the total length (length of history_key + conversion_key)
    // doesn't exceed the maximum key length. If it exceeds the limit, we
    // simply clears such useless history segments, which is acceptable because
    // such cases rarely happen in normal use cases.
    if historyKey.utf8.count + conversionKey.utf8.count >= maxCharLen {
      // LOG(WARNING) << "Clear history segments due to the limit of key length.";
      segments.clearHistorySegments()
      historyKey = ""
    }

    lattice.setKey(historyKey + conversionKey, bosId: options.bosId)

    if isReverse {
      // Reverse lookup for each prefix string in key is slow with current
      // implementation, so run it for them at once and cache the result.
      dictionary.populateReverseLookupCache(lattice.key)
    }

    var isValidLattice = true
    // Perform the main part of lattice construction.
    if !makeLatticeNodesForHistorySegments(segments, options, lattice)
      || lattice.endNodes(historyKey.utf8.count).isEmpty
    {
      isValidLattice = false
    }

    // Can not apply key corrector to invalid lattice.
    if isValidLattice {
      makeLatticeNodesForConversionSegments(segments, options, historyKey, lattice)
    }

    if isReverse {
      // No reverse look up will happen afterwards.
      dictionary.clearReverseLookupCache()
    }

    if !isValidLattice {
      // Safely bail out, since reverse look up cache was released already.
      return false
    }

    if lattice.endNodes(lattice.key.utf8.count).isEmpty {
      // LOG(WARNING) << "cannot build lattice from input";
      return false
    }

    applyPrefixSuffixPenalty(options, conversionKey, lattice)

    // Re-segment personal-names, numbers ...etc
    if options.requestType == .conversion {
      resegment(segments, historyKey, conversionKey, lattice)
    }

    return true
  }

  private func makeLatticeNodesForHistorySegments(
    _ segments: Segments, _ options: ConversionOptions, _ lattice: Lattice
  ) -> Bool {
    let isReverse = options.requestType == .reverseConversion
    let historySegmentsSize = segments.historySegmentsSize

    var segmentsPos = 0

    for s in 0..<historySegmentsSize {
      let segment = segments.segment(s)
      if segment.segmentType != .history && segment.segmentType != .submitted {
        // LOG(WARNING) << "inconsistent history";
        return false
      }
      if segment.key.isEmpty {
        // LOG(WARNING) << "invalid history: key is empty";
        return false
      }
      let candidate = segment.candidate(0)

      // Add a virtual nodes corresponding to HISTORY segments.
      let rnode = lattice.newNode()
      rnode.lid = candidate.lid
      rnode.rid = candidate.rid
      rnode.wcost = 0
      rnode.value = candidate.value
      rnode.key = segment.key
      rnode.nodeType = .hisNode
      lattice.insert(segmentsPos, rnode)

      // For the last history segment,  we also insert a new node having
      // EOS part-of-speech. Viterbi algorithm will find the
      // best path from rnode(context) and rnode2(EOS).
      if s + 1 == historySegmentsSize && candidate.rid != 0 {
        let rnode2 = lattice.newNode()
        rnode2.lid = candidate.lid
        rnode2.rid = 0  // 0 is BOS/EOS

        // This cost was originally set to 1500.
        // It turned out this penalty was so strong that it caused some
        // undesirable conversions like "の-なまえ" -> "の-な前" etc., so we
        // changed this to 0.
        // Reducing the cost promotes context-unaware conversions, and this may
        // have some unexpected side effects.
        // TODO(team): Figure out a better way to set the cost using
        // boundary.def-like approach.
        rnode2.wcost = 0
        rnode2.value = candidate.value
        rnode2.key = segment.key
        rnode2.nodeType = .hisNode
        lattice.insert(segmentsPos, rnode2)
      }

      // Dictionary lookup for the candidates which are
      // overlapping between history and conversion.
      // Check only the last history segment at this moment.
      //
      // Example: history "おいかわ(及川)", conversion: "たくや"
      // Here, try to find "おいかわたくや(及川卓也)" from dictionary
      // and insert "卓也" as a new word node with a modified cost
      //
      // Note: The overlapping lookup is disabled for prediction, because it
      // can produce noisy realtime candidates such as "て配" for the history
      // "に", which comes from "にて" + "配".
      // The bigram-like lookup ("卓也" from "及川") is covered in
      // dictionary_predictor.
      let isPrediction = options.requestType == .suggestion || options.requestType == .prediction
      if !isPrediction && s + 1 == historySegmentsSize {
        let rnodeKeySize = rnode.key.utf8.count
        let rnodeValueSize = rnode.value.utf8.count
        for compoundNode in lookup(segmentsPos, options, isReverse, lattice) {
          // No overlaps
          if compoundNode.key.utf8.count <= rnodeKeySize
            || compoundNode.value.utf8.count <= rnodeValueSize
            || !compoundNode.key.hasBytePrefix(rnode.key)
            || !compoundNode.value.hasBytePrefix(rnode.value)
          {
            // not a prefix
            continue
          }

          // Must be in the same POS group.
          // http://b/issue?id=2977618
          if posGroup.getPosGroup(candidate.lid) != posGroup.getPosGroup(compoundNode.lid) {
            continue
          }

          // make new virtual node
          let newNode = lattice.newNode()

          // get the suffix part ("たくや/卓也")
          newNode.key = String(compoundNode.key.byteSubstring(from: rnodeKeySize))
          newNode.value = String(compoundNode.value.byteSubstring(from: rnodeValueSize))

          // rid/lid are derived from the compound.
          // lid is just an approximation
          newNode.rid = compoundNode.rid
          newNode.lid = compoundNode.lid
          newNode.nodeType = .norNode
          newNode.attributes |= UInt16(truncatingIfNeeded: Attribute.contextSensitive)

          // New cost recalcuration:
          //
          // compound_node->wcost * (candidate len / compound_node len)
          // - trans(candidate.rid, new_node.lid)
          // (int * size_t / size_t: evaluated in size_t in C++.)
          let scaled =
            UInt64(bitPattern: Int64(compoundNode.wcost)) &* UInt64(candidate.value.utf8.count)
            / UInt64(compoundNode.value.utf8.count)
          newNode.wcost = Int32(
            truncatingIfNeeded: Int64(bitPattern: scaled)
              - Int64(connector.getTransitionCost(candidate.rid, newNode.lid)))

          newNode.constrainedPrev = rnode

          // Added as new node
          lattice.insert(segmentsPos + rnodeKeySize, newNode)
        }
      }

      // update segment pos
      segmentsPos += rnode.key.utf8.count
    }
    return true
  }

  private func makeLatticeNodesForConversionSegments(
    _ segments: Segments, _ options: ConversionOptions, _ historyKey: String, _ lattice: Lattice
  ) {
    let key = lattice.key
    let isConversion = options.requestType == .conversion
    // Do not use KeyCorrector if user changes the boundary.
    // http://b/issue?id=2804996
    var keyCorrector: KeyCorrector? = nil
    if isConversion && !segments.resized {
      var mode = KeyCorrector.InputMode.roman
      if options.inputMode == .kana {
        mode = .kana
      }
      keyCorrector = KeyCorrector(key, mode, historyKey.utf8.count)
    }

    let isReverse = options.requestType == .reverseConversion
    let keySize = key.utf8.count
    var pos = historyKey.utf8.count
    while pos < keySize {
      defer { pos += 1 }
      if lattice.endNodes(pos).isEmpty { continue }

      let rnodes = lookup(pos, options, isReverse, lattice)
      // If history key is NOT empty and user input seems to starts with
      // a particle ("はにで..."), mark the node as STARTS_WITH_PARTICLE.
      // We change the segment boundary if STARTS_WITH_PARTICLE attribute
      // is assigned.
      if !historyKey.isEmpty && pos == historyKey.utf8.count {
        for node in rnodes {
          if posMatcher.isAcceptableParticleAtBeginOfSegment(node.lid) && node.lid == node.rid {
            // not a compound.
            node.attributes |= Node.Attribute.startsWithParticle
          }
        }
      }
      lattice.insert(pos, rnodes)
      insertCorrectedNodes(pos, key, options, keyCorrector, dictionary, lattice)
    }
  }

  /// Fixes for "好む" vs "この|無", "大|代" vs "代々" preferences.
  /// If the last node ends with "prefix", give an extra
  /// wcost penalty. In this case  "無" doesn't tend to appear at
  /// user input.
  private func applyPrefixSuffixPenalty(
    _ options: ConversionOptions, _ conversionKey: String, _ lattice: Lattice
  ) {
    let keySize = lattice.key.utf8.count

    if !options.disablePrefixPenalty {
      for node in lattice.beginNodes(keySize - conversionKey.utf8.count) {
        // TODO(taku):
        // We might be able to tweak the penalty according to
        // the size of history segments.
        // If history-segments is non-empty, we can make the
        // penalty smaller so that history context is more likely
        // selected.
        node.wcost &+= segmenter.getPrefixPenalty(node.lid)
      }
    }

    for node in lattice.endNodes(keySize) {
      node.wcost &+= segmenter.getSuffixPenalty(node.rid)
    }
  }

  private func resegment(
    _ segments: Segments, _ historyKey: String, _ conversionKey: String, _ lattice: Lattice
  ) {
    let historySize = historyKey.utf8.count
    for pos in historySize..<(historySize + conversionKey.utf8.count) {
      applyResegmentRules(pos, lattice)
    }

    // Enable constrained node.
    var segmentsPos = 0
    for segment in segments.all {
      if segment.segmentType == .fixedValue {
        let candidate = segment.candidate(0)
        let rnode = lattice.newNode()
        rnode.lid = candidate.lid
        rnode.rid = candidate.rid
        rnode.wcost = kMinCost
        rnode.value = candidate.value
        rnode.key = segment.key
        rnode.nodeType = .conNode
        lattice.insert(segmentsPos, rnode)
      }
      segmentsPos += segment.key.utf8.count
    }
  }

  /// Helper function for InsertCandidates().
  /// Returns true if |node| is valid node for segment end.
  func isSegmentEndNode(
    _ options: ConversionOptions, _ segments: Segments, _ node: Node, _ group: [UInt16],
    _ isSingleSegment: Bool
  ) -> Bool {
    guard let next = node.next else {
      preconditionFailure("a segment end node is linked to the next node")
    }
    if next.nodeType == .eosNode {
      return true
    }

    // In reverse conversion, group consecutive white spaces into one segment.
    // For example, "ほん むりょう" -> "ほん", " ", "むりょう".
    if options.requestType == .reverseConversion {
      let thisNodeIsWs = containsWhiteSpacesOnly(node.key)
      let nextNodeIsWs = containsWhiteSpacesOnly(next.key)
      if thisNodeIsWs {
        return !nextNodeIsWs
      }
      if nextNodeIsWs {
        return true
      }
      // If this and next nodes are both non-white spaces, fall back to the
      // subsequent logic.
    }

    let oldSegment = segments.segment(Int(group[Int(node.beginPos)]))
    // |node| and |node->next| should be in same segment due to FIXED_BOUNDAY
    // |node->next| is NOT a boundary. Very strong constraint.
    if group[Int(node.beginPos)] == group[Int(next.beginPos)]
      && oldSegment.segmentType == .fixedBoundary
    {
      return false
    }

    // |node->next| is a boundary. Very strong constraint.
    if group[Int(node.beginPos)] != group[Int(next.beginPos)] {
      return true
    }

    // CON_NODE is generated for FIXED_VALUE candidate.
    if node.nodeType == .conNode {
      return true
    }

    // Grammatically segmented.
    if segmenter.isBoundary(node, next, isSingleSegment) {
      return true
    }

    return false
  }

  /// Helper function for InsertCandidates().
  /// Returns the segment for inserting candidates.
  private func getInsertTargetSegment(
    _ lattice: Lattice, _ group: [UInt16], _ type: InsertCandidatesType, _ beginPos: Int,
    _ node: Node, _ segments: Segments
  ) -> Segment {
    if type != .multiSegments {
      // Realtime conversion that produces only one segment.
      return segments.mutableSegment(segments.segmentsSize - 1)
    }

    // 'Normal' conversion. Add new segment and initialize it.
    let segment = segments.addSegment()
    segment.clearCandidates()
    segment.setKey(lattice.key.byteSubstring(from: beginPos, length: Int(node.endPos) - beginPos))
    let oldSegment = segments.segment(Int(group[Int(node.beginPos)]))
    segment.setSegmentType(oldSegment.segmentType)
    return segment
  }

  private func insertCandidates(
    _ options: ConversionOptions, _ segments: Segments, _ lattice: Lattice, _ group: [UInt16],
    _ maxCandidatesSize: Int, _ type: InsertCandidatesType
  ) {
    let conn = makeCachingConnector(options)
    insertCandidatesImpl(conn, options, segments, lattice, group, maxCandidatesSize, type)
  }

  private func insertCandidatesImpl(
    _ conn: CachingConnector, _ options: ConversionOptions, _ segments: Segments,
    _ lattice: Lattice, _ group: [UInt16], _ maxCandidatesSize: Int, _ type: InsertCandidatesType
  ) {
    // skip HIS_NODE(s)
    var prev = lattice.bosNode
    var n = lattice.bosNode.next
    while let node = n, let next = node.next, node.nodeType == .hisNode {
      prev = node
      n = next
    }

    let expandSize = min(max(maxCandidatesSize, 1), 512)

    let isSingleSegment = type == .singleSegment || type == .firstInnerSegment

    let nbestGenerator = NBestGenerator(
      userDictionary, segmenter, conn, posMatcher, lattice, suggestionFilter)

    var originalKey = ""
    for segment in segments.conversionSegments {
      originalKey += segment.key
    }

    var beginPos = Int.max  // std::string::npos
    var current = prev.next
    while let node = current, let next = node.next {
      defer { current = next }
      if beginPos == Int.max {
        beginPos = Int(node.beginPos)
      }

      if !isSegmentEndNode(options, segments, node, group, isSingleSegment) {
        continue
      }

      let segment = getInsertTargetSegment(lattice, group, type, beginPos, node, segments)

      var nbestOptions = NBestGenerator.Options()
      if type == .singleSegment || type == .firstInnerSegment {
        // For real time conversion.
        nbestOptions.boundaryMode = .onlyEdge
        nbestOptions.candidateMode |= NBestGenerator.CandidateMode.fillInnerSegmentInfo
      } else if segment.segmentType == .fixedBoundary {
        // Boundary is specified. Skip boundary check in n-best generator.
        nbestOptions.boundaryMode = .onlyMid
      }
      if type == .firstInnerSegment {
        // Inserts only first segment from realtime conversion path.
        nbestOptions.candidateMode |= NBestGenerator.CandidateMode.buildFromOnlyFirstInnerSegment
        nbestOptions.candidateMode |= NBestGenerator.CandidateMode.fillInnerSegmentInfo
      }
      nbestGenerator.reset(prev, next, nbestOptions)
      nbestGenerator.setCandidates(options, originalKey, expandSize, segment)

      if type == .multiSegments || type == .singleSegment {
        insertDummyCandidates(segment, expandSize)
      }

      if node.nodeType == .conNode {
        segment.setSegmentType(.fixedValue)
      }

      beginPos = Int.max
      prev = node
    }
  }

  private func makeSegments(_ options: ConversionOptions, _ lattice: Lattice, _ segments: Segments)
    -> Bool
  {
    let group = makeGroup(segments)
    let type = options.requestType

    if type == .conversion || type == .reverseConversion {
      insertCandidatesForConversion(options, lattice, group, segments)
    } else {
      insertCandidatesForPrediction(options, lattice, group, segments)
    }

    return true
  }

  private func insertCandidatesForConversion(
    _ options: ConversionOptions, _ lattice: Lattice, _ group: [UInt16], _ segments: Segments
  ) {
    // Currently, we assume that REVERSE_CONVERSION only
    // requires 1 result.
    // TODO(taku): support to set the size on REVESER_CONVERSION mode.
    let maxCandidatesSize =
      (options.requestType == .reverseConversion) ? 1 : options.maxConversionCandidatesSize

    // InsertCandidates inserts new segments after the existing
    // conversion segments. So we have to erase old conversion segments.
    // We have to keep old segments for calling InsertCandidates because
    // we need segment constraints like FIXED_BOUNDARY.
    // TODO(toshiyuki): We want more beautiful structure.
    let oldConversionSegmentsSize = segments.conversionSegmentsSize
    insertCandidates(options, segments, lattice, group, maxCandidatesSize, .multiSegments)
    if oldConversionSegmentsSize > 0 {
      segments.eraseSegments(segments.historySegmentsSize, oldConversionSegmentsSize)
    }
  }

  private func insertCandidatesForRealtimeWithCandidateChecker(
    _ options: ConversionOptions, _ lattice: Lattice, _ group: [UInt16], _ segments: Segments
  ) {
    let kSingleSegmentCharCoverage = 12
    let targetSegment = segments.mutableConversionSegment(0)
    var added = Set<[UInt8]>()  // flat_hash_set<std::string> (bytewise)
    let tmpSegments = segments.copy()
    do {
      // Candidates for the whole path
      let kMaxSize = 3
      insertCandidates(options, tmpSegments, lattice, group, kMaxSize, .singleSegment)

      // At least one candidate should be added.
      // Skip to add the similar candidates unless the char coverage is still
      // available.
      let topCand = tmpSegments.conversionSegment(0).candidate(0)
      let topBoundary = getBoundaryInfo(topCand)
      var remainingCharCoverage = kSingleSegmentCharCoverage
      for i in 0..<tmpSegments.conversionSegment(0).candidatesSize {
        let c = tmpSegments.conversionSegment(0).candidate(i)
        let kCostDiff = 2302  // 500*log(100)
        if Int(c.cost) - Int(topCand.cost) > kCostDiff {
          continue
        }
        if i != 0 && boundaryInfoEqual(getBoundaryInfo(c), topBoundary)
          && remainingCharCoverage < 0
        {
          // Skip to add the similar candidates when there is no remaining
          // coverage.
          continue
        }
        let candidate = targetSegment.addCandidate()
        candidate.assign(from: c)
        added.insert(Array(c.value.utf8))
        remainingCharCoverage -= Util.charsLen(c.value)
      }
    }
    tmpSegments.mutableConversionSegment(0).clearCandidates()

    do {
      // Candidates for the first segment of each n-best path.
      // int - size_t is evaluated in size_t in C++: a negative difference
      // wraps around (and is clamped to 512 in InsertCandidates).
      let remaining = options.maxConversionCandidatesSize - targetSegment.candidatesSize
      insertCandidates(
        options, tmpSegments, lattice, group, remaining < 0 ? Int.max : remaining,
        .firstInnerSegment)
      let kMaxCostDiffForFirstInnerSegment = 3107  // 500*log(500)
      let checker = FirstInnerSegmentCandidateChecker(
        targetSegment, kMaxCostDiffForFirstInnerSegment)
      for i in 0..<tmpSegments.conversionSegment(0).candidatesSize {
        let c = tmpSegments.mutableConversionSegment(0).mutableCandidate(i)
        if added.contains(Array(c.value.utf8)) {
          continue
        }
        if c.key.utf8.count != targetSegment.key.utf8.count {
          // Explicitly add suffix penalty, since the penalty is not added for
          // non end nodes.
          let suffixPenalty = segmenter.getSuffixPenalty(c.rid)
          c.wcost &+= suffixPenalty
          c.cost &+= suffixPenalty
        }

        if !checker.isGoodCandidate(c) {
          continue
        }
        let candidate = targetSegment.addCandidate()
        candidate.assign(from: c)
        checker.addEntry(c)
        added.insert(Array(c.value.utf8))
      }
    }
  }

  private func insertCandidatesForPrediction(
    _ options: ConversionOptions, _ lattice: Lattice, _ group: [UInt16], _ segments: Segments
  ) {
    let maxCandidatesSize = options.maxConversionCandidatesSize

    if !options.createPartialCandidates {
      // Desktop (or physical keyboard / handwriting in Mobile)
      insertCandidates(options, segments, lattice, group, maxCandidatesSize, .singleSegment)
      return
    }

    // Mobile
    insertCandidatesForRealtimeWithCandidateChecker(options, lattice, group, segments)
  }

  func makeGroup(_ segments: Segments) -> [UInt16] {
    var group: [UInt16] = []
    for i in 0..<segments.segmentsSize {
      for _ in 0..<segments.segment(i).key.utf8.count {
        group.append(UInt16(truncatingIfNeeded: i))
      }
    }
    group.append(UInt16(truncatingIfNeeded: segments.segmentsSize))
    return group
  }

  /// Accepts the internal lattice structure for debugging.
  public func convert(_ options: ConversionOptions, _ segments: Segments, _ lattice: Lattice) -> Bool {
    let isPrediction = options.requestType == .prediction || options.requestType == .suggestion

    if !makeLattice(options, segments, lattice) {
      // LOG(WARNING) << "could not make lattice";
      return false
    }

    if isPrediction {
      if !predictionViterbi(options, segments, lattice) {
        // LOG(WARNING) << "prediction_viterbi failed";
        return false
      }
    } else {
      if !viterbi(options, segments, lattice) {
        // LOG(WARNING) << "viterbi failed";
        return false
      }
    }

    if !makeSegments(options, lattice, segments) {
      // LOG(WARNING) << "make segments failed";
      return false
    }

    return true
  }

  public func convert(_ options: ConversionOptions, _ segments: Segments) -> Bool {
    let lattice = Lattice()
    return convert(options, segments, lattice)
  }
}
