// Port of mozc/src/data_manager/dataset_writer.{h,cc} (3.35.6354).
//
// A build-time tool in C++; ported because the dataset reader tests (and
// tests of later modules that need small custom data sets) use it.

import GenmaiBase
import GenmaiProtocol
import SwiftProtobuf

/// Creates a data set file that packs multiple files into one.  For file
/// format, see dataset.proto.
public struct DataSetWriter {
  private var image: [UInt8]
  public private(set) var metadata = Genmai_DataSetMetadata()
  private var seenNames: Set<String> = []

  /// Creates a writer with specified magic number.
  public init(magic: some Collection<UInt8>) {
    image = Array(magic)
  }

  /// Creates a writer with the UTF-8 bytes of `magic` as the magic number.
  public init(magic: String) {
    self.init(magic: Array(magic.utf8))
  }

  /// Adds a binary image to the packed file so that data is aligned at the
  /// specified bit boundary (8, 16, 32, 64, ...).
  public mutating func add(_ name: String, _ alignment: Int, _ data: some Collection<UInt8>) {
    precondition(seenNames.insert(name).inserted, "\(name) was already added")
    appendPadding(alignment)
    var entry = Genmai_DataSetMetadata.Entry()
    entry.name = name
    entry.offset = UInt64(image.count)
    entry.size = UInt64(data.count)
    metadata.entries.append(entry)
    image.append(contentsOf: data)
  }

  /// Similar to add() but data is read from file.
  public mutating func addFile(_ name: String, _ alignment: Int, _ filepath: String) throws {
    let content = try FileUtil.getContentBytes(filepath)
    add(name, alignment, content)
  }

  /// Returns the final image (C++ `Finish(std::ostream*)` writes it to a
  /// stream).
  public mutating func finish() -> [UInt8] {
    let s: [UInt8] = (try? metadata.serializedBytes()) ?? []
    image.append(contentsOf: s)  // Metadata
    image.append(contentsOf: Util.serializeUint64(UInt64(s.count)))  // Metadata size

    // SHA1 checksum
    image.append(contentsOf: UnverifiedSHA1.makeDigest(image))

    // File size.  Note that the final file size becomes image.count + 8 after
    // writing this file size.
    image.append(contentsOf: Util.serializeUint64(UInt64(image.count + 8)))
    return image
  }

  /// Writes the image to `path`.
  public mutating func finish(toFile path: String) throws {
    try FileUtil.setContents(path, finish())
  }

  private mutating func appendPadding(_ alignment: Int) {
    precondition(DataSetWriter.isValidAlignment(alignment), "Invalid alignment: \(alignment)")
    let byteAlignment = alignment / 8  // To byte
    if image.count % byteAlignment > 0 {
      image.append(contentsOf: repeatElement(0, count: byteAlignment - image.count % byteAlignment))
    }
  }

  /// Checks if `a` is a power of 2 greater than or equal to 8.
  private static func isValidAlignment(_ a: Int) -> Bool {
    a >= 8 && a.nonzeroBitCount == 1
  }
}
