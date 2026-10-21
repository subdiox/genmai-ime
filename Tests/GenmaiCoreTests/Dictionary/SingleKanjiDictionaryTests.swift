// Port of mozc/src/dictionary/single_kanji_dictionary_test.cc (3.35.6354).

import GenmaiBase
import Testing

@testable import GenmaiCore

@Suite(.enabled(if: DictionaryTestSupport.hasMockData, DictionaryTestSupport.mockDataMissing))
struct SingleKanjiDictionaryTests {
  func makeDictionary() throws -> SingleKanjiDictionary {
    SingleKanjiDictionary(try DictionaryTestSupport.mockDataManager().getSingleKanjiRewriterData())
  }

  @Test func generateDescription() throws {
    try SystemUtil.withTempUserProfile { _ in
      let dictionary = try makeDictionary()
      // variant of "亜".
      #expect(dictionary.generateDescription("亞") == "亜の旧字体")
      // no entry
      #expect(dictionary.generateDescription("あ") == nil)
      #expect(dictionary.generateDescription("ABC") == nil)
      #expect(dictionary.generateDescription("") == nil)
    }
  }

  @Test func lookupNounPrefixEntries() throws {
    try SystemUtil.withTempUserProfile { _ in
      let dictionary = try makeDictionary()
      do {
        let entries = dictionary.lookupNounPrefixEntries("ご")
        #expect(!entries.isEmpty)
        for entry in entries {
          #expect(!entry.value.isEmpty)
          #expect(entry.cost == 0 || entry.cost == 1)
        }
      }
      do {
        // no entry
        #expect(dictionary.lookupNounPrefixEntries("てすと").isEmpty)
        #expect(dictionary.lookupNounPrefixEntries("").isEmpty)
      }
    }
  }

  @Test func lookupKanjiEntries() throws {
    try SystemUtil.withTempUserProfile { _ in
      let dictionary = try makeDictionary()
      // Bytewise comparison: Swift `==` treats the CJK compatibility ideograph
      // U+FA19 as canonically equal to U+795E.
      func contains(_ entries: [String], _ value: String) -> Bool {
        entries.contains { $0.bytesEqual(value) }
      }
      do {
        let entries = dictionary.lookupKanjiEntries("かみ", true)
        #expect(!entries.isEmpty)
        #expect(contains(entries, "神"))
        // 神︀ SVS character.
        #expect(contains(entries, "\u{795E}\u{FE00}"))
        // 神 CJK compat ideograph.
        #expect(!contains(entries, "\u{FA19}"))
      }
      do {
        let entries = dictionary.lookupKanjiEntries("かみ", false)
        #expect(!entries.isEmpty)
        #expect(contains(entries, "神"))
        // 神︀ SVS character.
        #expect(!contains(entries, "\u{795E}\u{FE00}"))
        // 神 CJK compat ideograph.
        #expect(contains(entries, "\u{FA19}"))
      }
      do {
        var entries = dictionary.lookupKanjiEntries("", false)
        #expect(entries.isEmpty)
        entries = dictionary.lookupKanjiEntries("unknown reading", false)
        #expect(entries.isEmpty)
      }
    }
  }
}
