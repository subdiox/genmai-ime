// Model tests for the dictionary tool (gui/dictionary_tool has no C++ unit tests; these cover the
// behaviors of dictionary_tool.cc, find_dialog.cc and import_dialog.cc).

import Foundation
import GenmaiBase
import GenmaiClient
import GenmaiCore
import Testing

@testable import GenmaiGUI

@MainActor
@Suite(.serialized) struct DictionaryToolModelTests {
  init() {
    GUILanguage.setOverride(.english)
  }

  private func makeModel(_ path: String) -> (DictionaryToolModel, RecordingBackend) {
    let (client, backend) = makeRecordingClient()
    return (DictionaryToolModel(client: client, storage: UserDictionaryStorage(path)), backend)
  }

  private func fillRow(_ model: DictionaryToolModel, _ reading: String, _ word: String, _ pos: String = "名詞") {
    let id = model.rows[model.rows.count - 1].id
    model.setCell(id, .reading, reading)
    model.setCell(id, .word, word)
    model.setCell(id, .category, pos)
  }

  @Test func firstLaunchCreatesDefaultDictionary() {
    withTempDictionaryFile { path in
      let (model, _) = makeModel(path)
      #expect(model.availability == .available)
      #expect(model.dictionaries.map(\.name) == ["User Dictionary 1"])
      #expect(model.selectedDictionaryID == model.dictionaries[0].id)
      // CreateDictionaryHelper calls AddWord.
      #expect(model.rows.count == 1)
      #expect(model.rows[0].category == "名詞")
      model.close()
    }
  }

  @Test func lockedStorageIsUnavailable() {
    withTempDictionaryFile { path in
      let other = UserDictionaryStorage(path)
      #expect(other.lock())
      let (model, _) = makeModel(path)
      #expect(model.availability == .unavailable("Another process is accessing the user dictionary file."))
      other.unlock()
    }
  }

  @Test func createRenameDeleteDictionary() {
    withTempDictionaryFile { path in
      let (model, _) = makeModel(path)
      model.requestCreateDictionary()
      #expect(model.prompt == .newDictionary)
      model.completePrompt(.newDictionary, text: "Second")
      #expect(model.dictionaries.map(\.name) == ["User Dictionary 1", "Second"])
      #expect(model.selectedDictionaryID == model.dictionaries[1].id)

      // Duplicated name.
      model.createDictionary(named: "Second")
      #expect(model.pendingMessage?.text == "Dictionary already exists.")
      #expect(model.dictionaries.count == 2)
      model.pendingMessage = nil

      model.requestRenameDictionary()
      #expect(model.prompt == .renameDictionary(currentName: "Second"))
      model.completePrompt(.renameDictionary(currentName: "Second"), text: "Renamed")
      #expect(model.dictionaries[1].name == "Renamed")
      #expect(model.storage.proto.dictionaries[1].name == "Renamed")

      model.requestDeleteDictionary()
      #expect(model.pendingMessage?.kind == .question)
      #expect(model.pendingMessage?.text == "Do you want to delete Renamed?")
      model.pendingMessage?.onYes?()
      #expect(model.dictionaries.map(\.name) == ["User Dictionary 1"])
      #expect(model.selectedDictionaryID == nil)
      #expect(model.rows.isEmpty)
      model.close()
    }
  }

