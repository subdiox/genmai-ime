// Port of mozc/src/dictionary/system/codec.{h,cc} (3.35.6354).
//
// Named SystemDictionaryCodec.swift (not Codec.swift) to avoid a clash with the
// dictionary file codec inside the GenmaiCore target.
//
// Swift API notes:
// - Encoded keys / values are byte arrays (`[UInt8]`); they are not UTF-8
//   strings in general (encoded values never are). Decoders take any
//   contiguous byte buffer and return `String` (decoded keys are always valid
//   UTF-8; decoded values are repaired with U+FFFD only for ill-formed data).
//   Byte-returning variants (`decodeKeyBytes`, `decodeValueBytes`) exist for
//   tests that must round-trip ill-formed input (e.g. surrogates).
// - Character iteration follows `ConstChar32Iterator` / `Util::SplitFirstChar32`
//   (stops at the first ill-formed sequence) and is done on raw bytes.
// - Only the OSS (non GOOGLE_JAPANESE_INPUT_BUILD) branch exists.

import GenmaiBase

//// Constants for section name ////
private let kKeySectionName = "k"
private let kValueSectionName = "v"
private let kTokensSectionName = "t"
private let kPosSectionName = "p"

//// Constants for validation ////
// 12 bits
private let kPosMax = 0x0fff
// 15 bits
private let kCostMax = 0x7fff
// 22 bits
private let kValueTrieIdMax = 0x3fffff

//// Constants for value ////
// Unused for now.
// We are using from 0x00~0xfa for the Kanji, Hiragana and Katakana.
// Please see the comments for EncodeValue for details.
// const uint8_t kValueCharMarkReserved = 0xfb;
// ASCII character.
private let kValueCharMarkAscii: UInt8 = 0xfc
// UCS4 character 0x??00.
private let kValueCharMarkXX00: UInt8 = 0xfd
// This UCS4 character is neither Hiragana nor above 2 patterns 0x????
private let kValueCharMarkOtherUcs2: UInt8 = 0xfe

// UCS4 character 0x00?????? (beyond UCS2 range)
// UCS4 characters never exceed 10FFFF. (three 8bits, A-B-C).
// For left most 8bits A, we will use upper 2bits for the flag
// that indicating whether B and C is 0 or not.
private let kValueCharMarkCodepoint: UInt8 = 0xff
private let kValueCharMarkCodepointMiddle0: UInt8 = 0x80
private let kValueCharMarkCodepointRight0: UInt8 = 0x40
private let kValueCharMarkCodepointLeftMask: UInt8 = 0x1f

// character code related constants
private let kValueKanjiOffset = 0x01
private let kValueHiraganaOffset = 0x4b
private let kValueKatakanaOffset = 0x9f

//// Cost encoding flag ////
private let kSmallCostFlag: UInt8 = 0x80
private let kSmallCostMask: UInt8 = 0x7f

//// Flags for token ////
private let kTokenTerminationFlag: UInt8 = 0xff
// Note that the flag for the first token for a certain key cannot be 0xff.
// First token cannot be kSameAsPrevValueFlag(0x33) nor kSameAsPrevPosFlag(0x0c)

// 7 kLastTokenFlag
// 6  <id encoding>
// below bits will be used for upper 6 bits of token value
// when CRAM_VALUE_FLAG is set.
// 5    <reserved(unused)>
// 4     kSpellingCorrectionFlag
// 3      <pos encoding(high)>
// 2       <pos encoding(low)>
// 1        <value encoding(high)>
// 0         <value encoding(low)>

//// Value encoding flag ////
// There are 4 mutually exclusive cases
//  1) Same as index hiragana key
//  2) Value is katakana
//  3) Same as previous token
//  4) Others. We have to store the value
private let kValueTypeFlagMask: UInt8 = 0x03
// Same as index hiragana word
private let kAsIsHiraganaValueFlag: UInt8 = 0x01
// Same as index katakana word
private let kAsIsKatakanaValueFlag: UInt8 = 0x2
// has same word
private let kSameAsPrevValueFlag: UInt8 = 0x03
// other cases
private let kNormalValueFlag: UInt8 = 0x00

//// Pos encoding flag ////
// There are 4 mutually exclusive cases
//  1) Same pos with previous token
//  2) Not same, frequent 1 byte pos
//  3) Not same, full_pos but lid==rid, 2 byte
//  4) Not same, full_pos 4 byte (no flag for this)
private let kPosTypeFlagMask: UInt8 = 0x0c
// Pos(left/right ID) is coded into 3 bytes
// Note that lid/rid is less than 12 bits
// We need 24 bits (= 3 bytes) to store full pos.
private let kFullPosFlag: UInt8 = 0x04
// lid == rid 8 bits
private let kMonoPosFlag: UInt8 = 0x08
// has same left/right id as previous token
private let kSameAsPrevPosFlag: UInt8 = 0x0c
// frequent
private let kFrequentPosFlag: UInt8 = 0x00

