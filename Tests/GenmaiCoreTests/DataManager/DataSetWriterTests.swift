// Port of mozc/src/data_manager/dataset_writer_test.cc (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

@Suite struct DatasetWriterTest {
  private static func entry(_ name: String, _ offset: UInt64, _ size: UInt64)
    -> Genmai_DataSetMetadata.Entry
  {
    var e = Genmai_DataSetMetadata.Entry()
    e.name = name
    e.offset = offset
    e.size = size
    return e
  }

  @Test func write() throws {
    let cBytes = DataManagerTestSupport.cBytes
    // Create a dummy file to be packed.
    let tempDir = try TempDirectory.default().createTempDirectory()
    defer { withExtendedLifetime(tempDir) {} }
    tempDir.keep = false
    let inPath = FileUtil.joinPath(tempDir.path, "in")
    try FileUtil.setContents(inPath, [0x6D, 0x00, 0x7A, 0x63, 0xEF] as [UInt8])
    defer { try? FileUtil.unlinkIfExists(inPath) }

    // Generate a packed file into |actual|.
    var w = DataSetWriter(magic: "magic")
    w.add("data8", 8, cBytes(#"data8 \x00\x01"#))
    w.add("data16", 16, cBytes(#"data16 \xAB\xCD\xEF"#))
    w.add("data32", 32, cBytes(#"data32 \x00\xAB\x0A\x0D\x0A"#))
    w.add("data64", 64, cBytes(#"data64 \x09\x09\x00\x00"#))
    w.add("data128", 128, cBytes("data128 abcdefg"))
    w.add("data256", 256, cBytes("data256 xyz"))

    try w.addFile("file8", 8, inPath)
    try w.addFile("file16", 16, inPath)
    try w.addFile("file32", 32, inPath)
    try w.addFile("file64", 64, inPath)
    try w.addFile("file128", 128, inPath)
    try w.addFile("file256", 256, inPath)

    let actual = w.finish()

    // Define the expected binary image.
    let pad = { (n: Int) in [UInt8](repeating: 0, count: n) }
    let mozc = cBytes(#"m\x00zc\xEF"#)
    var dataChunk = cBytes("magic")  // offset 0, size 5
    dataChunk += cBytes(#"data8 \x00\x01"#)  // offset 5, size 8
    dataChunk += pad(1)  // offset 13, size 1 (padding)
    dataChunk += cBytes(#"data16 \xAB\xCD\xEF"#)  // offset 14, size 10
    dataChunk += cBytes(#"data32 \x00\xAB\x0A\x0D\x0A"#)  // offset 24, size 12
    dataChunk += pad(4)  // offset 36, size 4 (padding)
    dataChunk += cBytes(#"data64 \x09\x09\x00\x00"#)  // offset 40, size 11
    dataChunk += pad(13)  // offset 51, size 13 (padding)
    dataChunk += cBytes("data128 abcdefg")  // offset 64, size 15
    dataChunk += pad(17)  // offset 79, size 17 (padding)
    dataChunk += cBytes("data256 xyz")  // offset 96, size 11
    dataChunk += mozc  // offset 107, size 5 (file8)
    dataChunk += mozc  // offset 112, size 5 (file16)
    dataChunk += pad(3)  // offset 117, size 3 (padding)
    dataChunk += mozc  // offset 120, size 5 (file32)
    dataChunk += pad(3)  // offset 125, size 3 (padding)
    dataChunk += mozc  // offset 128, size 5 (file64)
    dataChunk += pad(11)  // offset 133, size 11 (padding)
    dataChunk += mozc  // offset 144 size 5 (file128)
    dataChunk += pad(11)  // offset 149, size 11 (padding)
    dataChunk += mozc  // offset 160, size 5 (file256)

    var metadata = Genmai_DataSetMetadata()
    metadata.entries = [
      Self.entry("data8", 5, 8),
      Self.entry("data16", 14, 10),
      Self.entry("data32", 24, 12),
      Self.entry("data64", 40, 11),
      Self.entry("data128", 64, 15),
      Self.entry("data256", 96, 11),
      Self.entry("file8", 107, 5),
      Self.entry("file16", 112, 5),
      Self.entry("file32", 120, 5),
      Self.entry("file64", 128, 5),
      Self.entry("file128", 144, 5),
      Self.entry("file256", 160, 5),
    ]
    let metadataChunk: [UInt8] = try metadata.serializedBytes()
    var expected = dataChunk
    expected += metadataChunk
    expected += Util.serializeUint64(UInt64(metadataChunk.count))
    expected += UnverifiedSHA1.makeDigest(expected)
    expected += Util.serializeUint64(UInt64(expected.count + 8))

    // Compare the results.
    #expect(actual == expected)
  }
}
