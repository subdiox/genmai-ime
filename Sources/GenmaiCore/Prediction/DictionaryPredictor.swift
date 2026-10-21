// Port of mozc/src/prediction/dictionary_predictor.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - `open class` so that tests can override the aggregation methods
//   (MockAggregator); the private methods used by DictionaryPredictorTestPeer
//   are `internal` (accessible with @testable import).
// - `absl::Span<Result>` parameters are `inout [PredictionResult]`.
// - RerankAndFilterResults builds a heap with ResultCostLess and pops it; the
//   comparator is a total order, so the popped sequence equals the sorted
//   order and the results are sorted instead.
// - The previous top result (`AtomicSharedPtr<Result>` + atomic key length)
//   is kept under one lock.
// - `IsDebug()` is true in DEBUG builds (C++ `!NDEBUG`), otherwise
//   `verbose_level >= 1`.
// - MOZC_WORD_LOG is omitted (debug log only).

import Foundation
import GenmaiBase
import GenmaiProtocol
import Synchronization

open class DictionaryPredictor: PredictorInterface, @unchecked Sendable {
  private struct PrevTopState: Sendable {
    var result: PredictionResult?
    var keyLength: Int32 = 0
  }

  // Previous top result and request key length. (not result length).
  // When the previous and current result are consistent, we still keep
  // showing the previous result to prevent flickering.
  //
  // We can still keep the purely functional decoder design as
  // result = Decode("ABCD") = Decode(Decode("ABC"), "D") =
  //          Decode(Decode(Decode("AB"), "C"), "D")) ...
  // These variables work as a cache of previous results to prevent recursive
  // and expensive functional calls.
  private let prevTop = Mutex(PrevTopState())

  let decoder: RealtimeDecoder
  let connector: Connector
  let segmenter: Segmenter
  let suggestionFilter: SuggestionFilter
  let posMatcher: PosMatcher
  let generalSymbolId: UInt16
  let modules: any PredictionModules
  let dictionaryDecoder: DictionaryDecoder
  let handwritingDecoder: HandwritingDecoder
  let zeroQueryDecoder: ZeroQueryDecoder
  let englishDecoder: EnglishDecoder

  /// Initializes a predictor with given references to submodules.
  public init(_ modules: any PredictionModules, _ decoder: RealtimeDecoder) {
    self.decoder = decoder
    connector = modules.getConnector()
    segmenter = modules.getSegmenter()
    suggestionFilter = modules.getSuggestionFilter()
    posMatcher = modules.getPosMatcher()
    generalSymbolId = posMatcher.getGeneralSymbolId()
    self.modules = modules
    dictionaryDecoder = DictionaryDecoder(modules)
    handwritingDecoder = HandwritingDecoder(modules, decoder)
    zeroQueryDecoder = ZeroQueryDecoder(modules)
    englishDecoder = EnglishDecoder(modules)
  }

  // MARK: - Helpers (anonymous namespace in C++)

  static func isDebug(_ request: ConversionRequest) -> Bool {
    #if DEBUG
      return true
    #else
      return request.config().verboseLevel >= 1
    #endif
  }

  // Return true if the current keyboard is capable to type Latin characters
  // regardless of actual input mode. QWERTY keyboard is the typical case.
  private static func isQwertyMobileTable(_ request: ConversionRequest) -> Bool {
    let table = request.request().specialRomanjiTable
    return table == .qwertyMobileToHiragana || table == .qwertyMobileToHalfwidthascii
  }

  private static func isLanguageAwareInputEnabled(_ request: ConversionRequest) -> Bool {
    request.request().languageAwareInput == .languageAwareSuggestion
  }

  private static func isZeroQueryEnabled(_ request: ConversionRequest) -> Bool {
    request.request().zeroQuerySuggestion
  }

  private static func isMixedConversionEnabled(_ request: ConversionRequest) -> Bool {
    request.request().mixedConversion
  }

  private static func isTypingCorrectionEnabled(_ request: ConversionRequest) -> Bool {
    request.config().useTypingCorrection
  }

  private static func hasHistoryKeyLongerThanOrEqualTo(
    _ request: ConversionRequest, _ utf8Len: Int
  ) -> Bool {
    Util.charsLen(request.converterHistoryKey(1)) >= utf8Len
  }

  private static func isLongKeyForRealtimeCandidates(_ request: ConversionRequest) -> Bool {
    let kFewResultThreshold = 8
    return Util.charsLen(request.key()) >= kFewResultThreshold
  }

  private static func shouldAggregateRealTimeConversionResults(_ request: ConversionRequest)
    -> Bool
  {
    let kMaxRealtimeKeySize = 300  // 300 bytes in UTF8
    let key = request.key()
    if key.isEmpty || key.utf8.count >= kMaxRealtimeKeySize {
      // 1) If key is empty, realtime conversion doesn't work.
      // 2) If the key is too long, we'll hit a performance issue.
      return false
    }

    return request.requestType() == .partialSuggestion
      || request.config().useRealtimeConversion || isMixedConversionEnabled(request)
  }

  private static func isZipCodeRequest(_ key: String) -> Bool {
    if key.isEmpty {
      return false
    }

    var numChars = 0
    for c in key.unicodeScalars {
      if !(c.value >= 0x30 && c.value <= 0x39) && c.value != 0x2D {
        return false
      }
      numChars += 1
    }

    return numChars < 6
  }

