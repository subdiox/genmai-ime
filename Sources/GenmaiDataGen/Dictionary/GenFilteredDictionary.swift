// Port of mozc/src/dictionary/gen_filtered_dictionary.py (3.35.6354).
//
// A tool to remove specified words from dictionary files.
//
// ### Format of dictionary_filter.tsv
//
// | key      | value    |
// | :------: | :------: |
// | あるぱか | 或るパカ |
//
// * `key` and `value` are the regexp patterns of words to be removed.
// * Each line is extended to the following regexp pattern:
//   + `'^{key}\t\\d+\t\\d+\t\\d+\t{value}(\t.*)?\n$'`

import Foundation
import GenmaiBase

public enum GenFilteredDictionary {
  /// Class for dictionary0*.txt.
  final class Dictionary {
    var lines: [String] = []
    var filters: [NSRegularExpression] = []

    func loadFiles(_ dictionaryTxts: [String], _ filterTsv: String) throws {
      try loadFilter(filterTsv)
      for file in dictionaryTxts {
        try loadDict(file)
      }
    }

    private func loadFilter(_ file: String) throws {
      for line in try Py.readLines(file) {
        if line.hasPrefix("#") { continue }
        let kv = Py.split(Py.chompLF(line), "\t")
        guard kv.count == 2 else { throw DataGenError.invalidInput("filter: \(line)") }
        // re.fullmatch(pattern, line): anchored at both ends (\A ... \z).
        // Python's '.' matches everything but '\n' (ICU's also excludes \r,
        // U+2028, ...); a line holds at most one '\n', at its end, so dot-all
        // ((?s)) gives the same matches.
        let pattern = kv[0] + "\t\\d+\t\\d+\t\\d+\t" + kv[1] + "(\t.*)?\n"
        filters.append(try NSRegularExpression(pattern: "(?s)\\A(?:" + pattern + ")\\z"))
      }
    }

    /// Parses the file and set values to data and entry_set.
    private func loadDict(_ file: String) throws {
      for line in try Py.readLines(file) {
        if checkFilter(line) { continue }
        lines.append(line)
      }
    }

    private func checkFilter(_ line: String) -> Bool {
      let range = NSRange(location: 0, length: (line as NSString).length)
      for pattern in filters where pattern.firstMatch(in: line, options: [], range: range) != nil {
        return true
      }
      return false
    }

    func contents() -> [UInt8] {
      var out: [UInt8] = []
      for line in lines { out.append(contentsOf: line.utf8) }
      return out
    }
  }

  /// Returns the filtered dictionary (contents of the --output file).
  public static func generate(filterTsv: String, dictionaryTxts: [String]) throws -> [UInt8] {
    let dictionary = Dictionary()
    try dictionary.loadFiles(dictionaryTxts, filterTsv)
    return dictionary.contents()
  }
}
