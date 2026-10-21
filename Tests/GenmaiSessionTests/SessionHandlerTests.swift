// Port of mozc/src/session/session_handler_test.cc (3.35.6354).
//
// Deviations from C++:
// - The handler does not block: CREATE_SESSION does not wait for the data
//   loader (C++ Engine::MaybeReloadEngine waits while converter_ is null or
//   SetAlwaysWaitForTesting(true)), so the engine reload tests await
//   `Engine.waitForDataLoader()` after sending a request; SYNC_DATA does not
//   call Engine::Wait() (`SessionHandler.waitForEngine()` does).

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import Testing

@testable import GenmaiSession

private func sendMockEngineReloadRequest(
  _ handler: SessionHandler, _ request: Genmai_EngineReloadRequest
) -> Genmai_EngineReloadResponse.Status {
  var command = Genmai_Commands_Command()
  command.input.type = .sendEngineReloadRequest
  command.input.engineReloadRequest = request
  handler.evalCommand(&command)
  return command.output.engineReloadResponse.status
}

private func createSession(_ handler: SessionHandler, _ id: inout UInt64) -> Bool {
  var command = Genmai_Commands_Command()
  command.input.type = .createSession
  command.input.capability.textDeletion = .deletePrecedingText
  handler.evalCommand(&command)
  id = command.hasOutput ? command.output.id : 0
  return command.output.errorCode == .sessionSuccess
}

private func createSession(_ handler: SessionHandler) -> Bool {
  var id: UInt64 = 0
  return createSession(handler, &id)
}

private func deleteSession(_ handler: SessionHandler, _ id: UInt64) -> Bool {
  var command = Genmai_Commands_Command()
  command.input.id = id
  command.input.type = .deleteSession
  return handler.evalCommand(&command)
}

private func cleanUp(_ handler: SessionHandler, _ id: UInt64) -> Bool {
  var command = Genmai_Commands_Command()
  command.input.id = id
  command.input.type = .cleanup
  return handler.evalCommand(&command)
}

private func isGoodSession(_ handler: SessionHandler, _ id: UInt64) -> Bool {
  var command = Genmai_Commands_Command()
  command.input.id = id
  command.input.type = .sendKey
  command.input.key.specialKey = .space
  handler.evalCommand(&command)
  return command.output.errorCode == .sessionSuccess
}

private let kMockMagicNumber = "MOCK"
/// The C++ magic number "\xEFMOZC\x0D\x0A" is raw bytes; the proto string
/// holds it as Latin-1 scalars (see DataLoader.magicNumberBytes).
private let kOssMagicNumber = "\u{EF}MOZC\r\n"
private let kOssMagicBytes: [UInt8] = [0xEF, 0x4D, 0x4F, 0x5A, 0x43, 0x0D, 0x0A]

/// class SessionHandlerTest : public SessionHandlerTestBase
private final class SessionHandlerTestFixture {
  var handler: SessionHandler!
  var engine: Engine!

  var mockVersion = ""
  var ossVersion = ""

  var mockRequest = Genmai_EngineReloadRequest()
  var ossRequest = Genmai_EngineReloadRequest()
  var invalidPathRequest = Genmai_EngineReloadRequest()
  var invalidDataRequest = Genmai_EngineReloadRequest()

  init() throws {
    let mockPath = MockDataManager.defaultDataPath ?? ""
    mockRequest.filePath = mockPath
    mockRequest.magicNumber = kMockMagicNumber

    let ossPath = OssDataManager.defaultDataPath
    ossRequest.filePath = ossPath
    ossRequest.magicNumber = kOssMagicNumber

    let invalidPath = SessionTestPaths.upstreamSourceFile(["data_manager", "invalid", "genmai.data"])
    invalidPathRequest.filePath = invalidPath
    invalidPathRequest.magicNumber = kOssMagicNumber

    invalidDataRequest.filePath = mockPath
    invalidDataRequest.magicNumber = kOssMagicNumber

    mockVersion = try DataManager.createFromFile(mockPath, magic: Array(kMockMagicNumber.utf8))
      .getDataVersion()
    if SessionTestPaths.ossDataAvailable {
      ossVersion = try DataManager.createFromFile(ossPath, magic: kOssMagicBytes).getDataVersion()
    }

    // SessionHandlerTestBase::SetUp -> ClearState
    clearState()

    let engine = Engine.createEngine()
    self.engine = engine
    handler = SessionHandler(engine)
  }

