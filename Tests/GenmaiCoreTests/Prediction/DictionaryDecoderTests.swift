// Port of mozc/src/prediction/dictionary_decoder_test.cc (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

@Suite(.enabled(if: predictionMockDataAvailable, "mock_genmai.data is missing"))
struct DictionaryDecoderTests {
  let config = PT.config()
  let request = Genmai_Commands_Request()
  var composer: Composer

  init() {
    composer = Composer(PT.tableFromFile("system://romanji-hiragana.tsv"), request, config)
  }

  private func initWithMockDictionary(_ mockDict: MockDictionary) throws -> DictionaryDecoder {
    DictionaryDecoder(try PredictionTestModules.mock(dictionary: mockDict))
  }

  private func initWithDefaultMock() throws -> DictionaryDecoder {
    let dict = KeyedMockDictionary()
    dict.predictive.on("ぐーぐるあ", kv: [("ぐーぐるあどせんす", "グーグルアドセンス")])
    dict.predictive.on(
      "ぐーぐる",
      kv: [
        ("ぐーぐる", "グーグル"),
        ("ぐーぐるあどせんす", "グーグルアドセンス"),
      ])
    dict.prefix.on("ぐーぐる", kv: [("ぐーぐる", "グーグル")])
    dict.prefix.on("ぐーぐるあ", kv: [("ぐーぐる", "グーグル")])
    return try initWithMockDictionary(dict.mock)
  }

  private mutating func createPredictionRequest(_ key: String) -> ConversionRequest {
    composer.reset()
    PT.insertInputSequence(key, &composer)
    return ConversionRequestBuilder()
      .setComposer(composer)
      .setKey(key)
      .setRequestType(.prediction)
      .build()
  }

  private mutating func createSuggestionRequest(_ key: String) -> ConversionRequest {
    composer.reset()
    PT.insertInputSequence(key, &composer)
    return ConversionRequestBuilder()
      .setComposer(composer)
      .setKey(key)
      .setRequestType(.suggestion)
      .build()
  }

  @Test func emptyRequestReturnsEmpty() throws {
    let decoder = try initWithDefaultMock()
    let request = ConversionRequest()
    var results: [PredictionResult] = []
    decoder.aggregateUnigram(request, &results)
    #expect(results.isEmpty)
  }

  @Test mutating func aggregateUnigramCandidate() throws {
    let decoder = try initWithDefaultMock()
    let kKey = "ぐーぐるあ"
    let convreq = createSuggestionRequest(kKey)
    var results: [PredictionResult] = []
    decoder.aggregateUnigram(convreq, &results)
    #expect(!results.isEmpty)

    for result in results {
      #expect((result.attributes & Attribute.unigram) != 0)
      #expect(result.key.hasBytePrefix(kKey))
    }
  }

  @Test mutating func aggregatePrefixCandidates() throws {
    let decoder = try initWithDefaultMock()
    let kKey = "ぐーぐるあ"
    let convreq = createPredictionRequest(kKey)
    var results: [PredictionResult] = []
    decoder.aggregatePrefix(convreq, &results)
    #expect(!results.isEmpty)
    for r in results {
      #expect((r.attributes & Attribute.partiallyKeyConsumed) != 0)
      #expect(r.consumedKeySize != 0)
    }
  }

  @Test mutating func bigramTest() throws {
    let dict = KeyedMockDictionary()
    dict.prefix.on("ぐーぐる", kv: [("ぐーぐる", "グーグル")])
    dict.prefix.on("あどせんす", kv: [("あどせんす", "アドセンス")])
    dict.predictive.on("ぐーぐる", kv: [("ぐーぐるあどせんす", "グーグルアドセンス")])
    let decoder = try initWithMockDictionary(dict.mock)

    var historyResult = PredictionResult()
    historyResult.key = "ぐーぐる"
    historyResult.value = "グーグル"

    composer.reset()
    PT.insertInputSequence("あ", &composer)

    let convreq = ConversionRequestBuilder()
      .setComposer(composer)
      .setHistoryResult(historyResult)
      .setKey("あ")
      .setRequestType(.suggestion)
      .build()

    var results: [PredictionResult] = []
    decoder.aggregateBigram(convreq, &results)
    #expect(!results.isEmpty)
    for result in results {
      #expect((result.attributes & Attribute.bigram) != 0)
    }
  }

  @Test mutating func userDictionaryPredictionFilter() throws {
    let kHiraganaA = "あ"
    let kHiraganaAA = "ああ"
    let kCost = MockDictionary.kDefaultCost
    let kPosId = MockDictionary.kDefaultPosId

    let aTokens = [
      PT.makeToken(kHiraganaA, "a", kCost, kPosId, kPosId, Token.Attribute.none),
      PT.makeToken(kHiraganaA, "a0", kCost, kPosId, kPosId, Token.Attribute.none),
      PT.makeToken(kHiraganaA, "a1", kCost, kPosId, kPosId, Token.Attribute.none),
      PT.makeToken(kHiraganaA, "aaa", kCost, kPosId, kPosId, Token.Attribute.userDictionary),
    ]
    let aaTokens = [
      PT.makeToken(kHiraganaAA, "bbb", 0, 0, 0, Token.Attribute.userDictionary)
    ]

    let dict = KeyedMockDictionary()
    dict.predictive.on(kHiraganaA, tokens: aTokens)
    dict.predictive.on(kHiraganaAA, tokens: aaTokens)
    let decoder = try initWithMockDictionary(dict.mock)

    func isUserDictionaryResult(_ res: PredictionResult) -> Bool {
      (res.attributes & Attribute.userDictionary) != 0
    }

    do {
      // Test prediction from input あ.
      let convreq = createPredictionRequest(kHiraganaA)
      var results: [PredictionResult] = []
      decoder.aggregateUnigramForMixedConversion(convreq, &results)

      // Check if "aaa" is not filtered.
      #expect(
        results.contains {
          $0.key == kHiraganaA && $0.value == "aaa" && isUserDictionaryResult($0)
        })

      // "bbb" is looked up from input "あ" but it will be filtered because it
      // is from user dictionary with unknown POS ID.
      #expect(
        !results.contains {
          $0.key == kHiraganaAA && $0.value == "bbb" && isUserDictionaryResult($0)
        })
    }

    do {
      // Test prediction from input ああ.
      let convreq = createPredictionRequest(kHiraganaAA)
      var results: [PredictionResult] = []
      decoder.aggregateUnigramForMixedConversion(convreq, &results)

      // Check if "aaa" is not found as its key is あ.
      #expect(
        !results.contains {
          $0.key == kHiraganaA && $0.value == "aaa" && isUserDictionaryResult($0)
        })

      // Unlike the above case for "あ", "bbb" is now found because input key is
      // exactly "ああ".
      #expect(
        results.contains {
          $0.key == kHiraganaAA && $0.value == "bbb" && isUserDictionaryResult($0)
        })
    }
  }
}
