// Port of mozc/src/session/keymap_test.cc (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import Testing

@testable import GenmaiSession

private func getDefaultConfig(_ keymap: Genmai_Config_Config.SessionKeymap) -> Genmai_Config_Config {
  var config = Genmai_Config_Config()
  config.sessionKeymap = keymap
  return config
}

private func parseKey(_ s: String) -> Genmai_Commands_KeyEvent {
  var keyEvent = Genmai_Commands_KeyEvent()
  _ = KeyParser.parseKey(s, &keyEvent)
  return keyEvent
}

private var isCompositionModeXCommandSupported: Bool {
  KeyMapManager.kCompositionModeXCommandSupported
}

@Suite struct KeyMapTests {
  @Test func addRule() {
    var keymap = KeyMap<PrecompositionState.Commands>()
    var ok = false
    _ = ok
    var keyEvent = Genmai_Commands_KeyEvent()
    // 'a'
    keyEvent.keyCode = 97
    ok = keymap.addRule(keyEvent, .insertCharacter)
    #expect(ok)

    // 0 is treated as null input
    keyEvent.keyCode = 0
    ok = keymap.addRule(keyEvent, .insertCharacter)
    #expect(ok)

    // 1 to 31 should be rejected.
    keyEvent.keyCode = 1
    ok = keymap.addRule(keyEvent, .insertCharacter)
    #expect(!ok)
    keyEvent.keyCode = 31
    ok = keymap.addRule(keyEvent, .insertCharacter)
    #expect(!ok)

    // 32 (space) is also invalid input.
    keyEvent.keyCode = 32
    ok = keymap.addRule(keyEvent, .insertCharacter)
    #expect(!ok)

    // 33 (!) is a valid input.
    keyEvent.keyCode = 33
    ok = keymap.addRule(keyEvent, .insertCharacter)
    #expect(ok)

    // 8bit char is a valid input.
    keyEvent.keyCode = 127
    ok = keymap.addRule(keyEvent, .insertCharacter)
    #expect(ok)
    keyEvent.keyCode = 255
    ok = keymap.addRule(keyEvent, .insertCharacter)
    #expect(ok)
  }

  @Test func getCommand() {
    do {
      var keymap = KeyMap<PrecompositionState.Commands>()
      var ok = false
      _ = ok
      var initKeyEvent = Genmai_Commands_KeyEvent()
      initKeyEvent.keyCode = 97
      ok = keymap.addRule(initKeyEvent, .insertCharacter)
      #expect(ok)

      var keyEvent = Genmai_Commands_KeyEvent()
      keyEvent.keyCode = 97
      #expect(keymap.getCommand(keyEvent) == .insertCharacter)

      keyEvent = Genmai_Commands_KeyEvent()
      keyEvent.keyCode = 98
      #expect(keymap.getCommand(keyEvent) == nil)
    }
    do {
      var keymap = KeyMap<PrecompositionState.Commands>()
      var ok = false
      _ = ok
      var initKeyEvent = Genmai_Commands_KeyEvent()
      initKeyEvent.specialKey = .textInput
      ok = keymap.addRule(initKeyEvent, .insertCharacter)
      #expect(ok)

      var keyEvent = Genmai_Commands_KeyEvent()
      keyEvent.keyString = "hoge"
      #expect(keymap.getCommand(keyEvent) == .insertCharacter)
    }
    do {
      var keymap = KeyMap<CompositionState.Commands>()
      var ok = false
      _ = ok
      var initKeyEvent = Genmai_Commands_KeyEvent()
      initKeyEvent.keyCode = 97
      ok = keymap.addRule(initKeyEvent, .insertCharacter)
      #expect(ok)

      var keyEvent = Genmai_Commands_KeyEvent()
      keyEvent.keyCode = 97
      #expect(keymap.getCommand(keyEvent) == .insertCharacter)

      keyEvent = Genmai_Commands_KeyEvent()
      keyEvent.keyCode = 98
      #expect(keymap.getCommand(keyEvent) == nil)
    }
    do {
      var keymap = KeyMap<CompositionState.Commands>()
      var ok = false
      _ = ok
      var initKeyEvent = Genmai_Commands_KeyEvent()
      initKeyEvent.specialKey = .enter
      ok = keymap.addRule(initKeyEvent, .commit)
      #expect(ok)

      initKeyEvent = Genmai_Commands_KeyEvent()
      initKeyEvent.specialKey = .del
      initKeyEvent.modifierKeys.append(.ctrl)
      initKeyEvent.modifierKeys.append(.alt)
      ok = keymap.addRule(initKeyEvent, .imeOff)
      #expect(ok)

      // ENTER
      var keyEvent = Genmai_Commands_KeyEvent()
      keyEvent.specialKey = .enter
      #expect(keymap.getCommand(keyEvent) == .commit)

      // CTRL-ALT-DELETE
      keyEvent = Genmai_Commands_KeyEvent()
      keyEvent.specialKey = .del
      keyEvent.modifierKeys.append(.ctrl)
      keyEvent.modifierKeys.append(.alt)
      #expect(keymap.getCommand(keyEvent) == .imeOff)
    }
  }

