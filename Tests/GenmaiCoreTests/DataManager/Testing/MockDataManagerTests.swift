// Port of mozc/src/data_manager/testing/mock_data_manager_test.cc (3.35.6354).

import GenmaiBase
import Testing

@testable import GenmaiCore

@Suite(
  .enabled(
    if: DataManagerTestSupport.hasMockData,
    "mock_genmai.data is missing; build //data_manager/testing:mozc_dataset_for_testing"))
struct MockDataManagerTest {
  @Test func allTests() throws {
    // kLSize / kRSize / IsBoundaryInternal of the generated segmenter_inl.inc.
    let segmenterInternal = try SegmenterInternal(
      idFile: DataManagerTestSupport.sourcePath("data", "test", "dictionary", "id.def"),
      specialPosFile: DataManagerTestSupport.sourcePath("data", "rules", "special_pos.def"),
      segmenterDef: DataManagerTestSupport.sourcePath("data", "rules", "segmenter.def"))
    let dictionaryDir = DataManagerTestSupport.sourcePath("data", "test", "dictionary")
    let base = DataManagerTestBase(
      dataManager: try MockDataManager.create(),
      lsize: segmenterInternal.lsize, rsize: segmenterInternal.rsize,
      isBoundary: segmenterInternal.isBoundaryInternal,
      connectionTxtFile: FileUtil.joinPath(dictionaryDir, "connection_single_column.txt"),
      expectedResolution: 1,
      dictionaryFiles: [FileUtil.joinPath(dictionaryDir, "dictionary.txt")],
      suggestionFilterFiles: [FileUtil.joinPath(dictionaryDir, "suggestion_filter.txt")])
    // The rule table has the size of the segmenter data and is not trivial.
    #expect(segmenterInternal.lsize <= base.dataManager.getSegmenterData().lTable.count)
    #expect(segmenterInternal.rsize <= base.dataManager.getSegmenterData().rTable.count)
    #expect(
      (1..<segmenterInternal.lsize).contains { rid in
        (1..<segmenterInternal.rsize).contains { !segmenterInternal.isBoundaryInternal(rid, $0) }
      })
    try base.runAllTests()
  }

  // Swift-only: the gmock GetDataVersion override.
  @Test func dataVersionOverride() throws {
    #expect(try MockDataManager.create().getDataVersion() == "24.11.mock")
    #expect(try MockDataManager.create(dataVersion: "1.2.3").getDataVersion() == "1.2.3")
  }
}
