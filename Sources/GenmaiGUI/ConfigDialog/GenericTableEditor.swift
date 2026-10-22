// Port of mozc/src/gui/config_dialog/generic_table_editor.{h,cc,ui} and gui/base/table_util (3.35.6354).
//
// The Qt GenericTableEditorDialog is a QDialog with a QTableWidget, an "Edit" menu button and OK/Cancel.
// Subclasses (KeyMapEditorDialog, RomanTableEditorDialog) override LoadFromStream / Update / UpdateMenuStatus.
// In Swift the shared row operations live in `GenericTableEditorModel<Row>` (composition instead of
// inheritance). The views are Genmai's own sheet layout instead of the Qt dialog: `EditorSheet` (title,
// explanation, content, Cancel / OK) and `TableEditorBox` (the table with +/− buttons and a "More" menu under it,
// like the lists of System Settings). Their strings are in `TableEditorStrings`.

import AppKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// A row of a table editor.
public protocol TableEditorRow: Identifiable, Equatable, Sendable where ID == UUID {
  /// An empty row (InsertEmptyItem).
  static func empty() -> Self
}

/// Splits text into lines the way `std::getline` + `Util::ChopReturns` do in the table editors:
/// lines are separated by '\n', trailing '\r'/'\n' are removed, and the trailing empty piece after a final
/// '\n' is not a line.
func tableEditorLines(_ text: String) -> [String] {
  if text.isEmpty {
    return []
  }
  var lines = text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false).map {
    String(String.UnicodeScalarView($0))
  }
  if text.unicodeScalars.last == "\n" {
    lines.removeLast()
  }
  return lines.map { line in
    var scalars = Substring(line).unicodeScalars
    while let last = scalars.last, last == "\r" || last == "\n" {
      scalars.removeLast()
    }
    return String(scalars)
  }
}

/// `absl::StrSplit(line, '\t', absl::AllowEmpty())`.
func splitTabAllowEmpty(_ line: String) -> [String] {
  line.unicodeScalars.split(separator: "\t", omittingEmptySubsequences: false).map {
    String(String.UnicodeScalarView($0))
  }
}

/// `absl::StrSplit(line, '\t', absl::SkipEmpty())`.
func splitTabSkipEmpty(_ line: String) -> [String] {
  splitTabAllowEmpty(line).filter { !$0.isEmpty }
}

@MainActor
@Observable
public final class GenericTableEditorModel<Row: TableEditorRow> {
  /// kMaxEntrySize.
  public static var maxEntrySize: Int { 10000 }

  public var rows: [Row] = []
  public var selection: Set<UUID> = []
  /// The row whose first cell should get focus after InsertEmptyItem.
  public var focusedRowID: UUID?
  /// Pending QMessageBox.
  public var pendingMessage: GUIMessage?

  /// The window title used for message boxes.
  public var dialogTitle: String

  public init(dialogTitle: String) {
    self.dialogTitle = dialogTitle
  }

  public var rowCount: Int { rows.count }

  // MARK: - GenericTableEditorDialog slots

  /// InsertEmptyItem(row).
  public func insertEmptyItem(at index: Int) {
    let row = Row.empty()
    rows.insert(row, at: min(max(index, 0), rows.count))
    selection = [row.id]
    focusedRowID = row.id
  }

  /// InsertItem(): inserts after the current item.
  public func insertItem() {
    guard let current = currentRowIndex else {
      warn(tr("genmai::gui::GenericTableEditorDialog", "No entry is selected"))
      return
    }
    insertEmptyItem(at: current + 1)
  }

  /// AddNewItem().
  public func addNewItem() {
    if rows.count >= Self.maxEntrySize {
      warn(
        tr("genmai::gui::GenericTableEditorDialog", "You can't have more than %1 entries")
          .replacingOccurrences(of: "%1", with: String(Self.maxEntrySize)))
      return
    }
    insertEmptyItem(at: rows.count)
  }

