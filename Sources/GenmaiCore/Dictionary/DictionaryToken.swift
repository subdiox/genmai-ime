// Port of mozc/src/dictionary/dictionary_token.h (3.35.6354).

/// `mozc::dictionary::Token`: one dictionary entry.
public struct Token: Sendable, Hashable {
  public typealias AttributesBitfield = UInt8

  /// `Token::Attribute`. Attributes are combined as a bit field
  /// (`AttributesBitfield`), so they are plain constants rather than an enum.
  public enum Attribute {
    public static let none: AttributesBitfield = 0
    public static let spellingCorrection: AttributesBitfield = 1
    public static let labelSize: AttributesBitfield = 2
    // * CAUTION *
    // If you are going to add new attributes, make sure that they have larger
    // values than LABEL_SIZE!! The attributes having less values than it are
    // tightly integrated with the system dictionary codec.

    // The following attribute is not stored in the system dictionary but is
    // added by dictionary modules when looking up from user dictionary.
    public static let suffixDictionary: AttributesBitfield = 1 << 6
    public static let userDictionary: AttributesBitfield = 1 << 7
  }

  public var key: String = ""
  public var value: String = ""
  public var cost: Int = 0
  public var lid: UInt16 = 0
  public var rid: UInt16 = 0
  public var attributes: AttributesBitfield = Attribute.none

  public init() {}

  public init(key: String, value: String) {
    self.key = key
    self.value = value
  }

  public init(
    key: String, value: String, cost: Int, lid: UInt16, rid: UInt16,
    attributes: AttributesBitfield
  ) {
    self.key = key
    self.value = value
    self.cost = cost
    self.lid = lid
    self.rid = rid
    self.attributes = attributes
  }
}