//// Spelling Correction flag ////
private let kSpellingCorrectionFlag: UInt8 = 0x10

//// Reverved ////
// You can use one more flag!
// constexpr int kReservedFlag = 0x20;

//// Id encoding flag ////
// According to lower 6 bits of flags there are 2 patterns.
//  1) lower 6 bits are used.
//   - Store an id in a trie use 3 bytes
//  2) lower 6 bits are not used.
//   - Set CRAM_VALUE_FLAGS and use lower 6 bits.
//     We need another 2 bytes to store the id in the trie.
//     Note that we are assuming each id in the trie is less than 22 bits.
// Lower 6 bits of flags field are used to store upper part of id
// in value trie.
private let kCrammedIDFlag: UInt8 = 0x40
// Mask to cover upper valid 2bits when kCrammedIDFlag is used
private let kUpperFlagsMask: UInt8 = 0xc0
// Mask to get upper 6bits from flags value
private let kUpperCrammedIDMask: UInt8 = 0x3f

//// Last token flag ////
// This token is last token for a index word
private let kLastTokenFlag: UInt8 = 0x80

// MARK: - UTF-8 helpers (byte level)

/// `Util::SplitFirstChar32` on raw bytes: decodes the character at `i`.
/// Returns (codepoint, length) or nil for an ill-formed sequence / end.
@inline(__always)
private func splitFirstChar32(_ s: Span<UInt8>, _ i: Int) -> (UInt32, Int)? {
  let n = s.count - i
  if n <= 0 { return nil }
  let lead = s[i]
  if lead < 0x80 {
    return (UInt32(lead), 1)
  }
  if lead & 0xc0 == 0x80 {
    // UTF-8 sequence should not start trailing bytes.
    return nil
  }
  var result: UInt32
  let len: Int
  let minValue: UInt32
  let maxValue: UInt32
  if lead & 0xe0 == 0xc0 {
    len = 2
    minValue = 0x0080
    maxValue = 0x07ff
    result = UInt32(lead & 0x1f)
  } else if lead & 0xf0 == 0xe0 {
    len = 3
    minValue = 0x0800
    maxValue = 0xffff
    result = UInt32(lead & 0x0f)
  } else if lead & 0xf8 == 0xf0 {
    len = 4
    minValue = 0x010000
    maxValue = 0x1fffff
    result = UInt32(lead & 0x07)
    // Below is out of UCS4 but acceptable in 32-bit.
  } else if lead & 0xfc == 0xf8 {
    len = 5
    minValue = 0x0200000
    maxValue = 0x3ffffff
    result = UInt32(lead & 0x03)
  } else if lead & 0xfe == 0xfc {
    len = 6
    minValue = 0x4000000
    maxValue = 0x7fff_ffff
    result = UInt32(lead & 0x01)
  } else {
    // Currently 0xFE and 0xFF are treated as invalid.
    return nil
  }
  if n < len {
    // Data length is too short.
    return nil
  }
  for k in 1..<len {
    let c = s[i + k]
    if c & 0xc0 != 0x80 {
      // Trailing bytes not found.
      return nil
    }
    result = (result << 6) + UInt32(c & 0x3f)
  }
  if result < minValue || maxValue < result {
    // redundant UTF-8 sequence found.
    return nil
  }
  return (result, len)
}

/// `Util::CodepointToUtf8Append`: appends the UTF-8 bytes of `c` to `out`
/// (nothing for U+0000, as in C++).
@inline(__always)
private func appendUtf8(_ c: UInt32, _ out: inout [UInt8]) {
  if c == 0 {
    return
  }
  if c < 0x80 {
    out.append(UInt8(c))
    return
  }
  if c < 0x800 {
    out.append(UInt8(0xc0 | (c >> 6)))
    out.append(UInt8(0x80 | (c & 0x3f)))
    return
  }
  if c < 0x10000 {
    out.append(UInt8(0xe0 | (c >> 12)))
    out.append(UInt8(0x80 | ((c >> 6) & 0x3f)))
    out.append(UInt8(0x80 | (c & 0x3f)))
    return
  }
  if c < 0x200000 {
    out.append(UInt8(0xf0 | (c >> 18)))
    out.append(UInt8(0x80 | ((c >> 12) & 0x3f)))
    out.append(UInt8(0x80 | ((c >> 6) & 0x3f)))
    out.append(UInt8(0x80 | (c & 0x3f)))
    return
  }
  // Outside of the 21-bit range; never produced by the codec for valid data.
  out.append(contentsOf: Util.codepointToUtf8Bytes(c))
}

