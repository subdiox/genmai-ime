// Port of mozc/src/converter/inner_segment.h (3.35.6354).

/// Data structure for storing segment boundary information.
/// Clients should not depend on the internal data structure but
/// need to use this alias as the underlying encoding schema will be updated.
///
/// Each element packs (key_len, value_len, content_key_len, content_value_len)
/// in bytes as 8-bit fields, `key_len` in the lowest byte (the layout of the
/// C++ `internal::LengthData` bit field on little-endian targets). The encoding
/// is persisted by user history, so it must stay bit exact.
public typealias InnerSegmentBoundary = [UInt32]

/// `internal::LengthData`.
public struct InnerSegmentLengthData: Sendable, Equatable {
  public var keyLen: UInt32
  public var valueLen: UInt32
  public var contentKeyLen: UInt32
  public var contentValueLen: UInt32
}

// TODO(taku): Deprecate EncodeLengths since they expose the internal
// implementations. Migrates to InnerSegmentBoundaryBuilder.
public func encodeLengths(
  _ keyLen: UInt32, _ valueLen: UInt32, _ contentKeyLen: UInt32, _ contentValueLen: UInt32
) -> UInt32? {
  func fixContentLen(_ len: UInt32, _ fullLen: UInt32) -> UInt32 {
    len == 0 || len > fullLen ? fullLen : len
  }

  // Workaround for the case when Candidate::content_(key|value) are invalid.
  let contentKeyLen = fixContentLen(contentKeyLen, keyLen)
  let contentValueLen = fixContentLen(contentValueLen, valueLen)

  if keyLen == 0 || valueLen == 0 || contentKeyLen == 0 || contentValueLen == 0
    || keyLen > UInt32(UInt8.max) || valueLen > UInt32(UInt8.max)
    || contentKeyLen > UInt32(UInt8.max) || contentValueLen > UInt32(UInt8.max)
  {
    return nil
  }
  return keyLen | (valueLen << 8) | (contentKeyLen << 16) | (contentValueLen << 24)
}

public func encodeLengths(_ keyLen: Int, _ valueLen: Int, _ contentKeyLen: Int, _ contentValueLen: Int)
  -> UInt32?
{
  // Negative or huge lengths are out of range of the 8-bit fields anyway.
  func clamp(_ v: Int) -> UInt32 { v < 0 ? UInt32.max : UInt32(truncatingIfNeeded: min(v, Int(UInt32.max))) }
  return encodeLengths(clamp(keyLen), clamp(valueLen), clamp(contentKeyLen), clamp(contentValueLen))
}

public func decodeLengths(_ encoded: UInt32) -> InnerSegmentLengthData {
  InnerSegmentLengthData(
    keyLen: encoded & 0xff, valueLen: (encoded >> 8) & 0xff,
    contentKeyLen: (encoded >> 16) & 0xff, contentValueLen: (encoded >> 24) & 0xff)
}

/// Iterator class to access inner segments.
/// Allows to access the inner segment via for-in loop.
///
///     for iter in result.innerSegments() {
///       print(iter.key, iter.value)
///     }
public struct InnerSegments: Sequence {
  /// `InnerSegments::IteratorData`: one inner segment. All strings are
  /// substrings of the candidate key/value (C++ `string_view`s).
  public struct Element {
    public let key: Substring
    public let value: Substring
    public let contentKey: Substring
    public let contentValue: Substring

    public var functionalKey: Substring { key[contentKey.endIndex...] }
    public var functionalValue: Substring { value[contentValue.endIndex...] }

    // C++-style accessors.
    public func getKey() -> Substring { key }
    public func getValue() -> Substring { value }
    public func getContentKey() -> Substring { contentKey }
    public func getContentValue() -> Substring { contentValue }
    public func getFunctionalKey() -> Substring { functionalKey }
    public func getFunctionalValue() -> Substring { functionalValue }
  }

  public struct Iterator: IteratorProtocol {
    fileprivate var key: Substring
    fileprivate var value: Substring
    fileprivate let encodedLengths: [UInt32]
    fileprivate var lengthIndex: Int

