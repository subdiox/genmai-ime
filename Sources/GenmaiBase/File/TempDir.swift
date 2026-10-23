// Port of mozc/src/base/file/temp_dir.{h,cc} (3.35.6354). POSIX code path.
//
// The C++ move-only RAII types become final classes whose deinit performs the
// cleanup.

#if canImport(Darwin)
  import Darwin
#endif

/// TempFile represents a temporary file created by TempDirectory.
/// Deletes the file when this object is released.
/// It doesn't result in an error when the file doesn't exit unlike
/// FileUnlinker.
/// Unlike a C++ object it can be released right after the last use of
/// `path` (optimized builds do): keep it alive with withExtendedLifetime
/// while the file is used. The same holds for TempDirectory.
public final class TempFile {
  public let path: String
  /// Delete a temp file by default.
  public var keep = false

  public init(_ path: String) {
    self.path = path
  }

  deinit {
    if keep {
      return
    }
    do {
      try FileUtil.unlinkIfExists(path)
    } catch {
      GenmaiLog.warning("Failed to remove temporary file (\(path)) :\(error)")
    }
  }
}

public final class TempDirectory {
  /// The temporary directory path.
  public let path: String
  /// The default value for keep is true here because there are more code
  /// paths where we don't want to delete the directory (also for safety).
  public var keep: Bool

  private init(_ path: String, keep: Bool = true) {
    self.path = path
    self.keep = keep
  }

  deinit {
    if keep {
      return
    }
    do {
      try FileRecursive.deleteRecursively(path)
    } catch {
      GenmaiLog.warning("Failed to remove temporary directory (\(path)) :\(error)")
    }
  }

  private static func tryTempDirectory(_ dir: String) -> Bool {
    FileUtil.directoryExistsOK(dir)
  }

  private static func tryTempEnv(_ envname: String) -> String? {
    let env = Environ.getEnv(envname)
    if env.isEmpty {
      return nil
    }
    if tryTempDirectory(env) {
      return env
    }
    return nil
  }

  /// Default tries several common temporary paths and returns the path to the
  /// first found. It returns an empty string when it couldn't find a
  /// directory.
  public static func `default`() -> TempDirectory {
    // Try TEST_TMPDIR first. This is set by Blaze.
    if let tmpdir = tryTempEnv("TEST_TMPDIR") {
      return TempDirectory(tmpdir)
    }
    if let tmpdir = tryTempEnv("TMPDIR") {
      return TempDirectory(tmpdir)
    }
    if tryTempDirectory("/tmp") {
      return TempDirectory("/tmp")
    }
    // We ran out of options. Return the current directory as the best
    // alternative.
    var cwd = [CChar](repeating: 0, count: Int(PATH_MAX))
    if getcwd(&cwd, cwd.count) != nil {
      let dir = cString(cwd)
      if tryTempDirectory(dir) {
        return TempDirectory(dir)
      }
    }
    return TempDirectory("")
  }

  /// Creates a unique temporary file in the directory and returns it.
  public func createTempFile() throws -> TempFile {
    var template = Array(FileUtil.joinPath(path, "genmai-XXXXXX").utf8CString)  // six X's
    let fd = mkstemp(&template)
    if fd < 0 {
      throw StatusError.errno(errno, "mkstemp failed")
    }
    if close(fd) != 0 {
      throw StatusError.errno(errno, "close failed")
    }
    return TempFile(cString(template))
  }

  /// Creates a unique temporary directory in the directory and returns it.
  /// The new directory is deleted (recursively) when released.
  public func createTempDirectory() throws -> TempDirectory {
    var template = Array(FileUtil.joinPath(path, "genmai-XXXXXX").utf8CString)  // six X's
    if mkdtemp(&template) == nil {
      throw StatusError.errno(errno, "mkdtemp failed")
    }
    return TempDirectory(cString(template), keep: false)
  }
}

/// Port of testing::MakeTempDirectoryOrDie (testing/mozctest.h): creates a
/// temporary directory under TempDirectory.default() or crashes.
public func makeTempDirectoryOrDie() -> TempDirectory {
  do {
    return try TempDirectory.default().createTempDirectory()
  } catch {
    fatalError("Failed to create a temporary directory: \(error)")
  }
}

private func cString(_ array: [CChar]) -> String {
  let bytes = array.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
  return String(decoding: bytes, as: UTF8.self)
}
