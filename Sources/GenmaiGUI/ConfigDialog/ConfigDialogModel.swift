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
import Synchronization

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
  public var incognitoMode = false
  public var presentationMode = false

  // tab6
  public var verboseLevel = 0
  public var checkDefault = true
  public var yenSignCharacter: C.YenSignCharacter = .yenSign

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

/// Not in Mozc: the newest release of a model, as far as the AI tab knows.
public enum AIModelLatestState: Equatable, Sendable {
  case unknown
  case checking(AIModelSize)
  case available(GenmaiModelRelease)
  case failed(String)
}

/// Not in Mozc: a model download of the AI tab.
public enum AIModelInstallState: Equatable, Sendable {
  case idle
  case running(AIModelInstaller.Phase)
  case failed(String)

  public var isRunning: Bool {
    if case .running = self { return true }
    return false
  }
}

@MainActor
@Observable
public final class ConfigDialogModel {
  static let context = "genmai::gui::ConfigDialog"

  public var values = ConfigDialogValues() {
    didSet {
      if !isLoading && values != oldValue {
        noteChange()
      }
    }
  }
  public let characterFormEditor = CharacterFormEditorModel()
  /// Not in Mozc: the AI tab (ai_conversion.json, saved together with the config).
  public var aiValues = AIConversionSettings() {
    didSet {
      if aiValues.modelDirectory != oldValue.modelDirectory || aiValues.modelSize != oldValue.modelSize {
        refreshAIModelStatus()
      }
      if !isLoading && aiValues != oldValue {
        noteChange()
      }
    }
  }
  /// Which model files exist in each model's directory (both models can be installed; `modelSize` picks the one the
  /// IME uses).
  public private(set) var aiModelStatuses: [AIModelSize: AIModelStatus] = [:]
  /// Bytes of each installed model on disk.
  public private(set) var aiModelDiskSizes: [AIModelSize: Int64] = [:]
  /// Not in Mozc: the model download / installation started from the AI tab (one at a time).
  public private(set) var aiModelInstall = AIModelInstallState.idle
  /// The model `aiModelInstall` is about.
  public private(set) var aiModelInstallSize: AIModelSize?
  private var aiModelInstallTask: Task<Void, Never>?
  /// Not in Mozc: the newest release of each model on Hugging Face, looked up when the AI tab is shown.
  public private(set) var aiModelLatest: [AIModelSize: AIModelLatestState] = [:]
  /// Looks up the newest release of a model (replaced by tests).
  var aiModelReleaseFetcher: @Sendable (AIModelSize) async throws -> GenmaiModelRelease = {
    try await GenmaiModelRelease.latest(repository: $0.repository)
  }
  /// Downloads and installs a model release into a directory (replaced by tests).
  var aiModelInstaller:
    @Sendable (GenmaiModelRelease, URL, @escaping @Sendable (AIModelInstaller.Phase) -> Void) async throws -> Void =
      { release, directory, progress in
        try await AIModelInstaller.install(release, to: directory, progress: progress)
      }
  /// Edits not saved yet (Mozc's 'Apply' button state: off on launching, on after any edit).
  public private(set) var hasPendingChanges = false
  /// Not in Mozc: the settings window has no OK / Cancel / Apply; edits are saved shortly after they are made
  /// (and when the window closes). Off for tests, which save with `apply()` / `accept()`.
  public var savesChangesAutomatically = false
  private var saveTask: Task<Void, Never>?
  static let saveDelay: Duration = .milliseconds(300)
  public var pendingMessage: GUIMessage?
  public var activeEditor: ConfigDialogEditor?

  private let client: any GenmaiClientProtocol
  private let openApp: @MainActor (String) -> Void
  private var baseConfig = Genmai_Config_Config()
  private var isLoading = false
  private let aiSettingsURL: URL?
  #if os(macOS)
    /// Not in Mozc: updates of Genmai itself (tab "Misc"). The iOS app is updated by the App Store.
    public let appUpdate: GenmaiUpdateModel
  #endif
  /// The AI settings as last loaded / saved.
  private var savedAIValues = AIConversionSettings()

