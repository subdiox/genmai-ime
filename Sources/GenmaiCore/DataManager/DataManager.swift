// Port of mozc/src/data_manager/data_manager.{h,cc} (3.35.6354).
//
// Sections are returned as zero-copy `DataView` / `DataSpan` views that keep
// the backing memory (the memory-mapped data set file) alive. The C++
// `std::array<absl::string_view, N>` / `std::tuple` results become labeled
// tuples. `absl::Status` errors are thrown as `StatusError`.

import GenmaiBase
import GenmaiProtocol
import SwiftProtobuf

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
/// Thread safety: all sections are set during initialization and never
/// mutated afterwards; the memory is a read-only mmap or an immutable owned
/// buffer. Hence `@unchecked Sendable`. The `initFrom*` methods (protected in
/// C++) must only be called while constructing an instance.
open class DataManager: @unchecked Sendable {
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

  private var filename: String? = nil
  private var mmap: Mmap? = nil
  private var posMatcherData = DataView.empty
  private var posIdMapData = DataView.empty
  private var userPosTokenArrayData = DataView.empty
  private var userPosStringArrayData = DataView.empty
  private var connectionData = DataView.empty
  private var dictionaryData = DataView.empty
  private var suggestionFilterData = DataView.empty
  private var collocationData = DataView.empty
  private var collocationSuppressionData = DataView.empty
  private var posGroupData = DataView.empty
  private var boundaryData = DataView.empty
  private var segmenterCompressedLSize = 0
  private var segmenterCompressedRSize = 0
  private var segmenterLTable = DataView.empty
  private var segmenterRTable = DataView.empty
  private var segmenterBitarray = DataView.empty
  private var counterSuffixData = DataView.empty
  private var suffixKeyArrayData = DataView.empty
  private var suffixValueArrayData = DataView.empty
  private var suffixTokenArrayData = DataView.empty
  private var readingCorrectionValueArrayData = DataView.empty
  private var readingCorrectionErrorArrayData = DataView.empty
  private var readingCorrectionCorrectionArrayData = DataView.empty
  private var symbolTokenArrayData = DataView.empty
  private var symbolStringArrayData = DataView.empty
  private var emoticonTokenArrayData = DataView.empty
  private var emoticonStringArrayData = DataView.empty
  private var emojiTokenArrayData = DataView.empty
  private var emojiStringArrayData = DataView.empty
  private var singleKanjiTokenArrayData = DataView.empty
  private var singleKanjiStringArrayData = DataView.empty
  private var singleKanjiVariantTypeData = DataView.empty
  private var singleKanjiVariantTokenArrayData = DataView.empty
  private var singleKanjiVariantStringArrayData = DataView.empty
  private var singleKanjiNounPrefixTokenArrayData = DataView.empty
  private var singleKanjiNounPrefixStringArrayData = DataView.empty
  private var a11yDescriptionTokenArrayData = DataView.empty
  private var a11yDescriptionStringArrayData = DataView.empty
  private var zeroQueryTokenArrayData = DataView.empty
  private var zeroQueryStringArrayData = DataView.empty
  private var zeroQueryNumberTokenArrayData = DataView.empty
  private var zeroQueryNumberStringArrayData = DataView.empty
  private var usageBaseConjugationSuffixData = DataView.empty
  private var usageConjugationSuffixData = DataView.empty
  private var usageConjugationIndexData = DataView.empty
  private var usageItemsData = DataView.empty
  private var usageStringArrayData = DataView.empty
  private var dataVersion = DataView.empty
  // Note: as in the C++ code (3.35.6354), this map is never populated, so
  // getOffsetAndSize() always returns nil.
  private var offsetAndSize: [String: (Int, Int)] = [:]

