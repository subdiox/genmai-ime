// Port of mozc/src/rewriter/gen_emoji_rewriter_data.py (3.35.6354).
//
// Converter of emoji data (data/emoji/emoji_data.tsv) to the token and string
// arrays used by EmojiRewriter.  Each line has 7 TAB-separated columns:
// code point, emoji, space separated readings, unicode name, Japanese name,
// descriptions, unicode emoji version.

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenEmojiRewriterData {
  // LINT.IfChange
  static let versionAll = [
    "E0.6", "E0.7", "E1.0", "E2.0", "E3.0", "E4.0", "E5.0", "E11.0", "E12.0", "E12.1", "E13.0", "E13.1",
    "E14.0", "E15.0", "E15.1", "E16.0", "E17.0", "E18.0",
  ]
  /// Dict for converting version string into enum index.
  static let versionToIndex: [String: Int] = Dictionary(
    uniqueKeysWithValues: versionAll.enumerated().map { ($1, $0) })

  /// Normalize full width ascii characters to half width characters
  /// (`[！-～]`, U+FF01 - U+FF5E).
  static func normalizeString(_ string: String) -> String {
    let offset: UInt32 = 0xFF21 - 0x41  // ord('Ａ') - ord('A')
    var out = String.UnicodeScalarView()
    for c in string.unicodeScalars {
      if (0xFF01...0xFF5E).contains(c.value) {
        out.append(Unicode.Scalar(UInt8(c.value - offset)))
      } else {
        out.append(c)
      }
    }
    return String(out)
  }

  struct EmojiData {
    let emoji: String
    let utf8Description: String
    let unicodeVersion: String
  }

  /// Parses emoji_data.tsv and builds the emoji_data_list and reading map.
  static func readEmojiTsv(_ lines: [String]) throws -> ([EmojiData], [BStr: [Int]]) {
    var emojiDataList: [EmojiData] = []
    var tokenDict: [BStr: [Int]] = [:]
    for columns in Py.parseColumnStream(Py.skipLineComment(lines), delimiter: "\t") {
      if columns.count != 7 {
        throw DataGenError.invalidInput("format error: \(columns.joined(separator: "\t"))")
      }
      // [0]: Emoji code point.
      let emoji = columns[1]
      if emoji.isEmpty { continue }
      let readings = columns[2]
      // [3]: Name defined in Unicode.  It is ignored in current implementation.
      let utf8Description = columns[4]
      // [5]: Descriptions. It is ignored in current implementation.
      let unicodeVersion = columns[6]

      let index = emojiDataList.count
      emojiDataList.append(EmojiData(emoji: emoji, utf8Description: utf8Description, unicodeVersion: unicodeVersion))

      // re.split(r'(?: |\xe3\x80\x80)+', readings.strip()): in a Python 3 str
      // pattern, '\xe3\x80\x80' is the three characters U+00E3 U+0080 U+0080,
      // not U+3000.
      for reading in Py.reSplitRuns(Py.strip(readings), [" ", "\u{E3}\u{80}\u{80}"]) where !reading.isEmpty {
        tokenDict[BStr(normalizeString(reading)), default: []].append(index)
      }
    }
    return (emojiDataList, tokenDict)
  }

  /// Output token and string arrays.
  static func outputData(_ emojiDataList: [EmojiData], _ tokenDict: [BStr: [Int]]) throws -> (
    tokens: [UInt8], strings: [UInt8]
  ) {
    let sortedTokenDict = tokenDict.sorted { $0.key < $1.key }
    var strings = Set<BStr>()
    strings.insert(BStr(""))
    for (reading, _) in sortedTokenDict { strings.insert(reading) }
    for d in emojiDataList {
      strings.insert(BStr(d.emoji))
      strings.insert(BStr(d.utf8Description))
    }
    let sortedStrings = strings.sorted()
    var index: [BStr: Int] = [:]
    for (i, s) in sortedStrings.enumerated() { index[s] = i }

    var f: [UInt8] = []
    let empty = try index.requiredValue(BStr(""))
    for (reading, valueList) in sortedTokenDict {
      let readingIndex = try index.requiredValue(reading)
      for valueIndex in valueList {
        let d = emojiDataList[valueIndex]
        guard let version = versionToIndex[d.unicodeVersion] else {
          throw DataGenError.invalidInput("unknown emoji version \(d.unicodeVersion)")
        }
        Py.packU32(readingIndex, into: &f)
        Py.packU32(try index.requiredValue(BStr(d.emoji)), into: &f)
        Py.packU32(version, into: &f)
        Py.packU32(try index.requiredValue(BStr(d.utf8Description)), into: &f)
        Py.packU32(empty, into: &f)
        Py.packU32(empty, into: &f)
        Py.packU32(empty, into: &f)
      }
    }
    return (f, SerializedStringArray.serializeToBuffer(sortedStrings.map(\.s)))
  }

  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    let (list, dict) = try readEmojiTsv(try Py.readLines(ctx.sources.emoji, mode: .splitlines))
    let out = try outputData(list, dict)
    return ["emoji_token": out.tokens, "emoji_string": out.strings]
  }
}
