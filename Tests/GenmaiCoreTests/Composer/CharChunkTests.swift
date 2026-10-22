// Port of mozc/src/composer/char_chunk_test.cc (3.35.6354).
//
// The gMock matchers Loop() / NoLoop() / RestIs() / RestIsEmpty() check the
// (should loop, rest of the input) pair returned by addInputInternal().

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

// Transliterators use the CharacterFormManager singleton; each test gets a
// fresh task-local instance.
@Suite(.scopedConfigEnvironment) struct CharChunkTest {
  @Test func addInputCharByChar() throws {
    // Test against http://b/1547858
    let table = Table()
    table.addRule("i", "い", "")
    table.addRule("tt", "っ", "t")
    table.addRule("ta", "た", "")

    var chunk1 = CharChunk(.conversionString, table)
    var result = chunk1.addInputInternal("i")
    #expect(!(result).0)
    #expect(chunk1.isFixed())
    #expect(chunk1.raw == "i")
    #expect(chunk1.conversion == "い")
    #expect(chunk1.pending == "")
    #expect((result).1.isEmpty)

    var chunk2 = CharChunk(.conversionString, table)
    result = chunk2.addInputInternal("t")
    #expect(!(result).0)
    #expect(!chunk2.isFixed())
    #expect(chunk2.raw == "t")
    #expect(chunk2.conversion == "")
    #expect(chunk2.pending == "t")
    #expect((result).1.isEmpty)

    result = chunk2.addInputInternal("t")
    #expect(!(result).0)
    #expect(!chunk2.isFixed())
    #expect(chunk2.raw == "tt")
    #expect(chunk2.conversion == "っ")
    #expect(chunk2.pending == "t")
    #expect((result).1.isEmpty)

    result = chunk2.addInputInternal("a")
    #expect(!(result).0)
    #expect(chunk2.isFixed())
    #expect(chunk2.raw == "tta")
    #expect(chunk2.conversion == "った")
    #expect(chunk2.pending == "")
    #expect((result).1.isEmpty)
  }

  @Test func addInputNoEffectInput() throws {
    let table = Table()
    table.addRule("2", "", "<*>2")
    table.addRule("<*>1", "", "1")
    table.addRule("*", "", "")

    var chunk1 = CharChunk(.conversionString, table)
    var result = chunk1.addInputInternal("2")
    #expect(!(result).0)
    #expect(!chunk1.isFixed())
    #expect(chunk1.raw == "2")
    #expect(chunk1.conversion == "")
    #expect(chunk1.pending == "<*>2")
    #expect((result).1.isEmpty)

    // "<*>2*" is used as a query but no such entry is in the table.
    // Thus AddInputInternal() should not consume the input.
    result = chunk1.addInputInternal("*")
    #expect(!(result).0)
    #expect(!chunk1.isFixed())
    #expect(chunk1.raw == "2")
    #expect(chunk1.conversion == "")
    #expect(chunk1.pending == "<*>2")
    #expect((result).1 == "*")
  }

  @Test func addInputForN() throws {
    let table = Table()
    table.addRule("a", "[A]", "")
    table.addRule("n", "[N]", "")
    table.addRule("nn", "[N]", "")
    table.addRule("na", "[NA]", "")
    table.addRule("nya", "[NYA]", "")
    table.addRule("ya", "[YA]", "")
    table.addRule("ka", "[KA]", "")

    var chunk1 = CharChunk(.conversionString, table)
    var result = chunk1.addInputInternal("n")
    #expect(!(result).0)
    #expect(!chunk1.isFixed())
    #expect(chunk1.raw == "n")
    #expect(chunk1.conversion == "")
    #expect(chunk1.pending == "n")
    #expect((result).1.isEmpty)

    result = chunk1.addInputInternal("y")
    #expect(!(result).0)
    #expect(!chunk1.isFixed())
    #expect(chunk1.raw == "ny")
    #expect(chunk1.conversion == "")
    #expect(chunk1.pending == "ny")
    #expect((result).1.isEmpty)

    result = chunk1.addInputInternal("n")
    #expect(!(result).0)
    #expect(!chunk1.isFixed())
    #expect(chunk1.raw == "ny")
    #expect(chunk1.conversion == "")
    #expect(chunk1.pending == "ny")
    #expect((result).1 == "n")

    result = chunk1.addInputInternal("a")
    #expect(!(result).0)
    #expect(chunk1.isFixed())
    #expect(chunk1.raw == "nya")
    #expect(chunk1.conversion == "[NYA]")
    #expect(chunk1.pending == "")
    #expect((result).1.isEmpty)
  }

  @Test func addInputWithString() throws {
    // Test against http://b/1547858
    let table = Table()
    table.addRule("i", "い", "")
    table.addRule("tt", "っ", "t")
    table.addRule("ta", "た", "")

    var chunk1 = CharChunk(.conversionString, table)
    var result = chunk1.addInputInternal("itta")
    #expect(!(result).0)
    #expect(chunk1.isFixed())
    #expect(chunk1.raw == "i")
    #expect(chunk1.conversion == "い")
    #expect(chunk1.pending == "")
    #expect((result).1 == "tta")

    var chunk2 = CharChunk(.conversionString, table)
    result = chunk2.addInputInternal(result.1)
    #expect((result).0)
    #expect(!chunk2.isFixed())
    #expect(chunk2.raw == "tt")
    #expect(chunk2.conversion == "っ")
    #expect(chunk2.pending == "t")
    #expect((result).1 == "a")

    result = chunk2.addInputInternal(result.1)
    #expect(!(result).0)
    #expect(chunk2.isFixed())
    #expect(chunk2.raw == "tta")
    #expect(chunk2.conversion == "った")
    #expect(chunk2.pending == "")
    #expect((result).1.isEmpty)
  }

  @Test func addInputEmptyOutput() throws {
    // Test against http://b/289217346
    let table = Table()
    table.addRule("a", "", "")
    table.addRuleWithAttributes("b", "", "", .noTransliteration)
    table.addRuleWithAttributes("c", "", "", [.newChunk, .noTransliteration])

    var chunkA = CharChunk(.conversionString, table)
    var resultA = chunkA.addInputInternal("a")
    #expect(resultA.1.isEmpty)
    #expect(chunkA.raw == "a")

    var chunkB = CharChunk(.conversionString, table)
    var resultB = chunkB.addInputInternal("b")
    #expect(resultB.1.isEmpty)
    #expect(chunkB.raw.isEmpty)

    var chunkC = CharChunk(.conversionString, table)
    var resultC = chunkC.addInputInternal("c")
    #expect(resultC.1.isEmpty)
    #expect(chunkC.raw.isEmpty)
  }

  @Test func getLength() throws {
    var chunk1 = CharChunk(.conversionString)
    chunk1.conversion = "ね"
    chunk1.pending = ""
    chunk1.raw = "ne"
    #expect(chunk1.getLength(.conversionString) == 1)
    #expect(chunk1.getLength(.rawString) == 2)

    var chunk2 = CharChunk(.conversionString)
    chunk2.conversion = "っと"
    chunk2.pending = ""
    chunk2.raw = "tto"
    #expect(chunk2.getLength(.conversionString) == 2)
    #expect(chunk2.getLength(.rawString) == 3)

    var chunk3 = CharChunk(.conversionString)
    chunk3.conversion = "が"
    chunk3.pending = ""
    chunk3.raw = "ga"
    #expect(chunk3.getLength(.conversionString) == 1)
    #expect(chunk3.getLength(.rawString) == 2)

    chunk3.setTransliterator(.halfKatakana)
    #expect(chunk3.getLength(.halfKatakana) == 2)
    chunk3.setTransliterator(.halfAscii)
    #expect(chunk3.getLength(.halfAscii) == 2)
  }

