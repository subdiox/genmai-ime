// Port of mozc/src/base/text_normalizer_test.cc (3.35.6354).

import Testing

@testable import GenmaiBase

@Suite struct TextNormalizerTest {
  @Test func normalizeText() {
    #expect(TextNormalizer.normalizeText("めかぶ").bytesEqual("めかぶ"))
    #expect(TextNormalizer.normalizeText("ゔぁいおりん").bytesEqual("ゔぁいおりん"))

    // "〜" is U+301C. Not _WIN32: not normalized.
    #expect(TextNormalizer.normalizeText("ぐ〜ぐる").bytesEqual("ぐ〜ぐる"))
    #expect(TextNormalizer.normalizeTextWithFlag("ぐ〜ぐる", .kAll).bytesEqual("ぐ～ぐる"))  // U+FF5E
    #expect(TextNormalizer.normalizeTextWithFlag("ぐ〜ぐる", .kNone).bytesEqual("ぐ〜ぐる"))

    // "−" is U+2212
    #expect(TextNormalizer.normalizeText("１−２−３").bytesEqual("１−２−３"))
    #expect(TextNormalizer.normalizeTextWithFlag("１−２−３", .kAll).bytesEqual("１－２－３"))  // U+FF0D
    #expect(TextNormalizer.normalizeTextWithFlag("１−２−３", .kNone).bytesEqual("１−２−３"))

    // "¥" is U+00A5. U+00A5 is no longer normalized.
    #expect(TextNormalizer.normalizeText("¥298").bytesEqual("¥298"))
  }

  @Test func normalizeTextToSvs() {
    var output = ""
    #expect(!TextNormalizer.normalizeTextToSvs("", &output))
    #expect(output.isEmpty)
    #expect(TextNormalizer.normalizeTextToSvs("").isEmpty)

    var input = "abcあいう"
    #expect(!TextNormalizer.normalizeTextToSvs(input, &output))
    #expect(output.isEmpty)
    #expect(TextNormalizer.normalizeTextToSvs(input) == input)

    input = "\u{FA10}"  // 塚 U+FA10, CJK compatibility character.
    var expected = "\u{585A}\u{FE00}"  // 塚︀ U+585A,U+FE00 SVS character.
    #expect(TextNormalizer.normalizeTextToSvs(input, &output))
    #expect(output.bytesEqual(expected))
    #expect(TextNormalizer.normalizeTextToSvs(input).bytesEqual(expected))

    input = "abc\u{FA10}あいう"
    expected = "abc\u{585A}\u{FE00}あいう"
    #expect(TextNormalizer.normalizeTextToSvs(input, &output))
    #expect(output.bytesEqual(expected))
    #expect(TextNormalizer.normalizeTextToSvs(input).bytesEqual(expected))

    // 欄 in KS X 1001
    #expect(TextNormalizer.normalizeTextToSvs("\u{F91D}").bytesEqual("\u{6B04}\u{FE00}"))
    // 𤋮 in ARIB. The output is more than 16bits.
    #expect(TextNormalizer.normalizeTextToSvs("\u{FA6C}").bytesEqual("\u{242EE}\u{FE00}"))
    // 艹 uses FE01 for SVS extends
    #expect(TextNormalizer.normalizeTextToSvs("\u{FA5E}").bytesEqual("\u{8279}\u{FE01}"))
    // 﨑 is a CJK compat ideograph, but not normalized.
    #expect(TextNormalizer.normalizeTextToSvs("\u{FA11}").bytesEqual("\u{FA11}"))
    // 舘 has the largetst codepoint.
    #expect(TextNormalizer.normalizeTextToSvs("\u{FA6D}").bytesEqual("\u{8218}\u{FE00}"))
    // Next codeponit of 舘.
    #expect(TextNormalizer.normalizeTextToSvs("\u{FA6E}").bytesEqual("\u{FA6E}"))
  }

  @Test func sanitizeText() {
    // 1. No modifications
    #expect(TextNormalizer.sanitizeText("abcあいう", 15) == nil)
    #expect(TextNormalizer.sanitizeText("", 10) == nil)

    // 2. Truncation by max_bytes (safely preserving UTF-8 boundaries)
    // "あいうえお" is 15 bytes in UTF-8 (3 bytes per character).
    // Triggered at limit 6 bytes (should cut exactly to "あい" -> 6 bytes).
    #expect(TextNormalizer.sanitizeText("あいうえお", 6) == "あい")
    #expect(TextNormalizer.sanitizeText("あいうえお", 7) == "あい")
    #expect(TextNormalizer.sanitizeText("あいうえお", 8) == "あい")
    #expect(TextNormalizer.sanitizeText("あいうえお", 9) == "あいう")

    // 3. Skip control characters
    #expect(TextNormalizer.sanitizeText("abc\n\t\0def", 10) == "abcdef")

    // 4. Skip invalid UTF-8 sequences
    // (including partial characters of "あ" \xE3\x81\x82)
    #expect(TextNormalizer.sanitizeText(cBytes(#"abc\xFFdef"#), 10) == "abcdef")
    // \xE3 only (missing 2nd and 3rd bytes)
    #expect(TextNormalizer.sanitizeText(cBytes(#"abc\xE3def"#), 10) == "abcdef")
    // \xE3\x81 only (missing 3rd byte)
    #expect(TextNormalizer.sanitizeText(cBytes(#"abc\xE3\x81def"#), 10) == "abcdef")
    // \x81 only (missing 1st and 2nd bytes)
    #expect(TextNormalizer.sanitizeText(cBytes(#"abc\x81def"#), 10) == "abcdef")
    // \x81\x82 only (missing 1st byte)
    #expect(TextNormalizer.sanitizeText(cBytes(#"abc\x81\x82def"#), 10) == "abcdef")

    // 5. Valid emoji or SVS cases (no modifications -> nil)
    // Emoji 😊 (4 bytes: \xF0\x9F\x98\x8A)
    #expect(TextNormalizer.sanitizeText("😊", 10) == nil)
    // SVS 塚︀ (6 bytes: 塚塚 [3] + FE00 [3])
    #expect(TextNormalizer.sanitizeText("\u{585A}\u{FE00}", 10) == nil)
    // Combined Emoji and SVS (4 + 6 = 10 bytes)
    #expect(TextNormalizer.sanitizeText("😊\u{585A}\u{FE00}", 10) == nil)

    // 6. Truncation of Emoji and SVS
    // 😊 (4 bytes) triggers at 3 bytes -> truncated, broken byte ignored -> ""
    #expect(TextNormalizer.sanitizeText("😊", 3) == "")
    #expect(TextNormalizer.sanitizeText("ab😊", 5) == "ab")
    // 塚︀ (6 bytes) truncated at 5 bytes -> U+FE00 SVS part is cut -> "塚"
    #expect(TextNormalizer.sanitizeText("\u{585A}\u{FE00}", 5)?.bytesEqual("\u{585A}") == true)
    #expect(TextNormalizer.sanitizeText("\u{585A}\u{FE00}", 4)?.bytesEqual("\u{585A}") == true)
    #expect(TextNormalizer.sanitizeText("\u{585A}\u{FE00}", 2) == "")

    // 7. Combined control skip and byte truncation
    // "あ\nい\tうえお" is truncated by 11 bytes after skips -> "あいう".
    #expect(TextNormalizer.sanitizeText("あ\nい\tうえお", 11) == "あいう")
  }
}
