// Port of mozc/src/rewriter/gen_existence_data.{h,cc} (3.35.6354).
// Only the binary output (OutputExistenceBinary) is ported; the C++ header
// output is not used by the data set build.

import Foundation
import GenmaiBase
import GenmaiStorage

public enum GenExistenceData {
  /// `GenExistenceData(entries, error_rate)`.  `errorRate` is a double flag
  /// value converted to float by MinFilterSizeInBytesForErrorRate's parameter.
  public static func genExistenceData(_ entries: [String], _ errorRate: Double) -> [UInt8] {
    let n = entries.count
    let m = ExistenceFilterBuilder.minFilterSizeInBytesForErrorRate(Float(errorRate), n)
    GenmaiLog.info("entry: \(n) err: \(errorRate) bytes: \(m)")

    var builder = ExistenceFilterBuilder.createOptimal(m, UInt32(n))
    for entry in entries {
      builder.insert(entry)
    }
    return builder.serializeAsString()
  }

  /// `OutputExistenceBinary`.
  public static func outputExistenceBinary(_ entries: [String], _ errorRate: Double) -> [UInt8] {
    genExistenceData(entries, errorRate)
  }
}