  @Test func getCommandForKeyString() {
    var keymap = KeyMap<PrecompositionState.Commands>()
    var ok = false
    _ = ok

    // When a key event is not registered, GetCommand should return false.
    do {
      var keyEvent = Genmai_Commands_KeyEvent()
      keyEvent.keyCode = 97
      #expect(keymap.getCommand(keyEvent) == nil)
    }

    // When a key event is not registered, GetCommand should return false even
    // if the key event has |key_string|. See also b/9684668
    do {
      var keyEvent = Genmai_Commands_KeyEvent()
      keyEvent.keyCode = 97
      keyEvent.keyString = "a"
      #expect(keymap.getCommand(keyEvent) == nil)
    }

    // Special case for b/4170089. VK_PACKET on Windows.
    do {
      var keyEvent = Genmai_Commands_KeyEvent()
      keyEvent.keyString = "a"
      #expect(keymap.getCommand(keyEvent) == nil)
    }

    // After adding the rule of TEXT_INPUT -> INSERT_CHARACTER, the above cases
    // should return INSERT_CHARACTER.
    var textInputKeyEvent = Genmai_Commands_KeyEvent()
    textInputKeyEvent.specialKey = .textInput
    keymap.addRule(textInputKeyEvent, .insertCharacter)

    // key_code = 97, key_string = empty
    do {
      var keyEvent = Genmai_Commands_KeyEvent()
      keyEvent.keyCode = 97
      #expect(keymap.getCommand(keyEvent) == .insertCharacter)
    }

    // key_code = 97, key_string = "a"
    do {
      var keyEvent = Genmai_Commands_KeyEvent()
      keyEvent.keyCode = 97
      keyEvent.keyString = "a"
      #expect(keymap.getCommand(keyEvent) == .insertCharacter)
    }

    // key_code = empty, key_string = "a"
    do {
      var keyEvent = Genmai_Commands_KeyEvent()
      keyEvent.keyString = "a"
      #expect(keymap.getCommand(keyEvent) == .insertCharacter)
    }
  }

  @Test func getCommandKeyStub() {
    var keymap = KeyMap<PrecompositionState.Commands>()
    var ok = false
    _ = ok
    var initKeyEvent = Genmai_Commands_KeyEvent()
    initKeyEvent.specialKey = .textInput
    ok = keymap.addRule(initKeyEvent, .insertCharacter)
    #expect(ok)

    var keyEvent = Genmai_Commands_KeyEvent()
    keyEvent.keyCode = 97
    #expect(keymap.getCommand(keyEvent) == .insertCharacter)
  }

  @Test func getCommandOverlay() {
    withScopedSessionEnvironment {
      var config = Genmai_Config_Config()
      config.sessionKeymap = .msime
      config.overlayKeymaps.append(.overlayHenkanMuhenkanToImeOnOff)
      let manager = KeyMapManager(config)
      var keyEvent = Genmai_Commands_KeyEvent()
      keyEvent.specialKey = .henkan
      // MSIME defines HENKAN as Reconvert, but the overlay defines it as IME_ON.
      #expect(manager.getCommandDirect(keyEvent) == .imeOn)
    }
  }

