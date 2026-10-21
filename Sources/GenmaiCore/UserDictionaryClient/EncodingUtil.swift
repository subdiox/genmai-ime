// Port of mozc/src/gui/base/encoding_util.{h,cc} (3.35.6354).
//
// The dictionary tool reads Shift_JIS files with this converter (it does not
// use QTextCodec). Mozc's own table (sjis_to_ucs2_table.h) is used instead of
// Foundation's Shift_JIS / CP932 decoders, whose mappings differ for some
// characters (e.g. 0x815F, 0x8160, the NEC/IBM extensions).

import GenmaiBase

public enum EncodingUtil {
  // Each character of SJIS is encoded in one or two bytes.
  //
  // For first byte, there are 4 valid ranges (closed intervals):
  //   * FirstByteRange1: [0x00, 0x80]
  //   * FirstByteRange2: [0x81, 0x9F]
  //   * FirstByteRange3: [0xA1, 0xDF]
  //   * FirstByteRange4: [0xE0, 0xFF]
  // Ranges 2 and 4 are for two bytes encoding, so one more byte is needed to
  // decode a character.
  //
  // For second byte, there are 2 valid ranges (closed intervals):
  //   * SecondByteRange1: [0x40, 0x7E]
  //   * SecondByteRange2: [0x80, 0xFF]
  // Two byte characters are decoded using the conversion table defined in
  // sjis_to_ucs2_table.h.
  private static func isInFirstByteRange1(_ byte: UInt8) -> Bool { byte <= 0x80 }

  private static func isInFirstByteRange2(_ byte: UInt8) -> Bool {
    0x81 <= byte && byte <= 0x9F
  }

  private static func isInFirstByteRange3(_ byte: UInt8) -> Bool {
    0xA1 <= byte && byte <= 0xDF
  }

  private static func isInFirstByteRange4(_ byte: UInt8) -> Bool { 0xE0 <= byte }

  private static func isInSecondByteRange1(_ byte: UInt8) -> Bool {
    0x40 <= byte && byte <= 0x7E
  }

  private static func isInSecondByteRange2(_ byte: UInt8) -> Bool { 0x80 <= byte }

  private static func computeIndex(_ first: UInt8, _ second: UInt8) -> Int {
    var firstIndex = 0
    if isInFirstByteRange2(first) {
      // first_index = "offset of first in FirstByteRange2".
      firstIndex = Int(first) - 0x81
    } else if isInFirstByteRange4(first) {
      // first_index = "offset of first in FirstByteRange4" +
      //               length(FirstByteRange2)
      firstIndex = (Int(first) - 0xE0) + (0x9F - 0x81 + 1)
    }

    var secondIndex = 0
    if isInSecondByteRange1(second) {
      // second_index = "offset of second in SecondByteRange1";
      secondIndex = Int(second) - 0x40
    } else if isInSecondByteRange2(second) {
      // second_index = "offset of second in SecondByteRange2" +
      //                length(SecondByteRange1)
      secondIndex = (Int(second) - 0x80) + (0x7E - 0x40 + 1)
    }

    // width = length(SecondByteRange1) + length(SecondByteRange2)
    let width = (0x7E - 0x40 + 1) + (0xFF - 0x80 + 1)
    return firstIndex * width + secondIndex
  }

  private static func sjisToUtf8Internal(_ input: some Collection<UInt8>, _ output: inout [UInt8])
    -> Bool
  {
    var expectFirstByte = true
    var firstByte: UInt8 = 0
    for byte in input {
      if expectFirstByte {
        if isInFirstByteRange1(byte) {
          Strings.strAppendChar32(&output, Char32(byte))
        } else if isInFirstByteRange3(byte) {
          Strings.strAppendChar32(&output, Char32(byte) + 0xFEC0)
        } else if isInFirstByteRange2(byte) || isInFirstByteRange4(byte) {
          firstByte = byte
          expectFirstByte = false
        } else {
          return false  // Invalid first byte.
        }
        continue
      }

      if !isInSecondByteRange1(byte) && !isInSecondByteRange2(byte) {
        return false
      }
      let index = computeIndex(firstByte, byte)
      // NOTE: C++ compares against sizeof(kSJISToUCS2Table) (= the size in
      // bytes, twice the element count), which can read past the table; the
      // Swift port bounds the index by the element count.
      if index >= kSJISToUCS2Table.count {
        return false
      }
      let ucs2 = kSJISToUCS2Table[index]
      if ucs2 == 0 {
        return false
      }
      Strings.strAppendChar32(&output, Char32(ucs2))
      expectFirstByte = true
    }
    return expectFirstByte
  }

  /// Converts a Shift_JIS byte sequence to UTF-8 bytes. Returns an empty
  /// array if the input is not valid Shift_JIS.
  public static func sjisToUtf8Bytes(_ input: some Collection<UInt8>) -> [UInt8] {
    var output: [UInt8] = []
    if !sjisToUtf8Internal(input, &output) {
      return []
    }
    return output
  }

  /// Converts a Shift_JIS byte sequence to a UTF-8 string. Returns an empty
  /// string if the input is not valid Shift_JIS.
  public static func sjisToUtf8(_ input: some Collection<UInt8>) -> String {
    String(decoding: sjisToUtf8Bytes(input), as: UTF8.self)
  }
}
