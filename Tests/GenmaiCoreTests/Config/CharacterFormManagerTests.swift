// Port of mozc/src/config/character_form_manager_test.cc (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

// TestWithTempUserProfile + SetUp/TearDown (SetDefaultRule) are provided by the
// scoped environment: every test gets a fresh CharacterFormManager.
@Suite(.scopedConfigEnvironment) struct CharacterFormManagerTest {
  @Test func defaultTest() throws {
    let manager = CharacterFormManager.getCharacterFormManager()

  manager.clearHistory()

  #expect(manager.getPreeditCharacterForm("カタカナ") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("012") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("[") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("/") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("・") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("。") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("、") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("\\") == .fullWidth)

  #expect(manager.getConversionCharacterForm("ABC012ほげ") == .noConversion)

  #expect(manager.getConversionCharacterForm("カタカナ") == .fullWidth)

  #expect(manager.getConversionCharacterForm("012") == .fullWidth)

  #expect(manager.getConversionCharacterForm("[") == .fullWidth)

  #expect(manager.getConversionCharacterForm("/") == .fullWidth)

  #expect(manager.getConversionCharacterForm("・") == .fullWidth)

  #expect(manager.getConversionCharacterForm("。") == .fullWidth)

  #expect(manager.getConversionCharacterForm("、") == .fullWidth)

  #expect(manager.getConversionCharacterForm("\\") == .fullWidth)

  #expect(manager.getConversionCharacterForm("ABC012ほげ") == .noConversion)

  var output = ""
  manager.convertPreeditString("京都東京ABCインターネット", &output)
  #expect(output == "京都東京ＡＢＣインターネット")

  manager.convertPreeditString("ｲﾝﾀｰﾈｯﾄ", &output)
  #expect(output == "インターネット")

  manager.convertPreeditString("[]・。、", &output)
  #expect(output == "［］・。、")

  manager.convertPreeditString(".!@#$%^&", &output)
  #expect(output == "．！＠＃＄％＾＆")

  manager.convertPreeditString("京都東京ABCｲﾝﾀｰﾈｯﾄ012", &output)
  #expect(output == "京都東京ＡＢＣインターネット０１２")

  manager.convertPreeditString("グーグルABCｲﾝﾀｰﾈｯﾄ012あいう", &output)
  #expect(output == "グーグルＡＢＣインターネット０１２あいう")

  manager.convertPreeditString("京都東京ABCインターネット", &output)
  #expect(output == "京都東京ＡＢＣインターネット")

  manager.convertPreeditString("[京都]{東京}ABC!インターネット", &output)
  #expect(output == "［京都］｛東京｝ＡＢＣ！インターネット")

  manager.convertConversionString("ｲﾝﾀｰﾈｯﾄ", &output)
  #expect(output == "インターネット")

  manager.convertConversionString("[]・。、", &output)
  #expect(output == "［］・。、")

  manager.convertConversionString(".!@#$%^&", &output)
  #expect(output == "．！＠＃＄％＾＆")

  manager.convertConversionString("京都東京ABCｲﾝﾀｰﾈｯﾄ012", &output)
  #expect(output == "京都東京ＡＢＣインターネット０１２")

  manager.convertConversionString("グーグルABCｲﾝﾀｰﾈｯﾄ012あいう", &output)
  #expect(output == "グーグルＡＢＣインターネット０１２あいう")

  manager.convertConversionString("[京都]{東京}ABC!インターネット", &output)
  #expect(output == "［京都］｛東京｝ＡＢＣ！インターネット")

  // Set
  manager.setCharacterForm("カタカナ", .halfWidth)
  manager.setCharacterForm("012", .halfWidth)
  manager.setCharacterForm("[", .halfWidth)
  manager.setCharacterForm("/", .halfWidth)
  manager.setCharacterForm("・", .halfWidth)
  manager.setCharacterForm("。", .halfWidth)
  manager.setCharacterForm("、", .halfWidth)
  manager.setCharacterForm("\\", .halfWidth)

  // retry
  #expect(manager.getPreeditCharacterForm("カタカナ") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("012") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("[") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("/") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("・") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("。") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("、") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("\\") == .fullWidth)

  #expect(manager.getConversionCharacterForm("ABC012ほげ") == .noConversion)

  #expect(manager.getConversionCharacterForm("カタカナ") == .fullWidth)

  #expect(manager.getConversionCharacterForm("012") == .halfWidth)

  #expect(manager.getConversionCharacterForm("[") == .halfWidth)

  #expect(manager.getConversionCharacterForm("/") == .halfWidth)

  #expect(manager.getConversionCharacterForm("・") == .fullWidth)

  #expect(manager.getConversionCharacterForm("。") == .fullWidth)

  #expect(manager.getConversionCharacterForm("、") == .fullWidth)

  #expect(manager.getConversionCharacterForm("\\") == .halfWidth)

  manager.convertPreeditString("京都東京ABCインターネット", &output)
  #expect(output == "京都東京ＡＢＣインターネット")

  manager.convertPreeditString("ｲﾝﾀｰﾈｯﾄ", &output)
  #expect(output == "インターネット")

  manager.convertPreeditString("[]・。、", &output)
  #expect(output == "［］・。、")

  manager.convertPreeditString(".!@#$%^&", &output)
  #expect(output == "．！＠＃＄％＾＆")

  manager.convertPreeditString("京都東京ABCｲﾝﾀｰﾈｯﾄ", &output)
  #expect(output == "京都東京ＡＢＣインターネット")

  manager.convertPreeditString("グーグルABCｲﾝﾀｰﾈｯﾄあいう", &output)
  #expect(output == "グーグルＡＢＣインターネットあいう")

  manager.convertPreeditString("京都東京ABCインターネット", &output)
  #expect(output == "京都東京ＡＢＣインターネット")

  manager.convertPreeditString("[京都]{東京}ABC!インターネット", &output)
  #expect(output == "［京都］｛東京｝ＡＢＣ！インターネット")

  manager.convertConversionString("ｲﾝﾀｰﾈｯﾄ", &output)
  #expect(output == "インターネット")

  manager.convertConversionString("[]・。、", &output)
  #expect(output == "[]・。、")

  // require_consistent_conversion_ suppresses this conversion because
  // ".!@#$%^&" would become "．！@#$%^&" by preference, which mixes
  // full-width ("．！") and half-width ("@#$%^&") forms within a contiguous
  // run of variable-width symbols.
  manager.convertConversionString(".!@#$%^&", &output)
  #expect(output == ".!@#$%^&")

  // Converting chunks separately confirms that each chunk matches its
  // individual preference.
  manager.convertConversionString(".!", &output)
  #expect(output == "．！")
  manager.convertConversionString("@#$%^&", &output)
  #expect(output == "@#$%^&")

  manager.convertConversionString("京都東京ABCｲﾝﾀｰﾈｯﾄ", &output)
  #expect(output == "京都東京ＡＢＣインターネット")

  manager.convertConversionString("グーグルABCｲﾝﾀｰﾈｯﾄあいう", &output)
  #expect(output == "グーグルＡＢＣインターネットあいう")

  // "[京都]{東京}ABC!インターネット" would be
  // "[京都]{東京}ＡＢＣ！インターネット" by preference, but "}ABC!" is not
  // consistent within that contiguous variable-width run, so it is kept as-is.
  manager.convertConversionString("[京都]{東京}ABC!インターネット", &output)
  #expect(output == "[京都]{東京}ABC!インターネット")

  manager.convertConversionString("[京都]{東京}", &output)
  #expect(output == "[京都]{東京}")

  manager.convertConversionString("ABC!インターネット", &output)
  #expect(output == "ＡＢＣ！インターネット")

  // reset
  manager.setCharacterForm("カタカナ", .fullWidth)
  manager.setCharacterForm("012", .fullWidth)
  manager.setCharacterForm("[", .fullWidth)
  manager.setCharacterForm("/", .fullWidth)
  manager.setCharacterForm("・", .fullWidth)
  manager.setCharacterForm("。", .fullWidth)
  manager.setCharacterForm("、", .fullWidth)
  manager.setCharacterForm("\\", .fullWidth)

  #expect(manager.getPreeditCharacterForm("カタカナ") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("012") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("[") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("/") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("・") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("。") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("、") == .fullWidth)

  #expect(manager.getPreeditCharacterForm("\\") == .fullWidth)

  #expect(manager.getConversionCharacterForm("ABC012ほげ") == .noConversion)

  #expect(manager.getConversionCharacterForm("カタカナ") == .fullWidth)

  #expect(manager.getConversionCharacterForm("012") == .fullWidth)

  #expect(manager.getConversionCharacterForm("[") == .fullWidth)

  #expect(manager.getConversionCharacterForm("/") == .fullWidth)

  #expect(manager.getConversionCharacterForm("・") == .fullWidth)

  #expect(manager.getConversionCharacterForm("。") == .fullWidth)

  #expect(manager.getConversionCharacterForm("、") == .fullWidth)

  #expect(manager.getConversionCharacterForm("ABC012ほげ") == .noConversion)

  manager.convertPreeditString("京都東京ABCインターネット", &output)
  #expect(output == "京都東京ＡＢＣインターネット")

  manager.convertPreeditString("ｲﾝﾀｰﾈｯﾄ", &output)
  #expect(output == "インターネット")

  manager.convertPreeditString("[]・。、", &output)
  #expect(output == "［］・。、")

  manager.convertPreeditString(".!@#$%^&", &output)
  #expect(output == "．！＠＃＄％＾＆")

  manager.convertPreeditString("京都東京ABCｲﾝﾀｰﾈｯﾄ012", &output)
  #expect(output == "京都東京ＡＢＣインターネット０１２")

  manager.convertPreeditString("グーグルABCｲﾝﾀｰﾈｯﾄ012あいう", &output)
  #expect(output == "グーグルＡＢＣインターネット０１２あいう")

  manager.convertPreeditString("京都東京ABCインターネット", &output)
  #expect(output == "京都東京ＡＢＣインターネット")

  manager.convertPreeditString("[京都]{東京}ABC!インターネット", &output)
  #expect(output == "［京都］｛東京｝ＡＢＣ！インターネット")

  manager.convertConversionString("ｲﾝﾀｰﾈｯﾄ", &output)
  #expect(output == "インターネット")

  manager.convertConversionString("[]・。、", &output)
  #expect(output == "［］・。、")

  manager.convertConversionString(".!@#$%^&", &output)
  #expect(output == "．！＠＃＄％＾＆")

  manager.convertConversionString("京都東京ABCｲﾝﾀｰﾈｯﾄ012", &output)
  #expect(output == "京都東京ＡＢＣインターネット０１２")

  manager.convertConversionString("グーグルABCｲﾝﾀｰﾈｯﾄ012あいう", &output)
  #expect(output == "グーグルＡＢＣインターネット０１２あいう")

  manager.convertConversionString("[京都]{東京}ABC!インターネット", &output)
  #expect(output == "［京都］｛東京｝ＡＢＣ！インターネット")
}

