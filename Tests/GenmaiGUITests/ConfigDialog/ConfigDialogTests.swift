// Tests for the config dialog model (port of gui/config_dialog/config_dialog.cc logic).

import Foundation
import GenmaiCore
import GenmaiProtocol
import Testing

@testable import GenmaiGUI

/// A config with every field the dialog edits set to a non-default value.
private func makeNonDefaultConfig() -> Genmai_Config_Config {
  var config = ConfigHandler.defaultConfig()
  config.preeditMethod = .kana
  config.useKeyboardToChangePreeditMethod = false
  config.punctuationMethod = .commaKuten
  config.symbolMethod = .squareBracketMiddleDot
  config.spaceCharacterForm = .fundamentalHalfWidth
  config.selectionShortcut = .shortcutAsdfghjkl
  config.numpadCharacterForm = .numpadDirectInput
  config.sessionKeymap = .kotoeri
  config.customKeymapTable = Data("status\tkey\tcommand\nPrecomposition\tCtrl a\tIMEOn\n".utf8)
  config.customRomanTable = Data("a\tあ\n".utf8)
  config.historyLearningLevel = .readOnly
  config.useSingleKanjiConversion = false
  config.useSymbolConversion = false
  config.useEmoticonConversion = false
  config.useDateConversion = false
  config.useEmojiConversion = false
  config.useNumberConversion = false
  config.useCalculator = false
  config.useT13NConversion = false
  config.useZipCodeConversion = false
  config.useSpellingCorrection = false
  config.informationListConfig.useLocalUsageDictionary = false
  config.autoSwitchCompositionMode = false
  config.useAutoConversion = true
  config.autoConversionKey = 1 | 4 | 8
  config.shiftKeyModeSwitch = .katakanaInputMode
  config.useJapaneseLayout = true
  config.useModeIndicator = false
  config.useHistorySuggest = false
  config.useDictionarySuggest = false
  config.useRealtimeConversion = false
  config.suggestionsSize = 7
  config.incognitoMode = true
  config.presentationMode = true
  config.verboseLevel = 2
  config.checkDefault = false
  config.yenSignCharacter = .backslash
  var rule = Genmai_Config_Config.CharacterFormRule()
  rule.group = "0"
  rule.preeditCharacterForm = .halfWidth
  rule.conversionCharacterForm = .lastForm
  config.characterFormRules = [rule]
  return config
}

@MainActor
@Suite struct ConfigDialogTests {
  @Test func convertRoundTripKeepsEveryField() {
    let config = makeNonDefaultConfig()
    let client = ConfigDialogMockClient(config: config)
    let model = ConfigDialogModel(client: client)
    #expect(model.values.inputModeIndex == 1)
    #expect(model.values.kuten && !model.values.touten && model.values.questionMark && model.values.exclamationMark)
    #expect(model.values.suggestionsSize == 7)
    #expect(model.convertToProto() == config)
  }

  @Test func convertRoundTripOfDefaultConfig() {
    let config = ConfigHandler.defaultConfig()
    let model = ConfigDialogModel(client: ConfigDialogMockClient(config: config))
    var expected = config
    // ConvertToProto always sets these (has-bits) like the C++ setters.
    expected.useKeyboardToChangePreeditMethod = false
    expected.customKeymapTable = Data()
    let actual = model.convertToProto()
    #expect(actual.characterFormRules == config.characterFormRules)
    #expect(actual.sessionKeymap == config.sessionKeymap)
    #expect(actual.suggestionsSize == config.suggestionsSize)
    #expect(actual.useKeyboardToChangePreeditMethod == false)
  }

  @Test func suggestionsSizeIsClamped() {
    var config = Genmai_Config_Config()
    config.suggestionsSize = 20
    #expect(ConfigDialogValues(config: config).suggestionsSize == 9)
    config.suggestionsSize = 0
    #expect(ConfigDialogValues(config: config).suggestionsSize == 1)
  }

  @Test func getConfigFailureShowsCritical() {
    let model = ConfigDialogModel(client: ConfigDialogMockClient(config: nil))
    #expect(model.pendingMessage?.kind == .critical)
  }

  @Test func applyButtonIsDisabledOnLaunchAndEnabledByEdits() {
    let model = ConfigDialogModel(client: ConfigDialogMockClient())
    #expect(!model.applyEnabled)
    model.values.useCalculator.toggle()
    #expect(model.applyEnabled)
  }

  @Test func updateRejectsEmptyCustomKeymap() {
    var config = ConfigHandler.defaultConfig()
    config.sessionKeymap = .custom
    config.customKeymapTable = Data()
    let client = ConfigDialogMockClient(config: config)
    let model = ConfigDialogModel(client: client)
    #expect(!model.update())
    #expect(model.pendingMessage?.kind == .warning)
    #expect(client.setConfigCalls.isEmpty)
  }

