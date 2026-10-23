// Port of mozc/src/base/file_util_test.cc (3.35.6354). Non-Windows parts.

import Foundation
import Testing

@testable import GenmaiBase

private func createTestFile(_ filename: String, _ data: String) throws {
  try FileUtil.setContents(filename, data)
}

@Suite struct FileUtilTest {
  @Test func createDirectory() throws {
    let tempDir = makeTempDirectoryOrDie()
    defer { withExtendedLifetime(tempDir) {} }
    try FileUtil.directoryExists(tempDir.path)
    // dirpath = FLAGS_test_tmpdir/testdir
    let dirpath = FileUtil.joinPath(tempDir.path, "testdir")

    // Delete dirpath, if it exists.
    try FileUtil.removeDirectoryIfExists(dirpath)
    #expect(!FileUtil.fileExistsOK(dirpath))

    // Create the directory.
    try FileUtil.createDirectory(dirpath)
    try FileUtil.directoryExists(dirpath)

    // Create the same directory again.
    try FileUtil.createDirectory(dirpath)

    // Delete the directory.
    try FileUtil.removeDirectory(dirpath)
    #expect(!FileUtil.fileExistsOK(dirpath))
  }

  @Test func directoryExists() throws {
    let tempDir = makeTempDirectoryOrDie()
    defer { withExtendedLifetime(tempDir) {} }
    try FileUtil.directoryExists(tempDir.path)
    let filepath = FileUtil.joinPath(tempDir.path, "testfile")

    // Delete filepath, if it exists.
    try FileUtil.unlinkIfExists(filepath)
    #expect(!FileUtil.fileExistsOK(filepath))

    // Create a file.
    try createTestFile(filepath, "test data")
    try FileUtil.fileExists(filepath)
    #expect(!FileUtil.directoryExistsOK(filepath))

    // Delete the file.
    try FileUtil.unlink(filepath)
    #expect(!FileUtil.fileExistsOK(filepath))
  }

  @Test func unlink() throws {
    let tempDir = makeTempDirectoryOrDie()
    defer { withExtendedLifetime(tempDir) {} }
    let filepath = FileUtil.joinPath(tempDir.path, "testfile")
    try FileUtil.unlinkIfExists(filepath)
    #expect(!FileUtil.fileExistsOK(filepath))

    try createTestFile(filepath, "simple test")
    try FileUtil.fileExists(filepath)
    try FileUtil.unlink(filepath)
    #expect(!FileUtil.fileExistsOK(filepath))
    try FileUtil.unlinkIfExists(filepath)
  }

  @Test func isEqualFile() throws {
    let tempDir = makeTempDirectoryOrDie()
    defer { withExtendedLifetime(tempDir) {} }
    let filename1 = FileUtil.joinPath(tempDir.path, "test1")
    let filename2 = FileUtil.joinPath(tempDir.path, "test2")
    #expect(throws: (any Error).self) { try FileUtil.isEqualFile(filename1, filename2) }
    try createTestFile(filename1, "test data1")
    #expect(throws: (any Error).self) { try FileUtil.isEqualFile(filename1, filename2) }
    try createTestFile(filename2, "test data1")
    #expect(try FileUtil.isEqualFile(filename1, filename2))

    try createTestFile(filename2, "test data1 test data1")
    #expect(try !FileUtil.isEqualFile(filename1, filename2))

    try createTestFile(filename2, "test data2")
    #expect(try !FileUtil.isEqualFile(filename1, filename2))
  }

  @Test func isEquivalent() throws {
    let tempDir = makeTempDirectoryOrDie()
    defer { withExtendedLifetime(tempDir) {} }
    let filename1 = FileUtil.joinPath(tempDir.path, "test1")
    let filename2 = FileUtil.joinPath(tempDir.path, "test2")
    #expect(throws: (any Error).self) { try FileUtil.isEquivalent(filename1, filename1) }
    #expect(throws: (any Error).self) { try FileUtil.isEquivalent(filename1, filename2) }

    try createTestFile(filename1, "test data")
    #expect(try FileUtil.isEquivalent(filename1, filename1))

    // filename2 doesn't exist, so the status is not OK.
    #expect(throws: (any Error).self) { try FileUtil.isEquivalent(filename1, filename2) }

    // filename2 exists but it's a different file.
    try createTestFile(filename2, "test data")
    #expect(try !FileUtil.isEquivalent(filename1, filename2))
  }

