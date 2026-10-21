// Port of mozc/src/session/session_test.cc (3.35.6354), part 3 (AutoConversion .. end).
//
// This file holds AutoConversion .. DedupAfterUndo; SessionTests4.swift holds
// MoveCursor .. the end of the C++ file.

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import Testing

@testable import GenmaiSession

/// segments_mo: "MO" -> MOCHA / MOZUKU (values only).
func makeSegmentsMo() -> Segments {
  let segments = Segments()
  let segment = segments.addSegment()
  segment.setKey("MO")
  segment.addCandidate().value = "MOCHA"
  segment.addCandidate().value = "MOZUKU"
  return segments
}

/// FindCandidateID
func findCandidateID(
  _ candidateWindow: Genmai_Commands_CandidateWindow, _ value: String, _ id: inout Int
) -> Bool {
  for candidate in candidateWindow.candidate where candidate.value == value {
    id = Int(candidate.id)
    return true
  }
  return false
}

/// FindCandidateIDs
func findCandidateIDs(
  _ candidateWindow: Genmai_Commands_CandidateWindow, _ value: String, _ ids: inout [Int]
) {
  ids.removeAll()
  for candidate in candidateWindow.candidate where candidate.value == value {
    ids.append(Int(candidate.id))
  }
}

/// `EXPECT_CALL(*converter, StartPrediction(_, _)).WillOnce(DoAll(SetArgPointee<1>(segments), Return(true)))`
/// After one call the handler falls back to the default action (false).
func setStartPredictionOnce(_ converter: MockConverter, _ segments: Segments) {
  let copy = Segments()
  copy.assign(from: segments)
  var used = false
  converter.startPredictionHandler = { _, out in
    if used { return false }
    used = true
    out.assign(from: copy)
    return true
  }
}

/// WillOnce variant for StartConversion.
func setStartConversionOnce(_ converter: MockConverter, _ segments: Segments) {
  let copy = Segments()
  copy.assign(from: segments)
  var used = false
  converter.startConversionHandler = { _, out in
    if used { return false }
    used = true
    out.assign(from: copy)
    return true
  }
}

/// A session with a KeyMapManager built from `config` (common pattern).
func makeSessionWithKeymap(_ engine: MockEngine, _ config: Genmai_Config_Config) -> Session {
  let session = Session(engine)
  let keyMapManager = KeyMapManager(config)
  session.setConfig(config)
  session.setKeyMapManager(keyMapManager)
  return session
}

func makeTable(_ request: Genmai_Commands_Request) -> Table {
  let table = Table()
  table.initializeWithRequestAndConfig(request, ConfigHandler.defaultConfig())
  return table
}

@Suite struct SessionTests3 {
  @Test func autoConversion() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let segments = Segments()
      f.setAiueo(segments)
      let defaultRequest = ConversionRequest()
      f.fillT13Ns(defaultRequest, segments)
      converter.setStartConversion(segments, true)

      // Auto Off
      var config = Genmai_Config_Config()
      config.useAutoConversion = false
      do {
        let session = Session(engine)
        session.setConfig(config)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()

        // The last "." is a triggering key for auto conversion
        f.insertCharacterChars("tesuto.", session, &command)

        expectSingleSegmentAndKey("てすと。", "てすと。", command)
      }
      do {
        let session = Session(engine)
        session.setConfig(config)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()

        // The last "." is a triggering key for auto conversion
        f.insertCharacterString("てすと。", "wrs/", session, &command)

        expectSingleSegmentAndKey("てすと。", "てすと。", command)
      }

      // Auto On
      config.useAutoConversion = true
      do {
        let session = Session(engine)
        session.setConfig(config)
        f.initSessionToPrecomposition(session)

        var command = Genmai_Commands_Command()

        // The last "." is a triggering key for auto conversion
        f.insertCharacterChars("tesuto.", session, &command)

        expectSingleSegmentAndKey("あいうえお", "あいうえお", command)
      }
      do {
        let session = Session(engine)
        session.setConfig(config)
        f.initSessionToPrecomposition(session)

        var command = Genmai_Commands_Command()

        // The last "." is a triggering key for auto conversion
        f.insertCharacterString("てすと。", "wrs/", session, &command)

        expectSingleSegmentAndKey("あいうえお", "あいうえお", command)
      }

      // Don't trigger auto conversion for the pattern number + "."
      do {
        let session = Session(engine)
        session.setConfig(config)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()

        // The last "." is a triggering key for auto conversion
        f.insertCharacterChars("123.", session, &command)

        expectSingleSegmentAndKey("１２３．", "１２３．", command)
      }

      // Don't trigger auto conversion for the ".."
      do {
        let session = Session(engine)
        session.setConfig(config)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()

        // The last "." is a triggering key for auto conversion
        f.insertCharacterChars("..", session, &command)

        expectSingleSegmentAndKey("。。", "。。", command)
      }

      do {
        let session = Session(engine)
        session.setConfig(config)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()

        // The last "." is a triggering key for auto conversion
        f.insertCharacterString("１２３。", "123.", session, &command)

        expectSingleSegmentAndKey("１２３．", "１２３．", command)
      }

      // Don't trigger auto conversion for "." only.
      do {
        let session = Session(engine)
        session.setConfig(config)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()

        // The last "." is a triggering key for auto conversion
        f.insertCharacterChars(".", session, &command)

        expectSingleSegmentAndKey("。", "。", command)
      }

      do {
        let session = Session(engine)
        session.setConfig(config)
        f.initSessionToPrecomposition(session)
        var command = Genmai_Commands_Command()

        // The last "." is a triggering key for auto conversion
        f.insertCharacterString("。", "/", session, &command)

        expectSingleSegmentAndKey("。", "。", command)
      }

      // Do auto conversion even if romanji-table is modified.
      do {
        let session = Session(engine)
        session.setConfig(config)
        f.initSessionToPrecomposition(session)

        // Modify romanji-table to convert "zz" -> "。"
        let zzTable = Table()
        _ = zzTable.addRule("te", "て", "")
        _ = zzTable.addRule("su", "す", "")
        _ = zzTable.addRule("to", "と", "")
        _ = zzTable.addRule("zz", "。", "")
        session.internalComposerOnlyForUnittest.setTable(zzTable)

        // The last "zz" is converted to "." and triggering key for auto conversion
        var command = Genmai_Commands_Command()
        f.insertCharacterChars("tesutozz", session, &command)

        expectSingleSegmentAndKey("あいうえお", "あいうえお", command)
      }