  @Test func updateSendsConfig() {
    let client = ConfigDialogMockClient(config: ConfigHandler.defaultConfig())
    let model = ConfigDialogModel(client: client)
    model.values.incognitoMode = true
    #expect(model.accept())
    #expect(client.setConfigCalls.count == 1)
    #expect(client.setConfigCalls[0].incognitoMode)
  }

  @Test func updateFailureShowsCriticalButCloses() {
    let client = ConfigDialogMockClient(config: ConfigHandler.defaultConfig())
    client.setConfigResult = false
    let model = ConfigDialogModel(client: client)
    #expect(model.update())
    #expect(model.pendingMessage?.kind == .critical)
  }

  @Test func resetToDefaultsAsksAndRestoresDefaults() {
    let model = ConfigDialogModel(client: ConfigDialogMockClient(config: makeNonDefaultConfig()))
    model.resetToDefaults()
    let message = try! #require(model.pendingMessage)
    #expect(message.kind == .question)
    #expect(model.values.incognitoMode)
    message.onYes?()
    #expect(model.values == ConfigDialogValues(config: ConfigHandler.defaultConfig()))
    #expect(model.applyEnabled)
  }

  @Test func clearUserHistoryAsksThenClearsBoth() {
    let client = ConfigDialogMockClient()
    let model = ConfigDialogModel(client: client)
    model.clearUserHistory()
    #expect(client.clearUserHistoryCount == 0)
    model.pendingMessage?.onYes?()
    #expect(client.clearUserHistoryCount == 1)
    #expect(client.clearUserPredictionCount == 1)
  }

  @Test func clearUserHistoryFailure() {
    let client = ConfigDialogMockClient()
    client.clearUserHistoryResult = false
    let model = ConfigDialogModel(client: client)
    model.performClearUserHistory()
    #expect(model.pendingMessage?.kind == .critical)
    // ClearUserPrediction is not called when ClearUserHistory fails (short circuit).
    #expect(client.clearUserPredictionCount == 0)
  }

  @Test func editUserDictionaryLaunchesTool() {
    let client = ConfigDialogMockClient()
    let model = ConfigDialogModel(client: client)
    model.editUserDictionary()
    #expect(client.launchedTools == ["dictionary_tool"])
  }

  @Test func editKeymapLoadsPredefinedTableAndSwitchesToCustom() {
    var config = ConfigHandler.defaultConfig()
    config.sessionKeymap = .msime
    let model = ConfigDialogModel(client: ConfigDialogMockClient(config: config))
    model.editKeymap()
    #expect(model.activeEditor == .keymap(currentTable: KeyMapEditorModel.predefinedKeymapTable(.msime)))
    model.finishKeymapEditor("status\tkey\tcommand\n")
    #expect(model.values.sessionKeymap == .custom)
    #expect(model.values.customKeymapTable == "status\tkey\tcommand\n")
    #expect(model.activeEditor == nil)
  }

  @Test func editKeymapCancelKeepsKeymap() {
    var config = ConfigHandler.defaultConfig()
    config.sessionKeymap = .atok
    let model = ConfigDialogModel(client: ConfigDialogMockClient(config: config))
    model.editKeymap()
    model.finishKeymapEditor(nil)
    #expect(model.values.sessionKeymap == .atok)
  }

  @Test func editRomanTable() {
    let model = ConfigDialogModel(client: ConfigDialogMockClient(config: ConfigHandler.defaultConfig()))
    model.editRomanTable()
    #expect(model.activeEditor == .romanTable(currentTable: ""))
    model.finishRomanTableEditor("a\tあ\n")
    #expect(model.convertToProto().customRomanTable == Data("a\tあ\n".utf8))
    model.finishRomanTableEditor("")
    #expect(!model.convertToProto().hasCustomRomanTable)
  }

  @Test func enabledStates() {
    var values = ConfigDialogValues()
    values.inputModeIndex = 1
    #expect(!values.isRomanTableEditable)
    values.useAutoConversion = false
    #expect(!values.isAutoConversionKeyEditable)
    values.useHistorySuggest = false
    values.useDictionarySuggest = false
    values.useRealtimeConversion = false
    #expect(!values.isPresentationModeEditable)
    values.useRealtimeConversion = true
    #expect(values.isPresentationModeEditable)
  }

  @Test func platformHooks() {
    nonisolated(unsafe) var loginItem = false
    let platform = ConfigDialogPlatform(
      isLoginItemEnabled: { loginItem }, setLoginItemEnabled: { loginItem = $0 })
    let model = ConfigDialogModel(
      client: ConfigDialogMockClient(config: ConfigHandler.defaultConfig()), platform: platform)
    model.values.startup = true
    #expect(model.update())
    #expect(loginItem)
  }

  @Test func japaneseLabels() {
    #expect(tr("ConfigDialog", "General", language: .japanese) == "一般")
    #expect(tr("genmai::gui::ConfigDialog", "[ProductName] Preferences", language: .japanese) == "Genmai 環境設定")
    #expect(tr("genmai::gui::ConfigDialog", "Romaji", language: .english) == "Romaji")
  }
}
