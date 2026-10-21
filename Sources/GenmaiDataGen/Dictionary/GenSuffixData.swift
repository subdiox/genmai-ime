// Port of mozc/src/dictionary/gen_suffix_data.py (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenSuffixData {
  /// Data set sections produced by this generator (keys: dataset_writer_main names).
  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    let (k, v, t) = try generate(ctx.sources.suffix)
    return ["suffix_key": k, "suffix_value": v, "suffix_token": t]
  }

  public static func generate(_ input: String) throws -> (keyArray: [UInt8], valueArray: [UInt8], tokenArray: [UInt8]) {
    // Remove noisy and unuseful words.
    // invalid_re = ^[→↓↑→─あいうえおぁぃぅぇぉつっょ]$ (re.match; `$` also
    // matches before a trailing '\n').
    let invalid = Set("→↓↑→─あいうえおぁぃぅぇぉつっょ".unicodeScalars)
    func isInvalid(_ value: String) -> Bool {
      var u = Array(value.unicodeScalars)
      if u.count == 2, u[1] == "\n" { u.removeLast() }
      return u.count == 1 && invalid.contains(u[0])
    }

    var result: [(key: String, value: String, lid: Int, rid: Int, cost: Int)] = []
    for raw in try Py.readLines(input, mode: .splitlines) {
      let line = Py.rstrip(raw, "\r\n")
      let fields = Py.split(line, "\t")
      guard fields.count >= 5, let lid = Py.int(fields[1]), let rid = Py.int(fields[2]),
        let cost = Py.int(fields[3])
      else { throw DataGenError.invalidInput("suffix line: \(line)") }
      let key = fields[0]
      var value = fields[4]
      if isInvalid(value) { continue }
      if key.utf8.elementsEqual(value.utf8) { value = "" }
      result.append((key, value, lid, rid, cost))
    }

    // Sort entries in ascending order of key (stable).
    result = result.enumerated().sorted { a, b in
      if a.element.key.utf8.elementsEqual(b.element.key.utf8) { return a.offset < b.offset }
      return Py.less(a.element.key, b.element.key)
    }.map(\.element)

    let keys = SerializedStringArray.serializeToBuffer(result.map(\.key))
    let values = SerializedStringArray.serializeToBuffer(result.map(\.value))
    var tokens: [UInt8] = []
    tokens.reserveCapacity(result.count * 12)
    for e in result {
      CodeGenUtil.packU32(e.lid, into: &tokens)
      CodeGenUtil.packU32(e.rid, into: &tokens)
      CodeGenUtil.packU32(e.cost, into: &tokens)
    }
    return (keys, values, tokens)
  }
}
