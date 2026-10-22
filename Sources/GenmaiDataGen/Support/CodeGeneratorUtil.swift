// Ports of the helpers of mozc/src/build_tools/code_generator_util.py
// (3.35.6354) used by the dictionary-group generators.

import Foundation
import GenmaiBase

/// Namespaced to avoid clashing with other groups' `Py` extensions.
public enum CodeGenUtil {
  /// `code_generator_util.SkipLineComment(stream, comment_prefix)`: yields
  /// `line.rstrip('\n')` of lines that are neither blank nor comments.
  public static func skipLineComment(_ lines: [String], commentPrefix: String = "#") -> [String] {
    lines.compactMap { line in
      let stripped = Py.strip(line)
      guard !stripped.isEmpty, !stripped.hasPrefix(commentPrefix) else { return nil }
      return Py.chompLF(line)
    }
  }

  /// `code_generator_util.ParseColumnStream(stream, num_column, delimiter)`.
  /// `delimiter == nil` splits at whitespace runs (Python `str.split()`).
  public static func parseColumnStream(_ lines: [String], numColumn: Int? = nil, delimiter: String? = nil) -> [[String]]
  {
    lines.map { line in
      let l = Py.chompLF(line)
      let cols = delimiter.map { Py.split(l, $0) } ?? Py.split(l)
      if let n = numColumn { return Array(cols.prefix(n)) }
      return cols
    }
  }

  /// Splits bytes at '\n' like `std::getline` (no trailing empty line; '\r'
  /// kept).
  public static func getlines(_ bytes: [UInt8]) -> [String] {
    var lines: [String] = []
    var start = 0
    for (i, b) in bytes.enumerated() where b == 10 {
      lines.append(String(decoding: bytes[start..<i], as: UTF8.self))
      start = i + 1
    }
    if start < bytes.count { lines.append(String(decoding: bytes[start...], as: UTF8.self)) }
    return lines
  }

  /// `struct.pack('<I', v)` / `'<H'` appenders.
  public static func packU32(_ v: Int, into buf: inout [UInt8]) {
    buf.appendLittleEndian(UInt32(truncatingIfNeeded: v))
  }
  public static func packU16(_ v: Int, into buf: inout [UInt8]) {
    buf.appendLittleEndian(UInt16(truncatingIfNeeded: v))
  }
}
