// Helpers that reproduce the Python 3 semantics the Mozc data generators
// (gen_*.py) rely on, so that the Swift ports produce byte-identical output.
//
// - `str.strip()` / `str.split()` (no argument) use Python's Unicode notion of
//   whitespace (`str.isspace`), not just ASCII.
// - Python `dict` keeps insertion order: use `PyOrderedDict` where the
//   iteration order of a dict reaches the output.
// - `sorted()` on `str` compares code points, which equals UTF-8 byte order:
//   use `Strings.byteLess` / `pyLess`.
// - Text files opened with `open(path, encoding=...)` use universal newlines
//   (`\n`, `\r\n`, `\r`); files opened with `codecs.open(...)` are iterated
//   with `str.splitlines(keepends=True)`, which also splits at \v, \f, \x1c-\x1e,
//   \x85, U+2028 and U+2029.  `pyReadLines` implements both.

import Foundation
import GenmaiBase

public enum Py {
  /// Python `str.isspace()` for one scalar.
  public static func isSpace(_ c: Unicode.Scalar) -> Bool {
    switch c.value {
    case 0x09...0x0D, 0x1C...0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F,
      0x205F, 0x3000:
      return true
    default:
      return false
    }
  }

  /// Python `str.strip()` (no argument).
  public static func strip(_ s: some StringProtocol) -> String {
    let u = s.unicodeScalars
    guard let first = u.firstIndex(where: { !isSpace($0) }), let last = u.lastIndex(where: { !isSpace($0) }) else {
      return ""
    }
    return String(String.UnicodeScalarView(u[first...last]))
  }

  /// Python `str.rstrip()` (no argument).
  public static func rstrip(_ s: some StringProtocol) -> String {
    let u = s.unicodeScalars
    guard let last = u.lastIndex(where: { !isSpace($0) }) else { return "" }
    return String(String.UnicodeScalarView(u[...last]))
  }

  /// Python `str.lstrip()` (no argument).
  public static func lstrip(_ s: some StringProtocol) -> String {
    let u = s.unicodeScalars
    guard let first = u.firstIndex(where: { !isSpace($0) }) else { return "" }
    return String(String.UnicodeScalarView(u[first...]))
  }

  /// Python `str.strip(chars)`.
  public static func strip(_ s: some StringProtocol, _ chars: String) -> String {
    let set = Set(chars.unicodeScalars)
    let u = s.unicodeScalars
    guard let first = u.firstIndex(where: { !set.contains($0) }), let last = u.lastIndex(where: { !set.contains($0) })
    else { return "" }
    return String(String.UnicodeScalarView(u[first...last]))
  }

  /// Python `str.rstrip(chars)`.
  public static func rstrip(_ s: some StringProtocol, _ chars: String) -> String {
    let set = Set(chars.unicodeScalars)
    let u = s.unicodeScalars
    guard let last = u.lastIndex(where: { !set.contains($0) }) else { return "" }
    return String(String.UnicodeScalarView(u[...last]))
  }

  /// Python `str.split()` (no argument): splits at runs of whitespace and
  /// drops empty strings.  `maxsplit` as in Python (-1 = unlimited).
  public static func split(_ s: some StringProtocol, maxsplit: Int = -1) -> [String] {
    var result: [String] = []
    var current = String.UnicodeScalarView()
    var inWord = false
    var splits = 0
    let scalars = Array(s.unicodeScalars)
    var i = 0
    while i < scalars.count {
      let c = scalars[i]
      if isSpace(c) {
        if inWord {
          result.append(String(current))
          current = String.UnicodeScalarView()
          inWord = false
          splits += 1
          if maxsplit >= 0 && splits >= maxsplit {
            // Rest (after leading whitespace) is the last element.
            var j = i
            while j < scalars.count && isSpace(scalars[j]) { j += 1 }
            if j < scalars.count {
              var rest = String.UnicodeScalarView()
              rest.append(contentsOf: scalars[j...])
              // Python keeps trailing whitespace of the rest only when
              // maxsplit is hit; it strips leading whitespace.
              result.append(String(rest))
            }
            return result
          }
        }
      } else {
        current.append(c)
        inWord = true
      }
      i += 1
    }
    if inWord { result.append(String(current)) }
    return result
  }

  /// Python `str.split(sep)` with an explicit separator (empty fields kept).
  public static func split(_ s: some StringProtocol, _ sep: String, maxsplit: Int = -1) -> [String] {
    precondition(!sep.isEmpty)
    let str = String(s)
    var result: [String] = []
    var rest = str[...]
    var splits = 0
    while maxsplit < 0 || splits < maxsplit, let r = rest.range(of: sep, options: .literal) {
      result.append(String(rest[..<r.lowerBound]))
      rest = rest[r.upperBound...]
      splits += 1
    }
    result.append(String(rest))
    return result
  }

  public enum NewlineMode: Sendable {
    /// `open(path, 'r', encoding=...)`: universal newlines; `\r\n` and `\r`
    /// are translated to `\n`.
    case universal
    /// `codecs.open(path, 'r', encoding=...)`: lines split by
    /// `str.splitlines(keepends=True)`; no translation.
    case splitlines
    /// Binary / `newline=''`: split at `\n` only.
    case lf
  }

