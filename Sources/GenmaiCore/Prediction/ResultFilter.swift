// Port of mozc/src/prediction/result_filter.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - The namespace `mozc::prediction::filter` is the `ResultFilter` class
//   (stateful filter) plus the static functions `getMissSpelledPosition` and
//   `removeRedundantResults` on it.
// - The seen set compares values bytewise.

import GenmaiBase

public final class ResultFilter {
  // Bit field.
  public struct SuggestionFilterStrategy {
    public static let kSkipFilter: UInt32 = 0
    // Applied against result's value
    public static let kFilterByValue: UInt32 = 1
    // Applied against the concatenation of history value and result's value
    public static let kFilterByHistoryAndValue: UInt32 = 2
    // Applied against "<NWP>" + result's value
    public static let kFilterByNwp: UInt32 = 4
  }

  public static let kSkipFilter = SuggestionFilterStrategy.kSkipFilter
  public static let kFilterByValue = SuggestionFilterStrategy.kFilterByValue
  public static let kFilterByHistoryAndValue = SuggestionFilterStrategy.kFilterByHistoryAndValue
  public static let kFilterByNwp = SuggestionFilterStrategy.kFilterByNwp

  private static let kNwpPrefix = "<NWP>"

  private let requestKey: String
  private let historyValue: String
  private let requestKeyLen: Int
  private let connector: Connector
  private let suggestionFilter: any SuggestionFilterProtocol
  private let isMixedConversion: Bool
  private let autoPartialSuggestion: Bool
  private let includeExactKey: Bool
  private let isHandwriting: Bool
  private let suffixNwpTransitionCostThreshold: Int
  private let historyRid: Int

  private var suffixCount = 0
  private var predictiveCount = 0
  private var realtimeCount = 0
  private var prefixTcCount = 0
  private var tcCount = 0

  // Seen set for dup value check.
  private var seen = Set<PredictionBytesKey>()

  public init(
    _ request: ConversionRequest, _ connector: Connector,
    _ suggestionFilter: any SuggestionFilterProtocol
  ) {
    requestKey = request.key()
    historyValue = request.converterHistoryValue(1)
    requestKeyLen = Util.charsLen(requestKey)
    self.connector = connector
    self.suggestionFilter = suggestionFilter
    isMixedConversion = request.request().mixedConversion
    autoPartialSuggestion = RequestUtil.isAutoPartialSuggestionEnabled(request)
    includeExactKey = request.request().mixedConversion
    isHandwriting = RequestUtil.isHandwriting(request)
    suffixNwpTransitionCostThreshold = Int(
      request.request().decoderExperimentParams.suffixNwpTransitionCostThreshold)
    historyRid = request.converterHistoryRid()
  }

  /// `x++` on an Int (returns the old value).
  private static func postIncrement(_ x: inout Int) -> Int {
    defer { x += 1 }
    return x
  }

