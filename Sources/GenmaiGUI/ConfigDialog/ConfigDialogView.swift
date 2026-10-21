// SwiftUI version of mozc/src/gui/config_dialog/config_dialog.ui (3.35.6354), macOS layout:
// tabs General / Dictionary / Advanced / Suggest / Privacy / Misc (+ AI, not in Mozc), "Reset to defaults",
// Cancel / Apply / OK.

import GenmaiClient
import GenmaiProtocol
import SwiftUI

public struct ConfigDialogView: View {
  @State private var model: ConfigDialogModel
  @Environment(\.closeDialog) private var closeDialog

  public init(client: any GenmaiClientProtocol, launchTool: @escaping @MainActor (String) -> Void = { _ in }) {
    _model = State(initialValue: ConfigDialogModel(client: client, launchTool: launchTool))
  }

  public init(model: ConfigDialogModel) {
    _model = State(initialValue: model)
  }

  public var body: some View {
    VStack(spacing: 12) {
      TabView {
        GeneralTab(model: model)
          .tabItem { Text(verbatim: tr("ConfigDialog", "General")) }
        DictionaryTab(model: model)
          .tabItem { Text(verbatim: tr("ConfigDialog", "Dictionary")) }
        AdvancedTab(model: model)
          .tabItem { Text(verbatim: tr("ConfigDialog", "Advanced")) }
        SuggestTab(model: model)
          .tabItem { Text(verbatim: tr("ConfigDialog", "Suggest")) }
        PrivacyTab(model: model)
          .tabItem { Text(verbatim: tr("ConfigDialog", "Privacy")) }
        MiscTab(model: model)
          .tabItem { Text(verbatim: tr("ConfigDialog", "Misc")) }
        // Not in Mozc: AI conversion (genmai).
        AIConversionTab(model: model)
          .tabItem { Text(verbatim: AIStrings.text(.tab)) }
      }
      ConfigDialogButtons(model: model, close: closeDialog)
    }
    .padding(16)
    .frame(minWidth: 560, minHeight: 560)
    .navigationTitle(model.windowTitle)
    .genmaiMessageAlert($model.pendingMessage)
    .sheet(item: $model.activeEditor) { editor in
      ConfigDialogEditorSheet(editor: editor, model: model)
    }
  }
}

struct ConfigDialogEditorSheet: View {
  let editor: ConfigDialogEditor
  let model: ConfigDialogModel

  var body: some View {
    switch editor {
    case .keymap(let table):
      KeyMapEditorView(currentKeymap: table) { model.finishKeymapEditor($0) }
    case .romanTable(let table):
      RomanTableEditorView(currentRomanTable: table) { model.finishRomanTableEditor($0) }
    }
  }
}

struct ConfigDialogButtons: View {
  let model: ConfigDialogModel
  let close: CloseDialogAction

  var body: some View {
    let context = ConfigDialogModel.context
    HStack {
      Button(tr("ConfigDialog", "Reset to defaults")) { model.resetToDefaults() }
      Spacer()
      Button(tr(context, "Cancel"), role: .cancel) { close() }
        .keyboardShortcut(.cancelAction)
      Button(tr(context, "Apply")) { model.apply() }
        .disabled(!model.applyEnabled)
      Button(tr(context, "  Ok  ").trimmingCharacters(in: .whitespaces)) {
        if model.accept() {
          close()
        }
      }
      .keyboardShortcut(.defaultAction)
    }
  }
}

// MARK: - Shared rows

/// A labeled picker row (QLabel + QComboBox).
struct ConfigPicker<Value: Hashable>: View {
  let label: String
  @Binding var selection: Value
  let items: [(Value, String)]

  var body: some View {
    Picker(selection: $selection) {
      if !items.contains(where: { $0.0 == selection }) {
        // An out-of-range config value: the Qt combo box shows no item.
        Text(verbatim: "").tag(selection)
      }
      ForEach(items, id: \.0) { item in
        Text(verbatim: item.1).tag(item.0)
      }
    } label: {
      Text(verbatim: label)
    }
  }
}

struct ConfigToggle: View {
  let label: String
  @Binding var isOn: Bool

  var body: some View {
    Toggle(isOn: $isOn) { Text(verbatim: label) }
  }
}

struct ConfigSectionHeader: View {
  let title: String

  var body: some View {
    Text(verbatim: tr("ConfigDialog", title))
  }
}

// MARK: - Tabs

struct GeneralTab: View {
  @Bindable var model: ConfigDialogModel

