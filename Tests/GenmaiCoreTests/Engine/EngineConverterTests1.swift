// Port of mozc/src/engine/engine_converter_test.cc (3.35.6354), part 1.
//
// TEST_F(EngineConverterTest, Convert) .. TEST_F(EngineConverterTest,
// CommitSuggestionById).
//
// Notes:
// - `Mock::VerifyAndClearExpectations(&mock_converter)` in the C++ test is
//   passed the address of the shared_ptr (not the mock), so it verifies and
//   clears nothing; earlier expectations stay active. The Swift handlers
//   reproduce that by simply staying installed.
// - gMock expectations with argument matchers are handlers that only perform
//   the action when the arguments match (otherwise the NiceMock default:
//   false / no-op), and record the number of matched calls.

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private typealias F = EngineConverterTestFixture

/// `DoAll(SetArgPointee<1>(segments), Return(true))` for StartPrediction.
private func setStartPrediction(
  _ mock: MockConverter, _ segments: Segments, _ result: Bool, _ counter: CallCounter? = nil
) {
  mock.startPredictionHandler = { _, out in
    counter?.increment()
    out.assign(from: segments)
    return result
  }
}

struct EngineConverterTests1 {
  @Test func convert() throws {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    do {
      let segments = Segments()
      F.setAiueo(segments)
      f.composer.insertCharacterPreedit("あいうえお")
      F.fillT13Ns(segments, f.composer)
      mockConverter.setStartConversion(segments, true)
    }

    var expectedIndices: [Int] = []
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    f.composer.insertCharacterPreedit(kChars_Aiueo)
    #expect(converter.convert(f.composer))
    try #require(converter.isActive())
    expectedIndices.append(0)
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    var output = Genmai_Commands_Output()
    converter.fillOutput(f.composer, &output)
    #expect(!output.hasResult)
    #expect(output.hasPreedit)
    #expect(!output.hasCandidateWindow)

    let conversion = output.preedit
    #expect(conversion.segment.count == 1)
    #expect(conversion.segment[0].annotation == .highlight)
    #expect(conversion.segment[0].value == kChars_Aiueo)
    #expect(conversion.segment[0].key == kChars_Aiueo)

    // Converter should be active before submission
    #expect(converter.isActive())
    #expect(!F.isCandidateListVisible(converter))

    converter.commit(f.composer, Genmai_Commands_Context())
    f.composer.reset()
    output = Genmai_Commands_Output()
    converter.fillOutput(f.composer, &output)
    #expect(output.hasResult)
    #expect(!output.hasPreedit)
    #expect(!output.hasCandidateWindow)
    expectedIndices.removeAll()
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    let result = output.result
    #expect(result.value == kChars_Aiueo)
    #expect(result.key == kChars_Aiueo)

    // Converter should be inactive after submission
    #expect(!converter.isActive())
    #expect(!F.isCandidateListVisible(converter))
  }

  @Test func convertWithSpellingCorrection() throws {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    do {
      let segments = Segments()
      F.setAiueo(segments)
      f.composer.insertCharacterPreedit("あいうえお")
      F.fillT13Ns(segments, f.composer)
      segments.mutableConversionSegment(0).mutableCandidate(0).attributes |=
        Attribute.spellingCorrection
      mockConverter.setStartConversion(segments, true)
    }

    f.composer.insertCharacterPreedit(kChars_Aiueo)
    #expect(converter.convert(f.composer))
    try #require(converter.isActive())
    #expect(F.isCandidateListVisible(converter))
  }

  @Test func convertWithA11yTalkbackEnabled() throws {
    let f = F()
    f.request.isA11YTalkbackEnabled = true
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    do {
      let segments = Segments()
      F.setAiueo(segments)
      f.composer.insertCharacterPreedit("あいうえお")
      F.fillT13Ns(segments, f.composer)
      mockConverter.setStartConversion(segments, true)
    }

    f.composer.insertCharacterPreedit(kChars_Aiueo)
    #expect(converter.convert(f.composer))
    try #require(converter.isActive())
    #expect(F.isCandidateListVisible(converter))
  }

  @Test func convertToTransliteration() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    do {
      let segments = Segments()
      F.setAiueo(segments)
      f.composer.insertCharacterKeyAndPreedit("aiueo", kChars_Aiueo)
      F.fillT13Ns(segments, f.composer)
      mockConverter.setStartConversion(segments, true)
    }

