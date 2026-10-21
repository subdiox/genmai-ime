// Port of mozc/src/gui/config_dialog/roman_table_editor.{h,cc} (3.35.6354).

import Foundation
import GenmaiBase
import Observation
import SwiftUI

public struct RomanTableRow: TableEditorRow {
  public let id: UUID
  public var input: String
  public var output: String
  public var pending: String

  public init(id: UUID = UUID(), input: String, output: String, pending: String) {
    self.id = id
    self.input = input
    self.output = output
    self.pending = pending
  }

  public static func empty() -> RomanTableRow { RomanTableRow(input: "", output: "", pending: "") }
}

@MainActor
@Observable
public final class RomanTableEditorModel {
  static let kRomanTableFile = "system://romanji-hiragana.tsv"
  static let defaultFilename = "romantable.txt"

  public let table: GenericTableEditorModel<RomanTableRow>
  /// The serialized table built by `update()` (GenericTableEditorDialog::table()).
  public private(set) var serializedTable = ""

  public init() {
    table = GenericTableEditorModel(
      dialogTitle: tr("genmai::gui::RomanTableEditorDialog", "[ProductName] settings"))
  }

  public var windowTitle: String {
    tr("genmai::gui::RomanTableEditorDialog", "[ProductName] Romaji table editor")
  }

  /// Initializes the editor like RomanTableEditorDialog::Show.
  public convenience init(currentRomanTable: String) {
    self.init()
    if currentRomanTable.isEmpty {
      loadDefaultRomanTable()
    } else {
      _ = loadFromString(currentRomanTable)
    }
  }

  /// GetDefaultRomanTable(): the embedded table normalized to "input\toutput[\tpending]\n" lines.
  public static func defaultRomanTable() -> String {
    let text = ConfigFileStream.legacyOpen(kRomanTableFile)?.readAllString() ?? ""
    var result = ""
    for line in tableEditorLines(text) where !line.isEmpty {
      let fields = splitTabAllowEmpty(line)
      if fields.count < 2 {
        continue
      }
      result += fields[0] + "\t" + fields[1]
      if fields.count >= 3 {
        result += "\t" + fields[2]
      }
      result += "\n"
    }
    return result
  }

  /// LoadFromStream.
  @discardableResult
  public func loadFromString(_ text: String) -> Bool {
    var rows: [RomanTableRow] = []
    for line in tableEditorLines(text) where !line.isEmpty {
      var fields = splitTabAllowEmpty(line)
      if fields.count < 2 {
        continue
      }
      if fields.count == 2 {
        fields.append("")
      }
      rows.append(RomanTableRow(input: fields[0], output: fields[1], pending: fields[2]))
      if rows.count >= GenericTableEditorModel<RomanTableRow>.maxEntrySize {
        table.warn(
          tr("genmai::gui::RomanTableEditorDialog", "You can't have more than %1 entries")
            .replacingOccurrences(
              of: "%1", with: String(GenericTableEditorModel<RomanTableRow>.maxEntrySize)))
        break
      }
    }
    table.rows = rows
    table.selection = []
    return true
  }

  /// LoadDefaultRomanTable.
  public func loadDefaultRomanTable() {
    loadFromString(ConfigFileStream.legacyOpen(Self.kRomanTableFile)?.readAllString() ?? "")
  }

  /// Update(): validates and serializes the table. Returns false if the dialog must stay open.
  @discardableResult
  public func update() -> Bool {
    if table.rows.isEmpty {
      table.warn(tr("genmai::gui::RomanTableEditorDialog", "Romaji to Kana table is empty."))
      return false
    }
    var containsCapital = false
    var result = ""
    for row in table.rows {
      if row.input.isEmpty || (row.output.isEmpty && row.pending.isEmpty) {
        continue
      }
      result += row.input + "\t" + row.output
      if !row.pending.isEmpty {
        result += "\t" + row.pending
      }
      result += "\n"
      if !containsCapital {
        var lower = row.input
        Util.lowerString(&lower)
        containsCapital = lower != row.input
      }
    }
    serializedTable = result
    if containsCapital {
      table.inform(
        tr(
          "genmai::gui::RomanTableEditorDialog",
          "Input fields contain capital characters. \"Shift-mode-switch\" function should be Off with this new mapping."
        ))
    }
    return true
  }

