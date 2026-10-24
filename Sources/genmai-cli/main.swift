// genmai-cli: model preparation, conversion, evaluation and parity checks for GenmaiAI.
//
//   genmai-cli install [--size small|medium] [--tag vX.Y.Z] [destination dir]
//       downloads the newest model release this IME can run (or the given tag) from Hugging Face and installs it
//       like the config dialog does (8-bit weights; default: medium, into the IME's model directory)
//   genmai-cli prepare <source model dir> <destination dir>
//       writes the compact runtime model (bf16, Conv1D weights as (out, in)) + tokenizer.json, config.json for a
//       local HF model directory (e.g. a checkpoint that is not a release)
//   genmai-cli quantize [--bits 8] <model dir> <output file>
//       writes the weights of <model dir> with the linear layers quantized (MLX affine, groups of 64): the
//       model-8bit.safetensors of a release
//   genmai-cli convert [--model DIR] [--context TEXT] [--beams N] <reading>...
//   genmai-cli eval [--model DIR] --tag TAG [--beams 5] [--incremental] [--out-dir DIR] <eval set>...
//       eval sets: anco-format .json (query / answer / left_context) or ime_v1 .jsonl (reading / positives /
//       left_context / id), like the Python evaluator; writes <out-dir>/gen_<TAG>_c40_<name>.json
//       in gen_eval format and prints top-1 accuracy (exact match) and latency (median / p90 / max).
//       --incremental replays the reading one character at a time through GenmaiIncrementalConverter, like
//       mlx_eval.py --incremental: latency is the conversion key only. --every-key also converts the whole
//       prefix after every character (the IME's speculation; "background" = those conversions).
//       --no-kv-reuse disables the prompt KV cache (GenmaiOptions.reusePromptKV); --draft [--draft-margin M] enables
//       draft-and-verify decoding (GenmaiOptions.draft).
//   genmai-cli compare <ours.json> <reference.json>
//       per-item parity: identical top-1 / identical n-best (texts) / max score difference.
//   genmai-cli session-eval [--timeout-ms N] [--settle none|chunks|idle] [--errors] [--out-dir DIR] <anco set.json>...
//       types the readings through the IME session layer (SessionHandlerBackend) with AI conversion off and on
//       and reports top-1 accuracy and conversion-key latency (see SessionEval.swift).
//   GENMAI_MODEL_DIR overrides the default model directory (~/Library/Application Support/Genmai/model).

import Foundation
import GenmaiAI
import GenmaiClient
import Synchronization

func fail(_ msg: String) -> Never {
  FileHandle.standardError.write(Data((msg + "\n").utf8))
  exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
  fail(
    "usage: genmai-cli install|prepare|quantize|convert|eval|compare|session-eval ... (see Sources/genmai-cli/main.swift)"
  )
}
args.removeFirst()

@MainActor func option(_ name: String) -> String? {
  guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
  let v = args[i + 1]
  args.removeSubrange(i...(i + 1))
  return v
}

@MainActor func flag(_ name: String) -> Bool {
  guard let i = args.firstIndex(of: name) else { return false }
  args.remove(at: i)
  return true
}

@MainActor func modelDirectory() -> URL {
  if let m = option("--model") { return URL(filePath: m) }
  if let e = ProcessInfo.processInfo.environment["GENMAI_MODEL_DIR"] { return URL(filePath: e) }
  return GenmaiConverter.defaultModelDirectory
}

@MainActor func loadConverter() async -> GenmaiConverter {
  let dir = modelDirectory()
  do {
    let c = try GenmaiConverter(directory: dir)
    let t = Date()
    await c.warmup()
    print(
      String(
        format: "model %@: load %.2f s, warmup %.2f s, weights %.0f MB", dir.path, c.loadSeconds,
        Date().timeIntervalSince(t), Double(c.weightBytes) / 1e6))
    return c
  } catch {
    fail("cannot load \(dir.path): \(error)")
  }
}

struct EvalItem {
  var query: String
  var answers: [String]
  var context: String
  var id: String
}

