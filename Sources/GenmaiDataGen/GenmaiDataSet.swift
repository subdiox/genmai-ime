// Port of the `mozc_dataset` macro of mozc/src/data_manager/mozc_data.bzl
// (3.35.6354): the list of data set sections, the generator producing each of
// them, and the final dataset_writer_main invocation.

import Foundation
import GenmaiBase
import GenmaiCore

/// The genrules of `mozc_dataset` (one per generator tool).
public enum DataGenerator: String, CaseIterable, Sendable {
  case userPos = "user_pos"  // dictionary/gen_user_pos_data.py
  case posMatcher = "pos_matcher"  // dictionary/gen_pos_matcher_code.py
  case posIdMap = "pos_id_map"  // dictionary/gen_pos_id_map.py
  case collocation  // rewriter/gen_collocation_data_main.cc
  case collocationSuppression = "collocation_suppression"  // rewriter/gen_collocation_suppression_data_main.cc
  case connection  // data_manager/gen_connection_data.py
  case dictionary  // dictionary/gen_system_dictionary_data_main.cc
  case suggestionFilter = "suggestion_filter"  // prediction/gen_suggestion_filter_main.cc
  case posGroup = "pos_group"  // dictionary/gen_pos_rewrite_rule.py
  case boundary  // converter/gen_boundary_data.py
  case segmenter  // converter/gen_segmenter_code.py + gen_*_segmenter_bitarray_main.cc
  case counterSuffix = "counter_suffix"  // rewriter/gen_counter_suffix_array.py
  case suffix  // dictionary/gen_suffix_data.py
  case readingCorrection = "reading_correction"  // rewriter/gen_reading_correction_data.py
  case symbol  // rewriter/gen_symbol_rewriter_dictionary_main.cc
  case emoticon  // rewriter/gen_emoticon_rewriter_data.cc
  case emoji  // rewriter/gen_emoji_rewriter_data.py
  case singleKanji = "single_kanji"  // rewriter/gen_single_kanji_rewriter_data.py
  case singleKanjiNounPrefix = "single_kanji_noun_prefix"  // rewriter/gen_single_kanji_noun_prefix_data.cc
  case zeroQuery = "zero_query"  // prediction/gen_zero_query_data.py
  case zeroQueryNumber = "zero_query_number"  // prediction/gen_zero_query_number_data.py
  case a11yDescription = "a11y_description"  // rewriter/gen_a11y_description_rewriter_data.py
  case version  // data_manager/gen_data_version.py
  case usage  // rewriter/gen_usage_rewriter_dictionary_main.cc

  /// Runs the generator.  The result maps data set keys (the `name` part of
  /// dataset_writer_main's `name:alignment:file` arguments) to file contents.
  public func run(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    switch self {
    case .userPos: return try GenUserPosData.sections(ctx)
    case .posMatcher: return try GenPosMatcherCode.sections(ctx)
    case .posIdMap: return try GenPosIdMap.sections(ctx)
    case .collocation: return try GenCollocationDataMain.sections(ctx)
    case .collocationSuppression: return try GenCollocationSuppressionDataMain.sections(ctx)
    case .connection: return try GenConnectionData.sections(ctx)
    case .dictionary: return try GenSystemDictionaryDataMain.sections(ctx)
    case .suggestionFilter: return try GenSuggestionFilterMain.sections(ctx)
    case .posGroup: return try GenPosRewriteRule.sections(ctx)
    case .boundary: return try GenBoundaryData.sections(ctx)
    case .segmenter: return try GenSegmenterBitarrayMain.sections(ctx)
    case .counterSuffix: return try GenCounterSuffixArray.sections(ctx)
    case .suffix: return try GenSuffixData.sections(ctx)
    case .readingCorrection: return try GenReadingCorrectionData.sections(ctx)
    case .symbol: return try GenSymbolRewriterDictionaryMain.sections(ctx)
    case .emoticon: return try GenEmoticonRewriterData.sections(ctx)
    case .emoji: return try GenEmojiRewriterData.sections(ctx)
    case .singleKanji: return try GenSingleKanjiRewriterData.sections(ctx)
    case .singleKanjiNounPrefix: return try GenSingleKanjiNounPrefixData.sections(ctx)
    case .zeroQuery: return try GenZeroQueryData.sections(ctx)
    case .zeroQueryNumber: return try GenZeroQueryNumberData.sections(ctx)
    case .a11yDescription: return try GenA11yDescriptionRewriterData.sections(ctx)
    case .version: return try GenDataVersion.sections(ctx)
    case .usage: return try GenUsageRewriterDictionaryMain.sections(ctx)
    }
  }
}

