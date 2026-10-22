// Port of mozc/src/base/config_file_stream_test.cc (3.35.6354).

import Foundation
import Testing

@testable import GenmaiBase

// Returns true if |inputStream| is at the end of stream.
private func isEof(_ inputStream: InputFileStream) -> Bool {
  inputStream.peek() == nil && inputStream.get() == nil && inputStream.eof
}

// Serialized because memory:// files are process-global.
@Suite(.serialized) struct ConfigFileStreamTest {
  @Test func onMemoryFiles() {
    SystemUtil.withTempUserProfile { _ in
      let kData = "data"
      let kPath = "memory://test"
      #expect(ConfigFileStream.getFileName(kPath).isEmpty)
      ConfigFileStream.atomicUpdate(kPath, kData)
      do {
        let ifs = ConfigFileStream.legacyOpen(kPath)
        #expect(ifs != nil)
        guard let ifs else { return }
        let buf = ifs.read(kData.utf8.count)
        #expect(String(decoding: buf, as: UTF8.self) == kData)
        #expect(isEof(ifs))
      }

      ConfigFileStream.clearOnMemoryFiles()
      do {
        let ifs = ConfigFileStream.legacyOpen(kPath)
        #expect(ifs != nil)
        guard let ifs else { return }
        #expect(isEof(ifs))
      }
    }
  }

  @Test func atomicUpdate() throws {
    try SystemUtil.withTempUserProfile { (_: String) throws in
      let prefixedFilename = "user://atomic_update_test"
      let filename = ConfigFileStream.getFileName(prefixedFilename)
      let tmpFilename = filename + ".tmp"

      #expect(!FileUtil.fileExistsOK(filename))
      #expect(!FileUtil.fileExistsOK(tmpFilename))

      let contents = "123\n2\n3"
      ConfigFileStream.atomicUpdate(prefixedFilename, contents)
      try FileUtil.fileExists(filename)
      #expect(!FileUtil.fileExistsOK(tmpFilename))
      #expect((try? FileUtil.getContents(filename)) == contents)

      let newContents = "246\n4\n6"
      ConfigFileStream.atomicUpdate(prefixedFilename, newContents)
      try FileUtil.fileExists(filename)
      #expect(!FileUtil.fileExistsOK(tmpFilename))
      #expect((try? FileUtil.getContents(filename)) == newContents)

      try FileUtil.unlinkIfExists(filename)
    }
  }

  @Test func openReadBinary() throws {
    try SystemUtil.withTempUserProfile { (_: String) throws in
      // At first, generate a binary data file in (temporary) user directory
      // so that we can load it as "user://my_binary_file.dat"
      let kTestFileName = "my_binary_file.dat"
      let testFilePath = FileUtil.joinPath(SystemUtil.getUserProfileDirectory(), kTestFileName)

      let kBinaryData: [UInt8] = Array(" \u{0D} \n \u{0D}\n \u{00} ".utf8)
      try FileUtil.setContents(testFilePath, kBinaryData)
      try FileUtil.fileExists(testFilePath)
      do {
        let ifs = ConfigFileStream.openReadBinary("user://" + kTestFileName)
        #expect(ifs != nil)
        guard let ifs else { return }
        let buf = ifs.read(kBinaryData.count)
        // Check if all the data are loaded as binary mode.
        #expect(Array(buf) == kBinaryData)
        #expect(isEof(ifs))
      }
    }
  }

  @Test func openReadText() throws {
    try SystemUtil.withTempUserProfile { (_: String) throws in
      let kTestFileName = "my_text_file.dat"
      let testFilePath = FileUtil.joinPath(SystemUtil.getUserProfileDirectory(), kTestFileName)
      let kSourceTextData = "ab\rc\nd\r\ne"
      try FileUtil.setContents(testFilePath, kSourceTextData)
      try FileUtil.fileExists(testFilePath)

      let kExpectedLines = ["ab\rc", "d\r", "e"]
      let ifs = ConfigFileStream.openReadText("user://" + kTestFileName)
      #expect(ifs != nil)
      guard let ifs else { return }
      var lineNumber = 0  // note that this is 1-origin.
      while let line = ifs.getlineBytes() {
        lineNumber += 1
        #expect(lineNumber <= kExpectedLines.count)
        if lineNumber <= kExpectedLines.count {
          #expect(Array(line) == Array(kExpectedLines[lineNumber - 1].utf8))
        }
      }
      #expect(lineNumber == kExpectedLines.count)
    }
  }

  // Not in the C++ test: system:// files are embedded.
  @Test func systemFiles() {
    #expect(ConfigFileStreamData.kFileData.count == 27)
    let ifs = ConfigFileStream.openReadText("system://romanji-hiragana.tsv")
    #expect(ifs != nil)
    let first = ifs?.getline()
    #expect(first?.isEmpty == false)
    #expect(ConfigFileStream.openReadText("system://no_such_file.tsv") == nil)
    let msime = ConfigFileStream.openReadBinary("system://ms-ime.tsv")?.readAll() ?? []
    let onDisk =
      (try? FileUtil.getContentBytes(
        vendorPath("Vendor/mozc/src/data/keymap/ms-ime.tsv"))) ?? [1]
    #expect(msime == onDisk)
  }
}

/// Absolute path of a file in the repository.
func vendorPath(_ relative: String, file: String = #filePath) -> String {
  // Tests/GenmaiBaseTests/<file>.swift -> repository root
  // Resolve symlinks so that the path is inside the repository.
  var url =
    realpath(file, nil).map { p in
      defer { free(p) }
      return String(cString: p)
    } ?? file
  for _ in 0..<3 {
    url = FileUtil.dirname(url)
  }
  return FileUtil.joinPath(url, relative)
}
