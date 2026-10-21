// Port of mozc/src/base/clock.{h,cc} (3.35.6354).
//
// absl::Time is represented by Foundation `Date` and absl::TimeZone by
// Foundation `TimeZone`.
//
// Mocking: the C++ code has a single global mock (`SetClockForUnitTest`). That
// is kept, but because Swift Testing runs tests in parallel, a task-local
// override (`Clock.withClock(_:_:)`) is also provided and takes precedence.
// Tests should prefer the task-local form (see `ScopedClockMock`).

import Foundation
import Synchronization

public protocol ClockInterface: AnyObject, Sendable {
  func getAbslTime() -> Date
  func getTimeZone() -> TimeZone
}

public enum Clock {
  private static let globalMock = Mutex<(any ClockInterface)?>(nil)

  @TaskLocal static var taskLocalMock: (any ClockInterface)?

  @inline(__always)
  private static var mock: (any ClockInterface)? {
    if let m = taskLocalMock { return m }
    return globalMock.withLock { $0 }
  }

  /// Returns the current time.
  public static func getAbslTime() -> Date {
    if let m = mock { return m.getAbslTime() }
    return Date()
  }

  /// Returns the timezone. LocalTimeZone is usually returned.
  public static func getTimeZone() -> TimeZone {
    if let m = mock { return m.getTimeZone() }
    return TimeZone.current
  }

  /// Current time in unix seconds (absl::ToUnixSeconds(Clock::GetAbslTime())).
  public static func getUnixSeconds() -> Int64 {
    Int64(getAbslTime().timeIntervalSince1970.rounded(.down))
  }

  /// TESTONLY: The behavior of global system clock can be overridden by using
  /// this method. Set to nil to restore the default clock.
  public static func setClockForUnitTest(_ clock: (any ClockInterface)?) {
    globalMock.withLock { $0 = clock }
  }

  /// TESTONLY: Overrides the clock for the duration of `body` in the current
  /// task (and its child tasks) only.
  public static func withClock<R>(
    _ clock: any ClockInterface, _ body: () throws -> R
  ) rethrows -> R {
    try $taskLocalMock.withValue(clock, operation: body)
  }

  nonisolated(nonsending) public static func withClock<R>(
    _ clock: any ClockInterface, _ body: nonisolated(nonsending) () async throws -> R
  ) async rethrows -> R {
    try await $taskLocalMock.withValue(clock, operation: body)
  }
}

// MARK: - absl::Time / absl::Duration helpers

extension Date {
  /// The time as integral nanoseconds since the Unix epoch (rounded).
  public var unixNanoseconds: Int64 {
    Int64((timeIntervalSince1970 * 1e9).rounded())
  }

  /// absl::ToUnixSeconds (floor).
  public var unixSeconds: Int64 {
    Int64(timeIntervalSince1970.rounded(.down))
  }

  /// absl::FromUnixSeconds.
  public init(unixSeconds: Int64) {
    self.init(timeIntervalSince1970: TimeInterval(unixSeconds))
  }

  public static func + (lhs: Date, rhs: Duration) -> Date {
    lhs.addingTimeInterval(rhs.timeInterval)
  }

  public static func - (lhs: Date, rhs: Duration) -> Date {
    lhs.addingTimeInterval(-rhs.timeInterval)
  }

  /// `lhs - rhs` as a Duration, rounded to microseconds. Foundation's Date
  /// (a Double relative to 2001-01-01) is only precise to ~0.1 us for current
  /// dates, so sub-microsecond differences are not representable.
  public static func - (lhs: Date, rhs: Date) -> Duration {
    let diff = lhs.timeIntervalSinceReferenceDate - rhs.timeIntervalSinceReferenceDate
    return .microseconds(Int64((diff * 1e6).rounded()))
  }
}

extension Duration {
  /// The duration in (fractional) seconds.
  public var timeInterval: TimeInterval {
    let (s, atto) = components
    return TimeInterval(s) + TimeInterval(atto) / 1e18
  }
}
