// Port of mozc/src/base/hash_test.cc (3.35.6354).

import Testing
@testable import GenmaiBase

@Suite struct HashTest {
  // Tests to confirm the behavior of CityHash.
  @Test func cityFingerprint() {
    var s = ""
    #expect(GenmaiBase.cityFingerprint(s) == 0x9ae16a3b2f90404f)
    #expect(cityFingerprintWithSeed(s, 0xdeadbeef) == 0xa124a921b10cc2f)

    s = "google"
    #expect(GenmaiBase.cityFingerprint(s) == 0xae26cdb9998ac502)
    #expect(cityFingerprintWithSeed(s, 0xdeadbeef) == 0xce10609e8e3ef7fb)

    s = "Hello, world!  Hello, Tokyo!  Good afternoon!  Ladies and gentlemen."
    #expect(GenmaiBase.cityFingerprint(s) == 0x8477e610cd1108ce)
    #expect(cityFingerprintWithSeed(s, 0xdeadbeef) == 0xdc8878e5c23ac13f)
  }

  @Test func legacyFingerprint() {
    var s = ""
    #expect(legacyFingerprint32(s) == 0x0d46d8e3)
    #expect(GenmaiBase.legacyFingerprint(s) == 0x2dcdbae1b24d9501)
    #expect(legacyFingerprintWithSeed(s, 0xdeadbeef) == 0x1153f4beb24d9501)

    s = "google"
    #expect(legacyFingerprint32(s) == 0x74290877)
    #expect(GenmaiBase.legacyFingerprint(s) == 0x56d4ad5eafa6beed)
    #expect(legacyFingerprintWithSeed(s, 0xdeadbeef) == 0x1f8cbc0cafa6beed)

    s = "Hello, world!  Hello, Tokyo!  Good afternoon!  Ladies and gentlemen."
    #expect(legacyFingerprint32(s) == 0xb0f5a2ba)
    #expect(GenmaiBase.legacyFingerprint(s) == 0x936ccddf9d4f0b39)
    #expect(legacyFingerprintWithSeed(s, 0xdeadbeef) == 0xe3fd29979d4f0b39)
  }

  // Not in the C++ test: vectors for non-ASCII and long inputs, generated with
  // Abseil's city.cc and Mozc's hash.cc built with -funsigned-char (as Mozc is).
  @Test func nonAsciiVectors() {
    let long = String(repeating: "0123456789abcdefghijklmnopqrstuvwxyz", count: 4)
    let city: [(String, UInt64, UInt64)] = [
      ("あ", 0xb82852303ee7858e, 0xcce7b7b013f47983),
      ("かな漢字変換", 0x98307947a6a6d83e, 0xd3e77e2e16f4fd11),
      (long, 0x0010d91093f05aa2, 0xb795f773f504e0cc),
      ("わたしのなまえはなかのです。今日はいい天気ですね。", 0x2b04e3d9a587c8bd, 0x70e2c33f5c992f04),
    ]
    for (str, h, hs) in city {
      #expect(GenmaiBase.cityFingerprint(str) == h)
      #expect(cityFingerprintWithSeed(str, 0x1234) == hs)
    }
    let legacy: [(String, UInt32, UInt64)] = [
      ("あ", 0x998548da, 0x8f77806d48ee1885),
      ("かな漢字変換", 0xbd791f0b, 0x9f9df0b333003411),
      ("わたしのなまえはなかのです。今日はいい天気ですね。", 0x281c29b1, 0x072192e8124b6141),
    ]
    for (str, h32, h64) in legacy {
      #expect(legacyFingerprint32(str) == h32)
      #expect(GenmaiBase.legacyFingerprint(str) == h64)
    }
  }
}
