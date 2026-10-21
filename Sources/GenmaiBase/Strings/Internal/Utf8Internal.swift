// Port of mozc/src/base/strings/internal/utf8_internal.{h,cc} (3.35.6354).

/// A Unicode code point as used by Mozc (`char32_t`). It is a plain integer,
/// so values outside of the Unicode scalar range (surrogates, > U+10FFFF) can
/// be represented exactly like in C++.
public typealias Char32 = UInt32

public enum Utf8Internal {
  public static let kMaxByteSize = 4
  public static let kCharsInByte = 256
  public static let kReplacementCharacter: Char32 = 0xFFFD

  // C0, C1 are disallowed in UTF-8. F5-FF are disallowed in UTF-8.
  public static let kUtf8LenTbl: [UInt8] = {
    var table = [UInt8](repeating: 1, count: 256)
    for i in 0xC2...0xDF { table[i] = 2 }
    for i in 0xE0...0xEF { table[i] = 3 }
    for i in 0xF0...0xF4 { table[i] = 4 }
    return table
  }()

  /// Returns the byte length of a single UTF-8 character based on the leading
  /// byte. Identical to `kUtf8LenTbl[c]`.
  public static func oneCharLen(_ c: UInt8) -> Int {
    if c < 0xC2 { return 1 }
    if c < 0xE0 { return 2 }
    if c < 0xF0 { return 3 }
    if c < 0xF5 { return 4 }
    return 1
  }

  public struct EncodeResult: Sendable, Equatable {
    // Up to four bytes.
    public let b0: UInt8, b1: UInt8, b2: UInt8, b3: UInt8
    /// The byte length.
    public let count: Int

    /// Returns an EncodeResult for a single ASCII code point cp.
    static func ascii(_ cp: Char32) -> EncodeResult {
      EncodeResult(b0: UInt8(truncatingIfNeeded: cp), b1: 0, b2: 0, b3: 0, count: 1)
    }

    /// Encodes a Unicode character cp in UTF-8 according to the count and
    /// offset parameters as in https://encoding.spec.whatwg.org/#utf-8-encoder.
    static func encodeSequence(_ cp: Char32, _ count: Int, _ offset: UInt8) -> EncodeResult {
      var bytes: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
      bytes.0 = UInt8(truncatingIfNeeded: cp >> (kShift * UInt32(count))) &+ offset
      var c = count
      var n = 1
      while c > 0 {
        let temp = UInt8(truncatingIfNeeded: cp >> (kShift * UInt32(c - 1)))
        let v: UInt8 = 0x80 | (temp & 0x3f)
        switch n {
        case 1: bytes.1 = v
        case 2: bytes.2 = v
        default: bytes.3 = v
        }
        n += 1
        c -= 1
      }
      // count_ in the result is the byte length.
      return EncodeResult(b0: bytes.0, b1: bytes.1, b2: bytes.2, b3: bytes.3, count: count + 1)
    }

    /// The encoded bytes.
    public var bytes: [UInt8] { Array([b0, b1, b2, b3].prefix(count)) }

    /// Appends the encoded bytes to `dest`.
    public func append(to dest: inout [UInt8]) {
      dest.append(b0)
      if count > 1 { dest.append(b1) }
      if count > 2 { dest.append(b2) }
      if count > 3 { dest.append(b3) }
    }
  }

  public struct DecodeResult: Sendable, Equatable {
    /// Decoded code point. kReplacementCharacter if error.
    public let codePoint: Char32
    /// True if the UTF-8 string is valid.
    public let ok: Bool
    /// Number of processed bytes. 0-4 bytes.
    public let bytesSeen: Int

    public static func `continue`(_ cp: Char32, _ bytesSeen: Int) -> DecodeResult {
      DecodeResult(codePoint: cp, ok: true, bytesSeen: bytesSeen)
    }

    public static func error(_ bytesSeen: Int) -> DecodeResult {
      DecodeResult(codePoint: kReplacementCharacter, ok: false, bytesSeen: bytesSeen)
    }

    /// Indicates that the decoded position is the `end` sentinel.
    public static var sentinel: DecodeResult { DecodeResult(codePoint: 0, ok: false, bytesSeen: 0) }

    public var isSentinel: Bool { bytesSeen == 0 }

    public init(codePoint: Char32, ok: Bool, bytesSeen: Int) {
      self.codePoint = codePoint
      self.ok = ok
      self.bytesSeen = bytesSeen
    }
  }

  static let kShift: UInt32 = 6
  static let kTrailingMask: UInt8 = (1 << 6) - 1

