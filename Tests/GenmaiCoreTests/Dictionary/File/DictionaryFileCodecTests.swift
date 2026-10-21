// Port of mozc/src/dictionary/file/codec_test.cc (3.35.6354).

import GenmaiBase
import Testing

@testable import GenmaiCore

@Suite struct DictionaryFileCodecTests {
  private func addSection(
    _ codec: DictionaryFileCodec, _ name: String, _ data: String, _ sections: inout [DictionaryFileSection]
  ) {
    sections.append(DictionaryFileSection(image: DataView(copying: data), name: codec.getSectionName(name)))
  }

  private func findSection(
    _ codec: DictionaryFileCodec, _ sections: [DictionaryFileSection], _ name: String
  ) -> Int? {
    let nameFind = codec.getSectionName(name)
    return sections.firstIndex { $0.name == nameFind }
  }

  private func checkValue(_ section: DictionaryFileSection, _ expected: String) -> Bool {
    section.image.array == Array(expected.utf8)
  }

  private func writeAndRead(_ codec: DictionaryFileCodec) throws {
    let tempDir = TempDirectory.default()
    let testFile = try tempDir.createTempFile()
    do {
      var writeSections: [DictionaryFileSection] = []
      addSection(codec, "Section 0", "Value 0 test", &writeSections)
      addSection(codec, "Section 1", "Value 1 test test", &writeSections)
      try FileUtil.setContents(testFile.path, codec.writeSections(writeSections))
    }
    // sections will reference this buffer.
    let buf = DataView(copying: try FileUtil.getContentBytes(testFile.path))
    let sections = try codec.readSections(buf)
    try #require(sections.count == 2)
    var index = try #require(findSection(codec, sections, "Section 0"))
    #expect(index == 0)
    #expect(checkValue(sections[index], "Value 0 test"))

    index = try #require(findSection(codec, sections, "Section 1"))
    #expect(index == 1)
    #expect(checkValue(sections[index], "Value 1 test test"))
  }

  @Test func defaultTest() throws {
    try writeAndRead(DictionaryFileCodec())
  }

  @Test func randomizedCodecTest() throws {
    try writeAndRead(DictionaryFileCodec())
  }

  // Swift-only: malformed images are rejected.
  @Test func readSectionsErrors() throws {
    let codec = DictionaryFileCodec()
    #expect(throws: StatusError.self) { try codec.readSections(DataView(copying: [UInt8](repeating: 0, count: 8))) }
    #expect(throws: StatusError.self) { try codec.readSections(DataView(copying: [UInt8](repeating: 0, count: 16))) }
    var image = codec.writeSections([])
    #expect(try codec.readSections(DataView(copying: image)).isEmpty)
    image.append(contentsOf: [0, 0, 0, 0])
    #expect(throws: StatusError.self) { try codec.readSections(DataView(copying: image)) }
  }
}
