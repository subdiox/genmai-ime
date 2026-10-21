// Port of mozc/src/rewriter/gen_reading_correction_data.py (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenReadingCorrectionData {
  /// Data set sections produced by this generator (keys: dataset_writer_main names).
  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    let (v, e, c) = try writeData(ctx.sources.readingCorrection)
    return ["reading_correction_value": v, "reading_correction_error": e, "reading_correction_correction": c]
  }

  /// `WriteData`: returns the value, error and correction arrays.
  public static func writeData(_ inputPath: String) throws -> ([UInt8], [UInt8], [UInt8]) {
    var outputs: [(value: String, error: String, correction: String)] = []
    let lines = CodeGenUtil.skipLineComment(try Py.readLines(inputPath, mode: .splitlines))
    // ex. (value, error, correction) = ("雰囲気", "ふいんき", "ふんいき")
    for cols in CodeGenUtil.parseColumnStream(lines, numColumn: 3) {
      guard cols.count == 3 else { throw DataGenError.invalidInput("reading correction: \(cols)") }
      outputs.append((cols[0], cols[1], cols[2]))
    }

    // In order to lookup the entries via |error| with binary search,
    // sort outputs here (key = (error, value); stable).
    outputs = outputs.enumerated().sorted { a, b in
      let x = a.element, y = b.element
      if !x.error.utf8.elementsEqual(y.error.utf8) { return Py.less(x.error, y.error) }
      if !x.value.utf8.elementsEqual(y.value.utf8) { return Py.less(x.value, y.value) }
      return a.offset < b.offset
    }.map(\.element)

    return (
      SerializedStringArray.serializeToBuffer(outputs.map(\.value)),
      SerializedStringArray.serializeToBuffer(outputs.map(\.error)),
      SerializedStringArray.serializeToBuffer(outputs.map(\.correction))
    )
  }
}
