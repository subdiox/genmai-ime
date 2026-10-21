// Port of mozc/src/mac/main.mm (3.35.6354).
//
// Entry point of the input method (Mozc.app/Contents/MacOS/GenmaiIME). Starts the IMKServer named by
// Info.plist's InputMethodConnectionName and runs the application. `--register_input_source` registers and
// enables the input source and exits (used by installers; never run automatically). `--self_test` loads the
// conversion engine from the bundle, converts a few sentences through the session layer, prints the results
// and timings, and exits (no IMKServer, nothing is registered). It also reports the AI conversion status and,
// if the genmai model is installed, converts the samples with AI conversion off and on.
//
// Not in Mozc: the backend gets the AI conversion hook (GenmaiAIClient's genmai augmenter); it is idle unless
// AI conversion is enabled in ai_conversion.json (config dialog > AI).

import AppKit
import Carbon
@preconcurrency import InputMethodKit
import GenmaiAIClient
import GenmaiBase
import GenmaiClient
import GenmaiCore
import GenmaiMac
import GenmaiProtocol

/// Registers the input source bundle with the Text Input Services (TIS)
/// and enables the bundle, which automatically enables all default input modes
/// (Hiragana, Katakana, Roman, etc.) defined in Info.plist, then selects the
/// bundle so that the primary input mode (Hiragana) is active.
func registerInputSource() {
  let bundle = Bundle.main
  TISRegisterInputSource(bundle.bundleURL as CFURL)

  guard let bundleID = bundle.bundleIdentifier else {
    return
  }
  guard let sourceList = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource]
  else {
    return
  }
  for inputSource in sourceList {
    guard let idPointer = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else {
      continue
    }
    let sourceID = Unmanaged<CFString>.fromOpaque(idPointer).takeUnretainedValue() as String
    if sourceID != bundleID {
      continue
    }
    if let enabledPointer = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceIsEnabled) {
      let isEnabled = Unmanaged<CFBoolean>.fromOpaque(enabledPointer).takeUnretainedValue()
      if CFBooleanGetValue(isEnabled) {
        // The input source is already enabled. Skip enabling and selecting to
        // avoid prompting the user or resetting their active input source.
        return
      }
    }
    TISEnableInputSource(inputSource)
    TISSelectInputSource(inputSource)
    break
  }
}

/// Kept alive for the lifetime of the process.
nonisolated(unsafe) var imkServer: IMKServer?

let kUsage = """
  Usage: GenmaiIME [--register_input_source | --self_test | --help]
    (no option)              run the input method (started by the system from Genmai.app)
    --register_input_source  register and enable the input source of this bundle, then exit
    --self_test              load the conversion engine, convert sample inputs, print timings, then exit
  """

/// Formats a duration in milliseconds.
func ms(_ duration: Duration) -> String {
  let (seconds, attoseconds) = duration.components
  return String(format: "%.2f ms", Double(seconds) * 1000 + Double(attoseconds) / 1e15)
}

/// Suspends until the model load of `hook` has finished, or at most `timeout` (the load continues after a
/// timeout; the caller then sees the `.loading` status).
@MainActor
func waitForAIModel(_ hook: AIConversionHook, timeout: Duration = .seconds(60)) async {
  guard let genmai = hook.genmai else { return }
  let (finished, continuation) = AsyncStream<Void>.makeStream()
  Task {
    await genmai.waitUntilLoaded()
    continuation.yield()
  }
  let timer = Task {
    try? await Task.sleep(for: timeout)
    continuation.yield()
  }
  for await _ in finished { break }
  timer.cancel()
}

/// Converts the self-test samples through the session layer of `backend` (ON, keys, SPACE, ENTER). Returns the
/// number of samples whose conversion differs from the expected one (when `expect` is true).
@MainActor
func runSamples(_ backend: SessionHandlerBackend, label: String, expect: Bool) async -> Int {
  print("[\(label)]")
  let client = InProcessClient.make(backend: backend)

  func send(_ key: KeyEvent) -> Output? { client.sendKey(key) }
  func special(_ special: KeyEvent.SpecialKey) -> KeyEvent {
    var key = KeyEvent()
    key.specialKey = special
    return key
  }
  var on = special(.on)
  on.mode = .hiragana
  _ = send(on)

  var failures = 0
  let samples = [
    ("kyouhahayamenikaerimasu", "今日は早めに帰ります"),
    ("watashinonamaehanakanodesu", "私の名前は中野です"),
    ("kisyanokisyagakisyadekisyasita", nil),
    ("nihongonyuuryoku", "日本語入力"),
    ("hashiwowatarihajimeta", nil),
  ]
  for (romaji, expected) in samples {
    var keyTimes: [Duration] = []
    var lastPreedit = ""
    for c in romaji.unicodeScalars {
      var key = KeyEvent()
      key.keyCode = c.value
      key.mode = .hiragana
      let start = ContinuousClock.now
      let output = send(key)
      keyTimes.append(ContinuousClock.now - start)
      lastPreedit = output?.preedit.segment.map(\.value).joined() ?? ""
    }
    let start = ContinuousClock.now
    // like the input controller: an AI result still in flight is awaited before SPACE is evaluated
    let converted =
      if let hook = backend.aiHook { await hook.sendKey(special(.space), via: client) } else { send(special(.space)) }
    let conversionTime = ContinuousClock.now - start
    let top = converted?.preedit.segment.map(\.value).joined() ?? ""
    let candidates = converted?.allCandidateWords.candidates.count ?? 0
    let commitStart = ContinuousClock.now
    let committed = send(special(.enter))
    let commitTime = ContinuousClock.now - commitStart
    let total = keyTimes.reduce(Duration.zero, +)
    print(
      "\(romaji): preedit \(lastPreedit) -> \(top) (\(candidates) candidates) committed \(committed?.result.value ?? "-")")
    var ai = ""
    if let record = backend.aiHook?.lastConversion, backend.aiHook?.isEnabled == true {
      ai =
        record.timedOut
        ? " (AI timed out)"
        : record.error.map { " (AI error: \($0))" }
          ?? " (AI \(record.texts.first ?? "-"), waited \(ms(record.waited)))"
    }
    print(
      "  per key avg \(ms(total / keyTimes.count)) max \(ms(keyTimes.max() ?? .zero)); conversion \(ms(conversionTime)); commit \(ms(commitTime))\(ai)"
    )
    if expect, let expected, top != expected {
      print("  FAILED: expected \(expected)")
      failures += 1
    }
  }
  return failures
}