/// Runs `body` over the bytes of `src` (copied into a contiguous array).
@inline(__always)
private func withSpan<R>(_ src: some Collection<UInt8>, _ body: (Span<UInt8>) -> R) -> R {
  let array = ContiguousArray(src)
  return body(array.span)
}

/// Runs `body` over the bytes of `src` (no copy).
@inline(__always)
private func withSpan<R>(_ src: [UInt8], _ body: (Span<UInt8>) -> R) -> R {
  let slice = src[...]
  return body(slice.span)
}

/// Runs `body` over the bytes of `src` (no copy).
@inline(__always)
private func withSpan<R>(_ src: ArraySlice<UInt8>, _ body: (Span<UInt8>) -> R) -> R {
  body(src.span)
}

/// Runs `body` over the UTF-8 bytes of `s`.
@inline(__always)
private func withUTF8Span<R>(_ s: some StringProtocol, _ body: (Span<UInt8>) -> R) -> R {
  withSpan(s.utf8, body)
}

// MARK: - Key codec implementation

// Swap the area for Hiragana, prolonged sound mark and middle dot with
// the one for control codes and alphabets.
//
// U+3041 - U+305F ("ぁ" - "た") <=> U+0001 - U+001F
// U+3060 - U+3095 ("だ" - "ゕ") <=> U+0040 - U+0075
// U+30FB - U+30FC ("・" - "ー") <=> U+0076 - U+0077
//
// U+0020 - U+003F are left intact to represent numbers and hyphen in 1 byte.
@inline(__always)
private func encodeDecodeKeyChar(_ code: UInt32) -> UInt32 {
  var offset: UInt32 = 0
  if (code >= 0x0001 && code <= 0x001f) || (code >= 0x3041 && code <= 0x305f) {
    offset = 0x3041 - 0x0001
  } else if (code >= 0x0040 && code <= 0x0075) || (code >= 0x3060 && code <= 0x3095) {
    offset = 0x3060 - 0x0040
  } else if (code >= 0x0076 && code <= 0x0077) || (code >= 0x30FB && code <= 0x30FC) {
    offset = 0x30FB - 0x0076
  }
  if code < 0x80 {
    return code &+ offset
  } else {
    return code &- offset
  }
}

/// Appends the encoded/decoded key of `src` to `out`.
@inline(__always)
private func encodeDecodeKeyImpl(_ src: Span<UInt8>, _ out: inout [UInt8]) {
  var i = 0
  while let (code, len) = splitFirstChar32(src, i) {
    i += len
    appendUtf8(encodeDecodeKeyChar(code), &out)
  }
}

@inline(__always)
private func getEncodedDecodedKeyLengthImpl(_ src: Span<UInt8>) -> Int {
  var size = src.count
  var i = 0
  while let (code, len) = splitFirstChar32(src, i) {
    i += len
    if (code >= 0x3041 && code <= 0x3095) || (code >= 0x30FB && code <= 0x30FC) {
      // This code point takes three bytes in UTF-8 encoding,
      // and will be swapped with a code point which takes one byte in UTF-8
      // encoding.
      size -= 2
      continue
    }
    if (code >= 0x0001 && code <= 0x001F) || (code >= 0x0040 && code <= 0x0077) {
      // Vice versa on above.
      size += 2
      continue
    }
  }
  return size
}

/// Output capacity that is always enough for the key codec (every character
/// grows by at most 2 bytes; ill-formed tails are dropped).
@inline(__always)
private func keyCodecCapacity(_ n: Int) -> Int { n * 3 }

@inline(__always)
private func encodeDecodeKeyToBytes(_ src: Span<UInt8>) -> [UInt8] {
  var out: [UInt8] = []
  out.reserveCapacity(keyCodecCapacity(src.count))
  encodeDecodeKeyImpl(src, &out)
  return out
}

@inline(__always)
private func encodeDecodeKeyToString(_ src: Span<UInt8>) -> String {
  String(decoding: encodeDecodeKeyToBytes(src), as: UTF8.self)
}

// MARK: - Token encoding helpers

