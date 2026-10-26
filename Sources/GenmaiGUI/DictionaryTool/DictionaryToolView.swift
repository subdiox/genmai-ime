// SwiftUI replacement of mozc/src/gui/dictionary_tool/dictionary_tool.ui + dictionary_tool.cc (widget setup,
// toolbar, context menus), find_dialog and dictionary_content_table_widget (3.35.6354).
//
// Layout: a sidebar with the dictionaries | the entry table, with a toolbar (add word, delete words, a menu of
// dictionary operations), a search field that finds words (FindDialog: Return finds the next match) and a
// word count below the table.

#if os(macOS)
  import AppKit
  import GenmaiClient
  import SwiftUI

  private let kContext = "genmai::gui::DictionaryTool"

  private func trDT(_ source: String) -> String { tr(kContext, source) }

  private typealias Strings = DictionaryToolStrings

  public struct DictionaryToolView: View {
    @State private var model: DictionaryToolModel

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
          DictionaryUnavailableView(message: message)
        }
      }
      .frame(minWidth: 720, minHeight: 420)
      .navigationTitle(tr("DictionaryTool", "[ProductName] Dictionary Tool"))
      .genmaiMessageAlert($model.pendingMessage)
    }
  }

  /// The storage is locked by another process (the Qt version shows a message box and exits).
  private struct DictionaryUnavailableView: View {
    let message: String
    @Environment(\.closeDialog) private var closeDialog

    var body: some View {
      ContentUnavailableView {
        Label(Strings.text(.unavailableTitle), systemImage: "lock")
      } description: {
        Text(verbatim: message)
      } actions: {
        Button(Strings.text(.close)) { closeDialog() }
          .keyboardShortcut(.defaultAction)
      }
    }
  }

  private struct DictionaryToolContent: View {
    @Bindable var model: DictionaryToolModel
    @State private var searchText = ""
    /// The row the table scrolls to (a found or added word).
    @State private var scrollTarget: DictionaryToolModel.Row.ID?

    var body: some View {
      NavigationSplitView {
        DictionarySidebar(model: model)
          .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 320)
      } detail: {
        DictionaryDetail(model: model, scrollTarget: $scrollTarget)
          .toolbar {
            DictionaryToolToolbar(model: model, find: find)
          }
      }
      .searchable(text: $searchText, placement: .toolbar, prompt: Text(Strings.text(.searchPrompt)))
      .onSubmit(of: .search) { find(.forward) }
      .onChange(of: searchText) { model.resetFind() }
      .onChange(of: model.editingRowID) { _, rowID in
        if let rowID {
          scrollTarget = rowID
        }
      }
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
      .sheet(item: $model.prompt) { prompt in
        PromptSheet(prompt: prompt) { text in model.completePrompt(prompt, text: text) }
      }
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

    /// FindDialog's Up / Down buttons: selects the next match of the search text and scrolls to it.
    private func find(_ direction: DictionaryToolModel.FindDirection) {
      guard !searchText.isEmpty else { return }
      if model.find(searchText, direction: direction), let rowID = model.selectedRowIDs.first {
        scrollTarget = rowID
      }
    }
  }

  extension DictionaryToolModel.ImportMode: Identifiable {
    public var id: Self { self }
  }

  // MARK: - Toolbar

  private struct DictionaryToolToolbar: ToolbarContent {
    let model: DictionaryToolModel
    let find: (DictionaryToolModel.FindDirection) -> Void

    var body: some ToolbarContent {
      ToolbarItemGroup(placement: .primaryAction) {
        Button {
          model.addWord()
        } label: {
          Label(Strings.text(.addWord), systemImage: "plus")
        }
        .help(Strings.text(.addWord))
        .disabled(!model.canAddWord)

        Button {
          model.requestDeleteWords()
        } label: {
          Label(Strings.text(.deleteWords), systemImage: "trash")
        }
        .help(Strings.text(.deleteWords))
        .disabled(!model.canDeleteWord || model.selectedRowIDs.isEmpty)

        DictionaryOperationsMenu(model: model, find: find)
      }
    }
  }

  /// The "Tools" menu of the Qt version.
  private struct DictionaryOperationsMenu: View {
    let model: DictionaryToolModel
    let find: (DictionaryToolModel.FindDirection) -> Void

    var body: some View {
      Menu {
        Section {
          Button(Strings.text(.newDictionaryMenu), systemImage: "plus") { model.requestCreateDictionary() }
            .disabled(!model.canCreateDictionary)
          Button(Strings.text(.renameDictionaryMenu), systemImage: "pencil") { model.requestRenameDictionary() }
            .disabled(!model.hasCurrentDictionary)
          Button(Strings.text(.deleteDictionaryMenu), systemImage: "trash") {
            model.requestDeleteDictionary()
          }
          .disabled(!model.hasCurrentDictionary)
        }
        Section {
          Button(Strings.text(.importAsNewMenu), systemImage: "square.and.arrow.down.on.square") {
            model.requestImportAndCreateDictionary()
          }
          .disabled(!model.canCreateDictionary)
          Button(Strings.text(.importToThisMenu), systemImage: "square.and.arrow.down") {
            model.requestImportAndAppendDictionary()
          }
          .disabled(!model.hasCurrentDictionary)
          Button(Strings.text(.exportCurrentMenu), systemImage: "square.and.arrow.up") {
            DictionaryExporter.export(model)
          }
          .disabled(!model.hasCurrentDictionary)
        }
        Section {
          Button(Strings.text(.findNext), systemImage: "chevron.down") { find(.forward) }
            .keyboardShortcut("g")
          Button(Strings.text(.findPrevious), systemImage: "chevron.up") { find(.backward) }
            .keyboardShortcut("g", modifiers: [.command, .shift])
        }
      } label: {
        Label(Strings.text(.moreMenu), systemImage: "ellipsis.circle")
      }
      .help(Strings.text(.moreMenu))
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

  // MARK: - Sidebar

  private struct DictionarySidebar: View {
    let model: DictionaryToolModel

    var body: some View {
      List(
        selection: Binding(
          get: { model.selectedDictionaryID },
          set: { model.selectDictionary($0) })
      ) {
        Section(Strings.text(.dictionaries)) {
          ForEach(model.dictionaries) { item in
            Label(item.name, systemImage: "book.closed")
              .tag(item.id)
              .contextMenu { DictionaryContextMenu(model: model, id: item.id) }
          }
        }
      }
      .listStyle(.sidebar)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        NewDictionaryButton(model: model)
      }
    }
  }

  /// "New dictionary..." at the bottom of the sidebar (like "Add List" in Reminders).
  private struct NewDictionaryButton: View {
    let model: DictionaryToolModel

    var body: some View {
      Button {
        model.requestCreateDictionary()
      } label: {
        Label(Strings.text(.newDictionary), systemImage: "plus.circle")
      }
      .buttonStyle(.borderless)
      .disabled(!model.canCreateDictionary)
      .help(Strings.text(.newDictionary))
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
    }
  }

  private struct DictionaryContextMenu: View {
    let model: DictionaryToolModel
    let id: UInt64

    var body: some View {
      Button(Strings.text(.renameMenu), systemImage: "pencil") {
        model.selectDictionary(id)
        model.requestRenameDictionary()
      }
      Divider()
      Button(Strings.text(.importToThisMenu), systemImage: "square.and.arrow.down") {
        model.selectDictionary(id)
        model.requestImportAndAppendDictionary()
      }
      Button(Strings.text(.exportThisMenu), systemImage: "square.and.arrow.up") {
        model.selectDictionary(id)
        DictionaryExporter.export(model)
      }
      Divider()
      Button(Strings.text(.deleteMenu), systemImage: "trash", role: .destructive) {
        model.selectDictionary(id)
        model.requestDeleteDictionary()
      }
    }
  }

  // MARK: - Detail

  private struct DictionaryDetail: View {
    /// What the content area shows.
    enum Content {
      case noDictionaries
      case noSelection
      case noWords
      case words
    }

    let model: DictionaryToolModel
    @Binding var scrollTarget: DictionaryToolModel.Row.ID?

    private var content: Content {
      if model.dictionaries.isEmpty { return .noDictionaries }
      if !model.hasCurrentDictionary { return .noSelection }
      return model.rows.isEmpty ? .noWords : .words
    }

    var body: some View {
      switch content {
      case .noDictionaries:
        ContentUnavailableView {
          Label(Strings.text(.noDictionaries), systemImage: "books.vertical")
        } description: {
          Text(Strings.text(.noDictionariesDescription))
        } actions: {
          Button(Strings.text(.newDictionaryMenu)) { model.requestCreateDictionary() }
        }
      case .noSelection:
        ContentUnavailableView(
          Strings.text(.noSelection), systemImage: "sidebar.left",
          description: Text(Strings.text(.noSelectionDescription)))
      case .noWords:
        ContentUnavailableView {
          Label(Strings.text(.noWords), systemImage: "character.book.closed")
        } description: {
          Text(Strings.text(.noWordsDescription))
        } actions: {
          Button(Strings.text(.addWord)) { model.addWord() }
            .disabled(!model.canAddWord)
        }
      case .words:
        DictionaryContentTable(model: model, scrollTarget: $scrollTarget)
          .safeAreaInset(edge: .bottom, spacing: 0) {
            WordCountFooter(count: model.rows.count)
          }
      }
    }
  }

  /// The status line of the Qt version ("<dictionary>: <n> entries"); the dictionary is the sidebar selection.
  private struct WordCountFooter: View {
    let count: Int

    var body: some View {
      VStack(spacing: 0) {
        Divider()
        Text(verbatim: Strings.wordCount(count))
          .font(.footnote)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .frame(maxWidth: .infinity)
          .padding(.vertical, 5)
      }
      .background(.bar)
    }
  }

  // MARK: - Entry table

  private struct DictionaryContentTable: View {
    @Bindable var model: DictionaryToolModel
    @Binding var scrollTarget: DictionaryToolModel.Row.ID?
    @State private var sortOrder: [KeyPathComparator<DictionaryToolModel.Row>] = []

    var body: some View {
      ScrollViewReader { proxy in
        Table(model.rows, selection: $model.selectedRowIDs, sortOrder: $sortOrder) {
          TableColumn(trDT("Reading"), value: \.reading) { row in
            EditableCell(model: model, rowID: row.id, column: .reading, text: row.reading)
          }
          .width(min: 80, ideal: 120)
          TableColumn(trDT("Word"), value: \.word) { row in
            EditableCell(model: model, rowID: row.id, column: .word, text: row.word)
          }
          .width(min: 80, ideal: 120)
          TableColumn(trDT("Category"), value: \.category) { row in
            CategoryCell(model: model, rowID: row.id, category: row.category)
          }
          .width(min: 90, ideal: 110)
          TableColumn(trDT("Comment"), value: \.comment) { row in
            EditableCell(model: model, rowID: row.id, column: .comment, text: row.comment)
          }
          .width(min: 80, ideal: 140)
        }
        .alternatingRowBackgrounds()
        .onChange(of: scrollTarget) { _, rowID in
          guard let rowID else { return }
          withAnimation { proxy.scrollTo(rowID) }
          scrollTarget = nil
        }
      }
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
        EntryContextMenu(model: model, ids: ids)
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
      Button(trDT("Add a word")) { model.addWord() }
        .disabled(!model.canAddWord)
      if !ids.isEmpty {
        let multiple = ids.count > 1
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
        Menu(trDT("Change category to")) {
          ForEach(model.posList, id: \.self) { pos in
            Button(pos) {
              model.selectedRowIDs = ids
              model.editPos(pos)
            }
          }
        }
        Button(Strings.text(.editCommentMenu)) {
          model.selectedRowIDs = ids
          model.requestEditComment()
        }
        Divider()
        Button(multiple ? trDT("Delete the selected words") : trDT("Delete this word"), role: .destructive) {
          model.selectedRowIDs = ids
          model.requestDeleteWords()
        }
      }
    }
  }

  // MARK: - Prompts (QInputDialog)

  /// QInputDialog::getText for the dictionary name and the comment.
  private struct PromptSheet: View {
    let prompt: DictionaryToolModel.Prompt
    let completion: (String?) -> Void
    @State private var text: String
    @FocusState private var focused: Bool

    init(prompt: DictionaryToolModel.Prompt, completion: @escaping (String?) -> Void) {
      self.prompt = prompt
      self.completion = completion
      _text = State(initialValue: prompt.initialText)
    }

    private var title: String {
      switch prompt {
      case .newDictionary: Strings.text(.newDictionaryTitle)
      case .renameDictionary: Strings.text(.renameDictionaryTitle)
      case .editComment: Strings.text(.editCommentTitle)
      }
    }

    private var acceptTitle: String {
      switch prompt {
      case .newDictionary: Strings.text(.create)
      case .renameDictionary: Strings.text(.rename)
      case .editComment: Strings.text(.ok)
      }
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(title)
          .font(.headline)
        TextField(prompt.label, text: $text)
          .focused($focused)
          .onSubmit(accept)
        HStack {
          Spacer()
          Button(Strings.text(.cancel), role: .cancel) { completion(nil) }
            .keyboardShortcut(.cancelAction)
          Button(acceptTitle, action: accept)
            .keyboardShortcut(.defaultAction)
            .disabled(!canAccept)
        }
      }
      .padding(20)
      .frame(width: 340)
      .onAppear { focused = true }
    }

    private var canAccept: Bool { prompt.allowsEmpty || !text.isEmpty }

    private func accept() {
      if canAccept {
        completion(text)
      }
    }
  }
#endif
