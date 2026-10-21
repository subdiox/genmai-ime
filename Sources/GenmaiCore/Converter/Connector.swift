// Port of mozc/src/converter/connector.{h,cc} (3.35.6354).

import GenmaiBase

/// `mozc::Connector`: the connection (transition) cost matrix.
///
/// Reads the compressed matrix in place (no copy) from the data view, which is
/// kept alive. The transition cost cache has the same layout and hashing as the
/// C++ one, so results are bit exact including its quirks (an untouched bucket
/// holds 0, which is a hit for (rid 0, lid 0) with cost 0).
///
/// `@unchecked Sendable`: the matrix is immutable. The cache entries are
/// 64-bit words read and written with plain aligned loads/stores (the C++ code
/// uses relaxed atomics); concurrent access may only lose cache updates, never
/// produce a wrong value, because the tag and value share one word.
public final class Connector: @unchecked Sendable {
  public static let kInvalidCost: Int16 = 30000

  private static let kConnectorMagicNumber: UInt16 = 0xCDAB
  private static let kInvalid1ByteCostValue: UInt8 = 255
  private static let kCacheSize: UInt32 = 1024
  private static let kCacheHashMask: UInt32 = kCacheSize - 1
  /// The number of consecutive compact bits that a chunk bit represents.
  private static let kChunkWidth: UInt32 = 8

  /// One row of the matrix: byte offsets of its blocks from `base` and the
  /// offsets of its rank indices in `rankIndex`.
  private struct Row {
    var chunkBits: Int = 0
    var compactBits: Int = 0
    var values: Int = 0
    var chunkRank: Int = 0
    var compactRank: Int = 0
  }

  private let data: DataView
  private let base: UnsafeRawPointer
  private var rows: UnsafeMutableBufferPointer<Row>
  private var rankIndex: UnsafeMutablePointer<UInt16>
  private var defaultCost: Int = 0  // byte offset of the default cost array
  private var resolution: Int = 0
  /// True if the values of the rows are quantized to 1 byte.
  private var use1ByteValue = false
  /// Cache for transition cost.
  private let cache: UnsafeMutablePointer<UInt64>

  private init(_ data: DataView) {
    self.data = data
    base = data.baseAddress ?? UnsafeRawPointer(bitPattern: 0x10)!
    rows = .allocate(capacity: 0)
    rankIndex = .allocate(capacity: 1)
    cache = .allocate(capacity: Int(Self.kCacheSize))
    cache.initialize(repeating: 0, count: Int(Self.kCacheSize))
  }

  deinit {
    rows.deallocate()
    rankIndex.deallocate()
    cache.deallocate()
  }

  /// `Connector::Create`.
  public static func create(_ connectionData: DataView) throws -> Connector {
    let connector = Connector(connectionData)
    try connector.initialize()
    return connector
  }

  /// `Connector::Create` over a copy of `bytes` (tests).
  public static func create(copying bytes: some Collection<UInt8>) throws -> Connector {
    try create(DataView(copying: bytes))
  }

  public func getResolution() -> Int { resolution }

  private struct Metadata {
    static let kByteSize = 8

    var magic: UInt16 = .max
    var resolution: UInt16 = .max
    var rsize: UInt16 = .max
    var lsize: UInt16 = .max

    // The number of valid bits in a chunk. Each bit is bitwise-or of
    // consecutive 8-bits.
    var numChunkBits: Int { (Int(lsize) + Int(kChunkWidth) - 1) / Int(kChunkWidth) }

    // Then calculate the actual size of chunk in bytes, which is aligned to
    // 32-bits boundary.
    var chunkBitsSize: Int { (numChunkBits + 31) / 32 * 4 }

    // True if value is quantized to 1 byte.
    var use1ByteValue: Bool { resolution != 1 }

    // Number of elements in the default cost array.
    var defaultCostArraySize: Int { Int(rsize) + Int(rsize & 1) }

    var debugString: String {
      "Metadata{magic: \(magic), resolution: \(resolution), rsize: \(rsize), lsize: \(lsize)}"
    }
  }