private func getFlagForPos(_ tokenInfo: TokenInfo) -> UInt8 {
  let token = tokenInfo.token
  let lid = Int(token.lid)
  let rid = Int(token.rid)
  if lid > kPosMax || rid > kPosMax {
    // We can use LOG(FATAL) here, as this code runs in dictionary_builder.
    fatalError("Too large pos id: lid \(lid), rid \(rid)")
  }

  if tokenInfo.posType == .frequentPos {
    return kFrequentPosFlag
  } else if tokenInfo.posType == .sameAsPrevPos {
    return kSameAsPrevPosFlag
  } else if lid == rid {
    return kMonoPosFlag
  } else {
    return kFullPosFlag
  }
}

private func getFlagForValue(_ tokenInfo: TokenInfo) -> UInt8 {
  switch tokenInfo.valueType {
  case .sameAsPrevValue: return kSameAsPrevValueFlag
  case .asIsHiragana: return kAsIsHiraganaValueFlag
  case .asIsKatakana: return kAsIsKatakanaValueFlag
  default: return kNormalValueFlag
  }
}

// Return flags for token
private func getFlagsForToken(_ tokens: [TokenInfo], _ index: Int) -> UInt8 {
  // Determines the flags for this token.
  var flags: UInt8 = 0
  if index == tokens.count - 1 {
    flags |= kLastTokenFlag
  }

  let tokenInfo = tokens[index]
  let token = tokenInfo.token

  // Special treatment for spelling correction.
  if token.attributes & Token.Attribute.spellingCorrection != 0 {
    flags |= kSpellingCorrectionFlag
  }

  // Pos flag
  flags |= getFlagForPos(tokenInfo)

  if index == 0 {
    precondition(
      flags & kPosTypeFlagMask != kSameAsPrevPosFlag,
      "First token cannot become the SameAsPrevPos.")
  }

  // Value flag
  flags |= getFlagForValue(tokenInfo)
  if index == 0 {
    precondition(
      flags & kValueTypeFlagMask != kSameAsPrevValueFlag,
      "First token cannot become the SameAsPrevValue.")
  }

  if flags & kUpperCrammedIDMask == 0 {
    // Lower 6bits are available. Use it for value trie id.
    flags |= kCrammedIDFlag
  }
  return flags
}

private func encodeCost(_ tokenInfo: TokenInfo, _ dst: inout [UInt8]) {
  let token = tokenInfo.token
  precondition(token.cost <= kCostMax, "Assuming cost is within 15bits.")
  if tokenInfo.costType == .canUseSmallEncoding {
    dst.append(UInt8(truncatingIfNeeded: token.cost >> 8) | kSmallCostFlag)
  } else {
    dst.append(UInt8(truncatingIfNeeded: token.cost >> 8))
    dst.append(UInt8(truncatingIfNeeded: token.cost & 0xff))
  }
}

private func encodePos(_ tokenInfo: TokenInfo, _ flags: UInt8, _ dst: inout [UInt8]) {
  let posFlag = flags & kPosTypeFlagMask
  let token = tokenInfo.token
  let lid = token.lid
  let rid = token.rid
  switch posFlag {
  case kFullPosFlag:
    // 3 bytes
    dst.append(UInt8(truncatingIfNeeded: lid & 255))
    dst.append(UInt8(truncatingIfNeeded: (rid << 4) & 255) | UInt8(truncatingIfNeeded: lid >> 8))
    dst.append(UInt8(truncatingIfNeeded: (rid >> 4) & 255))
  case kMonoPosFlag:
    // 2 bytes
    dst.append(UInt8(truncatingIfNeeded: lid & 255))
    dst.append(UInt8(truncatingIfNeeded: lid >> 8))
  case kFrequentPosFlag:
    // Frequent 1 byte pos.
    let id = tokenInfo.idInFrequentPosMap
    precondition(id >= 0)
    dst.append(UInt8(truncatingIfNeeded: id))
  case kSameAsPrevPosFlag:
    break
  default:
    // We can use LOG(FATAL) here. This code runs in dictionary_builder.
    fatalError("Should not come here")
  }
}

private func encodeValueInfo(_ tokenInfo: TokenInfo, _ flags: UInt8, _ dst: inout [UInt8]) {
  let valueTypeFlag = flags & kValueTypeFlagMask
  if valueTypeFlag != kNormalValueFlag {
    // No need to store id for word trie
    return
  }
  let id = UInt32(truncatingIfNeeded: tokenInfo.idInValueTrie)
  if id > kValueTrieIdMax {  // 22 bits
    // We can use LOG(FATAL) here.
    fatalError("Too large word trie (should be less than 2^22)\t\(id)")
  }

  if flags & kCrammedIDFlag != 0 {
    dst.append(UInt8(truncatingIfNeeded: id & 255))
    dst.append(UInt8(truncatingIfNeeded: (id >> 8) & 255))
    // Uses lower 6 bits of flags.
    dst[0] |= UInt8(truncatingIfNeeded: id >> 16) & kUpperCrammedIDMask
  } else {
    dst.append(UInt8(truncatingIfNeeded: id & 255))
    dst.append(UInt8(truncatingIfNeeded: (id >> 8) & 255))
    dst.append(UInt8(truncatingIfNeeded: (id >> 16) & 255))
  }
}

