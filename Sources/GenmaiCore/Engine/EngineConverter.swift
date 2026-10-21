// Port of mozc/src/engine/engine_converter.{h,cc} (3.35.6354).
//
// A class handling the converter as an interface for the session layer.
//
// Deviations from C++:
// - The members the C++ test accesses through `friend class
//   EngineConverterTest` are `internal` (tests use `@testable import`).
// - `Segments` / `Segment` are reference types in the Swift port; the C++
//   by-value members (`segments_`, `incognito_segments_`,
//   `previous_suggestions_`) are owned instances and `Clone()` deep-copies
//   them (the C++ default copy operator).
// - `size_t* consumed_key_size` is `inout Int`; `kConsumedAllCharacters` is
//   `Int.max` (C++: SIZE_MAX). `UpdateResult(..., nullptr)` and
//   `UpdateResult(..., &size)` are one `updateResult` plus
//   `getConsumedPreeditSize` (which is pure) called by the caller.
// - `std::shared_ptr<const Request/Config>` are protobuf values.
// - The usage-stats helper `UpdateCandidateStats` only builds a stat name and
//   records nothing in 3.35.6354 (usage_stats is disabled in OSS builds); it
//   is kept as a no-op. `selected_candidate_indices_` bookkeeping is ported
//   as is.
// - DCHECKs are omitted; CHECKs are `precondition`s.

import GenmaiBase
import GenmaiProtocol

private func getCandidateShortcuts(_ selectionShortcut: Genmai_Config_Config.SelectionShortcut)
  -> String
{
  // Keyboard shortcut for candidates.
  let kShortcut123456789 = "123456789"
  let kShortcutASDFGHJKL = "asdfghjkl"
  let kNoShortcut = ""

  var shortcut = kNoShortcut
  switch selectionShortcut {
  case .shortcut123456789:
    shortcut = kShortcut123456789
  case .shortcutAsdfghjkl:
    shortcut = kShortcutASDFGHJKL
  case .noShortcut:
    break
  }
  return shortcut
}

/// Calculate cursor offset for committed text.
private func calculateCursorOffset(_ committedText: some StringProtocol) -> Int32 {
  // If committed_text is a bracket pair, set the cursor in the middle.
  Util.isBracketPairText(committedText) ? -1 : 0
}

private typealias EAttr = CandidateList.Attribute

private func getT13nAttributes(_ type: TransliterationType) -> CandidateList.Attributes {
  var attributes = EAttr.noAttributes
  switch type {
  case .hiragana:  // "ひらがな"
    attributes = EAttr.hiragana
  case .fullKatakana:  // "カタカナ"
    attributes = (EAttr.fullWidth | EAttr.katakana)
  case .halfAscii:  // "ascII"
    attributes = (EAttr.halfWidth | EAttr.ascii | EAttr.asis)
  case .halfAsciiUpper:  // "ASCII"
    attributes = (EAttr.halfWidth | EAttr.ascii | EAttr.upper)
  case .halfAsciiLower:  // "ascii"
    attributes = (EAttr.halfWidth | EAttr.ascii | EAttr.lower)
  case .halfAsciiCapitalized:  // "Ascii"
    attributes = (EAttr.halfWidth | EAttr.ascii | EAttr.capitalized)
  case .fullAscii:  // "ａｓｃＩＩ"
    attributes = (EAttr.fullWidth | EAttr.ascii | EAttr.asis)
  case .fullAsciiUpper:  // "ＡＳＣＩＩ"
    attributes = (EAttr.fullWidth | EAttr.ascii | EAttr.upper)
  case .fullAsciiLower:  // "ａｓｃｉｉ"
    attributes = (EAttr.fullWidth | EAttr.ascii | EAttr.lower)
  case .fullAsciiCapitalized:  // "Ａｓｃｉｉ"
    attributes = (EAttr.fullWidth | EAttr.ascii | EAttr.capitalized)
  case .halfKatakana:  // "ｶﾀｶﾅ"
    attributes = (EAttr.halfWidth | EAttr.katakana)
  }
  return attributes
}

// Cycles ASCII (= Alphanumeric) cases to ASIS → UPPER → LOWER → CAPITALIZED.
// example:
//   "moZc": moZc (ASIS) → MOZC (UPPER) → mozc (LOWER) → Mozc (CAPITALIZED) →
//           moZc (ASIS) → ...
//
// If UPPER, LOWER, or CAPITALIZED is the same as ASIS, skip it and cycle to the
// next case.
// example:
//   "mozc": mozc (ASIS | LOWER) → MOZC (UPPER) → Mozc (CAPITALIZED) →
//           mozc (ASIS | LOWER) →
//   "MOZC": MOZC (ASIS | UPPER) → mozc (LOWER) → Mozc (CAPITALIZED) →
//           MOZC (ASIS | UPPER) →
//   "m": m (ASIS | LOWER) → M (UPPER | CAPACALIZED) → m (ASIS | LOWER) →
//   "M": M (ASIS | UPPER | CAPACALIZED) → m (LOWER) →
//        M (ASIS | UPPER | CAPACALIZED) →
private func cycleAlphaCase(_ queryAttrIn: CandidateList.Attributes, _ candidateList: CandidateList)
{
  var queryAttr = queryAttrIn
  var currentAttr = candidateList.getDeepestFocusedCandidate().attributes

  // If the current case is same as the user typed, move to the next case.
  if currentAttr & EAttr.asis != 0 {
    // The next case is basically UPPER.
    // However, if the ASIS is also UPPER, skip it and move to the LOWER case.
    queryAttr |= ((currentAttr & EAttr.upper != 0) ? EAttr.lower : EAttr.upper)
    candidateList.moveNextAttributes(queryAttr)
    return
  }

  // Move to the next case. If the next case is also ASIS, skip it as it's
  // already cycled before.
  // Try up to 3 times as there are 4 cases and avoid infinite loop.
  let baseQueryAttr = queryAttr
  for _ in 0..<3 {
    // Set query_attr to the next case and move it.
    if currentAttr & EAttr.upper != 0 {
      queryAttr = baseQueryAttr | EAttr.lower
    } else if currentAttr & EAttr.lower != 0 {
      queryAttr = baseQueryAttr | EAttr.capitalized
    } else if currentAttr & EAttr.capitalized != 0 {
      queryAttr = baseQueryAttr | EAttr.asis
    } else {  // nothing.
      queryAttr = baseQueryAttr | EAttr.upper
    }
    candidateList.moveNextAttributes(queryAttr)

    // If the next case is intentional ASIS, no need to skip it.
    if queryAttr & EAttr.asis != 0 {
      break
    }

    let newAttr = candidateList.getDeepestFocusedCandidate().attributes

    // If the next case is not ASIS, no need to skip it.
    if newAttr & EAttr.asis == 0 {
      break
    }

    // This checks an edge case. Even if the next case is also ASIS,
    // but the next case is only available case, we should not skip it.
    // If all possible attributes are covered by the current and next cases,
    // it means the next case is only available case.
    let sumAttr = newAttr | currentAttr
    if sumAttr & EAttr.asis != 0 && sumAttr & EAttr.upper != 0 && sumAttr & EAttr.lower != 0
      && sumAttr & EAttr.capitalized != 0
    {
      break
    }

    // The new case also contains ASIS, skip it and get the next case.
    currentAttr = newAttr
  }
}

/// Convert transliteration::TransliterationType to id used in the
/// converter.  The id number are negative values, and 0 of
/// transliteration::TransliterationType is bound for -1 of the id.
private func getT13nId(_ type: TransliterationType) -> Int {
  -(type.rawValue + 1)
}

private func maybeFillConfig(
  _ command: Candidate.Command, _ baseConfig: Genmai_Config_Config,
  _ output: inout Genmai_Commands_Output
) {
  if command == .defaultCommand {
    return
  }

  output.config = baseConfig
  switch command {
  case .enableIncognitoMode:
    output.config.incognitoMode = true
  case .disableIncognitoMode:
    output.config.incognitoMode = false
  case .enablePresentationMode:
    output.config.presentationMode = true
  case .disablePresentationMode:
    output.config.presentationMode = false
  default:
    GenmaiLog.warning("Unknown command: \(command)")
  }
}