  @Test func addCompositionInput() throws {
    let table = Table()
    table.addRule("す゛", "ず", "")

    var chunk1 = CharChunk(.conversionString, table)
    var input = CompositionInput()
    input.initFromRawAndConv("m", "も", false)
    chunk1.addCompositionInput(&input)
    #expect(input.raw.isEmpty)
    #expect(input.conversion.isEmpty)
    #expect(chunk1.raw == "m")
    #expect(chunk1.pending == "も")
    #expect(chunk1.conversion.isEmpty)

    input.initFromRawAndConv("r", "す", false)
    chunk1.addCompositionInput(&input)
    // The input values are not used.
    #expect(input.raw == "r")
    #expect(input.conversion == "す")
    // The chunk remains the previous value.
    #expect(chunk1.raw == "m")
    #expect(chunk1.pending == "も")
    #expect(chunk1.conversion.isEmpty)

    var chunk2 = CharChunk(.conversionString, table)
    // raw == "r", conversion == "す"
    chunk2.addCompositionInput(&input)
    #expect(input.raw.isEmpty)
    #expect(input.conversion.isEmpty)
    #expect(chunk2.raw == "r")
    #expect(chunk2.pending == "す")
    #expect(chunk2.conversion.isEmpty)

    input.initFromRawAndConv("@", "゛", false)
    chunk2.addCompositionInput(&input)
    #expect(input.raw.isEmpty)
    #expect(input.conversion.isEmpty)
    #expect(chunk2.raw == "r@")
    #expect(chunk2.pending.isEmpty)
    #expect(chunk2.conversion == "ず")

    input.initFromRawAndConv("h", "く", false)
    chunk2.addCompositionInput(&input)
    // The input values are not used.
    #expect(input.raw == "h")
    #expect(input.conversion == "く")
    // The chunk remains the previous value.
    #expect(chunk2.raw == "r@")
    #expect(chunk2.pending.isEmpty)
    #expect(chunk2.conversion == "ず")
  }

  @Test func addCompositionInputWithHalfAscii() throws {
    let table = Table()
    table.addRule("-", "ー", "")

    var chunk1 = CharChunk(.conversionString, table)
    var input = CompositionInput()
    input.initFromRawAndConv("-", "-", false)
    chunk1.addCompositionInput(&input)
    #expect(input.raw.isEmpty)
    #expect(input.conversion.isEmpty)
    #expect(chunk1.raw == "-")
    #expect(chunk1.pending == "-")
    #expect(chunk1.conversion.isEmpty)

    input.initFromRawAndConv("-", "-", false)
    chunk1.addCompositionInput(&input)
    // The input values are not used.
    #expect(input.raw == "-")
    #expect(input.conversion == "-")
    // The chunk remains the previous value.
    #expect(chunk1.raw == "-")
    #expect(chunk1.pending == "-")
    #expect(chunk1.conversion.isEmpty)

    var chunk2 = CharChunk(.conversionString, table)
    // key == "-", value == "-"
    chunk2.addCompositionInput(&input)
    #expect(input.raw.isEmpty)
    #expect(input.conversion.isEmpty)
    #expect(chunk2.raw == "-")
    #expect(chunk2.pending == "-")
    #expect(chunk2.conversion.isEmpty)
  }

  @Test func outputMode() throws {
    let table = Table()
    table.addRule("a", "あ", "")

    var chunk = CharChunk(.conversionString, table)
    _ = chunk.addInputInternal("a")

    var result = ""
    chunk.appendResult(.local, &result)
    #expect(result == "あ")

    chunk.setTransliterator(.fullKatakana)
    result = ""
    chunk.appendResult(.local, &result)
    #expect(result == "ア")

    chunk.setTransliterator(.halfAscii)
    result = ""
    chunk.appendResult(.local, &result)
    #expect(result == "a")

    result = ""
    chunk.appendResult(.halfKatakana, &result)
    #expect(result == "ｱ")
  }

  @Test func splitChunk() throws {
    let table = Table()
    table.addRule("mo", "も", "")

    var chunk = CharChunk(.hiragana, table)

    #expect((chunk.addInputInternal("m")).1.isEmpty)

    var output = ""
    chunk.appendResult(.local, &output)
    #expect(output == "ｍ")

    #expect((chunk.addInputInternal("o")).1.isEmpty)

    output = ""
    chunk.appendResult(.local, &output)
    #expect(output == "も")

    chunk.setTransliterator(.halfAscii)
    output = ""
    chunk.appendResult(.local, &output)
    #expect(output == "mo")

    // Split "mo" to "m" and "o".
    let leftChunkOpt = chunk.splitChunk(.local, 1)
    let leftChunk = try #require(leftChunkOpt)

    // The output should be half width "m" rather than full width "ｍ".
    output = ""
    leftChunk.appendResult(.local, &output)
    #expect(output == "m")
  }

  @Test func isAppendable() throws {
    let table = Table()
    table.addRule("mo", "も", "")
    let tableAnother = Table()

    var chunk = CharChunk(.hiragana, table)

    #expect((chunk.addInputInternal("m")).1.isEmpty)
    #expect(chunk.isAppendable(.local, table))
    #expect(chunk.isAppendable(.hiragana, table))
    #expect(!chunk.isAppendable(.fullKatakana, table))
    #expect(!chunk.isAppendable(.local, tableAnother))
    #expect(!chunk.isAppendable(.hiragana, tableAnother))

    #expect((chunk.addInputInternal("o")).1.isEmpty)
    #expect(!chunk.isAppendable(.local, table))
    #expect(!chunk.isAppendable(.hiragana, table))
    #expect(!chunk.isAppendable(.fullKatakana, table))
  }

  @Test func addInputInternal() throws {
    let table = Table()
    table.addRule("tt", "っ", "t")

    var chunk = CharChunk(.conversionString, table)
    do {
      #expect((chunk.addInputInternal("t")).1.isEmpty)
      #expect(chunk.raw == "t")
      #expect(chunk.conversion == "")
      #expect(chunk.pending == "t")
    }
    do {
      #expect((chunk.addInputInternal("t")).1.isEmpty)
      #expect(chunk.raw == "tt")
      #expect(chunk.conversion == "っ")
      #expect(chunk.pending == "t")
    }
    do {
      #expect((chunk.addInputInternal("t")).1.isEmpty)
      #expect(chunk.raw == "ttt")
      #expect(chunk.conversion == "っっ")
      #expect(chunk.pending == "t")
    }
    do {
      #expect((chunk.addInputInternal("!")).1 == "!")
      #expect(chunk.raw == "ttt")
      #expect(chunk.conversion == "っっ")
      #expect(chunk.pending == "t")
    }
  }

  @Test func addInputInternalDifferentPending() throws {
    let table = Table()
    table.addRule("1", "", "あ")
    table.addRule("あ*", "", "ぁ")

    var chunk = CharChunk(.conversionString, table)
    do {
      #expect((chunk.addInputInternal("1")).1.isEmpty)
      #expect(chunk.raw == "1")
      #expect(chunk.conversion == "")
      #expect(chunk.pending == "あ")
    }
    do {
      #expect((chunk.addInputInternal("*")).1.isEmpty)
      #expect(chunk.raw == "1*")
      #expect(chunk.conversion == "")
      #expect(chunk.pending == "ぁ")
    }
  }