  func clearState() {
    if let handler {
      var command = Genmai_Commands_Command()
      command.input.type = .clearUserPrediction
      handler.evalCommand(&command)
    }
    var config = Genmai_Config_Config()
    ConfigHandler.getDefaultConfig(&config)
    ConfigHandler.setConfig(config)
    // CharacterFormManager is not automatically updated when the config is
    // updated.
    CharacterFormManager.getCharacterFormManager().reloadConfig(config)
  }

  static func createMockDataEngine() throws -> Engine {
    try MockDataEngineFactory.create()
  }
}

/// Runs `body` with the SessionHandlerTestBase environment and the given
/// flags (absl::FlagSaver).
private func withSessionHandlerTest(
  _ flags: SessionHandlerFlags = SessionHandlerFlags(),
  _ body: (SessionHandlerTestFixture) throws -> Void
) throws {
  try withScopedSessionEnvironment {
    try SessionHandler.withFlagsForTesting(flags) {
      let f = try SessionHandlerTestFixture()
      try body(f)
    }
  }
}

private func withSessionHandlerTest(
  _ flags: SessionHandlerFlags = SessionHandlerFlags(),
  _ body: (SessionHandlerTestFixture) async throws -> Void
) async throws {
  try await withScopedSessionEnvironment {
    try await SessionHandler.withFlagsForTesting(flags) {
      let f = try SessionHandlerTestFixture()
      try await body(f)
    }
  }
}

@Suite struct SessionHandlerTest {
  @Test func maxSessionSizeTest() throws {
    var flags = SessionHandlerFlags()
    let intervalTime: Int32 = 10  // 10 sec
    flags.createSessionMinInterval = intervalTime
    let clock = ClockMock(Date(unixSeconds: 1000))

    // The oldest item is removed
    let sessionSize = 3
    flags.maxSessionSize = Int32(sessionSize)
    try withSessionHandlerTest(flags) { _ in
      try Clock.withClock(clock) {
        do {
          let handler = SessionHandler(try SessionHandlerTestFixture.createMockDataEngine())

          // Create session_size + 1 sessions
          var ids: [UInt64] = []
          for _ in 0...sessionSize {
            var id: UInt64 = 0
            #expect(createSession(handler, &id))
            ids.append(id)
            clock.advance(.seconds(Int64(intervalTime)))
          }

          for i in stride(from: ids.count - 1, through: 0, by: -1) {
            if i > 0 {  // this id is alive
              #expect(isGoodSession(handler, ids[i]))
            } else {  // the first id should be removed
              #expect(!isGoodSession(handler, ids[i]))
            }
          }
        }

        do {
          let handler = SessionHandler(try SessionHandlerTestFixture.createMockDataEngine())

          // Create session_size sessions
          var ids: [UInt64] = []
          for _ in 0..<sessionSize {
            var id: UInt64 = 0
            #expect(createSession(handler, &id))
            ids.append(id)
            clock.advance(.seconds(Int64(intervalTime)))
          }

          ids.shuffle()
          let oldestId = ids[0]
          for i in 0..<sessionSize {
            #expect(isGoodSession(handler, ids[i]))
          }

          // Create new session
          var id: UInt64 = 0
          #expect(createSession(handler, &id))

          // the oldest id no longer exists
          #expect(!isGoodSession(handler, oldestId))
        }
      }
    }
  }

  @Test func createSessionConfigTest() throws {
    try withSessionHandlerTest { _ in
      // Setting ATOK to ConfigHandler before all other initializations.
      //  Not using SET_CONFIG command
      // because we're emulating the behavior of initial launch of Mozc
      // decoder, where SET_CONFIG isn't sent.
      var config = Genmai_Config_Config()
      config.sessionKeymap = .atok
      ConfigHandler.setConfig(config)

      let handler = SessionHandler(try SessionHandlerTestFixture.createMockDataEngine())

      // The created session should be using ATOK keymap.
      var sessionId: UInt64 = 0
      #expect(createSession(handler, &sessionId))
      do {
        // Move to PRECOMPOSITION mode.
        // On Windows, its initial mode is DIRECT.
        var command = Genmai_Commands_Command()
        command.input.id = sessionId
        command.input.type = .sendKey
        command.input.key.specialKey = .on
        #expect(handler.evalCommand(&command))
      }
      do {
        // Check if the config in ConfigHandler is respected
        // even without SET_CONFIG command.
        var command = Genmai_Commands_Command()
        command.input.id = sessionId
        command.input.type = .sendKey
        command.input.key.specialKey = .f7
        command.input.key.modifierKeys.append(.ctrl)
        #expect(handler.evalCommand(&command))
        #expect(command.output.launchToolMode == .wordRegisterDialog)
      }
    }
  }