/// Class handling ConverterInterface with a session state.  This class
/// support stateful operations related with the converter.
public final class EngineConverter: EngineConverterInterface {
  private typealias State = EngineConverterState

  /// Meaning that all the composition characters are consumed.
  /// c.f. CommitSuggestionInternal
  public static let kConsumedAllCharacters = Int.max

  let converter: any ConverterInterface

  // Conversion stats used by converter_.
  var segments = Segments()

  // Segments for Text Conversion API to fill incognito_candidate_words
  // Note:
  // Text Conversion API is available in Android Gboard.
  // It provides the converted candidates from the composition texts.
  var incognitoSegments = Segments()
  var segmentIndex = 0

  // Previous suggestions to be merged with the current predictions.
  var previousSuggestions = Segment()

  // A part of Output protobuf to be returned to the client side.
  var result = Genmai_Commands_Result()

  // Component of the candidate list converted from segments_to result_.
  var candidateList = CandidateList(rotate: true)

  var request: Genmai_Commands_Request
  var config = Genmai_Config_Config()

  var state: EngineConverterStates = EngineConverterState.composition

  // Remembers request type to manage state.
  // TODO(team): Check whether we can switch behaviors using state_
  // instead of request_type_.
  var requestType: RequestType = .conversion

  // Default conversion preferences.
  var conversionPreferencesValue = ConversionPreferences()

  var selectionShortcut: Genmai_Config_Config.SelectionShortcut = .noShortcut

  // Selected index data of each segments for usage stats.
  var selectedCandidateIndices: [Int] = []

  // Indicates whether config_ will be updated by the command candidate.
  var updatedCommand: Candidate.Command = .defaultCommand

  // Revision number of client context with which the converter determines when
  // the history segments should be invalidated. See the implementation of
  // OnStartComposition for details.
  var clientRevision: Int32 = 0

  var candidateListVisible = false

  // Mutable values of |config_|.  These values may be changed temporarily per
  // session.
  var useCascadingWindow = false

  public convenience init(_ converter: any ConverterInterface) {
    self.init(converter, getSharedDefaultRequest(), ConfigHandler.getSharedDefaultConfig())
  }

  public init(
    _ converter: any ConverterInterface, _ request: Genmai_Commands_Request,
    _ config: Genmai_Config_Config
  ) {
    self.converter = converter
    self.request = request
    conversionPreferencesValue.useHistory = true
    conversionPreferencesValue.requestSuggestion = true
    candidateList.pageSize = Int(request.candidatePageSize)
    setConfig(config)
  }

  /// Checks if the current state is in the state bitmap.
  public func checkState(_ states: EngineConverterStates) -> Bool {
    (state & states) != State.noState
  }

  /// Indicates if the conversion session is active or not.  In general,
  /// Convert functions make it active and Cancel, Reset and Commit
  /// functions make it deactive.
  public func isActive() -> Bool {
    checkState(State.suggestion | State.prediction | State.conversion)
  }

  /// Returns the default conversion preferences to be used for custom
  /// conversion.
  public var conversionPreferences: ConversionPreferences { conversionPreferencesValue }

  private func makeRequestBuilder(_ composer: Composer, _ context: Genmai_Commands_Context?)
    -> ConversionRequestBuilder
  {
    var builder = ConversionRequestBuilder()
      .setComposer(composer)
      .setRequestView(request)
    if let context {
      builder = builder.setContextView(context)
    }
    return builder.setConfigView(config)
  }

  /// Sends a conversion request to the converter.
  public func convert(
    _ composer: Composer, _ context: Genmai_Commands_Context, _ preferences: ConversionPreferences
  ) -> Bool {
    var options = ConversionRequest.Options()
    options.enableUserHistoryForConversion = preferences.useHistory
    setRequestType(.conversion, &options)
    let conversionRequest = makeRequestBuilder(composer, context)
      .setOptions(options)
      .build()

    if !converter.startConversion(conversionRequest, segments) {
      GenmaiLog.warning("StartConversion() failed")
      resetState()
      return false
    }

    segmentIndex = 0
    state = State.conversion
    // If TalkBack is enabled, the candidate list should be always visible to
    // propagate the candidate words to TalkBack. Otherwise, the candidate list
    // is not visible on the first conversion.
    candidateListVisible = request.isA11YTalkbackEnabled
    updateCandidateList()
    initializeSelectedCandidateIndices()
    return true
  }

  /// Gets reading text (e.g. from "猫" to "ねこ").
  public func getReadingText(_ sourceText: String, _ reading: inout String) -> Bool {
    reading = ""
    let reverseSegments = Segments()
    // TODO(team): Replace with StartReverseConversionForRequest()
    // once it is implemented.
    if !converter.startReverseConversion(reverseSegments, sourceText) {
      return false
    }
    if reverseSegments.segmentsSize == 0 {
      GenmaiLog.warning("no segments from reverse conversion")
      return false
    }
    for segment in reverseSegments.all {
      if segment.candidatesSize == 0 {
        GenmaiLog.warning("got an empty segment from reverse conversion")
        return false
      }
      reading.append(segment.candidate(0).value)
    }
    return true
  }

  /// Sends a transliteration request to the converter.
  public func convertToTransliteration(_ composer: Composer, _ type: TransliterationType) -> Bool {
    if checkState(State.prediction) {
      // TODO(komatsu): A better way is to transliterate the key of the
      // focused candidate.  However it takes a long time.
      cancel()
    }

    var queryAttr =
      (getT13nAttributes(type)
        & (EAttr.halfWidth | EAttr.fullWidth | EAttr.ascii | EAttr.hiragana | EAttr.katakana))

    if checkState(State.composition | State.suggestion) {
      if !convert(composer) {
        GenmaiLog.error("Conversion failed")
        return false
      }

      // TODO(komatsu): This is a workaround to transliterate the whole
      // preedit as a single segment.  We should modify
      // converter/converter.cc to enable to accept mozc::Segment::FIXED
      // from the session layer.
      if segmentIndex + 1 != segments.conversionSegmentsSize {
        var offset = 0
        for segment in segments.conversionSegments.dropFirst(segmentIndex + 1) {
          offset += segment.keyLen
        }
        resizeSegmentWidth(composer, Int(Int32(truncatingIfNeeded: offset)))
      }

      // The initial transliteration to ASCII is always as-is case.
      // e.g. もZc → moZc
      if queryAttr & EAttr.ascii != 0 {
        queryAttr |= EAttr.asis
      }
      candidateList.moveToAttributes(queryAttr)
    } else {
      let currentAttr = candidateList.getDeepestFocusedCandidate().attributes
      let commonAttr = currentAttr & queryAttr

      // Transliterations among half-width and full-width will keep the case.
      // e.g. Mozc → Ｍｏｚｃ
      if commonAttr & EAttr.ascii != 0
        && ((queryAttr & EAttr.halfWidth != 0 && currentAttr & EAttr.fullWidth != 0)
          || (queryAttr & EAttr.fullWidth != 0 && currentAttr & EAttr.halfWidth != 0))
      {
        queryAttr |= (currentAttr & (EAttr.upper | EAttr.lower | EAttr.capitalized | EAttr.asis))
      }

      if commonAttr & EAttr.ascii != 0
        && (commonAttr & EAttr.halfWidth != 0 || commonAttr & EAttr.fullWidth != 0)
      {
        cycleAlphaCase(queryAttr, candidateList)
      } else {
        candidateList.moveNextAttributes(queryAttr)
      }
    }
    candidateListVisible = false
    // Treat as top conversion candidate on usage stats.
    selectedCandidateIndices[segmentIndex] = 0
    segmentFocus()
    return true
  }

