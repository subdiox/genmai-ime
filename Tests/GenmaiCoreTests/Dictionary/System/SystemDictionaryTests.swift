// Port of mozc/src/dictionary/system/system_dictionary_test.cc (3.35.6354).
//
// The tests use the mock data manager's POS matcher and the first 100000
// lines of data/dictionary_oss/dictionary00.txt, as in C++
// (FLAGS_dictionary_test_size). Dictionaries are built in memory
// (SystemDictionary.Builder(image:)); LookupReverseIndex goes through a file
// as in C++. Small cost encoding is disabled unless a test enables it.
//
// Swift-only additions at the bottom check the real system dictionary in
// Data/genmai.data against the dictionary_oss sources.

import Foundation
import GenmaiBase
import Testing

@testable import GenmaiCore

private typealias Support = SystemDictionaryTestSupport

/// Returns true if they seem to be same.
private func compareTokensForLookup(_ a: Token, _ b: Token, _ reverse: Bool) -> Bool {
  let keyValueCheck =
    reverse
    ? (a.key.bytesEqual(b.value) && a.value.bytesEqual(b.key))
    : (a.key.bytesEqual(b.key) && a.value.bytesEqual(b.value))
  if !keyValueCheck {
    return false
  }
  if a.cost != b.cost {
    return false
  }
  let spellingMatch =
    (a.attributes & Token.Attribute.spellingCorrection) == (b.attributes & Token.Attribute.spellingCorrection)
  if !spellingMatch {
    return false
  }
  return a.lid == b.lid && a.rid == b.rid
}

private func tok(
  _ key: String, _ value: String, _ cost: Int = 0, _ lid: UInt16 = 0, _ rid: UInt16 = 0,
  _ attributes: Token.AttributesBitfield = Token.Attribute.none
) -> Token {
  Token(key: key, value: value, cost: cost, lid: lid, rid: rid, attributes: attributes)
}

private final class LookupPrefixTestCallback: SysDicCallbackBase {
  private(set) var result = Set<[String]>()

  override func onKey(_ key: String) -> DictionaryCallbackResult {
    if key == "かき" {
      return .traverseCull
    } else if key == "さ" {
      return .traverseNextKey
    } else if key == "た" {
      return .traverseDone
    }
    return .traverseContinue
  }

  override func onToken(_ key: String, _ actualKey: String, _ token: Token) -> DictionaryCallbackResult {
    result.insert([token.key, token.value])
    return .traverseContinue
  }
}

@Suite(.enabled(if: SystemDictionaryTestSupport.hasMockData, "mock_genmai.data is missing (run Tools/build_oracle.sh)"))
struct SystemDictionaryTests {
  private var textTokens: [Token] { Support.fixture?.tokens ?? [] }

  @Test func callback() throws {
    let tokens = [tok("star", "star"), tok("start", "start"), tok("starting", "starting")]
    let systemDic = try Support.buildSystemDictionary(tokens)

    do {
      let cb = SysDicRecordingCallback()
      systemDic.lookupPredictive("start", callback: cb)
      #expect(cb.actualKeys.count >= 1)
      #expect(cb.onKeyCount("start") == 1)
      #expect(cb.onActualKeyCount("start", "start", 0) == 1)
      #expect(cb.onTokenCount("start", "start") == 1)
    }
    do {
      let cb = SysDicRecordingCallback()
      systemDic.lookupExact("start", callback: cb)
      #expect(cb.keys == ["start"])
      #expect(cb.actualKeys.count == 1 && cb.onActualKeyCount("start", "start", 0) == 1)
      #expect(cb.tokenKeys.count == 1 && cb.onTokenCount("start", "start") == 1)
    }
    do {
      let cb = SysDicRecordingCallback()
      systemDic.lookupPrefix("start", callback: cb)
      #expect(cb.actualKeys.count >= 1)
      #expect(cb.onKeyCount("start") == 1)
      #expect(cb.onActualKeyCount("start", "start", 0) == 1)
      #expect(cb.onTokenCount("start", "start") == 1)
    }
  }

