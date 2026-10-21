// Port of mozc/src/base/text_normalizer.{h,cc} (3.35.6354).
//
// static class for nomalizing session output
// Class functions to be used for output by the Session class.

public enum TextNormalizer {
  public enum Flag: Int, Sendable {
    case kNone = 0  // No normalization.
    case kDefault = 1  // Default behavior (different per platform).
    case kAll = 2  // All normalizations.
  }

  // Unicode vender specific character table:
  // http://hp.vector.co.jp/authors/VA010341/unicode/
  // http://www.notoinsatu.co.jp/font/omake/OTF_other.pdf
  //
  // Example: WAVE_DASH / FULLWIDTH TILDE
  // http://ja.wikipedia.org/wiki/%E6%B3%A2%E3%83%80%E3%83%83%E3%82%B7%E3%83%A5
  // Windows CP932 (shift-jis) maps WAVE_DASH to FULL_WIDTH_TILDA.
  // Since the font of WAVE-DASH is ugly on Windows, here we convert WAVE-DHASH
  // to FULL_WIDTH_TILDA as CP932 does.
  //
  // As Unicode has became the defacto default encoding, we have reduced
  // the number of characters to be normalized.
  private static func normalizeCharForWindows(_ c: Char32) -> Char32 {
    switch c {
    case 0x301C:  // WAVE DASH
      return 0xFF5E  // FULLWIDTH TILDE
    case 0x2212:  // MINUS SIGN
      return 0xFF0D  // FULLWIDTH HYPHEN MINUS
    default:
      return c
    }
  }

  // value (2N):   codepoint of CJK compatibility character.
  // value (2N+1): codepoint of SVS base character.
  private static let exceptions: [Int] = [
    0xF91D, 0x6B04,  // {欄, 欄} defined in KS X 1001.
    0xF928, 0x5ECA,  // {廊, 廊} defined in KS X 1001.
    0xF929, 0x6717,  // {朗, 朗} defined in KS X 1001.
    0xF936, 0x865C,  // {虜, 虜} defined in KS X 1001.
    0xF970, 0x6BBA,  // {殺, 殺} defined in KS X 1001.
    0xF9D0, 0x985E,  // {類, 類} defined in KS X 1001.
    0xF9DC, 0x9686,  // {隆, 隆} defined in KS X 1001.
    0xFA6C, 0x242EE,  // {𤋮, 𤋮} value is more than 16bits.
  ]

  // value: codepoint of CJK compatibility character
  //        to be converted to SVS character with FE01.
  private static let fe01Chars: [UInt16] = [
    0xFA57,  // 練 → 7DF4 FE01 練
    0xFA5E,  // 艹 → 8279 FE01 艹
    0xFA67,  // 逸 → 8279 FE01 艹
  ]

  // index: codepoint of CJK compatibility character - 0xFA10.
  // value: codepoint of SVS base character.
  private static let convTable: [UInt16] = [
    // FA10
    //  塚     (﨑)     晴     (﨓)    (﨔)     凞      猪      益
    0x585A, 0x0000, 0x6674, 0x0000, 0x0000, 0x51DE, 0x732A, 0x76CA,
    // FA18
    //  礼      神      祥      福      靖      精      羽     (﨟)
    0x793C, 0x795E, 0x7965, 0x798F, 0x9756, 0x7CBE, 0x7FBD, 0x0000,
    // FA20
    //  蘒     (﨡)     諸     (﨣)    (﨤)     逸      都     (﨧)
    0x8612, 0x0000, 0x8AF8, 0x0000, 0x0000, 0x9038, 0x90FD, 0x0000,
    // FA28
    // (﨨)    (﨩)     飯      飼      館      鶴     (郞)    (隷)
    0x0000, 0x0000, 0x98EF, 0x98FC, 0x9928, 0x9DB4, 0x90DE, 0x96B7,
    // FA30
    //  侮      僧      免      勉      勤      卑      喝      嘆
    0x4FAE, 0x50E7, 0x514D, 0x52C9, 0x52E4, 0x5351, 0x559D, 0x5606,
    // FA38
    //  器      塀      墨      層      屮      悔      慨      憎
    0x5668, 0x5840, 0x58A8, 0x5C64, 0x5C6E, 0x6094, 0x6168, 0x618E,
    // FA40
    //  懲      敏      既      暑      梅      海      渚      漢
    0x61F2, 0x654F, 0x65E2, 0x6691, 0x6885, 0x6D77, 0x6E1A, 0x6F22,
    // FA48
    //  煮      爫      琢      碑      社      祉      祈      祐
    0x716E, 0x722B, 0x7422, 0x7891, 0x793E, 0x7949, 0x7948, 0x7950,
    // FA50
    //  祖      祝      禍      禎      穀      突      節      練
    0x7956, 0x795D, 0x798D, 0x798E, 0x7A40, 0x7A81, 0x7BC0, 0x7DF4,
    // FA58
    //  縉      繁      署      者      臭      艹      艹      著
    0x7E09, 0x7E41, 0x7F72, 0x8005, 0x81ED, 0x8279, 0x8279, 0x8457,
    // FA60
    //  褐      視      謁      謹      賓      贈      辶      逸
    0x8910, 0x8996, 0x8B01, 0x8B39, 0x8CD3, 0x8D08, 0x8FB6, 0x8279,
    // FA68 - FA6D
    //  難      響      頻      恵     (𤋮)     舘
    0x96E3, 0x97FF, 0x983B, 0x6075, 0x0000, 0x8218,
  ]

