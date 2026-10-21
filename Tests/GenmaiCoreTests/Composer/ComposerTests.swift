// Port of mozc/src/composer/composer_test.cc (3.35.6354).
//
// Notes:
// - The C++ fixture shares `config_` / `request_` with the composer through
//   shared_ptr, so mutating them after construction affects the composer. Swift
//   stores protobufs by value; the `didSet` observers below forward every
//   mutation to the composer to keep the same behavior.
// - ComposerTestPeer::ApplyTemporaryInputMode is
//   Composer.applyTemporaryInputModeForTesting.
// - ScopedClockMock is replaced with the task-local Clock.withClock.

import Foundation
import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private typealias KeyEvent = Genmai_Commands_KeyEvent

private func kc(_ c: String) -> UInt32 { c.unicodeScalars.first!.value }

@discardableResult
private func insertKey(_ keyString: String, _ composer: inout Composer) -> Bool {
  var key = Genmai_Commands_KeyEvent()
  if !KeyParser.parseKey(keyString, &key) {
    return false
  }
  return composer.insertCharacterKeyEvent(key)
}

@discardableResult
private func insertKeyWithMode(
  _ keyString: String, _ mode: Genmai_Commands_CompositionMode, _ composer: inout Composer
) -> Bool {
  var key = Genmai_Commands_KeyEvent()
  if !KeyParser.parseKey(keyString, &key) {
    return false
  }
  key.mode = mode
  return composer.insertCharacterKeyEvent(key)
}

private func expectSameComposer(_ lhs: Composer, _ rhs: Composer) {
  #expect(lhs.getCursor() == rhs.getCursor())
  #expect(lhs.isNewInput == rhs.isNewInput)
  #expect(lhs.getInputMode() == rhs.getInputMode())
  #expect(lhs.getOutputMode() == rhs.getOutputMode())
  #expect(lhs.getComebackInputMode() == rhs.getComebackInputMode())
  #expect(lhs.shiftedSequenceCount == rhs.shiftedSequenceCount)
  #expect(lhs.sourceText == rhs.sourceText)
  #expect(lhs.maxLength == rhs.maxLength)
  #expect(lhs.getInputFieldType() == rhs.getInputFieldType())

  #expect(lhs.getStringForPreedit() == rhs.getStringForPreedit())
  #expect(lhs.getStringForSubmission() == rhs.getStringForSubmission())
  #expect(lhs.getQueryForConversion() == rhs.getQueryForConversion())
  #expect(lhs.getQueryForPrediction() == rhs.getQueryForPrediction())
}

extension Array where Element == String {
  fileprivate subscript(_ t: TransliterationType) -> String { self[t.rawValue] }
}

private let kYama = "山"
private let kKawa = "川"
private let kSora = "空"

@Suite(.scopedConfigEnvironment) final class ComposerTest {
  var table = Table()
  var config = Genmai_Config_Config() {
    didSet { composer.setConfig(config) }
  }
  var request = Genmai_Commands_Request() {
    didSet { composer.setRequest(request) }
  }
  var composer: Composer

  init() {
    composer = Composer(table, Genmai_Commands_Request(), Genmai_Config_Config())
    CharacterFormManager.getCharacterFormManager().setDefaultRule()
  }


  @Test func reset() throws {
  composer.insertCharacter("mozuku")

  composer.setInputMode(.halfAscii)

  #expect(composer.getOutputMode() == .hiragana)
  composer.setOutputMode(.halfAscii)
  #expect(composer.getOutputMode() == .halfAscii)

  composer.setInputFieldType(.password)
  composer.reset()

  #expect(composer.isEmpty())
  // The input mode remains as the previous mode.
  #expect(composer.getInputMode() == .halfAscii)
  #expect(composer.getInputFieldType() == .password)
  // The output mode should be reset.
  #expect(composer.getOutputMode() == .hiragana)
}

  @Test func resetInputMode() throws {
  composer.insertCharacter("mozuku")

  composer.setInputMode(.fullKatakana)
  composer.setTemporaryInputMode(.halfAscii)
  composer.resetInputMode()

  #expect(!composer.isEmpty())
  #expect(composer.getInputMode() == .fullKatakana)
}

  @Test func empty() throws {
  composer.insertCharacter("mozuku")
  #expect(!composer.isEmpty())

  composer.editErase()
  #expect(composer.isEmpty())
}

  @Test func enableInsert() throws {
  composer.maxLength = 6

  composer.insertCharacter("mozuk")
  #expect(composer.getLength() == 5)

  #expect(composer.enableInsert())
  composer.insertCharacter("u")
  #expect(composer.getLength() == 6)

  #expect(!composer.enableInsert())
  composer.insertCharacter("!")
  #expect(composer.getLength() == 6)

  #expect(composer.getQueryForConversion() == "mozuku")

  composer.backspace()
  #expect(composer.getLength() == 5)
  #expect(composer.enableInsert())
}

  @Test func backSpace() throws {
  composer.insertCharacter("abc")

  composer.backspace()
  #expect(composer.getLength() == 2)
  #expect(composer.getCursor() == 2)
  #expect(composer.getQueryForConversion() == "ab")

  #expect(composer.getQueryForConversion() == "ab")

  composer.moveCursorToBeginning()
  #expect(composer.getCursor() == 0)

  composer.backspace()
  #expect(composer.getLength() == 2)
  #expect(composer.getCursor() == 0)
  #expect(composer.getQueryForConversion() == "ab")

  composer.backspace()
  #expect(composer.getLength() == 2)
  #expect(composer.getCursor() == 0)
  #expect(composer.getQueryForConversion() == "ab")
}

  @Test func outputMode() throws {
  // This behaviour is based on Kotoeri

  table.addRule("a", "あ", "")
  table.addRule("i", "い", "")
  table.addRule("u", "う", "")

  composer.setOutputMode(.hiragana)

  composer.insertCharacter("a")
  composer.insertCharacter("i")
  composer.insertCharacter("u")

  #expect(composer.getStringForPreedit() == "あいう")

  composer.setOutputMode(.fullAscii)
  #expect(composer.getStringForPreedit() == "ａｉｕ")

  composer.insertCharacter("a")
  composer.insertCharacter("i")
  composer.insertCharacter("u")
  #expect(composer.getStringForPreedit() == "ａｉｕあいう")
}

  @Test func outputMode2() throws {
  // This behaviour is based on Kotoeri

  table.addRule("a", "あ", "")
  table.addRule("i", "い", "")
  table.addRule("u", "う", "")

  composer.insertCharacter("a")
  composer.insertCharacter("i")
  composer.insertCharacter("u")

  #expect(composer.getStringForPreedit() == "あいう")

  composer.moveCursorLeft()
  composer.setOutputMode(.fullAscii)
  #expect(composer.getStringForPreedit() == "ａｉｕ")

  composer.insertCharacter("a")
  composer.insertCharacter("i")
  composer.insertCharacter("u")
  #expect(composer.getStringForPreedit() == "ａｉｕあいう")
}

  @Test func getTransliterations() throws {
  table.addRule("a", "あ", "")
  table.addRule("i", "い", "")
  table.addRule("u", "う", "")
  table.addRule("A", "あ", "")
  table.addRule("I", "い", "")
  table.addRule("U", "う", "")
  composer.insertCharacter("a")

  var transliterations = Transliterations()
  composer.getTransliterations(&transliterations)
  #expect(transliterations.count == TransliterationType.numT13nTypes)
  #expect(transliterations[.hiragana] == "あ")
  #expect(transliterations[.fullKatakana] == "ア")
  #expect(transliterations[.halfAscii] == "a")
  #expect(transliterations[.fullAscii] == "ａ")
  #expect(transliterations[.halfKatakana] == "ｱ")

  composer.reset()
  try #require(composer.isEmpty())
  transliterations.removeAll()

  composer.insertCharacter("!")
  composer.getTransliterations(&transliterations)
  #expect(transliterations.count == TransliterationType.numT13nTypes)
  // NOTE(komatsu): The duplication will be handled by the session layer.
  #expect(transliterations[.hiragana] == "！")
  #expect(transliterations[.fullKatakana] == "！")
  #expect(transliterations[.halfAscii] == "!")
  #expect(transliterations[.fullAscii] == "！")
  #expect(transliterations[.halfKatakana] == "!")

  composer.reset()
  try #require(composer.isEmpty())
  transliterations.removeAll()

  composer.insertCharacter("aIu")
  composer.getTransliterations(&transliterations)
  #expect(transliterations.count == TransliterationType.numT13nTypes)
  #expect(transliterations[.hiragana] == "あいう")
  #expect(transliterations[.fullKatakana] == "アイウ")
  #expect(transliterations[.halfAscii] == "aIu")
  #expect(transliterations[.halfAsciiUpper] == "AIU")
  #expect(transliterations[.halfAsciiLower] == "aiu")
  #expect(transliterations[.halfAsciiCapitalized] == "Aiu")
  #expect(transliterations[.fullAscii] == "ａＩｕ")
  #expect(transliterations[.fullAsciiUpper] == "ＡＩＵ")
  #expect(transliterations[.fullAsciiLower] == "ａｉｕ")
  #expect(transliterations[.fullAsciiCapitalized] == "Ａｉｕ")
  #expect(transliterations[.halfKatakana] == "ｱｲｳ")

  // Transliterations for quote marks.  This is a test against
  // http://b/1581367
  composer.reset()
  try #require(composer.isEmpty())
  transliterations.removeAll()

  composer.insertCharacter("'\"`")
  composer.getTransliterations(&transliterations)
  #expect(transliterations[.halfAscii] == "'\"`")
  #expect(transliterations[.fullAscii] == "’”｀")
}

  @Test func getSubTransliterations() throws {
  table.addRule("ka", "か", "")
  table.addRule("n", "ん", "")
  table.addRule("na", "な", "")
  table.addRule("da", "だ", "")

  composer.insertCharacter("kanna")

  var transliterations = Transliterations()
  composer.getSubTransliterations(0, 2, &transliterations)
  #expect(transliterations[.hiragana] == "かん")
  #expect(transliterations[.fullKatakana] == "カン")
  #expect(transliterations[.halfAscii] == "kan")
  #expect(transliterations[.fullAscii] == "ｋａｎ")
  #expect(transliterations[.halfKatakana] == "ｶﾝ")

  transliterations.removeAll()
  composer.getSubTransliterations(1, 1, &transliterations)
  #expect(transliterations[.hiragana] == "ん")
  #expect(transliterations[.fullKatakana] == "ン")
  #expect(transliterations[.halfAscii] == "n")
  #expect(transliterations[.fullAscii] == "ｎ")
  #expect(transliterations[.halfKatakana] == "ﾝ")

  transliterations.removeAll()
  composer.getSubTransliterations(2, 1, &transliterations)
  #expect(transliterations[.hiragana] == "な")
  #expect(transliterations[.fullKatakana] == "ナ")
  #expect(transliterations[.halfAscii] == "na")
  #expect(transliterations[.fullAscii] == "ｎａ")
  #expect(transliterations[.halfKatakana] == "ﾅ")

  // Invalid position
  transliterations.removeAll()
  composer.getSubTransliterations(5, 3, &transliterations)
  #expect(transliterations[.hiragana] == "")
  #expect(transliterations[.fullKatakana] == "")
  #expect(transliterations[.halfAscii] == "")
  #expect(transliterations[.fullAscii] == "")
  #expect(transliterations[.halfKatakana] == "")

  // Invalid size
  transliterations.removeAll()
  composer.getSubTransliterations(0, 999, &transliterations)
  #expect(transliterations[.hiragana] == "かんな")
  #expect(transliterations[.fullKatakana] == "カンナ")
  #expect(transliterations[.halfAscii] == "kanna")
  #expect(transliterations[.fullAscii] == "ｋａｎｎａ")
  #expect(transliterations[.halfKatakana] == "ｶﾝﾅ")

  // Dakuon case
  transliterations.removeAll()
  composer.editErase()
  composer.insertCharacter("dankann")
  composer.getSubTransliterations(0, 3, &transliterations)
  #expect(transliterations[.hiragana] == "だんか")
  #expect(transliterations[.fullKatakana] == "ダンカ")
  #expect(transliterations[.halfAscii] == "danka")
  #expect(transliterations[.fullAscii] == "ｄａｎｋａ")
  #expect(transliterations[.halfKatakana] == "ﾀﾞﾝｶ")
}

  @Test func getStringFunctions() throws {
  table.addRule("ka", "か", "")
  table.addRule("n", "ん", "")
  table.addRule("na", "な", "")
  table.addRule("sa", "さ", "")

  // Query: "!kan"
  composer.insertCharacter("!kan")
  #expect(composer.getStringForPreedit() == "！かｎ")
  #expect(composer.getStringForSubmission() == "！かｎ")
  #expect(composer.getQueryForConversion() == "!かん")
  #expect(composer.getQueryForPrediction() == "!か")

  // Query: "kas"
  composer.editErase()
  composer.insertCharacter("kas")

  #expect(composer.getStringForPreedit() == "かｓ")
  #expect(composer.getStringForSubmission() == "かｓ")
  // Pending chars should remain.  This is a test against
  // http://b/1799399
  #expect(composer.getQueryForConversion() == "かs")
  #expect(composer.getQueryForPrediction() == "か")

  // Query: "s"
  composer.editErase()
  composer.insertCharacter("s")

  #expect(composer.getStringForPreedit() == "ｓ")
  #expect(composer.getStringForSubmission() == "ｓ")
  #expect(composer.getQueryForConversion() == "s")
  #expect(composer.getQueryForPrediction() == "s")

  // Query: "sk"
  composer.editErase()
  composer.insertCharacter("sk")

  #expect(composer.getStringForPreedit() == "ｓｋ")
  #expect(composer.getStringForSubmission() == "ｓｋ")
  #expect(composer.getQueryForConversion() == "sk")
  #expect(composer.getQueryForPrediction() == "sk")
}

