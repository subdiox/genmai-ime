// Port of mozc/src/prediction/zero_query_decoder.{h,cc} (3.35.6354).
//
// Deviation from C++: ZeroQueryDecoderTestPeer's private methods are
// `internal` (accessible with @testable import).

import GenmaiBase

public final class ZeroQueryDecoder {
  private let modules: any PredictionModules
  private let zeroQueryDict: ZeroQueryDict
  private let zeroQueryNumberDict: ZeroQueryDict
  private let suffixDictionary: any DictionaryInterface
  private let counterSuffixWordId: UInt16
  private let zipCodeId: UInt16
  private let unknownId: UInt16

  public init(_ modules: any PredictionModules) {
    self.modules = modules
    zeroQueryDict = modules.getZeroQueryDict()
    zeroQueryNumberDict = modules.getZeroQueryNumberDict()
    suffixDictionary = modules.getSuffixDictionary()
    counterSuffixWordId = modules.getPosMatcher().getCounterSuffixWordId()
    zipCodeId = modules.getPosMatcher().getZipcodeId()
    unknownId = modules.getPosMatcher().getUnknownId()
  }

  private static func isZeroQuerySuffixPredictionDisabled(_ request: ConversionRequest) -> Bool {
    request.request().decoderExperimentParams.disableZeroQuerySuffixPrediction
  }

  private static func getNumberHistory(_ request: ConversionRequest) -> String? {
    var historyValue = Substring(request.converterHistoryValue(1))
    if historyValue.isEmpty {
      // Note: Full width number is not supported in `preceding_text`.
      let precedingText = request.context().precedingText
      let bytes = Array(precedingText.utf8)
      var start = bytes.count
      while start > 0 && bytes[start - 1] >= 0x30 && bytes[start - 1] <= 0x39 {
        start -= 1
      }
      historyValue = precedingText.byteSubstring(from: start)
    }
    if historyValue.isEmpty || !NumberUtil.isArabicNumber(historyValue) {
      return nil
    }
    return Japanese.fullWidthToHalfWidth(historyValue)
  }

  private static func isEmailPrefix(_ str: some StringProtocol) -> Bool {
    str.hasByteSuffix("@") && Util.isAscii(str)
  }

  private final class SuffixLookupCallback: DictionaryCallback {
    let types: PredictionTypes
    let limit: Int
    let zipCodeId: UInt16
    let unknownId: UInt16
    var results: [PredictionResult] = []

    init(_ types: PredictionTypes, _ limit: Int, _ zipCodeId: UInt16, _ unknownId: UInt16) {
      self.types = types
      self.limit = limit
      self.zipCodeId = zipCodeId
      self.unknownId = unknownId
    }

    func onKey(_ key: String) -> DictionaryCallbackResult { .traverseContinue }

    func onActualKey(_ key: String, _ actualKey: String, _ numExpanded: Int)
      -> DictionaryCallbackResult
    { .traverseContinue }

    func onToken(_ key: String, _ expandedNewKey: String, _ token: Token)
      -> DictionaryCallbackResult
    {
      if token.lid == zipCodeId || token.lid == unknownId {
        return .traverseContinue
      }
      var result = PredictionResult()
      result.initializeByTokenAndTypes(token, types)
      results.append(result)
      if results.count >= limit {
        return .traverseDone
      }
      return .traverseContinue
    }

    func isKanaModifierInsensitiveConversion() -> Bool { false }
  }

