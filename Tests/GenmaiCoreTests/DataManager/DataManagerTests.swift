// Tests for the port of mozc/src/data_manager/data_manager.{h,cc} (3.35.6354).
// (There is no data_manager_test.cc in C++; these are Swift-only checks of
// the real data set and of DataManager's validation.)

import Foundation
import GenmaiBase
import Testing

@testable import GenmaiCore

@Suite(
  .enabled(if: DataManagerTestSupport.hasOssData, "Data/genmai.data is missing; run Tools/build_oracle.sh to create it")
)
struct DataManagerOssDataSetTest {
  static let kAllSections = [
    "pos_matcher", "pos_id_map", "user_pos_token", "user_pos_string", "coll", "cols", "conn",
    "dict", "sugg", "posg", "bdry", "segmenter_sizeinfo", "segmenter_ltable", "segmenter_rtable",
    "segmenter_bitarray", "counter_suffix", "suffix_key", "suffix_value", "suffix_token",
    "reading_correction_value", "reading_correction_error", "reading_correction_correction",
    "symbol_token", "symbol_string", "emoticon_token", "emoticon_string", "emoji_token",
    "emoji_string", "single_kanji_token", "single_kanji_string", "single_kanji_variant_type",
    "single_kanji_variant_token", "single_kanji_variant_string",
    "single_kanji_noun_prefix_token", "single_kanji_noun_prefix_string",
    "zero_query_token_array", "zero_query_string_array", "zero_query_number_token_array",
    "zero_query_number_string_array", "a11y_description_token", "a11y_description_string",
    "version", "usage_base_conjugation_suffix", "usage_conjugation_suffix",
    "usage_conjugation_index", "usage_item_array", "usage_string_array",
  ]

  @Test func everySectionIsPresent() throws {
    let path = DataManagerTestSupport.ossDataPath
    let mmap = try Mmap.map(path)
    let image = DataView(mmap)

    // Magic number check (CreateFromFile checks the full magic).
    let magic = DataManager.getDataSetMagicNumber("oss")
    #expect(magic == [0xEF, 0x4D, 0x4F, 0x5A, 0x43, 0x0D, 0x0A])
    #expect(image.starts(with: magic))

    var reader = DataSetReader()
    let initialized = reader.initialize(image, magic: magic)
    try #require(initialized)
    #expect(Set(reader.nameToDataMap.keys) == Set(Self.kAllSections))
    for name in Self.kAllSections {
      let data = try #require(reader.get(name), "\(name)")
      #expect(!data.isEmpty, "\(name)")
      // Every section must be at least 4-byte aligned so that typed spans work.
      let (offset, _) = try #require(reader.getOffsetAndSize(name))
      #expect(offset % 4 == 0, "\(name) at \(offset)")
    }

    let dm = try DataManager.createFromFile(path)
    #expect(dm.getFilename() == path)

    // Version: "<engine>.<data>.oss".
    let version = dm.getDataVersion()
    let components = version.split(separator: ".").map(String.init)
    #expect(components.count == 3)
    #expect(components.first == Version.getGenmaiEngineVersion())
    #expect(components.last == "oss")
    let versionSection = try #require(reader.get("version"))
    #expect(version == versionSection.string)

    // Typed spans are non-empty (i.e. aligned and of valid size).
    #expect(!dm.getPosMatcherData().isEmpty)
    #expect(!dm.getPosIdMapData().isEmpty)
    let userPos = dm.getUserPosData()
    #expect(!userPos.tokenArray.isEmpty && userPos.tokenArray.count % 8 == 0)
    #expect(SerializedStringArray.verifyData(userPos.stringArray))
    #expect(!dm.getConnectorData().isEmpty)
    let dictSection = try #require(reader.get("dict"))
    #expect(dm.getSystemDictionaryData() == dictSection)
    let suggSection = try #require(reader.get("sugg"))
    #expect(dm.getSuggestionFilterData().count == suggSection.count / 4)
    let collocation = dm.getCollocationData()
    #expect(!collocation.collocation.isEmpty && !collocation.collocationSuppression.isEmpty)
    let posgSection = try #require(reader.get("posg"))
    #expect(dm.getPosGroupData().count == posgSection.count)

    let segmenter = dm.getSegmenterData()
    #expect(segmenter.lNumElements > 0 && segmenter.rNumElements > 0)
    let segmenterLtableSection = try #require(reader.get("segmenter_ltable"))
    #expect(segmenter.lTable.count == segmenterLtableSection.count / 2)
    let segmenterRtableSection = try #require(reader.get("segmenter_rtable"))
    #expect(segmenter.rTable.count == segmenterRtableSection.count / 2)
    #expect(segmenter.bitarrayData.count * 8 >= segmenter.lNumElements * segmenter.rNumElements)
    let bdrySection = try #require(reader.get("bdry"))
    #expect(segmenter.boundaryData.count == bdrySection.count / 2)
    // Every compressed id is within the compressed size.
    #expect(segmenter.lTable.allSatisfy { Int($0) < segmenter.lNumElements })
    #expect(segmenter.rTable.allSatisfy { Int($0) < segmenter.rNumElements })

    #expect(SerializedStringArray.verifyData(dm.getCounterSuffixSortedArray()))
    let suffix = dm.getSuffixDictionaryData()
    let suffixKeys = try #require(SerializedStringArray(suffix.keyArray))
    #expect(suffix.tokenArray.count == 12 * suffixKeys.size)

    let rc = dm.getReadingCorrectionData()
    let valueArray = try #require(SerializedStringArray(rc.valueArray))
    let errorArray = try #require(SerializedStringArray(rc.errorArray))
    #expect(valueArray.size == errorArray.size)

    for (name, data) in [
      ("symbol", dm.getSymbolRewriterData()), ("emoticon", dm.getEmoticonRewriterData()),
      ("a11y", dm.getA11yDescriptionRewriterData()),
    ] {
      #expect(SerializedDictionary.verifyData(data.tokenArray, data.stringArray), "\(name)")
      #expect(!SerializedDictionary(data).isEmpty, "\(name)")
    }

    let emoji = dm.getEmojiRewriterData()
    let emojiTokens = EmojiDataArray(emoji.tokenArray)
    #expect(emojiTokens.count == emoji.tokenArray.count / EmojiData.byteSize)
    #expect(emojiTokens.count > 0)
    let emojiStrings = try #require(SerializedStringArray(emoji.stringArray))
    for token in emojiTokens {
      #expect(Int(token.keyIndex) < emojiStrings.size)
      #expect(Int(token.emojiIndex) < emojiStrings.size)
      #expect(Int(token.descriptionUtf8Index) < emojiStrings.size)
      #expect(token.unicodeVersionIndex <= EmojiVersion.emojiMaxVersion.rawValue)
    }

    let singleKanji = dm.getSingleKanjiRewriterData()
    #expect(!singleKanji.tokenArray.isEmpty)
    #expect(SerializedStringArray.verifyData(singleKanji.stringArray))
    #expect(SerializedStringArray.verifyData(singleKanji.variantTypeArray))
    #expect(!singleKanji.variantTokenArray.isEmpty)
    #expect(SerializedStringArray.verifyData(singleKanji.variantStringArray))
    #expect(
      SerializedDictionary.verifyData(
        singleKanji.nounPrefixTokenArray, singleKanji.nounPrefixStringArray))