  private static func isNotExceedingCutoffThreshold(
    _ request: ConversionRequest, _ results: [PredictionResult]
  ) -> Bool {
    results.count <= DecoderUtil.getCandidateCutoffThreshold(request.requestType())
  }

  private static func appendDescription(_ result: inout PredictionResult, _ text: String) {
    result.description += (result.description.isEmpty ? "" : " ") + text
  }

  private static func maybeFixRealtimeTopCost(
    _ request: ConversionRequest, _ results: inout [PredictionResult]
  ) {
    // Remember the minimum cost among those REALTIME
    // candidates that have the same key length as |request_key| so that we
    // can set a slightly smaller cost to REALTIME_TOP than these.
    var realtimeCostMin = PredictionResult.invalidCost
    var realtimeTopResult: Int?
    let requestKeySize = request.key().utf8.count
    for i in results.indices {
      let result = results[i]
      if (result.attributes & Attribute.realtimeTop) != 0 {
        realtimeTopResult = i
      }

      // Update the minimum cost for REALTIME candidates that have the same
      // key length as request_key.
      if (result.attributes & Attribute.realtimeConversion) != 0 && result.cost < realtimeCostMin
        && result.key.utf8.count == requestKeySize
      {
        realtimeCostMin = result.cost
      }
    }

    // Ensure that the REALTIME_TOP candidate has relatively smaller cost than
    // those of REALTIME candidates.
    if let realtimeTopResult, realtimeCostMin != PredictionResult.invalidCost {
      results[realtimeTopResult].cost = max(0, realtimeCostMin - 10)
    }
  }

  // MARK: - PredictorInterface

  public func predict(_ request: ConversionRequest) -> [PredictionResult] {
    if request.requestType() == .conversion {
      return []
    }

    // TODO(taku): Separate DesktopPredictor and MixedDecodingPredictor.
    var results: [PredictionResult]
    if Self.isMixedConversionEnabled(request) {
      results = aggregateResultsForMixedConversion(request)
      results.append(contentsOf: aggregateTypingCorrectedResultsForMixedConversion(request))
    } else {
      results = aggregateResultsForDesktop(request)
    }

    rewriteResultsForPrediction(request, &results)

    maybeRescoreResults(request, &results)

    // `results` are no longer used.
    return rerankAndFilterResults(request, results)
  }

  public func convert(_ request: ConversionRequest) -> [PredictionResult] { [] }
  public func finish(_ request: ConversionRequest, _ results: [PredictionResult], _ revertId: UInt32)
  {}
  public func revert(_ revertId: UInt32) {}
  public func commitContext(_ request: ConversionRequest) {}
  @discardableResult public func clearAllHistory() -> Bool { true }
  @discardableResult public func clearHistoryEntry(_ key: String, _ value: String) -> Bool { true }
  @discardableResult public func addHistoryEntry(_ key: String, _ value: String) -> Bool { true }
  @discardableResult public func sync() -> Bool { true }
  @discardableResult public func reload() -> Bool { true }
  @discardableResult public func wait() async -> Bool { true }

  public func getPredictorName() -> String { "DictionaryPredictor" }

  // MARK: - Implementation

  /// Populate conversion costs to `results`.
  func rewriteResultsForPrediction(
    _ request: ConversionRequest, _ results: inout [PredictionResult]
  ) {
    // Mixed conversion is the feature that mixes prediction and
    // conversion, meaning that results may include the candidates whose
    // key is exactly the same as the composition.  This mode is used in
    // mobile.
    let isMixedConversion = Self.isMixedConversionEnabled(request)

    if isMixedConversion {
      setPredictionCostForMixedConversion(request, &results)
    } else {
      setPredictionCost(request, &results)
    }

    Self.maybeFixRealtimeTopCost(request, &results)

    if !isMixedConversion {
      Self.removeMissSpelledCandidates(request, &results)
    }
  }

  // These methods will be moved to DesktopPredictor and
  // MixedDecodingPredictor.
  open func aggregateResultsForMixedConversion(_ request: ConversionRequest)
    -> [PredictionResult]
  {
    assert(Self.isMixedConversionEnabled(request))

    var results: [PredictionResult] = []
    let key = request.key()

    // Zero query prediction.
    if request.isZeroQuerySuggestion() {
      if Self.isZeroQueryEnabled(request) {
        results.append(contentsOf: zeroQueryDecoder.decode(request))
      }
      return results
    }

    if request.requestType() == .suggestion
      && (!request.config().useDictionarySuggest || Self.isZipCodeRequest(key))
    {
      return results
    }

    // Always aggregate realtime results when mixed conversion mode.
    aggregateRealtime(
      request, Self.getRealtimeCandidateMaxSize(request),
      request.options().useActualConverterForRealtimeConversion, &results)

    // In partial suggestion or prediction, only realtime candidates are used.
    if request.requestType() == .partialSuggestion || request.requestType() == .partialPrediction
    {
      return results
    }

    // TODO(taku): Removes the dependency to `min_unigram_key_len`.
    // This variable is only used in this method.
    let minUnigramKeyLen = aggregateUnigram(request, &results)

    if Self.isNotExceedingCutoffThreshold(request, results) {
      results.append(contentsOf: NumberDecoder(modules.getPosMatcher()).decode(request))
    }

    let kMinHistoryKeyLen = 3
    if Self.hasHistoryKeyLongerThanOrEqualTo(request, kMinHistoryKeyLen)
      && !request.isZeroQuerySuggestion()
    {
      dictionaryDecoder.aggregateBigram(request, &results)
    }

    // `min_unigram_key_len` is only used here.
    let keyLen = Util.charsLen(key)
    if Self.isLanguageAwareInputEnabled(request) && !RequestUtil.isLatinInputMode(request)
      && Self.isQwertyMobileTable(request) && keyLen >= minUnigramKeyLen
    {
      // QWERTY-Romaji mode to type Japanese. Handle the ごおgぇ -> Google.
      results.append(contentsOf: englishDecoder.decodeUsingRawInput(request))
    }

    if RequestUtil.isAutoPartialSuggestionEnabled(request)
      && Self.isNotExceedingCutoffThreshold(request, results)
    {
      dictionaryDecoder.aggregatePrefix(request, &results)
    }

    // Always aggregate single kanji results when mixed conversion mode.
    results.append(
      contentsOf: SingleKanjiDecoder(modules.getPosMatcher(), modules.getSingleKanjiDictionary())
        .decode(request))

    modules.predictionSupplementalModel().populateTypeCorrectedQuery(request, &results)

    return results
  }

