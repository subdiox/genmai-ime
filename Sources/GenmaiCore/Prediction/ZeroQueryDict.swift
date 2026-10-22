// Port of mozc/src/prediction/zero_query_dict.h (3.35.6354).
//
// Deviations from C++:
// - `ZeroQueryType` is a Swift enum with the same raw values; unknown raw
//   values in the data map to `.none` via `ZeroQueryEntry.type`.
// - `absl::Span<const ZeroQueryEntry>` over the token array becomes an index
//   range (`Range<Int>`) plus `entry(at:)`, which decodes the 16-byte packed
//   entry with little-endian loads. `equal_range` compares keys bytewise.

import GenmaiBase

public enum ZeroQueryType: UInt16, Sendable {
  case none = 0  // "☁" (symbol, non-unicode 6.0 emoji), and rule based.
  case numberSuffix  // "階" from "2"
  case emoticon  // "(>ω<)" from "うれしい"
  case emoji  // <umbrella emoji> from "かさ"
  // Following types are defined for usage stats.
  // The candidates of these types will not be stored at |ZeroQueryList|.
  // - "ヒルズ" from "六本木"
  // These candidates will be generated from dictionary entries
  // such as "六本木ヒルズ".
  case bigram
  // - "に" from "六本木".
  // These candidates will be generated from suffix dictionary.
  case suffix
  // These candidates will be generated from supplemental model.
  case supplementalModel
}

/// `ZeroQueryEntry` (16 bytes, packed).
public struct ZeroQueryEntry: Sendable, Equatable {
  public static let byteSize = 16

  public var keyIndex: UInt32 = 0
  public var valueIndex: UInt32 = 0
  public var rawType: UInt16 = 0

  public var type: ZeroQueryType { ZeroQueryType(rawValue: rawType) ?? .none }

  public init(keyIndex: UInt32 = 0, valueIndex: UInt32 = 0, rawType: UInt16 = 0) {
    self.keyIndex = keyIndex
    self.valueIndex = valueIndex
    self.rawType = rawType
  }
}

/// An immutable view of the data set.
public struct ZeroQueryDict: Sendable {
  private var tokenArray = DataView()
  private var stringArray = SerializedStringArray()

  public init() {}

  public init(_ tokenArrayData: DataView, _ stringArrayData: DataView) {
    initialize(tokenArrayData, stringArrayData)
  }

  /// `Init`.
  public mutating func initialize(_ tokenArrayData: DataView, _ stringArrayData: DataView) {
    tokenArray = tokenArrayData
    stringArray.set(stringArrayData.bytes, owner: stringArrayData.owner)
  }

  public func key(_ entry: ZeroQueryEntry) -> String {
    stringArray[Int(entry.keyIndex)]
  }

  public func value(_ entry: ZeroQueryEntry) -> String {
    stringArray[Int(entry.valueIndex)]
  }

  /// The number of entries (`GetZeroQueryEntreis().size()`).
  public var entriesCount: Int { tokenArray.count / ZeroQueryEntry.byteSize }

  /// Returns the i-th entry of the token array.
  public func entry(at i: Int) -> ZeroQueryEntry {
    let offset = i * ZeroQueryEntry.byteSize
    return ZeroQueryEntry(
      keyIndex: tokenArray.load(fromByteOffset: offset, as: UInt32.self),
      valueIndex: tokenArray.load(fromByteOffset: offset + 4, as: UInt32.self),
      rawType: tokenArray.load(fromByteOffset: offset + 8, as: UInt16.self))
  }

  /// `GetZeroQueryEntreis()`.
  public func getZeroQueryEntries() -> [ZeroQueryEntry] {
    (0..<entriesCount).map { entry(at: $0) }
  }

  private func compareKey(_ i: Int, _ key: some StringProtocol) -> Int {
    stringArray.compare(at: Int(entry(at: i).keyIndex), with: key)
  }

  /// `equal_range(key)`: the index range of the entries whose key is `key`.
  public func equalRange(_ key: some StringProtocol) -> Range<Int> {
    // lower_bound
    var first = 0
    var count = entriesCount
    while count > 0 {
      let step = count / 2
      let it = first + step
      if compareKey(it, key) < 0 {
        first = it + 1
        count -= step + 1
      } else {
        count = step
      }
    }
    let lower = first
    // upper_bound
    count = entriesCount - lower
    while count > 0 {
      let step = count / 2
      let it = first + step
      if !(compareKey(it, key) > 0) {
        first = it + 1
        count -= step + 1
      } else {
        count = step
      }
    }
    return lower..<first
  }

  /// `equal_range(key)` as entries.
  public func equalRangeEntries(_ key: some StringProtocol) -> [ZeroQueryEntry] {
    equalRange(key).map { entry(at: $0) }
  }
}
