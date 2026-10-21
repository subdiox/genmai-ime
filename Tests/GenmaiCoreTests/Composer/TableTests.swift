// Port of mozc/src/composer/table_test.cc (3.35.6354).
//
// The C++ fixture holds a MockDataManager that no test uses; it is omitted.

import Foundation
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private typealias Config = Genmai_Config_Config
private typealias Request = Genmai_Commands_Request

private func initTable(_ table: Table) {
  table.addRule("a", "あ", "")
  table.addRule("i", "い", "")
  table.addRule("ka", "か", "")
  table.addRule("ki", "き", "")
  table.addRule("ku", "く", "")
  table.addRule("ke", "け", "")
  table.addRule("ko", "こ", "")
  table.addRule("kk", "っ", "k")
  table.addRule("na", "な", "")
  table.addRule("ni", "に", "")
  table.addRule("n", "ん", "")
  table.addRule("nn", "ん", "")
}

private func getResult(_ table: Table, _ key: String) -> String {
  guard let entry = table.lookUp(key) else {
    return "<nullptr>"
  }
  return entry.result
}

private func getInput(_ table: Table, _ key: String) -> String {
  guard let entry = table.lookUp(key) else {
    return "<nullptr>"
  }
  return entry.input
}

private func defaultConfig() -> Config {
  var config = Config()
  ConfigHandler.getDefaultConfig(&config)
  return config
}

@Suite struct TableTest {
  @Test func lookUp() {
    struct TestCase {
      var input: String
      var expectedResult: Bool
      var expectedOutput: String
      var expectedPending: String
      init(_ input: String, _ expectedResult: Bool, _ expectedOutput: String, _ expectedPending: String) {
        self.input = input
        self.expectedResult = expectedResult
        self.expectedOutput = expectedOutput
        self.expectedPending = expectedPending
      }
    }
    let testCases = [
      TestCase("a", true, "あ", ""), TestCase("k", false, "", ""), TestCase("ka", true, "か", ""),
      TestCase("ki", true, "き", ""), TestCase("ku", true, "く", ""), TestCase("kk", true, "っ", "k"),
      TestCase("aka", false, "", ""), TestCase("na", true, "な", ""), TestCase("n", true, "ん", ""),
      TestCase("nn", true, "ん", ""),
    ]

    let table = Table()
    initTable(table)

    for test in testCases {
      let entry = table.lookUp(test.input)

      #expect((entry != nil) == test.expectedResult)
      guard let entry else {
        continue
      }
      #expect(entry.result == test.expectedOutput)
      #expect(entry.pending == test.expectedPending)
    }
  }

  @Test func lookUpPredictiveAll() {
    let table = Table()
    initTable(table)

    var results: [Entry] = []
    table.lookUpPredictiveAll("k", &results)

    #expect(results.count == 6)
  }

  @Test func punctuations() throws {
    let testCases: [(Config.PunctuationMethod, String, String)] = [
      (.toutenKuten, ",", "、"),
      (.toutenKuten, ".", "。"),
      (.commaPeriod, ",", "，"),
      (.commaPeriod, ".", "．"),
      (.toutenPeriod, ",", "、"),
      (.toutenPeriod, ".", "．"),
      (.commaKuten, ",", "，"),
      (.commaKuten, ".", "。"),
    ]

    let request = Request()
    for (index, testCase) in testCases.enumerated() {
      var config = Config()
      config.punctuationMethod = testCase.0
      let table = Table()
      try #require(table.initializeWithRequestAndConfig(request, config))

      let entry = table.lookUp(testCase.1)
      #expect(entry != nil, "Failed index = \(index)")
      if let entry {
        #expect(entry.result == testCase.2)
      }
    }
  }

