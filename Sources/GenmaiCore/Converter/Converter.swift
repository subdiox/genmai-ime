// Port of mozc/src/converter/converter.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - engine::Modules (engine/modules.h) is not part of the converter port. The
//   converter only needs the POS matcher, the user dictionary and the
//   supplemental model from it, abstracted by the `ConverterModules`
//   protocol below; engine::Modules should conform to it. Likewise only the
//   two methods of engine::SupplementalModelInterface used here are
//   abstracted by `ConverterSupplementalModel` (the engine's
//   SupplementalModelInterface should refine it).
// - The factories receive `any ConverterModules`; the engine's factories can
//   capture (or downcast to) the concrete modules.
// - The predictor is created after `self` is initialized (it needs `self` as
//   ConverterInterface), so it is stored as an implicitly unwrapped optional.
// - The revert id is drawn with `UInt64.random(in: 1...UInt64.max)`
//   (absl::Uniform over the closed interval in C++).

import GenmaiBase
import GenmaiProtocol

/// The subset of engine::SupplementalModelInterface used by the converter.
public protocol ConverterSupplementalModel: AnyObject {
  /// Returns true if supplemental model is available.
  func isAvailable() -> Bool
  /// Performs general post correction on `results`.
  func postCorrect(_ request: ConversionRequest, _ results: inout [PredictionResult])
}

/// engine::SupplementalModelStub (no-op).
public final class ConverterSupplementalModelStub: ConverterSupplementalModel, @unchecked Sendable {
  public init() {}
  public func isAvailable() -> Bool { false }
  public func postCorrect(_ request: ConversionRequest, _ results: inout [PredictionResult]) {}
}

/// The subset of engine::Modules used by the converter.
public protocol ConverterModules: AnyObject {
  func getPosMatcher() -> PosMatcher
  func getUserDictionary() -> any UserDictionaryInterface
  func getSupplementalModel() -> any ConverterSupplementalModel
}

private let kErrorIndex = -1

private func getSegmentIndex(_ segments: Segments, _ segmentIndex: Int) -> Int {
  let historySegmentsSize = segments.historySegmentsSize
  let result = historySegmentsSize + segmentIndex
  if result >= segments.segmentsSize {
    return kErrorIndex
  }
  return result
}

/// Consolidates a multi-segment candidate (span > 1) at `raw_segment_index`
/// into a single segment by updating the segment key to the candidate's full
/// reading, erasing covered trailing segments, and decrementing
/// `converted_segment_count` accordingly.
private func mergeMultiSegmentCandidate(
  _ segments: Segments, _ rawSegmentIndex: Int, _ forceUpdateKey: Bool = false
) {
  let seg = segments.mutableSegment(rawSegmentIndex)
  if seg.candidatesSize == 0 {
    return
  }
  let topCand = seg.mutableCandidate(0)
  let span = Int(topCand.effectiveConvertedSegmentCount)
  if (forceUpdateKey || span > 1) && !topCand.key.isEmpty {
    seg.setKey(topCand.key)
  }
  if span > 1 && rawSegmentIndex + 1 < segments.segmentsSize {
    let remainingSegments = segments.segmentsSize - 1 - rawSegmentIndex
    let eraseCount = min(span - 1, remainingSegments)
    segments.eraseSegments(rawSegmentIndex + 1, eraseCount)
    topCand.convertedSegmentCount -= UInt32(eraseCount)
  }
}

private func shouldInitSegmentsForPrediction(_ key: String, _ segments: Segments) -> Bool {
  // (1) If the segment size is 0, invoke SetKey because the segments is not
  //   correctly prepared.
  //   If the key of the segments differs from the input key,
  //   invoke SetKey because current segments should be completely reset.
  // (2) Otherwise keep current key and candidates.
  //
  // This SetKey omitting is for mobile predictor.
  // On normal inputting, we are showing suggestion results. When users
  // push expansion button, we will add prediction results just after the
  // suggestion results. For this, we don't reset segments for prediction.
  // However, we don't have to do so for suggestion. Here, we are deciding
  // whether the input key is changed or not by using segment key. This is
  // not perfect because for roman input, conversion key is not updated by
  // incomplete input, for example, conversion key is "あ" for the input "a",
  // and will still be "あ" for the input "ak". For avoiding mis-reset of
  // the results, we will reset always for suggestion request type.
  segments.conversionSegmentsSize == 0 || !segments.conversionSegment(0).key.bytesEqual(key)
}

private func isValidSegments(_ request: ConversionRequest, _ segments: Segments) -> Bool {
  let isMobile = request.request().zeroQuerySuggestion && request.request().mixedConversion

  // All segments should have candidate
  for segment in segments.all {
    if segment.candidatesSize != 0 {
      continue
    }
    // On mobile, we don't distinguish candidates and meta candidates
    // So it's ok if we have meta candidates even if we don't have candidates
    // TODO(team): we may remove mobile check if other platforms accept
    // meta candidate only segment
    if isMobile && segment.metaCandidatesSize != 0 {
      continue
    }
    return false
  }
  return true
}

