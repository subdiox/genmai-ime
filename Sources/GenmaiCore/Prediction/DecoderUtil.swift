// Port of mozc/src/prediction/decoder_util.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - The free functions live in the `DecoderUtil` namespace enum; the size
//   constants are module-level like the C++ inline constants.
// - `ResultsSizeAdjuster` is RAII in C++ (it adjusts the size in its
//   destructor). In Swift it records the previous size of an array; callers
//   call `adjustSize(&results)` explicitly where the C++ destructor runs.
// - `PredictiveLookupCallback` appends to its own `results` array instead of
//   a `std::vector<Result>*`. Callers move their array in and out with
//   `swap(&callback.results, &results)` around the lookup so that the size
//   limit sees the already aggregated results, as in C++.
// - `absl::btree_set<std::string>` of subsequent chars is a `[String]`.

import GenmaiBase

public let kSuggestionMaxResultsSize = 256
public let kPredictionMaxResultsSize = 100000

public enum DecoderUtil {
  public static func getCandidateCutoffThreshold(_ requestType: RequestType) -> Int {
    assert(
      requestType == .prediction || requestType == .suggestion
        || requestType == .partialPrediction || requestType == .partialSuggestion)
    if requestType == .prediction || requestType == .partialPrediction {
      return kPredictionMaxResultsSize
    }
    return kSuggestionMaxResultsSize
  }

  public static func isNoisyNumberToken(
    _ key: some StringProtocol, _ originalKeyLen: Int, _ token: Token
  ) -> Bool {
    let origKey = key.byteSubstring(from: 0, length: originalKeyLen)
    if !NumberUtil.isArabicNumber(origKey) {
      return false
    }
    let origKeySize = origKey.utf8.count
    let keySuffix = token.key.byteSubstring(from: origKeySize)
    if keySuffix.isEmpty {
      return false
    }
    if Util.getFirstScriptType(keySuffix) == .number {
      // If the key is "1", the token "10がつ" is noisy because the suffix
      // starts from a number. i.e. "0がつ".
      return true
    }

    if !token.value.hasBytePrefix(origKey) {
      return false
    }

    let valueSuffix = token.value.byteSubstring(from: origKeySize)
    if valueSuffix.isEmpty {
      return false
    }
    if Util.getFirstScriptType(valueSuffix) == .number {
      return true
    }
    return Util.charsLen(valueSuffix) >= 3
  }

  private static let kParenthesizedWeekdays: [String] = [
    "(月)", "(火)", "(水)", "(木)", "(金)", "(土)", "(日)",
    "（月）", "（火）", "（水）", "（木）", "（金）", "（土）", "（日）",
  ]

  private static let kRedundantWeekdayCandidates: [String] = [
    "(", "（", "()", "（）", "(月)", "(火)", "(水)",
    "(木)", "(金)", "(土)", "(日)", "（月）", "（火）", "（水）",
    "（木）", "（金）", "（土）", "（日）", "月曜", "火曜", "水曜",
    "木曜", "金曜", "土曜", "日曜", "月曜日", "火曜日", "水曜日",
    "木曜日", "金曜日", "土曜日", "日曜日",
  ]

  private static let kWeekdaySuffixes: [String] = [
    "(月)", "(火)", "(水)", "(木)", "(金)", "(土)", "(日)",
    "（月）", "（火）", "（水）", "（木）", "（金）", "（土）", "（日）",
    "月曜", "火曜", "水曜", "木曜", "金曜", "土曜", "日曜",
    "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日", "日曜日",
  ]

  public static func isStandaloneParenthesizedWeekday(_ text: some StringProtocol) -> Bool {
    let stripped = Strings.stripWhitespace(text)
    return kParenthesizedWeekdays.contains { $0.bytesEqual(stripped) }
  }

  public static func isRedundantForWeekdayPrediction(_ text: some StringProtocol) -> Bool {
    let stripped = Strings.stripWhitespace(text)
    return kRedundantWeekdayCandidates.contains { $0.bytesEqual(stripped) }
  }

  public static func endsWithWeekdayExpression(_ text: some StringProtocol) -> Bool {
    let stripped = Strings.stripTrailingWhitespace(text)
    return kWeekdaySuffixes.contains { stripped.hasByteSuffix($0) }
  }
}

