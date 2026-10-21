// Port of mozc/src/gui/config_dialog/generic_table_editor.{h,cc,ui} and gui/base/table_util (3.35.6354).
//
// The Qt GenericTableEditorDialog is a QDialog with a QTableWidget, an "Edit" menu button and OK/Cancel.
// Subclasses (KeyMapEditorDialog, RomanTableEditorDialog) override LoadFromStream / Update / UpdateMenuStatus.
// In Swift the shared row operations live in `GenericTableEditorModel<Row>` (composition instead of
// inheritance), and `TableEditorChrome` renders the common dialog chrome (Edit menu, OK/Cancel).

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

// MARK: - Views

/// The actions of the Edit menu of a concrete editor.
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

/// The "Edit" button with its menu (editButton + edit_menu_).
struct TableEditorEditMenu: View {
  let items: [TableEditorMenuItem]

  var body: some View {
    Menu {
      TableEditorMenuContent(items: items)
    } label: {
      Text(verbatim: tr("GenericTableEditorDialog", "Edit"))
    }
    .fixedSize()
  }
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

/// The bottom bar of the generic table editor: Edit menu on the left, Cancel / OK on the right.
struct TableEditorButtonBar: View {
  let menuItems: [TableEditorMenuItem]
  let okEnabled: Bool
  let onCancel: () -> Void
  let onOK: () -> Void

  var body: some View {
    HStack {
      TableEditorEditMenu(items: menuItems)
      Spacer()
      Button(tr("genmai::gui::ConfigDialog", "Cancel"), role: .cancel, action: onCancel)
        .keyboardShortcut(.cancelAction)
      Button("OK", action: onOK)
        .keyboardShortcut(.defaultAction)
        .disabled(!okEnabled)
    }
  }
}

/// Context menu of a table row (OnContextMenuRequested).
struct TableEditorContextMenu: View {
  let canEdit: Bool
  let onEdit: () -> Void
  let onNew: () -> Void
  let onRemove: () -> Void

  var body: some View {
    if canEdit {
      Button(tr("genmai::gui::GenericTableEditorDialog", "Edit entry"), action: onEdit)
    }
    Button(tr("genmai::gui::GenericTableEditorDialog", "New entry"), action: onNew)
    Button(tr("genmai::gui::GenericTableEditorDialog", "Remove entry"), action: onRemove)
  }
}

extension View {
  /// `QFileDialog::getOpenFileName(tr("import from file"))` / `getSaveFileName(tr("export to file"))`.
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
    panel.title = tr("genmai::gui::GenericTableEditorDialog", "export to file")
    panel.nameFieldStringValue = defaultFilename
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
    return panel.runModal() == .OK ? panel.url : nil
  }
}
