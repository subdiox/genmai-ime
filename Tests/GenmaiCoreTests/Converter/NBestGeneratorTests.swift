// Port of mozc/src/converter/nbest_generator_test.cc (3.35.6354).
//
// ImmutableConverterTestPeer's IsSegmentEndNode / MakeGroup are the
// internal ImmutableConverter methods (via @testable import).

import GenmaiProtocol
import Testing
@testable import GenmaiCore

@Suite(.enabled(if: ConverterCoreTestSupport.hasMockData, ConverterCoreTestSupport.mockDataMissing))
struct NBestGeneratorTests {
  private let modules: TestModules
  private let converter: ImmutableConverter

  init() throws {
    modules = try TestModules.mock()
    converter = modules.makeImmutableConverter()
  }

  private func convReq(_ requestType: RequestType) -> ConversionRequest {
    ConversionRequestBuilder().setRequestType(requestType).build()
  }

  private func createNBestGenerator(_ lattice: Lattice, _ request: ConversionRequest) -> NBestGenerator {
    let cachingConnector = CachingConnector(
      hasBonus: true, modules.connector,
      Int(request.request().decoderExperimentParams.particleOmissionTransitionCostBonus), modules.posMatcher)
    return NBestGenerator(
      modules.userDictionary, modules.segmenter, cachingConnector, modules.posMatcher, lattice,
      modules.suggestionFilter)
  }

  private func getEndNode(
    _ request: ConversionRequest, _ segments: Segments, _ beginNode: Node, _ group: [UInt16],
    _ isSingleSegment: Bool
  ) -> Node {
    var endNode: Node? = nil
    var node = beginNode.next!
    while let next = node.next {
      endNode = next
      if converter.isSegmentEndNode(request.options(), segments, node, group, isSingleSegment) {
        break
      }
      node = next
    }
    return endNode!
  }

  /// MakeLattice + MakeGroup + Viterbi.
  private func build(_ segments: Segments, _ key: String, _ request: ConversionRequest) -> (Lattice, [UInt16]) {
    let lattice = Lattice()
    lattice.setKey(key)
    _ = converter.makeLattice(request.options(), segments, lattice)
    let group = converter.makeGroup(segments)
    _ = converter.viterbi(request.options(), segments, lattice)
    return (lattice, group)
  }

  private func addSegment(_ segments: Segments, _ key: String, _ type: Segment.SegmentType) {
    let segment = segments.addSegment()
    segment.setSegmentType(type)
    segment.setKey(key)
  }

  @Test func multiSegmentConnectionTest() throws {
    let segments = Segments()
    addSegment(segments, "しんこう", .fixedBoundary)
    addSegment(segments, "する", .free)

    let request = convReq(.conversion)
    let (lattice, group) = build(segments, "しんこうする", request)
    let nbestGenerator = createNBestGenerator(lattice, request)

    let kSingleSegment = false  // For 'normal' conversion
    let beginNode = lattice.bosNode
    let endNode = getEndNode(request, segments, beginNode, group, kSingleSegment)
    do {
      nbestGenerator.reset(beginNode, endNode, .init(boundaryMode: .strict))
      let resultSegment = Segment()
      nbestGenerator.setCandidates(request.options(), "", 10, resultSegment)
      // The top result is treated exceptionally and has no boundary check
      // in NBestGenerator.
      // The best route is calculated in ImmutalbeConverter with boundary check.
      // So, the top result should be inserted, but other candidates will be cut
      // due to boundary check between "する".
      try #require(resultSegment.candidatesSize == 1)
      #expect(resultSegment.candidate(0).value == "進行")
    }
    do {
      nbestGenerator.reset(beginNode, endNode, .init(boundaryMode: .onlyMid))
      let resultSegment = Segment()
      nbestGenerator.setCandidates(request.options(), "", 10, resultSegment)
      try #require(resultSegment.candidatesSize == 3)
      #expect(resultSegment.candidate(0).value == "進行")
      #expect(resultSegment.candidate(1).value == "信仰")
      #expect(resultSegment.candidate(2).value == "深耕")
    }
  }

