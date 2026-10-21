// Port of mozc/src/prediction/user_history_predictor_test.cc (3.35.6354),
// part 5 (PartialRevert .. CharacterFormNormalization). See
// UserHistoryPredictorTests.swift for the conventions.
//
// The C++ ConversionRequest keeps views of request_/config_/context_; where a
// C++ test changes them after building a request and reuses that request, the
// request is rebuilt here (same composer state and SegmentsProxy).

import Foundation
import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private typealias Fixture = UserHistoryPredictorTestFixture

/// Rebuilds a request with `requestType` from the current fixture state
/// (composer, request_, config_, context_) without touching the proxy.
private func part5RebuildRequest(
  _ f: Fixture, _ requestType: RequestType, _ segmentsProxy: SegmentsProxy
) -> ConversionRequest {
  var options = ConversionRequest.Options()
  options.requestType = requestType
  return f.createConversionRequestWithOptions(options, segmentsProxy)
}

@Suite(.scopedConfigEnvironment) struct UserHistoryPredictorTestPart5 {
  @Test func partialRevert() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    var results: [PredictionResult] = []

    let mock = MockSupplementalModel()

    // Emulates reading aligner.
    mock.getReadingAlignmentHandler = { surface, reading in
      // splits 京都大学 -> 京都|大学
      let s = Array(surface.utf8)
      let r = Array(reading.utf8)
      func find(_ h: [UInt8], _ n: String) -> Int {
        let n = Array(n.utf8)
        var i = 0
        while i + n.count <= h.count {
          if h[i..<(i + n.count)].elementsEqual(n) { return i }
          i += 1
        }
        return h.count
      }
      let pos1 = find(s, "大学")
      let pos2 = find(r, "だいがく")
      return [
        (String(decoding: s[..<pos1], as: UTF8.self), String(decoding: r[..<pos2], as: UTF8.self)),
        (String(decoding: s[pos1...], as: UTF8.self), String(decoding: r[pos2...], as: UTF8.self)),
      ]
    }

    let data = try await Fixture.createDataAndPredictor(supplementalModel: mock)
    let predictor = data.predictor

    func hasEntry(_ key: String, _ value: String) -> Bool {
      let entry = predictor.storage.lookup(key, value)
      return !entry.isNull && entry.entry.suggestionFreq > 0 && entry.entry.lastAccessTime > 0
    }

    func hasLink(_ prevKey: String, _ prevValue: String, _ nextKey: String, _ nextValue: String)
      -> Bool
    {
      let prevEntry = predictor.storage.lookup(prevKey, prevValue)
      if prevEntry.isNull { return false }
      let nextFp = UserHistoryStorage.fingerprint(nextKey, nextValue)
      return prevEntry.entry.nextEntryFps.contains(nextFp)
    }

    func initPredictor() async {
      predictor.clearAllHistory()
      await predictor.wait()

      var result = PredictionResult()

      func addSegment(_ key: String, _ value: String, _ contentKey: String, _ contentValue: String)
      {
        #expect(key.hasBytePrefix(contentKey))
        #expect(value.hasBytePrefix(contentValue))
        result.key += key
        result.value += value
        result.innerSegmentBoundary.append(
          encodeLengths(
            key.utf8.count, value.utf8.count, contentKey.utf8.count, contentValue.utf8.count)!)
      }

      // 佐藤さんは京都大学を卒業した
      addSegment("さとうさんは", "佐藤さんは", "さとうさん", "佐藤さん")
      addSegment("きょうとだいがくを", "京都大学を", "きょうとだいがく", "京都大学")
      // value == content_value.
      addSegment("そつぎょうした", "卒業した", "そつぎょうした", "卒業した")

      // Make a placeholder request for Finish().
      let segmentsProxy = SegmentsProxy()
      f.request.mixedConversion = true
      f.request.zeroQuerySuggestion = true
      let convreq = f.setUpInputForSuggestion("さとう", segmentsProxy)

      predictor.finish(convreq, [result], kRevertId)

      // New entries are inserted.
      #expect(hasEntry("さとうさんは", "佐藤さんは"))
      #expect(hasEntry("さとうさん", "佐藤さん"))
      #expect(hasEntry("きょうとだいがくを", "京都大学を"))
      #expect(hasEntry("きょうとだいがく", "京都大学"))
      #expect(hasEntry("そつぎょうした", "卒業した"))

      predictor.revert(kRevertId)

      // All entries are removed with Revret.
      #expect(!hasEntry("さとうさんはきょうとだいがくをそつぎょうした", "佐藤さんは京都大学を卒業した"))
      #expect(!hasEntry("さとうさんは", "佐藤さんは"))
      #expect(!hasEntry("さとうさん", "佐藤さん"))
      #expect(!hasEntry("きょうとだいがくを", "京都大学を"))
      #expect(!hasEntry("きょうとだいがく", "京都大学"))
      #expect(!hasEntry("そつぎょうした", "卒業した"))
    }

    // Continue to type with the key and left_context.
    func suggestWithContext(_ key: String, _ leftContext: String) -> [PredictionResult] {
      f.context.precedingText = leftContext
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForSuggestion(key, segmentsProxy)
      return predictor.predict(convreq)
    }

