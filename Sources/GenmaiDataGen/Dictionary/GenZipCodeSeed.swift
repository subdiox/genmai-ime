// Port of mozc/src/dictionary/gen_zip_code_seed.py (3.35.6354).
//
// Zip code dictionary generator.  Input files are shift-jis (cp932) csv;
// output lines are utf-8.
//
//  Zip code sample input line:
//  01101,"060  ","0600007","ﾎｯｶｲﾄﾞｳ",
//  "ｻｯﾎﾟﾛｼﾁｭｳｵｳｸ","ｷﾀ7ｼﾞｮｳﾆｼ","北海道",
//  "札幌市中央区","北七条西",0
//
//  Jigyosyo zip code sample input line:
//  01101,"ｻﾂﾎﾟﾛｼﾁﾕｳｵｳｸﾔｸｼﾖ",
//  "札幌市中央区役所","北海道","札幌市中央区",
//  "南三条西","１１丁目","0608612","060  ","札幌",0,0,0

import Foundation
import GenmaiBase

public enum GenZipCodeSeed {
  static let zipCodeLabel = "ZIP_CODE"
  static let zipCodeCost = 7000

  /// Container class for zip code entry.
  struct ZipEntry {
    let zipCode: String
    let address: String

    /// Get formatted zip code.
    func formatZip(_ zipCode: String) -> String {
      // XXX-XXXX format (zip_code[0:3], zip_code[3:])
      let scalars = Array(zipCode.unicodeScalars)
      var head = String.UnicodeScalarView()
      var tail = String.UnicodeScalarView()
      head.append(contentsOf: scalars.prefix(3))
      tail.append(contentsOf: scalars.dropFirst(3))
      return String(head) + "-" + String(tail)
    }

    /// Return the output line.
    func getLine() -> String {
      let zip = formatZip(zipCode)
      // unicodedata.normalize('NFKC', ...)
      let address = self.address.precomposedStringWithCompatibilityMapping
      return [zip, "0", "0", String(zipCodeCost), address, zipCodeLabel].joined(separator: "\t")
    }
  }

  /// Process zip code csv.
  static func processZipCodeCSV(_ fileName: String) throws -> [String] {
    let csvLines = try ZipCodeUtil.readCSV(fileName)
    let mergedCsvLines = ZipCodeUtil.mergeCSV(csvLines)
    var output: [String] = []
    let patterns = TownNamePatterns()
    for tokens in mergedCsvLines {
      for entry in try readZipCodeEntries(tokens[2], tokens[6], tokens[7], tokens[8], patterns) {
        output.append(entry.getLine())
      }
    }
    return output
  }

  /// Process jigyosyo csv.
  static func processJigyosyoCSV(_ fileName: String) throws -> [String] {
    try ZipCodeUtil.readCSV(fileName).map { tokens in
      readJigyosyoEntry(tokens[7], tokens[3], tokens[4], tokens[5], tokens[2]).getLine()
    }
  }

  /// Read zip code entries.
  static func readZipCodeEntries(
    _ zipCode: String, _ level1: String, _ level2: String, _ level3: String,
    _ patterns: TownNamePatterns = TownNamePatterns()
  ) throws -> [ZipEntry] {
    try parseTownName(level3, patterns).map { ZipEntry(zipCode: zipCode, address: level1 + level2 + $0) }
  }

  /// Read jigyosyo entry.
  static func readJigyosyoEntry(
    _ zipCode: String, _ level1: String, _ level2: String, _ level3: String, _ name: String
  ) -> ZipEntry {
    ZipEntry(zipCode: zipCode, address: level1 + level2 + level3 + " " + name)
  }

  /// The Python `re` patterns of parse_town_name.  Python matches code points
  /// and its Unicode \d / \D are \p{Nd} / \P{Nd}, as in Swift `Regex` with
  /// Unicode scalar semantics.  (`Regex` is not `Sendable`: made once per CSV
  /// file and passed down.)
  struct TownNamePatterns {
    let paren = /（.*）/.matchingSemantics(.unicodeScalar)
    let chiwari = /(\D*?)第?\d+地割.*/.matchingSemantics(.unicodeScalar)
    let chou = /(.*町)?(.*)/.matchingSemantics(.unicodeScalar)
  }

  static func contains(_ s: String, _ sub: String) -> Bool {
    let a = Array(s.utf8)
    let b = Array(sub.utf8)
    if b.isEmpty { return true }
    if a.count < b.count { return false }
    for i in 0...(a.count - b.count) where a[i] == b[0] && a[i..<(i + b.count)].elementsEqual(b) {
      return true
    }
    return false
  }

  /// Parse town name.
  static func parseTownName(_ level3In: String, _ patterns: TownNamePatterns = TownNamePatterns()) throws
    -> [String]
  {
    var level3 = level3In
    // Skip some exceptional cases
    // 中津市の次に番地がくる場合 : 871-0099 大分県中津市
    // 小菅村の次に1~663番地がくる場合 : 409-0142 山梨県北都留郡小菅村
    // 小菅村の次に664番地以降がくる場合 : 409-0211 山梨県北都留郡小菅村
    // 渡名喜村一円 : 901-3601 沖縄県島尻郡渡名喜村
    // 琴平町の次に４２７番地以降がくる場合（川西） : 766-0001 香川県仲多度郡琴平町
    // 琴平町の次に１～４２６番地がくる場合（川東） : 766-0002 香川県仲多度郡琴平町
    if contains(level3, "以下に掲載がない場合") || contains(level3, "がくる場合")
      || level3.utf8.reversed().starts(with: "村一円".utf8.reversed())
    {
      return [""]
    }

    guard canParseAddress(level3) else {
      throw DataGenError.invalidInput("failed to be merged \(level3)")
    }

    // We ignore additional information here.
    // re.sub(r'（.*）', '', level3)
    level3 = level3.replacing(patterns.paren, with: "")

    // For 地割, we have these cases.
    //  XX1地割
    //  XX1地割、XX2地割、
    //  XX1地割〜XX2地割、
    //  XX第1地割
    //  XX第1地割、XX第2地割、
    //  XX第1地割〜XX第2地割、
    // We simply use XX for them.
    // re.match: anchored at the start.
    if let m = level3.prefixMatch(of: patterns.chiwari) {
      return [String(m.1)]
    }

    // For "、"
    //  XX町YY、ZZ
    //   -> XX町YY and (XX町)ZZ
    //  YY、ZZ
    //   -> YY and ZZ
    if let m = level3.prefixMatch(of: patterns.chou) {
      let chou = m.1.map(String.init) ?? ""
      let rests = String(m.2)
      return Py.split(rests, "、").map { chou + $0 }
    }

    return [level3]
  }

  /// Return true for valid address.
  static func canParseAddress(_ address: String) -> Bool {
    !contains(address, "（") || contains(address, "）")
  }

  /// Returns the zip_code.tsv contents for the given csv files (nil: not given).
  public static func generate(zipCode: String?, jigyosyo: String?) throws -> String {
    var lines: [String] = []
    if let zipCode { lines += try processZipCodeCSV(zipCode) }
    if let jigyosyo { lines += try processJigyosyoCSV(jigyosyo) }
    // with open(options.output, 'w') ...: if lines: write('\n'.join(lines) + '\n')
    return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
  }
}
