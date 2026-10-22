// Port of mozc/src/session/keymap.{h,cc} (3.35.6354).
//
// Keymap utils of Mozc interface.

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import Synchronization

public enum DirectInputState {
  public enum Commands: Int, Sendable, Hashable {
    case none = 0
    case imeOn
    // Switch input mode.
    case compositionModeHiragana
    case compositionModeFullKatakana
    case compositionModeHalfKatakana
    case compositionModeFullAlphanumeric
    case compositionModeHalfAlphanumeric
    case reconvert
  }
}

public enum PrecompositionState {
  public enum Commands: Int, Sendable, Hashable {
    case none = 0
    case imeOff
    case imeOn
    case insertCharacter  // Move to Composition status.
    case insertSpace  // To handle spaces.
    // to handle shift+spaces (useally toggle half/full with)
    case insertAlternateSpace
    case insertHalfSpace  // Input half-width space
    case insertFullSpace  // Input full-width space
    case toggleAlphanumericMode  // toggle AlphaNumeric and Hiragana mode.
    // Switch input mode.
    case compositionModeHiragana
    case compositionModeFullKatakana
    case compositionModeHalfKatakana
    case compositionModeFullAlphanumeric
    case compositionModeHalfAlphanumeric
    case compositionModeSwitchKanaType  // rotate input mode
    case launchConfigDialog
    case launchDictionaryTool
    case launchWordRegisterDialog
    case revert  // revert last operation (preedit still remains)
    case undo  // undo last operation (preedit is restored)
    case reconvert

    // For ZeroQuerySuggestion
    case cancel  // Back to Composition status.
    case cancelAndImeOff  // Cancel composition and turn off IME
    case commitFirstSuggestion  // ATOK's Shift-Enter style
    case predictAndConvert

    // For search button on mobile device.
    case imeAction
  }
}

public enum CompositionState {
  public enum Commands: Int, Sendable, Hashable {
    case none = 0
    case imeOff
    case imeOn
    case insertCharacter
    case del  // DELETE cannot be used on Windows.  It is defined as a macro.
    case backspace
    case insertSpace  // To handle spaces.
    // to handle shift+spaces (useally toggle half/full with)
    case insertAlternateSpace
    case insertHalfSpace  // Input half-width space
    case insertFullSpace  // Input full-width space
    case cancel  // Move to Precomposition status.
    case cancelAndImeOff  // Cancel composition and turn off IME
    case undo
    case moveCursorLeft
    case moveCursorRight
    case moveCursorToBeginning
    case moveMoveCursorToEnd
    case commit  // Move to Precomposition status.
    case commitFirstSuggestion  // ATOK's Shift-Enter style
    case convert  // Move to Conversion status.
    case convertWithoutHistory  // Move to Conversion status.
    case predictAndConvert
    // Switching to ConversionState
    case convertToHiragana  // F6
    case convertToFullKatakana  // F7
    case convertToHalfKatakana
    case convertToHalfWidth  // F8
    case convertToFullAlphanumeric  // F9
    case convertToHalfAlphanumeric  // F10
    case switchKanaType  // Muhenkan
    // Rmaining CompositionState
    case displayAsHiragana  // F6
    case displayAsFullKatakana  // F7
    case displayAsHalfKatakana
    case translateHalfWidth  // F8
    case translateFullAscii  // F9
    case translateHalfAscii  // F10
    case toggleAlphanumericMode  // toggle AlphaNumeric and Hiragana mode.
    // Switch input mode.
    case compositionModeHiragana
    case compositionModeFullKatakana
    case compositionModeHalfKatakana
    case compositionModeFullAlphanumeric
    case compositionModeHalfAlphanumeric
  }
}

public enum ConversionState {
  public enum Commands: Int, Sendable, Hashable {
    case none = 0
    case imeOff
    case imeOn
    case insertCharacter  // Submit and Move to Composition status.
    case insertSpace  // To handle spaces.
    // to handle shift+spaces (useally toggle half/full with)
    case insertAlternateSpace
    case insertHalfSpace  // Input half-width space
    case insertFullSpace  // Input full-width space
    case cancel  // Back to Composition status.
    case cancelAndImeOff  // Cancel composition and turn off IME
    case undo
    case segmentFocusLeft
    case segmentFocusRight
    case segmentFocusFirst
    case segmentFocusLast
    case segmentWidthExpand
    case segmentWidthShrink
    case convertNext
    case convertPrev
    case convertNextPage
    case convertPrevPage
    case predictAndConvert
    case commit  // Move to Precomposition status.
    case commitSegment  // Down on the ATOK style.
    // CONVERT_TO and TRANSLATE are same behavior on ConversionState.
    case convertToHiragana  // F6
    case convertToFullKatakana  // F7
    case convertToHalfKatakana
    case convertToHalfWidth  // F8
    case convertToFullAlphanumeric  // F9
    case convertToHalfAlphanumeric  // F10
    case switchKanaType  // Muhenkan
    case displayAsHiragana  // F6
    case displayAsFullKatakana  // F7
    case displayAsHalfKatakana
    case translateHalfWidth  // F8
    case translateFullAscii  // F9
    case translateHalfAscii  // F10
    case toggleAlphanumericMode  // toggle AlphaNumeric and Hiragana mode.
    // Switch input mode.
    case compositionModeHiragana
    case compositionModeFullKatakana
    case compositionModeHalfKatakana
    case compositionModeFullAlphanumeric
    case compositionModeHalfAlphanumeric
    case deleteSelectedCandidate
    case reportBug
  }
}

