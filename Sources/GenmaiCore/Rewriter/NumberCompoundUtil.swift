// Port of mozc/src/rewriter/number_compound_util.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - The C++ namespace `number_compound_util` is the enum `NumberCompoundUtil`.
// - `SplitStringIntoNumberAndCounterSuffix` returns the number, the counter
//   suffix and the script type as a tuple (nil when it returns false). The
//   number / suffix are `Substring`s of the input (string_view semantics).

import GenmaiBase

public enum NumberCompoundUtil {
  /// `NumberScriptType` (bit flags).
  public enum NumberScriptType {
    public static let none: UInt32 = 0
    public static let halfwidthArabic: UInt32 = 1
    public static let fullwidthArabic: UInt32 = 2
    public static let kanji: UInt32 = 4
    public static let oldKanji: UInt32 = 8
  }

  /// Splits `input` into a leading number and a trailing counter suffix.
  /// Returns nil (C++ false) when the suffix is non-empty and not in
  /// `suffixArray`.
  public static func splitStringIntoNumberAndCounterSuffix(
    _ suffixArray: SerializedStringArray, _ input: some StringProtocol
  ) -> (number: Substring, counterSuffix: Substring, scriptType: UInt32)? {
    let r = splitStringIntoNumberAndCounterSuffixImpl(suffixArray, Substring(input))
    return r.ok ? (r.number, r.counterSuffix, r.scriptType) : nil
  }

  static func splitStringIntoNumberAndCounterSuffixImpl(
    _ suffixArray: SerializedStringArray, _ input: Substring
  ) -> (ok: Bool, number: Substring, counterSuffix: Substring, scriptType: UInt32) {
    var scriptType = NumberScriptType.none
    var s = input
    loop: while !s.isEmpty {
      guard let (c, rest) = Util.splitFirstChar32(s) else {
        return (false, "", "", scriptType)
      }
      // Ascii numbers: [0-9]
      if 0x0030 <= c && c <= 0x0039 {
        scriptType |= NumberScriptType.halfwidthArabic
        s = rest
        continue
      }
      // Full-width arabic numbers: [０-９]
      if 0xFF10 <= c && c <= 0xFF19 {
        scriptType |= NumberScriptType.fullwidthArabic
        s = rest
        continue
      }
      switch c {
      // Cases where c is one of "〇零一二三四五六七八九十百千".
      case 0x3007, 0x4E00, 0x4E03, 0x4E09, 0x4E5D, 0x4E8C, 0x4E94, 0x516B, 0x516D, 0x5341,
        0x5343, 0x56DB, 0x767E, 0x96F6:
        scriptType |= NumberScriptType.kanji
        s = rest
        continue
      // Cases where c is one of "壱弐参".
      case 0x58F1, 0x5F10, 0x53C2:
        scriptType |= NumberScriptType.oldKanji
        s = rest
        continue
      default:
        break loop
      }
    }
    let number = input[input.startIndex..<s.startIndex]
    let counterSuffix = s
    let ok = counterSuffix.isEmpty || suffixArray.binarySearch(counterSuffix)
    return (ok, number, counterSuffix, scriptType)
  }

