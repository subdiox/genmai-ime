// Port of mozc/src/dictionary/pos_pattern_matcher_test.cc (3.35.6354).

import Testing

@testable import GenmaiCore

@Suite(.enabled(if: DictionaryTestSupport.hasMockData, DictionaryTestSupport.mockDataMissing))
struct PosPatternMatcherTests {
  let posIdMap: PosIdMap

  init() throws {
    posIdMap = PosIdMap(try DictionaryTestSupport.mockDataManager().getPosIdMapData())
  }

  func findPosId(_ posString: String, sourceLocation: SourceLocation = #_sourceLocation) -> UInt16 {
    for id in 0..<posIdMap.getPosIdCount() where posIdMap.getPosString(UInt16(id)).bytesEqual(posString) {
      return UInt16(id)
    }
    Issue.record("POS string not found in PosIdMap: \(posString)", sourceLocation: sourceLocation)
    return 0
  }

  @Test func exactMatchWithDollar() {
    let toId = findPosId("助詞,並立助詞,*,*,*,*,と")
    let tokaId = findPosId("助詞,並立助詞,*,*,*,*,とか")
    let teId = findPosId("助詞,接続助詞,*,*,*,*,て")

    // Pattern with trailing '$' strictly matches "と", but NOT "とか".
    let exactMatcher = PosPatternMatcher("助詞,並立助詞,*,*,*,*,と$", posIdMap)
    #expect(!exactMatcher.match(teId))
    #expect(exactMatcher.match(toId))  // "と" -> exact match
    #expect(!exactMatcher.match(tokaId))  // "とか" -> excluded by '$'

    // Without '$', prefix matching matches both "と" and "とか".
    let prefixMatcher = PosPatternMatcher("助詞,並立助詞,*,*,*,*,と", posIdMap)
    #expect(prefixMatcher.match(toId))  // "と"
    #expect(prefixMatcher.match(tokaId))  // "とか"
    #expect(!prefixMatcher.match(teId))
  }

  @Test func prefixCollisionWithTrailingComma() {
    let fukuJoshiId = findPosId("助詞,副助詞,*,*,*,*,かも")
    let fukushikaId = findPosId("助詞,副詞化,*,*,*,*,と")

    // "助詞,副助詞," with trailing comma strictly matches "助詞,副助詞,...",
    // but does NOT match "助詞,副詞化,...".
    let strictMatcher = PosPatternMatcher("助詞,副助詞,", posIdMap)
    #expect(strictMatcher.match(fukuJoshiId))
    #expect(!strictMatcher.match(fukushikaId))

    // Without trailing comma, "助詞,副" matches both because it is a prefix of
    // both.
    let lenientMatcher = PosPatternMatcher("助詞,副", posIdMap)
    #expect(lenientMatcher.match(fukuJoshiId))
    #expect(lenientMatcher.match(fukushikaId))
  }

  @Test func prefixMatch() {
    let generalNounId = findPosId("名詞,一般,*,*,*,*,*")
    let properNounId = findPosId("名詞,固有名詞,人名,名,*,*,*")
    let verbId = findPosId("動詞,自立,*,*,五段・カ行促音便,連用タ接続,行く")
    let teId = findPosId("助詞,接続助詞,*,*,*,*,て")
    let toId = findPosId("助詞,並立助詞,*,*,*,*,と")
    let tokaId = findPosId("助詞,並立助詞,*,*,*,*,とか")

    // Stopping at "名詞," matches any POS ID starting with "名詞,"
    let matcher = PosPatternMatcher("名詞,", posIdMap)
    #expect(matcher.match(generalNounId))
    #expect(matcher.match(properNounId))
    #expect(!matcher.match(verbId))

    // Stopping at "助詞," matches any particle
    let matcher2 = PosPatternMatcher("助詞,", posIdMap)
    #expect(matcher2.match(teId))
    #expect(matcher2.match(toId))
    #expect(matcher2.match(tokaId))
    #expect(!matcher2.match(generalNounId))
  }

  @Test func subCategoryNaturalPrefixMatch() {
    let godanId = findPosId("動詞,自立,*,*,五段・カ行促音便,連用タ接続,行く")
    let nonContentVerbId = findPosId("動詞,非自立,*,*,五段・カ行促音便,仮定形,いく")
    let adjectiveId = findPosId("形容詞,自立,*,*,形容詞・アウオ段,ガル接続,*")

    // "動詞,自立,*,*,五段" naturally prefixes
    // "動詞,自立,*,*,五段・カ行促音便,..."
    let matcher = PosPatternMatcher("動詞,自立,*,*,五段", posIdMap)
    #expect(matcher.match(godanId))
    #expect(!matcher.match(nonContentVerbId))

    // List of patterns
    let matcher2 = PosPatternMatcher(["動詞,自立,*,*,五段", "動詞,自立,*,*,一段", "形容詞,自立,"], posIdMap)
    #expect(matcher2.match(godanId))
    #expect(!matcher2.match(nonContentVerbId))
    #expect(matcher2.match(adjectiveId))
  }

