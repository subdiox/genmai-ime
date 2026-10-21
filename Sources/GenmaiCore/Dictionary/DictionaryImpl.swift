// Port of mozc/src/dictionary/dictionary_impl.{h,cc} (3.35.6354).

import GenmaiBase

/// `mozc::dictionary::DictionaryImpl`: the composite of the system, value and
/// user dictionaries.
public final class DictionaryImpl: DictionaryInterface, @unchecked Sendable {
  // @unchecked Sendable: all stored properties are immutable references to
  // Sendable dictionaries.

  // Used to check POS IDs.
  private let posMatcher: PosMatcher

  // Main three dictionaries.
  private let systemDictionary: any DictionaryInterface
  private let valueDictionary: any DictionaryInterface
  private let userDictionary: any UserDictionaryInterface

  // Convenient container to handle the above three dictionaries as one
  // composite dictionary.
  private let dics: [any DictionaryInterface]

  /// Initializes a dictionary with given dictionaries and POS data. The user
  /// dictionary is shared with the caller (who may reload it).
  public init(
    _ systemDictionary: any DictionaryInterface, _ valueDictionary: any DictionaryInterface,
    _ userDictionary: any UserDictionaryInterface, _ posMatcher: PosMatcher
  ) {
    self.posMatcher = posMatcher
    self.systemDictionary = systemDictionary
    self.valueDictionary = valueDictionary
    self.userDictionary = userDictionary
    self.dics = [systemDictionary, valueDictionary, userDictionary]
  }

  public func hasKey(_ key: String) -> Bool {
    dics.contains { $0.hasKey(key) }
  }

  public func hasValue(_ value: String) -> Bool {
    dics.contains { $0.hasValue(value) }
  }

  // Interfaces with conversion_options.

  public func lookupPredictive(
    _ key: String, options: ConversionOptions, callback: any DictionaryCallback
  ) {
    let callbackWithFilter = CallbackWithFilter(options, posMatcher, userDictionary, callback)
    for dic in getDictionaries(options.incognitoMode) {
      dic.lookupPredictive(key, callback: callbackWithFilter)
    }
  }

  public func lookupPrefix(
    _ key: String, options: ConversionOptions, callback: any DictionaryCallback
  ) {
    let callbackWithFilter = CallbackWithFilter(options, posMatcher, userDictionary, callback)
    for dic in getDictionaries(options.incognitoMode) {
      dic.lookupPrefix(key, callback: callbackWithFilter)
    }
  }

  public func lookupExact(
    _ key: String, options: ConversionOptions, callback: any DictionaryCallback
  ) {
    let callbackWithFilter = CallbackWithFilter(options, posMatcher, userDictionary, callback)
    for dic in getDictionaries(options.incognitoMode) {
      dic.lookupExact(key, callback: callbackWithFilter)
    }
  }

  public func lookupReverse(
    _ str: String, options: ConversionOptions, callback: any DictionaryCallback
  ) {
    let callbackWithFilter = CallbackWithFilter(options, posMatcher, userDictionary, callback)
    for dic in getDictionaries(options.incognitoMode) {
      dic.lookupReverse(str, callback: callbackWithFilter)
    }
  }

  public func lookupComment(_ key: String, _ value: String, options: ConversionOptions) -> String? {
    // Access dics in reverse order to prefer UserDictionary (if not in incognito)
    for dic in getDictionaries(options.incognitoMode).reversed() {
      if let comment = dic.lookupComment(key, value) {
        return comment
      }
    }
    return nil
  }

  // Interfaces without conversion_options.

  public func lookupPredictive(_ key: String, callback: any DictionaryCallback) {
    for dic in dics {
      dic.lookupPredictive(key, callback: callback)
    }
  }

  public func lookupPrefix(_ key: String, callback: any DictionaryCallback) {
    for dic in dics {
      dic.lookupPrefix(key, callback: callback)
    }
  }

  public func lookupExact(_ key: String, callback: any DictionaryCallback) {
    for dic in dics {
      dic.lookupExact(key, callback: callback)
    }
  }

  public func lookupReverse(_ str: String, callback: any DictionaryCallback) {
    for dic in dics {
      dic.lookupReverse(str, callback: callback)
    }
  }

  public func lookupComment(_ key: String, _ value: String) -> String? {
    // Access dics in reverse order to prefer UserDictionary
    for dic in dics.reversed() {
      if let comment = dic.lookupComment(key, value) {
        return comment
      }
    }
    return nil
  }

  public func populateReverseLookupCache(_ str: String) {
    for dic in dics {
      dic.populateReverseLookupCache(str)
    }
  }

  public func clearReverseLookupCache() {
    for dic in dics {
      dic.clearReverseLookupCache()
    }
  }

  private func getDictionaries(_ incognitoMode: Bool) -> ArraySlice<any DictionaryInterface> {
    // Removes the last user dictionary when incognito_mode.
    let size = (incognitoMode && !dics.isEmpty) ? 1 : 0
    return dics[0..<(dics.count - size)]
  }
}

private final class CallbackWithFilter: DictionaryCallback {
  private let options: ConversionOptions
  private let posMatcher: PosMatcher
  private let userDictionary: any UserDictionaryInterface
  // cache the result of HasSuppressedEntries, because calling
  // IsSuppressedEntry() has some latency because of mutex lock even when
  // the entry is empty.
  private let hasSuppressedEntries: Bool
  private let callback: any DictionaryCallback

  init(
    _ options: ConversionOptions, _ posMatcher: PosMatcher,
    _ userDictionary: any UserDictionaryInterface, _ callback: any DictionaryCallback
  ) {
    self.options = options
    self.posMatcher = posMatcher
    self.userDictionary = userDictionary
    self.hasSuppressedEntries = userDictionary.hasSuppressedEntries()
    self.callback = callback
  }

  func onKey(_ key: String) -> DictionaryCallbackResult {
    callback.onKey(key)
  }

  func onActualKey(_ key: String, _ actualKey: String, _ numExpanded: Int)
    -> DictionaryCallbackResult
  {
    callback.onActualKey(key, actualKey, numExpanded)
  }

  func onToken(_ key: String, _ actualKey: String, _ token: Token) -> DictionaryCallbackResult {
    if token.attributes & Token.Attribute.userDictionary == 0 {
      if !options.useSpellingCorrection
        && (token.attributes & Token.Attribute.spellingCorrection) != 0
      {
        return .traverseContinue
      }
      if !options.useZipCodeConversion && posMatcher.isZipcode(token.lid) {
        return .traverseContinue
      }
      if !options.useT13nConversion && Util.isEnglishTransliteration(token.value) {
        return .traverseContinue
      }
    }

    if hasSuppressedEntries && userDictionary.isSuppressedEntry(token.key, token.value) {
      return .traverseContinue
    }
    return callback.onToken(key, actualKey, token)
  }

  func isKanaModifierInsensitiveConversion() -> Bool {
    options.kanaModifierInsensitiveConversion
  }
}
