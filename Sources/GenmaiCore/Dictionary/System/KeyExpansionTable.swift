// Port of mozc/src/dictionary/system/key_expansion_table.h (3.35.6354).
//
// Deviation: keys/values are `UInt8` (edge labels of the LOUDS trie). The C++
// code takes `char`, which is signed on the reference platforms, so labels
// >= 0x80 would index out of bounds there; only encoded-ASCII labels are ever
// added (see BuildHiraganaExpansionTable), and other labels hit the identity
// matrix in both implementations.

/// Very thin wrapper class to check the edge annotated character is hit the
/// expanded key or not.
/// Note that this type is very small so it's ok to be copied.
public struct ExpandedKey {
  // 256 bits.
  @usableFromInline let data: (UInt64, UInt64, UInt64, UInt64)

  @inlinable
  init(_ data: (UInt64, UInt64, UInt64, UInt64)) {
    self.data = data
  }

  @inlinable @inline(__always)
  public func isHit(_ value: UInt8) -> Bool {
    let word: UInt64
    switch value >> 6 {
    case 0: word = data.0
    case 1: word = data.1
    case 2: word = data.2
    default: word = data.3
    }
    return (word >> UInt64(value & 63)) & 1 != 0
  }
}

/// Table to keep the key expanding information.
/// Implementation Note: This type holds a 256x256 bitmap table.
/// The client (typically SystemDictionary over LoudsTrie) can check if the
/// value is hit to the expanded key or not.
/// TODO(hidehiko): We should have yet another way for Key Expansion.
///   For example, by holding expanded characters directly, and iterate
///   both sorted edge annotated characters and expanded keys.
///   Check the performance of it, and if it's efficient, move to it.
public struct KeyExpansionTable: Sendable {
  // 256x256 (key -> value) bit map matrix, 4 x 64 bits per key.
  private var table: [UInt64]

  public init() {
    table = [UInt64](repeating: 0, count: 256 * 4)
    // Initialize with identity matrix.
    for i in 0..<256 {
      setBit(UInt8(i), UInt8(i))
    }
  }

  /// Add expanding data of the given key.
  public mutating func add(_ key: UInt8, _ data: some Collection<UInt8>) {
    for v in data {
      setBit(key, v)
    }
  }

  /// Character version (`char`) for tests.
  public mutating func add(_ key: Character, _ data: String) {
    add(key.asciiValue!, Array(data.utf8))
  }

  @inline(__always)
  public func expandKey(_ key: UInt8) -> ExpandedKey {
    let base = Int(key) * 4
    return table.withUnsafeBufferPointer { t in
      ExpandedKey((t[base], t[base + 1], t[base + 2], t[base + 3]))
    }
  }

  /// Returns the default (no-effective) KeyExpansionTable instance.
  /// (in other words, the result holds identity-bitmap matrix).
  public static let defaultInstance = KeyExpansionTable()

  /// Set a bit corresponding (key -> value) to '1'.
  private mutating func setBit(_ key: UInt8, _ value: UInt8) {
    table[Int(key) * 4 + Int(value >> 6)] |= UInt64(1) << UInt64(value & 63)
  }
}
