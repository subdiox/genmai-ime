// Port of mozc/src/dictionary/system/system_dictionary.{h,cc} (3.35.6354).
//
// System dictionary maintains following sections
//  (1) Key trie
//       Trie containing encoded key. Returns ids for lookup.
//       We can get the key using the id by performing reverse lookup
//       against the trie.
//  (2) Value trie
//       Trie containing encoded value. Returns ids for lookup.
//       We can get the value using the id by performing reverse lookup
//       against the trie.
//  (3) Token array
//       Array containing encoded tokens. Array index is the id in key trie.
//       Token contains cost, POS, the id in key trie, etc.
//  (4) Table for high frequent POS(left/right ID)
//       Frequenty appearing POSs are stored as POS ids in token info for
//       reducing binary size. This table is the map from the id to the
//       actual ids.
//
// Swift notes:
// - `SystemDictionary.Builder(filename:)` / `Builder(image:)` +
//   `setOptions(_:)` + `build() throws`. The dictionary keeps the mapped file /
//   the image owner alive; nothing is copied.
// - absl::btree_set<int> / btree_multimap<int, ...> are replaced by a Swift
//   Set iterated in sorted order and a dictionary of arrays kept in insertion
//   order (equal keys of a btree_multimap keep insertion order), so the
//   callback order is identical.
// - AtomicSharedPtr<ReverseLookupCache> is a Mutex around an
//   immutable cache object.
// - The ReverseLookupIndex stores its per-value-id result arrays in one flat
//   array with offsets (same contents and order as the C++ arrays).

import GenmaiBase
import GenmaiStorage
import Synchronization

private let kMinTokenArrayBlobSize = 4

// TODO(noriyukit): The following parameters may not be well optimized.  In our
// experiments, Select1 is computational burden, so increasing cache size for
// lb1/select1 may improve performance.
private let kKeyTrieLb0CacheSize = 1 * 1024
private let kKeyTrieLb1CacheSize = 1 * 1024
private let kKeyTrieSelect0CacheSize = 4 * 1024
private let kKeyTrieSelect1CacheSize = 4 * 1024
private let kKeyTrieTermvecCacheSize = 1 * 1024

private let kValueTrieLb0CacheSize = 1 * 1024
private let kValueTrieLb1CacheSize = 1 * 1024
private let kValueTrieSelect0CacheSize = 1 * 1024
private let kValueTrieSelect1CacheSize = 16 * 1024
private let kValueTrieTermvecCacheSize = 4 * 1024

// Expansion table format:
// "<Character to expand>[<Expanded character 1><Expanded character 2>...]"
//
// Only characters that will be encoded into 1-byte ASCII char are allowed in
// the table.
//
// Note that this implementation has potential issue that the key/values may
// be mixed.
// TODO(hidehiko): Clean up this hacky implementation.
private let kHiraganaExpansionTable: [String] = [
  "ああぁ", "いいぃ", "ううぅゔ", "ええぇ", "おおぉ", "かかが",
  "ききぎ", "くくぐ", "けけげ", "ここご", "ささざ", "ししじ",
  "すすず", "せせぜ", "そそぞ", "たただ", "ちちぢ", "つつっづ",
  "っっづ", "ててで", "ととど", "ははばぱ", "ひひびぴ", "ふふぶぷ",
  "へへべぺ", "ほほぼぽ", "ややゃ", "ゆゆゅ", "よよょ", "わわゎ",
]

private func buildHiraganaExpansionTable(_ codec: SystemDictionaryCodec, _ encodedTable: inout KeyExpansionTable) {
  for entry in kHiraganaExpansionTable {
    let encoded = codec.encodeKey(entry)
    assert(encoded.allSatisfy { $0 < 0x80 }, "Encoded expansion data are supposed to fit within ASCII")
    assert(!encoded.isEmpty, "Expansion data is empty")

    if encoded.count == 1 {
      continue
    } else {
      encodedTable.add(encoded[0], encoded[1...])
    }
  }
}

@inline(__always)
private func getTokenArrayPtr(_ tokenArray: BitVectorBasedArray, _ keyId: Int) -> UnsafePointer<UInt8> {
  tokenArray.get(keyId).baseAddress!.assumingMemoryBound(to: UInt8.self)
}

/// Creates a String from the first `length` bytes of `bytes` (a prefix that
/// ends at a character boundary).
@inline(__always)
private func makeString(_ bytes: UnsafeBufferPointer<UInt8>, _ length: Int) -> String {
  String(decoding: UnsafeBufferPointer(rebasing: bytes[0..<length]), as: UTF8.self)
}

