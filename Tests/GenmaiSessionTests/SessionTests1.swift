// Port of mozc/src/session/session_test.cc (3.35.6354), part 1 (TestOfTestForSetup .. ShortcutFromVK).
//
// Test names that would shadow the free helpers of SessionTestFixture.swift
// (TestSendKey, SendCommand, SwitchCompositionMode) get a `Test` suffix.

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import Testing

@testable import GenmaiSession

private typealias Command = Genmai_Commands_Command

/// `segment->add_candidate()->value = value`.
private func addValue(_ segment: Segment, _ value: String) {
  segment.addCandidate().value = value
}

/// Builds a segment with `key` and candidates having `values`.
private func addSegment(_ segments: Segments, _ key: String, _ values: [String]) -> Segment {
  let segment = segments.addSegment()
  segment.setKey(key)
  for value in values {
    segment.addCandidate().value = value
  }
  return segment
}

@Suite struct SessionTests1 {
  // This test is intentionally defined at this location so that this
  // test can ensure that the first SetUp() initialized table object to
  // the default state.
  @Test func testOfTestForSetup() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      var config = Genmai_Config_Config()
      ConfigHandler.getDefaultConfig(&config)
      let keyMapManager = KeyMapManager(config)
      #expect(
        !config.hasUseAutoConversion,
        "Global config should be initialized for each test fixture.")

      // Make sure that the default roman table is initialized.
      do {
        let engine = MockEngine()
        _ = f.createEngineConverterMock(engine)

        let session = Session(engine)
        session.setConfig(config)
        session.setKeyMapManager(keyMapManager)
        f.initSessionToPrecomposition(session)
        var command = Command()
        sendKey("a", session, &command)
        expectSingleSegment("あ", command)
      }
    }
  }

  @Test func testSendKeyTest() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Command()

      // Precomposition status
      testSendKey("Up", session, &command)
      #expect(!command.output.consumed)

      sendKey("Up", session, &command)
      #expect(!command.output.consumed)

      // InsertSpace on Precomposition status
      // TODO(komatsu): Test both cases of config.ascii_character_form() is
      // FULL_WIDTH and HALF_WIDTH.
      testSendKey("Space", session, &command)
      let consumedOnTestsendkey = command.output.consumed
      sendKey("Space", session, &command)
      let consumedOnSendkey = command.output.consumed
      #expect(consumedOnSendkey == consumedOnTestsendkey)

      // Precomposition status
      testSendKey("G", session, &command)
      #expect(command.output.consumed)
      sendKey("G", session, &command)
      #expect(command.output.consumed)

      // Composition status
      testSendKey("Up", session, &command)
      #expect(command.output.consumed)
      sendKey("Up", session, &command)
      #expect(command.output.consumed)
    }
  }

  @Test func updateComposition() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Command()
      command.input.type = .sendCommand
      command.input.command.type = .updateComposition
      var compositionEvent = Genmai_Commands_SessionCommand.CompositionEvent()
      compositionEvent.compositionString = "かん字"
      compositionEvent.probability = 1.0
      command.input.command.compositionEvents.append(compositionEvent)

      #expect(session.updateComposition(&command))
      #expect(command.output.consumed)
      #expect(command.output.preedit.segment.first?.value == "かん字")
    }
  }

  @Test func sendCommandTest() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Command()
      command.input.type = .sendCommand
      f.insertCharacterChars("kanji", session, &command)

      // REVERT
      sendCommand(.revert, session, &command)
      #expect(command.output.consumed)
      #expect(!command.output.hasResult)
      #expect(!command.output.hasPreedit)
      #expect(!command.output.hasCandidateWindow)

      // SUBMIT
      f.insertCharacterChars("k", session, &command)
      sendCommand(.submit, session, &command)
      #expect(command.output.consumed)
      expectResult("ｋ", command)
      #expect(!command.output.hasPreedit)
      #expect(!command.output.hasCandidateWindow)

      // SWITCH_COMPOSITION_MODE
      sendKey("a", session, &command)
      expectSingleSegment("あ", command)

      switchCompositionMode(.fullAscii, session)

      sendKey("a", session, &command)
      expectSingleSegment("あａ", command)

      // GET_STATUS
      sendCommand(.getStatus, session, &command)
      // FULL_ASCII was set at the SWITCH_COMPOSITION_MODE testcase.
      switchCompositionMode(.fullAscii, session)

      // RESET_CONTEXT
      // test of reverting composition
      f.insertCharacterChars("kanji", session, &command)
      sendCommand(.resetContext, session, &command)
      #expect(command.output.consumed)
      #expect(!command.output.hasResult)
      #expect(!command.output.hasPreedit)
      #expect(!command.output.hasCandidateWindow)
      // test of resetting the history segements
      do {
        let engine = MockEngine()
        let converter = f.createEngineConverterMock(engine)
        // ResetConversion is called twice, first in IMEOff through
        // InitSessionToPrecomposition() and then EchoBack() through
        // SendCommand().
        var resetCount = 0
        converter.resetConversionHandler = { _ in resetCount += 1 }
        let session = Session(engine)
        f.initSessionToPrecomposition(session)
        sendCommand(.resetContext, session, &command)
        #expect(!command.output.consumed)
        #expect(resetCount == 2)
      }
    }
  }

  @Test func switchCompositionModeTest() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      do {
        let session = Session(engine)
        f.initSessionToPrecomposition(session)
        var command = Command()

        // SWITCH_COMPOSITION_MODE
        sendKey("a", session, &command)
        expectSingleSegment("あ", command)

        switchCompositionMode(.fullAscii, session)

        sendKey("a", session, &command)
        expectSingleSegment("あａ", command)

        // GET_STATUS
        sendCommand(.getStatus, session, &command)
        // FULL_ASCII was set at the SWITCH_COMPOSITION_MODE testcase.
        #expect(command.output.mode == .fullAscii)
      }

      do {
        // Confirm that we can change the mode from DIRECT
        // to other modes directly (without IMEOn command).
        let session = Session(engine)
        f.initSessionToDirect(session)

        var command = Command()

        // GET_STATUS
        sendCommand(.getStatus, session, &command)
        #expect(command.output.mode == .direct)

        // SWITCH_COMPOSITION_MODE
        switchCompositionMode(.hiragana, session)

        // GET_STATUS
        sendCommand(.getStatus, session, &command)
        #expect(command.output.mode == .hiragana)

        sendKey("a", session, &command)
        expectSingleSegment("あ", command)

        // GET_STATUS
        sendCommand(.getStatus, session, &command)
        #expect(command.output.mode == .hiragana)
      }
    }
  }

  @Test func switchCompositionModeWithCandidateList() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      do {
        let session = Session(engine)
        f.initSessionToPrecomposition(session)

        // Enable zero query suggest.
        var request = Genmai_Commands_Request()
        f.setupZeroQuerySuggestionReady(true, session, &request, converter)

        var command = Command()
        session.commit(&command)
        #expect(command.output.result.value == "GOOGLE")
        #expect(getComposition(command) == "")

        #expect(command.output.hasAllCandidateWords)
        #expect(session.context.state == .precomposition)

        // SWITCH_COMPOSITION_MODE
        command = Command()
        #expect(switchCompositionModeCommand(.fullAscii, session, &command))

        // FULL_ASCII was set at the SWITCH_COMPOSITION_MODE testcase.
        #expect(command.output.mode == .fullAscii)
        #expect(command.output.hasAllCandidateWords)
        #expect(session.context.state == .precomposition)
      }

      do {
        let session = Session(engine)
        f.initSessionToPrecomposition(session)

        do {
          // Set up a mock conversion result.
          let segments = Segments()
          _ = addSegment(segments, "", ["google"])
          converter.setStartPrediction(segments, true)
        }
        // Type "g".
        var command = Command()
        f.insertCharacterChars("g", session, &command)

        #expect(command.output.hasAllCandidateWords)
        #expect(session.context.state == .composition)

        // SWITCH_COMPOSITION_MODE
        command = Command()
        #expect(switchCompositionModeCommand(.fullAscii, session, &command))

        // FULL_ASCII was set at the SWITCH_COMPOSITION_MODE testcase.
        #expect(command.output.mode == .fullAscii)
        #expect(command.output.hasAllCandidateWords)
        #expect(session.context.state == .composition)
      }
    }
  }

  @Test func revertComposition() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      // Issue#2237323
      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Command()

      f.insertCharacterChars("aiueo", session, &command)
      let request = f.createConversionRequest(session)
      let segments = Segments()
      f.setAiueo(segments)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      command = Command()
      session.convert(&command)

      // REVERT
      sendCommand(.revert, session, &command)
      #expect(command.output.consumed)
      #expect(!command.output.hasResult)
      #expect(!command.output.hasPreedit)
      #expect(!command.output.hasCandidateWindow)

      sendKey("a", session, &command)
      expectSingleSegment("あ", command)
    }
  }

  @Test func compositionMode() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Command()
      #expect(session.compositionModeHalfASCII(&command))
      #expect(command.output.consumed)
      #expect(command.output.mode == .halfAscii)

      sendKey("a", session, &command)
      #expect(command.output.preedit.segment.first?.key == "a")

      command = Command()
      session.commit(&command)

      // Input mode remains even after submission.
      command = Command()
      session.getStatus(&command)
      #expect(command.output.mode == .halfAscii)
    }
  }

  @Test func selectCandidate() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Command()
      f.insertCharacterChars("aiueo", session, &command)
      let request = f.createConversionRequest(session)
      let segments = Segments()
      f.setAiueo(segments)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      command = Command()
      session.convert(&command)

      command = Command()
      session.convertNext(&command)

      setSendCommandCommand(.selectCandidate, &command)
      command.input.command.id = -Int32(TransliterationType.halfKatakana.rawValue + 1)
      session.sendCommand(&command)
      #expect(command.output.consumed)
      #expect(!command.output.hasResult)
      expectPreedit("ｱｲｳｴｵ", command)
      #expect(!command.output.hasCandidateWindow)
    }
  }

  @Test func highlightCandidate() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Command()
      f.insertCharacterChars("aiueo", session, &command)
      let request = f.createConversionRequest(session)
      let segments = Segments()
      f.setAiueo(segments)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      command = Command()
      session.convert(&command)

      command = Command()
      session.convertNext(&command)
      expectSingleSegment("アイウエオ", command)

      setSendCommandCommand(.highlightCandidate, &command)
      command.input.command.id = -Int32(TransliterationType.halfKatakana.rawValue + 1)
      session.sendCommand(&command)
      #expect(command.output.consumed)
      #expect(!command.output.hasResult)
      expectSingleSegment("ｱｲｳｴｵ", command)
      #expect(command.output.hasCandidateWindow)
    }
  }

  @Test func conversion() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Command()
      f.insertCharacterChars("aiueo", session, &command)
      let request = f.createConversionRequest(session)
      let segments = Segments()
      f.setAiueo(segments)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      expectSingleSegmentAndKey("あいうえお", "あいうえお", command)

      command = Command()
      session.convert(&command)

      command = Command()
      session.convertNext(&command)

      var key = ""
      for segment in command.output.preedit.segment {
        #expect(segment.hasValue)
        #expect(segment.hasKey)
        key += segment.key
      }
      #expect(key == "あいうえお")
    }
  }

  @Test func segmentWidthShrink() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Command()
      f.insertCharacterChars("aiueo", session, &command)
      let request = f.createConversionRequest(session)
      let segments = Segments()
      f.setAiueo(segments)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      command = Command()
      session.convert(&command)

      command = Command()
      session.segmentWidthShrink(&command)

      command = Command()
      session.segmentWidthShrink(&command)
    }
  }

  @Test func convertPrev() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Command()
      f.insertCharacterChars("aiueo", session, &command)
      let request = f.createConversionRequest(session)
      let segments = Segments()
      f.setAiueo(segments)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      command = Command()
      session.convert(&command)

      command = Command()
      session.convertNext(&command)

      command = Command()
      session.convertPrev(&command)

      command = Command()
      session.convertPrev(&command)
    }
  }

  @Test func resetFocusedSegmentAfterCommit() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Command()
      f.insertCharacterChars("watasinonamaehanakanodesu", session, &command)
      // "わたしのなまえはなかのです[]"

      let segments = Segments()
      _ = addSegment(segments, "わたしの", ["私の", "わたしの", "渡しの"])
      _ = addSegment(segments, "なまえは", ["名前は", "ナマエは"])
      _ = addSegment(segments, "なかのです", ["中野です", "なかのです"])
      let request1 = f.createConversionRequest(session)
      f.fillT13Ns(request1, segments)
      converter.setStartConversion(segments, true)

      command = Command()
      session.convert(&command)
      #expect(command.output.hasPreedit)
      #expect(!command.output.hasResult)
      // "[私の]名前は中野です"
      command = Command()
      session.segmentFocusRight(&command)
      #expect(command.output.hasPreedit)
      #expect(!command.output.hasResult)
      // "私の[名前は]中野です"
      command = Command()
      session.segmentFocusRight(&command)
      #expect(command.output.hasPreedit)
      #expect(!command.output.hasResult)
      // "私の名前は[中野です]"

      command = Command()
      session.convertNext(&command)
      #expect(command.output.candidateWindow.focusedIndex == 1)
      #expect(command.output.hasPreedit)
      #expect(!command.output.hasResult)
      // "私の名前は[中のです]"

      command = Command()
      session.convertNext(&command)
      #expect(command.output.candidateWindow.focusedIndex == 2)
      #expect(command.output.hasPreedit)
      #expect(!command.output.hasResult)
      // "私の名前は[なかのです]"

      command = Command()
      session.commit(&command)
      #expect(!command.output.hasPreedit)
      #expect(command.output.hasResult)
      // "私の名前はなかのです[]"
      converter.clear()

      f.insertCharacterChars("a", session, &command)

      segments.clear()
      _ = addSegment(segments, "あ", ["阿", "亜"])

      let request2 = f.createConversionRequest(session)
      f.fillT13Ns(request2, segments)
      converter.setStartConversion(segments, true)

      // "あ[]"

      command = Command()
      session.convert(&command)
      // "[阿]"

      command = Command()
      // If the forcused_segment_ was not reset, this raises segmentation fault.
      session.convertNext(&command)
      // "[亜]"
    }
  }

  @Test func resetFocusedSegmentAfterCancel() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Command()
      f.insertCharacterChars("ai", session, &command)

      let segments = Segments()
      _ = addSegment(segments, "あい", ["愛", "相"])
      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)
      // "あい[]"

      command = Command()
      session.convert(&command)
      // "[愛]"
      converter.clear()

      segments.clear()
      _ = addSegment(segments, "あ", ["あ"])
      _ = addSegment(segments, "い", ["い", "位"])
      converter.setResizeSegment(segments, true)

      command = Command()
      session.segmentWidthShrink(&command)
      // "[あ]い"
      converter.clear()

      let segment = segments.mutableSegment(0)
      segment.setSegmentType(.fixedValue)
      converter.setCommitSegmentValue(segments, true)

      command = Command()
      session.segmentFocusRight(&command)
      // "あ[い]"

      command = Command()
      session.convertNext(&command)
      // "あ[位]"

      command = Command()
      session.convertCancel(&command)
      // "あい[]"
      converter.clear()

      segments.clear()
      _ = addSegment(segments, "あい", ["愛", "相"])
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      command = Command()
      session.convert(&command)
      // "[愛]"

      command = Command()
      // If the forcused_segment_ was not reset, this raises segmentation fault.
      session.convert(&command)
      // "[相]"
    }
  }

  @Test func keepFixedCandidateAfterSegmentWidthExpand() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      // Issue#1271099
      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Command()
      f.insertCharacterChars("bariniryokouniitta", session, &command)
      // "ばりにりょこうにいった[]"

      let segments = Segments()
      _ = addSegment(segments, "ばりに", ["バリに", "針に"])
      _ = addSegment(segments, "りょこうに", ["旅行に"])
      _ = addSegment(segments, "いった", ["行った"])

      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      command = Command()
      session.convert(&command)
      // ex. "[バリに]旅行に行った"
      #expect(getComposition(command) == "バリに旅行に行った")
      command = Command()
      session.convertNext(&command)
      // ex. "[針に]旅行に行った"
      let firstSegment = command.output.preedit.segment.first?.value

      var segment = segments.mutableSegment(0)
      segment.setSegmentType(.fixedValue)
      segment.moveCandidate(1, 0)
      converter.setCommitSegmentValue(segments, true)

      command = Command()
      session.segmentFocusRight(&command)
      // ex. "針に[旅行に]行った"
      // Make sure the first segment (i.e. "針に" in the above case) remains
      // after moving the focused segment right.
      #expect(command.output.preedit.segment.first?.value == firstSegment)

      segment = segments.mutableSegment(1)
      segment.setKey("りょこうにい")
      var candidate = segment.mutableCandidate(0)
      candidate.value = "旅行に行"

      segment = segments.mutableSegment(2)
      segment.setKey("った")
      candidate = segment.mutableCandidate(0)
      candidate.value = "った"

      converter.setResizeSegment(segments, true)

      command = Command()
      session.segmentWidthExpand(&command)
      // ex. "針に[旅行に行]った"

      // Make sure the first segment (i.e. "針に" in the above case) remains
      // after expanding the focused segment.
      #expect(command.output.preedit.segment.first?.value == firstSegment)
    }
  }

  @Test func commitSegment() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      // Issue#1560608
      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Command()
      f.insertCharacterChars("watasinonamae", session, &command)
      // "わたしのなまえ[]"

      let segments = Segments()
      _ = addSegment(segments, "わたしの", ["私の", "わたしの", "渡しの"])
      _ = addSegment(segments, "なまえ", ["名前"])

      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      command = Command()
      session.convert(&command)
      #expect(command.output.candidateWindow.focusedIndex == 0)
      // "[私の]名前"

      command = Command()
      session.convertNext(&command)
      #expect(command.output.candidateWindow.focusedIndex == 1)
      // "[わたしの]名前"

      command = Command()
      session.convertNext(&command)
      // "[渡しの]名前" showing a candidate window
      #expect(command.output.candidateWindow.focusedIndex == 2)

      let segment = segments.mutableSegment(0)
      segment.setSegmentType(.fixedValue)
      segment.moveCandidate(2, 0)

      converter.setCommitSegments(segments, true)

      command = Command()
      session.commitSegment(&command)
      // "渡しの" + "[名前]"
      #expect(command.output.candidateWindow.focusedIndex == 0)
    }
  }

  @Test func commitSegmentAt2ndSegment() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Command()
      f.insertCharacterChars("watasinohaha", session, &command)
      // "わたしのはは[]"

      let segments = Segments()
      var segment = segments.addSegment()
      segment.setKey("わたしの")
      var candidate = segment.addCandidate()
      candidate.value = "私の"
      segment = segments.addSegment()
      segment.setKey("はは")
      candidate = segment.addCandidate()
      candidate.value = "母"

      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      command = Command()
      session.convert(&command)
      // "[私の]母"

      command = Command()
      session.segmentFocusRight(&command)
      // "私の[母]"

      segment.setSegmentType(.fixedValue)
      segment.moveCandidate(1, 0)
      converter.setCommitSegments(segments, true)

      command = Command()
      session.commitSegment(&command)
      // "私の" + "[母]"

      segment.setKey("は")
      candidate.value = "葉"
      segment = segments.addSegment()
      segment.setKey("は")
      candidate = segment.addCandidate()
      candidate.value = "は"
      segments.popFrontSegment()
      converter.setResizeSegment(segments, true)

      command = Command()
      session.segmentWidthShrink(&command)
      // "私の" + "[葉]は"
      #expect(command.output.preedit.segment.count == 2)
    }
  }

  @Test func transliterations() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Command()
      f.insertCharacterChars("jishin", session, &command)

      let segments = Segments()
      _ = addSegment(segments, "じしん", ["自信", "自身"])

      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      command = Command()
      session.convert(&command)

      command = Command()
      session.convertNext(&command)

      command = Command()
      session.translateHalfASCII(&command)
      expectSingleSegment("jishin", command)

      command = Command()
      session.translateHalfASCII(&command)
      expectSingleSegment("JISHIN", command)

      command = Command()
      session.translateHalfASCII(&command)
      expectSingleSegment("Jishin", command)

      command = Command()
      session.translateHalfASCII(&command)
      expectSingleSegment("jishin", command)
    }
  }

  @Test func transliterationOfNegativeNumber() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Command()
      f.insertCharacterChars("-255", session, &command)
      // "－" (U+FF0D) is used as a minus sign in Windows.
      #expect(
        ensureSingleSegment("−２５５", command) == nil  // "−" is U+2212
          || ensureSingleSegment("－２５５", command) == nil)  // "－" is U+FF0D

      command = Command()
      session.translateHalfASCII(&command)
      expectSingleSegment("-255", command)
    }
  }

  @Test func convertToTransliteration() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Command()
      f.insertCharacterChars("jishin", session, &command)

      let segments = Segments()
      _ = addSegment(segments, "じしん", ["自信", "自身"])

      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      command = Command()
      session.convertToHalfASCII(&command)
      expectSingleSegment("jishin", command)

      command = Command()
      session.convertToHalfASCII(&command)
      expectSingleSegment("JISHIN", command)

      command = Command()
      session.convertToHalfASCII(&command)
      expectSingleSegment("Jishin", command)

      command = Command()
      session.convertToHalfASCII(&command)
      expectSingleSegment("jishin", command)
    }
  }

  @Test func convertToTransliterationOfNegativeNumber() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Command()
      f.insertCharacterChars("-789", session, &command)

      let segments = Segments()
      _ = addSegment(segments, "−７８９", ["−７８９"])

      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      command = Command()
      session.convertToHalfASCII(&command)
      expectSingleSegment("-789", command)

      command = Command()
      session.convertToHalfASCII(&command)
      expectSingleSegment("-789", command)
    }
  }

  @Test func convertToTransliterationWithMultipleSegments() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Command()
      f.insertCharacterChars("like", session, &command)

      let segments = Segments()
      f.setLike(segments)
      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      // Convert
      command = Command()
      session.convert(&command)
      do {  // Check the conversion #1
        let output = command.output
        #expect(!output.hasResult)
        #expect(output.hasPreedit)
        #expect(!output.hasCandidateWindow)

        let conversion = output.preedit
        try #require(conversion.segment.count == 2)
        #expect(conversion.segment[0].value == "ぃ")
        #expect(conversion.segment[1].value == "家")
      }

      // TranslateHalfASCII
      command = Command()
      session.translateHalfASCII(&command)
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

  @Test func convertToHalfWidth() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Command()
      f.insertCharacterChars("abc", session, &command)

      let segments = Segments()
      do {  // Initialize segments.
        _ = addSegment(segments, "あｂｃ", ["あべし"])
      }
      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      command = Command()
      session.convertToHalfWidth(&command)
      expectSingleSegment("ｱbc", command)

      command = Command()
      session.convertToFullASCII(&command)
      // The output is "ａｂｃ".

      command = Command()
      session.convertToHalfWidth(&command)
      expectSingleSegment("abc", command)
    }
  }

  @Test func convertConsonantsToFullAlphanumeric() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Command()
      f.insertCharacterChars("dvd", session, &command)

      let segments = Segments()
      _ = addSegment(segments, "ｄｖｄ", ["DVD", "dvd"])

      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      command = Command()
      session.convertToFullASCII(&command)
      expectSingleSegment("ｄｖｄ", command)

      command = Command()
      session.convertToFullASCII(&command)
      expectSingleSegment("ＤＶＤ", command)

      command = Command()
      session.convertToFullASCII(&command)
      expectSingleSegment("Ｄｖｄ", command)

      command = Command()
      session.convertToFullASCII(&command)
      expectSingleSegment("ｄｖｄ", command)
    }
  }

  @Test func convertConsonantsToFullAlphanumericWithoutCascadingWindow() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)

      var config = Genmai_Config_Config()
      config.useCascadingWindow = false
      session.setConfig(config)

      var command = Command()
      f.initSessionToPrecomposition(session)
      f.insertCharacterChars("dvd", session, &command)

      let segments = Segments()
      _ = addSegment(segments, "ｄｖｄ", ["DVD", "dvd"])

      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      command = Command()
      session.convertToFullASCII(&command)
      expectSingleSegment("ｄｖｄ", command)

      command = Command()
      session.convertToFullASCII(&command)
      expectSingleSegment("ＤＶＤ", command)

      command = Command()
      session.convertToFullASCII(&command)
      expectSingleSegment("Ｄｖｄ", command)

      command = Command()
      session.convertToFullASCII(&command)
      expectSingleSegment("ｄｖｄ", command)
    }
  }

  // Convert input string to Hiragana, Katakana, and Half Katakana
  @Test func switchKanaType() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      do {  // From composition mode.
        let session = Session(engine)
        f.initSessionToPrecomposition(session)
        var command = Command()
        f.insertCharacterChars("abc", session, &command)

        let segments = Segments()
        do {  // Initialize segments.
          _ = addSegment(segments, "あｂｃ", ["あべし"])
        }

        let request = f.createConversionRequest(session)
        f.fillT13Ns(request, segments)
        converter.setStartConversion(segments, true)

        command = Command()
        session.switchKanaType(&command)
        expectSingleSegment("アｂｃ", command)

        command = Command()
        session.switchKanaType(&command)
        expectSingleSegment("ｱbc", command)

        command = Command()
        session.switchKanaType(&command)
        expectSingleSegment("あｂｃ", command)

        command = Command()
        session.switchKanaType(&command)
        expectSingleSegment("アｂｃ", command)

        converter.clear()
      }

      do {  // From conversion mode.
        let session = Session(engine)
        f.initSessionToPrecomposition(session)
        var command = Command()
        f.insertCharacterChars("kanji", session, &command)

        let segments = Segments()
        do {  // Initialize segments.
          _ = addSegment(segments, "かんじ", ["漢字"])
        }

        let request = f.createConversionRequest(session)
        f.fillT13Ns(request, segments)
        converter.setStartConversion(segments, true)

        command = Command()
        session.convert(&command)
        expectSingleSegment("漢字", command)

        command = Command()
        session.switchKanaType(&command)
        expectSingleSegment("かんじ", command)

        command = Command()
        session.switchKanaType(&command)
        expectSingleSegment("カンジ", command)

        command = Command()
        session.switchKanaType(&command)
        expectSingleSegment("ｶﾝｼﾞ", command)

        command = Command()
        session.switchKanaType(&command)
        expectSingleSegment("かんじ", command)

        converter.clear()
      }
    }
  }

  // Rotate input mode among Hiragana, Katakana, and Half Katakana
  @Test func compositionModeSwitchKanaType() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Command()

      // HIRAGANA
      f.insertCharacterChars("a", session, &command)
      #expect(getComposition(command) == "あ")
      #expect(command.output.hasMode)
      #expect(command.output.mode == .hiragana)

      // HIRAGANA to FULL_KATAKANA
      command = Command()
      session.commit(&command)
      command = Command()
      session.compositionModeSwitchKanaType(&command)
      f.insertCharacterChars("a", session, &command)
      #expect(getComposition(command) == "ア")
      #expect(command.output.hasMode)
      #expect(command.output.mode == .fullKatakana)

      // FULL_KATRAKANA to HALF_KATAKANA
      command = Command()
      session.commit(&command)
      command = Command()
      session.compositionModeSwitchKanaType(&command)
      f.insertCharacterChars("a", session, &command)
      #expect(getComposition(command) == "ｱ")
      #expect(command.output.hasMode)
      #expect(command.output.mode == .halfKatakana)

      // HALF_KATAKANA to HIRAGANA
      command = Command()
      session.commit(&command)
      command = Command()
      session.compositionModeSwitchKanaType(&command)
      f.insertCharacterChars("a", session, &command)
      #expect(getComposition(command) == "あ")
      #expect(command.output.hasMode)
      #expect(command.output.mode == .hiragana)

      // To Half ASCII mode.
      command = Command()
      session.commit(&command)
      command = Command()
      session.compositionModeHalfASCII(&command)
      f.insertCharacterChars("a", session, &command)
      #expect(getComposition(command) == "a")
      #expect(command.output.hasMode)
      #expect(command.output.mode == .halfAscii)

      // HALF_ASCII to HALF_ASCII
      command = Command()
      session.commit(&command)
      command = Command()
      session.compositionModeSwitchKanaType(&command)
      f.insertCharacterChars("a", session, &command)
      #expect(getComposition(command) == "a")
      #expect(command.output.hasMode)
      #expect(command.output.mode == .halfAscii)

      // To Full ASCII mode.
      command = Command()
      session.commit(&command)
      command = Command()
      session.compositionModeFullASCII(&command)
      f.insertCharacterChars("a", session, &command)
      #expect(getComposition(command) == "ａ")
      #expect(command.output.hasMode)
      #expect(command.output.mode == .fullAscii)

      // FULL_ASCII to FULL_ASCII
      command = Command()
      session.commit(&command)
      command = Command()
      session.compositionModeSwitchKanaType(&command)
      f.insertCharacterChars("a", session, &command)
      #expect(getComposition(command) == "ａ")
      #expect(command.output.hasMode)
      #expect(command.output.mode == .fullAscii)
    }
  }

  @Test func translateHalfWidth() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Command()
      f.insertCharacterChars("abc", session, &command)

      command = Command()
      session.translateHalfWidth(&command)
      expectSingleSegment("ｱbc", command)

      command = Command()
      session.translateFullASCII(&command)
      expectSingleSegment("ａｂｃ", command)

      command = Command()
      session.translateHalfWidth(&command)
      expectSingleSegment("abc", command)
    }
  }

  @Test func updatePreferences() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Command()
      f.insertCharacterChars("aiueo", session, &command)
      let segments = Segments()
      f.setAiueo(segments)

      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      setSendKeyCommand("SPACE", &command)
      command.input.config.useCascadingWindow = false
      session.sendKey(&command)
      setSendKeyCommand("SPACE", &command)
      session.sendKey(&command)

      let noCascadingCandSize = command.output.candidateWindow.candidate.count

      command = Command()
      session.convertCancel(&command)

      setSendKeyCommand("SPACE", &command)
      command.input.config.useCascadingWindow = true
      session.sendKey(&command)
      setSendKeyCommand("SPACE", &command)
      session.sendKey(&command)

      let cascadingCandSize = command.output.candidateWindow.candidate.count

      #if os(Linux)
        #expect(cascadingCandSize == noCascadingCandSize)
      #else
        #expect(noCascadingCandSize > cascadingCandSize)
      #endif

      command = Command()
      session.convertCancel(&command)

      // On MS-IME keymap, EISU key does nothing.
      setSendKeyCommand("EISU", &command)
      command.input.config.sessionKeymap = .msime
      session.sendKey(&command)
      #expect(command.output.status.mode == .halfAscii)
      #expect(command.output.status.comebackMode == .halfAscii)

      // On KOTOERI keymap, EISU key does "ToggleAlphanumericMode".
      setSendKeyCommand("EISU", &command)
      command.input.config.sessionKeymap = .kotoeri
      session.sendKey(&command)
      #expect(command.output.status.mode == .hiragana)
      #expect(command.output.status.comebackMode == .hiragana)
    }
  }

  @Test func romajiInput() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let table = Table()
      table.addRule("pa", "ぱ", "")
      table.addRule("n", "ん", "")
      table.addRule("na", "な", "")
      // This rule makes the "n" rule ambiguous.

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      session.withInternalComposerOnlyForUnittest { $0.setTable(table) }
      f.initSessionToPrecomposition(session)

      var command = Command()
      f.insertCharacterChars("pan", session, &command)

      #expect(command.output.preedit.segment.first?.value == "ぱｎ")

      command = Command()

      let segments = Segments()
      _ = addSegment(segments, "ぱん", ["パン"])

      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      session.convertToHiragana(&command)
      expectSingleSegment("ぱん", command)

      command = Command()
      session.convertToHalfASCII(&command)
      expectSingleSegment("pan", command)
    }
  }

  @Test func kanaInput() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let table = Table()
      table.addRule("す゛", "ず", "")

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      session.withInternalComposerOnlyForUnittest { $0.setTable(table) }
      f.initSessionToPrecomposition(session)

      var command = Command()
      setSendKeyCommand("m", &command)
      command.input.key.keyString = "も"
      session.sendKey(&command)

      setSendKeyCommand("r", &command)
      command.input.key.keyString = "す"
      session.sendKey(&command)

      setSendKeyCommand("@", &command)
      command.input.key.keyString = "゛"
      session.sendKey(&command)

      setSendKeyCommand("h", &command)
      command.input.key.keyString = "く"
      session.sendKey(&command)

      setSendKeyCommand("!", &command)
      command.input.key.keyString = "!"
      session.sendKey(&command)

      #expect(command.output.preedit.segment.first?.value == "もずく！")

      let segments = Segments()
      _ = addSegment(segments, "もずく!", ["もずく！"])

      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      command = Command()
      session.convertToHalfASCII(&command)
      expectSingleSegment("mr@h!", command)
    }
  }

  @Test func exceededComposition() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Command()

      let exceededPreedit = String(repeating: "a", count: 500)
      try #require(exceededPreedit.utf8.count == 500)
      f.insertCharacterChars(exceededPreedit, session, &command)

      let longA = String(repeating: "あ", count: 500)
      let segments = Segments()
      _ = addSegment(segments, longA, [longA])

      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      command = Command()
      session.convert(&command)
      #expect(!command.output.hasCandidateWindow)

      // The status should remain the preedit status, although the
      // previous command was convert.  The next command makes sure that
      // the preedit will disappear by canceling the preedit status.
      command = Command()
      command.input.key.specialKey = .escape
      #expect(!command.output.hasPreedit)
    }
  }

  @Test func outputAllCandidateWords() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Command()

      let segments = Segments()
      f.setAiueo(segments)
      f.insertCharacterChars("aiueo", session, &command)

      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      command = Command()
      session.convert(&command)
      do {
        let output = command.output
        #expect(output.hasAllCandidateWords)

        #expect(output.allCandidateWords.focusedIndex == 0)
        #expect(output.allCandidateWords.category == .conversion)
        // [ "あいうえお", "アイウエオ", "アイウエオ" (t13n), "あいうえお" (t13n),
        //   "aiueo" (t13n), "AIUEO" (t13n), "Aieuo" (t13n),
        //   "ａｉｕｅｏ"  (t13n), "ＡＩＵＥＯ" (t13n), "Ａｉｅｕｏ" (t13n),
        //   "ｱｲｳｴｵ" (t13n) ]
        #expect(output.allCandidateWords.candidates.count == 11)
      }

      command = Command()
      session.convertNext(&command)
      do {
        let output = command.output

        #expect(output.hasAllCandidateWords)

        #expect(output.allCandidateWords.focusedIndex == 1)
        #expect(output.allCandidateWords.category == .conversion)
        #expect(output.allCandidateWords.candidates.count == 11)
      }
    }
  }

  @Test func undoForComposition() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      // Enable zero query suggest.
      var request = Genmai_Commands_Request()
      f.setupZeroQuerySuggestionReady(true, session, &request, converter)

      // Undo requires capability DELETE_PRECEDING_TEXT.
      var capability = Genmai_Commands_Capability()
      capability.textDeletion = .deletePrecedingText
      session.setClientCapability(capability)

      var command = Command()
      let segments = Segments()

      do {  // Undo for CommitFirstSuggestion
        f.setAiueo(segments)
        converter.setStartPrediction(segments, true)
        f.insertCharacterChars("ai", session, &command)
        #expect(getComposition(command) == "あい")

        command = Command()
        session.commitFirstSuggestion(&command)
        #expect(!command.output.hasPreedit)
        expectResult("あいうえお", command)
        #expect(session.context.state == .precomposition)

        command = Command()
        session.undo(&command)
        #expect(!command.output.hasResult)
        #expect(command.output.hasDeletionRange)
        #expect(command.output.deletionRange.offset == -5)
        #expect(command.output.deletionRange.length == 5)
        expectSingleSegment("あい", command)
        #expect(command.output.candidateWindow.size == 2)
        #expect(session.context.state == .composition)
      }
    }
  }

  @Test func requestUndo() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      let sessionPeer = SessionTestPeer(session)

      // It is OK not to check ImeContext::DIRECT because you cannot
      // assign any key event to Undo command in DIRECT mode.
      // See "session/keymap_interface.h".

      f.initSessionToPrecomposition(session)
      #expect(
        tryUndoAndAssertDoNothing(session) == nil,
        "When the UNDO context is empty and the context state is ImeContext::PRECOMPOSITION, UNDO command should be ignored. See b/5553298."
      )

      f.initSessionToPrecomposition(session)
      f.setUndoContext(session, converter)
      #expect(tryUndoAndAssertSuccess(session) == nil)

      f.initSessionToPrecomposition(session)
      f.setUndoContext(session, converter)
      sessionPeer.context.state = .composition
      #expect(tryUndoAndAssertSuccess(session) == nil)

      f.initSessionToPrecomposition(session)
      f.setUndoContext(session, converter)
      sessionPeer.context.state = .conversion
      #expect(tryUndoAndAssertSuccess(session) == nil)
    }
  }

  @Test func undoForSingleSegment() throws {
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

      var command = Command()
      let segments = Segments()

      do {  // Create segments
        f.insertCharacterChars("aiueo", session, &command)
        f.setAiueo(segments)
        // Don't use FillT13Ns(). It makes platform dependent segments.
        // TODO(hsumita): Makes FillT13Ns() independent from platforms.
        addValue(segments.mutableSegment(0), "aiueo")
        addValue(segments.mutableSegment(0), "AIUEO")
      }

      do {  // Undo after commitment of composition
        converter.setStartConversion(segments, true)
        command = Command()
        session.convert(&command)
        #expect(!command.output.hasResult)
        expectPreedit("あいうえお", command)

        converter.setCommitSegmentValue(segments, true)
        command = Command()
        session.commit(&command)
        #expect(!command.output.hasPreedit)
        expectResult("あいうえお", command)

        command = Command()
        session.undo(&command)
        #expect(!command.output.hasResult)
        #expect(command.output.hasDeletionRange)
        #expect(command.output.deletionRange.offset == -5)
        #expect(command.output.deletionRange.length == 5)
        expectPreedit("あいうえお", command)

        // Undo twice - do nothing and keep the previous status.
        command = Command()
        session.undo(&command)
        #expect(!command.output.hasResult)
        #expect(!command.output.hasDeletionRange)
        expectPreedit("あいうえお", command)
      }

      do {  // Undo after commitment of conversion
        command = Command()
        session.convertNext(&command)
        #expect(!command.output.hasResult)
        expectPreedit("アイウエオ", command)

        converter.setCommitSegmentValue(segments, true)
        command = Command()
        session.commit(&command)
        #expect(!command.output.hasPreedit)
        expectResult("アイウエオ", command)

        command = Command()
        session.undo(&command)
        #expect(!command.output.hasResult)
        #expect(command.output.hasDeletionRange)
        #expect(command.output.deletionRange.offset == -5)
        #expect(command.output.deletionRange.length == 5)
        expectPreedit("アイウエオ", command)

        // Undo twice - do nothing and keep the previous status.
        command = Command()
        session.undo(&command)
        #expect(!command.output.hasResult)
        #expect(!command.output.hasDeletionRange)
        expectPreedit("アイウエオ", command)
      }

      do {  // Undo after commitment of conversion with Ctrl-Backspace.
        command = Command()
        session.convertNext(&command)
        #expect(!command.output.hasResult)
        expectPreedit("aiueo", command)

        converter.setCommitSegmentValue(segments, true)
        command = Command()
        session.commit(&command)
        #expect(!command.output.hasPreedit)
        expectResult("aiueo", command)

        command = Command()
        session.undo(&command)
        #expect(!command.output.hasResult)
        #expect(command.output.hasDeletionRange)
        #expect(command.output.deletionRange.offset == -5)
        #expect(command.output.deletionRange.length == 5)
        expectPreedit("aiueo", command)
      }

      do {
        // If capability does not support DELETE_PRECEDIGN_TEXT, Undo is not
        // performed.
        converter.setCommitSegmentValue(segments, true)
        command = Command()
        session.commit(&command)
        #expect(!command.output.hasPreedit)
        expectResult("aiueo", command)

        // Reset capability
        capability = Genmai_Commands_Capability()
        session.setClientCapability(capability)

        command = Command()
        session.undo(&command)
        #expect(!command.output.hasResult)
        #expect(!command.output.hasDeletionRange)
        #expect(!command.output.hasPreedit)
      }
    }
  }

  @Test func clearUndoContextByKeyEventIssue5529702() throws {
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

      f.setUndoContext(session, converter)

      var command = Command()

      // Modifier key event does not clear undo context.
      sendKey("Shift", session, &command)

      // Ctrl+BS should be consumed as UNDO.
      setSendKeyCommand("Ctrl Backspace", &command)
      command.input.config.sessionKeymap = .msime
      session.testSendKey(&command)
      #expect(command.output.consumed)

      // Any other (test) send key event clears undo context.
      testSendKey("LEFT", session, &command)
      #expect(!command.output.consumed)

      // Undo context is just cleared. Ctrl+BS should not be consumed b/5553298.
      setSendKeyCommand("Ctrl Backspace", &command)
      command.input.config.sessionKeymap = .msime
      session.testSendKey(&command)
      #expect(!command.output.consumed)
    }
  }

  /// Segments "key1".."key3" with candidates "candN-1" / "candN-2".
  private func makeKey123Segments() -> Segments {
    let segments = Segments()
    _ = addSegment(segments, "key1", ["cand1-1", "cand1-2"])
    _ = addSegment(segments, "key2", ["cand2-1", "cand2-2"])
    _ = addSegment(segments, "key3", ["cand3-1", "cand3-2"])
    return segments
  }

  private func setTypes(_ segments: Segments, _ types: [Segment.SegmentType]) {
    for (i, type) in types.enumerated() {
      segments.mutableSegment(i).setSegmentType(type)
    }
  }

  @Test func undoForMultipleSegments() throws {
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

      var command = Command()

      // Create segments
      f.insertCharacterChars("key1key2key3", session, &command)
      let segments = makeKey123Segments()

      do {  // Undo for CommitCandidate
        converter.setStartConversion(segments, true)
        command = Command()
        session.convert(&command)
        #expect(!command.output.hasResult)
        expectPreedit("cand1-1cand2-1cand3-1", command)
        #expect(session.context.state == .conversion)

        // CommitSegments() sets the first segment SUBMITTED.
        setTypes(segments, [.submitted, .free, .free])
        converter.setCommitSegments(segments, true)
        command = Command()
        command.input.command.id = 1
        session.commitCandidate(&command)
        expectPreedit("cand2-1cand3-1", command)
        expectResult("cand1-2", command)
        #expect(session.context.state == .conversion)

        command = Command()
        session.undo(&command)
        #expect(!command.output.hasResult)
        #expect(command.output.hasDeletionRange)
        #expect(command.output.deletionRange.offset == -7)
        #expect(command.output.deletionRange.length == 7)
        expectPreedit("cand1-1cand2-1cand3-1", command)
        #expect(session.context.state == .conversion)

        // Move to second segment and do the same thing.
        setTypes(segments, [.submitted, .submitted, .free])
        converter.setCommitSegments(segments, true)
        command = Command()
        session.segmentFocusRight(&command)
        command = Command()
        command.input.command.id = 1
        session.commitCandidate(&command)
        // "cand2-2" is focused
        expectPreedit("cand3-1", command)
        expectResult("cand1-1cand2-2", command)
        #expect(session.context.state == .conversion)

        command = Command()
        session.undo(&command)
        #expect(!command.output.hasResult)
        #expect(command.output.hasDeletionRange)
        #expect(command.output.deletionRange.offset == -14)
        #expect(command.output.deletionRange.length == 14)
        // "cand2-1" is focused
        expectPreedit("cand1-1cand2-1cand3-1", command)
        #expect(session.context.state == .conversion)
      }
      do {  // Undo for CommitSegment
        setTypes(segments, [.free, .free, .free])
        converter.setStartConversion(segments, true)
        command = Command()
        session.convert(&command)
        #expect(!command.output.hasResult)
        expectPreedit("cand1-1cand2-1cand3-1", command)
        #expect(session.context.state == .conversion)

        command = Command()
        session.convertNext(&command)
        #expect(getComposition(command) == "cand1-2cand2-1cand3-1")
        command = Command()
        setTypes(segments, [.submitted, .free, .free])
        converter.setCommitSegments(segments, true)
        session.commitSegment(&command)
        expectPreedit("cand2-1cand3-1", command)
        expectResult("cand1-2", command)
        #expect(session.context.state == .conversion)

        command = Command()
        session.undo(&command)
        #expect(!command.output.hasResult)
        #expect(command.output.hasDeletionRange)
        #expect(command.output.deletionRange.offset == -7)
        #expect(command.output.deletionRange.length == 7)
        expectPreedit("cand1-2cand2-1cand3-1", command)
        #expect(session.context.state == .conversion)

        // Move to third segment and do the same thing.
        command = Command()
        session.segmentFocusRight(&command)
        command = Command()
        session.segmentFocusRight(&command)
        command = Command()
        session.convertNext(&command)
        expectPreedit("cand1-1cand2-1cand3-2", command)
        command = Command()
        setTypes(segments, [.submitted, .free, .free])
        converter.setCommitSegments(segments, true)
        // "cand3-2" is focused, but once CommitSegment() runs, which commits
        // the first segment (Ctrl + N on MS-IME),
        // the last segment goes back to the initial candidate ("cand3-1").
        session.commitSegment(&command)
        expectPreedit("cand2-1cand3-1", command)
        expectResult("cand1-1", command)
        #expect(session.context.state == .conversion)

        command = Command()
        session.undo(&command)
        #expect(!command.output.hasResult)
        #expect(command.output.hasDeletionRange)
        #expect(command.output.deletionRange.offset == -7)
        #expect(command.output.deletionRange.length == 7)
        // "cand3-2" is focused
        expectPreedit("cand1-1cand2-1cand3-2", command)
        #expect(session.context.state == .conversion)
      }
    }
  }

  @Test func undoForCommittedBracketPairIssue284235847() throws {
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

      var command = Command()
      let segments = Segments()

      do {  // Create segments
        f.insertCharacterChars("あかっこ", session, &command)
        _ = addSegment(segments, "あ", ["あ"])
        _ = addSegment(segments, "かっこ", ["かっこ", "（）"])
      }

      do {  // Commit 1st and 2nd segment
        converter.setStartConversion(segments, true)
        command = Command()
        session.convert(&command)
        // -> preedit: "あかっこ", result: empty, state: CONVERSION

        // CommitSegments() sets the first segment SUBMITTED.
        setTypes(segments, [.submitted, .free])
        // WillOnce: the second CommitCandidate hits the default action (false).
        var commitSegmentsCalled = false
        let copy = segments.copy()
        converter.commitSegmentsHandler = { out, _ in
          if commitSegmentsCalled { return false }
          commitSegmentsCalled = true
          out.assign(from: copy)
          return true
        }
        command = Command()
        command.input.command.id = 1
        session.commitCandidate(&command)
        // -> preedit: "かっこ", result: "あ", state: CONVERSION

        // Move to second segment and do the same thing.
        command = Command()
        session.segmentFocusRight(&command)
        command = Command()
        command.input.command.id = 1
        session.commitCandidate(&command)
        // -> preedit: empty, result: "（）", state: PRECOMPOSITION
      }

      do {  // Undo for 2nd segment (ie. bracket pair)
        command = Command()
        session.undo(&command)
        #expect(!command.output.hasResult)
        #expect(command.output.hasDeletionRange)
        #expect(command.output.deletionRange.offset == -1)
        #expect(command.output.deletionRange.length == 2)
        expectPreedit("かっこ", command)
        #expect(session.context.state == .conversion)
      }
    }
  }

  @Test func multipleUndo() throws {
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

      var command = Command()

      // Create segments
      f.insertCharacterChars("key1key2key3", session, &command)
      let segments = makeKey123Segments()

      converter.setStartConversion(segments, true)
      command = Command()
      session.convert(&command)
      #expect(!command.output.hasResult)
      expectPreedit("cand1-1cand2-1cand3-1", command)
      #expect(session.context.state == .conversion)

      // Commit 1st and 2nd segment
      setTypes(segments, [.submitted, .free, .free])
      converter.setCommitSegments(segments, true)
      command = Command()
      command.input.command.id = 1
      session.commitCandidate(&command)
      expectPreedit("cand2-1cand3-1", command)
      expectResult("cand1-2", command)
      setTypes(segments, [.submitted, .submitted, .free])
      converter.setCommitSegments(segments, true)
      command = Command()
      command.input.command.id = 1
      session.commitCandidate(&command)
      expectPreedit("cand3-1", command)
      expectResult("cand2-2", command)
      #expect(session.context.state == .conversion)

      // Undo to revive 2nd commit.
      command = Command()
      session.undo(&command)
      #expect(!command.output.hasResult)
      #expect(command.output.hasDeletionRange)
      #expect(command.output.deletionRange.offset == -7)
      #expect(command.output.deletionRange.length == 7)
      expectPreedit("cand2-1cand3-1", command)
      #expect(session.context.state == .conversion)

      // Try undoing against the 1st commit.
      command = Command()
      session.undo(&command)
      #expect(!command.output.hasResult)
      #expect(command.output.hasDeletionRange)
      #expect(command.output.deletionRange.offset == -7)
      #expect(command.output.deletionRange.length == 7)
      expectPreedit("cand1-1cand2-1cand3-1", command)
      #expect(session.context.state == .conversion)

      // No further undo available.
      command = Command()
      session.undo(&command)
      #expect(!command.output.hasResult)
      #expect(!command.output.hasDeletionRange)
    }
  }

  /// SetAiueo + "aiueo" / "AIUEO" candidates (no FillT13Ns).
  private func makeAiueoWithAscii(_ f: SessionTestFixture) -> Segments {
    let segments = Segments()
    f.setAiueo(segments)
    addValue(segments.mutableSegment(0), "aiueo")
    addValue(segments.mutableSegment(0), "AIUEO")
    return segments
  }

  @Test func undoOrRewindUndo() throws {
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

      // Commit twice.
      for _ in 0..<2 {
        var command = Command()
        f.insertCharacterChars("aiueo", session, &command)
        let segments = makeAiueoWithAscii(f)
        do {
          converter.setStartConversion(segments, true)
          command = Command()
          session.convert(&command)
          #expect(!command.output.hasResult)
          expectPreedit("あいうえお", command)

          converter.setCommitSegmentValue(segments, true)
          command = Command()
          session.commit(&command)
          #expect(!command.output.hasPreedit)
          expectResult("あいうえお", command)
        }
      }
      // Try UndoOrRewind twice.
      // Second trial should not consume the event. Echoback is expected.
      var command = Command()
      session.undoOrRewind(&command)
      #expect(!command.output.hasResult)
      expectPreedit("あいうえお", command)
      #expect(command.output.hasDeletionRange)
      command = Command()
      session.undoOrRewind(&command)
      #expect(!command.output.hasResult)
      #expect(!command.output.hasPreedit)
      #expect(!command.output.hasDeletionRange)
      #expect(!command.output.consumed)
    }
  }

  @Test func undoOrRewindRewind() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session, f.mobileRequest)

      do {  // Commit something. It's expected that Undo is not triggered later.
        var command = Command()
        f.insertCharacterChars("aiueo", session, &command)
        let segments = makeAiueoWithAscii(f)

        converter.setStartConversion(segments, true)
        command = Command()
        session.convert(&command)
        #expect(!command.output.hasResult)
        expectPreedit("あいうえお", command)

        converter.setCommitSegmentValue(segments, true)
        command = Command()
        session.commit(&command)
        #expect(!command.output.hasPreedit)
        expectResult("あいうえお", command)
      }

      let segments = Segments()
      do {
        let segment = segments.addSegment()
        addCandidate("e", "e", segment)
        addCandidate("e", "E", segment)
      }
      converter.setStartPrediction(segments, true)

      var command = Command()
      f.insertCharacterChars("11111", session, &command)
      #expect(!command.output.hasResult)
      expectPreedit("お", command)
      #expect(!command.output.hasDeletionRange)
      #expect(command.output.hasAllCandidateWords)

      command = Command()
      session.undoOrRewind(&command)
      #expect(!command.output.hasResult)
      expectPreedit("え", command)
      #expect(!command.output.hasDeletionRange)
      #expect(command.output.hasAllCandidateWords)
    }
  }

  @Test func stopKeyToggling() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session, f.mobileRequest)

      let segments = Segments()
      do {
        let segment = segments.addSegment()
        addCandidate("placeholder", "PLACEHOLDER", segment)
      }

      // StartPrediction() is called twice in InsertChararcterChars(),
      // but it is not called in StopKeyToggling().
      var startPredictionCount = 0
      let copy = segments.copy()
      converter.startPredictionHandler = { _, out in
        startPredictionCount += 1
        out.assign(from: copy)
        return true
      }

      var command = Command()
      f.insertCharacterChars("1", session, &command)
      expectPreedit("あ", command)
      #expect(command.output.allCandidateWords.candidates.count == 1)

      command = Command()
      session.stopKeyToggling(&command)
      #expect(command.output.allCandidateWords.candidates.count == 1)

      command = Command()
      f.insertCharacterChars("1", session, &command)
      expectPreedit("ああ", command)
      #expect(command.output.allCandidateWords.candidates.count == 1)
      #expect(startPredictionCount == 2)
    }
  }

  @Test func commitRawText() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      do {  // From composition mode.
        let session = Session(engine)
        f.initSessionToPrecomposition(session)
        var command = Command()
        f.insertCharacterChars("abc", session, &command)
        #expect(session.context.state == .composition)

        let segments = Segments()
        do {  // Initialize segments.
          _ = addSegment(segments, "あｂｃ", ["あべし"])
        }

        command = Command()
        setSendCommandCommand(.commitRawText, &command)
        session.sendCommand(&command)
        expectResultAndKey("abc", "abc", command)
        #expect(session.context.state == .precomposition)
        converter.clear()
      }
      do {  // From conversion mode.
        let session = Session(engine)
        f.initSessionToPrecomposition(session)
        var command = Command()
        f.insertCharacterChars("abc", session, &command)
        #expect(session.context.state == .composition)

        let segments = Segments()
        do {  // Initialize segments.
          _ = addSegment(segments, "あｂｃ", ["あべし"])
        }

        let request = f.createConversionRequest(session)
        f.fillT13Ns(request, segments)
        converter.setStartConversion(segments, true)
        command = Command()
        session.convert(&command)
        expectPreedit("あべし", command)
        #expect(session.context.state == .conversion)

        command = Command()
        setSendCommandCommand(.commitRawText, &command)
        session.sendCommand(&command)
        expectResultAndKey("abc", "abc", command)
        #expect(session.context.state == .precomposition)
        converter.clear()
      }
    }
  }

  @Test func commitRawTextKanaInput() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let table = Table()
      table.addRule("す゛", "ず", "")

      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      session.withInternalComposerOnlyForUnittest { $0.setTable(table) }
      f.initSessionToPrecomposition(session)

      var command = Command()
      setSendKeyCommand("m", &command)
      command.input.key.keyString = "も"
      session.sendKey(&command)

      setSendKeyCommand("r", &command)
      command.input.key.keyString = "す"
      session.sendKey(&command)

      setSendKeyCommand("@", &command)
      command.input.key.keyString = "゛"
      session.sendKey(&command)

      setSendKeyCommand("h", &command)
      command.input.key.keyString = "く"
      session.sendKey(&command)

      setSendKeyCommand("!", &command)
      command.input.key.keyString = "!"
      session.sendKey(&command)

      #expect(command.output.preedit.segment.first?.value == "もずく！")

      command = Command()
      setSendCommandCommand(.commitRawText, &command)
      session.sendCommand(&command)
      expectResultAndKey("mr@h!", "mr@h!", command)
      #expect(session.context.state == .precomposition)
    }
  }

  @Test func convertNextPagePrevPage() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      var command = Command()

      f.initSessionToPrecomposition(session)

      // Should be ignored in precomposition state.
      do {
        command = Command()
        command.input.type = .sendCommand
        command.input.command.type = .convertNextPage
        try #require(session.sendCommand(&command))
        #expect(command.output.consumed)

        command = Command()
        command.input.type = .sendCommand
        command.input.command.type = .convertPrevPage
        try #require(session.sendCommand(&command))
        #expect(command.output.consumed)
      }

      f.insertCharacterChars("aiueo", session, &command)
      expectPreedit("あいうえお", command)

      // Should be ignored in composition state.
      do {
        command = Command()
        command.input.type = .sendCommand
        command.input.command.type = .convertNextPage
        try #require(session.sendCommand(&command))
        #expect(command.output.consumed)
        expectPreedit("あいうえお", command)  // should do nothing

        command = Command()
        command.input.type = .sendCommand
        command.input.command.type = .convertPrevPage
        try #require(session.sendCommand(&command))
        #expect(command.output.consumed)
        expectPreedit("あいうえお", command)  // should do nothing
      }

      // Generate sequential candidates as follows.
      //   "page0-cand0" ... "page2-cand8"
      do {
        let segments = Segments()
        let segment = segments.addSegment()
        segment.setKey("あいうえお")
        for pageIndex in 0..<3 {
          for candIndex in 0..<9 {
            segment.addCandidate().value = "page\(pageIndex)-cand\(candIndex)"
          }
        }
        converter.setStartConversion(segments, true)
      }

      // Make sure the selected candidate changes as follows.
      //                              -> Convert
      //  -> "page0-cand0" -> SendCommand/CONVERT_NEXT_PAGE
      //  -> "page1-cand0" -> SendCommand/CONVERT_PREV_PAGE
      //  -> "page0-cand0" -> SendCommand/CONVERT_PREV_PAGE
      //  -> "page2-cand0"

      command = Command()
      try #require(session.convert(&command))
      expectPreedit("page0-cand0", command)

      command = Command()
      command.input.type = .sendCommand
      command.input.command.type = .convertNextPage
      try #require(session.sendCommand(&command))
      expectPreedit("page1-cand0", command)

      command = Command()
      command.input.type = .sendCommand
      command.input.command.type = .convertPrevPage
      try #require(session.sendCommand(&command))
      expectPreedit("page0-cand0", command)

      command = Command()
      command.input.type = .sendCommand
      command.input.command.type = .convertPrevPage
      try #require(session.sendCommand(&command))
      expectPreedit("page2-cand0", command)
    }
  }

  @Test func needlessClearUndoContext() throws {
    try withScopedSessionEnvironment {
      // This is a unittest against http://b/3423910.
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      // Undo requires capability DELETE_PRECEDING_TEXT.
      var capability = Genmai_Commands_Capability()
      capability.textDeletion = .deletePrecedingText
      session.setClientCapability(capability)
      var command = Command()

      do {  // Conversion -> Send Shift -> Undo
        let segments = Segments()
        f.insertCharacterChars("aiueo", session, &command)
        let request = f.createConversionRequest(session)
        f.setAiueo(segments)
        f.fillT13Ns(request, segments)

        converter.setStartConversion(segments, true)
        command = Command()
        session.convert(&command)
        #expect(!command.output.hasResult)
        expectPreedit("あいうえお", command)

        converter.setCommitSegmentValue(segments, true)
        command = Command()
        session.commit(&command)
        #expect(!command.output.hasPreedit)
        expectResult("あいうえお", command)

        sendKey("Shift", session, &command)
        #expect(!command.output.hasResult)
        #expect(!command.output.hasPreedit)

        command = Command()
        session.undo(&command)
        #expect(!command.output.hasResult)
        #expect(command.output.hasDeletionRange)
        #expect(command.output.deletionRange.offset == -5)
        #expect(command.output.deletionRange.length == 5)
        expectPreedit("あいうえお", command)
      }

      do {  // Type "aiueo" -> Convert -> Type "a" -> Escape -> Undo
        let segments = Segments()
        f.insertCharacterChars("aiueo", session, &command)
        let request = f.createConversionRequest(session)
        f.setAiueo(segments)
        f.fillT13Ns(request, segments)

        command = Command()
        session.convert(&command)
        #expect(!command.output.hasResult)
        expectPreedit("あいうえお", command)

        sendKey("a", session, &command)
        expectResult("あいうえお", command)
        expectSingleSegment("あ", command)

        sendKey("Escape", session, &command)
        #expect(!command.output.hasResult)
        #expect(!command.output.hasPreedit)

        command = Command()
        session.undo(&command)

        // Undo did nothing because the undo stack emptied by Escape event,
        // which modified the composition.
        #expect(!command.output.hasResult)
        #expect(!command.output.hasDeletionRange)
        #expect(!command.output.hasResult)
      }
    }
  }

  @Test func clearUndoContextAfterDirectInputAfterConversion() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      // Prepare Numpad
      var config = Genmai_Config_Config()
      config.numpadCharacterForm = .numpadDirectInput
      // Update KeyEventTransformer
      session.setConfig(config)

      // Undo requires capability DELETE_PRECEDING_TEXT.
      var capability = Genmai_Commands_Capability()
      capability.textDeletion = .deletePrecedingText
      session.setClientCapability(capability)
      var command = Command()

      // Cleate segments
      let segments = Segments()
      f.insertCharacterChars("aiueo", session, &command)
      let request = f.createConversionRequest(session)
      f.setAiueo(segments)
      f.fillT13Ns(request, segments)

      // Convert
      converter.setStartConversion(segments, true)
      command = Command()
      session.convert(&command)
      #expect(!command.output.hasResult)
      expectPreedit("あいうえお", command)
      // Direct input
      sendKey("Numpad0", session, &command)
      #expect(getComposition(command).isEmpty)
      expectResult("あいうえお0", command)

      // Undo - Do NOT nothing
      command = Command()
      session.undo(&command)
      #expect(!command.output.hasResult)
      #expect(!command.output.hasDeletionRange)
      #expect(!command.output.hasPreedit)
    }
  }

  @Test func temporaryCompositionModeAfterUndo() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      // This is a unittest against http://b/3423599.
      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      // Undo requires capability DELETE_PRECEDING_TEXT.
      var capability = Genmai_Commands_Capability()
      capability.textDeletion = .deletePrecedingText
      session.setClientCapability(capability)
      var command = Command()

      // Shift + Ascii triggers temporary input mode switch.
      sendKey("A", session, &command)
      #expect(command.output.mode == .halfAscii)
      sendKey("Enter", session, &command)
      #expect(command.output.mode == .hiragana)

      // Undo and keep temporary input mode correct
      command = Command()
      session.undo(&command)
      #expect(command.output.mode == .halfAscii)
      #expect(!command.output.hasResult)
      expectPreedit("A", command)
      sendKey("Enter", session, &command)
      #expect(command.output.mode == .hiragana)

      // Undo and input additional "A" with temporary input mode.
      command = Command()
      session.undo(&command)
      #expect(command.output.mode == .halfAscii)
      sendKey("A", session, &command)
      #expect(!command.output.hasResult)
      expectPreedit("AA", command)
      #expect(command.output.mode == .halfAscii)

      // Input additional "a" with original input mode.
      sendKey("a", session, &command)
      #expect(command.output.mode == .hiragana)
      #expect(!command.output.hasResult)
      expectPreedit("AAあ", command)

      // Submit and Undo
      sendKey("Enter", session, &command)
      #expect(command.output.mode == .hiragana)
      command = Command()
      session.undo(&command)
      #expect(command.output.mode == .hiragana)
      #expect(!command.output.hasResult)
      expectPreedit("AAあ", command)

      // Input additional "Aa"
      sendKey("A", session, &command)
      sendKey("a", session, &command)
      #expect(!command.output.hasResult)
      expectPreedit("AAあAa", command)
      #expect(command.output.mode == .halfAscii)

      // Submit and Undo
      sendKey("Enter", session, &command)
      #expect(command.output.mode == .hiragana)
      command = Command()
      session.undo(&command)
      #expect(command.output.mode == .halfAscii)
      #expect(!command.output.hasResult)
      expectPreedit("AAあAa", command)
    }
  }

  @Test func dcheckFailureAfterUndo() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      // This is a unittest against http://b/3437358.
      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var capability = Genmai_Commands_Capability()
      capability.textDeletion = .deletePrecedingText
      session.setClientCapability(capability)
      var command = Command()

      f.insertCharacterChars("abe", session, &command)
      command = Command()
      session.commit(&command)
      command = Command()
      session.undo(&command)
      #expect(!command.output.hasResult)
      expectPreedit("あべ", command)

      f.insertCharacterChars("s", session, &command)
      #expect(!command.output.hasResult)
      expectPreedit("あべｓ", command)

      f.insertCharacterChars("h", session, &command)
      #expect(!command.output.hasResult)
      expectPreedit("あべｓｈ", command)

      f.insertCharacterChars("i", session, &command)
      #expect(!command.output.hasResult)
      expectPreedit("あべし", command)
    }
  }

  @Test func convertToFullOrHalfAlphanumericAfterUndo() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      // This is a unittest against http://b/3423592.
      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      // Undo requires capability DELETE_PRECEDING_TEXT.
      var capability = Genmai_Commands_Capability()
      capability.textDeletion = .deletePrecedingText
      session.setClientCapability(capability)

      let segments = Segments()
      f.setAiueo(segments)
      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)

      do {  // ConvertToHalfASCII
        var command = Command()
        f.insertCharacterChars("aiueo", session, &command)

        sendKey("Enter", session, &command)
        command = Command()
        session.undo(&command)
        #expect(!command.output.hasResult)
        try #require(command.output.hasPreedit)
        #expect(getComposition(command) == "あいうえお")

        converter.setStartConversion(segments, true)
        command = Command()
        session.convertToHalfASCII(&command)
        #expect(!command.output.hasResult)
        try #require(command.output.hasPreedit)
        #expect(getComposition(command) == "aiueo")
        converter.clear()
      }

      do {  // ConvertToFullASCII
        var command = Command()
        f.insertCharacterChars("aiueo", session, &command)

        sendKey("Enter", session, &command)
        command = Command()
        session.undo(&command)
        #expect(!command.output.hasResult)
        try #require(command.output.hasPreedit)
        #expect(getComposition(command) == "あいうえお")

        converter.setStartConversion(segments, true)
        command = Command()
        session.convertToFullASCII(&command)
        #expect(!command.output.hasResult)
        try #require(command.output.hasPreedit)
        #expect(getComposition(command) == "ａｉｕｅｏ")
        converter.clear()
      }
    }
  }

  @Test func composeVoicedSoundMarkAfterUndoIssue5369632() throws {
    try withScopedSessionEnvironment {
      // This is a unittest against http://b/5369632.
      let f = try SessionTestFixture()
      var config = Genmai_Config_Config()
      config.preeditMethod = .kana

      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      session.setConfig(config)
      f.initSessionToPrecomposition(session)

      // Undo requires capability DELETE_PRECEDING_TEXT.
      var capability = Genmai_Commands_Capability()
      capability.textDeletion = .deletePrecedingText
      session.setClientCapability(capability)

      var command = Command()

      insertCharacterCodeAndString("a", "ち", session, &command)
      #expect(getComposition(command) == "ち")

      sendKey("Enter", session, &command)
      command = Command()
      session.undo(&command)

      #expect(!command.output.hasResult)
      try #require(command.output.hasPreedit)
      #expect(getComposition(command) == "ち")

      insertCharacterCodeAndString("@", "゛", session, &command)
      #expect(!command.output.hasResult)
      try #require(command.output.hasPreedit)
      #expect(getComposition(command) == "ぢ")
    }
  }

  @Test func spaceOnAlphanumeric() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      var request = Genmai_Commands_Request()
      var command = Command()

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      _ = Session(engine)
      do {
        request.spaceOnAlphanumeric = .commit

        let session = Session(engine)
        f.initSessionToPrecomposition(session, request)

        sendKey("A", session, &command)
        #expect(getComposition(command) == "A")

        sendKey("Space", session, &command)
        expectResult("A ", command)
        converter.clear()
      }

      do {
        request.spaceOnAlphanumeric = .spaceOrConvertCommittingComposition

        let session = Session(engine)
        f.initSessionToPrecomposition(session, request)

        sendKey("A", session, &command)
        #expect(getComposition(command) == "A")

        sendKey("Space", session, &command)
        #expect(!command.output.hasResult)
        #expect(getComposition(command) == "A ")

        sendKey("a", session, &command)
        expectResult("A ", command)
        #expect(getComposition(command) == "あ")
        converter.clear()
      }

      do {
        request.spaceOnAlphanumeric = .spaceOrConvertKeepingComposition

        let session = Session(engine)
        f.initSessionToPrecomposition(session, request)

        sendKey("A", session, &command)
        #expect(getComposition(command) == "A")

        sendKey("Space", session, &command)
        #expect(!command.output.hasResult)
        #expect(getComposition(command) == "A ")

        sendKey("a", session, &command)
        #expect(!command.output.hasResult)
        #expect(getComposition(command) == "A a")
        converter.clear()
      }
    }
  }

  @Test func issue1805239() throws {
    try withScopedSessionEnvironment {
      // This is a unittest against http://b/1805239.
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Command()
      f.insertCharacterChars("watasinonamae", session, &command)

      let segments = Segments()
      _ = addSegment(segments, "わたしの", ["私の", "渡しの"])
      _ = addSegment(segments, "名前", ["なまえ", "ナマエ"])

      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      sendSpecialKey(.space, session, &command)
      sendSpecialKey(.right, session, &command)
      sendSpecialKey(.space, session, &command)
      #expect(command.output.hasCandidateWindow)

      sendSpecialKey(.left, session, &command)
      #expect(!command.output.hasCandidateWindow)

      sendSpecialKey(.right, session, &command)
      #expect(!command.output.hasCandidateWindow)

      sendSpecialKey(.space, session, &command)
      #expect(command.output.hasCandidateWindow)

      sendSpecialKey(.space, session, &command)
      #expect(command.output.hasCandidateWindow)

      sendSpecialKey(.space, session, &command)
      #expect(command.output.hasCandidateWindow)

      sendSpecialKey(.space, session, &command)
      #expect(command.output.hasCandidateWindow)
    }
  }

  @Test func issue1816861() throws {
    try withScopedSessionEnvironment {
      // This is a unittest against http://b/1816861
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Command()
      f.insertCharacterChars("kamabokonoinbou", session, &command)
      let segments = Segments()
      _ = addSegment(segments, "かまぼこの", ["かまぼこの", "カマボコの"])
      _ = addSegment(segments, "いんぼう", ["陰謀", "印房"])

      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      sendSpecialKey(.space, session, &command)
      sendSpecialKey(.right, session, &command)
      sendSpecialKey(.space, session, &command)
      sendSpecialKey(.backspace, session, &command)
      sendSpecialKey(.left, session, &command)
      sendSpecialKey(.left, session, &command)
      sendSpecialKey(.left, session, &command)
      sendSpecialKey(.left, session, &command)
      sendSpecialKey(.backspace, session, &command)
      sendSpecialKey(.backspace, session, &command)
      sendSpecialKey(.backspace, session, &command)
      sendSpecialKey(.backspace, session, &command)
      sendSpecialKey(.backspace, session, &command)

      segments.clear()
      _ = addSegment(segments, "いんぼう", ["陰謀", "陰謀論", "陰謀説"])

      converter.setStartPredictionWithPreviousSuggestion(segments, true)

      sendSpecialKey(.tab, session, &command)
    }
  }

  @Test func t13NWithResegmentation() throws {
    try withScopedSessionEnvironment {
      // This is a unittest against http://b/3272827
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Command()
      f.insertCharacterChars("kamabokonoinbou", session, &command)

      do {
        let segments = Segments()
        _ = addSegment(segments, "かまぼこの", ["かまぼこの", "カマボコの"])
        _ = addSegment(segments, "いんぼう", ["陰謀", "印房"])
        let request = f.createConversionRequest(session)
        f.fillT13Ns(request, segments)
        converter.setStartConversion(segments, true)
      }
      do {
        let segments = Segments()
        _ = addSegment(segments, "かまぼこの", ["かまぼこの", "カマボコの"])
        _ = addSegment(segments, "いんぼ", ["いんぼ", "インボ"])
        _ = addSegment(segments, "う", ["ウ", "卯"])

        let request = f.createConversionRequest(session)
        f.fillT13Ns(request, segments)
        converter.setResizeSegment(segments, true)
      }

      // Start conversion
      sendSpecialKey(.space, session, &command)
      // Select second segment
      sendSpecialKey(.right, session, &command)
      // Shrink segment
      sendKey("Shift left", session, &command)
      // Convert to T13N (Half katakana)
      sendKey("F8", session, &command)

      try #require(command.output.preedit.segment.count > 1)
      #expect(command.output.preedit.segment[1].value == "ｲﾝﾎﾞ")
    }
  }

  @Test func shortcut() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let kDataShortcut: [Genmai_Config_Config.SelectionShortcut] = [
        .noShortcut,
        .shortcut123456789,
        .shortcutAsdfghjkl,
      ]
      let kDataExpected: [[String]] = [
        ["", ""],
        ["1", "2"],
        ["a", "s"],
      ]
      for i in 0..<kDataShortcut.count {
        let shortcut = kDataShortcut[i]
        let expected = kDataExpected[i]

        var config = Genmai_Config_Config()
        config.selectionShortcut = shortcut

        let engine = MockEngine()
        let converter = f.createEngineConverterMock(engine)

        let session = Session(engine)
        session.setConfig(config)
        f.initSessionToPrecomposition(session)

        let segments = Segments()
        f.setAiueo(segments)
        let context = session.context
        let request = ConversionRequestBuilder()
          .setComposer(context.composer)
          .setRequestView(context.getRequest())
          .setContextView(context.clientContext)
          .setConfigView(context.getConfig())
          .build()
        f.fillT13Ns(request, segments)
        converter.setStartConversion(segments, true)

        var command = Command()
        f.insertCharacterChars("aiueo", session, &command)

        command = Command()
        session.convert(&command)

        command = Command()
        // Convert next
        sendSpecialKey(.space, session, &command)
        try #require(command.output.hasCandidateWindow)
        let candidateWindow = command.output.candidateWindow
        try #require(candidateWindow.candidate.count >= 2)
        #expect(candidateWindow.candidate[0].annotation.shortcut == expected[0])
        #expect(candidateWindow.candidate[1].annotation.shortcut == expected[1])
      }
    }
  }

  @Test func shortcutWithCapsLockIssue5655743() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      var config = Genmai_Config_Config()
      config.selectionShortcut = .shortcutAsdfghjkl

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      session.setConfig(config)
      f.initSessionToPrecomposition(session)

      let segments = Segments()
      f.setAiueo(segments)
      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      var command = Command()
      f.insertCharacterChars("aiueo", session, &command)

      command = Command()
      session.convert(&command)

      command = Command()
      // Convert next
      sendSpecialKey(.space, session, &command)
      try #require(command.output.hasCandidateWindow)

      let candidateWindow = command.output.candidateWindow
      try #require(candidateWindow.candidate.count >= 2)
      #expect(candidateWindow.candidate[0].annotation.shortcut == "a")
      #expect(candidateWindow.candidate[1].annotation.shortcut == "s")

      // Select the second candidate by 's' key when the CapsLock is enabled.
      // Note that "CAPS S" means that 's' key is pressed w/o shift key.
      // See the description in command.proto.
      #expect(sendKey("CAPS S", session, &command))
      #expect(command.output.consumed)
      #expect(getComposition(command) == "アイウエオ")
    }
  }

  @Test func shortcutFromVK() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      var config = Genmai_Config_Config()
      config.selectionShortcut = .shortcut123456789
      var clientRequest = Genmai_Commands_Request()
      clientRequest.specialRomanjiTable = .qwertyMobileToHiragana

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      session.setConfig(config)
      f.initSessionToPrecomposition(session, clientRequest)

      let segments = Segments()
      f.setAiueo(segments)
      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      converter.setStartConversion(segments, true)

      var command = Command()
      f.insertCharacterChars("aiueo", session, &command)

      command = Command()
      session.convert(&command)

      command = Command()
      // Convert next
      sendSpecialKey(.space, session, &command)
      try #require(command.output.hasCandidateWindow)

      let candidateWindow = command.output.candidateWindow
      try #require(candidateWindow.candidate.count >= 2)
      #expect(candidateWindow.candidate[0].annotation.shortcut == "1")
      #expect(candidateWindow.candidate[1].annotation.shortcut == "2")

      // Because the request has a special romaji table (== the event is from VK),
      // "1" must be treated not as shortcut selection but as character insertion.
      #expect(sendKey("1", session, &command))
      #expect(command.output.consumed)
      expectResult("アイウエオ", command)
      #expect(getComposition(command) == "１")
    }
  }
}