  @Test func copyFile() throws {
    let tempDir = makeTempDirectoryOrDie()
    defer { withExtendedLifetime(tempDir) {} }
    // just test rename operation works as intended
    let from = FileUtil.joinPath(tempDir.path, "copy_from")
    let to = FileUtil.joinPath(tempDir.path, "copy_to")
    try createTestFile(from, "simple test")
    try FileUtil.copyFile(from, to)
    #expect(try FileUtil.isEqualFile(from, to))

    try createTestFile(from, "overwrite test")
    try FileUtil.copyFile(from, to)
    #expect(try FileUtil.isEqualFile(from, to))
  }

  @Test func atomicRename() throws {
    let tempDir = makeTempDirectoryOrDie()
    defer { withExtendedLifetime(tempDir) {} }
    // just test rename operation works as intended
    let from = FileUtil.joinPath(tempDir.path, "atomic_rename_test_from")
    let to = FileUtil.joinPath(tempDir.path, "atomic_rename_test_to")

    // |from| is not found
    #expect(throws: (any Error).self) { try FileUtil.atomicRename(from, to) }
    try createTestFile(from, "test")
    try FileUtil.atomicRename(from, to)

    // from is deleted
    #expect(!FileUtil.fileExistsOK(from))
    try FileUtil.fileExists(to)
    #expect(try FileUtil.getContents(to) == "test")

    #expect(throws: (any Error).self) { try FileUtil.atomicRename(from, to) }

    try FileUtil.unlinkIfExists(from)
    try FileUtil.unlinkIfExists(to)

    // overwrite the file
    try createTestFile(from, "test")
    try createTestFile(to, "test")
    try FileUtil.atomicRename(from, to)
  }

  @Test func atomicRenameWhileReading() async throws {
    let tempDir = makeTempDirectoryOrDie()
    defer { withExtendedLifetime(tempDir) {} }
    let from = FileUtil.joinPath(tempDir.path, "atomic_rename_test_from")
    let to = FileUtil.joinPath(tempDir.path, "atomic_rename_test_to")
    try createTestFile(from, "new")
    try createTestFile(to, "old")

    // Keeps |to| open for a while in another task, e.g. like the user
    // dictionary reloader.
    let fd = open(to, O_RDONLY)
    #expect(fd >= 0)
    let reader = Task.detached {
      try? await Task.sleep(for: .milliseconds(50))
      close(fd)
    }
    try FileUtil.atomicRename(from, to)
    await reader.value

    #expect(!FileUtil.fileExistsOK(from))
    #expect(try FileUtil.getContents(to) == "new")
  }

  @Test func createHardLink() throws {
    let tempDir = makeTempDirectoryOrDie()
    defer { withExtendedLifetime(tempDir) {} }
    let filename1 = FileUtil.joinPath(tempDir.path, "test1")
    let filename2 = FileUtil.joinPath(tempDir.path, "test2")
    try createTestFile(filename1, "test data")
    try FileUtil.createHardLink(filename1, filename2)
    #expect(try FileUtil.isEquivalent(filename1, filename2))
    #expect(throws: (any Error).self) { try FileUtil.createHardLink(filename1, filename2) }
  }

  @Test func joinPath() {
    #expect(FileUtil.joinPath([]).isEmpty)
    #expect(FileUtil.joinPath(["foo"]) == "foo")
    #expect(FileUtil.joinPath(["foo", "bar"]) == "foo/bar")
    #expect(FileUtil.joinPath(["foo", "bar", "baz"]) == "foo/bar/baz")

    // Some path components end with delimiter.
    #expect(FileUtil.joinPath(["foo/", "bar", "baz"]) == "foo/bar/baz")
    #expect(FileUtil.joinPath(["foo", "bar/", "baz"]) == "foo/bar/baz")
    #expect(FileUtil.joinPath(["foo", "bar", "baz/"]) == "foo/bar/baz/")

    // Containing empty strings.
    #expect(FileUtil.joinPath(["", "", ""]).isEmpty)
    #expect(FileUtil.joinPath(["", "foo", "bar"]) == "foo/bar")
    #expect(FileUtil.joinPath(["foo", "", "bar"]) == "foo/bar")
    #expect(FileUtil.joinPath(["foo", "bar", ""]) == "foo/bar")

    #expect(FileUtil.joinPath(["foo/", "bar"]) == "foo/bar")
    #expect(FileUtil.joinPath(["foo", "bar/"]) == "foo/bar/")
    #expect(FileUtil.joinPath(["/foo", "bar"]) == "/foo/bar")
    #expect(FileUtil.joinPath(["/", "foo", "bar"]) == "/foo/bar")
    #expect(FileUtil.joinPath(["", "foo", "bar"]) == "foo/bar")

    // Separator in the beginning of the component will remain.
    #expect(FileUtil.joinPath(["foo", "/bar"]) == "foo//bar")
    #expect(FileUtil.joinPath(["foo/", "/bar"]) == "foo//bar")
  }