  @Test func getQueryForPredictionHalfAscii() throws {
  // Dummy setup of romanji table.
  table.addRule("he", "へ", "")
  table.addRule("ll", "っｌ", "")
  table.addRule("lo", "ろ", "")

  // Switch to Half-Latin input mode.
  composer.setInputMode(.halfAscii)

  do {
    let kInput = "hello"
    composer.insertCharacter(kInput)
    #expect(composer.getQueryForPrediction() == kInput)
  }
  composer.editErase()
  do {
    let kInput = "hello!"
    composer.insertCharacter(kInput)
    #expect(composer.getQueryForPrediction() == kInput)
  }
}

  @Test func getQueryForPredictionFullAscii() throws {
  // Dummy setup of romanji table.
  table.addRule("he", "へ", "")
  table.addRule("ll", "っｌ", "")
  table.addRule("lo", "ろ", "")

  // Switch to Full-Latin input mode.
  composer.setInputMode(.fullAscii)

  do {
    composer.insertCharacter("ｈｅｌｌｏ")
    #expect(composer.getQueryForPrediction() == "hello")
  }
  composer.editErase()
  do {
    composer.insertCharacter("ｈｅｌｌｏ！")
    #expect(composer.getQueryForPrediction() == "hello!")
  }
}

  @Test func getQueriesForPredictionRoman() throws {
  table.addRule("u", "う", "")
  table.addRule("ss", "っ", "s")
  table.addRule("sa", "さ", "")
  table.addRule("si", "し", "")
  table.addRule("su", "す", "")
  table.addRule("se", "せ", "")
  table.addRule("so", "そ", "")

  do {
    composer.editErase()
    composer.insertCharacter("us")
    // auto = std::pair<std::string, absl::btree_set<std::string>>
    let (base, expanded) = composer.getQueriesForPrediction()
    _ = composer.getStringForPreedit()
    #expect(base == "う")
    #expect(expanded.count == 7)
    // We can't use EXPECT_NE for iterator
    #expect(expanded.contains("s"))
    #expect(expanded.contains("っ"))
    #expect(expanded.contains("さ"))
    #expect(expanded.contains("し"))
    #expect(expanded.contains("す"))
    #expect(expanded.contains("せ"))
    #expect(expanded.contains("そ"))
  }
}

  @Test func getQueriesForPredictionMobile() throws {
  table.addRule("_", "", "い")
  table.addRule("い*", "", "ぃ")
  table.addRule("ぃ*", "", "い")
  table.addRule("$", "", "と")
  table.addRule("と*", "", "ど")
  table.addRule("ど*", "", "と")
  table.addRule("x", "", "つ")
  table.addRule("つ*", "", "っ")
  table.addRule("っ*", "", "づ")
  table.addRule("づ*", "", "つ")

  do {
    composer.editErase()
    composer.insertCharacter("_$")
    // auto = std::pair<std::string, absl::btree_set<std::string>>
    let (base, expanded) = composer.getQueriesForPrediction()
    _ = composer.getStringForPreedit()
    #expect(base == "い")
    #expect(expanded.count == 2)
    #expect(expanded.contains("と"))
    #expect(expanded.contains("ど"))
  }
  do {
    composer.editErase()
    composer.insertCharacter("_$*")
    // auto = std::pair<std::string, absl::btree_set<std::string>>
    let (base, expanded) = composer.getQueriesForPrediction()
    _ = composer.getStringForPreedit()
    #expect(base == "い")
    #expect(expanded.count == 1)
    #expect(expanded.contains("ど"))
  }
  do {
    composer.editErase()
    composer.insertCharacter("_x*")
    // auto = std::pair<std::string, absl::btree_set<std::string>>
    let (base, expanded) = composer.getQueriesForPrediction()
    _ = composer.getStringForPreedit()
    #expect(base == "い")
    #expect(expanded.count == 1)
    #expect(expanded.contains("っ"))
  }
}

// TODO(yukiokamoto): This unit test currently fails due to a crash. (Please
// note that this crash could only occur in a debug build.)
// Once another issue in b/277163340 that an input "[][]" is not converted
// properly is fixed, uncomment the following test.
  @Test func issue277163340() throws {
  // Test against http://b/277163340.
  // Before the fix, unexpected input was passed to
  // RemoveExpandedCharsForModifier() in the following test due to another
  // bug in composer/char_chunk.cc and it
  // caused the process to crash.
  table.addRuleWithAttributes("[", "", "", .noTransliteration)
  var key = Genmai_Commands_KeyEvent()
  key.keyString = "[]"
  key.inputStyle = .asIs
  composer.insertCharacterKeyEvent(key)
  composer.insertCharacterKeyEvent(key)
  composer.insertCommandCharacter(.stopKeyToggling)
  // auto = std::pair<std::string, absl::btree_set<std::string>>
  let (base, expanded) = composer.getQueriesForPrediction()

  // Never reached here due to the crash before the fix for b/277163340.
  #expect(base == "[][]")
}

// Emulates tapping "[]" key twice without enough internval.
  @Test func doubleTapSquareBracketPairKey() throws {
  var key = Genmai_Commands_KeyEvent()
  table.addRuleWithAttributes("[", "", "", .noTransliteration)

  key.keyString = "[]"
  key.inputStyle = .asIs
  composer.insertCharacterKeyEvent(key)
  composer.insertCharacterKeyEvent(key)
  #expect(composer.getStringForPreedit() == "[][]")
}

// Emulates tapping "[" key twice without enough internval.
  @Test func doubleTapOpenSquareBracketKey() throws {
  var key = Genmai_Commands_KeyEvent()
  table.addRuleWithAttributes("[", "", "", .noTransliteration)

  key.keyString = "["
  key.inputStyle = .asIs
  composer.insertCharacterKeyEvent(key)
  composer.insertCharacterKeyEvent(key)
  #expect(composer.getStringForPreedit() == "[[")
}

// Emulates tapping "[]" key twice with enough internval.
  @Test func doubleTapSquareBracketPairKeyWithInterval() throws {
  var key = Genmai_Commands_KeyEvent()
  table.addRuleWithAttributes("[", "", "", .noTransliteration)

  key.keyString = "[]"
  key.inputStyle = .asIs
  composer.insertCharacterKeyEvent(key)
  composer.insertCommandCharacter(.stopKeyToggling)
  composer.insertCharacterKeyEvent(key)
  #expect(composer.getStringForPreedit() == "[][]")
}

  @Test func getStringFunctionsForN() throws {
  table.addRule("a", "[A]", "")
  table.addRule("n", "[N]", "")
  table.addRule("nn", "[N]", "")
  table.addRule("na", "[NA]", "")
  table.addRule("nya", "[NYA]", "")
  table.addRule("ya", "[YA]", "")
  table.addRule("ka", "[KA]", "")

  composer.insertCharacter("nynyan")
  #expect(composer.getStringForPreedit() == "ｎｙ［ＮＹＡ］ｎ")
  #expect(composer.getStringForSubmission() == "ｎｙ［ＮＹＡ］ｎ")
  #expect(composer.getQueryForConversion() == "ny[NYA][N]")
  #expect(composer.getQueryForPrediction() == "ny[NYA]")

  composer.insertCharacter("ka")
  #expect(composer.getQueryForConversion() == "ny[NYA][N][KA]")
  #expect(composer.getQueryForPrediction() == "ny[NYA][N][KA]")
}

  @Test func getStringFunctionsInputFieldType() throws {
  struct TestData {
    let field_type: Genmai_Commands_Context.InputFieldType
    let ascii_expected: Bool
  }
  let test_data_list = [
    TestData(field_type: .normal, ascii_expected: false),
    TestData(field_type: .number, ascii_expected: true),
    TestData(field_type: .password, ascii_expected: true),
    TestData(field_type: .tel, ascii_expected: true),
  ]

  composer.setInputMode(.hiragana)
  for test_data_index in 0..<test_data_list.count {
    let test_data = test_data_list[test_data_index]
    composer.setInputFieldType(test_data.field_type)
    var key = ""
    for c in UInt8(0x20)...UInt8(0x7E) {
      key = String(UnicodeScalar(c))
      composer.editErase()
      composer.insertCharacter(key)
      if (test_data.ascii_expected) {
        #expect(composer.getStringForPreedit() == key)
        #expect(composer.getStringForSubmission() == key)
      } else {
        // Expected result is FULL_WIDTH form.
        // Typically the result is a full-width form of the key,
        // but some characters are not.
        // So here we checks only the character form.
        #expect(Util.getFormType(composer.getStringForPreedit()) == .fullWidth)
        #expect(Util.getFormType(composer.getStringForSubmission()) == .fullWidth)
      }
    }
  }
}

  @Test func insertCommandCharacter() throws {
  table.addRule("{<}", "REWIND", "")
  table.addRule("{!}", "STOP", "")

  composer.setInputMode(.halfAscii)

  composer.insertCommandCharacter(.rewind)
  #expect(composer.getStringForPreedit() == "REWIND")

  composer.reset()
  composer.insertCommandCharacter(.stopKeyToggling)
  #expect(composer.getStringForPreedit() == "STOP")
}

  @Test func insertCharacterKeyEvent() throws {
  var key = Genmai_Commands_KeyEvent()
  table.addRule("a", "あ", "")

  key.keyCode = kc("a")
  composer.insertCharacterKeyEvent(key)

  #expect(composer.getStringForPreedit() == "あ")

  // Half width "A" will be inserted.
  key.keyCode = kc("A")
  composer.insertCharacterKeyEvent(key)

  #expect(composer.getStringForPreedit() == "あA")

  // Half width "a" will be inserted.
  key.keyCode = kc("a")
  composer.insertCharacterKeyEvent(key)

  #expect(composer.getStringForPreedit() == "あAa")

  // Reset() should revert the previous input mode (Hiragana).
  composer.reset()

  key.keyCode = kc("a")
  composer.insertCharacterKeyEvent(key)
  #expect(composer.getStringForPreedit() == "あ")

  // Typing "A" temporarily switch the input mode.  The input mode
  // should be reverted back after reset.
  composer.setInputMode(.fullKatakana)
  key.keyCode = kc("a")
  composer.insertCharacterKeyEvent(key)
  #expect(composer.getStringForPreedit() == "あア")

  key.keyCode = kc("A")
  composer.insertCharacterKeyEvent(key)
  #expect(composer.getStringForPreedit() == "あアA")

  // Reset() should revert the previous input mode (Katakana).
  composer.reset()

  key.keyCode = kc("a")
  composer.insertCharacterKeyEvent(key)
  #expect(composer.getStringForPreedit() == "ア")
}


  @Test func insertCharacterKeyEventWithCodepointKeyCode() throws {
  var key = Genmai_Commands_KeyEvent()

  // Input "山" as key_code.
  key.keyCode = 0x5C71  // U+5C71 = "山"
  composer.insertCharacterKeyEvent(key)

  #expect(composer.getStringForPreedit() == kYama)

  // Input "山" as key_code which is converted to "川".
  table.addRule(kYama, kKawa, "")
  composer.reset()
  composer.insertCharacterKeyEvent(key)
  #expect(composer.getStringForPreedit() == kKawa)

  // Input ("山", "空") as (key_code, key_string) which is treated as "空".
  key.keyString = kSora
  composer.reset()
  composer.insertCharacterKeyEvent(key)
  #expect(composer.getStringForPreedit() == kSora)
}

  @Test func insertCharacterKeyEventWithoutKeyCode() throws {
  var key = Genmai_Commands_KeyEvent()

  // Input "山" as key_string.  key_code is empty.
  key.keyString = kYama
  composer.insertCharacterKeyEvent(key)
  #expect(!key.hasKeyCode)

  #expect(composer.getStringForPreedit() == kYama)

  var transliterations = Transliterations()
  composer.getTransliterations(&transliterations)
  #expect(transliterations[.hiragana] == kYama)
  #expect(transliterations[.halfAscii] == kYama)
}

  @Test func insertCharacterKeyEventWithAsIs() throws {
  var key = Genmai_Commands_KeyEvent()
  table.addRule("a", "あ", "")
  table.addRule("-", "ー", "")

  key.keyCode = kc("a")
  composer.insertCharacterKeyEvent(key)

  #expect(composer.getStringForPreedit() == "あ")

  // Full width "０" will be inserted.
  key.keyCode = kc("0")
  key.keyString = "0"
  composer.insertCharacterKeyEvent(key)

  #expect(composer.getStringForPreedit() == "あ０")

  // Half width "0" will be inserted.
  key.keyCode = kc("0")
  key.keyString = "0"
  key.inputStyle = .asIs
  composer.insertCharacterKeyEvent(key)

  #expect(composer.getStringForPreedit() == "あ０0")

  // Full width "0" will be inserted.
  key.keyCode = kc("0")
  key.keyString = "0"
  key.inputStyle = .followMode
  composer.insertCharacterKeyEvent(key)

  #expect(composer.getStringForPreedit() == "あ０0０")

  // Half width "-" will be inserted.
  key.keyCode = kc("-")
  key.keyString = "-"
  key.inputStyle = .asIs
  composer.insertCharacterKeyEvent(key)

  #expect(composer.getStringForPreedit() == "あ０0０-")

  // Full width "−" (U+2212) will be inserted.
  key.keyCode = kc("-")
  key.keyString = "−"
  key.inputStyle = .followMode
  composer.insertCharacterKeyEvent(key)

  #expect(composer.getStringForPreedit() == "あ０0０-−")  // The last hyphen is U+2212.
}