/// KeyMap<T>: a key-event-to-command table.
public struct KeyMap<Command: Hashable & Sendable>: Sendable {
  private var keymap: [KeyInformation: Command] = [:]

  public init() {}

  public func getCommand(_ keyEvent: Genmai_Commands_KeyEvent) -> Command? {
    // Shortcut keys should be available as if CapsLock was not enabled like
    // other IMEs such as MS-IME or ATOK. b/5627459
    var normalizedKeyEvent = Genmai_Commands_KeyEvent()
    KeyEventUtil.normalizeModifiers(keyEvent, &normalizedKeyEvent)
    var key: KeyInformation = 0
    if !KeyEventUtil.getKeyInformation(normalizedKeyEvent, &key) {
      return nil
    }

    if let command = keymap[key] {
      return command
    }

    if KeyEventUtil.maybeGetKeyStub(normalizedKeyEvent, &key) {
      if let command = keymap[key] {
        return command
      }
    }

    return nil
  }

  /// C++ `bool GetCommand(key_event, CommandsType* command)`.
  public func getCommand(_ keyEvent: Genmai_Commands_KeyEvent, _ command: inout Command) -> Bool {
    guard let result = getCommand(keyEvent) else { return false }
    command = result
    return true
  }

  @discardableResult
  public mutating func addRule(_ keyEvent: Genmai_Commands_KeyEvent, _ command: Command) -> Bool {
    var key: KeyInformation = 0
    if !KeyEventUtil.getKeyInformation(keyEvent, &key) {
      return false
    }
    keymap[key] = command
    return true
  }

  public mutating func clear() {
    keymap.removeAll()
  }
}

private let kMSIMEKeyMapFile = "system://ms-ime.tsv"
private let kATOKKeyMapFile = "system://atok.tsv"
private let kKotoeriKeyMapFile = "system://kotoeri.tsv"
// keymap.tsv is a write-only file for debugging purposes.
private let kCustomKeyMapFile = "user://keymap.tsv"
private let kMobileKeyMapFile = "system://mobile.tsv"
private let kChromeOsKeyMapFile = "system://chromeos.tsv"
private let kOverlayHenkanMuhenkanToImeOnOffKeyMapFile =
  "system://overlay_henkan_muhenkan_to_ime_on_off.tsv"

private let kCommandStringCompositionModeHiragana = "CompositionModeHiragana"
private let kCommandStringCompositionModeFullKatakana = "CompositionModeFullKatakana"
private let kCommandStringCompositionModeHalfKatakana = "CompositionModeHalfKatakana"
private let kCommandStringCompositionModeFullAlphanumeric = "CompositionModeFullAlphanumeric"
private let kCommandStringCompositionModeHalfAlphanumeric = "CompositionModeHalfAlphanumeric"
private let kCommandStringCompositionModeSwitchKanaType = "CompositionModeSwitchKanaType"

private let kLegacyCommandStringsToCommandStrings: [String: String] = [
  "InputModeHiragana": kCommandStringCompositionModeHiragana,
  "InputModeFullKatakana": kCommandStringCompositionModeFullKatakana,
  "InputModeHalfKatakana": kCommandStringCompositionModeHalfKatakana,
  "InputModeFullAlphanumeric": kCommandStringCompositionModeFullAlphanumeric,
  "InputModeHalfAlphanumeric": kCommandStringCompositionModeHalfAlphanumeric,
  "InputModeSwitchKanaType": kCommandStringCompositionModeSwitchKanaType,
]

private func normalizeCommand(_ commandString: String) -> String {
  kLegacyCommandStringsToCommandStrings[commandString] ?? commandString
}

/// Reads keymap rules from `ifs` with the std::getline loop used by Mozc:
/// the first line is skipped, and each following line is chopped.
func forEachKeyMapLine(_ ifs: InputFileStream, _ body: (String) -> Void) {
  _ = ifs.getline()  // Skip the first line.
  while !ifs.eof {
    var line = ifs.getline() ?? ""
    _ = Util.chopReturns(&line)
    body(line)
  }
}

/// absl::StrSplit(line, '\t', absl::SkipEmpty()).
func splitTabSkipEmpty(_ line: String) -> [String] {
  line.split(separator: "\t", omittingEmptySubsequences: true).map(String.init)
}
/// The tables of a KeyMapManager.
struct KeyMapManagerState: Sendable {

  var commandDirectMap: [String: DirectInputState.Commands] = [:]
  var commandPrecompositionMap: [String: PrecompositionState.Commands] = [:]
  var commandCompositionMap: [String: CompositionState.Commands] = [:]
  var commandConversionMap: [String: ConversionState.Commands] = [:]

