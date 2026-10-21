// Port of mozc/src/dictionary/gen_aux_dictionary.py (3.35.6354).
//
// A tool to generate aux_dictionary.txt from aux_dictionary.tsv.
//
// * Create a dictionary with entries of key and value in the TSV file.
//   + Fields: [key, value, base_key, base_value, cost_offset]
// * lid, rid and cost are copied from entries of base_key and base_value.
// * cost_offset adjusts the cost copied from the base entry. If the cost_offset
//   is -1, the new entry is ranked higher than the base entry.
//
// Then entries of the words TSVs (data/dictionary_manual/*.tsv) are appended.

import Foundation
import GenmaiBase

public enum GenAuxDictionary {
  /// Class for an entry in the dictionary.
  struct Entry {
    let key: String
    let value: String
    let lid: String
    let rid: String
    let cost: Int

    func entryKey() -> BStr { BStr([lid, rid, key, value].joined(separator: "\t")) }

    static func parse(_ line: String) throws -> Entry {
      // key, lid, rid, cost, value, *_ = line.rstrip().split('\t')
      let f = Py.rstrip(line).utf8.split(separator: 0x09, omittingEmptySubsequences: false).map { String($0)! }
      guard f.count >= 5, let cost = Py.int(f[3]) else {
        throw DataGenError.invalidInput("dictionary line: \(line)")
      }
      return Entry(key: f[0], value: f[4], lid: f[1], rid: f[2], cost: cost)
    }
  }

  /// Class for a list of entries.  (Only the costs are needed: AtRatio's
  /// result is only used for its cost, and Python's sort by cost is stable.)
  struct EntryList {
    var costs: [Int] = []
    var sorted = false

    mutating func add(_ entry: Entry) {
      costs.append(entry.cost)
      sorted = false
    }

    mutating func sort() {
      if sorted { return }
      costs.sort()
      sorted = true
    }

    mutating func costAtRatio(_ ratioIn: Double) -> Int {
      sort()
      let ratio = max(0, min(ratioIn, 1.0))
      let index = Int(Double(max(costs.count - 1, 0)) * ratio)
      return costs[index]
    }
  }

  /// Class for pos ids.
  struct PosIds {
    var ids: [BStr: String] = [:]  // "pos_name" -> "pos_id"
    // Keys are subset of data/rules/user_pos.def
    static let posAlias: [(String, String)] = [
      ("名詞", "名詞,一般,*,*,*,*,*"),
      ("固有名詞", "名詞,固有名詞,一般,*,*,*,*"),
      ("人名", "名詞,固有名詞,人名,一般,*,*,*"),
      ("姓", "名詞,固有名詞,人名,姓,*,*,*"),
      ("名", "名詞,固有名詞,人名,名,*,*,*"),
      ("組織", "名詞,固有名詞,組織,*,*,*,*"),
      ("地名", "名詞,固有名詞,地域,一般,*,*,*"),
      ("名詞サ変", "名詞,サ変接続,*,*,*,*,*"),
      ("名詞形動", "名詞,形容動詞語幹,*,*,*,*,*"),
      ("副詞", "副詞,一般,*,*,*,*,*"),
      ("連体詞", "連体詞,*,*,*,*,*,*"),
      ("接続詞", "接続詞,*,*,*,*,*,*"),
      ("感動詞", "感動詞,*,*,*,*,*,*"),
      ("接頭語", "接頭詞,名詞接続,*,*,*,*,*"),
      ("助数詞", "名詞,接尾,助数詞,*,*,*,*"),
      ("接尾一般", "名詞,接尾,一般,*,*,*,*"),
      ("接尾人名", "名詞,接尾,人名,*,*,*,*"),
      ("接尾地名", "名詞,接尾,地域,*,*,*,*"),
    ]

    mutating func parseFile(_ idDef: String) throws {
      for line in try Py.readLines(idDef) {
        let f = Py.split(Py.rstrip(line), " ")
        guard f.count == 2 else { throw DataGenError.invalidInput("id.def line: \(line)") }
        ids[BStr(f[1])] = f[0]
      }
      for (alias, name) in PosIds.posAlias {
        guard let posId = ids[BStr(name)] else { throw DataGenError.invalidInput("id.def: no \(name)") }
        ids[BStr(alias)] = posId
      }
    }

    func getId(_ posName: String) -> String { ids[BStr(posName)] ?? "" }
  }

  /// Class for dictionary0*.txt.
  final class Dictionary {
    var entrySet = Set<BStr>()
    var data: [BStr: [Entry]] = [:]  // "<key>\t<value>" -> [entry1, entry2, ...]
    var posEntryMap: [BStr: EntryList] = [:]  // "<lid>\t<rid>" -> EntryList

    func parse(_ dictionaryTxts: [String]) throws {
      for file in dictionaryTxts {
        try parseFile(file)
      }
    }

    /// Parses the file and set values to data and entry_set.
    private func parseFile(_ file: String) throws {
      for line in try Py.readLines(file) {
        let entry = try Entry.parse(line)
        // Update data
        data[BStr(entry.key + "\t" + entry.value), default: []].append(entry)
        // Update entry_set
        entrySet.insert(entry.entryKey())
        // Update pos_map
        posEntryMap[BStr(entry.lid + "\t" + entry.rid), default: EntryList()].add(entry)
      }
    }

