// Test support for the converter tests: builds the modules that
// engine::Modules::Create() builds in C++ (mozc/src/engine/modules.cc), which
// the converter tests use through the ImmutableConverter / Converter
// constructors.

import Foundation
import GenmaiBase
import GenmaiProtocol
import GenmaiStorage

@testable import GenmaiCore

/// mozc::SuggestionFilter (prediction/suggestion_filter.cc) for the tests.
final class TestSuggestionFilter: SuggestionFilterProtocol, @unchecked Sendable {
  private let filter: ExistenceFilter

  init(_ data: DataSpan<UInt32>) throws {
    filter = try ExistenceFilter.read(UnsafeRawBufferPointer(data.buffer))
  }

  func isBadSuggestion(_ text: String) -> Bool {
    var lowerText = text
    Util.lowerString(&lowerText)
    return filter.exists(lowerText)
  }
}

/// The parts of engine::Modules needed by ImmutableConverter and Converter.
final class TestModules: ConverterModules, @unchecked Sendable {
  let dataManager: DataManager
  let posMatcher: PosMatcher
  let userDictionary: any UserDictionaryInterface
  let dictionary: any DictionaryInterface
  let suffixDictionary: any DictionaryInterface
  let connector: Connector
  let segmenter: Segmenter
  let posGroup: PosGroup
  let suggestionFilter: TestSuggestionFilter
  var supplementalModel: any ConverterSupplementalModel = ConverterSupplementalModelStub()

  init(
    _ dataManager: DataManager, posMatcher: PosMatcher? = nil,
    userDictionary: (any UserDictionaryInterface)? = nil,
    dictionary: (any DictionaryInterface)? = nil,
    suffixDictionary: (any DictionaryInterface)? = nil
  ) throws {
    self.dataManager = dataManager
    let posMatcher = posMatcher ?? PosMatcher(dataManager.getPosMatcherData())
    self.posMatcher = posMatcher
    let userDictionary =
      userDictionary
      ?? {
        let userPosData = dataManager.getUserPosData()
        return UserDictionary(UserPos(userPosData.tokenArray, userPosData.stringArray), posMatcher)
      }()
    self.userDictionary = userDictionary
    if let dictionary {
      self.dictionary = dictionary
    } else {
      let sysdic = try SystemDictionary.Builder(image: dataManager.getSystemDictionaryData()).build()
      let valueDic = ValueDictionary(posMatcher, sysdic.valueTrie)
      self.dictionary = DictionaryImpl(sysdic, valueDic, userDictionary, posMatcher)
    }
    if let suffixDictionary {
      self.suffixDictionary = suffixDictionary
    } else {
      let d = dataManager.getSuffixDictionaryData()
      self.suffixDictionary = SuffixDictionary(d.keyArray, d.valueArray, d.tokenArray)
    }
    connector = try Connector.create(dataManager.getConnectorData())
    segmenter = Segmenter(dataManager: dataManager)
    posGroup = PosGroup(dataManager.getPosGroupData())
    suggestionFilter = try TestSuggestionFilter(dataManager.getSuggestionFilterData())
  }

  static func mock() throws -> TestModules { try TestModules(MockDataManager()) }

  /// nil when Data/genmai.data is missing.
  static func oss() throws -> TestModules? {
    guard FileManager.default.fileExists(atPath: OssDataManager.defaultDataPath) else { return nil }
    return try TestModules(OssDataManager())
  }

  func getPosMatcher() -> PosMatcher { posMatcher }
  func getUserDictionary() -> any UserDictionaryInterface { userDictionary }
  func getSupplementalModel() -> any ConverterSupplementalModel { supplementalModel }

  func makeImmutableConverter() -> ImmutableConverter {
    ImmutableConverter(
      dictionary: dictionary, suffixDictionary: suffixDictionary, userDictionary: userDictionary,
      connector: connector, segmenter: segmenter, posMatcher: posMatcher, posGroup: posGroup,
      suggestionFilter: suggestionFilter)
  }
}

enum ConverterTestPaths {
  /// Repository root, located from this file.
  static let repoRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()

  static let oracleDir = repoRoot.appendingPathComponent("Tests/Fixtures/oracle")
}
