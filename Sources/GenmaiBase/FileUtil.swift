// Port of mozc/src/base/file_util.{h,cc} (3.35.6354). macOS (POSIX) code paths
// only.
//
// absl::Status-returning functions throw `StatusError`; StatusOr<T> functions
// return T or throw. The mock (`FileUtilInterface`) can be installed globally
// (`setMockForUnitTest`) or for the current task only (`withMock`), which
// is safe with Swift Testing's parallel execution.

import Foundation
import Synchronization

public typealias FileTimeStamp = UInt64

public protocol FileUtilInterface: AnyObject, Sendable {
  func createDirectory(_ path: String) throws
  func removeDirectory(_ dirname: String) throws
  func unlink(_ filename: String) throws
  func fileExists(_ filename: String) throws
  func directoryExists(_ dirname: String) throws
  func copyFile(_ from: String, _ to: String) throws
  func isEqualFile(_ filename1: String, _ filename2: String) throws -> Bool
  func isEquivalent(_ filename1: String, _ filename2: String) throws -> Bool
  func atomicRename(_ from: String, _ to: String) throws
  func createHardLink(_ from: String, _ to: String) throws
  func getModificationTime(_ filename: String) throws -> FileTimeStamp
  func readSymlink(_ filename: String) throws -> String
}

public enum FileUtil {
  private static let kFileDelimiter: Character = "/"
  private static let globalMock = Mutex<(any FileUtilInterface)?>(nil)
  @TaskLocal static var taskLocalMock: (any FileUtilInterface)?

  @inline(__always)
  private static var mock: (any FileUtilInterface)? {
    if let m = taskLocalMock { return m }
    return globalMock.withLock { $0 }
  }

  /// Creates a directory. Does not create directories in the way to the path.
  /// If the directory already exists, does nothing (non-Windows behavior).
  public static func createDirectory(_ path: String) throws {
    if let mock { return try mock.createDirectory(path) }
    // If the path already exists, returns OkStatus and does nothing.
    if (try? directoryExists(path)) != nil {
      return
    }
    if mkdir(path, 0o700) != 0 {
      throw StatusError.errno(errno, "mkdir failed")
    }
  }

  /// Removes an empty directory.
  public static func removeDirectory(_ dirname: String) throws {
    if let mock { return try mock.removeDirectory(dirname) }
    if rmdir(dirname) != 0 {
      throw StatusError.errno(errno, "rmdir failed")
    }
  }

  public static func removeDirectoryIfExists(_ dirname: String) throws {
    do {
      try fileExists(dirname)
    } catch let e as StatusError where e.code == .notFound {
      return
    }
    try removeDirectory(dirname)
  }

  /// Removes a file.
  public static func unlink(_ filename: String) throws {
    if let mock { return try mock.unlink(filename) }
    if Darwin.unlink(filename) != 0 {
      throw StatusError.unknown("unlink failed: errno = \(errno)")
    }
  }

  /// Removes a file. Returns normally when `filename` doesn't exist.
  public static func unlinkIfExists(_ filename: String) throws {
    do {
      try fileExists(filename)
    } catch let e as StatusError where e.code == .notFound {
      return
    }
    try unlink(filename)
  }

  /// Logs error message on failure (i.e., it ignores any error).
  public static func unlinkOrLogError(_ filename: String) {
    do {
      try unlink(filename)
    } catch {
      GenmaiLog.error("Cannot unlink \(filename): \(error)")
    }
  }

  /// Succeeds if a file or a directory with the name exists.
  public static func fileExists(_ filename: String) throws {
    if let mock { return try mock.fileExists(filename) }
    var s = stat()
    if stat(filename, &s) == 0 {
      return
    }
    throw StatusError.errno(errno, "Cannot stat \(filename)")
  }

  /// Bool convenience for `fileExists` (`FileExists(...).ok()`).
  public static func fileExistsOK(_ filename: String) -> Bool {
    (try? fileExists(filename)) != nil
  }

