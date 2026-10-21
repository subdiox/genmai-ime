// Replacement for LOG / DLOG / VLOG (absl/log and base/vlog) used by the
// GenmaiBase ports: messages go to os.Logger at debug level (no-op in
// release-like usage).

import os

public enum GenmaiLog {
  static let logger = Logger(subsystem: "io.github.subdiox.genmai", category: "GenmaiBase")

  public static func error(_ message: @autoclosure () -> String) {
    let m = message()
    logger.debug("ERROR: \(m, privacy: .public)")
  }

  public static func warning(_ message: @autoclosure () -> String) {
    let m = message()
    logger.debug("WARNING: \(m, privacy: .public)")
  }

  public static func info(_ message: @autoclosure () -> String) {
    let m = message()
    logger.debug("\(m, privacy: .public)")
  }
}