// Iterator for scanning token array.
// This iterator does not return actual token info but returns
// id data and the position only.
// This will be used only for reverse lookup.
// Forward lookup does not need such iterator because it can access
// a token directly without linear scan.
private struct TokenScanIterator {
  struct Result {
    // Value id for the current token
    var valueId = -1
    // Index (= key id) for the current token
    var index = 0
    // Offset from the tokens section beginning.
    // (token_array_->Get(id_in_key_trie) ==
    //  token_array_->Get(0) + tokens_offset)
    var tokensOffset = 0
  }

  private enum State {
    case hasNext
    case done
  }

  private let codec: SystemDictionaryCodec
  private let encodedTokensPtr: UnsafePointer<UInt8>
  private let terminationFlag: UInt8
  private var state: State = .hasNext
  private(set) var result = Result()
  private var offset = 0
  private var tokensOffset = 0
  private var index = 0

  init(_ codec: SystemDictionaryCodec, _ tokenArray: BitVectorBasedArray) {
    self.codec = codec
    terminationFlag = codec.getTokensTerminationFlag()
    encodedTokensPtr = getTokenArrayPtr(tokenArray, 0)
    nextInternal()
  }

  func get() -> Result { result }

  func done() -> Bool { state == .done }

  mutating func next() {
    assert(state != .done)
    nextInternal()
  }

  private mutating func nextInternal() {
    if encodedTokensPtr[offset] == terminationFlag {
      state = .done
      return
    }
    var readBytes = 0
    result.valueId = -1
    result.index = index
    result.tokensOffset = tokensOffset
    let isLastToken = !codec.readTokenForReverseLookup(
      encodedTokensPtr + offset, &result.valueId, &readBytes)
    if isLastToken {
      var tokensSize = offset + readBytes - tokensOffset
      if tokensSize < kMinTokenArrayBlobSize {
        tokensSize = kMinTokenArrayBlobSize
      }
      tokensOffset += tokensSize
      index += 1
      offset = tokensOffset
    } else {
      offset += readBytes
    }
  }
}

private struct ReverseLookupResult: Sendable {
  // Offset from the tokens section beginning.
  // (token_array_.Get(id_in_key_trie) == token_array_.Get(0) + tokens_offset)
  var tokensOffset = -1
  // Id in key trie
  var idInKeyTrie = -1
}

/// `SystemDictionary::ReverseLookupCache`.
private final class ReverseLookupCache: @unchecked Sendable {
  // @unchecked Sendable: never mutated after it is published.
  var results: [Int: [ReverseLookupResult]] = [:]

  func isAvailable(_ idSet: Set<Int>) -> Bool {
    // std::all_of(x.begin(), x.end(), .. ) returns true if x is empty
    // regardless of the condition.
    idSet.allSatisfy { results[$0] != nil }
  }

  func emplace(_ id: Int, _ result: ReverseLookupResult) {
    results[id, default: []].append(result)
  }
}

/// `SystemDictionary::ReverseLookupIndex`.
private final class ReverseLookupIndex: Sendable {
  // results for value id i: flat[offsets[i]..<offsets[i + 1]]
  private let offsets: [Int]
  private let flat: [ReverseLookupResult]

  init(_ codec: SystemDictionaryCodec, _ tokenArray: BitVectorBasedArray) {
    // Gets id size.
    var valueIdMax = -1
    do {
      var iter = TokenScanIterator(codec, tokenArray)
      while !iter.done() {
        valueIdMax = Swift.max(valueIdMax, iter.get().valueId)
        iter.next()
      }
    }

    precondition(valueIdMax >= 0)
    let indexSize = valueIdMax + 1

    // Gets result size for each ids.
    var sizes = [Int](repeating: 0, count: indexSize)
    do {
      var iter = TokenScanIterator(codec, tokenArray)
      while !iter.done() {
        let result = iter.get()
        if result.valueId != -1 {
          sizes[result.valueId] += 1
        }
        iter.next()
      }
    }

    var offsets = [Int](repeating: 0, count: indexSize + 1)
    for i in 0..<indexSize {
      offsets[i + 1] = offsets[i] + sizes[i]
    }

    // Builds index.
    var flat = [ReverseLookupResult](repeating: ReverseLookupResult(), count: offsets[indexSize])
    var filled = [Int](repeating: 0, count: indexSize)
    do {
      var iter = TokenScanIterator(codec, tokenArray)
      while !iter.done() {
        let result = iter.get()
        if result.valueId != -1 {
          // Finds uninitialized result.
          let pos = offsets[result.valueId] + filled[result.valueId]
          flat[pos].tokensOffset = result.tokensOffset
          flat[pos].idInKeyTrie = result.index
          filled[result.valueId] += 1
        }
        iter.next()
      }
    }
    self.offsets = offsets
    self.flat = flat
  }