  public func shouldRemove(_ result: PredictionResult, _ addedNum: Int) -> Bool {
    if result.removed {
      return true
    }

    if result.cost >= PredictionResult.invalidCost {
      return true
    }

    if !autoPartialSuggestion && (result.attributes & Attribute.partiallyKeyConsumed) != 0 {
      return true
    }

    do {
      let strategies = selectSuggestionFilterStrategies(result)
      if (strategies & Self.kFilterByValue) != 0
        && suggestionFilter.isBadSuggestion(result.value)
      {
        return true
      }
      if (strategies & Self.kFilterByHistoryAndValue) != 0
        && suggestionFilter.isBadSuggestion(historyValue + result.value)
      {
        return true
      }
      if (strategies & Self.kFilterByNwp) != 0
        && suggestionFilter.isBadSuggestion(Self.kNwpPrefix + result.value)
      {
        return true
      }
    }

    if isHandwriting {
      // Only unigram results are appended for handwriting and we do not need to
      // apply filtering.
      return false
    }

    // Don't suggest exactly the same candidate as key.
    // if |include_exact_key| is true, that's not the case.
    if !includeExactKey && (result.attributes & Attribute.realtimeConversion) == 0
      && requestKey.bytesEqual(result.value)
    {
      return true
    }

    if seen.contains(PredictionBytesKey(result.value)) {
      return true
    }

    // User input: "おーすとり" (len = 5)
    // key/value:  "おーすとりら" "オーストラリア" (miss match pos = 4)
    if (result.attributes & Attribute.spellingCorrection) != 0
      && !result.key.bytesEqual(requestKey)
      && requestKeyLen <= Self.getMissSpelledPosition(result.key, result.value) + 1
    {
      return true
    }

    let lookupKeyLen = Util.charsLen(requestKey)

    if suffixNwpTransitionCostThreshold > 0 && lookupKeyLen == 0 && historyRid != 0
      && (result.attributes & Attribute.suffixDictionary) != 0
      && connector.getTransitionCost(UInt16(truncatingIfNeeded: historyRid), result.lid)
        > suffixNwpTransitionCostThreshold
    {
      return true
    }

    if (result.attributes & Attribute.suffixDictionary) != 0
      && Self.postIncrement(&suffixCount) >= 20
    {
      // TODO(toshiyuki): Need refactoring for controlling suffix
      // prediction number after we will fix the appropriate number.
      return true
    }

    let checkDupAndReturn = { (value: String) -> Bool in
      !self.seen.insert(PredictionBytesKey(value)).inserted
    }

    if !isMixedConversion {
      return checkDupAndReturn(result.value)
    }

    // Suppress long candidates to show more candidates in the candidate view.
    let candidateKeyLen = Util.charsLen(result.key)
    if lookupKeyLen > 0  // Do not filter for zero query
      && lookupKeyLen < candidateKeyLen
      && (Self.postIncrement(&predictiveCount) >= 3 || addedNum >= 10)
    {
      return true
    }

    if (result.attributes & Attribute.realtimeConversion) != 0
      // Do not remove one-segment / on-char realtime candidates
      // example:
      // - "勝った" for the reading, "かった".
      // - "勝" for the reading, "かつ".
      && result.innerSegmentBoundary.count >= 2
      && Util.charsLen(result.value) != 1
      && (Self.postIncrement(&realtimeCount) >= 3 || addedNum >= 5)
    {
      return true
    }

    let kTcMaxCount = 3
    let kTcMaxRank = 10

    if (result.attributes & Attribute.typingCorrection) != 0
      && (Self.postIncrement(&tcCount) >= kTcMaxCount || addedNum >= kTcMaxRank)
    {
      return true
    }

    if (result.attributes & Attribute.partiallyKeyConsumed) != 0
      && (result.attributes & Attribute.typingCorrection) != 0
      && (Self.postIncrement(&prefixTcCount) >= 3 || addedNum >= 10)
    {
      return true
    }

    return checkDupAndReturn(result.value)
  }

  /// Select how to apply the suggestion filter against `result`. Returns a
  /// bit fields of `SuggestionFilterStrategy`.
  public func selectSuggestionFilterStrategies(_ result: PredictionResult) -> UInt32 {
    Self.selectSuggestionFilterStrategies(result, requestKey, historyValue, includeExactKey)
  }

  public static func selectSuggestionFilterStrategies(
    _ result: PredictionResult, _ requestKey: some StringProtocol,
    _ historyValue: some StringProtocol, _ includeExactKey: Bool
  ) -> UInt32 {
    // For next word prediction, we always apply the filter by value,
    // history+value, and <NWP>-prefixed entries.
    if requestKey.isEmpty || result.key.isEmpty {
      return kFilterByValue | kFilterByHistoryAndValue | kFilterByNwp
    }

    if includeExactKey {
      // If `include_exact_key_` is true, we don't apply the filter to the
      // results which have exactly the same key as the request. Consequently,
      // such candidates can appear even if they are bad suggestion.
      return result.key.bytesEqual(requestKey) ? kSkipFilter : kFilterByValue
    }

    // Apply the filter by value by default.
    return kFilterByValue
  }

