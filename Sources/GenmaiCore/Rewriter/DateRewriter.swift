// Port of mozc/src/rewriter/date_rewriter.{h,cc} (3.35.6354).
//
// Date comment style are following.
//  - If the input number converts strictly 2 character with padding, comment
//  format is like "HH" or "MM".
//   e.g.) "YYYY/MM/DD HH:MM" ->  "2011/01/30 03:20"
//  - If the input number converts string without padding, comment format is
//  like "H" or "M"
//   e.g.) "Y/M/D H:M" -> "645/2/3 9:2"
//
// Deviations from C++:
// - `date_rewriter_internal::DateCandidate` is `DateRewriter.DateCandidate`.
// - absl::CivilMinute is replaced by a small private `CivilMinute` struct
//   (proleptic Gregorian, built from GenmaiBase `CivilDay`), and
//   absl::FormatTime is replaced by `formatTime`, which only implements the
//   conversion specifiers that `ConvertExtraFormat` can produce (`%%`, `%Y`,
//   `%m`, `%d`, `%H`, `%M`; every user-supplied `%` is escaped to `%%`).
// - The unsigned hour / minute / year / month / day parameters of
//   ConvertTime / ConvertDateWithYear take `Int`; negative values are invalid,
//   which matches the C++ behavior where they wrap to huge `uint32_t` values.
// - `RewriteEra` returns false when the segment has no candidates (C++ would
//   dereference `candidate(0)` of an empty segment).
// - `Segments::range` is `[Segment]` (segments are reference types).

import Foundation
import GenmaiBase
import GenmaiProtocol

public final class DateRewriter: RewriterInterface, Sendable {
  public struct DateCandidate: Sendable, Equatable {
    public var candidate: String
    public var description: String

    public init(_ candidate: String, _ description: String) {
      self.candidate = candidate
      self.description = description
    }
  }

  /// Type of diff (e.g. year, month, date, etc).
  public enum DateType: Sendable {
    case year
    case month
    case date
    case weekday
    case currentTime
    case dateAndCurrentTime
  }

  public struct DateData: Sendable {
    public let key: String
    public let value: String
    public let description: String
    /// diff from the current time in day or month or year
    public let diff: Int
    /// type of diff (e.g. year, month, date, etc).
    public let type: DateType
  }

  // The key of the extra format.
  // The value can be specified via user dictionary.
  // The value accepts the same format with absl::FormatTime, which is extended
  // from std::strftime.
  // https://abseil.io/docs/cpp/guides/time#formatting-absltime
  //
  // THIS IS EXPERIMENTAL. This functionality may be dropped or changed.
  public static let kExtraDateFormatKey = "DATE_FORMAT"
  public static let kExtraDatetimeFormatKey = "DATETIME_FORMAT"

  private let dictionary: (any DictionaryInterface)?

  public init() {
    dictionary = nil
  }

  public init(_ dictionary: any DictionaryInterface) {
    self.dictionary = dictionary
  }

  // MARK: - Public static helpers

  /// In general, Japanese era can be identified without the month.
  /// However, during the era migration time, we have to check the month., i.e.,
  /// 2019/01-04 => Heisei, 2019/05- => new era.
  /// The `month` field is only checked at the year of 2019.
  /// The case o year=2019 and month=0 is treated as "entire year" and returns
  /// both Heisei and the new e
  @discardableResult
  public static func adToEra(_ year: Int, _ month: Int, _ results: inout [String]) -> Bool {
    if year < 645 {
      return false
    }

    // This block should be kept until 2020
    // to change the year depending on the month.
    if year == 2019 {
      if month == 0 {
        // When month is not specified, show both.
        // Shows 令和 first.
        expandYear("令和", 1, &results)
        expandYear("平成", 31, &results)
      } else if month <= 4 {
        expandYear("平成", 31, &results)
      } else {
        expandYear("令和", 1, &results)
      }
      return true
    }

    if year > 2200 {
      return false
    }

    // The order is south to north.
    var eras: [String] = []
    var r = false
    r = adToEraForCourt(kEraData, year, &eras)
    if year > 1331 && year < 1393 {
      r = adToEraForCourt(kNorthEraData, year, &eras) || r
    }
    // 1334 requires dedupe
    for i in 0..<eras.count {
      var found = false
      for j in 0..<i where eras[j].bytesEqual(eras[i]) {
        found = true
      }
      if !found {
        results.append(eras[i])
      }
    }
    return r
  }

  public static func adToEra(_ year: Int, _ month: Int) -> [String] {
    var results: [String] = []
    if !adToEra(year, month, &results) {
      results.removeAll()
    }
    return results
  }

  /// Converts AD to Japanese ERA.
  /// If given string is invalid, this function does not nothing and
  /// returns an empty vector.
  /// The results will have multiple variants.
  /// e.g.)
  ///   key              -> list of result and description
  ///   -----------------------------------------------
  ///   "へいせい20ねん" -> {{"2008年", "平成20年"}, {"２００８年", "平成20年"},
  ///                       {"二〇〇八年", "平成20年"}}
  ///   "しょうわ2ねん"  -> {{"1927年", "昭和2年"}, {"１９２７年", "昭和2年"},
  ///                       {"一九二七年", "昭和2年"}, {"1313年", "正和2年"},
  ///                       {"１３１３年", "正和2年"}, {"一三一三年", "正和2年"}}
  ///
  /// The `年` suffix is appended to the reuslts if the `key` has the `ねん`
  /// suffix, but it's omitted otherwise.
  public static func eraToAd(_ key: some StringProtocol) -> [(String, String)] {
    let key = String(key)
    var resultsAndDescriptions: [(String, String)] = []
    // The order is south to north, older to newer
    eraToAdForCourt(kEraData, key, &resultsAndDescriptions)
    eraToAdForCourt(kNorthEraData, key, &resultsAndDescriptions)
    return resultsAndDescriptions
  }

  /// Converts given time to string expression.
  /// If given time information is invalid, this function does nothing and
  /// returns false.
  /// Over 24-hour expression is only allowed in case of lower than 30 hour.
  /// The "hour" argument only accepts between 0 and 29.
  /// The "min" argument only accepts between 0 and 59.
  @discardableResult
  public static func convertTime(_ hour: Int, _ min: Int, _ results: inout [String]) -> Bool {
    if !isValidTime(hour, min) {
      return false
    }
    results.append("\(hour):\(pad2(min))")
    results.append("\(hour)時\(pad2(min))分")
    if min == 30 {
      results.append("\(hour)時半")
    }

    if (hour % 24) * 60 + min < 720 {  // 0:00 -- 11:59
      results.append("午前\(hour % 24)時\(min)分")
      if min == 30 {
        results.append("午前\(hour % 24)時半")
      }
    } else {
      results.append("午後\((hour - 12) % 24)時\(min)分")
      if min == 30 {
        results.append("午後\((hour - 12) % 24)時半")
      }
    }
    return true
  }

  public static func convertTime(_ hour: Int, _ min: Int) -> [String] {
    var results: [String] = []
    if !convertTime(hour, min, &results) {
      results.removeAll()
    }
    return results
  }

  /// Converts given date to string expression.
  /// If given date information is invalid, this function does nothing and
  /// returns false.
  /// The "year" argument only accepts positive integer.
  /// The "month" argument only accepts between 1 and 12.
  /// The "day" argument only accept valid day. This function deals with leap
  /// year.
  @discardableResult
  public static func convertDateWithYear(
    _ year: Int, _ month: Int, _ day: Int, _ results: inout [String]
  ) -> Bool {
    if !isValidDate(year, month, day) {
      return false
    }
    // Generate "Y/MM/DD", "Y-MM-DD" and "Y年M月D日" formats.
    results.append("\(year)/\(pad2(month))/\(pad2(day))")
    results.append("\(year)-\(pad2(month))-\(pad2(day))")
    results.append("\(year)年\(month)月\(day)日")
    return true
  }

  public static func convertDateWithYear(_ year: Int, _ month: Int, _ day: Int) -> [String] {
    var results: [String] = []
    if !convertDateWithYear(year, month, day, &results) {
      results.removeAll()
    }
    return results
  }

  // MARK: - RewriterInterface

  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType {
    if request.request().mixedConversion {
      return .all
    }
    return .conversion
  }

