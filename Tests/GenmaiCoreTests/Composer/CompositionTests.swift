// Port of mozc/src/composer/composition_test.cc (3.35.6354).
//
// Notes:
// - The C++ fixture (table_, composition_) is a class suite with `table` and
//   `composition`; Swift Testing creates a new instance for every test.
// - std::list iterators are array indices in the Swift Composition. Where the
//   C++ test keeps a `CharChunk&` obtained from an iterator, the Swift test
//   keeps the index and mutates the chunk through `mutableChunks`.
// - `static_cast<size_t>(-1)` positions are passed as `Int.max`.

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private func getRawString(_ composition: Composition) -> String {
  composition.getStringWithTransliterator(.rawString)
}

@discardableResult
private func insertCharacters(_ input: String, _ pos: Int, _ composition: inout Composition) -> Int {
  var pos = pos
  for c in input.utf8 {
    pos = composition.insertAt(pos, String(UnicodeScalar(c)))
  }
  return pos
}

private struct TestCharChunk {
  var conversion: String
  var pending: String
  var raw: String
}

@discardableResult
private func initComposition(_ comp: inout Composition) -> Int {
  let testChunks = [
    // "あ ky き った っty"  (9 chars)
    // a ky ki tta tty
    TestCharChunk(conversion: "あ", pending: "", raw: "a"),
    TestCharChunk(conversion: "", pending: "ky", raw: "ky"),
    TestCharChunk(conversion: "き", pending: "", raw: "ki"),
    TestCharChunk(conversion: "った", pending: "", raw: "tta"),
    TestCharChunk(conversion: "っ", pending: "ty", raw: "tty"),
  ]
  // In C++ `it` stays at the same element (end()), so every chunk is inserted
  // before it, i.e. appended in order. With indices, `it` moves forward.
  var it = comp.maybeSplitChunkAt(0)
  for data in testChunks {
    let index = comp.insertChunk(it)
    it = index + 1
    comp.mutableChunks[index].conversion = data.conversion
    comp.mutableChunks[index].pending = data.pending
    comp.mutableChunks[index].raw = data.raw
  }
  return testChunks.count
}

/// Returns the index of the appended chunk (`CharChunk&` in C++).
@discardableResult
private func appendChunk(
  _ conversion: String, _ pending: String, _ raw: String, _ comp: inout Composition
) -> Int {
  let it = comp.maybeSplitChunkAt(comp.getLength())

  let index = comp.insertChunk(it)
  comp.mutableChunks[index].conversion = conversion
  comp.mutableChunks[index].pending = pending
  comp.mutableChunks[index].raw = raw
  return index
}

private func testGetChunkAt(
  _ comp: Composition, _ transliterator: Transliterators.Transliterator, _ index: Int,
  _ expectedIndex: Int, _ expectedInnerPosition: Int,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  let expectedIt = expectedIndex

  var innerPosition = 0
  let it = comp.getChunkAt(index, transliterator, &innerPosition)
  if it == comp.getCharChunkList().count {
    #expect(expectedIt == it, sourceLocation: sourceLocation)
    #expect(innerPosition == expectedInnerPosition, sourceLocation: sourceLocation)
  } else {
    let chunks = comp.getCharChunkList()
    #expect(chunks[it].conversion == chunks[expectedIt].conversion, sourceLocation: sourceLocation)
    #expect(chunks[it].pending == chunks[expectedIt].pending, sourceLocation: sourceLocation)
    #expect(chunks[it].raw == chunks[expectedIt].raw, sourceLocation: sourceLocation)
    #expect(innerPosition == expectedInnerPosition, sourceLocation: sourceLocation)
  }
}

private func getDeletedString(_ t12r: Transliterators.Transliterator, _ position: Int) -> String {
  let table = Table()
  var comp = Composition(table)

  initComposition(&comp)
  comp.setDisplayMode(0, t12r)
  comp.deleteAt(position)
  return comp.getString()
}

private func initTable(_ table: Table) {
  table.addRule("i", "い", "")
  table.addRule("ki", "き", "")
  table.addRule("kyi", "きぃ", "")
  table.addRule("ti", "ち", "")
  table.addRule("tya", "ちゃ", "")
  table.addRule("tyi", "ちぃ", "")
  table.addRule("ya", "や", "")
  table.addRule("yy", "っ", "y")
}

private func getInsertedString(
  _ t12r: Transliterators.Transliterator, _ position: Int, _ input: String
) -> String {
  let table = Table()
  initTable(table)
  var comp = Composition(table)
  initComposition(&comp)

  comp.setTable(table)
  comp.setDisplayMode(0, t12r)
  _ = comp.insertAt(position, input)

  return comp.getString()
}

private struct SplitTestCase {
  var conversion: String
  var pending: String
  var raw: String
  var position: Int
  var expectedLeftConversion: String
  var expectedLeftPending: String
  var expectedLeftRaw: String
  var expectedRightConversion: String
  var expectedRightPending: String
  var expectedRightRaw: String

  init(
    _ conversion: String, _ pending: String, _ raw: String, _ position: Int,
    _ expectedLeftConversion: String, _ expectedLeftPending: String, _ expectedLeftRaw: String,
    _ expectedRightConversion: String, _ expectedRightPending: String, _ expectedRightRaw: String
  ) {
    self.conversion = conversion
    self.pending = pending
    self.raw = raw
    self.position = position
    self.expectedLeftConversion = expectedLeftConversion
    self.expectedLeftPending = expectedLeftPending
    self.expectedLeftRaw = expectedLeftRaw
    self.expectedRightConversion = expectedRightConversion
    self.expectedRightPending = expectedRightPending
    self.expectedRightRaw = expectedRightRaw
  }
}

// Transliterators use the CharacterFormManager singleton; each test gets a
// fresh task-local instance.
@Suite(.scopedConfigEnvironment) final class CompositionTest {
  let table: Table
  var composition: Composition

  init() {
    table = Table()
    composition = Composition(table)
    composition.setInputMode(.conversionString)
  }

  func setInput(
    _ raw: String, _ conversion: String, _ isNewInput: Bool, _ input: inout CompositionInput
  ) {
    input.clear()
    input.raw = table.parseSpecialKey(raw)
    if !conversion.isEmpty {
      input.conversion = conversion
    }
    input.isNewInput = isNewInput
  }

  @Test func getChunkLength() throws {
    struct TestCase {
      var conversion: String
      var pending: String
      var raw: String
      var expectedConvLength: Int
      var expectedRawLength: Int
    }
    let testCases = [
      TestCase(conversion: "あ", pending: "", raw: "a", expectedConvLength: 1, expectedRawLength: 1),
      TestCase(conversion: "", pending: "ky", raw: "ky", expectedConvLength: 2, expectedRawLength: 2),
      TestCase(conversion: "き", pending: "", raw: "ki", expectedConvLength: 1, expectedRawLength: 2),
      TestCase(
        conversion: "った", pending: "", raw: "tta", expectedConvLength: 2, expectedRawLength: 3),
      TestCase(
        conversion: "っ", pending: "ty", raw: "tty", expectedConvLength: 3, expectedRawLength: 3),
    ]
    let index = appendChunk("", "", "", &composition)

    for test in testCases {
      composition.mutableChunks[index].conversion = test.conversion
      composition.mutableChunks[index].pending = test.pending
      composition.mutableChunks[index].raw = test.raw
      let chunk = composition.chunks[index]

      let convLength = chunk.getLength(.conversionString)
      #expect(convLength == test.expectedConvLength)

      let rawLength = chunk.getLength(.rawString)
      #expect(rawLength == test.expectedRawLength)
    }
  }