  @Test func patternListAlternation() {
    let generalNounId = findPosId("名詞,一般,*,*,*,*,*")
    let properNounId = findPosId("名詞,固有名詞,人名,名,*,*,*")
    let verbId = findPosId("動詞,自立,*,*,五段・カ行促音便,連用タ接続,行く")
    let teId = findPosId("助詞,接続助詞,*,*,*,*,て")
    let toId = findPosId("助詞,並立助詞,*,*,*,*,と")
    let auxId = findPosId("助動詞,*,*,*,特殊・タ,基本形,た")

    // Match multiple patterns
    let matcher = PosPatternMatcher(["名詞,固有名詞,人名,", "助詞,"], posIdMap)
    #expect(!matcher.match(generalNounId))
    #expect(matcher.match(properNounId))
    #expect(!matcher.match(verbId))
    #expect(matcher.match(teId))
    #expect(matcher.match(toId))
    #expect(!matcher.match(auxId))

    // Another list of patterns
    let matcher2 = PosPatternMatcher(["名詞,一般,", "動詞,自立,", "助動詞,"], posIdMap)
    #expect(matcher2.match(generalNounId))
    #expect(!matcher2.match(properNounId))
    #expect(matcher2.match(verbId))
    #expect(matcher2.match(auxId))
  }

  @Test func patternSpanAlternation() {
    let generalNounId = findPosId("名詞,一般,*,*,*,*,*")
    let verbId = findPosId("動詞,自立,*,*,五段・カ行促音便,連用タ接続,行く")
    let teId = findPosId("助詞,接続助詞,*,*,*,*,て")
    let toId = findPosId("助詞,並立助詞,*,*,*,*,と")
    let nonContentVerbId = findPosId("動詞,非自立,*,*,五段・カ行促音便,仮定形,いく")

    let patterns = ["助詞,接続助詞,", "助詞,並立助詞,", "動詞,非自立,"]
    let matcher = PosPatternMatcher(patterns, posIdMap)
    #expect(!matcher.match(generalNounId))
    #expect(matcher.match(teId))
    #expect(matcher.match(toId))
    #expect(matcher.match(nonContentVerbId))
    #expect(!matcher.match(verbId))
  }

  @Test func whitespaceHandling() {
    let teId = findPosId("助詞,接続助詞,*,*,*,*,て")
    let toId = findPosId("助詞,並立助詞,*,*,*,*,と")
    let generalNounId = findPosId("名詞,一般,*,*,*,*,*")

    // Whitespace around pattern is trimmed
    let matcher = PosPatternMatcher(["  助詞,接続助詞,  ", " 助詞,並立助詞, "], posIdMap)
    #expect(matcher.match(teId))
    #expect(matcher.match(toId))
    #expect(!matcher.match(generalNounId))
  }

  @Test func moveOperations() {
    let generalNounId = findPosId("名詞,一般,*,*,*,*,*")
    let verbId = findPosId("動詞,自立,*,*,五段・カ行促音便,連用タ接続,行く")

    let matcher1 = PosPatternMatcher("名詞,一般,", posIdMap)
    #expect(matcher1.match(generalNounId))

    // Copy (Swift value semantics; C++ move constructor)
    let matcher2 = matcher1
    #expect(matcher2.match(generalNounId))

    // Assignment
    var matcher3 = PosPatternMatcher("動詞,", posIdMap)
    #expect(matcher3.match(verbId))
    matcher3 = matcher2
    #expect(matcher3.match(generalNounId))
    #expect(!matcher3.match(verbId))
  }

