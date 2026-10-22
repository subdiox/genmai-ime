// Port of mozc/src/base/strings/strip_test.cc (3.35.6354).

import Testing

@testable import GenmaiBase

@Suite struct StripTest {
  @Test func stripWhitespace() {
    #expect(Strings.stripLeadingWhitespace("") == "")
    #expect(Strings.stripTrailingWhitespace("") == "")
    #expect(Strings.stripWhitespace("") == "")
    #expect(Strings.stripLeadingWhitespace(" 　(水) ") == "(水) ")
    #expect(Strings.stripTrailingWhitespace(" (水) 　") == " (水)")
    #expect(Strings.stripWhitespace(" 　(水) 　") == "(水)")
    #expect(Strings.stripWhitespace(" 　") == "")
  }
}
