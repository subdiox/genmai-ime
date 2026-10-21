// Port of mozc/src/rewriter/transliteration_rewriter_test.cc (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiProtocol
import Testing
@testable import GenmaiCore

private func insertASCIISequence(_ text: String, _ composer: inout Composer) {
  for c in text.utf8 {
    var key = Genmai_Commands_KeyEvent()
    key.keyCode = UInt32(c)
    composer.insertCharacterKeyEvent(key)
  }
}

private func setAkann(_ composer: inout Composer) {
  insertASCIISequence("akann", &composer)
  #expect(composer.getQueryForConversion() == "あかん")
}

private let transliterationMockData: MockDataManager? = try? MockDataManager()


private func meta(_ seg: Segment, _ type: TransliterationType) -> Candidate {
  seg.metaCandidate(type.rawValue)
}

/// Checks all 11 meta candidate values in TransliterationType order.
private func expectMetaValues(
  _ seg: Segment, _ expected: [TransliterationType: String],
  sourceLocation: SourceLocation = #_sourceLocation
) {
  for (type, value) in expected {
    #expect(
      meta(seg, type).value.bytesEqual(value),
      "\(type): \(meta(seg, type).value) != \(value)", sourceLocation: sourceLocation)
  }
}

private func uniformMeta(_ value: String, halfKatakana: String) -> [TransliterationType: String] {
  var result: [TransliterationType: String] = [:]
  for type in TransliterationType.allCases {
    result[type] = value
  }
  result[.fullKatakana] = nil
  result[.halfKatakana] = halfKatakana
  return result
}

@Suite(
  .enabled(
    if: DataManagerTestSupport.hasMockData,
    "mock_genmai.data is missing; build //data_manager/testing:mozc_dataset_for_testing"))
struct TransliterationRewriterTests {
  let defaultRequest = Genmai_Commands_Request()
  let defaultConfig: Genmai_Config_Config = {
    var config = Genmai_Config_Config()
    ConfigHandler.getDefaultConfig(&config)
    return config
  }()

  func createTransliterationRewriter() -> TransliterationRewriter {
    TransliterationRewriter(PosMatcher(transliterationMockData!.getPosMatcherData()))
  }

  func makeTable(_ request: Genmai_Commands_Request) -> Table {
    let table = Table()
    table.initializeWithRequestAndConfig(request, defaultConfig)
    return table
  }

  @Test func t13nFromKeyTest() {
    let t13nRewriter = createTransliterationRewriter()
    let segments = Segments()
    let segment = segments.addSegment()
    segment.setKey("あかん")
    #expect(segment.metaCandidatesSize == 0)
    let defaultRequest = ConversionRequest()
    #expect(t13nRewriter.rewrite(defaultRequest, segments))
    do {
      expectMetaValues(
        segment,
        [
          .hiragana: "あかん", .fullKatakana: "アカン", .halfAscii: "akan", .halfAsciiUpper: "AKAN",
          .halfAsciiLower: "akan", .halfAsciiCapitalized: "Akan", .fullAscii: "ａｋａｎ",
          .fullAsciiUpper: "ＡＫＡＮ", .fullAsciiLower: "ａｋａｎ", .fullAsciiCapitalized: "Ａｋａｎ",
          .halfKatakana: "ｱｶﾝ",
        ])
      for i in 0..<segment.metaCandidatesSize {
        #expect(segment.metaCandidate(i).lid != 0)
        #expect(segment.metaCandidate(i).rid != 0)
        #expect(!segment.metaCandidate(i).key.isEmpty)
      }
    }
  }

