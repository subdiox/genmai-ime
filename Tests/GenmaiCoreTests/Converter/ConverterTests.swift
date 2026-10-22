// Port of mozc/src/converter/converter_test.cc (3.35.6354).
//
// Deviations from C++:
// - The C++ tests that build the converter through engine::Engine /
//   MockDataEngineFactory, prediction::Predictor or rewriter::Rewriter
//   (real predictors / rewriters) are ported with the stub predictor and
//   stub rewriter when their assertions only depend on the converter and the
//   immutable converter; the converter is built from `TestModules` (the
//   engine::Modules equivalent of the test support). Tests whose assertions
//   depend on the real predictor or rewriters (meta candidates, mobile
//   prediction, variant expansion, calculator / date / symbol / unicode /
//   small letter rewriter integration, learning) are not ported yet; they
//   belong with the engine port:
//   StartSuggestion, StartPartialPrediction, StartPartialSuggestion,
//   StartPartialPredictionMobile, StartPartialSuggestionMobile,
//   VariantExpansionForSuggestion, UserEntryInMobilePrediction,
//   UserEntryShouldBePromotedMobilePrediction,
//   SuppressionEntryShouldBePrioritizedPrediction,
//   AbbreviationShouldBeIndependentPrediction,
//   RewriterShouldRespectDefaultCandidates,
//   DoNotPromotePrefixOfSingleEntryForEnrichPartialCandidates,
//   DoNotAddOverlappingNodesForPrediction, IntegrationWith*Rewriter,
//   ApplyUserHistoryToConversionE2ETest.
// - gMock mocks are hand-written test doubles; gMock's default actions
//   (false / empty / no-op) are kept.

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private typealias UserEntry = Genmai_UserDictionary_UserDictionary.Entry
private typealias PosType = Genmai_UserDictionary_UserDictionary.PosType

@discardableResult
private func addSegment(_ key: String, _ type: Segment.SegmentType, _ segments: Segments) -> Segment {
  let segment = segments.addSegment()
  segment.setKey(key)
  segment.setSegmentType(type)
  return segment
}

private func pushBackCandidate(_ text: String, _ segment: Segment) {
  let cand = segment.pushBackCandidate()
  cand.key = text
  cand.contentKey = text
  cand.value = text
  cand.contentValue = text
}

private final class StubPredictor: PredictorInterface {
  func predict(_ request: ConversionRequest) -> [PredictionResult] {
    let key = request.key()
    if key.isEmpty {
      return []
    }
    var result = PredictionResult()
    result.key = key
    result.value = key
    return [result]
  }

  func getPredictorName() -> String { "StubPredictor" }
}

private final class StubRewriter: RewriterInterface {
  func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool { true }
}

private final class InsertPlaceholderWordsRewriter: RewriterInterface {
  func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    for segment in segments.conversionSegments {
      do {
        let cand = segment.addCandidate()
        cand.key = "tobefiltered"
        cand.value = "ToBeFiltered"
      }
      do {
        let cand = segment.addCandidate()
        cand.key = "nottobefiltered"
        cand.value = "NotToBeFiltered"
      }
    }
    return true
  }
}

private final class ResizeSegmentsRewriter: RewriterInterface {
  private let segmentIndex: Int
  private let segmentSizes: [UInt8]

  init(_ segmentIndex: Int, _ segmentSizes: [UInt8]) {
    self.segmentIndex = segmentIndex
    self.segmentSizes = segmentSizes
  }

  func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool { true }

  func checkResizeSegmentsRequest(_ request: ConversionRequest, _ segments: Segments)
    -> Rewriter.ResizeSegmentsRequest?
  {
    if segments.resized {
      return nil
    }
    return Rewriter.ResizeSegmentsRequest(segmentIndex: segmentIndex, segmentSizes: segmentSizes)
  }
}

private final class MockPredictor: PredictorInterface {
  var predictHandler: ((ConversionRequest) -> [PredictionResult])?
  var convertHandler: ((ConversionRequest) -> [PredictionResult])?
  var addHistoryEntryHandler: ((String, String) -> Bool)?
  private(set) var predictCount = 0
  private(set) var convertCount = 0
  private(set) var revertCount = 0
  private(set) var commitContextCount = 0
  private(set) var addHistoryEntryCount = 0

  func predict(_ request: ConversionRequest) -> [PredictionResult] {
    predictCount += 1
    return predictHandler?(request) ?? []
  }
  func convert(_ request: ConversionRequest) -> [PredictionResult] {
    convertCount += 1
    return convertHandler?(request) ?? []
  }
  func revert(_ revertId: UInt32) { revertCount += 1 }
  func getPredictorName() -> String { "" }
  func commitContext(_ request: ConversionRequest) { commitContextCount += 1 }
  func addHistoryEntry(_ key: String, _ value: String) -> Bool {
    addHistoryEntryCount += 1
    return addHistoryEntryHandler?(key, value) ?? false
  }
}

private final class MockRewriter: RewriterInterface {
  private(set) var revertCount = 0
  func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool { false }
  func revert(_ segments: Segments) { revertCount += 1 }
}

/// engine::MockSupplementalModel with IsAvailable() / PostCorrect()
/// overridden.
private final class TestSupplementalModel: ConverterSupplementalModel {
  let postCorrectHandler: (ConversionRequest, inout [PredictionResult]) -> Void
  init(_ postCorrectHandler: @escaping (ConversionRequest, inout [PredictionResult]) -> Void) {
    self.postCorrectHandler = postCorrectHandler
  }
  func isAvailable() -> Bool { true }
  func postCorrect(_ request: ConversionRequest, _ results: inout [PredictionResult]) {
    postCorrectHandler(request, &results)
  }
}

private func convReq(_ key: String, _ requestType: RequestType) -> ConversionRequest {
  var composer = Composer()
  composer.setPreeditTextForTestOnly(key)
  return ConversionRequestBuilder().setComposer(composer).setRequestType(requestType).build()
}

private func convReq(_ key: String, request: Genmai_Commands_Request, _ requestType: RequestType)
  -> ConversionRequest
{
  var composer = Composer()
  composer.setPreeditTextForTestOnly(key)
  return ConversionRequestBuilder().setComposer(composer).setRequest(request)
    .setRequestType(requestType).build()
}

private func createConverter(
  _ modules: TestModules, _ rewriter: any RewriterInterface,
  _ predictor: (any PredictorInterface)? = nil
) -> Converter {
  Converter(
    modules,
    { _ in modules.makeImmutableConverter() },
    { _, _, _ in predictor ?? StubPredictor() },
    { _ in rewriter })
}

private func createStubbedConverter() throws -> Converter {
  createConverter(try TestModules.mock(), StubRewriter())
}

private struct UserDefinedEntry {
  let key: String
  let value: String
  let pos: PosType
  init(_ key: String, _ value: String, _ pos: PosType) {
    self.key = key
    self.value = value
    self.pos = pos
  }
}

private func createConverterWithUserDefinedEntries(_ userDefinedEntries: [UserDefinedEntry]) async throws
  -> Converter
{
  let dataManager = try MockDataManager()
  let posMatcher = PosMatcher(dataManager.getPosMatcherData())
  let userPosData = dataManager.getUserPosData()
  let userDictionary = UserDictionary(
    UserPos(userPosData.tokenArray, userPosData.stringArray), posMatcher)
  // the reload started by init must not replace the entries loaded below
  await userDictionary.waitForReloader()
  do {
    var storage = Genmai_UserDictionary_UserDictionaryStorage()
    var dictionary = Genmai_UserDictionary_UserDictionary()
    for userEntry in userDefinedEntries {
      var entry = UserEntry()
      entry.key = userEntry.key
      entry.value = userEntry.value
      entry.pos = userEntry.pos
      dictionary.entries.append(entry)
    }
    storage.dictionaries.append(dictionary)
    userDictionary.load(storage)
  }
  let modules = try TestModules(dataManager, posMatcher: posMatcher, userDictionary: userDictionary)
  return createConverter(modules, StubRewriter())
}

private func findCandidateByValue(_ value: String, _ segment: Segment) -> Bool {
  getCandidateIndexByValue(value, segment) != -1
}

private func getCandidateIndexByValue(_ value: String, _ segment: Segment) -> Int {
  for i in 0..<segment.candidatesSize {
    if segment.candidate(i).value.bytesEqual(value) {
      return i
    }
  }
  return -1  // not found
}

private func requestWithLegacyMode(_ mode: Int32) -> Genmai_Commands_Request {
  var request = Genmai_Commands_Request()
  request.decoderExperimentParams.disableLegacyRewriterInAllConversionMode = mode
  return request
}

private let kLegacyHistoryModes =
  Rewriter.LegacyRewriterType.disableUserSegmentHistory
  | Rewriter.LegacyRewriterType.disableUserBoundaryHistory

@Suite("Converter")
struct ConverterTests {
  // test for issue:2209644
  // just checking whether this causes segmentation fault or not.
  @Test func canConvertTest() throws {
    let converter = try createStubbedConverter()
    do {
      let segments = Segments()
      #expect(converter.startConversion(convReq("-", .conversion), segments))
    }
    do {
      let segments = Segments()
      #expect(converter.startConversion(convReq("おきておきて", .conversion), segments))
    }
  }

  @Test func convertTest() throws {
    let converter = try createStubbedConverter()
    let segments = Segments()
    do {
      let convreq = convReq("ぐうぐる", .conversion)
      #expect(converter.startConversion(convreq, segments))
      #expect(segments.conversionSegmentsSize == 1)

      let index = getCandidateIndexByValue("Google", segments.conversionSegment(0))
      try #require(index != -1)
      #expect(converter.commitSegmentValue(segments, 0, index))
      converter.finishConversion(convreq, segments)
    }
    do {
      #expect(converter.startConversion(convReq("ぐーぐる", .conversion), segments))
      #expect(segments.conversionSegmentsSize == 1)

      let index = getCandidateIndexByValue("Google", segments.conversionSegment(0))
      try #require(index != -1)
      #expect(converter.commitSegmentValue(segments, 0, index))
    }
  }

  // Confirm that user dictionary words with alphabet keys are generated
  // after an alphabet history segment (Issue #1598).
  @Test func userDictionaryAlphabetKeyAfterAlphabetHistory() async throws {
    let converter = try await createConverterWithUserDefinedEntries([
      UserDefinedEntry("tyksk", "着席", .noun),
      UserDefinedEntry("tz", "地図", .noun),
      UserDefinedEntry("tz", "徳泉", .noun),
    ])

    let segments = Segments()
    // Scenario 1: Commit an alphabet word, then convert an alphabet-keyed user
    // word.
    do {
      let convreq = convReq("test", .conversion)
      #expect(converter.startConversion(convreq, segments))
      #expect(converter.commitSegmentValue(segments, 0, 0))
      converter.finishConversion(convreq, segments)
    }
    do {
      let convreq = convReq("tyksk", .conversion)
      #expect(converter.startConversion(convreq, segments))
      #expect(segments.conversionSegmentsSize == 1)
      #expect(findCandidateByValue("着席", segments.conversionSegment(0)))
      converter.cancelConversion(segments)
    }

    // Scenario 2: Commit an alphabet-keyed user word, then convert another.
    segments.clear()
    do {
      let convreq = convReq("tz", .conversion)
      #expect(converter.startConversion(convreq, segments))
      let index = getCandidateIndexByValue("地図", segments.conversionSegment(0))
      try #require(index != -1)
      #expect(converter.commitSegmentValue(segments, 0, index))
      converter.finishConversion(convreq, segments)
    }
    do {
      let convreq = convReq("tz", .conversion)
      #expect(converter.startConversion(convreq, segments))
      #expect(segments.conversionSegmentsSize == 1)
      #expect(findCandidateByValue("徳泉", segments.conversionSegment(0)))
    }
  }

