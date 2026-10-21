// Port of mozc/src/rewriter/gen_symbol_rewriter_dictionary_main.cc
// (3.35.6354).
//
// Symbol dictionary generator: reads data/symbol/symbol.tsv, the sorting map
// (data/rules/sorting_map.tsv) and the ordering rule
// (data/symbol/ordering_rule.txt), writes the dictionary in Mozc's text format
// and compiles it with SerializedDictionary.  (The C++ writes the text to a
// temporary file; here it stays in memory.)

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenSymbolRewriterDictionaryMain {
  typealias DictionaryGenerator = RewriterDictionaryGenerator.DictionaryGenerator
  typealias Token = RewriterDictionaryGenerator.Token

  /// A 16-bit bitmap of JIS X 0208 and allow-listed characters.  The bitmap
  /// is intended to be compatible with Util::IsJisX0208(), which we used to
  /// have.
  static let kJisX0208OrAllowListedMap: [Bool] = {
    var map = [Bool](repeating: false, count: 0x10000)
    for codepoint in kJisX0208Chars {
      map[Int(codepoint)] = true
    }
    // The following characters need to be allow-listed to be fully compatible
    // with the legacy Util::IsJisX0208() behavior.

    // All 7-bit ASCII characters:
    for codepoint in 0x0000...0x007F { map[codepoint] = true }
    // HALFWIDTH characters: U+FF61 "｡" ... U+FF9F "ﾟ"
    for codepoint in 0xFF61...0xFF9F { map[codepoint] = true }
    // Misc characters:
    map[0x00A5] = true  // "¥" YEN SIGN
    map[0x203E] = true  // "‾" OVERLINE
    map[0x2225] = true  // "∥" PARALLEL TO
    map[0xFF0D] = true  // "－" FULLWIDTH HYPHEN MINUS
    map[0xFF3C] = true  // "＼" FULLWIDTH REVERSE SOLIDS
    map[0xFF5E] = true  // "～" FULLWIDTH TILDE
    map[0xFFE0] = true  // "￥" FULLWIDTH CENT SIGN
    map[0xFFE1] = true  // "￡" FULLWIDTH POUND SIGN
    map[0xFFE2] = true  // "￢" FULLWIDTH NOT SIGN
    return map
  }()

  /// A re-implementation of Util::IsJisX0208(), which we used to have.
  static func isJisX0208OrAllowListed(_ str: String) -> Bool {
    for c in str.unicodeScalars {
      // Char16BitMap::test takes a char16_t: the char32_t is truncated.
      if !kJisX0208OrAllowListedMap[Int(UInt16(truncatingIfNeeded: c.value))] {
        return false
      }
    }
    return true
  }

  typealias SortingKeyMap = [BStr: UInt16]

  /// absl::SimpleHexAtoi for uint32_t (optional whitespace and 0x prefix).
  static func simpleHexAtoi(_ s: String) -> UInt32? {
    var t = Substring(s.trimmingCharacters(in: .whitespaces))
    if t.hasPrefix("0x") || t.hasPrefix("0X") { t = t.dropFirst(2) }
    if t.isEmpty { return nil }
    return UInt32(t, radix: 16)
  }

  static func lines(_ path: String) throws -> [String] {
    let ifs = InputFileStream(path)
    guard !ifs.fail else { throw DataGenError.invalidInput("cannot open \(path)") }
    var result: [String] = []
    while let line = ifs.getline() { result.append(line) }
    return result
  }

  static func createSortingKeyMap(_ autoFile: String, _ ruleFile: String) throws -> SortingKeyMap {
    var sortingKeys: SortingKeyMap = [:]
    var sortingKey = 0
    for line in try lines(ruleFile) {
      if line.isEmpty
        // Support comment and single '#'
        || (line.utf8.first == UInt8(ascii: "#") && line.utf8.count > 1)
      {
        continue
      }
      // emplace() keeps an existing entry.
      if sortingKeys[BStr(line)] == nil { sortingKeys[BStr(line)] = UInt16(truncatingIfNeeded: sortingKey) }
      sortingKey += 1
    }

    for line in try lines(autoFile) {
      if line.isEmpty || line.utf8.first == UInt8(ascii: "#") {
        continue
      }
      let fields = line.utf8.split(omittingEmptySubsequences: true) {
        $0 == UInt8(ascii: "\t") || $0 == UInt8(ascii: " ")
      }.map { String(decoding: $0, as: UTF8.self) }
      guard fields.count >= 2, let codepoint = simpleHexAtoi(fields[0]) else {
        throw DataGenError.invalidInput("sorting map: \(line)")
      }
      let utf8 = BStr(Util.codepointToUtf8(codepoint))
      if sortingKeys[utf8] != nil {
        // ordered by rule
        continue
      }
      sortingKeys[utf8] = UInt16(truncatingIfNeeded: sortingKey)
      sortingKey += 1
    }
    return sortingKeys
  }

  static func addSymbolToDictionary(
    _ pos: String, _ value: String, _ keys: [String], _ description: String, _ additionalDescription: String,
    _ sortingKeys: SortingKeyMap, _ dictionary: DictionaryGenerator
  ) {
    // use first char of value as sorting key.
    let firstValue = String(Util.utf8SubString(value, 0, 1))
    var sortingKey: UInt16 = 0
    if let k = sortingKeys[BStr(firstValue)] {
      sortingKey = k
    } else {
      // If the character is platform-dependent, put the character at the last.
      // Probably we should revisit the logic here. There is no strong rationale.
      if !isJisX0208OrAllowListed(value) {
        sortingKey = UInt16.max
      }
    }

    // flat_hash_set: the iteration order does not matter (the generator keeps
    // a sorted set).
    var normalizedKeys: [BStr] = []
    var seen = Set<BStr>()
    for key in keys {
      var normalizedKey = Japanese.fullWidthAsciiToHalfWidthAscii(key)
      Util.lowerString(&normalizedKey)
      if seen.insert(BStr(normalizedKey)).inserted { normalizedKeys.append(BStr(normalizedKey)) }
    }

    for key in normalizedKeys {
      dictionary.addToken(
        Token(
          sortingKey: Int(sortingKey), key: key.s, value: value, pos: pos, description: description,
          additionalDescription: additionalDescription))
    }
  }

  static func makeDictionary(
    _ symbolDictionaryFile: String, _ sortingMapFile: String, _ orderingRuleFile: String,
    _ dictionary: DictionaryGenerator
  ) throws {
    var seen = Set<BStr>()
    let sortingKeys = try createSortingKeyMap(sortingMapFile, orderingRuleFile)

    var all = try lines(symbolDictionaryFile)
    guard !all.isEmpty else { throw DataGenError.invalidInput("empty \(symbolDictionaryFile)") }
    all.removeFirst()  // get first line

    for line in all {
      // Format:
      // POS <tab> value <tab> readings(space delimited) <tab>
      // description <tab> memo
      let fields = line.utf8.split(separator: UInt8(ascii: "\t"), omittingEmptySubsequences: false).map {
        String(decoding: $0, as: UTF8.self)
      }
      if fields.count < 3 || (fields[1].isEmpty && fields[2].isEmpty) {
        continue  // invalid format. skip line
      }
      var pos = fields[0]
      Util.upperString(&pos)
      let value = fields[1]
      if !seen.insert(BStr(value)).inserted {
        continue  // already inserted
      }

      var keys: [String] = []
      for key in fields[2].utf8.split(separator: UInt8(ascii: " "), omittingEmptySubsequences: true) {
        // Full-width space
        keys.append(String(decoding: key, as: UTF8.self).replacingOccurrences(of: "　", with: " ", options: .literal))
      }
      let description = fields.count > 3 ? fields[3] : ""
      let additionalDescription = fields.count > 4 ? fields[4] : ""
      addSymbolToDictionary(pos, value, keys, description, additionalDescription, sortingKeys, dictionary)
    }
    // Add space as a symbol
    addSymbolToDictionary("記号", " ", [" "], "空白", "", sortingKeys, dictionary)
  }

  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    // User pos manager data for build tools has no magic number.
    let dataManager = try DataManager.createUserPosManagerDataFromArray(
      DataView(copying: ctx.userPosManagerData), magic: [])
    let (tokenArray, stringArray) = dataManager.getUserPosData()
    let userPos = UserPos(tokenArray, stringArray)
    let posMatcher = PosMatcher(dataManager.getPosMatcherData())

    let dictionary = DictionaryGenerator(userPos, posMatcher)
    let s = ctx.sources
    try makeDictionary(s.symbol, s.sortingMap, s.symbolOrderingRule, dictionary)
    let text = try dictionary.output()
    let (tokens, strings) = SerializedDictionary.compile(InputFileStream(bytes: text))
    return ["symbol_token": tokens, "symbol_string": strings]
  }
}
