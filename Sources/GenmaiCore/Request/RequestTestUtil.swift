// Port of mozc/src/request/request_test_util.{h,cc} (3.35.6354).
//
// testonly in C++; kept in the library so that the tests of other modules
// (converter, prediction, rewriter, session, ...) can use it.

import GenmaiProtocol

/// mozc::request_test_util
public enum RequestTestUtil {
  public static func fillMobileRequest(_ request: inout Genmai_Commands_Request) {
    request.zeroQuerySuggestion = true
    request.mixedConversion = true
    request.updateInputModeFromSurroundingText = false
    request.specialRomanjiTable = .toggleFlickToHiragana
    request.kanaModifierInsensitiveConversion = true
    request.autoPartialSuggestion = true
    request.languageAwareInput = .noLanguageAwareInput
  }

  public static func fillMobileRequestWithHardwareKeyboard(_ request: inout Genmai_Commands_Request) {
    request.zeroQuerySuggestion = false
    request.mixedConversion = false
    request.updateInputModeFromSurroundingText = true
    request.specialRomanjiTable = .toggleFlickToHiragana
    request.kanaModifierInsensitiveConversion = true
    request.autoPartialSuggestion = false
    request.languageAwareInput = .noLanguageAwareInput
    request.candidatePageSize = 2
  }

  public static func fillMobileRequestForHandwriting(_ request: inout Genmai_Commands_Request) {
    request.zeroQuerySuggestion = true
    request.mixedConversion = true
    request.kanaModifierInsensitiveConversion = false
    request.autoPartialSuggestion = false
  }
}
