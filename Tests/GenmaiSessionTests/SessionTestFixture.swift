// Port of the fixture and helpers of mozc/src/session/session_test.cc
// (3.35.6354), plus the test doubles it uses:
// - converter/converter_mock.h (MockConverter; a copy of
//   Tests/GenmaiCoreTests/Converter/ConverterMock.swift, test targets cannot
//   share code),
// - engine/engine_mock.h (MockEngine).
//
// gMock expectations are expressed with handlers and call counters:
//   EXPECT_CALL(*converter, StartConversion(_, _))
//       .WillOnce(DoAll(SetArgPointee<1>(segments), Return(true)));
// becomes `converter.setStartConversion(segments, true)`.
// `Mock::VerifyAndClearExpectations(converter)` becomes `converter.clear()`.
//
// The C++ fixture class `SessionTest` becomes `SessionTestFixture`; each Swift
// test creates its own instance inside `withScopedSessionEnvironment`.

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import Testing

@testable import GenmaiSession

// MARK: - MockConverter (converter/converter_mock.h)

/// NiceMock<StrictMockConverter>: unset handlers return false / do nothing.
/// `@unchecked Sendable`: a test double with mutable handlers / records, set and used on the test's own task only.
final class MockConverter: ConverterInterface, @unchecked Sendable {
  var startConversionHandler: ((ConversionRequest, Segments) -> Bool)?
  var startReverseConversionHandler: ((Segments, String) -> Bool)?
  var startPredictionHandler: ((ConversionRequest, Segments) -> Bool)?
  var startPredictionWithPreviousSuggestionHandler: ((ConversionRequest, Segment, Segments) -> Bool)?
  var prependCandidatesHandler: ((ConversionRequest, Segment, Segments) -> Void)?
  var finishConversionHandler: ((ConversionRequest, Segments) -> Void)?
  var cancelConversionHandler: ((Segments) -> Void)?
  var resetConversionHandler: ((Segments) -> Void)?
  var revertConversionHandler: ((Segments) -> Void)?
  var deleteCandidateFromHistoryHandler: ((Segments, Int, Int) -> Bool)?
  var reconstructHistoryHandler: ((Segments, String) -> Bool)?
  var commitSegmentValueHandler: ((Segments, Int, Int) -> Bool)?
  var commitPartialSuggestionSegmentValueHandler: ((Segments, Int, Int, String, String) -> Bool)?
  var focusSegmentValueHandler: ((Segments, Int, Int) -> Bool)?
  var commitSegmentsHandler: ((Segments, [Int]) -> Bool)?
  var resizeSegmentHandler: ((Segments, ConversionRequest, Int, Int) -> Bool)?
  var resizeSegmentsHandler: ((Segments, ConversionRequest, Int, [UInt8]) -> Bool)?
  var commitContextHandler: ((ConversionRequest) -> Void)?

  /// Mock::VerifyAndClearExpectations: removes all handlers.
  func clear() {
    startConversionHandler = nil
    startReverseConversionHandler = nil
    startPredictionHandler = nil
    startPredictionWithPreviousSuggestionHandler = nil
    prependCandidatesHandler = nil
    finishConversionHandler = nil
    cancelConversionHandler = nil
    resetConversionHandler = nil
    revertConversionHandler = nil
    deleteCandidateFromHistoryHandler = nil
    reconstructHistoryHandler = nil
    commitSegmentValueHandler = nil
    commitPartialSuggestionSegmentValueHandler = nil
    focusSegmentValueHandler = nil
    commitSegmentsHandler = nil
    resizeSegmentHandler = nil
    resizeSegmentsHandler = nil
    commitContextHandler = nil
  }

  /// `DoAll(SetArgPointee<1>(segments), Return(result))` for StartConversion.
  func setStartConversion(_ segments: Segments, _ result: Bool) {
    let copy = Segments()
    copy.assign(from: segments)
    startConversionHandler = { _, out in
      out.assign(from: copy)
      return result
    }
  }

  /// `DoAll(SetArgPointee<1>(segments), Return(result))` for StartPrediction.
  func setStartPrediction(_ segments: Segments, _ result: Bool) {
    let copy = Segments()
    copy.assign(from: segments)
    startPredictionHandler = { _, out in
      out.assign(from: copy)
      return result
    }
  }

