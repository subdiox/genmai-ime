// Port of mozc/src/rewriter/gen_a11y_description_rewriter_data.py (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenA11yDescriptionRewriterData {
  /// Data set sections produced by this generator (keys: dataset_writer_main names).
  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    let pairs = try readJapanesePhoneticReading(ctx.sources.a11yDescription)
    let (t, s) = writeOutput(pairs)
    return ["a11y_description_token": t, "a11y_description_string": s]
  }

  static func readJapanesePhoneticReading(_ file: String) throws -> [[String]] {
    let lines = CodeGenUtil.skipLineComment(try Py.readLines(file, mode: .splitlines))
    let outputs = CodeGenUtil.parseColumnStream(lines, numColumn: 2, delimiter: "\t")
    // outputs.sort(key=lambda x: x[0]) (stable)
    return outputs.enumerated().sorted { a, b in
      if a.element[0].utf8.elementsEqual(b.element[0].utf8) { return a.offset < b.offset }
      return Py.less(a.element[0], b.element[0])
    }.map(\.element)
  }

  static func writeOutput(_ keyValuePairs: [[String]]) -> (tokenArray: [UInt8], stringArray: [UInt8]) {
    var strings: [String] = []
    var buf: [UInt8] = []
    for (index, kv) in keyValuePairs.enumerated() {
      CodeGenUtil.packU32(2 * index, into: &buf)
      CodeGenUtil.packU32(2 * index + 1, into: &buf)
      CodeGenUtil.packU32(0, into: &buf)
      CodeGenUtil.packU32(0, into: &buf)
      for _ in 0..<4 { CodeGenUtil.packU16(0, into: &buf) }
      strings.append(kv[0])
      strings.append(kv[1])
    }
    return (buf, SerializedStringArray.serializeToBuffer(strings))
  }
}
