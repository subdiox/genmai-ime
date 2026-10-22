// Port of mozc/src/rewriter/language_aware_rewriter_test.cc (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

@Suite(.enabled(if: ConverterCoreTestSupport.hasMockData, ConverterCoreTestSupport.mockDataMissing))
struct LanguageAwareRewriterTests {
  private static func insertASCIISequence(_ text: String, _ composer: inout Composer) {
    for b in text.utf8 {
      var key = Genmai_Commands_KeyEvent()
      key.keyCode = UInt32(b)
      _ = composer.insertCharacterKeyEvent(key)
    }
  }

  private func rewriteWithLanguageAwareInput(
    _ rewriter: LanguageAwareRewriter, _ key: String, _ isMobile: Bool,
    _ composition: inout String, _ segments: Segments
  ) -> Bool {
    var clientRequest = Genmai_Commands_Request()
    clientRequest.languageAwareInput = .languageAwareSuggestion

    if isMobile {
      clientRequest.zeroQuerySuggestion = true
      clientRequest.mixedConversion = true
    }

    let table = Table()
    let defaultConfig = Genmai_Config_Config()
    table.initializeWithRequestAndConfig(clientRequest, defaultConfig)

    var composer = Composer(table, clientRequest, defaultConfig)
    Self.insertASCIISequence(key, &composer)
    composition = composer.getStringForPreedit()

    // Perform the rewrite command.
    if segments.conversionSegmentsSize == 0 {
      _ = segments.addSegment()
    }
    let segment = segments.mutableConversionSegment(0)
    segment.setKey(composition)
    let request = ConversionRequestBuilder()
      .setComposer(composer)
      .setRequest(clientRequest)
      .setRequestType(.suggestion)
      .build()

    return rewriter.rewrite(request, segments)
  }

  private static func pushFrontCandidate(_ data: String, _ segment: Segment) {
    pushFrontCandidate(data, 0, segment)
  }

  private static func pushFrontCandidate(
    _ data: String, _ attributes: UInt32, _ segment: Segment
  ) {
    let candidate = segment.pushFrontCandidate()
    candidate.value = data
    candidate.key = data
    candidate.contentValue = data
    candidate.contentKey = data
    if attributes != 0 {
      segment.mutableCandidate(0).attributes |= attributes
    }
  }

  // A matcher for converter::Candidate to test if a candidate has the given
  // value with "did you mean" annotation.
  private static func isLangAwareCandidate(_ value: String) -> (Candidate) -> Bool {
    { $0.key.bytesEqual(value) && $0.value.bytesEqual(value) }
  }