  @Test func mixedFormTest() throws {
    let manager = CharacterFormManager.getCharacterFormManager()

  manager.addConversionRule("0", .fullWidth)
  manager.addConversionRule(".,", .halfWidth)
  manager.addPreeditRule("0", .fullWidth)
  manager.addPreeditRule(".,", .halfWidth)

  var output = ""
  // A period surrounded by numbers is treated as part of the number run ("0"
  // rule).
  manager.convertConversionString("1.23", &output)
  #expect(output == "１．２３")

  manager.convertPreeditString("1.23", &output)
  #expect(output == "１．２３")

  // When not surrounded by numbers, the period follows the ".," rule.
  // In conversion, require_consistent_conversion_ prevents mixed-width
  // conversion of "ABC.DEF".
  manager.convertConversionString("ABC.DEF", &output)
  #expect(output == "ABC.DEF")

  // In preedit, where require_consistent_conversion_ is false, chunks are
  // converted according to their respective preferences.
  manager.convertPreeditString("ABC.DEF", &output)
  #expect(output == "ＡＢＣ.ＤＥＦ")
}

  @Test func chunkNormalizationAndAlternativeTest() throws {
    let manager = CharacterFormManager.getCharacterFormManager()

  // Test 1: "Tシャツ" / "Ｔシャツ"
  do {
    manager.setDefaultRule()
    manager.setCharacterForm("A", .fullWidth)
    manager.setCharacterForm("ア", .fullWidth)

    var primary = "", secondary = ""
    #expect(manager.convertConversionStringWithAlternative("Tシャツ", &primary, &secondary))
    #expect(primary == "Ｔシャツ")
    #expect(secondary == "Tシャツ")

    manager.setCharacterForm("A", .halfWidth)
    #expect(manager.convertConversionStringWithAlternative("Ｔシャツ", &primary, &secondary))
    #expect(primary == "Tシャツ")
    #expect(secondary == "Ｔシャツ")
  }

  // Test 2: "3時" / "３時"
  do {
    manager.setDefaultRule()
    manager.setCharacterForm("0", .fullWidth)

    var primary = "", secondary = ""
    #expect(manager.convertConversionStringWithAlternative("3時", &primary, &secondary))
    #expect(primary == "３時")
    #expect(secondary == "3時")

    manager.setCharacterForm("0", .halfWidth)
    #expect(manager.convertConversionStringWithAlternative("３時", &primary, &secondary))
    #expect(primary == "3時")
    #expect(secondary == "３時")
  }

  // Test 3: "3.14" / "３．１４" and "1,234" / "１，２３４"
  do {
    manager.setDefaultRule()
    manager.setCharacterForm("0", .fullWidth)

    var primary = "", secondary = ""
    #expect(manager.convertConversionStringWithAlternative("3.14", &primary, &secondary))
    #expect(primary == "３．１４")
    #expect(secondary == "3.14")

    #expect(manager.convertConversionStringWithAlternative("1,234", &primary, &secondary))
    #expect(primary == "１，２３４")
    #expect(secondary == "1,234")

    manager.setCharacterForm("0", .halfWidth)
    #expect(manager.convertConversionStringWithAlternative("３．１４", &primary, &secondary))
    #expect(primary == "3.14")
    #expect(secondary == "３．１４")

    #expect(manager.convertConversionStringWithAlternative("１，２３４", &primary, &secondary))
    #expect(primary == "1,234")
    #expect(secondary == "１，２３４")
  }

  // Test 4: "2日です。"
  do {
    manager.setDefaultRule()
    manager.setCharacterForm("0", .halfWidth)

    var primary = "", secondary = ""
    #expect(manager.convertConversionStringWithAlternative("２日です。", &primary, &secondary))
    #expect(primary == "2日です。")
    #expect(secondary == "２日です。")
  }

  // Test 5: Regression tests for mixed alphanumeric/symbol candidates
  // ("Wi-Fi", "C++", "Yahoo!", "12:30").
  // When alphabet/number is learned as half-width, but symbols have not been
  // committed (defaulting to full-width in storage fallback), consistency
  // within a variable-width run must be preserved, preventing inconsistent
  // forms like "Wi－Fi", "C＋＋", "Yahoo！", or "12：30".
  do {
    manager.setDefaultRule()
    manager.clearHistory()
    manager.setCharacterForm("A", .halfWidth)
    manager.setCharacterForm("0", .halfWidth)

    var primary = "", secondary = ""

    // "Wi-Fi" keeps primary as "Wi-Fi" because "-" is uncommitted (fallback
    // full-width) and adjacent to alphabet "Wi" and "Fi" in the same
    // variable-width run, but still generates full-width alternative
    // "Ｗｉ−Ｆｉ".
    #expect(manager.convertConversionStringWithAlternative("Wi-Fi", &primary, &secondary))
    #expect(primary == "Wi-Fi")
    #expect(secondary == "Ｗｉ−Ｆｉ")

    // "C++" keeps primary "C++", generates "Ｃ＋＋".
    #expect(manager.convertConversionStringWithAlternative("C++", &primary, &secondary))
    #expect(primary == "C++")
    #expect(secondary == "Ｃ＋＋")

    // "Yahoo!" keeps primary "Yahoo!", generates "Ｙａｈｏｏ！".
    #expect(manager.convertConversionStringWithAlternative("Yahoo!", &primary, &secondary))
    #expect(primary == "Yahoo!")
    #expect(secondary == "Ｙａｈｏｏ！")

    // "12:30" keeps primary "12:30", generates "１２：３０".
    #expect(manager.convertConversionStringWithAlternative("12:30", &primary, &secondary))
    #expect(primary == "12:30")
    #expect(secondary == "１２：３０")

    // If the symbol is explicitly set/learned as HALF_WIDTH, conversion
    // from full-width input succeeds consistently to half-width.
    manager.setCharacterForm("-", .halfWidth)
    #expect(manager.convertConversionStringWithAlternative("Ｗｉ−Ｆｉ", &primary, &secondary))
    #expect(primary == "Wi-Fi")
    #expect(secondary == "Ｗｉ−Ｆｉ")
  }

  // Test 6: Japanese brackets/punctuation and katakana as run delimiters.
  do {
    manager.setDefaultRule()
    manager.setCharacterForm("A", .halfWidth)
    manager.setCharacterForm("0", .halfWidth)
    manager.setCharacterForm("ア", .fullWidth)

    var primary = "", secondary = ""

    // "「Ｔシャツ」" converts to "「Tシャツ」" because "「" is a fixed-width
    // delimiter.
    #expect(manager.convertConversionStringWithAlternative("「Ｔシャツ」", &primary, &secondary))
    #expect(primary == "「Tシャツ」")
    #expect(secondary == "「Ｔシャツ」")

    // "「３時」" converts to "「3時」".
    #expect(manager.convertConversionStringWithAlternative("「３時」", &primary, &secondary))
    #expect(primary == "「3時」")
    #expect(secondary == "「３時」")

    // "１００。" converts to "100。" because "。" is a fixed-width delimiter.
    #expect(manager.convertConversionStringWithAlternative("１００。", &primary, &secondary))
    #expect(primary == "100。")
    #expect(secondary == "１００。")

    // "ABCｲﾝﾀｰﾈｯﾄ" converts to "ABCインターネット" because katakana acts as a
    // delimiter regardless of whether input katakana is full- or half-width.
    var output = ""
    manager.convertConversionString("ABCｲﾝﾀｰﾈｯﾄ", &output)
    #expect(output == "ABCインターネット")
  }
}