  @Test func insertCharacterKeyEventWithInputMode() throws {
  table.addRule("a", "あ", "")
  table.addRule("i", "い", "")
  table.addRule("u", "う", "")

  do {
    // "a" → "あ" (Hiragana)
    #expect(insertKeyWithMode("a", .hiragana, &composer))
    #expect(composer.getStringForPreedit() == "あ")
    #expect(composer.getInputMode() == .hiragana)

    // "aI" → "あI" (Alphanumeric)
    #expect(insertKeyWithMode("I", .hiragana, &composer))
    #expect(composer.getStringForPreedit() == "あI")
    #expect(composer.getInputMode() == .halfAscii)

    // "u" → "あIu" (Alphanumeric)
    #expect(insertKeyWithMode("u", .halfAscii, &composer))
    #expect(composer.getStringForPreedit() == "あIu")
    #expect(composer.getInputMode() == .halfAscii)

    // [shift] → "あIu" (Hiragana)
    #expect(insertKeyWithMode("Shift", .halfAscii, &composer))
    #expect(composer.getStringForPreedit() == "あIu")
    #expect(composer.getInputMode() == .hiragana)

    // "u" → "あIuう" (Hiragana)
    #expect(insertKeyWithMode("u", .hiragana, &composer))
    #expect(composer.getStringForPreedit() == "あIuう")
    #expect(composer.getInputMode() == .hiragana)
  }

  composer = Composer(table, request, config)

  do {
    // "a" → "あ" (Hiragana)
    #expect(insertKeyWithMode("a", .hiragana, &composer))
    #expect(composer.getStringForPreedit() == "あ")
    #expect(composer.getInputMode() == .hiragana)

    // "i" (Katakana) → "あイ" (Katakana)
    #expect(insertKeyWithMode("i", .fullKatakana, &composer))
    #expect(composer.getStringForPreedit() == "あイ")
    #expect(composer.getInputMode() == .fullKatakana)

    // SetInputMode(Alphanumeric) → "あイ" (Alphanumeric)
    composer.setInputMode(.halfAscii)
    #expect(composer.getInputMode() == .halfAscii)

    // [shift] → "あイ" (Alphanumeric) - Nothing happens.
    #expect(insertKeyWithMode("Shift", .halfAscii, &composer))
    #expect(composer.getStringForPreedit() == "あイ")
    #expect(composer.getInputMode() == .halfAscii)

    // "U" → "あイ" (Alphanumeric)
    #expect(insertKeyWithMode("U", .halfAscii, &composer))
    #expect(composer.getStringForPreedit() == "あイU")
    #expect(composer.getInputMode() == .halfAscii)

    // [shift] → "あイU" (Alphanumeric) - Nothing happens.
    #expect(insertKeyWithMode("Shift", .halfAscii, &composer))
    #expect(composer.getStringForPreedit() == "あイU")
    #expect(composer.getInputMode() == .halfAscii)
  }
}

  @Test func applyTemporaryInputMode() throws {
  let kCapsLocked = true
  let kCapsUnlocked = false


  table.addRule("a", "あ", "")
  composer.setInputMode(.hiragana)

  // Since handlings of continuous shifted input differ,
  // test cases differ between ASCII_INPUT_MODE and KATAKANA_INPUT_MODE

  do {  // ASCII_INPUT_MODE (w/o CapsLock)
    config.shiftKeyModeSwitch = .asciiInputMode

    // pair<input, use_temporary_input_mode>
    let kTestDataAscii: [(String, Bool)] = [
        ("a", false),  ("A", true),
        ("a", true),   ("a", true),
        ("A", true),   ("A", true),
        ("a", false),  ("A", true),
        ("A", true),   ("A", true),
        ("a", false),  ("A", true),
        (".", true),   ("a", true),
        ("A", true),   ("A", true),
        (".", true),   ("a", true),
        ("あ", false), ("a", false),
    ]

    for i in 0..<kTestDataAscii.count {
      composer.applyTemporaryInputModeForTesting(kTestDataAscii[i].0, kCapsUnlocked)

      let expected: TransliterationType =
          kTestDataAscii[i].1 ? .halfAscii
                                   : .hiragana

      #expect(expected == composer.getInputMode(), "index=\(i)")
      #expect(.hiragana == composer.getComebackInputMode(), "index=\(i)")
    }
  }

  do {  // ASCII_INPUT_MODE (w/ CapsLock)
    config.shiftKeyModeSwitch = .asciiInputMode

    // pair<input, use_temporary_input_mode>
    let kTestDataAscii: [(String, Bool)] = [
        ("A", false),  ("a", true),
        ("A", true),   ("A", true),
        ("a", true),   ("a", true),
        ("A", false),  ("a", true),
        ("a", true),   ("a", true),
        ("A", false),  ("a", true),
        (".", true),   ("A", true),
        ("a", true),   ("a", true),
        (".", true),   ("A", true),
        ("あ", false), ("A", false),
    ]

    for i in 0..<kTestDataAscii.count {
      composer.applyTemporaryInputModeForTesting(kTestDataAscii[i].0, kCapsLocked)

      let expected: TransliterationType =
          kTestDataAscii[i].1 ? .halfAscii
                                   : .hiragana

      #expect(expected == composer.getInputMode(), "index=\(i)")
      #expect(.hiragana == composer.getComebackInputMode(), "index=\(i)")
    }
  }

  do {  // KATAKANA_INPUT_MODE (w/o CapsLock)
    config.shiftKeyModeSwitch = .katakanaInputMode

    // pair<input, use_temporary_input_mode>
    let kTestDataKatakana: [(String, Bool)] = [
        ("a", false),  ("A", true),
        ("a", false),  ("a", false),
        ("A", true),   ("A", true),
        ("a", false),  ("A", true),
        ("A", true),   ("A", true),
        ("a", false),  ("A", true),
        (".", true),   ("a", false),
        ("A", true),   ("A", true),
        (".", true),   ("a", false),
        ("あ", false), ("a", false),
    ]

    for i in 0..<kTestDataKatakana.count {
      composer.applyTemporaryInputModeForTesting(kTestDataKatakana[i].0, kCapsUnlocked)

      let expected: TransliterationType =
          kTestDataKatakana[i].1 ? .fullKatakana
                                      : .hiragana

      #expect(expected == composer.getInputMode(), "index=\(i)")
      #expect(.hiragana == composer.getComebackInputMode(), "index=\(i)")
    }
  }

  do {  // KATAKANA_INPUT_MODE (w/ CapsLock)
    config.shiftKeyModeSwitch = .katakanaInputMode

    // pair<input, use_temporary_input_mode>
    let kTestDataKatakana: [(String, Bool)] = [
        ("A", false),  ("a", true),
        ("A", false),  ("A", false),
        ("a", true),   ("a", true),
        ("A", false),  ("a", true),
        ("a", true),   ("a", true),
        ("A", false),  ("a", true),
        (".", true),   ("A", false),
        ("a", true),   ("a", true),
        (".", true),   ("A", false),
        ("あ", false), ("A", false),
    ]

    for i in 0..<kTestDataKatakana.count {
      composer.applyTemporaryInputModeForTesting(kTestDataKatakana[i].0, kCapsLocked)

      let expected: TransliterationType =
          kTestDataKatakana[i].1 ? .fullKatakana
                                      : .hiragana

      #expect(expected == composer.getInputMode(), "index=\(i)")
      #expect(.hiragana == composer.getComebackInputMode(), "index=\(i)")
    }
  }
}

  @Test func fullWidthCharRulesb31444698() throws {
  // Construct the following romaji table:
  //
  // 1<tab><tab>{?}あ<tab>NewChunk NoTransliteration
  // {?}あ1<tab><tab>{?}い<tab>
  // か<tab><tab>{?}か<tab>NewChunk NoTransliteration
  // {?}かか<tab><tab>{?}き<tab>
  let kAttrs: TableAttributes = [.newChunk, .noTransliteration]
  table.addRuleWithAttributes("1", "", "{?}あ", kAttrs)
  table.addRule("{?}あ1", "", "{?}い")
  table.addRuleWithAttributes("か", "", "{?}か", kAttrs)
  table.addRule("{?}かか", "", "{?}き")

  // Test if "11" is transliterated to "い"
  try #require(insertKeyWithMode("1", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "あ")
  try #require(insertKeyWithMode("1", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "い")

  composer.reset()

  // b/31444698.  Test if "かか" is transliterated to "き"
  try #require(insertKeyWithMode("か", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "か")
  try #require(insertKeyWithMode("か", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "き")
}

  @Test func copy() throws {
  table.addRule("a", "あ", "")
  table.addRule("n", "ん", "")
  table.addRule("na", "な", "")

  do {
    // SCOPED_TRACE("Precomposition")

    #expect(composer.getStringForSubmission() == "")

    let dest = composer
    expectSameComposer(composer, dest)
  }

  do {
    // SCOPED_TRACE("Composition")

    composer.insertCharacter("a")
    composer.insertCharacter("n")
    #expect(composer.getStringForSubmission() == "あｎ")

    let dest = composer
    expectSameComposer(composer, dest)
  }

  do {
    // SCOPED_TRACE("Conversion")

    #expect(composer.getQueryForConversion() == "あん")

    let dest = composer
    expectSameComposer(composer, dest)
  }

  do {
    // SCOPED_TRACE("Composition with temporary input mode")

    composer.reset()
    insertKey("A", &composer)
    insertKey("a", &composer)
    insertKey("A", &composer)
    insertKey("A", &composer)
    insertKey("a", &composer)
    #expect(composer.getStringForSubmission() == "AaAAあ")

    let dest = composer
    expectSameComposer(composer, dest)
  }

  do {
    // SCOPED_TRACE("Composition with password mode")

    composer.reset()
    composer.setInputFieldType(.password)
    composer.setInputMode(.halfAscii)
    composer.setOutputMode(.halfAscii)
    composer.insertCharacter("M")
    #expect(composer.getStringForSubmission() == "M")

    let dest = composer
    expectSameComposer(composer, dest)
  }
  }

  @Test func shiftKeyOperation() throws {
  table.addRule("a", "あ", "")

  do {  // Basic feature.
    composer.reset()
    insertKey("a", &composer);  // "あ"
    insertKey("A", &composer);  // "あA"
    insertKey("a", &composer);  // "あAa"
    // Shift reverts the input mode to Hiragana.
    insertKey("Shift", &composer)
    insertKey("a", &composer);  // "あAaあ"
    // Shift does nothing because the input mode has already been reverted.
    insertKey("Shift", &composer)
    insertKey("a", &composer);  // "あAaああ"

    #expect(composer.getStringForPreedit() == "あAaああ")
  }

  do {  // Revert back to the previous input mode.
    composer.setInputMode(.fullKatakana)
    composer.reset()
    insertKey("a", &composer);  // "ア"
    insertKey("A", &composer);  // "アA"
    insertKey("a", &composer);  // "アAa"
    // Shift reverts the input mode to Hiragana.
    insertKey("Shift", &composer)
    insertKey("a", &composer);  // "アAaア"
    // Shift does nothing because the input mode has already been reverted.
    insertKey("Shift", &composer)
    insertKey("a", &composer);  // "アAaアア"

    #expect(composer.getStringForPreedit() == "アAaアア")
    #expect(composer.getInputMode() == .fullKatakana)
  }

  do {  // Multiple shifted characters
    composer.setInputMode(.hiragana)
    composer.reset()
    // Sequential shfited keys change the behavior of the next
    // non-shifted key.  "AAaa" Should become "AAああ", "Aaa" should
    // become "Aaa".
    insertKey("A", &composer);  // "A"
    insertKey("A", &composer);  // "AA"
    insertKey("a", &composer);  // "AAあ"
    insertKey("A", &composer);  // "AAあA"
    insertKey("a", &composer);  // "AAあAa"

    #expect(composer.getStringForPreedit() == "AAあAa")
  }

  do {  // Multiple shifted characters #2
    composer.setInputMode(.hiragana)
    composer.reset()
    insertKey("D", &composer);  // "D"
    insertKey("&", &composer);  // "D&"
    insertKey("D", &composer);  // "D&D"
    insertKey("2", &composer);  // "D&D2"
    insertKey("a", &composer);  // "D&D2a"

    #expect(composer.getStringForPreedit() == "D&D2a")
  }

  do {  // Full-witdh alphanumeric
    composer.setInputMode(.fullAscii)
    composer.reset()
    insertKey("A", &composer);  // "Ａ"
    insertKey("a", &composer);  // "Ａａ"

    #expect(composer.getStringForPreedit() == "Ａａ")
  }

  do {  // Half-witdh alphanumeric
    composer.setInputMode(.halfAscii)
    composer.reset()
    insertKey("A", &composer);  // "A"
    insertKey("a", &composer);  // "Aa"

    #expect(composer.getStringForPreedit() == "Aa")
  }
}

  @Test func shiftKeyOperationForKatakana() throws {
  config.shiftKeyModeSwitch = .katakanaInputMode
  table.initializeWithRequestAndConfig(request, config)
  composer.reset()
  composer.setInputMode(.hiragana)
  insertKey("K", &composer)
  #expect(composer.getInputMode() == .fullKatakana)
  insertKey("A", &composer)
  #expect(composer.getInputMode() == .fullKatakana)
  insertKey("T", &composer)
  #expect(composer.getInputMode() == .fullKatakana)
  insertKey("a", &composer)
  // See the below comment.
  // EXPECT_EQ(composer.getInputMode(), .fullKatakana)
  #expect(composer.getInputMode() == .hiragana)
  insertKey("k", &composer)
  #expect(composer.getInputMode() == .hiragana)
  insertKey("A", &composer)
  #expect(composer.getInputMode() == .fullKatakana)
  insertKey("n", &composer)
  #expect(composer.getInputMode() == .hiragana)
  insertKey("a", &composer)
  #expect(composer.getInputMode() == .hiragana)

  // NOTE(komatsu): "KATakAna" is converted to "カＴあｋアな" rather
  // than "カタカな".  This is a different behavior from Kotoeri due
  // to avoid complecated implementation.  Unless this is a problem
  // for users, this difference probably remains.
  //
  // EXPECT_EQ(composer.getStringForPreedit(), "カタカな")

  #expect(composer.getStringForPreedit() == "カＴあｋアな")
}

