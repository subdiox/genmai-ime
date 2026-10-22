import Foundation
import Testing

@testable import GenmaiAI

/// Paths: the model directory comes from GENMAI_MODEL_DIR, falling back to the directory the IME loads it from
/// (the settings download or Tools/prepare_genmai_model.sh). Tests that need it are skipped when it is missing.
enum GenmaiTestPaths {
  static let repoRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
  static let modelDirectory: URL = {
    if let e = ProcessInfo.processInfo.environment["GENMAI_MODEL_DIR"] { return URL(filePath: e) }
    return GenmaiConverter.defaultModelDirectory
  }()
  static let fixtures = repoRoot.appending(path: "Tests/Fixtures/genmai/tokenizer_fixtures.json")
  static var tokenizerAvailable: Bool {
    FileManager.default.fileExists(atPath: modelDirectory.appending(path: "tokenizer.json").path)
  }
  static var modelAvailable: Bool {
    FileManager.default.fileExists(atPath: modelDirectory.appending(path: "model.safetensors").path)
  }
  /// The Python reference fixtures were made with the bf16 weights; with 8-bit weights (the default install) only
  /// the results, not the exact scores, are compared.
  static var modelIsBF16: Bool { SharedConverter.converter?.quantizationBits == nil }
  /// Results of the Python MLX reference decoder (incremental, beams 5, bf16) on the daily set.
  static func pythonResults(_ name: String) -> URL {
    repoRoot.appending(path: "Tests/Fixtures/genmai/python_mlx_\(name).json")
  }
}

/// One model shared by all tests (loading takes ~0.5 s and 0.6-1.2 GB).
enum SharedConverter {
  static let converter: GenmaiConverter? = try? GenmaiConverter(directory: GenmaiTestPaths.modelDirectory)
}

struct TokenizerFixtures: Decodable {
  struct Prompt: Decodable {
    let reading: String
    let context: String
    let ids: [Int32]
  }

  struct Text: Decodable {
    let text: String
    let ids: [Int32]
  }

  let bos: Int32
  let eos: Int32
  let prompts: [Prompt]
  let raw: [Text]
  let outputs: [Text]
  let decode: [Text]

  static func load() throws -> TokenizerFixtures {
    try JSONDecoder().decode(TokenizerFixtures.self, from: Data(contentsOf: GenmaiTestPaths.fixtures))
  }
}

@Suite struct GenmaiPromptTests {
  @Test func katakana() {
    #expect(GenmaiPrompt.katakana("きょうはゔゕゖ、カナABCー") == "キョウハヴヵヶ、カナABCー")
    #expect(GenmaiPrompt.katakana("ゝゞ") == "ゝゞ")
  }

  @Test func preprocess() {
    #expect(GenmaiPrompt.preprocess("a b\nc\r\nd") == "a\u{3000}bc\rd")
  }

  @Test func contextIsCutToTheLast500Scalars() {
    let ctx = String(repeating: "あ", count: 10) + String(repeating: "い", count: 500)
    let t = GenmaiPrompt.text(reading: "う", context: ctx)
    #expect(t == "\u{EE02}" + String(repeating: "い", count: 500) + "\u{EE00}ウ\u{EE01}")
    #expect(GenmaiPrompt.text(reading: "う", context: "") == "\u{EE00}ウ\u{EE01}")
    // Python slices by code point: a combining sequence counts as two characters
    #expect(GenmaiPrompt.suffix("x\u{304B}\u{3099}", 1) == "\u{3099}")
  }

  @Test func split() {
    #expect(GenmaiModel.split("みじかい、ぶん。", chunk: 40) == ["みじかい、ぶん。"])
    let a = String(repeating: "あ", count: 30) + "、"
    let b = String(repeating: "い", count: 20) + "。"
    let c = String(repeating: "う", count: 5) + "！"
    let d = String(repeating: "え", count: 3)
    #expect(GenmaiModel.split(a + b + c + d, chunk: 40) == [a, b + c + d])
    #expect(GenmaiModel.split(a + a, chunk: 40) == [a, a])
    #expect(GenmaiModel.split(String(repeating: "お", count: 50), chunk: 40) == [String(repeating: "お", count: 50)])
    #expect(GenmaiModel.split(a + "?" + b, chunk: 0) == [a + "?" + b])
  }
}

