// Port of mozc/src/composer/key_event_util_test.cc (3.35.6354).

import GenmaiProtocol
import Testing

@testable import GenmaiCore

private typealias KeyEvent = Genmai_Commands_KeyEvent

private func m(_ keys: Genmai_Commands_KeyEvent.ModifierKey...) -> UInt32 {
  keys.reduce(0) { $0 | UInt32($1.rawValue) }
}

private func ch(_ c: Unicode.Scalar) -> UInt32 { c.value }

private func parse(_ s: String) -> KeyEvent {
  var e = KeyEvent()
  _ = KeyParser.parseKey(s, &e)
  return e
}

/// CompareKeyEvent / EXPECT_EQ_KEY_EVENT.
private func expectEqKeyEvent(
  _ actual: KeyEvent, _ expected: KeyEvent, _ comment: Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  // Key code
  let expectedKeyCode: Int64 = expected.hasKeyCode ? Int64(expected.keyCode) : -1
  let actualKeyCode: Int64 = actual.hasKeyCode ? Int64(actual.keyCode) : -1
  #expect(
    actualKeyCode == expectedKeyCode, "Key codes are not same \(comment ?? "")",
    sourceLocation: sourceLocation)
  // Special key
  let expectedSpecialKey = expected.hasSpecialKey ? expected.specialKey.rawValue : -1
  let actualSpecialKey = actual.hasSpecialKey ? actual.specialKey.rawValue : -1
  #expect(
    actualSpecialKey == expectedSpecialKey, "Special keys are not same \(comment ?? "")",
    sourceLocation: sourceLocation)
  // Modifier keys
  #expect(
    KeyEventUtil.getModifiers(actual) == KeyEventUtil.getModifiers(expected),
    "Modifier keys are not same \(comment ?? "")", sourceLocation: sourceLocation)
}