    let zeroQuery = dm.getZeroQueryData()
    #expect(!zeroQuery.tokenArray.isEmpty && !zeroQuery.numberTokenArray.isEmpty)
    #expect(SerializedStringArray.verifyData(zeroQuery.stringArray))
    #expect(SerializedStringArray.verifyData(zeroQuery.numberStringArray))

    let usage = dm.getUsageRewriterData()
    #expect(!usage.baseConjugationSuffix.isEmpty && !usage.conjugationSuffix.isEmpty)
    #expect(!usage.conjugationIndex.isEmpty && !usage.usageItems.isEmpty)
    #expect(SerializedStringArray.verifyData(usage.stringArray))

    // As in C++ 3.35.6354, GetOffsetAndSize() of DataManager is never filled.
    #expect(dm.getOffsetAndSize("dict") == nil)
  }

  @Test func checksum() throws {
    let mmap = try Mmap.map(DataManagerTestSupport.ossDataPath)
    #expect(DataSetReader.verifyChecksum(DataView(mmap)))
  }

  @Test func wrongMagicIsRejected() {
    #expect(throws: StatusError.self) {
      _ = try DataManager.createFromFile(
        DataManagerTestSupport.ossDataPath, magic: Array("MOCK".utf8))
    }
  }

  @Test func viewsKeepTheMappedFileAlive() throws {
    var symbol: (tokenArray: DataView, stringArray: DataView)
    do {
      let dm = try DataManager.createFromFile(DataManagerTestSupport.ossDataPath)
      symbol = dm.getSymbolRewriterData()
    }
    // The DataManager is gone; the views still own the mapping.
    let dic = SerializedDictionary(symbol)
    #expect(dic.count == symbol.tokenArray.count / SerializedDictionary.kTokenByteLength)
    let first = dic[dic.startIndex]
    #expect(dic.equalRange(first.key).contains(dic.startIndex))
  }

  @Test func symbolDictionaryLookup() throws {
    let dm = try OssDataManager.create()
    let dic = SerializedDictionary(dm.getSymbolRewriterData())
    // data/symbol/symbol.tsv has entries for "きごう".
    let range = dic.equalRange("きごう")
    #expect(!range.isEmpty)
    var prevCost = Int16.min
    for i in range {
      #expect(dic[i].key == "きごう")
      #expect(dic[i].cost >= prevCost)  // sorted by cost
      prevCost = dic[i].cost
    }
    #expect(dic.lowerBound("きごう") == range.lowerBound)
    #expect(dic.upperBound("きごう") == range.upperBound)
    #expect(dic.equalRange("存在しないキー").isEmpty)
    // The whole array is sorted by key bytes.
    for i in 1..<dic.count {
      #expect(!Array(dic[i].keyBytes).lexicographicallyPrecedes(Array(dic[i - 1].keyBytes)))
    }
  }

  @Test func userPosManagerData() throws {
    let path = DataManagerTestSupport.ossDataPath
    let dm = try DataManager.createUserPosManagerDataFromFile(
      path, magic: DataManager.getDataSetMagicNumber("oss"))
    #expect(!dm.getPosMatcherData().isEmpty)
    #expect(!dm.getUserPosData().tokenArray.isEmpty)
    // Only the user POS sections are loaded.
    #expect(dm.getSystemDictionaryData().isEmpty)
  }
}