  @Test func autoSwitchCompositionModeEnabled() throws {
  config.preeditMethod = .roman
  config.autoSwitchCompositionMode = true

  table.initializeWithRequestAndConfig(request, config)

  do {  // http
    insertKey("h", &composer)
    insertKey("t", &composer)
    insertKey("t", &composer)
    #expect(composer.getInputMode() == .hiragana)
    insertKey("p", &composer)

    #expect(composer.getStringForPreedit() == "http")
    #expect(composer.getInputMode() == .halfAscii)

    composer.reset()
    #expect(composer.getInputMode() == .hiragana)
  }

  composer = Composer(table, request, config)

  do {  // google
    insertKey("g", &composer)
    insertKey("o", &composer)
    insertKey("o", &composer)
    insertKey("g", &composer)
    insertKey("l", &composer)
    #expect(composer.getInputMode() == .hiragana)
    insertKey("e", &composer)
    #expect(composer.getInputMode() == .hiragana)
    #expect(composer.getStringForPreedit() == "google")

    insertKey("a", &composer)
    #expect(composer.getInputMode() == .hiragana)
    #expect(composer.getStringForPreedit() == "googleあ")

    composer.reset()
    #expect(composer.getInputMode() == .hiragana)
  }

  do {  // google in full-width alphanumeric mode.
    composer.setInputMode(.fullAscii)
    insertKey("g", &composer)
    insertKey("o", &composer)
    insertKey("o", &composer)
    insertKey("g", &composer)
    insertKey("l", &composer)
    #expect(composer.getInputMode() == .fullAscii)
    insertKey("e", &composer)
    #expect(composer.getInputMode() == .fullAscii)

    #expect(composer.getStringForPreedit() == "ｇｏｏｇｌｅ")

    insertKey("a", &composer)
    #expect(composer.getInputMode() == .fullAscii)
    #expect(composer.getStringForPreedit() == "ｇｏｏｇｌｅａ")

    composer.reset()
    #expect(composer.getInputMode() == .fullAscii)
    // Reset to Hiragana mode
    composer.setInputMode(.hiragana)
  }

  do {  // Google
    insertKey("G", &composer)
    #expect(composer.getInputMode() == .halfAscii)
    insertKey("o", &composer)
    insertKey("o", &composer)
    insertKey("g", &composer)
    insertKey("l", &composer)
    #expect(composer.getInputMode() == .halfAscii)
    insertKey("e", &composer)
    #expect(composer.getInputMode() == .halfAscii)
    #expect(composer.getStringForPreedit() == "Google")

    insertKey("a", &composer)
    #expect(composer.getInputMode() == .halfAscii)
    #expect(composer.getStringForPreedit() == "Googlea")

    composer.reset()
    #expect(composer.getInputMode() == .hiragana)
  }

  config.shiftKeyModeSwitch = .off
  composer = Composer(table, request, config)

  do {  // Google
    insertKey("G", &composer)
    insertKey("o", &composer)
    insertKey("o", &composer)
    insertKey("g", &composer)
    insertKey("l", &composer)
    #expect(composer.getInputMode() == .hiragana)
    insertKey("e", &composer)
    #expect(composer.getInputMode() == .hiragana)
    #expect(composer.getStringForPreedit() == "Google")

    insertKey("a", &composer)
    #expect(composer.getInputMode() == .hiragana)
    #expect(composer.getStringForPreedit() == "Googleあ")

    composer.reset()
    #expect(composer.getInputMode() == .hiragana)
  }
}

  @Test func autoSwitchCompositionModeDisabled() throws {
  config.preeditMethod = .roman
  config.autoSwitchCompositionMode = false

  table.initializeWithRequestAndConfig(request, config)

  var key = Genmai_Commands_KeyEvent()

  // Roman
  key.keyCode = kc("h")
  composer.insertCharacterKeyEvent(key)

  key.keyCode = kc("t")
  composer.insertCharacterKeyEvent(key)

  key.keyCode = kc("t")
  composer.insertCharacterKeyEvent(key)

  key.keyCode = kc("p")
  composer.insertCharacterKeyEvent(key)

  key.keyCode = kc(":")
  composer.insertCharacterKeyEvent(key)

  key.keyCode = kc("/")
  composer.insertCharacterKeyEvent(key)

  key.keyCode = kc("/")
  composer.insertCharacterKeyEvent(key)

  #expect(composer.getStringForPreedit() == "ｈっｔｐ：・・")
}

  @Test func autoSwitchCompositionModeKana() throws {
  config.preeditMethod = .kana
  config.autoSwitchCompositionMode = true

  table.initializeWithRequestAndConfig(request, config)

  var key = Genmai_Commands_KeyEvent()

  // Kana
  key.keyCode = kc("h")
  composer.insertCharacterKeyEvent(key)

  key.keyCode = kc("t")
  composer.insertCharacterKeyEvent(key)

  key.keyCode = kc("t")
  composer.insertCharacterKeyEvent(key)

  key.keyCode = kc("p")
  composer.insertCharacterKeyEvent(key)

  key.keyCode = kc(":")
  composer.insertCharacterKeyEvent(key)

  key.keyCode = kc("/")
  composer.insertCharacterKeyEvent(key)

  key.keyCode = kc("/")
  composer.insertCharacterKeyEvent(key)

  #expect(composer.getStringForPreedit() == "ｈっｔｐ：・・")
}

  @Test func kanaPrediction() throws {
  composer.insertCharacterKeyAndPreedit("t", "か")
  #expect(composer.getQueryForPrediction() == "か")

  composer.insertCharacterKeyAndPreedit("\\", "ー")
  #expect(composer.getQueryForPrediction() == "かー")

  composer.insertCharacterKeyAndPreedit(",", "、")
  #expect(composer.getQueryForPrediction() == "かー、")
}

  @Test func kanaTransliteration() throws {
  table.addRule("く゛", "ぐ", "")
  composer.insertCharacterKeyAndPreedit("h", "く")
  composer.insertCharacterKeyAndPreedit("e", "い")
  composer.insertCharacterKeyAndPreedit("l", "り")
  composer.insertCharacterKeyAndPreedit("l", "り")
  composer.insertCharacterKeyAndPreedit("o", "ら")

  #expect(composer.getStringForPreedit() == "くいりりら")

  var transliterations = Transliterations()
  composer.getTransliterations(&transliterations)
  #expect(transliterations.count == TransliterationType.numT13nTypes)
  #expect(transliterations[.halfAscii] == "hello")
}

  @Test func setOutputMode() throws {
  table.addRule("mo", "も", "")
  table.addRule("zu", "ず", "")

  composer.insertCharacter("m")
  composer.insertCharacter("o")
  composer.insertCharacter("z")
  composer.insertCharacter("u")

  #expect(composer.getStringForPreedit() == "もず")
  #expect(composer.getCursor() == 2)

  composer.setOutputMode(.halfAscii)
  #expect(composer.getStringForPreedit() == "mozu")
  #expect(composer.getCursor() == 4)

  composer.setOutputMode(.halfKatakana)
  #expect(composer.getStringForPreedit() == "ﾓｽﾞ")
  #expect(composer.getCursor() == 3)
}

  @Test func updateInputMode() throws {
  table.addRule("a", "あ", "")
  table.addRule("i", "い", "")

  insertKey("A", &composer)
  #expect(composer.getInputMode() == .halfAscii)

  insertKey("I", &composer)
  #expect(composer.getInputMode() == .halfAscii)

  insertKey("a", &composer)
  #expect(composer.getInputMode() == .hiragana)

  insertKey("i", &composer)
  #expect(composer.getInputMode() == .hiragana)

  composer.setInputMode(.fullAscii)
  insertKey("a", &composer)
  #expect(composer.getInputMode() == .fullAscii)

  insertKey("i", &composer)
  #expect(composer.getInputMode() == .fullAscii)

  #expect(composer.getStringForPreedit() == "AIあいａｉ")

  composer.setInputMode(.fullKatakana)

  // "|AIあいａｉ"
  composer.moveCursorToBeginning()
  #expect(composer.getInputMode() == .fullKatakana)

  // "A|Iあいａｉ"
  composer.moveCursorRight()
  #expect(composer.getInputMode() == .halfAscii)

  // "AI|あいａｉ"
  composer.moveCursorRight()
  #expect(composer.getInputMode() == .fullKatakana)

  // "AIあ|いａｉ"
  composer.moveCursorRight()
  #expect(composer.getInputMode() == .hiragana)

  // "AIあい|ａｉ"
  composer.moveCursorRight()
  #expect(composer.getInputMode() == .fullKatakana)

  // "AIあいａ|ｉ"
  composer.moveCursorRight()
  #expect(composer.getInputMode() == .fullAscii)

  // "AIあいａｉ|"
  composer.moveCursorRight()
  #expect(composer.getInputMode() == .fullAscii)

  // "AIあいａ|ｉ"
  composer.moveCursorLeft()
  #expect(composer.getInputMode() == .fullAscii)

  // "|AIあいａｉ"
  composer.moveCursorToBeginning()
  #expect(composer.getInputMode() == .fullKatakana)

  // "A|Iあいａｉ"
  composer.moveCursorRight()
  #expect(composer.getInputMode() == .halfAscii)

  // "A|あいａｉ"
  composer.delete()
  #expect(composer.getInputMode() == .fullKatakana)

  // "Aあ|いａｉ"
  composer.moveCursorRight()
  #expect(composer.getInputMode() == .hiragana)

  // "A|いａｉ"
  composer.backspace()
  #expect(composer.getInputMode() == .fullKatakana)

  // "Aいａｉ|"
  composer.moveCursorToEnd()
  #expect(composer.getInputMode() == .fullKatakana)

  // "Aいａ|ｉ"
  composer.moveCursorLeft()
  #expect(composer.getInputMode() == .fullAscii)

  // "Aいａｉ|"
  composer.moveCursorToEnd()
  #expect(composer.getInputMode() == .fullKatakana)
}

  @Test func disabledUpdateInputMode() throws {
  // Set the flag disable.
  var request = Genmai_Commands_Request()
  request.updateInputModeFromSurroundingText = false
  composer.setRequest(request)

  table.addRule("a", "あ", "")
  table.addRule("i", "い", "")

  insertKey("A", &composer)
  #expect(composer.getInputMode() == .halfAscii)

  insertKey("I", &composer)
  #expect(composer.getInputMode() == .halfAscii)

  insertKey("a", &composer)
  #expect(composer.getInputMode() == .hiragana)

  insertKey("i", &composer)
  #expect(composer.getInputMode() == .hiragana)

  composer.setInputMode(.fullAscii)
  insertKey("a", &composer)
  #expect(composer.getInputMode() == .fullAscii)

  insertKey("i", &composer)
  #expect(composer.getInputMode() == .fullAscii)

  #expect(composer.getStringForPreedit() == "AIあいａｉ")

  composer.setInputMode(.fullKatakana)

  // Use same scenario as above test case, but the result of GetInputMode
  // should be always FULL_KATAKANA regardless of the surrounding text.

  // "|AIあいａｉ"
  composer.moveCursorToBeginning()
  #expect(composer.getInputMode() == .fullKatakana)

  // "A|Iあいａｉ"
  composer.moveCursorRight()
  #expect(composer.getInputMode() == .fullKatakana)

  // "AI|あいａｉ"
  composer.moveCursorRight()
  #expect(composer.getInputMode() == .fullKatakana)

  // "AIあ|いａｉ"
  composer.moveCursorRight()
  #expect(composer.getInputMode() == .fullKatakana)

  // "AIあい|ａｉ"
  composer.moveCursorRight()
  #expect(composer.getInputMode() == .fullKatakana)

  // "AIあいａ|ｉ"
  composer.moveCursorRight()
  #expect(composer.getInputMode() == .fullKatakana)

  // "AIあいａｉ|"
  composer.moveCursorRight()
  #expect(composer.getInputMode() == .fullKatakana)

  // "AIあいａ|ｉ"
  composer.moveCursorLeft()
  #expect(composer.getInputMode() == .fullKatakana)

  // "|AIあいａｉ"
  composer.moveCursorToBeginning()
  #expect(composer.getInputMode() == .fullKatakana)

  // "A|Iあいａｉ"
  composer.moveCursorRight()
  #expect(composer.getInputMode() == .fullKatakana)

  // "A|あいａｉ"
  composer.delete()
  #expect(composer.getInputMode() == .fullKatakana)

  // "Aあ|いａｉ"
  composer.moveCursorRight()
  #expect(composer.getInputMode() == .fullKatakana)

  // "A|いａｉ"
  composer.backspace()
  #expect(composer.getInputMode() == .fullKatakana)

  // "Aいａｉ|"
  composer.moveCursorToEnd()
  #expect(composer.getInputMode() == .fullKatakana)

  // "Aいａ|ｉ"
  composer.moveCursorLeft()
  #expect(composer.getInputMode() == .fullKatakana)

  // "Aいａｉ|"
  composer.moveCursorToEnd()
  #expect(composer.getInputMode() == .fullKatakana)
}

