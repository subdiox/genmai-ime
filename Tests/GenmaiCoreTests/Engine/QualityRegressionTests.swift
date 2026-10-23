// Evaluation-set parity: the Mozc dictionary evaluation
// (data/dictionary_oss/evaluation.tsv, generated in C++ by
// //data/dictionary_oss:evaluation = quality_regression_main over
// data/test/quality_regression_test/{oss,regression}.tsv with the OSS data set,
// desktop engine) run through the Swift port of quality_regression_main.
//
// - desktop: every one of the 680 cases must give the same status (OK: /
//   FAILED:), input, actual output, command and argument as evaluation.tsv
//   (which equals the output of the 3.35.6354 C++ binary, checked when the
//   fixture was made).
// - mobile: same comparison against the C++ output with --engine_type=mobile
//   (Tests/Fixtures/quality_regression/evaluation_mobile_oracle.tsv).
// - myoji.tsv (50,612 prediction cases, ~2 min in C++ release, much longer in a
//   debug Swift build): only when MOZC_QUALITY_REGRESSION_MYOJI=1, against
//   myoji_desktop_oracle.tsv.gz.
// - QualityRegressionTest (port of quality_regression_test_lib) over the same
//   680 cases: every FAILED case is reported (accuracy 1.0 by default).
//
// Regenerate the oracle fixtures with
//   bazel build //converter:quality_regression_main --config oss_macos
//   bazel-bin/converter/quality_regression_main --test_files=<tsv,...> \
//     --data_file=Data/genmai.data --data_type=oss --engine_type=<desktop|mobile>

import Foundation
import GenmaiBase
import Testing

@testable import GenmaiCore

private enum QualityRegressionPaths {
  static let fixtureDir: String = {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<4 { url.deleteLastPathComponent() }
    return url.appendingPathComponent("Tests/Fixtures/quality_regression").path
  }()

  static let testFiles = [
    DataManagerTestSupport.sourcePath("data", "test", "quality_regression_test", "oss.tsv"),
    DataManagerTestSupport.sourcePath("data", "test", "quality_regression_test", "regression.tsv"),
  ]
  static let myoji = DataManagerTestSupport.sourcePath(
    "data", "test", "quality_regression_test", "myoji.tsv")
  static let evaluation = DataManagerTestSupport.sourcePath(
    "data", "dictionary_oss", "evaluation.tsv")
}

/// Rows of a quality_regression_main output / evaluation.tsv: the first five
/// fields (status, input, output, command, argument), '#' lines skipped.
private func rows(_ text: String) -> [[String]] {
  text.split(separator: "\n", omittingEmptySubsequences: true)
    .filter { !$0.hasPrefix("#") }
    .map { line in
      Array(
        line.split(separator: "\t", omittingEmptySubsequences: false).prefix(5).map(String.init))
    }
}

private func compare(_ swift: [[String]], _ oracle: [[String]]) -> (matched: Int, diffs: [String]) {
  var matched = 0
  var diffs: [String] = []
  for (i, (a, b)) in zip(swift, oracle).enumerated() {
    if a == b {
      matched += 1
    } else if diffs.count < 20 {
      diffs.append("#\(i + 1)\n  swift:  \(a.joined(separator: "\t"))\n  oracle: \(b.joined(separator: "\t"))")
    }
  }
  return (matched, diffs)
}

private func runSwift(_ files: [String], _ engineType: String) throws -> String {
  try CharacterFormManager.withScopedManagerForTesting {
    try QualityRegressionMain.main(
      testFiles: files, dataFile: DataManagerTestSupport.ossDataPath, dataType: "oss",
      engineType: engineType)
  }
}

@Suite(
  .serialized,
  .enabled(if: DataManagerTestSupport.hasOssData, "genmai.data is missing; run Tools/build_oracle.sh"))
