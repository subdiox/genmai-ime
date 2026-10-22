// Port of mozc/src/base/file/temp_dir_test.cc (3.35.6354).

import Testing

@testable import GenmaiBase

@Suite struct TempDirectoryTest {
  // Tracks created paths and checks that they are deleted at the end
  // (the C++ fixture destructor).
  final class Tracker {
    var paths: [String] = []

    func createFile(_ t: TempDirectory) -> TempFile {
      let f = try! t.createTempFile()
      #expect(f.path.hasPrefix(t.path))
      #expect(f.path != t.path)
      paths.append(f.path)
      return f
    }

    func createDirectory(_ t: TempDirectory) -> TempDirectory {
      let d = try! t.createTempDirectory()
      #expect(d.path.hasPrefix(t.path))
      #expect(d.path != t.path)
      paths.append(d.path)
      return d
    }

    func verifyDeleted() {
      for path in paths {
        #expect(!FileUtil.fileExistsOK(path), "\(path)")
      }
    }
  }

  @Test func `default`() throws {
    let tracker = Tracker()
    var dirToKeepPath = ""
    do {
      let tempDir = TempDirectory.default()
      #expect(!tempDir.path.isEmpty)

      // Try to write something to a temporary file.
      let kTestContent = "testing temp dir"
      let tempFile = tracker.createFile(tempDir)
      try FileUtil.setContents(tempFile.path, kTestContent)
      #expect(try FileUtil.getContents(tempFile.path) == kTestContent)

      // Create some more directories and files.
      let nestedDir = tracker.createDirectory(tempDir)
      let nested1 = tracker.createFile(nestedDir)
      let nested2 = tracker.createFile(nestedDir)
      do {
        // Test keep().
        let dirToKeep = tracker.createDirectory(nestedDir)
        dirToKeepPath = dirToKeep.path
        #expect(!dirToKeep.keep)
        dirToKeep.keep = true
        #expect(dirToKeep.keep)
      }
      // This directory should continue to exist after going out of scope.
      #expect(FileUtil.directoryExistsOK(dirToKeepPath))

      let of2 = OutputFileStream(FileUtil.joinPath(nestedDir.path, "test"))
      #expect(of2.good)
      of2.close()
      let nestedNestedDir = tracker.createDirectory(nestedDir)
      let nestedNested = tracker.createFile(nestedNestedDir)
      withExtendedLifetime((tempFile, nested1, nested2, nestedNested, nestedNestedDir)) {}
    }
    // dir_to_keep was kept, but its parent was deleted recursively.
    tracker.verifyDeleted()
  }

  @Test func testTmpDirEnv() {
    let tracker = Tracker()
    do {
      // Set a random temp directory to TEST_TMPDIR.
      let tempDir = TempDirectory.default()
      let testDir = tracker.createDirectory(tempDir)
      let envMock = EnvironMock()
      Environ.withMock(envMock) {
        do {
          envMock.setEnv("TEST_TMPDIR", testDir.path)
          let newTempDir = TempDirectory.default()
          #expect(newTempDir.path == testDir.path)
        }
        // Check that the deinit doesn't delete the directory when
        // constructed by default().
        #expect(FileUtil.directoryExistsOK(testDir.path))

        // Clear TEST_TMPDIR so we can test other code paths.
        envMock.setEnv("TEST_TMPDIR", "")
        let systemTempDir = TempDirectory.default()
        #expect(!systemTempDir.path.isEmpty)
      }
    }
    tracker.verifyDeleted()
  }
}
