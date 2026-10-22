// Port of mozc/src/prediction/dictionary_decoder.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - `std::vector<Result>*` output parameters are `inout [PredictionResult]`.
// - `int* min_unigram_key_len` is returned.

import GenmaiBase

/// Bigram lookup callback (anonymous namespace in C++).
final class PredictiveBigramLookupCallback: PredictiveLookupCallback {
  private let historyKey: String
  private let historyValue: String

  init(
    _ types: PredictionTypes, _ limit: Int, _ originalKeyLen: Int, _ subsequentChars: [String],
    _ historyKey: String, _ historyValue: String, _ zipCodeId: Int, _ unknownId: Int
  ) {
    self.historyKey = historyKey
    self.historyValue = historyValue
    super.init(types, limit, originalKeyLen, subsequentChars, zipCodeId, unknownId)
  }

  override func onToken(_ key: String, _ expandedKey: String, _ token: Token)
    -> DictionaryCallbackResult
  {
    // Skip the token if its value doesn't start with the previous user input,
    // |history_value_|.
    if !token.value.hasBytePrefix(historyValue)
      || token.value.utf8.count <= historyValue.utf8.count
    {
      return .traverseContinue
    }
    return super.onToken(key, expandedKey, token)
  }

  // Removes the history key/values in the result.
  override func rewriteResult(_ result: inout PredictionResult) {
    result.key = String(result.key.byteSubstring(from: historyKey.utf8.count))
    result.value = String(result.value.byteSubstring(from: historyValue.utf8.count))
  }
}

public final class DictionaryDecoder {
  private let modules: any PredictionModules
  private let dictionary: any DictionaryInterface
  private let kanjiNumberId: UInt16
  private let zipCodeId: UInt16
  private let unknownId: UInt16

  public init(_ modules: any PredictionModules) {
    self.modules = modules
    dictionary = modules.getDictionary()
    kanjiNumberId = modules.getPosMatcher().getKanjiNumberId()
    zipCodeId = modules.getPosMatcher().getZipcodeId()
    unknownId = modules.getPosMatcher().getUnknownId()
  }

  private static func findKeyAndValue(
    _ dic: any DictionaryInterface, _ request: ConversionRequest, _ key: String, _ value: String
  ) -> Token? {
    var resultToken: Token?
    let cb = InlineCallback().onToken { _, _, token in
      if !token.value.bytesEqual(value) {
        return .traverseContinue
      }
      resultToken = token
      return .traverseDone
    }
    dic.lookupPrefix(key, options: request.options(), callback: cb)
    return resultToken
  }

  private static func lookupPredictive(
    _ dictionary: any DictionaryInterface, _ key: String, _ request: ConversionRequest,
    _ callback: PredictiveLookupCallback, _ results: inout [PredictionResult]
  ) {
    swap(&callback.results, &results)
    dictionary.lookupPredictive(key, options: request.options(), callback: callback)
    swap(&callback.results, &results)
  }

  private static func getPredictiveResultsForUnigram(
    _ dictionary: any DictionaryInterface, _ request: ConversionRequest, _ types: PredictionTypes,
    _ lookupLimit: Int, _ zipCodeId: Int, _ unknownId: Int, _ results: inout [PredictionResult]
  ) {
    let emptyExpanded: [String] = []
    if request.options().useAlreadyTypingCorrectedKey {
      let callback = PredictiveLookupCallback(
        types, lookupLimit, request.key().utf8.count, emptyExpanded, zipCodeId, unknownId)
      lookupPredictive(dictionary, request.key(), request, callback, &results)
      return
    }

    // If we have ambiguity for the input, get expanded key.
    // Example1 roman input: for "あk", we will get |base|, "あ" and
    // |expanded|, "か", "き", etc
    // Example2 kana input: for "あか", we will get |base|, "あ" and
    // |expanded|, "か", and "が".
    let (base, expanded) = request.composer().getQueriesForPrediction()
    if expanded.isEmpty {
      let callback = PredictiveLookupCallback(
        types, lookupLimit, base.utf8.count, expanded, zipCodeId, unknownId)
      lookupPredictive(dictionary, base, request, callback, &results)
      return
    }

    // |expanded| is a very small set, so calling LookupPredictive multiple
    // times is not so expensive.  Also, the number of lookup results is
    // limited by |lookup_limit|.
    for expandedChar in expanded {
      let requestKey = base + expandedChar
      let callback = PredictiveLookupCallback(
        types, lookupLimit, requestKey.utf8.count, emptyExpanded, zipCodeId, unknownId)
      lookupPredictive(dictionary, requestKey, request, callback, &results)
    }
  }

