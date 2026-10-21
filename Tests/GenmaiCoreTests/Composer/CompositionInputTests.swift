// Port of mozc/src/composer/composition_input_test.cc (3.35.6354).

import GenmaiProtocol
import Testing

@testable import GenmaiCore

private typealias ProbableKeyEvent = Genmai_Commands_KeyEvent.ProbableKeyEvent

@Suite struct CompositionInputTest {
  @Test func basicTest() {
    var input = CompositionInput()

    do {  // Initial status.
      #expect(input.isEmpty)
      #expect(input.raw.isEmpty)
      #expect(input.conversion.isEmpty)
      #expect(input.probableKeyEvents.isEmpty)
      #expect(!input.isNewInput)
      #expect(!input.isAsis)
    }

    do {  // Value setting
      input.raw = "raw"
      input.conversion = "conversion"

      var keyEvents: [ProbableKeyEvent] = []

      var keyEvent1 = ProbableKeyEvent()
      keyEvent1.keyCode = UInt32(UInt8(ascii: "i"))
      keyEvent1.probability = 0.6
      keyEvents.append(keyEvent1)

      var keyEvent2 = ProbableKeyEvent()
      keyEvent2.keyCode = UInt32(UInt8(ascii: "o"))
      keyEvent2.probability = 0.4
      keyEvents.append(keyEvent2)

      input.probableKeyEvents = keyEvents
      input.isNewInput = true

      #expect(!input.isEmpty)
      #expect(input.raw == "raw")
      #expect(input.conversion == "conversion")
      #expect(input.probableKeyEvents.count == 2)
      #expect(input.isNewInput)
    }

    var input2 = CompositionInput()
    do {  // Copy and Clear
      input2 = input
      input.clear()
      #expect(input.isEmpty)
      #expect(input.raw.isEmpty)
      #expect(input.conversion.isEmpty)
      #expect(input.probableKeyEvents.isEmpty)
      #expect(!input.isNewInput)

      #expect(!input2.isEmpty)
      #expect(input2.raw == "raw")
      #expect(input2.conversion == "conversion")
      #expect(input2.probableKeyEvents.count == 2)
      #expect(input2.isNewInput)
    }
  }

  @Test func specialKeys() {
    var input = CompositionInput()
    let newInput = true

    let table = Table()
    table.addRule("{henkan}", "", "!")

    do {
      // key event with a special key
      // special key is escaped as a command key wrapped with {}.
      var key = Genmai_Commands_KeyEvent()
      key.specialKey = .henkan
      _ = input.initialize(table, key, newInput)

      #expect(input.raw == "\u{F004}")  // U+F004 represents "{henkan}".
    }
    do {
      // key event with a key code and a special key.
      // This is not an expected case.
      var key = Genmai_Commands_KeyEvent()
      key.keyCode = UInt32(UInt8(ascii: "a"))
      key.specialKey = .henkan
      _ = input.initialize(table, key, newInput)
      #expect(input.raw == "a")
    }
    do {
      // key event with a key string and a special key.
      // This is not an expected case.
      var key = Genmai_Commands_KeyEvent()
      key.keyString = "あ"
      key.specialKey = .henkan
      _ = input.initialize(table, key, newInput)
      #expect(input.raw == "あ")
    }
  }

  @Test func asIsValue() {
    var input = CompositionInput()
    let newInput = true

    let table = Table()
    table.addRule("{henkan}", "", "!")

    do {
      // key event with a special key
      // special key is escaped as a command key wrapped with {}.
      var key = Genmai_Commands_KeyEvent()
      key.keyString = "[]"
      key.inputStyle = .asIs
      _ = input.initialize(table, key, newInput)

      #expect(input.raw == "[]")
      #expect(input.conversion == "[]")
      #expect(input.isAsis)
    }
  }
}
