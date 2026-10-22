// Port of mozc/src/prediction/handwriting_decoder.{h,cc} (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiProtocol

public final class HandwritingDecoder {
  public struct HandwritingQueryInfo: Sendable, Equatable {
    public var query = ""
    public var constraints: [String] = []
    public init() {}
  }

  private let dictionary: any DictionaryInterface
  private let realtimeDecoder: RealtimeDecoder

  public init(_ modules: any PredictionModules, _ realtimeDecoder: RealtimeDecoder) {
    dictionary = modules.getDictionary()
    self.realtimeDecoder = realtimeDecoder
  }

  /// `std::string::find(needle, from)` on UTF-8 bytes.
  private static func byteFind(_ haystack: [UInt8], _ needle: [UInt8], _ from: Int) -> Int? {
    if needle.isEmpty {
      return from <= haystack.count ? from : nil
    }
    if needle.count > haystack.count {
      return nil
    }
    var i = from
    while i + needle.count <= haystack.count {
      if haystack[i] == needle[0] && haystack[i..<(i + needle.count)].elementsEqual(needle) {
        return i
      }
      i += 1
    }
    return nil
  }

  /// Decodes handwriting candidates for the given request.
  public func decode(_ request: ConversionRequest) -> [PredictionResult] {
    if !RequestUtil.isHandwriting(request) {
      return []
    }
    if request.requestType() != .prediction && request.requestType() != .suggestion {
      return []
    }

    var results: [PredictionResult] = []
    let adjuster = ResultsSizeAdjuster(request, results)
    defer { adjuster.adjustSize(&results) }

    let param = request.request().decoderExperimentParams
    let handwritingCostOffset = Int(param.handwritingConversionCandidateCostOffset)

    var processedCount = 0
    let sizeToProcess = Int(param.maxCompositionEventToProcess)
    let compositionEvents = request.composer().getHandwritingCompositions()
    for i in 0..<compositionEvents.count {
      let elm = compositionEvents[i]
      if elm.probability <= 0.0 {
        continue
      }
      let recognitionCost = Int(-500.0 * Foundation.log(elm.probability))
      let kAsisCostOffset = 3453  // 500 * log(1000) = ~3453
      var asisResult = PredictionResult()
      asisResult.key = elm.compositionString
      asisResult.value = elm.compositionString
      asisResult.attributes =
        (Attribute.unigram | Attribute.noVariantsExpansion | Attribute.noExtraDescription
          | Attribute.noModification)
      // Set small cost for the top recognition result.
      asisResult.wcost = (i == 0) ? 0 : kAsisCostOffset + recognitionCost

      let queryInfo: HandwritingQueryInfo? =
        processedCount < sizeToProcess ? generateQueryForHandwriting(request, elm) : nil
      if let queryInfo {
        processedCount += 1

        let constraints = queryInfo.constraints.map { Array($0.utf8) }
        let cb = InlineCallback().onToken { _, _, token in
          let penalty = handwritingCostOffset + recognitionCost
          var nextPos = 0
          let valueBytes = Array(token.value.utf8)
          for constraint in constraints {
            guard let pos = Self.byteFind(valueBytes, constraint, nextPos) else {
              return .traverseContinue
            }
            nextPos = pos + 1
          }
          var result = PredictionResult()
          result.initializeByTokenAndTypes(token, Attribute.unigram)
          result.wcost += penalty
          results.append(result)
          return (results.count < adjuster.cutoffThreshold) ? .traverseContinue : .traverseDone
        }

        dictionary.lookupExact(queryInfo.query, options: request.options(), callback: cb)

        // Rewrite key with the look-up query.
        asisResult.key = queryInfo.query
      }
      results.append(asisResult)
    }

    return results
  }

  /// Generates `HandwritingQueryInfo` for the given composition event.
  public func generateQueryForHandwriting(
    _ request: ConversionRequest,
    _ compositionEvent: Genmai_Commands_SessionCommand.CompositionEvent
  ) -> HandwritingQueryInfo? {
    if compositionEvent.probability < 0.0001 {
      // Skip generating the query info for unconfident composition,
      // since running reverse conversion is slow.
      return nil
    }
    if compositionEvent.compositionString.utf8.contains(0x20) {
      // Skip providing converted candidates for queries including white
      // space.
      return nil
    }
    if !Util.containsScriptType(compositionEvent.compositionString, .hiragana) {
      // Skip providing converted candidates for queries not including
      // Hiragana.
      return nil
    }

    let requestForRealtime = ConversionRequestBuilder()
      .setConversionRequestView(request)
      .setRequestType(.reverseConversion)
      .setKey(compositionEvent.compositionString)
      .build()

    var info = HandwritingQueryInfo()
    let results = realtimeDecoder.reverseDecode(requestForRealtime)
    guard let result = results.first else {
      return info
    }

    info.query = result.value

    // b/324976556:
    // We have to use the segment key instead of the candidate key.
    // candidate key does not always match segment key for T13N chars.
    var utf8Str = ""
    for c in result.key.unicodeScalars {
      if Util.getScriptType(String(c)) != .hiragana {
        utf8Str.unicodeScalars.append(c)
      } else if !utf8Str.isEmpty {
        info.constraints.append(utf8Str)
        utf8Str = ""
      }
    }
    if !utf8Str.isEmpty {
      info.constraints.append(utf8Str)
    }

    return info
  }
}
