// Test helpers for the converter core tests (Swift only). Namespaced to avoid
// clashing with helpers of other test files in this folder.

import Foundation
import GenmaiBase
import GenmaiStorage
import Synchronization
import Testing

@testable import GenmaiCore

enum ConverterCoreTestSupport {
  static var hasMockData: Bool { MockDataManager.defaultDataPath != nil }
  static let mockDataMissing: Comment = "mock_genmai.data is missing; run Tools/build_oracle.sh"

  private static let cachedMock = Mutex<DataManager?>(nil)
  private static let cachedConnector = Mutex<Connector?>(nil)

  static func mockDataManager() throws -> DataManager {
    try cachedMock.withLock { cached in
      if let m = cached { return m }
      let m = try MockDataManager.create()
      cached = m
      return m
    }
  }

  static func mockConnector() throws -> Connector {
    let dm = try mockDataManager()
    return try cachedConnector.withLock { cached in
      if let c = cached { return c }
      let c = try Connector.create(dm.getConnectorData())
      cached = c
      return c
    }
  }

  static func mockPosMatcher() throws -> PosMatcher {
    PosMatcher(try mockDataManager().getPosMatcherData())
  }

  /// Absolute path of a file in Vendor/mozc/src (C++ GetSourceFileOrDie).
  static func sourcePath(_ components: String...) -> String {
    upstreamSourceFile(components)
  }
}

/// A suggestion filter that accepts everything (C++ default-constructed
/// `SuggestionFilter`). C2's `TestSuggestionFilter` reads the data set.
struct EmptySuggestionFilter: SuggestionFilterProtocol {
  func isBadSuggestion(_ text: String) -> Bool { false }
}