  open func aggregateResultsForDesktop(_ request: ConversionRequest) -> [PredictionResult] {
    assert(!Self.isMixedConversionEnabled(request))

    var results: [PredictionResult] = []

    let key = request.key()

    if request.requestType() == .suggestion
      && (!request.config().useDictionarySuggest || Self.isZipCodeRequest(key))
    {
      return results
    }

    if Self.shouldAggregateRealTimeConversionResults(request) {
      aggregateRealtime(
        request, Self.getRealtimeCandidateMaxSize(request),
        request.options().useActualConverterForRealtimeConversion, &results)
    }

    // Desktop mode never sets PARTIAL mode, so we may use DCHECK after the
    // refactoring.
    if request.requestType() == .partialSuggestion || request.requestType() == .partialPrediction
    {
      return results
    }

    aggregateUnigram(request, &results)

    if Self.isNotExceedingCutoffThreshold(request, results) {
      results.append(contentsOf: NumberDecoder(modules.getPosMatcher()).decode(request))
    }

    let kMinHistoryKeyLen = 3
    if Self.hasHistoryKeyLongerThanOrEqualTo(request, kMinHistoryKeyLen) {
      dictionaryDecoder.aggregateBigram(request, &results)
    }

    return results
  }

  func aggregateTypingCorrectedResultsForMixedConversion(_ request: ConversionRequest)
    -> [PredictionResult]
  {
    let kMinTypingCorrectionKeyLen = 3
    if !Self.isTypingCorrectionEnabled(request)
      || Util.charsLen(request.key()) < kMinTypingCorrectionKeyLen
    {
      return []
    }

    guard let corrected = modules.predictionSupplementalModel().correctComposition(request) else {
      return []
    }

    var results: [PredictionResult] = []

    var numberAdded = false

    for query in corrected {
      let key = query.correction

      // Make ConversionRequest that uses conversion_segment(0).key() as
      // typing corrected key instead of ComposerData to avoid the original
      // key from being used during the candidate aggregation.
      // Kana modifier insensitive dictionary lookup is also disabled as
      // composition spellchecker has already fixed them.
      var options = request.options()
      options.kanaModifierInsensitiveConversion = false
      options.useAlreadyTypingCorrectedKey = true

      // Populates all information, e.g., history segments, from `request`,
      // and overrides the options and key.
      let correctedRequest = ConversionRequestBuilder()
        .setConversionRequestView(request)
        .setOptions(options)
        .setKey(key)
        .build()

      var correctedResults: [PredictionResult] = []

      // Since COMPLETION query already performs predictive lookup,
      // no need to run UNIGRAM and BIGRAM lookup.
      let isRealtimeOnly =
        query.type.contains(.completion) || request.requestType() == .partialSuggestion
        || request.requestType() == .partialPrediction

      if isRealtimeOnly {
        let kRealtimeSize = 1
        aggregateRealtime(
          correctedRequest, kRealtimeSize, /* insert_realtime_top_from_actual_converter= */ false,
          &correctedResults)
      } else {
        aggregateUnigram(correctedRequest, &correctedResults)

        let kRealtimeSize = 2
        aggregateRealtime(
          correctedRequest, kRealtimeSize, /* insert_realtime_top_from_actual_converter= */ false,
          &correctedResults)

        if !request.isZeroQuerySuggestion() {
          dictionaryDecoder.aggregateBigram(correctedRequest, &correctedResults)
        }

        if !numberAdded {
          let prevSize = correctedResults.count
          correctedResults.append(
            contentsOf: NumberDecoder(modules.getPosMatcher()).decode(correctedRequest))
          numberAdded = numberAdded || correctedResults.count > prevSize
        }
      }

      let manager = CharacterFormManager.getCharacterFormManager()

      // Appends the result with TYPING_CORRECTION attribute.
      for var result in correctedResults {
        populateTypeCorrectedQuery(query, &result)
        rewriteCandidateValues({ s in manager.convertConversionString(s) }, &result)
        results.append(result)
      }
    }

    return results
  }