  /// `DoAll(SetArgPointee<2>(segments), Return(result))` for
  /// StartPredictionWithPreviousSuggestion.
  func setStartPredictionWithPreviousSuggestion(_ segments: Segments, _ result: Bool) {
    let copy = Segments()
    copy.assign(from: segments)
    startPredictionWithPreviousSuggestionHandler = { _, _, out in
      out.assign(from: copy)
      return result
    }
  }

  /// `DoAll(SetArgPointee<0>(segments), Return(result))` for
  /// StartReverseConversion.
  func setStartReverseConversion(_ segments: Segments, _ result: Bool) {
    let copy = Segments()
    copy.assign(from: segments)
    startReverseConversionHandler = { out, _ in
      out.assign(from: copy)
      return result
    }
  }

  /// `DoAll(SetArgPointee<0>(segments), Return(result))` for CommitSegmentValue.
  func setCommitSegmentValue(_ segments: Segments, _ result: Bool) {
    let copy = Segments()
    copy.assign(from: segments)
    commitSegmentValueHandler = { out, _, _ in
      out.assign(from: copy)
      return result
    }
  }

  /// `DoAll(SetArgPointee<0>(segments), Return(result))` for
  /// CommitPartialSuggestionSegmentValue.
  func setCommitPartialSuggestionSegmentValue(_ segments: Segments, _ result: Bool) {
    let copy = Segments()
    copy.assign(from: segments)
    commitPartialSuggestionSegmentValueHandler = { out, _, _, _, _ in
      out.assign(from: copy)
      return result
    }
  }

  /// `DoAll(SetArgPointee<0>(segments), Return(result))` for FocusSegmentValue.
  func setFocusSegmentValue(_ segments: Segments, _ result: Bool) {
    let copy = Segments()
    copy.assign(from: segments)
    focusSegmentValueHandler = { out, _, _ in
      out.assign(from: copy)
      return result
    }
  }

  /// `DoAll(SetArgPointee<0>(segments), Return(result))` for CommitSegments.
  func setCommitSegments(_ segments: Segments, _ result: Bool) {
    let copy = Segments()
    copy.assign(from: segments)
    commitSegmentsHandler = { out, _ in
      out.assign(from: copy)
      return result
    }
  }

  /// `DoAll(SetArgPointee<0>(segments), Return(result))` for ResizeSegment.
  func setResizeSegment(_ segments: Segments, _ result: Bool) {
    let copy = Segments()
    copy.assign(from: segments)
    resizeSegmentHandler = { out, _, _, _ in
      out.assign(from: copy)
      return result
    }
  }

  /// `DoAll(SetArgPointee<0>(segments), Return(result))` for ResizeSegments.
  func setResizeSegments(_ segments: Segments, _ result: Bool) {
    let copy = Segments()
    copy.assign(from: segments)
    resizeSegmentsHandler = { out, _, _, _ in
      out.assign(from: copy)
      return result
    }
  }