  @Test func addInputInternalAmbiguousConversion() throws {
    let table = Table()
    table.addRule("a", "あ", "")
    table.addRule("n", "ん", "")
    table.addRule("nn", "ん", "")
    table.addRule("na", "な", "")
    table.addRule("ya", "や", "")
    table.addRule("nya", "にゃ", "")

    do {
      var chunk = CharChunk(.conversionString, table)

      #expect((chunk.addInputInternal("n")).1.isEmpty)
      #expect(chunk.raw == "n")
      #expect(chunk.conversion == "")
      #expect(chunk.pending == "n")
      #expect(chunk.ambiguous == "ん")

      #expect((chunk.addInputInternal("a")).1.isEmpty)
      #expect(chunk.raw == "na")
      #expect(chunk.conversion == "な")
      #expect(chunk.pending == "")
      #expect(chunk.ambiguous == "")
    }

    do {
      var chunk = CharChunk(.conversionString, table)

      #expect((chunk.addInputInternal("n")).1.isEmpty)
      #expect(chunk.raw == "n")
      #expect(chunk.conversion == "")
      #expect(chunk.pending == "n")
      #expect(chunk.ambiguous == "ん")

      #expect((chunk.addInputInternal("y")).1.isEmpty)
      #expect(chunk.raw == "ny")
      #expect(chunk.conversion == "")
      #expect(chunk.pending == "ny")
      #expect(chunk.ambiguous == "")

      #expect((chunk.addInputInternal("a")).1.isEmpty)
      #expect(chunk.raw == "nya")
      #expect(chunk.conversion == "にゃ")
      #expect(chunk.pending == "")
      #expect(chunk.ambiguous == "")
    }

    do {
      var chunk = CharChunk(.conversionString, table)

      #expect((chunk.addInputInternal("nya")).1.isEmpty)
      #expect(chunk.raw == "nya")
      #expect(chunk.conversion == "にゃ")
      #expect(chunk.pending == "")
      #expect(chunk.ambiguous == "")
    }

    do {
      var chunk = CharChunk(.conversionString, table)

      #expect((chunk.addInputInternal("n")).1.isEmpty)
      #expect(chunk.raw == "n")
      #expect(chunk.conversion == "")
      #expect(chunk.pending == "n")
      #expect(chunk.ambiguous == "ん")

      #expect((chunk.addInputInternal("k")).1 == "k")
      #expect(chunk.raw == "n")
      #expect(chunk.conversion == "ん")
      #expect(chunk.pending == "")
      #expect(chunk.ambiguous == "")
    }

    do {
      var chunk = CharChunk(.conversionString, table)

      #expect((chunk.addInputInternal("nk")).1 == "k")
      #expect(chunk.raw == "n")
      #expect(chunk.conversion == "ん")
      #expect(chunk.pending == "")
      #expect(chunk.ambiguous == "")
    }
  }

  @Test func addInputInternalWithAttributes() throws {
    let table = Table()
    table.addRuleWithAttributes("1", "", "あ", .noTransliteration)
    table.addRule("あ*", "", "ぁ")

    do {
      var chunk = CharChunk(.conversionString, table)

      #expect((chunk.addInputInternal("1")).1.isEmpty)
      #expect(chunk.raw == "1")
      #expect(chunk.conversion == "")
      #expect(chunk.pending == "あ")
      #expect(chunk.attributes == .noTransliteration)

      #expect((chunk.addInputInternal("*")).1.isEmpty)
      #expect(chunk.raw == "1*")
      #expect(chunk.conversion == "")
      #expect(chunk.pending == "ぁ")
      #expect(chunk.attributes == .noTransliteration)
    }

    do {
      var chunk = CharChunk(.conversionString, table)

      #expect((chunk.addInputInternal("1*")).1 == "*")
      #expect(chunk.raw == "1")
      #expect(chunk.conversion == "")
      #expect(chunk.pending == "あ")
      #expect(chunk.attributes == .noTransliteration)

      #expect((chunk.addInputInternal("*")).1.isEmpty)
      #expect(chunk.raw == "1*")
      #expect(chunk.conversion == "")
      #expect(chunk.pending == "ぁ")
      #expect(chunk.attributes == .noTransliteration)
    }

    let table2 = Table()
    table2.addRuleWithAttributes("n", "ん", "", .noTransliteration)
    table2.addRuleWithAttributes("na", "な", "", .directInput)

    do {
      var chunk = CharChunk(.conversionString, table2)

      _ = chunk.addInputInternal("n")
      #expect(chunk.conversion == "")
      #expect(chunk.pending == "n")
      #expect(chunk.ambiguous == "ん")
      #expect(chunk.attributes == .noTransliteration)

      _ = chunk.addInputInternal("a")
      #expect(chunk.conversion == "な")
      #expect(chunk.pending == "")
      #expect(chunk.ambiguous == "")
      #expect(chunk.attributes == .directInput)
    }
  }

  @Test func caseSensitive() throws {
    let table = Table()
    table.addRule("ka", "[ka]", "")
    var chunk = CharChunk(.conversionString, table)

    #expect((chunk.addInputInternal("Ka")).1.isEmpty)
    #expect(chunk.raw == "Ka")
    #expect(chunk.conversion == "[ka]")
    #expect(chunk.pending.isEmpty)
  }

  @Test func trimLeadingSpecialKey() throws {
    let table = Table()
    table.addRule("ああ", "", "い")
    table.addRule("いあ", "", "う")
    table.addRule("あ{!}", "あ", "")
    table.addRule("い{!}", "い", "")
    table.addRule("う{!}", "う", "")
    table.addRule("{#}え", "え", "")

    var input = String(table.parseSpecialKey("ああ{!}{!}あ{!}"))
    do {
      // Check a normal behavior. "ああ{!}" is converted to "い".
      var chunk = CharChunk(.hiragana, table)
      chunk.addInput(&input)
      #expect(input == table.parseSpecialKey("{!}あ{!}"))
      #expect(chunk.raw == table.parseSpecialKey("ああ{!}"))
      #expect(chunk.conversion == "い")
      #expect(chunk.pending == "")
      #expect(chunk.ambiguous == "")
    }
    do {
      // The first "{!}" is erased because:
      // 1. it is a special key.
      // 2. there is no conversion rule starting from "{!}"".
      var chunk = CharChunk(.hiragana, table)
      chunk.addInput(&input)
      #expect(input == "")
      #expect(chunk.raw == table.parseSpecialKey("あ{!}"))
      #expect(chunk.conversion == "あ")
      #expect(chunk.pending == "")
      #expect(chunk.ambiguous == "")
    }

    // {?} is an unused special key.
    input = table.parseSpecialKey("い{?}あ")
    do {
      var chunk = CharChunk(.hiragana, table)
      chunk.addInput(&input)
      #expect(input == table.parseSpecialKey("{?}あ"))
      #expect(chunk.raw == "い")
      #expect(chunk.conversion == "")
      #expect(chunk.pending == "い")
      #expect(chunk.ambiguous == "")

      // {?} is trimed because it is not used by any rules.
      chunk.addInput(&input)
      #expect(input == "")
      #expect(chunk.raw == "いあ")
      #expect(chunk.conversion == "")
      #expect(chunk.pending == "う")
      #expect(chunk.ambiguous == "")
    }

    // {#} is a used special key for "{#}え".
    input = table.parseSpecialKey("い{#}え")
    do {
      var chunk = CharChunk(.hiragana, table)
      chunk.addInput(&input)
      #expect(input == table.parseSpecialKey("{#}え"))
      #expect(chunk.raw == "い")
      #expect(chunk.conversion == "")
      #expect(chunk.pending == "い")
      #expect(chunk.ambiguous == "")

      // No input is used for this already filled chunk.
      chunk.addInput(&input)
      #expect(input == table.parseSpecialKey("{#}え"))
      #expect(chunk.raw == "い")
      #expect(chunk.conversion == "")
      #expect(chunk.pending == "い")
      #expect(chunk.ambiguous == "")
    }
  }

