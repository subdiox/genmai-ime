// Port of mozc/src/session/session_test.cc (3.35.6354), part 3 (AutoConversion .. end).
//
// Continuation of SessionTests3.swift: MoveCursor .. the end of the C++ file.

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import Testing

@testable import GenmaiSession

/// CreateMultiSegmentTestData
func createMultiSegmentTestData() -> Segments {
  let segments = Segments()

  let seg0 = segments.addSegment()
  seg0.setKey("わたしの")
  let cand00 = seg0.addCandidate()
  cand00.value = "私の"
  cand00.key = "わたしの"
  cand00.contentKey = "わたしの"
  cand00.convertedSegmentCount = 1
  let cand01 = seg0.addCandidate()
  cand01.value = "私の名前は"
  cand01.key = "わたしのなまえは"
  cand01.contentKey = "わたしのなまえは"
  cand01.convertedSegmentCount = 2

  let seg1 = segments.addSegment()
  seg1.setKey("なまえは")
  let cand10 = seg1.addCandidate()
  cand10.value = "名前は"
  cand10.key = "なまえは"
  cand10.contentKey = "なまえは"
  cand10.convertedSegmentCount = 1

  let seg2 = segments.addSegment()
  seg2.setKey("なかのです")
  let cand20 = seg2.addCandidate()
  cand20.value = "中野です"
  cand20.key = "なかのです"
  cand20.contentKey = "なかのです"
  cand20.convertedSegmentCount = 1

  return segments
}

/// CommitSegmentValue: move the selected candidate to the top.
func setCommitSegmentValueMoveCandidate(_ converter: MockConverter) {
  converter.commitSegmentValueHandler = { segs, segIdx, candIdx in
    if segIdx < segs.conversionSegmentsSize {
      segs.mutableConversionSegment(segIdx).moveCandidate(candIdx, 0)
    }
    return true
  }
}

@Suite struct SessionTests4 {
  @Test func moveCursor() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()

