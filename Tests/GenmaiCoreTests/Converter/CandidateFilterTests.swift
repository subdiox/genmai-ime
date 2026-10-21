// Port of mozc/src/converter/candidate_filter_test.cc (3.35.6354).

import Testing
@testable import GenmaiCore

private let kRequestTypes: [RequestType] = [
  .conversion,
  .prediction,
  .suggestion,
  .partialPrediction,
  .partialSuggestion,
  // Type REVERSE_CONVERSION is tested separately.
]

@Suite(.enabled(if: ConverterCoreTestSupport.hasMockData, ConverterCoreTestSupport.mockDataMissing))
final class CandidateFilterTests {
  private let posMatcher: PosMatcher
  private let mockUserDictionary = MockUserDictionary()
  private let suggestionFilter: TestSuggestionFilter
  /// Keeps the test nodes alive (C++ node arena).
  private var nodeArena: [Node] = []

  init() throws {
    let dm = try ConverterCoreTestSupport.mockDataManager()
    posMatcher = PosMatcher(dm.getPosMatcherData())
    suggestionFilter = try TestSuggestionFilter(dm.getSuggestionFilterData())
  }

  private func getDefaultNodes() -> [Node] {
    let n1 = newNode()
    n1.value = "てすと"
    n1.lid = posMatcher.getUnknownId()
    n1.rid = posMatcher.getUnknownId()

    let n2 = newNode()
    n2.value = "てすと"
    n2.lid = posMatcher.getFunctionalId()
    n2.rid = posMatcher.getFunctionalId()
    return [n1, n2]
  }

  private func newNode() -> Node {
    let n = Node()
    nodeArena.append(n)
    return n
  }

  private func newCandidate() -> Candidate {
    let c = Candidate()
    c.cost = 100
    c.structureCost = 100
    return c
  }

  private func createCandidateFilter() -> CandidateFilter {
    mockUserDictionary.isSuppressedEntryHandler = { _, _ in false }
    mockUserDictionary.hasSuppressedEntriesHandler = { true }
    return CandidateFilter(mockUserDictionary, posMatcher, suggestionFilter)
  }

  private func convReq(_ requestType: RequestType) -> ConversionOptions {
    var options = ConversionOptions()
    options.requestType = requestType
    return options
  }

  private func makeNode(_ key: String, _ value: String, _ lid: UInt16, _ rid: UInt16) -> Node {
    let n = newNode()
    n.key = key
    n.value = value
    n.lid = lid
    n.rid = rid
    return n
  }

  @Test(arguments: kRequestTypes)
  func filterTest(type: RequestType) {
    let filter = createCandidateFilter()
    let n = getDefaultNodes()

    let c1 = newCandidate()
    c1.lid = 1
    c1.rid = 1
    c1.key = "abc"
    c1.value = "abc"

    let convreqType = convReq(type)
    let convreqConv = convReq(.conversion)

    #expect(filter.filterCandidate(convreqType, "abc", c1, n, n) == .goodCandidate)
    // Clear the internal set |seen_| to prevent "abc" from being filtered by
    // "seen" rule.
    filter.reset()

    // A candidate having the value seen before should be rejected.
    let c2 = newCandidate()
    c2.lid = 1
    c2.rid = 1
    c2.key = "abc"
    c2.value = "abc"

    // Once filter "abc" so that the filter memorizes it.
    #expect(filter.filterCandidate(convreqConv, "abc", c1, n, n) == .goodCandidate)
    #expect(filter.filterCandidate(convreqType, "abc", c2, n, n) == .badCandidate)

    // A candidate having high structure cost should be rejected.
    let c3 = newCandidate()
    c3.structureCost = Int32.max
    c3.key = "def"
    c3.value = "def"
    #expect(filter.filterCandidate(convreqConv, "def", c3, n, n) == .badCandidate)

    // Check if a candidate is active before appending many candidates.
    let c4 = newCandidate()
    #expect(filter.filterCandidate(convreqConv, "", c4, n, n) == .goodCandidate)

    // Don't filter if lid/rid is the same as that of the top candidate.
    let c5 = newCandidate()
    c5.key = "foo"
    c5.value = "foo"
    c5.lid = 1
    c5.rid = 1
    #expect(filter.filterCandidate(convreqConv, "foo", c5, n, n) == .goodCandidate)

    // Although CandidateFilter may change its limit, 1000 should always exceed
    // the limit.
    for i in 0..<1000 {
      let cand = newCandidate()
      cand.key = String(i)
      cand.value = cand.key
      _ = filter.filterCandidate(convreqConv, cand.key, cand, n, n)
    }
    // There will be no more candidates.
    #expect(filter.filterCandidate(convreqType, "", c4, n, n) == .stopEnumeration)
  }