  /// Aggregates basic unigram candidates from dictionary. Returns
  /// `min_unigram_key_len`.
  @discardableResult
  func aggregateUnigram(_ request: ConversionRequest, _ results: inout [PredictionResult]) -> Int {
    let keyLen = Util.charsLen(request.key())
    if keyLen == 0 {
      return 0
    }

    // User switches to Latin input mode type Latin characters or English
    // words. No need to perform Japanese decoding.
    if RequestUtil.isLatinInputMode(request) {
      // For SUGGESTION request in Desktop, We don't look up English words
      // when key length is one.
      let isMixedConversion = Self.isMixedConversionEnabled(request)
      let minKeyLen = (isMixedConversion || request.requestType() == .prediction) ? 1 : 2
      if keyLen >= minKeyLen {
        results.append(contentsOf: englishDecoder.decode(request))
      }
      return minKeyLen
    }

    if RequestUtil.isHandwriting(request) {
      let minKeyLen = 1
      if keyLen >= minKeyLen {
        results.append(contentsOf: handwritingDecoder.decode(request))
      }
      return minKeyLen
    }

    return dictionaryDecoder.aggregateUnigram(request, &results)
  }

  /// Aggregates results from the realtime decoder.
  func aggregateRealtime(
    _ request: ConversionRequest, _ realtimeCandidatesSize: Int,
    _ insertRealtimeTopFromActualConverter: Bool, _ results: inout [PredictionResult]
  ) {
    var options = request.options()
    options.maxConversionCandidatesSize = realtimeCandidatesSize
    options.useActualConverterForRealtimeConversion = insertRealtimeTopFromActualConverter

    let requestForRealtime = ConversionRequestBuilder()
      .setConversionRequestView(request)
      .setOptions(options)
      .build()

    results.append(contentsOf: decoder.decode(requestForRealtime))
  }

  /// Returns max size of realtime candidates.
  static func getRealtimeCandidateMaxSize(_ request: ConversionRequest) -> Int {
    let requestType = request.requestType()
    assert(
      requestType == .prediction || requestType == .suggestion
        || requestType == .partialPrediction || requestType == .partialSuggestion)
    if request.key().isEmpty {
      return 0
    }
    if RequestUtil.isHandwriting(request) {
      let kRealtimeCandidatesSizeForHandwriting = 3
      return kRealtimeCandidatesSizeForHandwriting
    }

    let sizeLimit = request.options().maxDictionaryPredictionCandidatesSize

    // Set the initial values to max_size and default_size.
    var maxSize = sizeLimit
    if request.options().createPartialCandidates {
      maxSize = 20
    }
    var defaultSize = 10

    // Reduce the number of candidates for long key.
    if isLongKeyForRealtimeCandidates(request) {
      maxSize = 8
      defaultSize = 5
    }

    // Cap the numbers of candidates to the size limit.
    maxSize = min(maxSize, sizeLimit)
    defaultSize = min(defaultSize, sizeLimit)

    let mixedConversion = isMixedConversionEnabled(request)
    switch requestType {
    case .prediction:
      return mixedConversion ? maxSize : defaultSize
    case .suggestion:
      // Fewer candidates are needed basically.
      // But on mixed_conversion mode we should behave like as conversion
      // mode.
      return mixedConversion ? defaultSize : 1
    case .partialPrediction:
      // This is kind of prediction so richer result than PARTIAL_SUGGESTION
      // is needed.
      return maxSize
    case .partialSuggestion:
      // PARTIAL_SUGGESTION works like as conversion mode so returning
      // some candidates is needed.
      return defaultSize
    default:
      assertionFailure("Unexpected request type: \(requestType)")
      return 0
    }
  }

  func rerankAndFilterResults(_ request: ConversionRequest, _ resultsIn: [PredictionResult])
    -> [PredictionResult]
  {
    let cursorAtTail = request.composer().getCursor() == request.composer().getLength()

    // Instead of sorting all the results, we construct a heap (C++).
    // The comparator is a total order, so popping the heap yields the sorted
    // order.
    var results = resultsIn
    results.sort(by: resultCostLess)

    let maxCandidatesSize = min(
      request.options().maxDictionaryPredictionCandidatesSize, results.count)

    let filter = ResultFilter(request, connector, suggestionFilter)

    var mergedAttributes: [PredictionBytesKey: UInt32] = [:]
    if Self.isDebug(request) {
      for result in results where !result.removed {
        mergedAttributes[PredictionBytesKey(result.value), default: 0] |= result.attributes
      }
    }

    var finalResults: [PredictionResult] = []

    for i in 0..<results.count {
      var result = results[i]
      if finalResults.count >= maxCandidatesSize || result.cost >= PredictionResult.invalidCost {
        break
      }

      if filter.shouldRemove(result, finalResults.count) {
        continue
      }

      if finalResults.isEmpty {
        if let prevTop = maybeGetPreviousTopResult(result, request),
          !filter.shouldRemove(prevTop, finalResults.count)
        {
          finalResults.append(prevTop)
        }
      }

      if (result.attributes & Attribute.partiallyKeyConsumed) != 0 && cursorAtTail {
        result.attributes |= Attribute.autoPartialSuggestion
      }

      if ((result.attributes & Attribute.spellingCorrection) == 0
        && RequestUtil.isLatinInputMode(request))
        || (result.attributes & Attribute.suffixDictionary) != 0
      {
        result.attributes |= Attribute.noVariantsExpansion
        result.attributes |= Attribute.noExtraDescription
      }

      finalResults.append(result)
    }

    maybeApplyPostCorrection(request, &finalResults)

    if Self.isDebug(request) {
      for i in finalResults.indices {
        let types = mergedAttributes[PredictionBytesKey(finalResults[i].value)] ?? 0
        Self.appendDescription(&finalResults[i], getPredictionTypeDebugString(types))
      }
    }

    return finalResults
  }