private func validateConversionRequestForPrediction(_ request: ConversionRequest) -> Bool {
  switch request.requestType() {
  case .conversion:
    // Conversion request is not for prediction.
    return false
  case .prediction, .suggestion:
    // Typical use case.
    return true
  case .partialPrediction, .partialSuggestion:
    // Partial prediction/suggestion request is applicable only if the
    // cursor is in the middle of the composer.
    let cursor = request.composer().getCursor()
    return cursor != 0 || cursor != request.composer().getLength()
  case .reverseConversion:
    fatalError("unreachable")
  }
}

public final class Converter: ConverterInterface, @unchecked Sendable {
  public typealias ImmutableConverterFactory =
    (any ConverterModules) -> any ImmutableConverterInterface

  public typealias PredictorFactory =
    (any ConverterModules, any ConverterInterface, any ImmutableConverterInterface) ->
    any PredictorInterface

  public typealias RewriterFactory = (any ConverterModules) -> any RewriterInterface

  private let modulesStorage: any ConverterModules
  private let immutableConverterStorage: any ImmutableConverterInterface
  private var predictorStorage: (any PredictorInterface)!
  private var rewriterStorage: (any RewriterInterface)!

  private let posMatcher: PosMatcher
  private let userDictionary: any UserDictionaryInterface
  private let historyReconstructor: HistoryReconstructor
  private let reverseConverter: ReverseConverter
  private let generalNounId: UInt16

  /// Converter is initialized with the factory methods of ImmutableConverter,
  /// Predictor and Rewriter, so that all these sub components share the
  /// same resources and modules. Converter creates these sub modules and
  /// holds their ownership.
  public init(
    _ modules: any ConverterModules,
    _ immutableConverterFactory: ImmutableConverterFactory,
    _ predictorFactory: PredictorFactory,
    _ rewriterFactory: RewriterFactory
  ) {
    modulesStorage = modules
    immutableConverterStorage = immutableConverterFactory(modules)
    posMatcher = modules.getPosMatcher()
    userDictionary = modules.getUserDictionary()
    historyReconstructor = HistoryReconstructor(modules.getPosMatcher())
    reverseConverter = ReverseConverter(immutableConverterStorage)
    generalNounId = posMatcher.getGeneralNounId()
    predictorStorage = predictorFactory(modules, self, immutableConverterStorage)
    rewriterStorage = rewriterFactory(modules)
  }

  public var predictor: any PredictorInterface { predictorStorage }
  public var rewriter: any RewriterInterface { rewriterStorage }
  public var immutableConverter: any ImmutableConverterInterface { immutableConverterStorage }
  public var modules: any ConverterModules { modulesStorage }

  public func startConversion(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    assert(request.requestType() == .conversion)

    let key = request.key()
    if key.isEmpty {
      return false
    }

    segments.initForConvert(key)
    applyConversion(segments, request)
    return isValidSegments(request, segments)
  }

  public func startReverseConversion(_ segments: Segments, _ key: String) -> Bool {
    segments.clear()
    if key.isEmpty {
      return false
    }
    segments.initForConvert(key)

    return reverseConverter.reverseConvert(key, segments)
  }

  /// Sets all the candidates' attribute PARTIALLY_KEY_CONSUMED
  /// and consumed_key_size if the attribute is not set.
  static func maybeSetConsumedKeySizeToCandidate(_ consumedKeySize: Int, _ candidate: Candidate) {
    if candidate.attributes & Attribute.partiallyKeyConsumed != 0 {
      // If PARTIALLY_KEY_CONSUMED is set already,
      // the candidate has set appropriate attribute and size by predictor.
      return
    }
    candidate.attributes |= Attribute.partiallyKeyConsumed
    candidate.consumedKeySize = UInt32(consumedKeySize)
  }

  /// Sets all the candidates' attribute PARTIALLY_KEY_CONSUMED
  /// and consumed_key_size if the attribute is not set.
  static func maybeSetConsumedKeySizeToSegment(_ consumedKeySize: Int, _ segment: Segment) {
    for i in 0..<segment.candidatesSize {
      maybeSetConsumedKeySizeToCandidate(consumedKeySize, segment.mutableCandidate(i))
    }
    for i in 0..<segment.metaCandidatesSize {
      maybeSetConsumedKeySizeToCandidate(consumedKeySize, segment.mutableMetaCandidate(i))
    }
  }