  @Test func t13nFromComposerTest() {
    let t13nRewriter = createTransliterationRewriter()

    let table = makeTable(defaultRequest)
    var composer = Composer(table, defaultRequest, defaultConfig)
    setAkann(&composer)

    let segments = Segments()
    let segment = segments.addSegment()

    let request = ConversionRequestBuilder().setComposer(composer).build()
    segment.setKey("あかん")
    #expect(t13nRewriter.rewrite(request, segments))
    do {
      #expect(segments.conversionSegmentsSize == 1)
      let seg = segments.conversionSegment(0)
      expectMetaValues(
        seg,
        [
          .hiragana: "あかん", .fullKatakana: "アカン", .halfAscii: "akann",
          .halfAsciiUpper: "AKANN", .halfAsciiLower: "akann", .halfAsciiCapitalized: "Akann",
          .fullAscii: "ａｋａｎｎ", .fullAsciiUpper: "ＡＫＡＮＮ", .fullAsciiLower: "ａｋａｎｎ",
          .fullAsciiCapitalized: "Ａｋａｎｎ", .halfKatakana: "ｱｶﾝ",
        ])
      for i in 0..<segment.metaCandidatesSize {
        #expect(segment.metaCandidate(i).lid != 0)
        #expect(segment.metaCandidate(i).rid != 0)
        #expect(!segment.metaCandidate(i).key.isEmpty)
      }
    }
  }

  @Test func keyOfT13nFromComposerTest() {
    let t13nRewriter = createTransliterationRewriter()

    let table = makeTable(defaultRequest)
    var composer = Composer(table, defaultRequest, defaultConfig)
    insertASCIISequence("ssh", &composer)

    let segments = Segments()
    let segment = segments.addSegment()

    var input = Genmai_Commands_Request()
    input.mixedConversion = true
    let request = ConversionRequestBuilder()
      .setComposer(composer)
      .setRequest(input)
      .setRequestType(.suggestion)
      .build()
    do {
      // Although the segment key is "っ" as a partial string of the full
      // composition, the transliteration key should be "っsh" as the
      // whole composition string.

      segment.setKey("っ")
      #expect(t13nRewriter.rewrite(request, segments))

      #expect(segments.conversionSegmentsSize == 1)
      let seg = segments.conversionSegment(0)

      #expect(meta(seg, .hiragana).value == "っｓｈ")
      #expect(meta(seg, .hiragana).key == "っsh")
      #expect(meta(seg, .halfAscii).value == "ssh")
      #expect(meta(seg, .halfAscii).key == "っsh")
    }
  }

  @Test func t13nWithMultiSegmentsTest() {
    let t13nRewriter = createTransliterationRewriter()

    let table = makeTable(defaultRequest)
    var composer = Composer(table, defaultRequest, defaultConfig)

    // Set kamabokoinbou to composer.
    do {
      insertASCIISequence("kamabokonoinbou", &composer)
      #expect(composer.getQueryForConversion() == "かまぼこのいんぼう")
    }

    let segments = Segments()
    let request = ConversionRequestBuilder().setComposer(composer).build()
    do {
      var segment = segments.addSegment()
      segment.setKey("かまぼこの")
      segment = segments.addSegment()
      segment.setKey("いんぼう")
    }

    #expect(t13nRewriter.rewrite(request, segments))
    #expect(segments.conversionSegmentsSize == 2)
    do {
      let seg = segments.conversionSegment(0)
      #expect(meta(seg, .hiragana).value == "かまぼこの")
      #expect(meta(seg, .halfAscii).value == "kamabokono")
    }
    do {
      let seg = segments.conversionSegment(1)
      #expect(meta(seg, .hiragana).value == "いんぼう")
      #expect(meta(seg, .halfAscii).value == "inbou")
    }
  }

