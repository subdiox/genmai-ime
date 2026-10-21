// Port of mozc/src/rewriter/collocation_util.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - `GetNormalizedScript` returns the result instead of writing to an output
//   pointer.
// - `absl::StrReplaceAll({{"％", "%"}, {"～", "〜"}})` is applied per code
//   point while the output is built; both replacements are single code point
//   to single code point and cannot overlap, so the result is identical.

import GenmaiBase

public enum CollocationUtil {
  /// Gets normalized script
  /// Removes or rewrites some symbols.
  /// for example:
  /// "一個" -> "個" (removes 'number' if |remove_number| is true)
  /// "%％" -> "%%" (full width '%' to half width)
  public static func getNormalizedScript(_ str: some StringProtocol, _ removeNumber: Bool) -> String {
    var output = ""
    removeExtraCharacters(str, removeNumber, &output)
    return output
  }

  /// Returns true if given char is number including kanji.
  public static func isNumber(_ c: Char32) -> Bool {
    if Util.getScriptType(c) == .number {
      return true
    }

    switch c {
    case 0x3007,  // "〇"
      0x4e00,  // "一"
      0x4e8c,  // "二"
      0x4e09,  // "三"
      0x56db,  // "四"
      0x4e94,  // "五"
      0x516d,  // "六"
      0x4e03,  // "七"
      0x516b,  // "八"
      0x4e5d,  // "九"
      0x5341,  // "十"
      0x767e,  // "百"
      0x5343,  // "千"
      0x4e07,  // "万"
      0x5104,  // "億"
      0x5146:  // "兆"
      return true
    default:
      break
    }
    return false
  }

  /// Removes characters for normalizing.
  private static func removeExtraCharacters(
    _ input: some StringProtocol, _ removeNumber: Bool, _ output: inout String
  ) {
    for scalar in input.unicodeScalars {
      let codepoint = Char32(scalar.value)
      if ((Util.getScriptType(codepoint) != .unknownScript)
        && (!removeNumber || !isNumber(codepoint))) || codepoint == 0x3005  // "々"
        || codepoint == 0x0025 || codepoint == 0xFF05  // "%", "％"
        || codepoint == 0x3006  // "〆"
        || codepoint == 0x301C || codepoint == 0xFF5E
      {  // "〜", "～"
        // StrReplaceAll({{"％", "%"}, {"～", "〜"}}).
        let normalized: Char32 =
          switch codepoint {
          case 0xFF05: 0x0025
          case 0xFF5E: 0x301C
          default: codepoint
          }
        Util.codepointToUtf8Append(normalized, &output)
      }
    }
  }
}
