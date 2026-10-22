// Port of mozc/src/base/system_util.{h,cc} (3.35.6354). macOS code paths only
// (OSS "Mozc" branding).
//
// The user profile directory is ~/Library/Application Support/Genmai. It can be
// overridden globally (`setUserProfileDirectory`, as in C++) or for the
// current task only (`withUserProfileDirectory`), which is what tests should
// use because Swift Testing runs tests in parallel.

import Foundation
import Synchronization

public enum SystemUtil {
  // base/const.h (macOS, OSS branding).
  static let kGenmaiServerName = GenmaiConst.kGenmaiServerName
  static let kGenmaiRenderer = GenmaiConst.kGenmaiRenderer
  static let kGenmaiApp = GenmaiConst.kGenmaiApp

  private static let userProfileDir = Mutex("")
  private static let programInvocationName = Mutex("")
  @TaskLocal static var taskLocalUserProfileDirectory: String?

  private static func defaultUserProfileDirectory() -> String {
    let dir = MacUtil.getApplicationSupportDirectory()
    return FileUtil.joinPath(dir, "Genmai")
  }

  /// User profile directory (created if it doesn't exist).
  public static func getUserProfileDirectory() -> String {
    if let dir = taskLocalUserProfileDirectory {
      return dir
    }
    return userProfileDir.withLock { current in
      if !current.isEmpty {
        return current
      }
      let dir = defaultUserProfileDirectory()
      do {
        try FileUtil.createDirectory(dir)
      } catch let e as StatusError where e.code == .alreadyExists {
      } catch {
        GenmaiLog.error("Failed to create directory: \(dir): \(error)")
      }
      if !FileUtil.directoryExistsOK(dir) {
        GenmaiLog.error("User profile directory doesn't exist: \(dir)")
      }
      current = dir
      return current
    }
  }

  /// Logging directory (~/Library/Logs/Genmai on macOS).
  public static func getLoggingDirectory() -> String {
    let dir = MacUtil.getLoggingDirectory()
    do {
      try FileUtil.createDirectory(dir)
    } catch {
      GenmaiLog.error("\(error)")
    }
    return dir
  }

  /// Sets the user profile directory (global).
  public static func setUserProfileDirectory(_ path: String) {
    userProfileDir.withLock { $0 = path }
  }

  /// TESTONLY: overrides the user profile directory in the current task while
  /// running `body`.
  public static func withUserProfileDirectory<R>(
    _ path: String, _ body: () throws -> R
  ) rethrows -> R {
    try $taskLocalUserProfileDirectory.withValue(path, operation: body)
  }

  nonisolated(nonsending) public static func withUserProfileDirectory<R>(
    _ path: String, _ body: nonisolated(nonsending) () async throws -> R
  ) async rethrows -> R {
    try await $taskLocalUserProfileDirectory.withValue(path, operation: body)
  }

  /// Port of testing::TestWithTempUserProfile (testing/mozctest.h): runs
  /// `body` with a fresh temporary user profile directory, deleted afterwards.
  public static func withTempUserProfile<R>(_ body: (String) throws -> R) rethrows -> R {
    let dir = makeTempDirectoryOrDie()
    return try withUserProfileDirectory(dir.path) {
      try withExtendedLifetime(dir) { try body(dir.path) }
    }
  }

  nonisolated(nonsending) public static func withTempUserProfile<R>(
    _ body: nonisolated(nonsending) (String) async throws -> R
  ) async rethrows -> R {
    let dir = makeTempDirectoryOrDie()
    let result = try await withUserProfileDirectory(dir.path) { try await body(dir.path) }
    withExtendedLifetime(dir) {}
    return result
  }

  /// Returns the directory where the Mozc server is installed.
  public static func getServerDirectory() -> String {
    MacUtil.getServerDirectory()
  }

  /// Returns the path of the mozc server.
  public static func getServerPath() -> String {
    let serverPath = getServerDirectory()
    if serverPath.isEmpty {
      return ""
    }
    return FileUtil.joinPath(serverPath, kGenmaiServerName)
  }

  /// Returns the path of the mozc renderer.
  public static func getRendererPath() -> String {
    let serverPath = getServerDirectory()
    if serverPath.isEmpty {
      return ""
    }
    return FileUtil.joinPath(serverPath, kGenmaiRenderer)
  }

  /// Returns the path of the mozc tool.
  public static func getAppPath() -> String {
    let serverPath = getServerDirectory()
    if serverPath.isEmpty {
      return ""
    }
    return FileUtil.joinPath(serverPath, kGenmaiApp)
  }

  /// Returns the directory where the documents are installed.
  public static func getDocumentDirectory() -> String {
    getServerDirectory()
  }

  /// Returns the user name.
  public static func getUserNameAsString() -> String {
    var bufsize = sysconf(Int32(_SC_GETPW_R_SIZE_MAX))
    if bufsize == -1 {
      bufsize = 1024
    }
    var buf = [CChar](repeating: 0, count: bufsize)
    var pw = passwd()
    var ppw: UnsafeMutablePointer<passwd>?
    let r = getpwuid_r(geteuid(), &pw, &buf, buf.count, &ppw)
    precondition(r == 0 && ppw != nil, "getpwuid_r failed")
    return String(cString: pw.pw_name)
  }

  /// Returns the user SID (= user name on non-Windows).
  public static func getUserSidAsString() -> String {
    getUserNameAsString()
  }

  /// Returns the desktop name ("" on macOS).
  public static func getDesktopNameAsString() -> String {
    ""
  }

  /// Returns a string representing the OS version.
  public static func getOSVersionString() -> String {
    "MacOSX " + MacUtil.getOSVersionString()
  }

  /// Disables IME (no-op except on Windows).
  public static func disableIME() {}

  /// Returns the total physical memory in bytes (hw.memsize), 0 on failure.
  public static func getTotalPhysicalMemory() -> UInt64 {
    var mib: [Int32] = [CTL_HW, HW_MEMSIZE]
    var totalMemory: UInt64 = 0
    var size = MemoryLayout<UInt64>.size
    if sysctl(&mib, UInt32(mib.count), &totalMemory, &size, nil, 0) == -1 {
      GenmaiLog.error("sysctl with hw.memsize failed. errno: \(errno)")
      return 0
    }
    return totalMemory
  }

  public static func setProgramInvocationName(_ name: String) {
    programInvocationName.withLock { $0 = name }
  }

  public static func getProgramRunfilesDirectory() -> String {
    let name = programInvocationName.withLock { $0 }
    if name.isEmpty {
      return ""
    }
    return name + ".runfiles"
  }
}