  @Test func getChunkAt() throws {
    initComposition(&composition)

    testGetChunkAt(composition, .conversionString, 0, 0, 0)
    testGetChunkAt(composition, .conversionString, 1, 0, 1)
    testGetChunkAt(composition, .conversionString, 2, 1, 1)
    testGetChunkAt(composition, .conversionString, 3, 1, 2)
    testGetChunkAt(composition, .conversionString, 4, 2, 1)
    testGetChunkAt(composition, .conversionString, 5, 3, 1)
    testGetChunkAt(composition, .conversionString, 6, 3, 2)
    testGetChunkAt(composition, .conversionString, 7, 4, 1)
    testGetChunkAt(composition, .conversionString, 8, 4, 2)
    testGetChunkAt(composition, .conversionString, 9, 4, 3)
    // end
    testGetChunkAt(composition, .conversionString, 10, 4, 3)
    // end
    testGetChunkAt(composition, .conversionString, 11, 4, 3)

    testGetChunkAt(composition, .rawString, 0, 0, 0)
    testGetChunkAt(composition, .rawString, 1, 0, 1)
    testGetChunkAt(composition, .rawString, 2, 1, 1)
    testGetChunkAt(composition, .rawString, 3, 1, 2)
    testGetChunkAt(composition, .rawString, 4, 2, 1)
    testGetChunkAt(composition, .rawString, 5, 2, 2)
    testGetChunkAt(composition, .rawString, 6, 3, 1)
    testGetChunkAt(composition, .rawString, 7, 3, 2)
    testGetChunkAt(composition, .rawString, 8, 3, 3)
    testGetChunkAt(composition, .rawString, 9, 4, 1)
    testGetChunkAt(composition, .rawString, 10, 4, 2)
    testGetChunkAt(composition, .rawString, 11, 4, 3)
    // end
    testGetChunkAt(composition, .rawString, 12, 4, 3)
    // end
    testGetChunkAt(composition, .rawString, 13, 4, 3)
  }

  @Test func getString() throws {
    initComposition(&composition)

    let dummyPosition = 0

    // Test RAW mode
    composition.setDisplayMode(dummyPosition, .rawString)
    var compositionString = composition.getString()
    #expect(compositionString == "akykittatty")

    // Test CONVERSION mode
    composition.setDisplayMode(dummyPosition, .conversionString)
    compositionString = composition.getString()
    #expect(compositionString == "あkyきったっty")
  }

  @Test func getStringWithDisplayMode() throws {
    appendChunk("も", "", "mo", &composition)
    appendChunk("ず", "", "z", &composition)
    appendChunk("く", "", "c", &composition)

    var compositionString = composition.getStringWithTransliterator(.conversionString)
    #expect(compositionString == "もずく")

    compositionString = composition.getStringWithTransliterator(.rawString)
    #expect(compositionString == "mozc")
  }

  private func checkSplit(_ testCases: [SplitTestCase], _ t12r: Transliterators.Transliterator) {
    for test in testCases {
      var rightOrigChunk = CharChunk(.conversionString, table)
      rightOrigChunk.conversion = test.conversion
      rightOrigChunk.pending = test.pending
      rightOrigChunk.raw = test.raw
      let leftNewChunk = rightOrigChunk.splitChunk(t12r, test.position)

      if let leftNewChunk {
        #expect(leftNewChunk.conversion == test.expectedLeftConversion)
        #expect(leftNewChunk.pending == test.expectedLeftPending)
        #expect(leftNewChunk.raw == test.expectedLeftRaw)
      }

      #expect(rightOrigChunk.conversion == test.expectedRightConversion)
      #expect(rightOrigChunk.pending == test.expectedRightPending)
      #expect(rightOrigChunk.raw == test.expectedRightRaw)
    }
  }

  @Test func splitRawChunk() throws {
    let testCases = [
      SplitTestCase("あ", "", "a", 0, "", "", "", "あ", "", "a"),
      SplitTestCase("", "ky", "ky", 1, "", "k", "k", "", "y", "y"),
      SplitTestCase("き", "", "ki", 1, "k", "", "k", "i", "", "i"),
      SplitTestCase("った", "", "tta", 1, "t", "", "t", "ta", "", "ta"),
      SplitTestCase("った", "", "tta", 2, "tt", "", "tt", "a", "", "a"),
      SplitTestCase("っ", "ty", "tty", 1, "っ", "", "t", "", "ty", "ty"),
      SplitTestCase("っ", "ty", "tty", 2, "っ", "t", "tt", "", "y", "y"),
      SplitTestCase("っ", "ty", "tty", 3, "", "", "", "っ", "ty", "tty"),
    ]
    checkSplit(testCases, .rawString)
  }

  @Test func splitConversionChunk() throws {
    let testCases = [
      SplitTestCase("あ", "", "a", 0, "", "", "", "あ", "", "a"),
      SplitTestCase("", "ky", "ky", 1, "", "k", "k", "", "y", "y"),
      SplitTestCase("きょ", "", "kyo", 1, "き", "", "き", "ょ", "", "ょ"),
      SplitTestCase("っ", "t", "tt", 1, "っ", "", "t", "", "t", "t"),
      SplitTestCase("った", "", "tta", 1, "っ", "", "っ", "た", "", "た"),
      SplitTestCase("っ", "ty", "tty", 1, "っ", "", "t", "", "ty", "ty"),
      SplitTestCase("っ", "ty", "tty", 2, "っ", "t", "tt", "", "y", "y"),
      SplitTestCase("っ", "ty", "tty", 3, "", "", "", "っ", "ty", "tty"),
    ]
    checkSplit(testCases, .conversionString)
  }

  @Test func getLength() throws {
    table.addRule("a", "A", "")
    table.addRule("ka", "K", "")

    #expect(composition.getLength() == 0)

    insertCharacters("aka", 0, &composition)
    #expect(composition.getLength() == 2)
  }

  @Test func maybeSplitChunkAt() throws {
    let testCases: [(position: Int, expectedRawChunksSize: Int, expectedConvChunksSize: Int)] = [
      // "あ ky き った っty"  (9 chars)
      // a ky ki tta tty (11 chars)
      (0, 5, 5), (1, 5, 5), (2, 6, 6), (3, 5, 5), (4, 6, 5),
      (5, 5, 6), (6, 6, 5), (7, 6, 6), (8, 5, 6), (9, 6, 5),
      (10, 6, 5), (11, 5, 5), (12, 5, 5),
    ]
    let dummyPosition = 0
    for test in testCases {
      do {  // Test RAW mode
        var rawComp = Composition(table)
        initComposition(&rawComp)
        rawComp.setDisplayMode(dummyPosition, .rawString)
        _ = rawComp.maybeSplitChunkAt(test.position)
        let rawChunksSize = rawComp.getCharChunkList().count
        #expect(rawChunksSize == test.expectedRawChunksSize, "position: \(test.position)")
      }

      do {  // Test CONVERSION mode
        var convComp = Composition(table)
        initComposition(&convComp)
        convComp.setDisplayMode(dummyPosition, .conversionString)
        _ = convComp.maybeSplitChunkAt(test.position)
        let convChunksSize = convComp.getCharChunkList().count
        #expect(convChunksSize == test.expectedConvChunksSize, "position: \(test.position)")
      }
    }
  }

