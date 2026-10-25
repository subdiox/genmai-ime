// Tests of the AI conversion hook (not a port of a C++ test): reading alignment, merging into Mozc segments,
// settings persistence, and the hook inside the real session layer with a fake augmenter (ordering, fallback on
// timeout / error / not ready, AI off == Mozc, context, background preparation, learning).

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import GenmaiSession
import Synchronization
import Testing

@testable import GenmaiClient

// MARK: - Fakes

final class FakeAugmenter: ConversionAugmenter, Sendable {
  struct State {
    var status: AIConversionStatus = .ready
    var settings = AIConversionSettings()
    var prepared: [(reading: String, context: String)] = []
    var converted: [(reading: String, context: String)] = []
    var results: [String: [String]] = [:]
    var background: [String: Task<Bool, Never>] = [:]
  }
  let lock = Mutex(State())
  let respond: @Sendable (String, String) async throws -> [String]

  init(_ respond: @escaping @Sendable (String, String) async throws -> [String]) {
    self.respond = respond
  }

  convenience init(_ table: [String: [String]]) {
    self.init { reading, _ in table[reading] ?? [] }
  }

  var prepared: [(reading: String, context: String)] { lock.withLock { $0.prepared } }
  var converted: [(reading: String, context: String)] { lock.withLock { $0.converted } }

  func setStatus(_ status: AIConversionStatus) { lock.withLock { $0.status = status } }

  func configure(_ settings: AIConversionSettings) { lock.withLock { $0.settings = settings } }
  var status: AIConversionStatus { lock.withLock { $0.status } }
  func prepare(reading: String, context: String) {
    lock.withLock { $0.prepared.append((reading, context)) }
  }
  func convert(reading: String, context: String, maxResults: Int) async throws -> [String] {
    lock.withLock { $0.converted.append((reading, context)) }
    let texts = try await respond(reading, context)
    lock.withLock { $0.results[reading + "\u{0}" + context] = texts }
    return Array(texts.prefix(maxResults))
  }
  func readyResult(reading: String, context: String, maxResults: Int) -> [String]? {
    lock.withLock { $0.results[reading + "\u{0}" + context] }.map { Array($0.prefix(maxResults)) }
  }
  /// Background work registered with `startBackground` (the speculation of a real augmenter).
  func resultUpdate(reading: String, context: String) -> Task<Bool, Never>? {
    lock.withLock { $0.background[reading + "\u{0}" + context] }
  }
  func resultInfo(reading: String, context: String) -> AIResultInfo? {
    readyResult(reading: reading, context: context, maxResults: 1) == nil
      ? nil : AIResultInfo(latency: .milliseconds(1), exact: false)
  }
  func setDictionaryAdvice(_ advice: AIDictionaryAdvice?) {}

  /// Simulates a speculation in flight: `resultUpdate` returns a task that stores `texts` (as ready) when
  /// `release()` is called.
  func startBackground(reading: String, context: String, texts: [String]) -> @Sendable () -> Void {
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    let key = reading + "\u{0}" + context
    let task = Task.detached { [weak self] () -> Bool in
      for await _ in stream { break }
      self?.lock.withLock {
        $0.results[key] = texts
        $0.background[key] = nil
      }
      return true
    }
    lock.withLock { $0.background[key] = task }
    return {
      continuation.yield()
      continuation.finish()
    }
  }
}

struct FakeError: Error {}

/// A converter double for the merger: `resizeSegments` re-segments and "converts" every new segment to its
/// key (plus a katakana candidate), like Mozc's re-conversion.
/// `@unchecked Sendable`: a test double with mutable handlers / records, set and used on the test's own task only.
final class ResizingConverterStub: ConverterInterface, @unchecked Sendable {
  var resizeCalls: [[UInt8]] = []

  func startConversion(_ request: ConversionRequest, _ segments: Segments) -> Bool { false }
  func startReverseConversion(_ segments: Segments, _ key: String) -> Bool { false }
  func startPrediction(_ request: ConversionRequest, _ segments: Segments) -> Bool { false }
  func startPredictionWithPreviousSuggestion(
    _ request: ConversionRequest, _ previousSegment: Segment, _ segments: Segments
  ) -> Bool { false }
  func prependCandidates(_ request: ConversionRequest, _ segment: Segment, _ segments: Segments) {}
  func finishConversion(_ request: ConversionRequest, _ segments: Segments) {}
  func cancelConversion(_ segments: Segments) {}
  func resetConversion(_ segments: Segments) {}
  func revertConversion(_ segments: Segments) {}
  func deleteCandidateFromHistory(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int) -> Bool {
    false
  }
  func reconstructHistory(_ segments: Segments, _ precedingText: String) -> Bool { false }
  func commitSegmentValue(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int) -> Bool { false }
  func commitPartialSuggestionSegmentValue(
    _ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int, _ currentSegmentKey: String,
    _ newSegmentKey: String
  ) -> Bool { false }
  func focusSegmentValue(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int) -> Bool { false }
  func commitSegments(_ segments: Segments, _ candidateIndex: [Int]) -> Bool { false }
  func resizeSegment(
    _ segments: Segments, _ request: ConversionRequest, _ segmentIndex: Int, _ offsetLength: Int
  ) -> Bool { false }
  func resizeSegments(
    _ segments: Segments, _ request: ConversionRequest, _ startSegmentIndex: Int, _ newSizeArray: [UInt8]
  ) -> Bool {
    resizeCalls.append(newSizeArray)
    guard segments.resize(startSegmentIndex, newSizeArray) else { return false }
    for i in 0..<segments.conversionSegmentsSize {
      let segment = segments.mutableConversionSegment(i)
      segment.clearCandidates()
      let c = segment.addCandidate()
      c.key = segment.key
      c.value = segment.key
      c.contentKey = segment.key
      c.contentValue = segment.key
    }
    return true
  }
  func commitContext(_ request: ConversionRequest) {}
}

/// Segments with the given (key, [candidate values]) conversion segments.
func makeSegments(_ spec: [(String, [String])]) -> Segments {
  let segments = Segments()
  for (key, values) in spec {
    let segment = segments.addSegment()
    segment.setKey(key)
    for v in values {
      let c = segment.addCandidate()
      c.key = key
      c.value = v
      c.contentKey = key
      c.contentValue = v
      c.lid = 10
      c.rid = 20
    }
  }
  return segments
}

func tops(_ segments: Segments) -> [String] {
  (0..<segments.conversionSegmentsSize).map { segments.conversionSegment($0).candidate(0).value }
}

func conversionRequest() -> ConversionRequest {
  ConversionRequestBuilder().setRequestType(.conversion).build()
}

// MARK: - Alignment