  @Test func hasValue() throws {
    var tokens: [Token] = []
    for i in 0..<4 {
      tokens.append(tok("きー\(i)", "バリュー\(i)"))
    }

    let kFull = "ｆｕｌｌ"
    let kHiragana = "ひらがな"
    let kKatakanaKey = "かたかな"
    let kKatakanaValue = "カタカナ"

    tokens.append(tok("Mozc", "Mozc"))  // Alphabet
    tokens.append(tok("upper", "UPPER"))  // Alphabet upper case
    tokens.append(tok("full", kFull))  // Alphabet full width
    tokens.append(tok(kHiragana, kHiragana))  // Hiragana
    tokens.append(tok(kKatakanaKey, kKatakanaValue))  // Katakana

    let systemDic = try Support.buildSystemDictionary(tokens)

    #expect(systemDic.hasValue("バリュー0"))
    #expect(systemDic.hasValue("バリュー1"))
    #expect(systemDic.hasValue("バリュー2"))
    #expect(systemDic.hasValue("バリュー3"))
    #expect(!systemDic.hasValue("バリュー4"))
    #expect(!systemDic.hasValue("バリュー5"))
    #expect(!systemDic.hasValue("バリュー6"))

    #expect(systemDic.hasValue("Mozc"))
    #expect(!systemDic.hasValue("mozc"))

    #expect(systemDic.hasValue("UPPER"))
    #expect(!systemDic.hasValue("upper"))

    #expect(systemDic.hasValue(kFull))
    #expect(!systemDic.hasValue("full"))

    #expect(systemDic.hasValue(kHiragana))
    #expect(!systemDic.hasValue("ヒラガナ\n"))

    #expect(systemDic.hasValue(kKatakanaValue))
    #expect(!systemDic.hasValue(kKatakanaKey))
  }

  @Test func normalWord() throws {
    let token = tok("あ", "亜", 100, 50, 70)
    let systemDic = try Support.buildSystemDictionary([token], Support.dictionaryTestSize)

    let callback = SysDicCollectTokenCallback()

    // Look up by exact key.
    systemDic.lookupPrefix(token.key, callback: callback)
    try #require(callback.tokens.count == 1)
    expectTokenEq(token, callback.tokens[0])

    // Look up by prefix.
    callback.clear()
    systemDic.lookupPrefix("あいう", callback: callback)
    try #require(callback.tokens.count == 1)
    expectTokenEq(token, callback.tokens[0])

    // Nothing should be looked up.
    callback.clear()
    systemDic.lookupPrefix("かきく", callback: callback)
    #expect(callback.tokens.isEmpty)
  }

  @Test func sameWord() throws {
    let tokens = [
      tok("あ", "亜", 100, 50, 70),
      tok("あ", "亜", 150, 100, 200),
      tok("あ", "あ", 100, 1000, 2000),
      tok("あ", "亜", 1000, 2000, 3000),
    ]
    let systemDic = try Support.buildSystemDictionary(tokens, Support.dictionaryTestSize)

    // All the tokens should be looked up.
    let callback = SysDicCollectTokenCallback()
    systemDic.lookupPrefix("あ", callback: callback)
    expectTokensEqUnordered(tokens, callback.tokens)
  }

  @Test func lookupAllWords() throws {
    let sourceTokens = textTokens
    let systemDic = try Support.buildSystemDictionary(sourceTokens, Support.dictionaryTestSize)

    // All the tokens should be looked up.
    var notFound = 0
    for token in sourceTokens {
      let callback = SysDicCheckTokenExistenceCallback(token)
      systemDic.lookupPrefix(token.key, callback: callback)
      if !callback.found {
        notFound += 1
        if notFound <= 10 {
          Issue.record("Token was not found: \(printToken(token))")
        }
      }
    }
    #expect(notFound == 0)
  }

