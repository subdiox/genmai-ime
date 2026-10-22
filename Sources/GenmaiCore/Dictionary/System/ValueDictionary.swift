// Port of mozc/src/dictionary/system/value_dictionary.{h,cc} (3.35.6354).
//
// This dictionary supports system dicitonary that will be looked up from
// value, rather than key.
// Value dictionary is mainly used to lookup the English words from
// user-typed literal sequences. (English has no 'reading' representation.)
// Token's key, cost, ids will not be looked up due to performance concern

import GenmaiBase
import GenmaiStorage

/// `mozc::dictionary::ValueDictionary`.
public final class ValueDictionary: DictionaryInterface, Sendable {
  // Immutable; |value_trie| is immutable after open().

  // This class doesn't take the ownership of |value_trie| (the LoudsTrie
  // object is shared, e.g. `SystemDictionary.valueTrie`; its image must stay
  // alive).
  private let valueTrie: LoudsTrie
  private let codec = SystemDictionaryCodec()
  private let suggestionOnlyWordId: UInt16

  public init(_ posMatcher: PosMatcher, _ valueTrie: LoudsTrie) {
    self.valueTrie = valueTrie
    suggestionOnlyWordId = posMatcher.getSuggestOnlyWordId()
  }

  // A version of the above function for Token.
  @inline(__always)
  private static func fillToken(_ suggestionOnlyWordId: UInt16, _ key: String) -> Token {
    Token(
      key: key, value: key, cost: 10000, lid: suggestionOnlyWordId, rid: suggestionOnlyWordId,
      attributes: Token.Attribute.none)
  }

  private static func isValidKey(_ key: String) -> Bool {
    // Do nothing for empty key, although looking up all the entries with empty
    // string seems natural.
    if key.isEmpty {
      return false
    }
    // Value dictionary is used to suggest English words from literal ASCII
    // query.
    let type = Util.getFirstScriptType(key)
    if type == .hiragana || type == .kanji || type == .katakana {
      return false
    }
    return true
  }

  private func handleTerminalNode(
    _ node: LoudsTrie.Node, _ callback: any DictionaryCallback
  ) -> DictionaryCallbackResult {
    let encodedValue = valueTrie.restoreKeyString(node)

    let value = codec.decodeValue(encodedValue)
    var result = callback.onKey(value)
    if result != .traverseContinue {
      return result
    }
    result = callback.onActualKey(value, value, 0)  // num_expanded
    if result != .traverseContinue {
      return result
    }
    return callback.onToken(value, value, Self.fillToken(suggestionOnlyWordId, value))
  }

  public func lookupPredictive(_ key: String, callback: any DictionaryCallback) {
    if !Self.isValidKey(key) {
      return
    }

    var node = LoudsTrie.Node()
    if !valueTrie.traverse(codec.encodeValue(key), &node) {
      return
    }

    // Traverse subtree rooted at |node|.
    var queue: [LoudsTrie.Node] = [node]
    var head = 0
    repeat {
      node = queue[head]
      head += 1

      if valueTrie.isTerminalNode(node) {
        switch handleTerminalNode(node, callback) {
        case .traverseDone:
          return
        case .traverseCull:
          continue
        default:
          break
        }
      }

      valueTrie.moveToFirstChild(&node)
      while valueTrie.isValidNode(node) {
        queue.append(node)
        LoudsTrie.moveToNextSibling(&node)
      }
    } while head < queue.count
  }

  public func lookupExact(_ key: String, callback: any DictionaryCallback) {
    if !Self.isValidKey(key) {
      return
    }

    if valueTrie.exactSearch(codec.encodeValue(key)) == -1 {
      return
    }
    if callback.onKey(key) != .traverseContinue {
      return
    }
    if callback.onActualKey(key, key, 0) != .traverseContinue {  // num_expanded
      return
    }
    _ = callback.onToken(key, key, Self.fillToken(suggestionOnlyWordId, key))
  }
}
