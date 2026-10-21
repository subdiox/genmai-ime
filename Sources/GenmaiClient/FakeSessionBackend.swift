// A stand-in for GenmaiSession's SessionHandler for UI tests and previews (the IME uses SessionHandlerBackend).
//
// Not a port of any Mozc file. It understands just enough of the session protocol to exercise the IME UI:
// romaji/kana composition through the real `Composer` (GenmaiCore), a fake "conversion" whose candidates are the
// transliterations of the preedit (with an infolist entry and a footer), candidate selection by keys and mouse,
// mode switching, reconversion of a given text, and GET_CONFIG / SET_CONFIG / RELOAD backed by `ConfigHandler`.

import GenmaiBase
import GenmaiCore
import GenmaiProtocol

@MainActor
public final class FakeSessionBackend: SessionBackend {
  private enum State {
    case direct
    case precomposition
    case composition
    case conversion(candidates: [String], focused: Int)
  }

  private var nextSessionID: UInt64 = 1
  private var state: State = .direct
  private var mode: Genmai_Commands_CompositionMode = .hiragana
  private var composer: Composer
  private var config: Config
  private let tableManager = TableManager()

  public init(config: Config = ConfigHandler.getCopiedConfig()) {
    self.config = config
    let table = tableManager.getTable(getSharedDefaultRequest(), config) ?? Table.getSharedDefaultTable()
    composer = Composer(table, getSharedDefaultRequest(), config)
  }

  private func applyConfig() {
    composer.setConfig(config)
    if let table = tableManager.getTable(getSharedDefaultRequest(), config) {
      composer.setTable(table)
    }
  }

  /// Convenience: an `InProcessClient` talking to a fresh fake backend.
  public static func makeClient(toolLauncher: (any ToolLauncher)? = nil) -> InProcessClient {
    InProcessClient(
      backend: FakeSessionBackend(),
      initialConfig: ConfigHandler.getCopiedConfig(),
      toolLauncher: toolLauncher)
  }

  public func evalCommand(_ input: Input) -> Output? {
    var output = Output()
    output.id = input.id
    switch input.type {
    case .createSession:
      output.id = nextSessionID
      nextSessionID += 1
      output.errorCode = .sessionSuccess
    case .deleteSession, .noOperation, .cleanup, .syncData, .clearUserHistory, .clearUserPrediction,
      .shutdown, .setRequest:
      output.errorCode = .sessionSuccess
    case .getConfig:
      output.config = config
    case .setConfig:
      config = input.config
      ConfigHandler.setConfig(config)
      applyConfig()
    case .reload:
      ConfigHandler.reload()
      config = ConfigHandler.getCopiedConfig()
      applyConfig()
    case .sendKey:
      handleKey(input.key, &output)
    case .testSendKey:
      var copy = self.snapshot()
      handleKey(input.key, &output)
      restore(&copy)
      output.clearPreedit()
      output.clearCandidateWindow()
      output.clearResult()
    case .sendCommand:
      handleCommand(input.command, &output)
    default:
      output.errorCode = .sessionSuccess
    }
    return output
  }

  // MARK: - Key handling

  private func handleKey(_ key: KeyEvent, _ output: inout Output) {
    if key.hasMode, key.mode != .direct {
      mode = key.mode
    }
    if key.hasSpecialKey {
      switch key.specialKey {
      case .on, .hankaku, .kanji, .kana, .katakana:
        if case .direct = state {
          state = .precomposition
        }
        output.consumed = true
        output.mode = mode
        return
      case .off:
        commitIfNeeded(&output)
        state = .direct
        output.consumed = true
        output.mode = .direct
        return
      default:
        break
      }
    }
    switch state {
    case .direct:
      output.consumed = false
      return
    case .precomposition:
      if isInsertable(key) {
        state = .composition
        insert(key)
        fillComposition(&output)
      } else {
        output.consumed = false
        output.mode = mode
      }
    case .composition:
      handleCompositionKey(key, &output)
    case .conversion(let candidates, let focused):
      handleConversionKey(key, candidates: candidates, focused: focused, &output)
    }
  }

