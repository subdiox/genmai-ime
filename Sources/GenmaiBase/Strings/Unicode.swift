// Port of mozc/src/base/strings/unicode.{h,cc} (3.35.6354).
//
// Notes on the Swift port:
// - Mozc strings are UTF-8 `std::string` / `absl::string_view` and are indexed
//   by byte. In Swift, values are `String` / `Substring`, which are always
//   valid UTF-8. A "character" in Mozc is a Unicode code point (= a Swift
//   `Unicode.Scalar`), never a grapheme cluster (`Character`).
// - Functions that must handle ill-formed UTF-8 have overloads taking any
//   `Collection` of `UInt8` (e.g. `[UInt8]`, `String.UTF8View`, `Data`),
//   so the byte semantics of the C++ code are kept.
// - When bytes produced by a faithful port are turned into a `String`, Swift's
//   standard UTF-8 repair (U+FFFD substitution) applies. This only matters for
//   ill-formed data (e.g. encoding a lone surrogate).
// - Swift's `==`, `<`, `hasPrefix` and `Dictionary` hashing on `String` use
//   Unicode canonical equivalence ("が" == "か\u{3099}"), unlike the bytewise
//   C++ comparisons. Use the byte helpers at the bottom of this file
//   (`bytesEqual`, `compareBytes`, `hasBytePrefix`, ...) where it matters.

public enum Strings {
  /// The Unicode replacement character (U+FFFD) for ill-formed sequences.
  public static let kReplacementCharacter: Char32 = Utf8Internal.kReplacementCharacter

  /// Returns the byte length of a single UTF-8 character based on the leading
  /// byte.
  public static func oneCharLen(_ c: UInt8) -> Int {
    Utf8Internal.oneCharLen(c)
  }

  /// Checks if the bytes are a valid UTF-8 string.
  public static func isValidUtf8<C: Collection>(_ bytes: C) -> Bool where C.Element == UInt8 {
    var i = bytes.startIndex
    while i != bytes.endIndex {
      let dr = Utf8Internal.decode(bytes, from: i)
      if !dr.ok {
        return false
      }
      i = bytes.index(i, offsetBy: dr.bytesSeen)
    }
    return true
  }

  /// Always true for a Swift string; provided for parity.
  public static func isValidUtf8(_ s: some StringProtocol) -> Bool {
    isValidUtf8(s.utf8)
  }

  /// Returns the codepoint count of the given UTF-8 bytes.
  ///
  /// REQUIRES: The UTF-8 string must be valid. This implementation only counts
  /// the leading byte of each character and doesn't check if it's well-formed.
  public static func charsLen<C: Collection>(_ bytes: C) -> Int where C.Element == UInt8 {
    // Every UTF-8 character has exactly one leading byte followed by zero or
    // more continuation bytes (0b10xxxxxx). Therefore, the character count is
    // the byte count minus the continuation byte count.
    var count = 0
    for c in bytes where (c & 0xc0) != 0x80 {
      count += 1
    }
    return count
  }

  /// Returns the codepoint (Unicode scalar) count of the string.
  public static func charsLen(_ s: some StringProtocol) -> Int {
    charsLen(s.utf8)
  }

  /// Returns the number of Unicode characters between [0, n]. It stops
  /// counting at n.
  public static func atLeastCharsLen<C: Collection>(_ bytes: C, _ n: Int) -> Int
  where C.Element == UInt8 {
    var i = 0
    var it = bytes.startIndex
    while it != bytes.endIndex && i < n {
      i += 1
      // std::advance past the end is UB in C++; clip at the end.
      it =
        bytes.index(it, offsetBy: oneCharLen(bytes[it]), limitedBy: bytes.endIndex)
        ?? bytes.endIndex
    }
    return i
  }

  public static func atLeastCharsLen(_ s: some StringProtocol, _ n: Int) -> Int {
    atLeastCharsLen(s.utf8, n)
  }

