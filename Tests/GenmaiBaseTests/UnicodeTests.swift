// Port of mozc/src/base/strings/unicode_test.cc (3.35.6354).

import Testing

@testable import GenmaiBase

@Suite struct UnicodeTest {
  @Test func oneCharLen() {
    let kText = "Mozc"
    #expect(Strings.oneCharLen(UInt8(ascii: "M")) == 1)
    #expect(kText.utf8.first == UInt8(ascii: "M"))
  }

  @Test func charsLen() {
    #expect(Strings.charsLen("") == 0)

    let kText = "私の名前は中野です"
    #expect(Strings.charsLen(kText) == 9)
    #expect(Strings.charsLen(kText.utf8) == 9)
    #expect(Strings.charsLen(kText.utf8.suffix(0)) == 0)

    // Mixed character widths with lengths around the eight-byte block size of
    // the implementation.
    #expect(Strings.charsLen("abcdefg") == 7)
    #expect(Strings.charsLen("abcdefgh") == 8)
    #expect(Strings.charsLen("abcdefghi") == 9)
    #expect(Strings.charsLen("aあbいc😀") == 6)
    #expect(Strings.charsLen("😀🎉🚀🍣") == 4)
  }

  @Test func atLeastCharsLen() {
    #expect(Strings.atLeastCharsLen("", 0) == 0)
    #expect(Strings.atLeastCharsLen("", 1) == 0)
    #expect(Strings.atLeastCharsLen("あ", 0) == 0)
    #expect(Strings.atLeastCharsLen("あ", 1) == 1)
    #expect(Strings.atLeastCharsLen("あ", 2) == 1)
    #expect(Strings.atLeastCharsLen("Mozc", 3) == 3)
    #expect(Strings.atLeastCharsLen("Mozc", 4) == 4)
    #expect(Strings.atLeastCharsLen("Mozc", 5) == 4)
  }

