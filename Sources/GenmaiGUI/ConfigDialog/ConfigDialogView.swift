// The settings window. The options and their logic are those of mozc/src/gui/config_dialog (3.35.6354,
// ConfigDialogModel); the window is Genmai's own: a sidebar of panes like System Settings, and edits take effect
// right away (no OK / Cancel / Apply). Panes: General, Input, Conversion, Suggestions, AI (not in Mozc), Privacy,
// Updates (not in Mozc).

import AppKit
import GenmaiClient
import GenmaiProtocol
import SwiftUI

/// The settings panes, in sidebar order.
enum SettingsPane: String, CaseIterable, Identifiable {
  case general, input, conversion, suggestions, ai, privacy, updates

  var id: Self { self }

  var title: String {
    switch self {
    case .general: tr("Settings", "General")
    case .input: tr("Settings", "Input")
    case .conversion: tr("Settings", "Conversion")
    case .suggestions: tr("Settings", "Suggestions")
    case .ai: tr("Settings", "AI")
    case .privacy: tr("Settings", "Privacy")
    case .updates: tr("Settings", "Updates")
    }
  }

  var symbol: String {
    switch self {
    case .general: "gearshape.fill"
    case .input: "keyboard.fill"
    case .conversion: "character.book.closed.fill"
    case .suggestions: "text.bubble.fill"
    case .ai: "sparkles"
    case .privacy: "hand.raised.fill"
    case .updates: "arrow.down.circle.fill"
    }
  }

  var tint: Color {
    switch self {
    case .general: .gray
    case .input: .blue
    case .conversion: .orange
    case .suggestions: .teal
    case .ai: .purple
    case .privacy: .indigo
    case .updates: .green
    }
  }
}

public struct ConfigDialogView: View {
  /// The window's ideal size; the tool's window follows it (`sizingOptions = .preferredContentSize`). It is the
  /// same for every pane so that the window does not jump when the selection changes; the panes scroll.
  static let idealSize = CGSize(width: 760, height: 620)

  @State private var model: ConfigDialogModel
  @State private var selection: SettingsPane? = .general

  public init(client: any GenmaiClientProtocol, launchTool: @escaping @MainActor (String) -> Void = { _ in }) {
    let model = ConfigDialogModel(client: client, launchTool: launchTool)
    model.savesChangesAutomatically = true
    _model = State(initialValue: model)
  }

  public init(model: ConfigDialogModel) {
    self.init(model: model, pane: .general)
  }

  init(model: ConfigDialogModel, pane: SettingsPane) {
    _model = State(initialValue: model)
    _selection = State(initialValue: pane)
  }

  public var body: some View {
    NavigationSplitView {
      List(SettingsPane.allCases, selection: $selection) { pane in
        SettingsSidebarRow(pane: pane)
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
    } detail: {
      SettingsPaneView(pane: selection ?? .general, model: model)
        .navigationTitle((selection ?? .general).title)
    }
    .frame(
      minWidth: 640, idealWidth: Self.idealSize.width, maxWidth: .infinity,
      minHeight: 460, idealHeight: Self.idealSize.height, maxHeight: .infinity)
    .genmaiMessageAlert($model.pendingMessage)
    .sheet(item: $model.activeEditor) { editor in
      ConfigDialogEditorSheet(editor: editor, model: model)
    }
    .onDisappear { model.savePendingChanges() }
  }
}

struct SettingsSidebarRow: View {
  let pane: SettingsPane

  var body: some View {
    Label {
      Text(verbatim: pane.title)
    } icon: {
      Image(systemName: pane.symbol)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 22, height: 22)
        .background(pane.tint.gradient, in: .rect(cornerRadius: 6))
        .accessibilityHidden(true)
    }
  }
}

struct SettingsPaneView: View {
  let pane: SettingsPane
  let model: ConfigDialogModel

