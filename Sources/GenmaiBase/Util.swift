// Port of mozc/src/base/util.{h,cc} (3.35.6354).
//
// Functions whose C++ behavior depends on raw bytes (ill-formed UTF-8, 5/6-byte
// legacy sequences, BOMs) have generic overloads taking a `Collection` of
// `UInt8`; the `StringProtocol` overloads are the ones normally used by the
// rest of the port.

public enum Util {
  // MARK: - Splitting into characters

  /// Splits a string into UTF8 chars.
  public static func splitStringToUtf8Chars(_ str: some StringProtocol) -> [String] {
    var output: [String] = []
    appendUtf8Chars(str, &output)
    return output
  }

  /// Splits a string into UTF8 chars and appends them to `output`.
  public static func appendUtf8Chars(_ str: some StringProtocol, _ output: inout [String]) {
    for scalar in str.unicodeScalars {
      output.append(String(scalar))
    }
  }

  /// Splits a string into UTF8 chars and appends them to `output`.
  public static func appendUtf8Chars(_ str: some StringProtocol, _ output: inout [Substring]) {
    output.append(contentsOf: Utf8AsChars(str))
  }

  /// Split `str` to graphemes.
  /// A grapheme may contain multiple characters such as modifiers and variation
  /// squesnces (e.g. 神︀ = U+795E,U+FE00 [SVS]).
  /// Note, this function does not support full requirements of the grapheme
  /// specifications defined by Unicode.
  /// * https://www.unicode.org/reports/tr29/#Grapheme_Cluster_Boundaries
  public static func splitStringToUtf8Graphemes(_ str: some StringProtocol) -> [String] {
    let graphemes = splitStringToUtf8Chars(str)
    if graphemes.count <= 1 {
      return graphemes
    }

    // Use U+0000 (NUL) to represent a codepoint which doesn't appear in any
    // grapheme clusters since it's always used standalone.
    let kStandaloneCodepoint: Char32 = 0x0000
    var prev = kStandaloneCodepoint
    var newGraphemes: [String] = []
    newGraphemes.reserveCapacity(graphemes.count)

    for grapheme in graphemes {
      let codepoint = utf8ToCodepoint(grapheme)
      let isDakuten = (codepoint == 0x3099 || codepoint == 0x309A)
      let isSvs = (0xFE00 <= codepoint && codepoint <= 0xFE0F)
      let isIvs = (0xE0100 <= codepoint && codepoint <= 0xE01EF)

      // ED-8a. text presentation sequence
      let isTextPresentationSequence = (codepoint == 0xFE0E)  // VS15

      // ED-9a. emoji presentation sequence
      let isEmojiPresentationSequence = (codepoint == 0xFE0F)  // VS16

      // ED-13. emoji modifier sequence
      let isEmojiModifierSequence = (codepoint >= 0x1F3FB && codepoint <= 0x1F3FF)

      // ED-14. emoji flag sequence
      let isEmojiFlagSequence =
        ((prev >= 0x1F1E6 && prev <= 0x1F1FF) && (codepoint >= 0x1F1E6 && codepoint <= 0x1F1FF))

      // ED-14.a. emoji tag sequence (ETS)
      let isEmojiTagSequence =
        ((codepoint >= 0xE0020 && codepoint <= 0xE007E)  // tag_spec
          || (codepoint == 0xE007F))  // tag_end

      // ED-14.c. emoji keycap sequence
      let isEmojiKeycapSequence = (prev == 0xFE0F && codepoint == 0x20E3)

      // ED-16. emoji zwj sequence
      let isEmojiZwjSequence = (codepoint == 0x200D || prev == 0x200D)  // ZWJ

      if isEmojiFlagSequence && !newGraphemes.isEmpty {
        newGraphemes[newGraphemes.count - 1] += grapheme
        // Reset prev with noop value in case that regional indicator codepoints
        // continues more than 2.
        prev = kStandaloneCodepoint
        continue
      }

      if (isDakuten || isSvs || isIvs || isTextPresentationSequence
        || isEmojiPresentationSequence || isEmojiModifierSequence || isEmojiTagSequence
        || isEmojiKeycapSequence || isEmojiZwjSequence) && !newGraphemes.isEmpty
      {
        newGraphemes[newGraphemes.count - 1] += grapheme
      } else {
        newGraphemes.append(grapheme)
      }
      prev = codepoint
    }

    return newGraphemes
  }

  /// Splits a CSV line.
  public static func splitCSV(_ input: some StringProtocol) -> [String] {
    // A mutable copy with the terminating '\0' of std::string.
    var buf = Array(input.utf8)
    let eos = buf.count
    buf.append(0)
    var str = 0
    var start = 0
    var end = 0
    var output: [String] = []

    while str < eos {
      while buf[str] == 0x20 || buf[str] == 0x09 {
        str += 1
      }

      if buf[str] == 0x22 {  // '"'
        str += 1
        start = str
        end = start
        while str < eos {
          if buf[str] == 0x22 {
            str += 1
            if buf[str] != 0x22 { break }
          }
          buf[end] = buf[str]
          end += 1
          str += 1
        }
        str = buf[str..<eos].firstIndex(of: 0x2C) ?? eos
      } else {
        start = str
        str = buf[str..<eos].firstIndex(of: 0x2C) ?? eos
        end = str
      }
      var endIsEmpty = false
      if buf[end] == 0x2C && end == eos - 1 {
        endIsEmpty = true
      }
      output.append(String(decoding: buf[start..<end], as: UTF8.self))
      if endIsEmpty {
        output.append("")
      }

      str += 1
    }
    return output
  }