  @Test func leadingSpecialKey() throws {
    let table = Table()
    table.addRule("{!}あ", "い", "")

    var input = String(table.parseSpecialKey("{!}"))

    var chunk = CharChunk(.hiragana, table)
    chunk.addInput(&input)
    #expect(input == "")
    #expect(chunk.raw == table.parseSpecialKey("{!}"))
    #expect(chunk.conversion == "")
    #expect(chunk.pending == table.parseSpecialKey("{!}"))
    #expect(chunk.ambiguous == "")

    input = "あ"
    chunk.addInput(&input)
    #expect(input == "")
    #expect(chunk.raw == table.parseSpecialKey("{!}あ"))
    #expect(chunk.conversion == "い")
    #expect(chunk.pending == "")
    #expect(chunk.ambiguous == "")
  }

  @Test func leadingSpecialKey2() throws {
    let table = Table()
    table.addRule("{henkan}", "", "{r}")
    table.addRule("{r}j", "お", "")

    var usedLength = 0
    var fixed = false
    table.lookUpPrefix(table.parseSpecialKey("{r}j"), &usedLength, &fixed)
    #expect(usedLength == 4)
    #expect(fixed)

    var input = String(table.parseSpecialKey("{henkan}"))

    var chunk = CharChunk(.hiragana, table)
    chunk.addInput(&input)
    #expect(input == "")
    #expect(chunk.raw == table.parseSpecialKey("{henkan}"))
    #expect(chunk.conversion == "")
    #expect(chunk.pending == table.parseSpecialKey("{r}"))
    #expect(chunk.ambiguous == "")

    input = "j"
    chunk.addInput(&input)
    #expect(input == "")
    #expect(chunk.raw == table.parseSpecialKey("{henkan}j"))
    #expect(chunk.conversion == "お")
    #expect(chunk.pending == "")
    #expect(chunk.ambiguous == "")
  }

  @Test func alphanumericOfSSH() throws {
    // This is a unittest against http://b/3199626
    // 'ssh' (っｓｈ) + F10 should be 'ssh'.
    let table = Table()
    table.addRule("ss", "っ", "s")
    table.addRule("shi", "し", "")

    var chunk = CharChunk(.hiragana, table)

    do {
      var input = String("ssh")
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "ssh")
      #expect(chunk.conversion == "っ")
      #expect(chunk.pending == "sh")
      // empty() is intentionaly not used due to check the actual value.
      #expect(chunk.ambiguous == "")
    }
    do {
      var result = ""
      chunk.appendFixedResult(.hiragana, &result)
      #expect(result == "っｓｈ")
    }