  private static func getPredictiveResultsForBigram(
    _ dictionary: any DictionaryInterface, _ historyKey: String, _ historyValue: String,
    _ request: ConversionRequest, _ types: PredictionTypes, _ lookupLimit: Int,
    _ zipCodeId: Int, _ unknownId: Int, _ results: inout [PredictionResult]
  ) {
    if request.options().useAlreadyTypingCorrectedKey {
      let requestKey = historyKey + request.key()
      let callback = PredictiveBigramLookupCallback(
        types, lookupLimit, requestKey.utf8.count, [], historyKey, historyValue, zipCodeId,
        unknownId)
      lookupPredictive(dictionary, requestKey, request, callback, &results)
      return
    }

    // If we have ambiguity for the input, get expanded key.
    // Example1 roman input: for "あk", we will get |base|, "あ" and
    // |expanded|, "か", "き", etc
    // Example2 kana input: for "あか", we will get |base|, "あ" and
    // |expanded|, "か", and "が".
    let (base, expanded) = request.composer().getQueriesForPrediction()
    let requestKey = historyKey + base

    let callback = PredictiveBigramLookupCallback(
      types, lookupLimit, requestKey.utf8.count, expanded, historyKey, historyValue, zipCodeId,
      unknownId)
    lookupPredictive(dictionary, requestKey, request, callback, &results)
  }

  /// Aggregates unigram predictions for the given request. Returns
  /// `min_unigram_key_len`.
  @discardableResult
  public func aggregateUnigram(
    _ request: ConversionRequest, _ results: inout [PredictionResult]
  ) -> Int {
    var minUnigramKeyLen = 0

    let keyLen = Util.charsLen(request.key())
    if keyLen == 0 {
      return minUnigramKeyLen
    }

    let isMixedConversion = request.request().mixedConversion

    var minKeyLen = 1
    if isMixedConversion {
      // In mixed conversion mode, we want to show unigram candidates even for
      // short keys to emulate PREDICTION mode.
      minUnigramKeyLen = minKeyLen
      if keyLen >= minKeyLen {
        aggregateUnigramForMixedConversion(request, &results)
      }
    } else {
      // Use the standard dictionary-based prediction by default.
      minKeyLen = (request.requestType() == .prediction) ? 1 : 3
      minUnigramKeyLen = minKeyLen
      if keyLen >= minKeyLen {
        aggregateUnigramForDesktop(request, &results)
      }
    }
    return minUnigramKeyLen
  }

  /// Aggregates unigram predictions for standard (non-mixed-conversion) mode.
  ///
  /// Suggestions (key length >= 3) and explicit Tab-driven predictions (key
  /// length >= 1) look up unigram dictionary entries directly up to the
  /// cutoff threshold (adjuster.cutoff_threshold()).
  public func aggregateUnigramForDesktop(
    _ request: ConversionRequest, _ results: inout [PredictionResult]
  ) {
    assert(request.requestType() == .prediction || request.requestType() == .suggestion)

    let adjuster = ResultsSizeAdjuster(request, results)
    Self.getPredictiveResultsForUnigram(
      dictionary, request, Attribute.unigram, adjuster.cutoffThreshold, Int(zipCodeId),
      Int(unknownId), &results)
    adjuster.adjustSize(&results)
  }

