// SwiftUI replacement of mozc/src/gui/word_register_dialog/word_register_dialog.ui and the widget wiring of
// word_register_dialog.cc (3.35.6354).

import GenmaiClient
import SwiftUI

private let kUIContext = "WordRegisterDialog"

/// English / Japanese strings of the word register dialog that Mozc's Qt translations do not have (or have only
/// in an outdated form: "..." instead of "…", "ユーザ" instead of "ユーザー").
enum WordRegisterStrings {
  enum Key: CaseIterable, Sendable {
    case register, cancel, editUserDictionary, unavailableTitle, close, wordPrompt, readingPrompt
  }

  static let english: [Key: String] = [
    .register: "Add",
    .cancel: "Cancel",
    .editUserDictionary: "Edit User Dictionary…",
    .unavailableTitle: "Can’t Add the Word",
    .close: "Close",
    .wordPrompt: "e.g. 玄米",
    .readingPrompt: "e.g. げんまい",
  ]

  static let japanese: [Key: String] = [
    .register: "登録",
    .cancel: "キャンセル",
    .editUserDictionary: "ユーザー辞書を編集…",
    .unavailableTitle: "単語を登録できません",
    .close: "閉じる",
    .wordPrompt: "例: 玄米",
    .readingPrompt: "例: げんまい",
  ]

  static func text(_ key: Key, language: GUILanguage = .current) -> String {
    let table = language == .japanese ? japanese : english
    return table[key] ?? english[key] ?? ""
  }
}

public struct WordRegisterDialogView: View {
  @State private var model: WordRegisterDialogModel
  private let launchDictionaryTool: @MainActor () -> Void

  public init(
    client: any GenmaiClientProtocol, initialWord: String?, initialReading: String?,
    launchDictionaryTool: @escaping @MainActor () -> Void = {}
  ) {
    _model = State(
      initialValue: WordRegisterDialogModel(
        client: client, initialWord: initialWord, initialReading: initialReading))
    self.launchDictionaryTool = launchDictionaryTool
  }

  init(model: WordRegisterDialogModel, launchDictionaryTool: @escaping @MainActor () -> Void = {}) {
    _model = State(initialValue: model)
    self.launchDictionaryTool = launchDictionaryTool
  }

  public var body: some View {
    Group {
      switch model.availability {
      case .available:
        WordRegisterForm(model: model, launchDictionaryTool: launchDictionaryTool)
      case .unavailable(let message):
        WordRegisterUnavailableView(message: message)
      }
    }
    .navigationTitle(tr(kUIContext, "[ProductName] Word Register Dialog"))
  }
}

/// The storage is locked or broken (the Qt version shows a message box and closes).
private struct WordRegisterUnavailableView: View {
  let message: String
  @Environment(\.closeDialog) private var closeDialog

  var body: some View {
    ContentUnavailableView {
      Label(WordRegisterStrings.text(.unavailableTitle), systemImage: "lock")
    } description: {
      Text(verbatim: message)
    } actions: {
      Button(WordRegisterStrings.text(.close)) { closeDialog() }
        .keyboardShortcut(.defaultAction)
    }
    .padding(.vertical, 12)
    .frame(width: 420)
    .fixedSize(horizontal: false, vertical: true)
  }
}

private struct WordRegisterForm: View {
  enum Field: Hashable {
    case word
    case reading
  }

  @Bindable var model: WordRegisterDialogModel
  let launchDictionaryTool: @MainActor () -> Void
  @Environment(\.closeDialog) private var closeDialog
  @FocusState private var focusedField: Field?
  /// Set when the dialog accepted but has to show a warning first (QDialog::accept after the message box).
  @State private var closesAfterMessage = false

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          TextField(
            tr(kUIContext, "Word"), text: $model.word, prompt: Text(WordRegisterStrings.text(.wordPrompt)))
            .focused($focusedField, equals: .word)
            .onSubmit { model.completeReading() }
          TextField(
            tr(kUIContext, "Reading"), text: $model.reading,
            prompt: Text(WordRegisterStrings.text(.readingPrompt)))
            .focused($focusedField, equals: .reading)
        }
        Section {
          Picker(tr(kUIContext, "Part of Speech"), selection: $model.posIndex) {
            ForEach(model.posList.indices, id: \.self) { index in
              Text(verbatim: model.posList[index]).tag(index)
            }
          }
          Picker(tr(kUIContext, "Dictionary"), selection: $model.dictionaryIndex) {
            ForEach(model.dictionaryNames.indices, id: \.self) { index in
              Text(verbatim: model.dictionaryNames[index]).tag(index)
            }
          }
        }
      }
      .formStyle(.grouped)
      .scrollDisabled(true)
      .fixedSize(horizontal: false, vertical: true)
      WordRegisterButtons(
        model: model,
        editUserDictionary: {
          model.prepareLaunchDictionaryTool()
          launchDictionaryTool()
          closeDialog()
        },
        cancel: {
          model.reject()
          closeDialog()
        },
        register: register)
    }
    .frame(width: 420)
    .genmaiMessageAlert($model.pendingMessage)
    .onChange(of: model.pendingMessage) { _, message in
      if message == nil && closesAfterMessage {
        closeDialog()
      }
    }
    .onChange(of: focusedField) { oldValue, _ in
      // WordlineEdit::editingFinished -> CompleteReading.
      if oldValue == .word {
        model.completeReading()
      }
    }
    .onAppear {
      focusedField = model.focusesReadingInitially ? .reading : .word
    }
  }

  /// The OK button of the Qt version.
  private func register() {
    if model.accept() {
      if model.pendingMessage != nil {
        closesAfterMessage = true
      } else {
        closeDialog()
      }
    }
  }
}

private struct WordRegisterButtons: View {
  let model: WordRegisterDialogModel
  let editUserDictionary: () -> Void
  let cancel: () -> Void
  let register: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Button(WordRegisterStrings.text(.editUserDictionary), action: editUserDictionary)
        .buttonStyle(.link)
      Spacer()
      Button(WordRegisterStrings.text(.cancel), role: .cancel, action: cancel)
        .keyboardShortcut(.cancelAction)
      Button(WordRegisterStrings.text(.register), action: register)
        .disabled(!model.isOKEnabled)
        .keyboardShortcut(.defaultAction)
    }
    .padding([.horizontal, .bottom], 20)
  }
}
