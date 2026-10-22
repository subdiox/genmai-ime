// Tests of InProcessClient (the parts of client/client_test.cc that do not depend on IPC: session creation,
// input construction, context handling, history playback after a lost session, direct mode keys, tool
// launching) and of FakeSessionBackend.

import GenmaiProtocol
import Testing

@testable import GenmaiClient

@MainActor
final class RecordingBackend: SessionBackend {
  var inputs: [Input] = []
  var nextID: UInt64 = 1
  var sessionID: UInt64 = 0
  var fail = false

  func evalCommand(_ input: Input) -> Output? {
    inputs.append(input)
    if fail { return nil }
    var output = Output()
    switch input.type {
    case .createSession:
      sessionID = nextID
      nextID += 1
      output.id = sessionID
      output.errorCode = .sessionSuccess
    case .getConfig:
      output.id = input.id
      output.config.incognitoMode = true
    default:
      output.id = sessionID
      output.consumed = true
      if input.type == .sendKey, input.key.specialKey == .enter {
        output.result.type = .string
        output.result.value = "x"
      }
    }
    return output
  }

  /// Simulates a server restart: the old session id becomes invalid.
  func dropSession() { sessionID = 0 }
}

@MainActor
final class RecordingLauncher: AppLauncher {
  var modes: [String] = []
  func openApp(mode: String, extraArg: String, environment: [String: String]) -> Bool {
    modes.append(mode)
    return true
  }
}

private func key(_ c: Character) -> KeyEvent {
  var key = KeyEvent()
  key.keyCode = c.unicodeScalars.first.map { UInt32($0.value) } ?? 0
  return key
}

@MainActor
@Suite struct InProcessClientTests {
  func makeClient(_ backend: RecordingBackend, launcher: RecordingLauncher? = nil) -> InProcessClient {
    InProcessClient(backend: backend, initialConfig: Config(), toolLauncher: launcher)
  }

  @Test func createsSessionWithCapability() {
    let backend = RecordingBackend()
    let client = makeClient(backend)
    var capability = Capability()
    capability.textDeletion = .deletePrecedingText
    client.setClientCapability(capability)
    #expect(client.sendKey(key("a")) != nil)
    #expect(backend.inputs.map(\.type) == [.createSession, .sendKey])
    #expect(backend.inputs[0].capability.textDeletion == .deletePrecedingText)
    #expect(backend.inputs[0].applicationInfo.hasProcessID)
    #expect(backend.inputs[1].id == 1)
    // A nil context is the default instance: no context field.
    #expect(!backend.inputs[1].hasContext)
  }

  @Test func contextIsCopiedEvenIfEmpty() {
    let backend = RecordingBackend()
    let client = makeClient(backend)
    _ = client.sendKey(key("a"), context: Context())
    #expect(backend.inputs.last?.hasContext == true)
    var context = Context()
    context.precedingText = "abc"
    _ = client.sendCommand(SessionCommand(), context: context)
    #expect(backend.inputs.last?.type == .sendCommand)
    #expect(backend.inputs.last?.context.precedingText == "abc")
  }

  @Test func playbackHistoryAfterSessionLoss() {
    let backend = RecordingBackend()
    let client = makeClient(backend)
    _ = client.sendKey(key("a"))
    _ = client.sendKey(key("b"))
    #expect(client.historyInputs.count == 2)
    backend.dropSession()
    backend.inputs.removeAll()
    _ = client.sendKey(key("c"))
    // c (invalid id) -> CREATE_SESSION -> playback a, b -> c again.
    #expect(backend.inputs.map(\.type) == [.sendKey, .createSession, .sendKey, .sendKey, .sendKey])
    #expect(backend.inputs.suffix(3).map(\.key.keyCode) == [97, 98, 99])
    #expect(backend.inputs.suffix(3).allSatisfy { $0.id == 2 })
  }

  @Test func resultResetsHistory() {
    let backend = RecordingBackend()
    let client = makeClient(backend)
    _ = client.sendKey(key("a"))
    var enter = KeyEvent()
    enter.specialKey = .enter
    _ = client.sendKey(enter)
    #expect(client.historyInputs.isEmpty)
  }

  @Test func backendFailureIsReported() {
    let backend = RecordingBackend()
    backend.fail = true
    let client = makeClient(backend)
    #expect(client.sendKey(key("a")) == nil)
    #expect(client.getConfig() == nil)
  }

  @Test func configAndCommands() {
    let backend = RecordingBackend()
    let client = makeClient(backend)
    #expect(client.getConfig()?.incognitoMode == true)
    #expect(client.setConfig(Config()))
    #expect(client.reload())
    #expect(client.clearUserHistory())
    #expect(backend.inputs.map(\.type) == [.getConfig, .setConfig, .reload, .clearUserHistory])
  }

  @Test func directModeCommand() {
    let client = makeClient(RecordingBackend())
    var on = KeyEvent()
    on.specialKey = .on
    #expect(client.isDirectModeCommand(on))
    #expect(!client.isDirectModeCommand(key("a")))
  }

  @Test func openAppWithProtoBuf() {
    let launcher = RecordingLauncher()
    let client = makeClient(RecordingBackend(), launcher: launcher)
    var output = Output()
    #expect(!client.openAppWithProtoBuf(output))
    output.launchToolMode = .noTool
    #expect(!client.openAppWithProtoBuf(output))
    output.launchToolMode = .dictionaryTool
    #expect(client.openAppWithProtoBuf(output))
    #expect(launcher.modes == ["dictionary_tool"])
    #expect(!client.openApp(mode: "", extraArg: ""))
    #expect(!client.openApp(mode: String(repeating: "x", count: 32), extraArg: ""))
  }
}

@MainActor
@Suite struct FakeSessionBackendTests {
  @Test func composeConvertCommit() {
    let client = FakeSessionBackend.makeClient()
    var on = KeyEvent()
    on.specialKey = .on
    on.mode = .hiragana
    #expect(client.sendKey(on)?.consumed == true)

    var output = client.sendKey(key("k"))
    output = client.sendKey(key("a"))
    #expect(output?.preedit.segment.first?.value == "か")

    var space = KeyEvent()
    space.specialKey = .space
    output = client.sendKey(space)
    #expect(output?.candidateWindow.candidate.first?.value == "か")
    #expect(output?.candidateWindow.candidate.map(\.value).contains("カ") == true)
    #expect(output?.preedit.segment.first?.annotation == .highlight)

    var select = SessionCommand()
    select.type = .selectCandidate
    select.id = 1
    output = client.sendCommand(select)
    #expect(output?.result.value == "カ")
  }

  @Test func directModeDoesNotConsume() {
    let client = FakeSessionBackend.makeClient()
    #expect(client.sendKey(key("a"))?.consumed == false)
  }

  @Test func reverseConversion() {
    let client = FakeSessionBackend.makeClient()
    var on = KeyEvent()
    on.specialKey = .on
    _ = client.sendKey(on)
    var command = SessionCommand()
    command.type = .convertReverse
    command.text = "漢字"
    let output = client.sendCommand(command)
    #expect(output?.preedit.segment.first?.value == "漢字")
    #expect(output?.candidateWindow.candidate.first?.value == "漢字")
  }
}
