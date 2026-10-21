// Port of mozc/src/base/version.{h,cc} (3.35.6354).

public enum Version {
  /// Get current mozc version (former called MOZC_VERSION)
  public static func getGenmaiVersion() -> String { VersionDef.kGenmaiVersion }
  /// The product version (not the upstream engine version).
  public static func getProductVersion() -> String { VersionDef.kProductVersion }
  public static func getGenmaiVersionMajor() -> Int { VersionDef.kGenmaiVersionMajor }
  public static func getGenmaiVersionMinor() -> Int { VersionDef.kGenmaiVersionMinor }
  public static func getGenmaiVersionBuildNumber() -> Int { VersionDef.kGenmaiVersionBuildNumber }
  public static func getGenmaiVersionRevision() -> Int { VersionDef.kGenmaiVersionRevision }
  public static func getGenmaiEngineVersion() -> String { VersionDef.kGenmaiEngineVersion }

  /// Returns true if lhs is less than rhs in the lexical order.
  /// compareVersion("1.2.3.4", "1.2.3.4") => false
  /// compareVersion("1.2.3.4", "5.2.3.4") => true
  /// compareVersion("1.25.3.4", "1.2.3.4") => false
  public static func compareVersion(_ lhs: String, _ rhs: String) -> Bool {
    if lhs == rhs {
      return false
    }
    if lhs.contains("Unknown") || rhs.contains("Unknown") {
      // LOG(WARNING) << "Unknown is given as version";
      return false
    }
    let vlhs = lhs.utf8.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: true)
    let vrhs = rhs.utf8.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: true)
    return vlhs.lexicographicallyPrecedes(vrhs) { a, b in
      simpleAtoi(a) < simpleAtoi(b)
    }
  }

  // NumberUtil::SimpleAtoi: returns 0 when the string is not a valid int.
  private static func simpleAtoi(_ s: Substring.UTF8View) -> Int {
    Int(String(decoding: s, as: UTF8.self).trimmingWhitespace()) ?? 0
  }
}

extension String {
  fileprivate func trimmingWhitespace() -> String {
    var s = Substring(self)
    while let f = s.first, f == " " || f == "\t" || f == "\n" || f == "\r" { s.removeFirst() }
    while let l = s.last, l == " " || l == "\t" || l == "\n" || l == "\r" { s.removeLast() }
    return String(s)
  }
}