  @Test func groupTest() throws {
    let manager = CharacterFormManager.getCharacterFormManager()

  do {
    manager.clearHistory()
    manager.clear()
    manager.addConversionRule("ア", .fullWidth)
    manager.addPreeditRule("ア", .halfWidth)
    manager.addConversionRule("[]", .halfWidth)
    manager.addPreeditRule("[]", .fullWidth)
    manager.addConversionRule("!@#$%^&*()-=", .fullWidth)
    manager.addConversionRule("!@#$%^&*()-=", .halfWidth)

    #expect(manager.getConversionCharacterForm("[") == .halfWidth)

    #expect(manager.getPreeditCharacterForm("[") == .fullWidth)

    #expect(manager.getPreeditCharacterForm("ア") == .halfWidth)

    manager.setCharacterForm("[", .fullWidth)
    manager.setCharacterForm("ア", .fullWidth)
    manager.setCharacterForm("@", .fullWidth)

    #expect(manager.getConversionCharacterForm("[") == .halfWidth)

    #expect(manager.getPreeditCharacterForm("[") == .fullWidth)

    #expect(manager.getPreeditCharacterForm("ア") == .halfWidth)
  }

  do {
    manager.clearHistory()
    manager.clear()
    manager.addConversionRule("ア", .fullWidth)
    manager.addConversionRule("[]", .lastForm)
    manager.addConversionRule("!@#$%^&*()-=", .fullWidth)

    #expect(manager.getConversionCharacterForm("[") == .fullWidth)  // default

    // same group
    manager.setCharacterForm("]", .halfWidth)

    #expect(manager.getConversionCharacterForm("[") == .halfWidth)
  }

  do {
    manager.clearHistory()
    manager.clear()
    manager.addConversionRule("ア", .fullWidth)
    manager.addConversionRule("[](){}", .lastForm)
    manager.addConversionRule("!@#$%^&*-=", .fullWidth)

    #expect(manager.getConversionCharacterForm("{") == .fullWidth)
    #expect(manager.getConversionCharacterForm("}") == .fullWidth)
    #expect(manager.getConversionCharacterForm("(") == .fullWidth)
    #expect(manager.getConversionCharacterForm(")") == .fullWidth)

    // same group
    manager.setCharacterForm(")", .halfWidth)

    #expect(manager.getConversionCharacterForm("{") == .halfWidth)
    #expect(manager.getConversionCharacterForm("}") == .halfWidth)
    #expect(manager.getConversionCharacterForm("(") == .halfWidth)
    #expect(manager.getConversionCharacterForm(")") == .halfWidth)
  }

  do {
    manager.clearHistory()
    manager.clear()
    manager.addConversionRule("ア", .fullWidth)
    manager.addConversionRule("[](){}", .lastForm)
    manager.addPreeditRule("[](){}", .fullWidth)
    manager.addConversionRule("!@#$%^&*-=", .fullWidth)

    #expect(manager.getConversionCharacterForm("{") == .fullWidth)
    #expect(manager.getConversionCharacterForm("}") == .fullWidth)
    #expect(manager.getConversionCharacterForm("(") == .fullWidth)
    #expect(manager.getConversionCharacterForm(")") == .fullWidth)

    #expect(manager.getPreeditCharacterForm("{") == .fullWidth)
    #expect(manager.getPreeditCharacterForm("}") == .fullWidth)
    #expect(manager.getPreeditCharacterForm("(") == .fullWidth)
    #expect(manager.getPreeditCharacterForm(")") == .fullWidth)

    // same group
    manager.setCharacterForm(")", .halfWidth)

    #expect(manager.getConversionCharacterForm("{") == .halfWidth)
    #expect(manager.getConversionCharacterForm("}") == .halfWidth)
    #expect(manager.getConversionCharacterForm("(") == .halfWidth)
    #expect(manager.getConversionCharacterForm(")") == .halfWidth)

    #expect(manager.getPreeditCharacterForm("{") == .fullWidth)
    #expect(manager.getPreeditCharacterForm("}") == .fullWidth)
    #expect(manager.getPreeditCharacterForm("(") == .fullWidth)
    #expect(manager.getPreeditCharacterForm(")") == .fullWidth)
  }
}

