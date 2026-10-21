// Port of mozc/src/prediction/number_decoder.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - `number_decoder_internal::{Type, Entry, State}` are nested in
//   `NumberDecoderInternal`.
// - `State.consumed_keys` holds copies of the consumed key strings.
// - The default entries are a lazily created shared Trie (the C++
//   NoDestructor singleton); the Trie is only read after creation.

import GenmaiBase

public enum NumberDecoderInternal {
  public enum EntryType: UInt8, Sendable {
    case stopDecoding  // "にん", "せんち", ...
    case unit  // 0-9
    case smallDigit  // 10, 100, 1000
    case bigDigit  // 万, 億, ...
    // Special type for "にちょう"
    // We do not parse it as "にち"+"ょう" by the longest match
    case unitAndBigDigit
    // Special type for "にちょうめ"
    // We do not parse it as "にちょう"+"め" by the longest match
    case unitAndStopDecoding
  }

  public struct Entry: Sendable {
    public var type: EntryType = .stopDecoding
    public var number = 0
    public var digit = 1
    public var digitStr = ""
    // Output the current status before decoding the input with the entry.
    public var outputBeforeDecode = false
    // For UNIT_AND_BIG_DIGIT and UNIT_AND_STOP_DECODING.
    // The key length for the first part.
    public var consumeByteLenOfFirst = 0

    public init(
      _ type: EntryType = .stopDecoding, _ number: Int = 0, _ digit: Int = 1,
      _ digitStr: String = "", _ outputBeforeDecode: Bool = false,
      _ consumeByteLenOfFirst: Int = 0
    ) {
      self.type = type
      self.number = number
      self.digit = digit
      self.digitStr = digitStr
      self.outputBeforeDecode = outputBeforeDecode
      self.consumeByteLenOfFirst = consumeByteLenOfFirst
    }
  }

  // We decode the Japanese number reading using big_digit and small_digit.
  // Big digit stands for the number digit for 10^4N, e.g. "万", "億", "兆", ...
  // Small digit stands for the digit, 1, 10, 100, 1000.
  //
  // |small_digit| and |big_digit| will be used to validate the current state.
  // For example, we do not decode "兆" after decoding "万".
  public struct State: Sendable {
    public func isValid() -> Bool {
      !(smallDigitNum == -1 && smallDigit == -1 && bigDigit == -1)
    }

    public func result() -> NumberDecoderResult? {
      if !isValid() {
        return nil
      }

      let smallDigitValue = max(smallDigitNum, 0)

      if smallDigitValue > 0 {
        // "1万" + "2000"
        return NumberDecoderResult(
          consumedKeyByteLen, currentNumStr + String(smallDigitValue), digitNum)
      } else if !currentNumStr.isEmpty {
        // "1万"
        return NumberDecoderResult(consumedKeyByteLen, currentNumStr, digitNum)
      } else if smallDigitValue == 0 {
        // "0"
        return NumberDecoderResult(consumedKeyByteLen, "0", 1)
      }
      return nil
    }

    public var debugString: String {
      "small_digit_num: \(smallDigitNum), num_str: \(currentNumStr), sd: \(smallDigit), "
        + "bd: \(bigDigit), consumed_blen: \(consumedKeyByteLen)"
    }

    // Current number in string (e.g. 46億, 2億6000万)
    public var currentNumStr = ""

    // Key to decode
    public var key = ""

    // Consumed keys
    // ["に", "じゅう"] for "にじゅう": "20"
    public var consumedKeys: [String] = []

    // Current small digit number in integer (e.g. 2000, <= 9999)
    public var smallDigitNum = -1
    // The current index for the small digit ('digit' in NumberDecoderEntry).
    // e.g. (small_digit_number : digit index) = (1:1), (10:2), (100:3),
    // (1000:4)
    public var smallDigit = -1
    // The current index for the big digit
    // e.g. (digit_str : digit index) = ("万":1), ("億", 2), ...
    public var bigDigit = -1
    // The digit number
    // 12万(=120000) → 6
    public var digitNum = 0
    public var consumedKeyByteLen: UInt32 = 0

    public init() {}
  }
}

public struct NumberDecoderResult: Sendable, Equatable, CustomStringConvertible {
  public var candidate = ""
  public var consumedKeyByteLen: UInt32 = 0
  public var digitNum = 0  // 12万(=120000) → 6

  public init() {}

