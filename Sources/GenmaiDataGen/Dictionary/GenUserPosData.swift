// Port of mozc/src/dictionary/gen_user_pos_data.py (3.35.6354).
//
// Utility to generate User POS binary data.

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenUserPosData {
  static func toString(_ s: String?) -> String { s ?? "" }

  /// Returns (token array, string array).
  public static func outputUserPosData(
    _ userPosData: [(userPos: String, conjugations: [UserPosRules.Conjugation])]
  ) -> (tokenArray: [UInt8], stringArray: [UInt8]) {
    var keys = Set<BStr>()
    for (userPos, conjugationList) in userPosData {
      keys.insert(BStr(toString(userPos)))
      for c in conjugationList {
        keys.insert(BStr(toString(c.valueSuffix)))
        keys.insert(BStr(toString(c.keySuffix)))
      }
    }
    let sortedKeys = keys.sorted()
    var stringIndex: [BStr: Int] = [:]
    for (index, s) in sortedKeys.enumerated() { stringIndex[s] = index }

    var tokens: [UInt8] = []
    func put(_ v: Int) {
      let u = UInt16(v)
      tokens.append(UInt8(u & 0xFF))
      tokens.append(UInt8(u >> 8))
    }
    // sorted(user_pos_data): by user_pos (the entries are unique).
    let sortedData = userPosData.enumerated().sorted {
      let a = BStr($0.element.userPos)
      let b = BStr($1.element.userPos)
      return a != b ? a < b : $0.offset < $1.offset
    }.map(\.element)
    for (userPos, conjugationList) in sortedData {
      let userPosIndex = stringIndex[BStr(toString(userPos))]!
      for c in conjugationList {
        // One entry is serialized to 8 byte (four uint16_t components).
        put(userPosIndex)
        put(stringIndex[BStr(toString(c.valueSuffix))]!)
        put(stringIndex[BStr(toString(c.keySuffix))]!)
        put(c.posId)
      }
    }
    return (tokens, SerializedStringArray.serializeToBuffer(sortedKeys.map(\.s)))
  }

  /// Parses id.def, special_pos.def, cforms.def and user_pos.def.
  public static func loadUserPos(_ s: DataGenSources) throws -> UserPosRules {
    let posDatabase = PosDataBase()
    try posDatabase.parse(s.idDef, s.specialPos)
    let inflectionMap = InflectionMap()
    try inflectionMap.parse(s.cforms)
    let userPos = UserPosRules(posDatabase, inflectionMap)
    try userPos.parse(s.userPosDef)
    return userPos
  }

  /// user_pos_token, user_pos_string and pos_list (--output_pos_list; not a
  /// data set section).
  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    let userPos = try loadUserPos(ctx.sources)
    let (token, string) = outputUserPosData(userPos.data)
    return [
      "user_pos_token": token,
      "user_pos_string": string,
      "pos_list": SerializedStringArray.serializeToBuffer(userPos.data.map(\.userPos)),
    ]
  }
}
