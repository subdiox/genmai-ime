// Port of mozc/src/dictionary/pos_id_map_test.cc (3.35.6354).

import Testing

@testable import GenmaiCore

@Suite struct PosIdMapTests {
  // The C++ test reads data_manager/testing/pos_id_map.data (a generated file);
  // the same section of the mock data set is used here.
  @Test(.enabled(if: DictionaryTestSupport.hasMockData, DictionaryTestSupport.mockDataMissing))
  func loadFromGeneratedBinary() throws {
    let dm = try DictionaryTestSupport.mockDataManager()
    let posIdMap = PosIdMap(dm.getPosIdMapData())
    #expect(posIdMap.getPosIdCount() > 2000)
    #expect(posIdMap.getPosString(0) == "BOS/EOS,*,*,*,*,*,*")
    #expect(posIdMap.getPosString(UInt16(posIdMap.getPosIdCount() + 100)) == "")

    // Verify that some known POS string exists and matches.
    var foundNounGeneral = false
    for posId in 0..<posIdMap.getPosIdCount() {
      if posIdMap.getPosString(UInt16(posId)).hasBytePrefix("名詞,一般") {
        foundNounGeneral = true
        break
      }
    }
    #expect(foundNounGeneral)
  }

  @Test func simpleNullSeparatedData() {
    // 3 entries: "BOS/EOS", "名詞,一般", "動詞"
    let posIdMap = PosIdMap("BOS/EOS\0名詞,一般\0動詞")
    #expect(posIdMap.getPosIdCount() == 3)
    #expect(posIdMap.getPosString(0) == "BOS/EOS")
    #expect(posIdMap.getPosString(1) == "名詞,一般")
    #expect(posIdMap.getPosString(2) == "動詞")
    #expect(posIdMap.getPosString(3) == "")
    #expect(posIdMap.getPosString(100) == "")
  }

  @Test func emptyDataHandledGracefully() {
    let posIdMap = PosIdMap("")
    #expect(posIdMap.getPosIdCount() == 0)
    #expect(posIdMap.getPosString(0) == "")
    #expect(posIdMap.getPosString(100) == "")
  }
}
