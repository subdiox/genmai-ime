// Port of mozc/src/prediction/result.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - `mozc::prediction::Result` is named `PredictionResult` so that it does not
//   shadow `Swift.Result` inside GenmaiCore.
// - The deprecated `PredictionType` compatibility enum is not ported; use
//   `Attribute` directly. `kPredictionTypesMaskForTesting` is kept as
//   `PredictionResult.predictionTypesMaskForTesting`.
// - The debug-only `log` field and the MOZC_WORD_LOG macro are omitted.
// - Comparisons of strings are bytewise (C++ std::string).

import GenmaiBase

/// Bitfield to store a set of prediction types (`Attribute` bits).
public typealias PredictionTypes = UInt32

public struct PredictionResult: Sendable, Equatable {
  /// A bitmask of all prediction-specific types. Used exclusively in unit tests
  /// to verify the exact expected prediction types while ignoring other
  /// behavioral attributes to keep test assertions consistent and robust.
  public static let predictionTypesMaskForTesting: UInt32 =
    Attribute.unigram | Attribute.bigram | Attribute.realtimeConversion
    | Attribute.suffixDictionary | Attribute.english | Attribute.typingCorrection
    | Attribute.partiallyKeyConsumed | Attribute.number | Attribute.singleKanji
    | Attribute.typingCompletion | Attribute.postCorrection | Attribute.supplementalModel
    | Attribute.weakUserHistoryPrediction | Attribute.realtimeTop
    | Attribute.keyExpandedInDictionary | Attribute.disableRescoring

  /// Used to emulate positive infinity for cost. This value is set for those
  /// candidates that are thought to be aggressive; thus we can eliminate such
  /// candidates from suggestion or prediction. Note that for this purpose we
  /// don't want to use INT_MAX because someone might further add penalty after
  /// cost is set to INT_MAX, which leads to overflow and consequently
  /// aggressive candidates would appear in the top results.
  public static let invalidCost: Int = (2 << 20)

  public static let defaultResult = PredictionResult()

  public var key = ""
  public var value = ""
  public var description = ""
  public var displayValue = ""
  // Boundary information for realtime conversion.
  // This will be set only for realtime conversion result candidates.
  // This contains inner segment size for key and value.
  // If the candidate key and value are
  // "わたしの|なまえは|なかのです", " 私の|名前は|中野です",
  // |inner_segment_boundary| have [(4,2), (4, 3), (5, 4)].
  public var innerSegmentBoundary: InnerSegmentBoundary = []

  // Unified attributes field.
  public var attributes: UInt32 = Attribute.defaultAttribute
  // Context "insensitive" candidate cost.
  public var wcost: Int = 0
  // Context "sensitive" candidate cost.
  public var cost: Int = 0
  public var consumedKeySize: UInt32 = 0
  // The total penalty added to this result.
  public var penalty: Int = 0
  // The original cost before rescoring. Used for debugging purpose.
  public var costBeforeRescoring: Int = 0
  // Confidence score of typing correction. Larger is more confident.
  public var typingCorrectionScore: Float = 0.0
  // Adjustment for `wcost` made by the typing correction. This value can be
  // zero, positive (penalty) or negative (bonus), and it is added to `wcost`.
  public var typingCorrectionAdjustment: Int = 0
  // The probability of post correction. When zero, this candidate is not
  // handed by the post-correction component.
  public var postCorrectionProb: Float = 0.0

  public var lid: UInt16 = 0
  public var rid: UInt16 = 0
  // If removed is true, this result is not used for a candidate.
  public var removed = false

  public init() {}

  public mutating func initializeByTokenAndTypes(_ token: Token, _ types: PredictionTypes) {
    setTypesAndTokenAttributes(types, token.attributes)
    key = token.key
    value = token.value
    wcost = token.cost
    lid = token.lid
    rid = token.rid
  }

  public mutating func setTypesAndTokenAttributes(
    _ predictionTypes: PredictionTypes, _ tokenAttr: Token.AttributesBitfield
  ) {
    attributes = predictionTypes
    if attributes & Attribute.realtimeTop != 0 {
      attributes |= Attribute.noVariantsExpansion
    }
    if tokenAttr & Token.Attribute.spellingCorrection != 0 {
      attributes |= Attribute.spellingCorrection
    }
    if tokenAttr & Token.Attribute.userDictionary != 0 {
      attributes |=
        (Attribute.userDictionary | Attribute.noModification
          | Attribute.noVariantsExpansion)
    }
  }

  /// Returns only the behavioral/semantic attributes (e.g. USER_DICTIONARY,
  /// SPELLING_CORRECTION) by masking out the prediction-specific flags.
  public func getBehavioralAttributes() -> UInt32 { attributes & 0xFFFFF }

  /// Returns only the prediction-specific types (e.g. UNIGRAM, BIGRAM).
  public func getPredictionTypesForTesting() -> UInt32 {
    attributes & PredictionResult.predictionTypesMaskForTesting
  }

