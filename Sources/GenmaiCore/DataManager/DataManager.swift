// Port of mozc/src/data_manager/data_manager.{h,cc} (3.35.6354).
//
// Sections are returned as zero-copy `DataView` / `DataSpan` views that keep
// the backing memory (the memory-mapped data set file) alive. The C++
// `std::array<absl::string_view, N>` / `std::tuple` results become labeled
// tuples. `absl::Status` errors are thrown as `StatusError`.

import GenmaiBase
import GenmaiProtocol
import SwiftProtobuf
import Synchronization

private let kDataSetMagicNumber: [UInt8] = [0xEF, 0x4D, 0x4F, 0x5A, 0x43, 0x0D, 0x0A]  // "\xEFMOZC\r\n"
private let kDataSetMagicNumberOss: [UInt8] = [0xEF, 0x4D, 0x4F, 0x5A, 0x43, 0x0D, 0x0A]  // "\xEFMOZC\r\n"

private func initUserPosManagerDataFromReader(_ reader: DataSetReader) throws -> (
  posMatcher: DataView, userPosToken: DataView, userPosString: DataView
) {
  guard let posMatcherData = reader.get("pos_matcher") else {
    throw StatusError.notFound("Cannot find POS matcher rule ID table")
  }
  guard let userPosTokenArrayData = reader.get("user_pos_token") else {
    throw StatusError.notFound("Cannot find a user POS token array")
  }
  guard let userPosStringArrayData = reader.get("user_pos_string") else {
    throw StatusError.notFound("Cannot find a user POS string array")
  }
  if userPosTokenArrayData.count % 8 != 0
    || !SerializedStringArray.verifyData(userPosStringArrayData)
  {
    throw StatusError.dataLoss(
      "User POS data is broken: token array data size = \(userPosTokenArrayData.count), string array size = \(userPosStringArrayData.count)"
    )
  }
  return (posMatcherData, userPosTokenArrayData, userPosStringArrayData)
}

/// This data manager parses a data set file image and extracts each data
/// (dictionary, LM, etc.).
///
/// Thread safety: the sections are guarded by a mutex; they are set during
/// initialization (the `initFrom*` methods, protected in C++, are called while
/// constructing an instance) and the memory is a read-only mmap or an
/// immutable owned buffer. The C++ subclasses (OssDataManager,
/// MockDataManager) are factories here (see those files).
public final class DataManager: Sendable {
  public static func getDataSetMagicNumber(_ type: String) -> [UInt8] {
    if type == "oss" {
      return kDataSetMagicNumberOss
    }
    return kDataSetMagicNumber
  }

  // MARK: - Factories

  /// Creates an instance of DataManager from a data set file or throws on
  /// failure.
  public static func createFromFile(_ path: String) throws -> DataManager {
    try createFromFile(path, magic: kDataSetMagicNumber)
  }

  public static func createFromFile(_ path: String, magic: [UInt8]) throws -> DataManager {
    let dataManager = DataManager()
    do {
      try dataManager.initFromFile(path, magic: magic)
    } catch {
      GenmaiLog.error("\(error)")
      throw error
    }
    return dataManager
  }

  public static func createFromArray(_ array: DataView) throws -> DataManager {
    try createFromArray(array, magic: kDataSetMagicNumber)
  }

  public static func createFromArray(_ array: DataView, magic: [UInt8]) throws -> DataManager {
    let dataManager = DataManager()
    do {
      try dataManager.initFromArray(array, magic: magic)
    } catch {
      GenmaiLog.error("\(error)")
      throw error
    }
    return dataManager
  }

  public static func createFromArray(_ array: DataView, magicLength: Int) throws -> DataManager {
    let dataManager = DataManager()
    do {
      try dataManager.initFromArray(array, magicLength: magicLength)
    } catch {
      GenmaiLog.error("\(error)")
      throw error
    }
    return dataManager
  }

