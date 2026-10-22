// Port of mozc/src/base/hash_test.cc (3.35.6354).

import Testing

@testable import GenmaiBase

@Suite struct HashTest {
  // Tests to confirm the behavior of CityHash.
  @Test func cityFingerprint() {
    var s = ""
    #expect(GenmaiBase.cityFingerprint(s) == 0x9ae1_6a3b_2f90_404f)
    #expect(cityFingerprintWithSeed(s, 0xdead_beef) == 0xa12_4a92_1b10_cc2f)

    s = "google"
    #expect(GenmaiBase.cityFingerprint(s) == 0xae26_cdb9_998a_c502)
    #expect(cityFingerprintWithSeed(s, 0xdead_beef) == 0xce10_609e_8e3e_f7fb)

    s = "Hello, world!  Hello, Tokyo!  Good afternoon!  Ladies and gentlemen."
    #expect(GenmaiBase.cityFingerprint(s) == 0x8477_e610_cd11_08ce)
    #expect(cityFingerprintWithSeed(s, 0xdead_beef) == 0xdc88_78e5_c23a_c13f)
  }

  @Test func legacyFingerprint() {
    var s = ""
    #expect(legacyFingerprint32(s) == 0x0d46_d8e3)
    #expect(GenmaiBase.legacyFingerprint(s) == 0x2dcd_bae1_b24d_9501)
    #expect(legacyFingerprintWithSeed(s, 0xdead_beef) == 0x1153_f4be_b24d_9501)

    s = "google"
    #expect(legacyFingerprint32(s) == 0x7429_0877)
    #expect(GenmaiBase.legacyFingerprint(s) == 0x56d4_ad5e_afa6_beed)
    #expect(legacyFingerprintWithSeed(s, 0xdead_beef) == 0x1f8c_bc0c_afa6_beed)

    s = "Hello, world!  Hello, Tokyo!  Good afternoon!  Ladies and gentlemen."
    #expect(legacyFingerprint32(s) == 0xb0f5_a2ba)
    #expect(GenmaiBase.legacyFingerprint(s) == 0x936c_cddf_9d4f_0b39)
    #expect(legacyFingerprintWithSeed(s, 0xdead_beef) == 0xe3fd_2997_9d4f_0b39)
  }

  // Not in the C++ test: vectors for non-ASCII and long inputs, generated with
  // Abseil's city.cc and Mozc's hash.cc built with -funsigned-char (as Mozc is).
  @Test func nonAsciiVectors() {
    let long = String(repeating: "0123456789abcdefghijklmnopqrstuvwxyz", count: 4)
    let city: [(String, UInt64, UInt64)] = [
      ("あ", 0xb828_5230_3ee7_858e, 0xcce7_b7b0_13f4_7983),
      ("かな漢字変換", 0x9830_7947_a6a6_d83e, 0xd3e7_7e2e_16f4_fd11),
      (long, 0x0010_d910_93f0_5aa2, 0xb795_f773_f504_e0cc),
      ("わたしのなまえはなかのです。今日はいい天気ですね。", 0x2b04_e3d9_a587_c8bd, 0x70e2_c33f_5c99_2f04),
    ]
    for (str, h, hs) in city {
      #expect(GenmaiBase.cityFingerprint(str) == h)
      #expect(cityFingerprintWithSeed(str, 0x1234) == hs)
    }
    let legacy: [(String, UInt32, UInt64)] = [
      ("あ", 0x9985_48da, 0x8f77_806d_48ee_1885),
      ("かな漢字変換", 0xbd79_1f0b, 0x9f9d_f0b3_3300_3411),
      ("わたしのなまえはなかのです。今日はいい天気ですね。", 0x281c_29b1, 0x0721_92e8_124b_6141),
    ]
    for (str, h32, h64) in legacy {
      #expect(legacyFingerprint32(str) == h32)
      #expect(GenmaiBase.legacyFingerprint(str) == h64)
    }
  }
}
