// SwiftUI replacement of mozc/src/gui/dictionary_tool/dictionary_tool.ui + dictionary_tool.cc (widget setup,
// toolbar, context menus) and dictionary_content_table_widget / zero_width_splitter (3.35.6354).
//
// Layout: dictionary list | entry table (HSplitView, 1:3 like the Qt splitter), a toolbar with the "Tools"
// menu, "Add" and "Remove", and a status line "<dictionary>: <n> entries".

import AppKit
import GenmaiClient
import SwiftUI

private let kContext = "genmai::gui::DictionaryTool"

private func trDT(_ source: String) -> String { tr(kContext, source) }

public struct DictionaryToolView: View {
  @State private var model: DictionaryToolModel
  @Environment(\.closeDialog) private var closeDialog

  public init(client: any GenmaiClientProtocol) {
    _model = State(initialValue: DictionaryToolModel(client: client))
  }

  init(model: DictionaryToolModel) {
    _model = State(initialValue: model)
  }

  public var body: some View {
    @Bindable var model = model
    Group {
      switch model.availability {
      case .available:
        DictionaryToolContent(model: model)
      case .unavailable(let message):
        UnavailableView(message: message, title: model.windowTitle) { closeDialog() }
      }
    }
    .frame(minWidth: 640, minHeight: 400)
    .navigationTitle(tr("DictionaryTool", "[ProductName] Dictionary Tool"))
    .genmaiMessageAlert($model.pendingMessage)
  }
}

private struct UnavailableView: View {
  let message: String
  let title: String
  let close: () -> Void
  @State private var isPresented = true

  var body: some View {
    Color.clear
      .alert(title, isPresented: $isPresented) {
        Button("OK", action: close)
      } message: {
        Text(verbatim: message)
      }
  }
}

private struct DictionaryToolContent: View {
  @Bindable var model: DictionaryToolModel

  var body: some View {
    VStack(spacing: 0) {
      HSplitView {
        DictionaryListView(model: model)
          .frame(minWidth: 140, idealWidth: 180, maxWidth: 320)
        DictionaryContentTable(model: model)
          .frame(minWidth: 400)
      }
      Divider()
      StatusBar(message: model.statusMessage)
    }
    .toolbar { DictionaryToolToolbar(model: model) }
    .sheet(item: $model.importMode) { mode in
      ImportDialogView(mode: mode) { result in
        if let result {
          model.completeImport(
            mode: mode, fileName: result.fileName, dicName: result.dicName, imeType: result.imeType,
            encodingType: result.encodingType)
        } else {
          model.importMode = nil
        }
      }
    }
    .sheet(isPresented: $model.isFindDialogShown) {
      FindDialogView(model: model)
    }
    .modifier(PromptModifier(model: model))
    .onDisappear { model.close() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
      // When application focus leaves, save so that the new dictionary can be loaded (the Qt version delays
      // OnDeactivate by 200 msec so that pending edits are committed first).
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(200))
        model.onDeactivate()
      }
    }
  }
}

extension DictionaryToolModel.ImportMode: Identifiable {
  public var id: Self { self }
}

private struct StatusBar: View {
  let message: String

  var body: some View {
    HStack {
      Text(verbatim: message)
        .font(.callout)
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
  }
}

// MARK: - Toolbar

private struct DictionaryToolToolbar: ToolbarContent {
  let model: DictionaryToolModel

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .primaryAction) {
      Menu(trDT("Tools")) {
        Button(trDT("New dictionary...")) { model.requestCreateDictionary() }
          .disabled(!model.canCreateDictionary)
        Button(trDT("Rename dictionary...")) { model.requestRenameDictionary() }
          .disabled(!model.hasCurrentDictionary)
        Button(trDT("Delete dictionary")) { model.requestDeleteDictionary() }
          .disabled(model.dictionaries.isEmpty)
        Button(trDT("Find...")) { model.isFindDialogShown = true }
        Divider()
        Button(trDT("Import as new dictionary...")) { model.requestImportAndCreateDictionary() }
          .disabled(!model.canCreateDictionary)
        Button(trDT("Import to current dictionary...")) { model.requestImportAndAppendDictionary() }
          .disabled(model.dictionaries.isEmpty || !model.hasCurrentDictionary)
        Button(trDT("Export current dictionary...")) { DictionaryExporter.export(model) }
          .disabled(!model.hasCurrentDictionary)
      }
      // The toolbar would otherwise shrink the menu's title to "管…".
      .fixedSize()
      Button(trDT("Add")) { model.addWord() }
        .disabled(!model.canAddWord)
      Button(trDT("Remove")) { model.requestDeleteWords() }
        .disabled(!model.canDeleteWord)
    }
  }
}

/// QFileDialog::getSaveFileName for "Export dictionary".
@MainActor
enum DictionaryExporter {
  static func export(_ model: DictionaryToolModel) {
    guard model.canStartExport() else { return }
    let panel = NSSavePanel()
    panel.title = trDT("Export dictionary")
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
    panel.allowedContentTypes = [.plainText]
    panel.allowsOtherFileTypes = true
    if panel.runModal() == .OK, let url = panel.url {
      model.exportDictionary(to: url.path)
    }
  }
}

// MARK: - Dictionary list

private struct DictionaryListView: View {
  let model: DictionaryToolModel

  var body: some View {
    List(
      selection: Binding(
        get: { model.selectedDictionaryID },
        set: { model.selectDictionary($0) })
    ) {
      ForEach(model.dictionaries) { item in
        Text(verbatim: item.name)
          .tag(item.id)
          .contextMenu { DictionaryContextMenu(model: model, id: item.id) }
      }
    }
    .listStyle(.sidebar)
  }
}

