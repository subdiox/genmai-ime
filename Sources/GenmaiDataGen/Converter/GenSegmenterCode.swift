// Port of mozc/src/converter/gen_segmenter_code.py (3.35.6354).
//
// The Python tool generates C++ code (segmenter_inl.inc: kLSize, kRSize and
// IsBoundaryInternal(rid, lid)) from the human-readable rule file, which is
// then compiled into gen_{oss,mock}_segmenter_bitarray_main.  Swift cannot
// compile generated code at build time, so this port evaluates exactly the
// same conditions directly: every rule "L R result" becomes
//   if ((lcond(rid)) && (rcond(lid))) { return result; }
// where each condition is the generated disjunction of `(x == a)` /
// `(x >= a && x <= b)` terms, with the ranges computed as GetRange() does
// (consecutive matches over the POS names in sorted order; note that a range
// may cover non-matching IDs, or be empty when a > b).

import Foundation
import GenmaiBase
import GenmaiCore

public struct GenSegmenterCode: Sendable {
  /// kLSize / kRSize: the number of distinct POS names (later duplicates of a
  /// POS name in id.def replace the ID of the earlier one, as in the Python
  /// dict).
  public let lsize: Int
  public let rsize: Int

  struct Rule {
    /// nil: "*" (condition "true").
    var l: [(Int, Int)]?
    var r: [(Int, Int)]?
    var result: Bool
  }
  let rules: [Rule]

  /// ReadPOSID: POS name -> id string.
  static func readPOSID(_ idFile: String, _ specialPosFile: String) throws -> [BStr: Int] {
    var pos: [BStr: Int] = [:]
    var maxId = 0
    for line in try Py.readLines(idFile, mode: .splitlines) {
      let fields = Py.split(line)
      guard fields.count >= 2, let id = Py.int(fields[0]) else {
        throw DataGenError.invalidInput("\(idFile): \(line)")
      }
      pos[BStr(fields[1])] = id
      maxId = max(id, maxId)
    }
    maxId += 1
    for line in try Py.readLines(specialPosFile, mode: .splitlines) {
      if line.unicodeScalars.count <= 1 || line.hasPrefix("#") { continue }
      let fields = Py.split(line)
      pos[BStr(fields[0])] = maxId
      maxId += 1
    }
    return pos
  }

  static func patternToRegexp(_ pattern: String) -> String {
    pattern.replacingOccurrences(of: "*", with: "[^,]+")
  }

  static func getRange(_ pos: [BStr: Int], _ sortedKeys: [BStr], _ pattern: String) throws -> [(Int, Int)]? {
    if pattern == "*" { return nil }
    let pat = try PyRegex(patternToRegexp(pattern))
    var minId = -1
    var maxId = -1
    var idRange: [(Int, Int)] = []
    for p in sortedKeys {
      let idVal = try pos.requiredValue(p)
      if pat.match(p.s) {
        if minId == -1 {
          minId = idVal
          maxId = idVal
        } else {
          maxId = idVal
        }
      } else if minId != -1 {
        idRange.append((minId, maxId))
        minId = -1
      }
    }
    if minId != -1 {
      idRange.append((minId, maxId))
    }
    if idRange.isEmpty {
      throw DataGenError.invalidInput("FATAL: No rule fiind \(pattern)")
    }
    return idRange
  }

  public init(idFile: String, specialPosFile: String, segmenterDef: String) throws {
    let pos = try GenSegmenterCode.readPOSID(idFile, specialPosFile)
    let keys = pos.keys.sorted()
    lsize = pos.count
    rsize = pos.count
    var rules: [Rule] = []
    for line in try Py.readLines(segmenterDef, mode: .splitlines) {
      if line.unicodeScalars.count <= 1 || line.hasPrefix("#") { continue }
      let fields = Py.split(line)
      guard fields.count == 3 else { throw DataGenError.invalidInput("segmenter.def: \(line)") }
      let result = fields[2].lowercased()
      guard result == "true" || result == "false" else {
        throw DataGenError.invalidInput("segmenter.def: bad result: \(line)")
      }
      rules.append(
        Rule(
          l: try GenSegmenterCode.getRange(pos, keys, fields[0]),
          r: try GenSegmenterCode.getRange(pos, keys, fields[1]), result: result == "true"))
    }
    self.rules = rules
  }

  /// The generated `IsBoundaryInternal(rid, lid)` evaluated for all
  /// rid < lsize, lid < rsize; returns table[rid * rsize + lid].
  public func isBoundaryTable() -> [Bool] {
    // Bit masks over rules: rule k holds for rid (resp. lid).
    let words = (rules.count + 63) / 64
    func masks(_ size: Int, _ cond: (Rule) -> [(Int, Int)]?) -> [UInt64] {
      var m = [UInt64](repeating: 0, count: size * words)
      for (k, rule) in rules.enumerated() {
        let bit = UInt64(1) << UInt64(k % 64)
        if let ranges = cond(rule) {
          for (a, b) in ranges where a <= b {
            for x in max(a, 0)...b where x < size { m[x * words + k / 64] |= bit }
          }
        } else {
          for x in 0..<size { m[x * words + k / 64] |= bit }
        }
      }
      return m
    }
    let lm = masks(lsize, \.l)  // indexed by rid
    let rm = masks(rsize, \.r)  // indexed by lid
    var table = [Bool](repeating: true, count: lsize * rsize)
    for rid in 0..<lsize {
      for lid in 0..<rsize {
        // BOS * or * EOS true
        if rid == 0 || lid == 0 { continue }
        var result = true  // default
        for w in 0..<words {
          let x = lm[rid * words + w] & rm[lid * words + w]
          if x != 0 {
            result = rules[w * 64 + x.trailingZeroBitCount].result
            break
          }
        }
        table[rid * rsize + lid] = result
      }
    }
    return table
  }
}