/// A JSON string or number as text (the item ids of the evaluation sets are either).
struct JSONScalarText: Decodable, CustomStringConvertible {
  var description: String

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let string = try? container.decode(String.self) {
      description = string
    } else if let int = try? container.decode(Int.self) {
      description = String(int)
    } else {
      description = String(try container.decode(Double.self))
    }
  }
}

/// A line of an AJIMEE-style .jsonl set.
private struct JSONLItem: Decodable {
  var reading: String
  var positives: [String]
  var leftContext: String?
  var id: JSONScalarText

  enum CodingKeys: String, CodingKey {
    case reading, positives, id
    case leftContext = "left_context"
  }
}

/// An item of a .json set.
private struct JSONItem: Decodable {
  var query: String
  var answer: [String]
  var leftContext: String?

  enum CodingKeys: String, CodingKey {
    case query, answer
    case leftContext = "left_context"
  }
}

func loadSet(_ path: String) throws -> [EvalItem] {
  let data = try Data(contentsOf: URL(filePath: path))
  let decoder = JSONDecoder()
  if path.hasSuffix(".jsonl") {
    return try String(decoding: data, as: UTF8.self).split(separator: "\n").map { line in
      let r = try decoder.decode(JSONLItem.self, from: Data(line.utf8))
      return EvalItem(query: r.reading, answers: r.positives, context: r.leftContext ?? "", id: r.id.description)
    }
  }
  return try decoder.decode([JSONItem].self, from: data).map { x in
    EvalItem(query: x.query, answers: x.answer, context: x.leftContext ?? "", id: x.query)
  }
}

/// The result file of `eval` (and of the Python reference): per item its n-best list.
struct EvalResultFile: Decodable {
  struct Output: Decodable {
    var text: String
    var score: Double
  }

  struct Item: Decodable {
    var id: JSONScalarText
    var query: String
    var outputs: [Output]?
  }

  var items: [Item]
}

func percentile(_ xs: [Double], _ p: Double) -> Double {
  let s = xs.sorted()
  return s[min(s.count - 1, Int(Double(s.count) * p))]
}

func median(_ xs: [Double]) -> Double {
  let s = xs.sorted()
  let n = s.count
  return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
}

func prefix(_ s: String, _ n: Int) -> String {
  String(String.UnicodeScalarView(s.unicodeScalars.prefix(n)))
}