  var body: some View {
    let ui = "ConfigDialog"
    Form {
      Section {
        ConfigPicker(
          label: tr(ui, "Input mode"), selection: $model.values.inputModeIndex,
          items: ConfigDialogModel.inputModeItems)
        ConfigPicker(
          label: tr(ui, "Punctuation style"), selection: $model.values.punctuationMethod,
          items: ConfigDialogModel.punctuationItems)
        ConfigPicker(
          label: tr(ui, "Symbol style"), selection: $model.values.symbolMethod,
          items: ConfigDialogModel.symbolItems)
        ConfigPicker(
          label: tr(ui, "Space input style"), selection: $model.values.spaceCharacterForm,
          items: ConfigDialogModel.spaceCharacterFormItems)
        ConfigPicker(
          label: tr(ui, "Candidate selection shortcut"), selection: $model.values.selectionShortcut,
          items: ConfigDialogModel.selectionShortcutItems)
        ConfigPicker(
          label: tr(ui, "Input from numpad keys"), selection: $model.values.numpadCharacterForm,
          items: ConfigDialogModel.numpadCharacterFormItems)
        ConfigPicker(
          label: tr(ui, "Input from ¥ or backslash key"), selection: $model.values.yenSignCharacter,
          items: ConfigDialogModel.yenSignItems)
      } header: {
        ConfigSectionHeader(title: "Basics")
      }
      Section {
        LabeledContent {
          HStack {
            Picker("", selection: $model.values.sessionKeymap) {
              if !ConfigDialogModel.keymapItems.contains(where: { $0.0 == model.values.sessionKeymap }) {
                Text(verbatim: "").tag(model.values.sessionKeymap)
              }
              ForEach(ConfigDialogModel.keymapItems, id: \.0) { item in
                Text(verbatim: item.1).tag(item.0)
              }
            }
            .labelsHidden()
            .fixedSize()
            Button(tr(ui, "Customize...")) { model.editKeymap() }
          }
        } label: {
          Text(verbatim: tr(ui, "Keymap style"))
        }
        LabeledContent {
          Button(tr(ui, "Customize...")) { model.editRomanTable() }
            .disabled(!model.values.isRomanTableEditable)
        } label: {
          Text(verbatim: tr(ui, "Romaji table"))
        }
      } header: {
        ConfigSectionHeader(title: "Keymap")
      }
    }
    .formStyle(.grouped)
  }
}

struct DictionaryTab: View {
  @Bindable var model: ConfigDialogModel

  var body: some View {
    let ui = "ConfigDialog"
    Form {
      Section {
        ConfigPicker(
          label: tr(ui, "Adjust conversion based on previous input"),
          selection: $model.values.historyLearningLevel,
          items: ConfigDialogModel.historyLearningLevelItems)
        LabeledContent {
          Button(tr(ui, "Clear personalization data")) { model.clearUserHistory() }
        } label: {
          EmptyView()
        }
      } header: {
        ConfigSectionHeader(title: "Personalization")
      }
      Section {
        LabeledContent {
          Button(tr(ui, "Edit user dictionary...")) { model.editUserDictionary() }
        } label: {
          EmptyView()
        }
      } header: {
        ConfigSectionHeader(title: "User dictionary")
      }
      Section {
        ConfigToggle(label: tr(ui, "Homonym dictionary"), isOn: $model.values.useLocalUsageDictionary)
      } header: {
        ConfigSectionHeader(title: "Usage dictionary")
      }
      Section {
        SpecialConversionToggles(values: $model.values)
      } header: {
        ConfigSectionHeader(title: "Special conversions")
      }
    }
    .formStyle(.grouped)
  }
}

struct SpecialConversionToggles: View {
  @Binding var values: ConfigDialogValues

  var body: some View {
    let ui = "ConfigDialog"
    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
      GridRow {
        ConfigToggle(label: tr(ui, "Single kanji conversion"), isOn: $values.useSingleKanjiConversion)
        ConfigToggle(label: tr(ui, "Symbol conversion"), isOn: $values.useSymbolConversion)
      }
      GridRow {
        ConfigToggle(label: tr(ui, "Emoticon conversion"), isOn: $values.useEmoticonConversion)
        ConfigToggle(label: tr(ui, "Katakana to English conversion"), isOn: $values.useT13nConversion)
      }
      GridRow {
        ConfigToggle(label: tr(ui, "Postal code conversion"), isOn: $values.useZipCodeConversion)
        ConfigToggle(label: tr(ui, "Spelling correction"), isOn: $values.useSpellingCorrection)
      }
      GridRow {
        ConfigToggle(label: tr(ui, "Calculator"), isOn: $values.useCalculator)
        ConfigToggle(label: tr(ui, "Special number conversion"), isOn: $values.useNumberConversion)
      }
      GridRow {
        ConfigToggle(label: tr(ui, "Date/time conversion"), isOn: $values.useDateConversion)
        ConfigToggle(label: tr(ui, "Emoji conversion"), isOn: $values.useEmojiConversion)
      }
    }
  }
}

struct AdvancedTab: View {
  @Bindable var model: ConfigDialogModel