  public init(_ len: UInt32, _ c: String, _ digitNum: Int) {
    candidate = c
    consumedKeyByteLen = len
    self.digitNum = digitNum
  }

  public var description: String { "(\(consumedKeyByteLen),\" \(candidate)\", \(digitNum))" }

  public static func == (lhs: NumberDecoderResult, rhs: NumberDecoderResult) -> Bool {
    lhs.consumedKeyByteLen == rhs.consumedKeyByteLen && lhs.candidate.bytesEqual(rhs.candidate)
      && lhs.digitNum == rhs.digitNum
  }
}

/// `@unchecked Sendable`: the shared entries are immutable after creation.
public final class NumberDecoder: @unchecked Sendable {
  private typealias Entry = NumberDecoderInternal.Entry
  private typealias State = NumberDecoderInternal.State

  private final class EntriesBox: @unchecked Sendable {
    let trie: Trie<NumberDecoderInternal.Entry>
    init(_ trie: Trie<NumberDecoderInternal.Entry>) { self.trie = trie }
  }

  // Returns a singleton enries.
  private static let defaultEntries = EntriesBox(createDefaultEntries())

  private let entries: Trie<NumberDecoderInternal.Entry>
  private let kanjiNumberId: UInt16
  private let numberId: UInt16

  public init(_ posMatcher: PosMatcher) {
    entries = Self.defaultEntries.trie
    kanjiNumberId = posMatcher.getKanjiNumberId()
    numberId = posMatcher.getNumberId()
  }

  private static func createDefaultEntries() -> Trie<NumberDecoderInternal.Entry> {
    let result = Trie<Entry>()
    // unit
    result.addEntry("ぜろ", Entry(.unit, 0))
    result.addEntry("いち", Entry(.unit, 1))
    result.addEntry("いっ", Entry(.unit, 1))
    result.addEntry("に", Entry(.unit, 2))
    result.addEntry("さん", Entry(.unit, 3))
    result.addEntry("し", Entry(.unit, 4))
    result.addEntry("よん", Entry(.unit, 4))
    result.addEntry("よ", Entry(.unit, 4))
    result.addEntry("ご", Entry(.unit, 5))
    result.addEntry("ろく", Entry(.unit, 6))
    result.addEntry("ろっ", Entry(.unit, 6))
    result.addEntry("なな", Entry(.unit, 7))
    result.addEntry("しち", Entry(.unit, 7))
    result.addEntry("はち", Entry(.unit, 8))
    result.addEntry("はっ", Entry(.unit, 8))
    result.addEntry("きゅう", Entry(.unit, 9))
    result.addEntry("きゅー", Entry(.unit, 9))
    result.addEntry("く", Entry(.unit, 9))

    // small digit
    // "重", etc
    result.addEntry("じゅう", Entry(.smallDigit, 10, 2, "", true))
    result.addEntry("じゅー", Entry(.smallDigit, 10, 2, "", true))
    result.addEntry("じゅっ", Entry(.smallDigit, 10, 2))
    result.addEntry("ひゃく", Entry(.smallDigit, 100, 3))
    result.addEntry("ひゃっ", Entry(.smallDigit, 100, 3))
    result.addEntry("びゃく", Entry(.smallDigit, 100, 3))
    result.addEntry("びゃっ", Entry(.smallDigit, 100, 3))
    result.addEntry("ぴゃく", Entry(.smallDigit, 100, 3))
    result.addEntry("ぴゃっ", Entry(.smallDigit, 100, 3))
    // "戦", etc
    result.addEntry("せん", Entry(.smallDigit, 1000, 4, "", true))
    // "膳"
    result.addEntry("ぜん", Entry(.smallDigit, 1000, 4, "", true))

    // big digit
    result.addEntry("まん", Entry(.bigDigit, 10000, 5, "万"))
    result.addEntry("おく", Entry(.bigDigit, -1, 9, "億"))
    result.addEntry("おっ", Entry(.bigDigit, -1, 9, "億"))
    // "町", etc
    result.addEntry("ちょう", Entry(.bigDigit, -1, 13, "兆", true))
    // "系", etc
    result.addEntry("けい", Entry(.bigDigit, -1, 17, "京", true))
    result.addEntry("がい", Entry(.bigDigit, -1, 21, "垓"))

    // spacial cases
    // conflict with "にち"
    result.addEntry("にちょう", Entry(.unitAndBigDigit, 2, 13, "兆", true, 3))
    result.addEntry("にちょうめ", Entry(.unitAndStopDecoding, 2, -1, "", false, 3))
    result.addEntry("にちゃん", Entry(.unitAndStopDecoding, 2, -1, "", false, 3))
    // サンチーム (currency) v.s. 3チーム
    result.addEntry("さんちーむ", Entry(.unitAndStopDecoding, 3, -1, "", true, 6))

    // number suffix conflicting with the other entries
    let kSuffixEntries = [
      // に
      // 握り, 日, 人
      "にぎり",
      "にち",
      "にん",
      // し
      // cc, シート, シーベルト (unit), 試合, 式, 室, 品, 社, 尺, 種, 周, 勝, 色
      // シリング, 進, シンガポールドル
      "しーしー",
      "しーと",
      "しーべると",
      "しあい",
      "しき",
      "しつ",
      "しな",
      "しゃ",
      "しゅ",
      "しょう",
      "しょく",
      "しりんぐ",
      "しん",
      // よ
      // 葉
      "よう",
      // ご
      // 号
      "ごう",
      // く
      // 口, 組, クラス, クローナ
      "くだり",
      "くち",
      "くみ",
      "くらす",
      "くろーな",
      // せん
      // センチ, セント
      "せんち",
      "せんと",
      // おく
      // オクターブ
      "おくたーぶ",
      // ちょう
      // 丁目
      "ちょうめ",
    ]
    for key in kSuffixEntries {
      result.addEntry(key, Entry())
    }
    return result
  }

