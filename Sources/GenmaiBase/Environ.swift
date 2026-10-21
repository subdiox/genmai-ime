// Port of mozc/src/base/environ.{h,cc} and environ_mock.h (3.35.6354).

import Foundation
import Synchronization

/// Interface to make a mock of Environ.
public protocol EnvironInterface: AnyObject, Sendable {
  func getEnv(_ envVar: String) -> String
}

public enum Environ {
  private static let globalMock = Mutex<(any EnvironInterface)?>(nil)
  @TaskLocal static var taskLocalMock: (any EnvironInterface)?

  /// Returns the value of the specified environment variable ("" if unset).
  public static func getEnv(_ envVar: String) -> String {
    if let mock = taskLocalMock ?? globalMock.withLock({ $0 }) {
      return mock.getEnv(envVar)
    }
    guard let value = getenv(envVar) else { return "" }
    return String(cString: value)
  }

  /// Sets a mock for unit test (global; prefer `withMock` in parallel tests).
  public static func setMockForUnitTest(_ mock: (any EnvironInterface)?) {
    globalMock.withLock { $0 = mock }
  }

  /// TESTONLY: Uses `mock` in the current task while running `body`.
  public static func withMock<R>(_ mock: any EnvironInterface, _ body: () throws -> R) rethrows -> R {
    try $taskLocalMock.withValue(mock, operation: body)
  }
}

/// Port of EnvironMock (environ_mock.h). Register it with
/// `Environ.withMock(_:_:)` or `Environ.setMockForUnitTest(_:)`.
public final class EnvironMock: EnvironInterface, Sendable {
  private let envVars = Mutex<[String: String]>(["HOME": "/home/genmaiuser"])

  public init() {}

  public func getEnv(_ envVar: String) -> String {
    envVars.withLock { $0[envVar] ?? "" }
  }

  public func setEnv(_ envVar: String, _ value: String) {
    envVars.withLock { $0[envVar] = value }
  }
}