  public func startPrediction(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    assert(validateConversionRequestForPrediction(request))

    let key = request.key()
    if shouldInitSegmentsForPrediction(key, segments) {
      segments.initForConvert(key)
    }

    if !predictForRequestWithSegments(request, segments) {
      // Prediction can fail for keys like "12". Even in such cases, rewriters
      // (e.g., number and variant rewriters) can populate some candidates.
      // Therefore, this is not an error.
    }
    applyPostProcessing(request, segments)
    return isValidSegments(request, segments)
  }

  public func startPredictionWithPreviousSuggestion(
    _ request: ConversionRequest, _ previousSegment: Segment, _ segments: Segments
  ) -> Bool {
    let result = startPrediction(request, segments)
    segments.prependCandidates(previousSegment)
    if !result {
      return false
    }

    applyPostProcessing(request, segments)
    return isValidSegments(request, segments)
  }

  public func prependCandidates(
    _ request: ConversionRequest, _ segment: Segment, _ segments: Segments
  ) {
    segments.prependCandidates(segment)
    applyPostProcessing(request, segments)
  }

  private func applyPostProcessing(_ request: ConversionRequest, _ segments: Segments) {
    rewriteAndSuppressCandidates(request, segments)
    trimCandidates(request, segments)
    if request.requestType() == .partialSuggestion || request.requestType() == .partialPrediction {
      // Here 1st segment's key is the query string of
      // the partial prediction/suggestion.
      // e.g. If the composition is "わた|しは", the key is "わた".
      // If partial prediction/suggestion candidate is submitted,
      // all the characters which are located from the head to the cursor
      // should be submitted (in above case "わた" should be submitted).
      // To do this, PARTIALLY_KEY_CONSUMED and consumed_key_size should be
      // set. Note that this process should be done in a predictor because
      // we have to do this on the candidates created by rewriters.
      Converter.maybeSetConsumedKeySizeToSegment(
        Util.charsLen(request.key()), segments.mutableConversionSegment(0))
    }
  }

  public func finishConversion(_ request: ConversionRequest, _ segments: Segments) {
    // Consolidates multi-segment candidates (span > 1) into single segments
    // before committing to history and learning. During conversion, individual
    // segments are preserved for navigation and reversion, but upon commit,
    // covered trailing segments are merged and erased.
    let histSize = segments.historySegmentsSize
    let forceUpdateKey = request.requestType() != .conversion
    var i = 0
    while i < segments.conversionSegmentsSize {
      mergeMultiSegmentCandidate(segments, histSize + i, forceUpdateKey)
      i += 1
    }

    for segment in segments.all {
      // revert SUBMITTED segments to FIXED_VALUE
      // SUBMITTED segments are created by "submit first segment" operation
      // (ctrl+N for ATOK keymap).
      // To learn the conversion result, we should change the segment types
      // to FIXED_VALUE.
      if segment.segmentType == .submitted {
        segment.setSegmentType(.fixedValue)
      }
      if segment.candidatesSize > 0 {
        completePosIds(segment.mutableCandidate(0))
      }
    }

    populateReadingOfCommittedCandidateIfMissing(segments)

    // Sets unique revert id.
    // Clients store the last commit operations with this id.
    let revertId = UInt64.random(in: 1...UInt64.max)
    segments.setRevertId(revertId)

    let historyResult = ConverterUtil.historySegmentsToResult(segments)
    let committedResults = ConverterUtil.conversionSegmentsToResults(segments)
    let finishReq = ConversionRequestBuilder()
      .setConversionRequestView(request)
      .setHistoryResultView(historyResult)
      .build()
    rewriter.finish(finishReq, segments)
    predictor.finish(finishReq, committedResults, UInt32(truncatingIfNeeded: segments.revertId))

    // Remove the front segments except for some segments which will be
    // used as history segments.
    let startIndex = max(0, segments.segmentsSize - segments.maxHistorySegmentsSize)
    for _ in 0..<startIndex {
      segments.popFrontSegment()
    }

    // Remaining segments are used as history segments.
    for segment in segments.all {
      segment.setSegmentType(.history)
    }
  }

  public func cancelConversion(_ segments: Segments) {
    segments.clearConversionSegments()
  }

  public func resetConversion(_ segments: Segments) { segments.clear() }

  public func revertConversion(_ segments: Segments) {
    if segments.revertId == 0 {
      return
    }
    rewriter.revert(segments)
    predictor.revert(UInt32(truncatingIfNeeded: segments.revertId))
    segments.setRevertId(0)
  }

  public func deleteCandidateFromHistory(
    _ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int
  ) -> Bool {
    let segment = segments.segment(segmentIndex)
    let candidate = segment.candidate(candidateIndex)
    var result = false
    result = rewriter.clearHistoryEntry(segments, segmentIndex, candidateIndex) || result
    result = predictor.clearHistoryEntry(candidate.key, candidate.value) || result
    return result
  }

  public func reconstructHistory(_ segments: Segments, _ precedingText: String) -> Bool {
    segments.clear()
    return historyReconstructor.reconstructHistory(precedingText, segments)
  }

