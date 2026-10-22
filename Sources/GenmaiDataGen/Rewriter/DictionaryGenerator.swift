// Port of mozc/src/rewriter/dictionary_generator.{h,cc} (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiCore

public enum RewriterDictionaryGenerator {
  public struct Token {
    public var sortingKey: Int = 0
    public var key: String = ""
    public var value: String = ""
    public var pos: String = ""
    public var description: String = ""
    public var additionalDescription: String = ""

    public init(
      sortingKey: Int, key: String, value: String, pos: String, description: String, additionalDescription: String
    ) {
      self.sortingKey = sortingKey
      self.key = key
      self.value = value
      self.pos = pos
      self.description = description
      self.additionalDescription = additionalDescription
    }

    static func mergeTokenString(_ base: inout String, _ newString: String) {
      if !newString.isEmpty {
        base = newString
      }
    }

    mutating func mergeFrom(_ newToken: Token) {
      sortingKey = newToken.sortingKey == 0 ? sortingKey : newToken.sortingKey
      Token.mergeTokenString(&key, newToken.key)
      Token.mergeTokenString(&value, newToken.value)
      Token.mergeTokenString(&pos, newToken.pos)
      Token.mergeTokenString(&description, newToken.description)
      Token.mergeTokenString(&additionalDescription, newToken.additionalDescription)
    }

    /// The ordering key of the btree_set: std::tie(key, sorting_key, value),
    /// strings compared bytewise.
    struct OrderKey: Hashable, Comparable {
      let key: BStr
      let sortingKey: Int
      let value: BStr
      static func < (a: OrderKey, b: OrderKey) -> Bool {
        if a.key != b.key { return a.key < b.key }
        if a.sortingKey != b.sortingKey { return a.sortingKey < b.sortingKey }
        return a.value < b.value
      }
    }

    var orderKey: OrderKey { OrderKey(key: BStr(key), sortingKey: sortingKey, value: BStr(value)) }
  }

  public final class DictionaryGenerator {
    /// absl::btree_set<Token> (sorted on output).
    private var tokens: [Token.OrderKey: Token] = [:]
    private let userPos: UserPos
    private let openBracketId: UInt16
    private let closeBracketId: UInt16

    public init(_ userPos: UserPos, _ posMatcher: PosMatcher) {
      self.userPos = userPos
      openBracketId = posMatcher.getOpenBracketId()
      closeBracketId = posMatcher.getCloseBracketId()
    }

    /// Add the token into the pool.
    public func addToken(_ token: Token) {
      // extract() finds an equivalent element under operator<; the merged
      // token is reinserted (its ordering fields may change).
      let k = token.orderKey
      if var existing = tokens.removeValue(forKey: k) {
        existing.mergeFrom(token)
        tokens[existing.orderKey] = existing
      } else {
        tokens[k] = token
      }
    }

    /// Output the tokens in Mozc dictionary format.
    public func output() throws -> [UInt8] {
      var os: [UInt8] = []
      var numSameKeys: UInt32 = 0
      var prevKey = ""
      for orderKey in tokens.keys.sorted() {
        let token = tokens[orderKey]!
        let pos = token.pos

        // Update the number of the sequence of the same keys
        if prevKey.utf8.elementsEqual(token.key.utf8) {
          numSameKeys += 1
        } else {
          numSameKeys = 0
          prevKey = token.key
        }
        let cost = 10 * numSameKeys

        let id: UInt16
        if pos.utf8.elementsEqual("括弧開".utf8) {
          id = openBracketId
        } else if pos.utf8.elementsEqual("括弧閉".utf8) {
          id = closeBracketId
        } else {
          guard let i = userPos.getPosIds(pos) else { throw DataGenError.invalidInput("unknown POS \(pos)") }
          id = i
        }

        // Output in mozc dictionary format
        let line =
          "\(token.key)\t\(id)\t\(id)\t\(cost)\t\(token.value)\t\(token.description)\t\(token.additionalDescription)\n"
        os.append(contentsOf: line.utf8)
      }
      return os
    }
  }
}
