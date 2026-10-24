import Foundation
import GenmaiBase
import GenmaiCore
import Testing

@testable import GenmaiClient

@Suite(
  .enabled(
    if: FileManager.default.fileExists(atPath: OssDataManager.defaultDataPath),
    "Data/genmai.data is missing (run Tools/build_data.sh)"))
struct AIDictionaryHinterTests {
  let hinter: AIDictionaryHinter

  init() throws {
    let profile = FileManager.default.temporaryDirectory.appending(path: "genmai-hinter-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
    SystemUtil.setUserProfileDirectory(profile.path)
    let dataManager = try OssDataManager.create()
    hinter = try AIDictionaryHinter(engine: try Engine.createEngine(dataManager), dataManager: dataManager)
  }

  @Test func conversionAndProperNouns() {
    let h = hinter.hints(reading: "くさかべちょうにいった")
    #expect(h.segments.joined() == "日下部町に行った")
    // 草壁 / 可部町 lie inside the reading of 日下部町, which the conversion has
    #expect(!h.properNouns.contains("草壁"))
    #expect(!h.properNouns.contains("可部町"))
    #expect(h.properNouns.count <= AIDictionaryHinter.maxProperNouns)
    #expect(h.properNouns.allSatisfy { $0.count >= 2 && !h.segments.joined().contains($0) })
  }

  @Test func katakanaReadingAndEmpty() {
    #expect(hinter.hints(reading: "キョウハ").segments.joined() == hinter.hints(reading: "きょうは").segments.joined())
    #expect(hinter.hints(reading: "") == AIDictionaryHints(segments: [], properNouns: []))
  }
}
