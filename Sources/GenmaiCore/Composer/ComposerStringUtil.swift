// Byte-offset string helpers for the composer port (not a port of a C++
// file). Mozc's composer works on UTF-8 `std::string` / `absl::string_view`
// with byte offsets (`find`, `substr`, `size()`); these helpers provide the
// same semantics on Swift strings. All offsets must be on Unicode scalar
// boundaries, which holds for every caller (offsets come from table lookups
// and UTF-8 aware splitting).

import GenmaiBase

enum ComposerBytes {
  /// `absl::string_view::find(pattern, from)` in bytes. Returns nil for npos.
  static func find(_ s: some StringProtocol, _ pattern: some StringProtocol, from: Int = 0) -> Int? {
    let hay = Array(s.utf8)
    let needle = Array(pattern.utf8)
    if from > hay.count {
      return nil
    }
    if needle.isEmpty {
      return from
    }
    if needle.count > hay.count {
      return nil
    }
    var i = from
    while i + needle.count <= hay.count {
      if hay[i] == needle[0] {
        var match = true
        for j in 1..<needle.count where hay[i + j] != needle[j] {
          match = false
          break
        }
        if match {
          return i
        }
      }
      i += 1
    }
    return nil
  }

  /// `absl::string_view::rfind(pattern)` in bytes. Returns nil for npos.
  static func rfind(_ s: some StringProtocol, _ pattern: some StringProtocol) -> Int? {
    let hay = Array(s.utf8)
    let needle = Array(pattern.utf8)
    if needle.count > hay.count {
      return nil
    }
    var i = hay.count - needle.count
    while i >= 0 {
      if Array(hay[i..<(i + needle.count)]) == needle {
        return i
      }
      i -= 1
    }
    return nil
  }

  /// `std::string::substr(pos, len)` in bytes (clipped).
  static func substr(_ s: some StringProtocol, _ pos: Int, _ len: Int = Int.max) -> String {
    String(s.byteSubstring(from: pos, length: len))
  }

  /// Byte equality.
  static func equal(_ a: some StringProtocol, _ b: some StringProtocol) -> Bool {
    a.utf8.elementsEqual(b.utf8)
  }

  /// Bytewise `<` (std::string ordering).
  static func less(_ a: String, _ b: String) -> Bool {
    a.utf8.lexicographicallyPrecedes(b.utf8)
  }

  /// absl::btree_set<std::string>::insert on a byte-ordered, unique array.
  static func insertSorted(_ set: inout [String], _ value: String) {
    var lo = 0
    var hi = set.count
    while lo < hi {
      let mid = (lo + hi) / 2
      if less(set[mid], value) {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    if lo < set.count && equal(set[lo], value) {
      return
    }
    set.insert(value, at: lo)
  }

  /// absl::btree_set<std::string>::contains.
  static func containsSorted(_ set: [String], _ value: some StringProtocol) -> Bool {
    set.contains { equal($0, value) }
  }

  /// absl::btree_set<std::string>::erase.
  static func eraseSorted(_ set: inout [String], _ value: some StringProtocol) {
    set.removeAll { equal($0, value) }
  }
}