  // MARK: - Case conversion

  // The offset value to transform the upper case character to the lower
  // case.  The value comes from both of (0x0061 "a" - 0x0041 "A") and
  // (0xFF41 "ａ" - 0xFF21 "Ａ").
  private static let kOffsetFromUpperToLower: Char32 = 0x0020

  public static func lowerString(_ str: inout String) {
    var result = String.UnicodeScalarView()
    var changed = false
    for scalar in str.unicodeScalars {
      let codepoint = scalar.value
      // ('A' <= codepoint && codepoint <= 'Z') ||
      // ('Ａ' <= codepoint && codepoint <= 'Ｚ')
      if (0x0041 <= codepoint && codepoint <= 0x005A) || (0xFF21 <= codepoint && codepoint <= 0xFF3A) {
        result.append(Unicode.Scalar(codepoint + kOffsetFromUpperToLower) ?? scalar)
        changed = true
      } else {
        result.append(scalar)
      }
    }
    if changed {
      str = String(result)
    }
  }

  public static func upperString(_ str: inout String) {
    var result = String.UnicodeScalarView()
    var changed = false
    for scalar in str.unicodeScalars {
      let codepoint = scalar.value
      // ('a' <= codepoint && codepoint <= 'z') ||
      // ('ａ' <= codepoint && codepoint <= 'ｚ')
      if (0x0061 <= codepoint && codepoint <= 0x007A) || (0xFF41 <= codepoint && codepoint <= 0xFF5A) {
        result.append(Unicode.Scalar(codepoint - kOffsetFromUpperToLower) ?? scalar)
        changed = true
      } else {
        result.append(scalar)
      }
    }
    if changed {
      str = String(result)
    }
  }

  /// Transforms the first character to the upper case and tailing characters
  /// to the lower cases.  ex. "abCd" => "Abcd".
  public static func capitalizeString(_ str: inout String) {
    var firstStr = String(utf8SubString(str, 0, 1))
    upperString(&firstStr)

    var tailingStr = String(utf8SubString(str, 1, Int.max))
    lowerString(&tailingStr)

    str = firstStr + tailingStr
  }

  private static func isAsciiLower(_ c: UInt8) -> Bool { c >= 0x61 && c <= 0x7A }
  private static func isAsciiUpper(_ c: UInt8) -> Bool { c >= 0x41 && c <= 0x5A }

  /// Returns true if the characters in [first, last) are all in lower case
  /// ASCII.
  public static func isLowerAscii(_ s: some StringProtocol) -> Bool {
    s.utf8.allSatisfy(isAsciiLower)
  }

  /// Returns true if the characters in [first, last) are all in upper case
  /// ASCII.
  public static func isUpperAscii(_ s: some StringProtocol) -> Bool {
    s.utf8.allSatisfy(isAsciiUpper)
  }

  /// Returns true if the text in the rage [first, last) is capitalized ASCII.
  public static func isCapitalizedAscii(_ s: some StringProtocol) -> Bool {
    guard let first = s.utf8.first else {
      return true
    }
    if isAsciiUpper(first) {
      return s.utf8.dropFirst().allSatisfy(isAsciiLower)
    }
    return false
  }

  // MARK: - UTF-8 utilities

  private static func isUtf8TrailingByte(_ c: UInt8) -> Bool { (c & 0xc0) == 0x80 }

  /// Returns the lengths of [src, src+size] encoded in UTF8.
  public static func charsLen(_ str: some StringProtocol) -> Int {
    Strings.charsLen(str)
  }

  public static func charsLen<C: Collection>(_ bytes: C) -> Int where C.Element == UInt8 {
    Strings.charsLen(bytes)
  }

  /// Returns the character length of every byte prefix of `str`.
  /// The i-th element of the returned vector is CharsLen(str.substr(0, i)).
  public static func prefixCharsLen<C: Collection>(_ bytes: C) -> [Int] where C.Element == UInt8 {
    let str = Array(bytes)
    var charLens = [Int](repeating: 0, count: str.count + 1)
    var byteOffset = 0
    var charOffset = 0
    while byteOffset < str.count {
      let len = Strings.oneCharLen(str[byteOffset])
      var i = 0
      while i < len && byteOffset + i < str.count {
        charLens[byteOffset + i] = charOffset
        i += 1
      }
      byteOffset += len
      charOffset += 1
    }
    charLens[str.count] = charOffset
    return charLens
  }

  public static func prefixCharsLen(_ str: some StringProtocol) -> [Int] {
    prefixCharsLen(str.utf8)
  }

  /// Converts a UTF-8 string to UTF-32. Stops at the first invalid sequence.
  public static func utf8ToUtf32<C: Collection>(_ bytes: C) -> [Char32] where C.Element == UInt8 {
    var codepoints: [Char32] = []
    var str = bytes[...]
    while let (codepoint, rest) = splitFirstChar32(str) {
      codepoints.append(codepoint)
      str = rest
    }
    return codepoints
  }

  public static func utf8ToUtf32(_ str: some StringProtocol) -> [Char32] {
    str.unicodeScalars.map { $0.value }
  }

  /// Converts a UTF-32 string to UTF-8 bytes (CodepointToUtf8Append; NUL is
  /// skipped and code points up to 0x7FFFFFFF use the legacy 5/6-byte forms).
  public static func utf32ToUtf8Bytes(_ str: some Sequence<Char32>) -> [UInt8] {
    var output: [UInt8] = []
    for codepoint in str {
      codepointToUtf8Append(codepoint, &output)
    }
    return output
  }

