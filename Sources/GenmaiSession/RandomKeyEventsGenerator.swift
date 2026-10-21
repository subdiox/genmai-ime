// Port of mozc/src/session/random_keyevents_generator.{h,cc} (3.35.6354).
//
// Swift notes: absl::BitGen is GenmaiBase's `Random` (system or seeded
// xoshiro256**), so the generated sequences do not match the C++ ones; the
// distributions are the same (absl::Uniform(a, b) is [a, b), absl::Bernoulli,
// absl::Poisson). The test sentences (kTestSentences) are generated into
// RandomKeyEventsGeneratorData.swift.

import Foundation
import GenmaiBase
import GenmaiProtocol

// Constants for ProbableKeyEvent.
private let kMostPossibleKeyProbability = 0.98
private let kProbableKeyEventSize = 8

private let kSpecialKeys: [Genmai_Commands_KeyEvent.SpecialKey] = [
  .space, .backspace,
  .del, .down,
  .end, .enter,
  .escape, .home,
  .insert, .henkan,
  .muhenkan, .left,
  .right, .up,
  .down, .pageUp,
  .pageDown, .tab,
  .f1, .f2,
  .f3, .f4,
  .f5, .f6,
  .f7, .f8,
  .f9, .f10,
  .f11, .f12,
  .numpad0, .numpad1,
  .numpad2, .numpad3,
  .numpad4, .numpad5,
  .numpad6, .numpad7,
  .numpad8, .numpad9,
  .multiply, .add,
  .separator, .subtract,
  .decimal, .divide,
  .equals, .comma,
]

// Converts from Hiragana to Romaji.
func toRomaji(_ hiragana: some StringProtocol) -> String {
  let tmp = Japanese.hiraganaToRomanji(hiragana)
  return Japanese.fullWidthToHalfWidth(tmp)
}

public struct RandomKeyEventsGenerator {
  private var bitgen: Random

  public init() {
    bitgen = Random()
  }

  /// Initialize with seed.
  public init(_ rng: Random) {
    bitgen = rng
  }

  // absl::Uniform<T>(gen, lo, hi): [lo, hi).
  private mutating func uniform(_ lo: Int, _ hi: Int) -> Int {
    Int.random(in: lo..<hi, using: &bitgen)
  }

  private mutating func bernoulli(_ p: Double) -> Bool {
    Double.random(in: 0..<1, using: &bitgen) < p
  }

  // absl::Poisson<size_t>(gen, mean) (Knuth's algorithm).
  private mutating func poisson(_ mean: Double) -> Int {
    let l = exp(-mean)
    var k = 0
    var p = 1.0
    repeat {
      k += 1
      p *= Double.random(in: 0..<1, using: &bitgen)
    } while p > l
    return k - 1
  }

  /// Load all data to avoid a increase of memory usage
  /// during memory leak tests.
  public func prepareForMemoryLeakTest() {
    // Read all kTestSentences and load these to memory.
    for sentence in kTestSentences {
      precondition(!sentence.isEmpty)
    }
  }

  /// Generates KeyEvent instances based on |romaji| and stores into |keys|.
  private mutating func typeRawKeys(
    _ romaji: some StringProtocol, _ createProbableKeyEvents: Bool,
    _ keys: inout [Genmai_Commands_KeyEvent]
  ) {
    for scalar in romaji.unicodeScalars {
      let codepoint = scalar.value
      if codepoint < 0x20 || codepoint > 0x7F {
        continue
      }
      var key = Genmai_Commands_KeyEvent()
      key.keyCode = codepoint
      if createProbableKeyEvents {
        var probableKeyEvent = Genmai_Commands_KeyEvent.ProbableKeyEvent()
        probableKeyEvent.keyCode = codepoint
        probableKeyEvent.probability = kMostPossibleKeyProbability
        key.probableKeyEvent.append(probableKeyEvent)
        for _ in 0..<kProbableKeyEventSize {
          var probableKeyEvent = Genmai_Commands_KeyEvent.ProbableKeyEvent()
          probableKeyEvent.keyCode = UInt32(uniform(0x20, 0x7F))
          probableKeyEvent.probability =
            (1.0 - kMostPossibleKeyProbability) / Double(kProbableKeyEventSize)
          key.probableKeyEvent.append(probableKeyEvent)
        }
      }
      keys.append(key)
    }
  }

  /// Generates KeyEvent instances based on |sentence| and stores into |keys|.
  /// And Enter key event is appended at the tail.
  /// The instances have ProbableKeyEvent if |create_probable_key_events| is set.
  private mutating func generateMobileSequenceInternal(
    _ sentence: some StringProtocol, _ createProbableKeyEvents: Bool,
    _ keys: inout [Genmai_Commands_KeyEvent]
  ) {
    let input = toRomaji(sentence)

    // Type the sentence
    typeRawKeys(input, createProbableKeyEvents, &keys)

    var key = Genmai_Commands_KeyEvent()
    key.specialKey = .enter
    keys.append(key)
  }

