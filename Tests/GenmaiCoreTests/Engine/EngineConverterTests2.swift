// Port of mozc/src/engine/engine_converter_test.cc (3.35.6354), part 2.
//
// TEST_F(EngineConverterTest, PartialPrediction) through
// TEST(EngineConverterRevertTest, Revert).
//
// gMock translation notes:
// - `Mock::VerifyAndClearExpectations(&mock_converter)` in the C++ test is
//   passed the address of the shared_ptr (not the mock), so it neither
//   verifies nor clears anything; expectations stay alive and newer ones take
//   precedence. The Swift port replaces the handler at each EXPECT_CALL and
//   checks the WillOnce call counts at the end of the test.
// - Argument matchers are `#expect`s inside the handlers.

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private typealias F = EngineConverterTestFixture
private typealias S = EngineConverterState

struct EngineConverterTests2 {
  @Test func partialPrediction() {
    let f = F()
    RequestTestUtil.fillMobileRequest(&f.request)
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    let segments1 = Segments()
    let segments2 = Segments()
    let suggestionSegments = Segments()
    let kChars_Kokode = "ここで"
    let kChars_Hakimonowo = "はきものを"

    do {  // Initialize mock segments for partial prediction
      let segment = segments1.addSegment()
      segment.setKey(kChars_Kokode)
      let candidate = segment.addCandidate()
      candidate.value = "此処では"
      candidate.key = kChars_Kokode
      candidate.contentKey = kChars_Kokode
      candidate.attributes = Attribute.partiallyKeyConsumed
      candidate.consumedKeySize = UInt32(Util.charsLen(kChars_Kokode))
    }

    // Suggestion that matches to the same key by its prefix.
    // Should not be used by partial prediction.
    do {
      let segment = suggestionSegments.addSegment()
      segment.setKey(kChars_Kokode)
      let candidate = segment.addCandidate()
      candidate.value = "ここでは着物を"
      candidate.key = "ここではきものを"
      candidate.contentKey = candidate.key
      _ = segment.addCandidate()
    }

    do {  // Initialize mock segments for prediction
      let segment = segments2.addSegment()
      segment.setKey(kChars_Hakimonowo)
      let candidate = segment.addCandidate()
      candidate.value = "此処では"
      candidate.key = kChars_Hakimonowo
      candidate.contentKey = kChars_Hakimonowo
    }

    // "ここではきものを|"    ("|" is cursor position)
    f.composer.insertCharacterPreedit(kChars_Kokode + kChars_Hakimonowo)
    f.composer.moveCursorToEnd()
    // Prediction for "ここではきものを".
    let predictionCount1 = CallCounter()
    mockConverter.startPredictionHandler = { _, out in
      predictionCount1.increment()
      out.assign(from: suggestionSegments)
      return true
    }
    #expect(converter.suggest(f.composer, Genmai_Commands_Context()))
    #expect(predictionCount1.count == 1)
    let expectedIndices = [0]
    #expect(F.isCandidateListVisible(converter))
    #expect(converter.isActive())
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    // "|ここではきものを"    ("|" is cursor position)
    f.composer.moveCursorTo(0)

    // Prediction for "ここではきものを".
    let predictionCount2 = CallCounter()
    mockConverter.startPredictionHandler = { _, out in
      predictionCount2.increment()
      out.assign(from: suggestionSegments)
      return true
    }
    #expect(converter.suggest(f.composer, Genmai_Commands_Context()))
    #expect(predictionCount2.count == 1)
    #expect(F.isCandidateListVisible(converter))
    #expect(converter.isActive())
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    // "ここで|はきものを"    ("|" is cursor position)
    f.composer.moveCursorTo(3)

    // Partial prediction for "ここで"
    let predictionCount3 = CallCounter()
    mockConverter.startPredictionHandler = { _, out in
      predictionCount3.increment()
      out.assign(from: segments1)
      return true
    }
    #expect(converter.suggest(f.composer, Genmai_Commands_Context()))
    #expect(predictionCount3.count == 1)
    #expect(F.isCandidateListVisible(converter))
    #expect(converter.isActive())
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    // commit partial suggestion
    var committedKeySize = 0
    let partialCount = CallCounter()
    mockConverter.commitPartialSuggestionSegmentValueHandler = { out, _, _, _, _ in
      partialCount.increment()
      out.assign(from: segments2)
      return true
    }
    _ = converter.commitSuggestionById(0, f.composer, Genmai_Commands_Context(), &committedKeySize)
    #expect(partialCount.count == 1)
    #expect(committedKeySize == Util.charsLen(kChars_Kokode))
    // Indices should be {0} since there is another segment.
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    do {  // Check the result
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(output.hasResult)

      let result = output.result
      #expect(result.value == "此処では")
      #expect(result.key == kChars_Kokode)
      #expect(F.getState(converter) == S.suggestion)
    }
  }

  @Test func suggestAndPredict() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    let suggestSegments: Segments = {
      // Initialize mock segments for suggestion
      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey(kChars_Mo)
      var candidate = segment.addCandidate()
      candidate.value = kChars_Mozukusu
      candidate.contentKey = kChars_Mozukusu
      candidate = segment.addCandidate()
      candidate.value = kChars_Momonga
      candidate.contentKey = kChars_Momonga
      return segments
    }()
    f.composer.insertCharacterPreedit(kChars_Mo)

    // Action 1. Suggest()
    // ["もずくす", "ももんが"] will be suggested.
    let predictionCount = CallCounter()
    mockConverter.startPredictionHandler = { _, out in
      predictionCount.increment()
      out.assign(from: suggestSegments)
      return true
    }
    #expect(converter.suggest(f.composer, Genmai_Commands_Context()))
    #expect(predictionCount.count == 1)