  @Test func deleteAt() throws {
    // "あkyきったっty" is the original string
    #expect(getDeletedString(.conversionString, 0) == "kyきったっty")
    #expect(getDeletedString(.conversionString, 1) == "あyきったっty")
    #expect(getDeletedString(.conversionString, 2) == "あkきったっty")
    #expect(getDeletedString(.conversionString, 3) == "あkyったっty")
    #expect(getDeletedString(.conversionString, 4) == "あkyきたっty")
    #expect(getDeletedString(.conversionString, 5) == "あkyきっっty")
    #expect(getDeletedString(.conversionString, 6) == "あkyきったty")
    #expect(getDeletedString(.conversionString, 7) == "あkyきったっy")
    #expect(getDeletedString(.conversionString, 8) == "あkyきったっt")
    // end
    #expect(getDeletedString(.conversionString, 9) == "あkyきったっty")
    // -1 as size_t.
    #expect(getDeletedString(.conversionString, Int.max) == "あkyきったっty")

    // "akykittatty" is the original string
    #expect(getDeletedString(.rawString, 0) == "kykittatty")
    #expect(getDeletedString(.rawString, 1) == "aykittatty")
    #expect(getDeletedString(.rawString, 2) == "akkittatty")
    #expect(getDeletedString(.rawString, 3) == "akyittatty")
    #expect(getDeletedString(.rawString, 4) == "akykttatty")
    #expect(getDeletedString(.rawString, 5) == "akykitatty")
    #expect(getDeletedString(.rawString, 6) == "akykitatty")
    #expect(getDeletedString(.rawString, 7) == "akykitttty")
    #expect(getDeletedString(.rawString, 8) == "akykittaty")
    #expect(getDeletedString(.rawString, 9) == "akykittaty")
    #expect(getDeletedString(.rawString, 10) == "akykittatt")
    // end
    #expect(getDeletedString(.rawString, 11) == "akykittatty")
    // -1 as size_t.
    #expect(getDeletedString(.rawString, Int.max) == "akykittatty")
  }

  @Test func deleteAtInvisibleCharacter() throws {
    func initChunk(_ composition: inout Composition, _ data: [(String, String)]) {
      composition.erase()
      var it = composition.maybeSplitChunkAt(0)
      for item in data {
        let index = composition.insertChunk(it)
        it = index + 1
        composition.mutableChunks[index].raw = table.parseSpecialKey(item.0)
        composition.mutableChunks[index].pending = table.parseSpecialKey(item.1)
      }
    }

    do {
      initChunk(&composition, [("1", "{1}"), ("2", "{2}2"), ("3", "3")])

      // Now the CharChunks in the comp are expected to be following;
      // (raw, pending) = [ ("1", "{1}"), ("2", "{2}2"), ("3", "3") ]
      // {} means invisible characters.

      composition.deleteAt(0)
      let compositionString = composition.getString()
      #expect(compositionString == "3")
      #expect(composition.getCharChunkList().count == 1)
    }
    do {
      initChunk(&composition, [("1", "{1}"), ("2", "{2}2"), ("3", "3")])

      composition.deleteAt(1)
      let compositionString = composition.getString()
      #expect(compositionString == "2")
      let chunks = composition.getCharChunkList()
      try #require(chunks.count == 2)
      let chunk0 = chunks[0]
      #expect(chunk0.raw == "1")
      #expect(chunk0.pending == table.parseSpecialKey("{1}"))
      let chunk1 = chunks[1]
      #expect(chunk1.raw == "2")
      #expect(chunk1.pending == table.parseSpecialKey("{2}2"))
    }

    do {
      initChunk(&composition, [("1", "{1}"), ("2", "2{2}"), ("3", "3")])

      composition.deleteAt(0)
      let compositionString = composition.getString()
      // 0-th character is "2".
      // As "{1}" is a character between the head and "2", it is removed.
      // All "2{2}" is also removed because they are in the same chunk.
      #expect(compositionString == "3")
      #expect(composition.getCharChunkList().count == 1)
    }

    do {
      initChunk(&composition, [("1", "{1}"), ("2", "2{2}"), ("3", "{3}")])

      composition.deleteAt(0)
      let compositionString = composition.getString()
      #expect(compositionString == "")
      try #require(composition.getCharChunkList().count == 1)
      #expect(composition.getCharChunkList()[0].raw == "3")
    }
  }

  @Test func insertAt() throws {
    // "あkyきったっty" is the original string
    #expect(getInsertedString(.conversionString, 0, "i") == "いあkyきったっty")
    #expect(getInsertedString(.conversionString, 1, "i") == "あいkyきったっty")
    #expect(getInsertedString(.conversionString, 2, "i") == "あきyきったっty")
    #expect(getInsertedString(.conversionString, 3, "i") == "あきぃきったっty")
    #expect(getInsertedString(.conversionString, 4, "i") == "あkyきいったっty")
    #expect(getInsertedString(.conversionString, 5, "i") == "あkyきっいたっty")
    #expect(getInsertedString(.conversionString, 9, "i") == "あkyきったっちぃ")
    #expect(getInsertedString(.conversionString, 0, "y") == "yあkyきったっty")
    #expect(getInsertedString(.conversionString, 1, "y") == "あykyきったっty")
    #expect(getInsertedString(.conversionString, 2, "y") == "あkyyきったっty")
    #expect(getInsertedString(.conversionString, 3, "y") == "あkyyきったっty")
    #expect(getInsertedString(.conversionString, 4, "y") == "あkyきyったっty")
    #expect(getInsertedString(.conversionString, 5, "y") == "あkyきっyたっty")
    // end
    #expect(getInsertedString(.conversionString, 9, "i") == "あkyきったっちぃ")
    // end
    #expect(getInsertedString(.conversionString, 9, "y") == "あkyきったっtyy")

    // "akykittatty" is the original string
    #expect(getInsertedString(.rawString, 0, "i") == "iakykittatty")

    #expect(getInsertedString(.rawString, 1, "i") == "aikykittatty")

    #expect(getInsertedString(.rawString, 2, "i") == "akiykittatty")

    #expect(getInsertedString(.rawString, 3, "i") == "akyikittatty")

    #expect(getInsertedString(.rawString, 4, "i") == "akykiittatty")

    #expect(getInsertedString(.rawString, 5, "i") == "akykiittatty")

    #expect(getInsertedString(.rawString, 11, "i") == "akykittattyi")  // end
  }

