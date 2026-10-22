// Test doubles for the input controller tests (MockClient / ClientMock / MockRenderer of
// mozc_imk_input_controller_test.mm).

import AppKit
import GenmaiClient
import GenmaiProtocol
import GenmaiRenderer

@testable import GenmaiMac

/// MockClient of mozc_imk_input_controller_test.mm (the IMKTextInput side).
@MainActor
final class MockTextInputClient: TextInputClient {
  var bundleID: String? = "com.google.exampleBundle"
  var expectedCursor = NSRect.zero
  var expectedRange = NSRange(location: NSNotFound, length: NSNotFound)
  var expectedAttributes: [AnyHashable: Any]?
  private(set) var selectedMode = ""
  private(set) var insertedText: String?
  private(set) var overriddenLayout: String?
  private(set) var markedText: NSAttributedString?
  var attributedString = NSAttributedString()
  private var counters: [String: Int] = [:]

  func getCounter(_ selector: String) -> Int { counters[selector, default: 0] }

  func bundleIdentifier() -> String? { bundleID }

  func attributes(forCharacterIndex index: Int, lineHeightRectangle: inout NSRect) -> [AnyHashable: Any]? {
    counters["attributesForCharacterIndex:lineHeightRectangle:", default: 0] += 1
    lineHeightRectangle = expectedCursor
    return expectedAttributes
  }

  func selectedRange() -> NSRange {
    counters["selectedRange", default: 0] += 1
    return expectedRange
  }

  func markedRange() -> NSRange {
    counters["markedRange", default: 0] += 1
    return expectedRange
  }

  func selectInputMode(_ modeIdentifier: String) {
    counters["selectInputMode:", default: 0] += 1
    selectedMode = modeIdentifier
  }

  func length() -> Int { attributedString.length }

  func attributedSubstring(from range: NSRange) -> NSAttributedString? {
    attributedString.attributedSubstring(from: range)
  }

  func setMarkedText(_ text: NSAttributedString, selectionRange: NSRange, replacementRange: NSRange) {
    markedText = NSAttributedString(attributedString: text)
  }

  func insertText(_ text: String, replacementRange: NSRange) {
    counters["insertText:replacementRange:", default: 0] += 1
    insertedText = text
  }

  func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String) {
    counters["overrideKeyboardWithKeyboardNamed:", default: 0] += 1
    overriddenLayout = keyboardUniqueName
  }
}

/// client::ClientMock. Unexpected calls return nil (gmock's default `false`).
@MainActor
final class MockGenmaiClient: GenmaiClientProtocol {
  var sendKeyCalls: [(key: KeyEvent, context: Context?)] = []
  var sendCommandCalls: [(command: SessionCommand, context: Context?)] = []
  var sendKeyHandler: (KeyEvent) -> Output? = { _ in nil }
  var sendCommandHandler: (SessionCommand) -> Output? = { _ in nil }
  var config: Config?
  var capability: Capability?
  var directModeKeys: [KeyEvent] = []

  func isValidRunLevel() -> Bool { true }
  func ensureConnection() -> Bool { true }
  func ensureSession() -> Bool { true }
  func checkVersionOrRestartServer() -> Bool { true }

  func sendKey(_ key: KeyEvent, context: Context?) -> Output? {
    sendKeyCalls.append((key, context))
    return sendKeyHandler(key)
  }

  func testSendKey(_ key: KeyEvent, context: Context?) -> Output? { nil }

  func sendCommand(_ command: SessionCommand, context: Context?) -> Output? {
    sendCommandCalls.append((command, context))
    return sendCommandHandler(command)
  }

  func isDirectModeCommand(_ key: KeyEvent) -> Bool { directModeKeys.contains(key) }
  func getConfig() -> Config? { config }
  func setConfig(_ config: Config) -> Bool {
    self.config = config
    return true
  }
  func clearUserHistory() -> Bool { true }
  func clearUserPrediction() -> Bool { true }
  func shutdown() -> Bool { true }
  func syncData() -> Bool { true }
  func reload() -> Bool { true }
  func cleanup() -> Bool { true }
  func reset() {}
  func pingServer() -> Bool { true }
  func noOperation() -> Bool { true }
  func enableCascadingWindow(_ enable: Bool) {}
  func setSuppressErrorDialog(_ suppress: Bool) {}
  func setClientCapability(_ capability: Capability) { self.capability = capability }
  func openApp(mode: String, extraArg: String) -> Bool { true }
  func openAppWithProtoBuf(_ output: Output) -> Bool { true }
  func openBrowser(_ url: String) -> Bool { true }
}

@MainActor
final class MockRenderer: RendererInterface {
  private(set) var activateCounter = 0
  private(set) var isAvailableCounter = 0
  private(set) var execCommandCounter = 0
  private(set) var calledCommand = RendererCommand()

  func activate() -> Bool {
    activateCounter += 1
    return true
  }

  func isAvailable() -> Bool {
    isAvailableCounter += 1
    return true
  }

  func execCommand(_ command: RendererCommand) -> Bool {
    execCommandCounter += 1
    calledCommand = command
    return true
  }
}

@MainActor
final class MockAppLauncher: AppLauncher {
  var launches: [(mode: String, environment: [String: String])] = []
  func openApp(mode: String, extraArg: String, environment: [String: String]) -> Bool {
    launches.append((mode, environment))
    return true
  }
}