  /// Reads a UTF-8 text file and returns its lines **with** their line
  /// terminators, as iterating a Python file object does.
  public static func readLines(_ path: String, mode: NewlineMode = .universal) throws -> [String] {
    let bytes = try FileUtil.getContentBytes(path)
    var text = String(decoding: bytes, as: UTF8.self)
    // A UTF-8 BOM is kept by Python's 'utf-8' codec (only 'utf-8-sig' drops it).
    switch mode {
    case .universal:
      if text.utf8.contains(13) {
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
      }
      return splitKeepingLF(text)
    case .lf:
      return splitKeepingLF(text)
    case .splitlines:
      return splitlines(text, keepends: true)
    }
  }

  private static func splitKeepingLF(_ text: String) -> [String] {
    var lines: [String] = []
    var start = text.utf8.startIndex
    let u = text.utf8
    var i = u.startIndex
    while i != u.endIndex {
      if u[i] == 10 {
        let next = u.index(after: i)
        lines.append(String(text[start..<next]))
        start = next
      }
      i = u.index(after: i)
    }
    if start != u.endIndex { lines.append(String(text[start...])) }
    return lines
  }

  /// Python `str.splitlines(keepends)`.
  public static func splitlines(_ text: String, keepends: Bool = false) -> [String] {
    func isBreak(_ c: Unicode.Scalar) -> Bool {
      switch c.value {
      case 0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x85, 0x2028, 0x2029: return true
      default: return false
      }
    }
    let scalars = Array(text.unicodeScalars)
    var lines: [String] = []
    var cur = String.UnicodeScalarView()
    var i = 0
    while i < scalars.count {
      let c = scalars[i]
      if isBreak(c) {
        var end = String.UnicodeScalarView()
        end.append(c)
        if c.value == 0x0D && i + 1 < scalars.count && scalars[i + 1].value == 0x0A {
          end.append(scalars[i + 1])
          i += 1
        }
        if keepends { cur.append(contentsOf: end) }
        lines.append(String(cur))
        cur = String.UnicodeScalarView()
      } else {
        cur.append(c)
      }
      i += 1
    }
    if !cur.isEmpty { lines.append(String(cur)) }
    return lines
  }

  /// Python `line.rstrip('\n')`.
  public static func chompLF(_ s: some StringProtocol) -> String {
    var str = String(s)
    while str.utf8.last == 10 { str.removeLast() }
    return str
  }

  /// Python `str < str` (code point order == UTF-8 byte order).
  public static func less(_ a: String, _ b: String) -> Bool {
    a.utf8.lexicographicallyPrecedes(b.utf8)
  }

  /// Python `int(s)` for decimal strings (surrounding whitespace allowed).
  public static func int(_ s: some StringProtocol) -> Int? {
    let t = strip(s).replacingOccurrences(of: "_", with: "")
    return Int(t)
  }
}

/// A minimal insertion-ordered dictionary (Python `dict` semantics).
public struct PyOrderedDict<Key: Hashable, Value> {
  public private(set) var keys: [Key] = []
  private var storage: [Key: Value] = [:]

  public init() {}

  public var count: Int { keys.count }
  public var isEmpty: Bool { keys.isEmpty }

  public subscript(key: Key) -> Value? {
    get { storage[key] }
    set {
      if let v = newValue {
        if storage.updateValue(v, forKey: key) == nil { keys.append(key) }
      } else if storage.removeValue(forKey: key) != nil {
        keys.removeAll { $0 == key }
      }
    }
  }

  public subscript(key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
    get { storage[key] ?? defaultValue() }
    set {
      if storage.updateValue(newValue, forKey: key) == nil { keys.append(key) }
    }
  }

  public func contains(_ key: Key) -> Bool { storage[key] != nil }

  /// (key, value) pairs in insertion order.
  public var items: [(key: Key, value: Value)] { keys.compactMap { key in storage[key].map { (key, $0) } } }
  public var values: [Value] { keys.compactMap { storage[$0] } }
}

extension Dictionary {
  /// The value of a key the generator itself put into the dictionary; throws
  /// instead of trapping if it is missing.
  func requiredValue(_ key: Key) throws -> Value {
    guard let value = self[key] else { throw DataGenError.invalidInput("missing key \(key)") }
    return value
  }
}

/// A string compared, hashed and ordered by its UTF-8 bytes (= code points),
/// like Python `str` and C++ `std::string`.  Swift `String` equality and `<`
/// use canonical equivalence (e.g. "が" == "か\u{3099}"), so a Swift
/// `Dictionary<String, _>` / `Set<String>` / `sorted()` can merge or reorder
/// entries that Python / C++ keep apart.  Use `BStr` as the key type wherever
/// the source data may contain such strings (emoji, symbols, kana with
/// combining marks, ...).
public struct BStr: Hashable, Comparable, CustomStringConvertible, Sendable {
  public let s: String
  public init(_ s: String) { self.s = s }
  public init(_ s: Substring) { self.s = String(s) }
  public static func == (a: BStr, b: BStr) -> Bool { a.s.utf8.elementsEqual(b.s.utf8) }
  public func hash(into h: inout Hasher) {
    for b in s.utf8 { h.combine(b) }
    h.combine(0xFF as UInt8)
  }
  public static func < (a: BStr, b: BStr) -> Bool { a.s.utf8.lexicographicallyPrecedes(b.s.utf8) }
  public var description: String { s }
}
