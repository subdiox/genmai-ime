// Port of mozc/src/base/process_mutex.{h,cc} (3.35.6354). POSIX (fcntl) path.
//
// Process-wide named mutex class:
// Make a simple process-wide named mutex using file locking.
// Useful to prevent a process from being instantiated twice or more.
//
// Example:
//   let foo = ProcessMutex("foo")
//   if !foo.lock() {
//     // process foo is already running
//     exit(-1)
//   }

#if canImport(Darwin)
import Darwin
#endif
import Synchronization

public final class ProcessMutex: Sendable {
  private struct State {
    var locked = false
    var filename: String
  }

  private let state: Mutex<State>

  public init(_ name: String) {
    state = Mutex(State(filename: ProcessMutex.createProcessMutexFileName(name)))
  }

  deinit {
    _ = unlock()
  }

  private static func createProcessMutexFileName(_ name: String) -> String {
    let basename = "." + name + ".lock"
    return FileUtil.joinPath(SystemUtil.getUserProfileDirectory(), basename)
  }

  /// return false if the process is already locked
  public func lock() -> Bool {
    lockAndWrite("")
  }

  /// Lock the mutex file and write some message to this file
  public func lockAndWrite(_ message: String) -> Bool {
    state.withLock {
      if $0.locked {
        return false
      }
      $0.locked = Self.lockAndWriteInternal($0.filename, message)
      return $0.locked
    }
  }

  /// always return true at this moment.
  @discardableResult
  public func unlock() -> Bool {
    state.withLock {
      if !$0.locked {
        return true
      }
      Self.unlockInternal($0.filename)
      $0.locked = false
      return true
    }
  }

  /// return lock filename
  /// filename: <user_profile>/.<name>.lock
  public var lockFilename: String {
    get { state.withLock { $0.filename } }
    set { state.withLock { $0.filename = newValue } }
  }

  public var locked: Bool {
    state.withLock { $0.locked }
  }

  private static func lockAndWriteInternal(_ filename: String, _ message: String) -> Bool {
    let fd: Int32
    do {
      fd = try FileLockManager.shared.lock(filename)
    } catch {
      GenmaiLog.error("\(error)")
      return false
    }
    if !message.isEmpty {
      let bytes = Array(message.utf8)
      if write(fd, bytes, bytes.count) != bytes.count {
        GenmaiLog.error("Cannot write message: \(message)")
        unlockInternal(filename)
        return false
      }
    }
    // changed it to read only mode.
    chmod(filename, 0o400)
    return true
  }

  private static func unlockInternal(_ filename: String) {
    do {
      try FileLockManager.shared.unlock(filename)
    } catch {
      GenmaiLog.warning("\(error)")
    }
  }
}

// Special workaround for the bad treatment of fcntl.
// Basically, fcntl provides "per-process" file-locking.
// When a process has multiple fds on the same file,
// file lock is released if one fd is closed. This is not
// an expected behavior for Mozc.
//
// FileLockManager a wrapper class providing per-filename
// file locking implemented upon fcntl. Multiple threads on
// the same process share one fd for file locking.
//
// We will be able to use flock() instead of fcntl since,
// flock() provides "per-fd" file locking. However, we don't
// use it because flock() doesn't work on NFS.
private final class FileLockManager: Sendable {
  static let shared = FileLockManager()

  private let fdmap = Mutex<[String: Int32]>([:])

  func lock(_ filename: String) throws -> Int32 {
    try fdmap.withLock { fdmap in
      if filename.isEmpty {
        throw StatusError.invalidArgument("filename is empty")
      }
      if fdmap[filename] != nil {
        throw StatusError.failedPrecondition("already locked")
      }
      chmod(filename, 0o600)  // write temporary
      let fd = open(filename, O_RDWR | O_CREAT | O_TRUNC, 0o600)
      if fd < 0 {
        throw StatusError.errno(errno, "open() failed")
      }
      var command = flock()
      command.l_type = Int16(F_WRLCK)
      command.l_whence = Int16(SEEK_SET)
      command.l_start = 0
      command.l_len = 0
      let result = fcntl(fd, F_SETLK, &command)
      if result < 0 {  // failed
        close(fd)
        throw StatusError.failedPrecondition(
          "Already locked. Another server is already running?")
      }
      fdmap[filename] = fd
      return fd
    }
  }

  func unlock(_ filename: String) throws {
    try fdmap.withLock { fdmap in
      guard let fd = fdmap.removeValue(forKey: filename) else {
        throw StatusError.failedPrecondition("\(filename) is not locked")
      }
      close(fd)
      FileUtil.unlinkOrLogError(filename)
    }
  }
}
