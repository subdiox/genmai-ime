import Foundation
import Testing

@testable import GenmaiAI

@Suite struct GenmaiSearchTests {
  @Test func draftAcceptance() {
    // rows: (best token, its log-prob, second best log-prob) after the prompt and after each draft token
    let rows: [(Int32, Float, Float)] = [(7, -0.1, -3.0), (8, -0.2, -2.5), (9, -0.5, -1.0), (4, -0.1, -5)]
    let top2 = { (a: Int) in (best: (token: rows[a].0, logp: rows[a].1), second: rows[a].2) }
    // the third token's margin is 0.5 < 2: two accepted
    #expect(GenmaiDraftStore.accept([7, 8, 9, 4], margin: 2, top2: top2) == [0, -0.1, -0.3])
    #expect(GenmaiDraftStore.accept([7, 8, 9, 4], margin: 0.5, top2: top2).count == 5)
    #expect(GenmaiDraftStore.accept([7, 5], margin: 2, top2: top2) == [0, -0.1])  // 5 is not the argmax
    #expect(GenmaiDraftStore.accept([], margin: 2, top2: top2) == [0])
  }

  @Test func draftStore() {
    var s = GenmaiDraftStore()
    s.store("a", [1, 2, 3])
    s.store("b", [4])
    s.store("a", [5, 6])
    #expect(s.tokens(for: "a", maxNew: 10) == [5, 6])
    #expect(s.tokens(for: "a", maxNew: 3) == [5])  // at most maxNew - 2
    #expect(s.tokens(for: "c", maxNew: 10) == [])
    s.store("b", [])
    #expect(s.tokens(for: "b", maxNew: 10) == [])
    for i in 0..<(GenmaiDraftStore.maxDrafts + 1) { s.store("x\(i)", [1]) }
    #expect(s.tokens(for: "a", maxNew: 10) == [])  // the oldest was dropped
  }

  @Test func bestAndFloor() {
    let c = [
      GenmaiCandidate(text: "x", score: -1), GenmaiCandidate(text: "y", score: -2),
      GenmaiCandidate(text: "x", score: -0.5), GenmaiCandidate(text: "z", score: -3),
    ]
    #expect(GenmaiSearch.best(c, 2) == [c[2], c[1]])
    let bound = GenmaiSearchBound(prefixes: [], offsets: [], keep: 3)
    #expect(bound.floor(c) == -3)  // distinct texts x, y, z
    #expect(bound.floor(Array(c.prefix(3))) == -.infinity)  // only two distinct texts
  }
}

/// Core ML decoder tests: they need a Core ML model directory in $GENMAI_COREML_MODEL_DIR (genmai.mlpackage or
/// genmai.mlmodelc, genmai_coreml.json, tokenizer.json, config.json) and are skipped without it.
@Suite(
  .enabled(
    if: GenmaiTestPaths.modelAvailable, "genmai model dir (GENMAI_MODEL_DIR or the IME model directory) is missing"))
struct GenmaiCoreMLModelTests {
  @Test func convertsAndTheBoundKeepsTheResult() async throws {
    let dir = GenmaiTestPaths.modelDirectory
    let m = try await GenmaiCoreMLModel.load(directory: dir)
    let r = try m.convert("きょうははやめにかえります")
    #expect(r.first?.text == "今日は早めに帰ります")
    // a two-chunk reading: extend with the bound (the default) = the unbounded batch merged by hand
    let reading = String(repeating: "あしたはあめがふるそうです、", count: 2) + "かさをもっていきます。"
    let parts = GenmaiSearch.split(reading, chunk: 20)
    #expect(parts.count > 1)
    var hyps = [GenmaiCandidate(text: "", score: 0)]
    for p in parts.dropLast() { hyps = try m.extend(hyps, part: p, options: GenmaiOptions(chunk: 20)) }
    let bounded = try m.extend(hyps, part: parts[parts.count - 1], options: GenmaiOptions(chunk: 20))
    let outs = try m.genBatch(
      parts[parts.count - 1], contexts: hyps.map(\.text), beams: 4, bound: nil)
    var all: [GenmaiCandidate] = []
    for (h, o) in zip(hyps, outs) {
      all += o.map { GenmaiCandidate(text: h.text + $0.text, score: h.score + $0.score) }
    }
    // (the prompts are prefilled in other chunks: equal up to fp16 rounding)
    let expected = GenmaiSearch.best(all, 5)
    #expect(bounded.map(\.text) == expected.map(\.text))
    for (x, y) in zip(bounded, expected) { #expect(abs(x.score - y.score) < 0.05) }
  }

  /// The score of a text equals its score as a candidate of the beam search (up to fp16 rounding).
  @Test func scoreMatchesTheSearch() async throws {
    let dir = GenmaiTestPaths.modelDirectory
    let m = try await GenmaiCoreMLModel.load(directory: dir)
    let r = try m.convert("きょうははやめにかえります", context: "あ")
    for x in r {
      let s = try #require(try m.score(x.text, reading: "きょうははやめにかえります", context: "あ"))
      #expect(abs(x.score - s) < 0.1, "\(x.text): \(x.score) vs. \(s)")
    }
  }

  @Test func draftsAreVerified() async throws {
    let dir = GenmaiTestPaths.modelDirectory
    let m = try await GenmaiCoreMLModel.load(directory: dir)
    let opt = GenmaiOptions(draft: true)
    let plain = try m.convert("きょうはいいてんきですね")
    _ = try m.convert("きょうはいいてんきですね", options: opt)  // stores the draft
    let steps = m.decodeSteps
    let drafted = try m.convert("きょうはいいてんきですね", options: opt)
    #expect(m.draftTokensAccepted > 0)
    #expect(m.decodeSteps - steps < 5)
    #expect(drafted.first?.text == plain.first?.text)
  }
}
