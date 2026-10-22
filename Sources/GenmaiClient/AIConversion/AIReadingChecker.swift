// The reading check of AI candidates (not part of Mozc).
//
// The genmai model sometimes proposes a text that does not read as the input (ははははがいたいらしい →
// 母は歯痒いらしい). This check drops such candidates from the AI n-best list. It is deliberately lenient: a
// candidate passes if *some* reading of it matches the input, so that correct conversions are never dropped
// (an earlier attempt that required Mozc's reverse conversion to give exactly the input lost correct answers
// such as 日本 = にっぽん, numbers and proper nouns). It only removes candidates; the order is unchanged.
//
// Both strings are compared after `fold`: NFKC, katakana → hiragana, voicing marks removed (が → か, ぱ → は), small
// kana enlarged (っ → つ, ゃ → や), prolonged sound marks and tildes removed, so that rendaku, sokuon and long
// vowels (三本 = さんぼん, コーヒー = こーひー) match. A dynamic program reads the candidate left to right; a state
// is (position in the text, position in the folded reading) and a step is one of
//   a. a dictionary word text[p..<q] (Mozc's system dictionary, by reverse lookup) with one of its readings;
//      this includes words spanning several dictionary words if they are in the dictionary (御社 = おんしゃ),
//   b. a single kanji with one of the readings of its one-character entries in the dictionary (on and kun
//      readings), for compounds missing from the dictionary (仕置人 = しおきじん),
//   c. a kana or symbol matching itself (characters that fold to nothing are skipped),
//   d. a wildcard for runs of digits / Latin or other letters (plus one following kanji, e.g. a counter) and for
//      kanji without any reading: 1...6 × length + 6 reading characters (1991 = せんきゅうひゃく…, １日 = ついたち),
//   e. between two kanji, one extra か / の / つ in the reading (鶴岡 = つるがおか).
// The text is readable if its end is reached exactly at the end of the reading.

import Foundation
import GenmaiBase
import GenmaiCore
import Synchronization

public final class AIReadingChecker: Sendable {
  private let systemDictionary: SystemDictionary
  /// Recent results ("reading\0text" → readable): the same candidates come back at every keystroke (suggestion)
  /// and at the conversion key.
  private let results = Mutex<[String: Bool]>([:])
  static let maxCachedResults = 4096

  /// Dictionary words longer than this (in characters) are not looked up.
  static let maxWordLength = 16
  /// Reading characters a wildcard may consume: 1 ... `wildcardPerCharacter` × length + `wildcardBase`.
  static let wildcardPerCharacter = 6
  static let wildcardBase = 6
  /// Reading characters allowed between two kanji (folded).
  static let linkingKana: Set<Unicode.Scalar> = ["か", "の", "つ"]
  /// Symbols that may continue a run of digits / letters in a wildcard (3.5, 10:30, 50%, A-1).
  static let wildcardJoiners: Set<Character> = [
    ".", ",", ":", "/", "%", "+", "-", "&", "．", "，", "：", "／", "％", "＋", "－", "＆",
  ]

  /// Builds the checker from the data set: a second instance of the system dictionary with the reverse lookup
  /// index (~0.1 s, ~20 MB).
  public init(dataManager: DataManager) throws {
    systemDictionary = try SystemDictionary.Builder(image: dataManager.getSystemDictionaryData())
      .setOptions(.enableReverseLookupIndex).build()
  }

  // MARK: - Filtering

  /// `texts` without the candidates that cannot be read as `reading`, in the same order. If none can, the first
  /// one is kept (better than nothing).
  public func filter(_ texts: [String], reading: String) -> [String] {
    let folded = Self.fold(reading)
    let kept = texts.filter { text in
      let key = reading + "\0" + text
      if let cached = results.withLock({ $0[key] }) {
        return cached
      }
      let readable = isReadable(text, foldedReading: folded)
      results.withLock { r in
        if r.count >= Self.maxCachedResults {
          r.removeAll(keepingCapacity: true)
        }
        r[key] = readable
      }
      return readable
    }
    return kept.isEmpty ? Array(texts.prefix(1)) : kept
  }

  /// Whether `text` can be read as `reading`.
  public func isReadable(_ text: String, reading: String) -> Bool {
    isReadable(text, foldedReading: Self.fold(reading))
  }