private struct DictionaryContextMenu: View {
  let model: DictionaryToolModel
  let id: UInt64

  var body: some View {
    Button(trDT("Rename...")) {
      model.selectDictionary(id)
      model.requestRenameDictionary()
    }
    Button(trDT("Delete")) {
      model.selectDictionary(id)
      model.requestDeleteDictionary()
    }
    Button(trDT("Import to this dictionary...")) {
      model.selectDictionary(id)
      model.requestImportAndAppendDictionary()
    }
    Button(trDT("Export this dictionary...")) {
      model.selectDictionary(id)
      DictionaryExporter.export(model)
    }
  }
}

// MARK: - Entry table

private struct DictionaryContentTable: View {
  @Bindable var model: DictionaryToolModel
  @State private var sortOrder: [KeyPathComparator<DictionaryToolModel.Row>] = []

  var body: some View {
    Table(model.rows, selection: $model.selectedRowIDs, sortOrder: $sortOrder) {
      TableColumn(trDT("Reading"), value: \.reading) { row in
        EditableCell(model: model, rowID: row.id, column: .reading, text: row.reading)
      }
      TableColumn(trDT("Word"), value: \.word) { row in
        EditableCell(model: model, rowID: row.id, column: .word, text: row.word)
      }
      TableColumn(trDT("Category"), value: \.category) { row in
        CategoryCell(model: model, rowID: row.id, category: row.category)
      }
      TableColumn(trDT("Comment"), value: \.comment) { row in
        EditableCell(model: model, rowID: row.id, column: .comment, text: row.comment)
      }
    }
    .alternatingRowBackgrounds()
    .disabled(!model.hasCurrentDictionary)
    .onChange(of: sortOrder) { _, newValue in
      guard let comparator = newValue.first else { return }
      let column: DictionaryToolModel.Column =
        switch comparator.keyPath {
        case \DictionaryToolModel.Row.word: .word
        case \DictionaryToolModel.Row.category: .category
        case \DictionaryToolModel.Row.comment: .comment
        default: .reading
        }
      model.sort(by: column, ascending: comparator.order == .forward)
    }
    .contextMenu(forSelectionType: DictionaryToolModel.Row.ID.self) { ids in
      if !ids.isEmpty {
        EntryContextMenu(model: model, ids: ids)
      }
    }
    .onDeleteCommand { model.requestDeleteWords() }
  }
}

private struct EditableCell: View {
  let model: DictionaryToolModel
  let rowID: DictionaryToolModel.Row.ID
  let column: DictionaryToolModel.Column
  let text: String
  @FocusState private var focused: Bool

  var body: some View {
    TextField(
      "",
      text: Binding(get: { text }, set: { model.setCell(rowID, column, $0) })
    )
    .textFieldStyle(.plain)
    .focused($focused)
    .onSubmit { model.onItemChanged(rowID, column) }
    .onChange(of: focused) { _, isFocused in
      if !isFocused {
        model.onItemChanged(rowID, column)
      }
    }
    .onAppear {
      if column == .reading && model.editingRowID == rowID {
        focused = true
      }
    }
  }
}

private struct CategoryCell: View {
  let model: DictionaryToolModel
  let rowID: DictionaryToolModel.Row.ID
  let category: String

  var body: some View {
    Picker(
      "",
      selection: Binding(
        get: { category },
        set: {
          model.setCell(rowID, .category, $0)
          model.onItemChanged(rowID, .category)
        })
    ) {
      ForEach(model.posList, id: \.self) { pos in
        Text(verbatim: pos).tag(pos)
      }
    }
    .labelsHidden()
    .pickerStyle(.menu)
    .buttonStyle(.borderless)
  }
}

private struct EntryContextMenu: View {
  let model: DictionaryToolModel
  let ids: Set<DictionaryToolModel.Row.ID>

  var body: some View {
    let multiple = ids.count > 1
    Button(trDT("Add a word")) { model.addWord() }
    if model.canMoveWords {
      Menu(multiple ? trDT("Move the selected words to") : trDT("Move this word to")) {
        ForEach(model.moveTargets) { target in
          Button(target.name) {
            model.selectedRowIDs = ids
            model.moveSelectedWords(to: target.id)
          }
        }
      }
    }
    Button(multiple ? trDT("Delete the selected words") : trDT("Delete this word")) {
      model.selectedRowIDs = ids
      model.requestDeleteWords()
    }
    Divider()
    Menu(trDT("Change category to")) {
      ForEach(model.posList, id: \.self) { pos in
        Button(pos) {
          model.selectedRowIDs = ids
          model.editPos(pos)
        }
      }
    }
    Button(trDT("Edit comment")) {
      model.selectedRowIDs = ids
      model.requestEditComment()
    }
  }
}

// MARK: - Prompts (QInputDialog)

private struct PromptModifier: ViewModifier {
  @Bindable var model: DictionaryToolModel
  @State private var text = ""

  func body(content: Content) -> some View {
    content
      .alert(
        model.windowTitle,
        isPresented: Binding(get: { model.prompt != nil }, set: { if !$0 { model.prompt = nil } }),
        presenting: model.prompt
      ) { prompt in
        TextField(prompt.label, text: $text)
        Button("OK") { model.completePrompt(prompt, text: text) }
          .disabled(!prompt.allowsEmpty && text.isEmpty)
        Button(tr("FindDialog", "Cancel"), role: .cancel) { model.completePrompt(prompt, text: nil) }
      } message: { prompt in
        Text(verbatim: prompt.label)
      }
      .onChange(of: model.prompt) { _, prompt in
        text = prompt?.initialText ?? ""
      }
  }
}
