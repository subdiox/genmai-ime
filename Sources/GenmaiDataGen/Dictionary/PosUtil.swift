// Port of mozc/src/dictionary/pos_util.py (3.35.6354).
//
// Utilities to handle pos related stuff for source code generation.

import Foundation
import GenmaiBase

/// Python `re.compile(pattern).match(s)` (anchored at the start, not at the
/// end).  The patterns of the rule files only use groups, alternation,
/// character classes, `^` and `$`, whose semantics agree between Python `re`
/// and ICU.
public struct PyRegex: @unchecked Sendable {
  let regex: NSRegularExpression

  public init(_ pattern: String) throws {
    regex = try NSRegularExpression(pattern: pattern)
  }

  public func match(_ s: String) -> Bool {
    let ns = s as NSString
    return regex.firstMatch(in: s, options: [.anchored], range: NSRange(location: 0, length: ns.length)) != nil
  }
}

/// code_generator_util helpers (namespaced to avoid clashing with other groups' helpers).
enum PosCodeGenUtil {
  /// code_generator_util.SkipLineComment: yields non-blank, non-comment lines
  /// with the trailing '\n' removed.
  static func skipLineComment(_ lines: [String], commentPrefix: String = "#") -> [String] {
    lines.compactMap { line in
      let stripped = Py.strip(line)
      if !stripped.isEmpty && !stripped.hasPrefix(commentPrefix) {
        return Py.chompLF(line)
      }
      return nil
    }
  }

  /// code_generator_util.ParseColumnStream with `delimiter=None`.
  static func parseColumns(_ lines: [String], numColumn: Int? = nil) -> [[String]] {
    lines.map { line in
      let cols = Py.split(Py.chompLF(line))
      if let n = numColumn { return Array(cols.prefix(n)) }
      return cols
    }
  }
}

/// Utility to look up data in id.def and special_pos.def.
public final class PosDataBase {
  /// (feature or special POS line, POS ID), in file order.
  public private(set) var idList: [(line: String, id: Int)] = []

  public init() {}

  public func parse(_ idFile: String, _ specialPosFile: String) throws {
    var list: [(line: String, id: Int)] = []
    let idLines = PosCodeGenUtil.skipLineComment(try Py.readLines(idFile, mode: .splitlines))
    for cols in PosCodeGenUtil.parseColumns(idLines, numColumn: 2) {
      guard cols.count == 2, let id = Py.int(cols[0]) else {
        throw DataGenError.invalidInput("\(idFile): bad line \(cols)")
      }
      list.append((cols[1], id))
    }
    let maxId = list.map(\.id).max()!
    let special = PosCodeGenUtil.skipLineComment(try Py.readLines(specialPosFile, mode: .splitlines))
    for (k, line) in special.enumerated() {
      list.append((line, maxId + 1 + k))
    }
    idList = list
  }

  /// Returns id for the feature if found (by prefix match). Otherwise nil.
  public func getPosId(_ feature: String) -> Int? {
    precondition(!feature.isEmpty)
    for (line, posId) in idList where line.utf8.starts(with: feature.utf8) {
      return posId
    }
    return nil
  }

  static func groupConsecutiveId(_ values: [Int]) -> [[Int]] {
    var groups: [[Int]] = []
    var result: [Int] = []
    for value in values {
      if let last = result.last, last + 1 != value {
        groups.append(result)
        result = []
      }
      result.append(value)
    }
    if !result.isEmpty { groups.append(result) }
    return groups
  }

  public func getRange(_ pattern: PyRegex) -> [(Int, Int)] {
    let ids = idList.filter { pattern.match($0.line) }.map(\.id).sorted()
    return PosDataBase.groupConsecutiveId(ids).map { ($0.first!, $0.last!) }
  }
}

public final class PosMatcherRules {
  let posDatabase: PosDataBase
  /// name -> (pattern, regex, sortkey); a later duplicate name replaces the
  /// value (and the sort key) of the earlier one, as in a Python dict.
  private var matchRuleMap: [BStr: (pattern: String, regex: PyRegex, sortKey: Int)] = [:]

  public init(_ posDatabase: PosDataBase) {
    self.posDatabase = posDatabase
  }

