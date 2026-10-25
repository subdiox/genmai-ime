// The words the user committed, as a dictionary for `AIDictionaryScorer` (not part of Mozc): a name the AI got wrong
// and the user converted once (picked from the candidates) is proposed to the AI conversion from then on, like a
// user dictionary word.
//
// The words come from Mozc's prediction history (`UserHistoryStorage`, the learning data; thread-safe), so they follow
// its rules: nothing is learned where Mozc learns nothing (incognito, password fields, history learning off), and
// clearing the history clears them. The entries with a kanji and a reading of `keyLengths` characters are copied
// into a reading → surfaces map, again at most every `refreshInterval` (or after `invalidate`).

import Foundation
import GenmaiCore
import Synchronization

public final class AILearnedWords: DictionaryInterface {
  static let refreshInterval: Duration = .seconds(30)
  /// Readings of words and short phrases (longer entries are whole sentences committed before).
  static let keyLengths = 2...12
  /// The cost of a learned word (like a common word of the system dictionary).
  static let cost = 5000

  private struct Snapshot {
    var words: [String: [String]] = [:]
    var built: ContinuousClock.Instant?
    /// Changes whenever the words are copied again (`AIDictionaryScorer` drops its cached costs).
    var generation = 0
  }

  private let storage: UserHistoryStorage
  private let posID: UInt16
  private let snapshot = Mutex(Snapshot())

  /// `posID`: the left / right id of the learned words (a general noun).
  public init(storage: UserHistoryStorage, posID: UInt16) {
    self.storage = storage
    self.posID = posID
  }

  /// The history may have changed (cleared, reloaded): the words are copied again at the next lookup.
  public func invalidate() {
    snapshot.withLock { $0.built = nil }
  }

  /// The current snapshot's generation (copies the words first if they are due).
  public var generation: Int { current().generation }

  public func lookupPrefix(_ key: String, callback: any DictionaryCallback) {
    let words = current().words
    let chars = Array(key)
    for length in Self.keyLengths where length <= chars.count {
      let prefix = String(chars[..<length])
      for value in words[prefix] ?? [] {
        let token = Token(
          key: prefix, value: value, cost: Self.cost, lid: posID, rid: posID, attributes: Token.Attribute.userDictionary
        )
        if callback.onToken(prefix, prefix, token) == .traverseDone { return }
      }
    }
  }

  public func lookupPrefix(_ key: String, options: ConversionOptions, callback: any DictionaryCallback) {
    lookupPrefix(key, callback: callback)
  }

  private func current() -> Snapshot {
    let now = ContinuousClock.now
    if let s = snapshot.withLock({ s in s.built.map { now - $0 < Self.refreshInterval } == true ? s : nil }) {
      return s
    }
    var words: [String: [String]] = [:]
    storage.forEachEntry { _, entry in
      let key = entry.key
      let value = entry.value
      if !entry.removed, Self.keyLengths.contains(key.count), value.contains(where: AIReadingChecker.isKanji),
        !(words[key]?.contains(value) ?? false)
      {
        words[key, default: []].append(value)
      }
      return true
    }
    return snapshot.withLock { s in
      s.words = words
      s.built = now
      s.generation += 1
      return s
    }
  }
}
