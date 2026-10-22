// Port of mozc/src/base/hash.{h,cc} (3.35.6354).
//
// Also contains a port of CityHash64 / CityHash64WithSeed(s) from Abseil's
// absl/hash/internal/city.cc, which Mozc's CityFingerprint uses. All functions
// here must be bit-exact with the C++ implementation because fingerprints are
// persisted (user history keys, etc.).
//
// Note: Mozc is built with -funsigned-char, so bytes are treated as unsigned
// in the legacy fingerprint.

// MARK: - Public API (base/hash.h)

// New fingerprint functions based on CityHash.
// https://github.com/google/cityhash
// Currently, it uses absl::hash_internal. Since internal implementation may be
// updated or deleted in the future, we have compatibility checks in the unit
// tests.

/// CityHash64 of the UTF-8 bytes of `str`.
@inlinable
public func cityFingerprint(_ str: some StringProtocol) -> UInt64 {
  var s = String(str)
  return s.withUTF8 { CityHash.cityHash64($0) }
}

/// CityHash64 of raw bytes.
public func cityFingerprint(bytes: UnsafeRawBufferPointer) -> UInt64 {
  CityHash.cityHash64(
    UnsafeBufferPointer(
      start: bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), count: bytes.count))
}

/// CityHash64WithSeed of the UTF-8 bytes of `str`.
@inlinable
public func cityFingerprintWithSeed(_ str: some StringProtocol, _ seed: UInt64) -> UInt64 {
  var s = String(str)
  return s.withUTF8 { CityHash.cityHash64WithSeed($0, seed) }
}

// Legacy Fingerprint Functions
// These are about 5-7 times slower than CityFingerprint.
// Do not use legacy Fingerprint in new code.

private let kFingerPrint32Seed: UInt32 = 0xfd12_deff
private let kFingerPrintSeed0: UInt32 = 0x6d6f
private let kFingerPrintSeed1: UInt32 = 0x7a63

/// Calculates 64-bit fingerprint.
public func legacyFingerprint(_ str: some StringProtocol) -> UInt64 {
  legacyFingerprintWithSeed(str, kFingerPrintSeed0)
}

/// Calculates 64-bit fingerprint with seed.
public func legacyFingerprintWithSeed(_ str: some StringProtocol, _ seed: UInt32) -> UInt64 {
  var s = String(str)
  return s.withUTF8 { buf in
    let hi = legacyFingerprint32WithSeed(buf, seed)
    let lo = legacyFingerprint32WithSeed(buf, kFingerPrintSeed1)
    var result = UInt64(hi) << 32 | UInt64(lo)
    if hi == 0 && lo < 2 {
      result ^= 0x130f_9bef_94a0_a928
    }
    return result
  }
}

/// Calculates 32-bit fingerprint.
public func legacyFingerprint32(_ str: some StringProtocol) -> UInt32 {
  var s = String(str)
  return s.withUTF8 { legacyFingerprint32WithSeed($0, kFingerPrint32Seed) }
}

// MARK: - Legacy implementation