      do {
        let triggerKey: [Character] = [".", ",", "?", "!"]

        // try all possible patterns.
        for kanaMode in 0..<2 {
          for onoff in 0..<2 {
            for pattern in 0...16 {
              config.useAutoConversion = onoff != 0
              config.autoConversionKey = UInt32(pattern)

              var flag = [Int](repeating: 0, count: 4)
              flag[0] = Int(
                config.autoConversionKey
                  & UInt32(Genmai_Config_Config.AutoConversionKey.autoConversionKuten.rawValue))
              flag[1] = Int(
                config.autoConversionKey
                  & UInt32(Genmai_Config_Config.AutoConversionKey.autoConversionTouten.rawValue))
              flag[2] = Int(
                config.autoConversionKey
                  & UInt32(
                    Genmai_Config_Config.AutoConversionKey.autoConversionQuestionMark.rawValue))
              flag[3] = Int(
                config.autoConversionKey
                  & UInt32(
                    Genmai_Config_Config.AutoConversionKey.autoConversionExclamationMark.rawValue))

              for i in 0..<4 {
                let session = Session(engine)
                session.setConfig(config)
                f.initSessionToPrecomposition(session)
                var command = Genmai_Commands_Command()

                if kanaMode != 0 {
                  var key = "てすと"
                  key.append(triggerKey[i])
                  f.insertCharacterString(key, "wst/", session, &command)
                } else {
                  var key = "tesuto"
                  key.append(triggerKey[i])
                  f.insertCharacterChars(key, session, &command)
                }
                #expect(command.output.hasPreedit)
                #expect(command.output.preedit.segment.count == 1)
                guard command.output.preedit.segment.count >= 1 else { continue }
                #expect(command.output.preedit.segment[0].hasValue)
                #expect(command.output.preedit.segment[0].hasKey)

                if onoff > 0 && flag[i] > 0 {
                  #expect(command.output.preedit.segment[0].key == "あいうえお")
                } else {
                  // Not "あいうえお"
                  #expect(command.output.preedit.segment[0].key != "あいうえお")
                }
              }
            }
          }
        }
      }
    }
  }

  @Test func inputSpaceWithKatakanaMode() throws {
    try withScopedSessionEnvironment {
      // This is a unittest against http://b/3203944.
      // Input mode should not be changed when a space key is typed.
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Genmai_Commands_Command()
      #expect(session.compositionModeHiragana(&command))
      #expect(command.output.consumed)
      #expect(command.output.mode == .hiragana)

      setSendKeyCommand("Space", &command)
      command.input.key.mode = .fullKatakana
      #expect(session.sendKey(&command))
      #expect(command.output.consumed)
      expectResult("　", command)
      #expect(command.output.mode == .fullKatakana)
    }
  }

  @Test func alphanumericOfSSH() throws {
    try withScopedSessionEnvironment {
      // This is a unittest against http://b/3199626
      // 'ssh' (っｓｈ) + F10 should be 'ssh'.
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Genmai_Commands_Command()
      f.insertCharacterChars("ssh", session, &command)
      #expect(getComposition(command) == "っｓｈ")

      let segments = Segments()
      // Set a dummy segments for ConvertToHalfASCII.
      do {
        let segment = segments.addSegment()
        segment.setKey("っsh")

        segment.addCandidate().value = "[SSH]"
      }
      let request = f.createConversionRequest(session)
      f.fillT13Ns(request, segments)
      setStartConversionOnce(converter, segments)

      command = Genmai_Commands_Command()
      #expect(session.convertToHalfASCII(&command))
      expectSingleSegment("ssh", command)
    }
  }

  @Test func keitaiInputToggle() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      var config = Genmai_Config_Config()
      config.sessionKeymap = .msime

      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = makeSessionWithKeymap(engine, config)

      f.initSessionToPrecomposition(session, f.mobileRequest)
      var command = Genmai_Commands_Command()

      func preedit0() -> String {
        command.output.preedit.segment.first?.value ?? ""
      }

      sendKey("1", session, &command)
      // "あ|"
      #expect(preedit0() == "あ")
      #expect(command.output.preedit.cursor == 1)

      sendKey("1", session, &command)
      // "い|"
      #expect(preedit0() == "い")
      #expect(command.output.preedit.cursor == 1)

      for _ in 0..<9 {
        sendKey("1", session, &command)
      }
      #expect(preedit0() == "あ")
      #expect(command.output.preedit.cursor == 1)

      sendKey("2", session, &command)
      #expect(preedit0() == "あか")
      #expect(command.output.preedit.cursor == 2)

      sendKey("2", session, &command)
      #expect(preedit0() == "あき")
      #expect(command.output.preedit.cursor == 2)

      sendKey("*", session, &command)
      #expect(preedit0() == "あぎ")
      #expect(command.output.preedit.cursor == 2)

      sendKey("*", session, &command)
      #expect(preedit0() == "あき")
      #expect(command.output.preedit.cursor == 2)

      sendKey("3", session, &command)
      #expect(preedit0() == "あきさ")
      #expect(command.output.preedit.cursor == 3)

      sendSpecialKey(.right, session, &command)
      #expect(preedit0() == "あきさ")
      #expect(command.output.preedit.cursor == 3)

      sendKey("3", session, &command)
      #expect(preedit0() == "あきささ")
      #expect(command.output.preedit.cursor == 4)

      sendSpecialKey(.left, session, &command)
      #expect(preedit0() == "あきささ")
      #expect(command.output.preedit.cursor == 3)

      sendKey("4", session, &command)
      #expect(preedit0() == "あきさたさ")
      #expect(command.output.preedit.cursor == 4)

      sendSpecialKey(.left, session, &command)
      #expect(preedit0() == "あきさたさ")
      #expect(command.output.preedit.cursor == 3)

      sendKey("*", session, &command)
      #expect(preedit0() == "あきざたさ")
      #expect(command.output.preedit.cursor == 3)

      // Test for End key
      sendSpecialKey(.end, session, &command)
      sendKey("6", session, &command)
      sendKey("6", session, &command)
      sendSpecialKey(.end, session, &command)
      sendKey("6", session, &command)
      sendKey("*", session, &command)
      #expect(preedit0() == "あきざたさひば")
      #expect(command.output.preedit.cursor == 7)

      // Test for Right key
      sendSpecialKey(.end, session, &command)
      sendKey("6", session, &command)
      sendKey("6", session, &command)
      sendSpecialKey(.right, session, &command)
      sendKey("6", session, &command)
      sendKey("*", session, &command)
      #expect(preedit0() == "あきざたさひばひば")
      #expect(command.output.preedit.cursor == 9)

      // Test for Left key
      sendSpecialKey(.end, session, &command)
      sendKey("6", session, &command)
      sendKey("6", session, &command)
      #expect(preedit0() == "あきざたさひばひばひ")
      sendSpecialKey(.left, session, &command)
      sendKey("6", session, &command)
      #expect(preedit0() == "あきざたさひばひばはひ")
      sendKey("*", session, &command)
      #expect(preedit0() == "あきざたさひばひばばひ")
      #expect(command.output.preedit.cursor == 10)

      // Test for Home key
      sendSpecialKey(.home, session, &command)
      #expect(preedit0() == "あきざたさひばひばばひ")
      sendKey("6", session, &command)
      sendKey("*", session, &command)
      #expect(preedit0() == "ばあきざたさひばひばばひ")
      #expect(command.output.preedit.cursor == 1)

      sendSpecialKey(.end, session, &command)
      sendKey("5", session, &command)
      #expect(preedit0() == "ばあきざたさひばひばばひな")
      sendKey("*", session, &command)  // no effect
      #expect(preedit0() == "ばあきざたさひばひばばひな")
      #expect(command.output.preedit.cursor == 13)
    }
  }

  @Test func keitaiInputFlick() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      var config = Genmai_Config_Config()
      config.sessionKeymap = .msime
      var mobileRequest = f.mobileRequest
      mobileRequest.specialRomanjiTable = .twelveKeysToHiragana
      var command = Genmai_Commands_Command()

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      func preedit0() -> String {
        command.output.preedit.segment.first?.value ?? ""
      }

      do {
        let session = makeSessionWithKeymap(engine, config)
        f.initSessionToPrecomposition(session, mobileRequest)
        insertCharacterCodeAndString("6", "は", session, &command)
        insertCharacterCodeAndString("3", "し", session, &command)
        sendKey("*", session, &command)
        insertCharacterCodeAndString("3", "ょ", session, &command)
        insertCharacterCodeAndString("1", "う", session, &command)
        #expect(preedit0() == "はじょう")
        converter.clear()
      }

      do {
        let session = makeSessionWithKeymap(engine, config)
        f.initSessionToPrecomposition(session, mobileRequest)

        sendKey("6", session, &command)
        sendKey("3", session, &command)
        sendKey("3", session, &command)
        sendKey("*", session, &command)
        insertCharacterCodeAndString("3", "ょ", session, &command)
        insertCharacterCodeAndString("1", "う", session, &command)
        #expect(preedit0() == "はじょう")
        converter.clear()
      }

      do {
        let session = makeSessionWithKeymap(engine, config)
        f.initSessionToPrecomposition(session, mobileRequest)

        sendKey("1", session, &command)
        sendKey("2", session, &command)
        sendKey("3", session, &command)
        sendKey("3", session, &command)
        #expect(preedit0() == "あかし")
        insertCharacterCodeAndString("5", "の", session, &command)
        insertCharacterCodeAndString("2", "く", session, &command)
        insertCharacterCodeAndString("3", "し", session, &command)
        #expect(preedit0() == "あかしのくし")
        for _ in 0..<5 {
          sendSpecialKey(.left, session, &command)
        }
        for _ in 0..<8 {
          sendKey("9", session, &command)
        }
        sendSpecialKey(.right, session, &command)
        sendSpecialKey(.right, session, &command)
        insertCharacterCodeAndString("0", "ん", session, &command)
        sendSpecialKey(.end, session, &command)
        sendKey("1", session, &command)
        sendKey("1", session, &command)
        sendKey("1", session, &command)
        sendKey("*", session, &command)
        sendSpecialKey(.left, session, &command)
        insertCharacterCodeAndString("8", "ゆ", session, &command)
        sendKey("*", session, &command)
        sendSpecialKey(.right, session, &command)
        sendKey("*", session, &command)
        sendKey("*", session, &command)
        #expect(preedit0() == "あるかしんのくしゅう")
        sendSpecialKey(.home, session, &command)
        sendSpecialKey(.right, session, &command)
        sendSpecialKey(.right, session, &command)
        insertCharacterCodeAndString("6", "は", session, &command)
        for _ in 0..<5 {
          sendKey("*", session, &command)
        }
        for _ in 0..<4 {
          sendSpecialKey(.right, session, &command)
        }
        sendKey("6", session, &command)
        sendKey("6", session, &command)
        sendKey("6", session, &command)
        #expect(preedit0() == "あるぱかしんのふくしゅう")
        converter.clear()
      }
    }
  }

  @Test func toggleFlick() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      var config = Genmai_Config_Config()
      config.sessionKeymap = .msime
      var mobileRequest = f.mobileRequest
      mobileRequest.specialRomanjiTable = .toggleFlickToHiragana
      var command = Genmai_Commands_Command()

      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      func preedit0() -> String {
        command.output.preedit.segment.first?.value ?? ""
      }

      do {
        let session = makeSessionWithKeymap(engine, config)
        f.initSessionToPrecomposition(session, mobileRequest)
        f.insertCharacterChars("6d*888888;", session, &command)
        #expect(preedit0() == "はじょう")
        converter.clear()
      }
      do {
        let session = makeSessionWithKeymap(engine, config)
        f.initSessionToPrecomposition(session, mobileRequest)

        f.insertCharacterChars("1233", session, &command)  // Toggle
        #expect(preedit0() == "あかし")
        #expect(command.output.preedit.isToggleable)

        f.insertCharacterChars("%bd", session, &command)  // Flick
        #expect(preedit0() == "あかしのくし")
        #expect(!command.output.preedit.isToggleable)
        #expect(command.output.preedit.cursor == 6)

        sendSpecialKey(.left, session, &command)
        #expect(!command.output.preedit.isToggleable)
        #expect(command.output.preedit.cursor == 5)

        sendSpecialKey(.left, session, &command)
        sendSpecialKey(.left, session, &command)
        sendSpecialKey(.left, session, &command)
        sendSpecialKey(.left, session, &command)
        #expect(command.output.preedit.cursor == 1)
        #expect(!command.output.preedit.isToggleable)

        f.insertCharacterChars("99999999", session, &command)
        #expect(preedit0() == "あるかしのくし")
        #expect(command.output.preedit.cursor == 2)

        sendSpecialKey(.right, session, &command)
        sendSpecialKey(.right, session, &command)
        #expect(command.output.preedit.cursor == 4)

        f.insertCharacterChars("/", session, &command)
        #expect(preedit0() == "あるかしんのくし")

        sendSpecialKey(.end, session, &command)
        #expect(command.output.preedit.cursor == 8)
        #expect(!command.output.preedit.isToggleable)

        f.insertCharacterChars("111*", session, &command)
        #expect(preedit0() == "あるかしんのくしぅ")

        sendSpecialKey(.left, session, &command)
        f.insertCharacterChars("u*", session, &command)
        #expect(preedit0() == "あるかしんのくしゅぅ")

        sendSpecialKey(.right, session, &command)
        f.insertCharacterChars("**", session, &command)
        #expect(preedit0() == "あるかしんのくしゅう")

        sendSpecialKey(.home, session, &command)
        sendSpecialKey(.right, session, &command)
        sendSpecialKey(.right, session, &command)
        f.insertCharacterChars("6*****", session, &command)
        #expect(preedit0() == "あるぱかしんのくしゅう")

        for _ in 0..<4 {
          sendSpecialKey(.right, session, &command)
        }
        f.insertCharacterChars("n", session, &command)
        #expect(preedit0() == "あるぱかしんのふくしゅう")
        #expect(!command.output.preedit.isToggleable)
        converter.clear()
      }
    }
  }

  /// Segments "ねこの|しっぽを|ぬいた" -> "猫の|しっぽを|抜いた".
  private func makeNekoSegments() -> Segments {
    let segments = Segments()
    var segment = segments.addSegment()
    segment.setKey("ねこの")
    segment.addCandidate().value = "猫の"

    segment = segments.addSegment()
    segment.setKey("しっぽを")
    segment.addCandidate().value = "しっぽを"

    segment = segments.addSegment()
    segment.setKey("ぬいた")
    segment.addCandidate().value = "抜いた"
    return segments
  }

  @Test func commitCandidateAt2ndOf3Segments() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Genmai_Commands_Command()
      f.insertCharacterChars("nekonoshippowonuita", session, &command)

      // Segments as conversion result.
      setStartConversionOnce(converter, makeNekoSegments())

      command = Genmai_Commands_Command()
      session.convert(&command)
      // "[猫の]|しっぽを|抜いた"

      command = Genmai_Commands_Command()
      session.segmentFocusRight(&command)
      // "猫の|[しっぽを]|抜いた"

      do {  // Segments as result of CommitHeadToFocusedSegments
        let segments = Segments()
        let segment = segments.addSegment()
        segment.setKey("ぬいた")
        segment.addCandidate().value = "抜いた"
        converter.setCommitSegments(segments, true)
      }

      command = Genmai_Commands_Command()
      command.input.command.id = 0
      try #require(session.commitCandidate(&command))
      expectPreedit("抜いた", command)
      expectSingleSegmentAndKey("抜いた", "ぬいた", command)
      expectResult("猫のしっぽを", command)
    }
  }

  @Test func commitCandidateAt3rdOf3Segments() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Genmai_Commands_Command()
      f.insertCharacterChars("nekonoshippowonuita", session, &command)

      // Segments as conversion result.
      setStartConversionOnce(converter, makeNekoSegments())

      command = Genmai_Commands_Command()
      session.convert(&command)
      // "[猫の]|しっぽを|抜いた"

      command = Genmai_Commands_Command()
      session.segmentFocusRight(&command)
      session.segmentFocusRight(&command)
      // "猫の|しっぽを|[抜いた]"

      command = Genmai_Commands_Command()
      command.input.command.id = 0
      try #require(session.commitCandidate(&command))
      #expect(!command.output.hasPreedit)
      expectResult("猫のしっぽを抜いた", command)
    }
  }

  @Test func commitCandidateSuggestion() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session, f.mobileRequest)

      let segmentsMo = Segments()
      do {
        let segment = segmentsMo.addSegment()
        segment.setKey("MO")
        addCandidate("MOCHA", "MOCHA", segment)
        addCandidate("MOZUKU", "MOZUKU", segment)
      }

      var command = Genmai_Commands_Command()
      sendKey("M", session, &command)
      command = Genmai_Commands_Command()
      converter.setStartPrediction(segmentsMo, true)
      sendKey("O", session, &command)
      try #require(command.output.hasCandidateWindow)
      #expect(command.output.candidateWindow.candidate.count == 2)
      #expect(command.output.candidateWindow.candidate.first?.value == "MOCHA")

      converter.setCommitSegmentValue(segmentsMo, true)
      var finishUsed = false
      converter.finishConversionHandler = { _, out in
        if finishUsed { return }
        finishUsed = true
        out.assign(from: Segments())
      }
      setSendCommandCommand(.submitCandidate, &command)
      command.input.command.id = 1
      session.sendCommand(&command)
      #expect(command.output.consumed)
      expectResultAndKey("MOZUKU", "MOZUKU", command)
      #expect(!command.output.hasPreedit)
      // Zero query suggestion fills the candidates.
      #expect(command.output.hasCandidateWindow)
      #expect(command.output.preedit.cursor == 0)
    }
  }

  @Test func commitCandidateT13N() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session, f.mobileRequest)

      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey("tok")
      addCandidate("tok", "tok", segment)
      addMetaCandidate("tok", "tok", segment)
      addMetaCandidate("tok", "TOK", segment)
      addMetaCandidate("tok", "Tok", segment)
      #expect(segment.candidate(-1).value == "tok")
      #expect(segment.candidate(-2).value == "TOK")
      #expect(segment.candidate(-3).value == "Tok")

      converter.setStartPrediction(segments, true)

      var command = Genmai_Commands_Command()
      sendKey("k", session, &command)
      try #require(command.output.hasCandidateWindow)
      var id = 0
      // _WIN32 || __APPLE__: meta candidates are in cascading window
      #expect(!findCandidateID(command.output.candidateWindow, "TOK", &id))
    }
  }

  @Test func requestConvertReverse() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Genmai_Commands_Command()
      #expect(session.requestConvertReverse(&command))
      #expect(!command.output.hasResult)
      #expect(!command.output.hasDeletionRange)
      #expect(command.output.hasCallback)
      #expect(command.output.callback.hasSessionCommand)
      #expect(command.output.callback.sessionCommand.type == .convertReverse)
    }
  }

  @Test func convertReverseFails() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      let kKanjiContainsNewline = "改行\n禁止"
      var command = Genmai_Commands_Command()
      f.setupCommandForReverseConversion(kKanjiContainsNewline, &command.input)

      #expect(session.sendCommand(&command))
      #expect(command.output.consumed)
      #expect(!command.output.hasCandidateWindow)
    }
  }

  @Test func convertReverse() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      let kKanjiAiueo = "阿伊宇江於"
      var command = Genmai_Commands_Command()
      f.setupCommandForReverseConversion(kKanjiAiueo, &command.input)
      f.setupMockForReverseConversion(kKanjiAiueo, "あいうえお", converter)

      #expect(session.sendCommand(&command))
      #expect(command.output.consumed)
      #expect(command.output.preedit.segment.first?.value == kKanjiAiueo)
      #expect(command.output.allCandidateWords.candidates.first?.value == kKanjiAiueo)
      #expect(command.output.hasCandidateWindow)
      #expect(command.output.candidateWindow.candidate.count > 0)
    }
  }

  @Test func escapeFromConvertReverse() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      let kKanjiAiueo = "阿伊宇江於"

      var command = Genmai_Commands_Command()
      f.setupCommandForReverseConversion(kKanjiAiueo, &command.input)
      f.setupMockForReverseConversion(kKanjiAiueo, "あいうえお", converter)

      #expect(session.sendCommand(&command))
      #expect(command.output.consumed)
      #expect(getComposition(command) == kKanjiAiueo)

      sendKey("ESC", session, &command)

      // KANJI should be converted into HIRAGANA in pre-edit state.
      expectSingleSegment("あいうえお", command)

      sendKey("ESC", session, &command)

      // Fixed KANJI should be output
      #expect(!command.output.hasPreedit)
      expectResult(kKanjiAiueo, command)
    }
  }

  @Test func secondEscapeFromConvertReverse() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      let kKanjiAiueo = "阿伊宇江於"
      var command = Genmai_Commands_Command()
      f.setupCommandForReverseConversion(kKanjiAiueo, &command.input)
      f.setupMockForReverseConversion(kKanjiAiueo, "あいうえお", converter)

      #expect(session.sendCommand(&command))
      #expect(command.output.consumed)
      #expect(getComposition(command) == kKanjiAiueo)

      sendKey("ESC", session, &command)
      sendKey("ESC", session, &command)

      #expect(!command.output.hasPreedit)
      // When a reverse conversion is canceled, the converter sets the
      // original text into |command.output().result().key()|.
      expectResultAndKey(kKanjiAiueo, kKanjiAiueo, command)

      sendKey("a", session, &command)
      #expect(getComposition(command) == "あ")

      sendKey("ESC", session, &command)
      #expect(!command.output.hasPreedit)
      #expect(!command.output.hasResult)
    }
  }

  @Test func secondEscapeFromConvertReverseIssue5687022() throws {
    try withScopedSessionEnvironment {
      // This is a unittest against http://b/5687022
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      let kInput = "abcde"
      let kReading = "abcde"

      var command = Genmai_Commands_Command()
      f.setupCommandForReverseConversion(kInput, &command.input)
      f.setupMockForReverseConversion(kInput, kReading, converter)

      #expect(session.sendCommand(&command))
      #expect(command.output.consumed)
      #expect(getComposition(command) == kInput)

      sendKey("ESC", session, &command)
      sendKey("ESC", session, &command)

      #expect(!command.output.hasPreedit)
      // When a reverse conversion is canceled, the converter sets the
      // original text into |result().key()|.
      expectResultAndKey(kInput, kInput, command)
    }
  }

  @Test func secondEscapeFromConvertReverseKeepsOriginalText() throws {
    try withScopedSessionEnvironment {
      // Second escape from ConvertReverse should restore the original text
      // without any text normalization even if the input text contains any
      // special characters which Mozc usually do normalization.
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      let kInput = "ゔ"

      var command = Genmai_Commands_Command()
      f.setupCommandForReverseConversion(kInput, &command.input)
      f.setupMockForReverseConversion(kInput, kInput, converter)

      #expect(session.sendCommand(&command))
      #expect(command.output.consumed)
      #expect(getComposition(command) == kInput)

      sendKey("ESC", session, &command)
      sendKey("ESC", session, &command)

      #expect(!command.output.hasPreedit)

      // When a reverse conversion is canceled, the converter sets the
      // original text into |result().key()|.
      expectResultAndKey(kInput, kInput, command)
    }
  }

  @Test func escapeFromCompositionAfterConvertReverse() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      let kKanjiAiueo = "阿伊宇江於"

      var command = Genmai_Commands_Command()
      f.setupCommandForReverseConversion(kKanjiAiueo, &command.input)
      f.setupMockForReverseConversion(kKanjiAiueo, "あいうえお", converter)

      // Conversion Reverse
      #expect(session.sendCommand(&command))
      #expect(command.output.consumed)
      #expect(getComposition(command) == kKanjiAiueo)

      session.commit(&command)

      expectResult(kKanjiAiueo, command)

      // Escape in composition state
      sendKey("a", session, &command)
      #expect(getComposition(command) == "あ")

      sendKey("ESC", session, &command)
      #expect(!command.output.hasPreedit)
      #expect(!command.output.hasResult)
    }
  }

  @Test func convertReverseFromOffState() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      let kanjiAiueo = "阿伊宇江於"

      // IMEOff
      var command = Genmai_Commands_Command()
      sendSpecialKey(.off, session, &command)

      f.setupCommandForReverseConversion(kanjiAiueo, &command.input)
      f.setupMockForReverseConversion(kanjiAiueo, "あいうえお", converter)
      #expect(session.sendCommand(&command))
      #expect(command.output.consumed)
    }
  }

  @Test func dcheckFailureAfterConvertReverse() throws {
    try withScopedSessionEnvironment {
      // This is a unittest against http://b/5145295.
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      var command = Genmai_Commands_Command()
      f.setupCommandForReverseConversion("あいうえお", &command.input)
      f.setupMockForReverseConversion("あいうえお", "あいうえお", converter)
      #expect(session.sendCommand(&command))
      #expect(command.output.consumed)
      #expect(command.output.preedit.segment.first?.value == "あいうえお")
      #expect(command.output.allCandidateWords.candidates.first?.value == "あいうえお")
      #expect(command.output.hasCandidateWindow)
      #expect(command.output.candidateWindow.candidate.count > 0)

      sendKey("ESC", session, &command)
      sendKey("a", session, &command)
      #expect(command.output.preedit.segment.first?.value == "あいうえおあ")
      #expect(!command.output.hasResult)
    }
  }

  @Test func launchTool() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)

      do {
        var command = Genmai_Commands_Command()
        #expect(session.launchConfigDialog(&command))
        #expect(command.output.launchToolMode == .configDialog)
        #expect(command.output.consumed)
      }

      do {
        var command = Genmai_Commands_Command()
        #expect(session.launchDictionaryTool(&command))
        #expect(command.output.launchToolMode == .dictionaryTool)
        #expect(command.output.consumed)
      }

      do {
        var command = Genmai_Commands_Command()
        #expect(session.launchWordRegisterDialog(&command))
        #expect(command.output.launchToolMode == .wordRegisterDialog)
        #expect(command.output.consumed)
      }
    }
  }

  @Test func notZeroQuerySuggest() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      // Disable zero query suggest.
      var request = Genmai_Commands_Request()
      request.zeroQuerySuggestion = false
      session.setRequest(request)

      // Type "google".
      var command = Genmai_Commands_Command()
      f.insertCharacterChars("google", session, &command)
      #expect(getComposition(command) == "google")

      // Set up a mock suggestion result.
      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey("")
      segment.addCandidate().value = "search"
      segment.addCandidate().value = "input"

      // Commit composition and zero query suggest should not be invoked.
      var startPredictionCount = 0
      converter.startPredictionHandler = { _, _ in
        startPredictionCount += 1
        return false
      }
      command = Genmai_Commands_Command()
      session.commit(&command)
      #expect(command.output.result.value == "google")
      #expect(getComposition(command) == "")
      #expect(!command.output.hasCandidateWindow)
      #expect(startPredictionCount == 0)

      let context = session.context
      #expect(context.state == .precomposition)
    }
  }

  @Test func zeroQuerySuggest() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      func expectSearchInput(_ command: Genmai_Commands_Command) {
        #expect(command.output.hasCandidateWindow)
        #expect(command.output.candidateWindow.candidate.count == 2)
        if command.output.candidateWindow.candidate.count == 2 {
          #expect(command.output.candidateWindow.candidate[0].value == "search")
          #expect(command.output.candidateWindow.candidate[1].value == "input")
        }
      }

      do {  // Commit
        let session = Session(engine)
        var request = Genmai_Commands_Request()
        f.setupZeroQuerySuggestionReady(true, session, &request, converter)

        var command = Genmai_Commands_Command()
        session.commit(&command)
        #expect(command.output.result.value == "GOOGLE")
        #expect(getComposition(command) == "")
        expectSearchInput(command)
        #expect(session.context.state == .precomposition)
        converter.clear()
      }

      do {  // CommitSegment
        let session = Session(engine)
        var request = Genmai_Commands_Request()
        f.setupZeroQuerySuggestionReady(true, session, &request, converter)

        var command = Genmai_Commands_Command()
        session.commitSegment(&command)
        #expect(command.output.result.value == "GOOGLE")
        #expect(getComposition(command) == "")
        expectSearchInput(command)
        #expect(session.context.state == .precomposition)
        converter.clear()
      }

      do {  // CommitCandidate
        let session = Session(engine)
        var request = Genmai_Commands_Request()
        f.setupZeroQuerySuggestionReady(true, session, &request, converter)

        var command = Genmai_Commands_Command()
        setSendCommandCommand(.submitCandidate, &command)
        command.input.command.id = 0
        session.sendCommand(&command)

        #expect(command.output.result.value == "GOOGLE")
        #expect(getComposition(command) == "")
        expectSearchInput(command)
        #expect(session.context.state == .precomposition)
        converter.clear()
      }

      do {  // CommitFirstSuggestion
        let session = Session(engine)
        f.initSessionToPrecomposition(session)

        // Enable zero query suggest.
        var request = Genmai_Commands_Request()
        request.zeroQuerySuggestion = true
        session.setRequest(request)

        // Type "g".
        var command = Genmai_Commands_Command()
        f.insertCharacterChars("g", session, &command)

        do {
          // Set up a mock conversion result.
          let segments = Segments()
          let segment = segments.addSegment()
          segment.setKey("")
          segment.addCandidate().value = "google"
          setStartPredictionOnce(converter, segments)
        }

        command = Genmai_Commands_Command()
        f.insertCharacterChars("o", session, &command)

        do {
          // Set up a mock suggestion result.
          let segments = Segments()
          let segment = segments.addSegment()
          segment.setKey("")
          segment.addCandidate().value = "search"
          segment.addCandidate().value = "input"
          setStartPredictionOnce(converter, segments)
        }

        command = Genmai_Commands_Command()
        session.commitFirstSuggestion(&command)
        #expect(command.output.result.value == "google")
        #expect(getComposition(command) == "")
        expectSearchInput(command)
        #expect(session.context.state == .precomposition)
      }
    }
  }

  @Test func commandsAfterZeroQuerySuggest() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      do {  // Cancel command should close the candidate window.
        let session = Session(engine)
        var request = Genmai_Commands_Request()
        var command = Genmai_Commands_Command()
        f.setupZeroQuerySuggestion(session, &request, &command, converter)

        command = Genmai_Commands_Command()
        session.editCancel(&command)
        #expect(command.output.consumed)
        #expect(!command.output.hasPreedit)
        #expect(!command.output.hasResult)
        #expect(getComposition(command) == "")
        #expect(session.context.state == .precomposition)
      }

      do {  // PredictAndConvert should select the first candidate.
        let session = Session(engine)
        var request = Genmai_Commands_Request()
        var command = Genmai_Commands_Command()
        f.setupZeroQuerySuggestion(session, &request, &command, converter)

        command = Genmai_Commands_Command()
        session.predictAndConvert(&command)
        #expect(command.output.consumed)
        #expect(!command.output.hasResult)
        // "search" is the first suggest candidate.
        expectPreedit("search", command)
        #expect(session.context.state == .conversion)
      }

      do {  // CommitFirstSuggestion should insert the first candidate.
        let session = Session(engine)
        var request = Genmai_Commands_Request()
        var command = Genmai_Commands_Command()
        f.setupZeroQuerySuggestion(session, &request, &command, converter)

        command = Genmai_Commands_Command()
        // FinishConversion is expected to return empty Segments.
        converter.finishConversionHandler = { _, out in out.assign(from: Segments()) }
        session.commitFirstSuggestion(&command)
        #expect(command.output.consumed)
        #expect(!command.output.hasPreedit)
        #expect(getComposition(command) == "")
        // "search" is the first suggest candidate.
        expectResult("search", command)
        #expect(session.context.state == .precomposition)
      }

      do {  // Space should be inserted directly.
        let session = Session(engine)
        var request = Genmai_Commands_Request()
        var command = Genmai_Commands_Command()
        f.setupZeroQuerySuggestion(session, &request, &command, converter)

        sendKey("Space", session, &command)
        #expect(command.output.consumed)
        #expect(!command.output.hasPreedit)
        #expect(getComposition(command) == "")
        expectResult("　", command)  // Full-width space
        #expect(session.context.state == .precomposition)
      }

      do {  // 'a' should be inserted in the composition.
        let session = Session(engine)
        var request = Genmai_Commands_Request()
        var command = Genmai_Commands_Command()
        f.setupZeroQuerySuggestion(session, &request, &command, converter)
        #expect(command.output.mode == .hiragana)

        sendKey("a", session, &command)
        #expect(command.output.consumed)
        #expect(!command.output.hasResult)
        #expect(command.output.mode == .hiragana)
        expectPreedit("あ", command)
        #expect(session.context.state == .composition)
      }

      do {  // Enter should be inserted directly.
        let session = Session(engine)
        var request = Genmai_Commands_Request()
        var command = Genmai_Commands_Command()
        f.setupZeroQuerySuggestion(session, &request, &command, converter)

        sendKey("Enter", session, &command)
        #expect(!command.output.consumed)
        #expect(!command.output.hasPreedit)
        #expect(!command.output.hasResult)
        #expect(getComposition(command) == "")
        #expect(session.context.state == .precomposition)
      }

      do {  // Right should be inserted directly.
        let session = Session(engine)
        var request = Genmai_Commands_Request()
        var command = Genmai_Commands_Command()
        f.setupZeroQuerySuggestion(session, &request, &command, converter)

        sendKey("Right", session, &command)
        #expect(!command.output.consumed)
        #expect(!command.output.hasPreedit)
        #expect(!command.output.hasResult)
        #expect(getComposition(command) == "")
        #expect(session.context.state == .precomposition)
      }

      do {  // SelectCnadidate command should work with zero query suggestion.
        let session = Session(engine)
        var request = Genmai_Commands_Request()
        var command = Genmai_Commands_Command()
        f.setupZeroQuerySuggestion(session, &request, &command, converter)

        // Send SELECT_CANDIDATE command.
        let firstId = command.output.candidateWindow.candidate.first?.id ?? 0
        setSendCommandCommand(.selectCandidate, &command)
        command.input.command.id = firstId
        #expect(session.sendCommand(&command))

        #expect(command.output.consumed)
        #expect(!command.output.hasResult)
        // "search" is the first suggest candidate.
        expectPreedit("search", command)
        #expect(session.context.state == .conversion)
      }
    }
  }

  @Test func issue4437420() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)
      var command = Genmai_Commands_Command()
      var request = Genmai_Commands_Request()
      // Creates overriding config.
      var overridingConfig = Genmai_Config_Config()
      overridingConfig.sessionKeymap = .mobile
      // Change to 12keys-halfascii mode.
      switchCompositionMode(.halfAscii, session)

      command = Genmai_Commands_Command()
      request.specialRomanjiTable = .twelveKeysToHalfwidthascii
      session.setRequest(request)
      session.setTable(makeTable(request))
      // Type "2*" to produce "A".
      setSendKeyCommand("2", &command)
      command.input.config = overridingConfig
      session.sendKey(&command)
      setSendKeyCommand("*", &command)
      command.input.config = overridingConfig
      session.sendKey(&command)
      #expect(getComposition(command) == "A")

      // Change to 12keys-halfascii mode.
      switchCompositionMode(.halfAscii, session)

      command = Genmai_Commands_Command()
      request.specialRomanjiTable = .twelveKeysToHalfwidthascii
      session.setRequest(request)
      session.setTable(makeTable(request))
      // Type "2" to produce "Aa".
      setSendKeyCommand("2", &command)
      command.input.config = overridingConfig
      session.sendKey(&command)
      #expect(getComposition(command) == "Aa")
    }
  }

  // If undo context is empty, key event for UNDO should be echoed back. b/5553298
  @Test func issue5553298() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      _ = f.createEngineConverterMock(engine)

      let session = Session(engine)
      f.initSessionToPrecomposition(session)

      // Undo requires capability DELETE_PRECEDING_TEXT.
      var capability = Genmai_Commands_Capability()
      capability.textDeletion = .deletePrecedingText
      session.setClientCapability(capability)

      var command = Genmai_Commands_Command()
      session.resetContext(&command)

      setSendKeyCommand("Ctrl Backspace", &command)
      command.input.config.sessionKeymap = .msime
      session.testSendKey(&command)
      #expect(!command.output.consumed)

      setSendKeyCommand("Ctrl Backspace", &command)
      command.input.config.sessionKeymap = .msime
      session.sendKey(&command)
      #expect(!command.output.consumed)
    }
  }

  @Test func undoKeyAction() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      let engine = MockEngine()
      let converter = f.createEngineConverterMock(engine)

      var command = Genmai_Commands_Command()
      var request = Genmai_Commands_Request()
      // Creates overriding config.
      var overridingConfig = Genmai_Config_Config()
      overridingConfig.sessionKeymap = .mobile

      func sendKeyOverriding(_ key: String, _ session: Session) {
        setSendKeyCommand(key, &command)
        command.input.config = overridingConfig
        session.sendKey(&command)
      }
      func sendUndoOrRewindOverriding(_ session: Session) {
        setSendCommandCommand(.undoOrRewind, &command)
        command.input.config = overridingConfig
        session.sendCommand(&command)
      }

      // Test in half width ascii mode.
      do {
        let session = Session(engine)
        f.initSessionToPrecomposition(session)

        // Change to 12keys-halfascii mode.
        switchCompositionMode(.halfAscii, session)

        command = Genmai_Commands_Command()
        request.specialRomanjiTable = .twelveKeysToHalfwidthascii
        session.setRequest(request)
        session.setTable(makeTable(request))

        // Type "2" to produce "a".
        sendKeyOverriding("2", session)
        #expect(getComposition(command) == "a")

        // Type "2" again to produce "b".
        sendKeyOverriding("2", session)
        #expect(getComposition(command) == "b")

        // Push UNDO key to reproduce "a".
        sendUndoOrRewindOverriding(session)
        #expect(getComposition(command) == "a")
        #expect(command.output.consumed)

        // Push UNDO key again to produce "2".
        sendUndoOrRewindOverriding(session)
        #expect(getComposition(command) == "2")
        #expect(command.output.consumed)
        command = Genmai_Commands_Command()
      }

      // Test in Hiaragana-mode.
      do {
        let session = Session(engine)
        f.initSessionToPrecomposition(session)

        // Change to 12keys-Hiragana mode.
        switchCompositionMode(.hiragana, session)

        command = Genmai_Commands_Command()
        request.specialRomanjiTable = .twelveKeysToHiragana
        session.setRequest(request)
        session.setTable(makeTable(request))
        // Type "33{<}{<}" to produce "さ"->"し"->"さ"->"そ".
        sendKeyOverriding("3", session)
        #expect(getComposition(command) == "さ")

        sendKeyOverriding("3", session)
        #expect(getComposition(command) == "し")

        sendUndoOrRewindOverriding(session)
        #expect(getComposition(command) == "さ")
        #expect(command.output.consumed)
        command = Genmai_Commands_Command()

        sendUndoOrRewindOverriding(session)
        #expect(getComposition(command) == "そ")
        #expect(command.output.consumed)
        command = Genmai_Commands_Command()
      }

      // Test to do nothing for voiced sounds.
      do {
        let session = Session(engine)
        f.initSessionToPrecomposition(session)

        // Change to 12keys-Hiragana mode.
        switchCompositionMode(.hiragana, session)

        command = Genmai_Commands_Command()
        request.specialRomanjiTable = .twelveKeysToHiragana
        session.setRequest(request)
        session.setTable(makeTable(request))
        // Type "3*{<}*{<}", and composition should change
        // "さ"->"ざ"->(No change)->"さ"->(No change).
        sendKeyOverriding("3", session)
        #expect(getComposition(command) == "さ")

        sendKeyOverriding("*", session)
        #expect(getComposition(command) == "ざ")

        sendUndoOrRewindOverriding(session)
        #expect(getComposition(command) == "ざ")
        #expect(command.output.consumed)

        sendKeyOverriding("*", session)
        #expect(getComposition(command) == "さ")
        command = Genmai_Commands_Command()

        sendUndoOrRewindOverriding(session)
        #expect(getComposition(command) == "さ")
        #expect(command.output.consumed)
        command = Genmai_Commands_Command()
      }

      // Test to make nothing newly in preedit for empty composition.
      do {
        let session = Session(engine)
        f.initSessionToPrecomposition(session)

        // Change to 12keys-Hiragana mode.
        switchCompositionMode(.hiragana, session)

        command = Genmai_Commands_Command()
        request.specialRomanjiTable = .twelveKeysToHiragana
        session.setRequest(request)
        session.setTable(makeTable(request))
        // Type "{<}" and do nothing
        sendUndoOrRewindOverriding(session)

        #expect(!command.output.hasPreedit)

        command = Genmai_Commands_Command()
      }

      // Test of acting as UNDO key. Almost same as the first section in Undo test.
      do {
        let session = Session(engine)
        f.initSessionToPrecomposition(session)

        var capability = Genmai_Commands_Capability()
        capability.textDeletion = .deletePrecedingText
        session.setClientCapability(capability)

        let segments = Segments()
        f.insertCharacterChars("aiueo", session, &command)
        f.setAiueo(segments)
        var candidate = segments.mutableSegment(0).addCandidate()
        candidate.value = "aiueo"
        candidate = segments.mutableSegment(0).addCandidate()
        candidate.value = "AIUEO"

        setStartConversionOnce(converter, segments)
        command = Genmai_Commands_Command()
        session.convert(&command)
        #expect(!command.output.hasResult)
        expectPreedit("あいうえお", command)

        converter.setCommitSegmentValue(segments, true)
        command = Genmai_Commands_Command()
        session.commit(&command)
        #expect(!command.output.hasPreedit)
        expectResult("あいうえお", command)

        command = Genmai_Commands_Command()
        sendUndoOrRewindOverriding(session)
        #expect(!command.output.hasResult)
        #expect(command.output.hasDeletionRange)
        #expect(command.output.deletionRange.offset == -5)
        #expect(command.output.deletionRange.length == 5)
        expectPreedit("あいうえお", command)
        #expect(command.output.consumed)

        // Undo twice - do nothing and don't cosume the input.
        command = Genmai_Commands_Command()
        setSendCommandCommand(.undoOrRewind, &command)
        session.sendCommand(&command)
        #expect(!command.output.hasResult)
        #expect(!command.output.hasDeletionRange)
        #expect(!command.output.hasPreedit)
        #expect(!command.output.consumed)
      }

      // Do not UNDO even if UNDO stack is not empty if it is in COMPOSITE state.
      do {
        let session = Session(engine)
        f.initSessionToPrecomposition(session)

        // Change to 12keys-Hiragana mode.
        switchCompositionMode(.hiragana, session)

        command = Genmai_Commands_Command()
        request.specialRomanjiTable = .twelveKeysToHiragana
        session.setRequest(request)
        session.setTable(makeTable(request))

        // commit "あ" to push UNDO stack
        sendKeyOverriding("1", session)
        #expect(getComposition(command) == "あ")
        command = Genmai_Commands_Command()

        session.commit(&command)
        #expect(!command.output.hasPreedit)
        expectResult("あ", command)

        // Produce "か" in composition.
        sendKeyOverriding("2", session)
        #expect(getComposition(command) == "か")
        #expect(command.output.consumed)
        command = Genmai_Commands_Command()

        // Send UNDO_OR_REWIND key, then get "こ" in composition
        sendUndoOrRewindOverriding(session)
        expectPreedit("こ", command)
        #expect(command.output.consumed)
        command = Genmai_Commands_Command()
      }
    }
  }

  @Test
  func dedupAfterUndo() throws {
    try withScopedSessionEnvironment {
      let f = try SessionTestFixture()
      var command = Genmai_Commands_Command()
      do {
        let session = Session(try f.mockDataEngine())
        f.initSessionToPrecomposition(session, f.mobileRequest)

        // Undo requires capability DELETE_PRECEDING_TEXT.
        var capability = Genmai_Commands_Capability()
        capability.textDeletion = .deletePrecedingText
        session.setClientCapability(capability)

        switchCompositionMode(.hiragana, session)

        var request = f.mobileRequest
        request.specialRomanjiTable = .twelveKeysToHiragana
        session.setRequest(request)

        session.setTable(makeTable(request))

        // Type "!" to produce "！".
        setSendKeyCommand("!", &command)
        session.sendKey(&command)
        #expect(session.context.state == .composition)
        #expect(getComposition(command) == "！")

        try #require(command.output.hasCandidateWindow)

        var ids: [Int] = []
        findCandidateIDs(command.output.candidateWindow, "！", &ids)
        #expect(1 >= ids.count)

        findCandidateIDs(command.output.candidateWindow, "!", &ids)
        #expect(1 >= ids.count)

        let candidateSizeBeforeUndo = command.output.candidateWindow.candidate.count

        command = Genmai_Commands_Command()
        session.commitFirstSuggestion(&command)
        #expect(!command.output.hasPreedit)
        #expect(session.context.state == .precomposition)

        command = Genmai_Commands_Command()
        session.undo(&command)
        #expect(session.context.state == .composition)
        #expect(command.output.hasDeletionRange)
        try #require(command.output.hasCandidateWindow)

        findCandidateIDs(command.output.candidateWindow, "！", &ids)
        #expect(1 >= ids.count)

        findCandidateIDs(command.output.candidateWindow, "!", &ids)
        #expect(1 >= ids.count)

        #expect(candidateSizeBeforeUndo == command.output.candidateWindow.candidate.count)
      }
    }
  }
}