  /// Succeeds if the directory exists.
  public static func directoryExists(_ dirname: String) throws {
    if let mock { return try mock.directoryExists(dirname) }
    var s = stat()
    if stat(dirname, &s) == 0 {
      if (s.st_mode & S_IFMT) == S_IFDIR {
        return
      }
      throw StatusError.notFound("Path exists but it's not a directory")
    }
    throw StatusError.errno(errno, "Cannot stat \(dirname)")
  }

  /// Bool convenience for `directoryExists` (`DirectoryExists(...).ok()`).
  public static func directoryExistsOK(_ dirname: String) -> Bool {
    (try? directoryExists(dirname)) != nil
  }

  /// Copies a file to another file. The destination file will be overwritten
  /// if exists.
  public static func copyFile(_ from: String, _ to: String) throws {
    if let mock { return try mock.copyFile(from, to) }
    guard let input = FileManager.default.contents(atPath: from) else {
      throw StatusError.unknown("Can't open input file \(from)")
    }
    guard let fp = fopen(to, "wb") else {
      throw StatusError.unknown("Can't open output file \(to)")
    }
    let written = input.withUnsafeBytes { buf -> Int in
      buf.isEmpty ? 0 : fwrite(buf.baseAddress, 1, buf.count, fp)
    }
    let closeResult = fclose(fp)
    if written != input.count || closeResult != 0 {
      throw StatusError.unknown("Can't write data")
    }
  }

  /// Compares the contents of two given files. Ignores the difference between
  /// their path strings. Returns true if both files have same contents.
  public static func isEqualFile(_ filename1: String, _ filename2: String) throws -> Bool {
    if let mock { return try mock.isEqualFile(filename1, filename2) }
    let mmap1 = try Mmap.map(filename1, .readOnly)
    let mmap2 = try Mmap.map(filename2, .readOnly)
    return mmap1.buffer.elementsEqual(mmap2.buffer)
  }

  /// Compares the two filenames point to the same file. Symbolic/hard links
  /// are considered. Throws if either of files doesn't exist.
  public static func isEquivalent(_ filename1: String, _ filename2: String) throws -> Bool {
    if let mock { return try mock.isEquivalent(filename1, filename2) }
    // If either of filename1 or filename2 does not exist, an error is returned.
    if fileExistsOK(filename1) != fileExistsOK(filename2) {
      throw StatusError.unknown("No such file or directory")
    }
    // std::filesystem::equivalent: compares st_dev and st_ino (following
    // symlinks); an error if neither exists.
    var s1 = stat()
    var s2 = stat()
    let r1 = stat(filename1, &s1)
    let e1 = errno
    let r2 = stat(filename2, &s2)
    let e2 = errno
    if r1 != 0 && r2 != 0 {
      throw StatusError.unknown("\(e1) \(String(cString: strerror(e1)))")
    }
    if r1 != 0 || r2 != 0 {
      _ = e2
      return false
    }
    return s1.st_dev == s2.st_dev && s1.st_ino == s2.st_ino
  }

  /// Moves/Renames a file atomically.
  public static func atomicRename(_ from: String, _ to: String) throws {
    if let mock { return try mock.atomicRename(from, to) }
    // macOS: use rename(2), but rename(2) on macOS is not properly implemented,
    // atomic rename is POSIX spec though.
    if rename(from, to) != 0 {
      let err = errno
      throw StatusError.unknown("errno(\(err)): \(String(cString: strerror(err)))")
    }
  }

  /// Creates a hard link. This fails if the filesystem does not support hard
  /// link or the target file already exists.
  public static func createHardLink(_ from: String, _ to: String) throws {
    if let mock { return try mock.createHardLink(from, to) }
    if link(from, to) != 0 {
      let err = errno
      throw StatusError.unknown("\(String(cString: strerror(err))) (code=\(err))")
    }
  }

  /// Joins the give path components using the OS-specific path delimiter.
  public static func joinPath(_ components: [String]) -> String {
    var output = ""
    for component in components {
      if component.isEmpty {
        continue
      }
      if !output.isEmpty && output.last != kFileDelimiter {
        output.append(kFileDelimiter)
      }
      output += component
    }
    return output
  }

  /// Joins the given two path components using the OS-specific path delimiter.
  public static func joinPath(_ path1: String, _ path2: String) -> String {
    joinPath([path1, path2])
  }