  func maybeApplyPostCorrection(_ request: ConversionRequest, _ results: inout [PredictionResult])
  {
    // b/363902660:
    // Stop applying post correction when handwriting mode.
    if RequestUtil.isHandwriting(request) {
      return
    }

    // Apply PostCorrection.
    modules.predictionSupplementalModel().postCorrect(request, &results)
  }

  /// Returns the cost offset for SINGLE_KANJI results.
  /// Aggregated SINGLE_KANJI results does not have LM based wcost(word cost),
  /// so we want to add the offset based on the other entries.
  func calculateSingleKanjiCostOffset(
    _ request: ConversionRequest, _ rid: Int, _ results: [PredictionResult]
  ) -> Int {
    // Make a map from reference value to min-cost result.
    // Reference entry:
    //  - single-char REALTIME or UNIGRAM entry
    //  - PREFIX or NUMBER entry
    // cost is calculated with LM cost (with prefix penalty)
    // When the reference is not found, Hiragana (value == key) entry will be
    // used as the fallback.
    var minCostMap: [PredictionBytesKey: Int] = [:]
    var fallbackCost = -1
    let requestKey = request.key()
    for result in results {
      if result.removed {
        continue
      }
      if (result.attributes
        & (Attribute.realtimeConversion | Attribute.unigram | Attribute.partiallyKeyConsumed
          | Attribute.number)) == 0
      {
        continue
      }

      if result.value.bytesEqual(requestKey) {
        let cost = getLMCost(result, rid)
        if fallbackCost == -1 || fallbackCost > cost {
          fallbackCost = cost
        }
      }

      if (result.attributes & (Attribute.realtimeConversion | Attribute.unigram)) != 0
        && Util.charsLen(result.value) != 1
      {
        continue
      }
      var lmCost = getLMCost(result, rid)
      if (result.attributes & Attribute.partiallyKeyConsumed) != 0 {
        lmCost += calculatePrefixPenalty(request, result)
      }
      let k = PredictionBytesKey(result.value)
      if let existing = minCostMap[k] {
        minCostMap[k] = min(existing, lmCost)
      } else {
        minCostMap[k] = lmCost
      }
    }

    // Use the wcost of the highest cost to calculate the single kanji cost
    // offset.
    var singleKanjiMaxCost = 0
    for (_, cost) in minCostMap {
      singleKanjiMaxCost = max(singleKanjiMaxCost, cost)
    }
    singleKanjiMaxCost = max(singleKanjiMaxCost, fallbackCost)

    let singleKanjiTransitionCost = min(
      connector.getTransitionCost(UInt16(truncatingIfNeeded: rid), generalSymbolId),
      connector.getTransitionCost(0, generalSymbolId))
    let wcostDiff = max(0, singleKanjiMaxCost - singleKanjiTransitionCost)
    let kSingleKanjiPredictionCostOffset = 800  // ~= 500*ln(5)
    return wcostDiff + kSingleKanjiPredictionCostOffset
  }

  /// Returns language model cost of |token| given prediction type |type|.
  /// |rid| is the right id of previous word (token).
  /// If |rid| is unknown, set 0 as a default value.
  ///
  /// Suffix penalty is also added for non-realtime results.
  func getLMCost(_ result: PredictionResult, _ rid: Int) -> Int {
    let costWithContext = connector.getTransitionCost(UInt16(truncatingIfNeeded: rid), result.lid)

    var lmCost = 0

    if (result.attributes & Attribute.suffixDictionary) != 0 {
      // We always respect the previous context to calculate the cost of
      // SUFFIX. Otherwise, the suffix that doesn't match the context will be
      // promoted.
      lmCost = costWithContext + result.wcost
    } else {
      // Sometimes transition cost is too high and causes a bug like
      // b/18112966. For example, "接続詞 が" -> "始まる 動詞,五段活用,基本形" has
      // very large cost and "始まる" is demoted.  To prevent such cases,
      // ImmutableConverter computes transition from BOS/EOS too; see
      // ImmutableConverterImpl::MakeLatticeNodesForHistorySegments().
      // Here, taking the minimum of |cost1| and |cost2| has a similar effect.
      let costWithoutContext = connector.getTransitionCost(0, result.lid)
      lmCost = min(costWithContext, costWithoutContext) + result.wcost
    }

    if (result.attributes & Attribute.realtimeConversion) == 0 {
      // Realtime conversion already adds prefix/suffix penalties to the
      // result. Note that we don't add prefix penalty the role of "bunsetsu"
      // is ambiguous on zero-query suggestion.
      lmCost += Int(segmenter.getSuffixPenalty(result.rid))
    }

    return lmCost
  }

