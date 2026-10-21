// Port of mozc/src/base/version_def_template.h (3.35.6354).
//
// Values are those of the generated `version_def.h` for the macOS OSS build
// (Vendor/mozc/src/version.bzl: MAJOR=3, MINOR=35, BUILD_OSS=6354,
// REVISION=101 for TARGET_PLATFORM=Mac, ENGINE_VERSION=24).

public enum VersionDef {
  /// The version of the product (genmai), shown in the About dialog, the bundle and the version rewriter. The
  /// values below are the upstream engine version the port follows.
  public static let kProductVersion = "0.1.0"
  public static let kGenmaiVersion = "3.35.6354.101"
  public static let kGenmaiVersionMajor = 3
  public static let kGenmaiVersionMinor = 35
  public static let kGenmaiVersionBuildNumber = 6354
  public static let kGenmaiVersionRevision = 101
  public static let kGenmaiEngineVersion = "24"
  /// DATA_VERSION in version.bzl (not part of version_def.h).
  public static let kGenmaiDataVersion = 11
}
