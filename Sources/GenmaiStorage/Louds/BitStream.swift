// Port of mozc/src/storage/louds/bit_stream.{h,cc} (3.35.6354).
//
// The image (std::string in C++) is a byte array.

/// Stream taking 'bits', especially designed for building a LOUDS trie.
public struct BitStream: Sendable {
  public private(set) var image: [UInt8] = []
  public private(set) var numBits = 0

  public init() {}

  public var byteSize: Int { image.count }

  public mutating func pushBit(_ bit: Int) {
    assert(bit == 0 || bit == 1)

    let shift = numBits % 8
    if shift == 0 {
      image.append(0)
    }
    image[image.count - 1] |= UInt8((bit & 1) << shift)
    numBits += 1
  }

  /// Fills the padding (0-bit) until the size is aligned to 32-bit boundary.
  public mutating func fillPadding32() {
    let remaining = image.count % 4
    if remaining != 0 {
      image.append(contentsOf: repeatElement(0, count: 4 - remaining))
    }
    numBits = image.count * 8
  }
}

/// Port of louds::internal::PushInt32: appends `value` as a little endian
/// 32-bit integer.
func pushInt32(_ value: Int, _ image: inout [UInt8]) {
  // Make sure the value is fit in the 32-bit value.
  precondition(value >= 0 && value <= Int(UInt32.max))

  // Output LSB to MSB.
  image.append(UInt8(truncatingIfNeeded: value))
  image.append(UInt8(truncatingIfNeeded: value >> 8))
  image.append(UInt8(truncatingIfNeeded: value >> 16))
  image.append(UInt8(truncatingIfNeeded: value >> 24))
}
