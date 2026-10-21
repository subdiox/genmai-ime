// Port of mozc/src/converter/key_corrector.{h,cc} (3.35.6354).

import GenmaiBase

/// `mozc::KeyCorrector`: corrects common romaji typos in the key ("みんあ" →
/// "みんな", ...) and keeps the byte alignment between the original and the
/// corrected key.
public struct KeyCorrector: Sendable {
  public enum InputMode: Sendable {
    case roman
    case kana
  }

  /// maximum key length KeyCorrector can handle
  /// if key is too long, we don't do key correction
  private static let kMaxSize = 128

  /// invalid alignment marker (C++ `static_cast<size_t>(-1)`).
  private static let kInvalidPos = Int.max

  public private(set) var mode: InputMode = .roman
  private var available = false
  private var correctedKeyBytes: [UInt8] = []
  /// return corrected key;
  public private(set) var correctedKey: String = ""
  /// return original key;
  public private(set) var originalKey: String = ""
  private var alignment: [Int] = []
  private var revAlignment: [Int] = []

  public init(_ key: some StringProtocol, _ mode: InputMode, _ historySize: Int) {
    self.mode = mode
    _ = initialize(Array(key.utf8), String(key), mode, historySize)
    correctedKey = String(decoding: correctedKeyBytes, as: UTF8.self)
  }

  /// return true key correction was done successfully
  public func isAvailable() -> Bool { available }

  /// return the position of corrected_key corresponding
  /// to the original_key_pos
  /// return invalidPosition() if invalid pos is passed.
  /// Note that the position is not by Unicode Character but by bytes.
  public func getCorrectedPosition(_ originalKeyPos: Int) -> Int {
    if originalKeyPos >= 0 && originalKeyPos < alignment.count {
      return alignment[originalKeyPos]
    }
    return Self.kInvalidPos
  }

  /// return the position of original_key corresponding
  /// to the corrected_key_pos
  /// return invalidPosition() if invalid pos is passed.
  /// Note that the position is not by Unicode Character but by bytes.
  public func getOriginalPosition(_ correctedKeyPos: Int) -> Int {
    if correctedKeyPos >= 0 && correctedKeyPos < revAlignment.count {
      return revAlignment[correctedKeyPos]
    }
    return Self.kInvalidPos
  }

  /// return true if pos is NOT kInvalidPos
  public static func isValidPosition(_ pos: Int) -> Bool { pos != kInvalidPos }

  /// return true if pos is kInvalidPos
  public static func isInvalidPosition(_ pos: Int) -> Bool { pos == kInvalidPos }

  /// return kInvalidPos
  public static func invalidPosition() -> Int { kInvalidPos }

  /// return new prefix of string corresponding to
  /// the prefix of the original key at `original_key_pos`.
  /// if new prefix and original prefix are the same, return empty string.
  ///
  /// More formally, this function can be defined as:
  /// GetNewPrefix(original_key_pos) ==
  ///   corrected_key.substr(GetCorrectedPosition(original_key),
  ///                        corrected_key.size() -
  ///                        GetCorrectedPosition(original_key))
  ///
  /// Example:
  ///  original: "せかいじゅのはっぱ"
  ///  corrected: "せかいじゅうのはっぱ"
  ///  GetPrefix(0) = "せかいじゅうのはっぱ"
  ///  GetPrefix(3) = "かいじゅうのはっぱ"
  ///  GetPrefix(9) = "じゅうのはっぱ"
  ///  GetPrefix(12) = "ゅうのはっぱ"
  ///  GetPrefix(15) = "" (not "うのはっぱ")
  ///                  "う" itself doesn't correspond to the original key,
  ///                   so, we don't make a new prefix
  ///  GetPrefix(18) = "" (same as original)
  ///
  /// Example2:
  ///  original: "みんあのほん"
  ///  GetPrefix(0) = "みんなのほん"
  ///  GetPrefix(3) = "んなのほん"
  ///  GetPrefix(9) = "なのほん"
  ///  GetPrefix(12) = ""
  public func getCorrectedPrefix(_ originalKeyPos: Int) -> Substring {
    if !isAvailable() {
      return ""
    }
    if mode == .kana {
      return ""
    }
    let correctedKeyPos = getCorrectedPosition(originalKeyPos)
    if !Self.isValidPosition(correctedKeyPos) {
      return ""
    }
    let correctedSubstr = correctedKey.byteSubstring(from: correctedKeyPos)
    let originalSubstr = originalKey.byteSubstring(from: originalKeyPos)
    if !correctedSubstr.bytesEqual(originalSubstr) {
      return correctedSubstr
    }
    return ""
  }