  @Test func getKeyMapFileName() {
    #expect(KeyMapManager.getKeyMapFileName(.atok) == "system://atok.tsv")
    #expect(KeyMapManager.getKeyMapFileName(.mobile) == "system://mobile.tsv")
    #expect(KeyMapManager.getKeyMapFileName(.msime) == "system://ms-ime.tsv")
    #expect(KeyMapManager.getKeyMapFileName(.kotoeri) == "system://kotoeri.tsv")
    #expect(KeyMapManager.getKeyMapFileName(.chromeos) == "system://chromeos.tsv")
    #expect(KeyMapManager.getKeyMapFileName(.custom) == "user://keymap.tsv")
  }

  @Test func defaultKeyBindings() {
    withScopedSessionEnvironment {
      let manager = KeyMapManager()

      #expect(manager.loadStream(InputFileStream(string: "")))

      do {  // Check key bindings of TextInput.
        let keyEvent = parseKey("TextInput")
        #expect(manager.getCommandPrecomposition(keyEvent) == .insertCharacter)
        #expect(manager.getCommandComposition(keyEvent) == .insertCharacter)
        #expect(manager.getCommandConversion(keyEvent) == .insertCharacter)
      }

      do {  // Check key bindings of Shift.
        let keyEvent = parseKey("Shift")
        #expect(manager.getCommandPrecomposition(keyEvent) == nil)
        #expect(manager.getCommandComposition(keyEvent) == .insertCharacter)
        #expect(manager.getCommandConversion(keyEvent) == nil)
      }
    }
  }

  @Test func loadStreamWithErrors() {
    withScopedSessionEnvironment {
      let manager = KeyMapManager()
      for file in ["system://atok.tsv", "system://ms-ime.tsv", "system://kotoeri.tsv", "system://mobile.tsv"]
      {
        var errors: [String] = []
        let stream = ConfigFileStream.openReadText(file)
        #expect(stream != nil)
        if let stream {
          #expect(manager.loadStreamWithErrors(stream, &errors))
        }
        #expect(errors.isEmpty, "\(file): \(errors)")
      }
    }
  }

  @Test func getName() {
    withScopedSessionEnvironment {
      let manager = KeyMapManager()
      do {
        // Direct
        #expect(manager.getNameFromCommandDirect(.imeOn) == "IMEOn")
        #expect(manager.getNameFromCommandDirect(.reconvert) == "Reconvert")

        if isCompositionModeXCommandSupported {
          #expect(manager.getNameFromCommandDirect(.compositionModeHiragana) == "CompositionModeHiragana")
          #expect(manager.getNameFromCommandDirect(.compositionModeFullKatakana) == "CompositionModeFullKatakana")
          #expect(manager.getNameFromCommandDirect(.compositionModeHalfKatakana) == "CompositionModeHalfKatakana")
          #expect(manager.getNameFromCommandDirect(.compositionModeFullAlphanumeric) == "CompositionModeFullAlphanumeric")
          #expect(manager.getNameFromCommandDirect(.compositionModeHalfAlphanumeric) == "CompositionModeHalfAlphanumeric")
        }
      }
      do {
        // Precomposition
        #expect(manager.getNameFromCommandPrecomposition(.imeOff) == "IMEOff")
        #expect(manager.getNameFromCommandPrecomposition(.imeOn) == "IMEOn")
        #expect(manager.getNameFromCommandPrecomposition(.insertCharacter) == "InsertCharacter")
        #expect(manager.getNameFromCommandPrecomposition(.reconvert) == "Reconvert")

        if isCompositionModeXCommandSupported {
          #expect(manager.getNameFromCommandPrecomposition(.compositionModeHiragana) == "CompositionModeHiragana")
          #expect(manager.getNameFromCommandPrecomposition(.compositionModeFullKatakana) == "CompositionModeFullKatakana")
          #expect(manager.getNameFromCommandPrecomposition(.compositionModeHalfKatakana) == "CompositionModeHalfKatakana")
          #expect(manager.getNameFromCommandPrecomposition(.compositionModeFullAlphanumeric) == "CompositionModeFullAlphanumeric")
          #expect(manager.getNameFromCommandPrecomposition(.compositionModeHalfAlphanumeric) == "CompositionModeHalfAlphanumeric")
          #expect(manager.getNameFromCommandPrecomposition(.compositionModeSwitchKanaType) == "CompositionModeSwitchKanaType")
        }
      }
      do {
        // Composition
        #expect(manager.getNameFromCommandComposition(.imeOff) == "IMEOff")
        #expect(manager.getNameFromCommandComposition(.imeOn) == "IMEOn")
        #expect(manager.getNameFromCommandComposition(.insertCharacter) == "InsertCharacter")

        if isCompositionModeXCommandSupported {
          #expect(manager.getNameFromCommandComposition(.compositionModeHiragana) == "CompositionModeHiragana")
          #expect(manager.getNameFromCommandComposition(.compositionModeFullKatakana) == "CompositionModeFullKatakana")
          #expect(manager.getNameFromCommandComposition(.compositionModeHalfKatakana) == "CompositionModeHalfKatakana")
          #expect(manager.getNameFromCommandComposition(.compositionModeFullAlphanumeric) == "CompositionModeFullAlphanumeric")
          #expect(manager.getNameFromCommandComposition(.compositionModeHalfAlphanumeric) == "CompositionModeHalfAlphanumeric")
        }
      }
      do {
        // Conversion
        #expect(manager.getNameFromCommandConversion(.imeOff) == "IMEOff")
        #expect(manager.getNameFromCommandConversion(.imeOn) == "IMEOn")
        #expect(manager.getNameFromCommandConversion(.insertCharacter) == "InsertCharacter")

        if isCompositionModeXCommandSupported {
          #expect(manager.getNameFromCommandConversion(.compositionModeHiragana) == "CompositionModeHiragana")
          #expect(manager.getNameFromCommandConversion(.compositionModeFullKatakana) == "CompositionModeFullKatakana")
          #expect(manager.getNameFromCommandConversion(.compositionModeHalfKatakana) == "CompositionModeHalfKatakana")
          #expect(manager.getNameFromCommandConversion(.compositionModeFullAlphanumeric) == "CompositionModeFullAlphanumeric")
          #expect(manager.getNameFromCommandConversion(.compositionModeHalfAlphanumeric) == "CompositionModeHalfAlphanumeric")
        }
      }
    }
  }

