// Port of mozc/src/prediction/user_history_predictor_test.cc (3.35.6354),
// part 3 (RomanFuzzyPrefixMatch .. JoinedSegmentsTestDesktop). See
// UserHistoryPredictorTests.swift for the conventions and
// UserHistoryPredictorTestSupport.swift for the fixture.

import Foundation
import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private typealias Fixture = UserHistoryPredictorTestFixture
private typealias MatchType = UserHistoryPredictor.MatchType

private struct Part3LookupTestData {
  let entryKey: String
  let expectResult: Bool
}

private struct Part3MatchTypeTestData {
  let target: String
  let expectType: MatchType
}

/// `expanded->LookUpPrefix(key, &value, ...)` returning (found, value).
private func part3LookUpPrefix(_ trie: Trie<String>, _ key: String) -> (Bool, String?) {
  var value: String? = nil
  var keyLength = 0
  var hasSubtrie = false
  let found = trie.lookUpPrefix(key, &value, &keyLength, &hasSubtrie)
  return (found, value)
}

/// All prefixes kKey.substr(0, i) for i in [0, size) (ASCII keys).
private func part3Prefixes(_ key: String) -> [String] {
  (0..<key.utf8.count).map { String(key.byteSubstring(from: 0, length: $0)) }
}

@Suite(.scopedConfigEnvironment) struct UserHistoryPredictorTestPart3 {
  @Test func romanFuzzyPrefixMatch() async {
    let match: (String, String) -> Bool = { UserHistoryPredictor.romanFuzzyPrefixMatch($0, $1) }
    // same
    #expect(!match("abc", "abc"))
    #expect(!match("a", "a"))

    // exact prefix
    #expect(!match("abc", "a"))
    #expect(!match("abc", "ab"))
    #expect(!match("abc", ""))

    // swap
    #expect(match("ab", "ba"))
    #expect(match("abfoo", "bafoo"))
    #expect(match("fooab", "fooba"))
    #expect(match("fooabfoo", "foobafoo"))

    // swap + prefix
    #expect(match("fooabfoo", "fooba"))

    // deletion
    #expect(match("abcd", "acd"))
    #expect(match("abcd", "bcd"))

    // deletion + prefix
    #expect(match("abcdf", "acd"))
    #expect(match("abcdfoo", "bcd"))

    // voice sound mark
    #expect(match("gu-guru", "gu^guru"))
    #expect(match("gu-guru", "gu=guru"))
    #expect(match("gu-guru", "gu^gu"))
    #expect(!match("gu-guru", "gugu"))

    // Invalid
    #expect(!match("", ""))
    #expect(!match("", "a"))
    #expect(!match("abcde", "defe"))
  }

  @Test func maybeRomanMisspelledKey() async {
    let f: (String) -> Bool = { UserHistoryPredictor.maybeRomanMisspelledKey($0) }
    #expect(f("こんぴゅーｔ"))
    #expect(f("こんぴゅーt"))
    #expect(!f("こんぴゅーた"))
    #expect(f("ぱｓこん"))
    #expect(!f("ぱそこん"))
    #expect(f("おねがいしまうｓ"))
    #expect(!f("おねがいします"))
    #expect(f("いんた=ねっと"))
    #expect(!f("ｔ"))
    #expect(f("ーｔ"))
    #expect(!f("おｎがいしまうｓ"))
    // Two unknowns
    #expect(!f("お＆がい＄しまう"))
    // One alpha and one unknown
    #expect(!f("お＆がいしまうｓ"))
  }

