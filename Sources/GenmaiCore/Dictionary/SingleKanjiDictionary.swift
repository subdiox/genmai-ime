// Port of mozc/src/dictionary/single_kanji_dictionary.{h,cc} (3.35.6354).

import GenmaiBase

/// `mozc::dictionary::SingleKanjiDictionary`.
///
/// Data: `DataManager.getSingleKanjiRewriterData()`. The C++ virtual methods
/// are the requirements of `SingleKanjiDictionaryInterface`, which tests mock.
public final class SingleKanjiDictionary: SingleKanjiDictionaryInterface {
  private let singleKanjiTokenArray: DataView
  private let singleKanjiStringArray: SerializedStringArray
  private let variantTypeArray: SerializedStringArray
  private let variantTokenArray: DataView
  private let variantStringArray: SerializedStringArray

  // Since nounPrefixDictionary is just a tentative workaround,
  // we copy the SingleKanji structure so that we can remove this workaround
  // easily. Also, the logic of NounPrefix insertion is put independently from
  // the single kanji dictionary. Ideally, we want to regenerate our
  // language model for fixing noun-prefix issue.
  private let nounPrefixDictionary: SerializedDictionary?

  public init() {
    singleKanjiTokenArray = DataView()
    singleKanjiStringArray = SerializedStringArray()
    variantTypeArray = SerializedStringArray()
    variantTokenArray = DataView()
    variantStringArray = SerializedStringArray()
    nounPrefixDictionary = nil
  }

  public init(
    _ tokenArrayData: DataView, _ stringArrayData: DataView, _ variantTypeArrayData: DataView,
    _ variantTokenArrayData: DataView, _ variantStringArrayData: DataView,
    _ nounPrefixTokenArrayData: DataView, _ nounPrefixStringArrayData: DataView
  ) {
    singleKanjiTokenArray = tokenArrayData
    variantTokenArray = variantTokenArrayData
    // Single Kanji token array is an array of uint32_t.  Its size must be
    // multiple of 2; see the comment above lookupKanjiEntries.
    assert(singleKanjiTokenArray.count % (2 * 4) == 0)
    var singleKanjiStringArray = SerializedStringArray()
    singleKanjiStringArray.set(stringArrayData)
    self.singleKanjiStringArray = singleKanjiStringArray
    var variantTypeArray = SerializedStringArray()
    variantTypeArray.set(variantTypeArrayData)
    self.variantTypeArray = variantTypeArray
    // Variant token array is an array of uint32_t.  Its size must be multiple
    // of 3; see the comment above generateDescription.
    assert(variantTokenArray.count % (3 * 4) == 0)
    var variantStringArray = SerializedStringArray()
    variantStringArray.set(variantStringArrayData)
    self.variantStringArray = variantStringArray
    nounPrefixDictionary = SerializedDictionary(
      tokenArray: nounPrefixTokenArrayData, stringArrayData: nounPrefixStringArrayData)
  }

  /// Convenience initializer from `DataManager.getSingleKanjiRewriterData()`.
  public convenience init(
    _ data: (
      tokenArray: DataView, stringArray: DataView, variantTypeArray: DataView,
      variantTokenArray: DataView, variantStringArray: DataView,
      nounPrefixTokenArray: DataView, nounPrefixStringArray: DataView
    )
  ) {
    self.init(
      data.tokenArray, data.stringArray, data.variantTypeArray, data.variantTokenArray,
      data.variantStringArray, data.nounPrefixTokenArray, data.nounPrefixStringArray)
  }

  // The underlying token array, singleKanjiTokenArray, has the following
  // format:
  //
  // +------------------+
  // | index of key 0   |
  // +------------------+
  // | index of value 0 |
  // +------------------+
  // | index of key 1   |
  // +------------------+
  // | index of value 1 |
  // +------------------+
  // | ...              |
  //
  // Here, each element is of uint32_t type.  Each of actual string values are
  // stored in singleKanjiStringArray at its index.

