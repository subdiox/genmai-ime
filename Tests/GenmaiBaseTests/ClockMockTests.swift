// Port of mozc/src/base/clock_mock_test.cc (3.35.6354).

import Foundation
import Testing

@testable import GenmaiBase

@Suite struct ClockMockTest {
  @Test func parsesTimeAtUtc() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let expected = calendar.date(
      from: DateComponents(year: 2020, month: 12, day: 23, hour: 13, minute: 24, second: 35))!
    #expect(parseTimeOrDie("2020-12-23T13:24:35Z") == expected)
  }

  @Test func getAbslTimeReturnsInitiallyGivenTime() {
    let mock = ClockMock(parseTimeOrDie("2020-12-23T13:24:35Z"))
    #expect(mock.getAbslTime() == parseTimeOrDie("2020-12-23T13:24:35Z"))
  }

  @Test func advanceAdvancesByGivenDuration() {
    let mock = ClockMock(parseTimeOrDie("2020-12-23T13:24:35Z"))
    mock.advance(.seconds(1))
    #expect(mock.getAbslTime() == parseTimeOrDie("2020-12-23T13:24:36Z"))
    mock.advance(.seconds(12 * 3600))
    #expect(mock.getAbslTime() == parseTimeOrDie("2020-12-24T01:24:36Z"))
  }

  @Test func autoAdvanceAdvancesOnEveryGetAbslTimeCall() {
    let mock = ClockMock(parseTimeOrDie("2020-12-23T13:24:35Z"))
    mock.autoAdvance(.seconds(5))
    #expect(mock.getAbslTime() == parseTimeOrDie("2020-12-23T13:24:35Z"))
    #expect(mock.getAbslTime() == parseTimeOrDie("2020-12-23T13:24:40Z"))
    #expect(mock.getAbslTime() == parseTimeOrDie("2020-12-23T13:24:45Z"))
  }

  // ScopedClockMockTest.AbslTime
  @Test func scopedClockMockAbslTime() {
    withScopedClockMock(parseTimeOrDie("2020-12-23T13:24:35Z")) { _ in
      #expect(Clock.getAbslTime() == parseTimeOrDie("2020-12-23T13:24:35Z"))
    }
    // The override ends with the scope. (Not checked through the time: ClockTest briefly installs a global mock at
    // the same instant while suites run in parallel.)
    #expect(Clock.taskLocalMock == nil)
  }
}