  private static func maybeAppendResult(_ state: State, _ results: inout [NumberDecoderResult]) {
    guard let result = state.result() else {
      return
    }

    // Filter out invalid number sequences.
    var keys = state.consumedKeys
    if Int(state.consumedKeyByteLen) < state.key.utf8.count {
      keys.append(String(state.key.byteSubstring(from: Int(state.consumedKeyByteLen))))
    }
    for i in 0..<keys.count {
      let k = keys[i]
      if (k.bytesEqual("よ") || k.bytesEqual("く")) && i + 1 < keys.count {
        // Other than the tail of the sequence is invalid
        return
      }
      if k.bytesEqual("し") && !(i + 1 == keys.count || keys[i + 1].bytesEqual("じゅう")) {
        // Valid: "し:4", "じゅうし:4", "しじゅう:4"
        // Invalid: "しひゃく", "しせん", etc
        return
      }
    }
    results.append(result)
  }

  public func decode(_ request: ConversionRequest) -> [PredictionResult] {
    var results: [PredictionResult] = []
    let requestKey = request.key()

    for decodeResult in decode(requestKey) {
      var result = PredictionResult()
      let isArabic = Util.getScriptType(decodeResult.candidate) == .number
      result.key = String(
        requestKey.byteSubstring(from: 0, length: Int(decodeResult.consumedKeyByteLen)))
      result.value = decodeResult.candidate
      result.attributes |= Attribute.number
      result.attributes |= Attribute.noSuggestLearning
      // Heuristic cost:
      // Large digit number (1億, 1兆, etc) should have larger cost
      // 1000 ~= 500 * log(10)
      result.wcost = 1000 * (1 + decodeResult.digitNum)
      result.lid = isArabic ? numberId : kanjiNumberId
      result.rid = isArabic ? numberId : kanjiNumberId
      if Int(decodeResult.consumedKeyByteLen) < requestKey.utf8.count {
        result.attributes |= Attribute.partiallyKeyConsumed
        result.consumedKeySize = UInt32(Util.charsLen(result.key))
      }
      results.append(result)
    }

    return results
  }

  public func decode(_ key: String) -> [NumberDecoderResult] {
    var state = State()
    state.key = key
    var results: [NumberDecoderResult] = []
    decodeAux(Substring(key), &state, &results)

    Self.maybeAppendResult(state, &results)
    return results
  }