  /// This is a helper function for CommonPrefixSearch in Converter.
  /// Basically it is equivalent to
  /// GetOriginalPosition(GetCorrectedPosition(original_key_pos)
  ///                     + new_key_offset) - original_key_pos;
  ///
  /// Example:
  ///  original:  "せかいじゅのはっぱ"
  ///  corrected: "せかいじゅうのはっぱ"
  /// GetOffset(0, 3) == 3
  /// GetOffset(0, 12) == 12
  /// GetOffset(0, 15) == 12
  /// GetOffset(0, 18) == 15
  ///
  /// By combining GetCorrectedPrefix() and GetOriginalOffset(),
  /// Converter is able to know the position of the lattice
  public func getOriginalOffset(_ originalKeyPos: Int, _ newKeyOffset: Int) -> Int {
    if !isAvailable() {
      return Self.kInvalidPos
    }
    if mode == .kana {
      return Self.kInvalidPos
    }
    let correctedKeyPos = getCorrectedPosition(originalKeyPos)
    if !Self.isValidPosition(correctedKeyPos) {
      return Self.kInvalidPos
    }

    if revAlignment.count == correctedKeyPos + newKeyOffset {
      return alignment.count - getOriginalPosition(correctedKeyPos)
    } else {
      // treat right edge
      let originalKeyPos2 = getOriginalPosition(correctedKeyPos + newKeyOffset)

      if !Self.isValidPosition(originalKeyPos2) {
        return Self.kInvalidPos
      }

      // Don't allow NULL matching
      if originalKeyPos2 >= originalKeyPos {
        return originalKeyPos2 - originalKeyPos
      }
    }
    return Self.kInvalidPos
  }

  /// return the cost penalty for the corrected key.
  /// The return value is added to the original cost as a penalty.
  public static func getCorrectedCostPenalty(_ key: some StringProtocol) -> Int {
    // "んん" and "っっ" must be mis-spelling.
    if key.utf8.firstRange(of: "んん".utf8) != nil || key.utf8.firstRange(of: "っっ".utf8) != nil {
      return 0
    }
    // add 3000 to the original word cost
    let kCorrectedCostPenalty = 3000
    return kCorrectedCostPenalty
  }

