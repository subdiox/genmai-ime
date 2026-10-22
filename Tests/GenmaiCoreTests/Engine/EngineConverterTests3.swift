// Port of mozc/src/engine/engine_converter_test.cc (3.35.6354), part 3.
//
// TEST_F DeleteCandidateFromHistory .. CommitHeadToFocusedSegmentsMultiSegmentCandidate.

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private typealias F = EngineConverterTestFixture
private typealias S = EngineConverterState

/// EXPECT_CALL(StartConversion(_, _)).WillOnce(DoAll(SetArgPointee<1>(segments), Return(result)))
@discardableResult
private func expectStartConversion(
  _ mock: MockConverter, _ segments: Segments, _ result: Bool = true
) -> CallCounter {
  let counter = CallCounter()
  let copy = segments.copy()
  mock.startConversionHandler = { _, out in
    counter.increment()
    out.assign(from: copy)
    return result
  }
  return counter
}

/// EXPECT_CALL(StartPrediction(_, _)).WillOnce(DoAll(SetArgPointee<1>(segments), Return(result)))
@discardableResult
private func expectStartPrediction(
  _ mock: MockConverter, _ segments: Segments, _ result: Bool = true
) -> CallCounter {
  let counter = CallCounter()
  let copy = segments.copy()
  mock.startPredictionHandler = { _, out in
    counter.increment()
    out.assign(from: copy)
    return result
  }
  return counter
}

/// EXPECT_CALL(FocusSegmentValue(_, segmentIndex, candidateIndex)).WillOnce(Return(true))
private func expectFocusSegmentValue(
  _ mock: MockConverter, _ segmentIndex: Int, _ candidateIndex: Int,
  sourceLocation: SourceLocation = #_sourceLocation
) -> CallCounter {
  let counter = CallCounter()
  mock.focusSegmentValueHandler = { _, s, c in
    counter.increment()
    #expect(s == segmentIndex, sourceLocation: sourceLocation)
    #expect(c == candidateIndex, sourceLocation: sourceLocation)
    return true
  }
  return counter
}

/// EXPECT_CALL(CommitSegmentValue(_, segmentIndex, candidateIndex)).WillOnce(action)
private func expectCommitSegmentValue(
  _ mock: MockConverter, _ segmentIndex: Int, _ candidateIndex: Int,
  sourceLocation: SourceLocation = #_sourceLocation,
  _ action: ((Segments, Int, Int) -> Bool)? = nil
) -> CallCounter {
  let counter = CallCounter()
  mock.commitSegmentValueHandler = { segs, s, c in
    counter.increment()
    #expect(s == segmentIndex, sourceLocation: sourceLocation)
    #expect(c == candidateIndex, sourceLocation: sourceLocation)
    return action?(segs, s, c) ?? true
  }
  return counter
}

/// EXPECT_CALL(FinishConversion(_, _))
private func expectFinishConversion(_ mock: MockConverter) -> CallCounter {
  let counter = CallCounter()
  mock.finishConversionHandler = { _, _ in counter.increment() }
  return counter
}

/// EXPECT_CALL(ResizeSegment(_, _, segmentIndex, offsetLength)).WillOnce(Return(true))
private func expectResizeSegment(
  _ mock: MockConverter, _ segmentIndex: Int, _ offsetLength: Int,
  sourceLocation: SourceLocation = #_sourceLocation
) -> CallCounter {
  let counter = CallCounter()
  mock.resizeSegmentHandler = { _, _, s, o in
    counter.increment()
    #expect(s == segmentIndex, sourceLocation: sourceLocation)
    #expect(o == offsetLength, sourceLocation: sourceLocation)
    return true
  }
  return counter
}

private func addSegment(_ segments: Segments, _ key: String) -> Segment {
  let seg = segments.addSegment()
  seg.setKey(key)
  return seg
}

private func addCandidate(
  _ segment: Segment, value: String, key: String, contentKey: String? = nil,
  convertedSegmentCount: UInt32? = nil
) -> Candidate {
  let cand = segment.addCandidate()
  cand.value = value
  cand.key = key
  if let contentKey { cand.contentKey = contentKey }
  if let convertedSegmentCount { cand.convertedSegmentCount = convertedSegmentCount }
  return cand
}

private func setAllHistory(_ segments: Segments) {
  for segment in segments.all {
    segment.setSegmentType(.history)
  }
}

struct EngineConverterTests3 {
  @Test func deleteCandidateFromHistory() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    mockConverter.deleteCandidateFromHistoryHandler = { _, _, _ in true }

    // No valid segments / focused candidate list
    #expect(!converter.deleteCandidateFromHistory(nil))
    #expect(!converter.deleteCandidateFromHistory(1))

