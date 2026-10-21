// Port of mozc/src/data_manager/serialized_dictionary.{h,cc} (3.35.6354).

import GenmaiBase

/// This class serializes Mozc's dictionary data and load it at runtime without
/// cost of deserialization.  Mozc's dictionary is analogous to
/// std::multimap<Key, Value>, where Key is a string (e.g., reading for symbols,
/// etc.), and Value is its associated data:
///
///     Value {
///       string value;  // Surface form
///       string description;
///       string additional_description;
///       uint16_t lid;
///       uint16_t rid;
///       int16_t cost;
///     }
///
/// * Prerequisite
/// Little endian is assumed.
///
/// * Creating serialized data
/// The binary data consists of two data, token array and string array.  Use
/// SerializedDictionary.compile() to create the images.
///
/// * Map access
/// At runtime, we can access map contents just by loading two binary images,
/// token array and string array, e.g., from files, onto memory blocks.
/// Accessors are designed to have similar interfaces to
/// std::multimap<string, Value>, so values can be looked up by equalRange(),
/// etc.  (Swift: the dictionary is a RandomAccessCollection of `Entry`, indexed
/// by token position; C++ iterators correspond to indices.)
///
/// * Binary format
///
/// ** String array
/// All the strings, such as keys and values, are serialized into one array
/// using SerializedStringArray.  In the map structure (see below), every string
/// is stored as an index to this array.
///
/// ** Token array
/// A key value pair of map entry is encoded as data block of fixed byte length:
///
///     Token layout (24 bytes)
///     +---------------------------------------+
///     | Key index  (4 bytes)                  |
///     + - - - - - - - - - - - - - - - - - - - +
///     | Value index (4 bytes)                 |
///     + - - - - - - - - - - - - - - - - - - - +
///     | Description index  (4 bytes)          |
///     + - - - - - - - - - - - - - - - - - - - +
///     | Additional description index (4 bytes)|
///     + - - - - - - - - - - - - - - - - - - - +
///     | LID (2 bytes)                         |
///     + - - - - - - - - - - - - - - - - - - - +
///     | RID (2 bytes)                         |
///     + - - - - - - - - - - - - - - - - - - - +
///     | Cost (2 bytes)                        |
///     + - - - - - - - - - - - - - - - - - - - +
///     | Padding = 0x0000 (2 bytes)            |
///     +---------------------------------------+
///
/// The map structure is serialized as a sorted array of tokens where tokens are
/// sorted first by key and then by cost, both in ascending order.  Thus, the
/// array has 24 * #tokens bytes.  Note that each token is properly aligned at 4
/// byte boundary by the insertion of padding.  String values of a token (key,
/// value, description, additional_description) can be retrieved from the
/// string array by index.
public struct SerializedDictionary: RandomAccessCollection, Sendable {
  public struct CompilerToken: Sendable {
    public var value: String
    public var description: String
    public var additionalDescription: String
    public var lid: UInt16
    public var rid: UInt16
    public var cost: Int16

    public init(
      value: String, description: String = "", additionalDescription: String = "", lid: UInt16,
      rid: UInt16, cost: Int16
    ) {
      self.value = value
      self.description = description
      self.additionalDescription = additionalDescription
      self.lid = lid
      self.rid = rid
      self.cost = cost
    }
  }

  public typealias TokenList = [CompilerToken]

  public static let kTokenByteLength = 24

  /// One token (what a C++ `SerializedDictionary::iterator` dereferences to).
  public struct Entry: Sendable {
    /// Byte offset of the token in the token array.
    @usableFromInline let tokenOffset: Int
    @usableFromInline let tokenArray: DataView
    public let stringArray: SerializedStringArray

    @inlinable
    init(tokenOffset: Int, tokenArray: DataView, stringArray: SerializedStringArray) {
      self.tokenOffset = tokenOffset
      self.tokenArray = tokenArray
      self.stringArray = stringArray
    }

    public var keyIndex: UInt32 { tokenArray.load(fromByteOffset: tokenOffset, as: UInt32.self) }
    public var key: String { stringArray[Int(keyIndex)] }
    /// The key bytes without decoding.
    public var keyBytes: UnsafeRawBufferPointer { stringArray.bytes(at: Int(keyIndex)) }

    public var valueIndex: UInt32 { tokenArray.load(fromByteOffset: tokenOffset + 4, as: UInt32.self) }
    public var value: String { stringArray[Int(valueIndex)] }

