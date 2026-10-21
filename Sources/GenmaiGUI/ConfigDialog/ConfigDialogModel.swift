// Port of mozc/src/gui/config_dialog/config_dialog.{h,cc} (3.35.6354), macOS behavior.
//
// The Qt dialog keeps its state in widgets and converts with ConvertFromProto / ConvertToProto. The Swift
// port keeps the widget state in `ConfigDialogValues` (one field per widget, same names as the .ui file) and
// the dialog logic (Reload / Update / ClearUserHistory / ResetToDefaults / EditKeymap / EditRomanTable ...)
// in `ConfigDialogModel`. Windows-only widgets (IME hotkey, default IME check, administration dialog) are not
// shown, as on macOS; their config fields are carried through unchanged via `baseConfig`.

import Foundation
import GenmaiBase
import GenmaiClient
import GenmaiCore
import GenmaiProtocol
import Observation

/// The widget values of the config dialog.
public struct ConfigDialogValues: Equatable, Sendable {
  public typealias C = Genmai_Config_Config

  // tab1
  /// inputModeComboBox index: 0 = Romaji, 1 = Kana (the "switchable" items exist only on Windows).
  public var inputModeIndex = 0
  public var punctuationMethod: C.PunctuationMethod = .toutenKuten
  public var symbolMethod: C.SymbolMethod = .cornerBracketMiddleDot
  public var spaceCharacterForm: C.FundamentalCharacterForm = .fundamentalInputMode
  public var selectionShortcut: C.SelectionShortcut = .noShortcut
  public var numpadCharacterForm: C.NumpadCharacterForm = .numpadInputMode
  public var sessionKeymap: C.SessionKeymap = .custom
  public var customKeymapTable = ""
  public var customRomanTable = ""

  // tab2
  public var historyLearningLevel: C.HistoryLearningLevel = .defaultHistory
  public var useSingleKanjiConversion = true
  public var useSymbolConversion = true
  public var useEmoticonConversion = true
  public var useDateConversion = true
  public var useEmojiConversion = true
  public var useNumberConversion = true
  public var useCalculator = true
  public var useT13nConversion = true
  public var useZipCodeConversion = true
  public var useSpellingCorrection = true
  public var useLocalUsageDictionary = true

  // tab3
  public var autoSwitchCompositionMode = true
  public var useAutoConversion = false
  public var kuten = false
  public var touten = false
  public var questionMark = false
  public var exclamationMark = false
  public var shiftKeyModeSwitch: C.ShiftKeyModeSwitch = .asciiInputMode
  public var useJapaneseLayout = false
  public var useModeIndicator = true

  // tab4
  public var useHistorySuggest = true
  public var useDictionarySuggest = true
  public var useRealtimeConversion = true
  public var suggestionsSize = 3

  // tab5
  public var usageStats = false
  public var incognitoMode = false
  public var presentationMode = false

  // tab6
  public var verboseLevel = 0
  public var checkDefault = true
  public var yenSignCharacter: C.YenSignCharacter = .yenSign
  public var startup = false

  public init() {}

  static let kPreeditMethodSize = 2

