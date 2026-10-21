// Port of mozc/src/session/session_handler_tool.{h,cc} (3.35.6354).
//
// Session utility for stress tests and the scenario tests.
//
// Swift notes:
// - absl::Status results of SessionHandlerInterpreter::Eval are thrown as
//   `SessionHandlerInterpreterError`.
// - `syncData()` and the interpreter commands that sync (`eval`, `clearAll`,
//   `clearUserPrediction`, `syncDataToStorage`) are `async`: they await the
//   engine's background tasks instead of blocking.
// - protobuf reflection (FieldDescriptor / TextFormat::ParseFieldValueFromString)
//   is replaced by text-format parsing of a single "a { b { c: value } }"
//   message which is then merged into the target (MergeFrom semantics: a
//   singular field is overwritten, a repeated field gets the value appended).

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import SwiftProtobuf

private func toTextFormat(_ proto: some SwiftProtobuf.Message) -> String {
  proto.textFormatString()
}

/// Session utility for stress tests.
public final class SessionHandlerTool {
  private var id: UInt64 = 0  // Session ID
  private let engine: any EngineInterface
  private let handler: SessionHandler
  private var callbackText = ""

  public init(_ engine: any EngineInterface) {
    self.engine = engine
    handler = SessionHandler(engine)
  }

  public var sessionHandler: SessionHandler { handler }

  @discardableResult
  public func createSession() -> Bool {
    var command = Genmai_Commands_Command()
    command.input.type = .createSession
    command.input.capability.textDeletion = .deletePrecedingText
    handler.evalCommand(&command)
    id = command.hasOutput ? command.output.id : 0
    return command.output.errorCode == .sessionSuccess
  }

  @discardableResult
  public func deleteSession() -> Bool {
    var command = Genmai_Commands_Command()
    command.input.id = id
    command.input.type = .deleteSession
    return handler.evalCommand(&command)
  }

  @discardableResult
  public func cleanUp() -> Bool {
    var command = Genmai_Commands_Command()
    command.input.id = id
    command.input.type = .cleanup
    return handler.evalCommand(&command)
  }

  @discardableResult
  public func clearUserPrediction() -> Bool {
    var command = Genmai_Commands_Command()
    command.input.id = id
    command.input.type = .clearUserPrediction
    return handler.evalCommand(&command)
  }

  @discardableResult
  public func clearUserHistory() -> Bool {
    var command = Genmai_Commands_Command()
    command.input.id = id
    command.input.type = .clearUserHistory
    return handler.evalCommand(&command)
  }

  @discardableResult
  public func sendKey(_ key: Genmai_Commands_KeyEvent, _ output: inout Genmai_Commands_Output) -> Bool {
    sendKeyWithOption(key, Genmai_Commands_Input(), &output)
  }

  @discardableResult
  public func sendKeyWithOption(
    _ key: Genmai_Commands_KeyEvent, _ option: Genmai_Commands_Input,
    _ output: inout Genmai_Commands_Output
  ) -> Bool {
    var input = Genmai_Commands_Input()
    input.type = .sendKey
    input.key = key
    mergeFrom(&input, option)
    return evalCommand(&input, &output)
  }

  @discardableResult
  public func testSendKey(_ key: Genmai_Commands_KeyEvent, _ output: inout Genmai_Commands_Output)
    -> Bool
  {
    testSendKeyWithOption(key, Genmai_Commands_Input(), &output)
  }

  @discardableResult
  public func testSendKeyWithOption(
    _ key: Genmai_Commands_KeyEvent, _ option: Genmai_Commands_Input,
    _ output: inout Genmai_Commands_Output
  ) -> Bool {
    var input = Genmai_Commands_Input()
    input.type = .testSendKey
    input.key = key
    mergeFrom(&input, option)
    return evalCommand(&input, &output)
  }

  @discardableResult
  public func updateComposition(_ args: ArraySlice<String>, _ output: inout Genmai_Commands_Output)
    -> Bool
  {
    var input = Genmai_Commands_Input()
    //  input.set_type(commands::Input::UPDATE_COMPOSITION);
    input.type = .sendCommand
    input.command.type = .updateComposition
    var i = args.startIndex
    while i < args.endIndex {
      var compositionEvent = Genmai_Commands_SessionCommand.CompositionEvent()
      compositionEvent.compositionString = args[i]
      if i + 1 < args.endIndex, let value = NumberUtil.safeStrToDouble(args[i + 1]) {
        compositionEvent.probability = value
      }
      input.command.compositionEvents.append(compositionEvent)
      i += 2
    }
    return evalCommand(&input, &output)
  }