  // Some number including general noun should be excluded from IsNumber().
  // Keyed by the UTF-8 bytes of "key\0value" (bytewise comparison).
  private static let kExceptions: Set<[UInt8]> = {
    let pairs: [(String, String)] = [
      ("いざよい", "十六夜"),
      ("いちぎ", "一義"),
      ("いちじょ", "一女"),
      ("いっか", "一家"),
      ("いっこう", "一行"),
      ("いったい", "一体"),
      ("いっとき", "一時"),
      ("おはこ", "十八番"),
      ("ここのえ", "九重"),
      ("ごごん", "五言"),
      ("ごしちにち", "五七日"),
      ("ごじゅうさんつぎ", "五十三次"),
      ("ごせち", "五節"),
      ("さんきゃく", "三脚"),
      ("さんさんくど", "三三九度"),
      ("さんしちにち", "三七日"),
      ("さんしゃ", "三者"),
      ("しき", "四季"),
      ("しきゅう", "四球"),
      ("しちごん", "七言"),
      ("しちりん", "七輪"),
      ("しで", "四手"),
      ("じゅうじ", "十字"),
      ("しろくばん", "四六判"),
      ("しろくぶん", "四六文"),
      ("しんし", "参差"),
      ("せんきん", "千金"),
      ("せんげん", "千言"),
      ("せんざい", "千歳"),
      ("せんしん", "千進"),
      ("せんすじ", "千筋"),
      ("せんみつ", "千三つ"),
      ("ちくさ", "千種"),
      ("ちとせ", "千年"),
      ("ちとせ", "千歳"),
      ("ちよ", "千代"),
      ("とうしゃく", "十尺"),
      ("とえ", "十重"),
      ("とき", "十寸"),
      ("ななえ", "七重"),
      ("ななくさ", "七種"),
      ("なななぬか", "七七日"),
      ("はたえ", "二十重"),
      ("はちじゅうはちや", "八十八夜"),
      ("はっぴゃくやちょう", "八百八町"),
      ("ひとえ", "一重"),
      ("ひとなのか", "一七日"),
      ("ひゃっこう", "百行"),
      ("ふたえ", "二重"),
      ("ふたご", "二子"),
      ("ふたなのか", "二七日"),
      ("ふたば", "二葉"),
      ("ふため", "二目"),
      ("みけ", "三毛"),
      ("みそか", "三十日"),
      ("みつくち", "三口"),
      ("みつご", "三児"),
      ("みつご", "三子"),
      ("みつば", "三葉"),
      ("みつめ", "三目"),
      ("みなのか", "三七日"),
      ("むかで", "百足"),
      ("ももとせ", "百歳"),
      ("やえ", "八重"),
      ("やちよ", "八千代"),
      ("やつがしら", "八頭"),
      ("やつくち", "八口"),
      ("やつで", "八手"),
      ("やつはし", "八橋"),
      ("ゆり", "百合"),
      ("よも", "四方"),
      ("りくごう", "六合"),
      ("りくたい", "六体"),
      ("れいほん", "零本"),
      ("ろくどう", "六道"),
      ("ろっかい", "六界"),
      ("ろっぽう", "六方"),
      ("ろっぽう", "六法"),
    ]
    return Set(pairs.map { exceptionKey($0.0, $0.1) })
  }()

  private static func exceptionKey(_ key: some StringProtocol, _ value: some StringProtocol)
    -> [UInt8]
  {
    // Keys never contain NUL, so "key\0value" identifies the pair.
    Array(key.utf8) + [0] + Array(value.utf8)
  }

  /// Checks if the given candidate is a number (or number compound).
  public static func isNumber(
    _ suffixArray: SerializedStringArray, _ posMatcher: PosMatcher, _ cand: Candidate
  ) -> Bool {
    // Compound number entries have the left POS ID of number.
    if posMatcher.isNumber(cand.lid) || posMatcher.isKanjiNumber(cand.lid) {
      return true
    }
    // Some number candidates possibly have noun POS, e.g., 一階.  We further
    // check the opportunities of rewriting such number nouns.
    // TODO(toshiyuki, team): It may be better to set number POS to such number
    // noun entries at dictionary build time.  correct POS.  Then, we can omit
    // the following runtime structure check.
    if !posMatcher.isGeneralNoun(cand.lid) {
      return false
    }
    // Try splitting candidate's content value to number and counter suffix.
    // If it's successful and the resulting number component is nonempty, we
    // may assume the candidate is number.  This check prevents, e.g., the
    // following misrewrite: 百舌鳥(もず, noun) -> 100舌鳥, １００舌鳥, etc.
    guard
      let (number, _, _) = splitStringIntoNumberAndCounterSuffix(
        suffixArray, cand.contentValue)
    else {
      return false
    }
    if kExceptions.contains(exceptionKey(cand.key, cand.value)) {
      return false
    }
    return !number.isEmpty
  }
}