/// `--self_test`: drives the real session layer the way the input controller does (ON, keys, SPACE, ENTER).
@MainActor
func runSelfTest() async -> Int32 {
  // AI settings of the user (read before switching to the temporary profile); the self test enables AI itself.
  let userAISettings = AIConversionSettings.load()
  // Keep the user's learning data untouched: use a temporary profile directory.
  let profile = FileManager.default.temporaryDirectory.appendingPathComponent(
    "GenmaiIME-self-test-\(ProcessInfo.processInfo.processIdentifier)")
  try? FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: profile) }
  SystemUtil.setUserProfileDirectory(profile.path)

  print("data: \(OssDataManager.defaultDataPath)")
  let backend = SessionHandlerBackend()
  guard backend.isAvailable else {
    print("error: the conversion engine is not available: \(backend.loadError.map { "\($0)" } ?? "unknown")")
    return 1
  }
  print("engine load: \(ms(backend.engineLoadTime)) (data version \(backend.dataVersion))")
  var failures = await runSamples(backend, label: "Genmai (AI conversion off)", expect: true)

  // AI conversion.
  let modelDirectory = userAISettings.resolvedModelDirectory
  let modelStatus = AIModelStatus.check(modelDirectory)
  print(
    "AI conversion: \(userAISettings.enabled ? "enabled" : "disabled") in the user settings; timeout \(userAISettings.timeoutMilliseconds) ms, \(userAISettings.candidateCount) candidates; model \(modelStatus.isFound ? "found" : "missing") at \(modelDirectory.path)"
  )
  if !modelStatus.isFound {
    print("  (prepare it with Tools/prepare_genmai_model.sh; skipping the AI samples)")
    return failures == 0 ? 0 : 1
  }
  var aiSettings = userAISettings
  aiSettings.enabled = true
  let hook = AIConversionHook.makeGenmai(settings: aiSettings)
  let loadStart = ContinuousClock.now
  await waitForAIModel(hook)
  print("AI model: \(hook.augmenter.status) after \(ms(ContinuousClock.now - loadStart)) (load + warm-up)")
  guard hook.augmenter.status == .ready else {
    print("error: the AI model failed to load")
    return 1
  }
  let aiBackend = SessionHandlerBackend(aiHook: hook)
  _ = await runSamples(aiBackend, label: "AI conversion on", expect: false)
  // AI off through the hook: must match plain Mozc.
  aiSettings.enabled = false
  hook.apply(aiSettings)
  failures += await runSamples(aiBackend, label: "AI hook installed, AI conversion off", expect: true)
  return failures == 0 ? 0 : 1
}

@MainActor
func runInputMethod() -> Int32 {
  let arguments = CommandLine.arguments.dropFirst()
  if arguments.contains("--help") || arguments.contains("-h") {
    print(kUsage)
    return 0
  }
  if arguments.contains("--register_input_source") {
    registerInputSource()
    return 0
  }
  if arguments.contains("--self_test") {
    Task { @MainActor in exit(await runSelfTest()) }
    RunLoop.main.run()
    return 0
  }

  if !RunLevel.isValidClientRunLevel() {
    return -1
  }

  // Initialize imkServer
  let bundle = Bundle.main
  guard let connectionName = bundle.infoDictionary?["InputMethodConnectionName"] as? String,
    let server = IMKServer(name: connectionName, bundleIdentifier: bundle.bundleIdentifier)
  else {
    NSLog("Genmai failed to initialize: run GenmaiIME from the Genmai.app bundle (Tools/make_ime_bundle.sh).")
    return -1
  }
  imkServer = server

  // Not in Mozc: the conversion server gets the AI conversion hook (idle unless enabled in the settings).
  let aiHook = AIConversionHook.makeGenmai()
  GenmaiIMEEnvironment.shared.backendFactory = { SessionHandlerBackend(aiHook: aiHook) }

  // The renderer and the conversion engine run in-process; RendererReceiver forwards candidate clicks to the
  // active controller. The engine is loaded now so that the first key press does not pay for it.
  let environment = GenmaiIMEEnvironment.shared
  _ = environment.renderer
  environment.start()

  let app = NSApplication.shared
  app.run()
  return 0
}

exit(MainActor.assumeIsolated { runInputMethod() })