  @Test func composerValidationTest() {
    let t13nRewriter = createTransliterationRewriter()

    let table = makeTable(defaultRequest)
    var composer = Composer(table, defaultRequest, defaultConfig)

    // Set kan to composer.
    do {
      insertASCIISequence("kan", &composer)
      #expect(composer.getQueryForConversion() == "かん")
    }

    let segments = Segments()
    let segment = segments.addSegment()

    let request = ConversionRequestBuilder().setComposer(composer).build()
    segment.setKey("かん")
    #expect(t13nRewriter.rewrite(request, segments))
    // Should not use composer
    do {
      #expect(segments.conversionSegmentsSize == 1)
      let seg = segments.conversionSegment(0)
      expectMetaValues(
        seg,
        [
          .hiragana: "かん", .fullKatakana: "カン", .halfAscii: "kan", .halfAsciiUpper: "KAN",
          .halfAsciiLower: "kan", .halfAsciiCapitalized: "Kan", .fullAscii: "ｋａｎ",
          .fullAsciiUpper: "ＫＡＮ", .fullAsciiLower: "ｋａｎ", .fullAsciiCapitalized: "Ｋａｎ",
          .halfKatakana: "ｶﾝ",
        ])
    }
  }

  @Test func rewriteWithSameComposerTest() {
    let t13nRewriter = createTransliterationRewriter()

    let table = makeTable(defaultRequest)

    var composer = Composer(table, defaultRequest, defaultConfig)
    setAkann(&composer)

    let segments = Segments()
    var segment = segments.addSegment()
    let request = ConversionRequestBuilder().setComposer(composer).build()
    segment.setKey("あかん")
    #expect(t13nRewriter.rewrite(request, segments))
    do {
      #expect(segments.conversionSegmentsSize == 1)
      let seg = segments.conversionSegment(0)
      expectMetaValues(
        seg,
        [
          .hiragana: "あかん", .fullKatakana: "アカン", .halfAscii: "akann",
          .halfAsciiUpper: "AKANN", .halfAsciiLower: "akann", .halfAsciiCapitalized: "Akann",
          .fullAscii: "ａｋａｎｎ", .fullAsciiUpper: "ＡＫＡＮＮ", .fullAsciiLower: "ａｋａｎｎ",
          .fullAsciiCapitalized: "Ａｋａｎｎ", .halfKatakana: "ｱｶﾝ",
        ])
    }

    // Resegmentation
    segment = segments.mutableSegment(0)
    segment.setKey("あか")

    segment = segments.addSegment()
    segment.setKey("ん")

    #expect(t13nRewriter.rewrite(request, segments))

    #expect(segments.conversionSegmentsSize == 2)
    do {
      let seg = segments.conversionSegment(0)
      expectMetaValues(
        seg,
        [
          .hiragana: "あか", .fullKatakana: "アカ", .halfAscii: "aka", .halfAsciiUpper: "AKA",
          .halfAsciiLower: "aka", .halfAsciiCapitalized: "Aka", .fullAscii: "ａｋａ",
          .fullAsciiUpper: "ＡＫＡ", .fullAsciiLower: "ａｋａ", .fullAsciiCapitalized: "Ａｋａ",
          .halfKatakana: "ｱｶ",
        ])
    }
    do {
      let seg = segments.conversionSegment(1)
      expectMetaValues(
        seg,
        [
          .hiragana: "ん", .fullKatakana: "ン", .halfAscii: "nn", .halfAsciiUpper: "NN",
          .halfAsciiLower: "nn", .halfAsciiCapitalized: "Nn", .fullAscii: "ｎｎ",
          .fullAsciiUpper: "ＮＮ", .fullAsciiLower: "ｎｎ", .fullAsciiCapitalized: "Ｎｎ",
          .halfKatakana: "ﾝ",
        ])
    }
  }

  @Test func noKeyTest() {
    let t13nRewriter = createTransliterationRewriter()

    let segments = Segments()
    var segment = segments.addSegment()
    segment.setKey("あ")
    segment = segments.addSegment()
    segment.setKey("")  // void key

    let request = ConversionRequest()
    #expect(t13nRewriter.rewrite(request, segments))
    #expect(segments.conversionSegmentsSize == 2)
    #expect(segments.conversionSegment(0).metaCandidatesSize != 0)
    #expect(segments.conversionSegment(1).metaCandidatesSize == 0)
  }