  @Test func createSessionMinIntervalTest() throws {
    var flags = SessionHandlerFlags()
    let kIntervalTime: Int64 = 10
    flags.createSessionMinInterval = Int32(kIntervalTime)
    let clock = ClockMock(Date(unixSeconds: 1000))
    try withSessionHandlerTest(flags) { _ in
      try Clock.withClock(clock) {
        let handler = SessionHandler(try SessionHandlerTestFixture.createMockDataEngine())

        var id: UInt64 = 0
        #expect(createSession(handler, &id))
        #expect(!createSession(handler, &id))

        clock.advance(.seconds(kIntervalTime) - .seconds(1))
        #expect(!createSession(handler, &id))

        clock.advance(.seconds(1))
        #expect(createSession(handler, &id))
      }
    }
  }

  @Test func createSessionNegativeIntervalTest() throws {
    var flags = SessionHandlerFlags()
    flags.createSessionMinInterval = 0
    let clock = ClockMock(Date(unixSeconds: 1000))
    try withSessionHandlerTest(flags) { _ in
      try Clock.withClock(clock) {
        let handler = SessionHandler(try SessionHandlerTestFixture.createMockDataEngine())

        var id: UInt64 = 0
        #expect(createSession(handler, &id))

        // A user can modify their system clock.
        clock.advance(.seconds(-1))
        #expect(createSession(handler, &id))
      }
    }
  }

  @Test func lastCreateSessionTimeoutTest() throws {
    var flags = SessionHandlerFlags()
    let kTimeout: Int64 = 10
    flags.lastCreateSessionTimeout = Int32(kTimeout)
    let clock = ClockMock(Date(unixSeconds: 1000))
    try withSessionHandlerTest(flags) { _ in
      try Clock.withClock(clock) {
        let handler = SessionHandler(try SessionHandlerTestFixture.createMockDataEngine())

        var id: UInt64 = 0
        #expect(createSession(handler, &id))

        clock.advance(.seconds(kTimeout))
        #expect(cleanUp(handler, id))

        // the session is removed by server
        #expect(!isGoodSession(handler, id))
      }
    }
  }

  @Test func lastCommandTimeoutTest() throws {
    var flags = SessionHandlerFlags()
    let timeout: Int32 = 10  // 10 sec
    flags.lastCommandTimeout = timeout
    let clock = ClockMock(Date(unixSeconds: 1000))
    try withSessionHandlerTest(flags) { _ in
      try Clock.withClock(clock) {
        let handler = SessionHandler(try SessionHandlerTestFixture.createMockDataEngine())

        var id: UInt64 = 0
        #expect(createSession(handler, &id))

        #expect(cleanUp(handler, id))
        #expect(isGoodSession(handler, id))

        clock.advance(.seconds(Int64(timeout)))
        #expect(cleanUp(handler, id))
        #expect(!isGoodSession(handler, id))
      }
    }
  }

  @Test func shutdownTest() throws {
    try withSessionHandlerTest { _ in
      let handler = SessionHandler(try SessionHandlerTestFixture.createMockDataEngine())

      var sessionId: UInt64 = 0
      #expect(createSession(handler, &sessionId))

      do {
        var command = Genmai_Commands_Command()
        command.input.id = sessionId
        command.input.type = .shutdown
        // EvalCommand returns false since the session no longer exists.
        #expect(!handler.evalCommand(&command))
        #expect(command.output.id == sessionId)
      }

      do {  // Any command should be rejected after shutdown.
        var command = Genmai_Commands_Command()
        command.input.id = sessionId
        command.input.type = .noOperation
        #expect(!handler.evalCommand(&command))
      }
    }
  }

  @Test func clearHistoryTest() throws {
    try withSessionHandlerTest { _ in
      let handler = SessionHandler(try SessionHandlerTestFixture.createMockDataEngine())

      var sessionId: UInt64 = 0
      #expect(createSession(handler, &sessionId))

      do {
        var command = Genmai_Commands_Command()
        command.input.id = sessionId
        command.input.type = .clearUserHistory
        #expect(handler.evalCommand(&command))
        #expect(command.output.id == sessionId)
      }

      do {
        var command = Genmai_Commands_Command()
        command.input.id = sessionId
        command.input.type = .clearUserPrediction
        #expect(handler.evalCommand(&command))
        #expect(command.output.id == sessionId)
      }
    }
  }

