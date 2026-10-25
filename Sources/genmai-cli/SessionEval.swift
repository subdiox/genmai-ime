// genmai-cli session-eval: AI conversion through the real IME session layer.
//
//   genmai-cli session-eval [--timeout-ms N] [--candidates N] [--settle none|chunks|idle] [--limit N] [--errors]
//                           [--typing-ms N[,N...]] [--space-delay-ms N] [--out-dir DIR] [--profile-copy DIR]
//                           [--trace] [--debug-log] [--no-reading-check] [--dictionary-weight W]
//                           <anco-format set.json>...
//
// Every item is typed into a `SessionHandlerBackend` (Mozc Engine + SessionHandler) as direct kana input
// (one SEND_KEY per character with key_string, hiragana mode), the left context is given as the IMK surrounding
// text would be (Context.preceding_text = last 20 characters on the first key, the AI hook gets up to 500),
// then SPACE converts and the preedit (all segments) is the result; ESC ESC cancels, so nothing is learned.
// Two runs per set: plain Mozc (no hook) and Mozc + AIConversionHook(GenmaiAugmenter). Before SPACE the run
// waits for the background work of the last keystroke: --settle chunks (default) = the pre-conversion of the
// finished chunks (a user typing at normal speed gives it the time), idle = also the speculative conversion of
// the whole composition (a user who pauses before converting), none = SPACE right after the last key.
// --typing-ms 120,200 instead simulates real typing: one kana every N ms of wall-clock time (one AI run per
// interval; the background work runs while the next key is awaited), SPACE --space-delay-ms (default 0) after the
// last kana; it also reports where the AI result came from at SPACE (ready / awaited in flight / converted then)
// and the model's busy time per keystroke. The plain Mozc run types without delays (its result does not depend on
// timing). Reports strict / normalized top-1 (normalization of
// the research scoring script) and the conversion-key latency; --out-dir writes anco-format results
// (<dir>/session_<mode>_<set>.json, readable by score.py).
// --profile-copy DIR copies the profile files in DIR (e.g. a `cp` of ~/Library/Application Support/Mozc, without
// the genmai model) into the temporary profile, so that the user's learning data and config take part (DIR itself
// is never written). --trace prints, per key, the first suggestions (AI ones marked; also after the AI suggestion
// refresh, which it awaits like the input controller does) and, at SPACE, the AI n-best and every segment's top
// candidates. --debug-log enables ai_debug.log in the temporary profile and prints it. --no-reading-check turns off
// the reading check of AI candidates (AIReadingChecker); with it on, the report counts the candidates it dropped
// and how many of them were a correct answer.

import Foundation
import GenmaiAI
import GenmaiAIClient
import GenmaiBase
import GenmaiClient
import GenmaiCore
import GenmaiProtocol

/// The research scoring script's VARIANTS (orthographic variants treated as equal).
let kScoreVariants: [(String, String)] = [
  ("宜しく", "よろしく"), ("致し", "いたし"), ("下さい", "ください"), ("御飯", "ご飯"),
  ("気を付け", "気をつけ"), ("取り敢えず", "とりあえず"), ("マジ", "まじ"),
  ("て来る", "てくる"), ("て来た", "てきた"), ("て来て", "てきて"),
  ("て行く", "ていく"), ("既に", "すでに"), ("綺麗", "きれい"), ("分か", "わか"),
  ("出来", "でき"), ("為", "ため"), ("事", "こと"), ("時", "とき"), ("頂", "いただ"),
  ("貰", "もら"), ("沢山", "たくさん"), ("又", "また"), ("良い", "いい"),
  ("０", "0"), ("１", "1"), ("２", "2"), ("３", "3"), ("４", "4"), ("５", "5"),
  ("６", "6"), ("７", "7"), ("８", "8"), ("９", "9"), ("？", "?"), ("！", "!"),
  ("　", " "),
]

func scoreNorm(_ s: String) -> String {
  var s = s
  for (a, b) in kScoreVariants {
    s = s.replacingOccurrences(of: a, with: b)
  }
  return s
}

