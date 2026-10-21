// Port of mozc/src/client/user_dictionary/user_dictionary_importer_test.cc (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private final class TestInputIterator: InputIteratorInterface {
  var index = 0
  var isAvailableFlag = false
  var entries: [RawEntry] = []

  var isAvailable: Bool { isAvailableFlag }

  func next(_ entry: inout RawEntry) -> Bool {
    if !isAvailableFlag {
      return false
    }
    if index >= entries.count {
      return false
    }
    entry.key = entries[index].key
    entry.value = entries[index].value
    entry.pos = entries[index].pos
    entry.comment = entries[index].comment
    index += 1
    return true
  }

  func setEntries(_ entries: [RawEntry]) { self.entries = entries }

  func setAvailable(_ isAvailable: Bool) { isAvailableFlag = isAvailable }
}

@Suite struct UserDictionaryImporterTests {
  typealias UserDictionary = Genmai_UserDictionary_UserDictionary
  typealias ExtendedErrorCode = UserDictionaryUtil.ExtendedErrorCode
  typealias Importer = UserDictionaryImporter

  private func code(_ body: () throws(ExtendedErrorCode) -> Void) -> ExtendedErrorCode {
    do {
      try body()
      return .ok
    } catch {
      return error
    }
  }

  private func importText(
    _ imeType: Importer.IMEType, _ input: String, _ userDic: inout UserDictionary
  ) -> ExtendedErrorCode {
    let iter = StringTextLineIterator(input)
    do {
      try Importer.importFromTextLineIterator(imeType, iter, &userDic)
      return .ok
    } catch {
      return error
    }
  }

  private func importIter(_ iter: TestInputIterator, _ userDic: inout UserDictionary)
    -> ExtendedErrorCode
  {
    do {
      try Importer.importFromIterator(iter, &userDic)
      return .ok
    } catch {
      return error
    }
  }

  @Test func importFromNormalTextTest() throws {
    let kInput =
      "きょうと\t京都\t名詞\n"
      + "おおさか\t大阪\t地名*\n"  // suffix "*" is removed.
      + "とうきょう\t東京\t地名\tコメント\n"
      + "すずき\t鈴木\t人名\n"
      + "あめりか\tアメリカ\t地名:en"

    var userDic = UserDictionary()
    #expect(importText(.google, kInput, &userDic) == .ok)

    try #require(userDic.entries.count == 5)

    #expect(userDic.entries[0].key == "きょうと")
    #expect(userDic.entries[0].value == "京都")
    #expect(userDic.entries[0].pos == .noun)
    #expect(userDic.entries[0].comment == "")
    #expect(userDic.entries[0].locale == "")

    #expect(userDic.entries[1].key == "おおさか")
    #expect(userDic.entries[1].value == "大阪")
    #expect(userDic.entries[1].pos == .placeName)
    #expect(userDic.entries[1].comment == "")
    #expect(userDic.entries[1].locale == "")

    #expect(userDic.entries[2].key == "とうきょう")
    #expect(userDic.entries[2].value == "東京")
    #expect(userDic.entries[2].pos == .placeName)
    #expect(userDic.entries[2].comment == "コメント")
    #expect(userDic.entries[2].locale == "")

    #expect(userDic.entries[3].key == "すずき")
    #expect(userDic.entries[3].value == "鈴木")
    #expect(userDic.entries[3].pos == .personalName)
    #expect(userDic.entries[3].comment == "")
    #expect(userDic.entries[3].locale == "")

    #expect(userDic.entries[4].key == "あめりか")
    #expect(userDic.entries[4].value == "アメリカ")
    #expect(userDic.entries[4].pos == .placeName)
    #expect(userDic.entries[4].comment == "")
    #expect(userDic.entries[4].locale == "en")
  }

