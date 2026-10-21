// Port of mozc/src/dictionary/text_dictionary_loader.{h,cc} (3.35.6354).
//
// NOTE(tabata): This code is used mainly by louds trie builder to build
// dictionary. Please check error handling, if you want to include
// this to run within client.

import GenmaiBase

/// `mozc::dictionary::TextDictionaryLoader`.
///
/// Deviation: tokens are values (`[Token]`) instead of
/// `std::vector<std::unique_ptr<Token>>`; `collectTokens` appends copies.
open class TextDictionaryLoader {
  /// `--tokens_reserve_size` flag: reserve the specified size of token buffer
  /// in advance.
  public nonisolated(unsafe) static var tokensReserveSize = 1_400_000

  private let zipcodeId: UInt16
  private let isolatedWordId: UInt16
  public private(set) var tokens: [Token] = []

  // TODO(noriyukit): Better to pass the pointer of pos_matcher.
  public init(_ posMatcher: PosMatcher) {
    zipcodeId = posMatcher.getZipcodeId()
    isolatedWordId = posMatcher.getIsolatedWordId()
  }

  public init(_ zipcodeId: UInt16, _ isolatedWordId: UInt16) {
    self.zipcodeId = zipcodeId
    self.isolatedWordId = isolatedWordId
  }

  /// Loads tokens from system dictionary files and reading correction
  /// files. Each file name can take multiple file names by separating commas.
  /// The reading correction file is optional and can be an empty string.  Note
  /// that the tokens loaded so far are all cleared.
  public func load(_ dictionaryFilename: String, _ readingCorrectionFilename: String) {
    loadWithLineLimit(dictionaryFilename, readingCorrectionFilename, -1)
  }

  /// The same as load() method above except that the number of tokens to be
  /// loaded is limited up to first `limit` entries.
  public func loadWithLineLimit(
    _ dictionaryFilename: String, _ readingCorrectionFilename: String, _ limitArg: Int
  ) {
    var limit = limitArg
    tokens.removeAll()

    // Roughly allocate buffers for Token pointers.
    if limit < 0 {
      tokens.reserveCapacity(Self.tokensReserveSize)
      limit = Int(Int32.max)
    } else {
      tokens.reserveCapacity(limit)
    }

    // Read system dictionary.
    do {
      let file = InputMultiFile(dictionaryFilename)
      while limit > 0, var line = file.readLine() {
        _ = Util.chopReturns(&line)
        if let token = parseTSVLine(line) {
          tokens.append(token)
          limit -= 1
        }
      }
      GenmaiLog.info("\(tokens.count) tokens from \(dictionaryFilename)")
    }

    if readingCorrectionFilename.isEmpty || limit <= 0 {
      return
    }

    // Prepare for loading reading corrections. We sort `tokens` first by value
    // and then by key so that we can perform the following operations both in
    // O(log(N)), where N is the size of tokens.
    //   1. Checking the existence of any key-value pairs: This can be done by
    //      binary-searching for a pair of value and key.
    //   2. Accessing all the tokens that have the same value: Since tokens are
    //      also sorted in order of value, this can be done by finding a range of
    //      tokens that have the same value.
    // std::stable_sort with OrderByValueThenByKey.
    let order = tokens.indices.sorted { l, r in
      let c = Self.compareValueAndKey(tokens[l], tokens[r].value, tokens[r].key)
      if c != 0 { return c < 0 }
      return l < r
    }
    tokens = order.map { tokens[$0] }
    let readingCorrectionTokens = Self.loadReadingCorrectionTokens(
      readingCorrectionFilename, tokens, &limit)
    tokens.append(contentsOf: readingCorrectionTokens)
  }

  /// Clears the loaded tokens.
  public func clear() { tokens.removeAll() }

  public func addToken(_ token: Token) {
    tokens.append(token)
  }

  /// Appends the tokens of this instance to `res`.
  public func collectTokens(_ res: inout [Token]) {
    res.reserveCapacity(res.count + tokens.count)
    res.append(contentsOf: tokens)
  }

  // ToValueAndKey(token) <=> (value, key), bytewise.
  private static func compareValueAndKey(_ token: Token, _ value: String, _ key: String) -> Int {
    let c = token.value.compareBytes(value)
    if c != 0 { return c }
    return token.key.compareBytes(key)
  }