  /// Converts the current composition to half-width characters.
  /// NOTE(komatsu): This function might be merged to ConvertToTransliteration.
  public func convertToHalfWidth(_ composer: Composer) -> Bool {
    if checkState(State.prediction) {
      // TODO(komatsu): A better way is to transliterate the key of the
      // focused candidate.  However it takes a long time.
      cancel()
    }

    let composition: String
    if checkState(State.composition | State.suggestion) {
      composition = composer.getStringForPreedit()
    } else {
      composition = getSelectedCandidate(segmentIndex).value
    }

    // TODO(komatsu): make a function to return a logical sum of ScriptType.
    // If composition_ is "あｂｃ", it should be treated as Katakana.
    if Util.containsScriptType(composition, .katakana)
      || Util.containsScriptType(composition, .hiragana)
      || Util.containsScriptType(composition, .kanji)
      || Util.isKanaSymbolContained(composition)
    {
      return convertToTransliteration(composer, .halfKatakana)
    } else {
      return convertToTransliteration(composer, .halfAscii)
    }
  }

  /// Switches the composition to Hiragana, full-width Katakana or
  /// half-width Katakana by rotation.
  public func switchKanaType(_ composer: Composer) -> Bool {
    if checkState(State.prediction) {
      // TODO(komatsu): A better way is to transliterate the key of the
      // focused candidate.  However it takes a long time.
      cancel()
    }

    var attributes = EAttr.noAttributes
    if checkState(State.composition | State.suggestion) {
      if !convert(composer) {
        GenmaiLog.error("Conversion failed")
        return false
      }

      // TODO(komatsu): This is a workaround to transliterate the whole
      // preedit as a single segment.  We should modify
      // converter/converter.cc to enable to accept mozc::Segment::FIXED
      // from the session layer.
      if segments.conversionSegmentsSize != 1 {
        var offset: UInt8 = 0
        for i in 0..<segments.conversionSegmentsSize {
          offset &+= UInt8(truncatingIfNeeded: segments.conversionSegment(i).keyLen)
        }
        let conversionRequest = makeRequestBuilder(composer, nil)
          .setRequestType(.conversion)
          .build()
        if !converter.resizeSegments(segments, conversionRequest, 0, [offset]) {
          GenmaiLog.warning("ResizeSegment failed for segments.")
        }
        updateCandidateList()
      }

      attributes = (EAttr.fullWidth | EAttr.katakana)
    } else {
      let currentAttributes = candidateList.getDeepestFocusedCandidate().attributes
      // "漢字" -> "かんじ" -> "カンジ" -> "ｶﾝｼﾞ" -> "かんじ" -> ...
      if currentAttributes & EAttr.hiragana != 0 {
        attributes = (EAttr.fullWidth | EAttr.katakana)
      } else if currentAttributes & EAttr.katakana != 0
        && currentAttributes & EAttr.fullWidth != 0
      {
        attributes = (EAttr.halfWidth | EAttr.katakana)
      } else {
        attributes = EAttr.hiragana
      }
    }

    candidateList.moveNextAttributes(attributes)
    candidateListVisible = false
    // Treat as top conversion candidate on usage stats.
    selectedCandidateIndices[segmentIndex] = 0
    segmentFocus()
    return true
  }

  /// Sends a suggestion request to the converter.
  public func suggest(
    _ composer: Composer, _ context: Genmai_Commands_Context, _ preferences: ConversionPreferences
  ) -> Bool {
    candidateListVisible = false

    // Normalize the current state by resetting the previous state.
    resetState()

    // If we are on a password field, suppress suggestion.
    if !preferences.requestSuggestion || composer.getInputFieldType() == .password {
      return false
    }

    // Initialize the conversion request and segments for suggestion.
    var options = ConversionRequest.Options()
    options.enableUserHistoryForConversion = preferences.useHistory
    segments.clearConversionSegments()

    let cursor = composer.getCursor()

    // We have four (2x2) conditions for
    // (use_prediction_candidate, use_partial_composition):
    // - (false, false): Original suggestion behavior on desktop.
    // - (false, true): Never happens.
    // - (true, false): Mobile suggestion with richer candidates through
    //                  prediction API.
    // - (true, true): Mobile suggestion with richer candidates through
    //                  prediction API, using partial composition text.
    let usePredictionCandidate = request.mixedConversion
    let usePartialComposition =
      (cursor != composer.getLength() && cursor != 0 && request.mixedConversion)

    // Setup request based on the above two flags.
    options.useActualConverterForRealtimeConversion = true
    if usePartialComposition {
      // Auto partial suggestion should be activated only when we use all the
      // composition.
      // Note: For now, use_partial_composition is only for mobile typing.
      setRequestType(.partialPrediction, &options)
    } else {
      options.createPartialCandidates = request.autoPartialSuggestion
      if usePredictionCandidate {
        setRequestType(.prediction, &options)
      } else {
        setRequestType(.suggestion, &options)
      }
    }

    let conversionRequest = makeRequestBuilder(composer, context)
      .setOptions(options)
      .build()

    // Start actual suggestion/prediction.
    var result = converter.startPrediction(conversionRequest, segments)
    if !result {
      // Clear segments and keep the context
      converter.cancelConversion(segments)
      return false
    }

    // Fill incognito candidates if required.
    // The candidates are always from suggestion API
    // as richer results are not needed.
    if request.fillIncognitoCandidateWords {
      var incognitoOptions = conversionRequest.options()
      incognitoOptions.enableUserHistoryForConversion = false
      incognitoOptions.requestType = usePartialComposition ? .partialSuggestion : .suggestion
      incognitoOptions.incognitoMode = true
      let incognitoConversionRequest = ConversionRequestBuilder()
        .setConversionRequestView(conversionRequest)
        .setConfigView(config)
        .setOptions(incognitoOptions)
        .build()
      incognitoSegments.clear()
      result = converter.startPrediction(incognitoConversionRequest, incognitoSegments)
      if !result {
        // TODO(noriyukit): Check if fall through here is ok.
      }
    }

    // Copy current suggestions so that we can merge
    // prediction/suggestions later
    previousSuggestions = segments.conversionSegment(0).copy()

    // Overwrite the request type to SUGGESTION.
    // Without this logic, a candidate gets focused that is unexpected behavior.
    requestType = .suggestion

    // TODO(komatsu): the next line can be deleted.
    segmentIndex = 0
    state = State.suggestion
    updateCandidateList()
    candidateListVisible = true
    initializeSelectedCandidateIndices()
    return true
  }

  func isEmptySegment(_ segment: Segment) -> Bool {
    (segment.candidatesSize == 0) && (segment.metaCandidatesSize == 0)
  }

  /// Sends a prediction request to the converter.
  public func predict(
    _ composer: Composer, _ context: Genmai_Commands_Context, _ preferences: ConversionPreferences
  ) -> Bool {
    resetResult()

    // Initialize the segments and conversion_request for prediction
    var options = ConversionRequest.Options()
    options.enableUserHistoryForConversion = preferences.useHistory
    setRequestType(.prediction, &options)
    options.useActualConverterForRealtimeConversion = true
    let conversionRequest = makeRequestBuilder(composer, context)
      .setOptions(options)
      .build()

    let predictFirst = !checkState(State.prediction) && isEmptySegment(previousSuggestions)

    let predictExpand =
      (checkState(State.prediction) && !isEmptySegment(previousSuggestions)
        && candidateList.size > 0 && candidateList.focused
        && candidateList.focusedIndex == candidateList.lastIndex)

    segments.clearConversionSegments()

    if predictExpand || predictFirst {
      let result = converter.startPredictionWithPreviousSuggestion(
        conversionRequest, previousSuggestions, segments)
      if !result && predictFirst {
        // Returns false if we failed at the first prediction.
        // If predict_expand is true, it means we have prevous_suggestions_.
        // So we can use it as the result of this prediction.
        resetState()
        return false
      }
    } else {
      converter.prependCandidates(conversionRequest, previousSuggestions, segments)
    }

    segmentIndex = 0
    state = State.prediction
    updateCandidateList()
    candidateListVisible = true
    initializeSelectedCandidateIndices()
    return true
  }