@Suite struct AIConversionAlignerTests {
  @Test func alignsKanaAnchors() throws {
    let groups = try #require(
      AIConversionAligner.plan(surface: "今日は早めに帰ります", segmentKeys: ["きょうは", "はやめに", "かえります"]))
    #expect(groups.map(\.text) == ["今日は", "早めに", "帰ります"])
    #expect(groups.map(\.segments) == [0..<1, 1..<2, 2..<3])
  }

  @Test func mergesSegmentsWhoseBoundaryFallsInsideAKanjiRun() throws {
    // Mozc: とうきょう|とに|いく; the AI writes 東京都 as one kanji run.
    let groups = try #require(
      AIConversionAligner.plan(surface: "東京都に行く", segmentKeys: ["とうきょう", "とに", "いく"]))
    #expect(groups.map(\.text) == ["東京都に", "行く"])
    #expect(groups.map(\.segments) == [0..<2, 2..<3])
  }

  @Test func katakanaAndPunctuationMatchTheReading() throws {
    let groups = try #require(
      AIConversionAligner.plan(surface: "コンピューターを、使う！", segmentKeys: ["こんぴゅーたーを、", "つかう!"]))
    #expect(groups.map(\.text) == ["コンピューターを、", "使う！"])
  }

  @Test func digitsAndLettersReadAsFreeRuns() throws {
    let groups = try #require(
      AIConversionAligner.plan(surface: "3時にMTG", segmentKeys: ["さんじに", "みーてぃんぐ"]))
    #expect(groups.map(\.text) == ["3時に", "MTG"])
  }

  @Test func unalignableTextReturnsNil() {
    #expect(AIConversionAligner.plan(surface: "こんにちは", segmentKeys: ["さよう", "なら"]) == nil)
    #expect(AIConversionAligner.align(surface: "", reading: "あ") == nil)
  }

  @Test func ambiguousBoundariesAreNotResolved() throws {
    // 日本 / 日本 around は: the kana anchor is unique, but the boundary between two adjacent kanji runs is not.
    let b = try #require(AIConversionAligner.align(surface: "日本酒", reading: "にほんしゅ"))
    #expect(b == [0: 0, 5: 3])
    #expect(AIConversionAligner.split(surface: "日本酒", readingLengths: [3, 2], reading: "にほんしゅ") == nil)
    #expect(
      AIConversionAligner.split(surface: "日本の酒", readingLengths: [4, 2], reading: "にほんのさけ") == ["日本の", "酒"])
  }
}

// MARK: - Merging

@Suite struct AIConversionMergerTests {
  @Test func putsTheAITopFirstAndMarksIt() {
    let segments = makeSegments([("はしを", ["箸を", "橋を"]), ("わたりはじめた", ["わたり始めた", "渡り始めた"])])
    let outcome = AIConversionMerger.apply(
      ["橋を渡り始めた"], to: segments, request: conversionRequest(), converter: ResizingConverterStub(),
      maxCandidates: 5)
    #expect(outcome.replacedTop)
    #expect(!outcome.resized)
    #expect(tops(segments) == ["橋を", "渡り始めた"])
    #expect(outcome.aiSegments.map(\.value) == ["橋を", "渡り始めた"])
    // Committing the AI's choice teaches Mozc like a user reranking.
    #expect(segments.conversionSegment(0).candidate(0).attributes & Attribute.reranked != 0)
    #expect(segments.conversionSegment(0).candidate(0).description == "AI")
    // Mozc's former tops stay reachable.
    #expect(segments.conversionSegment(0).candidate(1).value == "箸を")
    #expect(segments.conversionSegment(1).candidate(1).value == "わたり始めた")
  }

  /// The user history keeps the description of what is committed: the AI mark must not be learned.
  @Test func unmarkRemovesOnlyTheAIMark() {
    let segments = makeSegments([("はし", ["橋", "箸", "端"])])
    let segment = segments.mutableConversionSegment(0)
    segment.mutableCandidate(0).description = "AI"
    segment.mutableCandidate(1).description = "AI 食器"
    segment.mutableCandidate(2).description = "AIの説明"
    AIConversionMerger.unmarkAI(segments)
    #expect((0..<3).map { segment.candidate($0).description } == ["", "食器", "AIの説明"])
  }

  @Test func sameTopAddsOnlyAlternatives() {
    let segments = makeSegments([("きしゃの", ["記者の"]), ("きしゃ", ["記者", "貴社"])])
    let outcome = AIConversionMerger.apply(
      ["記者の記者", "記者の貴社", "記者の記者", "汽車の記者"], to: segments, request: conversionRequest(),
      converter: ResizingConverterStub(), maxCandidates: 5)
    #expect(!outcome.replacedTop)
    #expect(tops(segments) == ["記者の", "記者"])
    #expect(segments.conversionSegment(1).candidate(1).value == "貴社")
    #expect(segments.conversionSegment(1).candidate(1).description == "AI")
    #expect(segments.conversionSegment(0).candidate(1).value == "汽車の")
    #expect(segments.conversionSegment(0).candidate(1).description == "AI")
    #expect(outcome.alternatives == 2)
  }

  @Test func alternativesRespectTheCandidateLimit() {
    let segments = makeSegments([("きしゃ", ["記者"])])
    AIConversionMerger.apply(
      ["汽車", "貴社", "帰社", "喜捨"], to: segments, request: conversionRequest(),
      converter: ResizingConverterStub(), maxCandidates: 2)
    let values = (0..<segments.conversionSegment(0).candidatesSize).map {
      segments.conversionSegment(0).candidate($0).value
    }
    #expect(values == ["汽車", "貴社", "記者"])
  }

  @Test func newCandidatesReusePOSOfAMatchingGenmaiCandidate() {
    let segments = makeSegments([("きょうは", [])])
    let c = segments.mutableConversionSegment(0).addCandidate()
    c.key = "きょうは"
    c.value = "京は"
    c.contentKey = "きょう"
    c.contentValue = "京"
    c.lid = 1851
    c.rid = 261
    AIConversionMerger.apply(
      ["今日は"], to: segments, request: conversionRequest(), converter: ResizingConverterStub(), maxCandidates: 5)
    let top = segments.conversionSegment(0).candidate(0)
    #expect(top.value == "今日は")
    #expect(top.contentValue == "今日")
    #expect(top.contentKey == "きょう")
    #expect(top.lid == 1851 && top.rid == 261)
  }

  @Test func mergesSegmentsWithoutLearningTheBoundary() {
    let segments = makeSegments([("とうきょう", ["東京"]), ("とに", ["とに"]), ("いく", ["行く"])])
    let converter = ResizingConverterStub()
    let outcome = AIConversionMerger.apply(
      ["東京都に行く"], to: segments, request: conversionRequest(), converter: converter, maxCandidates: 5)
    #expect(outcome.resized)
    #expect(converter.resizeCalls == [[7, 2]])
    #expect(tops(segments) == ["東京都に", "行く"])
    #expect(segments.conversionSegment(0).candidate(1).value == "とうきょうとに")  // Mozc's re-conversion
    #expect(!segments.resized)
  }

