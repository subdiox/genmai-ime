// Port of mozc/src/gui/config_dialog/keymap_editor.{h,cc} and combobox_delegate.{h,cc} (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import GenmaiSession
import Observation
import SwiftUI

public struct KeyMapRow: TableEditorRow {
  public let id: UUID
  /// Normalized (untranslated) status name, e.g. "Precomposition".
  public var status: String
  /// Mozc key string, e.g. "Ctrl Shift a".
  public var key: String
  /// Normalized (untranslated) command name, e.g. "IMEOn".
  public var command: String

  public init(id: UUID = UUID(), status: String, key: String, command: String) {
    self.id = id
    self.status = status
    self.key = key
    self.command = command
  }

  public static func empty() -> KeyMapRow { KeyMapRow(status: "", key: "", command: "") }
}

/// Port of KeyMapEditorDialog::KeyMapValidator.
struct KeyMapValidator {
  static let kInsertCharacterCommand = "InsertCharacter"
  static let kReportBugCommand = "ReportBug"
  // Old command name
  static let kEditInsertCommand = "EditInsert"
  static let kIMEOnCommand = "IMEOn"
  static let kIMEOffCommand = "IMEOff"

  let invisibleCommands: Set<String> = [
    kInsertCharacterCommand, kReportBugCommand, kEditInsertCommand,
    // On Mac, we cannot customize keybindings for IME ON/OFF
    // So we do not show them.
    kIMEOnCommand, kIMEOffCommand,
  ]
  let invisibleModifiers: Set<Genmai_Commands_KeyEvent.ModifierKey> = [.keyDown, .keyUp]
  let invisibleKeyEvents: Set<Genmai_Commands_KeyEvent.SpecialKey> = [.kanji, .on, .off, .textInput]

  func isVisibleKey(_ key: String) -> Bool {
    var keyEvent = Genmai_Commands_KeyEvent()
    if !KeyParser.parseKey(key, &keyEvent) {
      return false
    }
    if keyEvent.modifierKeys.contains(where: { invisibleModifiers.contains($0) }) {
      return false
    }
    if keyEvent.hasSpecialKey && invisibleKeyEvents.contains(keyEvent.specialKey) {
      return false
    }
    return true
  }

  func isVisibleCommand(_ command: String) -> Bool {
    !invisibleCommands.contains(command)
  }

  /// Returns true if the key map entry is valid; invalid keymaps are not exported/imported.
  func isValidEntry(_ fields: [String]) -> Bool {
    if fields.count < 3 {
      return false
    }
    #if !DEBUG
      if fields[2] == Self.kReportBugCommand {
        return false
      }
    #endif
    return true
  }

  /// Returns true if the key map entry is configurable and we want to show them.
  func isVisibleEntry(_ fields: [String]) -> Bool {
    if fields.count < 3 {
      return false
    }
    return isVisibleKey(fields[1]) && isVisibleCommand(fields[2])
  }
}

@MainActor
@Observable
public final class KeyMapEditorModel {
  static let context = "genmai::gui::KeyMapEditorDialog"
  static let kDirectMode = "DirectInput"
  static let defaultFilename = "keymap.txt"

  /// kKeyMapStatus.
  public static let statuses = [
    "DirectInput", "Precomposition", "Composition", "Conversion", "Suggestion", "Prediction",
  ]

  /// kKeyMaps: the predefined mappings offered by "Import predefined mapping".
  public static let predefinedKeymaps: [(Genmai_Config_Config.SessionKeymap, String)] = [
    (.atok, "ATOK"), (.msime, "MS-IME"), (.kotoeri, "Kotoeri"),
  ]