switch command {
case "install":
  let tag = option("--tag")
  guard let size = AIModelSize(rawValue: option("--size") ?? AIModelSize.default.rawValue) else {
    fail("--size must be one of \(AIModelSize.allCases.map(\.rawValue).joined(separator: ", "))")
  }
  let release: GenmaiModelRelease
  do {
    if let tag {
      release = try await GenmaiModelRelease.fetch(repository: size.repository, tag: tag)
    } else {
      release = try await GenmaiModelRelease.latest(repository: size.repository)
    }
  } catch {
    fail("cannot look up the model release: \(error)")
  }
  let dst = args.first.map { URL(filePath: $0) } ?? GenmaiConverter.defaultModelDirectory
  print(
    "installing \(size.modelName) \(release.info.version) (\(release.info.repository)@\(release.info.revision))"
      + " into \(dst.path)")
  let last = Mutex<String>("")
  do {
    let t = Date()
    try await AIModelInstaller.install(release, to: dst) { phase in
      let line: String
      switch phase {
      case .downloading(let received, let total):
        line = String(format: "downloading %.0f%%", Double(received) / Double(max(total, 1)) * 100)
      case .verifying:
        line = "verifying"
      case .installing:
        line = "installing"
      }
      let changed = last.withLock { l in
        defer { l = line }
        return l != line
      }
      if changed { print(line) }
    }
    print(String(format: "installed in %.1f s", Date().timeIntervalSince(t)))
    let c = try GenmaiConverter(directory: dst)
    print("check:", try await c.convert("きょうはいいてんきですね").first?.text ?? "-")
  } catch {
    fail("install failed: \(error)")
  }

case "quantize":
  let bits = option("--bits").flatMap(Int.init) ?? 8
  guard args.count == 2 else { fail("usage: genmai-cli quantize [--bits 8] <model dir> <output file>") }
  let src = URL(filePath: args[0])
  let out = URL(filePath: args[1])
  do {
    let t = Date()
    try GenmaiModel.writeQuantized(from: src.appending(path: "model.safetensors"), to: out, bits: bits)
    let size = (try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
    print(String(format: "wrote %@ (%.0f MB) in %.1f s", out.path, Double(size) / 1e6, Date().timeIntervalSince(t)))
  } catch {
    fail("quantize failed: \(error)")
  }

case "prepare":
  guard args.count == 2 else { fail("usage: genmai-cli prepare <source dir> <destination dir>") }
  let src = URL(filePath: args[0])
  let dst = URL(filePath: args[1])
  do {
    let t = Date()
    try await AIModelInstaller.prepare(source: src, destination: dst)
    let out = dst.appending(path: "model.safetensors")
    let size = (try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
    print(String(format: "wrote %@ (%.0f MB) in %.1f s", out.path, Double(size) / 1e6, Date().timeIntervalSince(t)))
    // sanity check: load the result
    let c = try GenmaiConverter(directory: dst)
    print("check:", try await c.convert("きょうはいいてんきですね").first?.text ?? "-")
  } catch {
    fail("prepare failed: \(error)")
  }

case "convert":
  let ctx = option("--context") ?? ""
  guard let beams = Int(option("--beams") ?? "5") else { fail("--beams needs a number") }
  let c = await loadConverter()
  for reading in args {
    let t = Date()
    let r = try await c.convert(reading, context: ctx, options: GenmaiOptions(beams: beams))
    print(String(format: "%@  (%.0f ms)", reading, Date().timeIntervalSince(t) * 1000))
    for x in r { print(String(format: "  %8.3f  %@", x.score, x.text)) }
  }

case "eval":
  guard let tag = option("--tag") else { fail("eval needs --tag") }
  guard let beams = Int(option("--beams") ?? "5") else { fail("--beams needs a number") }
  let outDir = URL(filePath: option("--out-dir") ?? ".")
  let incremental = flag("--incremental")
  let everyKey = flag("--every-key")
  let c = await loadConverter()
  var opt = GenmaiOptions(beams: beams)
  if flag("--no-kv-reuse") { opt.reusePromptKV = false }
  if let m = option("--draft-margin").flatMap(Float.init) { opt.draftMargin = m }
  if flag("--draft") { opt.draft = true }
  for path in args {
    let name = String(URL(filePath: path).lastPathComponent.split(separator: ".")[0])
    let items: [EvalItem]
    do { items = try loadSet(path) } catch { fail("cannot read \(path): \(error)") }
    var out: [[String: Any]] = []
    var ts: [Double] = []
    var bg: [Double] = []
    var hits = 0
    for x in items {
      let hyps: [GenmaiCandidate]
      let t: Date
      if everyKey {
        // the IME's speculation: the whole composition is converted after every keystroke
        let inc = GenmaiIncrementalConverter(converter: c, context: x.context, options: opt)
        let n = x.query.unicodeScalars.count
        for i in 1..<max(n, 1) {
          let t0 = Date()
          _ = try await inc.convert(prefix(x.query, i))
          bg.append(Date().timeIntervalSince(t0) * 1000)
        }
        t = Date()
        hyps = try await inc.convert(x.query)
      } else if incremental {
        let inc = GenmaiIncrementalConverter(converter: c, context: x.context, options: opt)
        let n = x.query.unicodeScalars.count
        for i in 1..<max(n, 1) {
          let t0 = Date()
          if try await inc.update(prefix(x.query, i)) > 0 {
            bg.append(Date().timeIntervalSince(t0) * 1000)
          }
        }
        t = Date()
        hyps = try await inc.convert(x.query)
      } else {
        t = Date()
        hyps = try await c.convert(x.query, context: x.context, options: opt)
      }
      ts.append(Date().timeIntervalSince(t) * 1000)
      if let top = hyps.first, x.answers.contains(top.text) { hits += 1 }
      out.append([
        "query": x.query, "answers": x.answers, "id": x.id, "latency_ms": ts.last ?? 0,
        "outputs": hyps.map { ["text": $0.text, "score": $0.score] as [String: Any] },
      ])
    }
    let json: [String: Any] = ["n_best": beams, "execution_time": ts.reduce(0, +) / 1000, "items": out]
    let file = outDir.appending(path: "gen_\(tag)_c40_\(name).json")
    try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .withoutEscapingSlashes]).write(to: file)
    print(
      String(
        format: "%@: top1 (exact) %.1f%%  latency median %.0f ms p90 %.0f ms max %.0f ms  (n=%d)",
        name, Double(hits) / Double(items.count) * 100, median(ts), percentile(ts, 0.9), ts.max() ?? 0,
        items.count))
    if !bg.isEmpty {
      print(
        String(
          format: "  background %@ while typing: %d (median %.1f ms, mean %.1f, max %.0f ms)",
          everyKey ? "conversions" : "chunk conversions", bg.count, median(bg),
          bg.reduce(0, +) / Double(bg.count), bg.max() ?? 0))
    }
    let (pre, re) = await c.promptTokenStats
    let (acc, steps) = await c.draftStats
    print(
      "  so far: prompt tokens prefilled \(pre), reused from the KV cache \(re); output tokens accepted from drafts \(acc), decode steps \(steps)"
    )
  }

case "compare":
  guard args.count == 2 else { fail("usage: genmai-cli compare <ours.json> <reference.json>") }
  func items(_ p: String) throws -> [String: [EvalResultFile.Output]] {
    let j = try JSONDecoder().decode(EvalResultFile.self, from: Data(contentsOf: URL(filePath: p)))
    var d: [String: [EvalResultFile.Output]] = [:]
    for x in j.items { d["\(x.id)\u{0}\(x.query)"] = x.outputs }
    return d
  }
  let a = try items(args[0])
  let b = try items(args[1])
  var n = 0
  var top1 = 0
  var all = 0
  var sameSet = 0
  var maxDiff = 0.0
  var diffs: [String] = []
  for (k, ob) in b.sorted(by: { $0.key < $1.key }) {
    guard let oa = a[k] else { continue }
    n += 1
    let ta = oa.map(\.text)
    let tb = ob.map(\.text)
    if ta.first == tb.first { top1 += 1 } else { diffs.append(k) }
    if ta == tb {
      all += 1
      for (x, y) in zip(oa, ob) {
        maxDiff = max(maxDiff, abs(x.score - y.score))
      }
    }
    if Set(ta) == Set(tb) { sameSet += 1 }
  }
  print(
    String(
      format:
        "items %d: top-1 identical %d (%.1f%%), n-best identical %d (%.1f%%), same n-best set %d; max |score diff| on identical lists %.4f",
      n, top1, Double(top1) / Double(max(n, 1)) * 100, all, Double(all) / Double(max(n, 1)) * 100, sameSet, maxDiff))
  for k in diffs.prefix(20) {
    let q = k.split(separator: "\u{0}").last.map(String.init) ?? k
    let fa = (a[k] ?? []).prefix(2).map { "\($0.text) \(String(format: "%.3f", $0.score))" }
    let fb = (b[k] ?? []).prefix(2).map { "\($0.text) \(String(format: "%.3f", $0.score))" }
    print("  \(q)\n    swift:  \(fa)\n    python: \(fb)")
  }

case "logprobs":
  // logprobs <reading> [ids...]: prints the 8 best next tokens after the prompt and after each given id
  let c = await loadConverter()
  let reading = args.removeFirst()
  var continuation: [Int32] = []
  for arg in args {
    guard let id = Int32(arg) else { fail("not a token id: \(arg)") }
    continuation.append(id)
  }
  let rows = await c.debugLogProbs(reading, continuation: continuation)
  for r in rows {
    let top = r.enumerated().sorted { $0.element > $1.element }.prefix(8)
    print(top.map { String(format: "%d:%.5f", $0.offset, $0.element) }.joined(separator: " "))
  }

case "session-eval":
  await runSessionEval(args)

default:
  fail("unknown command \(command)")
}
