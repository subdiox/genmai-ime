// Port of mozc/src/dictionary/file/dictionary_file_test.cc (3.35.6354).

import GenmaiBase
import Testing

@testable import GenmaiCore

@Suite struct DictionaryFileTests {
  @Test func basic() throws {
    let tempDir = try TempDirectory.default().createTempDirectory()
    let dfn = FileUtil.joinPath(tempDir.path, "test-dictionary")
    let fn1 = FileUtil.joinPath(tempDir.path, "sec1")
    let fn2 = FileUtil.joinPath(tempDir.path, "sec2")

    try FileUtil.setContents(fn1, "0123456789")
    try FileUtil.setContents(fn2, "9876543210")

    let codec = DictionaryFileCodec()

    do {
      let builder = DictionaryFileBuilder(codec)
      #expect(builder.addSectionFromFile("sec1", fn1))
      #expect(builder.addSectionFromFile("sec2", fn2))
      #expect(!builder.addSectionFromFile("sec2", fn2))
      try builder.writeImageToFile(dfn)
    }

    try FileUtil.fileExists(dfn)

    do {
      let df = DictionaryFile(codec)
      try df.openFromFile(dfn)
      let data1 = try #require(df.getSection("sec1"))
      #expect(data1.count == 10)
      #expect(data1.string == "0123456789")
      let data2 = df.getSection("sec2")
      #expect(data2 != nil)
      #expect(data2?.count == 10)
      #expect(data2?.string == "9876543210")
      let data3 = df.getSection("sec3")
      #expect(data3 == nil)
    }

    try FileUtil.unlink(dfn)
    try FileUtil.unlink(fn1)
    try FileUtil.unlink(fn2)
  }
}
