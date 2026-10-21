// Port of mozc/src/base/process.{h,cc} (3.35.6354), macOS branch.
//
// Deviations from C++:
// - Only the POSIX / __APPLE__ code paths are ported (no Win32 / Linux /
//   Android / wasm branches).
// - WaitProcess is `async`: it polls with Task.sleep (suspends instead of
//   blocking the thread).
// - `mozc::Process` is named `GenmaiProcess` so that it does not shadow
//   Foundation.Process in modules that import GenmaiBase.

import Darwin
import Foundation

public enum GenmaiProcess {
  /// Opens `url` with the default browser. `url` must start with http://,
  /// https:// or file://.
  public static func openBrowser(_ url: String) -> Bool {
    // url must start with http:// or https:// or file://
    if !url.hasPrefix("http://") && !url.hasPrefix("https://") && !url.hasPrefix("file://") {
      return false
    }
    return MacProcess.openBrowserForMac(url)
  }

  /// Spawns `path` with the space separated arguments `arg`. If `path` is an
  /// application bundle, it is opened with NSWorkspace (without arguments,
  /// like the C++). Returns the child pid in `pid` (0 for bundles).
  @discardableResult
  public static func spawnProcess(_ path: String, _ arg: String, _ pid: inout Int) -> Bool {
    let argTmp = arg.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

    var statbuf = stat()
    if stat(path, &statbuf) != 0 {
      GenmaiLog.error("Can't stat \(path): \(String(cString: strerror(errno)))")
      return false
    }

    // Check if the "path" is an application or not.  If it's an
    // application, do a special process using mac_process.mm.
    if (statbuf.st_mode & S_IFMT) == S_IFDIR && path.utf8.count > 4 && path.hasSuffix(".app") {
      // In mac launchApplication cannot accept any arguments.
      return MacProcess.openApplication(path)
    }

    var tmpPid: pid_t = 0
    // Spawn new process.
    // NOTE:
    // posix_spawn returns 0 even if kGenmaiServer doesn't exist, because
    // the return value of posix_spawn is basically determined
    // by the return value of fork().
    var cArgs: [UnsafeMutablePointer<CChar>?] = ([path] + argTmp).map { strdup($0) }
    cArgs.append(nil)
    defer {
      for p in cArgs { free(p) }
    }
    let result = posix_spawn(&tmpPid, path, nil, nil, cArgs, environ)
    if result != 0 {
      GenmaiLog.error("posix_spawn failed: \(String(cString: strerror(result)))")
    }
    pid = Int(tmpPid)
    return result == 0
  }

  @discardableResult
  public static func spawnProcess(_ path: String, _ arg: String) -> Bool {
    var pid = 0
    return spawnProcess(path, arg, &pid)
  }

  /// Spawns `filename` in the server directory.
  @discardableResult
  public static func spawnGenmaiProcess(_ filename: String, _ arg: String, _ pid: inout Int) -> Bool {
    spawnProcess(FileUtil.joinPath(SystemUtil.getServerDirectory(), filename), arg, &pid)
  }

  @discardableResult
  public static func spawnGenmaiProcess(_ filename: String, _ arg: String) -> Bool {
    var pid = 0
    return spawnGenmaiProcess(filename, arg, &pid)
  }

  /// Waits for the process `pid` to terminate within `timeout` msec
  /// (negative = forever). Returns true if the process is not found.
  public static func waitProcess(_ pid: Int, _ timeout: Int) async -> Bool {
    if pid == 0 {
      GenmaiLog.warning("pid is 0. ignored")
      return true
    }
    if timeout == 0 {
      GenmaiLog.error("timeout is 0")
      return false
    }
    let processId = pid_t(truncatingIfNeeded: pid)
    let kPollingDuration = 250
    var leftTime = timeout < 0 ? 1 : timeout
    while leftTime > 0 {
      try? await Task.sleep(for: .milliseconds(kPollingDuration))
      if kill(processId, 0) != 0 {
        if errno == EPERM {
          return false  // access defined
        }
        return true  // process not found
      }
      if timeout > 0 {
        leftTime -= kPollingDuration
      }
    }
    GenmaiLog.error("\(pid) didn't terminate within \(timeout) msec")
    return false
  }

  /// Returns true if the process `pid` is alive. Returns `defaultResult` if
  /// the status cannot be determined.
  public static func isProcessAlive(_ pid: Int, _ defaultResult: Bool) -> Bool {
    if pid == 0 {
      return defaultResult
    }
    let kSig: Int32 = 0
    if kill(pid_t(truncatingIfNeeded: pid), kSig) == -1 {
      if errno == EPERM || errno == EINVAL {
        // permission denied or invalid signal.
        return defaultResult
      }
      return false
    }
    return true
  }

  /// On Linux/Mac, there is no way to check the status of thread id from
  /// other process.
  public static func isThreadAlive(_ threadId: Int, _ defaultResult: Bool) -> Bool {
    defaultResult
  }

  /// Launches the error message dialog of GenmaiTool.
  public static func launchErrorMessageDialog(_ errorType: String) -> Bool {
    if !MacProcess.launchErrorMessageDialog(errorType) {
      GenmaiLog.error("cannot error message dialog")
      return false
    }
    return true
  }
}
