// Scores AI candidates with Mozc's dictionary and connection costs (not part of Mozc).
//
// The genmai model does not know rare proper nouns and invents a plausible spelling (西神吉 → 西換気, 日下部町 →
// 草壁町), often with the right one further down its n-best list. Mozc's dictionary knows them: a word it has for the
// whole reading is one cheap token, an invented spelling needs several words or none. `cost(_:reading:)` is the
// cost of the cheapest path through Mozc's lattice that produces exactly the text (system dictionary tokens +
// connection costs, like the converter's Viterbi search but constrained to the text); `rerank` adds it to the
// model's score to choose among candidates that differ only in kanji, so that a better dictionary also improves the
// AI conversion.
//
// Characters no dictionary token covers are read as themselves (kana, symbols) or as a wildcard (digits, Latin), at
// `unknownCost` per character; a kanji without a token makes the text unreachable (nil).
//
// The model often writes a proper noun it does not know in kana (莇平 → アザミヒラ) or with other kanji, and then the
// right spelling is not among its candidates at all. `propose` offers the dictionary's: the cheapest path through
// the lattice (`bestPath`, Mozc's conversion without its rewriters) and the AI's top with the path's proper nouns
// put in for their kana; the augmenter scores them with the model and `rerank` weighs them like the AI's candidates.

import Foundation
import GenmaiBase
import GenmaiCore
import Synchronization

public final class AIDictionaryScorer: Sendable {
  private let systemDictionary: SystemDictionary
  private let connector: Connector
  private let posMatcher: PosMatcher
  private let results = Mutex<[String: Int?]>([:])
  static let maxCachedResults = 4096
  /// The cost of a character without a dictionary token (about a word's cost: exp(-6) in Mozc's units).
  static let unknownCost = 3000
  /// The cost of a character without a dictionary token in `bestPath`: so high that the path takes dictionary words
  /// wherever they cover the reading (with `unknownCost` a run of kana as themselves beat 西神吉 for にしかんき).
  static let pathGapCost = 10000
  /// Mozc costs are -500 × ln(probability).
  public static let costPerNat = 500.0

  public init(dataManager: DataManager) throws {
    systemDictionary = try SystemDictionary.Builder(image: dataManager.getSystemDictionaryData()).build()
    connector = try Connector.create(dataManager.getConnectorData())
    posMatcher = PosMatcher(dataManager.getPosMatcherData())
  }

  /// The cost of producing `text` from `reading` (hiragana), nil if Mozc's dictionary cannot produce it.
  public func cost(_ text: String, reading: String) -> Int? {
    let cacheKey = reading + "\0" + text
    if let cached = results.withLock({ $0[cacheKey] }) {
      return cached
    }
    let c = compute(Array(text), reading: Array(reading))
    results.withLock { r in
      if r.count >= Self.maxCachedResults {
        r.removeAll(keepingCapacity: true)
      }
      r[cacheKey] = c
    }
    return c
  }

  /// `texts` (best first, `scores`: the model's log-probs) with the top replaced by the best candidate by model score
  /// + weight × (-cost / 500), in two rounds:
  /// 1. among the texts that spell the kana and symbols of the top the same way, with `weight` (they differ only in
  ///    kanji: 西換気 / 西神吉, not 晩ご飯 / 晩ごはん, whose choice is a matter of style the model knows better);
  /// 2. that one against the texts of `proposals` (`propose`'s, scored by the model), whatever their kana, with
  ///    `proposalWeight` (default `weight`).
  /// A text Mozc cannot produce (a kanji reading missing from the dictionary, rendaku: 試合 = じあい) counts as the
  /// cheapest producible one of its round, i.e. the dictionary has no say. The other texts keep their order.
  public func rerank(
    _ texts: [String], scores: [Double], reading: String, weight: Double, proposals: [String] = [],
    proposalWeight: Double? = nil
  ) -> [String] {
    guard texts.count > 1, texts.count == scores.count, let top = texts.first else { return texts }
    let skeleton = Self.kanaSkeleton(top)
    var best = choose(
      texts.indices.filter { $0 == 0 || Self.kanaSkeleton(texts[$0]) == skeleton }, texts, scores, reading, weight)
    let proposed = texts.indices.filter { $0 != best && proposals.contains(texts[$0]) }
    if !proposed.isEmpty {
      best = choose([best] + proposed, texts, scores, reading, proposalWeight ?? weight)
    }
    guard best != 0 else { return texts }
    return [texts[best]] + texts.enumerated().filter { $0.offset != best }.map(\.element)
  }

