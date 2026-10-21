// Port of mozc/src/dictionary/user_dictionary_util_test.cc (3.35.6354).

import GenmaiProtocol
import Testing

@testable import GenmaiCore

@Suite struct UserDictionaryUtilTests {
  typealias UserDictionary = Genmai_UserDictionary_UserDictionary
  typealias ExtendedErrorCode = UserDictionaryUtil.ExtendedErrorCode

  @Test func testIsValidReading() {
    #expect(UserDictionaryUtil.isValidReading("ABYZabyz0189"))
    #expect(UserDictionaryUtil.isValidReading("〜「」"))
    #expect(UserDictionaryUtil.isValidReading("あいうわをんゔ"))
    #expect(UserDictionaryUtil.isValidReading("アイウワヲンヴ"))
    #expect(!UserDictionaryUtil.isValidReading("水雲"))

    // COMBINING KATAKANA-HIRAGANA VOICED/SEMI-VOICED SOUND MARK (u3099, u309A)
    #expect(!UserDictionaryUtil.isValidReading("\u{3099}\u{309A}"))

    // KATAKANA-HIRAGANA VOICED/SEMI-VOICED SOUND MARK (u309B, u309C)
    #expect(UserDictionaryUtil.isValidReading("゛゜"))

    #expect(!UserDictionaryUtil.isValidReading("𠮷"))
    #expect(!UserDictionaryUtil.isValidReading("😁"))
    #expect(!UserDictionaryUtil.isValidReading("ヷ"))
    #expect(!UserDictionaryUtil.isValidReading("ヺ"))
    #expect(UserDictionaryUtil.isValidReading("。「」、・"))
  }

  @Test func testNormalizeReading() {
    #expect(UserDictionaryUtil.normalizeReading("アイウヴヮ").bytesEqual("あいうゔゎ"))
    #expect(UserDictionaryUtil.normalizeReading("ｱｲｳｬ").bytesEqual("あいうゃ"))
    #expect(UserDictionaryUtil.normalizeReading("ＡＢａｂ０１＠＆＝｜").bytesEqual("ABab01@&=|"))
    #expect(UserDictionaryUtil.normalizeReading("｡｢｣､･").bytesEqual("。「」、・"))
  }

  private func makeEntry(
    _ key: String, _ value: String, _ pos: UserDictionary.PosType, _ comment: String
  ) -> UserDictionary.Entry {
    var output = UserDictionary.Entry()
    output.key = key
    output.value = value
    output.pos = pos
    output.comment = comment
    return output
  }

  @Test func testSanitizeEntry() {
    let golden = makeEntry("abc", "abc", .noun, "abc")
    do {
      var input = makeEntry("abc", "abc", .noun, "abc")
      #expect(!UserDictionaryUtil.sanitizeEntry(&input))
      #expect(golden == input)
    }
    do {
      var input = makeEntry("ab\tc", "abc", .noun, "abc")
      #expect(UserDictionaryUtil.sanitizeEntry(&input))
      #expect(golden == input)
    }
    do {
      var input = makeEntry("abc", "ab\tc", .noun, "ab\tc")
      #expect(UserDictionaryUtil.sanitizeEntry(&input))
      #expect(golden == input)
    }
    do {
      var input = makeEntry("ab\tc", "ab\tc", .noun, "ab\tc")
      #expect(UserDictionaryUtil.sanitizeEntry(&input))
      #expect(golden == input)
    }
  }

  @Test func validateEntry() {
    // Create a valid entry.
    let baseEntry = makeEntry("よみ", "単語", .noun, "コメント")

    var entry = baseEntry
    #expect(UserDictionaryUtil.validateEntryCode(entry) == .ok)

    entry = baseEntry
    entry.clearKey()
    #expect(UserDictionaryUtil.validateEntryCode(entry) == .readingEmpty)

    entry = baseEntry
    entry.key = String(repeating: "a", count: 500)
    #expect(UserDictionaryUtil.validateEntryCode(entry) == .readingTooLong)

    entry = baseEntry
    entry.key = "a\nb"
    #expect(UserDictionaryUtil.validateEntryCode(entry) == .readingContainsInvalidCharacter)

    // Invalid UTF-8 cannot be stored in a Swift String; the byte-level
    // validator (used by the user dictionary loader) is checked instead.
    // "い" is "E3 81 84".
    let validValue = Array("単語".utf8)
    let validComment = Array("コメント".utf8)
    #expect(
      UserDictionaryUtil.validateEntry(
        key: [0xE3, 0x81, 0x82, 0xE3, 0x84, 0xE3, 0x81, 0x86], value: validValue,
        comment: validComment, hasPos: true) == .readingContainsInvalidCharacter)

    entry = baseEntry
    entry.key = "ふ頭"  // Non-Hiragana characters are also acceptable.
    #expect(UserDictionaryUtil.validateEntryCode(entry) == .ok)

    entry = baseEntry
    entry.clearValue()
    #expect(UserDictionaryUtil.validateEntryCode(entry) == .wordEmpty)

    entry = baseEntry
    entry.value = String(repeating: "a", count: 500)
    #expect(UserDictionaryUtil.validateEntryCode(entry) == .wordTooLong)

    entry = baseEntry
    entry.value = "a\nb"
    #expect(UserDictionaryUtil.validateEntryCode(entry) == .wordContainsInvalidCharacter)

    #expect(
      UserDictionaryUtil.validateEntry(
        key: Array("よみ".utf8), value: [0xE3, 0x81, 0x82, 0x81, 0x84, 0xE3, 0x81, 0x86],
        comment: validComment, hasPos: true) == .wordContainsInvalidCharacter)

    entry = baseEntry
    entry.clearComment()
    #expect(UserDictionaryUtil.validateEntryCode(entry) == .ok)

    entry = baseEntry
    entry.comment = String(repeating: "a", count: 500)
    #expect(UserDictionaryUtil.validateEntryCode(entry) == .commentTooLong)

    entry = baseEntry
    entry.comment = "a\nb"
    #expect(UserDictionaryUtil.validateEntryCode(entry) == .commentContainsInvalidCharacter)

    #expect(
      UserDictionaryUtil.validateEntry(
        key: Array("よみ".utf8), value: validValue, comment: [0xE3, 0x81, 0x82, 0xE3, 0xE3, 0x81, 0x86],
        hasPos: true) == .commentContainsInvalidCharacter)

    entry = baseEntry
    entry.clearPos()
    #expect(UserDictionaryUtil.validateEntryCode(entry) == .invalidPosType)
  }

  @Test func validateDictionaryName() {
    func code(_ name: String) -> ExtendedErrorCode {
      do {
        try UserDictionaryUtil.validateDictionaryName(name)
        return .ok
      } catch {
        return error
      }
    }
    #expect(code("") == .dictionaryNameEmpty)
    #expect(code(String(repeating: "a", count: 500)) == .dictionaryNameTooLong)
    #expect(code("a\nbc") == .dictionaryNameContainsInvalidCharacter)
  }
}