  func fillResultMap(_ idSet: Set<Int>, _ resultMap: ReverseLookupCache) {
    for id in idSet.sorted() {
      for i in offsets[id]..<offsets[id + 1] {
        resultMap.emplace(id, flat[i])
      }
    }
  }
}

private struct PredictiveLookupSearchState {
  var node = LoudsTrie.Node()
  var keyPos = 0
  var numExpanded = 0
}

/// Simple FIFO queue (std::queue) over an array.
private struct Queue<T> {
  private var items: [T] = []
  private var head = 0

  var isEmpty: Bool { head == items.count }

  mutating func push(_ x: T) { items.append(x) }

  mutating func pop() -> T {
    let x = items[head]
    head += 1
    return x
  }
}

private final class ReverseLookupCallbackWrapper: DictionaryCallback {
  let callback: any DictionaryCallback

  init(_ callback: any DictionaryCallback) {
    self.callback = callback
  }

  func onToken(_ key: String, _ actualKey: String, _ token: Token) -> DictionaryCallbackResult {
    var token = token
    swap(&token.key, &token.value)
    return callback.onToken(key, actualKey, token)
  }
}

/// `mozc::dictionary::SystemDictionary`.
public final class SystemDictionary: DictionaryInterface, @unchecked Sendable {
  // @unchecked Sendable: all lookup state is immutable after build(); the
  // reverse lookup cache is guarded by a lock.