  private func contextAwareConvert(_ firstKey: String, _ firstValue: String, _ secondKey: String)
    throws -> String
  {
    let converter = try createStubbedConverter()

    let segments = Segments()
    #expect(converter.startConversion(convReq(firstKey, .conversion), segments))

    var converted = ""
    var segmentNum = 0
    while true {
      var position = -1
      for i in 0..<segments.segment(segmentNum).candidatesSize {
        let value = segments.segment(segmentNum).candidate(i).value
        if firstValue.byteSubstring(from: converted.utf8.count, length: value.utf8.count)
          .bytesEqual(value)
        {
          position = i
          converted += value
          break
        }
      }

      if position < 0 {
        break
      }

      #expect(converter.commitSegmentValue(segments, 0, position), "\(firstValue)")

      segmentNum += 1

      if firstValue.bytesEqual(converted) {
        break
      }
    }
    #expect(firstValue == converted, "\(firstValue)")
    let defaultRequest = ConversionRequest()
    converter.finishConversion(defaultRequest, segments)
    #expect(converter.startConversion(convReq(secondKey, .conversion), segments))
    #expect(segments.segmentsSize == segmentNum + 1)

    return segments.segment(segmentNum).candidate(0).value
  }

  @Test func contextAwareConversionTest() throws {
    // Desirable context aware conversions
    #expect(try contextAwareConvert("きき", "危機", "いっぱつ") == "一髪")

    #expect(try contextAwareConvert("きょうと", "京都", "だい") == "大")
    #expect(try contextAwareConvert("きき", "危機", "かん") == "感")

    #expect(try contextAwareConvert("いのうえ", "井上", "ようすい") == "陽水")

    // Undesirable context aware conversions
    #expect(try contextAwareConvert("19じ", "19時", "しゅうごう") != "宗号")

    #expect(try contextAwareConvert("の", "の", "なまえ") != "な前")

    #expect(try contextAwareConvert("の", "の", "しりょう") != "し料")

    #expect(try contextAwareConvert("ぼくと", "僕と", "しらいさん") != "し礼賛")
  }

  @Test func commitSegmentValue() throws {
    let converter = try createStubbedConverter()
    let segments = Segments()

    do {
      // Prepare a segment, with candidates "1" and "2";
      let segment = segments.addSegment()
      segment.addCandidate().value = "1"
      segment.addCandidate().value = "2"
    }
    do {
      // Prepare a segment, with candidates "3" and "4";
      let segment = segments.addSegment()
      segment.addCandidate().value = "3"
      segment.addCandidate().value = "4"
    }
    do {
      // Commit the candidate whose value is "2".
      #expect(converter.commitSegmentValue(segments, 0, 1))
      #expect(segments.segmentsSize == 2)
      #expect(segments.historySegmentsSize == 0)
      #expect(segments.conversionSegmentsSize == 2)
      let segment = segments.conversionSegment(0)
      #expect(segment.segmentType == .fixedValue)
      #expect(segment.candidate(0).value == "2")
      #expect(segment.candidate(0).attributes & Attribute.reranked != 0)
    }
    do {
      // Make the segment SUBMITTED
      segments.mutableConversionSegment(0).setSegmentType(.submitted)
      #expect(segments.segmentsSize == 2)
      #expect(segments.historySegmentsSize == 1)
      #expect(segments.conversionSegmentsSize == 1)
    }
    do {
      // Commit the candidate whose value is "3".
      #expect(converter.commitSegmentValue(segments, 0, 0))
      #expect(segments.segmentsSize == 2)
      #expect(segments.historySegmentsSize == 1)
      #expect(segments.conversionSegmentsSize == 1)
      let segment = segments.conversionSegment(0)
      #expect(segment.segmentType == .fixedValue)
      #expect(segment.candidate(0).value == "3")
      #expect(segment.candidate(0).attributes & Attribute.reranked == 0)
    }
  }

  @Test func commitSegmentValueWithMultiSegmentCandidate() throws {
    let converter = try createStubbedConverter()
    let segments = Segments()

    segments.setMaxHistorySegmentsSize(3)
    do {
      let segment = segments.addSegment()
      segment.setKey("わたしの")
      let cand0 = segment.addCandidate()
      cand0.value = "私の"
      cand0.key = "わたしの"
      let cand1 = segment.addCandidate()
      cand1.value = "私の名前は"
      cand1.key = "わたしのなまえは"
      cand1.convertedSegmentCount = 2
    }
    do {
      let segment = segments.addSegment()
      segment.setKey("なまえは")
      let cand = segment.addCandidate()
      cand.value = "名前は"
      cand.key = "なまえは"
    }
    do {
      let segment = segments.addSegment()
      segment.setKey("なかのです")
      let cand = segment.addCandidate()
      cand.value = "中野です"
      cand.key = "なかのです"
    }

    try #require(segments.conversionSegmentsSize == 3)

    // CommitSegmentValue selects the multi-segment candidate without
    // destructively erasing segments.
    #expect(converter.commitSegmentValue(segments, 0, 1))
    #expect(segments.conversionSegmentsSize == 3)
    let seg0 = segments.conversionSegment(0)
    #expect(seg0.segmentType == .fixedValue)
    #expect(seg0.candidate(0).value == "私の名前は")
    #expect(seg0.candidate(0).convertedSegmentCount == 2)

    // FinishConversion merges the multi-segment candidate segments into
    // history segments.
    let request = ConversionRequestBuilder().setRequestType(.conversion).build()
    converter.finishConversion(request, segments)
    #expect(segments.conversionSegmentsSize == 0)
    try #require(segments.historySegmentsSize == 2)
    let finalSeg0 = segments.historySegment(0)
    #expect(finalSeg0.key == "わたしのなまえは")
    #expect(finalSeg0.candidate(0).value == "私の名前は")
    let finalSeg1 = segments.historySegment(1)
    #expect(finalSeg1.key == "なかのです")
    #expect(finalSeg1.candidate(0).value == "中野です")
  }

  @Test func commitSegments() throws {
    let converter = try createStubbedConverter()
    let segments = Segments()

    // History segment.
    do {
      let segment = segments.addSegment()
      segment.setKey("あした")
      segment.setSegmentType(.history)
      let candidate = segment.addCandidate()
      candidate.key = "あした"
      candidate.value = "今日"
    }

    do {
      let segment = segments.addSegment()
      segment.setKey("かつこうに")
      let candidate = segment.addCandidate()
      candidate.value = "学校に"
      candidate.key = "がっこうに"
    }

    do {
      let segment = segments.addSegment()
      segment.setKey("いく")
      let candidate = segment.addCandidate()
      candidate.value = "行く"
      candidate.key = "いく"
    }

    // Test "CommitFirstSegment" feature.
    do {
      // Commit 1st segment.
      try #require(converter.commitSegments(segments, [0]))

      #expect(segments.historySegmentsSize == 2)
      #expect(segments.conversionSegmentsSize == 1)
      #expect(segments.historySegment(0).segmentType == .history)
      #expect(segments.historySegment(1).segmentType == .submitted)
    }

    // Reset the test data.
    segments.mutableHistorySegment(1).setSegmentType(.free)

    // Test "CommitHeadToFocusedSegment" feature.
    do {
      // Commit 1st and 2nd segments.
      try #require(converter.commitSegments(segments, [0, 0]))

      #expect(segments.historySegmentsSize == 3)
      #expect(segments.conversionSegmentsSize == 0)
      #expect(segments.historySegment(0).segmentType == .history)
      #expect(segments.historySegment(1).segmentType == .submitted)
      #expect(segments.historySegment(2).segmentType == .submitted)
    }
  }

  @Test func commitSegmentsMultiSegment() throws {
    let converter = try createStubbedConverter()
    let segments = Segments()

    // Segment 0: multi-segment candidate covering segments 0 and 1.
    do {
      let segment = segments.addSegment()
      segment.setKey("ここでは")
      let candidate = segment.addCandidate()
      candidate.key = "ここではきものを"
      candidate.value = "ここで履物を"
      candidate.convertedSegmentCount = 2
    }
    // Segment 1: covered by segment 0's multi-segment candidate.
    do {
      let segment = segments.addSegment()
      segment.setKey("きものを")
      let candidate = segment.addCandidate()
      candidate.key = "きものを"
      candidate.value = "着物を"
    }
    // Segment 2: uncovered segment.
    do {
      let segment = segments.addSegment()
      segment.setKey("ぬぐ")
      let candidate = segment.addCandidate()
      candidate.key = "ぬぐ"
      candidate.value = "脱ぐ"
    }

    try #require(converter.commitSegments(segments, [0]))

    #expect(segments.historySegmentsSize == 1)
    #expect(segments.conversionSegmentsSize == 1)
    #expect(segments.historySegment(0).segmentType == .submitted)
    #expect(segments.historySegment(0).key == "ここではきものを")
    #expect(segments.historySegment(0).candidate(0).value == "ここで履物を")
    #expect(segments.historySegment(0).candidate(0).convertedSegmentCount == 1)
    #expect(segments.conversionSegment(0).key == "ぬぐ")
    #expect(segments.conversionSegment(0).candidate(0).value == "脱ぐ")
  }

  @Test func commitPartialSuggestionSegmentValue() throws {
    let converter = try createStubbedConverter()
    let segments = Segments()

    do {
      // Prepare a segment, with candidates "1" and "2";
      let segment = segments.addSegment()
      segment.addCandidate().value = "1"
      segment.addCandidate().value = "2"
    }
    do {
      // Prepare a segment, with candidates "3" and "4";
      let segment = segments.addSegment()
      segment.addCandidate().value = "3"
      segment.addCandidate().value = "4"
    }
    do {
      // Commit the candidate whose value is "2".
      #expect(converter.commitPartialSuggestionSegmentValue(segments, 0, 1, "left2", "right2"))
      #expect(segments.segmentsSize == 3)
      #expect(segments.historySegmentsSize == 1)
      #expect(segments.conversionSegmentsSize == 2)
      do {
        // The tail segment of the history segments uses
        // CommitPartialSuggestionSegmentValue's |current_segment_key|
        // parameter and contains original value.
        let segment = segments.historySegment(segments.historySegmentsSize - 1)
        #expect(segment.segmentType == .submitted)
        #expect(segment.candidate(0).value == "2")
        #expect(segment.key == "left2")
        #expect(segment.candidate(0).attributes & Attribute.reranked != 0)
      }
      do {
        // The head segment of the conversion segments uses |new_segment_key|.
        let segment = segments.conversionSegment(0)
        #expect(segment.segmentType == .free)
        #expect(segment.key == "right2")
      }
    }
  }