    do {
      // Set segments
      let segments = Segments()
      F.setAiueo(segments)
      f.composer.insertCharacterPreedit(kCharsAiueo)
      F.fillT13Ns(segments, f.composer)
      expectStartConversion(mockConverter, segments)

      _ = converter.convert(f.composer)
    }
    #expect(converter.deleteCandidateFromHistory(nil))
    #expect(converter.deleteCandidateFromHistory(1))
    // Invalid candidate id
    #expect(!converter.deleteCandidateFromHistory(-100))
  }

  @Test func commitHead() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    f.composer.insertCharacterPreedit(kCharsAiueo)

    var committedSize = 0
    converter.commitHead(1, f.composer, &committedSize)
    #expect(committedSize == 1)
    f.composer.deleteAt(0)

    var output = Genmai_Commands_Output()
    converter.fillOutput(f.composer, &output)
    #expect(output.hasResult)
    #expect(!output.hasCandidateWindow)

    let result = output.result
    #expect(result.value == "あ")
    #expect(result.key == "あ")
    var preedit = f.composer.getStringForPreedit()
    #expect(preedit == "いうえお")

    converter.commitHead(3, f.composer, &committedSize)
    #expect(committedSize == 3)
    f.composer.deleteAt(0)
    f.composer.deleteAt(0)
    f.composer.deleteAt(0)
    converter.fillOutput(f.composer, &output)
    #expect(output.hasResult)
    #expect(!output.hasCandidateWindow)

    let result2 = output.result
    #expect(result2.value == "いうえ")
    #expect(result2.key == "いうえ")
    preedit = f.composer.getStringForPreedit()
    #expect(preedit == "お")
  }

  @Test func commandCandidate() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    let segments = Segments()
    F.setAiueo(segments)
    f.composer.insertCharacterPreedit("あいうえお")
    F.fillT13Ns(segments, f.composer)
    // set COMMAND_CANDIDATE.
    F.setCommandCandidate(segments, 0, 0, .defaultCommand)
    expectStartConversion(mockConverter, segments)

    f.composer.insertCharacterPreedit(kCharsAiueo)
    #expect(converter.convert(f.composer))

    converter.commit(f.composer, Genmai_Commands_Context())
    var output = Genmai_Commands_Output()
    converter.fillOutput(f.composer, &output)
    #expect(!output.hasResult)
  }

  @Test func commandCandidateWithCommitCommands() {
    let f = F()
    let kKamabokono = "かまぼこの"
    let kInbou = "いんぼう"
    f.composer.insertCharacterPreedit(kKamabokono + kInbou)

    do {
      // The first candidate is a command candidate, so
      // CommitFirstSegment resets all conversion.
      let mockConverter = MockConverter()
      let converter = EngineConverter(mockConverter, f.request, f.config)
      let segments = Segments()
      F.setKamaboko(segments)
      F.setCommandCandidate(segments, 0, 0, .defaultCommand)
      expectStartConversion(mockConverter, segments)
      _ = converter.convert(f.composer)

      var committedSize = 0
      converter.commitFirstSegment(f.composer, Genmai_Commands_Context(), &committedSize)
      #expect(committedSize == 0)

      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!converter.isActive())
      #expect(!output.hasResult)
    }

    do {
      // The second candidate is a command candidate, so
      // CommitFirstSegment commits all conversion.
      let mockConverter = MockConverter()
      let converter = EngineConverter(mockConverter, f.request, f.config)
      let segments = Segments()
      F.setKamaboko(segments)
      F.setCommandCandidate(segments, 1, 0, .defaultCommand)
      expectStartConversion(mockConverter, segments)
      _ = converter.convert(f.composer)

      var committedSize = 0
      converter.commitFirstSegment(f.composer, Genmai_Commands_Context(), &committedSize)
      #expect(committedSize == Util.charsLen(kKamabokono))

      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(converter.isActive())
      #expect(output.hasResult)
    }

    do {
      // The selected suggestion with Id is a command candidate.
      let mockConverter = MockConverter()
      let converter = EngineConverter(mockConverter, f.request, f.config)
      let segments = Segments()
      F.setAiueo(segments)
      F.setCommandCandidate(segments, 0, 0, .defaultCommand)
      expectStartPrediction(mockConverter, segments)
      _ = converter.suggest(f.composer, Genmai_Commands_Context())

      var committedSize = 0
      #expect(
        !converter.commitSuggestionById(0, f.composer, Genmai_Commands_Context(), &committedSize))
      #expect(committedSize == 0)
    }

    do {
      // The selected suggestion with Index is a command candidate.
      let mockConverter = MockConverter()
      let converter = EngineConverter(mockConverter, f.request, f.config)
      let segments = Segments()
      F.setAiueo(segments)
      F.setCommandCandidate(segments, 0, 1, .defaultCommand)
      expectStartPrediction(mockConverter, segments)
      _ = converter.suggest(f.composer, Genmai_Commands_Context())

      var committedSize = 0
      #expect(
        !converter.commitSuggestionByIndex(1, f.composer, Genmai_Commands_Context(), &committedSize))
      #expect(committedSize == 0)
    }
  }

  @Test func executeCommandCandidate() {
    let f = F()
    // Enable Incognito mode
    do {
      f.config.incognitoMode = false
      let mockConverter = MockConverter()
      let converter = EngineConverter(mockConverter, f.request, f.config)

      let segments = Segments()
      F.setAiueo(segments)
      F.setCommandCandidate(segments, 0, 0, .enableIncognitoMode)
      expectStartConversion(mockConverter, segments)

      f.composer.insertCharacterPreedit(kCharsAiueo)
      #expect(converter.convert(f.composer))

      converter.commit(f.composer, Genmai_Commands_Context())
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)

      // The config in the |output| has the updated value, but |config_| keeps
      // the previous value.
      #expect(output.hasConfig)
      #expect(output.config.incognitoMode)
      #expect(!f.config.incognitoMode)
    }

    // Disable Incognito mode
    do {
      f.config.incognitoMode = false
      let mockConverter = MockConverter()
      let converter = EngineConverter(mockConverter, f.request, f.config)

      let segments = Segments()
      F.setAiueo(segments)
      F.setCommandCandidate(segments, 0, 0, .disableIncognitoMode)
      expectStartConversion(mockConverter, segments)

      f.composer.insertCharacterPreedit(kCharsAiueo)
      #expect(converter.convert(f.composer))

      converter.commit(f.composer, Genmai_Commands_Context())
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)

      // The config in the |output| has the updated value, but |config_| keeps
      // the previous value.
      #expect(output.hasConfig)
      #expect(!output.config.incognitoMode)
      #expect(!f.config.incognitoMode)
    }

    // Enable Presentation mode
    do {
      f.config.presentationMode = false
      let mockConverter = MockConverter()
      let converter = EngineConverter(mockConverter, f.request, f.config)

      let segments = Segments()
      F.setAiueo(segments)
      F.setCommandCandidate(segments, 0, 0, .enablePresentationMode)
      expectStartConversion(mockConverter, segments)

      f.composer.insertCharacterPreedit(kCharsAiueo)
      #expect(converter.convert(f.composer))

      converter.commit(f.composer, Genmai_Commands_Context())
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)

      // The config in the |output| has the updated value, but |config_| keeps
      // the previous value.
      #expect(output.hasConfig)
      #expect(output.config.presentationMode)
      #expect(!f.config.presentationMode)
    }

    // Disable Presentation mode
    do {
      f.config.incognitoMode = true
      let mockConverter = MockConverter()
      let converter = EngineConverter(mockConverter, f.request, f.config)

      let segments = Segments()
      F.setAiueo(segments)
      F.setCommandCandidate(segments, 0, 0, .disablePresentationMode)
      expectStartConversion(mockConverter, segments)

      f.composer.insertCharacterPreedit(kCharsAiueo)
      #expect(converter.convert(f.composer))

      converter.commit(f.composer, Genmai_Commands_Context())
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)

      // The config in the |output| has the updated value, but |config_| keeps
      // the previous value.
      #expect(output.hasConfig)
      #expect(!output.config.presentationMode)
      #expect(!f.config.presentationMode)
    }
  }

  @Test func propagateConfigToRenderer() {
    let f = F()
    // Disable information_list_config()
    do {
      let mockConverter = MockConverter()
      let converter = EngineConverter(mockConverter, f.request, f.config)
      let segments = Segments()
      F.setAiueo(segments)
      f.composer.insertCharacterPreedit("あいうえお")
      F.fillT13Ns(segments, f.composer)
      expectStartConversion(mockConverter, segments)

      var output = Genmai_Commands_Output()
      f.composer.insertCharacterPreedit(kCharsAiueo)
      _ = converter.convert(f.composer)

      #expect(!F.isCandidateListVisible(converter))
      output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasConfig)

      converter.candidateNext(f.composer)
      #expect(F.isCandidateListVisible(converter))
      output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasConfig)
    }
  }

  @Test func conversionFail() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    // Conversion fails.
    do {
      // segments doesn't have any candidates.
      let segments = Segments()
      segments.addSegment().setKey(kCharsAiueo)
      let c = expectStartConversion(mockConverter, segments, false)
      f.composer.insertCharacterPreedit(kCharsAiueo)

      // Falls back to composition state.
      #expect(!converter.convert(f.composer))
      #expect(c.count == 1)
      #expect(!F.isCandidateListVisible(converter))
      #expect(converter.checkState(S.composition))

      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)
      #expect(!F.isCandidateListVisible(converter))
    }

    f.composer.reset()

    // Suggestion succeeds and conversion fails.
    do {
      let segments = Segments()
      F.setAiueo(segments)
      let p = expectStartPrediction(mockConverter, segments)
      f.composer.insertCharacterPreedit(kCharsAiueo)

      #expect(converter.suggest(f.composer, Genmai_Commands_Context()))
      #expect(p.count == 1)
      #expect(F.isCandidateListVisible(converter))
      #expect(converter.checkState(S.suggestion))

      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)

      segments.clear()
      output = Genmai_Commands_Output()

      // segments doesn't have any candidates.
      segments.addSegment().setKey(kCharsAiueo)
      let c = expectStartConversion(mockConverter, segments, false)

      // Falls back to composition state.
      #expect(!converter.convert(f.composer))
      #expect(c.count == 1)
      #expect(!F.isCandidateListVisible(converter))
      #expect(converter.checkState(S.composition))

      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)
    }
  }

  @Test func resetByClientRevision() {
    let f = F()
    let kRevision: Int32 = 0x1234

    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    var context = Genmai_Commands_Context()

    let reset = CallCounter()
    let revert = CallCounter()
    mockConverter.resetConversionHandler = { _ in reset.increment() }
    mockConverter.revertConversionHandler = { _ in revert.increment() }

    // Initialize the session converter with given context age.
    context.revision = kRevision
    converter.onStartComposition(context)
    #expect(reset.count == 1)
    converter.revert()
    #expect(revert.count == 1)

    // OnStartComposition with different context age causes Reset()
    context.revision = kRevision + 1
    converter.onStartComposition(context)
    #expect(reset.count == 2)
  }

  @Test func resetByPrecedingText() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let reset = CallCounter()
    let revert = CallCounter()
    mockConverter.resetConversionHandler = { _ in reset.increment() }
    mockConverter.revertConversionHandler = { _ in revert.increment() }

    // no preceding_text -> Reset should not be called.
    do {
      let segments = Segments()
      F.setAiueo(segments)
      f.composer.insertCharacterPreedit("あいうえお")
      F.fillT13Ns(segments, f.composer)
      setAllHistory(segments)
      F.setSegments(segments, converter)
      converter.onStartComposition(Genmai_Commands_Context())
      #expect(reset.count == 0)
      converter.revert()
      #expect(revert.count == 1)
    }

    // preceding_text == history_segments -> Reset should not be called.
    do {
      let segments = Segments()
      F.setAiueo(segments)
      f.composer.insertCharacterPreedit("あいうえお")
      F.fillT13Ns(segments, f.composer)
      setAllHistory(segments)
      F.setSegments(segments, converter)
      var context = Genmai_Commands_Context()
      context.precedingText = kCharsAiueo
      converter.onStartComposition(context)
      #expect(reset.count == 0)
      converter.revert()
      #expect(revert.count == 2)
    }

    // preceding_text == "" && history_segments != "" -> Reset should be called.
    do {
      let segments = Segments()
      F.setAiueo(segments)
      f.composer.insertCharacterPreedit("あいうえお")
      F.fillT13Ns(segments, f.composer)
      setAllHistory(segments)
      F.setSegments(segments, converter)
      var context = Genmai_Commands_Context()
      context.precedingText = ""
      converter.onStartComposition(context)
      #expect(reset.count == 1)
      converter.revert()
      #expect(revert.count == 3)
    }

    // preceding_text != "" && preceding_text.EndsWith(history_segments).
    //    -> Reset should not be called.
    do {
      let segments = Segments()
      F.setAiueo(segments)
      f.composer.insertCharacterPreedit("あいうえお")
      F.fillT13Ns(segments, f.composer)
      setAllHistory(segments)
      F.setSegments(segments, converter)
      var context = Genmai_Commands_Context()
      context.precedingText = kCharsAiueo
      converter.onStartComposition(context)
      #expect(reset.count == 1)
    }

    // preceding_text != "" && history_segments.EndsWith(preceding_text).
    //    -> Reset should not be called.
    do {
      let segments = Segments()
      F.setAiueo(segments)
      f.composer.insertCharacterPreedit("あいうえお")
      F.fillT13Ns(segments, f.composer)
      setAllHistory(segments)
      F.setSegments(segments, converter)
      var context = Genmai_Commands_Context()
      context.precedingText = kCharsAiueo
      converter.onStartComposition(context)
      #expect(reset.count == 1)
      converter.revert()
      #expect(revert.count == 4)
    }
  }

  @Test func reconstructHistoryByPrecedingText() {
    let f = F()
    let kId: UInt16 = 1234
    let kKey = "1"
    let kValue = "1"

    // Set up the result which mock_converter.ReconstructHistory() returns.
    let mockResult = Segments()
    do {
      let segment = mockResult.addSegment()
      segment.setKey(kKey)
      segment.setSegmentType(.history)
      let candidate = segment.pushBackCandidate()
      candidate.rid = kId
      candidate.lid = kId
      candidate.contentKey = kKey
      candidate.key = kKey
      candidate.contentValue = kValue
      candidate.value = kValue
      candidate.attributes = Attribute.noLearning
    }

    func expectReconstruct(_ mock: MockConverter) -> CallCounter {
      let counter = CallCounter()
      mock.reconstructHistoryHandler = { segs, text in
        counter.increment()
        #expect(text == kKey)
        segs.assign(from: mockResult)
        return true
      }
      return counter
    }

    // With revision
    do {
      let mockConverter = MockConverter()
      let converter = EngineConverter(mockConverter, f.request, f.config)

      let counter = expectReconstruct(mockConverter)

      var context = Genmai_Commands_Context()
      context.revision = 0
      context.precedingText = kKey
      // History segments should be reconstructed by this call.
      converter.onStartComposition(context)
      #expect(equalsSegments(F.getSegments(converter), mockResult) == nil)

      // Increment the revision. Since the history segments for kKey was already
      // constructed, ReconstructHistory should not be called.
      context.revision = 1
      context.precedingText = kKey
      converter.onStartComposition(context)
      #expect(counter.count == 1)
    }

    // Without revision
    do {
      let mockConverter = MockConverter()
      let converter = EngineConverter(mockConverter, f.request, f.config)

      let counter = expectReconstruct(mockConverter)

      var context = Genmai_Commands_Context()
      context.precedingText = kKey
      converter.onStartComposition(context)
      // History segments should be reconstructed by this call.
      converter.onStartComposition(context)
      #expect(equalsSegments(F.getSegments(converter), mockResult) == nil)

      // Revision is not present but, since the history segments for kKey was
      // already constructed, ReconstructHistory should not be called.
      context.precedingText = kKey
      converter.onStartComposition(context)
      #expect(counter.count == 1)
    }
  }

  // Test whether Request::candidate_page_size is correctly propagated to
  // CandidateList.page_size in EngineConverter.  The tests for the behavior
  // of CandidateList.page_size is in session/internal/candidate_list_test.cc
  @Test func candidatePageSize() {
    let f = F()
    let kPageSize = 3
    f.request.candidatePageSize = Int32(kPageSize)
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    #expect(F.getCandidateList(converter).pageSize == kPageSize)
  }

  // Test output.result.tokens is filled on commit.
  @Test func resultTokens() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let segments = Segments()
    do {
      let segment = segments.addSegment()
      segment.setKey("きょうは")
      let candidate = segment.addCandidate()
      candidate.key = "きょうは"
      candidate.value = "今日は"
      candidate.contentKey = "きょう"
      candidate.contentValue = "今日"
      candidate.lid = 100
      candidate.rid = 101
    }
    do {
      let segment = segments.addSegment()
      segment.setKey("はれ")
      let candidate = segment.addCandidate()
      candidate.key = "はれ"
      candidate.value = "晴れ"
      candidate.contentKey = candidate.key
      candidate.contentValue = candidate.value
      candidate.lid = 200
      candidate.rid = 201
    }
    expectStartConversion(mockConverter, segments)

    f.composer.insertCharacterPreedit("きょうははれ")
    #expect(converter.convert(f.composer))
    try? #require(converter.isActive())

    var output = Genmai_Commands_Output()
    converter.commit(f.composer, Genmai_Commands_Context())
    converter.fillOutput(f.composer, &output)

    #expect(output.hasResult)
    #expect(output.result.tokens.count == 3)
    guard output.result.tokens.count == 3 else { return }
    #expect(output.result.tokens[0].key == "きょう")
    #expect(output.result.tokens[0].value == "今日")
    #expect(output.result.tokens[0].lid == 100)
    #expect(output.result.tokens[0].rid == -1)

    #expect(output.result.tokens[1].key == "は")
    #expect(output.result.tokens[1].value == "は")
    #expect(output.result.tokens[1].lid == -1)
    #expect(output.result.tokens[1].rid == 101)

    #expect(output.result.tokens[2].key == "はれ")
    #expect(output.result.tokens[2].value == "晴れ")
    #expect(output.result.tokens[2].lid == 200)
    #expect(output.result.tokens[2].rid == 201)
  }

  @Test func resultTokensWithInnerSegements() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let segments = Segments()
    do {
      let segment = segments.addSegment()
      segment.setKey("きょうははれ")
      let candidate = segment.addCandidate()
      candidate.key = "きょうははれ"
      candidate.value = "今日は晴れ"
      candidate.contentKey = "きょうははれ"
      candidate.contentValue = "今日は晴れ"
      candidate.lid = 100
      candidate.rid = 201
      candidate.innerSegmentBoundary = buildInnerSegmentBoundary(
        [
          // len("きょうは"), len("今日"), len("きょう"), len("今日")
          (12, 9, 9, 6),
          // len("はれ"), len("晴れ"), len("はれ"), len("晴れ")
          (6, 6, 6, 6),
        ], candidate.key, candidate.value)
    }
    expectStartConversion(mockConverter, segments)

    f.composer.insertCharacterPreedit("きょうははれ")
    #expect(converter.convert(f.composer))
    try? #require(converter.isActive())

    var output = Genmai_Commands_Output()
    converter.commit(f.composer, Genmai_Commands_Context())
    converter.fillOutput(f.composer, &output)

    #expect(output.hasResult)
    #expect(output.result.tokens.count == 3)
    guard output.result.tokens.count == 3 else { return }
    #expect(output.result.tokens[0].key == "きょう")
    #expect(output.result.tokens[0].value == "今日")
    #expect(output.result.tokens[0].lid == 100)
    #expect(output.result.tokens[0].rid == -1)

    #expect(output.result.tokens[1].key == "は")
    #expect(output.result.tokens[1].value == "は")
    #expect(output.result.tokens[1].lid == -1)
    #expect(output.result.tokens[1].rid == -1)

    #expect(output.result.tokens[2].key == "はれ")
    #expect(output.result.tokens[2].value == "晴れ")
    #expect(output.result.tokens[2].lid == -1)
    #expect(output.result.tokens[2].rid == 201)
  }

  @Test func commitContext() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let counter = CallCounter()
    mockConverter.commitContextHandler = { _ in counter.increment() }
    converter.commitContext(f.composer, Genmai_Commands_Context())
    #expect(counter.count == 1)
  }

  @Test func convertWithContext() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    var context = Genmai_Commands_Context()
    context.precedingText = "left_context"
    context.followingText = "right_context"

    let counter = CallCounter()
    mockConverter.startConversionHandler = { req, segments in
      counter.increment()
      #expect(req.context().precedingText == "left_context")
      #expect(req.context().followingText == "right_context")
      F.setAiueo(segments)
      return true
    }

    f.composer.insertCharacterPreedit(kCharsAiueo)
    #expect(converter.convert(f.composer, context))
    #expect(counter.count == 1)
  }

  @Test func predictWithContext() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    var context = Genmai_Commands_Context()
    context.precedingText = "left_context"
    context.followingText = "right_context"

    let counter = CallCounter()
    mockConverter.startPredictionWithPreviousSuggestionHandler = { req, _, segments in
      counter.increment()
      #expect(req.context().precedingText == "left_context")
      #expect(req.context().followingText == "right_context")
      F.setAiueo(segments)
      return true
    }

    f.composer.insertCharacterPreedit(kCharsAiueo)
    #expect(converter.predict(f.composer, context))
    #expect(counter.count == 1)
  }

  @Test func fullSentenceCandidateInConversion() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let segments = Segments()
    do {
      let seg0 = addSegment(segments, "わたしは")
      _ = addCandidate(seg0, value: "私", key: "わたし", contentKey: "わたし")
      let cand1 = addCandidate(
        seg0, value: "私は", key: "わたしは", contentKey: "わたしは", convertedSegmentCount: 2)
      cand1.lid = 10
      cand1.rid = 20

      let seg1 = addSegment(segments, "は")
      _ = addCandidate(seg1, value: "は", key: "は", contentKey: "は")
    }

    expectStartConversion(mockConverter, segments)

    f.composer.insertCharacterPreedit("わたしは")
    #expect(converter.convert(f.composer))
    try? #require(converter.isActive())

    // Default: candidate 0 is focused -> 2 segments rendered
    do {
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(output.hasPreedit)
      #expect(output.preedit.segment.count == 2)
      if output.preedit.segment.count == 2 {
        #expect(output.preedit.segment[0].value == "私")
        #expect(output.preedit.segment[1].value == "は")
      }
    }

    // Move candidate to candidate 1 (FULL_SENTENCE)
    let focus = expectFocusSegmentValue(mockConverter, 0, 1)
    converter.candidateNext(f.composer)
    #expect(focus.count == 1)

    // Now candidate 1 is focused -> 1 segment rendered for the full sentence
    do {
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(output.hasPreedit)
      #expect(output.preedit.segment.count == 1)
      if output.preedit.segment.count == 1 {
        #expect(output.preedit.segment[0].value == "私は")
      }
    }

    // Commit the conversion with candidate 1 (FULL_SENTENCE)
    let commitValue = expectCommitSegmentValue(mockConverter, 0, 1)
    let finish = expectFinishConversion(mockConverter)

    var output = Genmai_Commands_Output()
    converter.commit(f.composer, Genmai_Commands_Context())
    converter.fillOutput(f.composer, &output)
    #expect(commitValue.count == 1)
    #expect(finish.count == 1)

    #expect(output.hasResult)
    #expect(output.result.value == "私は")
    #expect(output.result.key == "わたしは")
  }

  @Test func multiSegmentCandidateAtNonZeroIndex() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let segments = Segments()
    do {
      let seg0 = addSegment(segments, "きょう")
      _ = addCandidate(seg0, value: "今日", key: "きょう", contentKey: "きょう")

      let seg1 = addSegment(segments, "はいい")
      _ = addCandidate(seg1, value: "は", key: "は", contentKey: "は")
      _ = addCandidate(
        seg1, value: "は良い", key: "はいい", contentKey: "はいい", convertedSegmentCount: 2)

      let seg2 = addSegment(segments, "いい")
      _ = addCandidate(seg2, value: "良い", key: "いい", contentKey: "いい")
    }

    expectStartConversion(mockConverter, segments)

    f.composer.insertCharacterPreedit("きょうはいい")
    #expect(converter.convert(f.composer))
    try? #require(converter.isActive())

    // Focus segment 1
    let commitValue = expectCommitSegmentValue(mockConverter, 0, 0)
    converter.segmentFocusRight()
    #expect(commitValue.count == 1)

    // Select candidate 1 on segment 1 (converted_segment_count = 2)
    let focus = expectFocusSegmentValue(mockConverter, 1, 1)
    converter.candidateNext(f.composer)
    #expect(focus.count == 1)

    // Preedit should show 2 segments: seg 0 ("今日", unfocused) and seg 1
    // ("は良い", focused)
    do {
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(output.hasPreedit)
      #expect(output.preedit.segment.count == 2)
      if output.preedit.segment.count == 2 {
        #expect(output.preedit.segment[0].value == "今日")
        #expect(output.preedit.segment[1].value == "は良い")
      }
    }
  }

  /// Segments shared by several multi-segment tests:
  /// わたしの [私の | 私の名前は(2)] / なまえは [名前は] / なかのです [中野です]
  private func makeWatashinoSegments() -> Segments {
    let segments = Segments()
    let seg0 = addSegment(segments, "わたしの")
    _ = addCandidate(seg0, value: "私の", key: "わたしの", contentKey: "わたしの")
    _ = addCandidate(
      seg0, value: "私の名前は", key: "わたしのなまえは", contentKey: "わたしのなまえは",
      convertedSegmentCount: 2)

    let seg1 = addSegment(segments, "なまえは")
    _ = addCandidate(seg1, value: "名前は", key: "なまえは", contentKey: "なまえは")

    let seg2 = addSegment(segments, "なかのです")
    _ = addCandidate(seg2, value: "中野です", key: "なかのです", contentKey: "なかのです")
    return segments
  }

  @Test func resizeMultiSegmentCandidateWidth() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let segments = makeWatashinoSegments()

    expectStartConversion(mockConverter, segments)

    f.composer.insertCharacterPreedit("わたしのなまえはなかのです")
    #expect(converter.convert(f.composer))
    try? #require(converter.isActive())

    // Select candidate 1 on segment 0 ("私の名前は", key length = 8)
    let focus = expectFocusSegmentValue(mockConverter, 0, 1)
    converter.candidateNext(f.composer)
    #expect(focus.count == 1)

    // Shrink segment width by 1.
    // Original segment 0 has key_len = 4, but selected candidate has key_len = 8.
    // Target key length is 8 - 1 = 7, so offset_length should be 7 - 4 = 3.
    let resize = expectResizeSegment(mockConverter, 0, 3)
    converter.segmentWidthShrink(f.composer)
    #expect(resize.count == 1)
  }

  @Test func focusRightAfterMultiSegmentCandidateSelection() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let segments = makeWatashinoSegments()

    expectStartConversion(mockConverter, segments)

    f.composer.insertCharacterPreedit("わたしのなまえはなかのです")
    #expect(converter.convert(f.composer))
    try? #require(converter.isActive())

    // Select candidate 1 on segment 0 ("私の名前は", converted_segment_count = 2)
    let focus = expectFocusSegmentValue(mockConverter, 0, 1)
    converter.candidateNext(f.composer)
    #expect(focus.count == 1)

    // Focus right. SegmentFix commits segment 0 candidate 1.
    let commitValue = expectCommitSegmentValue(mockConverter, 0, 1)
    converter.segmentFocusRight()
    #expect(commitValue.count == 1)

    // The focused segment should now be "なかのです" (index 2 in the 3-segment
    // list when converter mock does not resize segments). Shrinking this segment
    // should invoke ResizeSegment on index 2 with offset -1.
    let resize = expectResizeSegment(mockConverter, 2, -1)
    converter.segmentWidthShrink(f.composer)
    #expect(resize.count == 1)
  }

  @Test func focusLeftAfterMultiSegmentCandidateSelection() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let segments = makeWatashinoSegments()

    expectStartConversion(mockConverter, segments)

    f.composer.insertCharacterPreedit("わたしのなまえはなかのです")
    #expect(converter.convert(f.composer))
    try? #require(converter.isActive())

    // Select candidate 1 on segment 0 ("私の名前は", converted_segment_count = 2)
    var focus = expectFocusSegmentValue(mockConverter, 0, 1)
    converter.candidateNext(f.composer)
    #expect(focus.count == 1)

    // Focus right -> moves to "中野です" (index 2).
    // CommitSegmentValue moves candidate to position 0 without erasing segments.
    var commitValue = expectCommitSegmentValue(mockConverter, 0, 1) { segs, _, candIdx in
      segs.mutableConversionSegment(0).setSegmentType(.fixedValue)
      segs.mutableConversionSegment(0).moveCandidate(candIdx, 0)
      return true
    }
    converter.segmentFocusRight()
    #expect(commitValue.count == 1)
    #expect(F.getSegmentIndex(converter) == 2)

    // Focus left -> moves back to "私の名前は" (index 0) because
    // GetSegmentSpan(0) == 2.
    commitValue = expectCommitSegmentValue(mockConverter, 2, 0)
    converter.segmentFocusLeft()
    #expect(commitValue.count == 1)
    #expect(F.getSegmentIndex(converter) == 0)

    // Check preedit with "私の名前は" selected: [私の名前は] 中野です
    do {
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(output.hasPreedit)
      #expect(output.preedit.segment.count == 2)
      if output.preedit.segment.count == 2 {
        #expect(output.preedit.segment[0].value == "私の名前は")
        #expect(output.preedit.segment[1].value == "中野です")
      }
    }

    // Change candidate on segment 0 back to single-segment candidate "私の"
    // (index 1 after move).
    focus = expectFocusSegmentValue(mockConverter, 0, 1)
    converter.candidateNext(f.composer)
    #expect(focus.count == 1)

    // Preedit should now restore "名前は": [私の] 名前は 中野です
    do {
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(output.hasPreedit)
      #expect(output.preedit.segment.count == 3)
      if output.preedit.segment.count == 3 {
        #expect(output.preedit.segment[0].value == "私の")
        #expect(output.preedit.segment[1].value == "名前は")
        #expect(output.preedit.segment[2].value == "中野です")
      }
    }
  }

  @Test func focusNavigationWithSpan3Candidate() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let segments = Segments()
    do {
      let seg0 = addSegment(segments, "とうきょう")
      _ = addCandidate(seg0, value: "東京", key: "とうきょう")
      _ = addCandidate(
        seg0, value: "東京都渋谷区", key: "とうきょうとしぶやく", convertedSegmentCount: 3)

      let seg1 = addSegment(segments, "と")
      _ = addCandidate(seg1, value: "都", key: "と")

      let seg2 = addSegment(segments, "しぶやく")
      _ = addCandidate(seg2, value: "渋谷区", key: "しぶやく")

      let seg3 = addSegment(segments, "に")
      _ = addCandidate(seg3, value: "に", key: "に")
    }

    expectStartConversion(mockConverter, segments)

    f.composer.insertCharacterPreedit("とうきょうとしぶやくに")
    #expect(converter.convert(f.composer))
    try? #require(converter.isActive())

    // Select candidate 1 on segment 0 ("東京都渋谷区", converted_segment_count =
    // 3)
    var focus = expectFocusSegmentValue(mockConverter, 0, 1)
    converter.candidateNext(f.composer)
    #expect(focus.count == 1)

    // Focus right -> moves to "に" (index 3).
    var commitValue = expectCommitSegmentValue(mockConverter, 0, 1) { segs, _, candIdx in
      segs.mutableConversionSegment(0).setSegmentType(.fixedValue)
      segs.mutableConversionSegment(0).moveCandidate(candIdx, 0)
      return true
    }
    converter.segmentFocusRight()
    #expect(commitValue.count == 1)
    #expect(F.getSegmentIndex(converter) == 3)

    // Focus left -> moves back to "東京都渋谷区" (index 0) because
    // GetSegmentSpan(0) == 3.
    commitValue = expectCommitSegmentValue(mockConverter, 3, 0)
    converter.segmentFocusLeft()
    #expect(commitValue.count == 1)
    #expect(F.getSegmentIndex(converter) == 0)

    // Check preedit: [東京都渋谷区] に
    do {
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(output.hasPreedit)
      #expect(output.preedit.segment.count == 2)
      if output.preedit.segment.count == 2 {
        #expect(output.preedit.segment[0].value == "東京都渋谷区")
        #expect(output.preedit.segment[1].value == "に")
      }
    }

    // Change back to single-segment candidate "東京" (index 1 after move).
    focus = expectFocusSegmentValue(mockConverter, 0, 1)
    converter.candidateNext(f.composer)
    #expect(focus.count == 1)

    // Preedit should restore all segments: [東京] 都 渋谷区 に
    do {
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(output.hasPreedit)
      #expect(output.preedit.segment.count == 4)
      if output.preedit.segment.count == 4 {
        #expect(output.preedit.segment[0].value == "東京")
        #expect(output.preedit.segment[1].value == "都")
        #expect(output.preedit.segment[2].value == "渋谷区")
        #expect(output.preedit.segment[3].value == "に")
      }
    }
  }

  @Test func focusNavigationWithMiddleSegmentMultiSegmentCandidate() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let segments = Segments()
    do {
      let seg0 = addSegment(segments, "きょうは")
      _ = addCandidate(seg0, value: "今日は", key: "きょうは")

      let seg1 = addSegment(segments, "いい")
      _ = addCandidate(seg1, value: "良い", key: "いい")
      _ = addCandidate(seg1, value: "いい天気", key: "いいてんき", convertedSegmentCount: 2)

      let seg2 = addSegment(segments, "てんき")
      _ = addCandidate(seg2, value: "天気", key: "てんき")

      let seg3 = addSegment(segments, "ですね")
      _ = addCandidate(seg3, value: "ですね", key: "ですね")
    }

    expectStartConversion(mockConverter, segments)

    f.composer.insertCharacterPreedit("きょうはいいてんきですね")
    #expect(converter.convert(f.composer))
    try? #require(converter.isActive())

    // Focus right from seg 0 to seg 1.
    var commitValue = expectCommitSegmentValue(mockConverter, 0, 0)
    converter.segmentFocusRight()
    #expect(commitValue.count == 1)
    #expect(F.getSegmentIndex(converter) == 1)

    // Select candidate 1 on segment 1 ("いい天気", converted_segment_count = 2)
    var focus = expectFocusSegmentValue(mockConverter, 1, 1)
    converter.candidateNext(f.composer)
    #expect(focus.count == 1)

    // Focus right -> moves to "ですね" (index 3).
    commitValue = expectCommitSegmentValue(mockConverter, 1, 1) { segs, _, candIdx in
      segs.mutableConversionSegment(1).setSegmentType(.fixedValue)
      segs.mutableConversionSegment(1).moveCandidate(candIdx, 0)
      return true
    }
    converter.segmentFocusRight()
    #expect(commitValue.count == 1)
    #expect(F.getSegmentIndex(converter) == 3)

    // Focus left -> moves back to "いい天気" (index 1) because GetSegmentSpan(1)
    // == 2.
    commitValue = expectCommitSegmentValue(mockConverter, 3, 0)
    converter.segmentFocusLeft()
    #expect(commitValue.count == 1)
    #expect(F.getSegmentIndex(converter) == 1)

    // Check preedit: 今日は [いい天気] ですね
    do {
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(output.hasPreedit)
      #expect(output.preedit.segment.count == 3)
      if output.preedit.segment.count == 3 {
        #expect(output.preedit.segment[0].value == "今日は")
        #expect(output.preedit.segment[1].value == "いい天気")
        #expect(output.preedit.segment[2].value == "ですね")
      }
    }

    // Change back to single-segment candidate "良い" (index 1 after move).
    focus = expectFocusSegmentValue(mockConverter, 1, 1)
    converter.candidateNext(f.composer)
    #expect(focus.count == 1)

    // Preedit should restore segment 2: 今日は [良い] 天気 ですね
    do {
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(output.hasPreedit)
      #expect(output.preedit.segment.count == 4)
      if output.preedit.segment.count == 4 {
        #expect(output.preedit.segment[0].value == "今日は")
        #expect(output.preedit.segment[1].value == "良い")
        #expect(output.preedit.segment[2].value == "天気")
        #expect(output.preedit.segment[3].value == "ですね")
      }
    }
  }

  @Test func commit_FullSentenceCandidate() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let segments = Segments()
    let seg0 = addSegment(segments, "わたしは")
    _ = addCandidate(
      seg0, value: "私は中野です", key: "わたしはなかのです", convertedSegmentCount: 2)

    let seg1 = addSegment(segments, "なかのです")
    _ = addCandidate(seg1, value: "中野です", key: "なかのです")

    f.composer.insertCharacterPreedit("わたしはなかのです")
    expectStartConversion(mockConverter, segments)

    #expect(converter.convert(f.composer))

    // Commit with full-sentence candidate selected on segment 0 (L1441).
    let commitValue = expectCommitSegmentValue(mockConverter, 0, 0)
    let finish = expectFinishConversion(mockConverter)
    converter.commit(f.composer, Genmai_Commands_Context())
    var output = Genmai_Commands_Output()
    converter.fillOutput(f.composer, &output)
    #expect(commitValue.count == 1)
    #expect(finish.count == 1)
    #expect(output.hasResult)
    #expect(output.result.value == "私は中野です")
  }

  @Test func getSegmentSpan_TruncatedWhenFocusIsInsideSpan() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let segments = Segments()
    let seg0 = addSegment(segments, "きょうは")
    _ = addCandidate(seg0, value: "今日は", key: "きょうは", convertedSegmentCount: 1)

    let seg1 = addSegment(segments, "いいてんき")
    _ = addCandidate(seg1, value: "いい天気", key: "いいてんき", convertedSegmentCount: 2)

    let seg2 = addSegment(segments, "ですね")
    _ = addCandidate(seg2, value: "ですね", key: "ですね", convertedSegmentCount: 1)

    f.composer.insertCharacterPreedit("きょうはいいてんきですね")
    expectStartConversion(mockConverter, segments)

    #expect(converter.convert(f.composer))

    // Initially focus is at seg0.
    #expect(F.getSegmentIndex(converter) == 0)
    #expect(F.getSegmentSpan(converter, 0) == 1)
    #expect(F.getSegmentSpan(converter, 1) == 2)
    #expect(F.getSegmentSpan(converter, 2) == 1)

    // Focus right from seg0 to seg1, modifying seg0's candidate count to 2.
    let commitValue = expectCommitSegmentValue(mockConverter, 0, 0) { segs, _, _ in
      segs.mutableConversionSegment(0).mutableCandidate(0).convertedSegmentCount = 2
      return true
    }
    converter.segmentFocusRight()
    #expect(commitValue.count == 1)
    #expect(F.getSegmentIndex(converter) == 1)

    // When segment_index_ is 1, GetSegmentSpan(0) has current_index(0) <
    // focused_index(1) and 0 + 2 > 1, so span is truncated to 1 - 0 = 1 (L1633).
    #expect(F.getSegmentSpan(converter, 0) == 1)
    // GetSegmentSpan for current and later segments should return their normal
    // counts.
    #expect(F.getSegmentSpan(converter, 1) == 2)
    #expect(F.getSegmentSpan(converter, 2) == 1)

    var output = Genmai_Commands_Output()
    converter.fillOutput(f.composer, &output)
    #expect(output.hasPreedit)
    try? #require(output.preedit.segment.count == 2)
    guard output.preedit.segment.count == 2 else { return }
    #expect(output.preedit.segment[0].value == "今日は")
    #expect(output.preedit.segment[1].value == "いい天気")
    #expect(output.preedit.segment[1].annotation == .highlight)
  }

  @Test func getPreeditWithMultiSegmentCandidateKey() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let segments = Segments()
    let seg0 = addSegment(segments, "わたし")
    _ = addCandidate(
      seg0, value: "私の名前は", key: "わたしのなまえは", convertedSegmentCount: 2)

    let seg1 = addSegment(segments, "のなまえは")
    _ = addCandidate(seg1, value: "の名前は", key: "のなまえは")

    let seg2 = addSegment(segments, "なかのです")
    _ = addCandidate(seg2, value: "中野です", key: "なかのです", convertedSegmentCount: 1)

    expectStartConversion(mockConverter, segments)

    f.composer.insertCharacterPreedit("わたしのなまえはなかのです")
    #expect(converter.convert(f.composer))

    // Multi-segment candidate on segment 0 (span = 2) + single segment 2:
    var preedit = F.getPreedit(converter, 0, 3)
    #expect(preedit == "わたしのなまえはなかのです")

    // Partial ranges:
    preedit = F.getPreedit(converter, 0, 2)
    #expect(preedit == "わたしのなまえは")

    preedit = F.getPreedit(converter, 2, 1)
    #expect(preedit == "なかのです")
  }

  @Test func getPreedit_FallbackWhenCandidateKeyIsEmpty() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let segments = Segments()
    let seg0 = addSegment(segments, "わたしは")
    // Empty candidate key with converted_segment_count = 2.
    _ = addCandidate(seg0, value: "私は", key: "", convertedSegmentCount: 2)

    let seg1 = addSegment(segments, "なかのです")
    _ = addCandidate(seg1, value: "中野です", key: "なかのです", convertedSegmentCount: 1)

    expectStartConversion(mockConverter, segments)

    f.composer.insertCharacterPreedit("わたしはなかのです")
    #expect(converter.convert(f.composer))

    // When cand0->key is empty on a 2-span candidate, it falls back to
    // segment(0).key() ("わたしは") and advances span (2), so only "わたしは"
    // is returned for range [0, 2).
    let preedit = F.getPreedit(converter, 0, 2)
    #expect(preedit == "わたしは")
  }

  @Test func isFullSentenceCandidateSelected() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let segments = Segments()
    let seg0 = addSegment(segments, "わたしは")
    _ = addCandidate(
      seg0, value: "私は中野です", key: "わたしはなかのです", convertedSegmentCount: 3)
    _ = addCandidate(
      seg0, value: "私の名前は", key: "わたしのなまえは", convertedSegmentCount: 2)
    _ = addCandidate(seg0, value: "私は", key: "わたしは", convertedSegmentCount: 1)

    let seg1 = addSegment(segments, "なか")
    _ = addCandidate(seg1, value: "中", key: "なか")

    let seg2 = addSegment(segments, "のです")
    _ = addCandidate(seg2, value: "野です", key: "のです")

    f.composer.insertCharacterPreedit("わたしはなかのです")
    expectStartConversion(mockConverter, segments)

    #expect(converter.convert(f.composer))

    // 1. Full-sentence candidate covering all 3 segments (cand0, count = 3 >= 3).
    #expect(F.isFullSentenceCandidateSelected(converter))

    // 2. Partial multi-segment candidate (cand1, count = 2 < 3): returns false.
    var focus = expectFocusSegmentValue(mockConverter, 0, 1)
    converter.candidateNext(f.composer)
    #expect(focus.count == 1)
    #expect(!F.isFullSentenceCandidateSelected(converter))

    // 3. Single-segment candidate (cand2, count = 1 < 3): returns false.
    focus = expectFocusSegmentValue(mockConverter, 0, 2)
    converter.candidateNext(f.composer)
    #expect(focus.count == 1)
    #expect(!F.isFullSentenceCandidateSelected(converter))

    // 4. Focus right to segment 1. Now segment_index_ != 0, so returns false.
    let commitValue = expectCommitSegmentValue(mockConverter, 0, 2)
    converter.segmentFocusRight()
    #expect(commitValue.count == 1)
    #expect(F.getSegmentIndex(converter) == 1)
    #expect(!F.isFullSentenceCandidateSelected(converter))
  }

  @Test func commitFirstSegmentFullSentenceCandidate() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let segments = Segments()
    let seg0 = addSegment(segments, "きょうは")
    _ = addCandidate(
      seg0, value: "今日は良い天気ですね", key: "きょうはいいてんきですね", convertedSegmentCount: 2)

    let seg1 = addSegment(segments, "いいてんきですね")
    _ = addCandidate(seg1, value: "良い天気ですね", key: "いいてんきですね")

    expectStartConversion(mockConverter, segments)

    f.composer.insertCharacterPreedit("きょうはいいてんきですね")
    #expect(converter.convert(f.composer))

    // When full-sentence candidate is selected at segment 0, CommitFirstSegment
    // should commit all segments at once via Commit().
    let commitValue = expectCommitSegmentValue(mockConverter, 0, 0)
    let finish = expectFinishConversion(mockConverter)

    let context = Genmai_Commands_Context()
    var consumedKeySize = 12345
    converter.commitFirstSegment(f.composer, context, &consumedKeySize)
    #expect(commitValue.count == 1)
    #expect(finish.count == 1)
    #expect(!converter.isActive())
    #expect(consumedKeySize == 0)
  }

  @Test func commitFirstSegmentSingleSegmentCandidate() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let segments = Segments()
    let seg0 = addSegment(segments, "きょうは")
    _ = addCandidate(seg0, value: "今日は", key: "きょうは", convertedSegmentCount: 1)

    let seg1 = addSegment(segments, "いいてんきですね")
    _ = addCandidate(seg1, value: "良い天気ですね", key: "いいてんきですね")

    expectStartConversion(mockConverter, segments)

    f.composer.insertCharacterPreedit("きょうはいいてんきですね")
    #expect(converter.convert(f.composer))

    // Single-segment candidate at segment 0 commits only the first segment.
    let commitSegments = CallCounter()
    mockConverter.commitSegmentsHandler = { _, _ in
      commitSegments.increment()
      return true
    }

    let context = Genmai_Commands_Context()
    var consumedKeySize = 0
    converter.commitFirstSegment(f.composer, context, &consumedKeySize)
    #expect(commitSegments.count == 1)
    #expect(converter.isActive())
    #expect(consumedKeySize == Util.charsLen("きょうは"))
  }

  /// ここでは [ここで履物を(2)] / きものを [着物を] / ぬぐ [脱ぐ]; with an
  /// optional single-segment first candidate.
  private func makeKokodewaSegments(withSingleFirst: Bool) -> Segments {
    let segments = Segments()
    let seg0 = addSegment(segments, "ここでは")
    if withSingleFirst {
      _ = addCandidate(seg0, value: "ここでは", key: "ここでは")
    }
    _ = addCandidate(
      seg0, value: "ここで履物を", key: "ここではきものを", convertedSegmentCount: 2)

    let seg1 = addSegment(segments, "きものを")
    _ = addCandidate(seg1, value: "着物を", key: "きものを")

    let seg2 = addSegment(segments, "ぬぐ")
    _ = addCandidate(seg2, value: "脱ぐ", key: "ぬぐ")
    return segments
  }

  /// EXPECT_CALL(CommitSegments(_, ElementsAre(expectedId))).WillOnce(...)
  private func expectCommitSegments(_ mock: MockConverter, _ expectedIds: [Int]) -> CallCounter {
    let counter = CallCounter()
    mock.commitSegmentsHandler = { segs, ids in
      counter.increment()
      #expect(ids == expectedIds)
      segs.mutableConversionSegment(0).setSegmentType(.submitted)
      segs.eraseSegments(segs.historySegmentsSize, 1)
      return true
    }
    return counter
  }

  @Test func commitFirstSegmentPartialMultiSegmentCandidate() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let segments = makeKokodewaSegments(withSingleFirst: false)

    expectStartConversion(mockConverter, segments)

    f.composer.insertCharacterPreedit("ここではきものをぬぐ")
    #expect(converter.convert(f.composer))

    let commitSegments = expectCommitSegments(mockConverter, [0])

    let context = Genmai_Commands_Context()
    var consumedKeySize = 0
    converter.commitFirstSegment(f.composer, context, &consumedKeySize)
    #expect(commitSegments.count == 1)
    #expect(converter.isActive())
    #expect(consumedKeySize == Util.charsLen("ここではきものを"))

    var output = Genmai_Commands_Output()
    converter.fillOutput(f.composer, &output)
    #expect(output.result.value == "ここで履物を")
    #expect(output.result.key == "ここではきものを")
  }

  @Test func commitHeadToFocusedSegmentsMultiSegmentCandidate() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let segments = makeKokodewaSegments(withSingleFirst: true)

    expectStartConversion(mockConverter, segments)

    f.composer.insertCharacterPreedit("ここではきものをぬぐ")
    #expect(converter.convert(f.composer))
    converter.candidateMoveToId(1, f.composer)

    let commitSegments = expectCommitSegments(mockConverter, [1])

    let context = Genmai_Commands_Context()
    var consumedKeySize = 0
    converter.commitHeadToFocusedSegments(f.composer, context, &consumedKeySize)
    #expect(commitSegments.count == 1)
    #expect(converter.isActive())
    #expect(consumedKeySize == Util.charsLen("ここではきものを"))

    var output = Genmai_Commands_Output()
    converter.fillOutput(f.composer, &output)
    #expect(output.result.value == "ここで履物を")
    #expect(output.result.key == "ここではきものを")
  }
}