  public static func createUserPosManagerDataFromArray(_ array: DataView, magic: [UInt8]) throws
    -> DataManager
  {
    let dataManager = DataManager()
    do {
      try dataManager.initUserPosManagerDataFromArray(array, magic: magic)
    } catch {
      GenmaiLog.error("\(error)")
      throw error
    }
    return dataManager
  }

  public static func createUserPosManagerDataFromFile(_ path: String, magic: [UInt8]) throws
    -> DataManager
  {
    let dataManager = DataManager()
    do {
      try dataManager.initUserPosManagerDataFromFile(path, magic: magic)
    } catch {
      GenmaiLog.error("\(error)")
      throw error
    }
    return dataManager
  }

  // MARK: - State

  /// The sections of the data set (set by the `initFrom*` methods).
  private struct Sections: Sendable {

    var filename: String? = nil
    var mmap: Mmap? = nil
    var posMatcherData = DataView.empty
    var posIdMapData = DataView.empty
    var userPosTokenArrayData = DataView.empty
    var userPosStringArrayData = DataView.empty
    var connectionData = DataView.empty
    var dictionaryData = DataView.empty
    var suggestionFilterData = DataView.empty
    var collocationData = DataView.empty
    var collocationSuppressionData = DataView.empty
    var posGroupData = DataView.empty
    var boundaryData = DataView.empty
    var segmenterCompressedLSize = 0
    var segmenterCompressedRSize = 0
    var segmenterLTable = DataView.empty
    var segmenterRTable = DataView.empty
    var segmenterBitarray = DataView.empty
    var counterSuffixData = DataView.empty
    var suffixKeyArrayData = DataView.empty
    var suffixValueArrayData = DataView.empty
    var suffixTokenArrayData = DataView.empty
    var readingCorrectionValueArrayData = DataView.empty
    var readingCorrectionErrorArrayData = DataView.empty
    var readingCorrectionCorrectionArrayData = DataView.empty
    var symbolTokenArrayData = DataView.empty
    var symbolStringArrayData = DataView.empty
    var emoticonTokenArrayData = DataView.empty
    var emoticonStringArrayData = DataView.empty
    var emojiTokenArrayData = DataView.empty
    var emojiStringArrayData = DataView.empty
    var singleKanjiTokenArrayData = DataView.empty
    var singleKanjiStringArrayData = DataView.empty
    var singleKanjiVariantTypeData = DataView.empty
    var singleKanjiVariantTokenArrayData = DataView.empty
    var singleKanjiVariantStringArrayData = DataView.empty
    var singleKanjiNounPrefixTokenArrayData = DataView.empty
    var singleKanjiNounPrefixStringArrayData = DataView.empty
    var a11yDescriptionTokenArrayData = DataView.empty
    var a11yDescriptionStringArrayData = DataView.empty
    var zeroQueryTokenArrayData = DataView.empty
    var zeroQueryStringArrayData = DataView.empty
    var zeroQueryNumberTokenArrayData = DataView.empty
    var zeroQueryNumberStringArrayData = DataView.empty
    var usageBaseConjugationSuffixData = DataView.empty
    var usageConjugationSuffixData = DataView.empty
    var usageConjugationIndexData = DataView.empty
    var usageItemsData = DataView.empty
    var usageStringArrayData = DataView.empty
    var dataVersion = DataView.empty
    /// Replaces the data version (MockDataManager's mocked GetDataVersion()).
    var dataVersionOverride: String? = nil
    // Note: as in the C++ code (3.35.6354), this map is never populated, so
    // getOffsetAndSize() always returns nil.
    var offsetAndSize: [String: (Int, Int)] = [:]
  }

  private let state = Mutex(Sections())

  /// A snapshot of the sections (the getters are not on hot paths).
  private var sections: Sections { state.withLock { $0 } }

  /// An uninitialized data manager (C++ protected default constructor).
  /// Call one of the `initFrom*` methods next.
  public init() {}

  // MARK: - Initialization (protected in C++)

  /// Parses |array| and extracts byte blocks of data set.  The second version
  /// specifies a custom magic number to expect (e.g., mock data set has a
  /// different magic number).  The third version specifies the length of the
  /// magic number in bytes.
  public func initFromArray(_ array: DataView) throws {
    try initFromArray(array, magic: kDataSetMagicNumber)
  }