  private func commitSegmentValueInternal(
    _ segments: Segments, _ segmentIndexIn: Int, _ candidateIndex: Int,
    _ segmentType: Segment.SegmentType
  ) -> Bool {
    let segmentIndex = getSegmentIndex(segments, segmentIndexIn)
    if segmentIndex == kErrorIndex {
      return false
    }

    let segment = segments.mutableSegment(segmentIndex)
    let valuesSize = segment.candidatesSize
    if candidateIndex < -TransliterationType.numT13nTypes || candidateIndex >= valuesSize {
      return false
    }

    segment.setSegmentType(segmentType)
    segment.moveCandidate(candidateIndex, 0)

    if candidateIndex != 0 {
      segment.mutableCandidate(0).attributes |= Attribute.reranked
    }

    return true
  }

  public func commitSegmentValue(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int)
    -> Bool
  {
    commitSegmentValueInternal(segments, segmentIndex, candidateIndex, .fixedValue)
  }

  public func commitPartialSuggestionSegmentValue(
    _ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int,
    _ currentSegmentKey: String, _ newSegmentKey: String
  ) -> Bool {
    let rawSegmentIndex = getSegmentIndex(segments, segmentIndex)
    if !commitSegmentValueInternal(segments, segmentIndex, candidateIndex, .submitted) {
      return false
    }

    let segment = segments.mutableSegment(rawSegmentIndex)
    segment.setKey(currentSegmentKey)

    let newSegment = segments.insertSegment(rawSegmentIndex + 1)
    newSegment.setKey(newSegmentKey)

    return true
  }

  public func focusSegmentValue(_ segments: Segments, _ segmentIndexIn: Int, _ candidateIndex: Int)
    -> Bool
  {
    let segmentIndex = getSegmentIndex(segments, segmentIndexIn)
    if segmentIndex == kErrorIndex {
      return false
    }

    return rewriter.focus(segments, segmentIndex, candidateIndex)
  }

  public func commitSegments(_ segments: Segments, _ candidateIndex: [Int]) -> Bool {
    for i in 0..<candidateIndex.count {
      // 2nd argument must always be 0 because on each iteration
      // 1st segment is submitted.
      // Using 0 means submitting 1st segment iteratively.
      let rawSegmentIndex = getSegmentIndex(segments, 0)
      if !commitSegmentValueInternal(segments, 0, candidateIndex[i], .submitted) {
        return false
      }
      mergeMultiSegmentCandidate(segments, rawSegmentIndex)
    }
    return true
  }

  public func resizeSegment(
    _ segments: Segments, _ request: ConversionRequest, _ segmentIndex: Int, _ offsetLength: Int
  ) -> Bool {
    if request.requestType() != .conversion {
      return false
    }

    // invalid request
    if offsetLength == 0 {
      return false
    }

    if segmentIndex >= segments.conversionSegmentsSize {
      return false
    }

    let keyLen = segments.conversionSegment(segmentIndex).keyLen
    if keyLen == 0 {
      return false
    }

    let newSize = keyLen + offsetLength
    if newSize <= 0 || newSize > Int(UInt8.max) {
      return false
    }
    let newSizeArray: [UInt8] = [UInt8(newSize)]
    return resizeSegments(segments, request, segmentIndex, newSizeArray)
  }

  public func resizeSegments(
    _ segments: Segments, _ request: ConversionRequest, _ startSegmentIndexIn: Int,
    _ newSizeArray: [UInt8]
  ) -> Bool {
    if request.requestType() != .conversion {
      return false
    }

    let startSegmentIndex = getSegmentIndex(segments, startSegmentIndexIn)
    if startSegmentIndex == kErrorIndex {
      return false
    }

    if !segments.resize(startSegmentIndex, newSizeArray) {
      return false
    }

    applyConversion(segments, request)
    return true
  }

  public func commitContext(_ request: ConversionRequest) {
    predictor.commitContext(request)
  }

  /// Execute ImmutableConverter, Rewriters, SuppressionDictionary.
  /// ApplyConversion does not initialize the Segment unlike StartConversion.
  public func applyConversion(_ segments: Segments, _ request: ConversionRequest) {
    if !immutableConverter.convert(request.options(), segments) {
      // Conversion can fail for keys like "12". Even in such cases, rewriters
      // (e.g., number and variant rewriters) can populate some candidates.
      // Therefore, this is not an error.
    }

    maybeApplyPredictionToConversion(request, segments)
    applyPostProcessing(request, segments)
  }

