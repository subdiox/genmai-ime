// Port of mozc/src/dictionary/dictionary_impl_test.cc (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private typealias UserEntry = Genmai_UserDictionary_UserDictionary.Entry

private struct DictionaryData {
  let userDictionary: UserDictionary
  let posMatcher: PosMatcher
  let dictionary: any DictionaryInterface
}

private func createDictionaryData() throws -> DictionaryData {
  let dataManager = try DictionaryTestSupport.mockDataManager()
  let posMatcher = PosMatcher(dataManager.getPosMatcherData())
  let sysDict = try SystemDictionary.Builder(image: dataManager.getSystemDictionaryData()).build()
  let valDict = ValueDictionary(posMatcher, sysDict.valueTrie)
  let userPosData = dataManager.getUserPosData()
  let userPos = UserPos(userPosData.tokenArray, userPosData.stringArray)
  let userDictionary = UserDictionary(userPos, posMatcher)
  let dictionary = DictionaryImpl(sysDict, valDict, userDictionary, posMatcher)
  return DictionaryData(userDictionary: userDictionary, posMatcher: posMatcher, dictionary: dictionary)
}

private final class CheckKeyValueExistenceCallback: DictionaryCallback {
  let key: String
  let value: String
  private(set) var found = false

  init(_ key: String, _ value: String) {
    self.key = key
    self.value = value
  }

  func onToken(_ key: String, _ actualKey: String, _ token: Token) -> DictionaryCallbackResult {
    if token.key.bytesEqual(self.key) && token.value.bytesEqual(value) {
      found = true
      return .traverseDone
    }
    return .traverseContinue
  }
}

private final class CheckSpellingExistenceCallback: DictionaryCallback {
  let key: String
  let value: String
  private(set) var found = false

  init(_ key: String, _ value: String) {
    self.key = key
    self.value = value
  }

  func onToken(_ key: String, _ actualKey: String, _ token: Token) -> DictionaryCallbackResult {
    if token.key.bytesEqual(self.key) && token.value.bytesEqual(value)
      && (token.attributes & Token.Attribute.spellingCorrection) != 0
    {
      found = true
      return .traverseDone
    }
    return .traverseContinue
  }
}

private final class CheckZipCodeExistenceCallback: DictionaryCallback {
  let key: String
  let value: String
  let posMatcher: PosMatcher
  private(set) var found = false

  init(_ key: String, _ value: String, _ posMatcher: PosMatcher) {
    self.key = key
    self.value = value
    self.posMatcher = posMatcher
  }

  func onToken(_ key: String, _ actualKey: String, _ token: Token) -> DictionaryCallbackResult {
    if token.key.bytesEqual(self.key) && token.value.bytesEqual(value)
      && posMatcher.isZipcode(token.lid)
    {
      found = true
      return .traverseDone
    }
    return .traverseContinue
  }
}

private final class CheckEnglishT13nCallback: DictionaryCallback {
  let key: String
  let value: String
  private(set) var found = false

  init(_ key: String, _ value: String) {
    self.key = key
    self.value = value
  }

  func onToken(_ key: String, _ actualKey: String, _ token: Token) -> DictionaryCallbackResult {
    if token.key.bytesEqual(self.key) && token.value.bytesEqual(value)
      && Util.isEnglishTransliteration(token.value)
    {
      found = true
      return .traverseDone
    }
    return .traverseContinue
  }
}

/// Pair of DictionaryInterface's lookup method and query text.
private struct LookupMethodAndQuery {
  let lookupMethod: (any DictionaryInterface, String, ConversionOptions, any DictionaryCallback) -> Void
  let query: String

  static func prefix(_ query: String) -> LookupMethodAndQuery {
    LookupMethodAndQuery(lookupMethod: { $0.lookupPrefix($1, options: $2, callback: $3) }, query: query)
  }

  static func predictive(_ query: String) -> LookupMethodAndQuery {
    LookupMethodAndQuery(lookupMethod: { $0.lookupPredictive($1, options: $2, callback: $3) }, query: query)
  }
}

@Suite(.serialized, .enabled(if: DictionaryTestSupport.hasMockData, DictionaryTestSupport.mockDataMissing))
struct DictionaryImplTests {
  var config = Genmai_Config_Config()

  init() {
    ConfigHandler.getDefaultConfig(&config)
  }

  static func convReq(_ config: Genmai_Config_Config) -> ConversionRequest {
    ConversionRequestBuilder().setConfig(config).build()
  }

  @Test func wordSuppressionTest() throws {
    try SystemUtil.withTempUserProfile { _ in
      let data = try createDictionaryData()
      let d = data.dictionary

      let kKey = "ぐーぐる"
      let kValue = "グーグル"

      let kTestPair: [LookupMethodAndQuery] = [.prefix("ぐーぐるは"), .predictive("ぐーぐ")]

      // First add (kKey, kValue) to the suppression dictionary; thus it should not
      // be looked up.
      do {
        var storage = Genmai_UserDictionary_UserDictionaryStorage()
        var entry = UserEntry()
        entry.key = kKey
        entry.value = kValue
        entry.pos = .suppressionWord
        var dic = Genmai_UserDictionary_UserDictionary()
        dic.entries.append(entry)
        storage.dictionaries.append(dic)
        data.userDictionary.load(storage)
        #expect(data.userDictionary.hasSuppressedEntries())
      }
      let convreq1 = Self.convReq(config)
      for pair in kTestPair {
        let callback = CheckKeyValueExistenceCallback(kKey, kValue)
        pair.lookupMethod(d, pair.query, convreq1.options(), callback)
        #expect(!callback.found)
      }

      do {
        let storage = Genmai_UserDictionary_UserDictionaryStorage()
        data.userDictionary.load(storage)
        #expect(!data.userDictionary.hasSuppressedEntries())
      }
      let convreq2 = Self.convReq(config)
      for pair in kTestPair {
        let callback = CheckKeyValueExistenceCallback(kKey, kValue)
        pair.lookupMethod(d, pair.query, convreq2.options(), callback)
        #expect(callback.found)
      }
    }
  }

