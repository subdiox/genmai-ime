// Input files and parameters of one Mozc data set, i.e. the arguments of the
// `mozc_dataset` macro in mozc/src/data_manager/mozc_data.bzl as instantiated
// by mozc/src/data_manager/oss/BUILD.bazel (`mozc_dataset_for_oss`) and
// mozc/src/data_manager/testing/BUILD.bazel (`mozc_dataset_for_testing`)
// (3.35.6354).

import Foundation

public struct DataGenSources: Sendable {
  /// `Vendor/mozc/src`.
  public var srcRoot: String
  /// `tag` ("oss" / "mock").
  public var tag: String
  /// `magic` (MOZC_DATASET_MAGIC_NUMBER).
  public var magic: [UInt8]
  /// `use_1byte_cost` (both data sets: false).
  public var useOneByteCost: Bool = false

  public var a11yDescription: String
  public var boundaryDef: String
  public var cforms: String
  public var collocation: String
  public var collocationSuppression: String
  public var connectionSingleColumn: String
  /// `dictionary_srcs`, in the order Bazel passes them (`$(locations ...)`).
  /// Files ending with `reading_correction.tsv` are reading correction inputs
  /// (see gen_system_dictionary_data_main.cc).  For the OSS set, the first two
  /// entries are generated (aux_dictionary.txt and the filtered
  /// dictionary.txt, see `OssDictionarySources`).
  public var dictionaryFiles: [String]
  public var emoji: String
  public var emoticonCategorized: String
  public var emoticon: String
  public var idDef: String
  public var posGroupDef: String
  public var posMatcherRuleDef: String
  public var readingCorrection: String
  public var segmenterDef: String
  public var singleKanji: String
  public var sortingMap: String
  public var specialPos: String
  public var suffix: String
  public var suggestionFilter: String
  public var suggestionFilterSafeDefs: [String] = []
  public var symbolOrderingRule: String
  public var symbol: String
  public var userPosDef: String
  public var variantRule: String
  public var zeroQueryDef: String
  public var zeroQueryNumberDef: String
  /// `//:version.bzl`.
  public var versionBzl: String
  /// `@ja_usage_dict//:usage_dict.txt` (nil: no usage sections).
  public var usageDict: String?

  /// Path relative to `srcRoot`.
  static func path(_ root: String, _ rel: String) -> String {
    (root as NSString).appendingPathComponent(rel)
  }

  /// Files shared by both data sets.
  private init(srcRoot: String, tag: String, magic: [UInt8], dictionaryDir: String, dictionaryFiles: [String], usageDict: String?) {
    func p(_ rel: String) -> String { DataGenSources.path(srcRoot, rel) }
    self.srcRoot = srcRoot
    self.tag = tag
    self.magic = magic
    a11yDescription = p("data/a11y_description/a11y_description_data.tsv")
    boundaryDef = p("data/rules/boundary.def")
    cforms = p("data/rules/cforms.def")
    collocation = p("\(dictionaryDir)/collocation.txt")
    collocationSuppression = p("\(dictionaryDir)/collocation_suppression.txt")
    connectionSingleColumn = p("\(dictionaryDir)/connection_single_column.txt")
    self.dictionaryFiles = dictionaryFiles
    emoji = p("data/emoji/emoji_data.tsv")
    emoticonCategorized = p("data/emoticon/categorized.tsv")
    emoticon = p("data/emoticon/emoticon.tsv")
    idDef = p("\(dictionaryDir)/id.def")
    posGroupDef = p("data/rules/user_segment_history_pos_group.def")
    posMatcherRuleDef = p("data/rules/pos_matcher_rule.def")
    readingCorrection = p("\(dictionaryDir)/reading_correction.tsv")
    segmenterDef = p("data/rules/segmenter.def")
    singleKanji = p("data/single_kanji/single_kanji.tsv")
    sortingMap = p("data/rules/sorting_map.tsv")
    specialPos = p("data/rules/special_pos.def")
    suffix = p("\(dictionaryDir)/suffix.txt")
    suggestionFilter = p("\(dictionaryDir)/suggestion_filter.txt")
    symbolOrderingRule = p("data/symbol/ordering_rule.txt")
    symbol = p("data/symbol/symbol.tsv")
    userPosDef = p("data/rules/user_pos.def")
    variantRule = p("data/single_kanji/variant_rule.txt")
    zeroQueryDef = p("data/zero_query/zero_query.def")
    zeroQueryNumberDef = p("data/zero_query/zero_query_number.def")
    versionBzl = p("version.bzl")
    self.usageDict = usageDict
  }

