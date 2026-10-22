// Port of mozc/src/prediction/zero_query_decoder_test.cc (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private func createHistoryResult(_ key: String, _ value: String) -> PredictionResult {
  var result = PredictionResult()
  result.key = key
  result.value = value
  return result
}

// Essentially the same logic as converter::EncodeLengths in
// converter/inner_segment.h.
private func encodeBoundary(_ keyLen: UInt8, _ valueLen: UInt8) -> UInt32 {
  UInt32(keyLen) | (UInt32(valueLen) << 8) | (UInt32(keyLen) << 16) | (UInt32(valueLen) << 24)
}

/// absl::FromCivil(absl::CivilSecond(y, m, d, h, 0, 0), absl::UTCTimeZone()).
private func utcDate(_ y: Int, _ m: Int, _ d: Int, _ h: Int) -> Date {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = .gmt
  guard let date = calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h)) else {
    Issue.record("invalid date \(y)-\(m)-\(d) \(h):00")
    return Date(timeIntervalSince1970: 0)
  }
  return date
}

private let kTestZeroQueryTokenArray: [UInt8] = DataManagerTestSupport.cBytes(
  // The last two items must be 0x00, because they are now unused field.
  // {"あ", "❕", ZERO_QUERY_EMOJI, 0x00, 0x00}
  #"\x04\x00\x00\x00"# + #"\x02\x00\x00\x00"# + #"\x03\x00"# + #"\x00\x00"#
    + #"\x00\x00\x00\x00"#
    // {"ああ", "( •̀ㅁ•́;)", ZERO_QUERY_EMOTICON, 0x00, 0x00}
    + #"\x05\x00\x00\x00"# + #"\x01\x00\x00\x00"# + #"\x02\x00"# + #"\x00\x00"#
    + #"\x00\x00\x00\x00"#
    // {"あい", "❕", ZERO_QUERY_EMOJI, 0x00, 0x00}
    + #"\x06\x00\x00\x00"# + #"\x02\x00\x00\x00"# + #"\x03\x00"# + #"\x00\x00"#
    + #"\x00\x00\x00\x00"#
    // {"あい", "❣", ZERO_QUERY_NONE, 0x00, 0x00}
    + #"\x06\x00\x00\x00"# + #"\x03\x00\x00\x00"# + #"\x00\x00"# + #"\x00\x00"#
    + #"\x00\x00\x00\x00"#
    // {"猫", "😾", ZERO_QUERY_EMOJI, 0x00, 0x00}
    + #"\x07\x00\x00\x00"# + #"\x08\x00\x00\x00"# + #"\x03\x00"# + #"\x00\x00"#
    + #"\x00\x00\x00\x00"#)

private let kTestZeroQueryStrings = [
  "", "( •̀ㅁ•́;)", "❕", "❣", "あ", "ああ", "あい", "猫", "😾",
]

@Suite(.enabled(if: predictionMockDataAvailable, "mock_genmai.data is missing"))
struct ZeroQueryDecoderTests {
  let modules: PredictionTestModules
  let decoder: ZeroQueryDecoder

  init() throws {
    modules = try PredictionTestModules.mock()
    decoder = ZeroQueryDecoder(modules)
  }

  private var posMatcher: PosMatcher { modules.getPosMatcher() }

  private static func zeroQueryRequest() -> Genmai_Commands_Request {
    var request = Genmai_Commands_Request()
    request.zeroQuerySuggestion = true
    return request
  }

  private static func weekdayRequest() -> Genmai_Commands_Request {
    var request = zeroQueryRequest()
    request.decoderExperimentParams.enableWeekdayZeroQueryPrediction = true
    return request
  }

  private static func context(_ precedingText: String) -> Genmai_Commands_Context {
    var context = Genmai_Commands_Context()
    context.precedingText = precedingText
    return context
  }

  @Test func emptyRequestReturnsEmpty() {
    let request = ConversionRequest()
    #expect(decoder.decode(request).isEmpty)
  }

  @Test func zeroQuerySuggestionAfterNumbers() throws {
    let requestProto = Self.zeroQueryRequest()

    do {
      let kExpectedValue = "月"
      let history = createHistoryResult("12", "12")
      let request = ConversionRequestBuilder()
        .setHistoryResult(history)
        .setRequest(requestProto)
        .build()

      let results = decoder.decode(request)
      #expect(!results.isEmpty)

      let target = try #require(results.first { $0.value.bytesEqual(kExpectedValue) })
      #expect(target.value == kExpectedValue)
      #expect(target.lid == posMatcher.getCounterSuffixWordId())
      #expect(target.rid == posMatcher.getCounterSuffixWordId())
    }

    do {
      // A random number
      let kExpectedValue = "個"
      let history = createHistoryResult("66050713", "66050713")
      let request = ConversionRequestBuilder()
        .setHistoryResult(history)
        .setRequest(requestProto)
        .build()

      let results = decoder.decode(request)
      #expect(!results.isEmpty)
      #expect(results.contains { $0.value.bytesEqual(kExpectedValue) })
    }
  }

  @Test func triggerNumberZeroQuerySuggestion() {
    let requestProto = Self.zeroQueryRequest()

    let kTestCases: [(String, String, String, Bool)] = [
      ("12", "12", "月", true), ("12", "１２", "月", true),
      ("12", "壱拾弐", "月", false), ("12", "十二", "月", false),
      ("12", "一二", "月", false), ("12", "Ⅻ", "月", false),
      ("あか", "12", "月", true),  // T13N
      ("あか", "１２", "月", true),  // T13N
      ("じゅう", "10", "時", true), ("じゅう", "１０", "時", true),
      ("じゅう", "十", "時", false), ("じゅう", "拾", "時", false),
    ]

    for (historyKey, historyValue, findSuffixValue, expectedResult) in kTestCases {
      let history = createHistoryResult(historyKey, historyValue)
      let request = ConversionRequestBuilder()
        .setHistoryResult(history)
        .setRequest(requestProto)
        .build()

      let results = decoder.decode(request)
      let found = results.contains { $0.value.bytesEqual(findSuffixValue) }
      #expect(
        found == expectedResult,
        "Failed for history: \(historyValue), suffix: \(findSuffixValue)")
    }
  }

  @Test func generalZeroQuery() {
    let request = ConversionRequestBuilder()
      .setContext(Self.context("あけまして"))
      .setRequest(Self.zeroQueryRequest())
      .build()

    let results = decoder.decode(request)
    #expect(!results.isEmpty)
  }

  @Test func getZeroQueryCandidates() {
    // Create test zero query data.
    let stringArrayData = SerializedStringArray.serializeToBuffer(kTestZeroQueryStrings)
    let zeroQueryDict = ZeroQueryDict(
      DataView(copying: kTestZeroQueryTokenArray), DataView(copying: stringArrayData))

    let kTestCases: [(String, Bool, [String], [ZeroQueryType])] = [
      ("あい", true, ["❕", "❣"], [.emoji, .none]),
      ("猫", true, ["😾"], [.emoji]),
      ("あ", false, [], []),  // Do not look up for one-char non-Kanji key
      ("あい", true, ["❕", "❣"], [.emoji, .none]),
      ("あいう", false, [], []),
      ("", false, [], []),
      ("ああ", true, ["( •̀ㅁ•́;)"], [.emoticon]),
    ]

    for (key, _, expectedCandidates, expectedTypes) in kTestCases {
      #expect(expectedCandidates.count == expectedTypes.count)

      let request = ConversionRequest()
      var results: [PredictionResult] = []
      let kId: UInt16 = 0  // EOS
      decoder.getZeroQueryCandidatesForKey(request, key, zeroQueryDict, kId, kId, &results)
      #expect(results.count == expectedCandidates.count, "key: \(key)")
      for i in 0..<min(results.count, expectedCandidates.count) {
        #expect(results[i].value == expectedCandidates[i])
      }
    }
  }

  @Test func weekdayZeroQuerySuggestion() throws {
    // Set clock to Wednesday, September 16, 2026 12:00:00 UTC.
    try withScopedClockMock(utcDate(2026, 9, 16, 12)) { _ in
      var requestProto = Self.zeroQueryRequest()

      // 1. Default (disabled): should not emit day-of-week candidates.
      do {
        let history = createHistoryResult("9/16", "9/16")
        let request = ConversionRequestBuilder()
          .setHistoryResult(history)
          .setRequest(requestProto)
          .build()
        let results = decoder.decode(request)
        for r in results {
          #expect(r.value != " (水)")
        }
      }

      // 2. Enabled via DecoderExperimentParams.
      requestProto.decoderExperimentParams.enableWeekdayZeroQueryPrediction = true

      let kTestCases: [(String, Bool, String, String)] = [
        ("9/16", false, " (水)", "すい"),
        ("9/16", true, " (水)", "すい"),
        ("9/17", false, " (木)", "もく"),
        ("09/16", true, " (水)", "すい"),
        ("2026/09/16", false, " (水)", "すい"),
        ("9月16日", false, " (水)", "すい"),
        ("2026年9月16日", true, " (水)", "すい"),
        ("予定は９／１６", true, " (水)", "すい"),
        ("明日は９月１７日", true, " (木)", "もく"),
      ]

      for (input, usePrecedingText, expectedValue, expectedKey) in kTestCases {
        var builder = ConversionRequestBuilder().setRequest(requestProto)
        if usePrecedingText {
          builder = builder.setContext(Self.context(input))
        } else {
          builder = builder.setHistoryResult(createHistoryResult(input, input))
        }
        let request = builder.build()
        let results = decoder.decode(request)

        try #require(results.count >= 1, "Input: \(input)")
        #expect(results[0].value == expectedValue, "Input: \(input)")
        #expect(results[0].key == expectedKey, "Input: \(input)")
        #expect(results[0].lid == 0, "Input: \(input)")
        #expect(results[0].rid == 0, "Input: \(input)")
        #expect(results[0].wcost == -500, "Input: \(input)")
        #expect((results[0].attributes & Attribute.disableRescoring) != 0, "Input: \(input)")
        #expect((results[0].attributes & Attribute.noLearning) != 0, "Input: \(input)")
        for i in 1..<results.count {
          #expect(
            !results[i].value.hasBytePrefix(" （"),
            "Redundant full-width weekday candidate: \(results[i].value)")
          #expect(
            !results[i].value.hasByteSuffix("曜日"),
            "Redundant full-name weekday candidate: \(results[i].value)")
          #expect(results[i].value != "(")
          #expect(results[i].value != " (")
          #expect(results[i].value != "（")
          #expect(results[i].value != " （")
        }
      }
    }
  }

  @Test func weekdayZeroQueryNotRepeatedAfterCommittingWeekday() {
    withScopedClockMock(utcDate(2026, 9, 16, 12)) { _ in
      let requestProto = Self.weekdayRequest()

      // Case 1: `preceding_text` is still "9/16" (not yet updated by client
      // during Session::CommitCandidate), while `history_result` contains
      // " (水)".
      do {
        let request = ConversionRequestBuilder()
          .setContext(Self.context("9/16"))
          .setHistoryResult(createHistoryResult("すい", " (水)"))
          .setRequest(requestProto)
          .build()
        for r in decoder.decode(request) {
          #expect(r.value != " (水)")
        }
      }

      // Case 2: `preceding_text` is still "9/16", while `history_result`
      // contains concatenated segments "9/16 (水)".
      do {
        let request = ConversionRequestBuilder()
          .setContext(Self.context("9/16"))
          .setHistoryResult(createHistoryResult("9/16すい", "9/16 (水)"))
          .setRequest(requestProto)
          .build()
        for r in decoder.decode(request) {
          #expect(r.value != " (水)")
        }
      }

      // Case 3: `preceding_text` has been updated to "9/16 (水)" with empty
      // `history_result`.
      do {
        let request = ConversionRequestBuilder()
          .setContext(Self.context("9/16 (水)"))
          .setRequest(requestProto)
          .build()
        for r in decoder.decode(request) {
          #expect(r.value != " (水)")
        }
      }
    }
  }

  @Test func weekdayZeroQueryWithSplitCommitAndMultiSegmentHistory() throws {
    try withScopedClockMock(utcDate(2026, 9, 16, 12)) { _ in
      let requestProto = Self.weekdayRequest()

      // Case 1: `preceding_text` is "9/16" and `history_result` is "16" (e.g.,
      // after HistoryReconstructor extracts the trailing number token, or
      // when `preceding_text` already includes the last committed segment).
      do {
        let request = ConversionRequestBuilder()
          .setContext(Self.context("9/16"))
          .setHistoryResult(createHistoryResult("16", "16"))
          .setRequest(requestProto)
          .build()
        let results = decoder.decode(request)
        try #require(results.count >= 1)
        #expect(results[0].value == " (水)")
        #expect(results[0].key == "すい")
      }

      // Case 2: Multi-segment history where Segment 0 = "9" and Segment 1 =
      // "16", and "/" was committed directly to the editor
      // (`preceding_text` = "9/").
      do {
        var history = createHistoryResult("916", "916")
        history.innerSegmentBoundary.append(encodeBoundary(1, 1))
        history.innerSegmentBoundary.append(encodeBoundary(2, 2))
        let request = ConversionRequestBuilder()
          .setContext(Self.context("9/"))
          .setHistoryResult(history)
          .setRequest(requestProto)
          .build()
        let results = decoder.decode(request)
        try #require(results.count >= 1)
        #expect(results[0].value == " (水)")
        #expect(results[0].key == "すい")
      }

      // Case 3: Multi-segment history where Segment 0 = "9月" and Segment 1 =
      // "16日" (`last_history_value` = "16日", `full_history_value` =
      // "9月16日").
      do {
        var history = createHistoryResult("9がつ16にち", "9月16日")
        history.innerSegmentBoundary.append(encodeBoundary(7, 4))
        history.innerSegmentBoundary.append(encodeBoundary(8, 5))
        let request = ConversionRequestBuilder()
          .setHistoryResult(history)
          .setRequest(requestProto)
          .build()
        let results = decoder.decode(request)
        try #require(results.count >= 1)
        #expect(results[0].value == " (水)")
        #expect(results[0].key == "すい")
      }
    }
  }

  @Test func weekdayZeroQueryFiltersRedundantOpenParenthesesAndWeekdays() throws {
    try withScopedClockMock(utcDate(2026, 9, 16, 12)) { _ in
      let request = ConversionRequestBuilder()
        .setHistoryResult(createHistoryResult("9/16", "9/16"))
        .setRequest(Self.weekdayRequest())
        .build()

      var results: [PredictionResult] = []
      func addCandidate(_ val: String) {
        var r = PredictionResult()
        r.value = val
        results.append(r)
      }
      // Redundant candidates that might be predicted by SupplementalModel.
      addCandidate("(")
      addCandidate(" (")
      addCandidate("（")
      addCandidate(" （")
      addCandidate("()")
      addCandidate("（）")
      addCandidate(" (金)")
      addCandidate("（水）")
      addCandidate("水曜日")
      // Valid non-redundant candidate.
      addCandidate("の")

      #expect(decoder.aggregateWeekdayZeroQuery(request, &results))

      try #require(results.count == 2)
      #expect(results[0].value == "の")
      #expect(results[1].value == " (水)")
    }
  }

  @Test func weekdayZeroQuerySlidingWindowAndValidation() throws {
    let requestProto = Self.weekdayRequest()

    // 1. Sliding window forward rollover: typed in late December 2026 -> Jan
    // 2027
    try withScopedClockMock(utcDate(2026, 12, 20, 12)) { _ in
      // Jan 10, 2027 is Sunday ("日"). (Jan 10, 2026 was Saturday).
      let request = ConversionRequestBuilder()
        .setContext(Self.context("1/10"))
        .setRequest(requestProto)
        .build()
      let results = decoder.decode(request)
      try #require(results.count >= 1)
      #expect(results[0].value == " (日)")
      #expect(results[0].key == "にち")
    }

    // 2. Sliding window backward rollover: typed in early January 2026 -> Dec
    // 2025
    try withScopedClockMock(utcDate(2026, 1, 5, 12)) { _ in
      // Dec 28, 2025 is Sunday ("日"). (Dec 28, 2026 is Monday).
      let request = ConversionRequestBuilder()
        .setContext(Self.context("12/28"))
        .setRequest(requestProto)
        .build()
      let results = decoder.decode(request)
      try #require(results.count >= 1)
      #expect(results[0].value == " (日)")
      #expect(results[0].key == "にち")
    }

    // 3. Leap year validation: 2028/2/29 is valid (Tuesday), 2026/2/29 is
    // invalid
    try withScopedClockMock(utcDate(2026, 9, 16, 12)) { _ in
      do {
        let request = ConversionRequestBuilder()
          .setContext(Self.context("2028/2/29"))
          .setRequest(requestProto)
          .build()
        let results = decoder.decode(request)
        try #require(results.count >= 1)
        #expect(results[0].value == " (火)")
        #expect(results[0].key == "か")
      }

      let kInvalidInputs = [
        "2/30", "2026/2/29", "13/1", "0/10", "192.168.1/24", "1/2/3",
      ]
      for invalidInput in kInvalidInputs {
        let request = ConversionRequestBuilder()
          .setContext(Self.context(invalidInput))
          .setRequest(requestProto)
          .build()
        let results = decoder.decode(request)
        for r in results {
          #expect(
            !r.value.hasBytePrefix(" ("),
            "Unexpected date candidate for invalid input: \(invalidInput) -> \(r.value)")
        }
      }
    }
  }
}