  var body: some View {
    switch pane {
    case .general: GeneralPane(model: model)
    case .input: InputPane(model: model)
    case .conversion: ConversionPane(model: model)
    case .suggestions: SuggestionsPane(model: model)
    case .ai: AIConversionTab(model: model)
    case .privacy: PrivacyPane(model: model)
    case .updates: UpdatesPane(model: model)
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
        .frame(idealWidth: 660, idealHeight: 560)
    case .romanTable(let table):
      RomanTableEditorView(currentRomanTable: table) { model.finishRomanTableEditor($0) }
        .frame(idealWidth: 500, idealHeight: 560)
    }
  }
}

// MARK: - Shared rows

/// `tr` in the context of the settings window.
func settingsText(_ source: String) -> String { tr("Settings", source) }

/// A labeled picker row.
struct ConfigPicker<Value: Hashable>: View {
  let label: String
  @Binding var selection: Value
  let items: [(Value, String)]

  var body: some View {
    Picker(selection: $selection) {
      if !items.contains(where: { $0.0 == selection }) {
        // An out-of-range config value: shown as an empty item.
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

/// A switch with an optional explanation below its title.
struct ConfigToggle: View {
  let label: String
  var detail: String?
  @Binding var isOn: Bool

  var body: some View {
    Toggle(isOn: $isOn) {
      Text(verbatim: label)
      if let detail {
        Text(verbatim: detail)
      }
    }
  }
}

/// A section header.
struct ConfigSectionHeader: View {
  let title: String

  var body: some View {
    Text(verbatim: settingsText(title))
  }
}

// MARK: - Panes

struct GeneralPane: View {
  @Bindable var model: ConfigDialogModel

  var body: some View {
    Form {
      Section {
        ConfigPicker(
          label: settingsText("Input method"), selection: $model.values.inputModeIndex,
          items: ConfigDialogModel.inputModeItems)
        KeymapRow(model: model)
        LabeledContent {
          Button(settingsText("Customize…")) { model.editRomanTable() }
            .disabled(!model.values.isRomanTableEditable)
        } label: {
          Text(verbatim: settingsText("Romaji table"))
        }
      } header: {
        ConfigSectionHeader(title: "Typing")
      }
      Section {
        ConfigPicker(
          label: settingsText("Punctuation"), selection: $model.values.punctuationMethod,
          items: ConfigDialogModel.punctuationItems)
        ConfigPicker(
          label: settingsText("Symbols"), selection: $model.values.symbolMethod,
          items: ConfigDialogModel.symbolItems)
        ConfigPicker(
          label: settingsText("Space"), selection: $model.values.spaceCharacterForm,
          items: ConfigDialogModel.spaceCharacterFormItems)
        ConfigPicker(
          label: settingsText("Numeric keypad"), selection: $model.values.numpadCharacterForm,
          items: ConfigDialogModel.numpadCharacterFormItems)
        ConfigPicker(
          label: settingsText("¥ key"), selection: $model.values.yenSignCharacter,
          items: ConfigDialogModel.yenSignItems)
      } header: {
        ConfigSectionHeader(title: "Characters")
      }
      Section {
        ConfigPicker(
          label: settingsText("Selection shortcut"), selection: $model.values.selectionShortcut,
          items: ConfigDialogModel.selectionShortcutItems)
      } header: {
        ConfigSectionHeader(title: "Candidates")
      }
      Section {
        LabeledContent {
          Button(settingsText("Reset All Settings…")) { model.resetToDefaults() }
        } label: {
          Text(verbatim: settingsText("Reset"))
          Text(verbatim: settingsText("Personalization data and input history are kept."))
        }
        LabeledContent {
          Button(settingsText("Uninstall [ProductName]…")) { UninstallerLauncher.open() }
            .disabled(UninstallerLauncher.url == nil)
        } label: {
          Text(verbatim: settingsText("Uninstall"))
          Text(
            verbatim: settingsText(
              "Removes [ProductName]. You choose whether your dictionary, learning data and settings go too."))
        }
      }
    }
    .formStyle(.grouped)
  }
}

/// The keymap style with its editor, and the warning for an empty custom keymap.
struct KeymapRow: View {
  @Bindable var model: ConfigDialogModel

  var body: some View {
    LabeledContent {
      HStack {
        Picker(selection: $model.values.sessionKeymap) {
          if !ConfigDialogModel.keymapItems.contains(where: { $0.0 == model.values.sessionKeymap }) {
            Text(verbatim: "").tag(model.values.sessionKeymap)
          }
          ForEach(ConfigDialogModel.keymapItems, id: \.0) { item in
            Text(verbatim: item.1).tag(item.0)
          }
        } label: {
          EmptyView()
        }
        .labelsHidden()
        .fixedSize()
        Button(settingsText("Customize…")) { model.editKeymap() }
      }
    } label: {
      Text(verbatim: settingsText("Key bindings"))
      if model.hasEmptyCustomKeymap {
        Label {
          Text(
            verbatim: settingsText(
              "The custom key bindings are empty. Customize them, or choose another style; until then the settings are not saved."
            ))
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.orange)
      }
    }
  }
}

struct InputPane: View {
  @Bindable var model: ConfigDialogModel

  var body: some View {
    Form {
      Section {
        ConfigToggle(
          label: settingsText("Switch to halfwidth automatically"),
          detail: settingsText(
            "Switches to halfwidth alphanumerics when the input looks like English, a URL or a number."),
          isOn: $model.values.autoSwitchCompositionMode)
        ConfigPicker(
          label: settingsText("Shift key switches to"), selection: $model.values.shiftKeyModeSwitch,
          items: ConfigDialogModel.shiftKeyModeSwitchItems)
        AutoConversionRow(values: $model.values)
        ConfigToggle(
          label: settingsText("Always use the Japanese keyboard layout"), isOn: $model.values.useJapaneseLayout)
        // useModeIndicator is available only on Windows (hidden).
      } header: {
        ConfigSectionHeader(title: "Input assistance")
      }
      Section {
        CharacterFormEditorView(model: model.characterFormEditor) { model.markButtonClicked() }
      } header: {
        ConfigSectionHeader(title: "Fullwidth and halfwidth")
      }
    }
    .formStyle(.grouped)
  }
}

/// "Convert at punctuation" with the punctuation marks that trigger it.
struct AutoConversionRow: View {
  @Binding var values: ConfigDialogValues

  var body: some View {
    ConfigToggle(label: settingsText("Convert at punctuation"), isOn: $values.useAutoConversion)
    if values.useAutoConversion {
      HStack(spacing: 20) {
        PunctuationToggle(mark: "。", isOn: $values.kuten)
        PunctuationToggle(mark: "、", isOn: $values.touten)
        PunctuationToggle(mark: "？", isOn: $values.questionMark)
        PunctuationToggle(mark: "！", isOn: $values.exclamationMark)
        Spacer()
      }
      .padding(.leading, 12)
    }
  }
}

struct PunctuationToggle: View {
  let mark: String
  @Binding var isOn: Bool

  var body: some View {
    Toggle(isOn: $isOn) { Text(verbatim: mark) }
      .toggleStyle(.checkbox)
  }
}

struct ConversionPane: View {
  @Bindable var model: ConfigDialogModel

  var body: some View {
    Form {
      Section {
        ConfigPicker(
          label: settingsText("Learn from what you type"), selection: $model.values.historyLearningLevel,
          items: ConfigDialogModel.historyLearningLevelItems)
        LabeledContent {
          Button(settingsText("Clear Personalization Data…"), role: .destructive) { model.clearUserHistory() }
        } label: {
          EmptyView()
        }
      } header: {
        ConfigSectionHeader(title: "Learning")
      }
      Section {
        LabeledContent {
          Button(settingsText("Edit…")) { model.editUserDictionary() }
        } label: {
          Text(verbatim: settingsText("User dictionary"))
        }
        ConfigToggle(
          label: settingsText("Homonym dictionary"),
          detail: settingsText("Shows how words with the same reading differ, next to the candidates."),
          isOn: $model.values.useLocalUsageDictionary)
      } header: {
        ConfigSectionHeader(title: "Dictionaries")
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
    ConfigToggle(label: settingsText("Single kanji"), isOn: $values.useSingleKanjiConversion)
    ConfigToggle(label: settingsText("Symbols and arrows"), isOn: $values.useSymbolConversion)
    ConfigToggle(label: settingsText("Emoticons"), isOn: $values.useEmoticonConversion)
    ConfigToggle(label: settingsText("Emoji"), isOn: $values.useEmojiConversion)
    ConfigToggle(label: settingsText("Katakana to English"), isOn: $values.useT13nConversion)
    ConfigToggle(label: settingsText("Postal codes"), isOn: $values.useZipCodeConversion)
    ConfigToggle(label: settingsText("Spelling correction (もしかして)"), isOn: $values.useSpellingCorrection)
    ConfigToggle(label: settingsText("Calculator"), isOn: $values.useCalculator)
    ConfigToggle(label: settingsText("Special numbers"), isOn: $values.useNumberConversion)
    ConfigToggle(label: settingsText("Date and time"), isOn: $values.useDateConversion)
  }
}

struct SuggestionsPane: View {
  @Bindable var model: ConfigDialogModel

  var body: some View {
    Form {
      Section {
        ConfigToggle(label: settingsText("Input history"), isOn: $model.values.useHistorySuggest)
        ConfigToggle(label: settingsText("System dictionary"), isOn: $model.values.useDictionarySuggest)
        ConfigToggle(
          label: settingsText("Realtime conversion"),
          detail: settingsText("Shows the conversion of the whole input as the first suggestion."),
          isOn: $model.values.useRealtimeConversion)
      } header: {
        ConfigSectionHeader(title: "Sources")
      }
      Section {
        Stepper(value: $model.values.suggestionsSize, in: 1...9) {
          LabeledContent {
            Text(verbatim: String(model.values.suggestionsSize))
              .monospacedDigit()
          } label: {
            Text(verbatim: settingsText("Maximum number of suggestions"))
          }
        }
      } header: {
        ConfigSectionHeader(title: "Display")
      }
    }
    .formStyle(.grouped)
  }
}

struct PrivacyPane: View {
  @Bindable var model: ConfigDialogModel

  var body: some View {
    Form {
      Section {
        ConfigToggle(
          label: settingsText("Secret mode"),
          detail: settingsText("Temporarily stops learning, history-based suggestions and the user dictionary."),
          isOn: $model.values.incognitoMode)
        ConfigToggle(
          label: settingsText("Presentation mode"), detail: settingsText("Temporarily hides all suggestions."),
          isOn: $model.values.presentationMode
        )
        .disabled(!model.values.isPresentationModeEditable)
      }
    }
    .formStyle(.grouped)
  }
}

struct UpdatesPane: View {
  @Bindable var model: ConfigDialogModel

  var body: some View {
    Form {
      UpdateSection(update: model.appUpdate)
      #if DEBUG
        // disable logging options in release builds (NDEBUG).
        Section {
          ConfigPicker(
            label: settingsText("Logging level (debug builds)"), selection: $model.values.verboseLevel,
            items: ConfigDialogModel.verboseLevelItems)
        } header: {
          ConfigSectionHeader(title: "Logging")
        }
      #endif
    }
    .formStyle(.grouped)
  }
}

/// Opens the uninstaller, which lives next to the tool app in Genmai.app/Contents/Resources.
@MainActor
enum UninstallerLauncher {
  static let appName = "UninstallGenmai.app"

  /// nil when the tool does not run from the input method bundle (development builds).
  static var url: URL? {
    let url = Bundle.main.bundleURL.deletingLastPathComponent().appending(path: appName)
    return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
  }

  static func open() {
    guard let url else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
      if let error {
        NSLog("Genmai: cannot open the uninstaller: %@", error.localizedDescription)
      }
    }
  }
}