  @Test func transformCharactersForNumbers() throws {
  var query = ""

  query = ""
  #expect(!Composer.transformCharactersForNumbers(&query))

  query = "R2D2"
  #expect(!Composer.transformCharactersForNumbers(&query))

  query = "ー１"
  #expect(Composer.transformCharactersForNumbers(&query))
  #expect(query == "−１")  // The hyphen is U+2212.

  query = "ーー１"
  #expect(!Composer.transformCharactersForNumbers(&query))

  query = "ー"
  #expect(!Composer.transformCharactersForNumbers(&query))

  query = "ーー"
  #expect(!Composer.transformCharactersForNumbers(&query))

  query = "ーーーーー"
  #expect(!Composer.transformCharactersForNumbers(&query))

  query = "ｗ"
  #expect(!Composer.transformCharactersForNumbers(&query))

  query = "ーｗ"
  #expect(!Composer.transformCharactersForNumbers(&query))

  query = "ーーｗ"
  #expect(!Composer.transformCharactersForNumbers(&query))

  query = "@"
  #expect(!Composer.transformCharactersForNumbers(&query))

  query = "ー@"
  #expect(!Composer.transformCharactersForNumbers(&query))

  query = "ーー@"
  #expect(!Composer.transformCharactersForNumbers(&query))

  query = "＠"
  #expect(!Composer.transformCharactersForNumbers(&query))

  query = "ー＠"
  #expect(!Composer.transformCharactersForNumbers(&query))

  query = "ーー＠"
  #expect(!Composer.transformCharactersForNumbers(&query))

  query = "まじかー１"
  #expect(!Composer.transformCharactersForNumbers(&query))

  query = "まじかーｗ"
  #expect(!Composer.transformCharactersForNumbers(&query))

  query = "１、０"
  #expect(Composer.transformCharactersForNumbers(&query))
  #expect(query == "１，０")

  query = "０。５"
  #expect(Composer.transformCharactersForNumbers(&query))
  #expect(query == "０．５")

  query = "ー１、０００。５"
  #expect(Composer.transformCharactersForNumbers(&query))
  #expect(query == "−１，０００．５")  // The hyphen is U+2212.

  query = "０３ー"
  #expect(Composer.transformCharactersForNumbers(&query))
  #expect(query == "０３−")  // The hyphen is U+2212.

  query = "０３ーーーーー"
  #expect(Composer.transformCharactersForNumbers(&query))
  #expect(query == "０３−−−−−")  // The hyphen is U+2212.

  query = "ｘー（ー１）＞ーｘ"
  #expect(Composer.transformCharactersForNumbers(&query))
  #expect(query == "ｘ−（−１）＞−ｘ")  // The hyphen is U+2212.

  query = "１＊ー２／ー３ーー４"
  #expect(Composer.transformCharactersForNumbers(&query))
  #expect(query == "１＊−２／−３−−４")  // The hyphen is U+2212.

  query = "ＡーＺ"
  #expect(Composer.transformCharactersForNumbers(&query))
  #expect(query == "Ａ−Ｚ")  // The hyphen is U+2212.

  query = "もずく、うぉーきんぐ。"
  #expect(!Composer.transformCharactersForNumbers(&query))

  query = "えー２、９８０円！月々たった、２、９８０円？"
  #expect(Composer.transformCharactersForNumbers(&query))
  #expect(query == "えー２，９８０円！月々たった、２，９８０円？")

  query = "およそ、３。１４１５９。"
  #expect(Composer.transformCharactersForNumbers(&query))
  #expect(query == "およそ、３．１４１５９．")

  query = "１００、"
  #expect(Composer.transformCharactersForNumbers(&query))
  #expect(query == "１００，")

  query = "１００。"
  #expect(Composer.transformCharactersForNumbers(&query))
  #expect(query == "１００．")
}

  @Test func preeditFormAfterCharacterTransform() throws {
  let manager = CharacterFormManager.getCharacterFormManager()
  table.addRule("0", "０", "")
  table.addRule("1", "１", "")
  table.addRule("2", "２", "")
  table.addRule("3", "３", "")
  table.addRule("4", "４", "")
  table.addRule("5", "５", "")
  table.addRule("6", "６", "")
  table.addRule("7", "７", "")
  table.addRule("8", "８", "")
  table.addRule("9", "９", "")
  table.addRule("-", "ー", "")
  table.addRule(",", "、", "")
  table.addRule(".", "。", "")

  do {
    composer.reset()
    manager.setDefaultRule()
    manager.addPreeditRule("1", .halfWidth)
    manager.addPreeditRule(".,", .halfWidth)
    composer.insertCharacter("3.14")
    #expect(composer.getStringForPreedit() == "3.14")
  }

  do {
    composer.reset()
    manager.setDefaultRule()
    manager.addPreeditRule("1", .fullWidth)
    manager.addPreeditRule(".,", .halfWidth)
    composer.insertCharacter("3.14")
    #expect(composer.getStringForPreedit() == "３.１４")
  }

  do {
    composer.reset()
    manager.setDefaultRule()
    manager.addPreeditRule("1", .halfWidth)
    manager.addPreeditRule(".,", .fullWidth)
    composer.insertCharacter("3.14")
    #expect(composer.getStringForPreedit() == "3．14")
  }

  do {
    composer.reset()
    manager.setDefaultRule()
    manager.addPreeditRule("1", .fullWidth)
    manager.addPreeditRule(".,", .fullWidth)
    composer.insertCharacter("3.14")
    #expect(composer.getStringForPreedit() == "３．１４")
  }

  do {
    composer.reset()
    manager.setDefaultRule()
    composer.insertCharacter("-123")
    #expect(composer.getStringForPreedit() == "−１２３")
    #expect(composer.getRawString() == "-123")
  }
}

  @Test func composingWithcharactertransform() throws {
  table.addRule("0", "０", "")
  table.addRule("1", "１", "")
  table.addRule("2", "２", "")
  table.addRule("3", "３", "")
  table.addRule("4", "４", "")
  table.addRule("5", "５", "")
  table.addRule("6", "６", "")
  table.addRule("7", "７", "")
  table.addRule("8", "８", "")
  table.addRule("9", "９", "")
  table.addRule("-", "ー", "")
  table.addRule(",", "、", "")
  table.addRule(".", "。", "")
  composer.insertCharacter("-1,000.5")

  #expect(composer.getStringForPreedit() == "−１，０００．５")  // The hyphen is U+2212.
  #expect(composer.getStringForSubmission() == "−１，０００．５")  // The hyphen is U+2212.
  #expect(composer.getQueryForConversion() == "-1,000.5")
  #expect(composer.getQueryForPrediction() == "-1,000.5")
  do {
    var left = "", focused = "", right = ""
    // Right edge
    composer.getPreedit(&left, &focused, &right)
    #expect(left == "−１，０００．５")  // The hyphen is U+2212.
    #expect(focused.isEmpty)
    #expect(right.isEmpty)

    composer.moveCursorLeft()
    composer.getPreedit(&left, &focused, &right)
    #expect(left == "−１，０００．")  // The hyphen is U+2212.
    #expect(focused == "５")
    #expect(right.isEmpty)

    composer.moveCursorLeft()
    composer.getPreedit(&left, &focused, &right)
    #expect(left == "−１，０００")  // The hyphen is U+2212.
    #expect(focused == "．")
    #expect(right == "５")

    composer.moveCursorLeft()
    composer.getPreedit(&left, &focused, &right)
    #expect(left == "−１，００")  // The hyphen is U+2212.
    #expect(focused == "０")
    #expect(right == "．５")

    composer.moveCursorLeft()
    composer.getPreedit(&left, &focused, &right)
    #expect(left == "−１，０")  // The hyphen is U+2212.
    #expect(focused == "０")
    #expect(right == "０．５")

    composer.moveCursorLeft()
    composer.getPreedit(&left, &focused, &right)
    #expect(left == "−１，")  // The hyphen is U+2212.
    #expect(focused == "０")
    #expect(right == "００．５")

    composer.moveCursorLeft()
    composer.getPreedit(&left, &focused, &right)
    #expect(left == "−１")
    #expect(focused == "，")
    #expect(right == "０００．５")

    composer.moveCursorLeft()
    composer.getPreedit(&left, &focused, &right)
    #expect(left == "−")  // U+2212.
    #expect(focused == "１")
    #expect(right == "，０００．５")

    // Left edge
    composer.moveCursorLeft()
    composer.getPreedit(&left, &focused, &right)
    #expect(left.isEmpty)
    #expect(focused == "−")  // U+2212.
    #expect(right == "１，０００．５")
  }
}

  @Test func alphanumericOfSSH() throws {
  // This is a unittest against http://b/3199626
  // 'ssh' (っｓｈ) + F10 should be 'ssh'.
  table.addRule("ss", "[X]", "s")
  table.addRule("sha", "[SHA]", "")
  composer.insertCharacter("ssh")
  #expect(composer.getStringForPreedit() == "［Ｘ］ｓｈ")

  #expect(composer.getQueryForConversion() == "[X]sh")

  var t13ns = Transliterations()
  composer.getTransliterations(&t13ns)
  #expect(t13ns[.halfAscii] == "ssh")
}

  @Test func transliterationsOfNegativeNumber() throws {
  table.addRule("-", "ー", "");  // U+30FC (prolonged sound mark)
  table.addRule("1", "１", "")
  composer.insertCharacter("-1")
  #expect(composer.getStringForPreedit() == "−１")  // U+2212 (minus)

  var t13ns = Transliterations()
  composer.getTransliterations(&t13ns)
  // U+002D (hyphen-minus)
  #expect(t13ns[.halfAscii] == "-1")
  // U+2212 (minus)
  #expect(t13ns[.fullAscii] == "−１")
  // U+30FC (prolonged sound mark, 長音)
  #expect(t13ns[.hiragana] == "ー１")
}

  @Test func issue2190364() throws {
  // This is a unittest against http://b/2190364
  var key = Genmai_Commands_KeyEvent()
  key.keyCode = kc("a")
  key.keyString = "ち"

  // Toggle the input mode to HALF_ASCII
  composer.toggleInputMode()
  let inserted = composer.insertCharacterKeyEvent(key)
  #expect(inserted)
  #expect(composer.getStringForPreedit() == "a")

  // Insertion of a space and backspace it should not change the composition.
  composer.insertCharacter(" ")
  #expect(composer.getStringForPreedit() == "a ")

  composer.backspace()
  #expect(composer.getStringForPreedit() == "a")

  // Toggle the input mode to HIRAGANA, the preedit should not be changed.
  composer.toggleInputMode()
  #expect(composer.getStringForPreedit() == "a")

  // "a" should be converted to "ち" on Hiragana input mode.
  let inserted2 = composer.insertCharacterKeyEvent(key)
  #expect(inserted2)
  #expect(composer.getStringForPreedit() == "aち")
}

  @Test func issue1817410() throws {
  // This is a unittest against http://b/2190364
  table.addRule("ss", "っ", "s")

  insertKey("s", &composer)
  insertKey("s", &composer)

  #expect(composer.getStringForPreedit() == "っｓ")

  var t13n =
      composer.getSubTransliteration(.halfAscii, 0, 2)
  #expect(t13n == "ss")

  t13n = composer.getSubTransliteration(.halfAscii, 0, 1)
  #expect(t13n == "s")

  t13n = composer.getSubTransliteration(.halfAscii, 1, 1)
  #expect(t13n == "s")
}

  @Test func issue2272745() throws {
  // This is a unittest against http://b/2272745.
  // A temporary input mode remains when a composition is canceled.
  do {
    insertKey("G", &composer)
    #expect(composer.getInputMode() == .halfAscii)

    composer.backspace()
    #expect(composer.getInputMode() == .hiragana)
  }
  composer.reset()
  do {
    insertKey("G", &composer)
    #expect(composer.getInputMode() == .halfAscii)

    composer.editErase()
    #expect(composer.getInputMode() == .hiragana)
  }
}

  @Test func isue2555503() throws {
  // This is a unittest against http://b/2555503.
  // Mode respects the previous character too much.
  insertKey("a", &composer)
  composer.setInputMode(.fullKatakana)
  insertKey("i", &composer)
  #expect(composer.getInputMode() == .fullKatakana)

  composer.backspace()
  #expect(composer.getInputMode() == .fullKatakana)
}

  @Test func issue2819580Case1() throws {
  // This is a unittest against http://b/2819580.
  // 'y' after 'n' disappears.
  table.addRule("n", "ん", "")
  table.addRule("na", "な", "")
  table.addRule("ya", "や", "")
  table.addRule("nya", "にゃ", "")

  insertKey("n", &composer)
  insertKey("y", &composer)

  #expect(composer.getQueryForConversion() == "ny")
}

  @Test func issue2819580Case2() throws {
  // This is a unittest against http://b/2819580.
  // 'y' after 'n' disappears.
  table.addRule("po", "ぽ", "")
  table.addRule("n", "ん", "")
  table.addRule("na", "な", "")
  table.addRule("ya", "や", "")
  table.addRule("nya", "にゃ", "")

  insertKey("p", &composer)
  insertKey("o", &composer)
  insertKey("n", &composer)
  insertKey("y", &composer)

  #expect(composer.getQueryForConversion() == "ぽny")
}

  @Test func issue2819580Case3() throws {
  // This is a unittest against http://b/2819580.
  // 'y' after 'n' disappears.
  table.addRule("n", "ん", "")
  table.addRule("na", "な", "")
  table.addRule("ya", "や", "")
  table.addRule("nya", "にゃ", "")

  insertKey("z", &composer)
  insertKey("n", &composer)
  insertKey("y", &composer)

  #expect(composer.getQueryForConversion() == "zny")
}