  @Test func importFromGboardTextTest() throws {
    let kInput =
      "# Gboard Dictionary Version:1\n"
      + "きょうと\t京都\tja-JP\n"
      + "せかい\t世界\t\n"
      + "あめりか\tアメリカ\ten\n"

    var userDic = UserDictionary()
    #expect(importText(.gboardV1, kInput, &userDic) == .ok)

    try #require(userDic.entries.count == 3)

    #expect(userDic.entries[0].key == "きょうと")
    #expect(userDic.entries[0].value == "京都")
    #expect(userDic.entries[0].pos == .noPos)
    #expect(userDic.entries[0].comment == "")
    #expect(userDic.entries[0].locale == "ja-JP")

    #expect(userDic.entries[1].key == "せかい")
    #expect(userDic.entries[1].value == "世界")
    #expect(userDic.entries[1].pos == .noPos)
    #expect(userDic.entries[1].comment == "")
    #expect(userDic.entries[1].locale == "")

    #expect(userDic.entries[2].key == "あめりか")
    #expect(userDic.entries[2].value == "アメリカ")
    #expect(userDic.entries[2].pos == .noPos)
    #expect(userDic.entries[2].comment == "")
    #expect(userDic.entries[2].locale == "en")
  }

  @Test func importFromKotoeriTextTest() throws {
    let kInput =
      "\"きょうと\"," + "\"京都\",\"名詞\"\n" + "\"おおさか\"," + "\"大阪\",\"地名\"\n" + "// last line"
    do {
      var userDic = UserDictionary()
      #expect(importText(.google, kInput, &userDic) == .importNotSupported)
      #expect(userDic.entries.count == 0)
    }
    do {
      var userDic = UserDictionary()
      #expect(importText(.kotoeri, kInput, &userDic) == .ok)

      try #require(userDic.entries.count == 2)

      #expect(userDic.entries[0].key == "きょうと")
      #expect(userDic.entries[0].value == "京都")
      #expect(userDic.entries[0].pos == .noun)

      #expect(userDic.entries[1].key == "おおさか")
      #expect(userDic.entries[1].value == "大阪")
      #expect(userDic.entries[1].pos == .placeName)
    }
  }

  @Test func importSpecialPosTagTest() throws {
    let kInput =
      "きょうと\t京都\tサジェストのみ\n" + "おおさか\t大阪\t短縮よみ\n" + "すずき\t鈴木\t品詞なし\n"
    var userDic = UserDictionary()
    #expect(importText(.google, kInput, &userDic) == .ok)

    try #require(userDic.entries.count == 3)

    #expect(userDic.entries[0].key == "きょうと")
    #expect(userDic.entries[0].value == "京都")
    #expect(userDic.entries[0].pos == .suggestionOnly)

    #expect(userDic.entries[1].key == "おおさか")
    #expect(userDic.entries[1].value == "大阪")
    #expect(userDic.entries[1].pos == .abbreviation)

    #expect(userDic.entries[2].key == "すずき")
    #expect(userDic.entries[2].value == "鈴木")
    #expect(userDic.entries[2].pos == .noPos)
  }

  @Test func importFromCommentTextTest() throws {
    let kInput =
      "きょうと\t京都\t名詞\n" + "!おおさか\t大阪\t地名\n" + "\n" + "#とうきょう\t東京\t地名\tコメント\n"
      + "すずき\t鈴木\t人名\n"
    do {
      let kMsImeInput = "!Microsoft IME\n" + kInput
      var userDic = UserDictionary()
      #expect(importText(.msime, kMsImeInput, &userDic) == .ok)

      try #require(userDic.entries.count == 3)

      #expect(userDic.entries[0].key == "きょうと")
      #expect(userDic.entries[0].value == "京都")
      #expect(userDic.entries[0].pos == .noun)

      #expect(userDic.entries[1].key == "#とうきょう")
      #expect(userDic.entries[1].value == "東京")
      #expect(userDic.entries[1].pos == .placeName)

      #expect(userDic.entries[2].key == "すずき")
      #expect(userDic.entries[2].value == "鈴木")
      #expect(userDic.entries[2].pos == .personalName)
    }
    do {
      var userDic = UserDictionary()
      #expect(importText(.google, kInput, &userDic) == .ok)

      try #require(userDic.entries.count == 3)

      #expect(userDic.entries[0].key == "きょうと")
      #expect(userDic.entries[0].value == "京都")
      #expect(userDic.entries[0].pos == .noun)

      #expect(userDic.entries[1].key == "!おおさか")
      #expect(userDic.entries[1].value == "大阪")
      #expect(userDic.entries[1].pos == .placeName)

      #expect(userDic.entries[2].key == "すずき")
      #expect(userDic.entries[2].value == "鈴木")
      #expect(userDic.entries[2].pos == .personalName)
    }
  }

