// Port of the fixture of mozc/src/engine/engine_converter_test.cc (3.35.6354).
//
// `EngineConverterTest` (the C++ fixture with `friend` access) becomes the
// class `EngineConverterTestFixture`; each Swift test creates its own
// instance. gMock expectations are expressed with `MockConverter` handlers
// (Tests/GenmaiCoreTests/Converter/ConverterMock.swift) and call counters.
//
// NOTE: the C++ fixture shares `request_` / `config_` with the converter
// through shared_ptr, so mutating them after constructing the converter is
// visible to it. In Swift they are values: tests must call
// `converter.setRequest(f.request)` / `setConfig` when the C++ test mutates
// them after construction.

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

let kCharsAiueo = "あいうえお"
let kCharsMo = "も"
let kCharsMozuku = "もずく"
let kCharsMozukusu = "もずくす"
let kCharsMomonga = "ももんが"

func addSegmentWithSingleCandidate(_ segments: Segments, _ key: String, _ value: String) {
  let seg = segments.addSegment()
  seg.setKey(key)
  let cand = seg.addCandidate()
  cand.key = key
  cand.contentKey = cand.key
  cand.value = value
  cand.contentValue = cand.value
}

/// Simple call counter for gMock `Times(n)` / `WillOnce` expectations.
final class CallCounter {
  var count = 0
  func increment() { count += 1 }
}

final class EngineConverterTestFixture {
  var config: Genmai_Config_Config
  var request: Genmai_Commands_Request
  let table: Table
  var composer: Composer

  init() {
    config = Genmai_Config_Config()
    config.useCascadingWindow = true
    request = Genmai_Commands_Request()

    table = Table()
    table.initializeWithRequestAndConfig(request, config)
    composer = Composer(table, request, config)
  }

  static func getSegments(_ converter: EngineConverter, _ dest: Segments) {
    dest.assign(from: converter.segments)
  }

  static func getSegments(_ converter: EngineConverter) -> Segments {
    converter.segments
  }

  static func setSegments(_ src: Segments, _ converter: EngineConverter) {
    converter.segments.assign(from: src)
  }

  static func getResult(_ converter: EngineConverter) -> Genmai_Commands_Result {
    converter.result
  }

  static func getCandidateList(_ converter: EngineConverter) -> CandidateList {
    converter.candidateList
  }

  static func getState(_ converter: EngineConverter) -> EngineConverterStates {
    converter.state
  }

  static func setState(_ state: EngineConverterStates, _ converter: EngineConverter) {
    converter.state = state
  }

  static func getSegmentIndex(_ converter: EngineConverter) -> Int {
    converter.segmentIndex
  }

  static func isCandidateListVisible(_ converter: EngineConverter) -> Bool {
    converter.candidateListVisible
  }

  static func getRequest(_ converter: EngineConverter) -> Genmai_Commands_Request {
    converter.request
  }

  static func getPreedit(_ converter: EngineConverter, _ index: Int, _ size: Int) -> String {
    converter.getPreedit(index, size)
  }

  static func getConversion(_ converter: EngineConverter, _ index: Int, _ size: Int) -> String {
    converter.getConversion(index, size)
  }

  static func getSegmentSpan(_ converter: EngineConverter, _ segmentIndex: Int) -> Int {
    converter.getSegmentSpan(segmentIndex)
  }

  static func isFullSentenceCandidateSelected(_ converter: EngineConverter) -> Bool {
    converter.isFullSentenceCandidateSelected()
  }

  static func appendCandidateList(_ requestType: RequestType, _ converter: EngineConverter) {
    var unusedOptions = ConversionRequest.Options()
    converter.setRequestType(requestType, &unusedOptions)
    converter.appendCandidateList()
  }