  /// DeleteSelectedItems().
  public func deleteSelectedItems() {
    let indices = rows.indices.filter { selection.contains(rows[$0].id) }
    guard let last = indices.last else {
      warn(tr("genmai::gui::GenericTableEditorDialog", "No entry is selected"))
      return
    }
    // Keep the current cursor position after the deletion.
    var nextSelection: UUID?
    if last + 1 < rows.count {
      nextSelection = rows[last + 1].id
    } else if last - 1 >= 0 {
      nextSelection = rows[last - 1].id
    }
    for index in indices.reversed() {
      rows.remove(at: index)
    }
    if let nextSelection, rows.contains(where: { $0.id == nextSelection }) {
      selection = [nextSelection]
    } else {
      selection = []
    }
  }

  /// The row index of the "current item" (the last selected row).
  public var currentRowIndex: Int? {
    rows.indices.last { selection.contains(rows[$0].id) }
  }

  public func warn(_ text: String) {
    pendingMessage = GUIMessage(kind: .warning, title: dialogTitle, text: text)
  }

  public func inform(_ text: String) {
    pendingMessage = GUIMessage(kind: .information, title: dialogTitle, text: text)
  }

  /// QMessageBox::question(Ok | Cancel); `action` runs on Ok.
  public func ask(_ text: String, _ action: @escaping @MainActor @Sendable () -> Void) {
    pendingMessage = GUIMessage(kind: .question, title: dialogTitle, text: text, onYes: action)
  }

  // MARK: - Import / Export (GenericTableEditorDialog::Import / Export)

  /// The checks of GenericTableEditorDialog::Import before LoadFromStream. Returns the file contents.
  public func readImportFile(_ url: URL) -> String? {
    let path = url.path
    guard FileManager.default.fileExists(atPath: path) else {
      warn(tr("genmai::gui::GenericTableEditorDialog", "File not found"))
      return nil
    }
    let kMaxSize: Int64 = 100 * 1024
    let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
    if size >= kMaxSize {
      warn(tr("genmai::gui::GenericTableEditorDialog", "The specified file is too large (>=100K byte)"))
      return nil
    }
    guard let data = FileManager.default.contents(atPath: path) else {
      warn(tr("genmai::gui::GenericTableEditorDialog", "Import failed"))
      return nil
    }
    return String(decoding: data, as: UTF8.self)
  }

  /// Writes `table` for Export().
  public func writeExportFile(_ url: URL, _ table: String) {
    do {
      try Data(table.utf8).write(to: url)
    } catch {
      warn(tr("genmai::gui::GenericTableEditorDialog", "Export failed"))
    }
  }
}

// MARK: - Strings

/// English / Japanese strings of the editor sheets (key bindings, romaji table, key assignment, character forms)
/// that Mozc's Qt translations do not have or word differently.
enum TableEditorStrings {
  enum Key: CaseIterable, Sendable {
    case cancel, ok, addEntry, removeEntries, more, importFromFile, exportToFile, exportPanelTitle, importPreset,
      resetToDefaults, newEntry, changeKey, deleteEntries, keymapTitle, keymapMessage, romanTitle, romanMessage,
      keyBindingTitle, keyBindingMessage, keyBindingPlaceholder, keyBindingInvalid, characterGroup,
      characterComposition, characterConversion, characterFormFootnote
  }

  static let english: [Key: String] = [
    .cancel: "Cancel",
    .ok: "OK",
    .addEntry: "Add Entry",
    .removeEntries: "Remove Selected Entries",
    .more: "More",
    .importFromFile: "Import from File…",
    .exportToFile: "Export to File…",
    .exportPanelTitle: "Export",
    .importPreset: "Import Preset",
    .resetToDefaults: "Reset to Defaults",
    .newEntry: "New Entry",
    .changeKey: "Change Key…",
    .deleteEntries: "Delete",
    .keymapTitle: "Key Bindings",
    .keymapMessage:
      "Choose the command each key runs in each input state. Double-click a row to assign another key.",
    .romanTitle: "Romaji Table",
    .romanMessage:
      "Each romaji sequence you type is replaced by its output. The next input stays in the composition, so “kk” becomes “っ” followed by “k”.",
    .keyBindingTitle: "Assign a Key",
    .keyBindingMessage: "Press the key or key combination to assign.",
    .keyBindingPlaceholder: "Press a Key",
    .keyBindingInvalid: "This key combination can’t be assigned.",
    .characterGroup: "Characters",
    .characterComposition: "Composition",
    .characterConversion: "Conversion",
    .characterFormFootnote: "“Remember” uses the width you chose last time.",
  ]