  @Test func importFromInvalidTextTest() throws {
    let kInput = "a" + "\n" + "東京\t\t地名\tコメント\n" + "すずき\t鈴木\t人名\n"

    var userDic = UserDictionary()
    #expect(importText(.google, kInput, &userDic) == .importInvalidEntries)

    try #require(userDic.entries.count == 1)

    #expect(userDic.entries[0].key == "すずき")
    #expect(userDic.entries[0].value == "鈴木")
    #expect(userDic.entries[0].pos == .personalName)
  }

  @Test func importFromIteratorInvalidTest() {
    let iter = TestInputIterator()
    var userDic = UserDictionary()
    #expect(!iter.isAvailable)
    #expect(importIter(iter, &userDic) == .ok)
  }

  @Test func importFromIteratorAlreadyFullTest() {
    let iter = TestInputIterator()
    iter.setAvailable(true)
    var userDic = UserDictionary()

    var entries: [RawEntry] = []
    entries.append(RawEntry(key: "aa", value: "aa", pos: "名詞"))

    userDic.entries = Array(
      repeating: UserDictionary.Entry(), count: UserDictionaryStorage.maxEntrySize())

    iter.setAvailable(true)
    iter.setEntries(entries)

    #expect(userDic.entries.count == UserDictionaryStorage.maxEntrySize())

    #expect(iter.isAvailable)
    #expect(importIter(iter, &userDic) == .importTooManyWords)

    #expect(userDic.entries.count == UserDictionaryStorage.maxEntrySize())
  }

  @Test func importFromIteratorNormalTest() throws {
    let iter = TestInputIterator()
    var userDic = UserDictionary()

    let kSizes = [10, 100, 1000, 5000, 12000]
    for size in kSizes {
      var entries: [RawEntry] = []
      entries.reserveCapacity(size)
      for i in 0..<size {
        entries.append(RawEntry(key: "key\(i)", value: "value\(i)", pos: "名詞"))
      }

      iter.setAvailable(true)
      iter.setEntries(entries)

      if size <= UserDictionaryStorage.maxEntrySize() {
        #expect(importIter(iter, &userDic) == .ok)
      } else {
        #expect(importIter(iter, &userDic) == .importTooManyWords)
      }

      let validSize = min(UserDictionaryStorage.maxEntrySize(), size)
      try #require(userDic.entries.count == validSize)
      for i in 0..<validSize {
        #expect(userDic.entries[i].key.utf8.elementsEqual(entries[i].key))
        #expect(userDic.entries[i].value.utf8.elementsEqual(entries[i].value))
        #expect(userDic.entries[i].pos == .noun)
      }
    }
  }

  @Test func importFromIteratorInvalidEntriesTest() {
    let iter = TestInputIterator()
    var userDic = UserDictionary()

    let kSizes = [10, 100, 1000]
    for size in kSizes {
      var entries: [RawEntry] = []
      entries.reserveCapacity(size)
      for i in 0..<size {
        var pos = ""
        if i % 2 == 0 {
          pos = "名詞"
        }
        entries.append(RawEntry(key: "key\(i)", value: "value\(i)", pos: pos))
      }

      iter.setAvailable(true)
      iter.setEntries(entries)

      #expect(importIter(iter, &userDic) == .importInvalidEntries)
      #expect(userDic.entries.count == size / 2)
    }
  }