  /// Converts a UTF-32 string to UTF-8.
  public static func utf32ToUtf8(_ str: some Sequence<Char32>) -> String {
    var output = ""
    for codepoint in str {
      codepointToUtf8Append(codepoint, &output)
    }
    return output
  }

  /// Converts the first character of UTF8 string to UCS4. Returns the code
  /// point and the read byte length (0, 0 if the sequence is invalid or empty).
  public static func utf8ToCodepoint<C: Collection>(_ s: C) -> (codepoint: Char32, mblen: Int)
  where C.Element == UInt8 {
    guard let (c, rest) = splitFirstChar32(s) else {
      return (0, 0)
    }
    return (c, s.count - rest.count)
  }

  public static func utf8ToCodepoint(_ s: some StringProtocol, _ mblen: inout Int) -> Char32 {
    let r = utf8ToCodepoint(s.utf8)
    mblen = r.mblen
    return r.codepoint
  }

  public static func utf8ToCodepoint(_ s: some StringProtocol) -> Char32 {
    utf8ToCodepoint(s.utf8).codepoint
  }

  /// Converts a UCS4 code point to UTF8 string.
  public static func codepointToUtf8(_ c: Char32) -> String {
    var output = ""
    codepointToUtf8Append(c, &output)
    return output
  }

  /// Converts a UCS4 code point to UTF8 string and appends it to |output|.
  public static func codepointToUtf8Append(_ c: Char32, _ output: inout String) {
    if c != 0, let scalar = Unicode.Scalar(c) {
      output.unicodeScalars.append(scalar)
      return
    }
    let bytes = codepointToUtf8Bytes(c)
    if !bytes.isEmpty {
      output += String(decoding: bytes, as: UTF8.self)
    }
  }

  /// Byte version of codepointToUtf8Append.
  public static func codepointToUtf8Append(_ c: Char32, _ output: inout [UInt8]) {
    output.append(contentsOf: codepointToUtf8Bytes(c))
  }

  /// Converts a UCS4 code point to UTF8 bytes (the C++ buffer version without
  /// the terminating '\0'; its length is the C++ return value).
  public static func codepointToUtf8Bytes(_ c: Char32) -> [UInt8] {
    if c == 0 {
      // Do nothing if |c| is `\0`. Previous implementation of
      // CodepointToUtf8Append worked like this.
      return []
    }
    if c < 0x00080 {
      return [UInt8(c & 0xFF)]
    }
    if c < 0x00800 {
      return [UInt8(0xC0 + ((c >> 6) & 0x1F)), UInt8(0x80 + (c & 0x3F))]
    }
    if c < 0x10000 {
      return [
        UInt8(0xE0 + ((c >> 12) & 0x0F)), UInt8(0x80 + ((c >> 6) & 0x3F)),
        UInt8(0x80 + (c & 0x3F)),
      ]
    }
    if c < 0x200000 {
      return [
        UInt8(0xF0 + ((c >> 18) & 0x07)), UInt8(0x80 + ((c >> 12) & 0x3F)),
        UInt8(0x80 + ((c >> 6) & 0x3F)), UInt8(0x80 + (c & 0x3F)),
      ]
    }
    // below is not in UCS4 but in 32bit int.
    if c < 0x8000000 {
      return [
        UInt8(0xF8 + ((c >> 24) & 0x03)), UInt8(0x80 + ((c >> 18) & 0x3F)),
        UInt8(0x80 + ((c >> 12) & 0x3F)), UInt8(0x80 + ((c >> 6) & 0x3F)),
        UInt8(0x80 + (c & 0x3F)),
      ]
    }
    return [
      UInt8(truncatingIfNeeded: 0xFC + ((c >> 30) & 0x01)), UInt8(0x80 + ((c >> 24) & 0x3F)),
      UInt8(0x80 + ((c >> 18) & 0x3F)), UInt8(0x80 + ((c >> 12) & 0x3F)),
      UInt8(0x80 + ((c >> 6) & 0x3F)), UInt8(0x80 + (c & 0x3F)),
    ]
  }

  /// Returns (first_char32, rest) if |s| is split into |first_char32| + |rest|.
  /// Returns nil if an invalid UTF-8 sequence is prefixed. That is, |rest| may
  /// contain any invalid sequence even when this method succeeds.
  public static func splitFirstChar32<C: Collection>(_ s: C) -> (Char32, C.SubSequence)?
  where C.Element == UInt8 {
    guard let leadingByte = s.first else {
      return nil
    }

    var result: Char32 = 0
    var len = 0
    var minValue: Char32 = 0
    var maxValue: Char32 = 0xffff_ffff
    if leadingByte < 0x80 {
      return (Char32(leadingByte), s.dropFirst())
    }

    if isUtf8TrailingByte(leadingByte) {
      // UTF-8 sequence should not start trailing bytes.
      return nil
    }

    if (leadingByte & 0xe0) == 0xc0 {
      len = 2
      minValue = 0x0080
      maxValue = 0x07ff
      result = Char32(leadingByte & 0x1f)
    } else if (leadingByte & 0xf0) == 0xe0 {
      len = 3
      minValue = 0x0800
      maxValue = 0xffff
      result = Char32(leadingByte & 0x0f)
    } else if (leadingByte & 0xf8) == 0xf0 {
      len = 4
      minValue = 0x010000
      maxValue = 0x1fffff
      result = Char32(leadingByte & 0x07)
      // Below is out of UCS4 but acceptable in 32-bit.
    } else if (leadingByte & 0xfc) == 0xf8 {
      len = 5
      minValue = 0x0200000
      maxValue = 0x3ffffff
      result = Char32(leadingByte & 0x03)
    } else if (leadingByte & 0xfe) == 0xfc {
      len = 6
      minValue = 0x4000000
      maxValue = 0x7fff_ffff
      result = Char32(leadingByte & 0x01)
    } else {
      // Currently 0xFE and 0xFF are treated as invalid.
      return nil
    }

    if s.count < len {
      // Data length is too short.
      return nil
    }

    var it = s.index(after: s.startIndex)
    for _ in 1..<len {
      let c = s[it]
      if !isUtf8TrailingByte(c) {
        // Trailing bytes not found.
        return nil
      }
      result <<= 6
      result += Char32(c & 0x3f)
      s.formIndex(after: &it)
    }
    if result < minValue || maxValue < result {
      // redundant UTF-8 sequence found.
      return nil
    }
    return (result, s[it...])
  }

