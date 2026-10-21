// Port of mozc/src/rewriter/number_compound_util_test.cc (3.35.6354).

import GenmaiBase
import Testing

@testable import GenmaiCore

@Suite struct NumberCompoundUtilTests {
  @Test func splitStringIntoNumberAndCounterSuffix() throws {
    let suffixArray = try #require(
      SerializedStringArray(
        bytes: SerializedStringArray.serializeToBuffer(["デシベル", "回", "階"])))

    // Test cases for splittable compounds.
    let kSplittableCases: [(String, String, String, UInt32)] = [
      ("一階", "一", "階", NumberCompoundUtil.NumberScriptType.kanji),
      ("壱階", "壱", "階", NumberCompoundUtil.NumberScriptType.oldKanji),
      ("三十一回", "三十一", "回", NumberCompoundUtil.NumberScriptType.kanji),
      ("三十一", "三十一", "", NumberCompoundUtil.NumberScriptType.kanji),
      ("デシベル", "", "デシベル", 0),
      ("回", "", "回", 0),
      ("階", "", "階", 0),
    ]
    for (input, expectedNumber, expectedSuffix, expectedScriptType) in kSplittableCases {
      let result = NumberCompoundUtil.splitStringIntoNumberAndCounterSuffix(suffixArray, input)
      #expect(result != nil, "\(input)")
      #expect(result?.number.bytesEqual(expectedNumber) == true, "\(input)")
      #expect(result?.counterSuffix.bytesEqual(expectedSuffix) == true, "\(input)")
      #expect(result?.scriptType == expectedScriptType, "\(input)")
    }

    // Test cases for unsplittable compounds.
    let kUnsplittableCases = [
      "回八",
      "Google",
      "ア一階",
      "八億九千万600七十４デシベル",
    ]
    for input in kUnsplittableCases {
      #expect(
        NumberCompoundUtil.splitStringIntoNumberAndCounterSuffix(suffixArray, input) == nil,
        "\(input)")
    }
  }

  @Test(.enabled(if: ConverterCoreTestSupport.hasMockData, ConverterCoreTestSupport.mockDataMissing))
  func isNumber() throws {
    let suffixArray = try #require(
      SerializedStringArray(
        bytes: SerializedStringArray.serializeToBuffer([
          // Should be sorted
          "回",
          "行",
          "階",
        ])))

    let dataManager = try ConverterCoreTestSupport.mockDataManager()
    let posMatcher = PosMatcher(dataManager.getPosMatcherData())

    var c = Candidate()
    c.lid = posMatcher.getNumberId()
    c.rid = posMatcher.getNumberId()
    #expect(NumberCompoundUtil.isNumber(suffixArray, posMatcher, c))

    c = Candidate()
    c.lid = posMatcher.getKanjiNumberId()
    c.rid = posMatcher.getKanjiNumberId()
    #expect(NumberCompoundUtil.isNumber(suffixArray, posMatcher, c))

    c = Candidate()
    c.lid = posMatcher.getNumberId()
    c.rid = posMatcher.getCounterSuffixWordId()
    #expect(NumberCompoundUtil.isNumber(suffixArray, posMatcher, c))

    c = Candidate()
    c.lid = posMatcher.getNumberId()
    c.rid = posMatcher.getParallelMarkerId()
    #expect(NumberCompoundUtil.isNumber(suffixArray, posMatcher, c))

    c = Candidate()
    c.value = "一階"
    c.contentValue = "一階"
    c.lid = posMatcher.getNumberId()
    c.rid = posMatcher.getNumberId()
    #expect(NumberCompoundUtil.isNumber(suffixArray, posMatcher, c))

    c = Candidate()
    c.lid = posMatcher.getAdverbId()
    c.rid = posMatcher.getAdverbId()
    #expect(!NumberCompoundUtil.isNumber(suffixArray, posMatcher, c))

    c = Candidate()
    c.key = "いちぎょう"
    c.contentKey = "いちぎょう"
    c.value = "一行"
    c.contentValue = "一行"
    c.lid = posMatcher.getGeneralNounId()
    c.rid = posMatcher.getGeneralNounId()
    #expect(NumberCompoundUtil.isNumber(suffixArray, posMatcher, c))

    // Exception entry
    c = Candidate()
    c.key = "いっこう"
    c.contentKey = "いっこう"
    c.value = "一行"
    c.contentValue = "一行"
    c.lid = posMatcher.getGeneralNounId()
    c.rid = posMatcher.getGeneralNounId()
    #expect(!NumberCompoundUtil.isNumber(suffixArray, posMatcher, c))
  }
}
