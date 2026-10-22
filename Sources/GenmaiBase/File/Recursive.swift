// Port of mozc/src/base/file/recursive.{h,cc} (3.35.6354). macOS (fts) path.

#if canImport(Darwin)
  import Darwin
#endif

public enum FileRecursive {
  private static func removeDirectoryOrLog(_ path: String) {
    do {
      try FileUtil.removeDirectory(path)
    } catch {
      if error.statusCode != .notFound {
        GenmaiLog.error("Cannot remove directory \(path):\(error)")
      }
    }
  }

  private static func unlinkFileOrLog(_ path: String) {
    do {
      try FileUtil.unlink(path)
    } catch {
      if error.statusCode != .notFound {
        GenmaiLog.error("Cannot unlink \(path):\(error)")
      }
    }
  }

  /// Recursively delete all files under path including itself
  /// (mozc::file::DeleteRecursively).
  public static func deleteRecursively(_ path: String) throws {
    // fts is not POSIX, but it's available on both Linux and MacOS.
    let pathCString = strdup(path)
    defer { free(pathCString) }
    var files: [UnsafeMutablePointer<CChar>?] = [pathCString, nil]
    // - FTS_NOCHDIR: don't change current directory.
    // - FTS_NOSTAT: don't stat(2).
    // - FTS_PHYSICAL: don't follow symlinks.
    // - FTS_XDEV: don't descend into a different device.
    guard let ftsp = fts_open(&files, FTS_NOCHDIR | FTS_NOSTAT | FTS_PHYSICAL | FTS_XDEV, nil)
    else {
      throw StatusError.errno(errno, "fts_open failed")
    }
    defer {
      if fts_close(ftsp) < 0 {
        GenmaiLog.error("fts_close failed : errno = \(errno)")
      }
    }
    errno = 0
    while let ent = fts_read(ftsp) {
      let entPath = String(cString: ent.pointee.fts_path)
      switch Int32(ent.pointee.fts_info) {
      case FTS_DP:  // directory postorder
        removeDirectoryOrLog(entPath)
      case FTS_F, FTS_NSOK, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
        unlinkFileOrLog(entPath)
      default:
        break
      }
      errno = 0
    }
    if errno != 0 {
      throw StatusError.errno(errno, "fts_read failed")
    }
  }
}
