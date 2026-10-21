// Tests for the keymap / romaji table / character form editors and the generic table editor.

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import Testing

@testable import GenmaiGUI

@MainActor
@Suite struct GenericTableEditorTests {
  @Test func linesLikeGetlineAndChopReturns() {
    #expect(tableEditorLines("") == [])
    #expect(tableEditorLines("a\r\nb\n") == ["a", "b"])
    #expect(tableEditorLines("a\n\nb") == ["a", "", "b"])
    #expect(splitTabAllowEmpty("a\t\tb") == ["a", "", "b"])
    #expect(splitTabSkipEmpty("a\t\tb") == ["a", "b"])
  }

  @Test func addInsertDelete() {
    let table = GenericTableEditorModel<RomanTableRow>(dialogTitle: "t")
    table.deleteSelectedItems()
    #expect(table.pendingMessage?.kind == .warning)
    table.pendingMessage = nil
    table.insertItem()
    #expect(table.pendingMessage?.kind == .warning)

    table.addNewItem()
    table.rows[0].input = "a"
    table.addNewItem()
    table.rows[1].input = "b"
    #expect(table.selection == [table.rows[1].id])
    table.selection = [table.rows[0].id]
    table.insertItem()
    #expect(table.rows.map(\.input) == ["a", "", "b"])

    // Deleting keeps the cursor on the next row.
    let bID = table.rows[2].id
    table.selection = [table.rows[1].id]
    table.deleteSelectedItems()
    #expect(table.rows.map(\.input) == ["a", "b"])
    #expect(table.selection == [bID])
  }
}

@MainActor
@Suite struct RomanTableEditorTests {
  @Test func defaultTableLoads() {
    let model = RomanTableEditorModel(currentRomanTable: "")
    #expect(model.table.rowCount > 100)
    #expect(model.update())
    #expect(model.serializedTable == RomanTableEditorModel.defaultRomanTable())
    // Show() returns an empty table when the result equals the default.
    #expect(model.acceptedRomanTable() == "")
  }

  @Test func loadAndUpdate() {
    let model = RomanTableEditorModel(currentRomanTable: "a\tあ\nka\tか\nkk\tっ\tk\nbad\n\n")
    #expect(model.table.rows.map(\.input) == ["a", "ka", "kk"])
    #expect(model.table.rows[0].pending == "")
    #expect(model.table.rows[2].pending == "k")
    model.table.addNewItem()  // empty rows are dropped
    #expect(model.update())
    #expect(model.serializedTable == "a\tあ\nka\tか\nkk\tっ\tk\n")
    #expect(model.acceptedRomanTable() == "a\tあ\nka\tか\nkk\tっ\tk\n")
    #expect(model.table.pendingMessage == nil)
  }

  @Test func capitalInputShowsInformation() {
    let model = RomanTableEditorModel(currentRomanTable: "A\tあ\n")
    #expect(model.update())
    #expect(model.table.pendingMessage?.kind == .information)
  }

  @Test func emptyTableIsRejected() {
    let model = RomanTableEditorModel(currentRomanTable: "a\tあ\n")
    model.table.selection = [model.table.rows[0].id]
    model.table.deleteSelectedItems()
    #expect(!model.okEnabled)
    #expect(!model.update())
    #expect(model.table.pendingMessage?.kind == .warning)
  }

  @Test func resetAsksBeforeOverwriting() {
    let model = RomanTableEditorModel(currentRomanTable: "a\tあ\n")
    model.confirmOverwrite { model.loadDefaultRomanTable() }
    #expect(model.table.rowCount == 1)
    model.table.pendingMessage?.onYes?()
    #expect(model.table.rowCount > 100)
  }

  @Test func importAndExportFiles() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("romantable.txt")
    try Data("xa\tぁ\n".utf8).write(to: file)
    let model = RomanTableEditorModel(currentRomanTable: "a\tあ\n")
    model.importFile(file)
    #expect(model.table.rows.map(\.output) == ["ぁ"])
    model.importFile(dir.appendingPathComponent("missing"))
    #expect(model.table.pendingMessage?.kind == .warning)

    let out = dir.appendingPathComponent("out.txt")
    #expect(model.update())
    model.table.writeExportFile(out, model.serializedTable)
    #expect(try String(contentsOf: out, encoding: .utf8) == "xa\tぁ\n")

    let large = dir.appendingPathComponent("large.txt")
    try Data(repeating: 0x61, count: 100 * 1024).write(to: large)
    model.table.pendingMessage = nil
    model.importFile(large)
    #expect(model.table.pendingMessage?.kind == .warning)
  }
}