  /// Resizes conversion segments to match inner segment boundaries of result
  /// and re-runs conversion if needed. Returns false if resizing/conversion
  /// fails.
  func resizeSegmentsByResult(
    _ request: ConversionRequest, _ result: PredictionResult, _ segments: Segments
  ) -> Bool {
    var newSizes: [UInt8] = []
    for innerSeg in result.innerSegments() {
      let charLen = Util.charsLen(innerSeg.getKey())
      if charLen == 0 || charLen > Int(UInt8.max) {
        return false
      }
      newSizes.append(UInt8(charLen))
    }

    var needResize = segments.conversionSegmentsSize < newSizes.count
    if !needResize {
      for i in 0..<newSizes.count {
        if segments.conversionSegment(i).keyLen != Int(newSizes[i]) {
          needResize = true
          break
        }
      }
    }

    if needResize {
      if !resizeSegments(segments, request, 0, newSizes) {
        // LOG(WARNING) << "Failed to resize or convert segments for result
        // match";
        return false
      }
    }

    return true
  }

  /// Applies each inner segment of `result` to the corresponding conversion
  /// segment at `target_pos`.
  func applyResultToSegments(
    _ result: PredictionResult, _ targetPos: Int, _ additionalAttributes: UInt32,
    _ segments: Segments
  ) {
    if result.innerSegments().size != segments.conversionSegmentsSize {
      return
    }

    var segIdx = 0
    for innerSeg in result.innerSegments() {
      if segIdx >= segments.conversionSegmentsSize { break }
      let currentSegIdx = segIdx
      segIdx += 1
      let segment = segments.mutableConversionSegment(currentSegIdx)

      // Find existing candidate with matching value.
      var existingIndex = -1
      for i in 0..<segment.candidatesSize {
        if segment.candidate(i).value.bytesEqual(innerSeg.getValue()) {
          existingIndex = i
          break
        }
      }

      // static_cast<size_t>(candidates_size() - 1) wraps to SIZE_MAX when the
      // segment is empty, so min() yields target_pos.
      let pos =
        segment.candidatesSize == 0 ? targetPos : min(targetPos, segment.candidatesSize - 1)
      if existingIndex >= 0 {
        segment.moveCandidate(existingIndex, pos)
        let cand = segment.mutableCandidate(pos)
        cand.cost = min(cand.cost, Int32(truncatingIfNeeded: result.cost))
        cand.wcost = min(cand.wcost, Int32(truncatingIfNeeded: result.wcost))
        cand.attributes |= (result.attributes | additionalAttributes)
        if currentSegIdx < result.innerSegmentBoundary.count {
          cand.innerSegmentBoundary = [result.innerSegmentBoundary[currentSegIdx]]
        }
      } else {
        let cand = (pos == 0) ? segment.pushFrontCandidate() : segment.insertCandidate(pos)!
        cand.key = String(innerSeg.getKey())
        cand.value = String(innerSeg.getValue())
        cand.contentKey = String(innerSeg.getContentKey())
        cand.contentValue = String(innerSeg.getContentValue())
        cand.lid = result.lid
        cand.rid = result.rid
        cand.wcost = Int32(truncatingIfNeeded: result.wcost)
        cand.cost = Int32(truncatingIfNeeded: result.cost)
        cand.attributes = (result.attributes | additionalAttributes)
        cand.consumedKeySize = result.consumedKeySize
        if currentSegIdx < result.innerSegmentBoundary.count {
          cand.innerSegmentBoundary = [result.innerSegmentBoundary[currentSegIdx]]
        }
      }
    }
  }