  @Test func noKeyWithComposerTest() {
    let t13nRewriter = createTransliterationRewriter()

    let table = makeTable(defaultRequest)
    var composer = Composer(table, defaultRequest, defaultConfig)
    insertASCIISequence("a", &composer)

    let segments = Segments()
    var segment = segments.addSegment()

    let request = ConversionRequestBuilder().setComposer(composer).build()

    segment.setKey("あ")
    segment = segments.addSegment()
    segment.setKey("")  // void key

    #expect(t13nRewriter.rewrite(request, segments))
    #expect(segments.conversionSegmentsSize == 2)
    #expect(segments.conversionSegment(0).metaCandidatesSize != 0)
    #expect(segments.conversionSegment(1).metaCandidatesSize == 0)
  }

  @Test func noRewriteTest() {
    let t13nRewriter = createTransliterationRewriter()

    _ = makeTable(defaultRequest)

    let segments = Segments()
    let segment = segments.addSegment()
    segment.setKey("亜")
    let request = ConversionRequest()
    #expect(!t13nRewriter.rewrite(request, segments))
    #expect(segments.conversionSegment(0).metaCandidatesSize == 0)
  }

  @Test func mobileEnvironmentTest() {
    var request = Genmai_Commands_Request()
    let rewriter = createTransliterationRewriter()
    do {
      request.mixedConversion = true
      let convreq = ConversionRequestBuilder().setRequest(request).build()
      #expect(rewriter.capability(convreq) == .all)
    }

    do {
      request.mixedConversion = false
      let convreq = ConversionRequestBuilder().setRequest(request).build()
      #expect(rewriter.capability(convreq) == .conversion)
    }
  }

  @Test func mobileT13nTestWith12KeysHiragana() {
    let t13nRewriter = createTransliterationRewriter()

    var request = Genmai_Commands_Request()
    RequestTestUtil.fillMobileRequest(&request)

    let table = makeTable(request)
    var composer = Composer(table, request, defaultConfig)

    do {
      insertASCIISequence("11#", &composer)
      #expect(composer.getQueryForConversion() == "い、")
    }
    let segments = Segments()
    let segment = segments.addSegment()
    segment.setKey("い、")
    let rewriteRequest = ConversionRequestBuilder()
      .setComposer(composer)
      .setRequest(request)
      .setConfig(defaultConfig)
      .build()
    #expect(t13nRewriter.rewrite(rewriteRequest, segments))

    // Do not want to show raw keys for implementation
    do {
      let seg = segments.conversionSegment(0)
      #expect(meta(seg, .fullKatakana).value == "イ、")
      expectMetaValues(seg, uniformMeta("い、", halfKatakana: "ｲ､"))
    }
  }

  @Test func mobileT13nTestWith12KeysToNumber() {
    let t13nRewriter = createTransliterationRewriter()

    var request = Genmai_Commands_Request()
    RequestTestUtil.fillMobileRequest(&request)

    let table = makeTable(request)
    var composer = Composer(table, request, defaultConfig)

    do {
      insertASCIISequence("1212", &composer)
      #expect(composer.getQueryForConversion() == "あかあか")
    }
    let segments = Segments()
    let segment = segments.addSegment()
    segment.setKey("あかあか")
    let rewriteRequest = ConversionRequestBuilder()
      .setComposer(composer)
      .setRequest(request)
      .build()
    #expect(t13nRewriter.rewrite(rewriteRequest, segments))

    // Because NoTransliteration attribute is specified in the mobile romaji
    // table's entries, raw-key based meta-candidates are not shown.
    do {
      let seg = segments.conversionSegment(0)
      #expect(meta(seg, .fullKatakana).value == "アカアカ")
      expectMetaValues(seg, uniformMeta("あかあか", halfKatakana: "ｱｶｱｶ"))
    }
  }

