// Test helpers shared by the session tests (not a port of a C++ file).
//
// Swift Testing runs tests in parallel, so every test that touches the
// process-wide ConfigHandler / CharacterFormManager singletons or the user
// profile runs inside `withScopedSessionEnvironment`, which installs fresh
// task-local instances and a temporary user profile (like
// testing::TestWithTempUserProfile + SessionHandlerTestBase in C++).

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import Testing

@testable import GenmaiSession

/// Runs `body` with a temporary user profile, a fresh ConfigHandler and a
/// fresh CharacterFormManager (all task-local).
func withScopedSessionEnvironment<R>(_ body: () throws -> R) rethrows -> R {
  try SystemUtil.withTempUserProfile { _ in
    try ConfigHandler.withScopedHandlerForTesting {
      try CharacterFormManager.withScopedManagerForTesting {
        try body()
      }
    }
  }
}

nonisolated(nonsending) func withScopedSessionEnvironment<R>(
  _ body: nonisolated(nonsending) () async throws -> R
) async rethrows -> R {
  try await SystemUtil.withTempUserProfile { _ in
    try await ConfigHandler.withScopedHandlerForTesting {
      try await CharacterFormManager.withScopedManagerForTesting {
        try await body()
      }
    }
  }
}

enum SessionTestPaths {
  /// Repository root, located from this file.
  static let repoRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  /// testing::GetSourceFile({...}) under Vendor/mozc/src.
  static func upstreamSourceFile(_ components: [String]) -> String {
    let candidates = [
      repoRoot.appendingPathComponent("Vendor/mozc/src").path,
    ]
    for root in candidates {
      let path = ([root] + components).joined(separator: "/")
      if FileManager.default.fileExists(atPath: path) {
        return path
      }
    }
    return ([candidates[0]] + components).joined(separator: "/")
  }

  static var ossDataAvailable: Bool {
    FileManager.default.fileExists(atPath: OssDataManager.defaultDataPath)
  }
}