    public var descriptionIndex: UInt32 {
      tokenArray.load(fromByteOffset: tokenOffset + 8, as: UInt32.self)
    }
    public var description: String { stringArray[Int(descriptionIndex)] }

    public var additionalDescriptionIndex: UInt32 {
      tokenArray.load(fromByteOffset: tokenOffset + 12, as: UInt32.self)
    }
    public var additionalDescription: String { stringArray[Int(additionalDescriptionIndex)] }

    public var lid: UInt16 { tokenArray.load(fromByteOffset: tokenOffset + 16, as: UInt16.self) }
    public var rid: UInt16 { tokenArray.load(fromByteOffset: tokenOffset + 18, as: UInt16.self) }
    public var cost: Int16 { tokenArray.load(fromByteOffset: tokenOffset + 20, as: Int16.self) }
  }

  public typealias Index = Int
  public typealias Element = Entry

  private let tokenArray: DataView
  public let stringArray: SerializedStringArray

  /// The token array and string array data (4-byte alignment is not required
  /// in the Swift port; loads are unaligned).
  public init(tokenArray: DataView, stringArrayData: DataView) {
    assert(SerializedDictionary.verifyData(tokenArray, stringArrayData))
    self.tokenArray = tokenArray
    var sa = SerializedStringArray()
    sa.set(stringArrayData)
    stringArray = sa
  }

  /// Convenience for the `[token_array, string_array]` pairs returned by
  /// DataManager.
  public init(_ data: (tokenArray: DataView, stringArray: DataView)) {
    self.init(tokenArray: data.tokenArray, stringArrayData: data.stringArray)
  }

  public var size: Int { tokenArray.count / SerializedDictionary.kTokenByteLength }
  public var count: Int { size }
  public var startIndex: Int { 0 }
  public var endIndex: Int { size }

  public subscript(i: Int) -> Entry {
    Entry(
      tokenOffset: i * SerializedDictionary.kTokenByteLength, tokenArray: tokenArray,
      stringArray: stringArray)
  }

  /// Bytewise comparison of the key of the i-th token with `key`.
  @inline(__always)
  private func compareKey(at i: Int, _ key: some StringProtocol) -> Int {
    let keyIndex = tokenArray.load(
      fromByteOffset: i * SerializedDictionary.kTokenByteLength, as: UInt32.self)
    return stringArray.compare(at: Int(keyIndex), with: key)
  }

  /// std::lower_bound(begin(), end(), key): the first token whose key is not
  /// less than `key` (bytewise).
  public func lowerBound(_ key: some StringProtocol) -> Int {
    var first = 0
    var count = size
    while count > 0 {
      let step = count / 2
      let it = first + step
      if compareKey(at: it, key) < 0 {
        first = it + 1
        count -= step + 1
      } else {
        count = step
      }
    }
    return first
  }

  /// std::upper_bound(begin(), end(), key): the first token whose key is
  /// greater than `key` (bytewise).
  public func upperBound(_ key: some StringProtocol) -> Int {
    var first = 0
    var count = size
    while count > 0 {
      let step = count / 2
      let it = first + step
      if compareKey(at: it, key) <= 0 {
        first = it + 1
        count -= step + 1
      } else {
        count = step
      }
    }
    return first
  }

  /// Returns the range of indices whose keys match the given key.  The range
  /// is sorted in ascending order of cost.
  // TODO(noriyukit): Instead of comparing key as string, we can do binary
  // search using key index to minimize string comparison cost.
  public func equalRange(_ key: some StringProtocol) -> Range<Int> {
    lowerBound(key)..<upperBound(key)
  }

  // MARK: - Compilation

  /// Creates serialized data.  The first and second arrays of the returned
  /// value are the token array and string array, respectively.  The input
  /// stream should supply TSV file of Mozc's dictionary format; see, e.g.,
  /// data/symbol/symbol.tsv.
  public static func compile(_ input: InputFileStream) -> (tokenArray: [UInt8], stringArray: [UInt8]) {
    compile(loadTokens(input))
  }