    do {
      await initPredictor()

      results = suggestWithContext("さとう", "佐藤さんは京都大学を")
      #expect(!results.isEmpty)
      #expect(results.first?.value.hasBytePrefix("佐藤さん") == true)

      #expect(hasEntry("さとうさんは", "佐藤さんは"))
      #expect(hasEntry("さとうさん", "佐藤さん"))
      #expect(hasEntry("きょうとだいがくを", "京都大学を"))
      #expect(hasEntry("きょうとだいがく", "京都大学"))
      #expect(!hasEntry("そつぎょうした", "卒業した"))
    }

    do {
      await initPredictor()

      results = suggestWithContext("さとう", "佐藤さんは京都大学")
      #expect(!results.isEmpty)

      #expect(hasEntry("さとうさんは", "佐藤さんは"))
      #expect(hasEntry("さとうさん", "佐藤さん"))
      #expect(!hasEntry("きょうとだいがくを", "京都大学を"))
      #expect(hasEntry("きょうとだいがく", "京都大学"))
      #expect(!hasEntry("そつぎょうした", "卒業した"))
    }

    do {
      await initPredictor()

      // middle of 京都大学 -> split by reading aligner.
      results = suggestWithContext("さとう", "佐藤さんは京都")
      #expect(!results.isEmpty)

      #expect(hasEntry("さとうさんは", "佐藤さんは"))
      #expect(hasEntry("さとうさん", "佐藤さん"))
      #expect(hasEntry("きょうと", "京都"))
      #expect(!hasEntry("きょうとだいがくを", "京都大学を"))
      #expect(!hasEntry("きょうとだいがく", "京都大学"))
      #expect(!hasEntry("そつぎょうした", "卒業した"))
    }

    do {
      await initPredictor()

      // Middle of 卒業した -> safely remove "した" as it is HIRAGANA.
      results = suggestWithContext("さとう", "佐藤さんは京都大学を卒業")
      #expect(!results.isEmpty)

      #expect(hasEntry("さとうさんは", "佐藤さんは"))
      #expect(hasEntry("さとうさん", "佐藤さん"))
      #expect(hasEntry("きょうとだいがくを", "京都大学を"))
      #expect(hasEntry("きょうとだいがく", "京都大学"))
      #expect(!hasEntry("そつぎょうした", "卒業した"))
      #expect(hasEntry("そつぎょう", "卒業"))  // Newly added.
      #expect(hasLink("きょうとだいがくを", "京都大学を", "そつぎょう", "卒業"))
    }

    do {
      await initPredictor()
      results = suggestWithContext("さとう", "佐藤さんは京都大学を卒業し")
      #expect(!results.isEmpty)

      #expect(hasEntry("さとうさんは", "佐藤さんは"))
      #expect(hasEntry("さとうさん", "佐藤さん"))
      #expect(hasEntry("きょうとだいがくを", "京都大学を"))
      #expect(hasEntry("きょうとだいがく", "京都大学"))
      #expect(!hasEntry("そつぎょうした", "卒業した"))
      #expect(hasEntry("そつぎょうし", "卒業し"))  // Newly added.
      #expect(hasLink("きょうとだいがくを", "京都大学を", "そつぎょうし", "卒業し"))
    }

    do {
      await initPredictor()
      results = suggestWithContext("さとう", "佐藤さん")
      #expect(!results.isEmpty)

      #expect(!hasEntry("さとうさんは", "佐藤さんは"))
      #expect(hasEntry("さとうさん", "佐藤さん"))
      #expect(!hasEntry("きょうとだいがくを", "京都大学を"))
      #expect(!hasEntry("きょうとだいがく", "京都大学"))
      #expect(!hasEntry("そつぎょうした", "卒業した"))
    }

    do {
      await initPredictor()
      results = suggestWithContext("さとう", "佐藤")
      #expect(!results.isEmpty)

      #expect(hasEntry("さとう", "佐藤"))
      #expect(!hasEntry("さとうさんは", "佐藤さんは"))
      #expect(!hasEntry("さとうさん", "佐藤さん"))
      #expect(!hasEntry("きょうとだいがくを", "京都大学を"))
      #expect(!hasEntry("きょうとだいがく", "京都大学"))
      #expect(!hasEntry("そつぎょうした", "卒業した"))
    }

    do {
      await initPredictor()
      results = suggestWithContext("さとう", "")
      #expect(results.isEmpty)

      #expect(!hasEntry("さとうさんは", "佐藤さんは"))
      #expect(!hasEntry("さとうさん", "佐藤さん"))
      #expect(!hasEntry("きょうとだいがくを", "京都大学を"))
      #expect(!hasEntry("きょうとだいがく", "京都大学"))
      #expect(!hasEntry("そつぎょうした", "卒業した"))
    }

    do {
      await initPredictor()
      results = suggestWithContext("さとう", "関係ない文脈")
      #expect(results.isEmpty)

      #expect(!hasEntry("さとうさんは", "佐藤さんは"))
      #expect(!hasEntry("さとうさん", "佐藤さん"))
      #expect(!hasEntry("きょうとだいがくを", "京都大学を"))
      #expect(!hasEntry("きょうとだいがく", "京都大学"))
      #expect(!hasEntry("そつぎょうした", "卒業した"))
    }

    // Zero query. partial-revert handling is invoked when user has
    // started new input.
    do {
      await initPredictor()
      results = suggestWithContext("", "佐藤さんは京都大学を卒業し")
      #expect(results.isEmpty)

      #expect(!hasEntry("さとうさんは", "佐藤さんは"))
      #expect(!hasEntry("さとうさん", "佐藤さん"))
      #expect(!hasEntry("きょうとだいがくを", "京都大学を"))
      #expect(!hasEntry("きょうとだいがく", "京都大学"))
      #expect(!hasEntry("そつぎょうした", "卒業した"))
    }

