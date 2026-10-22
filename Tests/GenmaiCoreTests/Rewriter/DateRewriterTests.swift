// Port of mozc/src/rewriter/date_rewriter_test.cc (3.35.6354).
//
// - `Clock::SetClockForUnitTest(&mock_clock)` becomes the task-local
//   `withScopedClockMock`, so parallel tests do not interfere.
// - gmock `EXPECT_CALL(dictionary, LookupExact(...)).WillOnce(...)` becomes
//   `MockDictionary.lookupExactHandler`, plus a check that each key was looked
//   up exactly once.
// - `CandidatesAreArray({ValueAndDescAre(...)})` compares the list of
//   (value, description) pairs.

import Foundation
import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private func initCandidate(_ key: String, _ value: String, _ candidate: Candidate) {
  candidate.contentKey = key
  candidate.value = value
  candidate.contentValue = value
}

private func appendSegment(_ key: String, _ value: String, _ segments: Segments) {
  let seg = segments.addSegment()
  seg.setKey(key)
  initCandidate(key, value, seg.addCandidate())
}

private func initSegment(_ key: String, _ value: String, _ segments: Segments) {
  segments.clear()
  appendSegment(key, value, segments)
}

private func insertCandidate(
  _ key: String, _ value: String, _ position: Int, _ segment: Segment
) {
  let cand = segment.insertNewCandidate(position)
  cand.contentKey = key
  cand.value = value
  cand.contentValue = value
}

private func hasCandidate(_ segment: Segment, _ value: String) -> Bool {
  segment.candidates.contains { $0.value.bytesEqual(value) }
}

/// (value, description) pairs of all the candidates.
private func valuesAndDescs(_ segment: Segment) -> [[String]] {
  segment.candidates.map { [$0.value, $0.description] }
}

private func pairs(_ list: [(String, String)]) -> [[String]] {
  list.map { [$0.0, $0.1] }
}

/// The C++ `InvokeCallbackWithUserDictionaryToken` action.
private func invokeCallbackWithUserDictionaryToken(
  _ values: [String], _ key: String, _ callback: any DictionaryCallback
) {
  for value in values {
    let token = Token(
      key: key, value: value, cost: MockDictionary.kDefaultCost,
      lid: UInt16(MockDictionary.kDefaultPosId), rid: UInt16(MockDictionary.kDefaultPosId),
      attributes: Token.Attribute.userDictionary)
    _ = callback.onToken(key, key, token)
  }
}

/// Builds a MockDictionary that returns `dateFormats` for DATE_FORMAT and
/// `datetimeFormats` for DATETIME_FORMAT, and records the lookups.
private final class DateRewriterTestFormatDictionary {
  let dictionary = MockDictionary()
  private(set) var dateLookups = 0
  private(set) var datetimeLookups = 0

  init(dateFormats: [String], datetimeFormats: [String]) {
    dictionary.lookupExactHandler = { [unowned self] key, _, callback in
      if key == DateRewriter.kExtraDateFormatKey {
        self.dateLookups += 1
        invokeCallbackWithUserDictionaryToken(dateFormats, key, callback)
      } else if key == DateRewriter.kExtraDatetimeFormatKey {
        self.datetimeLookups += 1
        invokeCallbackWithUserDictionaryToken(datetimeFormats, key, callback)
      }
    }
  }
}

private let kMockTime = "2011-04-18T15:06:31Z"

private func makeComposer(_ table: Table = Table()) -> Composer {
  Composer(table, Genmai_Commands_Request(), Genmai_Config_Config())
}

