// Port of mozc/src/base/strings/internal/double_array.{h,cc} (3.35.6354).

/// `mozc::japanese::internal`.
public enum JapaneseInternal {}

/// A Darts double array. The C++ array of `{int16_t base; uint16_t check;}` is
/// stored as two parallel arrays.
public struct DoubleArray: Sendable {
  public let base: [Int16]
  public let check: [UInt16]

  public init(base: [Int16], check: [UInt16]) {
    precondition(base.count == check.count)
    self.base = base
    self.check = check
  }
}

/// A conversion rule: a double array and the value table it points into.
/// Each entry in the table consists of:
/// - null-terminated string
/// - one byte offset to rewind the input
public struct JapaneseRule: Sendable {
  public let table: [UInt8]
  public let doubleArray: DoubleArray
}

extension JapaneseInternal {
  struct LookupResult {
    var seekto: Int = 0
    var index: Int = 0
  }

  static func lookupDoubleArray(
    _ base: UnsafeBufferPointer<Int16>, _ check: UnsafeBufferPointer<UInt16>,
    _ key: UnsafeBufferPointer<UInt8>, _ start: Int
  ) -> LookupResult {
    var n = 0
    var b = Int(base[0])
    var p = 0
    var result = LookupResult()
    let size = key.count - start
    let count = base.count

    for i in 0..<size {
      p = b
      guard p >= 0 && p < count else { return result }
      n = Int(base[p])
      if b == Int(check[p]) && n < 0 {
        result.seekto = i
        result.index = -n - 1
      }
      p = b + Int(key[start + i]) + 1
      guard p >= 0 && p < count else { return result }
      if b == Int(check[p]) {
        b = Int(base[p])
      } else {
        return result
      }
    }
    p = b
    guard p >= 0 && p < count else { return result }
    n = Int(base[p])
    if b == Int(check[p]) && n < 0 {
      result.seekto = size
      result.index = -n - 1
    }
    return result
  }

  /// Returns the length of the null-terminated string at `index` of `table`.
  static func tableStringLength(_ table: UnsafeBufferPointer<UInt8>, _ index: Int) -> Int {
    var len = 0
    while table[index + len] != 0 {
      len += 1
    }
    return len
  }

  static func advanceInputBy(_ table: UnsafeBufferPointer<UInt8>, _ result: LookupResult, _ len: Int)
    -> Int
  {
    result.seekto - Int(table[result.index + len + 1])
  }

  /// Converts `input` (UTF-8 bytes) with the rule and returns UTF-8 bytes.
  public static func convertUsingDoubleArray(_ rule: JapaneseRule, _ input: [UInt8]) -> [UInt8] {
    var output: [UInt8] = []
    output.reserveCapacity(input.count)
    rule.doubleArray.base.withUnsafeBufferPointer { base in
      rule.doubleArray.check.withUnsafeBufferPointer { check in
        rule.table.withUnsafeBufferPointer { table in
          input.withUnsafeBufferPointer { key in
            var mblen = 0
            var i = 0
            while i < key.count {
              let result = lookupDoubleArray(base, check, key, i)
              if result.seekto > 0 {
                let len = tableStringLength(table, result.index)
                output.append(contentsOf: table[result.index..<(result.index + len)])
                mblen = advanceInputBy(table, result, len)
              } else {
                // Not found in the table. Copy from input.
                mblen = Utf8Internal.oneCharLen(key[i])
                output.append(contentsOf: key[i..<min(i + mblen, key.count)])
              }
              i += mblen
            }
          }
        }
      }
    }
    return output
  }

  /// Converts `input` with the rule.
  public static func convertUsingDoubleArray(_ rule: JapaneseRule, _ input: some StringProtocol)
    -> String
  {
    String(decoding: convertUsingDoubleArray(rule, Array(input.utf8)), as: UTF8.self)
  }

  /// Returns the alignment of `input` and the converted result as pairs of
  /// (input piece, output piece).
  public static func alignUsingDoubleArray(_ rule: JapaneseRule, _ input: some StringProtocol)
    -> [(String, String)]
  {
    let bytes = Array(input.utf8)
    var output: [(String, String)] = []
    rule.doubleArray.base.withUnsafeBufferPointer { base in
      rule.doubleArray.check.withUnsafeBufferPointer { check in
        rule.table.withUnsafeBufferPointer { table in
          bytes.withUnsafeBufferPointer { key in
            var mblen = 0
            var i = 0
            while i < key.count {
              let result = lookupDoubleArray(base, check, key, i)
              if result.seekto > 0 {
                let len = tableStringLength(table, result.index)
                let s = String(decoding: table[result.index..<(result.index + len)], as: UTF8.self)
                mblen = advanceInputBy(table, result, len)
                let piece = key[i..<min(i + mblen, key.count)]
                output.append((String(decoding: piece, as: UTF8.self), s))
              } else {
                // Not found in the table. Copy from input.
                mblen = Utf8Internal.oneCharLen(key[i])
                let piece = String(decoding: key[i..<min(i + mblen, key.count)], as: UTF8.self)
                output.append((piece, piece))
              }
              i += mblen
            }
          }
        }
      }
    }
    return output
  }
}