  @Test func frontChar() {
    func check(_ s: String, _ first: String, _ rest: String) {
      let r = Strings.frontChar(s)
      #expect(r.0 == first)
      #expect(r.1 == rest)
    }
    check("", "", "")
    check("01", "0", "1")
    check("\u{01}", "\u{01}", "")
    check("あいうえお", "あ", "いうえお")
    check("𧜎𧝒", "𧜎", "𧝒")
    // Invalid length
    let r = Strings.frontChar(cBytes(#"\xC2"#))
    #expect(Array(r.0) == [0xC2])
    #expect(r.1.isEmpty)
    // BOM
    check("\u{FEFF}abc", "\u{FEFF}", "abc")
    let r2 = Strings.frontChar(cBytes(#"\xEF\xBB\xBFabc"#))
    #expect(Array(r2.0) == [0xEF, 0xBB, 0xBF])
    #expect(Array(r2.1) == Array("abc".utf8))
  }

  @Test func utf8ToUtf32() {
    #expect(Strings.utf8ToUtf32("") == [])
    // Single codepoint characters.
    #expect(Strings.utf8ToUtf32("aあ亜\na") == [0x61, 0x3042, 0x4E9C, 0x0A, 0x61])
    // Multiple codepoint characters
    let kStr =
      ("神"  // U+795E
        + "神\u{E0100}"  // U+795E,U+E0100 - 2 codepoints [IVS]
        + "あ\u{3099}")  // U+3042,U+3099  - 2 codepoints [Dakuten]
    #expect(Strings.utf8ToUtf32(kStr) == [0x795E, 0x795E, 0xE0100, 0x3042, 0x3099])
    #expect(Strings.utf8ToUtf32(kStr.utf8) == [0x795E, 0x795E, 0xE0100, 0x3042, 0x3099])
  }

  @Test func utf32ToUtf8() {
    #expect(Strings.utf32ToUtf8([]) == "")
    // Single codepoint characters.
    #expect(Strings.utf32ToUtf8([0x61, 0x3042, 0x4E9C, 0x0A, 0x61]).bytesEqual("aあ亜\na"))
    // Multiple codepoint characters
    let kExpected = "神" + "神\u{E0100}" + "あ\u{3099}"
    let kU32Str: [Char32] = [0x795E, 0x795E, 0xE0100, 0x3042, 0x3099]
    #expect(Strings.utf32ToUtf8(kU32Str).bytesEqual(kExpected))
    #expect(Strings.utf32ToUtf8Bytes(kU32Str) == Array(kExpected.utf8))
  }

  @Test func strAppendChar32() {
    var result = ""
    Strings.strAppendChar32(&result, 0)
    #expect(result.isEmpty)
    Strings.strAppendChar32(&result, 0x41)
    #expect(result == "A")
    Strings.strAppendChar32(&result, 0x3042)
    #expect(result == "Aあ")
    Strings.strAppendChar32(&result, 0x110000)
    #expect(result == "Aあ\u{FFFD}")

    var bytes: [UInt8] = []
    Strings.strAppendChar32(&bytes, 0)
    #expect(bytes.isEmpty)
    Strings.strAppendChar32(&bytes, 0x110000)
    #expect(bytes == [0xEF, 0xBF, 0xBD])
  }

  @Test func char32ToUtf8() {
    #expect(Strings.char32ToUtf8(0) == "\0")
    #expect(Strings.char32ToUtf8(0x41) == "A")
    #expect(Strings.char32ToUtf8(0x3042) == "あ")
    #expect(Strings.char32ToUtf8(0x110000) == "\u{FFFD}")
    #expect(Strings.char32ToUtf8Bytes(0) == [0])
  }

  @Test func isValidUtf8() {
    #expect(Strings.isValidUtf8(""))
    #expect(Strings.isValidUtf8("abc"))
    #expect(Strings.isValidUtf8("あいう"))
    #expect(Strings.isValidUtf8("aあbいcう"))

    #expect(!Strings.isValidUtf8(cBytes(#"\xC2 "#)))
    #expect(!Strings.isValidUtf8(cBytes(#"\xC2\xC2 "#)))
    #expect(!Strings.isValidUtf8(cBytes(#"\xE0 "#)))
    #expect(!Strings.isValidUtf8(cBytes(#"\xE0\xE0\xE0 "#)))
    #expect(!Strings.isValidUtf8(cBytes(#"\xF0 "#)))
    #expect(!Strings.isValidUtf8(cBytes(#"\xF0\xF0\xF0\xF0 "#)))

    // String is too short.
    #expect(!Strings.isValidUtf8(cBytes(#"\xC2"#)))
    let kNotNullTerminated: [UInt8] = [0xf0, 0x90]
    #expect(!Strings.isValidUtf8(kNotNullTerminated))

    // BOM should be treated as invalid byte.
    #expect(!Strings.isValidUtf8(cBytes(#"\xFF "#)))
    #expect(!Strings.isValidUtf8(cBytes(#"\xFE "#)))

    // Redundant encoding.
    #expect(!Strings.isValidUtf8(cBytes(#"\xC0\xAF"#)))
    #expect(!Strings.isValidUtf8(cBytes(#"\xE0\x80\xAF"#)))
    #expect(!Strings.isValidUtf8(cBytes(#"\xF0\x80\x80\xAF"#)))

    // Ill-formed sequences for Surrogates
    #expect(!Strings.isValidUtf8(cBytes(#"\xED\xA0\x80"#)))
    #expect(!Strings.isValidUtf8(cBytes(#"\xED\xBF\xBF"#)))
    #expect(!Strings.isValidUtf8(cBytes(#"\xED\xAF\x41"#)))
  }

  @Test func utf8Substring() {
    #expect(Strings.utf8Substring("", 0) == "")
    #expect(Strings.utf8Substring("Mozc", 0) == "Mozc")
    #expect(Strings.utf8Substring("あいうえお", 3) == "えお")
    #expect(Strings.utf8Substring("日本語入力", 5) == "")

    #expect(Strings.utf8Substring("", 0, 0) == "")
    #expect(Strings.utf8Substring("", 0, 42) == "")
    #expect(Strings.utf8Substring("五十音ABC", 2, 2) == "音A")
    #expect(Strings.utf8Substring("Mozc は便利", 6, 100) == "便利")
    #expect(Strings.utf8Substring("日本語", 2, 0) == "")

    // Invalid sequence.
    #expect(Array(Strings.utf8Substring(cBytes(#"\xF0\x80\x80\xAF"#), 1, 2)) == [0x80, 0x80])
  }

  struct Utf8AsCharsTestParam: Sendable, CustomStringConvertible {
    let input: [UInt8]
    let chars32: [Char32]
    let u8Strings: [[UInt8]]

    init(_ input: String, _ chars32: [Char32], _ u8Strings: [String]) {
      self.input = cBytes(input)
      self.chars32 = chars32
      self.u8Strings = u8Strings.map(cBytes)
    }

    var description: String { input.map { String($0, radix: 16) }.joined(separator: " ") }
  }

  static let kValid: [Utf8AsCharsTestParam] = [
    .init("", [], []),
    .init("あ", [0x3042], ["あ"]),
    .init("Mozc", [0x4D, 0x6F, 0x7A, 0x63], ["M", "o", "z", "c"]),
    .init("日本語入力", [0x65E5, 0x672C, 0x8A9E, 0x5165, 0x529B], ["日", "本", "語", "入", "力"]),
    .init(
      "神" + "神\u{E0100}" + "あ\u{3099}", [0x795E, 0x795E, 0xE0100, 0x3042, 0x3099],
      ["神", "\u{795e}", "\u{e0100}", "\u{3042}", "\u{3099}"]),
    .init(
      "😀 🙆\u{200D}♀\u{FE0F}", [0x1F600, 0x20, 0x1F646, 0x200D, 0x2640, 0xFE0F],
      ["😀", " ", "🙆", "\u{200d}", "♀", "\u{FE0F}"]),
  ]

  static let kInvalid: [Utf8AsCharsTestParam] = [
    .init(#"\xff"#, [0xfffd], [#"\xff"#]),
    .init(#"\xbf"#, [0xfffd], [#"\xbf"#]),
    .init(#"a\xbf\xbf"#, [0x61, 0xfffd, 0xfffd], ["a", #"\xbf"#, #"\xbf"#]),
    .init(#"日\xc0"#, [0x65E5, 0xfffd], ["日", #"\xc0"#]),
    .init(#"\xa0あ"#, [0xfffd, 0x3042], [#"\xa0"#, "あ"]),
    .init(#"\xff\xc0🙂"#, [0xfffd, 0xfffd, 0x1F642], [#"\xff"#, #"\xc0"#, "🙂"]),
    .init(
      #"\xed\xbf\xbfあ"#, [0xfffd, 0xfffd, 0xfffd, 0x3042], [#"\xed"#, #"\xbf"#, #"\xbf"#, "あ"]),
    .init(
      #"あ\xed\xbf\xbf"#, [0x3042, 0xfffd, 0xfffd, 0xfffd], ["あ", #"\xed"#, #"\xbf"#, #"\xbf"#]),
    // From Unicode Standard §3.9 Unicode Encoding Forms
    // Non-shortest form sequences (Table 3-8)
    .init(
      #"\xc0\xaf\xe0\x80\xbf\xf0\x81\x82\x41"#,
      [0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0x41],
      [
        #"\xc0"#, #"\xaf"#, #"\xe0"#, #"\x80"#, #"\xbf"#, #"\xf0"#, #"\x81"#, #"\x82"#, #"\x41"#,
      ]),
    // Ill-formed sequences for surrogates (Table 3-9)
    .init(
      #"\xed\xa0\x80\xed\xbf\xbf\xed\xaf\x41"#,
      [0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0x41],
      [
        #"\xed"#, #"\xa0"#, #"\x80"#, #"\xed"#, #"\xbf"#, #"\xbf"#, #"\xed"#, #"\xaf"#, #"\x41"#,
      ]),
    // Other ill-formed sequences (Table 3-10)
    .init(
      #"\xf4\x91\x92\x93\xff\x41\x80\xbf\x42"#,
      [0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0x41, 0xfffd, 0xfffd, 0x42],
      [
        #"\xf4"#, #"\x91"#, #"\x92"#, #"\x93"#, #"\xff"#, #"\x41"#, #"\x80"#, #"\xbf"#, #"\x42"#,
      ]),
    // Truncated sequences (Table 3-11)
    .init(
      #"\xe1\x80\xe2\xf0\x91\x92\xf1\xbf\x41"#, [0xfffd, 0xfffd, 0xfffd, 0xfffd, 0x41],
      [#"\xe1\x80"#, #"\xe2"#, #"\xf0\x91\x92"#, #"\xf1\xbf"#, #"\x41"#]),
  ]

  static let kBoundChecks: [Utf8AsCharsTestParam] = [
    // 1 byte
    .init(#"\x00"#, [0x00], [#"\x00"#]),
    .init(#"\x01"#, [0x01], [#"\x01"#]),
    .init(#"\x7F"#, [0x7F], [#"\x7F"#]),
    // 2 bytes
    .init(#"\xC2\x7F"#, [0xfffd, 0x7F], [#"\xC2"#, #"\x7F"#]),
    .init(#"\xC2\x80"#, [0x80], [#"\xC2\x80"#]),
    .init(#"\xDF\xBF"#, [0x07FF], [#"\xDF\xBF"#]),
    .init(#"\xDF\xC0"#, [0xfffd, 0xfffd], [#"\xDF"#, #"\xC0"#]),
    // 3 bytes
    .init(#"\xE0\x9F\xBF"#, [0xfffd, 0xfffd, 0xfffd], [#"\xE0"#, #"\x9F"#, #"\xBF"#]),
    .init(#"\xE0\xA0\x80"#, [0x0800], [#"\xE0\xA0\x80"#]),
    .init(#"\xE1\x80\x80"#, [0x1000], [#"\xE1\x80\x80"#]),
    .init(#"\xED\x9F\xBF"#, [0xD7FF], [#"\xED\x9F\xBF"#]),
    .init(#"\xED\xA0\x80"#, [0xfffd, 0xfffd, 0xfffd], [#"\xED"#, #"\xA0"#, #"\x80"#]),
    // 4 bytes
    .init(
      #"\xF0\x8F\xBF\xBF"#, [0xfffd, 0xfffd, 0xfffd, 0xfffd],
      [#"\xF0"#, #"\x8F"#, #"\xBF"#, #"\xBF"#]),
    .init(#"\xF0\x90\x80\x80"#, [0x10000], [#"\xF0\x90\x80\x80"#]),
    .init(#"\xF1\x80\x80\x80"#, [0x40000], [#"\xF1\x80\x80\x80"#]),
    .init(#"\xF3\xBF\xBF\xBF"#, [0xFFFFF], [#"\xF3\xBF\xBF\xBF"#]),
    .init(#"\xF4\x8F\xBF\xBF"#, [0x10FFFF], [#"\xF4\x8F\xBF\xBF"#]),
    .init(
      #"\xF4\x90\x80\x80"#, [0xfffd, 0xfffd, 0xfffd, 0xfffd],
      [#"\xF4"#, #"\x90"#, #"\x80"#, #"\x80"#]),
    .init(
      #"\xF5\x80\x80\x80"#, [0xfffd, 0xfffd, 0xfffd, 0xfffd],
      [#"\xF5"#, #"\x80"#, #"\x80"#, #"\x80"#]),
    .init(
      #"\xFF\xBF\xBF\xBF"#, [0xfffd, 0xfffd, 0xfffd, 0xfffd],
      [#"\xFF"#, #"\xBF"#, #"\xBF"#, #"\xBF"#]),
  ]

  static let kAllParams = kValid + kInvalid + kBoundChecks

  @Test(arguments: kAllParams)
  func asChars32(_ param: Utf8AsCharsTestParam) {
    let s = Utf8BytesAsUnicodeChar(param.input)
    let actual = s.map { $0.char32 }
    #expect(actual == param.chars32)
    if !s.isEmpty {
      #expect(s.front().char32 == param.chars32.first)
      #expect(s.back().char32 == param.chars32.last)
    }
  }

  @Test(arguments: kAllParams)
  func asString(_ param: Utf8AsCharsTestParam) {
    let s = Utf8BytesAsUnicodeChar(param.input)
    let actual = s.map { Array($0.utf8) }
    #expect(actual == param.u8Strings)
    if !s.isEmpty {
      #expect(Array(s.front().utf8) == param.u8Strings.first)
      #expect(Array(s.back().utf8) == param.u8Strings.last)
    }
  }

  /// The String-based Utf8AsChars / Utf8AsChars32 / Utf8AsUnicodeChar for the
  /// valid inputs.
  @Test(arguments: kValid)
  func asStringTypes(_ param: Utf8AsCharsTestParam) {
    let input = String(decoding: param.input, as: UTF8.self)
    #expect(Array(Utf8AsChars32(input)) == param.chars32)
    #expect(Utf8AsChars(input).map { Array($0.utf8) } == param.u8Strings)
    let unicodeChars = Array(Utf8AsUnicodeChar(input))
    #expect(unicodeChars.map(\.char32) == param.chars32)
    #expect(unicodeChars.map { Array($0.utf8.utf8) } == param.u8Strings)
    if !param.chars32.isEmpty {
      #expect(Utf8AsChars32(input).front() == param.chars32.first)
      #expect(Utf8AsChars32(input).back() == param.chars32.last)
      #expect(Array(Utf8AsChars(input).back().utf8) == param.u8Strings.last)
      #expect(Utf8AsUnicodeChar(input).back().char32 == param.chars32.last)
    }
  }

  @Test(arguments: kAllParams)
  func properties(_ param: Utf8AsCharsTestParam) {
    let s = Utf8BytesAsUnicodeChar(param.input)
    #expect(s.isEmpty == param.input.isEmpty)
    #expect(s.base == param.input)
  }

  @Test(arguments: kAllParams)
  func toUtf32(_ param: Utf8AsCharsTestParam) {
    #expect(Strings.utf8ToUtf32(param.input) == param.chars32)
  }

  @Test(arguments: kAllParams)
  func substring(_ param: Utf8AsCharsTestParam) {
    let sv = Utf8BytesAsUnicodeChar(param.input)
    #expect(Array(sv.substring(sv.startIndex, sv.endIndex)) == param.input)

    var first = sv.startIndex
    var expected = 0
    var i = 0
    while i < 2 && first != sv.endIndex {
      first = sv.index(after: first)
      expected += 1
      i += 1
    }
    var last = first
    i = 0
    while i < 2 && last != sv.endIndex {
      last = sv.index(after: last)
      i += 1
    }
    let substr = Utf8BytesAsUnicodeChar(sv.substring(first, last))
    for s in substr {
      #expect(Array(s.utf8) == param.u8Strings[expected])
      expected += 1
    }

    let substr2 = Utf8BytesAsUnicodeChar(sv.substring(first, sv.endIndex))
    #expect(substr2.map(\.char32) == sv[first...].map(\.char32))
  }

  @Test func comparators() {
    let a = Utf8AsChars("aA")
    let b = Utf8AsChars32("aあ")
    #expect(a.view.bytesEqual(a.view))
    #expect(!a.view.bytesEqual(b.view))
    #expect(a.view.compareBytes(b.view) < 0)
    #expect(b.view.compareBytes(a.view) > 0)
    #expect(b.view.compareBytes(b.view) == 0)
  }

  @Test func iteratorMethods() {
    // "a�\xDF"
    let chars = Utf8BytesAsUnicodeChar([0x61, 0xEF, 0xBF, 0xBD, 0xDF])
    var it = chars.startIndex
    #expect(chars[it].char32 == 0x61)
    #expect(Array(chars[it].utf8) == [0x61])
    #expect(chars[it].size == 1)
    #expect(chars[it].ok)
    it = chars.index(after: it)
    #expect(chars[it].char32 == 0xFFFD)
    #expect(Array(chars[it].utf8) == [0xEF, 0xBF, 0xBD])
    #expect(chars[it].size == 3)
    #expect(chars[it].ok)
    it = chars.index(after: it)
    #expect(chars[it].char32 == 0xFFFD)
    #expect(Array(chars[it].utf8) == [0xDF])
    #expect(chars[it].size == 1)
    #expect(!chars[it].ok)

    // String version.
    let s = Utf8AsUnicodeChar("a\u{FFFD}")
    var si = s.startIndex
    #expect(s.char32(at: si) == 0x61)
    #expect(s.charView(at: si) == "a")
    #expect(s.size(at: si) == 1)
    si = s.index(after: si)
    #expect(s.char32(at: si) == 0xFFFD)
    #expect(s.size(at: si) == 3)
    #expect(s.substring(si) == "\u{FFFD}")
  }

  @Test func byteHelpers() {
    let s = "がか\u{3099}"
    // Swift's == uses canonical equivalence; the byte helpers don't.
    #expect("が" == "か\u{3099}")
    #expect(!"が".bytesEqual("か\u{3099}"))
    #expect(s.byteCount == 9)
    #expect(s.byteSubstring(from: 3) == "か\u{3099}")
    #expect(s.byteSubstring(from: 3, length: 3).bytesEqual("か"))
    #expect(s.hasBytePrefix("が"))
    #expect(s.hasByteSuffix("\u{3099}"))
    #expect(!s.hasByteSuffix("が"))
    #expect(s.byteOffset(of: s.byteIndex(6)) == 6)
    #expect(s.byte(at: 0) == 0xE3)
  }
}