    public mutating func next() -> Element? {
      // The C++ end iterator is the one with empty key and value.
      if key.utf8.isEmpty && value.utf8.isEmpty {
        return nil
      }
      let keyBytes = key.utf8.count
      let valueBytes = value.utf8.count
      let empty = lengthIndex >= encodedLengths.count
      let data = empty ? nil : decodeLengths(encodedLengths[lengthIndex])
      // When `encoded_lengths` is not available, returns (key_|values_).size()
      // to consume all keys/values. This treatment supports empty
      // `encoded_lengths`.
      let keyLen = Swift.min(keyBytes, data.map { Int($0.keyLen) } ?? keyBytes)
      let valueLen = Swift.min(valueBytes, data.map { Int($0.valueLen) } ?? valueBytes)
      let contentKeyLen = Swift.min(keyBytes, data.map { Int($0.contentKeyLen) } ?? keyBytes)
      let contentValueLen = Swift.min(valueBytes, data.map { Int($0.contentValueLen) } ?? valueBytes)
      let element = Element(
        key: key.byteSubstring(from: 0, length: keyLen),
        value: value.byteSubstring(from: 0, length: valueLen),
        contentKey: key.byteSubstring(from: 0, length: contentKeyLen),
        contentValue: value.byteSubstring(from: 0, length: contentValueLen))
      // Next()
      key = key.byteSubstring(from: keyLen)
      value = value.byteSubstring(from: valueLen)
      if !empty { lengthIndex += 1 }
      return element
    }
  }

  private let key: Substring
  private let value: Substring
  private let encodedLengths: [UInt32]

  public func makeIterator() -> Iterator {
    Iterator(key: key, value: value, encodedLengths: encodedLengths, lengthIndex: 0)
  }

  /// size() returns the number of segments. Zero segment is only allowed when
  /// both key and value are empty. When inner segment boundary is not defined,
  /// the segment size is 1.
  public var size: Int {
    if key.utf8.isEmpty && value.utf8.isEmpty {
      return 0
    }
    return Swift.max(1, encodedLengths.count)
  }

  /// Returns the content key and content value after merging the segments.
  /// Simply removing the functional key and value of last segment.
  /// This method is used to treat the multi-segments as single-segment.
  public func getMergedContentKeyAndValue() -> (key: Substring, value: Substring) {
    var lastFunctionalKeyLen = 0
    var lastFunctionalValueLen = 0
    for iter in self {  // Remember the last functional key/value.
      lastFunctionalKeyLen = iter.functionalKey.utf8.count
      lastFunctionalValueLen = iter.functionalValue.utf8.count
    }
    return (
      key.byteSubstring(from: 0, length: key.utf8.count - lastFunctionalKeyLen),
      value.byteSubstring(from: 0, length: value.utf8.count - lastFunctionalValueLen)
    )
  }

  /// Returns the concatenated prefix key and value of segments size `size`, used
  /// in history result. When size is -1, returns all key/value.
  public func getPrefixKeyAndValue(_ size: Int = -1) -> (key: Substring, value: Substring) {
    if size < 0 { return (key, value) }
    var size = size
    let keySize = key.utf8.count
    let valueSize = value.utf8.count
    var keyLen = 0
    var valueLen = 0
    for iter in self {
      let done = size == 0
      size -= 1
      if done || keyLen >= keySize || valueLen >= valueSize {
        return (key.byteSubstring(from: 0, length: keyLen), value.byteSubstring(from: 0, length: valueLen))
      }
      keyLen += iter.key.utf8.count
      valueLen += iter.value.utf8.count
    }
    return (key, value)
  }

  /// Returns the concatenated suffix key and value of segments size `size`, used
  /// in history result. When size is -1, returns all key/value.
  public func getSuffixKeyAndValue(_ size: Int = -1) -> (key: Substring, value: Substring) {
    if size == 0 {
      // Returns last empty string so to allow pointer diff.
      return (key[key.endIndex...], value[value.endIndex...])
    }
    var index = self.size - size - 1
    if size < 0 || index < 0 {
      return (key, value)
    }
    var k = key
    var v = value
    for iter in self {
      k = k.byteSubstring(from: iter.key.utf8.count)
      v = v.byteSubstring(from: iter.value.utf8.count)
      let hit = index == 0
      index -= 1
      if hit { return (k, v) }
    }
    return (k, v)
  }

