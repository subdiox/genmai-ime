// Port of mozc/src/gui/base/encoding_util_test.cc (3.35.6354).
// CompareToWinAPI (Windows only) is replaced by a comparison with Foundation's
// Shift_JIS decoder on the same vectors.

import Foundation
import Testing

@testable import GenmaiCore

@Suite struct EncodingUtilTests {
  private static let kValidCases: [([UInt8], String)] = [
    // "私の名前はGoogleです。"
    (
      [
        0x8E, 0x84, 0x82, 0xCC, 0x96, 0xBC, 0x91, 0x4F, 0x82, 0xCD, 0x47, 0x6F, 0x6F, 0x67, 0x6C,
        0x65, 0x82, 0xC5, 0x82, 0xB7, 0x81, 0x42,
      ], "私の名前はGoogleです。"
    ),
    // "今日はとても良い天気です。"
    (
      [
        0x8D, 0xA1, 0x93, 0xFA, 0x82, 0xCD, 0x82, 0xC6, 0x82, 0xC4, 0x82, 0xE0, 0x97, 0xC7, 0x82,
        0xA2, 0x93, 0x56, 0x8B, 0x43, 0x82, 0xC5, 0x82, 0xB7, 0x81, 0x42,
      ], "今日はとても良い天気です。"
    ),
    (Array("This is a test for SJIS.".utf8), "This is a test for SJIS."),
    // "あいうえおアイウエオｱｲｳｴｵ"
    (
      [
        0x82, 0xA0, 0x82, 0xA2, 0x82, 0xA4, 0x82, 0xA6, 0x82, 0xA8, 0x83, 0x41, 0x83, 0x43, 0x83,
        0x45, 0x83, 0x47, 0x83, 0x49, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5,
      ], "あいうえおアイウエオｱｲｳｴｵ"
    ),
  ]

  @Test func compareToFoundation() {
    for (sjis, _) in Self.kValidCases {
      let expected = String(data: Data(sjis), encoding: .shiftJIS)
      #expect(EncodingUtil.sjisToUtf8(sjis) == expected)
    }
  }

  @Test func issue2190350() {
    let result = EncodingUtil.sjisToUtf8Bytes([0x82, 0xA0] as [UInt8])
    #expect(result.count == 3)
    #expect(result == Array("あ".utf8))
  }

  @Test func validSJIS() {
    for (sjis, utf8) in Self.kValidCases {
      #expect(EncodingUtil.sjisToUtf8Bytes(sjis) == Array(utf8.utf8))
    }
  }

  @Test func invalidSJIS() {
    let kInvalidInputs: [[UInt8]] = [
      // Invalid first byte (0xA0) at 1st byte
      [0xA0, 0x61, 0x62, 0x63],
      // Invalid first byte (0xA0) at 4-th byte
      [0x61, 0x62, 0x63, 0xA0, 0x64, 0x65, 0x66],
      // Invalid first byte (0xA0) at the last byte
      [0x61, 0x62, 0x63, 0xA0],
      // Valid first byte (0xE0) but there's no second byte
      [0x61, 0x62, 0x63, 0xE0],
      // Valid first byte (0x90) in range 2 + invalid second byte (0x15)
      [0x61, 0x62, 0x63, 0x90, 0x15, 0x64, 0x65, 0x66],
      // Valid first byte (0xEE) in range 4 + invalid second byte (0x01)
      [0x61, 0x62, 0x63, 0xEE, 0x01, 0x64, 0x65, 0x66],
    ]
    for input in kInvalidInputs {
      #expect(EncodingUtil.sjisToUtf8Bytes(input).isEmpty)
    }
  }
}
