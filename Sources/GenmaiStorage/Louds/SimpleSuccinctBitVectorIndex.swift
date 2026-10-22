// Port of mozc/src/storage/louds/simple_succinct_bit_vector_index.{h,cc}
// (3.35.6354).
//
// The C++ lower-bound caches hold `const int*` pointers into `index_`; here
// they hold offsets into `index`. The bit data is not owned (same as C++): the
// caller must keep the memory alive while the index is used.

/// This is simple(naive) implementation of succinct bit vector.
public struct SimpleSuccinctBitVectorIndex: @unchecked Sendable {
  // @unchecked Sendable: `data` points to immutable (typically memory-mapped)
  // bytes owned by the caller; the index itself is never mutated after init().

  private var data: UnsafeRawPointer?
  private var length = 0
  private let chunkSize: Int
  private var index: [Int] = []
  private var lb0Cache: [Int] = []
  private var lb0CacheIncrement = 1
  private var lb1CacheIncrement = 1
  private var lb1Cache: [Int] = []

  /// The default chunk_size is 32.
  public init() {
    chunkSize = 32
  }

  /// chunk_size is in bytes, and must be greater than or equal to 4
  /// and power of 2, at the moment, although we may relax the restriction
  /// in future if necessary.
  public init(chunkSize: Int) {
    self.chunkSize = chunkSize
  }

  /// Initializes the index. This type doesn't have the ownership of the
  /// memory pointed by data, so it is caller's responsibility to manage its
  /// life time. The 'data' needs to be aligned to 32-bits.
  public mutating func initialize(
    _ data: UnsafeRawPointer, _ length: Int, _ lb0CacheSize: Int = 0, _ lb1CacheSize: Int = 0
  ) {
    self.data = data
    self.length = length
    Self.initIndex(data, length, chunkSize, &index)

    // TODO(noriyukit): Currently, we simply use uniform increment width for
    // lower bound cache.  Nonuniform increment width may improve performance.
    lb0CacheIncrement = lb0CacheSize == 0 ? num0Bits : num0Bits / lb0CacheSize
    if lb0CacheIncrement == 0 {
      lb0CacheIncrement = 1
    }
    Self.initLowerBound0Cache(index, chunkSize, lb0CacheIncrement, lb0CacheSize, &lb0Cache)

    lb1CacheIncrement = lb1CacheSize == 0 ? num1Bits : num1Bits / lb1CacheSize
    if lb1CacheIncrement == 0 {
      lb1CacheIncrement = 1
    }
    Self.initLowerBound1Cache(index, lb1CacheIncrement, lb1CacheSize, &lb1Cache)
  }

  /// Resets the internal state, especially releases the allocated memory
  /// for the index used internally.
  public mutating func reset() {
    data = nil
    length = 0
    index.removeAll()
    lb0CacheIncrement = 1
    lb0Cache.removeAll()
    lb1CacheIncrement = 1
    lb1Cache.removeAll()
  }

  /// Returns the bit at the index in data. The index in a byte is as follows;
  /// MSB|XXXXXXXX|LSB
  ///     76543210
  @inline(__always)
  public func get(_ index: Int) -> Int {
    Int((data.unsafelyUnwrapped.load(fromByteOffset: index / 8, as: UInt8.self) >> (index % 8)) & 1)
  }

  /// Returns the number of 0-bit in [0, n) bits of data.
  public func rank0(_ n: Int) -> Int { n - rank1(n) }

  /// Returns the number of 1-bit in [0, n) bits of data.
  public func rank1(_ n: Int) -> Int {
    let data = data.unsafelyUnwrapped
    // Look up pre-computed 1-bits for the preceding chunks.
    let numChunks = n / (chunkSize * 8)
    var result = index[numChunks]

    // Count 1-bits for remaining "words".
    result += Self.count1Bits(
      data + numChunks * chunkSize, (n / 32) - numChunks * (chunkSize / 4))

    // Count 1-bits for remaining "bits".
    if n % 32 > 0 {
      let offset = 4 * (n / 32)
      let shift = UInt32(32 - n % 32)
      result +=
        (data.loadUnaligned(fromByteOffset: offset, as: UInt32.self) << shift)
        .nonzeroBitCount
    }

    return result
  }

