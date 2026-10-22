// Port of mozc/src/prediction/single_kanji_decoder.{h,cc} (3.35.6354).
//
// Deviation from C++: `Decode` is `open` (virtual in C++) so that tests can
// subclass the decoder.

import GenmaiBase
import GenmaiProtocol

open class SingleKanjiDecoder {
  private let singleKanjiDictionary: any SingleKanjiDictionaryInterface
  private let generalSymbolId: UInt16

  public init(_ posMatcher: PosMatcher, _ singleKanjiDictionary: any SingleKanjiDictionaryInterface) {
    self.singleKanjiDictionary = singleKanjiDictionary
    generalSymbolId = posMatcher.getGeneralSymbolId()
  }

  private static func useSvs(_ request: ConversionRequest) -> Bool {
    request.request().decoderExperimentParams.variationCharacterTypes
      & UInt32(Genmai_Commands_DecoderExperimentParams.VariationCharacterType.svsJapanese.rawValue)
      != 0
  }

  private static func stripLastChar(_ key: inout String) {
    let keyLen = Util.charsLen(key)
    if keyLen <= 1 {
      key = ""
      return
    }
    key = String(Util.utf8SubString(key, 0, keyLen - 1))
  }

  open func decode(_ request: ConversionRequest) -> [PredictionResult] {
    var results: [PredictionResult] = []
    let kMinSingleKanjiSize = 5

    let useSvs = Self.useSvs(request)

    let originalRequestKey = request.composer().getQueryForPrediction()
    var offset = 0
    var key = originalRequestKey
    while !key.isEmpty {
      defer { Self.stripLastChar(&key) }
      if !RequestUtil.isAutoPartialSuggestionEnabled(request)
        && !key.bytesEqual(originalRequestKey)
      {
        // Do not include partial results
        break
      }
      let kanjiList = singleKanjiDictionary.lookupKanjiEntries(key, useSvs)
      if kanjiList.isEmpty {
        continue
      }
      appendResults(key, originalRequestKey, kanjiList, offset, &results)
      // Make sure that single kanji entries for shorter key should be
      // ranked lower than the entries for longer key.
      let kShorterKeyOffst = 3450  // 500 * log(1000)
      offset += kShorterKeyOffst
      if results.count > kMinSingleKanjiSize {
        break
      }
    }
    return results
  }

  private func appendResults(
    _ kanjiKey: String, _ originalRequestKey: String, _ kanjiList: [String], _ offset: Int,
    _ results: inout [PredictionResult]
  ) {
    for kanji in kanjiList {
      var result = PredictionResult()
      // Set the wcost to keep the `kanji_list` order.
      result.wcost = offset + results.count
      result.attributes |= Attribute.singleKanji
      result.key = kanjiKey
      result.value = kanji
      result.lid = generalSymbolId
      result.rid = generalSymbolId
      if kanjiKey.utf8.count < originalRequestKey.utf8.count {
        result.attributes |= Attribute.partiallyKeyConsumed
        result.consumedKeySize = UInt32(Util.charsLen(kanjiKey))
      }

      results.append(result)
    }
  }
}
