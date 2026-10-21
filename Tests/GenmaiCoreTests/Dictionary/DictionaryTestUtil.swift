// Port of mozc/src/dictionary/dictionary_test_util.{h,cc} (3.35.6354).

import Testing

@testable import GenmaiCore

// NOTE: the base class implements every DictionaryCallback requirement so
// that subclasses can `override` them. (A subclass method does not replace a
// protocol extension default that the base class inherited.)
class TokenCallbackBase: DictionaryCallback {
  private var kanaModifierInsensitiveConversion = false

  func onKey(_ key: String) -> DictionaryCallbackResult { .traverseContinue }

  func onActualKey(_ key: String, _ actualKey: String, _ numExpanded: Int) -> DictionaryCallbackResult {
    .traverseContinue
  }

  func onToken(_ key: String, _ actualKey: String, _ token: Token) -> DictionaryCallbackResult {
    .traverseContinue
  }

  func isKanaModifierInsensitiveConversion() -> Bool {
    kanaModifierInsensitiveConversion
  }

  func setKanaModifierInsensitiveConversion(_ flag: Bool) {
    kanaModifierInsensitiveConversion = flag
  }
}

/// Used to collect all the tokens looked up.
final class CollectTokenCallback: TokenCallbackBase {
  private(set) var tokens: [Token] = []

  func clear() { tokens.removeAll() }

  override func onToken(_ key: String, _ actualKey: String, _ token: Token) -> DictionaryCallbackResult {
    tokens.append(token)
    return .traverseContinue
  }
}

/// Used to test if a given token is looked up.
final class CheckTokenExistenceCallback: TokenCallbackBase {
  private let targetToken: Token
  private(set) var found = false

  init(_ targetToken: Token) {
    self.targetToken = targetToken
  }

  override func onToken(_ key: String, _ actualKey: String, _ token: Token) -> DictionaryCallbackResult {
    if isTokenEqualImpl(targetToken, token) {
      found = true
      return .traverseDone
    }
    return .traverseContinue
  }
}

/// The C++ version identifies tokens by pointer; here they are identified by
/// their index in the array given to the initializer.
final class CheckMultiTokensExistenceCallback: TokenCallbackBase {
  private let tokens: [Token]
  private var result: [Bool]
  private var foundCount = 0

  init(_ tokens: [Token]) {
    self.tokens = tokens
    self.result = Array(repeating: false, count: tokens.count)
  }

  func isFound(_ index: Int) -> Bool { result[index] }

  func areAllFound() -> Bool { !result.contains(false) }

  override func onToken(_ key: String, _ actualKey: String, _ token: Token) -> DictionaryCallbackResult {
    for i in tokens.indices where !result[i] && isTokenEqualImpl(tokens[i], token) {
      result[i] = true
      foundCount += 1
      break
    }
    return foundCount == result.count ? .traverseDone : .traverseContinue
  }
}

func isTokenEqualImpl(_ expected: Token, _ actual: Token) -> Bool {
  expected.key.bytesEqual(actual.key) && expected.value.bytesEqual(actual.value)
    && expected.cost == actual.cost && expected.lid == actual.lid && expected.rid == actual.rid
    && expected.attributes == actual.attributes
}

/// Generates a human redable string of token(s).
func printToken(_ token: Token) -> String {
  "{key:\(token.key), val:\(token.value), cost:\(token.cost), lid:\(token.lid), "
    + "rid:\(token.rid), attr:\(token.attributes)}"
}

func printTokens(_ tokens: [Token]) -> String {
  "[" + tokens.map { printToken($0) + ", " }.joined() + "]"
}

/// EXPECT_TOKEN_EQ.
func expectTokenEq(
  _ expected: Token, _ actual: Token, sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(
    isTokenEqualImpl(expected, actual),
    "Tokens are not equal\nExpected: \(printToken(expected))\nActual: \(printToken(actual))",
    sourceLocation: sourceLocation)
}

/// EXPECT_TOKENS_EQ_UNORDERED: tests if two token vectors are equal to each
/// other as unordered set.
func expectTokensEqUnordered(
  _ expected: [Token], _ actual: [Token], sourceLocation: SourceLocation = #_sourceLocation
) {
  guard expected.count == actual.count else {
    Issue.record(
      "Size are different\nExpected: \(printTokens(expected))\nActual: \(printTokens(actual))",
      sourceLocation: sourceLocation)
    return
  }
  let encodedActual = Set(actual.map(printToken))
  for (i, token) in expected.enumerated() where !encodedActual.contains(printToken(token)) {
    Issue.record(
      "Expected token \(i) not found\nExpected: \(printTokens(expected))\nActual: \(printTokens(actual))",
      sourceLocation: sourceLocation)
    return
  }
}