  private static func parseMetadata(_ data: DataView) throws -> Metadata {
    if data.count < Metadata.kByteSize {
      throw StatusError.failedPrecondition(
        "connector.cc: At least \(Metadata.kByteSize) bytes expected.  (\(data.count) bytes)")
    }
    var metadata = Metadata()
    metadata.magic = UInt16(littleEndian: data.bytes.loadUnaligned(fromByteOffset: 0, as: UInt16.self))
    metadata.resolution = UInt16(littleEndian: data.bytes.loadUnaligned(fromByteOffset: 2, as: UInt16.self))
    metadata.rsize = UInt16(littleEndian: data.bytes.loadUnaligned(fromByteOffset: 4, as: UInt16.self))
    metadata.lsize = UInt16(littleEndian: data.bytes.loadUnaligned(fromByteOffset: 6, as: UInt16.self))

    if metadata.magic != kConnectorMagicNumber {
      throw StatusError.failedPrecondition(
        "connector.cc: Unexpected magic number. Expected: \(kConnectorMagicNumber) Actual: \(metadata.debugString)"
      )
    }
    if metadata.lsize != metadata.rsize {
      throw StatusError.failedPrecondition("connector.cc: Matrix is not square: \(metadata.debugString)")
    }
    return metadata
  }

  private func initialize() throws {
    let metadata = try Self.parseMetadata(data)
    resolution = Int(metadata.resolution)
    use1ByteValue = metadata.use1ByteValue

    let dataEnd = data.count
    // Set the read location to the metadata end.
    var ptr = Metadata.kByteSize

    func debugInfo(_ p: Int) -> String {
      "\(metadata.debugString), Reader{location: \(p), datasize: \(data.count)}"
    }
    // A helper to check if the array is aligned at 32-bit boundary.
    func validateAlignment(_ offset: Int, _ name: String) throws {
      let addr = UInt(bitPattern: base) &+ UInt(offset)
      let alignment = addr % 4
      if alignment != 0 {
        throw StatusError.failedPrecondition(
          "connector.cc: \(debugInfo(ptr)): \(name) is not 32-bit aligned: Aligned at \(alignment) byte")
      }
    }
    // A helper to check if the data range [p, p + numBytes) is not
    // out-of-range.
    func validateSize(_ p: Int, _ numBytes: Int, _ what: @autoclosure () -> String) throws {
      let remaining = dataEnd - p
      if remaining >= numBytes {
        return
      }
      throw StatusError.outOfRange(
        "connector.cc: \(debugInfo(p)): Tried to read past-the-end.  Required bytes: \(numBytes), remaining: \(remaining): \(what())"
      )
    }

    // Read default cost array and move the read pointer.
    defaultCost = ptr
    // Each element of default cost array is 2 bytes.
    let defaultCostSize = metadata.defaultCostArraySize * 2
    try validateSize(ptr, defaultCostSize, "Default cost")
    try validateAlignment(ptr, "default_cost_")
    ptr += defaultCostSize

    let chunkBitsSize = metadata.chunkBitsSize
    let rsize = Int(metadata.rsize)
    rows.deallocate()
    rows = .allocate(capacity: rsize)
    rows.initialize(repeating: Row())
    var indexSize = 0
    for i in 0..<rsize {
      // Each row is formatted as follows:
      // +-------------------+-------------+------------+------------+-----------+
      // |     uint16_t      |  uint16_t   | uint8_t[]  | uint8_t[]  | uint8_t[] |
      // | compact_bits_size | values_size | chunk_bits |compact_bits| values    |
      // +-------------------+-------------+------------+------------+-----------+
      // ^
      // |ptr| points to here now.  Every uint8_t[] block needs to be aligned at
      // 32-bit boundary.
      try validateSize(ptr, 2, "Compact bits size of row \(i)/\(rsize)")
      let compactBitsSize = Int(UInt16(littleEndian: base.loadUnaligned(fromByteOffset: ptr, as: UInt16.self)))
      ptr += 2

      try validateSize(ptr, 2, "Values size of row \(i)/\(rsize)")
      let valuesSize = Int(UInt16(littleEndian: base.loadUnaligned(fromByteOffset: ptr, as: UInt16.self)))
      ptr += 2

      try validateSize(ptr, chunkBitsSize, "Chunk bits of row \(i)/\(rsize)")
      let chunkBits = ptr
      try validateAlignment(chunkBits, "chunk_bits")
      ptr += chunkBitsSize

      try validateSize(ptr, compactBitsSize, "Compact bits of row \(i)/\(rsize)")
      let compactBits = ptr
      try validateAlignment(compactBits, "compact_bits")
      ptr += compactBitsSize

      try validateSize(ptr, valuesSize, "Values of row \(i)/\(rsize)")
      let values = ptr
      try validateAlignment(values, "values")
      ptr += valuesSize

      rows[i] = Row(
        chunkBits: chunkBits, compactBits: compactBits, values: values,
        chunkRank: indexSize, compactRank: indexSize + chunkBitsSize / 4)
      indexSize += chunkBitsSize / 4 + compactBitsSize / 4
    }
    try validateSize(ptr, 0, "Data end")

    // Allocate the storage for the rank indices of all rows at once, exactly as
    // large as needed, and build them.
    rankIndex.deallocate()
    rankIndex = .allocate(capacity: max(indexSize, 1))
    for i in 0..<rsize {
      let row = rows[i]
      buildIndex(row.chunkBits, chunkBitsSize / 4, row.chunkRank)
      buildIndex(row.compactBits, (row.values - row.compactBits) / 4, row.compactRank)
    }
  }

