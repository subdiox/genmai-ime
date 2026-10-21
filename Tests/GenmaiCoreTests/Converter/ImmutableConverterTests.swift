// Port of mozc/src/converter/immutable_converter_test.cc (3.35.6354).
//
// The C++ KeyCheckDictionary helper and the MockDataAndImmutableConverter
// constructor with preset dictionaries are unused there and not ported.

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private func setCandidate(_ key: String, _ value: String, _ segment: Segment) {
  segment.setKey(key)
  let candidate = segment.addCandidate()
  candidate.key = key
  candidate.value = value
  candidate.contentKey = key
  candidate.contentValue = value
}

private func getCandidateIndexByValue(_ value: String, _ segment: Segment) -> Int {
  for i in 0..<segment.candidatesSize {
    if segment.candidate(i).value.bytesEqual(value) {
      return i
    }
  }
  return -1  // not found
}

private func makeConverter() throws -> ImmutableConverter {
  try TestModules.mock().makeImmutableConverter()
}

private func options(
  _ requestType: RequestType, maxConversionCandidatesSize: Int? = nil,
  createPartialCandidates: Bool? = nil
) -> ConversionOptions {
  var options = ConversionOptions()
  options.requestType = requestType
  if let maxConversionCandidatesSize {
    options.maxConversionCandidatesSize = maxConversionCandidatesSize
  }
  if let createPartialCandidates {
    options.createPartialCandidates = createPartialCandidates
  }
  return options
}

@Suite("ImmutableConverter")
struct ImmutableConverterTests {
  @Test func keepKeyForPrediction() throws {
    let converter = try makeConverter()
    let segments = Segments()
    let request = ConversionRequestBuilder()
      .setOptions(options(.prediction, maxConversionCandidatesSize: 10)).build()
    let segment = segments.addSegment()
    let kRequestKey = "よろしくおねがいしま"
    segment.setKey(kRequestKey)
    #expect(converter.convert(request.options(), segments))
    #expect(segments.segmentsSize == 1)
    #expect(segments.segment(0).candidatesSize > 0)
    #expect(segments.segment(0).key == kRequestKey)
  }

  @Test func resegmentTest() throws {
    let converter = try makeConverter()
    let segments = Segments()
    let request = ConversionRequestBuilder()
      .setOptions(options(.conversion, maxConversionCandidatesSize: 10)).build()

    do {
      segments.clear()
      let segment = segments.addSegment()
      segment.setKey("1ねんせい")
      #expect(converter.convert(request.options(), segments))
      try #require(segments.segmentsSize == 2)
      #expect(segments.segment(0).candidate(0).value == "1")
      #expect(segments.segment(1).candidate(0).value == "年生")
    }

    do {
      segments.clear()
      let segment = segments.addSegment()
      segment.setKey("ちゅう2")
      #expect(converter.convert(request.options(), segments))
      try #require(segments.segmentsSize == 2)
      #expect(segments.segment(0).candidate(0).value == "中")
      #expect(segments.segment(1).candidate(0).value == "2")
    }
  }

  @Test func dummyCandidatesCost() throws {
    let converter = try makeConverter()
    let segment = Segment()
    setCandidate("てすと", "test", segment)
    converter.insertDummyCandidates(segment, 10)
    try #require(segment.candidatesSize >= 3)
    #expect(segment.candidate(0).wcost < segment.candidate(1).wcost)
    #expect(segment.candidate(0).wcost < segment.candidate(2).wcost)
  }

  @Test func dummyCandidatesInnerSegmentBoundary() throws {
    let converter = try makeConverter()
    let segment = Segment()
    setCandidate("てすと", "test", segment)
    let c = segment.mutableCandidate(0)
    c.innerSegmentBoundary = buildInnerSegmentBoundary([(3, 2, 3, 2), (6, 2, 6, 2)], c.key, c.value)
    #expect(c.innerSegmentBoundary.count == 2)

    converter.insertDummyCandidates(segment, 10)
    try #require(segment.candidatesSize >= 3)
    for i in 1..<3 {
      #expect(segment.candidate(i).innerSegmentBoundary.isEmpty)
    }
  }