  /// If focus_id is pointing to the last of suggestions,
  /// call StartPrediction().
  func maybeExpandPrediction(_ composer: Composer) {
    // Expand the current suggestions and fill with Prediction results.
    if !checkState(State.prediction) || isEmptySegment(previousSuggestions)
      || !candidateList.focused || candidateList.focusedIndex != candidateList.lastIndex
    {
      return
    }

    resetResult()

    let previousIndex = candidateList.focusedIndex
    if !predict(composer, conversionPreferencesValue) {
      return
    }

    candidateList.moveToId(candidateList.candidate(previousIndex).id)
    updateSelectedCandidateIndex()
  }

  /// Clears conversion segments, but keep the context.
  public func cancel() {
    resetResult()

    // Clear segments and keep the context
    converter.cancelConversion(segments)
    resetState()
  }

  /// Clears conversion segments and the context.
  public func reset() {
    // Even if composition mode, call ResetConversion
    // in order to clear history segments.
    converter.resetConversion(segments)

    if checkState(State.composition) {
      return
    }

    resetResult()
    // Reset segments (and its internal context)
    resetState()
  }

  /// Fixes the conversion with the current status.
  public func commit(_ composer: Composer, _ context: Genmai_Commands_Context) {
    resetResult()

    if !updateResult(0, segments.conversionSegmentsSize) {
      cancel()
      resetState()
      return
    }

    var i = 0
    while i < segments.conversionSegmentsSize {
      let candIdx = getCandidateIndexForConverter(i)
      if !converter.commitSegmentValue(segments, i, candIdx) {
        GenmaiLog.warning("Failed to commit segment \(i)")
      }
      i += getSegmentSpan(i)
    }
    commitSegmentsSize(state, context)
    let conversionRequest = makeRequestBuilder(composer, context).build()
    converter.finishConversion(conversionRequest, segments)
    resetState()
  }

  /// Syncs user-modified context.
  public func commitContext(_ composer: Composer, _ context: Genmai_Commands_Context) {
    let conversionRequest = makeRequestBuilder(composer, context).build()
    converter.commitContext(conversionRequest)
  }

  /// Returns the length of committed candidate's key in characters.
  /// True is returned if the selected candidate is successfully committed.
  func commitSuggestionInternal(
    _ composer: Composer, _ context: Genmai_Commands_Context, _ consumedKeySize: inout Int
  ) -> Bool {
    resetResult()
    let preedit = composer.getStringForPreedit()

    if !updateResult(0, segments.conversionSegmentsSize) {
      // Do not need to call Cancel like Commit because the current
      // state is SUGGESTION.
      resetState()
      return false
    }
    consumedKeySize = getConsumedPreeditSize(0, segments.conversionSegmentsSize)

    let preeditLength = Util.charsLen(preedit)

    // TODO(horo): When we will support hardware keyboard and introduce
    // shift+enter keymap in Android, this if condition may be insufficient.
    if request.zeroQuerySuggestion && consumedKeySize < composer.getLength() {
      // A candidate was chosen from partial suggestion.
      if !converter.commitPartialSuggestionSegmentValue(
        segments, 0, getCandidateIndexForConverter(0),
        String(Util.utf8SubString(preedit, 0, consumedKeySize)),
        String(Util.utf8SubString(preedit, consumedKeySize, preeditLength - consumedKeySize)))
      {
        GenmaiLog.warning("CommitPartialSuggestionSegmentValue failed")
        return false
      }
      commitSegmentsSize(State.suggestion, context)
      initializeSelectedCandidateIndices()
      // One or more segments must exist because new segment is inserted
      // just after the committed segment.
    } else {
      // Not partial suggestion so let's reset the state.
      if !converter.commitSegmentValue(segments, 0, getCandidateIndexForConverter(0)) {
        GenmaiLog.warning("CommitSegmentValue failed")
        return false
      }
      commitSegmentsSize(State.suggestion, context)
      let conversionRequest = makeRequestBuilder(composer, context).build()
      converter.finishConversion(conversionRequest, segments)
      resetState()
    }
    return true
  }

  /// Fixes the suggestion candidate. Stores the number of characters in the key
  /// of the committed candidate to committed_key_size.
  /// For example, assume that "日本語" was suggested as a candidate for "にほ".
  /// The key of the candidate is "にほんご". Therefore, when the candidate is
  /// committed by this function, consumed_key_size will be set to 4.
  /// |consumed_key_size| can be very large value
  /// (i.e. EngineConverter::kConsumedAllCharacters).
  /// In this case all the composition characters are consumed.
  /// True is returned if the suggestion is successfully committed.
  public func commitSuggestionByIndex(
    _ index: Int, _ composer: Composer, _ context: Genmai_Commands_Context,
    _ consumedKeySize: inout Int
  ) -> Bool {
    if index >= candidateList.size {
      GenmaiLog.error("index is out of the range: \(index)")
      return false
    }
    candidateList.moveToPageIndex(index)
    updateSelectedCandidateIndex()
    return commitSuggestionInternal(composer, context, &consumedKeySize)
  }

  /// Selects a candidate and commit the selected candidate.  True is
  /// returned if the suggestion is successfully committed.
  /// c.f. CommitSuggestionInternal
  public func commitSuggestionById(
    _ id: Int, _ composer: Composer, _ context: Genmai_Commands_Context,
    _ consumedKeySize: inout Int
  ) -> Bool {
    if !candidateList.moveToId(id) {
      // Don't use CandidateMoveToId() method, which overwrites candidates.
      // This is harmful for EXPAND_SUGGESTION session command.
      GenmaiLog.error("No id found")
      return false
    }
    updateSelectedCandidateIndex()
    return commitSuggestionInternal(composer, context, &consumedKeySize)
  }

  /// Does almost the same thing as CommitFirstSegment.
  /// The only difference is to fix the segments from the head to the focused.
  public func commitHeadToFocusedSegments(
    _ composer: Composer, _ context: Genmai_Commands_Context, _ consumedKeySize: inout Int
  ) {
    commitSegmentsInternal(
      composer, context, segmentIndex + getSegmentSpan(segmentIndex), &consumedKeySize)
  }

  /// Fixes only the conversion of the first segment, and keep the rest.
  /// The caller should delete characters from composer based on returned
  /// |committed_key_size|.
  /// If |consumed_key_size| is 0, this means that there is only a segment
  /// so Commit() method is called instead. In this case, the caller
  /// should not delete any characters.
  public func commitFirstSegment(
    _ composer: Composer, _ context: Genmai_Commands_Context, _ consumedKeySize: inout Int
  ) {
    commitSegmentsInternal(composer, context, getSegmentSpan(0), &consumedKeySize)
  }

  /// Fixes the conversion of the [0, segments_to_commit -1 ] segments,
  /// and keep the rest.
  func commitSegmentsInternal(
    _ composer: Composer, _ context: Genmai_Commands_Context, _ segmentsToCommit: Int,
    _ consumedKeySize: inout Int
  ) {
    resetResult()
    candidateListVisible = false
    consumedKeySize = 0

    // If the selected candidate on the first segment covers all conversion
    // segments (e.g. full-sentence candidate), commit the entire conversion
    // rather than partially committing only the first segment.
    if isFullSentenceCandidateSelected() {
      commit(composer, context)
      return
    }

    // If commit all segments, just call Commit.
    if segments.conversionSegmentsSize <= segmentsToCommit {
      commit(composer, context)
      return
    }

    // Store the first conversion segment to the result.
    if !updateResult(0, segmentsToCommit) {
      // If the selected candidate of the first segment has the command
      // attribute, Cancel is performed instead of Commit.
      cancel()
      resetState()
      return
    }

    for i in 0..<segmentsToCommit {
      // Accumulate the size of i-th segment's key.
      // The caller will remove corresponding characters from the composer.
      consumedKeySize += segments.conversionSegment(i).keyLen
    }

    var candidateIds: [Int] = []
    var i = 0
    while i < segmentsToCommit {
      // Collect candidate's id for each logical segment.
      candidateIds.append(getCandidateIndexForConverter(i))
      i += getSegmentSpan(i)
    }
    if !converter.commitSegments(segments, candidateIds) {
      GenmaiLog.warning("CommitSegments failed")
    }

    // Commit the [0, segments_to_commit - 1] conversion segment.
    commitSegmentsSize(segmentsToCommit)

    // Adjust the segment_index, since the [0, segment_to_commit - 1] segments
    // disappeared.
    // Note that segment_index_ is unsigned.
    segmentIndex = segmentIndex > segmentsToCommit ? segmentIndex - segmentsToCommit : 0
    updateCandidateList()
  }