  /// Scoring function which takes prediction bounus into account.
  /// It basically reranks the candidate by lang_prob * (1 + remain_len).
  /// This algorithm is mainly used for desktop.
  func setPredictionCost(_ request: ConversionRequest, _ results: inout [PredictionResult]) {
    let historyRid = request.converterHistoryRid()

    let isSuggestion = request.requestType() == .suggestion

    // use the same scoring function for both unigram/bigram.
    // Bigram will be boosted because we pass the previous
    // key as a context information.
    let historyKeyLen = Util.charsLen(request.converterHistoryKey(1))
    let requestKeyLen = Util.charsLen(request.key())

    let totalSize = results.count
    for i in results.indices {
      let cost = getLMCost(results[i], historyRid)
      var queryLen = requestKeyLen
      var keyLen = Util.charsLen(results[i].key)
      if (results[i].attributes & Attribute.bigram) != 0 {
        queryLen += historyKeyLen
        keyLen += historyKeyLen
      }

      if Self.isAggressiveSuggestion(queryLen, keyLen, cost, isSuggestion, totalSize) {
        results[i].cost = PredictionResult.invalidCost
        continue
      }

      // cost = -500 * log(lang_prob(w) * (1 + remain_length))    -- (1)
      // where lang_prob(w) is a language model probability of the word "w",
      // and remain_length the length of key user must type to input "w".
      //
      // Example:
      // key/value = "とうきょう/東京"
      // user_input = "とう"
      // remain_length = len("とうきょう") - len("とう") = 3
      //
      // By taking the log of (1),
      // cost  = -500 [log(lang_prob(w)) + log(1 + ramain_length)]
      //       = -500 * log(lang_prob(w)) + 500 * log(1 + remain_length)
      //       = cost - 500 * log(1 + remain_length)
      // Because 500 * log(lang_prob(w)) = -cost.
      //
      // lang_prob(w) * (1 + remain_length) represents how user can reduce
      // the total types by choosing this candidate.
      // Before this simple algorithm, we have been using an SVM-base scoring,
      // but we stop usign it with the following reasons.
      // 1) Hard to maintain the ranking.
      // 2) Hard to control the final results of SVM.
      // 3) Hard to debug.
      // 4) Since we used the log(remain_length) as a feature,
      //    the new ranking algorithm and SVM algorithm was essentially
      //    the same.
      // 5) Since we used the length of value as a feature, we find
      //    inconsistencies between the conversion and the prediction
      //    -- the results of top prediction and the top conversion
      //    (the candidate shown after the space key) may differ.
      //
      // The new function brings consistent results. If two candidate
      // have the same reading (key), they should have the same cost bonus
      // from the length part. This implies that the result is reranked by
      // the language model probability as long as the key part is the same.
      // This behavior is basically the same as the converter.
      //
      // TODO(team): want find the best parameter instead of kCostFactor.
      let kCostFactor = 500
      // std::max<int>(0, key_len - query_len) with size_t operands.
      let remain = Int(Int32(truncatingIfNeeded: keyLen &- queryLen))
      results[i].cost = Int(
        Double(cost) - Double(kCostFactor) * Foundation.log(1.0 + Double(max(0, remain))))
    }
  }