  func startConversion(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    startConversionHandler?(request, segments) ?? false
  }
  func startReverseConversion(_ segments: Segments, _ key: String) -> Bool {
    startReverseConversionHandler?(segments, key) ?? false
  }
  func startPrediction(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    startPredictionHandler?(request, segments) ?? false
  }
  func startPredictionWithPreviousSuggestion(
    _ request: ConversionRequest, _ previousSegment: Segment, _ segments: Segments
  ) -> Bool {
    startPredictionWithPreviousSuggestionHandler?(request, previousSegment, segments) ?? false
  }
  func prependCandidates(_ request: ConversionRequest, _ segment: Segment, _ segments: Segments) {
    prependCandidatesHandler?(request, segment, segments)
  }
  func finishConversion(_ request: ConversionRequest, _ segments: Segments) {
    finishConversionHandler?(request, segments)
  }
  func cancelConversion(_ segments: Segments) { cancelConversionHandler?(segments) }
  func resetConversion(_ segments: Segments) { resetConversionHandler?(segments) }
  func revertConversion(_ segments: Segments) { revertConversionHandler?(segments) }
  func deleteCandidateFromHistory(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int)
    -> Bool
  {
    deleteCandidateFromHistoryHandler?(segments, segmentIndex, candidateIndex) ?? false
  }
  func reconstructHistory(_ segments: Segments, _ precedingText: String) -> Bool {
    reconstructHistoryHandler?(segments, precedingText) ?? false
  }
  func commitSegmentValue(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int) -> Bool {
    commitSegmentValueHandler?(segments, segmentIndex, candidateIndex) ?? false
  }
  func commitPartialSuggestionSegmentValue(
    _ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int,
    _ currentSegmentKey: String, _ newSegmentKey: String
  ) -> Bool {
    commitPartialSuggestionSegmentValueHandler?(
      segments, segmentIndex, candidateIndex, currentSegmentKey, newSegmentKey) ?? false
  }
  func focusSegmentValue(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int) -> Bool {
    focusSegmentValueHandler?(segments, segmentIndex, candidateIndex) ?? false
  }
  func commitSegments(_ segments: Segments, _ candidateIndex: [Int]) -> Bool {
    commitSegmentsHandler?(segments, candidateIndex) ?? false
  }
  func resizeSegment(
    _ segments: Segments, _ request: ConversionRequest, _ segmentIndex: Int, _ offsetLength: Int
  ) -> Bool {
    resizeSegmentHandler?(segments, request, segmentIndex, offsetLength) ?? false
  }
  func resizeSegments(
    _ segments: Segments, _ request: ConversionRequest, _ startSegmentIndex: Int,
    _ newSizeArray: [UInt8]
  ) -> Bool {
    resizeSegmentsHandler?(segments, request, startSegmentIndex, newSizeArray) ?? false
  }
  func commitContext(_ request: ConversionRequest) { commitContextHandler?(request) }
}

// MARK: - MockEngine (engine/engine_mock.h)

/// gMock MockEngine (a NiceMock-like test double). Every requirement is
/// implemented here (protocol default dispatch pitfall).
/// `@unchecked Sendable`: a test double with mutable handlers / records, set and used on the test's own task only.
final class MockEngine: EngineInterface, @unchecked Sendable {
  var getDataVersionHandler: (() -> String)?
  var createEngineConverterHandler: (() -> any EngineConverterInterface)?
  var reloadHandler: (() -> Bool)?
  var syncHandler: (() -> Bool)?
  var waitHandler: (() -> Bool)?
  var clearUserHistoryHandler: (() -> Bool)?
  var clearUserPredictionHandler: (() -> Bool)?
  var reloadAndWaitHandler: (() -> Bool)?
  var getPosListHandler: (() -> [String])?
  var maybeReloadEngineHandler: ((inout Genmai_EngineReloadResponse) -> Bool)?
  var sendEngineReloadRequestHandler: ((Genmai_EngineReloadRequest) -> Bool)?
  var sendSupplementalModelReloadRequestHandler: ((Genmai_EngineReloadRequest) -> Bool)?

  var reloadCount = 0
  var syncCount = 0
  var waitCount = 0
  var clearUserHistoryCount = 0
  var clearUserPredictionCount = 0
  var reloadAndWaitCount = 0
  var createEngineConverterCount = 0

  func createEngineConverter() -> any EngineConverterInterface {
    createEngineConverterCount += 1
    guard let handler = createEngineConverterHandler else {
      preconditionFailure("MockEngine.createEngineConverter is not set")
    }
    return handler()
  }
  func getDataVersion() -> String { getDataVersionHandler?() ?? "" }
  func reload() -> Bool {
    reloadCount += 1
    return reloadHandler?() ?? false
  }
  func sync() -> Bool {
    syncCount += 1
    return syncHandler?() ?? false
  }
  func wait() -> Bool {
    waitCount += 1
    return waitHandler?() ?? false
  }
  func reloadAndWait() -> Bool {
    reloadAndWaitCount += 1
    return reloadAndWaitHandler?() ?? false
  }
  func clearUserHistory() -> Bool {
    clearUserHistoryCount += 1
    return clearUserHistoryHandler?() ?? false
  }
  func clearUserPrediction() -> Bool {
    clearUserPredictionCount += 1
    return clearUserPredictionHandler?() ?? false
  }
  func addUserHistory(_ key: String, _ value: String) -> Bool { true }
  func getPosList() -> [String] { getPosListHandler?() ?? [] }
  func maybeReloadEngine(_ response: inout Genmai_EngineReloadResponse) -> Bool {
    maybeReloadEngineHandler?(&response) ?? false
  }
  func clearOldSupplementalModels() {}
  func sendEngineReloadRequest(_ request: Genmai_EngineReloadRequest) -> Bool {
    sendEngineReloadRequestHandler?(request) ?? false
  }
  func sendSupplementalModelReloadRequest(_ request: Genmai_EngineReloadRequest) -> Bool {
    sendSupplementalModelReloadRequestHandler?(request) ?? false
  }
}