public enum DataGenError: Error, CustomStringConvertible {
  case invalidInput(String)
  case missingSection(String)

  public var description: String {
    switch self {
    case .invalidInput(let s): return "invalid input: \(s)"
    case .missingSection(let s): return "generator did not produce section \(s)"
    }
  }
}

/// What every generator gets: the inputs, and the outputs of the generators
/// it depends on.
public struct DataGenContext: Sendable {
  public let sources: DataGenSources
  /// `name@user_pos_manager_data`: a data set without magic containing
  /// pos_matcher, user_pos_token and user_pos_string (input of
  /// gen_system_dictionary_data_main and gen_symbol_rewriter_dictionary_main).
  /// Empty while the POS generators themselves run.
  public let userPosManagerData: [UInt8]

  public init(sources: DataGenSources, userPosManagerData: [UInt8] = []) {
    self.sources = sources
    self.userPosManagerData = userPosManagerData
  }
}

public enum GenmaiDataSet {
  /// One `name:alignment:file` argument of dataset_writer_main.
  public struct Entry: Sendable {
    public let name: String
    public let alignment: Int
    public let generator: DataGenerator
  }

  /// The `arguments` of `mozc_dataset`, in order.
  public static func entries(withUsage: Bool) -> [Entry] {
    var list: [(String, DataGenerator)] = [
      ("pos_matcher", .posMatcher),
      ("pos_id_map", .posIdMap),
      ("user_pos_token", .userPos),
      ("user_pos_string", .userPos),
      ("coll", .collocation),
      ("cols", .collocationSuppression),
      ("conn", .connection),
      ("dict", .dictionary),
      ("sugg", .suggestionFilter),
      ("posg", .posGroup),
      ("bdry", .boundary),
      ("segmenter_sizeinfo", .segmenter),
      ("segmenter_ltable", .segmenter),
      ("segmenter_rtable", .segmenter),
      ("segmenter_bitarray", .segmenter),
      ("counter_suffix", .counterSuffix),
      ("suffix_key", .suffix),
      ("suffix_value", .suffix),
      ("suffix_token", .suffix),
      ("reading_correction_value", .readingCorrection),
      ("reading_correction_error", .readingCorrection),
      ("reading_correction_correction", .readingCorrection),
      ("symbol_token", .symbol),
      ("symbol_string", .symbol),
      ("emoticon_token", .emoticon),
      ("emoticon_string", .emoticon),
      ("emoji_token", .emoji),
      ("emoji_string", .emoji),
      ("single_kanji_token", .singleKanji),
      ("single_kanji_string", .singleKanji),
      ("single_kanji_variant_type", .singleKanji),
      ("single_kanji_variant_token", .singleKanji),
      ("single_kanji_variant_string", .singleKanji),
      ("single_kanji_noun_prefix_token", .singleKanjiNounPrefix),
      ("single_kanji_noun_prefix_string", .singleKanjiNounPrefix),
      ("zero_query_token_array", .zeroQuery),
      ("zero_query_string_array", .zeroQuery),
      ("zero_query_number_token_array", .zeroQueryNumber),
      ("zero_query_number_string_array", .zeroQueryNumber),
      ("a11y_description_token", .a11yDescription),
      ("a11y_description_string", .a11yDescription),
      ("version", .version),
    ]
    if withUsage {
      list += [
        ("usage_base_conjugation_suffix", .usage),
        ("usage_conjugation_suffix", .usage),
        ("usage_conjugation_index", .usage),
        ("usage_item_array", .usage),
        ("usage_string_array", .usage),
      ]
    }
    return list.map { Entry(name: $0.0, alignment: 32, generator: $0.1) }
  }