  @Test func outOfRangeAndEdgeCases() {
    let matcher = PosPatternMatcher("名詞,", posIdMap)
    #expect(matcher.isAvailable())
    #expect(!matcher.match(UInt16(posIdMap.getPosIdCount() + 100)))
    #expect(!matcher.match(UInt16.max))

    // Empty pattern matches nothing and is not available.
    let emptyPattern = PosPatternMatcher("", posIdMap)
    #expect(!emptyPattern.isAvailable())
    #expect(!emptyPattern.match(0))
    #expect(!emptyPattern.match(1))

    // Empty pattern list matches nothing and is not available.
    let emptyList = PosPatternMatcher([String](), posIdMap)
    #expect(!emptyList.isAvailable())
    #expect(!emptyList.match(0))
    #expect(!emptyList.match(1))

    // List with empty pattern matches nothing and is not available.
    let listWithEmpty = PosPatternMatcher([""], posIdMap)
    #expect(!listWithEmpty.isAvailable())
    #expect(!listWithEmpty.match(0))
    #expect(!listWithEmpty.match(1))

    // Empty PosIdMap -> isAvailable() returns false and match() returns false
    // safely.
    let emptyMap = PosIdMap("")
    let matcherForEmpty = PosPatternMatcher("名詞,", emptyMap)
    #expect(!matcherForEmpty.isAvailable())
    #expect(!matcherForEmpty.match(0))
    #expect(!matcherForEmpty.match(1))

    // Default constructed matcher is not available and match() returns false
    // safely.
    let defaultMatcher = PosPatternMatcher()
    #expect(!defaultMatcher.isAvailable())
    #expect(!defaultMatcher.match(0))
    #expect(!defaultMatcher.match(1))
  }

  @Test func getId() throws {
    // Pattern matching a specific unique SOS POS
    let exactMatcher = PosPatternMatcher("BOS/EOS,*,*,*,*,*,*", posIdMap)
    let bosId = try #require(exactMatcher.getId())
    #expect(exactMatcher.match(bosId))
    #expect(bosId == findPosId("BOS/EOS,*,*,*,*,*,*"))

    // Broad pattern should return the first matching ID
    let nounMatcher = PosPatternMatcher("名詞,", posIdMap)
    let nounId = try #require(nounMatcher.getId())
    #expect(nounMatcher.match(nounId))
    #expect(posIdMap.getPosString(nounId).hasBytePrefix("名詞,"))

    // Pattern with no matches
    let noMatchMatcher = PosPatternMatcher("存在しない品詞,", posIdMap)
    #expect(noMatchMatcher.getId() == nil)

    // Default constructed
    let defaultMatcher = PosPatternMatcher()
    #expect(defaultMatcher.getId() == nil)
  }

  @Test func comprehensiveRuleMatching() throws {
    try #require(posIdMap.getPosIdCount() > 2000)

    // Functional rules as prefix pattern list:
    let functionalMatcher = PosPatternMatcher(
      ["助詞,", "助動詞,", "動詞,非自立,", "名詞,非自立,", "形容詞,非自立,", "動詞,接尾,", "名詞,接尾,", "形容詞,接尾,"],
      posIdMap)
    // FirstName: "名詞,固有名詞,人名,名,"
    let firstNameMatcher = PosPatternMatcher("名詞,固有名詞,人名,名,", posIdMap)
    // GeneralNoun with exact match '$': "名詞,一般,*,*,*,*,*$"
    let generalNounMatcher = PosPatternMatcher("名詞,一般,*,*,*,*,*$", posIdMap)
    // ContentWordWithConjugation:
    let contentWordMatcher = PosPatternMatcher(
      ["動詞,自立,*,*,五段", "動詞,自立,*,*,一段", "形容詞,自立,"], posIdMap)
    // Exact particle "と": "助詞,並立助詞,*,*,*,*,と$"
    let exactToMatcher = PosPatternMatcher("助詞,並立助詞,*,*,*,*,と$", posIdMap)

    var foundFirstName = false
    var foundGeneralNoun = false
    var foundFunctional = false
    var foundContentWord = false
    var foundExactTo = false
    var checkedTokaExcluded = false

    for idx in 0..<posIdMap.getPosIdCount() {
      let posId = UInt16(idx)
      let posStr = posIdMap.getPosString(posId)
      if posStr.hasBytePrefix("名詞,固有名詞,人名,名,") {
        #expect(firstNameMatcher.match(posId))
        foundFirstName = true
      }
      if posStr.bytesEqual("名詞,一般,*,*,*,*,*") {
        #expect(generalNounMatcher.match(posId))
        foundGeneralNoun = true
      }
      if posStr.hasBytePrefix("助詞,") || posStr.hasBytePrefix("助動詞,") {
        #expect(functionalMatcher.match(posId))
        foundFunctional = true
      }
      if posStr.hasBytePrefix("動詞,自立,*,*,五段・") {
        #expect(contentWordMatcher.match(posId))
        foundContentWord = true
      }
      if posStr.bytesEqual("助詞,並立助詞,*,*,*,*,と") {
        #expect(exactToMatcher.match(posId))
        foundExactTo = true
      }
      if posStr.bytesEqual("助詞,並立助詞,*,*,*,*,とか") {
        #expect(!exactToMatcher.match(posId))
        checkedTokaExcluded = true
      }
    }

    #expect(foundFirstName)
    #expect(foundGeneralNoun)
    #expect(foundFunctional)
    #expect(foundContentWord)
    #expect(foundExactTo)
    #expect(checkedTokaExcluded)
  }
}
