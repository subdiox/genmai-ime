// Port of mozc/src/base/util_test.cc (3.35.6354).

import Testing
@testable import GenmaiBase

@Suite struct UtilTest {
  @Test func appendUtf8Chars() {
    do {
      var output: [String] = []
      Util.appendUtf8Chars("", &output)
      #expect(output.isEmpty)
      var output2: [Substring] = []
      Util.appendUtf8Chars("", &output2)
      #expect(output2.isEmpty)
    }
    do {
      let kInputs = ["a", "あ", "亜", "\n", "a"]
      let joined = kInputs.joined()

      var output = ["x", "y", "z"]
      Util.appendUtf8Chars(joined, &output)
      #expect(output == ["x", "y", "z", "a", "あ", "亜", "\n", "a"])

      var output2: [Substring] = ["x", "y", "z"]
      Util.appendUtf8Chars(joined, &output2)
      #expect(output2 == ["x", "y", "z", "a", "あ", "亜", "\n", "a"])
    }
  }

  @Test func splitStringToUtf8Chars() {
    #expect(Util.splitStringToUtf8Chars("").isEmpty)
    let kInputs = ["a", "あ", "亜", "\n", "a"]
    #expect(Util.splitStringToUtf8Chars(kInputs.joined()) == kInputs)
    // Code points, not graphemes.
    #expect(Util.splitStringToUtf8Chars("あ\u{3099}").map { Array($0.utf8) } == [
      Array("あ".utf8), Array("\u{3099}".utf8),
    ])
  }

  private func checkGraphemes(_ kInputs: [String]) {
    let graphemes = Util.splitStringToUtf8Graphemes(kInputs.joined())
    #expect(graphemes.map { Array($0.utf8) } == kInputs.map { Array($0.utf8) })
  }

  @Test func splitStringToUtf8Graphemes() {
    // Single codepoint characters.
    checkGraphemes(["a", "あ", "亜", "\n", "a"])

    // Multiple codepoint characters
    checkGraphemes([
      "神",  // U+795E
      "神\u{FE00}",  // U+795E,U+FE00  - 2 codepoints [SVS]
      "神\u{E0100}",  // U+795E,U+E0100 - 2 codepoints [IVS]
      "あ\u{3099}",  // U+3042,U+3099  - 2 codepoints [Dakuten]
      "か\u{309A}",  // U+304B,U+309A  - 2 codepoints [Handakuten]
    ])

    // Multiple codepoint emojis
    checkGraphemes([
      "🛳\u{FE0E}",  // U+1F6F3,U+FE0E - text presentation sequence
      "🛳\u{FE0F}",  // U+1F6F3,U+FE0F - emoji presentation sequence
      "✌🏿",  // U+261D,U+1F3FF - emoji modifier sequence
      "🇯🇵",  // U+1F1EF,U+1F1F5 - emoji flag sequence
      "🏴\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}",  // emoji tag sequence
      "#\u{FE0F}\u{20E3}",  // U+0023,U+FE0F,U+20E3 - emoji keycap sequence
      "👨\u{200D}👩\u{200D}👧\u{200D}👦",  // emoji zwj sequence
    ])

    // Multiple emoji flag sequences
    checkGraphemes([
      "🇧🇸",  // U+1F1E7,U+1F1F8 - Bahamas (Country code: BS)
      "🇸🇧",  // U+1F1F8,U+1F1E7 - Solomon Islands (Country code: SB)
    ])

    // Invalid codepoint characters
    checkGraphemes([
      "\u{FE00}",  // Extend only [SVS]
      "神\u{FE00}\u{E0100}",  // Multiple extends [SVS, IVS]
      "🛳\u{FE0E}\u{FE0E}",  // Multiple extends [text_presentation_selector x2]
      "🛳\u{FE0F}\u{FE0F}",  // Multiple extends [emoji_presentation_selector x2]
      "✌🏿\u{1F3FF}",  // Multiple extends [emoji_modifier x2]
      "🏴\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}\u{E0067}",  // tag_end, tag
      "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{200D}\u{1F467}\u{200D}\u{1F466}",  // Successive ZWJ
    ])
  }

  @Test func splitCSV() {
    var answer = Util.splitCSV(#"Google,x,"Buchheit, Paul","string with "" quote in it""#)
    #expect(answer == ["Google", "x", "Buchheit, Paul", "string with \" quote in it"])

    answer = Util.splitCSV("Google,hello,")
    #expect(answer == ["Google", "hello", ""])

    answer = Util.splitCSV("Google rocks,hello")
    #expect(answer == ["Google rocks", "hello"])

    answer = Util.splitCSV(#",,"",,"#)
    #expect(answer == ["", "", "", "", ""])

    // Test a string containing a comma.
    answer = Util.splitCSV(#"",",hello"#)
    #expect(answer == [",", "hello"])

    // Invalid CSV
    answer = Util.splitCSV(#""no,last,quote"#)
    #expect(answer == ["no,last,quote"])

    answer = Util.splitCSV(#"backslash\,is,no,an,"escape""#)
    #expect(answer == ["backslash\\", "is", "no", "an", "escape"])

    answer = Util.splitCSV("")
    #expect(answer.isEmpty)
  }

  @Test func lowerString() {
    var s = "TeSTtest"
    Util.lowerString(&s)
    #expect(s == "testtest")

    var s2 = "ＴｅＳＴ＠ＡＢＣＸＹＺ［｀ａｂｃｘｙｚ｛"
    Util.lowerString(&s2)
    #expect(s2 == "ｔｅｓｔ＠ａｂｃｘｙｚ［｀ａｂｃｘｙｚ｛")
  }

  @Test func upperString() {
    var s = "TeSTtest"
    Util.upperString(&s)
    #expect(s == "TESTTEST")

    var s2 = "ＴｅＳＴ＠ＡＢＣＸＹＺ［｀ａｂｃｘｙｚ｛"
    Util.upperString(&s2)
    #expect(s2 == "ＴＥＳＴ＠ＡＢＣＸＹＺ［｀ＡＢＣＸＹＺ｛")
  }

  @Test func capitalizeString() {
    var s = "TeSTtest"
    Util.capitalizeString(&s)
    #expect(s == "Testtest")

    var s2 = "ＴｅＳＴ＠ＡＢＣＸＹＺ［｀ａｂｃｘｙｚ｛"
    Util.capitalizeString(&s2)
    #expect(s2 == "Ｔｅｓｔ＠ａｂｃｘｙｚ［｀ａｂｃｘｙｚ｛")
  }

  @Test func isLowerAscii() {
    #expect(Util.isLowerAscii(""))
    #expect(Util.isLowerAscii("hello"))
    #expect(!Util.isLowerAscii("HELLO"))
    #expect(!Util.isLowerAscii("Hello"))
    #expect(!Util.isLowerAscii("HeLlO"))
    #expect(!Util.isLowerAscii("symbol!"))
    #expect(!Util.isLowerAscii("Ｈｅｌｌｏ"))
  }

  @Test func isUpperAscii() {
    #expect(Util.isUpperAscii(""))
    #expect(!Util.isUpperAscii("hello"))
    #expect(Util.isUpperAscii("HELLO"))
    #expect(!Util.isUpperAscii("Hello"))
    #expect(!Util.isUpperAscii("HeLlO"))
    #expect(!Util.isUpperAscii("symbol!"))
    #expect(!Util.isUpperAscii("Ｈｅｌｌｏ"))
  }

  @Test func isCapitalizedAscii() {
    #expect(Util.isCapitalizedAscii(""))
    #expect(!Util.isCapitalizedAscii("hello"))
    #expect(!Util.isCapitalizedAscii("HELLO"))
    #expect(Util.isCapitalizedAscii("Hello"))
    #expect(!Util.isCapitalizedAscii("HeLlO"))
    #expect(!Util.isCapitalizedAscii("symbol!"))
    #expect(!Util.isCapitalizedAscii("Ｈｅｌｌｏ"))
  }

  @Test func utf8ToUtf32() {
    #expect(Util.utf8ToUtf32("") == [])
    // Single codepoint characters.
    #expect(Util.utf8ToUtf32("aあ亜\na") == [0x61, 0x3042, 0x4E9C, 0x0A, 0x61])
    // Multiple codepoint characters
    let kStr = "神" + "神\u{E0100}" + "あ\u{3099}"
    #expect(Util.utf8ToUtf32(kStr) == [0x795E, 0x795E, 0xE0100, 0x3042, 0x3099])
    #expect(Util.utf8ToUtf32(kStr.utf8) == [0x795E, 0x795E, 0xE0100, 0x3042, 0x3099])
    // Stops at an invalid sequence.
    #expect(Util.utf8ToUtf32(cBytes(#"a\xC2b"#)) == [0x61])
  }

  @Test func utf32ToUtf8() {
    #expect(Util.utf32ToUtf8([]) == "")
    // Single codepoint characters.
    #expect(Util.utf32ToUtf8([0x61, 0x3042, 0x4E9C, 0x0A, 0x61]).bytesEqual("aあ亜\na"))
    // Multiple codepoint characters
    let kExpected = "神" + "神\u{E0100}" + "あ\u{3099}"
    let kU32Str: [Char32] = [0x795E, 0x795E, 0xE0100, 0x3042, 0x3099]
    #expect(Util.utf32ToUtf8(kU32Str).bytesEqual(kExpected))
    #expect(Util.utf32ToUtf8Bytes(kU32Str) == Array(kExpected.utf8))
  }

  private func verifyUtf8ToCodepoint(_ text: [UInt8], _ expectedCodepoint: Char32, _ expectedLen: Int) {
    let result = Util.utf8ToCodepoint(text)
    #expect(result.codepoint == expectedCodepoint)
    #expect(result.mblen == expectedLen)
  }

  @Test func utf8ToCodepoint() {
    verifyUtf8ToCodepoint([], 0, 0)
    verifyUtf8ToCodepoint(cBytes(#"\x01"#), 1, 1)
    verifyUtf8ToCodepoint(cBytes(#"\x7F"#), 0x7F, 1)
    verifyUtf8ToCodepoint(cBytes(#"\xC2\x80"#), 0x80, 2)
    verifyUtf8ToCodepoint(cBytes(#"\xDF\xBF"#), 0x7FF, 2)
    verifyUtf8ToCodepoint(cBytes(#"\xE0\xA0\x80"#), 0x800, 3)
    verifyUtf8ToCodepoint(cBytes(#"\xEF\xBF\xBF"#), 0xFFFF, 3)
    verifyUtf8ToCodepoint(cBytes(#"\xF0\x90\x80\x80"#), 0x10000, 4)
    verifyUtf8ToCodepoint(cBytes(#"\xF7\xBF\xBF\xBF"#), 0x1FFFFF, 4)
    // do not test 5-6 bytes because it's out of spec of UTF8.

    var mblen = 0
    #expect(Util.utf8ToCodepoint("あい", &mblen) == 0x3042)
    #expect(mblen == 3)
  }

  @Test func codepointToUtf8() {
    // Do nothing if |c| is NUL. Previous implementation of CodepointToUtf8
    // worked like this even though the reason is unclear.
    #expect(Util.codepointToUtf8(0).isEmpty)

    #expect(Util.codepointToUtf8(0x7F) == "\u{7F}")
    #expect(Util.codepointToUtf8(0x80) == "\u{80}")
    #expect(Util.codepointToUtf8(0x7FF) == "\u{7FF}")
    #expect(Util.codepointToUtf8(0x800) == "\u{800}")
    #expect(Util.codepointToUtf8(0xFFFF) == "\u{FFFF}")
    #expect(Util.codepointToUtf8(0x10000) == "\u{10000}")

    // Buffer version.
    #expect(Util.codepointToUtf8Bytes(0) == [])
    #expect(Util.codepointToUtf8Bytes(0x7F) == cBytes(#"\x7F"#))
    #expect(Util.codepointToUtf8Bytes(0x80) == cBytes(#"\xC2\x80"#))
    #expect(Util.codepointToUtf8Bytes(0x7FF) == cBytes(#"\xDF\xBF"#))
    #expect(Util.codepointToUtf8Bytes(0x800) == cBytes(#"\xE0\xA0\x80"#))
    #expect(Util.codepointToUtf8Bytes(0xFFFF) == cBytes(#"\xEF\xBF\xBF"#))
    #expect(Util.codepointToUtf8Bytes(0x10000) == cBytes(#"\xF0\x90\x80\x80"#))
    #expect(Util.codepointToUtf8Bytes(0x1FFFFF) == cBytes(#"\xF7\xBF\xBF\xBF"#))
  }

  @Test func charsLen() {
    #expect(Util.charsLen("私の名前は中野です") == 9)
  }

  @Test func charsLenInvalid() {
    let kText = Array("あいうえお".utf8)
    #expect(Util.charsLen(kText.prefix(1)) == 1)
    #expect(Util.charsLen(kText.prefix(4)) == 2)
  }

  @Test func prefixCharsLen() {
    // 9 bytes: 3 + 3 + 3
    #expect(Util.prefixCharsLen("東京駅") == [0, 0, 0, 1, 1, 1, 2, 2, 2, 3])
    #expect(Util.prefixCharsLen("a亜b") == [0, 1, 1, 1, 2, 3])
    #expect(Util.prefixCharsLen("") == [0])
  }

  @Test func utf8SubString() {
    let src = "私の名前は中野です"
    #expect(Util.utf8SubString(src, 0, 2) == "私の")
    #expect(Util.utf8SubString(src, 4, 1) == "は")
    #expect(Util.utf8SubString(src, 5, 3) == "中野で")
    #expect(Util.utf8SubString(src, 6, 10) == "野です")
    #expect(Util.utf8SubString(src, 4, 2) == "は中")
    #expect(Util.utf8SubString(src, 2, Int.max) == "名前は中野です")
    #expect(Util.utf8SubString(src, 5, Int.max) == "中野です")
    // |result| should point to the same storage as src.
    let r = Util.utf8SubString(src, 5, 3)
    #expect(r.base == src)
    #expect(src.byteOffset(of: r.startIndex) == 15)
  }

  @Test func utf8SubString2() {
    let src = "私はGoogleです"
    #expect(Util.utf8SubString(src, 0) == src[...])
    #expect(Util.utf8SubString(src, 5) == "gleです")
    #expect(Util.utf8SubString(src, 10).isEmpty)
    #expect(Util.utf8SubString(src, 13).isEmpty)
  }

  @Test func utf8SubString3() {
    let src = "私の名前は中野です"
    var result = ""
    Util.utf8SubString(src, 0, 2, &result)
    #expect(result == "私の")
    Util.utf8SubString(src, 4, 1, &result)
    #expect(result == "は")
    Util.utf8SubString(src, 5, 3, &result)
    #expect(result == "中野で")
    Util.utf8SubString(src, 6, 10, &result)
    #expect(result == "野です")
    Util.utf8SubString(src, 4, 2, &result)
    #expect(result == "は中")
    Util.utf8SubString(src, 2, Int.max, &result)
    #expect(result == "名前は中野です")
    Util.utf8SubString(src, 5, Int.max, &result)
    #expect(result == "中野です")
    // Doesn't clear result and call Util::Utf8SubString
    Util.utf8SubString(src, 5, Int.max, &result)
    #expect(result == "中野です")
  }

  @Test func stripUtf8Bom() {
    // Should be stripped.
    #expect(Array(Util.stripUtf8Bom(cBytes(#"\xef\xbb\xbfabc"#))) == Array("abc".utf8))
    #expect(Util.stripUtf8Bom("\u{FEFF}abc") == "abc")

    // Should be stripped.
    #expect(Util.stripUtf8Bom(cBytes(#"\xef\xbb\xbf"#)).isEmpty)
    #expect(Util.stripUtf8Bom("\u{FEFF}") == "")

    // BOM in the middle of text. Shouldn't be stripped.
    #expect(Array(Util.stripUtf8Bom(cBytes(#"a\xef\xbb\xbfbc"#))) == cBytes(#"a\xef\xbb\xbfbc"#))
    #expect(Util.stripUtf8Bom("a\u{FEFF}bc") == "a\u{FEFF}bc")

    // Incomplete BOM. Shouldn't be stripped.
    #expect(Array(Util.stripUtf8Bom(cBytes(#"\xef\xbbabc"#))) == cBytes(#"\xef\xbbabc"#))

    // String shorter than the BOM. Do nothing.
    #expect(Util.stripUtf8Bom("a") == "a")

    // Empty string. Do nothing.
    #expect(Util.stripUtf8Bom("") == "")
  }

  @Test func isUtf16Bom() {
    #expect(!Util.isUtf16Bom(""))
    #expect(!Util.isUtf16Bom("abc"))
    #expect(Util.isUtf16Bom(cBytes(#"\xfe\xff"#)))
    #expect(Util.isUtf16Bom(cBytes(#"\xff\xfe"#)))
    #expect(Util.isUtf16Bom(cBytes(#"\xfe\xff "#)))
    #expect(Util.isUtf16Bom(cBytes(#"\xff\xfe "#)))
    #expect(!Util.isUtf16Bom(cBytes(#" \xfe\xff"#)))
    #expect(!Util.isUtf16Bom(cBytes(#" \xff\xfe"#)))
    #expect(!Util.isUtf16Bom(cBytes(#"\xff\xff"#)))
  }

  @Test func bracketTest() {
    let kBracketType: [(String, String)] = [
      ("（", "）"),
      ("〔", "〕"),
      ("［", "］"),
      ("｛", "｝"),
      ("〈", "〉"),
      ("《", "》"),
      ("「", "」"),
      ("『", "』"),
      ("【", "】"),
      ("〘", "〙"),
      ("〚", "〛"),
      ("«", "»"),
      ("‘", "’"),
      ("“", "”"),
      ("‹", "›"),
      ("〝", "〟"),
    ]

    for bracket in kBracketType {
      #expect(Util.isOpenBracket(bracket.0) == Substring(bracket.1))
      #expect(Util.isCloseBracket(bracket.1) == Substring(bracket.0))
      #expect(Util.isOpenBracket(bracket.1) == nil)
      #expect(Util.isCloseBracket(bracket.0) == nil)
    }
  }

  @Test func isBracketPairText() {
    #expect(Util.isBracketPairText("\"\""))
    #expect(Util.isBracketPairText("''"))
    #expect(Util.isBracketPairText("<>"))
    #expect(Util.isBracketPairText("``"))
    #expect(Util.isBracketPairText("«»"))
    #expect(Util.isBracketPairText("()"))
    #expect(Util.isBracketPairText("[]"))
    #expect(Util.isBracketPairText("{}"))
    #expect(Util.isBracketPairText("‘’"))
    #expect(Util.isBracketPairText("“”"))
    #expect(Util.isBracketPairText("‹›"))
    #expect(Util.isBracketPairText("〈〉"))
    #expect(Util.isBracketPairText("《》"))
    #expect(Util.isBracketPairText("「」"))
    #expect(Util.isBracketPairText("『』"))
    #expect(Util.isBracketPairText("【】"))
    #expect(Util.isBracketPairText("〔〕"))
    #expect(Util.isBracketPairText("〘〙"))
    #expect(Util.isBracketPairText("〚〛"))
    #expect(Util.isBracketPairText("（）"))
    #expect(Util.isBracketPairText("［］"))
    #expect(Util.isBracketPairText("｛｝"))
    #expect(Util.isBracketPairText("｢｣"))
    #expect(Util.isBracketPairText("〝〟"))

    // Open bracket and close brakcet don't match.
    #expect(!Util.isBracketPairText("(]"))

    // More than two characters.
    #expect(!Util.isBracketPairText("{{}}"))

    // Non bracket character exists.
    #expect(!Util.isBracketPairText("1)"))
  }

  @Test func isEnglishTransliteration() {
    #expect(Util.isEnglishTransliteration("ABC"))
    #expect(Util.isEnglishTransliteration("Google"))
    #expect(Util.isEnglishTransliteration("Google Map"))
    #expect(Util.isEnglishTransliteration("ABC-DEF"))
    #expect(Util.isEnglishTransliteration("Foo-bar"))
    #expect(Util.isEnglishTransliteration("Foo!"))
    #expect(Util.isEnglishTransliteration("Who's"))
    #expect(Util.isEnglishTransliteration("!"))
    #expect(Util.isEnglishTransliteration("  "))
    #expect(!Util.isEnglishTransliteration("てすと"))
    #expect(!Util.isEnglishTransliteration("テスト"))
    #expect(!Util.isEnglishTransliteration("東京"))
  }

  @Test func chopReturns() {
    var line = "line\n"
    #expect(Util.chopReturns(&line))
    #expect(line == "line")

    line = "line\r"
    #expect(Util.chopReturns(&line))
    #expect(line == "line")

    line = "line\r\n"
    #expect(Util.chopReturns(&line))
    #expect(line == "line")

    line = "line"
    #expect(!Util.chopReturns(&line))
    #expect(line == "line")

    line = "line1\nline2\n"
    #expect(Util.chopReturns(&line))
    #expect(line == "line1\nline2")

    line = "line\n\n\n"
    #expect(Util.chopReturns(&line))
    #expect(line == "line")
  }

  @Test func scriptType() {
    #expect(Util.isScriptType("くどう", .hiragana))
    #expect(Util.isScriptType("京都", .kanji))
    // (b/4201140)
    #expect(Util.isScriptType("人々", .kanji))
    #expect(Util.isScriptType("モズク", .katakana))
    #expect(Util.isScriptType("モズクﾓｽﾞｸ", .katakana))
    #expect(Util.isScriptType("ぐーぐる", .hiragana))
    #expect(Util.isScriptType("グーグル", .katakana))
    // U+309F: HIRAGANA DIGRAPH YORI
    #expect(Util.isScriptType("ゟ", .hiragana))
    // U+30FF: KATAKANA DIGRAPH KOTO
    #expect(Util.isScriptType("ヿ", .katakana))
    #expect(Util.isScriptType("ヷヸヹヺㇰㇱㇲㇳㇴㇵㇶㇷㇸㇹㇺㇻㇼㇽㇾㇿ", .katakana))
    // "𛀀" U+1B000: KATAKANA LETTER ARCHAIC E
    #expect(Util.isScriptType("\u{1B000}", .katakana))
    // "𛀁" U+1B001: HIRAGANA LETTER ARCHAIC YE
    #expect(Util.isScriptType("\u{1B001}", .hiragana))

    #expect(Util.isScriptType("012", .number))
    #expect(Util.isScriptType("０１２012", .number))
    #expect(Util.isScriptType("abcABC", .alphabet))
    #expect(Util.isScriptType("ＡＢＣＤ", .alphabet))
    #expect(Util.isScriptType("@!#", .unknownScript))

    #expect(!Util.isScriptType("くどカう", .hiragana))
    #expect(!Util.isScriptType("京あ都", .kanji))
    #expect(!Util.isScriptType("モズあク", .katakana))
    #expect(!Util.isScriptType("モあズクﾓｽﾞｸ", .katakana))
    #expect(!Util.isScriptType("012あ", .number))
    #expect(!Util.isScriptType("０１２あ012", .number))
    #expect(!Util.isScriptType("abcABあC", .alphabet))
    #expect(!Util.isScriptType("ＡＢあＣＤ", .alphabet))
    #expect(!Util.isScriptType("ぐーぐるグ", .hiragana))
    #expect(!Util.isScriptType("グーグルぐ", .katakana))

    #expect(Util.containsScriptType("グーグルsuggest", .alphabet))
    #expect(!Util.containsScriptType("グーグルサジェスト", .alphabet))

    #expect(Util.getScriptType("くどう") == .hiragana)
    #expect(Util.getScriptType("京都") == .kanji)
    // b/4201140
    #expect(Util.getScriptType("人々") == .kanji)
    #expect(Util.getScriptType("モズク") == .katakana)
    #expect(Util.getScriptType("モズクﾓｽﾞｸ") == .katakana)
    #expect(Util.getScriptType("ぐーぐる") == .hiragana)
    #expect(Util.getFirstScriptType("ぐーぐる") == .hiragana)

    #expect(Util.getScriptType("グーグル") == .katakana)
    #expect(Util.getFirstScriptType("グーグル") == .katakana)
    // U+309F HIRAGANA DIGRAPH YORI
    #expect(Util.getScriptType("ゟ") == .hiragana)
    #expect(Util.getFirstScriptType("ゟ") == .hiragana)

    // U+30FF KATAKANA DIGRAPH KOTO
    #expect(Util.getScriptType("ヿ") == .katakana)
    #expect(Util.getScriptType("ヷヸヹヺㇰㇱㇲㇳㇴㇵㇶㇷㇸㇹㇺㇻㇼㇽㇾㇿ") == .katakana)
    // "𛀀" U+1B000 KATAKANA LETTER ARCHAIC E
    #expect(Util.getScriptType("\u{1B000}") == .katakana)
    // "𛀁" U+1B001 HIRAGANA LETTER ARCHAIC YE
    #expect(Util.getScriptType("\u{1B001}") == .hiragana)

    #expect(Util.getScriptType("!グーグル") == .unknownScript)
    #expect(Util.getScriptType("ー") == .unknownScript)  // U+30FC
    #expect(Util.getFirstScriptType("ー") == .katakana)  // U+30FC
    #expect(Util.getScriptType("ーー") == .unknownScript)  // U+30FC * 2
    #expect(Util.getFirstScriptType("ーー") == .katakana)  // U+30FC * 2
    #expect(Util.getScriptType("゛") == .unknownScript)
    #expect(Util.getScriptType("゜") == .unknownScript)

    #expect(Util.getScriptType("012") == .number)
    #expect(Util.getScriptType("０１２012") == .number)
    #expect(Util.getScriptType("abcABC") == .alphabet)
    #expect(Util.getScriptType("ＡＢＣＤ") == .alphabet)
    #expect(Util.getScriptType("@!#") == .unknownScript)
    #expect(Util.getScriptType("＠！＃") == .unknownScript)

    #expect(Util.getScriptType("ーひらがな") == .hiragana)
    #expect(Util.getFirstScriptType("ーひらがな") == .katakana)
    #expect(Util.getScriptType("ーカタカナ") == .katakana)
    #expect(Util.getScriptType("ｰｶﾀｶﾅ") == .katakana)
    #expect(Util.getScriptType("ひらがなー") == .hiragana)
    #expect(Util.getScriptType("カタカナー") == .katakana)
    #expect(Util.getScriptType("ｶﾀｶﾅｰ") == .katakana)

    #expect(Util.getScriptType("あ゛っ") == .hiragana)
    #expect(Util.getScriptType("あ゜っ") == .hiragana)
    #expect(Util.getScriptType("ア゛ッ") == .katakana)
    #expect(Util.getScriptType("ア゜ッ") == .katakana)

    #expect(Util.getScriptType("くどカう") == .unknownScript)
    #expect(Util.getScriptType("京あ都") == .unknownScript)
    #expect(Util.getFirstScriptType("京あ都") == .kanji)

    #expect(Util.getScriptType("モズあク") == .unknownScript)
    #expect(Util.getFirstScriptType("モズあク") == .katakana)

    // Numbers with period
    #expect(Util.getScriptType("25.4") == .number)
    #expect(Util.getScriptType(".") == .unknownScript)
    #expect(Util.getScriptType(".123") == .unknownScript)
    // The following are limitations of the current implementation.
    // It's nice to be treated as UNKNOWN_SCRIPT.
    #expect(Util.getScriptType("1..9") == .number)
    #expect(Util.getScriptType("42.") == .number)

    #expect(Util.getScriptType("モあズクﾓｽﾞｸ") == .unknownScript)
    #expect(Util.getScriptType("012あ") == .unknownScript)
    #expect(Util.getFirstScriptType("012あ") == .number)
    #expect(Util.getScriptType("０１２あ012") == .unknownScript)
    #expect(Util.getFirstScriptType("０１２あ012") == .number)
    #expect(Util.getScriptType("abcABあC") == .unknownScript)
    #expect(Util.getScriptType("ＡＢあＣＤ") == .unknownScript)
    #expect(Util.getScriptType("ぐーぐるグ") == .unknownScript)
    #expect(Util.getScriptType("グーグルぐ") == .unknownScript)
    #expect(Util.getScriptType("@012") == .unknownScript)
    // ・ (U+30FB, KATAKANA MIDDLE DOT) + numbers
    #expect(Util.getScriptType("・012") == .unknownScript)
    // ー (U+30FC, KATAKANA-HIRAGANA PROLONGED SOUND MARK) + numbers
    #expect(Util.getScriptType("ー012") == .unknownScript)

    // "龦" U+9FA6
    #expect(Util.getScriptType("\u{9FA6}") == .kanji)
    // "龻" U+9FBB
    #expect(Util.getScriptType("\u{9FBB}") == .kanji)
    // U+9FFF is not assigned yet but reserved for CJK Unified Ideographs.
    #expect(Util.getScriptType("\u{9FFF}") == .kanji)
    // "𠮟咤" U+20B9F U+54A4
    #expect(Util.getScriptType("\u{20B9F}\u{54A4}") == .kanji)
    // "𠮷野" U+20BB7 U+91CE
    #expect(Util.getScriptType("\u{20BB7}\u{91CE}") == .kanji)
    // "巽" U+2F884
    #expect(Util.getScriptType("\u{2F884}") == .kanji)

    // U+1F466, BOY/smile emoji
    #expect(Util.getScriptType("\u{1F466}") == .emoji)
    // U+FE003, Snow-man Android PUA emoji
    // Historically, Android PUA Emoji was treated as EMOJI. However, because
    // Mozc does not support Android PUA Emoji, GetScriptType for Android PUA
    // Emoji just returns UNKNOWN_SCRIPT now.
    #expect(Util.getScriptType("\u{FE003}") == .unknownScript)

    var mblen = -1
    #expect(Util.getFirstScriptType("", &mblen) == .unknownScript)
    #expect(mblen == 0)
    #expect(Util.getFirstScriptType("あa", &mblen) == .hiragana)
    #expect(mblen == 3)
  }

  @Test func scriptTypeWithoutSymbols() {
    #expect(Util.getScriptTypeWithoutSymbols("くど う") == .hiragana)
    #expect(Util.getScriptTypeWithoutSymbols("京 都") == .kanji)
    #expect(Util.getScriptTypeWithoutSymbols("モズク") == .katakana)
    #expect(Util.getScriptTypeWithoutSymbols("モズ クﾓｽﾞｸ") == .katakana)
    #expect(Util.getScriptTypeWithoutSymbols("Google Earth") == .alphabet)
    #expect(Util.getScriptTypeWithoutSymbols("Google ") == .alphabet)
    #expect(Util.getScriptTypeWithoutSymbols(" Google") == .alphabet)
    #expect(Util.getScriptTypeWithoutSymbols(" Google ") == .alphabet)
    #expect(Util.getScriptTypeWithoutSymbols("     g") == .alphabet)
    #expect(Util.getScriptTypeWithoutSymbols("") == .unknownScript)
    #expect(Util.getScriptTypeWithoutSymbols(" ") == .unknownScript)
    #expect(Util.getScriptTypeWithoutSymbols("   ") == .unknownScript)
    #expect(Util.getScriptTypeWithoutSymbols("Hello!") == .alphabet)
    #expect(Util.getScriptTypeWithoutSymbols("Hello!あ") == .unknownScript)
    #expect(Util.getScriptTypeWithoutSymbols("CD-ROM") == .alphabet)
    #expect(Util.getScriptTypeWithoutSymbols("CD-ROMア") == .unknownScript)
    #expect(Util.getScriptTypeWithoutSymbols("-") == .unknownScript)
    #expect(Util.getScriptTypeWithoutSymbols("-A") == .alphabet)
    #expect(Util.getScriptTypeWithoutSymbols("--A") == .alphabet)
    #expect(Util.getScriptTypeWithoutSymbols("--A---") == .alphabet)
    #expect(Util.getScriptTypeWithoutSymbols("--A-ｱ-") == .unknownScript)
    #expect(Util.getScriptTypeWithoutSymbols("!") == .unknownScript)
    #expect(Util.getScriptTypeWithoutSymbols("・あ") == .hiragana)
    #expect(Util.getScriptTypeWithoutSymbols("・・あ") == .hiragana)
    #expect(Util.getScriptTypeWithoutSymbols("コギト・エルゴ・スム") == .katakana)
    #expect(Util.getScriptTypeWithoutSymbols("コギト・エルゴ・住む") == .unknownScript)
    #expect(Util.getScriptTypeWithoutSymbols("人☆名") == .kanji)
    #expect(Util.getScriptTypeWithoutSymbols("ひとの☆なまえ") == .hiragana)
    #expect(Util.getScriptTypeWithoutSymbols("超☆最高です") == .unknownScript)
    #expect(Util.getScriptTypeWithoutSymbols("・--☆") == .unknownScript)
  }

  @Test func formType() {
    #expect(Util.getFormType("くどう") == .fullWidth)
    #expect(Util.getFormType("京都") == .fullWidth)
    #expect(Util.getFormType("モズク") == .fullWidth)
    #expect(Util.getFormType("ﾓｽﾞｸ") == .halfWidth)
    #expect(Util.getFormType("ぐーぐる") == .fullWidth)
    #expect(Util.getFormType("グーグル") == .fullWidth)
    #expect(Util.getFormType("ｸﾞｰｸﾞﾙ") == .halfWidth)
    #expect(Util.getFormType("ｰ") == .halfWidth)
    #expect(Util.getFormType("ー") == .fullWidth)
    #expect(Util.getFormType("¢£¥¦¬¯") == .halfWidth)
    // "￨￩￪￫￬￭￮"
    #expect(Util.getFormType("\u{FFE8}\u{FFE9}\u{FFEA}\u{FFEB}\u{FFEC}\u{FFED}\u{FFEE}") == .halfWidth)

    // Half-width mathematical symbols
    // [U+27E6, U+27ED], U+2985, and U+2986
    #expect(Util.getFormType("⟦⟧⟨⟩⟪⟫⟬⟭⦅⦆") == .halfWidth)

    // Half-width hangul "ﾠﾡﾢ"
    #expect(Util.getFormType("\u{FFA0}\u{FFA1}\u{FFA2}") == .halfWidth)

    // Half-width won "₩"
    #expect(Util.getFormType("₩") == .halfWidth)

    #expect(Util.getFormType("012") == .halfWidth)
    #expect(Util.getFormType("０１２012") == .unknownForm)
    #expect(Util.getFormType("abcABC") == .halfWidth)
    #expect(Util.getFormType("ＡＢＣＤ") == .fullWidth)
    #expect(Util.getFormType("@!#") == .halfWidth)
  }

  @Test func isAscii() {
    #expect(!Util.isAscii("あいうえお"))
    #expect(Util.isAscii("abc"))
    #expect(!Util.isAscii("abcあいう"))
    #expect(Util.isAscii(""))
    #expect(Util.isAscii("\u{7F}"))
    #expect(!Util.isAscii(cBytes(#"\x80"#)))
  }

  @Test func isKanaSymbolContained() {
    let kFullstop = "。"
    let kSpace = " "
    #expect(Util.isKanaSymbolContained(kFullstop))
    #expect(Util.isKanaSymbolContained(kSpace + kFullstop))
    #expect(Util.isKanaSymbolContained(kFullstop + kSpace))
    #expect(!Util.isKanaSymbolContained(kSpace))
    #expect(!Util.isKanaSymbolContained(""))
  }

  private func checkSplitFirst(_ s: String, _ c: Char32, _ rest: String) {
    let r = Util.splitFirstChar32(cBytes(s))
    #expect(r != nil)
    #expect(r?.0 == c)
    #expect(r.map { Array($0.1) } == cBytes(rest))
  }

  @Test func splitFirstChar32() {
    #expect(Util.splitFirstChar32([UInt8]()) == nil)
    #expect(Util.splitFirstChar32("") == nil)

    #expect(Util.splitFirstChar32("01")?.1 == "1")
    #expect(Util.splitFirstChar32("01")?.0 == 0x30)

    checkSplitFirst(#"\x01 "#, 1, " ")
    checkSplitFirst(#"\x7F "#, 0x7F, " ")
    checkSplitFirst(#"\xC2\x80 "#, 0x80, " ")
    checkSplitFirst(#"\xDF\xBF "#, 0x7FF, " ")
    checkSplitFirst(#"\xE0\xA0\x80 "#, 0x800, " ")
    checkSplitFirst(#"\xEF\xBF\xBF "#, 0xFFFF, " ")
    checkSplitFirst(#"\xF0\x90\x80\x80 "#, 0x10000, " ")
    checkSplitFirst(#"\xF7\xBF\xBF\xBF "#, 0x1FFFFF, " ")
    checkSplitFirst(#"\xF8\x88\x80\x80\x80 "#, 0x200000, " ")
    checkSplitFirst(#"\xFB\xBF\xBF\xBF\xBF "#, 0x3FFFFFF, " ")
    checkSplitFirst(#"\xFC\x84\x80\x80\x80\x80 "#, 0x4000000, " ")
    checkSplitFirst(#"\xFD\xBF\xBF\xBF\xBF\xBF "#, 0x7FFFFFFF, " ")

    // If there is any invalid sequence, the entire text should be treated as
    // am empty string.
    for s in [
      #"\xC2 "#, #"\xC2\xC2 "#, #"\xE0 "#, #"\xE0\xE0\xE0 "#, #"\xF0 "#, #"\xF0\xF0\xF0\xF0 "#,
    ] {
      #expect(Util.splitFirstChar32(cBytes(s)) == nil)
    }

    // BOM should be treated as invalid byte.
    #expect(Util.splitFirstChar32(cBytes(#"\xFF "#)) == nil)
    #expect(Util.splitFirstChar32(cBytes(#"\xFE "#)) == nil)

    // Invalid sequence for U+002F (redundant encoding)
    #expect(Util.splitFirstChar32(cBytes(#"\xC0\xAF"#)) == nil)
    #expect(Util.splitFirstChar32(cBytes(#"\xE0\x80\xAF"#)) == nil)
    #expect(Util.splitFirstChar32(cBytes(#"\xF0\x80\x80\xAF"#)) == nil)
  }

  private func checkSplitLast(_ s: String, _ c: Char32, _ rest: String) {
    let r = Util.splitLastChar32(cBytes(s))
    #expect(r != nil)
    #expect(r?.1 == c)
    #expect(r.map { Array($0.0) } == cBytes(rest))
  }

  @Test func splitLastChar32() {
    #expect(Util.splitLastChar32([UInt8]()) == nil)
    #expect(Util.splitLastChar32("") == nil)

    #expect(Util.splitLastChar32("01")?.1 == 0x31)
    #expect(Util.splitLastChar32("01")?.0 == "0")

    checkSplitLast(#" \x01"#, 1, " ")
    checkSplitLast(#" \x7F"#, 0x7F, " ")
    checkSplitLast(#" \xC2\x80"#, 0x80, " ")
    checkSplitLast(#" \xDF\xBF"#, 0x7FF, " ")
    checkSplitLast(#" \xE0\xA0\x80"#, 0x800, " ")
    checkSplitLast(#" \xEF\xBF\xBF"#, 0xFFFF, " ")
    checkSplitLast(#" \xF0\x90\x80\x80"#, 0x10000, " ")
    checkSplitLast(#" \xF7\xBF\xBF\xBF"#, 0x1FFFFF, " ")
    checkSplitLast(#" \xF8\x88\x80\x80\x80"#, 0x200000, " ")
    checkSplitLast(#" \xFB\xBF\xBF\xBF\xBF"#, 0x3FFFFFF, " ")
    checkSplitLast(#" \xFC\x84\x80\x80\x80\x80"#, 0x4000000, " ")
    checkSplitLast(#" \xFD\xBF\xBF\xBF\xBF\xBF"#, 0x7FFFFFFF, " ")

    // If there is any invalid sequence, the entire text should be treated as
    // am empty string.
    for s in [
      #" \xC2"#, #" \xC2\xC2"#, #" \xE0"#, #" \xE0\xE0\xE0"#, #" \xF0"#, #" \xF0\xF0\xF0\xF0"#,
    ] {
      #expect(Util.splitLastChar32(cBytes(s)) == nil)
    }

    // BOM should be treated as invalid byte.
    #expect(Util.splitLastChar32(cBytes(#" \xFF"#)) == nil)
    #expect(Util.splitLastChar32(cBytes(#" \xFE"#)) == nil)

    // Invalid sequence for U+002F (redundant encoding)
    #expect(Util.splitLastChar32(cBytes(#"\xC0\xAF"#)) == nil)
    #expect(Util.splitLastChar32(cBytes(#"\xE0\x80\xAF"#)) == nil)
    #expect(Util.splitLastChar32(cBytes(#"\xF0\x80\x80\xAF"#)) == nil)
  }

  @Test func isValidUtf8() {
    #expect(Util.isValidUtf8(""))
    #expect(Util.isValidUtf8("abc"))
    #expect(Util.isValidUtf8("あいう"))
    #expect(Util.isValidUtf8("aあbいcう"))

    #expect(!Util.isValidUtf8(cBytes(#"\xC2 "#)))
    #expect(!Util.isValidUtf8(cBytes(#"\xC2\xC2 "#)))
    #expect(!Util.isValidUtf8(cBytes(#"\xE0 "#)))
    #expect(!Util.isValidUtf8(cBytes(#"\xE0\xE0\xE0 "#)))
    #expect(!Util.isValidUtf8(cBytes(#"\xF0 "#)))
    #expect(!Util.isValidUtf8(cBytes(#"\xF0\xF0\xF0\xF0 "#)))

    // BOM should be treated as invalid byte.
    #expect(!Util.isValidUtf8(cBytes(#"\xFF "#)))
    #expect(!Util.isValidUtf8(cBytes(#"\xFE "#)))

    // Redundant encoding with U+002F is invalid.
    #expect(!Util.isValidUtf8(cBytes(#"\xC0\xAF"#)))
    #expect(!Util.isValidUtf8(cBytes(#"\xE0\x80\xAF"#)))
    #expect(!Util.isValidUtf8(cBytes(#"\xF0\x80\x80\xAF"#)))
  }

  @Test func isAcceptableCharacterAsCandidate() {
    // Control Characters
    #expect(!Util.isAcceptableCharacterAsCandidate(0x0A))
    #expect(!Util.isAcceptableCharacterAsCandidate(0x09))
    #expect(!Util.isAcceptableCharacterAsCandidate(0x0D))

    // Bidirectional text controls
    // See: https://en.wikipedia.org/wiki/Bidirectional_text
    #expect(!Util.isAcceptableCharacterAsCandidate(0x200E))  // LRM
    #expect(!Util.isAcceptableCharacterAsCandidate(0x200F))  // RLM
    #expect(!Util.isAcceptableCharacterAsCandidate(0x2069))  // PDI
    #expect(!Util.isAcceptableCharacterAsCandidate(0x061C))  // ALM

    // For normal letters, it should be false
    #expect(Util.isAcceptableCharacterAsCandidate(0x3042))  // あ
    #expect(Util.isAcceptableCharacterAsCandidate(0x2198))  // ↘
    #expect(Util.isAcceptableCharacterAsCandidate(0x6C38))  // 永
    #expect(Util.isAcceptableCharacterAsCandidate(0x22BF))  // ⊿
    #expect(Util.isAcceptableCharacterAsCandidate(0x61))  // a
    #expect(Util.isAcceptableCharacterAsCandidate(0x1B001))  // hentaigana ye
    #expect(Util.isAcceptableCharacterAsCandidate(0x1F600))  // emoji
  }

  @Test func serializeAndDeserializeUint64() {
    let kCorrectPairs: [(String, UInt64)] = [
      (#"\x00\x00\x00\x00\x00\x00\x00\x00"#, 0),
      (#"\x00\x00\x00\x00\x00\x00\x00\xFF"#, UInt64(UInt8.max)),
      (#"\x00\x00\x00\x00\x00\x00\xFF\xFF"#, UInt64(UInt16.max)),
      (#"\x00\x00\x00\x00\xFF\xFF\xFF\xFF"#, UInt64(UInt32.max)),
      (#"\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF"#, UInt64.max),
      (#"\x01\x23\x45\x67\x89\xAB\xCD\xEF"#, 0x0123456789ABCDEF),
      (#"\xFE\xDC\xBA\x98\x76\x54\x32\x10"#, 0xFEDCBA9876543210),
    ]

    for (str, value) in kCorrectPairs {
      let serialized = cBytes(str)
      #expect(Util.serializeUint64(value) == serialized)
      #expect(Util.deserializeUint64(serialized) == value)
    }

    // Invalid patterns for DeserializeUint64.
    for s in ["", "abc", "helloworld"] {
      #expect(Util.deserializeUint64(Array(s.utf8)) == nil)
    }
  }

  @Test func constChar32Iterator() {
    var iter = ConstChar32Iterator("aあ𠮷")
    var result: [Char32] = []
    while !iter.done {
      result.append(iter.get())
      iter.advance()
    }
    #expect(result == [0x61, 0x3042, 0x20BB7])
    #expect(Array(ConstChar32Iterator("aあ𠮷")) == [0x61, 0x3042, 0x20BB7])
    #expect(Array(ConstChar32ReverseIterator("aあ𠮷")) == [0x20BB7, 0x3042, 0x61])
    #expect(Array(ConstChar32Iterator("")) == [])
  }
}