  @Test func getExpandedStrings() throws {
    initTable(table)
    initComposition(&composition)

    // a ky ki tta tty
    let (base, expanded) = composition.getExpandedStrings()
    #expect(base == "あkyきったっ")
    #expect(expanded.count == 2)
    // You cannot use EXPECT_NE here because it causes compile error in gtest
    // when the compiler is Visual C++. b/5655673
    #expect(expanded.contains("ちぃ"))
    // You cannot use EXPECT_NE here because it causes compile error in gtest
    // when the compiler is Visual C++. b/5655673
    #expect(expanded.contains("ちゃ"))
  }

  @Test func convertPosition() throws {
    // Test against http://b/1550597

    // Invalid positions.
    #expect(composition.convertPosition(Int.max, .conversionString, .rawString) == 0)
    #expect(composition.convertPosition(0, .conversionString, .rawString) == 0)
    #expect(composition.convertPosition(1, .conversionString, .rawString) == 0)
    #expect(composition.convertPosition(0, .rawString, .conversionString) == 0)
    #expect(composition.convertPosition(Int.max, .rawString, .conversionString) == 0)
    #expect(composition.convertPosition(1, .rawString, .conversionString) == 0)

    appendChunk("ね", "", "ne", &composition)
    appendChunk("っと", "", "tto", &composition)

    // "|ねっと" -> "|netto"
    #expect(composition.convertPosition(0, .conversionString, .rawString) == 0)
    // "ね|っと" -> "ne|tto"
    #expect(composition.convertPosition(1, .conversionString, .rawString) == 2)
    // "ねっ|と" -> "net|to"
    #expect(composition.convertPosition(2, .conversionString, .rawString) == 3)
    // "ねっと|" -> "netto|"
    #expect(composition.convertPosition(3, .conversionString, .rawString) == 5)

    // Invalid positions.
    #expect(composition.convertPosition(Int.max, .conversionString, .rawString) == 5)
    #expect(composition.convertPosition(4, .conversionString, .rawString) == 5)

    // "|netto" -> "|ねっと"
    #expect(composition.convertPosition(0, .rawString, .conversionString) == 0)
    // "n|etto" -> "ね|っと"
    #expect(composition.convertPosition(1, .rawString, .conversionString) == 1)
    // "ne|tto" -> "ね|っと"
    #expect(composition.convertPosition(2, .rawString, .conversionString) == 1)
    // "net|to" -> "ねっ|と"
    #expect(composition.convertPosition(3, .rawString, .conversionString) == 2)
    // "nett|o" -> "ねっと|"
    #expect(composition.convertPosition(4, .rawString, .conversionString) == 3)
    // "netto|" -> "ねっと|"
    #expect(composition.convertPosition(5, .rawString, .conversionString) == 3)
    // Invalid positions.
    #expect(composition.convertPosition(Int.max, .rawString, .conversionString) == 3)
    #expect(composition.convertPosition(6, .rawString, .conversionString) == 3)

    var innerPosition = 0
    let chunkIt = composition.getChunkAt(5, .rawString, &innerPosition)

    #expect(composition.chunks[chunkIt].raw == "tto")
    #expect(innerPosition == 3)
  }

  @Test func setDisplayMode() throws {
    appendChunk("も", "", "mo", &composition)
    appendChunk("ず", "", "zu", &composition)
    appendChunk("く", "", "ku", &composition)

    var innerPosition = 0
    var chunkIt = composition.getChunkAt(0, .conversionString, &innerPosition)
    #expect(composition.chunks[chunkIt].raw == "mo")
    #expect(innerPosition == 0)
    chunkIt = composition.getChunkAt(1, .conversionString, &innerPosition)
    #expect(composition.chunks[chunkIt].raw == "mo")
    #expect(innerPosition == 1)
    chunkIt = composition.getChunkAt(2, .conversionString, &innerPosition)
    #expect(composition.chunks[chunkIt].raw == "zu")
    #expect(innerPosition == 1)
    chunkIt = composition.getChunkAt(3, .conversionString, &innerPosition)
    #expect(composition.chunks[chunkIt].raw == "ku")
    #expect(innerPosition == 1)

    #expect(composition.setDisplayMode(1, .rawString) == 6)
    #expect(composition.setDisplayMode(2, .conversionString) == 3)
    #expect(composition.setDisplayMode(2, .rawString) == 6)
  }

  @Test func getStringWithTrimMode() throws {
    table.addRule("ka", "か", "")
    table.addRule("n", "ん", "")
    // This makes the above rule ambiguous.
    table.addRule("na", "な", "")

    let outputEmpty = composition.getStringWithTrimMode(.trim)
    #expect(outputEmpty.isEmpty)

    var pos = 0
    pos = composition.insertAt(pos, "k")
    pos = composition.insertAt(pos, "a")
    pos = composition.insertAt(pos, "n")

    let outputTrim = composition.getStringWithTrimMode(.trim)
    #expect(outputTrim == "か")

    let outputAsis = composition.getStringWithTrimMode(.asis)
    #expect(outputAsis == "かn")

    let outputFix = composition.getStringWithTrimMode(.fix)
    #expect(outputFix == "かん")
  }

  @Test func insertKeyAndPreeditAt() throws {
    table.addRule("す゛", "ず", "")
    table.addRule("く゛", "ぐ", "")

    var pos = 0
    pos = composition.insertKeyAndPreeditAt(pos, "m", "も")
    pos = composition.insertKeyAndPreeditAt(pos, "r", "す")
    pos = composition.insertKeyAndPreeditAt(pos, "@", "゛")
    pos = composition.insertKeyAndPreeditAt(pos, "h", "く")
    pos = composition.insertKeyAndPreeditAt(pos, "!", "!")

    let compStr = composition.getString()
    #expect(compStr == "もずく!")

    let compAsciiStr = composition.getStringWithTransliterator(.rawString)
    #expect(compAsciiStr == "mr@h!")
  }

  @Test func insertKeyForN() throws {
    table.addRule("a", "[A]", "")
    table.addRule("n", "[N]", "")
    table.addRule("nn", "[N]", "")
    table.addRule("na", "[NA]", "")
    table.addRule("nya", "[NYA]", "")
    table.addRule("ya", "[YA]", "")
    table.addRule("ka", "[KA]", "")

    var pos = 0
    pos = composition.insertAt(pos, "n")
    pos = composition.insertAt(pos, "y")
    pos = composition.insertAt(pos, "n")
    pos = composition.insertAt(pos, "y")
    pos = composition.insertAt(pos, "a")

    let compStr = composition.getString()
    #expect(compStr == "ny[NYA]")
  }

  @Test func getStringWithDisplayModeForKana() throws {
    var pos = 0
    pos = composition.insertKeyAndPreeditAt(pos, "m", "も")

    let compStr = composition.getStringWithTransliterator(.rawString)
    #expect(compStr == "m")
  }

  @Test func inputMode() throws {
    table.addRule("a", "あ", "")
    table.addRule("ka", "か", "")

    var pos = 0
    pos = composition.insertAt(pos, "k")

    var result = composition.getString()
    #expect(result == "k")

    composition.setInputMode(.fullKatakana)
    pos = composition.insertAt(pos, "a")
    result = composition.getString()
    // If a vowel and a consonant were typed with different
    // transliterators, these characters should not be combined.
    #expect(result == "kア")

    composition.setInputMode(.halfAscii)
    pos = composition.insertAt(pos, "k")
    result = composition.getString()
    #expect(result == "kアk")

    composition.setInputMode(.hiragana)
    pos = composition.insertAt(pos, "a")
    result = composition.getString()
    #expect(result == "kアkあ")

    #expect(composition.getTransliterator(0) == .conversionString)
    #expect(composition.getTransliterator(1) == .conversionString)
    #expect(composition.getTransliterator(2) == .fullKatakana)
    #expect(composition.getTransliterator(3) == .halfAscii)
    #expect(composition.getTransliterator(4) == .hiragana)
    #expect(composition.getTransliterator(5) == .hiragana)
    #expect(composition.getTransliterator(10) == .hiragana)
  }