  /// Returns the position of misspelled character position.
  ///
  /// Example:
  /// key: "れみおめろん"
  /// value: "レミオロメン"
  /// returns 3
  ///
  /// Example:
  /// key: "ろっぽんぎ"
  /// value: "六本木"
  /// returns 5 (charslen("六本木"))
  public static func getMissSpelledPosition(
    _ key: some StringProtocol, _ value: some StringProtocol
  ) -> Int {
    let hiraganaValue = Japanese.katakanaToHiragana(value)
    // value is mixed type. return true if key == request_key.
    if Util.getScriptType(hiraganaValue) != .hiragana {
      return Util.charsLen(key)
    }

    // Find the first position of character where miss spell occurs.
    var position = 0
    var keyIter = key.unicodeScalars.makeIterator()
    var hiraganaIter = hiraganaValue.unicodeScalars.makeIterator()
    var keyChar = keyIter.next()
    var hiraganaChar = hiraganaIter.next()
    while let h = hiraganaChar, let k = keyChar {
      if h != k {
        return position
      }
      hiraganaChar = hiraganaIter.next()
      keyChar = keyIter.next()
      position += 1
    }

    // not find. return the length of key.
    while keyChar != nil {
      position += 1
      keyChar = keyIter.next()
    }

    return position
  }

  private static func maybeRedundant(
    _ referenceResult: PredictionResult, _ targetResult: PredictionResult
  ) -> Bool {
    let reference = referenceResult.value
    let target = targetResult.value

    // Same value means the result is redundant.
    if reference.bytesEqual(target) {
      return true
    }

    // If the key is the same, the target is not redundant as value is
    // different.
    if referenceResult.key.bytesEqual(targetResult.key) {
      return false
    }

    // target is not an appended value of the reference.
    if !target.hasBytePrefix(reference) {
      return false
    }

    // If the suffix is Emoji or unknown script, the result is not redundant.
    // For example, if the reference is "東京", "東京🗼" is not redundant, but
    // "東京タワー" is redundant.
    let suffix = target.byteSubstring(from: reference.utf8.count)
    let scriptType = Util.getScriptType(suffix)
    return scriptType != .emoji && scriptType != .unknownScript
  }

  /// Removes redundant results from `results`.
  public static func removeRedundantResults(_ results: inout [PredictionResult]) {
    let kDeleteTrialNum = 5

    // min_iter is the beginning of the remaining results (inclusive), and
    // max_iter is the end of the remaining results (exclusive).
    var minIter = 0
    var maxIter = results.count
    for _ in 0..<kDeleteTrialNum {
      if minIter == maxIter {
        break
      }

      // Find the Result with minimum cost. Swap it with the beginning element.
      var minElement = minIter
      var j = minIter + 1
      while j < maxIter {
        if resultWCostLess(results[j], results[minElement]) {
          minElement = j
        }
        j += 1
      }
      results.swapAt(minIter, minElement)

      let referenceResult = results[minIter]

      // Preserve the reference result.
      minIter += 1

      // Traverse all remaining elements and check if each result is redundant.
      var iter = minIter
      while iter != maxIter {
        // We do not filter user dictionary word.
        if (results[iter].attributes & Attribute.userDictionary) != 0 {
          iter += 1
          continue
        }
        // If the result is redundant, swap it out.
        if maybeRedundant(referenceResult, results[iter]) {
          maxIter -= 1
          results.swapAt(iter, maxIter)
          continue
        }
        iter += 1
      }
    }

    // Then the |results| contains;
    // [begin, min_iter): reference results in the above loop.
    // [max_iter, end): (maybe) redundant results.
    // [min_iter, max_iter): remaining results.
    // Here, we revive the redundant results up to five in the result cost
    // order.
    let kDoNotDeleteNum = 5
    if results.count - maxIter >= kDoNotDeleteNum {
      // std::partial_sort: only the first kDoNotDeleteNum elements of the
      // tail are kept, and they are sorted. The comparator is a total order,
      // so a selection of the smallest elements yields the same result.
      for k in 0..<kDoNotDeleteNum {
        var m = maxIter + k
        var i = m + 1
        while i < results.count {
          if resultWCostLess(results[i], results[m]) {
            m = i
          }
          i += 1
        }
        results.swapAt(maxIter + k, m)
      }
      maxIter += kDoNotDeleteNum
    } else {
      maxIter = results.count
    }

    results.removeSubrange(maxIter...)
  }
}