  @Test func directModeDoesNotSupportInsertSpace() {
    // InsertSpace, InsertAlternateSpace, InsertHalfSpace, and InsertFullSpace
    // are not supported in direct mode.
    withScopedSessionEnvironment {
      let manager = KeyMapManager()
      var names = Set<String>()
      manager.appendAvailableCommandNameDirect(&names)

      #expect(!names.contains("InsertSpace"))
      #expect(!names.contains("InsertAlternateSpace"))
      #expect(!names.contains("InsertHalfSpace"))
      #expect(!names.contains("InsertFullSpace"))
    }
  }

  private func checkCompositionModeCommandStrings(
    _ names: Set<String>, switchKanaType: Bool, sourceLocation: SourceLocation = #_sourceLocation
  ) {
    // CompositionMode* command strings.
    for name in [
      "CompositionModeHiragana", "CompositionModeHalfKatakana", "CompositionModeFullKatakana",
      "CompositionModeHalfAlphanumeric", "CompositionModeFullAlphanumeric",
    ] {
      #expect(names.contains(name), sourceLocation: sourceLocation)
    }
    if switchKanaType {
      #expect(names.contains("CompositionModeSwitchKanaType"), sourceLocation: sourceLocation)
    }
    // Legacy InputMode* command strings are not exposed.
    for name in [
      "InputModeHiragana", "InputModeHalfKatakana", "InputModeFullKatakana",
      "InputModeHalfAlphanumeric", "InputModeFullAlphanumeric",
    ] {
      #expect(!names.contains(name), sourceLocation: sourceLocation)
    }
    if switchKanaType {
      #expect(!names.contains("InputModeSwitchKanaType"), sourceLocation: sourceLocation)
    }
  }

  @Test func directStateSupportsCompositionModeCommandStrings() {
    if !isCompositionModeXCommandSupported {
      return
    }
    withScopedSessionEnvironment {
      let manager = KeyMapManager()
      var names = Set<String>()
      manager.appendAvailableCommandNameDirect(&names)
      checkCompositionModeCommandStrings(names, switchKanaType: false)
    }
  }

  @Test func precompositionStateSupportsCompositionModeCommandStrings() {
    if !isCompositionModeXCommandSupported {
      return
    }
    withScopedSessionEnvironment {
      let manager = KeyMapManager()
      var names = Set<String>()
      manager.appendAvailableCommandNamePrecomposition(&names)
      checkCompositionModeCommandStrings(names, switchKanaType: true)
    }
  }