  /// Generates prediction results from UserHistoryPredictor and
  /// SupplementalModel (PostCorrection) for conversion.
  func predictForConversion(
    _ request: ConversionRequest, _ segments: Segments, _ defaultResult: PredictionResult
  ) -> [PredictionResult] {
    // Build ConversionRequest with history_result extracted from segments,
    // consistent with PredictForRequestWithSegments.
    let historyResult = ConverterUtil.historySegmentsToResult(segments)
    let convReq = ConversionRequestBuilder()
      .setConversionRequestView(request)
      .setHistoryResultView(historyResult)
      .build()

    // 1. Run SupplementalModel (PostCorrect).
    // Stop applying post correction when handwriting mode, consistent with
    // DictionaryPredictor::MaybeApplyPostCorrection.
    // For single-segment conversion, passes up to 5 N-best candidates so that
    // supplemental model works consistently with SUGGESTION mode.
    // TODO(taku): Extend multi-segment conversion to also pass N-best
    // candidates instead of only the single top composite result.
    var pcResults = ConverterUtil.conversionSegmentsToResults(segments)
    if !RequestUtil.isHandwriting(convReq) && modules.getSupplementalModel().isAvailable()
      && Rewriter.disableLegacyRewriter(convReq, Rewriter.LegacyRewriterType.disableCollocation)
    {
      modules.getSupplementalModel().postCorrect(convReq, &pcResults)
    }

    // 2. Run UserHistoryPredictor.
    var userHistoryResults: [PredictionResult] = []
    let kLegacyHistoryMode =
      Rewriter.LegacyRewriterType.disableUserSegmentHistory
      | Rewriter.LegacyRewriterType.disableUserBoundaryHistory
    if predictorStorage != nil && Rewriter.disableLegacyRewriter(convReq, kLegacyHistoryMode) {
      userHistoryResults = predictor.convert(convReq)
    }

    let isDefaultMultiSegment = segments.conversionSegmentsSize > 1
    let enableMultiSegment =
      request.request().decoderExperimentParams.enableMultiSegmentCandidate

    // Fail-safe for legacy single-segment resizing (!enable_multi_segment):
    // Older history entries lack inner_segment boundary information,
    // indicated by Attribute::USER_HISTORY_EMPTY_INNER_SEGMENT_BOUNDARY.
    // When enable_multi_segment is false and top_result is a single-segment
    // prediction without boundary info, resizing a multi-segment default
    // Viterbi would corrupt the structure.
    // When enable_multi_segment is true, multi-segment alignment handles
    // single-segment candidates as spanning multi-segment entries without
    // resizing.
    if !userHistoryResults.isEmpty {
      let historyTop = userHistoryResults[0]
      let isHistoryMultiSegment = historyTop.innerSegmentBoundary.count > 1
      let missingBoundaryError =
        !enableMultiSegment && !isHistoryMultiSegment && isDefaultMultiSegment
        && (historyTop.attributes & Attribute.userHistoryEmptyInnerSegmentBoundary) != 0
      if missingBoundaryError || historyTop.key.isEmpty || historyTop.value.isEmpty {
        userHistoryResults.removeAll()
      }
    }

    // 3. Merge results: user_history_results -> pc_results.
    return ConverterUtil.mergePredictionResults(userHistoryResults, pcResults)
  }

  /// Populates prediction results into conversion segments.
  func populatePredictionResultsToSegments(
    _ request: ConversionRequest, _ defaultResult: PredictionResult,
    _ results: [PredictionResult], _ segments: Segments
  ) {
    if results.isEmpty {
      return
    }

    let enableMultiSegment =
      request.request().decoderExperimentParams.enableMultiSegmentCandidate

    let topResult = results[0]
    let isDefaultMultiSegment = segments.conversionSegmentsSize > 1
    let topIsSameAsDefault =
      topResult.value.bytesEqual(defaultResult.value)
      && topResult.innerSegmentBoundary == defaultResult.innerSegmentBoundary

    if !enableMultiSegment {
      // If there is no change in the top candidate and the conversion has
      // multiple segments, do nothing.
      if topIsSameAsDefault && isDefaultMultiSegment {
        return
      }

      // 1. Resize segments if needed to match top_result's inner segment
      // boundaries.
      if !resizeSegmentsByResult(request, topResult, segments) {
        return
      }

      // 2. Apply results across conversion segments.
      // For single-segment conversion, apply up to 5 results.
      // If the 1st candidate is identical to the default result, apply
      // starting from candidate position 1.
      let isSingleSegment = !isDefaultMultiSegment && segments.conversionSegmentsSize == 1
      let startIdx = topIsSameAsDefault ? 1 : 0

      if isSingleSegment {
        let maxResults = min(results.count, 5)
        var i = startIdx
        while i < maxResults {
          let res = results[i]
          if !res.key.isEmpty && !res.value.isEmpty {
            applyResultToSegments(res, i, Attribute.defaultAttribute, segments)
          }
          i += 1
        }
      } else if !topIsSameAsDefault {
        // Multi-segment conversion: only apply top_result when it modifies
        // default.
        applyResultToSegments(topResult, 0, Attribute.defaultAttribute, segments)
      }
      return
    }

    // When enable_multi_segment is true:
    // Do NOT resize segments. Apply up to 5 results with multi-segment
    // alignment.
    let startIdx = topIsSameAsDefault ? 1 : 0
    let maxResults = min(results.count, 5)
    var i = startIdx
    while i < maxResults {
      ConverterUtil.applyResultToSegmentsMultiSegment(results[i], i, segments)
      i += 1
    }
  }