  public func initFromArray(_ array: DataView, magic: [UInt8]) throws {
    var reader = DataSetReader()
    if !reader.initialize(array, magic: magic) {
      throw StatusError.dataLoss("Binary data of size \(array.count) is broken")
    }
    try initFromReader(reader)
  }

  public func initFromArray(_ array: DataView, magicLength: Int) throws {
    var reader = DataSetReader()
    if !reader.initialize(array, magicLength: magicLength) {
      throw StatusError.dataLoss("Binary data of size \(array.count) is broken")
    }
    try initFromReader(reader)
  }

  /// The same as above initFromArray() but the data is loaded using mmap,
  /// which is owned in this instance.
  public func initFromFile(_ path: String) throws {
    try initFromFile(path, magic: kDataSetMagicNumber)
  }

  public func initFromFile(_ path: String, magic: [UInt8]) throws {
    let data = try mapFile(path)
    state.withLock { $0.filename = path }
    try initFromArray(data, magic: magic)
  }

  /// Swift addition: initFromFile() that checks only the length of the magic
  /// number, used by OssDataManager / MockDataManager, which in C++ call
  /// `InitFromArray(embedded_data, kMagicNumberLength)` on embedded data.
  public func initFromFile(_ path: String, magicLength: Int) throws {
    let data = try mapFile(path)
    state.withLock { $0.filename = path }
    try initFromArray(data, magicLength: magicLength)
  }

  /// The same as above initFromArray() but only parses data set for user pos
  /// manager.  For mozc runtime modules, use initFromArray() because this
  /// method is only for build tools, e.g., rewriter/dictionary_generator.cc
  /// (some build tools depend on user pos data to create outputs, so we need
  /// to handle partial data set).
  public func initUserPosManagerDataFromArray(_ array: DataView, magic: [UInt8]) throws {
    var reader = DataSetReader()
    if !reader.initialize(array, magic: magic) {
      throw StatusError.dataLoss("Binary data of size \(array.count) is broken")
    }
    let userPosManagerData = try initUserPosManagerDataFromReader(reader)
    state.withLock { s in
      (s.posMatcherData, s.userPosTokenArrayData, s.userPosStringArrayData) = userPosManagerData
    }
  }

  public func initUserPosManagerDataFromFile(_ path: String, magic: [UInt8]) throws {
    let data = try mapFile(path)
    try initUserPosManagerDataFromArray(data, magic: magic)
  }

  private func mapFile(_ path: String) throws -> DataView {
    let mapped: Mmap
    do {
      mapped = try Mmap.map(path, .readOnly)
    } catch {
      throw StatusError.permissionDenied("Mmap failed \(error)")
    }
    state.withLock { $0.mmap = mapped }
    return DataView(mapped)
  }

  private func initFromReader(_ reader: DataSetReader) throws {
    var s = state.withLock { $0 }
    try Self.readSections(reader, &s)
    state.withLock { [s] in $0 = s }
  }