  @Test func simpleLookupPrefix() throws {
    let k0 = "は"
    let k1 = "はひふへほ"
    let t0 = tok(k0, "aa")
    let t1 = tok(k1, "bb")

    let sourceTokens = [t0, t1] + textTokens
    let systemDic = try Support.buildSystemDictionary(sourceTokens, 100)

    // |t0| should be looked up from |k1|.
    let callback = SysDicCheckTokenExistenceCallback(t0)
    systemDic.lookupPrefix(k1, callback: callback)
    #expect(callback.found)
  }

  @Test func lookupPrefix() throws {
    // Set up a test dictionary.
    let kKeyValues: [(String, String)] = [
      ("あ", "亜"), ("あ", "安"), ("あ", "在"),
      ("あい", "愛"), ("あい", "藍"), ("あいう", "藍雨"),
      ("か", "可"), ("かき", "牡蠣"), ("かき", "夏季"),
      ("かきく", "柿久"), ("さ", "差"), ("さ", "左"),
      ("さし", "刺"), ("た", "田"), ("た", "多"),
      ("たち", "多値"), ("たちつ", "タチツ"), ("は", "葉"),
      ("は", "歯"), ("はひ", "ハヒ"), ("ば", "場"),
      ("はび", "波美"), ("ばび", "馬尾"), ("ばびぶ", "バビブ"),
    ]
    let tokens = kKeyValues.map { tok($0.0, $0.1) }
    let systemDic = try Support.buildSystemDictionary(tokens, kKeyValues.count)

    // Test for normal prefix lookup without key expansion.
    do {
      let callback = LookupPrefixTestCallback()
      systemDic.lookupPrefix("あい", callback: callback)
      let result = callback.result
      // "あ" -- "あい" should be found.
      for i in 0..<5 {
        #expect(result.contains([kKeyValues[i].0, kKeyValues[i].1]))
      }
      // The others should not be found.
      for i in 5..<kKeyValues.count {
        #expect(!result.contains([kKeyValues[i].0, kKeyValues[i].1]))
      }
    }

    // Test for normal prefix lookup without key expansion, but with culling
    // feature.
    do {
      let callback = LookupPrefixTestCallback()
      systemDic.lookupPrefix("かきく", callback: callback)
      let result = callback.result
      // Only "か" should be found as the callback doesn't traverse the subtree of
      // "かき" due to culling request from LookupPrefixTestCallback::OnKey().
      for kv in kKeyValues {
        #expect((kv.0 == "か") == result.contains([kv.0, kv.1]))
      }
    }

    // Test for TRAVERSE_NEXT_KEY.
    do {
      let callback = LookupPrefixTestCallback()
      systemDic.lookupPrefix("さしす", callback: callback)
      let result = callback.result
      // Only "さし" should be found as tokens for "さ" is skipped (see
      // LookupPrefixTestCallback::OnKey()).
      for kv in kKeyValues {
        #expect((kv.0 == "さし") == result.contains([kv.0, kv.1]))
      }
    }

    // Test for TRAVERSE_DONE.
    do {
      let callback = LookupPrefixTestCallback()
      systemDic.lookupPrefix("たちつ", callback: callback)
      // Nothing should be found as the traversal is immediately done after seeing
      // "た"; see LookupPrefixTestCallback::OnKey().
      #expect(callback.result.isEmpty)
    }

    // Test for prefix lookup with key expansion.
    do {
      let callback = LookupPrefixTestCallback()
      callback.setKanaModifierInsensitiveConversion(true)
      // Use kana modifier insensitive lookup
      systemDic.lookupPrefix("はひ", callback: callback)
      let result = callback.result
      let expected: Set<String> = ["は", "ば", "はひ", "ばひ", "はび", "ばび"]
      for kv in kKeyValues {
        let toBeFound = expected.contains(kv.0)
        #expect(result.contains([kv.0, kv.1]) == toBeFound, "\(kv)")
      }
    }
  }