  @discardableResult
  public func selectCandidate(_ id: UInt32, _ output: inout Genmai_Commands_Output) -> Bool {
    var input = Genmai_Commands_Input()
    input.type = .sendCommand
    input.command.type = .selectCandidate
    input.command.id = Int32(bitPattern: id)
    return evalCommand(&input, &output)
  }

  @discardableResult
  public func submitCandidate(_ id: UInt32, _ output: inout Genmai_Commands_Output) -> Bool {
    var input = Genmai_Commands_Input()
    input.type = .sendCommand
    input.command.type = .submitCandidate
    input.command.id = Int32(bitPattern: id)
    return evalCommand(&input, &output)
  }

  @discardableResult
  public func reload() -> Bool {
    var input = Genmai_Commands_Input()
    input.type = .reload
    return evalCommand(&input, nil)
  }

  @discardableResult
  public func resetContext() -> Bool {
    var input = Genmai_Commands_Input()
    input.type = .sendCommand
    input.command.type = .resetContext
    return evalCommand(&input, nil)
  }

  @discardableResult
  public func undoOrRewind(_ output: inout Genmai_Commands_Output) -> Bool {
    var input = Genmai_Commands_Input()
    input.type = .sendCommand
    input.command.type = .undoOrRewind
    return evalCommand(&input, &output)
  }

  /// Try to delete the candidate from the history.
  /// The target candidate is specified with the |id|. If |id| is not specified,
  /// the current focused candidate will be specified.
  @discardableResult
  public func deleteCandidateFromHistory(_ id: Int?, _ output: inout Genmai_Commands_Output) -> Bool {
    var input = Genmai_Commands_Input()
    input.type = .sendCommand
    input.command.type = .deleteCandidateFromHistory
    if let id {
      input.command.id = Int32(truncatingIfNeeded: id)
    }
    return evalCommand(&input, &output)
  }

  @discardableResult
  public func switchCompositionMode(_ compositionMode: Genmai_Commands_CompositionMode) -> Bool {
    var input = Genmai_Commands_Input()
    input.type = .sendCommand
    input.command.type = .switchCompositionMode
    input.command.compositionMode = compositionMode
    return evalCommand(&input, nil)
  }

  @discardableResult
  public func setRequest(_ request: Genmai_Commands_Request, _ output: inout Genmai_Commands_Output)
    -> Bool
  {
    var input = Genmai_Commands_Input()
    input.type = .setRequest
    input.request = request
    return evalCommand(&input, &output)
  }

  @discardableResult
  public func setConfig(_ config: Genmai_Config_Config, _ output: inout Genmai_Commands_Output) -> Bool
  {
    var input = Genmai_Commands_Input()
    input.type = .setConfig
    input.config = config
    return evalCommand(&input, &output)
  }

  @discardableResult
  public func syncData() async -> Bool {
    engine.sync()
    await engine.wait()
    return true
  }

  public func setCallbackText(_ text: String) {
    callbackText = text
  }

  @discardableResult
  public func reloadSupplementalModel(_ modelPath: String) -> Bool {
    var input = Genmai_Commands_Input()
    input.engineReloadRequest.filePath = modelPath
    input.type = .reloadSupplementalModel
    var output = Genmai_Commands_Output()
    return evalCommand(&input, &output)
  }

  private func evalCommandInternal(
    _ input: inout Genmai_Commands_Input, _ output: UnsafeMutablePointer<Genmai_Commands_Output>?,
    _ allowCallback: Bool
  ) -> Bool {
    input.id = id
    var command = Genmai_Commands_Command()
    command.input = input
    var result = handler.evalCommand(&command)
    if result, let output {
      output.pointee = command.output
    }

    // If callback is allowed and the callback field exists, evaluate the callback
    // command.
    if result && allowCallback && command.output.hasCallback
      && command.output.callback.hasSessionCommand
    {
      var input2 = Genmai_Commands_Input()
      input2.type = .sendCommand
      input2.command = command.output.callback.sessionCommand
      input2.command.text = callbackText
      // Disallow further recursion.
      result = evalCommandInternal(&input2, output, false)
    }
    callbackText = ""
    return result
  }

