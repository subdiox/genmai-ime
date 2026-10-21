// Port of mozc/src/data_manager/dataset_reader_test.cc (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import Testing
@testable import GenmaiCore

@Suite struct DataSetReaderTest {
  static let kTestMagicNumber: [UInt8] = [0x6D, 0x61, 0x00, 0x67, 0x69, 0x63]  // "ma\0gic"
  static let kGoogle: [UInt8] = Array("GOOGLE".utf8)
  static let kGenmai: [UInt8] = [0x6D, 0x00, 0x7A, 0x63, 0xEF]  // "m\0zc\xEF"

  @Test func validData() {
    var w = DataSetWriter(magic: Self.kTestMagicNumber)
    w.add("google", 16, Self.kGoogle)
    w.add("mozc", 64, Self.kGenmai)
    let image = DataView(copying: w.finish())

    var r = DataSetReader()
    #expect(DataSetReader.verifyChecksum(image))
    do { let ok = r.initialize(image, magic: Self.kTestMagicNumber); #expect(ok) }

    #expect(r.get("google")?.array == Self.kGoogle)
    #expect(r.getOffsetAndSize("google").map { [$0.offset, $0.size] } == [6, Self.kGoogle.count])
    #expect(r.get("mozc")?.array == Self.kGenmai)
    #expect(r.getOffsetAndSize("mozc").map { [$0.offset, $0.size] } == [16, Self.kGenmai.count])

    #expect(r.get("") == nil)
    #expect(r.get("foo") == nil)
    #expect(r.getOffsetAndSize("") == nil)
    #expect(r.getOffsetAndSize("foo") == nil)
  }

  @Test func invalidMagicString() {
    var r = DataSetReader()
    do { let ok = r.initialize(DataView(copying: ""), magic: Self.kTestMagicNumber); #expect(!ok) }
    do { let ok = r.initialize(DataView(copying: "abc"), magic: Self.kTestMagicNumber); #expect(!ok) }
    do { let ok = r.initialize(DataView(copying: "this is a text file"), magic: Self.kTestMagicNumber); #expect(!ok) }
  }

  @Test func brokenMetadata() {
    var r = DataSetReader()
    let kContent = Array("content and metadata".utf8)

    // Only magic number, no metadata.
    #expect(!DataSetReader.verifyChecksum(DataView(copying: Self.kTestMagicNumber)))
    do { let ok = r.initialize(DataView(copying: Self.kTestMagicNumber), magic: Self.kTestMagicNumber); #expect(!ok) }

    // Metadata size is too small.
    var data = DataView(copying: Self.kTestMagicNumber + kContent + Util.serializeUint64(0))
    #expect(!DataSetReader.verifyChecksum(data))
    do { let ok = r.initialize(data, magic: Self.kTestMagicNumber); #expect(!ok) }

    // Metadata size is too small.
    data = DataView(copying: Self.kTestMagicNumber + kContent + Util.serializeUint64(4))
    #expect(!DataSetReader.verifyChecksum(data))
    do { let ok = r.initialize(data, magic: Self.kTestMagicNumber); #expect(!ok) }

    // Metadata size is too large.
    data = DataView(copying: Self.kTestMagicNumber + kContent + Util.serializeUint64(UInt64.max))
    #expect(!DataSetReader.verifyChecksum(data))
    do { let ok = r.initialize(data, magic: Self.kTestMagicNumber); #expect(!ok) }

    // Metadata chunk is not a serialized protobuf.
    data = DataView(
      copying: Self.kTestMagicNumber + kContent + Util.serializeUint64(UInt64(kContent.count)))
    #expect(!DataSetReader.verifyChecksum(data))
    do { let ok = r.initialize(data, magic: Self.kTestMagicNumber); #expect(!ok) }
  }

  @Test func brokenMetadataFields() throws {
    var content: [UInt8]
    do {
      var w = DataSetWriter(magic: Self.kTestMagicNumber)
      w.add("google", 16, Self.kGoogle)
      w.add("mozc", 64, Self.kGenmai)
      content = w.finish()

      // Remove the metadata chunk at the bottom, which will be appended in each
      // test below.
      let metadataSize = try w.metadata.serializedBytes() as [UInt8]
      content.removeSubrange((content.count - metadataSize.count - 8)...)
    }
    do {
      // Create an image with broken metadata.
      var md = Genmai_DataSetMetadata()
      var e = Genmai_DataSetMetadata.Entry()
      e.name = "google"
      e.offset = UInt64(content.count + 3)  // Invalid offset
      e.size = UInt64(Self.kGoogle.count)
      md.entries.append(e)
      let mdStr: [UInt8] = try md.serializedBytes()
      let image = DataView(copying: content + mdStr + Util.serializeUint64(UInt64(mdStr.count)))

      var r = DataSetReader()
      #expect(!DataSetReader.verifyChecksum(image))
      do { let ok = r.initialize(image, magic: Self.kTestMagicNumber); #expect(!ok) }
    }
    do {
      // Create an image with broken size.
      var md = Genmai_DataSetMetadata()
      var e = Genmai_DataSetMetadata.Entry()
      e.name = "google"
      e.offset = UInt64(content.count)
      e.size = UInt64.max  // Too big size
      md.entries.append(e)
      let mdStr: [UInt8] = try md.serializedBytes()
      let image = DataView(copying: content + mdStr + Util.serializeUint64(UInt64(mdStr.count)))

      var r = DataSetReader()
      #expect(!DataSetReader.verifyChecksum(image))
      do { let ok = r.initialize(image, magic: Self.kTestMagicNumber); #expect(!ok) }
    }
  }

  @Test func oneBitError() async {
    let kTestMagicNumber = Array("Dummy magic number\r\n".utf8)

    // Create data at random.
    var image: [UInt8]
    do {
      let kAlignments = [8, 16, 32, 64]
      var w = DataSetWriter(magic: kTestMagicNumber)
      var random = Random()
      for i in 0..<10 {
        w.add(
          "key\(i)", kAlignments[Int.random(in: 0..<kAlignments.count, using: &random)],
          random.byteString(Int.random(in: 1..<1024, using: &random)))
      }
      image = w.finish()
    }

    var r = DataSetReader()
    #expect(DataSetReader.verifyChecksum(DataView(copying: image)))
    do { let ok = r.initialize(DataView(copying: image), magic: kTestMagicNumber); #expect(ok) }

    // Flip each bit and test if verifyChecksum fails.  (The byte range is
    // split over concurrent tasks because SHA1 is slow in debug builds.)
    let original = image
    let chunkSize = 256
    let failures = await withTaskGroup(of: Int.self) { group in
      for chunkStart in stride(from: 0, to: original.count, by: chunkSize) {
        group.addTask {
          var image = original
          var r = DataSetReader()
          var failures = 0
          for i in chunkStart..<min(chunkStart + chunkSize, image.count) {
            let orig = image[i]
            for j in 0..<8 {
              image[i] = orig ^ UInt8(1 << j)  // Flip (j + 1)-th bit

              // Since checksum is computed from the bytes up to metadata size,
              // errors in the last 8 bytes (where file size is stored) cannot
              // be tested using the checksum.  However, in such case,
              // initialize() should fail due to file size mismatch.  Thus,
              // either verifyChecksum() or initialize() fails.
              let view = DataView(copying: image)
              if DataSetReader.verifyChecksum(view), r.initialize(view, magic: kTestMagicNumber) {
                failures += 1
              }
            }
            image[i] = orig  // Recover the original data.
          }
          return failures
        }
      }
      return await group.reduce(0, +)
    }
    #expect(failures == 0)
  }
}