      f.insertCharacterChars("MOZUKU", session, &command)
      #expect(command.output.preedit.cursor == 6)
      session.moveCursorLeft(&command)
      #expect(command.output.preedit.cursor == 5)
      command.input.command.cursorPosition = 3
      session.moveCursorTo(&command)
      #expect(command.output.preedit.cursor == 3)
      session.moveCursorRight(&command)
      #expect(command.output.preedit.cursor == 4)
    }
  }

  @Test func moveCursorPrecomposition() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()

      command.input.command.cursorPosition = 3
      session.moveCursorTo(&command)
      #expect(!command.output.hasPreedit)
      #expect(!command.output.consumed)
    }
  }

  @Test func moveCursorRightWithCommit() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      var request = f.mobileRequest
      request.specialRomanjiTable = .qwertyMobileToHalfwidthascii
      request.crossingEdgeBehavior = .commitWithoutConsuming
      f.initSessionToPrecomposition(session, request)
      var command = Genmai_Commands_Command()

      f.insertCharacterChars("MOZC", session, &command)
      #expect(command.output.preedit.cursor == 4)
      command = Genmai_Commands_Command()
      session.moveCursorLeft(&command)
      #expect(command.output.preedit.cursor == 3)
      command = Genmai_Commands_Command()
      session.moveCursorRight(&command)
      #expect(command.output.preedit.cursor == 4)
      command = Genmai_Commands_Command()
      session.moveCursorRight(&command)
      #expect(!command.output.consumed)
      try #require(command.output.hasResult)
      #expect(command.output.result.type == .string)
      #expect(command.output.result.value == "MOZC")
      #expect(command.output.result.cursorOffset == 0)
    }
  }

  @Test func moveCursorLeftWithCommit() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      var request = f.mobileRequest
      request.specialRomanjiTable = .qwertyMobileToHalfwidthascii
      request.crossingEdgeBehavior = .commitWithoutConsuming
      f.initSessionToPrecomposition(session, request)
      var command = Genmai_Commands_Command()

      f.insertCharacterChars("MOZC", session, &command)
      #expect(command.output.preedit.cursor == 4)
      for expected in [3, 2, 1, 0] {
        command = Genmai_Commands_Command()
        session.moveCursorLeft(&command)
        #expect(command.output.preedit.cursor == UInt32(expected))
      }
      command = Genmai_Commands_Command()

      session.moveCursorLeft(&command)
      #expect(!command.output.consumed)
      try #require(command.output.hasResult)
      #expect(command.output.result.type == .string)
      #expect(command.output.result.value == "MOZC")
      #expect(command.output.result.cursorOffset == -4)
    }
  }

  @Test func moveCursorRightWithCommitWithZeroQuerySuggestion() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      var request = f.mobileRequest
      request.specialRomanjiTable = .qwertyMobileToHalfwidthascii
      request.crossingEdgeBehavior = .commitWithoutConsuming
      f.setupZeroQuerySuggestionReady(true, session, &request, converter)
      var command = Genmai_Commands_Command()

      f.insertCharacterChars("GOOGLE", session, &command)
      #expect(command.output.preedit.cursor == 6)
      command = Genmai_Commands_Command()

      session.moveCursorRight(&command)
      #expect(!command.output.consumed)
      try #require(command.output.hasResult)
      #expect(command.output.result.type == .string)
      #expect(command.output.result.value == "GOOGLE")
      #expect(command.output.result.cursorOffset == 0)
      #expect(command.output.hasCandidateWindow)
      #expect(command.output.candidateWindow.candidate.count == 2)
    }
  }

  @Test func moveCursorLeftWithCommitWithZeroQuerySuggestion() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      var request = f.mobileRequest
      request.specialRomanjiTable = .qwertyMobileToHalfwidthascii
      request.crossingEdgeBehavior = .commitWithoutConsuming
      f.setupZeroQuerySuggestionReady(true, session, &request, converter)
      var command = Genmai_Commands_Command()

      f.insertCharacterChars("GOOGLE", session, &command)
      #expect(command.output.preedit.cursor == 6)
      command = Genmai_Commands_Command()
      for i in stride(from: 5, through: 0, by: -1) {
        session.moveCursorLeft(&command)
        #expect(command.output.preedit.cursor == UInt32(i))
        command = Genmai_Commands_Command()
      }

      session.moveCursorLeft(&command)
      #expect(!command.output.consumed)
      try #require(command.output.hasResult)
      #expect(command.output.result.type == .string)
      #expect(command.output.result.value == "GOOGLE")
      #expect(command.output.result.cursorOffset == -6)
      #expect(!command.output.hasCandidateWindow)
    }
  }

  @Test func commitHead() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      let table = Table()
      _ = table.addRule("mo", "も", "")
      _ = table.addRule("zu", "ず", "")

      session.internalComposerOnlyForUnittest.setTable(table)

      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()

      f.insertCharacterChars("moz", session, &command)
      #expect(getComposition(command) == "もｚ")
      command = Genmai_Commands_Command()
      session.commitHead(1, &command)
      #expect(command.output.result.type == .string)
      #expect(command.output.result.value == "も")
      #expect(getComposition(command) == "ｚ")
      f.insertCharacterChars("u", session, &command)
      #expect(getComposition(command) == "ず")
    }
  }

  @Test func passwordWithToggleAlphabetInput() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)

      var request = f.mobileRequest
      request.specialRomanjiTable = .twelveKeysToHalfwidthascii

      f.initSessionToPrecomposition(session, request)

      // Change to 12keys-halfascii mode.
      switchInputFieldType(.password, session)
      switchCompositionMode(.halfAscii, session)

      var command = Genmai_Commands_Command()
      sendKey("2", session, &command)
      #expect(getComposition(command) == "a")
      #expect(command.output.preedit.cursor == 1)

      sendKey("2", session, &command)
      #expect(getComposition(command) == "b")
      #expect(command.output.preedit.cursor == 1)

      // cursor key commits the preedit.
      sendKey("right", session, &command)
      // "b"
      #expect(command.output.result.type == .string)
      #expect(command.output.result.value == "b")
      #expect(getComposition(command) == "")
      #expect(command.output.preedit.cursor == 0)

      sendKey("2", session, &command)
      // "b[a]"
      #expect(command.output.result.type == .none)
      #expect(getComposition(command) == "a")
      #expect(command.output.preedit.cursor == 1)

      sendKey("4", session, &command)
      // ba[g]
      #expect(command.output.result.type == .string)
      #expect(command.output.result.value == "a")
      #expect(getComposition(command) == "g")
      #expect(command.output.preedit.cursor == 1)

      // cursor key commits the preedit.
      sendKey("left", session, &command)
      #expect(command.output.result.type == .string)
      #expect(command.output.result.value == "g")
      #expect(command.output.preedit.segment.count == 0)
      #expect(command.output.preedit.cursor == 0)
    }
  }

  @Test func switchInputFieldTypeTest() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      // initial state is NORMAL
      #expect(session.context.composer.getInputFieldType() == .normal)

      // Switch input field type to PASSWORD
      switchInputFieldType(.password, session)
      // Switch input field type to NORMAL
      switchInputFieldType(.normal, session)
    }
  }

  @Test func cursorKeysInPasswordMode() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)

      var request = f.mobileRequest
      request.specialRomanjiTable = .defaultTable
      session.setRequest(request)

      f.initSessionToPrecomposition(session, request)

      switchInputFieldType(.password, session)
      switchCompositionMode(.halfAscii, session)

      var command = Genmai_Commands_Command()
      // cursor key commits the preedit without moving system cursor.
      sendKey("m", session, &command)
      #expect(command.output.result.type == .none)
      command = Genmai_Commands_Command()
      session.moveCursorLeft(&command)
      #expect(command.output.result.type == .string)
      #expect(command.output.result.value == "m")
      #expect(getComposition(command) == "")
      #expect(command.output.preedit.cursor == 0)
      #expect(command.output.consumed)

      sendKey("o", session, &command)
      #expect(command.output.result.type == .none)
      command = Genmai_Commands_Command()
      session.moveCursorRight(&command)
      #expect(command.output.result.type == .string)
      #expect(command.output.result.value == "o")
      #expect(getComposition(command) == "")
      #expect(command.output.preedit.cursor == 0)
      #expect(command.output.consumed)

      sendKey("z", session, &command)
      #expect(command.output.result.type == .none)
      setSendCommandCommand(.moveCursor, &command)
      command.input.command.cursorPosition = 3
      session.moveCursorTo(&command)
      #expect(command.output.result.value == "z")
      #expect(getComposition(command) == "")
      #expect(command.output.preedit.cursor == 0)
      #expect(command.output.consumed)
    }
  }

  @Test func backKeyCommitsPreeditInPasswordMode() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()
      var request = Genmai_Commands_Request()

      request.zeroQuerySuggestion = false
      request.specialRomanjiTable = .defaultTable
      session.setRequest(request)

      session.setTable(makeTable(request))

      switchInputFieldType(.password, session)
      switchCompositionMode(.halfAscii, session)

      sendKey("m", session, &command)
      #expect(command.output.result.type == .none)
      #expect(getComposition(command) == "m")
      sendKey("esc", session, &command)
      #expect(command.output.result.type == .string)
      #expect(command.output.result.value == "m")
      #expect(getComposition(command) == "")
      #expect(!command.output.consumed)

      sendKey("o", session, &command)
      sendKey("z", session, &command)
      #expect(command.output.result.type == .string)
      #expect(command.output.result.value == "o")
      #expect(getComposition(command) == "z")
      sendKey("esc", session, &command)
      #expect(command.output.result.type == .string)
      #expect(command.output.result.value == "z")
      #expect(getComposition(command) == "")
      #expect(!command.output.consumed)

      // in normal mode, preedit is cleared without commit.
      switchInputFieldType(.normal, session)

      sendKey("m", session, &command)
      #expect(command.output.result.type == .none)
      #expect(getComposition(command) == "m")
      sendKey("esc", session, &command)
      #expect(command.output.consumed)
      #expect(command.output.result.type == .none)
      #expect(!command.output.hasPreedit)
    }
  }

  @Test func editCancel() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      let segmentsMo = makeSegmentsMo()

      do {  // Cancel of Suggestion
        var command = Genmai_Commands_Command()
        sendKey("M", session, &command)

        setStartPredictionOnce(converter, segmentsMo)
        sendKey("O", session, &command)
        try #require(command.output.hasCandidateWindow)
        #expect(command.output.candidateWindow.candidate.count == 2)
        #expect(command.output.candidateWindow.candidate.first?.value == "MOCHA")

        command = Genmai_Commands_Command()
        session.editCancel(&command)
        #expect(getComposition(command) == "")
        #expect(command.output.candidateWindow.candidate.count == 0)
        #expect(!command.output.hasResult)
      }

      do {  // Cancel of Reverse conversion
        var command = Genmai_Commands_Command()

        // "[MO]" is a converted string like Kanji.
        // "MO" is an input string like Hiragana.
        f.setupCommandForReverseConversion("[MO]", &command.input)
        f.setupMockForReverseConversion("[MO]", "MO", converter)
        #expect(session.sendCommand(&command))

        command = Genmai_Commands_Command()
        setStartPredictionOnce(converter, segmentsMo)
        session.convertCancel(&command)
        try #require(command.output.hasCandidateWindow)
        #expect(command.output.candidateWindow.candidate.count == 2)
        #expect(command.output.candidateWindow.candidate.first?.value == "MOCHA")

        command = Genmai_Commands_Command()
        session.editCancel(&command)
        #expect(getComposition(command) == "")
        #expect(command.output.candidateWindow.candidate.count == 0)
        // test case against b/5566728
        expectResult("[MO]", command)
      }
    }
  }

  @Test func imeOff() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)

      var resetCount = 0
      converter.resetConversionHandler = { _ in resetCount += 1 }
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()
      session.imeOff(&command)
      #expect(resetCount == 1)
    }
  }

  private static let kCancelAndIMEOffKeymapTable =
    "status\tkey\tcommand\n"
    + "Precomposition\thankaku/zenkaku\tCancelAndIMEOff\n"
    + "Composition\thankaku/zenkaku\tCancelAndIMEOff\n"
    + "Conversion\thankaku/zenkaku\tCancelAndIMEOff\n"

  @Test func editCancelAndIMEOff() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      var config = Genmai_Config_Config()
      config.sessionKeymap = .custom
      config.customKeymapTable = Data(SessionTests4.kCancelAndIMEOffKeymapTable.utf8)

      let segmentsMo = makeSegmentsMo()

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      do {  // Cancel of Precomposition and deactivate IME
        let session = makeSessionWithKeymap(engine, config)
        f.initSessionToPrecomposition(session)

        var command = Genmai_Commands_Command()
        #expect(testSendKey("hankaku/zenkaku", session, &command))
        #expect(command.output.consumed)

        #expect(sendKey("hankaku/zenkaku", session, &command))
        #expect(command.output.consumed)
        #expect(getComposition(command) == "")
        #expect(command.output.candidateWindow.candidate.count == 0)
        #expect(!command.output.hasResult)
        try #require(command.output.hasStatus)
        #expect(!command.output.status.activated)
      }

      do {  // Cancel of Composition and deactivate IME
        let session = makeSessionWithKeymap(engine, config)
        f.initSessionToPrecomposition(session)

        var command = Genmai_Commands_Command()
        sendKey("M", session, &command)

        #expect(testSendKey("hankaku/zenkaku", session, &command))
        #expect(command.output.consumed)

        #expect(sendKey("hankaku/zenkaku", session, &command))
        #expect(command.output.consumed)
        #expect(getComposition(command) == "")
        #expect(command.output.candidateWindow.candidate.count == 0)
        #expect(!command.output.hasResult)
        try #require(command.output.hasStatus)
        #expect(!command.output.status.activated)
      }

      do {  // Cancel of Suggestion and deactivate IME
        let session = makeSessionWithKeymap(engine, config)
        f.initSessionToPrecomposition(session)

        var command = Genmai_Commands_Command()
        sendKey("M", session, &command)

        converter.setStartPrediction(segmentsMo, true)
        sendKey("O", session, &command)
        try #require(command.output.hasCandidateWindow)
        #expect(command.output.candidateWindow.candidate.count == 2)
        #expect(command.output.candidateWindow.candidate.first?.value == "MOCHA")

        #expect(testSendKey("hankaku/zenkaku", session, &command))
        #expect(command.output.consumed)

        #expect(sendKey("hankaku/zenkaku", session, &command))
        #expect(command.output.consumed)
        #expect(getComposition(command) == "")
        #expect(command.output.candidateWindow.candidate.count == 0)
        #expect(!command.output.hasResult)
        try #require(command.output.hasStatus)
        #expect(!command.output.status.activated)
      }

      do {  // Cancel of Conversion and deactivate IME
        let session = makeSessionWithKeymap(engine, config)
        f.initSessionToConversionWithAiueo(session, converter)

        var command = Genmai_Commands_Command()
        #expect(testSendKey("hankaku/zenkaku", session, &command))
        #expect(command.output.consumed)

        #expect(sendKey("hankaku/zenkaku", session, &command))
        #expect(command.output.consumed)
        #expect(getComposition(command) == "")
        #expect(command.output.candidateWindow.candidate.count == 0)
        #expect(!command.output.hasResult)
        try #require(command.output.hasStatus)
        #expect(!command.output.status.activated)
      }

      do {  // Cancel of Reverse conversion and deactivate IME
        let session = makeSessionWithKeymap(engine, config)
        f.initSessionToPrecomposition(session)

        var command = Genmai_Commands_Command()

        // "[MO]" is a converted string like Kanji.
        // "MO" is an input string like Hiragana.
        f.setupCommandForReverseConversion("[MO]", &command.input)
        f.setupMockForReverseConversion("[MO]", "MO", converter)
        #expect(session.sendCommand(&command))

        command = Genmai_Commands_Command()
        converter.setStartPrediction(segmentsMo, true)
        session.convertCancel(&command)
        try #require(command.output.hasCandidateWindow)
        #expect(command.output.candidateWindow.candidate.count == 2)
        #expect(command.output.candidateWindow.candidate.first?.value == "MOCHA")

        #expect(testSendKey("hankaku/zenkaku", session, &command))
        #expect(command.output.consumed)

        #expect(sendKey("hankaku/zenkaku", session, &command))
        #expect(command.output.consumed)
        #expect(getComposition(command) == "")
        #expect(command.output.candidateWindow.candidate.count == 0)
        expectResult("[MO]", command)
        try #require(command.output.hasStatus)
        #expect(!command.output.status.activated)
      }
    }
  }

  // TODO(matsuzakit): Update the expected result when b/5955618 is fixed.
  @Test func cancelInPasswordModeIssue5955618() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      var config = Genmai_Config_Config()
      config.sessionKeymap = .custom
      config.customKeymapTable = Data(
        ("status\tkey\tcommand\n" + "Precomposition\tESC\tCancel\n"
          + "Composition\tESC\tCancel\n" + "Conversion\tESC\tCancel\n").utf8)

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      do {  // Cancel of Precomposition in password field
        // Basically this is unusual because there is no character to be canceled
        // when Precomposition state.
        let session = makeSessionWithKeymap(engine, config)
        f.initSessionToPrecomposition(session)
        switchInputFieldType(.password, session)

        var command = Genmai_Commands_Command()
        #expect(testSendKey("ESC", session, &command))
        #expect(command.output.consumed)  // should be consumed, anyway.

        #expect(sendKey("ESC", session, &command))
        // This behavior is the bug of b/5955618.
        // The result of TestSendKey and SendKey should be the same in terms of
        // |consumed()|.
        #expect(!command.output.consumed, "Congrats! b/5955618 seems to be fixed")
      }

      do {  // Cancel of Composition in password field
        let session = makeSessionWithKeymap(engine, config)
        f.initSessionToPrecomposition(session)
        switchInputFieldType(.password, session)

        var command = Genmai_Commands_Command()
        #expect(testSendKey("ESC", session, &command))
        #expect(command.output.consumed)

        #expect(sendKey("ESC", session, &command))
        // This behavior is the bug of b/5955618.
        #expect(!command.output.consumed, "Congrats! b/5955618 seems to be fixed")
      }

      do {  // Cancel of Conversion in password field
        let session = makeSessionWithKeymap(engine, config)
        f.initSessionToConversionWithAiueo(session, converter)
        switchInputFieldType(.password, session)

        // Actually this works well because Cancel command in conversion mode
        // is mapped into ConvertCancel not EditCancel.
        var command = Genmai_Commands_Command()
        #expect(testSendKey("ESC", session, &command))
        #expect(command.output.consumed)
        #expect(sendKey("ESC", session, &command))
        #expect(command.output.consumed)
        #expect(!command.output.hasResult)

        #expect(session.context.state == .composition)
      }

      do {  // Cancel of Reverse conversion in password field
        let session = makeSessionWithKeymap(engine, config)
        f.initSessionToPrecomposition(session)
        switchInputFieldType(.password, session)

        var command = Genmai_Commands_Command()

        // "[MO]" is a converted string like Kanji.
        // "MO" is an input string like Hiragana.
        f.setupCommandForReverseConversion("[MO]", &command.input)
        f.setupMockForReverseConversion("[MO]", "MO", converter)
        #expect(session.sendCommand(&command))

        // Actually this works well because Cancel command in conversion mode
        // is mapped into ConvertCancel not EditCancel.
        #expect(testSendKey("ESC", session, &command))
        #expect(command.output.consumed)
        #expect(sendKey("ESC", session, &command))
        #expect(command.output.consumed)
        #expect(!command.output.hasResult)
        #expect(session.context.state == .composition)

        // The second escape key will be mapped into EditCancel.
        #expect(testSendKey("ESC", session, &command))
        #expect(command.output.consumed)
        #expect(sendKey("ESC", session, &command))
        // This behavior is the bug of b/5955618.
        #expect(!command.output.consumed, "Congrats! b/5955618 seems to be fixed")
        expectResult("[MO]", command)
      }
    }
  }

  // TODO(matsuzakit): Update the expected result when b/5955618 is fixed.
  @Test func cancelAndIMEOffInPasswordModeIssue5955618() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      var config = Genmai_Config_Config()
      config.sessionKeymap = .custom
      config.customKeymapTable = Data(SessionTests4.kCancelAndIMEOffKeymapTable.utf8)

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      do {  // Cancel of Precomposition and deactivate IME in password field.
        let session = makeSessionWithKeymap(engine, config)
        f.initSessionToPrecomposition(session)
        switchInputFieldType(.password, session)

        var command = Genmai_Commands_Command()
        #expect(testSendKey("hankaku/zenkaku", session, &command))
        #expect(command.output.consumed)

        #expect(sendKey("hankaku/zenkaku", session, &command))
        // This behavior is the bug of b/5955618.
        #expect(!command.output.consumed, "Congrats! b/5955618 seems to be fixed")
        #expect(getComposition(command) == "")
        #expect(command.output.candidateWindow.candidate.count == 0)
        #expect(!command.output.hasResult)
        // Current behavior seems to be a bug.
        // This command should deactivate the IME.
        try #require(!command.output.hasStatus, "Congrats! b/5955618 seems to be fixed.")
      }

      do {  // Cancel of Composition and deactivate IME in password field
        let session = makeSessionWithKeymap(engine, config)
        f.initSessionToPrecomposition(session)
        switchInputFieldType(.password, session)

        var command = Genmai_Commands_Command()
        #expect(testSendKey("hankaku/zenkaku", session, &command))
        #expect(command.output.consumed)

        #expect(sendKey("hankaku/zenkaku", session, &command))
        // This behavior is the bug of b/5955618.
        #expect(!command.output.consumed, "Congrats! b/5955618 seems to be fixed")
        #expect(getComposition(command) == "")
        #expect(command.output.candidateWindow.candidate.count == 0)
        #expect(!command.output.hasResult)
        // Following behavior seems to be a bug.
        // This command should deactivate the IME.
        try #require(!command.output.hasStatus, "Congrats! b/5955618 seems to be fixed.")
      }

      do {  // Cancel of Conversion and deactivate IME in password field
        let session = makeSessionWithKeymap(engine, config)
        f.initSessionToConversionWithAiueo(session, converter)
        switchInputFieldType(.password, session)

        var command = Genmai_Commands_Command()
        #expect(testSendKey("hankaku/zenkaku", session, &command))
        #expect(command.output.consumed)
        command = Genmai_Commands_Command()
        // This behavior is the bug of b/5955618.
        #expect(!command.output.consumed, "Congrats! b/5955618 seems to be fixed")
        #expect(getComposition(command) == "")
        #expect(command.output.candidateWindow.candidate.count == 0)
        #expect(!command.output.hasResult)
        // Following behavior seems to be a bug.
        // This command should deactivate the IME.
        try #require(!command.output.hasStatus, "Congrats! b/5955618 seems to be fixed.")
      }

      do {  // Cancel of Reverse conversion and deactivate IME in password field
        let session = makeSessionWithKeymap(engine, config)
        f.initSessionToPrecomposition(session)
        switchInputFieldType(.password, session)

        var command = Genmai_Commands_Command()

        // "[MO]" is a converted string like Kanji.
        // "MO" is an input string like Hiragana.
        f.setupCommandForReverseConversion("[MO]", &command.input)
        f.setupMockForReverseConversion("[MO]", "MO", converter)
        #expect(session.sendCommand(&command))

        #expect(testSendKey("hankaku/zenkaku", session, &command))
        #expect(command.output.consumed)
        #expect(sendKey("hankaku/zenkaku", session, &command))
        // This behavior is the bug of b/5955618.
        #expect(!command.output.consumed, "Congrats! b/5955618 seems to be fixed")
        expectResult("[MO]", command)
        try #require(command.output.hasStatus)
        // This behavior is the bug of b/5955618. IME should be deactivated.
        #expect(command.output.status.activated, "Congrats! b/5955618 seems to be fixed")
      }
    }
  }

  @Test func doNothingOnCompositionKeepingSuggestWindow() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      setStartPredictionOnce(converter, makeSegmentsMo())

      var command = Genmai_Commands_Command()
      sendKey("M", session, &command)
      #expect(command.output.hasCandidateWindow)

      sendKey("Ctrl", session, &command)
      #expect(command.output.hasCandidateWindow)
    }
  }

  @Test func modeChangeOfConvertAtPunctuations() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      var config = Genmai_Config_Config()
      config.useAutoConversion = true

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      session.setConfig(config)
      f.initSessionToPrecomposition(session)

      let segmentsAConv = Segments()
      do {
        let segment = segmentsAConv.addSegment()
        segment.setKey("あ")
        segment.addCandidate().value = "あ"
      }
      setStartConversionOnce(converter, segmentsAConv)

      var command = Genmai_Commands_Command()
      sendKey("a", session, &command)  // "あ|" (composition)
      #expect(session.context.state == .composition)

      sendKey(".", session, &command)  // "あ。|" (conversion)
      #expect(session.context.state == .conversion)

      sendKey("ESC", session, &command)  // "あ。|" (composition)
      #expect(session.context.state == .composition)

      sendKey("Left", session, &command)  // "あ|。" (composition)
      #expect(session.context.state == .composition)

      sendKey("i", session, &command)  // "あい|。" (should be composition)
      #expect(session.context.state == .composition)
    }
  }

  @Test
  func suppressSuggestion() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let session = Session(try f.mockDataEngine())
      f.initSessionToPrecomposition(session)

      var command = Genmai_Commands_Command()
      sendKey("a", session, &command)
      #expect(command.output.hasCandidateWindow)

      command = Genmai_Commands_Command()
      session.editCancel(&command)
      #expect(!command.output.hasCandidateWindow)

      // Default behavior.
      sendKey("d", session, &command)
      #expect(command.output.hasCandidateWindow)

      // Suppress suggestion context
      setSendKeyCommand("e", &command)
      command.input.context.suppressSuggestion = true
      session.sendKey(&command)
      #expect(!command.output.hasCandidateWindow)

      // With an invalid identifier.  It should be the same with the
      // default behavior.
      setSendKeyCommand("i", &command)
      command.input.context.experimentalFeatures.append("invalid_identifier")
      session.sendKey(&command)
      #expect(command.output.hasCandidateWindow)
    }
  }

  @Test func deleteHistory() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey("delete")
      segment.addCandidate().value = "DeleteHistory"
      converter.setStartPredictionWithPreviousSuggestion(segments, true)

      // Type "del". Preedit = "でｌ".
      var command = Genmai_Commands_Command()
      #expect(sendKey("d", session, &command))
      #expect(sendKey("e", session, &command))
      #expect(sendKey("l", session, &command))
      expectPreedit("でｌ", command)

      // Start prediction. Preedit = "DeleteHistory".
      command = Genmai_Commands_Command()
      #expect(session.predictAndConvert(&command))
      #expect(command.output.hasCandidateWindow)
      #expect(session.context.state == .conversion)
      expectPreedit("DeleteHistory", command)

      // Do DeleteHistory command. After that, the session should be back in
      // composition state and preedit gets back to "でｌ" again.
      var deleteArgs: [(Int, Int)] = []
      converter.deleteCandidateFromHistoryHandler = { _, segmentIndex, candidateIndex in
        deleteArgs.append((segmentIndex, candidateIndex))
        return deleteArgs.count == 1
      }
      #expect(sendKey("Ctrl Delete", session, &command))
      #expect(session.context.state == .composition)
      expectPreedit("でｌ", command)
      #expect(deleteArgs.count == 1)
      #expect(deleteArgs.first.map { $0 == (0, 0) } ?? false)
    }
  }

  @Test func sendKeyWithKeyStringDirect() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToDirect(session)

      var command = Genmai_Commands_Command()
      let kZa = "ざ"
      setSendKeyCommandWithKeyString(kZa, &command)
      #expect(session.testSendKey(&command))
      #expect(!command.output.consumed)
      command.output = Genmai_Commands_Output()
      #expect(session.sendKey(&command))
      #expect(!command.output.consumed)
    }
  }

  @Test func sendKeyWithKeyString() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Genmai_Commands_Command()

      // Test for precomposition state.
      #expect(session.context.state == .precomposition)
      let kZa = "ざ"
      setSendKeyCommandWithKeyString(kZa, &command)
      #expect(session.testSendKey(&command))
      #expect(command.output.consumed)
      command.output = Genmai_Commands_Output()
      #expect(session.sendKey(&command))
      #expect(command.output.consumed)
      expectPreedit(kZa, command)

      command = Genmai_Commands_Command()

      // Test for composition state.
      #expect(session.context.state == .composition)
      let kOnsenManju = "♨饅頭"
      setSendKeyCommandWithKeyString(kOnsenManju, &command)
      #expect(session.testSendKey(&command))
      #expect(command.output.consumed)
      command.output = Genmai_Commands_Output()
      #expect(session.sendKey(&command))
      #expect(command.output.consumed)
      expectPreedit(kZa + kOnsenManju, command)
    }
  }

  @Test func indirectImeOnOff() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      do {
        var command = Genmai_Commands_Command()
        // IMEOff
        sendSpecialKey(.off, session, &command)
      }
      do {
        var command = Genmai_Commands_Command()
        // 'a'
        testSendKeyWithModeAndActivated("a", true, .hiragana, session, &command)
        #expect(command.output.consumed)
      }
      do {
        var command = Genmai_Commands_Command()
        // 'a'
        sendKeyWithModeAndActivated("a", true, .hiragana, session, &command)
        #expect(command.output.consumed)
        #expect(command.output.hasStatus)
        #expect(command.output.status.activated, "Should be activated.")
      }
      do {
        var command = Genmai_Commands_Command()
        // 'a'
        testSendKeyWithModeAndActivated("a", false, .hiragana, session, &command)
        #expect(!command.output.consumed)
      }
      do {
        var command = Genmai_Commands_Command()
        // 'a'
        sendKeyWithModeAndActivated("a", false, .hiragana, session, &command)
        #expect(!command.output.consumed)
        #expect(!command.output.hasResult, "Indirect IME off flushes ongoing composition")
        #expect(command.output.hasStatus)
        #expect(!command.output.status.activated, "Should be inactivated.")
      }
    }
  }

  @Test func makeSureIMEOn() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToDirect(session)

      do {
        var command = Genmai_Commands_Command()
        setSendCommandCommand(.turnOnIme, &command)

        try #require(session.sendCommand(&command))
        #expect(command.output.consumed)
        try #require(command.output.hasStatus)
        #expect(command.output.status.activated)
      }

      do {
        // Make sure we can change the input mode.
        var command = Genmai_Commands_Command()
        setSendCommandCommand(.turnOnIme, &command)
        command.input.command.compositionMode = .fullKatakana

        try #require(session.sendCommand(&command))
        #expect(command.output.consumed)
        try #require(command.output.hasStatus)
        #expect(command.output.status.activated)
        #expect(command.output.status.mode == .fullKatakana)
      }

      do {
        // Make sure we can change the input mode again.
        var command = Genmai_Commands_Command()
        setSendCommandCommand(.turnOnIme, &command)
        command.input.command.compositionMode = .hiragana

        try #require(session.sendCommand(&command))
        #expect(command.output.consumed)
        try #require(command.output.hasStatus)
        #expect(command.output.status.activated)
        #expect(command.output.status.mode == .hiragana)
      }

      do {
        // commands::DIRECT is not supported for the composition_mode.
        var command = Genmai_Commands_Command()
        setSendCommandCommand(.turnOnIme, &command)
        command.input.command.compositionMode = .direct
        #expect(!session.sendCommand(&command))
      }
    }
  }

  @Test func makeSureIMEOff() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      do {
        var command = Genmai_Commands_Command()
        setSendCommandCommand(.turnOffIme, &command)

        try #require(session.sendCommand(&command))
        #expect(command.output.consumed)
        try #require(command.output.hasStatus)
        #expect(!command.output.status.activated)
      }

      do {
        // Make sure we can change the input mode.
        var command = Genmai_Commands_Command()
        setSendCommandCommand(.turnOffIme, &command)
        command.input.command.compositionMode = .fullKatakana

        try #require(session.sendCommand(&command))
        #expect(command.output.consumed)
        try #require(command.output.hasStatus)
        #expect(!command.output.status.activated)
        #expect(command.output.status.mode == .fullKatakana)
      }

      do {
        // Make sure we can change the input mode again.
        var command = Genmai_Commands_Command()
        setSendCommandCommand(.turnOffIme, &command)
        command.input.command.compositionMode = .hiragana

        try #require(session.sendCommand(&command))
        #expect(command.output.consumed)
        try #require(command.output.hasStatus)
        #expect(!command.output.status.activated)
        #expect(command.output.status.mode == .hiragana)
      }

      do {
        // commands::DIRECT is not supported for the composition_mode.
        var command = Genmai_Commands_Command()
        setSendCommandCommand(.turnOffIme, &command)
        command.input.command.compositionMode = .direct
        #expect(!session.sendCommand(&command))
      }
    }
  }

  @Test func makeSureIMEOffWithCommitComposition() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      // Make sure SessionCommand::TURN_OFF_IME terminates the existing
      // composition.

      f.initSessionToPrecomposition(session)

      // Set up converter.
      do {
        var command = Genmai_Commands_Command()
        f.insertCharacterChars("aiueo", session, &command)
      }

      // Send SessionCommand::TURN_OFF_IME to commit composition.
      do {
        var command = Genmai_Commands_Command()
        setSendCommandCommand(.turnOffIme, &command)
        command.input.command.compositionMode = .fullKatakana
        try #require(session.sendCommand(&command))
        expectResult("あいうえお", command)
        #expect(command.output.consumed)
        try #require(command.output.hasStatus)
        #expect(!command.output.status.activated)
        #expect(command.output.status.mode == .fullKatakana)
      }
    }
  }

  @Test func deleteCandidateFromHistory() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      // InitSessionToConversionWithAiueo initializes candidates as follows:
      // 0:あいうえお, 1:アイウエオ, -3:aiueo, -4:AIUEO, ...
      do {
        // A test case to delete focused candidate (i.e. without candidate ID).
        let session = Session(engine)
        f.initSessionToConversionWithAiueo(session, converter)

        var args: [(Int, Int)] = []
        converter.deleteCandidateFromHistoryHandler = { _, s, c in
          args.append((s, c))
          return true
        }

        var command = Genmai_Commands_Command()
        session.deleteCandidateFromHistory(&command)

        #expect(args.count == 1)
        #expect(args.first.map { $0 == (0, 0) } ?? false)
        converter.clear()
      }
      do {
        // A test case to delete candidate by ID.
        let session = Session(engine)
        f.initSessionToConversionWithAiueo(session, converter)

        var args: [(Int, Int)] = []
        converter.deleteCandidateFromHistoryHandler = { _, s, c in
          args.append((s, c))
          return true
        }

        var command = Genmai_Commands_Command()
        setSendCommandCommand(.deleteCandidateFromHistory, &command)
        command.input.command.id = 1
        session.deleteCandidateFromHistory(&command)

        #expect(args.count == 1)
        #expect(args.first.map { $0 == (0, 1) } ?? false)
        converter.clear()
      }
    }
  }

  @Test func setConfig() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      var config = ConfigHandler.defaultConfig()
      config.sessionKeymap = .custom
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)
      let session = Session(engine)
      let sessionPeer = SessionTestPeer(session)
      sessionPeer.pushUndoContext()
      session.setConfig(config)

      // (C++ compares the shared_ptr identity; values are compared here.)
      #expect(sessionPeer.context.getConfig() == config)
      // SetConfig() resets undo context.
      #expect(sessionPeer.undoContexts.isEmpty)
    }
  }

  @Test func clearCompositionByBackspace() throws {
    try withScopedSessionEnvironment {
      // The internal candidate list should be cleared when the composition is
      // cleared by backspace.
      let f = try SessionTestFixture()
      let segments = Segments()
      do {
        // Set up a mock conversion result.
        let segment = segments.addSegment()
        segment.setKey("あ")
        segment.addCandidate().value = "あ"
      }

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)
      setStartPredictionOnce(converter, segments)

      let session = Session(engine)
      f.initSessionToPrecomposition(session, f.mobileRequest)
      var command = Genmai_Commands_Command()

      #expect(sendKey("1", session, &command))
      expectSingleSegment("あ", command)
      #expect(command.output.hasAllCandidateWords)

      #expect(sendKey("Backspace", session, &command))
      #expect(!command.output.hasPreedit)
      #expect(!command.output.hasAllCandidateWords)

      // Input mode switch command can output the current internal candidate list,
      // which should be cleared by the above backspace.
      session.compositionModeSwitchKanaType(&command)
      #expect(!command.output.hasPreedit)
      #expect(!command.output.hasAllCandidateWords)
    }
  }

  @Test func clearCompositionByEscape() throws {
    try withScopedSessionEnvironment {
      // The internal candidate list should be cleared when the composition is
      // cleared by escape.
      let f = try SessionTestFixture()
      let segments = Segments()
      do {
        // Set up a mock conversion result.
        let segment = segments.addSegment()
        segment.setKey("あ")
        segment.addCandidate().value = "あ"
      }

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)
      setStartPredictionOnce(converter, segments)

      let session = Session(engine)
      f.initSessionToPrecomposition(session, f.mobileRequest)
      var command = Genmai_Commands_Command()

      #expect(sendKey("1", session, &command))
      expectSingleSegment("あ", command)
      #expect(command.output.hasAllCandidateWords)

      #expect(sendKey("Escape", session, &command))
      #expect(!command.output.hasPreedit)
      #expect(!command.output.hasAllCandidateWords)

      // Input mode switch command can output the current internal candidate list,
      // which should be cleared by the above backspace.
      session.compositionModeSwitchKanaType(&command)
      #expect(!command.output.hasPreedit)
      #expect(!command.output.hasAllCandidateWords)
    }
  }

  @Test func requestNWP() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      do {
        // Set up a mock suggestion result.
        let segments = Segments()
        let segment = segments.addSegment()
        segment.setKey("")
        addCandidate("predicted", "predicted", segment)
        setStartPredictionOnce(converter, segments)
      }

      var command = Genmai_Commands_Command()
      command.input.type = .sendCommand
      command.input.command.type = .requestNwp
      command.input.requestSuggestion = true

      #expect(session.sendCommand(&command))
      #expect(command.output.hasAllCandidateWords)
      #expect(command.output.allCandidateWords.candidates.count == 1)
      #expect(command.output.allCandidateWords.candidates.first?.value == "predicted")
      converter.clear()

      // If request_suggestion is false, StartPrediction should not be called.
      var startPredictionCount = 0
      converter.startPredictionHandler = { _, _ in
        startPredictionCount += 1
        return false
      }
      command = Genmai_Commands_Command()
      command.input.type = .sendCommand
      command.input.command.type = .requestNwp
      command.input.requestSuggestion = false
      #expect(!session.sendCommand(&command))
      #expect(startPredictionCount == 0)
      #expect(!command.output.hasAllCandidateWords)
    }
  }

  @Test func multiSegmentSelectionFocusRightAndLeft() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)
      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Genmai_Commands_Command()
      f.insertCharacterChars("watasinonamaehanakanodesu", session, &command)

      setStartConversionOnce(converter, createMultiSegmentTestData())
      converter.focusSegmentValueHandler = { _, _, _ in true }
      setCommitSegmentValueMoveCandidate(converter)
      var finishCount = 0
      converter.finishConversionHandler = { _, _ in finishCount += 1 }

      command = Genmai_Commands_Command()
      session.convert(&command)
      try #require(command.output.hasPreedit)

      // Select "私の名前は" (candidate 1 on segment 0).
      command = Genmai_Commands_Command()
      session.convertNext(&command)
      try #require(command.output.hasPreedit)
      try #require(command.output.preedit.segment.count > 0)
      try #require(command.output.preedit.segment[0].value == "私の名前は")

      // Preedit: [私の名前は] 中野です
      let segmentCount = command.output.preedit.segment.count
      #expect(segmentCount >= 2)

      // Focus right -> moves to next segment ("中野です").
      command = Genmai_Commands_Command()
      session.segmentFocusRight(&command)
      #expect(command.output.preedit.segment.count == segmentCount)
      #expect(command.output.preedit.segment.first?.value == "私の名前は")

      // Focus left -> moves back to "私の名前は".
      command = Genmai_Commands_Command()
      session.segmentFocusLeft(&command)
      // Preedit should remain: [私の名前は] 中野です ("中野です" must NOT
      // disappear)
      #expect(command.output.preedit.segment.count == segmentCount)
      #expect(command.output.preedit.segment.first?.value == "私の名前は")
      for i in 1..<segmentCount where i < command.output.preedit.segment.count {
        #expect(!command.output.preedit.segment[i].value.isEmpty)
      }

      // Change candidate on segment 0 back to a single-segment candidate.
      // "名前は" must NOT disappear from preedit.
      command = Genmai_Commands_Command()
      session.convertNext(&command)
      try #require(command.output.hasPreedit)
      #expect(command.output.preedit.segment.count > segmentCount)
      #expect(command.output.preedit.segment.first?.value != "私の名前は")

      var fullPreedit = ""
      for segment in command.output.preedit.segment {
        fullPreedit += segment.value
      }
      #expect(fullPreedit.contains("名前は") || fullPreedit.contains("なまえは"))
      #expect(
        fullPreedit.contains("中野") || fullPreedit.contains("中ノ")
          || fullPreedit.contains("なか"))

      // Cycle back to "私の名前は" and commit.
      command = Genmai_Commands_Command()
      session.convertNext(&command)
      try #require(command.output.hasPreedit)
      try #require(command.output.preedit.segment.first?.value == "私の名前は")

      // Commit the conversion.
      command = Genmai_Commands_Command()
      session.commit(&command)
      try #require(command.output.hasResult)
      #expect(command.output.result.value.hasPrefix("私の名前は"))
      #expect(finishCount >= 1)
    }
  }

  @Test func multiSegmentSelectionCommitDirect() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)
      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Genmai_Commands_Command()
      f.insertCharacterChars("watasinonamaehanakanodesu", session, &command)

      setStartConversionOnce(converter, createMultiSegmentTestData())
      converter.focusSegmentValueHandler = { _, _, _ in true }
      setCommitSegmentValueMoveCandidate(converter)
      var finishCount = 0
      converter.finishConversionHandler = { _, _ in finishCount += 1 }

      command = Genmai_Commands_Command()
      session.convert(&command)
      try #require(command.output.hasPreedit)

      // Select "私の名前は"
      command = Genmai_Commands_Command()
      session.convertNext(&command)
      try #require(command.output.hasPreedit)
      try #require(command.output.preedit.segment.first?.value == "私の名前は")

      // Commit directly without moving focus.
      command = Genmai_Commands_Command()
      session.commit(&command)
      try #require(command.output.hasResult)
      #expect(command.output.result.value.hasPrefix("私の名前は"))
      #expect(finishCount >= 1)
    }
  }

  @Test func multiSegmentSelectionCancel() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)
      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Genmai_Commands_Command()
      f.insertCharacterChars("watasinonamaehanakanodesu", session, &command)

      setStartConversionOnce(converter, createMultiSegmentTestData())
      converter.focusSegmentValueHandler = { _, _, _ in true }
      setCommitSegmentValueMoveCandidate(converter)
      var cancelCount = 0
      converter.cancelConversionHandler = { _ in cancelCount += 1 }

      command = Genmai_Commands_Command()
      session.convert(&command)
      try #require(command.output.hasPreedit)

      // Select "私の名前は"
      command = Genmai_Commands_Command()
      session.convertNext(&command)
      try #require(command.output.hasPreedit)
      try #require(command.output.preedit.segment.first?.value == "私の名前は")

      // Focus right
      command = Genmai_Commands_Command()
      session.segmentFocusRight(&command)

      // Cancel conversion -> returns to composition/preedit.
      command = Genmai_Commands_Command()
      session.convertCancel(&command)
      try #require(command.output.hasPreedit)
      #expect(command.output.preedit.segment.count == 1)
      #expect(command.output.preedit.segment.first?.value == "わたしのなまえはなかのです")
      #expect(cancelCount >= 1)
    }
  }

  @Test func multiSegmentSubmitCandidate() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)
      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Genmai_Commands_Command()
      f.insertCharacterChars("kokodehakimonowonugu", session, &command)

      let segments = Segments()
      do {
        let seg0 = segments.addSegment()
        seg0.setKey("ここでは")
        let cand00 = seg0.addCandidate()
        cand00.value = "ここでは"
        cand00.key = "ここでは"
        cand00.contentKey = "ここでは"
        cand00.convertedSegmentCount = 1
        let cand01 = seg0.addCandidate()
        cand01.value = "ここで履物を"
        cand01.key = "ここではきものを"
        cand01.contentKey = "ここではきものを"
        cand01.convertedSegmentCount = 2

        let seg1 = segments.addSegment()
        seg1.setKey("きものを")
        let cand10 = seg1.addCandidate()
        cand10.value = "着物を"
        cand10.key = "きものを"
        cand10.contentKey = "きものを"
        cand10.convertedSegmentCount = 1

        let seg2 = segments.addSegment()
        seg2.setKey("ぬぐ")
        let cand20 = seg2.addCandidate()
        cand20.value = "脱ぐ"
        cand20.key = "ぬぐ"
        cand20.contentKey = "ぬぐ"
        cand20.convertedSegmentCount = 1
      }

      setStartConversionOnce(converter, segments)
      converter.focusSegmentValueHandler = { _, _, _ in true }
      var commitSegmentsUsed = false
      var commitSegmentsIds: [Int] = []
      converter.commitSegmentsHandler = { segs, candidateIds in
        if commitSegmentsUsed { return false }
        commitSegmentsUsed = true
        commitSegmentsIds = candidateIds
        let seg0 = segs.mutableConversionSegment(0)
        seg0.moveCandidate(1, 0)
        seg0.setSegmentType(.submitted)
        seg0.setKey("ここではきものを")
        seg0.mutableCandidate(0).convertedSegmentCount = 1
        segs.eraseSegments(segs.historySegmentsSize, 1)
        return true
      }
      setCommitSegmentValueMoveCandidate(converter)
      var finishCount = 0
      converter.finishConversionHandler = { _, _ in finishCount += 1 }

      command = Genmai_Commands_Command()
      session.convert(&command)
      try #require(command.output.hasPreedit)

      // Submit multi-segment candidate "ここで履物を" (id 1) via mobile tap.
      command = Genmai_Commands_Command()
      setSendCommandCommand(.submitCandidate, &command)
      command.input.command.id = 1
      session.sendCommand(&command)

      #expect(commitSegmentsIds == [1])

      // "ここで履物を" is committed, and only "脱ぐ" remains in preedit (NOT
      // "着物を脱ぐ").
      try #require(command.output.hasResult)
      #expect(command.output.result.value == "ここで履物を")
      try #require(command.output.hasPreedit)
      #expect(command.output.preedit.segment.count == 1)
      #expect(command.output.preedit.segment.first?.value == "脱ぐ")

      // Commit the remaining segment.
      command = Genmai_Commands_Command()
      session.commit(&command)
      try #require(command.output.hasResult)
      #expect(command.output.result.value == "脱ぐ")
      #expect(finishCount >= 1)
    }
  }
}
