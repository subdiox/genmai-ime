// Prompt format of the genmai converter (the "zenzlc" prompt of the Python training code, `prompt_ids`, and
// zenz_score.py `k2k` / `pre`): BOS + pre(CTX + context + IN + katakana(reading) + OUT), with the context limited
// to its last 500 characters (Unicode scalars, as Python `str` slicing), spaces -> U+3000 and newlines removed.

public enum GenmaiPrompt {
  /// Control characters (private use) of the zenz prompt format.
  public static let inputMarker = "\u{EE00}"
  public static let outputMarker = "\u{EE01}"
  public static let contextMarker = "\u{EE02}"
  /// zenzlc keeps up to this many characters of left context.
  public static let maxContextLength = 500

  /// Hiragana (U+3041 ... U+3096) to katakana; everything else unchanged.
  public static func katakana(_ s: String) -> String {
    var out = String.UnicodeScalarView()
    for c in s.unicodeScalars {
      if c.value >= 0x3041 && c.value <= 0x3096 {
        out.append(Unicode.Scalar(c.value + 0x60)!)
      } else {
        out.append(c)
      }
    }
    return String(out)
  }

  /// zenz `pre`: ' ' -> U+3000, '\n' removed.
  public static func preprocess(_ s: String) -> String {
    var out = String.UnicodeScalarView()
    for c in s.unicodeScalars {
      if c == " " {
        out.append("\u{3000}")
      } else if c != "\n" {
        out.append(c)
      }
    }
    return String(out)
  }

  /// The last `n` Unicode scalars of `s` (Python `s[-n:]`).
  static func suffix(_ s: String, _ n: Int) -> String {
    let u = s.unicodeScalars
    let count = u.count
    guard count > n else { return s }
    return String(String.UnicodeScalarView(u.dropFirst(count - n)))
  }

  public static func text(reading: String, context: String) -> String {
    let ctx = suffix(context, maxContextLength)
    return preprocess((ctx.isEmpty ? "" : contextMarker + ctx) + inputMarker + katakana(reading) + outputMarker)
  }

  public static func ids(_ tokenizer: GenmaiTokenizer, reading: String, context: String) -> [Int32] {
    [tokenizer.bosTokenID] + tokenizer.encode(text(reading: reading, context: context))
  }
}
