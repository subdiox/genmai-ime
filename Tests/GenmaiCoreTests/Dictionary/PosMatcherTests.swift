// Tests for the port of mozc/src/dictionary/pos_matcher.h (3.35.6354).
// There is no pos_matcher_test.cc in Mozc; these check the generated rule
// methods against the POS strings of the mock data set and
// data/rules/pos_matcher_rule.def.

import Testing

@testable import GenmaiCore

@Suite(.enabled(if: DictionaryTestSupport.hasMockData, DictionaryTestSupport.mockDataMissing))
struct PosMatcherTests {
  let posMatcher: PosMatcher
  let posIdMap: PosIdMap

  init() throws {
    let dm = try DictionaryTestSupport.mockDataManager()
    posMatcher = PosMatcher(dm.getPosMatcherData())
    posIdMap = PosIdMap(dm.getPosIdMapData())
  }

  @Test func ruleTableSize() throws {
    // The generated table has one Get*Id entry and one range-table offset per
    // rule; the first range table starts right after them.
    let data = try DictionaryTestSupport.mockDataManager().getPosMatcherData()
    #expect(Int(data[PosMatcher.kLidTableSize]) == 2 * PosMatcher.kLidTableSize)
  }

  @Test func getIdAndIsAgreeWithPosStrings() {
    // GeneralNoun "名詞,一般,*,*,*,*,*"
    let generalNoun = posMatcher.getGeneralNounId()
    #expect(posIdMap.getPosString(generalNoun).bytesEqual("名詞,一般,*,*,*,*,*"))
    #expect(posMatcher.isGeneralNoun(generalNoun))
    // Unknown "名詞,サ変接続"
    let unknown = posMatcher.getUnknownId()
    #expect(posIdMap.getPosString(unknown).hasBytePrefix("名詞,サ変接続"))
    #expect(posMatcher.isUnknown(unknown))
    #expect(!posMatcher.isUnknown(generalNoun))
    // Zipcode / IsolatedWord / Number
    #expect(posMatcher.isZipcode(posMatcher.getZipcodeId()))
    #expect(posMatcher.isIsolatedWord(posMatcher.getIsolatedWordId()))
    #expect(posMatcher.isNumber(posMatcher.getNumberId()))
    // Functional rule covers particles.
    for id in 0..<posIdMap.getPosIdCount() {
      let pos = posIdMap.getPosString(UInt16(id))
      if pos.hasBytePrefix("助詞,") {
        #expect(posMatcher.isFunctional(UInt16(id)))
      }
      if pos.hasBytePrefix("名詞,固有名詞,人名,名,") {
        #expect(posMatcher.isFirstName(UInt16(id)))
      }
    }
  }

  @Test func outOfRangeIdsDoNotMatch() {
    #expect(!posMatcher.isGeneralNoun(0xFFFE))
    #expect(!posMatcher.isFunctional(UInt16(posIdMap.getPosIdCount() + 10)))
  }
}