  /// Returns the position of n-th 0-bit on the data. (n is 1-origin).
  /// Returned index is 0-origin.
  public func select0(_ n: Int) -> Int {
    assert(n > 0)
    var n = n
    let data = data.unsafelyUnwrapped

    // Narrow down the range of |index_| on which lower bound is performed.
    var lb0CacheIndex = n / lb0CacheIncrement
    if lb0CacheIndex > lb0Cache.count - 2 {
      lb0CacheIndex = lb0Cache.count - 2
    }
    assert(lb0CacheIndex >= 0)

    // Binary search on chunks.
    let chunkPtr = lowerBound0(lb0Cache[lb0CacheIndex], lb0Cache[lb0CacheIndex + 1], n)
    let chunkIndex = chunkPtr - 1
    assert(chunkIndex >= 0)
    n -= chunkSize * 8 * chunkIndex - index[chunkIndex]

    // Linear search on remaining "words"
    var ptr = (chunkIndex * chunkSize) & ~3
    while true {
      let bitCount = (~data.loadUnaligned(fromByteOffset: ptr, as: UInt32.self)).nonzeroBitCount
      if bitCount >= n {
        break
      }
      n -= bitCount
      ptr += 4
    }

    // Select the n-th 0-bit in the word: clear the lowest (n - 1) 1-bits of
    // the inverted word, then the target position is the number of trailing
    // zeros.
    var word = ~data.loadUnaligned(fromByteOffset: ptr, as: UInt32.self)
    while n > 1 {
      word &= word &- 1
      n -= 1
    }
    return ptr * 8 + word.trailingZeroBitCount
  }

  /// Returns the position of n-th 1-bit in the data. (n is 1-origin).
  /// Returned index is 0-origin.
  public func select1(_ n: Int) -> Int {
    assert(n > 0)
    var n = n
    let data = data.unsafelyUnwrapped

    // Narrow down the range of |index_| on which lower bound is performed.
    var lb1CacheIndex = n / lb1CacheIncrement
    if lb1CacheIndex > lb1Cache.count - 2 {
      lb1CacheIndex = lb1Cache.count - 2
    }
    assert(lb1CacheIndex >= 0)

    // Binary search on chunks.
    let chunkPtr = lowerBound1(lb1Cache[lb1CacheIndex], lb1Cache[lb1CacheIndex + 1], n)
    let chunkIndex = chunkPtr - 1
    assert(chunkIndex >= 0)
    n -= index[chunkIndex]

    // Linear search on remaining "words"
    var ptr = (chunkIndex * chunkSize) & ~3
    while true {
      let bitCount = data.loadUnaligned(fromByteOffset: ptr, as: UInt32.self).nonzeroBitCount
      if bitCount >= n {
        break
      }
      n -= bitCount
      ptr += 4
    }

    // Select the n-th 1-bit in the word: clear the lowest (n - 1) 1-bits, then
    // the target position is the number of trailing zeros.
    var word = data.loadUnaligned(fromByteOffset: ptr, as: UInt32.self)
    while n > 1 {
      word &= word &- 1
      n -= 1
    }
    return ptr * 8 + word.trailingZeroBitCount
  }

  public var num1Bits: Int { index[index.count - 1] }
  public var num0Bits: Int { 8 * length - index[index.count - 1] }

  // MARK: - Private helpers (anonymous namespace in C++)

  /// The view of 1-bit index as 0-bit index (ZeroBitIndexIterator):
  /// The number of 0-bits
  ///   = (total num bits) - (1-bits)
  ///   = (chunk_size [bytes] * 8 [bits/byte] * (ptr's offset) - (1-bits)
  @inline(__always)
  private static func zeroBitIndex(_ index: [Int], _ chunkSize: Int, _ i: Int) -> Int {
    chunkSize * 8 * i - index[i]
  }

