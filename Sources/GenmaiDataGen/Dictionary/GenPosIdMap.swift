// Port of mozc/src/dictionary/gen_pos_id_map.py (3.35.6354).
//
// Generates pos_id_map: the POS strings of id.def, ordered by POS ID and
// separated by '\0'.

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenPosIdMap {
  /// Parses id.def and returns a mapping from POS ID to POS string.
  public static func parseIdDef(_ idDefPath: String) throws -> [Int: String] {
    var idMap: [Int: String] = [:]
    for raw in try Py.readLines(idDefPath, mode: .universal) {
      let line = Py.strip(raw)
      if line.isEmpty || line.hasPrefix("#") { continue }
      let parts = Py.split(line, maxsplit: 1)
      if parts.count < 2 { continue }
      guard let posId = Py.int(parts[0]) else { throw DataGenError.invalidInput("\(idDefPath): \(line)") }
      idMap[posId] = parts[1]
    }
    return idMap
  }

  /// Generates pos_id_map binary data as null-separated strings.
  public static func generatePosIdMapBinary(_ idMap: [Int: String]) throws -> [UInt8] {
    let posIds = idMap.keys.sorted()
    if posIds.isEmpty {
      throw DataGenError.invalidInput("id.def must contain at least one valid POS ID.")
    }
    if posIds != Array(0..<posIds.count) {
      throw DataGenError.invalidInput("POS IDs in id.def must be contiguous and start from 0.")
    }
    var data: [UInt8] = []
    for (posId, name) in idMap.sorted(by: { $0.key < $1.key }) {
      if posId > 0 { data.append(0) }
      data.append(contentsOf: name.utf8)
    }
    return data
  }

  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    ["pos_id_map": try generatePosIdMapBinary(try parseIdDef(ctx.sources.idDef))]
  }
}