  public func innerSegments() -> InnerSegments {
    InnerSegments(key: key, value: value, innerSegmentBoundary: innerSegmentBoundary)
  }

  /// `AbslStringify` (release build format, without the debug log).
  public var debugString: String {
    "key: \(key), value: \(value), attrs: \(attributes), wcost: \(wcost), cost: \(cost), "
      + "cost_before: \(costBeforeRescoring), lid: \(lid), rid: \(rid), "
      + "bdd: \(innerSegmentBoundary.map(String.init).joined(separator: ",")), "
      + "consumed_key_size: \(consumedKeySize), penalty: \(penalty), "
      + "tc_adjustment: \(typingCorrectionAdjustment), removed: \(removed), "
      + "post_correction_prob: \(String(format: "%f", postCorrectionProb)), "
      + "typing_correction_score: \(String(format: "%f", typingCorrectionScore))"
  }

  public static func == (lhs: PredictionResult, rhs: PredictionResult) -> Bool {
    lhs.key.bytesEqual(rhs.key) && lhs.value.bytesEqual(rhs.value)
      && lhs.description.bytesEqual(rhs.description)
      && lhs.displayValue.bytesEqual(rhs.displayValue)
      && lhs.innerSegmentBoundary == rhs.innerSegmentBoundary
      && lhs.attributes == rhs.attributes && lhs.wcost == rhs.wcost && lhs.cost == rhs.cost
      && lhs.consumedKeySize == rhs.consumedKeySize && lhs.penalty == rhs.penalty
      && lhs.costBeforeRescoring == rhs.costBeforeRescoring
      && lhs.typingCorrectionScore == rhs.typingCorrectionScore
      && lhs.typingCorrectionAdjustment == rhs.typingCorrectionAdjustment
      && lhs.postCorrectionProb == rhs.postCorrectionProb && lhs.lid == rhs.lid
      && lhs.rid == rhs.rid && lhs.removed == rhs.removed
  }
}

extension PredictionResult: InnerSegmentValueRewritable {
  /// prediction::Result has no content_value.
  public static var hasContentValue: Bool { false }
  public var rewritableContentValue: String {
    get { "" }
    set {}
  }
}

extension PredictionResult: ConversionRequestHistoryResult {
  public func historySuffixKeyAndValue(_ size: Int) -> (key: String, value: String) {
    let (k, v) = innerSegments().getSuffixKeyAndValue(size)
    return (String(k), String(v))
  }
  public var historyInnerSegmentsSize: Int { innerSegments().size }
  public var historyRid: Int { Int(rid) }
  public var historyCost: Int { cost }
}

public enum ResultInternal {
  /// ValueLess returns if lhs is less than rhs by comparing the two strings by
  /// the number of Unicode characters and then value.
  /// Examples,
  ///  "ん" < "あいうえお"
  ///  "あいうえお" < "かきくけこ"
  ///  "テスト1" < "テスト00"
  public static func valueLess(_ lhsIn: some StringProtocol, _ rhsIn: some StringProtocol) -> Bool {
    var lhs = Array(lhsIn.utf8)[...]
    var rhs = Array(rhsIn.utf8)[...]
    // This loop processes lhs and rhs in one pass.
    while !lhs.isEmpty && !rhs.isEmpty {
      // Read each Unicode character.
      let (lhsChar, lhsRest) = Strings.frontChar(lhs)
      let (rhsChar, rhsRest) = Strings.frontChar(rhs)
      lhs = lhsRest
      rhs = rhsRest
      if !lhsChar.elementsEqual(rhsChar) {
        // If they're different, count the number of characters first.
        var lhsIt = lhs.startIndex
        var rhsIt = rhs.startIndex
        while lhsIt < lhs.endIndex && rhsIt < rhs.endIndex {
          lhsIt += Strings.oneCharLen(lhs[lhsIt])
          rhsIt += Strings.oneCharLen(rhs[rhsIt])
        }
        // Note: like the C++ iterator arithmetic, an iterator can step past
        // the end on ill-formed input; ">=" treats that as the end.
        let lhsEnd = lhsIt >= lhs.endIndex
        let rhsEnd = rhsIt >= rhs.endIndex
        if lhsEnd && rhsEnd {
          // Same lengths, use the codepoint order.
          return Strings.compareBytes(lhsChar, rhsChar) < 0
        } else {
          // Different lengths. Check if lhs is shorter.
          return lhsEnd
        }
      }
    }
    // Here, the numbers of chars in lhs and rhs are different.
    // Return true if the remaining lhs is shorter than the remaining lhs.
    return lhs.count < rhs.count
  }

