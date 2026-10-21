// Port of mozc/src/base/url.{h,cc} (3.35.6354).
//
// The C++ works on bytes (std::string); the Swift functions take and return
// Strings but process their UTF-8 bytes. `decodeUrl` decodes the resulting
// bytes as UTF-8 (invalid sequences become U+FFFD).

public enum Url {
  /// Decodes %XX sequences and '+' (as a space).
  public static func decodeUrl(_ input: some StringProtocol) -> String {
    let bytes = Array(input.utf8)
    var result: [UInt8] = []
    result.reserveCapacity(bytes.count)
    func toUpper(_ c: UInt8) -> UInt8 { (c >= 0x61 && c <= 0x7A) ? c - 0x20 : c }
    func isAlpha(_ c: UInt8) -> Bool { (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) }
    var p = 0
    while p < bytes.count {
      if bytes[p] == UInt8(ascii: "%") && p + 2 < bytes.count {
        let h = toUpper(bytes[p + 1])
        let l = toUpper(bytes[p + 2])
        let vh = isAlpha(h) ? (10 + (Int(h) - 0x41)) : (Int(h) - 0x30)
        let vl = isAlpha(l) ? (10 + (Int(l) - 0x41)) : (Int(l) - 0x30)
        result.append(UInt8(truncatingIfNeeded: (vh << 4) + vl))
        p += 2
      } else if bytes[p] == UInt8(ascii: "+") {
        result.append(UInt8(ascii: " "))
      } else {
        result.append(bytes[p])
      }
      p += 1
    }
    return String(decoding: result, as: UTF8.self)
  }

  /// Percent-encodes every byte except ASCII alphanumerics.
  public static func encodeUrl(_ input: some StringProtocol) -> String {
    let hex = Array("0123456789ABCDEF".utf8)
    var result: [UInt8] = []
    for c in input.utf8 {
      if (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) {
        result.append(c)
      } else {
        result.append(UInt8(ascii: "%"))
        result.append(hex[Int(c >> 4)])
        result.append(hex[Int(c & 0x0F)])
      }
    }
    return String(decoding: result, as: UTF8.self)
  }

  private static let kSurveyBaseUrl = "http://www.google.com/support/ime/japanese/bin/request.py"
  private static let kSurveyVersionEntry = "version"
  private static let kSurveyContactTypeEntry = "contact_type"
  private static let kSurveyContactType = "surveyime"
  private static let kSurveyHtmlLanguageEntry = "hl"
  private static let kSurveyHtmlLanguage = "jp"
  private static let kSurveyFormatEntry = "format"
  private static let kSurveyFormat = "inproduct"

  private static func paramPairToString(_ key: String, _ value: some StringProtocol) -> String {
    key + "=" + encodeUrl(value)
  }

  /// Returns the URL of the uninstallation survey (used by the macOS
  /// uninstaller).
  public static func getUninstallationSurveyUrl(_ version: some StringProtocol) -> String {
    var params = [
      paramPairToString(kSurveyContactTypeEntry, kSurveyContactType),
      paramPairToString(kSurveyHtmlLanguageEntry, kSurveyHtmlLanguage),
      paramPairToString(kSurveyFormatEntry, kSurveyFormat),
    ]
    if !version.isEmpty {
      params.append(paramPairToString(kSurveyVersionEntry, version))
    }
    return kSurveyBaseUrl + "?" + params.joined(separator: "&")
  }
}