  /// Aggregates unigram predictions for mixed conversion mode (and partial
  /// suggestions/predictions).
  ///
  /// In mixed conversion mode, unigram lookups trigger from the first
  /// character (key length >= 1). It fetches candidates up to
  /// `kPredictionMaxResultsSize` and applies `filter::RemoveRedundantResults`
  /// to eliminate redundant candidates.
  public func aggregateUnigramForMixedConversion(
    _ request: ConversionRequest, _ results: inout [PredictionResult]
  ) {
    var rawResult: [PredictionResult] = []
    Self.getPredictiveResultsForUnigram(
      dictionary, request, Attribute.unigram, kPredictionMaxResultsSize, Int(zipCodeId),
      Int(unknownId), &rawResult)
    ResultFilter.removeRedundantResults(&rawResult)
    results.append(contentsOf: rawResult)
  }

  /// Aggregates bigram predictions for the given request.
  public func aggregateBigram(_ request: ConversionRequest, _ results: inout [PredictionResult]) {
    // Disables bigram zero query just in case.
    // This check must be done outside of this method.
    if request.isZeroQuerySuggestion() {
      return
    }

    // TODO(toshiyuki): Support suggestion from the last 2 histories.
    //  ex) "六本木"+"ヒルズ"->"レジデンス"
    let historyKey = request.converterHistoryKey(1)
    let historyValue = request.converterHistoryValue(1)
    if historyKey.isEmpty || historyValue.isEmpty {
      return
    }

    // Check that history_key/history_value are in the dictionary.
    guard
      let findHistoryToken = Self.findKeyAndValue(dictionary, request, historyKey, historyValue)
    else {
      // History value is not found in the dictionary.
      // User may create this the history candidate from T13N or segment
      // expand/shrinkg operations.
      return
    }

    let adjuster = ResultsSizeAdjuster(request, results)
    Self.getPredictiveResultsForBigram(
      dictionary, historyKey, historyValue, request, Attribute.bigram, adjuster.cutoffThreshold,
      Int(zipCodeId), Int(unknownId), &results)
    adjuster.adjustSize(&results)

    let historyCtype = Util.getScriptType(historyValue)
    let historyValueSize = Util.charsLen(historyValue)
    let lastHistoryCtype = Util.getScriptType(
      Util.utf8SubString(historyValue, historyValueSize - 1, 1))
    for i in adjuster.getAddedResults(results) {
      checkBigramResult(findHistoryToken, historyCtype, lastHistoryCtype, request, &results[i])
    }
    // The destructor of the adjuster in C++ runs AdjustSize() again here,
    // which is a no-op since no result is added after the call above.
    adjuster.adjustSize(&results)
  }