  /// Returns <first char, rest> of the bytes. The result is clipped if the
  /// input isn't long enough.
  public static func frontChar<C: Collection>(_ s: C) -> (C.SubSequence, C.SubSequence)
  where C.Element == UInt8 {
    guard let first = s.first else {
      return (s[s.startIndex..<s.startIndex], s[s.startIndex..<s.startIndex])
    }
    let len = oneCharLen(first)
    let mid = s.index(s.startIndex, offsetBy: len, limitedBy: s.endIndex) ?? s.endIndex
    return (s[s.startIndex..<mid], s[mid...])
  }

  /// Returns <first char, rest> of the string.
  public static func frontChar(_ s: some StringProtocol) -> (Substring, Substring) {
    let sub = toSubstring(s)
    if sub.isEmpty {
      return ("", "")
    }
    let mid = sub.unicodeScalars.index(after: sub.startIndex)
    return (sub[..<mid], sub[mid...])
  }

  /// Converts the UTF-8 bytes to UTF-32. Ill-formed sequences are replaced
  /// with U+FFFD.
  public static func utf8ToUtf32<C: Collection>(_ bytes: C) -> [Char32] where C.Element == UInt8 {
    Array(Utf8BytesAsUnicodeChar(bytes).lazy.map { $0.char32 })
  }

  public static func utf8ToUtf32(_ s: some StringProtocol) -> [Char32] {
    s.unicodeScalars.map { $0.value }
  }

  /// Converts the UTF-32 string to UTF-8 bytes. If a code point is outside of
  /// the valid Unicode range [U+0000, U+10FFFF], it'll be replaced with U+FFFD.
  /// Null characters are ignored (StrAppendChar32).
  public static func utf32ToUtf8Bytes(_ s: some Sequence<Char32>) -> [UInt8] {
    var result: [UInt8] = []
    for c in s {
      strAppendChar32(&result, c)
    }
    return result
  }

  /// Converts the UTF-32 string to UTF-8.
  public static func utf32ToUtf8(_ s: some Sequence<Char32>) -> String {
    var result = ""
    for c in s {
      strAppendChar32(&result, c)
    }
    return result
  }

  /// Appends a single Unicode character represented by a char32_t code point
  /// to dest. It ignores a null character.
  public static func strAppendChar32(_ dest: inout [UInt8], _ cp: Char32) {
    if cp == 0 {
      // Do nothing if |cp| is `\0`. Keeping the the legacy behavior of
      // CodepointToUtf8Append as some code may rely on it.
      return
    }
    Utf8Internal.encode(cp).append(to: &dest)
  }

  /// Appends a single Unicode character represented by a char32_t code point
  /// to dest. It ignores a null character.
  public static func strAppendChar32(_ dest: inout String, _ cp: Char32) {
    if cp == 0 {
      return
    }
    appendEncoded(&dest, cp)
  }

  /// Converts a single Unicode character by a char32_t code point to UTF-8.
  /// Unlike strAppendChar32, U+0000 is converted to "\0".
  public static func char32ToUtf8(_ cp: Char32) -> String {
    var s = ""
    appendEncoded(&s, cp)
    return s
  }

  /// Byte version of char32ToUtf8.
  public static func char32ToUtf8Bytes(_ cp: Char32) -> [UInt8] {
    Utf8Internal.encode(cp).bytes
  }

  static func appendEncoded(_ dest: inout String, _ cp: Char32) {
    if let scalar = Unicode.Scalar(cp) {
      dest.unicodeScalars.append(scalar)
    } else {
      // > U+10FFFF is encoded as U+FFFD; a surrogate is encoded as an
      // ill-formed 3-byte sequence, which Swift repairs.
      dest += String(decoding: Utf8Internal.encode(cp).bytes, as: UTF8.self)
    }
  }

  /// Returns a substring of the UTF-8 string sv [pos, sv.end()) by the number
  /// of Unicode characters. The result is clipped.
  public static func utf8Substring(_ s: some StringProtocol, _ pos: Int) -> Substring {
    let sub = toSubstring(s)
    let first =
      sub.unicodeScalars.index(sub.startIndex, offsetBy: pos, limitedBy: sub.endIndex)
      ?? sub.endIndex
    return sub[first...]
  }