  @Test(arguments: kRequestTypes)
  func deduplicationTest(type: RequestType) {
    let filter = createCandidateFilter()
    let convreq = convReq(type)
    let n = getDefaultNodes()

    func cand(_ lid: UInt16, _ rid: UInt16, _ value: String) -> Candidate {
      let c = newCandidate()
      c.lid = lid
      c.rid = rid
      c.key = "abc"
      c.value = value
      return c
    }
    #expect(filter.filterCandidate(convreq, "abc", cand(1, 1, "abc"), n, n) == .goodCandidate)
    // If all of lid, rid and value are the same with existing candidates,
    // it is filtered.
    #expect(filter.filterCandidate(convreq, "abc", cand(1, 1, "abc"), n, n) == .badCandidate)
    // lid is different from existing candidates.
    #expect(filter.filterCandidate(convreq, "abc", cand(2, 1, "abc"), n, n) == .goodCandidate)
    // rid is different from existing candidates.
    #expect(filter.filterCandidate(convreq, "abc", cand(1, 2, "abc"), n, n) == .goodCandidate)
    // value is different from existing candidates.
    #expect(filter.filterCandidate(convreq, "abc", cand(1, 1, "xyz"), n, n) == .goodCandidate)
  }

  @Test(arguments: kRequestTypes)
  func katakanaT13N(type: RequestType) {
    let convreq = convReq(type)
    do {
      let filter = createCandidateFilter()
      var nodes = getDefaultNodes()
      // nodes[0] is KatakanaT13N
      let c = newCandidate()
      c.key = "えびし"
      c.value = "abc"
      nodes[0] = makeNode("えびし", "abc", posMatcher.getUnknownId(), posMatcher.getUnknownId())
      #expect(filter.filterCandidate(convreq, "abc", c, nodes, nodes) == .goodCandidate)
      filter.reset()
    }
    do {
      let filter = createCandidateFilter()
      var nodes = getDefaultNodes()
      // nodes[1] is KatakanaT13N
      let c = newCandidate()
      c.key = "えびし"
      c.value = "abc"
      nodes[1] = makeNode("えびし", "abc", posMatcher.getFunctionalId(), posMatcher.getFunctionalId())
      #expect(filter.filterCandidate(convreq, "abc", c, nodes, nodes) == .badCandidate)
    }
    do {
      let filter = createCandidateFilter()
      var nodes = getDefaultNodes()
      // nodes[1] is not a functional word
      let c = newCandidate()
      c.key = "えびし"
      c.value = "abc"
      nodes[0] = makeNode("えびし", "abc", posMatcher.getUnknownId(), posMatcher.getUnknownId())
      nodes[1] = makeNode("てすと", "てすと", posMatcher.getUnknownId(), posMatcher.getUnknownId())
      #expect(filter.filterCandidate(convreq, "abcてすと", c, nodes, nodes) == .badCandidate)
    }
  }