  /// Scoring function for mixed conversion.
  /// In the mixed conversion we basically use the pure language model-based
  /// scoring function. This algorithm is mainly used for mobile.
  func setPredictionCostForMixedConversion(
    _ request: ConversionRequest, _ results: inout [PredictionResult]
  ) {
    // ranking for mobile
    let historyRid = request.converterHistoryRid()  // 0 (BOS) is default

    // cost of the last history candidate.
    var prevCost = request.converterHistoryCost()
    if prevCost == 0 {
      // if prev_cost is set to be 0 for some reason, use default cost.
      prevCost = 5000
    }

    let singleKanjiOffset = calculateSingleKanjiCostOffset(request, historyRid, results)

    for i in results.indices {
      var cost = getLMCost(results[i], historyRid)
      let lid = results[i].lid
      let rid = results[i].rid
      if lid == rid && !posMatcher.isSuffixWord(rid) && !posMatcher.isFunctional(rid)
        && !posMatcher.isWeakCompoundVerbSuffix(rid)
      {
        // TODO(b/242683049): It's better to define a new POS matcher rule once
        // we decide to make this behavior default.
        // Implementation note:
        // Suffix penalty is added in the above GetLMCost(), which is also used
        // for calculating non-mobile prediction cost. So we modify the cost
        // calculation here for now.
        cost -= Int(segmenter.getSuffixPenalty(rid))
      }

      // Demote filtered word here, because they are not filtered for exact
      // match. Even for exact match, we don't want to show aggressive words
      // with high ranking.
      if suggestionFilter.isBadSuggestion(results[i].value) {
        // Cost penalty means for bad suggestion.
        // 3453 = 500 * log(1000)
        let kBadSuggestionPenalty = 3453
        cost += kBadSuggestionPenalty
      }

      let attributes = results[i].attributes
      if (attributes & Attribute.bigram) != 0 {
        // When user inputs "六本木" and there is an entry
        // "六本木ヒルズ" in the dictionary, we can suggest
        // "ヒルズ" as a ZeroQuery suggestion. In this case,
        // We can't calcurate the transition cost between "六本木"
        // and "ヒルズ". If we ignore the transition cost,
        // bigram-based suggestion will be overestimated.
        // Here we use kDefaultTransitionCost as an
        // transition cost between "六本木" and "ヒルズ". Currently,
        // the cost is basically the same as the cost between
        // "名詞,一般" and "名詞,一般".
        // TODO(taku): Adjust these parameters.
        // Seems the bigram is overestimated.
        let kDefaultTransitionCost = 1347
        // Promoting bigram candidates.
        let kBigramBonus = 800  // ~= 500*ln(5)
        cost += (kDefaultTransitionCost - kBigramBonus - prevCost)
        // The bonus can make the cost negative and promotes bigram results
        // too much.
        // Align the cost here before applying other cost modifications.
        cost = max(1, cost)
      }

      if (attributes & Attribute.singleKanji) != 0 {
        cost += singleKanjiOffset
        if cost <= 0 {
          // single_kanji_offset can be negative.
          // cost should be larger than 0.
          cost = results[i].wcost + 1
        }
      }

      if (attributes & Attribute.userDictionary) != 0 && lid != generalSymbolId {
        // Decrease cost for words from user dictionary in order to promote
        // them, provided that it is not a general symbol (Note: emoticons are
        // mapped to general symbol).  Currently user dictionary words are
        // evaluated 5 times bigger in frequency, being capped by 1000 (this
        // number is adhoc, so feel free to adjust).
        let kUserDictionaryPromotionFactor = 804  // 804 = 500 * log(5)
        let kUserDictionaryCostUpperLimit = 1000
        cost = min(cost - kUserDictionaryPromotionFactor, kUserDictionaryCostUpperLimit)
      }

      // Demote predictive results for making exact candidates to have higher
      // ranking.
      // - Users expect the candidates for the input key on the candidates.
      // - We want to show candidates as many as possible in the limited
      //   candidates area.
      let candidateLookupKeyLen = Util.charsLen(request.key())
      let candidateKeyLen = Util.charsLen(results[i].key)
      if (attributes & Attribute.suffixDictionary) == 0
        && candidateKeyLen > candidateLookupKeyLen
      {
        let predictedKeyLen = candidateKeyLen - candidateLookupKeyLen
        // -500 * log(prob)
        // See also: mozc/converter/candidate_filter.cc
        let predictivePenalty = Int(500 * Foundation.log(Double(50 * predictedKeyLen)))
        cost += predictivePenalty
      }
      if (attributes & Attribute.partiallyKeyConsumed) != 0 {
        let prefixPenalty = calculatePrefixPenalty(request, results[i])
        results[i].penalty += prefixPenalty
        cost += prefixPenalty
      }

      // Note that the cost is defined as -500 * log(prob).
      // Even after the ad hoc manipulations, cost must remain larger than 0.
      results[i].cost = max(1, cost)
    }
  }

  /// Given the results aggregated by aggregates, remove
  /// miss-spelled results from the |results|.
  /// we don't directly remove miss-spelled result but set
  /// result[i].removed = true.
  ///
  /// Here's the basic step of removal:
  /// Case1:
  /// result1: "あぼがど" => "アボガド"
  /// result2: "あぼがど" => "アボカド" (spelling correction)
  /// result3: "あぼかど" => "アボカド"
  /// In this case, we can remove result 1 and 2.
  /// If there exists the same result2.key in result1,3 and
  /// the same result2.value in result1,3, we can remove the
  /// 1) spelling correction candidate 2) candidate having
  /// the same key as the spelling correction candidate.
  ///
  /// Case2:
  /// result1: "あぼかど" => "アボカド"
  /// result2: "あぼがど" => "アボカド" (spelling correction)
  /// In this case, remove result2.
  ///
  /// Case3:
  /// result1: "あぼがど" => "アボガド"
  /// result2: "あぼがど" => "アボカド" (spelling correction)
  /// In this case,
  ///   a) user input: あ,あぼ,あぼ => remove result1, result2
  ///   b) user input: あぼが,あぼがど  => remove result1
  ///
  /// let |same_key_size| and |same_value_size| be the number of
  /// non-spelling-correction-candidates who have the same key/value as
  /// spelling-correction-candidate respectively.
  ///
  /// if (same_key_size > 0 && same_value_size > 0) {
  ///   remove spelling correction and candidates having the
  ///   same key as the spelling correction.
  /// } else if (same_key_size == 0 && same_value_size > 0) {
  ///   remove spelling correction
  /// } else {
  ///   do nothing.
  /// }
  static func removeMissSpelledCandidates(
    _ request: ConversionRequest, _ results: inout [PredictionResult]
  ) {
    let requestKeyLen = Util.charsLen(request.key())

    if results.count <= 1 {
      return
    }

    var spellingCorrectionSize = 5
    for i in 0..<results.count {
      let result = results[i]
      if (result.attributes & Attribute.spellingCorrection) == 0 {
        continue
      }

      // Only checks at most 5 spelling corrections to avoid the case
      // like all candidates have SPELLING_CORRECTION.
      spellingCorrectionSize -= 1
      if spellingCorrectionSize == 0 {
        return
      }

      var sameKeyIndex: [Int] = []
      var sameValueIndex: [Int] = []
      for j in 0..<results.count {
        if i == j {
          continue
        }
        let targetResult = results[j]
        if (targetResult.attributes & Attribute.spellingCorrection) != 0 {
          continue
        }
        if targetResult.key.bytesEqual(result.key) {
          sameKeyIndex.append(j)
        }
        if targetResult.value.bytesEqual(result.value) {
          sameValueIndex.append(j)
        }
      }

      // delete same_key_index and same_value_index
      if !sameKeyIndex.isEmpty && !sameValueIndex.isEmpty {
        results[i].removed = true
        for k in sameKeyIndex {
          results[k].removed = true
        }
      } else if sameKeyIndex.isEmpty && !sameValueIndex.isEmpty {
        results[i].removed = true
      } else if !sameKeyIndex.isEmpty && sameValueIndex.isEmpty {
        for k in sameKeyIndex {
          results[k].removed = true
        }
        if requestKeyLen <= ResultFilter.getMissSpelledPosition(result.key, result.value) {
          results[i].removed = true
        }
      }
    }
  }

