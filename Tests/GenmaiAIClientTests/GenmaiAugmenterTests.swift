// Model-backed tests of the genmai augmenter and of AI conversion in the real session layer.
// Skipped when the genmai model (GENMAI_MODEL_DIR or the IME's default directory)
// or Data/genmai.data is missing.

import Foundation
import GenmaiAI
import GenmaiBase
import GenmaiClient
import GenmaiCore
import GenmaiProtocol
import Testing

@testable import GenmaiAIClient

enum ModelPaths {
  static let repoRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
  static let modelDirectory: URL? = {
    var dirs: [URL] = []
    if let e = ProcessInfo.processInfo.environment["GENMAI_MODEL_DIR"] { dirs.append(URL(filePath: e)) }
    dirs.append(AIConversionSettings.defaultModelDirectory)
    return dirs.first { AIModelStatus.check($0).isFound }
  }()
  static var modelAvailable: Bool { modelDirectory != nil }
  static var ossDataAvailable: Bool { FileManager.default.fileExists(atPath: OssDataManager.defaultDataPath) }
}

/// One loaded augmenter shared by the tests (the model is 0.6-1.2 GB).
enum SharedAugmenter {
  static let settings = AIConversionSettings(
    enabled: true, timeoutMilliseconds: 5000, modelDirectory: ModelPaths.modelDirectory?.path)
  static let augmenter: GenmaiAugmenter = {
    let a = GenmaiAugmenter()
    a.configure(settings)
    return a
  }()
}

@Suite(.serialized, .enabled(if: ModelPaths.modelAvailable, "the genmai model is missing"))
struct GenmaiAugmenterTests {
  @Test func loadsAndConverts() async throws {
    let a = SharedAugmenter.augmenter
    await a.waitUntilLoaded()
    #expect(a.status == .ready)
    let texts = try await a.convert(reading: "きょうははやめにかえります", context: "", maxResults: 3)
    #expect(texts.first == "今日は早めに帰ります")
    #expect(texts.count <= 3)
    #expect(Set(texts).count == texts.count)
  }

  @Test func preparedAndSpeculativeResultsEqualADirectConversion() async throws {
    let a = SharedAugmenter.augmenter
    await a.waitUntilLoaded()
    let reading = "だんせいせいねんしにおけるだんせいゆういのせいいしき、そしてじょせいのしてんからみたひょうげん"
    let context = "青年誌で描くことが多いが、"
    let converter = try GenmaiConverter(directory: try #require(ModelPaths.modelDirectory))
    let direct = try await converter.convert(reading, context: context).map(\.text)
    // Typing: every prefix is prepared; the last one is converted speculatively after the pause.
    for n in stride(from: 4, through: reading.count, by: 4) {
      a.prepare(reading: String(reading.prefix(n)), context: context)
    }
    a.prepare(reading: reading, context: context)
    await a.waitForPreparation(speculation: true)
    let start = ContinuousClock.now
    let texts = try await a.convert(reading: reading, context: context, maxResults: 5)
    #expect(ContinuousClock.now - start < .milliseconds(50))  // cached
    #expect(texts == Array(direct.prefix(5)))
  }

  /// `resultUpdate` (the suggestion window refresh): a task while the speculation of the reading is in flight
  /// that reports the new result; after the exact refinement nothing is in flight any more.
  @Test func resultUpdateFollowsTheSpeculation() async throws {
    let a = SharedAugmenter.augmenter
    await a.waitUntilLoaded()
    let reading = "はしをわたりはじめた"
    let context = "resultUpdate"
    #expect(a.resultUpdate(reading: reading, context: context) == nil)
    a.prepare(reading: reading, context: context)
    let update = try #require(a.resultUpdate(reading: reading, context: context))
    #expect(await update.value)
    #expect(a.readyResult(reading: reading, context: context, maxResults: 1) != nil)
    #expect(a.resultInfo(reading: reading, context: context)?.exact == false)
    #expect(a.resultUpdate(reading: "べつのよみ", context: context) == nil)
    // the refinement after the pause; awaited before the test ends (MLX work at exit crashes Metal)
    await a.waitForPreparation(speculation: true)
    #expect(a.resultInfo(reading: reading, context: context)?.exact == true)
    #expect(a.resultUpdate(reading: reading, context: context) == nil)
  }

  /// Speculation on every keystroke: each `prepare` cancels the previous speculative conversion (latest wins),
  /// so a burst of keystrokes costs about one conversion, and the last one's result is ready at the conversion
  /// key (identical to a direct conversion).
  @Test func speculationLatestWins() async throws {
    let a = SharedAugmenter.augmenter
    await a.waitUntilLoaded()
    let reading = "あしたのかいぎはごごさんじからにへんこうになりました"
    let context = "連絡です。"
    let converter = try GenmaiConverter(directory: try #require(ModelPaths.modelDirectory))
    let t0 = ContinuousClock.now
    let direct = try await converter.convert(reading, context: context).map(\.text)
    let single = ContinuousClock.now - t0
    let busy0 = GenmaiConverter.busyStats.seconds
    let u = Array(reading.unicodeScalars)
    for n in 1...u.count {
      a.prepare(reading: String(String.UnicodeScalarView(u[..<n])), context: context)
    }
    await a.waitForPreparation(speculation: true)
    let busy = GenmaiConverter.busyStats.seconds - busy0
    let texts = try await a.convert(reading: reading, context: context, maxResults: 5)
    #expect(a.lastConvertSource == .ready)
    #expect(texts == Array(direct.prefix(5)))
    // 26 speculations were started; the stale ones stopped before (or within one step of) their work
    let (s, at) = single.components
    let singleSeconds = Double(s) + Double(at) / 1e18
    #expect(
      busy < singleSeconds * 4 + 0.2, "busy \(busy) s for \(u.count) keystrokes, one conversion \(singleSeconds) s")
  }

  /// The conversion key right after the last keystroke awaits the speculation already in flight for it.
  @Test func conversionKeyAwaitsTheSpeculationInFlight() async throws {
    let a = SharedAugmenter.augmenter
    await a.waitUntilLoaded()
    let reading = "らいしゅうのしゅっちょうのよていをおしえてください"
    a.prepare(reading: reading, context: "")
    let texts = try await a.convert(reading: reading, context: "", maxResults: 5)
    #expect(a.lastConvertSource == .awaited)
    #expect(texts.first == "来週の出張の予定を教えてください")
    // now cached
    #expect(try await a.convert(reading: reading, context: "", maxResults: 5) == texts)
    #expect(a.lastConvertSource == .ready)
    // let the delayed refine finish: MLX work still running at process exit crashes Metal
    await a.waitForPreparation(speculation: true)
  }

  @Test func cancelledConversionDoesNotHang() async throws {
    let a = SharedAugmenter.augmenter
    await a.waitUntilLoaded()
    let task = Task.detached {
      try await a.convert(reading: String(repeating: "あいうえおかきくけこ", count: 8), context: "", maxResults: 5)
    }
    task.cancel()
    _ = await task.result
    // The augmenter still works afterwards.
    let texts = try await a.convert(reading: "にほんごにゅうりょく", context: "", maxResults: 1)
    #expect(texts == ["日本語入力"])
  }

  @Test func disablingReleasesTheModel() async throws {
    let a = GenmaiAugmenter()
    a.configure(SharedAugmenter.settings)
    #expect(a.status == .loading)
    a.configure(AIConversionSettings(enabled: false))
    #expect(a.status == .disabled)
    await a.waitUntilLoaded()
    #expect(a.status == .disabled)
    await #expect(throws: (any Error).self) {
      _ = try await a.convert(reading: "あ", context: "", maxResults: 1)
    }
  }