  /// Applies prediction-layer outputs (e.g., user history prediction and
  /// supplemental model post-correction) to conversion segments to minimize
  /// the behavioral discrepancy between prediction and conversion pipelines
  /// and allow conversion to benefit from improvements introduced in
  /// prediction.
  ///
  /// NOTE: This method is a short-term workaround. Because conversion
  /// currently requires tricky conversions and segment resizing between
  /// `Segments` and `prediction::Result`, the long-term goal is to eliminate
  /// dependency on `Segments` entirely in favor of a unified `Result`-based
  /// pipeline.
  func maybeApplyPredictionToConversion(_ request: ConversionRequest, _ segments: Segments) {
    // NOTE: Skip when `used_in_predictor_realtime_conversion` is true to
    // prevent PostCorrect and UserHistoryPredictor from being called twice
    // per keystroke (once inside RealtimeDecoder's nested StartConversion call
    // and once in DictionaryPredictor).
    if segments.conversionSegmentsSize == 0 || segments.resized
      || request.options().usedInPredictorRealtimeConversion
    {
      return
    }

    // 1. Build a single Result from the top candidates of default conversion
    // segments.
    guard let defaultResult = ConverterUtil.conversionSegmentsToResult(segments.conversionSegments)
    else {
      return
    }

    // 2. Generate and merge prediction results from UserHistoryPredictor and
    // SupplementalModel (PostCorrection).
    let results = predictForConversion(request, segments, defaultResult)
    if results.isEmpty {
      return
    }

    // 3. Populate prediction results into conversion segments (including
    // segment resizing if needed).
    populatePredictionResultsToSegments(request, defaultResult, results, segments)
  }

  /// Complete Left id/Right id if they are not defined.
  /// Some users don't push conversion button but directly
  /// input hiragana sequence only with composition mode. Converter
  /// cannot know which POS ids should be used for these directly-
  /// input strings. This function estimates IDs from value heuristically.
  func completePosIds(_ candidate: Candidate) {
    if candidate.value.isEmpty || candidate.key.isEmpty {
      return
    }

    if candidate.lid != 0 && candidate.rid != 0 {
      return
    }

    // Use general noun,  unknown word ("サ変") tend to produce
    // "する" "して", which are not always acceptable for non-sahen words.
    candidate.lid = generalNounId
    candidate.rid = generalNounId
    let kExpandSizeStart = 5
    let kExpandSizeDiff = 50
    let kExpandSizeMax = 80
    // In almost all cases, user chooses the top candidate.
    // In order to reduce the latency, first, expand 5 candidates.
    // If no valid candidates are found within 5 candidates, expand
    // candidates step-by-step.
    var size = kExpandSizeStart
    while size < kExpandSizeMax {
      let segments = Segments()
      segments.initForConvert(candidate.key)
      // use PREDICTION mode, as the size of segments after
      // PREDICTION mode is always 1, thanks to real time conversion.
      // However, PREDICTION mode produces "predictions", meaning
      // that keys of result candidate are not always the same as
      // query key. It would be nice to have
      // PREDICTION_REALTIME_CONVERSION_ONLY.
      var options = ConversionOptions()
      options.requestType = .prediction
      options.maxConversionCandidatesSize = size
      let request = ConversionRequestBuilder().setOptions(options).build()
      // In order to complete PosIds, call ImmutableConverter again.
      if !immutableConverter.convert(request.options(), segments) {
        // LOG(ERROR) << "ImmutableConverter::Convert() failed";
        return
      }
      for i in 0..<segments.segment(0).candidatesSize {
        let refCandidate = segments.segment(0).candidate(i)
        if refCandidate.value.bytesEqual(candidate.value) {
          candidate.lid = refCandidate.lid
          candidate.rid = refCandidate.rid
          candidate.cost = refCandidate.cost
          candidate.wcost = refCandidate.wcost
          candidate.structureCost = refCandidate.structureCost
          return
        }
      }
      size += kExpandSizeDiff
    }
  }

  /// Rewrites and applies the suppression dictionary.
  private func rewriteAndSuppressCandidates(_ request: ConversionRequest, _ segments: Segments) {
    // 1. Resize segments if needed.
    // Check if the segments need to be resized.
    if let resizeRequest = rewriter.checkResizeSegmentsRequest(request, segments) {
      if resizeSegments(segments, request, resizeRequest.segmentIndex, resizeRequest.segmentSizes)
      {
        // If the segments are resized, ResizeSegments recursively executed
        // RewriteAndSuppressCandidates with resized segments. No need to
        // execute them again.
        // TODO(b/381537649): Stop using the recursive call of
        // RewriteAndSuppressCandidates.
        return
      }
    }

    // 2. Rewrite candidates in each segment.
    if !rewriter.rewrite(request, segments) {
      return
    }

    // 3. Suppress candidates in each segment.
    // Optimization for common use case: Since most of users don't use
    // suppression dictionary and we can skip the subsequent check.
    if !userDictionary.hasSuppressedEntries() {
      return
    }
    // Although the suppression dictionary is applied at node-level in
    // dictionary layer, there's possibility that bad words are generated from
    // multiple nodes and by rewriters. Hence, we need to apply it again at the
    // last stage of converter.
    for segment in segments.conversionSegments {
      var j = 0
      while j < segment.candidatesSize {
        let cand = segment.candidate(j)
        if userDictionary.isSuppressedEntry(cand.key, cand.value) {
          segment.eraseCandidate(j)
        } else {
          j += 1
        }
      }
    }
  }