  /// Decodes and returns zero query results for the given request.
  public func decode(_ request: ConversionRequest) -> [PredictionResult] {
    // There are 4 sources in zero query suggestion.

    var historyValue = request.converterHistoryValue(1)
    var historyKey = request.converterHistoryKey(1)

    if historyValue.isEmpty && historyKey.isEmpty {
      // (b/475682454): Use the preceding text as the history value and key.
      // We may want to tokenize the preceding text to increase the coverage.
      historyValue = request.context().precedingText
      historyKey = historyValue
    }

    if historyKey.isEmpty || historyValue.isEmpty {
      return []
    }

    var results: [PredictionResult] = []

    // 1. Supplemental model.
    modules.predictionSupplementalModel().predict(request, &results)

    // 2. Zero query weekday prediction.
    // "9/16" -> " (水)"
    _ = aggregateWeekdayZeroQuery(request, &results)

    // 3. Zero query number dictionary(data / zero_query /
    // zero_query_number.def) "30" -> "年"
    // TODO(taku): Consider to aggregate other candidates.
    if aggregateNumberZeroQuery(request, &results) {
      return results
    }

    // 4. Zero query dictionary (data/zero_query/zero_query.def)
    // "あけまして" -> "おめでとうございます”
    let kId: UInt16 = 0  // EOS
    getZeroQueryCandidatesForKey(request, historyValue, zeroQueryDict, kId, kId, &results)

    // Special treatment for email address.
    // "user@" -> "google.com"
    if Self.isEmailPrefix(historyKey) && historyKey.bytesEqual(historyValue) {
      getZeroQueryCandidatesForKey(request, "@", zeroQueryDict, kId, kId, &results)
    }

    // 5. English decoder.
    modules.predictionSupplementalModel().decodeEnglish(request, &results)

    // We do not want zero query results from suffix dictionary for Latin
    // input mode. For example, we do not need "です", "。" just after "when".
    if RequestUtil.isLatinInputMode(request) {
      return results
    }

    // We do not want zero query results from suffix dictionary if the request
    // does not have the history POS information.
    // (b/475682454): Context does not have POS information. Suffix dictionary
    // may generate noisy predictions.
    if request.converterHistoryRid() == 0 {
      return results
    }

    // 6. Zero query suffix dictionary.
    //    "東京" -> "は"
    if results.isEmpty || !Self.isZeroQuerySuffixPredictionDisabled(request)
      || RequestUtil.isHandwriting(request)
    {
      // Uses larger cutoff (kPredictionMaxResultsSize) in order to consider
      // all suffix entries.
      let (base, expanded) = request.composer().getQueriesForPrediction()
      if expanded.isEmpty {
        let callback = SuffixLookupCallback(
          Attribute.suffixDictionary, kPredictionMaxResultsSize, zipCodeId, unknownId)
        swap(&callback.results, &results)
        suffixDictionary.lookupPredictive(base, options: request.options(), callback: callback)
        swap(&callback.results, &results)
      } else {
        for expandedChar in expanded {
          let requestKey = base + expandedChar
          let callback = SuffixLookupCallback(
            Attribute.suffixDictionary, kPredictionMaxResultsSize, zipCodeId, unknownId)
          swap(&callback.results, &results)
          suffixDictionary.lookupPredictive(
            requestKey, options: request.options(), callback: callback)
          swap(&callback.results, &results)
        }
      }
    }

    return results
  }

