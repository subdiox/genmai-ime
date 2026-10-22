// The `IsBoundaryInternal` / kLSize / kRSize that converter/gen_segmenter_code.py
// (3.35.6354) generates as segmenter_inl.inc from id.def, special_pos.def and
// segmenter.def, evaluated from the same rule files instead of compiled code.
// Used by DataManagerTestBase.segmenterTestSameAsInternal.

import Foundation
import GenmaiBase

struct SegmenterInternal {
  let lsize: Int
  let rsize: Int
  /// table[rid * rsize + lid]
  private let table: [Bool]

  func isBoundaryInternal(_ rid: Int, _ lid: Int) -> Bool {
    table[rid * rsize + lid]
  }

  /// ReadPOSID: POS name -> id (id.def, then special_pos.def from max id + 1).
  private static func readPOSID(_ idFile: String, _ specialPosFile: String) throws -> [String: Int] {
    var pos: [String: Int] = [:]
    var maxId = 0
    for line in try lines(idFile) {
      let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
      if fields.count < 2 { continue }
      guard let id = Int(fields[0]) else {
        throw StatusError.invalidArgument("invalid id: \(line)")
      }
      pos[String(fields[1])] = id
      maxId = max(id, maxId)
    }
    maxId += 1
    for line in try lines(specialPosFile) {
      if line.utf8.count < 1 || line.hasPrefix("#") { continue }
      let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
      if fields.isEmpty { continue }
      pos[String(fields[0])] = maxId
      maxId += 1
    }
    return pos
  }

  private static func lines(_ path: String) throws -> [Substring] {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    return text.split(separator: "\n", omittingEmptySubsequences: false)
  }

  /// GetRange: the ids whose POS name matches `pattern` ('*' = "[^,]+",
  /// re.match = anchored at the start), as ranges over the POS names in sorted
  /// order (exactly like the generated code). nil means "*" (always true).
  private static func getRange(_ pos: [String: Int], _ sortedKeys: [String], _ pattern: String)
    throws -> [ClosedRange<Int>]?
  {
    if pattern == "*" { return nil }
    let regex = try Regex(pattern.replacingOccurrences(of: "*", with: "[^,]+")).matchingSemantics(.unicodeScalar)
    var ranges: [ClosedRange<Int>] = []
    var minId = -1
    var maxId = -1
    for p in sortedKeys {
      guard let id = pos[p] else {
        preconditionFailure("sortedKeys are the keys of pos")
      }
      if p.prefixMatch(of: regex) != nil {
        if minId == -1 {
          minId = id
          maxId = id
        } else {
          maxId = id
        }
      } else if minId != -1 {
        ranges.append(minId...maxId)
        minId = -1
      }
    }
    if minId != -1 {
      ranges.append(minId...maxId)
    }
    precondition(!ranges.isEmpty, "FATAL: No rule fiind \(pattern)")
    return ranges
  }

  init(idFile: String, specialPosFile: String, segmenterDef: String) throws {
    let pos = try Self.readPOSID(idFile, specialPosFile)
    // Python sorts str by code point.
    let sortedKeys = pos.keys.sorted { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) }
    let size = pos.count
    lsize = size
    rsize = size

    struct Rule {
      var l: [Bool]?  // rid matches
      var r: [Bool]?  // lid matches
      var result: Bool
    }
    func mask(_ ranges: [ClosedRange<Int>]?) -> [Bool]? {
      guard let ranges else { return nil }
      var m = [Bool](repeating: false, count: size)
      for range in ranges {
        for id in range where id >= 0 && id < size { m[id] = true }
      }
      return m
    }
    var rules: [Rule] = []
    for line in try Self.lines(segmenterDef) {
      if line.utf8.count < 1 || line.hasPrefix("#") { continue }
      let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" })
      if fields.isEmpty { continue }
      precondition(fields.count == 3, "bad rule: \(line)")
      let result = fields[2].lowercased() == "true"
      rules.append(
        Rule(
          l: mask(try Self.getRange(pos, sortedKeys, String(fields[0]))),
          r: mask(try Self.getRange(pos, sortedKeys, String(fields[1]))), result: result))
    }

    var table = [Bool](repeating: true, count: size * size)  // default: true
    for rid in 0..<size {
      // BOS * or * EOS true
      if rid == 0 { continue }
      var undecided = [Bool](repeating: true, count: size)
      undecided[0] = false
      var remaining = size - 1
      for rule in rules {
        if remaining == 0 { break }
        if let l = rule.l, !l[rid] { continue }
        for lid in 1..<size where undecided[lid] {
          if let r = rule.r, !r[lid] { continue }
          table[rid * size + lid] = rule.result
          undecided[lid] = false
          remaining -= 1
        }
      }
    }
    self.table = table
  }
}
