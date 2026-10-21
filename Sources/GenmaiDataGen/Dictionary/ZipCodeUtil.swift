// Port of mozc/src/dictionary/zip_code_util.py (3.35.6354).
//
// Util module for Japanese postal(ZIP) code.

import Foundation
import GenmaiBase

public enum ZipCodeUtil {
  /// Decodes cp932 bytes as Python's `codecs.open(..., 'cp932', errors='replace')`
  /// (Foundation's kCFStringEncodingDOSJapanese is the same Microsoft code page).
  public static func decodeCp932(_ bytes: [UInt8]) throws -> String {
    let enc = String.Encoding(
      rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
    guard let s = String(bytes: bytes, encoding: enc) else {
      throw DataGenError.invalidInput("cannot decode cp932 input")
    }
    return s
  }

  /// Read CSV file.
  public static func readCSV(_ fileName: String) throws -> [[String]] {
    // Do not use csv reader module because it does not support unicode
    let text = try decodeCp932(try FileUtil.getContentBytes(fileName))
    // codecs.open iterates lines with str.splitlines(keepends=True).
    return Py.splitlines(text, keepends: true).map(getCells)
  }

  /// Get cells.
  static func getCells(_ line: String) -> [String] {
    // [A, B, C, ..] from "A","B ",C,..
    Py.split(Py.strip(line), ",").map { Py.strip(Py.strip($0, "\"")) }
  }

  /// Merge CSV.
  static func mergeCSV(_ csvLines: [[String]]) -> [[String]] {
    // When the flag says a zip code have no multiple entry while we can see
    // multiple line for that zip code, we have to merge them.
    var zipCount: [BStr: Int] = [:]
    var ret: [[String]] = []
    for entry in csvLines {
      let zipCode = BStr(entry[2])
      zipCount[zipCode, default: 0] += 1
      if !shouldMerge(zipCount, entry) {
        ret.append(entry)
      } else {
        ret[ret.count - 1][5] += entry[5]  // reading of '町域'
        ret[ret.count - 1][8] += entry[8]  // '町域'
      }
    }
    return ret
  }

  /// Return true if this entry should be merged to the previous entry.
  static func shouldMerge(_ zipCount: [BStr: Int], _ entry: [String]) -> Bool {
    let zipCode = BStr(entry[2])
    let flagMulti = entry[12] == "1"
    let shouldMerge = zipCount[zipCode]! > 1 && !flagMulti
    let shouldMergeSpecial = shouldMergeSpecial(entry)
    return shouldMerge || shouldMergeSpecial
  }

  /// Container class for special zip code entry to be merged.
  struct SpecialMergeZip {
    let zipCode: String
    let pref: String
    let city: String
    let towns: [String]
  }

  static let specialCases: [SpecialMergeZip] = [
    SpecialMergeZip(zipCode: "5900111", pref: "大阪府", city: "堺市中区", towns: ["三原台"]),
    SpecialMergeZip(zipCode: "8710046", pref: "大分県", city: "中津市", towns: ["金谷", "西堀端", "東堀端", "古金谷"]),
    SpecialMergeZip(zipCode: "9218046", pref: "石川県", city: "金沢市", towns: ["大桑町", "三小牛町"]),
  ]

  /// Return true for special cases to be merged.
  static func shouldMergeSpecial(_ entry: [String]) -> Bool {
    let zipCode = entry[2]
    let level1 = entry[6]
    let level2 = entry[7]
    let level3 = entry[8]
    for specialCase in specialCases {
      if bEq(zipCode, specialCase.zipCode) && bEq(level1, specialCase.pref) && bEq(level2, specialCase.city)
        && continuedLine(level3, specialCase.towns)
      {
        return true
      }
    }
    return false
  }

  /// Return true if this seems continued line.
  static func continuedLine(_ level3: String, _ towns: [String]) -> Bool {
    for town in towns where level3.utf8.starts(with: town.utf8) {
      return false
    }
    return true
  }

  static func bEq(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }
}
