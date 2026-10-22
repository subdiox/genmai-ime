// Port of mozc/src/storage/existence_filter.{h,cc} (3.35.6354).
//
// Deviations:
// - absl::Span<const uint32_t> views become `Data` slices (sharing the memory,
//   e.g. of the memory-mapped data set; read with little-endian loads through
//   their Span, so the buffer does not need to be 4-byte aligned).
// - ExistenceFilterBuilder.build() snapshots the builder's blocks (copy on
//   write) instead of referencing them, so later inserts into the builder are
//   not visible to an already built filter.
// - absl::StatusOr is replaced by `throws`.

import Foundation
import GenmaiBase

public enum ExistenceFilterInternal {
  public static let kBlockShift = 21  // 2^21 bits == 256KB block
  public static let kBlockBits = 1 << kBlockShift
  public static let kBlockMask = kBlockBits - 1
  public static let kBlockBytes = kBlockBits >> 3
  public static let kBlockWords = kBlockBits >> 5

  struct BlockDimensions {
    var count: UInt32
    var lastSize: UInt32

    init(_ bits: UInt32) {
      count = bits >> UInt32(kBlockShift)
      let bitsInLastBlock = bits & UInt32(kBlockMask)
      if bitsInLastBlock != 0 {
        count += 1
        lastSize = (bitsInLastBlock + 31) / 32
      } else {
        lastSize = UInt32(kBlockWords)
      }
    }
  }

  /// BlockBitmap is an immutable view, directly referencing data given to the
  /// initializers (or holding a snapshot of a builder's blocks).
  public struct BlockBitmap: Sendable {
    private enum Storage: Sendable {
      case view([Data])
      case owned([[UInt32]])
    }

    private var storage: Storage

    public init() {
      storage = .view([])
    }

    /// Array of blocks. Each block has kBlockBits region except for last
    /// block.
    public init(_ size: UInt32, _ buf: Data) {
      let dimensions = BlockDimensions(size)
      var blocks: [Data] = []
      blocks.reserveCapacity(Int(dimensions.count))
      var offset = buf.startIndex
      for _ in 0..<(Int(dimensions.count) - 1) {
        blocks.append(buf[offset..<(offset + kBlockWords * 4)])
        offset += kBlockWords * 4
      }
      blocks.append(buf[offset..<(offset + Int(dimensions.lastSize) * 4)])
      storage = .view(blocks)
    }

    init(owned blocks: [[UInt32]]) {
      storage = .owned(blocks)
    }

    @inline(__always)
    public func get(_ index: UInt32) -> Bool {
      let bindex = Int(index >> UInt32(kBlockShift))
      let windex = Int((index & UInt32(kBlockMask)) >> 5)
      let bitpos = index & 31
      let word: UInt32
      switch storage {
      case .view(let blocks):
        word = blocks[bindex].span.loadLittleEndian(UInt32.self, at: windex * 4)
      case .owned(let blocks):
        word = blocks[bindex][windex]
      }
      return (word >> bitpos) & 1 != 0
    }
  }

  /// BlockBitmapBuilder is a utility to create a BlockBitmap data.
  public struct BlockBitmapBuilder: Sendable {
    private var blocks: [[UInt32]] = []

    public init(_ size: UInt32) {
      precondition(size > 0)
      let dimensions = BlockDimensions(size)

      // Allocate the block array
      precondition(dimensions.count > 0)
      blocks.reserveCapacity(Int(dimensions.count))
      for _ in 0..<(Int(dimensions.count) - 1) {
        blocks.append([UInt32](repeating: 0, count: kBlockWords))
      }
      blocks.append([UInt32](repeating: 0, count: Int(dimensions.lastSize)))
    }

    public mutating func clear() {
      blocks.removeAll()
    }

    @inline(__always)
    public mutating func set(_ index: UInt32) {
      let bindex = Int(index >> UInt32(kBlockShift))
      let windex = Int((index & UInt32(kBlockMask)) >> 5)
      let bitpos = index & 31
      blocks[bindex][windex] |= UInt32(1) << bitpos
    }

    /// Serializes the bitmap (little endian words) by appending to `out`.
    public func serialize(to out: inout [UInt8]) {
      for block in blocks {
        for i in block {
          out.appendLittleEndian(i)
        }
      }
    }

    /// Builds a BlockBitmap from the underlying data.
    public func build() -> BlockBitmap {
      BlockBitmap(owned: blocks)
    }
  }

  @inline(__always)
  public static func fingerprint(_ str: some StringProtocol, _ fpType: UInt16) -> UInt64 {
    fpType == 0 ? legacyFingerprint(str) : cityFingerprint(str)
  }
}

/// ExistenceFilter parameters.
public struct ExistenceFilterParams: Sendable, Equatable, CustomStringConvertible {
  public enum FpType {
    public static let legacyFp: UInt16 = 0
    public static let cityFp: UInt16 = 1
    public static let fpTypeSize: UInt16 = 2
  }

