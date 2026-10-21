// Port of mozc/src/prediction/predictor.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - The predictor members are `any PredictorInterface` (unique_ptr in C++).
// - The main initializer takes modules conforming to both PredictionModules
//   and UserHistoryPredictorModules (the subsets of engine::Modules used by
//   the two predictors).
// - PredictorTestPeer's private methods are `internal` (accessible with
//   @testable import).

import GenmaiBase

public final class Predictor: PredictorInterface, @unchecked Sendable {
  private static let kPredictionSizeForDesktop = 100

  // On mixed conversion mode PREDICTION (including PARTIAL_PREDICTION) behaves
  // like as conversion so the limit is same as conversion's one.
  private static let kPredictionSizeForMixedConersion = 200

  // Shared by dictionary_predictor and user_history_predictor.
  private let realtimeDecoder: RealtimeDecoder?

  private let dictionaryPredictor: any PredictorInterface
  private let userHistoryPredictor: any PredictorInterface

  public init(
    _ modules: any PredictionModules & UserHistoryPredictorModules,
    _ converter: any ConverterInterface, _ immutableConverter: any ImmutableConverterInterface
  ) {
    let realtimeDecoder = RealtimeDecoder(immutableConverter, converter)
    self.realtimeDecoder = realtimeDecoder
    dictionaryPredictor = DictionaryPredictor(modules, realtimeDecoder)
    userHistoryPredictor = UserHistoryPredictor(modules, realtimeDecoder)
  }

  /// Test only constructor.
  public init(
    _ modules: any PredictionModules, _ dictionaryPredictor: any PredictorInterface,
    _ userHistoryPredictor: any PredictorInterface
  ) {
    realtimeDecoder = nil
    self.dictionaryPredictor = dictionaryPredictor
    self.userHistoryPredictor = userHistoryPredictor
  }

  private static func isMixedConversionEnabled(_ request: ConversionRequest) -> Bool {
    request.request().mixedConversion
  }

  // Fills empty lid and rid of candidates with the candidates of the same
  // value.
  private static func maybeFillFallbackPos(_ results: inout [PredictionResult]) {
    var poslessResults: [PredictionBytesKey: Int] = [:]
    for i in results.indices {
      let result = results[i]
      let key = PredictionBytesKey(result.value)
      // Candidates with empty POS come before candidates with filled POS.
      if result.lid == 0 || result.rid == 0 {
        poslessResults[key] = i
        continue
      }
      guard let poslessIndex = poslessResults[key] else {
        continue
      }
      if results[poslessIndex].lid == 0 {
        results[poslessIndex].lid = result.lid
      }
      if results[poslessIndex].rid == 0 {
        results[poslessIndex].rid = result.rid
      }
      if results[poslessIndex].lid != 0 && results[poslessIndex].rid != 0 {
        poslessResults.removeValue(forKey: key)
      }
    }
  }

  public func predict(_ request: ConversionRequest) -> [PredictionResult] {
    assert(
      request.requestType() == .prediction || request.requestType() == .suggestion
        || request.requestType() == .partialPrediction
        || request.requestType() == .partialSuggestion)
    if request.requestType() == .conversion {
      return []
    }

    if request.config().presentationMode {
      return []
    }

    // TODO(taku): Introduces independent sub predictors for desktop and mixed
    // conversion.
    return Self.isMixedConversionEnabled(request)
      ? predictForMixedConversion(request) : predictForDesktop(request)
  }

  public func convert(_ request: ConversionRequest) -> [PredictionResult] {
    if request.requestType() != .conversion {
      return []
    }

    // Returns history candidates only.
    // TODO(all): Call dictionary_predictor->Convert() to unify the backend.
    return userHistoryPredictor.convert(request)
  }

  public func getPredictorName() -> String { "Predictor" }

  // Hook(s) for all mutable operations.
  public func finish(_ request: ConversionRequest, _ results: [PredictionResult], _ revertId: UInt32)
  {
    userHistoryPredictor.finish(request, results, revertId)
  }

