// Port of mozc/src/base/date_util.{h,cc} (3.35.6354).
//
// absl::CivilDay / absl::Weekday are replaced by the minimal `CivilDay` and
// `Weekday` types below (proleptic Gregorian calendar, absl normalization
// semantics for out-of-range days).

import Foundation

/// absl::Weekday: Monday (0) through Sunday (6).
public enum Weekday: Int, Sendable, CaseIterable {
  case monday = 0
  case tuesday, wednesday, thursday, friday, saturday, sunday
}

/// Minimal absl::CivilDay.
public struct CivilDay: Hashable, Comparable, Sendable, CustomStringConvertible {
  /// Days since 1970-01-01.
  public let daysSinceEpoch: Int64

  /// Normalizes like absl (e.g. 2026-02-30 becomes 2026-03-02).
  public init(_ year: Int, _ month: Int, _ day: Int) {
    // Normalize the month first.
    var y = Int64(year)
    var m = Int64(month) - 1
    y += m >= 0 ? m / 12 : -((11 - m) / 12)
    m = ((m % 12) + 12) % 12
    daysSinceEpoch = CivilDay.daysFromCivil(y, m + 1, 1) + Int64(day) - 1
  }

  public init(daysSinceEpoch: Int64) {
    self.daysSinceEpoch = daysSinceEpoch
  }

  /// absl::ToCivilDay(time, tz).
  public init(_ time: Date, _ timeZone: TimeZone) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    self.init(
      calendar.component(.year, from: time), calendar.component(.month, from: time),
      calendar.component(.day, from: time))
  }

  // Howard Hinnant's days_from_civil.
  private static func daysFromCivil(_ y0: Int64, _ m: Int64, _ d: Int64) -> Int64 {
    let y = m <= 2 ? y0 - 1 : y0
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146097 + doe - 719468
  }

  private var civil: (year: Int, month: Int, day: Int) {
    let z = daysSinceEpoch + 719468
    let era = (z >= 0 ? z : z - 146096) / 146097
    let doe = z - era * 146097
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
    let y = yoe + era * 400
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let d = doy - (153 * mp + 2) / 5 + 1
    let m = mp < 10 ? mp + 3 : mp - 9
    return (Int(m <= 2 ? y + 1 : y), Int(m), Int(d))
  }

  public var year: Int { civil.year }
  public var month: Int { civil.month }
  public var day: Int { civil.day }

  /// absl::GetWeekday.
  public var weekday: Weekday {
    // 1970-01-01 was a Thursday (3).
    Weekday.allCases[Int(((daysSinceEpoch + 3) % 7 + 7) % 7)]
  }

  public static func - (lhs: CivilDay, rhs: CivilDay) -> Int64 {
    lhs.daysSinceEpoch - rhs.daysSinceEpoch
  }

  public static func + (lhs: CivilDay, rhs: Int64) -> CivilDay {
    CivilDay(daysSinceEpoch: lhs.daysSinceEpoch + rhs)
  }

  public static func < (lhs: CivilDay, rhs: CivilDay) -> Bool {
    lhs.daysSinceEpoch < rhs.daysSinceEpoch
  }

  public var description: String {
    let c = civil
    return String(format: "%04d-%02d-%02d", c.year, c.month, c.day)
  }
}

public enum DateUtil {
  @inline(__always)
  private static func isDigit(_ c: UInt8) -> Bool {
    c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9")
  }

  /// Removes the trailing ASCII digits from `s` and returns them.
  private static func consumeTrailingDigits(_ s: inout ArraySlice<UInt8>) -> ArraySlice<UInt8> {
    let end = s.endIndex
    var pos = end
    while pos > s.startIndex && isDigit(s[pos - 1]) {
      pos -= 1
    }
    let digits = s[pos..<end]
    s = s[s.startIndex..<pos]
    return digits
  }

  private static func endsWith(_ s: ArraySlice<UInt8>, _ suffix: [UInt8]) -> Bool {
    s.count >= suffix.count && s.suffix(suffix.count).elementsEqual(suffix)
  }

  private static func simpleAtoi(_ s: ArraySlice<UInt8>) -> Int? {
    Int(String(decoding: s, as: UTF8.self))
  }