  /// Returns a substring of the UTF-8 string sv [pos, pos + count) by the
  /// number of Unicode characters. The result is clipped.
  public static func utf8Substring(_ s: some StringProtocol, _ pos: Int, _ count: Int) -> Substring {
    let sub = utf8Substring(s, pos)
    let last =
      sub.unicodeScalars.index(sub.startIndex, offsetBy: count, limitedBy: sub.endIndex)
      ?? sub.endIndex
    return sub[..<last]
  }

  /// Byte version of utf8Substring(_:_:).
  public static func utf8Substring<C: Collection>(_ s: C, _ pos: Int) -> C.SubSequence
  where C.Element == UInt8 {
    let chars = Utf8BytesAsUnicodeChar(s)
    var first = chars.startIndex
    var p = pos
    // REQUIRES: pos <= [number of characters]. Clipped for safety.
    while p > 0 && first != chars.endIndex {
      first = chars.index(after: first)
      p -= 1
    }
    return s[first.position...]
  }

  /// Byte version of utf8Substring(_:_:_:).
  public static func utf8Substring<C: Collection>(_ s: C, _ pos: Int, _ count: Int)
    -> C.SubSequence where C.Element == UInt8
  {
    let rest = utf8Substring(s, pos)
    let chars = Utf8BytesAsUnicodeChar(rest)
    var last = chars.startIndex
    var c = count
    while last != chars.endIndex && c > 0 {
      last = chars.index(after: last)
      c -= 1
    }
    return rest[rest.startIndex..<last.position]
  }

  /// Converts any StringProtocol value to a Substring without copying when it
  /// is a String or a Substring.
  @usableFromInline
  static func toSubstring<S: StringProtocol>(_ s: S) -> Substring {
    if let sub = s as? Substring { return sub }
    if let str = s as? String { return str[...] }
    return Substring(s)
  }
}

// MARK: - UnicodeChar / Utf8AsChars

/// Represents both a UTF-8 string and its decoded result.
public struct UnicodeChar: Sendable, Equatable {
  /// The code point (U+FFFD if `ok` is false).
  public let char32: Char32
  /// The UTF-8 string of the character.
  public let utf8: Substring
  /// Returns if the current character has a valid UTF-8 encoding. Always true
  /// for a character of a Swift string.
  public let ok: Bool

  public init(char32: Char32, utf8: Substring, ok: Bool = true) {
    self.char32 = char32
    self.utf8 = utf8
    self.ok = ok
  }
}

/// Common implementation of Utf8AsChars, Utf8AsChars32 and Utf8AsUnicodeChar:
/// a collection over the Unicode scalars of a string. Indices are
/// `String.Index` values of the underlying string, so they can be converted to
/// byte offsets (`view.byteOffset(of:)`).
public protocol Utf8CharsCollection: BidirectionalCollection where Index == String.Index {
  /// The underlying string.
  var view: Substring { get }
}

extension Utf8CharsCollection {
  public var startIndex: String.Index { view.startIndex }
  public var endIndex: String.Index { view.endIndex }
  public func index(after i: String.Index) -> String.Index {
    view.unicodeScalars.index(after: i)
  }
  public func index(before i: String.Index) -> String.Index {
    view.unicodeScalars.index(before: i)
  }

  /// Returns a substring of [first, end()).
  public func substring(_ first: String.Index) -> Substring { view[first...] }
  /// Returns a substring of [first, last).
  public func substring(_ first: String.Index, _ last: String.Index) -> Substring {
    view[first..<last]
  }
  /// Returns the UTF-8 string of the character at `i`.
  public func charView(at i: String.Index) -> Substring { view[i..<index(after: i)] }
  /// Returns the code point of the character at `i`.
  public func char32(at i: String.Index) -> Char32 { view.unicodeScalars[i].value }
  /// Returns the byte length in UTF-8 of the character at `i`.
  public func size(at i: String.Index) -> Int { view.unicodeScalars[i].utf8.count }
  /// Returns the first character. REQUIRES: !isEmpty.
  public func front() -> Element { self[startIndex] }
  /// Returns the last character. REQUIRES: !isEmpty.
  public func back() -> Element { self[index(before: endIndex)] }
}

