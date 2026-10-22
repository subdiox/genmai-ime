// Port of mozc/src/dictionary/system/value_dictionary_test.cc (3.35.6354).

import GenmaiBase
import GenmaiStorage
import Testing

@testable import GenmaiCore

@Suite(.enabled(if: SystemDictionaryTestSupport.hasMockData, "mock_genmai.data is missing (run Tools/build_oracle.sh)"))
final class ValueDictionaryTests {
  private let posMatcher: PosMatcher
  private let codec = SystemDictionaryCodec()
  private let loudsTrieBuilder = LoudsTrieBuilder()
  private let loudsTrie = LoudsTrie()
  private var image = DataView()

  init() throws {
    posMatcher = SystemDictionaryTestSupport.fixture!.posMatcher
  }

  private func addValue(_ value: String) {
    loudsTrieBuilder.add(codec.encodeValue(value))
  }

  private func buildValueDictionary() -> ValueDictionary {
    loudsTrieBuilder.build()
    image = DataView(copying: loudsTrieBuilder.image)
    guard let base = image.baseAddress else {
      preconditionFailure("the trie image is not empty")
    }
    loudsTrie.open(base)
    return ValueDictionary(posMatcher, loudsTrie)
  }

  private func initToken(_ value: String) -> Token {
    let id = posMatcher.getSuggestOnlyWordId()
    return Token(key: value, value: value, cost: 10000, lid: id, rid: id, attributes: Token.Attribute.none)
  }

  @Test func callback() {
    addValue("star")
    addValue("start")
    addValue("starting")
    let dictionary = buildValueDictionary()

    do {
      let cb = SysDicRecordingCallback()
      dictionary.lookupPredictive("start", callback: cb)
      #expect(cb.actualKeys.count >= 1)
      #expect(cb.onKeyCount("start") == 1)
      #expect(cb.onActualKeyCount("start", "start", 0) == 1)
      #expect(cb.onTokenCount("start", "start") == 1)
    }
    do {
      let cb = SysDicRecordingCallback()
      dictionary.lookupExact("start", callback: cb)
      #expect(cb.keys == ["start"])
      #expect(cb.actualKeys.count == 1 && cb.onActualKeyCount("start", "start", 0) == 1)
      #expect(cb.tokenKeys.count == 1 && cb.onTokenCount("start", "start") == 1)
    }
  }

  @Test func hasValue() {
    addValue("we")
    addValue("war")
    addValue("word")
    addValue("world")
    let dictionary = buildValueDictionary()

    // ValueDictionary is supposed to use the same data with SystemDictionary
    // and SystemDictionary::HasValue should return the same result with
    // ValueDictionary::HasValue.  So we can skip the actual logic of HasValue
    // and return just false.
    #expect(!dictionary.hasValue("we"))
    #expect(!dictionary.hasValue("war"))
    #expect(!dictionary.hasValue("word"))
    #expect(!dictionary.hasValue("world"))

    #expect(!dictionary.hasValue("hoge"))
    #expect(!dictionary.hasValue("piyo"))
  }

  @Test func lookupPredictive() {
    addValue("google")
    addValue("we")
    addValue("war")
    addValue("word")
    addValue("world")

    // These values are not fetched.
    addValue("あいう")
    addValue("東京")
    addValue("アイウ")
    let dictionary = buildValueDictionary()

    // Reading fields are irrelevant to value dictionary.  Prepare actual tokens
    // that are to be looked up.
    let tokenWe = initToken("we")
    let tokenWar = initToken("war")
    let tokenWord = initToken("word")
    let tokenWorld = initToken("world")

    do {
      let callback = SysDicCollectTokenCallback()
      dictionary.lookupPredictive("", callback: callback)
      #expect(callback.tokens.isEmpty)
    }
    do {
      let callback = SysDicCollectTokenCallback()
      dictionary.lookupPredictive("w", callback: callback)
      expectTokensEqUnordered([tokenWe, tokenWar, tokenWord, tokenWorld], callback.tokens)
    }
    do {
      let callback = SysDicCollectTokenCallback()
      dictionary.lookupPredictive("wo", callback: callback)
      expectTokensEqUnordered([tokenWord, tokenWorld], callback.tokens)
    }
    do {
      let callback = SysDicCollectTokenCallback()
      dictionary.lookupPredictive("ho", callback: callback)
      #expect(callback.tokens.isEmpty)
    }
    do {
      let callback = SysDicCollectTokenCallback()
      dictionary.lookupPredictive("あ", callback: callback)
      #expect(callback.tokens.isEmpty)

      dictionary.lookupPredictive("東", callback: callback)
      #expect(callback.tokens.isEmpty)

      dictionary.lookupPredictive("ア", callback: callback)
      #expect(callback.tokens.isEmpty)
    }
  }

  @Test func lookupExact() throws {
    addValue("we")
    addValue("war")
    addValue("word")
    let dictionary = buildValueDictionary()

    let callback = SysDicCollectTokenCallback()
    dictionary.lookupExact("war", callback: callback)
    try #require(callback.tokens.count == 1)
    #expect(callback.tokens[0].value == "war")
  }
}