  @Test func languageAwareInput() throws {
    let dictionary = MockDictionary()
    let rewriter = LanguageAwareRewriter(try ConverterCoreTestSupport.mockPosMatcher(), dictionary)
    do {
      // "python" is composed to "ｐｙてょｎ", but "python" should be suggested,
      // because alphabet characters are in the middle of the word.
      var composition = ""
      let segments = Segments()
      #expect(rewriteWithLanguageAwareInput(rewriter, "python", false, &composition, segments))

      #expect(composition == "ｐｙてょｎ")
      try #require(segments.conversionSegmentsSize == 1)
      #expect(
        hasSingleCandidate(segments.conversionSegment(0), Self.isLangAwareCandidate("python")))
    }
    do {
      // On mobile, we insert the new candidate at the third position.
      var composition = ""
      let segments = Segments()
      let segment = segments.pushBackSegment()
      Self.pushFrontCandidate("cand3", segment)
      Self.pushFrontCandidate("cand2", segment)
      Self.pushFrontCandidate("cand1", segment)
      Self.pushFrontCandidate("cand0", segment)
      try #require(segment.candidatesSize == 4)
      #expect(rewriteWithLanguageAwareInput(rewriter, "python", true, &composition, segments))
      #expect(composition == "ｐｙてょｎ")
      try #require(segments.conversionSegmentsSize == 1)
      #expect(segments.conversionSegment(0).candidate(2).value == "python")
      #expect(segments.conversionSegment(0).candidate(2).prefix.isEmpty)
    }
    do {
      // On mobile, the candidate is inserted after the typing correction.
      var composition = ""
      let segments = Segments()
      let segment = segments.pushBackSegment()
      Self.pushFrontCandidate("cand4", segment)
      Self.pushFrontCandidate("cand3", Attribute.typingCorrection, segment)
      Self.pushFrontCandidate("cand2", Attribute.typingCorrection, segment)
      Self.pushFrontCandidate("cand1", segment)
      Self.pushFrontCandidate("cand0", segment)
      try #require(segment.candidatesSize == 5)
      #expect(
        rewriteWithLanguageAwareInput(
          rewriter, "python", true, &composition, segments))  // is_mobile
      #expect(composition == "ｐｙてょｎ")
      try #require(segments.conversionSegmentsSize == 1)
      #expect(segments.conversionSegment(0).candidate(4).value == "python")
      #expect(segments.conversionSegment(0).candidate(4).prefix.isEmpty)
    }
    do {
      // "mozuk" is composed to "もずｋ", then "mozuk" is not suggested.
      // The trailing alphabet characters are not counted.
      var composition = ""
      let segments = Segments()
      #expect(
        !rewriteWithLanguageAwareInput(
          rewriter, "mozuk", false, &composition, segments))  // is_mobile

      #expect(composition == "もずｋ")
      try #require(segments.conversionSegmentsSize == 1)
      #expect(segments.conversionSegment(0).candidatesSize == 0)
    }
    do {
      // "house" is composed to "ほうせ".  Since "house" is in the dictionary
      // unlike the above "mozuk" case, "house" should be suggested.
      var composition = ""
      let segments = Segments()
      let segment = segments.pushBackSegment()
      // Add three candidates: ["cand0", "cand1", "cand2"].
      Self.pushFrontCandidate("cand2", segment)
      Self.pushFrontCandidate("cand1", segment)
      Self.pushFrontCandidate("cand0", segment)
      try #require(segment.candidatesSize == 3)

      // Set up the mock dictionary: "ほうせ" -> "house" doesn't exist but
      // there's an entry whose value is "house".
      var hasKeyCalls = 0
      var hasValueCalls = 0
      dictionary.hasKeyHandler = { key in
        if key == "ほうせ" { hasKeyCalls += 1 }
        return false
      }
      dictionary.hasValueHandler = { value in
        if value == "house" {
          hasValueCalls += 1
          return true
        }
        return false
      }

      // "house" should be inserted as the 3rd candidate (b/w cand1 and cand2).
      // => ["cand0", "cand1", "house", "cand2"]
      #expect(
        rewriteWithLanguageAwareInput(
          rewriter, "house", false, &composition, segments))  // is_mobile
      #expect(composition == "ほうせ")
      #expect(
        candidatesAreArray(
          segment,
          [
            valueIs("cand0"),
            valueIs("cand1"),
            Self.isLangAwareCandidate("house"),
            valueIs("cand2"),
          ]))
      #expect(hasKeyCalls == 1)
      #expect(hasValueCalls == 1)
      dictionary.hasKeyHandler = nil
      dictionary.hasValueHandler = nil
    }
    do {
      // Set up the mock dictionary: there's an entry whose value is "house".
      var hasValueCalls = 0
      dictionary.hasValueHandler = { value in
        if value == "query" {
          hasValueCalls += 1
          return true
        }
        return false
      }

      // "query" is composed to "くえｒｙ".  Since "query" is in the dictionary
      // unlike the above "mozuk" case, "query" should be suggested.
      var composition = ""
      let segments = Segments()
      #expect(
        rewriteWithLanguageAwareInput(
          rewriter, "query", false, &composition, segments))  // is_mobile

      #expect(composition == "くえｒｙ")
      try #require(segments.conversionSegmentsSize == 1)
      #expect(
        hasSingleCandidate(segments.conversionSegment(0), Self.isLangAwareCandidate("query")))
      #expect(hasValueCalls == 1)
      dictionary.hasValueHandler = nil
    }
    do {
      // "google" is composed to "google" by mode_switching_handler.
      // If the suggestion is equal to the composition, that suggestion
      // is not added.
      var composition = ""
      let segments = Segments()
      #expect(
        !rewriteWithLanguageAwareInput(
          rewriter, "google", false, &composition, segments))  // is_mobile
      #expect(composition == "google")
    }
    do {
      // Set up the mock dictionary.
      dictionary.hasKeyHandler = { $0 == "なる" }
      dictionary.hasValueHandler = { $0 == "なる" || $0 == "naru" }

      // The key "なる" has two value "naru" and "なる".
      // In this case, language aware rewriter should not be triggered.
      var composition = ""
      let segments = Segments()
      #expect(
        !rewriteWithLanguageAwareInput(
          rewriter, "naru", false, &composition, segments))  // is_mobile

      #expect(composition == "なる")
      try #require(segments.conversionSegmentsSize == 1)
      #expect(segments.conversionSegment(0).candidatesSize == 0)
      dictionary.hasKeyHandler = nil
      dictionary.hasValueHandler = nil
    }
  }

  @Test func notRewriteFullWidthAsciiToHalfWidthAscii() throws {
    let dictionary = MockDictionary()
    let rewriter = LanguageAwareRewriter(try ConverterCoreTestSupport.mockPosMatcher(), dictionary)
    do {
      // "1d*=" is composed to "１ｄ＊＝", which are the full width ascii
      // characters of "1d*=". We do not want to rewrite full width ascii to
      // half width ascii by LanguageAwareRewriter.
      var composition = ""
      let segments = Segments()
      #expect(
        !rewriteWithLanguageAwareInput(
          rewriter, "1d*=", false, &composition, segments))  // is_mobile
      #expect(composition == "１ｄ＊＝")
    }
    do {
      // "xyzw" is composed to "ｘｙｚｗ". Do not rewrite.
      var composition = ""
      let segments = Segments()
      #expect(
        !rewriteWithLanguageAwareInput(
          rewriter, "xyzw", false, &composition, segments))  // is_mobile
      #expect(composition == "ｘｙｚｗ")
    }
  }

  @Test func isDisabledInTwelveKeyLayout() throws {
    struct Param {
      let table: Genmai_Commands_Request.SpecialRomanjiTable
      let preeditMethod: Genmai_Config_Config.PreeditMethod
      let type: Rewriter.CapabilityType
    }
    let kParams: [Param] = [
      // Enabled combinations.
      Param(table: .defaultTable, preeditMethod: .roman, type: [.suggestion, .prediction]),
      Param(
        table: .qwertyMobileToHiragana, preeditMethod: .roman, type: [.suggestion, .prediction]),
      // Disabled combinations.
      Param(table: .defaultTable, preeditMethod: .kana, type: .notAvailable),
      Param(table: .twelveKeysToHiragana, preeditMethod: .roman, type: .notAvailable),
      Param(table: .toggleFlickToHiragana, preeditMethod: .roman, type: .notAvailable),
      Param(table: .godanToHiragana, preeditMethod: .roman, type: .notAvailable),
    ]

    let dictionary = MockDictionary()
    let rewriter = LanguageAwareRewriter(try ConverterCoreTestSupport.mockPosMatcher(), dictionary)
    for param in kParams {
      var request = Genmai_Commands_Request()
      request.languageAwareInput = .languageAwareSuggestion
      request.specialRomanjiTable = param.table

      var config = Genmai_Config_Config()
      config.preeditMethod = param.preeditMethod

      let table = Table()
      table.initializeWithRequestAndConfig(request, config)

      var composer = Composer(table, request, config)
      Self.insertASCIISequence("query", &composer)

      let convRequest = ConversionRequestBuilder()
        .setComposer(composer)
        .setRequest(request)
        .setConfig(config)
        .build()

      #expect(rewriter.capability(convRequest) == param.type)
    }
  }
}