  @Test func lookupPredictive() throws {
    let tokens = [
      tok("まみむめもや", "value0"),
      tok("まみむめもやゆよ", "value1"),
    ]
    // Build a dictionary with the above two tokens plus those from test data.
    let sourceTokens = tokens + textTokens
    let systemDic = try Support.buildSystemDictionary(sourceTokens, 10000)

    // All the tokens in |tokens| should be looked up by "まみむめも".
    let callback = SysDicCheckMultiTokensExistenceCallback(tokens)
    systemDic.lookupPredictive("まみむめも", callback: callback)
    #expect(callback.areAllFound())
  }

  @Test func lookupPredictiveKanaModifierInsensitiveLookup() throws {
    let tokens = [
      tok("がっこう", "学校"),
      tok("かっこう", "格好"),
    ]
    let systemDic = try Support.buildSystemDictionary(tokens, 100)

    let kKey = "かつこう"

    // Without Kana modifier insensitive lookup flag, nothing is looked up.
    let callback = SysDicCollectTokenCallback()
    systemDic.lookupPredictive(kKey, callback: callback)
    #expect(callback.tokens.isEmpty)

    // With Kana modifier insensitive lookup flag, every token is looked up.
    callback.clear()
    callback.setKanaModifierInsensitiveConversion(true)
    systemDic.lookupPredictive(kKey, callback: callback)
    expectTokensEqUnordered(tokens, callback.tokens)
  }

  @Test func lookupPredictiveCutOffEmulatingBFS() throws {
    let tokens = [
      tok("あい", "ai"),
      tok("あいうえお", "aiueo"),
    ]
    // Build a dictionary with the above two tokens plus those from test data.
    let sourceTokens = tokens + textTokens
    let systemDic = try Support.buildSystemDictionary(sourceTokens, 10000)

    // Since there are many entries starting with "あ" in test dictionary, it's
    // expected that "あいうえお" is not looked up because of longer key cut-off
    // mechanism.  However, "あい" is looked up as it's short.
    let callback = SysDicCheckMultiTokensExistenceCallback(tokens)
    systemDic.lookupPredictive("あ", callback: callback)
    #expect(callback.isFound(0))
    #expect(!callback.isFound(1))
  }

  @Test func lookupExact() throws {
    let k0 = "は"
    let k1 = "はひふへほ"
    let t0 = tok(k0, "aa")
    let t1 = tok(k1, "bb")
    let sourceTokens = [t0, t1] + textTokens
    let systemDic = try Support.buildSystemDictionary(sourceTokens, 100)

    // |t0| should not be looked up from |k1|.
    let callback0 = SysDicCheckTokenExistenceCallback(t0)
    systemDic.lookupExact(k1, callback: callback0)
    #expect(!callback0.found)
    // But |t1| should be found.
    let callback1 = SysDicCheckTokenExistenceCallback(t1)
    systemDic.lookupExact(k1, callback: callback1)
    #expect(callback1.found)

    // Nothing should be found from "hoge".
    let callbackHoge = SysDicCollectTokenCallback()
    systemDic.lookupExact("hoge", callback: callbackHoge)
    #expect(callbackHoge.tokens.isEmpty)
  }

