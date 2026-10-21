// Port of mozc/src/dictionary/suffix_dictionary_test.cc (3.35.6354).

import Testing

@testable import GenmaiCore

@Suite(.enabled(if: DictionaryTestSupport.hasMockData, DictionaryTestSupport.mockDataMissing))
struct SuffixDictionaryTests {
  func makeDictionary() throws -> SuffixDictionary {
    let data = try DictionaryTestSupport.mockDataManager().getSuffixDictionaryData()
    return SuffixDictionary(data.keyArray, data.valueArray, data.tokenArray)
  }

  @Test func callback() throws {
    // Test SuffixDictionary with mock data.
    let dic = try makeDictionary()
    let mockCallback = MockCallback()
    dic.lookupPredictive("た", callback: mockCallback)
    #expect(mockCallback.onActualKeyCount >= 1)
  }

  @Test func lookupPredictive() throws {
    // Test SuffixDictionary with mock data.
    let dic = try makeDictionary()
    do {
      // Lookup with empty key.  All tokens are looked up.  Here, just verify the
      // result is nonempty and each token has valid data.
      let callback = CollectTokenCallback()
      dic.lookupPredictive("", callback: callback)
      #expect(!callback.tokens.isEmpty)
      for token in callback.tokens {
        #expect(!token.key.isEmpty)
        #expect(!token.value.isEmpty)
        #expect(0 < token.lid)
        #expect(0 < token.rid)
        #expect(token.attributes == Token.Attribute.suffixDictionary)
      }
    }
    do {
      // Non-empty prefix.
      let kPrefix = "た"
      let callback = CollectTokenCallback()
      dic.lookupPredictive(kPrefix, callback: callback)
      #expect(!callback.tokens.isEmpty)
      for token in callback.tokens {
        #expect(token.key.hasBytePrefix(kPrefix))
        #expect(!token.value.isEmpty)
        #expect(0 < token.lid)
        #expect(0 < token.rid)
        #expect(token.attributes == Token.Attribute.suffixDictionary)
      }
    }
  }
}