  @Test func candidateKeyTest() throws {
    let converter = try createStubbedConverter()
    let segments = Segments()
    #expect(converter.startConversion(convReq("わたしは", .conversion), segments))
    try #require(segments.segmentsSize == 1)
    #expect(segments.segment(0).candidate(0).key == "わたしは")
    #expect(segments.segment(0).candidate(0).contentKey == "わたし")
  }

  @Test func regression3437022() throws {
    let modules = try TestModules.mock()
    let converter = createConverter(modules, StubRewriter())
    let segments = Segments()

    let kKey1 = "けいたい"
    let kKey2 = "でんわ"

    let kValue1 = "携帯"
    let kValue2 = "電話"

    do {
      // Make sure convert result is one segment
      #expect(converter.startConversion(convReq(kKey1 + kKey2, .conversion), segments))
      try #require(segments.conversionSegmentsSize == 1)
      #expect(segments.conversionSegment(0).candidate(0).value == kValue1 + kValue2)
    }
    do {
      // Make sure we can convert first part
      segments.clear()
      #expect(converter.startConversion(convReq(kKey1, .conversion), segments))
      try #require(segments.conversionSegmentsSize == 1)
      #expect(segments.conversionSegment(0).candidate(0).value == kValue1)
    }
    do {
      // Make sure we can convert last part
      segments.clear()
      #expect(converter.startConversion(convReq(kKey2, .conversion), segments))
      try #require(segments.conversionSegmentsSize == 1)
      #expect(segments.conversionSegment(0).candidate(0).value == kValue2)
    }

    segments.clear()

    // Add compound entry to suppression dictionary
    do {
      var storage = Genmai_UserDictionary_UserDictionaryStorage()
      var dictionary = Genmai_UserDictionary_UserDictionary()
      var entry = UserEntry()
      entry.key = kKey1 + kKey2
      entry.value = kValue1 + kValue2
      entry.pos = .suppressionWord
      dictionary.entries.append(entry)
      storage.dictionaries.append(dictionary)
      _ = modules.getUserDictionary().load(storage)
      #expect(modules.getUserDictionary().hasSuppressedEntries())
    }

    #expect(converter.startConversion(convReq(kKey1 + kKey2, .conversion), segments))

    var restSize = 0
    for segment in segments.conversionSegments.dropFirst() {
      restSize += Util.charsLen(segment.candidate(0).key)
    }

    // Expand segment so that the entire part will become one segment
    if restSize > 0 {
      let defaultRequest = ConversionRequest()
      #expect(converter.resizeSegment(segments, defaultRequest, 0, restSize))
    }

    try #require(segments.conversionSegmentsSize == 1)
    #expect(segments.conversionSegment(0).candidate(0).value != kValue1 + kValue2)
  }

  @Test func completePosIds() throws {
    let kTestKeys = [
      "きょうと", "いきます", "うつくしい", "おおきな", "いっちゃわないね", "わたしのなまえはなかのです",
    ]

    let converter = try createStubbedConverter()
    for testKey in kTestKeys {
      let segments = Segments()
      let seg = segments.addSegment()
      seg.setKey(testKey)
      seg.setSegmentType(.free)
      var options = ConversionOptions()
      options.requestType = .prediction
      options.maxConversionCandidatesSize = 20
      let request = ConversionRequestBuilder().setOptions(options).build()
      try #require(converter.immutableConverter.convert(request.options(), segments))
      let lid = segments.segment(0).candidate(0).lid
      let rid = segments.segment(0).candidate(0).rid
      let candidate = Candidate()
      candidate.value = segments.segment(0).candidate(0).value
      candidate.key = segments.segment(0).candidate(0).key
      candidate.lid = 0
      candidate.rid = 0
      converter.completePosIds(candidate)
      #expect(candidate.lid == lid)
      #expect(candidate.rid == rid)
      #expect(candidate.lid != 0)
      #expect(candidate.rid != 0)
    }

    do {
      let candidate = Candidate()
      candidate.key = "test"
      candidate.value = "test"
      candidate.lid = 10
      candidate.rid = 11
      converter.completePosIds(candidate)
      #expect(candidate.lid == 10)
      #expect(candidate.rid == 11)
    }
  }

  @Test func regression3046266() throws {
    // Shouldn't correct nodes at the beginning of a sentence.
    let converter = try createStubbedConverter()
    let segments = Segments()

    // Can be any string that has "ん" at the end
    let kKey1 = "かん"

    // Can be any string that has a vowel at the beginning
    let kKey2 = "あか"

    let kValueNotExpected = "中"

    #expect(converter.startConversion(convReq(kKey1, .conversion), segments))
    #expect(segments.conversionSegmentsSize == 1)
    #expect(converter.commitSegmentValue(segments, 0, 0))

    let defaultRequest = ConversionRequest()
    converter.finishConversion(defaultRequest, segments)

    #expect(converter.startConversion(convReq(kKey2, .conversion), segments))
    try #require(segments.conversionSegmentsSize == 1)
    let segment = segments.conversionSegment(0)
    for i in 0..<segment.candidatesSize {
      #expect(segment.candidate(i).value != kValueNotExpected)
    }
  }

  @Test func regression5502496() throws {
    // Make sure key correction works for the first word of a sentence.
    let converter = try createStubbedConverter()
    let segments = Segments()

    let kKey = "みんあ"
    let kValueExpected = "みんな"

    #expect(converter.startConversion(convReq(kKey, .conversion), segments))
    try #require(segments.conversionSegmentsSize == 1)
    #expect(findCandidateByValue(kValueExpected, segments.conversionSegment(0)))
  }

  @Test func maybeSetConsumedKeySizeToSegment() {
    let consumedKeySize = 5
    let originalConsumedKeySize: UInt32 = 10

    let segment = Segment()
    // 1st candidate without PARTIALLY_KEY_CONSUMED
    _ = segment.pushBackCandidate()
    // 2nd candidate with PARTIALLY_KEY_CONSUMED
    let candidate2 = segment.pushBackCandidate()
    candidate2.attributes |= Attribute.partiallyKeyConsumed
    candidate2.consumedKeySize = originalConsumedKeySize
    // 1st meta candidate without PARTIALLY_KEY_CONSUMED
    _ = segment.addMetaCandidate()
    // 2nd meta candidate with PARTIALLY_KEY_CONSUMED
    let metaCandidate2 = segment.addMetaCandidate()
    metaCandidate2.attributes |= Attribute.partiallyKeyConsumed
    metaCandidate2.consumedKeySize = originalConsumedKeySize

    Converter.maybeSetConsumedKeySizeToSegment(consumedKeySize, segment)
    #expect(segment.candidate(0).attributes & Attribute.partiallyKeyConsumed != 0)
    #expect(segment.candidate(0).consumedKeySize == UInt32(consumedKeySize))
    #expect(segment.candidate(1).attributes & Attribute.partiallyKeyConsumed != 0)
    #expect(segment.candidate(1).consumedKeySize == originalConsumedKeySize)
    #expect(segment.metaCandidate(0).attributes & Attribute.partiallyKeyConsumed != 0)
    #expect(segment.metaCandidate(0).consumedKeySize == UInt32(consumedKeySize))
    #expect(segment.metaCandidate(1).attributes & Attribute.partiallyKeyConsumed != 0)
    #expect(segment.metaCandidate(1).consumedKeySize == originalConsumedKeySize)
  }

  @Test func predictSetKey() throws {
    let kPredictionKey = "prediction key"
    let kPredictionKey2 = "prediction key2"
    // Tests whether SetKey method is called or not.
    struct TestData {
      // Input conditions.
      let key: String?  // Input key presence.
      let expectSetKeyIsCalled: Bool
    }
    let testDataList = [
      TestData(key: nil, expectSetKeyIsCalled: true),
      TestData(key: kPredictionKey2, expectSetKeyIsCalled: true),
      // This is the only case where SetKey() is not called; because SetKey is
      // not requested in Request and Segments' key is already present.
      TestData(key: kPredictionKey, expectSetKeyIsCalled: false),
    ]

    let converter = try createStubbedConverter()

    for testData in testDataList {
      let segments = Segments()
      var origCandidatesSize = 0
      if let key = testData.key {
        let seg = segments.addSegment()
        seg.setKey(key)
        pushBackCandidate(key, seg)
        origCandidatesSize = seg.candidatesSize
      }

      var composer = Composer()
      composer.setPreeditTextForTestOnly(kPredictionKey)
      let request = ConversionRequestBuilder()
        .setComposer(composer)
        .setHistoryResult(ConverterUtil.historySegmentsToResult(segments))
        .setRequestType(.prediction)
        .build()
      try #require(converter.startPrediction(request, segments))

      try #require(segments.conversionSegmentsSize == 1)
      #expect(segments.conversionSegment(0).key == kPredictionKey)
      if testData.expectSetKeyIsCalled {
        // If SetKey is called, the segment has only one candidate populated
        // by StubPredictor.
        #expect(segments.conversionSegment(0).candidatesSize == 1)
      } else {
        // If SetKey is not called, the segment has been added one candidate
        // by StubPredictor.
        #expect(segments.conversionSegment(0).candidatesSize == origCandidatesSize + 1)
      }
    }
  }

  @Test func composerKeySelection() throws {
    let converter = try createStubbedConverter()
    let table = Table()
    let config = Genmai_Config_Config()
    let defaultRequest = Genmai_Commands_Request()
    do {
      let segments = Segments()
      var composer = Composer(table, defaultRequest, config)
      composer.insertCharacterPreedit("わたしh")

      var options = ConversionOptions()
      options.composerKeySelection = .conversionKey
      let request = ConversionRequestBuilder()
        .setComposer(composer)
        .setHistoryResult(ConverterUtil.historySegmentsToResult(segments))
        .setOptions(options)
        .build()
      try #require(converter.startConversion(request, segments))
      try #require(segments.conversionSegmentsSize == 2)
      #expect(segments.conversionSegment(0).candidate(0).value == "私")
      #expect(segments.conversionSegment(1).candidate(0).value == "h")
    }
    do {
      let segments = Segments()
      var composer = Composer(table, defaultRequest, config)
      composer.insertCharacterPreedit("わたしh")

      var options = ConversionOptions()
      options.composerKeySelection = .predictionKey
      let request = ConversionRequestBuilder()
        .setComposer(composer)
        .setHistoryResult(ConverterUtil.historySegmentsToResult(segments))
        .setOptions(options)
        .build()
      try #require(converter.startConversion(request, segments))
      try #require(segments.conversionSegmentsSize == 1)
      #expect(segments.conversionSegment(0).candidate(0).value == "私")
    }
  }

