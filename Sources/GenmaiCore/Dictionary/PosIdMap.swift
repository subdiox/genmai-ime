// Port of mozc/src/dictionary/pos_id_map.{h,cc} (3.35.6354).

/// `mozc::dictionary::PosIdMap`: manages POS ID to POS string mappings.
/// Typically initialized with the content of 'pos_id_map.data' packaged in
/// genmai.data (`DataManager.getPosIdMapData()`).
///
/// Binary format:
/// Null-separated UTF-8 strings. The N-th null-separated token corresponds to
/// POS ID N.
///
/// Deviation: the strings are decoded into Swift `String`s at construction
/// (C++ keeps `string_view`s into the buffer).
public final class PosIdMap: Sendable {
  // Maps POS ID to POS string.
  // The index is the POS ID.
  private let posIdToStringTable: [String]

  /// Initializes the map from serialized binary data.
  /// If the data is invalid or empty, it initializes an empty map.
  public init<C: Collection>(_ posIdMapData: C) where C.Element == UInt8 {
    if posIdMapData.isEmpty {
      posIdToStringTable = []
      return
    }
    // absl::StrSplit(data, '\0') keeps empty pieces (including a trailing one).
    posIdToStringTable = posIdMapData.split(separator: 0, omittingEmptySubsequences: false).map {
      String(decoding: $0, as: UTF8.self)
    }
  }

  public convenience init(_ posIdMapData: String) {
    self.init(Array(posIdMapData.utf8))
  }

  /// Returns the POS string corresponding to the given POS ID.
  /// Returns an empty string if the POS ID is invalid or not found.
  /// Example: 12 -> "副詞,一般,*,*,*,*,*"
  public func getPosString(_ posId: UInt16) -> String {
    if Int(posId) >= posIdToStringTable.count {
      return ""
    }
    return posIdToStringTable[Int(posId)]
  }

  /// Returns the total number of POS IDs.
  public func getPosIdCount() -> Int {
    posIdToStringTable.count
  }
}