  @Test func lookupReverse() throws {
    let tokens = [
      tok("ど", "ド", 1, 2, 3),
      tok("どらえもん", "ドラえもん", 1, 2, 3),
      tok("といざらす®", "トイザらス®", 1, 2, 3),
      // Both token[3] and token[4] will be encoded into 3 bytes.
      tok("ああああああ", "ああああああ", 32000, 1, 1),
      tok("ああああああ", "ああああああ", 32000, 1, 2),
      // token[5] will be encoded into 3 bytes.
      tok("いいいいいい", "いいいいいい", 32000, 1, 1),
      tok("どらえもん", "ドラえもん", 1, 2, 3, Token.Attribute.spellingCorrection),
      tok("こんさーと", "コンサート", 1, 1, 1),
      tok("ばーじょん", "バージョン", 1, 1, 1),
    ]
    let sourceTokens = tokens + textTokens
    let systemDic = try Support.buildSystemDictionary(sourceTokens, sourceTokens.count)

    let testSize = Swift.min(Support.dictionaryReverseLookupTestSize, sourceTokens.count)
    for sourceIndex in 0..<testSize {
      let sourceToken = sourceTokens[sourceIndex]
      let callback = SysDicCollectTokenCallback()
      systemDic.lookupReverse(sourceToken.value, callback: callback)

      var found = false
      for token in callback.tokens {
        // Make sure any of the key lengths of the lookup results
        // doesn't exceed the original key length.
        // It happened once
        // when called with "バージョン", returning "ヴァージョン".
        #expect(
          token.key.utf8.count <= sourceToken.value.utf8.count,
          "\(token.key):\(token.value)\t\(sourceToken.value)")
        if compareTokensForLookup(sourceToken, token, true) {
          found = true
        }
      }

      if sourceToken.attributes & Token.Attribute.spellingCorrection == Token.Attribute.spellingCorrection {
        #expect(!found, "Spelling correction token was retrieved:\(printToken(sourceToken))")
        if found {
          return
        }
      } else {
        #expect(found, "Failed to find \(sourceToken.key):\(sourceToken.value)")
        if !found {
          return
        }
      }
    }