  static let japanese: [Key: String] = [
    .cancel: "キャンセル",
    .ok: "OK",
    .addEntry: "エントリーを追加",
    .removeEntries: "選択したエントリーを削除",
    .more: "その他",
    .importFromFile: "ファイルからインポート…",
    .exportToFile: "ファイルにエクスポート…",
    .exportPanelTitle: "エクスポート",
    .importPreset: "プリセットを読み込む",
    .resetToDefaults: "初期設定に戻す",
    .newEntry: "エントリーを追加",
    .changeKey: "キーを変更…",
    .deleteEntries: "削除",
    .keymapTitle: "キー操作",
    .keymapMessage: "入力の状態ごとに、キーで実行するコマンドを選びます。行をダブルクリックすると、別のキーを割り当てられます。",
    .romanTitle: "ローマ字テーブル",
    .romanMessage: "入力したローマ字を出力の文字に置き換えます。「次の入力」は出力の後に入力中の文字として残ります（例: kk →「っ」+「k」）。",
    .keyBindingTitle: "キーを割り当てる",
    .keyBindingMessage: "割り当てるキー、またはキーの組み合わせを押してください。",
    .keyBindingPlaceholder: "キーを押してください",
    .keyBindingInvalid: "このキーの組み合わせは割り当てられません。",
    .characterGroup: "文字の種類",
    .characterComposition: "変換前",
    .characterConversion: "変換後",
    .characterFormFootnote: "「学習」は前回使った幅で入力します。",
  ]

  static func text(_ key: Key, language: GUILanguage = .current) -> String {
    let table = language == .japanese ? japanese : english
    return table[key] ?? english[key] ?? ""
  }
}

// MARK: - Views

/// The layout of an editor sheet: title and explanation, the content, and Cancel / OK.
struct EditorSheet<Content: View>: View {
  let title: String
  let message: String
  let okEnabled: Bool
  /// False when Return must reach the content (the key capture field) instead of OK.
  var okIsDefault = true
  let onCancel: () -> Void
  let onOK: () -> Void
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      EditorSheetHeader(title: title, message: message)
      content
      HStack {
        Spacer()
        Button(TableEditorStrings.text(.cancel), role: .cancel, action: onCancel)
          .keyboardShortcut(.cancelAction)
        if okIsDefault {
          Button(TableEditorStrings.text(.ok), action: onOK)
            .keyboardShortcut(.defaultAction)
            .disabled(!okEnabled)
        } else {
          Button(TableEditorStrings.text(.ok), action: onOK)
            .buttonStyle(.borderedProminent)
            .disabled(!okEnabled)
        }
      }
      .controlSize(.regular)
    }
    .padding(20)
  }
}

struct EditorSheetHeader: View {
  let title: String
  let message: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(verbatim: title)
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      Text(verbatim: message)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// A table with +/− buttons and a "More" menu under it, in a rounded box.
struct TableEditorBox<Content: View>: View {
  let canRemove: Bool
  let moreItems: [TableEditorMenuItem]
  let onAdd: () -> Void
  let onRemove: () -> Void
  @ViewBuilder let content: Content

  var body: some View {
    VStack(spacing: 0) {
      content
      Divider()
      TableEditorControlBar(
        canRemove: canRemove, moreItems: moreItems, onAdd: onAdd, onRemove: onRemove)
    }
    .background(Color(nsColor: .controlBackgroundColor))
    .clipShape(.rect(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(.separator)
    }
  }
}

/// + / − and the "More" menu.
struct TableEditorControlBar: View {
  let canRemove: Bool
  let moreItems: [TableEditorMenuItem]
  let onAdd: () -> Void
  let onRemove: () -> Void

