// The extra dictionary of the extended data set (not part of Mozc): proper nouns that the Mozc OSS dictionary
// lacks, in the format of dictionary0*.txt (reading, left id, right id, cost, surface).
//
// Sources:
// - Japan Post's KEN_ALL.CSV (public domain; the same file as the zip code dictionary): municipality and town
//   names with their readings.
// - SudachiDict small_lex.csv / core_lex.csv (Apache License 2.0, Works Applications): its proper nouns with
//   readings: place names and other proper nouns of both, person names of small_lex only (core_lex adds ~180k
//   mostly rare given names and family names, which would flood the candidate lists of common readings).
//
// Only entries with a kanji whose (surface, reading) is not in the base dictionary are added, and no addresses
// (prefecture / municipality + more: Mozc composes those from their parts). Their POS ids are the
// Mozc proper noun ids; their cost is the 90th percentile of the base dictionary's costs for that id, so that they
// rank below most existing words of the same kind.

import Foundation
import GenmaiBase

public enum GenExtraDictionary {
  public struct Entry: Hashable, Sendable {
    public var reading: String
    public var posName: String
    public var surface: String
  }

  /// Mozc POS names of the entries (id.def without the trailing "*" fields).
  static let personName = "名詞,固有名詞,人名,一般,*,*,*"
  static let givenName = "名詞,固有名詞,人名,名,*,*,*"
  static let familyName = "名詞,固有名詞,人名,姓,*,*,*"
  static let placeName = "名詞,固有名詞,地域,一般,*,*,*"
  static let countryName = "名詞,固有名詞,地域,国,*,*,*"
  static let properNoun = "名詞,固有名詞,一般,*,*,*,*"

  static let maxSurfaceLength = 16
  static let maxReadingLength = 24

  /// The dictionary text: entries of `kenAll`, `sudachiSmall` and `sudachiCore` (csv files) not in
  /// `baseDictionaries`.
  public static func generate(
    idDef: String, baseDictionaries: [String], kenAll: String?, sudachiSmall: String?, sudachiCore: String?
  ) throws -> String {
    var ids: [String: Int] = [:]
    for line in Py.splitlines(try FileUtil.getContents(idDef)) {
      let p = line.split(separator: " ", maxSplits: 1).map(String.init)
      if p.count == 2, let id = Int(p[0]) { ids[p[1]] = id }
    }
    var existing = Set<String>()
    var costs: [Int: [Int]] = [:]
    for file in baseDictionaries {
      for line in try FileUtil.getContents(file).split(separator: "\n").map(String.init) {
        let p = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard p.count >= 5 else { continue }
        existing.insert(key(surface: p[4], reading: p[0]))
        if let id = Int(p[1]), let cost = Int(p[3]) { costs[id, default: []].append(cost) }
      }
    }
    var entries: [Entry] = []
    if let kenAll { entries += try placeNames(kenAll) }
    if let sudachiSmall { entries += try sudachiProperNouns(sudachiSmall, personNames: true) }
    if let sudachiCore { entries += try sudachiProperNouns(sudachiCore, personNames: false) }

    let percentile90 = costs.mapValues { c in c.sorted()[c.count * 9 / 10] }
    var seen = Set<String>()
    var lines: [String] = []
    for e in entries {
      guard let id = ids[e.posName] else { throw DataGenError.invalidInput("no id for \(e.posName)") }
      let k = key(surface: e.surface, reading: e.reading)
      guard !existing.contains(k), seen.insert(k).inserted else { continue }
      let cost = percentile90[id] ?? 8000
      lines.append("\(e.reading)\t\(id)\t\(id)\t\(cost)\t\(e.surface)")
    }
    return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
  }

  static func key(surface: String, reading: String) -> String {
    surface.precomposedStringWithCompatibilityMapping + "\t" + hiragana(reading)
  }

  /// NFKC (+ NFC: Foundation leaves half-width voiced kana decomposed, ﾍﾞ → ヘ + U+3099), katakana to hiragana.
  static func hiragana(_ s: String) -> String {
    var out = String.UnicodeScalarView()
    for c in s.precomposedStringWithCompatibilityMapping.precomposedStringWithCanonicalMapping.unicodeScalars {
      if c.value >= 0x30A1 && c.value <= 0x30F6, let h = Unicode.Scalar(c.value - 0x60) {
        out.append(h)
      } else {
        out.append(c)
      }
    }
    return String(out)
  }

  static func isKanji(_ c: Unicode.Scalar) -> Bool {
    (0x4E00...0x9FFF).contains(c.value) || (0x3400...0x4DBF).contains(c.value) || (0xF900...0xFAFF).contains(c.value)
      || c == "々" || c == "〆" || c == "ヶ"
  }

  static func isHiraganaReading(_ s: String) -> Bool {
    !s.isEmpty && s.unicodeScalars.allSatisfy { (0x3041...0x3096).contains($0.value) || $0 == "ー" }
  }