  @Test func setTable() throws {
    table.addRule("a", "あ", "")
    table.addRule("ka", "か", "")

    let table2 = Table()
    table2.addRule("a", "あ", "")
    table2.addRule("ka", "か", "")

    composition.setInputMode(.hiragana)

    var pos = 0
    pos = composition.insertAt(pos, "k")

    var result = composition.getString()
    #expect(result == "ｋ")

    composition.setTable(table2)

    pos = composition.insertAt(pos, "a")
    result = composition.getString()
    #expect(result == "ｋあ")
  }

  @Test func transliterator() throws {
    table.addRule("a", "あ", "")

    // Insert "a" which is converted to "あ".
    var pos = 0
    pos = composition.insertAt(pos, "a")
    #expect(pos == 1)
    var result = composition.getString()
    #expect(result == "あ")

    // Set transliterator for Half Ascii.
    composition.setTransliterator(0, pos, .halfAscii)
    result = composition.getString()
    #expect(result == "a")

    // Insert "a" again.
    pos = composition.insertAt(pos, "a")
    #expect(pos == 2)
    result = composition.getString()
    #expect(result == "aあ")

    // Set transliterator for Full Katakana.
    composition.setTransliterator(0, pos, .fullKatakana)
    result = composition.getString()
    #expect(result == "アア")
  }

  @Test func halfAsciiTransliterator() throws {
    table.addRule("-", "ー", "")
    composition.setInputMode(.halfAscii)

    var pos = 0
    pos = composition.insertKeyAndPreeditAt(pos, "-", "-")
    #expect(pos == 1)
    #expect(composition.getString() == "-")

    pos = composition.insertKeyAndPreeditAt(pos, "-", "-")
    #expect(pos == 2)
    #expect(composition.getString() == "--")
  }

  @Test func shouldCommit() throws {
    table.addRuleWithAttributes("ka", "[KA]", "", .directInput)
    table.addRuleWithAttributes("tt", "[X]", "t", .directInput)
    table.addRuleWithAttributes("ta", "[TA]", "", .noTableAttribute)

    var pos = 0

    pos = composition.insertAt(pos, "k")
    #expect(!composition.shouldCommit())

    pos = composition.insertAt(pos, "a")
    #expect(composition.shouldCommit())

    pos = composition.insertAt(pos, "t")
    #expect(!composition.shouldCommit())

    pos = composition.insertAt(pos, "t")
    #expect(!composition.shouldCommit())

    pos = composition.insertAt(pos, "a")
    #expect(composition.shouldCommit())

    pos = composition.insertAt(pos, "t")
    #expect(!composition.shouldCommit())

    pos = composition.insertAt(pos, "a")
    #expect(!composition.shouldCommit())
    #expect(composition.getString() == "[KA][X][TA][TA]")
  }

  @Test func issue2190364() throws {
    // This is a unittest against http://b/2190364
    var pos = 0

    composition.setInputMode(.fullAscii)
    pos = composition.insertKeyAndPreeditAt(pos, "a", "ち")
    #expect(composition.getString() == "ａ")

    pos = composition.insertAt(pos, " ")
    #expect(composition.getString() == "ａ　")
  }

  @Test func issue1817410() throws {
    // This is a unittest against http://b/2190364
    table.addRule("ss", "っ", "s")

    var pos = 0
    pos = composition.insertAt(pos, "s")
    pos = composition.insertAt(pos, "s")

    let preedit = composition.getString()
    #expect(preedit == "っs")

    #expect(composition.convertPosition(0, .local, .halfAscii) == 0)
    #expect(composition.convertPosition(1, .local, .halfAscii) == 1)
    #expect(composition.convertPosition(2, .local, .halfAscii) == 2)

    do {  // "s|s"
      var innerPosition = 0
      let chunkIt = composition.getChunkAt(1, .local, &innerPosition)
      #expect(innerPosition == 1)
      #expect(composition.chunks[chunkIt].getLength(.local) == 2)

      #expect(composition.getPosition(.halfAscii, chunkIt) == 0)
      #expect(composition.chunks[chunkIt].getLength(.halfAscii) == 2)
    }

    do {  // "ss|"
      var innerPosition = 0
      let chunkIt = composition.getChunkAt(2, .local, &innerPosition)
      #expect(innerPosition == 2)
      #expect(composition.chunks[chunkIt].getLength(.local) == 2)

      #expect(composition.getPosition(.halfAscii, chunkIt) == 0)
      #expect(composition.chunks[chunkIt].getLength(.halfAscii) == 2)
    }
  }

  @Test func issue2209634() throws {
    // This is a unittest against http://b/2209634
    // "q@" becomes "qた@".
    table.addRule("q", "", "た")
    table.addRule("た@", "だ", "")

    composition.setInputMode(.halfAscii)

    var pos = 0
    pos = composition.insertAt(pos, "q")
    pos = composition.insertAt(pos, "@")

    let preedit = composition.getString()
    #expect(preedit == "q@")
  }

  @Test func issue2330530() throws {
    // This is a unittest against http://b/2330530
    // "Win" + Numpad7 becomes "Win77" instead of "Win7".
    table.addRule("wi", "うぃ", "")
    table.addRule("i", "い", "")
    table.addRule("n", "ん", "")
    table.addRule("na", "な", "")

    composition.setInputMode(.halfAscii)

    var pos = 0
    pos = composition.insertAt(pos, "W")
    pos = composition.insertAt(pos, "i")
    pos = composition.insertAt(pos, "n")

    var preedit = composition.getString()
    #expect(preedit == "Win")

    pos = composition.insertKeyAndPreeditAt(pos, "7", "7")
    preedit = composition.getString()
    #expect(preedit == "Win7")
  }

  @Test func issue2819580() throws {
    // This is a unittest against http://b/2819580.
    // 'y' after 'n' disappears.
    table.addRule("po", "ぽ", "")
    table.addRule("n", "ん", "")
    table.addRule("na", "な", "")
    table.addRule("ya", "や", "")
    table.addRule("nya", "にゃ", "")
    table.addRule("byo", "びょ", "")

    composition.setInputMode(.hiragana)

    var pos = 0
    pos = composition.insertAt(pos, "n")
    pos = composition.insertAt(pos, "y")
    do {
      var output = composition.getStringWithTrimMode(.fix)
      #expect(output == "ｎｙ")

      output = composition.getStringWithTrimMode(.asis)
      #expect(output == "ｎｙ")

      output = composition.getStringWithTrimMode(.trim)
      #expect(output == "")
    }
  }