  private func isInsertable(_ key: KeyEvent) -> Bool {
    if !key.modifierKeys.isEmpty, key.modifierKeys != [.shift] {
      return false
    }
    return (key.hasKeyCode && !key.hasSpecialKey) || key.hasKeyString
  }

  private func insert(_ key: KeyEvent) {
    var key = key
    key.mode = mode
    _ = composer.insertCharacterKeyEvent(key)
  }

  private func handleCompositionKey(_ key: KeyEvent, _ output: inout Output) {
    if isInsertable(key) {
      insert(key)
      fillComposition(&output)
      return
    }
    switch key.specialKey {
    case .backspace:
      composer.backspace()
    case .del:
      composer.delete()
    case .left:
      composer.moveCursorLeft()
    case .right:
      composer.moveCursorRight()
    case .home:
      composer.moveCursorToBeginning()
    case .end:
      composer.moveCursorToEnd()
    case .enter:
      commit(composer.getStringForSubmission(), &output)
      return
    case .escape:
      reset()
      output.consumed = true
      output.mode = mode
      return
    case .space, .down, .tab:
      let candidates = makeCandidates()
      state = .conversion(candidates: candidates, focused: 0)
      fillConversion(candidates, 0, &output)
      return
    default:
      if key.hasSpecialKey {
        fillComposition(&output)
        return
      }
    }
    if composer.isEmpty() {
      reset()
      output.consumed = true
      output.mode = mode
      return
    }
    fillComposition(&output)
  }

  private func handleConversionKey(
    _ key: KeyEvent, candidates: [String], focused: Int, _ output: inout Output
  ) {
    if key.hasKeyCode, !key.hasSpecialKey, key.modifierKeys.isEmpty,
      let digit = Int(String(UnicodeScalar(UInt8(truncatingIfNeeded: key.keyCode)))), digit >= 1,
      digit <= candidates.count
    {
      commit(candidates[digit - 1], &output)
      return
    }
    if isInsertable(key) {
      // Commit the focused candidate and start a new composition.
      var result = Output()
      commit(candidates[focused], &result)
      state = .composition
      insert(key)
      fillComposition(&output)
      output.result = result.result
      return
    }
    switch key.specialKey {
    case .space, .down, .tab:
      let next = (focused + 1) % candidates.count
      state = .conversion(candidates: candidates, focused: next)
      fillConversion(candidates, next, &output)
    case .up:
      let previous = (focused + candidates.count - 1) % candidates.count
      state = .conversion(candidates: candidates, focused: previous)
      fillConversion(candidates, previous, &output)
    case .enter:
      commit(candidates[focused], &output)
    case .escape, .backspace:
      state = .composition
      fillComposition(&output)
    default:
      fillConversion(candidates, focused, &output)
    }
  }

  // MARK: - Commands

  private func handleCommand(_ command: SessionCommand, _ output: inout Output) {
    output.consumed = true
    switch command.type {
    case .switchCompositionMode:
      mode = command.compositionMode
      output.mode = mode
      refill(&output)
    case .submit:
      commitIfNeeded(&output)
    case .selectCandidate, .submitCandidate:
      if case .conversion(let candidates, _) = state, candidates.indices.contains(Int(command.id)) {
        commit(candidates[Int(command.id)], &output)
      }
    case .highlightCandidate:
      if case .conversion(let candidates, _) = state, candidates.indices.contains(Int(command.id)) {
        state = .conversion(candidates: candidates, focused: Int(command.id))
      }
      refill(&output)
    case .convertReverse:
      guard command.hasText, !command.text.isEmpty else {
        output.consumed = false
        return
      }
      reset()
      composer.setPreeditTextForTestOnly(command.text)
      let candidates = makeCandidates(including: command.text)
      state = .conversion(candidates: candidates, focused: 0)
      fillConversion(candidates, 0, &output)
    case .commitRawText:
      if composer.isEmpty() {
        output.consumed = false
        return
      }
      commit(composer.getRawString(), &output)
    case .revert, .resetContext:
      reset()
      output.mode = mode
    case .undo:
      output.consumed = false
    default:
      refill(&output)
    }
  }

  // MARK: - Output construction