    #expect(converter.convertToTransliteration(f.composer, .halfAscii))
    let expectedIndices = [0]
    do {  // Check the conversion #1
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment.count == 1)
      #expect(conversion.segment.first?.value == "aiueo")
      #expect(!F.isCandidateListVisible(converter))
      F.expectSelectedCandidateIndices(converter, expectedIndices)
    }

    #expect(converter.convertToTransliteration(f.composer, .halfAscii))
    do {  // Check the conversion #2
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment.count == 1)
      #expect(conversion.segment.first?.value == "AIUEO")
      #expect(!F.isCandidateListVisible(converter))
      F.expectSelectedCandidateIndices(converter, expectedIndices)
    }

    #expect(converter.convertToTransliteration(f.composer, .fullAscii))
    do {  // Check the conversion #3
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment.count == 1)
      #expect(conversion.segment.first?.value == "ＡＩＵＥＯ")
      #expect(!F.isCandidateListVisible(converter))
      F.expectSelectedCandidateIndices(converter, expectedIndices)
    }

    converter.commit(f.composer, Genmai_Commands_Context())
  }

  @Test func convertToTransliterationWithMultipleSegments() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    do {
      let segments = Segments()
      f.setLike(segments)
      mockConverter.setStartConversion(segments, true)
    }

    // Convert
    #expect(converter.convert(f.composer))
    let expectedIndices = [0, 0]
    do {  // Check the conversion #1
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment.count == 2)
      if conversion.segment.count == 2 {
        #expect(conversion.segment[0].value == "ぃ")
        #expect(conversion.segment[1].value == "家")
      }
      #expect(!F.isCandidateListVisible(converter))
      F.expectSelectedCandidateIndices(converter, expectedIndices)
    }

    // Convert to half-width alphanumeric.
    #expect(converter.convertToTransliteration(f.composer, .halfAscii))
    do {  // Check the conversion #2
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment.count == 2)
      #expect(conversion.segment.first?.value == "li")
      #expect(!F.isCandidateListVisible(converter))
      F.expectSelectedCandidateIndices(converter, expectedIndices)
    }
  }

  @Test func convertToTransliterationWithoutCascadigWindow() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    do {
      let segments = Segments()
      do {
        let segment = segments.addSegment()
        segment.setKey("dvd")
        var candidate = segment.addCandidate()
        candidate.value = "dvd"
        candidate = segment.addCandidate()
        candidate.value = "DVD"
      }
      do {  // Set OperationPreferences
        converter.setUseCascadingWindow(false)
        converter.setSelectionShortcut(.noShortcut)
      }
      f.composer.insertCharacterKeyAndPreedit("dvd", "ｄｖｄ")
      F.fillT13Ns(segments, f.composer)

      mockConverter.setStartConversion(segments, true)
    }

    #expect(converter.convertToTransliteration(f.composer, .fullAscii))
    let expectedIndices = [0]
    do {  // Check the conversion #1
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment.count == 1)
      #expect(conversion.segment.first?.value == "ｄｖｄ")
      #expect(!F.isCandidateListVisible(converter))
      F.expectSelectedCandidateIndices(converter, expectedIndices)
    }

    #expect(converter.convertToTransliteration(f.composer, .fullAscii))
    do {  // Check the conversion #2
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment.count == 1)
      #expect(conversion.segment.first?.value == "ＤＶＤ")
      #expect(!F.isCandidateListVisible(converter))
      F.expectSelectedCandidateIndices(converter, expectedIndices)
    }

    #expect(converter.convertToTransliteration(f.composer, .fullAscii))
    do {  // Check the conversion #3
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment.count == 1)
      #expect(conversion.segment.first?.value == "Ｄｖｄ")
      #expect(!F.isCandidateListVisible(converter))
      F.expectSelectedCandidateIndices(converter, expectedIndices)
    }
  }

  @Test func multiSegmentsConversion() throws {
    let kKamabokono = "かまぼこの"
    let kInbou = "いんぼう"

    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    do {
      let segments = Segments()
      F.setKamaboko(segments)
      f.composer.insertCharacterPreedit(kKamabokono + kInbou)
      F.fillT13Ns(segments, f.composer)
      mockConverter.setStartConversion(segments, true)
    }
    #expect(converter.convert(f.composer))
    var expectedIndices = [0, 0]
    do {
      #expect(F.getSegmentIndex(converter) == 0)
      F.expectSelectedCandidateIndices(converter, expectedIndices)

      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let conversion = output.preedit
      try #require(conversion.segment.count == 2)
      #expect(conversion.segment[0].annotation == .highlight)
      #expect(conversion.segment[0].key == kKamabokono)
      #expect(conversion.segment[0].value == kKamabokono)

      #expect(conversion.segment[1].annotation == .underline)
      #expect(conversion.segment[1].key == kInbou)
      #expect(conversion.segment[1].value == "陰謀")
    }

    // Test for candidates [CandidateNext]
    #expect(!F.isCandidateListVisible(converter))
    converter.candidateNext(f.composer)
    expectedIndices[0] += 1
    do {
      #expect(F.isCandidateListVisible(converter))
      F.expectSelectedCandidateIndices(converter, expectedIndices)
    }

    // Test for candidates [CandidatePrev]
    converter.candidatePrev()
    expectedIndices[0] -= 1
    do {
      #expect(F.isCandidateListVisible(converter))
      #expect(F.getSegmentIndex(converter) == 0)
      F.expectSelectedCandidateIndices(converter, expectedIndices)
      F.expectSelectedCandidateIndices(converter, expectedIndices)

      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)

      let candidateWindow = output.candidateWindow
      try #require(candidateWindow.size == 3)  // two candidates + one t13n sub list.
      #expect(candidateWindow.position == 0)
      #expect(candidateWindow.candidate[0].value == kKamabokono)
      #expect(candidateWindow.candidate[1].value == "カマボコの")
      #expect(candidateWindow.candidate[2].value == "そのほかの文字種")
    }

    // Test for segment motion. [SegmentFocusRight]
    converter.segmentFocusRight()
    do {
      #expect(F.getSegmentIndex(converter) == 1)
      #expect(!F.isCandidateListVisible(converter))
      converter.setCandidateListVisible(true)

      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)
      F.expectSelectedCandidateIndices(converter, expectedIndices)

      let candidateWindow = output.candidateWindow
      #expect(candidateWindow.focusedIndex == 0)
      try #require(candidateWindow.size == 3)  // two candidates + one t13n sub list.
      #expect(candidateWindow.position == 5)
      #expect(candidateWindow.candidate[0].value == "陰謀")
      #expect(candidateWindow.candidate[1].value == "印房")
      #expect(candidateWindow.candidate[2].value == "そのほかの文字種")
    }

    // Test for segment motion. [SegmentFocusLeft]
    converter.segmentFocusLeft()
    do {
      #expect(F.getSegmentIndex(converter) == 0)
      #expect(!F.isCandidateListVisible(converter))
      converter.setCandidateListVisible(true)
      F.expectSelectedCandidateIndices(converter, expectedIndices)

      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)

      let candidateWindow = output.candidateWindow
      #expect(candidateWindow.focusedIndex == 0)
      try #require(candidateWindow.size == 3)  // two candidates + one t13n sub list.
      #expect(candidateWindow.position == 0)
      #expect(candidateWindow.candidate[0].value == kKamabokono)
      #expect(candidateWindow.candidate[1].value == "カマボコの")
      #expect(candidateWindow.candidate[2].value == "そのほかの文字種")
    }

    // Test for segment motion. [SegmentFocusLeft] at the head of segments.
    // http://b/2990134
    // Focus changing at the tail of segments to right,
    // and at the head of segments to left, should work.
    converter.segmentFocusLeft()
    do {
      #expect(F.getSegmentIndex(converter) == 1)
      #expect(!F.isCandidateListVisible(converter))
      converter.setCandidateListVisible(true)
      F.expectSelectedCandidateIndices(converter, expectedIndices)

      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)

      let candidateWindow = output.candidateWindow
      #expect(candidateWindow.focusedIndex == 0)
      try #require(candidateWindow.size == 3)  // two candidates + one t13n sub list.
      #expect(candidateWindow.position == 5)
      #expect(candidateWindow.candidate[0].value == "陰謀")
      #expect(candidateWindow.candidate[1].value == "印房")
      #expect(candidateWindow.candidate[2].value == "そのほかの文字種")
    }

    // Test for segment motion. [SegmentFocusRight] at the tail of segments.
    // http://b/2990134
    // Focus changing at the tail of segments to right,
    // and at the head of segments to left, should work.
    converter.segmentFocusRight()
    do {
      #expect(!F.isCandidateListVisible(converter))
      converter.setCandidateListVisible(true)
      F.expectSelectedCandidateIndices(converter, expectedIndices)

      var output = Genmai_Commands_Output()
      #expect(F.getSegmentIndex(converter) == 0)
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)

      let candidateWindow = output.candidateWindow
      #expect(candidateWindow.focusedIndex == 0)
      try #require(candidateWindow.size == 3)  // two candidates + one t13n sub list.
      #expect(candidateWindow.position == 0)
      #expect(candidateWindow.candidate[0].value == kKamabokono)
      #expect(candidateWindow.candidate[1].value == "カマボコの")
      #expect(candidateWindow.candidate[2].value == "そのほかの文字種")
    }

    // Test for candidate motion. [CandidateNext]
    converter.segmentFocusRight()  // Focus to the last segment.
    #expect(F.getSegmentIndex(converter) == 1)
    converter.candidateNext(f.composer)
    expectedIndices[1] += 1
    do {
      #expect(F.isCandidateListVisible(converter))
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)
      F.expectSelectedCandidateIndices(converter, expectedIndices)

      let candidateWindow = output.candidateWindow
      #expect(candidateWindow.focusedIndex == 1)
      try #require(candidateWindow.size == 3)  // two candidates + one t13n sub list.
      #expect(candidateWindow.position == 5)
      #expect(candidateWindow.candidate[0].value == "陰謀")
      #expect(candidateWindow.candidate[1].value == "印房")
      #expect(candidateWindow.candidate[2].value == "そのほかの文字種")

      let conversion = output.preedit
      #expect(conversion.segment[0].value == kKamabokono)
      #expect(conversion.segment[1].value == "印房")
    }

    // Test for segment motion again [SegmentFocusLeftEdge] [SegmentFocusLast]
    // The positions of "陰謀" and "印房" should be swapped.
    do {
      let fixedSegments = Segments()
      F.setKamaboko(fixedSegments)
      F.expectSelectedCandidateIndices(converter, expectedIndices)

      try #require(fixedSegments.segment(1).candidate(0).value == "陰謀")
      try #require(fixedSegments.segment(1).candidate(1).value == "印房")
      // swap the values.
      swap(
        &fixedSegments.mutableSegment(1).mutableCandidate(0).value,
        &fixedSegments.mutableSegment(1).mutableCandidate(1).value)
      try #require(fixedSegments.segment(1).candidate(0).value == "印房")
      try #require(fixedSegments.segment(1).candidate(1).value == "陰謀")
      mockConverter.commitSegmentValueHandler = { out, _, _ in
        out.assign(from: fixedSegments)
        return true
      }
    }
    converter.segmentFocusLeftEdge()
    do {
      #expect(F.getSegmentIndex(converter) == 0)
      #expect(!F.isCandidateListVisible(converter))
      converter.segmentFocusLast()
      #expect(F.getSegmentIndex(converter) == 1)
      #expect(!F.isCandidateListVisible(converter))
      converter.setCandidateListVisible(true)

      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)

      let candidateWindow = output.candidateWindow
      #expect(candidateWindow.focusedIndex == 0)
      try #require(candidateWindow.size == 3)  // two candidates + one t13n sub list.
      #expect(candidateWindow.position == 5)
      #expect(candidateWindow.candidate[0].value == "印房")

      #expect(candidateWindow.candidate[1].value == "陰謀")

      #expect(candidateWindow.candidate[2].value == "そのほかの文字種")

      let conversion = output.preedit
      #expect(conversion.segment[0].value == kKamabokono)
      #expect(conversion.segment[1].value == "印房")
    }

    converter.commit(f.composer, Genmai_Commands_Context())
    expectedIndices.removeAll()
    do {
      f.composer.reset()
      #expect(!F.isCandidateListVisible(converter))
      F.expectSelectedCandidateIndices(converter, expectedIndices)

      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(output.hasResult)
      #expect(!output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let result = output.result
      #expect(result.value == "かまぼこの印房")
      #expect(result.key == "かまぼこのいんぼう")
      #expect(!converter.isActive())
    }
  }

  @Test func transliterations() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    f.composer.insertCharacterKeyAndPreedit("h", "く")
    f.composer.insertCharacterKeyAndPreedit("J", "ま")

    let segments = Segments()
    do {  // Initialize segments.
      let segment = segments.addSegment()
      segment.setKey("くま")
      segment.addCandidate().value = "クマー"
    }
    F.fillT13Ns(segments, f.composer)
    mockConverter.setStartConversion(segments, true)

    #expect(converter.convert(f.composer))
    var expectedIndices: [Int] = []
    expectedIndices.append(0)
    #expect(!F.isCandidateListVisible(converter))
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    // Move to the t13n list.
    converter.candidateNext(f.composer)
    expectedIndices[0] = -1
    #expect(F.isCandidateListVisible(converter))
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    var output = Genmai_Commands_Output()
    converter.fillOutput(f.composer, &output)
    #expect(!output.hasResult)
    #expect(output.hasPreedit)
    #expect(output.hasCandidateWindow)

    let candidateWindow = output.candidateWindow
    #expect(candidateWindow.size == 2)  // one candidate + one t13n sub list.
    #expect(candidateWindow.focusedIndex == 1)
    #expect(candidateWindow.candidate[1].value == "そのほかの文字種")

    var t13ns: [String] = []
    f.composer.getTransliterations(&t13ns)

    #expect(candidateWindow.hasSubCandidateWindow)
    #expect(candidateWindow.subCandidateWindow.size == UInt32(t13ns.count))
    #expect(candidateWindow.subCandidateWindow.candidate.count == 9)

    for i in 0..<candidateWindow.subCandidateWindow.candidate.count {
      #expect(candidateWindow.subCandidateWindow.candidate[i].value == t13ns[i])
    }
  }

  @Test func t13NWithResegmentation() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    do {
      let segments = Segments()
      var segment = segments.addSegment()
      segment.setKey("かまぼこの")
      var candidate = segment.addCandidate()
      candidate.value = "かまぼこの"

      segment = segments.addSegment()
      segment.setKey("いんぼう")
      candidate = segment.addCandidate()
      candidate.value = "いんぼう"

      F.insertASCIISequence("kamabokonoinbou", &f.composer)
      F.fillT13Ns(segments, f.composer)
      mockConverter.setStartConversion(segments, true)
    }
    #expect(converter.convert(f.composer))
    var expectedIndices = [0, 0]
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    // Test for segment motion. [SegmentFocusRight]
    converter.segmentFocusRight()
    F.expectSelectedCandidateIndices(converter, expectedIndices)
    // Shrink segment
    let resizeCounter = CallCounter()
    do {
      let segments = Segments()

      segments.clear()
      var segment = segments.addSegment()

      segment.setKey("かまぼこの")
      var candidate = segment.addCandidate()
      candidate.value = "かまぼこの"
      candidate = segment.addCandidate()
      candidate.value = "カマボコの"

      segment = segments.addSegment()
      segment.setKey("いんぼ")
      candidate = segment.addCandidate()
      candidate.value = "インボ"

      segment = segments.addSegment()
      segment.setKey("う")
      candidate = segment.addCandidate()
      candidate.value = "ウ"

      F.fillT13Ns(segments, f.composer)
      mockConverter.resizeSegmentHandler = { out, _, _, _ in
        resizeCounter.increment()
        out.assign(from: segments)
        return true
      }
    }
    converter.segmentWidthShrink(f.composer)
    #expect(resizeCounter.count == 1)
    expectedIndices.append(0)
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    // Convert to half katakana. Expected index should be 0.
    _ = converter.convertToTransliteration(f.composer, .halfKatakana)
    expectedIndices[0] = 0
    do {
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      let preedit = output.preedit
      #expect(preedit.segment.count == 3)
      if preedit.segment.count > 1 {
        #expect(preedit.segment[1].value == "ｲﾝﾎﾞ")
      }
      F.expectSelectedCandidateIndices(converter, expectedIndices)
    }
  }

  @Test func convertToHalfWidth() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    var expectedIndices: [Int] = []
    f.composer.insertCharacterKeyAndPreedit("a", "あ")
    f.composer.insertCharacterKeyAndPreedit("b", "ｂ")
    f.composer.insertCharacterKeyAndPreedit("c", "ｃ")

    let segments = Segments()
    do {  // Initialize segments.
      let segment = segments.addSegment()
      segment.setKey("あｂｃ")
      segment.addCandidate().value = "あべし"
    }
    F.fillT13Ns(segments, f.composer)
    mockConverter.setStartConversion(segments, true)
    #expect(converter.convertToHalfWidth(f.composer))
    expectedIndices.append(0)
    #expect(!F.isCandidateListVisible(converter))
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    do {  // Make sure the output
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment.count == 1)
      #expect(conversion.segment.first?.value == "ｱbc")
    }

    // Composition will be transliterated to "ａｂｃ".
    #expect(converter.convertToTransliteration(f.composer, .fullAscii))
    F.expectSelectedCandidateIndices(converter, expectedIndices)
    do {  // Make sure the output
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment.count == 1)
      #expect(conversion.segment.first?.value == "ａｂｃ")
    }

    #expect(converter.convertToHalfWidth(f.composer))
    F.expectSelectedCandidateIndices(converter, expectedIndices)
    #expect(!F.isCandidateListVisible(converter))
    do {  // Make sure the output
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment.count == 1)
      #expect(conversion.segment.first?.value == "abc")
    }

    #expect(converter.convertToHalfWidth(f.composer))
    F.expectSelectedCandidateIndices(converter, expectedIndices)
    #expect(!F.isCandidateListVisible(converter))
    do {  // Make sure the output
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment.count == 1)
      #expect(conversion.segment.first?.value == "ABC")
    }
  }

  @Test func convertToHalfWidth2() {
    // http://b/2517514
    // ConvertToHalfWidth converts punctuations differently w/ or w/o kana.
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    f.composer.insertCharacterKeyAndPreedit("q", "ｑ")
    f.composer.insertCharacterKeyAndPreedit(",", "、")
    f.composer.insertCharacterKeyAndPreedit(".", "。")

    let segments = Segments()
    do {  // Initialize segments.
      let segment = segments.addSegment()
      segment.setKey("ｑ、。")
      segment.addCandidate().value = "q,."
      segment.addCandidate().value = "q､｡"
    }
    F.fillT13Ns(segments, f.composer)
    mockConverter.setStartConversion(segments, true)
    #expect(converter.convertToHalfWidth(f.composer))
    var expectedIndices: [Int] = []
    expectedIndices.append(0)
    #expect(!F.isCandidateListVisible(converter))
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    do {  // Make sure the output
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment.count == 1)
      #expect(conversion.segment.first?.value == "q､｡")
    }
  }

  @Test func switchKanaTypeFromCompositionMode() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    f.composer.insertCharacterKeyAndPreedit("a", "あ")
    f.composer.insertCharacterKeyAndPreedit("b", "ｂ")
    f.composer.insertCharacterKeyAndPreedit("c", "ｃ")

    let segments = Segments()
    do {  // Initialize segments.
      let segment = segments.addSegment()
      segment.setKey("あｂｃ")
      segment.addCandidate().value = "あべし"
    }
    F.fillT13Ns(segments, f.composer)
    mockConverter.setStartConversion(segments, true)
    #expect(converter.switchKanaType(f.composer))
    let expectedIndices = [0]
    #expect(!F.isCandidateListVisible(converter))
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    for expected in ["アｂｃ", "ｱbc", "あｂｃ"] {
      if expected != "アｂｃ" {
        #expect(converter.switchKanaType(f.composer))
        #expect(!F.isCandidateListVisible(converter))
        F.expectSelectedCandidateIndices(converter, expectedIndices)
      }
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment.count == 1)
      #expect(conversion.segment.first?.value == expected)
    }
  }

  @Test func switchKanaTypeFromConversionMode() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    f.composer.editErase()
    f.composer.insertCharacterKeyAndPreedit("ka", "か")
    f.composer.insertCharacterKeyAndPreedit("n", "ん")
    f.composer.insertCharacterKeyAndPreedit("ji", "じ")

    let segments = Segments()
    do {  // Initialize segments.
      let segment = segments.addSegment()
      segment.setKey("かんじ")
      segment.addCandidate().value = "漢字"
    }
    F.fillT13Ns(segments, f.composer)
    mockConverter.setStartConversion(segments, true)
    #expect(converter.convert(f.composer))
    let expectedIndices = [0]
    #expect(!F.isCandidateListVisible(converter))
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    do {  // Make sure the output
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment.count == 1)
      #expect(conversion.segment.first?.value == "漢字")
    }

    for expected in ["かんじ", "カンジ", "ｶﾝｼﾞ", "かんじ"] {
      #expect(converter.switchKanaType(f.composer))
      #expect(!F.isCandidateListVisible(converter))
      F.expectSelectedCandidateIndices(converter, expectedIndices)
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment.count == 1)
      #expect(conversion.segment.first?.value == expected)
    }
  }

  @Test func resizeSegmentsFailedInSwitchKanaType() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    // ResizeSegments() is called when the conversion result has multiple
    // segments. Let the underlying converter return the result with two segments.
    let segments = Segments()
    addSegmentWithSingleCandidate(segments, "かな", "カナ")
    addSegmentWithSingleCandidate(segments, "たいぷ", "タイプ")
    mockConverter.setStartConversion(segments, true)

    // Suppose that ResizeSegments() fails for "かな|たいぷ" (UTF8-length is 5).
    let newSizes: [UInt8] = [5]
    let resizeCounter = CallCounter()
    mockConverter.resizeSegmentsHandler = { _, _, start, sizes in
      if start == 0 && sizes == newSizes { resizeCounter.increment() }
      return false
    }

    // FocusSegmentValue() is called in the last step.
    let focusCounter = CallCounter()
    mockConverter.focusSegmentValueHandler = { _, segmentIndex, candidateIndex in
      guard segmentIndex == 0 && candidateIndex == 0 else { return false }
      focusCounter.increment()
      return true
    }

    // Calling SwitchKanaType() with the above set up doesn't crash.
    #expect(converter.switchKanaType(f.composer))
    #expect(resizeCounter.count == 1)
    #expect(focusCounter.count == 1)
  }

  @Test func commitFirstSegment() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    let segments = Segments()
    F.setKamaboko(segments)
    f.composer.insertCharacterPreedit("かまぼこ")
    F.fillT13Ns(segments, f.composer)
    mockConverter.setStartConversion(segments, true)

    let kKamabokono = "かまぼこの"
    let kInbou = "いんぼう"

    f.composer.insertCharacterPreedit(kKamabokono + kInbou)
    #expect(converter.convert(f.composer))
    var expectedIndices = [0, 0]
    #expect(!F.isCandidateListVisible(converter))
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    do {  // Check the conversion.
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment[0].value == kKamabokono)
      #expect(conversion.segment[1].value == "陰謀")
    }

    let focusCounter = CallCounter()
    mockConverter.focusSegmentValueHandler = { _, segmentIndex, candidateIndex in
      guard segmentIndex == 0 && candidateIndex == 1 else { return false }
      focusCounter.increment()
      return true
    }
    converter.candidateNext(f.composer)
    #expect(focusCounter.count == 1)
    expectedIndices[0] += 1
    #expect(F.isCandidateListVisible(converter))
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    do {  // Check the conversion.
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment[0].value == "カマボコの")
      #expect(conversion.segment[1].value == "陰謀")
    }

    do {  // Initialization of CommitSegments.
      let segmentsAfterSubmit = Segments()
      let segment = segmentsAfterSubmit.addSegment()
      segment.setKey("いんぼう")
      segment.addCandidate().value = "陰謀"
      segment.addCandidate().value = "印房"
      // NOTE: the C++ test sets |segments| (not |segments_after_submit|).
      mockConverter.commitSegmentsHandler = { out, _ in
        out.assign(from: segments)
        return true
      }
    }
    var size = 0
    converter.commitFirstSegment(f.composer, Genmai_Commands_Context(), &size)
    expectedIndices.removeFirst(1)
    #expect(!F.isCandidateListVisible(converter))
    #expect(size == Util.charsLen(kKamabokono))
    #expect(converter.isActive())
    F.expectSelectedCandidateIndices(converter, expectedIndices)
  }

  @Test func commitHeadToFocusedSegments() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    let kIberiko = "いべりこ"
    let kNekowo = "ねこを"
    let kItadaita = "いただいた"
    do {  // Three segments as the result of conversion.
      let segments = Segments()

      var segment = segments.addSegment()
      segment.setKey(kIberiko)
      var candidate = segment.addCandidate()
      candidate.value = "イベリコ"

      segment = segments.addSegment()
      segment.setKey(kNekowo)
      candidate = segment.addCandidate()
      candidate.value = "猫を"

      segment = segments.addSegment()
      segment.setKey(kItadaita)
      candidate = segment.addCandidate()
      candidate.value = "頂いた"

      mockConverter.setStartConversion(segments, true)
    }

    f.composer.insertCharacterPreedit(kIberiko + kNekowo + kItadaita)
    #expect(converter.convert(f.composer))
    // Here [イベリコ]|猫を|頂いた

    let commitValueCounter = CallCounter()
    mockConverter.commitSegmentValueHandler = { _, segmentIndex, candidateIndex in
      guard segmentIndex == 0 && candidateIndex == 0 else { return false }
      commitValueCounter.increment()
      return true
    }
    converter.segmentFocusRight()
    #expect(commitValueCounter.count == 1)
    // Here イベリコ|[猫を]|頂いた

    let commitSegmentsCounter = CallCounter()
    do {  // Initialization of CommitSegments.
      let segments = Segments()

      let segment = segments.addSegment()
      segment.setKey(kItadaita)
      let candidate = segment.addCandidate()
      candidate.value = "頂いた"
      mockConverter.commitSegmentsHandler = { out, _ in
        commitSegmentsCounter.increment()
        out.assign(from: segments)
        return true
      }
    }
    var size = 0
    converter.commitHeadToFocusedSegments(f.composer, Genmai_Commands_Context(), &size)
    #expect(commitSegmentsCounter.count == 1)
    // Here 頂いた
    #expect(!F.isCandidateListVisible(converter))
    #expect(size == Util.charsLen(kIberiko + kNekowo))
    #expect(converter.isActive())
  }

  @Test func commitHeadToFocusedSegmentsAtLastSegment() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let segments = Segments()
    F.setKamaboko(segments)
    mockConverter.setStartConversion(segments, true)

    let kKamabokono = "かまぼこの"
    let kInbou = "いんぼう"

    f.composer.insertCharacterPreedit(kKamabokono + kInbou)
    #expect(converter.convert(f.composer))
    // Here [かまぼこの]|陰謀

    converter.segmentFocusRight()
    // Here かまぼこの|[陰謀]

    var size = 0
    // All the segments should be committed.
    converter.commitHeadToFocusedSegments(f.composer, Genmai_Commands_Context(), &size)
    #expect(!F.isCandidateListVisible(converter))
    #expect(size == 0)
    #expect(!converter.isActive())
  }

  @Test func commitConvertedBracketPairText() throws {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    let segments = Segments()
    let kKakko = "かっこ"

    do {  // Initialize segments.
      segments.clear()
      let segment = segments.addSegment()
      segment.setKey(kKakko)
      var candidate = segment.addCandidate()
      candidate.value = "（）"
      candidate.key = kKakko
      candidate.contentKey = kKakko
      candidate = segment.addCandidate()
      candidate.value = "「」"
      candidate.key = kKakko
      candidate.contentKey = kKakko
    }

    f.composer.insertCharacterPreedit(kKakko)

    // Suggestion
    setStartPrediction(mockConverter, segments, true)
    try #require(converter.suggest(f.composer, Genmai_Commands_Context()))
    var expectedIndices = [0]
    #expect(F.isCandidateListVisible(converter))
    #expect(converter.isActive())

    do {  // Check the candidate list.
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)

      let preedit = output.preedit
      #expect(preedit.segment.count == 1)
      #expect(preedit.segment.first?.value == kKakko)

      let candidateWindow = output.candidateWindow
      #expect(candidateWindow.size == 2)
      #expect(candidateWindow.candidate.first?.value == "（）")
      #expect(!candidateWindow.hasFocusedIndex)
      F.expectSelectedCandidateIndices(converter, expectedIndices)
    }

    let commitValueCounter = CallCounter()
    mockConverter.commitSegmentValueHandler = { _, segmentIndex, candidateIndex in
      guard segmentIndex == 0 && candidateIndex == 1 else { return false }
      commitValueCounter.increment()
      return true
    }
    // FinishConversion is expected to return empty Segments.
    let finishCounter = CallCounter()
    mockConverter.finishConversionHandler = { _, out in
      finishCounter.increment()
      out.assign(from: Segments())
    }

    var committedKeySize = 0
    _ = converter.commitSuggestionByIndex(
      1, f.composer, Genmai_Commands_Context(), &committedKeySize)
    #expect(commitValueCounter.count == 1)
    #expect(finishCounter.count == 1)
    expectedIndices.removeAll()
    f.composer.reset()
    #expect(!F.isCandidateListVisible(converter))
    #expect(!converter.isActive())
    #expect(committedKeySize == EngineConverter.kConsumedAllCharacters)

    do {  // Check the result
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(output.hasResult)
      #expect(!output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let result = output.result
      #expect(result.value == "「」")
      #expect(result.key == kKakko)
      #expect(result.cursorOffset == -1)
      #expect(F.getState(converter) == EngineConverterState.composition)
      F.expectSelectedCandidateIndices(converter, expectedIndices)
    }

    #expect(!converter.isActive())
  }

  @Test func commitPreedit() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let expectedIndices: [Int] = []
    F.expectSelectedCandidateIndices(converter, expectedIndices)
    f.composer.insertCharacterPreedit(kChars_Aiueo)
    F.expectSelectedCandidateIndices(converter, expectedIndices)
    converter.commitPreedit(f.composer, Genmai_Commands_Context())
    f.composer.reset()
    #expect(!F.isCandidateListVisible(converter))
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    do {  // Check the result
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(output.hasResult)
      #expect(!output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let result = output.result
      #expect(result.value == kChars_Aiueo)
      #expect(result.key == kChars_Aiueo)

      #expect(result.tokens.count == 1)
      #expect(result.tokens.first?.key == kChars_Aiueo)
      #expect(result.tokens.first?.value == kChars_Aiueo)
      #expect(result.tokens.first?.lid == -1)
      #expect(result.tokens.first?.rid == -1)
    }
    #expect(!converter.isActive())
  }

  @Test func commitPreeditBracketPairText() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let expectedIndices: [Int] = []
    F.expectSelectedCandidateIndices(converter, expectedIndices)
    f.composer.insertCharacterPreedit("（）")
    F.expectSelectedCandidateIndices(converter, expectedIndices)
    converter.commitPreedit(f.composer, Genmai_Commands_Context())
    f.composer.reset()
    #expect(!F.isCandidateListVisible(converter))
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    do {  // Check the result
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(output.hasResult)
      #expect(!output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let result = output.result
      #expect(result.value == "（）")
      #expect(result.key == "（）")
      #expect(result.cursorOffset == -1)
    }

    #expect(!converter.isActive())
  }

  @Test func clearSegmentsBeforeSuggest() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    // Call Suggest() and sets the segments of converter to the following one.
    let segments = F.getSegmentsTest()
    setStartPrediction(mockConverter, segments, true)
    f.composer.insertCharacterPreedit("てすと")
    #expect(converter.suggest(f.composer, Genmai_Commands_Context()))

    // Then, call Suggest() again. It should be called with brand new segments.
    let empty = Segments()
    let counter = CallCounter()
    mockConverter.startPredictionHandler = { _, out in
      // Pointee(EqualsSegments(empty))
      guard out.segmentsSize == empty.segmentsSize else { return false }
      counter.increment()
      out.assign(from: segments)
      return true
    }
    #expect(converter.suggest(f.composer, Genmai_Commands_Context()))
    #expect(counter.count == 1)
  }

  @Test func predictIsNotCalledInPredictionState() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    // Call Predict() and sets the segments of converter to the following one. By
    // calling Predict(), converter enters PREDICTION state.
    let segments = F.getSegmentsTest()
    let withPreviousCounter = CallCounter()
    mockConverter.startPredictionWithPreviousSuggestionHandler = { _, _, out in
      withPreviousCounter.increment()
      out.assign(from: segments)
      return true
    }
    f.composer.insertCharacterPreedit("てすと")
    #expect(converter.predict(f.composer))
    #expect(withPreviousCounter.count == 1)

    // Then, call Predict() again. PredictForRequest() is not called.
    let prependCounter = CallCounter()
    mockConverter.prependCandidatesHandler = { _, _, out in
      prependCounter.increment()
      out.assign(from: segments)
    }
    #expect(converter.predict(f.composer))
    #expect(withPreviousCounter.count == 1)  // Times(0) for the second call.
    #expect(prependCounter.count == 1)
  }

  @Test func commitSuggestionByIndex() throws {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    let segments = Segments()
    do {  // Initialize mock segments for suggestion
      let segment = segments.addSegment()
      segment.setKey(kChars_Mo)
      var candidate = segment.addCandidate()
      candidate.value = kChars_Mozukusu
      candidate.key = kChars_Mozukusu
      candidate.contentKey = kChars_Mozukusu
      candidate = segment.addCandidate()
      candidate.value = kChars_Momonga
      candidate.key = kChars_Momonga
      candidate.contentKey = kChars_Momonga
    }
    f.composer.insertCharacterPreedit(kChars_Mo)

    // Suggestion
    setStartPrediction(mockConverter, segments, true)
    try #require(converter.suggest(f.composer, Genmai_Commands_Context()))
    var expectedIndices = [0]
    #expect(F.isCandidateListVisible(converter))
    #expect(converter.isActive())

    do {  // Check the candidate list
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)

      let preedit = output.preedit
      #expect(preedit.segment.count == 1)
      #expect(preedit.segment.first?.value == kChars_Mo)

      let candidateWindow = output.candidateWindow
      #expect(candidateWindow.size == 2)
      #expect(candidateWindow.candidate.first?.value == kChars_Mozukusu)
      #expect(!candidateWindow.hasFocusedIndex)
      F.expectSelectedCandidateIndices(converter, expectedIndices)
    }

    let commitValueCounter = CallCounter()
    mockConverter.commitSegmentValueHandler = { _, segmentIndex, candidateIndex in
      guard segmentIndex == 0 && candidateIndex == 1 else { return false }
      commitValueCounter.increment()
      return true
    }
    // FinishConversion is expected to return empty Segments.
    let finishCounter = CallCounter()
    mockConverter.finishConversionHandler = { _, out in
      finishCounter.increment()
      out.assign(from: Segments())
    }

    var committedKeySize = 0
    _ = converter.commitSuggestionByIndex(
      1, f.composer, Genmai_Commands_Context(), &committedKeySize)
    #expect(commitValueCounter.count == 1)
    #expect(finishCounter.count == 1)
    expectedIndices.removeAll()
    f.composer.reset()
    #expect(!F.isCandidateListVisible(converter))
    #expect(!converter.isActive())
    #expect(committedKeySize == EngineConverter.kConsumedAllCharacters)

    do {  // Check the result
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(output.hasResult)
      #expect(!output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let result = output.result
      #expect(result.value == kChars_Momonga)
      #expect(result.key == kChars_Momonga)
      #expect(F.getState(converter) == EngineConverterState.composition)
      F.expectSelectedCandidateIndices(converter, expectedIndices)
    }
  }

  @Test func commitSuggestionById() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    let segments = Segments()
    do {  // Initialize mock segments for suggestion
      let segment = segments.addSegment()
      segment.setKey(kChars_Mo)
      var candidate = segment.addCandidate()
      candidate.value = kChars_Mozukusu
      candidate.key = kChars_Mozukusu
      candidate.contentKey = kChars_Mozukusu
      candidate = segment.addCandidate()
      candidate.value = kChars_Momonga
      candidate.key = kChars_Momonga
      candidate.contentKey = kChars_Momonga
    }
    f.composer.insertCharacterPreedit(kChars_Mo)

    // Suggestion
    setStartPrediction(mockConverter, segments, true)
    #expect(converter.suggest(f.composer, Genmai_Commands_Context()))

    var expectedIndices = [0]
    #expect(F.isCandidateListVisible(converter))
    #expect(converter.isActive())
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    // FinishConversion is expected to return empty Segments.
    let kCandidateIndex = 1
    let finishCounter = CallCounter()
    mockConverter.finishConversionHandler = { _, out in
      finishCounter.increment()
      out.assign(from: Segments())
    }
    let commitValueCounter = CallCounter()
    mockConverter.commitSegmentValueHandler = { out, segmentIndex, candidateIndex in
      guard segmentIndex == 0 && candidateIndex == kCandidateIndex else { return false }
      commitValueCounter.increment()
      out.assign(from: segments)
      return true
    }
    var committedKeySize = 0
    _ = converter.commitSuggestionById(
      kCandidateIndex, f.composer, Genmai_Commands_Context(), &committedKeySize)
    #expect(finishCounter.count == 1)
    #expect(commitValueCounter.count == 1)
    expectedIndices.removeAll()
    f.composer.reset()
    #expect(!F.isCandidateListVisible(converter))
    #expect(!converter.isActive())
    #expect(committedKeySize == EngineConverter.kConsumedAllCharacters)
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    do {  // Check the result
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(output.hasResult)
      #expect(!output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let result = output.result
      #expect(result.value == kChars_Momonga)
      #expect(result.key == kChars_Momonga)
      #expect(F.getState(converter) == EngineConverterState.composition)
    }
  }
}
