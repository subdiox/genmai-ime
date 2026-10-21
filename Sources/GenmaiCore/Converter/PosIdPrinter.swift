// Port of mozc/src/converter/pos_id_printer.{h,cc} (3.35.6354).
//
// Providing the string representation of POS id.

import GenmaiBase

/// `mozc::internal::PosIdPrinter`.
///
/// Example:
///     let posIdPrinter = PosIdPrinter(InputFileStream("id.def"))
///     posIdPrinter.idToString(1934) == "名詞,サ変接続,*,*,*,*,*"
///     posIdPrinter.idToString(-1) == ""  // invalid id
public struct PosIdPrinter: Sendable {
  private var idToPosMap: [Int: String] = [:]

  public init(_ idDef: InputFileStream) {
    while let line = idDef.getline() {
      let columns = line.split(separator: " ", omittingEmptySubsequences: true)
      precondition(columns.count == 2, "Invalid id.def line: \(line)")
      let id = NumberUtil.simpleAtoi(columns[0])
      if idToPosMap[id] == nil {  // emplace() keeps the first entry.
        idToPosMap[id] = String(columns[1])
      }
    }
  }

  /// Returns the POS string for the given id.
  /// For an invalid id, returns empty string.
  public func idToString(_ id: Int) -> String {
    idToPosMap[id] ?? ""
  }
}
