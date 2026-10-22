// Port of mozc/src/dictionary/file/codec.{h,cc} (3.35.6354).
//
// Named DictionaryFileCodec.swift (not Codec.swift) to avoid a clash with the
// system dictionary codec inside the GenmaiCore target.
//
// Deviations:
// - `WriteSections(sections, std::ostream*)` appends to a byte array instead
//   of writing to a stream.
// - `ReadSections` throws `StatusError` instead of returning absl::Status.

import GenmaiBase
import Synchronization

enum FileCodecUtil {
  static func writeInt32(_ value: Int32, _ ofs: inout [UInt8]) {
    let v = UInt32(bitPattern: value)
    ofs.append(UInt8(truncatingIfNeeded: v))
    ofs.append(UInt8(truncatingIfNeeded: v >> 8))
    ofs.append(UInt8(truncatingIfNeeded: v >> 16))
    ofs.append(UInt8(truncatingIfNeeded: v >> 24))
  }

  static func roundUp4(_ length: Int) -> Int {
    let rem = length % 4
    return length + ((4 - rem) % 4)
  }

  static func pad4(_ length: Int, _ ofs: inout [UInt8]) {
    var i = length
    while i % 4 != 0 {
      ofs.append(0)
      i += 1
    }
  }
}

/// `mozc::dictionary::DictionaryFileCodec`.
public final class DictionaryFileCodec: Sendable {
  /// Seed value for name string finger print.
  /// Mutable for reading sections (C++ uses std::atomic).
  private let seed = Mutex<Int32>(2_135_654_146)
  /// Magic value for simple file validation.
  private let filemagic: Int32 = 20_110_701

  public init() {}

  public func writeSections(_ sections: [DictionaryFileSection], _ ofs: inout [UInt8]) {
    writeHeader(&ofs)

    if sections.count == 4 {
      // In production, the number of sections equals 4.  In this case, write the
      // sections in the following deterministic order.  This order was determined
      // by random shuffle for engine version 24 but it's now made deterministic
      // to obsolete DictionaryFileCodec.
      for i in [0, 2, 1, 3] {
        writeSection(sections[i], &ofs)
      }
    } else {
      // Some tests don't have four sections.  In this case, simply write sections
      // in given order.
      for section in sections {
        writeSection(section, &ofs)
      }
    }

    FileCodecUtil.writeInt32(0, &ofs)
  }

  /// Convenience: returns the image of `sections`.
  public func writeSections(_ sections: [DictionaryFileSection]) -> [UInt8] {
    var out: [UInt8] = []
    writeSections(sections, &out)
    return out
  }

  /// Parses `image` into sections. The section images are views into `image`
  /// (they keep `image.owner` alive).
  public func readSections(_ image: DataView) throws -> [DictionaryFileSection] {
    var sections: [DictionaryFileSection] = []
    // At least 12 bytes (3 * int32_t) are required.
    if image.count < 12 {
      throw StatusError.failedPrecondition(
        "codec.cc: Insufficient data size: \(image.count) bytes")
    }
    // The image must be aligned at 32-bit boundary.
    if Int(bitPattern: image.baseAddress) % 4 != 0 {
      throw StatusError.failedPrecondition(
        "codec.cc: memory block of size \(image.count) is not aligned at 32-bit boundary")
    }
    // The current position at which data is read.
    var ptr = 0
    let imageEnd = image.count

    let filemagic = Int32(bitPattern: image.load(fromByteOffset: ptr, as: UInt32.self))
    ptr += 4
    if filemagic != self.filemagic {
      throw StatusError.failedPrecondition(
        "codec.cc: Invalid dictionary file magic. Expected: \(self.filemagic) Actual: \(filemagic)")
    }
    let newSeed = Int32(bitPattern: image.load(fromByteOffset: ptr, as: UInt32.self))
    ptr += 4
    seed.withLock { $0 = newSeed }
    var sectionIndex = 0
    while true {
      defer { sectionIndex += 1 }
      // Each section has the following format:
      // +-----------+-------------+-----------------+---------------+
      // |  int32_t  |   char[8]   | char[data_size] | up to 3 bytes |
      // | data_size | fingerprint |      data       |   padding     |
      // +-----------+-------------+-----------------+---------------+
      // ^                         <- - - - padded_data_size - - - - >
      // ptr points to here now.
      if imageEnd - ptr < 4 {
        throw StatusError.outOfRange(
          "codec.cc: Section \(sectionIndex): Insufficient image to read data_size(4 bytes), available size = \(imageEnd - ptr)"
        )
      }
      let dataSize = Int(Int32(bitPattern: image.load(fromByteOffset: ptr, as: UInt32.self)))
      ptr += 4
      if dataSize == 0 {  // The end marker written in WriteSections().
        break
      }
      // Calculate the section end pointer.  Note that |ptr| currently points to
      // the beginning of fingerprint.
      let kFingerprintByteLength = 8
      let paddedDataSize = FileCodecUtil.roundUp4(dataSize)
      let sectionEnd = ptr + kFingerprintByteLength + paddedDataSize
      if dataSize < 0 || sectionEnd > imageEnd {
        throw StatusError.outOfRange(
          "codec.cc: Section \(sectionIndex): Read pointer will pass the end: offset=\(sectionEnd), image_size=\(image.count)"
        )
      }
      let fingerprint = Array(image.bytes[ptr..<(ptr + kFingerprintByteLength)])
      ptr += kFingerprintByteLength
      // Add a section with data and fingerprint.  Note that the data size is
      // |data_size| but |ptr| is advanced by |padded_data_size| to skip padding
      // bytes at the end.
      sections.append(DictionaryFileSection(image: image.slice(ptr, dataSize), name: fingerprint))
      ptr += paddedDataSize
    }
    if ptr != imageEnd {
      throw StatusError.failedPrecondition(
        "codec.cc: \(imageEnd - ptr) bytes remaining out of \(image.count)")
    }
    return sections
  }

  /// Returns the 8-byte encoded section name (LegacyFingerprintWithSeed in
  /// host (little-endian) byte order).
  public func getSectionName(_ name: some StringProtocol) -> [UInt8] {
    let s = seed.withLock { $0 }
    let nameFp = legacyFingerprintWithSeed(name, UInt32(bitPattern: s))
    return withUnsafeBytes(of: nameFp.littleEndian) { Array($0) }
  }

  private func writeHeader(_ ofs: inout [UInt8]) {
    FileCodecUtil.writeInt32(filemagic, &ofs)
    FileCodecUtil.writeInt32(seed.withLock { $0 }, &ofs)
  }

  private func writeSection(_ section: DictionaryFileSection, _ ofs: inout [UInt8]) {
    let name = section.name
    let image = section.image
    // name should be encoded
    // uint64_t needs just 8 bytes.
    assert(name.count == 8)
    FileCodecUtil.writeInt32(Int32(truncatingIfNeeded: image.count), &ofs)
    ofs.append(contentsOf: name)
    ofs.append(contentsOf: image.bytes)
    FileCodecUtil.pad4(image.count, &ofs)
  }
}