  /// KeyMapManager::GetKeyMapFileName.
  public static func keyMapFileName(_ keymap: Genmai_Config_Config.SessionKeymap) -> String? {
    switch keymap {
    case .atok: "system://atok.tsv"
    case .mobile: "system://mobile.tsv"
    case .msime: "system://ms-ime.tsv"
    case .kotoeri: "system://kotoeri.tsv"
    case .chromeos: "system://chromeos.tsv"
    case .custom: "user://keymap.tsv"
    case .overlayHenkanMuhenkanToImeOnOff: "system://overlay_henkan_muhenkan_to_ime_on_off.tsv"
    default: nil
    }
  }

  /// The contents of a predefined keymap file.
  public static func predefinedKeymapTable(_ keymap: Genmai_Config_Config.SessionKeymap) -> String {
    guard let file = keyMapFileName(keymap) else { return "" }
    return ConfigFileStream.legacyOpen(file)?.readAllString() ?? ""
  }

  private let validator = KeyMapValidator()
  public let table: GenericTableEditorModel<KeyMapRow>
  /// Sorted (by translated name) command list (commands_delegate_ items), normalized names.
  public let commands: [String]
  public private(set) var serializedTable = ""
  private var invisibleKeymapTable = ""
  private var directModeCommands: Set<String> = []

  public init() {
    table = GenericTableEditorModel(dialogTitle: tr(Self.context, "[ProductName] keymap editor"))
    // get all command names
    var commandNames = Set<String>()
    let manager = KeyMapManager()
    manager.appendAvailableCommandNameDirect(&commandNames)
    manager.appendAvailableCommandNamePrecomposition(&commandNames)
    manager.appendAvailableCommandNameComposition(&commandNames)
    manager.appendAvailableCommandNameConversion(&commandNames)
    manager.appendAvailableCommandNameZeroQuerySuggestion(&commandNames)
    manager.appendAvailableCommandNameSuggestion(&commandNames)
    manager.appendAvailableCommandNamePrediction(&commandNames)
    let visible = commandNames.filter { KeyMapValidator().isVisibleCommand($0) }
    commands = visible.sorted { Self.translate($0) < Self.translate($1) }
  }

  public convenience init(currentKeymap: String) {
    self.init()
    _ = loadFromString(currentKeymap)
  }

  static func translate(_ name: String) -> String { tr(context, name) }

  /// LoadFromStream.
  @discardableResult
  public func loadFromString(_ text: String) -> Bool {
    let lines = tableEditorLines(text)
    guard !lines.isEmpty else {  // must have 1st line
      return false
    }
    var rows: [KeyMapRow] = []
    invisibleKeymapTable = ""
    directModeCommands = []
    for line in lines.dropFirst() {
      if line.isEmpty || line.hasPrefix("#") {
        continue
      }
      let fields = splitTabSkipEmpty(line)
      if fields.count < 3 {
        continue
      }
      let (status, key, command) = (fields[0], fields[1], fields[2])
      // don't accept invalid keymap entries.
      if !validator.isValidEntry(fields) {
        continue
      }
      // don't show invisible (not configurable) keymap entries.
      if !validator.isVisibleEntry(fields) {
        invisibleKeymapTable += "\(status)\t\(key)\t\(command)\n"
        continue
      }
      if status == Self.kDirectMode {
        directModeCommands.insert(key)
      }
      rows.append(KeyMapRow(status: status, key: key, command: command))
    }
    table.rows = rows
    table.selection = []
    return true
  }

  /// Update().
  @discardableResult
  public func update() -> Bool {
    if table.rows.isEmpty {
      table.warn(
        tr(
          Self.context,
          "Current keymap table is empty. You might want to import a pre-defined keymap table first."))
      return false
    }
    var newDirectModeCommands: Set<String> = []
    var result = "status\tkey\tcommand\n"
    for row in table.rows {
      // Rows whose status / command are not in the delegates' lists are dropped
      // (the "Unsupported i18n status/command name" branches).
      guard Self.statuses.contains(row.status), commands.contains(row.command) else {
        continue
      }
      if !validator.isVisibleKey(row.key) {
        table.warn(tr(Self.context, "Invalid key:\n%1").replacingOccurrences(of: "%1", with: row.key))
        return false
      }
      result += "\(row.status)\t\(row.key)\t\(row.command)\n"
      if row.status == Self.kDirectMode {
        newDirectModeCommands.insert(row.key)
      }
    }
    result += invisibleKeymapTable
    // The "Changes of keymaps for direct input mode..." notice is shown only on Windows/Linux.
    directModeCommands = newDirectModeCommands
    serializedTable = result
    return true
  }

