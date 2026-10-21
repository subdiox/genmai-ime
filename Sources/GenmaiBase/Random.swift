// Port of mozc/src/base/random.{h,cc} (3.35.6354).
//
// absl::BitGen is replaced by SystemRandomNumberGenerator (default) or a
// deterministic xoshiro256** generator when a seed is given (the C++ code uses
// `Random(std::seed_seq{})` for determinism in tests). Sequences therefore do
// not match the C++ ones; only the statistical behavior is the same.

/// Random is a utility type to generate random sequences. It conforms to
/// RandomNumberGenerator, so it can be passed to `Int.random(in:using:)` etc.
public struct Random: RandomNumberGenerator, Sendable {
  private enum Source: Sendable {
    case system
    case seeded(Xoshiro256StarStar)
  }

  private var source: Source

  public init() {
    source = .system
  }

  /// Deterministic generator.
  public init(seed: UInt64) {
    source = .seeded(Xoshiro256StarStar(seed: seed))
  }

  public mutating func next() -> UInt64 {
    switch source {
    case .system:
      var g = SystemRandomNumberGenerator()
      return g.next()
    case .seeded(var g):
      let v = g.next()
      source = .seeded(g)
      return v
    }
  }

  /// Generates a random valid utf-8 sequence with len codepoints [lo, hi].
  public mutating func utf8String(_ len: Int, _ lo: UInt32, _ hi: UInt32) -> String {
    var result: [UInt8] = []
    result.reserveCapacity(len)
    for _ in 0..<len {
      Random.appendUTF8(UInt32.random(in: lo...hi, using: &self), to: &result)
    }
    return String(decoding: result, as: UTF8.self)
  }

  /// Generates a random valid utf-8 sequence with [1, len_max] codepoints
  /// [lo, hi].
  public mutating func utf8StringRandomLen(_ lenMax: Int, _ lo: UInt32, _ hi: UInt32) -> String {
    utf8String(Int.random(in: 1...lenMax, using: &self), lo, hi)
  }

  /// Generates a random binary ([0, 0xff]) string of size bytes.
  /// Note that NUL can be in the middle of the sequence.
  public mutating func byteString(_ size: Int) -> [UInt8] {
    var result = [UInt8](repeating: 0, count: size)
    for i in 0..<size {
      result[i] = UInt8.random(in: .min ... .max, using: &self)
    }
    return result
  }

  // Same encoding as Util::CodepointToUtf8Append.
  private static func appendUTF8(_ c: UInt32, to out: inout [UInt8]) {
    if c < 0x80 {
      out.append(UInt8(c))
    } else if c < 0x800 {
      out.append(UInt8(0xC0 | (c >> 6)))
      out.append(UInt8(0x80 | (c & 0x3F)))
    } else if c < 0x10000 {
      out.append(UInt8(0xE0 | (c >> 12)))
      out.append(UInt8(0x80 | ((c >> 6) & 0x3F)))
      out.append(UInt8(0x80 | (c & 0x3F)))
    } else if c < 0x110000 {
      out.append(UInt8(0xF0 | (c >> 18)))
      out.append(UInt8(0x80 | ((c >> 12) & 0x3F)))
      out.append(UInt8(0x80 | ((c >> 6) & 0x3F)))
      out.append(UInt8(0x80 | (c & 0x3F)))
    }
  }
}

/// xoshiro256** seeded through SplitMix64.
struct Xoshiro256StarStar: RandomNumberGenerator, Sendable {
  private var s: (UInt64, UInt64, UInt64, UInt64)

  init(seed: UInt64) {
    var x = seed
    func splitMix() -> UInt64 {
      x &+= 0x9e37_79b9_7f4a_7c15
      var z = x
      z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
      z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
      return z ^ (z >> 31)
    }
    s = (splitMix(), splitMix(), splitMix(), splitMix())
  }

  mutating func next() -> UInt64 {
    let result = ((s.1 &* 5) << 7 | (s.1 &* 5) >> 57) &* 9
    let t = s.1 << 17
    s.2 ^= s.0
    s.3 ^= s.1
    s.1 ^= s.2
    s.0 ^= s.3
    s.2 ^= t
    s.3 = (s.3 << 45) | (s.3 >> 19)
    return result
  }
}