  @Test func issue2797991Case1() throws {
  // This is a unittest against http://b/2797991.
  // Half-width alphanumeric mode quits after [CAPITAL LETTER]:[CAPITAL LETTER]
  // e.g. C:\Wi . C:\Wい

  table.addRule("i", "い", "")

  insertKey("C", &composer)
  insertKey(":", &composer)
  insertKey("\\", &composer)
  insertKey("W", &composer)
  insertKey("i", &composer)

  #expect(composer.getStringForPreedit() == "C:\\Wi")
}

  @Test func issue2797991Case2() throws {
  // This is a unittest against http://b/2797991.
  // Half-width alphanumeric mode quits after [CAPITAL LETTER]:[CAPITAL LETTER]
  // e.g. C:\Wi . C:\Wい

  table.addRule("i", "い", "")

  insertKey("C", &composer)
  insertKey(":", &composer)
  insertKey("W", &composer)
  insertKey("i", &composer)

  #expect(composer.getStringForPreedit() == "C:Wi")
}

  @Test func issue2797991Case3() throws {
  // This is a unittest against http://b/2797991.
  // Half-width alphanumeric mode quits after [CAPITAL LETTER]:[CAPITAL LETTER]
  // e.g. C:\Wi . C:\Wい

  table.addRule("i", "い", "")

  insertKey("C", &composer)
  insertKey(":", &composer)
  insertKey("\\", &composer)
  insertKey("W", &composer)
  insertKey("i", &composer)
  insertKeyWithMode("i", .hiragana, &composer)
  #expect(composer.getStringForPreedit() == "C:\\Wiい")
}

  @Test func issue2797991Case4() throws {
  // This is a unittest against http://b/2797991.
  // Half-width alphanumeric mode quits after [CAPITAL LETTER]:[CAPITAL LETTER]
  // e.g. C:\Wi . C:\Wい

  table.addRule("i", "い", "")

  insertKey("c", &composer)
  insertKey(":", &composer)
  insertKey("\\", &composer)
  insertKey("W", &composer)
  insertKey("i", &composer)

  #expect(composer.getStringForPreedit() == "c:\\Wi")
}

  @Test func caseSensitiveByConfiguration() throws {
  do {
    config.shiftKeyModeSwitch = .off
    table.initializeWithRequestAndConfig(request, config)

    table.addRule("i", "い", "")
    table.addRule("I", "イ", "")

    insertKey("i", &composer)
    insertKey("I", &composer)
    insertKey("i", &composer)
    insertKey("I", &composer)
    #expect(composer.getStringForPreedit() == "いイいイ")
  }
  composer.reset()
  do {
    config.shiftKeyModeSwitch = .asciiInputMode
    table.initializeWithRequestAndConfig(request, config)

    table.addRule("i", "い", "")
    table.addRule("I", "イ", "")

    insertKey("i", &composer)
    insertKey("I", &composer)
    insertKey("i", &composer)
    insertKey("I", &composer)
    #expect(composer.getStringForPreedit() == "いIiI")
  }
}

  @Test func inputUppercaseInAlphanumericModeWithShiftKeyModeSwitchIsKatakana() throws {
  do {
    config.shiftKeyModeSwitch = .katakanaInputMode
    table.initializeWithRequestAndConfig(request, config)

    table.addRule("i", "い", "")
    table.addRule("I", "イ", "")

    do {
      composer.reset()
      composer.setInputMode(.fullAscii)
      insertKey("I", &composer)
      #expect(composer.getStringForPreedit() == "Ｉ")
    }

    do {
      composer.reset()
      composer.setInputMode(.halfAscii)
      insertKey("I", &composer)
      #expect(composer.getStringForPreedit() == "I")
    }

    do {
      composer.reset()
      composer.setInputMode(.fullKatakana)
      insertKey("I", &composer)
      #expect(composer.getStringForPreedit() == "イ")
    }

    do {
      composer.reset()
      composer.setInputMode(.halfKatakana)
      insertKey("I", &composer)
      #expect(composer.getStringForPreedit() == "ｲ")
    }

    do {
      composer.reset()
      composer.setInputMode(.hiragana)
      insertKey("I", &composer)
      #expect(composer.getStringForPreedit() == "イ")
    }
  }
}

  @Test func deletingAlphanumericPartShouldQuitToggleAlphanumericMode() throws {
  // http://b/2206560
  // 1. Type "iGoogle" (preedit text turns to be "いGoogle")
  // 2. Type Back-space 6 times ("い")
  // 3. Type "i" (should be "いい")

  table.initializeWithRequestAndConfig(request, config)

  table.addRule("i", "い", "")

  insertKey("i", &composer)
  insertKey("G", &composer)
  insertKey("o", &composer)
  insertKey("o", &composer)
  insertKey("g", &composer)
  insertKey("l", &composer)
  insertKey("e", &composer)

  #expect(composer.getStringForPreedit() == "いGoogle")

  composer.backspace()
  composer.backspace()
  composer.backspace()
  composer.backspace()
  composer.backspace()
  composer.backspace()

  #expect(composer.getStringForPreedit() == "い")

  insertKey("i", &composer)

  #expect(composer.getStringForPreedit() == "いい")
}

  @Test func inputModesChangeWhenCursorMoves() throws {
  // The expectation of this test is the same as MS-IME's

  table.initializeWithRequestAndConfig(request, config)

  table.addRule("i", "い", "")
  table.addRule("gi", "ぎ", "")

  insertKey("i", &composer)
  composer.moveCursorRight()
  #expect(composer.getStringForPreedit() == "い")

  composer.moveCursorLeft()
  #expect(composer.getStringForPreedit() == "い")

  insertKey("G", &composer)
  #expect(composer.getStringForPreedit() == "Gい")

  composer.moveCursorRight()
  #expect(composer.getStringForPreedit() == "Gい")

  insertKey("G", &composer)
  #expect(composer.getStringForPreedit() == "GいG")

  composer.moveCursorLeft()
  insertKey("i", &composer)
  #expect(composer.getStringForPreedit() == "GいいG")

  composer.moveCursorRight()
  insertKey("i", &composer)
  #expect(composer.getStringForPreedit() == "GいいGi")

  insertKey("G", &composer)
  insertKey("i", &composer)
  #expect(composer.getStringForPreedit() == "GいいGiGi")

  composer.backspace()
  composer.backspace()
  composer.backspace()
  insertKey("i", &composer)
  #expect(composer.getStringForPreedit() == "GいいGi")

  insertKey("G", &composer)
  insertKey("G", &composer)
  composer.moveCursorRight()
  insertKey("i", &composer)
  #expect(composer.getStringForPreedit() == "GいいGiGGi")

  composer.backspace()
  composer.backspace()
  composer.backspace()
  composer.backspace()
  composer.backspace()
  composer.backspace()
  composer.backspace()
  insertKey("i", &composer)
  #expect(composer.getStringForPreedit() == "Gい")

  composer.backspace()
  composer.moveCursorLeft()
  composer.moveCursorRight()
  insertKey("i", &composer)
  #expect(composer.getStringForPreedit() == "Gi")
}

  @Test func shouldCommit() throws {
  table.addRuleWithAttributes("ka", "[KA]", "", .directInput)
  table.addRuleWithAttributes("tt", "[X]", "t", .directInput)
  table.addRuleWithAttributes("ta", "[TA]", "", .noTableAttribute)

  composer.insertCharacter("k")
  #expect(!composer.shouldCommit())

  composer.insertCharacter("a")
  #expect(composer.shouldCommit())

  composer.insertCharacter("t")
  #expect(!composer.shouldCommit())

  composer.insertCharacter("t")
  #expect(!composer.shouldCommit())

  composer.insertCharacter("a")
  #expect(composer.shouldCommit())

  composer.insertCharacter("t")
  #expect(!composer.shouldCommit())

  composer.insertCharacter("a")
  #expect(!composer.shouldCommit())
}

  @Test func shouldCommitHead() throws {
  struct TestData {
    let input_text: String
    let field_type: Genmai_Commands_Context.InputFieldType
    let expected_return: Bool
    let expected_commit_length: Int
    init(
      _ input_text: String, _ field_type: Genmai_Commands_Context.InputFieldType,
      _ expected_return: Bool, _ expected_commit_length: Int
    ) {
      self.input_text = input_text
      self.field_type = field_type
      self.expected_return = expected_return
      self.expected_commit_length = expected_commit_length
    }
  }
  let test_data_list = [
      // On NORMAL, never commit the head.
      TestData("", .normal, false, 0),
      TestData("A", .normal, false, 0),
      TestData("AB", .normal, false, 0),
      TestData("", .password, false, 0),
      // On PASSWORD, commit (length - 1) characters.
      TestData("A", .password, false, 0),
      TestData("AB", .password, true, 1),
      TestData("ABCDEFGHI", .password, true, 8),
      // On NUMBER and TEL, commit (length) characters.
      TestData("", .number, false, 0),
      TestData("A", .number, true, 1),
      TestData("AB", .number, true, 2),
      TestData("ABCDEFGHI", .number, true, 9),
      TestData("", .tel, false, 0),
      TestData("A", .tel, true, 1),
      TestData("AB", .tel, true, 2),
      TestData("ABCDEFGHI", .tel, true, 9),
  ]

  for i in 0..<test_data_list.count {
    let test_data = test_data_list[i]
    // SCOPED_TRACE(test_data.input_text)
    // SCOPED_TRACE(test_data.field_type)
    // SCOPED_TRACE(test_data.expected_return)
    // SCOPED_TRACE(test_data.expected_commit_length)
    composer.reset()
    composer.setInputFieldType(test_data.field_type)
    composer.insertCharacter(test_data.input_text)
    var length_to_commit = 0
    let result = composer.shouldCommitHead(&length_to_commit)
    if (test_data.expected_return) {
      #expect(result)
      #expect(length_to_commit == test_data.expected_commit_length)
    } else {
      #expect(!result)
    }
  }
}

  @Test func cursorMovements() throws {
  composer.insertCharacter("mozuku")
  #expect(composer.getLength() == 6)
  #expect(composer.getCursor() == 6)

  composer.moveCursorRight()
  #expect(composer.getCursor() == 6)
  composer.moveCursorLeft()
  #expect(composer.getCursor() == 5)

  composer.moveCursorToBeginning()
  #expect(composer.getCursor() == 0)
  composer.moveCursorLeft()
  #expect(composer.getCursor() == 0)
  composer.moveCursorRight()
  #expect(composer.getCursor() == 1)

  composer.moveCursorTo(0)
  #expect(composer.getCursor() == 0)
  composer.moveCursorTo(6)
  #expect(composer.getCursor() == 6)
  composer.moveCursorTo(3)
  #expect(composer.getCursor() == 3)
  composer.moveCursorTo(10)
  #expect(composer.getCursor() == 3)
  composer.moveCursorTo(UInt32(bitPattern: -1))
  #expect(composer.getCursor() == 3)
}

  @Test func sourceText() throws {
  composer.setInputMode(.halfAscii)
  composer.insertCharacterPreedit("mozc")
  composer.sourceText = "MOZC"
  #expect(!composer.isEmpty())
  #expect(composer.getStringForPreedit() == "mozc")
  #expect(composer.sourceText == "MOZC")

  composer.backspace()
  composer.backspace()
  #expect(!composer.isEmpty())
  #expect(composer.getStringForPreedit() == "mo")
  #expect(composer.sourceText == "MOZC")

  composer.reset()
  #expect(composer.isEmpty())
  #expect(composer.sourceText.isEmpty)
}

  @Test func deleteAt() throws {
  table.addRule("mo", "も", "")
  table.addRule("zu", "ず", "")

  composer.insertCharacter("z")
  #expect(composer.getStringForPreedit() == "ｚ")
  #expect(composer.getCursor() == 1)
  composer.deleteAt(0)
  #expect(composer.getStringForPreedit() == "")
  #expect(composer.getCursor() == 0)

  composer.insertCharacter("mmoz")
  #expect(composer.getStringForPreedit() == "ｍもｚ")
  #expect(composer.getCursor() == 3)
  composer.deleteAt(0)
  #expect(composer.getStringForPreedit() == "もｚ")
  #expect(composer.getCursor() == 2)
  composer.insertCharacter("u")
  #expect(composer.getStringForPreedit() == "もず")
  #expect(composer.getCursor() == 2)

  composer.insertCharacter("m")
  #expect(composer.getStringForPreedit() == "もずｍ")
  #expect(composer.getCursor() == 3)
  composer.deleteAt(1)
  #expect(composer.getStringForPreedit() == "もｍ")
  #expect(composer.getCursor() == 2)
  composer.insertCharacter("o")
  #expect(composer.getStringForPreedit() == "もも")
  #expect(composer.getCursor() == 2)
}

  @Test func deleteRange() throws {
  table.addRule("mo", "も", "")
  table.addRule("zu", "ず", "")

  composer.insertCharacter("z")
  #expect(composer.getStringForPreedit() == "ｚ")
  #expect(composer.getCursor() == 1)

  composer.deleteRange(0, 1)
  #expect(composer.getStringForPreedit() == "")
  #expect(composer.getCursor() == 0)

  composer.insertCharacter("mmozmoz")
  #expect(composer.getStringForPreedit() == "ｍもｚもｚ")
  #expect(composer.getCursor() == 5)

  composer.deleteRange(0, 3)
  #expect(composer.getStringForPreedit() == "もｚ")
  #expect(composer.getCursor() == 2)

  composer.insertCharacter("u")
  #expect(composer.getStringForPreedit() == "もず")
  #expect(composer.getCursor() == 2)

  composer.insertCharacter("xyz")
  composer.moveCursorToBeginning()
  composer.insertCharacter("mom")
  #expect(composer.getStringForPreedit() == "もｍもずｘｙｚ")
  #expect(composer.getCursor() == 2)

  composer.deleteRange(2, 3)
  // "もｍ|ｙｚ"
  #expect(composer.getStringForPreedit() == "もｍｙｚ")
  #expect(composer.getCursor() == 2)

  composer.insertCharacter("o")
  // "もも|ｙｚ"
  #expect(composer.getStringForPreedit() == "ももｙｚ")
  #expect(composer.getCursor() == 2)

  composer.deleteRange(2, 1000)
  // "もも|"
  #expect(composer.getStringForPreedit() == "もも")
  #expect(composer.getCursor() == 2)
}