  @Test func issue2990253() throws {
    // SplitChunk fails.
    // Ambiguous text is left in rhs CharChunk invalidly.
    table.addRule("po", "ぽ", "")
    table.addRule("n", "ん", "")
    table.addRule("na", "な", "")
    table.addRule("ya", "や", "")
    table.addRule("nya", "にゃ", "")
    table.addRule("byo", "びょ", "")

    composition.setInputMode(.hiragana)

    var pos = 0
    pos = composition.insertAt(pos, "n")
    pos = composition.insertAt(pos, "y")
    pos = 1
    pos = composition.insertAt(pos, "b")
    do {
      var output = composition.getStringWithTrimMode(.fix)
      #expect(output == "んｂｙ")

      output = composition.getStringWithTrimMode(.asis)
      #expect(output == "んｂｙ")

      output = composition.getStringWithTrimMode(.trim)
      // doubtful result. should be "ん"
      // May relate to http://b/2990358
      #expect(output == "んｂ")
    }
  }

  @Test func insertionIntoPreeditMakesInvalidText1() throws {
    // http://b/2990358
    // Test for mainly Composition.insertAt()
    table.addRule("po", "ぽ", "")
    table.addRule("n", "ん", "")
    table.addRule("na", "な", "")
    table.addRule("ya", "や", "")
    table.addRule("nya", "にゃ", "")
    table.addRule("byo", "びょ", "")

    composition.setInputMode(.hiragana)

    var pos = 0
    pos = composition.insertAt(pos, "n")
    pos = composition.insertAt(pos, "y")
    pos = 1
    pos = composition.insertAt(pos, "b")
    pos = 3
    pos = composition.insertAt(pos, "o")
    do {
      var output = composition.getStringWithTrimMode(.fix)
      #expect(output == "んびょ")

      output = composition.getStringWithTrimMode(.asis)
      #expect(output == "んびょ")

      output = composition.getStringWithTrimMode(.trim)
      #expect(output == "んびょ")
    }
  }

  @Test func insertionIntoPreeditMakesInvalidText2() throws {
    // http://b/2990358
    // Test for mainly Composition.insertKeyAndPreeditAt()

    table.addRule("す゛", "ず", "")
    table.addRule("く゛", "ぐ", "")

    var pos = 0
    pos = composition.insertKeyAndPreeditAt(pos, "m", "も")
    pos = composition.insertKeyAndPreeditAt(pos, "r", "す")
    pos = composition.insertKeyAndPreeditAt(pos, "h", "く")
    pos = composition.insertKeyAndPreeditAt(2, "@", "゛")
    pos = composition.insertKeyAndPreeditAt(5, "!", "!")

    let compStr = composition.getString()
    #expect(compStr == "もずく!")

    let compAsciiStr = composition.getStringWithTransliterator(.rawString)
    #expect(compAsciiStr == "mr@h!")
  }

  @Test func combinePendingChunks() throws {
    table.addRule("po", "ぽ", "")
    table.addRule("n", "ん", "")
    table.addRule("na", "な", "")
    table.addRule("ya", "や", "")
    table.addRule("nya", "にゃ", "")
    table.addRule("byo", "びょ", "")

    do {
      // empty chunks + "n" -> empty chunks + "n"
      var comp = Composition(table)
      comp.setInputMode(.hiragana)

      let pos = 0

      let it = comp.maybeSplitChunkAt(pos)
      var chunkIt = comp.getInsertionChunk(it)

      var input = CompositionInput()
      setInput("n", "", false, &input)
      chunkIt -= comp.combinePendingChunks(chunkIt, input)
      #expect(comp.chunks[chunkIt].pending == "")
      #expect(comp.chunks[chunkIt].conversion == "")
      #expect(comp.chunks[chunkIt].raw == "")
      #expect(comp.chunks[chunkIt].ambiguous == "")
    }
    do {
      // [x] + "n" -> [x] + "n"
      // No combination performed.
      var comp = Composition(table)
      comp.setInputMode(.hiragana)

      var pos = 0
      pos = comp.insertAt(pos, "x")

      let it = comp.maybeSplitChunkAt(pos)
      var chunkIt = comp.getInsertionChunk(it)
      var input = CompositionInput()
      setInput("n", "", false, &input)

      chunkIt -= comp.combinePendingChunks(chunkIt, input)
      #expect(comp.chunks[chunkIt].pending == "")
      #expect(comp.chunks[chunkIt].conversion == "")
      #expect(comp.chunks[chunkIt].raw == "")
      #expect(comp.chunks[chunkIt].ambiguous == "")
    }
    do {
      // Append "a" to [n][y] -> [ny] + "a"
      // Combination performed.
      var comp = Composition(table)
      comp.setInputMode(.hiragana)

      var pos = 0
      pos = comp.insertAt(pos, "y")
      pos = comp.insertAt(0, "n")

      let it = comp.maybeSplitChunkAt(2)
      var chunkIt = comp.getInsertionChunk(it)
      var input = CompositionInput()
      setInput("a", "", false, &input)

      chunkIt -= comp.combinePendingChunks(chunkIt, input)
      #expect(comp.chunks[chunkIt].pending == "ny")
      #expect(comp.chunks[chunkIt].conversion == "")
      #expect(comp.chunks[chunkIt].raw == "ny")
      #expect(comp.chunks[chunkIt].ambiguous == "んy")
    }
    do {
      // Append "a" to [x][n][y] -> [x][ny] + "a"
      // Combination performed.
      var comp = Composition(table)
      comp.setInputMode(.hiragana)

      var pos = 0
      pos = comp.insertAt(pos, "x")
      pos = comp.insertAt(pos, "y")
      pos = comp.insertAt(1, "n")

      let it = comp.maybeSplitChunkAt(3)
      var chunkIt = comp.getInsertionChunk(it)
      var input = CompositionInput()
      setInput("a", "", false, &input)

      chunkIt -= comp.combinePendingChunks(chunkIt, input)
      #expect(comp.chunks[chunkIt].pending == "ny")
      #expect(comp.chunks[chunkIt].conversion == "")
      #expect(comp.chunks[chunkIt].raw == "ny")
      #expect(comp.chunks[chunkIt].ambiguous == "んy")
    }

    do {
      // Append "a" of conversion value to [x][n][y] -> [x][ny] + "a"
      // Combination performed.  If composition input contains a
      // conversion, the conversion is used rather than a raw value.
      var comp = Composition(table)
      comp.setInputMode(.hiragana)

      var pos = 0
      pos = comp.insertAt(pos, "x")
      pos = comp.insertAt(pos, "y")
      pos = comp.insertAt(1, "n")

      let it = comp.maybeSplitChunkAt(3)
      var chunkIt = comp.getInsertionChunk(it)
      var input = CompositionInput()
      setInput("x", "a", false, &input)

      chunkIt -= comp.combinePendingChunks(chunkIt, input)
      #expect(comp.chunks[chunkIt].pending == "ny")
      #expect(comp.chunks[chunkIt].conversion == "")
      #expect(comp.chunks[chunkIt].raw == "ny")
    }
  }