  public static let kDefaultFpType: UInt16 = FpType.cityFp

  /// the number of bits in the bit vector
  public var size: UInt32 = 0
  /// the number of values that will be stored
  public var expectedNelts: UInt32 = 0

  /// the number of hash values to use per insert/lookup.
  /// num_hashes must be less than 8.
  public var numHashes: UInt16 = 0

  /// Fingerprint algorithm type.
  /// The old code defines `num_hashes` as 32 bits int. To store the fp_type,
  /// splits the `num_hashes` into two 16 bits int.
  public var fpType: UInt16 = kDefaultFpType

  public init() {}

  public init(
    size: UInt32, expectedNelts: UInt32, numHashes: UInt16, fpType: UInt16 = kDefaultFpType
  ) {
    self.size = size
    self.expectedNelts = expectedNelts
    self.numHashes = numHashes
    self.fpType = fpType
  }

  public var description: String {
    "size: \(size) bits, estimated insertions: \(expectedNelts), num_hashes: \(numHashes), fp_type: \(fpType)"
  }
}

/// Bloom filter
public struct ExistenceFilter: Sendable {
  private static let kHeaderSize = 3

  public private(set) var params = ExistenceFilterParams()
  private var rep = ExistenceFilterInternal.BlockBitmap()  // points to bitmap

  public init() {}

  /// Constructs a new ExistenceFilter view from the parameters and the
  /// BlockBitmap buffer.
  public init(_ params: ExistenceFilterParams, _ buf: Data) {
    self.params = params
    rep = ExistenceFilterInternal.BlockBitmap(params.size, buf)
  }

  public init(_ params: ExistenceFilterParams, _ rep: ExistenceFilterInternal.BlockBitmap) {
    self.params = params
    self.rep = rep
  }

  /// Read Existence filter from buf (a sequence of little endian 32-bit
  /// words; `buf.count` is in bytes).
  public static func read(_ buf: Data) throws -> ExistenceFilter {
    let numWords = buf.count / 4
    let params: ExistenceFilterParams
    do {
      params = try readHeader(buf.span, numWords)
    } catch {
      throw StatusError.invalidArgument("Invalid format: could not read header")
    }
    let body = buf.dropFirst(kHeaderSize * 4)

    GenmaiLog.info("Reading bloom filter with params: \(params)")

    if numWords - kHeaderSize < Int(bitsToWords(params.size)) {
      throw StatusError.invalidArgument("Not enough bufsize: could not read")
    }

    return ExistenceFilter(params, body)
  }

  /// Checks if the concatenation of the given `keys` was in the filter.
  public func exists(_ keys: [String]) -> Bool {
    exists(hash: ExistenceFilterInternal.fingerprint(keys.joined(), params.fpType))
  }

  /// Checks if the given `key` was in the filter.
  public func exists(_ key: some StringProtocol) -> Bool {
    exists(hash: ExistenceFilterInternal.fingerprint(key, params.fpType))
  }

  /// Checks if the given 'hash' was previously inserted int the filter
  /// It may return some false positives
  private func exists(hash: UInt64) -> Bool {
    var hash = hash
    for _ in 0..<Int(params.numHashes) {
      hash = Self.rotl(hash, 8)
      let index = UInt32(truncatingIfNeeded: hash % UInt64(params.size))
      if !rep.get(index) {
        return false
      }
    }
    return true
  }

  @inline(__always)
  static func rotl(_ x: UInt64, _ s: UInt64) -> UInt64 {
    (x << s) | (x >> (64 - s))
  }

  private static func readHeader(_ buf: Span<UInt8>, _ numWords: Int) throws
    -> ExistenceFilterParams
  {
    if numWords < kHeaderSize {
      throw StatusError.invalidArgument("Not enough bufsize: could not read header")
    }

    var params = ExistenceFilterParams()
    params.size = buf.loadLittleEndian(UInt32.self, at: 0)
    params.expectedNelts = buf.loadLittleEndian(UInt32.self, at: 4)

    // Assumes little-endian.
    // num_hashes was originally stored as 32bit integer, so the old
    // binary stores the value in lower bits.
    let v = buf.loadLittleEndian(UInt32.self, at: 8)
    params.numHashes = UInt16(truncatingIfNeeded: v & 0xFFFF)
    params.fpType = UInt16(truncatingIfNeeded: v >> 16)

    if params.numHashes >= 8 || params.numHashes <= 0 {
      throw StatusError.invalidArgument("Bad number of hashes (header.k)")
    }

    if params.fpType >= ExistenceFilterParams.FpType.fpTypeSize {
      throw StatusError.invalidArgument("unsupported fp type")
    }

    return params
  }

  static func bitsToWords(_ bits: UInt32) -> UInt32 {
    var words = (bits &+ 31) >> 5
    if bits > 0 && words == 0 {
      words = 1 << (32 - 5)  // possible overflow
    }
    return words
  }
}