@MainActor
@Suite struct KeyMapEditorTests {
  @Test func commandListExcludesInvisibleCommands() {
    let model = KeyMapEditorModel()
    #expect(!model.commands.contains("IMEOn"))
    #expect(!model.commands.contains("IMEOff"))
    #expect(!model.commands.contains("InsertCharacter"))
    #expect(!model.commands.contains("ReportBug"))
    #expect(model.commands.contains("Convert"))
    #expect(Set(model.commands).count == model.commands.count)
  }

  @Test func predefinedKeymapsExist() {
    for (keymap, _) in KeyMapEditorModel.predefinedKeymaps {
      #expect(KeyMapEditorModel.predefinedKeymapTable(keymap).hasPrefix("status\tkey\tcommand"))
    }
  }

  @Test func loadSplitsVisibleAndInvisibleEntries() {
    let text = """
      status\tkey\tcommand
      # comment
      Precomposition\tCtrl a\tConvert
      Composition\tASCII\tInsertCharacter
      Precomposition\tHankaku/Zenkaku\tIMEOn
      Conversion\tShift Space\tConvertPrev
      Conversion\tbroken

      """
    let model = KeyMapEditorModel(currentKeymap: text)
    #expect(model.table.rows.map(\.key) == ["Ctrl a", "Shift Space"])
    #expect(model.update())
    #expect(
      model.serializedTable
        == "status\tkey\tcommand\nPrecomposition\tCtrl a\tConvert\nConversion\tShift Space\tConvertPrev\n"
        + "Composition\tASCII\tInsertCharacter\nPrecomposition\tHankaku/Zenkaku\tIMEOn\n")
  }

  @Test func predefinedTableRoundTrips() {
    let model = KeyMapEditorModel()
    model.importPredefined(.msime)
    #expect(model.table.rowCount > 50)
    #expect(model.update())
    let first = model.serializedTable
    let second = KeyMapEditorModel(currentKeymap: first)
    #expect(second.update())
    #expect(second.serializedTable == first)
  }

  @Test func emptyAndInvalidTables() {
    #expect(!KeyMapEditorModel().loadFromString(""))
    let empty = KeyMapEditorModel(currentKeymap: "status\tkey\tcommand\n")
    #expect(!empty.okEnabled)
    #expect(!empty.update())
    #expect(empty.table.pendingMessage?.kind == .warning)

    let invalid = KeyMapEditorModel(currentKeymap: "status\tkey\tcommand\nPrecomposition\tCtrl a\tConvert\n")
    invalid.table.rows[0].key = "NoSuchKey"
    #expect(!invalid.update())
    #expect(invalid.table.pendingMessage?.kind == .warning)
  }

  @Test func rowsWithUnknownCommandsAreDropped() {
    let model = KeyMapEditorModel(
      currentKeymap: "status\tkey\tcommand\nPrecomposition\tCtrl a\tConvert\nPrecomposition\tCtrl b\tFooBar\n")
    #expect(model.table.rowCount == 2)
    #expect(model.update())
    #expect(model.serializedTable == "status\tkey\tcommand\nPrecomposition\tCtrl a\tConvert\n")
  }

  @Test func overwriteConfirmation() {
    let model = KeyMapEditorModel(currentKeymap: "status\tkey\tcommand\nPrecomposition\tCtrl a\tConvert\n")
    model.confirmOverwrite { model.importPredefined(.atok) }
    #expect(model.table.rowCount == 1)
    model.table.pendingMessage?.onYes?()
    #expect(model.table.rowCount > 10)
  }

  @Test func localizedNames() {
    #expect(tr("genmai::gui::KeyMapEditorDialog", "Precomposition", language: .japanese) == "入力文字なし")
    #expect(tr("genmai::gui::KeyMapEditorDialog", "Convert", language: .japanese) == "変換")
  }
}

@MainActor
@Suite struct CharacterFormEditorTests {
  @Test func loadDefaultWhenEmptyAndSaveRoundTrip() {
    let editor = CharacterFormEditorModel()
    editor.load(Genmai_Config_Config())
    let defaults = ConfigHandler.defaultConfig().characterFormRules
    #expect(editor.rows.count == defaults.count)
    var config = Genmai_Config_Config()
    editor.save(&config)
    #expect(config.characterFormRules == defaults)
  }

