// Port of mozc/src/rewriter/gen_single_kanji_rewriter_data.py (3.35.6354).
//
// Single kanji dictionary generator.

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenSingleKanjiRewriterData {
  /// Parses single kanji dictionary data from stream.
  static func readSingleKanji(_ lines: [String]) -> [[String]] {
    var outputs = Py.parseColumnStream(Py.skipLineComment(lines), numColumn: 2)
    // For binary search by |key|, sort outputs here.  (list.sort is stable.)
    outputs.sort { BStr($0[0]) < BStr($1[0]) }
    return outputs
  }

  /// Parses variant data from stream.
  static func readVariant(_ lines: [String]) -> (types: [String], items: [(String, String, Int)]) {
    var variantTypes: [String] = []
    var variantItems: [(String, String, Int)] = []
    for tokens in Py.parseColumnStream(Py.skipLineComment(lines)) {
      if tokens.count == 1 {
        variantTypes.append(tokens[0])
      } else if tokens.count == 2 && !variantTypes.isEmpty {
        variantItems.append((tokens[0], tokens[1], variantTypes.count - 1))
      }
    }
    // For binary search by |target|, sort variant items here.
    variantItems.sort { BStr($0.0) < BStr($1.0) }
    return (variantTypes, variantItems)
  }

  /// Writes single kanji list for readings.  The token output is an array of
  /// uint32s, where array[2 * i] and array[2 * i + 1] are the indices of key
  /// and value in the string array.  See rewriter/single_kanji_rewriter.cc.
  static func writeSingleKanji(_ dic: [[String]]) -> (tokens: [UInt8], strings: [UInt8]) {
    var tokens: [UInt8] = []
    var strings: [String] = []
    for (index, kv) in dic.enumerated() {
      Py.packU32(2 * index, into: &tokens)
      Py.packU32(2 * index + 1, into: &tokens)
      strings.append(kv[0])
      strings.append(kv[1])
    }
    return (tokens, SerializedStringArray.serializeToBuffer(strings))
  }

  /// Writes single kanji variants info.  The token output is an array of
  /// uint32s, where array[3 * i], array[3 * i + 1] and array[3 * i + 2] are
  /// the index of target, index of original, and variant type ID.
  static func writeVariantInfo(_ info: (types: [String], items: [(String, String, Int)]))
    -> (types: [UInt8], tokens: [UInt8], strings: [UInt8])
  {
    var tokens: [UInt8] = []
    var strings: [String] = []
    for (index, item) in info.items.enumerated() {
      Py.packU32(2 * index, into: &tokens)
      Py.packU32(2 * index + 1, into: &tokens)
      Py.packU32(item.2, into: &tokens)
      strings.append(item.0)
      strings.append(item.1)
    }
    return (
      SerializedStringArray.serializeToBuffer(info.types), tokens, SerializedStringArray.serializeToBuffer(strings)
    )
  }

  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    let singleKanji = readSingleKanji(try Py.readLines(ctx.sources.singleKanji, mode: .splitlines))
    let variantInfo = readVariant(try Py.readLines(ctx.sources.variantRule, mode: .splitlines))
    let sk = writeSingleKanji(singleKanji)
    let v = writeVariantInfo(variantInfo)
    return [
      "single_kanji_token": sk.tokens,
      "single_kanji_string": sk.strings,
      "single_kanji_variant_type": v.types,
      "single_kanji_variant_token": v.tokens,
      "single_kanji_variant_string": v.strings,
    ]
  }
}