  public var canRemoveOrExport: Bool { !table.rows.isEmpty }
  public var okEnabled: Bool { !table.rows.isEmpty }

  public func confirmOverwrite(_ action: @escaping @MainActor @Sendable () -> Void) {
    if table.rows.isEmpty {
      action()
      return
    }
    table.ask(tr(Self.context, "Do you want to overwrite the current keymaps?"), action)
  }

  public func importPredefined(_ keymap: Genmai_Config_Config.SessionKeymap) {
    loadFromString(Self.predefinedKeymapTable(keymap))
  }

  public func importFile(_ url: URL) {
    guard let text = table.readImportFile(url) else { return }
    if !loadFromString(text) {
      table.warn(tr("genmai::gui::GenericTableEditorDialog", "Import failed"))
    }
  }
}

/// The keymap editor sheet. `onFinish` receives the new keymap table on OK, or nil on cancel.
public struct KeyMapEditorView: View {
  @State private var model: KeyMapEditorModel
  @State private var isImporting = false
  private let onFinish: (String?) -> Void

  public init(currentKeymap: String, onFinish: @escaping (String?) -> Void) {
    _model = State(initialValue: KeyMapEditorModel(currentKeymap: currentKeymap))
    self.onFinish = onFinish
  }

  public var body: some View {
    @Bindable var table = model.table
    EditorSheet(
      title: TableEditorStrings.text(.keymapTitle),
      message: TableEditorStrings.text(.keymapMessage),
      okEnabled: model.okEnabled,
      onCancel: { onFinish(nil) },
      onOK: {
        if model.update() {
          onFinish(model.serializedTable)
        }
      }
    ) {
      TableEditorBox(
        canRemove: model.canRemoveOrExport && !table.selection.isEmpty,
        moreItems: moreItems,
        onAdd: { model.table.addNewItem() },
        onRemove: { model.table.deleteSelectedItems() }
      ) {
        KeyMapGrid(table: model.table, commands: model.commands)
      }
    }
    .frame(minWidth: 600, minHeight: 440)
    .genmaiMessageAlert($table.pendingMessage)
    .tableEditorImporter(isPresented: $isImporting) { model.importFile($0) }
  }

  private var moreItems: [TableEditorMenuItem] {
    let model = model
    let predefined = KeyMapEditorModel.predefinedKeymaps.map { keymap, name in
      TableEditorMenuItem.action(tr(KeyMapEditorModel.context, name)) {
        model.confirmOverwrite { model.importPredefined(keymap) }
      }
    }
    return [
      .submenu(TableEditorStrings.text(.importPreset), predefined),
      .divider,
      .action(TableEditorStrings.text(.importFromFile)) {
        model.confirmOverwrite { isImporting = true }
      },
      .action(TableEditorStrings.text(.exportToFile), enabled: model.canRemoveOrExport) {
        guard model.update(),
          let url = TableEditorSavePanel.run(defaultFilename: KeyMapEditorModel.defaultFilename)
        else { return }
        model.table.writeExportFile(url, model.serializedTable)
      },
    ]
  }
}

struct KeyMapGrid: View {
  @Bindable var table: GenericTableEditorModel<KeyMapRow>
  let commands: [String]
  @State private var editingKey: KeyEditTarget?

