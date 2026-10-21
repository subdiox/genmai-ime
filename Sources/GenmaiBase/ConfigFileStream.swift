// Port of mozc/src/base/config_file_stream.{h,cc} (3.35.6354).
//
// A class for user-configurable file object
//
// read filename and return a stream object.
// filename format:
//
// A) system file embedded in the binary (see ConfigFileStreamData.swift)
//   system://ms-ime.tsv
//   system://kotoeri.tsv
//
// B) user file. expanded into $(USER_PROFILE_DIR)/file_name
//   user://foo.tsv
//   user://foo.bar
//
// C) file -- should only be enabled in debug build
//   file:///foo/bar/foo.tsv
//
// D) on-memory -- for debug.  Does not store to the disk at all.
//   memory://foo.tsv
//   memory://foo.bar

import Synchronization

public enum ConfigFileStream {
  private static let kSystemPrefix = "system://"
  private static let kUserPrefix = "user://"
  private static let kFilePrefix = "file://"
  private static let kMemoryPrefix = "memory://"

  private static let onMemoryFileMap = Mutex<[String: [UInt8]]>([:])

  /// Open |filename| as a text file with read permission.
  public static func openReadText(_ filename: String) -> InputFileStream? {
    open(filename)
  }

  /// Open |filename| as a binary file with read permission.
  public static func openReadBinary(_ filename: String) -> InputFileStream? {
    open(filename)
  }

  /// Mozc 1.3 and prior had had this method; do not use in new code.
  public static func legacyOpen(_ filename: String) -> InputFileStream? {
    open(filename)
  }

  private static func stripPrefix(_ s: String, _ prefix: String) -> String {
    s.hasPrefix(prefix) ? String(s.dropFirst(prefix.count)) : s
  }

  private static func open(_ filename: String) -> InputFileStream? {
    // system://foo.bar.txt
    if filename.hasPrefix(kSystemPrefix) {
      let newFilename = stripPrefix(filename, kSystemPrefix)
      for entry in ConfigFileStreamData.kFileData where newFilename == entry.name {
        return InputFileStream(bytes: entry.data)
      }
      // user://foo.bar.txt
    } else if filename.hasPrefix(kUserPrefix) {
      let newFilename = FileUtil.joinPath(
        SystemUtil.getUserProfileDirectory(), stripPrefix(filename, kUserPrefix))
      let ifs = InputFileStream(newFilename)
      return ifs.good ? ifs : nil
      // file:///foo.map
    } else if filename.hasPrefix(kFilePrefix) {
      let newFilename = stripPrefix(filename, kFilePrefix)
      let ifs = InputFileStream(newFilename)
      return ifs.good ? ifs : nil
    } else if filename.hasPrefix(kMemoryPrefix) {
      let data = onMemoryFileMap.withLock { $0[filename] ?? [] }
      return InputFileStream(bytes: data)
    } else {
      GenmaiLog.warning("\(filename) has no prefix. open from localfile")
      let ifs = InputFileStream(filename)
      return ifs.good ? ifs : nil
    }
    return nil
  }

  /// Update the specified config filename (formatted as above) with
  /// the |newBinaryContents| atomically. Returns true if the update
  /// succeeds. Note that this method uses binary mode to update |filename|.
  @discardableResult
  public static func atomicUpdate(_ filename: String, _ newBinaryContents: some Collection<UInt8>) -> Bool {
    if filename.hasPrefix(kMemoryPrefix) {
      let bytes = Array(newBinaryContents)
      onMemoryFileMap.withLock { $0[filename] = bytes }
      return true
    } else if filename.hasPrefix(kSystemPrefix) {
      GenmaiLog.error("Cannot update system:// files.")
      return false
    }
    // We should save the new config first,
    // as we may rewrite the original config according to platform.
    // The original config should be platform independent.
    let realFilename = getFileName(filename)
    if realFilename.isEmpty {
      return false
    }
    let tmpFilename = realFilename + ".tmp"
    do {
      try FileUtil.setContents(tmpFilename, newBinaryContents)
    } catch {
      GenmaiLog.error("Cannot write the contents to \(tmpFilename): \(error)")
      return false
    }
    do {
      try FileUtil.atomicRename(tmpFilename, realFilename)
    } catch {
      GenmaiLog.error("AtomicRename failed: \(error); from: \(tmpFilename), to: \(realFilename)")
      return false
    }
    return true
  }

  @discardableResult
  public static func atomicUpdate(_ filename: String, _ newContents: String) -> Bool {
    atomicUpdate(filename, Array(newContents.utf8))
  }

  /// if prefix is system:// or memory:// return "".
  public static func getFileName(_ filename: String) -> String {
    if filename.hasPrefix(kSystemPrefix) || filename.hasPrefix(kMemoryPrefix) {
      return ""
    } else if filename.hasPrefix(kUserPrefix) {
      return FileUtil.joinPath(
        SystemUtil.getUserProfileDirectory(), stripPrefix(filename, kUserPrefix))
    } else if filename.hasPrefix(kFilePrefix) {
      // Note: the C++ code strips kUserPrefix here (not kFilePrefix), so the
      // "file://" prefix is kept. Ported as is.
      return stripPrefix(filename, kUserPrefix)
    } else {
      GenmaiLog.warning("\(filename) has no prefix. open from localfile")
      return filename
    }
  }

  /// Clear all memory:// files.  This is a utility method for testing.
  public static func clearOnMemoryFiles() {
    onMemoryFileMap.withLock { $0.removeAll() }
  }
}