  @Test func dirname() {
    #expect(FileUtil.dirname("/foo/bar") == "/foo")
    #expect(FileUtil.dirname("/foo/bar/foo.txt") == "/foo/bar")
    #expect(FileUtil.dirname("foo.txt") == "")
    #expect(FileUtil.dirname("/") == "")
  }

  @Test func basename() {
    #expect(FileUtil.basename("/foo/bar") == "bar")
    #expect(FileUtil.basename("/foo/bar/foo.txt") == "foo.txt")
    #expect(FileUtil.basename("foo.txt") == "foo.txt")
    #expect(FileUtil.basename("./foo.txt") == "foo.txt")
    #expect(FileUtil.basename("./.foo.txt") == ".foo.txt")
    #expect(FileUtil.basename("/") == "")
    #expect(FileUtil.basename("foo/bar/buz/") == "")
  }

  @Test func normalizeDirectorySeparator() {
    #expect(FileUtil.normalizeDirectorySeparator("\\foo\\bar") == "\\foo\\bar")
    #expect(FileUtil.normalizeDirectorySeparator("/foo\\bar") == "/foo\\bar")
    #expect(FileUtil.normalizeDirectorySeparator("\\foo/bar") == "\\foo/bar")
    #expect(FileUtil.normalizeDirectorySeparator("/foo/bar") == "/foo/bar")
    #expect(FileUtil.normalizeDirectorySeparator("\\foo\\bar\\") == "\\foo\\bar\\")
    #expect(FileUtil.normalizeDirectorySeparator("/foo/bar/") == "/foo/bar/")
    #expect(FileUtil.normalizeDirectorySeparator("") == "")
    #expect(FileUtil.normalizeDirectorySeparator("/") == "/")
    #expect(FileUtil.normalizeDirectorySeparator("\\") == "\\")
  }

  @Test func getModificationTime() throws {
    let tempDir = makeTempDirectoryOrDie()
    defer { withExtendedLifetime(tempDir) {} }
    #expect(throws: (any Error).self) {
      try FileUtil.getModificationTime(FileUtil.joinPath(tempDir.path, "not_existent_file"))
    }

    let path = FileUtil.joinPath(tempDir.path, "testfile")
    try createTestFile(path, "content")
    let timeStamp1 = try FileUtil.getModificationTime(path)
    #expect(timeStamp1 != 0)

    let timeStamp2 = try FileUtil.getModificationTime(path)
    #expect(timeStamp1 == timeStamp2)
  }

  @Test func getAndSetContents() throws {
    let tempDir = makeTempDirectoryOrDie()
    defer { withExtendedLifetime(tempDir) {} }
    let filename = FileUtil.joinPath(tempDir.path, "test.txt")

    // File doesn't exist yet.
    do {
      _ = try FileUtil.getContents(filename)
      Issue.record("expected an error")
    } catch {
      #expect(error.statusCode == .notFound)
    }

    // Basic write and read test.
    try FileUtil.setContents(filename, "test")
    let unlinker = FileUnlinker(filename)
    #expect(try FileUtil.getContents(filename) == "test")

    // Overwrite test.
    try FileUtil.setContents(filename, "more tests!")
    #expect(try FileUtil.getContents(filename) == "more tests!")

    // Text mode write (no difference on macOS).
    try FileUtil.setContents(filename, "test\ntest\n")
    #expect(try FileUtil.getContents(filename) == "test\ntest\n")

    // Text mode read.
    try FileUtil.setContents(filename, "test\r\ntest\r\n")
    #expect(try FileUtil.getContents(filename) == "test\r\ntest\r\n")
    withExtendedLifetime(unlinker) {}
  }

  @Test func fileUnlinker() throws {
    let tempFile = try TempDirectory.default().createTempFile()
    defer { withExtendedLifetime(tempFile) {} }
    try FileUtil.setContents(tempFile.path, "test")
    do {
      let unlinker = FileUnlinker(tempFile.path)
      try FileUtil.fileExists(tempFile.path)
      withExtendedLifetime(unlinker) {}
    }
    #expect(!FileUtil.fileExistsOK(tempFile.path))
  }
}