  /// String version of splitFirstChar32.
  public static func splitFirstChar32(_ s: some StringProtocol) -> (Char32, Substring)? {
    let sub = Strings.toSubstring(s)
    guard let (c, rest) = splitFirstChar32(sub.utf8) else { return nil }
    return (c, Substring(rest))
  }

  /// Returns (rest, last_char32) if |s| is split into |rest| + |last_char32|.
  /// Returns nil if an invalid UTF-8 sequence is suffixed.
  public static func splitLastChar32<C: BidirectionalCollection>(_ s: C) -> (C.SubSequence, Char32)?
  where C.Element == UInt8 {
    if s.isEmpty {
      return nil
    }
    var it = s.endIndex
    repeat {
      s.formIndex(before: &it)
    } while it != s.startIndex && isUtf8TrailingByte(s[it])
    if isUtf8TrailingByte(s[it]) {
      // All bytes are trailing bytes.
      return nil
    }
    let lastPiece = s[it...]
    guard let (c, resultPiece) = splitFirstChar32(lastPiece) else {
      return nil
    }
    if !resultPiece.isEmpty {
      return nil
    }
    return (s[..<it], c)
  }

  /// String version of splitLastChar32.
  public static func splitLastChar32(_ s: some StringProtocol) -> (Substring, Char32)? {
    let sub = Strings.toSubstring(s)
    guard let (rest, c) = splitLastChar32(sub.utf8) else { return nil }
    return (Substring(rest), c)
  }

  /// Returns true if |s| is a valid UTF8 (in the SplitFirstChar32 sense, which
  /// accepts surrogates and legacy 5/6-byte sequences).
  public static func isValidUtf8<C: Collection>(_ s: C) -> Bool where C.Element == UInt8 {
    var s = s[...]
    while !s.isEmpty {
      guard let (_, rest) = splitFirstChar32(s) else {
        return false
      }
      s = rest
    }
    return true
  }

  public static func isValidUtf8(_ s: some StringProtocol) -> Bool {
    isValidUtf8(s.utf8)
  }

  /// Extracts a substring range, where both start and length are in terms of
  /// UTF8 size. The returned substring refers to the same storage as the input.
  public static func utf8SubString(_ src: some StringProtocol, _ start: Int, _ length: Int)
    -> Substring
  {
    let sub = utf8SubString(src, start)
    let end =
      sub.unicodeScalars.index(sub.startIndex, offsetBy: length, limitedBy: sub.endIndex)
      ?? sub.endIndex
    return sub[..<end]
  }

  /// This version extracts the substring to the end.
  public static func utf8SubString(_ src: some StringProtocol, _ start: Int) -> Substring {
    let sub = Strings.toSubstring(src)
    let begin =
      sub.unicodeScalars.index(sub.startIndex, offsetBy: start, limitedBy: sub.endIndex)
      ?? sub.endIndex
    return sub[begin...]
  }

  /// Extracts a substring of length |length| starting at |start| into result.
  public static func utf8SubString(
    _ src: some StringProtocol, _ start: Int, _ length: Int, _ result: inout String
  ) {
    result = String(utf8SubString(src, start, length))
  }

  private static let kUtf8Bom: [UInt8] = [0xef, 0xbb, 0xbf]

  /// Strip a heading UTF-8 BOM (binary order mark) sequence (= \xef\xbb\xbf).
  public static func stripUtf8Bom<C: Collection>(_ line: C) -> C.SubSequence where C.Element == UInt8 {
    if line.starts(with: kUtf8Bom) {
      return line.dropFirst(3)
    }
    return line[...]
  }

  public static func stripUtf8Bom(_ line: some StringProtocol) -> Substring {
    let sub = Strings.toSubstring(line)
    if sub.utf8.starts(with: kUtf8Bom) {
      return sub.byteSubstring(from: 3)
    }
    return sub
  }

  /// return true the line starts with UTF16-LE/UTF16-BE BOM.
  public static func isUtf16Bom<C: Collection>(_ line: C) -> Bool where C.Element == UInt8 {
    line.starts(with: [0xff, 0xfe]) || line.starts(with: [0xfe, 0xff])
  }

  public static func isUtf16Bom(_ line: some StringProtocol) -> Bool {
    isUtf16Bom(line.utf8)
  }

