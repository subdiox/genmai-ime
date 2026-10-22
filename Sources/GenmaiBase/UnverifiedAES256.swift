// Port of mozc/src/base/unverified_aes256.{h,cc} (3.35.6354).

// Note that this implementation is kept just for the backward compatibility
// so that we can read previously obfuscated data.
// !!! Not FIPS-certified.
// !!! Performance optimization is not well considered.
// !!! Side-channel attack is not well considered.
public enum UnverifiedAES256 {
  public static let kKeyBytes = 32  // 256 bit
  public static let kBlockBytes = 16  // 128 bit
  public static let kKeyScheduleBytes = 240

  static let kSBox: [UInt8] = [
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b,
    0xfe, 0xd7, 0xab, 0x76, 0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0,
    0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0, 0xb7, 0xfd, 0x93, 0x26,
    0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2,
    0xeb, 0x27, 0xb2, 0x75, 0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0,
    0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84, 0x53, 0xd1, 0x00, 0xed,
    0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f,
    0x50, 0x3c, 0x9f, 0xa8, 0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5,
    0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2, 0xcd, 0x0c, 0x13, 0xec,
    0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14,
    0xde, 0x5e, 0x0b, 0xdb, 0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c,
    0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79, 0xe7, 0xc8, 0x37, 0x6d,
    0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f,
    0x4b, 0xbd, 0x8b, 0x8a, 0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e,
    0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e, 0xe1, 0xf8, 0x98, 0x11,
    0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f,
    0xb0, 0x54, 0xbb, 0x16,
  ]

  static let kInvSBox: [UInt8] = [
    0x52, 0x09, 0x6a, 0xd5, 0x30, 0x36, 0xa5, 0x38, 0xbf, 0x40, 0xa3, 0x9e,
    0x81, 0xf3, 0xd7, 0xfb, 0x7c, 0xe3, 0x39, 0x82, 0x9b, 0x2f, 0xff, 0x87,
    0x34, 0x8e, 0x43, 0x44, 0xc4, 0xde, 0xe9, 0xcb, 0x54, 0x7b, 0x94, 0x32,
    0xa6, 0xc2, 0x23, 0x3d, 0xee, 0x4c, 0x95, 0x0b, 0x42, 0xfa, 0xc3, 0x4e,
    0x08, 0x2e, 0xa1, 0x66, 0x28, 0xd9, 0x24, 0xb2, 0x76, 0x5b, 0xa2, 0x49,
    0x6d, 0x8b, 0xd1, 0x25, 0x72, 0xf8, 0xf6, 0x64, 0x86, 0x68, 0x98, 0x16,
    0xd4, 0xa4, 0x5c, 0xcc, 0x5d, 0x65, 0xb6, 0x92, 0x6c, 0x70, 0x48, 0x50,
    0xfd, 0xed, 0xb9, 0xda, 0x5e, 0x15, 0x46, 0x57, 0xa7, 0x8d, 0x9d, 0x84,
    0x90, 0xd8, 0xab, 0x00, 0x8c, 0xbc, 0xd3, 0x0a, 0xf7, 0xe4, 0x58, 0x05,
    0xb8, 0xb3, 0x45, 0x06, 0xd0, 0x2c, 0x1e, 0x8f, 0xca, 0x3f, 0x0f, 0x02,
    0xc1, 0xaf, 0xbd, 0x03, 0x01, 0x13, 0x8a, 0x6b, 0x3a, 0x91, 0x11, 0x41,
    0x4f, 0x67, 0xdc, 0xea, 0x97, 0xf2, 0xcf, 0xce, 0xf0, 0xb4, 0xe6, 0x73,
    0x96, 0xac, 0x74, 0x22, 0xe7, 0xad, 0x35, 0x85, 0xe2, 0xf9, 0x37, 0xe8,
    0x1c, 0x75, 0xdf, 0x6e, 0x47, 0xf1, 0x1a, 0x71, 0x1d, 0x29, 0xc5, 0x89,
    0x6f, 0xb7, 0x62, 0x0e, 0xaa, 0x18, 0xbe, 0x1b, 0xfc, 0x56, 0x3e, 0x4b,
    0xc6, 0xd2, 0x79, 0x20, 0x9a, 0xdb, 0xc0, 0xfe, 0x78, 0xcd, 0x5a, 0xf4,
    0x1f, 0xdd, 0xa8, 0x33, 0x88, 0x07, 0xc7, 0x31, 0xb1, 0x12, 0x10, 0x59,
    0x27, 0x80, 0xec, 0x5f, 0x60, 0x51, 0x7f, 0xa9, 0x19, 0xb5, 0x4a, 0x0d,
    0x2d, 0xe5, 0x7a, 0x9f, 0x93, 0xc9, 0x9c, 0xef, 0xa0, 0xe0, 0x3b, 0x4d,
    0xae, 0x2a, 0xf5, 0xb0, 0xc8, 0xeb, 0xbb, 0x3c, 0x83, 0x53, 0x99, 0x61,
    0x17, 0x2b, 0x04, 0x7e, 0xba, 0x77, 0xd6, 0x26, 0xe1, 0x69, 0x14, 0x63,
    0x55, 0x21, 0x0c, 0x7d,
  ]