  var body: some View {
    let ui = "ConfigDialog"
    Form {
      Section {
        ConfigToggle(
          label: tr(ui, "Automatically switch to halfwidth"), isOn: $model.values.autoSwitchCompositionMode)
        ConfigPicker(
          label: tr(ui, "Shift key mode switch"), selection: $model.values.shiftKeyModeSwitch,
          items: ConfigDialogModel.shiftKeyModeSwitchItems)
        AutoConversionRow(values: $model.values)
        ConfigToggle(
          label: tr(ui, "Always use Japanese keyboard layout for Japanese input"),
          isOn: $model.values.useJapaneseLayout)
        // useModeIndicator is available only on Windows (hidden).
      } header: {
        ConfigSectionHeader(title: "Input Assistance")
      }
      Section {
        CharacterFormEditorView(model: model.characterFormEditor) { model.markButtonClicked() }
      } header: {
        ConfigSectionHeader(title: "Fullwidth/Halfwidth")
      }
    }
    .formStyle(.grouped)
  }
}

struct AutoConversionRow: View {
  @Binding var values: ConfigDialogValues

  var body: some View {
    let ui = "ConfigDialog"
    VStack(alignment: .leading, spacing: 6) {
      ConfigToggle(label: tr(ui, "Convert at punctuations"), isOn: $values.useAutoConversion)
      HStack(spacing: 16) {
        ConfigToggle(label: tr(ui, "。"), isOn: $values.kuten)
        ConfigToggle(label: tr(ui, "、"), isOn: $values.touten)
        ConfigToggle(label: tr(ui, "?"), isOn: $values.questionMark)
        ConfigToggle(label: tr(ui, "!"), isOn: $values.exclamationMark)
      }
      .padding(.leading, 20)
      .disabled(!values.isAutoConversionKeyEditable)
    }
  }
}

struct SuggestTab: View {
  @Bindable var model: ConfigDialogModel

  var body: some View {
    let ui = "ConfigDialog"
    Form {
      Section {
        ConfigToggle(label: tr(ui, "Use input history"), isOn: $model.values.useHistorySuggest)
        ConfigToggle(label: tr(ui, "Use system dictionary"), isOn: $model.values.useDictionarySuggest)
        ConfigToggle(label: tr(ui, "Use realtime conversion"), isOn: $model.values.useRealtimeConversion)
      } header: {
        ConfigSectionHeader(title: "Source data")
      }
      Section {
        Stepper(value: $model.values.suggestionsSize, in: 1...9) {
          LabeledContent {
            Text(verbatim: String(model.values.suggestionsSize))
              .monospacedDigit()
          } label: {
            Text(verbatim: tr(ui, "Maximum number of suggestions"))
          }
        }
      } header: {
        ConfigSectionHeader(title: "Other settings")
      }
    }
    .formStyle(.grouped)
  }
}

struct PrivacyTab: View {
  @Bindable var model: ConfigDialogModel

  var body: some View {
    let ui = "ConfigDialog"
    Form {
      Section {
        MessageToggle(
          message: tr(
            ui,
            "Temporarily disable conversion personalization, history-based suggestions and user dictionary"),
          isOn: $model.values.incognitoMode)
      } header: {
        ConfigSectionHeader(title: "Secret mode")
      }
      Section {
        ConfigToggle(
          label: tr(ui, "Temporarily disable all suggestions"), isOn: $model.values.presentationMode
        )
        .disabled(!model.values.isPresentationModeEditable)
      } header: {
        ConfigSectionHeader(title: "Presentation mode")
      }
      Section {
        MessageToggle(
          message: tr(
            ui,
            "Help make [ProductName] better by automatically sending usage statistics and crash reports to Google (changes will take effect after you log out and log back in)"
          ),
          isOn: $model.values.usageStats)
      } header: {
        ConfigSectionHeader(title: "Usage statistics and crash reports")
      }
    }
    .formStyle(.grouped)
  }
}

/// A check box whose long message label also toggles it (ConfigDialog::eventFilter).
struct MessageToggle: View {
  let message: String
  @Binding var isOn: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Toggle("", isOn: $isOn)
        .labelsHidden()
      Text(verbatim: message)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(.rect)
        .onTapGesture { isOn.toggle() }
    }
  }
}

struct MiscTab: View {
  @Bindable var model: ConfigDialogModel

  var body: some View {
    let ui = "ConfigDialog"
    Form {
      // Default IME and Administration are Windows only (miscDefaultIMEWidget /
      // miscAdministrationWidget are hidden on macOS).
      Section {
        ConfigToggle(label: tr(ui, "Start conversion engine on login"), isOn: $model.values.startup)
      } header: {
        ConfigSectionHeader(title: "Startup")
      }
      #if DEBUG
        // disable logging options in release builds (NDEBUG).
        Section {
          ConfigPicker(
            label: tr(ui, "Logging level (debug only)"), selection: $model.values.verboseLevel,
            items: ConfigDialogModel.verboseLevelItems)
        } header: {
          ConfigSectionHeader(title: "Logging")
        }
      #endif
    }
    .formStyle(.grouped)
  }
}
