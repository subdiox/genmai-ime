// Port of mozc/src/base/number_util_test.cc (3.35.6354).

import Testing

@testable import GenmaiBase

@Suite struct NumberUtilTest {
  typealias Style = NumberUtil.NumberString.Style

  @Test func simpleAtoi() {
    #expect(NumberUtil.simpleAtoi("0") == 0)
    #expect(NumberUtil.simpleAtoi("123") == 123)
    #expect(NumberUtil.simpleAtoi("-1") == -1)

    // Invalid cases return 0.
    #expect(NumberUtil.simpleAtoi("abc") == 0)
    #expect(NumberUtil.simpleAtoi("a1") == 0)
    #expect(NumberUtil.simpleAtoi("1 a") == 0)
  }

  @Test func safeStrToInt16() {
    #expect(NumberUtil.safeStrToInt16("0") == 0)
    #expect(NumberUtil.safeStrToInt16("+0") == 0)
    #expect(NumberUtil.safeStrToInt16("-0") == 0)
    #expect(NumberUtil.safeStrToInt16(" \t\r\n\u{0B}\u{0C}0 \t\r\n\u{0B}\u{0C}") == 0)
    #expect(NumberUtil.safeStrToInt16(" \t\r\n\u{0B}\u{0C}-0 \t\r\n\u{0B}\u{0C}") == 0)
    #expect(NumberUtil.safeStrToInt16("012345") == 12345)
    #expect(NumberUtil.safeStrToInt16("-012345") == -12345)
    #expect(NumberUtil.safeStrToInt16("-32768") == Int16.min)
    #expect(NumberUtil.safeStrToInt16("32767") == Int16.max)
    #expect(NumberUtil.safeStrToInt16(" 1") == 1)
    #expect(NumberUtil.safeStrToInt16("2 ") == 2)

    #expect(NumberUtil.safeStrToInt16("0x1234") == nil)
    #expect(NumberUtil.safeStrToInt16("-32769") == nil)
    #expect(NumberUtil.safeStrToInt16("32768") == nil)
    #expect(NumberUtil.safeStrToInt16("18446744073709551616") == nil)
    #expect(NumberUtil.safeStrToInt16("3e") == nil)
    #expect(NumberUtil.safeStrToInt16("0.") == nil)
    #expect(NumberUtil.safeStrToInt16(".0") == nil)
    #expect(NumberUtil.safeStrToInt16("") == nil)

    // Test for substring input.
    let kString = "123 abc 789"
    #expect(NumberUtil.safeStrToInt16(kString.byteSubstring(from: 0, length: 3)) == 123)
    #expect(NumberUtil.safeStrToInt16(kString.byteSubstring(from: 4, length: 3)) == nil)
    #expect(NumberUtil.safeStrToInt16(kString.byteSubstring(from: 8, length: 3)) == 789)
    #expect(NumberUtil.safeStrToInt16(kString.byteSubstring(from: 7, length: 4)) == 789)
  }

  @Test func safeStrToUInt16() {
    #expect(NumberUtil.safeStrToUInt16("0") == 0)
    #expect(NumberUtil.safeStrToUInt16(" \t\r\n\u{0B}\u{0C}0 \t\r\n\u{0B}\u{0C}") == 0)
    #expect(NumberUtil.safeStrToUInt16("012345") == 12345)
    #expect(NumberUtil.safeStrToUInt16("65535") == 65535)  // max of 16-bit unsigned integer
    #expect(NumberUtil.safeStrToUInt16(" 1") == 1)
    #expect(NumberUtil.safeStrToUInt16("2 ") == 2)

    #expect(NumberUtil.safeStrToUInt16("-0") == nil)
    #expect(NumberUtil.safeStrToUInt16("0x1234") == nil)
    #expect(NumberUtil.safeStrToUInt16("65536") == nil)
    #expect(NumberUtil.safeStrToUInt16("18446744073709551616") == nil)
    #expect(NumberUtil.safeStrToUInt16("3e") == nil)
    #expect(NumberUtil.safeStrToUInt16("0.") == nil)
    #expect(NumberUtil.safeStrToUInt16(".0") == nil)
    #expect(NumberUtil.safeStrToUInt16("") == nil)

    // Test for substring input.
    let kString = "123 abc 789"
    #expect(NumberUtil.safeStrToUInt16(kString.byteSubstring(from: 0, length: 3)) == 123)
    #expect(NumberUtil.safeStrToUInt16(kString.byteSubstring(from: 4, length: 3)) == nil)
    #expect(NumberUtil.safeStrToUInt16(kString.byteSubstring(from: 8, length: 3)) == 789)
    #expect(NumberUtil.safeStrToUInt16(kString.byteSubstring(from: 7, length: 4)) == 789)
  }

