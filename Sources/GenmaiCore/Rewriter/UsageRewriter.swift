// Port of mozc/src/rewriter/usage_rewriter.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - `absl::flat_hash_map<StrPair, const UsageDictItem*>` is a Swift
//   `Dictionary` keyed by the bytes of the (key, value) pair (bytewise
//   identity, as in C++) whose values are indices into the usage item array.
//   Its iteration order is never observed.
// - `GetKanjiPrefixAndOneHiragana` is `internal static` and the string array
//   is `internal` (the C++ test peer accesses them).
// - The `NO_USAGE_REWRITER` build flag is not supported (always enabled).

import GenmaiBase
import GenmaiProtocol

public final class UsageRewriter: RewriterInterface {
  struct UsageDictItem {
    var usageId: UInt32 = 0
    var keyIndex: UInt32 = 0
    var valueIndex: UInt32 = 0
    var conjugationId: UInt32 = 0
    var meaningIndex: UInt32 = 0
  }

  private static let kUsageDictItemSize = 20  // sizeof(UsageDictItem)

  private struct StrPair: Hashable {
    let first: [UInt8]
    let second: [UInt8]
  }

  private var keyValueUsageitemMap: [StrPair: Int] = [:]
  private var usageItems: [UsageDictItem] = []
  private let dictionary: any DictionaryInterface
  private let posMatcher: PosMatcher
  private let baseConjugationSuffix: DataView
  private(set) var stringArray = SerializedStringArray()

  public init(
    _ baseConjugationSuffixData: DataView, _ conjugationSuffixData: DataView,
    _ conjugationIndexData: DataView, _ usageItemsData: DataView, _ stringArrayData: DataView,
    _ dictionary: any DictionaryInterface, _ posMatcher: PosMatcher
  ) {
    self.dictionary = dictionary
    self.posMatcher = posMatcher
    baseConjugationSuffix = baseConjugationSuffixData
    let conjugationSuffix = conjugationSuffixData
    let conjugationSuffixDataIndex = conjugationIndexData

    if SerializedStringArray.verifyData(stringArrayData) {
      stringArray.set(stringArrayData)
    } else {
      // \0\0\0\0 is the header value of the data size.
      stringArray = SerializedStringArray(bytes: [0, 0, 0, 0]) ?? SerializedStringArray()
    }

    func u32(_ view: DataView, _ index: Int) -> Int {
      Int(view.load(fromByteOffset: index * 4, as: UInt32.self))
    }

    let n = usageItemsData.count / UsageRewriter.kUsageDictItemSize
    usageItems.reserveCapacity(n)
    for t in 0..<n {
      let base = t * 5
      usageItems.append(
        UsageDictItem(
          usageId: UInt32(u32(usageItemsData, base)),
          keyIndex: UInt32(u32(usageItemsData, base + 1)),
          valueIndex: UInt32(u32(usageItemsData, base + 2)),
          conjugationId: UInt32(u32(usageItemsData, base + 3)),
          meaningIndex: UInt32(u32(usageItemsData, base + 4))))
    }

    // TODO(taku): To reduce memory footprint, better to replace it with
    // binary search over the conjugation_suffix_data directly.
    for (t, token) in usageItems.enumerated() {
      let key = stringArray.utf8(at: Int(token.keyIndex))
      let value = stringArray.utf8(at: Int(token.valueIndex))
      let conjugationId = Int(token.conjugationId)
      let begin = u32(conjugationSuffixDataIndex, conjugationId)
      let end = u32(conjugationSuffixDataIndex, conjugationId + 1)
      var i = begin
      while i < end {
        let keySuffix = stringArray.utf8(at: u32(conjugationSuffix, 2 * i + 1))
        let valueSuffix = stringArray.utf8(at: u32(conjugationSuffix, 2 * i))
        let keyValue1 = StrPair(first: key + keySuffix, second: value + valueSuffix)
        keyValueUsageitemMap[keyValue1] = t

        let keyValue2 = StrPair(first: [], second: keyValue1.second)
        keyValueUsageitemMap[keyValue2] = t
        i += 1
      }
    }
  }

  /// `make_unique_from_tuples<UsageRewriter>(GetUsageRewriterData(),
  /// dictionary, pos_matcher)`.
  public convenience init(
    _ data: (
      baseConjugationSuffix: DataView, conjugationSuffix: DataView, conjugationIndex: DataView,
      usageItems: DataView, stringArray: DataView
    ),
    _ dictionary: any DictionaryInterface, _ posMatcher: PosMatcher
  ) {
    self.init(
      data.baseConjugationSuffix, data.conjugationSuffix, data.conjugationIndex, data.usageItems,
      data.stringArray, dictionary, posMatcher)
  }

