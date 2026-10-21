// Port of mozc/src/session/session_regression_test.cc (3.35.6354).
//
// This is a test with the actual converter.  So the result of the
// conversion may differ from previous versions.
//
// (FLAGS_use_history_rewriter is true by default in the Swift port.)

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import Testing

@testable import GenmaiSession

// GetComposition: getComposition(_:) in SessionTestFixture.swift.

private func initSessionToPrecomposition(_ session: Session) {
  // Session is created with direct mode on Windows only.
}

/// class SessionRegressionTest.
private final class SessionRegressionFixture {
  let handler: SessionHandler
  var session: Session
  var config = Genmai_Config_Config()

  init() async throws {
    // Note: engine must be created after setting all the flags, as it
    // internally depends on global flags, e.g., for creation of rewriters.
    let engine = try MockDataEngineFactory.create()

    // Clear previous data just in case.
    engine.clearUserHistory()
    engine.clearUserPrediction()
    await engine.wait()

    handler = SessionHandler(engine)
    session = handler.newSession()
    resetSession()
  }

  func tearDown() {
    // just in case, reset the config in test_tmpdir
    var config = Genmai_Config_Config()
    ConfigHandler.getDefaultConfig(&config)
    ConfigHandler.setConfig(config)
  }

  @discardableResult
  func sendKey(_ key: String, _ command: inout Genmai_Commands_Command) -> Bool {
    command = Genmai_Commands_Command()
    command.input.type = .sendKey
    if !KeyParser.parseKey(key, &command.input.key) {
      return false
    }
    return session.sendKey(&command)
  }

  @discardableResult
  func sendCommandWithId(
    _ type: Genmai_Commands_SessionCommand.CommandType, _ id: Int32,
    _ command: inout Genmai_Commands_Command
  ) -> Bool {
    command = Genmai_Commands_Command()
    command.input.type = .sendCommand
    command.input.command.type = type
    command.input.command.id = id
    return session.sendCommand(&command)
  }

  func insertCharacterChars(_ chars: String, _ command: inout Genmai_Commands_Command) {
    let kNoModifiers: UInt32 = 0
    for c in chars.utf8 {
      command.clearInput()
      command.clearOutput()
      command.input.key.keyCode = UInt32(c)
      command.input.key.modifiers = kNoModifiers
      session.insertCharacter(&command)
    }
  }

  func resetSession() {
    session = handler.newSession()
    let request = Genmai_Commands_Request()
    let table = Table()
    table.initializeWithRequestAndConfig(request, config)
    session.setTable(table)
  }
}

/// Runs `body` with a fresh environment and fixture.
private func withFixture(_ body: (SessionRegressionFixture) throws -> Void) async throws {
  try await withScopedSessionEnvironment {
    let f = try await SessionRegressionFixture()
    defer { f.tearDown() }
    try body(f)
  }
}

@Suite(.serialized) struct SessionRegressionTests {
  @Test func convertToTransliterationWithMultipleSegments() async throws {
    try await withFixture { f in
      initSessionToPrecomposition(f.session)

      var command = Genmai_Commands_Command()
      f.insertCharacterChars("liie", &command)

      // Convert
      command = Genmai_Commands_Command()
      f.session.convert(&command)
      do {  // Check the conversion #1
        let output = command.output
        #expect(!output.hasResult)
        #expect(output.hasPreedit)
        #expect(!output.hasCandidateWindow)

        let conversion = output.preedit
        try #require(2 <= conversion.segment.count)
        #expect(conversion.segment[0].value == "ぃ")
      }

      // TranslateHalfASCII
      command = Genmai_Commands_Command()
      f.session.translateHalfASCII(&command)
      do {  // Check the conversion #2
        let output = command.output
        #expect(!output.hasResult)
        #expect(output.hasPreedit)
        #expect(!output.hasCandidateWindow)

        let conversion = output.preedit
        try #require(conversion.segment.count == 2)
        #expect(conversion.segment[0].value == "li")
      }
    }
  }

  @Test func exitTemporaryAlphanumModeAfterCommittingSugesstion() async throws {
    // This is a regression test against http://b/2977131.
    try await withFixture { f in
      initSessionToPrecomposition(f.session)
      var command = Genmai_Commands_Command()
      f.insertCharacterChars("NFL", &command)
      #expect(command.output.status.mode == .halfAscii)
      #expect(command.output.mode == .halfAscii)  // obsolete

      #expect(f.sendKey("F10", &command))
      try #require(!command.output.hasCandidateWindow)
      #expect(!command.output.hasResult)

      #expect(f.sendKey("a", &command))
      // The MacOS default short cut of F10 is DisplayAsHalfAlphanumeric.
      // It does not start the conversion so output does not have any result.
      #expect(!command.output.hasResult)
      #expect(command.output.status.mode == .hiragana)
      #expect(command.output.mode == .hiragana)  // obsolete
    }
  }

