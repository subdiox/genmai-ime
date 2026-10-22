// Port of mozc/src/base/clock_mock.{h,cc} (3.35.6354).
//
// Lives in the library target (not the test target) so that the tests of
// every module can use it.

import Foundation
import Synchronization

/// Parses the given time in RFC3339 format (see `absl::RFC3339_full`), or
/// terminates the program on failure.
public func parseTimeOrDie(_ time: String) -> Date {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  if let d = formatter.date(from: time) { return d }
  formatter.formatOptions = [.withInternetDateTime]
  guard let d = formatter.date(from: time) else {
    fatalError("Cannot parse time: \(time)")
  }
  return d
}

/// Standard mock clock implementation. This mock behaves in UTC.
public final class ClockMock: ClockInterface, Sendable {
  private struct State {
    var time: Date
    var timeZone = TimeZone.gmt
    // Every time user requests the time, autoDelta is added to time.
    var autoDelta: Duration = .zero
  }

  private let state: Mutex<State>

  public init(_ time: Date) {
    state = Mutex(State(time: time))
  }

  public func getAbslTime() -> Date {
    state.withLock {
      let output = $0.time
      $0.time = $0.time + $0.autoDelta
      return output
    }
  }

  public func getTimeZone() -> TimeZone {
    state.withLock { $0.timeZone }
  }

  /// Advances the clock.
  public func advance(_ delta: Duration) {
    state.withLock { $0.time = $0.time + delta }
  }

  /// Automatically advances the clock every time it returns time.
  public func autoAdvance(_ delta: Duration) {
    state.withLock { $0.autoDelta = delta }
  }

  public func setTime(_ time: Date) {
    state.withLock { $0.time = time }
  }

  /// Not in the C++ mock: allows tests to use a non-UTC time zone.
  public func setTimeZone(_ tz: TimeZone) {
    state.withLock { $0.timeZone = tz }
  }
}

/// Changes the clock with a mock during `body` (port of ScopedClockMock).
/// Uses the task-local override so that parallel tests don't interfere.
@discardableResult
public func withScopedClockMock<R>(
  _ time: Date, _ body: (ClockMock) throws -> R
) rethrows -> R {
  let mock = ClockMock(time)
  return try Clock.withClock(mock) { try body(mock) }
}

@discardableResult
nonisolated(nonsending) public func withScopedClockMock<R>(
  _ time: Date, _ body: nonisolated(nonsending) (ClockMock) async throws -> R
) async rethrows -> R {
  let mock = ClockMock(time)
  return try await Clock.withClock(mock) { try await body(mock) }
}