  @Test func symbols() throws {
    let testCases: [(Config.SymbolMethod, String, String)] = [
      (.cornerBracketMiddleDot, "[", "「"),
      (.cornerBracketMiddleDot, "]", "」"),
      (.cornerBracketMiddleDot, "/", "・"),
      (.squareBracketSlash, "[", "["),
      (.squareBracketSlash, "]", "]"),
      (.squareBracketSlash, "/", "／"),
      (.cornerBracketSlash, "[", "「"),
      (.cornerBracketSlash, "]", "」"),
      (.cornerBracketSlash, "/", "／"),
      (.squareBracketMiddleDot, "[", "["),
      (.squareBracketMiddleDot, "]", "]"),
      (.squareBracketMiddleDot, "/", "・"),
    ]

    let request = Request()
    for (index, testCase) in testCases.enumerated() {
      var config = Config()
      config.symbolMethod = testCase.0
      let table = Table()
      try #require(table.initializeWithRequestAndConfig(request, config))

      let entry = table.lookUp(testCase.1)
      #expect(entry != nil, "Failed index = \(index)")
      if let entry {
        #expect(entry.result == testCase.2)
      }
    }
  }

  @Test func kanaSuppressed() throws {
    var config = defaultConfig()
    config.preeditMethod = .kana

    let request = Request()

    let table = Table()
    try #require(table.initializeWithRequestAndConfig(request, config))

    let entry = try #require(table.lookUp("a"))
    #expect(entry.result == "あ")
    #expect(entry.pending.isEmpty)
  }

  @Test func kanaCombination() throws {
    let table = Table()
    let request = Request()
    try #require(table.initializeWithRequestAndConfig(request, defaultConfig()))

    let entry = try #require(table.lookUp("か゛"))
    #expect(entry.result == "が")
    #expect(entry.pending.isEmpty)
  }

  @Test func invalidEntryTest() {
    do {
      let table = Table()
      #expect(!table.isLoopingEntry("a", "b"))
      table.addRule("a", "aa", "b")

      #expect(table.isLoopingEntry("b", "a"))
      table.addRule("b", "aa", "a")  // looping

      #expect(table.lookUp("a") != nil)
      #expect(table.lookUp("b") == nil)
    }

    do {
      let table = Table()
      #expect(!table.isLoopingEntry("a", "ba"))
      table.addRule("a", "aa", "ba")

      #expect(table.isLoopingEntry("b", "a"))
      table.addRule("b", "aa", "a")  // looping

      #expect(table.lookUp("a") != nil)
      #expect(table.lookUp("b") == nil)
    }

    do {
      let table = Table()
      #expect(!table.isLoopingEntry("a", "b"))
      table.addRule("a", "aa", "b")

      #expect(!table.isLoopingEntry("b", "c"))
      table.addRule("b", "aa", "c")

      #expect(!table.isLoopingEntry("c", "d"))
      table.addRule("c", "aa", "d")

      #expect(table.isLoopingEntry("d", "a"))
      table.addRule("d", "aa", "a")  // looping

      #expect(table.lookUp("a") != nil)
      #expect(table.lookUp("b") != nil)
      #expect(table.lookUp("c") != nil)
      #expect(table.lookUp("d") == nil)
    }

    do {
      let table = Table()
      table.addRule("wa", "WA", "")
      table.addRule("ww", "X", "w")

      #expect(!table.isLoopingEntry("www", "ww"))
      table.addRule("www", "W", "ww")  // not looping

      #expect(table.lookUp("wa") != nil)
      #expect(table.lookUp("ww") != nil)
      #expect(table.lookUp("www") != nil)
    }

    do {
      let table = Table()
      table.addRule("wa", "WA", "")
      table.addRule("www", "W", "ww")

      #expect(!table.isLoopingEntry("ww", "w"))
      table.addRule("ww", "X", "w")

      #expect(table.lookUp("wa") != nil)
      #expect(table.lookUp("ww") != nil)
      #expect(table.lookUp("www") != nil)
    }

    do {
      let table = Table()
      #expect(table.isLoopingEntry("a", "a"))
      table.addRule("a", "aa", "a")  // looping

      #expect(table.lookUp("a") == nil)
    }

    // Too long input
    do {
      let table = Table()
      // Maximum size is 300 now.
      let tooLong = String(repeating: "a", count: 1024)
      table.addRule(tooLong, "test", "test")
      #expect(table.lookUp(tooLong) == nil)

      table.addRule("a", tooLong, "test")
      #expect(table.lookUp("a") == nil)

      table.addRule("a", "test", tooLong)
      #expect(table.lookUp("a") == nil)
    }

    // reasonably long
    do {
      let table = Table()
      // Maximum size is 300 now.
      let reasonablyLong = String(repeating: "a", count: 200)
      table.addRule(reasonablyLong, "test", "test")
      #expect(table.lookUp(reasonablyLong) != nil)

      table.addRule("a", reasonablyLong, "test")
      #expect(table.lookUp("a") != nil)

      table.addRule("a", "test", reasonablyLong)
      #expect(table.lookUp("a") != nil)
    }
  }

