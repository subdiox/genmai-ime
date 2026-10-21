// Port of mozc/src/base/stopwatch_test.cc (3.35.6354).

import Foundation
import Testing
@testable import GenmaiBase

@Suite struct StopwatchTest {
  private func withMock(_ body: (ClockMock) -> Void) {
    withScopedClockMock(Date(timeIntervalSince1970: 0), body)
  }

  @Test func multipleGetElapsedMillisecondsTest() {
    withMock { clock in
      let kWait: Duration = .milliseconds(20_021_001)
      var stopwatch = Stopwatch.startNew()
      clock.advance(kWait)
      stopwatch.stop()

      // GetElapsedX should return the same value if the stopwatch is not
      // running.
      #expect(!stopwatch.isRunning)
      let elapsed1 = stopwatch.getElapsed()
      clock.advance(kWait)
      let elapsed2 = stopwatch.getElapsed()
      clock.advance(kWait)
      let elapsed3 = stopwatch.getElapsed()
      #expect(elapsed2 == elapsed1)
      #expect(elapsed3 == elapsed1)
    }
  }

  @Test func getElapsedXSecondsTest() {
    withMock { clock in
      let kWait: Duration = .microseconds(12_122_323)
      var stopwatch = Stopwatch.startNew()
      clock.advance(kWait)
      stopwatch.stop()
      #expect(stopwatch.getElapsed() == kWait)
    }
  }

  @Test func restartTest() {
    withMock { clock in
      let kWait1: Duration = .seconds(1)
      let kWait2: Duration = .microseconds(42)
      let kWait3: Duration = .seconds(100 * 3600)
      var stopwatch = Stopwatch.startNew()
      clock.advance(kWait1)
      stopwatch.stop()
      clock.advance(kWait2)
      stopwatch.start()
      clock.advance(kWait3)
      stopwatch.stop()
      #expect(stopwatch.getElapsed() == kWait1 + kWait3)
    }
  }

  @Test func resetTest() {
    withMock { clock in
      let kWait1: Duration = .milliseconds(12345)
      let kWait2: Duration = .microseconds(54321)
      var stopwatch = Stopwatch.startNew()
      clock.advance(kWait1)
      stopwatch.stop()
      stopwatch.reset()
      stopwatch.start()
      clock.advance(kWait2)
      stopwatch.stop()
      #expect(stopwatch.getElapsed() == kWait2)
    }
  }
}
