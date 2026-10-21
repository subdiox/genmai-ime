// Port of mozc/src/dictionary/user_pos_test.cc (3.35.6354).

import GenmaiProtocol
import Testing

@testable import GenmaiCore

@Suite(.enabled(if: DictionaryTestSupport.hasMockData, DictionaryTestSupport.mockDataMissing))
struct UserPosTests {
  typealias PosType = Genmai_UserDictionary_UserDictionary.PosType
  let userPos: UserPos

  init() throws {
    let data = try DictionaryTestSupport.mockDataManager().getUserPosData()
    userPos = UserPos(data.tokenArray, data.stringArray)
  }

  @Test func userPosBasicTest() {
    let posList = userPos.getPosList()
    #expect(!posList.isEmpty)
    // test contains
    #expect(posList.contains("名詞サ変"))
    #expect(posList.contains("サジェストのみ"))
    #expect(posList.contains("短縮よみ"))
    #expect(posList.contains("抑制単語"))
    #expect(posList.contains("品詞なし"))
    for pos in posList {
      #expect((userPos.getPosIds(pos) ?? 0) > 0)
    }
    #expect(userPos.getPosIds("__ERROR__") == nil)
  }

  @Test func userPosGetTokensTest() throws {
    let posList = userPos.getPosList()
    let posType0 = try #require(UserPos.toPosType(posList[0]))
    #expect(userPos.getTokens("", "test", posType0).isEmpty)
    #expect(userPos.getTokens("test", "", posType0).isEmpty)
    // GetTokens("test", "test", ToPosType("")): an invalid PosType is not
    // representable in Swift (toPosType returns nil).
    #expect(UserPos.toPosType("") == nil)
    #expect(!userPos.getTokens("test", "test", posType0).isEmpty)

    // http://b/2674666
    #expect(!userPos.getTokens("あか", "赤", .adjective).isEmpty)

    for pos in posList {
      let posType = try #require(UserPos.toPosType(pos))
      #expect(!userPos.getTokens("test", "test", posType).isEmpty)
    }
  }

  @Test func conjugationTest() {
    var tokens1 = userPos.getTokens("わら", "嗤", .waGroup1Verb)
    var tokens2 = userPos.getTokens("わらう", "嗤う", .waGroup1Verb)
    #expect(!tokens1.isEmpty)
    #expect(!tokens2.isEmpty)
    #expect(tokens1.count == tokens2.count)
    for i in 0..<min(tokens1.count, tokens2.count) {
      #expect(tokens1[i].key == tokens2[i].key)
      #expect(tokens1[i].value == tokens2[i].value)
      #expect(tokens1[i].id == tokens2[i].id)
    }

    tokens1 = userPos.getTokens("おそれ", "惧れ", .group2Verb)
    tokens2 = userPos.getTokens("おそれる", "惧れる", .group2Verb)
    #expect(tokens1.count == tokens2.count)
    for i in 0..<min(tokens1.count, tokens2.count) {
      #expect(tokens1[i].key == tokens2[i].key)
      #expect(tokens1[i].value == tokens2[i].value)
      #expect(tokens1[i].id == tokens2[i].id)
    }
  }

  @Test func swapToken() {
    var token1 = UserPos.Token()
    token1.key = "key1"
    token1.value = "value1"
    token1.id = 1
    token1.rawPosType = 1
    var token2 = UserPos.Token()
    token2.key = "key2"
    token2.value = "value2"
    token2.id = 2
    token2.rawPosType = 2
    swap(&token1, &token2)
    #expect(token1.key == "key2")
    #expect(token1.value == "value2")
    #expect(token1.id == 2)
    #expect(token1.rawPosType == 2)
    #expect(token2.key == "key1")
    #expect(token2.value == "value1")
    #expect(token2.id == 1)
    #expect(token2.rawPosType == 1)
  }

  @Test func toPosType() {
    #expect(UserPos.toPosType("品詞なし") == .noPos)
    #expect(UserPos.toPosType("サジェストのみ") == .suggestionOnly)
    #expect(UserPos.toPosType("動詞ワ行五段") == .waGroup1Verb)
    #expect(UserPos.toPosType("抑制単語") == .suppressionWord)
  }

  @Test func getStringPosType() {
    #expect(UserPos.getStringPosType(.noPos) == "品詞なし")
    #expect(UserPos.getStringPosType(.suggestionOnly) == "サジェストのみ")
    #expect(UserPos.getStringPosType(.waGroup1Verb) == "動詞ワ行五段")
    #expect(UserPos.getStringPosType(.suppressionWord) == "抑制単語")
  }

  @Test func getCostFromPosTypeWithPenalty() {
    // NOUN base cost is 2500 (kStandardCost). With penalty 346: 2500 + 346 =
    // 2846.
    #expect(UserPos.getCostFromPosType(.noun, 346) == 2846)
    // ABBREVIATION always returns 200 regardless of cost_penalty.
    #expect(UserPos.getCostFromPosType(.abbreviation, 0) == 200)
    #expect(UserPos.getCostFromPosType(.abbreviation, 346) == 200)
    #expect(UserPos.getCostFromPosType(.abbreviation, 2500) == 200)
    #expect(UserPos.getCostFromPosType(.abbreviation, 4605) == 200)
    // When cost is 0 in user_pos.def (e.g. verbs/adjectives), default cost 5000
    // is returned without penalty.
    #expect(UserPos.getCostFromPosType(.waGroup1Verb, 346) == 5000)
    // Lower base-cost POS types (e.g. SYMBOL = 2000, PERSONAL_NAME = 1500)
    // gradually phase out their discount as cost_penalty approaches 2500.
    #expect(UserPos.getCostFromPosType(.symbol, 0) == 2000)
    // At penalty = 1250 (half of 2500), effective_base_cost = 2000 + 500 / 2 =
    // 2250, total = 2250 + 1250 = 3500.
    #expect(UserPos.getCostFromPosType(.symbol, 1250) == 3500)
    // At penalty = 2500, all non-zero POS types (except ABBREVIATION) converge
    // to 5000.
    #expect(UserPos.getCostFromPosType(.symbol, 2500) == 5000)
    #expect(UserPos.getCostFromPosType(.personalName, 2500) == 5000)
    #expect(UserPos.getCostFromPosType(.sentenceEndingParticle, 2500) == 5000)
    #expect(UserPos.getCostFromPosType(.noun, 2500) == 5000)
    // Above penalty = 2500 (e.g. N = 10,000 -> penalty = 4605), all scale as
    // 2500 + cost_penalty = 7105.
    #expect(UserPos.getCostFromPosType(.symbol, 4605) == 7105)
    #expect(UserPos.getCostFromPosType(.noun, 4605) == 7105)
  }

  @Test func posTypeRoundTrip() throws {
    for pos in userPos.getPosList() {
      let posType = try #require(UserPos.toPosType(pos))
      #expect(UserPos.getStringPosType(posType) == pos)
    }
  }
}