  @Test func customPunctuationsAndSymbols() throws {
    // Test against Issue2465801.
    var customRomanTable = ""
    customRomanTable += "mozc\tMOZC\n"
    customRomanTable += ",\tCOMMA\n"
    customRomanTable += ".\tPERIOD\n"
    customRomanTable += "/\tSLASH\n"
    customRomanTable += "[\tOPEN\n"
    customRomanTable += "]\tCLOSE\n"

    var config = defaultConfig()
    config.customRomanTable = Data(customRomanTable.utf8)

    let table = Table()
    let request = Request()
    table.initializeWithRequestAndConfig(request, config)

    var entry = try #require(table.lookUp("mozc"))
    #expect(entry.result == "MOZC")

    entry = try #require(table.lookUp(","))
    #expect(entry.result == "COMMA")

    entry = try #require(table.lookUp("."))
    #expect(entry.result == "PERIOD")

    entry = try #require(table.lookUp("/"))
    #expect(entry.result == "SLASH")

    entry = try #require(table.lookUp("["))
    #expect(entry.result == "OPEN")

    entry = try #require(table.lookUp("]"))
    #expect(entry.result == "CLOSE")
  }

  @Test func caseSensitive() {
    let table = Table()
    table.addRule("a", "[a]", "")
    table.addRule("A", "[A]", "")
    table.addRule("ba", "[ba]", "")
    table.addRule("BA", "[BA]", "")
    table.addRule("Ba", "[Ba]", "")
    // The rule of "bA" is intentionally dropped.
    // table.AddRule("bA",  "[bA]", "");
    table.addRule("za", "[za]", "")

    // case insensitive
    table.setCaseSensitive(false)
    #expect(getResult(table, "a") == "[a]")
    #expect(getResult(table, "A") == "[a]")
    #expect(getResult(table, "ba") == "[ba]")
    #expect(getResult(table, "BA") == "[ba]")
    #expect(getResult(table, "Ba") == "[ba]")
    #expect(getResult(table, "bA") == "[ba]")

    #expect(getInput(table, "a") == "a")
    #expect(getInput(table, "A") == "a")
    #expect(getInput(table, "ba") == "ba")
    #expect(getInput(table, "BA") == "ba")
    #expect(getInput(table, "Ba") == "ba")
    #expect(getInput(table, "bA") == "ba")

    // Test for HasSubRules
    #expect(table.hasSubRules("Z"))

    do {  // Test for LookUpPrefix
      var keyLength = 0
      var fixed = false
      let entry = table.lookUpPrefix("bA", &keyLength, &fixed)
      #expect(entry != nil)
      #expect(entry?.result == "[ba]")
      #expect(keyLength == 2)
      #expect(fixed)
    }

    // case sensitive
    table.setCaseSensitive(true)
    #expect(table.caseSensitive)
    #expect(getResult(table, "a") == "[a]")
    #expect(getResult(table, "A") == "[A]")
    #expect(getResult(table, "ba") == "[ba]")
    #expect(getResult(table, "BA") == "[BA]")
    #expect(getResult(table, "Ba") == "[Ba]")
    #expect(getResult(table, "bA") == "<nullptr>")

    #expect(getInput(table, "a") == "a")
    #expect(getInput(table, "A") == "A")
    #expect(getInput(table, "ba") == "ba")
    #expect(getInput(table, "BA") == "BA")
    #expect(getInput(table, "Ba") == "Ba")
    #expect(getInput(table, "bA") == "<nullptr>")

    // Test for HasSubRules
    #expect(!table.hasSubRules("Z"))

    do {  // Test for LookUpPrefix
      var keyLength = 0
      var fixed = false
      let entry = table.lookUpPrefix("bA", &keyLength, &fixed)
      #expect(entry == nil)
      #expect(keyLength == 1)
      #expect(fixed)
    }
  }