  @Test func addEditDeleteWordsAndSave() throws {
    try withTempDictionaryFile { path in
      let (model, backend) = makeModel(path)
      fillRow(model, "きょうと", "京都")
      model.addWord()
      fillRow(model, "とうきょう", "東京", "地名")
      model.addWord()
      fillRow(model, "おおさか", "大阪", "地名")
      #expect(model.rows.count == 3)

      // Invalid reading is reported.
      model.setCell(model.rows[0].id, .reading, "京都")
      model.onItemChanged(model.rows[0].id, .reading)
      #expect(model.pendingMessage?.text == "An invalid character is included in the reading.")
      model.setCell(model.rows[0].id, .reading, "きょうと")
      model.pendingMessage = nil

      // Edit comment / POS of the selection.
      model.selectedRowIDs = [model.rows[1].id, model.rows[2].id]
      model.requestEditComment()
      model.completePrompt(.editComment, text: "city")
      model.editPos("固有名詞")
      #expect(model.rows.map(\.comment) == ["", "city", "city"])
      #expect(model.rows.map(\.category) == ["名詞", "固有名詞", "固有名詞"])

      // Delete one word.
      model.selectedRowIDs = [model.rows[2].id]
      model.requestDeleteWords()
      #expect(model.pendingMessage?.text == "Do you want to delete this word?")
      model.pendingMessage?.onYes?()
      #expect(model.rows.map(\.word) == ["京都", "東京"])

      model.close()
      #expect(backend.reloadCount == 1)

      let reloaded = UserDictionaryStorage(path)
      try reloaded.load()
      let entries = reloaded.proto.dictionaries[0].entries
      #expect(entries.map(\.key) == ["きょうと", "とうきょう"])
      #expect(entries.map(\.pos) == [.noun, .properNoun])
      #expect(entries.map(\.comment) == ["", "city"])
    }
  }

  @Test func sortAndFind() {
    withTempDictionaryFile { path in
      let (model, _) = makeModel(path)
      fillRow(model, "c", "Gamma")
      model.addWord()
      fillRow(model, "a", "alpha")
      model.addWord()
      fillRow(model, "b", "beta ALPHA")
      model.sort(by: .reading, ascending: true)
      #expect(model.rows.map(\.reading) == ["a", "b", "c"])
      model.sort(by: .reading, ascending: false)
      #expect(model.rows.map(\.reading) == ["c", "b", "a"])
      model.sort(by: .word, ascending: true)
      #expect(model.rows.map(\.word) == ["Gamma", "alpha", "beta ALPHA"])

      model.selectedRowIDs = []
      model.resetFind()
      #expect(model.find("alpha", direction: .forward))
      #expect(model.selectedRowIDs == [model.rows[1].id])
      #expect(model.find("alpha", direction: .forward))
      #expect(model.selectedRowIDs == [model.rows[2].id])
      #expect(model.find("ALPHA", direction: .backward))
      #expect(model.selectedRowIDs == [model.rows[1].id])
      #expect(!model.find("zzz", direction: .forward))
      #expect(model.pendingMessage?.text == "Cannot find pattern zzz")
      model.close()
    }
  }

  @Test func moveWordsToAnotherDictionary() throws {
    withTempDictionaryFile { path in
      let (model, _) = makeModel(path)
      fillRow(model, "いち", "一")
      model.addWord()
      fillRow(model, "に", "二")
      let firstID = model.dictionaries[0].id
      model.createDictionary(named: "Target")
      let targetID = model.dictionaries[1].id
      model.selectDictionary(firstID)
      #expect(model.rows.map(\.word) == ["一", "二"])
      model.selectedRowIDs = [model.rows[0].id]
      model.moveSelectedWords(to: targetID)
      #expect(model.rows.map(\.word) == ["二"])
      model.selectDictionary(targetID)
      // "Target" got the moved word after its own empty AddWord row was saved.
      #expect(model.rows.map(\.word).contains("一"))
      model.close()
    }
  }