  /// `aiSettingsURL`: where the AI settings are stored (nil: `AIConversionSettings.fileURL` in the profile).
  public init(
    client: any GenmaiClientProtocol,
    openApp: @escaping @MainActor (String) -> Void = { _ in },
    aiSettingsURL: URL? = nil
  ) {
    #if os(macOS)
      self.appUpdate = GenmaiUpdateModel()
    #endif
    self.client = client
    self.openApp = openApp
    self.aiSettingsURL = aiSettingsURL
    reload()
  }

  public var windowTitle: String { tr("Settings", "[ProductName] Settings") }

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
    refreshAIModelStatus()
  }

  /// The model files of `size` (the selected model by default).
  public func aiModelStatus(_ size: AIModelSize? = nil) -> AIModelStatus {
    let size = size ?? aiValues.modelSize
    return aiModelStatuses[size] ?? AIModelStatus.check(aiValues.modelDirectory(for: size))
  }

  /// Re-checks the model directories (the "Check again" button).
  public func refreshAIModelStatus() {
    for size in AIModelSize.allCases {
      let directory = aiValues.modelDirectory(for: size)
      let status = AIModelStatus.check(directory)
      aiModelStatuses[size] = status
      aiModelDiskSizes[size] = status.isFound ? Self.diskSize(of: directory) : nil
    }
  }

  /// Bytes of the files in `directory` (recursively).
  static func diskSize(of directory: URL) -> Int64 {
    guard
      let files = FileManager.default.enumerator(
        at: directory, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
    else { return 0 }
    var total: Int64 = 0
    for case let url as URL in files {
      let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
      if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
    }
    return total
  }

  /// Looks up the newest release of each model on Hugging Face (when the AI tab is shown; again after a failure or
  /// with `force`, the "Check again" button).
  public func checkLatestAIModels(force: Bool = false) async {
    for size in AIModelSize.allCases {
      await checkLatestAIModel(size, force: force)
    }
  }

  /// Looks up the newest release of `size`.
  public func checkLatestAIModel(_ size: AIModelSize, force: Bool = false) async {
    switch aiModelLatest[size] ?? .unknown {
    case .checking: return
    case .available where !force: return
    default: break
    }
    aiModelLatest[size] = .checking(size)
    let result: AIModelLatestState
    do {
      result = .available(try await aiModelReleaseFetcher(size))
    } catch {
      result = .failed("\(error)")
    }
    aiModelLatest[size] = result
  }

  /// Downloads the newest release of `size` from Hugging Face and installs it into its directory (the "Download" /
  /// "Update" button of its row). The IME is told to reload, so a running IME picks up the new model.
  public func installAIModel(_ size: AIModelSize) {
    guard aiModelInstallTask == nil, case .available(let release) = aiModelLatest[size] ?? .unknown,
      release.info.size == size
    else { return }
    let directory = aiValues.modelDirectory(for: size)
    aiModelInstallSize = size
    aiModelInstall = .running(.downloading(received: 0, total: release.downloadSize))
    let installer = aiModelInstaller
    // Progress arrives for every network chunk: forward it only when the shown permille changes.
    let lastShown = Mutex<Int>(-1)
    let report: @Sendable (AIModelInstaller.Phase) -> Void = { [weak self] phase in
      let key: Int
      switch phase {
      case .downloading(let received, let total): key = Int(received * 1000 / max(total, 1))
      case .verifying: key = 1001
      case .installing: key = 1002
      case .preparing: key = 1003
      }
      guard
        lastShown.withLock({ last in
          defer { last = key }
          return last != key
        })
      else { return }
      Task { @MainActor [weak self] in
        if case .running = self?.aiModelInstall { self?.aiModelInstall = .running(phase) }
      }
    }
    aiModelInstallTask = Task { [weak self] in
      let result: AIModelInstallState
      do {
        try await installer(release, directory, report)
        result = .idle
      } catch is CancellationError {
        result = .idle
      } catch {
        result = .failed("\(error)")
      }
      guard let self else { return }
      self.aiModelInstallTask = nil
      self.aiModelInstall = result
      self.refreshAIModelStatus()
      if result == .idle, self.aiModelStatus(size).isFound {
        _ = self.client.reload()
      }
    }
  }

  /// The "Remove…" button of a model's row: asks first, then deletes its files (`performRemoveAIModel`).
  public func removeAIModel(_ size: AIModelSize) {
    guard aiModelStatus(size).isFound, !aiModelInstall.isRunning else { return }
    let question = String(
      format: AIStrings.text(.removeConfirm), size.modelName, AIStrings.bytes(aiModelDiskSizes[size] ?? 0))
    showQuestion(question) { [weak self] in
      self?.performRemoveAIModel(size)
    }
  }

  /// Deletes the files of `size` and tells the IME to reload (without the selected model it converts without AI
  /// until one is installed again).
  func performRemoveAIModel(_ size: AIModelSize) {
    do {
      try AIModelInstaller.uninstall(from: aiValues.modelDirectory(for: size))
    } catch {
      showMessage(.critical, String(format: AIStrings.text(.removeFailed), "\(error)"))
    }
    if aiModelInstallSize == size {
      aiModelInstall = .idle
    }
    refreshAIModelStatus()
    _ = client.reload()
  }

  /// Cancels the running download / installation (the model directory is left as it was).
  public func cancelAIModelInstall() {
    aiModelInstallTask?.cancel()
  }

  /// ConvertFromProto.
  public func convertFromProto(_ config: Genmai_Config_Config) {
    isLoading = true
    defer { isLoading = false }
    baseConfig = config
    values = ConfigDialogValues(config: config)
    characterFormEditor.load(config)
  }

  /// ConvertToProto.
  public func convertToProto() -> Genmai_Config_Config {
    var config = baseConfig
    values.apply(to: &config)
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
    baseConfig = config
    return true
  }

  // MARK: - Buttons

  /// The OK button (AcceptRole). Returns true if the dialog should close.
  public func accept() -> Bool {
    guard update() else { return false }
    hasPendingChanges = false
    return true
  }

  /// The Apply button (ApplyRole).
  public func apply() {
    if update() {
      hasPendingChanges = false
    }
  }

  /// A custom keymap must have entries; the settings are not saved until it has (Update's warning, shown in
  /// place instead of an alert).
  public var hasEmptyCustomKeymap: Bool {
    values.sessionKeymap == .custom && values.customKeymapTable.isEmpty
  }

  private func noteChange() {
    hasPendingChanges = true
    guard savesChangesAutomatically else { return }
    saveTask?.cancel()
    saveTask = Task { [weak self] in
      try? await Task.sleep(for: Self.saveDelay)
      guard !Task.isCancelled else { return }
      self?.savePendingChanges()
    }
  }

  /// Saves the pending edits now (automatic saving; the window closes).
  public func savePendingChanges() {
    saveTask?.cancel()
    saveTask = nil
    guard hasPendingChanges, !hasEmptyCustomKeymap else { return }
    apply()
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
    if !client.openApp(mode: "dictionary_tool", extraArg: "") {
      openApp("dictionary_tool")
    }
  }

  /// "Reset to defaults" (with the confirmation).
  public func resetToDefaults() {
    markButtonClicked()
    let message = tr(
      "Settings",
      "Do you want to reset all settings to their defaults? Personalization data and input history are kept.")
    showQuestion(message) { [weak self] in
      self?.performResetToDefaults()
    }
  }

  func performResetToDefaults() {
    // TODO(taku): remove the dependency to config::ConfigHandler
    // nice to have GET_DEFAULT_CONFIG command
    convertFromProto(ConfigHandler.defaultConfig())
    aiValues = AIConversionSettings()
    noteChange()
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

  /// EnableApplyButton(): any button click / check box / combo box activation enables 'Apply' (and saves).
  public func markButtonClicked() {
    noteChange()
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
      (.kotoeri, tr(context, "Kotoeri")), (.msime, tr(context, "MS-IME")), (.atok, tr(context, "ATOK")),
      (.custom, tr(context, "Custom keymap")),
    ]
  }
  public static var inputModeItems: [(Int, String)] {
    [(0, tr("Settings", "Romaji input")), (1, tr("Settings", "Kana input"))]
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
      (.noShortcut, tr("Settings", "None")), (.shortcut123456789, tr("Settings", "1–9")),
      (.shortcutAsdfghjkl, tr("Settings", "A–L")),
    ]
  }
  public static var historyLearningLevelItems: [(Genmai_Config_Config.HistoryLearningLevel, String)] {
    [
      (.defaultHistory, tr("Settings", "Yes")), (.readOnly, tr("Settings", "Yes, without recording new data")),
      (.noHistory, tr("Settings", "No")),
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