  private func evalCommand(_ input: inout Genmai_Commands_Input, _ output: inout Genmai_Commands_Output)
    -> Bool
  {
    withUnsafeMutablePointer(to: &output) { evalCommandInternal(&input, $0, true) }
  }

  private func evalCommand(_ input: inout Genmai_Commands_Input, _ output: Never?) -> Bool {
    evalCommandInternal(&input, nil, true)
  }
}

/// Message::MergeFrom.
func mergeFrom<M: SwiftProtobuf.Message>(_ target: inout M, _ source: M) {
  do {
    let bytes: [UInt8] = try source.serializedBytes(partial: true)
    try target.merge(serializedBytes: bytes, partial: true)
  } catch {
    GenmaiLog.error("MergeFrom failed: \(error)")
  }
}

/// Builds the text format "a { b { c: value } }" for `names` = [a, b, c].
private func nestedTextFormat(_ names: [String], _ value: String) -> String {
  var text = "\(names.last!): \(value)"
  for name in names.dropLast().reversed() {
    text = "\(name) { \(text) }"
  }
  return text
}

/// SetOrAddFieldValueFromString(names, value, message).
func setOrAddFieldValueFromString<M: SwiftProtobuf.Message>(
  _ names: [String], _ value: String, _ message: inout M
) -> Bool {
  if names.isEmpty {
    GenmaiLog.error("Empty names is passed")
    return false
  }
  do {
    let partial = try M(textFormatString: nestedTextFormat(names, value))
    mergeFrom(&message, partial)
    return true
  } catch {
    GenmaiLog.error("Cannot parse field value: \(names.joined(separator: ".")) = \(value)")
    return false
  }
}

/// Parses protobuf from string without validation.
/// input sample: context.experimental_features="chrome_omnibox"
/// We cannot use TextFormat::ParseFromString since it doesn't allow invalid
/// protobuf. (e.g. lack of required field)
func parseProtobufFromString<M: SwiftProtobuf.Message>(_ text: String, _ message: inout M) -> Bool {
  let fullName: Substring
  let value: Substring
  if let separator = text.firstIndex(of: "=") {
    fullName = text[..<separator]
    value = text[text.index(after: separator)...]
  } else {
    fullName = Substring(text)
    value = Substring(text)
  }
  let names = fullName.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
  if names.isEmpty {
    return false
  }
  return setOrAddFieldValueFromString(names, String(value), &message)
}

/// Parses an enum value name (e.g. "HIRAGANA") through the text format of a
/// message that has a field of that enum type.
private func parseEnum<M: SwiftProtobuf.Message, E>(
  _ messageType: M.Type, _ field: String, _ name: String, _ get: (M) -> E
) -> E? {
  // Only plain identifiers are accepted (Foo_Parse semantics).
  if name.isEmpty
    || !name.utf8.allSatisfy({
      ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39)
        || $0 == 0x5F
    })
  {
    return nil
  }
  guard let message = try? M(textFormatString: "\(field): \(name)") else {
    return nil
  }
  return get(message)
}

public enum SessionHandlerInterpreterError: Error, CustomStringConvertible {
  /// absl::InvalidArgumentError (MOZC_ASSERT_*).
  case invalidArgument(String)
  /// absl::InternalError (MOZC_EXPECT_*).
  case `internal`(String)
  /// absl::StatusCode::kUnimplemented.
  case unimplemented

  public var description: String {
    switch self {
    case .invalidArgument(let message): return "INVALID_ARGUMENT: \(message)"
    case .internal(let message): return "INTERNAL: \(message)"
    case .unimplemented: return "UNIMPLEMENTED"
    }
  }
}

public final class SessionHandlerInterpreter {
  private let client: SessionHandlerTool
  private var config: Genmai_Config_Config
  private var lastOutput = Genmai_Commands_Output()
  private var request = Genmai_Commands_Request()

  public convenience init() throws {
    self.init(try EngineFactory.create())
  }

  public init(_ engine: any EngineInterface) {
    client = SessionHandlerTool(engine)
    lastOutput = Genmai_Commands_Output()
    request = Genmai_Commands_Request()
    config = ConfigHandler.getCopiedConfig()

    // Set up session.
    precondition(client.createSession(), "Client initialization is failed.")
  }