    do {
      // test for non exact transliterated index string.
      // append "が"
      let key = tokens[7].value + "が"
      let callback = SysDicCollectTokenCallback()
      systemDic.lookupReverse(key, callback: callback)
      let found = callback.tokens.contains { compareTokensForLookup(tokens[7], $0, true) }
      #expect(found, "Missed token for non exact transliterated index \(key)")
    }
  }

  @Test func lookupReverseIndex() throws {
    let sourceTokens = textTokens
    let tempDir = try TempDirectory.default().createTempDirectory()
    defer { withExtendedLifetime(tempDir) {} }
    let dicFn = FileUtil.joinPath(tempDir.path, "mozc.dic")
    do {
      let builder = SystemDictionaryBuilder()
      builder.minKeyLengthToUseSmallCostEncoding = Int(Int32.max)
      builder.buildFromTokens(Array(sourceTokens.prefix(Support.dictionaryTestSize)))
      try builder.writeToFile(dicFn)
    }

    let systemDicWithoutIndex = try SystemDictionary.Builder(filename: dicFn).setOptions(.none).build()
    let systemDicWithIndex = try SystemDictionary.Builder(filename: dicFn)
      .setOptions(.enableReverseLookupIndex).build()

    for t in sourceTokens.prefix(Support.dictionaryReverseLookupTestSize) {
      let callback1 = SysDicCollectTokenCallback()
      let callback2 = SysDicCollectTokenCallback()
      systemDicWithoutIndex.lookupReverse(t.value, callback: callback1)
      systemDicWithIndex.lookupReverse(t.value, callback: callback2)

      let tokens1 = callback1.tokens
      let tokens2 = callback2.tokens
      try #require(tokens1.count == tokens2.count)
      for i in tokens1.indices {
        expectTokenEq(tokens1[i], tokens2[i])
      }
    }
  }

  @Test func lookupReverseWithCache() throws {
    let kDoraemon = "ドラえもん"

    var sourceToken = Token()
    sourceToken.key = "どらえもん"
    sourceToken.value = kDoraemon
    sourceToken.cost = 1
    sourceToken.lid = 2
    sourceToken.rid = 3
    let sourceTokens = [sourceToken] + textTokens
    let systemDic = try Support.buildSystemDictionary(sourceTokens, sourceTokens.count)
    systemDic.populateReverseLookupCache(kDoraemon)

    var targetToken = sourceToken
    swap(&targetToken.key, &targetToken.value)

    let callback = SysDicCheckTokenExistenceCallback(targetToken)
    systemDic.lookupReverse(kDoraemon, callback: callback)
    #expect(callback.found, "Could not find \(printToken(sourceToken))")
    systemDic.clearReverseLookupCache()
  }

  @Test func spellingCorrectionTokens() throws {
    let tokens = [
      tok("あぼがど", "アボカド", 1, 0, 2, Token.Attribute.spellingCorrection),
      tok("しゅみれーしょん", "シミュレーション", 1, 100, 3, Token.Attribute.spellingCorrection),
      tok("あきはばら", "秋葉原", 1000, 1, 2),
    ]
    let systemDic = try Support.buildSystemDictionary(tokens, tokens.count)

    for (i, token) in tokens.enumerated() {
      let callback = SysDicCheckTokenExistenceCallback(token)
      systemDic.lookupPrefix(token.key, callback: callback)
      #expect(callback.found, "Token \(i) was not found: \(printToken(token))")
    }
  }

  @Test func enableNoModifierTargetWithLoudsTrie() throws {
    let k0 = "かつ"
    let k1 = "かっこ"
    let k2 = "かつこう"
    let k3 = "かっこう"
    let k4 = "がっこう"

    let tokens = [tok(k0, "aa"), tok(k1, "bb"), tok(k2, "cc"), tok(k3, "dd"), tok(k4, "ee")]
    let sourceTokens = tokens + textTokens
    let systemDic = try Support.buildSystemDictionary(sourceTokens, 100)

    // Prefix search
    for (i, token) in tokens.enumerated() {
      let callback = SysDicCheckTokenExistenceCallback(token)
      callback.setKanaModifierInsensitiveConversion(true)
      // "かつこう" -> "かつ", "かっこ", "かつこう", "かっこう" and "がっこう"
      systemDic.lookupPrefix(k2, callback: callback)
      #expect(callback.found, "Token \(i) was not found: \(printToken(token))")
    }

    // Predictive searches
    do {
      // "かつ" -> "かつ", "かっこ", "かつこう", "かっこう" and "がっこう"
      let callback = SysDicCheckMultiTokensExistenceCallback(tokens)
      callback.setKanaModifierInsensitiveConversion(true)
      systemDic.lookupPredictive(k0, callback: callback)
      #expect(callback.areAllFound())
    }
    do {
      // "かっこ" -> "かっこ", "かっこう" and "がっこう"
      let callback = SysDicCheckMultiTokensExistenceCallback([tokens[1], tokens[3], tokens[4]])
      callback.setKanaModifierInsensitiveConversion(true)
      systemDic.lookupPredictive(k1, callback: callback)
      #expect(callback.areAllFound())
    }
  }

  @Test func noModifierForKanaEntries() throws {
    let t0 = tok("ていすてぃんぐ", "テイスティング")
    let t1 = tok("てすとです", "てすとです")

    let sourceTokens = [t0, t1] + textTokens
    let systemDic = try Support.buildSystemDictionary(sourceTokens, 100)

    // Lookup |t0| from "ていすていんぐ"
    let k = "ていすていんぐ"
    let callback = SysDicCheckTokenExistenceCallback(t0)
    callback.setKanaModifierInsensitiveConversion(true)
    systemDic.lookupPrefix(k, callback: callback)
    #expect(callback.found, "Not found: \(printToken(t0))")
  }

  @Test func doNotReturnNoModifierTargetWithLoudsTrie() throws {
    let k0 = "かつ"
    let k1 = "かっこ"
    let k2 = "かつこう"
    let k3 = "かっこう"
    let k4 = "がっこう"

    let tokens = [tok(k0, "aa"), tok(k1, "bb"), tok(k2, "cc"), tok(k3, "dd"), tok(k4, "ee")]
    let sourceTokens = tokens + textTokens
    let systemDic = try Support.buildSystemDictionary(sourceTokens, 100)

    // Prefix search
    do {
      // "かっこう" (k3) -> "かっこ" (k1) and "かっこう" (k3)
      // Make sure "がっこう" is not in the results when searched by "かっこう"
      for token in [tokens[1], tokens[3]] {
        let callback = SysDicCheckTokenExistenceCallback(token)
        systemDic.lookupPrefix(k3, callback: callback)
        #expect(callback.found, "Token is not found: \(printToken(token))")
      }
      for token in [tokens[0], tokens[2], tokens[4]] {
        let callback = SysDicCheckTokenExistenceCallback(token)
        systemDic.lookupPrefix(k3, callback: callback)
        #expect(!callback.found, "Token should not be found: \(printToken(token))")
      }
    }

    // Predictive search
    do {
      // "かっこ" -> "かっこ" and "かっこう"
      // Make sure "がっこう" is not in the results when searched by "かっこ"
      for token in [tokens[1], tokens[3]] {
        let callback = SysDicCheckTokenExistenceCallback(token)
        systemDic.lookupPredictive(k1, callback: callback)
        #expect(callback.found, "Token is not found: \(printToken(token))")
      }
      for token in [tokens[0], tokens[2], tokens[4]] {
        let callback = SysDicCheckTokenExistenceCallback(token)
        systemDic.lookupPredictive(k3, callback: callback)
        #expect(!callback.found, "Token should not be found: \(printToken(token))")
      }
    }
  }

  @Test func shouldNotUseSmallCostEncodingForHeteronyms() throws {
    let tokens = [
      tok("しょうろんぽう", "ショウロンポウ", 5948, 100, 100),
      tok("しょうろんぽう", "小籠包", 7692, 100, 100),
      tok("しょーろんぽう", "ショーロンポウ", 6092, 200, 200),
      tok("しょーろんぽう", "小籠包", 9000, 100, 100),
    ]
    // Uses the default FLAGS_min_key_length_to_use_small_cost_encoding (6).
    let systemDic = try Support.buildSystemDictionary(tokens, tokens.count, minKeyLength: 6)

    for (i, token) in tokens.enumerated() {
      let callback = SysDicCheckTokenExistenceCallback(token)
      systemDic.lookupPrefix(token.key, callback: callback)
      // The original token will not be found when the token is encoded with
      // small_cost_encoding
      #expect(callback.found, "Token \(i) was not found: \(printToken(token))")
    }
  }

  // MARK: - Swift-only

  // Small cost encoding drops the lower 8 bits of the cost.
  @Test func smallCostEncoding() throws {
    let token = tok("しょうろんぽう", "小籠包", 7692, 100, 100)
    let systemDic = try Support.buildSystemDictionary([token], 1, minKeyLength: 6)
    let callback = SysDicCollectTokenCallback()
    systemDic.lookupExact(token.key, callback: callback)
    try #require(callback.tokens.count == 1)
    #expect(callback.tokens[0].cost == 7692 & 0x7f00)
    #expect(systemDic.hasKey("しょうろんぽう"))
    #expect(!systemDic.hasKey("しょうろんぽ"))
  }

  // The image written by the builder is deterministic and re-readable from a
  // file.
  @Test func builderImageRoundTrip() throws {
    let tokens = Array(textTokens.prefix(2000))
    let image1 = Support.buildImage(tokens)
    let image2 = Support.buildImage(tokens)
    #expect(image1 == image2)
    let systemDic = try SystemDictionary.Builder(image: DataView(copying: image1)).build()
    for token in tokens.prefix(200) {
      let callback = SysDicCheckTokenExistenceCallback(token)
      systemDic.lookupExact(token.key, callback: callback)
      #expect(callback.found, "\(printToken(token))")
    }
  }
}