  var reverseCommandDirectMap: [DirectInputState.Commands: String] = [:]
  var reverseCommandPrecompositionMap: [PrecompositionState.Commands: String] = [:]
  var reverseCommandCompositionMap: [CompositionState.Commands: String] = [:]
  var reverseCommandConversionMap: [ConversionState.Commands: String] = [:]

  // Status should be out of keymap.
  var keymapDirect = KeyMap<DirectInputState.Commands>()
  var keymapPrecomposition = KeyMap<PrecompositionState.Commands>()
  var keymapComposition = KeyMap<CompositionState.Commands>()
  var keymapConversion = KeyMap<ConversionState.Commands>()

  // enabled only if zero query suggestion is shown. Otherwise, inherit from
  // keymap_precomposition
  var keymapZeroQuerySuggestion = KeyMap<PrecompositionState.Commands>()

  // enabled only if suggestion is shown. Otherwise, inherit from
  // keymap_composition
  var keymapSuggestion = KeyMap<CompositionState.Commands>()

  // enabled only if prediction is shown. Otherwise, inherit from
  // keymap_conversion
  var keymapPrediction = KeyMap<ConversionState.Commands>()

  /// Default ctor. keymap is NONE.
  init() {
    initCommandData()
    _ = applyPrimarySessionKeymap(ConfigHandler.getDefaultKeyMap(), "")
    // No overlay keymap is set.
  }

  init(_ config: Genmai_Config_Config) {
    initCommandData()
    _ = applyPrimarySessionKeymap(
      config.sessionKeymap, String(decoding: config.customKeymapTable, as: UTF8.self))
    applyOverlaySessionKeymap(config.overlayKeymaps)
  }

  mutating func reset() {
    keymapDirect.clear()
    keymapPrecomposition.clear()
    keymapComposition.clear()
    keymapConversion.clear()
    keymapZeroQuerySuggestion.clear()
    keymapSuggestion.clear()
    keymapPrediction.clear()
  }

  /// Applies "primary" SessionKeymap, like MSIME or KOTOERI.
  @discardableResult
  mutating func applyPrimarySessionKeymap(
    _ keymap: Genmai_Config_Config.SessionKeymap, _ customKeymapTable: String
  ) -> Bool {
    let keymapFile = KeyMapManager.getKeyMapFileName(keymap)
    if (keymap == .custom && customKeymapTable.isEmpty) || keymapFile == nil {
      // Exceptional case; fallback to default key map.
      GenmaiLog.warning("custom_keymap_table is empty. use default setting")
      return loadFile(KeyMapManager.getKeyMapFileName(ConfigHandler.getDefaultKeyMap()))
    } else if keymap != .custom {
      // For non-custom keymap, load and apply an embedded keymap tsv file.
      return loadFile(keymapFile)
    } else {
      // For custom keymap, apply keymap in the config message.
      // (The C++ debug build also writes a copy to user://keymap.tsv for
      // debugging; that write-only copy is omitted here.)
      return loadStream(InputFileStream(string: customKeymapTable))
    }
  }

  /// Applies "overlay" SessionKeymaps, like OVERLAY_HENKAN_TO_IME_ON.
  mutating func applyOverlaySessionKeymap(_ overlayKeymaps: [Genmai_Config_Config.SessionKeymap]) {
    for overlay in overlayKeymaps {
      if let overlayKeymapFile = KeyMapManager.getKeyMapFileName(overlay) {
        _ = loadFile(overlayKeymapFile)
      }
    }
  }

  mutating func loadFile(_ filename: String?) -> Bool {
    guard let filename, let ifs = ConfigFileStream.legacyOpen(filename) else {
      GenmaiLog.warning("cannot load keymap table: \(filename ?? "(null)")")
      return false
    }
    return loadStream(ifs)
  }

  mutating func loadStream(_ ifs: InputFileStream) -> Bool {
    var errors: [String] = []
    return loadStreamWithErrors(ifs, &errors)
  }

  mutating func loadStreamWithErrors(_ ifs: InputFileStream, _ errors: inout [String]) -> Bool {
    forEachKeyMapLine(ifs) { line in
      if line.isEmpty || line.utf8.first == UInt8(ascii: "#") {  // Skip empty or comment line.
        return
      }
      let rules = splitTabSkipEmpty(line)
      if rules.count != 3 {
        GenmaiLog.error("Invalid format: \(line)")
        return
      }
      if !addCommand(rules[0], rules[1], rules[2]) {
        errors.append(line)
        GenmaiLog.error("Unknown command: \(line)")
      }
    }

    var keyEvent = Genmai_Commands_KeyEvent()
    _ = KeyParser.parseKey("TextInput", &keyEvent)
    keymapPrecomposition.addRule(keyEvent, .insertCharacter)
    keymapComposition.addRule(keyEvent, .insertCharacter)
    keymapConversion.addRule(keyEvent, .insertCharacter)

    keyEvent = Genmai_Commands_KeyEvent()
    _ = KeyParser.parseKey("Shift", &keyEvent)
    keymapComposition.addRule(keyEvent, .insertCharacter)

    keyEvent = Genmai_Commands_KeyEvent()
    keyEvent.specialKey = .imeAction
    keymapPrecomposition.addRule(keyEvent, .imeAction)

    return true
  }

