// Port of mozc/src/rewriter/gen_counter_suffix_array.py (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenCounterSuffixArray {
  /// Data set sections produced by this generator (keys: dataset_writer_main names).
  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    let ids = try readCounterSuffixPosIds(ctx.sources.idDef)
    let suffixes = try readCounterSuffixes(ctx.sources.dictionaryFiles, ids)
    return ["counter_suffix": SerializedStringArray.serializeToBuffer(suffixes)]
  }

  /// POS ids (as strings, compared as strings) of 名詞,接尾,助数詞.
  static func readCounterSuffixPosIds(_ idFile: String) throws -> Set<String> {
    var posIds = Set<String>()
    for cols in CodeGenUtil.parseColumnStream(try Py.readLines(idFile, mode: .splitlines), numColumn: 2) {
      guard cols.count == 2 else { throw DataGenError.invalidInput("id.def: \(cols)") }
      if cols[1].hasPrefix("名詞,接尾,助数詞") { posIds.insert(cols[0]) }
    }
    return posIds
  }

  /// Returns the counter suffixes sorted by their UTF-8 bytes.
  static func readCounterSuffixes(_ dictionaryFiles: [String], _ ids: Set<String>) throws -> [String] {
    var suffixes = Set<BStr>()
    for filename in dictionaryFiles {
      // reading_correction.tsv is passed in the list of input files due to the
      // restriction of build system.
      if filename.contains("reading_correction.tsv") { continue }
      for cols in CodeGenUtil.parseColumnStream(try Py.readLines(filename, mode: .splitlines), numColumn: 5, delimiter: "\t") {
        guard cols.count == 5 else { throw DataGenError.invalidInput("\(filename): \(cols)") }
        let lid = cols[1], rid = cols[2]
        if lid == rid && ids.contains(lid) && ids.contains(rid) {
          suffixes.insert(BStr(cols[4]))
        }
      }
    }
    return suffixes.sorted().map(\.s)
  }
}