  @Test func suppressionDictionaryForRewriter() throws {
    let modules = try TestModules.mock()
    let converter = createConverter(modules, InsertPlaceholderWordsRewriter())

    // Set up suppression dictionary
    do {
      var storage = Genmai_UserDictionary_UserDictionaryStorage()
      var dictionary = Genmai_UserDictionary_UserDictionary()
      var entry = UserEntry()
      entry.key = "tobefiltered"
      entry.value = "ToBeFiltered"
      entry.pos = .suppressionWord
      dictionary.entries.append(entry)
      storage.dictionaries.append(dictionary)
      _ = modules.getUserDictionary().load(storage)
      #expect(modules.getUserDictionary().hasSuppressedEntries())
    }

    // Convert
    let table = Table()
    let config = Genmai_Config_Config()
    var composer = Composer(table, Genmai_Commands_Request(), config)
    composer.insertCharacter("placeholder")
    let segments = Segments()
    let request = ConversionRequestBuilder()
      .setComposer(composer)
      .setHistoryResult(ConverterUtil.historySegmentsToResult(segments))
      .setConfig(config)
      .build()
    #expect(converter.startConversion(request, segments))

    // Verify that words inserted by the rewriter is suppressed if its in the
    // suppression_dictionary.
    for segment in segments.conversionSegments {
      #expect(!findCandidateByValue("ToBeFiltered", segment))
      #expect(findCandidateByValue("NotToBeFiltered", segment))
    }
  }

  @Test func emptyConvertReverseIssue8661091() throws {
    // This is a test case against b/8661091.
    let converter = try createStubbedConverter()
    let segments = Segments()
    #expect(!converter.startReverseConversion(segments, ""))
  }