  /// Add a command bound with state and key_event.
  mutating func addCommand(_ stateName: String, _ keyEventName: String, _ commandName: String) -> Bool {
    #if !DEBUG  // means RELEASE BUILD
      // On the release build, we do not support the ReportBug
      // commands.  Note, true is returned as the arguments are
      // interpreted properly.
      if commandName == "ReportBug" {
        return true
      }
    #endif

    var keyEvent = Genmai_Commands_KeyEvent()
    if !KeyParser.parseKey(keyEventName, &keyEvent) {
      return false
    }

    if stateName == "DirectInput" || stateName == "Direct" {
      guard let command = parseCommandDirect(commandName) else { return false }
      keymapDirect.addRule(keyEvent, command)
      return true
    }

    if stateName == "Precomposition" {
      guard let command = parseCommandPrecomposition(commandName) else { return false }
      keymapPrecomposition.addRule(keyEvent, command)
      return true
    }

    if stateName == "Composition" {
      guard let command = parseCommandComposition(commandName) else { return false }
      keymapComposition.addRule(keyEvent, command)
      return true
    }

    if stateName == "Conversion" {
      guard let command = parseCommandConversion(commandName) else { return false }
      keymapConversion.addRule(keyEvent, command)
      return true
    }

    if stateName == "ZeroQuerySuggestion" {
      guard let command = parseCommandPrecomposition(commandName) else { return false }
      keymapZeroQuerySuggestion.addRule(keyEvent, command)
      return true
    }

    if stateName == "Suggestion" {
      guard let command = parseCommandComposition(commandName) else { return false }
      keymapSuggestion.addRule(keyEvent, command)
      return true
    }

    if stateName == "Prediction" {
      guard let command = parseCommandConversion(commandName) else { return false }
      keymapPrediction.addRule(keyEvent, command)
      return true
    }

    return false
  }

  public func getNameFromCommandDirect(_ command: DirectInputState.Commands) -> String? {
    reverseCommandDirectMap[command]
  }

  public func getNameFromCommandPrecomposition(_ command: PrecompositionState.Commands) -> String? {
    reverseCommandPrecompositionMap[command]
  }

  public func getNameFromCommandComposition(_ command: CompositionState.Commands) -> String? {
    reverseCommandCompositionMap[command]
  }

  public func getNameFromCommandConversion(_ command: ConversionState.Commands) -> String? {
    reverseCommandConversionMap[command]
  }

  private mutating func registerDirectCommand(_ commandString: String, _ command: DirectInputState.Commands) {
    commandDirectMap[commandString] = command
    reverseCommandDirectMap[command] = commandString
  }

  private mutating func registerPrecompositionCommand(
    _ commandString: String, _ command: PrecompositionState.Commands
  ) {
    commandPrecompositionMap[commandString] = command
    reverseCommandPrecompositionMap[command] = commandString
  }

  private mutating func registerCompositionCommand(
    _ commandString: String, _ command: CompositionState.Commands
  ) {
    commandCompositionMap[commandString] = command
    reverseCommandCompositionMap[command] = commandString
  }

  private mutating func registerConversionCommand(
    _ commandString: String, _ command: ConversionState.Commands
  ) {
    commandConversionMap[commandString] = command
    reverseCommandConversionMap[command] = commandString
  }