  /// Constructor for the structure only with key/value.
  public init(key: some StringProtocol, value: some StringProtocol, innerSegmentBoundary: [UInt32]) {
    self.key = Substring(key)
    self.value = Substring(value)
    self.encodedLengths =
      Self.isValidInnerSegmentBoundary(self.key, self.value, innerSegmentBoundary)
      ? innerSegmentBoundary : []
  }

  /// Constructor for the structure with content_key/value.
  /// When inner_segment_boundary is empty or inconsistent with key/value,
  /// generates the placeholder inner_segment_boundary from content_key/value.
  public init(
    key: some StringProtocol, value: some StringProtocol, contentKey: some StringProtocol,
    contentValue: some StringProtocol, innerSegmentBoundary: [UInt32]
  ) {
    self.key = Substring(key)
    self.value = Substring(value)
    self.encodedLengths = Self.fixInnerSegmentBoundary(
      self.key, self.value, contentKey.utf8.count, contentValue.utf8.count, innerSegmentBoundary)
  }

  /// `AbslStringify`: "<k,v,ck,cv>" for each segment.
  public var description: String {
    var s = ""
    for iter in self {
      s +=
        "<\(iter.key.utf8.count),\(iter.value.utf8.count),\(iter.contentKey.utf8.count),\(iter.contentValue.utf8.count)>"
    }
    return s
  }

  private static func isValidUtf8Boundary(_ str: Substring, _ offset: Int) -> Bool {
    let size = str.utf8.count
    return offset <= size && (offset == size || (str.byte(at: offset) & 0xc0) != 0x80)
  }

  private static func isValidInnerSegmentBoundary(
    _ key: Substring, _ value: Substring, _ innerSegmentBoundary: [UInt32]
  ) -> Bool {
    if innerSegmentBoundary.isEmpty {
      return false
    }
    var keyOffset = 0
    var valueOffset = 0
    for encoded in innerSegmentBoundary {
      let data = decodeLengths(encoded)
      if data.keyLen == 0 || data.valueLen == 0 || data.contentKeyLen == 0 || data.contentValueLen == 0
        || data.contentKeyLen > data.keyLen || data.contentValueLen > data.valueLen
      {
        return false
      }
      if !isValidUtf8Boundary(key, keyOffset + Int(data.contentKeyLen))
        || !isValidUtf8Boundary(key, keyOffset + Int(data.keyLen))
        || !isValidUtf8Boundary(value, valueOffset + Int(data.contentValueLen))
        || !isValidUtf8Boundary(value, valueOffset + Int(data.valueLen))
      {
        return false
      }
      keyOffset += Int(data.keyLen)
      valueOffset += Int(data.valueLen)
    }
    return keyOffset == key.utf8.count && valueOffset == value.utf8.count
  }

  private static func fixInnerSegmentBoundary(
    _ key: Substring, _ value: Substring, _ contentKeySize: Int, _ contentValueSize: Int,
    _ innerSegmentBoundary: [UInt32]
  ) -> [UInt32] {
    if isValidInnerSegmentBoundary(key, value, innerSegmentBoundary) {
      return innerSegmentBoundary
    }
    let keySize = key.utf8.count
    let valueSize = value.utf8.count
    let contentKeyLen = isValidUtf8Boundary(key, contentKeySize) ? contentKeySize : keySize
    let contentValueLen = isValidUtf8Boundary(value, contentValueSize) ? contentValueSize : valueSize
    if let encoded = encodeLengths(keySize, valueSize, contentKeyLen, contentValueLen) {
      return [encoded]
    }
    return []
  }
}

/// Builder class for inner segment boundary.
///
/// Example:
///     var builder = InnerSegmentBoundaryBuilder()
///     for ... {
///       builder.add(2, 3, 1, 1)  // key/value/content_key/content_value len.
///     }
///     let boundary = builder.build("key", "value")
///
/// The last build() method checks whether the encoded lengths are consistent
/// with key/value. When inconsistent lengths are passed, return empty boundary
public struct InnerSegmentBoundaryBuilder {
  private var error = false
  private var boundary: InnerSegmentBoundary = []
  private var keyConsumed: UInt32 = 0
  private var valueConsumed: UInt32 = 0