  private static let kNr = 14

  private static func addRoundKey(_ block: UnsafeMutablePointer<UInt8>, _ roundKey: UnsafePointer<UInt8>) {
    for i in 0..<kBlockBytes {
      block[i] ^= roundKey[i]
    }
  }

  // Multiplication by 2 in GF(2^8) (named GF_p8_mul3 in the C++ code).
  @inline(__always)
  private static func gfP8Mul3(_ val: UInt8) -> UInt8 {
    let x = val &* 2
    return val >= 0x80 ? (x ^ 0x1b) : x
  }

  private static func mixColumnsImpl(_ column: UnsafeMutablePointer<UInt8>) {
    var a1 = [UInt8](repeating: 0, count: 4)
    var a2 = a1
    var a3 = a1
    for i in 0..<4 {
      a1[i] = column[i]
      a2[i] = gfP8Mul3(a1[i])
      a3[i] = a2[i] ^ a1[i]
    }
    column[0] = a2[0] ^ a3[1] ^ a1[2] ^ a1[3]
    column[1] = a1[0] ^ a2[1] ^ a3[2] ^ a1[3]
    column[2] = a1[0] ^ a1[1] ^ a2[2] ^ a3[3]
    column[3] = a3[0] ^ a1[1] ^ a1[2] ^ a2[3]
  }

  private static func invMixColumnsImpl(_ column: UnsafeMutablePointer<UInt8>) {
    var a9 = [UInt8](repeating: 0, count: 4)
    var a11 = a9
    var a13 = a9
    var a14 = a9
    for i in 0..<4 {
      let a1 = column[i]
      let a2 = gfP8Mul3(a1)
      let a2_2 = gfP8Mul3(a2)
      a9[i] = gfP8Mul3(a2_2) ^ a1
      a11[i] = gfP8Mul3(a2_2 ^ a1) ^ a1
      let a2a1_2 = gfP8Mul3(a2 ^ a1)
      a13[i] = gfP8Mul3(a2a1_2) ^ a1
      a14[i] = gfP8Mul3(a2a1_2 ^ a1)
    }
    column[0] = a14[0] ^ a11[1] ^ a13[2] ^ a9[3]
    column[1] = a9[0] ^ a14[1] ^ a11[2] ^ a13[3]
    column[2] = a13[0] ^ a9[1] ^ a14[2] ^ a11[3]
    column[3] = a11[0] ^ a13[1] ^ a9[2] ^ a14[3]
  }

  /// Does AES256 CBC transformation in place. `block.count` must be a multiple
  /// of kBlockBytes.
  public static func transformCBC(key: [UInt8], iv: [UInt8], block: inout [UInt8]) {
    precondition(block.count % kBlockBytes == 0)
    block.withUnsafeMutableBufferPointer {
      transformCBC(key: key, iv: iv, block: $0.baseAddress!, blockCount: $0.count / kBlockBytes)
    }
  }

  /// Does AES256 CBC inverse transformation in place.
  public static func inverseTransformCBC(key: [UInt8], iv: [UInt8], block: inout [UInt8]) {
    precondition(block.count % kBlockBytes == 0)
    block.withUnsafeMutableBufferPointer {
      inverseTransformCBC(key: key, iv: iv, block: $0.baseAddress!, blockCount: $0.count / kBlockBytes)
    }
  }

  public static func transformCBC(
    key: [UInt8], iv: [UInt8], block: UnsafeMutablePointer<UInt8>, blockCount: Int
  ) {
    precondition(key.count == kKeyBytes && iv.count == kBlockBytes)
    let w = makeKeySchedule(key)
    var vec = iv
    w.withUnsafeBufferPointer { w in
      for i in 0..<blockCount {
        let src = block + i * kBlockBytes
        for j in 0..<kBlockBytes {
          src[j] ^= vec[j]
        }
        transformECB(w.baseAddress!, src)
        for j in 0..<kBlockBytes { vec[j] = src[j] }
      }
    }
  }