  // From Unicode 15.0 §3.9 Table 3-7: Well-Formed UTF-8 Byte Sequences
  static func secondByteBoundary(_ n: UInt8) -> (min: UInt8, max: UInt8) {
    if n < 0xc2 || 0xf4 < n {
      // Not a valid leading byte.
      return (0xff, 0x00)
    } else if n == 0xe0 {
      return (0xa0, 0xbf)
    } else if n == 0xed {
      return (0x80, 0x9f)
    } else if n == 0xf0 {
      return (0x90, 0xbf)
    } else if n == 0xf4 {
      return (0x80, 0x8f)
    } else {
      // C2..DF, E1..EC, EE..EF, F1..F3
      return (0x80, 0xbf)
    }
  }

  static func isTrailingByte(_ c: UInt8) -> Bool { (c & 0xc0) == 0x80 }

  static func isValidSecondByte(_ leadingByte: UInt8, _ secondByte: UInt8) -> Bool {
    let boundary = secondByteBoundary(leadingByte)
    return boundary.min <= secondByte && secondByte <= boundary.max
  }

  static func appendTrailingByte(_ base: Char32, _ byte: UInt8) -> Char32 {
    (base << kShift) + Char32(byte & kTrailingMask)
  }

  public static func encode(_ cp: Char32) -> EncodeResult {
    // This is a naive UTF-8 encoder based on the WHATWG Encoding standard.
    // https://encoding.spec.whatwg.org/#utf-8-encoder
    if cp <= 0x7f {
      return .ascii(cp)
    } else if cp <= 0x7ff {
      return .encodeSequence(cp, 1, 0xc0)
    } else if cp <= 0xffff {
      return .encodeSequence(cp, 2, 0xe0)
    } else if cp <= 0x10ffff {
      return .encodeSequence(cp, 3, 0xf0)
    } else {
      // Unicode 15.0 §3.4 Characters and Encoding D9
      // "Unicode codespace: A range of integers from 0 to 0x10FFFF."
      // §3.9 UTF-32 D90
      // "Any UTF-32 code unit greater than 0010FFFF16 is ill-formed."
      return encode(kReplacementCharacter)
    }
  }

  /// Decodes the first character of `bytes`, where `available` is the number
  /// of valid bytes in the tuple (`last - ptr` clipped to 4).
  public static func decode(_ bytes: (UInt8, UInt8, UInt8, UInt8), available: Int) -> DecodeResult {
    if available == 0 {
      return .sentinel
    }
    // https://encoding.spec.whatwg.org/#utf-8-decoder
    // Note that bytes needed and bytes seen include the leading byte here.
    let b0 = bytes.0
    if b0 < 0x80 {
      // Fast path for ASCII.
      return .continue(Char32(b0), 1)
    }
    let needed = oneCharLen(b0)
    if available < needed {
      // If the buffer is not long enough, stop processing and return error.
      // The Unicode Standard requires implementations to check each byte
      // regardless, so we're just performing the check here.
      if available == 1 || !isValidSecondByte(b0, bytes.1) {
        return .error(1)
      }
      var seen = 2
      if available > 2 {
        if !isTrailingByte(bytes.2) { return .error(seen) }
        seen += 1
      }
      return .error(seen)
    }
    // The overwhelming majority of UTF-8 characters in Mozc are three bytes
    // long.
    let mask: UInt8
    switch needed {
    case 3: mask = 0x0f
    case 2: mask = 0x1f
    case 4: mask = 0x07
    default:
      // Trailing and disallowed bytes fall here.
      return .error(1)
    }
    var base = Char32(b0 & mask)
    // Decode the second byte.
    let secondOk = needed == 2 ? isTrailingByte(bytes.1) : isValidSecondByte(b0, bytes.1)
    if !secondOk {
      return .error(1)
    }
    base = appendTrailingByte(base, bytes.1)
    // Third and fourth bytes are always within [0x80, 0xbf].
    if needed >= 3 {
      if !isTrailingByte(bytes.2) { return .error(2) }
      base = appendTrailingByte(base, bytes.2)
    }
    if needed == 4 {
      if !isTrailingByte(bytes.3) { return .error(3) }
      base = appendTrailingByte(base, bytes.3)
    }
    return .continue(base, needed)
  }

  /// Decodes the character at `index` of `bytes` (the C++ `Decode(ptr, last)`
  /// with `last = bytes.end()`).
  public static func decode<C: Collection>(_ bytes: C, from index: C.Index) -> DecodeResult
  where C.Element == UInt8 {
    var b: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
    var n = 0
    var i = index
    while n < 4 && i != bytes.endIndex {
      switch n {
      case 0: b.0 = bytes[i]
      case 1: b.1 = bytes[i]
      case 2: b.2 = bytes[i]
      default: b.3 = bytes[i]
      }
      n += 1
      bytes.formIndex(after: &i)
    }
    return decode(b, available: n)
  }

  /// Decodes the first character of `bytes`.
  public static func decode<C: Collection>(_ bytes: C) -> DecodeResult where C.Element == UInt8 {
    decode(bytes, from: bytes.startIndex)
  }
}