/// `ResultsSizeAdjuster`: rolls back the results added after its creation if
/// their number reaches the cutoff threshold.
public struct ResultsSizeAdjuster {
  public let cutoffThreshold: Int
  public let prevSize: Int

  public init(_ request: ConversionRequest, _ results: [PredictionResult]) {
    cutoffThreshold = DecoderUtil.getCandidateCutoffThreshold(request.requestType())
    prevSize = results.count
  }

  public func adjustSize(_ results: inout [PredictionResult]) {
    let addedSize = results.count - prevSize
    if addedSize >= cutoffThreshold {
      results.removeSubrange(prevSize...)
    }
  }

  /// Returns the range of newly added results.
  public func getAddedResults(_ results: [PredictionResult]) -> Range<Int> {
    prevSize..<results.count
  }
}

/// `PredictiveLookupCallback`. Subclasses must `override` the methods (see
/// the protocol default dispatch pitfall in CLAUDE.md); every requirement of
/// DictionaryCallback is implemented here.
open class PredictiveLookupCallback: DictionaryCallback {
  public var penalty: Int32 = 0
  public let types: PredictionTypes
  public let limit: Int
  public let originalKeyLen: Int
  public let subsequentChars: [String]?
  public let zipCodeId: Int
  public let unknownId: Int
  public var results: [PredictionResult] = []

  public init(
    _ types: PredictionTypes, _ limit: Int, _ originalKeyLen: Int,
    _ subsequentChars: [String], _ zipCodeId: Int, _ unknownId: Int
  ) {
    self.types = types
    self.limit = limit
    self.originalKeyLen = originalKeyLen
    self.subsequentChars = subsequentChars
    self.zipCodeId = zipCodeId
    self.unknownId = unknownId
  }

  public init(
    _ types: PredictionTypes, _ limit: Int, _ originalKeyLen: Int, _ zipCodeId: Int,
    _ unknownId: Int
  ) {
    self.types = types
    self.limit = limit
    self.originalKeyLen = originalKeyLen
    self.subsequentChars = nil
    self.zipCodeId = zipCodeId
    self.unknownId = unknownId
  }

  open func rewriteResult(_ result: inout PredictionResult) {}

  open func onKey(_ key: String) -> DictionaryCallbackResult {
    guard let subsequentChars, !subsequentChars.isEmpty else {
      return .traverseContinue
    }
    let rest = key.byteSubstring(from: originalKeyLen)
    for chr in subsequentChars {
      if rest.hasBytePrefix(chr) {
        return .traverseContinue
      }
    }
    return .traverseNextKey
  }

  open func onActualKey(_ key: String, _ actualKey: String, _ numExpanded: Int)
    -> DictionaryCallbackResult
  {
    penalty = getSpatialCostPenalty(numExpanded)
    return .traverseContinue
  }

  open func onToken(_ key: String, _ actualKey: String, _ token: Token) -> DictionaryCallbackResult {
    if ((token.attributes & Token.Attribute.userDictionary) != 0 && Int(token.lid) == unknownId)
      || Int(token.lid) == zipCodeId
    {
      let origKey = key.byteSubstring(from: 0, length: originalKeyLen)
      if !token.key.bytesEqual(origKey) {
        return .traverseContinue
      }
    }
    if DecoderUtil.isNoisyNumberToken(key, originalKeyLen, token) {
      return .traverseContinue
    }

    var result = PredictionResult()
    result.initializeByTokenAndTypes(token, types)
    result.wcost += Int(penalty)
    if penalty > 0 {
      result.attributes |= Attribute.keyExpandedInDictionary
    }
    rewriteResult(&result)
    results.append(result)
    return (results.count < limit) ? .traverseContinue : .traverseDone
  }

  open func isKanaModifierInsensitiveConversion() -> Bool { false }
}

/// Bytewise key for hash containers (C++ `std::string` keys compare bytes;
/// Swift `String` equality is canonical equivalence).
struct PredictionBytesKey: Hashable {
  let bytes: [UInt8]
  init(_ s: some StringProtocol) { bytes = Array(s.utf8) }
}