@MainActor
final class SessionEvalRunner {
  let backend: SessionHandlerBackend
  let hook: AIConversionHook?
  enum Settle: String {
    case none, chunks, idle
  }
  let settle: Settle
  /// Real-time typing: one kana every `typingInterval` (wall clock, background work runs meanwhile), SPACE
  /// `spaceDelay` after the last kana. nil: keys back to back, then `settle`.
  let typingInterval: Duration?
  let spaceDelay: Duration
  let client: InProcessClient
  let trace: Bool

  init(
    backend: SessionHandlerBackend, hook: AIConversionHook?, settle: Settle, typingInterval: Duration? = nil,
    spaceDelay: Duration = .zero, trace: Bool = false
  ) {
    self.trace = trace
    self.backend = backend
    self.hook = hook
    self.settle = settle
    self.typingInterval = typingInterval
    self.spaceDelay = spaceDelay
    client = InProcessClient.make(backend: backend)
    var on = KeyEvent()
    on.specialKey = .on
    on.mode = .hiragana
    _ = client.sendKey(on)
  }

  struct ItemResult {
    var preedit: String
    var top: String
    var latency: Double
    var record: AIConversionHook.ConversionRecord?
    var source: GenmaiAugmenter.ConvertSource?
    /// Model busy time while typing (first key to SPACE) and during SPACE, in ms.
    var busyTyping: Double = 0
    var busyConversion: Double = 0
    var keys = 0
  }

  func run(_ item: EvalItem) async -> ItemResult {
    hook?.noteSurroundingText(item.context)
    var context = Context()
    context.precedingText = String(item.context.suffix(20))
    var preedit = ""
    var first = true
    let clock = ContinuousClock()
    let typingStart = clock.now
    let busy0 = GenmaiConverter.busyStats.seconds
    var keys = 0
    for c in item.query {
      if let typingInterval, keys > 0 {
        try? await clock.sleep(until: typingStart + typingInterval * keys)
      }
      var key = KeyEvent()
      key.keyString = String(c)
      key.mode = .hiragana
      let output = client.sendKey(key, context: first ? context : nil)
      first = false
      keys += 1
      preedit = output?.preedit.segment.map(\.value).joined() ?? preedit
      if trace, let output {
        Self.printSuggestions(preedit, output)
        // the input controller's AI suggestion refresh: await the AI result of this composition, then
        // MOVE_CURSOR to the current position re-runs the suggestion
        while let update = hook?.suggestionUpdate(), await update.value {
          var command = SessionCommand()
          command.type = .moveCursor
          command.cursorPosition = output.preedit.cursor
          guard let refreshed = client.sendCommand(command) else { break }
          Self.printSuggestions("  refreshed", refreshed)
        }
      }
    }
    if let typingInterval {
      try? await clock.sleep(until: typingStart + typingInterval * (keys - 1) + spaceDelay)
    } else if settle != .none, let genmai = hook?.genmai, hook?.isEnabled == true {
      await genmai.waitForPreparation(speculation: settle == .idle)
    }
    var space = KeyEvent()
    space.specialKey = .space
    let busy1 = GenmaiConverter.busyStats.seconds
    let start = clock.now
    // like the input controller: an AI result still in flight is awaited (bounded) before SPACE is evaluated
    var waited = false
    if let hook, let wait = hook.conversionWait(for: space) {
      waited = true
      await wait.value
    }
    let converted = client.sendKey(space)
    let elapsed = clock.now - start
    if trace, let converted {
      if let record = hook?.lastConversion, hook?.isEnabled == true {
        print("  SPACE: AI \(record.texts) timedOut=\(record.timedOut) outcome=\(record.outcome)")
      }
      printConversion(client, converted)
    }
    let busy2 = GenmaiConverter.busyStats.seconds
    let top = converted?.preedit.segment.map(\.value).joined() ?? ""
    var escape = KeyEvent()
    escape.specialKey = .escape
    _ = client.sendKey(escape)
    _ = client.sendKey(escape)
    let (s, a) = elapsed.components
    return ItemResult(
      preedit: preedit, top: top, latency: Double(s) * 1000 + Double(a) / 1e15,
      record: hook?.isEnabled == true ? hook?.lastConversion : nil,
      source: hook?.isEnabled != true
        ? nil
        : waited ? hook?.genmai?.lastConvertSource : hook?.lastConversion?.timedOut == true ? .notReady : .ready,
      busyTyping: (busy1 - busy0) * 1000, busyConversion: (busy2 - busy1) * 1000, keys: keys)
  }