  @Test func groupTitlesAndKatakanaPreedit() {
    let editor = CharacterFormEditorModel()
    editor.load(ConfigHandler.defaultConfig())
    let katakana = editor.rows.first { $0.group == "ア" }
    #expect(katakana?.isPreeditEditable == false)
    #expect(katakana?.groupTitle == tr("QObject", "Katakana"))
  }

  @Test func unknownFormAndEmptyGroup() {
    var config = Genmai_Config_Config()
    var rule = Genmai_Config_Config.CharacterFormRule()
    rule.group = "A"
    rule.preeditCharacterForm = .noConversion
    rule.conversionCharacterForm = .halfWidth
    config.characterFormRules = [rule]
    let editor = CharacterFormEditorModel()
    editor.load(config)
    #expect(editor.rows[0].preedit == .unknown)
    editor.rows.append(CharacterFormRow(group: "", preedit: .fullWidth, conversion: .fullWidth))
    var saved = Genmai_Config_Config()
    editor.save(&saved)
    #expect(saved.characterFormRules.count == 1)
    #expect(saved.characterFormRules[0].preeditCharacterForm == .fullWidth)  // failsafe
    #expect(saved.characterFormRules[0].conversionCharacterForm == .halfWidth)
  }
}

@Suite struct KeyBindingFilterTests {
  private func press(_ inputs: [KeyBindingInput]) -> (String, Bool) {
    var filter = KeyBindingFilter()
    var result = ("", false)
    for input in inputs {
      let (text, ok) = filter.keyPress(input)
      result = (text, ok)
    }
    return result
  }

  @Test func encodeCombinations() {
    #expect(press([.control, .printable(0x41)]) == ("Ctrl a", true))
    #expect(press([.printable(0x41)]) == ("a", false))  // no modifier
    #expect(press([.shift, .printable(0x41)]) == ("Shift a", false))  // Shift + 'a' only
    #expect(press([.control, .shift, .printable(0x41)]) == ("Ctrl Shift a", true))
    #expect(press([.control, .shift, .printable(0x40)]) == ("Ctrl Shift @", false))
    #expect(press([.control]) == ("Ctrl", false))
    #expect(press([.shift]) == ("Shift", false))
    #expect(press([.option, .nonModifierRequired("Space")]) == ("Option Space", true))
    #expect(press([.nonModifierRequired("F5")]) == ("F5", true))
    #expect(press([.shift, .nonModifierRequired("Tab")]) == ("Shift Tab", true))
    #expect(press([.yen]) == ("\\", true))
    #expect(press([.unknown(keyCode: 0x7F)]) == ("", false))
  }

  @Test func modeKeysAreSubmittedWithoutModifiers() {
    var filter = KeyBindingFilter()
    _ = filter.keyPress(.control)
    let (text, ok) = filter.keyPress(.nonModifierRequired("Hiragana"))
    #expect(text == "Hiragana")
    #expect(ok)
    // Submitted: the next key starts over.
    let (next, _) = filter.keyPress(.control)
    #expect(next == "Ctrl")
  }

  @Test func releaseCommits() {
    var filter = KeyBindingFilter()
    _ = filter.keyPress(.control)
    _ = filter.keyPress(.printable(0x41))
    filter.keyRelease()
    #expect(filter.keyPress(.printable(0x42)) == ("b", false))
  }

  @Test func nsEventTranslation() {
    #expect(KeyBindingInput(keyCode: 0x00, charactersIgnoringModifiers: "a") == .printable(0x41))
    #expect(KeyBindingInput(keyCode: 0x14, charactersIgnoringModifiers: "#") == .printable(0x23))
    #expect(KeyBindingInput(keyCode: 0x60, charactersIgnoringModifiers: "\u{F708}") == .nonModifierRequired("F5"))
    #expect(KeyBindingInput(keyCode: 0x5D, charactersIgnoringModifiers: "¥") == .yen)
    #expect(KeyBindingInput(keyCode: 0x66, charactersIgnoringModifiers: "") == .nonModifierRequired("Eisu"))
    #expect(KeyBindingInput(keyCode: 0x24, charactersIgnoringModifiers: "\r") == .nonModifierRequired("Enter"))
    #expect(KeyBindingInput(modifierKeyCode: 0x3B, flags: .control) == .control)
    #expect(KeyBindingInput(modifierKeyCode: 0x3B, flags: []) == nil)
    #expect(KeyBindingInput(modifierKeyCode: 0x3A, flags: .option) == .option)
    #expect(KeyBindingInput(modifierKeyCode: 0x37, flags: .command) == nil)
  }
}