  private mutating func initialize(_ key: [UInt8], _ keyString: String, _ mode: InputMode, _ historySize: Int)
    -> Bool
  {
    // TODO(taku)  support KANA
    if mode == .kana {
      return false
    }

    if key.isEmpty || key.count >= Self.kMaxSize {
      // MOZC_VLOG(1) << "invalid key length";
      return false
    }

    originalKey = keyString

    let inputBegin = min(key.count, historySize)
    var p = 0  // prefix = key[p...]
    var keyPos = 0

    while p < key.count {
      let prefix = key[p...]
      var mblen = 0
      let orgLen = correctedKeyBytes.count
      if p < inputBegin
        || (!Self.rewriteDoubleNN(keyPos, prefix, &mblen, &correctedKeyBytes)
          && !Self.rewriteNN(keyPos, prefix, &mblen, &correctedKeyBytes)
          && !Self.rewriteYu(keyPos, prefix, &mblen, &correctedKeyBytes)
          && !Self.rewriteNI(keyPos, prefix, &mblen, &correctedKeyBytes)
          && !Self.rewriteSmallTSU(keyPos, prefix, &mblen, &correctedKeyBytes)
          && !Self.rewriteM(keyPos, prefix, &mblen, &correctedKeyBytes))
      {
        let (codepoint, len) = Util.utf8ToCodepoint(prefix)
        mblen = len
        Util.codepointToUtf8Append(codepoint, &correctedKeyBytes)
      }

      let correctedMblen = correctedKeyBytes.count - orgLen

      if correctedMblen <= 0 && mblen <= 0 {
        // LOG(ERROR) << "Invalid pattern: " << key;
        return false
      }

      // one to one mapping
      if mblen == correctedMblen {
        let len = p
        for i in 0..<mblen {
          alignment.append(orgLen + i)
          revAlignment.append(len + i)
        }
      } else {
        // NOT a one to one mapping, we take fist/last alignment only
        alignment.append(orgLen)
        if mblen > 1 {
          for _ in 1..<mblen {
            alignment.append(Self.kInvalidPos)
          }
        }
        revAlignment.append(p)
        if correctedMblen > 1 {
          for _ in 1..<correctedMblen {
            revAlignment.append(Self.kInvalidPos)
          }
        }
      }

      p += mblen
      keyPos += 1
    }

    available = true
    return true
  }

  // MARK: - Rewrite rules

  private typealias Bytes = ArraySlice<UInt8>

  @inline(__always)
  private static func codepoint(_ s: Bytes, _ mblen: inout Int) -> Char32 {
    let r = Util.utf8ToCodepoint(s)
    mblen = r.mblen
    return r.codepoint
  }

  // "ん" (few "n" pattern)
  // "んあ" -> "んな"
  // "んい" -> "んに"
  // "んう" -> "んぬ"
  // "んえ" -> "んね"
  // "んお" -> "んの"
  private static func rewriteNN(_ keyPos: Int, _ prefix: Bytes, _ mblen: inout Int, _ output: inout [UInt8])
    -> Bool
  {
    if keyPos == 0 {
      mblen = 0
      return false
    }
    let cp = codepoint(prefix, &mblen)
    if cp != 0x3093 {  // "ん"
      mblen = 0
      return false
    }
    let rest = prefix.dropFirst(mblen)
    if rest.isEmpty {
      mblen = 0
      return false
    }
    var mblen2 = 0
    let nextCodepoint = UInt16(truncatingIfNeeded: codepoint(rest, &mblen2))
    var outputCodepoint: UInt16 = 0x0000
    switch nextCodepoint {
    case 0x3042: outputCodepoint = 0x306A  // "あ" -> "な"
    case 0x3044: outputCodepoint = 0x306B  // "い" -> "に"
    case 0x3046: outputCodepoint = 0x306C  // "う" -> "ぬ"
    case 0x3048: outputCodepoint = 0x306D  // "え" -> "ね"
    case 0x304A: outputCodepoint = 0x306E  // "お" -> "の"
    default: break
    }

    if outputCodepoint != 0x0000 {  // "ん[あいうえお]"
      Util.codepointToUtf8Append(cp, &output)
      Util.codepointToUtf8Append(Char32(outputCodepoint), &output)
      mblen += mblen2
      return true
    } else {  // others
      mblen = 0
      return false
    }
  }