  /// std::lower_bound over [first, last) of the 0-bit view of `index`.
  private func lowerBound0(_ first: Int, _ last: Int, _ value: Int) -> Int {
    Self.lowerBound0(index, chunkSize, first, last, value)
  }

  private static func lowerBound0(
    _ index: [Int], _ chunkSize: Int, _ first: Int, _ last: Int, _ value: Int
  ) -> Int {
    var first = first
    var count = last - first
    while count > 0 {
      let step = count / 2
      let it = first + step
      if zeroBitIndex(index, chunkSize, it) < value {
        first = it + 1
        count -= step + 1
      } else {
        count = step
      }
    }
    return first
  }

  /// std::lower_bound over [first, last) of `index`.
  private func lowerBound1(_ first: Int, _ last: Int, _ value: Int) -> Int {
    Self.lowerBound1(index, first, last, value)
  }

  private static func lowerBound1(_ index: [Int], _ first: Int, _ last: Int, _ value: Int) -> Int {
    var first = first
    var count = last - first
    while count > 0 {
      let step = count / 2
      let it = first + step
      if index[it] < value {
        first = it + 1
        count -= step + 1
      } else {
        count = step
      }
    }
    return first
  }

  /// Returns 1-bits in the data to length 32-bit words.
  /// Processes in 64-bit words as much as possible for speed.
  @inline(__always)
  private static func count1Bits(_ data: UnsafeRawPointer, _ length: Int) -> Int {
    var numBits = 0
    var offset = 0
    var length = length
    while length >= 2 {
      numBits += data.loadUnaligned(fromByteOffset: offset, as: UInt64.self).nonzeroBitCount
      offset += 8
      length -= 2
    }
    if length == 1 {
      numBits += data.loadUnaligned(fromByteOffset: offset, as: UInt32.self).nonzeroBitCount
    }
    return numBits
  }

  /// Stores index (the cumulative number of the 1-bits from begin of each
  /// chunk).
  private static func initIndex(
    _ data: UnsafeRawPointer, _ length: Int, _ chunkSize: Int, _ index: inout [Int]
  ) {
    assert(chunkSize >= 4)
    assert(chunkSize.nonzeroBitCount == 1, "\(chunkSize)")
    assert(length % 4 == 0)

    index.removeAll()

    // Count the number of chunks with ceiling.
    let chunkLength = (length + chunkSize - 1) / chunkSize

    // Reserve the memory including a sentinel.
    index.reserveCapacity(chunkLength + 1)

    var numBits = 0
    var offset = 0
    var remainingNumWords = length / 4
    while remainingNumWords > 0 {
      index.append(numBits)
      numBits += count1Bits(data + offset, min(chunkSize / 4, remainingNumWords))
      offset += chunkSize
      remainingNumWords -= chunkSize / 4
    }
    index.append(numBits)

    precondition(chunkLength + 1 == index.count)
  }

  private static func initLowerBound0Cache(
    _ index: [Int], _ chunkSize: Int, _ increment: Int, _ size: Int, _ cache: inout [Int]
  ) {
    assert(increment > 0)
    cache.removeAll()
    cache.reserveCapacity(size + 2)
    cache.append(0)
    if size >= 1 {
      for i in 1...size {
        let targetIndex = increment * i
        cache.append(lowerBound0(index, chunkSize, 0, index.count, targetIndex))
      }
    }
    cache.append(index.count)
  }

  private static func initLowerBound1Cache(
    _ index: [Int], _ increment: Int, _ size: Int, _ cache: inout [Int]
  ) {
    assert(increment > 0)
    cache.removeAll()
    cache.reserveCapacity(size + 2)
    cache.append(0)
    if size >= 1 {
      for i in 1...size {
        let targetIndex = increment * i
        cache.append(lowerBound1(index, 0, index.count, targetIndex))
      }
    }
    cache.append(index.count)
  }
}