  /// ConvertFromProto (without the character form editor, stats and login item).
  public init(config: C) {
    // tab1
    // SetComboboxForPreeditMethod: use_keyboard_to_change_preedit_method only matters on Windows.
    inputModeIndex = config.preeditMethod.rawValue
    punctuationMethod = config.punctuationMethod
    symbolMethod = config.symbolMethod
    spaceCharacterForm = config.spaceCharacterForm
    selectionShortcut = config.selectionShortcut
    numpadCharacterForm = config.numpadCharacterForm
    sessionKeymap = config.sessionKeymap
    customKeymapTable = String(decoding: config.customKeymapTable, as: UTF8.self)
    customRomanTable = String(decoding: config.customRomanTable, as: UTF8.self)

    // tab2
    historyLearningLevel = config.historyLearningLevel
    useSingleKanjiConversion = config.useSingleKanjiConversion
    useSymbolConversion = config.useSymbolConversion
    useEmoticonConversion = config.useEmoticonConversion
    useDateConversion = config.useDateConversion
    useEmojiConversion = config.useEmojiConversion
    useNumberConversion = config.useNumberConversion
    useCalculator = config.useCalculator
    useT13nConversion = config.useT13NConversion
    useZipCodeConversion = config.useZipCodeConversion
    useSpellingCorrection = config.useSpellingCorrection
    // InfoListConfig
    useLocalUsageDictionary = config.informationListConfig.useLocalUsageDictionary

    // tab3
    autoSwitchCompositionMode = config.autoSwitchCompositionMode
    useAutoConversion = config.useAutoConversion
    let key = config.autoConversionKey
    kuten = key & UInt32(C.AutoConversionKey.autoConversionKuten.rawValue) != 0
    touten = key & UInt32(C.AutoConversionKey.autoConversionTouten.rawValue) != 0
    questionMark = key & UInt32(C.AutoConversionKey.autoConversionQuestionMark.rawValue) != 0
    exclamationMark = key & UInt32(C.AutoConversionKey.autoConversionExclamationMark.rawValue) != 0
    shiftKeyModeSwitch = config.shiftKeyModeSwitch
    useJapaneseLayout = config.useJapaneseLayout
    useModeIndicator = config.useModeIndicator

    // tab4
    useHistorySuggest = config.useHistorySuggest
    useDictionarySuggest = config.useDictionarySuggest
    useRealtimeConversion = config.useRealtimeConversion
    suggestionsSize = min(max(Int(config.suggestionsSize), 1), 9)

    // tab5
    incognitoMode = config.incognitoMode
    presentationMode = config.presentationMode

    // tab6
    verboseLevel = Int(config.verboseLevel)
    checkDefault = config.checkDefault
    yenSignCharacter = config.yenSignCharacter
  }

  /// ConvertToProto (without the character form editor and stats): writes the widgets over `config`.
  public func apply(to config: inout C) {
    // tab1
    // GetComboboxForPreeditMethod
    if inputModeIndex >= Self.kPreeditMethodSize {
      config.preeditMethod = C.PreeditMethod(rawValue: inputModeIndex - Self.kPreeditMethodSize) ?? .roman
      config.useKeyboardToChangePreeditMethod = true
    } else {
      config.preeditMethod = C.PreeditMethod(rawValue: inputModeIndex) ?? .roman
      config.useKeyboardToChangePreeditMethod = false
    }
    config.punctuationMethod = punctuationMethod
    config.symbolMethod = symbolMethod
    config.spaceCharacterForm = spaceCharacterForm
    config.selectionShortcut = selectionShortcut
    config.numpadCharacterForm = numpadCharacterForm
    config.sessionKeymap = sessionKeymap

    config.customKeymapTable = Data(customKeymapTable.utf8)
    config.clearCustomRomanTable()
    if !customRomanTable.isEmpty {
      config.customRomanTable = Data(customRomanTable.utf8)
    }

    // tab2
    config.historyLearningLevel = historyLearningLevel
    config.useSingleKanjiConversion = useSingleKanjiConversion
    config.useSymbolConversion = useSymbolConversion
    config.useEmoticonConversion = useEmoticonConversion
    config.useDateConversion = useDateConversion
    config.useEmojiConversion = useEmojiConversion
    config.useNumberConversion = useNumberConversion
    config.useCalculator = useCalculator
    config.useT13NConversion = useT13nConversion
    config.useZipCodeConversion = useZipCodeConversion
    config.useSpellingCorrection = useSpellingCorrection
    // InformationListConfig
    config.informationListConfig.useLocalUsageDictionary = useLocalUsageDictionary

    // tab3
    config.autoSwitchCompositionMode = autoSwitchCompositionMode
    config.useAutoConversion = useAutoConversion
    config.useJapaneseLayout = useJapaneseLayout
    config.useModeIndicator = useModeIndicator
    var autoConversionKey: UInt32 = 0
    if kuten {
      autoConversionKey |= UInt32(C.AutoConversionKey.autoConversionKuten.rawValue)
    }
    if touten {
      autoConversionKey |= UInt32(C.AutoConversionKey.autoConversionTouten.rawValue)
    }
    if questionMark {
      autoConversionKey |= UInt32(C.AutoConversionKey.autoConversionQuestionMark.rawValue)
    }
    if exclamationMark {
      autoConversionKey |= UInt32(C.AutoConversionKey.autoConversionExclamationMark.rawValue)
    }
    config.autoConversionKey = autoConversionKey
    config.shiftKeyModeSwitch = shiftKeyModeSwitch

    // tab4
    config.useHistorySuggest = useHistorySuggest
    config.useDictionarySuggest = useDictionarySuggest
    config.useRealtimeConversion = useRealtimeConversion
    config.suggestionsSize = UInt32(suggestionsSize)

    // tab5
    config.incognitoMode = incognitoMode
    config.presentationMode = presentationMode

    // tab6
    config.verboseLevel = Int32(verboseLevel)
    config.checkDefault = checkDefault
    config.yenSignCharacter = yenSignCharacter
  }

