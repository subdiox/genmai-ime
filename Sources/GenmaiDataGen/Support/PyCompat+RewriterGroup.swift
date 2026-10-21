// Port of the helpers of mozc/src/build_tools/code_generator_util.py
// (3.35.6354) used by the rewriter / zero query generators, plus little-endian
// packing (`struct.pack('<I' / '<H', ...)`).

import Foundation

extension Py {
  /// `code_generator_util.SkipLineComment(stream)`: drops blank lines and
  /// lines starting with `#` (after strip()); yields `line.rstrip('\n')`.
  public static func skipLineComment(_ lines: [String], commentPrefix: String = "#") -> [String] {
    var result: [String] = []
    for line in lines {
      let stripped = strip(line)
      if !stripped.isEmpty && !stripped.hasPrefix(commentPrefix) {
        result.append(chompLF(line))
      }
    }
    return result
  }

  /// `code_generator_util.ParseColumnStream(stream, num_column, delimiter)`.
  /// `delimiter == nil` splits at whitespace runs (`str.split()`).
  public static func parseColumnStream(_ lines: [String], numColumn: Int? = nil, delimiter: String? = nil)
    -> [[String]]
  {
    lines.map { line in
      let l = chompLF(line)
      let columns = delimiter.map { split(l, $0) } ?? split(l)
      if let n = numColumn { return Array(columns.prefix(n)) }
      return columns
    }
  }

  /// Splits `s` at runs of any of `separators` (each a literal string), like
  /// `re.split(r'(?:a|b|c)+', s)`: empty strings are kept at both ends and
  /// between nothing else (adjacent separators form one run).
  public static func reSplitRuns(_ s: String, _ separators: [String]) -> [String] {
    let seps = separators.map { Array($0.unicodeScalars) }
    let scalars = Array(s.unicodeScalars)
    var result: [String] = []
    var cur = String.UnicodeScalarView()
    var i = 0
    var inRun = false
    while i < scalars.count {
      var matched = 0
      // Alternation tries the alternatives in order; the first match wins.
      for sep in seps where !sep.isEmpty && i + sep.count <= scalars.count {
        if Array(scalars[i..<(i + sep.count)]) == sep {
          matched = sep.count
          break
        }
      }
      if matched > 0 {
        if !inRun {
          result.append(String(cur))
          cur = String.UnicodeScalarView()
          inRun = true
        }
        i += matched
      } else {
        inRun = false
        cur.append(scalars[i])
        i += 1
      }
    }
    result.append(String(cur))
    return result
  }

  /// `struct.pack('<I', v)`.
  public static func packU32(_ v: Int, into out: inout [UInt8]) {
    let x = UInt32(v)
    out.append(UInt8(x & 0xFF))
    out.append(UInt8((x >> 8) & 0xFF))
    out.append(UInt8((x >> 16) & 0xFF))
    out.append(UInt8((x >> 24) & 0xFF))
  }

  /// `struct.pack('<H', v)`.
  public static func packU16(_ v: Int, into out: inout [UInt8]) {
    let x = UInt16(v)
    out.append(UInt8(x & 0xFF))
    out.append(UInt8(x >> 8))
  }
}
