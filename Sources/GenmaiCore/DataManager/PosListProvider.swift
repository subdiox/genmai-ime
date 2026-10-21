// Port of mozc/src/data_manager/pos_list_provider.{h,cc} (3.35.6354).

import GenmaiBase

/// Provides the list of user POS names (for the dictionary tool / word
/// register UI).
public struct PosListProvider: Sendable {
  private var posList: [String] = []
  private var posListDefaultIndex = 0

  public init() {
    guard let array = SerializedStringArray(bytes: PosListData.kPosArray) else {
      preconditionFailure("Embedded pos list is broken")
    }

    posList.reserveCapacity(array.size)
    for pos in array {
      if pos == "名詞" {
        posListDefaultIndex = posList.count
      }
      posList.append(pos)
    }
  }

  public func getPosList() -> [String] {
    posList
  }

  public func getPosListDefaultIndex() -> Int {
    posListDefaultIndex
  }
}