  public static func dirname(_ filename: String) -> String {
    guard let p = filename.utf8.lastIndex(of: UInt8(ascii: "/")) else {
      return ""
    }
    return String(filename[..<p])
  }

  public static func basename(_ filename: String) -> String {
    guard let p = filename.utf8.lastIndex(of: UInt8(ascii: "/")) else {
      return filename
    }
    return String(filename[filename.utf8.index(after: p)...])
  }

  /// Returns the normalized path by replacing '/' with '\\' on Windows.
  /// Does nothing on other platforms.
  public static func normalizeDirectorySeparator(_ path: String) -> String {
    path
  }

  /// Returns the modification time (std::filesystem::file_time_type count,
  /// i.e. nanoseconds since the epoch on macOS libc++).
  public static func getModificationTime(_ filename: String) throws -> FileTimeStamp {
    if let mock { return try mock.getModificationTime(filename) }
    var s = stat()
    if stat(filename, &s) != 0 {
      let err = errno
      throw StatusError.errno(err, "last_write_time failed: \(filename): \(String(cString: strerror(err)))")
    }
    let ns = Int64(s.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(s.st_mtimespec.tv_nsec)
    return FileTimeStamp(bitPattern: ns)
  }

  /// Returns the file path resolved from the given symbolic link.
  public static func readSymlink(_ filename: String) throws -> String {
    if let mock { return try mock.readSymlink(filename) }
    var buf = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
    let n = readlink(filename, &buf, buf.count - 1)
    if n < 0 {
      let err = errno
      throw StatusError.unknown("\(String(cString: strerror(err))) (code=\(err))")
    }
    return String(decoding: buf[0..<n].map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }

  /// Reads the contents of the file `filename` and returns it (binary).
  public static func getContentBytes(_ filename: String) throws -> [UInt8] {
    guard let fp = fopen(filename, "rb") else {
      throw StatusError.errno(errno, "Cannot open \(filename)")
    }
    defer { fclose(fp) }
    var result: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      let n = fread(&chunk, 1, chunk.count, fp)
      if n > 0 { result.append(contentsOf: chunk[0..<n]) }
      if n < chunk.count {
        if ferror(fp) != 0 {
          throw StatusError.errno(errno, "Cannot read \(filename)")
        }
        break
      }
    }
    return result
  }

  /// Reads the contents of the file `filename` and returns it as a String
  /// (invalid UTF-8 is replaced with U+FFFD; use `getContentBytes` for binary).
  public static func getContents(_ filename: String) throws -> String {
    String(decoding: try getContentBytes(filename), as: UTF8.self)
  }

  /// Writes the data provided in `content` to the file `filename`, overwriting
  /// any existing content.
  public static func setContents(_ filename: String, _ content: some Collection<UInt8>) throws {
    guard let fp = fopen(filename, "wb") else {
      throw StatusError.errno(errno, "Cannot open \(filename)")
    }
    let bytes = Array(content)
    let written = bytes.isEmpty ? 0 : fwrite(bytes, 1, bytes.count, fp)
    let err = errno
    if fclose(fp) != 0 || written != bytes.count {
      throw StatusError.errno(err, "Cannot write \(bytes.count) bytes to \(filename)")
    }
  }

  public static func setContents(_ filename: String, _ content: String) throws {
    try setContents(filename, Array(content.utf8))
  }

  /// Sets a mock for unittest (global).
  public static func setMockForUnitTest(_ mock: (any FileUtilInterface)?) {
    globalMock.withLock { $0 = mock }
  }

  /// TESTONLY: Uses `mock` in the current task while running `body`.
  public static func withMock<R>(_ mock: any FileUtilInterface, _ body: () throws -> R) rethrows -> R {
    try $taskLocalMock.withValue(mock, operation: body)
  }
}

/// RAII wrapper for a file. Unlinks the file when this instance is released.
public final class FileUnlinker {
  private let filename: String

  public init(_ filename: String) {
    self.filename = filename
  }

  deinit {
    FileUtil.unlinkOrLogError(filename)
  }
}