  @Test func caseSensitivity() {
    let request = Request()
    let config = defaultConfig()
    do {
      let table = Table()
      table.initializeWithRequestAndConfig(request, config)
      #expect(!table.caseSensitive)
    }
    do {
      let table = Table()
      table.initializeWithRequestAndConfig(request, config)
      table.addRule("", "", "")
      #expect(!table.caseSensitive)
    }
    do {
      let table = Table()
      table.initializeWithRequestAndConfig(request, config)
      table.addRule("a", "", "")
      #expect(!table.caseSensitive)
    }
    do {
      let table = Table()
      table.initializeWithRequestAndConfig(request, config)
      table.addRule("A", "", "")
      #expect(table.caseSensitive)
    }
    do {
      let table = Table()
      table.initializeWithRequestAndConfig(request, config)
      table.addRule("a{A}a", "", "")
      #expect(!table.caseSensitive)
    }
    do {
      let table = Table()
      table.initializeWithRequestAndConfig(request, config)
      table.addRule("A{A}A", "", "")
      #expect(table.caseSensitive)
    }
  }

  // This test case was needed because the case sensitivity was configured
  // by the configuration.
  // Currently the case sensitivity is independent from the configuration.
  @Test func caseSensitiveByConfiguration() {
    let request = Request()
    let table = Table()
    var config = defaultConfig()

    for mode in [Config.ShiftKeyModeSwitch.off, .asciiInputMode, .katakanaInputMode] {
      config.shiftKeyModeSwitch = mode
      table.initializeWithRequestAndConfig(request, config)

      table.addRule("a", "[a]", "")
      table.addRule("A", "[A]", "")
      table.addRule("ba", "[ba]", "")
      table.addRule("BA", "[BA]", "")
      table.addRule("Ba", "[Ba]", "")

      #expect(table.caseSensitive)
      #expect(getResult(table, "a") == "[a]")
      #expect(getResult(table, "A") == "[A]")
      #expect(getResult(table, "ba") == "[ba]")
      #expect(getResult(table, "BA") == "[BA]")
      #expect(getResult(table, "Ba") == "[Ba]")
      #expect(getResult(table, "bA") == "<nullptr>")

      #expect(getInput(table, "a") == "a")
      #expect(getInput(table, "A") == "A")
      #expect(getInput(table, "ba") == "ba")
      #expect(getInput(table, "BA") == "BA")
      #expect(getInput(table, "Ba") == "Ba")
      #expect(getInput(table, "bA") == "<nullptr>")

      // Test for HasSubRules
      #expect(!table.hasSubRules("Z"))

      do {  // Test for LookUpPrefix
        var keyLength = 0
        var fixed = false
        let entry = table.lookUpPrefix("bA", &keyLength, &fixed)
        #expect(entry == nil)
        #expect(keyLength == 1)
        #expect(fixed)
      }
    }
  }

