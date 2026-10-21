// Port of mozc/src/dictionary/system/token_decode_iterator.h (3.35.6354).
//
// A value type (the C++ class is non-copyable and used on the stack).
// `get()` returns the current TokenInfo; its `token` is reused across
// iterations exactly like the C++ shared `Token` instance (lid/rid stay for
// SAME_AS_PREV_POS, value stays for SAME_AS_PREV_VALUE), so callers copy the
// token (Swift value semantics do that implicitly).

import GenmaiBase
import GenmaiStorage

public struct TokenDecodeIterator {
  private enum State {
    case hasNext
    case lastToken
    case done
  }

  private let codec: SystemDictionaryCodec
  private let valueTrie: LoudsTrie
  private let frequentPos: UnsafeBufferPointer<UInt32>

  private let key: String
  // Katakana key will be lazily initialized.
  private var keyKatakana = ""

  private var state: State = .hasNext
  private var ptr: UnsafePointer<UInt8>

  private var tokenInfo: TokenInfo

  public init(
    _ codec: SystemDictionaryCodec, _ valueTrie: LoudsTrie, _ frequentPos: UnsafeBufferPointer<UInt32>,
    _ key: String, _ ptr: UnsafePointer<UInt8>
  ) {
    self.codec = codec
    self.valueTrie = valueTrie
    self.frequentPos = frequentPos
    self.key = key
    self.ptr = ptr
    var token = Token()
    token.key = key
    tokenInfo = TokenInfo(token)
    nextInternal()
  }

  @inline(__always)
  public func get() -> TokenInfo { tokenInfo }

  /// The current token (shortcut for `get().token`).
  @inline(__always)
  public var token: Token { tokenInfo.token }

  @inline(__always)
  public func done() -> Bool { state == .done }

  public mutating func next() {
    assert(state != .done)
    if state == .lastToken {
      state = .done
      return
    }
    nextInternal()
  }

  private func lookupValue(_ id: Int) -> String {
    withUnsafeTemporaryAllocation(of: UInt8.self, capacity: LoudsTrie.kMaxDepth + 1) { buffer in
      let encodedValue = valueTrie.restoreKeyString(id, buffer.baseAddress!)
      return codec.decodeValue(encodedValue)
    }
  }

  private mutating func nextInternal() {
    // Reset token_info with preserving some needed info in previous token.
    let prevIdInValueTrie = tokenInfo.idInValueTrie
    tokenInfo.clear()

    // Do not clear key in token.
    tokenInfo.token.attributes = Token.Attribute.none

    // This implementation is depending on the internal behavior of DecodeToken
    // especially which fields are updated or not. Important fields are:
    // Token::key, Token::value : key and value are never updated.
    // Token::cost : always updated.
    // Token::lid, Token::rid : updated iff the pos_type is neither
    //   FREQUENT_POS nor SAME_AS_PREV_POS.
    // Token::attributes : updated iff the value is SPELLING_COLLECTION.
    // TokenInfo::id_in_value_trie : updated iff the value_type is
    //   DEFAULT_VALUE.
    // Thus, by not-reseting Token instance intentionally, we can skip most
    //   SAME_AS_PREV operations.
    // The exception is Token::attributes. It is not-always set, so we need
    // reset it everytime.
    // This kind of structure should be packed in the codec or some
    // related but new class.
    var readBytes = 0
    if !codec.decodeToken(ptr, &tokenInfo, &readBytes) {
      state = .lastToken
    }
    ptr += readBytes

    // Fill remaining values.
    switch tokenInfo.valueType {
    case .defaultValue:
      tokenInfo.token.value = lookupValue(tokenInfo.idInValueTrie)
    case .sameAsPrevValue:
      assert(prevIdInValueTrie != -1)
      tokenInfo.idInValueTrie = prevIdInValueTrie
    // We can keep the current value here.
    case .asIsHiragana:
      tokenInfo.token.value = tokenInfo.token.key
    case .asIsKatakana:
      if !key.isEmpty && keyKatakana.isEmpty {
        keyKatakana = Japanese.hiraganaToKatakana(key)
      }
      tokenInfo.token.value = keyKatakana
    }

    if tokenInfo.accentEncodingType == .embeddedInToken {
      tokenInfo.token.value += "_\(tokenInfo.accentType)"
    }

    if tokenInfo.posType == .frequentPos {
      let pos = UInt32(littleEndian: frequentPos[tokenInfo.idInFrequentPosMap])
      tokenInfo.token.lid = UInt16(truncatingIfNeeded: pos >> 16)
      tokenInfo.token.rid = UInt16(truncatingIfNeeded: pos & 0xffff)
    }
  }
}
