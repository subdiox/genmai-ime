// Port of mozc/src/prediction/gen_zero_query_util.py (3.35.6354).
//
// Generate binary data for zero query suggestion.  For output format, see
// zero_query_dict.h.

import Foundation
import GenmaiBase

public enum GenZeroQueryUtil {
  static let zeroQueryTypeNone = 0
  static let zeroQueryTypeNumberSuffix = 1
  static let zeroQueryTypeEmoticon = 2
  static let zeroQueryTypeEmoji = 3

  struct ZeroQueryEntry {
    let entryType: Int
    let value: String
  }

  /// `collections.defaultdict(list)`: keys in insertion order.
  typealias ZeroQueryDict = PyOrderedDict<BStr, [ZeroQueryEntry]>

  static func writeZeroQueryData(_ dict: ZeroQueryDict) -> (tokens: [UInt8], strings: [UInt8]) {
    // Collect all the strings and assign index in ascending order
    var all = Set<BStr>()
    for (key, entryList) in dict.items {
      all.insert(key)
      for entry in entryList { all.insert(BStr(entry.value)) }
    }
    let sortedStrings = all.sorted()
    var stringIndex: [BStr: Int] = [:]
    for (i, s) in sortedStrings.enumerated() { stringIndex[s] = i }

    var f: [UInt8] = []
    for key in dict.keys.sorted() {
      for entry in dict[key]! {
        Py.packU32(stringIndex[key]!, into: &f)
        Py.packU32(stringIndex[BStr(entry.value)]!, into: &f)
        Py.packU16(entry.entryType, into: &f)
        Py.packU16(0, into: &f)  // Set 0 for unused field.
        Py.packU32(0, into: &f)  // Set 0 for unused field.
      }
    }
    return (f, SerializedStringArray.serializeToBuffer(sortedStrings.map(\.s)))
  }
}
