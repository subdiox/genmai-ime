// The user dictionary on iOS: the macOS dictionary tool's model (`DictionaryToolModel`: storage, validation,
// messages, saving and the reload of the keyboard) with a list and an edit sheet instead of the table.

#if os(iOS)
  import GenmaiClient
  import GenmaiGUI
  import SwiftUI

  struct UserDictionaryView: View {
    @State private var model = DictionaryToolModel(client: AppSessionBackend.makeClient())
    @State private var editing: WordDraft?
    @State private var promptText = ""
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
      @Bindable var model = model
      Group {
        switch model.availability {
        case .available:
          wordList
        case .unavailable(let message):
          ContentUnavailableView(settingsText("User dictionary"), systemImage: "book", description: Text(message))
        }
      }
      .navigationTitle(settingsText("User dictionary"))
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            editing = WordDraft(category: model.defaultPos)
          } label: {
            Label(AppStrings.text(.newWord), systemImage: "plus")
          }
          .disabled(!model.canAddWord)
        }
        ToolbarItem(placement: .secondaryAction) {
          dictionaryMenu
        }
      }
      .sheet(item: $editing) { draft in
        WordEditor(draft: draft, posList: model.posList) { saved in
          save(saved)
        }
      }
      .alert(
        model.prompt?.label ?? "",
        isPresented: Binding(get: { model.prompt != nil }, set: { if !$0 { model.prompt = nil } }),
        presenting: model.prompt
      ) { prompt in
        TextField("", text: $promptText)
        Button(AppStrings.text(.done)) { model.completePrompt(prompt, text: promptText) }
        Button(AppStrings.text(.cancel), role: .cancel) { model.completePrompt(prompt, text: nil) }
      }
      .onChange(of: model.prompt) { _, prompt in
        promptText = prompt?.initialText ?? ""
      }
      .genmaiMessageAlert($model.pendingMessage)
      .onChange(of: scenePhase) { _, phase in
        if phase != .active {
          model.onDeactivate()
        }
      }
      .onAppear { dropBlankRows() }
      .onChange(of: model.selectedDictionaryID) { dropBlankRows() }
      .onChange(of: model.dictionaries.count) { dropBlankRows() }
      .onDisappear { model.close() }
    }

    /// The dictionary tool adds an empty row to a new dictionary for the table to edit; the list has no use
    /// for it.
    private func dropBlankRows() {
      if model.rows.contains(where: \.isBlank) {
        model.rows.removeAll(where: \.isBlank)
      }
    }

    private var wordList: some View {
      List {
        if model.dictionaries.count > 1 {
          Picker(
            AppStrings.text(.dictionaries),
            selection: Binding(get: { model.selectedDictionaryID }, set: { model.selectDictionary($0) })
          ) {
            ForEach(model.dictionaries) { dictionary in
              Text(verbatim: dictionary.name).tag(Optional(dictionary.id))
            }
          }
        }
        if model.rows.isEmpty {
          Text(verbatim: AppStrings.text(.noWords)).foregroundStyle(.secondary)
        }
        ForEach(model.rows) { row in
          Button {
            editing = WordDraft(row: row)
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(verbatim: row.word).foregroundStyle(.primary)
              Text(verbatim: "\(row.reading) · \(row.category)").font(.caption).foregroundStyle(.secondary)
            }
          }
          .swipeActions {
            Button(role: .destructive) {
              model.selectedRowIDs = [row.id]
              model.requestDeleteWords()
            } label: {
              Label(AppStrings.text(.deleteWord), systemImage: "trash")
            }
          }
        }
      }
    }

    private var dictionaryMenu: some View {
      Menu {
        Button(AppStrings.text(.newDictionary)) { model.requestCreateDictionary() }
          .disabled(!model.canCreateDictionary)
        Button(AppStrings.text(.renameDictionary)) { model.requestRenameDictionary() }
          .disabled(!model.hasCurrentDictionary)
        Button(AppStrings.text(.deleteDictionary), role: .destructive) { model.requestDeleteDictionary() }
          .disabled(!model.hasCurrentDictionary)
      } label: {
        Label(AppStrings.text(.dictionaries), systemImage: "books.vertical")
      }
    }

    private func save(_ draft: WordDraft) {
      let rowID: DictionaryToolModel.Row.ID
      if let id = draft.rowID {
        rowID = id
      } else {
        model.addWord()
        guard let id = model.rows.last?.id else { return }
        rowID = id
      }
      model.setCell(rowID, .reading, draft.reading)
      model.setCell(rowID, .word, draft.word)
      model.setCell(rowID, .category, draft.category)
      model.setCell(rowID, .comment, draft.comment)
      model.onItemChanged(rowID, .reading)
      model.onDeactivate()
    }
  }

  private func settingsText(_ source: String) -> String { tr("Settings", source) }

  extension DictionaryToolModel.Row {
    fileprivate var isBlank: Bool { reading.isEmpty && word.isEmpty }
  }

  /// The word being edited (nil `rowID`: a new word).
  struct WordDraft: Identifiable {
    let id = UUID()
    var rowID: DictionaryToolModel.Row.ID?
    var reading = ""
    var word = ""
    var category: String
    var comment = ""

    init(category: String) {
      self.category = category
    }

    init(row: DictionaryToolModel.Row) {
      rowID = row.id
      reading = row.reading
      word = row.word
      category = row.category
      comment = row.comment
    }
  }

  private struct WordEditor: View {
    @State var draft: WordDraft
    let posList: [String]
    let onSave: (WordDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
      NavigationStack {
        Form {
          TextField(AppStrings.text(.reading), text: $draft.reading)
          TextField(AppStrings.text(.word), text: $draft.word)
          Picker(AppStrings.text(.category), selection: $draft.category) {
            ForEach(posList, id: \.self) { pos in
              Text(verbatim: pos).tag(pos)
            }
          }
          TextField(AppStrings.text(.comment), text: $draft.comment)
        }
        .navigationTitle(AppStrings.text(draft.rowID == nil ? .newWord : .editWord))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(AppStrings.text(.cancel), role: .cancel) { dismiss() }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(AppStrings.text(.save)) {
              onSave(draft)
              dismiss()
            }
            .disabled(draft.reading.isEmpty || draft.word.isEmpty)
          }
        }
      }
    }
  }
#endif
