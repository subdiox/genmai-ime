// Partial port of mozc/src/base/mac/mac_util.{h,mm} (3.35.6354): only the
// functions needed by GenmaiBase (system_util, encryptor). Launchd / login item
// / prelauncher helpers belong to the app layer and are not ported.

import Foundation

#if os(macOS)
  import IOKit
#endif

public enum MacUtil {
  // kProductPrefix for the OSS (MOZC_BUILD) branding.
  static let kProductPrefix = "Genmai"
  static let kServerDirectory = "/Library/Input Methods/\(kProductPrefix).app/Contents/Resources"
  static let kProjectPrefix = "io.github.subdiox.genmai.inputmethod.Japanese."

  private static func searchPathForDirectoriesInDomains(
    _ directory: FileManager.SearchPathDirectory
  ) -> String {
    let paths = NSSearchPathForDirectoriesInDomains(directory, .userDomainMask, true)
    return paths.first ?? ""
  }

  /// Returns the label of the commands that this user interface depends on.
  public static func getLabelForSuffix(_ suffix: String) -> String {
    kProjectPrefix + suffix
  }

  /// ~/Library/Application Support
  public static func getApplicationSupportDirectory() -> String {
    searchPathForDirectoriesInDomains(.applicationSupportDirectory)
  }

  /// ~/Library/Caches
  public static func getCachesDirectory() -> String {
    searchPathForDirectoriesInDomains(.cachesDirectory)
  }

  /// ~/Library/Logs/Genmai
  public static func getLoggingDirectory() -> String {
    let paths = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true)
    guard let first = paths.first else { return "" }
    return ((first as NSString).appendingPathComponent("Logs") as NSString)
      .appendingPathComponent(kProductPrefix)
  }

  public static func getOSVersionString() -> String {
    ProcessInfo.processInfo.operatingSystemVersionString
  }

  public static func getServerDirectory() -> String { kServerDirectory }

  public static func getResourcesDirectory() -> String {
    Bundle.main.resourcePath ?? ""
  }

  /// Returns the serial number of the Mac (IOPlatformSerialNumber), or ""
  /// if failed. See TN1103. Always "" on iOS (no IOKit).
  public static func getSerialNumber() -> String {
    #if os(macOS)
      let platformExpert = IOServiceGetMatchingService(
        kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
      guard platformExpert != 0 else { return "" }
      defer { IOObjectRelease(platformExpert) }
      guard
        let value = IORegistryEntryCreateCFProperty(
          platformExpert, kIOPlatformSerialNumberKey as CFString, kCFAllocatorDefault, 0)?
          .takeRetainedValue() as? String
      else {
        return ""
      }
      return value
    #else
      return ""
    #endif
  }
}