  /// set result for "あいうえお"
  static func setAiueo(_ segments: Segments) {
    segments.clear()
    let segment = segments.addSegment()
    segment.setKey("あいうえお")
    var candidate = segment.addCandidate()
    candidate.key = "あいうえお"
    candidate.contentKey = candidate.key
    candidate.value = candidate.key
    candidate.contentValue = candidate.value
    candidate = segment.addCandidate()
    candidate.key = "あいうえお"
    candidate.contentKey = candidate.key
    candidate.value = "アイウエオ"
    candidate.contentValue = candidate.value
  }

  /// set result for "かまぼこのいんぼう"
  static func setKamaboko(_ segments: Segments) {
    segments.clear()
    var segment = segments.addSegment()

    segment.setKey("かまぼこの")
    var candidate = segment.addCandidate()
    candidate.key = "かまぼこの"
    candidate.contentKey = candidate.key
    candidate.value = "かまぼこの"
    candidate.contentValue = candidate.value
    candidate = segment.addCandidate()
    candidate.key = "かまぼこの"
    candidate.contentKey = candidate.key
    candidate.value = "カマボコの"
    candidate.contentValue = candidate.value
    segment = segments.addSegment()
    segment.setKey("いんぼう")
    candidate = segment.addCandidate()
    candidate.key = "いんぼう"
    candidate.contentKey = candidate.key
    candidate.value = "陰謀"
    candidate.contentValue = candidate.value
    candidate = segment.addCandidate()
    candidate.key = "いんぼう"
    candidate.contentKey = candidate.key
    candidate.value = "印房"
    candidate.contentValue = candidate.value

    // Set dummy T13Ns
    segment.metaCandidates = (0..<TransliterationType.numT13nTypes).map { _ in
      let c = Candidate()
      c.value = segment.key
      c.contentValue = segment.key
      c.contentKey = segment.key
      return c
    }
  }

  /// set T13N candidates to segments using composer
  static func fillT13Ns(_ segments: Segments, _ composer: Composer) {
    var compositionPos = 0
    for segment in segments.conversionSegments {
      let compositionLen = Util.charsLen(segment.key)
      var t13ns: [String] = []
      composer.getSubTransliterations(compositionPos, compositionLen, &t13ns)
      segment.metaCandidates = (0..<TransliterationType.numT13nTypes).map { j in
        let c = Candidate()
        c.value = t13ns[j]
        c.contentValue = t13ns[j]
        c.key = segment.key
        c.contentKey = segment.key
        return c
      }
      compositionPos += compositionLen
    }
  }

  /// Sets the result for "like"
  func setLike(_ segments: Segments) {
    composer.insertCharacterKeyAndPreedit("li", "ぃ")
    composer.insertCharacterKeyAndPreedit("ke", "け")

    segments.clear()
    var segment = segments.addSegment()

    segment.setKey("ぃ")
    var candidate = segment.addCandidate()
    candidate.value = "ぃ"

    candidate = segment.addCandidate()
    candidate.value = "ィ"

    segment = segments.addSegment()
    segment.setKey("け")
    candidate = segment.addCandidate()
    candidate.value = "家"
    candidate = segment.addCandidate()
    candidate.value = "け"

    Self.fillT13Ns(segments, composer)
  }

  static func getSegmentsTest() -> Segments {
    let segments = Segments()
    let segment = segments.addSegment()
    segment.setKey("てすと")
    let candidate = segment.addCandidate()
    candidate.value = "テスト"
    candidate.key = "てすと"
    candidate.contentKey = "てすと"
    return segments
  }

  static func insertASCIISequence(_ text: String, _ composer: inout Composer) {
    for b in text.utf8 {
      var key = Genmai_Commands_KeyEvent()
      key.keyCode = UInt32(b)
      composer.insertCharacterKeyEvent(key)
    }
  }

  static func expectSameEngineConverter(
    _ lhs: EngineConverter, _ rhs: EngineConverter,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(lhs.isActive() == rhs.isActive(), sourceLocation: sourceLocation)
    #expect(
      isCandidateListVisible(lhs) == isCandidateListVisible(rhs), sourceLocation: sourceLocation)
    #expect(getSegmentIndex(lhs) == getSegmentIndex(rhs), sourceLocation: sourceLocation)

