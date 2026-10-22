// Port of mozc/src/base/clock_test.cc (3.35.6354).

import Foundation
import Testing

@testable import GenmaiBase

// Serialized because timeTestWithMock installs the *global* mock, which is
// read by the other tests of this suite.
@Suite(.serialized) struct ClockTest {
  @Test func timeTestWithMock() {
    let clockMock = ClockMock(parseTimeOrDie("2020-12-23T13:24:35Z"))
    Clock.setClockForUnitTest(clockMock)
    #expect(Clock.getAbslTime() == parseTimeOrDie("2020-12-23T13:24:35Z"))

    // Restore the default clock
    Clock.setClockForUnitTest(nil)

    // Can be flaky.
    #expect(abs(Clock.getAbslTime().timeIntervalSince(Date())) <= 1)
  }

  @Test func timeTestWithoutMock() {
    // Can be flaky.
    #expect(abs(Clock.getAbslTime().timeIntervalSince(Date())) <= 1)
  }

  @Test func timeZone() {
    let tz = Clock.getTimeZone()
    let abslOffset = tz.secondsFromGMT(for: Date(timeIntervalSince1970: 0))

    var epoch: time_t = 24 * 60 * 60  // 1970-01-02 00:00:00 UTC
    let offset = localtime(&epoch)!.pointee
    let tmOffset =
      (Int(offset.tm_mday) - 2) * 24 * 60 * 60  // date offset from Jan 2.
      + Int(offset.tm_hour) * 60 * 60  // hour offset from 00 am.
      + Int(offset.tm_min) * 60  // minute offset.
    #expect(tmOffset == abslOffset)
  }
}