  deinit {
    // Shut down.
    _ = client.deleteSession()

    clearState()
  }

  public var tool: SessionHandlerTool { client }

  public func clearState() {
    let config = ConfigHandler.defaultConfig()
    ConfigHandler.setConfig(config)

    // CharacterFormManager is not automatically updated when the config is
    // updated.
    CharacterFormManager.getCharacterFormManager().reloadConfig(config)

    precondition(client.clearUserHistory())

    // Some destructors may save the state on storages. To clear the state, we
    // explicitly call destructors before clearing storages.
    FileUtil.unlinkOrLogError(ConfigFileStream.getFileName("user://boundary.db"))
    FileUtil.unlinkOrLogError(ConfigFileStream.getFileName("user://segment.db"))
  }

  public func clearAll() async {
    resetContext()
    await clearUserPrediction()
  }

  public func resetContext() {
    precondition(client.resetContext())
    lastOutput = Genmai_Commands_Output()
  }

  public func syncDataToStorage() async {
    let synced = await client.syncData()
    precondition(synced)
  }

  public func clearUserPrediction() async {
    precondition(client.clearUserPrediction())
    precondition(client.clearUserHistory())
    await syncDataToStorage()
  }

  /// Usage stats are disabled in OSS; nothing to clear.
  public func clearUsageStats() {}

  public func getLastOutput() -> Genmai_Commands_Output { lastOutput }

  public func getCandidateByValue(_ value: String) -> Genmai_Commands_CandidateWord {
    let output = lastOutput

    for candidate in output.allCandidateWords.candidates where candidate.value == value {
      return candidate
    }

    for candidate in output.removedCandidateWordsForDebug.candidates where candidate.value == value {
      return candidate
    }

    return Genmai_Commands_CandidateWord()
  }

  public func getCandidateIdByValue(_ value: String, _ id: inout UInt32) -> Bool {
    let output = lastOutput
    if !output.hasAllCandidateWords {
      return false
    }

    for candidate in output.allCandidateWords.candidates
    where candidate.hasValue && candidate.value == value {
      id = UInt32(bitPattern: candidate.id)
      return true
    }
    return false
  }

  public func getCandidateIdsByValue(_ value: String) -> [UInt32] {
    let output = lastOutput
    if !output.hasAllCandidateWords {
      return []
    }

    var ids: [UInt32] = []
    for candidate in output.allCandidateWords.candidates
    where candidate.hasValue && candidate.value == value {
      ids.append(UInt32(bitPattern: candidate.id))
    }
    return ids
  }

  public func getRemovedCandidateIdsByValue(_ value: String) -> [UInt32] {
    let output = lastOutput
    if !output.hasRemovedCandidateWordsForDebug {
      return []
    }

    var ids: [UInt32] = []
    for candidate in output.removedCandidateWordsForDebug.candidates
    where candidate.hasValue && candidate.value == value {
      ids.append(UInt32(bitPattern: candidate.id))
    }
    return ids
  }

  public func parse(_ line: String) -> [String] {
    var args: [String] = []
    if line.isEmpty || line.utf8.first == UInt8(ascii: "#") {
      return args
    }
    let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
    for var column in columns {
      if column.isEmpty {
        args.append("")
        continue
      }
      // If the first and last characters are doublequotes, trim them.
      if column.utf8.count > 1 && column.utf8.first == UInt8(ascii: "\"")
        && column.utf8.last == UInt8(ascii: "\"")
      {
        column = column.dropFirst().dropLast()
      }
      args.append(String(column))
    }
    return args
  }