  @Test func historyLearning() async throws {
    try await withFixture { f in
      initSessionToPrecomposition(f.session)
      var command = Genmai_Commands_Command()
      var candidate1 = ""
      var candidate2 = ""

      do {  // First session.  Second candidate is committed.
        f.insertCharacterChars("kanji", &command)

        command = Genmai_Commands_Command()
        f.session.convert(&command)
        candidate1 = getComposition(command)

        command = Genmai_Commands_Command()
        f.session.convertNext(&command)
        candidate2 = getComposition(command)
        #expect(candidate2 != candidate1)

        command = Genmai_Commands_Command()
        f.session.commit(&command)
        #expect(!command.output.hasPreedit)
        #expect(command.output.result.value == candidate2)
      }

      do {  // Second session.  The previous second candidate should be promoted.
        command = Genmai_Commands_Command()
        f.insertCharacterChars("kanji", &command)

        command = Genmai_Commands_Command()
        f.session.convert(&command)
        #expect(getComposition(command) != candidate1)
        #expect(getComposition(command) == candidate2)
      }
    }
  }

  @Test func undo() async throws {
    try await withFixture { f in
      initSessionToPrecomposition(f.session)

      var capability = Genmai_Commands_Capability()
      capability.textDeletion = .deletePrecedingText
      f.session.setClientCapability(capability)

      var command = Genmai_Commands_Command()
      f.insertCharacterChars("kanji", &command)

      command = Genmai_Commands_Command()
      f.session.convert(&command)
      let candidate1 = getComposition(command)

      command = Genmai_Commands_Command()
      f.session.convertNext(&command)
      let candidate2 = getComposition(command)
      #expect(candidate2 != candidate1)

      command = Genmai_Commands_Command()
      f.session.commit(&command)
      #expect(!command.output.hasPreedit)
      #expect(command.output.result.value == candidate2)

      command = Genmai_Commands_Command()
      f.session.undo(&command)
      #expect(getComposition(command) != candidate1)
      #expect(getComposition(command) == candidate2)
    }
  }

  // TODO(hsumita): This test may be moved to session_test.cc.
  @Test func predictionAfterUndo() async throws {
    // This is a unittest against http://b/3427619
    try await withFixture { f in
      initSessionToPrecomposition(f.session)

      var capability = Genmai_Commands_Capability()
      capability.textDeletion = .deletePrecedingText
      f.session.setClientCapability(capability)

      var command = Genmai_Commands_Command()
      f.insertCharacterChars("yoroshi", &command)
      let kYoroshikuString = "よろしく"

      command = Genmai_Commands_Command()
      f.session.predictAndConvert(&command)
      #expect(command.output.preedit.segment.count == 1)

      // Candidate contain "よろしく" or NOT
      var yoroshikuId = -1
      for i in 0..<10 {
        if getComposition(command) == kYoroshikuString {
          yoroshikuId = i
          break
        }
        command = Genmai_Commands_Command()
        f.session.convertNext(&command)
      }
      #expect(getComposition(command) == kYoroshikuString)
      #expect(yoroshikuId >= 0)

      command = Genmai_Commands_Command()
      f.session.commit(&command)
      #expect(!command.output.hasPreedit)
      #expect(command.output.result.value == kYoroshikuString)

      command = Genmai_Commands_Command()
      f.session.undo(&command)
      #expect(getComposition(command) == kYoroshikuString)
    }
  }

  // This test is to check the consistency between the result of prediction and
  // suggestion.
  @Test func consistencyBetweenPredictionAndSuggestion() async throws {
    try await withFixture { f in
      let kKey = "aio"

      var request = Genmai_Commands_Request()
      RequestTestUtil.fillMobileRequest(&request)
      f.session.setRequest(request)

      initSessionToPrecomposition(f.session)
      var command = Genmai_Commands_Command()

      f.insertCharacterChars(kKey, &command)
      #expect(command.output.preedit.segment.count == 1)
      try #require(!command.output.allCandidateWords.candidates.isEmpty)
      let suggestionFirstCandidate = command.output.allCandidateWords.candidates[0].value

      command = Genmai_Commands_Command()
      f.session.commitFirstSuggestion(&command)
      let suggestionCommitResult = command.output.result.value

      initSessionToPrecomposition(f.session)
      command = Genmai_Commands_Command()
      f.insertCharacterChars(kKey, &command)
      command = Genmai_Commands_Command()
      f.session.predictAndConvert(&command)
      try #require(!command.output.allCandidateWords.candidates.isEmpty)
      let predictionFirstCandidate = command.output.allCandidateWords.candidates[0].value

      command = Genmai_Commands_Command()
      f.session.commit(&command)
      let predictionCommitResult = command.output.result.value

      #expect(suggestionCommitResult == suggestionFirstCandidate)
      #expect(predictionFirstCandidate == suggestionFirstCandidate)
      #expect(predictionCommitResult == suggestionFirstCandidate)
    }
  }

