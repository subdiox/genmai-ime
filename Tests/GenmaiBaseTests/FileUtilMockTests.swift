// Port of mozc/src/base/file_util_mock_test.cc (3.35.6354).

import Testing

@testable import GenmaiBase

@Suite struct FileUtilMockTest {
  @Test func directoryMockTests() throws {
    let mock = FileUtilMock()
    try FileUtil.withMock(mock) {
      try FileUtil.createDirectory("/tmp/mozc")
      try FileUtil.removeDirectory("/tmp/mozc")
      #expect(!FileUtil.directoryExistsOK("/tmp/no_mozc"))
      #expect(!FileUtil.directoryExistsOK("/tmp/"))  // Limitation of mock.
    }
  }

  @Test func fileMockTests() throws {
    let mock = FileUtilMock()
    try FileUtil.withMock(mock) {
      mock.createFile("/mozc/file.txt")
      try FileUtil.unlink("/mozc/file.txt")
      #expect(!FileUtil.fileExistsOK("/mozc/file.txt"))

      mock.createFile("/mozc/file1.txt")
      mock.createFile("/mozc/file2.txt")
      #expect(try FileUtil.isEqualFile("/mozc/file1.txt", "/mozc/file2.txt") == false)
      try FileUtil.copyFile("/mozc/file2.txt", "/mozc/file3.txt")
      #expect(try FileUtil.isEqualFile("/mozc/file2.txt", "/mozc/file3.txt") == true)

      try FileUtil.atomicRename("/mozc/file3.txt", "/mozc/file4.txt")
      #expect(!FileUtil.fileExistsOK("/mozc/file3.txt"))
      try FileUtil.fileExists("/mozc/file4.txt")
      #expect(try FileUtil.isEqualFile("/mozc/file2.txt", "/mozc/file4.txt") == true)

      let time1 = try FileUtil.getModificationTime("/mozc/file1.txt")
      let time2 = try FileUtil.getModificationTime("/mozc/file2.txt")
      #expect(time1 != time2)
      #expect(throws: (any Error).self) { try FileUtil.getModificationTime("/mozc/file3.txt") }
      let time4 = try FileUtil.getModificationTime("/mozc/file4.txt")
      #expect(time2 == time4)
    }
  }

  @Test func hardLinkTests() throws {
    let mock = FileUtilMock()
    try FileUtil.withMock(mock) {
      // # Hard link for files.
      #expect(try FileUtil.isEquivalent("/mozc/file1.txt", "/mozc/file1.txt") == true)
      #expect(try FileUtil.isEquivalent("/mozc/file1.txt", "/mozc/file2.txt") == false)

      // file1 does not exist.
      #expect(throws: (any Error).self) {
        try FileUtil.createHardLink("/mozc/file1.txt", "/mozc/file2.txt")
      }
      mock.createFile("/mozc/file1.txt")
      try FileUtil.createHardLink("/mozc/file1.txt", "/mozc/file2.txt")
      #expect(try FileUtil.isEquivalent("/mozc/file1.txt", "/mozc/file2.txt") == true)

      // file2 already exists.
      #expect(throws: (any Error).self) {
        try FileUtil.createHardLink("/mozc/file1.txt", "/mozc/file2.txt")
      }
      #expect(try FileUtil.isEquivalent("/mozc/file1.txt", "/mozc/file2.txt") == true)

      // # Hard link for directories.
      #expect(try FileUtil.isEquivalent("/mozc/dir1", "/mozc/dir1") == true)
      #expect(try FileUtil.isEquivalent("/mozc/dir1", "/mozc/dir2") == false)

      // dir1 does not exist.
      #expect(throws: (any Error).self) { try FileUtil.createHardLink("/mozc/dir1", "/mozc/dir2") }
      try FileUtil.createDirectory("/mozc/dir1")
      try FileUtil.createHardLink("/mozc/dir1", "/mozc/dir2")
      #expect(try FileUtil.isEquivalent("/mozc/dir1", "/mozc/dir2") == true)

      // dir2 already exists.
      #expect(throws: (any Error).self) { try FileUtil.createHardLink("/mozc/dir1", "/mozc/dir2") }
      #expect(try FileUtil.isEquivalent("/mozc/dir1", "/mozc/dir2") == true)
    }
  }

  @Test func isEquivalentTests() throws {
    let mock = FileUtilMock()
    try FileUtil.withMock(mock) {
      let kFile1 = "/mozc/file1.txt"
      let kFile2 = "/mozc/file2.txt"
      #expect(try FileUtil.isEquivalent(kFile1, kFile1) == true)
      #expect(try FileUtil.isEquivalent(kFile1, kFile2) == false)

      mock.createFile(kFile1)
      #expect(try FileUtil.isEquivalent(kFile1, kFile1) == true)
      #expect(throws: (any Error).self) { try FileUtil.isEquivalent(kFile1, kFile2) }

      try FileUtil.createHardLink(kFile1, kFile2)
      #expect(try FileUtil.isEquivalent(kFile1, kFile2) == true)
    }
  }
}
