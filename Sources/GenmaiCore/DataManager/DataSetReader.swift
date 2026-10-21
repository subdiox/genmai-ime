// Port of mozc/src/data_manager/dataset_reader.{h,cc} (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import SwiftProtobuf

/// The size of the file footer, which contains some metadata; see dataset.proto.
private let kFooterSize = 36

/// Reads a data set file image (see dataset.proto for the format):
///
///     magic | padding/file data ... | metadata | metadata size (8) | SHA1 (20) | file size (8)
public struct DataSetReader: Sendable {
  private var memblock = DataView.empty

  /// The value points to a block of the specified |memblock|.
  public private(set) var nameToDataMap: [String: DataView] = [:]

  public init() {}

  /// Initializes the reader from the binary image of dataset file and expected
  /// magic number.  The memory of |memblock| is kept alive by its owner.  Note:
  /// this method doesn't verify checksum for performance.  One can separately
  /// call verifyChecksum().
  public mutating func initialize(_ memblock: DataView, magic: some Collection<UInt8>) -> Bool {
    self.memblock = memblock
    nameToDataMap.removeAll()

    // Initializes |nameToDataMap| from |memblock|.  For binary data format,
    // see dataset.proto.

    // Check the file magic string.
    if !memblock.starts(with: magic) {
      GenmaiLog.error("Invalid format: magic number doesn't match")
      return false
    }

    return initialize(memblock, magicLength: magic.count)
  }

  /// A variant of initialize() that takes the length of the magic number rather
  /// than the magic number itself.
  public mutating func initialize(_ memblock: DataView, magicLength: Int) -> Bool {
    self.memblock = memblock
    nameToDataMap.removeAll()

    // Check minimum required data size.
    if memblock.count < magicLength + kFooterSize {
      GenmaiLog.error("Broken: data is too small")
      return false
    }

    // Check the file size.
    guard let filesize = Util.deserializeUint64(memblock.clippedSubstr(memblock.count - 8, 8)) else {
      GenmaiLog.error("Broken: failed to read filesize")
      return false
    }
    if filesize != UInt64(memblock.count) {
      GenmaiLog.error("Broken: filesize mismatch.  \(filesize) vs \(memblock.count)")
      return false
    }

    // Checksum is not checked.

    // Read the metadata size.
    guard
      let metadataSize = Util.deserializeUint64(
        memblock.clippedSubstr(memblock.count - kFooterSize, 8))
    else {
      GenmaiLog.error("Broken: failed to read metadata size")
      return false
    }

    // Note: This subtraction doesn't cause underflow by the above check.
    let contentAndMetadataSize = UInt64(memblock.count - magicLength - kFooterSize)
    if metadataSize == 0 || contentAndMetadataSize < metadataSize {
      GenmaiLog.error("Broken: metadata size is broken or metadata is broken")
      return false
    }

    // Note: This subtraction doesn't cause underflow by the above check.
    let metadataOffset = UInt64(memblock.count - kFooterSize) - metadataSize

    // Open metadata.
    let metadataChunk = memblock.clippedSubstr(Int(metadataOffset), Int(metadataSize))
    let metadata: Genmai_DataSetMetadata
    do {
      metadata = try Genmai_DataSetMetadata(serializedBytes: metadataChunk.array)
    } catch {
      GenmaiLog.error("Broken: Failed to parse metadata")
      return false
    }

    // Construct a mapping from name to data chunk.
    var prevChunkEnd = UInt64(magicLength)
    for e in metadata.entries {
      if e.offset < prevChunkEnd || e.offset >= metadataOffset {
        GenmaiLog.error("Broken: Offset is out of range: \(e), metadata offset = \(metadataOffset)")
        return false
      }
      // Check the condition e.offset + e.size <= metadataOffset, i.e., data
      // chunk must point to a block before metadata.
      if e.size > metadataOffset || e.offset > metadataOffset - e.size {
        GenmaiLog.error("Broken: Size exceeds the metadata offset: \(e), metadata offset = \(metadataOffset)")
        return false
      }
      nameToDataMap[e.name] = memblock.clippedSubstr(Int(e.offset), Int(e.size))
      prevChunkEnd = e.offset + e.size
    }

    return true
  }

  /// Gets the byte data corresponding to |name|.  If the data for |name|
  /// doesn't exist, returns nil.
  public func get(_ name: String) -> DataView? {
    nameToDataMap[name]
  }

  /// Gets the byte offset and size of the data corresponding to `name`.
  public func getOffsetAndSize(_ name: String) -> (offset: Int, size: Int)? {
    guard let data = get(name) else {
      return nil
    }
    let offset: Int
    if let p = data.baseAddress, let base = memblock.baseAddress {
      offset = p - base
    } else {
      offset = 0
    }
    return (offset, data.count)
  }

  /// Verifies the checksum of binary image.
  public static func verifyChecksum(_ memblock: DataView) -> Bool {
    if memblock.count < kFooterSize {
      return false
    }
    // Checksum is computed for all but last 28 bytes.
    let actualChecksum = memblock.bytes.withMemoryRebound(to: UInt8.self) { p in
      UnverifiedSHA1.makeDigest(UnsafeBufferPointer(rebasing: p[0..<(p.count - 28)]))
    }

    // Extract the stored SHA1; see dataset.proto for file format.
    let kSHA1Length = 20
    let expectedChecksum = memblock.clippedSubstr(memblock.count - 28, kSHA1Length)

    return actualChecksum.elementsEqual(expectedChecksum)
  }
}