  /// Chop the return characters (i.e. '\n' and '\r') at the end of the
  /// given line.
  public static func chopReturns(_ line: inout String) -> Bool {
    var count = line.utf8.count
    let original = count
    while count > 0 {
      let c = line.byte(at: count - 1)
      if c == 0x0D || c == 0x0A {
        count -= 1
      } else {
        break
      }
    }
    if count != original {
      line = String(line.byteSubstring(from: 0, length: count))
      return true
    }
    return false
  }

  // MARK: - Brackets

  // A sorted array of opening and closing brackets.
  // * Both `open` and `close` bracket must be sorted.
  // * Both `open` and `close` bracket must be the same size.
  // If you add a new bracket pair, you must keep this property.
  private static let kSortedBrackets: [String] = [
    "()",  // U+0028 U+0029
    "[]",  // U+005B U+005D
    "{}",  // U+007B U+007D
    "«»",  // U+00AB U+00BB
    "‘’",  // U+2018 U+2019
    "“”",  // U+201C U+201D
    "‹›",  // U+2039 U+203A
    "〈〉",  // U+3008 U+3009
    "《》",  // U+300A U+300B
    "「」",  // U+300C U+300D
    "『』",  // U+300E U+300F
    "【】",  // U+3010 U+3011
    "〔〕",  // U+3014 U+3015
    "〘〙",  // U+3018 U+3019
    "〚〛",  // U+301A U+301B
    "〝〟",  // U+301D U+301F
    "（）",  // U+FF08 U+FF09
    "［］",  // U+FF3B U+FF3D
    "｛｝",  // U+FF5B U+FF5D
    "｢｣",  // U+FF62 U+FF63
  ]

  private static func openBracket(_ pair: String) -> Substring {
    pair.byteSubstring(from: 0, length: pair.utf8.count / 2)
  }

  private static func closeBracket(_ pair: String) -> Substring {
    pair.byteSubstring(from: pair.utf8.count / 2)
  }

  /// std::lower_bound over `array` with the given "element < key" predicate.
  private static func lowerBound<T>(_ array: [T], _ less: (T) -> Bool) -> Int {
    var first = 0
    var count = array.count
    while count > 0 {
      let step = count / 2
      let it = first + step
      if less(array[it]) {
        first = it + 1
        count -= step + 1
      } else {
        count = step
      }
    }
    return first
  }

  /// Returns the corresponding close bracket if key is an open bracket.
  public static func isOpenBracket(_ key: some StringProtocol) -> Substring? {
    let iter = lowerBound(kSortedBrackets) { openBracket($0).bytesLess(key) }
    if iter == kSortedBrackets.count || !openBracket(kSortedBrackets[iter]).bytesEqual(key) {
      return nil
    }
    return closeBracket(kSortedBrackets[iter])
  }

  /// Returns the corresponding open bracket if key is a close bracket.
  public static func isCloseBracket(_ key: some StringProtocol) -> Substring? {
    let iter = lowerBound(kSortedBrackets) { closeBracket($0).bytesLess(key) }
    if iter == kSortedBrackets.count || !closeBracket(kSortedBrackets[iter]).bytesEqual(key) {
      return nil
    }
    return openBracket(kSortedBrackets[iter])
  }

  /// Returns true if input is a bracket pair text (e.g. "「」").
  public static func isBracketPairText(_ input: some StringProtocol) -> Bool {
    // The characters like ", ' <, > and ` are not always considered as
    // "brackets" themselves but they also have bracket-like usages by
    // doubling, or coupling with the corresponding characters. (e.g. "", '',
    // <>, ``) This function considers such character sequences as "bracket
    // pairs".
    let kAdditionalBracketPairs = ["\"\"", "''", "<>", "``"]  // sorted
    let iter0 = lowerBound(kAdditionalBracketPairs) { $0.bytesLess(input) }
    if iter0 != kAdditionalBracketPairs.count && kAdditionalBracketPairs[iter0].bytesEqual(input) {
      return true
    }

    let iter1 = lowerBound(kSortedBrackets) { $0.bytesLess(input) }
    if iter1 != kSortedBrackets.count && kSortedBrackets[iter1].bytesEqual(input) {
      return true
    }

    return false
  }

  // MARK: - Kana symbols

  /// Returns true if all chars in input are both defined
  /// in full width and half-width-katakana area
  public static func isFullWidthSymbolInHalfWidthKatakana(_ input: some StringProtocol) -> Bool {
    for scalar in input.unicodeScalars {
      switch scalar.value {
      case 0x3002,  // FULLSTOP "。"
        0x300C,  // LEFT CORNER BRACKET "「"
        0x300D,  // RIGHT CORNER BRACKET "」"
        0x3001,  // COMMA "、"
        0x30FB,  // MIDDLE DOT "・"
        0x30FC,  // SOUND_MARK "ー"
        0x3099,  // VOICE SOUND MARK "゙"
        0x309A:  // SEMI VOICE SOUND MARK "゚"
        break
      default:
        return false
      }
    }
    return true
  }

  /// Returns true if all chars are defined in half-width-katakana area.
  public static func isHalfWidthKatakanaSymbol(_ input: some StringProtocol) -> Bool {
    for scalar in input.unicodeScalars {
      switch scalar.value {
      case 0xFF61,  // FULLSTOP "｡"
        0xFF62,  // LEFT CORNER BRACKET "｢"
        0xFF63,  // RIGHT CORNER BRACKET "｣"
        0xFF64,  // COMMA "､"
        0xFF65,  // MIDDLE DOT "･"
        0xFF70,  // SOUND_MARK "ｰ"
        0xFF9E,  // VOICE SOUND MARK "ﾞ"
        0xFF9F:  // SEMI VOICE SOUND MARK "ﾟ"
        break
      default:
        return false
      }
    }
    return true
  }