// MARK: - SessionTestPeer

struct SessionTestPeer {
  let session: Session
  init(_ session: Session) { self.session = session }

  func isFullWidthInsertSpace(_ input: Genmai_Commands_Input) -> Bool {
    session.isFullWidthInsertSpace(input)
  }
  func pushUndoContext() { session.pushUndoContext() }

  var context: ImeContext {
    get { session.contextImpl }
    nonmutating set { session.contextImpl = newValue }
  }
  var undoContexts: [ImeContext] {
    get { session.undoContexts }
    nonmutating set { session.undoContexts = newValue }
  }
}

// MARK: - Free helpers (anonymous namespace of session_test.cc)

func setSendKeyCommandWithKeyString(_ keyString: String, _ command: inout Genmai_Commands_Command) {
  command = Genmai_Commands_Command()
  command.input.type = .sendKey
  command.input.key.keyString = keyString
}

@discardableResult
func setSendKeyCommand(_ key: String, _ command: inout Genmai_Commands_Command) -> Bool {
  command = Genmai_Commands_Command()
  command.input.type = .sendKey
  return KeyParser.parseKey(key, &command.input.key)
}

@discardableResult
func sendKey(_ key: String, _ session: Session, _ command: inout Genmai_Commands_Command) -> Bool {
  if !setSendKeyCommand(key, &command) {
    return false
  }
  return session.sendKey(&command)
}

@discardableResult
func sendKeyWithMode(
  _ key: String, _ mode: Genmai_Commands_CompositionMode, _ session: Session,
  _ command: inout Genmai_Commands_Command
) -> Bool {
  if !setSendKeyCommand(key, &command) {
    return false
  }
  command.input.key.mode = mode
  return session.sendKey(&command)
}

@discardableResult
func sendKeyWithModeAndActivated(
  _ key: String, _ activated: Bool, _ mode: Genmai_Commands_CompositionMode, _ session: Session,
  _ command: inout Genmai_Commands_Command
) -> Bool {
  if !setSendKeyCommand(key, &command) {
    return false
  }
  command.input.key.activated = activated
  command.input.key.mode = mode
  return session.sendKey(&command)
}

@discardableResult
func testSendKey(_ key: String, _ session: Session, _ command: inout Genmai_Commands_Command)
  -> Bool
{
  if !setSendKeyCommand(key, &command) {
    return false
  }
  return session.testSendKey(&command)
}

@discardableResult
func testSendKeyWithMode(
  _ key: String, _ mode: Genmai_Commands_CompositionMode, _ session: Session,
  _ command: inout Genmai_Commands_Command
) -> Bool {
  if !setSendKeyCommand(key, &command) {
    return false
  }
  command.input.key.mode = mode
  return session.testSendKey(&command)
}

@discardableResult
func testSendKeyWithModeAndActivated(
  _ key: String, _ activated: Bool, _ mode: Genmai_Commands_CompositionMode, _ session: Session,
  _ command: inout Genmai_Commands_Command
) -> Bool {
  if !setSendKeyCommand(key, &command) {
    return false
  }
  command.input.key.activated = activated
  command.input.key.mode = mode
  return session.testSendKey(&command)
}

@discardableResult
func sendSpecialKey(
  _ specialKey: Genmai_Commands_KeyEvent.SpecialKey, _ session: Session,
  _ command: inout Genmai_Commands_Command
) -> Bool {
  command = Genmai_Commands_Command()
  command.input.type = .sendKey
  command.input.key.specialKey = specialKey
  return session.sendKey(&command)
}

func setSendCommandCommand(
  _ type: Genmai_Commands_SessionCommand.CommandType, _ command: inout Genmai_Commands_Command
) {
  command = Genmai_Commands_Command()
  command.input.type = .sendCommand
  command.input.command.type = type
}

@discardableResult
func sendCommand(
  _ type: Genmai_Commands_SessionCommand.CommandType, _ session: Session,
  _ command: inout Genmai_Commands_Command
) -> Bool {
  setSendCommandCommand(type, &command)
  return session.sendCommand(&command)
}