@inline(__always)
private func toUInt32(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> UInt32 {
  UInt32(a) &+ (UInt32(b) << 8) &+ (UInt32(c) << 16) &+ (UInt32(d) << 24)
}

@inline(__always)
private func mix(_ a: inout UInt32, _ b: inout UInt32, _ c: inout UInt32) {
  a &-= b
  a &-= c
  a ^= (c >> 13)
  b &-= c
  b &-= a
  b ^= (a << 8)
  c &-= a
  c &-= b
  c ^= (b >> 13)
  a &-= b
  a &-= c
  a ^= (c >> 12)
  b &-= c
  b &-= a
  b ^= (a << 16)
  c &-= a
  c &-= b
  c ^= (b >> 5)
  a &-= b
  a &-= c
  a ^= (c >> 3)
  b &-= c
  b &-= a
  b ^= (a << 10)
  c &-= a
  c &-= b
  c ^= (b >> 15)
}

private func legacyFingerprint32WithSeed(_ str: UnsafeBufferPointer<UInt8>, _ seed: UInt32) -> UInt32 {
  let strLen = UInt32(truncatingIfNeeded: str.count)
  var a: UInt32 = 0x9e37_79b9
  var b: UInt32 = a
  var c: UInt32 = seed
  var p = 0
  var rest = str.count

  while rest >= 12 {
    a &+= toUInt32(str[p], str[p + 1], str[p + 2], str[p + 3])
    b &+= toUInt32(str[p + 4], str[p + 5], str[p + 6], str[p + 7])
    c &+= toUInt32(str[p + 8], str[p + 9], str[p + 10], str[p + 11])
    mix(&a, &b, &c)
    p += 12
    rest -= 12
  }

  c &+= strLen
  // Emulates the fallthrough switch of the C++ code.
  if rest >= 11 { c &+= UInt32(str[p + 10]) << 24 }
  if rest >= 10 { c &+= UInt32(str[p + 9]) << 16 }
  if rest >= 9 { c &+= UInt32(str[p + 8]) << 8 }
  if rest >= 8 { b &+= UInt32(str[p + 7]) << 24 }
  if rest >= 7 { b &+= UInt32(str[p + 6]) << 16 }
  if rest >= 6 { b &+= UInt32(str[p + 5]) << 8 }
  if rest >= 5 { b &+= UInt32(str[p + 4]) }
  if rest >= 4 { a &+= UInt32(str[p + 3]) << 24 }
  if rest >= 3 { a &+= UInt32(str[p + 2]) << 16 }
  if rest >= 2 { a &+= UInt32(str[p + 1]) << 8 }
  if rest >= 1 { a &+= UInt32(str[p]) }
  mix(&a, &b, &c)

  return c
}

// MARK: - CityHash64 (port of absl/hash/internal/city.cc)

public enum CityHash {
  private static let k0: UInt64 = 0xc3a5_c85c_97cb_3127
  private static let k1: UInt64 = 0xb492_b66f_be98_f273
  private static let k2: UInt64 = 0x9ae1_6a3b_2f90_404f

  @inline(__always)
  private static func fetch64(_ s: UnsafePointer<UInt8>, _ i: Int) -> UInt64 {
    UInt64(littleEndian: UnsafeRawPointer(s + i).loadUnaligned(as: UInt64.self))
  }

  @inline(__always)
  private static func fetch32(_ s: UnsafePointer<UInt8>, _ i: Int) -> UInt64 {
    UInt64(UInt32(littleEndian: UnsafeRawPointer(s + i).loadUnaligned(as: UInt32.self)))
  }

  @inline(__always)
  private static func rotate(_ val: UInt64, _ shift: Int) -> UInt64 {
    // Avoid shifting by 64: doing so yields an undefined result.
    shift == 0 ? val : ((val >> UInt64(shift)) | (val << UInt64(64 - shift)))
  }

  @inline(__always)
  private static func shiftMix(_ val: UInt64) -> UInt64 { val ^ (val >> 47) }

  @inline(__always)
  private static func hashLen16(_ u: UInt64, _ v: UInt64, _ mul: UInt64) -> UInt64 {
    // Murmur-inspired hashing.
    var a = (u ^ v) &* mul
    a ^= (a >> 47)
    var b = (v ^ a) &* mul
    b ^= (b >> 47)
    b = b &* mul
    return b
  }

  @inline(__always)
  private static func hashLen16(_ u: UInt64, _ v: UInt64) -> UInt64 {
    let kMul: UInt64 = 0x9ddf_ea08_eb38_2d69
    return hashLen16(u, v, kMul)
  }

  private static func hashLen0to16(_ s: UnsafePointer<UInt8>, _ len: Int) -> UInt64 {
    let ulen = UInt64(len)
    if len >= 8 {
      let mul = k2 &+ ulen &* 2
      let a = fetch64(s, 0) &+ k2
      let b = fetch64(s, len - 8)
      let c = rotate(b, 37) &* mul &+ a
      let d = (rotate(a, 25) &+ b) &* mul
      return hashLen16(c, d, mul)
    }
    if len >= 4 {
      let mul = k2 &+ ulen &* 2
      let a = fetch32(s, 0)
      return hashLen16(ulen &+ (a << 3), fetch32(s, len - 4), mul)
    }
    if len > 0 {
      let a = s[0]
      let b = s[len >> 1]
      let c = s[len - 1]
      let y = UInt32(a) &+ (UInt32(b) << 8)
      let z = UInt32(truncatingIfNeeded: len) &+ (UInt32(c) << 2)
      return shiftMix(UInt64(y) &* k2 ^ UInt64(z) &* k0) &* k2
    }
    return k2
  }

  private static func hashLen17to32(_ s: UnsafePointer<UInt8>, _ len: Int) -> UInt64 {
    let mul = k2 &+ UInt64(len) &* 2
    let a = fetch64(s, 0) &* k1
    let b = fetch64(s, 8)
    let c = fetch64(s, len - 8) &* mul
    let d = fetch64(s, len - 16) &* k2
    return hashLen16(
      rotate(a &+ b, 43) &+ rotate(c, 30) &+ d,
      a &+ rotate(b &+ k2, 18) &+ c, mul)
  }

  @inline(__always)
  private static func weakHashLen32WithSeeds(
    _ w: UInt64, _ x: UInt64, _ y: UInt64, _ z: UInt64, _ a: UInt64, _ b: UInt64
  ) -> (UInt64, UInt64) {
    var a = a
    var b = b
    a &+= w
    b = rotate(b &+ a &+ z, 21)
    let c = a
    a &+= x
    a &+= y
    b &+= rotate(a, 44)
    return (a &+ z, b &+ c)
  }

  @inline(__always)
  private static func weakHashLen32WithSeeds(
    _ s: UnsafePointer<UInt8>, _ i: Int, _ a: UInt64, _ b: UInt64
  ) -> (UInt64, UInt64) {
    weakHashLen32WithSeeds(
      fetch64(s, i), fetch64(s, i + 8), fetch64(s, i + 16),
      fetch64(s, i + 24), a, b)
  }

  private static func hashLen33to64(_ s: UnsafePointer<UInt8>, _ len: Int) -> UInt64 {
    let mul = k2 &+ UInt64(len) &* 2
    var a = fetch64(s, 0) &* k2
    var b = fetch64(s, 8)
    let c = fetch64(s, len - 24)
    let d = fetch64(s, len - 32)
    let e = fetch64(s, 16) &* k2
    let f = fetch64(s, 24) &* 9
    let g = fetch64(s, len - 8)
    let h = fetch64(s, len - 16) &* mul
    let u = rotate(a &+ g, 43) &+ (rotate(b, 30) &+ c) &* 9
    let v = ((a &+ g) ^ d) &+ f &+ 1
    let w = ((u &+ v) &* mul).byteSwapped &+ h
    let x = rotate(e &+ f, 42) &+ c
    let y = (((v &+ w) &* mul).byteSwapped &+ g) &* mul
    let z = e &+ f &+ c
    a = ((x &+ z) &* mul &+ y).byteSwapped &+ b
    b = shiftMix((z &+ a) &* mul &+ d &+ h) &* mul
    return b &+ x
  }

  public static func cityHash64(_ buf: UnsafeBufferPointer<UInt8>) -> UInt64 {
    var len = buf.count
    guard let base = buf.baseAddress, len > 0 else { return k2 }
    if len <= 32 {
      if len <= 16 {
        return hashLen0to16(base, len)
      } else {
        return hashLen17to32(base, len)
      }
    } else if len <= 64 {
      return hashLen33to64(base, len)
    }

    // For strings over 64 bytes we hash the end first, and then as we
    // loop we keep 56 bytes of state: v, w, x, y, and z.
    let s = base
    var x = fetch64(s, len - 40)
    var y = fetch64(s, len - 16) &+ fetch64(s, len - 56)
    var z = hashLen16(fetch64(s, len - 48) &+ UInt64(len), fetch64(s, len - 24))
    var v = weakHashLen32WithSeeds(s, len - 64, UInt64(len), z)
    var w = weakHashLen32WithSeeds(s, len - 32, y &+ k1, x)
    x = x &* k1 &+ fetch64(s, 0)

    // Decrease len to the nearest multiple of 64, and operate on 64-byte chunks.
    len = (len - 1) & ~63
    var p = 0
    repeat {
      x = rotate(x &+ y &+ v.0 &+ fetch64(s, p + 8), 37) &* k1
      y = rotate(y &+ v.1 &+ fetch64(s, p + 48), 42) &* k1
      x ^= w.1
      y &+= v.0 &+ fetch64(s, p + 40)
      z = rotate(z &+ w.0, 33) &* k1
      v = weakHashLen32WithSeeds(s, p, v.1 &* k1, x &+ w.0)
      w = weakHashLen32WithSeeds(s, p + 32, z &+ w.1, y &+ fetch64(s, p + 16))
      swap(&z, &x)
      p += 64
      len -= 64
    } while len != 0
    return hashLen16(
      hashLen16(v.0, w.0) &+ shiftMix(y) &* k1 &+ z,
      hashLen16(v.1, w.1) &+ x)
  }

  public static func cityHash64WithSeed(_ buf: UnsafeBufferPointer<UInt8>, _ seed: UInt64) -> UInt64 {
    cityHash64WithSeeds(buf, k2, seed)
  }

  public static func cityHash64WithSeeds(
    _ buf: UnsafeBufferPointer<UInt8>, _ seed0: UInt64, _ seed1: UInt64
  ) -> UInt64 {
    hashLen16(cityHash64(buf) &- seed0, seed1)
  }
}