  @Test func newChunkBehaviors() throws {
    table.addRule("n", "", "ん")
    table.addRule("na", "", "な")
    table.addRuleWithAttributes("a", "", "あ", .newChunk)
    table.addRule("ん*", "", "猫")
    table.addRule("*", "", "")
    table.addRule("ん#", "", "猫")

    var input = CompositionInput()
    do {
      var pos = 0
      composition.erase()
      setInput("n", "", true, &input)
      pos = composition.insertInput(pos, input)
      setInput("a", "", true, &input)
      pos = composition.insertInput(pos, input)
      #expect(composition.getString() == "nあ")
    }
    do {
      var pos = 0
      composition.erase()
      setInput("n", "", false, &input)
      pos = composition.insertInput(pos, input)
      setInput("a", "", false, &input)
      pos = composition.insertInput(pos, input)
      #expect(composition.getString() == "な")
    }

    do {
      var pos = 0
      composition.erase()
      setInput("n", "", true, &input)
      pos = composition.insertInput(pos, input)
      setInput("*", "", true, &input)
      pos = composition.insertInput(pos, input)
      #expect(composition.getString() == "猫")
    }
    do {
      var pos = 0
      composition.erase()
      setInput("n", "", false, &input)
      pos = composition.insertInput(pos, input)
      setInput("*", "", false, &input)
      pos = composition.insertInput(pos, input)
      #expect(composition.getString() == "猫")
    }

    do {
      var pos = 0
      composition.erase()
      setInput("n", "", true, &input)
      pos = composition.insertInput(pos, input)
      setInput("#", "", true, &input)
      pos = composition.insertInput(pos, input)
      #expect(composition.getString() == "n#")
    }
    do {
      var pos = 0
      composition.erase()
      setInput("n", "", false, &input)
      pos = composition.insertInput(pos, input)
      setInput("#", "", false, &input)
      pos = composition.insertInput(pos, input)
      #expect(composition.getString() == "猫")
    }

    do {
      var pos = 0
      composition.erase()
      setInput("n", "", true, &input)
      pos = composition.insertInput(pos, input)
      setInput("1", "", true, &input)
      pos = composition.insertInput(pos, input)
      #expect(composition.getString() == "n1")
    }
    do {
      var pos = 0
      composition.erase()
      setInput("n", "", false, &input)
      pos = composition.insertInput(pos, input)
      setInput("1", "", false, &input)
      pos = composition.insertInput(pos, input)
      #expect(composition.getString() == "ん1")
    }
  }

  @Test func twelveKeysInput() throws {
    // Simulates flick + toggle input mode.

    table.addRule("n", "", "ん")
    table.addRule("na", "", "な")
    table.addRule("a", "", "あ")
    table.addRule("*", "", "")
    table.addRule("ほ*", "", "ぼ")
    table.addRuleWithAttributes("7", "", "は", .newChunk)
    table.addRule("は7", "", "ひ")
    table.addRule("ひ*", "", "び")

    var input = CompositionInput()
    var pos = 0

    setInput("n", "", true, &input)
    pos = composition.insertInput(pos, input)

    setInput("a", "", false, &input)
    pos = composition.insertInput(pos, input)

    setInput("7", "ほ", false, &input)
    pos = composition.insertInput(pos, input)

    setInput("*", "", true, &input)
    pos = composition.insertInput(pos, input)

    setInput("7", "ひ", false, &input)
    pos = composition.insertInput(pos, input)

    setInput("7", "", true, &input)
    pos = composition.insertInput(pos, input)

    setInput("7", "は", false, &input)
    pos = composition.insertInput(pos, input)

    setInput("7", "", true, &input)
    pos = composition.insertInput(pos, input)

    setInput("7", "は", false, &input)
    pos = composition.insertInput(pos, input)

    #expect(composition.getString() == "なぼひはははは")
  }

  @Test func specialKeysInput() throws {
    table.addRule("{*}j", "お", "")

    var input = CompositionInput()
    var pos = 0

    setInput("{*}", "", true, &input)
    pos = composition.insertInput(pos, input)
    #expect(composition.getString() == "")
    #expect(composition.getCharChunkList().count == 1)
    #expect(pos == 0)

    setInput("j", "", false, &input)
    pos = composition.insertInput(pos, input)
    #expect(composition.getString() == "お")
  }

  @Test func specialKeysInputWithReplacedKey() throws {
    table.addRule("r", "", "{r}")
    table.addRule("{r}j", "お", "")

    var input = CompositionInput()
    var pos = 0

    setInput("r", "", true, &input)
    pos = composition.insertInput(pos, input)
    #expect(composition.getString() == "")
    #expect(composition.getCharChunkList().count == 1)
    #expect(pos == 0)

    setInput("j", "", false, &input)
    pos = composition.insertInput(pos, input)
    #expect(composition.getString() == "お")
    #expect(composition.getCharChunkList().count == 1)
    #expect(pos == 1)
  }

  @Test func specialKeysInputWithLeadingPendingKey() throws {
    table.addRule("{*}j", "お", "")

    var input = CompositionInput()
    var pos = 0

    setInput("q", "", true, &input)
    pos = composition.insertInput(pos, input)
    #expect(composition.getString() == "q")
    #expect(composition.getCharChunkList().count == 1)
    #expect(pos == 1)

    setInput("{*}", "", true, &input)
    pos = composition.insertInput(pos, input)
    #expect(composition.getString() == "q")
    #expect(composition.getCharChunkList().count == 2)
    #expect(pos == 1)

    setInput("j", "", false, &input)
    pos = composition.insertInput(pos, input)
    #expect(composition.getString() == "qお")
  }

  @Test func differentRulesForSamePendingWithSpecialKeys() throws {
    table.addRule("4", "", "[ta]")
    table.addRule("[to]4", "", "[x]{#1}")
    table.addRule("[x]{#1}4", "", "[ta]")

    table.addRule("*", "", "")
    table.addRule("[tu]*", "", "[x]{#2}")
    table.addRule("[x]{#2}*", "", "[tu]")

    do {
      composition.erase()
      var pos = 0
      pos = composition.insertAt(pos, "[to]4")
      #expect(pos == 3)
      #expect(composition.getString() == "[x]")
      #expect(getRawString(composition) == "[to]4")

      pos = composition.insertAt(pos, "4")
      #expect(pos == 4)
      #expect(composition.getString() == "[ta]")
      #expect(getRawString(composition) == "[to]44")
    }

    do {
      composition.erase()
      var pos = 0
      pos = composition.insertAt(pos, "[to]4")
      #expect(pos == 3)
      #expect(composition.getString() == "[x]")
      #expect(getRawString(composition) == "[to]4")

      pos = composition.insertAt(pos, "*")
      #expect(pos == 3)
      #expect(composition.getString() == "[x]")
      #expect(getRawString(composition) == "[to]4*")
    }

    do {
      composition.erase()
      var pos = 0
      pos = composition.insertAt(pos, "[tu]*")
      #expect(pos == 3)
      #expect(composition.getString() == "[x]")
      #expect(getRawString(composition) == "[tu]*")

      pos = composition.insertAt(pos, "*")
      #expect(pos == 4)
      #expect(composition.getString() == "[tu]")
      #expect(getRawString(composition) == "[tu]**")
    }

    do {
      composition.erase()
      var pos = 0
      pos = composition.insertAt(pos, "[tu]*")
      #expect(pos == 3)
      #expect(composition.getString() == "[x]")
      #expect(getRawString(composition) == "[tu]*")

      pos = composition.insertAt(pos, "*")
      #expect(pos == 4)
      #expect(composition.getString() == "[tu]")
      #expect(getRawString(composition) == "[tu]**")
    }
  }