  @Test func compositionStateSupportsCompositionModeCommandStrings() {
    if !isCompositionModeXCommandSupported {
      return
    }
    withScopedSessionEnvironment {
      let manager = KeyMapManager()
      var names = Set<String>()
      manager.appendAvailableCommandNameComposition(&names)
      checkCompositionModeCommandStrings(names, switchKanaType: false)
    }
  }

  @Test func conversionStateSupportsCompositionModeCommandStrings() {
    if !isCompositionModeXCommandSupported {
      return
    }
    withScopedSessionEnvironment {
      let manager = KeyMapManager()
      var names = Set<String>()
      manager.appendAvailableCommandNameConversion(&names)
      checkCompositionModeCommandStrings(names, switchKanaType: false)
    }
  }

  // The five (or six) CompositionMode* commands, with their legacy names.
  private static let modeNames: [(String, String)] = [
    ("CompositionModeHiragana", "InputModeHiragana"),
    ("CompositionModeHalfKatakana", "InputModeHalfKatakana"),
    ("CompositionModeFullKatakana", "InputModeFullKatakana"),
    ("CompositionModeHalfAlphanumeric", "InputModeHalfAlphanumeric"),
    ("CompositionModeFullAlphanumeric", "InputModeFullAlphanumeric"),
  ]

  @Test(arguments: [false, true])
  func parseCompositionModeCommandStringsForDirectState(_ legacy: Bool) {
    withScopedSessionEnvironment {
      let manager = KeyMapManager()
      let expected: [DirectInputState.Commands] = [
        .compositionModeHiragana, .compositionModeHalfKatakana, .compositionModeFullKatakana,
        .compositionModeHalfAlphanumeric, .compositionModeFullAlphanumeric,
      ]
      for (i, names) in Self.modeNames.enumerated() {
        let command = manager.parseCommandDirect(legacy ? names.1 : names.0)
        #expect(command == (isCompositionModeXCommandSupported ? expected[i] : DirectInputState.Commands.none))
      }
    }
  }

  @Test(arguments: [false, true])
  func parseCompositionModeCommandStringsForPrecompositionState(_ legacy: Bool) {
    withScopedSessionEnvironment {
      let manager = KeyMapManager()
      let expected: [PrecompositionState.Commands] = [
        .compositionModeHiragana, .compositionModeHalfKatakana, .compositionModeFullKatakana,
        .compositionModeHalfAlphanumeric, .compositionModeFullAlphanumeric,
        .compositionModeSwitchKanaType,
      ]
      let names = Self.modeNames + [("CompositionModeSwitchKanaType", "InputModeSwitchKanaType")]
      for (i, name) in names.enumerated() {
        let command = manager.parseCommandPrecomposition(legacy ? name.1 : name.0)
        #expect(command == (isCompositionModeXCommandSupported ? expected[i] : PrecompositionState.Commands.none))
      }
    }
  }

  @Test(arguments: [false, true])
  func parseCompositionModeCommandStringsForCompositionState(_ legacy: Bool) {
    withScopedSessionEnvironment {
      let manager = KeyMapManager()
      let expected: [CompositionState.Commands] = [
        .compositionModeHiragana, .compositionModeHalfKatakana, .compositionModeFullKatakana,
        .compositionModeHalfAlphanumeric, .compositionModeFullAlphanumeric,
      ]
      for (i, names) in Self.modeNames.enumerated() {
        let command = manager.parseCommandComposition(legacy ? names.1 : names.0)
        #expect(command == (isCompositionModeXCommandSupported ? expected[i] : CompositionState.Commands.none))
      }
    }
  }

  @Test(arguments: [false, true])
  func parseCompositionModeCommandStringsForConversionState(_ legacy: Bool) {
    withScopedSessionEnvironment {
      let manager = KeyMapManager()
      let expected: [ConversionState.Commands] = [
        .compositionModeHiragana, .compositionModeHalfKatakana, .compositionModeFullKatakana,
        .compositionModeHalfAlphanumeric, .compositionModeFullAlphanumeric,
      ]
      for (i, names) in Self.modeNames.enumerated() {
        let command = manager.parseCommandConversion(legacy ? names.1 : names.0)
        #expect(command == (isCompositionModeXCommandSupported ? expected[i] : ConversionState.Commands.none))
      }
    }
  }

