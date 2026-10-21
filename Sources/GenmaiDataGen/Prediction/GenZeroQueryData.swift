// Port of mozc/src/prediction/gen_zero_query_data.py (3.35.6354).
//
// Generates zero query data file.
//
// The optional --output_tsv (zero_query_data.tsv, not part of the data set) is
// not reproduced: its line order follows a Python `set` iteration order, which
// depends on the per-process string hash seed.

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenZeroQueryData {
  typealias Dict = GenZeroQueryUtil.ZeroQueryDict
  typealias Entry = GenZeroQueryUtil.ZeroQueryEntry

  /// RE_SPLIT = r'(?: |\xe3\x80\x80|　)+'.  In a Python 3 str pattern
  /// '\xe3\x80\x80' is the three characters U+00E3 U+0080 U+0080.
  static let reSplit = [" ", "\u{E3}\u{80}\u{80}", "\u{3000}"]

  static func normalizeString(_ string: String) -> String {
    // unicodedata.normalize('NFKC', string)
    let normalized = string.precomposedStringWithCompatibilityMapping
    return normalized.replacingOccurrences(of: "~", with: "〜", options: .literal)
  }

  /// re.sub(r'^([^0-9]+)[0-9]+$', r'\1', string)
  static func removeTrailingNumber(_ string: String) -> String {
    if string.isEmpty { return "" }
    var scalars = Array(string.unicodeScalars)
    // Python '$' also matches before a trailing '\n'.
    var trailingNewline = false
    if scalars.last == "\n" {
      trailingNewline = true
      scalars.removeLast()
    }
    func isDigit(_ c: Unicode.Scalar) -> Bool { ("0"..."9").contains(c) }
    guard let firstDigit = scalars.firstIndex(where: isDigit), firstDigit > 0,
      scalars[firstDigit...].allSatisfy(isDigit)
    else {
      return string
    }
    var out = String.UnicodeScalarView(scalars[..<firstDigit])
    if trailingNewline { out.append("\n") }
    return String(out)
  }

  static func getReadingsFromDescription(_ description: String) -> [String] {
    if description.isEmpty { return [] }
    let normalized = normalizeString(description)
    // Description format example:
    //  - 電話１（プッシュホン）
    //  - ビル・建物
    // r'(?:\(|\)|/|\xE3\x83\xBB|・)+' ('\xE3\x83\xBB' = U+00E3 U+0083 U+00BB)
    return Py.reSplitRuns(normalized, ["(", ")", "/", "\u{E3}\u{83}\u{BB}", "・"]).map(removeTrailingNumber)
  }

  /// Reads emoji data from stream and returns zero query data.
  static func readEmojiTsv(_ lines: [String]) throws -> Dict {
    var dict = Dict()
    for columns in Py.parseColumnStream(Py.skipLineComment(lines), delimiter: "\t") {
      if columns.count != 7 {
        throw DataGenError.invalidInput("format error: \(columns.joined(separator: "\t"))")
      }
      let codepoints = columns[0]
      let emoji = columns[1]
      let readings = columns[2]
      let japaneseName = columns[4]
      let descriptions = columns[5]
      if codepoints.isEmpty { continue }

      var readingList: [String] = []
      for reading in Py.reSplitRuns(normalizeString(readings), reSplit) where !reading.isEmpty {
        readingList.append(reading)
      }
      readingList += getReadingsFromDescription(japaneseName)
      for description in Py.reSplitRuns(normalizeString(descriptions), reSplit) where !description.isEmpty {
        readingList += getReadingsFromDescription(description)
      }

      // `for description in set(reading_list)`: the set order only affects the
      // key insertion order, which does not reach the binary output (keys are
      // sorted there and the per-key lists are sorted below).
      var seen = Set<BStr>()
      for description in readingList where !description.isEmpty {
        let key = BStr(description)
        if !seen.insert(key).inserted { continue }
        dict[key, default: []].append(Entry(entryType: GenZeroQueryUtil.zeroQueryTypeEmoji, value: emoji))
      }
    }

    // Sort emoji for each reading.  (list.sort is stable.)
    for key in dict.keys {
      dict[key] = dict[key]!.sorted { BStr($0.value) < BStr($1.value) }
    }
    return dict
  }

  /// Reads zero query rule data from stream and returns zero query data.
  static func readZeroQueryRuleData(_ lines: [String]) -> Dict {
    var dict = Dict()
    for var line in lines {
      if line.hasPrefix("#") { continue }
      line = Py.rstrip(line, "\r\n")
      if line.isEmpty { continue }
      let tokens = Py.split(line, "\t")
      let key = BStr(tokens[0])
      for value in Py.split(tokens[1], ",") {
        dict[key, default: []].append(Entry(entryType: GenZeroQueryUtil.zeroQueryTypeNone, value: value))
      }
    }
    return dict
  }

  /// Reads emoticon data from stream and returns zero query data.
  static func readEmoticonTsv(_ lines: [String]) throws -> Dict {
    var dict = Dict()
    for columns in Py.parseColumnStream(Py.skipLineComment(lines), delimiter: "\t") {
      if columns.count != 3 {
        throw DataGenError.invalidInput("format error: \(columns.joined(separator: "\t"))")
      }
      let emoticon = columns[0]
      let readings = columns[2]
      for reading in Py.reSplitRuns(Py.strip(readings), reSplit) where !reading.isEmpty {
        dict[BStr(reading), default: []].append(
          Entry(entryType: GenZeroQueryUtil.zeroQueryTypeEmoticon, value: emoticon))
      }
    }
    return dict
  }

  /// Reads symbol data from stream and returns zero query data.
  static func readSymbolTsv(_ lines: [String]) -> Dict {
    var dict = Dict()
    for columns in Py.parseColumnStream(Py.skipLineComment(lines), delimiter: "\t") {
      if columns.count < 3 { continue }  // format error
      let symbol = columns[1]
      let readings = columns[2]
      let scalars = Array(symbol.unicodeScalars)
      if scalars.count != 1 { continue }
      let symbolCodePoint = scalars[0].value
      // Selects emoji symbols from symbol dictionary.
      // from "☀"(black sun with rays) to "❧"(rotated floral heart).
      if !(0x2600 <= symbolCodePoint && symbolCodePoint <= 0x2767) { continue }

      for reading in Py.reSplitRuns(Py.strip(readings), reSplit) where !reading.isEmpty {
        dict[BStr(reading), default: []].append(Entry(entryType: GenZeroQueryUtil.zeroQueryTypeNone, value: symbol))
      }
      if columns.count >= 4 && !columns[3].isEmpty {
        // description: "天気", etc.
        dict[BStr(columns[3]), default: []].append(
          Entry(entryType: GenZeroQueryUtil.zeroQueryTypeNone, value: symbol))
      }
      if columns.count >= 5 && !columns[4].isEmpty {
        // additional_description: "傘", etc.
        dict[BStr(columns[4]), default: []].append(
          Entry(entryType: GenZeroQueryUtil.zeroQueryTypeNone, value: symbol))
      }
    }
    return dict
  }

  /// Returns if the key is valid for zero query trigger.
  static func isValidKeyForZeroQuery(_ key: BStr) -> Bool {
    let isAscii = key.s.unicodeScalars.allSatisfy { $0.value < 128 }
    return !isAscii
  }

  /// Returns merged zero query data.
  static func mergeZeroQueryData(_ ruleDict: Dict, _ symbolDict: Dict, _ emojiDict: Dict, _ emoticonDict: Dict)
    -> Dict
  {
    var merged = Dict()
    for key in ruleDict.keys {
      merged[key, default: []] += ruleDict[key]!
    }
    for key in emojiDict.keys {
      if !isValidKeyForZeroQuery(key) { continue }
      // Skips aggressive emoji candidates.
      // Example: "顔", "天気" are category name and have many candidates.
      if emojiDict[key]!.count > 3 { continue }
      merged[key, default: []] += emojiDict[key]!
    }
    for key in emoticonDict.keys {
      if !isValidKeyForZeroQuery(key) { continue }
      // Merges only up to 3 emoticons.
      // Example: "にこにこ" have many candidates.
      merged[key, default: []] += emoticonDict[key]!.prefix(3)
    }
    for key in symbolDict.keys {
      if !isValidKeyForZeroQuery(key) { continue }
      // Skip aggressive emoji candidates.
      // Example: "きごう" is category name and has many candidates.
      if symbolDict[key]!.count > 3 { continue }
      merged[key, default: []] += symbolDict[key]!
    }
    return merged
  }

  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    let s = ctx.sources
    let rule = readZeroQueryRuleData(try Py.readLines(s.zeroQueryDef, mode: .splitlines))
    let symbol = readSymbolTsv(try Py.readLines(s.symbol, mode: .splitlines))
    let emoji = try readEmojiTsv(try Py.readLines(s.emoji, mode: .splitlines))
    let emoticon = try readEmoticonTsv(try Py.readLines(s.emoticonCategorized, mode: .splitlines))
    let merged = mergeZeroQueryData(rule, symbol, emoji, emoticon)
    let out = GenZeroQueryUtil.writeZeroQueryData(merged)
    return ["zero_query_token_array": out.tokens, "zero_query_string_array": out.strings]
  }
}
