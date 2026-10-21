// Port of mozc/src/session/session_test.cc (3.35.6354), part 2 (NumpadKey .. Issue5742293).

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import Testing

@testable import GenmaiSession

/// config.set_custom_keymap_table(...) helper.
private func customKeymapConfig(_ table: String) -> Genmai_Config_Config {
  var config = Genmai_Config_Config()
  config.sessionKeymap = .custom
  config.customKeymapTable = Data(table.utf8)
  return config
}

private func spaceKey() -> Genmai_Commands_KeyEvent {
  var key = Genmai_Commands_KeyEvent()
  key.specialKey = .space
  return key
}

@Suite struct SessionTests2 {
  @Test func numpadKey() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)
      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()

      var config = Genmai_Config_Config()
      config.numpadCharacterForm = .numpadDirectInput
      session.setConfig(config)

      // In the Precomposition state, numpad keys should not be consumed.
      #expect(testSendKey("Numpad1", session, &command))
      #expect(!command.output.consumed)
      #expect(sendKey("Numpad1", session, &command))
      #expect(!command.output.consumed)

      #expect(testSendKey("Add", session, &command))
      #expect(!command.output.consumed)
      #expect(sendKey("Add", session, &command))
      #expect(!command.output.consumed)

      #expect(testSendKey("Equals", session, &command))
      #expect(!command.output.consumed)
      #expect(sendKey("Equals", session, &command))
      #expect(!command.output.consumed)

      #expect(testSendKey("Separator", session, &command))
      #expect(!command.output.consumed)
      #expect(sendKey("Separator", session, &command))
      #expect(!command.output.consumed)

      #expect(getComposition(command).isEmpty)

      config.numpadCharacterForm = .numpadHalfWidth
      session.setConfig(config)

      // In the Precomposition state, numpad keys should not be consumed.
      #expect(testSendKey("Numpad1", session, &command))
      #expect(command.output.consumed)
      #expect(sendKey("Numpad1", session, &command))
      #expect(command.output.consumed)
      #expect(getComposition(command) == "1")

      #expect(testSendKey("Add", session, &command))
      #expect(command.output.consumed)
      #expect(sendKey("Add", session, &command))
      #expect(command.output.consumed)
      #expect(getComposition(command) == "1+")

      #expect(testSendKey("Equals", session, &command))
      #expect(command.output.consumed)
      #expect(sendKey("Equals", session, &command))
      #expect(command.output.consumed)
      #expect(getComposition(command) == "1+=")

      #expect(testSendKey("Separator", session, &command))
      #expect(command.output.consumed)
      #expect(sendKey("Separator", session, &command))
      #expect(command.output.consumed)

      #expect(getComposition(command).isEmpty)

      // "0" should be treated as full-width "０".
      #expect(testSendKey("0", session, &command))
      #expect(sendKey("0", session, &command))

      expectSingleSegmentAndKey("０", "０", command)

      // In the Composition state, DIVIDE on the pre-edit should be treated as "/".
      #expect(testSendKey("Divide", session, &command))
      #expect(sendKey("Divide", session, &command))

      expectSingleSegmentAndKey("０/", "０/", command)

      // In the Composition state, "Numpad0" should be treated as half-width "0".
      #expect(sendKey("Numpad0", session, &command))

      expectSingleSegmentAndKey("０/0", "０/0", command)

      // Separator should be treated as Enter.
      #expect(testSendKey("Separator", session, &command))
      #expect(sendKey("Separator", session, &command))

      #expect(!command.output.hasPreedit)
      expectResult("０/0", command)

      // http://b/2097087
      #expect(sendKey("0", session, &command))

      expectSingleSegmentAndKey("０", "０", command)

      #expect(sendKey("Divide", session, &command))
      expectSingleSegmentAndKey("０/", "０/", command)

      #expect(sendKey("Divide", session, &command))
      expectSingleSegmentAndKey("０//", "０//", command)

      #expect(sendKey("Subtract", session, &command))
      #expect(sendKey("Subtract", session, &command))
      #expect(sendKey("Decimal", session, &command))
      #expect(sendKey("Decimal", session, &command))
      expectSingleSegmentAndKey("０//--..", "０//--..", command)
    }
  }

  @Test func kanaSymbols() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      var config = Genmai_Config_Config()
      config.punctuationMethod = .commaPeriod
      config.symbolMethod = .cornerBracketSlash

      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      session.setConfig(config)
      f.initSessionToPrecomposition(session)

      do {
        var command = Genmai_Commands_Command()
        setSendKeyCommand("<", &command)
        command.input.key.keyString = "、"
        #expect(session.sendKey(&command))
        #expect(command.input.key.keyCode == UInt32(UInt8(ascii: ",")))
        #expect(command.input.key.keyString == "，")
        #expect(command.output.preedit.segment.first?.value == "，")
      }
      do {
        var command = Genmai_Commands_Command()
        session.editCancel(&command)
      }
      do {
        var command = Genmai_Commands_Command()
        setSendKeyCommand("?", &command)
        command.input.key.keyString = "・"
        #expect(session.sendKey(&command))
        #expect(command.input.key.keyCode == UInt32(UInt8(ascii: "/")))
        #expect(command.input.key.keyString == "／")
        #expect(command.output.preedit.segment.first?.value == "／")
      }
    }
  }

  @Test func insertCharacterWithShiftKey() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      do {  // Basic behavior
        let session = Session(engine)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()
        #expect(sendKey("a", session, &command))
        #expect(sendKey("A", session, &command))  // "あA"
        #expect(sendKey("a", session, &command))  // "あAa"
        // Shift reverts the input mode to Hiragana.
        #expect(sendKey("Shift", session, &command))
        #expect(sendKey("a", session, &command))  // "あAaあ"
        // Shift does nothing because the input mode has already been reverted.
        #expect(sendKey("Shift", session, &command))
        #expect(sendKey("a", session, &command))  // "あAaああ"
        #expect(getComposition(command) == "あAaああ")
      }

      do {  // Revert back to the previous input mode.
        let session = Session(engine)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()
        session.compositionModeFullKatakana(&command)
        #expect(command.output.mode == .fullKatakana)
        #expect(sendKey("a", session, &command))
        #expect(sendKey("A", session, &command))  // "アA"
        #expect(sendKey("a", session, &command))  // "アAa"
        // Shift reverts the input mode to Hiragana.
        #expect(sendKey("Shift", session, &command))
        #expect(sendKey("a", session, &command))  // "アAaア"
        // Shift does nothing because the input mode has already been reverted.
        #expect(sendKey("Shift", session, &command))
        #expect(sendKey("a", session, &command))  // "アAaアア"
        #expect(getComposition(command) == "アAaアア")
      }
    }
  }

  @Test func exitTemporaryAlphanumModeAfterCommittingSuggestion1() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2977131.
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()
      #expect(sendKey("N", session, &command))
      #expect(command.output.mode == .halfAscii)  // obsolete
      #expect(command.output.status.mode == .halfAscii)
      // Global mode should be kept as HIRAGANA
      #expect(command.output.status.comebackMode == .hiragana)

      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey("NFL")
      segment.addCandidate().value = "NFL"
      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      #expect(session.convert(&command))
      #expect(!command.output.hasCandidateWindow)
      #expect(!command.output.candidateWindow.hasFocusedIndex)
      #expect(command.output.candidateWindow.focusedIndex == 0)
      #expect(!command.output.hasResult)
      #expect(command.output.mode == .hiragana)  // obsolete
      #expect(command.output.status.mode == .hiragana)
      #expect(command.output.status.comebackMode == .hiragana)

      #expect(sendKey("a", session, &command))
      #expect(!command.output.hasCandidateWindow)
      expectResult("NFL", command)
      #expect(command.output.mode == .hiragana)  // obsolete
      #expect(command.output.status.mode == .hiragana)
      #expect(command.output.status.comebackMode == .hiragana)
    }
  }

  @Test func exitTemporaryAlphanumModeAfterCommittingSuggestion2() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2977131.
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()
      #expect(sendKey("N", session, &command))
      #expect(command.output.mode == .halfAscii)  // obsolete
      #expect(command.output.status.mode == .halfAscii)
      // Global mode should be kept as HIRAGANA
      #expect(command.output.status.comebackMode == .hiragana)

      do {
        let segments = Segments()
        let segment = segments.addSegment()
        segment.setKey("NFL")
        segment.addCandidate().value = "NFL"
        converter.setStartPredictionWithPreviousSuggestion(segments, true)
      }

      #expect(session.predictAndConvert(&command))
      try #require(command.output.hasCandidateWindow)
      #expect(command.output.candidateWindow.hasFocusedIndex)
      #expect(command.output.candidateWindow.focusedIndex == 0)
      #expect(!command.output.hasResult)
      #expect(command.output.mode == .hiragana)  // obsolete
      #expect(command.output.status.mode == .hiragana)
      #expect(command.output.status.comebackMode == .hiragana)

      #expect(sendKey("a", session, &command))
      #expect(!command.output.hasCandidateWindow)
      expectResult("NFL", command)

      #expect(command.output.mode == .hiragana)  // obsolete
      #expect(command.output.status.mode == .hiragana)
      #expect(command.output.status.comebackMode == .hiragana)
    }
  }

  @Test func exitTemporaryAlphanumModeAfterCommittingSugesstion3() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2977131.
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()
      #expect(sendKey("N", session, &command))
      #expect(command.output.mode == .halfAscii)  // obsolete
      #expect(command.output.status.mode == .halfAscii)
      // Global mode should be kept as HIRAGANA
      #expect(command.output.status.comebackMode == .hiragana)

      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey("NFL")
      segment.addCandidate().value = "NFL"
      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      #expect(session.convertToHalfASCII(&command))
      #expect(!command.output.hasCandidateWindow)
      #expect(!command.output.candidateWindow.hasFocusedIndex)
      #expect(command.output.candidateWindow.focusedIndex == 0)
      #expect(!command.output.hasResult)
      #expect(command.output.mode == .hiragana)  // obsolete
      #expect(command.output.status.mode == .hiragana)
      #expect(command.output.status.comebackMode == .hiragana)

      #expect(sendKey("a", session, &command))
      #expect(!command.output.hasCandidateWindow)
      expectResult("NFL", command)
      #expect(command.output.mode == .hiragana)  // obsolete
      #expect(command.output.status.mode == .hiragana)
      #expect(command.output.status.comebackMode == .hiragana)
    }
  }

  @Test func statusOutput() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      do {  // Basic behavior
        let session = Session(engine)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()
        #expect(sendKey("a", session, &command))  // "あ"
        try #require(command.output.hasStatus)
        #expect(command.output.status.activated)
        // command.output().mode() is going to be obsolete.
        #expect(command.output.mode == .hiragana)
        #expect(command.output.status.mode == .hiragana)
        #expect(command.output.status.comebackMode == .hiragana)

        #expect(sendKey("A", session, &command))  // "あA"
        try #require(command.output.hasStatus)
        #expect(command.output.status.activated)
        #expect(command.output.mode == .halfAscii)  // obsolete
        #expect(command.output.status.mode == .halfAscii)
        // Global mode should be kept as HIRAGANA
        #expect(command.output.status.comebackMode == .hiragana)

        #expect(sendKey("a", session, &command))  // "あAa"
        try #require(command.output.hasStatus)
        #expect(command.output.status.activated)
        #expect(command.output.mode == .halfAscii)  // obsolete
        #expect(command.output.status.mode == .halfAscii)
        // Global mode should be kept as HIRAGANA
        #expect(command.output.status.comebackMode == .hiragana)

        // Shift reverts the input mode to Hiragana.
        #expect(sendKey("Shift", session, &command))
        #expect(sendKey("a", session, &command))  // "あAaあ"
        try #require(command.output.hasStatus)
        #expect(command.output.status.activated)
        #expect(command.output.mode == .hiragana)  // obsolete
        #expect(command.output.status.mode == .hiragana)
        #expect(command.output.status.comebackMode == .hiragana)

        #expect(sendKey("A", session, &command))  // "あAaあA"
        try #require(command.output.hasStatus)
        #expect(command.output.status.activated)
        #expect(command.output.mode == .halfAscii)  // obsolete
        #expect(command.output.status.mode == .halfAscii)
        // Global mode should be kept as HIRAGANA
        #expect(command.output.status.comebackMode == .hiragana)

        // When the IME is deactivated, the temporary composition mode is reset.
        #expect(sendKey("OFF", session, &command))  // "あAaあA"
        try #require(command.output.hasStatus)
        #expect(!command.output.status.activated)
        // command.output().mode() always returns DIRECT when IME is
        // deactivated.  This is the reason why command.output().mode() is
        // going to be obsolete.
        #expect(command.output.mode == .direct)
        #expect(command.output.status.mode == .hiragana)
        #expect(command.output.status.comebackMode == .hiragana)
      }

      do {  // Katakana mode + Shift key
        let session = Session(engine)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()
        session.compositionModeFullKatakana(&command)
        #expect(command.output.mode == .fullKatakana)  // obsolete
        #expect(command.output.status.mode == .fullKatakana)
        #expect(command.output.status.comebackMode == .fullKatakana)

        #expect(sendKey("a", session, &command))
        try #require(command.output.hasStatus)
        #expect(command.output.status.activated)
        #expect(command.output.mode == .fullKatakana)  // obsolete
        #expect(command.output.status.mode == .fullKatakana)
        #expect(command.output.status.comebackMode == .fullKatakana)

        #expect(sendKey("A", session, &command))  // "アA"
        try #require(command.output.hasStatus)
        #expect(command.output.status.activated)
        #expect(command.output.mode == .halfAscii)  // obsolete
        #expect(command.output.status.mode == .halfAscii)
        // Global mode should be kept as FULL_KATAKANA
        #expect(command.output.status.comebackMode == .fullKatakana)

        // When the IME is deactivated, the temporary composition mode is reset.
        #expect(sendKey("OFF", session, &command))  // "アA"
        try #require(command.output.hasStatus)
        #expect(!command.output.status.activated)
        // command.output().mode() always returns DIRECT when IME is
        // deactivated.  This is the reason why command.output().mode() is
        // going to be obsolete.
        #expect(command.output.mode == .direct)
        #expect(command.output.status.mode == .fullKatakana)
        #expect(command.output.status.comebackMode == .fullKatakana)
      }
    }
  }

  @Test func suggest() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let segmentsM = Segments()
      do {
        let segment = segmentsM.addSegment()
        segment.setKey("M")
        segment.addCandidate().value = "MOCHA"
        segment.addCandidate().value = "MOZUKU"
      }

      let segmentsMo = Segments()
      do {
        let segment = segmentsMo.addSegment()
        segment.setKey("MO")
        segment.addCandidate().value = "MOCHA"
        segment.addCandidate().value = "MOZUKU"
      }

      let segmentsMoz = Segments()
      do {
        let segment = segmentsMoz.addSegment()
        segment.setKey("MOZ")
        segment.addCandidate().value = "MOZUKU"
      }

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()
      sendKey("M", session, &command)

      converter.setStartPrediction(segmentsMo, true)
      sendKey("O", session, &command)
      try #require(command.output.hasCandidateWindow)
      #expect(command.output.candidateWindow.candidate.count == 2)
      #expect(command.output.candidateWindow.candidate[0].value == "MOCHA")

      // moz|
      converter.setStartPrediction(segmentsMoz, true)
      sendKey("Z", session, &command)
      try #require(command.output.hasCandidateWindow)
      #expect(command.output.candidateWindow.candidate.count == 1)
      #expect(command.output.candidateWindow.candidate[0].value == "MOZUKU")

      // mo|
      converter.setStartPrediction(segmentsMo, true)
      sendKey("Backspace", session, &command)
      try #require(command.output.hasCandidateWindow)
      #expect(command.output.candidateWindow.candidate.count == 2)
      #expect(command.output.candidateWindow.candidate[0].value == "MOCHA")

      // m|o
      converter.setStartPrediction(segmentsMo, true)
      command = Genmai_Commands_Command()
      #expect(session.moveCursorLeft(&command))
      try #require(command.output.hasCandidateWindow)
      #expect(command.output.candidateWindow.candidate.count == 2)
      #expect(command.output.candidateWindow.candidate[0].value == "MOCHA")

      // mo|
      converter.setStartPrediction(segmentsMo, true)
      command = Genmai_Commands_Command()
      #expect(session.moveCursorToEnd(&command))
      try #require(command.output.hasCandidateWindow)
      #expect(command.output.candidateWindow.candidate.count == 2)
      #expect(command.output.candidateWindow.candidate[0].value == "MOCHA")

      // |mo
      converter.setStartPrediction(segmentsMo, true)
      command = Genmai_Commands_Command()
      #expect(session.moveCursorToBeginning(&command))
      try #require(command.output.hasCandidateWindow)
      #expect(command.output.candidateWindow.candidate.count == 2)
      #expect(command.output.candidateWindow.candidate[0].value == "MOCHA")

      // m|o
      converter.setStartPrediction(segmentsMo, true)
      command = Genmai_Commands_Command()
      #expect(session.moveCursorRight(&command))
      try #require(command.output.hasCandidateWindow)
      #expect(command.output.candidateWindow.candidate.count == 2)
      #expect(command.output.candidateWindow.candidate[0].value == "MOCHA")

      // m|
      converter.setStartPrediction(segmentsM, true)
      command = Genmai_Commands_Command()
      #expect(session.delete(&command))
      try #require(command.output.hasCandidateWindow)
      #expect(command.output.candidateWindow.candidate.count == 2)
      #expect(command.output.candidateWindow.candidate[0].value == "MOCHA")

      let segmentsMConv = Segments()
      do {
        let segment = segmentsMConv.addSegment()
        segment.setKey("M")
        segment.addCandidate().value = "M"
        segment.addCandidate().value = "m"
      }
      let requestMConv = f.createConversionRequest(session)
      f.fillT13Ns(requestMConv, segmentsMConv)
      converter.setStartConversion(segmentsMConv, true)
      command = Genmai_Commands_Command()
      #expect(session.convert(&command))

      converter.setStartPrediction(segmentsM, true)
      command = Genmai_Commands_Command()
      #expect(session.convertCancel(&command))
      try #require(command.output.hasCandidateWindow)
      #expect(command.output.candidateWindow.candidate.count == 2)
      #expect(command.output.candidateWindow.candidate[0].value == "MOCHA")
    }
  }

  @Test func commitCandidateTypingCorrection() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      var request = f.mobileRequest
      request.specialRomanjiTable = .qwertyMobileToHiragana

      let segmentsJueri = Segments()
      let segment = segmentsJueri.addSegment()
      let kJueri = "じゅえり"
      segment.setKey(kJueri)
      let candidate = segment.addCandidate()
      candidate.key = "くえり"
      candidate.contentKey = candidate.key
      candidate.value = "クエリ"
      candidate.attributes = Attribute.partiallyKeyConsumed
      candidate.consumedKeySize = UInt32(Util.charsLen(kJueri))

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session, request)

      var command = Genmai_Commands_Command()
      converter.setStartPrediction(segmentsJueri, true)
      f.insertCharacterChars("jueri", session, &command)

      try #require(command.output.hasCandidateWindow)
      #expect(command.output.preedit.segment.count == 1)
      #expect(command.output.preedit.segment.first?.key == kJueri)
      #expect(command.output.candidateWindow.candidate.count == 1)
      #expect(command.output.candidateWindow.candidate.first?.value == "クエリ")

      // commit partial prediction
      converter.setCommitSegmentValue(segmentsJueri, true)
      let emptySegments = Segments()
      converter.finishConversionHandler = { _, out in out.assign(from: emptySegments) }
      setSendCommandCommand(.submitCandidate, &command)
      command.input.command.id = 0
      converter.setStartPrediction(segmentsJueri, true)
      session.sendCommand(&command)
      #expect(command.output.consumed)
      expectResultAndKey("クエリ", "くえり", command)
      #expect(!command.output.hasPreedit)
    }
  }

  @Test func mobilePartialPrediction() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      var request = f.mobileRequest
      request.specialRomanjiTable = .qwertyMobileToHiragana

      let segmentsWata = Segments()
      do {
        let segment = segmentsWata.addSegment()
        let kWata = "わた"
        segment.setKey(kWata)
        let cand1 = addCandidate(kWata, "綿", segment)
        cand1.attributes = Attribute.partiallyKeyConsumed
        cand1.consumedKeySize = UInt32(Util.charsLen(kWata))
        let cand2 = addCandidate(kWata, kWata, segment)
        cand2.attributes = Attribute.partiallyKeyConsumed
        cand2.consumedKeySize = UInt32(Util.charsLen(kWata))
      }

      let segmentsWatashino = Segments()
      do {
        let segment = segmentsWatashino.addSegment()
        let kWatashino = "わたしの"
        segment.setKey(kWatashino)
        let cand1 = segment.addCandidate()
        cand1.value = "私の"
        cand1.attributes = Attribute.partiallyKeyConsumed
        cand1.consumedKeySize = UInt32(Util.charsLen(kWatashino))
        let cand2 = segment.addCandidate()
        cand2.value = kWatashino
        cand2.attributes = Attribute.partiallyKeyConsumed
        cand2.consumedKeySize = UInt32(Util.charsLen(kWatashino))
      }

      let segmentsShino = Segments()
      do {
        let segment = segmentsShino.addSegment()
        let kShino = "しの"
        segment.setKey(kShino)
        var candidate = addCandidate("しのみや", "四ノ宮", segment)
        candidate.contentKey = segment.key
        candidate.attributes = Attribute.partiallyKeyConsumed
        candidate.consumedKeySize = UInt32(Util.charsLen(kShino))
        candidate = addCandidate(kShino, "shino", segment)
      }

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session, request)

      var command = Genmai_Commands_Command()
      converter.setStartPrediction(segmentsWatashino, true)
      f.insertCharacterChars("watashino", session, &command)
      try #require(command.output.hasCandidateWindow)
      #expect(command.output.candidateWindow.candidate.count == 2)
      #expect(command.output.candidateWindow.candidate[0].value == "私の")

      // partial suggestion for "わた|しの"
      converter.setStartPrediction(segmentsWata, true)
      command = Genmai_Commands_Command()
      #expect(session.moveCursorLeft(&command))
      command = Genmai_Commands_Command()
      #expect(session.moveCursorLeft(&command))
      // partial suggestion candidates
      try #require(command.output.hasCandidateWindow)
      #expect(command.output.candidateWindow.candidate.count == 2)
      #expect(command.output.candidateWindow.candidate[0].value == "綿")

      // commit partial prediction
      converter.setCommitPartialSuggestionSegmentValue(segmentsWata, true)
      setSendCommandCommand(.submitCandidate, &command)
      command.input.command.id = 0
      converter.setStartPrediction(segmentsShino, true)
      session.sendCommand(&command)
      #expect(command.output.consumed)
      expectResultAndKey("綿", "わた", command)

      // remaining text in preedit
      #expect(command.output.preedit.cursor == 2)
      expectSingleSegment("しの", command)

      // Suggestion for new text fills the candidates.
      #expect(command.output.hasCandidateWindow)
      #expect(command.output.candidateWindow.candidate.first?.value == "四ノ宮")
    }
  }

  @Test func toggleAlphanumericMode() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()

      do {
        f.insertCharacterChars("a", session, &command)
        #expect(getComposition(command) == "あ")
        #expect(command.output.hasMode)
        #expect(command.output.mode == .hiragana)

        command = Genmai_Commands_Command()
        session.toggleAlphanumericMode(&command)
        #expect(command.output.mode == .halfAscii)
        f.insertCharacterChars("a", session, &command)
        #expect(getComposition(command) == "あa")
        #expect(command.output.hasMode)
        #expect(command.output.mode == .halfAscii)

        command = Genmai_Commands_Command()
        session.toggleAlphanumericMode(&command)
        f.insertCharacterChars("a", session, &command)
        #expect(getComposition(command) == "あaあ")
        #expect(command.output.hasMode)
        #expect(command.output.mode == .hiragana)
      }

      do {
        // ToggleAlphanumericMode on Precomposition mode should work.
        command = Genmai_Commands_Command()
        session.editCancel(&command)
        #expect(!command.output.hasPreedit)
        #expect(command.output.hasMode)
        #expect(command.output.mode == .hiragana)

        session.toggleAlphanumericMode(&command)
        #expect(command.output.mode == .halfAscii)
        f.insertCharacterChars("a", session, &command)
        #expect(getComposition(command) == "a")
        #expect(command.output.hasMode)
        #expect(command.output.mode == .halfAscii)
      }

      do {
        // A single "n" on Hiragana mode should not converted to "ん" for
        // the compatibility with MS-IME.
        command = Genmai_Commands_Command()
        session.editCancel(&command)
        #expect(!command.output.hasPreedit)
        #expect(command.output.hasMode)
        #expect(command.output.mode == .halfAscii)

        session.toggleAlphanumericMode(&command)
        #expect(command.output.mode == .hiragana)
        f.insertCharacterChars("n", session, &command)  // on Hiragana mode
        #expect(getComposition(command) == "ｎ")

        command = Genmai_Commands_Command()
        session.toggleAlphanumericMode(&command)
        #expect(command.output.mode == .halfAscii)
        f.insertCharacterChars("a", session, &command)  // on Half ascii mode.
        #expect(getComposition(command) == "ｎa")
      }

      do {
        // ToggleAlphanumericMode should work even when it is called in
        // the conversion state.
        command = Genmai_Commands_Command()
        session.editCancel(&command)
        #expect(!command.output.hasPreedit)
        #expect(command.output.hasMode)
        #expect(command.output.mode == .halfAscii)

        session.compositionModeHiragana(&command)
        f.insertCharacterChars("a", session, &command)  // on Hiragana mode
        #expect(getComposition(command) == "あ")

        let segments = Segments()
        f.setAiueo(segments)
        let request = f.createConversionRequest(session)
        f.fillT13Ns(request, segments)
        converter.setStartConversion(segments, true)

        command = Genmai_Commands_Command()
        session.convert(&command)

        #expect(getComposition(command) == "あいうえお")

        command = Genmai_Commands_Command()
        session.toggleAlphanumericMode(&command)
        #expect(command.output.mode == .halfAscii)

        command = Genmai_Commands_Command()
        session.commit(&command)

        f.insertCharacterChars("a", session, &command)  // on Half ascii mode.
        #expect(getComposition(command) == "a")
      }
    }
  }

  @Test func insertSpace() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()

      // Default should be FULL_WIDTH.
      command.input.key = spaceKey()
      #expect(session.insertSpace(&command))
      #expect(command.output.consumed)
      #expect(!command.output.hasPreedit)
      expectResult("　", command)  // Full-width space

      // Change the setting to HALF_WIDTH.
      var config = Genmai_Config_Config()
      config.spaceCharacterForm = .fundamentalHalfWidth
      session.setConfig(config)
      command = Genmai_Commands_Command()
      command.input.key = spaceKey()
      #expect(session.insertSpace(&command))
      #expect(!command.output.consumed)
      #expect(!command.output.hasPreedit)
      #expect(!command.output.hasResult)

      // Change the setting to FULL_WIDTH.
      config.spaceCharacterForm = .fundamentalFullWidth
      session.setConfig(config)
      command = Genmai_Commands_Command()
      command.input.key = spaceKey()
      #expect(session.insertSpace(&command))
      #expect(command.output.consumed)
      #expect(!command.output.hasPreedit)
      expectResult("　", command)  // Full-width space
    }
  }

  @Test func insertSpaceToggled() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()

      // Default should be FULL_WIDTH.  So the toggled space should be
      // half-width.
      command.input.key = spaceKey()
      #expect(session.insertSpaceToggled(&command))
      #expect(!command.output.consumed)
      #expect(!command.output.hasPreedit)
      #expect(!command.output.hasResult)

      // Change the setting to HALF_WIDTH.
      var config = Genmai_Config_Config()
      config.spaceCharacterForm = .fundamentalHalfWidth
      session.setConfig(config)
      command = Genmai_Commands_Command()
      command.input.key = spaceKey()
      #expect(session.insertSpaceToggled(&command))
      #expect(command.output.consumed)
      #expect(!command.output.hasPreedit)
      expectResult("　", command)  // Full-width space

      // Change the setting to FULL_WIDTH.
      config.spaceCharacterForm = .fundamentalFullWidth
      session.setConfig(config)
      command = Genmai_Commands_Command()
      command.input.key = spaceKey()
      #expect(session.insertSpaceToggled(&command))
      #expect(!command.output.consumed)
      #expect(!command.output.hasPreedit)
      #expect(!command.output.hasResult)
    }
  }

  @Test func insertSpaceHalfWidth() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()

      command.input.key = spaceKey()
      #expect(session.insertSpaceHalfWidth(&command))
      #expect(!command.output.consumed)
      #expect(!command.output.hasPreedit)
      #expect(!command.output.hasResult)

      #expect(sendKey("a", session, &command))
      #expect(getComposition(command) == "あ")

      command = Genmai_Commands_Command()
      #expect(session.insertSpaceHalfWidth(&command))
      #expect(getComposition(command) == "あ ")

      do {  // Convert "あ " with dummy conversions.
        let segments = Segments()
        segments.addSegment().addCandidate().value = "亜 "
        let request = f.createConversionRequest(session)
        f.fillT13Ns(request, segments)
        converter.setStartConversion(segments, true)

        command = Genmai_Commands_Command()
        #expect(session.convert(&command))
      }

      command = Genmai_Commands_Command()
      #expect(session.insertSpaceHalfWidth(&command))
      #expect(command.output.result.value == "亜  ")
      #expect(getComposition(command) == "")
    }
  }

  @Test func insertSpaceFullWidth() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()

      command.input.key = spaceKey()
      #expect(session.insertSpaceFullWidth(&command))
      #expect(command.output.consumed)
      #expect(!command.output.hasPreedit)
      expectResult("　", command)  // Full-width space

      #expect(sendKey("a", session, &command))
      #expect(getComposition(command) == "あ")

      command = Genmai_Commands_Command()
      command.input.key = spaceKey()
      #expect(session.insertSpaceFullWidth(&command))
      #expect(getComposition(command) == "あ　")  // full-width space

      do {  // Convert "あ　" (full-width space) with dummy conversions.
        let segments = Segments()
        segments.addSegment().addCandidate().value = "亜　"
        let request = f.createConversionRequest(session)
        f.fillT13Ns(request, segments)
        converter.setStartConversion(segments, true)

        command = Genmai_Commands_Command()
        #expect(session.convert(&command))
      }

      command = Genmai_Commands_Command()
      command.input.key = spaceKey()
      #expect(session.insertSpaceFullWidth(&command))
      #expect(command.output.result.value == "亜　　")
      #expect(getComposition(command) == "")
    }
  }

  @Test func insertSpaceWithCompositionMode() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      func makeSession(_ config: Genmai_Config_Config) -> Session {
        let session = Session(engine)
        let keyMapManager = KeyMapManager(config)
        session.setConfig(config)
        session.setKeyMapManager(keyMapManager)
        f.initSessionToPrecomposition(session)
        return session
      }

      // First, test against http://b/6027559
      var config = customKeymapConfig(
        "status\tkey\tcommand\n" + "Precomposition\tSpace\tInsertSpace\n"
          + "Composition\tSpace\tInsertSpace\n")
      do {
        let session = makeSession(config)
        var command = Genmai_Commands_Command()
        #expect(testSendKeyWithMode("Space", .halfKatakana, session, &command))
        #expect(!command.output.consumed)
        #expect(sendKeyWithMode("Space", .halfKatakana, session, &command))
        // In this case, space key event should not be consumed.
        #expect(!command.output.consumed)
        #expect(session.context.state == .precomposition)
      }
      do {
        let session = makeSession(config)
        var command = Genmai_Commands_Command()
        #expect(testSendKey("a", session, &command))
        #expect(command.output.consumed)
        #expect(sendKey("a", session, &command))
        #expect(command.output.consumed)
        expectPreedit("あ", command)
        #expect(session.context.state == .composition)

        #expect(testSendKeyWithMode("Space", .halfKatakana, session, &command))
        #expect(command.output.consumed)
        #expect(sendKeyWithMode("Space", .halfKatakana, session, &command))
        #expect(command.output.consumed)
        expectPreedit("あ ", command)
        #expect(session.context.state == .composition)
      }

      config.customKeymapTable = Data(
        ("status\tkey\tcommand\n" + "Precomposition\tSpace\tInsertAlternateSpace\n"
          + "Composition\tSpace\tInsertAlternateSpace\n").utf8)
      do {
        let session = makeSession(config)
        var command = Genmai_Commands_Command()
        #expect(testSendKeyWithMode("Space", .halfKatakana, session, &command))
        #expect(command.output.consumed)
        #expect(sendKeyWithMode("Space", .halfKatakana, session, &command))
        #expect(command.output.consumed)
        expectResult("　", command)
        #expect(session.context.state == .precomposition)
        #expect(command.output.mode == .halfKatakana)
      }
      do {
        let session = makeSession(config)
        var command = Genmai_Commands_Command()
        #expect(testSendKey("a", session, &command))
        #expect(command.output.consumed)
        #expect(sendKey("a", session, &command))
        #expect(command.output.consumed)
        expectPreedit("あ", command)
        #expect(session.context.state == .composition)

        #expect(testSendKeyWithMode("Space", .halfKatakana, session, &command))
        #expect(command.output.consumed)
        #expect(sendKeyWithMode("Space", .halfKatakana, session, &command))
        #expect(command.output.consumed)
        expectPreedit("あ　", command)  // Full-width space
        #expect(session.context.state == .composition)
      }

      // Second, the 1st case filed in http://b/2936141
      config.customKeymapTable = Data(
        ("status\tkey\tcommand\n" + "Precomposition\tSpace\tInsertSpace\n"
          + "Composition\tSpace\tInsertSpace\n").utf8)
      config.spaceCharacterForm = .fundamentalFullWidth
      do {
        let session = makeSession(config)
        var command = Genmai_Commands_Command()
        #expect(testSendKeyWithMode("Space", .halfAscii, session, &command))
        #expect(command.output.consumed)
        command = Genmai_Commands_Command()
        #expect(sendKeyWithMode("Space", .halfAscii, session, &command))
        #expect(command.output.consumed)
        expectResult("　", command)
        #expect(session.context.state == .precomposition)
        #expect(command.output.mode == .halfAscii)
      }
      do {
        let session = makeSession(config)
        var command = Genmai_Commands_Command()
        #expect(testSendKeyWithMode("a", .halfAscii, session, &command))
        #expect(command.output.consumed)
        #expect(sendKeyWithMode("a", .halfAscii, session, &command))
        #expect(command.output.consumed)
        expectPreedit("a", command)
        #expect(command.output.mode == .halfAscii)

        #expect(testSendKeyWithMode("Space", .halfAscii, session, &command))
        #expect(command.output.consumed)
        #expect(sendKeyWithMode("Space", .halfAscii, session, &command))
        #expect(command.output.consumed)
        expectPreedit("a　", command)  // Full-width space
        #expect(command.output.mode == .halfAscii)
      }

      // Finally, the 2nd case filed in http://b/2936141
      config.customKeymapTable = Data(
        ("status\tkey\tcommand\n" + "Precomposition\tSpace\tInsertSpace\n"
          + "Composition\tSpace\tInsertSpace\n").utf8)
      config.spaceCharacterForm = .fundamentalHalfWidth
      do {
        let session = makeSession(config)
        var command = Genmai_Commands_Command()
        #expect(testSendKeyWithMode("Space", .fullAscii, session, &command))
        #expect(!command.output.consumed)
        #expect(sendKeyWithMode("Space", .fullAscii, session, &command))
        #expect(!command.output.consumed)
      }
      do {
        let session = makeSession(config)
        var command = Genmai_Commands_Command()
        #expect(testSendKeyWithMode("a", .fullAscii, session, &command))
        #expect(command.output.consumed)
        #expect(sendKeyWithMode("a", .fullAscii, session, &command))
        #expect(command.output.consumed)
        expectPreedit("ａ", command)
        #expect(command.output.mode == .fullAscii)

        #expect(testSendKeyWithMode("Space", .fullAscii, session, &command))
        #expect(command.output.consumed)
        #expect(sendKeyWithMode("Space", .fullAscii, session, &command))
        #expect(command.output.consumed)
        expectPreedit("ａ ", command)
        #expect(command.output.mode == .fullAscii)
      }
    }
  }

  /// Shared body of the four *WithCustomKeyBinding tests that start in
  /// precomposition and check Space / Shift Space.
  private func checkSpaceCustomKeyBinding(
    _ f: SessionTestFixture, _ session: Session, _ converter: MockConverter,
    plainConsumed: Bool, expectedResult: String
  ) {
    var command = Genmai_Commands_Command()
    if !plainConsumed {
      // A plain space key event should be echoed back.
      f.setUndoContext(session, converter)
      #expect(testSendKey("Space", session, &command))
      #expect(!command.output.consumed)  // should not be consumed.
      #expect(tryUndoAndAssertDoNothing(session) == nil)

      f.setUndoContext(session, converter)
      #expect(sendKey("Space", session, &command))
      #expect(!command.output.consumed)  // should not be consumed.
      #expect(tryUndoAndAssertDoNothing(session) == nil)
    }

    // A space key event with any modifier key should be consumed.
    f.setUndoContext(session, converter)
    #expect(testSendKey("Shift Space", session, &command))
    #expect(command.output.consumed)
    // It is OK not to check |TryUndoAndAssertDoNothing| here because this
    // (test) send key event is actually *consumed*.

    #expect(sendKey("Shift Space", session, &command))
    #expect(command.output.consumed)
    #expect(!command.output.hasPreedit)
    expectResult(expectedResult, command)
    #expect(tryUndoAndAssertDoNothing(session) == nil)
  }

  @Test func insertSpaceWithCustomKeyBinding() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/5872031
      var config = customKeymapConfig(
        "status\tkey\tcommand\n" + "Precomposition\tSpace\tInsertSpace\n"
          + "Precomposition\tShift Space\tInsertSpace\n")
      config.spaceCharacterForm = .fundamentalHalfWidth

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      let keyMapManager = KeyMapManager(config)
      session.setConfig(config)
      session.setKeyMapManager(keyMapManager)
      f.initSessionToPrecomposition(session)

      checkSpaceCustomKeyBinding(f, session, converter, plainConsumed: false, expectedResult: " ")
    }
  }

  @Test func insertAlternateSpaceWithCustomKeyBinding() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/5872031
      var config = customKeymapConfig(
        "status\tkey\tcommand\n" + "Precomposition\tSpace\tInsertAlternateSpace\n"
          + "Precomposition\tShift Space\tInsertAlternateSpace\n")
      config.spaceCharacterForm = .fundamentalFullWidth

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      let keyMapManager = KeyMapManager(config)
      session.setConfig(config)
      session.setKeyMapManager(keyMapManager)
      f.initSessionToPrecomposition(session)

      checkSpaceCustomKeyBinding(f, session, converter, plainConsumed: false, expectedResult: " ")
    }
  }

  @Test func insertSpaceHalfWidthWithCustomKeyBinding() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/5872031
      let config = customKeymapConfig(
        "status\tkey\tcommand\n" + "Precomposition\tSpace\tInsertHalfSpace\n"
          + "Precomposition\tShift Space\tInsertHalfSpace\n")

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      let keyMapManager = KeyMapManager(config)
      session.setConfig(config)

      session.setKeyMapManager(keyMapManager)
      f.initSessionToPrecomposition(session)

      checkSpaceCustomKeyBinding(f, session, converter, plainConsumed: false, expectedResult: " ")
    }
  }

  @Test func insertSpaceFullWidthWithCustomKeyBinding() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/5872031
      let config = customKeymapConfig(
        "status\tkey\tcommand\n" + "Precomposition\tSpace\tInsertFullSpace\n"
          + "Precomposition\tShift Space\tInsertFullSpace\n")

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      let keyMapManager = KeyMapManager(config)
      session.setConfig(config)
      session.setKeyMapManager(keyMapManager)
      f.initSessionToDirect(session)

      var command = Genmai_Commands_Command()

      // A plain space key event assigned to InsertFullSpace should be consumed.
      f.setUndoContext(session, converter)
      #expect(testSendKey("Space", session, &command))
      #expect(command.output.consumed)
      // It is OK not to check |TryUndoAndAssertDoNothing| here because this
      // (test) send key event is actually *consumed*.

      #expect(sendKey("Space", session, &command))
      #expect(command.output.consumed)
      #expect(!command.output.hasPreedit)
      expectResult("　", command)  // Full-width space
      #expect(tryUndoAndAssertDoNothing(session) == nil)

      // A space key event with any modifier key assigned to InsertFullSpace should
      // be consumed.
      f.setUndoContext(session, converter)
      #expect(testSendKey("Shift Space", session, &command))
      #expect(command.output.consumed)

      #expect(sendKey("Shift Space", session, &command))
      #expect(command.output.consumed)
      #expect(!command.output.hasPreedit)
      expectResult("　", command)  // Full-width space
      #expect(tryUndoAndAssertDoNothing(session) == nil)
    }
  }

  @Test func insertSpaceInDirectMode() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let config = customKeymapConfig(
        "status\tkey\tcommand\n" + "Direct\tCtrl a\tInsertSpace\n"
          + "Direct\tCtrl b\tInsertAlternateSpace\n" + "Direct\tCtrl c\tInsertHalfSpace\n"
          + "Direct\tCtrl d\tInsertFullSpace\n")

      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      let keyMapManager = KeyMapManager(config)
      session.setConfig(config)
      session.setKeyMapManager(keyMapManager)
      f.initSessionToDirect(session)

      var command = Genmai_Commands_Command()

      // [Insert*Space] should be echoes back in the direct mode.
      for key in ["Ctrl a", "Ctrl b", "Ctrl c", "Ctrl d"] {
        #expect(testSendKey(key, session, &command))
        #expect(!command.output.consumed)
        #expect(!command.output.hasPreedit)
        #expect(!command.output.hasResult)
        #expect(sendKey(key, session, &command))
        #expect(!command.output.consumed)
        #expect(!command.output.hasPreedit)
        #expect(!command.output.hasResult)
      }
    }
  }

  @Test func insertSpaceInCompositionMode() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/5872031
      var config = customKeymapConfig(
        "status\tkey\tcommand\n" + "Composition\tCtrl a\tInsertSpace\n"
          + "Composition\tCtrl b\tInsertAlternateSpace\n"
          + "Composition\tCtrl c\tInsertHalfSpace\n" + "Composition\tCtrl d\tInsertFullSpace\n")
      config.spaceCharacterForm = .fundamentalFullWidth

      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      let keyMapManager = KeyMapManager(config)
      session.setConfig(config)
      session.setKeyMapManager(keyMapManager)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()

      sendKey("a", session, &command)
      #expect(getComposition(command) == "あ")
      #expect(session.context.state == .composition)

      #expect(testSendKey("Ctrl a", session, &command))
      #expect(command.output.consumed)

      sendKey("Ctrl a", session, &command)
      #expect(getComposition(command) == "あ　")

      #expect(testSendKey("Ctrl b", session, &command))
      #expect(command.output.consumed)

      sendKey("Ctrl b", session, &command)
      #expect(getComposition(command) == "あ　 ")

      #expect(testSendKey("Ctrl c", session, &command))
      #expect(command.output.consumed)

      sendKey("Ctrl c", session, &command)
      #expect(getComposition(command) == "あ　  ")

      #expect(testSendKey("Ctrl d", session, &command))
      #expect(command.output.consumed)

      sendKey("Ctrl d", session, &command)
      #expect(getComposition(command) == "あ　  　")
    }
  }

  @Test func insertSpaceInConversionMode() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/5872031
      var config = customKeymapConfig(
        "status\tkey\tcommand\n" + "Conversion\tCtrl a\tInsertSpace\n"
          + "Conversion\tCtrl b\tInsertAlternateSpace\n"
          + "Conversion\tCtrl c\tInsertHalfSpace\n" + "Conversion\tCtrl d\tInsertFullSpace\n")
      config.spaceCharacterForm = .fundamentalFullWidth

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      let keyMapManager = KeyMapManager(config)
      session.setConfig(config)
      session.setKeyMapManager(keyMapManager)

      for (key, expected) in [
        ("Ctrl a", "あいうえお　"), ("Ctrl b", "あいうえお "), ("Ctrl c", "あいうえお "),
        ("Ctrl d", "あいうえお　"),
      ] {
        f.initSessionToConversionWithAiueo(session, converter)
        var command = Genmai_Commands_Command()

        #expect(testSendKey(key, session, &command))
        #expect(command.output.consumed)

        #expect(sendKey(key, session, &command))
        #expect(getComposition(command).isEmpty)
        try #require(command.output.hasResult)
        #expect(command.output.result.value == expected)
        #expect(tryUndoAndAssertDoNothing(session) == nil)
        converter.clear()
      }
    }
  }

  @Test func insertSpaceFullWidthOnHalfKanaInput() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()

      #expect(session.compositionModeHalfKatakana(&command))
      #expect(command.output.mode == .halfKatakana)
      f.insertCharacterChars("a", session, &command)
      #expect(getComposition(command) == "ｱ")

      command = Genmai_Commands_Command()
      command.input.key = spaceKey()
      #expect(session.insertSpaceFullWidth(&command))
      #expect(getComposition(command) == "ｱ　")  // "ｱ　" (full-width space)
    }
  }

  @Test func isFullWidthInsertSpace() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      var config = Genmai_Config_Config()
      var command = Genmai_Commands_Command()
      let emptyInput = Genmai_Commands_Input()

      // When |empty_command| does not have |empty_command.key().input()| field,
      // the current input mode will be used.

      /// Runs Hiragana, FullKatakana, HalfKatakana, FullASCII, HalfASCII, Direct
      /// and checks IsFullWidthInsertSpace(input) against `expected`.
      func check(
        _ form: Genmai_Config_Config.FundamentalCharacterForm, _ input: Genmai_Commands_Input,
        _ expected: [Bool], _ katakanaInput: Bool = false
      ) {
        config.spaceCharacterForm = form
        let session = Session(engine)
        let peer = SessionTestPeer(session)
        session.setConfig(config)
        f.initSessionToPrecomposition(session)

        command = Genmai_Commands_Command()
        session.compositionModeHiragana(&command)
        #expect(peer.isFullWidthInsertSpace(input) == expected[0])
        command = Genmai_Commands_Command()
        session.compositionModeFullKatakana(&command)
        #expect(peer.isFullWidthInsertSpace(katakanaInput ? command.input : input) == expected[1])
        command = Genmai_Commands_Command()
        session.compositionModeHalfKatakana(&command)
        #expect(peer.isFullWidthInsertSpace(input) == expected[2])
        command = Genmai_Commands_Command()
        session.compositionModeFullASCII(&command)
        #expect(peer.isFullWidthInsertSpace(input) == expected[3])
        command = Genmai_Commands_Command()
        session.compositionModeHalfASCII(&command)
        #expect(peer.isFullWidthInsertSpace(input) == expected[4])
        command = Genmai_Commands_Command()
        session.imeOff(&command)
        #expect(peer.isFullWidthInsertSpace(input) == expected[5])
      }

      // Default config -- follow to the current mode.
      check(.fundamentalInputMode, emptyInput, [true, true, false, true, false, false])
      // Set config to 'half' -- all mode has to emit half-width space.
      check(.fundamentalHalfWidth, emptyInput, [false, false, false, false, false, false])
      // Set config to 'FULL' -- all mode except for DIRECT emits
      // full-width space.
      check(.fundamentalFullWidth, emptyInput, [true, true, true, true, true, false], true)

      // When |input| has |input.key().mode()| field,
      // the specified input mode by |input| will be used.
      do {
        // Default config -- follow to the current mode.
        config.spaceCharacterForm = .fundamentalInputMode
        let session = Session(engine)
        let peer = SessionTestPeer(session)
        session.setConfig(config)
        f.initSessionToPrecomposition(session)

        // Use HALF_KATAKANA for the new input mode
        var input = Genmai_Commands_Input()
        input.key.mode = .halfKatakana

        func run(_ expected: [Bool]) {
          var command = Genmai_Commands_Command()
          session.compositionModeHiragana(&command)
          #expect(peer.isFullWidthInsertSpace(input) == expected[0])
          command = Genmai_Commands_Command()
          session.compositionModeFullKatakana(&command)
          #expect(peer.isFullWidthInsertSpace(input) == expected[1])
          command = Genmai_Commands_Command()
          session.compositionModeHalfKatakana(&command)
          #expect(peer.isFullWidthInsertSpace(input) == expected[2])
          command = Genmai_Commands_Command()
          session.compositionModeFullASCII(&command)
          #expect(peer.isFullWidthInsertSpace(input) == expected[3])
          command = Genmai_Commands_Command()
          session.compositionModeHalfASCII(&command)
          #expect(peer.isFullWidthInsertSpace(input) == expected[4])
          command = Genmai_Commands_Command()
          session.imeOff(&command)
          #expect(peer.isFullWidthInsertSpace(input) == expected[5])
        }
        run([false, false, false, false, false, false])

        // Use FULL_ASCII for the new input mode
        input.key.mode = .fullAscii
        run([true, true, true, true, true, false])
      }
    }
  }

  @Test func issue1951385() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/1951385
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()

      let exceededPreedit = String(repeating: "a", count: 500)
      try #require(exceededPreedit.utf8.count == 500)
      f.insertCharacterChars(exceededPreedit, session, &command)

      let segments = Segments()
      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, false)

      command = Genmai_Commands_Command()
      session.convertToFullASCII(&command)
      #expect(!command.output.hasCandidateWindow)

      // The status should remain the preedit status, although the
      // previous command was convert.  The next command makes sure that
      // the preedit will disappear by canceling the preedit status.
      command = Genmai_Commands_Command()
      command.input.key.specialKey = .escape
      #expect(!command.output.hasPreedit)
    }
  }

  @Test func issue1978201() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      // This is a unittest against http://b/1978201
      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey("いんぼう")
      segment.addCandidate().value = "陰謀"
      segment.addCandidate().value = "陰謀論"
      segment.addCandidate().value = "陰謀説"

      var command = Genmai_Commands_Command()
      #expect(session.segmentWidthShrink(&command))

      command = Genmai_Commands_Command()
      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)
      #expect(session.convert(&command))

      command = Genmai_Commands_Command()
      #expect(session.commitSegment(&command))
      expectResult("陰謀", command)
      #expect(!command.output.hasPreedit)
    }
  }

  @Test func issue1975771() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      // This is a unittest against http://b/1975771
      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      // Trigger suggest by pressing "a".
      let segments = Segments()
      f.setAiueo(segments)
      converter.setStartPrediction(segments, true)

      var command = Genmai_Commands_Command()
      command.input.key.keyCode = UInt32(UInt8(ascii: "a"))
      command.input.key.modifiers = 0  // No modifiers.
      #expect(session.insertCharacter(&command))

      // Click the first candidate.
      let copy = Segments()
      copy.assign(from: segments)
      converter.prependCandidatesHandler = { _, _, out in out.assign(from: copy) }
      setSendCommandCommand(.selectCandidate, &command)
      command.input.command.id = 0
      #expect(session.sendCommand(&command))

      // After select candidate session.status_ should be
      // SessionStatus::CONVERSION.

      sendSpecialKey(.space, session, &command)
      #expect(command.output.hasCandidateWindow)
      // The second candidate should be selected.
      #expect(command.output.candidateWindow.focusedIndex == 1)
    }
  }

  @Test func issue2029466() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2029466
      //
      // "a<tab><ctrl-N>a" raised an exception because CommitFirstSegment
      // did not check if the current status is in conversion or
      // precomposition.
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Genmai_Commands_Command()
      f.insertCharacterChars("a", session, &command)

      // <tab>
      let segments = Segments()
      f.setAiueo(segments)
      converter.setStartPredictionWithPreviousSuggestion(segments, true)
      command = Genmai_Commands_Command()
      #expect(session.predictAndConvert(&command))

      // <ctrl-N>
      segments.clear()
      // FinishConversion is expected to return empty Segments.
      let empty = Segments()
      converter.finishConversionHandler = { _, out in out.assign(from: empty) }
      converter.setStartPrediction(segments, false)
      command = Genmai_Commands_Command()
      #expect(session.commitSegment(&command))

      f.insertCharacterChars("a", session, &command)
      expectSingleSegment("あ", command)
      #expect(!command.output.hasCandidateWindow)
    }
  }

  @Test func issue2034943() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2029466
      //
      // The composition should have been reset if CommitSegment submitted
      // the all segments (e.g. the size of segments is one).
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()
      f.insertCharacterChars("mozu", session, &command)

      do {  // Initialize a suggest result triggered by "mozu".
        let segments = Segments()
        let segment = segments.addSegment()
        segment.setKey("mozu")
        let candidate = segment.addCandidate()
        candidate.value = "MOZU"
        let request = f.createConversionRequest(session)
        f.fillT13Ns(request, segments)
        converter.setStartConversion(segments, true)
      }
      // Get conversion
      command = Genmai_Commands_Command()
      #expect(session.convert(&command))

      // submit segment
      command = Genmai_Commands_Command()
      #expect(session.commitSegment(&command))

      // The composition should have been reset.
      f.insertCharacterChars("ku", session, &command)
      #expect(command.output.preedit.segment.first?.value == "く")
    }
  }

  @Test func issue2026354() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2026354
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Genmai_Commands_Command()
      f.insertCharacterChars("aiueo", session, &command)

      // Trigger suggest by pressing "a".
      let segments = Segments()
      f.setAiueo(segments)
      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      command = Genmai_Commands_Command()
      #expect(session.convert(&command))

      //  EXPECT_TRUE(session.ConvertNext(&command));
      testSendKey("Space", session, &command)
      expectPreedit("あいうえお", command)
      command.output.clearCandidateWindow()
      #expect(!command.output.hasCandidateWindow)
    }
  }

  @Test func issue2066906() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2066906
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey("a")
      var candidate = segment.addCandidate()
      candidate.value = "abc"
      candidate = segment.addCandidate()
      candidate.value = "abcdef"
      converter.setStartPredictionWithPreviousSuggestion(segments, true)

      // Prediction with "a"
      var command = Genmai_Commands_Command()
      #expect(session.predictAndConvert(&command))
      #expect(!command.output.hasResult)

      // Commit
      command = Genmai_Commands_Command()
      #expect(session.commit(&command))
      expectResult("abc", command)

      converter.setStartPrediction(segments, true)
      f.insertCharacterChars("a", session, &command)
      #expect(!command.output.hasResult)
    }
  }

  @Test func issue2187132() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2187132
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()

      // Shift + Ascii triggers temporary input mode switch.
      sendKey("A", session, &command)
      sendKey("Enter", session, &command)

      // After submission, input mode should be reverted.
      sendKey("a", session, &command)
      #expect(getComposition(command) == "あ")

      command = Genmai_Commands_Command()
      session.editCancel(&command)
      #expect(getComposition(command).isEmpty)

      // If a user intentionally switched an input mode, it should remain.
      #expect(session.compositionModeHalfASCII(&command))
      sendKey("A", session, &command)
      sendKey("Enter", session, &command)
      sendKey("a", session, &command)
      #expect(getComposition(command) == "a")
    }
  }

  @Test func issue2190364() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2190364
      var config = Genmai_Config_Config()
      config.preeditMethod = .kana

      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      session.setConfig(config)
      f.initSessionToPrecomposition(session)

      var command = Genmai_Commands_Command()
      session.toggleAlphanumericMode(&command)

      insertCharacterCodeAndString("a", "ち", session, &command)
      #expect(getComposition(command) == "a")

      command = Genmai_Commands_Command()
      session.toggleAlphanumericMode(&command)
      #expect(getComposition(command) == "a")

      insertCharacterCodeAndString("i", "に", session, &command)
      #expect(getComposition(command) == "aに")
    }
  }

  @Test func issue1556649() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/1556649
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()
      f.insertCharacterChars("kudoudesu", session, &command)
      #expect(getComposition(command) == "くどうです")
      #expect(command.output.preedit.cursor == 5)

      command = Genmai_Commands_Command()
      #expect(session.displayAsHalfKatakana(&command))
      #expect(getComposition(command) == "ｸﾄﾞｳﾃﾞｽ")
      #expect(command.output.preedit.cursor == 7)

      for i in 0..<7 {
        let expectedPos = UInt32(6 - i)
        #expect(sendKey("Left", session, &command))
        #expect(command.output.preedit.cursor == expectedPos)
      }
    }
  }

  @Test func issue1518994() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/1518994.
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      // - Can't input space in ascii mode.
      do {
        let session = Session(engine)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()
        #expect(sendKey("a", session, &command))
        command = Genmai_Commands_Command()
        #expect(session.toggleAlphanumericMode(&command))
        #expect(sendKey("i", session, &command))
        #expect(getComposition(command) == "あi")

        #expect(sendKey("Space", session, &command))
        #expect(getComposition(command) == "あi ")
      }

      do {
        let session = Session(engine)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()
        #expect(sendKey("a", session, &command))
        #expect(sendKey("I", session, &command))
        #expect(getComposition(command) == "あI")

        #expect(sendKey("Space", session, &command))
        #expect(getComposition(command) == "あI ")
      }
    }
  }

  @Test func issue1571043() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/1571043.
      // - Underline of composition is separated.
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()
      f.insertCharacterChars("aiu", session, &command)
      #expect(getComposition(command) == "あいう")

      for i in 0..<3 {
        let expectedPos = UInt32(2 - i)
        #expect(sendKey("Left", session, &command))
        #expect(command.output.preedit.cursor == expectedPos)
        #expect(command.output.preedit.segment.count == 1)
      }
    }
  }

  @Test func issue2217250() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2217250.
      // Temporary direct input mode through a special sequence such as
      // www. continues even after committing them
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()
      f.insertCharacterChars("www.", session, &command)
      #expect(getComposition(command) == "www.")
      #expect(command.output.mode == .halfAscii)

      sendKey("Enter", session, &command)
      #expect(command.output.result.value == "www.")
      #expect(command.output.mode == .hiragana)
    }
  }

  @Test func issue2223823() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2223823
      // Input mode does not recover like MS-IME by single shift key down
      // and up.
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()
      sendKey("G", session, &command)
      #expect(getComposition(command) == "G")
      #expect(command.output.mode == .halfAscii)

      sendKey("Shift", session, &command)
      #expect(getComposition(command) == "G")
      #expect(command.output.mode == .hiragana)
    }
  }

  @Test func issue2223762() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2223762.
      // - The first space in half-width alphanumeric mode is full-width.
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()

      #expect(session.compositionModeHalfASCII(&command))
      #expect(command.output.mode == .halfAscii)

      #expect(sendKey("Space", session, &command))
      #expect(!command.output.consumed)
      #expect(!command.output.hasPreedit)
      #expect(!command.output.hasResult)
    }
  }

  @Test func issue2223755() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2223755.
      // - F6 and F7 convert space to half-width.
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      do {  // DisplayAsFullKatakana
        let session = Session(engine)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()

        #expect(sendKey("a", session, &command))
        #expect(sendKey("Eisu", session, &command))
        #expect(sendKey("Space", session, &command))
        #expect(sendKey("Eisu", session, &command))
        #expect(sendKey("i", session, &command))

        #expect(getComposition(command) == "あ い")

        command = Genmai_Commands_Command()
        #expect(session.displayAsFullKatakana(&command))

        #expect(getComposition(command) == "ア　イ")  // fullwidth space
      }

      do {  // ConvertToFullKatakana
        let session = Session(engine)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()

        #expect(sendKey("a", session, &command))
        #expect(sendKey("Eisu", session, &command))
        #expect(sendKey("Space", session, &command))
        #expect(sendKey("Eisu", session, &command))
        #expect(sendKey("i", session, &command))

        #expect(getComposition(command) == "あ い")

        do {  // Initialize the mock converter to generate t13n candidates.
          let segments = Segments()
          let segment = segments.addSegment()
          segment.setKey("あ い")
          let candidate = segment.addCandidate()
          candidate.value = "あ い"
          let request = f.createConversionRequest(session)
          f.fillT13Ns(request, segments)
          converter.setStartConversion(segments, true)
        }

        command = Genmai_Commands_Command()
        #expect(session.convertToFullKatakana(&command))

        #expect(getComposition(command) == "ア　イ")  // fullwidth space
      }
    }
  }

  @Test func issue2269058() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2269058.
      // - Temporary input mode should not be overridden by a permanent
      //   input mode change.
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()

      #expect(sendKey("G", session, &command))
      #expect(command.output.mode == .halfAscii)

      command = Genmai_Commands_Command()
      #expect(session.compositionModeHalfASCII(&command))
      #expect(command.output.mode == .halfAscii)

      #expect(sendKey("Shift", session, &command))
      #expect(command.output.mode == .hiragana)
    }
  }

  @Test func issue2272745() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2272745.
      // A temporary input mode remains when a composition is canceled.
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)
      do {
        let session = Session(engine)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()

        #expect(sendKey("G", session, &command))
        #expect(command.output.mode == .halfAscii)

        #expect(sendKey("Backspace", session, &command))
        #expect(command.output.mode == .hiragana)
      }

      do {
        let session = Session(engine)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()

        #expect(sendKey("G", session, &command))
        #expect(command.output.mode == .halfAscii)

        #expect(sendKey("Escape", session, &command))
        #expect(command.output.mode == .hiragana)
      }
    }
  }

  @Test func issue2282319() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2282319.
      // InsertFullSpace is not working in half-width input mode.
      var config = Genmai_Config_Config()
      config.sessionKeymap = .msime

      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      let keyMapManager = KeyMapManager(config)
      f.initSessionToPrecomposition(session)
      session.setConfig(config)
      session.setKeyMapManager(keyMapManager)

      var command = Genmai_Commands_Command()
      #expect(session.compositionModeHalfASCII(&command))
      #expect(command.output.consumed)
      #expect(command.output.mode == .halfAscii)

      #expect(testSendKey("a", session, &command))
      #expect(command.output.consumed)

      #expect(sendKey("a", session, &command))
      #expect(command.output.consumed)
      expectPreedit("a", command)

      #expect(testSendKey("Ctrl Shift Space", session, &command))
      #expect(command.output.consumed)

      #expect(sendKey("Ctrl Shift Space", session, &command))
      #expect(command.output.consumed)
      expectPreedit("a　", command)  // Full-width space
    }
  }

  @Test func issue2297060() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2297060.
      // Ctrl-Space is not working
      var config = Genmai_Config_Config()
      config.sessionKeymap = .msime

      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      let keyMapManager = KeyMapManager(config)
      f.initSessionToPrecomposition(session)
      session.setConfig(config)
      session.setKeyMapManager(keyMapManager)

      var command = Genmai_Commands_Command()
      #expect(sendKey("Ctrl Space", session, &command))
      #expect(!command.output.consumed)
    }
  }

  @Test func issue2379374() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2379374.
      // Numpad ignores Direct input style when typing after conversion.
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()

      // Set numpad_character_form with NUMPAD_DIRECT_INPUT
      var config = Genmai_Config_Config()
      config.numpadCharacterForm = .numpadDirectInput
      session.setConfig(config)

      let segments = Segments()
      do {  // Set mock conversion.
        let segment = segments.addSegment()
        segment.setKey("あ")
        let candidate = segment.addCandidate()
        candidate.value = "亜"
        let request = f.createConversionRequest(session)
        f.fillT13Ns(request, segments)
        converter.setStartConversion(segments, true)
      }

      #expect(sendKey("a", session, &command))
      #expect(getComposition(command) == "あ")

      #expect(sendKey("Space", session, &command))
      #expect(getComposition(command) == "亜")

      #expect(sendKey("Numpad0", session, &command))
      #expect(getComposition(command).isEmpty)
      expectResultAndKey("亜0", "あ0", command)

      // The previous Numpad0 must not affect the current composition.
      #expect(sendKey("a", session, &command))
      #expect(getComposition(command) == "あ")
    }
  }

  @Test func issue2569789() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2379374.
      // After typing "google", the input mode does not come back to the
      // previous input mode.
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      do {
        let session = Session(engine)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()

        f.insertCharacterChars("google", session, &command)
        #expect(getComposition(command) == "google")
        #expect(command.output.mode == .hiragana)

        #expect(sendKey("enter", session, &command))
        try #require(command.output.hasResult)
        #expect(command.output.result.value == "google")
        #expect(command.output.mode == .hiragana)
      }

      do {
        let session = Session(engine)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()

        f.insertCharacterChars("Google", session, &command)
        #expect(command.output.mode == .halfAscii)

        #expect(sendKey("enter", session, &command))
        try #require(command.output.hasResult)
        #expect(command.output.result.value == "Google")
        #expect(command.output.mode == .hiragana)
      }

      do {
        let session = Session(engine)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()

        f.insertCharacterChars("Google", session, &command)
        #expect(command.output.mode == .halfAscii)

        #expect(sendKey("shift", session, &command))
        #expect(getComposition(command) == "Google")
        #expect(command.output.mode == .hiragana)

        f.insertCharacterChars("aaa", session, &command)
        #expect(getComposition(command) == "Googleあああ")
      }

      do {
        let session = Session(engine)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()

        f.insertCharacterChars("http", session, &command)
        #expect(command.output.mode == .halfAscii)

        #expect(sendKey("enter", session, &command))
        try #require(command.output.hasResult)
        #expect(command.output.result.value == "http")
        #expect(command.output.mode == .hiragana)
      }
    }
  }

  @Test func issue2555503() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2555503.
      // Mode respects the previous character too much.
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()
      sendKey("a", session, &command)

      command = Genmai_Commands_Command()
      session.compositionModeFullKatakana(&command)

      sendKey("i", session, &command)
      #expect(getComposition(command) == "あイ")

      sendKey("backspace", session, &command)
      #expect(getComposition(command) == "あ")
      #expect(command.output.mode == .fullKatakana)
    }
  }

  /// Body shared by Issue2791640 / CommitExistingPreeditWhenIMEIsTurnedOff.
  private func checkCommitOnImeOff(_ f: SessionTestFixture, _ engine: MockEngine, _ offKey: String)
    throws
  {
    let session = Session(engine)
    f.initSessionToPrecomposition(session)

    var command = Genmai_Commands_Command()
    sendKey("a", session, &command)
    sendKey(offKey, session, &command)

    try #require(command.output.consumed)

    try #require(command.output.hasResult)
    #expect(command.output.result.value == "あ")
    #expect(command.output.mode == .direct)

    try #require(!command.output.hasPreedit)
  }

  @Test func issue2791640() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // This is a unittest against http://b/2791640.
      // Existing preedit should be committed when IME is turned off.
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)
      try checkCommitOnImeOff(f, engine, "hankaku/zenkaku")
    }
  }

  @Test func commitExistingPreeditWhenIMEIsTurnedOff() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      // Existing preedit should be committed when IME is turned off.
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      // Check "hankaku/zenkaku"
      try checkCommitOnImeOff(f, engine, "hankaku/zenkaku")
      // Check "kanji"
      try checkCommitOnImeOff(f, engine, "kanji")
    }
  }

  @Test func sendKeyDirectInputStateTest() throws {
    // InputModeChange commands from direct mode are supported only for Windows
    // for now. (The body is #ifdef _WIN32 in C++.)
  }

  @Test func handlingDirectInputTableAttribute() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let table = Table()
      table.addRuleWithAttributes("ka", "か", "", .directInput)
      table.addRuleWithAttributes("tt", "っ", "t", .directInput)
      table.addRuleWithAttributes("ta", "た", "", .noTableAttribute)

      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      session.withInternalComposerOnlyForUnittest { $0.setTable(table) }

      var command = Genmai_Commands_Command()
      sendKey("k", session, &command)
      #expect(!command.output.hasResult)

      sendKey("a", session, &command)
      expectResult("か", command)

      sendKey("t", session, &command)
      #expect(!command.output.hasResult)

      sendKey("t", session, &command)
      #expect(!command.output.hasResult)

      sendKey("a", session, &command)
      expectResult("った", command)
    }
  }

  @Test func imeOnWithModeTest() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)
      for (mode, expected) in [
        (Genmai_Commands_CompositionMode.hiragana, "あ"), (.fullKatakana, "ア"),
        (.halfKatakana, "ｱ"),  // "ｱ" (half-width Katakana)
        (.fullAscii, "ａ"), (.halfAscii, "a"),
      ] {
        let session = Session(engine)
        f.initSessionToDirect(session)

        var command = Genmai_Commands_Command()
        command.input.key.mode = mode
        #expect(session.imeOn(&command))
        if mode == .hiragana {
          #expect(command.output.hasConsumed)
          #expect(command.output.consumed)
        }
        #expect(command.output.hasMode)
        #expect(command.output.mode == mode)
        sendKey("a", session, &command)
        expectSingleSegment(expected, command)
      }
    }
  }

  @Test func compositionModeConsumed() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()
      #expect(session.compositionModeHiragana(&command))
      #expect(command.output.consumed)
      #expect(command.output.mode == .hiragana)
      command = Genmai_Commands_Command()
      #expect(session.compositionModeFullKatakana(&command))
      #expect(command.output.consumed)
      #expect(command.output.mode == .fullKatakana)
      command = Genmai_Commands_Command()
      #expect(session.compositionModeHalfKatakana(&command))
      #expect(command.output.consumed)
      #expect(command.output.mode == .halfKatakana)
      command = Genmai_Commands_Command()
      #expect(session.compositionModeFullASCII(&command))
      #expect(command.output.consumed)
      #expect(command.output.mode == .fullAscii)
      command = Genmai_Commands_Command()
      #expect(session.compositionModeHalfASCII(&command))
      #expect(command.output.consumed)
      #expect(command.output.mode == .halfAscii)
    }
  }

  @Test func inputModeConsumedForTestSendKey() throws {
    // This test is only for Windows, because InputModeHiragana bound
    // with Hiragana key is only supported on Windows yet. (#ifdef _WIN32)
  }

  @Test func compositionModeOutputHasComposition() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()
      sendKey("a", session, &command)
      expectSingleSegment("あ", command)

      let steps: [((inout Genmai_Commands_Command) -> Bool, Genmai_Commands_CompositionMode)] = [
        ({ session.compositionModeHiragana(&$0) }, .hiragana),
        ({ session.compositionModeFullKatakana(&$0) }, .fullKatakana),
        ({ session.compositionModeHalfKatakana(&$0) }, .halfKatakana),
        ({ session.compositionModeFullASCII(&$0) }, .fullAscii),
        ({ session.compositionModeHalfASCII(&$0) }, .halfAscii),
      ]
      for (step, mode) in steps {
        command = Genmai_Commands_Command()
        #expect(step(&command))
        #expect(command.output.consumed)
        #expect(command.output.mode == mode)
        expectSingleSegment("あ", command)
      }
    }
  }

  @Test func compositionModeOutputHasCandidates() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      let segments = Segments()
      f.setAiueo(segments)
      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      var command = Genmai_Commands_Command()
      f.insertCharacterChars("aiueo", session, &command)

      command = Genmai_Commands_Command()
      session.convert(&command)
      session.convertNext(&command)
      #expect(command.output.hasCandidateWindow)
      #expect(command.output.hasPreedit)

      let steps: [((inout Genmai_Commands_Command) -> Bool, Genmai_Commands_CompositionMode)] = [
        ({ session.compositionModeHiragana(&$0) }, .hiragana),
        ({ session.compositionModeFullKatakana(&$0) }, .fullKatakana),
        ({ session.compositionModeHalfKatakana(&$0) }, .halfKatakana),
        ({ session.compositionModeFullASCII(&$0) }, .fullAscii),
        ({ session.compositionModeHalfASCII(&$0) }, .halfAscii),
      ]
      for (step, mode) in steps {
        command = Genmai_Commands_Command()
        #expect(step(&command))
        #expect(command.output.consumed)
        #expect(command.output.mode == mode)
        #expect(command.output.hasCandidateWindow)
        #expect(command.output.hasPreedit)
      }
    }
  }

  @Test func performedCommand() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      do {
        var command = Genmai_Commands_Command()
        // IMEOff
        sendSpecialKey(.off, session, &command)
      }
      do {
        var command = Genmai_Commands_Command()
        // IMEOn
        sendSpecialKey(.on, session, &command)
      }
      do {
        var command = Genmai_Commands_Command()
        // 'a'
        sendKey("a", session, &command)
      }
      do {
        // SetStartConversion for changing state to Convert.
        let segments = Segments()
        f.setAiueo(segments)
        let request = f.createConversionRequest(session)
        f.fillT13Ns(request, segments)
        converter.setStartConversion(segments, true)
        var command = Genmai_Commands_Command()
        // SPACE
        sendSpecialKey(.space, session, &command)
      }
      do {
        var command = Genmai_Commands_Command()
        // ENTER
        sendSpecialKey(.enter, session, &command)
      }
    }
  }

  @Test func resetContext() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()

      var resetCount = 0
      converter.resetConversionHandler = { _ in resetCount += 1 }
      session.resetContext(&command)
      #expect(!command.output.consumed)

      let segments = Segments()
      segments.addSegment().addCandidate()  // Stub candidate.
      converter.setStartPrediction(segments, true)
      #expect(sendKey("A", session, &command))
      command = Genmai_Commands_Command()
      // EXPECT_CALL(*converter, ResetConversion(_)).Times(2)
      #expect(resetCount == 2)

      resetCount = 0
      session.resetContext(&command)
      #expect(command.output.consumed)
      // EXPECT_CALL(*converter, ResetConversion(_))
      #expect(resetCount == 1)
    }
  }

  @Test func clearUndoOnResetContext() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      // Undo requires capability DELETE_PRECEDING_TEXT.
      var capability = Genmai_Commands_Capability()
      capability.textDeletion = .deletePrecedingText
      session.setClientCapability(capability)

      var command = Genmai_Commands_Command()
      let segments = Segments()

      do {  // Create segments
        f.insertCharacterChars("aiueo", session, &command)
        f.setAiueo(segments)
        // Don't use FillT13Ns(). It makes platform dependent segments.
        var candidate = segments.mutableSegment(0).addCandidate()
        candidate.value = "aiueo"
        candidate = segments.mutableSegment(0).addCandidate()
        candidate.value = "AIUEO"
      }

      do {
        converter.setStartConversion(segments, true)
        command = Genmai_Commands_Command()
        session.convert(&command)
        #expect(!command.output.hasResult)
        expectSingleSegment("あいうえお", command)

        converter.setCommitSegmentValue(segments, true)
        command = Genmai_Commands_Command()
        session.commit(&command)
        #expect(!command.output.hasPreedit)
        expectResult("あいうえお", command)

        command = Genmai_Commands_Command()
        session.resetContext(&command)

        command = Genmai_Commands_Command()
        session.undo(&command)
        // After reset, undo shouldn't run.
        #expect(!command.output.hasPreedit)
      }
    }
  }

  @Test func issueResetConversion() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()

      var resetCount = 0
      converter.resetConversionHandler = { _ in resetCount += 1 }
      // Any meaneangless key calls ResetConversion
      #expect(sendKey("enter", session, &command))
      #expect(resetCount == 1)

      resetCount = 0
      #expect(sendKey("space", session, &command))
      #expect(resetCount == 2)
    }
  }

  @Test func issueRevert() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()

      // Changes the state to PRECOMPOSITION
      session.imeOn(&command)

      var revertCount = 0
      var resetCount = 0
      converter.revertConversionHandler = { _ in revertCount += 1 }
      converter.resetConversionHandler = { _ in resetCount += 1 }
      session.revert(&command)
      #expect(!command.output.consumed)
      #expect(revertCount == 1)
      #expect(resetCount == 1)
    }
  }

  // Undo command must call RervertConversion
  @Test func issue3428520() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      // Undo requires capability DELETE_PRECEDING_TEXT.
      var capability = Genmai_Commands_Capability()
      capability.textDeletion = .deletePrecedingText
      session.setClientCapability(capability)

      var command = Genmai_Commands_Command()
      let segments = Segments()
      f.setAiueo(segments)

      converter.setStartPrediction(segments, true)
      f.insertCharacterChars("aiueo", session, &command)
      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)

      // EXPECT_CALL(*converter, StartConversion(_, _)).WillOnce(Return(true));
      converter.startConversionHandler = { _, _ in true }
      command = Genmai_Commands_Command()
      session.convert(&command)
      #expect(!command.output.hasResult)
      expectSingleSegment("あいうえお", command)

      var finishCount = 0
      converter.commitSegmentValueHandler = { _, _, _ in true }
      converter.finishConversionHandler = { _, _ in finishCount += 1 }
      command = Genmai_Commands_Command()
      session.commit(&command)
      #expect(!command.output.hasPreedit)
      expectResult("あいうえお", command)
      #expect(finishCount == 1)

      // RevertConversion must be called.
      var revertCount = 0
      converter.revertConversionHandler = { _ in revertCount += 1 }
      command = Genmai_Commands_Command()
      session.undo(&command)
      #expect(revertCount == 1)
    }
  }

  // Revert command must clear the undo context.
  @Test func issue5742293() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      var config = Genmai_Config_Config()
      config.sessionKeymap = .msime

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      let keyMapManager = KeyMapManager(config)
      session.setConfig(config)
      session.setKeyMapManager(keyMapManager)
      f.initSessionToPrecomposition(session)

      // Undo requires capability DELETE_PRECEDING_TEXT.
      var capability = Genmai_Commands_Capability()
      capability.textDeletion = .deletePrecedingText
      session.setClientCapability(capability)

      f.setUndoContext(session, converter)

      var command = Genmai_Commands_Command()

      // BackSpace key event issues Revert command, which should clear the undo
      // context.
      #expect(sendKey("Backspace", session, &command))

      // Ctrl+BS should be consumed as UNDO.
      #expect(testSendKey("Ctrl Backspace", session, &command))

      #expect(!command.output.consumed)
    }
  }
}
