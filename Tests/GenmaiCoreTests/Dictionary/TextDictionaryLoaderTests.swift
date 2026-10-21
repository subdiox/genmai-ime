// Port of mozc/src/dictionary/text_dictionary_loader_test.cc (3.35.6354).

import GenmaiBase
import Testing

@testable import GenmaiCore

private let kTextLines =
  "key_test1\t0\t0\t1\tvalue_test1\n" + "foo\t1\t2\t3\tbar\n" + "buz\t10\t20\t30\tfoobar\n"

private let kReadingCorrectionLines =
  "bar\tfoo\tfoo_correct\n" + "foobar\tfoobar_error\tfoobar_correct\n"

@Suite(.enabled(if: DictionaryTestSupport.hasMockData, DictionaryTestSupport.mockDataMissing))
struct TextDictionaryLoaderTests {
  let posMatcher: PosMatcher
  let tempDir: TempDirectory

  init() throws {
    posMatcher = PosMatcher(try DictionaryTestSupport.mockDataManager().getPosMatcherData())
    tempDir = makeTempDirectoryOrDie()
  }

  func createTextDictionaryLoader() -> TextDictionaryLoader {
    TextDictionaryLoader(posMatcher)
  }

  @Test func basicTest() throws {
    do {
      let loader = createTextDictionaryLoader()
      var tokens: [Token] = []
      loader.collectTokens(&tokens)
      #expect(tokens.isEmpty)
    }

    let filename = FileUtil.joinPath(tempDir.path, "test.tsv")
    try FileUtil.setContents(filename, kTextLines)

    do {
      let loader = createTextDictionaryLoader()
      loader.load(filename, "")
      let tokens = loader.tokens
      try #require(tokens.count == 3)

      #expect(tokens[0].key == "key_test1")
      #expect(tokens[0].value == "value_test1")
      #expect(tokens[0].lid == 0)
      #expect(tokens[0].rid == 0)
      #expect(tokens[0].cost == 1)

      #expect(tokens[1].key == "foo")
      #expect(tokens[1].value == "bar")
      #expect(tokens[1].lid == 1)
      #expect(tokens[1].rid == 2)
      #expect(tokens[1].cost == 3)

      #expect(tokens[2].key == "buz")
      #expect(tokens[2].value == "foobar")
      #expect(tokens[2].lid == 10)
      #expect(tokens[2].rid == 20)
      #expect(tokens[2].cost == 30)

      loader.clear()
      #expect(loader.tokens.isEmpty)
    }

    do {
      let loader = createTextDictionaryLoader()
      loader.loadWithLineLimit(filename, "", 2)
      let tokens = loader.tokens
      try #require(tokens.count == 2)

      #expect(tokens[0].key == "key_test1")
      #expect(tokens[0].value == "value_test1")
      #expect(tokens[0].lid == 0)
      #expect(tokens[0].rid == 0)
      #expect(tokens[0].cost == 1)

      #expect(tokens[1].key == "foo")
      #expect(tokens[1].value == "bar")
      #expect(tokens[1].lid == 1)
      #expect(tokens[1].rid == 2)
      #expect(tokens[1].cost == 3)

      loader.clear()
      #expect(loader.tokens.isEmpty)
    }

    do {
      let loader = createTextDictionaryLoader()
      // open twice -- tokens are cleared everytime
      loader.load(filename, "")
      loader.load(filename, "")
      #expect(loader.tokens.count == 3)
    }

    try FileUtil.unlink(filename)
  }

  @Test func rewriteSpecialTokenTest() {
    let loader = createTextDictionaryLoader()
    do {
      var token = Token()
      token.lid = 100
      token.rid = 200
      #expect(loader.rewriteSpecialToken(&token, ""))
      #expect(token.lid == 100)
      #expect(token.rid == 200)
      #expect(token.attributes == Token.Attribute.none)
    }
    do {
      var token = Token()
      token.lid = 100
      token.rid = 200
      #expect(loader.rewriteSpecialToken(&token, "SPELLING_CORRECTION"))
      #expect(token.lid == 100)
      #expect(token.rid == 200)
      #expect(token.attributes == Token.Attribute.spellingCorrection)
    }
    do {
      var token = Token()
      token.lid = 100
      token.rid = 200
      #expect(loader.rewriteSpecialToken(&token, "ZIP_CODE"))
      #expect(token.lid == posMatcher.getZipcodeId())
      #expect(token.rid == posMatcher.getZipcodeId())
      #expect(token.attributes == Token.Attribute.none)
    }
    do {
      var token = Token()
      token.lid = 100
      token.rid = 200
      #expect(loader.rewriteSpecialToken(&token, "ENGLISH:RATED"))
      #expect(token.lid == posMatcher.getIsolatedWordId())
      #expect(token.rid == posMatcher.getIsolatedWordId())
      #expect(token.attributes == Token.Attribute.none)
    }
    do {
      var token = Token()
      token.lid = 100
      token.rid = 200
      #expect(!loader.rewriteSpecialToken(&token, "foo"))
      #expect(token.lid == 100)
      #expect(token.rid == 200)
      #expect(token.attributes == Token.Attribute.none)
    }
  }

  @Test func loadMultipleFilesTest() throws {
    let filename1 = FileUtil.joinPath(tempDir.path, "test1.tsv")
    let filename2 = FileUtil.joinPath(tempDir.path, "test2.tsv")
    let filename = filename1 + "," + filename2

    try FileUtil.setContents(filename1, kTextLines)
    let unlinker1 = FileUnlinker(filename1)
    try FileUtil.setContents(filename2, kTextLines)
    let unlinker2 = FileUnlinker(filename2)

    do {
      let loader = createTextDictionaryLoader()
      loader.load(filename, "")
      #expect(loader.tokens.count == 6)
    }
    withExtendedLifetime((unlinker1, unlinker2)) {}
  }

  @Test func readingCorrectionTest() throws {
    let loader = createTextDictionaryLoader()
    let dicFilename = FileUtil.joinPath(tempDir.path, "test.tsv")
    let readingCorrectionFilename = FileUtil.joinPath(tempDir.path, "reading_correction.tsv")

    try FileUtil.setContents(dicFilename, kTextLines)
    let dicUnlinker = FileUnlinker(dicFilename)
    try FileUtil.setContents(readingCorrectionFilename, kReadingCorrectionLines)
    let readingCorrectionUnlinker = FileUnlinker(readingCorrectionFilename)

    loader.load(dicFilename, readingCorrectionFilename)
    let tokens = loader.tokens
    try #require(tokens.count == 4)
    #expect(tokens[3].key == "foobar_error")
    #expect(tokens[3].value == "foobar")
    #expect(tokens[3].lid == 10)
    #expect(tokens[3].rid == 20)
    #expect(tokens[3].cost == 30 + 2302)
    withExtendedLifetime((dicUnlinker, readingCorrectionUnlinker)) {}
  }
}
