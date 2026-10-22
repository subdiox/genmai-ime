// Test helpers shared by the config / composer / request tests (not a port of
// a C++ file).
//
// Swift Testing runs tests in parallel, so tests that touch the process-wide
// ConfigHandler / CharacterFormManager singletons run inside a scope that
// installs fresh task-local instances (and a temporary user profile, like
// testing::TestWithTempUserProfile in C++).

import Foundation
import GenmaiBase
import Testing

@testable import GenmaiCore

/// Runs `body` with a temporary user profile, a fresh ConfigHandler and a
/// fresh CharacterFormManager (all task-local).
func withScopedConfigEnvironment<R>(_ body: () throws -> R) rethrows -> R {
  try SystemUtil.withTempUserProfile { _ in
    try ConfigHandler.withScopedHandlerForTesting {
      try CharacterFormManager.withScopedManagerForTesting {
        try body()
      }
    }
  }
}

/// Test trait form of `withScopedConfigEnvironment` (applies to every test of
/// a suite).
struct ScopedConfigEnvironmentTrait: SuiteTrait, TestTrait, TestScoping {
  var isRecursive: Bool { true }

  func provideScope(
    for test: Test, testCase: Test.Case?,
    performing function: @Sendable () async throws -> Void
  ) async throws {
    try await SystemUtil.withTempUserProfile { _ in
      try await ConfigHandler.withScopedHandlerForTesting {
        try await CharacterFormManager.withScopedManagerForTesting {
          try await function()
        }
      }
    }
  }
}

extension Trait where Self == ScopedConfigEnvironmentTrait {
  /// Fresh task-local ConfigHandler / CharacterFormManager and a temporary
  /// user profile for each test.
  static var scopedConfigEnvironment: Self { ScopedConfigEnvironmentTrait() }
}

/// Locates a file under the Mozc C++ source tree (`Vendor/mozc/src`), falling
/// back to the main checkout when the submodule is not checked out in this
/// working copy. Port of testing::GetSourceFileOrDie.
func upstreamSourceFile(_ components: [String], filePath: String = #filePath) -> String {
  var url = URL(fileURLWithPath: filePath)
  // Tests/GenmaiCoreTests/<Folder>/<File>.swift -> repository root.
  for _ in 0..<4 { url.deleteLastPathComponent() }
  let candidates = [
    url.appendingPathComponent("Vendor/mozc/src").path
  ]
  for root in candidates {
    let path = ([root] + components).joined(separator: "/")
    if FileManager.default.fileExists(atPath: path) {
      return path
    }
  }
  return ([candidates[0]] + components).joined(separator: "/")
}