  @Test(arguments: kRequestTypes)
  func isolatedWordOrGeneralSymbol(type: RequestType) {
    let filter = createCandidateFilter()
    let c = newCandidate()
    c.key = "abc"
    c.value = "abc"

    let node = newNode()
    let nodes = [node]
    let prevNode = newNode()
    let nextNode = newNode()
    node.prev = prevNode
    node.next = nextNode
    node.key = "abc"
    node.value = "test"

    let posIds = [posMatcher.getIsolatedWordId(), posMatcher.getGeneralSymbolId()]
    // Perform the same test for the above POS IDs.
    let convreq = convReq(type)
    for id in posIds {
      node.lid = id
      node.rid = id

      prevNode.nodeType = .norNode
      nextNode.nodeType = .eosNode
      #expect(filter.filterCandidate(convreq, "abc", c, nodes, nodes) == .badCandidate)
      filter.reset()

      prevNode.nodeType = .bosNode
      nextNode.nodeType = .norNode
      #expect(filter.filterCandidate(convreq, "abc", c, nodes, nodes) == .badCandidate)
      filter.reset()

      prevNode.nodeType = .norNode
      nextNode.nodeType = .norNode
      #expect(filter.filterCandidate(convreq, "abc", c, nodes, nodes) == .badCandidate)
      filter.reset()

      prevNode.nodeType = .bosNode
      nextNode.nodeType = .eosNode
      #expect(filter.filterCandidate(convreq, "abc", c, nodes, nodes) == .goodCandidate)
      filter.reset()

      node.prev = nil
      nextNode.nodeType = .eosNode
      #expect(filter.filterCandidate(convreq, "abc", c, nodes, nodes) == .goodCandidate)
      filter.reset()

      node.prev = prevNode

      prevNode.nodeType = .bosNode
      node.next = nil
      #expect(filter.filterCandidate(convreq, "abc", c, nodes, nodes) == .goodCandidate)
      filter.reset()

      node.next = nextNode
    }
  }

  @Test func isolatedWordInMultipleNodes() {
    let filter = createCandidateFilter()
    let c = newCandidate()
    c.key = "abcisolatedxyz"
    c.value = "abcisolatedxyz"

    let nodes = [
      makeNode("abc", "abc", posMatcher.getUnknownId(), posMatcher.getUnknownId()),
      makeNode("isolated", "isolated", posMatcher.getIsolatedWordId(), posMatcher.getIsolatedWordId()),
      makeNode("xyz", "xyz", posMatcher.getUnknownId(), posMatcher.getUnknownId()),
    ]
    nodes[0].prev = nil
    nodes[0].next = nodes[1]
    nodes[1].prev = nodes[0]
    nodes[1].next = nodes[2]
    nodes[2].prev = nodes[1]
    nodes[2].next = nil

    #expect(filter.filterCandidate(convReq(.conversion), "abcisolatedxyz", c, nodes, nodes) == .badCandidate)
  }