@Suite(
  .enabled(
    if: GenmaiTestPaths.tokenizerAvailable, "genmai model dir (GENMAI_MODEL_DIR or the IME model directory) is missing")
)
struct GenmaiTokenizerTests {
  let tok: GenmaiTokenizer
  let fx: TokenizerFixtures

  init() throws {
    tok = try GenmaiTokenizer(url: GenmaiTestPaths.modelDirectory.appending(path: "tokenizer.json"))
    fx = try TokenizerFixtures.load()
  }

  @Test func specialTokens() {
    #expect(tok.bosTokenID == fx.bos)
    #expect(tok.eosTokenID == fx.eos)
  }

  /// Prompts of the eval sets (zenzlc, with contexts up to and over 500 characters) give the same ids as
  /// fmt.py `prompt_ids` with the HF tokenizer.
  @Test func promptIDsMatchPython() {
    #expect(fx.prompts.count > 500)
    var bad = 0
    for p in fx.prompts {
      let ids = GenmaiPrompt.ids(tok, reading: p.reading, context: p.context)
      if ids != p.ids {
        bad += 1
        if bad <= 5 { Issue.record("prompt ids differ for \(p.reading) / \(p.context.prefix(30))") }
      }
    }
    #expect(bad == 0)
  }

  /// Raw strings exercising the GPT-2 pre-tokenizer (contractions, spaces, digits, special tokens, emoji).
  @Test func rawStringsMatchPython() {
    for r in fx.raw {
      #expect(tok.encode(r.text) == r.ids, "\(r.text.debugDescription)")
    }
  }

  @Test func outputsMatchPython() {
    for o in fx.outputs {
      #expect(tok.encode(GenmaiPrompt.preprocess(o.text)) == o.ids, "\(o.text)")
    }
  }

  @Test func decodeMatchesPython() {
    for d in fx.decode {
      #expect(tok.decode(d.ids) == d.text, "\(d.ids.prefix(8))")
    }
  }
}

@Suite(
  .enabled(
    if: GenmaiTestPaths.modelAvailable, "genmai model dir (GENMAI_MODEL_DIR or the IME model directory) is missing"))
struct GenmaiConverterTests {
  func converter() throws -> GenmaiConverter {
    try #require(SharedConverter.converter, "cannot load \(GenmaiTestPaths.modelDirectory.path)")
  }

  @Test func convertDaily() async throws {
    let c = try converter()
    let r = try await c.convert("きょうははやめにかえります")
    #expect(r.count == 5)
    #expect(r.first?.text == "今日は早めに帰ります")
    guard GenmaiTestPaths.modelIsBF16 else { return }
    // Python MLX (genmai 0.1.0, bf16): -0.02613067626953125, second 今日は早目に帰ります -4.152080535888672
    #expect(abs((r.first?.score ?? 0) - -0.02613) < 0.01)
    #expect(r.count > 1 && r[1].text == "今日は早目に帰ります")
  }

  /// MLX keeps at most `cacheLimitBytes` of freed buffers (trimmed at its next allocation), and
  /// `releaseCachedMemory` returns them.
  @Test func bufferCacheIsBounded() async throws {
    let c = try converter()
    _ = try await c.convert("きょうはいいてんきなので、こうえんまでさんぽにいってきました")
    #expect(GenmaiConverter.memoryStats.cacheLimit == GenmaiModel.cacheLimitBytes)
    #expect(await c.releaseCachedMemory() == 0)
  }