  /// `MOZC_DATASET_MAGIC_NUMBER` of data_manager/oss/BUILD.bazel.
  public static let ossMagic: [UInt8] = [0xEF, 0x4D, 0x4F, 0x5A, 0x43, 0x0D, 0x0A]
  /// `MOZC_DATASET_MAGIC_NUMBER` of data_manager/testing/BUILD.bazel.
  public static let mockMagic: [UInt8] = [0x4D, 0x4F, 0x43, 0x4B]

  /// `mozc_dataset_for_oss`.  `auxDictionary` and `filteredDictionary` are the
  /// outputs of `//data/dictionary_oss:aux_dictionary` and
  /// `:filtered_dictionary` (see `OssDictionarySources.generate`).
  public static func oss(
    srcRoot: String, auxDictionary: String, filteredDictionary: String, usageDict: String?
  ) -> DataGenSources {
    DataGenSources(
      srcRoot: srcRoot, tag: "oss", magic: ossMagic, dictionaryDir: "data/dictionary_oss",
      dictionaryFiles: [
        auxDictionary, filteredDictionary,
        path(srcRoot, "data/dictionary_oss/reading_correction.tsv"),
        path(srcRoot, "data/dictionary_manual/domain.txt"),
      ],
      usageDict: usageDict)
  }

  /// `mozc_dataset_for_testing`.
  public static func mock(srcRoot: String, usageDict: String?) -> DataGenSources {
    DataGenSources(
      srcRoot: srcRoot, tag: "mock", magic: mockMagic, dictionaryDir: "data/test/dictionary",
      dictionaryFiles: [
        path(srcRoot, "data/test/dictionary/dictionary.txt"),
        path(srcRoot, "data/dictionary_manual/domain.txt"),
      ],
      usageDict: usageDict)
  }
}

/// Inputs of the OSS dictionary preprocessing rules in
/// data/dictionary_oss/BUILD.bazel (`aux_dictionary`, `filtered_dictionary`)
/// and dictionary/BUILD.bazel (`zip_code_data`).
public struct OssDictionarySources: Sendable {
  public var srcRoot: String
  /// `@zip_code_ken_all//:KEN_ALL.CSV` (nil: no zip code dictionary, as in
  /// the `prod` / default branches of mozc_select).
  public var zipCodeKenAll: String?
  /// `@zip_code_jigyosyo//:JIGYOSYO.CSV`.
  public var zipCodeJigyosyo: String?

  public init(srcRoot: String, zipCodeKenAll: String?, zipCodeJigyosyo: String?) {
    self.srcRoot = srcRoot
    self.zipCodeKenAll = zipCodeKenAll
    self.zipCodeJigyosyo = zipCodeJigyosyo
  }

  /// dictionary00.txt ... dictionary09.txt.
  public var baseDictionaryTexts: [String] {
    (0..<10).map { DataGenSources.path(srcRoot, "data/dictionary_oss/dictionary0\($0).txt") }
  }
  public var auxTsv: String { DataGenSources.path(srcRoot, "data/dictionary_oss/aux_dictionary.tsv") }
  public var idDef: String { DataGenSources.path(srcRoot, "data/dictionary_oss/id.def") }
  public var filterTsv: String { DataGenSources.path(srcRoot, "data/dictionary_oss/dictionary_filter.tsv") }
  /// `//data/dictionary_manual` filegroup.
  public var wordsTsvs: [String] {
    ["places.tsv", "words.tsv"].map { DataGenSources.path(srcRoot, "data/dictionary_manual/\($0)") }
  }
}