  @Test func autoConversionTest() async throws {
    try await withFixture { f in
      func insert(_ keys: String) {
        var command = Genmai_Commands_Command()
        for c in keys.utf8 {
          command = Genmai_Commands_Command()
          command.input.key.keyCode = UInt32(c)
          command.input.key.keyString = String(UnicodeScalar(c))
          f.session.insertCharacter(&command)
        }
      }

      // Default mode
      do {
        f.resetSession()
        initSessionToPrecomposition(f.session)
        insert("123456.7")
        #expect(f.session.context.state == .composition)
      }

      // Auto conversion with KUTEN
      do {
        f.resetSession()
        initSessionToPrecomposition(f.session)
        var config = Genmai_Config_Config()
        ConfigHandler.getDefaultConfig(&config)
        config.useAutoConversion = true
        f.session.setConfig(config)

        insert("aiueo.")
        #expect(f.session.context.state == .conversion)
      }

      // Auto conversion with KUTEN, but do not convert in numerical input
      do {
        f.resetSession()
        initSessionToPrecomposition(f.session)
        var config = ConfigHandler.getCopiedConfig()
        config.useAutoConversion = true
        f.session.setConfig(config)

        insert("1234.")
        #expect(f.session.context.state == .composition)
      }
    }
  }

  @Test func transliterationIssue2330463() async throws {
    try await withFixture { f in
      for (input, expected) in [("[],.", "｢｣､｡"), ("[g],.", "｢g｣､｡"), ("[a],.", "｢ｱ｣､｡")] {
        f.resetSession()
        var command = Genmai_Commands_Command()

        f.insertCharacterChars(input, &command)
        command = Genmai_Commands_Command()
        f.sendKey("F8", &command)
        #expect(command.output.preedit.segment.first?.value == expected, "\(input)")
      }
    }
  }

  @Test func transliterationIssue6209563() async throws {
    try await withFixture { f in
      do {  // Romaji mode
        f.resetSession()
        var command = Genmai_Commands_Command()

        f.insertCharacterChars("tt", &command)
        command = Genmai_Commands_Command()
        f.sendKey("F10", &command)
        #expect(command.output.preedit.segment.first?.value == "tt")
      }

      do {  // Kana mode
        f.resetSession()
        var command = Genmai_Commands_Command()

        initSessionToPrecomposition(f.session)
        var config = ConfigHandler.getCopiedConfig()
        config.preeditMethod = .kana

        // Inserts "ち" 5 times
        for _ in 0..<5 {
          command = Genmai_Commands_Command()
          command.input.key.keyCode = UInt32(UInt8(ascii: "a"))
          command.input.key.keyString = "ち"
          f.session.insertCharacter(&command)
        }

        command = Genmai_Commands_Command()
        f.sendKey("F10", &command)
        #expect(command.output.preedit.segment.first?.value == "aaaaa")
      }
    }
  }

  @Test func commitT13nSuggestion() async throws {
    // This is the test for http://b/6934881.
    // Pending char chunk remains after committing transliteration.
    try await withFixture { f in
      var request = Genmai_Commands_Request()
      RequestTestUtil.fillMobileRequest(&request)
      f.session.setRequest(request)

      initSessionToPrecomposition(f.session)

      var command = Genmai_Commands_Command()
      f.insertCharacterChars("ssh", &command)
      #expect(getComposition(command) == "っｓｈ")

      let kHiraganaId: Int32 = -1
      f.sendCommandWithId(.submitCandidate, kHiraganaId, &command)

      #expect(command.output.hasResult)
      #expect(!command.output.hasPreedit)

      #expect(command.output.result.value == "っｓｈ")
    }
  }

  @Test func deleteCandidateFromHistory() async throws {
    try await withFixture { f in
      var request = Genmai_Commands_Request()
      RequestTestUtil.fillMobileRequest(&request)
      f.session.setRequest(request)

      initSessionToPrecomposition(f.session)

      var command = Genmai_Commands_Command()
      var targetId: Int32 = 1  // ID of deletation tareget

      // 1. Type "aiu" and check 2nd candidate, which is our deleteation target.
      f.insertCharacterChars("aiu", &command)
      try #require(command.output.candidateWindow.candidate.count > 1)
      let targetWord = command.output.candidateWindow.candidate[1].value

      // 2. Submit the 2nd candidate to be deleted from history.
      f.sendCommandWithId(.submitCandidate, targetId, &command)
      targetId = 0  // ID of the deletion target is changed after submit.

      f.insertCharacterChars("aiu", &command)
      try #require(command.output.candidateWindow.candidate.count > 1)
      do {
        let candidate = command.output.candidateWindow.candidate[0]
        #expect(candidate.id == targetId)
        #expect(candidate.value == targetWord)
      }
      do {
        let candidate = command.output.candidateWindow.candidate[1]
        #expect(candidate.id != targetId)
        #expect(candidate.value != targetWord)
      }

      // 3. Delete the above candidate from the history.
      f.sendCommandWithId(.deleteCandidateFromHistory, targetId, &command)
      targetId = 1  // ID of the deletion target is reverted after history deletion.

      #expect(command.output.hasCandidateWindow)
      try #require(command.output.candidateWindow.candidate.count > 1)
      do {
        let candidate = command.output.candidateWindow.candidate[0]
        #expect(candidate.id != targetId)
        #expect(candidate.value != targetWord)
      }
      do {
        let candidate = command.output.candidateWindow.candidate[1]
        #expect(candidate.id == targetId)
        #expect(candidate.value == targetWord)
      }
    }
  }
}