/// DataManager validation on small synthetic data sets.
@Suite struct DataManagerValidationTest {
  static let kMagic = DataManager.getDataSetMagicNumber("oss")

  /// A string array image of `strs`.
  static func strings(_ strs: [String]) -> [UInt8] {
    SerializedStringArray.serializeToBuffer(strs)
  }

  /// A minimal valid data set; `override` replaces (or with nil removes)
  /// sections.
  static func makeImage(_ override: [String: [UInt8]?] = [:]) -> DataView {
    let empty = strings([])
    let dictionary = SerializedDictionary.compile(
      InputFileStream(string: "key\t1\t2\t3\tvalue\n"))
    var sections: [(String, [UInt8])] = [
      ("pos_matcher", [1, 0, 2, 0]),
      ("user_pos_token", [UInt8](repeating: 0, count: 8)),
      ("user_pos_string", strings(["名詞"])),
      ("conn", [1]), ("dict", [2]), ("sugg", [0, 0, 0, 0]), ("coll", [3]), ("cols", [4]),
      ("posg", [5]), ("bdry", [0, 0]),
      ("segmenter_sizeinfo", [0x08, 0x02, 0x10, 0x03]),  // compressed_lsize = 2, rsize = 3
      ("segmenter_ltable", [0, 0]), ("segmenter_rtable", [0, 0]), ("segmenter_bitarray", [0]),
      ("counter_suffix", strings(["個"])),
      ("suffix_key", strings(["a"])), ("suffix_value", strings(["b"])),
      ("suffix_token", [UInt8](repeating: 0, count: 12)),
      ("reading_correction_value", empty), ("reading_correction_error", empty),
      ("reading_correction_correction", empty),
      ("symbol_token", dictionary.tokenArray), ("symbol_string", dictionary.stringArray),
      ("emoticon_token", dictionary.tokenArray), ("emoticon_string", dictionary.stringArray),
      ("emoji_token", []), ("emoji_string", empty),
      ("single_kanji_token", []), ("single_kanji_string", empty),
      ("single_kanji_variant_type", empty), ("single_kanji_variant_token", []),
      ("single_kanji_variant_string", empty),
      ("single_kanji_noun_prefix_token", dictionary.tokenArray),
      ("single_kanji_noun_prefix_string", dictionary.stringArray),
      ("zero_query_token_array", []), ("zero_query_string_array", empty),
      ("zero_query_number_token_array", []), ("zero_query_number_string_array", empty),
      ("version", Array("\(Version.getGenmaiEngineVersion()).1.test".utf8)),
    ]
    for (name, data) in override {
      if let index = sections.firstIndex(where: { $0.0 == name }) {
        if let data {
          sections[index].1 = data
        } else {
          sections.remove(at: index)
        }
      } else if let data {
        sections.append((name, data))
      }
    }
    var w = DataSetWriter(magic: kMagic)
    for (name, data) in sections {
      w.add(name, 32, data)
    }
    return DataView(copying: w.finish())
  }