  @Test func mobileT13nTestWith12KeysFlick() {
    let t13nRewriter = createTransliterationRewriter()

    var request = Genmai_Commands_Request()
    request.zeroQuerySuggestion = true
    request.mixedConversion = true
    request.specialRomanjiTable = .toggleFlickToHiragana

    let table = makeTable(request)
    var composer = Composer(table, request, defaultConfig)

    do {
      insertASCIISequence("1a", &composer)
      #expect(composer.getQueryForConversion() == "あき")
    }
    let segments = Segments()
    let segment = segments.addSegment()
    segment.setKey("あき")
    let rewriteRequest = ConversionRequestBuilder()
      .setComposer(composer)
      .setRequest(request)
      .build()
    #expect(t13nRewriter.rewrite(rewriteRequest, segments))

    // Do not want to show raw keys for implementation
    do {
      let seg = segments.conversionSegment(0)
      #expect(meta(seg, .fullKatakana).value == "アキ")
      expectMetaValues(seg, uniformMeta("あき", halfKatakana: "ｱｷ"))
    }
  }

  @Test func mobileT13nTestWithQwertyHiragana() {
    let t13nRewriter = createTransliterationRewriter()

    var clientRequest = Genmai_Commands_Request()
    clientRequest.zeroQuerySuggestion = true
    clientRequest.mixedConversion = true
    clientRequest.specialRomanjiTable = .qwertyMobileToHiragana

    let kShi = "し"
    let table = makeTable(clientRequest)

    do {
      var composer = Composer(table, clientRequest, defaultConfig)

      insertASCIISequence("shi", &composer)
      #expect(composer.getQueryForConversion() == kShi)

      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey(kShi)
      let request = ConversionRequestBuilder()
        .setComposer(composer)
        .setRequest(clientRequest)
        .build()
      #expect(t13nRewriter.rewrite(request, segments))

      let seg = segments.conversionSegment(0)
      #expect(meta(seg, .halfAscii).value == "shi")
    }

    do {
      var composer = Composer(table, clientRequest, defaultConfig)

      insertASCIISequence("si", &composer)
      #expect(composer.getQueryForConversion() == kShi)

      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey(kShi)
      let request = ConversionRequestBuilder()
        .setComposer(composer)
        .setRequest(clientRequest)
        .build()
      #expect(t13nRewriter.rewrite(request, segments))

      let seg = segments.conversionSegment(0)
      #expect(meta(seg, .halfAscii).value == "si")
    }
  }

  @Test func mobileT13nTestWithGodan() {
    let t13nRewriter = createTransliterationRewriter()

    var request = Genmai_Commands_Request()
    request.zeroQuerySuggestion = true
    request.mixedConversion = true
    request.specialRomanjiTable = .godanToHiragana

    let table = makeTable(request)
    var composer = Composer(table, request, defaultConfig)
    do {
      insertASCIISequence("<'de", &composer)
      #expect(composer.getQueryForConversion() == "あん゜で")
    }
    let segments = Segments()
    let segment = segments.addSegment()
    segment.setKey("あん゜で")
    let rewriteRequest = ConversionRequestBuilder()
      .setComposer(composer)
      .setRequest(request)
      .build()
    #expect(t13nRewriter.rewrite(rewriteRequest, segments))

    // Do not show raw keys.
    do {
      let seg = segments.conversionSegment(0)
      expectMetaValues(
        seg,
        [
          .hiragana: "あん゜で", .fullKatakana: "アン゜デ", .halfAscii: "annde",
          .halfAsciiUpper: "ANNDE", .halfAsciiLower: "annde", .halfAsciiCapitalized: "Annde",
          .fullAscii: "ａｎｎｄｅ", .fullAsciiUpper: "ＡＮＮＤＥ", .fullAsciiLower: "ａｎｎｄｅ",
          .fullAsciiCapitalized: "Ａｎｎｄｅ", .halfKatakana: "ｱﾝﾟﾃﾞ",
        ])
    }
  }