  @Test(arguments: kRequestTypes)
  func mayHaveMoreCandidates(type: RequestType) {
    let filter = createCandidateFilter()
    let n = getDefaultNodes()

    let c1 = newCandidate()
    c1.key = "abc"
    c1.value = "abc"
    #expect(filter.filterCandidate(convReq(type), "abc", c1, n, n) == .goodCandidate)
    filter.reset()

    let c2 = newCandidate()
    c2.key = "abc"
    c2.value = "abc"
    // Once filter "abc" so that the filter memorizes it.
    #expect(filter.filterCandidate(convReq(.conversion), "abc", c1, n, n) == .goodCandidate)
    // Candidates having the same value as c1 should be rejected but enumeration
    // should continue (i.e., STOP_ENUMERATION is not returned).
    let convreq3 = convReq(type)
    #expect(filter.filterCandidate(convreq3, "abc", c2, n, n) == .badCandidate)

    let c3 = newCandidate()
    c3.structureCost = Int32.max
    c3.key = "def"
    c3.value = "def"
    // High structure cost should not Stop enumeration.
    #expect(filter.filterCandidate(convreq3, "def", c3, n, n) == .badCandidate)

    let c4 = newCandidate()
    c4.cost = Int32.max
    c4.structureCost = Int32.max
    c4.key = "ghi"
    c4.value = "ghi"
    // High cost candidate should be rejected.
    #expect(filter.filterCandidate(convreq3, "ghi", c4, n, n) == .badCandidate)

    // Insert many valid candidates
    for i in 0..<50 {
      let tmp = newCandidate()
      tmp.key = "\(i)test"
      tmp.value = tmp.key
      _ = filter.filterCandidate(convReq(.conversion), tmp.key, tmp, n, n)
    }

    let c5 = newCandidate()
    c5.cost = Int32.max
    c5.structureCost = Int32.max
    // Finally, it returns STOP_ENUMERATION, because
    // filter has seen more than 50 good candidates.
    c5.value = "ghi2"
    #expect(filter.filterCandidate(convReq(type), "ghi2", c5, n, n) == .stopEnumeration)
  }

  @Test(arguments: kRequestTypes)
  func regression3437022(type: RequestType) {
    let filter = createCandidateFilter()
    let n = getDefaultNodes()

    let c1 = newCandidate()
    c1.key = "test_key"
    c1.value = "test_value"

    let convreq = convReq(type)
    #expect(filter.filterCandidate(convreq, "test_key", c1, n, n) == .goodCandidate)
    filter.reset()

    mockUserDictionary.isSuppressedEntryHandler = { key, value in
      key == "test_key" && value == "test_value"
    }

    #expect(filter.filterCandidate(convreq, c1.key, c1, n, n) == .badCandidate)

    c1.key = "test_key_suffix"
    c1.value = "test_value_suffix"
    c1.contentKey = "test_key"
    c1.contentValue = "test_value"

    #expect(filter.filterCandidate(convreq, "test_key_suffix", c1, n, n) == .badCandidate)

    mockUserDictionary.isSuppressedEntryHandler = { _, _ in false }

    #expect(filter.filterCandidate(convreq, "test_key_suffix", c1, n, n) == .goodCandidate)
  }

  @Test(arguments: kRequestTypes)
  func filterRealtimeConversionTest(type: RequestType) {
    let filter = createCandidateFilter()
    let n1 = makeNode("PC", "PC", posMatcher.getUnknownId(), posMatcher.getUnknownId())
    let n2 = makeNode("", "てすと", posMatcher.getUnknownId(), posMatcher.getUnknownId())
    let n = [n1, n2]

    let c1 = newCandidate()
    c1.attributes |= Attribute.realtimeConversion
    c1.key = "PCてすと"
    c1.value = "PCテスト"
    // Don't filter a candidate because it starts with alphabets and
    // is followed by a non-functional word.
    #expect(filter.filterCandidate(convReq(type), "PCてすと", c1, n, n) == .goodCandidate)
  }

  @Test(arguments: kRequestTypes)
  func doNotFilterExchangeableCandidates(type: RequestType) throws {
    let filter = createCandidateFilter()
    let convreq = convReq(type)
    let unknown = posMatcher.getUnknownId()

    let topNodes = [makeNode("よかっ", "よかっ", unknown, unknown), makeNode("たり", "たり", unknown, unknown)]

    let c1 = newCandidate()
    c1.key = "よかったり"
    c1.value = "よかったり"
    c1.contentKey = "よかっ"
    c1.contentValue = "よかっ"
    c1.cost = 6000
    c1.structureCost = 1000

    // Good top candidate
    try #require(filter.filterCandidate(convreq, c1.key, c1, topNodes, topNodes) == .goodCandidate)

    var nodes = [makeNode("よかっ", "良かっ", unknown, unknown), makeNode("たり", "たり", unknown, unknown)]

    let c2 = newCandidate()
    c2.key = "よかったり"
    c2.value = "良かったり"
    c2.contentKey = "よかっ"
    c2.contentValue = "良かっ"
    c2.cost = 12000
    c2.structureCost = 7500  // has big structure cost

    #expect(filter.filterCandidate(convreq, c2.key, c2, topNodes, nodes) == .goodCandidate)

    nodes = [
      makeNode("よ", "よ", unknown, unknown), makeNode("かっ", "買っ", unknown, unknown),
      makeNode("たり", "たり", unknown, unknown),
    ]

    let c3 = newCandidate()
    c3.key = "よかったり"
    c3.value = "よ買ったり"
    c3.contentKey = "よかっ"
    c3.contentValue = "よ買っ"
    c3.cost = 12000
    c3.structureCost = 7500  // has big structure cost

    #expect(filter.filterCandidate(convreq, c3.key, c3, topNodes, nodes) == .goodCandidate)
  }