  @Test func getRomanMisspelledKey() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }

    f.config.preeditMethod = .roman

    func convreq(_ key: String) -> ConversionRequest {
      ConversionRequestBuilder()
        .setConfigView(f.config)
        .setKey(key)
        .build()
    }

    #expect(UserHistoryPredictor.getRomanMisspelledKey(convreq("")) == "")

    #expect(UserHistoryPredictor.getRomanMisspelledKey(convreq("おねがいしまうs")) == "onegaisimaus")

    #expect(UserHistoryPredictor.getRomanMisspelledKey(convreq("おねがいします")) == "")

    f.config.preeditMethod = .kana

    #expect(UserHistoryPredictor.getRomanMisspelledKey(convreq("おねがいしまうs")) == "")

    #expect(UserHistoryPredictor.getRomanMisspelledKey(convreq("おねがいします")) == "")
  }

  @Test func romanFuzzyLookupEntry() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictor()
    var entry = UserHistoryPredictor.Entry()
    let results = UserHistoryPredictor.EntryPriorityQueue()

    entry.key = ""
    #expect(!predictor.romanFuzzyLookupEntry("", entry, results))

    entry.key = "よろしく"
    #expect(predictor.romanFuzzyLookupEntry("yorosku", entry, results))
    #expect(predictor.romanFuzzyLookupEntry("yrosiku", entry, results))
    #expect(predictor.romanFuzzyLookupEntry("yorsiku", entry, results))
    #expect(!predictor.romanFuzzyLookupEntry("yrsk", entry, results))
    #expect(!predictor.romanFuzzyLookupEntry("yorosiku", entry, results))

    entry.key = "ぐーぐる"
    #expect(predictor.romanFuzzyLookupEntry("gu=guru", entry, results))
    #expect(!predictor.romanFuzzyLookupEntry("gu-guru", entry, results))
    #expect(!predictor.romanFuzzyLookupEntry("g=guru", entry, results))
  }

  @Test func expandedLookupRoman() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictor()
    var entry = UserHistoryPredictor.Entry()
    let results = UserHistoryPredictor.EntryPriorityQueue()

    // Roman
    // preedit: "あｋ"
    // request_key: "あｋ"
    // key_base: "あ"
    // key_expanded: "か","き","く","け", "こ"
    let expanded = Trie<String>()
    expanded.addEntry("か", "")
    expanded.addEntry("き", "")
    expanded.addEntry("く", "")
    expanded.addEntry("け", "")
    expanded.addEntry("こ", "")

    let kTests1: [Part3LookupTestData] = [
      .init(entryKey: "", expectResult: false), .init(entryKey: "あか", expectResult: true),
      .init(entryKey: "あき", expectResult: true), .init(entryKey: "あかい", expectResult: true),
      .init(entryKey: "あまい", expectResult: false), .init(entryKey: "あ", expectResult: false),
      .init(entryKey: "さか", expectResult: false), .init(entryKey: "さき", expectResult: false),
      .init(entryKey: "さかい", expectResult: false), .init(entryKey: "さまい", expectResult: false),
      .init(entryKey: "さ", expectResult: false),
    ]

    let convreq = ConversionRequestBuilder().build()

    // with expanded
    for t in kTests1 {
      entry.key = t.entryKey
      #expect(
        predictor.lookupEntry(convreq, "あｋ", "あ", expanded, entry, nil, false, results)
          == t.expectResult, "\(t.entryKey)")
    }

    // only expanded
    // preedit: "k"
    // request_key: ""
    // key_base: ""
    // key_expanded: "か","き","く","け", "こ"

    let kTests2: [Part3LookupTestData] = [
      .init(entryKey: "", expectResult: false), .init(entryKey: "か", expectResult: true),
      .init(entryKey: "き", expectResult: true), .init(entryKey: "かい", expectResult: true),
      .init(entryKey: "まい", expectResult: false), .init(entryKey: "も", expectResult: false),
    ]

    for t in kTests2 {
      entry.key = t.entryKey
      #expect(
        predictor.lookupEntry(convreq, "", "", expanded, entry, nil, false, results)
          == t.expectResult, "\(t.entryKey)")
    }
  }

  @Test func expandedLookupKana() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictor()
    var entry = UserHistoryPredictor.Entry()
    let results = UserHistoryPredictor.EntryPriorityQueue()

    // Kana
    // preedit: "あし"
    // request_key: "あし"
    // key_base: "あ"
    // key_expanded: "し","じ"
    let expanded = Trie<String>()
    expanded.addEntry("し", "")
    expanded.addEntry("じ", "")

    let kTests1: [Part3LookupTestData] = [
      .init(entryKey: "", expectResult: false), .init(entryKey: "あ", expectResult: false),
      .init(entryKey: "あし", expectResult: true), .init(entryKey: "あじ", expectResult: true),
      .init(entryKey: "あしかゆい", expectResult: true),
      .init(entryKey: "あじうまい", expectResult: true),
      .init(entryKey: "あまにがい", expectResult: false),
      .init(entryKey: "あめ", expectResult: false), .init(entryKey: "まし", expectResult: false),
      .init(entryKey: "まじ", expectResult: false),
      .init(entryKey: "ましなあじ", expectResult: false),
      .init(entryKey: "まじうまい", expectResult: false),
      .init(entryKey: "ままにがい", expectResult: false),
      .init(entryKey: "まめ", expectResult: false),
    ]

    let convreq = ConversionRequestBuilder().build()

    // with expanded
    for t in kTests1 {
      entry.key = t.entryKey
      #expect(
        predictor.lookupEntry(convreq, "あし", "あ", expanded, entry, nil, false, results)
          == t.expectResult, "\(t.entryKey)")
    }

    // only expanded
    // request_key: "し"
    // key_base: ""
    // key_expanded: "し","じ"
    let kTests2: [Part3LookupTestData] = [
      .init(entryKey: "", expectResult: false), .init(entryKey: "し", expectResult: true),
      .init(entryKey: "じ", expectResult: true), .init(entryKey: "しかうまい", expectResult: true),
      .init(entryKey: "じゅうかい", expectResult: true), .init(entryKey: "ま", expectResult: false),
      .init(entryKey: "まめ", expectResult: false),
    ]

    for t in kTests2 {
      entry.key = t.entryKey
      #expect(
        predictor.lookupEntry(convreq, "し", "", expanded, entry, nil, false, results)
          == t.expectResult, "\(t.entryKey)")
    }
  }

  @Test func expandedLookupExact() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictor()
    var entry = UserHistoryPredictor.Entry()
    let results = UserHistoryPredictor.EntryPriorityQueue()

    let kTestData = ["よ", "よろ", "よろし", "よろしく"]

    let convreq = ConversionRequestBuilder().build()

    // prefix match.
    let kExactMatchOnly = true

    for entryKey in kTestData {
      entry.key = entryKey
      for queryKey in kTestData {
        let expecetd = entryKey.hasBytePrefix(queryKey)
        #expect(
          predictor.lookupEntry(
            convreq, queryKey, queryKey, nil, entry, nil, !kExactMatchOnly, results) == expecetd)
      }
    }

    // Exact match
    for entryKey in kTestData {
      entry.key = entryKey
      for queryKey in kTestData {
        let expecetd = entryKey.bytesEqual(queryKey)
        #expect(
          predictor.lookupEntry(
            convreq, queryKey, queryKey, nil, entry, nil, kExactMatchOnly, results) == expecetd)
      }
    }
  }

  @Test func getMatchTypeFromInputRoman() async {
    // Roman
    // preedit: "あｋ"
    // request_key: "あ"
    // key_base: "あ"
    // key_expanded: "か","き","く","け", "こ"
    let expanded = Trie<String>()
    expanded.addEntry("か", "か")
    expanded.addEntry("き", "き")
    expanded.addEntry("く", "く")
    expanded.addEntry("け", "け")
    expanded.addEntry("こ", "こ")

    let kTests1: [Part3MatchTypeTestData] = [
      .init(target: "", expectType: .noMatch),
      .init(target: "い", expectType: .noMatch),
      .init(target: "あ", expectType: .rightPrefixMatch),
      .init(target: "あい", expectType: .noMatch),
      .init(target: "あか", expectType: .leftPrefixMatch),
      .init(target: "あかい", expectType: .leftPrefixMatch),
    ]

    for t in kTests1 {
      #expect(
        UserHistoryPredictor.getMatchTypeFromInput("あ", "あ", expanded, t.target) == t.expectType,
        "\(t.target)")
    }

    // only expanded
    // preedit: "ｋ"
    // request_key: ""
    // key_base: ""
    // key_expanded: "か","き","く","け", "こ"
    let kTests2: [Part3MatchTypeTestData] = [
      .init(target: "", expectType: .noMatch),
      .init(target: "い", expectType: .noMatch),
      .init(target: "いか", expectType: .noMatch),
      .init(target: "か", expectType: .leftPrefixMatch),
      .init(target: "かいがい", expectType: .leftPrefixMatch),
    ]

    for t in kTests2 {
      #expect(
        UserHistoryPredictor.getMatchTypeFromInput("", "", expanded, t.target) == t.expectType,
        "\(t.target)")
    }
  }

  @Test func getMatchTypeFromInputKana() async {
    // Kana
    // preedit: "あし"
    // request_key: "あし"
    // key_base: "あ"
    // key_expanded: "し","じ"
    let expanded = Trie<String>()
    expanded.addEntry("し", "し")
    expanded.addEntry("じ", "じ")

    let kTests1: [Part3MatchTypeTestData] = [
      .init(target: "", expectType: .noMatch),
      .init(target: "い", expectType: .noMatch),
      .init(target: "いし", expectType: .noMatch),
      .init(target: "あ", expectType: .rightPrefixMatch),
      .init(target: "あし", expectType: .exactMatch),
      .init(target: "あじ", expectType: .leftPrefixMatch),
      .init(target: "あした", expectType: .leftPrefixMatch),
      .init(target: "あじしお", expectType: .leftPrefixMatch),
    ]

    for t in kTests1 {
      #expect(
        UserHistoryPredictor.getMatchTypeFromInput("あし", "あ", expanded, t.target) == t.expectType,
        "\(t.target)")
    }

    // only expanded
    // preedit: "し"
    // request_key: "し"
    // key_base: ""
    // key_expanded: "し","じ"
    let kTests2: [Part3MatchTypeTestData] = [
      .init(target: "", expectType: .noMatch),
      .init(target: "い", expectType: .noMatch),
      .init(target: "し", expectType: .exactMatch),
      .init(target: "じ", expectType: .leftPrefixMatch),
      .init(target: "しじみ", expectType: .leftPrefixMatch),
      .init(target: "じかん", expectType: .leftPrefixMatch),
    ]

    for t in kTests2 {
      #expect(
        UserHistoryPredictor.getMatchTypeFromInput("し", "", expanded, t.target) == t.expectType,
        "\(t.target)")
    }
  }

  @Test func getInputKeyFromSegmentsRoman() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    _ = f.table.loadFromFile("system://romanji-hiragana.tsv")
    let segmentsProxy = SegmentsProxy()

    let convreq = f.initSegmentsFromInputSequence("gu-g", segmentsProxy)
    let (requestKey, base, expanded) = UserHistoryPredictor.getInputKeyFromRequest(convreq)
    #expect(requestKey == "ぐーｇ")
    #expect(base == "ぐー")
    let trie = try #require(expanded)
    let (found, value) = part3LookUpPrefix(trie, "ぐ")
    #expect(found)
    #expect(value == "ぐ")
  }

  @Test func getInputKeyFromSegmentsRomanRandom() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    _ = f.table.loadFromFile("system://romanji-hiragana.tsv")
    let segmentsProxy = SegmentsProxy()
    var random = Random()

    for _ in 0..<1000 {
      f.composer.reset()
      let input = random.utf8StringRandomLen(
        4, UInt32(UInt8(ascii: " ")), UInt32(UInt8(ascii: "~")))
      let convreq = f.initSegmentsFromInputSequence(input, segmentsProxy)
      _ = UserHistoryPredictor.getInputKeyFromRequest(convreq)
    }
  }

  // Found by random test.
  // request_key != base by composer modification.
  @Test func getInputKeyFromSegmentsShouldNotCrash() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    _ = f.table.loadFromFile("system://romanji-hiragana.tsv")
    let segmentsProxy = SegmentsProxy()

    do {
      let convreq = f.initSegmentsFromInputSequence("8,+", segmentsProxy)
      _ = UserHistoryPredictor.getInputKeyFromRequest(convreq)
    }
  }

  @Test func getInputKeyFromSegmentsRomanN() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    _ = f.table.loadFromFile("system://romanji-hiragana.tsv")
    let segmentsProxy = SegmentsProxy()

    do {
      let convreq = f.initSegmentsFromInputSequence("n", segmentsProxy)
      let (requestKey, base, expanded) = UserHistoryPredictor.getInputKeyFromRequest(convreq)
      #expect(requestKey == "ｎ")
      #expect(base == "")
      let trie = try #require(expanded)
      let (found, value) = part3LookUpPrefix(trie, "な")
      #expect(found)
      #expect(value == "な")
    }

    f.composer.reset()
    segmentsProxy.clear()
    do {
      let convreq = f.initSegmentsFromInputSequence("nn", segmentsProxy)
      let (requestKey, base, expanded) = UserHistoryPredictor.getInputKeyFromRequest(convreq)
      #expect(requestKey == "ん")
      #expect(base == "ん")
      #expect(expanded == nil)
    }

    f.composer.reset()
    segmentsProxy.clear()
    do {
      let convreq = f.initSegmentsFromInputSequence("n'", segmentsProxy)
      let (requestKey, base, expanded) = UserHistoryPredictor.getInputKeyFromRequest(convreq)
      #expect(requestKey == "ん")
      #expect(base == "ん")
      #expect(expanded == nil)
    }

    f.composer.reset()
    segmentsProxy.clear()
    do {
      let convreq = f.initSegmentsFromInputSequence("n'n", segmentsProxy)
      let (requestKey, base, expanded) = UserHistoryPredictor.getInputKeyFromRequest(convreq)
      #expect(requestKey == "んｎ")
      #expect(base == "ん")
      let trie = try #require(expanded)
      let (found, value) = part3LookUpPrefix(trie, "な")
      #expect(found)
      #expect(value == "な")
    }
  }

  @Test func getInputKeyFromSegmentsFlickN() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    _ = f.table.loadFromFile("system://flick-hiragana.tsv")
    let segmentsProxy = SegmentsProxy()

    do {
      let convreq = f.initSegmentsFromInputSequence("/", segmentsProxy)
      let (requestKey, base, expanded) = UserHistoryPredictor.getInputKeyFromRequest(convreq)
      #expect(requestKey == "ん")
      #expect(base == "")
      let trie = try #require(expanded)
      let (found, value) = part3LookUpPrefix(trie, "ん")
      #expect(found)
      #expect(value == "ん")
    }
  }

  @Test func getInputKeyFromSegments12KeyN() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    _ = f.table.loadFromFile("system://12keys-hiragana.tsv")
    let segmentsProxy = SegmentsProxy()

    do {
      let convreq = f.initSegmentsFromInputSequence("わ00", segmentsProxy)
      let (requestKey, base, expanded) = UserHistoryPredictor.getInputKeyFromRequest(convreq)
      #expect(requestKey == "ん")
      #expect(base == "")
      let trie = try #require(expanded)
      let (found, value) = part3LookUpPrefix(trie, "ん")
      #expect(found)
      #expect(value == "ん")
    }
  }

  @Test func getInputKeyFromSegmentsKana() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    _ = f.table.loadFromFile("system://kana.tsv")
    let segmentsProxy = SegmentsProxy()

    let convreq = f.initSegmentsFromInputSequence("あか", segmentsProxy)

    do {
      let (requestKey, base, expanded) = UserHistoryPredictor.getInputKeyFromRequest(convreq)
      #expect(requestKey == "あか")
      #expect(base == "あ")
      let trie = try #require(expanded)
      let (found, value) = part3LookUpPrefix(trie, "が")
      #expect(found)
      #expect(value == "が")
    }
  }

  @Test func realtimeConversionInnerSegment() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    for mixedConversion in [true, false] {
      let predictor = f.getUserHistoryPredictorWithClearedHistory()

      let segmentsProxy = SegmentsProxy()
      var results: [PredictionResult] = []

      f.request.mixedConversion = mixedConversion

      do {
        let kKey = "わたしのなまえはなかのです"
        let kValue = "私の名前は中野です"
        let convreq1 = f.setUpInputForPrediction(kKey, segmentsProxy)
        segmentsProxy.addCandidate(0, kValue)
        // "わたしの, 私の", "わたし, 私"
        segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 12, 6, 9, 3)
        // "なまえは, 名前は", "なまえ, 名前"
        segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 12, 9, 9, 6)
        // "なかのです, 中野です", "なかの, 中野"
        segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 15, 12, 9, 6)
        predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

        let entry = predictor.storage.mutableLookup(kKey, kValue)
        #expect(!entry.isNull)
      }
      segmentsProxy.clear()

      let convreq2 = f.setUpInputForPrediction("なかの", segmentsProxy)
      results = predictor.predict(convreq2)
      #expect(!results.isEmpty)
      #expect(Fixture.findCandidateByValue("中野", results) != nil)
      #expect(Fixture.findCandidateByValue("中野です", results) == nil)
      segmentsProxy.clear()

      let convreq3 = f.setUpInputForPrediction("なかので", segmentsProxy)
      results = predictor.predict(convreq3)
      #expect(!results.isEmpty)
      #expect(Fixture.findCandidateByValue("中野です", results) != nil)

      segmentsProxy.clear()
      let convreq4 = f.setUpInputForPrediction("なまえ", segmentsProxy)
      results = predictor.predict(convreq4)
      #expect(!results.isEmpty)
      #expect(Fixture.findCandidateByValue("名前", results) != nil)
      // Do not suggest the phrase ends with [content_word + function_word].
      #expect(Fixture.findCandidateByValue("名前は", results) == nil)
      #expect(Fixture.findCandidateByValue("名前は中野です", results) == nil)
      if mixedConversion {
        // prefer exact match.
        #expect(Fixture.findCandidateByValue("名前は中野", results) == nil)
      } else {
        // prefer prediction.
        #expect(Fixture.findCandidateByValue("名前は中野", results) != nil)
      }
    }
  }

  @Test func zeroQueryFromRealtimeConversion() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()
    f.request.mixedConversion = true

    let segmentsProxy = SegmentsProxy()
    do {
      let kKey = "わたしのなまえはなかのです"
      let kValue = "私の名前は中野です"
      let convreq = f.setUpInputForPrediction(kKey, segmentsProxy)
      segmentsProxy.addCandidate(0, kValue)
      // "わたしの, 私の", "わたし, 私"
      segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 12, 6, 9, 3)
      // "なまえは, 名前は", "なまえ, 名前"
      segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 12, 9, 9, 6)
      // "なかのです, 中野です", "なかの, 中野"
      segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 15, 12, 9, 6)
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }
    segmentsProxy.clear()

    let convreq2 = f.setUpInputForConversion("わたしの", segmentsProxy)
    segmentsProxy.addCandidate(0, "私の")
    predictor.finish(convreq2, segmentsProxy.makeLearningResults(), kRevertId)
    segmentsProxy.setHistoryType(0)

    f.request.zeroQuerySuggestion = true
    let convreq3 = f.setUpInputForSuggestionWithHistory("", "わたしの", "私の", segmentsProxy)
    let results = predictor.predict(convreq3)
    #expect(!results.isEmpty)
    #expect(Fixture.findCandidateByValue("名前", results) != nil)
  }

  @Test func longCandidateForMobile() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    RequestTestUtil.fillMobileRequest(&f.request)

    let segmentsProxy = SegmentsProxy()
    for _ in 0..<3 {
      let kKey = "よろしくおねがいします"
      let kValue = "よろしくお願いします"
      let convreq = f.setUpInputForPrediction(kKey, segmentsProxy)
      segmentsProxy.addCandidate(0, kValue)
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
      segmentsProxy.clear()
    }

    let convreq = f.setUpInputForPrediction("よろ", segmentsProxy)
    let results = predictor.predict(convreq)
    #expect(!results.isEmpty)
    #expect(Fixture.findCandidateByValue("よろしくお願いします", results) != nil)
  }

  @Test func insertNextEntry() async {
    func insertNextEntry(_ fps: [UInt64], _ newFp: UInt64) -> [UInt64] {
      var e = UserHistoryPredictor.Entry()
      for fp in fps {
        e.nextEntryFps.append(fp)
      }
      UserHistoryPredictor.insertNextEntry(newFp, &e)
      return e.nextEntryFps
    }

    #expect(insertNextEntry([], 10) == [10])
    #expect(insertNextEntry([1], 10) == [1, 10])
    #expect(insertNextEntry([1, 10], 10) == [1, 10])
    #expect(insertNextEntry([1, 10, 20], 10) == [1, 20, 10])

    // Remove dups.
    #expect(insertNextEntry([1, 10, 10, 20], 10) == [1, 20, 10])
    #expect(insertNextEntry([1, 10, 20, 10], 10) == [1, 20, 10])
    #expect(insertNextEntry([10, 10, 10], 10) == [10])

    // Exceeds the capacity.
    #expect(insertNextEntry([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 10) == [5, 6, 7, 8, 9, 10])
  }

  @Test func eraseNextEntries() async throws {
    var e = UserHistoryPredictor.Entry()
    e.nextEntryFps.append(100)
    e.nextEntryFps.append(10)
    e.nextEntryFps.append(30)
    e.nextEntryFps.append(10)
    e.nextEntryFps.append(100)

    UserHistoryPredictor.eraseNextEntries(1234, &e)
    #expect(e.nextEntryFps.count == 5)

    UserHistoryPredictor.eraseNextEntries(30, &e)
    try #require(e.nextEntryFps.count == 4)
    for i in 0..<4 {
      #expect(e.nextEntryFps[i] != 30)
    }

    UserHistoryPredictor.eraseNextEntries(10, &e)
    try #require(e.nextEntryFps.count == 2)
    for i in 0..<2 {
      #expect(e.nextEntryFps[i] != 10)
    }

    UserHistoryPredictor.eraseNextEntries(100, &e)
    #expect(e.nextEntryFps.count == 0)
  }

  @Test func removeNgramChain() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    // Set up the following chain of next entries:
    // ("abc", "ABC")
    // (  "a",   "A") --- ("b", "B") --- ("c", "C")
    let abc = Fixture.insertEntry(predictor, "abc", "ABC")
    let a = Fixture.insertEntry(predictor, "a", "A")
    let b = Fixture.appendEntry(predictor, "b", "B", a)
    let c = Fixture.appendEntry(predictor, "c", "C", b)

    let entries = [abc, a, b, c]

    // RemoveNgramChain(key, value, *entry): the Swift port takes a mutable
    // snapshot of the entry.
    func removeNgramChain(_ key: String, _ value: String, _ entry: EntryRef) -> Bool {
      predictor.removeNgramChain(key, value, predictor.storage.mutableLookup(entry.entry))
    }

    // The method should return NOT_FOUND for key-value pairs not in the chain.
    for entry in entries {
      #expect(!removeNgramChain("hoge", "HOGE", entry))
    }
    // Moreover, all nodes and links should be kept.
    for entry in entries {
      #expect(!entry.entry.removed)
    }
    #expect(Fixture.isConnected(a.entry, b.entry))
    #expect(Fixture.isConnected(b.entry, c.entry))

    do {
      // Try deleting the chain for "abc". Only the link from "b" to "c" should be
      // removed.
      #expect(removeNgramChain("abc", "ABC", a))
      for entry in entries {
        #expect(!entry.entry.removed)
      }
      #expect(Fixture.isConnected(a.entry, b.entry))
      #expect(!Fixture.isConnected(b.entry, c.entry))
    }
    do {
      // Try deleting the chain for "a". Since this is the head of the chain, the
      // function returns TAIL and nothing should be removed.
      #expect(!removeNgramChain("a", "A", a))
      for entry in entries {
        #expect(!entry.entry.removed)
      }
      #expect(Fixture.isConnected(a.entry, b.entry))
      #expect(!Fixture.isConnected(b.entry, c.entry))
    }
    do {
      // Further delete the chain for "ab".  Now all the links should be removed.
      #expect(removeNgramChain("ab", "AB", a))
      for entry in entries {
        #expect(!entry.entry.removed)
      }
      #expect(!Fixture.isConnected(a.entry, b.entry))
      #expect(!Fixture.isConnected(b.entry, c.entry))
    }
  }

  @Test func removeEntryWithInnerSegment() async {
    let remove = UserHistoryPredictor.removeEntryWithInnerSegment
    do {
      // single segment case.
      var entry = UserHistoryPredictor.Entry()
      entry.value = "京都の"
      entry.key = "きょうとの"

      #expect(!remove("きょうと", "京都", &entry))
      #expect(!entry.removed)

      for encoded in buildInnerSegmentBoundary([(15, 9, 12, 6)], "きょうとの", "京都の") {
        entry.innerSegmentBoundary.append(encoded)
      }
      #expect(remove("きょうと", "京都", &entry))
      #expect(entry.removed)
    }

    do {
      // multi segment case.
      var entry = UserHistoryPredictor.Entry()
      entry.value = "京都の歴史あるお寺は"
      entry.key = "きょうとのれきしあるおてらは"
      for encoded in buildInnerSegmentBoundary(
        [(15, 9, 12, 6), (15, 12, 9, 6), (12, 9, 9, 6)], "きょうとのれきしあるおてらは",
        "京都の歴史あるお寺は")
      {
        entry.innerSegmentBoundary.append(encoded)
      }

      // All prefix
      #expect(!remove("きょう", "京", &entry))
      #expect(remove("きょうと", "京都", &entry))
      #expect(remove("きょうとの", "京都の", &entry))
      #expect(!remove("きょうとのれき", "京都の歴", &entry))
      #expect(remove("きょうとのれきし", "京都の歴史", &entry))
      #expect(remove("きょうとのれきしある", "京都の歴史ある", &entry))
      #expect(!remove("きょうとのれきしあるお", "京都の歴史あるお", &entry))
      #expect(remove("きょうとのれきしあるおてら", "京都の歴史あるお寺", &entry))
      #expect(remove("きょうとのれきしあるおてらは", "京都の歴史あるお寺は", &entry))

      // Partial
      #expect(remove("れきし", "歴史", &entry))
      #expect(!remove("れきしあ", "歴史あ", &entry))
      #expect(remove("れきしある", "歴史ある", &entry))
      #expect(!remove("れきしあるお", "歴史あるお", &entry))
      #expect(remove("れきしあるおてら", "歴史あるお寺", &entry))
      #expect(remove("れきしあるおてらは", "歴史あるお寺は", &entry))

      #expect(!remove("お", "お", &entry))
      #expect(remove("おてら", "お寺", &entry))
      #expect(remove("おてらは", "お寺は", &entry))
      #expect(!remove("てら", "寺", &entry))
      #expect(!remove("てらは", "寺は", &entry))
    }
  }

  @Test func clearHistoryEntryUnigram() async throws {
    try await withScopedClockMock(Date(unixSeconds: 1)) { _ in
      guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
      // Tests ClearHistoryEntry() for unigram history.
      let predictor = f.getUserHistoryPredictorWithClearedHistory()

      do {
        // Add a unigram history ("japanese", "Japanese").
        let e = Fixture.insertEntry(predictor, "japanese", "Japanese")
        e.entry.lastAccessTime = 1

        // "Japanese" should be suggested and predicted from "japan".
        #expect(f.isSuggestedAndPredicted(predictor, "japan", "Japanese"))

        // Delete the history.
        #expect(predictor.clearHistoryEntry("japanese", "Japanese"))

        #expect(e.entry.removed)

        // "Japanese" should be never be suggested nor predicted.
        for prefix in part3Prefixes("japanese") {
          #expect(!f.isSuggested(predictor, prefix, "Japanese"))
          #expect(!f.isPredicted(predictor, prefix, "Japanese"))
        }
      }

      // Prefix space.
      do {
        // The data is stored with zero width sapce.
        let e = Fixture.insertEntry(predictor, "\u{200b}とうきょう", "\u{200b}東京")
        #expect(!e.entry.removed)
        #expect(predictor.clearHistoryEntry(" とうきょう", " 東京"))
        #expect(e.entry.removed)
      }
    }
  }

  @Test func clearHistoryEntryBigramDeleteWhole() async throws {
    try await withScopedClockMock(Date(unixSeconds: 1)) { _ in
      guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
      // Tests ClearHistoryEntry() for bigram history.  This case tests the deletion
      // of whole sentence.
      let predictor = f.getUserHistoryPredictorWithClearedHistory()

      // Make the history for ("japaneseinput", "JapaneseInput"). It's assumed that
      // this sentence consists of two segments, "japanese" and "input". So, the
      // following history entries are constructed:
      //   ("japaneseinput", "JapaneseInput")  // Unigram
      //   ("japanese", "Japanese") --- ("input", "Input")  // Bigram chain
      let (japaneseinput, japanese, input) = f.initHistoryJapaneseInput(predictor)

      // Check the predictor functionality for the above history structure.
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "Japanese"))
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "JapaneseInput"))
      #expect(f.isSuggestedAndPredicted(predictor, "input", "Input"))

      // Delete the unigram ("japaneseinput", "JapaneseInput").
      #expect(predictor.clearHistoryEntry("japaneseinput", "JapaneseInput"))

      #expect(japaneseinput.entry.removed)
      #expect(!japanese.entry.removed)
      #expect(!input.entry.removed)
      #expect(!Fixture.isConnected(japanese.entry, input.entry))

      // Now "JapaneseInput" should never be suggested nor predicted.
      for prefix in part3Prefixes("japaneseinput") {
        #expect(!f.isSuggested(predictor, prefix, "Japaneseinput"))
        #expect(!f.isPredicted(predictor, prefix, "Japaneseinput"))
      }

      // However, predictor should show "Japanese" and "Input".
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "Japanese"))
      #expect(f.isSuggestedAndPredicted(predictor, "inpu", "Input"))
    }
  }

  @Test func clearHistoryEntryBigramDeleteFirst() async throws {
    try await withScopedClockMock(Date(unixSeconds: 1)) { _ in
      guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
      // Tests ClearHistoryEntry() for bigram history.  This case tests the deletion
      // of the first node of the bigram chain.
      let predictor = f.getUserHistoryPredictorWithClearedHistory()

      // Make the history for ("japaneseinput", "JapaneseInput"), i.e., the same
      // history structure as ClearHistoryEntry_Bigram_DeleteWhole is constructed.
      let (japaneseinput, japanese, input) = f.initHistoryJapaneseInput(predictor)

      #expect(f.isSuggestedAndPredicted(predictor, "japan", "Japanese"))
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "JapaneseInput"))
      #expect(f.isSuggestedAndPredicted(predictor, "input", "Input"))

      // Delete the first bigram node ("japanese", "Japanese").
      #expect(predictor.clearHistoryEntry("japanese", "Japanese"))

      // Note that the first node was removed but the connection to the second node
      // is still valid.
      #expect(!japaneseinput.entry.removed)
      #expect(japanese.entry.removed)
      #expect(!input.entry.removed)
      #expect(Fixture.isConnected(japanese.entry, input.entry))

      // Now "Japanese" should never be suggested nor predicted.
      for prefix in part3Prefixes("japaneseinput") {
        #expect(!f.isSuggested(predictor, prefix, "Japanese"))
        #expect(!f.isPredicted(predictor, prefix, "Japanese"))
      }

      // However, predictor should show "JapaneseInput" and "Input".
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "JapaneseInput"))
      #expect(f.isSuggestedAndPredicted(predictor, "inpu", "Input"))
    }
  }

  @Test func clearHistoryEntryBigramDeleteSecond() async throws {
    try await withScopedClockMock(Date(unixSeconds: 1)) { _ in
      guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
      // Tests ClearHistoryEntry() for bigram history.  This case tests the deletion
      // of the first node of the bigram chain.
      let predictor = f.getUserHistoryPredictorWithClearedHistory()

      // Make the history for ("japaneseinput", "JapaneseInput"), i.e., the same
      // history structure as ClearHistoryEntry_Bigram_DeleteWhole is constructed.
      let (japaneseinput, japanese, input) = f.initHistoryJapaneseInput(predictor)

      #expect(f.isSuggestedAndPredicted(predictor, "japan", "Japanese"))
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "JapaneseInput"))
      #expect(f.isSuggestedAndPredicted(predictor, "input", "Input"))

      // Delete the second bigram node ("input", "Input").
      #expect(predictor.clearHistoryEntry("input", "Input"))

      #expect(!japaneseinput.entry.removed)
      #expect(!japanese.entry.removed)
      #expect(input.entry.removed)
      #expect(Fixture.isConnected(japanese.entry, input.entry))

      // Now "Input" should never be suggested nor predicted.
      for prefix in part3Prefixes("input") {
        #expect(!f.isSuggested(predictor, prefix, "Input"))
        #expect(!f.isPredicted(predictor, prefix, "Input"))
      }

      // However, predictor should show "Japanese" and "JapaneseInput".
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "Japanese"))
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "JapaneseInput"))
    }
  }

  /// The checks done after InitHistory_JapaneseInputMethod in several tests.
  private func expectAllJapaneseInputMethod(
    _ f: Fixture, _ predictor: UserHistoryPredictor
  ) {
    #expect(f.isSuggestedAndPredicted(predictor, "japan", "Japanese"))
    #expect(f.isSuggestedAndPredicted(predictor, "japan", "JapaneseInput"))
    #expect(f.isSuggestedAndPredicted(predictor, "japan", "JapaneseInputMethod"))
    #expect(f.isSuggestedAndPredicted(predictor, "inpu", "Input"))
    #expect(f.isSuggestedAndPredicted(predictor, "inpu", "InputMethod"))
    #expect(f.isSuggestedAndPredicted(predictor, "meth", "Method"))
  }

  @Test func clearHistoryEntryTrigramDeleteWhole() async throws {
    try await withScopedClockMock(Date(unixSeconds: 1)) { _ in
      guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
      // Tests ClearHistoryEntry() for trigram history.  This case tests the
      // deletion of the whole sentence.
      let predictor = f.getUserHistoryPredictorWithClearedHistory()

      // Make the history for ("japaneseinputmethod", "JapaneseInputMethod"). It's
      // assumed that this sentence consists of three segments, "japanese", "input"
      // and "method". So, the following history entries are constructed:
      //   ("japaneseinputmethod", "JapaneseInputMethod")  // Unigram
      //   ("japanese", "Japanese") -- ("input", "Input") -- ("method", "Method")
      let (japaneseinputmethod, japanese, input, method) =
        f.initHistoryJapaneseInputMethod(predictor)

      // Delete the history of the whole sentence.
      #expect(predictor.clearHistoryEntry("japaneseinputmethod", "JapaneseInputMethod"))

      // Note that only the link from "input" to "method" was removed.
      #expect(japaneseinputmethod.entry.removed)
      #expect(!japanese.entry.removed)
      #expect(!input.entry.removed)
      #expect(!method.entry.removed)
      #expect(Fixture.isConnected(japanese.entry, input.entry))
      #expect(!Fixture.isConnected(input.entry, method.entry))

      do {
        // Now "JapaneseInputMethod" should never be suggested nor predicted.
        for prefix in part3Prefixes("japaneseinputmethod") {
          #expect(!f.isSuggested(predictor, prefix, "JapaneseInputMethod"))
          #expect(!f.isPredicted(predictor, prefix, "JapaneseInputMethod"))
        }
      }
      do {
        // Here's a limitation of chain cut.  Since we have cut the link from
        // "input" to "method", the predictor cannot show "InputMethod" although it
        // could before.  However, since "InputMethod" is not the direct input by
        // the user (user's input was "JapaneseInputMethod" in this case), this
        // limitation would be acceptable.
        for prefix in part3Prefixes("inputmethod") {
          #expect(!f.isSuggested(predictor, prefix, "InputMethod"))
          #expect(!f.isPredicted(predictor, prefix, "InputMethod"))
        }
      }

      // The following can be still suggested and predicted.
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "Japanese"))
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "JapaneseInput"))
      #expect(f.isSuggestedAndPredicted(predictor, "inpu", "Input"))
      #expect(f.isSuggestedAndPredicted(predictor, "meth", "Method"))
    }
  }

  @Test func clearHistoryEntryTrigramDeleteFirst() async throws {
    try await withScopedClockMock(Date(unixSeconds: 1)) { _ in
      guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
      // Tests ClearHistoryEntry() for trigram history.  This case tests the
      // deletion of the first node of trigram.
      let predictor = f.getUserHistoryPredictorWithClearedHistory()

      // Make the same history structure as ClearHistoryEntry_Trigram_DeleteWhole.
      let (japaneseinputmethod, japanese, input, method) =
        f.initHistoryJapaneseInputMethod(predictor)

      expectAllJapaneseInputMethod(f, predictor)

      // Delete the first node of the chain.
      #expect(predictor.clearHistoryEntry("japanese", "Japanese"))

      // Note that the two links are still alive.
      #expect(!japaneseinputmethod.entry.removed)
      #expect(japanese.entry.removed)
      #expect(!input.entry.removed)
      #expect(!method.entry.removed)
      #expect(Fixture.isConnected(japanese.entry, input.entry))
      #expect(Fixture.isConnected(input.entry, method.entry))

      do {
        // Now "Japanese" should never be suggested nor predicted.
        for prefix in part3Prefixes("japaneseinputmethod") {
          #expect(!f.isSuggested(predictor, prefix, "Japanese"))
          #expect(!f.isPredicted(predictor, prefix, "Japanese"))
        }
      }

      // The following are still suggested and predicted.
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "JapaneseInput"))
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "JapaneseInputMethod"))
      #expect(f.isSuggestedAndPredicted(predictor, "inpu", "Input"))
      #expect(f.isSuggestedAndPredicted(predictor, "inpu", "InputMethod"))
      #expect(f.isSuggestedAndPredicted(predictor, "meth", "Method"))
    }
  }

  @Test func clearHistoryEntryTrigramDeleteSecond() async throws {
    try await withScopedClockMock(Date(unixSeconds: 1)) { _ in
      guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
      // Tests ClearHistoryEntry() for trigram history.  This case tests the
      // deletion of the second node of trigram.
      let predictor = f.getUserHistoryPredictorWithClearedHistory()

      // Make the same history structure as ClearHistoryEntry_Trigram_DeleteWhole.
      let (japaneseinputmethod, japanese, input, method) =
        f.initHistoryJapaneseInputMethod(predictor)

      expectAllJapaneseInputMethod(f, predictor)

      // Delete the second node of the chain.
      #expect(predictor.clearHistoryEntry("input", "Input"))

      // Note that the two links are still alive.
      #expect(!japaneseinputmethod.entry.removed)
      #expect(!japanese.entry.removed)
      #expect(input.entry.removed)
      #expect(!method.entry.removed)
      #expect(Fixture.isConnected(japanese.entry, input.entry))
      #expect(Fixture.isConnected(input.entry, method.entry))

      do {
        // Now "Input" should never be suggested nor predicted.
        for prefix in part3Prefixes("inputmethod") {
          #expect(!f.isSuggested(predictor, prefix, "Input"))
          #expect(!f.isPredicted(predictor, prefix, "Input"))
        }
      }

      // The following can still be shown by the predictor.
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "Japanese"))
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "JapaneseInput"))
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "JapaneseInputMethod"))
      #expect(f.isSuggestedAndPredicted(predictor, "inpu", "InputMethod"))
      #expect(f.isSuggestedAndPredicted(predictor, "meth", "Method"))
    }
  }

  @Test func clearHistoryEntryTrigramDeleteThird() async throws {
    try await withScopedClockMock(Date(unixSeconds: 1)) { _ in
      guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
      // Tests ClearHistoryEntry() for trigram history.  This case tests the
      // deletion of the third node of trigram.
      let predictor = f.getUserHistoryPredictorWithClearedHistory()

      // Make the same history structure as ClearHistoryEntry_Trigram_DeleteWhole.
      let (japaneseinputmethod, japanese, input, method) =
        f.initHistoryJapaneseInputMethod(predictor)

      expectAllJapaneseInputMethod(f, predictor)

      // Delete the third node, "method".
      #expect(predictor.clearHistoryEntry("method", "Method"))

      // Note that the two links are still alive.
      #expect(!japaneseinputmethod.entry.removed)
      #expect(!japanese.entry.removed)
      #expect(!input.entry.removed)
      #expect(method.entry.removed)
      #expect(Fixture.isConnected(japanese.entry, input.entry))
      #expect(Fixture.isConnected(input.entry, method.entry))

      do {
        // Now "Method" should never be suggested nor predicted.
        for prefix in part3Prefixes("method") {
          #expect(!f.isSuggested(predictor, prefix, "Method"))
          #expect(!f.isPredicted(predictor, prefix, "Method"))
        }
      }

      // The following can still be shown by the predictor.
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "Japanese"))
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "JapaneseInput"))
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "JapaneseInputMethod"))
      #expect(f.isSuggestedAndPredicted(predictor, "inpu", "Input"))
      #expect(f.isSuggestedAndPredicted(predictor, "inpu", "InputMethod"))
    }
  }

  @Test func clearHistoryEntryTrigramDeleteFirstBigram() async throws {
    try await withScopedClockMock(Date(unixSeconds: 1)) { _ in
      guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
      // Tests ClearHistoryEntry() for trigram history.  This case tests the
      // deletion of the first bigram of trigram.
      let predictor = f.getUserHistoryPredictorWithClearedHistory()

      // Make the same history structure as ClearHistoryEntry_Trigram_DeleteWhole.
      let (japaneseinputmethod, japanese, input, method) =
        f.initHistoryJapaneseInputMethod(predictor)

      expectAllJapaneseInputMethod(f, predictor)

      // Delete the sentence consisting of the first two nodes.
      #expect(predictor.clearHistoryEntry("japaneseinput", "JapaneseInput"))

      // Note that the node "japaneseinput" and the link from "japanese" to "input"
      // were removed.
      #expect(!japaneseinputmethod.entry.removed)
      #expect(!japanese.entry.removed)
      #expect(!input.entry.removed)
      #expect(!method.entry.removed)
      #expect(!Fixture.isConnected(japanese.entry, input.entry))
      #expect(Fixture.isConnected(input.entry, method.entry))

      do {
        // Now "JapaneseInput" should never be suggested nor predicted.
        for prefix in part3Prefixes("japaneseinputmethod") {
          #expect(!f.isSuggested(predictor, prefix, "JapaneseInput"))
          #expect(!f.isPredicted(predictor, prefix, "JapaneseInput"))
        }
      }

      // However, the following can still be available, including
      // "JapaneseInputMethod".
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "Japanese"))
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "JapaneseInputMethod"))
      #expect(f.isSuggestedAndPredicted(predictor, "inpu", "Input"))
      #expect(f.isSuggestedAndPredicted(predictor, "inpu", "InputMethod"))
      #expect(f.isSuggestedAndPredicted(predictor, "meth", "Method"))
    }
  }

  @Test func clearHistoryEntryTrigramDeleteSecondBigram() async throws {
    try await withScopedClockMock(Date(unixSeconds: 1)) { _ in
      guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
      // Tests ClearHistoryEntry() for trigram history.  This case tests the
      // deletion of the latter bigram of trigram.
      let predictor = f.getUserHistoryPredictorWithClearedHistory()

      // Make the same history structure as ClearHistoryEntry_Trigram_DeleteWhole.
      let (japaneseinputmethod, japanese, input, method) =
        f.initHistoryJapaneseInputMethod(predictor)

      expectAllJapaneseInputMethod(f, predictor)

      // Delete the latter bigram.
      #expect(predictor.clearHistoryEntry("inputmethod", "InputMethod"))

      // Note that only link from "input" to "method" was removed.
      #expect(!japaneseinputmethod.entry.removed)
      #expect(!japanese.entry.removed)
      #expect(!input.entry.removed)
      #expect(!method.entry.removed)
      #expect(Fixture.isConnected(japanese.entry, input.entry))
      #expect(!Fixture.isConnected(input.entry, method.entry))

      do {
        // Now "InputMethod" should never be suggested.
        for prefix in part3Prefixes("inputmethod") {
          #expect(!f.isSuggested(predictor, prefix, "InputMethod"))
          #expect(!f.isPredicted(predictor, prefix, "InputMethod"))
        }
      }

      // However, the following are available.
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "Japanese"))
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "JapaneseInput"))
      #expect(f.isSuggestedAndPredicted(predictor, "japan", "JapaneseInputMethod"))
      #expect(f.isSuggestedAndPredicted(predictor, "inpu", "Input"))
      #expect(f.isSuggestedAndPredicted(predictor, "meth", "Method"))
    }
  }

  @Test func clearHistoryEntryScenario1() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    // Tests a common scenario: First, a user accidentally inputs an incomplete
    // romaji sequence and the predictor learns it.  Then, the user deletes it.
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    // Set up history. Convert "ぐーぐｒ" to "グーグr" 3 times.  This emulates a
    // case that a user accidentally input incomplete sequence.
    for _ in 0..<3 {
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForConversion("ぐーぐｒ", segmentsProxy)
      segmentsProxy.addCandidate(0, "グーグr")
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }

    // Test if the predictor learned "グーグr".
    #expect(f.isSuggested(predictor, "ぐーぐ", "グーグr"))
    #expect(f.isPredicted(predictor, "ぐーぐ", "グーグr"))

    // The user tris deleting the history ("ぐーぐｒ", "グーグr").
    #expect(predictor.clearHistoryEntry("ぐーぐｒ", "グーグr"))

    // The predictor shouldn't show "グーグr" both for suggestion and prediction.
    #expect(!f.isSuggested(predictor, "ぐーぐ", "グーグr"))
    #expect(!f.isPredicted(predictor, "ぐーぐ", "グーグr"))
  }

  @Test func clearHistoryEntryScenario2() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    // Tests a common scenario: First, a user inputs a sentence ending with a
    // symbol and it's learned by the predictor.  Then, the user deletes the
    // history containing the symbol.
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    // Set up history. Convert "きょうもいいてんき！" to "今日もいい天気!" 3 times
    // so that the predictor learns the sentence. We assume that this sentence
    // consists of three segments: "今日も|いい天気|!".
    for _ in 0..<3 {
      let segmentsProxy = SegmentsProxy()

      segmentsProxy.addSegment("きょうも")
      segmentsProxy.addSegment("いいてんき")
      segmentsProxy.addSegment("！")
      segmentsProxy.addCandidate(0, "今日も")
      segmentsProxy.addCandidate(1, "いい天気")
      segmentsProxy.addCandidate(2, "!")

      let convreq = f.createConversionRequest(segmentsProxy)

      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }

    // Check if the predictor learned the sentence.
    // Only predict "今日もいい天気". "今日もいい天気!" is not suggested as it
    // ends with punctuation.
    #expect(f.isSuggestedAndPredicted(predictor, "きょうも", "今日もいい天気"))
    #expect(!f.isSuggestedAndPredicted(predictor, "きょうも", "今日もいい天気!"))

    // Now the user deletes the sentence containing the "!".
    #expect(predictor.clearHistoryEntry("きょうもいいてんき！", "今日もいい天気!"))

    // The sentence "今日もいい天気" should still be suggested and predicted.
    #expect(f.isSuggestedAndPredicted(predictor, "きょうも", "今日もいい天気"))

    // However, "今日もいい天気!" should be neither suggested nor predicted.
    #expect(!f.isSuggested(predictor, "きょうも", "今日もいい天気!"))
    #expect(!f.isPredicted(predictor, "きょうも", "今日もいい天気!"))
  }

  @Test func contentWordLearningFromInnerSegmentBoundary() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    f.request.mixedConversion = true

    let segmentsProxy = SegmentsProxy()
    var results: [PredictionResult] = []

    do {
      let kKey = "とうきょうかなごやにいきたい"
      let kValue = "東京か名古屋に行きたい"
      let convreq1 = f.setUpInputForPrediction(kKey, segmentsProxy)
      segmentsProxy.addCandidate(0, kValue)
      segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 18, 9, 15, 6)
      segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 12, 12, 9, 9)
      segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 12, 12, 12, 12)
      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)
    }

    segmentsProxy.clear()
    let convreq2 = f.setUpInputForPrediction("と", segmentsProxy)
    results = predictor.predict(convreq2)
    #expect(!results.isEmpty)
    #expect(Fixture.findCandidateByValue("東京", results) != nil)
    #expect(Fixture.findCandidateByValue("東京か", results) == nil)

    segmentsProxy.clear()
    let convreq3 = f.setUpInputForPrediction("な", segmentsProxy)
    results = predictor.predict(convreq3)
    #expect(!results.isEmpty)
    #expect(Fixture.findCandidateByValue("名古屋", results) != nil)
    #expect(Fixture.findCandidateByValue("名古屋に", results) == nil)
    segmentsProxy.clear()
    let convreq4 = f.setUpInputForPrediction("い", segmentsProxy)
    results = predictor.predict(convreq4)
    #expect(!results.isEmpty)
    #expect(Fixture.findCandidateByValue("行きたい", results) != nil)
  }

  @Test func joinedSegmentsTestMobile() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()
    RequestTestUtil.fillMobileRequest(&f.request)
    let segmentsProxy = SegmentsProxy()
    var results: [PredictionResult] = []

    let convreq1 = f.setUpInputForConversion("わたしの", segmentsProxy)
    segmentsProxy.addCandidate(0, "私の")

    segmentsProxy.addSegment("なまえは")
    segmentsProxy.addCandidate(1, "名前は")

    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)
    segmentsProxy.clear()

    let convreq2 = f.setUpInputForSuggestion("わたし", segmentsProxy)
    results = predictor.predict(convreq2)
    #expect(!results.isEmpty)
    #expect(results.count == 1)
    #expect(results.first?.value == "私の")
    segmentsProxy.clear()

    let convreq3 = f.setUpInputForPrediction("わたしの", segmentsProxy)
    results = predictor.predict(convreq3)
    #expect(!results.isEmpty)
    #expect(results.count == 1)
    #expect(results.first?.value == "私の")
    segmentsProxy.clear()

    let convreq4 = f.setUpInputForPrediction("わたしのな", segmentsProxy)
    results = predictor.predict(convreq4)
    #expect(!results.isEmpty)
    #expect(results.count == 1)
    #expect(results.first?.value == "私の名前は")
    segmentsProxy.clear()
  }

  @Test func joinedSegmentsTestDesktop() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    let segmentsProxy = SegmentsProxy()
    var results: [PredictionResult] = []

    let convreq1 = f.setUpInputForConversion("わたしの", segmentsProxy)
    segmentsProxy.addCandidate(0, "私の")

    segmentsProxy.addSegment("なまえは")
    segmentsProxy.addCandidate(1, "名前は")

    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

    segmentsProxy.clear()

    let convreq2 = f.setUpInputForSuggestion("わたし", segmentsProxy)
    results = predictor.predict(convreq2)
    #expect(!results.isEmpty)
    #expect(results.count == 2)
    if results.count == 2 {
      #expect(results[0].value == "私の")
      #expect(results[1].value == "私の名前は")
    }

    segmentsProxy.clear()

    let convreq3 = f.setUpInputForPrediction("わたしの", segmentsProxy)
    results = predictor.predict(convreq3)
    #expect(!results.isEmpty)
    #expect(results.count == 1)
    #expect(results.first?.value == "私の名前は")

    segmentsProxy.clear()

    let convreq4 = f.setUpInputForPrediction("わたしのな", segmentsProxy)
    results = predictor.predict(convreq4)
    #expect(!results.isEmpty)
    #expect(results.count == 1)
    #expect(results.first?.value == "私の名前は")

    segmentsProxy.clear()
  }
}