  /// Loads reading correction data.  The second argument is used to
  /// determine costs of reading correction tokens and must be sorted by
  /// OrderByValueThenByKey().
  static func loadReadingCorrectionTokens(
    _ readingCorrectionFilename: String, _ refSortedTokens: [Token], _ limit: inout Int
  ) -> [Token] {
    // Load reading correction entries.
    var tokens: [Token] = []
    var readingCorrectionSize = 0

    let file = InputMultiFile(readingCorrectionFilename)
    while var line = file.readLine() {
      if line.isEmpty || line.utf8.first == UInt8(ascii: "#") {
        continue
      }

      // Parse TSV line in a pair of value and key (Note: first element is value
      // and the second key).
      _ = Util.chopReturns(&line)
      // Format: value\terror\tcorrect
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
      precondition(fields.count >= 2)
      let value = String(fields[0])
      let key = String(fields[1])

      // Filter the entry if this key value pair already exists in the system
      // dictionary.
      // std::binary_search with OrderByValueThenByKey.
      let lb = lowerBound(refSortedTokens) { compareValueAndKey($0, value, key) < 0 }
      if lb < refSortedTokens.count && compareValueAndKey(refSortedTokens[lb], value, key) == 0 {
        continue
      }

      // Since reading correction entries lack POS and cost, we recover those
      // fields from a token in the system dictionary that has the same value.
      // Since multiple tokens may have the same value, from such tokens, we
      // select the one that has the maximum cost.
      // std::equal_range with OrderByValue.
      var begin = lowerBound(refSortedTokens) { $0.value.compareBytes(value) < 0 }
      let end = lowerBound(refSortedTokens) { !(value.compareBytes($0.value) < 0) }
      if begin == end {
        continue
      }

      // Now [begin, end) contains all the tokens that have the same value as
      // this reading correction entry.  Next, find the token that has the
      // maximum cost in [begin, end).  Note that linear search is sufficiently
      // fast here because the size of the range is small.
      var maxCostToken = refSortedTokens[begin]
      begin += 1
      while begin != end {
        if refSortedTokens[begin].cost > maxCostToken.cost {
          maxCostToken = refSortedTokens[begin]
        }
        begin += 1
      }

      // The cost is calculated as -log(prob) * 500.
      // We here assume that the wrong reading appear with 1/100 probability
      // of the original (correct) reading.
      let kCostPenalty = 2302  // -log(1/100) * 500;
      var token = Token()
      token.key = key
      token.value = maxCostToken.value
      token.lid = maxCostToken.lid
      token.rid = maxCostToken.rid
      token.cost = maxCostToken.cost + kCostPenalty
      // We don't set SPELLING_CORRECTION. The entries in reading_correction
      // data are also stored in rewriter/correction_rewriter.cc.
      // reading_correction_rewriter annotates the spelling correction
      // notations.
      token.attributes = Token.Attribute.none
      tokens.append(token)
      readingCorrectionSize += 1
      limit -= 1
      if limit <= 0 {
        break
      }
    }
    GenmaiLog.info("\(readingCorrectionSize) tokens from \(readingCorrectionFilename)")
    return tokens
  }

  // Index of the first element for which `isLess` is false (partitioned).
  private static func lowerBound(_ tokens: [Token], _ isLess: (Token) -> Bool) -> Int {
    var lo = 0
    var n = tokens.count
    while n > 0 {
      let half = n / 2
      if isLess(tokens[lo + half]) {
        lo += half + 1
        n -= half + 1
      } else {
        n = half
      }
    }
    return lo
  }

  /// Encodes special information into `token` with the `label`.
  /// Currently, label must be:
  ///   - empty string,
  ///   - "SPELLING_CORRECITON",
  ///   - "ZIP_CODE", or
  ///   - "ENGLISH".
  /// Otherwise, the method returns false.
  func rewriteSpecialToken(_ token: inout Token, _ label: some StringProtocol) -> Bool {
    if label.isEmpty {
      return true
    }
    if label.hasBytePrefix("SPELLING_CORRECTION") {
      token.attributes = Token.Attribute.spellingCorrection
      return true
    }
    if label.hasBytePrefix("ZIP_CODE") {
      token.lid = zipcodeId
      token.rid = zipcodeId
      return true
    }
    if label.hasBytePrefix("ENGLISH") {
      // TODO(noriyukit): Might be better to use special POS for english words.
      token.lid = isolatedWordId
      token.rid = isolatedWordId
      return true
    }
    GenmaiLog.error("Unknown special label: \(label)")
    return false
  }

  func parseTSVLine(_ line: String) -> Token? {
    // absl::StrSplit(line, '\t', absl::SkipEmpty())
    let columns = line.split(separator: "\t", omittingEmptySubsequences: true)
    return parseTSV(columns)
  }

  func parseTSV(_ columns: [Substring]) -> Token? {
    precondition(columns.count >= 5, "Lack of columns: \(columns.count)")
    var token = Token()

    // Parse key, lid, rid, cost, value.
    token.key = Japanese.normalizeVoicedSoundMark(columns[0])
    guard let lid = Self.simpleAtoi(columns[1], as: UInt16.self) else {
      preconditionFailure("Wrong lid: \(columns[1])")
    }
    token.lid = lid
    guard let rid = Self.simpleAtoi(columns[2], as: UInt16.self) else {
      preconditionFailure("Wrong rid: \(columns[2])")
    }
    token.rid = rid
    guard let cost = Self.simpleAtoi(columns[3], as: Int32.self) else {
      preconditionFailure("Wrong cost: \(columns[3])")
    }
    token.cost = Int(cost)
    token.value = Japanese.normalizeVoicedSoundMark(columns[4])

    // Optionally, label (SPELLING_CORRECTION, ZIP_CODE, etc.) may be provided in
    // column 6.
    if columns.count > 5 {
      precondition(rewriteSpecialToken(&token, columns[5]), "Invalid label: \(columns[5])")
    }
    return token
  }

  /// absl::SimpleAtoi: optional surrounding ASCII whitespace, optional sign,
  /// decimal digits; fails on overflow.
  static func simpleAtoi<T: FixedWidthInteger>(_ s: some StringProtocol, as: T.Type) -> T? {
    var bytes = Array(s.utf8)[...]
    func isSpace(_ b: UInt8) -> Bool {
      b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0B || b == 0x0C || b == 0x0D
    }
    while let f = bytes.first, isSpace(f) { bytes = bytes.dropFirst() }
    while let l = bytes.last, isSpace(l) { bytes = bytes.dropLast() }
    var negative = false
    if let f = bytes.first, f == UInt8(ascii: "+") || f == UInt8(ascii: "-") {
      negative = f == UInt8(ascii: "-")
      bytes = bytes.dropFirst()
    }
    if bytes.isEmpty { return nil }
    var value: T = 0
    for b in bytes {
      guard b >= 0x30 && b <= 0x39 else { return nil }
      let d = T(b - 0x30)
      let (m, o1) = value.multipliedReportingOverflow(by: 10)
      if o1 { return nil }
      let (r, o2) = negative ? m.subtractingReportingOverflow(d) : m.addingReportingOverflow(d)
      if o2 { return nil }
      value = r
    }
    return value
  }
}