  /// Reads the sections from `reader` into `s` (C++ `InitFromReader`).
  private static func readSections(_ reader: DataSetReader, _ s: inout Sections) throws {
    (s.posMatcherData, s.userPosTokenArrayData, s.userPosStringArrayData) =
      try initUserPosManagerDataFromReader(reader)

    if let data = reader.get("pos_id_map") {
      s.posIdMapData = data
    } else {
      // pos_id_map is not provided
      s.posIdMapData = .empty
    }
    guard let conn = reader.get("conn") else {
      throw StatusError.notFound("Cannot find a connection data")
    }
    s.connectionData = conn
    guard let dict = reader.get("dict") else {
      throw StatusError.notFound("Cannot find a dictionary data")
    }
    s.dictionaryData = dict
    guard let sugg = reader.get("sugg") else {
      throw StatusError.notFound("Cannot find a suggestion filter data")
    }
    s.suggestionFilterData = sugg
    guard let coll = reader.get("coll") else {
      throw StatusError.notFound("Cannot find a collocation data")
    }
    s.collocationData = coll
    guard let cols = reader.get("cols") else {
      throw StatusError.notFound("Cannot find a collocation suprression data")
    }
    s.collocationSuppressionData = cols
    guard let posg = reader.get("posg") else {
      throw StatusError.notFound("Cannot find a POS group data")
    }
    s.posGroupData = posg
    guard let bdry = reader.get("bdry") else {
      throw StatusError.notFound("Cannot find a boundary data")
    }
    s.boundaryData = bdry
    do {
      guard let memblock = reader.get("segmenter_sizeinfo") else {
        throw StatusError.notFound("Cannot find a segmenter size info")
      }
      let sizeinfo: Genmai_Converter_SegmenterDataSizeInfo
      do {
        sizeinfo = try Genmai_Converter_SegmenterDataSizeInfo(serializedBytes: memblock.array)
      } catch {
        throw StatusError.dataLoss("Failed to parse SegmenterDataSizeInfo")
      }
      s.segmenterCompressedLSize = Int(sizeinfo.compressedLsize)
      s.segmenterCompressedRSize = Int(sizeinfo.compressedRsize)
    }
    guard let ltable = reader.get("segmenter_ltable") else {
      throw StatusError.notFound("Cannot find a segmenter ltable")
    }
    s.segmenterLTable = ltable
    guard let rtable = reader.get("segmenter_rtable") else {
      throw StatusError.notFound("Cannot find a segmenter rtable")
    }
    s.segmenterRTable = rtable
    guard let bitarray = reader.get("segmenter_bitarray") else {
      throw StatusError.notFound("Cannot find a segmenter bit-array")
    }
    s.segmenterBitarray = bitarray
    guard let counterSuffix = reader.get("counter_suffix") else {
      throw StatusError.notFound("Cannot find a counter suffix data")
    }
    s.counterSuffixData = counterSuffix
    if !SerializedStringArray.verifyData(s.counterSuffixData) {
      throw StatusError.notFound("Counter suffix string array is broken")
    }
    guard let suffixKey = reader.get("suffix_key") else {
      throw StatusError.notFound("Cannot find a suffix key array")
    }
    s.suffixKeyArrayData = suffixKey
    guard let suffixValue = reader.get("suffix_value") else {
      throw StatusError.notFound("Cannot find a suffix value array")
    }
    s.suffixValueArrayData = suffixValue
    guard let suffixToken = reader.get("suffix_token") else {
      throw StatusError.notFound("Cannot find a suffix token array")
    }
    s.suffixTokenArrayData = suffixToken
    do {
      var suffixKeys = SerializedStringArray()
      var suffixValues = SerializedStringArray()
      if !suffixKeys.initialize(s.suffixKeyArrayData) || !suffixValues.initialize(s.suffixValueArrayData)
        || suffixKeys.size != suffixValues.size
        // Suffix token array is an array of triple (lid, rid, cost) of
        // uint32_t, so it contains N = 3 * |suffix_keys.size()| uint32_t
        // elements. Therefore, its byte length must be 4 * N bytes.
        || s.suffixTokenArrayData.count != 4 * 3 * suffixKeys.size
      {
        throw StatusError.dataLoss("Suffix dictionary data is broken")
      }
    }
    guard let rcValue = reader.get("reading_correction_value") else {
      throw StatusError.notFound("Cannot find reading correction value array")
    }
    s.readingCorrectionValueArrayData = rcValue
    guard let rcError = reader.get("reading_correction_error") else {
      throw StatusError.notFound("Cannot find reading correction error array")
    }
    s.readingCorrectionErrorArrayData = rcError
    guard let rcCorrection = reader.get("reading_correction_correction") else {
      throw StatusError.notFound("Cannot find reading correction correction array")
    }
    s.readingCorrectionCorrectionArrayData = rcCorrection
    do {
      var valueArray = SerializedStringArray()
      var errorArray = SerializedStringArray()
      var correctionArray = SerializedStringArray()
      if !valueArray.initialize(s.readingCorrectionValueArrayData)
        || !errorArray.initialize(s.readingCorrectionErrorArrayData)
        || !correctionArray.initialize(s.readingCorrectionCorrectionArrayData)
        || valueArray.size != errorArray.size || valueArray.size != correctionArray.size
      {
        throw StatusError.dataLoss("Reading correction data is broken")
      }
    }
    guard let symbolToken = reader.get("symbol_token") else {
      throw StatusError.notFound("Cannot find a symbol token array")
    }
    s.symbolTokenArrayData = symbolToken
    guard let symbolString = reader.get("symbol_string") else {
      throw StatusError.notFound("Cannot find a symbol string array or data is broken")
    }
    s.symbolStringArrayData = symbolString
    if !SerializedDictionary.verifyData(s.symbolTokenArrayData, s.symbolStringArrayData) {
      throw StatusError.dataLoss("Symbol dictionary data is broken")
    }
    guard let emoticonToken = reader.get("emoticon_token") else {
      throw StatusError.notFound("Cannot find an emoticon token array")
    }
    s.emoticonTokenArrayData = emoticonToken
    guard let emoticonString = reader.get("emoticon_string") else {
      throw StatusError.notFound("Cannot find an emoticon string array or data is broken")
    }
    s.emoticonStringArrayData = emoticonString
    if !SerializedDictionary.verifyData(s.emoticonTokenArrayData, s.emoticonStringArrayData) {
      throw StatusError.dataLoss("Emoticon dictionary data is broken")
    }
    guard let emojiToken = reader.get("emoji_token") else {
      throw StatusError.notFound("Cannot find an emoji token array")
    }
    s.emojiTokenArrayData = emojiToken
    guard let emojiString = reader.get("emoji_string") else {
      throw StatusError.notFound("Cannot find an emoji string array or data is broken")
    }
    s.emojiStringArrayData = emojiString
    if !SerializedStringArray.verifyData(s.emojiStringArrayData) {
      throw StatusError.dataLoss("Emoji rewriter string array data is broken")
    }
    guard let skToken = reader.get("single_kanji_token"),
      let skString = reader.get("single_kanji_string"),
      let skVariantType = reader.get("single_kanji_variant_type"),
      let skVariantToken = reader.get("single_kanji_variant_token"),
      let skVariantString = reader.get("single_kanji_variant_string"),
      let skNounPrefixToken = reader.get("single_kanji_noun_prefix_token"),
      let skNounPrefixString = reader.get("single_kanji_noun_prefix_string")
    else {
      throw StatusError.notFound("Cannot find single Kanji rewriter data")
    }
    s.singleKanjiTokenArrayData = skToken
    s.singleKanjiStringArrayData = skString
    s.singleKanjiVariantTypeData = skVariantType
    s.singleKanjiVariantTokenArrayData = skVariantToken
    s.singleKanjiVariantStringArrayData = skVariantString
    s.singleKanjiNounPrefixTokenArrayData = skNounPrefixToken
    s.singleKanjiNounPrefixStringArrayData = skNounPrefixString
    if !SerializedStringArray.verifyData(s.singleKanjiStringArrayData)
      || !SerializedStringArray.verifyData(s.singleKanjiVariantTypeData)
      || !SerializedStringArray.verifyData(s.singleKanjiVariantStringArrayData)
      || !SerializedDictionary.verifyData(
        s.singleKanjiNounPrefixTokenArrayData, s.singleKanjiNounPrefixStringArrayData)
    {
      throw StatusError.dataLoss("Single Kanji data is broken")
    }
    if let data = reader.get("a11y_description_token") {
      s.a11yDescriptionTokenArrayData = data
    } else {
      // A11y description dictionary's token array is not provided.
      // A11y description dictionary is optional, so don't fail here.
      s.a11yDescriptionTokenArrayData = .empty
    }
    if let data = reader.get("a11y_description_string") {
      s.a11yDescriptionStringArrayData = data
    } else {
      // A11y description dictionary's string array is not provided.
      // A11y description dictionary is optional, so don't fail here.
      s.a11yDescriptionStringArrayData = .empty
    }
    if !(s.a11yDescriptionTokenArrayData.isEmpty && s.a11yDescriptionStringArrayData.isEmpty)
      && !SerializedDictionary.verifyData(
        s.a11yDescriptionTokenArrayData, s.a11yDescriptionStringArrayData)
    {
      throw StatusError.dataLoss("A11y description dictionary data is broken")
    }
    guard let zqToken = reader.get("zero_query_token_array"),
      let zqString = reader.get("zero_query_string_array"),
      let zqNumberToken = reader.get("zero_query_number_token_array"),
      let zqNumberString = reader.get("zero_query_number_string_array")
    else {
      throw StatusError.notFound("Cannot find zero query data")
    }
    s.zeroQueryTokenArrayData = zqToken
    s.zeroQueryStringArrayData = zqString
    s.zeroQueryNumberTokenArrayData = zqNumberToken
    s.zeroQueryNumberStringArrayData = zqNumberString
    if !SerializedStringArray.verifyData(s.zeroQueryStringArrayData)
      || !SerializedStringArray.verifyData(s.zeroQueryNumberStringArrayData)
    {
      throw StatusError.dataLoss("Zero query data is broken")
    }

    if let items = reader.get("usage_item_array") {
      s.usageItemsData = items
      guard let baseConjugationSuffix = reader.get("usage_base_conjugation_suffix"),
        let conjugationSuffix = reader.get("usage_conjugation_suffix"),
        let conjugationIndex = reader.get("usage_conjugation_index"),
        let stringArray = reader.get("usage_string_array")
      else {
        throw StatusError.notFound("Cannot find some usage dictionary data components")
      }
      s.usageBaseConjugationSuffixData = baseConjugationSuffix
      s.usageConjugationSuffixData = conjugationSuffix
      s.usageConjugationIndexData = conjugationIndex
      s.usageStringArrayData = stringArray
      if !SerializedStringArray.verifyData(s.usageStringArrayData) {
        throw StatusError.dataLoss("Usage dictionary's string array is broken")
      }
    } else {
      // Usage dictionary is not provided.
      // Usage dictionary is optional, so don't fail here.
    }

    guard let version = reader.get("version") else {
      throw StatusError.notFound("Cannot find data version")
    }
    s.dataVersion = version
    do {
      let versionString = s.dataVersion.string
      // absl::StrSplit(data_version_, '.', absl::SkipEmpty())
      let components = versionString.utf8.split(
        separator: UInt8(ascii: "."), omittingEmptySubsequences: true
      ).map { String(decoding: $0, as: UTF8.self) }
      if components.count != 3 {
        throw StatusError.dataLoss("Invalid version format: \(versionString)")
      }
      if components[0] != Version.getGenmaiEngineVersion() {
        throw StatusError.failedPrecondition(
          "Incompatible data. The required engine version is \(Version.getGenmaiEngineVersion()) but tried to load \(components[0]) (\(versionString))"
        )
      }
    }
  }