  // MARK: - Enabled states (SelectInputModeSetting / SelectAutoConversionSetting / SelectSuggestionSetting)

  /// The romaji table "Customize..." button is enabled only for Romaji input.
  public var isRomanTableEditable: Bool { inputModeIndex == 0 }
  /// The punctuation check boxes follow "Convert at punctuations".
  public var isAutoConversionKeyEditable: Bool { useAutoConversion }
  /// Presentation mode is meaningful only when some suggestion source is on.
  public var isPresentationModeEditable: Bool {
    useHistorySuggest || useDictionarySuggest || useRealtimeConversion
  }
}

/// Platform hooks of the dialog (StatsConfigUtil, MacUtil login item).
public struct ConfigDialogPlatform: Sendable {
  public var isUsageStatsEnabled: @MainActor @Sendable () -> Bool
  public var setUsageStatsEnabled: @MainActor @Sendable (Bool) -> Void
  public var isLoginItemEnabled: @MainActor @Sendable () -> Bool
  public var setLoginItemEnabled: @MainActor @Sendable (Bool) -> Void

  public init(
    isUsageStatsEnabled: @escaping @MainActor @Sendable () -> Bool,
    setUsageStatsEnabled: @escaping @MainActor @Sendable (Bool) -> Void,
    isLoginItemEnabled: @escaping @MainActor @Sendable () -> Bool,
    setLoginItemEnabled: @escaping @MainActor @Sendable (Bool) -> Void
  ) {
    self.isUsageStatsEnabled = isUsageStatsEnabled
    self.setUsageStatsEnabled = setUsageStatsEnabled
    self.isLoginItemEnabled = isLoginItemEnabled
    self.setLoginItemEnabled = setLoginItemEnabled
  }

  /// The OSS build: NullStatsConfigUtilImpl (never enabled) and no prelauncher login item (the Swift IME
  /// has no separate converter process to start on login).
  public static let oss = ConfigDialogPlatform(
    isUsageStatsEnabled: { false }, setUsageStatsEnabled: { _ in },
    isLoginItemEnabled: { false }, setLoginItemEnabled: { _ in })
}

/// The modal sub-editors opened from the dialog.
public enum ConfigDialogEditor: Identifiable, Equatable, Sendable {
  case keymap(currentTable: String)
  case romanTable(currentTable: String)

  public var id: String {
    switch self {
    case .keymap: "keymap"
    case .romanTable: "romanTable"
    }
  }
}

