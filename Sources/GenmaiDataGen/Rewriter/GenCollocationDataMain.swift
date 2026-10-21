// Port of mozc/src/rewriter/gen_collocation_data_main.cc (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenCollocationDataMain {
  /// `_get_collocation_error_rate` of mozc_data.bzl: passed as
  /// `--error_rate=%f` ("0.000010" / "0.000001").
  static func errorRate(tag: String) -> Double {
    tag != "mock" ? 1e-5 : 1e-6
  }

  /// Data set sections produced by this generator (keys: dataset_writer_main names).
  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    ["coll": try convert(ctx.sources.collocation, errorRate: errorRate(tag: ctx.sources.tag))]
  }

  /// `Convert()` with --binary_mode.
  public static func convert(_ collocationData: String, errorRate: Double) throws -> [UInt8] {
    var entries: [String] = []
    for line in CodeGenUtil.getlines(try FileUtil.getContentBytes(collocationData)) where !line.isEmpty {
      entries.append(line)
    }
    return GenExistenceData.outputExistenceBinary(entries, errorRate)
  }
}