  @Test(arguments: kRequestTypes)
  func doNotFilterExchangeableCandidatesNoisyNonContentWord(type: RequestType) {
    let filter = createCandidateFilter()
    let convreq = convReq(type)
    let unknown = posMatcher.getUnknownId()

    let nodes1 = [makeNode("よう", "用", unknown, unknown), makeNode("ずみ", "済み", unknown, unknown)]

    let c1 = newCandidate()
    c1.key = "ようずみ"
    c1.value = "用済み"
    c1.contentKey = "よう"
    c1.contentValue = "用"
    c1.cost = 6000
    c1.structureCost = 500

    let nodes2 = [makeNode("よう", "洋", unknown, unknown), makeNode("ずみ", "済み", unknown, unknown)]

    let c2 = newCandidate()
    c2.key = "ようずみ"
    c2.value = "洋済み"
    c2.contentKey = "よう"
    c2.contentValue = "洋"
    c2.cost = 12000
    c2.structureCost = 8000  // has big structure cost

    #expect(filter.filterCandidate(convreq, c1.key, c1, nodes1, nodes1) == .goodCandidate)
    #expect(filter.filterCandidate(convreq, c2.key, c2, nodes1, nodes2) == .badCandidate)
  }

  @Test(arguments: kRequestTypes)
  func notFilteringAntiPhraseNode(type: RequestType) {
    let filter = createCandidateFilter()
    let convreq = convReq(type)

    let topNodes: [Node]
    do {
      // Set "選考とともに" as the top candidate to the `filter` object.
      // The top candidate is not filtered in any case.
      let n1 = makeNode("せんこう", "選考", posMatcher.getGeneralNounId(), posMatcher.getGeneralNounId())
      let n2 = makeNode("とともに", "とともに", posMatcher.getAdverbSegmentSuffixId(), posMatcher.getAdverbId())
      #expect(n2.lid != n2.rid)
      topNodes = [n1, n2]

      let c = newCandidate()
      c.key = n1.key + n2.key
      c.value = n1.value + n2.value
      c.contentKey = n1.key
      c.contentValue = n1.value
      c.cost = 6000
      c.structureCost = 500
      #expect(filter.filterCandidate(convreq, c.key, c, topNodes, topNodes) == .goodCandidate)
    }
    do {
      // Confirm "閃光とともに" is not filtered although it is not the top
      // candidate.
      let n1 = makeNode("せんこう", "閃光", posMatcher.getGeneralNounId(), posMatcher.getGeneralNounId())
      // n2 (i.e. "と + ともに") is a compound word as lid != rid.
      // Compound words are usually filtered, but the anti-phrase node is an
      // exception.
      let n2 = makeNode("とともに", "とともに", posMatcher.getAdverbSegmentSuffixId(), posMatcher.getAdverbId())
      #expect(n2.lid != n2.rid)
      let nodes = [n1, n2]

      let c = newCandidate()
      c.key = n1.key + n2.key
      c.value = n1.value + n2.value
      c.contentKey = n1.key
      c.contentValue = n1.value
      c.cost = 6000
      c.structureCost = 500
      #expect(filter.filterCandidate(convreq, c.key, c, topNodes, nodes) == .goodCandidate)
    }
  }

