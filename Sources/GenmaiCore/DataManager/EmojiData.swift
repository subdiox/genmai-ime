// Port of mozc/src/data_manager/emoji_data.h (3.35.6354).

/// LINT.IfChange: same values as rewriter/gen_emoji_rewriter_data.py. The
/// cases keep the upstream names (E0_6, ...): the version numbers read better
/// with the underscore.
// swift-format-ignore: AlwaysUseLowerCamelCase
public enum EmojiVersion: UInt32, Sendable {
  case e0_6 = 0
  case e0_7
  case e1_0
  case e2_0
  case e3_0
  case e4_0
  case e5_0
  case e11_0
  case e12_0
  case e12_1
  case e13_0
  case e13_1
  case e14_0
  case e15_0
  case e15_1
  case e16_0
  case e17_0
  case e18_0

  public static let emojiMaxVersion = EmojiVersion.e18_0
}

/// Emoji data token is 28 bytes data of the following format:
///
///     +-------------------------------------+
///     | Key index (4 byte)                  |
///     +-------------------------------------+
///     | UTF8 emoji index (4 byte)           |
///     +-------------------------------------+
///     | Unicode Emoji version (4 byte)      |
///     +-------------------------------------+
///     | UTF8 description index (4 byte)     |
///     +-------------------------------------+
///     | Unused field (4 byte)               |
///     +-------------------------------------+
///     | Unused field (4 byte)               |
///     +-------------------------------------+
///     | Unused field (4 byte)               |
///     +-------------------------------------+
///
/// Here, index is the position in the string array at which the corresponding
/// string value is stored.  Tokens are sorted in order of key so that it can
/// be search by binary search.
public struct EmojiData: Sendable, Equatable {
  public static let byteSize = 28

  public var keyIndex: UInt32 = 0
  public var emojiIndex: UInt32 = 0
  /// The raw `EmojiVersion` value.
  public var unicodeVersionIndex: UInt32 = 0
  public var descriptionUtf8Index: UInt32 = 0
  public var unused: (UInt32, UInt32, UInt32) = (0, 0, 0)

  public init() {}

  /// Loads the token at byte offset `offset` of `view` (packed layout, little
  /// endian).
  public init(_ view: DataView, byteOffset offset: Int) {
    keyIndex = view.load(fromByteOffset: offset, as: UInt32.self)
    emojiIndex = view.load(fromByteOffset: offset + 4, as: UInt32.self)
    unicodeVersionIndex = view.load(fromByteOffset: offset + 8, as: UInt32.self)
    descriptionUtf8Index = view.load(fromByteOffset: offset + 12, as: UInt32.self)
    unused = (
      view.load(fromByteOffset: offset + 16, as: UInt32.self),
      view.load(fromByteOffset: offset + 20, as: UInt32.self),
      view.load(fromByteOffset: offset + 24, as: UInt32.self)
    )
  }

  public static func == (lhs: EmojiData, rhs: EmojiData) -> Bool {
    lhs.keyIndex == rhs.keyIndex && lhs.emojiIndex == rhs.emojiIndex
      && lhs.unicodeVersionIndex == rhs.unicodeVersionIndex
      && lhs.descriptionUtf8Index == rhs.descriptionUtf8Index && lhs.unused == rhs.unused
  }
}

/// The emoji token array viewed as `EmojiData` elements (C++
/// `MakeAlignedConstSpan<EmojiData>(token_array_data)`). Like the C++ span, it
/// is empty when the data size is not a multiple of 28 bytes.
public struct EmojiDataArray: RandomAccessCollection, Sendable {
  public typealias Index = Int
  public typealias Element = EmojiData

  public let data: DataView

  public init(_ tokenArrayData: DataView) {
    data = tokenArrayData.count % EmojiData.byteSize == 0 ? tokenArrayData : .empty
  }

  public var startIndex: Int { 0 }
  public var endIndex: Int { data.count / EmojiData.byteSize }

  public subscript(i: Int) -> EmojiData {
    EmojiData(data, byteOffset: i * EmojiData.byteSize)
  }
}