@inline(__always)
private func readFlags(_ val: UInt8) -> UInt8 {
  var ret = val
  if ret & kCrammedIDFlag != 0 {
    ret &= kUpperFlagsMask
  }
  return ret
}

@inline(__always)
private func decodeCost(_ ptr: Span<UInt8>, _ tokenInfo: inout TokenInfo, _ offset: inout Int) {
  if ptr[offset] & kSmallCostFlag != 0 {
    tokenInfo.token.cost = Int(ptr[offset] & kSmallCostMask) << 8
    offset += 1
  } else {
    tokenInfo.token.cost = (Int(ptr[offset]) << 8) + Int(ptr[offset + 1])
    offset += 2
  }
}

@inline(__always)
private func decodePos(
  _ ptr: Span<UInt8>, _ flags: UInt8, _ tokenInfo: inout TokenInfo, _ offset: inout Int
) {
  let posFlag = flags & kPosTypeFlagMask
  switch posFlag {
  case kFrequentPosFlag:
    let posId = Int(ptr[offset])
    tokenInfo.posType = .frequentPos
    tokenInfo.idInFrequentPosMap = posId
    offset += 1
  case kSameAsPrevPosFlag:
    tokenInfo.posType = .sameAsPrevPos
  case kMonoPosFlag:
    let id = (UInt16(ptr[offset + 1]) << 8) | UInt16(ptr[offset])
    tokenInfo.token.lid = id
    tokenInfo.token.rid = id
    offset += 2
  case kFullPosFlag:
    tokenInfo.token.lid = UInt16(ptr[offset]) + (UInt16(ptr[offset + 1] & 0x0f) << 8)
    tokenInfo.token.rid = UInt16(ptr[offset + 1] >> 4) + (UInt16(ptr[offset + 2]) << 4)
    offset += 3
  default:
    assertionFailure("should never come here")
  }
}

@inline(__always)
private func decodeValueInfo(
  _ ptr: Span<UInt8>, _ flags: UInt8, _ tokenInfo: inout TokenInfo, _ offset: inout Int
) {
  let valueFlag = flags & kValueTypeFlagMask
  switch valueFlag {
  case kAsIsHiraganaValueFlag:
    tokenInfo.valueType = .asIsHiragana
  case kAsIsKatakanaValueFlag:
    tokenInfo.valueType = .asIsKatakana
  case kSameAsPrevValueFlag:
    tokenInfo.valueType = .sameAsPrevValue
  default:  // kNormalValueFlag
    tokenInfo.valueType = .defaultValue
    var id = (Int(ptr[offset + 1]) << 8) | Int(ptr[offset])
    if flags & kCrammedIDFlag != 0 {
      id |= Int(ptr[0] & kUpperCrammedIDMask) << 16
      offset += 2
    } else {
      id |= Int(ptr[offset + 2]) << 16
      offset += 3
    }
    tokenInfo.idInValueTrie = id
  }
}

// Get value id only for reverse conversion
@inline(__always)
private func readValueInfo(_ ptr: Span<UInt8>, _ flags: UInt8, _ valueId: inout Int, _ offset: inout Int) {
  valueId = -1
  let valueFlag = flags & kValueTypeFlagMask
  if valueFlag == kNormalValueFlag {
    var id = (Int(ptr[offset + 1]) << 8) | Int(ptr[offset])
    if flags & kCrammedIDFlag != 0 {
      id |= Int(ptr[0] & kUpperCrammedIDMask) << 16
      offset += 2
    } else {
      id |= Int(ptr[offset + 2]) << 16
      offset += 3
    }
    valueId = id
  }
}

// MARK: - Value codec implementation