  @Test(arguments: kRequestTypes)
  func filterMultipleNumberNodesWord(type: RequestType) {
    let filter = createCandidateFilter()
    let convreq = convReq(type)

    let nodes1 = [
      makeNode("に", "2", posMatcher.getNumberId(), posMatcher.getNumberId()),
      makeNode("じゅうさんじゅう", "十三重", posMatcher.getUnknownId(), posMatcher.getUnknownId()),
    ]

    let c1 = newCandidate()
    c1.key = "にじゅうさんじゅう"
    c1.value = "2十三重"
    c1.contentKey = "に"
    c1.contentValue = "2"
    c1.cost = 6000
    c1.structureCost = 500
    #expect(filter.filterCandidate(convreq, c1.key, c1, nodes1, nodes1) == .badCandidate)

    let nodes2 = [makeNode("にじゅうさんじゅう", "二重三重", posMatcher.getUnknownId(), posMatcher.getUnknownId())]

    let c2 = newCandidate()
    c2.key = "にじゅうさんじゅう"
    c2.value = "二重三重"
    c2.contentKey = "にじゅうさんじゅう"
    c2.contentValue = "二重三重"
    c2.cost = 6000
    c2.structureCost = 5000
    #expect(filter.filterCandidate(convreq, c2.key, c2, nodes1, nodes2) == .goodCandidate)

    let nodes3 = [
      makeNode("1", "1", posMatcher.getNumberId(), posMatcher.getNumberId()),
      makeNode("0", "0", posMatcher.getNumberId(), posMatcher.getNumberId()),
      makeNode("まん", "万", posMatcher.getKanjiNumberId(), posMatcher.getKanjiNumberId()),
      makeNode("えん", "円", posMatcher.getUnknownId(), posMatcher.getUnknownId()),
    ]

    let c3 = newCandidate()
    c3.key = "10まんえん"
    c3.value = "10万円"
    c3.contentKey = "10"
    c3.contentValue = "10"
    c3.cost = 6000
    c3.structureCost = 500
    #expect(filter.filterCandidate(convreq, c3.key, c3, nodes1, nodes3) == .goodCandidate)
  }

  @Test(arguments: kRequestTypes)
  func filterNoisyNumberCandidate(type: RequestType) {
    let filter = createCandidateFilter()
    var convreq = ConversionOptions()
    convreq.requestType = type
    convreq.createPartialCandidates = true

    let nodes1 = [
      makeNode("さん", "3", posMatcher.getNumberId(), posMatcher.getNumberId()),
      makeNode("です", "です", posMatcher.getSuffixWordId(), posMatcher.getSuffixWordId()),
    ]
    let c1 = newCandidate()
    c1.key = "さんです"
    c1.value = "3です"
    c1.contentKey = "さん"
    c1.contentValue = "3"
    c1.cost = 1000
    c1.structureCost = 50
    #expect(filter.filterCandidate(convreq, c1.key, c1, nodes1, nodes1) == .badCandidate)

    let nodes2 = [
      makeNode("しんじゅく", "新宿", posMatcher.getUniqueNounId(), posMatcher.getUniqueNounId()),
      makeNode("に", "二", posMatcher.getNumberId(), posMatcher.getNumberId()),
    ]
    let c2 = newCandidate()
    c2.key = "しんじゅくに"
    c2.value = "新宿二"
    c2.contentKey = "しんじゅく"
    c2.contentValue = "新宿"
    c2.cost = 1000
    c2.structureCost = 50
    #expect(filter.filterCandidate(convreq, c2.key, c2, nodes2, nodes2) == .badCandidate)

    let nodes3 = [
      makeNode("ginza", "GINZA", posMatcher.getUniqueNounId(), posMatcher.getUniqueNounId()),
      makeNode("7", "7", posMatcher.getNumberId(), posMatcher.getNumberId()),
    ]
    let c3 = newCandidate()
    c3.key = "ginza7"
    c3.value = "GINZA7"
    c3.contentKey = "ginza"
    c3.contentValue = "GINZA"
    c3.cost = 1000
    c3.structureCost = 50
    #expect(filter.filterCandidate(convreq, c3.key, c3, nodes3, nodes3) == .goodCandidate)

    let n3 = newNode()
    n3.key = "ご"
    n3.value = "後"
    let nodes4 = [
      makeNode("に", "2", posMatcher.getNumberId(), posMatcher.getNumberId()),
      makeNode("ねん", "年", posMatcher.getCounterSuffixWordId(), posMatcher.getCounterSuffixWordId()),
      n3,
    ]
    let c4 = newCandidate()
    c4.key = "にねんご"
    c4.value = "2年後"
    c4.contentKey = "に"
    c4.contentValue = "2"
    c4.cost = 1000
    c4.structureCost = 50
    #expect(filter.filterCandidate(convreq, c4.key, c4, nodes4, nodes4) == .goodCandidate)
  }

