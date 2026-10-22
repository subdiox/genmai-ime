// Port of mozc/src/prediction/english_decoder.{h,cc} (3.35.6354).

import GenmaiBase

public final class EnglishDecoder {
  private let modules: any PredictionModules
  private let dictionary: any DictionaryInterface
  private let zipCodeId: UInt16
  private let unknownId: UInt16

  public init(_ modules: any PredictionModules) {
    self.modules = modules
    dictionary = modules.getDictionary()
    zipCodeId = modules.getPosMatcher().getZipcodeId()
    unknownId = modules.getPosMatcher().getUnknownId()
  }

  /// Decodes English predictive results using query key.
  public func decode(_ request: ConversionRequest) -> [PredictionResult] {
    if request.requestType() == .conversion || request.key().isEmpty {
      return []
    }
    var results: [PredictionResult] = []
    let cutoff = DecoderUtil.getCandidateCutoffThreshold(request.requestType())
    getPredictiveResultsForEnglishKey(request, request.key(), cutoff, &results)
    modules.predictionSupplementalModel().decodeEnglish(request, &results)
    return results
  }

  /// Decodes English predictive results using raw input string from composer.
  public func decodeUsingRawInput(_ request: ConversionRequest) -> [PredictionResult] {
    if request.requestType() == .conversion || request.composer().getRawString().isEmpty {
      return []
    }
    var results: [PredictionResult] = []
    let cutoff = DecoderUtil.getCandidateCutoffThreshold(request.requestType())
    getPredictiveResultsForEnglishKey(request, request.composer().getRawString(), cutoff, &results)
    modules.predictionSupplementalModel().decodeEnglish(request, &results)
    return results
  }

  /// Performs a custom look up for English words where case-conversion might
  /// be applied to lookup key and/or output results.
  private func getPredictiveResultsForEnglishKey(
    _ request: ConversionRequest, _ requestKey: String, _ lookupLimit: Int,
    _ results: inout [PredictionResult]
  ) {
    let prevResultsSize = results.count
    if Util.isUpperAscii(requestKey) {
      // For upper case key, look up its lower case version and then transform
      // the results to upper case.
      var key = requestKey
      Util.lowerString(&key)
      let callback = PredictiveLookupCallback(
        Attribute.english, lookupLimit, key.utf8.count, Int(zipCodeId), Int(unknownId))
      swap(&callback.results, &results)
      dictionary.lookupPredictive(key, options: request.options(), callback: callback)
      swap(&callback.results, &results)
      for i in prevResultsSize..<results.count {
        Util.upperString(&results[i].value)
      }
    } else if Util.isCapitalizedAscii(requestKey) {
      // For capitalized key, look up its lower case version and then
      // transform the results to capital.
      var key = requestKey
      Util.lowerString(&key)
      let callback = PredictiveLookupCallback(
        Attribute.english, lookupLimit, key.utf8.count, Int(zipCodeId), Int(unknownId))
      swap(&callback.results, &results)
      dictionary.lookupPredictive(key, options: request.options(), callback: callback)
      swap(&callback.results, &results)
      for i in prevResultsSize..<results.count {
        Util.capitalizeString(&results[i].value)
      }
    } else {
      // For other cases (lower and as-is), just look up directly.
      let callback = PredictiveLookupCallback(
        Attribute.english, lookupLimit, requestKey.utf8.count, Int(zipCodeId), Int(unknownId))
      swap(&callback.results, &results)
      dictionary.lookupPredictive(requestKey, options: request.options(), callback: callback)
      swap(&callback.results, &results)
    }
    // If input mode is FULL_ASCII, then convert the results to full-width.
    if request.composer().getInputMode() == .fullAscii {
      for i in prevResultsSize..<results.count {
        results[i].value = Japanese.halfWidthAsciiToFullWidthAscii(results[i].value)
      }
    }
  }
}
