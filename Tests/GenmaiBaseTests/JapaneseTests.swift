// Port of mozc/src/base/strings/japanese_test.cc (3.35.6354).

import Testing
@testable import GenmaiBase

@Suite struct JapaneseUtilTest {
  @Test func hiraganaToKatakana() {
    do {
      let input =
        "あいうえおぁぃぅぇぉかきくけこがぎぐげごさしすせそざじずぜぞたちつてと"
        + "だぢづでどっなにぬねのはひふへほばびぶべぼぱぴぷぺぽまみむめもやゆよゃ"
        + "ゅょらりるれろわゎをんゔ"
      let output = Japanese.hiraganaToKatakana(input)
      #expect(
        output.bytesEqual(
          "アイウエオァィゥェォカキクケコガギグゲゴサシスセソザジズゼゾタチツテト"
            + "ダヂヅデドッナニヌネノハヒフヘホバビブベボパピプペポマミムメモヤユヨャ"
            + "ュョラリルレロワヮヲンヴ"))
    }
    do {
      let output = Japanese.hiraganaToKatakana("わたしのなまえはなかのですうまーよろしゅう")
      #expect(output.bytesEqual("ワタシノナマエハナカノデスウマーヨロシュウ"))
    }
    do {
      let output = Japanese.hiraganaToKatakana("グーグル工藤よろしくabc")
      #expect(output.bytesEqual("グーグル工藤ヨロシクabc"))
    }
  }

  @Test func katakanaToHiragana() {
    do {
      let input =
        "アイウエオァィゥェォカキクケコガギグゲゴサシスセソザジズゼゾタチツテト"
        + "ダヂヅデドッナニヌネノハヒフヘホバビブベボパピプペポマミムメモヤユヨャ"
        + "ュョラリルレロワヮヲンヰヱヴ"
      let output = Japanese.katakanaToHiragana(input)
      #expect(
        output.bytesEqual(
          "あいうえおぁぃぅぇぉかきくけこがぎぐげごさしすせそざじずぜぞたちつてと"
            + "だぢづでどっなにぬねのはひふへほばびぶべぼぱぴぷぺぽまみむめもやゆよゃ"
            + "ゅょらりるれろわゎをんゐゑゔ"))
    }
    do {
      let output = Japanese.katakanaToHiragana("ワタシノナマエハナカノデスウマーヨロシュウ")
      #expect(output.bytesEqual("わたしのなまえはなかのですうまーよろしゅう"))
    }
    do {
      let output = Japanese.katakanaToHiragana("グーグル工藤ヨロシクabc")
      #expect(output.bytesEqual("ぐーぐる工藤よろしくabc"))
    }
  }

  @Test func romanjiToHiragana() {
    let kTestCases: [(String, String)] = [
      ("watasinonamaehatakahashinoriyukidesu", "わたしのなまえはたかはしのりゆきです"),
      ("majissukamajiyabexe", "まじっすかまじやべぇ"),
      ("kk", "っk"),
      ("xyz", "xyz"),
    ]
    for (input, expected) in kTestCases {
      #expect(Japanese.romanjiToHiragana(input).bytesEqual(expected))
    }
  }

  @Test func hiraganaToRomanji() {
    let kTestCases: [(String, String)] = [
      ("わたしのなまえはたかはしのりゆきです", "watasinonamaehatakahasinoriyukidesu"),
      ("まじっすかまじやべぇ", "mazissukamaziyabexe"),
      ("おっっっ", "oxtuxtuxtu"),
      ("おっっっと", "oxtuxtutto"),
      ("らーめん", "ra-men"),
      ("かんな", "kanna"),
      ("かんnな", "kannna"),
      ("はんにゃ", "hannya"),
      ("はんnにゃ", "hannnya"),
      ("xyz", "xyz"),
    ]
    for (input, expected) in kTestCases {
      #expect(Japanese.hiraganaToRomanji(input).bytesEqual(expected))
    }
  }

  @Test func normalizeVoicedSoundMark() {
    let output = Japanese.normalizeVoicedSoundMark("僕のう゛ぁいおりん")
    #expect(output.bytesEqual("僕のゔぁいおりん"))
  }

  @Test func fullWidthAndHalfWidth() {
    #expect(Japanese.fullWidthToHalfWidth("") == "")
    #expect(Japanese.halfWidthToFullWidth("") == "")
    #expect(Japanese.halfWidthToFullWidth("abc[]?.").bytesEqual("ａｂｃ［］？．"))
    #expect(Japanese.halfWidthToFullWidth("ｲﾝﾀｰﾈｯﾄ｢」").bytesEqual("インターネット「」"))
    #expect(Japanese.halfWidthToFullWidth("ｲﾝﾀｰﾈｯﾄグーグル").bytesEqual("インターネットグーグル"))
    #expect(Japanese.fullWidthToHalfWidth("ａｂｃ［］？．").bytesEqual("abc[]?."))
    #expect(Japanese.fullWidthToHalfWidth("インターネット").bytesEqual("ｲﾝﾀｰﾈｯﾄ"))
    #expect(Japanese.fullWidthToHalfWidth("ｲﾝﾀｰﾈｯﾄグーグル").bytesEqual("ｲﾝﾀｰﾈｯﾄｸﾞｰｸﾞﾙ"))

    // spaces
    // Half- and full-width spaces -> 2 half-width spaces
    #expect(Japanese.fullWidthToHalfWidth(" 　").bytesEqual("  "))
    // Half- and full-width spaces -> 2 full-width spaces
    #expect(Japanese.halfWidthToFullWidth(" 　").bytesEqual("　　"))

    // Spaces are treated as Ascii here
    #expect(Japanese.fullWidthAsciiToHalfWidthAscii(" 　").bytesEqual("  "))
    #expect(Japanese.halfWidthAsciiToFullWidthAscii("  ").bytesEqual("　　"))

    // Not changed
    #expect(Japanese.fullWidthKatakanaToHalfWidthKatakana(" 　").bytesEqual(" 　"))
    #expect(Japanese.halfWidthKatakanaToFullWidthKatakana(" 　").bytesEqual(" 　"))
  }

  @Test func alignTest() {
    func check(_ actual: [(String, String)], _ expected: [(String, String)]) {
      #expect(actual.count == expected.count)
      for (a, e) in zip(actual, expected) {
        #expect(a.0.bytesEqual(e.0))
        #expect(a.1.bytesEqual(e.1))
      }
    }
    check(
      Japanese.alignRomanjiToHiragana("gakkou"),
      [("ga", "が"), ("k", "っ"), ("ko", "こ"), ("u", "う")])

    check(
      Japanese.alignHiraganaToRomanji("がっこう"), [("が", "ga"), ("っこ", "kko"), ("う", "u")])

    check(
      Japanese.alignRomanjiToHiragana("resipinokalzenn"),
      [
        ("re", "れ"), ("si", "し"), ("pi", "ぴ"), ("no", "の"), ("ka", "か"), ("l", "l"),
        ("ze", "ぜ"), ("nn", "ん"),
      ])
  }
}