  private mutating func initCommandData() {
    let x = KeyMapManager.kCompositionModeXCommandSupported

    registerDirectCommand("IMEOn", .imeOn)
    registerDirectCommand(kCommandStringCompositionModeHiragana, x ? .compositionModeHiragana : .none)
    registerDirectCommand(
      kCommandStringCompositionModeFullKatakana, x ? .compositionModeFullKatakana : .none)
    registerDirectCommand(
      kCommandStringCompositionModeHalfKatakana, x ? .compositionModeHalfKatakana : .none)
    registerDirectCommand(
      kCommandStringCompositionModeFullAlphanumeric, x ? .compositionModeFullAlphanumeric : .none)
    registerDirectCommand(
      kCommandStringCompositionModeHalfAlphanumeric, x ? .compositionModeHalfAlphanumeric : .none)
    registerDirectCommand("Reconvert", .reconvert)

    // Precomposition
    registerPrecompositionCommand("IMEOff", .imeOff)
    registerPrecompositionCommand("IMEOn", .imeOn)
    registerPrecompositionCommand("InsertCharacter", .insertCharacter)
    registerPrecompositionCommand("InsertSpace", .insertSpace)
    registerPrecompositionCommand("InsertAlternateSpace", .insertAlternateSpace)
    registerPrecompositionCommand("InsertHalfSpace", .insertHalfSpace)
    registerPrecompositionCommand("InsertFullSpace", .insertFullSpace)
    registerPrecompositionCommand("ToggleAlphanumericMode", .toggleAlphanumericMode)
    registerPrecompositionCommand(
      kCommandStringCompositionModeHiragana, x ? .compositionModeHiragana : .none)
    registerPrecompositionCommand(
      kCommandStringCompositionModeFullKatakana, x ? .compositionModeFullKatakana : .none)
    registerPrecompositionCommand(
      kCommandStringCompositionModeHalfKatakana, x ? .compositionModeHalfKatakana : .none)
    registerPrecompositionCommand(
      kCommandStringCompositionModeFullAlphanumeric, x ? .compositionModeFullAlphanumeric : .none)
    registerPrecompositionCommand(
      kCommandStringCompositionModeHalfAlphanumeric, x ? .compositionModeHalfAlphanumeric : .none)
    registerPrecompositionCommand(
      kCommandStringCompositionModeSwitchKanaType, x ? .compositionModeSwitchKanaType : .none)

    registerPrecompositionCommand("LaunchConfigDialog", .launchConfigDialog)
    registerPrecompositionCommand("LaunchDictionaryTool", .launchDictionaryTool)
    registerPrecompositionCommand("LaunchWordRegisterDialog", .launchWordRegisterDialog)

    registerPrecompositionCommand("Revert", .revert)
    registerPrecompositionCommand("Undo", .undo)
    registerPrecompositionCommand("Reconvert", .reconvert)

    registerPrecompositionCommand("Cancel", .cancel)
    registerPrecompositionCommand("CancelAndIMEOff", .cancelAndImeOff)
    registerPrecompositionCommand("CommitFirstSuggestion", .commitFirstSuggestion)
    registerPrecompositionCommand("PredictAndConvert", .predictAndConvert)

    // Composition
    registerCompositionCommand("IMEOff", .imeOff)
    registerCompositionCommand("IMEOn", .imeOn)
    registerCompositionCommand("InsertCharacter", .insertCharacter)
    registerCompositionCommand("Delete", .del)
    registerCompositionCommand("Backspace", .backspace)
    registerCompositionCommand("InsertSpace", .insertSpace)
    registerCompositionCommand("InsertAlternateSpace", .insertAlternateSpace)
    registerCompositionCommand("InsertHalfSpace", .insertHalfSpace)
    registerCompositionCommand("InsertFullSpace", .insertFullSpace)
    registerCompositionCommand("Cancel", .cancel)
    registerCompositionCommand("CancelAndIMEOff", .cancelAndImeOff)
    registerCompositionCommand("Undo", .undo)
    registerCompositionCommand("MoveCursorLeft", .moveCursorLeft)
    registerCompositionCommand("MoveCursorRight", .moveCursorRight)
    registerCompositionCommand("MoveCursorToBeginning", .moveCursorToBeginning)
    registerCompositionCommand("MoveCursorToEnd", .moveMoveCursorToEnd)
    registerCompositionCommand("Commit", .commit)
    registerCompositionCommand("CommitFirstSuggestion", .commitFirstSuggestion)
    registerCompositionCommand("Convert", .convert)
    registerCompositionCommand("ConvertWithoutHistory", .convertWithoutHistory)
    registerCompositionCommand("PredictAndConvert", .predictAndConvert)
    registerCompositionCommand("ConvertToHiragana", .convertToHiragana)
    registerCompositionCommand("ConvertToFullKatakana", .convertToFullKatakana)
    registerCompositionCommand("ConvertToHalfKatakana", .convertToHalfKatakana)
    registerCompositionCommand("ConvertToHalfWidth", .convertToHalfWidth)
    registerCompositionCommand("ConvertToFullAlphanumeric", .convertToFullAlphanumeric)
    registerCompositionCommand("ConvertToHalfAlphanumeric", .convertToHalfAlphanumeric)
    registerCompositionCommand("SwitchKanaType", .switchKanaType)
    registerCompositionCommand("DisplayAsHiragana", .displayAsHiragana)
    registerCompositionCommand("DisplayAsFullKatakana", .displayAsFullKatakana)
    registerCompositionCommand("DisplayAsHalfKatakana", .displayAsHalfKatakana)
    registerCompositionCommand("DisplayAsHalfWidth", .translateHalfWidth)
    registerCompositionCommand("DisplayAsFullAlphanumeric", .translateFullAscii)
    registerCompositionCommand("DisplayAsHalfAlphanumeric", .translateHalfAscii)
    registerCompositionCommand("ToggleAlphanumericMode", .toggleAlphanumericMode)
    registerCompositionCommand(
      kCommandStringCompositionModeHiragana, x ? .compositionModeHiragana : .none)
    registerCompositionCommand(
      kCommandStringCompositionModeFullKatakana, x ? .compositionModeFullKatakana : .none)
    registerCompositionCommand(
      kCommandStringCompositionModeHalfKatakana, x ? .compositionModeHalfKatakana : .none)
    registerCompositionCommand(
      kCommandStringCompositionModeFullAlphanumeric, x ? .compositionModeFullAlphanumeric : .none)
    registerCompositionCommand(
      kCommandStringCompositionModeHalfAlphanumeric, x ? .compositionModeHalfAlphanumeric : .none)

    // Conversion
    registerConversionCommand("IMEOff", .imeOff)
    registerConversionCommand("IMEOn", .imeOn)
    registerConversionCommand("InsertCharacter", .insertCharacter)
    registerConversionCommand("InsertSpace", .insertSpace)
    registerConversionCommand("InsertAlternateSpace", .insertAlternateSpace)
    registerConversionCommand("InsertHalfSpace", .insertHalfSpace)
    registerConversionCommand("InsertFullSpace", .insertFullSpace)
    registerConversionCommand("Cancel", .cancel)
    registerConversionCommand("CancelAndIMEOff", .cancelAndImeOff)
    registerConversionCommand("Undo", .undo)
    registerConversionCommand("SegmentFocusLeft", .segmentFocusLeft)
    registerConversionCommand("SegmentFocusRight", .segmentFocusRight)
    registerConversionCommand("SegmentFocusFirst", .segmentFocusFirst)
    registerConversionCommand("SegmentFocusLast", .segmentFocusLast)
    registerConversionCommand("SegmentWidthExpand", .segmentWidthExpand)
    registerConversionCommand("SegmentWidthShrink", .segmentWidthShrink)
    registerConversionCommand("ConvertNext", .convertNext)
    registerConversionCommand("ConvertPrev", .convertPrev)
    registerConversionCommand("ConvertNextPage", .convertNextPage)
    registerConversionCommand("ConvertPrevPage", .convertPrevPage)
    registerConversionCommand("PredictAndConvert", .predictAndConvert)
    registerConversionCommand("Commit", .commit)
    registerConversionCommand("CommitOnlyFirstSegment", .commitSegment)
    registerConversionCommand("ConvertToHiragana", .convertToHiragana)
    registerConversionCommand("ConvertToFullKatakana", .convertToFullKatakana)
    registerConversionCommand("ConvertToHalfKatakana", .convertToHalfKatakana)
    registerConversionCommand("ConvertToHalfWidth", .convertToHalfWidth)
    registerConversionCommand("ConvertToFullAlphanumeric", .convertToFullAlphanumeric)
    registerConversionCommand("ConvertToHalfAlphanumeric", .convertToHalfAlphanumeric)
    registerConversionCommand("SwitchKanaType", .switchKanaType)
    registerConversionCommand("ToggleAlphanumericMode", .toggleAlphanumericMode)
    registerConversionCommand("DisplayAsHiragana", .displayAsHiragana)
    registerConversionCommand("DisplayAsFullKatakana", .displayAsFullKatakana)
    registerConversionCommand("DisplayAsHalfKatakana", .displayAsHalfKatakana)
    registerConversionCommand("DisplayAsHalfWidth", .translateHalfWidth)
    registerConversionCommand("DisplayAsFullAlphanumeric", .translateFullAscii)
    registerConversionCommand("DisplayAsHalfAlphanumeric", .translateHalfAscii)
    registerConversionCommand("DeleteSelectedCandidate", .deleteSelectedCandidate)
    registerConversionCommand(
      kCommandStringCompositionModeHiragana, x ? .compositionModeHiragana : .none)
    registerConversionCommand(
      kCommandStringCompositionModeFullKatakana, x ? .compositionModeFullKatakana : .none)
    registerConversionCommand(
      kCommandStringCompositionModeHalfKatakana, x ? .compositionModeHalfKatakana : .none)
    registerConversionCommand(
      kCommandStringCompositionModeFullAlphanumeric, x ? .compositionModeFullAlphanumeric : .none)
    registerConversionCommand(
      kCommandStringCompositionModeHalfAlphanumeric, x ? .compositionModeHalfAlphanumeric : .none)
    #if DEBUG  // means NOT RELEASE build
      registerConversionCommand("ReportBug", .reportBug)
    #endif
  }

