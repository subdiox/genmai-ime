// Port of mozc/src/converter/quality_regression_main.cc (3.35.6354).
//
// The C++ binary (built with Bazel as //converter:quality_regression_main)
// generates data/dictionary_oss/evaluation.tsv together with
// converter/quality_regression.py. It lives in Engine/ here because it needs
// the engine (converter/ cannot depend on engine/ in the Swift module layout
// rules either way; this keeps converter/ free of engine code).
//
// Deviations from C++:
// - The absl flags and main() are replaced by `run(...)` (the caller sets up
//   the temporary user profile, like main() does with TempDirectory).
// - Output goes to a String instead of std::ostream.

import Foundation
import GenmaiBase
import GenmaiProtocol

public enum QualityRegressionMain {
  /// Runs `items` through `engine` and returns the result lines
  /// ("OK:\t" / "FAILED:\t" + key, actual value, command [+ rank], expected
  /// value) in the format of quality_regression_main.
  public static func run(
    _ engine: Engine, _ engineType: String, _ items: [QualityRegressionUtil.TestItem]
  ) throws -> String {
    let util = QualityRegressionUtil(engine.getConverter())
    if engineType == "mobile" {
      var request = Genmai_Commands_Request()
      RequestTestUtil.fillMobileRequest(&request)
      util.setRequest(request)
    }
    var out = ""
    for item in items {
      var actualValue = ""
      let result = try util.convertAndTest(item, &actualValue)
      out += result ? "OK:\t" : "FAILED:\t"
      out += "\(item.key)\t\(actualValue)\t\(item.command)"
      if item.expectedRank != 0 {
        out += " \(item.expectedRank)"
      }
      out += "\t\(item.expectedValue)\t\n"
    }
    return out
  }

  /// main(): creates the eval engine from `dataFile` / `dataType` in a
  /// temporary user profile and runs the items of `testFiles`.
  public static func main(
    testFiles: [String], dataFile: String, dataType: String, engineType: String = "desktop"
  ) throws -> String {
    try SystemUtil.withTempUserProfile { _ in
      let engine = try createEvalEngine(dataFile, dataType)
      var items: [QualityRegressionUtil.TestItem] = []
      try QualityRegressionUtil.parseFiles(testFiles, &items)
      return try run(engine, engineType, items)
    }
  }
}
