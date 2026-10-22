// Port of mozc/src/engine/modules_test.cc (3.35.6354).
//
// Deviations from C++:
// - Every test runs with a temporary user profile (Modules creates the user
//   dictionary and the user history storage in the profile directory).
// - PosMatcher is a value type in Swift, so PresetTest checks the preset
//   matcher by value (its ids) instead of by address.

import GenmaiBase
import Testing

@testable import GenmaiCore

@Suite(.enabled(if: DataManagerTestSupport.hasMockData, "mock_genmai.data is missing"))
struct ModulesTests {
  @Test func createTest() throws {
    try SystemUtil.withTempUserProfile { _ in
      let modules = try Modules.create(MockDataManager.create())
      #expect(modules.getPosIdMap().getPosIdCount() > 0)
    }
  }

  @Test func buildTwiceTest() throws {
    SystemUtil.withTempUserProfile { _ in
      let builder = ModulesPresetBuilder()

      #expect(throws: Never.self) { try builder.build(MockDataManager.create()) }
      #expect(throws: (any Error).self) { try builder.build(MockDataManager.create()) }
    }
  }

  @Test func presetTest() throws {
    try SystemUtil.withTempUserProfile { _ in
      let mockDataManager = try MockDataManager.create()

      // PosMatcher
      let posMatcher = PosMatcher(mockDataManager.getPosMatcherData())

      // PosIdMap
      let posIdMap = PosIdMap(mockDataManager.getPosIdMapData())

      // UserDictionary
      let userDictionary = MockUserDictionary()

      // SuffixDictionary
      let suffixDictionary = MockDictionary()

      // Dictionary
      let dictionary = MockDictionary()

      let modules = try ModulesPresetBuilder()
        .presetPosMatcher(posMatcher)
        .presetPosIdMap(posIdMap)
        .presetUserDictionary(userDictionary)
        .presetSuffixDictionary(suffixDictionary)
        .presetDictionary(dictionary)
        .build(MockDataManager.create())

      #expect(modules.getPosMatcher().getGeneralNounId() == posMatcher.getGeneralNounId())
      #expect(modules.getPosIdMap() === posIdMap)
      #expect(modules.getUserDictionary() as AnyObject === userDictionary)
      #expect(modules.getSuffixDictionary() as AnyObject === suffixDictionary)
      #expect(modules.getDictionary() as AnyObject === dictionary)
    }
  }

  @Test func supplementalModelTest() throws {
    try SystemUtil.withTempUserProfile { _ in
      let modules1 = try Modules.create(MockDataManager.create())
      let modules2 = try Modules.create(MockDataManager.create())

      // Returns the same non-null static instance by default.
      #expect(
        modules1.getSupplementalModelInterface() as AnyObject
          === modules2.getSupplementalModelInterface() as AnyObject)

      let supplementalModel = SupplementalModelStub()
      let modules3 = try ModulesPresetBuilder()
        .presetSupplementalModel(supplementalModel)
        .build(MockDataManager.create())

      #expect(
        modules1.getSupplementalModelInterface() as AnyObject
          !== modules3.getSupplementalModelInterface() as AnyObject)
      #expect(supplementalModel === modules3.getSupplementalModelInterface() as AnyObject)

      // The default static instance is used again.
      let modules4 = try Modules.create(MockDataManager.create())
      #expect(
        modules1.getSupplementalModelInterface() as AnyObject
          === modules4.getSupplementalModelInterface() as AnyObject)
    }
  }

  /// Swift only: every accessor of the partial modules protocols returns the
  /// same supplemental model object.
  @Test func supplementalModelAccessorsShareTheModel() throws {
    try SystemUtil.withTempUserProfile { _ in
      let model = SupplementalModelStub()
      let modules = try ModulesPresetBuilder().presetSupplementalModel(model).build(
        MockDataManager.create())
      #expect(modules.getSupplementalModel() as AnyObject === model)
      #expect(modules.getUserHistorySupplementalModel() as AnyObject === model)
      #expect(modules.getReadingAlignmentSupplementalModel() as AnyObject === model)
      #expect(modules.predictionSupplementalModel() as AnyObject === model)
    }
  }
}