  // better to show usage when user type "tab" key.
  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType {
    [.conversion, .prediction]
  }

  // "合いました" => "合い"
  static func getKanjiPrefixAndOneHiragana(_ word: some StringProtocol) -> String {
    // TODO(hidehiko): Refactor more based on ConstChar32Iterator.
    var result = ""
    var pos = 0
    var hasKanji = false
    var hasHiragana = false
    for scalar in word.unicodeScalars {
      let codepoint = scalar.value
      let s = Util.getScriptType(codepoint)
      if pos == 0 && s != .kanji {
        return ""
      } else if pos >= 0 && pos <= 1 && s == .kanji {
        // length of kanji <= 2.
        hasKanji = true
        pos += 1
        Util.codepointToUtf8Append(codepoint, &result)
        continue
      } else if pos > 0 && s == .hiragana {
        hasHiragana = true
        Util.codepointToUtf8Append(codepoint, &result)
        break
      } else {
        return ""
      }
    }

    if hasHiragana && hasKanji {
      return result
    }

    return ""
  }

  private func lookupUnmatchedUsageHeuristically(_ candidate: Candidate) -> UsageDictItem? {
    // We check Unknown POS ("名詞,サ変接続") as well, since
    // target verbs/adjectives may be in web dictionary.
    if !posMatcher.isContentWordWithConjugation(candidate.lid)
      && !posMatcher.isUnknown(candidate.lid)
    {
      return nil
    }

    let value = UsageRewriter.getKanjiPrefixAndOneHiragana(candidate.contentValue)
    if value.isEmpty {
      return nil
    }

    // key is empty;
    let keyValue = StrPair(first: [], second: Array(value.utf8))
    guard let index = keyValueUsageitemMap[keyValue] else {
      return nil
    }
    let item = usageItems[index]
    // Check result key part is a prefix of the content_key.
    let key = stringArray.data(at: Int(item.keyIndex))
    if candidate.contentKey.utf8.starts(with: key) {
      return item
    }

    return nil
  }

  private func lookupUsage(_ candidate: Candidate) -> UsageDictItem? {
    let keyValue = StrPair(
      first: Array(candidate.contentKey.utf8), second: Array(candidate.contentValue.utf8))
    if let index = keyValueUsageitemMap[keyValue] {
      return usageItems[index]
    }
    return lookupUnmatchedUsageHeuristically(candidate)
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    // MOZC_VLOG(2) << segments->DebugString();

    let config = request.config()
    // Default value of use_local_usage_dictionary() is true.
    // So if information_list_config() is not available in the config,
    // we don't need to return false here.
    if config.hasInformationListConfig
      && !config.informationListConfig.useLocalUsageDictionary
    {
      return false
    }

    var modified = false
    // UsageIDs for embedded usage dictionary are generated in advance by
    // gen_usage_rewriter_dictionary_main.cc (which are just sequential
    // numbers). However, since user dictionary comments don't have such IDs,
    // dynamically generate them so that they don't conflict with those of the
    // embedded usage dictionary.  Since just the uniqueness in one Segments is
    // sufficient, for usage from the user dictionary, we simply assign
    // sequential numbers larger than the maximum ID of the embedded usage
    // dictionary.
    var usageIdForUserComment = Int32(truncatingIfNeeded: keyValueUsageitemMap.count)
    for i in 0..<segments.conversionSegmentsSize {
      let segment = segments.mutableConversionSegment(i)
      for j in 0..<segment.candidatesSize {
        usageIdForUserComment &+= 1

        // First, search the user dictionary for comment.
        if let comment = dictionary.lookupComment(
          segment.candidate(j).contentKey, segment.candidate(j).contentValue,
          options: request.options())
        {
          let candidate = segment.mutableCandidate(j)
          candidate.usageId = usageIdForUserComment
          candidate.usageTitle = segment.candidate(j).contentValue
          candidate.usageDescription = comment
          modified = true
          continue
        }

        // If comment isn't in the user dictionary, search the system usage
        // dictionary.
        if let token = lookupUsage(segment.candidate(j)) {
          let candidate = segment.mutableCandidate(j)
          candidate.usageId = Int32(bitPattern: token.usageId)

          let valueSuffix = stringArray[
            Int(
              baseConjugationSuffix.load(
                fromByteOffset: 2 * Int(token.conjugationId) * 4, as: UInt32.self))]
          candidate.usageTitle = stringArray[Int(token.valueIndex)] + valueSuffix

          candidate.usageDescription = stringArray[Int(token.meaningIndex)]

          modified = true
        }
      }
    }
    return modified
  }
}
