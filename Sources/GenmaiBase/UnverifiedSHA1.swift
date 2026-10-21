// Port of mozc/src/base/unverified_sha1.{h,cc} (3.35.6354).

// Note that this implementation is kept just for the backward compatibility
// so that we can read previously obfuscated data.
// !!! Not FIPS-certified.
// !!! Performance optimization is not well considered.
// !!! Side-channel attack is not well considered.
public enum UnverifiedSHA1 {
  private static let kNumDWordsOfDigest = 5
  // SHA1 uses 64-byte (512-bit) message block.
  private static let kMessageBlockBytes = 64
  // The original data length in bit is stored as 8-byte-length data.
  private static let kDataBitLengthBytes = 8

  // See 4.1.1 SHA-1 Functions
  @inline(__always)
  private static func f(_ t: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
    if t < 20 {
      return (x & y) ^ ((~x) & z)
    } else if t < 40 {
      return x ^ y ^ z
    } else if t < 60 {
      return (x & y) ^ (x & z) ^ (y & z)
    } else {
      return x ^ y ^ z
    }
  }

  @inline(__always)
  private static func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 {
    (x << n) | (x >> (32 - n))
  }

  // See 4.2.1 SHA-1 Constants
  @inline(__always)
  private static func k(_ t: Int) -> UInt32 {
    if t < 20 {
      return 0x5a82_7999
    } else if t < 40 {
      return 0x6ed9_eba1
    } else if t < 60 {
      return 0x8f1b_bcdc
    } else {
      return 0xca62_c1d6
    }
  }

  // Returns the total message count.
  private static func totalMessageCount(_ originalMessageSize: Int) -> Int {
    // At minimum, we need additional 9 bytes (end-of-data marker + bit length).
    let minimumSize = originalMessageSize + 1 + kDataBitLengthBytes
    return (minimumSize + kMessageBlockBytes - 1) / kMessageBlockBytes
  }

  // Implements 5.1 Padding the Message / 5.1.1 SHA-1, SHA-224 and SHA-256
  private static func fillMessage(
    _ source: UnsafeBufferPointer<UInt8>, _ messageIndex: Int, _ dest: inout [UInt8]
  ) {
    let baseIndex = messageIndex * kMessageBlockBytes
    var cursor = 0
    if baseIndex < source.count {
      let rest = source.count - baseIndex
      if rest >= kMessageBlockBytes {
        for i in 0..<kMessageBlockBytes { dest[i] = source[baseIndex + i] }
        return
      }
      for i in 0..<rest { dest[i] = source[baseIndex + i] }
      cursor = rest
    }
    // Put the end-of-data marker.
    if baseIndex + cursor == source.count {
      dest[cursor] = 0x80
      cursor += 1
    }
    let kMessageBlockZeroFillLimit = kMessageBlockBytes - kDataBitLengthBytes
    if cursor > kMessageBlockZeroFillLimit {
      // The current message block does not have enough room to store 8-byte
      // length data. The data length will be stored into the next message.
      for i in cursor..<kMessageBlockBytes { dest[i] = 0 }
      return
    }
    // Fill 0x00 for padding.
    for i in cursor..<kMessageBlockZeroFillLimit { dest[i] = 0 }
    // Store the original data bit-length into the last 8-byte (big-endian).
    let bitLength = UInt64(source.count) &* 8
    for i in 0..<8 {
      dest[kMessageBlockZeroFillLimit + i] = UInt8(truncatingIfNeeded: bitLength >> UInt64(56 - 8 * i))
    }
  }

  /// Returns 20-byte-length SHA1 digest.
  public static func makeDigest(_ source: UnsafeBufferPointer<UInt8>) -> [UInt8] {
    // 5.3 Setting the Initial Hash Value / 5.3.1 SHA-1
    var h: [UInt32] = [0x6745_2301, 0xefcd_ab89, 0x98ba_dcfe, 0x1032_5476, 0xc3d2_e1f0]
    var message = [UInt8](repeating: 0, count: kMessageBlockBytes)
    var w = [UInt32](repeating: 0, count: 80)  // Message schedule.
    // 6.1.2 SHA-1 Hash Computation
    for index in 0..<totalMessageCount(source.count) {
      fillMessage(source, index, &message)
      for i in 0..<16 {
        let b = i * 4
        w[i] = UInt32(message[b]) << 24 | UInt32(message[b + 1]) << 16
          | UInt32(message[b + 2]) << 8 | UInt32(message[b + 3])
      }
      for t in 16..<80 {
        w[t] = rotl(w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16], 1)
      }
      var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4]
      for t in 0..<80 {
        let tt = rotl(a, 5) &+ f(t, b, c, d) &+ e &+ w[t] &+ k(t)
        e = d
        d = c
        c = rotl(b, 30)
        b = a
        a = tt
      }
      h[0] &+= a
      h[1] &+= b
      h[2] &+= c
      h[3] &+= d
      h[4] &+= e
    }
    // SHA1 algorithm is defined on big-endian.
    var result: [UInt8] = []
    result.reserveCapacity(20)
    for v in h {
      result.append(UInt8(truncatingIfNeeded: v >> 24))
      result.append(UInt8(truncatingIfNeeded: v >> 16))
      result.append(UInt8(truncatingIfNeeded: v >> 8))
      result.append(UInt8(truncatingIfNeeded: v))
    }
    return result
  }

  public static func makeDigest(_ source: some Collection<UInt8>) -> [UInt8] {
    let array = Array(source)
    return array.withUnsafeBufferPointer { makeDigest($0) }
  }

  public static func makeDigest(_ source: String) -> [UInt8] {
    makeDigest(Array(source.utf8))
  }
}