  /// `name@user_pos_manager_data`.
  public static func userPosManagerData(posMatcher: [String: [UInt8]], userPos: [String: [UInt8]]) throws -> [UInt8] {
    var writer = DataSetWriter(magic: [UInt8]())
    writer.add("pos_matcher", 32, try section(posMatcher, "pos_matcher"))
    writer.add("user_pos_token", 32, try section(userPos, "user_pos_token"))
    writer.add("user_pos_string", 32, try section(userPos, "user_pos_string"))
    return writer.finish()
  }

  static func section(_ outputs: [String: [UInt8]], _ name: String) throws -> [UInt8] {
    guard let s = outputs[name] else { throw DataGenError.missingSection(name) }
    return s
  }

  /// Timing of one generator run.
  public struct Timing: Sendable {
    public let generator: DataGenerator
    public let seconds: Double
  }

  /// Runs all generators (independent ones in parallel) and returns their
  /// outputs.
  public static func generateSections(
    _ sources: DataGenSources, only: Set<DataGenerator>? = nil,
    userPosManagerData givenUserPosManagerData: [UInt8]? = nil
  ) async throws -> (outputs: [DataGenerator: [String: [UInt8]]], timings: [Timing]) {
    let entries = entries(withUsage: sources.usageDict != nil)
    var wanted = Set(entries.map(\.generator))
    if let only { wanted.formIntersection(only) }

    var outputs: [DataGenerator: [String: [UInt8]]] = [:]
    var timings: [Timing] = []
    func timed(_ g: DataGenerator, _ ctx: DataGenContext) throws -> ([String: [UInt8]], Timing) {
      let start = Date()
      let r = try g.run(ctx)
      return (r, Timing(generator: g, seconds: Date().timeIntervalSince(start)))
    }

    // Phase 1: POS data (user_pos_manager_data is an input of later phases).
    // A given user_pos_manager_data (e.g. Bazel's) skips it unless requested.
    let ctx0 = DataGenContext(sources: sources)
    for g in [DataGenerator.posMatcher, .userPos] where givenUserPosManagerData == nil || wanted.contains(g) {
      let (r, t) = try timed(g, ctx0)
      outputs[g] = r
      timings.append(t)
    }
    let ctx = DataGenContext(
      sources: sources,
      userPosManagerData: try givenUserPosManagerData
        ?? userPosManagerData(posMatcher: outputs[.posMatcher]!, userPos: outputs[.userPos]!))

    // Phase 2: everything else, in parallel.
    let rest = DataGenerator.allCases.filter { wanted.contains($0) && outputs[$0] == nil }
    try await withThrowingTaskGroup(of: (DataGenerator, [String: [UInt8]], Timing).self) { group in
      for g in rest {
        group.addTask {
          let (r, t) = try timed(g, ctx)
          return (g, r, t)
        }
      }
      for try await (g, r, t) in group {
        outputs[g] = r
        timings.append(t)
      }
    }
    return (outputs, timings)
  }

  /// dataset_writer_main: packs the sections into the final image.
  public static func write(
    _ sources: DataGenSources, _ outputs: [DataGenerator: [String: [UInt8]]]
  ) throws -> [UInt8] {
    var writer = DataSetWriter(magic: sources.magic)
    for e in entries(withUsage: sources.usageDict != nil) {
      guard let out = outputs[e.generator] else { throw DataGenError.missingSection(e.name) }
      writer.add(e.name, e.alignment, try section(out, e.name))
    }
    return writer.finish()
  }

  /// Generates the whole data set image.
  public static func generate(_ sources: DataGenSources) async throws -> (image: [UInt8], timings: [Timing]) {
    let (outputs, timings) = try await generateSections(sources)
    return (try write(sources, outputs), timings)
  }
}