/// `key_code` is a C++ `char`.
@discardableResult
func insertCharacterCodeAndString(
  _ keyCode: Character, _ keyString: String, _ session: Session,
  _ command: inout Genmai_Commands_Command
) -> Bool {
  command = Genmai_Commands_Command()
  guard let ascii = keyCode.asciiValue else {
    Issue.record("not an ASCII key code: \(keyCode)")
    return false
  }
  command.input.key.keyCode = UInt32(ascii)
  command.input.key.keyString = keyString
  return session.insertCharacter(&command)
}

@discardableResult
func addCandidate(_ key: String, _ value: String, _ segment: Segment) -> Candidate {
  let candidate = segment.addCandidate()
  candidate.key = key
  candidate.contentKey = key
  candidate.value = value
  return candidate
}

@discardableResult
func addMetaCandidate(_ key: String, _ value: String, _ segment: Segment) -> Candidate {
  let candidate = segment.addMetaCandidate()
  candidate.key = key
  candidate.contentKey = key
  candidate.value = value
  return candidate
}

func getComposition(_ command: Genmai_Commands_Command) -> String {
  if !command.output.hasPreedit {
    return ""
  }
  var preedit = ""
  for segment in command.output.preedit.segment {
    preedit += segment.value
  }
  return preedit
}

/// EnsurePreedit: nil on success, failure message otherwise.
func ensurePreedit(_ expected: String, _ command: Genmai_Commands_Command) -> String? {
  if !command.output.hasPreedit {
    return "No preedit."
  }
  var actual = ""
  for segment in command.output.preedit.segment {
    actual += segment.value
  }
  if expected == actual {
    return nil
  }
  return "expected: \(expected), actual: \(actual)"
}

func ensureSingleSegment(_ expected: String, _ command: Genmai_Commands_Command) -> String? {
  if !command.output.hasPreedit {
    return "No preedit."
  }
  if command.output.preedit.segment.count != 1 {
    return "Not single segment. segment size: \(command.output.preedit.segment.count)"
  }
  let segment = command.output.preedit.segment[0]
  if !segment.hasValue {
    return "No segment value."
  }
  let actual = segment.value
  if expected == actual {
    return nil
  }
  return "expected: \(expected), actual: \(actual)"
}

func ensureSingleSegmentAndKey(
  _ expectedValue: String, _ expectedKey: String, _ command: Genmai_Commands_Command
) -> String? {
  if !command.output.hasPreedit {
    return "No preedit."
  }
  if command.output.preedit.segment.count != 1 {
    return "Not single segment. segment size: \(command.output.preedit.segment.count)"
  }
  let segment = command.output.preedit.segment[0]
  if !segment.hasValue {
    return "No segment value."
  }
  if !segment.hasKey {
    return "No segment key."
  }
  let actualValue = segment.value
  let actualKey = segment.key
  if expectedValue == actualValue && expectedKey == actualKey {
    return nil
  }
  return
    "expected_value: \(expectedValue), actual_value: \(actualValue), expected_key: \(expectedKey), actual_key: \(actualKey)"
}

func ensureResult(_ expected: String, _ command: Genmai_Commands_Command) -> String? {
  if !command.output.hasResult {
    return "No result."
  }
  if !command.output.result.hasValue {
    return "No result value."
  }
  let actual = command.output.result.value
  if expected == actual {
    return nil
  }
  return "expected: \(expected), actual: \(actual)"
}

func ensureResultAndKey(
  _ expectedValue: String, _ expectedKey: String, _ command: Genmai_Commands_Command
) -> String? {
  if !command.output.hasResult {
    return "No result."
  }
  if !command.output.result.hasValue {
    return "No result value."
  }
  if !command.output.result.hasKey {
    return "No result value."
  }
  let actualValue = command.output.result.value
  let actualKey = command.output.result.key
  if expectedValue == actualValue && expectedKey == actualKey {
    return nil
  }
  return
    "expected_value: \(expectedValue), actual_value: \(actualValue), expected_key: \(expectedKey), actual_key: \(actualKey)"
}