  // "んん" (many "n" pattern)
  // "([^ん])んん[ん]" -> ignore
  // "([^ん])んん[あいうえお]" ->  $1 and leave "ん[あいうえお]"
  // "([^ん])んん[^あいうえお]" -> $1"ん" and leave "[^あいうえお]"
  private static func rewriteDoubleNN(
    _ keyPos: Int, _ prefix: Bytes, _ mblen: inout Int, _ output: inout [UInt8]
  ) -> Bool {
    // 0x3093: "ん"
    let kPattern: [UInt16] = [0x0000, 0x3093, 0x3093]

    mblen = 0
    var firstChar: UInt16 = 0x0000
    var firstMblen = 0
    var prefix = prefix
    for i in 0..<kPattern.count {
      if prefix.isEmpty {
        mblen = 0
        return false
      }
      var mblen2 = 0
      let cp = codepoint(prefix, &mblen2)
      if (kPattern[i] == 0x0000 && cp != 0x3093 && Util.getScriptType(cp) == .hiragana)
        || (kPattern[i] == 0x3093 && cp == 0x3093)
      {
        if i == 0 {
          firstMblen = mblen2
          firstChar = UInt16(truncatingIfNeeded: cp)
        }
      } else {
        mblen = 0
        return false
      }
      prefix = prefix.dropFirst(mblen2)
      mblen += mblen2
    }

    if prefix.isEmpty {
      mblen = 0
      return false
    }

    if firstChar == 0x0000 || firstMblen == 0 {
      mblen = 0
      return false
    }

    var mblen2 = 0
    let cp = codepoint(prefix, &mblen2)
    if cp == 0x3093 {  // "ん" ignore
      mblen = 0
      return false
    } else if cp == 0x3042  // "[あいうえお]"
      || cp == 0x3044 || cp == 0x3046 || cp == 0x3048 || cp == 0x304A
    {
      // drop first "ん" and leave "ん[あいうえお]"
      // remained part will be handled by RewriteNN(), e.g., "んあ" -> "んな"
      Util.codepointToUtf8Append(Char32(firstChar), &output)
      // Skip one Hiragana character in UTF-8, which is 3 bytes.
      mblen = firstMblen + 3
      return true
    } else {  // "[^あいうえお]"
      Util.codepointToUtf8Append(Char32(firstChar), &output)
      Util.codepointToUtf8Append(0x3093, &output)  // "ん"
      return true
    }
  }

  // "に" pattern
  // "にゃ" -> "んや"
  // "にゅ" -> "んゆ"
  // "にょ" -> "んよ"
  private static func rewriteNI(_ keyPos: Int, _ prefix: Bytes, _ mblen: inout Int, _ output: inout [UInt8])
    -> Bool
  {
    let cp = codepoint(prefix, &mblen)
    if cp != 0x306B {  // "に"
      mblen = 0
      return false
    }
    let rest = prefix.dropFirst(mblen)
    if rest.isEmpty {
      mblen = 0
      return false
    }
    var mblen2 = 0
    let nextCodepoint = UInt16(truncatingIfNeeded: codepoint(rest, &mblen2))
    var outputCodepoint: UInt16 = 0x0000
    switch nextCodepoint {
    case 0x3083: outputCodepoint = 0x3084  // "ゃ" -> "や"
    case 0x3085: outputCodepoint = 0x3086  // "ゅ" -> "ゆ"
    case 0x3087: outputCodepoint = 0x3088  // "ょ" -> "よ"
    default: outputCodepoint = 0x0000
    }

    if outputCodepoint != 0x0000 {
      Util.codepointToUtf8Append(0x3093, &output)  // "ん"
      Util.codepointToUtf8Append(Char32(outputCodepoint), &output)
      mblen += mblen2
      return true
    } else {
      mblen = 0
      return false
    }
  }

  // "m" Pattern (not BOS)
  // "m[ばびぶべぼぱぴぷぺぽ]" -> "ん[ばびぶべぼぱぴぷぺぽ]"
  private static func rewriteM(_ keyPos: Int, _ prefix: Bytes, _ mblen: inout Int, _ output: inout [UInt8])
    -> Bool
  {
    if keyPos == 0 {
      mblen = 0
      return false
    }
    let cp = codepoint(prefix, &mblen)
    // "m" or "ｍ" (don't take capitial letter, as "M" might not be a misspelling)
    if cp != 0x006D && cp != 0xFF4D {
      mblen = 0
      return false
    }
    let rest = prefix.dropFirst(mblen)
    if rest.isEmpty {
      mblen = 0
      return false
    }
    var mblen2 = 0
    let nextCodepoint = UInt16(truncatingIfNeeded: codepoint(rest, &mblen2))
    // "[はばぱひびぴふぶぷへべぺほぼぽ]" => [0x306F .. 0X307D]
    // Here we want to take "[は..ぽ]" except for "はひふへほ"
    if nextCodepoint % 3 != 0  // not "はひふへほ"
      && nextCodepoint >= 0x306F && nextCodepoint <= 0x307D
    {  // "は..ぽ"
      Util.codepointToUtf8Append(0x3093, &output)  // "ん"
      Util.codepointToUtf8Append(Char32(nextCodepoint), &output)
      mblen += mblen2
      return true
    } else {
      mblen = 0
      return false
    }
  }