  // Note: the reverse maps keep the *last* registered name for a command, like
  // the C++ `reverse_command_*_map_[command] = command_string`.

  public func getCommandDirect(_ keyEvent: Genmai_Commands_KeyEvent) -> DirectInputState.Commands? {
    keymapDirect.getCommand(keyEvent)
  }

  public func getCommandPrecomposition(_ keyEvent: Genmai_Commands_KeyEvent)
    -> PrecompositionState.Commands?
  {
    keymapPrecomposition.getCommand(keyEvent)
  }

  public func getCommandComposition(_ keyEvent: Genmai_Commands_KeyEvent)
    -> CompositionState.Commands?
  {
    keymapComposition.getCommand(keyEvent)
  }

  public func getCommandZeroQuerySuggestion(_ keyEvent: Genmai_Commands_KeyEvent)
    -> PrecompositionState.Commands?
  {
    // try zero query suggestion rule first
    if let command = keymapZeroQuerySuggestion.getCommand(keyEvent) {
      return command
    }
    // use precomposition rule
    return keymapPrecomposition.getCommand(keyEvent)
  }

  public func getCommandSuggestion(_ keyEvent: Genmai_Commands_KeyEvent)
    -> CompositionState.Commands?
  {
    // try suggestion rule first
    if let command = keymapSuggestion.getCommand(keyEvent) {
      return command
    }
    // use composition rule
    return keymapComposition.getCommand(keyEvent)
  }

