// Port of mozc/src/composer/special_key_test.cc (3.35.6354).

import Testing

@testable import GenmaiCore

@Suite struct SpecialKeyTest {
  @Test func trimLeadingpecialKey() {
    let table = Table()
    var input = table.parseSpecialKey("{!}ab")
    #expect(trimLeadingSpecialKey(input) == "ab")

    input = table.parseSpecialKey("{!}{?}ab")
    #expect(trimLeadingSpecialKey(input) == table.parseSpecialKey("{?}ab")[...])

    input = table.parseSpecialKey("a{!}b")
    #expect(trimLeadingSpecialKey(input) == input[...])

    // Invalid patterns
    //   "\u000F" = parsed-"{"
    //   "\u000E" = parsed-"}"
    input = "\u{000F}ab"  // "{ab"
    #expect(trimLeadingSpecialKey(input) == input[...])
    input = "ab\u{000E}"  // "ab}"
    #expect(trimLeadingSpecialKey(input) == input[...])
    input = "\u{000F}\u{000F}ab\u{000E}"  // "{{ab}"
    #expect(trimLeadingSpecialKey(input).isEmpty)
    input = "\u{000F}ab\u{000E}\u{000E}"  // "{ab}}"
    #expect(trimLeadingSpecialKey(input) == "\u{000E}")
  }
}