  public static func inverseTransformCBC(
    key: [UInt8], iv: [UInt8], block: UnsafeMutablePointer<UInt8>, blockCount: Int
  ) {
    precondition(key.count == kKeyBytes && iv.count == kBlockBytes)
    let w = makeKeySchedule(key)
    var prevBlock = iv
    var original = [UInt8](repeating: 0, count: kBlockBytes)
    w.withUnsafeBufferPointer { w in
      for i in 0..<blockCount {
        let current = block + i * kBlockBytes
        for j in 0..<kBlockBytes { original[j] = current[j] }
        inverseTransformECB(w.baseAddress!, current)
        for j in 0..<kBlockBytes {
          current[j] ^= prevBlock[j]
        }
        prevBlock = original
      }
    }
  }

  static func makeKeySchedule(_ key: [UInt8]) -> [UInt8] {
    var w = [UInt8](repeating: 0, count: kKeyScheduleBytes)
    for i in 0..<kKeyBytes { w[i] = key[i] }
    var base = 1
    while true {
      let k = base * kKeyBytes
      let prev = k - kKeyBytes
      // Note: Although the following equation is not always satisfied,
      // it is valid at least when 1 <= |base| <= 7.
      let rcon = UInt8(1 << (base - 1))
      w[k + 0] = w[prev + 0] ^ kSBox[Int(w[prev + 29])] ^ rcon
      w[k + 1] = w[prev + 1] ^ kSBox[Int(w[prev + 30])]
      w[k + 2] = w[prev + 2] ^ kSBox[Int(w[prev + 31])]
      w[k + 3] = w[prev + 3] ^ kSBox[Int(w[prev + 28])]
      for i in 4..<16 {
        w[k + i] = w[prev + i] ^ w[k + i - 4]
      }
      if base == 7 {
        break
      }
      for i in 16..<20 {
        w[k + i] = w[prev + i] ^ kSBox[Int(w[k + i - 4])]
      }
      for i in 20..<32 {
        w[k + i] = w[prev + i] ^ w[k + i - 4]
      }
      base += 1
    }
    return w
  }

  static func subBytes(_ block: UnsafeMutablePointer<UInt8>) {
    for i in 0..<kBlockBytes {
      block[i] = kSBox[Int(block[i])]
    }
  }

  static func invSubBytes(_ block: UnsafeMutablePointer<UInt8>) {
    for i in 0..<kBlockBytes {
      block[i] = kInvSBox[Int(block[i])]
    }
  }

  static func mixColumns(_ block: UnsafeMutablePointer<UInt8>) {
    for i in stride(from: 0, to: kBlockBytes, by: 4) {
      mixColumnsImpl(block + i)
    }
  }

  static func invMixColumns(_ block: UnsafeMutablePointer<UInt8>) {
    for i in stride(from: 0, to: kBlockBytes, by: 4) {
      invMixColumnsImpl(block + i)
    }
  }

  static func shiftRows(_ block: UnsafeMutablePointer<UInt8>) {
    // Row 0 does not change.
    // Row 1
    var x = block[1]
    block[1] = block[5]
    block[5] = block[9]
    block[9] = block[13]
    block[13] = x
    // Row 2
    x = block[2]
    block[2] = block[10]
    block[10] = x
    x = block[6]
    block[6] = block[14]
    block[14] = x
    // Row 3
    x = block[3]
    block[3] = block[15]
    block[15] = block[11]
    block[11] = block[7]
    block[7] = x
  }

  static func invShiftRows(_ block: UnsafeMutablePointer<UInt8>) {
    // Row 0 does not change.
    // Row 1
    var x = block[1]
    block[1] = block[13]
    block[13] = block[9]
    block[9] = block[5]
    block[5] = x
    // Row 2
    x = block[2]
    block[2] = block[10]
    block[10] = x
    x = block[6]
    block[6] = block[14]
    block[14] = x
    // Row 3
    x = block[3]
    block[3] = block[7]
    block[7] = block[11]
    block[11] = block[15]
    block[15] = x
  }

  static func transformECB(_ w: UnsafePointer<UInt8>, _ block: UnsafeMutablePointer<UInt8>) {
    addRoundKey(block, w)
    for round in 1..<kNr {
      subBytes(block)
      shiftRows(block)
      mixColumns(block)
      addRoundKey(block, w + kBlockBytes * round)
    }
    subBytes(block)
    shiftRows(block)
    addRoundKey(block, w + kBlockBytes * kNr)
  }

  static func inverseTransformECB(_ w: UnsafePointer<UInt8>, _ block: UnsafeMutablePointer<UInt8>) {
    addRoundKey(block, w + kBlockBytes * kNr)
    invShiftRows(block)
    invSubBytes(block)
    var round = kNr - 1
    while round > 0 {
      addRoundKey(block, w + kBlockBytes * round)
      invMixColumns(block)
      invShiftRows(block)
      invSubBytes(block)
      round -= 1
    }
    addRoundKey(block, w)
  }
}