  /// Commits the preedit string represented by Composer.
  public func commitPreedit(_ composer: Composer, _ context: Genmai_Commands_Context) {
    let key = composer.getQueryForConversion()
    let preedit = composer.getStringForSubmission()
    let normalizedPreedit = TextNormalizer.normalizeText(preedit)
    EngineOutput.fillPreeditResult(preedit, &result)

    // Add ResultToken
    var token = Genmai_Commands_ResultToken()
    token.key = preedit
    token.value = preedit
    result.tokens.append(token)

    // Cursor offset needs to be calculated based on normalized text.
    EngineOutput.fillCursorOffsetResult(calculateCursorOffset(normalizedPreedit), &result)
    segments.initForCommit(key, normalizedPreedit)
    commitSegmentsSize(State.composition, context)
    // the request mode is CONVERSION, as the user experience
    // is similar to conversion. UserHistoryPredictor distinguishes
    // CONVERSION from SUGGESTION now.
    var options = ConversionRequest.Options()
    setRequestType(.conversion, &options)
    let conversionRequest = makeRequestBuilder(composer, context)
      .setOptions(options)
      .build()
    converter.finishConversion(conversionRequest, segments)
    resetState()
  }

  /// Commits the specified number of characters at the head of the preedit
  /// string represented by Composer.
  /// The caller should delete characters from composer based on returned
  /// |consumed_key_size|.
  /// TODO(yamaguchi): Enhance to support the conversion mode.
  public func commitHead(_ count: Int, _ composer: Composer, _ consumedKeySize: inout Int) {
    var preedit = composer.getStringForSubmission()
    // NOTE: C++ compares |count| (characters) with the byte length.
    if count > preedit.utf8.count {
      consumedKeySize = preedit.utf8.count
    } else {
      consumedKeySize = count
    }
    preedit = String(Util.utf8SubString(preedit, 0, consumedKeySize))
    let composition = TextNormalizer.normalizeText(preedit)
    EngineOutput.fillPreeditResult(composition, &result)
    EngineOutput.fillCursorOffsetResult(calculateCursorOffset(composition), &result)
  }

  /// Reverts the last "Commit" operation
  public func revert() { converter.revertConversion(segments) }

  /// Delete candidate from user input history.
  /// Try to delete the current selected candidate if |id| is not specified.
  /// Returns false if the candidate was not found or deletion failed.
  public func deleteCandidateFromHistory(_ idIn: Int?) -> Bool {
    var id = idIn
    if id == nil {
      if !candidateList.focused {
        return false
      }
      let cand = candidateList.focusedCandidate
      id = cand.id
    } else {
      if segmentIndex >= segments.conversionSegmentsSize {
        return false
      }
      let segment = segments.conversionSegment(segmentIndex)
      if !segment.isValidIndex(id!) {
        return false
      }
    }
    return converter.deleteCandidateFromHistory(
      segments, segments.historySegmentsSize + segmentIndex, id!)
  }

  func segmentFocusInternal(_ index: Int) {
    candidateListVisible = false
    if checkState(State.prediction) {
      return  // Do nothing.
    }
    resetResult()

    if segmentIndex == index {
      return
    }

    segmentFix()
    segmentIndex = index
    updateCandidateList()
  }

  /// Moves the focus of segments.
  public func segmentFocusRight() {
    let span = Int(getSelectedCandidate(segmentIndex).effectiveConvertedSegmentCount)
    if segmentIndex + span >= segments.conversionSegmentsSize {
      // If the next segment position reaches or exceeds the tail of the
      // segments, focus on the head.
      segmentFocusLeftEdge()
    } else {
      segmentFocusInternal(segmentIndex + span)
    }
  }

  public func segmentFocusLast() {
    let rEdge = segments.conversionSegmentsSize - 1
    segmentFocusInternal(rEdge)
  }

  public func segmentFocusLeft() {
    if segmentIndex <= 0 {
      // If |segment_index_| is at the head of the segments,
      // focus on the tail.
      segmentFocusLast()
    } else {
      // With multi-segment candidates, the previous segment's start index is not
      // necessarily `segment_index_ - 1`. Traverse from the beginning using
      // segment spans to find the start index of the segment immediately
      // preceding `segment_index_`.
      var prev = 0
      var i = 0
      while i < segmentIndex {
        prev = i
        i += getSegmentSpan(i)
      }
      segmentFocusInternal(prev)
    }
  }

  public func segmentFocusLeftEdge() { segmentFocusInternal(0) }

  func resizeSegmentWidth(_ composer: Composer, _ delta: Int) {
    candidateListVisible = false
    if checkState(State.prediction) {
      return  // Do nothing.
    }
    resetResult()

    let conversionRequest = makeRequestBuilder(composer, nil)
      .setRequestType(.conversion)
      .build()
    let segment = segments.conversionSegment(segmentIndex)
    let candidate = getSelectedCandidate(segmentIndex)

    // For multi-segment candidates with step resize (+/-1), resize based on
    // the full candidate key length.
    // e.g. For 2-segment candidate "私の名前は" (key: "わたしのなまえは", 8
    // chars) when segment(0).key_len() is 4, delta=+1 should target 9 chars
    // (offset = 9 - 4 = +5) rather than 5 chars (4 + 1).
    let currentLen =
      (abs(delta) == 1 && candidate.effectiveConvertedSegmentCount > 1 && !candidate.key.isEmpty)
      ? Util.charsLen(candidate.key) : segment.keyLen

    // target_len: The desired absolute key length after resizing (+/- delta).
    let targetLen = currentLen + delta
    // offset_length: The relative offset from segment.key_len() passed to
    // ResizeSegment.
    let offsetLength = targetLen - segment.keyLen

    if targetLen <= 0 || targetLen > Int(UInt8.max) || offsetLength == 0 {
      return
    }

    if !converter.resizeSegment(segments, conversionRequest, segmentIndex, offsetLength) {
      return
    }

    updateCandidateList()
    // Clears selected index of a focused segment and trailing segments.
    // TODO(hsumita): Keep the indices if the segment type is FIXED_VALUE.
    resizeSelectedCandidateIndices(segments.conversionSegmentsSize)
    if segmentIndex + 1 < selectedCandidateIndices.count {
      for j in (segmentIndex + 1)..<selectedCandidateIndices.count {
        selectedCandidateIndices[j] = 0
      }
    }
    updateSelectedCandidateIndex()
  }

  /// Resizes the focused segment.
  public func segmentWidthExpand(_ composer: Composer) {
    resizeSegmentWidth(composer, 1)
  }

  public func segmentWidthShrink(_ composer: Composer) {
    resizeSegmentWidth(composer, -1)
  }

  /// Moves the focus of candidates.
  public func candidateNext(_ composer: Composer) {
    resetResult()

    maybeExpandPrediction(composer)
    candidateList.moveNext()
    candidateListVisible = true
    updateSelectedCandidateIndex()
    segmentFocus()
  }

  public func candidateNextPage() {
    resetResult()

    candidateList.moveNextPage()
    candidateListVisible = true
    updateSelectedCandidateIndex()
    segmentFocus()
  }

  public func candidatePrev() {
    resetResult()

    candidateList.movePrev()
    candidateListVisible = true
    updateSelectedCandidateIndex()
    segmentFocus()
  }

  public func candidatePrevPage() {
    resetResult()

    candidateList.movePrevPage()
    candidateListVisible = true
    updateSelectedCandidateIndex()
    segmentFocus()
  }

  /// Moves the focus to the candidate represented by the id.
  public func candidateMoveToId(_ id: Int, _ composer: Composer) {
    resetResult()

    if checkState(State.suggestion) {
      // This method makes a candidate focused but SUGGESTION state cannot
      // have focused candidate.
      // To solve this conflict we call Predict() method to transit to
      // PREDICTION state, on which existence of focused candidate is acceptable.
      _ = predict(composer)
    }

    candidateList.moveToId(id)
    candidateListVisible = false
    updateSelectedCandidateIndex()
    segmentFocus()
  }