  public func checkResizeSegmentsRequest(_ request: ConversionRequest, _ segments: Segments)
    -> Rewriter.ResizeSegmentsRequest?
  {
    if !request.config().useDateConversion {
      // no use_date_conversion
      return nil
    }

    if request.request().decoderExperimentParams.enableMultiSegmentCandidate {
      return nil
    }

    if segments.resized {
      // If the given segments are resized by user, don't modify anymore.
      return nil
    }

    for segmentIndex in 0..<segments.conversionSegmentsSize {
      if let resizeRequest = checkResizeSegmentsForAd(request, segments, segmentIndex) {
        return resizeRequest
      }
    }

    return nil
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    if !request.config().useDateConversion {
      // no use_date_conversion
      return false
    }

    let conversionSegments = segments.conversionSegments
    if conversionSegments.isEmpty {
      return false
    }

    var modified = false
    let extraDateFormats = getExtraFormats(dictionary, DateRewriter.kExtraDateFormatKey)
    let extraDatetimeFormats = getExtraFormats(dictionary, DateRewriter.kExtraDatetimeFormatKey)
    var numDone = 1
    var restSegments = conversionSegments
    while !restSegments.isEmpty {
      let seg = restSegments[0]

      if DateRewriter.rewriteAd(request, restSegments, &numDone)
        || DateRewriter.rewriteDate(seg, extraDateFormats, extraDatetimeFormats, &numDone)
        || DateRewriter.rewriteEra(restSegments, &numDone)
      {
        modified = true
        restSegments = restSegments.drop(numDone)
        continue
      }

      numDone = 1
      restSegments = restSegments.drop(numDone)
    }

    // Select the insert position by Romaji table.  Note:
    // TOGGLE_FLICK_TO_HIRAGANA uses digits for Hiragana composing, date/time
    // conversion is performed even when typing Hiragana characters.  Thus, it
    // should not be promoted.
    var insertPos = conversionSegments[0].candidatesSize
    switch request.request().specialRomanjiTable {
    case .qwertyMobileToHalfwidthascii, .flickToNumber, .toggleFlickToNumber:
      insertPos = 1
    default:
      break
    }
    if DateRewriter.rewriteConsecutiveDigits(request.composer(), insertPos, segments) {
      modified = true
    }

    return modified
  }

  // MARK: - Private rewrites

  /// If the rewrite is done, returns `true` and sets the `numDoneOut` to the
  /// number of segments processed. The `numDoneOut` is not modified if the
  /// rewrite is not done.
  private static func rewriteDate(
    _ segment: Segment, _ extraDateFormats: [String], _ extraDatetimeFormats: [String],
    _ numDoneOut: inout Int
  ) -> Bool {
    let key = segment.key
    guard let data = kDateData.first(where: { key.bytesEqual($0.key) }) else {
      return false
    }

    var conversions = getConversions(data, extraDateFormats, extraDatetimeFormats)
    if conversions.isEmpty {
      return false
    }

    // Calculate insert_idx
    // Candidates will be inserted less than 10th candidate.
    let kMaxIdx = 10
    let endIdx = min(kMaxIdx, segment.candidatesSize)
    var candIdx = 0
    while candIdx < endIdx {
      if segment.candidate(candIdx).value.bytesEqual(data.value) {
        break
      }
      candIdx += 1
    }
    if candIdx == endIdx {
      return false
    }

    // Insert words.
    let baseCand = segment.candidate(candIdx)
    var candidates: [Candidate] = []
    candidates.reserveCapacity(conversions.count)
    for i in conversions.indices {
      candidates.append(createCandidate(baseCand, conversions[i], data.description))
    }
    conversions.removeAll()

    // Date candidates are too many, therefore highest candidate show at most 3rd.
    // TODO(nona): learn date candidate even if the date is changed.
    let minIdx = min(3, endIdx)
    let insertIdx = Swift.min(Swift.max(candIdx + 1, minIdx), endIdx)
    segment.insertCandidates(insertIdx, candidates)
    numDoneOut = 1
    return true
  }

  private static func rewriteEra(_ segmentsRange: [Segment], _ numDoneOut: inout Int) -> Bool {
    // Rewrite:
    // * If the first segment ends with the `kNenKey`, or
    // * If the second segment starts with the `kNenKey`.
    let segment = segmentsRange[0]
    var key = Substring(segment.key)
    let hasSuffix = key.hasByteSuffix(kNenKey)
    if hasSuffix {
      key = key.byteSubstring(from: 0, length: key.byteCount - kNenKey.byteCount)
    } else if segmentsRange.count < 2 || !segmentsRange[1].key.hasBytePrefix(kNenKey) {
      return false
    }

    if Util.getScriptType(key) != .number {
      return false
    }

    let len = Util.charsLen(key)
    if len < 3 || len > 4 {
      // Too long year
      return false
    }

    let yearStr = Japanese.fullWidthAsciiToHalfWidthAscii(key)

    guard let year = UInt32(yearStr) else {
      return false
    }

    var results: [String] = []
    if !adToEra(Int(year), 0, /* unknown month */ &results) {
      return false
    }

    if segment.candidatesSize == 0 {
      return false
    }

    let kDescription = "和暦"
    let baseCand = segment.candidate(0)
    var candidates: [Candidate] = []
    candidates.reserveCapacity(results.count)
    for var value in results {
      if hasSuffix {
        value += kNenValue
      }
      let candidate = createCandidate(baseCand, value, kDescription)
      candidate.attributes &= ~Attribute.noVariantsExpansion
      candidates.append(candidate)
    }

    let kInsertPosition = 2
    segment.insertCandidates(kInsertPosition, candidates)

    numDoneOut = hasSuffix ? 1 : 2
    return true
  }

  private static func rewriteAd(
    _ request: ConversionRequest, _ segmentsRange: [Segment], _ numDoneOut: inout Int
  ) -> Bool {
    if segmentsRange.isEmpty {
      return false
    }

    if request.request().decoderExperimentParams.enableMultiSegmentCandidate {
      return rewriteAdMultiSegmentCandidate(segmentsRange, &numDoneOut)
    }
    return rewriteAdResized(segmentsRange, &numDoneOut)
  }

  /// This function changes the default conversion behavior. For example, when
  /// the input is "taishou2nen", it is converted to 3 segments by default
  /// without this function, but this function merges them to 1 segment. Users
  /// can still resize segments to get the behavior without this function, and
  /// the engine learns the resize for the same string next time, but there will
  /// be cases where the default conversion looks degraded from what users
  /// expect.
  ///
  /// Supporting multiple segments without resizing has benefits for users, such
  /// as they can still see other candidates of the era segment. But unlike
  /// `RewriteEra` which supports multiple segments without merging, this
  /// function needs to produce a candidate for 2 segments (the era and the
  /// digits), which isn't easy.
  private func checkResizeSegmentsForAd(
    _ request: ConversionRequest, _ segments: Segments, _ segmentIndex: Int
  ) -> Rewriter.ResizeSegmentsRequest? {
    // Find the first segment that ends with `kNenKey`.
    let kMaxSegments = 3  // Only up to 3 segments.
    var hasSuffix = false
    var shouldResizeLastSegment = false
    var keys: [Substring] = []
    for segment in segments.conversionSegments.drop(segmentIndex) {
      let key = Substring(segment.key)
      if var pos = byteFind(key, kNenKey) {
        if pos == 0 && keys.count == 1 {
          // If the second key starts with the `kNenKey`, `RewriteAd()` can
          // handle it without resizing.
          return nil
        }
        pos += kNenKey.byteCount
        if pos == key.byteCount {
          keys.append(key)
        } else {
          // The segment has `kNenKey` and following characters; e.g.,
          // "nendesu".
          keys.append(key.byteSubstring(from: 0, length: pos))
          shouldResizeLastSegment = true
        }
        hasSuffix = true
        break
      }
      if keys.count >= kMaxSegments - 1 {
        return nil
      }
      keys.append(key)
    }
    if !hasSuffix || (keys.count <= 1 && !shouldResizeLastSegment) {
      return nil
    }
    let key = keys.joined()
    let keyLen = Util.charsLen(key)
    if keyLen > Int(UInt8.max) {
      return nil
    }
    let segmentSize = UInt8(keyLen)

    // Try to convert era to AD.
    let resultsAndDescriptions = DateRewriter.eraToAd(key)
    if resultsAndDescriptions.isEmpty {
      return nil
    }

    return Rewriter.ResizeSegmentsRequest(
      segmentIndex: segmentIndex, segmentSizes: [segmentSize, 0, 0, 0, 0, 0, 0, 0])
  }

  /// When only one conversion segment has consecutive number characters,
  /// this function adds date and time candidates.
  /// e.g.)
  ///   key  -> candidates will be added
  ///   ------------------------------------------------
  ///   0101 -> "1月1日、01/01、1時1分,午前1時1分、1:01"
  ///   2020 -> "20時20分、午後8時20分、20:20"
  ///   2930 -> "29時30分、29時半、午前5時30分、午前5時半"
  ///   123  -> "1月23日、01/23、1:23"
  private static func rewriteConsecutiveDigits(
    _ composer: ComposerData, _ insertPosition: Int, _ segments: Segments
  ) -> Bool {
    if segments.conversionSegmentsSize != 1 {
      // This method rewrites a segment only when the segments has only
      // one conversion segment.
      // This is spec matter.
      // Rewriting multiple segments will not make users happier.
      return false
    }
    let segment = segments.mutableConversionSegment(0)

    // segment->candidate(0) or segment->meta_candidate(0) is used as reference.
    // Check the existence before generating candidates to save time.
    if segment.candidatesSize == 0 && segment.metaCandidatesSize == 0 {
      // No (meta) candidates are found
      return false
    }

    // Generate candidates.  The results contain <candidate, description> pairs.
    var results: [DateCandidate] = []
    if let numberStr = getNDigits(composer, segments, 2) {
      if !rewriteConsecutiveTwoDigits(numberStr, &results) {
        return false
      }
    } else if let numberStr = getNDigits(composer, segments, 3) {
      if !rewriteConsecutiveThreeDigits(numberStr, &results) {
        return false
      }
    } else if let numberStr = getNDigits(composer, segments, 4) {
      if !rewriteConsecutiveFourDigits(numberStr, &results) {
        return false
      }
    }
    if results.isEmpty {
      return false
    }

    // The existence of segment->candidate(0) or segment->meta_candidate(0) is
    // guaranteed at the above check.
    let topCand = segment.candidatesSize > 0 ? segment.candidate(0) : segment.metaCandidate(0)
    var candidates: [Candidate] = []
    candidates.reserveCapacity(results.count)
    for result in results {
      candidates.append(createCandidate(topCand, result.candidate, result.description))
    }

    var insertPosition = insertPosition
    if insertPosition < 0 {
      insertPosition = segment.candidatesSize
    }
    segment.insertCandidates(insertPosition, candidates)
    return true
  }

