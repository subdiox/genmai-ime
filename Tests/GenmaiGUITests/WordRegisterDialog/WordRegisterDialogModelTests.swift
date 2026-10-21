// Model tests for gui/word_register_dialog (no C++ unit tests exist for it).

import Foundation
import GenmaiBase
import GenmaiClient
import GenmaiCore
import Testing

@testable import GenmaiGUI

@MainActor
@Suite(.serialized) struct WordRegisterDialogModelTests {
  init() {
    GUILanguage.setOverride(.english)
  }

  @Test func defaultsAndValidation() throws {
    try withTempDictionaryFile { path in
      let (client, backend) = makeRecordingClient()
      let model = WordRegisterDialogModel(
        client: client, initialWord: "  ぐーぐる\n", initialReading: nil, storage: UserDictionaryStorage(path))
      #expect(model.availability == .available)
      #expect(model.word == "ぐーぐる")
      // The recording backend returns no preedit: reverse conversion fails and the reading stays empty.
      #expect(model.reading.isEmpty)
      model.reading = "ぐーぐる"
      #expect(model.posList[model.posIndex] == "名詞")
      #expect(model.dictionaryNames == ["User Dictionary 1"])
      #expect(model.focusesReadingInitially)
      #expect(model.isOKEnabled)

      model.reading = "漢字"
      #expect(!model.accept())
      #expect(model.pendingMessage?.text == "Reading part contains invalid characters.")

      model.reading = "ぐーぐる"
      model.word = "Google"
      #expect(model.accept())
      #expect(backend.reloadCount == 1)

      let reloaded = UserDictionaryStorage(path)
      try reloaded.load()
      let entries = reloaded.proto.dictionaries[0].entries
      #expect(entries.count == 1)
      #expect(entries[0].key == "ぐーぐる")
      #expect(entries[0].value == "Google")
      #expect(entries[0].pos == .noun)
    }
  }

  /// GetReading through the real engine (reverse conversion of the OSS data set).
  @Test(.enabled(if: FileManager.default.fileExists(atPath: OssDataManager.defaultDataPath), "Data/genmai.data is missing"))
  func completeReadingAndLimits() {
    withTempDictionaryFile { path in
      ConfigHandler.withScopedHandlerForTesting {
        completeReadingAndLimits(path)
      }
    }
  }

  private func completeReadingAndLimits(_ path: String) {
    do {
      let client = InProcessClient.make(backend: ToolSessionBackend(notify: { _ in }))
      let model = WordRegisterDialogModel(
        client: client, initialWord: nil, initialReading: nil, storage: UserDictionaryStorage(path))
      #expect(model.word.isEmpty)
      #expect(!model.focusesReadingInitially)
      #expect(!model.isOKEnabled)
      model.word = "カタカナ"
      model.completeReading()
      #expect(model.reading == "かたかな")
      model.reading = ""
      model.word = "漢字"
      model.completeReading()
      #expect(model.reading == "かんじ")
      model.reading = ""
      model.word = "今日は早めに帰ります"
      model.completeReading()
      #expect(model.reading == "きょうははやめにかえります")
      model.reading = ""
      model.word = "☃"
      model.completeReading()
      #expect(model.reading.isEmpty)
      model.word = String(repeating: "あ", count: 150)
      #expect(model.word.count == WordRegisterDialogModel.kMaxEditLength)
      model.reject()
    }
  }

  @Test func lockedByDictionaryTool() {
    withTempDictionaryFile { path in
      let other = UserDictionaryStorage(path)
      #expect(other.lock())
      let (client, _) = makeRecordingClient()
      let model = WordRegisterDialogModel(
        client: client, initialWord: "a", initialReading: "a", storage: UserDictionaryStorage(path))
      #expect(model.availability == .unavailable("Close dictionary tool before using word register dialog."))
      other.unlock()
    }
  }

  @Test func trimValue() {
    #expect(WordRegisterDialogModel.trimValue(" a\r\nb ") == "ab")
  }
}