  /// `writeQuantized` writes 8-bit weights that load and convert like the bf16 ones (needs the bf16 install).
  @Test(.enabled(if: GenmaiTestPaths.modelIsBF16, "needs bf16 weights to quantize"))
  func quantizedWeightsRoundTrip() async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "genmai-q8-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    for name in ["config.json", "tokenizer.json"] {
      try FileManager.default.copyItem(
        at: GenmaiTestPaths.modelDirectory.appending(path: name), to: dir.appending(path: name))
    }
    try GenmaiModel.writeQuantized(
      from: GenmaiTestPaths.modelDirectory.appending(path: "model.safetensors"),
      to: dir.appending(path: "model.safetensors"), bits: 8)
    let q = try GenmaiConverter(directory: dir)
    #expect(q.quantizationBits == 8)
    #expect(q.weightBytes < 400_000_000)
    let r = try await q.convert("きょうははやめにかえります")
    #expect(r.first?.text == "今日は早めに帰ります")
  }

  @Test func contextChangesTheResult() async throws {
    let c = try converter()
    let r = try await c.convert("きしゃ", context: "新聞社の")
    #expect(r.first?.text == "記者")
  }

  /// Top-1 agrees with the Python MLX reference on the daily set (bf16 near-ties may flip a few items).
  @Test(
    .enabled(if: FileManager.default.fileExists(atPath: GenmaiTestPaths.pythonResults("daily").path)),
    .enabled(if: GenmaiTestPaths.modelIsBF16, "the Python reference is bf16"))
  func dailyParityWithPython() async throws {
    let c = try converter()
    struct Reference: Decodable {
      struct Item: Decodable {
        struct Output: Decodable { var text: String }
        var query: String
        var outputs: [Output]
      }
      var items: [Item]
    }
    let j = try JSONDecoder().decode(
      Reference.self, from: Data(contentsOf: GenmaiTestPaths.pythonResults("daily")))
    let items = j.items.prefix(30)
    var same = 0
    for x in items {
      let r = try await c.convert(x.query)
      if r.first?.text == x.outputs.first?.text { same += 1 }
    }
    #expect(same >= items.count - 1, "top-1 identical \(same)/\(items.count)")
  }

  /// Incremental conversion while typing gives exactly the result of a one-shot conversion.
  @Test func incrementalEqualsConvert() async throws {
    let c = try converter()
    let reading = "きのうはあめがふっていたので、いえでほんをよんですごしましたが、ゆうがたにはれたのでさんぽにでかけて、こうえんでともだちにあいました。"
    #expect(GenmaiModel.split(reading).count > 1)
    let ctx = "日記："
    // exact equality: without the prompt KV cache / drafts (they change results by bf16 noise)
    let exact = GenmaiOptions(reusePromptKV: false)
    let full = try await c.convert(reading, context: ctx, options: exact)
    let inc = GenmaiIncrementalConverter(converter: c, context: ctx, options: exact)
    let u = Array(reading.unicodeScalars)
    var done = 0
    for i in 1..<u.count {
      done += try await inc.update(String(String.UnicodeScalarView(u[..<i])))
    }
    #expect(done == GenmaiModel.split(reading).count - 1)
    let r = try await inc.convert(reading)
    #expect(r == full)
    // editing an already converted group invalidates it
    let edited = "おととい" + reading.dropFirst(3)
    let r2 = try await inc.convert(String(edited))
    #expect(r2 == (try await c.convert(String(edited), context: ctx, options: exact)))
  }

  /// The IME's speculation: every prefix of the reading is converted in turn. With the prompt KV cache
  /// (context + the reading so far, prefilled once) the results equal those of a full prefill up to bf16 noise
  /// (the cached rows were computed in a prefill of another shape): same top-1 for the whole reading and all but at
  /// most one prefix (a near-tie on a trailing kana: 家でほ / 家でホ with genmai 0.1.0), scores within 0.5.
  @Test(arguments: [
    ("きょうはともだちとえいがをみにいくよていです", ""),
    ("しんかんせんのきっぷをよやくしておきました", "来週の出張ですが、"),
    (
      "きのうはあめがふっていたので、いえでほんをよんですごしましたが、ゆうがたにはれたのでさんぽにでかけました",
      String(repeating: "日記を書くのが習慣になっている。", count: 20)
    ),
  ])
  func promptKVReuseMatchesFullPrefill(_ reading: String, _ context: String) async throws {
    let c = try GenmaiConverter(directory: GenmaiTestPaths.modelDirectory)
    let fast = GenmaiOptions(reusePromptKV: true)
    let plain = GenmaiOptions(reusePromptKV: false)
    let u = Array(reading.unicodeScalars)
    var maxDiff = 0.0
    var differentTop: [String] = []
    for n in 1...u.count {
      let r = String(String.UnicodeScalarView(u[..<n]))
      let a = try await c.convert(r, context: context, options: fast)
      let b = try await c.convert(r, context: context, options: plain)
      if a.first?.text != b.first?.text { differentTop.append("\(a.first?.text ?? "-") / \(b.first?.text ?? "-")") }
      if n == u.count { #expect(a.first?.text == b.first?.text) }
      if let x = a.first, let y = b.first { maxDiff = max(maxDiff, abs(x.score - y.score)) }
    }
    #expect(differentTop.count <= 1, "\(differentTop)")
    #expect(maxDiff < 0.5)
    let (_, reused) = await c.promptTokenStats
    #expect(reused > 0)
  }

  /// Draft-and-verify while typing (every prefix converted in turn, the previous best output as the draft):
  /// fewer decode steps and (almost always) the same top-1 as a plain beam search: identical for the full
  /// sentences, for >= 90 % of the prefixes typed on the way (an incomplete reading such as きょうはと is
  /// ambiguous). The n-best alternatives share the accepted prefix, so only the top-1 is compared.
  @Test(arguments: [
    ("きょうはともだちとえいがをみにいくよていです", ""),
    ("しんかんせんのきっぷをよやくしておきました", "来週の出張ですが、"),
    ("きのうはあめがふっていたので、いえでほんをよんですごしましたが、ゆうがたにはれたのでさんぽにでかけました", ""),
  ])
  func draftAndVerifyKeepsTheTopCandidate(_ reading: String, _ context: String) async throws {
    let c = try GenmaiConverter(directory: GenmaiTestPaths.modelDirectory)
    let fast = GenmaiOptions(draft: true)
    let plain = GenmaiOptions(reusePromptKV: false)
    let inc = GenmaiIncrementalConverter(converter: c, context: context)
    let u = Array(reading.unicodeScalars)
    var steps = 0
    var plainSteps = 0
    var same = 0
    for n in 1...u.count {
      let r = String(String.UnicodeScalarView(u[..<n]))
      let s0 = await c.draftStats.decodeSteps
      let a = try await inc.convert(r, lastGroup: fast)
      let s1 = await c.draftStats.decodeSteps
      let b = try await c.convert(r, context: context, options: plain)
      plainSteps += await c.draftStats.decodeSteps - s1
      steps += s1 - s0
      if a.first?.text == b.first?.text { same += 1 }
      if n == u.count { #expect(a.first?.text == b.first?.text) }
    }
    #expect(Double(same) >= Double(u.count) * 0.9, "same top-1 for \(same) / \(u.count) prefixes")
    #expect(await c.draftStats.accepted > 0)
    #expect(steps * 2 < plainSteps, "decode steps with drafts \(steps), without \(plainSteps)")
  }

  @Test func cancellation() async throws {
    let c = try converter()
    let reading = String(repeating: "とうきょうとっきょきょかきょく", count: 3)
    let task = Task { try await c.convert(reading) }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    // the converter is still usable afterwards
    #expect(try await c.convert("ねこ").isEmpty == false)
  }
}