func tryUndoAndAssertSuccess(_ session: Session) -> String? {
  var command = Genmai_Commands_Command()
  session.requestUndo(&command)
  if !command.output.consumed {
    return "Not consumed."
  }
  if !command.output.hasCallback {
    return "No callback."
  }
  if command.output.callback.sessionCommand.type != .undo {
    return
      "Callback type is not Undo. Actual type: \(command.output.callback.sessionCommand.type)"
  }
  return nil
}

func tryUndoAndAssertDoNothing(_ session: Session) -> String? {
  var command = Genmai_Commands_Command()
  session.requestUndo(&command)
  if command.output.consumed {
    return "Key event is consumed against expectation."
  }
  return nil
}

/// EXPECT_PREEDIT(expected, command)
func expectPreedit(
  _ expected: String, _ command: Genmai_Commands_Command, sourceLocation: SourceLocation = #_sourceLocation
) {
  let failure = ensurePreedit(expected, command)
  #expect(failure == nil, Comment(rawValue: failure ?? ""), sourceLocation: sourceLocation)
}

/// EXPECT_SINGLE_SEGMENT(expected, command)
func expectSingleSegment(
  _ expected: String, _ command: Genmai_Commands_Command, sourceLocation: SourceLocation = #_sourceLocation
) {
  let failure = ensureSingleSegment(expected, command)
  #expect(failure == nil, Comment(rawValue: failure ?? ""), sourceLocation: sourceLocation)
}

/// EXPECT_SINGLE_SEGMENT_AND_KEY(expected_value, expected_key, command)
func expectSingleSegmentAndKey(
  _ expectedValue: String, _ expectedKey: String, _ command: Genmai_Commands_Command,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  let failure = ensureSingleSegmentAndKey(expectedValue, expectedKey, command)
  #expect(failure == nil, Comment(rawValue: failure ?? ""), sourceLocation: sourceLocation)
}

/// EXPECT_RESULT(expected, command)
func expectResult(
  _ expected: String, _ command: Genmai_Commands_Command, sourceLocation: SourceLocation = #_sourceLocation
) {
  let failure = ensureResult(expected, command)
  #expect(failure == nil, Comment(rawValue: failure ?? ""), sourceLocation: sourceLocation)
}

/// EXPECT_RESULT_AND_KEY(expected_value, expected_key, command)
func expectResultAndKey(
  _ expectedValue: String, _ expectedKey: String, _ command: Genmai_Commands_Command,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  let failure = ensureResultAndKey(expectedValue, expectedKey, command)
  #expect(failure == nil, Comment(rawValue: failure ?? ""), sourceLocation: sourceLocation)
}

func switchInputFieldType(
  _ type: Genmai_Commands_Context.InputFieldType, _ session: Session,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  var command = Genmai_Commands_Command()
  setSendCommandCommand(.switchInputFieldType, &command)
  command.input.context.inputFieldType = type
  #expect(session.sendCommand(&command), sourceLocation: sourceLocation)
  #expect(session.context.composer.getInputFieldType() == type, sourceLocation: sourceLocation)
}

@discardableResult
func switchCompositionModeCommand(
  _ mode: Genmai_Commands_CompositionMode, _ session: Session, _ command: inout Genmai_Commands_Command
) -> Bool {
  setSendCommandCommand(.switchCompositionMode, &command)
  command.input.command.compositionMode = mode
  return session.sendCommand(&command)
}

func switchCompositionMode(
  _ mode: Genmai_Commands_CompositionMode, _ session: Session,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  var command = Genmai_Commands_Command()
  #expect(switchCompositionModeCommand(mode, session, &command), sourceLocation: sourceLocation)
}

// MARK: - SessionTestFixture (class SessionTest)

final class SessionTestFixture {
  let mobileRequest: Genmai_Commands_Request
  let mockDataManager: DataManager
  let t13nRewriter: TransliterationRewriter
  private var mockDataEngineImpl: Engine?

  init() throws {
    var request = Genmai_Commands_Request()
    RequestTestUtil.fillMobileRequest(&request)
    mobileRequest = request

    mockDataManager = try MockDataManager.create()
    t13nRewriter = TransliterationRewriter(PosMatcher(mockDataManager.getPosMatcherData()))
  }

  /// mock_data_engine_ (created lazily: building the full engine is costly
  /// and only some tests use it).
  func mockDataEngine() throws -> Engine {
    if let engine = mockDataEngineImpl {
      return engine
    }
    let engine = try MockDataEngineFactory.create()
    mockDataEngineImpl = engine
    return engine
  }