  // Table class automatically enables case-sensitive mode when the given roman
  // table has any input rule which contains one or more upper case characters.
  //   e.g. "V" -> "5" or "YT" -> "You there"
  // This feature was implemented as b/2910223 as per following request.
  // http://www.google.com/support/forum/p/ime/thread?tid=4ea9aed4ac8a2ba6&hl=ja
  //
  // The following test checks if a case-sensitive and a case-insensitive roman
  // table enables and disables this "case-sensitive mode", respectively.
  @Test func automaticCaseSensitiveDetection() throws {
    let kCaseInsensitiveRomanTable =
      "m\tmozc\n"  // m -> mozc
      + "n\tnamazu\n"  // n -> namazu
    let kCaseSensitiveRomanTable =
      "m\tmozc\n"  // m -> mozc
      + "M\tGenmai\n"  // M -> Mozc

    let request = Request()

    do {
      let table = Table()
      var config = ConfigHandler.defaultConfig()
      config.customRomanTable = Data(kCaseSensitiveRomanTable.utf8)
      #expect(!table.caseSensitive, "case-sensitive mode should be desabled by default.")
      // Load a custom config with case-sensitive custom roman table.
      try #require(table.initializeWithRequestAndConfig(request, config))

      #expect(table.caseSensitive, "Case sensitive roman table should enable case-sensitive mode.")
      // Explicitly disable case-sensitive mode.
      table.setCaseSensitive(false)
      try #require(!table.caseSensitive)
    }

    do {
      let table = Table()
      // Load a custom config with case-insensitive custom roman table.
      var config = ConfigHandler.defaultConfig()
      config.customRomanTable = Data(kCaseInsensitiveRomanTable.utf8)
      try #require(table.initializeWithRequestAndConfig(request, config))

      #expect(
        !table.caseSensitive, "Case insensitive roman table should disable case-sensitive mode.")
      // Explicitly enable case-sensitive mode.
      table.setCaseSensitive(true)
      try #require(table.caseSensitive)
    }
  }

  @Test func mobileMode() throws {
    var request = Request()
    request.zeroQuerySuggestion = true
    request.mixedConversion = true
    let config = defaultConfig()

    do {
      // To 12keys -> Hiragana mode
      request.specialRomanjiTable = .twelveKeysToHiragana
      let table = Table()
      table.initializeWithRequestAndConfig(request, config)
      do {
        var keyLength = 0
        var fixed = false
        let entry = try #require(table.lookUpPrefix("2", &keyLength, &fixed))
        #expect(entry.input == "2")
        #expect(entry.result == "")
        #expect(entry.pending == "か")
        #expect(keyLength == 1)
        #expect(fixed)
      }
      do {
        var keyLength = 0
        var fixed = false
        let entry = try #require(table.lookUpPrefix("し*", &keyLength, &fixed))
        #expect(entry.input == "し*")
        #expect(entry.result == "")
        // U+F001 is a Unicode PUA character converted from "{*}".
        // This codepoint may be changed when the table data is updated.
        #expect(entry.pending == "\u{F001}じ")
        #expect(keyLength == 4)
        #expect(fixed)
      }
    }

    do {
      // To 12keys -> Halfwidth Ascii mode
      request.specialRomanjiTable = .twelveKeysToHalfwidthascii
      let table = Table()
      table.initializeWithRequestAndConfig(request, config)
      var keyLength = 0
      var fixed = false
      let entry = try #require(table.lookUpPrefix("2", &keyLength, &fixed))
      // U+F000 is a Unicode PUA character converted from "{?}".
      // This codepoint may be changed when the table data is updated.
      #expect(entry.pending == "\u{F000}a")
    }

    do {
      // To Godan -> Hiragana mode
      request.specialRomanjiTable = .godanToHiragana
      let table = Table()
      table.initializeWithRequestAndConfig(request, config)
      do {
        var keyLength = 0
        var fixed = false
        let entry = try #require(table.lookUpPrefix("しゃ*", &keyLength, &fixed))
        #expect(entry.pending == "じゃ")
      }
    }

    do {
      // To Flick -> Hiragana mode.
      request.specialRomanjiTable = .flickToHiragana
      let table = Table()
      table.initializeWithRequestAndConfig(request, config)

      var keyLength = 0
      var fixed = false
      let entry = try #require(table.lookUpPrefix("a", &keyLength, &fixed))
      #expect(entry.pending == "き")
    }

    do {
      // To Notouch -> Hiragana mode.
      request.specialRomanjiTable = .notouchToHiragana
      let table = Table()
      table.initializeWithRequestAndConfig(request, config)

      var keyLength = 0
      var fixed = false
      let entry = try #require(table.lookUpPrefix("a", &keyLength, &fixed))
      #expect(entry.pending == "き")
    }
  }

  @Test func orderOfAddRule() {
    // The order of AddRule should not be sensitive.
    do {
      let table = Table()
      table.addRule("www", "w", "ww")
      table.addRule("ww", "[X]", "w")
      table.addRule("we", "[WE]", "")
      #expect(table.hasSubRules("ww"))

      var entry = table.lookUp("ww")
      #expect(entry != nil)

      var keyLength = 0
      var fixed = false
      entry = table.lookUpPrefix("ww", &keyLength, &fixed)
      #expect(entry != nil)
      #expect(keyLength == 2)
      #expect(!fixed)
    }
    do {
      let table = Table()
      table.addRule("ww", "[X]", "w")
      table.addRule("we", "[WE]", "")
      table.addRule("www", "w", "ww")
      #expect(table.hasSubRules("ww"))

      var entry = table.lookUp("ww")
      #expect(entry != nil)

      var keyLength = 0
      var fixed = false
      entry = table.lookUpPrefix("ww", &keyLength, &fixed)
      #expect(entry != nil)
      #expect(keyLength == 2)
      #expect(!fixed)
    }
  }

  @Test func addRuleWithAttributes() throws {
    let kInput = "1"
    let table = Table()
    table.addRuleWithAttributes(kInput, "", "a", .newChunk)

    #expect(table.hasNewChunkEntry(kInput))

    var keyLength = 0
    var fixed = false
    var entry = table.lookUpPrefix(kInput, &keyLength, &fixed)
    #expect(keyLength == 1)
    #expect(fixed)
    var e = try #require(entry)
    #expect(e.input == kInput)
    #expect(e.result == "")
    #expect(e.pending == "a")
    #expect(e.attributes == .newChunk)

    let kInput2 = "22"
    table.addRuleWithAttributes(kInput2, "", "b", [.newChunk, .noTransliteration])

    #expect(table.hasNewChunkEntry(kInput2))

    keyLength = 0
    fixed = false
    entry = table.lookUpPrefix(kInput2, &keyLength, &fixed)
    #expect(keyLength == 2)
    #expect(fixed)
    e = try #require(entry)
    #expect(e.input == kInput2)
    #expect(e.result == "")
    #expect(e.pending == "b")
    #expect(e.attributes == [.newChunk, .noTransliteration])
  }

  @Test func loadFromString() throws {
    let kRule =
      "# This is a comment\n"
      + "\n"  // Empty line to be ignored.
      + "a\t[A]\n"  // 2 entry rule
      + "kk\t[X]\tk\n"  // 3 entry rule
      + "ww\t[W]\tw\tNewChunk\n"  // 3 entry rule + attribute rule
      + "xx\t[X]\tx\tNewChunk NoTransliteration\n"  // multiple attribute rules
      // all attributes
      + "yy\t[Y]\ty\tNewChunk NoTransliteration DirectInput EndChunk\n"
      + "#\t[#]\n"  // This line starts with '#' but should be a rule.
    let table = Table()
    table.loadFromString(kRule)

    // Test for "a\t[A]\n"  -- 2 entry rule
    #expect(!table.hasNewChunkEntry("a"))
    var entry = try #require(table.lookUp("a"))
    #expect(entry.result == "[A]")
    #expect(entry.pending == "")

    // Test for "kk\t[X]\tk\n"  -- 3 entry rule
    #expect(!table.hasNewChunkEntry("kk"))
    entry = try #require(table.lookUp("kk"))
    #expect(entry.result == "[X]")
    #expect(entry.pending == "k")

    // Test for "ww\t[W]\tw\tNewChunk\n"  -- 3 entry rule + attribute rule
    #expect(table.hasNewChunkEntry("ww"))
    entry = try #require(table.lookUp("ww"))
    #expect(entry.result == "[W]")
    #expect(entry.pending == "w")
    #expect(entry.attributes == .newChunk)

    // Test for "xx\t[X]\tx\tNewChunk NoTransliteration\n" -- multiple
    // attribute rules
    #expect(table.hasNewChunkEntry("xx"))
    entry = try #require(table.lookUp("xx"))
    #expect(entry.result == "[X]")
    #expect(entry.pending == "x")
    #expect(entry.attributes == [.newChunk, .noTransliteration])

    // Test for "yy\t[Y]\ty\tNewChunk NoTransliteration DirectInput EndChunk\n"
    // -- all attributes
    #expect(table.hasNewChunkEntry("yy"))
    entry = try #require(table.lookUp("yy"))
    #expect(entry.result == "[Y]")
    #expect(entry.pending == "y")
    #expect(entry.attributes == [.newChunk, .noTransliteration, .directInput, .endChunk])

    // Test for "#\t[#]\n"  -- This line starts with '#' but should be a rule.
    entry = try #require(table.lookUp("#"))
    #expect(entry.result == "[#]")
    #expect(entry.pending == "")
  }

  @Test func specialKeys() throws {
    do {
      let table = Table()
      table.addRule("x{#1}y", "X1Y", "")
      table.addRule("x{#2}y", "X2Y", "")
      table.addRule("x{{}", "X{", "")
      table.addRule("xy", "XY", "")

      var entry = table.lookUp("x{#1}y")
      #expect(entry == nil)

      var key = table.parseSpecialKey("x{#1}y")
      entry = table.lookUp(key)
      var e = try #require(entry)
      #expect(e.input == key)
      #expect(e.result == "X1Y")

      key = table.parseSpecialKey("x{#2}y")
      entry = table.lookUp(key)
      e = try #require(entry)
      #expect(e.input == key)
      #expect(e.result == "X2Y")

      key = "x{"
      entry = table.lookUp(key)
      e = try #require(entry)
      #expect(e.input == key)
      #expect(e.result == "X{")
    }

    do {
      // "{{}" is replaced with "{".
      // "{}" is replaced with U+F004.
      // {b} = U+F005, {d} = U+F006, {e} = U+F007, {{-} = U+F008.
      let table = Table()
      #expect(table.addRule("{}", "", "")?.input == "\u{F004}")
      #expect(table.addRule("{", "", "")?.input == "{")
      #expect(table.addRule("}", "", "")?.input == "}")
      #expect(table.addRule("{{}", "", "")?.input == "{")
      #expect(table.addRule("{{}}", "", "")?.input == "{}")
      #expect(table.addRule("a{", "", "")?.input == "a{")
      #expect(table.addRule("{a", "", "")?.input == "{a")
      #expect(table.addRule("a{a", "", "")?.input == "a{a")
      #expect(table.addRule("a}", "", "")?.input == "a}")
      #expect(table.addRule("}a", "", "")?.input == "}a")
      #expect(table.addRule("a}a", "", "")?.input == "a}a")
      #expect(table.addRule("a{b}c", "", "")?.input == "a\u{F005}c")
      #expect(table.addRule("a{b}c{d}{e}", "", "")?.input == "a\u{F005}c\u{F006}\u{F007}")
      #expect(table.addRule("}-{", "", "")?.input == "}-{")
      #expect(table.addRule("a{bc", "", "")?.input == "a{bc")

      // This is not a fixed specification, but a current behavior.
      // "{{-}" is treated as a special key.
      #expect(table.addRule("{{-}}", "", "")?.input == "\u{F008}}")
    }
  }

  @Test func deleteSpecialKey() {
    let table = Table()
    #expect(deleteSpecialKeys(table.parseSpecialKey("{!}")) == "")
    #expect(deleteSpecialKeys(table.parseSpecialKey("a{!}")) == "a")
    #expect(deleteSpecialKeys(table.parseSpecialKey("{!}a")) == "a")
    #expect(deleteSpecialKeys(table.parseSpecialKey("{abc}")) == "")
    #expect(deleteSpecialKeys(table.parseSpecialKey("a{bcd}")) == "a")
    #expect(deleteSpecialKeys(table.parseSpecialKey("{abc}d")) == "d")
    #expect(deleteSpecialKeys(table.parseSpecialKey("{!}{abc}d")) == "d")
    #expect(deleteSpecialKeys(table.parseSpecialKey("{!}a{bc}d")) == "ad")
    #expect(deleteSpecialKeys(table.parseSpecialKey("{!}ab{cd}")) == "ab")

    // Invalid patterns
    //   "\u000F" = parsed-"{"
    //   "\u000E" = parsed-"}"
    #expect(deleteSpecialKeys("\u{000F}ab") == "\u{000F}ab")
    #expect(deleteSpecialKeys("ab\u{000E}") == "ab\u{000E}")
    #expect(deleteSpecialKeys("\u{000F}\u{000F}ab\u{000E}") == "")
    #expect(deleteSpecialKeys("\u{000F}ab\u{000E}\u{000E}") == "\u{000E}")
  }

  @Test func tableManager() throws {
    let tableManager = TableManager()
    var tableSet = Set<ObjectIdentifier>()
    var tables: [Table] = []  // keeps the tables alive (identity check)
    let specialRomanjiTable: [Request.SpecialRomanjiTable] = [
      .defaultTable,
      .twelveKeysToHiragana,
      .twelveKeysToHalfwidthascii,
      .flickToHiragana,
      .flickToHalfwidthascii,
      .toggleFlickToHiragana,
      .toggleFlickToHalfwidthascii,
      .godanToHiragana,
      .qwertyMobileToHiragana,
      .qwertyMobileToHalfwidthascii,
      .notouchToHiragana,
      .notouchToHalfwidthascii,
    ]
    let preeditMethod: [Config.PreeditMethod] = [.roman, .kana]
    let punctuationMethod: [Config.PunctuationMethod] = [
      .toutenKuten, .commaPeriod, .toutenPeriod, .commaKuten,
    ]
    let symbolMethod: [Config.SymbolMethod] = [
      .cornerBracketMiddleDot,
      .squareBracketSlash,
      .cornerBracketSlash,
      .squareBracketMiddleDot,
    ]

    for romanji in specialRomanjiTable {
      for preedit in preeditMethod {
        for punctuation in punctuationMethod {
          for symbol in symbolMethod {
            var request = Request()
            request.specialRomanjiTable = romanji
            var config = Config()
            config.preeditMethod = preedit
            config.punctuationMethod = punctuation
            config.symbolMethod = symbol
            let table = try #require(tableManager.getTable(request, config))
            #expect(tableManager.getTable(request, config) === table)
            #expect(!tableSet.contains(ObjectIdentifier(table)))
            tableSet.insert(ObjectIdentifier(table))
            tables.append(table)
          }
        }
      }
    }

    do {
      // b/6788850.
      let kRule = "a\t[A]\n"  // 2 entry rule

      var request = Request()
      request.specialRomanjiTable = .defaultTable
      var config = Config()
      config.preeditMethod = .roman
      config.punctuationMethod = .toutenKuten
      config.symbolMethod = .cornerBracketMiddleDot
      config.customRomanTable = Data(kRule.utf8)
      let table = try #require(tableManager.getTable(request, config))
      #expect(tableManager.getTable(request, config) === table)
      #expect(table.lookUp("a") != nil)
      #expect(table.lookUp("kk") == nil)

      let kRule2 =
        "a\t[A]\n"  // 2 entry rule
        + "kk\t[X]\tk\n"  // 3 entry rule
      config.customRomanTable = Data(kRule2.utf8)
      let table2 = try #require(tableManager.getTable(request, config))
      #expect(tableManager.getTable(request, config) === table2)
      #expect(table2.lookUp("a") != nil)
      #expect(table2.lookUp("kk") != nil)
    }
  }
}