  @Test func missingModelFails() async {
    let a = GenmaiAugmenter()
    a.configure(AIConversionSettings(enabled: true, modelDirectory: "/nonexistent/genmai"))
    await a.waitUntilLoaded()
    if case .failed = a.status {
    } else {
      Issue.record("expected .failed, got \(a.status)")
    }
  }
}

@MainActor
func sendRomaji(_ client: InProcessClient, _ romaji: String) {
  for c in romaji.unicodeScalars {
    var key = KeyEvent()
    key.keyCode = c.value
    key.mode = .hiragana
    _ = client.sendKey(key)
  }
}

@MainActor
func sendSpecial(_ client: InProcessClient, _ special: KeyEvent.SpecialKey) -> Output? {
  var key = KeyEvent()
  key.specialKey = special
  return client.sendKey(key)
}

extension GenmaiAugmenterTests {
  @MainActor
  @Test(.enabled(if: ModelPaths.ossDataAvailable, "Data/genmai.data is missing"))
  func aiConversionInTheSessionLayer() async throws {
    await SharedAugmenter.augmenter.waitUntilLoaded()
    await SystemUtil.withTempUserProfile { _ in
      await ConfigHandler.withScopedHandlerForTesting {
        await CharacterFormManager.withScopedManagerForTesting {
          let hook = AIConversionHook(augmenter: SharedAugmenter.augmenter, settings: SharedAugmenter.settings)
          let backend = SessionHandlerBackend(aiHook: hook)
          let client = InProcessClient.make(backend: backend)
          var on = KeyEvent()
          on.specialKey = .on
          on.mode = .hiragana
          _ = client.sendKey(on)

          var space = KeyEvent()
          space.specialKey = .space
          sendRomaji(client, "hashiwowatarihajimeta")
          // like the input controller: the result in flight is awaited before SPACE is evaluated
          let converted = await hook.sendKey(space, via: client)
          #expect(converted?.preedit.segment.map(\.value).joined() == "橋を渡り始めた")
          #expect(hook.lastConversion?.texts.first == "橋を渡り始めた")
          #expect(sendSpecial(client, .enter)?.result.value == "橋を渡り始めた")

          // Symbols: the model reads the preedit form and Mozc's character form applies to its output.
          sendRomaji(client, "imadokoniiruno?")
          let question = await hook.sendKey(space, via: client)
          #expect(question?.preedit.segment.map(\.value).joined() == "今どこにいるの？")
          _ = sendSpecial(client, .escape)
          _ = sendSpecial(client, .escape)

          // Without AI: plain Mozc (the shared augmenter stays enabled for the other tests).
          let plain = InProcessClient.make(backend: SessionHandlerBackend())
          _ = plain.sendKey(on)
          sendRomaji(plain, "kisyanokisyagakisyadekisyasita")
          #expect(sendSpecial(plain, .space)?.preedit.segment.map(\.value).joined() == "記者の記者が記者で帰社した")
          await SharedAugmenter.augmenter.waitForPreparation(speculation: true)
        }
      }
    }
  }
}