  /// An uninitialized data manager (C++ protected default constructor).
  /// Subclasses call one of the `initFrom*` methods in their initializer.
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
    filename = path
    try initFromArray(data, magic: magic)
  }

  /// Swift addition: initFromFile() that checks only the length of the magic
  /// number, used by OssDataManager / MockDataManager, which in C++ call
  /// `InitFromArray(embedded_data, kMagicNumberLength)` on embedded data.
  public func initFromFile(_ path: String, magicLength: Int) throws {
    let data = try mapFile(path)
    filename = path
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
    (posMatcherData, userPosTokenArrayData, userPosStringArrayData) =
      try initUserPosManagerDataFromReader(reader)
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
    mmap = mapped
    return DataView(mapped)
  }

  private func initFromReader(_ reader: DataSetReader) throws {
    (posMatcherData, userPosTokenArrayData, userPosStringArrayData) =
      try initUserPosManagerDataFromReader(reader)

    if let data = reader.get("pos_id_map") {
      posIdMapData = data
    } else {
      // pos_id_map is not provided
      posIdMapData = .empty
    }
    guard let conn = reader.get("conn") else {
      throw StatusError.notFound("Cannot find a connection data")
    }
    connectionData = conn
    guard let dict = reader.get("dict") else {
      throw StatusError.notFound("Cannot find a dictionary data")
    }
    dictionaryData = dict
    guard let sugg = reader.get("sugg") else {
      throw StatusError.notFound("Cannot find a suggestion filter data")
    }
    suggestionFilterData = sugg
    guard let coll = reader.get("coll") else {
      throw StatusError.notFound("Cannot find a collocation data")
    }
    collocationData = coll
    guard let cols = reader.get("cols") else {
      throw StatusError.notFound("Cannot find a collocation suprression data")
    }
    collocationSuppressionData = cols
    guard let posg = reader.get("posg") else {
      throw StatusError.notFound("Cannot find a POS group data")
    }
    posGroupData = posg
    guard let bdry = reader.get("bdry") else {
      throw StatusError.notFound("Cannot find a boundary data")
    }
    boundaryData = bdry
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
      segmenterCompressedLSize = Int(sizeinfo.compressedLsize)
      segmenterCompressedRSize = Int(sizeinfo.compressedRsize)
    }
    guard let ltable = reader.get("segmenter_ltable") else {
      throw StatusError.notFound("Cannot find a segmenter ltable")
    }
    segmenterLTable = ltable
    guard let rtable = reader.get("segmenter_rtable") else {
      throw StatusError.notFound("Cannot find a segmenter rtable")
    }
    segmenterRTable = rtable
    guard let bitarray = reader.get("segmenter_bitarray") else {
      throw StatusError.notFound("Cannot find a segmenter bit-array")
    }
    segmenterBitarray = bitarray
    guard let counterSuffix = reader.get("counter_suffix") else {
      throw StatusError.notFound("Cannot find a counter suffix data")
    }
    counterSuffixData = counterSuffix
    if !SerializedStringArray.verifyData(counterSuffixData) {
      throw StatusError.notFound("Counter suffix string array is broken")
    }
    guard let suffixKey = reader.get("suffix_key") else {
      throw StatusError.notFound("Cannot find a suffix key array")
    }
    suffixKeyArrayData = suffixKey
    guard let suffixValue = reader.get("suffix_value") else {
      throw StatusError.notFound("Cannot find a suffix value array")
    }
    suffixValueArrayData = suffixValue
    guard let suffixToken = reader.get("suffix_token") else {
      throw StatusError.notFound("Cannot find a suffix token array")
    }
    suffixTokenArrayData = suffixToken
    do {
      var suffixKeys = SerializedStringArray()
      var suffixValues = SerializedStringArray()
      if !suffixKeys.initialize(suffixKeyArrayData) || !suffixValues.initialize(suffixValueArrayData)
        || suffixKeys.size != suffixValues.size
        // Suffix token array is an array of triple (lid, rid, cost) of
        // uint32_t, so it contains N = 3 * |suffix_keys.size()| uint32_t
        // elements. Therefore, its byte length must be 4 * N bytes.
        || suffixTokenArrayData.count != 4 * 3 * suffixKeys.size
      {
        throw StatusError.dataLoss("Suffix dictionary data is broken")
      }
    }
    guard let rcValue = reader.get("reading_correction_value") else {
      throw StatusError.notFound("Cannot find reading correction value array")
    }
    readingCorrectionValueArrayData = rcValue
    guard let rcError = reader.get("reading_correction_error") else {
      throw StatusError.notFound("Cannot find reading correction error array")
    }
    readingCorrectionErrorArrayData = rcError
    guard let rcCorrection = reader.get("reading_correction_correction") else {
      throw StatusError.notFound("Cannot find reading correction correction array")
    }
    readingCorrectionCorrectionArrayData = rcCorrection
    do {
      var valueArray = SerializedStringArray()
      var errorArray = SerializedStringArray()
      var correctionArray = SerializedStringArray()
      if !valueArray.initialize(readingCorrectionValueArrayData)
        || !errorArray.initialize(readingCorrectionErrorArrayData)
        || !correctionArray.initialize(readingCorrectionCorrectionArrayData)
        || valueArray.size != errorArray.size || valueArray.size != correctionArray.size
      {
        throw StatusError.dataLoss("Reading correction data is broken")
      }
    }
    guard let symbolToken = reader.get("symbol_token") else {
      throw StatusError.notFound("Cannot find a symbol token array")
    }
    symbolTokenArrayData = symbolToken
    guard let symbolString = reader.get("symbol_string") else {
      throw StatusError.notFound("Cannot find a symbol string array or data is broken")
    }
    symbolStringArrayData = symbolString
    if !SerializedDictionary.verifyData(symbolTokenArrayData, symbolStringArrayData) {
      throw StatusError.dataLoss("Symbol dictionary data is broken")
    }
    guard let emoticonToken = reader.get("emoticon_token") else {
      throw StatusError.notFound("Cannot find an emoticon token array")
    }
    emoticonTokenArrayData = emoticonToken
    guard let emoticonString = reader.get("emoticon_string") else {
      throw StatusError.notFound("Cannot find an emoticon string array or data is broken")
    }
    emoticonStringArrayData = emoticonString
    if !SerializedDictionary.verifyData(emoticonTokenArrayData, emoticonStringArrayData) {
      throw StatusError.dataLoss("Emoticon dictionary data is broken")
    }
    guard let emojiToken = reader.get("emoji_token") else {
      throw StatusError.notFound("Cannot find an emoji token array")
    }
    emojiTokenArrayData = emojiToken
    guard let emojiString = reader.get("emoji_string") else {
      throw StatusError.notFound("Cannot find an emoji string array or data is broken")
    }
    emojiStringArrayData = emojiString
    if !SerializedStringArray.verifyData(emojiStringArrayData) {
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
    singleKanjiTokenArrayData = skToken
    singleKanjiStringArrayData = skString
    singleKanjiVariantTypeData = skVariantType
    singleKanjiVariantTokenArrayData = skVariantToken
    singleKanjiVariantStringArrayData = skVariantString
    singleKanjiNounPrefixTokenArrayData = skNounPrefixToken
    singleKanjiNounPrefixStringArrayData = skNounPrefixString
    if !SerializedStringArray.verifyData(singleKanjiStringArrayData)
      || !SerializedStringArray.verifyData(singleKanjiVariantTypeData)
      || !SerializedStringArray.verifyData(singleKanjiVariantStringArrayData)
      || !SerializedDictionary.verifyData(
        singleKanjiNounPrefixTokenArrayData, singleKanjiNounPrefixStringArrayData)
    {
      throw StatusError.dataLoss("Single Kanji data is broken")
    }
    if let data = reader.get("a11y_description_token") {
      a11yDescriptionTokenArrayData = data
    } else {
      // A11y description dictionary's token array is not provided.
      // A11y description dictionary is optional, so don't fail here.
      a11yDescriptionTokenArrayData = .empty
    }
    if let data = reader.get("a11y_description_string") {
      a11yDescriptionStringArrayData = data
    } else {
      // A11y description dictionary's string array is not provided.
      // A11y description dictionary is optional, so don't fail here.
      a11yDescriptionStringArrayData = .empty
    }
    if !(a11yDescriptionTokenArrayData.isEmpty && a11yDescriptionStringArrayData.isEmpty)
      && !SerializedDictionary.verifyData(
        a11yDescriptionTokenArrayData, a11yDescriptionStringArrayData)
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
    zeroQueryTokenArrayData = zqToken
    zeroQueryStringArrayData = zqString
    zeroQueryNumberTokenArrayData = zqNumberToken
    zeroQueryNumberStringArrayData = zqNumberString
    if !SerializedStringArray.verifyData(zeroQueryStringArrayData)
      || !SerializedStringArray.verifyData(zeroQueryNumberStringArrayData)
    {
      throw StatusError.dataLoss("Zero query data is broken")
    }

    if let items = reader.get("usage_item_array") {
      usageItemsData = items
      guard let baseConjugationSuffix = reader.get("usage_base_conjugation_suffix"),
        let conjugationSuffix = reader.get("usage_conjugation_suffix"),
        let conjugationIndex = reader.get("usage_conjugation_index"),
        let stringArray = reader.get("usage_string_array")
      else {
        throw StatusError.notFound("Cannot find some usage dictionary data components")
      }
      usageBaseConjugationSuffixData = baseConjugationSuffix
      usageConjugationSuffixData = conjugationSuffix
      usageConjugationIndexData = conjugationIndex
      usageStringArrayData = stringArray
      if !SerializedStringArray.verifyData(usageStringArrayData) {
        throw StatusError.dataLoss("Usage dictionary's string array is broken")
      }
    } else {
      // Usage dictionary is not provided.
      // Usage dictionary is optional, so don't fail here.
    }

    guard let version = reader.get("version") else {
      throw StatusError.notFound("Cannot find data version")
    }
    dataVersion = version
    do {
      let versionString = dataVersion.string
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

  open func getFilename() -> String? { filename }

  open func getPosMatcherData() -> DataSpan<UInt16> {
    posMatcherData.span(UInt16.self)
  }

  open func getPosIdMapData() -> DataView { posIdMapData }

  open func getUserPosData() -> (tokenArray: DataView, stringArray: DataView) {
    (userPosTokenArrayData, userPosStringArrayData)
  }

  open func getConnectorData() -> DataView { connectionData }

  open func getSystemDictionaryData() -> DataView { dictionaryData }

  open func getSuggestionFilterData() -> DataSpan<UInt32> {
    suggestionFilterData.span(UInt32.self)
  }

  open func getCollocationData() -> (collocation: DataView, collocationSuppression: DataView) {
    (collocationData, collocationSuppressionData)
  }

  open func getPosGroupData() -> DataSpan<UInt8> {
    posGroupData.span(UInt8.self)
  }

  open func getSegmenterData() -> (
    lNumElements: Int, rNumElements: Int, lTable: DataSpan<UInt16>, rTable: DataSpan<UInt16>,
    bitarrayData: DataSpan<UInt8>, boundaryData: DataSpan<UInt16>
  ) {
    (
      segmenterCompressedLSize,
      segmenterCompressedRSize,
      segmenterLTable.span(UInt16.self),
      segmenterRTable.span(UInt16.self),
      segmenterBitarray.span(UInt8.self),
      boundaryData.span(UInt16.self)
    )
  }

  open func getCounterSuffixSortedArray() -> DataView { counterSuffixData }

  open func getSuffixDictionaryData() -> (
    keyArray: DataView, valueArray: DataView, tokenArray: DataView
  ) {
    (suffixKeyArrayData, suffixValueArrayData, suffixTokenArrayData)
  }

  open func getReadingCorrectionData() -> (
    valueArray: DataView, errorArray: DataView, correctionArray: DataView
  ) {
    (
      readingCorrectionValueArrayData, readingCorrectionErrorArrayData,
      readingCorrectionCorrectionArrayData
    )
  }

  open func getSymbolRewriterData() -> (tokenArray: DataView, stringArray: DataView) {
    (symbolTokenArrayData, symbolStringArrayData)
  }

  open func getEmoticonRewriterData() -> (tokenArray: DataView, stringArray: DataView) {
    (emoticonTokenArrayData, emoticonStringArrayData)
  }

  open func getEmojiRewriterData() -> (tokenArray: DataView, stringArray: DataView) {
    (emojiTokenArrayData, emojiStringArrayData)
  }

  open func getSingleKanjiRewriterData() -> (
    tokenArray: DataView, stringArray: DataView, variantTypeArray: DataView,
    variantTokenArray: DataView, variantStringArray: DataView,
    nounPrefixTokenArray: DataView, nounPrefixStringArray: DataView
  ) {
    (
      singleKanjiTokenArrayData,
      singleKanjiStringArrayData,
      singleKanjiVariantTypeData,
      singleKanjiVariantTokenArrayData,
      singleKanjiVariantStringArrayData,
      singleKanjiNounPrefixTokenArrayData,
      singleKanjiNounPrefixStringArrayData
    )
  }

  open func getA11yDescriptionRewriterData() -> (tokenArray: DataView, stringArray: DataView) {
    (a11yDescriptionTokenArrayData, a11yDescriptionStringArrayData)
  }

  open func getZeroQueryData() -> (
    tokenArray: DataView, stringArray: DataView, numberTokenArray: DataView,
    numberStringArray: DataView
  ) {
    (
      zeroQueryTokenArrayData, zeroQueryStringArrayData, zeroQueryNumberTokenArrayData,
      zeroQueryNumberStringArrayData
    )
  }

  open func getUsageRewriterData() -> (
    baseConjugationSuffix: DataView, conjugationSuffix: DataView, conjugationIndex: DataView,
    usageItems: DataView, stringArray: DataView
  ) {
    (
      usageBaseConjugationSuffixData, usageConjugationSuffixData, usageConjugationIndexData,
      usageItemsData, usageStringArrayData
    )
  }

  /// The data version string, e.g. "24.11.oss".
  open func getDataVersion() -> String { dataVersion.string }

  open func getOffsetAndSize(_ name: String) -> (offset: Int, size: Int)? {
    if let v = offsetAndSize[name] {
      return v
    }
    return nil
  }
}