  private func refill(_ output: inout Output) {
    switch state {
    case .composition:
      fillComposition(&output)
    case .conversion(let candidates, let focused):
      fillConversion(candidates, focused, &output)
    case .direct, .precomposition:
      output.mode = isDirect ? .direct : mode
    }
  }

  private var isDirect: Bool {
    if case .direct = state { return true }
    return false
  }

  private func fillComposition(_ output: inout Output) {
    output.consumed = true
    output.mode = mode
    let preedit = composer.getStringForPreedit()
    if preedit.isEmpty {
      return
    }
    var segment = Genmai_Commands_Preedit.Segment()
    segment.annotation = .underline
    segment.value = preedit
    segment.valueLength = UInt32(preedit.count)
    output.preedit.segment = [segment]
    output.preedit.cursor = UInt32(composer.getCursor())
  }

  private func fillConversion(_ candidates: [String], _ focused: Int, _ output: inout Output) {
    output.consumed = true
    output.mode = mode
    var segment = Genmai_Commands_Preedit.Segment()
    segment.annotation = .highlight
    segment.value = candidates[focused]
    segment.valueLength = UInt32(candidates[focused].count)
    output.preedit.segment = [segment]
    output.preedit.cursor = UInt32(candidates[focused].count)
    output.preedit.highlightedPosition = 0

    var window = Genmai_Commands_CandidateWindow()
    window.size = UInt32(candidates.count)
    window.position = 0
    window.focusedIndex = UInt32(focused)
    window.category = .conversion
    window.displayType = .main
    window.pageSize = 9
    let descriptions = ["ひらがな", "カタカナ", "[半] 英数", "[全] 英数", "[半] カタカナ", "そのまま"]
    for (i, value) in candidates.enumerated() {
      var candidate = Genmai_Commands_CandidateWindow.Candidate()
      candidate.index = UInt32(i)
      candidate.id = Int32(i)
      candidate.value = value
      candidate.annotation.shortcut = String(i + 1)
      if i < descriptions.count {
        candidate.annotation.description_p = descriptions[i]
      }
      if i == 0 {
        candidate.informationID = 0
      }
      window.candidate.append(candidate)
    }
    window.footer.indexVisible = true
    window.footer.label = "FakeSessionBackend"
    window.footer.logoVisible = true

    var info = Genmai_Commands_Information()
    info.id = 0
    info.title = candidates[0]
    info.description_p = "FakeSessionBackend: these candidates are transliterations."
    info.candidateID = [0]
    window.usages.information = [info]
    window.usages.focusedIndex = 0
    window.usages.delay = 500
    output.candidateWindow = window
  }

  private func makeCandidates(including text: String? = nil) -> [String] {
    var t13ns = Transliterations()
    composer.getTransliterations(&t13ns)
    var result: [String] = []
    if let text {
      result.append(text)
    }
    let order: [TransliterationType] = [.hiragana, .fullKatakana, .halfAscii, .fullAscii, .halfKatakana]
    for type in order where type.rawValue < t13ns.count {
      let value = t13ns[type.rawValue]
      if !value.isEmpty, !result.contains(value) {
        result.append(value)
      }
    }
    if result.isEmpty {
      result.append(composer.getStringForPreedit())
    }
    return result
  }

  private func commit(_ text: String, _ output: inout Output) {
    output.consumed = true
    output.mode = mode
    if !text.isEmpty {
      output.result.type = .string
      output.result.value = text
      output.result.key = composer.getQueryForConversion()
    }
    reset()
  }

  private func commitIfNeeded(_ output: inout Output) {
    switch state {
    case .composition:
      commit(composer.getStringForSubmission(), &output)
    case .conversion(let candidates, let focused):
      commit(candidates[focused], &output)
    case .direct, .precomposition:
      break
    }
  }

  private func reset() {
    composer.reset()
    if !isDirect {
      state = .precomposition
    }
  }

  // MARK: - TEST_SEND_KEY support

  private struct Snapshot {
    var state: State
    var mode: Genmai_Commands_CompositionMode
    var composer: Composer
  }

  private func snapshot() -> Snapshot { Snapshot(state: state, mode: mode, composer: composer) }

  private func restore(_ snapshot: inout Snapshot) {
    state = snapshot.state
    mode = snapshot.mode
    composer = snapshot.composer
  }
}