    // Break down of the internal procedures
    chunk.clear()
    chunk.setTransliterator(.hiragana)
    do {
      var input = String("s")
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "s")
      // empty() is intentionaly not used due to check the actual value.
      #expect(chunk.conversion == "")
      #expect(chunk.pending == "s")
      #expect(chunk.ambiguous == "")
    }
    do {
      var input = String("s")
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "ss")
      #expect(chunk.conversion == "っ")
      #expect(chunk.pending == "s")
      // empty() is intentionaly not used due to check the actual value.
      #expect(chunk.ambiguous == "")
    }
    do {
      var input = String("h")
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "ssh")
      #expect(chunk.conversion == "っ")
      #expect(chunk.pending == "sh")
      // empty() is intentionaly not used due to check the actual value.
      #expect(chunk.ambiguous == "")
    }
  }

  @Test func shouldCommit() throws {
    let table = Table()
    table.addRuleWithAttributes("ka", "[KA]", "", .directInput)
    table.addRuleWithAttributes("tt", "[X]", "t", .directInput)
    table.addRuleWithAttributes("ta", "[TA]", "", .noTableAttribute)

    do {  // ka - .directInput
      var chunk = CharChunk(.conversionString, table)
      var input = String("k")
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "k")
      #expect(!chunk.shouldCommit())

      input = "a"
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "ka")
      #expect(chunk.conversion == "[KA]")
      #expect(chunk.shouldCommit())
    }

    do {  // ta - .noTableAttribute
      var chunk = CharChunk(.conversionString, table)
      var input = String("t")
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "t")
      #expect(!chunk.shouldCommit())

      input = "a"
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "ta")
      #expect(chunk.conversion == "[TA]")
      #expect(!chunk.shouldCommit())
    }

    do {  // tta - (tt: .directInput / ta: .noTableAttribute)
      var chunk = CharChunk(.conversionString, table)
      var input = String("t")
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "t")
      #expect(!chunk.shouldCommit())

      input = "t"
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "tt")
      #expect(chunk.conversion == "[X]")
      #expect(chunk.pending == "t")
      #expect(!chunk.shouldCommit())

      input = "a"
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "tta")
      #expect(chunk.conversion == "[X][TA]")
      #expect(chunk.pending.isEmpty)
      #expect(chunk.shouldCommit())
    }
  }

  @Test func flickAndToggle() throws {
    let table = Table()
    // Rule for both toggle and flick
    table.addRuleWithAttributes("2", "", "[KA]", .newChunk)
    // Rules for toggle
    table.addRuleWithAttributes("[KA]2", "", "[KI]", .noTableAttribute)
    table.addRuleWithAttributes("[KI]2", "", "[KU]", .noTableAttribute)
    // Rules for flick
    table.addRuleWithAttributes("a", "", "[KI]", .endChunk)
    table.addRuleWithAttributes("b", "", "[KU]", .endChunk)

    do {  // toggle
      var chunk = CharChunk(.conversionString, table)
      var input = String("2")
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "2")

      input = "2"
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "22")

      input = "2"
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "222")
    }

    do {  // flick#1
      var chunk = CharChunk(.conversionString, table)
      var input = String("2")
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "2")

      input = "a"
      #expect(input == "a")
      #expect(chunk.raw == "2")
    }

    do {  // flick#2
      var chunk = CharChunk(.conversionString, table)
      var input = String("a")
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "a")

      input = "b"
      #expect(input == "b")
      #expect(chunk.raw == "a")
    }

    do {  // flick and toggle
      var chunk = CharChunk(.conversionString, table)
      var input = String("a")
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "a")

      input = "2"
      #expect(input == "2")
      #expect(chunk.raw == "a")
    }
  }

  @Test func shouldInsertNewChunk() throws {
    let table = Table()
    table.addRuleWithAttributes("na", "[NA]", "", .noTableAttribute)
    table.addRuleWithAttributes("a", "[A]", "", .newChunk)
    table.addRuleWithAttributes("ni", "[NI]", "", .noTableAttribute)
    table.addRuleWithAttributes("i", "[I]", "", .noTableAttribute)

    var input = CompositionInput()
    var chunk = CharChunk(.conversionString, table)

    do {
      input.raw = "a"
      input.isNewInput = true
      #expect(!chunk.shouldInsertNewChunk(input))
    }

    do {
      input.raw = "a"
      input.isNewInput = false
      #expect(!chunk.shouldInsertNewChunk(input))
    }

    do {
      input.raw = "n"
      input.isNewInput = true
      #expect(!chunk.shouldInsertNewChunk(input))
    }

    chunk.addCompositionInput(&input)
    #expect(input.isEmpty)

    do {
      input.raw = "a"
      input.isNewInput = false
      #expect(!chunk.shouldInsertNewChunk(input))
    }

    do {
      input.raw = "a"
      input.isNewInput = true
      #expect(chunk.shouldInsertNewChunk(input))
    }

    do {
      input.raw = "i"
      input.isNewInput = false
      #expect(!chunk.shouldInsertNewChunk(input))
    }

    do {
      input.raw = "i"
      input.isNewInput = true
      #expect(!chunk.shouldInsertNewChunk(input))
    }

    do {
      input.raw = "z"
      input.isNewInput = false
      #expect(!chunk.shouldInsertNewChunk(input))
    }

    do {
      input.raw = "z"
      input.isNewInput = true
      #expect(chunk.shouldInsertNewChunk(input))
    }
  }

  @Test func addInputCompositionWithConvertedChar() throws {
    let table = Table()
    table.addRuleWithAttributes("na", "[NA]", "", .noTableAttribute)
    table.addRuleWithAttributes("a", "[A]", "", .newChunk)

    do {
      var input = CompositionInput()
      var chunk = CharChunk(.conversionString, table)

      input.raw = "a"
      input.isNewInput = true
      #expect(!chunk.shouldInsertNewChunk(input))

      chunk.addCompositionInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "a")
      #expect(chunk.conversion == "[A]")
      #expect(chunk.pending == "")
    }

    do {
      var input = CompositionInput()
      var chunk = CharChunk(.conversionString, table)

      input.raw = "a"
      input.isNewInput = false
      #expect(!chunk.shouldInsertNewChunk(input))

      chunk.addCompositionInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "a")
      #expect(chunk.conversion == "[A]")
      #expect(chunk.pending == "")
    }

    do {
      var input = CompositionInput()
      var chunk = CharChunk(.conversionString, table)

      input.raw = "n"
      input.isNewInput = true
      #expect(!chunk.shouldInsertNewChunk(input))

      chunk.addCompositionInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "n")
      #expect(chunk.conversion == "")
      #expect(chunk.pending == "n")

      input.raw = "a"
      input.isNewInput = false
      #expect(!chunk.shouldInsertNewChunk(input))

      chunk.addCompositionInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "na")
      #expect(chunk.conversion == "[NA]")
      #expect(chunk.pending == "")
    }

    do {
      var input = CompositionInput()
      var chunk = CharChunk(.conversionString, table)

      input.raw = "n"
      input.isNewInput = true
      #expect(!chunk.shouldInsertNewChunk(input))

      chunk.addCompositionInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.raw == "n")
      #expect(chunk.conversion == "")
      #expect(chunk.pending == "n")

      input.raw = "a"
      input.isNewInput = true
      #expect(chunk.shouldInsertNewChunk(input))

      chunk.addCompositionInput(&input)
      #expect(!input.isEmpty)
      #expect(chunk.raw == "n")
      #expect(chunk.conversion == "")
      #expect(chunk.pending == "n")
      #expect(input.raw == "a")
    }
  }

  @Test func issue2190364() throws {
    // This is a unittest against http://b/2190364
    let table = Table()
    table.addRule("ち゛", "ぢ", "")

    var chunk = CharChunk(.fullAscii, table)
    var input = CompositionInput()
    input.initFromRawAndConv("a", "ち", false)
    chunk.addCompositionInput(&input)

    #expect(input.raw.isEmpty)
    #expect(input.conversion.isEmpty)
    // "ち" can be "ぢ", so it should be appendable.
    #expect(chunk.isAppendable(.local, table))

    do {  // The output should be "ａ".
      var output = ""
      chunk.appendResult(.local, &output)
      #expect(output == "ａ")
    }

    // Space input makes the internal state of chunk, but it is not consumed.
    var key = " "
    chunk.addInput(&key)
    #expect(key == " ")
    #expect(chunk.isAppendable(.local, table))

    do {  // The output should be still "ａ".
      var output = ""
      chunk.appendResult(.local, &output)
      #expect(output == "ａ")
    }
  }

  @Test func issue2209634() throws {
    // This is a unittest against http://b/2209634
    // "q@" becomes "qた@".
    let table = Table()
    table.addRule("q", "", "た")
    table.addRule("た@", "だ", "")

    var chunk = CharChunk(.halfAscii, table)

    var key = "q@"
    chunk.addInput(&key)
    #expect(key.isEmpty)

    var output = ""
    chunk.appendResult(.local, &output)
    #expect(output == "q@")
  }

  @Test func issue2819580() throws {
    // This is an unittest against http://b/2819580.
    // 'y' after 'n' disappears.
    let table = Table()
    table.addRule("po", "ぽ", "")
    table.addRule("n", "ん", "")
    table.addRule("na", "な", "")
    table.addRule("ya", "や", "")
    table.addRule("nya", "にゃ", "")

    // Test for reported situation ("ny").
    // AddInput ver.
    do {
      var chunk = CharChunk(.hiragana, table)

      do {
        var input = String("n")
        chunk.addInput(&input)
      }
      do {
        var input = String("y")
        chunk.addInput(&input)
      }
      do {
        var result = ""
        chunk.appendFixedResult(.hiragana, &result)
        #expect(result == "ｎｙ")
      }

      do {
        var input = String("a")
        chunk.addInput(&input)
      }
      do {
        var result = ""
        chunk.appendFixedResult(.hiragana, &result)
        #expect(result == "にゃ")
      }
    }

    // Test for reported situation (ny) inputs with raw and conversion.
    do {
      var chunk = CharChunk(.hiragana, table)

      do {
        var input = String("n")
        chunk.addInput(&input)
      }
      do {
        var input = String("y")
        chunk.addInput(&input)
      }
      do {
        var input = CompositionInput()
        input.initFromRawAndConv("a", "a", false)
        chunk.addCompositionInput(&input)
      }
      do {
        var result = ""
        chunk.appendFixedResult(.hiragana, &result)
        #expect(result == "にゃ")
      }
    }

    // Test for reported situation ("pony").
    do {
      var chunk = CharChunk(.hiragana, table)

      do {
        var input = String("p")
        chunk.addInput(&input)
      }
      do {
        var input = String("o")
        chunk.addInput(&input)
      }
      do {
        var input = String("n")
        chunk.addInput(&input)
      }
      do {
        var input = String("y")
        chunk.addInput(&input)
      }
      do {
        var result = ""
        chunk.appendFixedResult(.hiragana, &result)
        #expect(result == "ぽｎｙ")
      }

      do {
        var input = String("a")
        chunk.addInput(&input)
      }
      do {
        var result = ""
        chunk.appendFixedResult(.hiragana, &result)
        // "ぽにゃ"
        #expect(result == "ぽにゃ")
      }
    }

    // The first input is not contained in the table.
    do {
      var chunk = CharChunk(.hiragana, table)

      do {
        var input = String("z")
        chunk.addInput(&input)
      }
      do {
        var input = String("n")
        chunk.addInput(&input)
      }
      do {
        var input = String("y")
        chunk.addInput(&input)
      }
      do {
        var result = ""
        chunk.appendFixedResult(.hiragana, &result)
        #expect(result == "ｚｎｙ")
      }
    }
  }

  @Test func issue2990253() throws {
    // http://b/2990253
    // SplitChunk fails.
    // Ambiguous text is left in rhs CharChunk invalidly.
    let table = Table()
    table.addRule("n", "ん", "")
    table.addRule("na", "な", "")
    table.addRule("ya", "や", "")
    table.addRule("nya", "にゃ", "")

    var chunk = CharChunk(.conversionString, table)

    do {
      var input = String("n")
      chunk.addInput(&input)
    }
    do {
      var input = String("y")
      chunk.addInput(&input)
    }

    var leftNewChunk = chunk.splitChunk(.hiragana, 1)
    do {
      var result = ""
      chunk.appendFixedResult(.hiragana, &result)
      #expect(result == "ｙ")
    }
  }

  @Test func combine() throws {
    do {
      var lhs = CharChunk(.conversionString)
      var rhs = CharChunk(.conversionString)
      lhs.ambiguous = "LA"
      lhs.conversion = "LC"
      lhs.pending = "LP"
      lhs.raw = "LR"

      rhs.ambiguous = "RA"
      rhs.conversion = "RC"
      rhs.pending = "RP"
      rhs.raw = "RR"

      rhs.combine(lhs)
      #expect(rhs.ambiguous == "LARA")
      #expect(rhs.conversion == "LCRC")
      #expect(rhs.pending == "LPRP")
      #expect(rhs.raw == "LRRR")
    }

    do {  // lhs' ambiguous is empty.
      var lhs = CharChunk(.conversionString)
      var rhs = CharChunk(.conversionString)

      lhs.ambiguous = ""
      lhs.conversion = "LC"
      lhs.pending = "LP"
      lhs.raw = "LR"

      rhs.ambiguous = "RA"
      rhs.conversion = "RC"
      rhs.pending = "RP"
      rhs.raw = "RR"

      rhs.combine(lhs)
      #expect(rhs.ambiguous == "")
      #expect(rhs.conversion == "LCRC")
      #expect(rhs.pending == "LPRP")
      #expect(rhs.raw == "LRRR")
    }

    do {  // rhs' ambiguous is empty.
      var lhs = CharChunk(.conversionString)
      var rhs = CharChunk(.conversionString)

      lhs.ambiguous = "LA"
      lhs.conversion = "LC"
      lhs.pending = "LP"
      lhs.raw = "LR"

      rhs.ambiguous = ""
      rhs.conversion = "RC"
      rhs.pending = "RP"
      rhs.raw = "RR"

      rhs.combine(lhs)
      #expect(rhs.ambiguous == "LARP")
      #expect(rhs.conversion == "LCRC")
      #expect(rhs.pending == "LPRP")
      #expect(rhs.raw == "LRRR")
    }
  }

  @Test func isConvertible() throws {
    let table = Table()
    table.addRule("n", "ん", "")
    table.addRule("na", "な", "")

    var chunk = CharChunk(.conversionString, table)
    do {
      // If pending is empty, returns false.
      chunk.clear()
      #expect(chunk.pending == "")
      #expect(!chunk.isConvertible(.hiragana, table, "n"))
    }
    do {
      // If t12r is inconsistent, returns false.
      chunk.clear()
      chunk.setTransliterator(.hiragana)
      var input = String("n")
      chunk.addInput(&input)
      #expect(chunk.pending == "n")
      #expect(!chunk.isConvertible(.fullAscii, table, "a"))
    }
    do {
      // If no entries are found from the table, returns false.
      chunk.clear()
      chunk.setTransliterator(.hiragana)
      var input = String("n")
      chunk.addInput(&input)
      #expect(chunk.pending == "n")
      #expect(!chunk.isConvertible(.hiragana, table, "x"))
    }
    do {
      // If found entry does not consume all of input, returns false.
      chunk.clear()
      chunk.setTransliterator(.hiragana)
      var input = String("n")
      chunk.addInput(&input)
      #expect(chunk.pending == "n")
      #expect(!chunk.isConvertible(.hiragana, table, "y"))
    }
    do {
      // [pending='n'] + [input='a'] is convertible (single combination).
      chunk.clear()
      chunk.setTransliterator(.hiragana)
      var input = String("n")
      chunk.addInput(&input)
      #expect(chunk.pending == "n")
      #expect(chunk.isConvertible(.hiragana, table, "a"))
    }
  }

  @Test func specialKeys() throws {
    let table = Table()
    table.addRule("4", "", "[ta]")
    table.addRule("[to]4", "", "[x]{#1}")
    table.addRule("[x]{#1}4", "", "[ta]")

    table.addRule("*", "", "")
    table.addRule("[tu]*", "", "[x]{#2}")
    table.addRule("[x]{#2}*", "", "[tu]")

    do {
      var chunk = CharChunk(.conversionString, table)
      chunk.raw = table.parseSpecialKey("[x]{#1}4")
      chunk.conversion = ""
      chunk.pending = "[ta]"

      var result = ""
      chunk.appendResult(.rawString, &result)
      #expect(result == "[x]4")

      result = ""
      chunk.appendTrimedResult(.rawString, &result)
      #expect(result == "[x]4")

      result = ""
      chunk.appendFixedResult(.rawString, &result)
      #expect(result == "[x]4")

      #expect(chunk.getLength(.rawString) == 4)

      result = ""
      chunk.appendResult(.conversionString, &result)
      #expect(result == "[ta]")

      result = ""
      chunk.appendTrimedResult(.conversionString, &result)
      // Trimed result does not take pending value.
      #expect(result == "")

      result = ""
      chunk.appendFixedResult(.conversionString, &result)
      #expect(result == "[ta]")

      #expect(chunk.getLength(.conversionString) == 4)
    }

    do {
      var chunk = CharChunk(.conversionString, table)
      chunk.raw = "[tu]*"
      chunk.conversion = ""
      chunk.pending = table.parseSpecialKey("[x]{#2}")

      var result = ""
      chunk.appendResult(.rawString, &result)
      #expect(result == "[tu]*")

      result = ""
      chunk.appendTrimedResult(.rawString, &result)
      #expect(result == "[tu]*")

      result = ""
      chunk.appendFixedResult(.rawString, &result)
      #expect(result == "[tu]*")

      #expect(chunk.getLength(.rawString) == 5)

      result = ""
      chunk.appendResult(.conversionString, &result)
      #expect(result == "[x]")

      result = ""
      chunk.appendTrimedResult(.conversionString, &result)
      // Trimed result does not take pending value.
      #expect(result == "")

      result = ""
      chunk.appendFixedResult(.conversionString, &result)
      #expect(result == "[x]")

      #expect(chunk.getLength(.conversionString) == 3)
    }
  }

  @Test func splitChunkWithSpecialKeys() throws {
    let table = Table()
    do {
      var chunk = CharChunk(.conversionString, table)
      chunk.raw = "a"
      chunk.conversion = table.parseSpecialKey("ab{1}cd")

      var leftChunk = chunk.splitChunk(.conversionString, 0)
      #expect(leftChunk == nil)
      #expect(chunk.getLength(.conversionString) == 4)

      leftChunk = chunk.splitChunk(.conversionString, 4)
      #expect(leftChunk == nil)
    }

    do {
      var chunk = CharChunk(.conversionString, table)
      chunk.raw = "a"
      chunk.conversion = table.parseSpecialKey("ab{1}cd")

      let leftChunkOpt = chunk.splitChunk(.conversionString, 1)

      let leftChunk = try #require(leftChunkOpt)
      #expect(leftChunk.conversion == "a")
      #expect(chunk.conversion == "bcd")
    }

    do {
      var chunk = CharChunk(.conversionString, table)
      chunk.raw = "a"
      chunk.conversion = table.parseSpecialKey("ab{1}cd")

      let leftChunkOpt = chunk.splitChunk(.conversionString, 2)

      let leftChunk = try #require(leftChunkOpt)
      #expect(leftChunk.conversion == "ab")
      #expect(chunk.conversion == "cd")
    }

    do {
      var chunk = CharChunk(.conversionString, table)
      chunk.raw = "a"
      chunk.conversion = table.parseSpecialKey("ab{1}cd")

      let leftChunkOpt = chunk.splitChunk(.conversionString, 3)

      let leftChunk = try #require(leftChunkOpt)
      #expect(leftChunk.conversion == "abc")
      #expect(chunk.conversion == "d")
    }
  }

  @Test func noTransliterationAttribute() throws {
    let table = Table()
    table.addRule("ka", "KA", "")
    table.addRuleWithAttributes("sa", "SA", "", .noTransliteration)
    table.addRuleWithAttributes("kk", "x", "k", .noTransliteration)
    table.addRule("ss", "x", "s")

    do {  // "ka" - Default normal behavior.
      var chunk = CharChunk(.rawString, table)
      try #require(chunk.getTransliterator(.local) == .rawString)

      var input = "ka"
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.conversion == "KA")
      #expect(chunk.getTransliterator(.local) == .rawString)
    }

    do {  // "sa" - kConvT12r is set if .noTransliteration is specified
      var chunk = CharChunk(.rawString, table)

      var input = "sa"
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.conversion == "SA")
      #expect(chunk.getTransliterator(.local) == .conversionString)
    }

    do {  // "s" + "a" - Same with the above.
      var chunk = CharChunk(.rawString, table)

      var input = "s"
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.conversion.isEmpty)
      #expect(chunk.getTransliterator(.local) == .rawString)

      input = "a"
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.conversion == "SA")
      #expect(chunk.getTransliterator(.local) == .conversionString)
    }

    do {  // "kka" - The first attribute (.noTransliteration) is used.
      var chunk = CharChunk(.rawString, table)

      var input = "kk"
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.conversion == "x")
      #expect(chunk.getTransliterator(.local) == .conversionString)

      input = "a"
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.conversion == "xKA")
      #expect(chunk.getTransliterator(.local) == .conversionString)
    }

    do {  // "ssa" - The first attribute (default behavior) is used.
      var chunk = CharChunk(.rawString, table)

      var input = "ss"
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.conversion == "x")
      #expect(chunk.getTransliterator(.local) == .rawString)

      input = "a"
      chunk.addInput(&input)
      #expect(input.isEmpty)
      #expect(chunk.conversion == "xSA")
      #expect(chunk.getTransliterator(.local) == .rawString)
    }
  }

  @Test func noTransliterationAttributeForInputAndConvertedChar() throws {
    let table = Table()
    table.addRuleWithAttributes("[ka]@", "[ga]", "", .noTransliteration)
    table.addRuleWithAttributes("[sa]", "[sa]", "", .noTransliteration)
    table.addRule("[sa]@", "[za]", "")

    do {  // "KA" - Default normal behavior.
      var chunk = CharChunk(.rawString, table)
      try #require(chunk.getTransliterator(.local) == .rawString)

      var input = CompositionInput()
      input.initFromRawAndConv("t", "[ka]", false)
      chunk.addCompositionInput(&input)
      #expect(input.raw.isEmpty)
      #expect(input.conversion.isEmpty)
      #expect(chunk.raw == "t")
      #expect(chunk.pending == "[ka]")
      #expect(chunk.getTransliterator(.local) == .rawString)

      // "GA" - The first attribute (default behavior) is used.
      input.initFromRawAndConv("!", "@", false)
      chunk.addCompositionInput(&input)
      #expect(input.raw.isEmpty)
      #expect(input.conversion.isEmpty)
      #expect(chunk.raw == "t!")
      #expect(chunk.pending == "")
      #expect(chunk.conversion == "[ga]")
      #expect(chunk.getTransliterator(.local) == .rawString)
    }

    do {  // "SA" - kConvT12r is set if .noTransliteration is specified.
      var chunk = CharChunk(.rawString, table)

      var input = CompositionInput()
      input.initFromRawAndConv("x", "[sa]", false)
      chunk.addCompositionInput(&input)
      #expect(input.raw.isEmpty)
      #expect(input.conversion.isEmpty)
      #expect(chunk.raw == "x")
      #expect(chunk.pending == "[sa]")
      #expect(chunk.getTransliterator(.local) == .conversionString)

      // "ZA" - The first attribute (.noTransliteration) is used.
      input.initFromRawAndConv("!", "@", false)
      chunk.addCompositionInput(&input)
      #expect(input.raw.isEmpty)
      #expect(input.conversion.isEmpty)
      #expect(chunk.raw == "x!")
      #expect(chunk.pending == "")
      #expect(chunk.conversion == "[za]")
      #expect(chunk.getTransliterator(.local) == .conversionString)
    }
  }

  @Test func romanGetExpandedResults() throws {
    let table = Table()
    table.addRule("kya", "きゃ", "")
    table.addRule("kyi", "きぃ", "")
    table.addRule("kyu", "きゅ", "")
    table.addRule("kye", "きぇ", "")
    table.addRule("kyo", "きょ", "")
    table.addRule("kk", "っ", "k")
    table.addRule("ka", "か", "")
    table.addRule("ki", "き", "")
    table.addRule("ku", "く", "")
    table.addRule("ke", "け", "")
    table.addRule("ko", "こ", "")

    do {
      var chunk = CharChunk(.conversionString, table)
      _ = chunk.addInputInternal("ka")

      var base = ""
      chunk.appendTrimedResult(.local, &base)
      #expect(base == "か")

      let results = chunk.getExpandedResults()
      #expect(results.count == 0)  // no ambiguity
    }
    do {
      var chunk = CharChunk(.conversionString, table)
      _ = chunk.addInputInternal("k")

      var base = ""
      chunk.appendTrimedResult(.local, &base)
      #expect(base == "")

      let results = chunk.getExpandedResults()
      #expect(results.count == 12)
      #expect(results.contains("k"))
      #expect(results.contains("か"))  // ka
      #expect(results.contains("き"))  // ki
      #expect(results.contains("きゃ"))  // kya
      #expect(results.contains("きぃ"))  // kyi
      #expect(results.contains("きゅ"))  // kyu
      #expect(results.contains("きぇ"))  // kye
      #expect(results.contains("きょ"))  // kyo
      #expect(results.contains("く"))  // ku
      #expect(results.contains("け"))  // ke
      #expect(results.contains("こ"))  // ko
      #expect(results.contains("っ"))  // kk
    }
    do {
      var chunk = CharChunk(.conversionString, table)
      _ = chunk.addInputInternal("ky")

      var base = ""
      chunk.appendTrimedResult(.local, &base)
      #expect(base == "")

      let results = chunk.getExpandedResults()
      #expect(results.count == 6)
      #expect(results.contains("ky"))
      #expect(results.contains("きゃ"))
      #expect(results.contains("きぃ"))
      #expect(results.contains("きゅ"))
      #expect(results.contains("きぇ"))
      #expect(results.contains("きょ"))
    }
    do {
      var chunk = CharChunk(.conversionString, table)
      _ = chunk.addInputInternal("kk")

      var base = ""
      chunk.appendTrimedResult(.local, &base)
      #expect(base == "っ")

      let results = chunk.getExpandedResults()
      #expect(results.count == 11)
      #expect(results.contains("か"))  // ka
      #expect(results.contains("き"))  // ki
      #expect(results.contains("きゃ"))  // kya
      #expect(results.contains("きぃ"))  // kyi
      #expect(results.contains("きゅ"))  // kyu
      #expect(results.contains("きぇ"))  // kye
      #expect(results.contains("きょ"))  // kyo
      #expect(results.contains("く"))  // ku
      #expect(results.contains("け"))  // ke
      #expect(results.contains("こ"))  // ko
      #expect(results.contains("っ"))  // kk
    }
  }

  @Test func kanaGetExpandedResults() throws {
    let table = Table()
    table.addRule("か゛", "が", "")
    table.addRule("は゛", "ば", "")
    table.addRule("は゜", "ぱ", "")

    do {
      var chunk = CharChunk(.conversionString, table)
      _ = chunk.addInputInternal("か")

      var base = ""
      chunk.appendTrimedResult(.local, &base)
      #expect(base == "")

      let results = chunk.getExpandedResults()
      #expect(results.count == 2)
      #expect(results.contains("か"))
      #expect(results.contains("が"))
    }
    do {
      var chunk = CharChunk(.conversionString, table)
      _ = chunk.addInputInternal("は")

      var base = ""
      chunk.appendTrimedResult(.local, &base)
      #expect(base == "")

      let results = chunk.getExpandedResults()
      #expect(results.count == 3)
      #expect(results.contains("は"))
      #expect(results.contains("ば"))
      #expect(results.contains("ぱ"))
    }
  }

  @Test func twelveKeyGetExpandedResults() throws {
    let table = Table()
    // It's not the test for the table, but use the real table file
    // for checking it's functionality.
    table.loadFromFile("system://12keys-hiragana.tsv")

    do {
      var chunk = CharChunk(.conversionString, table)
      _ = chunk.addInputInternal("1")

      var base = ""
      chunk.appendTrimedResult(.local, &base)
      #expect(base == "")

      let results = chunk.getExpandedResults()
      #expect(results.count == 2)
      #expect(results.contains("あ"))
      #expect(results.contains("ぁ"))
    }
    do {
      var chunk = CharChunk(.conversionString, table)
      _ = chunk.addInputInternal("8")

      var base = ""
      chunk.appendTrimedResult(.local, &base)
      #expect(base == "")

      let results = chunk.getExpandedResults()
      #expect(results.count == 2)
      #expect(results.contains("や"))
      #expect(results.contains("ゃ"))
    }
    do {
      var chunk = CharChunk(.conversionString, table)
      _ = chunk.addInputInternal("や8")

      var base = ""
      chunk.appendTrimedResult(.local, &base)
      #expect(base == "")

      let results = chunk.getExpandedResults()
      #expect(results.count == 2)
      #expect(results.contains("ゆ"))
      #expect(results.contains("ゅ"))
    }
    do {
      var chunk = CharChunk(.conversionString, table)
      _ = chunk.addInputInternal("6")

      var base = ""
      chunk.appendTrimedResult(.local, &base)
      #expect(base == "")

      let results = chunk.getExpandedResults()
      #expect(results.count == 3)
      #expect(results.contains("は"))
      #expect(results.contains("ば"))
      #expect(results.contains("ぱ"))
    }
  }

  @Test func flickGetExpandedResults() throws {
    let table = Table()
    // It's not the test for the table, but use the real table file
    // for checking it's functionality.
    table.loadFromFile("system://flick-hiragana.tsv")

    do {
      var chunk = CharChunk(.conversionString, table)
      _ = chunk.addInputInternal("1")

      var base = ""
      chunk.appendTrimedResult(.local, &base)
      #expect(base == "")

      let results = chunk.getExpandedResults()
      #expect(results.count == 2)
      #expect(results.contains("あ"))
      #expect(results.contains("ぁ"))
    }
    do {
      var chunk = CharChunk(.conversionString, table)
      _ = chunk.addInputInternal("8")

      var base = ""
      chunk.appendTrimedResult(.local, &base)
      #expect(base == "")

      let results = chunk.getExpandedResults()
      #expect(results.count == 2)
      #expect(results.contains("や"))
      #expect(results.contains("ゃ"))
    }
    do {
      var chunk = CharChunk(.conversionString, table)
      _ = chunk.addInputInternal("u")

      var base = ""
      chunk.appendTrimedResult(.local, &base)
      #expect(base == "")

      let results = chunk.getExpandedResults()
      #expect(results.count == 2)
      #expect(results.contains("ゆ"))
      #expect(results.contains("ゅ"))
    }
    do {
      var chunk = CharChunk(.conversionString, table)
      _ = chunk.addInputInternal("6")

      var base = ""
      chunk.appendTrimedResult(.local, &base)
      #expect(base == "")

      let results = chunk.getExpandedResults()
      #expect(results.count == 3)
      #expect(results.contains("は"))
      #expect(results.contains("ば"))
      #expect(results.contains("ぱ"))
    }
  }

  @Test func noTransliterationIssue3497962() throws {
    let table = Table()
    table.addRuleWithAttributes("2", "", "a", [.newChunk, .noTransliteration])
    table.addRuleWithAttributes("a2", "", "b", .noTableAttribute)
    table.addRuleWithAttributes("b2", "", "c", .noTableAttribute)

    var chunk = CharChunk(.hiragana, table)

    var input = "2"
    chunk.addInput(&input)
    #expect(input.isEmpty)
    #expect(chunk.raw == "2")
    #expect(chunk.conversion == "")
    #expect(chunk.pending == "a")
    #expect(chunk.getTransliterator(.local) == .conversionString)

    input = "2"
    chunk.addInput(&input)
    #expect(input.isEmpty)
    #expect(chunk.raw == "22")
    #expect(chunk.conversion == "")
    #expect(chunk.pending == "b")
    #expect(chunk.getTransliterator(.local) == .conversionString)
  }

  @Test func copy() throws {
    let table = Table()
    var src = CharChunk(.hiragana, table)
    src.raw = "raw"
    src.conversion = "conversion"
    src.pending = "pending"
    src.ambiguous = "ambiguous"
    src.attributes = .newChunk

    let copy = src
    #expect(copy.transliterator == src.transliterator)
    #expect(src.tableForTesting === copy.tableForTesting)
    #expect(copy.raw == src.raw)
    #expect(copy.conversion == src.conversion)
    #expect(copy.pending == src.pending)
    #expect(copy.ambiguous == src.ambiguous)
    #expect(copy.attributes == src.attributes)

    var assigned = CharChunk(.halfAscii)
    assigned = src
    #expect(assigned.transliterator == src.transliterator)
    #expect(src.tableForTesting === assigned.tableForTesting)
    #expect(assigned.raw == src.raw)
    #expect(assigned.conversion == src.conversion)
    #expect(assigned.pending == src.pending)
    #expect(assigned.ambiguous == src.ambiguous)
    #expect(assigned.attributes == src.attributes)
  }

  @Test func getTransliterator() throws {
    let table = Table()

    // Non-local vs non-local.
    // Given parametes should be returned.
    for t12r1 in Transliterators.Transliterator.allCases {
      if t12r1 == .local {
        continue
      }
      var chunk = CharChunk(t12r1, table)
      for t12r2 in Transliterators.Transliterator.allCases {
        if t12r2 == .local {
          continue
        }
        #expect(chunk.getTransliterator(t12r2) == t12r2)
      }
    }

    // Non-local vs local.
    // Constructor parameter should be returned.
    for t12r in Transliterators.Transliterator.allCases {
      if t12r == .local {
        continue
      }
      var chunk = CharChunk(t12r, table)
      #expect(chunk.getTransliterator(.local) == t12r)
    }

    // Non-local (with .noTransliteration attr) vs local.
    // If .noTransliteration is set, returns CONVERSION_STRING always.
    for t12r in Transliterators.Transliterator.allCases {
      if t12r == .local {
        continue
      }
      var chunk = CharChunk(t12r, table)
      chunk.attributes = .noTransliteration
      #expect(chunk.getTransliterator(.local) == .conversionString)
    }
  }
}