  public func eval(_ args: [String]) async throws(SessionHandlerInterpreterError) {
    func assertTrue(_ result: Bool, _ message: @autoclosure () -> String = "")
      throws(SessionHandlerInterpreterError)
    {
      if !result { throw .invalidArgument(message()) }
    }
    func expectTrue(_ result: Bool, _ message: @autoclosure () -> String = "")
      throws(SessionHandlerInterpreterError)
    {
      if !result { throw .internal(message()) }
    }

    if args.isEmpty {
      // Skip empty args
      return
    }

    await syncDataToStorage()

    let command = args[0]
    // TODO(hidehiko): Refactor out about each command when the number of
    //   supported commands is increased.
    if command == "RESET_CONTEXT" {
      try assertTrue(args.count == 1)
      resetContext()
    } else if command == "SEND_KEYS" {
      try assertTrue(args.count == 2)
      let keys = Array(args[1].utf8)
      for i in 0..<keys.count {
        var keyEvent = Genmai_Commands_KeyEvent()
        // set_key_code(char): a negative char wraps around.
        keyEvent.keyCode = UInt32(bitPattern: Int32(Int8(bitPattern: keys[i])))
        try assertTrue(client.sendKey(keyEvent, &lastOutput), "Failed at \(i)th key")
      }
    } else if command == "SEND_KANA_KEYS" {
      try assertTrue(
        args.count >= 3,
        "SEND_KEY requires more than or equal to two args \(args.joined(separator: "\t"))")
      let keys = Array(args[1].utf8)
      let kanas = args[2]
      try assertTrue(
        keys.count == Util.charsLen(kanas),
        "1st and 2nd column must have the same number of characters.")
      for i in 0..<keys.count {
        var keyEvent = Genmai_Commands_KeyEvent()
        keyEvent.keyCode = UInt32(bitPattern: Int32(Int8(bitPattern: keys[i])))
        keyEvent.keyString = String(Util.utf8SubString(kanas, i, 1))
        try assertTrue(
          client.sendKey(keyEvent, &lastOutput),
          "Failed at \(i)th \(args.joined(separator: "\t"))")
      }
    } else if command == "SEND_KEY" {
      try assertTrue(args.count == 2)
      var keyEvent = Genmai_Commands_KeyEvent()
      try assertTrue(KeyParser.parseKey(args[1], &keyEvent))
      try assertTrue(client.sendKey(keyEvent, &lastOutput))
    } else if command == "SEND_KEY_WITH_OPTION" {
      try assertTrue(args.count >= 3)
      var keyEvent = Genmai_Commands_KeyEvent()
      try assertTrue(KeyParser.parseKey(args[1], &keyEvent))
      var option = Genmai_Commands_Input()
      for i in 2..<args.count {
        try assertTrue(parseProtobufFromString(args[i], &option))
      }
      try assertTrue(client.sendKeyWithOption(keyEvent, option, &lastOutput))
    } else if command == "TEST_SEND_KEY" {
      try assertTrue(args.count == 2)
      var keyEvent = Genmai_Commands_KeyEvent()
      try assertTrue(KeyParser.parseKey(args[1], &keyEvent))
      try assertTrue(client.testSendKey(keyEvent, &lastOutput))
    } else if command == "TEST_SEND_KEY_WITH_OPTION" {
      try assertTrue(args.count >= 3)
      var keyEvent = Genmai_Commands_KeyEvent()
      try assertTrue(KeyParser.parseKey(args[1], &keyEvent))
      var option = Genmai_Commands_Input()
      for i in 2..<args.count {
        try assertTrue(parseProtobufFromString(args[i], &option))
      }
      try assertTrue(client.testSendKeyWithOption(keyEvent, option, &lastOutput))
    } else if command == "UPDATE_COMPOSITION" {
      try assertTrue(args.count % 2 == 1)
      try assertTrue(client.updateComposition(args[1...], &lastOutput))
    } else if command == "SELECT_CANDIDATE" {
      try assertTrue(args.count == 2)
      try assertTrue(
        client.selectCandidate(
          UInt32(truncatingIfNeeded: NumberUtil.simpleAtoi(args[1])), &lastOutput))
    } else if command == "SELECT_CANDIDATE_BY_VALUE" {
      try assertTrue(args.count == 2)
      var id: UInt32 = 0
      try assertTrue(getCandidateIdByValue(args[1], &id))
      try assertTrue(client.selectCandidate(id, &lastOutput))
    } else if command == "SUBMIT_CANDIDATE" {
      try assertTrue(args.count == 2)
      try assertTrue(
        client.submitCandidate(
          UInt32(truncatingIfNeeded: NumberUtil.simpleAtoi(args[1])), &lastOutput))
    } else if command == "SUBMIT_CANDIDATE_BY_VALUE" {
      try assertTrue(args.count == 2)
      var id: UInt32 = 0
      try assertTrue(getCandidateIdByValue(args[1], &id))
      try assertTrue(client.submitCandidate(id, &lastOutput))
    } else if command == "UNDO_OR_REWIND" {
      try assertTrue(client.undoOrRewind(&lastOutput))
    } else if command == "DELETE_CANDIDATE_FROM_HISTORY" {
      try assertTrue(args.count == 1 || args.count == 2)
      var id: Int? = nil
      if args.count == 2 {
        id = NumberUtil.simpleAtoi(args[1])
      }
      try assertTrue(client.deleteCandidateFromHistory(id, &lastOutput))
    } else if command == "SWITCH_COMPOSITION_MODE" {
      try assertTrue(args.count == 2)
      guard
        let compositionMode = parseEnum(
          Genmai_Commands_SessionCommand.self, "composition_mode", args[1], { $0.compositionMode })
      else {
        throw .invalidArgument("Unknown CompositionMode")
      }
      try assertTrue(client.switchCompositionMode(compositionMode))
    } else if command == "SET_DEFAULT_REQUEST" {
      request = Genmai_Commands_Request()
      try assertTrue(client.setRequest(request, &lastOutput))
    } else if command == "SET_MOBILE_REQUEST" {
      RequestTestUtil.fillMobileRequest(&request)
      try assertTrue(client.setRequest(request, &lastOutput))
    } else if command == "SET_HANDWRITING_REQUEST" {
      RequestTestUtil.fillMobileRequestForHandwriting(&request)
      try assertTrue(client.setRequest(request, &lastOutput))
    } else if command == "SET_REQUEST" {
      try assertTrue(args.count >= 3)
      try assertTrue(
        setOrAddFieldValueFromString(Array(args[1..<(args.count - 1)]), args.last!, &request))
      try assertTrue(client.setRequest(request, &lastOutput))
    } else if command == "SET_CONFIG" {
      try assertTrue(args.count >= 3)
      try assertTrue(
        setOrAddFieldValueFromString(Array(args[1..<(args.count - 1)]), args.last!, &config))
      try assertTrue(client.setConfig(config, &lastOutput))
    } else if command == "MERGE_DECODER_EXPERIMENT_PARAMS" {
      try assertTrue(args.count == 2)
      let textproto = args[1]
      if !textproto.isEmpty {
        guard let params = try? Genmai_Commands_DecoderExperimentParams(textFormatString: textproto)
        else {
          preconditionFailure("Invalid DecoderExperimentParams: \(textproto)")
        }
        mergeFrom(&request.decoderExperimentParams, params)
        try assertTrue(client.setRequest(request, &lastOutput))
      }
    } else if command == "SET_SELECTION_TEXT" {
      try assertTrue(args.count == 2)
      client.setCallbackText(args[1])
    } else if command == "UPDATE_MOBILE_KEYBOARD" {
      try assertTrue(args.count == 3)
      guard
        let specialRomanjiTable = parseEnum(
          Genmai_Commands_Request.self, "special_romanji_table", args[1], { $0.specialRomanjiTable })
      else {
        throw .invalidArgument("Unknown SpecialRomanjiTable")
      }
      guard
        let spaceOnAlphanumeric = parseEnum(
          Genmai_Commands_Request.self, "space_on_alphanumeric", args[2], { $0.spaceOnAlphanumeric })
      else {
        throw .invalidArgument("Unknown SpaceOnAlphanumeric")
      }
      request.specialRomanjiTable = specialRomanjiTable
      request.spaceOnAlphanumeric = spaceOnAlphanumeric
      try assertTrue(client.setRequest(request, &lastOutput))
    } else if command == "CLEAR_ALL" {
      try assertTrue(args.count == 1)
      await clearAll()
    } else if command == "CLEAR_USER_PREDICTION" {
      try assertTrue(args.count == 1)
      await clearUserPrediction()
    } else if command == "EXPECT_CONSUMED" {
      try assertTrue(args.count == 2)
      try assertTrue(lastOutput.hasConsumed)
      try expectTrue(lastOutput.consumed == (args[1] == "true"))
    } else if command == "EXPECT_PREEDIT" {
      // Concat preedit segments and assert.
      let expectedPreedit = TextNormalizer.normalizeText(args.count == 1 ? "" : args[1])
      var preeditString = ""
      let preedit = lastOutput.preedit
      for segment in preedit.segment {
        preeditString += segment.value
      }
      try expectTrue(
        preeditString == expectedPreedit,
        "Expected preedit: \(expectedPreedit)\nActual preedit: \(toTextFormat(preedit))")
    } else if command == "EXPECT_PREEDIT_IN_DETAIL" {
      try assertTrue(!args.isEmpty)
      let preedit = lastOutput.preedit
      try assertTrue(preedit.segment.count == args.count - 1)
      for i in 0..<preedit.segment.count {
        try expectTrue(
          preedit.segment[i].value == TextNormalizer.normalizeText(args[i + 1]),
          "Segment index = \(i)")
      }
    } else if command == "EXPECT_PREEDIT_CURSOR_POS" {
      // Concat preedit segments and assert.
      try assertTrue(args.count == 2)
      let expectedPos = NumberUtil.simpleAtoi(args[1])
      let preedit = lastOutput.preedit
      try expectTrue(Int(preedit.cursor) == expectedPos, toTextFormat(preedit))
    } else if command == "EXPECT_CANDIDATE" {
      try assertTrue(args.count == 3)
      var candidateId: UInt32 = 0
      let hasResult = getCandidateIdByValue(args[2], &candidateId)
      try expectTrue(
        hasResult, "\(args[2]) is not found\n\(toTextFormat(lastOutput.candidateWindow))")
      if hasResult {
        try expectTrue(
          candidateId == UInt32(truncatingIfNeeded: NumberUtil.simpleAtoi(args[1])),
          "\(args[1]) is not found\n\(toTextFormat(lastOutput.candidateWindow))")
      }
    } else if command == "EXPECT_CANDIDATE_DESCRIPTION" {
      try assertTrue(args.count == 3)
      let cand = getCandidateByValue(args[1])
      let hasCand = !cand.value.isEmpty
      try expectTrue(
        hasCand, "\(args[1]) is not found\n\(toTextFormat(lastOutput.candidateWindow))")
      try expectTrue(hasCand)
      try expectTrue(cand.annotation.description_p == args[2], toTextFormat(cand))
    } else if command == "EXPECT_RESULT" {
      if args.count == 2 && !args[1].isEmpty {
        try assertTrue(lastOutput.hasResult)
        let result = lastOutput.result
        try expectTrue(
          result.value == TextNormalizer.normalizeText(args[1]), toTextFormat(result))
      } else {
        try expectTrue(!lastOutput.hasResult, toTextFormat(lastOutput.result))
      }
    } else if command == "EXPECT_IN_ALL_CANDIDATE_WORDS" {
      try assertTrue(args.count == 2)
      var candidateId: UInt32 = 0
      let hasResult = getCandidateIdByValue(args[1], &candidateId)
      try expectTrue(hasResult, "\(args[1]) is not found.\n\(toTextFormat(lastOutput))")
    } else if command == "EXPECT_NOT_IN_ALL_CANDIDATE_WORDS" {
      try assertTrue(args.count == 2)
      var candidateId: UInt32 = 0
      let hasResult = getCandidateIdByValue(args[1], &candidateId)
      try expectTrue(!hasResult, "\(args[1]) is found.\n\(toTextFormat(lastOutput))")
    } else if command == "EXPECT_HAS_CANDIDATES" {
      if args.count == 2 && !args[1].isEmpty {
        try assertTrue(lastOutput.hasCandidateWindow)
        try assertTrue(
          Int(lastOutput.candidateWindow.size) > NumberUtil.simpleAtoi(args[1]),
          toTextFormat(lastOutput))
      } else {
        try assertTrue(lastOutput.hasCandidateWindow)
      }
    } else if command == "EXPECT_NO_CANDIDATES" {
      try assertTrue(!lastOutput.hasCandidateWindow)
    } else if command == "EXPECT_SEGMENTS_SIZE" {
      try assertTrue(args.count == 2)
      try assertTrue(lastOutput.preedit.segment.count == NumberUtil.simpleAtoi(args[1]))
    } else if command == "EXPECT_HIGHLIGHTED_SEGMENT_INDEX" {
      try assertTrue(args.count == 2)
      try assertTrue(lastOutput.hasPreedit)
      let preedit = lastOutput.preedit
      var index = -1
      for i in 0..<preedit.segment.count where preedit.segment[i].annotation == .highlight {
        index = i
        break
      }
      try assertTrue(index == NumberUtil.simpleAtoi(args[1]))
    } else {
      throw .unimplemented
    }
  }

  public func setRequest(_ request: Genmai_Commands_Request) {
    self.request = request
  }

  public func reloadSupplementalModel(_ modelPath: String) {
    client.reloadSupplementalModel(modelPath)
  }
}
