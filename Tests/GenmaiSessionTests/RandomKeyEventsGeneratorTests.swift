// Port of mozc/src/session/random_keyevents_generator_test.cc (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiSession

// Some of the tests are not deterministic, but we repeat enough times so
// they highly likely succeed.
private let kIterations = 1000

@Suite struct RandomKeyEventsGeneratorTests {
  // This is not a deterministic test.
  @Test func generateSequence() {
    var generator = RandomKeyEventsGenerator()
    generator.prepareForMemoryLeakTest()

    var keys: [Genmai_Commands_KeyEvent] = []
    // Deterministic checks
    generator.generateSequence(&keys)
    #expect(!keys.isEmpty)
    #expect(keys.first?.specialKey == .on)
    #expect(keys.last?.specialKey == .enter)

    // Non-deterministic checks
    var specialKeys: [Genmai_Commands_KeyEvent.SpecialKey: Int] = [:]
    var modifiers = false
    for _ in 0..<kIterations {
      keys.removeAll()
      generator.generateSequence(&keys)
      for k in keys {
        specialKeys[k.specialKey, default: 0] += 1
        modifiers = modifiers || !k.modifierKeys.isEmpty
      }
    }
    // The following conditions are highly likely true given the number of
    // iterations.
    #expect(modifiers)
    #expect(specialKeys[.backspace, default: 0] > 0)
    #expect(specialKeys[.left, default: 0] > 0)
    #expect(specialKeys[.right, default: 0] > 0)
    #expect(specialKeys[.del, default: 0] > 0)
  }

  // This is not a deterministic test.
  @Test func generateMobileSequence() {
    var generator = RandomKeyEventsGenerator()
    generator.prepareForMemoryLeakTest()

    // Deterministic checks
    var keys: [Genmai_Commands_KeyEvent] = []
    generator.generateMobileSequence(false, &keys)
    #expect(!keys.isEmpty)
    #expect(keys.last?.specialKey == .enter)
  }

  @Test func generateMobileSequenceProbable() {
    var generator = RandomKeyEventsGenerator()
    generator.prepareForMemoryLeakTest()

    var keys: [Genmai_Commands_KeyEvent] = []
    // Deterministic checks
    generator.generateMobileSequence(true, &keys)
    #expect(!keys.isEmpty)
    #expect(keys.last?.specialKey == .enter)
    for key in keys.dropLast() {
      for p in key.probableKeyEvent {
        #expect(p.probability > 0)
        #expect(p.probability < 1)
      }
    }
  }
}
