// Port of mozc/src/dictionary/dictionary_interface.h (3.35.6354).

import GenmaiProtocol

/// `DictionaryInterface::Callback::ResultType`.
///
/// Using the return value of each callback method, you can tell the traverser
/// how to proceed. The meanings of the four values are as follows:
///   1) traverseDone
///       Quit the traversal, i.e., no more callbacks for keys and/or tokens.
///   2) traverseNextKey
///       Finish the traversal for the current key and search for the next key.
///       If returned from onToken(), the remaining tokens are discarded.
///   3) traverseCull
///       Similar to traverseNextKey, finish the traversal for the current
///       key but search for the next key by using search culling. Namely,
///       traversal of the subtree starting with the current key is skipped,
///       which is the difference from traverseNextKey.
///   4) traverseContinue
///       Continue the traversal for the current key or tokens, namely:
///         - If returned from onKey(), onActualKey() will be called back.
///         - If returned from onActualKey(), a series of onToken()'s will be
///           called back.
///         - If returned from onToken(), onToken() will be called back again
///           with the next token, provided that it exists. Proceed to the next
///           key if there's no more token.
public enum DictionaryCallbackResult: Sendable, Equatable {
  case traverseDone
  case traverseNextKey
  case traverseCull
  case traverseContinue
}

/// `DictionaryInterface::Callback`: callback interface for dictionary traversal
/// (currently implemented only for prefix and exact search). Each method is
/// called in the following manner:
///
///     for (each key found) {
///       onKey(key)
///       onActualKey(key, actualKey, numExpanded)
///       for (each token in the token array for the key) {
///         onToken(key, actualKey, token)
///       }
///     }
///
/// Every requirement has a default implementation (returning
/// `.traverseContinue` / `false`), like the C++ virtual methods. Conformers are
/// classes because callbacks accumulate state during a lookup.
///
/// CAUTION: a class hierarchy must implement every requirement it wants
/// subclasses to customize in the *base* class (and subclasses `override`
/// them). A subclass method with the same signature does NOT replace a
/// protocol-extension default the base class inherited, so it would never be
/// called through `any DictionaryCallback`.
public protocol DictionaryCallback: AnyObject {
  typealias ResultType = DictionaryCallbackResult

  /// Called back when key is found.
  func onKey(_ key: String) -> DictionaryCallbackResult

  /// Called back when actual key is decoded. `numExpanded` is the number
  /// of different characters between key and actualKey.
  func onActualKey(_ key: String, _ actualKey: String, _ numExpanded: Int) -> DictionaryCallbackResult

  /// Called back when a token is decoded. The token is passed by value.
  func onToken(_ key: String, _ expandedKey: String, _ token: Token) -> DictionaryCallbackResult

  func isKanaModifierInsensitiveConversion() -> Bool
}

extension DictionaryCallback {
  public func onKey(_ key: String) -> DictionaryCallbackResult { .traverseContinue }

  public func onActualKey(_ key: String, _ actualKey: String, _ numExpanded: Int)
    -> DictionaryCallbackResult
  { .traverseContinue }

  public func onToken(_ key: String, _ expandedKey: String, _ token: Token)
    -> DictionaryCallbackResult
  { .traverseContinue }

  public func isKanaModifierInsensitiveConversion() -> Bool { false }
}

/// `mozc::dictionary::DictionaryInterface`.
///
/// Every requirement has a default implementation matching the C++ base class
/// (no-op / `false`). The `options:` overloads forward to the plain overloads
/// by default, as in C++.
///
/// Deviation: `LookupComment(key, value, std::string* comment) -> bool` is
/// `lookupComment(_:_:) -> String?` (nil corresponds to `false`).
public protocol DictionaryInterface: AnyObject, Sendable {
  /// Returns true if the dictionary has an entry for the given key.
  func hasKey(_ key: String) -> Bool

  /// Returns true if the dictionary has an entry for the given value.
  func hasValue(_ value: String) -> Bool

  /// Looks up values whose keys start from the key.
  /// (e.g. key = "abc" -> {"abc": "ABC", "abcd": "ABCD"})
  func lookupPredictive(_ key: String, callback: any DictionaryCallback)

  /// Looks up values whose keys are prefixes of the key.
  /// (e.g. key = "abc" -> {"abc": "ABC", "a": "A"})
  func lookupPrefix(_ key: String, callback: any DictionaryCallback)

  /// Looks up values whose keys are same with the key.
  /// (e.g. key = "abc" -> {"abc": "ABC"})
  func lookupExact(_ key: String, callback: any DictionaryCallback)

  /// For reverse lookup, the reading is stored in Token.value and the word
  /// is stored in Token.key.
  func lookupReverse(_ str: String, callback: any DictionaryCallback)