  @Test func importFromIteratorDupTest() {
    let iter = TestInputIterator()
    iter.setAvailable(true)
    var userDic = UserDictionary()

    do {
      var entry = UserDictionary.Entry()
      entry.key = "aa"
      entry.value = "aa"
      entry.pos = .noun
      userDic.entries.append(entry)
    }

    var entries: [RawEntry] = []
    entries.append(RawEntry(key: "aa", value: "aa", pos: "名詞"))

    iter.setEntries(entries)

    #expect(importIter(iter, &userDic) == .ok)

    #expect(userDic.entries.count == 1)

    entries.append(RawEntry(key: "bb", value: "bb", pos: "名詞"))

    iter.setEntries(entries)

    #expect(importIter(iter, &userDic) == .ok)

    #expect(userDic.entries.count == 2)

    #expect(importIter(iter, &userDic) == .ok)

    #expect(userDic.entries.count == 2)
  }

  @Test func guessIMETypeTest() {
    #expect(Importer.guessIMEType("") == .numImes)

    #expect(Importer.guessIMEType("!Microsoft IME Dictionary Tool") == .msime)

    #expect(Importer.guessIMEType("!!ATOK_TANGO_TEXT_HEADER_1") == .atok)

    #expect(Importer.guessIMEType("!!DICUT10") == .numImes)

    #expect(Importer.guessIMEType("!!DICUT") == .numImes)

    #expect(Importer.guessIMEType("!!DICUT11") == .atok)

    #expect(Importer.guessIMEType("!!DICUT17") == .atok)

    #expect(Importer.guessIMEType("!!DICUT20") == .atok)

    #expect(Importer.guessIMEType("\"foo\",\"bar\",\"buz\"") == .kotoeri)

    #expect(Importer.guessIMEType("\"comment\"") == .kotoeri)

    #expect(Importer.guessIMEType("foo\tbar\tbuz") == .google)

    #expect(Importer.guessIMEType("foo\tbar") == .google)

    #expect(Importer.guessIMEType("# Gboard Dictionary Version:1") == .gboardV1)

    #expect(Importer.guessIMEType("foo") == .numImes)
  }

  @Test func determineFinalIMETypeTest() {
    #expect(Importer.determineFinalIMEType(.imeAutoDetect, .msime) == .msime)

    #expect(Importer.determineFinalIMEType(.imeAutoDetect, .atok) == .atok)

    #expect(Importer.determineFinalIMEType(.imeAutoDetect, .kotoeri) == .kotoeri)

    #expect(Importer.determineFinalIMEType(.imeAutoDetect, .gboardV1) == .gboardV1)

    #expect(Importer.determineFinalIMEType(.imeAutoDetect, .numImes) == .numImes)

    #expect(Importer.determineFinalIMEType(.google, .msime) == .google)

    #expect(Importer.determineFinalIMEType(.google, .atok) == .google)

    #expect(Importer.determineFinalIMEType(.google, .kotoeri) == .numImes)

    #expect(Importer.determineFinalIMEType(.msime, .msime) == .msime)

    #expect(Importer.determineFinalIMEType(.atok, .msime) == .numImes)

    #expect(Importer.determineFinalIMEType(.atok, .kotoeri) == .numImes)
  }

  @Test func guessEncodingTypeTest() {
    #expect(Importer.guessEncodingType("これはテストです。") == .utf8)
    #expect(Importer.guessEncodingType("私の名前は中野ですABC") == .utf8)
    #expect(Importer.guessEncodingType("ABCDEFG abcdefg") == .utf8)
    #expect(Importer.guessEncodingType("ハロー") == .utf8)

    // "よろしくお願いします" in Shift-JIS
    let kSjis1: [UInt8] = [
      0x82, 0xE6, 0x82, 0xEB, 0x82, 0xB5, 0x82, 0xAD, 0x82, 0xA8, 0x8A, 0xE8, 0x82, 0xA2, 0x82,
      0xB5, 0x82, 0xDC, 0x82, 0xB7,
    ]
    #expect(Importer.guessEncodingType(kSjis1) == .shiftJIS)

    // "東京" in Shift-JIS
    let kSjis2: [UInt8] = [0x93, 0x8C, 0x8B, 0x9E]
    #expect(Importer.guessEncodingType(kSjis2) == .shiftJIS)

    // BOM of UTF-16
    #expect(Importer.guessEncodingType([0xFF, 0xFE] as [UInt8]) == .utf16)

    // BOM of UTF-16
    #expect(Importer.guessEncodingType([0xFE, 0xFF] as [UInt8]) == .utf16)

    // BOM of UTF-8
    #expect(Importer.guessEncodingType([0xEF, 0xBB, 0xBF] as [UInt8]) == .utf8)
  }