struct QualityRegressionTests {
  @Test func evaluationTsvDesktopParity() throws {
    let swift = rows(try runSwift(QualityRegressionPaths.testFiles, "desktop"))
    let oracle = rows(try String(contentsOfFile: QualityRegressionPaths.evaluation, encoding: .utf8))
    #expect(oracle.count == 680)
    #expect(swift.count == oracle.count)
    let (matched, diffs) = compare(swift, oracle)
    #expect(matched == oracle.count, "\(matched)/\(oracle.count)\n\(diffs.joined(separator: "\n"))")
    #expect(swift.filter { $0[0] == "OK:" }.count == oracle.filter { $0[0] == "OK:" }.count)
  }

  @Test func evaluationMobileParity() throws {
    let swift = rows(try runSwift(QualityRegressionPaths.testFiles, "mobile"))
    let oracle = rows(
      try String(
        contentsOfFile: QualityRegressionPaths.fixtureDir + "/evaluation_mobile_oracle.tsv",
        encoding: .utf8))
    #expect(swift.count == oracle.count)
    let (matched, diffs) = compare(swift, oracle)
    #expect(matched == oracle.count, "\(matched)/\(oracle.count)\n\(diffs.joined(separator: "\n"))")
  }

  @Test(
    .enabled(
      if: ProcessInfo.processInfo.environment["MOZC_QUALITY_REGRESSION_MYOJI"] == "1",
      "set MOZC_QUALITY_REGRESSION_MYOJI=1 to run the 50k-case myoji.tsv evaluation"))
  func myojiDesktopParity() throws {
    let gunzip = Foundation.Process()
    gunzip.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
    gunzip.arguments = ["-dc", QualityRegressionPaths.fixtureDir + "/myoji_desktop_oracle.tsv.gz"]
    let pipe = Pipe()
    gunzip.standardOutput = pipe
    try gunzip.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    gunzip.waitUntilExit()
    let oracle = rows(String(decoding: data, as: UTF8.self))
    let swift = rows(try runSwift([QualityRegressionPaths.myoji], "desktop"))
    #expect(swift.count == oracle.count)
    let (matched, diffs) = compare(swift, oracle)
    #expect(matched == oracle.count, "\(matched)/\(oracle.count)\n\(diffs.joined(separator: "\n"))")
  }

  @Test func runTestForPlatformReportsFailedCases() throws {
    let testData = try QualityRegressionTest.loadTestData(QualityRegressionPaths.testFiles)
    #expect(testData.count == 680)
    let report = try SystemUtil.withTempUserProfile { _ in
      try CharacterFormManager.withScopedManagerForTesting {
        let engine = try createEvalEngine(DataManagerTestSupport.ossDataPath, "oss")
        let util = QualityRegressionUtil(engine.getConverter())
        return try QualityRegressionTest.runTestForPlatform(
          QualityRegressionUtil.Platform.desktop, util, testData)
      }
    }
    let oracle = rows(try String(contentsOfFile: QualityRegressionPaths.evaluation, encoding: .utf8))
    #expect(report.numExecutedCases == 680)
    #expect(report.numDisabledCases == 0)
    #expect(report.numSkippedCases == 0)
    #expect(report.failures.count == oracle.filter { $0[0] == "FAILED:" }.count)
    #expect(report.logs.last == "Tested 680 / 680 entries.")
  }

  @Test func runTestForPlatformNullUtil() {
    #expect(throws: StatusError.self) {
      _ = try QualityRegressionTest.runTestForPlatform(QualityRegressionUtil.Platform.desktop, nil, [])
    }
  }

  @Test func loadTestDataDisabledPrefix() throws {
    let dir = try TempDirectory.default().createTempDirectory()
    defer { withExtendedLifetime(dir) {} }
    let path = FileUtil.joinPath(dir.path, "t.tsv")
    try Data("# comment\nDISABLED_l\tあ\t亜\tConversion Expected\r\n\nl\tい\t胃\tConversion Expected\n".utf8)
      .write(to: URL(fileURLWithPath: path))
    let data = try QualityRegressionTest.loadTestData([path])
    #expect(data.count == 2)
    #expect(!data[0].enabled)
    #expect(data[0].line == "l\tあ\t亜\tConversion Expected")
    #expect(data[1].enabled)
    #expect(data[1].line == "l\tい\t胃\tConversion Expected")
  }
}