  @Test func unalignableTextBecomesOneSegment() {
    // も does not match the reading's は: the AI text cannot be cut into Mozc's segments.
    let segments = makeSegments([("きょうは", ["今日は"]), ("はれ", ["晴れ"])])
    let outcome = AIConversionMerger.apply(
      ["今日も晴れ"], to: segments, request: conversionRequest(), converter: ResizingConverterStub(),
      maxCandidates: 5)
    #expect(outcome.wholeSentence)
    #expect(tops(segments) == ["今日も晴れ"])
    #expect(segments.conversionSegmentsSize == 1)
  }

  @Test func aiWinsOverLearnedSegments() {
    let segments = makeSegments([("はしを", ["箸を", "橋を"]), ("わたる", ["渡る"])])
    segments.mutableConversionSegment(0).mutableCandidate(0).attributes |= Attribute.userSegmentHistoryRewriter
    let outcome = AIConversionMerger.apply(
      ["橋を渡る", "箸を渡る"], to: segments, request: conversionRequest(), converter: ResizingConverterStub(),
      maxCandidates: 5)
    #expect(outcome.keptLearned == 0)
    #expect(tops(segments) == ["橋を", "渡る"])
    // The learned top stays right below the AI's.
    #expect(segments.conversionSegment(0).candidate(1).value == "箸を")
  }

  @Test func rejectedAITextsDoNotOverrideGenmai() {
    let segments = makeSegments([("はしを", ["箸を", "橋を"]), ("わたる", ["渡る"])])
    let outcome = AIConversionMerger.apply(
      ["橋を渡る"], to: segments, request: conversionRequest(), converter: ResizingConverterStub(),
      maxCandidates: 5, rejected: { $0 == AIConversionMerger.Piece(key: "はしを", value: "橋を") })
    #expect(outcome.keptLearned == 1)
    #expect(outcome.aiSegments.isEmpty)
    #expect(tops(segments) == ["箸を", "渡る"])
  }

  @Test func userDictionaryWordsWinOverAI() {
    // はるきが registered as 陽稀; the AI writes the common 春樹.
    let segments = makeSegments([("はるきが", ["陽稀が", "春樹が"]), ("きた", ["来た"])])
    let user = segments.mutableConversionSegment(0).mutableCandidate(0)
    user.attributes |= Attribute.userDictionary
    user.contentValue = "陽稀"
    let outcome = AIConversionMerger.apply(
      ["春樹が来た"], to: segments, request: conversionRequest(), converter: ResizingConverterStub(),
      maxCandidates: 5)
    #expect(outcome.keptUserWords == 1)
    #expect(outcome.aiSegments.isEmpty)
    #expect(tops(segments) == ["陽稀が", "来た"])

    // An AI text with the user's word is used.
    let kept = makeSegments([("はるきが", ["陽稀が"]), ("きた", ["着た", "来た"])])
    let word = kept.mutableConversionSegment(0).mutableCandidate(0)
    word.attributes |= Attribute.userDictionary
    word.contentValue = "陽稀"
    let used = AIConversionMerger.apply(
      ["陽稀が来た"], to: kept, request: conversionRequest(), converter: ResizingConverterStub(), maxCandidates: 5)
    #expect(used.keptUserWords == 0)
    #expect(tops(kept) == ["陽稀が", "来た"])
  }

  @Test func dictionaryWordsWinOverInventedSpellings() {
    let segments = makeSegments([("くさかべちょうに", ["日下部町に", "草壁町に"]), ("いく", ["行く"])])
    var asked: [(AIConversionMerger.Piece, String)] = []
    let outcome = AIConversionMerger.apply(
      ["草壁町に行く"], to: segments, request: conversionRequest(), converter: ResizingConverterStub(),
      maxCandidates: 5,
      keepsDictionaryWord: { engine, ai, tops in
        asked.append((engine, ai))
        return tops.first?.value == "日下部町に"
      })
    #expect(outcome.keptDictionaryWords == 1)
    #expect(asked.first?.0 == AIConversionMerger.Piece(key: "くさかべちょうに", value: "日下部町に"))
    #expect(tops(segments) == ["日下部町に", "行く"])
  }

  /// The hook's rule: Mozc's proper noun stays where the AI wrote its reading in kana.
  @Test(.enabled(if: FileManager.default.fileExists(atPath: OssDataManager.defaultDataPath)))
  func kanaSpelledNamesKeepTheDictionaryWord() async throws {
    let hook = AIConversionHook(augmenter: FakeAugmenter([:]), settings: AIConversionSettings(enabled: true))
    hook.attachReadingCheckData(try OssDataManager.create())
    await hook.waitForReadingCheck()
    let rule = hook.dictionaryWordRule(hook.settings)
    let dataManager = try OssDataManager.create()
    let posMatcher = PosMatcher(dataManager.getPosMatcherData())
    let noun = Candidate()
    noun.value = "日下部町に"
    noun.lid = posMatcher.getUniqueNounId()
    let piece = AIConversionMerger.Piece(key: "くさかべちょうに", value: "日下部町に")
    #expect(rule(piece, "クサカベチョウに", [noun]))
    #expect(rule(piece, "くさかべちょうに", [noun]))
    // other kana: not this rule
    #expect(!rule(piece, "クサカベマチに", [noun]))
    // not a proper noun
    noun.lid = 0
    #expect(!rule(piece, "クサカベチョウに", [noun]))
  }

  @Test func userDictionaryWordIsPromotedWhenMozcRanksItLower() {
    let segments = makeSegments([("はるきが", ["春樹が", "陽稀が"]), ("きた", ["来た"])])
    let user = segments.mutableConversionSegment(0).mutableCandidate(1)
    user.attributes |= Attribute.userDictionary
    user.contentValue = "陽稀"
    let outcome = AIConversionMerger.apply(
      ["晴樹が来た"], to: segments, request: conversionRequest(), converter: ResizingConverterStub(),
      maxCandidates: 5)
    #expect(outcome.keptUserWords == 1)
    #expect(tops(segments) == ["陽稀が", "来た"])
  }

  @Test func multiSegmentCandidatesAreLeftAlone() {
    let segments = makeSegments([("わたしの", ["私の"]), ("なまえ", ["名前"])])
    segments.mutableConversionSegment(0).mutableCandidate(0).convertedSegmentCount = 2
    let outcome = AIConversionMerger.apply(
      ["渡しの名前"], to: segments, request: conversionRequest(), converter: ResizingConverterStub(),
      maxCandidates: 5)
    #expect(outcome == AIConversionMerger.Outcome())
    #expect(tops(segments) == ["私の", "名前"])
  }
}

// MARK: - Settings