  // Helper functions for RewriteConsecutiveDigits().
  private static func rewriteConsecutiveTwoDigits(
    _ str: String, _ results: inout [DateCandidate]
  ) -> Bool {
    let s = Array(str.utf8)
    precondition(s.count == 2)
    let origSize = results.count
    let c = s.map { String(UnicodeScalar($0)) }
    let high = Int(s[0]) - 0x30
    let low = Int(s[1]) - 0x30
    if isValidMonthAndDay(high, low) {
      results.append(DateCandidate("\(c[0])/\(c[1])", kDateDescription))
      results.append(DateCandidate("\(c[0])月\(c[1])日", kDateDescription))
    }
    if isValidTime(high, low) {
      // "H時M分".
      generateKanjiTimeFormats(false, false, high, low, &results)
      // "午前H時M分".
      generateGozenGogoTimeFormats(false, false, high, low, &results)
    }
    return results.count > origSize
  }

  private static func rewriteConsecutiveThreeDigits(
    _ str: String, _ results: inout [DateCandidate]
  ) -> Bool {
    let s = Array(str.utf8)
    precondition(s.count == 3)
    let origSize = results.count
    let c = s.map { String(UnicodeScalar($0)) }

    let n = s.map { Int($0) - 0x30 }

    // Split pattern 1: N|NN
    let high1 = n[0]
    let low1 = 10 * n[1] + n[2]
    let isValidDate1 = isValidMonthAndDay(high1, low1) && s[1] != UInt8(ascii: "0")
    let isValidTime1 = isValidTime(high1, low1)

    // Split pattern 2: NN|N
    let high2 = 10 * n[0] + n[1]
    let low2 = n[2]
    let isValidDate2 = isValidMonthAndDay(high2, low2) && s[0] != UInt8(ascii: "0")
    let isValidTime2 = isValidTime(high2, low2) && s[0] != UInt8(ascii: "0")

    if isValidDate1 {
      // "M/DD"
      results.append(DateCandidate("\(c[0])/\(c[1])\(c[2])", kDateDescription))
    }
    if isValidDate2 {
      // "MM/D"
      results.append(DateCandidate("\(c[0])\(c[1])/\(c[2])", kDateDescription))
    }
    if isValidTime1 {
      // "H:MM"
      results.append(DateCandidate("\(c[0]):\(c[1])\(c[2])", kTimeDescription))
    }
    // Don't generate HH:M form as it is unusual.

    if isValidDate1 {
      // "M月DD日".
      results.append(DateCandidate("\(c[0])月\(c[1])\(c[2])日", kDateDescription))
    }
    if isValidDate2 {
      // "MM月D日"
      results.append(DateCandidate("\(c[0])\(c[1])月\(c[2])日", kDateDescription))
    }
    if isValidTime1 {
      // "M時DD分" etc.
      generateKanjiTimeFormats(false, true, high1, low1, &results)
    }
    if isValidTime2 {
      // "MM時D分" etc.
      generateKanjiTimeFormats(false, false, high2, low2, &results)
    }
    if isValidTime1 {
      // "午前M時DD分" etc.
      generateGozenGogoTimeFormats(false, true, high1, low1, &results)
    }
    if isValidTime2 {
      // "午前MM時D分" etc.
      generateGozenGogoTimeFormats(false, false, high2, low2, &results)
    }

    return results.count > origSize
  }

  private static func rewriteConsecutiveFourDigits(
    _ str: String, _ results: inout [DateCandidate]
  ) -> Bool {
    let s = Array(str.utf8)
    precondition(s.count == 4)
    let origSize = results.count
    let c = s.map { String(UnicodeScalar($0)) }

    let high = 10 * (Int(s[0]) - 0x30) + (Int(s[1]) - 0x30)
    let low = 10 * (Int(s[2]) - 0x30) + (Int(s[3]) - 0x30)

    let isValidDate = isValidMonthAndDay(high, low)
    let isValidTime = isValidTime(high, low)

    if isValidDate {
      // "MM/DD"
      results.append(DateCandidate("\(c[0])\(c[1])/\(c[2])\(c[3])", kDateDescription))
    }
    if isValidTime {
      // "MM:DD"
      results.append(DateCandidate("\(c[0])\(c[1]):\(c[2])\(c[3])", kTimeDescription))
    }
    if isValidDate && s[0] != UInt8(ascii: "0") && s[2] != UInt8(ascii: "0") {
      // "MM月DD日".  Don't generate this form if there is a leading zero in
      // month or day because it's rarely written like "01月01日".  Don't
      // generate "1月1日" too, as we shouldn't remove the zero explicitly added
      // by user.
      results.append(DateCandidate("\(c[0])\(c[1])月\(c[2])\(c[3])日", kDateDescription))
    }
    if isValidTime {
      // "MM時DD分" etc.
      generateKanjiTimeFormats(true, true, high, low, &results)
      if high >= 10 {
        // "午前MM時DD分" etc.
        generateGozenGogoTimeFormats(false, true, high, low, &results)
      }
    }

    return results.count > origSize
  }
}

// MARK: - File-private helpers

private struct YearData: Sendable {
  let ad: Int  // AD year
  let era: String  // Japanese year a.k.a., GENGO
  let key: String  // reading of the `era`
}

private let kDateDescription = "日付"
private let kTimeDescription = "時刻"
private let kNenKey = "ねん"
private let kNenValue = "年"

/// `%2.2d`.
private func pad2(_ n: Int) -> String {
  n >= 0 && n < 10 ? "0\(n)" : "\(n)"
}

/// `std::snprintf(buf, 4, "%d" or "%02d", num)`; nil when it does not fit.
private func printUint32(_ zeroPad2: Bool, _ num: Int) -> String? {
  let s = zeroPad2 ? pad2(num) : "\(num)"
  return s.utf8.count < 4 ? s : nil
}

/// Returns the byte offset of the first occurrence of `pattern` in `s`.
private func byteFind(_ s: some StringProtocol, _ pattern: some StringProtocol) -> Int? {
  let hay = Array(s.utf8)
  let pat = Array(pattern.utf8)
  if pat.isEmpty { return 0 }
  if pat.count > hay.count { return nil }
  for i in 0...(hay.count - pat.count) where hay[i..<(i + pat.count)].elementsEqual(pat) {
    return i
  }
  return nil
}

/// Helper function to generate "H時M分" time formats.
private func generateKanjiTimeFormats(
  _ hourZeroPad: Bool, _ minZeroPad: Bool, _ hour: Int, _ min: Int,
  _ results: inout [DateRewriter.DateCandidate]
) {
  guard let hourS = printUint32(hourZeroPad, hour), let minS = printUint32(minZeroPad, min) else {
    return
  }
  results.append(DateRewriter.DateCandidate("\(hourS)時\(minS)分", kTimeDescription))
  // "H時半".  Don't generate it when the printed hour starts with 0 because
  // formats like "03時半" is rarely used (but "3時半" is ok).
  if hourS.utf8.first != UInt8(ascii: "0") && min == 30 {
    results.append(DateRewriter.DateCandidate("\(hourS)時半", kTimeDescription))
  }
}

/// Helper function to generate "午前..." and "午後..." time formats.
private func generateGozenGogoTimeFormats(
  _ hourZeroPad: Bool, _ minZeroPad: Bool, _ hour: Int, _ min: Int,
  _ results: inout [DateRewriter.DateCandidate]
) {
  // "午前" and "午後" prefixes are only used for [0, 11].
  if hour >= 12 {
    return
  }
  guard let hourS = printUint32(hourZeroPad, hour), let minS = printUint32(minZeroPad, min) else {
    return
  }
  results.append(DateRewriter.DateCandidate("午前\(hourS)時\(minS)分", kTimeDescription))
  if min == 30 {
    results.append(DateRewriter.DateCandidate("午前\(hourS)時半", kTimeDescription))
  }

  results.append(DateRewriter.DateCandidate("午後\(hourS)時\(minS)分", kTimeDescription))
  if min == 30 {
    results.append(DateRewriter.DateCandidate("午後\(hourS)時半", kTimeDescription))
  }
}

