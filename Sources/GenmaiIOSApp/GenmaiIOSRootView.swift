// The Genmai app on iOS (not in Mozc): setup, keyboard settings, the conversion settings and the user dictionary
// of the macOS settings window (the same `ConfigDialogModel` / `DictionaryToolModel`), and a field to try the
// keyboard. The app writes the shared profile; the keyboard extension picks the changes up when it appears
// (`ToolCommandQueue`, `KeyboardSettings`).

#if os(iOS)
  import GenmaiBase
  import GenmaiClient
  import GenmaiGUI
  import GenmaiIOS
  import GenmaiProtocol
  import SwiftUI
  import UIKit

  private func settingsText(_ source: String) -> String { tr("Settings", source) }

  public struct GenmaiIOSRootView: View {
    @State private var model = ConfigDialogModel(client: AppSessionBackend.makeClient())
    @State private var keyboard = KeyboardSettingsModel()
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
      @Bindable var model = model
      NavigationStack {
        Form {
          SetupSection()
          KeyboardSection(keyboard: keyboard)
          Section {
            NavigationLink(AIStrings.text(.sectionAI)) { AISettingsView(model: model) }
            NavigationLink(settingsText("Conversion")) { ConversionSettingsView(model: model) }
            NavigationLink(settingsText("Suggestions")) { SuggestionSettingsView(model: model) }
            NavigationLink(settingsText("User dictionary")) { UserDictionaryView() }
          }
          TryItSection()
          AboutSection()
        }
        .navigationTitle(kProductNameInEnglish)
      }
      .genmaiMessageAlert($model.pendingMessage)
      .onAppear { model.savesChangesAutomatically = true }
      .onChange(of: scenePhase) { _, phase in
        if phase != .active {
          model.savesChangesAutomatically = true
          model.savePendingChanges()
        } else {
          model.reload()
          keyboard.reload()
        }
      }
    }
  }

  /// `KeyboardSettings`, saved on every change.
  @MainActor
  @Observable
  final class KeyboardSettingsModel {
    var settings = KeyboardSettings.load() {
      didSet {
        guard settings != oldValue else { return }
        do {
          try settings.save()
        } catch {
          GenmaiLog.error("Cannot save the keyboard settings: \(error)")
        }
      }
    }

    func reload() {
      settings = KeyboardSettings.load()
    }
  }

  private struct SetupSection: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
      Section {
        Text(verbatim: AppStrings.text(.setupSteps))
        Button(AppStrings.text(.openSettings)) {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
          }
        }
      } header: {
        Text(verbatim: AppStrings.text(.setup))
      } footer: {
        Text(verbatim: AppStrings.text(.fullAccess))
      }
    }
  }

  private struct KeyboardSection: View {
    @Bindable var keyboard: KeyboardSettingsModel

    var body: some View {
      Section {
        Picker(AppStrings.text(.kanaLayout), selection: $keyboard.settings.kanaLayout) {
          Text(verbatim: AppStrings.text(.twelveKeys)).tag(KanaLayout.twelveKeys)
          Text(verbatim: AppStrings.text(.qwerty)).tag(KanaLayout.qwerty)
        }
        if keyboard.settings.kanaLayout == .twelveKeys {
          Toggle(isOn: $keyboard.settings.flickOnly) {
            Text(verbatim: AppStrings.text(.flickOnly))
            Text(verbatim: AppStrings.text(.flickOnlyDetail))
          }
          Toggle(AppStrings.text(.qwertyAlphabet), isOn: $keyboard.settings.qwertyAlphabet)
        }
        Toggle(isOn: $keyboard.settings.haptics) {
          Text(verbatim: AppStrings.text(.haptics))
          Text(verbatim: AppStrings.text(.hapticsDetail))
        }
      } header: {
        Text(verbatim: AppStrings.text(.keyboard))
      }
    }
  }

  /// The macOS "Conversion" pane: learning, punctuation and the special conversions.
  struct ConversionSettingsView: View {
    @Bindable var model: ConfigDialogModel

    var body: some View {
      Form {
        Section {
          SettingsPicker(
            label: settingsText("Learn from what you type"), selection: $model.values.historyLearningLevel,
            items: ConfigDialogModel.historyLearningLevelItems)
          Button(settingsText("Clear Personalization Data…"), role: .destructive) { model.clearUserHistory() }
        } header: {
          Text(verbatim: settingsText("Learning"))
        }
        Section {
          SettingsPicker(
            label: settingsText("Punctuation"), selection: $model.values.punctuationMethod,
            items: ConfigDialogModel.punctuationItems)
          SettingsPicker(
            label: settingsText("Symbols"), selection: $model.values.symbolMethod,
            items: ConfigDialogModel.symbolItems)
        }
        Section {
          Toggle(settingsText("Single kanji"), isOn: $model.values.useSingleKanjiConversion)
          Toggle(settingsText("Symbols and arrows"), isOn: $model.values.useSymbolConversion)
          Toggle(settingsText("Emoticons"), isOn: $model.values.useEmoticonConversion)
          Toggle(settingsText("Emoji"), isOn: $model.values.useEmojiConversion)
          Toggle(settingsText("Katakana to English"), isOn: $model.values.useT13nConversion)
          Toggle(settingsText("Postal codes"), isOn: $model.values.useZipCodeConversion)
          Toggle(settingsText("Spelling correction (もしかして)"), isOn: $model.values.useSpellingCorrection)
          Toggle(settingsText("Calculator"), isOn: $model.values.useCalculator)
          Toggle(settingsText("Special numbers"), isOn: $model.values.useNumberConversion)
          Toggle(settingsText("Date and time"), isOn: $model.values.useDateConversion)
        }
        Section {
          Button(settingsText("Reset All Settings…")) { model.resetToDefaults() }
        } footer: {
          Text(verbatim: settingsText("Personalization data and input history are kept."))
        }
      }
      .navigationTitle(settingsText("Conversion"))
      .genmaiMessageAlert($model.pendingMessage)
    }
  }

  /// The macOS "Suggestions" and "Privacy" panes.
  struct SuggestionSettingsView: View {
    @Bindable var model: ConfigDialogModel

    var body: some View {
      Form {
        Section {
          Toggle(settingsText("Input history"), isOn: $model.values.useHistorySuggest)
          Toggle(settingsText("System dictionary"), isOn: $model.values.useDictionarySuggest)
        }
        Section {
          Toggle(isOn: $model.values.incognitoMode) {
            Text(verbatim: settingsText("Secret mode"))
            Text(
              verbatim: settingsText("Temporarily stops learning, history-based suggestions and the user dictionary."))
          }
        } header: {
          Text(verbatim: settingsText("Privacy"))
        }
      }
      .navigationTitle(settingsText("Suggestions"))
    }
  }

  struct SettingsPicker<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let items: [(Value, String)]

    var body: some View {
      Picker(label, selection: $selection) {
        ForEach(items, id: \.0) { item in
          Text(verbatim: item.1).tag(item.0)
        }
      }
    }
  }

  private struct TryItSection: View {
    @State private var text = ""

    var body: some View {
      Section {
        TextField(AppStrings.text(.tryItPlaceholder), text: $text, axis: .vertical)
          .lineLimit(3...6)
      } header: {
        Text(verbatim: AppStrings.text(.tryIt))
      } footer: {
        Text(verbatim: AppStrings.text(.aiFullAccess))
      }
    }
  }

  private struct AboutSection: View {
    var body: some View {
      Section {
        LabeledContent(AppStrings.text(.version), value: Version.getProductVersion())
        if let url = URL(string: "https://github.com/subdiox/genmai-ime") {
          Link(AppStrings.text(.sourceCode), destination: url)
        }
        NavigationLink(AppStrings.text(.licenses)) { CreditsView() }
      } header: {
        Text(verbatim: AppStrings.text(.about))
      }
    }
  }
#endif