  @Test func innerSegmenBoundaryForPrediction() throws {
    let converter = try makeConverter()
    let segments = Segments()
    let segment = segments.addSegment()
    segment.setKey("わたしのなまえはなかのです")
    let request = ConversionRequestBuilder()
      .setOptions(options(.prediction, maxConversionCandidatesSize: 1)).build()
    #expect(converter.convert(request.options(), segments))
    try #require(segments.segmentsSize == 1)
    try #require(segments.segment(0).candidatesSize == 1)

    // Result will be, "私の|名前は|中ノです" with mock dictionary.
    let cand = segments.segment(0).candidate(0)
    var keys: [String] = []
    var values: [String] = []
    var contentKeys: [String] = []
    var contentValues: [String] = []
    for iter in cand.innerSegments() {
      keys.append(String(iter.getKey()))
      values.append(String(iter.getValue()))
      contentKeys.append(String(iter.getContentKey()))
      contentValues.append(String(iter.getContentValue()))
    }
    #expect(keys == ["わたしの", "なまえは", "なかのです"])
    #expect(values == ["私の", "名前は", "中ノです"])
    #expect(contentKeys == ["わたし", "なまえ", "なかの"])
    #expect(contentValues == ["私", "名前", "中ノ"])
  }

  @Test func noInnerSegmenBoundaryForConversion() throws {
    let converter = try makeConverter()
    let segments = Segments()
    let segment = segments.addSegment()
    segment.setKey("わたしのなまえはなかのです")
    let request = ConversionRequestBuilder().setRequestType(.conversion).build()
    #expect(converter.convert(request.options(), segments))
    #expect(segments.segmentsSize >= 1)
    #expect(segments.segment(0).candidatesSize > 0)
    for i in 0..<segments.segment(0).candidatesSize {
      #expect(segments.segment(0).candidate(i).innerSegmentBoundary.isEmpty)
    }
  }

  @Test func makeLatticeKatakana() throws {
    let converter = try makeConverter()
    let segments = Segments()

    let segment = segments.addSegment()
    segment.setSegmentType(.free)
    segment.setKey("カタカナです")

    let lattice = Lattice()
    lattice.setKey("カタカナです")
    let request = ConversionRequest()
    _ = converter.makeLattice(request.options(), segments, lattice)

    // If the first character of a node is `ALPHABET` or `KATAKANA`,
    // `AddCharacterTypeBasedNodes` should create a node of the character
    // type.
    let node = lattice.beginNodes(0).last!
    #expect(node.key == "カタカナ")
    #expect(node.value == "カタカナ")
  }

  @Test func notConnectedTest() throws {
    let converter = try makeConverter()
    let segments = Segments()

    var segment = segments.addSegment()
    segment.setSegmentType(.fixedBoundary)
    segment.setKey("しょうめい")

    segment = segments.addSegment()
    segment.setSegmentType(.free)
    segment.setKey("できる")

    let lattice = Lattice()
    lattice.setKey("しょうめいできる")
    let request = ConversionRequest()
    _ = converter.makeLattice(request.options(), segments, lattice)

    _ = converter.viterbi(request.options(), segments, lattice)

    // Intentionally segmented position - 1
    let pos = "しょうめ".utf8.count
    var tested = false
    for rnode in lattice.beginNodes(pos) {
      if Util.charsLen(rnode.key) <= 1 {
        continue
      }
      // If len(rnode->value) > 1, that node should cross over the boundary
      #expect(rnode.prev == nil)
      tested = true
    }
    #expect(tested)
  }

  @Test func historyKeyLengthIsVeryLong() throws {
    // "あ..." (100 times)
    let kA100 = String(repeating: "あ", count: 100)

    // Set up history segments.
    let segments = Segments()
    for _ in 0..<4 {
      let segment = segments.addSegment()
      segment.setKey(kA100)
      segment.setSegmentType(.history)
      let candidate = segment.addCandidate()
      candidate.key = kA100
      candidate.value = kA100
    }

    // Set up a conversion segment.
    let segment = segments.addSegment()
    let kRequestKey = "あ"
    segment.setKey(kRequestKey)

    // Verify that history segments are cleared due to its length limit and at
    // least one candidate is generated.
    let converter = try makeConverter()
    let request = ConversionRequestBuilder().setRequestType(.conversion).build()
    #expect(converter.convert(request.options(), segments))
    #expect(segments.historySegmentsSize == 0)
    try #require(segments.conversionSegmentsSize == 1)
    #expect(segments.segment(0).candidatesSize > 0)
    #expect(segments.segment(0).key == kRequestKey)
  }