  /// Returns true if one or more Kana-symbol characters are in the input.
  public static func isKanaSymbolContained(_ input: some StringProtocol) -> Bool {
    for scalar in input.unicodeScalars {
      switch scalar.value {
      case 0x3002, 0x300C, 0x300D, 0x3001, 0x30FB, 0x30FC, 0x3099, 0x309A,
        0xFF61, 0xFF62, 0xFF63, 0xFF64, 0xFF65, 0xFF70, 0xFF9E, 0xFF9F:
        return true
      default:
        break
      }
    }
    return false
  }

  /// Returns true if |input| looks like a pure English word.
  public static func isEnglishTransliteration(_ value: some StringProtocol) -> Bool {
    for c in value.utf8 {
      if c == 0x20 || c == 0x21 || c == 0x27 || c == 0x2D
        // " ", "!", "'", "-"
        || (c >= 0x41 && c <= 0x5A)  // A..Z
        || (c >= 0x61 && c <= 0x7A)  // a..z
      {
        // do nothing
      } else {
        return false
      }
    }
    return true
  }

  // MARK: - Script type

  public enum ScriptType: Int, Sendable, CaseIterable {
    case unknownScript = 0
    case katakana
    case hiragana
    case kanji
    case number
    case alphabet
    case emoji
    case scriptTypeSize
  }

  private static func inRange(_ w: Char32, _ a: Char32, _ b: Char32) -> Bool {
    w >= a && w <= b
  }

  // TODO(yukawa, team): Make a mechanism to keep this classifier up-to-date
  //   based on the original data from Unicode.org.
  /// Returns the script type of `codepoint`.
  public static func getScriptType(_ codepoint: Char32) -> ScriptType {
    if inRange(codepoint, 0x0030, 0x0039)  // ascii number
      || inRange(codepoint, 0xFF10, 0xFF19)  // full width number
    {
      return .number
    } else if inRange(codepoint, 0x0041, 0x005A)  // ascii upper
      || inRange(codepoint, 0x0061, 0x007A)  // ascii lower
      || inRange(codepoint, 0xFF21, 0xFF3A)  // fullwidth ascii upper
      || inRange(codepoint, 0xFF41, 0xFF5A)  // fullwidth ascii lower
    {
      return .alphabet
    } else if codepoint == 0x3005  // IDEOGRAPHIC ITERATION MARK "々"
      || inRange(codepoint, 0x3400, 0x4DBF)  // CJK Unified Ideographs Extension A
      || inRange(codepoint, 0x4E00, 0x9FFF)  // CJK Unified Ideographs
      || inRange(codepoint, 0xF900, 0xFAFF)  // CJK Compatibility Ideographs
      || inRange(codepoint, 0x20000, 0x2A6DF)  // CJK Unified Ideographs Extension B
      || inRange(codepoint, 0x2A700, 0x2B73F)  // CJK Unified Ideographs Extension C
      || inRange(codepoint, 0x2B740, 0x2B81F)  // CJK Unified Ideographs Extension D
      || inRange(codepoint, 0x2F800, 0x2FA1F)  // CJK Compatibility Ideographs
    {
      return .kanji
    } else if inRange(codepoint, 0x3041, 0x309F)  // hiragana
      || codepoint == 0x1B001  // HIRAGANA LETTER ARCHAIC YE
    {
      return .hiragana
    } else if inRange(codepoint, 0x30A1, 0x30FF)  // full width katakana
      || inRange(codepoint, 0x31F0, 0x31FF)  // Katakana Phonetic Extensions for Ainu
      || inRange(codepoint, 0xFF65, 0xFF9F)  // half width katakana
      || codepoint == 0x1B000  // KATAKANA LETTER ARCHAIC E
    {
      return .katakana
    } else if inRange(codepoint, 0x02300, 0x023F3)  // Miscellaneous Technical
      || inRange(codepoint, 0x02700, 0x027BF)  // Dingbats
      || inRange(codepoint, 0x1F000, 0x1F02F)  // Mahjong tiles
      || inRange(codepoint, 0x1F030, 0x1F09F)  // Domino tiles
      || inRange(codepoint, 0x1F0A0, 0x1F0FF)  // Playing cards
      || inRange(codepoint, 0x1F100, 0x1F2FF)  // Enclosed Alphanumeric Supplement
      || inRange(codepoint, 0x1F200, 0x1F2FF)  // Enclosed Ideographic Supplement
      || inRange(codepoint, 0x1F300, 0x1F5FF)  // Miscellaneous Symbols And Pictographs
      || inRange(codepoint, 0x1F600, 0x1F64F)  // Emoticons
      || inRange(codepoint, 0x1F680, 0x1F6FF)  // Transport And Map Symbols
      || inRange(codepoint, 0x1F700, 0x1F77F)  // Alchemical Symbols
      || codepoint == 0x26CE  // Ophiuchus
    {
      return .emoji
    }

    return .unknownScript
  }

  /// Returns the script type of the first character in `str`, and sets the
  /// UTF-8 byte size of the character to `mblen`.
  public static func getFirstScriptType(_ str: some StringProtocol, _ mblen: inout Int) -> ScriptType {
    guard let first = str.unicodeScalars.first else {
      mblen = 0
      return getScriptType(0)
    }
    mblen = first.utf8.count
    return getScriptType(first.value)
  }

