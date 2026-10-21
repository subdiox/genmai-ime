// Port of mozc/src/base/strings/strip.{h,cc} (3.35.6354).

extension Strings {
  private static let kFullwidthWhitespace = "　"

  /// Strips leading half-width (U+0020) and full-width (U+3000) spaces.
  public static func stripLeadingWhitespace(_ text: some StringProtocol) -> Substring {
    var text = toSubstring(text)
    while !text.isEmpty {
      if text.utf8.first == 0x20 {
        text = text.byteSubstring(from: 1)
      } else if text.hasBytePrefix(kFullwidthWhitespace) {
        text = text.byteSubstring(from: kFullwidthWhitespace.utf8.count)
      } else {
        break
      }
    }
    return text
  }

  /// Strips trailing half-width (U+0020) and full-width (U+3000) spaces.
  public static func stripTrailingWhitespace(_ text: some StringProtocol) -> Substring {
    var text = toSubstring(text)
    while !text.isEmpty {
      if text.utf8.last == 0x20 {
        text = text.byteSubstring(from: 0, length: text.utf8.count - 1)
      } else if text.hasByteSuffix(kFullwidthWhitespace) {
        text = text.byteSubstring(
          from: 0, length: text.utf8.count - kFullwidthWhitespace.utf8.count)
      } else {
        break
      }
    }
    return text
  }

  public static func stripWhitespace(_ text: some StringProtocol) -> Substring {
    stripTrailingWhitespace(stripLeadingWhitespace(text))
  }
}