@Suite struct DateRewriterTests {
  @Test func dateRewriteTest() {
    withScopedClockMock(parseTimeOrDie(kMockTime)) { _ in
      let rewriter = DateRewriter()
      let segments = Segments()
      let request = ConversionRequest()

      func check(_ key: String, _ value: String, _ desc: String, _ expected: [String]) {
        initSegment(key, value, segments)
        #expect(rewriter.rewrite(request, segments))
        #expect(segments.segmentsSize == 1)
        #expect(
          valuesAndDescs(segments.segment(0))
            == [[value, ""]] + expected.map { [$0, desc] })
      }

      check(
        "きょう", "今日", "今日の日付",
        ["2011/04/18", "2011-04-18", "2011年4月18日", "平成23年4月18日", "月曜日"])
      check(
        "あした", "明日", "明日の日付",
        ["2011/04/19", "2011-04-19", "2011年4月19日", "平成23年4月19日", "火曜日"])
      check(
        "きのう", "昨日", "昨日の日付",
        ["2011/04/17", "2011-04-17", "2011年4月17日", "平成23年4月17日", "日曜日"])
      check(
        "あさって", "明後日", "明後日の日付",
        ["2011/04/20", "2011-04-20", "2011年4月20日", "平成23年4月20日", "水曜日"])

      for (key, value) in [("にちじ", "日時"), ("なう", "ナウ")] {
        check(key, value, "現在の日時", ["2011/04/18 15:06"])
      }
      for (key, value) in [("いま", "今"), ("じこく", "時刻")] {
        check(key, value, "現在の時刻", ["15:06", "15時06分", "午後3時6分"])
      }

      // Tests for insert positions.
      do {
        let kDesc = "今日の日付"
        let generated = [
          "2011/04/18", "2011-04-18", "2011年4月18日", "平成23年4月18日", "月曜日",
        ].map { [$0, kDesc] }

        // If the segment contains only one candidate, the date rewriter adds
        // candidates after it. This case is already tested above; see the case
        // for "きょう", "今日".

        // If the segment contains 5 candidates and the rewriter target is at
        // index 4, the rewriter adds candidates after it.
        initSegment("きょう", "今日", segments)
        // Push front 4 stub candidates so that "今日" is positioned at index 4.
        insertCandidate("Candidate1", "Candidate1", 0, segments.mutableSegment(0))
        insertCandidate("Candidate2", "Candidate2", 0, segments.mutableSegment(0))
        insertCandidate("Candidate3", "Candidate3", 0, segments.mutableSegment(0))
        insertCandidate("Candidate4", "Candidate4", 0, segments.mutableSegment(0))

        #expect(rewriter.rewrite(request, segments))
        #expect(segments.segmentsSize == 1)
        #expect(
          valuesAndDescs(segments.segment(0))
            == [
              ["Candidate4", ""], ["Candidate3", ""], ["Candidate2", ""], ["Candidate1", ""],
              ["今日", ""],
            ] + generated)

        // If the segment contains 5 candidates and the rewriter target is at
        // index 0, the rewriter adds candidates at index 3.
        initSegment("きょう", "今日", segments)
        insertCandidate("Candidate1", "Candidate1", 1, segments.mutableSegment(0))
        insertCandidate("Candidate2", "Candidate2", 1, segments.mutableSegment(0))
        insertCandidate("Candidate3", "Candidate3", 1, segments.mutableSegment(0))
        insertCandidate("Candidate4", "Candidate4", 1, segments.mutableSegment(0))

        #expect(rewriter.rewrite(request, segments))
        #expect(segments.segmentsSize == 1)
        #expect(
          valuesAndDescs(segments.segment(0))
            == [["今日", ""], ["Candidate4", ""], ["Candidate3", ""]] + generated + [
              ["Candidate2", ""], ["Candidate1", ""],
            ])
      }
    }
  }

  @Test func adToEra() {
    #expect(DateRewriter.adToEra(0, 1).isEmpty)

    // AD.645 is "大化元(年)"
    #expect(DateRewriter.adToEra(645, 1) == ["大化元"])

    // AD.646 is "大化2(年)" or "大化二(年)"
    #expect(DateRewriter.adToEra(646, 1) == ["大化2", "大化二"])

    // AD.1976 is "昭和51(年)" or "昭和五十一(年)"
    #expect(DateRewriter.adToEra(1976, 1) == ["昭和51", "昭和五十一"])

    // AD.1989 is "昭和64(年)" or "昭和六四(年)" or "平成元(年)"
    #expect(DateRewriter.adToEra(1989, 1) == ["平成元", "昭和64", "昭和六十四"])

    // AD.1990 is "平成2(年)" or "平成(二)年"
    #expect(DateRewriter.adToEra(1990, 1) == ["平成2", "平成二"])

    // 2 courts era.
    // AD.1331 "元徳3(年)" or "元弘元(年)"
    #expect(DateRewriter.adToEra(1331, 1) == ["元弘元", "元徳3", "元徳三"])

    // AD.1393 "明徳4(年)" or "明徳四(年)"
    #expect(DateRewriter.adToEra(1393, 1) == ["明徳4", "明徳四"])

    // AD.1375
    // South: "文中4(年)" or "文中四(年)", "天授元(年)"
    // North: "応安8(年)" or "応安八(年)", "永和元(年)"
    #expect(
      DateRewriter.adToEra(1375, 1) == ["天授元", "文中4", "文中四", "永和元", "応安8", "応安八"])

    // AD.1332
    // South: "元弘2(年)" or "元弘二(年)"
    // North: "正慶元(年)", "元徳4(年)" or "元徳四(年)"
    #expect(DateRewriter.adToEra(1332, 1) == ["元弘2", "元弘二", "正慶元", "元徳4", "元徳四"])

    // AD.1333
    // South: "元弘3" or "元弘三(年)"
    // North: "正慶2" or "正慶二(年)"
    #expect(DateRewriter.adToEra(1333, 1) == ["元弘3", "元弘三", "正慶2", "正慶二"])

    // AD.1334
    // South: "元弘4" or "元弘四(年)", "建武元"
    // North: "正慶3" or "正慶三(年)", "建武元(deduped)"
    #expect(DateRewriter.adToEra(1334, 1) == ["建武元", "元弘4", "元弘四", "正慶3", "正慶三"])

    // AD.1997
    // "平成九年"
    #expect(DateRewriter.adToEra(1997, 1) == ["平成9", "平成九"])

    // AD.2011
    // "平成二十三年"
    #expect(DateRewriter.adToEra(2011, 1) == ["平成23", "平成二十三"])

    // AD.2019
    // Show both "平成三十一年", "令和元年" when month is not specified.
    #expect(DateRewriter.adToEra(2019, 0) == ["令和元", "平成31", "平成三十一"])

    // Changes the era depending on the month.
    for m in 1...4 {
      #expect(DateRewriter.adToEra(2019, m) == ["平成31", "平成三十一"])
    }
    for m in 5...12 {
      #expect(DateRewriter.adToEra(2019, m) == ["令和元"])
    }

    // AD.2020
    #expect(DateRewriter.adToEra(2020, 1) == ["令和2", "令和二"])

    // AD.2030
    #expect(DateRewriter.adToEra(2030, 1) == ["令和12", "令和十二"])

    // AD.1998
    // "平成十年" or "平成10年"
    #expect(DateRewriter.adToEra(1998, 1) == ["平成10", "平成十"])

    // Negative Test
    // Too big number or negative number input are expected false return
    #expect(!DateRewriter.adToEra(2020, 1).isEmpty)
    #expect(!DateRewriter.adToEra(2100, 1).isEmpty)
    #expect(DateRewriter.adToEra(2201, 1).isEmpty)
    #expect(DateRewriter.adToEra(-100, 1).isEmpty)
  }

  struct EraToAdTestData: Sendable, CustomTestStringConvertible {
    var key: String
    var results: [(String, String)]

    func withSuffix() -> EraToAdTestData {
      EraToAdTestData(
        key: key + "ねん", results: results.map { ($0.0 + "年", $0.1 + "年") })
    }

    var testDescription: String { key }
  }

  static let eraToAdTestData: [EraToAdTestData] = [
    EraToAdTestData(
      key: "たいか1", results: [("六四五", "大化1"), ("６４５", "大化1"), ("645", "大化1")]),
    EraToAdTestData(
      key: "たいか2", results: [("六四六", "大化2"), ("６４６", "大化2"), ("646", "大化2")]),
    // "しょうわ2ねん" is AD.1313 or AD.1927.
    EraToAdTestData(
      key: "しょうわ2",
      results: [
        ("一三一三", "正和2"), ("１３１３", "正和2"), ("1313", "正和2"),
        ("一九二七", "昭和2"), ("１９２７", "昭和2"), ("1927", "昭和2"),
      ]),
    // North court tests.
    EraToAdTestData(
      key: "げんとく1", results: [("一三二九", "元徳1"), ("１３２９", "元徳1"), ("1329", "元徳1")]),
    EraToAdTestData(
      key: "めいとく3", results: [("一三九二", "明徳3"), ("１３９２", "明徳3"), ("1392", "明徳3")]),
    EraToAdTestData(
      key: "けんむ1", results: [("一三三四", "建武1"), ("１３３４", "建武1"), ("1334", "建武1")]),
    // Big number tests.
    EraToAdTestData(
      key: "しょうわ80",
      results: [
        ("一三九一", "正和80"), ("１３９１", "正和80"), ("1391", "正和80"),
        ("二〇〇五", "昭和80"), ("２００５", "昭和80"), ("2005", "昭和80"),
      ]),
    EraToAdTestData(
      key: "たいしょう101",
      results: [("二〇一二", "大正101"), ("２０１２", "大正101"), ("2012", "大正101")]),
    // "元年" test.
    EraToAdTestData(
      key: "れいわがん", results: [("二〇一九", "令和元"), ("２０１９", "令和元"), ("2019", "令和元")]),
    EraToAdTestData(
      key: "へいせいがん",
      results: [("一九八九", "平成元"), ("１９８９", "平成元"), ("1989", "平成元")]),
    // "しょうわがんねん" is AD.1926 or AD.1312.
    EraToAdTestData(
      key: "しょうわがん",
      results: [
        ("一三一二", "正和元"), ("１３１２", "正和元"), ("1312", "正和元"),
        ("一九二六", "昭和元"), ("１９２６", "昭和元"), ("1926", "昭和元"),
      ]),
  ]

  @Test(arguments: eraToAdTestData)
  func eraToAdWithSuffix(_ param: EraToAdTestData) {
    let data = param.withSuffix()
    #expect(pairs(DateRewriter.eraToAd(data.key)) == pairs(data.results))
  }

  @Test(arguments: eraToAdTestData)
  func eraToAdWithoutSuffix(_ data: EraToAdTestData) {
    #expect(pairs(DateRewriter.eraToAd(data.key)) == pairs(data.results))
  }

  @Test func eraToAdEmpty() {
    #expect(DateRewriter.eraToAd("").isEmpty)
  }

  // Negative Tests.
  // 0 or negative number input are expected false return.
  @Test func eraToAdNegative() {
    #expect(DateRewriter.eraToAd("しょうわ-1ねん").isEmpty)
    #expect(DateRewriter.eraToAd("しょうわ-1").isEmpty)
    #expect(DateRewriter.eraToAd("しょうわ0ねん").isEmpty)
    #expect(DateRewriter.eraToAd("しょうわ0").isEmpty)
    #expect(DateRewriter.eraToAd("0ねん").isEmpty)
    #expect(DateRewriter.eraToAd("0").isEmpty)
  }

  @Test func convertTime() {
    #expect(DateRewriter.convertTime(0, 0) == ["0:00", "0時00分", "午前0時0分"])
    #expect(DateRewriter.convertTime(9, 9) == ["9:09", "9時09分", "午前9時9分"])
    #expect(DateRewriter.convertTime(11, 59) == ["11:59", "11時59分", "午前11時59分"])
    #expect(DateRewriter.convertTime(12, 0) == ["12:00", "12時00分", "午後0時0分"])
    #expect(DateRewriter.convertTime(12, 1) == ["12:01", "12時01分", "午後0時1分"])
    #expect(DateRewriter.convertTime(19, 23) == ["19:23", "19時23分", "午後7時23分"])
    #expect(DateRewriter.convertTime(25, 23) == ["25:23", "25時23分", "午前1時23分"])

    // "18:30,18時30分、18時半、午後6時30分、午後6時半"
    // And the order of results is must be above.
    #expect(
      DateRewriter.convertTime(18, 30) == ["18:30", "18時30分", "18時半", "午後6時30分", "午後6時半"])

    #expect(DateRewriter.convertTime(-10, 20).isEmpty)
    #expect(DateRewriter.convertTime(10, -20).isEmpty)
    #expect(DateRewriter.convertTime(80, 20).isEmpty)
    #expect(DateRewriter.convertTime(20, 80).isEmpty)
    #expect(DateRewriter.convertTime(30, 80).isEmpty)
  }

  @Test func convertDateTest() {
    #expect(
      DateRewriter.convertDateWithYear(2011, 4, 17) == ["2011/04/17", "2011-04-17", "2011年4月17日"])

    // January, March, May, July, August, October, December has 31 days April,
    // June, September, November has 30 days February is dealt as a special
    // case, see below:
    let monthDaysTestData: [(month: Int, days: Int)] = [
      (1, 31), (3, 31), (4, 30), (5, 31), (6, 30), (7, 31), (8, 31), (9, 30), (10, 31),
      (11, 30), (12, 31),
    ]
    for testCase in monthDaysTestData {
      var results: [String] = []
      #expect(DateRewriter.convertDateWithYear(2001, testCase.month, testCase.days, &results))
      #expect(!DateRewriter.convertDateWithYear(2001, testCase.month, testCase.days + 1, &results))
    }

    // 4 dividable year is leap year.
    #expect(
      DateRewriter.convertDateWithYear(2004, 2, 29) == ["2004/02/29", "2004-02-29", "2004年2月29日"])

    // Non 4 dividable year is not leap year.
    var results: [String] = []
    #expect(!DateRewriter.convertDateWithYear(1999, 2, 29, &results))

    // However, 100 dividable year is not leap year.
    #expect(!DateRewriter.convertDateWithYear(1900, 2, 29, &results))

    // Furthermore, 400 dividable year is leap year.
    #expect(
      DateRewriter.convertDateWithYear(2000, 2, 29) == ["2000/02/29", "2000-02-29", "2000年2月29日"])

    #expect(!DateRewriter.convertDateWithYear(0, 1, 1, &results))
    #expect(!DateRewriter.convertDateWithYear(2000, 13, 1, &results))
    #expect(!DateRewriter.convertDateWithYear(2000, 1, 41, &results))
    #expect(!DateRewriter.convertDateWithYear(2000, 13, 41, &results))
    #expect(!DateRewriter.convertDateWithYear(2000, 0, 1, &results))
    #expect(!DateRewriter.convertDateWithYear(2000, 1, 0, &results))
    #expect(!DateRewriter.convertDateWithYear(2000, 0, 0, &results))
  }

  @Test func numberRewriterTest() {
    let segments = Segments()
    let rewriter = DateRewriter()
    let composer = makeComposer()
    let conversionRequest = ConversionRequestBuilder().setComposer(composer).build()

    // Not targets of rewrite.
    let kNonTargetCases = [
      "", "0", "1", "01234", "00000",  // Invalid number of digits.
      "hello", "123xyz",  // Not numbers.
      "660", "999", "3400",  // Neither date nor time.
    ]
    for input in kNonTargetCases {
      initSegment(input, input, segments)
      #expect(
        !rewriter.rewrite(conversionRequest, segments),
        "Input: \(input)\nSegments: \(segments.debugString())")
    }

    // {"M/D", "日付"}
    func date(_ month: String, _ day: String) -> [String] { ["\(month)/\(day)", "日付"] }
    // {"M月D日", "日付"}
    func kanjiDate(_ month: String, _ day: String) -> [String] { ["\(month)月\(day)日", "日付"] }
    // {"H:M", "時刻"}
    func time(_ hour: String, _ minute: String) -> [String] { ["\(hour):\(minute)", "時刻"] }
    // {"H時M分", "時刻"}
    func kanjiTime(_ hour: String, _ minute: String) -> [String] {
      ["\(hour)時\(minute)分", "時刻"]
    }
    // {"H時半", "時刻"}
    func kanjiTimeHan(_ hour: String) -> [String] { ["\(hour)時半", "時刻"] }
    // {"午前H時M分", "時刻"}
    func gozen(_ hour: String, _ minute: String) -> [String] { ["午前\(hour)時\(minute)分", "時刻"] }
    // {"午後H時M分", "時刻"}
    func gogo(_ hour: String, _ minute: String) -> [String] { ["午後\(hour)時\(minute)分", "時刻"] }
    // {"午前H時半", "時刻"}
    func gozenHan(_ hour: String) -> [String] { ["午前\(hour)時半", "時刻"] }
    // {"午後H時半", "時刻"}
    func gogoHan(_ hour: String) -> [String] { ["午後\(hour)時半", "時刻"] }

    // Targets of rewrite.
    let kTestCases: [[[String]]] = [
      // Two digits.
      [["00", ""], kanjiTime("0", "0"), gozen("0", "0"), gogo("0", "0")],
      [["01", ""], kanjiTime("0", "1"), gozen("0", "1"), gogo("0", "1")],
      [["10", ""], kanjiTime("1", "0"), gozen("1", "0"), gogo("1", "0")],
      [
        ["11", ""], date("1", "1"), kanjiDate("1", "1"), kanjiTime("1", "1"), gozen("1", "1"),
        gogo("1", "1"),
      ],

      // Three digits.
      [["000", ""], time("0", "00"), kanjiTime("0", "00"), gozen("0", "00"), gogo("0", "00")],
      [["001", ""], time("0", "01"), kanjiTime("0", "01"), gozen("0", "01"), gogo("0", "01")],
      [["010", ""], time("0", "10"), kanjiTime("0", "10"), gozen("0", "10"), gogo("0", "10")],
      [["011", ""], time("0", "11"), kanjiTime("0", "11"), gozen("0", "11"), gogo("0", "11")],
      [
        ["100", ""], time("1", "00"), kanjiTime("1", "00"), kanjiTime("10", "0"),
        gozen("1", "00"), gogo("1", "00"), gozen("10", "0"), gogo("10", "0"),
      ],
      [
        ["101", ""], date("10", "1"), time("1", "01"), kanjiDate("10", "1"),
        kanjiTime("1", "01"), kanjiTime("10", "1"), gozen("1", "01"), gogo("1", "01"),
        gozen("10", "1"), gogo("10", "1"),
      ],
      [
        ["110", ""], date("1", "10"), time("1", "10"), kanjiDate("1", "10"),
        kanjiTime("1", "10"), kanjiTime("11", "0"), gozen("1", "10"), gogo("1", "10"),
        gozen("11", "0"), gogo("11", "0"),
      ],
      [
        ["111", ""], date("1", "11"), date("11", "1"), time("1", "11"), kanjiDate("1", "11"),
        kanjiDate("11", "1"), kanjiTime("1", "11"), kanjiTime("11", "1"), gozen("1", "11"),
        gogo("1", "11"), gozen("11", "1"), gogo("11", "1"),
      ],
      [
        ["130", ""], date("1", "30"), time("1", "30"), kanjiDate("1", "30"),
        kanjiTime("1", "30"), kanjiTimeHan("1"), kanjiTime("13", "0"), gozen("1", "30"),
        gozenHan("1"), gogo("1", "30"), gogoHan("1"),
      ],

      // Four digits.
      [["0000", ""], time("00", "00"), kanjiTime("00", "00")],
      [["0010", ""], time("00", "10"), kanjiTime("00", "10")],
      [["0100", ""], time("01", "00"), kanjiTime("01", "00")],
      [
        ["1000", ""], time("10", "00"), kanjiTime("10", "00"), gozen("10", "00"),
        gogo("10", "00"),
      ],
      [["0011", ""], time("00", "11"), kanjiTime("00", "11")],
      [["0101", ""], date("01", "01"), time("01", "01"), kanjiTime("01", "01")],
      [
        ["1001", ""], date("10", "01"), time("10", "01"), kanjiTime("10", "01"),
        gozen("10", "01"), gogo("10", "01"),
      ],
      [["0110", ""], date("01", "10"), time("01", "10"), kanjiTime("01", "10")],
      [
        ["1010", ""], date("10", "10"), time("10", "10"), kanjiDate("10", "10"),
        kanjiTime("10", "10"), gozen("10", "10"), gogo("10", "10"),
      ],
      [
        ["1100", ""], time("11", "00"), kanjiTime("11", "00"), gozen("11", "00"),
        gogo("11", "00"),
      ],
      [["0111", ""], date("01", "11"), time("01", "11"), kanjiTime("01", "11")],
      [
        ["1011", ""], date("10", "11"), time("10", "11"), kanjiDate("10", "11"),
        kanjiTime("10", "11"), gozen("10", "11"), gogo("10", "11"),
      ],
      [
        ["1101", ""], date("11", "01"), time("11", "01"), kanjiTime("11", "01"),
        gozen("11", "01"), gogo("11", "01"),
      ],
      [
        ["1110", ""], date("11", "10"), time("11", "10"), kanjiDate("11", "10"),
        kanjiTime("11", "10"), gozen("11", "10"), gogo("11", "10"),
      ],
      [
        ["1111", ""], date("11", "11"), time("11", "11"), kanjiDate("11", "11"),
        kanjiTime("11", "11"), gozen("11", "11"), gogo("11", "11"),
      ],
      [["0030", ""], time("00", "30"), kanjiTime("00", "30")],
      [["0130", ""], date("01", "30"), time("01", "30"), kanjiTime("01", "30")],
      [
        ["1030", ""], date("10", "30"), time("10", "30"), kanjiDate("10", "30"),
        kanjiTime("10", "30"), kanjiTimeHan("10"), gozen("10", "30"), gozenHan("10"),
        gogo("10", "30"), gogoHan("10"),
      ],
      [
        ["1130", ""], date("11", "30"), time("11", "30"), kanjiDate("11", "30"),
        kanjiTime("11", "30"), kanjiTimeHan("11"), gozen("11", "30"), gozenHan("11"),
        gogo("11", "30"), gogoHan("11"),
      ],
      [["1745", ""], time("17", "45"), kanjiTime("17", "45")],
      [["2730", ""], time("27", "30"), kanjiTime("27", "30"), kanjiTimeHan("27")],
    ]

    for testCase in kTestCases {
      initSegment(testCase[0][0], testCase[0][0], segments)
      #expect(rewriter.rewrite(conversionRequest, segments))
      #expect(segments.segmentsSize == 1)
      #expect(valuesAndDescs(segments.segment(0)) == testCase, "Input: \(testCase[0][0])")
    }
  }

  @Test func numberRewriterFromRawInputTest() {
    let segments = Segments()
    let rewriter = DateRewriter()

    let table = Table()
    table.addRule("222", "c", "")
    table.addRule("3", "d", "")
    var composer = makeComposer(table)

    // Key sequence : 2223
    // Preedit : cd
    // In this case date/time candidates should be created from 2223.
    do {
      initSegment("cd", "cd", segments)
      composer.reset()
      composer.insertCharacter("2223")
      let convRequest = ConversionRequestBuilder().setComposer(composer).build()

      #expect(rewriter.rewrite(convRequest, segments))
      #expect(segments.segmentsSize == 1)
      #expect(hasCandidate(segments.segment(0), "22:23"))
    }

    // Key sequence : 2223
    // Preedit : 1111
    // Meta candidate(HALF_ASCII)
    // Preedit should be prioritized over key sequence.
    do {
      initSegment("1111", "1111", segments)
      composer.reset()
      composer.insertCharacter("2223")
      let convRequest = ConversionRequestBuilder().setComposer(composer).build()
      #expect(rewriter.rewrite(convRequest, segments))
      #expect(segments.segmentsSize == 1)
      #expect(hasCandidate(segments.segment(0), "11:11"))
      #expect(!hasCandidate(segments.segment(0), "22:23"))
    }

    // Key sequence : 2223
    // Preedit : cd
    // HALF_ASCII meta candidate: 1111
    // In this case meta candidates should be prioritized.
    do {
      initSegment("cd", "cd", segments)
      let metaCandidate = segments.mutableConversionSegment(0).addMetaCandidate()
      metaCandidate.value = "1111"
      composer.insertCharacter("2223")
      composer.reset()
      let convRequest = ConversionRequestBuilder().setComposer(composer).build()
      #expect(rewriter.rewrite(convRequest, segments))
      #expect(segments.segmentsSize == 1)
      #expect(hasCandidate(segments.segment(0), "11:11"))
      #expect(!hasCandidate(segments.segment(0), "22:23"))
    }
  }

  @Test func mobileEnvironmentTest() {
    var request = Genmai_Commands_Request()
    let rewriter = DateRewriter()

    do {
      request.mixedConversion = true
      let convreq = ConversionRequestBuilder().setRequest(request).build()
      #expect(rewriter.capability(convreq) == .all)
    }

    do {
      request.mixedConversion = false
      let convreq = ConversionRequestBuilder().setRequest(request).build()
      #expect(rewriter.capability(convreq) == .conversion)
    }
  }

  @Test func consecutiveDigitsInsertPositionTest() {
    var request = Genmai_Commands_Request()
    let composer = makeComposer()

    // Init an instance of Segments for this test.
    let testSegments = Segments()
    initSegment("1234", "1234", testSegments)
    insertCandidate("cand1", "cand1", 1, testSegments.mutableSegment(0))
    insertCandidate("cand2", "cand2", 2, testSegments.mutableSegment(0))

    // Test case where results are inserted after the top candidate.
    do {
      request.specialRomanjiTable = .qwertyMobileToHalfwidthascii
      let conversionRequest = ConversionRequestBuilder().setComposer(composer).setRequest(request)
        .build()

      let rewriter = DateRewriter()
      let segments = testSegments.copy()
      #expect(rewriter.rewrite(conversionRequest, segments))

      // Verify that the top candidate wasn't modified and the next two were
      // moved to last.
      let segment = segments.segment(0)
      let candSize = segment.candidatesSize
      #expect(3 < candSize)
      #expect(segment.candidate(0).value == "1234")
      #expect(segment.candidate(candSize - 2).value == "cand1")
      #expect(segment.candidate(candSize - 1).value == "cand2")
    }

    // Test case where results are inserted after the last candidate.
    do {
      request.specialRomanjiTable = .toggleFlickToHiragana
      let conversionRequest = ConversionRequestBuilder().setComposer(composer).setRequest(request)
        .build()

      let rewriter = DateRewriter()
      let segments = testSegments.copy()
      #expect(rewriter.rewrite(conversionRequest, segments))

      // Verify that the first three candidate weren't moved.
      let segment = segments.segment(0)
      let candSize = segment.candidatesSize
      #expect(3 < candSize)
      #expect(segment.candidate(0).value == "1234")
      #expect(segment.candidate(1).value == "cand1")
      #expect(segment.candidate(2).value == "cand2")
    }
  }

  @Test func consecutiveDigitsFromMetaCandidates() {
    let conversionRequest = ConversionRequestBuilder().setComposer(makeComposer()).build()

    let segments = Segments()
    initSegment("nisen", "にせん", segments)

    let segment = segments.mutableConversionSegment(0)
    segment.addMetaCandidate().value = "２０００"

    let rewriter = DateRewriter()
    #expect(rewriter.rewrite(conversionRequest, segments))
    #expect(hasCandidate(segments.segment(0), "20:00"))
  }

  @Test func consecutiveDigitsWithMinusSign() {
    let conversionRequest = ConversionRequestBuilder().setComposer(makeComposer()).build()

    // Init an instance of Segments for this test.
    let segments = Segments()
    initSegment("-123", "−１２３", segments)

    let segment = segments.mutableConversionSegment(0)
    // Hiragana: ー is prolonged sound mark (U+2212)
    segment.addMetaCandidate().value = "ー１２３"
    // Half Ascii: - is hyphen-minus (U+002D)
    segment.addMetaCandidate().value = "-123"
    // Full Ascii: − is minus (U+30FC)
    segment.addMetaCandidate().value = "−１２３"
    // Half Katakana: ｰ is half prolonged sound mark (U+FF70)
    segment.addMetaCandidate().value = "ｰ123"

    // No rewrite is expected.
    let rewriter = DateRewriter()
    #expect(!rewriter.rewrite(conversionRequest, segments))
  }

  @Test func consecutiveDigitsInsertPositionWithHistory() {
    let conversionRequest = ConversionRequestBuilder().setComposer(makeComposer()).build()

    let segments = Segments()

    // If there's a history segment containing N candidates where N is greater
    // than the number of candidates in the current conversion segment, crash
    // happened in Segment::insert_candidate().  This is a regression test for
    // it.

    // History segment
    initSegment("hist", "hist", segments)
    var seg = segments.mutableSegment(0)
    insertCandidate("hist1", "hist1", 1, seg)
    insertCandidate("hist2", "hist2", 1, seg)
    insertCandidate("hist3", "hist3", 1, seg)
    seg.setSegmentType(.history)

    // Conversion segment
    appendSegment("11", "11", segments)
    seg = segments.mutableSegment(1)
    insertCandidate("cand1", "cand1", 1, seg)
    insertCandidate("cand2", "cand2", 2, seg)

    // Rewrite is successful with a history segment.
    let rewriter = DateRewriter()
    #expect(rewriter.rewrite(conversionRequest, segments))
    #expect(3 < segments.conversionSegment(0).candidatesSize)
  }

  @Test func extraDateFormatTest() {
    withScopedClockMock(parseTimeOrDie(kMockTime)) { _ in
      let dictionary = DateRewriterTestFormatDictionary(
        dateFormats: ["{YEAR}{MONTH}{DATE}", "{YEAR}_{MONTH}_{DATE}"], datetimeFormats: [])

      let rewriter = DateRewriter(dictionary.dictionary)

      let segments = Segments()
      initSegment("きょう", "今日", segments)

      let request = ConversionRequest()
      #expect(rewriter.rewrite(request, segments))
      #expect(dictionary.dateLookups == 1)
      #expect(dictionary.datetimeLookups == 1)

      #expect(segments.segmentsSize == 1)
      let kDesc = "今日の日付"
      #expect(
        valuesAndDescs(segments.segment(0))
          == [["今日", ""]]
          + [
            "20110418",  // Custom format
            "2011_04_18",  // Custom format
            "2011/04/18", "2011-04-18", "2011年4月18日", "平成23年4月18日", "月曜日",
          ].map { [$0, kDesc] })
    }
  }

  @Test func extraDateFormatTest2() {
    withScopedClockMock(parseTimeOrDie(kMockTime)) { _ in
      // {HOUR} and {MINUTE} are also available for the date format.
      // However, they will be "00".
      // kExtraTimeFormatKey (i.e. TIME_FORMAT) is not used for date format.
      let dictionary = DateRewriterTestFormatDictionary(
        dateFormats: ["{YEAR}_{MONTH}_{DATE}_{HOUR}_{MINUTE}"],
        datetimeFormats: ["{HOUR}_{MINUTE}"])

      let rewriter = DateRewriter(dictionary.dictionary)

      let segments = Segments()
      initSegment("きょう", "今日", segments)

      let request = ConversionRequest()
      #expect(rewriter.rewrite(request, segments))
      #expect(dictionary.dateLookups == 1)
      #expect(dictionary.datetimeLookups == 1)

      #expect(segments.segmentsSize == 1)
      let kDesc = "今日の日付"
      #expect(
        valuesAndDescs(segments.segment(0))
          == [["今日", ""]]
          + [
            "2011_04_18_00_00",  // Custom format
            "2011/04/18", "2011-04-18", "2011年4月18日", "平成23年4月18日", "月曜日",
          ].map { [$0, kDesc] })
    }
  }

  @Test func extraTimeFormatTest() {
    withScopedClockMock(parseTimeOrDie(kMockTime)) { _ in
      let dictionary = DateRewriterTestFormatDictionary(
        dateFormats: [], datetimeFormats: ["{HOUR}{MINUTE}", "{HOUR}_{MINUTE}"])

      let rewriter = DateRewriter(dictionary.dictionary)

      let segments = Segments()
      initSegment("にちじ", "日時", segments)

      let request = ConversionRequest()
      #expect(rewriter.rewrite(request, segments))
      #expect(dictionary.dateLookups == 1)
      #expect(dictionary.datetimeLookups == 1)

      #expect(segments.segmentsSize == 1)
      let kDesc = "現在の日時"
      #expect(
        valuesAndDescs(segments.segment(0))
          == [
            ["日時", ""],
            ["1506", kDesc],  // Custom format
            ["15_06", kDesc],  // Custom format
            ["2011/04/18 15:06", kDesc],
          ])
    }
  }

  @Test func extraTimeFormatTest2() {
    withScopedClockMock(parseTimeOrDie(kMockTime)) { _ in
      // kExtraDateFormatKey (i.e. DATE_FORMAT) is not used for time format.
      // {YEAR}, {MONTH} and {DATE} are also available for the time format.
      let dictionary = DateRewriterTestFormatDictionary(
        dateFormats: ["{YEAR}{MONTH}{DATE}"],
        datetimeFormats: ["{YEAR}_{MONTH}_{DATE}_{HOUR}_{MINUTE}"])

      let rewriter = DateRewriter(dictionary.dictionary)

      let segments = Segments()
      initSegment("にちじ", "日時", segments)

      let request = ConversionRequest()
      #expect(rewriter.rewrite(request, segments))
      #expect(dictionary.dateLookups == 1)
      #expect(dictionary.datetimeLookups == 1)

      #expect(segments.segmentsSize == 1)
      let kDesc = "現在の日時"
      #expect(
        valuesAndDescs(segments.segment(0))
          == [
            ["日時", ""],
            ["2011_04_18_15_06", kDesc],  // Custom format
            ["2011/04/18 15:06", kDesc],
          ])
    }
  }

  @Test func extraFormatSyntaxTest() {
    withScopedClockMock(parseTimeOrDie(kMockTime)) { _ in
      func syntaxTest(_ input: String, _ output: String) {
        let dictionary = DateRewriterTestFormatDictionary(
          dateFormats: [input], datetimeFormats: [])
        let rewriter = DateRewriter(dictionary.dictionary)
        let segments = Segments()
        initSegment("きょう", "今日", segments)
        let request = ConversionRequest()
        #expect(rewriter.rewrite(request, segments))
        #expect(dictionary.dateLookups == 1)
        #expect(dictionary.datetimeLookups == 1)
        #expect(segments.segmentsSize == 1)
        #expect(hasCandidate(segments.segment(0), output), "input: \(input)")
      }

      syntaxTest("%", "%")  // Single % (illformat)
      syntaxTest("%%", "%%")  // Double
      syntaxTest("%Y", "%Y")  // %Y remains as-is.
      syntaxTest("{{}", "{")  // {{} is converted to {.
      syntaxTest("{{}}}", "{}}")
      syntaxTest("{}", "{}")
      syntaxTest("{{}YEAR}", "{YEAR}")
      syntaxTest("{MOZC}", "{MOZC}")  // invalid keyword.
      syntaxTest("{year}", "{year}")  // upper case only.

      // If the format is empty, it is ignored.
      // "2011/04/18" is the default first conversion.
      syntaxTest("", "2011/04/18")
    }
  }

  struct RewriteAdSegment: Sendable {
    var key: String
    var value: String
    var contentKey: String
    var contentValue: String

    init(_ k: String, _ v: String) {
      key = k
      value = v
      contentKey = k
      contentValue = v
    }

    init(_ k: String, _ v: String, _ ck: String, _ cv: String) {
      key = k
      value = v
      contentKey = ck
      contentValue = cv
    }
  }

  struct RewriteAdData: Sendable, CustomTestStringConvertible {
    var segments: [RewriteAdSegment]
    var segmentIndex: Int = 0
    var candidate: String = ""

    var testDescription: String {
      segments.map { "[\($0.key)]" }.joined() + " -> \(candidate)"
    }
  }

  static let rewriteAdTestData: [RewriteAdData] = {
    typealias S = RewriteAdSegment
    typealias D = RewriteAdData
    return [
      // One segment, the most basic case.
      D(segments: [S("へいせい23ねん", "平成23年")], segmentIndex: 0, candidate: "2011年"),
      D(segments: [S("2011ねん", "2011年")], segmentIndex: 0, candidate: "平成23年"),
      // The `value` should be ignored when rewriting.
      D(segments: [S("へいせい23ねん", "兵勢23年")], segmentIndex: 0, candidate: "2011年"),
      D(segments: [S("へいせい23ねん", "兵勢23念")], segmentIndex: 0, candidate: "2011年"),
      D(segments: [S("2011ねん", "2011念")], segmentIndex: 0, candidate: "平成23年"),
      // Invalid era name.
      D(segments: [S("ああ23ねん", "ああ23年")], segmentIndex: 0, candidate: ""),
      // One segment, with preceding and following segments.
      D(
        segments: [S("きょうは", "今日は"), S("へいせい23ねん", "平成23年"), S("です", "です")],
        segmentIndex: 1, candidate: "2011年"),
      D(
        segments: [S("きょうは", "今日は"), S("2011ねん", "2011年"), S("です", "です")],
        segmentIndex: 1, candidate: "平成23年"),
      // The "年" suffix in the following segment.
      // In multi-segment mode, era-to-AD merges both segments into "2011年",
      // while AD-to-era ("2011" + "ねん") produces "平成23".
      D(segments: [S("へいせい23", "平成23"), S("ねん", "年")], segmentIndex: 0, candidate: "2011年"),
      D(segments: [S("2011", "2011"), S("ねん", "年")], segmentIndex: 0, candidate: "平成23"),
      D(segments: [S("2011", "二千十一"), S("ねん", "年")], segmentIndex: 0, candidate: "平成23"),
      D(
        segments: [
          S("きょうは", "今日は"), S("へいせい23", "平成23"), S("ねん", "年"), S("です", "です"),
        ],
        segmentIndex: 1, candidate: "2011年"),
      D(
        segments: [S("きょうは", "今日は"), S("2011", "2011"), S("ねん", "年"), S("です", "です")],
        segmentIndex: 1, candidate: "平成23"),
      // Multiple segments.
      D(segments: [S("へいせい", "平成"), S("23ねん", "23年")], segmentIndex: 0, candidate: "2011年"),
      D(
        segments: [S("へいせい", "平成"), S("23", "23"), S("ねん", "年")], segmentIndex: 0,
        candidate: "2011年"),
      // 4 segments.
      D(
        segments: [S("へい", "平"), S("せい", "成"), S("23", "23"), S("ねん", "年")],
        segmentIndex: 0, candidate: "2011年"),
      // Reject more than 6 segments.
      D(segments: [
        S("へ", "へ"), S("い", "い"), S("せ", "せ"), S("い", "い"), S("2", "2"), S("3", "3"),
        S("ねん", "年"),
      ]),
      // The `value` should be ignored when merging too.
      D(segments: [S("へいせい", "兵勢"), S("23ねん", "23年")], segmentIndex: 0, candidate: "2011年"),
      // Multiple segments with preceding and following segments.
      D(
        segments: [
          S("きょうは", "今日は"), S("へいせい", "平成"), S("23", "23"), S("ねん", "年"),
          S("です", "です"),
        ],
        segmentIndex: 1, candidate: "2011年"),
      // Extra characters in the segment of "nen".
      D(
        segments: [S("へいせい23ねんです", "平成23年です", "へいせい23ねん", "平成23年")],
        segmentIndex: 0, candidate: "2011年です"),
      D(
        segments: [
          S("きょうは", "今日は"), S("へいせい23ねんです", "平成23年です", "へいせい23ねん", "平成23年"),
        ],
        segmentIndex: 1, candidate: "2011年です"),
      D(
        segments: [
          S("きょうは", "今日は"), S("へいせい", "平成"), S("23", "23"),
          S("ねんです", "年です", "ねん", "年"),
        ],
        segmentIndex: 1, candidate: "2011年です"),
      D(
        segments: [S("れいわ8ねんの", "令和8年の", "れいわ8ねん", "令和8年")], segmentIndex: 0,
        candidate: "2026年の"),
      D(
        segments: [S("れいわ3ねんの", "令和3年の", "れいわ3ねん", "令和3年")], segmentIndex: 0,
        candidate: "2021年の"),
      D(segments: [S("れいわ8ねんの", "令和8年の")], segmentIndex: 0, candidate: "2026年の"),
      D(segments: [S("れいわ8ねんの", "れいわ8ねんの")], segmentIndex: 0, candidate: "2026年の"),
      D(segments: [S("れいわ", "令和"), S("8ねん", "8年")], segmentIndex: 0, candidate: "2026年"),
      D(segments: [S("れいわ", "令和"), S("3ねん", "3年")], segmentIndex: 0, candidate: "2021年"),
      D(segments: [S("れいわ8", "令和8"), S("ねんの", "年の")], segmentIndex: 0, candidate: "2026年の"),
      D(
        segments: [S("れいわ", "令和"), S("8", "8"), S("ねんの", "年の")], segmentIndex: 0,
        candidate: "2026年の"),
    ]
  }()

  @Test(arguments: rewriteAdTestData)
  func rewriteAdMockConverter(_ data: RewriteAdData) {
    let dictionary = MockDictionary()
    let rewriter = DateRewriter(dictionary)
    let segments = Segments()
    for s in data.segments {
      let seg = segments.addSegment()
      seg.setKey(s.key)
      let cand = seg.addCandidate()
      cand.key = s.key
      cand.value = s.value
      cand.contentKey = s.contentKey
      cand.contentValue = s.contentValue
    }
    var requestProto = Genmai_Commands_Request()
    requestProto.decoderExperimentParams.enableMultiSegmentCandidate = true
    let request = ConversionRequestBuilder().setRequest(requestProto).build()

    if data.candidate.isEmpty {
      // Rewrite is not expected.
      #expect(!rewriter.rewrite(request, segments))
    } else {
      // Rewrite is expected.
      #expect(rewriter.rewrite(request, segments))
      let segment = segments.segment(data.segmentIndex)
      #expect(hasCandidate(segment, data.candidate), "\(segments.debugString())")
    }
  }

  // Test if `Segments::set_resized(true)` prevents merging segments.
  @Test func rewriteAdResizedSegments() {
    let dictionary = MockDictionary()
    let rewriter = DateRewriter(dictionary)
    let segments = Segments()
    initSegment("へいせい", "平成", segments)
    appendSegment("23", "23", segments)
    appendSegment("ねん", "年", segments)
    let request = ConversionRequest()
    segments.setResized(true)

    var resizeRequest = rewriter.checkResizeSegmentsRequest(request, segments)
    #expect(resizeRequest == nil)

    segments.setResized(false)
    resizeRequest = rewriter.checkResizeSegmentsRequest(request, segments)
    #expect(resizeRequest != nil)
  }

  @Test func rewriteAdLegacyBranch() throws {
    let dictionary = MockDictionary()
    let rewriter = DateRewriter(dictionary)
    do {
      // When enable_multi_segment_candidate is false (default):
      // Multi-segment input is resized via CheckResizeSegmentsRequest.
      let segments = Segments()
      initSegment("へいせい", "平成", segments)
      appendSegment("23", "23", segments)
      appendSegment("ねん", "年", segments)
      let request = ConversionRequest()

      let resizeRequest = try #require(rewriter.checkResizeSegmentsRequest(request, segments))
      #expect(resizeRequest.segmentIndex == 0)
      #expect(Int(resizeRequest.segmentSizes[0]) == Util.charsLen("へいせい23ねん"))
    }

    do {
      // When enable_multi_segment_candidate is true:
      // CheckResizeSegmentsRequest returns std::nullopt.
      let segments = Segments()
      initSegment("へいせい", "平成", segments)
      appendSegment("23", "23", segments)
      appendSegment("ねん", "年", segments)
      var requestProto = Genmai_Commands_Request()
      requestProto.decoderExperimentParams.enableMultiSegmentCandidate = true
      let request = ConversionRequestBuilder().setRequest(requestProto).build()

      let resizeRequest = rewriter.checkResizeSegmentsRequest(request, segments)
      #expect(resizeRequest == nil)
    }

    do {
      // Legacy rewrite on single (or resized) segment:
      let segments = Segments()
      initSegment("へいせい23ねん", "平成23年", segments)
      let request = ConversionRequest()
      #expect(rewriter.rewrite(request, segments))
      #expect(hasCandidate(segments.segment(0), "2011年"))
    }

    do {
      // Legacy rewrite when following segment starts with "ねん":
      let segments = Segments()
      initSegment("へいせい23", "平成23", segments)
      appendSegment("ねん", "年", segments)
      let request = ConversionRequest()
      #expect(rewriter.rewrite(request, segments))
      #expect(hasCandidate(segments.segment(0), "2011"))
    }
  }
}