  /// Returns the script type of the first character in `str`.
  public static func getFirstScriptType(_ str: some StringProtocol) -> ScriptType {
    var mblen = 0
    return getFirstScriptType(str, &mblen)
  }

  private static let kNumBs: UInt8 = 1 << UInt8(ScriptType.number.rawValue)
  private static let kKanaBs: UInt8 =
    (1 << UInt8(ScriptType.hiragana.rawValue)) | (1 << UInt8(ScriptType.katakana.rawValue))

  private static func getScriptTypeInternal(_ str: some StringProtocol, _ ignoreSymbols: Bool)
    -> ScriptType
  {
    // std::bitset<SCRIPT_TYPE_SIZE> bs(-1);
    var bs: UInt8 = (1 << UInt8(ScriptType.scriptTypeSize.rawValue)) - 1

    for scalar in str.unicodeScalars {
      let codepoint = scalar.value
      if bs == 0 {
        return .unknownScript
      }

      // PROLONGED SOUND MARK|MIDLE_DOT|VOICED_SOUND_MARKS
      // are HIRAGANA or KATAKANA as well.
      if codepoint == 0x30FC || codepoint == 0x30FB || (codepoint >= 0x3099 && codepoint <= 0x309C) {
        bs &= kKanaBs
        continue
      }

      // Periods ('．' U+FF0E and '.' U+002E) are NUMBER as well, if they are
      // not the first character.
      if (codepoint == 0xFF0E || codepoint == 0x2E) && bs == kNumBs {
        continue
      }

      let type = getScriptType(codepoint)
      // Ignore symbols
      // Regard UNKNOWN_SCRIPT as symbols here
      if ignoreSymbols && type == .unknownScript {
        continue
      }

      bs &= 1 << UInt8(type.rawValue)
    }

    if bs.nonzeroBitCount != 1 {
      return .unknownScript
    }

    return ScriptType(rawValue: bs.trailingZeroBitCount) ?? .unknownScript
  }

  /// Returns the script type of a string. All chars in str must be
  /// KATAKANA/HIRAGANA/KANJI/NUMBER or ALPHABET.
  /// If str has mixed scripts, this function returns UNKNOWN_SCRIPT
  public static func getScriptType(_ str: some StringProtocol) -> ScriptType {
    getScriptTypeInternal(str, false)
  }

  /// The same as GetScryptType(), but it ignores symbols in the |str|.
  public static func getScriptTypeWithoutSymbols(_ str: some StringProtocol) -> ScriptType {
    getScriptTypeInternal(str, true)
  }

  /// Returns true if all script_type in str is "type"
  public static func isScriptType(_ str: some StringProtocol, _ type: ScriptType) -> Bool {
    for scalar in str.unicodeScalars {
      let codepoint = scalar.value
      // Exception: 30FC (PROLONGEDSOUND MARK is categorized as HIRAGANA as well)
      if type != getScriptType(codepoint) && (codepoint != 0x30FC || type != .hiragana) {
        return false
      }
    }
    return true
  }

  /// Returns true if the string contains script_type char
  public static func containsScriptType(_ str: some StringProtocol, _ type: ScriptType) -> Bool {
    for scalar in str.unicodeScalars where type == getScriptType(scalar.value) {
      return true
    }
    return false
  }

  // MARK: - Form type

  /// See 'Unicode Standard Annex #11: EAST ASIAN WIDTH'
  /// http://www.unicode.org/reports/tr11/
  /// http://www.unicode.org/Public/UNIDATA/EastAsianWidth.txt
  public enum FormType: Int, Sendable {
    case unknownForm = 0
    case halfWidth  // [Na] and [H] in 'Unicode Standard Annex #11'
    case fullWidth  // Any other characters
    case formTypeSize
  }

  /// Returns Form type of single character.
  /// This function never returns UNKNOWN_FORM.
  public static func getFormType(_ codepoint: Char32) -> FormType {
    // 'Unicode Standard Annex #11: EAST ASIAN WIDTH'
    // http://www.unicode.org/reports/tr11/

    // Characters marked as 'Na' in
    // http://www.unicode.org/Public/UNIDATA/EastAsianWidth.txt
    if inRange(codepoint, 0x0020, 0x007F)  // ascii
      || inRange(codepoint, 0x27E6, 0x27ED)  // narrow mathematical symbols
      || inRange(codepoint, 0x2985, 0x2986)  // narrow white parentheses
    {
      return .halfWidth
    }

    // Other characters marked as 'Na' in
    // http://www.unicode.org/Public/UNIDATA/EastAsianWidth.txt
    if inRange(codepoint, 0x00A2, 0x00AF) {
      switch codepoint {
      case 0x00A2,  // CENT SIGN
        0x00A3,  // POUND SIGN
        0x00A5,  // YEN SIGN
        0x00A6,  // BROKEN BAR
        0x00AC,  // NOT SIGN
        0x00AF:  // MACRON
        return .halfWidth
      default:
        break
      }
    }

    // Characters marked as 'H' in
    // http://www.unicode.org/Public/UNIDATA/EastAsianWidth.txt
    if codepoint == 0x20A9  // WON SIGN
      || inRange(codepoint, 0xFF61, 0xFF9F)  // half-width katakana
      || inRange(codepoint, 0xFFA0, 0xFFBE)  // half-width hangul
      || inRange(codepoint, 0xFFC2, 0xFFCF)  // half-width hangul
      || inRange(codepoint, 0xFFD2, 0xFFD7)  // half-width hangul
      || inRange(codepoint, 0xFFDA, 0xFFDC)  // half-width hangul
      || inRange(codepoint, 0xFFE8, 0xFFEE)  // half-width symbols
    {
      return .halfWidth
    }

    return .fullWidth
  }