  public func getCommandConversion(_ keyEvent: Genmai_Commands_KeyEvent)
    -> ConversionState.Commands?
  {
    keymapConversion.getCommand(keyEvent)
  }

  public func getCommandPrediction(_ keyEvent: Genmai_Commands_KeyEvent)
    -> ConversionState.Commands?
  {
    // try prediction rule first
    if let command = keymapPrediction.getCommand(keyEvent) {
      return command
    }
    // use conversion rule
    return keymapConversion.getCommand(keyEvent)
  }

  func parseCommandDirect(_ commandString: String) -> DirectInputState.Commands? {
    commandDirectMap[normalizeCommand(commandString)]
  }

  // This should be in KeyMap instead of KeyMapManager.
  func parseCommandPrecomposition(_ commandString: String) -> PrecompositionState.Commands? {
    commandPrecompositionMap[normalizeCommand(commandString)]
  }

  func parseCommandComposition(_ commandString: String) -> CompositionState.Commands? {
    commandCompositionMap[normalizeCommand(commandString)]
  }

  func parseCommandConversion(_ commandString: String) -> ConversionState.Commands? {
    commandConversionMap[normalizeCommand(commandString)]
  }

  // Append command names to command_names.
  public func appendAvailableCommandNameDirect(_ commandNames: inout Set<String>) {
    commandNames.formUnion(commandDirectMap.keys)
  }

  public func appendAvailableCommandNamePrecomposition(_ commandNames: inout Set<String>) {
    commandNames.formUnion(commandPrecompositionMap.keys)
  }

  public func appendAvailableCommandNameComposition(_ commandNames: inout Set<String>) {
    commandNames.formUnion(commandCompositionMap.keys)
  }

  public func appendAvailableCommandNameConversion(_ commandNames: inout Set<String>) {
    commandNames.formUnion(commandConversionMap.keys)
  }

  public func appendAvailableCommandNameZeroQuerySuggestion(_ commandNames: inout Set<String>) {
    appendAvailableCommandNamePrecomposition(&commandNames)
  }

  public func appendAvailableCommandNameSuggestion(_ commandNames: inout Set<String>) {
    appendAvailableCommandNameComposition(&commandNames)
  }

  public func appendAvailableCommandNamePrediction(_ commandNames: inout Set<String>) {
    appendAvailableCommandNameConversion(&commandNames)
  }
}

/// A manager of key mapping rule for a Config.
/// The instance is created based on a Config through the constructor,
/// and the instance is immutable (If the config is updated after the instance
/// creation, this instance is unchanged).
///
/// The tables live in a `Mutex` so that the manager is `Sendable`; tests (and the
/// C++ friend functions) still modify them through `addCommand` / `loadStream`.
public final class KeyMapManager: Sendable {
  #if os(macOS) || os(iOS)
    static let kCompositionModeXCommandSupported = false
  #else
    static let kCompositionModeXCommandSupported = true
  #endif

  private let state: Mutex<KeyMapManagerState>

  /// Default ctor. keymap is NONE.
  public init() {
    state = Mutex(KeyMapManagerState())
  }

  public init(_ config: Genmai_Config_Config) {
    state = Mutex(KeyMapManagerState(config))
  }

  /// Returns true if both `new_config` and `old_config`
  /// can use the same KeyMapManager.
  public static func isSameKeyMapManagerApplicable(
    _ oldConfig: Genmai_Config_Config, _ newConfig: Genmai_Config_Config
  ) -> Bool {
    if oldConfig.sessionKeymap != newConfig.sessionKeymap {
      return false
    }
    if oldConfig.overlayKeymaps != newConfig.overlayKeymaps {
      return false
    }
    if oldConfig.sessionKeymap == .custom
      && oldConfig.customKeymapTable != newConfig.customKeymapTable
    {
      return false
    }
    return true
  }

  /// Return the file name bound with the keymap enum.
  public static func getKeyMapFileName(_ keymap: Genmai_Config_Config.SessionKeymap) -> String? {
    switch keymap {
    case .atok: return kATOKKeyMapFile
    case .mobile: return kMobileKeyMapFile
    case .msime: return kMSIMEKeyMapFile
    case .kotoeri: return kKotoeriKeyMapFile
    case .chromeos: return kChromeOsKeyMapFile
    case .custom: return kCustomKeyMapFile
    case .overlayHenkanMuhenkanToImeOnOff: return kOverlayHenkanMuhenkanToImeOnOffKeyMapFile
    default:
      // should not appear here.
      GenmaiLog.error("Keymap type: \(keymap) appeared at key map initialization.")
      // should never make loop.
      return getKeyMapFileName(ConfigHandler.getDefaultKeyMap())
    }
  }

  func reset() { state.withLock { $0.reset() } }

  /// Applies "primary" SessionKeymap, like MSIME or KOTOERI.
  @discardableResult
  func applyPrimarySessionKeymap(
    _ keymap: Genmai_Config_Config.SessionKeymap, _ customKeymapTable: String
  ) -> Bool {
    state.withLock { $0.applyPrimarySessionKeymap(keymap, customKeymapTable) }
  }