  static func label(_ c: Genmai_Commands_CandidateWindow.Candidate) -> String {
    c.annotation.description_p.isEmpty ? c.value : "\(c.value)[\(c.annotation.description_p)]"
  }

  static func printSuggestions(_ preedit: String, _ output: Output) {
    let window = output.candidateWindow
    let candidates = window.candidate.prefix(4).map(label)
    print("  \(preedit)\t\(window.category) \(candidates.joined(separator: " / "))")
  }

  static func label(_ c: Genmai_Commands_CandidateWord) -> String {
    c.annotation.description_p.isEmpty ? c.value : "\(c.value)[\(c.annotation.description_p)]"
  }

  /// The preedit segments of a conversion and the top candidates of each segment (the focus is moved along the
  /// segments with Right: an Output only lists the focused segment's candidates).
  func printConversion(_ client: InProcessClient, _ converted: Output) {
    let segments = converted.preedit.segment.map(\.value)
    print("  converted: \(segments.joined(separator: "|"))")
    var output = converted
    for i in segments.indices {
      let candidates = output.allCandidateWords.candidates.prefix(5).map(Self.label)
      print("    [\(i)] \(segments[i]): \(candidates.joined(separator: " / "))")
      if i + 1 < segments.count {
        var right = KeyEvent()
        right.specialKey = .right
        guard let next = client.sendKey(right) else { break }
        output = next
      }
    }
  }

  /// Lets the background work of the previous item finish (typing mode), so that items do not interfere.
  func drain() async {
    if let genmai = hook?.genmai, hook?.isEnabled == true {
      await genmai.waitForPreparation(speculation: true)
    }
  }
}