  // MARK: - Accessors

  public func getFilename() -> String? { sections.filename }

  public func getPosMatcherData() -> DataSpan<UInt16> {
    sections.posMatcherData.span(UInt16.self)
  }

  public func getPosIdMapData() -> DataView { sections.posIdMapData }

  public func getUserPosData() -> (tokenArray: DataView, stringArray: DataView) {
    (sections.userPosTokenArrayData, sections.userPosStringArrayData)
  }

  public func getConnectorData() -> DataView { sections.connectionData }

  public func getSystemDictionaryData() -> DataView { sections.dictionaryData }

  public func getSuggestionFilterData() -> DataSpan<UInt32> {
    sections.suggestionFilterData.span(UInt32.self)
  }

  public func getCollocationData() -> (collocation: DataView, collocationSuppression: DataView) {
    (sections.collocationData, sections.collocationSuppressionData)
  }

  public func getPosGroupData() -> DataSpan<UInt8> {
    sections.posGroupData.span(UInt8.self)
  }

  public func getSegmenterData() -> (
    lNumElements: Int, rNumElements: Int, lTable: DataSpan<UInt16>, rTable: DataSpan<UInt16>,
    bitarrayData: DataSpan<UInt8>, boundaryData: DataSpan<UInt16>
  ) {
    (
      sections.segmenterCompressedLSize,
      sections.segmenterCompressedRSize,
      sections.segmenterLTable.span(UInt16.self),
      sections.segmenterRTable.span(UInt16.self),
      sections.segmenterBitarray.span(UInt8.self),
      sections.boundaryData.span(UInt16.self)
    )
  }

