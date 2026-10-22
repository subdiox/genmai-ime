// Port of mozc/src/base/number_util.{h,cc} (3.35.6354).

/// This class sets up utilities to manage strings including numbers like
/// Arabic numbers, Roman numbers, Kanji numbers, and so on.
public enum NumberUtil {
  public struct NumberString: Sendable, Equatable {
    public enum Style: Int, Sendable {
      case defaultStyle = 0
      // 123,456,789
      case numberSeparatedArabicHalfwidth
      // "１２３，４５６，７８９"
      case numberSeparatedArabicFullwidth
      // "123億456万7890"
      case numberArabicAndKanjiHalfwidth
      // "１２３億４５６万７８９０"
      case numberArabicAndKanjiFullwidth
      // "一億二千三百四十五万六千七百八十九"
      case numberKanji
      // "壱億弐千参百四拾五万六千七百八拾九"
      case numberOldKanji
      // "ⅠⅡⅢ"
      case numberRomanCapital
      // "ⅰⅱⅲ"
      case numberRomanSmall
      // "①②③"
      case numberCircled
      // "ニ〇〇"
      case numberKanjiArabic
      // "0x4d2" (1234 in decimal)
      case numberHex
      // "02322" (1234 in decimal)
      case numberOct
      // "0b10011010010" (1234 in decimal)
      case numberBin
      // "¹²³⁴⁵⁶⁷⁸⁹"
      case numberSuperscript
      // "₁₂₃₄₅₆₇₈₉"
      case numberSubscript
    }

    /// Converted string
    public var value: String
    /// Description of Converted String
    public var description: String
    /// Converted Number Style
    public var style: Style

    public init(_ value: String, _ description: String, _ style: Style) {
      self.value = value
      self.description = description
      self.style = style
    }
  }