@MainActor
func runSessionEval(_ arguments: [String]) async {
  var args = arguments
  func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
  }
  func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
  }
  let timeout = option("--timeout-ms").flatMap(Int.init) ?? AIConversionSettings.defaultTimeoutMilliseconds
  let candidates = option("--candidates").flatMap(Int.init) ?? AIConversionSettings.defaultCandidateCount
  let limit = option("--limit").flatMap(Int.init)
  let outDir = option("--out-dir")
  let model = option("--model")
  guard let settle = SessionEvalRunner.Settle(rawValue: option("--settle") ?? "chunks") else {
    fail("--settle must be none, chunks or idle")
  }
  let showErrors = flag("--errors")
  let typingIntervals = (option("--typing-ms") ?? "").split(separator: ",").compactMap { Int($0) }
  let spaceDelay = option("--space-delay-ms").flatMap(Int.init) ?? 0
  let profileCopy = option("--profile-copy")
  let trace = flag("--trace")
  let debugLog = flag("--debug-log")
  let readingCheck = !flag("--no-reading-check")
  let dictionaryWeight =
    option("--dictionary-weight").flatMap(Double.init) ?? AIConversionSettings.defaultDictionaryWeight
  let proposalWeight =
    option("--proposal-weight").flatMap(Double.init) ?? AIConversionSettings.defaultDictionaryProposalWeight
  if args.isEmpty {
    fail(
      "usage: genmai-cli session-eval [--timeout-ms N] [--settle none|chunks|idle] [--typing-ms N[,N]] [--space-delay-ms N] [--errors] [--out-dir D] <set.json>..."
    )
  }

  // A temporary user profile: no learning data of the user is read or written.
  let profile = FileManager.default.temporaryDirectory.appending(path: "genmai-session-eval-\(getpid())")
  try? FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: profile) }
  if let profileCopy {
    // Copies the files (not the genmai model directory); the source is only read.
    let source = URL(filePath: profileCopy, directoryHint: .isDirectory)
    let names = (try? FileManager.default.contentsOfDirectory(atPath: source.path)) ?? []
    for name in names where name != "model" && name != AIConversionDebugLog.fileName {
      var isDirectory: ObjCBool = false
      let from = source.appending(path: name)
      guard FileManager.default.fileExists(atPath: from.path, isDirectory: &isDirectory), !isDirectory.boolValue
      else { continue }
      let to = profile.appending(path: name)
      try? FileManager.default.removeItem(at: to)
      do {
        try FileManager.default.copyItem(at: from, to: to)
        // .encrypt_key.db is read-only (0400); the copy must be writable like the original's owner.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: to.path)
      } catch {
        fail("cannot copy \(from.path): \(error)")
      }
    }
    print("profile: copy of \(source.path) (\(names.filter { $0 != "model" }.sorted().joined(separator: ", ")))")
  }
  SystemUtil.setUserProfileDirectory(profile.path)

  let plain = SessionHandlerBackend()
  guard plain.isAvailable else {
    fail("the Genmai engine is not available: \(String(describing: plain.loadError))")
  }
  var settings = AIConversionSettings(
    enabled: true, timeoutMilliseconds: timeout, candidateCount: candidates, readingCheck: readingCheck,
    dictionaryWeight: dictionaryWeight, dictionaryProposalWeight: proposalWeight,
    debugLog: debugLog)
  if let model {
    settings.modelDirectory = model
  } else if let e = ProcessInfo.processInfo.environment["GENMAI_MODEL_DIR"] {
    settings.modelDirectory = e
  }
  let hook = AIConversionHook.makeGenmai(settings: settings)
  let loadStart = Date()
  await hook.genmai?.waitUntilLoaded()
  guard hook.augmenter.status == .ready else {
    fail("the AI model is not available: \(hook.augmenter.status) (\(settings.resolvedModelDirectory.path))")
  }
  print(
    String(
      format: "AI model %@ ready in %.2f s; timeout %d ms, %d candidates, %@", settings.resolvedModelDirectory.path,
      Date().timeIntervalSince(loadStart), settings.timeoutMilliseconds, settings.candidateCount,
      "settle \(settle.rawValue)"))
  let ai = SessionHandlerBackend(aiHook: hook)
  await hook.waitForReadingCheck()
  print(
    "reading check \(readingCheck ? "on" : "off"), dictionary weight \(dictionaryWeight), proposals \(proposalWeight)")

  for path in args {
    var items = (try? loadSet(path)) ?? []
    if let limit { items = Array(items.prefix(limit)) }
    let name = URL(filePath: path).deletingPathExtension().lastPathComponent
    var runs: [(String, SessionHandlerBackend, AIConversionHook?, Int?)] = [("plain", plain, nil, nil)]
    if typingIntervals.isEmpty {
      runs.append(("ai", ai, hook, nil))
    } else {
      runs += typingIntervals.map { ("ai-typing\($0)", ai, hook, $0) }
    }
    for (mode, backend, h, typing) in runs {
      let runner = SessionEvalRunner(
        backend: backend, hook: h, settle: settle, typingInterval: typing.map { .milliseconds($0) },
        spaceDelay: .milliseconds(spaceDelay), trace: trace)
      var sources: [GenmaiAugmenter.ConvertSource: Int] = [:]
      var busyTyping = 0.0
      var busyConversion = 0.0
      var keyCount = 0
      var strict = 0
      var normalized = 0
      var preeditMismatch = 0
      var timedOut = 0
      var aiErrors = 0
      var replaced = 0
      var rawCorrect = 0
      var rawCorrectLost: [String] = []
      var candidates = 0
      var unreadable = 0
      var unreadableCorrect: [String] = []
      var latencies: [Double] = []
      var errors: [String] = []
      var outputs: [[String: Any]] = []
      let start = Date()
      for item in items {
        if trace { print("[\(mode)] \(item.query)  context: \(item.context.suffix(40))") }
        let r = await runner.run(item)
        if typing != nil { await runner.drain() }
        latencies.append(r.latency)
        if let src = r.source { sources[src, default: 0] += 1 }
        busyTyping += r.busyTyping
        busyConversion += r.busyConversion
        keyCount += r.keys
        if r.preedit != item.query { preeditMismatch += 1 }
        let s = item.answers.contains(r.top)
        let n = Set(item.answers.map(scoreNorm)).contains(scoreNorm(r.top))
        strict += s ? 1 : 0
        normalized += n ? 1 : 0
        if let rec = r.record {
          if rec.timedOut { timedOut += 1 }
          if rec.error != nil { aiErrors += 1 }
          if rec.outcome.replacedTop { replaced += 1 }
          candidates += rec.texts.count + rec.unreadable.count
          unreadable += rec.unreadable.count
          let answers = Set(item.answers.map(scoreNorm))
          unreadableCorrect += rec.unreadable.filter { answers.contains(scoreNorm($0)) }.map {
            "   dropped \($0) / \(item.query)"
          }
          if let raw = rec.texts.first, Set(item.answers.map(scoreNorm)).contains(scoreNorm(raw)) {
            rawCorrect += 1
            if !n { rawCorrectLost.append("   AI \(raw) -> session \(r.top)") }
          }
        }
        if !n {
          errors.append("   正解:\(item.answers[0])\n   出力:\(r.top)")
        }
        outputs.append([
          "query": item.query, "answers": item.answers, "left_context": item.context,
          "outputs": [["text": r.top]], "latency_ms": r.latency,
          "ai_texts": r.record?.texts ?? [], "ai_unreadable": r.record?.unreadable ?? [],
          "ai_timed_out": r.record?.timedOut ?? false,
          "ai_source": r.source?.rawValue ?? "", "busy_typing_ms": r.busyTyping, "busy_space_ms": r.busyConversion,
        ])
      }
      let total = Date().timeIntervalSince(start)
      let count = max(items.count, 1)
      print(
        String(
          format:
            "%@ [%@]: strict %d/%d (%.1f%%)  norm %d/%d (%.1f%%)  conversion key: median %.1f ms, p90 %.1f, max %.1f",
          name, mode, strict, items.count, Double(strict) / Double(count) * 100, normalized, items.count,
          Double(normalized) / Double(count) * 100, median(latencies), percentile(latencies, 0.9),
          latencies.max() ?? 0))
      if mode.hasPrefix("ai") {
        print(
          "   AI top used \(replaced), timed out \(timedOut), errors \(aiErrors); raw genmai top-1 correct (norm) \(rawCorrect), of which lost in the session \(rawCorrectLost.count)"
        )
        if showErrors {
          for line in rawCorrectLost { print(line) }
        }
        if readingCheck {
          print(
            "   reading check: dropped \(unreadable) of \(candidates) AI candidates, \(unreadableCorrect.count) of them correct"
          )
          for line in unreadableCorrect { print(line) }
        }
        let n = Double(count)
        print(
          String(
            format:
              "   result at SPACE: ready %d (%.1f%%), awaited %d, converted %d, not ready %d; model busy per key while typing %.1f ms (%.1f s total), per SPACE %.1f ms",
            sources[.ready] ?? 0, Double(sources[.ready] ?? 0) / n * 100, sources[.awaited] ?? 0,
            sources[.converted] ?? 0, sources[.notReady] ?? 0, busyTyping / Double(max(keyCount, 1)), busyTyping / 1000,
            busyConversion / n))
      }
      if preeditMismatch > 0 {
        print("   warning: \(preeditMismatch) items' preedit differs from the reading")
      }
      if mode.hasPrefix("ai") {
        let f = physicalFootprintMB()
        print(String(format: "   process footprint %.0f MB (peak %.0f MB)", f.current, f.peak))
      }
      if showErrors {
        for line in errors { print(line) }
      }
      if let outDir {
        let doc: [String: Any] = ["items": outputs, "n_best": 1, "execution_time": total]
        let url = URL(filePath: outDir).appending(path: "session_\(mode)_\(name).json")
        try? FileManager.default.createDirectory(at: URL(filePath: outDir), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted]) {
          try? data.write(to: url)
        }
      }
    }
  }
  if debugLog,
    let log = try? String(contentsOf: profile.appending(path: AIConversionDebugLog.fileName), encoding: .utf8)
  {
    print("--- ai_debug.log")
    print(log, terminator: "")
  }
}