  @Test func stringTextLineIterator() throws {
    let kTestData = [
      // Test for LF.
      "abcde\n" + "fghij\n" + "klmno",

      // Test for CR.
      "abcde\r" + "fghij\r" + "klmno",

      // Test for CRLF.
      "abcde\r\n" + "fghij\r\n" + "klmno",
    ]

    for data in kTestData {
      let iter = StringTextLineIterator(data)
      try #require(iter.isAvailable)
      #expect(try #require(iter.next()) == Array("abcde".utf8))
      try #require(iter.isAvailable)
      #expect(try #require(iter.next()) == Array("fghij".utf8))
      try #require(iter.isAvailable)
      #expect(try #require(iter.next()) == Array("klmno".utf8))
      #expect(!iter.isAvailable)
    }

    // Test empty line with CR / LF / CRLF.
    // Invalid empty line.
    // At the moment, \n\r is processed as two empty lines.
    for input in ["\r\rabcde", "\n\nabcde", "\r\n\r\nabcde", "\n\rabcde"] {
      let iter = StringTextLineIterator(bytes: Array(input.utf8))
      try #require(iter.isAvailable)
      #expect(try #require(iter.next()) == [])
      try #require(iter.isAvailable)
      #expect(try #require(iter.next()) == [])
      try #require(iter.isAvailable)
      #expect(try #require(iter.next()) == Array("abcde".utf8))
      #expect(!iter.isAvailable)
    }
  }

  // Swift-only: lines with invalid UTF-8 are rejected as invalid entries (as
  // the C++ ValidateEntry does on std::string), not repaired.
  @Test func importInvalidUtf8Test() throws {
    var input = Array("すずき\t鈴木\t人名\n".utf8)
    input += [0x93, 0x8C, 0x8B, 0x9E] + Array("\t東京\t地名\n".utf8)
    var userDic = UserDictionary()
    let iter = StringTextLineIterator(bytes: input)
    #expect(
      code { () throws(ExtendedErrorCode) in
        try Importer.importFromTextLineIterator(.google, iter, &userDic)
      } == .importInvalidEntries)
    try #require(userDic.entries.count == 1)
    #expect(userDic.entries[0].value == "鈴木")
  }

  // Swift-only: ATOK "$" marker, full-width POS normalization, and POSes
  // mapped to an invalid PosType (ignored in Mozc).
  @Test func convertEntryTest() {
    var to = UserDictionary.Entry()
    #expect(Importer.convertEntry(RawEntry(key: "アイ", value: "愛", pos: "名詞$"), &to))
    #expect(to.key == "あい")
    #expect(to.pos == .noun)
    #expect(Importer.convertEntry(RawEntry(key: "あい", value: "愛", pos: "名詞*", comment: "c"), &to))
    #expect(to.comment == "c")
    #expect(!Importer.convertEntry(RawEntry(key: "あい", value: "愛", pos: "ナ変動詞"), &to))
    #expect(!Importer.convertEntry(RawEntry(key: "あい", value: "愛", pos: "未知"), &to))
    #expect(!Importer.convertEntry(RawEntry(key: "あい", value: "愛", pos: ""), &to))
    #expect(!Importer.convertEntry(RawEntry(key: "", value: "愛", pos: "名詞"), &to))
  }
}