  private static func convertJaCjkCompatToSvs(_ cjkCompatChar: Char32) -> (Int, Int) {
    let noValue = (0, 0)

    // If the char is out of all data range, return kNoValue.
    // kExceptionMap: 0xF91D - 0xFA6C
    // kFe01Set:      0xFA57 - 0xFA67
    // kConvTable:    0xFA10 - 0xFA6D
    if cjkCompatChar < 0xF91D || cjkCompatChar > 0xFA6D {
      return noValue
    }

    var svsBase = 0
    var svsExtend = 0xFE00

    // Check the value in `exceptions`.
    var i = 0
    while i < exceptions.count {
      if Int(cjkCompatChar) == exceptions[i] {
        svsBase = exceptions[i + 1]
        // svs_extend for all values in `exceptions` is 0xFE00;
        return (svsBase, svsExtend)
      }
      i += 2
    }

    // Check if the char is out of kConvTable. Upper range is already checked.
    if cjkCompatChar < 0xFA10 {
      return noValue
    }

    // Get the value from the table.
    svsBase = Int(convTable[Int(cjkCompatChar) - 0xFA10])
    if svsBase == 0 {
      return noValue
    }

    // Check if the SVS extend is FE01. In most cases, it's FE00.
    // There is no case of 0xFE02 or more for Japanese CJK compatibility chars.
    for c in fe01Chars where Int(cjkCompatChar) == Int(c) {
      svsExtend += 1
      break
    }
    return (svsBase, svsExtend)
  }

  private static func normalizeTextForWindows(_ input: some StringProtocol) -> String {
    var output = ""
    for c in ConstChar32Iterator(input) {
      Util.codepointToUtf8Append(normalizeCharForWindows(c), &output)
    }
    return output
  }

  /// Normalizes `input` with all configurations.
  public static func normalizeTextWithFlag(_ input: some StringProtocol, _ flag: Flag) -> String {
    var flag = flag
    if flag == .kDefault {
      // Not _WIN32.
      flag = .kNone
    }

    if flag != .kAll {
      return String(input)
    }

    return normalizeTextForWindows(input)
  }

  /// Normalizes `input` considering the platform.
  public static func normalizeText(_ input: some StringProtocol) -> String {
    normalizeTextWithFlag(input, .kDefault)
  }

  /// Normalizes Japanese CJK compatibility ideographs to SVS characters.
  /// Returns false and keeps output as is, if no character is normalized.
  public static func normalizeTextToSvs(_ input: some StringProtocol, _ output: inout String) -> Bool {
    let codepoints = Util.utf8ToUtf32(input)
    var normalized: [Char32] = []
    normalized.reserveCapacity(codepoints.count)
    var modified = false
    for cp in codepoints {
      let svs = convertJaCjkCompatToSvs(cp)
      if svs.0 == 0 {
        normalized.append(cp)
      } else {
        modified = true
        normalized.append(Char32(svs.0))
        normalized.append(Char32(svs.1))
      }
    }
    if !modified {
      return false
    }

    output = Util.utf32ToUtf8(normalized)
    return true
  }

  public static func normalizeTextToSvs(_ input: some StringProtocol) -> String {
    var output = ""
    if normalizeTextToSvs(input, &output) {
      return output
    }
    return String(input)
  }

  /// Sanitizes the input text by enforcing byte limit, removing ASCII control
  /// characters, and filtering ill-formed UTF-8 sequences.
  /// Returns nil if no modification is necessary.
  public static func sanitizeText<C: Collection>(_ input: C, _ maxBytes: Int) -> String?
  where C.Element == UInt8 {
    func isValidText(_ str: C, _ maxBytes: Int) -> Bool {
      if str.count > maxBytes {
        return false
      }
      for c in Utf8BytesAsUnicodeChar(str) {
        if !c.ok || c.char32 < 32 || c.char32 == 127 {
          return false
        }
      }
      return true
    }
    if isValidText(input, maxBytes) {
      return nil
    }

    var sanitized: [UInt8] = []
    sanitized.reserveCapacity(maxBytes)
    let truncated = input.prefix(maxBytes)
    for c in Utf8BytesAsUnicodeChar(truncated) {
      if !c.ok || c.char32 < 32 || c.char32 == 127 {
        continue
      }
      sanitized.append(contentsOf: c.utf8)
    }
    return String(decoding: sanitized, as: UTF8.self)
  }

  public static func sanitizeText(_ input: some StringProtocol, _ maxBytes: Int) -> String? {
    sanitizeText(Array(input.utf8), maxBytes)
  }
}