  @Test func loopingRuleFor12KeysWithSpecialKeys() throws {
    table.addRule("2", "", "a")
    table.addRule("a2", "", "b")
    table.addRule("b2", "", "c")
    table.addRule("c2", "", "{2}2")
    table.addRule("{2}22", "", "a")

    var pos = 0
    pos = composition.insertAt(pos, "2")
    #expect(composition.getString() == "a")
    #expect(getRawString(composition) == "2")

    pos = composition.insertAt(pos, "2")
    #expect(composition.getString() == "b")
    #expect(getRawString(composition) == "22")

    pos = composition.insertAt(pos, "2")
    #expect(composition.getString() == "c")
    #expect(getRawString(composition) == "222")

    pos = composition.insertAt(pos, "2")
    #expect(composition.getString() == "2")
    #expect(getRawString(composition) == "2222")

    pos = composition.insertAt(pos, "2")
    #expect(composition.getString() == "a")
    #expect(getRawString(composition) == "22222")

    pos = composition.insertAt(pos, "2")
    #expect(composition.getString() == "b")
    #expect(getRawString(composition) == "222222")

    pos = composition.insertAt(pos, "2")
    #expect(composition.getString() == "c")
    #expect(getRawString(composition) == "2222222")
  }

  @Test func alphanumericOfSSH() throws {
    // This is a unittest against http://b/3199626
    // 'ssh' (っｓｈ) + F10 should be 'ssh'.
    table.addRule("ss", "っ", "s")
    table.addRule("shi", "し", "")

    composition.setInputMode(.hiragana)
    var pos = 0
    pos = composition.insertAt(pos, "s")
    pos = composition.insertAt(pos, "s")
    pos = composition.insertAt(pos, "h")
    #expect(pos == 3)

    let output = composition.getStringWithTrimMode(.fix)
    #expect(output == "っｓｈ")
  }

  @Test func grassHack() throws {
    table.addRule("ww", "っ", "w")
    table.addRule("we", "うぇ", "")
    table.addRule("www", "w", "ww")

    composition.setInputMode(.hiragana)
    var pos = 0
    pos = composition.insertAt(pos, "w")
    pos = composition.insertAt(pos, "w")
    pos = composition.insertAt(pos, "w")

    #expect(composition.getString() == "ｗｗｗ")

    pos = composition.insertAt(pos, "e")
    #expect(composition.getString() == "ｗっうぇ")
  }

  @Test func rulesForFirstKeyEvents() throws {
    table.addRuleWithAttributes("a", "[A]", "", .newChunk)
    table.addRule("n", "[N]", "")
    table.addRule("nn", "[N]", "")
    table.addRule("na", "[NA]", "")
    table.addRuleWithAttributes("ni", "[NI]", "", .newChunk)

    var input = CompositionInput()

    do {
      setInput("a", "", true, &input)
      _ = composition.insertInput(0, input)
      #expect(composition.getString() == "[A]")
    }

    do {
      composition.erase()
      var input = CompositionInput()
      setInput("anaa", "", true, &input)
      _ = composition.insertInput(0, input)
      #expect(composition.getString() == "[A][NA][A]")
    }

    do {
      composition.erase()

      var input = CompositionInput()
      setInput("an", "", true, &input)
      let positionAn = composition.insertInput(0, input)

      setInput("a", "", true, &input)
      _ = composition.insertInput(positionAn, input)
      #expect(composition.getString() == "[A]n[A]")

      // This input should be treated as a part of "NA".
      setInput("a", "", false, &input)
      _ = composition.insertInput(positionAn, input)
      #expect(composition.getString() == "[A][NA][A]")

      let rawT13n = composition.getStringWithTransliterator(.rawString)
      #expect(rawT13n == "anaa")
    }

    do {
      composition.erase()

      var input = CompositionInput()
      setInput("an", "", true, &input)
      let positionAn = composition.insertInput(0, input)

      setInput("ni", "", true, &input)
      _ = composition.insertInput(positionAn, input)
      #expect(composition.getString() == "[A]n[NI]")

      let rawT13n = composition.getStringWithTransliterator(.rawString)
      #expect(rawT13n == "anni")
    }
  }

  @Test func noTransliteration() throws {
    table.addRuleWithAttributes("0", "0", "", .noTableAttribute)
    table.addRuleWithAttributes("1", "1", "", .noTransliteration)
    table.addRuleWithAttributes("kk", "っ", "k", .noTableAttribute)
    table.addRuleWithAttributes("ka", "か", "", .noTransliteration)
    table.addRuleWithAttributes("ss", "っ", "s", .noTransliteration)
    table.addRuleWithAttributes("sa", "さ", "", .noTableAttribute)
    table.addRuleWithAttributes("tt", "っ", "t", .noTransliteration)
    table.addRuleWithAttributes("ta", "た", "", .noTransliteration)

    composition.setInputMode(.fullKatakana)

    insertCharacters("01kkassatta", 0, &composition)
    #expect(composition.getString() == "０1ッカっさった")
  }

  @Test func noTransliterationIssue3497962() throws {
    table.addRuleWithAttributes("2", "", "a", [.newChunk, .noTransliteration])
    table.addRuleWithAttributes("a2", "", "b", .noTableAttribute)
    table.addRuleWithAttributes("b2", "", "c", .noTableAttribute)
    table.addRuleWithAttributes("c2", "", "{2}2", .noTableAttribute)
    table.addRuleWithAttributes("{2}22", "", "a", .noTableAttribute)

    composition.setInputMode(.hiragana)

    var pos = 0
    pos = composition.insertAt(pos, "2")
    #expect(composition.getString() == "a")

    pos = composition.insertAt(pos, "2")
    #expect(composition.getString() == "b")
  }

  @Test func setTransliteratorOnEmpty() throws {
    composition.setTransliterator(0, 0, .hiragana)
    var input = CompositionInput()
    setInput("a", "", true, &input)
    _ = composition.insertInput(0, input)
    #expect(1 == composition.getLength())
  }

  @Test func copy() throws {
    var src = Composition(table)
    src.setInputMode(.fullKatakana)

    appendChunk("も", "", "mo", &src)
    appendChunk("ず", "", "z", &src)
    appendChunk("く", "", "c", &src)

    #expect(table === src.tableForTesting)
    #expect(src.inputT12r == .fullKatakana)
    #expect(src.chunks.count == 3)

    let copy = src
    #expect(copy == src)

    var copy2 = Composition()
    copy2 = src
    #expect(copy2 == src)
  }

  @Test func isToggleable() throws {
    let kAttrs: TableAttributes = [.newChunk, .noTransliteration]
    table.addRuleWithAttributes("1", "", "{?}あ", kAttrs)
    table.addRule("{?}あ1", "", "{*}あ")

    var pos = 0
    pos = composition.insertAt(pos, "1")
    #expect(composition.isToggleable(0))

    pos = composition.insertAt(pos, "1")
    #expect(!composition.isToggleable(0))
  }
}
