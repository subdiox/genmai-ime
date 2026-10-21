// Port of mozc/src/composer/mode_switching_handler_test.cc (3.35.6354).

import Testing

@testable import GenmaiCore

private func ruleEq(
  _ displayMode: ModeSwitchingHandler.ModeSwitching, _ inputMode: ModeSwitchingHandler.ModeSwitching
) -> ModeSwitchingHandler.Rule {
  ModeSwitchingHandler.Rule(displayMode: displayMode, inputMode: inputMode)
}

@Suite struct ModeSwitchingHandlerTest {
  @Test func getModeSwitchingRule() {
    #expect(
      ModeSwitchingHandler.getModeSwitchingRule("google")
        == ruleEq(.preferredAlphanumeric, .revertToPreviousMode))

    #expect(
      ModeSwitchingHandler.getModeSwitchingRule("Google")
        == ruleEq(.preferredAlphanumeric, .revertToPreviousMode))

    #expect(
      ModeSwitchingHandler.getModeSwitchingRule("Chrome")
        == ruleEq(.preferredAlphanumeric, .revertToPreviousMode))

    #expect(
      ModeSwitchingHandler.getModeSwitchingRule("chrome")
        == ruleEq(.preferredAlphanumeric, .revertToPreviousMode))

    #expect(
      ModeSwitchingHandler.getModeSwitchingRule("Android")
        == ruleEq(.preferredAlphanumeric, .revertToPreviousMode))

    #expect(
      ModeSwitchingHandler.getModeSwitchingRule("android")
        == ruleEq(.preferredAlphanumeric, .revertToPreviousMode))

    #expect(
      ModeSwitchingHandler.getModeSwitchingRule("http")
        == ruleEq(.halfAlphanumeric, .halfAlphanumeric))

    #expect(
      ModeSwitchingHandler.getModeSwitchingRule("www.")
        == ruleEq(.halfAlphanumeric, .halfAlphanumeric))

    #expect(
      ModeSwitchingHandler.getModeSwitchingRule("\\\\")
        == ruleEq(.halfAlphanumeric, .halfAlphanumeric))

    #expect(
      ModeSwitchingHandler.getModeSwitchingRule("C:\\")
        == ruleEq(.halfAlphanumeric, .halfAlphanumeric))

    // Normal text should return NO_CHANGE.
    #expect(ModeSwitchingHandler.getModeSwitchingRule("foobar") == ruleEq(.noChange, .noChange))
  }

  @Test func isDriveLetter() {
    #expect(ModeSwitchingHandler.isDriveLetter("C:\\"))
    #expect(ModeSwitchingHandler.isDriveLetter("c:\\"))
    #expect(!ModeSwitchingHandler.isDriveLetter("C:"))
    #expect(!ModeSwitchingHandler.isDriveLetter("6:\\"))
  }
}