/// Iterates a UTF-8 string over each character as substrings.
public struct Utf8AsChars: Utf8CharsCollection, Sendable {
  public let view: Substring
  public init(_ s: String) { view = s[...] }
  public init(_ s: Substring) { view = s }
  public init<S: StringProtocol>(_ s: S) { view = Strings.toSubstring(s) }
  public subscript(i: String.Index) -> Substring { charView(at: i) }
}

/// Iterates a UTF-8 string over each character as char32_t code points.
public struct Utf8AsChars32: Utf8CharsCollection, Sendable {
  public let view: Substring
  public init(_ s: String) { view = s[...] }
  public init(_ s: Substring) { view = s }
  public init<S: StringProtocol>(_ s: S) { view = Strings.toSubstring(s) }
  public subscript(i: String.Index) -> Char32 { view.unicodeScalars[i].value }
}

/// Iterates a UTF-8 string over each character providing both char32_t code
/// points and UTF-8 substrings.
public struct Utf8AsUnicodeChar: Utf8CharsCollection, Sendable {
  public let view: Substring
  public init(_ s: String) { view = s[...] }
  public init(_ s: Substring) { view = s }
  public init<S: StringProtocol>(_ s: S) { view = Strings.toSubstring(s) }
  public subscript(i: String.Index) -> UnicodeChar {
    UnicodeChar(char32: view.unicodeScalars[i].value, utf8: charView(at: i), ok: true)
  }
}

// MARK: - Byte-level iteration (handles ill-formed UTF-8)

/// A character of a byte sequence decoded by `Utf8BytesAsUnicodeChar`.
public struct Utf8ByteChar<Bytes: Collection> where Bytes.Element == UInt8 {
  /// The code point, U+FFFD for ill-formed sequences.
  public let char32: Char32
  /// The bytes of the character (as they are, even if ill-formed).
  public let utf8: Bytes
  /// True if the character has a valid UTF-8 encoding.
  public let ok: Bool
  /// Byte length.
  public var size: Int { utf8.count }
}

/// The C++ `Utf8AsUnicodeChar` / `Utf8AsChars` / `Utf8AsChars32` over raw
/// bytes, with the exact decoding behavior of utf8_internal::Decode for
/// ill-formed input.
public struct Utf8BytesAsUnicodeChar<Base: Collection>: Collection where Base.Element == UInt8 {
  public struct Index: Comparable {
    public let position: Base.Index
    public let decoded: Utf8Internal.DecodeResult
    public static func == (a: Index, b: Index) -> Bool { a.position == b.position }
    public static func < (a: Index, b: Index) -> Bool { a.position < b.position }
  }

  public let base: Base

  public init(_ base: Base) { self.base = base }

  public var startIndex: Index { makeIndex(base.startIndex) }
  public var endIndex: Index { Index(position: base.endIndex, decoded: .sentinel) }

  public func index(after i: Index) -> Index {
    precondition(!i.decoded.isSentinel)
    return makeIndex(base.index(i.position, offsetBy: i.decoded.bytesSeen))
  }

  public subscript(i: Index) -> Utf8ByteChar<Base.SubSequence> {
    precondition(!i.decoded.isSentinel)
    let end = base.index(i.position, offsetBy: i.decoded.bytesSeen)
    return Utf8ByteChar(char32: i.decoded.codePoint, utf8: base[i.position..<end], ok: i.decoded.ok)
  }

  /// Returns a substring of [first, last).
  public func substring(_ first: Index, _ last: Index) -> Base.SubSequence {
    base[first.position..<last.position]
  }

  public func front() -> Utf8ByteChar<Base.SubSequence> { self[startIndex] }