  /// Returns true if we add weekday zero query results.
  func aggregateWeekdayZeroQuery(
    _ request: ConversionRequest, _ results: inout [PredictionResult]
  ) -> Bool {
    if !request.request().decoderExperimentParams.enableWeekdayZeroQueryPrediction {
      return false
    }

    let lastHistoryValue = request.converterHistoryValue(1)
    let fullHistoryValue = request.converterHistoryValue(-1)
    let precedingText = request.context().precedingText

    // If the committed history or surrounding context already ends with a
    // weekday expression (e.g., immediately after selecting " (水)" following
    // "9/16"), suppress weekday prediction and remove any redundant weekday
    // or open-parenthesis candidates from `results` so that weekday
    // candidates are not suggested repeatedly.
    if DecoderUtil.endsWithWeekdayExpression(lastHistoryValue)
      || DecoderUtil.endsWithWeekdayExpression(fullHistoryValue)
      || (lastHistoryValue.isEmpty && DecoderUtil.endsWithWeekdayExpression(precedingText))
    {
      results.removeAll { DecoderUtil.isRedundantForWeekdayPrediction($0.value) }
      return false
    }

    var weekdayOpt: Weekday?
    if lastHistoryValue.isEmpty {
      weekdayOpt = DateUtil.getWeekdayFromTrailingDate(precedingText)
    } else {
      weekdayOpt = DateUtil.getWeekdayFromTrailingDate(lastHistoryValue)
      if weekdayOpt == nil && !fullHistoryValue.bytesEqual(lastHistoryValue) {
        weekdayOpt = DateUtil.getWeekdayFromTrailingDate(fullHistoryValue)
      }
      if weekdayOpt == nil && !precedingText.isEmpty
        && !DecoderUtil.endsWithWeekdayExpression(precedingText)
      {
        // On keyboards where '/' is committed directly to the editor while
        // digits go through Mozc composition (e.g., Gboard's ?123 digit
        // keyboard), typing "9/16" clears converter history on "9/" (because
        // HistoryReconstructor rejects '/') and leaves `preceding_text` =
        // "9/" and `last_history_value` = "16". Alternatively, if
        // HistoryReconstructor ran on "9/16", `preceding_text` is "9/16" and
        // `last_history_value` is "16".
        if precedingText.hasByteSuffix(lastHistoryValue) {
          weekdayOpt = DateUtil.getWeekdayFromTrailingDate(precedingText)
        } else {
          weekdayOpt = DateUtil.getWeekdayFromTrailingDate(precedingText + lastHistoryValue)
        }
      }
    }
    guard let weekday = weekdayOpt else {
      return false
    }

    // Remove any hallucinated weekday or redundant open-parenthesis
    // candidates generated by statistical language models (N-gram / neural
    // LM) prior to date zero-query decoding.
    results.removeAll { DecoderUtil.isRedundantForWeekdayPrediction($0.value) }

    let shortWd = DateUtil.getShortWeekdayString(weekday)
    let shortWdReading = DateUtil.getShortWeekdayReading(weekday)
    if shortWd.isEmpty || shortWdReading.isEmpty {
      return false
    }

    // Assign BOS/EOS POS (0) like general zero-query dictionary candidates
    // and a lower wcost so that the day-of-week candidate consistently ranks
    // first after both slash dates ("9/16") and Kanji dates ("9月16日"). Also
    // set DISABLE_RESCORING so that neural LM rescoring does not overwrite
    // this deterministic candidate's cost or demote it below general
    // suffixes, and NO_LEARNING so dynamic date-to-weekday pairs are not
    // persisted in user history.
    let kWeekdayWcost = -500
    let kEosId: UInt16 = 0
    var result = PredictionResult()
    result.setTypesAndTokenAttributes(Attribute.suffixDictionary, Token.Attribute.none)
    result.attributes |= Attribute.noLearning | Attribute.disableRescoring
    result.key = shortWdReading
    result.value = " (" + shortWd + ")"
    result.wcost = kWeekdayWcost
    result.lid = kEosId
    result.rid = kEosId
    results.append(result)

    return true
  }

  /// Returns true if we add zero query result.
  private func aggregateNumberZeroQuery(
    _ request: ConversionRequest, _ results: inout [PredictionResult]
  ) -> Bool {
    guard let numberKey = Self.getNumberHistory(request) else {
      return false
    }

    getZeroQueryCandidatesForKey(
      request, numberKey, zeroQueryNumberDict, counterSuffixWordId, counterSuffixWordId, &results)

    getZeroQueryCandidatesForKey(
      request, "default", zeroQueryNumberDict, counterSuffixWordId, counterSuffixWordId, &results)

    return true
  }

  /// Looks up the given range and appends zero query candidate list for
  /// |key| to |results|.
  func getZeroQueryCandidatesForKey(
    _ request: ConversionRequest, _ key: String, _ dict: ZeroQueryDict, _ lid: UInt16,
    _ rid: UInt16, _ results: inout [PredictionResult]
  ) {
    let entries = dict.equalRange(key)
    if entries.isEmpty {
      return
    }

    let isKeyOneCharAndNotKanji =
      Util.charsLen(key) == 1 && !Util.containsScriptType(key, .kanji)

    var cost = 0
    let kSuffixPenalty = 10

    func addEntry(_ entry: ZeroQueryEntry) {
      var result = PredictionResult()
      result.setTypesAndTokenAttributes(Attribute.suffixDictionary, Token.Attribute.none)
      result.key = dict.value(entry)
      result.value = dict.value(entry)
      result.wcost = cost
      result.lid = lid
      result.rid = rid
      results.append(result)
      cost += kSuffixPenalty
    }

    for i in entries {
      let entry = dict.entry(at: i)
      if entry.type != .emoji {
        addEntry(entry)
        continue
      }

      // Emoji should not be suggested for single Hiragana / Katakana input,
      // because they tend to be too much aggressive.
      if isKeyOneCharAndNotKanji {
        continue
      }

      addEntry(entry)
    }
  }
}
