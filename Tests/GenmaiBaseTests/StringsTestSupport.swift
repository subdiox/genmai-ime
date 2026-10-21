// Test helpers for the ports of base/strings/*_test.cc and base/util_test.cc.

/// Converts a C string literal written with `\xHH` escapes (in a Swift raw
/// string, e.g. `#"a\xC2\x80"#`) into its bytes. Other characters are encoded
/// in UTF-8. Every `\x` escape takes exactly two hex digits.
func cBytes(_ s: String) -> [UInt8] {
  var result: [UInt8] = []
  let u = Array(s.utf8)
  var i = 0
  while i < u.count {
    if u[i] == 0x5C, i + 3 < u.count, u[i + 1] == 0x78 {
      let hex = String(decoding: u[(i + 2)..<(i + 4)], as: UTF8.self)
      result.append(UInt8(hex, radix: 16)!)
      i += 4
    } else {
      result.append(u[i])
      i += 1
    }
  }
  return result
}

/// Converts bytes to an array of byte arrays (for comparing slices).
func byteArrays<S: Sequence>(_ slices: S) -> [[UInt8]] where S.Element: Sequence<UInt8> {
  slices.map { Array($0) }
}