  @Test func elapsedTimeTest() throws {
    try withSessionHandlerTest { _ in
      let handler = SessionHandler(try SessionHandlerTestFixture.createMockDataEngine())

      var id: UInt64 = 0

      let clock = ClockMock(Date(unixSeconds: 1000))
      Clock.withClock(clock) {
        #expect(createSession(handler, &id))
      }
    }
  }

  @Test func configTest() throws {
    try withSessionHandlerTest { _ in
      var config = ConfigHandler.getCopiedConfig()
      let handler = SessionHandler(try SessionHandlerTestFixture.createMockDataEngine())

      do {
        // Set KOTOERI keymap
        var command = Genmai_Commands_Command()
        command.input.type = .setConfig
        config.sessionKeymap = .kotoeri
        command.input.config = config
        #expect(handler.evalCommand(&command))
        config = ConfigHandler.getCopiedConfig()
        #expect(command.output.config.sessionKeymap == .kotoeri)
      }

      var sessionId: UInt64 = 0
      #expect(createSession(handler, &sessionId))
      do {
        // Move to PRECOMPOSITION mode.
        // On Windows, its initial mode is DIRECT.
        var command = Genmai_Commands_Command()
        command.input.id = sessionId
        command.input.type = .sendKey
        command.input.key.specialKey = .on
        #expect(handler.evalCommand(&command))
      }
      do {
        // KOTOERI doesn't assign anything to ctrl+shift+space (precomposition) so
        // SEND_KEY shouldn't consume it.
        var command = Genmai_Commands_Command()
        command.input.id = sessionId
        command.input.type = .sendKey
        command.input.key.specialKey = .space
        command.input.key.modifierKeys.append(.shift)
        command.input.key.modifierKeys.append(.ctrl)
        #expect(handler.evalCommand(&command))
        #expect(!command.output.consumed)
      }
      do {
        // Set ATOK keymap
        // The existing Session should apply it immediately.
        var command = Genmai_Commands_Command()
        command.input.id = sessionId
        command.input.type = .setConfig
        config.sessionKeymap = .atok
        command.input.config = config
        #expect(handler.evalCommand(&command))
        #expect(command.output.id == command.input.id)
        config = ConfigHandler.getCopiedConfig()
        #expect(command.output.config.sessionKeymap == .atok)
      }
      do {
        // ATOK assigns a function to ctrl+f7 (precomposition) (KOTOERI doesn't) so
        // TEST_SEND_KEY should consume it.
        var command = Genmai_Commands_Command()
        command.input.id = sessionId
        command.input.type = .sendKey
        command.input.key.specialKey = .f7
        command.input.key.modifierKeys.append(.ctrl)
        #expect(handler.evalCommand(&command))
        #expect(command.output.launchToolMode == .wordRegisterDialog)
      }
    }
  }

  @Test func updateComposition() throws {
    try withSessionHandlerTest { _ in
      let config = ConfigHandler.getCopiedConfig()
      ConfigHandler.setConfig(config)
      let handler = SessionHandler(try SessionHandlerTestFixture.createMockDataEngine())

      var sessionId: UInt64 = 0
      #expect(createSession(handler, &sessionId))
      do {
        // Move to PRECOMPOSITION mode.
        // On Windows, its initial mode is DIRECT.
        var command = Genmai_Commands_Command()
        command.input.id = sessionId
        command.input.type = .sendKey
        command.input.key.specialKey = .on
        #expect(handler.evalCommand(&command))
      }
      do {
        var command = Genmai_Commands_Command()
        command.input.id = sessionId
        command.input.type = .sendCommand
        command.input.command.type = .updateComposition
        var compositionEvent = Genmai_Commands_SessionCommand.CompositionEvent()
        compositionEvent.compositionString = "かん字"
        compositionEvent.probability = 1.0
        command.input.command.compositionEvents.append(compositionEvent)
        #expect(handler.evalCommand(&command))
        #expect(command.output.consumed)
        #expect(command.output.preedit.segment.first?.value == "かん字")
      }
    }
  }