@inline(__always)
private func encodeValueImpl(_ src: Span<UInt8>, _ dst: inout [UInt8]) {
  @inline(__always) func push(_ b: Int) {
    dst.append(UInt8(truncatingIfNeeded: b))
  }
  var i = 0
  while let (cp, len) = splitFirstChar32(src, i) {
    i += len
    let c = Int(cp)
    if c >= 0x3041 && c < 0x3095 {
      // Hiragana(85 characters) are encoded into 1 byte.
      push(c - 0x3041 + kValueHiraganaOffset)
    } else if c >= 0x30a1 && c < 0x30fd {
      // Katakana (92 characters) are encoded into 1 byte.
      push(c - 0x30a1 + kValueKatakanaOffset)
    } else if c < 0x10000 && ((c >> 8) & 255) == 0 {
      // 0x00?? (ASCII) are encoded into 2 bytes.
      push(Int(kValueCharMarkAscii))
      push(c & 255)
    } else if c < 0x10000 && (c & 255) == 0 {
      // 0x??00 are encoded into 2 bytes.
      push(Int(kValueCharMarkXX00))
      push((c >> 8) & 255)
    } else if c >= 0x4e00 && c < 0x9800 {
      // Frequent Kanji and others (74*256 characters) are encoded
      // into 2 bytes.
      // (Kanji in 0x9800 to 0x9fff are encoded in 3 bytes)
      let h = ((c - 0x4e00) >> 8) + kValueKanjiOffset
      push(h)
      push(c & 255)
    } else if 0x10000 <= c && c <= 0x10ffff {
      // characters encoded into 2-4bytes.
      var left = (c >> 16) & 255
      let middle = (c >> 8) & 255
      let right = c & 255
      if middle == 0 {
        left |= Int(kValueCharMarkCodepointMiddle0)
      }
      if right == 0 {
        left |= Int(kValueCharMarkCodepointRight0)
      }
      push(Int(kValueCharMarkCodepoint))
      push(left)
      if middle != 0 {
        push(middle)
      }
      if right != 0 {
        push(right)
      }
    } else {
      // Other charaters encoded into 3bytes.
      push(Int(kValueCharMarkOtherUcs2))
      push((c >> 8) & 255)
      push(c & 255)
    }
  }
}

@inline(__always)
private func decodeValueImpl(_ src: Span<UInt8>, _ dst: inout [UInt8]) {
  var p = 0
  let end = src.count
  // Reads past the end yield 0 (C++ reads the terminator / adjacent memory of
  // a well-formed image; ill-formed input is not expected).
  @inline(__always) func at(_ k: Int) -> Int { k < end ? Int(src[k]) : 0 }
  while p < end {
    let cc = Int(src[p])
    var c = 0
    if kValueHiraganaOffset <= cc && cc < kValueKatakanaOffset {
      // Hiragana
      c = 0x3041 + cc - kValueHiraganaOffset
      p += 1
    } else if kValueKatakanaOffset <= cc && cc < Int(kValueCharMarkAscii) {
      // Katakana
      c = 0x30a1 + cc - kValueKatakanaOffset
      p += 1
    } else if cc == Int(kValueCharMarkAscii) {
      // Ascii
      c = at(p + 1)
      p += 2
    } else if cc == Int(kValueCharMarkXX00) {
      // xx00
      c = at(p + 1) << 8
      p += 2
    } else if cc == Int(kValueCharMarkCodepoint) {
      // UCS4
      let p1 = at(p + 1)
      c = (p1 & Int(kValueCharMarkCodepointLeftMask)) << 16
      var pos = 2
      if p1 & Int(kValueCharMarkCodepointMiddle0) == 0 {
        c += at(p + pos) << 8
        pos += 1
      }
      if p1 & Int(kValueCharMarkCodepointRight0) == 0 {
        c += at(p + pos)
        pos += 1
      }
      p += pos
    } else if cc == Int(kValueCharMarkOtherUcs2) {
      // other
      c = at(p + 1) << 8
      c += at(p + 2)
      p += 3
    } else if cc < kValueHiraganaOffset {
      // Frequent kanji
      c = ((cc - kValueKanjiOffset) << 8) + 0x4e00
      c += at(p + 1)
      p += 2
    } else {
      // "should never come here"
    }
    appendUtf8(UInt32(truncatingIfNeeded: c), &dst)
  }
}

/// Every encoded value byte decodes to at most 3 UTF-8 bytes, except the
/// 2-byte UCS4 form (2 -> 4 bytes).
@inline(__always)
private func decodeValueCapacity(_ n: Int) -> Int { n * 3 + 4 }

// MARK: - SystemDictionaryCodec

/// `mozc::dictionary::SystemDictionaryCodec`.
public struct SystemDictionaryCodec: Sendable {
  public init() {}

  /// Return section name for key trie
  public func getSectionNameForKey() -> String { kKeySectionName }

  /// Return section name for value trie
  public func getSectionNameForValue() -> String { kValueSectionName }

  /// Return section name for tokens array
  public func getSectionNameForTokens() -> String { kTokensSectionName }

