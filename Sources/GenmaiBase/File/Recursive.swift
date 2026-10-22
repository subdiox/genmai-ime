// Port of mozc/src/base/file/recursive.{h,cc} (3.35.6354). macOS (fts) path.
//
// The C++ code walks the tree with fts (no chdir, no stat, physical walk, one
// device). The port walks it with FileManager the same way: symbolic links are
// removed, not followed; directories are removed after their contents; errors
// on single entries are logged, not thrown.

import Foundation

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
    deleteTree(path)
  }

  private static func deleteTree(_ path: String) {
    // attributesOfItem does not follow a symbolic link at `path` (lstat).
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
      return  // FTS_NS: nothing to remove.
    }
    if attributes[.type] as? FileAttributeType == .typeDirectory {
      let children = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
      for child in children {
        deleteTree(FileUtil.joinPath(path, child))
      }
      removeDirectoryOrLog(path)  // FTS_DP: directory postorder
    } else {
      unlinkFileOrLog(path)
    }
  }
}