  /// The index among `indices` (the first: the incumbent) of the best model score + weight × (-cost / 500).
  private func choose(_ indices: [Int], _ texts: [String], _ scores: [Double], _ reading: String, _ weight: Double)
    -> Int
  {
    guard weight > 0, indices.count > 1 else { return indices[0] }
    let costs = indices.map { cost(texts[$0], reading: reading) }
    guard let cheapest = costs.compactMap({ $0 }).min() else { return indices[0] }
    var best = indices[0]
    var bestScore = -Double.infinity
    for (k, i) in indices.enumerated() {
      let combined = scores[i] - weight * Double(costs[k] ?? cheapest) / Self.costPerNat
      if combined > bestScore {
        bestScore = combined
        best = i
      }
    }
    return best
  }

  /// Texts for the model to score besides its own candidates `texts` (best first) for `reading` (hiragana): when the
  /// cheapest path through the dictionary has a proper noun with kanji the AI's top lacks, that path's text and the
  /// top with the proper nouns written for their kana (アザミヒラ → 莇平). They may be among `texts` (the model may
  /// have the dictionary's text further down its list).
  public func propose(reading: String, texts: [String]) -> [String] {
    guard let top = texts.first, let path = bestPath(reading) else { return [] }
    let nouns = path.properNouns.filter {
      $0.surface.contains(where: AIReadingChecker.isKanji) && !top.contains($0.surface)
    }
    guard !nouns.isEmpty else { return [] }
    var substituted = top
    for n in nouns {
      for kana in [Japanese.hiraganaToKatakana(n.key), n.key] where substituted.contains(kana) {
        substituted = substituted.replacing(kana, with: n.surface)
      }
    }
    var out: [String] = []
    for t in [path.text, substituted] where t != top && !out.contains(t) {
      out.append(t)
    }
    return out
  }

  /// The cheapest path through the lattice of `reading` (system dictionary tokens + connection costs, uncovered
  /// characters as themselves at `pathGapCost`): its text and the proper nouns on it (surface, reading).
  public func bestPath(_ reading: String) -> (text: String, properNouns: [(surface: String, key: String)])? {
    let r = Array(reading)
    let m = r.count
    guard m > 0 else { return nil }
    struct Back {
      var from: Int
      var rid: UInt16
      var value: String
      var key: String
      var properNoun: Bool
    }
    // best[j]: right id of the last token → (cost, back pointer), for reading[..<j]
    var best = [[UInt16: (cost: Int, back: Back?)]](repeating: [:], count: m + 1)
    best[0] = [0: (0, nil)]
    for j in 0..<m {
      let states = best[j]
      guard !states.isEmpty else { continue }
      let collector = Collector()
      systemDictionary.lookupPrefix(String(r[j...]), callback: collector)
      func relax(_ to: Int, _ rid: UInt16, _ cost: Int, _ back: Back) {
        if let old = best[to][rid], old.cost <= cost { return }
        best[to][rid] = (cost, back)
      }
      for w in collector.words where w.keyLength > 0 && j + w.keyLength <= m {
        let key = String(r[j..<(j + w.keyLength)])
        for (rid, c) in states {
          relax(
            j + w.keyLength, w.rid, c.cost + connector.getTransitionCost(rid, w.lid) + w.cost,
            Back(from: j, rid: rid, value: String(w.value), key: key, properNoun: posMatcher.isUniqueNoun(w.lid)))
        }
      }
      // a character no token covers, as itself (keeps the right id: a gap, not a word)
      for (rid, c) in states {
        relax(
          j + 1, rid, c.cost + Self.pathGapCost,
          Back(from: j, rid: rid, value: String(r[j]), key: String(r[j]), properNoun: false))
      }
    }
    guard
      let end = best[m].min(by: {
        $0.value.cost + connector.getTransitionCost($0.key, 0) < $1.value.cost + connector.getTransitionCost($1.key, 0)
      })
    else {
      return nil
    }
    var pieces: [Back] = []
    var j = m
    var rid = end.key
    while j > 0, let back = best[j][rid]?.back {
      pieces.append(back)
      j = back.from
      rid = back.rid
    }
    pieces.reverse()
    return (
      pieces.map(\.value).joined(),
      pieces.filter(\.properNoun).map { (surface: $0.value, key: $0.key) }
    )
  }