    #expect(
      lhs.conversionPreferences.useHistory == rhs.conversionPreferences.useHistory,
      sourceLocation: sourceLocation)
    #expect(
      isCandidateListVisible(lhs) == isCandidateListVisible(rhs), sourceLocation: sourceLocation)

    let segmentsLhs = Segments()
    let segmentsRhs = Segments()
    getSegments(lhs, segmentsLhs)
    getSegments(rhs, segmentsRhs)
    #expect(segmentsLhs.segmentsSize == segmentsRhs.segmentsSize, sourceLocation: sourceLocation)
    for i in 0..<min(segmentsLhs.segmentsSize, segmentsRhs.segmentsSize) {
      let segmentLhs = segmentsLhs.segment(i)
      let segmentRhs = segmentsRhs.segment(i)
      #expect(segmentLhs.key == segmentRhs.key, " i=\(i)", sourceLocation: sourceLocation)
      #expect(
        segmentLhs.segmentType == segmentRhs.segmentType, " i=\(i)", sourceLocation: sourceLocation)
      #expect(
        segmentLhs.candidatesSize == segmentRhs.candidatesSize, sourceLocation: sourceLocation)
    }

    let candidateListLhs = getCandidateList(lhs)
    let candidateListRhs = getCandidateList(rhs)
    #expect(candidateListLhs.name == candidateListRhs.name, sourceLocation: sourceLocation)
    #expect(candidateListLhs.pageSize == candidateListRhs.pageSize, sourceLocation: sourceLocation)
    #expect(candidateListLhs.size == candidateListRhs.size, sourceLocation: sourceLocation)
    #expect(
      candidateListLhs.lastIndex == candidateListRhs.lastIndex, sourceLocation: sourceLocation)
    #expect(
      candidateListLhs.focusedId == candidateListRhs.focusedId, sourceLocation: sourceLocation)
    #expect(
      candidateListLhs.focusedIndex == candidateListRhs.focusedIndex,
      sourceLocation: sourceLocation)
    #expect(candidateListLhs.focused == candidateListRhs.focused, sourceLocation: sourceLocation)

    for i in 0..<min(candidateListLhs.size, candidateListRhs.size) {
      let candidateLhs = candidateListLhs.candidate(i)
      let candidateRhs = candidateListRhs.candidate(i)
      #expect(candidateLhs.id == candidateRhs.id, sourceLocation: sourceLocation)
      #expect(candidateLhs.attributes == candidateRhs.attributes, sourceLocation: sourceLocation)
      #expect(
        candidateLhs.hasSubcandidateList() == candidateRhs.hasSubcandidateList(),
        sourceLocation: sourceLocation)
      if candidateLhs.hasSubcandidateList() && candidateRhs.hasSubcandidateList() {
        #expect(
          candidateLhs.subcandidateList.size == candidateRhs.subcandidateList.size,
          sourceLocation: sourceLocation)
      }
    }

    #expect(getResult(lhs) == getResult(rhs), sourceLocation: sourceLocation)
    #expect(getRequest(lhs) == getRequest(rhs), sourceLocation: sourceLocation)
  }

  /// EXPECT_SELECTED_CANDIDATE_INDICES_EQ
  static func expectSelectedCandidateIndices(
    _ converter: EngineConverter, _ expected: [Int],
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(converter.selectedCandidateIndices == expected, sourceLocation: sourceLocation)
  }

  static func setCommandCandidate(
    _ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int, _ command: Candidate.Command
  ) {
    segments.mutableConversionSegment(segmentIndex).mutableCandidate(candidateIndex).attributes |=
      Attribute.commandCandidate
    segments.mutableConversionSegment(segmentIndex).mutableCandidate(candidateIndex).command =
      command
  }
}