  /// Moves the focus to the index from the beginning of the current page.
  public func candidateMoveToPageIndex(_ index: Int) {
    resetResult()

    candidateList.moveToPageIndex(index)
    candidateListVisible = false
    updateSelectedCandidateIndex()
    segmentFocus()
  }

  /// Moves the focus to the candidate represented by the shortcut.  If
  /// the shortcut is not bound with any candidate, false is returned.
  public func candidateMoveToShortcut(_ shortcut: UInt8) -> Bool {
    if !candidateListVisible {
      return false
    }

    let shortcuts = getCandidateShortcuts(selectionShortcut)
    if shortcuts.isEmpty {
      return false
    }

    // Check if the input character is in the shortcut.
    // TODO(komatsu): Support non ASCII characters such as Unicode and
    // special keys.
    guard let index = Array(shortcuts.utf8).firstIndex(of: shortcut) else {
      return false
    }

    if !candidateList.moveToPageIndex(index) {
      return false
    }
    updateSelectedCandidateIndex()
    resetResult()
    segmentFocus()
    return true
  }

  /// Operation for the candidate list.
  public func setCandidateListVisible(_ visible: Bool) {
    candidateListVisible = visible
  }

  /// Fills protocol buffers and update the internal status.
  public func popOutput(_ composer: Composer, _ output: inout Genmai_Commands_Output) {
    fillOutput(composer, &output)
    updatedCommand = .defaultCommand
    resetResult()
  }

  /// Fills preedit
  public func fillPreedit(_ composer: Composer, _ preedit: inout Genmai_Commands_Preedit) {
    EngineOutput.fillPreedit(composer, &preedit)
  }

  /// Fills protocol buffers
  public func fillOutput(_ composer: Composer, _ output: inout Genmai_Commands_Output) {
    if result.hasValue {
      fillResult(&output.result)
    }
    if checkState(State.composition) {
      if !composer.isEmpty() {
        EngineOutput.fillPreedit(composer, &output.preedit)
      }
    }

    maybeFillConfig(updatedCommand, config, &output)

    if !isActive() {
      return
    }

    // Composition on Suggestion
    if checkState(State.suggestion) {
      // When the suggestion comes from zero query suggestion, the
      // composer is empty.  In that case, preedit is not rendered.
      if !composer.isEmpty() {
        EngineOutput.fillPreedit(composer, &output.preedit)
      }
    } else if checkState(State.prediction | State.conversion) {
      // Conversion on Prediction or Conversion
      fillConversion(&output.preedit)
    }
    // Candidate list
    if checkState(State.suggestion | State.prediction | State.conversion) && candidateListVisible {
      fillCandidateWindow(&output.candidateWindow)
    }

    // All candidate words
    if checkState(State.suggestion | State.prediction | State.conversion) {
      fillAllCandidateWords(&output.allCandidateWords)
      // The bounds check must happen before mutable_incognito_candidate_words()
      // so that the field is not materialized (and hence
      // has_incognito_candidate_words() stays false) when the incognito
      // prediction produced no segments.
      if request.fillIncognitoCandidateWords
        && segmentIndex < incognitoSegments.conversionSegmentsSize
      {
        fillIncognitoCandidateWords(&output.incognitoCandidateWords)
      }
    }

    // For debug. Removed candidate words through the conversion process.
    if checkState(State.suggestion | State.prediction | State.conversion) {
      EngineOutput.fillRemovedCandidates(
        segments.conversionSegment(segmentIndex), &output.removedCandidateWordsForDebug)
    }
  }

  /// Copies EngineConverter
  public func clone() -> any EngineConverterInterface {
    cloneEngineConverter()
  }

  func cloneEngineConverter() -> EngineConverter {
    let engineConverter = EngineConverter(converter, request, config)
    // `*engine_converter = *this;` (default copy operator).
    engineConverter.segments = segments.copy()
    engineConverter.incognitoSegments = incognitoSegments.copy()
    engineConverter.segmentIndex = segmentIndex
    engineConverter.previousSuggestions = previousSuggestions.copy()
    engineConverter.result = result
    engineConverter.candidateList.assign(from: candidateList)
    engineConverter.request = request
    engineConverter.config = config
    engineConverter.state = state
    engineConverter.requestType = requestType
    engineConverter.conversionPreferencesValue = conversionPreferencesValue
    engineConverter.selectionShortcut = selectionShortcut
    engineConverter.selectedCandidateIndices = selectedCandidateIndices
    engineConverter.updatedCommand = updatedCommand
    engineConverter.clientRevision = clientRevision
    engineConverter.candidateListVisible = candidateListVisible
    engineConverter.useCascadingWindow = useCascadingWindow

    if engineConverter.checkState(State.suggestion | State.prediction | State.conversion) {
      // UpdateCandidateList() is not simple setter and it uses some members.
      engineConverter.updateCandidateList()
      engineConverter.candidateList.moveToId(candidateList.focusedId)
      engineConverter.setCandidateListVisible(candidateListVisible)
    }

    return engineConverter
  }

  public func setSelectionShortcut(_ selectionShortcut: Genmai_Config_Config.SelectionShortcut) {
    self.selectionShortcut = selectionShortcut
  }

  public func setUseCascadingWindow(_ useCascadingWindow: Bool) {
    self.useCascadingWindow = useCascadingWindow
  }

  /// Resets the result value stored at the previous command.
  func resetResult() { result = Genmai_Commands_Result() }

  /// Resets the session state variables.
  func resetState() {
    state = State.composition
    segmentIndex = 0
    previousSuggestions.clear()
    candidateListVisible = false
    candidateList.clear()
    selectedCandidateIndices.removeAll()
    incognitoSegments.clear()
  }

  /// Notifies the converter that the current segment is focused.
  func segmentFocus() {
    if !converter.focusSegmentValue(
      segments, segmentIndex, getCandidateIndexForConverter(segmentIndex))
    {
      GenmaiLog.error("FocusSegmentValue failed")
    }
  }

  /// Notifies the converter that the current segment is fixed.
  /// Sets the segment type to FIXED_VALUE and moves the selected candidate to
  /// candidate(0).
  func segmentFix() {
    if !converter.commitSegmentValue(
      segments, segmentIndex, getCandidateIndexForConverter(segmentIndex))
    {
      GenmaiLog.warning("CommitSegmentValue failed")
      return
    }
    // CommitSegmentValue moves the selected candidate to candidate(0),
    // so reset the selected index for this segment to 0.
    if segmentIndex < selectedCandidateIndices.count {
      selectedCandidateIndices[segmentIndex] = 0
    }
  }

  /// Gets preedit from segment(index) to segment(index + size).
  func getPreedit(_ index: Int, _ size: Int) -> String {
    var preedit = ""
    if checkState(State.conversion) {
      let end = index + size
      var i = index
      while i < end {
        let segment = segments.conversionSegment(i)
        let candidate = getSelectedCandidate(i)
        if candidate.effectiveConvertedSegmentCount > 1 && !candidate.key.isEmpty {
          preedit.append(candidate.key)
        } else {
          preedit.append(segment.key)
        }
        i += getSegmentSpan(i)
      }
    } else {
      // In suggestion or prediction modes, each key may have
      // different keys, so content_key is used although it is
      // possibly dropped the conjugational word (ex. the content_key
      // of "はしる" is "はし").
      var i = index
      while i < size {
        preedit.append(getSelectedCandidate(i).contentKey)
        i += 1
      }
    }
    return preedit
  }

  /// Gets conversion from segment(index) to segment(index + size).
  func getConversion(_ index: Int, _ size: Int) -> String {
    var conversion = ""
    let end = index + size
    var i = index
    while i < end {
      conversion.append(getSelectedCandidateValue(i))
      i += getSegmentSpan(i)
    }
    return conversion
  }