  @Test func keyMapTest() throws {
    try withSessionHandlerTest { _ in
      let handler = SessionHandler(try SessionHandlerTestFixture.createMockDataEngine())

      var sessionId: UInt64 = 0
      #expect(createSession(handler, &sessionId))

      let msimeKeymap: KeyMapManager
      do {
        var command = Genmai_Commands_Command()
        command.input.id = sessionId
        command.input.type = .setConfig
        command.input.config.sessionKeymap = .msime
        #expect(handler.evalCommand(&command))
        msimeKeymap = handler.keyMapManagerForTesting
      }
      do {
        var command = Genmai_Commands_Command()
        command.input.id = sessionId
        command.input.type = .setConfig
        command.input.config.sessionKeymap = .kotoeri
        #expect(handler.evalCommand(&command))
        // As different keymap is set, the handler's keymap manager should be
        // updated.
        #expect(handler.keyMapManagerForTesting !== msimeKeymap)
      }
    }
  }

  @Test func verifySyncIsCalledTest() throws {
    try withSessionHandlerTest { _ in
      // Tests if sync is called for the following input commands.
      let commandTypes: [Genmai_Commands_Input.CommandType] = [.deleteSession, .cleanup]
      for commandType in commandTypes {
        let engine = MockEngine()
        engine.syncHandler = { true }

        // Set up a session handler and a input command.
        let handler = SessionHandler(engine)
        var command = Genmai_Commands_Command()
        command.input.id = 0
        command.input.type = commandType

        handler.evalCommand(&command)
        #expect(engine.syncCount == 1)
      }
    }
  }

  @Test func syncDataTest() async throws {
    try await withSessionHandlerTest { _ in
      let engine = MockEngine()
      engine.syncHandler = { true }
      engine.waitHandler = { true }

      // Set up a session handler and a input command.
      let handler = SessionHandler(engine)
      var command = Genmai_Commands_Command()
      command.input.id = 0
      command.input.type = .syncData

      handler.evalCommand(&command)
      #expect(engine.syncCount == 1)
      // The wait is not part of evalCommand here (see the header comment).
      #expect(engine.waitCount == 0)
      await handler.waitForEngine()
      #expect(engine.waitCount == 1)
    }
  }

  // Tests the interaction with DataLoader for successful Engine reload event.
  @Test func engineReloadSuccessfulScenarioTest() async throws {
    try await withSessionHandlerTest { f in
      let handler = f.handler!
      try #require(sendMockEngineReloadRequest(handler, f.mockRequest) == .accepted)
      await f.engine.waitForDataLoader()

      // A new engine should be built on create session event because the session
      // handler currently holds no session.
      var command = Genmai_Commands_Command()
      command.input.type = .createSession
      handler.evalCommand(&command)
      #expect(command.output.errorCode == .sessionSuccess)
      #expect(command.output.hasEngineReloadResponse)
      #expect(command.output.engineReloadResponse.status == .reloaded)
      #expect(command.output.id != 0)

      // When the engine is created first, we wait until the engine gets ready.
      #expect(handler.getDataVersion() == f.mockVersion)

      // New session is created, but Build is not called as the id is the same.
      try #require(sendMockEngineReloadRequest(handler, f.mockRequest) == .accepted)
      await f.engine.waitForDataLoader()

      var id: UInt64 = 0
      try #require(deleteSession(handler, id))
      try #require(createSession(handler, &id))
      #expect(handler.getDataVersion() == f.mockVersion)
    }
  }

  // Tests situations to handle multiple new requests.
  @Test(.enabled(if: SessionTestPaths.ossDataAvailable, "Data/genmai.data is missing"))
  func engineUpdateSuccessfulScenarioTest() async throws {
    try await withSessionHandlerTest { f in
      let handler = f.handler!
      // engine_id = 1
      try #require(sendMockEngineReloadRequest(handler, f.mockRequest) == .accepted)
      await f.engine.waitForDataLoader()

      // build request is called one per new engine reload request.
      var id: UInt64 = 0
      try #require(createSession(handler, &id))
      #expect(handler.getDataVersion() == f.mockVersion)

      // engine_id = 2
      try #require(sendMockEngineReloadRequest(handler, f.ossRequest) == .accepted)
      await f.engine.waitForDataLoader()

      try #require(deleteSession(handler, id))
      try #require(createSession(handler, &id))
      #expect(handler.getDataVersion() == f.ossVersion)
    }
  }