  /// Filters out irrelevant bigram candidates by setting
  /// `result->removed = true`.
  ///
  /// Bigram prediction looks up words following committed history words.
  /// However, naive lookup can propose unnatural word fragments (e.g.
  /// suggesting "リカ" after committed "アメ", or "ターネット" after committed
  /// "イン"). This method verifies script types, prefix costs, and dictionary
  /// presence:
  ///   - Suppresses word fragments where whole word is more frequent (e.g.
  ///   "アメ" -> "リカ").
  ///   - Suppresses short boundaries sharing the same script type (Hiragana
  ///   <= 9, Katakana <= 5).
  ///   - Allows valid compounds like Kanji + Katakana (e.g. "六本木" ->
  ///   "ヒルズ") and long Kanji compounds (e.g. "京都大学" -> "霊長類研究所").
  public func checkBigramResult(
    _ historyToken: Token, _ historyCtype: Util.ScriptType, _ lastHistoryCtype: Util.ScriptType,
    _ request: ConversionRequest, _ result: inout PredictionResult
  ) {
    let key = result.key
    let value = result.value

    // Don't suggest 0-length key/value.
    if key.isEmpty || value.isEmpty {
      result.removed = true
      return
    }

    let ctype = Util.getScriptType(Util.utf8SubString(value, 0, 1))

    if historyCtype == .kanji && ctype == .katakana {
      // Do not filter "六本木ヒルズ"
      return
    }

    // If freq("アメ") < freq("アメリカ"), we don't
    // need to suggest it. As "アメリカ" should already be
    // suggested when user type "アメ".
    // Note that wcost = -500 * log(prob).
    if ctype != .kanji && historyToken.cost > result.wcost {
      result.removed = true
      return
    }

    // If character type doesn't change, this boundary might NOT
    // be a word boundary. Only use iif the entire key is reasonably long.
    let keyLen = Util.charsLen(result.key) + Util.charsLen(historyToken.key)
    if ctype == lastHistoryCtype
      && ((ctype == .hiragana && keyLen <= 9) || (ctype == .katakana && keyLen <= 5))
    {
      result.removed = true
      return
    }

    // The suggested key/value pair must exist in the dictionary.
    // For example, we don't want to suggest "ターネット" from
    // the history "イン".
    // If character type is Kanji and the suggestion is not a
    // zero_query_suggestion, we relax this condition, as there are
    // many Kanji-compounds which may not in the dictionary. For example,
    // we want to suggest "霊長類研究所" from the history "京都大学".
    if ctype == .kanji && Util.charsLen(value) >= 2 {
      // Do not filter this.
      // TODO(toshiyuki): one-length kanji prediction may be annoying other
      // than some exceptions, "駅", "口", etc
      return
    }

    // Check if the word is in the dictionary or not.
    // For Hiragana words, check if that word is in a key of values.
    // This is for a situation that
    // ありがとうございました is not in the dictionary, but
    // ありがとう御座いました is in the dictionary.
    if ctype == .hiragana {
      if !dictionary.hasKey(key) {
        result.removed = true
        return
      }
    } else {
      if Self.findKeyAndValue(dictionary, request, key, value) == nil {
        result.removed = true
        return
      }
    }
  }

  /// Aggregates prefix predictions for the given request.
  public func aggregatePrefix(_ request: ConversionRequest, _ results: inout [PredictionResult]) {
    let requestKey = request.key()
    let requestKeyLen = Util.charsLen(requestKey)
    if requestKeyLen <= 1 {
      return
    }

    // Excludes exact match nodes.
    let lookupKey = String(Util.utf8SubString(requestKey, 0, requestKeyLen - 1))

    let kMinValueCharsLen = 2
    let limit = DecoderUtil.getCandidateCutoffThreshold(request.requestType())

    let unknownId = self.unknownId
    let kanjiNumberId = self.kanjiNumberId
    var localResults: [PredictionResult] = []
    swap(&localResults, &results)
    let cb = InlineCallback().onToken { key, actualKey, token in
      if (token.attributes & Token.Attribute.userDictionary) != 0 && token.lid == unknownId {
        // No suggest-only words as prefix candidates
        return .traverseContinue
      }
      // Avoid noisy script type nodes.
      if token.lid == kanjiNumberId && token.rid == kanjiNumberId {
        // Kanji number entry can be looked up with the special reading and
        // will be expanded for the number variants, so we want to suppress
        // them here. For example, for the input "ろっぽんぎ", "六" can be
        // looked up for the prefix reading "ろ" or "ろっ", and then be
        // expanded with "6", "Ⅵ", etc.
        return .traverseContinue
      }
      let scriptType = Util.getScriptType(token.value)
      if scriptType == .number || scriptType == .alphabet || scriptType == .emoji {
        return .traverseContinue
      }
      if Util.charsLen(token.value) < kMinValueCharsLen {
        return .traverseContinue
      }
      var result = PredictionResult()
      result.initializeByTokenAndTypes(token, Attribute.partiallyKeyConsumed)
      if !key.bytesEqual(actualKey) {
        result.attributes |= Attribute.typingCorrection
      }
      let keyLen = Util.charsLen(key)
      if keyLen < requestKeyLen {
        result.attributes |= Attribute.partiallyKeyConsumed
        result.consumedKeySize = UInt32(keyLen)
      }
      localResults.append(result)
      return (localResults.count < limit) ? .traverseContinue : .traverseDone
    }

    dictionary.lookupPrefix(lookupKey, options: request.options(), callback: cb)
    swap(&localResults, &results)
  }
}