  private func singleNodeCandidate(_ nodes: [Node]) -> Candidate {
    let c = newCandidate()
    c.key = nodes.map(\.key).joined()
    c.value = nodes.map(\.value).joined()
    c.contentKey = c.key
    c.contentValue = c.value
    c.cost = 1000
    c.structureCost = 2000
    return c
  }

  @Test func capabilityOfSuggestionFilterConversion() {
    let filter = createCandidateFilter()
    // For CONVERSION, suggestion filter is not applied.
    let n = newNode()
    n.key = "ふぃるたー"
    n.value = "フィルター"
    let nodes = [n]
    let c = singleNodeCandidate(nodes)
    #expect(filter.filterCandidate(convReq(.conversion), c.key, c, nodes, nodes) == .goodCandidate)
  }

  private func filterNodes() -> (unigram: [Node], bigram: [Node], trigram: [Node]) {
    let n = newNode()
    n.key = "ふぃるたー"
    n.value = "フィルター"
    let b1 = newNode()
    b1.key = "これは"
    b1.value = b1.key
    let b2 = newNode()
    b2.key = "ふぃるたー"
    b2.value = "フィルター"
    let t1 = newNode()
    t1.key = "これは"
    t1.value = t1.key
    let t2 = newNode()
    t2.key = "ふぃる"
    t2.value = "フィル"
    let t3 = newNode()
    t3.key = "たー"
    t3.value = "ター"
    return ([n], [b1, b2], [t1, t2, t3])
  }

  @Test func capabilityOfSuggestionFilterSuggestion() {
    let filter = createCandidateFilter()
    let convreq = convReq(.suggestion)
    let (unigram, bigram, trigram) = filterNodes()

    // For SUGGESTION, suggestion filter is applied regardless of its original
    // key length. First test unigram case.
    do {
      let c = singleNodeCandidate(unigram)
      // Test case where "フィルター" is suggested from key "ふぃる".
      #expect(filter.filterCandidate(convreq, "ふぃる", c, unigram, unigram) == .badCandidate)
      filter.reset()
      // Test case where "フィルター" is suggested from key "ふぃるたー".
      #expect(filter.filterCandidate(convreq, unigram[0].key, c, unigram, unigram) == .badCandidate)
    }
    // Next test bigram case.
    do {
      filter.reset()
      let c = singleNodeCandidate(bigram)
      #expect(filter.filterCandidate(convreq, "これはふ", c, bigram, bigram) == .badCandidate)
      filter.reset()
      #expect(filter.filterCandidate(convreq, c.key, c, bigram, bigram) == .badCandidate)
    }
    // TODO(noriyukit): This is a limitation of current implementation. If
    // multiple nodes constitute a word in suggestion filter, it cannot be
    // filtered. Fix this.
    do {
      filter.reset()
      let c = singleNodeCandidate(trigram)
      #expect(filter.filterCandidate(convreq, "これはふ", c, trigram, trigram) == .goodCandidate)
      filter.reset()
      #expect(filter.filterCandidate(convreq, c.key, c, trigram, trigram) == .goodCandidate)
    }
  }

