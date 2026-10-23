// Port of mozc/src/base/multifile_test.cc (3.35.6354).

import Testing

@testable import GenmaiBase

@Suite struct InputMultiFileTest {
  @Test func openNonexistentFilesTest() {
    // Empty string
    do {
      let multfile = InputMultiFile("")
      #expect(multfile.readLine() == nil)
      #expect(multfile.readLine() == nil)
      #expect(multfile.readLine() == nil)
    }

    let tempDir = makeTempDirectoryOrDie()
    defer { withExtendedLifetime(tempDir) {} }

    // Single path
    do {
      let path = FileUtil.joinPath(tempDir.path, "this_file_does_not_exist")
      let multfile = InputMultiFile(path)
      #expect(multfile.readLine() == nil)
      #expect(multfile.readLine() == nil)
      #expect(multfile.readLine() == nil)
    }

    // Multiple paths
    do {
      let filenames = [
        FileUtil.joinPath(tempDir.path, "these_files"),
        FileUtil.joinPath(tempDir.path, "do_not"),
        FileUtil.joinPath(tempDir.path, "exist"),
      ]
      let multfile = InputMultiFile(filenames.joined(separator: ","))
      #expect(multfile.readLine() == nil)
      #expect(multfile.readLine() == nil)
      #expect(multfile.readLine() == nil)
    }
  }

  @Test func readSingleFileTest() {
    let tempDir = makeTempDirectoryOrDie()
    defer { withExtendedLifetime(tempDir) {} }
    let path = FileUtil.joinPath(tempDir.path, "i_am_a_test_file")

    // Create a test file
    var expectedLines: [String] = []
    let kNumLines = 10
    do {
      let ofs = OutputFileStream(path)
      for i in 0..<kNumLines {
        let line = "Hi, line \(i)"
        expectedLines.append(line)
        ofs.writeLine(line)
      }
    }
    #expect(expectedLines.count == kNumLines)

    // Read lines
    let multfile = InputMultiFile(path)
    for i in 0..<kNumLines {
      #expect(multfile.readLine() == expectedLines[i])
    }
    #expect(multfile.readLine() == nil)  // Check if no more lines remain
    #expect(multfile.readLine() == nil)
    #expect(multfile.readLine() == nil)
  }

  @Test func readMultipleFilesTest() {
    let tempDir = makeTempDirectoryOrDie()
    defer { withExtendedLifetime(tempDir) {} }
    let kNumFile = 3
    let kNumLinesPerFile = 10

    // Create test files
    var paths: [String] = []
    var expectedLines: [String] = []
    do {
      var serialLineNo = 0
      for fileno in 0..<kNumFile {
        let path = FileUtil.joinPath(tempDir.path, "testfile\(fileno)")
        paths.append(path)
        let ofs = OutputFileStream(path)
        for _ in 0..<kNumLinesPerFile {
          serialLineNo += 1
          let line = "Hi, line \(serialLineNo)"
          expectedLines.append(line)
          ofs.writeLine(line)
        }
      }
    }
    #expect(expectedLines.count == kNumLinesPerFile * kNumFile)

    // Read lines
    let multfile = InputMultiFile(paths.joined(separator: ","))
    for i in 0..<(kNumFile * kNumLinesPerFile) {
      #expect(multfile.readLine() == expectedLines[i])
    }
    #expect(multfile.readLine() == nil)  // Check if no more lines remain
    #expect(multfile.readLine() == nil)
    #expect(multfile.readLine() == nil)
  }
}