  // Table of number character of Kansuji
  static let kNumKanjiDigits = ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九", ""]
  static let kNumKanjiOldDigits = ["", "壱", "弐", "参", "四", "五", "六", "七", "八", "九"]
  static let kNumFullWidthDigits = ["０", "１", "２", "３", "４", "５", "６", "７", "８", "９", ""]
  static let kNumHalfWidthDigits = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ""]

  // Table of Kanji number ranks
  static let kNumKanjiRanks = ["", "", "十", "百", "千"]
  static let kNumKanjiBiggerRanks = ["", "万", "億", "兆", "京"]
  static let kNumKanjiOldRanks = ["", "", "拾", "百", "阡"]
  static let kNumKanjiBiggerOldRanks = ["", "萬", "億", "兆", "京"]

  static let kRomanNumbersCapital = [
    "", "Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ", "Ⅶ", "Ⅷ", "Ⅸ", "Ⅹ", "Ⅺ", "Ⅻ", "",
  ]

  static let kRomanNumbersSmall = [
    "", "ⅰ", "ⅱ", "ⅲ", "ⅳ", "ⅴ", "ⅵ", "ⅶ", "ⅷ", "ⅸ", "ⅹ", "ⅺ", "ⅻ", "",
  ]

  static let kCircledNumbers = [
    "⓪", "①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩",
    "⑪", "⑫", "⑬", "⑭", "⑮", "⑯", "⑰", "⑱", "⑲", "⑳", "㉑",
    "㉒", "㉓", "㉔", "㉕", "㉖", "㉗", "㉘", "㉙", "㉚", "㉛", "㉜",
    "㉝", "㉞", "㉟", "㊱", "㊲", "㊳", "㊴", "㊵", "㊶", "㊷", "㊸",
    "㊹", "㊺", "㊻", "㊼", "㊽", "㊾", "㊿", "",
  ]

  static let kSuperscriptNumbers = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹", ""]
  static let kSubscriptNumbers = ["₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉", ""]

  // Structure to store character set variations.
  struct NumberStringVariation {
    let digits: [String]
    let description: String
    let separator: String
    let point: String
    let numbersSize: Int
    let style: NumberString.Style
  }

  static let kAsciiZero: UInt8 = 0x30  // '0'
  static let kAsciiOne: UInt8 = 0x31  // '1'
  static let kAsciiNine: UInt8 = 0x39  // '9'

  static func isAsciiDigit(_ c: UInt8) -> Bool { c >= 0x30 && c <= 0x39 }

  // Judges given string is a decimal number (including integer) or not.
  // It accepts strings whose last point is a decimal point like "123456."
  static func isDecimalNumber(_ str: some StringProtocol) -> Bool {
    var numPoint = 0
    for c in str.utf8 {
      if c == 0x2E {  // '.'
        numPoint += 1
        // A valid decimal number has at most one decimal point.
        if numPoint >= 2 {
          return false
        }
      } else if !isAsciiDigit(c) {
        return false
      }
    }
    return true
  }

  // MARK: - absl::SimpleAtoi / SimpleAtod

  static func isAsciiSpace(_ c: UInt8) -> Bool {
    // absl::ascii_isspace: ' ', '\t', '\n', '\v', '\f', '\r'
    c == 0x20 || (c >= 0x09 && c <= 0x0D)
  }

  static func stripAsciiWhitespace<C: Collection>(_ s: C) -> ArraySlice<UInt8> where C.Element == UInt8 {
    var bytes = ArraySlice(s)
    while let f = bytes.first, isAsciiSpace(f) { bytes.removeFirst() }
    while let l = bytes.last, isAsciiSpace(l) { bytes.removeLast() }
    return bytes
  }

  /// Port of `absl::SimpleAtoi` (base 10) for the integer type T.
  static func simpleAtoi<T: FixedWidthInteger>(_ str: some StringProtocol, as type: T.Type) -> T? {
    var text = stripAsciiWhitespace(str.utf8)
    if text.isEmpty {
      return nil
    }
    var negative = false
    if text.first == 0x2D {  // '-'
      negative = true
      text.removeFirst()
    } else if text.first == 0x2B {  // '+'
      text.removeFirst()
    }
    if text.isEmpty {
      return nil
    }
    if negative && !T.isSigned {
      return nil
    }
    var value: T = 0
    for c in text {
      guard isAsciiDigit(c) else { return nil }
      let digit = T(c - 0x30)
      let (m, o1) = value.multipliedReportingOverflow(by: 10)
      if o1 { return nil }
      if negative {
        let (s, o2) = m.subtractingReportingOverflow(digit)
        if o2 { return nil }
        value = s
      } else {
        let (s, o2) = m.addingReportingOverflow(digit)
        if o2 { return nil }
        value = s
      }
    }
    return value
  }

  /// Port of `absl::SimpleAtod`.
  static func simpleAtod(_ str: some StringProtocol) -> Double? {
    var text = stripAsciiWhitespace(str.utf8)
    // std::from_chars doesn't accept an initial +, but SimpleAtod does, so if
    // one is present, skip it, while avoiding accepting "+-0" as valid.
    if text.first == 0x2B {
      text.removeFirst()
      if text.first == 0x2D || text.first == 0x2B {
        return nil
      }
    }
    guard let first = text.first, !isAsciiSpace(first) else {
      return nil
    }
    // Swift's Double(String) uses strtod and requires the whole string to be
    // consumed (decimal, hexadecimal, inf and nan forms are accepted).
    return Double(String(decoding: text, as: UTF8.self))
  }

  // MARK: - Public API

  /// Converts the string to a number and return it.
  public static func simpleAtoi(_ str: some StringProtocol) -> Int {
    if let integer = simpleAtoi(str, as: Int32.self) {
      return Int(integer)
    }
    return 0
  }

  // TODO(hidehiko): Refactoring with GetScriptType in Util class.
  static func isArabicDecimalChar32(_ codepoint: Char32) -> Bool {
    // Halfwidth digit.
    if Char32(kAsciiZero) <= codepoint && codepoint <= Char32(kAsciiNine) {
      return true
    }

    // Fullwidth digit.
    if 0xFF10 <= codepoint && codepoint <= 0xFF19 {
      return true
    }

    return false
  }

  /// Returns true if the given input_string contains only number characters
  /// (regardless of halfwidth or fullwidth). False for empty string.
  public static func isArabicNumber(_ inputString: some StringProtocol) -> Bool {
    if inputString.isEmpty {
      return false
    }
    for c in ConstChar32Iterator(inputString) where !isArabicDecimalChar32(c) {
      // Found non-Arabic decimal character.
      return false
    }

    // All characters are numbers.
    return true
  }

  /// Returns true if the given str consists of only ASCII digits.
  /// False for empty string.
  public static func isDecimalInteger(_ str: some StringProtocol) -> Bool {
    if str.isEmpty {
      return false
    }
    return str.utf8.allSatisfy(isAsciiDigit)
  }

  // To know what "大字" means, please refer
  // http://ja.wikipedia.org/wiki/%E5%A4%A7%E5%AD%97_(%E6%95%B0%E5%AD%97)
  static let kKanjiVariations: [NumberStringVariation] = [
    NumberStringVariation(
      digits: kNumHalfWidthDigits, description: "数字", separator: "", point: "", numbersSize: 10,
      style: .numberArabicAndKanjiHalfwidth),
    NumberStringVariation(
      digits: kNumFullWidthDigits, description: "数字", separator: "", point: "", numbersSize: 10,
      style: .numberArabicAndKanjiFullwidth),
    NumberStringVariation(
      digits: kNumKanjiDigits, description: "漢数字", separator: "", point: "", numbersSize: 10,
      style: .numberKanji),
    NumberStringVariation(
      digits: kNumKanjiOldDigits, description: "大字", separator: "", point: "", numbersSize: 10,
      style: .numberOldKanji),
  ]

  static let kOldTwoTen = "弐拾"
  static let kOldTwenty = "廿"

  /// Converts half-width Arabic number string to Kan-su-ji string.
  ///   - input_num: a string which *must* be half-width number string.
  ///   - output: function appends new representation into output vector.
  /// value, desc and style are stored same size and same order.
  /// if invalid string is set, this function do nothing.
  @discardableResult
  public static func arabicToKanji(_ inputNum: some StringProtocol, _ output: inout [NumberString])
    -> Bool
  {
    let kNumZero = "零"
    let kDigitsInBigRank = 4

    if !isDecimalInteger(inputNum) {
      return false
    }

    let inputBytes = Array(inputNum.utf8)
    // We don't convert a number starting with '0', other than 0 itself.
    if inputBytes.allSatisfy({ $0 == kAsciiZero }) {
      output.append(NumberString(kNumZero, "大字", .numberOldKanji))
      return true
    }

    // If given number needs higher ranks than our expectations,
    // we don't convert it.
    if kNumKanjiBiggerRanks.count * kDigitsInBigRank < inputBytes.count {
      return false
    }

    // Fill '0' in the beginning of input_num to make its length
    // (N * kDigitsInBigRank).
    let filledZeroNum = (kDigitsInBigRank - (inputBytes.count % kDigitsInBigRank)) % kDigitsInBigRank
    let input = [UInt8](repeating: kAsciiZero, count: filledZeroNum) + inputBytes

    // Segment into kDigitsInBigRank-digits pieces
    var rankedNumbers: [ArraySlice<UInt8>] = []
    var i = input.count - kDigitsInBigRank
    while i >= 0 {
      rankedNumbers.append(input[i..<(i + kDigitsInBigRank)])
      i -= kDigitsInBigRank
    }
    let rankSize = rankedNumbers.count

    for variation in kKanjiVariations {
      let digits = variation.digits
      let style = variation.style

      if rankSize == 1
        && (style == .numberArabicAndKanjiHalfwidth || style == .numberArabicAndKanjiFullwidth)
      {
        continue
      }

      let ranks: [String]
      let biggerRanks: [String]
      if style == .numberOldKanji {
        ranks = kNumKanjiOldRanks
        biggerRanks = kNumKanjiBiggerOldRanks
      } else {
        ranks = kNumKanjiRanks
        biggerRanks = kNumKanjiBiggerRanks
      }

      var result = ""

      // Converts each segment, and merges them with rank Kanjis.
      var rank = rankSize - 1
      while rank >= 0 {
        let segment = Array(rankedNumbers[rank])
        var segmentResult = ""
        var leading = true
        for i in 0..<segment.count {
          if leading && segment[i] == kAsciiZero {
            continue
          }

          leading = false
          if style == .numberArabicAndKanjiHalfwidth || style == .numberArabicAndKanjiFullwidth {
            segmentResult += digits[Int(segment[i] - kAsciiZero)]
          } else {
            if segment[i] == kAsciiZero {
              continue
            }
            // In "大字" style, "壱" is also required on every rank.
            if style == .numberOldKanji || i == kDigitsInBigRank - 1 || segment[i] != kAsciiOne {
              segmentResult += digits[Int(segment[i] - kAsciiZero)]
            }
            segmentResult += ranks[kDigitsInBigRank - i]
          }
        }
        if !segmentResult.isEmpty {
          result += segmentResult + biggerRanks[rank]
        }
        rank -= 1
      }

      let description = variation.description
      // Add simply converted numbers.
      output.append(NumberString(result, description, style))

      // Add specialized style numbers.
      if style == .numberOldKanji {
        let last = output[output.count - 1].value
        if last.utf8.firstRange(of: kOldTwoTen.utf8) != nil {
          let tmp = replaceAllBytes(last, kOldTwoTen, kOldTwenty)
          output.append(NumberString(tmp, description, style))
        }

        // for single kanji
        let inputString = String(decoding: input, as: UTF8.self)
        if inputString == "0010" {
          output.append(NumberString("拾", description, style))
        }
        if inputString == "1000" {
          output.append(NumberString("阡", description, style))
        }
      }
    }

    return true
  }

  /// absl::StrReplaceAll with a single bytewise replacement.
  static func replaceAllBytes(_ s: String, _ from: String, _ to: String) -> String {
    let src = Array(s.utf8)
    let pat = Array(from.utf8)
    let rep = Array(to.utf8)
    var out: [UInt8] = []
    var i = 0
    while i < src.count {
      if i + pat.count <= src.count && src[i..<(i + pat.count)].elementsEqual(pat) {
        out.append(contentsOf: rep)
        i += pat.count
      } else {
        out.append(src[i])
        i += 1
      }
    }
    return String(decoding: out, as: UTF8.self)
  }

  static let kNumDigitsVariations: [NumberStringVariation] = [
    NumberStringVariation(
      digits: kNumHalfWidthDigits, description: "数字", separator: ",", point: ".", numbersSize: 10,
      style: .numberSeparatedArabicHalfwidth),
    NumberStringVariation(
      digits: kNumFullWidthDigits, description: "数字", separator: "，", point: "．",
      numbersSize: 10, style: .numberSeparatedArabicFullwidth),
  ]

  /// Converts half-width Arabic number string to Separated Arabic string.
  /// (e.g. 1234567890 are converted to 1,234,567,890)
  @discardableResult
  public static func arabicToSeparatedArabic(
    _ inputNum: some StringProtocol, _ output: inout [NumberString]
  ) -> Bool {
    if !isDecimalNumber(inputNum) {
      return false
    }

    let bytes = Array(inputNum.utf8)
    // Separate a number into an integral part and a fractional part.
    let pointPos = bytes.firstIndex(of: 0x2E) ?? bytes.count
    let integer = bytes[0..<pointPos]
    // |fraction| has the decimal point with digits in fractional part.
    let fraction = bytes[pointPos...]

    // We don't add separator to number whose integral part starts with '0'.
    // (In C++, integer[0] of an empty integral part reads the next byte of the
    // input, which is '.' or the terminating '\0'.)
    if (bytes.first ?? 0) == kAsciiZero {
      return false
    }

    for variation in kNumDigitsVariations {
      let digits = variation.digits
      var result = ""

      // integral part
      for j in 0..<integer.count {
        // We don't add separator first
        if j != 0 && (integer.count - j) % 3 == 0 {
          result += variation.separator
        }
        let d = UInt32(integer[integer.startIndex + j]) &- UInt32(kAsciiZero)
        if d <= 9 && !digits[Int(d)].isEmpty {
          result += digits[Int(d)]
        }
      }

      // fractional part
      if !fraction.isEmpty {
        result += variation.point
        for j in (fraction.startIndex + 1)..<fraction.endIndex {
          result += digits[Int(fraction[j] - kAsciiZero)]
        }
      }

      output.append(NumberString(result, variation.description, variation.style))
    }
    return true
  }

  // use default for wide Arabic, because half/full width for
  // normal number is learned by character form manager.
  static let kSingleDigitsVariations: [NumberStringVariation] = [
    NumberStringVariation(
      digits: kNumKanjiDigits, description: "漢数字", separator: "", point: "", numbersSize: 10,
      style: .numberKanjiArabic),
    NumberStringVariation(
      digits: kNumFullWidthDigits, description: "数字", separator: "", point: "", numbersSize: 10,
      style: .defaultStyle),
  ]

  /// Converts half-width Arabic number string to full-width Arabic number
  /// string.
  @discardableResult
  public static func arabicToWideArabic(_ inputNum: some StringProtocol, _ output: inout [NumberString])
    -> Bool
  {
    if !isDecimalInteger(inputNum) {
      return false
    }

    for variation in kSingleDigitsVariations {
      var result = ""
      for c in inputNum.utf8 {
        result += variation.digits[Int(c - kAsciiZero)]
      }
      if !result.isEmpty {
        output.append(NumberString(result, variation.description, variation.style))
      }
    }
    return true
  }

  static let kSpecialNumericVariations: [NumberStringVariation] = [
    NumberStringVariation(
      digits: kRomanNumbersCapital, description: "ローマ数字(大文字)", separator: "", point: "",
      numbersSize: kRomanNumbersCapital.count, style: .numberRomanCapital),
    NumberStringVariation(
      digits: kRomanNumbersSmall, description: "ローマ数字(小文字)", separator: "", point: "",
      numbersSize: kRomanNumbersSmall.count, style: .numberRomanSmall),
    NumberStringVariation(
      digits: kCircledNumbers, description: "丸数字", separator: "", point: "",
      numbersSize: kCircledNumbers.count, style: .numberCircled),
    NumberStringVariation(
      digits: kSuperscriptNumbers, description: "上付き文字", separator: "", point: "",
      numbersSize: kSuperscriptNumbers.count, style: .numberSuperscript),
    NumberStringVariation(
      digits: kSubscriptNumbers, description: "下付き文字", separator: "", point: "",
      numbersSize: kSubscriptNumbers.count, style: .numberSubscript),
  ]

  /// Converts half-width Arabic number to various styles.
  ///   - Roman style (i) (ii) ...
  @discardableResult
  public static func arabicToOtherForms(_ inputNum: some StringProtocol, _ output: inout [NumberString])
    -> Bool
  {
    if !isDecimalInteger(inputNum) {
      return false
    }

    var converted = false

    // Googol
    do {
      // 10^100
      let kNumGoogol =
        "100000000000000000000000000000000000000000000000000"
        + "00000000000000000000000000000000000000000000000000"

      if inputNum.bytesEqual(kNumGoogol) {
        output.append(NumberString("Googol", "", .defaultStyle))
        converted = true
      }
    }

    // Following conversions require uint64_t number.
    guard let n = simpleAtoi(inputNum, as: UInt64.self) else {
      return converted
    }

    // Special forms
    for variation in kSpecialNumericVariations {
      if n < UInt64(variation.numbersSize) && !variation.digits[Int(n)].isEmpty {
        output.append(NumberString(variation.digits[Int(n)], variation.description, variation.style))
        converted = true
      }
    }

    return converted
  }

  /// Converts half-width Arabic number to various radices (2,8,16).
  /// Excepted number of input digits is smaller than 20, but it can be
  /// converted only if it can be stored in an unsigned 64-bit integer.
  @discardableResult
  public static func arabicToOtherRadixes(_ inputNum: some StringProtocol, _ output: inout [NumberString])
    -> Bool
  {
    if !isDecimalInteger(inputNum) {
      return false
    }

    guard let n = simpleAtoi(inputNum, as: UInt64.self) else {
      return false
    }

    // Hexadecimal
    if n > 9 {
      output.append(NumberString("0x" + String(n, radix: 16), "16進数", .numberHex))
    }

    // Octal
    if n > 7 {
      output.append(NumberString("0" + String(n, radix: 8), "8進数", .numberOct))
    }

    // Binary
    if n > 1 {
      output.append(NumberString("0b" + String(n, radix: 2), "2進数", .numberBin))
    }

    return n > 1
  }

  // MARK: - Safe conversions

  /// Converts the string to a 16-bit signed int. Returns nil if the string is
  /// in the wrong format or out of range.
  public static func safeStrToInt16(_ str: some StringProtocol) -> Int16? {
    // SimpleAtoi doesn't support 16-bit integers.
    guard let tmp = simpleAtoi(str, as: Int32.self) else {
      return nil
    }
    return Int16(exactly: tmp)
  }

  /// Converts the string to a 16-bit unsigned int.
  public static func safeStrToUInt16(_ str: some StringProtocol) -> UInt16? {
    // SimpleAtoi doesn't support 16-bit integers.
    guard let tmp = simpleAtoi(str, as: UInt32.self) else {
      return nil
    }
    return UInt16(exactly: tmp)
  }

  /// Converts the string to a double.  Returns nil if the string is in the
  /// wrong format, NaN or overflows.
  public static func safeStrToDouble(_ str: some StringProtocol) -> Double? {
    guard let value = simpleAtod(str) else {
      return nil
    }
    // SafeStrToDouble returns false for NaN and overflows.
    if value.isNaN || value == .infinity || value == -.infinity {
      return nil
    }
    return value
  }

  // MARK: - NormalizeNumbers

  // There is an informative discussion about the overflow detection in
  // "Hacker's Delight" (http://www.hackersdelight.org/basics.pdf)
  //   2-12 'Overflow Detection'

  // *output = arg1 + arg2
  // return false when an integer overflow happens.
  static func addAndCheckOverflow(_ arg1: UInt64, _ arg2: UInt64, _ output: inout UInt64) -> Bool {
    let (r, o) = arg1.addingReportingOverflow(arg2)
    output = r
    return !o
  }

  // *output = arg1 * arg2
  // return false when an integer overflow happens.
  static func multiplyAndCheckOverflow(_ arg1: UInt64, _ arg2: UInt64, _ output: inout UInt64) -> Bool
  {
    let (r, o) = arg1.multipliedReportingOverflow(by: arg2)
    output = r
    return !o
  }

  // Reduces leading digits less than 10 as their base10 interpretation, e.g.,
  //   [1, 2, 3, 10, 100] => begin points to [10, 100], output = 123
  // Returns false when overflow happened.
  static func reduceLeadingNumbersAsBase10System(
    _ numbers: [UInt64], _ begin: inout Int, _ end: Int, _ output: inout UInt64
  ) -> Bool {
    output = 0
    while begin < end {
      if numbers[begin] >= 10 {
        break
      }
      // output = output * 10 + *begin
      if !multiplyAndCheckOverflow(output, 10, &output)
        || !addAndCheckOverflow(output, numbers[begin], &output)
      {
        return false
      }
      begin += 1
    }
    return true
  }

  // Interprets digits as base10 system, e.g.,
  //   [1, 2, 3] => 123
  //   [1, 2, 3, 10] => false
  // Returns false if a number greater than 10 was found or overflow happened.
  static func interpretNumbersAsBase10System(_ numbers: [UInt64], _ output: inout UInt64) -> Bool {
    var begin = 0
    let success = reduceLeadingNumbersAsBase10System(numbers, &begin, numbers.count, &output)
    // Check if the whole numbers were reduced.
    return success && begin == numbers.count
  }

  // Reads a leading number in a sequence and advances the iterator. Returns
  // false if the range is empty or the leading number is not less than 10.
  static func reduceOnesDigit(_ numbers: [UInt64], _ begin: inout Int, _ end: Int, _ num: inout UInt64)
    -> Bool
  {
    if begin == end || numbers[begin] >= 10 {
      return false
    }
    num = numbers[begin]
    begin += 1
    return true
  }

  // Given expected_base, 10, 100, or 1000, reads leading one or two numbers and
  // calculates the number in the following way:
  //   Case: expected_base == 10
  //     [10, ...] => 10
  //     [2, 10, ...] => 20
  //     [1, 10, ...] => error because we don't write "一十" in Japanese.
  //     [20, ...] => 20 because "廿" is interpreted as 20.
  //     [2, 0, ...] => 20
  //   Case: expected_base == 100
  //     [100, ...] => 100
  //     [2, 100, ...] => 200
  //     [1, 100, ...] => error because we don't write "一百" in Japanese.
  //     [1, 2, 3, ...] => 123
  //   Case: expected_base == 1000
  //     [1000, ...] => 1000
  //     [2, 1000, ...] => 2000
  //     [1, 1000, ...] => 1000
  //     [1, 2, 3, 4, ...] => 1234
  static func reduceDigitsHelper(
    _ numbers: [UInt64], _ begin: inout Int, _ end: Int, _ expectedBase: UInt64, _ num: inout UInt64
  ) -> Bool {
    // Skip leading zero(s).
    while begin != end && numbers[begin] == 0 {
      begin += 1
    }
    if begin == end {
      return false
    }
    let leadingNumber = numbers[begin]

    // If the leading number is less than 10, e.g., patterns like [2, 10], we
    // need to check the next number.
    if leadingNumber < 10 {
      if end - begin < 2 {
        return false
      }
      let nextNumber = numbers[begin + 1]

      // If the next number is also less than 10, this pattern is like
      // [1, 2, ...] => 12. In this case, the result must be less than
      // 10 * expected_base.
      if nextNumber < 10 {
        if !reduceLeadingNumbersAsBase10System(numbers, &begin, end, &num)
          || num >= expectedBase * 10 || (begin != end && numbers[begin] < 10000)
        {
          begin = end  // Force to ignore the rest of the sequence.
          return false
        }
        return true
      }

      // Patterns like [2, 10, ...] and [1, 1000, ...].
      if nextNumber != expectedBase || (leadingNumber == 1 && expectedBase != 1000) {
        return false
      }
      num = leadingNumber * expectedBase
      begin += 2
      return true
    }

    // Patterns like [10, ...], [100, ...], [1000, ...], [20, ...]. The leading
    // 20 is a special case for Kanji "廿".
    if leadingNumber == expectedBase || (expectedBase == 10 && leadingNumber == 20) {
      num = leadingNumber
      begin += 1
      return true
    }
    return false
  }

  // Reduces leading digits as a number less than 10000 and advances the
  // iterator. For example:
  //   [1, 1000, 2, 100, 3, 10, 4, 10000, ...]
  //        => begin points to [10000, ...], num = 1234
  //   [3, 100, 4, 100]
  //        => error because same base number appears twice
  static func reduceNumberLessThan10000(
    _ numbers: [UInt64], _ begin: inout Int, _ end: Int, _ num: inout UInt64
  ) -> Bool {
    num = 0
    var success = false
    var n: UInt64 = 0
    // Note: the following additions never overflow.
    if reduceDigitsHelper(numbers, &begin, end, 1000, &n) {
      num += n
      success = true
    }
    if reduceDigitsHelper(numbers, &begin, end, 100, &n) {
      num += n
      success = true
    }
    if reduceDigitsHelper(numbers, &begin, end, 10, &n) {
      num += n
      success = true
    }
    if reduceOnesDigit(numbers, &begin, end, &n) {
      num += n
      success = true
    }
    // If at least one reduce was successful, no number remains in the sequence
    // or the next number should be a base number greater than 1000 (e.g.,
    // 10000, 100000, etc.). Strictly speaking, better to check
    // **begin % 10 == 0.
    return success && (begin == end || numbers[begin] >= 10000)
  }

  // Interprets a sequence of numbers in a Japanese reading way. For example:
  //   "一万二千三百四十五" = [1, 10000, 2, 1000, 3, 100, 4, 10, 5] => 12345
  // Base-10 numbers must be decreasing, i.e.,
  //   "一十二百" = [1, 10, 2, 100] => error
  static func interpretNumbersInJapaneseWay(_ numbers: [UInt64], _ output: inout UInt64) -> Bool {
    var lastBase = UInt64.max
    var begin = 0
    let end = numbers.count
    output = 0
    repeat {
      var coef: UInt64 = 0
      if !reduceNumberLessThan10000(numbers, &begin, end, &coef) {
        return false
      }
      if begin == end {
        return addAndCheckOverflow(output, coef, &output)
      }
      if numbers[begin] >= lastBase {
        return false  // Increasing order of base-10 numbers.
      }
      // Safely performs *output += coef * *begin.
      var delta: UInt64 = 0
      if !multiplyAndCheckOverflow(coef, numbers[begin], &delta)
        || !addAndCheckOverflow(output, delta, &output)
      {
        return false
      }
      lastBase = numbers[begin]
      begin += 1
    } while begin != end

    return true
  }

  // Interprets a sequence of numbers directly or in a Japanese reading way
  // depending on the maximum number in the sequence.
  static func normalizeNumbersHelper(_ numbers: [UInt64], _ numberOutput: inout UInt64) -> Bool {
    guard let max = numbers.max() else {
      return false  // numbers is empty
    }

    // When no scaling number is found, convert number directly.
    // For example, [5,4,3] => 543
    if max < 10 {
      return interpretNumbersAsBase10System(numbers, &numberOutput)
    }
    return interpretNumbersInJapaneseWay(numbers, &numberOutput)
  }

  // TODO(peria): Do refactoring this method.
  static func normalizeNumbersInternal(
    _ input: some StringProtocol, _ trimLeadingZeros: Bool, _ allowSuffix: Bool,
    _ kanjiOutput: inout String, _ arabicOutput: inout String, _ suffix: inout String
  ) -> Bool {
    var numbers: [UInt64] = []
    numbers.reserveCapacity(input.utf8.count)

    // Map Kanji number string to digits, e.g., "二百十一" -> [2, 100, 10, 1].
    // Simultaneously, constructs a Kanji number string.
    kanjiOutput = ""
    arabicOutput = ""

    let chars = Utf8AsUnicodeChar(input)
    for i in chars.indices {
      let ch = chars[i]
      var kanjiChar = ch.utf8

      let tmp = kanjiNumberToArabicNumber(kanjiChar)
      guard let n = simpleAtoi(tmp, as: UInt64.self) else {
        if !allowSuffix {
          return false
        }
        suffix = String(chars.substring(i))
        if Util.containsScriptType(suffix, .number) {
          // We do want to treat "2,000" as "2" + ",000".
          return false
        }
        break
      }

      let codepoint = ch.char32
      if codepoint >= 0x30 && codepoint <= 0x39 {  // '0' <= codepoint <= '9'
        kanjiChar = Substring(kNumKanjiDigits[Int(codepoint - 0x0030)])
      } else if codepoint >= 0xFF10 && codepoint <= 0xFF19 {  // '０' <= codepoint <= '９'
        kanjiChar = Substring(kNumKanjiDigits[Int(codepoint - 0xFF10)])
      }
      kanjiOutput += kanjiChar
      numbers.append(n)
    }

    if numbers.isEmpty {
      return false
    }

    // Try interpreting the sequence of digits.
    var n: UInt64 = 0
    if !normalizeNumbersHelper(numbers, &n) {
      return false
    }

    if !trimLeadingZeros {
      // If |numbers| contains only k zeros, add (k - 1) zeros to the output.
      // Otherwise, add the same number of leading zeros.
      var numZeros = 0
      while numZeros < numbers.count {
        if numbers[numZeros] != 0 {
          break
        }
        numZeros += 1
      }
      if numZeros == numbers.count {
        numZeros -= 1
      }
      arabicOutput += String(repeating: "0", count: numZeros)
    }

    arabicOutput += String(n)
    return true
  }

  /// Convert Kanji numeric into Arabic numeric.
  /// When the trim_leading_zeros is true, leading zeros for arabic_output
  /// are trimmed off.
  ///
  /// Input: "2千五百"
  /// kanji_output: "二千五百"
  /// arabic output: 2500
  ///
  /// NormalizeNumbers() returns false if it finds non-number characters.
  public static func normalizeNumbers(
    _ input: some StringProtocol, _ trimLeadingZeros: Bool, _ kanjiOutput: inout String,
    _ arabicOutput: inout String
  ) -> Bool {
    var unusedSuffix = ""
    return normalizeNumbersInternal(
      input, trimLeadingZeros, false, &kanjiOutput, &arabicOutput, &unusedSuffix)
  }

  /// NormalizeNumbersWithSuffix() skips trailing non-number characters and
  /// return them in "suffix".
  public static func normalizeNumbersWithSuffix(
    _ input: some StringProtocol, _ trimLeadingZeros: Bool, _ kanjiOutput: inout String,
    _ arabicOutput: inout String, _ suffix: inout String
  ) -> Bool {
    normalizeNumbersInternal(input, trimLeadingZeros, true, &kanjiOutput, &arabicOutput, &suffix)
  }

  /// Note: this function just does charcter-by-character conversion
  /// "百二十" -> 10020
  public static func kanjiNumberToArabicNumber(_ input: some StringProtocol) -> String {
    // TODO(yuryu): This file will also move into strings/.
    JapaneseInternal.convertUsingDoubleArray(JapaneseInternal.kanjinumberToArabicnumber, input)
  }
}
