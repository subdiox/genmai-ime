// Port of mozc/src/rewriter/gen_usage_rewriter_dictionary_main.cc (3.35.6354).
//
// Generates the usage dictionary data of UsageRewriter from usage_dict.txt
// (@ja_usage_dict) and cforms.def.  For the output format, see the comment at
// the top of the C++ source; all integers are little endian uint32.
//
// Strings are handled as UTF-8 byte arrays, as std::string in the C++ code
// (btree_map / std::map / std::set order = bytewise order).

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenUsageRewriterDictionaryMain {
  typealias Bytes = [UInt8]

  struct ConjugationType {
    var form: Bytes = []
    var valueSuffix: Bytes = []
    var keySuffix: Bytes = []
  }

  struct UsageItem {
    var key: Bytes
    var value: Bytes
    var conjugation: Bytes
    var conjugationId: Int32
    var meaning: Bytes
  }

  /// std::getline over the file contents ('\n' separated; '\r' is kept).
  static func getlines(_ data: Bytes) -> [ArraySlice<UInt8>] {
    var lines: [ArraySlice<UInt8>] = []
    var start = 0
    for i in 0..<data.count where data[i] == 0x0A {
      lines.append(data[start..<i])
      start = i + 1
    }
    if start < data.count { lines.append(data[start...]) }
    return lines
  }

  static let star: Bytes = Array("*".utf8)
  static let baseForm: Bytes = Array("基本形".utf8)

  /// Load cforms_file.
  static func loadConjugation(_ data: Bytes) throws -> (
    inflection: [Bytes: [ConjugationType]], baseform: [Bytes: ConjugationType]
  ) {
    var output: [Bytes: [ConjugationType]] = [:]
    var baseformMap: [Bytes: ConjugationType] = [:]
    for line in getlines(data) {
      if line.isEmpty || line.first == UInt8(ascii: "#") { continue }
      // absl::StrSplit(line, absl::ByAnyChar("\t "), absl::SkipEmpty())
      let fields = line.split(omittingEmptySubsequences: true) { $0 == 0x09 || $0 == 0x20 }.map { Bytes($0) }
      guard fields.count >= 4 else {
        throw DataGenError.invalidInput("format error: \(String(decoding: line, as: UTF8.self))")
      }
      var tmp = ConjugationType()
      tmp.form = fields[1]
      tmp.valueSuffix = fields[2] == star ? [] : fields[2]
      tmp.keySuffix = fields[3] == star ? [] : fields[3]
      output[fields[0], default: []].append(tmp)
      if tmp.form == baseForm {
        baseformMap[fields[0]] = tmp
      }
    }
    return (output, baseformMap)
  }

  /// Load usage_data_file.
  static func loadUsage(_ data: Bytes) throws -> (entries: [UsageItem], conjugationList: [Bytes]) {
    var usageEntries: [UsageItem] = []
    var conjugationList: [Bytes] = []
    var conjugationIdMap: [Bytes: Int32] = [:]
    var conjugationId: Int32 = 0
    for line in getlines(data) {
      if line.isEmpty || line.first == UInt8(ascii: "#") {
        // starting with '#' is a comment line.
        continue
      }
      let fields = line.split(separator: 0x09, omittingEmptySubsequences: false).map { Bytes($0) }
      guard fields.count >= 4 else {
        throw DataGenError.invalidInput("format error: \(String(decoding: line, as: UTF8.self))")
      }
      let meaning = fields[3] == star ? [] : fields[3]
      var item = UsageItem(
        key: fields[0] == star ? [] : fields[0],
        value: fields[1] == star ? [] : fields[1],
        conjugation: fields[2] == star ? [] : fields[2],
        conjugationId: 0,
        meaning: replaceBackslashN(meaning))
      if let id = conjugationIdMap[item.conjugation] {
        item.conjugationId = id
      } else {
        conjugationIdMap[item.conjugation] = conjugationId
        item.conjugationId = conjugationId
        conjugationList.append(item.conjugation)
        conjugationId += 1
      }
      usageEntries.append(item)
    }
    return (usageEntries, conjugationList)
  }

  /// absl::StrReplaceAll(s, {{"\\n", "\n"}}).
  static func replaceBackslashN(_ s: Bytes) -> Bytes {
    var out: Bytes = []
    out.reserveCapacity(s.count)
    var i = 0
    while i < s.count {
      if s[i] == UInt8(ascii: "\\"), i + 1 < s.count, s[i + 1] == UInt8(ascii: "n") {
        out.append(0x0A)
        i += 2
      } else {
        out.append(s[i])
        i += 1
      }
    }
    return out
  }

  /// remove "基本形"'s conjugation suffix
  static func removeBaseformConjugationSuffix(
    _ baseformMap: [Bytes: ConjugationType], _ usageEntries: inout [UsageItem]
  ) {
    for i in usageEntries.indices {
      guard let type = baseformMap[usageEntries[i].conjugation] else { continue }
      // (C++ logs a warning when the key/value is not longer than the suffix.)
      usageEntries[i].key.removeLast(min(type.keySuffix.count, usageEntries[i].key.count))
      usageEntries[i].value.removeLast(min(type.valueSuffix.count, usageEntries[i].value.count))
    }
  }

  public struct Output {
    public var baseConjugationSuffix: [UInt8] = []
    public var conjugationSuffix: [UInt8] = []
    public var conjugationIndex: [UInt8] = []
    public var usageItemArray: [UInt8] = []
    public var stringArray: [UInt8] = []
  }

  static func put(_ v: UInt32, _ out: inout [UInt8]) {
    withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) }
  }

  public static func convert(usageData: [UInt8], cforms: [UInt8]) throws -> Output {
    // Load cforms_file
    let (inflectionMap, baseformMap) = try loadConjugation(cforms)

    // Load usage_data_file
    var (usageEntries, conjugationList) = try loadUsage(usageData)
    removeBaseformConjugationSuffix(baseformMap, &usageEntries)
    // std::stable_sort by key (bytewise).  Swift's sort is stable.
    usageEntries.sort { $0.key.lexicographicallyPrecedes($1.key) }

    // Assign unique index to every string data.  The same string share the
    // same index, so the data is slightly compressed.
    var allStrings = Set<Bytes>()
    allStrings.insert([])
    for (_, v) in baseformMap {
      allStrings.insert(v.valueSuffix)
      allStrings.insert(v.keySuffix)
    }
    for (_, types) in inflectionMap {
      for t in types {
        allStrings.insert(t.valueSuffix)
        allStrings.insert(t.keySuffix)
      }
    }
    for item in usageEntries {
      allStrings.insert(item.key)
      allStrings.insert(item.value)
      allStrings.insert(item.meaning)
    }
    let strings = allStrings.sorted { $0.lexicographicallyPrecedes($1) }
    var stringIndex: [Bytes: UInt32] = [:]
    for (i, s) in strings.enumerated() { stringIndex[s] = UInt32(i) }
    func lookup(_ key: Bytes) throws -> UInt32 {
      guard let v = stringIndex[key] else {
        throw DataGenError.invalidInput("Cannot find key=\(String(decoding: key, as: UTF8.self))")
      }
      return v
    }

    var out = Output()
    // Output base conjugation suffix data.  (baseform_map[conj] default-
    // constructs an empty ConjugationType for a missing conjugation.)
    for conj in conjugationList {
      let base = baseformMap[conj] ?? ConjugationType()
      put(try lookup(base.keySuffix), &out.baseConjugationSuffix)
      put(try lookup(base.valueSuffix), &out.baseConjugationSuffix)
    }

    // Output conjugation suffix data.
    var conjugationIndex = [UInt32](repeating: 0, count: conjugationList.count + 1)
    var outCount: UInt32 = 0
    for (i, conj) in conjugationList.enumerated() {
      let conjugations = inflectionMap[conj] ?? []
      conjugationIndex[i] = outCount
      if conjugations.isEmpty {
        let index = try lookup([])
        put(index, &out.conjugationSuffix)
        put(index, &out.conjugationSuffix)
        outCount += 1
      } else {
        // std::set<std::pair<std::string, std::string>> of (value, key).
        var pairs: [(Bytes, Bytes)] = []
        var seen = Set<[Bytes]>()
        for c in conjugations where seen.insert([c.valueSuffix, c.keySuffix]).inserted {
          pairs.append((c.valueSuffix, c.keySuffix))
        }
        pairs.sort { a, b in
          if a.0 != b.0 { return a.0.lexicographicallyPrecedes(b.0) }
          return a.1.lexicographicallyPrecedes(b.1)
        }
        for (v, k) in pairs {
          put(try lookup(v), &out.conjugationSuffix)
          put(try lookup(k), &out.conjugationSuffix)
          outCount += 1
        }
      }
    }
    conjugationIndex[conjugationList.count] = outCount

    // Output conjugation suffix data index.
    for v in conjugationIndex { put(v, &out.conjugationIndex) }

    // Output usage data.
    var usageId: UInt32 = 0
    for item in usageEntries {
      put(usageId, &out.usageItemArray)
      put(try lookup(item.key), &out.usageItemArray)
      put(try lookup(item.value), &out.usageItemArray)
      put(UInt32(bitPattern: item.conjugationId), &out.usageItemArray)
      put(try lookup(item.meaning), &out.usageItemArray)
      usageId += 1
    }

    // Output string array.
    out.stringArray = SerializedStringArray.serializeToBuffer(strings.map { String(decoding: $0, as: UTF8.self) })
    return out
  }

  /// Data set sections produced by this generator (keys: dataset_writer_main names).
  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    guard let usageDict = ctx.sources.usageDict else {
      throw DataGenError.invalidInput("usage_dict is not given")
    }
    let out = try convert(
      usageData: try FileUtil.getContentBytes(usageDict), cforms: try FileUtil.getContentBytes(ctx.sources.cforms))
    return [
      "usage_base_conjugation_suffix": out.baseConjugationSuffix,
      "usage_conjugation_suffix": out.conjugationSuffix,
      "usage_conjugation_index": out.conjugationIndex,
      "usage_item_array": out.usageItemArray,
      "usage_string_array": out.stringArray,
    ]
  }
}