  /// The value Show() writes to |new_roman_table| on accept: empty if the table equals the default.
  public func acceptedRomanTable() -> String {
    serializedTable == Self.defaultRomanTable() ? "" : serializedTable
  }

  // MARK: - Menu (OnEditMenuAction / UpdateMenuStatus)

  public var canRemoveOrReset: Bool { !table.rows.isEmpty }
  public var okEnabled: Bool { !table.rows.isEmpty }

  /// Runs `action` after the overwrite confirmation when the table is not empty.
  public func confirmOverwrite(_ action: @escaping @MainActor @Sendable () -> Void) {
    if table.rows.isEmpty {
      action()
      return
    }
    table.ask(
      tr("genmai::gui::RomanTableEditorDialog", "Do you want to overwrite the current roman table?"),
      action)
  }

  public func importFile(_ url: URL) {
    guard let text = table.readImportFile(url) else { return }
    if !loadFromString(text) {
      table.warn(tr("genmai::gui::GenericTableEditorDialog", "Import failed"))
    }
  }
}

/// The romaji table editor dialog. `onFinish` receives the new table on OK (empty == default) or nil.
public struct RomanTableEditorView: View {
  @State private var model: RomanTableEditorModel
  @State private var isImporting = false
  /// Set when OK succeeded but an information message must be read before the dialog closes.
  @State private var finishAfterMessage = false
  private let onFinish: (String?) -> Void

  public init(currentRomanTable: String, onFinish: @escaping (String?) -> Void) {
    _model = State(initialValue: RomanTableEditorModel(currentRomanTable: currentRomanTable))
    self.onFinish = onFinish
  }

  public var body: some View {
    @Bindable var table = model.table
    VStack(spacing: 12) {
      RomanTableGrid(table: model.table)
      TableEditorButtonBar(
        menuItems: menuItems,
        okEnabled: model.okEnabled,
        onCancel: { onFinish(nil) },
        onOK: {
          if model.update() {
            if model.table.pendingMessage == nil {
              onFinish(model.acceptedRomanTable())
            } else {
              finishAfterMessage = true
            }
          }
        })
    }
    .padding(12)
    .frame(minWidth: 330, minHeight: 350)
    .navigationTitle(model.windowTitle)
    .genmaiMessageAlert($table.pendingMessage)
    .onChange(of: table.pendingMessage) { _, message in
      if message == nil, finishAfterMessage {
        onFinish(model.acceptedRomanTable())
      }
    }
    .tableEditorImporter(isPresented: $isImporting) { model.importFile($0) }
  }

  private var menuItems: [TableEditorMenuItem] {
    let context = "genmai::gui::RomanTableEditorDialog"
    let model = model
    return [
      .action(tr(context, "New entry")) { model.table.addNewItem() },
      .action(tr(context, "Remove selected entries"), enabled: model.canRemoveOrReset) {
        model.table.deleteSelectedItems()
      },
      .divider,
      .action(tr(context, "Import from file...")) {
        model.confirmOverwrite { isImporting = true }
      },
      .action(tr(context, "Export to file...")) {
        guard model.update(), let url = TableEditorSavePanel.run(
          defaultFilename: RomanTableEditorModel.defaultFilename)
        else { return }
        model.table.writeExportFile(url, model.serializedTable)
      },
      .divider,
      .action(tr(context, "Reset to defaults"), enabled: model.canRemoveOrReset) {
        model.confirmOverwrite { model.loadDefaultRomanTable() }
      },
    ]
  }
}

struct RomanTableGrid: View {
  @Bindable var table: GenericTableEditorModel<RomanTableRow>

  var body: some View {
    let context = "genmai::gui::RomanTableEditorDialog"
    Table($table.rows, selection: $table.selection) {
      TableColumn(tr(context, "Input")) { $row in
        TextField("", text: $row.input)
      }
      TableColumn(tr(context, "Output")) { $row in
        TextField("", text: $row.output)
      }
      TableColumn(tr(context, "Next input")) { $row in
        TextField("", text: $row.pending)
      }
    }
    .contextMenu(forSelectionType: UUID.self) { ids in
      TableEditorContextMenu(
        canEdit: false,
        onEdit: {},
        onNew: { table.addNewItem() },
        onRemove: {
          if !ids.isEmpty { table.selection = ids }
          table.deleteSelectedItems()
        })
    }
  }
}