  /// TiebreakLess returns if lhs is less than rhs by comparing the two results.
  /// This is used for tie breaking when cost, wcost and value are the same.
  /// "less than" here means "has higher priority (= lower cost)".
  public static func tiebreakLess(_ lhs: PredictionResult, _ rhs: PredictionResult) -> Bool {
    // Key is the primary tiebreaker.
    let keyCmp = lhs.key.compareBytes(rhs.key)
    if keyCmp != 0 {
      return keyCmp < 0
    }
    // Prioritize the result with candidate_attributes (behavioral part).
    let lhsBehavioral = lhs.getBehavioralAttributes()
    let rhsBehavioral = rhs.getBehavioralAttributes()
    if lhsBehavioral != rhsBehavioral {
      if lhsBehavioral == 0 {
        return false
      }
      if rhsBehavioral == 0 {
        return true
      }
      return lhsBehavioral < rhsBehavioral
    }
    // Then, use the rest of the fields (std::tie lexicographic comparison).
    func cmp<T: Comparable>(_ a: T, _ b: T) -> Int { a < b ? -1 : (b < a ? 1 : 0) }
    let comparisons: [() -> Int] = [
      { cmp(lhs.wcost, rhs.wcost) },
      { cmp(lhs.cost, rhs.cost) },
      { cmp(lhs.attributes, rhs.attributes) },
      { cmp(lhs.lid, rhs.lid) },
      { cmp(lhs.rid, rhs.rid) },
      { cmp(lhs.consumedKeySize, rhs.consumedKeySize) },
      { cmp(lhs.penalty, rhs.penalty) },
      { cmp(lhs.costBeforeRescoring, rhs.costBeforeRescoring) },
      { cmp(lhs.removed ? 1 : 0, rhs.removed ? 1 : 0) },
      { cmp(lhs.typingCorrectionScore, rhs.typingCorrectionScore) },
      { cmp(lhs.typingCorrectionAdjustment, rhs.typingCorrectionAdjustment) },
      { cmp(lhs.postCorrectionProb, rhs.postCorrectionProb) },
      { lhs.description.compareBytes(rhs.description) },
      { lhs.displayValue.compareBytes(rhs.displayValue) },
      {
        lhs.innerSegmentBoundary.lexicographicallyPrecedes(rhs.innerSegmentBoundary)
          ? -1 : (rhs.innerSegmentBoundary.lexicographicallyPrecedes(lhs.innerSegmentBoundary) ? 1 : 0)
      },
    ]
    for c in comparisons {
      let r = c()
      if r != 0 { return r < 0 }
    }
    return false
  }
}

/// Comparator for sorting prediction candidates.
/// If we have words A and AB, for example "六本木" and "六本木ヒルズ",
/// assume that cost(A) < cost(AB).
public func resultWCostLess(_ lhs: PredictionResult, _ rhs: PredictionResult) -> Bool {
  if lhs.wcost != rhs.wcost {
    return lhs.wcost < rhs.wcost
  }
  if !lhs.value.bytesEqual(rhs.value) {
    return ResultInternal.valueLess(lhs.value, rhs.value)
  }
  return ResultInternal.tiebreakLess(lhs, rhs)
}

/// Returns true if `lhs` is less than `rhs`.
public func resultCostLess(_ lhs: PredictionResult, _ rhs: PredictionResult) -> Bool {
  if lhs.cost != rhs.cost {
    return lhs.cost < rhs.cost
  }
  if !lhs.value.bytesEqual(rhs.value) {
    return ResultInternal.valueLess(lhs.value, rhs.value)
  }
  return ResultInternal.tiebreakLess(lhs, rhs)
}

/// Populates the typing correction result in `query` to prediction::Result.
public func populateTypeCorrectedQuery(
  _ typingCorrectedResult: TypeCorrectedQuery, _ result: inout PredictionResult
) {
  if typingCorrectedResult.type.contains(.correction) {
    result.attributes |= Attribute.typingCorrection
  }
  if typingCorrectedResult.type.contains(.completion) {
    result.attributes |= Attribute.typingCompletion
  }
  result.typingCorrectionScore = typingCorrectedResult.score
  // bias = hyp_score - base_score, so larger is better.
  // bias is computed in log10 domain, so we need to use the different
  // scale factor. 500 * log(10) = ~1150.
  let adjustment = Int(-1150 * typingCorrectedResult.bias)
  result.typingCorrectionAdjustment = adjustment
  result.wcost += adjustment
}

/// Makes debug string from `types`.
public func getPredictionTypeDebugString(_ types: PredictionTypes) -> String {
  var debugDesc = ""
  if types & Attribute.unigram != 0 {
    debugDesc.append("U")
  }
  if types & Attribute.bigram != 0 {
    debugDesc.append("B")
  }
  if types & Attribute.realtimeTop != 0 {
    debugDesc.append("R1")
  } else if types & Attribute.realtimeConversion != 0 {
    debugDesc.append("R")
  }
  if types & Attribute.suffixDictionary != 0 {
    debugDesc.append("S")
  }
  if types & Attribute.english != 0 {
    debugDesc.append("E")
  }
  if types & Attribute.typingCorrection != 0 {
    debugDesc.append("T")
  }
  if types & Attribute.typingCompletion != 0 {
    debugDesc.append("C")
  }
  if types & Attribute.supplementalModel != 0 {
    debugDesc.append("X")
  }
  if types & Attribute.keyExpandedInDictionary != 0 {
    debugDesc.append("K")
  }
  return debugDesc
}
