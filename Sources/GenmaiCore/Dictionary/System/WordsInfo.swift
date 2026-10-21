// Port of mozc/src/dictionary/system/words_info.h (3.35.6354).
//
// Container for words info to build system dictionary.
//
// Deviation: C++ `TokenInfo` holds a non-owning `Token*`. Here the token is
// stored by value (`token`); the decoder writes into it in place
// (`decodeToken(_:_:_:)` takes the TokenInfo `inout`), and `clear()` keeps the
// token so that TokenDecodeIterator can reuse the previous token's fields as
// the C++ code does through the shared `Token` instance.

/// Represents each token info.
public struct TokenInfo: Sendable {
  public enum PosType: Int, Sendable {
    case defaultPos = 0
    case frequentPos = 1
    case sameAsPrevPos = 2

    public static let posTypeSize = 3
  }

  public enum ValueType: Int, Sendable {
    case defaultValue = 0
    /// value is same as prev token's value
    case sameAsPrevValue = 1
    /// value is same as key
    case asIsHiragana = 2
    /// we can get the value by converting key to katakana form.
    case asIsKatakana = 3

    public static let valueTypeSize = 4
  }

  public enum CostType: Int, Sendable {
    case defaultCost = 0
    case canUseSmallEncoding = 1

    public static let costTypeSize = 2
  }

  public enum AccentEncodingType: Int, Sendable {
    case encodedInValue = 0
    case embeddedInToken = 1

    public static let accentEncodingTypeSize = 2
  }

  /// original token
  public var token: Token
  /// id of the value(=word) string in value trie
  public var idInValueTrie: Int = -1
  /// id of the pos map
  public var idInFrequentPosMap: Int = -1
  /// POS type for encoding
  public var posType: PosType = .defaultPos
  public var valueType: ValueType = .defaultValue
  public var costType: CostType = .defaultCost
  public var accentEncodingType: AccentEncodingType = .encodedInValue
  public var accentType: Int = -1

  public init(_ token: Token = Token()) {
    self.token = token
  }

  /// Resets every field except `token` (see the deviation note above).
  public mutating func clear() {
    idInValueTrie = -1
    idInFrequentPosMap = -1
    posType = .defaultPos
    valueType = .defaultValue
    costType = .defaultCost
    accentEncodingType = .encodedInValue
    accentType = -1
  }
}
