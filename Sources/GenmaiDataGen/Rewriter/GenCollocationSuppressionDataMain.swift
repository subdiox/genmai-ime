// Port of mozc/src/rewriter/gen_collocation_suppression_data_main.cc (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenCollocationSuppressionDataMain {
  /// Data set sections produced by this generator (keys: dataset_writer_main names).
  /// mozc_data.bzl passes no --error_rate, so the flag default 0.00001 is used.
  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    ["cols": try convert(ctx.sources.collocationSuppression, errorRate: 0.00001)]
  }

  /// `Convert()` with --binary_mode.
  public static func convert(_ suppressionData: String, errorRate: Double) throws -> [UInt8] {
    let kSeparator = "\t"
    var entries: [String] = []
    if suppressionData.isEmpty {
      let kDummyStr = "__NO_DATA__"
      entries.append(kDummyStr + kSeparator + kDummyStr)
    } else {
      for line in CodeGenUtil.getlines(try FileUtil.getContentBytes(suppressionData)) where !line.isEmpty {
        // absl::StrSplit(line, "\t", absl::SkipEmpty())
        let fields = line.split(separator: "\t", omittingEmptySubsequences: true)
        guard fields.count >= 2 else { throw DataGenError.invalidInput("collocation suppression: \(line)") }
        entries.append(fields[0] + kSeparator + fields[1])
      }
    }
    return GenExistenceData.outputExistenceBinary(entries, errorRate)
  }
}
