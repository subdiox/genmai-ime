// Port of mozc/src/dictionary/pos_pattern_matcher.{h,cc} (3.35.6354).

import GenmaiBase

/// `mozc::dictionary::PosPatternMatcher`: matches a POS ID against one or more
/// POS pattern rules.
/// Pattern evaluation and lookup table building are performed at construction
/// time using PosIdMap. Matches are evaluated in O(1) time at runtime.
///
/// Note: `posIdMap` is only used during construction to build the internal
/// lookup table and does not need to outlive this object.
///
/// Pattern syntax for each pattern:
/// - Prefix matching by default:
///   Patterns match POS strings starting with the pattern (absl::StartsWith).
///   For example, "名詞,一般," matches any POS string starting with
///   "名詞,一般,". Similarly, "動詞,自立,*,*,五段" matches
///   "動詞,自立,*,*,五段・カ行促音便,..." naturally because "五段" prefixes
///   "五段・...".
///
/// - Empty pattern:
///   An empty pattern "" is skipped and matches nothing. It does NOT act as a
///   wildcard matching everything.
///
/// - Delimiter boundary attention (trailing comma):
///   Because matching is strictly prefix-based, note that a pattern like
///   "名詞,数" will also match "名詞,数接続" since "名詞,数" is a prefix of
///   both. To match strictly at the POS field boundary, include a trailing
///   comma: e.g. "名詞,数," will match "名詞,数,*,..." but NOT
///   "名詞,数接続,...".
///
/// - Exact match with trailing '$':
///   If a pattern ends with '$', it requires an exact string match with the
///   entire POS string (the trailing '$' is stripped before comparison).
///   e.g. "助詞,並立助詞,*,*,*,*,と$" matches "助詞,並立助詞,*,*,*,*,と" exactly
///   and avoids matching "助詞,並立助詞,*,*,*,*,とか".
/// - Multiple patterns can be passed as a list to match if ANY of the patterns
///   match (logical OR).
public struct PosPatternMatcher: Sendable {
  private struct Pattern {
    var value: Substring = ""
    var exactMatch = false

    func matches(_ posString: String) -> Bool {
      if exactMatch {
        return posString.bytesEqual(value)
      }
      return posString.hasBytePrefix(value)
    }
  }

  private static func parsePattern(_ patternStr: String) -> Pattern {
    var pattern = Pattern()
    var str = stripAsciiWhitespace(patternStr[...])
    if str.hasByteSuffix("$") {
      pattern.exactMatch = true
      str = str.dropLast()
    }
    pattern.value = str
    return pattern
  }

  // absl::StripAsciiWhitespace.
  private static func stripAsciiWhitespace(_ s: Substring) -> Substring {
    func isSpace(_ b: UInt8) -> Bool {
      b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0B || b == 0x0C || b == 0x0D
    }
    let bytes = s.utf8
    var begin = bytes.startIndex
    var end = bytes.endIndex
    while begin < end && isSpace(bytes[begin]) { begin = bytes.index(after: begin) }
    while end > begin && isSpace(bytes[bytes.index(before: end)]) { end = bytes.index(before: end) }
    return s[begin..<end]
  }

  // Lookup table. Index is POS ID, value is match result.
  private var table: [Bool] = []
  private var firstId: UInt16? = nil

  /// Constructs an unavailable matcher (isAvailable() == false). match() always
  /// returns false safely.
  public init() {}

  /// Constructs a matcher for a single pattern.
  /// Example: "名詞,一般,"
  public init(_ pattern: String, _ posIdMap: PosIdMap) {
    buildTable([pattern], posIdMap)
  }

  /// Constructs a matcher for multiple patterns (logical OR).
  /// Matches if any of the patterns match.
  /// Example: PosPatternMatcher(["名詞,固有名詞,人名,", "助詞,"], posIdMap)
  public init(_ patterns: [String], _ posIdMap: PosIdMap) {
    buildTable(patterns, posIdMap)
  }

  /// Returns true if the matcher is available (i.e. built with non-empty
  /// patterns and a valid non-empty PosIdMap). If false, match() always returns
  /// false safely.
  public func isAvailable() -> Bool { !table.isEmpty }

  /// Returns true if the given POS ID matches any of the patterns.
  /// Runs in O(1) time.
  @inline(__always)
  public func match(_ posId: UInt16) -> Bool {
    if Int(posId) >= table.count {
      return false
    }
    return table[Int(posId)]
  }

  /// Returns the lowest matching POS ID numerically (numerically first in
  /// PosIdMap) that matches any of the patterns.
  /// Returns nil if the matcher is not available or no POS matches.
  public func getId() -> UInt16? {
    if !isAvailable() {
      return nil
    }
    return firstId
  }

  private mutating func buildTable(_ patterns: [String], _ posIdMap: PosIdMap) {
    if posIdMap.getPosIdCount() == 0 || patterns.isEmpty {
      return
    }

    var compiledPatterns: [Pattern] = []
    compiledPatterns.reserveCapacity(patterns.count)
    for patternStr in patterns {
      let p = PosPatternMatcher.parsePattern(patternStr)
      if !p.value.isEmpty {
        compiledPatterns.append(p)
      }
    }
    if compiledPatterns.isEmpty {
      return
    }

    // Cap pos_id_count to the maximum number of unique uint16_t values.
    let kMaxPosIdCount = Int(UInt16.max) + 1
    let posIdCount = min(posIdMap.getPosIdCount(), kMaxPosIdCount)
    table = Array(repeating: false, count: posIdCount)

    for posId in 0..<posIdCount {
      let posString = posIdMap.getPosString(UInt16(posId))
      if posString.isEmpty {
        continue
      }
      for pattern in compiledPatterns {
        if pattern.matches(posString) {
          table[posId] = true
          if firstId == nil {
            firstId = UInt16(posId)
          }
          break
        }
      }
    }
  }
}