  /// Return section name for frequent pos map
  public func getSectionNameForPos() -> String { kPosSectionName }

  // MARK: Key

  /// Compresses key string into small bytes.
  public func encodeKey(_ src: some StringProtocol) -> [UInt8] {
    withUTF8Span(src) { encodeDecodeKeyToBytes($0) }
  }

  /// Byte version of encodeKey.
  public func encodeKey(bytes src: some Collection<UInt8>) -> [UInt8] {
    withSpan(src) { encodeDecodeKeyToBytes($0) }
  }

  /// Byte version of encodeKey.
  public func encodeKey(bytes src: ArraySlice<UInt8>) -> [UInt8] {
    withSpan(src) { encodeDecodeKeyToBytes($0) }
  }

  /// Decompress key string.
  public func decodeKey(_ src: Span<UInt8>) -> String {
    encodeDecodeKeyToString(src)
  }

  public func decodeKey(_ src: [UInt8]) -> String {
    withSpan(src) { encodeDecodeKeyToString($0) }
  }

  public func decodeKey(_ src: ArraySlice<UInt8>) -> String {
    withSpan(src) { encodeDecodeKeyToString($0) }
  }

  public func decodeKey(_ src: some Collection<UInt8>) -> String {
    withSpan(src) { encodeDecodeKeyToString($0) }
  }

  /// Decompress key string into bytes.
  public func decodeKeyBytes(_ src: some Collection<UInt8>) -> [UInt8] {
    withSpan(src) { encodeDecodeKeyToBytes($0) }
  }

  /// Returns the length of encoded key string.
  public func getEncodedKeyLength(_ src: some StringProtocol) -> Int {
    withUTF8Span(src) { getEncodedDecodedKeyLengthImpl($0) }
  }

  public func getEncodedKeyLength(bytes src: some Collection<UInt8>) -> Int {
    withSpan(src) { getEncodedDecodedKeyLengthImpl($0) }
  }

  /// Returns the length of decoded key string.
  public func getDecodedKeyLength(_ src: Span<UInt8>) -> Int {
    getEncodedDecodedKeyLengthImpl(src)
  }

  public func getDecodedKeyLength(_ src: [UInt8]) -> Int {
    withSpan(src) { getEncodedDecodedKeyLengthImpl($0) }
  }

  public func getDecodedKeyLength(_ src: ArraySlice<UInt8>) -> Int {
    withSpan(src) { getEncodedDecodedKeyLengthImpl($0) }
  }

  public func getDecodedKeyLength(_ src: some Collection<UInt8>) -> Int {
    withSpan(src) { getEncodedDecodedKeyLengthImpl($0) }
  }

  // MARK: Value

  // This encodes each UCS4 character into following areas
  // The trickier part in this encoding is handling of \0 byte in UCS4
  // character. To avoid \0 in converted string, this function uses
  // VALUE_CHAR_MARK_* markers.
  //  Kanji in 0x4e00~0x97ff -> 0x01 0x00 ~ 0x4a 0xff (74*256 characters)
  //  Hiragana 0x3041~0x3095 -> 0x4b~0x9f (84 characters)
  //  Katakana 0x30a1~0x30fc -> 0x9f~0xfa (91 characters)
  //  0x?? (ASCII) -> VALUE_CHAR_MARK_ASCII ??
  //  0x??00 -> VALUE_CHAR_MARK_XX00 ??
  //  Other 0x?? ?? -> VALUE_CHAR_MARK_OTHER ?? ??
  //  0x?????? -> VALUE_CHAR_MARK_BIG ?? ?? ??

  /// Compresses value string into small bytes.
  public func encodeValue(_ src: some StringProtocol) -> [UInt8] {
    withUTF8Span(src) { encodeValueToBytes($0) }
  }

  /// Byte version of encodeValue.
  public func encodeValue(bytes src: some Collection<UInt8>) -> [UInt8] {
    withSpan(src) { encodeValueToBytes($0) }
  }

  /// Byte version of encodeValue.
  public func encodeValue(bytes src: ArraySlice<UInt8>) -> [UInt8] {
    withSpan(src) { encodeValueToBytes($0) }
  }

  private func encodeValueToBytes(_ src: Span<UInt8>) -> [UInt8] {
    // Each UTF-8 byte produces at most 2 output bytes (ASCII 1 -> 2).
    var out: [UInt8] = []
    out.reserveCapacity(src.count * 2)
    encodeValueImpl(src, &out)
    return out
  }

  /// Decompress value string.
  public func decodeValue(_ src: Span<UInt8>) -> String {
    String(decoding: decodeValueToBytes(src), as: UTF8.self)
  }