  func isReadable(_ text: String, foldedReading r: [Unicode.Scalar]) -> Bool {
    let t = Array(text)
    let n = t.count
    let m = r.count
    let width = m + 1
    var reach = [Bool](repeating: false, count: (n + 1) * width)
    reach[0] = true

    func matches(_ s: [Unicode.Scalar], at j: Int) -> Bool {
      j + s.count <= m && r[j..<(j + s.count)].elementsEqual(s)
    }

    for p in 0..<n {
      // e. one linking kana between two kanji (applied once: only to the states that reached p by reading text)
      if p > 0, Self.isKanji(t[p - 1]), Self.isKanji(t[p]) {
        for j in stride(from: m - 1, through: 0, by: -1) where reach[p * width + j] && Self.linkingKana.contains(r[j]) {
          reach[p * width + j + 1] = true
        }
      }
      let states = (0...m).filter { reach[p * width + $0] }
      guard !states.isEmpty else { continue }
      var steps: [(length: Int, reading: [Unicode.Scalar])] = []
      let c = t[p]
      let kanji = Self.isKanji(c)
      // c. kana and symbols read as themselves
      if !kanji {
        steps.append((1, Self.fold(String(c))))
      }
      // a., b. dictionary words starting at p, including the one-character entries. Words starting with
      // hiragana only matter before a kanji (お茶, ご飯); kana-only words read as themselves (c.).
      var words: [(length: Int, reading: [Unicode.Scalar])] = []
      if !Self.isHiragana(c) || t[(p + 1)..<min(n, p + 3)].contains(where: Self.isKanji) {
        words = dictionaryWords(String(t[p..<min(n, p + Self.maxWordLength)]))
        steps += words
      }
      for (length, s) in steps {
        for j in states where matches(s, at: j) {
          reach[(p + length) * width + j + s.count] = true
        }
      }
      // d. wildcards
      var spans: [Int] = []
      if Self.isWildcardCharacter(c) {
        var q = p + 1
        while q < n,
          Self.isWildcardCharacter(t[q])
            || (Self.wildcardJoiners.contains(t[q]) && q + 1 < n && Self.isWildcardCharacter(t[q + 1]))
        {
          q += 1
        }
        spans = Array((p + 1)...q)
        if q < n, Self.isKanji(t[q]) { spans.append(q + 1) }
      } else if kanji, !words.contains(where: { $0.length == 1 }) {
        spans = [p + 1]
      }
      for q in spans {
        let maxLength = Self.wildcardPerCharacter * (q - p) + Self.wildcardBase
        for j in states {
          for k in 1...maxLength where j + k <= m {
            reach[q * width + j + k] = true
          }
        }
      }
    }
    return reach[n * width + m]
  }

  /// Words of the system dictionary that are prefixes of `query`: (length in characters, folded reading).
  private func dictionaryWords(_ query: String) -> [(length: Int, reading: [Unicode.Scalar])] {
    let collector = WordCollector(query)
    systemDictionary.lookupReverse(query, callback: collector)
    return collector.words
  }

  private final class WordCollector: DictionaryCallback {
    let query: String
    var words: [(length: Int, reading: [Unicode.Scalar])] = []
    var seen = Set<String>()

    init(_ query: String) {
      self.query = query
    }

    func onKey(_ key: String) -> DictionaryCallbackResult { .traverseContinue }

    func onActualKey(_ key: String, _ actualKey: String, _ numExpanded: Int) -> DictionaryCallbackResult {
      .traverseContinue
    }

    // Reverse lookup: token.key is the surface, token.value the reading.
    func onToken(_ key: String, _ expandedKey: String, _ token: Token) -> DictionaryCallbackResult {
      let surface = token.key
      guard !surface.isEmpty, query.hasPrefix(surface), seen.insert(surface + "\t" + token.value).inserted else {
        return .traverseContinue
      }
      let reading = AIReadingChecker.fold(token.value)
      if !reading.isEmpty {
        words.append((surface.count, reading))
      }
      return .traverseContinue
    }

    func isKanaModifierInsensitiveConversion() -> Bool { false }
  }

  // MARK: - Characters

  static func isKanji(_ c: Character) -> Bool {
    c.unicodeScalars.count == 1 && Util.getScriptType(Char32(c.unicodeScalars.first!.value)) == .kanji
  }

  static func isHiragana(_ c: Character) -> Bool {
    c.unicodeScalars.count == 1 && (0x3041...0x309F).contains(c.unicodeScalars.first!.value)
  }

  /// Digits and letters other than kana and kanji (Latin, Greek, ...).
  static func isWildcardCharacter(_ c: Character) -> Bool {
    guard let u = c.unicodeScalars.first else { return false }
    switch Util.getScriptType(Char32(u.value)) {
    case .number, .alphabet:
      return true
    case .kanji, .hiragana, .katakana:
      return false
    default:
      return c.isNumber || c.isLetter
    }
  }

  static let smallKana: [Unicode.Scalar: Unicode.Scalar] = [
    "ぁ": "あ", "ぃ": "い", "ぅ": "う", "ぇ": "え", "ぉ": "お", "っ": "つ", "ゃ": "や", "ゅ": "ゆ", "ょ": "よ",
    "ゎ": "わ", "ゕ": "か", "ゖ": "け",
  ]
  static let removed: Set<Unicode.Scalar> = ["ー", "〜", "~", "\u{3099}", "\u{309A}", "\u{309B}", "\u{309C}"]

  /// NFKC, katakana → hiragana, voicing marks removed, small kana enlarged, ー / 〜 / ～ and white space removed.
  static func fold(_ s: String) -> [Unicode.Scalar] {
    var out: [Unicode.Scalar] = []
    let normalized = s.precomposedStringWithCompatibilityMapping.decomposedStringWithCanonicalMapping
    for var u in normalized.unicodeScalars {
      if (0x30A1...0x30F6).contains(u.value) {
        u = Unicode.Scalar(u.value - 0x60)!
      }
      if removed.contains(u) || u.properties.isWhitespace {
        continue
      }
      out.append(smallKana[u] ?? u)
    }
    return out
  }
}
