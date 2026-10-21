// Port of mozc/src/dictionary/dictionary_mock.h (3.35.6354).
//
// The gmock classes become hand-written test doubles: every method can be
// overridden with a closure and records how often it was called.

import GenmaiProtocol
import Testing
import os

@testable import GenmaiCore

/// `MockDictionary`.
final class MockDictionary: DictionaryInterface, @unchecked Sendable {
  static let kDefaultCost = 0
  static let kDefaultPosId = 1

  var hasKeyHandler: ((String) -> Bool)?
  var hasValueHandler: ((String) -> Bool)?
  var lookupPredictiveHandler: ((String, ConversionOptions, any DictionaryCallback) -> Void)?
  var lookupPrefixHandler: ((String, ConversionOptions, any DictionaryCallback) -> Void)?
  var lookupExactHandler: ((String, ConversionOptions, any DictionaryCallback) -> Void)?
  var lookupReverseHandler: ((String, ConversionOptions, any DictionaryCallback) -> Void)?
  var lookupCommentHandler: ((String, String, ConversionOptions) -> String?)?
  private(set) var calls: [String: Int] = [:]

  private func record(_ name: String) { calls[name, default: 0] += 1 }

  func hasKey(_ key: String) -> Bool {
    record("HasKey")
    return hasKeyHandler?(key) ?? false
  }

  func hasValue(_ value: String) -> Bool {
    record("HasValue")
    return hasValueHandler?(value) ?? false
  }

  func lookupPredictive(_ key: String, callback: any DictionaryCallback) {
    lookupPredictive(key, options: ConversionOptions(), callback: callback)
  }

  func lookupPrefix(_ key: String, callback: any DictionaryCallback) {
    lookupPrefix(key, options: ConversionOptions(), callback: callback)
  }

  func lookupExact(_ key: String, callback: any DictionaryCallback) {
    lookupExact(key, options: ConversionOptions(), callback: callback)
  }

  func lookupReverse(_ str: String, callback: any DictionaryCallback) {
    lookupReverse(str, options: ConversionOptions(), callback: callback)
  }

  func lookupComment(_ key: String, _ value: String) -> String? {
    lookupComment(key, value, options: ConversionOptions())
  }

  func lookupPredictive(_ key: String, options: ConversionOptions, callback: any DictionaryCallback) {
    record("LookupPredictive")
    lookupPredictiveHandler?(key, options, callback)
  }

  func lookupPrefix(_ key: String, options: ConversionOptions, callback: any DictionaryCallback) {
    record("LookupPrefix")
    lookupPrefixHandler?(key, options, callback)
  }

  func lookupExact(_ key: String, options: ConversionOptions, callback: any DictionaryCallback) {
    record("LookupExact")
    lookupExactHandler?(key, options, callback)
  }

  func lookupReverse(_ str: String, options: ConversionOptions, callback: any DictionaryCallback) {
    record("LookupReverse")
    lookupReverseHandler?(str, options, callback)
  }

  func lookupComment(_ key: String, _ value: String, options: ConversionOptions) -> String? {
    record("LookupComment")
    return lookupCommentHandler?(key, value, options)
  }

  func populateReverseLookupCache(_ str: String) { record("PopulateReverseLookupCache") }
  func clearReverseLookupCache() { record("ClearReverseLookupCache") }
}

/// `MockUserDictionary`. Only the interface w/o ConversionOptions is used.
final class MockUserDictionary: UserDictionaryInterface, @unchecked Sendable {
  static let kDefaultCost = 0
  static let kDefaultPosId = 1

  var hasKeyHandler: ((String) -> Bool)?
  var hasValueHandler: ((String) -> Bool)?
  var lookupPredictiveHandler: ((String, any DictionaryCallback) -> Void)?
  var lookupPrefixHandler: ((String, any DictionaryCallback) -> Void)?
  var lookupExactHandler: ((String, any DictionaryCallback) -> Void)?
  var lookupReverseHandler: ((String, any DictionaryCallback) -> Void)?
  var lookupCommentHandler: ((String, String) -> String?)?
  var isSuppressedEntryHandler: ((String, String) -> Bool)?
  var hasSuppressedEntriesHandler: (() -> Bool)?
  var posList: [String] = []
  private(set) var calls: [String: Int] = [:]

  private func record(_ name: String) { calls[name, default: 0] += 1 }

  func hasKey(_ key: String) -> Bool {
    record("HasKey")
    return hasKeyHandler?(key) ?? false
  }

  func hasValue(_ value: String) -> Bool {
    record("HasValue")
    return hasValueHandler?(value) ?? false
  }

  func lookupPredictive(_ key: String, callback: any DictionaryCallback) {
    record("LookupPredictive")
    lookupPredictiveHandler?(key, callback)
  }

  func lookupPrefix(_ key: String, callback: any DictionaryCallback) {
    record("LookupPrefix")
    lookupPrefixHandler?(key, callback)
  }

  func lookupExact(_ key: String, callback: any DictionaryCallback) {
    record("LookupExact")
    lookupExactHandler?(key, callback)
  }

  func lookupReverse(_ str: String, callback: any DictionaryCallback) {
    record("LookupReverse")
    lookupReverseHandler?(str, callback)
  }

  func lookupComment(_ key: String, _ value: String) -> String? {
    record("LookupComment")
    return lookupCommentHandler?(key, value)
  }

  func populateReverseLookupCache(_ str: String) { record("PopulateReverseLookupCache") }
  func clearReverseLookupCache() { record("ClearReverseLookupCache") }

  @discardableResult
  func reload() -> Bool {
    record("Reload")
    return true
  }

  func waitForReloader() { record("WaitForReloader") }

  func getPosList() -> [String] { posList }

  @discardableResult
  func load(_ storage: Genmai_UserDictionary_UserDictionaryStorage) -> Bool {
    record("Load")
    return true
  }

  func isSuppressedEntry(_ key: String, _ value: String) -> Bool {
    record("IsSuppressedEntry")
    return isSuppressedEntryHandler?(key, value) ?? false
  }

  func hasSuppressedEntries() -> Bool {
    record("HasSuppressedEntries")
    return hasSuppressedEntriesHandler?() ?? false
  }
}

/// `MockCallback`.
final class MockCallback: DictionaryCallback {
  var onKeyHandler: ((String) -> DictionaryCallbackResult)?
  var onActualKeyHandler: ((String, String, Int) -> DictionaryCallbackResult)?
  var onTokenHandler: ((String, String, Token) -> DictionaryCallbackResult)?
  private(set) var onKeyCount = 0
  private(set) var onActualKeyCount = 0
  private(set) var onTokenCount = 0

  func onKey(_ key: String) -> DictionaryCallbackResult {
    onKeyCount += 1
    return onKeyHandler?(key) ?? .traverseContinue
  }

  func onActualKey(_ key: String, _ actualKey: String, _ numExpanded: Int) -> DictionaryCallbackResult {
    onActualKeyCount += 1
    return onActualKeyHandler?(key, actualKey, numExpanded) ?? .traverseContinue
  }

  func onToken(_ key: String, _ expandedKey: String, _ token: Token) -> DictionaryCallbackResult {
    onTokenCount += 1
    return onTokenHandler?(key, expandedKey, token) ?? .traverseContinue
  }
}