  @Test func importAndExportRoundTrip() throws {
    try withTempDictionaryFile { path in
      let dir = makeTempDirectoryOrDie()
      let importFile = FileUtil.joinPath(dir.path, "import.txt")
      try FileUtil.setContents(importFile, "きょうと\t京都\t名詞\nおおさか\t大阪\t地名\tコメント\n")
      let (model, _) = makeModel(path)

      model.requestImportAndCreateDictionary()
      #expect(model.importMode == .create)
      model.completeImport(
        mode: .create, fileName: importFile, dicName: "Imported", imeType: .imeAutoDetect,
        encodingType: .encodingAutoDetect)
      #expect(model.pendingMessage?.text == "2 entries are imported to Imported.")
      #expect(model.dictionaries.map(\.name) == ["User Dictionary 1", "Imported"])
      #expect(model.rows.map(\.word) == ["京都", "大阪"])
      #expect(model.rows.map(\.category) == ["名詞", "地名"])
      model.pendingMessage = nil

      // Re-importing into the same dictionary does not duplicate entries.
      model.completeImport(
        mode: .append, fileName: importFile, dicName: "", imeType: .google, encodingType: .utf8)
      #expect(model.rows.count == 2)
      #expect(model.pendingMessage?.text == "0 entries are imported to Imported.")

      let exportFile = FileUtil.joinPath(dir.path, "export.txt")
      model.exportDictionary(to: exportFile)
      #expect(model.pendingMessage?.text == "Dictionary export finished.")
      #expect(try FileUtil.getContents(exportFile) == "きょうと\t京都\t名詞\t\nおおさか\t大阪\t地名\tコメント\n")

      // Unsupported file.
      let badFile = FileUtil.joinPath(dir.path, "bad.txt")
      try FileUtil.setContents(badFile, "\"a\",\"b\",\"c\"\n")
      model.completeImport(mode: .append, fileName: badFile, dicName: "", imeType: .google, encodingType: .utf8)
      #expect(model.pendingMessage?.text.hasPrefix("You have imported a file in an invalid") == true)

      // Missing file.
      model.completeImport(
        mode: .append, fileName: "/nonexistent/file.txt", dicName: "", imeType: .google, encodingType: .utf8)
      #expect(model.pendingMessage?.text == "Can't open /nonexistent/file.txt.")
      model.close()
    }
  }

  @Test func importShiftJISAndUTF16Files() throws {
    try withTempDictionaryFile { path in
      let dir = makeTempDirectoryOrDie()
      // "とうきょう\t東京\t地名\r\n" in Shift_JIS.
      let sjis: [UInt8] =
        [0x82, 0xC6, 0x82, 0xA4, 0x82, 0xAB, 0x82, 0xE5, 0x82, 0xA4, 0x09, 0x93, 0x8C, 0x8B, 0x9E, 0x09]
        + [0x92, 0x6E, 0x96, 0xBC, 0x0D, 0x0A]
      let sjisFile = FileUtil.joinPath(dir.path, "sjis.txt")
      try FileUtil.setContents(sjisFile, sjis)
      let utf16File = FileUtil.joinPath(dir.path, "utf16.txt")
      try #require("!Microsoft IME Dictionary Tool\r\nおおさか\t大阪\t地名\r\n".data(using: .utf16))
        .write(to: URL(fileURLWithPath: utf16File))

      let (model, _) = makeModel(path)
      model.completeImport(
        mode: .create, fileName: sjisFile, dicName: "SJIS", imeType: .imeAutoDetect,
        encodingType: .encodingAutoDetect)
      #expect(model.rows.map(\.word) == ["東京"])
      model.completeImport(
        mode: .create, fileName: utf16File, dicName: "UTF16", imeType: .imeAutoDetect,
        encodingType: .encodingAutoDetect)
      #expect(model.rows.map(\.word) == ["大阪"])
      model.close()
    }
  }

  @Test func dictionaryLimit() {
    withTempDictionaryFile { path in
      let (model, _) = makeModel(path)
      for i in 1..<UserDictionaryStorage.maxDictionarySize {
        model.createDictionary(named: "d\(i)")
      }
      #expect(model.dictionaries.count == UserDictionaryStorage.maxDictionarySize)
      #expect(!model.canCreateDictionary)
      model.requestCreateDictionary()
      #expect(model.pendingMessage?.text == "You can't have more than 100 dictionaries.")
      model.close()
    }
  }

  @Test func qtArg() {
    #expect(DictionaryToolText.arg("%1: %2 entries", "dic", 3) == "dic: 3 entries")
    #expect(DictionaryToolText.arg("%2 then %1", "a", "b") == "b then a")
    #expect(DictionaryToolText.arg("%1 %10", "x", "y") == "x y")
  }
}