  /// Returns the last character. REQUIRES: !isEmpty.
  public func back() -> Utf8ByteChar<Base.SubSequence> {
    let count = base.count
    let last = base.index(base.startIndex, offsetBy: count - 1)
    if base[last] <= 0x7f {
      // ASCII
      return Utf8ByteChar(char32: Char32(base[last]), utf8: base[last...], ok: true)
    }
    // Other patterns. UTF-8 characters are at most four bytes long.
    // Check three bytes first as it's the most common pattern.
    // We still need to check one byte as it handles invalid sequences.
    for size in [3, 2, 4, 1] where size <= count {
      let it = base.index(base.startIndex, offsetBy: count - size)
      let dr = Utf8Internal.decode(base, from: it)
      if dr.bytesSeen == size {
        return Utf8ByteChar(char32: dr.codePoint, utf8: base[it...], ok: dr.ok)
      }
    }
    fatalError("unreachable")
  }

  private func makeIndex(_ p: Base.Index) -> Index {
    Index(position: p, decoded: Utf8Internal.decode(base, from: p))
  }
}

// MARK: - Byte-offset helpers for Swift strings

extension StringProtocol {
  /// The UTF-8 byte length (`std::string::size()`).
  public var byteCount: Int { utf8.count }

  /// Returns the index at the given UTF-8 byte offset (clipped to endIndex).
  public func byteIndex(_ offset: Int) -> Index {
    utf8.index(startIndex, offsetBy: offset, limitedBy: endIndex) ?? endIndex
  }

  /// Returns the UTF-8 byte offset of `index`.
  public func byteOffset(of index: Index) -> Int {
    utf8.distance(from: startIndex, to: index)
  }

  /// `absl::ClippedSubstr(s, pos, n)` by byte offsets.
  /// REQUIRES: the offsets are on Unicode scalar boundaries.
  public func byteSubstring(from pos: Int, length: Int = .max) -> SubSequence {
    let begin = byteIndex(pos)
    let end: Index
    if length >= utf8.count {
      end = endIndex
    } else {
      end = utf8.index(begin, offsetBy: length, limitedBy: endIndex) ?? endIndex
    }
    return self[begin..<end]
  }

  /// Returns the UTF-8 byte at `offset`.
  public func byte(at offset: Int) -> UInt8 {
    utf8[utf8.index(startIndex, offsetBy: offset)]
  }

  /// Bytewise equality (`absl::string_view::operator==`).
  public func bytesEqual<T: StringProtocol>(_ other: T) -> Bool {
    utf8.elementsEqual(other.utf8)
  }

  /// Bytewise three-way comparison (`absl::string_view::compare`).
  public func compareBytes<T: StringProtocol>(_ other: T) -> Int {
    Strings.compareBytes(utf8, other.utf8)
  }

  /// Bytewise `<`.
  public func bytesLess<T: StringProtocol>(_ other: T) -> Bool {
    compareBytes(other) < 0
  }

  /// Bytewise `absl::StartsWith`.
  public func hasBytePrefix<T: StringProtocol>(_ prefix: T) -> Bool {
    utf8.starts(with: prefix.utf8)
  }

  /// Bytewise `absl::EndsWith`.
  public func hasByteSuffix<T: StringProtocol>(_ suffix: T) -> Bool {
    let n = suffix.utf8.count
    let m = utf8.count
    if n > m { return false }
    return utf8.dropFirst(m - n).elementsEqual(suffix.utf8)
  }
}

extension Strings {
  /// Bytewise three-way comparison of two byte sequences (memcmp semantics,
  /// shorter is smaller on a tie).
  public static func compareBytes<A: Sequence, B: Sequence>(_ a: A, _ b: B) -> Int
  where A.Element == UInt8, B.Element == UInt8 {
    var ia = a.makeIterator()
    var ib = b.makeIterator()
    while true {
      switch (ia.next(), ib.next()) {
      case (nil, nil): return 0
      case (nil, _): return -1
      case (_, nil): return 1
      case (let x?, let y?):
        if x != y { return x < y ? -1 : 1 }
      }
    }
  }
}