  private func decodeAux(
    _ key: Substring, _ state: inout State, _ results: inout [NumberDecoderResult]
  ) {
    if key.isEmpty {
      return
    }
    var keyByteLen = 0
    var found: Entry?
    if !entries.longestMatch(key, &found, &keyByteLen) {
      return
    }
    let e = found ?? Entry()
    let k = key.byteSubstring(from: 0, length: keyByteLen)
    switch e.type {
    case .stopDecoding:
      return
    case .unit:
      if !handleUnitEntry(k, e, &state, &results) {
        return
      }
      state.consumedKeyByteLen += UInt32(keyByteLen)
    case .smallDigit:
      if !handleSmallDigitEntry(k, e, &state, &results) {
        return
      }
      state.consumedKeyByteLen += UInt32(keyByteLen)
    case .bigDigit:
      if !handleBigDigitEntry(k, e, &state, &results) {
        return
      }
      state.consumedKeyByteLen += UInt32(keyByteLen)
    case .unitAndBigDigit:
      let unitKey = key.byteSubstring(from: 0, length: e.consumeByteLenOfFirst)
      if !handleUnitEntry(unitKey, e, &state, &results) {
        return
      }
      state.consumedKeyByteLen += UInt32(e.consumeByteLenOfFirst)
      let digitKey = key.byteSubstring(
        from: e.consumeByteLenOfFirst, length: keyByteLen - e.consumeByteLenOfFirst)
      if !handleBigDigitEntry(digitKey, e, &state, &results) {
        return
      }
      state.consumedKeyByteLen += UInt32(keyByteLen - e.consumeByteLenOfFirst)
    case .unitAndStopDecoding:
      let unitKey = key.byteSubstring(from: 0, length: e.consumeByteLenOfFirst)
      if !handleUnitEntry(unitKey, e, &state, &results) {
        return
      }
      state.consumedKeyByteLen += UInt32(e.consumeByteLenOfFirst)
      return
    }
    assert(keyByteLen > 0)
    decodeAux(key.byteSubstring(from: keyByteLen), &state, &results)
  }

  private func handleUnitEntry(
    _ key: Substring, _ entry: Entry, _ state: inout State,
    _ results: inout [NumberDecoderResult]
  ) -> Bool {
    results.removeAll()
    if state.isValid() && entry.number == 0 {
      // Supports 0 only as a dependent number.
      return false
    }
    if state.smallDigitNum == 0 || (state.smallDigitNum != -1 && state.smallDigitNum % 10 != 0) {
      // Unit has been already decoded.
      // Invalid: いちさん, ぜろご
      return false
    }

    if entry.outputBeforeDecode {
      Self.maybeAppendResult(state, &results)
    }

    if state.smallDigitNum == -1 {
      state.smallDigitNum = entry.number
    } else {
      assert(state.smallDigitNum % 10 == 0)
      state.smallDigitNum += entry.number
    }
    state.consumedKeys.append(String(key))
    state.digitNum = max(state.digitNum, 1)
    return true
  }

  private func handleSmallDigitEntry(
    _ key: Substring, _ entry: Entry, _ state: inout State,
    _ results: inout [NumberDecoderResult]
  ) -> Bool {
    results.removeAll()
    if state.smallDigit > 1 && entry.digit >= state.smallDigit {
      // Invalid: じゅうせん
      return false
    }
    if state.smallDigitNum == 0 {
      // Invalid: ぜろじゅう
      return false
    }

    if entry.outputBeforeDecode {
      Self.maybeAppendResult(state, &results)
    }

    if state.smallDigitNum == -1 {
      state.smallDigitNum = entry.number
    } else {
      let unit = max(1, state.smallDigitNum % 10)
      let base = (state.smallDigitNum / 10) * 10
      state.smallDigitNum = base + unit * entry.number
    }
    state.smallDigit = entry.digit
    state.consumedKeys.append(String(key))
    state.digitNum = max(state.digitNum, entry.digit)
    return true
  }

  private func handleBigDigitEntry(
    _ key: Substring, _ entry: Entry, _ state: inout State,
    _ results: inout [NumberDecoderResult]
  ) -> Bool {
    results.removeAll()
    if state.bigDigit > 0 && entry.digit >= state.bigDigit {
      // Invalid: おくまん
      return false
    }
    if state.smallDigitNum == -1 || state.smallDigitNum == 0 {
      // Do not decode "まん" to "10000"
      return false
    }

    if entry.outputBeforeDecode {
      Self.maybeAppendResult(state, &results)
    }

    //  state.current_num = -1;
    state.currentNumStr += String(state.smallDigitNum) + entry.digitStr

    state.digitNum = max(state.digitNum, entry.digit + String(state.smallDigitNum).utf8.count - 1)

    state.smallDigitNum = -1
    state.smallDigit = -1
    state.bigDigit = entry.digit
    state.consumedKeys.append(String(key))

    return true
  }
}