/// ExistenceFilterBuilder is a utility to construct ExistenceFilter data.
/// Use minFilterSizeInBytesForErrorRate to determine the size and call the
/// createOptimal function to create an instance.
public struct ExistenceFilterBuilder: Sendable {
  private static let kHeaderSize = 3

  private var params: ExistenceFilterParams
  private var rep: ExistenceFilterInternal.BlockBitmapBuilder

  public init(_ params: ExistenceFilterParams) {
    self.params = params
    rep = ExistenceFilterInternal.BlockBitmapBuilder(params.size)
  }

  public static func createOptimal(
    _ sizeInBytes: Int, _ estimatedInsertions: UInt32,
    _ fpType: UInt16 = ExistenceFilterParams.kDefaultFpType
  ) -> ExistenceFilterBuilder {
    precondition(sizeInBytes < (1 << 29), "Requested size is too big")
    precondition(estimatedInsertions > 0)
    precondition(fpType < ExistenceFilterParams.FpType.fpTypeSize)
    let m = max(UInt32(1), UInt32(truncatingIfNeeded: sizeInBytes * 8))
    let n = estimatedInsertions

    // std::round(static_cast<float>(m) / n * log(2.0)): float division, then
    // promoted to double for the multiplication.
    // The C++ static_cast<uint16_t> of a value above UINT16_MAX (e.g. a
    // 100 KB suggestion filter with a handful of words) is undefined; clang on
    // arm64 / x86-64 converts to a 32-bit integer and keeps the low 16 bits,
    // which the data generators' outputs depend on.
    var optimalK = UInt16(
      truncatingIfNeeded: Int64((Double(Float(m) / Float(n)) * log(2.0)).rounded(.toNearestOrAwayFromZero)))
    optimalK = min(max(optimalK, 1), 7)

    GenmaiLog.info("optimal_k: \(optimalK)")

    return ExistenceFilterBuilder(
      ExistenceFilterParams(size: m, expectedNelts: n, numHashes: optimalK, fpType: fpType))
  }

  /// Inserts the concatenation of a list of string into the filter.
  public mutating func insert(_ keys: [String]) {
    insert(hash: ExistenceFilterInternal.fingerprint(keys.joined(), params.fpType))
  }

  /// Inserts one string into the filter.
  public mutating func insert(_ key: some StringProtocol) {
    insert(hash: ExistenceFilterInternal.fingerprint(key, params.fpType))
  }

  /// Writes the existence filter to a buffer and returns it.
  public func serializeAsString() -> [UInt8] {
    let requiredBytes =
      (Self.kHeaderSize + Int(ExistenceFilter.bitsToWords(params.size))) * MemoryLayout<UInt32>.size
    var buf: [UInt8] = []
    buf.reserveCapacity(requiredBytes)

    // write header
    buf.appendLittleEndian(params.size)
    buf.appendLittleEndian(params.expectedNelts)
    // Original num_hashes was 32 bit integer. Pushes the num_hases first so
    // it can evaluated properly even when loading them as single 32 bit
    // integer.
    buf.appendLittleEndian(params.numHashes)
    buf.appendLittleEndian(params.fpType)
    GenmaiLog.info("Header written: \(params)")

    // write bitmap
    rep.serialize(to: &buf)

    if buf.count != requiredBytes {
      GenmaiLog.error("Wrote \(buf.count) bytes instead of \(requiredBytes)")
      // The C++ code writes into a pre-sized buffer.
      if buf.count < requiredBytes {
        buf.append(contentsOf: repeatElement(0, count: requiredBytes - buf.count))
      } else {
        buf.removeLast(buf.count - requiredBytes)
      }
    }
    return buf
  }

  /// Builds an ExistenceFilter directly from the internal buffer.
  public func build() -> ExistenceFilter {
    ExistenceFilter(params, rep.build())
  }

  /// Returns the minimum required size of the filter in bytes
  /// under the given error rate and number of elements
  public static func minFilterSizeInBytesForErrorRate(_ errorRate: Float, _ numElements: Int) -> Int {
    // (-num_hashes * num_elements) / log(1 - error_rate^(1/num_hashes))

    var minBits = 0.0
    for numHashes in 1..<8 {
      let numBits =
        (-1.0 * Double(numHashes) * Double(numElements))
        / log(1.0 - pow(Double(errorRate), 1.0 / Double(numHashes)))
      if minBits == 0 || numBits < minBits { minBits = numBits }
    }
    return Int((minBits / 8).rounded(.up))
  }

  /// Inserts a hash value into the filter
  /// We generate 'k' separate internal hash values
  private mutating func insert(hash: UInt64) {
    var hash = hash
    for _ in 0..<Int(params.numHashes) {
      hash = ExistenceFilter.rotl(hash, 8)
      let index = UInt32(truncatingIfNeeded: hash % UInt64(params.size))
      rep.set(index)
    }
  }
}