@MainActor
@Observable
public final class ConfigDialogModel {
  static let context = "genmai::gui::ConfigDialog"

  public var values = ConfigDialogValues() {
    didSet {
      if !isLoading && values != oldValue {
        applyEnabled = true
      }
    }
  }
  public let characterFormEditor = CharacterFormEditorModel()
  /// Not in Mozc: the AI tab (ai_conversion.json, saved together with the config).
  public var aiValues = AIConversionSettings() {
    didSet {
      if aiValues.modelDirectory != oldValue.modelDirectory {
        aiModelStatus = AIModelStatus.check(aiValues.resolvedModelDirectory)
      }
      if !isLoading && aiValues != oldValue {
        applyEnabled = true
      }
    }
  }
  /// Whether the model files exist in the selected model directory.
  public private(set) var aiModelStatus = AIModelStatus.check(AIConversionSettings.defaultModelDirectory)
  /// 'Apply' button is disabled on launching and enabled by any edit.
  public private(set) var applyEnabled = false
  public var pendingMessage: GUIMessage?
  public var activeEditor: ConfigDialogEditor?

  private let client: any GenmaiClientProtocol
  private let platform: ConfigDialogPlatform
  private let launchTool: @MainActor (String) -> Void
  private var baseConfig = Genmai_Config_Config()
  private var isLoading = false
  private let aiSettingsURL: URL?
  /// The AI settings as last loaded / saved.
  private var savedAIValues = AIConversionSettings()

  /// `aiSettingsURL`: where the AI settings are stored (nil: `AIConversionSettings.fileURL` in the profile).
  public init(
    client: any GenmaiClientProtocol,
    platform: ConfigDialogPlatform = .oss,
    launchTool: @escaping @MainActor (String) -> Void = { _ in },
    aiSettingsURL: URL? = nil
  ) {
    self.client = client
    self.platform = platform
    self.launchTool = launchTool
    self.aiSettingsURL = aiSettingsURL
    reload()
  }

  /// setWindowTitle(tr("%1 Preferences")) on macOS.
  public var windowTitle: String { tr(Self.context, "[ProductName] Preferences") }

  // MARK: - Config I/O

  private func getConfig() -> Genmai_Config_Config? {
    if !client.checkVersionOrRestartServer() {
      return nil
    }
    return client.getConfig()
  }

  private func setConfig(_ config: Genmai_Config_Config) -> Bool {
    if !client.checkVersionOrRestartServer() {
      return false
    }
    return client.setConfig(config)
  }

  /// Reload().
  public func reload() {
    let config: Genmai_Config_Config
    if let current = getConfig() {
      config = current
    } else {
      showMessage(.critical, tr(Self.context, "Failed to get current config values."))
      config = Genmai_Config_Config()
    }
    convertFromProto(config)
    loadAISettings()
  }

  private func loadAISettings() {
    isLoading = true
    defer { isLoading = false }
    aiValues = AIConversionSettings.load(from: aiSettingsURL ?? AIConversionSettings.fileURL)
    savedAIValues = aiValues
    aiModelStatus = AIModelStatus.check(aiValues.resolvedModelDirectory)
  }

  /// Re-checks the model directory (the "Check again" button).
  public func refreshAIModelStatus() {
    aiModelStatus = AIModelStatus.check(aiValues.resolvedModelDirectory)
  }

  /// ConvertFromProto.
  public func convertFromProto(_ config: Genmai_Config_Config) {
    isLoading = true
    defer { isLoading = false }
    baseConfig = config
    var newValues = ConfigDialogValues(config: config)
    newValues.usageStats = platform.isUsageStatsEnabled()
    newValues.startup = platform.isLoginItemEnabled()
    values = newValues
    characterFormEditor.load(config)
  }

  /// ConvertToProto.
  public func convertToProto() -> Genmai_Config_Config {
    var config = baseConfig
    values.apply(to: &config)
    // GetSendStatsCheckBox
    platform.setUsageStatsEnabled(values.usageStats)
    characterFormEditor.save(&config)
    return config
  }