/// Converts a prefix and year number to Japanese Kanji Representation
/// arguments :
///      - input "prefix" : a japanese style year counter prefix.
///      - input "year" : represent integer must be smaller than 100.
///      - output "result" : will be stored candidate strings
/// If the input year is invalid ( accept only [ 1 - 99 ] ) , this function
/// returns false and clear output vector.
@discardableResult
private func expandYear(_ prefix: String, _ year: Int, _ result: inout [String]) -> Bool {
  if year <= 0 || year >= 100 {
    result.removeAll()
    return false
  }

  if year == 1 {
    //  "元年"
    result.append(prefix + "元")
    return true
  }

  result.append(prefix + String(year))

  let arabic = String(year)

  var output: [NumberUtil.NumberString] = []

  _ = NumberUtil.arabicToKanji(arabic, &output)

  for o in output where o.style == .numberKanji {
    result.append(prefix + o.value)
  }

  return true
}

private func createCandidate(
  _ baseCandidate: Candidate, _ value: String, _ description: String
) -> Candidate {
  let candidate = Candidate()
  candidate.lid = baseCandidate.lid
  candidate.rid = baseCandidate.rid
  candidate.cost = baseCandidate.cost
  candidate.value = value
  candidate.key = baseCandidate.key
  candidate.contentKey = baseCandidate.contentKey
  candidate.attributes |= (Attribute.noLearning | Attribute.noVariantsExpansion)
  candidate.category = .other
  candidate.description = description
  return candidate
}

private func adToEraForCourt(_ data: [YearData], _ year: Int, _ results: inout [String]) -> Bool {
  let size = data.count
  var i = size - 1
  while i >= 0 {
    if i == size - 1 && year > data[i].ad {
      expandYear(data[i].era, year - data[i].ad + 1, &results)
      return true
    } else if i > 0 && data[i - 1].ad < year && year <= data[i].ad {
      // have two representations:
      // 1989 -> "昭和64" and "平成元"
      if year == data[i].ad {
        expandYear(data[i].era, 1, &results)
      }
      expandYear(data[i - 1].era, year - data[i - 1].ad + 1, &results)
      return true
    } else if i == 0 && data[i].ad <= year {
      // NOTE: Only `year == data[0].ad` reaches here (the other years are
      // handled by the branch above). The C++ `else` branch would read
      // `data[-1]`.
      if year == data[i].ad {
        expandYear(data[i].era, 1, &results)
      }
      return true
    }
    i -= 1
  }

  return false
}

private func getDescription(_ era: String, _ year: some StringProtocol, _ shouldAddSuffix: Bool)
  -> String
{
  shouldAddSuffix ? era + year + kNenValue : era + year
}

/// Extracts era year information from `key`.
private func extractYearFromKey(
  _ yearData: YearData, _ key: String, _ year: inout Int, _ hasSuffixOut: inout Bool,
  _ description: inout String
) -> Bool {
  let kGanKey = "がん"
  let kGanValue = "元"

  if !key.hasBytePrefix(yearData.key) {
    return false
  }

  // Append the `kNenValue` if the `key` has the `kNenKey` suffix.
  let hasSuffix = key.hasByteSuffix(kNenKey)
  hasSuffixOut = hasSuffix

  // key="しょうわ59ねん" -> era_year_str="59"
  // key="へいせいがんねん" -> era_year_str="がん"
  let yearStart = Util.charsLen(yearData.key)
  let yearLength = Util.charsLen(key) - yearStart - (hasSuffix ? Util.charsLen(kNenKey) : 0)
  // `Util::Utf8SubString` clips a negative length (size_t wrap) to the end.
  let eraYearStr =
    yearLength < 0
    ? Util.utf8SubString(key, yearStart) : Util.utf8SubString(key, yearStart, yearLength)

  if eraYearStr.bytesEqual(kGanKey) {
    year = 1
    description = getDescription(yearData.era, kGanValue, hasSuffix)
    return true
  }

  if !NumberUtil.isArabicNumber(eraYearStr) {
    return false
  }
  year = NumberUtil.simpleAtoi(eraYearStr)
  if year <= 0 {
    return false
  }
  description = getDescription(yearData.era, eraYearStr, hasSuffix)

  return true
}

private func eraToAdForCourt(
  _ data: [YearData], _ key: String, _ resultsAndDescriptions: inout [(String, String)]
) {
  for yearData in data {
    if !key.hasBytePrefix(yearData.key) {
      continue
    }

    // key="しょうわ59ねん" -> era_year=59, description="昭和59年"
    // key="へいせいがんねん" -> era_year=1, description="平成元年"
    var eraYear = 0
    var hasSuffix = false
    var description = ""
    if !extractYearFromKey(yearData, key, &eraYear, &hasSuffix, &description) {
      continue
    }
    let adYear = eraYear + yearData.ad - 1

    // Get wide arabic numbers
    // e.g.) 1989 -> "１９８９", "一九八九"
    var output: [NumberUtil.NumberString] = []
    let adYearStr = String(adYear)
    _ = NumberUtil.arabicToWideArabic(adYearStr, &output)
    // add half-width arabic number to `output` (e.g. "1989")
    output.append(NumberUtil.NumberString(adYearStr, "", .defaultStyle))

    for o in output {
      // "元徳", "建武" and "明徳" require dedupe
      var value = o.value
      if hasSuffix {
        value += kNenValue
      }
      if resultsAndDescriptions.contains(where: { $0.0.bytesEqual(value) }) {
        continue
      }
      resultsAndDescriptions.append((value, description))
    }
  }
}

/// Checks if the given date is valid or not.
/// Over 24 hour expression is allowed in this function.
/// Acceptable hour is between 0 and 29.
private func isValidTime(_ hour: Int, _ minute: Int) -> Bool {
  hour >= 0 && hour < 30 && minute >= 0 && minute < 60
}

/// Returns February last day.
/// This function deals with leap year with Gregorian calendar.
private func getFebruaryLastDay(_ year: Int) -> Int {
  var februaryEnd = (year % 4 == 0) ? 29 : 28
  if year % 100 == 0 && year % 400 != 0 {
    februaryEnd = 28
  }
  return februaryEnd
}

/// Checks given date is valid or not.
private func isValidDate(_ year: Int, _ month: Int, _ day: Int) -> Bool {
  if day < 1 {
    return false
  }

  if year <= 0 || year > 2100 {
    return false
  }

  switch month {
  case 2:
    return day <= getFebruaryLastDay(year)
  case 4, 6, 9, 11:
    return day <= 30
  case 1, 3, 5, 7, 8, 10, 12:
    return day <= 31
  default:
    return false
  }
}

/// Checks if a pair of month and day is valid.
private func isValidMonthAndDay(_ month: Int, _ day: Int) -> Bool {
  if day <= 0 {
    return false
  }
  switch month {
  case 2:
    return day <= 29
  case 4, 6, 9, 11:
    return day <= 30
  case 1, 3, 5, 7, 8, 10, 12:
    return day <= 31
  default:
    return false
  }
}

/// Minimal absl::CivilMinute.
private struct CivilMinute {
  var year: Int
  var month: Int
  var day: Int
  var hour: Int = 0
  var minute: Int = 0

  init(_ day: CivilDay) {
    year = day.year
    month = day.month
    self.day = day.day
  }

  /// absl::ToCivilMinute(time, tz).
  init(_ time: Date, _ timeZone: TimeZone) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: time)
    year = c.year!
    month = c.month!
    day = c.day!
    hour = c.hour!
    minute = c.minute!
  }

  var weekday: Weekday { CivilDay(year, month, day).weekday }
}

private func getCivilMinuteWithDiff(_ type: DateRewriter.DateType, _ diff: Int, _ tz: TimeZone)
  -> CivilMinute
{
  let at = Clock.getAbslTime()

  switch type {
  case .date:
    let cDay = CivilDay(at, tz) + Int64(diff)
    return CivilMinute(cDay)
  case .month:
    let today = CivilDay(at, tz)
    // absl::CivilMonth + diff, then the first day of the month.
    return CivilMinute(CivilDay(today.year, today.month + diff, 1))
  case .year:
    let today = CivilDay(at, tz)
    return CivilMinute(CivilDay(today.year + diff, 1, 1))
  case .weekday:
    let cDay = CivilDay(at, tz)
    let weekday = cDay.weekday.rawValue
    let weekdayDiff = (diff + 7 - weekday) % 7
    return CivilMinute(cDay + Int64(weekdayDiff))
  case .currentTime, .dateAndCurrentTime:
    return CivilMinute(at, tz)
  }
}