  @Test func twelveKeysAsciiGetQueryForPrediction() throws {
  // http://b/5509480
  var request = Genmai_Commands_Request()
  request.zeroQuerySuggestion = true
  request.mixedConversion = true
  request.specialRomanjiTable = .twelveKeysToHalfwidthascii
  composer.setRequest(request)
  table.initializeWithRequestAndConfig(request, ConfigHandler.defaultConfig())
  composer.insertCharacter("2")
  #expect(composer.getStringForPreedit() == "a")
  #expect(composer.getQueryForConversion() == "a")
  #expect(composer.getQueryForPrediction() == "a")
}

  @Test func insertCharacterPreedit() throws {
  let kTestStr = "ああaｋka。"

  do {
    composer.insertCharacterPreedit(kTestStr)
    let preedit = composer.getStringForPreedit()
    let conversion_query = composer.getQueryForConversion()
    let prediction_query = composer.getQueryForPrediction()
    // auto = std::pair<std::string, absl::btree_set<std::string>>
    let (base, expanded) = composer.getQueriesForPrediction()
    #expect(!preedit.isEmpty)
    #expect(!conversion_query.isEmpty)
    #expect(!prediction_query.isEmpty)
    #expect(!base.isEmpty)
  }
  composer.reset()
  do {
    for c in Util.splitStringToUtf8Chars(kTestStr) {
      composer.insertCharacterPreedit(c)
    }
    let preedit = composer.getStringForPreedit()
    let conversion_query = composer.getQueryForConversion()
    let prediction_query = composer.getQueryForPrediction()
    // auto = std::pair<std::string, absl::btree_set<std::string>>
    let (base, expanded) = composer.getQueriesForPrediction()
    #expect(!preedit.isEmpty)
    #expect(!conversion_query.isEmpty)
    #expect(!prediction_query.isEmpty)
    #expect(!base.isEmpty)
  }
}

  @Test func getRawString() throws {
  table.addRule("sa", "さ", "")
  table.addRule("shi", "し", "")
  table.addRule("mi", "み", "")

  composer.setOutputMode(.hiragana)

  composer.insertCharacter("sashimi")

  #expect(composer.getStringForPreedit() == "さしみ")

  var raw_string = composer.getRawString()
  #expect(raw_string == "sashimi")

  var raw_sub_string = composer.getRawSubString(0, 2)
  #expect(raw_sub_string == "sashi")

  raw_sub_string = composer.getRawSubString(1, 1)
  #expect(raw_sub_string == "shi")
}

  @Test func setPreeditTextForTestOnly() throws {
  composer.setPreeditTextForTestOnly("も")

  #expect(composer.getInputMode() == .hiragana)
  #expect(composer.getStringForPreedit() == "も")
  #expect(composer.getStringForSubmission() == "も")
  #expect(composer.getQueryForConversion() == "も")
  #expect(composer.getQueryForPrediction() == "も")

  // auto = std::pair<std::string, absl::btree_set<std::string>>
  let (output1, expanded1) = composer.getQueriesForPrediction()
  #expect(output1 == "も")
  #expect(expanded1.isEmpty)

  composer.reset()

  composer.setPreeditTextForTestOnly("mo")

  #expect(composer.getInputMode() == .halfAscii)
  #expect(composer.getStringForPreedit() == "mo")
  #expect(composer.getStringForSubmission() == "mo")
  #expect(composer.getQueryForConversion() == "mo")
  #expect(composer.getQueryForPrediction() == "mo")

  // auto = std::pair<std::string, absl::btree_set<std::string>>
  let (output2, expanded2) = composer.getQueriesForPrediction()
  #expect(output2 == "mo")

  #expect(expanded2.isEmpty)

  composer.reset()

  composer.setPreeditTextForTestOnly("ｍ")

  #expect(composer.getInputMode() == .hiragana)
  #expect(composer.getStringForPreedit() == "ｍ")
  #expect(composer.getStringForSubmission() == "ｍ")
  #expect(composer.getQueryForConversion() == "m")
  #expect(composer.getQueryForPrediction() == "m")

  // auto = std::pair<std::string, absl::btree_set<std::string>>
  let (output3, expanded3) = composer.getQueriesForPrediction()
  #expect(output3 == "m")

  #expect(expanded3.isEmpty)

  composer.reset()

  composer.setPreeditTextForTestOnly("もｚ")

  #expect(composer.getInputMode() == .hiragana)

  #expect(composer.getStringForPreedit() == "もｚ")
  #expect(composer.getStringForSubmission() == "もｚ")
  #expect(composer.getQueryForConversion() == "もz")
  #expect(composer.getQueryForPrediction() == "もz")

  // auto = std::pair<std::string, absl::btree_set<std::string>>
  let (output4, expanded4) = composer.getQueriesForPrediction()
  #expect(output4 == "もz")

  #expect(expanded4.isEmpty)
}

  @Test func isToggleable() throws {
  let kAttrs: TableAttributes = [.newChunk, .noTransliteration]
  table.addRuleWithAttributes("1", "", "{?}あ", kAttrs)
  table.addRule("{?}あ1", "", "{?}い")
  table.addRule("{?}い{!}", "", "{*}い")

  #expect(!composer.isToggleable())

  try #require(insertKeyWithMode("1", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "あ")
  #expect(composer.isToggleable())

  try #require(insertKeyWithMode("1", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "い")
  #expect(composer.isToggleable())

  composer.insertCommandCharacter(.stopKeyToggling)
  #expect(composer.getStringForPreedit() == "い")
  #expect(!composer.isToggleable())

  composer.reset()
  try #require(insertKeyWithMode("1", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "あ")
  composer.setNewInput()
  #expect(!composer.isToggleable())
}

  @Test func checkTimeout() throws {
  table.addRule("1", "", "あ")
  table.addRule("あ{!}", "あ", "")
  table.addRule("あ1", "", "い")
  table.addRule("い{!}", "い", "")
  table.addRule("い1", "", "う")

  let clock = ClockMock(Date(unixSeconds: 86400))
  try Clock.withClock(clock) {

  #expect(composer.timeoutThresholdMsec == 0)

  try #require(insertKeyWithMode("1", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "あ")

  clock.advance(.seconds(3))

  // Because the threshold is not set, STOP_KEY_TOGGLING is not sent.
  try #require(insertKeyWithMode("1", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "い")

  // Set the threshold time.
  composer.reset()
  composer.timeoutThresholdMsec = 1000

  try #require(insertKeyWithMode("1", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "あ")

  clock.advance(.seconds(3))

  try #require(insertKeyWithMode("1", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "ああ")

  clock.advance(.milliseconds(700))

  try #require(insertKeyWithMode("1", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "あい")
  }
}

  @Test func checkTimeoutWithProtobuf() throws {
  table.addRule("1", "", "あ")
  table.addRule("あ{!}", "あ", "")
  table.addRule("あ1", "", "い")
  table.addRule("い{!}", "い", "")
  table.addRule("い1", "", "う")

  let clock = ClockMock(Date(unixSeconds: 86400))
  try Clock.withClock(clock) {

  config.composingTimeoutThresholdMsec = 500
  composer.reset();  // The threshold should be updated to 500msec.

  var timestamp_msec: Int64 = 86_400_000  // absl::ToUnixMillis(UnixEpoch() + 24h)

  var key_event = KeyEvent()
  key_event.keyCode = kc("1")
  key_event.timestampMsec = timestamp_msec
  composer.insertCharacterKeyEvent(key_event)
  #expect(composer.getStringForPreedit() == "あ")

  clock.advance(.milliseconds(100))
  timestamp_msec += 3000;  // +3.0 sec in proto.
  key_event.timestampMsec = timestamp_msec
  composer.insertCharacterKeyEvent(key_event)
  #expect(composer.getStringForPreedit() == "ああ")

  clock.advance(.milliseconds(100))
  timestamp_msec += 700;  // +0.7 sec in proto.
  key_event.timestampMsec = timestamp_msec
  composer.insertCharacterKeyEvent(key_event)
  #expect(composer.getStringForPreedit() == "あああ")

  clock.advance(.milliseconds(300))
  timestamp_msec += 100;  // +0.7 sec in proto.
  key_event.timestampMsec = timestamp_msec
  composer.insertCharacterKeyEvent(key_event)
  #expect(composer.getStringForPreedit() == "ああい")
  }
}

  @Test func simultaneousInput() throws {
  table.addRule("k", "", "い");      // k → い
  table.addRule("い{!}", "い", "");  // k → い (timeout)
  table.addRule("d", "", "か");      // d → か
  table.addRule("か{!}", "か", "");  // d → か (timeout)
  table.addRule("かk", "れ", "");    // dk → れ
  table.addRule("いd", "れ", "");    // kd → れ
  table.addRule("zl", "→", "");      // normal conversion w/o timeout

  let clock = ClockMock(Date(unixSeconds: 86400))
  try Clock.withClock(clock) {
  composer.timeoutThresholdMsec = 50

  try #require(insertKeyWithMode("k", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "い")

  clock.advance(.milliseconds(30));  // < 50 msec
  try #require(insertKeyWithMode("d", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "れ")

  clock.advance(.milliseconds(30));  // < 50 msec
  try #require(insertKeyWithMode("k", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "れい")

  clock.advance(.milliseconds(200));  // > 50 msec
  try #require(insertKeyWithMode("d", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "れいか")

  clock.advance(.milliseconds(200));  // > 50 msec

  try #require(insertKeyWithMode("z", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "れいかｚ")

  // Even after timeout, normal conversions work.
  clock.advance(.milliseconds(200));  // > 50 msec
  try #require(insertKeyWithMode("l", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "れいか→")
  }
}

  @Test func simultaneousInputWithSpecialKey1() throws {
  table.addRule("{henkan}", "あ", "")

  try #require(insertKeyWithMode("Henkan", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "あ")
}

  @Test func simultaneousInputWithSpecialKey2() throws {
  table.addRule("{henkan}j", "お", "")

  try #require(insertKeyWithMode("Henkan", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "")

  try #require(insertKeyWithMode("j", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "お")

  try #require(insertKeyWithMode("Henkan", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "お")

  try #require(insertKeyWithMode("j", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "おお")
}

  @Test func simultaneousInputWithSpecialKey3() throws {
  table.addRule("j", "", "と")
  table.addRule("と{henkan}", "お", "")
  table.addRule("{henkan}j", "お", "")

  try #require(insertKeyWithMode("Henkan", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "")

  try #require(insertKeyWithMode("j", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "お")
}

  @Test func simultaneousInputWithSpecialKey4() throws {
  table.addRule("j", "", "と")
  table.addRule("と{henkan}", "お", "")
  table.addRule("{henkan}j", "お", "")

  try #require(insertKeyWithMode("j", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "と")

  try #require(insertKeyWithMode("Henkan", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "お")
}

  @Test func simultaneousInputWithSpecialKey5() throws {
  table.addRule("r", "", "{*}")
  table.addRule("{*}j", "お", "")

  try #require(insertKeyWithMode("r", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "")

  try #require(insertKeyWithMode("j", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "お")
}