  private static func code(_ body: () throws -> Void) -> StatusCode? {
    do {
      try body()
      return nil
    } catch let e as StatusError {
      return e.code
    } catch {
      return .unknown
    }
  }

  @Test func minimalDataSet() throws {
    let dm = try DataManager.createFromArray(Self.makeImage())
    #expect(dm.getFilename() == nil)
    #expect(dm.getPosMatcherData().elementsEqual([1, 2]))
    #expect(dm.getPosIdMapData().isEmpty)  // optional
    #expect(dm.getA11yDescriptionRewriterData().tokenArray.isEmpty)  // optional
    #expect(dm.getUsageRewriterData().usageItems.isEmpty)  // optional
    #expect(dm.getSegmenterData().lNumElements == 2)
    #expect(dm.getSegmenterData().rNumElements == 3)
    #expect(dm.getConnectorData().array == [1])
    #expect(dm.getDataVersion() == "\(Version.getGenmaiEngineVersion()).1.test")

    // The magic number can also be given by length only.
    _ = try DataManager.createFromArray(Self.makeImage(), magicLength: Self.kMagic.count)
  }

  @Test func missingSections() {
    for name in ["pos_matcher", "conn", "dict", "segmenter_sizeinfo", "version", "emoji_string"] {
      #expect(
        Self.code { _ = try DataManager.createFromArray(Self.makeImage([name: nil])) }
          == .notFound, "\(name)")
    }
    // Usage dictionary is optional, but all of its components are needed once
    // usage_item_array exists.
    #expect(
      Self.code { _ = try DataManager.createFromArray(Self.makeImage(["usage_item_array": [1]])) }
        == .notFound)
  }

  @Test func brokenSections() {
    #expect(
      Self.code {
        _ = try DataManager.createFromArray(Self.makeImage(["user_pos_token": [0, 0, 0, 0]]))
      } == .dataLoss)
    #expect(
      Self.code {
        _ = try DataManager.createFromArray(
          Self.makeImage(["suffix_token": [UInt8](repeating: 0, count: 8)]))
      } == .dataLoss)
    #expect(
      Self.code {
        _ = try DataManager.createFromArray(Self.makeImage(["symbol_token": [0, 0, 0]]))
      } == .dataLoss)
    #expect(
      Self.code {
        _ = try DataManager.createFromArray(Self.makeImage(["a11y_description_token": [0]]))
      } == .dataLoss)
    #expect(
      Self.code {
        _ = try DataManager.createFromArray(Self.makeImage(["segmenter_sizeinfo": [0xFF]]))
      } == .dataLoss)
  }

  @Test func version() {
    #expect(
      Self.code {
        _ = try DataManager.createFromArray(Self.makeImage(["version": Array("1.2".utf8)]))
      } == .dataLoss)
    #expect(
      Self.code {
        _ = try DataManager.createFromArray(Self.makeImage(["version": Array("1.2.3".utf8)]))
      } == .failedPrecondition)
  }

  @Test func brokenImage() {
    #expect(
      Self.code { _ = try DataManager.createFromArray(DataView(copying: "broken")) } == .dataLoss)
    #expect(
      Self.code {
        _ = try DataManager.createFromArray(Self.makeImage(), magic: Array("MOCK".utf8))
      } == .dataLoss)
    #expect(
      Self.code { _ = try DataManager.createFromFile("/nonexistent/genmai.data") }
        == .permissionDenied)
  }
}

@Suite struct PosListProviderTest {
  @Test func posList() {
    let provider = PosListProvider()
    let list = provider.getPosList()
    #expect(list.count == 45)
    #expect(list[provider.getPosListDefaultIndex()] == "名詞")
    #expect(list.first == "品詞なし")
    #expect(list.contains("動詞サ変"))
  }
}

@Suite struct ConnectionFileReaderTest {
  @Test func read() throws {
    let tempDir = try TempDirectory.default().createTempDirectory()
    defer { withExtendedLifetime(tempDir) {} }
    tempDir.keep = false
    let path = FileUtil.joinPath(tempDir.path, "connection_single_column.txt")
    defer { try? FileUtil.unlinkIfExists(path) }
    try FileUtil.setContents(path, "2\n0\n10\n20\n30\n")
    let reader = ConnectionFileReader(path)
    #expect(reader.leftSize == 2 && reader.rightSize == 2)
    var entries: [[Int32]] = []
    while !reader.done {
      entries.append([reader.ridOfLeftNode, reader.lidOfRightNode, reader.cost])
      reader.next()
    }
    #expect(entries == [[0, 0, 0], [0, 1, 10], [1, 0, 20], [1, 1, 30]])
  }
}