  /// Looks up a user comment from a pair of key and value. Returns nil when
  /// (key, value) doesn't exist in this dictionary or user comment is empty.
  func lookupComment(_ key: String, _ value: String) -> String?

  // Interfaces with conversion_options.
  // Decoupled from ConversionRequest.

  func lookupPredictive(_ key: String, options: ConversionOptions, callback: any DictionaryCallback)
  func lookupPrefix(_ key: String, options: ConversionOptions, callback: any DictionaryCallback)
  func lookupExact(_ key: String, options: ConversionOptions, callback: any DictionaryCallback)
  func lookupReverse(_ str: String, options: ConversionOptions, callback: any DictionaryCallback)
  func lookupComment(_ key: String, _ value: String, options: ConversionOptions) -> String?

  /// Populates cache for lookupReverse().
  func populateReverseLookupCache(_ str: String)
  func clearReverseLookupCache()
}

extension DictionaryInterface {
  public func hasKey(_ key: String) -> Bool { false }
  public func hasValue(_ value: String) -> Bool { false }
  public func lookupPredictive(_ key: String, callback: any DictionaryCallback) {}
  public func lookupPrefix(_ key: String, callback: any DictionaryCallback) {}
  public func lookupExact(_ key: String, callback: any DictionaryCallback) {}
  public func lookupReverse(_ str: String, callback: any DictionaryCallback) {}
  public func lookupComment(_ key: String, _ value: String) -> String? { nil }

  public func lookupPredictive(
    _ key: String, options: ConversionOptions, callback: any DictionaryCallback
  ) {
    lookupPredictive(key, callback: callback)
  }

  public func lookupPrefix(
    _ key: String, options: ConversionOptions, callback: any DictionaryCallback
  ) {
    lookupPrefix(key, callback: callback)
  }

  public func lookupExact(
    _ key: String, options: ConversionOptions, callback: any DictionaryCallback
  ) {
    lookupExact(key, callback: callback)
  }

  public func lookupReverse(
    _ str: String, options: ConversionOptions, callback: any DictionaryCallback
  ) {
    lookupReverse(str, callback: callback)
  }

  public func lookupComment(_ key: String, _ value: String, options: ConversionOptions) -> String? {
    lookupComment(key, value)
  }

  public func populateReverseLookupCache(_ str: String) {}
  public func clearReverseLookupCache() {}
}

/// `mozc::dictionary::InlineCallback`: a callback built from closures.
public final class InlineCallback: DictionaryCallback {
  public typealias KeyHandler = (String) -> DictionaryCallbackResult
  public typealias ActualKeyHandler = (String, String, Int) -> DictionaryCallbackResult
  public typealias TokenHandler = (String, String, Token) -> DictionaryCallbackResult

  private var keyHandler: KeyHandler?
  private var actualHandler: ActualKeyHandler?
  private var tokenHandler: TokenHandler?

  public init() {}

  @discardableResult
  public func onKey(_ handler: @escaping KeyHandler) -> InlineCallback {
    keyHandler = handler
    return self
  }

  @discardableResult
  public func onActualKey(_ handler: @escaping ActualKeyHandler) -> InlineCallback {
    actualHandler = handler
    return self
  }

  @discardableResult
  public func onToken(_ handler: @escaping TokenHandler) -> InlineCallback {
    tokenHandler = handler
    return self
  }

  public func onKey(_ key: String) -> DictionaryCallbackResult {
    keyHandler?(key) ?? .traverseContinue
  }

  public func onActualKey(_ key: String, _ actualKey: String, _ numExpanded: Int)
    -> DictionaryCallbackResult
  {
    actualHandler?(key, actualKey, numExpanded) ?? .traverseContinue
  }

  public func onToken(_ key: String, _ expandedKey: String, _ token: Token)
    -> DictionaryCallbackResult
  {
    tokenHandler?(key, expandedKey, token) ?? .traverseContinue
  }
}

/// `mozc::dictionary::UserDictionaryInterface`.
public protocol UserDictionaryInterface: DictionaryInterface {
  /// Waits until reloader finishes.
  func waitForReloader() async

  /// Gets the user POS list.
  func getPosList() -> [String]

  /// Loads dictionary from UserDictionaryStorage.
  /// mainly for unit testing
  @discardableResult
  func load(_ storage: Genmai_UserDictionary_UserDictionaryStorage) -> Bool

  /// Suppress `key` and `value` with suppression dictionary.
  /// Suppression entries are defined in the user dictionary with a special
  /// POS.
  func isSuppressedEntry(_ key: String, _ value: String) -> Bool

  /// Return true if the dictionary has at least one suppression entry.
  func hasSuppressedEntries() -> Bool

  /// Reload dictionary data from local disk.
  @discardableResult
  func reload() -> Bool
}

extension UserDictionaryInterface {
  @discardableResult
  public func reload() -> Bool { true }
}