  /// Applies "overlay" SessionKeymaps, like OVERLAY_HENKAN_TO_IME_ON.
  func applyOverlaySessionKeymap(_ overlayKeymaps: [Genmai_Config_Config.SessionKeymap]) {
    state.withLock { $0.applyOverlaySessionKeymap(overlayKeymaps) }
  }

  func loadFile(_ filename: String?) -> Bool { state.withLock { $0.loadFile(filename) } }

  func loadStream(_ ifs: InputFileStream) -> Bool { state.withLock { $0.loadStream(ifs) } }

  func loadStreamWithErrors(_ ifs: InputFileStream, _ errors: inout [String]) -> Bool {
    var collected = errors
    let result = state.withLock { $0.loadStreamWithErrors(ifs, &collected) }
    errors = collected
    return result
  }

  /// Add a command bound with state and key_event.
  func addCommand(_ stateName: String, _ keyEventName: String, _ commandName: String) -> Bool {
    state.withLock { $0.addCommand(stateName, keyEventName, commandName) }
  }

  public func getNameFromCommandDirect(_ command: DirectInputState.Commands) -> String? {
    state.withLock { $0.getNameFromCommandDirect(command) }
  }

  public func getNameFromCommandPrecomposition(_ command: PrecompositionState.Commands) -> String? {
    state.withLock { $0.getNameFromCommandPrecomposition(command) }
  }

  public func getNameFromCommandComposition(_ command: CompositionState.Commands) -> String? {
    state.withLock { $0.getNameFromCommandComposition(command) }
  }

  public func getNameFromCommandConversion(_ command: ConversionState.Commands) -> String? {
    state.withLock { $0.getNameFromCommandConversion(command) }
  }

  public func getCommandDirect(_ keyEvent: Genmai_Commands_KeyEvent) -> DirectInputState.Commands? {
    state.withLock { $0.getCommandDirect(keyEvent) }
  }

  public func getCommandPrecomposition(_ keyEvent: Genmai_Commands_KeyEvent)
    -> PrecompositionState.Commands?
  {
    state.withLock { $0.getCommandPrecomposition(keyEvent) }
  }

  public func getCommandComposition(_ keyEvent: Genmai_Commands_KeyEvent)
    -> CompositionState.Commands?
  {
    state.withLock { $0.getCommandComposition(keyEvent) }
  }

  public func getCommandZeroQuerySuggestion(_ keyEvent: Genmai_Commands_KeyEvent)
    -> PrecompositionState.Commands?
  {
    state.withLock { $0.getCommandZeroQuerySuggestion(keyEvent) }
  }

  public func getCommandSuggestion(_ keyEvent: Genmai_Commands_KeyEvent)
    -> CompositionState.Commands?
  {
    state.withLock { $0.getCommandSuggestion(keyEvent) }
  }

  public func getCommandConversion(_ keyEvent: Genmai_Commands_KeyEvent)
    -> ConversionState.Commands?
  {
    state.withLock { $0.getCommandConversion(keyEvent) }
  }

  public func getCommandPrediction(_ keyEvent: Genmai_Commands_KeyEvent)
    -> ConversionState.Commands?
  {
    state.withLock { $0.getCommandPrediction(keyEvent) }
  }

  func parseCommandDirect(_ commandString: String) -> DirectInputState.Commands? {
    state.withLock { $0.parseCommandDirect(commandString) }
  }

  func parseCommandPrecomposition(_ commandString: String) -> PrecompositionState.Commands? {
    state.withLock { $0.parseCommandPrecomposition(commandString) }
  }

  func parseCommandComposition(_ commandString: String) -> CompositionState.Commands? {
    state.withLock { $0.parseCommandComposition(commandString) }
  }

  func parseCommandConversion(_ commandString: String) -> ConversionState.Commands? {
    state.withLock { $0.parseCommandConversion(commandString) }
  }

  // Append command names to command_names.
  public func appendAvailableCommandNameDirect(_ commandNames: inout Set<String>) {
    commandNames.formUnion(state.withLock { $0.commandDirectMap.keys })
  }

  public func appendAvailableCommandNamePrecomposition(_ commandNames: inout Set<String>) {
    commandNames.formUnion(state.withLock { $0.commandPrecompositionMap.keys })
  }

  public func appendAvailableCommandNameComposition(_ commandNames: inout Set<String>) {
    commandNames.formUnion(state.withLock { $0.commandCompositionMap.keys })
  }

  public func appendAvailableCommandNameConversion(_ commandNames: inout Set<String>) {
    commandNames.formUnion(state.withLock { $0.commandConversionMap.keys })
  }

  public func appendAvailableCommandNameZeroQuerySuggestion(_ commandNames: inout Set<String>) {
    appendAvailableCommandNamePrecomposition(&commandNames)
  }

  public func appendAvailableCommandNameSuggestion(_ commandNames: inout Set<String>) {
    appendAvailableCommandNameComposition(&commandNames)
  }

  public func appendAvailableCommandNamePrediction(_ commandNames: inout Set<String>) {
    appendAvailableCommandNameConversion(&commandNames)
  }
}