  @Test func shiftTabToConvertPrev() {
    // http://b/2973471
    // Shift+TAB does not work on a suggestion window
    withScopedSessionEnvironment {
      for keymap in [Genmai_Config_Config.SessionKeymap.msime, .kotoeri, .atok] {
        let manager = KeyMapManager(getDefaultConfig(keymap))
        #expect(manager.getCommandConversion(parseKey("Shift Tab")) == .convertPrev, "\(keymap)")
      }
    }
  }

  @Test func openAppTest() {
    withScopedSessionEnvironment {
      do {  // ATOK
        let manager = KeyMapManager(getDefaultConfig(.atok))
        #expect(manager.getCommandPrecomposition(parseKey("Ctrl F7")) == .launchWordRegisterDialog)
        #expect(manager.getCommandPrecomposition(parseKey("Ctrl F12")) == .launchConfigDialog)
      }

      // http://b/3432829
      // MS-IME does not have the key-binding "Ctrl F7" in precomposition mode.
      do {
        let manager = KeyMapManager(getDefaultConfig(.msime))
        #expect(manager.getCommandPrecomposition(parseKey("Ctrl F7")) == nil)
      }
    }
  }

  @Test func undo() {
    withScopedSessionEnvironment {
      for keymap in [Genmai_Config_Config.SessionKeymap.atok, .msime, .kotoeri] {
        let manager = KeyMapManager(getDefaultConfig(keymap))
        #expect(manager.getCommandPrecomposition(parseKey("Ctrl Backspace")) == .undo, "\(keymap)")
      }
    }
  }

  @Test func reconvert() {
    withScopedSessionEnvironment {
      let cases: [(Genmai_Config_Config.SessionKeymap, String)] = [
        (.atok, "Shift Henkan"), (.msime, "Henkan"), (.kotoeri, "Ctrl Shift r"),
      ]
      for (keymap, key) in cases {
        let manager = KeyMapManager(getDefaultConfig(keymap))
        let keyEvent = parseKey(key)
        #expect(manager.getCommandDirect(keyEvent) == .reconvert, "\(keymap)")
        #expect(manager.getCommandPrecomposition(keyEvent) == .reconvert, "\(keymap)")
      }
    }
  }

  @Test func initialize() {
    withScopedSessionEnvironment {
      do {  // ATOK
        let manager = KeyMapManager(getDefaultConfig(.atok))
        #expect(manager.getCommandConversion(parseKey("Right")) == .segmentWidthExpand)
      }
      do {  // MSIME
        let manager = KeyMapManager(getDefaultConfig(.msime))
        #expect(manager.getCommandConversion(parseKey("Right")) == .segmentFocusRight)
      }
    }
  }

  @Test func addCommand() {
    withScopedSessionEnvironment {
      let manager = KeyMapManager()
      let kKeyEvent = "Ctrl Shift Insert"
      let keyEvent = parseKey(kKeyEvent)

      do {  // Add command
        #expect(manager.getCommandComposition(keyEvent) == nil)
        #expect(manager.addCommand("Composition", kKeyEvent, "Cancel"))
        #expect(manager.getCommandComposition(keyEvent) == .cancel)
      }

      do {  // Error detections
        #expect(!manager.addCommand("void", kKeyEvent, "Cancel"))
        #expect(!manager.addCommand("Composition", kKeyEvent, "Unknown"))
        #expect(!manager.addCommand("Composition", "INVALID", "Cancel"))
      }
    }
  }

  @Test func zeroQuerySuggestion() {
    withScopedSessionEnvironment {
      let manager = KeyMapManager()
      #expect(manager.addCommand("ZeroQuerySuggestion", "ESC", "Cancel"))
      #expect(manager.addCommand("ZeroQuerySuggestion", "Tab", "PredictAndConvert"))
      #expect(manager.addCommand("ZeroQuerySuggestion", "Shift Enter", "CommitFirstSuggestion"))
      // For fallback testing
      #expect(manager.addCommand("Precomposition", "Ctrl Backspace", "Revert"))

      #expect(manager.getCommandZeroQuerySuggestion(parseKey("ESC")) == .cancel)
      #expect(manager.getCommandZeroQuerySuggestion(parseKey("Tab")) == .predictAndConvert)
      #expect(manager.getCommandZeroQuerySuggestion(parseKey("Shift Enter")) == .commitFirstSuggestion)
      #expect(manager.getCommandZeroQuerySuggestion(parseKey("Ctrl Backspace")) == .revert)
    }
  }

