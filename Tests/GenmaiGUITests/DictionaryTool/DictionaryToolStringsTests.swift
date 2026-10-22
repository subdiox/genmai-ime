// Tests of the strings tables of the dictionary tool and the word register dialog views.

import Testing

@testable import GenmaiGUI

struct DictionaryToolStringsTests {
  @Test func everyKeyHasEnglishAndJapanese() {
    for key in DictionaryToolStrings.Key.allCases {
      #expect(DictionaryToolStrings.english[key] != nil, "missing English: \(key)")
      #expect(DictionaryToolStrings.japanese[key] != nil, "missing Japanese: \(key)")
    }
    for key in WordRegisterStrings.Key.allCases {
      #expect(WordRegisterStrings.english[key] != nil, "missing English: \(key)")
      #expect(WordRegisterStrings.japanese[key] != nil, "missing Japanese: \(key)")
    }
  }

  @Test func noAsciiEllipsisOrShortUser() {
    let texts =
      DictionaryToolStrings.Key.allCases.flatMap { key in
        [GUILanguage.english, .japanese].map { DictionaryToolStrings.text(key, language: $0) }
      }
      + WordRegisterStrings.Key.allCases.flatMap { key in
        [GUILanguage.english, .japanese].map { WordRegisterStrings.text(key, language: $0) }
      }
    for text in texts {
      #expect(!text.contains("..."), "\(text)")
      #expect(!text.contains("ユーザ") || text.contains("ユーザー"), "\(text)")
    }
  }

  @Test func wordCount() {
    #expect(DictionaryToolStrings.wordCount(1, language: .english) == "1 word")
    #expect(DictionaryToolStrings.wordCount(12, language: .english) == "12 words")
    #expect(DictionaryToolStrings.wordCount(0, language: .japanese) == "0 語")
  }
}
