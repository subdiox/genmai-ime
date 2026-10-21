// Port of mozc/src/base/url_test.cc (3.35.6354).

import Testing

@testable import GenmaiBase

private let kSurveyBaseUrl = "http://www.google.com/support/ime/japanese/bin/request.py"

private func findEncodedParam(_ params: [String], _ key: String, _ value: String) -> Bool {
  params.contains(key + "=" + Url.encodeUrl(value))
}

private func parseUrl(_ url: String) -> (baseUrl: String, params: [String])? {
  let urlAndParams = url.split(separator: "?", omittingEmptySubsequences: false)
  if urlAndParams.count != 2 {
    return nil
  }
  return (
    String(urlAndParams[0]),
    urlAndParams[1].split(separator: "&", omittingEmptySubsequences: false).map(String.init)
  )
}

@Suite struct UrlTests {
  @Test func uninstallationSurveyUrl() throws {
    let url = Url.getUninstallationSurveyUrl("0.1.2.3")
    let parsed = try #require(parseUrl(url), "Unexpected URL format: \(url)")
    #expect(parsed.baseUrl == kSurveyBaseUrl)
    #expect(parsed.params.count == 4)
    #expect(findEncodedParam(parsed.params, "contact_type", "surveyime"))
    #expect(findEncodedParam(parsed.params, "hl", "jp"))
    #expect(findEncodedParam(parsed.params, "format", "inproduct"))
    #expect(findEncodedParam(parsed.params, "version", "0.1.2.3"))
  }

  @Test func uninstallationSurveyUrlWithNoVersion() throws {
    let url = Url.getUninstallationSurveyUrl("")
    let parsed = try #require(parseUrl(url), "Unexpected URL format: \(url)")
    #expect(parsed.baseUrl == kSurveyBaseUrl)
    #expect(parsed.params.count == 3)
    #expect(findEncodedParam(parsed.params, "contact_type", "surveyime"))
    #expect(findEncodedParam(parsed.params, "hl", "jp"))
    #expect(findEncodedParam(parsed.params, "format", "inproduct"))
  }

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
