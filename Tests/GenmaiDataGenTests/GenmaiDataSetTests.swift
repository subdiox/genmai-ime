// Byte-identity tests of genmai-datagen against the Bazel-built data sets
// (Data/mock_genmai.data and Data/genmai.data, created by Tools/build_oracle.sh or
// copied from Vendor/mozc/src/bazel-bin).

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiDataGen
import Testing

enum DataGenTestPaths {
  static let repoRoot: String = {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<3 { url.deleteLastPathComponent() }
    return url.path
  }()
  static var srcRoot: String { repoRoot + "/Vendor/mozc/src" }
  static var mockData: String { repoRoot + "/Data/mock_genmai.data" }
  static var ossData: String { repoRoot + "/Data/genmai.data" }

  /// `@ja_usage_dict//:usage_dict.txt`: Data/external/ (Tools/build_data.sh downloads it), else the Bazel cache.
  static var usageDict: String? {
    firstExisting([
      repoRoot + "/Data/external/usage_dict.txt",
    ] + bazelExternal("+http_archive+ja_usage_dict/usage_dict.txt"))
  }
  static var zipCodeKenAll: String? {
    firstExisting([repoRoot + "/Data/external/KEN_ALL.CSV"] + bazelExternal("+http_archive+zip_code_ken_all/KEN_ALL.CSV"))
  }
  static var zipCodeJigyosyo: String? {
    firstExisting(
      [repoRoot + "/Data/external/JIGYOSYO.CSV"] + bazelExternal("+http_archive+zip_code_jigyosyo/JIGYOSYO.CSV"))
  }

  static func bazelExternal(_ rel: String) -> [String] {
    // Vendor/mozc/src/bazel-src -> <output_base>/execroot/_main
    let link = srcRoot + "/bazel-src"
    guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: link) else { return [] }
    let outputBase = ((dest as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
    return [outputBase + "/external/" + rel]
  }

  static func firstExisting(_ paths: [String]) -> String? {
    paths.first { FileManager.default.fileExists(atPath: $0) }
  }
}

@Suite("GenmaiDataSet")
struct GenmaiDataSetTests {
  static var mockAvailable: Bool {
    FileManager.default.fileExists(atPath: DataGenTestPaths.mockData) && DataGenTestPaths.usageDict != nil
  }

  /// The whole mock data set, byte for byte.
  @Test(.enabled(if: mockAvailable, "Data/mock_genmai.data or usage_dict.txt is missing (run Tools/build_oracle.sh)"))
  func mockDataSetIsByteIdentical() async throws {
    let sources = DataGenSources.mock(srcRoot: DataGenTestPaths.srcRoot, usageDict: DataGenTestPaths.usageDict)
    let (image, _) = try await GenmaiDataSet.generate(sources)
    let expected = try FileUtil.getContentBytes(DataGenTestPaths.mockData)
    let report = DataSetDiff.report(actual: image, expected: expected)
    #expect(report == nil, "\(report ?? "")")
  }

  static var ossEnabled: Bool {
    ProcessInfo.processInfo.environment["GENMAI_DATAGEN_OSS"] == "1"
      && FileManager.default.fileExists(atPath: DataGenTestPaths.ossData)
      && DataGenTestPaths.usageDict != nil && DataGenTestPaths.zipCodeKenAll != nil
      && DataGenTestPaths.zipCodeJigyosyo != nil
  }

  /// The whole OSS data set (incl. zip code / aux / filtered dictionary
  /// preprocessing).  Opt-in: GENMAI_DATAGEN_OSS=1 (slow; needs KEN_ALL.CSV /
  /// JIGYOSYO.CSV in Data/external or the Bazel cache).
  @Test(.enabled(if: ossEnabled, "set GENMAI_DATAGEN_OSS=1 (needs Data/genmai.data and the zip code CSVs)"))
  func ossDataSetIsByteIdentical() async throws {
    let workDir = NSTemporaryDirectory() + "genmai-datagen-test-\(getpid())"
    try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: workDir) }
    let dict = OssDictionarySources(
      srcRoot: DataGenTestPaths.srcRoot, zipCodeKenAll: DataGenTestPaths.zipCodeKenAll,
      zipCodeJigyosyo: DataGenTestPaths.zipCodeJigyosyo)
    let (aux, filtered) = try dict.generate(workDir: workDir)
    let sources = DataGenSources.oss(
      srcRoot: DataGenTestPaths.srcRoot, auxDictionary: aux, filteredDictionary: filtered,
      usageDict: DataGenTestPaths.usageDict)
    let (image, _) = try await GenmaiDataSet.generate(sources)
    let expected = try FileUtil.getContentBytes(DataGenTestPaths.ossData)
    let report = DataSetDiff.report(actual: image, expected: expected)
    #expect(report == nil, "\(report ?? "")")
  }
}

@Suite("DataSetDiff")
struct DataSetDiffTests {
  static func image(_ sections: [(String, [UInt8])]) -> [UInt8] {
    var w = DataSetWriter(magic: [0x4D, 0x4F, 0x43, 0x4B])
    for (n, d) in sections { w.add(n, 32, d) }
    return w.finish()
  }

  @Test func identicalImagesHaveNoReport() throws {
    let a = Self.image([("a", [1, 2, 3]), ("b", [4, 5])])
    #expect(DataSetDiff.report(actual: a, expected: a) == nil)
    #expect(try DataSetDiff.sections(a).map(\.name) == ["a", "b"])
  }

  @Test func reportsFirstDifferingSectionAndOffset() throws {
    let a = Self.image([("a", [1, 2, 3]), ("b", [4, 5, 6, 7])])
    let b = Self.image([("a", [1, 2, 3]), ("b", [4, 5, 9, 7])])
    let report = try #require(DataSetDiff.report(actual: a, expected: b))
    #expect(report.contains("b: DIFFERS"))
    #expect(report.contains("first difference at section offset 2"))
    #expect(!report.contains("a: DIFFERS"))
  }

  @Test func reportsMissingSections() throws {
    let a = Self.image([("a", [1])])
    let b = Self.image([("a", [1]), ("c", [2])])
    let report = try #require(DataSetDiff.report(actual: a, expected: b))
    #expect(report.contains("c: only in expected"))
  }
}

@Suite("PyCompat")
struct PyCompatTests {
  @Test func splitAndStripUseUnicodeWhitespace() {
    #expect(Py.split(" a\u{3000}b\t c ") == ["a", "b", "c"])
    #expect(Py.split("a b c", maxsplit: 1) == ["a", "b c"])
    #expect(Py.strip("\u{3000} x \n") == "x")
    #expect(Py.split("a\t\tb", "\t") == ["a", "", "b"])
  }

  @Test func bstrKeepsCanonicallyEquivalentStringsApart() {
    let composed = BStr("\u{304C}")  // が
    let decomposed = BStr("\u{304B}\u{3099}")  // か + combining dakuten
    #expect(composed != decomposed)
    #expect(Set([composed, decomposed]).count == 2)
    #expect(decomposed < composed)  // U+304B < U+304C
  }

  @Test func readLinesModes() throws {
    let path = NSTemporaryDirectory() + "pycompat-\(getpid()).txt"
    try FileUtil.setContents(path, "a\r\nb\u{2028}c\n")
    defer { try? FileManager.default.removeItem(atPath: path) }
    #expect(try Py.readLines(path, mode: .universal) == ["a\n", "b\u{2028}c\n"])
    #expect(try Py.readLines(path, mode: .splitlines) == ["a\r\n", "b\u{2028}", "c\n"])
  }
}
