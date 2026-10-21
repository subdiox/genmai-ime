// Port of mozc/src/request/request_test_util_test.cc (3.35.6354).

import GenmaiProtocol
import Testing

@testable import GenmaiCore

@Suite struct RequestTestUtilTest {
  @Test func checkFillMobileRequest() {
    var request = Genmai_Commands_Request()
    RequestTestUtil.fillMobileRequest(&request)
    #expect(request.zeroQuerySuggestion)
    #expect(request.mixedConversion)
    #expect(!request.updateInputModeFromSurroundingText)
    #expect(request.autoPartialSuggestion)
    #expect(request.specialRomanjiTable == .toggleFlickToHiragana)
  }

  @Test func checkFillMobileRequestWithHardwareKeyboard() {
    var request = Genmai_Commands_Request()
    RequestTestUtil.fillMobileRequestWithHardwareKeyboard(&request)
    #expect(!request.zeroQuerySuggestion)
    #expect(!request.mixedConversion)
    #expect(request.updateInputModeFromSurroundingText)
    #expect(!request.autoPartialSuggestion)
    #expect(request.candidatePageSize == 2)
    #expect(request.specialRomanjiTable == .toggleFlickToHiragana)
  }

  @Test func checkFillMobileRequestForHandwriting() {
    var request = Genmai_Commands_Request()
    RequestTestUtil.fillMobileRequestForHandwriting(&request)
    #expect(request.zeroQuerySuggestion)
    #expect(request.mixedConversion)
    #expect(!request.kanaModifierInsensitiveConversion)
    #expect(!request.autoPartialSuggestion)
  }
}