  var body: some View {
    HStack(spacing: 0) {
      Button(action: onAdd) {
        Image(systemName: "plus")
          .frame(width: 24, height: 22)
          .contentShape(.rect)
      }
      .help(TableEditorStrings.text(.addEntry))
      .accessibilityLabel(TableEditorStrings.text(.addEntry))
      Divider()
        .frame(height: 14)
      Button(action: onRemove) {
        Image(systemName: "minus")
          .frame(width: 24, height: 22)
          .contentShape(.rect)
      }
      .disabled(!canRemove)
      .help(TableEditorStrings.text(.removeEntries))
      .accessibilityLabel(TableEditorStrings.text(.removeEntries))
      Spacer()
      Menu {
        TableEditorMenuContent(items: moreItems)
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .help(TableEditorStrings.text(.more))
      .accessibilityLabel(TableEditorStrings.text(.more))
      .padding(.trailing, 6)
    }
    .buttonStyle(.borderless)
    .padding(.horizontal, 4)
    .frame(height: 26)
  }
}

/// An item of the "More" menu of a concrete editor.
struct TableEditorMenuItem: Identifiable {
  enum Kind {
    case action(title: String, enabled: Bool, perform: @MainActor () -> Void)
    case submenu(title: String, items: [TableEditorMenuItem])
    case divider
  }

  let id = UUID()
  let kind: Kind

  static func action(_ title: String, enabled: Bool = true, _ perform: @escaping @MainActor () -> Void)
    -> TableEditorMenuItem
  {
    TableEditorMenuItem(kind: .action(title: title, enabled: enabled, perform: perform))
  }

  static func submenu(_ title: String, _ items: [TableEditorMenuItem]) -> TableEditorMenuItem {
    TableEditorMenuItem(kind: .submenu(title: title, items: items))
  }

  static var divider: TableEditorMenuItem { TableEditorMenuItem(kind: .divider) }
}

struct TableEditorMenuContent: View {
  let items: [TableEditorMenuItem]

  var body: some View {
    ForEach(items) { item in
      switch item.kind {
      case .action(let title, let enabled, let perform):
        Button(title) { perform() }
          .disabled(!enabled)
      case .submenu(let title, let items):
        Menu(title) {
          TableEditorMenuContent(items: items)
        }
      case .divider:
        Divider()
      }
    }
  }
}

/// Context menu of table rows (OnContextMenuRequested).
struct TableEditorContextMenu: View {
  /// The "Change Key…" action, when the editor has one and a single row is clicked.
  let onEdit: (() -> Void)?
  let onNew: () -> Void
  let onRemove: () -> Void

  var body: some View {
    if let onEdit {
      Button(TableEditorStrings.text(.changeKey), action: onEdit)
      Divider()
    }
    Button(TableEditorStrings.text(.newEntry), action: onNew)
    Button(TableEditorStrings.text(.deleteEntries), action: onRemove)
  }
}

extension View {
  /// `QFileDialog::getOpenFileName(tr("import from file"))`.
  @MainActor
  func tableEditorImporter(isPresented: Binding<Bool>, onPick: @escaping (URL) -> Void) -> some View {
    fileImporter(isPresented: isPresented, allowedContentTypes: [.data, .plainText, .text]) { result in
      if case .success(let url) = result {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        onPick(url)
      }
    }
  }
}

/// Presents NSSavePanel for Export() (fileExporter needs a FileDocument; the panel is simpler here).
@MainActor
enum TableEditorSavePanel {
  static func run(defaultFilename: String) -> URL? {
    let panel = NSSavePanel()
    panel.title = TableEditorStrings.text(.exportPanelTitle)
    panel.nameFieldStringValue = defaultFilename
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
    return panel.runModal() == .OK ? panel.url : nil
  }
}