  /// The text without its kanji ("西換気に行って" → "に って" without the space).
  static func kanaSkeleton(_ text: String) -> String {
    String(text.filter { !AIReadingChecker.isKanji($0) })
  }

  struct Word {
    let keyLength: Int
    let value: [Character]
    let lid: UInt16
    let rid: UInt16
    let cost: Int
  }

  final class Collector: DictionaryCallback {
    var words: [Word] = []
    func onKey(_ key: String) -> DictionaryCallbackResult { .traverseContinue }
    func onActualKey(_ key: String, _ actualKey: String, _ numExpanded: Int) -> DictionaryCallbackResult {
      .traverseContinue
    }
    func onToken(_ key: String, _ expandedKey: String, _ token: Token) -> DictionaryCallbackResult {
      words.append(
        Word(keyLength: token.key.count, value: Array(token.value), lid: token.lid, rid: token.rid, cost: token.cost))
      return .traverseContinue
    }
    func isKanaModifierInsensitiveConversion() -> Bool { false }
  }

  private func compute(_ t: [Character], reading r: [Character]) -> Int? {
    let n = t.count
    let m = r.count
    guard n > 0, m > 0 else { return nil }
    // best[i][j]: right id of the last token → cost, for text[..<i] read as reading[..<j]
    var best = [[UInt16: Int]](repeating: [:], count: (n + 1) * (m + 1))
    best[0] = [0: 0]
    var words: [Int: [Word]] = [:]
    func wordsAt(_ j: Int) -> [Word] {
      if let w = words[j] { return w }
      let collector = Collector()
      systemDictionary.lookupPrefix(String(r[j...]), callback: collector)
      words[j] = collector.words
      return collector.words
    }
    func relax(_ i: Int, _ j: Int, _ rid: UInt16, _ cost: Int) {
      let k = i * (m + 1) + j
      if let old = best[k][rid], old <= cost { return }
      best[k][rid] = cost
    }
    for i in 0..<n {
      for j in 0..<m {
        let states = best[i * (m + 1) + j]
        guard !states.isEmpty else { continue }
        for w in wordsAt(j)
        where !w.value.isEmpty && i + w.value.count <= n
          && t[i..<(i + w.value.count)].elementsEqual(w.value)
        {
          for (rid, c) in states {
            relax(i + w.value.count, j + w.keyLength, w.rid, c + connector.getTransitionCost(rid, w.lid) + w.cost)
          }
        }
        // a character read as itself (katakana as hiragana); digits / Latin runs as 1...8 reading characters
        let ch = t[i]
        if Self.hiragana(ch) == r[j] {
          for (rid, c) in states { relax(i + 1, j + 1, rid, c + Self.unknownCost) }
        } else if ch.isNumber || (ch.isLetter && ch.isASCII) {
          for k in 1...8 where j + k <= m {
            for (rid, c) in states { relax(i + 1, j + k, rid, c + Self.unknownCost) }
          }
        }
      }
    }
    let end = best[n * (m + 1) + m]
    return end.map { $0.value + connector.getTransitionCost($0.key, 0) }.min()
  }

  /// Katakana → hiragana (other characters unchanged).
  static func hiragana(_ c: Character) -> Character {
    guard c.unicodeScalars.count == 1, let u = c.unicodeScalars.first, (0x30A1...0x30F6).contains(u.value),
      let h = Unicode.Scalar(u.value - 0x60)
    else { return c }
    return Character(h)
  }
}