  @Test func simultaneousInputWithSpecialKey6() throws {
  table.addRule("{!}", "", "");          // no-op
  table.addRule("{henkan}{!}", "", "");  // no-op
  table.addRule("j", "", "と")
  table.addRule("と{!}", "と", "")
  table.addRule("{henkan}j", "お", "")
  table.addRule("と{henkan}", "お", "")

  let clock = ClockMock(Date(unixSeconds: 86400))
  try Clock.withClock(clock) {
  composer.timeoutThresholdMsec = 50

  // "j"
  try #require(insertKeyWithMode("j", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "と")

  // "j{henkan}"
  clock.advance(.milliseconds(30));  // < 50 msec
  try #require(insertKeyWithMode("Henkan", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "お")

  // "j{henkan}j"
  clock.advance(.milliseconds(30));  // < 50 msec
  try #require(insertKeyWithMode("j", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "おと")

  // "j{henkan}j{!}{henkan}"
  clock.advance(.milliseconds(200));  // > 50 msec
  try #require(insertKeyWithMode("Henkan", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "おと")

  // "j{henkan}j{!}{henkan}{!}j"
  clock.advance(.milliseconds(200));  // > 50 msec
  try #require(insertKeyWithMode("j", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "おとと")

  // "j{henkan}j{!}{henkan}{!}j{!}{henkan}"
  clock.advance(.milliseconds(200));  // > 50 msec
  try #require(insertKeyWithMode("Henkan", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "おとと")

  // "j{henkan}j{!}{henkan}{!}j{!}{henkan}j"
  clock.advance(.milliseconds(30));  // < 50 msec
  try #require(insertKeyWithMode("j", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "おととお")
  }
}

// Confirms empty entries (e.g. the 大⇔小 key to は) are skipped. b/289217346
  @Test func skipEmptyEntries() throws {
  // Rules are extracted from data/preedit/toggle_flick-hiragana.tsv
  // specified from Request::TOGGLE_FLICK_TO_HIRAGANA.
  table.addRuleWithAttributes("6", "", "{?}は", [.newChunk, .noTransliteration])
  // "*" is the raw input for the 大⇔小 key.
  table.addRule("{?}は*", "", "{*}ば")
  // "`" is the raw input for the sliding up of the 大⇔小 key.
  table.addRuleWithAttributes("`", "", "", .noTransliteration)
  table.addRuleWithAttributes("*", "", "", .noTransliteration)

  // Type は from 6
  try #require(insertKeyWithMode("6", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "は")

  // Slide up the 大⇔小 key to try to make は smaller, but it's invalid.
  try #require(insertKeyWithMode("`", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "は")

  // Tap the 大⇔小 key to make は to ば. It should work regardless the above
  // step.
  try #require(insertKeyWithMode("*", .hiragana, &composer))
  #expect(composer.getStringForPreedit() == "ば")
}

// Confirm that N in the middle of composing text is not removed where the
// character form is fullwidth. (b/241724792)
  @Test func nBforeN_WithFullWidth() throws {
  table.addRule("na", "な", "")
  table.addRule("n", "ん", "")
  table.addRule("nn", "ん", "")
  table.addRule("a", "あ", "")

  let manager = CharacterFormManager.getCharacterFormManager()
  manager.setDefaultRule()
  manager.addPreeditRule("a", .fullWidth)

  try #require(insertKey("a", &composer))
  #expect(composer.getStringForPreedit() == "あ")

  try #require(insertKey("n", &composer))
  #expect(composer.getStringForPreedit() == "あｎ")

  composer.moveCursorLeft()
  try #require(insertKey("n", &composer))
  #expect(composer.getStringForPreedit() == "あｎｎ")

  var left = "", focused = "", right = ""
  composer.getPreedit(&left, &focused, &right)
  #expect(left == "あｎ")
  #expect(focused == "ｎ")
  #expect(right == "")

  // auto = std::pair<std::string, absl::btree_set<std::string>>
  let (queries_base, queries_expanded) =
      composer.getQueriesForPrediction()
  #expect(queries_base == "あn")

  #expect(composer.getQueryForPrediction() == "あnn")

  try #require(insertKey("a", &composer))
  #expect(composer.getStringForPreedit() == "あなｎ")

  composer.getPreedit(&left, &focused, &right)
  #expect(left == "あな")
  #expect(focused == "ｎ")
  #expect(right == "")

  #expect(composer.getQueryForPrediction() == "あな")
}

// Confirm that N in the middle of composing text is not removed where the
// character form is halfwidth. (b/241724792)
  @Test func nBforeN_WithHalfWidth() throws {
  table.addRule("na", "な", "")
  table.addRule("n", "ん", "")
  table.addRule("nn", "ん", "")
  table.addRule("a", "あ", "")

  let manager = CharacterFormManager.getCharacterFormManager()
  manager.setDefaultRule()
  manager.addPreeditRule("a", .halfWidth)

  try #require(insertKey("a", &composer))
  #expect(composer.getStringForPreedit() == "あ")

  try #require(insertKey("n", &composer))
  #expect(composer.getStringForPreedit() == "あn")

  composer.moveCursorLeft()
  try #require(insertKey("n", &composer))
  #expect(composer.getStringForPreedit() == "あnn")

  var left = "", focused = "", right = ""
  composer.getPreedit(&left, &focused, &right)
  #expect(left == "あn")
  #expect(focused == "n")
  #expect(right == "")

  // auto = std::pair<std::string, absl::btree_set<std::string>>
  let (queries_base, queries_expanded) =
      composer.getQueriesForPrediction()
  #expect(queries_base == "あn")

  #expect(composer.getQueryForPrediction() == "あnn")

  try #require(insertKey("a", &composer))
  #expect(composer.getStringForPreedit() == "あなn")
  composer.getPreedit(&left, &focused, &right)
  #expect(left == "あな")
  #expect(focused == "n")
  #expect(right == "")

  #expect(composer.getQueryForPrediction() == "あな")
}

  @Test func getStringForTypeCorrectionTest() throws {
  table.addRule("a", "あ", "")
  table.addRule("i", "い", "")
  table.addRule("u", "う", "")
  composer.insertCharacter("aiu")

  #expect(composer.getStringForTypeCorrection() == "あいう")
}

  @Test func updateComposition() throws {
  do {
    var command = Genmai_Commands_SessionCommand()
    var composition_event = Genmai_Commands_SessionCommand.CompositionEvent()
    composition_event.compositionString = "かん字"
    composition_event.probability = 1.0
    command.compositionEvents.append(composition_event)
    composer.setCompositionsForHandwriting(command.compositionEvents)
  }

  #expect(composer.getQueryForPrediction() == "かん字")
  #expect(composer.getHandwritingCompositions().count == 1)

  do {
    var command = Genmai_Commands_SessionCommand()
    var composition_event = Genmai_Commands_SessionCommand.CompositionEvent()
    composition_event.compositionString = "ねこ"
    composition_event.probability = 0.9
    command.compositionEvents.append(composition_event)
    composition_event = Genmai_Commands_SessionCommand.CompositionEvent()
    composition_event.compositionString = "ね二"
    composition_event.probability = 0.1
    command.compositionEvents.append(composition_event)
    composer.setCompositionsForHandwriting(command.compositionEvents)
  }

  #expect(composer.getQueryForPrediction() == "ねこ")
  #expect(composer.getHandwritingCompositions().count == 2)
}

  @Test func createComposerData() throws {
  table.addRule("a", "あ", "")
  table.addRule("ka", "か", "")
  table.addRule("ki", "き", "")

  insertKey("a", &composer)
  insertKeyWithMode("a", .fullKatakana, &composer)
  insertKey("k", &composer)

  let data = composer.createComposerData()
  #expect(data.getInputMode() == composer.getInputMode())
  #expect(data.getStringForPreedit() == "あアｋ")
  #expect(data.getStringForPreedit() == composer.getStringForPreedit())
  #expect(data.getQueryForConversion() == composer.getQueryForConversion())
  #expect(data.getQueryForPrediction() == "あア")
  #expect(data.getQueryForPrediction() == composer.getQueryForPrediction())
  #expect(data.getStringForTypeCorrection() == composer.getStringForTypeCorrection())
  #expect(data.getLength() == composer.getLength())
  #expect(data.getCursor() == composer.getCursor())
  #expect(data.getRawString() == composer.getRawString())
  #expect(data.getRawSubString(0, 2) == composer.getRawSubString(0, 2))
  #expect(data.getRawSubString(1, 1) == composer.getRawSubString(1, 1))
  #expect(data.sourceText == composer.sourceText)

  #expect(data.getHandwritingCompositions().count == 0)
  #expect(composer.getHandwritingCompositions().count == 0)

  do {  // Queries for prediction
    // auto = std::pair<std::string, absl::btree_set<std::string>>
    let (data_base, data_expanded) = data.getQueriesForPrediction()
    #expect(data_base == "あア")
    #expect(data_expanded.count == 3)

    // auto = std::pair<std::string, absl::btree_set<std::string>>
    let (composer_base, composer_expanded) =
        data.getQueriesForPrediction()
    #expect(data_base == composer_base)
    #expect(data_expanded.count == composer_expanded.count)

    let expected_expanded = ["k", "か", "き"]
    #expect(data_expanded == composer_expanded)
    #expect(data_expanded == expected_expanded)
  }

  do {  // Transliterations
    var data_t13ns = Transliterations()
    data.getTransliterations(&data_t13ns)
    var composer_t13ns = Transliterations()
    let expected_t13ns: Transliterations = [
        "ああｋ", "アアｋ", "aak",    "AAK",    "aak", "Aak",
        "ａａｋ", "ＡＡＫ", "ａａｋ", "Ａａｋ", "ｱｱk"]
    composer.getTransliterations(&composer_t13ns)
    #expect(data_t13ns.count == 11)
    #expect(data_t13ns.count == composer_t13ns.count)
    #expect(data_t13ns == expected_t13ns)
    #expect(data_t13ns == composer_t13ns)
  }

  do {  // SubTransliterations
    var data_t13ns = Transliterations()
    data.getSubTransliterations(2, 1, &data_t13ns)
    var composer_t13ns = Transliterations()
    let expected_t13ns: Transliterations = [
        "ｋ", "ｋ", "k", "K", "k", "K", "ｋ", "Ｋ", "ｋ", "Ｋ", "k"]
    composer.getSubTransliterations(2, 1, &composer_t13ns)
    #expect(data_t13ns.count == 11)
    #expect(data_t13ns.count == composer_t13ns.count)
    #expect(data_t13ns == expected_t13ns)
    #expect(data_t13ns == composer_t13ns)
  }
}

  @Test func createComposerDataForHandwriting() throws {
  var command = Genmai_Commands_SessionCommand()
  var composition_event = Genmai_Commands_SessionCommand.CompositionEvent()
  composition_event.compositionString = "ねこ"
  composition_event.probability = 0.9
  command.compositionEvents.append(composition_event)
  composition_event = Genmai_Commands_SessionCommand.CompositionEvent()
  composition_event.compositionString = "ね二"
  composition_event.probability = 0.1
  command.compositionEvents.append(composition_event)
  composer.setCompositionsForHandwriting(command.compositionEvents)

  let data = composer.createComposerData()
  #expect(data.getInputMode() == composer.getInputMode())
  #expect(data.getStringForPreedit() == composer.getStringForPreedit())
  #expect(data.getQueryForConversion() == composer.getQueryForConversion())
  #expect(data.getQueryForPrediction() == "ねこ")
  #expect(data.getQueryForPrediction() == composer.getQueryForPrediction())
  #expect(data.getStringForTypeCorrection() == composer.getStringForTypeCorrection())
  #expect(data.getLength() == composer.getLength())
  #expect(data.getCursor() == composer.getCursor())
  #expect(data.getRawString() == composer.getRawString())
  #expect(data.getRawSubString(0, 2) == composer.getRawSubString(0, 2))
  #expect(data.getRawSubString(1, 1) == composer.getRawSubString(1, 1))
  #expect(data.sourceText == composer.sourceText)

  do {  // HandwritingCompositions
    let data_events = data.getHandwritingCompositions()
    let composer_events = composer.getHandwritingCompositions()
    #expect(data_events.count == 2)
    #expect(data_events.count == composer_events.count)
    for i in 0..<data_events.count {
      #expect(data_events[i].compositionString == composer_events[i].compositionString)
      #expect(data_events[i].probability == composer_events[i].probability)
    }
  }

  do {  // Queries for prediction
    // auto = std::pair<std::string, absl::btree_set<std::string>>
    let (data_base, data_expanded) = data.getQueriesForPrediction()

    #expect(data_base == "ねこ")
    #expect(data_expanded.count == 0)

    // auto = std::pair<std::string, absl::btree_set<std::string>>
    let (composer_base, composer_expanded) =
        data.getQueriesForPrediction()
    #expect(data_base == composer_base)
    #expect(data_expanded.count == composer_expanded.count)
    #expect(data_expanded == composer_expanded)  // Empty
  }
}

  @Test func createComposerDataForSourceText() throws {
  let source_text = "再変換用"
  let preedit_text = "さいへんかんよう"
  composer.sourceText = source_text
  composer.setPreeditTextForTestOnly(preedit_text)
  let data = composer.createComposerData()
  #expect(data.getInputMode() == composer.getInputMode())
  #expect(data.getStringForPreedit() == composer.getStringForPreedit())
  #expect(data.getQueryForConversion() == composer.getQueryForConversion())
  #expect(data.getQueryForPrediction() == preedit_text)
  #expect(data.getQueryForPrediction() == composer.getQueryForPrediction())
  #expect(data.getStringForTypeCorrection() == composer.getStringForTypeCorrection())
  #expect(data.getLength() == composer.getLength())
  #expect(data.getCursor() == composer.getCursor())
  #expect(data.getRawString() == composer.getRawString())
  #expect(data.getRawSubString(0, 2) == composer.getRawSubString(0, 2))
  #expect(data.getRawSubString(1, 1) == composer.getRawSubString(1, 1))
  #expect(data.sourceText == source_text)
  #expect(data.sourceText == composer.sourceText)
}

  @Test func createComposerOperators() throws {
  table.addRule("a", "あ", "")
  table.addRule("ka", "か", "")
  table.addRule("ki", "き", "")

  insertKey("a", &composer)
  insertKeyWithMode("a", .fullKatakana, &composer)
  insertKey("k", &composer)

  let data = composer.createComposerData()
  let copied = data
  let moved = data

  #expect(copied.getInputMode() == moved.getInputMode())
  #expect(copied.getStringForPreedit() == moved.getStringForPreedit())
  #expect(copied.getQueryForConversion() == moved.getQueryForConversion())
  #expect(copied.getQueryForPrediction() == moved.getQueryForPrediction())
  #expect(copied.getStringForTypeCorrection() == moved.getStringForTypeCorrection())
  #expect(copied.getLength() == moved.getLength())
  #expect(copied.getCursor() == moved.getCursor())
  #expect(copied.getRawString() == moved.getRawString())
  #expect(copied.getRawSubString(0, 2) == moved.getRawSubString(0, 2))
  #expect(copied.getRawSubString(1, 1) == moved.getRawSubString(1, 1))
  #expect(copied.sourceText == moved.sourceText)
}

  @Test func createEmptyComposerData() throws {
  let data = Composer.emptyComposerData()
  #expect(data.getInputMode() == .hiragana)
  #expect(data.getStringForPreedit() == "")
  #expect(data.getQueryForConversion() == "")
  #expect(data.getQueryForPrediction() == "")
  #expect(data.getStringForTypeCorrection() == "")
  #expect(data.getLength() == 0)
  #expect(data.getCursor() == 0)
  #expect(data.getRawString() == "")
  #expect(data.getRawSubString(0, 2) == "")
  #expect(data.getRawSubString(1, 1) == "")
  #expect(data.sourceText == "")
}
}