  // Syncs user-modified context.
  public func commitContext(_ request: ConversionRequest) {
    userHistoryPredictor.commitContext(request)
  }

  // Since DictionaryPredictor is immutable, no need
  // to call DictionaryPredictor::Revert/Clear*/Finish methods.
  public func revert(_ revertId: UInt32) {
    userHistoryPredictor.revert(revertId)
  }

  @discardableResult
  public func clearAllHistory() -> Bool {
    userHistoryPredictor.clearAllHistory()
  }

  @discardableResult
  public func clearHistoryEntry(_ key: String, _ value: String) -> Bool {
    userHistoryPredictor.clearHistoryEntry(key, value)
  }

  @discardableResult
  public func addHistoryEntry(_ key: String, _ value: String) -> Bool {
    userHistoryPredictor.addHistoryEntry(key, value)
  }

  @discardableResult
  public func wait() async -> Bool { await userHistoryPredictor.wait() }

  @discardableResult
  public func sync() -> Bool { userHistoryPredictor.sync() }

  @discardableResult
  public func reload() -> Bool { userHistoryPredictor.reload() }

  private func predictForDesktop(_ request: ConversionRequest) -> [PredictionResult] {
    assert(!Self.isMixedConversionEnabled(request))

    var predictionSize = Self.kPredictionSizeForDesktop
    if request.requestType() == .suggestion {
      predictionSize = min(max(Int(request.config().suggestionsSize), 1), 9)
    }

    var userHistoryResults: [PredictionResult] = []
    var dictionaryResults: [PredictionResult] = []

    var options = request.options()
    options.maxUserHistoryPredictionCandidatesSize = predictionSize
    options.maxUserHistoryPredictionCandidatesSizeForZeroQuery = predictionSize
    let requestForPrediction = ConversionRequestBuilder()
      .setConversionRequestView(request)
      .setOptions(options)
      .build()

    userHistoryResults = userHistoryPredictor.predict(requestForPrediction)

    // Do not call dictionary_predictor if the size of candidates get
    // >= suggestions_size.
    if userHistoryResults.count < predictionSize {
      var options2 = requestForPrediction.options()
      options2.maxDictionaryPredictionCandidatesSize = predictionSize - userHistoryResults.count
      let requestForPrediction2 = ConversionRequestBuilder()
        .setConversionRequestView(requestForPrediction)
        .setOptions(options2)
        .build()
      dictionaryResults = dictionaryPredictor.predict(requestForPrediction2)
    }

    return mixCandidates(request, userHistoryResults, dictionaryResults)
  }

  private func predictForMixedConversion(_ request: ConversionRequest) -> [PredictionResult] {
    assert(Self.isMixedConversionEnabled(request))

    // No distinction between SUGGESTION and PREDICTION in mixed conversion
    // mode. Always PREDICTION mode is used.
    var options = request.options()
    options.maxUserHistoryPredictionCandidatesSize = 3
    options.maxUserHistoryPredictionCandidatesSizeForZeroQuery = 4
    options.maxDictionaryPredictionCandidatesSize = Self.kPredictionSizeForMixedConersion

    let requestForPredict = ConversionRequestBuilder()
      .setConversionRequestView(request)
      .setOptions(options)
      .build()

    var userHistoryResults: [PredictionResult] = []
    var dictionaryResults: [PredictionResult] = []

    switch request.requestType() {
    case .suggestion, .prediction:
      // Suggestion is triggered at every character insertion.
      // So here we should use slow predictors.
      userHistoryResults = userHistoryPredictor.predict(requestForPredict)
      dictionaryResults = dictionaryPredictor.predict(requestForPredict)
    case .partialSuggestion, .partialPrediction:
      // PARTIAL SUGGESTION can be triggered in a similar manner to that of
      // SUGGESTION. We don't call slow predictors by the same reason.
      dictionaryResults = dictionaryPredictor.predict(requestForPredict)
    default:
      break
    }

    var results = mixCandidates(request, userHistoryResults, dictionaryResults)

    Self.maybeFillFallbackPos(&results)

    return results
  }