  /// Parses a trailing Japanese or slash-separated date expression from
  /// `text` (e.g., "9/16", "2026/09/16", "9月16日", "2026年9月16日") and
  /// resolves omitted years using a [-90 days, +275 days] sliding window
  /// relative to Clock.getAbslTime().
  public static func parseTrailingDate(_ text: String) -> CivilDay? {
    var bytes = ArraySlice(Array(text.utf8))
    if bytes.isEmpty {
      return nil
    }
    // Bound the suffix length to avoid unnecessary allocation on long context
    // strings. Since `text.size() - kMaxSuffixBytes` is a byte offset that may
    // land in the middle of a multi-byte UTF-8 character, advance `start` past
    // any UTF-8 continuation bytes (10xxxxxx) to split on a character boundary.
    let kMaxSuffixBytes = 64
    if bytes.count > kMaxSuffixBytes {
      var start = bytes.count - kMaxSuffixBytes
      while start < bytes.count && (bytes[start] & 0xC0) == 0x80 {
        start += 1
      }
      bytes = bytes[start...]
    }
    let normalized = Japanese.fullWidthAsciiToHalfWidthAscii(
      String(decoding: bytes, as: UTF8.self))
    var s = ArraySlice(Array(normalized.utf8))

    let kDayKanji = Array("日".utf8)
    let kMonthKanji = Array("月".utf8)
    let kYearKanji = Array("年".utf8)
    let slash = UInt8(ascii: "/")
    let dot = UInt8(ascii: ".")
    func isDigitOrSeparator(_ c: UInt8) -> Bool { isDigit(c) || c == slash || c == dot }

    var explicitYear: Int?
    var month = 0
    var day = 0

    // Parses the "yyyy年mm月dd日" (or "mm月dd日") format.
    if endsWith(s, kDayKanji) {
      s = s.dropLast(kDayKanji.count)
      let dayStr = consumeTrailingDigits(&s)
      if dayStr.isEmpty || dayStr.count > 2 || !endsWith(s, kMonthKanji) {
        return nil
      }
      s = s.dropLast(kMonthKanji.count)
      let monthStr = consumeTrailingDigits(&s)
      if monthStr.isEmpty || monthStr.count > 2 {
        return nil
      }
      // Japanese era (e.g., "令和8年") is not supported.
      if endsWith(s, kYearKanji) {
        s = s.dropLast(kYearKanji.count)
        let yearStr = consumeTrailingDigits(&s)
        if yearStr.count != 4 || s.last.map(isDigit) == true {
          return nil
        }
        guard let y = simpleAtoi(yearStr) else {
          return nil
        }
        explicitYear = y
      } else if s.last.map(isDigit) == true {
        return nil
      }
      guard let m = simpleAtoi(monthStr), let d = simpleAtoi(dayStr) else {
        return nil
      }
      month = m
      day = d
    } else {
      // Parses the "yyyy/mm/dd" (or "mm/dd") format.
      let dayStr = consumeTrailingDigits(&s)
      if dayStr.isEmpty || dayStr.count > 2 || s.last != slash {
        return nil
      }
      s = s.dropLast(1)
      let monthStr = consumeTrailingDigits(&s)
      if monthStr.isEmpty || monthStr.count > 2 {
        return nil
      }
      if s.last == slash {
        s = s.dropLast(1)
        let yearStr = consumeTrailingDigits(&s)
        if yearStr.count != 4
          || s.last.map(isDigitOrSeparator) == true
        {
          return nil
        }
        guard let y = simpleAtoi(yearStr) else {
          return nil
        }
        explicitYear = y
      } else if s.last.map(isDigitOrSeparator) == true {
        return nil
      }
      guard let m = simpleAtoi(monthStr), let d = simpleAtoi(dayStr) else {
        return nil
      }
      month = m
      day = d
    }

    if month < 1 || month > 12 || day < 1 || day > 31 {
      return nil
    }

    var targetYear = 0
    if let explicitYear {
      if explicitYear < 1900 || explicitYear > 2100 {
        return nil
      }
      targetYear = explicitYear
    } else {
      let today = CivilDay(Clock.getAbslTime(), Clock.getTimeZone())
      let currentYear = today.year
      let cand = CivilDay(currentYear, month, day)
      let diffDays = cand - today
      if diffDays < -90 {
        targetYear = currentYear + 1
      } else if diffDays > 275 {
        targetYear = currentYear - 1
      } else {
        targetYear = currentYear
      }
    }

    let resultDay = CivilDay(targetYear, month, day)
    if resultDay.year != targetYear || resultDay.month != month || resultDay.day != day {
      return nil
    }
    return resultDay
  }

  /// Parses a trailing date expression from `text` using parseTrailingDate()
  /// and returns its day of the week.
  public static func getWeekdayFromTrailingDate(_ text: String) -> Weekday? {
    parseTrailingDate(text)?.weekday
  }

  /// Returns the short Japanese weekday string ("月", "火", "水", "木", "金",
  /// "土", "日") for `weekday`.
  public static func getShortWeekdayString(_ weekday: Weekday) -> String {
    // absl::Weekday starts from Monday (0) through Sunday (6).
    let kShortWeekdays = ["月", "火", "水", "木", "金", "土", "日"]
    return kShortWeekdays[weekday.rawValue]
  }

  /// Returns the Japanese reading ("げつ", "か", "すい", "もく", "きん", "ど",
  /// "にち") for the short weekday string of `weekday`.
  public static func getShortWeekdayReading(_ weekday: Weekday) -> String {
    let kShortWeekdayReadings = ["げつ", "か", "すい", "もく", "きん", "ど", "にち"]
    return kShortWeekdayReadings[weekday.rawValue]
  }
}