/// absl::FormatTime(format, absl::FromCivil(cm, tz), tz) for the conversion
/// specifiers produced by `convertExtraFormat`.
private func formatTime(_ format: String, _ cm: CivilMinute) -> String {
  var out = ""
  var it = format.unicodeScalars.makeIterator()
  while let c = it.next() {
    if c != "%" {
      out.unicodeScalars.append(c)
      continue
    }
    guard let spec = it.next() else {
      out += "%"
      break
    }
    switch spec {
    case "%": out += "%"
    case "Y": out += String(cm.year)
    case "m": out += pad2(cm.month)
    case "d": out += pad2(cm.day)
    case "H": out += pad2(cm.hour)
    case "M": out += pad2(cm.minute)
    default:
      out += "%"
      out.unicodeScalars.append(spec)
    }
  }
  return out
}

private func getConversions(
  _ data: DateRewriter.DateData, _ extraDateFormats: [String], _ extraDatetimeFormats: [String]
) -> [String] {
  var results: [String] = []
  let tz = Clock.getTimeZone()
  let cm = getCivilMinuteWithDiff(data.type, data.diff, tz)

  if data.type == .date {
    for dateFormat in extraDateFormats {
      results.append(formatTime(dateFormat, cm))
    }
  }
  if data.type == .dateAndCurrentTime {
    for datetimeFormat in extraDatetimeFormats {
      results.append(formatTime(datetimeFormat, cm))
    }
  }

  switch data.type {
  case .date, .weekday:
    DateRewriter.convertDateWithYear(cm.year, cm.month, cm.day, &results)
    var era: [String] = []
    if DateRewriter.adToEra(cm.year, cm.month, &era) && !era.isEmpty {
      results.append("\(era[0])年\(cm.month)月\(cm.day)日")
    }
    results.append("\(DateUtil.getShortWeekdayString(cm.weekday))曜日")

  case .month:
    results.append("\(cm.month)")
    results.append("\(cm.month)月")

  case .year:
    results.append("\(cm.year)")
    results.append("\(cm.year)年")

    var era: [String] = []
    if DateRewriter.adToEra(cm.year, 0, /* unknown month */ &era) && !era.isEmpty {
      for e in era.reversed() {
        results.append("\(e)年")
      }
    }

  case .currentTime:
    DateRewriter.convertTime(cm.hour, cm.minute, &results)

  case .dateAndCurrentTime:
    // Y/MM/DD H:MM
    let hour = cm.hour < 10 ? " \(cm.hour)" : "\(cm.hour)"  // %2d
    results.append("\(cm.year)/\(pad2(cm.month))/\(pad2(cm.day)) \(hour):\(pad2(cm.minute))")
  }

  return results
}

/// Rewrite AD for resized / single-segment inputs (legacy behavior).
private func rewriteAdResized(_ segmentsRange: [Segment], _ numDoneOut: inout Int) -> Bool {
  // Rewrite:
  // * If the first segment ends with the `kNenKey`, or
  // * If the second segment starts with the `kNenKey`.
  let segment = segmentsRange[0]
  let key = segment.key
  let hasSuffix = key.hasByteSuffix(kNenKey)
  if !hasSuffix {
    if segmentsRange.count < 2 || !segmentsRange[1].key.hasBytePrefix(kNenKey) {
      return false
    }
  }
  if segment.candidatesSize == 0 {
    // No candidates are found
    return false
  }

  // Try to convert era to AD.
  let resultsAndDescriptions = DateRewriter.eraToAd(key)
  if resultsAndDescriptions.isEmpty {
    return false
  }

  let baseCand = segment.candidate(0)
  var candidates: [Candidate] = []
  candidates.reserveCapacity(resultsAndDescriptions.count)
  for (adValue, description) in resultsAndDescriptions {
    candidates.append(createCandidate(baseCand, adValue, description))
  }

  // Insert position is the last of candidates
  let position = segment.candidatesSize
  segment.insertCandidates(position, candidates)
  numDoneOut = hasSuffix ? 1 : 2
  return true
}

/// Converts Japanese era representations to Christian Era (AD) and vice versa
/// (e.g., "へいせい23ねん" -> "2011年", "2011ねん" -> "平成23年").
/// Supports multi-segment candidate generation up to 6 segments.
private struct EraKeyInfo {
  /// Merged key for era conversion up to "ねん" (e.g. "へいせい23ねん").
  var mergedKey = ""

  /// Number of segments scanned (e.g. 3 for ["へいせい"] ["23"] ["ねん"]).
  var segmentCount = 0

  /// Byte offset of "ねん" in the last segment (e.g. 0 for ["2011"] ["ねん"],
  /// 1 for "8ねんの"). nil is `npos`.
  var nenPosInLastSeg: Int? = nil
}

private func extractEraKey(_ segmentsRange: [Segment]) -> EraKeyInfo? {
  let kMaxSegments = 6
  var info = EraKeyInfo()

  for seg in segmentsRange {
    let key = seg.key
    info.segmentCount += 1
    if let pos = byteFind(key, kNenKey) {
      // Extract up to the end of `kNenKey` (e.g. "ねんです" -> "ねん").
      info.mergedKey += key.byteSubstring(from: 0, length: pos + kNenKey.byteCount)
      info.nenPosInLastSeg = pos
      return info
    }
    info.mergedKey += key
    if info.segmentCount >= kMaxSegments {
      break
    }
  }

  return nil
}

/// Extracts trailing functional key/value
/// e.g. {"の", "の"} from "れいわ8ねんの" from `last_segment` after stripping
/// "ねん" from key and "年" from value.
private func extractFunctionalSuffix(_ lastSegment: Segment, _ info: EraKeyInfo) -> (
  Substring, Substring
) {
  if lastSegment.candidatesSize == 0 {
    return ("", "")
  }
  let lastCand = lastSegment.candidate(0)

  guard let nenPos = info.nenPosInLastSeg,
    lastSegment.key.byteCount > nenPos + kNenKey.byteCount
  else {
    // No trailing suffix after "ねん" (e.g. ["2011"] ["ねん"]).
    return ("", "")
  }

  // Suffix exists in the same segment after "ねん"
  // (e.g. "れいわ8ねんの" -> "の").
  let suffixKey = lastSegment.key.byteSubstring(from: nenPos + kNenKey.byteCount)

  // Extract the suffix after "年" from the candidate value (e.g. "年の" ->
  // "の").
  if let posVal = byteFind(lastCand.value, kNenValue),
    lastCand.value.byteCount > posVal + kNenValue.byteCount
  {
    let suffixValue = lastCand.value.byteSubstring(from: posVal + kNenValue.byteCount)
    return (suffixKey, suffixValue)
  }

  // Fallback: use suffix_key as suffix_value if "年" was not found in value
  // (e.g. in mock candidates or all-hiragana/katakana values).
  return (suffixKey, suffixKey)
}

private func rewriteAdMultiSegmentCandidate(_ segmentsRange: [Segment], _ numDoneOut: inout Int)
  -> Bool
{
  let segment = segmentsRange[0]
  if segment.candidatesSize == 0 {
    // No candidates are found
    return false
  }

  guard let eraInfo = extractEraKey(segmentsRange) else {
    return false
  }

  // `results` contains pairs of <AD year value, era description>
  // (e.g. <"2026年", "令和8年">, <"２０２６年", "令和8年">).
  let results = DateRewriter.eraToAd(eraInfo.mergedKey)
  if results.isEmpty {
    return false
  }

  // Extract trailing functional key/value (e.g. {"の", "の"} from ["れいわ"]
  // ["8ねんの"]) from the last scanned segment containing "ねん".
  // `functional_key` and `functional_value` are appended to the date candidate
  // (e.g. key: "れいわ8ねん" + "の", value: "2026年" + "の") to preserve
  // trailing particles/auxiliary words in the generated multi-segment
  // candidate.
  let lastSegment = segmentsRange[eraInfo.segmentCount - 1]
  let (functionalKey, functionalValue) = extractFunctionalSuffix(lastSegment, eraInfo)

  let baseCand = segment.candidate(0)
  var candidates: [Candidate] = []
  candidates.reserveCapacity(results.count)
  for (adValue, description) in results {
    let cand = createCandidate(baseCand, adValue + functionalValue, description)
    cand.contentValue = adValue
    cand.key = eraInfo.mergedKey + functionalKey
    cand.contentKey = eraInfo.mergedKey
    cand.convertedSegmentCount = UInt32(eraInfo.segmentCount)
    candidates.append(cand)
  }

  // For multi-segment conversion (count > 1), boost the candidate to the top
  // (index 2) so that it is easily discoverable. For single-segment
  // conversion, append to the end of candidates.
  let position =
    eraInfo.segmentCount > 1 ? min(2, segment.candidatesSize) : segment.candidatesSize
  segment.insertCandidates(position, candidates)
  numDoneOut = 1
  return true
}

private func validateNDigits(_ value: some StringProtocol, _ n: Int) -> String? {
  var u32value = Array(value.unicodeScalars).map(\.value)
  if u32value.count != n {
    return nil
  }

  for i in 0..<n {
    let c = u32value[i]
    if 0x30 <= c && c <= 0x39 {  // Half-width digits
      continue
    }
    if 0xFF10 <= c && c <= 0xFF19 {  // Full-width digits
      // Sets `u32value[i]` to the half-width digts of `c`.
      u32value[i] = c - 0xFF10 + 0x30
      continue
    }
    return nil
  }
  return String(String.UnicodeScalarView(u32value.map { UnicodeScalar($0)! }))
}