  public func getCounterSuffixSortedArray() -> DataView { sections.counterSuffixData }

  public func getSuffixDictionaryData() -> (
    keyArray: DataView, valueArray: DataView, tokenArray: DataView
  ) {
    (sections.suffixKeyArrayData, sections.suffixValueArrayData, sections.suffixTokenArrayData)
  }

  public func getReadingCorrectionData() -> (
    valueArray: DataView, errorArray: DataView, correctionArray: DataView
  ) {
    (
      sections.readingCorrectionValueArrayData, sections.readingCorrectionErrorArrayData,
      sections.readingCorrectionCorrectionArrayData
    )
  }

  public func getSymbolRewriterData() -> (tokenArray: DataView, stringArray: DataView) {
    (sections.symbolTokenArrayData, sections.symbolStringArrayData)
  }

  public func getEmoticonRewriterData() -> (tokenArray: DataView, stringArray: DataView) {
    (sections.emoticonTokenArrayData, sections.emoticonStringArrayData)
  }

  public func getEmojiRewriterData() -> (tokenArray: DataView, stringArray: DataView) {
    (sections.emojiTokenArrayData, sections.emojiStringArrayData)
  }

  public func getSingleKanjiRewriterData() -> (
    tokenArray: DataView, stringArray: DataView, variantTypeArray: DataView,
    variantTokenArray: DataView, variantStringArray: DataView,
    nounPrefixTokenArray: DataView, nounPrefixStringArray: DataView
  ) {
    (
      sections.singleKanjiTokenArrayData,
      sections.singleKanjiStringArrayData,
      sections.singleKanjiVariantTypeData,
      sections.singleKanjiVariantTokenArrayData,
      sections.singleKanjiVariantStringArrayData,
      sections.singleKanjiNounPrefixTokenArrayData,
      sections.singleKanjiNounPrefixStringArrayData
    )
  }