  private func autoPartialSuggestionTestHelper(_ request: ConversionRequest) throws -> Bool {
    let converter = try makeConverter()
    let segments = Segments()
    var options = request.options()
    options.requestType = .prediction
    options.maxConversionCandidatesSize = 10
    let conversionRequest = ConversionRequestBuilder()
      .setConversionRequest(request)
      .setOptions(options)
      .build()
    let segment = segments.addSegment()
    let kRequestKey = "わたしのなまえはなかのです"
    segment.setKey(kRequestKey)
    #expect(converter.convert(conversionRequest.options(), segments))
    #expect(segments.conversionSegmentsSize == 1)
    #expect(segments.segment(0).candidatesSize > 0)
    var includesOnlyFirst = false
    let segmentKey = segments.segment(0).key
    for i in 0..<segments.segment(0).candidatesSize {
      let cand = segments.segment(0).candidate(i)
      if cand.key.utf8.count < segmentKey.utf8.count && segmentKey.hasBytePrefix(cand.key) {
        includesOnlyFirst = true
        break
      }
    }
    return includesOnlyFirst
  }

  @Test func enableAutoPartialSuggestion() throws {
    var o = ConversionOptions()
    o.createPartialCandidates = true
    let conversionRequest = ConversionRequestBuilder().setOptions(o).build()
    #expect(conversionRequest.options().createPartialCandidates)
    #expect(try autoPartialSuggestionTestHelper(conversionRequest))
  }

  @Test func disableAutoPartialSuggestion() throws {
    var o = ConversionOptions()
    o.createPartialCandidates = false
    let conversionRequest = ConversionRequestBuilder().setOptions(o).build()
    #expect(try !autoPartialSuggestionTestHelper(conversionRequest))
  }

  @Test func autoPartialSuggestionDefault() throws {
    let conversionRequest = ConversionRequest()
    #expect(try !autoPartialSuggestionTestHelper(conversionRequest))
  }

  private func mobilePredictionRequest() -> ConversionRequest {
    var request = Genmai_Commands_Request()
    RequestTestUtil.fillMobileRequest(&request)
    return ConversionRequestBuilder()
      .setRequest(request)
      .setOptions(
        options(.prediction, maxConversionCandidatesSize: 100, createPartialCandidates: true))
      .build()
  }

  @Test func firstInnerSegment() throws {
    let conversionRequest = mobilePredictionRequest()
    let converter = try makeConverter()

    let segments = Segments()
    let segment = segments.addSegment()
    segment.setKey("くるまでこうどうした")
    #expect(converter.convert(conversionRequest.options(), segments))

    #expect(containsCandidate(segment, keyIs("くるまでこうどうした")))
    #expect(containsCandidate(segment, keyIs("くるまで")))
    #expect(containsCandidate(segment, keyIs("くる")))
  }

  @Test func firstInnerSegmentFiltering() throws {
    let conversionRequest = mobilePredictionRequest()
    let converter = try makeConverter()

    do {
      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey("したとき")
      #expect(converter.convert(conversionRequest.options(), segments))

      #expect(containsCandidate(segment, valueIs("した時")))
      // The same segment structure, but included by char coverage rule.
      #expect(containsCandidate(segment, valueIs("したとき")))
    }
    do {
      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey("のとき")
      #expect(converter.convert(conversionRequest.options(), segments))

      #expect(containsCandidate(segment, valueIs("の時")))
      // The same segment structure, included by char coverage.
      #expect(containsCandidate(segment, valueIs("のとき")))
    }
    do {
      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey("かえる")
      #expect(converter.convert(conversionRequest.options(), segments))

      #expect(containsCandidate(segment, valueIs("換える")))
      #expect(containsCandidate(segment, valueIs("代える")))
      #expect(containsCandidate(segment, valueIs("買える")))
      // Included by cost diff
      #expect(containsCandidate(segment, valueIs("飼える")))
    }
    do {
      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey("くるまでこうどうした")
      #expect(converter.convert(conversionRequest.options(), segments))

      #expect(containsCandidate(segment, valueIs("車で行動した")))
      #expect(containsCandidate(segment, valueIs("車で")))
      #expect(containsCandidate(segment, valueIs("来るまで")))
      #expect(containsCandidate(segment, valueIs("くるまで")))
    }
  }

