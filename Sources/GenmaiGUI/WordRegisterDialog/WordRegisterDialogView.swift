// SwiftUI replacement of mozc/src/gui/word_register_dialog/word_register_dialog.ui and the widget wiring of
// word_register_dialog.cc (3.35.6354).

import GenmaiClient
import SwiftUI

private let kUIContext = "WordRegisterDialog"

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
        WordRegisterUnavailableView(title: model.windowTitle, message: message)
      }
    }
    .navigationTitle(tr(kUIContext, "[ProductName] Word Register Dialog"))
  }
}

private struct WordRegisterUnavailableView: View {
  let title: String
  let message: String
  @Environment(\.closeDialog) private var closeDialog
  @State private var isPresented = true

  var body: some View {
    Color.clear
      .frame(width: 1, height: 1)
      .alert(title, isPresented: $isPresented) {
        Button("OK") { closeDialog() }
      } message: {
        Text(verbatim: message)
      }
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
    VStack(alignment: .leading, spacing: 12) {
      Form {
        TextField(tr(kUIContext, "Word"), text: $model.word)
          .focused($focusedField, equals: .word)
          .onSubmit { model.completeReading() }
        TextField(tr(kUIContext, "Reading"), text: $model.reading)
          .focused($focusedField, equals: .reading)
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
      HStack {
        Button(tr(kUIContext, "Edit user dictionary...")) {
          model.prepareLaunchDictionaryTool()
          launchDictionaryTool()
          closeDialog()
        }
        .buttonStyle(.link)
        Spacer()
        Button(tr("FindDialog", "Cancel"), role: .cancel) {
          model.reject()
          closeDialog()
        }
        .keyboardShortcut(.cancelAction)
        Button("OK") {
          if model.accept() {
            if model.pendingMessage != nil {
              closesAfterMessage = true
            } else {
              closeDialog()
            }
          }
        }
        .disabled(!model.isOKEnabled)
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(16)
    .frame(minWidth: 380)
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
}