  public func decodeValue(_ src: [UInt8]) -> String {
    withSpan(src) { decodeValue($0) }
  }

  public func decodeValue(_ src: some Collection<UInt8>) -> String {
    withSpan(src) { decodeValue($0) }
  }

  /// Decompress value into bytes (no UTF-8 repair).
  public func decodeValueBytes(_ src: some Collection<UInt8>) -> [UInt8] {
    withSpan(src) { decodeValueToBytes($0) }
  }

  private func decodeValueToBytes(_ src: Span<UInt8>) -> [UInt8] {
    var out: [UInt8] = []
    out.reserveCapacity(decodeValueCapacity(src.count))
    decodeValueImpl(src, &out)
    return out
  }

  // MARK: Tokens

  public func getTokensTerminationFlag() -> UInt8 { kTokenTerminationFlag }

  /// Compress tokens.
  public func encodeTokens(_ tokens: [TokenInfo]) -> [UInt8] {
    var output: [UInt8] = []
    for i in 0..<tokens.count {
      output.append(contentsOf: encodeToken(tokens, i))
    }
    precondition(output.first != getTokensTerminationFlag())
    return output
  }

  // Each token is encoded as following.
  //
  // Flags: 1 byte
  // Cost:
  //  For words without homonyms, 1 byte
  //  Other words, 2 bytes
  // Pos:
  //  For pos same as the previous token, 0 byte
  //  For frequent pos, 1 byte
  //  For pos of left id == right id, 2 bytes
  //  For other pos-es left id + right id 3 bytes
  // Index: (less than 2^22)
  //  When kCrammedIDFlag is set, 2 bytes
  //  Othewise, 3 bytes
  private func encodeToken(_ tokens: [TokenInfo], _ index: Int) -> [UInt8] {
    precondition(index < tokens.count)

    // Determines the flags for this token.
    let flags = getFlagsForToken(tokens, index)

    // Encodes token into bytes.
    var buff: [UInt8] = []
    buff.reserveCapacity(9)
    buff.append(flags)

    let tokenInfo = tokens[index]
    encodePos(tokenInfo, flags, &buff)  // <= 3 bytes
    encodeCost(tokenInfo, &buff)  // <= 2 bytes
    encodeValueInfo(tokenInfo, flags, &buff)  // <= 3 bytes

    precondition(buff.count <= 9)
    return buff
  }

  /// Decompress the token at byte `start` of `bytes`. Returns false if the
  /// token is the last token for a certain key. Only the fields encoded in the
  /// token are written (see TokenDecodeIterator).
  @inline(__always)
  public func decodeToken(
    _ bytes: Span<UInt8>, at start: Int, _ tokenInfo: inout TokenInfo, _ readBytes: inout Int
  ) -> Bool {
    // A token is at most 9 bytes.
    let ptr = bytes.extracting(start..<Swift.min(start + 9, bytes.count))
    let flags = readFlags(ptr[0])
    if flags & kSpellingCorrectionFlag != 0 {
      tokenInfo.token.attributes = Token.Attribute.spellingCorrection
    }

    var offset = 1
    decodePos(ptr, flags, &tokenInfo, &offset)  // <= 3bytes
    decodeCost(ptr, &tokenInfo, &offset)  // <= 2bytes
    decodeValueInfo(ptr, flags, &tokenInfo, &offset)  // <= 3bytes
    assert(offset <= 9)
    readBytes = offset
    return flags & kLastTokenFlag == 0
  }

  /// Read a token for reverse lookup.
  /// If the token have value id, assign it to |value_id| otherwise assign -1.
  /// Return false if a token is the last token for a certain key.
  @inline(__always)
  public func readTokenForReverseLookup(
    _ bytes: Span<UInt8>, at start: Int, _ valueId: inout Int, _ readBytes: inout Int
  ) -> Bool {
    // A token is at most 9 bytes.
    let ptr = bytes.extracting(start..<Swift.min(start + 9, bytes.count))
    let flags = readFlags(ptr[0])
    var offset = 1
    // Read pos
    let posFlag = flags & kPosTypeFlagMask
    if posFlag == kFrequentPosFlag {
      offset += 1
    } else if posFlag == kMonoPosFlag {
      offset += 2
    } else if posFlag == kFullPosFlag {
      offset += 3
    }
    // Read cost
    if ptr[offset] & kSmallCostFlag != 0 {
      offset += 1
    } else {
      offset += 2
    }
    readValueInfo(ptr, flags, &valueId, &offset)
    readBytes = offset
    return flags & kLastTokenFlag == 0
  }
}