  /// Update(): returns false if the dialog must stay open.
  @discardableResult
  public func update() -> Bool {
    let config = convertToProto()
    if config.sessionKeymap == .custom && config.customKeymapTable.isEmpty {
      showMessage(
        .warning,
        tr(
          Self.context,
          "The current custom keymap table is empty. When custom keymap is selected, you must customize it."
        ))
      return false
    }
    // The AI settings first (only when changed): SET_CONFIG makes the IME reload, which also re-reads them.
    if aiValues != savedAIValues {
      do {
        try aiValues.save(to: aiSettingsURL ?? AIConversionSettings.fileURL)
        savedAIValues = aiValues
      } catch {
        showMessage(.critical, AIStrings.text(.saveFailed))
      }
    }
    if !setConfig(config) {
      showMessage(.critical, tr(Self.context, "Failed to update config"))
    }
    if values.startup != platform.isLoginItemEnabled() {
      platform.setLoginItemEnabled(values.startup)
    }
    baseConfig = config
    return true
  }

  // MARK: - Buttons

  /// The OK button (AcceptRole). Returns true if the dialog should close.
  public func accept() -> Bool { update() }

  /// The Apply button (ApplyRole).
  public func apply() {
    update()
  }

  /// "Clear personalization data".
  public func clearUserHistory() {
    markButtonClicked()
    showQuestion(tr(Self.context, "Do you want to clear all history data?")) { [weak self] in
      self?.performClearUserHistory()
    }
  }

  func performClearUserHistory() {
    _ = client.checkVersionOrRestartServer()
    if !client.clearUserHistory() || !client.clearUserPrediction() {
      showMessage(
        .critical, tr(Self.context, "[ProductName] Converter is not running. Settings were not saved."))
    }
  }

  /// "Edit user dictionary...".
  public func editUserDictionary() {
    markButtonClicked()
    if !client.launchTool(mode: "dictionary_tool", extraArg: "") {
      launchTool("dictionary_tool")
    }
  }

  /// "Reset to defaults" (with the confirmation).
  public func resetToDefaults() {
    markButtonClicked()
    let message = tr(
      Self.context,
      "When you reset [ProductName] settings, any changes you've made will be reverted to the default settings. Do you want to reset settings? The following items are not reset with this operation.\n - Personalization data\n - Input history\n - Usage statistics and crash reports\n - Administrator settings"
    )
    showQuestion(message) { [weak self] in
      self?.performResetToDefaults()
    }
  }

  func performResetToDefaults() {
    // TODO(taku): remove the dependency to config::ConfigHandler
    // nice to have GET_DEFAULT_CONFIG command
    convertFromProto(ConfigHandler.defaultConfig())
    aiValues = AIConversionSettings()
    applyEnabled = true
  }

  /// The keymap "Customize..." button (EditKeymap).
  public func editKeymap() {
    markButtonClicked()
    let current: String
    switch values.sessionKeymap {
    case .atok, .msime, .kotoeri:
      // Load from predefined mapping file.
      current = KeyMapEditorModel.predefinedKeymapTable(values.sessionKeymap)
    default:
      current = values.customKeymapTable
    }
    activeEditor = .keymap(currentTable: current)
  }

  /// Result of the keymap editor (KeyMapEditorDialog::Show).
  public func finishKeymapEditor(_ output: String?) {
    activeEditor = nil
    if let output {
      values.customKeymapTable = output
      // set keymapSettingComboBox to "Custom keymap"
      values.sessionKeymap = .custom
    }
  }

  /// The romaji table "Customize..." button (EditRomanTable).
  public func editRomanTable() {
    markButtonClicked()
    activeEditor = .romanTable(currentTable: values.customRomanTable)
  }