  public init() {}

  @discardableResult
  public mutating func add(_ keyLen: Int, _ valueLen: Int, _ contentKeyLen: Int, _ contentValueLen: Int)
    -> InnerSegmentBoundaryBuilder
  {
    if error {
      return self
    }
    if let encoded = encodeLengths(keyLen, valueLen, contentKeyLen, contentValueLen) {
      keyConsumed &+= UInt32(keyLen)
      valueConsumed &+= UInt32(valueLen)
      boundary.append(encoded)
    } else {
      error = true
    }
    return self
  }

  @discardableResult
  public mutating func add(_ data: InnerSegments.Element) -> InnerSegmentBoundaryBuilder {
    add(
      data.key.utf8.count, data.value.utf8.count, data.contentKey.utf8.count,
      data.contentValue.utf8.count)
  }

  @discardableResult
  public mutating func addEncoded(_ encoded: UInt32) -> InnerSegmentBoundaryBuilder {
    let data = decodeLengths(encoded)
    keyConsumed &+= data.keyLen
    valueConsumed &+= data.valueLen
    boundary.append(encoded)
    return self
  }

  public mutating func build(_ key: some StringProtocol, _ value: some StringProtocol) -> InnerSegmentBoundary {
    if error || Int(keyConsumed) != key.utf8.count || Int(valueConsumed) != value.utf8.count {
      boundary.removeAll()
    }
    return boundary
  }
}

/// Utility function to accept fixed lengths array.
///
///     let boundary = buildInnerSegmentBoundary(
///                      [(2, 2, 1, 1), (3, 3, 2, 2)], "key", "value")
public func buildInnerSegmentBoundary(
  _ boundary: [(Int, Int, Int, Int)], _ key: some StringProtocol, _ value: some StringProtocol
) -> InnerSegmentBoundary {
  var builder = InnerSegmentBoundaryBuilder()
  for (keyLen, valueLen, contentKeyLen, contentValueLen) in boundary {
    builder.add(keyLen, valueLen, contentKeyLen, contentValueLen)
  }
  return builder.build(key, value)
}

/// Types whose values can be rewritten by `rewriteCandidateValues`
/// (`converter::Candidate` and `prediction::Result` in C++).
public protocol InnerSegmentValueRewritable {
  var key: String { get }
  var value: String { get set }
  var innerSegmentBoundary: InnerSegmentBoundary { get set }
  func innerSegments() -> InnerSegments
  /// True if the type has `content_value` (the C++ `requires` check).
  static var hasContentValue: Bool { get }
  /// `content_value`; ignored when `hasContentValue` is false.
  var rewritableContentValue: String { get set }
}

/// Rewrites `target.value` (and `target.content_value` if present) using `fn`,
/// and rebuilds `target.inner_segment_boundary` when populated so the encoded
/// byte lengths stay consistent with the rewritten values.
public func rewriteCandidateValues<T: InnerSegmentValueRewritable>(
  _ fn: (Substring) -> String, _ target: inout T
) {
  if target.innerSegmentBoundary.isEmpty {
    target.value = fn(Substring(target.value))
  } else {
    var newValue = ""
    var boundaryBuilder = InnerSegmentBoundaryBuilder()
    for iter in target.innerSegments() {
      let innerValue = fn(iter.value)
      let innerContentValue =
        iter.value.bytesEqual(iter.contentValue) ? innerValue : fn(iter.contentValue)
      newValue += innerValue
      boundaryBuilder.add(
        iter.key.utf8.count, innerValue.utf8.count, iter.contentKey.utf8.count,
        innerContentValue.utf8.count)
    }
    target.value = newValue
    target.innerSegmentBoundary = boundaryBuilder.build(target.key, target.value)
  }
  if T.hasContentValue {
    target.rewritableContentValue = fn(Substring(target.rewritableContentValue))
  }
}