  /// `RankBitVector::BuildIndex`: the number of 1-bits before each word.
  private func buildIndex(_ dataOffset: Int, _ words: Int, _ rankOffset: Int) {
    var numBits: UInt32 = 0
    for i in 0..<words {
      rankIndex[rankOffset + i] = UInt16(truncatingIfNeeded: numBits)
      let word = UInt32(littleEndian: base.loadUnaligned(fromByteOffset: dataOffset + 4 * i, as: UInt32.self))
      numBits += UInt32(word.nonzeroBitCount)
    }
  }

  /// `RankBitVector::Rank1IfSet`: returns the number of 1-bits in [0, n) if
  /// bit n is set, or -1.
  @inline(__always)
  private func rank1IfSet(_ dataOffset: Int, _ rankOffset: Int, _ n: UInt32) -> Int {
    let wordIndex = Int(n / 32)
    let word = UInt32(littleEndian: base.loadUnaligned(fromByteOffset: dataOffset + 4 * wordIndex, as: UInt32.self))
    let bit: UInt32 = 1 << (n % 32)
    if word & bit == 0 {
      return -1
    }
    return Int(rankIndex[rankOffset + wordIndex]) + (word & (bit &- 1)).nonzeroBitCount
  }

  /// `Row::GetValue`: returns the value in the row if found, or -1.
  @inline(__always)
  private func getValue(_ row: Row, _ index: UInt16) -> Int {
    let chunkRank = rank1IfSet(row.chunkBits, row.chunkRank, UInt32(index) / Self.kChunkWidth)
    if chunkRank < 0 {
      return -1
    }
    let compactRank = rank1IfSet(
      row.compactBits, row.compactRank, UInt32(chunkRank) * Self.kChunkWidth + UInt32(index) % Self.kChunkWidth)
    if compactRank < 0 {
      return -1
    }
    let valuePosition = compactRank
    var value: UInt16
    if use1ByteValue {
      value = UInt16(base.load(fromByteOffset: row.values + valuePosition, as: UInt8.self))
      if value == UInt16(Self.kInvalid1ByteCostValue) {
        value = UInt16(Self.kInvalidCost)
      }
    } else {
      value = UInt16(
        littleEndian: base.loadUnaligned(fromByteOffset: row.values + 2 * valuePosition, as: UInt16.self))
    }
    return Int(value)
  }

  public func getTransitionCost(_ rid: UInt16, _ lid: UInt16) -> Int {
    // Note:
    // This function is called very frequently and has a significant impact on
    // execution time. When making any modifications, please conduct a performance
    // analysis.

    let index = (UInt32(rid) << 16) | UInt32(lid)
    let bucket = (3 &* UInt32(rid) &+ UInt32(lid)) & Self.kCacheHashMask
    // The above value is equivalent to (3 * rid + lid) % kCacheSize;
    // because cache_size_ is the power of 2.
    // Multiplying '3' makes the conversion speed faster.
    // The result hash value becomes reasonably random.

    // Upper 32bits stores the value-cost, lower 32 bits the index.
    let cv = cache[Int(bucket)]
    if UInt32(truncatingIfNeeded: cv) == index {
      return Int(Int32(truncatingIfNeeded: cv >> 32))
    }
    let value = lookupCost(rid, lid)
    cache[Int(bucket)] = UInt64(UInt32(truncatingIfNeeded: value)) << 32 | UInt64(index)
    return value
  }

  private func lookupCost(_ rid: UInt16, _ lid: UInt16) -> Int {
    let value = getValue(rows[Int(rid)], lid)
    if value < 0 {
      return Int(UInt16(littleEndian: base.loadUnaligned(fromByteOffset: defaultCost + 2 * Int(rid), as: UInt16.self)))
    }
    // kInvalidCost is stored as is regardless of the resolution, so it must not
    // be scaled.
    if value == Int(Self.kInvalidCost) {
      return Int(Self.kInvalidCost)
    }
    return value * resolution
  }
}
