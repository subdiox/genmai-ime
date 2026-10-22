// Port of mozc/src/base/date_util_test.cc (3.35.6354).

import Foundation
import Testing

@testable import GenmaiBase

@Suite struct DateUtilTest {
  // 2026-09-16 12:00:00 UTC
  private let kNow = parseTimeOrDie("2026-09-16T12:00:00Z")

  @Test func parseTrailingDate() {
    withScopedClockMock(kNow) { _ in
      #expect(DateUtil.parseTrailingDate("9/16") == CivilDay(2026, 9, 16))
      #expect(DateUtil.parseTrailingDate("2026/09/16") == CivilDay(2026, 9, 16))
      #expect(DateUtil.parseTrailingDate("9月16日") == CivilDay(2026, 9, 16))
      #expect(DateUtil.parseTrailingDate("2026年9月16日") == CivilDay(2026, 9, 16))
      #expect(DateUtil.parseTrailingDate("９／１６") == CivilDay(2026, 9, 16))
      #expect(DateUtil.parseTrailingDate("予定は9/16") == CivilDay(2026, 9, 16))

      // Long context (> 64 bytes) with multi-byte characters.
      let longPrefix = String(repeating: "a", count: 30)
      #expect(
        DateUtil.parseTrailingDate(longPrefix + "あいうえおあいうえおあいうえお9月16日")
          == CivilDay(2026, 9, 16))

      // Invalid dates and non-date expressions.
      #expect(DateUtil.parseTrailingDate("") == nil)
      #expect(DateUtil.parseTrailingDate("2/30") == nil)
      #expect(DateUtil.parseTrailingDate("2026/02/29") == nil)
      #expect(DateUtil.parseTrailingDate("2024/02/29") == CivilDay(2024, 2, 29))
      #expect(DateUtil.parseTrailingDate("令和8年9月16日") == nil)
      #expect(DateUtil.parseTrailingDate("1/2/3") == nil)
    }
  }

  @Test func getWeekdayFromTrailingDateAndStrings() {
    withScopedClockMock(kNow) { _ in
      let wd = DateUtil.getWeekdayFromTrailingDate("9/16")
      #expect(wd == .wednesday)
      guard let wd else { return }
      #expect(DateUtil.getShortWeekdayString(wd) == "水")
      #expect(DateUtil.getShortWeekdayReading(wd) == "すい")
      #expect(DateUtil.getShortWeekdayString(.monday) == "月")
      #expect(DateUtil.getShortWeekdayReading(.monday) == "げつ")
      #expect(DateUtil.getShortWeekdayString(.sunday) == "日")
      #expect(DateUtil.getShortWeekdayReading(.sunday) == "にち")
    }
  }

  // Not in the C++ test: checks of the CivilDay replacement for absl.
  @Test func civilDay() {
    #expect(CivilDay(1970, 1, 1).daysSinceEpoch == 0)
    #expect(CivilDay(1970, 1, 1).weekday == .thursday)
    #expect(CivilDay(2026, 2, 30) == CivilDay(2026, 3, 2))
    #expect(CivilDay(2026, 13, 1) == CivilDay(2027, 1, 1))
    #expect(CivilDay(2024, 12, 31) - CivilDay(2024, 1, 1) == 365)
    let d = CivilDay(2000, 2, 29)
    #expect(d.year == 2000 && d.month == 2 && d.day == 29)
  }
}
