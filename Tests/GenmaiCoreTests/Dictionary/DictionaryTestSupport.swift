// Test helpers for the dictionary tests (Swift only). Namespaced to avoid
// clashing with helpers of other GenmaiCoreTests folders.

import Foundation
import GenmaiBase
import Synchronization
import Testing

@testable import GenmaiCore

enum DictionaryTestSupport {
  static var hasMockData: Bool { MockDataManager.defaultDataPath != nil }
  static var hasOssData: Bool { FileManager.default.fileExists(atPath: OssDataManager.defaultDataPath) }
  static let mockDataMissing: Comment =
    "mock_genmai.data is missing; build //data_manager/testing:mozc_dataset_for_testing"

  /// Shared mock data manager (loading is cheap but repeated in many tests).
  private static let cachedMock = Mutex<DataManager?>(nil)

  static func mockDataManager() throws -> DataManager {
    try cachedMock.withLock { cached in
      if let m = cached { return m }
      let m = try MockDataManager.create()
      cached = m
      return m
    }
  }

  /// Absolute path of a file in Vendor/mozc/src (C++ GetSourceFileOrDie).
  static func sourcePath(_ components: String...) -> String {
    upstreamSourceFile(components)
  }
}
