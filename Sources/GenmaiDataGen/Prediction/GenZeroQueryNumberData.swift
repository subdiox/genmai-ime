// Port of mozc/src/prediction/gen_zero_query_number_data.py (3.35.6354).
//
// Generate zero query data file for number suffixes.

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenZeroQueryNumberData {
  /// Reads zero query number data from stream and returns zero query data.
  static func readZeroQueryNumberData(_ lines: [String]) -> GenZeroQueryUtil.ZeroQueryDict {
    var dict = GenZeroQueryUtil.ZeroQueryDict()
    for var line in lines {
      if line.hasPrefix("#") { continue }
      line = Py.rstrip(line, "\r\n")
      if line.isEmpty { continue }
      let tokens = Py.split(line, "\t")
      let key = BStr(tokens[0])
      for value in Py.split(tokens[1], ",") {
        dict[key, default: []].append(
          .init(entryType: GenZeroQueryUtil.zeroQueryTypeNumberSuffix, value: value))
      }
    }
    return dict
  }

  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    let dict = readZeroQueryNumberData(try Py.readLines(ctx.sources.zeroQueryNumberDef, mode: .splitlines))
    let out = try GenZeroQueryUtil.writeZeroQueryData(dict)
    return ["zero_query_number_token_array": out.tokens, "zero_query_number_string_array": out.strings]
  }
}
