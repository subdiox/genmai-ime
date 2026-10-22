// Port of mozc/src/dictionary/pos_group.h (3.35.6354).

/// `mozc::dictionary::PosGroup`: manages pos grouping rule.
/// This holds a copy of the (small) array managed by DataManager
/// (`DataManager.getPosGroupData()`); pass it by value.
public struct PosGroup: Sendable {
  private let lidGroup: [UInt8]

  public init(_ lidGroup: DataSpan<UInt8>) {
    self.lidGroup = lidGroup.array
  }

  /// Returns grouped pos id based on an array pre-generated from
  /// data/rules/user_segment_history_pos_group.def.
  @inline(__always)
  public func getPosGroup(_ lid: UInt16) -> UInt8 {
    lidGroup[Int(lid)]
  }
}