  public func getA11yDescriptionRewriterData() -> (tokenArray: DataView, stringArray: DataView) {
    (sections.a11yDescriptionTokenArrayData, sections.a11yDescriptionStringArrayData)
  }

  public func getZeroQueryData() -> (
    tokenArray: DataView, stringArray: DataView, numberTokenArray: DataView,
    numberStringArray: DataView
  ) {
    (
      sections.zeroQueryTokenArrayData, sections.zeroQueryStringArrayData, sections.zeroQueryNumberTokenArrayData,
      sections.zeroQueryNumberStringArrayData
    )
  }

  public func getUsageRewriterData() -> (
    baseConjugationSuffix: DataView, conjugationSuffix: DataView, conjugationIndex: DataView,
    usageItems: DataView, stringArray: DataView
  ) {
    (
      sections.usageBaseConjugationSuffixData, sections.usageConjugationSuffixData, sections.usageConjugationIndexData,
      sections.usageItemsData, sections.usageStringArrayData
    )
  }

  /// The data version string, e.g. "24.11.oss".
  public func getDataVersion() -> String {
    let s = sections
    return s.dataVersionOverride ?? s.dataVersion.string
  }

  /// Makes `getDataVersion()` return `version` (MockDataManager).
  func overrideDataVersion(_ version: String?) {
    state.withLock { $0.dataVersionOverride = version }
  }

  public func getOffsetAndSize(_ name: String) -> (offset: Int, size: Int)? {
    if let v = sections.offsetAndSize[name] {
      return v
    }
    return nil
  }
}
