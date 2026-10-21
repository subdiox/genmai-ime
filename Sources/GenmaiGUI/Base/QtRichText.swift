// Converts the small subset of Qt rich text used by Mozc's dialog labels (<html><body>, <a href>, <span>)
// into an AttributedString with links, so that the translated HTML strings of the .qtts files can be used
// as they are.

import Foundation

public enum QtRichText {
  /// Parses `html`; `<a href="...">text</a>` becomes a link run, all other tags are dropped and the
  /// HTML entities &lt; &gt; &amp; &quot; are decoded.
  public static func attributedString(_ html: String) -> AttributedString {
    var result = AttributedString()
    var rest = Substring(html)
    var currentLink: URL?
    while !rest.isEmpty {
      guard let open = rest.firstIndex(of: "<") else {
        append(&result, rest, link: currentLink)
        break
      }
      append(&result, rest[rest.startIndex..<open], link: currentLink)
      guard let close = rest[open...].firstIndex(of: ">") else {
        break
      }
      let tag = rest[rest.index(after: open)..<close]
      if tag.hasPrefix("a ") || tag == "a" {
        currentLink = href(in: tag).flatMap { URL(string: $0) }
      } else if tag == "/a" {
        currentLink = nil
      }
      rest = rest[rest.index(after: close)...]
    }
    return result
  }

  /// The plain text of `html` (tags removed).
  public static func plainText(_ html: String) -> String {
    String(attributedString(html).characters)
  }

  private static func href(in tag: Substring) -> String? {
    guard let range = tag.range(of: "href=\"") else { return nil }
    let start = range.upperBound
    guard let end = tag[start...].firstIndex(of: "\"") else { return nil }
    return decodeEntities(String(tag[start..<end]))
  }

  private static func append(_ result: inout AttributedString, _ text: Substring, link: URL?) {
    guard !text.isEmpty else { return }
    var run = AttributedString(decodeEntities(String(text)))
    if let link {
      run.link = link
    }
    result.append(run)
  }

  static func decodeEntities(_ text: String) -> String {
    text.replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&nbsp;", with: "\u{00A0}")
      .replacingOccurrences(of: "&amp;", with: "&")
  }
}