  @Test func singleSegmentConnectionTest() throws {
    let segments = Segments()
    let kText = "わたしのなまえはなかのです"
    addSegment(segments, kText, .free)

    let request = convReq(.conversion)
    let (lattice, group) = build(segments, kText, request)
    let nbestGenerator = createNBestGenerator(lattice, request)

    let kSingleSegment = true  // For real time conversion
    let beginNode = lattice.bosNode
    let endNode = getEndNode(request, segments, beginNode, group, kSingleSegment)
    do {
      nbestGenerator.reset(beginNode, endNode, .init(boundaryMode: .strict))
      let resultSegment = Segment()
      nbestGenerator.setCandidates(request.options(), "", 10, resultSegment)
      // Top result should be inserted, but other candidates will be cut
      // due to boundary check.
      try #require(resultSegment.candidatesSize == 1)
      #expect(resultSegment.candidate(0).value == "私の名前は中ノです")
    }
    do {
      nbestGenerator.reset(
        beginNode, endNode,
        .init(boundaryMode: .onlyEdge, candidateMode: NBestGenerator.CandidateMode.fillInnerSegmentInfo))
      let resultSegment = Segment()
      nbestGenerator.setCandidates(request.options(), "", 10, resultSegment)
      // We can get several candidates.
      try #require(resultSegment.candidatesSize > 1)
      #expect(resultSegment.candidate(0).value == "私の名前は中ノです")
    }
  }

  @Test func innerSegmentBoundary() throws {
    let segments = Segments()
    let kInput = "とうきょうかなごやにいきたい"
    addSegment(segments, kInput, .free)

    let request = convReq(.prediction)
    let (lattice, group) = build(segments, kInput, request)
    let nbestGenerator = createNBestGenerator(lattice, request)

    let beginNode = lattice.bosNode
    let endNode = getEndNode(request, segments, beginNode, group, true)

    nbestGenerator.reset(
      beginNode, endNode,
      .init(boundaryMode: .onlyEdge, candidateMode: NBestGenerator.CandidateMode.fillInnerSegmentInfo))
    let resultSegment = Segment()
    nbestGenerator.setCandidates(request.options(), "", 10, resultSegment)
    try #require(resultSegment.candidatesSize >= 1)

    let topCand = resultSegment.candidate(0)
    #expect(topCand.key == kInput)
    #expect(topCand.value == "東京か名古屋に行きたい")

    let segs = Array(topCand.innerSegments())
    try #require(segs.count == 3)

    // Inner segment 0
    #expect(segs[0].key == "とうきょうか")
    #expect(segs[0].value == "東京か")
    #expect(segs[0].contentKey == "とうきょう")
    #expect(segs[0].contentValue == "東京")

    // Inner segment 1
    #expect(segs[1].key == "なごやに")
    #expect(segs[1].value == "名古屋に")
    #expect(segs[1].contentKey == "なごや")
    #expect(segs[1].contentValue == "名古屋")

    // Inner segment 2: In the original segment, "行きたい" has the form
    // "行き" (content word) + "たい" (functional).  However, since "行き" is
    // Yougen, our rule for inner segment boundary doesn't handle it as a content
    // value.  Thus, "行きたい" becomes the content value.
    #expect(segs[2].key == "いきたい")
    #expect(segs[2].value == "行きたい")
    #expect(segs[2].contentKey == "いきたい")
    #expect(segs[2].contentValue == "行きたい")
  }

  @Test func noPartialCandidateBetweenAlphabets() {
    let segments = Segments()
    let kInput = "AAA"
    addSegment(segments, kInput, .free)

    let request = convReq(.prediction)
    let (lattice, group) = build(segments, kInput, request)
    let nbestGenerator = createNBestGenerator(lattice, request)

    let beginNode = lattice.bosNode
    let endNode = getEndNode(request, segments, beginNode, group, true)

    // Since the test dictionary contains "A", partial candidates "A" and "AA" can
    // be generated but they should be suppressed because they are split between
    // alphabets.
    let options = NBestGenerator.Options(
      boundaryMode: .onlyEdge,
      candidateMode: NBestGenerator.CandidateMode.buildFromOnlyFirstInnerSegment
        | NBestGenerator.CandidateMode.fillInnerSegmentInfo)
    nbestGenerator.reset(beginNode, endNode, options)
    let resultSegment = Segment()
    nbestGenerator.setCandidates(request.options(), "", 10, resultSegment)
    #expect(hasSingleCandidate(resultSegment, valueIs("AAA")))
  }

  @Test func noAlphabetsConnection2Nodes() {
    let segments = Segments()
    let kText = "eupho"
    addSegment(segments, kText, .free)

    let request = convReq(.conversion)
    let (lattice, group) = build(segments, kText, request)
    let nbestGenerator = createNBestGenerator(lattice, request)

    let beginNode = lattice.bosNode
    let endNode = getEndNode(request, segments, beginNode, group, true)
    nbestGenerator.reset(
      beginNode, endNode,
      .init(boundaryMode: .onlyEdge, candidateMode: NBestGenerator.CandidateMode.fillInnerSegmentInfo))
    let resultSegment = Segment()
    nbestGenerator.setCandidates(request.options(), "", 10, resultSegment)
    // The test dictionary contains key value pairs (eu, EU) and (pho, pho), but
    // "EUpho" should not be generated as it is a concatenation of two alphabet
    // words. The only expected candidate is (eupho, eupho).
    #expect(hasSingleCandidate(resultSegment, valueIs("eupho")))
  }