  /// Updates ResultTokens of result_.
  func updateResultTokens(_ index: Int, _ size: Int) {
    func addTokens(
      _ contentKey: Substring, _ contentValue: Substring, _ functionalKey: Substring,
      _ functionalValue: Substring
    ) {
      var token1 = Genmai_Commands_ResultToken()
      token1.key = String(contentKey)
      token1.value = String(contentValue)
      result.tokens.append(token1)
      if !functionalKey.isEmpty || !functionalValue.isEmpty {
        var token2 = Genmai_Commands_ResultToken()
        token2.key = String(functionalKey)
        token2.value = String(functionalValue)
        result.tokens.append(token2)
      }
    }

    let end = index + size
    var i = index
    while i < end {
      let candIdx = getCandidateIndexForConverter(i)
      let candidate = segments.conversionSegment(i).candidate(candIdx)
      let firstTokenIdx = result.tokens.count

      for it in candidate.innerSegments() {
        addTokens(
          it.getContentKey(), it.getContentValue(), it.getFunctionalKey(),
          it.getFunctionalValue())
      }
      // Set lid and rid to the first and last tokens respectively.
      // Other lids and rids are filled with the default POS (i.e. -1 as unknown).
      let lastTokenIdx = result.tokens.count - 1
      result.tokens[firstTokenIdx].lid = Int32(candidate.lid)
      result.tokens[lastTokenIdx].rid = Int32(candidate.rid)
      i += getSegmentSpan(i)
    }
  }

  /// Gets consumed size of the preedit characters.
  /// c.f. CommitSuggestionInternal
  func getConsumedPreeditSize(_ index: Int, _ size: Int) -> Int {
    if checkState(State.suggestion | State.prediction) {
      let segment = segments.conversionSegment(0)
      let id = getCandidateIndexForConverter(0)
      let candidate = segment.candidate(id)
      return (candidate.attributes & Attribute.partiallyKeyConsumed != 0)
        ? Int(candidate.consumedKeySize) : Self.kConsumedAllCharacters
    }

    // If the selected candidate on the first segment covers all conversion
    // segments, all characters are considered consumed.
    if isFullSentenceCandidateSelected() {
      return Self.kConsumedAllCharacters
    }
    var result = 0
    var i = index
    while i < size {
      result += segments.conversionSegment(i).keyLen
      i += 1
    }
    return result
  }

  /// Performs the command if the command candidate is selected.  True
  /// is returned if a command is performed.
  func maybePerformCommandCandidate(_ index: Int, _ size: Int) -> Bool {
    // If a candidate has the command attribute, Cancel is performed
    // instead of Commit after executing the specified action.
    var i = index
    while i < size {
      let id = getCandidateIndexForConverter(i)
      let candidate = segments.conversionSegment(i).candidate(id)
      if candidate.attributes & Attribute.commandCandidate != 0 {
        switch candidate.command {
        case .defaultCommand:
          // Do nothing
          break
        case .enableIncognitoMode, .disableIncognitoMode, .enablePresentationMode,
          .disablePresentationMode:
          updatedCommand = candidate.command
        }
        return true
      }
      i += 1
    }
    return false
  }

  /// Updates internal states and fill result_.
  /// (The C++ `consumed_key_size` output is computed by the callers with
  /// `getConsumedPreeditSize` after a successful update.)
  func updateResult(_ index: Int, _ size: Int) -> Bool {
    // If command candidate is performed, result is not updated and
    // returns false.
    if maybePerformCommandCandidate(index, size) {
      return false
    }

    let preedit = getPreedit(index, size)
    let conversion = getConversion(index, size)
    EngineOutput.fillConversionResult(preedit, conversion, &result)
    EngineOutput.fillCursorOffsetResult(calculateCursorOffset(conversion), &result)
    updateResultTokens(index, size)
    return true
  }

  /// Fills the candidate list with the focused segment's candidates.
  /// This method does not clear the candidate list before processing.
  /// Only the candidates of which id is not existent in the candidate list
  /// are appended. Other candidates are ignored.
  func appendCandidateList() {
    // Meta candidates are added iff |candidate_list_| is empty.
    // This is because if |candidate_list_| is not empty we cannot decide
    // where to add meta candidates, especially use_cascading_window flag
    // is true (If there are two or more sub candidate lists, and existent
    // meta candidates are not located in the same list (distributed over
    // some lists), the most appropriate location to be added new meta candidates
    // cannot be decided).
    let addMetaCandidates = (candidateList.size == 0)

    let segment = segments.conversionSegment(segmentIndex)

    func getCandidateDedupKey(_ c: Candidate) -> String { c.value }

    var i = candidateList.nextAvailableId
    while i < segment.candidatesSize {
      let c = segment.candidate(i)
      candidateList.addCandidate(i, getCandidateDedupKey(c))
      // if candidate has spelling correction attribute,
      // always display the candidate to let user know the
      // miss spelled candidate.
      if i < 10 && (segment.candidate(i).attributes & Attribute.spellingCorrection != 0) {
        candidateListVisible = true
      }
      i += 1
    }

    let focused =
      (requestType != .suggestion && requestType != .partialSuggestion
        && requestType != .partialPrediction)
    candidateList.focused = focused

    if segment.metaCandidatesSize == 0 {
      // For suggestion mode, it is natural that T13N is not initialized.
      // For other modes, records |segment| just in case.
      return
    }

    if !addMetaCandidates {
      return
    }

    // Set transliteration candidates
    let transliterations: CandidateList
    if useCascadingWindow {
      transliterations = candidateList.addSubCandidateList()
      transliterations.rotate = false
      transliterations.focused = true

      let kT13nLabel = "そのほかの文字種"
      transliterations.name = kT13nLabel
    } else {
      transliterations = candidateList
    }

    // Add transliterations.
    for i in 0..<TransliterationType.numT13nTypes {
      let type = transliterationTypeArray[i]
      transliterations.addCandidateWithAttributes(
        getT13nId(type), getCandidateDedupKey(segment.metaCandidate(i)), getT13nAttributes(type))
    }
  }

  /// Clears the candidate list and fill it with the focused segment's
  /// candidates.
  func updateCandidateList() {
    candidateList.clear()
    appendCandidateList()
  }

  /// Returns the candidate index to be used by the converter.
  func getCandidateIndexForConverter(_ segmentIndex: Int) -> Int {
    // If segment_index does not point to the focused segment, the value
    // should be always zero.
    if segmentIndex != self.segmentIndex {
      return 0
    }
    return candidateList.focusedId
  }

  /// Returns the value of candidate to be used by the converter.
  func getSelectedCandidateValue(_ segmentIndex: Int) -> String {
    let id = getCandidateIndexForConverter(segmentIndex)
    let candidate = segments.conversionSegment(segmentIndex).candidate(id)
    if candidate.attributes & Attribute.commandCandidate != 0 {
      // Return an empty string, however this path should not be reached.
      return ""
    }
    return candidate.value
  }

  /// Returns the candidate to be used by the converter.
  func getSelectedCandidate(_ segmentIndex: Int) -> Candidate {
    let id = getCandidateIndexForConverter(segmentIndex)
    return segments.conversionSegment(segmentIndex).candidate(id)
  }

  /// Returns the number of segments covered by candidate at segment_index,
  /// clamped to avoid overlapping the focused segment.
  func getSegmentSpan(_ segmentIndex: Int) -> Int {
    let candidate = getSelectedCandidate(segmentIndex)
    let count = Int(candidate.effectiveConvertedSegmentCount)
    if segmentIndex < self.segmentIndex && segmentIndex + count > self.segmentIndex {
      return self.segmentIndex - segmentIndex
    }
    return count
  }

  /// Returns true if the selected candidate on the first segment covers all
  /// conversion segments.
  func isFullSentenceCandidateSelected() -> Bool {
    if segmentIndex != 0 {
      return false
    }
    return Int(getSelectedCandidate(0).effectiveConvertedSegmentCount)
      >= segments.conversionSegmentsSize
  }

  func fillConversion(_ preedit: inout Genmai_Commands_Preedit) {
    EngineOutput.fillConversion(segments, segmentIndex, candidateList.focusedId, &preedit)
  }