  @Test func invalidStringTest() throws {
    let manager = CharacterFormManager.getCharacterFormManager()

  var output = ""
  // "る<invalid>る"
  // Swift strings cannot hold invalid UTF-8: decoding the bytes replaces the
  // invalid byte with U+FFFD, which is then kept as an unknown symbol. (C++
  // drops the invalid byte and returns "るる".)
  let input = String(decoding: [0xE3, 0x82, 0x8B, 0x88, 0xE3, 0x82, 0x8B] as [UInt8], as: UTF8.self)
  manager.convertConversionString(input, &output)
  #expect(output == "る\u{FFFD}る")
}

  @Test func numberStyle() throws {
    let manager = CharacterFormManager.getCharacterFormManager()
  do {
    let storedEntry = manager.getLastNumberStyle()
    #expect(storedEntry == nil)
  }

  let entry = CharacterFormManager.NumberFormStyle(form: .fullWidth, style: .defaultStyle)
  manager.setLastNumberStyle(entry)

  do {
    let storedEntry = try #require(manager.getLastNumberStyle())
    #expect(storedEntry.form == entry.form)
    #expect(storedEntry.style == entry.style)
  }
}

  @Test func guessAndSetCharacterForm() throws {
    let manager = CharacterFormManager.getCharacterFormManager()
  manager.clearHistory()

  #expect(manager.getConversionCharacterForm("0") == .fullWidth)

  manager.guessAndSetCharacterForm("123")
  #expect(manager.getConversionCharacterForm("0") == .halfWidth)

  manager.guessAndSetCharacterForm("１２３")
  #expect(manager.getConversionCharacterForm("0") == .fullWidth)

  // Mixed-script number + Kanji counter.
  manager.guessAndSetCharacterForm("2日")
  #expect(manager.getConversionCharacterForm("0") == .halfWidth)

  manager.guessAndSetCharacterForm("２日")
  #expect(manager.getConversionCharacterForm("0") == .fullWidth)

  // Hiragana + number + Hiragana.
  manager.guessAndSetCharacterForm("あと3つ")
  #expect(manager.getConversionCharacterForm("0") == .halfWidth)

  // Decimal and comma-separated numbers.
  manager.guessAndSetCharacterForm("３．１４")
  #expect(manager.getConversionCharacterForm("0") == .fullWidth)

  manager.guessAndSetCharacterForm("3.14")
  #expect(manager.getConversionCharacterForm("0") == .halfWidth)

  // Full-width number with half-width period (e.g., when number and period
  // rules have different widths).
  manager.guessAndSetCharacterForm("３.１４")
  #expect(manager.getConversionCharacterForm("0") == .fullWidth)

  manager.guessAndSetCharacterForm("1.項目")
  #expect(manager.getConversionCharacterForm("0") == .halfWidth)

  manager.guessAndSetCharacterForm("１.項目")
  #expect(manager.getConversionCharacterForm("0") == .fullWidth)

  manager.guessAndSetCharacterForm("１，０００")
  #expect(manager.getConversionCharacterForm("0") == .fullWidth)

  manager.guessAndSetCharacterForm("1,000")
  #expect(manager.getConversionCharacterForm("0") == .halfWidth)

  // Katakana with prolonged sound mark.
  manager.addConversionRule("カタカナ", .lastForm)
  manager.guessAndSetCharacterForm("ｲﾝﾀｰﾈｯﾄ")
  #expect(manager.getConversionCharacterForm("カタカナ") == .halfWidth)

  manager.guessAndSetCharacterForm("インターネット")
  #expect(manager.getConversionCharacterForm("カタカナ") == .fullWidth)

  // Embedded full-width middle dot should not overwrite symbol rule or prevent
  // learning half-width katakana.
  manager.addConversionRule("・「」", .lastForm)
  manager.setCharacterForm("「", .halfWidth)
  manager.guessAndSetCharacterForm("東京・大阪")
  #expect(manager.getConversionCharacterForm("「") == .halfWidth)

  manager.guessAndSetCharacterForm("ｱ・ｲ")
  #expect(manager.getConversionCharacterForm("カタカナ") == .halfWidth)
}

