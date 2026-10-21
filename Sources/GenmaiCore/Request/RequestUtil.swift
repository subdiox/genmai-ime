// Port of mozc/src/request/request_util.h (3.35.6354).

import GenmaiProtocol

/// mozc::request_util
public enum RequestUtil {
  public static func isHandwriting(_ conversionRequest: ConversionRequest) -> Bool {
    conversionRequest.request().isHandwriting
      || !conversionRequest.composer().getHandwritingCompositions().isEmpty
  }

  public static func isAutoPartialSuggestionEnabled(_ conversionRequest: ConversionRequest) -> Bool {
    conversionRequest.request().autoPartialSuggestion
  }

  public static func shouldFilterNoisyNumberCandidate(_ options: ConversionOptions) -> Bool {
    options.createPartialCandidates
  }

  public static func shouldFilterNoisyNumberCandidate(_ conversionRequest: ConversionRequest) -> Bool {
    shouldFilterNoisyNumberCandidate(conversionRequest.options())
  }

  public static func isLatinInputMode(_ conversionRequest: ConversionRequest) -> Bool {
    let inputMode = conversionRequest.composer().getInputMode()
    return inputMode == .halfAscii || inputMode == .fullAscii
  }
}