/// Gets n digits if possible.
/// Following trials will be performed in this order.
/// 1. Checks segment's key.
/// 2. Checks all the meta candidates.
/// 3. Checks raw input.
///      This is mainly for mobile.
///      On 12keys-toggle-alphabet mode, a user types "2223" to get "cd".
///      In this case,
///      - Segment's key is "cd".
///      - All the meta candidates are based on "cd" (e.g. "CD", "Cd").
///      Therefore to get "2223" we should access the raw input.
/// Prerequisite: |segments| has only one conversion segment.
private func getNDigits(_ composer: ComposerData, _ segments: Segments, _ n: Int) -> String? {
  let segment = segments.conversionSegment(0)

  // 1. Segment's key
  if let validated = validateNDigits(segment.key, n) {
    return validated
  }

  // 2. Meta candidates
  for i in 0..<segment.metaCandidatesSize {
    if let validated = validateNDigits(segment.metaCandidate(i).value, n) {
      return validated
    }
  }

  // 3. Raw input
  // Note that only one segment is in the Segments, but sometimes like
  // on partial conversion, segment.key() is different from the size of
  // the whole composition.
  let raw = composer.getRawSubString(0, segment.keyLen)
  if let validated = validateNDigits(raw, n) {
    return validated
  }

  // No trials succeeded.
  return nil
}

private func convertExtraFormat(_ base: String) -> String {
  // std::strftime format used by absl::FormatTime.
  // https://en.cppreference.com/w/cpp/chrono/c/strftime.html
  // absl::StrReplaceAll: leftmost match first, no rescanning of replaced text.
  let replacements: [(String, String)] = [
    ("%", "%%"),
    ("{YEAR}", "%Y"),  // 4 digits
    ("{MONTH}", "%m"),  // (01 to 12)
    ("{DATE}", "%d"),  // (01 to 31)
    ("{HOUR}", "%H"),  // (01 to 23)
    ("{MINUTE}", "%M"),  // (00 to 59)
    ("{{}", "{"),
  ]
  let bytes = Array(base.utf8)
  var out: [UInt8] = []
  var i = 0
  outer: while i < bytes.count {
    for (old, new) in replacements {
      let o = Array(old.utf8)
      if i + o.count <= bytes.count && bytes[i..<(i + o.count)].elementsEqual(o) {
        out.append(contentsOf: new.utf8)
        i += o.count
        continue outer
      }
    }
    out.append(bytes[i])
    i += 1
  }
  return String(decoding: out, as: UTF8.self)
}

private func getExtraFormats(_ dictionary: (any DictionaryInterface)?, _ formatKey: String)
  -> [String]
{
  guard let dictionary else {
    return []
  }

  // Lookup the extra format key from the user dictionary and store the results
  // into `extra_formats`.
  var extraFormats: [String] = []
  let cb = InlineCallback()
  cb.onToken { _, _, token in
    if token.attributes != Token.Attribute.userDictionary {
      return .traverseContinue
    }
    extraFormats.append(convertExtraFormat(token.value))
    return .traverseDone
  }

  dictionary.lookupExact(formatKey, options: ConversionOptions(), callback: cb)
  return extraFormats
}

// MARK: - Data tables

private let kDateData: [DateRewriter.DateData] = [
  // Date rewrites.
  DateRewriter.DateData(key: "きょう", value: "今日", description: "今日の日付", diff: 0, type: .date),
  DateRewriter.DateData(key: "あした", value: "明日", description: "明日の日付", diff: 1, type: .date),
  DateRewriter.DateData(key: "あす", value: "明日", description: "明日の日付", diff: 1, type: .date),
  DateRewriter.DateData(key: "さくじつ", value: "昨日", description: "昨日の日付", diff: -1, type: .date),
  DateRewriter.DateData(key: "きのう", value: "昨日", description: "昨日の日付", diff: -1, type: .date),
  DateRewriter.DateData(key: "おととい", value: "一昨日", description: "2日前の日付", diff: -2, type: .date),
  DateRewriter.DateData(key: "おとつい", value: "一昨日", description: "2日前の日付", diff: -2, type: .date),
  DateRewriter.DateData(key: "いっさくじつ", value: "一昨日", description: "2日前の日付", diff: -2, type: .date),
  DateRewriter.DateData(key: "さきおととい", value: "一昨昨日", description: "3日前の日付", diff: -3, type: .date),
  DateRewriter.DateData(key: "あさって", value: "明後日", description: "明後日の日付", diff: 2, type: .date),
  DateRewriter.DateData(key: "みょうごにち", value: "明後日", description: "明後日の日付", diff: 2, type: .date),
  DateRewriter.DateData(key: "しあさって", value: "明明後日", description: "明明後日の日付", diff: 3, type: .date),
  // Weekday rewrites
  // Absl::Weekday starts from Monday, while std::tm.tm_wday starts from
  // Sunday.
  DateRewriter.DateData(key: "げつようび", value: "月曜日", description: "次の月曜日", diff: 0, type: .weekday),
  DateRewriter.DateData(key: "かようび", value: "火曜日", description: "次の火曜日", diff: 1, type: .weekday),
  DateRewriter.DateData(key: "すいようび", value: "水曜日", description: "次の水曜日", diff: 2, type: .weekday),
  DateRewriter.DateData(key: "もくようび", value: "木曜日", description: "次の木曜日", diff: 3, type: .weekday),
  DateRewriter.DateData(key: "きんようび", value: "金曜日", description: "次の金曜日", diff: 4, type: .weekday),
  DateRewriter.DateData(key: "どようび", value: "土曜日", description: "次の土曜日", diff: 5, type: .weekday),
  DateRewriter.DateData(key: "にちようび", value: "日曜日", description: "次の日曜日", diff: 6, type: .weekday),
  DateRewriter.DateData(key: "げつよう", value: "月曜", description: "次の月曜日", diff: 0, type: .weekday),
  DateRewriter.DateData(key: "かよう", value: "火曜", description: "次の火曜日", diff: 1, type: .weekday),
  DateRewriter.DateData(key: "すいよう", value: "水曜", description: "次の水曜日", diff: 2, type: .weekday),
  DateRewriter.DateData(key: "もくよう", value: "木曜", description: "次の木曜日", diff: 3, type: .weekday),
  DateRewriter.DateData(key: "きんよう", value: "金曜", description: "次の金曜日", diff: 4, type: .weekday),
  DateRewriter.DateData(key: "どよう", value: "土曜", description: "次の土曜日", diff: 5, type: .weekday),
  DateRewriter.DateData(key: "にちよう", value: "日曜", description: "次の日曜日", diff: 6, type: .weekday),
  // Year rewrites
  DateRewriter.DateData(key: "ことし", value: "今年", description: "今年", diff: 0, type: .year),
  DateRewriter.DateData(key: "らいねん", value: "来年", description: "来年", diff: 1, type: .year),
  DateRewriter.DateData(key: "さくねん", value: "昨年", description: "昨年", diff: -1, type: .year),
  DateRewriter.DateData(key: "きょねん", value: "去年", description: "去年", diff: -1, type: .year),
  DateRewriter.DateData(key: "おととし", value: "一昨年", description: "一昨年", diff: -2, type: .year),
  DateRewriter.DateData(key: "さらいねん", value: "再来年", description: "再来年", diff: 2, type: .year),
  // Month rewrites
  DateRewriter.DateData(key: "こんげつ", value: "今月", description: "今月", diff: 0, type: .month),
  DateRewriter.DateData(key: "らいげつ", value: "来月", description: "来月", diff: 1, type: .month),
  DateRewriter.DateData(key: "せんげつ", value: "先月", description: "先月", diff: -1, type: .month),
  DateRewriter.DateData(key: "せんせんげつ", value: "先々月", description: "先々月", diff: -2, type: .month),
  DateRewriter.DateData(key: "さらいげつ", value: "再来月", description: "再来月", diff: 2, type: .month),
  // Time rewrites.
  DateRewriter.DateData(key: "いま", value: "今", description: "現在の時刻", diff: 0, type: .currentTime),
  DateRewriter.DateData(key: "じこく", value: "時刻", description: "現在の時刻", diff: 0, type: .currentTime),
  // Date and time rewrites.
  DateRewriter.DateData(key: "にちじ", value: "日時", description: "現在の日時", diff: 0, type: .dateAndCurrentTime),
  DateRewriter.DateData(key: "なう", value: "ナウ", description: "現在の日時", diff: 0, type: .dateAndCurrentTime),
]