  @Test func mobileT13nTestValidateGodanT13nTable() {
    let t13nRewriter = createTransliterationRewriter()

    var request = Genmai_Commands_Request()
    request.zeroQuerySuggestion = true
    request.mixedConversion = true
    request.specialRomanjiTable = .godanToHiragana

    let table = makeTable(request)

    // Expected t13n of Godan keyboard.
    var keycodeToT13nMap = [String?](repeating: nil, count: 128)
    func set(_ c: Character, _ v: String) { keycodeToT13nMap[Int(c.asciiValue!)] = v }
    set("\"", "")
    set("'", "")
    set("`", "")
    set("$", "axtu")
    set("%", "ixtu")
    set("&", "uxtu")
    set("=", "extu")
    set("@", "oxtu")
    set("#", "ya")
    set("+", "xi")
    set("^", "yu")
    set("_", "xe")
    set("|", "yo")
    set("<", "ann")
    set(">", "inn")
    set("{", "unn")
    set("}", "enn")
    set("~", "onn")
    set("\\", "nn")
    set(";", "")

    for i in 0..<keycodeToT13nMap.count {
      // iscntrl(i)
      if i < 0x20 || i == 0x7F {
        continue
      }

      var composer = Composer(table, request, defaultConfig)

      let asciiInput = String(UnicodeScalar(UInt8(i)))
      insertASCIISequence(asciiInput, &composer)
      let query = composer.getQueryForConversion()
      let trace: Comment = "char code = \(i), ascii_input = \(asciiInput), query = \(query)"

      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey(query)
      let rewriteRequest = ConversionRequestBuilder()
        .setComposer(composer)
        .setRequest(request)
        .build()
      #expect(t13nRewriter.rewrite(rewriteRequest, segments) || query.isEmpty, trace)

      let seg = segments.conversionSegment(0)
      if seg.metaCandidatesSize <= TransliterationType.halfAscii.rawValue {
        // If no t13n happened, then should be no custom t13n.
        #expect(keycodeToT13nMap[i] == nil || keycodeToT13nMap[i] == "", trace)
      } else {
        let halfAscii = meta(seg, .halfAscii).value
        if let mapped = keycodeToT13nMap[i], !mapped.isEmpty {
          #expect(halfAscii.bytesEqual(mapped), trace)
        } else {
          #expect(halfAscii.bytesEqual(asciiInput) || halfAscii.bytesEqual(query), trace)
        }
      }
    }
  }

  @Test func t13nOnSuggestion() {
    let t13nRewriter = createTransliterationRewriter()

    var clientRequest = Genmai_Commands_Request()
    clientRequest.mixedConversion = true

    let kXtsu = "っ"

    let table = makeTable(clientRequest)
    do {
      var composer = Composer(table, clientRequest, defaultConfig)

      insertASCIISequence("ssh", &composer)
      #expect(composer.getQueryForPrediction() == kXtsu)

      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey(kXtsu)
      let request = ConversionRequestBuilder()
        .setComposer(composer)
        .setRequest(clientRequest)
        .setRequestType(.suggestion)
        .build()
      #expect(t13nRewriter.rewrite(request, segments))

      let seg = segments.conversionSegment(0)
      #expect(meta(seg, .halfAscii).value == "ssh")
    }
  }

  @Test func t13nOnPartialSuggestion() {
    let t13nRewriter = createTransliterationRewriter()

    var clientRequest = Genmai_Commands_Request()
    clientRequest.mixedConversion = true

    let kXtsu = "っ"

    let table = makeTable(clientRequest)
    do {
      var composer = Composer(table, clientRequest, defaultConfig)

      insertASCIISequence("ssh", &composer)  // "っsh|"
      #expect(composer.getQueryForPrediction() == kXtsu)

      composer.moveCursorTo(1)  // "っ|sh"

      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey(kXtsu)
      let request = ConversionRequestBuilder()
        .setComposer(composer)
        .setRequest(clientRequest)
        .setRequestType(.suggestion)
        .build()
      #expect(t13nRewriter.rewrite(request, segments))

      let seg = segments.conversionSegment(0)
      #expect(meta(seg, .halfAscii).value == "s")
    }
  }
}