  /// `dic` is a std::map<std::string, TokenList>: keys are iterated in
  /// bytewise order.  (Being a Swift Dictionary, canonically equivalent keys
  /// with different bytes would collide; this is a build-tool API.)
  public static func compile(_ dic: [String: TokenList]) -> (tokenArray: [UInt8], stringArray: [UInt8]) {
    let sortedKeys = dic.keys.sorted(by: Strings.byteLess)

    // Build a mapping from string to its index in a serialized string array.
    // Note that duplicate keys share the same index, so data is slightly
    // compressed.
    // (Strings are identified by their bytes, as in the C++ btree_map; Swift
    // String equality would merge canonically equivalent strings.)
    var allStrings = Set<[UInt8]>()
    for key in sortedKeys {
      allStrings.insert(Array(key.utf8))
      for token in dic[key]! {
        allStrings.insert(Array(token.value.utf8))
        allStrings.insert(Array(token.description.utf8))
        allStrings.insert(Array(token.additionalDescription.utf8))
      }
    }
    // This phase assigns index in ascending order of strings.
    let strings = allStrings.sorted { $0.lexicographicallyPrecedes($1) }
    var indexOf: [[UInt8]: UInt32] = [:]
    for (i, s) in strings.enumerated() {
      indexOf[s] = UInt32(i)
    }
    func stringIndex(_ s: String) -> UInt32 { indexOf[Array(s.utf8)]! }

    // Build a token array binary data.
    var buf: [UInt8] = []
    func put<T: FixedWidthInteger>(_ v: T) {
      withUnsafeBytes(of: v.littleEndian) { buf.append(contentsOf: $0) }
    }
    for key in sortedKeys {
      let keyIndex = stringIndex(key)
      for token in dic[key]! {
        put(keyIndex)
        put(stringIndex(token.value))
        put(stringIndex(token.description))
        put(stringIndex(token.additionalDescription))
        put(token.lid)
        put(token.rid)
        put(UInt16(bitPattern: token.cost))
        put(UInt16(0))
      }
    }

    // Build a string array.
    return (buf, SerializedStringArray.serializeToBuffer(strings.map { String(decoding: $0, as: UTF8.self) }))
  }

  /// Creates serialized data and writes them to files.
  public static func compileToFiles(
    _ input: String, _ outputTokenArray: String, _ outputStringArray: String
  ) throws {
    let ifs = InputFileStream(input)
    precondition(ifs.good, "Cannot open \(input)")
    try compileToFiles(loadTokens(ifs), outputTokenArray, outputStringArray)
  }

  public static func compileToFiles(
    _ dic: [String: TokenList], _ outputTokenArray: String, _ outputStringArray: String
  ) throws {
    let data = compile(dic)
    precondition(verifyData(DataView(copying: data.tokenArray), DataView(copying: data.stringArray)))
    try FileUtil.setContents(outputTokenArray, data.tokenArray)
    try FileUtil.setContents(outputStringArray, data.stringArray)
  }

  /// Validates the serialized data.
  public static func verifyData(_ tokenArrayData: DataView, _ stringArrayData: DataView) -> Bool {
    if tokenArrayData.count % kTokenByteLength != 0 {
      return false
    }
    var stringArray = SerializedStringArray()
    if !stringArray.initialize(stringArrayData) {
      return false
    }
    let n = UInt32(stringArray.size)
    var offset = 0
    while offset != tokenArrayData.count {
      if tokenArrayData.load(fromByteOffset: offset, as: UInt32.self) >= n
        || tokenArrayData.load(fromByteOffset: offset + 4, as: UInt32.self) >= n
        || tokenArrayData.load(fromByteOffset: offset + 8, as: UInt32.self) >= n
        || tokenArrayData.load(fromByteOffset: offset + 12, as: UInt32.self) >= n
      {
        return false
      }
      offset += kTokenByteLength
    }
    return true
  }

  private static func loadTokens(_ ifs: InputFileStream) -> [String: TokenList] {
    var dic: [String: TokenList] = [:]
    while let line = ifs.getline() {
      let fields = line.utf8.split(separator: UInt8(ascii: "\t"), omittingEmptySubsequences: true).map {
        String(decoding: $0, as: UTF8.self)
      }
      precondition(fields.count >= 4)
      let key = fields[0]
      guard let lid = NumberUtil.safeStrToUInt16(fields[1]),
        let rid = NumberUtil.safeStrToUInt16(fields[2]),
        let cost = NumberUtil.safeStrToInt16(fields[3])
      else {
        preconditionFailure("Invalid line: \(line)")
      }
      let token = CompilerToken(
        value: fields[4],
        description: fields.count > 5 ? fields[5] : "",
        additionalDescription: fields.count > 6 ? fields[6] : "",
        lid: lid, rid: rid, cost: cost)
      dic[key, default: []].append(token)
    }

    // Compare by cost.  (std::sort is not stable; the Swift sort is, which is
    // what libc++'s std::sort yields for the short per-key lists in practice.)
    for key in dic.keys {
      dic[key]!.sort { $0.cost < $1.cost }
    }
    return dic
  }
}