  public func parse(_ posMatcherRuleFile: String) throws {
    let lines = PosCodeGenUtil.skipLineComment(try Py.readLines(posMatcherRuleFile, mode: .splitlines))
    var map: [BStr: (pattern: String, regex: PyRegex, sortKey: Int)] = [:]
    for (sortKey, cols) in PosCodeGenUtil.parseColumns(lines, numColumn: 2).enumerated() {
      guard cols.count == 2 else { throw DataGenError.invalidInput("\(posMatcherRuleFile): \(cols)") }
      let regex = try PyRegex(cols[1].replacingOccurrences(of: "*", with: "[^,]+"))
      map[BStr(cols[0])] = (cols[1], regex, sortKey)
    }
    matchRuleMap = map
  }

  /// Returns a list of rule names in the original file's order.
  public func getRuleNameList() -> [String] {
    matchRuleMap.sorted { $0.value.sortKey < $1.value.sortKey }.map(\.key.s)
  }

  public func getRange(_ name: String) -> [(Int, Int)] {
    posDatabase.getRange(matchRuleMap[BStr(name)]!.regex)
  }

  public func getId(_ name: String) -> Int {
    getRange(name)[0].0
  }

  public func getOriginalPattern(_ name: String) -> String {
    matchRuleMap[BStr(name)]!.pattern
  }
}

/// Inflection map is a map from key to (form, value_suffix, key_suffix).
public final class InflectionMap {
  private var map: [BStr: [(form: String, valueSuffix: String, keySuffix: String)]] = [:]

  public init() {}

  public func parse(_ filepath: String) throws {
    var result: [BStr: [(form: String, valueSuffix: String, keySuffix: String)]] = [:]
    let lines = PosCodeGenUtil.skipLineComment(try Py.readLines(filepath, mode: .splitlines))
    for cols in PosCodeGenUtil.parseColumns(lines, numColumn: 4) {
      guard cols.count == 4 else { throw DataGenError.invalidInput("\(filepath): \(cols)") }
      result[BStr(cols[0]), default: []].append(
        (cols[1], cols[2] != "*" ? cols[2] : "", cols[3] != "*" ? cols[3] : ""))
    }
    map = result
  }

  /// `defaultdict(list)` lookup: an unknown key yields [].
  public func get(_ key: String) -> [(form: String, valueSuffix: String, keySuffix: String)] {
    map[BStr(key)] ?? []
  }
}

/// The data is assoc list from user_pos (string) to conjugation_list.
/// conjugation_list is a list of (value_suffix, key_suffix, pos_id); the
/// suffixes are nil for POS without conjugation (Python None).
public final class UserPosRules {
  public typealias Conjugation = (valueSuffix: String?, keySuffix: String?, posId: Int)
  let posDatabase: PosDataBase
  let inflectionMap: InflectionMap
  public private(set) var data: [(userPos: String, conjugations: [Conjugation])] = []

  public init(_ posDatabase: PosDataBase, _ inflectionMap: InflectionMap) {
    self.posDatabase = posDatabase
    self.inflectionMap = inflectionMap
  }

  public func parse(_ filepath: String) throws {
    var result: [(userPos: String, conjugations: [Conjugation])] = []
    let lines = PosCodeGenUtil.skipLineComment(try Py.readLines(filepath, mode: .splitlines))
    for cols in PosCodeGenUtil.parseColumns(lines, numColumn: 4) {
      guard cols.count == 4 else { throw DataGenError.invalidInput("\(filepath): \(cols)") }
      let (userPos, ctype, feature) = (cols[0], cols[2], cols[3])
      var conjugationList: [Conjugation] = []
      if ctype == "*" {
        guard let id = posDatabase.getPosId(feature) else {
          throw DataGenError.invalidInput("Cannot find the POS for: \(feature)")
        }
        conjugationList.append((nil, nil, id))
      } else {
        for (form, valueSuffix, keySuffix) in inflectionMap.get(ctype) {
          // repalce <cfrom> with actual cform
          // Known error items (pos_id is None) are skipped.
          if let posId = posDatabase.getPosId(feature.replacingOccurrences(of: "<cform>", with: form)) {
            conjugationList.append((valueSuffix, keySuffix, posId))
          }
        }
      }
      result.append((userPos, conjugationList))
    }
    data = result
  }

  /// Returns id of the given pos.
  public func getPosId(_ pos: String) -> Int? {
    for (userPos, list) in data where userPos.utf8.elementsEqual(pos.utf8) {
      return list[0].posId
    }
    return nil
  }
}