private let kEraData: [YearData] = [
  // "元徳", "建武" and "明徳" are used for both south and north courts.
  YearData(ad: 645, era: "大化", key: "たいか"),
  YearData(ad: 650, era: "白雉", key: "はくち"),
  YearData(ad: 686, era: "朱鳥", key: "しゅちょう"),
  YearData(ad: 701, era: "大宝", key: "たいほう"),
  YearData(ad: 704, era: "慶雲", key: "けいうん"),
  YearData(ad: 708, era: "和銅", key: "わどう"),
  YearData(ad: 715, era: "霊亀", key: "れいき"),
  YearData(ad: 717, era: "養老", key: "ようろう"),
  YearData(ad: 724, era: "神亀", key: "じんき"),
  YearData(ad: 729, era: "天平", key: "てんぴょう"),
  YearData(ad: 749, era: "天平感宝", key: "てんぴょうかんぽう"),
  YearData(ad: 749, era: "天平勝宝", key: "てんぴょうしょうほう"),
  YearData(ad: 757, era: "天平宝字", key: "てんぴょうほうじ"),
  YearData(ad: 765, era: "天平神護", key: "てんぴょうじんご"),
  YearData(ad: 767, era: "神護景雲", key: "じんごけいうん"),
  YearData(ad: 770, era: "宝亀", key: "ほうき"),
  YearData(ad: 781, era: "天応", key: "てんおう"),
  YearData(ad: 782, era: "延暦", key: "えんりゃく"),
  YearData(ad: 806, era: "大同", key: "たいどう"),
  YearData(ad: 810, era: "弘仁", key: "こうにん"),
  YearData(ad: 824, era: "天長", key: "てんちょう"),
  YearData(ad: 834, era: "承和", key: "じょうわ"),
  YearData(ad: 848, era: "嘉祥", key: "かしょう"),
  YearData(ad: 851, era: "仁寿", key: "にんじゅ"),
  YearData(ad: 854, era: "斉衡", key: "さいこう"),
  YearData(ad: 857, era: "天安", key: "てんなん"),
  YearData(ad: 859, era: "貞観", key: "じょうかん"),
  YearData(ad: 877, era: "元慶", key: "がんぎょう"),
  YearData(ad: 885, era: "仁和", key: "にんな"),
  YearData(ad: 889, era: "寛平", key: "かんぴょう"),
  YearData(ad: 898, era: "昌泰", key: "しょうたい"),
  YearData(ad: 901, era: "延喜", key: "えんぎ"),
  YearData(ad: 923, era: "延長", key: "えんちょう"),
  YearData(ad: 931, era: "承平", key: "じょうへい"),
  YearData(ad: 938, era: "天慶", key: "てんぎょう"),
  YearData(ad: 947, era: "天暦", key: "てんりゃく"),
  YearData(ad: 957, era: "天徳", key: "てんとく"),
  YearData(ad: 961, era: "応和", key: "おうわ"),
  YearData(ad: 964, era: "康保", key: "こうほう"),
  YearData(ad: 968, era: "安和", key: "あんな"),
  YearData(ad: 970, era: "天禄", key: "てんろく"),
  YearData(ad: 973, era: "天延", key: "てんえん"),
  YearData(ad: 976, era: "貞元", key: "じょうげん"),
  YearData(ad: 978, era: "天元", key: "てんげん"),
  YearData(ad: 983, era: "永観", key: "えいかん"),
  YearData(ad: 985, era: "寛和", key: "かんな"),
  YearData(ad: 987, era: "永延", key: "えいえん"),
  YearData(ad: 989, era: "永祚", key: "えいそ"),
  YearData(ad: 990, era: "正暦", key: "しょうりゃく"),
  YearData(ad: 995, era: "長徳", key: "ちょうとく"),
  YearData(ad: 999, era: "長保", key: "ちょうほう"),
  YearData(ad: 1004, era: "寛弘", key: "かんこう"),
  YearData(ad: 1012, era: "長和", key: "ちょうわ"),
  YearData(ad: 1017, era: "寛仁", key: "かんにん"),
  YearData(ad: 1021, era: "治安", key: "じあん"),
  YearData(ad: 1024, era: "万寿", key: "まんじゅ"),
  YearData(ad: 1028, era: "長元", key: "ちょうげん"),
  YearData(ad: 1037, era: "長暦", key: "ちょうりゃく"),
  YearData(ad: 1040, era: "長久", key: "ちょうきゅう"),
  YearData(ad: 1044, era: "寛徳", key: "かんとく"),
  YearData(ad: 1046, era: "永承", key: "えいしょう"),
  YearData(ad: 1053, era: "天喜", key: "てんき"),
  YearData(ad: 1058, era: "康平", key: "こうへい"),
  YearData(ad: 1065, era: "治暦", key: "じりゃく"),
  YearData(ad: 1069, era: "延久", key: "えんきゅう"),
  YearData(ad: 1074, era: "承保", key: "じょうほう"),
  YearData(ad: 1077, era: "承暦", key: "じょうりゃく"),
  YearData(ad: 1081, era: "永保", key: "えいほ"),
  YearData(ad: 1084, era: "応徳", key: "おうとく"),
  YearData(ad: 1087, era: "寛治", key: "かんじ"),
  YearData(ad: 1094, era: "嘉保", key: "かほう"),
  YearData(ad: 1096, era: "永長", key: "えいちょう"),
  YearData(ad: 1097, era: "承徳", key: "じょうとく"),
  YearData(ad: 1099, era: "康和", key: "こうわ"),
  YearData(ad: 1104, era: "長治", key: "ちょうじ"),
  YearData(ad: 1106, era: "嘉承", key: "かしょう"),
  YearData(ad: 1108, era: "天仁", key: "てんにん"),
  YearData(ad: 1110, era: "天永", key: "てんえい"),
  YearData(ad: 1113, era: "永久", key: "えいきゅう"),
  YearData(ad: 1118, era: "元永", key: "げんえい"),
  YearData(ad: 1120, era: "保安", key: "ほうあん"),
  YearData(ad: 1124, era: "天治", key: "てんじ"),
  YearData(ad: 1126, era: "大治", key: "だいじ"),
  YearData(ad: 1131, era: "天承", key: "てんじょう"),
  YearData(ad: 1132, era: "長承", key: "ちょうじょう"),
  YearData(ad: 1135, era: "保延", key: "ほうえん"),
  YearData(ad: 1141, era: "永治", key: "えいじ"),
  YearData(ad: 1142, era: "康治", key: "こうじ"),
  YearData(ad: 1144, era: "天養", key: "てんよう"),
  YearData(ad: 1145, era: "久安", key: "きゅうあん"),
  YearData(ad: 1151, era: "仁平", key: "にんぺい"),
  YearData(ad: 1154, era: "久寿", key: "きゅうじゅ"),
  YearData(ad: 1156, era: "保元", key: "ほうげん"),
  YearData(ad: 1159, era: "平治", key: "へいじ"),
  YearData(ad: 1160, era: "永暦", key: "えいりゃく"),
  YearData(ad: 1161, era: "応保", key: "おうほ"),
  YearData(ad: 1163, era: "長寛", key: "ちょうかん"),
  YearData(ad: 1165, era: "永万", key: "えいまん"),
  YearData(ad: 1166, era: "仁安", key: "にんあん"),
  YearData(ad: 1169, era: "嘉応", key: "かおう"),
  YearData(ad: 1171, era: "承安", key: "しょうあん"),
  YearData(ad: 1175, era: "安元", key: "あんげん"),
  YearData(ad: 1177, era: "治承", key: "じしょう"),
  YearData(ad: 1181, era: "養和", key: "ようわ"),
  YearData(ad: 1182, era: "寿永", key: "じゅえい"),
  YearData(ad: 1184, era: "元暦", key: "げんりゃく"),
  YearData(ad: 1185, era: "文治", key: "ぶんじ"),
  YearData(ad: 1190, era: "建久", key: "けんきゅう"),
  YearData(ad: 1199, era: "正治", key: "しょうじ"),
  YearData(ad: 1201, era: "建仁", key: "けんにん"),
  YearData(ad: 1204, era: "元久", key: "げんきゅう"),
  YearData(ad: 1206, era: "建永", key: "けんえい"),
  YearData(ad: 1207, era: "承元", key: "じょうげん"),
  YearData(ad: 1211, era: "建暦", key: "けんりゃく"),
  YearData(ad: 1213, era: "建保", key: "けんぽう"),
  YearData(ad: 1219, era: "承久", key: "しょうきゅう"),
  YearData(ad: 1222, era: "貞応", key: "じょうおう"),
  YearData(ad: 1224, era: "元仁", key: "げんにん"),
  YearData(ad: 1225, era: "嘉禄", key: "かろく"),
  YearData(ad: 1227, era: "安貞", key: "あんてい"),
  YearData(ad: 1229, era: "寛喜", key: "かんき"),
  YearData(ad: 1232, era: "貞永", key: "じょうえい"),
  YearData(ad: 1233, era: "天福", key: "てんぷく"),
  YearData(ad: 1234, era: "文暦", key: "ぶんりゃく"),
  YearData(ad: 1235, era: "嘉禎", key: "かてい"),
  YearData(ad: 1238, era: "暦仁", key: "りゃくにん"),
  YearData(ad: 1239, era: "延応", key: "えんおう"),
  YearData(ad: 1240, era: "仁治", key: "にんじゅ"),
  YearData(ad: 1243, era: "寛元", key: "かんげん"),
  YearData(ad: 1247, era: "宝治", key: "ほうじ"),
  YearData(ad: 1249, era: "建長", key: "けんちょう"),
  YearData(ad: 1256, era: "康元", key: "こうげん"),
  YearData(ad: 1257, era: "正嘉", key: "しょうか"),
  YearData(ad: 1259, era: "正元", key: "しょうげん"),
  YearData(ad: 1260, era: "文応", key: "ぶんおう"),
  YearData(ad: 1261, era: "弘長", key: "こうちょう"),
  YearData(ad: 1264, era: "文永", key: "ぶんえい"),
  YearData(ad: 1275, era: "建治", key: "けんじ"),
  YearData(ad: 1278, era: "弘安", key: "こうあん"),
  YearData(ad: 1288, era: "正応", key: "しょうおう"),
  YearData(ad: 1293, era: "永仁", key: "えいにん"),
  YearData(ad: 1299, era: "正安", key: "しょうあん"),
  YearData(ad: 1302, era: "乾元", key: "けんげん"),
  YearData(ad: 1303, era: "嘉元", key: "かげん"),
  YearData(ad: 1306, era: "徳治", key: "とくじ"),
  YearData(ad: 1308, era: "延慶", key: "えんぎょう"),
  YearData(ad: 1311, era: "応長", key: "おうちょう"),
  YearData(ad: 1312, era: "正和", key: "しょうわ"),
  YearData(ad: 1317, era: "文保", key: "ぶんぽう"),
  YearData(ad: 1319, era: "元応", key: "げんおう"),
  YearData(ad: 1321, era: "元亨", key: "げんこう"),
  YearData(ad: 1324, era: "正中", key: "しょうちゅう"),
  YearData(ad: 1326, era: "嘉暦", key: "かりゃく"),
  YearData(ad: 1329, era: "元徳", key: "げんとく"),
  YearData(ad: 1331, era: "元弘", key: "げんこう"),
  YearData(ad: 1334, era: "建武", key: "けんむ"),
  YearData(ad: 1336, era: "延元", key: "えんげん"),
  YearData(ad: 1340, era: "興国", key: "こうこく"),
  YearData(ad: 1346, era: "正平", key: "しょうへい"),
  YearData(ad: 1370, era: "建徳", key: "けんとく"),
  YearData(ad: 1372, era: "文中", key: "ぶんちゅう"),
  YearData(ad: 1375, era: "天授", key: "てんじゅ"),
  YearData(ad: 1381, era: "弘和", key: "こうわ"),
  YearData(ad: 1384, era: "元中", key: "げんちゅう"),
  YearData(ad: 1390, era: "明徳", key: "めいとく"),
  YearData(ad: 1394, era: "応永", key: "おうえい"),
  YearData(ad: 1428, era: "正長", key: "しょうちょう"),
  YearData(ad: 1429, era: "永享", key: "えいきょう"),
  YearData(ad: 1441, era: "嘉吉", key: "かきつ"),
  YearData(ad: 1444, era: "文安", key: "ぶんあん"),
  YearData(ad: 1449, era: "宝徳", key: "ほうとく"),
  YearData(ad: 1452, era: "享徳", key: "きょうとく"),
  YearData(ad: 1455, era: "康正", key: "こうしょう"),
  YearData(ad: 1457, era: "長禄", key: "ちょうろく"),
  YearData(ad: 1460, era: "寛正", key: "かんしょう"),
  YearData(ad: 1466, era: "文正", key: "ぶんしょう"),
  YearData(ad: 1467, era: "応仁", key: "おうにん"),
  YearData(ad: 1469, era: "文明", key: "ぶんめい"),
  YearData(ad: 1487, era: "長享", key: "ちょうきょう"),
  YearData(ad: 1489, era: "延徳", key: "えんとく"),
  YearData(ad: 1492, era: "明応", key: "めいおう"),
  YearData(ad: 1501, era: "文亀", key: "ぶんき"),
  YearData(ad: 1504, era: "永正", key: "えいしょう"),
  YearData(ad: 1521, era: "大永", key: "だいえい"),
  YearData(ad: 1528, era: "享禄", key: "きょうろく"),
  YearData(ad: 1532, era: "天文", key: "てんぶん"),
  YearData(ad: 1555, era: "弘治", key: "こうじ"),
  YearData(ad: 1558, era: "永禄", key: "えいろく"),
  YearData(ad: 1570, era: "元亀", key: "げんき"),
  YearData(ad: 1573, era: "天正", key: "てんしょう"),
  YearData(ad: 1592, era: "文禄", key: "ぶんろく"),
  YearData(ad: 1596, era: "慶長", key: "けいちょう"),
  YearData(ad: 1615, era: "元和", key: "げんな"),
  YearData(ad: 1624, era: "寛永", key: "かんえい"),
  YearData(ad: 1644, era: "正保", key: "しょうほう"),
  YearData(ad: 1648, era: "慶安", key: "けいあん"),
  YearData(ad: 1652, era: "承応", key: "じょうおう"),
  YearData(ad: 1655, era: "明暦", key: "めいれき"),
  YearData(ad: 1658, era: "万治", key: "まんじ"),
  YearData(ad: 1661, era: "寛文", key: "かんぶん"),
  YearData(ad: 1673, era: "延宝", key: "えんぽう"),
  YearData(ad: 1681, era: "天和", key: "てんな"),
  YearData(ad: 1684, era: "貞享", key: "じょうきょう"),
  YearData(ad: 1688, era: "元禄", key: "げんろく"),
  YearData(ad: 1704, era: "宝永", key: "ほうえい"),
  YearData(ad: 1711, era: "正徳", key: "しょうとく"),
  YearData(ad: 1716, era: "享保", key: "きょうほ"),
  YearData(ad: 1736, era: "元文", key: "げんぶん"),
  YearData(ad: 1741, era: "寛保", key: "かんぽ"),
  YearData(ad: 1744, era: "延享", key: "えんきょう"),
  YearData(ad: 1748, era: "寛延", key: "かんえん"),
  YearData(ad: 1751, era: "宝暦", key: "ほうれき"),
  YearData(ad: 1764, era: "明和", key: "めいわ"),
  YearData(ad: 1772, era: "安永", key: "あんえい"),
  YearData(ad: 1781, era: "天明", key: "てんめい"),
  YearData(ad: 1789, era: "寛政", key: "かんせい"),
  YearData(ad: 1801, era: "享和", key: "きょうわ"),
  YearData(ad: 1804, era: "文化", key: "ぶんか"),
  YearData(ad: 1818, era: "文政", key: "ぶんせい"),
  YearData(ad: 1830, era: "天保", key: "てんぽう"),
  YearData(ad: 1844, era: "弘化", key: "こうか"),
  YearData(ad: 1848, era: "嘉永", key: "かえい"),
  YearData(ad: 1854, era: "安政", key: "あんせい"),
  YearData(ad: 1860, era: "万延", key: "まんえん"),
  YearData(ad: 1861, era: "文久", key: "ぶんきゅう"),
  YearData(ad: 1864, era: "元治", key: "げんじ"),
  YearData(ad: 1865, era: "慶応", key: "けいおう"),
  YearData(ad: 1868, era: "明治", key: "めいじ"),
  YearData(ad: 1912, era: "大正", key: "たいしょう"),
  YearData(ad: 1926, era: "昭和", key: "しょうわ"),
  YearData(ad: 1989, era: "平成", key: "へいせい"),
  YearData(ad: 2019, era: "令和", key: "れいわ"),
]