  @Test func noAlphabetsConnection3Nodes() throws {
    let segments = Segments()
    let kText = "euphoとうきょう"
    addSegment(segments, kText, .free)

    let request = convReq(.conversion)
    let (lattice, group) = build(segments, kText, request)
    let nbestGenerator = createNBestGenerator(lattice, request)

    let beginNode = lattice.bosNode
    let endNode = getEndNode(request, segments, beginNode, group, true)
    nbestGenerator.reset(
      beginNode, endNode,
      .init(boundaryMode: .onlyEdge, candidateMode: NBestGenerator.CandidateMode.fillInnerSegmentInfo))
    let resultSegment = Segment()
    nbestGenerator.setCandidates(request.options(), "", 10, resultSegment)
    // Tne top candidate consists of two elements, "eupho" and "東京". Such
    // connection from English word to a normal word is possible.
    try #require(resultSegment.candidatesSize >= 1)
    #expect(resultSegment.candidate(0).value == "eupho東京")
    #expect(resultSegment.candidate(0).innerSegmentBoundary.count == 2)
    // However, we should not concatenate "EU", "pho", and "東京".
    for i in 0..<resultSegment.candidatesSize {
      #expect(resultSegment.candidate(i).value != "EUpho東京")
    }
  }

  @Test func alphabetsConnectionAcrossSegmentBoundary() throws {
    let segments = Segments()
    do {
      let segment = segments.addSegment()
      segment.setSegmentType(.history)
      segment.setKey("eu")
      let candidate = segment.addCandidate()
      candidate.key = "eu"
      candidate.value = "EU"
    }
    addSegment(segments, "pho", .free)

    let request = convReq(.conversion)
    let (lattice, group) = build(segments, "pho", request)
    let nbestGenerator = createNBestGenerator(lattice, request)

    // Skip HIS_NODE(s) to find the begin_node for the conversion segment.
    var beginNode = lattice.bosNode
    var node = lattice.bosNode.next!
    while node.next != nil && node.nodeType == .hisNode {
      beginNode = node
      node = node.next!
    }

    let endNode = getEndNode(request, segments, beginNode, group, false)
    nbestGenerator.reset(beginNode, endNode, .init(boundaryMode: .strict))
    let resultSegment = Segment()
    nbestGenerator.setCandidates(request.options(), "", 10, resultSegment)
    // Connection between "eu" and "pho" across the segment boundary should be
    // allowed even though both keys end/start with alphabets.
    try #require(resultSegment.candidatesSize >= 1)
    #expect(resultSegment.candidate(0).value == "pho")
  }

  private func particleOmissionTopCost(_ segments: Segments, _ bonus: Int?) throws -> Int32 {
    var builder = ConversionRequestBuilder()
    if let bonus {
      var requestProto = Genmai_Commands_Request()
      requestProto.decoderExperimentParams.particleOmissionTransitionCostBonus = Int32(bonus)
      builder = builder.setRequest(requestProto)
    }
    let request = builder.setRequestType(.conversion).build()
    let (lattice, group) = build(segments, "あんけーとひかえる", request)
    let nbestGenerator = createNBestGenerator(lattice, request)
    let beginNode = lattice.bosNode
    let endNode = getEndNode(request, segments, beginNode, group, false)
    nbestGenerator.reset(beginNode, endNode, .init(boundaryMode: .strict))
    let resultSegment = Segment()
    nbestGenerator.setCandidates(request.options(), "", 10, resultSegment)
    try #require(resultSegment.candidatesSize >= 1)
    #expect(resultSegment.candidate(0).value == "アンケート")
    return resultSegment.candidate(0).cost
  }

  @Test func particleOmissionBonusTest() throws {
    // Case 1: Noun ("あんけーと") + Verb ("ひかえる")
    let segments = Segments()
    addSegment(segments, "あんけーと", .free)
    addSegment(segments, "ひかえる", .free)

    _ = try particleOmissionTopCost(segments, nil)
    let costBonus2000 = try particleOmissionTopCost(segments, 2000)
    let costBonus2001 = try particleOmissionTopCost(segments, 2001)

    // Cost should be reduced by 1 for bonus 2001 compared to 2000.
    #expect(costBonus2000 - costBonus2001 == 1)
  }
}