  // Confirm t13n (Hiragana to English) conversions twice work (b/427316871).
  @Test func t13nConversionTwice() throws {
    let converter = try makeConverter()
    let segments = Segments()
    segments.addSegment().setKey("ぐうぐる")
    let request = ConversionRequest()
    #expect(converter.convert(request.options(), segments))
    try #require(segments.segmentsSize == 1)

    let index = getCandidateIndexByValue("Google", segments.conversionSegment(0))
    try #require(index != -1)

    do {  // Make the existing segment HISTORY
      let segment = segments.mutableSegment(0)
      segment.setSegmentType(.history)
      segment.moveCandidate(index, 0)
      if index != 0 {
        segment.mutableCandidate(0).attributes |= Attribute.reranked
      }
    }

    // Add a new segment for t13n conversion again.
    segments.addSegment().setKey("ぐーぐる")
    #expect(converter.convert(request.options(), segments))
    try #require(segments.segmentsSize == 2)
    try #require(segments.conversionSegmentsSize == 1)

    #expect(getCandidateIndexByValue("Google", segments.conversionSegment(0)) != -1)
  }

  private func particleOmissionCost(_ bonus: Int32, _ requestType: RequestType) throws -> Int32 {
    let converter = try makeConverter()
    let kRequestKey = "あんけーとひかえる"
    let segments = Segments()
    segments.addSegment().setKey(kRequestKey)

    var requestProto = Genmai_Commands_Request()
    requestProto.decoderExperimentParams.particleOmissionTransitionCostBonus = bonus

    let request = ConversionRequestBuilder()
      .setRequest(requestProto)
      .setRequestType(requestType)
      .build()

    #expect(converter.convert(request.options(), segments))
    try #require(segments.segmentsSize > 0)
    try #require(segments.segment(0).candidatesSize > 0)
    var convertedValue = ""
    for i in 0..<segments.segmentsSize {
      convertedValue += segments.segment(i).candidate(0).value
    }
    #expect(convertedValue == "アンケート控える")
    return segments.segment(0).candidate(0).cost
  }

  @Test func particleOmissionBonusTest() throws {
    let costBonus2000 = try particleOmissionCost(2000, .conversion)
    let costBonus2001 = try particleOmissionCost(2001, .conversion)
    // Cost of the first segment should be reduced by 1 for bonus 2001
    // compared to 2000.
    #expect(costBonus2000 - costBonus2001 == 1)
  }

  @Test func particleOmissionBonusPredictionTest() throws {
    let costBonus2000 = try particleOmissionCost(2000, .prediction)
    let costBonus2001 = try particleOmissionCost(2001, .prediction)
    // Cost of the first segment should be reduced by 1 for bonus 2001
    // compared to 2000.
    #expect(costBonus2000 - costBonus2001 == 1)
  }

  @Test func normalizeHistorySegmentsClearsInconsistentInnerSegmentBoundary() throws {
    let converter = try makeConverter()
    let segments = Segments()

    let historySegment = segments.addSegment()
    historySegment.setKey("１２")
    historySegment.setSegmentType(.history)
    let historyCand = historySegment.addCandidate()
    historyCand.key = "１２"
    historyCand.value = "１２"
    historyCand.contentKey = "１２"
    historyCand.contentValue = "１２"
    historyCand.innerSegmentBoundary = buildInnerSegmentBoundary([(6, 6, 6, 6)], "１２", "１２")
    try #require(!historyCand.innerSegmentBoundary.isEmpty)

    let conversionSegment = segments.addSegment()
    conversionSegment.setKey("がつ")

    let request = ConversionRequestBuilder().setRequestType(.conversion).build()
    #expect(converter.convert(request.options(), segments))
    try #require(segments.historySegmentsSize == 1)
    #expect(segments.historySegment(0).key == "2")
    #expect(segments.historySegment(0).candidate(0).key == "12")
    #expect(segments.historySegment(0).candidate(0).value == "2")
    #expect(segments.historySegment(0).candidate(0).innerSegmentBoundary.isEmpty)
  }
}
