// Port of mozc/src/converter/segmenter.{h,cc} (3.35.6354).

import GenmaiBase

/// `mozc::Segmenter`: segment boundary rules and boundary penalties.
///
/// Holds copies of the (small) tables of the data set for fast lookups.
public struct Segmenter: Sendable {
  private let lNumElements: Int
  private let rNumElements: Int
  private let lTable: [UInt16]
  private let rTable: [UInt16]
  private let bitarrayData: [UInt8]
  private let boundaryData: [UInt16]

  public init(
    _ lNumElements: Int, _ rNumElements: Int, _ lTable: DataSpan<UInt16>, _ rTable: DataSpan<UInt16>,
    _ bitarrayData: DataSpan<UInt8>, _ boundaryData: DataSpan<UInt16>
  ) {
    self.lNumElements = lNumElements
    self.rNumElements = rNumElements
    self.lTable = lTable.array
    self.rTable = rTable.array
    self.bitarrayData = bitarrayData.array
    self.boundaryData = boundaryData.array
    precondition(lNumElements * rNumElements <= bitarrayData.count * 8)
  }

  /// Creates a segmenter from `DataManager.getSegmenterData()` (what
  /// `engine::Modules` does in C++).
  public init(dataManager: DataManager) {
    let d = dataManager.getSegmenterData()
    self.init(d.lNumElements, d.rNumElements, d.lTable, d.rTable, d.bitarrayData, d.boundaryData)
  }

  public func isBoundary(_ lnode: Node, _ rnode: Node, _ isSingleSegment: Bool) -> Bool {
    if lnode.nodeType == .bosNode || rnode.nodeType == .eosNode {
      return true
    }

    // Always return false in prediction mode.
    // This implies that converter always returns single-segment-result
    // in prediction mode.
    if isSingleSegment {
      return false
    }

    // Concatenate particle and content word into one segment,
    // if lnode locates at the beginning of user input.
    // This hack is for handling ambiguous bunsetsu segmentation.
    // e.g. "かみ|にかく" => "紙|に書く" or "紙二角".
    // If we segment "に書く" into two segments, "二角" is never be shown.
    // There exits some implicit assumpution that user expects that their input
    // becomes one bunsetu. So, it would be better to keep "二角" even after "紙".
    if lnode.attributes & Node.Attribute.startsWithParticle != 0 {
      return false
    }

    return isBoundary(lnode.rid, rnode.lid)
  }

  @inline(__always)
  public func isBoundary(_ rid: UInt16, _ lid: UInt16) -> Bool {
    let bitarrayIndex = Int(lTable[Int(rid)]) + lNumElements * Int(rTable[Int(lid)])
    return (bitarrayData[bitarrayIndex >> 3] >> UInt8(bitarrayIndex & 0x7)) & 1 != 0
  }

  public func getPrefixPenalty(_ lid: UInt16) -> Int32 {
    Int32(boundaryData[2 * Int(lid)])
  }

  public func getSuffixPenalty(_ rid: UInt16) -> Int32 {
    Int32(boundaryData[2 * Int(rid) + 1])
  }
}