  func fillResult(_ result: inout Genmai_Commands_Result) {
    result = self.result
  }

  private static func category(for requestType: RequestType) -> Genmai_Commands_Category {
    switch requestType {
    case .conversion:
      return .conversion
    case .prediction:
      return .prediction
    case .suggestion:
      return .suggestion
    case .partialPrediction:
      // Not PREDICTION because we do not want to get focused candidate.
      return .suggestion
    case .partialSuggestion:
      return .suggestion
    default:
      GenmaiLog.warning("Unknown request type: \(requestType)")
      return .conversion
    }
  }

  func fillCandidateWindow(_ candidateWindow: inout Genmai_Commands_CandidateWindow) {
    if !candidateListVisible {
      return
    }

    // The position to display the candidate window.
    var position = 0
    var i = 0
    while i < segmentIndex {
      position += Util.charsLen(getSelectedCandidate(i).value)
      i += getSegmentSpan(i)
    }

    if segmentIndex >= segments.conversionSegmentsSize {
      GenmaiLog.warning(
        "Invalid segment_index_: \(segmentIndex), segments_size: \(segments.conversionSegmentsSize)"
      )
      return
    }

    let segment = segments.conversionSegment(segmentIndex)
    EngineOutput.fillCandidateWindow(segment, candidateList, position, &candidateWindow)

    // Shortcut keys
    if checkState(State.prediction | State.conversion) {
      EngineOutput.fillShortcuts(getCandidateShortcuts(selectionShortcut), &candidateWindow)
    }

    // Store category
    candidateWindow.category = Self.category(for: requestType)

    if candidateWindow.hasUsages {
      candidateWindow.usages.category = .usage
    }
    if candidateWindow.hasSubCandidateWindow {
      // TODO(komatsu): Subcandidate is not always for transliterations.
      // The category of the sub candidate window should be checked.
      candidateWindow.subCandidateWindow.category = .transliteration
    }

    // Store display type
    candidateWindow.displayType = .main
    if candidateWindow.hasUsages {
      candidateWindow.usages.displayType = .cascade
    }
    if candidateWindow.hasSubCandidateWindow {
      // TODO(komatsu): Sub candidate window is not always for transliterations.
      // The category of the sub candidate window should be checked.
      candidateWindow.subCandidateWindow.displayType = .cascade
    }

    // Store footer.
    EngineOutput.fillFooter(candidateWindow.category, &candidateWindow)
  }

  /// Fills protocol buffers with all flatten candidate words.
  func fillAllCandidateWords(_ candidates: inout Genmai_Commands_CandidateList) {
    let category = Self.category(for: requestType)

    if segmentIndex >= segments.conversionSegmentsSize {
      GenmaiLog.warning(
        "Invalid segment_index_: \(segmentIndex), segments_size: \(segments.conversionSegmentsSize)"
      )
      return
    }
    let segment = segments.conversionSegment(segmentIndex)
    EngineOutput.fillAllCandidateWords(segment, candidateList, category, &candidates)
  }

  func fillIncognitoCandidateWords(_ candidates: inout Genmai_Commands_CandidateList) {
    // |incognito_segments_| can be empty when the incognito prediction failed
    // to produce suggestions (e.g. no user history in incognito mode).  The
    // caller (FillOutput) checks the size before materializing the output field,
    // so this precondition is guaranteed to hold here.
    let segment = incognitoSegments.conversionSegment(segmentIndex)
    for i in 0..<segment.candidatesSize {
      var candidateWordProto = Genmai_Commands_CandidateWord()
      let cand = segment.candidate(i)

      candidateWordProto.id = Int32(i)
      candidateWordProto.index = UInt32(i)
      candidateWordProto.key = cand.key
      candidateWordProto.value = cand.value
      candidates.candidates.append(candidateWordProto)
    }
  }

  /// Sets setting by the request;
  public func setRequest(_ request: Genmai_Commands_Request) {
    self.request = request
    candidateList.pageSize = Int(request.candidatePageSize)
  }

  /// Sets setting by the config;
  public func setConfig(_ config: Genmai_Config_Config) {
    self.config = config
    updatedCommand = .defaultCommand
    selectionShortcut = config.selectionShortcut
    useCascadingWindow = config.useCascadingWindow
  }

  /// Set setting by the context.
  public func onStartComposition(_ context: Genmai_Commands_Context) {
    var revisionChanged = false
    if context.hasRevision {
      revisionChanged = (context.revision != clientRevision)
      clientRevision = context.revision
    }
    if !context.hasPrecedingText {
      // In this case, reset history segments when the revision is mismatched.
      if revisionChanged {
        converter.resetConversion(segments)
      }
      return
    }

    let precedingText = context.precedingText
    // If preceding text is empty, it is OK to reset the history segments by
    // calling ResetConversion.
    if precedingText.isEmpty {
      converter.resetConversion(segments)
      return
    }

    // Hereafter, we keep the existing history segments as long as it is
    // consistent with the preceding text even when revision_changed is true.
    var historyText = ""
    for segment in segments.all {
      if segment.segmentType != .history {
        break
      }
      if segment.candidatesSize == 0 {
        break
      }
      historyText.append(segment.candidate(0).value)
    }

    if !historyText.isEmpty {
      // Compare |preceding_text| with |history_text| to check if the history
      // segments are still valid or not.
      if precedingText.utf8.count > historyText.utf8.count {
        if precedingText.hasByteSuffix(historyText) {
          // History segments seem to be consistent with preceding text.
          return
        }
      } else {
        if historyText.hasByteSuffix(precedingText) {
          // History segments seem to be consistent with preceding text.
          return
        }
      }
    }

    // Here we reconstruct history segments from |preceding_text| regardless
    // of revision mismatch. If it fails the history segments is cleared anyway.
    if !converter.reconstructHistory(segments, precedingText) {
      GenmaiLog.warning("ReconstructHistory failed.")
    }
  }

  // Handles selected_indices for usage stats.
  func updateSelectedCandidateIndex() {
    let index: Int
    let focusedCandidate = candidateList.focusedCandidate
    if focusedCandidate.hasSubcandidateList() {
      let t13nIndex = focusedCandidate.subcandidateList.focusedIndex
      index = -1 - t13nIndex
    } else {
      // TODO(hsumita): Use id instead of focused index.
      index = candidateList.focusedIndex
    }
    selectedCandidateIndices[segmentIndex] = index
  }

  func initializeSelectedCandidateIndices() {
    selectedCandidateIndices.removeAll()
    resizeSelectedCandidateIndices(segments.conversionSegmentsSize)
  }

  private func resizeSelectedCandidateIndices(_ newSize: Int) {
    if selectedCandidateIndices.count > newSize {
      selectedCandidateIndices.removeLast(selectedCandidateIndices.count - newSize)
    } else if selectedCandidateIndices.count < newSize {
      selectedCandidateIndices.append(
        contentsOf: repeatElement(0, count: newSize - selectedCandidateIndices.count))
    }
  }

  /// Usage stats are not recorded (the C++ only builds the stat name).
  func updateCandidateStats(_ baseName: String, _ index: Int32) {}

  func commitSegmentsSize(_ commitState: EngineConverterStates, _ context: Genmai_Commands_Context)
  {
    var commitSegmentSize = 0
    switch commitState {
    case State.composition:
      commitSegmentSize = 0
    case State.suggestion, State.prediction:
      commitSegmentSize = 1
    case State.conversion:
      commitSegmentSize = segments.conversionSegmentsSize
    default:
      GenmaiLog.error("Unexpected state: \(commitState)")
    }
    commitSegmentsSize(commitSegmentSize)
  }

  func commitSegmentsSize(_ commitSegmentsSize: Int) {
    precondition(commitSegmentsSize <= selectedCandidateIndices.count)
    selectedCandidateIndices.removeFirst(commitSegmentsSize)
  }

  /// Sets request type and update the engine_converter's state
  func setRequestType(_ requestType: RequestType, _ options: inout ConversionRequest.Options) {
    self.requestType = requestType
    options.requestType = requestType
  }
}