private let kNorthEraData: [YearData] = [
  // "元徳", "建武" and "明徳" are used for both south and north courts.
  YearData(ad: 1329, era: "元徳", key: "げんとく"),
  YearData(ad: 1332, era: "正慶", key: "しょうけい"),
  YearData(ad: 1334, era: "建武", key: "けんむ"),
  YearData(ad: 1338, era: "暦応", key: "りゃくおう"),
  YearData(ad: 1342, era: "康永", key: "こうえい"),
  YearData(ad: 1345, era: "貞和", key: "じょうわ"),
  YearData(ad: 1350, era: "観応", key: "かんおう"),
  YearData(ad: 1352, era: "文和", key: "ぶんわ"),
  YearData(ad: 1356, era: "延文", key: "えんぶん"),
  YearData(ad: 1361, era: "康安", key: "こうあん"),
  YearData(ad: 1362, era: "貞治", key: "じょうじ"),
  YearData(ad: 1368, era: "応安", key: "おうあん"),
  YearData(ad: 1375, era: "永和", key: "えいわ"),
  YearData(ad: 1379, era: "康暦", key: "こうりゃく"),
  YearData(ad: 1381, era: "永徳", key: "えいとく"),
  YearData(ad: 1384, era: "至徳", key: "しとく"),
  YearData(ad: 1387, era: "嘉慶", key: "かけい"),
  YearData(ad: 1389, era: "康応", key: "こうおう"),
  YearData(ad: 1390, era: "明徳", key: "めいとく"),
]