  @Test func disableSpellingCorrectionTest() throws {
    var config = self.config
    try SystemUtil.withTempUserProfile { _ in
      let data = try createDictionaryData()
      let d = data.dictionary

      // "あぼがど" -> "アボカド", which is in the test dictionary.
      let kKey = "あぼがど"
      let kValue = "アボカド"

      let kTestPair: [LookupMethodAndQuery] = [.prefix(kKey), .predictive("あぼ")]

      // The spelling correction entry (kKey, kValue) should be found if spelling
      // correction flag is set in the config.
      config.useSpellingCorrection = true
      let convreq1 = Self.convReq(config)
      for pair in kTestPair {
        let callback = CheckSpellingExistenceCallback(kKey, kValue)
        pair.lookupMethod(d, pair.query, convreq1.options(), callback)
        #expect(callback.found)
      }

      // Without the flag, it should be suppressed.
      config.useSpellingCorrection = false
      let convreq2 = Self.convReq(config)
      for pair in kTestPair {
        let callback = CheckSpellingExistenceCallback(kKey, kValue)
        pair.lookupMethod(d, pair.query, convreq2.options(), callback)
        #expect(!callback.found)
      }
    }
  }

  @Test func disableZipCodeConversionTest() throws {
    var config = self.config
    try SystemUtil.withTempUserProfile { _ in
      let data = try createDictionaryData()
      let d = data.dictionary

      // "100-0000" -> "東京都千代田区", which is in the test dictionary.
      let kKey = "100-0000"
      let kValue = "東京都千代田区"

      let kTestPair: [LookupMethodAndQuery] = [.prefix(kKey), .predictive("100")]

      // The zip code entry (kKey, kValue) should be found if the flag is set in the
      // config.
      config.useZipCodeConversion = true
      let convreq1 = Self.convReq(config)
      for pair in kTestPair {
        let callback = CheckZipCodeExistenceCallback(kKey, kValue, data.posMatcher)
        pair.lookupMethod(d, pair.query, convreq1.options(), callback)
        #expect(callback.found)
      }

      // Without the flag, it should be suppressed.
      config.useZipCodeConversion = false
      let convreq2 = Self.convReq(config)
      for pair in kTestPair {
        let callback = CheckZipCodeExistenceCallback(kKey, kValue, data.posMatcher)
        pair.lookupMethod(d, pair.query, convreq2.options(), callback)
        #expect(!callback.found)
      }
    }
  }

  @Test func disableT13nConversionTest() throws {
    var config = self.config
    try SystemUtil.withTempUserProfile { _ in
      let data = try createDictionaryData()
      let d = data.dictionary

      let kKey = "ぐーぐる"
      let kValue = "Google"

      let kTestPair: [LookupMethodAndQuery] = [.prefix(kKey), .predictive("ぐー")]

      // The T13N entry (kKey, kValue) should be found if the flag is set in the
      // config.
      config.useT13NConversion = true
      let convreq1 = Self.convReq(config)
      for pair in kTestPair {
        let callback = CheckEnglishT13nCallback(kKey, kValue)
        pair.lookupMethod(d, pair.query, convreq1.options(), callback)
        #expect(callback.found)
      }

      // Without the flag, it should be suppressed.
      config.useT13NConversion = false
      let convreq2 = Self.convReq(config)
      for pair in kTestPair {
        let callback = CheckEnglishT13nCallback(kKey, kValue)
        pair.lookupMethod(d, pair.query, convreq2.options(), callback)
        #expect(!callback.found)
      }
    }
  }

  @Test func lookupComment() throws {
    try SystemUtil.withTempUserProfile { _ in
      let data = try createDictionaryData()
      let d = data.dictionary

      do {
        var storage = Genmai_UserDictionary_UserDictionaryStorage()
        var entry = UserEntry()
        entry.key = "key"
        entry.value = "comment"
        entry.comment = "UserDictionaryStub"
        entry.pos = .noun
        var dic = Genmai_UserDictionary_UserDictionary()
        dic.entries.append(entry)
        storage.dictionaries.append(dic)
        data.userDictionary.load(storage)
      }

      let convreq = Self.convReq(config)
      #expect(d.lookupComment("key", "value", options: convreq.options()) == nil)

      // If key or value is "comment", UserDictionaryStub returns
      // "UserDictionaryStub" as comment.
      #expect(d.lookupComment("key", "comment", options: convreq.options()) == "UserDictionaryStub")
    }
  }

  @Test func hasKeyValue() throws {
    try SystemUtil.withTempUserProfile { _ in
      let data = try createDictionaryData()
      let d = data.dictionary

      #expect(d.hasKey("きょうと"))
      #expect(d.hasValue("京都"))
      #expect(!d.hasKey("__きょうと__"))
      #expect(!d.hasValue("__京都__"))
    }
  }
}