  @Test func storageSerializationTest() throws {
    let manager = CharacterFormManager.getCharacterFormManager()
  manager.clearHistory()
  #expect(!manager.isStorageDirty())

  manager.setCharacterForm("012", .halfWidth)
  manager.setCharacterForm("[", .halfWidth)
  let numberStyle = CharacterFormManager.NumberFormStyle(form: .halfWidth, style: .numberKanji)
  manager.setLastNumberStyle(numberStyle)
  #expect(manager.isStorageDirty())

  var history = Genmai_UserHistoryPredictor_UserHistory()
  manager.saveStorage(&history)
  #expect(!manager.isStorageDirty())

  manager.clearHistory()
  #expect(manager.getConversionCharacterForm("012") == .fullWidth)
  #expect(manager.getConversionCharacterForm("[") == .fullWidth)
  #expect(manager.getLastNumberStyle() == nil)

  manager.loadStorage(history)
  #expect(!manager.isStorageDirty())
  #expect(manager.getConversionCharacterForm("012") == .halfWidth)
  #expect(manager.getConversionCharacterForm("[") == .halfWidth)
  #expect(manager.getConversionCharacterForm("]") == .halfWidth)
  let loadedStyle = try #require(manager.getLastNumberStyle())
  #expect(loadedStyle.form == numberStyle.form)
  #expect(loadedStyle.style == numberStyle.style)
}

}