  func insertCharacterChars(
    _ chars: String, _ session: Session, _ command: inout Genmai_Commands_Command
  ) {
    let kNoModifiers: UInt32 = 0
    for c in chars.utf8 {
      command = Genmai_Commands_Command()
      command.input.type = .sendKey
      command.input.key.keyCode = UInt32(bitPattern: Int32(Int8(bitPattern: c)))
      command.input.key.modifiers = kNoModifiers
      session.sendKey(&command)
    }
  }

  func insertCharacterCharsWithContext(
    _ chars: String, _ context: Genmai_Commands_Context, _ session: Session,
    _ command: inout Genmai_Commands_Command
  ) {
    let kNoModifiers: UInt32 = 0
    for c in chars.utf8 {
      command = Genmai_Commands_Command()
      command.input.type = .sendKey
      command.input.context = context
      command.input.key.keyCode = UInt32(bitPattern: Int32(Int8(bitPattern: c)))
      command.input.key.modifiers = kNoModifiers
      session.sendKey(&command)
    }
  }

  func insertCharacterString(
    _ keyStrings: String, _ chars: String, _ session: Session,
    _ command: inout Genmai_Commands_Command
  ) {
    let kNoModifiers: UInt32 = 0
    var charsIt = Array(chars.utf8).makeIterator()
    for key in keyStrings.unicodeScalars {
      guard let c = charsIt.next() else {
        preconditionFailure("chars is shorter than key_strings")
      }
      command = Genmai_Commands_Command()
      command.input.type = .sendKey
      command.input.key.keyCode = UInt32(bitPattern: Int32(Int8(bitPattern: c)))
      command.input.key.modifiers = kNoModifiers
      command.input.key.keyString = String(key)
      session.sendKey(&command)
    }
  }

  func setAiueo(_ segments: Segments) {
    segments.clear()
    let segment = segments.addSegment()
    segment.setKey("あいうえお")
    var candidate = segment.addCandidate()
    candidate.key = "あいうえお"
    candidate.contentKey = "あいうえお"
    candidate.value = "あいうえお"
    candidate = segment.addCandidate()
    candidate.key = "あいうえお"
    candidate.contentKey = "あいうえお"
    candidate.value = "アイウエオ"
  }

  func initSessionToDirect(_ session: Session) {
    initSessionToPrecomposition(session)
    var command = Genmai_Commands_Command()
    session.imeOff(&command)
  }

  func initSessionToConversionWithAiueo(
    _ session: Session, _ converter: MockConverter,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    initSessionToPrecomposition(session)

    var command = Genmai_Commands_Command()
    insertCharacterChars("aiueo", session, &command)
    let request = createConversionRequest(session)
    let segments = Segments()
    setAiueo(segments)
    fillT13Ns(request, segments)
    converter.setStartConversion(segments, true)

    command = Genmai_Commands_Command()
    #expect(session.convert(&command), sourceLocation: sourceLocation)
    #expect(session.context.state == .conversion, sourceLocation: sourceLocation)
    converter.clear()
  }

  func createEngineConverterMock(_ mockEngine: MockEngine) -> MockConverter {
    let mockConverter = MockConverter()
    mockEngine.createEngineConverterHandler = {
      EngineConverter(mockConverter)
    }
    return mockConverter
  }

  func initSessionToPrecomposition(_ session: Session) {
    initSessionWithRequest(session, Genmai_Commands_Request())
  }

  func initSessionToPrecomposition(_ session: Session, _ request: Genmai_Commands_Request) {
    initSessionWithRequest(session, request)
  }

  func initSessionWithRequest(_ session: Session, _ request: Genmai_Commands_Request) {
    session.setRequest(request)
    let table = Table()
    table.initializeWithRequestAndConfig(request, ConfigHandler.defaultConfig())
    session.setTable(table)
  }

  func setLike(_ segments: Segments) {
    segments.clear()
    var segment = segments.addSegment()

    segment.setKey("ぃ")
    var candidate = segment.addCandidate()
    candidate.value = "ぃ"

    candidate = segment.addCandidate()
    candidate.value = "ィ"

    segment = segments.addSegment()
    segment.setKey("け")
    candidate = segment.addCandidate()
    candidate.value = "家"
    candidate = segment.addCandidate()
    candidate.value = "け"
  }

