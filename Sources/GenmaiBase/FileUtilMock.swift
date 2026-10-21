// Port of mozc/src/base/file_util_mock.h (3.35.6354).
//
// Lives in the library target so that the tests of every module can use it.
// Install it with `FileUtil.withMock(mock) { ... }` (task-local) or
// `FileUtil.setMockForUnitTest(mock)` (global).

import Synchronization

public final class FileUtilMock: FileUtilInterface, Sendable {
  private struct State {
    // Use FileTimeStamp as time stamp and also file id.
    // 0 means that the file is removed.
    var files: [String: FileTimeStamp] = [:]
    var baseId: FileTimeStamp = 1_000_000_000
    var dirs: [String: Bool] = [:]
    var canonicalPaths: [String: String] = [:]

    mutating func createFile(_ path: String) {
      files[path] = baseId
      baseId += 100_000
    }

    func fileExists(_ filename: String) -> Bool {
      if let v = files[filename], v > 0 { return true }
      return false
    }

    func directoryExists(_ dirname: String) -> Bool {
      dirs[dirname] ?? false
    }

    mutating func createDirectory(_ path: String) throws {
      if fileExists(path) {
        throw StatusError.alreadyExists(path)
      }
      dirs[path] = true
    }
  }

  private let state = Mutex(State())

  public init() {}

  /// This is not an override function.
  public func createFile(_ path: String) {
    state.withLock { $0.createFile(path) }
  }

  public func createDirectory(_ path: String) throws {
    try state.withLock { try $0.createDirectory(path) }
  }

  public func removeDirectory(_ dirname: String) throws {
    try state.withLock { s in
      if s.fileExists(dirname) {
        throw StatusError.notFound(dirname)
      }
      s.dirs[dirname] = false
    }
  }

  public func unlink(_ filename: String) throws {
    try state.withLock { s in
      if s.directoryExists(filename) {
        throw StatusError.failedPrecondition("\(filename) is a directory")
      }
      s.files[filename] = 0
    }
  }

  public func fileExists(_ filename: String) throws {
    try state.withLock { s in
      if !s.fileExists(filename) { throw StatusError.notFound(filename) }
    }
  }

  public func directoryExists(_ dirname: String) throws {
    try state.withLock { s in
      if !s.directoryExists(dirname) { throw StatusError.notFound(dirname) }
    }
  }

  public func fileOrDirectoryExists(_ path: String) throws {
    try state.withLock { s in
      if !(s.fileExists(path) || s.directoryExists(path)) {
        throw StatusError.notFound(path)
      }
    }
  }

  public func copyFile(_ from: String, _ to: String) throws {
    try state.withLock { s in
      if !s.fileExists(from) {
        throw StatusError.notFound(from)
      }
      s.files[to] = s.files[from] ?? 0
    }
  }

  public func isEqualFile(_ filename1: String, _ filename2: String) throws -> Bool {
    try state.withLock { s in
      if !s.fileExists(filename1) { throw StatusError.notFound(filename1) }
      if !s.fileExists(filename2) { throw StatusError.notFound(filename2) }
      return s.files[filename1] == s.files[filename2]
    }
  }

  public func isEquivalent(_ filename1: String, _ filename2: String) throws -> Bool {
    try state.withLock { s in
      let canonical1 = s.canonicalPaths[filename1] ?? filename1
      let canonical2 = s.canonicalPaths[filename2] ?? filename2
      // If either of files does not exist, an error is returned.
      if s.fileExists(canonical1) != s.fileExists(canonical2) {
        throw StatusError.unknown("No such file or directory")
      }
      return canonical1 == canonical2
    }
  }

  public func atomicRename(_ from: String, _ to: String) throws {
    try state.withLock { s in
      if s.fileExists(from) {
        s.files[to] = s.files[from] ?? 0
        s.files[from] = 0
        return
      }
      if s.directoryExists(from) {
        s.dirs[to] = s.dirs[from] ?? false
        s.dirs[from] = false
        return
      }
      throw StatusError.notFound("\(from) doesn't exist")
    }
  }

  public func createHardLink(_ from: String, _ to: String) throws {
    try state.withLock { s in
      // Error if `from` doesn't exist.
      if !(s.fileExists(from) || s.directoryExists(from)) {
        throw StatusError.notFound(from)
      }
      // Error if `to` already exists.
      if s.fileExists(to) || s.directoryExists(to) {
        throw StatusError.alreadyExists(to)
      }
      s.canonicalPaths[to] = from
      if s.fileExists(from) {
        s.createFile(to)
        return
      }
      try s.createDirectory(to)
    }
  }

  public func getModificationTime(_ filename: String) throws -> FileTimeStamp {
    try state.withLock { s in
      if !s.fileExists(filename) { throw StatusError.notFound(filename) }
      return s.files[filename] ?? 0
    }
  }

  public func readSymlink(_ filename: String) throws -> String {
    // The mock does not support symbolic links. It returns the same filename.
    filename
  }
}