  /// Returns FormType of string.
  /// Returns UNKNOWN_FORM if |str| contains both HALF_WIDTH and FULL_WIDTH.
  public static func getFormType(_ str: some StringProtocol) -> FormType {
    // TODO(hidehiko): get rid of using FORM_TYPE_SIZE.
    var result = FormType.formTypeSize

    for scalar in str.unicodeScalars {
      let type = getFormType(scalar.value)
      if type == .unknownForm || (result != .formTypeSize && type != result) {
        return .unknownForm
      }
      result = type
    }

    return result
  }

  /// Returns true if all characters of `str` are ASCII (U+00 - U+7F).
  public static func isAscii(_ str: some StringProtocol) -> Bool {
    str.utf8.allSatisfy { $0 < 0x80 }
  }

  public static func isAscii<C: Collection>(_ bytes: C) -> Bool where C.Element == UInt8 {
    bytes.allSatisfy { $0 < 0x80 }
  }

  // MARK: - Serialization

  // CAUTION: Be careful to change the implementation of serialization.  Some
  // files use this format, so compatibility can be lost.  See, e.g.,
  // data_manager/dataset_writer.cc.
  /// Serializes uint64_t into eight bytes (big endian).
  public static func serializeUint64(_ x: UInt64) -> [UInt8] {
    [
      UInt8(x >> 56), UInt8((x >> 48) & 0xFF), UInt8((x >> 40) & 0xFF), UInt8((x >> 32) & 0xFF),
      UInt8((x >> 24) & 0xFF), UInt8((x >> 16) & 0xFF), UInt8((x >> 8) & 0xFF), UInt8(x & 0xFF),
    ]
  }

  /// Deserializes bytes serialized by SerializeUint64.  Returns nil if the
  /// length of s is not eight.
  public static func deserializeUint64<C: Collection>(_ s: C) -> UInt64? where C.Element == UInt8 {
    if s.count != 8 {
      return nil
    }
    var x: UInt64 = 0
    for c in s {
      x = (x << 8) | UInt64(c)
    }
    return x
  }

  /// Checks whether the letter is ucs 4 is appropriate target to be shown as
  /// candidate. This function is based on mozc internal logics, rather than
  /// orthodox classification logics.
  public static func isAcceptableCharacterAsCandidate(_ letter: Char32) -> Bool {
    // Unicode does not have code point larger than 0x10FFFF.
    if letter > 0x10FFFF {
      return false
    }

    // Control characters are not acceptable.  0x7F is DEL.
    if letter < 0x20 || (0x7F <= letter && letter <= 0x9F) {
      return false
    }

    // Bidirectional text control are not acceptable.
    // See: https://en.wikipedia.org/wiki/Bidirectional_text
    // Note: Bidirectional text controls can be allowed, as it can be contained
    // in some emoticons. If they are found not to be harmful for the system,
    // this section of validation can be abolished.
    if letter == 0x061C || letter == 0x200E || letter == 0x200F
      || (0x202A <= letter && letter <= 0x202E) || (0x2066 <= letter && letter <= 0x2069)
    {
      return false
    }
    return true
  }
}

// MARK: - ConstChar32Iterator

/// Const iterator implementation to traverse on a (utf8) string as a char32
/// string.
///
/// Example usage:
///   var iter = ConstChar32Iterator(utf8)
///   while !iter.done { let c = iter.get(); ...; iter.next() }
///
/// It is also a Swift `Sequence` of `Char32`. Iteration stops at the first
/// ill-formed sequence (never happens for a Swift string).
public struct ConstChar32Iterator: Sequence, IteratorProtocol {
  private var utf8String: Substring
  private var current: Char32 = 0
  public private(set) var done = false

  public init(_ utf8String: some StringProtocol) {
    self.utf8String = Strings.toSubstring(utf8String)
    advance()
  }

  public func get() -> Char32 {
    precondition(!done)
    return current
  }

  public mutating func advance() {
    if !done {
      if let (c, rest) = Util.splitFirstChar32(utf8String) {
        current = c
        utf8String = rest
      } else {
        done = true
      }
    }
  }

  /// IteratorProtocol: returns the current character and advances.
  public mutating func next() -> Char32? {
    if done { return nil }
    let c = current
    advance()
    return c
  }
}

/// Const reverse iterator implementation to traverse on a (utf8) string as a
/// char32_t string.
public struct ConstChar32ReverseIterator: Sequence, IteratorProtocol {
  private var utf8String: Substring
  private var current: Char32 = 0
  public private(set) var done = false

  public init(_ utf8String: some StringProtocol) {
    self.utf8String = Strings.toSubstring(utf8String)
    advance()
  }

  public func get() -> Char32 {
    precondition(!done)
    return current
  }

  public mutating func advance() {
    if !done {
      if let (rest, c) = Util.splitLastChar32(utf8String) {
        current = c
        utf8String = rest
      } else {
        done = true
      }
    }
  }

  public mutating func next() -> Char32? {
    if done { return nil }
    let c = current
    advance()
    return c
  }
}
