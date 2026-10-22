// Test helpers shared by the R2 rewriter tests (symbol, emoticon, emoji,
// single_kanji, usage, english_variants). Swift only; namespaced to avoid
// clashing with helpers of other test files in this folder.

import Foundation
import GenmaiBase
import Synchronization
import Testing

@testable import GenmaiCore

enum R2RewriterTestSupport {
  static var hasMockData: Bool { MockDataManager.defaultDataPath != nil }
  static let mockDataMissing: Comment = "mock_genmai.data is missing; run Tools/build_oracle.sh"

  private static let cachedMock = Mutex<MockDataManager?>(nil)

  /// The shared mock data manager (C++ `testing::MockDataManager`).
  static func mockDataManager() throws -> MockDataManager {
    try cachedMock.withLock { cached in
      if let m = cached { return m }
      let m = try MockDataManager()
      cached = m
      return m
    }
  }

  static func mockPosMatcher() throws -> PosMatcher {
    PosMatcher(try mockDataManager().getPosMatcherData())
  }

  /// Returns the index of the first candidate whose value equals `value`
  /// bytewise, or nil.
  static func rankOfValue(_ segment: Segment, _ value: String) -> Int? {
    for i in 0..<segment.candidatesSize where segment.candidate(i).value.bytesEqual(value) {
      return i
    }
    return nil
  }
}