  /// Limits the number of candidates based on a request.
  /// This method doesn't drop meta candidates for T13n conversion.
  private func trimCandidates(_ request: ConversionRequest, _ segments: Segments) {
    let requestProto = request.request()
    if !requestProto.hasCandidatesSizeLimit {
      return
    }

    let limit = Int(requestProto.candidatesSizeLimit)
    for segment in segments.conversionSegments {
      let candidatesSize = segment.candidatesSize
      // A segment should have at least one candidate.
      let candidatesLimit = max(1, limit - segment.metaCandidatesSize)
      if candidatesSize < candidatesLimit {
        continue
      }
      segment.eraseCandidates(candidatesLimit, candidatesSize - candidatesLimit)
    }
  }

  /// Reloads internal data, e.g., user dictionary, etc.
  @discardableResult
  public func reload() -> Bool {
    _ = modules.getUserDictionary().reload()
    return rewriter.reload() && predictor.reload()
  }

  /// Synchronizes internal data, e.g., user dictionary, etc.
  @discardableResult
  public func sync() -> Bool { rewriter.sync() && predictor.sync() }

  /// Waits for pending operations executed in different threads (suspends;
  /// no thread is blocked).
  @discardableResult
  public func wait() async -> Bool {
    await modules.getUserDictionary().waitForReloader()
    return await predictor.wait()
  }

  /// Adds `key` and `value` to the user history storage.
  /// Reverse conversion is used when the `key` is empty.
  @discardableResult
  public func addUserHistory(_ keyIn: String, _ valueIn: String) -> Bool {
    let value = stripAsciiWhitespace(valueIn)
    var key = stripAsciiWhitespace(keyIn)

    let kMaxValueSize = 128
    if value.isEmpty || value.utf8.count >= kMaxValueSize {
      return false
    }

    // When key is empty, use reverse conversion.
    if key.isEmpty {
      guard let reading = getReading(value, true) else { return false }
      key = reading
    }

    return predictor.addHistoryEntry(key, value)
  }

  /// Gets the reading of `text`.
  /// If `multi_segment` is true, `text` can consist of multiple segments.
  /// Otherwise, only allows `text` to be one dictionary entry.
  func getReading(_ text: String, _ multiSegment: Bool = false) -> String? {
    let segments = Segments()
    if !startReverseConversion(segments, text) {
      // LOG(ERROR) << "Reverse conversion failed to get the reading of " << text;
      return nil
    }

    if segments.conversionSegmentsSize == 0
      || (!multiSegment && segments.conversionSegmentsSize > 1)
    {
      // LOG(ERROR) << "Reverse conversion returned an invalid result for " << text;
      return nil
    }

    var reading = ""
    for segment in segments.all {
      if segment.candidatesSize == 0 { return nil }
      reading += segment.candidate(0).value
    }

    return reading
  }

  func populateReadingOfCommittedCandidateIfMissing(_ segments: Segments) {
    if segments.conversionSegmentsSize == 0 { return }

    let segment = segments.mutableConversionSegment(0)
    if segment.candidatesSize == 0 { return }

    let cand = segment.mutableCandidate(0)
    if !cand.key.isEmpty || cand.value.isEmpty { return }

    if cand.contentValue.bytesEqual(cand.value) {
      if let key = getReading(cand.value) {
        cand.key = key
        cand.contentKey = key
      }
      return
    }

    if cand.contentValue.isEmpty {
      // LOG(ERROR) << "Content value is empty: " << *cand;
      return
    }

    let functionalValue = cand.functionalValue
    if Util.getScriptType(functionalValue) != .hiragana {
      // LOG(ERROR) << "The functional value is not hiragana: " << *cand;
      return
    }
    if let contentKey = getReading(cand.contentValue) {
      cand.key = contentKey + functionalValue
      cand.contentKey = contentKey
    }
  }

  func predictForRequestWithSegments(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    let historyResult = ConverterUtil.historySegmentsToResult(segments)

    let convReq = ConversionRequestBuilder()
      .setConversionRequestView(request)
      .setHistoryResultView(historyResult)
      .build()

    let results = predictor.predict(convReq)

    let segment = segments.mutableConversionSegment(0)

    for result in results {
      ConverterUtil.populateCandidateFromResult(result, segment.addCandidate())
    }

    return !results.isEmpty
  }
}

/// absl::StripAsciiWhitespace.
private func stripAsciiWhitespace(_ s: String) -> String {
  func isSpace(_ b: UInt8) -> Bool {
    b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0B || b == 0x0C || b == 0x0D
  }
  let bytes = Array(s.utf8)
  var begin = 0
  var end = bytes.count
  while begin < end && isSpace(bytes[begin]) { begin += 1 }
  while end > begin && isSpace(bytes[end - 1]) { end -= 1 }
  return String(decoding: bytes[begin..<end], as: UTF8.self)
}