  @Test func safeStrToDouble() {
    #expect(NumberUtil.safeStrToDouble("0") == 0.0)
    #expect(NumberUtil.safeStrToDouble(" \t\r\n\u{0B}\u{0C}0 \t\r\n\u{0B}\u{0C}") == 0.0)
    #expect(NumberUtil.safeStrToDouble("-0") == 0.0)
    #expect(NumberUtil.safeStrToDouble("1.0e1") == 10.0)
    #expect(NumberUtil.safeStrToDouble("-5.0e-1") == -0.5)
    #expect(NumberUtil.safeStrToDouble(".0") == 0.0)
    #expect(NumberUtil.safeStrToDouble("0.") == 0.0)
    #expect(NumberUtil.safeStrToDouble("0.0") == 0.0)
    // Approximate representation of max of double.
    #expect(NumberUtil.safeStrToDouble("1.7976931348623158e308") == 1.7976931348623158e308)
    #expect(NumberUtil.safeStrToDouble("-1.7976931348623158e308") == -1.7976931348623158e308)

    #expect(NumberUtil.safeStrToDouble("0x1234") == Double(0x1234))

    #expect(NumberUtil.safeStrToDouble("1.0e309") == nil)  // overflow
    #expect(NumberUtil.safeStrToDouble("-1.0e309") == nil)  // underflow
    #expect(NumberUtil.safeStrToDouble("NaN") == nil)
    #expect(NumberUtil.safeStrToDouble("3e") == nil)
    #expect(NumberUtil.safeStrToDouble(".") == nil)
    #expect(NumberUtil.safeStrToDouble("") == nil)

    // Test for substring input.
    let kString = "0.01 3.1415 double"
    #expect(NumberUtil.safeStrToDouble(kString.byteSubstring(from: 0, length: 4)) == 0.01)
    #expect(NumberUtil.safeStrToDouble(kString.byteSubstring(from: 5, length: 6)) == 3.1415)
    #expect(NumberUtil.safeStrToDouble(kString.byteSubstring(from: 12, length: 6)) == nil)
  }

  @Test func isArabicNumber() {
    #expect(!NumberUtil.isArabicNumber(""))
    for s in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] {
      #expect(NumberUtil.isArabicNumber(s))
    }
    for s in ["０", "１", "２", "３", "４", "５", "６", "７", "８", "９"] {
      #expect(NumberUtil.isArabicNumber(s))
    }
    #expect(NumberUtil.isArabicNumber("0123456789"))
    #expect(NumberUtil.isArabicNumber("01234567890123456789"))
    #expect(NumberUtil.isArabicNumber("１０"))