    var expectedIndices = [0]
    #expect(F.isCandidateListVisible(converter))
    #expect(converter.isActive())
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    do {  // Check the candidate list
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)
      #expect(output.candidateWindow.hasFooter)
      // CHANNEL_DEV && GOOGLE_JAPANESE_INPUT_BUILD is not defined.
      #expect(output.candidateWindow.footer.hasLabel)
      #expect(!output.candidateWindow.footer.hasSubLabel)
      #expect(!output.candidateWindow.footer.indexVisible)
      #expect(!output.candidateWindow.footer.logoVisible)

      let candidateWindow = output.candidateWindow
      #expect(candidateWindow.size == 2)
      #expect(candidateWindow.candidate[0].value == kChars_Mozukusu)
      #expect(!candidateWindow.hasFocusedIndex)
    }

    // Action 2. Predict()
    // ["もずくす", "ももんが"] will be shown as prediction.
    // "もずくす" is focused.
    //
    // Since Suggest() was called, the converter stores its results internally. In
    // this case, the prediction is not triggered.
    let previousSuggestionCount0 = CallCounter()
    mockConverter.startPredictionWithPreviousSuggestionHandler = { _, _, _ in
      previousSuggestionCount0.increment()
      return false
    }
    // b/417900855: Post processing should be called for the previous segments.
    // We have different rewriter set for prediction and suggestion.
    let prependCount = CallCounter()
    mockConverter.prependCandidatesHandler = { _, segment, out in
      prependCount.increment()
      #expect(equalsSegment(segment, suggestSegments.conversionSegment(0)) == nil)
      out.assign(from: suggestSegments)
    }
    #expect(converter.predict(f.composer))
    #expect(previousSuggestionCount0.count == 0)
    #expect(prependCount.count == 1)

    #expect(F.isCandidateListVisible(converter))
    #expect(converter.isActive())
    F.expectSelectedCandidateIndices(converter, expectedIndices)
    do {
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)
      #expect(!output.candidateWindow.footer.hasLabel)
      #expect(output.candidateWindow.footer.indexVisible)
      #expect(output.candidateWindow.footer.logoVisible)

      // Check the conversion
      let conversion = output.preedit
      #expect(conversion.segment.count == 1)
      #expect(conversion.segment[0].value == kChars_Mozukusu)

      // Check the candidate list
      let candidateWindow = output.candidateWindow
      // Candidates should be the same as suggestion
      #expect(candidateWindow.size == 2)
      #expect(candidateWindow.candidate[0].value == kChars_Mozukusu)
      #expect(candidateWindow.candidate[1].value == kChars_Momonga)
      #expect(candidateWindow.hasFocusedIndex)
      #expect(candidateWindow.focusedIndex == 0)
    }

    // Action 3. CandidateNext()
    // "ももんが" is focused.
    let focusCount1 = CallCounter()
    mockConverter.focusSegmentValueHandler = { _, segmentIndex, candidateIndex in
      focusCount1.increment()
      #expect(segmentIndex == 0)
      #expect(candidateIndex == 1)
      return true
    }
    converter.candidateNext(f.composer)
    #expect(focusCount1.count == 1)

    // Action 4. CandidateNext()
    // Prediction is expanded.
    // converter returns:
    // ["もずくす", "ももんが", "もずく", "ももんが", "モンドリアン"]
    // output is deduped:
    // ["もずくす", "ももんが", "もずく", "モンドリアン"]
    // "もずく" is focused.
    let focusCount2 = CallCounter()
    mockConverter.focusSegmentValueHandler = { _, segmentIndex, candidateIndex in
      focusCount2.increment()
      #expect(segmentIndex == 0)
      #expect(candidateIndex == 2)
      return true
    }
    let expandedSegments: Segments = {
      let segments = Segments()
      // Initialize mock segments for prediction
      let segment = segments.addSegment()
      segment.setKey(kChars_Mo)
      // From previous suggestion
      var candidate = segment.addCandidate()
      candidate.value = kChars_Mozukusu
      candidate.contentKey = kChars_Mozukusu
      candidate = segment.addCandidate()
      candidate.value = kChars_Momonga
      candidate.contentKey = kChars_Momonga
      // From prediction
      candidate = segment.addCandidate()
      candidate.value = kChars_Mozuku
      candidate.contentKey = kChars_Mozuku
      candidate = segment.addCandidate()
      candidate.value = kChars_Momonga
      candidate.contentKey = kChars_Momonga
      candidate = segment.addCandidate()
      candidate.value = "モンドリアン"
      candidate.contentKey = "もんどりあん"
      return segments
    }()
    mockConverter.startPredictionWithPreviousSuggestionHandler = { _, previous, out in
      #expect(equalsSegment(previous, suggestSegments.conversionSegment(0)) == nil)
      out.assign(from: expandedSegments)
      return true
    }
    converter.candidateNext(f.composer)
    #expect(focusCount2.count == 1)
    expectedIndices[0] += 2
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    do {
      // Check the candidate list
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)

      let candidateWindow = output.candidateWindow
      // Candidates should be merged with the previous suggestions.
      #expect(candidateWindow.size == 4)
      #expect(candidateWindow.candidate[0].value == kChars_Mozukusu)
      #expect(candidateWindow.candidate[1].value == kChars_Momonga)
      #expect(candidateWindow.candidate[2].value == kChars_Mozuku)
      #expect(candidateWindow.candidate[3].value == "モンドリアン")
      #expect(candidateWindow.hasFocusedIndex)
    }

    // Action 5. CandidateNext()
    // "モンドリアン" is focused.
    let focusCount3 = CallCounter()
    mockConverter.focusSegmentValueHandler = { _, segmentIndex, candidateIndex in
      focusCount3.increment()
      #expect(segmentIndex == 0)
      #expect(candidateIndex == 4)
      return true
    }
    converter.candidateNext(f.composer)
    #expect(focusCount3.count == 1)
    expectedIndices[0] += 1
    F.expectSelectedCandidateIndices(converter, expectedIndices)

    // Action 6. Commit()
    // Commit "モンドリアン".
    let commitCount = CallCounter()
    mockConverter.commitSegmentValueHandler = { _, segmentIndex, candidateIndex in
      commitCount.increment()
      #expect(segmentIndex == 0)
      #expect(candidateIndex == 4)
      return true
    }
    let finishCount = CallCounter()
    mockConverter.finishConversionHandler = { _, _ in finishCount.increment() }
    converter.commit(f.composer, Genmai_Commands_Context())
    #expect(commitCount.count == 1)
    #expect(finishCount.count == 1)
    f.composer.reset()
    expectedIndices.removeAll()
    F.expectSelectedCandidateIndices(converter, expectedIndices)
    do {  // Check the submitted value
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(output.hasResult)
      #expect(!output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let result = output.result
      #expect(result.value == "モンドリアン")
      #expect(result.key == "もんどりあん")
    }

    // Action 7. Predict() (Next Word Prediction)
    // After commit, the state should be reset. Thus, calling prediction before
    // suggestion should trigger StartPrediction().
    let kEmptySegment = Segment()
    let nwpSegments: Segments = {
      let segments = Segments()
      let segment = segments.addSegment()
      var candidate = segment.addCandidate()
      candidate.value = "が"
      candidate.contentKey = "が"
      candidate = segment.addCandidate()
      candidate.value = "の"
      candidate.contentKey = "の"
      return segments
    }()
    let nwpCount = CallCounter()
    mockConverter.startPredictionWithPreviousSuggestionHandler = { _, previous, out in
      nwpCount.increment()
      #expect(equalsSegment(previous, kEmptySegment) == nil)
      out.assign(from: nwpSegments)
      return true
    }
    expectedIndices.append(0)
    #expect(converter.predict(f.composer))
    #expect(nwpCount.count == 1)
    #expect(converter.isActive())
    F.expectSelectedCandidateIndices(converter, expectedIndices)
    do {
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)

      // Check the composition
      let composition = output.preedit
      #expect(composition.segment.count == 1)
      #expect(composition.segment[0].value == "が")

      // Check the candidate list
      let candidateWindow = output.candidateWindow
      // Candidates should NOT be merged with the previous suggestions.
      #expect(candidateWindow.size == 2)
      #expect(candidateWindow.candidate[0].value == "が")
      #expect(candidateWindow.candidate[1].value == "の")
      #expect(candidateWindow.hasFocusedIndex)
    }
  }

  private static func makeMoSuggestionSegments() -> Segments {
    let segments = Segments()
    let segment = segments.addSegment()
    segment.setKey(kChars_Mo)
    var candidate = segment.addCandidate()
    candidate.value = kChars_Mozukusu
    candidate.contentKey = kChars_Mozukusu
    candidate = segment.addCandidate()
    candidate.value = kChars_Momonga
    candidate.contentKey = kChars_Momonga
    return segments
  }

  @Test func suggestFillIncognitoCandidateWords() {
    let f = F()
    // Initialize mock segments for suggestion
    let segments = Self.makeMoSuggestionSegments()
    f.composer.insertCharacterPreedit(kChars_Mo)

    do {
      f.request.fillIncognitoCandidateWords = false
      let mockConverter = MockConverter()
      let converter = EngineConverter(mockConverter, f.request, f.config)
      let normalCount = CallCounter()
      mockConverter.startPredictionHandler = { request, out in
        #expect(!request.incognitoMode())
        normalCount.increment()
        out.assign(from: segments)
        return true
      }
      #expect(converter.suggest(f.composer, Genmai_Commands_Context()))
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)
      #expect(!output.hasIncognitoCandidateWords)
      #expect(normalCount.count == 1)
    }
    do {
      f.request.fillIncognitoCandidateWords = true
      let mockConverter = MockConverter()
      let converter = EngineConverter(mockConverter, f.request, f.config)
      let normalCount = CallCounter()
      let incognitoCount = CallCounter()
      mockConverter.startPredictionHandler = { request, out in
        if request.incognitoMode() {
          incognitoCount.increment()
        } else {
          normalCount.increment()
        }
        out.assign(from: segments)
        return true
      }
      #expect(converter.suggest(f.composer, Genmai_Commands_Context()))
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)
      #expect(output.hasIncognitoCandidateWords)
      #expect(normalCount.count == 1)
      #expect(incognitoCount.count == 1)
    }
  }

  @Test func suggestFillIncognitoCandidateWordsEmptySegments() {
    let f = F()
    // Initialize mock segments for suggestion
    let segments = Self.makeMoSuggestionSegments()
    f.composer.insertCharacterPreedit(kChars_Mo)

    f.request.fillIncognitoCandidateWords = true
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    // Normal suggestion succeeds, but the incognito suggestion fails to produce
    // any candidates.  In this case |incognito_segments_| is left empty even
    // though the request asks to fill incognito candidate words.
    // FillOutput must not access out-of-bounds segments, and must not materialize
    // the field either, so has_incognito_candidate_words() stays false.
    let normalCount = CallCounter()
    let incognitoCount = CallCounter()
    mockConverter.startPredictionHandler = { request, out in
      if request.incognitoMode() {
        incognitoCount.increment()
        return false
      }
      normalCount.increment()
      out.assign(from: segments)
      return true
    }

    #expect(converter.suggest(f.composer, Genmai_Commands_Context()))
    var output = Genmai_Commands_Output()
    converter.fillOutput(f.composer, &output)
    #expect(!output.hasIncognitoCandidateWords)
    #expect(normalCount.count == 1)
    #expect(incognitoCount.count == 1)
  }

  @Test func onePhaseSuggestion() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    f.request.mixedConversion = true
    // The C++ fixture shares request_ with the converter.
    converter.setRequest(f.request)
    let segments = Segments()
    do {  // Initialize mock segments for suggestion (internally prediction)
      let segment = segments.addSegment()
      segment.setKey(kChars_Mo)
      var candidate = segment.addCandidate()
      candidate.value = kChars_Mozuku
      candidate.contentKey = kChars_Mozuku
      candidate = segment.addCandidate()
      candidate.value = kChars_Momonga
      candidate.contentKey = kChars_Momonga
      candidate = segment.addCandidate()
      candidate.value = "モンドリアン"
      candidate.contentKey = "もんどりあん"
    }
    f.composer.insertCharacterPreedit(kChars_Mo)

    // Suggestion (internally prediction)
    // Use "prediction" mock as this suggestion uses prediction internally.
    let predictionCount = CallCounter()
    mockConverter.startPredictionHandler = { _, out in
      predictionCount.increment()
      out.assign(from: segments)
      return true
    }
    #expect(converter.suggest(f.composer, Genmai_Commands_Context()))
    #expect(predictionCount.count == 1)
    #expect(F.isCandidateListVisible(converter))
    #expect(converter.isActive())

    do {  // Check the candidate list
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)

      let candidateWindow = output.candidateWindow
      #expect(candidateWindow.size == 3)
      #expect(candidateWindow.candidate[0].value == kChars_Mozuku)
      #expect(candidateWindow.candidate[1].value == kChars_Momonga)
      #expect(candidateWindow.candidate[2].value == "モンドリアン")
      #expect(!candidateWindow.hasFocusedIndex)
    }
  }

  @Test func suppressSuggestionWhenNotRequested() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    f.composer.insertCharacterPreedit(kChars_Mo)

    // Suggestion
    let predictionCount = CallCounter()
    mockConverter.startPredictionHandler = { _, _ in
      predictionCount.increment()
      return false
    }
    // No candidates should be visible because we are on password field.

    var conversionPreferences = converter.conversionPreferences
    conversionPreferences.requestSuggestion = false
    #expect(!converter.suggest(f.composer, Genmai_Commands_Context(), conversionPreferences))
    #expect(!F.isCandidateListVisible(converter))
    #expect(!converter.isActive())
    #expect(predictionCount.count == 0)
  }

  @Test func suppressSuggestionOnPasswordField() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    f.composer.setInputFieldType(.password)
    f.composer.insertCharacterPreedit(kChars_Mo)

    // Suggestion
    let predictionCount = CallCounter()
    mockConverter.startPredictionHandler = { _, _ in
      predictionCount.increment()
      return false
    }

    // No candidates should be visible because we are on password field.
    #expect(!converter.suggest(f.composer, Genmai_Commands_Context()))
    #expect(!F.isCandidateListVisible(converter))
    #expect(!converter.isActive())
    #expect(predictionCount.count == 0)
  }

  @Test func appendCandidateList() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    F.setState(S.conversion, converter)
    converter.setUseCascadingWindow(true)
    let segments = Segments()

    do {
      F.setAiueo(segments)
      f.composer.insertCharacterPreedit("あいうえお")
      F.fillT13Ns(segments, f.composer)

      F.setSegments(segments, converter)
      F.appendCandidateList(.conversion, converter)
      let candidateList = F.getCandidateList(converter)
      // 3 == hiragana cand, katakana cand and sub candidate list.
      #expect(candidateList.size == 3)
      #expect(candidateList.focused)
      var subCandListCount = 0
      for i in 0..<candidateList.size where candidateList.candidate(i).hasSubcandidateList() {
        subCandListCount += 1
      }
      // Sub candidate list for T13N.
      #expect(subCandListCount == 1)
    }
    do {
      let segment = segments.mutableConversionSegment(0)
      let candidate = segment.addCandidate()
      candidate.value = "あいうえお_2"
      // New meta candidates.
      // They should be ignored.
      let meta = Candidate()
      meta.value = "t13nValue"
      meta.contentValue = "t13nValue"
      meta.contentKey = segment.key
      segment.metaCandidates = [meta]

      F.setSegments(segments, converter)
      F.appendCandidateList(.conversion, converter)
      let candidateList = F.getCandidateList(converter)
      // 4 == hiragana cand, katakana cand, hiragana cand2
      // and sub candidate list.
      #expect(candidateList.size == 4)
      #expect(candidateList.focused)
      var subCandListCount = 0
      var idSet = Set<Int>()
      for i in 0..<candidateList.size {
        if candidateList.candidate(i).hasSubcandidateList() {
          subCandListCount += 1
        } else {
          // No duplicate ids are expected.
          let id = candidateList.candidate(i).id
          #expect(!idSet.contains(id))
          idSet.insert(id)
        }
      }
      // Sub candidate list shouldn't be duplicated.
      #expect(subCandListCount == 1)
    }
  }

  @Test func appendCandidateListForRequestTypes() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    F.setState(S.suggestion, converter)
    let segments = Segments()

    do {
      F.setAiueo(segments)
      f.composer.insertCharacterPreedit("あいうえお")
      F.fillT13Ns(segments, f.composer)
      F.setSegments(segments, converter)
      F.appendCandidateList(.suggestion, converter)
      let candidateList = F.getCandidateList(converter)
      #expect(!candidateList.focused)
    }

    segments.clear()
    do {
      F.setAiueo(segments)
      f.composer.insertCharacterPreedit("あいうえお")
      F.fillT13Ns(segments, f.composer)
      F.setSegments(segments, converter)
      F.appendCandidateList(.partialSuggestion, converter)
      let candidateList = F.getCandidateList(converter)
      #expect(!candidateList.focused)
    }

    segments.clear()
    do {
      F.setAiueo(segments)
      f.composer.insertCharacterPreedit("あいうえお")
      F.fillT13Ns(segments, f.composer)
      F.setSegments(segments, converter)
      F.appendCandidateList(.partialPrediction, converter)
      let candidateList = F.getCandidateList(converter)
      #expect(!candidateList.focused)
    }
  }

  @Test func reloadConfig() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    let segments = Segments()
    F.setAiueo(segments)
    f.composer.insertCharacterPreedit("あいうえお")
    F.fillT13Ns(segments, f.composer)
    let conversionCount = CallCounter()
    mockConverter.startConversionHandler = { _, out in
      conversionCount.increment()
      out.assign(from: segments)
      return true
    }

    f.composer.insertCharacterPreedit("aiueo")
    #expect(converter.convert(f.composer))
    converter.setCandidateListVisible(true)

    do {  // Set OperationPreferences
      converter.setUseCascadingWindow(false)
      converter.setSelectionShortcut(.shortcut123456789)
      #expect(F.isCandidateListVisible(converter))
    }
    do {  // Check the config update
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)

      let candidateWindow = output.candidateWindow
      #expect(candidateWindow.candidate[0].annotation.shortcut == "1")
      #expect(candidateWindow.candidate[1].annotation.shortcut == "2")
    }

    do {  // Set OperationPreferences #2
      converter.setUseCascadingWindow(false)
      converter.setSelectionShortcut(.noShortcut)
    }
    do {  // Check the config update
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)

      let candidateWindow = output.candidateWindow
      #expect(candidateWindow.candidate[0].annotation.shortcut.isEmpty)
      #expect(candidateWindow.candidate[1].annotation.shortcut.isEmpty)
    }
    #expect(conversionCount.count == 1)
  }

  @Test func outputAllCandidateWords() throws {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    let segments = Segments()
    F.setKamaboko(segments)
    let kKamabokono = "かまぼこの"
    let kInbou = "いんぼう"
    f.composer.insertCharacterPreedit(kKamabokono + kInbou)
    F.fillT13Ns(segments, f.composer)

    var output = Genmai_Commands_Output()

    let conversionCount = CallCounter()
    mockConverter.startConversionHandler = { _, out in
      conversionCount.increment()
      out.assign(from: segments)
      return true
    }
    #expect(converter.convert(f.composer))
    #expect(conversionCount.count == 1)
    do {
      try #require(converter.isActive())
      #expect(!F.isCandidateListVisible(converter))

      output = Genmai_Commands_Output()
      converter.popOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)
      #expect(output.hasAllCandidateWords)

      #expect(output.allCandidateWords.focusedIndex == 0)
      #expect(output.allCandidateWords.category == .conversion)
      // [ "かまぼこの", "カマボコの", "カマボコノ" (t13n), "かまぼこの" (t13n),
      //   "ｶﾏﾎﾞｺﾉ" (t13n) ]
      #expect(output.allCandidateWords.candidates.count == 5)
    }

    let focusCount = CallCounter()
    mockConverter.focusSegmentValueHandler = { _, segmentIndex, candidateIndex in
      focusCount.increment()
      #expect(segmentIndex == 0)
      #expect(candidateIndex == 1)
      return true
    }
    converter.candidateNext(f.composer)
    #expect(focusCount.count == 1)
    do {
      try #require(converter.isActive())
      #expect(F.isCandidateListVisible(converter))

      output = Genmai_Commands_Output()
      converter.popOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)
      #expect(output.hasAllCandidateWords)

      #expect(output.allCandidateWords.focusedIndex == 1)
      #expect(output.allCandidateWords.category == .conversion)
      // [ "かまぼこの", "カマボコの", "カマボコノ" (t13n), "かまぼこの" (t13n),
      //   "ｶﾏﾎﾞｺﾉ" (t13n) ]
      #expect(output.allCandidateWords.candidates.count == 5)
    }

    let commitCount = CallCounter()
    mockConverter.commitSegmentValueHandler = { _, segmentIndex, candidateIndex in
      commitCount.increment()
      #expect(segmentIndex == 0)
      #expect(candidateIndex == 1)
      return true
    }
    converter.segmentFocusRight()
    #expect(commitCount.count == 1)
    do {
      try #require(converter.isActive())
      #expect(!F.isCandidateListVisible(converter))

      output = Genmai_Commands_Output()
      converter.popOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)
      #expect(output.hasAllCandidateWords)

      #expect(output.allCandidateWords.focusedIndex == 0)
      #expect(output.allCandidateWords.category == .conversion)
      // [ "陰謀", "印房", "インボウ" (t13n), "いんぼう" (t13n), "ｲﾝﾎﾞｳ" (t13n) ]
      #expect(output.allCandidateWords.candidates.count == 5)
    }
  }

  @Test func getPreeditAndGetConversion() {
    let f = F()
    let segments = Segments()

    var segment = segments.addSegment()
    segment.setSegmentType(.history)
    segment.setKey("[key:history1]")
    var candidate = segment.addCandidate()
    candidate.contentKey = "[content_key:history1-1]"
    candidate = segment.addCandidate()
    candidate.contentKey = "[content_key:history1-2]"

    segment = segments.addSegment()
    segment.setSegmentType(.free)
    segment.setKey("[key:conversion1]")
    candidate = segment.addCandidate()
    candidate.key = "[key:conversion1-1]"
    candidate.contentKey = "[content_key:conversion1-1]"
    candidate.value = "[value:conversion1-1]"
    candidate.contentValue = "[content_value:conversion1-1]"
    candidate = segment.addCandidate()
    candidate.key = "[key:conversion1-2]"
    candidate.contentKey = "[content_key:conversion1-2]"
    candidate.value = "[value:conversion1-2]"
    candidate.contentValue = "[content_value:conversion1-2]"
    do {
      // PREDICTION
      let mockConverter = MockConverter()
      let converter = EngineConverter(mockConverter, f.request, f.config)
      let predictionCount = CallCounter()
      mockConverter.startPredictionWithPreviousSuggestionHandler = { _, _, out in
        predictionCount.increment()
        out.assign(from: segments)
        return true
      }
      let focusCount = CallCounter()
      mockConverter.focusSegmentValueHandler = { _, segmentIndex, candidateIndex in
        focusCount.increment()
        #expect(segmentIndex == 0)
        #expect(candidateIndex == 1)
        return true
      }
      _ = converter.predict(f.composer)
      converter.candidateNext(f.composer)
      let preedit = F.getPreedit(converter, 0, 1)
      #expect(preedit == "[content_key:conversion1-2]")
      let conversion = F.getConversion(converter, 0, 1)
      #expect(conversion == "[value:conversion1-2]")
      #expect(predictionCount.count == 1)
      #expect(focusCount.count == 1)
    }
    do {
      // SUGGESTION
      let mockConverter = MockConverter()
      let converter = EngineConverter(mockConverter, f.request, f.config)
      let predictionCount = CallCounter()
      mockConverter.startPredictionHandler = { _, out in
        predictionCount.increment()
        out.assign(from: segments)
        return true
      }
      _ = converter.suggest(f.composer, Genmai_Commands_Context())
      let preedit = F.getPreedit(converter, 0, 1)
      #expect(preedit == "[content_key:conversion1-1]")
      let conversion = F.getConversion(converter, 0, 1)
      #expect(conversion == "[value:conversion1-1]")
      #expect(predictionCount.count == 1)
    }
    segment = segments.addSegment()
    segment.setSegmentType(.free)
    segment.setKey("[key:conversion2]")
    candidate = segment.addCandidate()
    candidate.key = "[key:conversion2-1]"
    candidate.contentKey = "[content_key:conversion2-1]"
    candidate.value = "[value:conversion2-1]"
    candidate.contentValue = "[content_value:conversion2-1]"
    candidate = segment.addCandidate()
    candidate.key = "[key:conversion2-2]"
    candidate.contentKey = "[content_key:conversion2-2]"
    candidate.value = "[value:conversion2-2]"
    candidate.contentValue = "[content_value:conversion2-2]"
    do {
      // CONVERSION
      let mockConverter = MockConverter()
      let converter = EngineConverter(mockConverter, f.request, f.config)
      let conversionCount = CallCounter()
      mockConverter.startConversionHandler = { _, out in
        conversionCount.increment()
        out.assign(from: segments)
        return true
      }
      let focusCount = CallCounter()
      mockConverter.focusSegmentValueHandler = { _, segmentIndex, candidateIndex in
        focusCount.increment()
        #expect(segmentIndex == 0)
        #expect(candidateIndex == 1)
        return true
      }
      _ = converter.convert(f.composer)
      converter.candidateNext(f.composer)
      let preedit = F.getPreedit(converter, 0, 2)
      #expect(preedit == "[key:conversion1][key:conversion2]")
      let conversion = F.getConversion(converter, 0, 2)
      #expect(conversion == "[value:conversion1-2][value:conversion2-1]")
      #expect(conversionCount.count == 1)
      #expect(focusCount.count == 1)
    }
  }

  @Test func getAndSetSegments() throws {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    let segments = Segments()

    // Set history segments.
    let kHistoryInput = ["車で", "行く"]
    for input in kHistoryInput {
      let segment = segments.addSegment()
      segment.setSegmentType(.history)
      let candidate = segment.addCandidate()
      candidate.value = input
    }
    let finishCount = CallCounter()
    mockConverter.finishConversionHandler = { _, out in
      finishCount.increment()
      out.assign(from: segments)
    }
    converter.commitPreedit(f.composer, Genmai_Commands_Context())
    #expect(finishCount.count == 1)

    let src = Segments()
    F.getSegments(converter, src)
    try #require(src.historySegmentsSize == 2)
    #expect(src.historySegment(0).candidate(0).value == "車で")
    #expect(src.historySegment(1).candidate(0).value == "行く")

    src.mutableHistorySegment(0).mutableCandidate(0).value = "歩いて"
    let segment = src.addSegment()
    segment.setSegmentType(.free)
    let candidate = segment.addCandidate()
    candidate.value = "?"

    F.setSegments(src, converter)

    let dest = Segments()
    F.getSegments(converter, dest)

    try #require(dest.historySegmentsSize == 2)
    try #require(dest.conversionSegmentsSize == 1)
    #expect(dest.historySegment(0).candidate(0).value == src.historySegment(0).candidate(0).value)
    #expect(dest.historySegment(1).candidate(0).value == src.historySegment(1).candidate(0).value)
    #expect(dest.historySegment(2).candidate(0).value == src.historySegment(2).candidate(0).value)
  }

  @Test func clone() {
    let f = F()
    let mockConverter = MockConverter()
    let src = EngineConverter(mockConverter, f.request, f.config)

    do {  // create source converter
      let segments = Segments()
      F.setKamaboko(segments)

      mockConverter.startConversionHandler = { _, out in
        out.assign(from: segments)
        return true
      }

      src.setUseCascadingWindow(false)
      src.setSelectionShortcut(.shortcut123456789)
    }

    do {  // validation
      // Copy and validate
      var dest = src.cloneEngineConverter()
      F.expectSameEngineConverter(src, dest)

      // Convert source
      #expect(src.convert(f.composer))
      #expect(src.isActive())

      // Convert destination and validate
      #expect(dest.convert(f.composer))
      F.expectSameEngineConverter(src, dest)

      // Copy converted and validate
      dest = src.cloneEngineConverter()
      F.expectSameEngineConverter(src, dest)
    }
  }

  /// Suggest() in the suggestion state was not accepted.  (http://b/1948334)
  @Test func issue1948334() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    var segments = Self.makeMoSuggestionSegments()
    f.composer.insertCharacterPreedit(kChars_Mo)

    // Suggestion
    let first = segments
    mockConverter.startPredictionHandler = { _, out in
      out.assign(from: first)
      return true
    }
    #expect(converter.suggest(f.composer, Genmai_Commands_Context()))
    #expect(converter.isActive())

    segments = Segments()
    do {  // Initialize mock segments for the second suggestion
      let segment = segments.addSegment()
      segment.setKey("もず")
      let candidate = segment.addCandidate()
      candidate.value = kChars_Mozukusu
      candidate.contentKey = kChars_Mozukusu
    }
    f.composer.insertCharacterPreedit("もず")

    // Suggestion
    let second = segments
    mockConverter.startPredictionHandler = { _, out in
      out.assign(from: second)
      return true
    }
    #expect(converter.suggest(f.composer, Genmai_Commands_Context()))
    #expect(converter.isActive())

    do {  // Check the candidate list
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)

      let candidateWindow = output.candidateWindow
      // Candidates should be merged with the previous suggestions.
      #expect(candidateWindow.size == 1)
      #expect(candidateWindow.candidate[0].value == kChars_Mozukusu)
      #expect(!candidateWindow.hasFocusedIndex)
    }
  }

  @Test func issue1960362() {
    let f = F()
    // Testcase against http://b/1960362, a candidate list was not
    // updated when ConvertToTransliteration changed the size of segments.

    f.table.addRule("zyu", "ZYU", "")
    f.table.addRule("jyu", "ZYU", "")
    f.table.addRule("tt", "XTU", "t")
    f.table.addRule("ta", "TA", "")

    f.composer.insertCharacter("j")
    f.composer.insertCharacter("y")
    f.composer.insertCharacter("u")
    f.composer.insertCharacter("t")

    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let segments = Segments()
    do {
      var segment = segments.addSegment()
      segment.setKey("ZYU")
      var candidate = segment.addCandidate()
      candidate.value = "[ZYU]"
      candidate.contentKey = "[ZYU]"

      segment = segments.addSegment()
      segment.setKey("t")
      candidate = segment.addCandidate()
      candidate.value = "[t]"
      candidate.contentKey = "[t]"
    }

    let resizedSegments = Segments()
    do {
      let segment = resizedSegments.addSegment()
      segment.setKey("ZYUt")
      let candidate = segment.addCandidate()
      candidate.value = "[ZYUt]"
      candidate.contentKey = "[ZYUt]"
    }
    F.fillT13Ns(segments, f.composer)
    F.fillT13Ns(resizedSegments, f.composer)

    mockConverter.startConversionHandler = { _, out in
      out.assign(from: segments)
      return true
    }
    mockConverter.resizeSegmentHandler = { out, _, _, _ in
      out.assign(from: resizedSegments)
      return true
    }
    #expect(converter.convertToTransliteration(f.composer, .halfAscii))
    #expect(!F.isCandidateListVisible(converter))

    var output = Genmai_Commands_Output()
    converter.fillOutput(f.composer, &output)
    #expect(!output.hasResult)
    #expect(output.hasPreedit)
    #expect(!output.hasCandidateWindow)

    let conversion = output.preedit
    #expect(conversion.segment.first?.value == "jyut")
  }

  @Test func issue1978201() {
    let f = F()
    // This is a unittest against http://b/1978201
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    let segments = Segments()
    f.composer.insertCharacterPreedit(kChars_Mo)

    do {  // Initialize mock segments for prediction
      let segment = segments.addSegment()
      segment.setKey(kChars_Mo)
      var candidate = segment.addCandidate()
      candidate.value = kChars_Mozuku
      candidate.contentKey = kChars_Mozuku
      candidate = segment.addCandidate()
      candidate.value = kChars_Momonga
      candidate.contentKey = kChars_Momonga
    }

    // Prediction
    mockConverter.startPredictionWithPreviousSuggestionHandler = { _, _, out in
      out.assign(from: segments)
      return true
    }

    #expect(converter.predict(f.composer))
    #expect(converter.isActive())

    do {  // Check the conversion
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment.count == 1)
      #expect(conversion.segment.first?.value == kChars_Mozuku)
    }

    // Meaningless segment manipulations.
    converter.segmentWidthShrink(f.composer)
    converter.segmentFocusLeft()
    converter.segmentFocusLast()

    do {  // Check the conversion again
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(!output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment.count == 1)
      #expect(conversion.segment.first?.value == kChars_Mozuku)
    }
  }

  @Test func issue1981020() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)
    // "〜〜〜〜" U+301C * 4
    let waveDash301c = "〜〜〜〜"
    f.composer.insertCharacterPreedit(waveDash301c)
    let segments = Segments()
    let finishCount = CallCounter()
    mockConverter.finishConversionHandler = { _, arg in
      finishCount.increment()
      segments.assign(from: arg)
    }
    converter.commitPreedit(f.composer, Genmai_Commands_Context())
    #expect(finishCount.count == 1)

    // Not _WIN32.
    #expect(segments.conversionSegment(0).candidate(0).value == waveDash301c)
    #expect(segments.conversionSegment(0).candidate(0).contentValue == waveDash301c)
  }

  @Test func issue2029557() {
    let f = F()
    // Unittest against http://b/2029557
    // a<tab><F6> raised a DCHECK error.
    let mockConverter = MockConverter()

    let converter = EngineConverter(mockConverter, f.request, f.config)
    // Composition (as "a")
    f.composer.insertCharacterPreedit("a")

    // Prediction (as <tab>)
    let predictionSegments = Segments()
    F.setAiueo(predictionSegments)
    let predictionCount = CallCounter()
    mockConverter.startPredictionWithPreviousSuggestionHandler = { _, _, out in
      predictionCount.increment()
      out.assign(from: predictionSegments)
      return true
    }
    #expect(converter.predict(f.composer))
    #expect(converter.isActive())

    // Transliteration (as <F6>)
    let segments = Segments()
    let segment = segments.addSegment()
    segment.setKey("a")
    let candidate = segment.addCandidate()
    candidate.value = "a"

    F.fillT13Ns(segments, f.composer)
    let conversionCount = CallCounter()
    mockConverter.startConversionHandler = { _, out in
      conversionCount.increment()
      out.assign(from: segments)
      return true
    }
    #expect(converter.convertToTransliteration(f.composer, .hiragana))
    #expect(converter.isActive())
    #expect(predictionCount.count == 1)
    #expect(conversionCount.count == 1)
  }

  @Test func issue2031986() {
    let f = F()
    // Unittest against http://b/2031986
    // aaaaa<Shift+Enter> raised a CRT error.
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let count1 = CallCounter()
    do {  // Initialize a suggest result triggered by "aaaa".
      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey("aaaa")
      var candidate = segment.addCandidate()
      candidate.value = "AAAA"
      candidate = segment.addCandidate()
      candidate.value = "Aaaa"
      mockConverter.startPredictionHandler = { _, out in
        count1.increment()
        out.assign(from: segments)
        return true
      }
    }
    // Get suggestion
    f.composer.insertCharacterPreedit("aaaa")
    #expect(converter.suggest(f.composer, Genmai_Commands_Context()))
    #expect(converter.isActive())

    let count2 = CallCounter()
    do {  // Initialize no suggest result triggered by "aaaaa".
      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey("aaaaa")
      mockConverter.startPredictionHandler = { _, out in
        count2.increment()
        out.assign(from: segments)
        return false
      }
    }
    // Hide suggestion
    f.composer.insertCharacterPreedit("a")
    #expect(!converter.suggest(f.composer, Genmai_Commands_Context()))
    #expect(!converter.isActive())
    #expect(count1.count == 1)
    #expect(count2.count == 1)
  }

  @Test func issue2040116() {
    let f = F()
    // Unittest against http://b/2040116
    //
    // It happens when the first Predict returns results but the next
    // MaybeExpandPrediction does not return any results.  That's a
    // trick by GoogleSuggest.
    let mockConverter = MockConverter()

    let converter = EngineConverter(mockConverter, f.request, f.config)
    f.composer.insertCharacterPreedit("G")

    let count1 = CallCounter()
    do {
      // Initialize no predict result.
      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey("G")
      mockConverter.startPredictionWithPreviousSuggestionHandler = { _, _, out in
        count1.increment()
        out.assign(from: segments)
        return false
      }
    }
    // Get prediction
    #expect(!converter.predict(f.composer))
    #expect(!converter.isActive())

    let count2 = CallCounter()
    do {
      // Initialize a suggest result triggered by "G".
      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey("G")
      let candidate = segment.addCandidate()
      candidate.value = "GoogleSuggest"
      mockConverter.startPredictionWithPreviousSuggestionHandler = { _, _, out in
        count2.increment()
        out.assign(from: segments)
        return true
      }
    }
    // Get prediction again
    #expect(converter.predict(f.composer))
    #expect(converter.isActive())

    do {  // Check the conversion.
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment.count == 1)
      #expect(conversion.segment.first?.value == "GoogleSuggest")
    }

    let count3 = CallCounter()
    do {
      // Initialize no predict result triggered by "G".  It's possible
      // by Google Suggest.
      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey("G")
      mockConverter.startPredictionWithPreviousSuggestionHandler = { _, _, _ in
        count3.increment()
        return false
      }
    }
    // Hide prediction
    let focusCount = CallCounter()
    mockConverter.focusSegmentValueHandler = { _, segmentIndex, candidateIndex in
      focusCount.increment()
      #expect(segmentIndex == 0)
      #expect(candidateIndex == 0)
      return false
    }
    converter.candidateNext(f.composer)
    #expect(converter.isActive())
    #expect(count3.count == 0)
    #expect(focusCount.count == 1)

    do {  // Check the conversion.
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(output.hasPreedit)
      #expect(output.hasCandidateWindow)

      let conversion = output.preedit
      #expect(conversion.segment.count == 1)
      #expect(conversion.segment.first?.value == "GoogleSuggest")

      let candidateWindow = output.candidateWindow
      #expect(candidateWindow.candidate.count == 1)
    }
    #expect(count1.count == 1)
    #expect(count2.count == 1)
  }

  @Test func getReadingText() {
    let mockConverter = MockConverter()
    let f = F()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    let kKanjiAiueo = "阿伊宇江於"
    // Set up Segments for reverse conversion.
    let reverseSegments = Segments()
    let segment = reverseSegments.addSegment()
    segment.setKey(kKanjiAiueo)
    let candidate = segment.addCandidate()
    // For reverse conversion, key is the original kanji string.
    candidate.key = kKanjiAiueo
    candidate.value = kChars_Aiueo
    let count = CallCounter()
    mockConverter.startReverseConversionHandler = { out, key in
      count.increment()
      #expect(key == kKanjiAiueo)
      out.assign(from: reverseSegments)
      return true
    }
    var reading = ""
    #expect(converter.getReadingText(kKanjiAiueo, &reading))
    #expect(reading == kChars_Aiueo)
    #expect(count.count == 1)
  }

  @Test func zeroQuerySuggestion() {
    let f = F()
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter, f.request, f.config)

    // Set up a mock suggestion result.
    let segments = Segments()
    let segment = segments.addSegment()
    segment.setKey("")
    segment.addCandidate().value = "search"
    segment.addCandidate().value = "input"
    let count = CallCounter()
    mockConverter.startPredictionHandler = { _, out in
      count.increment()
      out.assign(from: segments)
      return true
    }

    #expect(f.composer.isEmpty())
    #expect(converter.suggest(f.composer, Genmai_Commands_Context()))
    #expect(F.isCandidateListVisible(converter))
    #expect(converter.isActive())

    do {  // Check the output
      var output = Genmai_Commands_Output()
      converter.fillOutput(f.composer, &output)
      #expect(!output.hasResult)
      #expect(!output.hasPreedit)
      #expect(output.hasCandidateWindow)

      let candidateWindow = output.candidateWindow
      #expect(candidateWindow.size == 2)
      #expect(candidateWindow.candidate[0].value == "search")
      #expect(candidateWindow.candidate[1].value == "input")
    }
    #expect(count.count == 1)
  }

  /// TEST(EngineConverterResetTest, Reset)
  @Test func reset() {
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter)
    let count = CallCounter()
    mockConverter.resetConversionHandler = { _ in count.increment() }
    converter.reset()
    #expect(count.count == 1)
  }

  /// TEST(EngineConverterRevertTest, Revert)
  @Test func revert() {
    let mockConverter = MockConverter()
    let converter = EngineConverter(mockConverter)
    let count = CallCounter()
    mockConverter.revertConversionHandler = { _ in count.increment() }
    converter.revert()
    #expect(count.count == 1)
  }
}