  /// Returns true if the suggestion is classified
  /// as "aggressive".
  static func isAggressiveSuggestion(
    _ queryLen: Int, _ keyLen: Int, _ cost: Int, _ isSuggestion: Bool, _ totalCandidatesSize: Int
  ) -> Bool {
    // Temporal workaround for fixing the problem where longer sentence-like
    // suggestions are shown when user input is very short.
    // "ただしい" => "ただしいけめんにかぎる"
    // "それでもぼ" => "それでもぼくはやっていない".
    // If total_candidates_size is small enough, we don't perform
    // special filtering. e.g., "せんとち" has only two candidates, so
    // showing "千と千尋の神隠し" is OK.
    // Also, if the cost is too small (< 5000), we allow to display
    // long phrases. Examples include "よろしくおねがいします".
    if isSuggestion && totalCandidatesSize >= 10 && keyLen >= 8 && cost >= 5000
      && queryLen <= Int(0.4 * Double(keyLen))
    {
      return true
    }

    return false
  }

  func calculatePrefixPenalty(_ request: ConversionRequest, _ result: PredictionResult) -> Int {
    let requestKey = request.key()
    if requestKey.bytesEqual(result.key) || requestKey.utf8.count <= result.key.utf8.count {
      GenmaiLog.warning("Invalid prefix key: \(result.key)")
      return 0
    }

    let suffix = String(requestKey.byteSubstring(from: result.key.utf8.count))

    // The resdult of DecodeSuffix is cached.
    let res = decoder.decodeSuffix(request, result.rid, suffix)
    var penalty = res?.cost ?? PredictionResult.invalidCost

    // In the previous CalculatePrefixPenalty code, we added the
    // transition cost from prefix.rid to suffix.lid. However, this treatment
    // is not precise. decoder_.Decode() returns the result of "unconstrained
    // full conversion" -- the transition cost from BOS and per-segment prefix
    // penalty are added to the result. Consequently, the penalty calculate in
    // the previous code was overestimated.
    //
    // By using decoder_.DecodeSuffix(), we can calculate the accurate suffix
    // cost using the prefix.rid as the BOS id and preventing to add prefix
    // penalty to the suffix. However, this treatment results in a lower
    // penalty than before. To handle this inconsistency, we add larger
    // additional penalty here. The default penalty is 5000.
    penalty += Int(request.request().decoderExperimentParams.partialCandidateCostPenalty)

    return penalty
  }

  func maybeRescoreResults(_ request: ConversionRequest, _ results: inout [PredictionResult]) {
    if RequestUtil.isHandwriting(request) {
      // We want to fix the first candidate for handwriting request.
      return
    }

    if Self.isDebug(request) {
      for i in results.indices {
        results[i].costBeforeRescoring = results[i].cost
      }
    }

    modules.predictionSupplementalModel().rescoreResults(request, &results)
  }

  func maybeGetPreviousTopResult(
    _ currentTopResult: PredictionResult, _ request: ConversionRequest
  ) -> PredictionResult? {
    let maxDiff = Int(request.request().decoderExperimentParams.candidateConsistencyCostMaxDiff)
    if maxDiff == 0 {
      return nil
    }

    return prevTop.withLock { state -> PredictionResult? in
      let prevTopResult = state.result

      // Updates the key length.
      let curTopKeyLength = Int32(truncatingIfNeeded: request.key().utf8.count)
      let prevTopKeyLength = state.keyLength
      state.keyLength = curTopKeyLength  // returns the old value.

      // Insert condition.
      // 1. 0 < prev key length < current key length (incrementally character
      //    is added)
      // 2. cost diff is less than max_diff.
      // 3. current key is non-empty and shorter than previous key.
      // 4. current key is the prefix of previous key.
      // 5. current result is not a partial suggestion.
      if let prevTopResult, 0 < prevTopKeyLength, prevTopKeyLength < curTopKeyLength,
        !currentTopResult.key.isEmpty,
        currentTopResult.key.utf8.count < prevTopResult.key.utf8.count,
        abs(currentTopResult.cost - prevTopResult.cost) < maxDiff,
        (currentTopResult.attributes & Attribute.partiallyKeyConsumed) == 0,
        prevTopResult.key.hasBytePrefix(currentTopResult.key)
      {
        // Do not need to remember the previous key as `prev_top_result` is
        // still top result.
        return prevTopResult
      }

      // Remembers the top result.
      state.result = currentTopResult

      return nil
    }
  }
}