    #expect(!NumberUtil.isArabicNumber("abc"))
    #expect(!NumberUtil.isArabicNumber("十"))
    #expect(!NumberUtil.isArabicNumber("億"))
    #expect(!NumberUtil.isArabicNumber("グーグル"))
  }

  @Test func isDecimalInteger() {
    #expect(!NumberUtil.isDecimalInteger(""))
    for s in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] {
      #expect(NumberUtil.isDecimalInteger(s))
    }
    #expect(NumberUtil.isDecimalInteger("0123456789"))
    #expect(NumberUtil.isDecimalInteger("01234567890123456789"))
    for s in ["０", "１", "２", "３", "４", "５", "６", "７", "８", "９"] {
      #expect(!NumberUtil.isDecimalInteger(s))
    }
    #expect(!NumberUtil.isDecimalInteger("１０"))
    #expect(!NumberUtil.isDecimalInteger("十"))
    #expect(!NumberUtil.isDecimalInteger("億"))
    #expect(!NumberUtil.isDecimalInteger("abc"))
    #expect(!NumberUtil.isDecimalInteger("グーグル"))
  }

  @Test func kanjiNumberToArabicNumber() {
    let inputs = ["十", "百", "千", "万", "億", "兆", "京"]
    let expects = [
      "10", "100", "1000", "10000", "100000000", "1000000000000", "10000000000000000",
    ]
    for (input, expected) in zip(inputs, expects) {
      #expect(NumberUtil.kanjiNumberToArabicNumber(input) == expected)
    }
  }

  @Test func normalizeNumbers() {
    // An element has input, expected Kanji output, and expected Arabic output.
    let successData: [(String, String, String)] = [
      ("一", "一", "1"),
      ("九", "九", "9"),
      ("十", "十", "10"),
      ("十五", "十五", "15"),
      ("二十", "二十", "20"),
      ("三十五", "三十五", "35"),
      ("百", "百", "100"),
      ("二百", "二百", "200"),
      ("二百十", "二百十", "210"),
      ("二百五十", "二百五十", "250"),
      ("七百七十七", "七百七十七", "777"),
      ("千", "千", "1000"),
      ("一千", "一千", "1000"),
      ("八千", "八千", "8000"),
      ("八千七百三十九", "八千七百三十九", "8739"),
      ("一万二十五", "一万二十五", "10025"),
      // 2^64 - 1
      (
        "千八百四十四京六千七百四十四兆七百三十七億九百五十五万千六百十五",
        "千八百四十四京六千七百四十四兆七百三十七億九百五十五万千六百十五",
        "18446744073709551615"
      ),
      ("百億百", "百億百", "10000000100"),
      ("一千京", "一千京", "10000000000000000000"),

      // Old Kanji numbers
      ("零", "零", "0"),
      ("拾", "拾", "10"),
      ("拾四", "拾四", "14"),
      ("廿", "廿", "20"),
      ("廿万廿", "廿万廿", "200020"),
      ("弐拾参", "弐拾参", "23"),
      ("零弐拾参", "零弐拾参", "23"),

      // Array of Kanji number digits
      ("0", "〇", "0"),
      ("00", "〇〇", "0"),
      ("二三五", "二三五", "235"),
      ("０１２", "〇一二", "12"),
      ("二零一一", "二零一一", "2011"),

      // Combinations of several types
      ("二三五万四三", "二三五万四三", "2350043"),
      ("二百三五万一", "二百三五万一", "2350001"),
      ("2十5", "二十五", "25"),
      ("2千四十３", "二千四十三", "2043"),
      ("九０", "九〇", "90"),
    ]

    for (input, kanji, arabic) in successData {
      var arabicOutput = "dummy_text_arabic"
      var kanjiOutput = "dummy_text_kanji"
      #expect(NumberUtil.normalizeNumbers(input, true, &kanjiOutput, &arabicOutput))
      #expect(kanjiOutput.bytesEqual(kanji))
      #expect(arabicOutput == arabic)
    }

    // An element has input, expected Kanji output, and expected Arabic output.
    let successNotrimData: [(String, String, String)] = [
      ("０１２", "〇一二", "012"),
      ("０00", "〇〇〇", "000"),
      ("００１２", "〇〇一二", "0012"),
      ("０零０１２", "〇零〇一二", "00012"),
      ("0", "〇", "0"),
      ("00", "〇〇", "00"),
    ]

    for (input, kanji, arabic) in successNotrimData {
      var arabicOutput = "dummy_text_arabic"
      var kanjiOutput = "dummy_text_kanji"
      #expect(NumberUtil.normalizeNumbers(input, false, &kanjiOutput, &arabicOutput))
      #expect(kanjiOutput.bytesEqual(kanji))
      #expect(arabicOutput == arabic)
    }

    // Test data expected to fail
    let failData = [
      // 2^64
      "千八百四十四京六千七百四十四兆七百三十七億九百五十五万千六百十六",
      "てすと",
      "てすと２",
      "一十",
      "一百",
      "万二千三百四十五",  // lack of number before "万"
      "三億一京",  // large base, "京", after small one, "億"
      "三百四百",  // same base appears twice
      "五億六億",  // same base appears twice
      "二十三十",  // same base appears twice
      "二十百",  // relatively large base "百" after "十"
      "一二三四五六七八九十",
      "九九八十一",
    ]

    for input in failData {
      var arabicOutput = ""
      var kanjiOutput = ""
      #expect(!NumberUtil.normalizeNumbers(input, true, &kanjiOutput, &arabicOutput))
    }
  }

  @Test func normalizeNumbersWithSuffix() {
    do {
      // Checks that kanji_output and arabic_output is cleared.
      var arabicOutput = "dummy_text_arabic"
      var kanjiOutput = "dummy_text_kanji"
      var suffix = "dummy_text_suffix"
      #expect(
        NumberUtil.normalizeNumbersWithSuffix("一個", true, &kanjiOutput, &arabicOutput, &suffix))
      #expect(kanjiOutput == "一")
      #expect(arabicOutput == "1")
      #expect(suffix == "個")
    }

    func check(_ input: String, _ kanji: String, _ arabic: String, _ expectedSuffix: String) {
      var arabicOutput = ""
      var kanjiOutput = ""
      var suffix = ""
      #expect(
        NumberUtil.normalizeNumbersWithSuffix(input, true, &kanjiOutput, &arabicOutput, &suffix))
      #expect(kanjiOutput.bytesEqual(kanji))
      #expect(arabicOutput == arabic)
      #expect(suffix.bytesEqual(expectedSuffix))
    }

    func checkFail(_ input: String) {
      var arabicOutput = ""
      var kanjiOutput = ""
      var suffix = ""
      #expect(
        !NumberUtil.normalizeNumbersWithSuffix(input, true, &kanjiOutput, &arabicOutput, &suffix))
    }

    check("一万二十五個", "一万二十五", "10025", "個")
    check("二百三五万一番目", "二百三五万一", "2350001", "番目")
    checkFail("てすと")
    checkFail("てすと２")

    // Tests for numbers less than 10.
    check("零セット", "零", "0", "セット")
    check("九０ぷよ", "九〇", "90", "ぷよ")
    check("三五$", "三五", "35", "$")

    checkFail("二十三十に")  // same base appears twice
    checkFail("２，０００")  // separated number style
    checkFail("２時３０分")
  }

  @Test func arabicToWideArabicTest() {
    var output: [NumberUtil.NumberString] = []

    #expect(NumberUtil.arabicToWideArabic("12345", &output))
    #expect(output.count == 2)
    #expect(output[0].value == "一二三四五")
    #expect(output[0].style == .numberKanjiArabic)
    #expect(output[1].value == "１２３４５")
    #expect(output[1].style == .defaultStyle)

    output.removeAll()
    #expect(NumberUtil.arabicToWideArabic("00123", &output))
    #expect(output.count == 2)
    #expect(output[0].value == "〇〇一二三")
    #expect(output[0].style == .numberKanjiArabic)
    #expect(output[1].value == "００１２３")
    #expect(output[1].style == .defaultStyle)

    for arabic in ["abcde", "012abc345", "0.001", "-100"] {
      output.removeAll()
      #expect(!NumberUtil.arabicToWideArabic(arabic, &output))
      #expect(output.isEmpty)
    }

    output.removeAll()
    #expect(NumberUtil.arabicToWideArabic("18446744073709551616", &output))  // UINT_MAX + 1
    #expect(output.count == 2)
    #expect(output[0].value == "一八四四六七四四〇七三七〇九五五一六一六")
    #expect(output[1].value == "１８４４６７４４０７３７０９５５１６１６")
    #expect(output[0].style == .numberKanjiArabic)
    #expect(output[1].style == .defaultStyle)
  }

  @Test func arabicToKanjiTest() {
    let kOldKanji = Style.numberOldKanji
    let kKanji = Style.numberKanji
    let kHalfArabicKanji = Style.numberArabicAndKanjiHalfwidth
    let kFullArabicKanji = Style.numberArabicAndKanjiFullwidth

    let kData: [(String, [String], [Style])] = [
      ("0", ["零"], [kOldKanji]),
      ("00000", ["零"], [kOldKanji]),
      ("2", ["二", "弐"], [kKanji, kOldKanji]),
      // "壱拾" is needed to avoid mistakes. Please refer http://b/6422355
      // for details.
      ("10", ["十", "壱拾", "拾"], [kKanji, kOldKanji, kOldKanji]),
      ("100", ["百", "壱百"], [kKanji, kOldKanji]),
      ("1000", ["千", "壱阡", "阡"], [kKanji, kOldKanji, kOldKanji]),
      ("20", ["二十", "弐拾", "廿"], [kKanji, kOldKanji, kOldKanji]),
      (
        "11111", ["1万1111", "１万１１１１", "一万千百十一", "壱萬壱阡壱百壱拾壱"],
        [kHalfArabicKanji, kFullArabicKanji, kKanji, kOldKanji]
      ),
      (
        "12345", ["1万2345", "１万２３４５", "一万二千三百四十五", "壱萬弐阡参百四拾五"],
        [kHalfArabicKanji, kFullArabicKanji, kKanji, kOldKanji]
      ),
      (
        "100002345", ["1億2345", "１億２３４５", "一億二千三百四十五", "壱億弐阡参百四拾五"],
        [kHalfArabicKanji, kFullArabicKanji, kKanji, kOldKanji]
      ),
      (
        "18446744073709551615",
        [
          "1844京6744兆737億955万1615",
          "１８４４京６７４４兆７３７億９５５万１６１５",
          "千八百四十四京六千七百四十四兆七百三十七億九百五十五万千六百十五",
          "壱阡八百四拾四京六阡七百四拾四兆七百参拾七億九百五拾五萬壱阡六百壱拾" + "五",
        ],
        [kHalfArabicKanji, kFullArabicKanji, kKanji, kOldKanji]
      ),
    ]

    for (input, values, styles) in kData {
      var output: [NumberUtil.NumberString] = []
      #expect(NumberUtil.arabicToKanji(input, &output))
      #expect(output.count == values.count, "on conversion of '\(input)'")
      guard output.count == values.count else { continue }
      for j in 0..<values.count {
        #expect(output[j].value.bytesEqual(values[j]), "input : \(input)\nj : \(j)")
        #expect(output[j].style == styles[j], "input : \(input)\nj : \(j)")
      }
    }

    for input in ["asf56789", "0.001", "-100", "123456789012345678901"] {
      var output: [NumberUtil.NumberString] = []
      #expect(!NumberUtil.arabicToKanji(input, &output))
      #expect(output.isEmpty, "input : \(input)")
    }
  }

  @Test func arabicToSeparatedArabicTest() {
    var output: [NumberUtil.NumberString] = []

    // Test data expected to succeed
    let kSuccess: [(String, String, String)] = [
      ("4", "4", "４"),
      ("123456789", "123,456,789", "１２３，４５６，７８９"),
      ("1234567.89", "1,234,567.89", "１，２３４，５６７．８９"),
      // UINT64_MAX + 1
      ("18446744073709551616", "18,446,744,073,709,551,616", ""),
    ]

    for (arabic, half, full) in kSuccess {
      output.removeAll()
      #expect(NumberUtil.arabicToSeparatedArabic(arabic, &output))
      #expect(output.count == 2)
      guard output.count == 2 else { continue }
      #expect(output[0].value == half)
      #expect(output[0].style == .numberSeparatedArabicHalfwidth)
      if !full.isEmpty {
        #expect(output[1].value == full)
        #expect(output[1].style == .numberSeparatedArabicFullwidth)
      }
    }

    // Test data expected to fail
    for arabic in ["0123456789", "asdf0123456789", "0.001", "-100"] {
      output.removeAll()
      #expect(!NumberUtil.arabicToSeparatedArabic(arabic, &output))
      #expect(output.isEmpty)
    }
  }

  @Test func arabicToOtherFormsTest() {
    var output: [NumberUtil.NumberString] = []

    #expect(NumberUtil.arabicToOtherForms("5", &output))
    #expect(output.count == 5)
    #expect(output.map(\.value) == ["Ⅴ", "ⅴ", "⑤", "⁵", "₅"])
    #expect(
      output.map(\.style) == [
        .numberRomanCapital, .numberRomanSmall, .numberCircled, .numberSuperscript,
        .numberSubscript,
      ])

    output.removeAll()
    #expect(NumberUtil.arabicToOtherForms("0", &output))
    #expect(output.count == 3)
    #expect(output.map(\.value) == ["⓪", "⁰", "₀"])
    #expect(output.map(\.style) == [.numberCircled, .numberSuperscript, .numberSubscript])

    for arabic in ["0123456789", "asdf0123456789", "0.001", "-100"] {
      output.removeAll()
      #expect(!NumberUtil.arabicToOtherForms(arabic, &output))
      #expect(output.isEmpty)
    }

    output.removeAll()
    #expect(!NumberUtil.arabicToOtherForms("18446744073709551616", &output))  // UINT64_MAX + 1

    // Googol
    output.removeAll()
    #expect(NumberUtil.arabicToOtherForms("1" + String(repeating: "0", count: 100), &output))
    #expect(output.map(\.value) == ["Googol"])
  }

  @Test func arabicToOtherRadixesTest() {
    var output: [NumberUtil.NumberString] = []

    // "1" is "1" in any radixes.
    #expect(!NumberUtil.arabicToOtherRadixes("1", &output))

    output.removeAll()
    #expect(NumberUtil.arabicToOtherRadixes("2", &output))
    #expect(output.count == 1)

    output.removeAll()
    #expect(NumberUtil.arabicToOtherRadixes("8", &output))
    #expect(output.count == 2)
    #expect(output.map(\.value) == ["010", "0b1000"])
    #expect(output.map(\.style) == [.numberOct, .numberBin])

    output.removeAll()
    #expect(NumberUtil.arabicToOtherRadixes("16", &output))
    #expect(output.count == 3)
    #expect(output.map(\.value) == ["0x10", "020", "0b10000"])
    #expect(output.map(\.style) == [.numberHex, .numberOct, .numberBin])

    for arabic in ["asdf0123456789", "0.001", "-100"] {
      output.removeAll()
      #expect(!NumberUtil.arabicToOtherRadixes(arabic, &output))
      #expect(output.isEmpty)
    }

    output.removeAll()
    #expect(!NumberUtil.arabicToOtherRadixes("18446744073709551616", &output))  // UINT64_MAX + 1

    // Hex of a large number is lower case.
    output.removeAll()
    #expect(NumberUtil.arabicToOtherRadixes("18446744073709551615", &output))
    #expect(output[0].value == "0xffffffffffffffff")
  }
}