  /// Looks up single kanji list from key (reading).  Returns empty list if not
  /// found.
  public func lookupKanjiEntries(_ key: String, _ useSvs: Bool) -> [String] {
    let tokenSize = 8
    let n = singleKanjiTokenArray.count / tokenSize
    let keyBytes = Array(key.utf8)
    func keyIndex(_ i: Int) -> Int {
      Int(singleKanjiTokenArray.load(fromByteOffset: i * tokenSize, as: UInt32.self))
    }
    // std::lower_bound.
    var lo = 0
    var count = n
    while count > 0 {
      let half = count / 2
      if singleKanjiStringArray.compare(at: keyIndex(lo + half), bytes: keyBytes) < 0 {
        lo += half + 1
        count -= half + 1
      } else {
        count = half
      }
    }
    if lo == n || !singleKanjiStringArray.equals(at: keyIndex(lo), bytes: keyBytes) {
      return []
    }
    let valueIndex = Int(
      singleKanjiTokenArray.load(fromByteOffset: lo * tokenSize + 4, as: UInt32.self))
    let values = singleKanjiStringArray[valueIndex]
    if useSvs {
      var svsValues = ""
      if TextNormalizer.normalizeTextToSvs(values, &svsValues) {
        return Util.splitStringToUtf8Graphemes(svsValues)
      }
    }
    return Util.splitStringToUtf8Graphemes(values)
  }

  /// Returns the range for noun prefix kanji entries whose keys match the
  /// given key.
  /// Noun prefix kanji entries are generated by
  /// mozc/rewriter/gen_single_kanji_noun_prefix_data.cc
  public func lookupNounPrefixEntries(_ key: String) -> Slice<SerializedDictionary> {
    guard let dic = nounPrefixDictionary else {
      return SerializedDictionary(tokenArray: DataView(), stringArrayData: DataView())[0..<0]
    }
    return dic[dic.equalRange(key)]
  }

  // The underlying token array, variantTokenArray, has the following
  // format:
  //
  // +-------------------------+
  // | index of target 0       |
  // +-------------------------+
  // | index of original 0     |
  // +-------------------------+
  // | index of variant type 0 |
  // +-------------------------+
  // | index of target 1       |
  // +-------------------------+
  // | ...                     |
  //
  // Here, each element is of uint32_t type.  Actual strings of target and
  // original are stored in variantStringArray, while strings of variant type
  // are stored in variantTypeArray.

  /// Generates kanji variant description.
  /// Returns nil if the description was not found.
  public func generateDescription(_ kanjiSurface: String) -> String? {
    let tokenSize = 12
    let n = variantTokenArray.count / tokenSize
    let surfaceBytes = Array(kanjiSurface.utf8)
    func field(_ i: Int, _ f: Int) -> Int {
      Int(variantTokenArray.load(fromByteOffset: i * tokenSize + f * 4, as: UInt32.self))
    }
    // std::lower_bound.
    var lo = 0
    var count = n
    while count > 0 {
      let half = count / 2
      if variantStringArray.compare(at: field(lo + half, 0), bytes: surfaceBytes) < 0 {
        lo += half + 1
        count -= half + 1
      } else {
        count = half
      }
    }
    if lo == n || !variantStringArray.equals(at: field(lo, 0), bytes: surfaceBytes) {
      return nil
    }
    let original = variantStringArray[field(lo, 1)]
    let typeId = field(lo, 2)
    assert(typeId < variantTypeArray.count)
    // Format like "XXXのYYY"
    return original + "の" + variantTypeArray[typeId]
  }
}

/// The virtual methods of the C++ `SingleKanjiDictionary` (a protocol so that
/// tests can mock them).
public protocol SingleKanjiDictionaryInterface: Sendable {
  /// Looks up single kanji list from key (reading).  Returns empty list if not
  /// found.
  func lookupKanjiEntries(_ key: String, _ useSvs: Bool) -> [String]

  /// Returns the range for noun prefix kanji entries whose keys match the
  /// given key.
  func lookupNounPrefixEntries(_ key: String) -> Slice<SerializedDictionary>

  /// Generates kanji variant description.
  /// Returns nil if the description was not found.
  func generateDescription(_ kanjiSurface: String) -> String?
}
