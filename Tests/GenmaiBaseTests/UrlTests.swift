// Port of mozc/src/base/url_test.cc (3.35.6354).

import Testing

@testable import GenmaiBase

@Suite struct UrlTests {
  @Test func encodeUri() {
    #expect(Url.encodeUrl("もずく") == "%E3%82%82%E3%81%9A%E3%81%8F")
    #expect(Url.encodeUrl("mozc") == "mozc")
    #expect(
      Url.encodeUrl("http://mozc/?q=Hello World") == "http%3A%2F%2Fmozc%2F%3Fq%3DHello%20World")
  }

  @Test func decodeUri() {
    #expect(Url.decodeUrl("%E3%82%82%E3%81%9A%E3%81%8F") == "もずく")
    #expect(Url.decodeUrl("mozc") == "mozc")
    #expect(Url.decodeUrl("http%3A%2F%2Fmozc%2F%3Fq%3DHello+World") == "http://mozc/?q=Hello World")
  }
}
