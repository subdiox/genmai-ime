// Port of mozc/src/dictionary/user_dictionary_stub.h (3.35.6354).

import GenmaiProtocol

/// `mozc::dictionary::UserDictionaryStub`.
public final class UserDictionaryStub: UserDictionaryInterface {
  public init() {}

  public func lookupComment(_ key: String, _ value: String) -> String? {
    if key.bytesEqual("comment") || value.bytesEqual("comment") {
      return "UserDictionaryStub"
    }
    return nil
  }

  public func getPosList() -> [String] { [] }

  public func waitForReloader() async {}

  @discardableResult
  public func load(_ storage: Genmai_UserDictionary_UserDictionaryStorage) -> Bool { true }

  public func isSuppressedEntry(_ key: String, _ value: String) -> Bool { false }

  public func hasSuppressedEntries() -> Bool { false }
}
