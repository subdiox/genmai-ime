// Port of mozc/src/dictionary/gen_pos_rewrite_rule.py (3.35.6354).
//
// Generates the POS group data (one byte per POS ID; see
// dictionary/pos_group.h).

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenPosRewriteRule {
  static func isPrefix(_ s: String, _ key: String) -> Bool {
    // s.index(key) == 0
    s.utf8.starts(with: key.utf8)
  }

  static func loadRewriteMapRule(_ filename: String) throws -> [(String, String)] {
    var rule: [(String, String)] = []
    for raw in try Py.readLines(filename, mode: .splitlines) {
      let line = Py.chompLF(raw)
      if line.isEmpty || line.hasPrefix("#") { continue }
      let fields = Py.split(line)
      rule.append((fields[0], fields[1]))
    }
    return rule
  }

  static func readPOSID(_ idFile: String, _ specialPosFile: String) throws -> [String] {
    var posList: [String] = []
    for line in try Py.readLines(idFile, mode: .splitlines) {
      let fields = Py.split(line)
      posList.append(fields[1])
    }
    for line in try Py.readLines(specialPosFile, mode: .splitlines) {
      if line.unicodeScalars.count <= 1 || line.hasPrefix("#") { continue }
      let fields = Py.split(line)
      posList.append(fields[0])
    }
    return posList
  }

  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    let posList = try readPOSID(ctx.sources.idDef, ctx.sources.specialPos)
    let rules = try loadRewriteMapRule(ctx.sources.posGroupDef)
    var currentId = 1
    var idMap: [BStr: Int] = [:]
    var ids: [UInt8] = []
    for target in posList {
      var id = 0
      for rule in rules where isPrefix(target, rule.0) {
        if let v = idMap[BStr(rule.1)] {
          id = v
        } else {
          id = currentId
          idMap[BStr(rule.1)] = currentId
          currentId += 1
        }
      }
      ids.append(UInt8(id))
    }
    return ["posg": ids]
  }
}