  // Tests the interaction with DataLoader in the situation where requested data
  // is broken.
  @Test func engineReloadInvalidDataTest() async throws {
    try await withSessionHandlerTest { f in
      let handler = f.handler!
      let initialVersion = handler.getDataVersion()

      try #require(sendMockEngineReloadRequest(handler, f.invalidPathRequest) == .accepted)
      await f.engine.waitForDataLoader()

      // Build() is called, but it returns invalid data, so new data is not used.
      #expect(handler.getDataVersion() == initialVersion)

      // CreateSession does not contain engine_reload_response.
      var command = Genmai_Commands_Command()
      command.input.type = .createSession
      handler.evalCommand(&command)
      #expect(command.output.errorCode == .sessionSuccess)
      #expect(!command.output.hasEngineReloadResponse)
      #expect(command.output.id != 0)

      #expect(handler.getDataVersion() == initialVersion)

      // Sends the same request again, but the request is already marked as
      // unregistered.
      var id: UInt64 = 0
      try #require(sendMockEngineReloadRequest(handler, f.invalidPathRequest) == .accepted)
      await f.engine.waitForDataLoader()
      try #require(deleteSession(handler, id))
      try #require(createSession(handler, &id))
      #expect(handler.getDataVersion() == initialVersion)
    }
  }

  // Tests the rollback scenario
  @Test func engineRollbackDataTest() async throws {
    try await withSessionHandlerTest { f in
      let handler = f.handler!
      // Sends multiple requests three times.
      try #require(sendMockEngineReloadRequest(handler, f.mockRequest) == .accepted)
      try #require(sendMockEngineReloadRequest(handler, f.invalidPathRequest) == .accepted)
      try #require(sendMockEngineReloadRequest(handler, f.invalidDataRequest) == .accepted)
      await f.engine.waitForDataLoader()

      for _ in 0..<3 {
        // Engine of 3, and 2 are unregistered.
        // The second best id (2, and 1) are used.
        var id: UInt64 = 0
        try #require(createSession(handler, &id))
        try #require(deleteSession(handler, id))
      }

      // Finally rollback to the new engine with the first request.
      #expect(handler.getDataVersion() == f.mockVersion)
    }
  }

  // Tests the interaction with DataLoader in the situation where
  // sessions exist in create session event.
  @Test func engineReloadSessionExistsTest() async throws {
    try await withSessionHandlerTest { f in
      let handler = f.handler!
      let initialVersion = handler.engine.getDataVersion()

      let oldEngine = handler.engine

      // As a session is created before data is loaded, engine is not reloaded yet.
      var id1: UInt64 = 0
      try #require(createSession(handler, &id1))
      #expect(handler.getDataVersion() == initialVersion)
      #expect(handler.engine === oldEngine)

      try #require(sendMockEngineReloadRequest(handler, f.mockRequest) == .accepted)
      await f.engine.waitForDataLoader()

      // Another session is created. Since the handler already holds one session
      // (id1), new data manager is not used.
      var id2: UInt64 = 0
      try #require(createSession(handler, &id2))
      #expect(handler.engine === oldEngine)
      #expect(handler.getDataVersion() == initialVersion)
      #expect(handler.getDataVersion() != f.mockVersion)

      // All the sessions were deleted.
      try #require(deleteSession(handler, id1))
      try #require(deleteSession(handler, id2))

      // A new session is created. Since the handler holds no session, engine
      // reloads the new data manager.
      var id3: UInt64 = 0
      try #require(createSession(handler, &id3))
      // New data is reloaded, but the engine is the same object.
      #expect(handler.engine === oldEngine)
      #expect(handler.getDataVersion() == f.mockVersion)
    }
  }

  @Test func getServerVersionTest() throws {
    try withSessionHandlerTest { _ in
      let engine = MockEngine()
      engine.getDataVersionHandler = { "24.20240101.01" }

      let handler = SessionHandler(engine)
      var command = Genmai_Commands_Command()
      command.input.type = .getServerVersion
      handler.evalCommand(&command)
      #expect(command.output.serverVersion.dataVersion == "24.20240101.01")
    }
  }

  @Test func reloadFromMinimalEngine() async throws {
    try await withSessionHandlerTest { f in
      let engine = Engine.createEngine()

      // (The C++ test also creates an unused MockDataManager here.)

      let handler = SessionHandler(engine)
      #expect(handler.getDataVersion() != f.mockVersion)

      try #require(sendMockEngineReloadRequest(handler, f.mockRequest) == .accepted)
      await engine.waitForDataLoader()

      // CreateSession updates the Engine including the Predictor.
      var id: UInt64 = 0
      try #require(createSession(handler, &id))
      #expect(handler.getDataVersion() == f.mockVersion)
    }
  }
}