  @Test func startReverseConversion() throws {
    let converter = try createStubbedConverter()

    let kHonKanji = "本"
    let kHonHiragana = "ほん"
    let kMuryouKanji = "無料"
    let kMuryouHiragana = "むりょう"
    let kFullWidthSpace = "　"  // full-width space

    func convert(_ input: String) -> [String]? {
      let segments = Segments()
      guard converter.startReverseConversion(segments, input) else { return nil }
      return segments.conversionSegments.map {
        $0.candidatesSize > 0 ? $0.candidate(0).value : "<none>"
      }
    }

    // Test for single Kanji character.
    #expect(convert(kHonKanji) == [kHonHiragana])
    // Test for multi-Kanji character.
    #expect(convert(kMuryouKanji) == [kMuryouHiragana])
    // Test for multi terms separated by a space.
    #expect(convert(kHonKanji + " " + kMuryouKanji) == [kHonHiragana, " ", kMuryouHiragana])
    // Test for multi terms separated by multiple spaces.
    #expect(convert(kHonKanji + "   " + kMuryouKanji) == [kHonHiragana, "   ", kMuryouHiragana])
    // Test for leading white spaces.
    #expect(convert("  " + kHonKanji) == ["  ", kHonHiragana])
    // Test for trailing white spaces.
    #expect(convert(kMuryouKanji + "  ") == [kMuryouHiragana, "  "])
    // Test for multi terms separated by a full-width space.
    #expect(
      convert(kHonKanji + kFullWidthSpace + kMuryouKanji)
        == [kHonHiragana, kFullWidthSpace, kMuryouHiragana])
    // Test for multi terms separated by two full-width spaces.
    let kFullWidthSpace2 = kFullWidthSpace + kFullWidthSpace
    #expect(
      convert(kHonKanji + kFullWidthSpace2 + kMuryouKanji)
        == [kHonHiragana, kFullWidthSpace2, kMuryouHiragana])
    // Test for multi terms separated by the mix of full- and half-width
    // spaces.
    let kFullWidthSpaceMix = kFullWidthSpace + " "
    #expect(
      convert(kHonKanji + kFullWidthSpaceMix + kMuryouKanji)
        == [kHonHiragana, kFullWidthSpaceMix, kMuryouHiragana])
    // Test for math expressions; see b/9398304.
    let kInputHalf = "365*24*60*60*1000="
    #expect(convert(kInputHalf) == [kInputHalf])
    // Test for full-width characters.
    #expect(convert("３６５＊２４＊６０＊６０＊１０００＝") == [kInputHalf])
  }

  @Test func reconstructHistory() throws {
    let converter = try createStubbedConverter()

    let kTen = "１０"

    let segments = Segments()
    #expect(converter.reconstructHistory(segments, kTen))
    try #require(segments.segmentsSize == 1)
    let segment = segments.segment(0)
    #expect(segment.segmentType == .history)
    #expect(segment.key == "10")
    try #require(segment.candidatesSize == 1)
    let candidate = segment.candidate(0)
    #expect(candidate.attributes == Attribute.noLearning)
    #expect(candidate.contentKey == "10")
    #expect(candidate.key == "10")
    #expect(candidate.contentValue == kTen)
    #expect(candidate.value == kTen)
    #expect(candidate.lid != 0)
    #expect(candidate.rid != 0)
  }

  @Test func limitCandidatesSize() throws {
    let converter = try createStubbedConverter()

    let table = Table()
    let config = ConfigHandler.defaultConfig()
    var requestProto = Genmai_Commands_Request()
    var composer = Composer(table, requestProto, config)
    composer.insertCharacterPreedit("あ")
    let segments = Segments()
    let request1 = ConversionRequestBuilder()
      .setComposer(composer)
      .setHistoryResult(ConverterUtil.historySegmentsToResult(segments))
      .setRequest(requestProto)
      .build()
    try #require(converter.startConversion(request1, segments))
    try #require(segments.conversionSegmentsSize == 1)
    let originalCandidatesSize = segments.segment(0).candidatesSize
    let originalMetaCandidatesSize = segments.segment(0).metaCandidatesSize
    #expect(
      0 < originalCandidatesSize - 1 - originalMetaCandidatesSize,
      "original candidates size: \(originalCandidatesSize), original meta candidates size: \(originalMetaCandidatesSize)"
    )

    segments.clear()
    requestProto.candidatesSizeLimit = Int32(originalCandidatesSize - 1)
    let request2 = ConversionRequestBuilder()
      .setComposer(composer)
      .setRequest(requestProto)
      .setHistoryResult(ConverterUtil.historySegmentsToResult(segments))
      .build()
    try #require(converter.startConversion(request2, segments))
    try #require(segments.conversionSegmentsSize == 1)
    #expect(originalCandidatesSize - 1 >= segments.segment(0).candidatesSize)
    #expect(
      originalCandidatesSize - 1 - originalMetaCandidatesSize <= segments.segment(0).candidatesSize)
    #expect(segments.segment(0).metaCandidatesSize == originalMetaCandidatesSize)

    segments.clear()
    requestProto.candidatesSizeLimit = 0
    let request3 = ConversionRequestBuilder()
      .setComposer(composer)
      .setRequest(requestProto)
      .setHistoryResult(ConverterUtil.historySegmentsToResult(segments))
      .build()
    try #require(converter.startConversion(request3, segments))
    try #require(segments.conversionSegmentsSize == 1)
    #expect(segments.segment(0).candidatesSize == 1)
    #expect(segments.segment(0).metaCandidatesSize == originalMetaCandidatesSize)
  }

  @Test func userEntryShouldBePromoted() async throws {
    // "哀" is not in the test dictionary
    let converter = try await createConverterWithUserDefinedEntries([
      UserDefinedEntry("あい", "哀", .noun)
    ])

    let segments = Segments()
    #expect(converter.startConversion(convReq("あい", .conversion), segments))
    try #require(segments.conversionSegmentsSize == 1)
    try #require(1 < segments.conversionSegment(0).candidatesSize)
    #expect(segments.conversionSegment(0).candidate(0).value == "哀")
  }

  @Test func suppressionEntryShouldBePrioritized() async throws {
    // "哀" is not in the test dictionary
    let converter = try await createConverterWithUserDefinedEntries([
      UserDefinedEntry("あい", "哀", .noun),
      UserDefinedEntry("あい", "哀", .suppressionWord),
    ])

    let segments = Segments()
    #expect(converter.startConversion(convReq("あい", .conversion), segments))
    try #require(segments.conversionSegmentsSize == 1)
    try #require(1 < segments.conversionSegment(0).candidatesSize)
    #expect(!findCandidateByValue("哀", segments.conversionSegment(0)))
  }

  @Test func abbreviationShouldBeIndependent() async throws {
    let converter = try await createConverterWithUserDefinedEntries([
      UserDefinedEntry("じゅ", "Google+", .abbreviation)
    ])

    let segments = Segments()
    #expect(converter.startConversion(convReq("じゅうじか", .conversion), segments))
    try #require(segments.conversionSegmentsSize == 1)
    #expect(!findCandidateByValue("Google+うじか", segments.conversionSegment(0)))
  }

  @Test func suggestionOnlyShouldBeIndependent() async throws {
    let converter = try await createConverterWithUserDefinedEntries([
      UserDefinedEntry("じゅ", "Google+", .suggestionOnly)
    ])

    let segments = Segments()
    #expect(converter.startConversion(convReq("じゅうじか", .conversion), segments))
    try #require(segments.conversionSegmentsSize == 1)
    #expect(!findCandidateByValue("Google+うじか", segments.conversionSegment(0)))
  }

  // The C++ test runs StartConversion with the default and mobile
  // predictors; StartConversion does not call Predict, so the stub predictor
  // is used.
  @Test func suggestionOnlyShouldBeIndependentPrediction() async throws {
    let converter = try await createConverterWithUserDefinedEntries([
      UserDefinedEntry("じゅ", "Google+", .suggestionOnly)
    ])

    let segments = Segments()
    #expect(converter.startConversion(convReq("じゅうじか", .conversion), segments))
    try #require(segments.conversionSegmentsSize == 1)
    #expect(!findCandidateByValue("Google+うじか", segments.conversionSegment(0)))
  }

  @Test func revertConversion() throws {
    let mockPredictor = MockPredictor()
    let mockRewriter = MockRewriter()
    let converter = createConverter(try TestModules.mock(), mockRewriter, mockPredictor)

    let segments = Segments()
    segments.setRevertId(10)

    converter.revertConversion(segments)
    #expect(mockPredictor.revertCount == 1)
    #expect(mockRewriter.revertCount == 1)
  }

  @Test func resizeSegmentWithOffset() throws {
    let converter = try createStubbedConverter()

    do {
      // Resize {"あいうえ"} to {"あいう", "え"}
      let segments = Segments()
      addSegment("あいうえ", .free, segments)
      let convreq = ConversionRequest()
      #expect(segments.conversionSegmentsSize == 1)
      #expect(converter.resizeSegment(segments, convreq, 0, -1))
      try #require(segments.conversionSegmentsSize == 2)
      #expect(segments.conversionSegment(0).key == "あいう")
      #expect(segments.conversionSegment(1).key == "え")
      #expect(segments.conversionSegment(0).segmentType == .fixedBoundary)
      #expect(segments.conversionSegment(1).segmentType == .free)
    }

    do {
      // Resize {"あ", "い", "う", "え"} to {"あいう", "え"}
      let segments = Segments()
      addSegment("あ", .free, segments)
      addSegment("い", .free, segments)
      addSegment("う", .free, segments)
      addSegment("え", .free, segments)
      let convreq = ConversionRequest()
      #expect(segments.conversionSegmentsSize == 4)
      #expect(converter.resizeSegment(segments, convreq, 0, 2))
      try #require(segments.conversionSegmentsSize == 2)
      #expect(segments.conversionSegment(0).key == "あいう")
      #expect(segments.conversionSegment(1).key == "え")
      #expect(segments.conversionSegment(0).segmentType == .fixedBoundary)
      #expect(segments.conversionSegment(1).segmentType == .free)
    }

    do {
      // Resize {"あ", "い", "う", "え"} to {"あ", "いう", "え"}
      let segments = Segments()
      addSegment("あ", .free, segments)
      addSegment("い", .free, segments)
      addSegment("う", .free, segments)
      addSegment("え", .free, segments)
      let convreq = ConversionRequest()
      #expect(segments.conversionSegmentsSize == 4)
      #expect(converter.resizeSegment(segments, convreq, 1, 1))
      try #require(segments.conversionSegmentsSize == 3)
      #expect(segments.conversionSegment(0).key == "あ")
      #expect(segments.conversionSegment(1).key == "いう")
      #expect(segments.conversionSegment(2).key == "え")
      #expect(segments.conversionSegment(0).segmentType == .free)
      #expect(segments.conversionSegment(1).segmentType == .fixedBoundary)
      #expect(segments.conversionSegment(2).segmentType == .free)
    }

    do {
      // Invalid offset: 0
      let segments = Segments()
      addSegment("あい", .free, segments)
      #expect(!converter.resizeSegment(segments, ConversionRequest(), 0, 0))
    }

    do {
      // Invalid offset: more than the end of the segment
      let segments = Segments()
      addSegment("あい", .free, segments)
      #expect(!converter.resizeSegment(segments, ConversionRequest(), 0, 1))
    }

    do {
      // Invalid offset: less than the start of the segment
      let segments = Segments()
      addSegment("あい", .free, segments)
      #expect(!converter.resizeSegment(segments, ConversionRequest(), 0, -2))
    }
  }

  @Test func resizeSegmentsWithArray() throws {
    let converter = try createStubbedConverter()

    func keysAndTypes(_ segments: Segments) -> [String] {
      segments.conversionSegments.map { "\($0.key):\($0.segmentType)" }
    }

    do {
      // Resize {"あいうえ"} to {"あいう", "え"}
      let segments = Segments()
      addSegment("あいうえ", .free, segments)
      #expect(converter.resizeSegments(segments, ConversionRequest(), 0, [3, 1]))
      #expect(keysAndTypes(segments) == ["あいう:fixedBoundary", "え:fixedBoundary"])
    }

    do {
      // Resize {"あいうえ"} to {"あいう", "え"} with history segments.
      // Even if segments has histroy segments, arguments for ResizeSegment is
      // not changed.
      let segments = Segments()
      pushBackCandidate("ヤユヨ", addSegment("やゆよ", .history, segments))
      pushBackCandidate("ワヲン", addSegment("わをん", .history, segments))
      addSegment("あいうえ", .free, segments)
      #expect(segments.conversionSegmentsSize == 1)
      #expect(converter.resizeSegments(segments, ConversionRequest(), 0, [3, 1]))
      #expect(keysAndTypes(segments) == ["あいう:fixedBoundary", "え:fixedBoundary"])
    }

    do {
      // Resize {"あいうえ"} to {"あいう", "え"} where size_array contains 0
      // values.
      let segments = Segments()
      addSegment("あいうえ", .free, segments)
      #expect(converter.resizeSegments(segments, ConversionRequest(), 0, [3, 1, 0, 0, 0, 0, 0, 0]))
      #expect(keysAndTypes(segments) == ["あいう:fixedBoundary", "え:fixedBoundary"])
    }

    do {
      // Resize {"あいうえおかきくけ"} to {"あい", "うえ", "お", "かき", "くけ"}
      let segments = Segments()
      addSegment("あいうえおかきくけ", .free, segments)
      #expect(converter.resizeSegments(segments, ConversionRequest(), 0, [2, 2, 1, 2, 2]))
      #expect(
        keysAndTypes(segments) == [
          "あい:fixedBoundary", "うえ:fixedBoundary", "お:fixedBoundary", "かき:fixedBoundary",
          "くけ:fixedBoundary",
        ])
    }

    do {
      // Resize {"あいう", "えお", "かき", "くけ"} to
      // {"あいうえ", "お", "かきくけ"}
      let segments = Segments()
      addSegment("あいう", .free, segments)
      addSegment("えお", .free, segments)
      addSegment("かき", .free, segments)
      addSegment("くけ", .free, segments)
      #expect(converter.resizeSegments(segments, ConversionRequest(), 0, [4, 1, 4]))
      #expect(
        keysAndTypes(segments) == ["あいうえ:fixedBoundary", "お:fixedBoundary", "かきくけ:fixedBoundary"])
    }

    do {
      // Resize {"あいう", "えお", "かき", "くけ"} to
      // {"あいうえ", "お"} and keeping {"かき", "くけ"} as-is.
      let segments = Segments()
      addSegment("あいう", .free, segments)
      addSegment("えお", .free, segments)
      addSegment("かき", .free, segments)
      addSegment("くけ", .free, segments)
      #expect(converter.resizeSegments(segments, ConversionRequest(), 0, [4, 1]))
      #expect(
        keysAndTypes(segments) == ["あいうえ:fixedBoundary", "お:fixedBoundary", "かき:free", "くけ:free"])
    }

    do {
      // Resize {"あいうえ"} to {"あいう"} and keeping {"え"} as-is.
      let segments = Segments()
      addSegment("あいうえ", .free, segments)
      #expect(converter.resizeSegments(segments, ConversionRequest(), 0, [3]))
      // Non specified segment (i.e. "え") is FREE to keep the consistency
      // with ResizeSegment.
      #expect(keysAndTypes(segments) == ["あいう:fixedBoundary", "え:free"])
    }

    do {
      // Resize {"あいう", "えお", "かき", "くけ"} to {"かきくけ"} while
      // {"あいう", "えお"} are free to be modified.
      let segments = Segments()
      addSegment("あいう", .free, segments)
      addSegment("えお", .free, segments)
      addSegment("かき", .free, segments)
      addSegment("くけ", .free, segments)
      #expect(converter.resizeSegments(segments, ConversionRequest(), 2, [4]))

      // Since {"あいう", "えお"} may be modified too, the segment index for
      // "かきくけ" may be different from 2.
      let resizedSize = segments.conversionSegmentsSize
      let lastSegment = segments.conversionSegment(resizedSize - 1)
      #expect(lastSegment.key == "かきくけ")
      #expect(lastSegment.segmentType == .fixedBoundary)
    }
  }

  @Test func resizeSegmentsRequest() throws {
    do {
      let converter = createConverter(
        try TestModules.mock(), ResizeSegmentsRewriter(0, [1, 2, 3, 0, 0, 0, 0, 0]))

      let segments = Segments()
      let convreq = ConversionRequestBuilder().setKey("あいうえおかき").build()
      try #require(converter.startConversion(convreq, segments))

      #expect(segments.conversionSegments.map(\.key) == ["あ", "いう", "えおか", "き"])
    }

    do {
      let converter = createConverter(
        try TestModules.mock(), ResizeSegmentsRewriter(0, [3, 3, 0, 0, 0, 0, 0, 0]))

      let segments = Segments()
      let convreq = ConversionRequestBuilder().setKey("あいうえおかき").build()
      try #require(converter.startConversion(convreq, segments))

      #expect(segments.conversionSegments.map(\.key) == ["あいう", "えおか", "き"])
    }

    do {
      let converter = createConverter(
        try TestModules.mock(), ResizeSegmentsRewriter(1, [1, 2, 0, 0, 0, 0, 0, 0]))

      let segments = Segments()
      let convreq = ConversionRequestBuilder().setKey("あいうえおかき").build()
      try #require(converter.startConversion(convreq, segments))

      // The total size of segments and the size of the first segment are not
      // specified.
      try #require(segments.conversionSegmentsSize >= 3)
      try #require(Util.charsLen(segments.conversionSegment(0).key) <= 4)

      #expect(Util.charsLen(segments.conversionSegment(1).key) == 1)
      #expect(Util.charsLen(segments.conversionSegment(2).key) == 2)
    }
  }

  @Test func populateReadingOfCommittedCandidateIfMissing() throws {
    let converter = try createStubbedConverter()
    let convreq = ConversionRequestBuilder().setRequestType(.conversion).build()

    // Test the case where value == content_value.
    do {
      let segments = Segments()
      let segment = segments.addSegment()

      let cand1 = segment.addCandidate()
      cand1.value = "東京"
      cand1.contentValue = "東京"

      let cand2 = segment.addCandidate()
      cand2.value = "大阪"
      cand2.contentValue = "大阪"

      let cand3 = segment.addCandidate()
      cand3.value = "群馬"
      cand3.contentValue = "群馬"

      converter.finishConversion(convreq, segments)
      #expect(cand1.key == "とうきょう")
      #expect(cand1.contentKey == "とうきょう")
      #expect(cand2.key.isEmpty)
      #expect(cand2.contentKey.isEmpty)
      #expect(cand3.key.isEmpty)
      #expect(cand3.contentKey.isEmpty)
    }
    // Test the case where value != content_value.
    do {
      let segments = Segments()
      let segment = segments.addSegment()

      let cand1 = segment.addCandidate()
      cand1.value = "東京に"
      cand1.contentValue = "東京"

      let cand2 = segment.addCandidate()
      cand2.value = "大阪に"
      cand2.contentValue = "大阪"

      let cand3 = segment.addCandidate()
      cand3.value = "群馬に"
      cand3.contentValue = "群馬"

      converter.finishConversion(convreq, segments)
      #expect(cand1.key == "とうきょうに")
      #expect(cand1.contentKey == "とうきょう")
      #expect(cand2.key.isEmpty)
      #expect(cand2.contentKey.isEmpty)
      #expect(cand3.key.isEmpty)
      #expect(cand3.contentKey.isEmpty)
    }
    // Test the case where value != content_value and the functional value is
    // not Hiragana. We cannot add the reading in this case.
    do {
      let segments = Segments()
      let segment = segments.addSegment()

      let cand1 = segment.addCandidate()
      cand1.value = "東京便"
      cand1.contentValue = "東京"

      converter.finishConversion(convreq, segments)
      #expect(cand1.key.isEmpty)
      #expect(cand1.contentKey.isEmpty)
    }
    // Test the case where value != content_value and content_value is empty.
    do {
      let segments = Segments()
      let segment = segments.addSegment()

      let cand1 = segment.addCandidate()
      cand1.value = "東京"
      cand1.contentValue = ""

      converter.finishConversion(convreq, segments)
      #expect(cand1.key.isEmpty)
      #expect(cand1.contentKey.isEmpty)
    }
  }

  @Test func bugfix424676259() throws {
    let mockPredictor = MockPredictor()
    let mockRewriter = MockRewriter()

    var result = PredictionResult()
    result.key = "3:30から"
    result.value = "３：３０から"

    // 3|:|30から
    result.innerSegmentBoundary = buildInnerSegmentBoundary(
      [
        (1, 3, 1, 3),  // 3
        (1, 3, 1, 3),  // :
        (8, 12, 2, 6),  // ３０_から
      ], result.key, result.value)

    let results = [result]
    mockPredictor.predictHandler = { _ in results }

    let converter = createConverter(try TestModules.mock(), mockRewriter, mockPredictor)

    var request = Genmai_Commands_Request()
    request.mixedConversion = true
    let convreq = ConversionRequestBuilder()
      .setRequestView(request)
      .setRequestType(.suggestion)
      .build()

    let segments = Segments()
    #expect(converter.startPrediction(convreq, segments))

    try #require(segments.segmentsSize == 1)
    let segment = segments.segment(0)
    try #require(segment.candidatesSize == 1)
    let candidate = segment.candidate(0)

    #expect(candidate.key == "3:30から")
    #expect(candidate.value == "３：３０から")
    #expect(candidate.contentKey == "3:30")
    #expect(candidate.contentValue == "３：３０")
    #expect(candidate.innerSegmentBoundary == results[0].innerSegmentBoundary)
  }

  @Test func commitContext() throws {
    let mockPredictor = MockPredictor()
    let converter = createConverter(try TestModules.mock(), MockRewriter(), mockPredictor)

    let convreq = ConversionRequestBuilder().build()
    converter.commitContext(convreq)
    #expect(mockPredictor.commitContextCount == 1)
  }

  @Test func addUserHistory() throws {
    let mockPredictor = MockPredictor()
    mockPredictor.addHistoryEntryHandler = { key, value in
      #expect(key == "key")
      #expect(value == "value")
      return true
    }
    let converter = createConverter(try TestModules.mock(), MockRewriter(), mockPredictor)

    #expect(converter.addUserHistory("key", "value"))
    #expect(mockPredictor.addHistoryEntryCount == 1)
  }

  // The C++ test uses rewriter::Rewriter and prediction::Predictor; the stub
  // rewriter / predictor are used here (the assertions are about the
  // supplemental model and the immutable converter).
  @Test func postCorrectInConversionMode() throws {
    // Test 1: PostCorrect modifies value without changing inner segment
    // boundary. "わたしのなまえ" -> "私の名前" (1 segment) is corrected to
    // "僕の名前".
    do {
      let modules = try TestModules.mock()
      modules.supplementalModel = TestSupplementalModel { _, results in
        if !results.isEmpty {
          results[0].value = "僕の名前"
          var builder = InnerSegmentBoundaryBuilder()
          builder.add(
            results[0].key.utf8.count, results[0].value.utf8.count, results[0].key.utf8.count,
            results[0].value.utf8.count)
          results[0].innerSegmentBoundary = builder.build(results[0].key, results[0].value)
        }
      }
      let converter = createConverter(modules, StubRewriter())

      let requestProto = requestWithLegacyMode(Rewriter.LegacyRewriterType.disableCollocation)
      let convreq = convReq("わたしのなまえ", request: requestProto, .conversion)

      let segments = Segments()
      #expect(converter.startConversion(convreq, segments))
      try #require(segments.conversionSegmentsSize == 1)
      #expect(segments.conversionSegment(0).candidate(0).value == "僕の名前")

      // When kDisableCollocation is not set, PostCorrect is not applied in
      // conversion mode.
      let segmentsLegacy = Segments()
      #expect(converter.startConversion(convReq("わたしのなまえ", .conversion), segmentsLegacy))
      try #require(segmentsLegacy.conversionSegmentsSize == 2)
      #expect(segmentsLegacy.conversionSegment(0).candidate(0).value == "私の")
      #expect(segmentsLegacy.conversionSegment(1).candidate(0).value == "名前")
    }

    // Test 2: PostCorrect changes inner segment boundary requiring Resize.
    // "しんだいしゃ" -> "寝台車" (1 segment) is corrected to
    // "死んだ" (3 chars, 9 bytes) + "医者" (2 chars, 6 bytes).
    do {
      let modules = try TestModules.mock()
      modules.supplementalModel = TestSupplementalModel { _, results in
        if !results.isEmpty {
          results[0].key = "しんだいしゃ"
          results[0].value = "死んだ医者"
          var builder = InnerSegmentBoundaryBuilder()
          builder.add(9, 9, 9, 9)  // しんだ (9 bytes) -> 死んだ (9 bytes)
          builder.add(9, 6, 9, 6)  // いしゃ (9 bytes) -> 医者 (6 bytes)
          results[0].innerSegmentBoundary = builder.build(results[0].key, results[0].value)
        }
      }
      let converter = createConverter(modules, StubRewriter())

      let requestProto = requestWithLegacyMode(Rewriter.LegacyRewriterType.disableCollocation)
      let convreq = convReq("しんだいしゃ", request: requestProto, .conversion)

      let segments = Segments()
      #expect(converter.startConversion(convreq, segments))
      try #require(segments.conversionSegmentsSize == 2)
      #expect(segments.conversionSegment(0).candidate(0).value == "死んだ")
      #expect(segments.conversionSegment(1).candidate(0).value == "医者")

      // When kDisableCollocation is not set, PostCorrect is not applied in
      // conversion mode.
      let segmentsLegacy = Segments()
      #expect(converter.startConversion(convReq("しんだいしゃ", .conversion), segmentsLegacy))
      try #require(segmentsLegacy.conversionSegmentsSize == 2)
      #expect(segmentsLegacy.conversionSegment(0).candidate(0).value == "新だい")
    }

    // Test 3: Single-segment conversion passes N-best candidates to
    // PostCorrect, allowing supplemental model reranking.
    do {
      let modules = try TestModules.mock()
      modules.supplementalModel = TestSupplementalModel { _, results in
        #expect(results.count > 1)
        if results.count > 1 {
          results.swapAt(0, 1)  // std::rotate(begin, begin + 1, begin + 2)
        }
      }
      let converter = createConverter(modules, StubRewriter())

      // First check default candidate order without PostCorrect.
      let segmentsDefault = Segments()
      #expect(converter.startConversion(convReq("きょう", .conversion), segmentsDefault))
      try #require(segmentsDefault.conversionSegmentsSize == 1)
      try #require(segmentsDefault.conversionSegment(0).candidatesSize > 1)
      let secondCandidateValue = segmentsDefault.conversionSegment(0).candidate(1).value

      // Now run with kDisableCollocation so PostCorrect reranks candidate 1
      // to 0.
      let requestProto = requestWithLegacyMode(Rewriter.LegacyRewriterType.disableCollocation)
      let convreq = convReq("きょう", request: requestProto, .conversion)

      let segments = Segments()
      #expect(converter.startConversion(convreq, segments))
      try #require(segments.conversionSegmentsSize == 1)
      #expect(segments.conversionSegment(0).candidate(0).value == secondCandidateValue)
    }
  }

  private func mockConverter(
    _ results: [PredictionResult], supplementalModel: (any ConverterSupplementalModel)? = nil
  ) throws -> (Converter, MockPredictor) {
    let mockPredictor = MockPredictor()
    mockPredictor.convertHandler = { _ in results }
    let modules = try TestModules.mock()
    if let supplementalModel {
      modules.supplementalModel = supplementalModel
    }
    return (createConverter(modules, MockRewriter(), mockPredictor), mockPredictor)
  }

  @Test func applyUserHistoryToConversionSingleSegmentTest() throws {
    var results = [PredictionResult](repeating: PredictionResult(), count: 2)
    results[0].key = "きょう"
    results[0].value = "本日"
    results[0].lid = 100
    results[0].rid = 200
    results[0].cost = 500
    results[0].wcost = 300
    results[0].attributes = Attribute.userHistoryPrediction

    results[1].key = "きょう"
    results[1].value = "今日"
    results[1].lid = 101
    results[1].rid = 201
    results[1].cost = 600
    results[1].wcost = 400
    results[1].attributes = Attribute.userHistoryPrediction

    let (converter, _) = try mockConverter(results)

    let convreq = convReq("きょう", request: requestWithLegacyMode(kLegacyHistoryModes), .conversion)

    let segments = Segments()
    #expect(converter.startConversion(convreq, segments))
    try #require(segments.conversionSegmentsSize == 1)
    let seg = segments.conversionSegment(0)
    #expect(seg.candidate(0).value == "本日")
    #expect(seg.candidate(0).attributes & Attribute.userHistoryPrediction != 0)
  }

  @Test func applyUserHistoryToConversionMultiSegmentTest() throws {
    var results = [PredictionResult](repeating: PredictionResult(), count: 1)
    results[0].key = "わたしのなまえ"
    results[0].value = "僕の名字"
    var builder = InnerSegmentBoundaryBuilder()
    builder.add(9, 3, 9, 3)  // わたし (9 bytes) -> 僕 (3 bytes)
    builder.add(3, 3, 3, 3)  // の (3 bytes) -> の (3 bytes)
    builder.add(9, 6, 9, 6)  // なまえ (9 bytes) -> 名字 (6 bytes)
    results[0].innerSegmentBoundary = builder.build(results[0].key, results[0].value)
    results[0].lid = 100
    results[0].rid = 200
    results[0].cost = 500
    results[0].wcost = 300

    let (converter, _) = try mockConverter(results)

    let convreq = convReq(
      "わたしのなまえ", request: requestWithLegacyMode(kLegacyHistoryModes), .conversion)

    let segments = Segments()
    #expect(converter.startConversion(convreq, segments))
    try #require(segments.conversionSegmentsSize == 3)
    #expect(segments.conversionSegment(0).candidate(0).value == "僕")
    #expect(segments.conversionSegment(1).candidate(0).value == "の")
    #expect(segments.conversionSegment(2).candidate(0).value == "名字")
  }

  @Test func applyUserHistoryToConversionFallbackWithoutBoundaryTest() throws {
    var results = [PredictionResult](repeating: PredictionResult(), count: 1)
    results[0].key = "わたしのなまえ"
    results[0].value = "僕の名字"
    results[0].attributes = Attribute.userHistoryEmptyInnerSegmentBoundary

    let (converter, _) = try mockConverter(results)

    let convreq = convReq(
      "わたしのなまえ", request: requestWithLegacyMode(kLegacyHistoryModes), .conversion)

    let segments = Segments()
    #expect(converter.startConversion(convreq, segments))
    #expect(segments.conversionSegmentsSize > 1)
    #expect(segments.conversionSegment(0).candidate(0).attributes & Attribute.userHistoryPrediction == 0)
  }

  @Test func applyUserHistoryToConversionMultiSegmentWithoutBoundaryTest() throws {
    var results = [PredictionResult](repeating: PredictionResult(), count: 1)
    results[0].key = "わたしのなまえ"
    results[0].value = "僕の名字"
    results[0].attributes =
      Attribute.userHistoryPrediction | Attribute.userHistoryEmptyInnerSegmentBoundary

    let (converter, _) = try mockConverter(results)

    var requestProto = requestWithLegacyMode(kLegacyHistoryModes)
    requestProto.decoderExperimentParams.enableMultiSegmentCandidate = true
    let convreq = convReq("わたしのなまえ", request: requestProto, .conversion)

    let segments = Segments()
    #expect(converter.startConversion(convreq, segments))
    #expect(segments.conversionSegmentsSize > 1)
    let seg0 = segments.conversionSegment(0)
    try #require(seg0.candidatesSize > 0)
    #expect(seg0.candidate(0).value == "僕の名字")
    #expect(Int(seg0.candidate(0).convertedSegmentCount) == segments.conversionSegmentsSize)
    #expect(seg0.candidate(0).attributes & Attribute.userHistoryPrediction != 0)
  }

  @Test func applyUserHistoryToConversionLegacyModeDisabledTest() throws {
    let (converter, mockPredictor) = try mockConverter([])

    let segments = Segments()
    #expect(converter.startConversion(convReq("きょう", .conversion), segments))
    #expect(mockPredictor.convertCount == 0)
  }

  @Test func applyUserHistoryToConversionPartialCommitMultiSegmentTest() throws {
    var results = [PredictionResult](repeating: PredictionResult(), count: 1)
    results[0].key = "わたしのなまえはなかのです"
    results[0].value = "僕の名字中野です"
    results[0].attributes = Attribute.userHistoryPrediction
    var builder = InnerSegmentBoundaryBuilder()
    builder.add(9, 3, 9, 3)  // わたし (9 bytes) -> 僕 (3 bytes)
    builder.add(15, 9, 15, 9)  // のなまえは (15 bytes) -> の名字 (9 bytes)
    builder.add(15, 12, 15, 12)  // なかのです (15 bytes) -> 中野です (12 bytes)
    results[0].innerSegmentBoundary = builder.build(results[0].key, results[0].value)
    results[0].lid = 100
    results[0].rid = 200
    results[0].cost = 500
    results[0].wcost = 300

    let (converter, _) = try mockConverter(results)

    var requestProto = requestWithLegacyMode(7)
    requestProto.decoderExperimentParams.enableMultiSegmentCandidate = true
    let convreq = convReq("わたしのなまえはなかのです", request: requestProto, .conversion)

    let segments = Segments()
    try #require(converter.startConversion(convreq, segments))
    try #require(segments.conversionSegmentsSize == 3)

    let multiCandIdx = getCandidateIndexByValue("僕の名字", segments.conversionSegment(0))
    try #require(multiCandIdx != -1)
    #expect(segments.conversionSegment(0).candidate(multiCandIdx).convertedSegmentCount == 2)

    // Partially commit the multi-segment candidate on segment 0 (mobile tap).
    try #require(converter.commitSegments(segments, [multiCandIdx]))
    #expect(segments.historySegmentsSize == 1)
    #expect(segments.historySegment(0).key == "わたしのなまえは")
    #expect(segments.historySegment(0).candidate(0).value == "僕の名字")
    #expect(segments.historySegment(0).candidate(0).convertedSegmentCount == 1)

    // Covered segment 1 ("なまえは") was erased; only segment 2 ("なかのです")
    // remains.
    try #require(segments.conversionSegmentsSize == 1)
    #expect(segments.conversionSegment(0).key == "なかのです")

    // FinishConversion commits the remaining conversion segment
    // ("なかのです").
    segments.mutableConversionSegment(0).setSegmentType(.fixedValue)
    converter.finishConversion(convreq, segments)
    #expect(segments.conversionSegmentsSize == 0)
    try #require(segments.historySegmentsSize == 2)
    #expect(segments.historySegment(0).candidate(0).value == "僕の名字")
    #expect(segments.historySegment(1).key == "なかのです")
  }

  @Test func applyPredictionToConversionMergedResultsTest() throws {
    // UserHistory returns "本日" and "きょう".
    var historyResults = [PredictionResult](repeating: PredictionResult(), count: 2)
    historyResults[0].key = "きょう"
    historyResults[0].value = "本日"
    historyResults[0].lid = 100
    historyResults[0].rid = 200
    historyResults[0].cost = 500
    historyResults[0].wcost = 300
    historyResults[0].attributes = Attribute.userHistoryPrediction
    historyResults[1].key = "きょう"
    historyResults[1].value = "きょう"
    historyResults[1].attributes = Attribute.userHistoryPrediction

    // PostCorrect returns "本日" (duplicate of history[0]) and "今宵".
    let supplementalModel = TestSupplementalModel { _, results in
      results.removeAll()
      var r1 = PredictionResult()
      r1.key = "きょう"
      r1.value = "本日"  // Duplicate of history_results[0]
      results.append(r1)

      var r2 = PredictionResult()
      r2.key = "きょう"
      r2.value = "今宵"
      results.append(r2)
    }

    let (converter, _) = try mockConverter(historyResults, supplementalModel: supplementalModel)

    let requestProto = requestWithLegacyMode(
      kLegacyHistoryModes | Rewriter.LegacyRewriterType.disableCollocation)
    let convreq = convReq("きょう", request: requestProto, .conversion)

    let segments = Segments()
    #expect(converter.startConversion(convreq, segments))
    try #require(segments.conversionSegmentsSize == 1)
    let seg = segments.conversionSegment(0)
    try #require(seg.candidatesSize >= 3)

    // Position 0: "本日" (User history prediction has higher priority)
    #expect(seg.candidate(0).value == "本日")
    #expect(seg.candidate(0).attributes & Attribute.userHistoryPrediction != 0)
    // Position 1: "きょう" (2nd user history candidate)
    #expect(seg.candidate(1).value == "きょう")
    // Position 2: "今宵" (PostCorrection result; duplicate "本日" was skipped)
    #expect(seg.candidate(2).value == "今宵")

    // Verify "本日" only appears once among top 3 candidates.
    var countHonjitsu = 0
    for i in 0..<min(seg.candidatesSize, 3) where seg.candidate(i).value == "本日" {
      countHonjitsu += 1
    }
    #expect(countHonjitsu == 1)
  }

  @Test func applyPredictionToConversionWeakHistoryDemotedTest() throws {
    var historyResults = [PredictionResult](repeating: PredictionResult(), count: 1)
    historyResults[0].key = "きょう"
    historyResults[0].value = "本日"
    historyResults[0].attributes = Attribute.weakUserHistoryPrediction

    let (converter, _) = try mockConverter(historyResults)

    let convreq = convReq("きょう", request: requestWithLegacyMode(kLegacyHistoryModes), .conversion)

    let segments = Segments()
    #expect(converter.startConversion(convreq, segments))
    try #require(segments.conversionSegmentsSize == 1)
    let seg = segments.conversionSegment(0)
    try #require(seg.candidatesSize >= 2)
    // Weak history candidate should not override default Viterbi result at
    // pos 0.
    #expect(seg.candidate(0).value != "本日")
    // Weak history candidate is demoted to subsequent candidate positions.
    #expect(seg.candidate(1).value == "本日")
    #expect(seg.candidate(1).attributes & Attribute.weakUserHistoryPrediction != 0)
  }

  private func koyoiConverter() throws -> Converter {
    let modules = try TestModules.mock()
    modules.supplementalModel = TestSupplementalModel { _, results in
      if !results.isEmpty {
        results[0].value = "今宵"
      }
    }
    return createConverter(modules, StubRewriter())
  }

  @Test func applyPredictionToConversionHandwritingModePostCorrectionSkippedTest() throws {
    let converter = try koyoiConverter()

    var requestProto = requestWithLegacyMode(Rewriter.LegacyRewriterType.disableCollocation)
    requestProto.isHandwriting = true
    let convreq = convReq("きょう", request: requestProto, .conversion)

    let segments = Segments()
    #expect(converter.startConversion(convreq, segments))
    try #require(segments.conversionSegmentsSize == 1)
    // In handwriting mode, PostCorrection should be skipped.
    #expect(segments.conversionSegment(0).candidate(0).value != "今宵")
  }

  @Test func applyPredictionToConversionUsedInPredictorRealtimeConversionSkippedTest() throws {
    let converter = try koyoiConverter()

    let requestProto = requestWithLegacyMode(Rewriter.LegacyRewriterType.disableCollocation)
    var composer = Composer()
    composer.setPreeditTextForTestOnly("きょう")
    var options = ConversionOptions()
    options.requestType = .conversion
    options.usedInPredictorRealtimeConversion = true
    let convreq = ConversionRequestBuilder()
      .setComposer(composer)
      .setRequest(requestProto)
      .setOptions(options)
      .build()

    let segments = Segments()
    #expect(converter.startConversion(convreq, segments))
    try #require(segments.conversionSegmentsSize == 1)
    // When used_in_predictor_realtime_conversion is true,
    // MaybeApplyPredictionToConversion should be skipped.
    #expect(segments.conversionSegment(0).candidate(0).value != "今宵")
  }

  @Test func applyPredictionToConversionHistoryContextTest() throws {
    let modules = try TestModules.mock()
    modules.supplementalModel = TestSupplementalModel { request, results in
      #expect(request.converterHistoryValue() == "私は")
      if !results.isEmpty {
        results[0].value = "本日"
      }
    }
    let converter = createConverter(modules, StubRewriter())

    let requestProto = requestWithLegacyMode(Rewriter.LegacyRewriterType.disableCollocation)
    let convreq = convReq("きょう", request: requestProto, .conversion)

    let segments = Segments()
    let historySeg = segments.addSegment()
    historySeg.setSegmentType(.history)
    historySeg.setKey("わたしは")
    let cand = historySeg.addCandidate()
    cand.key = "わたしは"
    cand.value = "私は"

    #expect(converter.startConversion(convreq, segments))
    try #require(segments.conversionSegmentsSize == 1)
    #expect(segments.conversionSegment(0).candidate(0).value == "本日")
  }

  @Test func finishConversionFullSentence() throws {
    let converter = try createStubbedConverter()

    let segments = Segments()
    segments.setMaxHistorySegmentsSize(3)
    let seg0 = segments.addSegment()
    seg0.setKey("わたしは")
    let cand0 = seg0.addCandidate()
    cand0.value = "私は"
    cand0.key = "わたしは"
    cand0.convertedSegmentCount = 2

    let seg1 = segments.addSegment()
    seg1.setKey("は")
    let cand1 = seg1.addCandidate()
    cand1.value = "は"
    cand1.key = "は"

    #expect(segments.conversionSegmentsSize == 2)

    let request = ConversionRequestBuilder().setRequestType(.conversion).build()

    converter.finishConversion(request, segments)

    #expect(segments.conversionSegmentsSize == 0)
    try #require(segments.historySegmentsSize == 1)
    #expect(segments.historySegment(0).key == "わたしは")
    #expect(segments.historySegment(0).candidate(0).value == "私は")
  }

  @Test func candidateConvertedSegmentCountZeroSafety() {
    // TEST(CandidateTest, ConvertedSegmentCountZeroSafety)
    let cand = Candidate()
    #expect(cand.convertedSegmentCount == 1)
    #expect(cand.effectiveConvertedSegmentCount == 1)

    cand.convertedSegmentCount = 0
    #expect(cand.effectiveConvertedSegmentCount == 1)

    cand.convertedSegmentCount = 3
    #expect(cand.effectiveConvertedSegmentCount == 3)

    cand.clear()
    #expect(cand.convertedSegmentCount == 1)
    #expect(cand.effectiveConvertedSegmentCount == 1)
  }

  private func makeKokodeSegments(withNuguAlternative: Bool, contentKeys: Bool = true) -> Segments {
    let segments = Segments()
    let s0 = segments.addSegment()
    s0.setKey("ここで")
    let c0 = s0.addCandidate()
    c0.key = "ここで"
    c0.value = "ここで"
    if contentKeys {
      c0.contentKey = "ここで"
      c0.contentValue = "ここで"
    }

    let s1 = segments.addSegment()
    s1.setKey("はきものを")
    let c1 = s1.addCandidate()
    c1.key = "はきものを"
    c1.value = "履物を"
    if contentKeys {
      c1.contentKey = "はきもの"
      c1.contentValue = "履物"
    }

    let s2 = segments.addSegment()
    s2.setKey("ぬぐ")
    if withNuguAlternative {
      let c2Other = s2.addCandidate()
      c2Other.key = "ぬぐ"
      c2Other.value = "塗ぐ"
      c2Other.contentKey = "ぬぐ"
      c2Other.contentValue = "塗ぐ"
    }
    let c2 = s2.addCandidate()
    c2.key = "ぬぐ"
    c2.value = "脱ぐ"
    if contentKeys {
      c2.contentKey = "ぬぐ"
      c2.contentValue = "脱ぐ"
    }
    return segments
  }

  private func makeResult(_ key: String, _ value: String, _ boundary: [(Int, Int, Int, Int)]? = nil)
    -> PredictionResult
  {
    var r = PredictionResult()
    r.key = key
    r.value = value
    if let boundary {
      r.innerSegmentBoundary = buildInnerSegmentBoundary(boundary, key, value)
    }
    return r
  }

  private func multiSegmentRequest() -> ConversionRequest {
    var requestProto = Genmai_Commands_Request()
    requestProto.decoderExperimentParams.enableMultiSegmentCandidate = true
    return ConversionRequestBuilder().setRequest(requestProto).build()
  }

  @Test func populatePredictionResultsToSegmentsMultiSegment() throws {
    let converter = try createStubbedConverter()

    let defaultResult = makeResult(
      "ここではきものをぬぐ", "ここで履物を脱ぐ", [(9, 9, 9, 9), (15, 9, 12, 6), (6, 6, 6, 6)])
    let predResult = makeResult(
      "ここではきものをぬぐ", "ここでは着物を脱ぐ", [(12, 12, 9, 9), (12, 9, 9, 6), (6, 6, 6, 6)])
    let results = [predResult]

    do {
      // enable_multi_segment_candidate = false (legacy behavior):
      // Segments are resized to match prediction result boundaries.
      let segments = makeKokodeSegments(withNuguAlternative: false)

      let request = ConversionRequestBuilder().build()
      converter.populatePredictionResultsToSegments(request, defaultResult, results, segments)

      // Legacy behavior resizes segments according to prediction boundaries.
      try #require(segments.conversionSegmentsSize == 3)
      #expect(segments.conversionSegment(0).key == "ここでは")
      #expect(segments.conversionSegment(0).candidate(0).value == "ここでは")
      #expect(
        segments.conversionSegment(0).candidate(0).innerSegmentBoundary
          == buildInnerSegmentBoundary([(12, 12, 9, 9)], "ここでは", "ここでは"))
      #expect(segments.conversionSegment(1).key == "きものを")
      #expect(segments.conversionSegment(1).candidate(0).value == "着物を")
      #expect(
        segments.conversionSegment(1).candidate(0).innerSegmentBoundary
          == buildInnerSegmentBoundary([(12, 9, 9, 6)], "きものを", "着物を"))
      #expect(segments.conversionSegment(2).key == "ぬぐ")
      #expect(segments.conversionSegment(2).candidate(0).value == "脱ぐ")
      #expect(
        segments.conversionSegment(2).candidate(0).innerSegmentBoundary
          == buildInnerSegmentBoundary([(6, 6, 6, 6)], "ぬぐ", "脱ぐ"))
    }

    do {
      // enable_multi_segment_candidate = true:
      // Segments are NOT resized. "ここでは着物を" is added as a multi-segment
      // candidate with converted_segment_count = 2 in segment 0.
      // "脱ぐ" is applied to segment 2 with converted_segment_count = 1.
      let segments = makeKokodeSegments(withNuguAlternative: true)

      converter.populatePredictionResultsToSegments(
        multiSegmentRequest(), defaultResult, results, segments)

      // Segments structure is preserved (3 segments).
      try #require(segments.conversionSegmentsSize == 3)
      #expect(segments.conversionSegment(0).key == "ここで")
      #expect(segments.conversionSegment(1).key == "はきものを")
      #expect(segments.conversionSegment(2).key == "ぬぐ")

      // Segment 0 contains multi-segment candidate "ここでは着物を" with
      // converted_segment_count = 2.
      let seg0 = segments.conversionSegment(0)
      try #require(seg0.candidatesSize > 0)
      #expect(seg0.candidate(0).value == "ここでは着物を")
      #expect(seg0.candidate(0).key == "ここではきものを")
      #expect(seg0.candidate(0).convertedSegmentCount == 2)

      // Segment 2 top candidate is moved to "脱ぐ".
      let seg2 = segments.conversionSegment(2)
      try #require(seg2.candidatesSize > 0)
      #expect(seg2.candidate(0).value == "脱ぐ")
      #expect(seg2.candidate(0).convertedSegmentCount == 1)
    }

    do {
      // Verify that multiple prediction results (up to 5) are inserted in
      // order.
      let predResult2 = makeResult(
        "ここではきものをぬぐ", "此処では着物を脱ぐ", [(12, 12, 9, 9), (12, 9, 9, 6), (6, 6, 6, 6)])
      let multiResults = [predResult, predResult2]

      let segments = makeKokodeSegments(withNuguAlternative: true)

      converter.populatePredictionResultsToSegments(
        multiSegmentRequest(), defaultResult, multiResults, segments)

      let seg0 = segments.conversionSegment(0)
      try #require(seg0.candidatesSize >= 2)
      #expect(seg0.candidate(0).value == "ここでは着物を")
      #expect(seg0.candidate(0).convertedSegmentCount == 2)
      #expect(seg0.candidate(1).value == "此処では着物を")
      #expect(seg0.candidate(1).convertedSegmentCount == 2)

      // Verify that "脱ぐ" in segment 2 was promoted to pos 0 by result 0 and
      // was NOT demoted to pos 1 by result 1.
      let seg2 = segments.conversionSegment(2)
      try #require(seg2.candidatesSize >= 2)
      #expect(seg2.candidate(0).value == "脱ぐ")
      #expect(seg2.candidate(1).value == "塗ぐ")
    }
  }

  @Test func populatePredictionResultsToSegmentsEmptyResults() throws {
    let converter = try createStubbedConverter()

    let defaultResult = makeResult("きょう", "今日")

    let segments = Segments()
    let s0 = segments.addSegment()
    s0.setKey("きょう")
    let c0 = s0.addCandidate()
    c0.key = "きょう"
    c0.value = "今日"

    converter.populatePredictionResultsToSegments(
      ConversionRequestBuilder().build(), defaultResult, [], segments)

    try #require(segments.conversionSegmentsSize == 1)
    #expect(segments.conversionSegment(0).candidatesSize == 1)
    #expect(segments.conversionSegment(0).candidate(0).value == "今日")
  }

  @Test func populatePredictionResultsToSegmentsResizeFailure() throws {
    let converter = try createStubbedConverter()

    let defaultResult = makeResult("とうきょう", "東京")
    let invalidPredResult = makeResult("", "別表記")

    let segments = Segments()
    let s0 = segments.addSegment()
    s0.setKey("とうきょう")
    let c0 = s0.addCandidate()
    c0.key = "とうきょう"
    c0.value = "東京"

    converter.populatePredictionResultsToSegments(
      ConversionRequestBuilder().build(), defaultResult, [invalidPredResult], segments)

    try #require(segments.conversionSegmentsSize == 1)
    #expect(segments.conversionSegment(0).candidatesSize == 1)
    #expect(segments.conversionSegment(0).candidate(0).value == "東京")
  }

  @Test func populatePredictionResultsToSegmentsLegacyMultiToSingleSegment() throws {
    let converter = try createStubbedConverter()

    let defaultResult = makeResult(
      "ここではきものをぬぐ", "ここで履物を脱ぐ", [(9, 9, 9, 9), (15, 9, 12, 6), (6, 6, 6, 6)])

    // Prediction result that resizes multi-segment default (3 segments) into
    // a single segment.
    let predResult0 = makeResult("ここではきものをぬぐ", "ここでは着物を脱ぐ", [(30, 30, 27, 27)])
    let predResult1 = makeResult("ここではきものをぬぐ", "此処では着物を脱ぐ", [(30, 30, 27, 27)])
    let results = [predResult0, predResult1]

    let segments = makeKokodeSegments(withNuguAlternative: false, contentKeys: false)

    // enable_multi_segment = false.
    // Because is_default_multi_segment was true, is_single_segment is false
    // even after resizing to 1 segment, so only pred_result0 is applied (not
    // pred_result1).
    converter.populatePredictionResultsToSegments(
      ConversionRequestBuilder().build(), defaultResult, results, segments)

    try #require(segments.conversionSegmentsSize == 1)
    #expect(segments.conversionSegment(0).key == "ここではきものをぬぐ")
    #expect(segments.conversionSegment(0).candidate(0).value == "ここでは着物を脱ぐ")
    #expect(!findCandidateByValue("此処では着物を脱ぐ", segments.conversionSegment(0)))
  }

  @Test func populatePredictionResultsToSegmentsSingleSegmentWithEmptyResult() throws {
    let converter = try createStubbedConverter()

    let defaultResult = makeResult("きょう", "今日", [(9, 9, 6, 6)])
    let predResult0 = makeResult("きょう", "今日", [(9, 9, 6, 6)])
    let emptyPredResult = makeResult("", "")
    let predResult2 = makeResult("きょう", "教", [(9, 9, 3, 3)])
    let results = [predResult0, emptyPredResult, predResult2]

    for request in [ConversionRequestBuilder().build(), multiSegmentRequest()] {
      let segments = Segments()
      let s0 = segments.addSegment()
      s0.setKey("きょう")
      let c0 = s0.addCandidate()
      c0.key = "きょう"
      c0.value = "今日"

      converter.populatePredictionResultsToSegments(request, defaultResult, results, segments)

      try #require(segments.conversionSegmentsSize == 1)
      #expect(findCandidateByValue("教", segments.conversionSegment(0)))
    }
  }
}