  /// System dictionary options represented as bitwise enum.
  public struct Options: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let none: Options = []
    /// If ENABLE_REVERSE_LOOKUP_INDEX is set, we will have the index in heap
    /// from the id in value trie to the id in key trie.
    /// That consumes more memory but we can perform reverse lookup more quickly.
    public static let enableReverseLookupIndex = Options(rawValue: 1)
  }

  /// Builder class for system dictionary
  /// Usage:
  ///   let dictionary = try SystemDictionary.Builder(filename: path)
  ///       .setOptions(.none).build()
  public final class Builder {
    private enum Input {
      case filename(String)
      case image(DataView)
    }

    private let input: Input
    private var options: Options = .none

    /// Creates Builder from filename
    public init(filename: String) {
      input = .filename(filename)
    }

    /// Creates Builder from image (e.g. `DataManager.getSystemDictionaryData()`).
    public init(image: DataView) {
      input = .image(image)
    }

    /// Sets options (default: NONE)
    @discardableResult
    public func setOptions(_ options: Options) -> Builder {
      self.options = options
      return self
    }

    /// Builds and returns system dictionary.
    public func build() throws -> SystemDictionary {
      let instance = SystemDictionary(SystemDictionaryCodec(), DictionaryFileCodec())

      switch input {
      case .filename(let filename):
        try instance.dictionaryFile.openFromFile(filename)
      case .image(let image):
        // Make the dictionary not to be paged out.
        // We don't check the return value because the process doesn't necessarily
        // has the privilege to mlock.
        // Note that we don't munlock the space because it's always better to keep
        // the singleton system dictionary paged in as long as the process runs.
        if let base = image.baseAddress {
          _ = Mmap.maybeMLock(base, image.count)
        }
        try instance.dictionaryFile.openFromImage(image)
      }

      if !instance.openDictionaryFile(options.contains(.enableReverseLookupIndex)) {
        throw StatusError.unknown("Failed to create system dictionary")
      }

      return instance
    }
  }

  private let keyTrie = LoudsTrie()
  private let _valueTrie = LoudsTrie()
  private var tokenArray = BitVectorBasedArray()
  private var frequentPos = UnsafeBufferPointer<UInt32>(start: nil, count: 0)
  private let codec: SystemDictionaryCodec
  private let fileCodec: DictionaryFileCodec
  private var hiraganaExpansionTable = KeyExpansionTable()
  private let dictionaryFile: DictionaryFile
  /// Keeps the section images (and through them the mapped file / image
  /// owner) alive.
  private var sectionImages: [DataView] = []
  private let reverseLookupCache = Mutex<ReverseLookupCache?>(nil)
  private var reverseLookupIndex: ReverseLookupIndex?

  private init(_ codec: SystemDictionaryCodec, _ fileCodec: DictionaryFileCodec) {
    self.codec = codec
    self.fileCodec = fileCodec
    dictionaryFile = DictionaryFile(fileCodec)
  }

  public var valueTrie: LoudsTrie { _valueTrie }

  private func openDictionaryFile(_ enableReverseLookupIndex: Bool) -> Bool {
    guard let keyImage = dictionaryFile.getSection(codec.getSectionNameForKey()),
      let valueImage = dictionaryFile.getSection(codec.getSectionNameForValue()),
      let tokenImage = dictionaryFile.getSection(codec.getSectionNameForTokens()),
      let frequentPosImage = dictionaryFile.getSection(codec.getSectionNameForPos()),
      let keyBase = keyImage.baseAddress, let valueBase = valueImage.baseAddress,
      let tokenBase = tokenImage.baseAddress
    else {
      return false
    }
    sectionImages = [keyImage, valueImage, tokenImage, frequentPosImage]

    if !keyTrie.open(
      keyBase, kKeyTrieLb0CacheSize, kKeyTrieLb1CacheSize, kKeyTrieSelect0CacheSize,
      kKeyTrieSelect1CacheSize, kKeyTrieTermvecCacheSize)
    {
      GenmaiLog.error("cannot open key trie")
      return false
    }

    buildHiraganaExpansionTable(codec, &hiraganaExpansionTable)

    if !_valueTrie.open(
      valueBase, kValueTrieLb0CacheSize, kValueTrieLb1CacheSize, kValueTrieSelect0CacheSize,
      kValueTrieSelect1CacheSize, kValueTrieTermvecCacheSize)
    {
      GenmaiLog.error("can not open value trie")
      return false
    }

    tokenArray.open(tokenBase)
    frequentPos = frequentPosImage.span(UInt32.self).buffer

    if enableReverseLookupIndex {
      initReverseLookupIndex()
    }

    return true
  }

  private func initReverseLookupIndex() {
    if reverseLookupIndex != nil {
      return
    }
    reverseLookupIndex = ReverseLookupIndex(codec, tokenArray)
  }

  // MARK: - DictionaryInterface

  public func hasKey(_ key: String) -> Bool {
    keyTrie.hasKey(codec.encodeKey(key))
  }

  public func hasValue(_ value: String) -> Bool {
    if _valueTrie.hasKey(codec.encodeValue(value)) {
      return true
    }

    // Because Hiragana, Katakana and Alphabet words are not stored in the
    // value_trie for the data compression.  They are only stored in the
    // key_trie with flags.  So we also need to check the existence in
    // the key_trie.

    // Normalize the value as the key.  This process depends on the
    // implementation of SystemDictionaryBuilder::BuildValueTrie.
    let key = Japanese.katakanaToHiragana(value)

    let keyId = keyTrie.exactSearch(codec.encodeKey(key))
    if keyId == -1 {
      return false
    }

    // We need to check the contents of value_trie for Katakana values.
    // If (key, value) = (かな, カナ) is in the dictionary, "カナ" is
    // not used as a key for value_trie or key_trie.  Only "かな" is
    // used as a key for key_trie.  If we accept this limitation, we can
    // skip the following code.
    //
    // If we add "if (key == value) return true;" here, we can check
    // almost all cases of Hiragana and Alphabet words without the
    // following iteration.  However, when (mozc, MOZC) is stored but
    // (mozc, mozc) is NOT stored, HasValue("mozc") wrongly returns
    // true.

    // Get the block of tokens for this key.
    let encodedTokensPtr = getTokenArrayPtr(tokenArray, keyId)

    // Check tokens.
    var iter = TokenDecodeIterator(codec, _valueTrie, frequentPos, key, encodedTokensPtr)
    while !iter.done() {
      if value.bytesEqual(iter.token.value) {
        return true
      }
      iter.next()
    }
    return false
  }

  private func collectPredictiveNodesInBfsOrder(
    _ encodedKey: [UInt8], _ table: KeyExpansionTable, _ limit: Int,
    _ result: inout [PredictiveLookupSearchState]
  ) {
    var queue = Queue<PredictiveLookupSearchState>()
    queue.push(PredictiveLookupSearchState(node: LoudsTrie.Node(), keyPos: 0, numExpanded: 0))
    repeat {
      var state = queue.pop()

      // Update traversal state for |encoded_key| and its expanded keys.
      if state.keyPos < encodedKey.count {
        let targetChar = encodedKey[state.keyPos]
        let chars = table.expandKey(targetChar)

        keyTrie.moveToFirstChild(&state.node)
        while keyTrie.isValidNode(state.node) {
          let c = keyTrie.getEdgeLabelToParentNode(state.node)
          if chars.isHit(c) {
            let numExpanded = state.numExpanded + (c != targetChar ? 1 : 0)
            queue.push(
              PredictiveLookupSearchState(node: state.node, keyPos: state.keyPos + 1, numExpanded: numExpanded))
          }
          LoudsTrie.moveToNextSibling(&state.node)
        }
        continue
      }

      // Collect prediction keys (state.key_pos >= encoded_key.size()).
      if keyTrie.isTerminalNode(state.node) {
        result.append(state)
      }

      // Collected enough entries.  Collect all the remaining keys that have the
      // same length as the longest key.
      if result.count > limit {
        // The current key is the longest because of BFS property.
        let maxKeyLen = state.keyPos
        while !queue.isEmpty {
          state = queue.pop()
          if state.keyPos > maxKeyLen {
            // Key length in the queue is monotonically increasing because of BFS
            // property.  So we don't need to check all the elements in the queue.
            break
          }
          assert(state.keyPos == maxKeyLen)
          if keyTrie.isTerminalNode(state.node) {
            result.append(state)
          }
        }
        break
      }

      // Update traversal state for children.
      keyTrie.moveToFirstChild(&state.node)
      while keyTrie.isValidNode(state.node) {
        queue.push(
          PredictiveLookupSearchState(node: state.node, keyPos: state.keyPos + 1, numExpanded: state.numExpanded))
        LoudsTrie.moveToNextSibling(&state.node)
      }
    } while !queue.isEmpty
  }

  public func lookupPredictive(_ key: String, callback: any DictionaryCallback) {
    // Do nothing for empty key, although looking up all the entries with empty
    // string seems natural.
    if key.isEmpty {
      return
    }

    let encodedKey = codec.encodeKey(key)
    if encodedKey.count > LoudsTrie.kMaxDepth {
      return
    }

    let table =
      callback.isKanaModifierInsensitiveConversion()
      ? hiraganaExpansionTable : KeyExpansionTable.defaultInstance

    // TODO(noriyukit): Lookup limit should be implemented at caller side by using
    // callback mechanism.  This hard-coding limits the capability and generality
    // of dictionary module.  CollectPredictiveNodesInBfsOrder() and the following
    // loop for callback should be integrated for this purpose.
    let kLookupLimit = 64
    var result: [PredictiveLookupSearchState] = []
    result.reserveCapacity(kLookupLimit)
    collectPredictiveNodesInBfsOrder(encodedKey, table, kLookupLimit, &result)

    // Reused buffer inside the following loop.
    withUnsafeTemporaryAllocation(of: UInt8.self, capacity: LoudsTrie.kMaxDepth + 1) { buffer in
      let encodedActualKeyBuffer = buffer.baseAddress!
      outer: for state in result {
        // Computes the actual key.  For example:
        // key = "くー"
        // encoded_actual_key = encode("ぐーぐる")  [expanded]
        // encoded_actual_key_prediction_suffix = encode("ぐる")
        let encodedActualKey = keyTrie.restoreKeyString(state.node, encodedActualKeyBuffer)
        let suffixStart = Swift.min(encodedKey.count, encodedActualKey.count)
        let encodedActualKeyPredictionSuffix = UnsafeBufferPointer(
          rebasing: encodedActualKey[suffixStart...])

        // decoded_key = "くーぐる" (= key + prediction suffix)
        let decodedKey = key + codec.decodeKey(encodedActualKeyPredictionSuffix)
        switch callback.onKey(decodedKey) {
        case .traverseDone:
          return
        case .traverseNextKey:
          continue outer
        case .traverseCull:
          fatalError("Culling is not implemented.")
        case .traverseContinue:
          break
        }

        let actualKey: String
        if state.numExpanded > 0 {
          actualKey = codec.decodeKey(encodedActualKey)
        } else {
          actualKey = decodedKey
        }
        switch callback.onActualKey(decodedKey, actualKey, state.numExpanded) {
        case .traverseDone:
          return
        case .traverseNextKey:
          continue outer
        case .traverseCull:
          fatalError("Culling is not implemented.")
        case .traverseContinue:
          break
        }

        let keyId = keyTrie.getKeyIdOfTerminalNode(state.node)
        var iter = TokenDecodeIterator(
          codec, _valueTrie, frequentPos, actualKey, getTokenArrayPtr(tokenArray, keyId))
        while !iter.done() {
          // Note: TokenDecodeIterator reuses its internal Token instance
          // (especially token.value) across iterations when decoding tokens
          // with SAME_AS_PREV_VALUE; the callback receives a copy.
          let r = callback.onToken(decodedKey, actualKey, iter.token)
          if r == .traverseDone {
            return
          }
          if r == .traverseNextKey {
            break
          }
          assert(r != .traverseCull, "Not implemented")
          iter.next()
        }
      }
    }
  }

  // An implementation of prefix search without key expansion.  Runs |callback|
  // for prefixes of |encoded_key| in |key_trie|.
  // Args:
  //   key:
  //     The original key before applying codec.
  //   encoded_key:
  //     The encoded |key|.
  //   callback:
  //     A callback function to be called.
  //   token_filter:
  //     A functor of signature bool(const TokenInfo &).  Only tokens for which
  //     this functor returns true are passed to callback function.
  private func runCallbackOnEachPrefix(
    _ key: String, _ encodedKey: [UInt8], _ callback: any DictionaryCallback,
    _ tokenFilter: (TokenInfo) -> Bool
  ) {
    var key = key
    key.withUTF8 { keyBytes in
      encodedKey.withUnsafeBufferPointer { encodedKeyBytes in
        var node = LoudsTrie.Node()
        var i = 0
        while i < encodedKeyBytes.count {
          if !keyTrie.moveToChildByLabel(encodedKeyBytes[i], &node) {
            return
          }
          i += 1  // Increment here for next loop and |encoded_prefix| defined below.
          if !keyTrie.isTerminalNode(node) {
            continue
          }
          let encodedPrefix = UnsafeBufferPointer(rebasing: encodedKeyBytes[0..<i])
          let prefix = makeString(
            keyBytes, Swift.min(codec.getDecodedKeyLength(encodedPrefix), keyBytes.count))

          switch callback.onKey(prefix) {
          case .traverseDone, .traverseCull:
            return
          case .traverseNextKey:
            continue
          case .traverseContinue:
            break
          }

          switch callback.onActualKey(prefix, prefix, 0) {
          case .traverseDone, .traverseCull:
            return
          case .traverseNextKey:
            continue
          case .traverseContinue:
            break
          }

          let keyId = keyTrie.getKeyIdOfTerminalNode(node)
          var iter = TokenDecodeIterator(
            codec, _valueTrie, frequentPos, prefix, getTokenArrayPtr(tokenArray, keyId))
          while !iter.done() {
            let tokenInfo = iter.get()
            if !tokenFilter(tokenInfo) {
              iter.next()
              continue
            }
            let res = callback.onToken(prefix, prefix, tokenInfo.token)
            if res == .traverseDone || res == .traverseCull {
              return
            }
            if res == .traverseNextKey {
              break
            }
            iter.next()
          }
        }
      }
    }
  }

  // Recursive implementation of depth-first prefix search with key expansion.
  // Input parameters:
  //   key:
  //     The bytes of the original key before applying codec.
  //   encoded_key:
  //     The encoded |key|.
  //   table:
  //     Key expansion table.
  //   callback:
  //     A callback function to be called.
  // Parameters for recursion:
  //   node:
  //     Stores the current location in |key_trie_|.
  //   key_pos:
  //     Depth of node, i.e., encoded_key.substr(0, key_pos) is the current prefix
  //     for search.
  //   num_expanded:
  //     the number of chharacters expanded. if non zero, characters are expanded.
  //   actual_key_buffer:
  //     Buffer for storing actually used characters to reach this node, i.e.,
  //     absl::string_view(actual_key_buffer, key_pos) is the matched prefix using
  //     key expansion.
  private func lookupPrefixWithKeyExpansionImpl(
    _ key: UnsafeBufferPointer<UInt8>, _ encodedKey: UnsafeBufferPointer<UInt8>,
    _ table: KeyExpansionTable, _ callback: any DictionaryCallback, _ node: LoudsTrie.Node,
    _ keyPos: Int, _ numExpanded: Int, _ actualKeyBuffer: UnsafeMutablePointer<UInt8>
  ) -> DictionaryCallbackResult {
    // This do-block handles a terminal node and callback.  do-block is used to
    // break the block and continue to the subsequent traversal phase.
    terminal: do {
      if !keyTrie.isTerminalNode(node) {
        break terminal
      }

      let encodedPrefix = UnsafeBufferPointer(rebasing: encodedKey[0..<keyPos])
      let prefix = makeString(key, Swift.min(codec.getDecodedKeyLength(encodedPrefix), key.count))
      var result = callback.onKey(prefix)
      if result == .traverseDone || result == .traverseCull {
        return result
      }
      if result == .traverseNextKey {
        break terminal  // Go to the traversal phase.
      }

      let encodedActualPrefix = UnsafeBufferPointer(start: actualKeyBuffer, count: keyPos)
      let actualPrefix = codec.decodeKey(encodedActualPrefix)
      result = callback.onActualKey(prefix, actualPrefix, numExpanded)
      if result == .traverseDone || result == .traverseCull {
        return result
      }
      if result == .traverseNextKey {
        break terminal  // Go to the traversal phase.
      }

      let keyId = keyTrie.getKeyIdOfTerminalNode(node)
      var iter = TokenDecodeIterator(
        codec, _valueTrie, frequentPos, actualPrefix, getTokenArrayPtr(tokenArray, keyId))
      while !iter.done() {
        result = callback.onToken(prefix, actualPrefix, iter.token)
        if result == .traverseDone || result == .traverseCull {
          return result
        }
        if result == .traverseNextKey {
          break terminal  // Go to the traversal phase.
        }
        iter.next()
      }
    }

    // Traversal phase.
    if keyPos == encodedKey.count {
      return .traverseContinue
    }
    let currentChar = encodedKey[keyPos]
    let chars = table.expandKey(currentChar)
    var node = node
    keyTrie.moveToFirstChild(&node)
    while keyTrie.isValidNode(node) {
      let c = keyTrie.getEdgeLabelToParentNode(node)
      if chars.isHit(c) {
        actualKeyBuffer[keyPos] = c
        let result = lookupPrefixWithKeyExpansionImpl(
          key, encodedKey, table, callback, node, keyPos + 1,
          numExpanded + (c != currentChar ? 1 : 0), actualKeyBuffer)
        if result == .traverseDone {
          return .traverseDone
        }
      }
      LoudsTrie.moveToNextSibling(&node)
    }

    return .traverseContinue
  }

  public func lookupPrefix(_ key: String, callback: any DictionaryCallback) {
    let encodedKey = codec.encodeKey(key)

    if !callback.isKanaModifierInsensitiveConversion() {
      runCallbackOnEachPrefix(
        key, encodedKey, callback,
        // Select all tokens.
        { _ in true })
      return
    }

    var key = key
    key.withUTF8 { keyBytes in
      encodedKey.withUnsafeBufferPointer { encodedKeyBytes in
        withUnsafeTemporaryAllocation(
          of: UInt8.self, capacity: Swift.max(LoudsTrie.kMaxDepth, encodedKeyBytes.count) + 1
        ) { actualKeyBuffer in
          _ = lookupPrefixWithKeyExpansionImpl(
            keyBytes, encodedKeyBytes, hiraganaExpansionTable, callback, LoudsTrie.Node(), 0, 0,
            actualKeyBuffer.baseAddress!)
        }
      }
    }
  }

  public func lookupExact(_ key: String, callback: any DictionaryCallback) {
    // Find the key in the key trie.
    let keyId = keyTrie.exactSearch(codec.encodeKey(key))
    if keyId == -1 {
      return
    }
    if callback.onKey(key) != .traverseContinue {
      return
    }
    if callback.onActualKey(key, key, /* num_expanded= */ 0) != .traverseContinue {
      return
    }
    // Callback on each token.
    var iter = TokenDecodeIterator(codec, _valueTrie, frequentPos, key, getTokenArrayPtr(tokenArray, keyId))
    while !iter.done() {
      if callback.onToken(key, key, iter.token) != .traverseContinue {
        break
      }
      iter.next()
    }
  }

  public func lookupReverse(_ str: String, callback: any DictionaryCallback) {
    // 1st step: Hiragana/Katakana are not in the value trie
    // 2nd step: Reverse lookup in value trie
    let callbackWrapper = ReverseLookupCallbackWrapper(callback)
    registerReverseLookupTokensForT13N(str, callbackWrapper)
    registerReverseLookupTokensForValue(str, callbackWrapper)
  }

  private func addKeyIdsOfAllPrefixes(_ trie: LoudsTrie, _ key: [UInt8], _ keyIds: inout Set<Int>) {
    trie.prefixSearch(key) { _, _, trie, node in
      keyIds.insert(trie.getKeyIdOfTerminalNode(node))
    }
  }

  public func populateReverseLookupCache(_ str: String) {
    if reverseLookupIndex != nil {
      // We don't need to prepare cache for the current reverse conversion,
      // as we have already built the index for reverse lookup.
      return
    }

    let reverseLookupCache = ReverseLookupCache()

    // Iterate each suffix and collect IDs of all substrings.
    var idSet = Set<Int>()
    let bytes = Array(str.utf8)
    var pos = 0
    while pos < bytes.count {
      let lookupKey = codec.encodeValue(bytes: bytes[pos...])
      addKeyIdsOfAllPrefixes(_valueTrie, lookupKey, &idSet)
      pos += Strings.oneCharLen(bytes[pos])
    }
    // Collect tokens for all IDs.
    scanTokens(idSet, reverseLookupCache)

    self.reverseLookupCache.withLock { $0 = reverseLookupCache }
  }

  public func clearReverseLookupCache() {
    reverseLookupCache.withLock { $0 = nil }
  }

  private func registerReverseLookupTokensForT13N(_ value: String, _ callback: any DictionaryCallback) {
    let hiraganaValue = Japanese.katakanaToHiragana(value)
    let encodedKey = codec.encodeKey(hiraganaValue)
    runCallbackOnEachPrefix(hiraganaValue, encodedKey, callback) { tokenInfo in
      // Skip spelling corrections.
      if tokenInfo.token.attributes & Token.Attribute.spellingCorrection != 0 {
        return false
      }
      if tokenInfo.valueType != .asIsHiragana && tokenInfo.valueType != .asIsKatakana {
        // SAME_AS_PREV_VALUE may be t13n token.
        let prevValue = Japanese.katakanaToHiragana(tokenInfo.token.value)
        if !tokenInfo.token.key.bytesEqual(prevValue) {
          return false
        }
      }
      return true
    }
  }

  private func registerReverseLookupTokensForValue(_ value: String, _ callback: any DictionaryCallback) {
    let lookupKey = codec.encodeValue(value)

    var idSet = Set<Int>()
    addKeyIdsOfAllPrefixes(_valueTrie, lookupKey, &idSet)

    let results: ReverseLookupCache
    if let reverseLookupIndex {
      let nonCachedResults = ReverseLookupCache()
      reverseLookupIndex.fillResultMap(idSet, nonCachedResults)
      results = nonCachedResults
    } else if let cachedResults = reverseLookupCache.withLock({ $0 }), cachedResults.isAvailable(idSet) {
      results = cachedResults
    } else {
      // Cache is not available. Get token for each ID.
      let nonCachedResults = ReverseLookupCache()
      scanTokens(idSet, nonCachedResults)
      results = nonCachedResults
    }

    registerReverseLookupResults(idSet, results, callback)
  }

  private func scanTokens(_ idSet: Set<Int>, _ cache: ReverseLookupCache) {
    var iter = TokenScanIterator(codec, tokenArray)
    while !iter.done() {
      let result = iter.get()
      if result.valueId != -1 && idSet.contains(result.valueId) {
        cache.emplace(
          result.valueId, ReverseLookupResult(tokensOffset: result.tokensOffset, idInKeyTrie: result.index))
      }
      iter.next()
    }
  }

  private func registerReverseLookupResults(
    _ idSet: Set<Int>, _ cache: ReverseLookupCache, _ callback: any DictionaryCallback
  ) {
    let encodedTokensPtr = getTokenArrayPtr(tokenArray, 0)
    withUnsafeTemporaryAllocation(of: UInt8.self, capacity: LoudsTrie.kMaxDepth + 1) { buffer in
      for valueId in idSet.sorted() {
        guard let range = cache.results[valueId] else { continue }
        for reverseResult in range {
          let encodedKey = keyTrie.restoreKeyString(reverseResult.idInKeyTrie, buffer.baseAddress!)
          let tokensKey = codec.decodeKey(encodedKey)
          if callback.onKey(tokensKey) != .traverseContinue {
            continue
          }
          var iter = TokenDecodeIterator(
            codec, _valueTrie, frequentPos, tokensKey, encodedTokensPtr + reverseResult.tokensOffset)
          while !iter.done() {
            let tokenInfo = iter.get()
            if tokenInfo.token.attributes & Token.Attribute.spellingCorrection != 0
              || tokenInfo.idInValueTrie != valueId
            {
              iter.next()
              continue
            }
            _ = callback.onToken(tokensKey, tokensKey, tokenInfo.token)
            iter.next()
          }
        }
      }
    }
  }
}