/// Lookups against the real system dictionary (Data/genmai.data), compared with
/// the dictionary_oss sources it is built from.
@Suite(.enabled(if: SystemDictionaryTestSupport.hasOssData, "Data/genmai.data is missing (run Tools/build_oracle.sh)"))
struct SystemDictionaryOssDataTests {
  static let dictionary: SystemDictionary? = {
    guard let dataManager = try? OssDataManager.create() else { return nil }
    return try? SystemDictionary.Builder(image: dataManager.getSystemDictionaryData()).build()
  }()

  /// (value, cost, lid, rid) of every line of dictionary_oss/dictionary0*.txt
  /// whose key is one of `keys`.
  static func sourceEntries(_ keys: Set<String>) throws -> [String: Set<[String]>] {
    var result: [String: Set<[String]>] = [:]
    for i in 0..<10 {
      let path = SystemDictionaryTestSupport.sourcePath("data", "dictionary_oss", "dictionary0\(i).txt")
      let text = try FileUtil.getContents(path)
      for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let tab = line.firstIndex(of: "\t") else { continue }
        let key = String(line[..<tab])
        guard keys.contains(key) else { continue }
        let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard cols.count >= 5 else { continue }
        // key lid rid cost value
        result[key, default: []].insert([cols[4], cols[3], cols[1], cols[2]])
      }
    }
    return result
  }

  private func entries(_ tokens: [Token]) -> Set<[String]> {
    Set(tokens.map { [$0.value, String($0.cost), String($0.lid), String($0.rid)] })
  }

  @Test func lookupExactWatashi() throws {
    let dic = try #require(Self.dictionary)
    let callback = SysDicCollectTokenCallback()
    dic.lookupExact("わたし", callback: callback)
    #expect(callback.tokens.contains { $0.value == "私" && $0.cost == 263 && $0.lid == 1902 && $0.rid == 1902 })
    #expect(callback.tokens.allSatisfy { $0.key == "わたし" })
    let expected = try Self.sourceEntries(["わたし"])["わたし"] ?? []
    #expect(entries(callback.tokens) == expected)
  }

  @Test func lookupPrefixKyouwa() throws {
    let dic = try #require(Self.dictionary)
    let callback = SysDicCollectTokenCallback()
    dic.lookupPrefix("きょうは", callback: callback)
    // 今日 (きょう) with the source cost / POS ids.
    #expect(callback.tokens.contains { $0.key == "きょう" && $0.value == "今日" && $0.cost == 121 && $0.lid == 1913 })
    let keys: Set<String> = ["き", "きょ", "きょう", "きょうは"]
    let source = try Self.sourceEntries(keys)
    for key in keys {
      let got = callback.tokens.filter { $0.key == key && $0.attributes & Token.Attribute.spellingCorrection == 0 }
      // Keys shorter than 6 characters never use the lossy small cost
      // encoding, so the tokens match the sources exactly.
      #expect(entries(got) == (source[key] ?? []), "key: \(key)")
    }
    // Prefixes are reported shortest first.
    let order = callback.tokens.map(\.key)
    #expect(order == order.sorted { $0.utf8.count < $1.utf8.count })
  }

  @Test func lookupPredictiveAndReverse() throws {
    let dic = try #require(Self.dictionary)
    let callback = SysDicCollectTokenCallback()
    dic.lookupPredictive("がっこ", callback: callback)
    #expect(callback.tokens.contains { $0.key == "がっこう" && $0.value == "学校" })
    #expect(callback.tokens.allSatisfy { $0.key.hasBytePrefix("がっこ") })

    let reverse = SysDicCollectTokenCallback()
    dic.lookupReverse("学校", callback: reverse)
    // Reverse lookup returns (key: word, value: reading).
    #expect(reverse.tokens.contains { $0.key == "学校" && $0.value == "がっこう" })

    #expect(dic.hasKey("がっこう"))
    #expect(dic.hasValue("学校"))
    #expect(!dic.hasValue("学校学校学校"))
  }

  // Oracle: 日本 (にほん) wcost 730, lid/rid 1928 in conversion_top10.txt.
  @Test func oracleNihon() throws {
    let dic = try #require(Self.dictionary)
    let callback = SysDicCollectTokenCallback()
    dic.lookupExact("にほん", callback: callback)
    #expect(callback.tokens.contains { $0.value == "日本" && $0.cost == 730 && $0.lid == 1928 && $0.rid == 1928 })
  }
}