  @Test func capabilityOfSuggestionFilterPrediction() {
    let filter = createCandidateFilter()
    let convreq = convReq(.prediction)
    let (unigram, bigram, trigram) = filterNodes()

    // For PREDICTION, suggestion filter is applied only when its original key
    // length is equal to the key of predicted node.  First test unigram case.
    do {
      let c = singleNodeCandidate(unigram)
      #expect(filter.filterCandidate(convreq, "ふぃる", c, unigram, unigram) == .badCandidate)
      // Note the difference from the case of SUGGESTION, now words in
      // suggestion filter are good if its key is equal to the original key.
      filter.reset()
      #expect(filter.filterCandidate(convreq, unigram[0].key, c, unigram, unigram) == .goodCandidate)
    }
    // Next test bigram case.
    do {
      filter.reset()
      let c = singleNodeCandidate(bigram)
      #expect(filter.filterCandidate(convreq, "これはふ", c, bigram, bigram) == .badCandidate)
      filter.reset()
      #expect(filter.filterCandidate(convreq, c.key, c, bigram, bigram) == .goodCandidate)
    }
    // TODO(noriyukit): This is a limitation of current implementation.
    do {
      filter.reset()
      filter.reset()
      let c = singleNodeCandidate(trigram)
      #expect(filter.filterCandidate(convreq, "これはふ", c, trigram, trigram) == .goodCandidate)
      filter.reset()
      #expect(filter.filterCandidate(convreq, c.key, c, trigram, trigram) == .goodCandidate)
    }
  }

  @Test func reverseConversion() {
    let convreq = convReq(.reverseConversion)
    let filter = createCandidateFilter()
    var nodes = getDefaultNodes()

    let kHonKanji = "本"
    let kHonHiragana = "ほん"

    let n1 = newNode()
    n1.key = kHonKanji
    n1.value = kHonHiragana
    nodes.append(n1)

    let n2 = newNode()
    n2.key = " "
    n2.value = " "
    nodes.append(n2)

    do {
      let c = newCandidate()
      c.key = n1.key
      c.value = n1.value
      c.contentKey = c.key
      c.contentValue = c.value
      c.cost = 1000
      c.structureCost = 2000
      #expect(filter.filterCandidate(convreq, kHonHiragana, c, nodes, nodes) == .goodCandidate)
      // Duplicates should be removed.
      #expect(filter.filterCandidate(convreq, kHonHiragana, c, nodes, nodes) == .badCandidate)
    }
    do {
      // White space should be valid candidate.
      let c = newCandidate()
      c.key = n2.key
      c.value = n2.value
      c.contentKey = c.key
      c.contentValue = c.value
      c.cost = 1000
      c.structureCost = 2000
      #expect(filter.filterCandidate(convreq, " ", c, nodes, nodes) == .goodCandidate)
    }
  }

  // Swift-only: CandidateId uses bytewise equality (C++ std::string), not
  // Unicode canonical equivalence.
  @Test func candidateIdIsBytewise() {
    let a = Candidate()
    a.value = "\u{00E9}"  // é (precomposed)
    let b = Candidate()
    b.value = "e\u{0301}"  // e + combining acute
    #expect(CandidateFilterCandidateId(a) != CandidateFilterCandidateId(b))
    #expect(Set([CandidateFilterCandidateId(a), CandidateFilterCandidateId(b)]).count == 2)
  }
}