  /// A usable entry: a surface with a kanji, no ASCII or digits, not too long, not an address; a hiragana reading.
  static func entry(surface: String, reading: String, posName: String) -> Entry? {
    let s = surface.precomposedStringWithCompatibilityMapping
    let r = hiragana(reading)
    guard s.unicodeScalars.contains(where: isKanji), !s.unicodeScalars.contains(where: { $0.isASCII }),
      !s.unicodeScalars.contains(where: { $0.properties.numericType != nil }),
      s.count <= maxSurfaceLength, r.count <= maxReadingLength, isHiraganaReading(r),
      posName != placeName || !isAddress(s)
    else { return nil }
    return Entry(reading: r, posName: posName, surface: s)
  }

  /// A prefecture, county, city or ward followed by more ("静岡県磐田市", "紫波郡紫波町", "札幌市中央区",
  /// "磯子区杉田"), or a town / village name followed by a district ("川俣町上桜"; not "本町通").
  static func isAddress(_ s: String) -> Bool {
    s.contains(/^(北海道|東京都|京都府|大阪府|.{1,3}県)./) || s.contains(/[郡市区]./) || s.contains(/..[町村]../)
  }

  // MARK: - KEN_ALL.CSV

  /// Municipalities (column 8, reading 5) and towns (column 9, reading 6) of KEN_ALL.CSV; a municipality in a
  /// county ("上川郡比布町") also without the county ("比布町").
  static func placeNames(_ kenAll: String) throws -> [Entry] {
    var out: [Entry] = []
    for t in ZipCodeUtil.mergeCSV(try ZipCodeUtil.readCSV(kenAll)) where t.count > 8 {
      let cityReading = t[4]
      let city = t[7]
      out += entry(surface: city, reading: cityReading, posName: placeName).map { [$0] } ?? []
      if let gun = city.range(of: "郡"), let gunReading = cityReading.range(of: "ｸﾞﾝ"),
        !city[gun.upperBound...].isEmpty
      {
        out +=
          entry(
            surface: String(city[gun.upperBound...]), reading: String(cityReading[gunReading.upperBound...]),
            posName: placeName
          ).map { [$0] } ?? []
      }
      if let town = townName(t[8], reading: t[5]) {
        out += entry(surface: town.surface, reading: town.reading, posName: placeName).map { [$0] } ?? []
      }
    }
    return out
  }

  /// The town name without notes: nil for "以下に掲載がない場合", "…の次に番地がくる場合", "…一円" and lists;
  /// parenthesized parts are removed from both the name and the reading.
  static func townName(_ town: String, reading: String) -> (surface: String, reading: String)? {
    let surface = town.replacing(/（.*?）/, with: "")
    let r = reading.replacing(/\(.*?\)/, with: "")
    if surface.contains("以下に掲載がない場合") || surface.contains("番地がくる場合") || surface.hasSuffix("一円")
      || surface.contains("、") || surface.contains("～") || surface.contains("「")
    {
      return nil
    }
    guard !surface.isEmpty, !surface.contains("（"), !r.contains("(") else { return nil }
    return (surface, r)
  }

  // MARK: - SudachiDict

  /// Proper nouns of a SudachiDict lexicon csv (columns: 0 index form, 4 headword, 5-10 POS, 11 reading).
  static func sudachiProperNouns(_ file: String, personNames: Bool) throws -> [Entry] {
    var out: [Entry] = []
    // most lines are not proper nouns: check the bytes before splitting the line into fields
    let marker = Array(",名詞,固有名詞,".utf8)
    for bytes in try FileUtil.getContentBytes(file).split(separator: UInt8(ascii: "\n")) {
      guard bytes.firstRange(of: marker) != nil, let line = String(validating: bytes, as: UTF8.self) else { continue }
      let p = csvFields(line)
      guard p.count > 11, p[5] == "名詞", p[6] == "固有名詞" else { continue }
      let posName: String
      switch (p[7], p[8]) {
      case ("人名", "姓") where personNames: posName = familyName
      case ("人名", "名") where personNames: posName = givenName
      case ("人名", _) where personNames: posName = personName
      case ("地名", "国"): posName = countryName
      case ("地名", _): posName = placeName
      case ("一般", _): posName = properNoun
      default: continue
      }
      let surface = p[4].isEmpty ? p[0] : p[4]
      if let e = entry(surface: surface, reading: p[11], posName: posName) { out.append(e) }
    }
    return out
  }

  /// The fields of a csv line (double quotes group fields with commas; "" inside them is a quote).
  static func csvFields(_ line: String) -> [String] {
    guard line.contains("\"") else {
      return line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    }
    let c = Array(line)
    var fields: [String] = []
    var cur = ""
    var quoted = false
    var i = 0
    while i < c.count {
      if quoted {
        if c[i] == "\"" {
          if i + 1 < c.count && c[i + 1] == "\"" {
            cur.append("\"")
            i += 1
          } else {
            quoted = false
          }
        } else {
          cur.append(c[i])
        }
      } else if c[i] == "\"" {
        quoted = true
      } else if c[i] == "," {
        fields.append(cur)
        cur = ""
      } else {
        cur.append(c[i])
      }
      i += 1
    }
    fields.append(cur)
    return fields
  }
}