  /// Result of the romaji table editor (RomanTableEditorDialog::Show).
  public func finishRomanTableEditor(_ output: String?) {
    activeEditor = nil
    if let output {
      values.customRomanTable = output
    }
  }

  /// EnableApplyButton(): any button click / check box / combo box activation enables 'Apply'.
  public func markButtonClicked() {
    applyEnabled = true
  }

  // MARK: - Option lists (the items added in the constructor)

  public static let punctuationItems: [(Genmai_Config_Config.PunctuationMethod, String)] = [
    (.toutenKuten, "、。"), (.commaPeriod, "，．"), (.toutenPeriod, "、．"), (.commaKuten, "，。"),
  ]
  public static let symbolItems: [(Genmai_Config_Config.SymbolMethod, String)] = [
    (.cornerBracketMiddleDot, "「」・"), (.squareBracketSlash, "[]／"),
    (.cornerBracketSlash, "「」／"), (.squareBracketMiddleDot, "[]・"),
  ]
  public static var keymapItems: [(Genmai_Config_Config.SessionKeymap, String)] {
    [
      (.custom, tr(context, "Custom keymap")), (.atok, tr(context, "ATOK")),
      (.msime, tr(context, "MS-IME")), (.kotoeri, tr(context, "Kotoeri")),
    ]
  }
  public static var inputModeItems: [(Int, String)] {
    [(0, tr(context, "Romaji")), (1, tr(context, "Kana"))]
  }
  public static var spaceCharacterFormItems: [(Genmai_Config_Config.FundamentalCharacterForm, String)] {
    [
      (.fundamentalInputMode, tr(context, "Follow input mode")),
      (.fundamentalFullWidth, tr(context, "Fullwidth")),
      (.fundamentalHalfWidth, tr(context, "Halfwidth")),
    ]
  }
  public static var selectionShortcutItems: [(Genmai_Config_Config.SelectionShortcut, String)] {
    [
      (.noShortcut, tr(context, "No shortcut")), (.shortcut123456789, tr(context, "1 -- 9")),
      (.shortcutAsdfghjkl, tr(context, "A -- L")),
    ]
  }
  public static var historyLearningLevelItems: [(Genmai_Config_Config.HistoryLearningLevel, String)] {
    [
      (.defaultHistory, tr(context, "Yes")), (.readOnly, tr(context, "Yes (don't record new data)")),
      (.noHistory, tr(context, "No")),
    ]
  }
  public static var shiftKeyModeSwitchItems: [(Genmai_Config_Config.ShiftKeyModeSwitch, String)] {
    [
      (.off, tr(context, "Off")), (.asciiInputMode, tr(context, "Alphanumeric")),
      (.katakanaInputMode, tr(context, "Katakana")),
    ]
  }
  public static var numpadCharacterFormItems: [(Genmai_Config_Config.NumpadCharacterForm, String)] {
    [
      (.numpadInputMode, tr(context, "Follow input mode")), (.numpadFullWidth, tr(context, "Fullwidth")),
      (.numpadHalfWidth, tr(context, "Halfwidth")), (.numpadDirectInput, tr(context, "Direct input")),
    ]
  }
  public static var verboseLevelItems: [(Int, String)] {
    [(0, tr(context, "0")), (1, tr(context, "1")), (2, tr(context, "2"))]
  }
  public static var yenSignItems: [(Genmai_Config_Config.YenSignCharacter, String)] {
    [(.yenSign, tr(context, "Yen Sign ¥")), (.backslash, tr(context, "Backslash \\"))]
  }

  // MARK: - Messages

  private func showMessage(_ kind: GUIMessage.Kind, _ text: String) {
    pendingMessage = GUIMessage(kind: kind, title: windowTitle, text: text)
  }

  private func showQuestion(_ text: String, _ onYes: @escaping @MainActor @Sendable () -> Void) {
    pendingMessage = GUIMessage(kind: .question, title: windowTitle, text: text, onYes: onYes)
  }
}