    func exists(_ key: String, _ value: String, _ lid: String, _ rid: String) -> Bool {
      entrySet.contains(BStr([lid, rid, key, value].joined(separator: "\t")))
    }

    func getDataList(_ key: String, _ value: String) -> [Entry]? {
      data[BStr(key + "\t" + value)]
    }

    func getCost(_ posId: String, _ ratio: Double) throws -> Int {
      let posKey = BStr(posId + "\t" + posId)
      guard posEntryMap[posKey] != nil else { throw DataGenError.invalidInput("no entry with POS \(posId)") }
      return posEntryMap[posKey]!.costAtRatio(ratio)
    }
  }

  /// Class for aux_dictionary.tsv.
  final class AuxDictionary {
    let dictionary: Dictionary
    var auxList: [[String]] = []
    var auxSet = Set<BStr>()

    init(_ dictionary: Dictionary) { self.dictionary = dictionary }

    /// Parses the file and update aux_list.
    func parse(_ auxTsv: String, strict: Bool) throws {
      for line in try Py.readLines(auxTsv) {
        if line.hasPrefix("#") { continue }
        let f = Py.split(Py.rstrip(line), "\t")
        guard f.count == 5 else { throw DataGenError.invalidInput("aux_dictionary.tsv line: \(line)") }
        let (key, value, baseKey, baseValue, costOffset) = (f[0], f[1], f[2], f[3], f[4])
        guard let dataList = dictionary.getDataList(baseKey, baseValue), !dataList.isEmpty else {
          let message = "\(baseKey) and \(baseValue) are not in the dictionary"
          if strict { throw DataGenError.invalidInput("Error: " + message) }
          FileHandle.standardError.write(Data("Warning: \(message)\n".utf8))
          continue
        }
        for entry in dataList {
          if dictionary.exists(key, value, entry.lid, entry.rid) {
            // Not overwrite the existing entry.
            continue
          }
          guard let offset = Py.int(costOffset) else { throw DataGenError.invalidInput("cost offset: \(line)") }
          let cost = entry.cost + offset
          auxList.append([key, entry.lid, entry.rid, String(cost), value])
          auxSet.insert(BStr([entry.lid, entry.rid, key, value].joined(separator: "\t")))
        }
      }
    }

    func exists(_ key: String, _ value: String, _ lid: String, _ rid: String) -> Bool {
      auxSet.contains(BStr([lid, rid, key, value].joined(separator: "\t")))
    }

    func contents() -> String {
      auxList.map { $0.joined(separator: "\t") + "\n" }.joined()
    }
  }

  /// Class for words.tsv.
  final class WordsDictionary {
    let dictionary: Dictionary
    let aux: AuxDictionary
    var words: [[String]] = []

    init(_ dictionary: Dictionary, _ aux: AuxDictionary) {
      self.dictionary = dictionary
      self.aux = aux
    }

    /// Parses the file and update aux_list.
    func parse(_ wordsTsv: String, _ idDef: String, ratio: Double = 0.5) throws {
      var posIds = PosIds()
      try posIds.parseFile(idDef)

      for line in try Py.readLines(wordsTsv) {
        if line.hasPrefix("#") || Py.rstrip(line).isEmpty { continue }
        let items = Py.split(Py.rstrip(line), "\t")
        guard items.count == 3 else { throw DataGenError.invalidInput("Error: invalid format: \"\(line)\"") }
        let (key, value, pos) = (items[0], items[1], items[2])
        let posId = posIds.getId(pos)
        if posId.isEmpty { throw DataGenError.invalidInput("Error: \(pos) is an invalid pos\n\(line)") }

        // Do not overwrite the existing entry.
        if dictionary.exists(key, value, posId, posId) || aux.exists(key, value, posId, posId) {
          continue
        }

        // Use the same cost as the entry of pos_id and ratio.
        // ratio indicates the position in the words sorted by cost.
        // 0.5 means the middle of the list. 0.0 means the top of the list.
        let cost = try dictionary.getCost(posId, ratio)
        words.append([key, posId, posId, String(cost), value])
      }
    }

    func contents() -> String {
      words.map { $0.joined(separator: "\t") + "\n" }.joined()
    }
  }

  /// Returns the contents of aux_dictionary.txt (`--output`).
  public static func generate(
    auxTsv: String, wordsTsvs: [String], dictionaryTxts: [String], idDef: String?, strict: Bool
  ) throws -> [UInt8] {
    let dictionary = Dictionary()
    try dictionary.parse(dictionaryTxts)

    let aux = AuxDictionary(dictionary)
    try aux.parse(auxTsv, strict: strict)
    var output = aux.contents()

    if !wordsTsvs.isEmpty, let idDef {
      for wordsTsv in wordsTsvs {
        let words = WordsDictionary(dictionary, aux)
        try words.parse(wordsTsv, idDef)
        output += words.contents()  // opened with 'a' (append)
      }
    }
    return Array(output.utf8)
  }
}
