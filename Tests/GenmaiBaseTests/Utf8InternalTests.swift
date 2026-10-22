// Port of mozc/src/base/strings/internal/utf8_internal_test.cc (3.35.6354).

import Testing

@testable import GenmaiBase

@Suite struct Utf8InternalTest {
  @Test func oneCharLen() {
    #expect(Utf8Internal.oneCharLen(0x00) == 1)
    #expect(Utf8Internal.oneCharLen(0x7F) == 1)
    #expect(Utf8Internal.oneCharLen(0xC2) == 2)
    #expect(Utf8Internal.oneCharLen(0xDF) == 2)
    #expect(Utf8Internal.oneCharLen(0xE0) == 3)
    #expect(Utf8Internal.oneCharLen(0xEF) == 3)
    #expect(Utf8Internal.oneCharLen(0xF0) == 4)
    #expect(Utf8Internal.oneCharLen(0xF4) == 4)
    // The function and the table agree.
    for i in 0..<256 {
      #expect(Utf8Internal.oneCharLen(UInt8(i)) == Int(Utf8Internal.kUtf8LenTbl[i]))
    }
  }

  static let kEncodeDecodeParams: [([UInt8], Char32)] = [
    ([0], 0),
    (Array("a".utf8), 0x61),
    (Array("€".utf8), 0x20AC),
    (Array("あ".utf8), 0x3042),
    (Array("🙂".utf8), 0x1F642),
    ([0xEF, 0xBF, 0xBD], 0xFFFD),
  ]

  @Test(arguments: kEncodeDecodeParams)
  func encodeDecodeDecode(_ param: ([UInt8], Char32)) {
    let actual = Utf8Internal.decode(param.0)
    #expect(actual.ok)
    #expect(actual.codePoint == param.1)
    #expect(actual.bytesSeen == param.0.count)
  }

  @Test(arguments: kEncodeDecodeParams)
  func encodeDecodeEncode(_ param: ([UInt8], Char32)) {
    let actual = Utf8Internal.encode(param.1)
    #expect(actual.bytes == param.0)
  }

  @Test func encodeInvalid() {
    var actual = Utf8Internal.encode(0xfffd)
    #expect(actual.bytes == Array("\u{fffd}".utf8))
    actual = Utf8Internal.encode(0x110000)
    #expect(actual.bytes == Array("\u{fffd}".utf8))
  }

  @Test func decodeEmpty() {
    let actual = Utf8Internal.decode([UInt8]())
    #expect(actual.isSentinel)
    // Check if the `Sentinel()` has the following characteristics. Not too
    // critical but they are chosen to minimize the risk when the sentinel was
    // accidentally read.
    #expect(!actual.ok)
    #expect(actual.codePoint == 0)
    #expect(actual.bytesSeen == 0)
  }

  static let kDecodeInvalidTestParams: [(String, Int)] = [
    (#"\xC0\xA0"#, 1),  // C0 is not allowed
    (#"\xC2"#, 1),
    (#"\xC2 "#, 1),
    (#"\xC2\xC2 "#, 1),
    (#"\xE0 "#, 1),
    (#"\xE0\xE0\xE0 "#, 1),
    (#"\xF0 "#, 1),
    (#"\xF0\xF0\xF0\xF0 "#, 1),
    (#"\xF5\x80\x80\x80"#, 1),  // F5 is not allowed
    // BOM
    (#"\xFF "#, 1),
    (#"\xFE "#, 1),
    // Non-shortest form sequences
    (#"\xC0\xAF"#, 1),
    (#"\xE0\x80\xBF"#, 1),
    (#"\xF0\x81\x82\x42"#, 1),
    (#"\xF0\x80\x80\xAF\x41"#, 1),
    // I-llformed sequences for surrogates
    (#"\xed\xa0\x80"#, 1),
    (#"\xed\xbf\xbf"#, 1),
    (#"\xed\xaf\xaf\x41"#, 1),
    (#"\xe0\x80\xe2"#, 1),
    // Beyond valid unicode range
    (#"\xf4\x91\x92\x93"#, 1),
    (#"\xff\x41"#, 1),
    (#"\x80\xbf\x42"#, 1),
    // Truncated sequences
    (#"\xe1\x80\xe2"#, 2),
    (#"\xe2\xf0"#, 1),
    (#"\xf0\x91\x92\xf1"#, 3),
    (#"\xf1\xbf\x41"#, 2),
    // Buffer is not long enough.
    (#"\xc2"#, 1),
    (#"\xe2"#, 1),
    (#"\xec\x80"#, 2),
    (#"\xf1"#, 1),
    (#"\xf1\xbf"#, 2),
    (#"\xf1\xbf\x80"#, 3),
    (#"\xf4\xbf "#, 1),
  ]

  @Test(arguments: kDecodeInvalidTestParams)
  func decodeInvalid(_ param: (String, Int)) {
    let actual = Utf8Internal.decode(cBytes(param.0))
    #expect(!actual.ok)
    #expect(actual.codePoint == Utf8Internal.kReplacementCharacter)
    #expect(actual.bytesSeen == param.1)
  }
}
