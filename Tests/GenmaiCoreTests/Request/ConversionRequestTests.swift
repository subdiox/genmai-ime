// Port of mozc/src/request/conversion_request_test.cc (3.35.6354).
//
// CopyOrViewPtrTest is not ported: internal::copy_or_view_ptr is a C++
// lifetime helper with no Swift counterpart (all members are values).

import GenmaiProtocol
import Testing

@testable import GenmaiCore

@Suite(.scopedConfigEnvironment) struct ConversionRequestTest {
  @Test func setKeyTest() {
    let request = Genmai_Commands_Request()
    let config = Genmai_Config_Config()
    let table = Table()
    table.initializeWithRequestAndConfig(request, config)

    var composer = Composer(table, request, config)
    composer.setPreeditTextForTestOnly("query")

    // SetKey("") is ignored. The actual key is created from composer.
    let conversionRequest1 = ConversionRequestBuilder()
      .setConfigView(config)
      .setRequestView(request)
      .setComposer(composer)
      .setKey("")
      .build()
    #expect("query" == conversionRequest1.key())

    let conversionRequest2 = ConversionRequestBuilder()
      .setConfigView(config)
      .setRequestView(request)
      .setComposer(composer)
      .setKey("foo")
      .build()
    #expect("foo" == conversionRequest2.key())

    let conversionRequest3 =
      ConversionRequestBuilder()
      .setConversionRequestView(conversionRequest2)
      .build()
    #expect("foo" == conversionRequest3.key())
  }

  @Test func isZeroQuerySuggestionTest() {
    #expect(ConversionRequestBuilder().build().isZeroQuerySuggestion())
    #expect(!ConversionRequestBuilder().setKey("key").build().isZeroQuerySuggestion())
  }

  @Test func incognitoModeTest() {
    do {
      let convreq = ConversionRequestBuilder().build()
      #expect(!convreq.incognitoMode())
    }
    do {
      var config = Genmai_Config_Config()
      config.incognitoMode = true
      let convreq = ConversionRequestBuilder().setConfig(config).build()
      #expect(convreq.incognitoMode())
    }
    do {
      var request = Genmai_Commands_Request()
      request.isIncognitoMode = true
      let convreq = ConversionRequestBuilder().setRequest(request).build()
      #expect(convreq.incognitoMode())
    }
    do {
      var options = ConversionRequest.Options()
      options.incognitoMode = true
      let convreq = ConversionRequestBuilder().setOptions(options).build()
      #expect(convreq.incognitoMode())
    }
    do {
      var config = Genmai_Config_Config()
      config.incognitoMode = true
      var request = Genmai_Commands_Request()
      request.isIncognitoMode = false
      var options = ConversionRequest.Options()
      options.incognitoMode = false
      let convreq = ConversionRequestBuilder()
        .setConfig(config)
        .setRequest(request)
        .setOptions(options)
        .build()
      #expect(convreq.incognitoMode())
    }
    do {
      var config = Genmai_Config_Config()
      config.incognitoMode = false
      var request = Genmai_Commands_Request()
      request.isIncognitoMode = true
      var options = ConversionRequest.Options()
      options.incognitoMode = false
      let convreq = ConversionRequestBuilder()
        .setConfig(config)
        .setRequest(request)
        .setOptions(options)
        .build()
      #expect(convreq.incognitoMode())
    }
    do {
      var config = Genmai_Config_Config()
      config.incognitoMode = false
      var request = Genmai_Commands_Request()
      request.isIncognitoMode = false
      var options = ConversionRequest.Options()
      options.incognitoMode = true
      let convreq = ConversionRequestBuilder()
        .setConfig(config)
        .setRequest(request)
        .setOptions(options)
        .build()
      #expect(convreq.incognitoMode())
    }
  }

  @Test func getSurroundingContextTest() {
    do {
      var context = Genmai_Commands_Context()
      context.precedingText = "line1\nline2 ａｂｃ "
      context.followingText = " ｄｅｆ\r\nline4"
      let convreq = ConversionRequestBuilder().setContext(context).build()
      let (left, right) = convreq.getSurroundingContext()
      #expect(left == "line2 abc")
      #expect(right == "def")
    }
    do {
      let convreq = ConversionRequestBuilder().build()
      let (left, right) = convreq.getSurroundingContext()
      #expect(left.isEmpty)
      #expect(right.isEmpty)
    }
  }
}