  // "きっって" ->" きって"
  // replace "([^っ])っっ([^っ])" => "$1っ$2"
  // Don't consider more that three "っっっ"
  // e.g., "かっっった" -> "かっっった"
  private static func rewriteSmallTSU(
    _ keyPos: Int, _ prefix: Bytes, _ mblen: inout Int, _ output: inout [UInt8]
  ) -> Bool {
    // 0x0000 is a place holder for "[^っ]"
    // "っ": 0x3063
    let kPattern: [UInt16] = [0x0000, 0x3063, 0x3063, 0x0000]

    var firstChar: UInt16 = 0x0000
    var lastChar: UInt16 = 0x0000
    var prefix = prefix
    for i in 0..<kPattern.count {
      if prefix.isEmpty {
        mblen = 0
        return false
      }
      var mblen2 = 0
      let cp = codepoint(prefix, &mblen2)
      if (kPattern[i] == 0x0000 && cp != 0x3063 && Util.getScriptType(cp) == .hiragana)
        || (kPattern[i] == 0x3063 && cp == 0x3063)
      {
        if i == 0 {
          firstChar = UInt16(truncatingIfNeeded: cp)
        } else if i == kPattern.count - 1 {
          lastChar = UInt16(truncatingIfNeeded: cp)
        }
      } else {
        mblen = 0
        return false
      }
      prefix = prefix.dropFirst(mblen2)
      mblen += mblen2
    }

    if firstChar == 0x0000 || lastChar == 0x0000 {
      mblen = 0
      return false
    }

    Util.codepointToUtf8Append(Char32(firstChar), &output)
    Util.codepointToUtf8Append(0x3063, &output)  // "っ"
    Util.codepointToUtf8Append(Char32(lastChar), &output)
    return true
  }

  // Not implemented yet, as they looks minor
  // "[子音][ゃゅょ][^う]" Pattern
  // "きゅ[^う] -> きゅう"
  // "しゅ[^う] -> しゅう"
  // "ちゅ[^う] -> ちゅう"
  // "にゅ[^う] -> にゅう"
  // "ひゅ[^う] -> ひゅう"
  // "りゅ[^う] -> りゅう"
  private static func rewriteYu(_ keyPos: Int, _ prefix: Bytes, _ mblen: inout Int, _ output: inout [UInt8])
    -> Bool
  {
    let firstChar = codepoint(prefix, &mblen)
    if firstChar != 0x304D && firstChar != 0x3057 && firstChar != 0x3061 && firstChar != 0x306B
      && firstChar != 0x3072 && firstChar != 0x308A
    {  // !"きしちにひり"
      mblen = 0
      return false
    }
    var rest = prefix.dropFirst(mblen)
    if rest.isEmpty {
      mblen = 0
      return false
    }
    var mblen2 = 0
    let nextChar = codepoint(rest, &mblen2)
    if nextChar != 0x3085 {  // "ゅ"
      mblen = 0
      return false
    }
    rest = rest.dropFirst(mblen2)
    if rest.isEmpty {
      mblen = 0
      return false
    }
    var mblen3 = 0
    let lastChar = codepoint(rest, &mblen3)
    if lastChar == 0x3046 {  // "う"
      mblen = 0
      return false
    }

    // OK, rewrite
    mblen += mblen2
    Util.codepointToUtf8Append(firstChar, &output)
    Util.codepointToUtf8Append(nextChar, &output)  // "ゅ"
    Util.codepointToUtf8Append(0x3046, &output)  // "う"
    return true
  }
}
