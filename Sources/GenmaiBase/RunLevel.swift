// Port of mozc/src/base/run_level.{h,cc} (3.35.6354). Non-Windows semantics.

#if canImport(Darwin)
  import Darwin
#endif

public enum RunLevel {
  public enum RunLevelType: Int, Comparable, Sendable {
    case normal = 0  // normal process
    case restricted  // with timeout
    case deny  // do not launch Mozc

    public static func < (a: RunLevelType, b: RunLevelType) -> Bool { a.rawValue < b.rawValue }
  }

  /// request type
  public enum RequestType: Sendable {
    case client  // user is client
    case server  // user is server
    case renderer  // user is renderer
  }

  /// return the runlevel of current process
  public static func getRunLevel(_ type: RequestType) -> RunLevelType {
    if type == .server || type == .renderer {
      if geteuid() == 0 {
        // This process is started by root, or the executable is setuid to root.
        return .deny
      }
      if getuid() == 0 {
        // The executable is setuided to non-root and is started by root user?
        // This is unexpected. Returns DENY.
        return .deny
      }
      return .normal
    }
    // type is 'CLIENT'
    if geteuid() == 0 || getuid() == 0 {
      // When mozc.so is loaded into a privileged process, deny clients to use
      // dictionary_tool and config_dialog.
      return .deny
    }
    return .normal
  }

  public static func isValidClientRunLevel() -> Bool {
    getRunLevel(.client) <= .restricted
  }

  /// return false on Mac/Linux
  public static func isElevatedByUAC() -> Bool { false }

  /// return false always on Linux/Mac
  public static func setElevatedProcessDisabled(_ disable: Bool) -> Bool { false }

  /// return false always on Linux/Mac.
  public static func getElevatedProcessDisabled() -> Bool { false }
}