@Suite struct AIConversionSettingsTests {
  @Test func roundTripsThroughTheProfileFile() throws {
    try SystemUtil.withTempUserProfile { dir in
      #expect(AIConversionSettings.fileURL.path == URL(filePath: dir).appending(path: "ai_conversion.json").path)
      #expect(AIConversionSettings.load() == AIConversionSettings())
      let s = AIConversionSettings(enabled: true, timeoutMilliseconds: 500, candidateCount: 3, modelDirectory: "/m")
      try s.save()
      #expect(AIConversionSettings.load() == s)
      let json = try String(contentsOf: AIConversionSettings.fileURL, encoding: .utf8)
      #expect(json.contains("\"timeout_ms\" : 500"))
    }
  }

  @Test func defaultsAndSanitizing() throws {
    let d = AIConversionSettings()
    #expect(!d.enabled)
    #expect(d.timeoutMilliseconds == 300)
    #expect(d.candidateCount == 5)
    #expect(d.resolvedModelDirectory == AIConversionSettings.defaultModelDirectory)
    let decoded = try JSONDecoder().decode(
      AIConversionSettings.self,
      from: Data(#"{"enabled": true, "timeout_ms": 1, "future": 3, "model_directory": ""}"#.utf8))
    #expect(decoded.enabled)
    #expect(decoded.modelDirectory == nil)
    #expect(decoded.sanitized.timeoutMilliseconds == AIConversionSettings.timeoutRange.lowerBound)
    #expect(decoded.candidateCount == 5)
    #expect(decoded.readingCheck)
    let off = try JSONDecoder().decode(AIConversionSettings.self, from: Data(#"{"reading_check": false}"#.utf8))
    #expect(!off.readingCheck)
    #expect(d.modelSize == .medium)
    let small = try JSONDecoder().decode(AIConversionSettings.self, from: Data(#"{"model_size": "small"}"#.utf8))
    #expect(small.modelSize == .small)
    let unknown = try JSONDecoder().decode(AIConversionSettings.self, from: Data(#"{"model_size": "huge"}"#.utf8))
    #expect(unknown.modelSize == .medium)
  }

  @Test func brokenFileFallsBackToDefaults() throws {
    try SystemUtil.withTempUserProfile { _ in
      try Data("{not json".utf8).write(to: AIConversionSettings.fileURL)
      #expect(AIConversionSettings.load() == AIConversionSettings())
    }
  }

  @Test func coreMLModelStatus() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "ai-model-status-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    for f in AIModelStatus.requiredFiles + [AIModelInstaller.coreMLConfigFileName] {
      try Data().write(to: dir.appending(path: f))
    }
    // genmai_coreml.json without a model
    #expect(!AIModelStatus.check(dir).isFound)
    try FileManager.default.createDirectory(
      at: dir.appending(path: "genmai_0.mlmodelc"), withIntermediateDirectories: false)
    #expect(AIModelStatus.check(dir).isFound)
    #expect(AIModelInstaller.coreMLModelFiles(in: dir) == ["genmai_0.mlmodelc"])
    let identity = AIModelStatus.identity(dir)
    #expect(identity != nil)
    try FileManager.default.createDirectory(
      at: dir.appending(path: "genmai_1.mlmodelc"), withIntermediateDirectories: false)
    #expect(AIModelStatus.identity(dir) != identity)
    try AIModelInstaller.uninstall(from: dir, cacheDirectory: dir.appending(path: "cache"))
    #expect(!FileManager.default.fileExists(atPath: dir.path))
  }

  @Test func modelStatus() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "ai-model-status-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(
      AIModelStatus.check(dir)
        == .missing(dir, missingFiles: AIModelStatus.requiredFiles + ["genmai.mlmodelc"]))
    for f in AIModelStatus.requiredFiles + ["genmai.mlmodelc"] {
      try Data().write(to: dir.appending(path: f))
    }
    let status = AIModelStatus.check(dir)
    #expect(status == .found(dir, info: nil))
    #expect(AIModelStatus.identity(dir) != nil)
    let release = GenmaiModelReleaseTests.release("0.2.0")
    #expect(status.needsInstall(release))
    #expect(status.installedSize == nil)
    try release.info.save(to: dir)
    #expect(AIModelStatus.check(dir) == .found(dir, info: release.info))
    #expect(AIModelStatus.check(dir).installedSize == .medium)
    #expect(!AIModelStatus.check(dir).needsInstall(release))
    // the other model is chosen in the settings
    #expect(AIModelStatus.check(dir).needsInstall(GenmaiModelReleaseTests.release("0.2.0", size: .small)))
    #expect(AIModelStatus.check(dir).needsInstall(GenmaiModelReleaseTests.release("0.10.0")))
    #expect(!AIModelStatus.check(dir).needsInstall(GenmaiModelReleaseTests.release("0.1.0")))
    #expect(AIModelStatus.check(dir.appending(path: "none")).needsInstall(release))
  }
}

// MARK: - Model installation

@Suite struct GenmaiModelReleaseTests {
  static func release(_ version: String, size: AIModelSize = .medium) -> GenmaiModelRelease {
    GenmaiModelRelease(
      info: GenmaiModelInfo(version: version, repository: size.repository, revision: "v\(version)"), files: [])
  }

  @Test func modelSizes() {
    #expect(AIModelSize.small.repository == "subdiox/genmai-90M")
    #expect(AIModelSize.medium.repository == "subdiox/genmai-310M")
    #expect(AIModelSize.small.modelName == "genmai-90M")
    #expect(AIModelSize(repository: "subdiox/genmai-90M") == .small)
    #expect(AIModelSize(repository: "someone/else") == nil)
  }

  /// Excerpts of the Hugging Face API answers for subdiox/genmai-310M.
  static let refs = Data(
    #"""
    {"tags":[{"name":"v0.1.0","ref":"refs/tags/v0.1.0","targetCommit":"876391d"},
    {"name":"v0.10.0","ref":"refs/tags/v0.10.0","targetCommit":"0"},{"name":"experiment","ref":"refs/tags/experiment"},
    {"name":"v0.2.0","ref":"refs/tags/v0.2.0","targetCommit":"aea042a"}],
    "branches":[{"name":"main","ref":"refs/heads/main","targetCommit":"08efa5c"}],"converts":[]}
    """#.utf8)
  static let tree = Data(
    #"""
    [{"type":"file","oid":"a6344aa","size":1519,"path":".gitattributes"},
    {"type":"file","oid":"70bb1e6b8b32086b8bccd5dcbb6d84ef3847669e","size":921,"path":"config.json"},
    {"type":"file","oid":"0695e41","size":1238046208,"lfs":{"oid":"e1ac64258359389b0451bdc521593cba825635baa08b2650a1140678a01396f6","size":1238046208,"pointerSize":135},"path":"model.safetensors"},
    {"type":"file","oid":"z1","size":282924021,"lfs":{"oid":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","size":282924021,"pointerSize":134},"path":"model-coreml.zip"},
    {"type":"file","oid":"ac7a91b3c4480c983debf6cc9c4d3d482c350fbf","size":394106,"path":"tokenizer.json"}]
    """#.utf8)

  @Test func releaseTagsNewestFirst() throws {
    let tags = try GenmaiModelRelease.releaseTags(Self.refs)
    #expect(tags.map(\.tag) == ["v0.10.0", "v0.2.0", "v0.1.0"])
    #expect(tags.map(\.version) == ["0.10.0", "0.2.0", "0.1.0"])
    #expect(GenmaiModelRelease.version(ofTag: "1.2") == nil)
    #expect(GenmaiModelRelease.version(ofTag: "2.0.1") == "2.0.1")
    #expect(GenmaiModelRelease.compareVersions("0.9.9", "0.10.0") == .orderedAscending)
    #expect(GenmaiModelRelease.compareVersions("1.0.0", "1.0.0") == .orderedSame)
  }

  /// Only config.json, tokenizer.json and the Core ML model are downloaded (not the fp32 weights).
  @Test func filesWithChecksums() throws {
    let files = try GenmaiModelRelease.files(Self.tree)
    #expect(files.map(\.name) == ["config.json", "tokenizer.json", "model-coreml.zip"])
    #expect(
      files[0] == .init(name: "config.json", size: 921, checksum: .gitBlob("70bb1e6b8b32086b8bccd5dcbb6d84ef3847669e")))
    #expect(
      files[2]
        == .init(
          name: "model-coreml.zip", size: 282_924_021,
          checksum: .sha256("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")))
    #expect(throws: AIModelInstallError.self) { try GenmaiModelRelease.files(Data("[]".utf8)) }
    let r = GenmaiModelRelease(
      info: GenmaiModelInfo(version: "1.0.0", repository: "subdiox/genmai-310M", revision: "v1.0.0"), files: files)
    #expect(r.downloadSize == 921 + 394_106 + 282_924_021)
    #expect(
      r.url(of: files[2]).absoluteString == "https://huggingface.co/subdiox/genmai-310M/resolve/v1.0.0/model-coreml.zip"
    )
    // a release without the Core ML model cannot be installed
    let fp32Only = Data(
      String(decoding: Self.tree, as: UTF8.self).replacing("model-coreml.zip", with: "other.zip").utf8)
    #expect(throws: AIModelInstallError.self) { try GenmaiModelRelease.files(fp32Only) }
    #expect(GenmaiModelRelease.isSupportedCoreML(config: Data(#"{"format": "genmai-coreml-1", "chunks": 2}"#.utf8)))
    #expect(!GenmaiModelRelease.isSupportedCoreML(config: Data(#"{"format": "genmai-coreml-2"}"#.utf8)))
  }

  /// A Core ML archive is extracted and its packages are found.
  @Test func unzipCoreMLArchive() async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "coreml-zip-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appending(path: "source")
    try FileManager.default.createDirectory(
      at: source.appending(path: "genmai_0.mlpackage"), withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: source.appending(path: "genmai_0.mlpackage/Manifest.json"))
    try Data(#"{"format": "genmai-coreml-1"}"#.utf8).write(to: source.appending(path: "genmai_coreml.json"))
    let archive = dir.appending(path: "model-coreml.zip")
    let zip = Process()
    zip.executableURL = URL(filePath: "/usr/bin/ditto")
    zip.arguments = ["-c", "-k", source.path, archive.path]
    let status: Int32 = try await withCheckedThrowingContinuation { continuation in
      zip.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
      do {
        try zip.run()
      } catch {
        zip.terminationHandler = nil
        continuation.resume(throwing: error)
      }
    }
    #expect(status == 0)
    let out = dir.appending(path: "out")
    try await AIModelInstaller.unzip(archive, to: out)
    #expect(AIModelInstaller.coreMLModelFiles(in: out) == ["genmai_0.mlpackage"])
    #expect(FileManager.default.fileExists(atPath: out.appending(path: "genmai_coreml.json").path))
    await #expect(throws: AIModelInstallError.self) {
      try await AIModelInstaller.unzip(dir.appending(path: "missing.zip"), to: out)
    }
  }

  @Test func compatibility() {
    func config(_ extra: String) -> Data {
      Data(
        #"{"model_type": "gpt2", "n_layer": 24, "n_embd": 1024, "n_head": 16, "vocab_size": 6000, "n_positions": 1024\#(extra)}"#
          .utf8)
    }
    #expect(GenmaiModelRelease.isCompatible(config: config("")))
    #expect(GenmaiModelRelease.isCompatible(config: config(#", "genmai_prompt_format": "zenzlc""#)))
    #expect(!GenmaiModelRelease.isCompatible(config: config(#", "genmai_prompt_format": "chat""#)))
    #expect(!GenmaiModelRelease.isCompatible(config: Data(#"{"model_type": "llama"}"#.utf8)))
    #expect(!GenmaiModelRelease.isCompatible(config: Data("nope".utf8)))
  }

  @Test func checksums() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "checksum-\(UUID())")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("hello\n".utf8).write(to: url)
    // `git hash-object` / `shasum -a 256` of "hello\n"
    #expect(try await AIModelInstaller.checksum(of: url, .gitBlob("ce013625030ba8dba906f756967f9e9ca394464a")))
    #expect(
      try await AIModelInstaller.checksum(
        of: url, .sha256("5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03")))
    #expect(!(try await AIModelInstaller.checksum(of: url, .gitBlob("0000"))))
  }
}

// MARK: - Hook in the session layer

private var ossDataAvailable: Bool {
  FileManager.default.fileExists(atPath: OssDataManager.defaultDataPath)
}

@MainActor
private func withScopedProfile(_ body: @MainActor () async throws -> Void) async throws {
  try await SystemUtil.withTempUserProfile { _ in
    try await ConfigHandler.withScopedHandlerForTesting {
      try await CharacterFormManager.withScopedManagerForTesting {
        try await body()
      }
    }
  }
}

@MainActor
final class SessionDriver {
  let backend: SessionHandlerBackend
  let client: InProcessClient

  init(_ backend: SessionHandlerBackend) {
    self.backend = backend
    client = InProcessClient.make(backend: backend)
    var on = KeyEvent()
    on.specialKey = .on
    on.mode = .hiragana
    _ = client.sendKey(on)
  }

  @discardableResult
  func type(_ romaji: String, context: Context? = nil) -> Output? {
    var last: Output?
    for (i, c) in romaji.unicodeScalars.enumerated() {
      var key = KeyEvent()
      key.keyCode = c.value
      key.mode = .hiragana
      last = client.sendKey(key, context: i == 0 ? context : nil)
    }
    return last
  }

  @discardableResult
  func special(_ special: KeyEvent.SpecialKey) -> Output? {
    var key = KeyEvent()
    key.specialKey = special
    return client.sendKey(key)
  }

  /// Types `romaji`, presses SPACE (awaiting an AI result in flight first, like the input controller);
  /// returns the conversion output.
  @discardableResult
  func convert(_ romaji: String, context: Context? = nil) async -> Output? {
    type(romaji, context: context)
    return await space()
  }

  /// SPACE, awaiting an AI result in flight first.
  @discardableResult
  func space() async -> Output? {
    var key = KeyEvent()
    key.specialKey = .space
    guard let hook = backend.aiHook else { return client.sendKey(key) }
    return await hook.sendKey(key, via: client)
  }

  static func preedit(_ output: Output?) -> String {
    output?.preedit.segment.map(\.value).joined() ?? ""
  }

  static func segments(_ output: Output?) -> [String] {
    output?.preedit.segment.map(\.value) ?? []
  }

  static func candidates(_ output: Output?) -> [String] {
    output?.allCandidateWords.candidates.map(\.value) ?? []
  }

  static func descriptions(_ output: Output?) -> [String] {
    output?.allCandidateWords.candidates.map(\.annotation.description_p) ?? []
  }
}

@MainActor
@Suite(.serialized, .enabled(if: ossDataAvailable, "Data/genmai.data is missing (run Tools/build_data.sh)"))
struct AIConversionHookTests {
  static let enabled = AIConversionSettings(enabled: true, timeoutMilliseconds: 1000)

  /// The output without the session id (each backend numbers its sessions independently).
  static func strip(_ output: Output?) -> Output? {
    guard var output else { return nil }
    output.id = 0
    return output
  }

  func makeAI(_ augmenter: FakeAugmenter, settings: AIConversionSettings = enabled) -> (SessionDriver, AIConversionHook)
  {
    let hook = AIConversionHook(augmenter: augmenter, settings: settings)
    return (SessionDriver(SessionHandlerBackend(aiHook: hook)), hook)
  }

  @Test func aiTopComesFirstAndIsMarked() async throws {
    try await withScopedProfile {
      let plain = SessionDriver(SessionHandlerBackend())
      let mozc = await plain.convert("hashiwowatarihajimeta")
      #expect(SessionDriver.preedit(mozc) == "橋をわたり始めた")

      let fake = FakeAugmenter(["はしをわたりはじめた": ["橋を渡り始めた", "箸を渡り始めた"]])
      let (ai, hook) = makeAI(fake)
      let output = await ai.convert("hashiwowatarihajimeta")
      #expect(SessionDriver.preedit(output) == "橋を渡り始めた")
      #expect(fake.converted.map(\.reading) == ["はしをわたりはじめた"])
      let record = try #require(hook.lastConversion)
      #expect(record.outcome.replacedTop)
      #expect(!record.timedOut)
      // The first segment's candidates: AI top, the AI alternative, then Mozc's.
      let candidates = SessionDriver.candidates(output)
      #expect(candidates.first == "橋を")
      #expect(candidates.dropFirst().first == "箸を")
      #expect(SessionDriver.descriptions(output).first?.hasPrefix("AI") != true)  // 橋を is Mozc's own top
      // The next segment carries the AI's 渡り, marked in the candidate window.
      let segments = SessionDriver.segments(output)
      #expect(segments.count >= 2)
      let next = ai.special(.right)
      #expect(SessionDriver.descriptions(next).first?.hasPrefix("AI") == true)
      #expect(SessionDriver.candidates(next).first?.hasPrefix("渡り") == true)
    }
  }

  @Test func readingCheckDropsCandidatesThatDoNotReadAsTheInput() async throws {
    try await withScopedProfile {
      let texts = ["母は歯が痛いらしい", "母は歯痒いらしい", "ハハハハが痛いらしい"]
      let fake = FakeAugmenter(["ははははがいたいらしい": texts])
      let (ai, hook) = makeAI(fake)
      await hook.waitForReadingCheck()
      _ = await ai.convert("hahahahagaitairasii")
      let record = try #require(hook.lastConversion)
      #expect(record.texts == ["母は歯が痛いらしい", "ハハハハが痛いらしい"])
      #expect(record.unreadable == ["母は歯痒いらしい"])
      #expect(!SessionDriver.candidates(ai.special(.space)).contains("母は歯痒いらしい"))
      _ = ai.special(.escape)
      _ = ai.special(.escape)

      var off = Self.enabled
      off.readingCheck = false
      let (plain, plainHook) = makeAI(FakeAugmenter(["ははははがいたいらしい": texts]), settings: off)
      _ = await plain.convert("hahahahagaitairasii")
      #expect(plainHook.lastConversion?.texts == texts)
      #expect(plainHook.lastConversion?.unreadable == [])
    }
  }

  @Test func disabledHookIsIdenticalToGenmai() async throws {
    try await withScopedProfile {
      let inputs = ["kisyanokisyagakisyadekisyasita", "watashinonamaehanakanodesu", "hashiwowatarihajimeta"]
      let fake = FakeAugmenter { _, _ in ["全然違う変換"] }
      let plain = SessionDriver(SessionHandlerBackend())
      let (ai, hook) = makeAI(fake, settings: AIConversionSettings(enabled: false))
      for romaji in inputs {
        #expect(Self.strip(await plain.convert(romaji)) == Self.strip(await ai.convert(romaji)))
        #expect(Self.strip(plain.special(.space)) == Self.strip(ai.special(.space)))
        #expect(Self.strip(plain.special(.right)) == Self.strip(ai.special(.right)))
        #expect(Self.strip(plain.special(.enter)) == Self.strip(ai.special(.enter)))
      }
      #expect(fake.converted.isEmpty)
      #expect(fake.prepared.isEmpty)
      #expect(hook.lastConversion == nil)
    }
  }

  @Test func fallsBackToGenmaiOnTimeout() async throws {
    try await withScopedProfile {
      let fake = FakeAugmenter { _, _ in
        try await Task.sleep(for: .seconds(5))
        return ["箸を渡り始めた"]
      }
      let (ai, hook) = makeAI(fake, settings: AIConversionSettings(enabled: true, timeoutMilliseconds: 100))
      let start = ContinuousClock.now
      let output = await ai.convert("hashiwowatarihajimeta")
      #expect(ContinuousClock.now - start < .seconds(2))
      #expect(SessionDriver.preedit(output) == "橋をわたり始めた")
      #expect(hook.lastConversion?.timedOut == true)
    }
  }

  /// The conversion key itself never waits: evaluated without `conversionWait`, a result still in flight is not
  /// used (Mozc's), a finished one is.
  @Test func conversionKeyNeverBlocks() async throws {
    try await withScopedProfile {
      let fake = FakeAugmenter { reading, _ in
        if reading == "はしをわたりはじめた" { try await Task.sleep(for: .seconds(5)) }
        return ["橋を渡り始めた"]
      }
      let (ai, hook) = makeAI(fake, settings: AIConversionSettings(enabled: true, timeoutMilliseconds: 3000))
      ai.type("hashiwowatarihajimeta")
      let start = ContinuousClock.now
      #expect(SessionDriver.preedit(ai.special(.space)) == "橋をわたり始めた")
      #expect(ContinuousClock.now - start < .seconds(1))
      #expect(hook.lastConversion?.timedOut == true)
      ai.special(.escape)
      ai.special(.escape)
      // A finished result is used directly; conversionWait has nothing to wait for.
      fake.lock.withLock { $0.results["はしをわたる\u{0}"] = ["橋を渡る"] }
      ai.type("hashiwowataru")
      var space = KeyEvent()
      space.specialKey = .space
      #expect(hook.conversionWait(for: space) == nil)
      #expect(SessionDriver.preedit(ai.special(.space)) == "橋を渡る")
      #expect(hook.lastConversion?.timedOut == false)
    }
  }

  @Test func fallsBackToGenmaiOnErrorOrWhenNotReady() async throws {
    try await withScopedProfile {
      let failing = FakeAugmenter { _, _ in throw FakeError() }
      let (ai, hook) = makeAI(failing)
      #expect(SessionDriver.preedit(await ai.convert("hashiwowatarihajimeta")) == "橋をわたり始めた")
      #expect(hook.lastConversion?.error != nil)

      let loading = FakeAugmenter { _, _ in ["箸を渡り始めた"] }
      loading.setStatus(.loading)
      let (ai2, hook2) = makeAI(loading)
      #expect(SessionDriver.preedit(await ai2.convert("hashiwowatarihajimeta")) == "橋をわたり始めた")
      #expect(loading.converted.isEmpty)
      #expect(hook2.lastConversion == nil)
    }
  }

  @Test func unalignedResultBecomesOneSegmentAndShrinkFallsBackToGenmai() async throws {
    try await withScopedProfile {
      // ず / づ: the AI text does not match the reading, so it cannot be cut into Mozc's segments.
      let fake = FakeAugmenter(["きょうははやめにかえります": ["今日わ早めに帰ります"]])
      let (ai, hook) = makeAI(fake)
      let output = await ai.convert("kyouhahayamenikaerimasu")
      #expect(SessionDriver.segments(output) == ["今日わ早めに帰ります"])
      #expect(hook.lastConversion?.outcome.wholeSentence == true)
      // Shift+Left shrinks the segment: Mozc re-converts with its own candidates.
      var shrink = KeyEvent()
      shrink.specialKey = .left
      shrink.modifierKeys = [.shift]
      let shrunk = ai.client.sendKey(shrink)
      #expect(SessionDriver.segments(shrunk).count == 2)
      #expect(!SessionDriver.preedit(shrunk).contains("わ早"))
    }
  }

  @Test func passesTheLeftContextAndPreparesWhileTyping() async throws {
    try await withScopedProfile {
      let fake = FakeAugmenter { _, _ in [] }
      let (ai, hook) = makeAI(fake)
      hook.noteSurroundingText("昨日は雨だった。")
      ai.type("kyouha")
      #expect(fake.prepared.map(\.reading).contains("きょうは"))
      #expect(fake.prepared.allSatisfy { $0.context == "昨日は雨だった。" })
      // Pending romaji is not part of the prepared reading.
      #expect(!fake.prepared.contains { $0.reading.contains("h") })
      await ai.space()
      #expect(fake.converted.last?.context == "昨日は雨だった。")
      ai.special(.enter)
      // The committed text extends the context of the next conversion.
      await ai.convert("hare")
      #expect(fake.converted.last?.context == "昨日は雨だった。今日は")
      ai.special(.escape)
      ai.special(.escape)
      // An empty preceding text (new field) resets it.
      var context = Context()
      context.precedingText = ""
      await ai.convert("hare", context: context)
      #expect(fake.converted.last?.context == "")
    }
  }

  @Test func selectionFeedsGenmaiLearning() async throws {
    try await withScopedProfile {
      let fake = FakeAugmenter(["はしをわたりはじめた": ["橋を渡り始めた"]])
      let hook = AIConversionHook(augmenter: fake, settings: Self.enabled)
      let ai = SessionDriver(SessionHandlerBackend(aiHook: hook))
      #expect(SessionDriver.preedit(await ai.convert("hashiwowatarihajimeta")) == "橋を渡り始めた")
      #expect(ai.special(.enter)?.result.value == "橋を渡り始めた")
      // AI off: Mozc now prefers what the user committed (user segment history).
      hook.apply(AIConversionSettings(enabled: false))
      #expect(SessionDriver.preedit(await ai.convert("hashiwowatarihajimeta")) == "橋を渡り始めた")
      ai.special(.escape)
      ai.special(.escape)
    }
  }

  @Test func userChoiceWinsOverAI() async throws {
    try await withScopedProfile {
      let fake = FakeAugmenter(["はしをわたりはじめた": ["橋を渡り始めた"]])
      let hook = AIConversionHook(augmenter: fake, settings: Self.enabled)
      let ai = SessionDriver(SessionHandlerBackend(aiHook: hook))
      let output = await ai.convert("hashiwowatarihajimeta")
      let segments = SessionDriver.segments(output)
      #expect(segments.first == "橋を")
      // Focus the AI segment (渡り) and choose Mozc's わたり from its candidates.
      ai.special(.right)
      var chosen = ai.special(.space)
      for _ in 0..<10 where !SessionDriver.segments(chosen).contains("わたり") {
        chosen = ai.special(.space)
      }
      #expect(SessionDriver.segments(chosen).contains("わたり"))
      let committed = ai.special(.enter)?.result.value ?? ""
      #expect(committed.contains("わたり"))
      // Next time the AI still says 渡り, but the user's learned choice stays first.
      let again = await ai.convert("hashiwowatarihajimeta")
      #expect(SessionDriver.segments(again).contains("わたり"))
      #expect((hook.lastConversion?.outcome.keptLearned ?? 0) >= 1)
    }
  }

  static func suggestions(_ output: Output?) -> [String] {
    output?.candidateWindow.candidate.map(\.value) ?? []
  }

  /// The ready AI result is the first suggestion while typing (what SPACE gives: Mozc's conversion with the AI
  /// result merged), and SPACE gives the same text.
  @Test func suggestionShowsTheReadyAIConversionAndSpaceMatches() async throws {
    try await withScopedProfile {
      let plain = SessionDriver(SessionHandlerBackend())
      let mozc = plain.type("hashiwowatarihajimeta")
      #expect(mozc?.candidateWindow.category == .suggestion)
      #expect(Self.suggestions(mozc).first != "橋を渡り始めた")

      let fake = FakeAugmenter(["はしをわたりはじめた": ["橋を渡り始めた", "箸を渡り始めた"]])
      fake.lock.withLock { $0.results["はしをわたりはじめた\u{0}"] = ["橋を渡り始めた", "箸を渡り始めた"] }
      let (ai, _) = makeAI(fake)
      let typed = ai.type("hashiwowatarihajimeta")
      #expect(SessionDriver.preedit(typed) == "はしをわたりはじめた")
      #expect(Self.suggestions(typed).first == "橋を渡り始めた")
      #expect(typed?.candidateWindow.candidate.first?.annotation.description_p.hasPrefix("AI") == true)
      // Mozc's own suggestions follow.
      #expect(Self.suggestions(typed).dropFirst().contains { Self.suggestions(mozc).contains($0) })
      let converted = await ai.space()
      #expect(SessionDriver.preedit(converted) == "橋を渡り始めた")
      #expect(fake.converted.isEmpty)  // ready: nothing awaited
    }
  }

  /// A result that arrives after the keystroke was answered: `suggestionUpdate` finishes, the suggestion is
  /// re-requested for the unchanged composition (MOVE_CURSOR) and has the AI text first; committing it from the
  /// suggestion window feeds Mozc's learning.
  @Test func suggestionRefreshAfterTheResultArrives() async throws {
    try await withScopedProfile {
      let fake = FakeAugmenter { _, _ in [] }
      let (ai, hook) = makeAI(fake)
      let release = fake.startBackground(reading: "はしをわたる", context: "", texts: ["箸を渡る"])
      let typed = ai.type("hashiwowataru")
      #expect(!Self.suggestions(typed).isEmpty)
      #expect(Self.suggestions(typed).first != "箸を渡る")
      let update = try #require(hook.suggestionUpdate())
      release()
      #expect(await update.value)
      var command = SessionCommand()
      command.type = .moveCursor
      command.cursorPosition = typed?.preedit.cursor ?? 0
      let refreshed = ai.client.sendCommand(command)
      #expect(refreshed?.preedit == typed?.preedit)
      #expect(!(refreshed?.hasResult ?? true))
      #expect(Self.suggestions(refreshed).first == "箸を渡る")
      #expect(hook.suggestionUpdate() == nil)  // nothing more in flight

      // Choose it in the suggestion window: committed like a Mozc suggestion, and learned.
      var submit = SessionCommand()
      submit.type = .submitCandidate
      submit.id = try #require(refreshed?.candidateWindow.candidate.first?.id)
      #expect(ai.client.sendCommand(submit)?.result.value == "箸を渡る")
      hook.apply(AIConversionSettings(enabled: false))
      #expect(Self.suggestions(ai.type("hashiwowataru")).contains("箸を渡る"))
    }
  }

  /// Until the AI result for the extended composition is ready, the last AI suggestion stays on top, extended by
  /// the kana typed since (the AI row does not disappear on every keystroke).
  @Test func lastAISuggestionStaysUntilTheNextResult() async throws {
    try await withScopedProfile {
      let fake = FakeAugmenter { _, _ in [] }
      fake.lock.withLock { $0.results["はしを\u{0}"] = ["端を"] }
      let (ai, _) = makeAI(fake)
      let first = ai.type("hashiwo")
      #expect(Self.suggestions(first).first == "端を")
      let next = ai.type("wa")
      #expect(SessionDriver.preedit(next) == "はしをわ")
      #expect(Self.suggestions(next).first == "端をわ")
      #expect(next?.candidateWindow.candidate.first?.annotation.description_p.hasPrefix("AI") == true)
      // A pending consonant does not remove it either.
      let pending = ai.type("t")
      #expect(Self.suggestions(pending).first?.hasPrefix("端をわ") == true)
      // Deleting characters: nothing to extend.
      ai.special(.escape)
      ai.special(.escape)
      ai.special(.escape)
      let again = ai.type("hashi")
      #expect(Self.suggestions(again).first != "端を")
    }
  }

  /// A pending "n" at the end is converted as ん by SPACE: the speculation reads it as ん, so the AI is used.
  @Test func pendingNIsSpeculatedAsN() async throws {
    try await withScopedProfile {
      let fake = FakeAugmenter(["じかん": ["時間"], "かいせん": ["回線"]])
      let (ai, hook) = makeAI(fake)
      _ = ai.type("kaisen")
      #expect(fake.prepared.last?.reading == "かいせん")
      // Pending consonants are not speculated on (かいｓ).
      #expect(!fake.prepared.contains { $0.reading.unicodeScalars.contains { AIConversionHook.isRomajiLetter($0) } })
      let converted = await ai.space()
      #expect(SessionDriver.preedit(converted) == "回線")
      #expect(hook.lastConversion?.texts.first == "回線")
    }
  }

  /// AI off (hook installed): typing gives exactly Mozc's suggestions, even with AI results at hand, and no
  /// refresh is ever requested.
  @Test func disabledHookSuggestionsAreIdenticalToGenmai() async throws {
    try await withScopedProfile {
      let fake = FakeAugmenter { _, _ in ["全然違う変換"] }
      fake.lock.withLock {
        $0.results["はしをわたる\u{0}"] = ["箸を渡る"]
        $0.results["きょうははれ\u{0}"] = ["京は晴れ"]
      }
      _ = fake.startBackground(reading: "はしをわたる", context: "", texts: ["箸を渡る"])
      let plain = SessionDriver(SessionHandlerBackend())
      let (ai, hook) = makeAI(fake, settings: AIConversionSettings(enabled: false))
      for romaji in ["hashiwowataru", "kyouhahare"] {
        for c in romaji.unicodeScalars {
          #expect(Self.strip(plain.type(String(c))) == Self.strip(ai.type(String(c))))
          #expect(hook.suggestionUpdate() == nil)
        }
        #expect(Self.strip(plain.special(.tab)) == Self.strip(ai.special(.tab)))
        #expect(Self.strip(plain.special(.escape)) == Self.strip(ai.special(.escape)))
        #expect(Self.strip(plain.special(.escape)) == Self.strip(ai.special(.escape)))
        #expect(Self.strip(plain.special(.escape)) == Self.strip(ai.special(.escape)))
      }
      #expect(fake.prepared.isEmpty)
    }
  }

  @Test func debugLogIsOptIn() async throws {
    try await withScopedProfile {
      let url = URL(filePath: SystemUtil.getUserProfileDirectory()).appending(path: AIConversionDebugLog.fileName)
      let fake = FakeAugmenter(["はしをわたる": ["箸を渡る"]])
      let (ai, hook) = makeAI(fake)
      await ai.convert("hashiwowataru")
      #expect(!FileManager.default.fileExists(atPath: url.path))
      ai.special(.escape)
      ai.special(.escape)
      var settings = Self.enabled
      settings.debugLog = true
      hook.apply(settings)
      await ai.convert("hashiwowataru")
      let log = try String(contentsOf: url, encoding: .utf8)
      let line = try #require(log.split(separator: "\n").last)
      #expect(line.contains("reading=はしをわたる"))
      #expect(line.contains("ai=[箸を渡る]"))
      #expect(line.contains("shown=箸を渡る"))
    }
  }
}