  var body: some View {
    let context = KeyMapEditorModel.context
    Table($table.rows, selection: $table.selection) {
      TableColumn(tr(context, "Mode")) { $row in
        NamePicker(selection: $row.status, names: KeyMapEditorModel.statuses)
      }
      .width(min: 120, ideal: 140)
      TableColumn(tr(context, "Key")) { $row in
        KeyMapKeyCell(key: row.key)
      }
      .width(min: 80, ideal: 100)
      TableColumn(tr(context, "Command")) { $row in
        NamePicker(selection: $row.command, names: commands)
      }
    }
    .tableStyle(.inset(alternatesRowBackgrounds: true))
    .contextMenu(forSelectionType: UUID.self) { ids in
      TableEditorContextMenu(
        onEdit: ids.count == 1 ? { editingKey = ids.first.map(KeyEditTarget.init) } : nil,
        onNew: { table.addNewItem() },
        onRemove: {
          if !ids.isEmpty { table.selection = ids }
          table.deleteSelectedItems()
        })
    } primaryAction: { ids in
      if ids.count == 1 {
        editingKey = ids.first.map(KeyEditTarget.init)
      }
    }
    .sheet(item: $editingKey) { target in
      let id = target.id
      KeyBindingEditorView(binding: table.rows.first { $0.id == id }?.key ?? "") { binding in
        if let binding, let index = table.rows.firstIndex(where: { $0.id == id }) {
          table.rows[index].key = binding
        }
        editingKey = nil
      }
    }
  }
}

/// The key of a row with macOS key symbols ("⌃⇧A"); double-clicking the row opens the key binding editor.
struct KeyMapKeyCell: View {
  let key: String

  var body: some View {
    Text(verbatim: KeyDisplayFormatter.display(key))
      .help(key)
      .accessibilityLabel(key)
  }
}

/// Shows Mozc key strings ("Ctrl Shift a", "Backspace") the way macOS menus show shortcuts ("⌃⇧A", "⌫").
/// Display only: the keymap keeps Mozc's names.
enum KeyDisplayFormatter {
  /// Modifiers in the macOS order (⌃⌥⇧⌘).
  static let modifiers: [(name: String, symbol: String)] = [
    ("Ctrl", "⌃"), ("Option", "⌥"), ("Alt", "⌥"), ("Shift", "⇧"), ("Command", "⌘"),
  ]

  static let keys: [String: String] = [
    "Backspace": "⌫", "Delete": "⌦", "Enter": "↩", "Tab": "⇥", "Escape": "⎋", "Left": "←", "Right": "→",
    "Up": "↑", "Down": "↓", "Home": "↖", "End": "↘", "PageUp": "⇞", "PageDown": "⇟",
  ]

  static func display(_ key: String) -> String {
    let parts = key.split(separator: " ").map(String.init)
    var symbols = ""
    for (name, symbol) in modifiers where parts.contains(name) && !symbols.contains(symbol) {
      symbols += symbol
    }
    let names = parts.filter { part in !modifiers.contains { $0.name == part } }
    let rest = names.map { name in
      if let symbol = keys[name] { return symbol }
      return name.count == 1 ? name.uppercased() : name
    }
    return symbols + rest.joined(separator: " ")
  }
}

/// The ComboBoxDelegate: a borderless menu over normalized names shown translated.
struct NamePicker: View {
  @Binding var selection: String
  let names: [String]

  var body: some View {
    Menu {
      Picker(selection: $selection) {
        if !names.contains(selection) {
          // Unknown names are shown as is (tr() of an unknown string) and dropped on Update().
          Text(verbatim: KeyMapEditorModel.translate(selection)).tag(selection)
        }
        ForEach(names, id: \.self) { name in
          Text(verbatim: KeyMapEditorModel.translate(name)).tag(name)
        }
      } label: {
        EmptyView()
      }
      .pickerStyle(.inline)
      .labelsHidden()
    } label: {
      Text(verbatim: KeyMapEditorModel.translate(selection))
    }
    .menuStyle(.borderlessButton)
    .accessibilityValue(KeyMapEditorModel.translate(selection))
  }
}

/// The row whose key is being edited with the key binding editor.
struct KeyEditTarget: Identifiable {
  let id: UUID
}