  @Test func capsLock() {
    withScopedSessionEnvironment {
      // MSIME
      let manager = KeyMapManager(getDefaultConfig(.msime))
      #expect(manager.getCommandConversion(parseKey("CAPS a")) == .insertCharacter)
    }
  }

  @Test func shortcutKeysWithCapsLockIssue5627459() {
    withScopedSessionEnvironment {
      // MSIME
      let manager = KeyMapManager(getDefaultConfig(.msime))

      // "Ctrl CAPS H" means that Ctrl and H key are pressed w/o shift key.
      // See the description in command.proto.
      #expect(manager.getCommandComposition(parseKey("Ctrl CAPS H")) == .backspace)

      // "Ctrl CAPS h" means that Ctrl, Shift and H key are pressed.
      #expect(manager.getCommandComposition(parseKey("Ctrl CAPS h")) == nil)
    }
  }

  // CompositionModeX is not supported on MacOSX.
  @Test func compositionModeChangeIsNotEnabledOnChromeOsIssue13947207() {
    if !isCompositionModeXCommandSupported {
      return
    }
    withScopedSessionEnvironment {
      do {  // MSIME
        let manager = KeyMapManager(getDefaultConfig(.msime))
        #expect(manager.getCommandConversion(parseKey("Hiragana")) == .compositionModeHiragana)
      }
      do {  // CHROMEOS
        let manager = KeyMapManager(getDefaultConfig(.chromeos))
        #expect(manager.getCommandConversion(parseKey("Hiragana")) == nil)
      }
    }
  }

  @Test func isSameKeyMapManagerApplicable() {
    do {
      // Current: CHROMEOS + [] / Sending config: CHROMEOS + [] -> True
      var configChromeOs1 = Genmai_Config_Config()
      configChromeOs1.sessionKeymap = .chromeos
      var configChromeOs2 = Genmai_Config_Config()
      configChromeOs2.sessionKeymap = .chromeos
      #expect(KeyMapManager.isSameKeyMapManagerApplicable(configChromeOs1, configChromeOs2))
    }
    do {
      // CHROMEOS + [] vs CHROMEOS + [OVERLAY_HENKAN_MUHENKAN_TO_IME_ON_OFF] -> False
      var configChromeOs = Genmai_Config_Config()
      configChromeOs.sessionKeymap = .chromeos
      var configChromeOsHenkan = Genmai_Config_Config()
      configChromeOsHenkan.sessionKeymap = .chromeos
      configChromeOsHenkan.overlayKeymaps.append(.overlayHenkanMuhenkanToImeOnOff)
      #expect(!KeyMapManager.isSameKeyMapManagerApplicable(configChromeOs, configChromeOsHenkan))
    }
    do {
      // [HENKAN_MUHENKAN, FOR_TEST] vs [FOR_TEST] -> False
      var a = Genmai_Config_Config()
      a.sessionKeymap = .chromeos
      a.overlayKeymaps.append(.overlayHenkanMuhenkanToImeOnOff)
      a.overlayKeymaps.append(.overlayForTest)
      var b = Genmai_Config_Config()
      b.sessionKeymap = .chromeos
      b.overlayKeymaps.append(.overlayForTest)
      #expect(!KeyMapManager.isSameKeyMapManagerApplicable(a, b))
    }
    do {
      // [HENKAN_MUHENKAN, FOR_TEST] vs [FOR_TEST, HENKAN_MUHENKAN] -> False
      // (must be ordering aware)
      var a = Genmai_Config_Config()
      a.sessionKeymap = .chromeos
      a.overlayKeymaps.append(.overlayHenkanMuhenkanToImeOnOff)
      a.overlayKeymaps.append(.overlayForTest)
      var b = Genmai_Config_Config()
      b.sessionKeymap = .chromeos
      b.overlayKeymaps.append(.overlayForTest)
      b.overlayKeymaps.append(.overlayHenkanMuhenkanToImeOnOff)
      #expect(!KeyMapManager.isSameKeyMapManagerApplicable(a, b))
    }
  }
}
