// Port of mozc/src/base/file/recursive_test.cc (3.35.6354).

import Testing
@testable import GenmaiBase

@Suite struct RecursiveTest {
  @Test func deleteRecursively() throws {
    let temp = TempDirectory.default()
    let dir = try temp.createTempDirectory()
    try FileUtil.setContents(FileUtil.joinPath(dir.path, "file1"), "")
    try FileUtil.setContents(FileUtil.joinPath(dir.path, "file2"), "")
    let dir2 = try dir.createTempDirectory()
    try FileUtil.setContents(FileUtil.joinPath(dir2.path, "file1"), "")
    try FileUtil.setContents(FileUtil.joinPath(dir2.path, "file2"), "")
    try FileRecursive.deleteRecursively(dir.path)
    #expect(throws: StatusError.self) { try FileUtil.directoryExists(dir.path) }
    do {
      try FileUtil.directoryExists(dir.path)
    } catch {
      #expect(error.statusCode == .notFound)
    }
  }

  @Test func deleteRecursivelyNonExistent() throws {
    let temp = TempDirectory.default()
    let dir = try temp.createTempDirectory()
    // Path leaf that doesn't exist.
    try FileRecursive.deleteRecursively(FileUtil.joinPath(dir.path, "non_existent"))
    // Path component that doesn't exist.
    try FileRecursive.deleteRecursively(
      FileUtil.joinPath([dir.path, "non_existent", "non_existent"]))
  }
}
