// Port of mozc/src/dictionary/gen_pos_matcher_code.py (3.35.6354).
//
// Generates POS matcher data (--output_pos_matcher_data).  The C++ header
// output (--output_pos_matcher_h) is not needed: the Swift PosMatcher is
// written by hand.

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenPosMatcherCode {
  public static func outputPosMatcherData(_ posMatcher: PosMatcherRules) throws -> [UInt8] {
    let names = posMatcher.getRuleNameList()
    var data: [Int] = []
    for ruleName in names {
      data.append(try posMatcher.getId(ruleName))
    }
    var offset = 2 * names.count
    for ruleName in names {
      data.append(offset)
      offset += 2 * (try posMatcher.getRange(ruleName)).count + 1
    }
    for ruleName in names {
      for idRange in try posMatcher.getRange(ruleName) {
        data.append(idRange.0)
        data.append(idRange.1)
      }
      data.append(0xFFFF)
    }
    var out: [UInt8] = []
    for v in data {
      let u = UInt16(v)
      out.append(UInt8(u & 0xFF))
      out.append(UInt8(u >> 8))
    }
    return out
  }

  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    let posDatabase = PosDataBase()
    try posDatabase.parse(ctx.sources.idDef, ctx.sources.specialPos)
    let posMatcher = PosMatcherRules(posDatabase)
    try posMatcher.parse(ctx.sources.posMatcherRuleDef)
    return ["pos_matcher": try outputPosMatcherData(posMatcher)]
  }
}
