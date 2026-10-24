// Dictionary hints for the genmai prompt (not part of Mozc): what Mozc's converter and dictionary offer for a
// reading. A model trained with them in its prompt can take the dictionary's spelling of words it does not know
// (日下部町, 西神吉) instead of inventing one, so that a better dictionary improves the AI conversion without
// retraining. The training data gets its hints from this code (`genmai-cli dict-hints`); the IME must compute them
// the same way.
//
// - `segments`: Mozc's conversion of the reading (the top candidate of each segment), with no user dictionary and no
//   learning.
// - `properNouns`: proper nouns of the system dictionary for a part of the reading that the conversion does not
//   contain: three or more reading characters, two or more characters with a kanji (single kanji are mostly given
//   names: 恭, 杏 for きょう), not inside the reading of a longer one (草壁 in 日下部町); longest reading first, then
//   cheapest; at most three.

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol

public struct AIDictionaryHints: Sendable, Equatable {
  public var segments: [String]
  public var properNouns: [String]

  public init(segments: [String], properNouns: [String]) {
    self.segments = segments
    self.properNouns = properNouns
  }
}

/// Not thread-safe (it owns a converter and a composer): one per task.
public final class AIDictionaryHinter {
  static let maxProperNouns = 3
  static let minProperNounKeyLength = 3

  private let converter: any ConverterInterface
  private let systemDictionary: SystemDictionary
  private let posMatcher: PosMatcher
  private let request = Genmai_Commands_Request()
  private let config = ConfigHandler.defaultConfig()
  private var composer: Composer
  private let segments = Segments()

  /// `engine` must be built on `dataManager` without a user profile that matters (its user dictionary and history
  /// would change the conversion).
  public init(engine: Engine, dataManager: DataManager) throws {
    converter = engine.getConverter()
    systemDictionary = try SystemDictionary.Builder(image: dataManager.getSystemDictionaryData()).build()
    posMatcher = PosMatcher(dataManager.getPosMatcherData())
    composer = Composer(request, config)
  }

  /// The hints for `reading` (hiragana; katakana is read as hiragana).
  public func hints(reading: String) -> AIDictionaryHints {
    let reading = String(reading.map(AIDictionaryScorer.hiragana))
    guard !reading.isEmpty else { return AIDictionaryHints(segments: [], properNouns: []) }
    let conversion = convert(reading)
    let text = conversion.joined()
    return AIDictionaryHints(segments: conversion, properNouns: properNouns(reading, excluding: text))
  }

  private func convert(_ reading: String) -> [String] {
    var options = ConversionOptions()
    options.requestType = .conversion
    options.useActualConverterForRealtimeConversion = true
    composer.reset()
    composer.setPreeditTextForTestOnly(reading)
    segments.clear()
    let conversionRequest = ConversionRequestBuilder()
      .setComposer(composer)
      .setRequestView(request)
      .setConfigView(config)
      .setOptions(options)
      .build()
    guard converter.startConversion(conversionRequest, segments) else { return [] }
    return segments.conversionSegments.compactMap { $0.candidatesSize > 0 ? $0.candidate(0).value : nil }
  }

  private func properNouns(_ reading: String, excluding text: String) -> [String] {
    let r = Array(reading)
    var all: [(start: Int, keyLength: Int, cost: Int, value: String)] = []
    for j in r.indices {
      let collector = AIDictionaryScorer.Collector()
      systemDictionary.lookupPrefix(String(r[j...]), callback: collector)
      for w in collector.words
      where w.keyLength >= Self.minProperNounKeyLength && posMatcher.isUniqueNoun(w.lid)
        && w.value.count >= 2 && w.value.contains(where: AIReadingChecker.isKanji)
      {
        all.append((j, w.keyLength, w.cost, String(w.value)))
      }
    }
    // a proper noun inside the reading of a longer one (草壁 in 日下部町) is not offered, nor one the conversion has
    let inLonger = { (a: (start: Int, keyLength: Int, cost: Int, value: String)) in
      all.contains {
        $0.keyLength > a.keyLength && $0.start <= a.start && a.start + a.keyLength <= $0.start + $0.keyLength
      }
    }
    var seen = Set<String>()
    var found = all.filter { !text.contains($0.value) && !inLonger($0) && seen.insert($0.value).inserted }
    found.sort {
      $0.keyLength != $1.keyLength
        ? $0.keyLength > $1.keyLength : $0.cost != $1.cost ? $0.cost < $1.cost : $0.value < $1.value
    }
    return found.prefix(Self.maxProperNouns).map(\.value)
  }
}
