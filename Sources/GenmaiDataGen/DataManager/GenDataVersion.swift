// Port of mozc/src/data_manager/gen_data_version.py (3.35.6354).
//
// Data version consists of three components:
//   <ENGINE_VERSION>.<DATA_VERSION>.<TAG>
// Here, <TAG> is any string to distinguish data set.

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenDataVersion {
  /// Data set sections produced by this generator (keys: dataset_writer_main names).
  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    ["version": Array(try generate(versionTemplate: ctx.sources.versionBzl, tag: ctx.sources.tag).utf8)]
  }

  public static func getVersionString(_ engineVersion: String, _ dataVersion: String, _ tag: String) -> String {
    [engineVersion, dataVersion, tag].joined(separator: ".")
  }

  public static func generate(versionTemplate: String, tag: String, dataVersionOverride: String? = nil) throws -> String {
    var data: [String: String] = [:]
    // re.match(r'(\w+) *= *(.*)', line.strip())
    let regex = try NSRegularExpression(pattern: #"^(\w+) *= *(.*)"#)
    for raw in try Py.readLines(versionTemplate, mode: .universal) {
      let line = Py.strip(raw)
      let ns = line as NSString
      guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
      data[ns.substring(with: m.range(at: 1))] = ns.substring(with: m.range(at: 2))
    }
    if let o = dataVersionOverride, !o.isEmpty { data["DATA_VERSION"] = o }
    guard let e = data["ENGINE_VERSION"], let d = data["DATA_VERSION"] else {
      throw DataGenError.invalidInput("ENGINE_VERSION / DATA_VERSION not found in \(versionTemplate)")
    }
    return getVersionString(e, d, tag)
  }
}