    // Adds extra characters directly w/o using IME.
    do {
      await initPredictor()

      results = suggestWithContext("さとう", "佐藤さんは京都大学を \n\r　")
      #expect(!results.isEmpty)
      #expect(results.first?.value.hasBytePrefix("佐藤さん") == true)

      #expect(hasEntry("さとうさんは", "佐藤さんは"))
      #expect(hasEntry("さとうさん", "佐藤さん"))
      #expect(hasEntry("きょうとだいがくを", "京都大学を"))
      #expect(hasEntry("きょうとだいがく", "京都大学"))
      #expect(!hasEntry("そつぎょうした", "卒業した"))
    }

    // Feed new context via CommitContext.
    do {
      await initPredictor()

      f.context.precedingText = "佐藤さんは京都"
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForSuggestion("", segmentsProxy)
      predictor.commitContext(convreq)

      #expect(hasEntry("さとうさんは", "佐藤さんは"))
      #expect(hasEntry("さとうさん", "佐藤さん"))
      #expect(hasEntry("きょうと", "京都"))
      #expect(!hasEntry("きょうとだいがくを", "京都大学を"))
      #expect(!hasEntry("きょうとだいがく", "京都大学"))
      #expect(!hasEntry("そつぎょうした", "卒業した"))
    }
  }

  @Test func predictPrefixSpace() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    let segmentsProxy = SegmentsProxy()
    var results: [PredictionResult] = []

    f.request.zeroQuerySuggestion = true
    f.request.mixedConversion = true

    func convertUnigram(_ key: String, _ value: String) {
      segmentsProxy.clear()
      let convreq = f.setUpInputForConversion(key, segmentsProxy)
      segmentsProxy.addCandidate(0, value)
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }

    func convertUnigramWithBoundary(
      _ key: String, _ value: String, _ keyLen: Int, _ valueLen: Int, _ contentKeyLen: Int,
      _ contentValueLen: Int
    ) {
      segmentsProxy.clear()
      let convreq = f.setUpInputForConversion(key, segmentsProxy)
      segmentsProxy.addCandidate(0, value)
      segmentsProxy.pushBackInnerSegmentBoundary(
        0, 0, keyLen, valueLen, contentKeyLen, contentValueLen)
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }

    do {
      f.request.displayValueCapability = .plainText

      predictor.clearAllHistory()

      convertUnigram("らーめん", "ラーメン")
      // user puts space after ラーメン
      f.context.precedingText = "ラーメン　"
      convertUnigram("しぶや", "渋谷")

      var convreq = f.setUpInputForSuggestionWithHistory("", "らーめん", "ラーメン", segmentsProxy)
      results = predictor.predict(convreq)
      try #require(results.count == 1)
      #expect(results[0].value == "　渋谷")
      #expect(results[0].key == "　しぶや")
      #expect(results[0].displayValue == "␣渋谷")

      f.config.spaceCharacterForm = .fundamentalHalfWidth
      convreq = part5RebuildRequest(f, .suggestion, segmentsProxy)
      results = predictor.predict(convreq)
      try #require(results.count == 1)
      #expect(results[0].value == " 渋谷")
      #expect(results[0].key == " しぶや")
      #expect(results[0].displayValue == "␣渋谷")

      f.request.displayValueCapability = .notSupported
      convreq = part5RebuildRequest(f, .suggestion, segmentsProxy)
      results = predictor.predict(convreq)
      try #require(results.count == 1)
      #expect(results[0].value == " 渋谷")
      #expect(results[0].key == " しぶや")
      #expect(results[0].displayValue.isEmpty)

      predictor.clearAllHistory()
      convertUnigram("らーめん", "ラーメン")
      f.context.precedingText = "テスト"  // invalid history.
      convertUnigram("しぶや", "渋谷")

      // (C++ reuses `convreq`, whose history view now refers to the proxy
      // reset by convert_unigram.)
      results = predictor.predict(convreq)
      #expect(results.isEmpty)

      predictor.clearAllHistory()
      convertUnigram("らーめん", "ラーメン")
      f.context.precedingText = "ラーメン    "  // multiple spaces.
      convertUnigram("しぶや", "渋谷")

      results = predictor.predict(convreq)
      #expect(results.isEmpty)
    }

    // No NWP from functional word.
    do {
      predictor.clearAllHistory()

      convertUnigramWithBoundary("らーめんの", "ラーメンの", 15, 15, 12, 12)
      f.context.precedingText = "ラーメンの　"
      convertUnigram("しぶや", "渋谷")

      let convreq1 = f.setUpInputForSuggestionWithHistory("", "の", "の", segmentsProxy)
      results = predictor.predict(convreq1)
      #expect(results.isEmpty)

      let convreq2 = f.setUpInputForSuggestionWithHistory("", "らーめんの", "ラーメンの", segmentsProxy)
      results = predictor.predict(convreq2)
      #expect(results.isEmpty)
    }

    // No NWP to segments with functional word.
    do {
      predictor.clearAllHistory()

      convertUnigram("らーめん", "ラーメン")
      f.context.precedingText = "ラーメン　"
      convertUnigramWithBoundary("しぶやは", "渋谷は", 12, 9, 9, 6)

      let convreq = f.setUpInputForSuggestionWithHistory("", "らーめん", "ラーメン", segmentsProxy)
      results = predictor.predict(convreq)
      #expect(results.isEmpty)
    }
  }

  @Test func maybeRewritePrefixSpace() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    _ = f
    var config = ConfigHandler.defaultConfig()
    var request = Genmai_Commands_Request()

    request.displayValueCapability = .plainText

    func check(
      _ convReq: ConversionRequest, _ key: String, _ value: String, _ expectedKey: String,
      _ expectedValue: String, _ expectedDisplayValue: String, _ expectedBoundaryEmpty: Bool,
      sourceLocation: SourceLocation = #_sourceLocation
    ) {
      var result = PredictionResult()
      result.key = key
      result.value = value
      result.innerSegmentBoundary = [0]
      UserHistoryPredictor.maybeRewritePrefixSpace(convReq, &result)
      #expect(result.key == expectedKey, sourceLocation: sourceLocation)
      #expect(result.value == expectedValue, sourceLocation: sourceLocation)
      #expect(result.displayValue == expectedDisplayValue, sourceLocation: sourceLocation)
      #expect(
        result.innerSegmentBoundary.isEmpty == expectedBoundaryEmpty,
        sourceLocation: sourceLocation)
    }

    do {
      let convReq = ConversionRequestBuilder().setRequestView(request).build()
      check(convReq, "key", "value", "key", "value", "", false)
    }

    do {
      let convReq = ConversionRequestBuilder().setConfigView(config).setRequestView(request).build()
      check(convReq, "　key", "　value", "　key", "　value", "␣value", true)
    }

    do {
      config.spaceCharacterForm = .fundamentalHalfWidth
      let convReq = ConversionRequestBuilder().setConfigView(config).setRequestView(request).build()
      check(convReq, "　key", "　value", " key", " value", "␣value", true)
    }

    do {
      config.spaceCharacterForm = .fundamentalFullWidth
      let convReq = ConversionRequestBuilder().setConfigView(config).setRequestView(request).build()
      check(convReq, "　key", "　value", "　key", "　value", "␣value", true)
    }

    do {
      config.spaceCharacterForm = .fundamentalFullWidth
      let convReq = ConversionRequestBuilder().setConfigView(config).setRequestView(request).build()
      // Internally, Zero-wdith space is added.
      check(convReq, "\u{3000}key", "\u{3000}value", "　key", "　value", "␣value", true)
    }

    do {
      request.displayValueCapability = .notSupported
      config.spaceCharacterForm = .fundamentalFullWidth
      let convReq = ConversionRequestBuilder().setConfigView(config).setRequestView(request).build()
      check(convReq, "　key", "　value", "　key", "　value", "", true)
    }
  }

  @Test func addHistoryEntryTest() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    #expect(!f.isSuggested(predictor, "とうきょう", "東京"))
    #expect(predictor.addHistoryEntry("とうきょう", "東京"))
    #expect(f.isSuggested(predictor, "とうきょう", "東京"))

    // Empty chars
    #expect(!predictor.addHistoryEntry("", ""))
    #expect(!predictor.addHistoryEntry("おおさか", ""))
    #expect(!predictor.addHistoryEntry("", "大阪"))

    // starts or ends with invalid chars
    #expect(!predictor.addHistoryEntry("おおさか", "大阪."))
    #expect(!predictor.addHistoryEntry("おおさか", ".大阪"))

    // Removes head and trailing whitespaces.
    #expect(!f.isSuggested(predictor, "おおさか", "大阪"))
    #expect(predictor.addHistoryEntry(" おおさか   ", "  大阪 "))
    #expect(f.isSuggested(predictor, "おおさか", "大阪"))
  }

  @Test func isProperNounTest() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    _ = f
    let dictionary = MockDictionary()
    let data = try await Fixture.createDataAndPredictor(dictionary: dictionary)
    let modules = data.modules
    let predictor = data.predictor
    await predictor.wait()

    dictionary.lookupExactHandler = { key, options, cb in
      var token = Token()
      // "たなか" is registered as proper noun.
      if key == "たなか" {
        token.lid = modules.getPosMatcher().getLastNameId()
        token.rid = token.lid
        #expect(cb.onToken(key, "", token) == .traverseDone)
        return
      }
      token.lid = 0
      token.rid = 0
      #expect(cb.onToken(key, "", token) == .traverseContinue)
    }

    let req = ConversionRequestBuilder().build()

    var result = PredictionResult()

    result.key = "あ"
    result.value = "あいう"
    #expect(!predictor.isProperNoun(req, result))

    result.key = "あいう"
    result.value = "カタカナ"
    #expect(predictor.isProperNoun(req, result))

    result.key = "やま"
    result.value = "山"
    result.attributes = Attribute.singleKanji
    #expect(predictor.isProperNoun(req, result))

    result.key = "123"
    result.value = "123"
    result.attributes = Attribute.number
    #expect(predictor.isProperNoun(req, result))

    result.key = "やました"
    result.value = "山下"
    result.attributes = 0
    result.lid = modules.getPosMatcher().getLastNameId()
    result.rid = result.lid
    #expect(predictor.isProperNoun(req, result))

    // "たなか" is registered as proper noun.
    result.key = "たなか"
    result.value = "田中"
    result.attributes = 0
    result.lid = 0
    result.rid = 0
    #expect(predictor.isProperNoun(req, result))

    // "たなか" is registered as proper noun, but value must be Kanji.
    result.key = "たなか"
    result.value = "たなか"
    result.attributes = 0
    result.lid = 0
    result.rid = 0
    #expect(!predictor.isProperNoun(req, result))

    // "じんるい" is registered as proper noun.
    result.key = "じんるい"
    result.value = "人類"
    result.attributes = 0
    result.lid = 0
    result.rid = 0
    #expect(!predictor.isProperNoun(req, result))
  }

  @Test func exactMatchTest() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()

    let segmentsProxy = SegmentsProxy()
    var results: [PredictionResult] = []

    f.request.mixedConversion = true

    // Create full sentence entry with boundary information.
    // By default, full sentence is allowed to be suggested when the freq >= 2.
    // However, allow full sentence to be suggested when
    // allow_exact_match flag is true and the query is exact match.
    let kKey = "わたしのなまえはなかのです"
    let kValue = "私の名前は中野です"
    do {
      let convreq1 = f.setUpInputForPrediction(kKey, segmentsProxy)
      segmentsProxy.addCandidate(0, kValue)
      segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 12, 6, 9, 3)
      segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 12, 9, 9, 6)
      segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 15, 12, 9, 6)
      predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)
      let entry = predictor.storage.mutableLookup(kKey, kValue)
      #expect(!entry.isNull)
      segmentsProxy.clear()
    }

    for freq: UInt32 in [1, 2] {
      do {
        let entry = predictor.storage.mutableLookup(kKey, kValue)
        try #require(!entry.isNull)
        entry.entry.suggestionFreq = freq
        try #require(entry.entry.innerSegmentBoundary.count == 3)
      }

      // Short partial
      segmentsProxy.clear()
      let convreq1 = f.setUpInputForPrediction("わたしのなまえは", segmentsProxy)
      results = predictor.predict(convreq1)
      // Partial matche is allowed when the entry is typed twice or more.
      if freq >= 2 {
        #expect(!results.isEmpty)
      } else {
        #expect(results.isEmpty)
      }

      // Partial that reaches to the last segment.
      segmentsProxy.clear()
      let convreq2 = f.setUpInputForPrediction("わたしのなまえはな", segmentsProxy)
      results = predictor.predict(convreq2)
      #expect(!results.isEmpty)
      #expect(results.first?.value == kValue)
      #expect(results.first?.key == kKey)

      // Exact
      segmentsProxy.clear()
      let convreq3 = f.setUpInputForPrediction(kKey, segmentsProxy)
      results = predictor.predict(convreq3)
      #expect(!results.isEmpty)
      #expect(results.first?.value == kValue)
      #expect(results.first?.key == kKey)
    }
  }

  @Test func partialMatchTest() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let data = try await Fixture.createDataAndPredictor()
    let modules = data.modules
    let realtimeDecoder = data.realtimeDecoder
    let predictor = data.predictor
    await predictor.wait()

    f.request.mixedConversion = true

    let firstNameId = modules.getPosMatcher().getFirstNameId()

    realtimeDecoder.decodeSuffixHandler = { request, prefixRid, suffix in
      var result = PredictionResult()
      result.key = suffix
      if suffix == "たくさん" {
        #expect(prefixRid == 0)
        result.value = "沢山"
        result.cost = 5000
        return result
      } else if suffix == "たくの" {
        #expect(prefixRid == 0)
        result.value = "宅の"
        result.cost = 1000
        var builder = InnerSegmentBoundaryBuilder()
        builder.add(9, 6, 6, 3)  // 宅|の
        result.innerSegmentBoundary = builder.build(result.key, result.value)
        return result
      }

      // "の", "さん"
      result.key = suffix
      result.value = suffix
      result.cost = 500
      result.lid = modules.getPosMatcher().getFunctionalId()
      #expect(prefixRid == firstNameId)
      return result
    }

    let segmentsProxy = SegmentsProxy()

    // Learn "拓"
    do {
      let convreq = f.setUpInputForConversion("たく", segmentsProxy)
      segmentsProxy.addCandidate(0, "拓")
      segmentsProxy.mutateCandidate(0, 0) { $0.rid = firstNameId }
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
      #expect(f.isSuggested(predictor, "たく", "拓"))
    }

    var results: [PredictionResult] = []

    // Cost-based filtering.  Rejected by boundary-based filtering.
    do {
      segmentsProxy.clear()
      _ = f.setUpInputForPrediction("たくさん", segmentsProxy)

      // trans(bos, first_name_id) + prefix_penalty(first_name_id) = 3599.
      // 3599 is added to the prefix wcost.

      // 3599 + 500(wcost) + {5000, 2000} > 5000(full_cost) -> NG
      f.request.decoderExperimentParams.userHistoryPartialPrefixWcost = 5000
      f.request.decoderExperimentParams.userHistoryPartialWeakPrefixWcost = 2000
      var convreq = part5RebuildRequest(f, .prediction, segmentsProxy)
      results = predictor.predict(convreq)
      #expect(results.isEmpty)

      // 3599 + 500(wcost) + {2000} > 5000(full_cost) -> NG
      // 3599 + 500(wcost) + {0} < 5000(full_cost) -> OK, but weak mode.
      f.request.decoderExperimentParams.userHistoryPartialPrefixWcost = 2000
      f.request.decoderExperimentParams.userHistoryPartialWeakPrefixWcost = 0
      convreq = part5RebuildRequest(f, .prediction, segmentsProxy)
      results = predictor.predict(convreq)
      try #require(!results.isEmpty)  // Weak.
      #expect(results[0].value == "拓さん")
      #expect(results[0].key == "たくさん")
      #expect(results[0].attributes & Attribute.weakUserHistoryPrediction != 0)
      #expect("たくさん,拓さん,たく,拓" == Fixture.getKeyValueWithBoundary(results[0]))

      // 3599 + 500(wcost) + {100, 0} < 5000(full_cost) -> OK
      f.request.decoderExperimentParams.userHistoryPartialPrefixWcost = 100
      f.request.decoderExperimentParams.userHistoryPartialWeakPrefixWcost = 0
      convreq = part5RebuildRequest(f, .prediction, segmentsProxy)
      results = predictor.predict(convreq)
      try #require(!results.isEmpty)  // Not weak.
      #expect(results[0].value == "拓さん")
      #expect(results[0].key == "たくさん")
      #expect(results[0].attributes & Attribute.weakUserHistoryPrediction == 0)
      #expect("たくさん,拓さん,たく,拓" == Fixture.getKeyValueWithBoundary(results[0]))
    }

    // Boundary-based filtering -> always non-weak mode.
    do {
      segmentsProxy.clear()
      // Too aggressive wcost so that cost-based filtering rejects the partial
      // match.
      f.request.decoderExperimentParams.userHistoryPartialPrefixWcost = 10000
      f.request.decoderExperimentParams.userHistoryPartialWeakPrefixWcost = 10000
      let convreq = f.setUpInputForPrediction("たくの", segmentsProxy)
      results = predictor.predict(convreq)
      try #require(!results.isEmpty)
      #expect(results[0].value == "拓の")
      #expect(results[0].key == "たくの")
      #expect(results[0].attributes & Attribute.weakUserHistoryPrediction == 0)
      #expect("たくの,拓の,たく,拓" == Fixture.getKeyValueWithBoundary(results[0]))
    }

    // General noun is typed recently -> Weak mode.
    do {
      segmentsProxy.clear()
      let convreq = f.setUpInputForPrediction("たく", segmentsProxy)
      segmentsProxy.addCandidate(0, "宅")  // General noun.
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
      #expect(f.isSuggested(predictor, "たく", "拓"))
      #expect(f.isSuggested(predictor, "たく", "宅"))

      let convreq2 = f.setUpInputForPrediction("たくの", segmentsProxy)
      results = predictor.predict(convreq2)
      try #require(results.count == 1)
      #expect(results[0].value == "拓の")  // Weak.
      #expect(results[0].key == "たくの")
      #expect(results[0].attributes & Attribute.weakUserHistoryPrediction != 0)
      #expect("たくの,拓の,たく,拓" == Fixture.getKeyValueWithBoundary(results[0]))
    }
  }

  @Test func compoundNounAndSentenceWithParticlesPartialMatchTest() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let data = try await Fixture.createDataAndPredictor()
    let modules = data.modules
    let realtimeDecoder = data.realtimeDecoder
    let predictor = data.predictor
    await predictor.wait()

    f.request.mixedConversion = true
    f.request.decoderExperimentParams.userHistoryEnableCompoundNounPartialMatch = true

    realtimeDecoder.decodeSuffixHandler = { request, prefixRid, suffix in
      var result = PredictionResult()
      if suffix == "たなかしょうてんは" {
        result.key = "たなかしょうてんは"
        result.value = "田中商店は"
        result.cost = 10000
        result.lid = modules.getPosMatcher().getFunctionalId()
        var builder = InnerSegmentBoundaryBuilder()
        builder.add(24, 12, 24, 12)
        builder.add(3, 3, 0, 0)
        result.innerSegmentBoundary = builder.build(result.key, result.value)
        return result
      }
      if suffix == "は" {
        result.key = "は"
        result.value = "は"
        result.cost = 500
        result.lid = modules.getPosMatcher().getFunctionalId()
        return result
      }
      return nil
    }

    let segmentsProxy = SegmentsProxy()

    // 1. Compound noun ("たなかしょうてん" -> "田中商店"):
    // Learned once with allow_partial_match = true -> Partial match is suggested.
    do {
      let convreq = f.setUpInputForConversion("たなかしょうてん", segmentsProxy)
      segmentsProxy.clear()
      segmentsProxy.addSegment("たなか")
      segmentsProxy.addCandidate(0, "田中")
      segmentsProxy.mutateCandidate(0, 0) { $0.rid = modules.getPosMatcher().getGeneralNounId() }

      segmentsProxy.addSegment("しょうてん")
      segmentsProxy.addCandidate(1, "商店")
      segmentsProxy.mutateCandidate(1, 0) { $0.rid = modules.getPosMatcher().getGeneralNounId() }

      // Learn compound noun once ("たなかしょうてん" -> "田中商店")
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)

      // Predict with suffix "は" -> "たなかしょうてんは"
      segmentsProxy.clear()
      let predictSuffixReq = f.setUpInputForPrediction("たなかしょうてんは", segmentsProxy)
      let results = predictor.predict(predictSuffixReq)

      let found = results.contains { $0.key == "たなかしょうてんは" && $0.value == "田中商店は" }
      #expect(found)

      // Convert with suffix "は" -> "たなかしょうてんは"
      segmentsProxy.clear()
      let convertSuffixReq = f.setUpInputForConversion("たなかしょうてんは", segmentsProxy)
      let convertResults = predictor.convert(convertSuffixReq)

      let convertFound = convertResults.contains {
        $0.key == "たなかしょうてんは" && $0.value == "田中商店は"
      }
      #expect(convertFound)
    }

    // 2. Sentence with particles ("きのうはおつかれ" -> "昨日はお疲れ"):
    // Learned once, but allow_partial_match = false because of the particle
    // -> Low frequency multi-segment sentence is NOT suggested.
    do {
      let convreq = f.setUpInputForConversion("きのうはおつかれ", segmentsProxy)
      segmentsProxy.clear()
      segmentsProxy.addSegment("きのうは")
      segmentsProxy.addCandidate(0, "昨日は")
      segmentsProxy.mutateCandidate(0, 0) {
        $0.innerSegmentBoundary = [
          encodeLengths(
            "きのうは".utf8.count, "昨日は".utf8.count, "きのう".utf8.count, "昨日".utf8.count)!
        ]
        $0.rid = modules.getPosMatcher().getFunctionalId()
      }

      segmentsProxy.addSegment("おつかれ")
      segmentsProxy.addCandidate(1, "お疲れ")
      segmentsProxy.mutateCandidate(1, 0) { $0.rid = modules.getPosMatcher().getGeneralNounId() }

      // Learned once
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)

      // Predict with suffix "さま" -> "きのうはおつかれさま"
      segmentsProxy.clear()
      let predictSuffixReq = f.setUpInputForPrediction("きのうはおつかれさま", segmentsProxy)
      let results = predictor.predict(predictSuffixReq)

      let found = results.contains { $0.key == "きのうはおつかれさま" }
      // Low frequency multi-segment sentence with particles must NOT be
      // suggested.
      #expect(!found)
    }
  }

  @Test func emptyInnerSegmentBoundaryAttributeTest() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let data = try await Fixture.createDataAndPredictor()
    let predictor = data.predictor
    await predictor.wait()

    // Entry 1: "今日" ("きょう" -> "今日") saved via Finish with a single-segment
    // placeholder inner segment boundary.
    let kKey1 = "きょう"
    let kValue1 = "今日"
    let segmentsProxy = SegmentsProxy()
    let convreq1 = f.setUpInputForPrediction(kKey1, segmentsProxy)
    segmentsProxy.addCandidate(0, kValue1)
    segmentsProxy.pushBackInnerSegmentBoundary(0, 0, 9, 6, 6, 3)
    predictor.finish(convreq1, segmentsProxy.makeLearningResults(), kRevertId)

    // Entry 2: "明日" ("あした" -> "明日") saved via InsertEntry without inner
    // segment boundary.
    let kKey2 = "あした"
    let kValue2 = "明日"
    Fixture.insertEntry(predictor, kKey2, kValue2)

    // Save to disk and reload to verify serialization and deserialization
    // for entries both with and without inner_segment_boundaries.
    let storage = predictor.storage
    storage.save()
    storage.load()

    do {
      let entryWithBoundary = storage.lookup(UserHistoryStorage.fingerprint(kKey1, kValue1))
      try #require(!entryWithBoundary.isNull)
      #expect(entryWithBoundary.entry.innerSegmentBoundary.count > 0)

      let entryWithoutBoundary = storage.lookup(UserHistoryStorage.fingerprint(kKey2, kValue2))
      try #require(!entryWithoutBoundary.isNull)
      #expect(entryWithoutBoundary.entry.innerSegmentBoundary.count == 0)
    }

    // Verify prediction result for Entry 1 ("今日" with inner_segment_boundary).
    do {
      segmentsProxy.clear()
      let convreq = f.setUpInputForPrediction(kKey1, segmentsProxy)
      let results = predictor.predict(convreq)
      try #require(!results.isEmpty)

      var found = false
      for res in results where res.key == kKey1 && res.value == kValue1 {
        #expect(res.attributes & Attribute.userHistoryEmptyInnerSegmentBoundary == 0)
        #expect(res.innerSegmentBoundary.isEmpty)
        found = true
        break
      }
      #expect(found)

      // Verify conversion result for Entry 1 (inner_segment_boundary is
      // populated).
      let convReq = f.setUpInputForConversion(kKey1, segmentsProxy)
      let convertResults = predictor.convert(convReq)
      try #require(!convertResults.isEmpty)

      var convertFound = false
      for res in convertResults where res.key == kKey1 && res.value == kValue1 {
        #expect(res.attributes & Attribute.userHistoryEmptyInnerSegmentBoundary == 0)
        #expect(!res.innerSegmentBoundary.isEmpty)
        convertFound = true
        break
      }
      #expect(convertFound)
    }

    // Verify prediction result for Entry 2 ("明日" without
    // inner_segment_boundary).
    do {
      segmentsProxy.clear()
      let convreq = f.setUpInputForPrediction(kKey2, segmentsProxy)
      let results = predictor.predict(convreq)
      try #require(!results.isEmpty)

      var found = false
      for res in results where res.key == kKey2 && res.value == kValue2 {
        #expect(res.attributes & Attribute.userHistoryEmptyInnerSegmentBoundary != 0)
        #expect(res.innerSegmentBoundary.isEmpty)
        found = true
        break
      }
      #expect(found)
    }
  }

  @Test func characterFormNormalization() async throws {
    guard let f = try await makeUserHistoryPredictorTestFixture() else { return }
    let predictor = f.getUserHistoryPredictorWithClearedHistory()
    let charFormManager = CharacterFormManager.getCharacterFormManager()
    charFormManager.clearHistory()

    // 1. Commit full-width number candidate "０１２３" for key "すうじ".
    do {
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForConversion("すうじ", segmentsProxy)
      segmentsProxy.addCandidate(0, "０１２３")
      segmentsProxy.pushBackInnerSegmentBoundary(
        0, 0, "すう".utf8.count, "０１".utf8.count, "すう".utf8.count, "０１".utf8.count)
      segmentsProxy.pushBackInnerSegmentBoundary(
        0, 0, "じ".utf8.count, "２３".utf8.count, "じ".utf8.count, "２３".utf8.count)
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
    }

    // 2. When CharacterFormManager preferences are set to HALF_WIDTH,
    // UserHistoryPredictor must dynamically normalize the suggestion/conversion
    // to "0123" and update inner_segment_boundary when populated.
    do {
      charFormManager.setCharacterForm("0", .halfWidth)
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForPrediction("すう", segmentsProxy)
      let results = predictor.predict(convreq)
      try #require(!results.isEmpty)
      #expect(results[0].value == "0123")

      let convReq = f.setUpInputForConversion("すうじ", segmentsProxy)
      let convertResults = predictor.convert(convReq)
      try #require(!convertResults.isEmpty)
      #expect(convertResults[0].value == "0123")
      #expect(
        convertResults[0].innerSegmentBoundary
          == buildInnerSegmentBoundary(
            [
              ("すう".utf8.count, "01".utf8.count, "すう".utf8.count, "01".utf8.count),
              ("じ".utf8.count, "23".utf8.count, "じ".utf8.count, "23".utf8.count),
            ], "すうじ", "0123"))
    }

    // 3. When CharacterFormManager preferences are set to FULL_WIDTH,
    // UserHistoryPredictor must dynamically normalize the suggestion/conversion
    // to "０１２３" and update inner_segment_boundary when populated.
    do {
      charFormManager.setCharacterForm("0", .fullWidth)
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForPrediction("すう", segmentsProxy)
      let results = predictor.predict(convreq)
      try #require(!results.isEmpty)
      #expect(results[0].value == "０１２３")

      let convReq = f.setUpInputForConversion("すうじ", segmentsProxy)
      let convertResults = predictor.convert(convReq)
      try #require(!convertResults.isEmpty)
      #expect(convertResults[0].value == "０１２３")
      #expect(
        convertResults[0].innerSegmentBoundary
          == buildInnerSegmentBoundary(
            [
              ("すう".utf8.count, "０１".utf8.count, "すう".utf8.count, "０１".utf8.count),
              ("じ".utf8.count, "２３".utf8.count, "じ".utf8.count, "２３".utf8.count),
            ], "すうじ", "０１２３"))
    }

    // 4. UserHistoryPredictor::Finish() does not modify CharacterFormManager
    // preferences (character form learning is handled solely by
    // VariantsRewriter::Finish()), preventing unselected n-best candidates in
    // `results` from overwriting the user's selected character form.
    do {
      charFormManager.setCharacterForm("0", .fullWidth)
      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForConversion("べつのきー", segmentsProxy)
      // Simulate a 1-segment commit where index 0 is full-width "９９９" and
      // index 1 (unselected n-best) is half-width "999".
      segmentsProxy.addCandidate(0, "９９９")
      segmentsProxy.addCandidate(0, "999")
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)

      #expect(charFormManager.getConversionCharacterForm("0") == .fullWidth)
    }

    // 5. User dictionary and NO_VARIANTS_EXPANSION results (including subsequent
    // predictions from user history) should not overwrite CharacterFormManager
    // preferences.
    do {
      charFormManager.setCharacterForm("A", .fullWidth)
      charFormManager.setCharacterForm("0", .fullWidth)

      let segmentsProxy = SegmentsProxy()
      let convreq = f.setUpInputForConversion("ぐーぐる", segmentsProxy)
      segmentsProxy.addCandidate(0, "Google")
      segmentsProxy.mutateCandidate(0, 0) {
        $0.attributes = Attribute.realtimeConversion | Attribute.userDictionary
      }
      predictor.finish(convreq, segmentsProxy.makeLearningResults(), kRevertId)
      #expect(charFormManager.getConversionCharacterForm("A") == .fullWidth)

      // Committing "Google" when predicted from user history (which carries
      // USER_HISTORY_PREDICTION | NO_VARIANTS_EXPANSION without USER_DICTIONARY)
      // must also preserve the FULL_WIDTH preference.
      segmentsProxy.clear()
      let predReq = f.setUpInputForPrediction("ぐー", segmentsProxy)
      let historyResults = predictor.predict(predReq)
      try #require(!historyResults.isEmpty)
      #expect(historyResults[0].value == "Google")
      predictor.finish(predReq, Array(historyResults.prefix(1)), kRevertId)
      #expect(charFormManager.getConversionCharacterForm("A") == .fullWidth)

      segmentsProxy.clear()
      let dateReq = f.setUpInputForConversion("きょう", segmentsProxy)
      segmentsProxy.addCandidate(0, "2026/10/04")
      segmentsProxy.mutateCandidate(0, 0) { $0.attributes = Attribute.noVariantsExpansion }
      predictor.finish(dateReq, segmentsProxy.makeLearningResults(), kRevertId)
      #expect(charFormManager.getConversionCharacterForm("0") == .fullWidth)
    }

    // Restore CharacterFormManager default state.
    charFormManager.setDefaultRule()
    charFormManager.clearHistory()
  }
}
