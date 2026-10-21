// Port of mozc/src/base/stopwatch.{h,cc} (3.35.6354).

import Foundation

public struct Stopwatch: Sendable {
  public enum StopwatchState: Sendable {
    case running
    case stopped
  }

  private var state: StopwatchState = .stopped
  private var startTime: Date = .distantPast
  private var elapsed: Duration = .zero

  public init() {}

  /// Initializes a new stopwatch object, starts measuring elapsed time,
  /// and returns the stopwatch object.
  public static func startNew() -> Stopwatch {
    var stopwatch = Stopwatch()
    stopwatch.start()
    return stopwatch
  }

  /// Sets elapsed time to zero. Stops the time counting.
  public mutating func reset() {
    state = .stopped
    elapsed = .zero
  }

  /// (Re)starts the time counting.
  /// This function does not reset elapsed time so that you can use start()
  /// to accumulate a periodic activity.
  public mutating func start() {
    if state == .stopped {
      startTime = Clock.getAbslTime()
      state = .running
    }
  }

  /// Stops the time counting.
  public mutating func stop() {
    if state == .running {
      elapsed += getElapsed()
      state = .stopped
    }
  }

  /// Returns the elapsed time.
  public func getElapsed() -> Duration {
    if state == .stopped {
      return elapsed
    }
    return Clock.getAbslTime() - startTime
  }

  /// Returns true if the time counting is on-going.
  public var isRunning: Bool { state == .running }
}