  /// Generate a random test keyevents sequence for mobile
  public mutating func generateMobileSequence(
    _ createProbableKeyEvents: Bool, _ keys: inout [Genmai_Commands_KeyEvent]
  ) {
    keys.removeAll()

    let sentence = kTestSentences[uniform(0, kTestSentences.count)]
    precondition(!sentence.isEmpty)
    let bytes = Array(sentence.utf8)
    var i = 0
    while i < bytes.count {
      // To simulate mobile key events, split given sentence into smaller parts.
      // Average 5, Min 1, Max 15.
      // absl::Poisson returns [0, max]. Add one and cap at 15.
      // (Note: the C++ code uses std::max, so len is at least 15.)
      let len = max(poisson(4) + 1, 15)
      // absl::ClippedSubstr(sentence, i, len) (byte based).
      let end = min(i + len, bytes.count)
      let part = String(decoding: bytes[i..<end], as: UTF8.self)
      generateMobileSequenceInternal(part, createProbableKeyEvents, &keys)
      i += len
    }
  }

  /// Generate a random test keyevents sequence for desktop
  public mutating func generateSequence(_ keys: inout [Genmai_Commands_KeyEvent]) {
    keys.removeAll()

    let sentence = kTestSentences[uniform(0, kTestSentences.count)]
    precondition(!sentence.isEmpty)

    let input = toRomaji(sentence)

    // Must send ON event first.
    do {
      var key = Genmai_Commands_KeyEvent()
      key.specialKey = .on
      keys.append(key)
    }

    var basicKeys: [Genmai_Commands_KeyEvent] = []

    // generate basic input
    typeRawKeys(input, false, &basicKeys)

    // basic keys + conversion
    do {
      keys.append(contentsOf: basicKeys)

      for _ in 0..<5 {
        let num = uniform(8, 38)
        for _ in 0..<num {
          if bernoulli(0.25) {
            var key = Genmai_Commands_KeyEvent()
            key.specialKey = .space
            key.modifierKeys.append(.shift)
            keys.append(key)
          }
        }
        var key = Genmai_Commands_KeyEvent()
        key.specialKey = .right
        keys.append(key)
      }

      var key = Genmai_Commands_KeyEvent()
      key.specialKey = .enter
      keys.append(key)
    }

    // segment resize
    do {
      keys.append(contentsOf: basicKeys)

      let num = uniform(10, 40)
      for _ in 0..<num {
        var key = Genmai_Commands_KeyEvent()
        switch uniform(0, 4) {
        case 0:
          key.specialKey = .left
          if bernoulli(0.5) {
            key.modifierKeys.append(.shift)
          }
        case 1:
          key.specialKey = .right
          if bernoulli(0.5) {
            key.modifierKeys.append(.shift)
          }
        default:
          let spaceNum = uniform(3, 23)
          for _ in 0..<spaceNum {
            key.specialKey = .space
            keys.append(key)
          }
        }

        if bernoulli(0.25) {
          key.modifierKeys.append(.ctrl)
        }

        if bernoulli(0.1) {
          key.modifierKeys.append(.alt)
        }

        keys.append(key)
      }

      var key = Genmai_Commands_KeyEvent()
      key.specialKey = .enter
      keys.append(key)
    }

    // insert + delete
    do {
      keys.append(contentsOf: basicKeys)

      let num = uniform(10, 30)
      for _ in 0..<num {
        var key = Genmai_Commands_KeyEvent()
        switch uniform(0, 5) {
        case 0:
          key.specialKey = .left
        case 1:
          key.specialKey = .right
        case 2:
          key.specialKey = .del
        case 3:
          key.specialKey = .backspace
        default:
          // add any ascii
          let insertNum = uniform(1, 6)
          for _ in 0..<insertNum {
            key.keyCode = getRandomAsciiKey()
          }
        }
        keys.append(key)
      }

      var key = Genmai_Commands_KeyEvent()
      key.specialKey = .enter
      keys.append(key)
    }

    // basic keys + modifiers
    do {
      for i in 0..<basicKeys.count {
        var key = Genmai_Commands_KeyEvent()
        switch uniform(0, 8) {
        case 0:
          // (C++ sets the SpecialKey enum value as key_code.)
          key.keyCode = UInt32(kSpecialKeys[uniform(0, kSpecialKeys.count)].rawValue)
        case 1:
          key.keyCode = getRandomAsciiKey()
        default:
          key = basicKeys[i]
        }

        if bernoulli(0.1) {  // 10%
          key.modifierKeys.append(.ctrl)
        }

        if bernoulli(0.1) {  // 10%
          key.modifierKeys.append(.shift)
        }

        if bernoulli(0.02) {  // 2%
          key.modifierKeys.append(.keyDown)
        }

        if bernoulli(0.02) {  // 2%
          key.modifierKeys.append(.keyUp)
        }

        keys.append(key)
      }

      // submit
      var key = Genmai_Commands_KeyEvent()
      key.specialKey = .enter
      keys.append(key)
    }

    precondition(!keys.isEmpty)
  }

  private mutating func getRandomAsciiKey() -> UInt32 {
    UInt32(uniform(Int(UInt8(ascii: " ")), Int(UInt8(ascii: "~"))))
  }

  /// return test sentence set embedded in RandomKeyEventsGenerator.
  public static func getTestSentences() -> [String] {
    kTestSentences
  }
}