@Suite struct KeyEventUtilTest {
  @Test func getModifiers() {
    var keyEvent = KeyEvent()

    _ = KeyParser.parseKey("a", &keyEvent)
    #expect(KeyEventUtil.getModifiers(keyEvent) == 0)

    _ = KeyParser.parseKey("Alt", &keyEvent)
    #expect(KeyEventUtil.getModifiers(keyEvent) == m(.alt))

    _ = KeyParser.parseKey("Ctrl", &keyEvent)
    #expect(KeyEventUtil.getModifiers(keyEvent) == m(.ctrl))

    _ = KeyParser.parseKey("Shift", &keyEvent)
    #expect(KeyEventUtil.getModifiers(keyEvent) == m(.shift))

    _ = KeyParser.parseKey("Caps", &keyEvent)
    #expect(KeyEventUtil.getModifiers(keyEvent) == m(.caps))

    _ = KeyParser.parseKey("LeftAlt RightAlt", &keyEvent)
    #expect(KeyEventUtil.getModifiers(keyEvent) == m(.alt, .leftAlt, .rightAlt))

    _ = KeyParser.parseKey("LeftAlt Ctrl RightShift", &keyEvent)
    #expect(
      KeyEventUtil.getModifiers(keyEvent) == m(.alt, .leftAlt, .ctrl, .shift, .rightShift))
  }

  @Test func getKeyInformation() throws {
    let kTestKeys = [
      "a",
      "Space",
      "Shift",
      "Shift a",
      "Shift Space",
      "Space a",
      "LeftShift Space a",
    ]

    var keyEvent = KeyEvent()
    var output: UInt64 = 0

    for testKey in kTestKeys {
      _ = KeyParser.parseKey(testKey, &keyEvent)
      try #require(KeyEventUtil.getKeyInformation(keyEvent, &output), "\(testKey)")

      var expected: UInt64 = 0
      if keyEvent.hasKeyCode {
        expected |= UInt64(keyEvent.keyCode)
      }
      if keyEvent.hasSpecialKey {
        expected |= UInt64(keyEvent.specialKey.rawValue) << 32
      }
      expected |= UInt64(KeyEventUtil.getModifiers(keyEvent)) << 48

      #expect(output == expected, "\(testKey)")
    }

    let kEscapeKeyCode: UInt32 = 27
    keyEvent = KeyEvent()
    keyEvent.keyCode = kEscapeKeyCode
    // Escape key should not set on key_code field.
    #expect(!KeyEventUtil.getKeyInformation(keyEvent, &output))
  }

  @Test func normalizeModifiers() throws {
    var keyEvent = KeyEvent()
    var normalizedKeyEvent = KeyEvent()

    do {  // Removes caps
      _ = KeyParser.parseKey("CAPS H", &keyEvent)
      try #require(keyEvent.modifierKeys.count == 1)
      try #require(KeyEventUtil.getModifiers(keyEvent) == m(.caps))
      try #require(keyEvent.keyCode == ch("H"))

      KeyEventUtil.normalizeModifiers(keyEvent, &normalizedKeyEvent)
      #expect(normalizedKeyEvent.modifierKeys.count == 0)
      #expect(normalizedKeyEvent.keyCode == ch("h"))
    }

    do {  // Removes left_shift
      _ = KeyParser.parseKey("LeftShift", &keyEvent)
      try #require(keyEvent.modifierKeys.count == 2)
      try #require(KeyEventUtil.getModifiers(keyEvent) == m(.shift, .leftShift))

      KeyEventUtil.normalizeModifiers(keyEvent, &normalizedKeyEvent)
      #expect(normalizedKeyEvent.modifierKeys.count == 1)
      try #require(KeyEventUtil.getModifiers(normalizedKeyEvent) == m(.shift))
    }

    do {  // Removes caps and left_shift
      _ = KeyParser.parseKey("CAPS LeftShift H", &keyEvent)
      try #require(keyEvent.modifierKeys.count == 3)
      try #require(KeyEventUtil.getModifiers(keyEvent) == m(.caps, .shift, .leftShift))

      try #require(keyEvent.keyCode == ch("H"))

      KeyEventUtil.normalizeModifiers(keyEvent, &normalizedKeyEvent)
      #expect(normalizedKeyEvent.modifierKeys.count == 1)
      #expect(KeyEventUtil.getModifiers(normalizedKeyEvent) == m(.shift))
      #expect(normalizedKeyEvent.keyCode == ch("h"))
    }
  }

  @Test func normalizeNumpadKey() {
    let kNormalizeNumpadKeyTestData: [(from: String, to: String)] = [
      ("a", "a"),
      ("Shift", "Shift"),
      ("Caps", "Caps"),
      ("Enter", "Enter"),
      ("Shift Caps a", "Shift Caps a"),
      ("NUMPAD0", "0"),
      ("NUMPAD9", "9"),
      ("MULTIPLY", "*"),
      ("SEPARATOR", "Enter"),
      ("EQUALS", "="),
      ("Ctrl NUMPAD0", "Ctrl 0"),
      ("NUMPAD0 a", "0"),
    ]

    for data in kNormalizeNumpadKeyTestData {
      let keyEventFrom = parse(data.from)
      let keyEventTo = parse(data.to)
      var keyEventNormalized = KeyEvent()
      KeyEventUtil.normalizeNumpadKey(keyEventFrom, &keyEventNormalized)
      expectEqKeyEvent(keyEventNormalized, keyEventTo, "\(data.from)")
    }
  }

  @Test func maybeGetKeyStub() {
    var keyEvent = KeyEvent()
    var key: KeyInformation = 0

    _ = KeyParser.parseKey("Shift", &keyEvent)
    #expect(!KeyEventUtil.maybeGetKeyStub(keyEvent, &key))

    _ = KeyParser.parseKey("Space", &keyEvent)
    #expect(!KeyEventUtil.maybeGetKeyStub(keyEvent, &key))

    let kEscapeKeyCode: UInt32 = 27
    keyEvent = KeyEvent()
    keyEvent.keyCode = kEscapeKeyCode
    #expect(!KeyEventUtil.maybeGetKeyStub(keyEvent, &key))

    _ = KeyParser.parseKey("a", &keyEvent)
    #expect(KeyEventUtil.maybeGetKeyStub(keyEvent, &key))
    #expect(key == KeyInformation(KeyEvent.SpecialKey.textInput.rawValue) << 32)
  }

  @Test func removeModifiers() {
    let kRemoveModifiersTestData: [(input: String, remove: String, output: String)] = [
      ("", "", ""),
      ("Ctrl Shift LeftAlt Caps", "Ctrl Shift LeftAlt Caps", ""),
      ("Ctrl Shift LeftAlt Caps", "Shift Caps", "Ctrl LeftAlt"),
      ("Ctrl Shift LeftAlt Caps", "Alt", "Ctrl Shift Caps"),
      ("", "Ctrl Shift LeftAlt Caps", ""),
    ]

    for (i, data) in kRemoveModifiersTestData.enumerated() {
      let input = parse(data.input)
      let remove = parse(data.remove)
      let output = parse(data.output)
      let removeModifiers = KeyEventUtil.getModifiers(remove)

      var removedKeyEvent = KeyEvent()
      KeyEventUtil.removeModifiers(input, removeModifiers, &removedKeyEvent)
      expectEqKeyEvent(removedKeyEvent, output, "index = \(i)")
    }
  }

  @Test func hasModifiers() {
    #expect(KeyEventUtil.hasAlt(m(.alt)))
    #expect(KeyEventUtil.hasAlt(m(.leftAlt)))
    #expect(KeyEventUtil.hasAlt(m(.alt, .ctrl)))
    #expect(!KeyEventUtil.hasAlt(0))
    #expect(!KeyEventUtil.hasAlt(m(.ctrl)))
    #expect(!KeyEventUtil.hasAlt(m(.shift)))

    #expect(KeyEventUtil.hasCtrl(m(.ctrl)))
    #expect(KeyEventUtil.hasCtrl(m(.leftCtrl)))
    #expect(KeyEventUtil.hasCtrl(m(.ctrl, .shift)))
    #expect(!KeyEventUtil.hasCtrl(0))
    #expect(!KeyEventUtil.hasCtrl(m(.alt)))
    #expect(!KeyEventUtil.hasCtrl(m(.shift)))

    #expect(KeyEventUtil.hasShift(m(.shift)))
    #expect(KeyEventUtil.hasShift(m(.leftShift)))
    #expect(KeyEventUtil.hasShift(m(.shift, .alt)))
    #expect(!KeyEventUtil.hasShift(0))
    #expect(!KeyEventUtil.hasShift(m(.alt)))
    #expect(!KeyEventUtil.hasShift(m(.ctrl)))

    #expect(KeyEventUtil.hasCaps(m(.caps)))
    #expect(KeyEventUtil.hasCaps(m(.caps, .alt)))
    #expect(!KeyEventUtil.hasCaps(0))
    #expect(!KeyEventUtil.hasCaps(m(.ctrl)))
  }

  @Test func isModifiers() {
    struct IsModifiersTestData {
      var modifiers: UInt32
      var isAlt: Bool
      var isCtrl: Bool
      var isShift: Bool
      var isAltCtrl: Bool
      var isAltShift: Bool
      var isCtrlShift: Bool
      var isAltCtrlShift: Bool
      init(
        _ modifiers: UInt32, _ isAlt: Bool, _ isCtrl: Bool, _ isShift: Bool, _ isAltCtrl: Bool,
        _ isAltShift: Bool, _ isCtrlShift: Bool, _ isAltCtrlShift: Bool
      ) {
        self.modifiers = modifiers
        self.isAlt = isAlt
        self.isCtrl = isCtrl
        self.isShift = isShift
        self.isAltCtrl = isAltCtrl
        self.isAltShift = isAltShift
        self.isCtrlShift = isCtrlShift
        self.isAltCtrlShift = isAltCtrlShift
      }
    }
    let kIsModifiersTestData: [IsModifiersTestData] = [
      IsModifiersTestData(0, false, false, false, false, false, false, false),
      IsModifiersTestData(m(.alt), true, false, false, false, false, false, false),
      IsModifiersTestData(m(.ctrl), false, true, false, false, false, false, false),
      IsModifiersTestData(m(.shift), false, false, true, false, false, false, false),
      IsModifiersTestData(m(.alt, .ctrl), false, false, false, true, false, false, false),
      IsModifiersTestData(m(.alt, .shift), false, false, false, false, true, false, false),
      IsModifiersTestData(m(.ctrl, .shift), false, false, false, false, false, true, false),
      IsModifiersTestData(m(.alt, .ctrl, .shift), false, false, false, false, false, false, true),
      IsModifiersTestData(m(.leftAlt), true, false, false, false, false, false, false),
      IsModifiersTestData(
        m(.alt, .leftAlt, .rightAlt), true, false, false, false, false, false, false),
      IsModifiersTestData(m(.caps), false, false, false, false, false, false, false),
      IsModifiersTestData(m(.alt, .caps), true, false, false, false, false, false, false),
    ]

    for (i, data) in kIsModifiersTestData.enumerated() {
      #expect(KeyEventUtil.isAlt(data.modifiers) == data.isAlt, "index: \(i)")
      #expect(KeyEventUtil.isCtrl(data.modifiers) == data.isCtrl, "index: \(i)")
      #expect(KeyEventUtil.isShift(data.modifiers) == data.isShift, "index: \(i)")
      #expect(KeyEventUtil.isAltCtrl(data.modifiers) == data.isAltCtrl, "index: \(i)")
      #expect(KeyEventUtil.isAltShift(data.modifiers) == data.isAltShift, "index: \(i)")
      #expect(KeyEventUtil.isCtrlShift(data.modifiers) == data.isCtrlShift, "index: \(i)")
      #expect(KeyEventUtil.isAltCtrlShift(data.modifiers) == data.isAltCtrlShift, "index: \(i)")
    }
  }

  @Test func isLowerUpperAlphabet() {
    let kIsLowerUpperAlphabetTestData: [(key: String, isLower: Bool, isUpper: Bool)] = [
      ("a", true, false),
      ("A", false, true),
      ("Shift a", false, true),
      ("Shift A", true, false),
      ("Shift Caps a", true, false),
      ("Shift Caps A", false, true),
      ("0", false, false),
      ("Shift", false, false),
      ("Caps", false, false),
      ("Space", false, false),
    ]

    for data in kIsLowerUpperAlphabetTestData {
      let keyEvent = parse(data.key)
      #expect(KeyEventUtil.isLowerAlphabet(keyEvent) == data.isLower, "\(data.key)")
      #expect(KeyEventUtil.isUpperAlphabet(keyEvent) == data.isUpper, "\(data.key)")
    }
  }

  @Test func isNumpadKey() {
    let kIsNumpadKeyTestData: [(key: String, isNumpadKey: Bool)] = [
      ("a", false), ("A", false), ("Shift", false),
      ("Shift a", false), ("0", false), ("EISU", false),
      ("NUMPAD0", true), ("NUMPAD9", true), ("MULTIPLY", true),
      ("EQUALS", true), ("COMMA", true), ("TEXTINPUT", false),
    ]

    for data in kIsNumpadKeyTestData {
      let keyEvent = parse(data.key)
      #expect(KeyEventUtil.isNumpadKey(keyEvent) == data.isNumpadKey, "\(data.key)")
    }
  }
}
