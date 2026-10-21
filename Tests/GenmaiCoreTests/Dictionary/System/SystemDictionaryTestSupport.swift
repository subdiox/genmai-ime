// Test helpers for the dictionary/system and dictionary/file tests (Swift
// only). Namespaced / prefixed to avoid clashing with helpers of other
// GenmaiCoreTests folders.
//
// The callbacks below declare every DictionaryCallback requirement in the base
// class so that subclasses' implementations are dispatched dynamically
// through the protocol (a subclass cannot override a protocol-extension
// default that the base class did not implement).

import Foundation
import GenmaiBase
import Testing

@testable import GenmaiCore

enum SystemDictionaryTestSupport {
  /// Repository root, located from this source file.
  static let repositoryRoot: String = {
    var url = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
    // Tests/GenmaiCoreTests/Dictionary/System/<file>.swift -> repository root
    for _ in 0..<5 {
      url.deleteLastPathComponent()
    }
    return url.path
  }()

  /// Absolute path of a file in Vendor/mozc/src (C++ GetSourceFileOrDie).
  static func sourcePath(_ components: String...) -> String {
    FileUtil.joinPath(repositoryRoot, "Vendor/mozc/src/" + components.joined(separator: "/"))
  }

  static var hasMockData: Bool { MockDataManager.defaultDataPath != nil }

  static var hasOssData: Bool { FileManager.default.fileExists(atPath: OssDataManager.defaultDataPath) }

  /// FLAGS_dictionary_test_size.
  static let dictionaryTestSize = 100000
  /// FLAGS_dictionary_reverse_lookup_test_size.
  static let dictionaryReverseLookupTestSize = 1000

  /// The mock data manager and the tokens of dictionary00.txt (first
  /// `dictionaryTestSize` lines) loaded by TextDictionaryLoader, shared by the
  /// tests (loading takes a while).
  static let fixture: (dataManager: MockDataManager, posMatcher: PosMatcher, tokens: [Token])? = {
    guard let dataManager = try? MockDataManager() else { return nil }
    let posMatcher = PosMatcher(dataManager.getPosMatcherData())
    let loader = TextDictionaryLoader(posMatcher)
    loader.loadWithLineLimit(sourcePath("data", "dictionary_oss", "dictionary00.txt"), "", dictionaryTestSize)
    return (dataManager, posMatcher, loader.tokens)
  }()

  /// Builds a system dictionary image from the first `numTokens` tokens.
  /// By default small cost encoding is disabled (as in the C++ test's SetUp).
  static func buildImage(
    _ source: [Token], _ numTokens: Int = Int.max, minKeyLength: Int = Int(Int32.max)
  ) -> [UInt8] {
    let builder = SystemDictionaryBuilder()
    builder.minKeyLengthToUseSmallCostEncoding = minKeyLength
    builder.buildFromTokens(Array(source.prefix(numTokens)))
    return builder.writeToBytes()
  }

  static func buildSystemDictionary(
    _ source: [Token], _ numTokens: Int = Int.max, minKeyLength: Int = Int(Int32.max)
  ) throws -> SystemDictionary {
    try SystemDictionary.Builder(image: DataView(copying: buildImage(source, numTokens, minKeyLength: minKeyLength)))
      .build()
  }
}

/// TokenCallbackBase with every requirement implemented in the class.
class SysDicCallbackBase: DictionaryCallback {
  private var kanaModifierInsensitiveConversion = false

  func onKey(_ key: String) -> DictionaryCallbackResult { .traverseContinue }

  func onActualKey(_ key: String, _ actualKey: String, _ numExpanded: Int) -> DictionaryCallbackResult {
    .traverseContinue
  }

  func onToken(_ key: String, _ actualKey: String, _ token: Token) -> DictionaryCallbackResult {
    .traverseContinue
  }

  func isKanaModifierInsensitiveConversion() -> Bool { kanaModifierInsensitiveConversion }

  func setKanaModifierInsensitiveConversion(_ flag: Bool) {
    kanaModifierInsensitiveConversion = flag
  }
}

/// CollectTokenCallback.
final class SysDicCollectTokenCallback: SysDicCallbackBase {
  private(set) var tokens: [Token] = []

  func clear() { tokens.removeAll() }

  override func onToken(_ key: String, _ actualKey: String, _ token: Token) -> DictionaryCallbackResult {
    tokens.append(token)
    return .traverseContinue
  }
}

/// CheckTokenExistenceCallback.
final class SysDicCheckTokenExistenceCallback: SysDicCallbackBase {
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

/// CheckMultiTokensExistenceCallback (tokens identified by index).
final class SysDicCheckMultiTokensExistenceCallback: SysDicCallbackBase {
  private let tokens: [Token]
  private var result: [Bool]
  private var foundCount = 0

  init(_ tokens: [Token]) {
    self.tokens = tokens
    result = Array(repeating: false, count: tokens.count)
  }

  func isFound(_ index: Int) -> Bool { result[index] }

  func areAllFound() -> Bool { foundCount == result.count }

  override func onToken(_ key: String, _ actualKey: String, _ token: Token) -> DictionaryCallbackResult {
    for i in tokens.indices where !result[i] && isTokenEqualImpl(tokens[i], token) {
      result[i] = true
      foundCount += 1
      break
    }
    return foundCount == result.count ? .traverseDone : .traverseContinue
  }
}

/// Replacement of the gmock MockCallback: records every call and returns
/// TRAVERSE_CONTINUE.
final class SysDicRecordingCallback: SysDicCallbackBase {
  private(set) var keys: [String] = []
  private(set) var actualKeys: [(String, String, Int)] = []
  private(set) var tokenKeys: [(String, String)] = []

  override func onKey(_ key: String) -> DictionaryCallbackResult {
    keys.append(key)
    return .traverseContinue
  }

  override func onActualKey(_ key: String, _ actualKey: String, _ numExpanded: Int) -> DictionaryCallbackResult {
    actualKeys.append((key, actualKey, numExpanded))
    return .traverseContinue
  }

  override func onToken(_ key: String, _ actualKey: String, _ token: Token) -> DictionaryCallbackResult {
    tokenKeys.append((key, actualKey))
    return .traverseContinue
  }

  func onKeyCount(_ key: String) -> Int { keys.filter { $0 == key }.count }

  func onActualKeyCount(_ key: String, _ actualKey: String, _ numExpanded: Int) -> Int {
    actualKeys.filter { $0.0 == key && $0.1 == actualKey && $0.2 == numExpanded }.count
  }

  func onTokenCount(_ key: String, _ actualKey: String) -> Int {
    tokenKeys.filter { $0.0 == key && $0.1 == actualKey }.count
  }
}