  func fillT13Ns(_ request: ConversionRequest, _ segments: Segments) {
    _ = t13nRewriter.rewrite(request, segments)
  }

  func createConversionRequest(_ session: Session) -> ConversionRequest {
    let context = session.context
    return ConversionRequestBuilder()
      .setComposer(context.composer)
      .setRequestView(context.getRequest())
      .setContextView(context.clientContext)
      .setConfigView(context.getConfig())
      .build()
  }

  func setupMockForReverseConversion(
    _ kanji: String, _ hiragana: String, _ converter: MockConverter
  ) {
    let reverseSegments = Segments()
    var segment = reverseSegments.addSegment()
    segment.setKey(kanji)
    var candidate = segment.addCandidate()
    candidate.key = kanji
    candidate.value = hiragana
    converter.setStartReverseConversion(reverseSegments, true)
    let segments = Segments()
    segment = segments.addSegment()
    segment.setKey(hiragana)
    candidate = segment.addCandidate()
    candidate.key = hiragana
    candidate.value = kanji
    converter.setStartConversion(segments, true)
  }

  func setupCommandForReverseConversion(_ text: String, _ input: inout Genmai_Commands_Input) {
    input = Genmai_Commands_Input()
    input.type = .sendCommand
    input.command.type = .convertReverse
    input.command.text = text
  }
  func setupZeroQuerySuggestionReady(
    _ enable: Bool, _ session: Session, _ request: inout Genmai_Commands_Request,
    _ mockConverter: MockConverter
  ) {
    initSessionToPrecomposition(session)

    // Enable zero query suggest.
    request.zeroQuerySuggestion = enable
    session.setRequest(request)

    // Type "google".
    var command = Genmai_Commands_Command()
    insertCharacterChars("google", session, &command)

    do {
      // Set up a mock conversion result.
      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey("google")
      segment.addCandidate().value = "GOOGLE"
      mockConverter.setStartConversion(segments, true)
    }
    command = Genmai_Commands_Command()
    session.convert(&command)

    do {
      // Set up a mock suggestion result.
      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey("")
      addCandidate("search", "search", segment)
      addCandidate("input", "input", segment)
      mockConverter.setStartPrediction(segments, true)
    }

    do {
      // Set up a mock prediction result.
      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey("")
      addCandidate("search", "search", segment)
      addCandidate("input", "input", segment)
      mockConverter.setStartPredictionWithPreviousSuggestion(segments, true)
      let copy = Segments()
      copy.assign(from: segments)
      mockConverter.prependCandidatesHandler = { _, _, out in
        out.assign(from: copy)
      }
    }
  }

  func setupZeroQuerySuggestion(
    _ session: Session, _ request: inout Genmai_Commands_Request,
    _ command: inout Genmai_Commands_Command, _ converter: MockConverter
  ) {
    setupZeroQuerySuggestionReady(true, session, &request, converter)
    command = Genmai_Commands_Command()
    session.commit(&command)
  }

  func setUndoContext(
    _ session: Session, _ converter: MockConverter,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    var command = Genmai_Commands_Command()
    let segments = Segments()

    do {  // Create segments
      insertCharacterChars("aiueo", session, &command)
      setAiueo(segments)
      // Don't use FillT13Ns(). It makes platform dependent segments.
      // TODO(hsumita): Makes FillT13Ns() independent from platforms.
      var candidate = segments.mutableSegment(0).addCandidate()
      candidate.value = "aiueo"
      candidate = segments.mutableSegment(0).addCandidate()
      candidate.value = "AIUEO"
    }

    do {  // Commit the composition to make an undo context.
      converter.setStartConversion(segments, true)
      command = Genmai_Commands_Command()
      session.convert(&command)
      #expect(!command.output.hasResult, sourceLocation: sourceLocation)
      expectPreedit("あいうえお", command, sourceLocation: sourceLocation)

      converter.setCommitSegmentValue(segments, true)
      command = Genmai_Commands_Command()

      session.commit(&command)
      #expect(!command.output.hasPreedit, sourceLocation: sourceLocation)
      expectResult("あいうえお", command, sourceLocation: sourceLocation)
      converter.clear()
    }
  }
}