  /// The results with WEAK_USER_HISTORY_PREDICTION are demoted so that they
  /// are not ranked at the top.
  static func demoteWeakUserHistory(
    _ request: ConversionRequest, _ results: inout [PredictionResult]
  ) {
    func isWeak(_ result: PredictionResult) -> Bool {
      (result.attributes & Attribute.weakUserHistoryPrediction) != 0
    }

    guard let front = results.first, isWeak(front) else {
      return
    }

    // When the top candidate is weak (e.g., multi-segment prefix user history
    // before reaching the last segment), promote only the first non-weak
    // exact-match candidate (or first non-weak candidate if none matches
    // request.key()) to position 0. This protects short exact-match
    // visibility at rank 1 while preserving the user's learned multi-segment
    // history at rank 2 (ahead of unlearned dictionary homophones), matching
    // the legacy UserSegmentHistoryRewriter behavior and
    // converter_util.cc::MergePredictionResults.
    //
    // TODO(taku): Once the UserSegmentHistoryRewriter migration finishes,
    // refactor and unify candidate scoring so explicit weak-candidate
    // demotion is no longer needed.
    let requestKey = request.key()
    var firstNoWeak = results.firstIndex { !isWeak($0) && $0.key.bytesEqual(requestKey) }
    if firstNoWeak == nil {
      firstNoWeak = results.firstIndex { !isWeak($0) }
    }
    if let firstNoWeak {
      // std::rotate(begin, first_no_weak, first_no_weak + 1)
      let moved = results.remove(at: firstNoWeak)
      results.insert(moved, at: 0)
    }
  }

  /// Mix user_history_results and dictionary_results.
  func mixCandidates(
    _ request: ConversionRequest, _ userHistoryResultsIn: [PredictionResult],
    _ dictionaryResultsIn: [PredictionResult]
  ) -> [PredictionResult] {
    var userHistoryResults = userHistoryResultsIn
    var dictionaryResults = dictionaryResultsIn
    if request.request().decoderExperimentParams.enableWeekdayZeroQueryPrediction
      && request.isZeroQuerySuggestion()
    {
      // Standalone parenthesized weekday zero-query candidates (e.g., " (水)")
      // are dynamically computed from the calendar date by ZeroQueryDecoder
      // and must never be replayed from persistent user history.
      userHistoryResults.removeAll { DecoderUtil.isStandaloneParenthesizedWeekday($0.value) }

      let lastHistoryValue = request.converterHistoryValue(1)
      let fullHistoryValue = request.converterHistoryValue(-1)
      let precedingText = request.context().precedingText
      if DecoderUtil.endsWithWeekdayExpression(lastHistoryValue)
        || DecoderUtil.endsWithWeekdayExpression(fullHistoryValue)
        || (lastHistoryValue.isEmpty && DecoderUtil.endsWithWeekdayExpression(precedingText))
      {
        dictionaryResults.removeAll { DecoderUtil.isStandaloneParenthesizedWeekday($0.value) }
      }
    }

    // Add NO_DELETABLE annotation when the top user history result is the
    // same as the top dictionary result.
    // when user_history_results.size() > 1, the decoder can still show the
    // second candidate, so user can be aware of the change after the
    // deleteion.
    if userHistoryResults.count == 1 && !dictionaryResults.isEmpty
      && userHistoryResults[0].key.bytesEqual(dictionaryResults[0].key)
      && userHistoryResults[0].value.bytesEqual(dictionaryResults[0].value)
    {
      userHistoryResults[0].attributes |= Attribute.noDeletable
    }

    var results: [PredictionResult] = []
    results.reserveCapacity(userHistoryResults.count + dictionaryResults.count)
    results.append(contentsOf: userHistoryResults)
    results.append(contentsOf: dictionaryResults)

    Self.demoteWeakUserHistory(request, &results)

    return results
  }
}
