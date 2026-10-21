// Port of mozc/src/storage/louds/louds_trie_builder.{h,cc} (3.35.6354).
//
// Words are byte sequences ([UInt8]); they are sorted by unsigned byte order,
// which is std::string's ordering.

public final class LoudsTrieBuilder {
  private var built = false
  private var wordList: [[UInt8]] = []
  private var idList: [Int] = []
  private var imageBytes: [UInt8] = []

  public init() {}

  /// Adds the word to the builder. It is necessary to call this method,
  /// before build invocation.
  public func add(_ word: [UInt8]) {
    precondition(!built)
    precondition(!word.isEmpty)
    wordList.append(word)
  }

  public func add(_ word: some StringProtocol) {
    add(Array(word.utf8))
  }

  /// Builds the trie image.
  public func build() {
    precondition(!built)

    // Initialize for the build. Sort and de-dup the words.
    wordList.sort { $0.lexicographicallyPrecedes($1) }
    var unique: [[UInt8]] = []
    unique.reserveCapacity(wordList.count)
    for word in wordList where unique.last != word {
      unique.append(word)
    }
    wordList = unique
    // A pair of word and its original index in the (sorted) word_list_; here
    // the word is referenced through the index.
    var entryList = Array(wordList.indices)
    idList = [Int](repeating: -1, count: wordList.count)

    // Output the tree to streams.
    var trieStream = BitStream()
    var terminalStream = BitStream()
    var edgeCharacter: [UInt8] = []

    // Push root.
    trieStream.pushBit(1)
    trieStream.pushBit(0)
    edgeCharacter.append(0)
    terminalStream.pushBit(0)

    // Then, traverse the sorted word list.
    // The basic concept to output the trie is simple:
    // - Iterate the depth beginning with 0.
    // - If the entry is the first one in the word list, the corresponding
    //   node should be newly created.
    // - If the prefix[0:depth] (inclusive) is different from the previous
    //   entry (if exists), the corresponding node should be newly created.
    // - Otherwise, the node should be shared with the previous entry.
    // So, if it turned out that we need to create a new node, just output '1'
    // for LOUDS to represent an "edge," output the corresponding character,
    // and output a bit representing whether the node is terminal or not.
    // In addition, output the 'id' of the word.
    //
    // Then we check if we need to output '0' for LOUDS as the stop bit of
    // a node. It should be done when the entry is the last child of its
    // parent.
    // - If the entry is the last one in the word list, it should be the last
    //   child of its parent.
    // - If the prefix[0:depth) (exclusive, i.e. [0:depth - 1] inclusive) is
    //   different from the next entry (if exists), it should be the last child
    //   of its parent.
    // - Otherwise, the node is not the last child of its parent, because it
    //   is shared with the next entry.
    //
    // Finally, to keep the pre-condition of above algorithms, we remove
    // entries which we already output.
    //
    // Here, there is an issue. Considering a very simple case; only 'a' is in
    // the word list.
    // At first, output '1' to LOUDS stream, and 'a' to the edge character.
    // Also as it is the terminal, output '1' to the terminal stream and
    // store the id '0'.
    // Then, as 'a' is the last entry, output '0' to the LOUDS stream.
    // Then 'a' is removed since it has already been output as a terminal node.
    // Now, look at the LOUDS stream, it's '10'. However, '100' is expected,
    // because the child node also needs stop bit '0' as a leaf.
    // To achieve this, we keep entries which are output as terminals one more
    // depth, and skip "edge check" for the entries.
    // This doesn't break the edge check condition, and stop bit check
    // condition, but adds a chance to output stop bits for leaves.
    var id = 0
    var depth = 0
    while !entryList.isEmpty {
      for i in 0..<entryList.count {
        let word = wordList[entryList[i]]
        if word.count > depth
          && (i == 0
            || !Self.prefixEqual(word, wordList[entryList[i - 1]], depth + 1))
        {
          // This is the first string of this node. Output an edge.
          trieStream.pushBit(1)
          edgeCharacter.append(word[depth])

          if word.count == depth + 1 {
            // This is a terminal node.
            // Note that the terminal string should be at the first of
            // strings sharing the node. So the check above should work well.
            terminalStream.pushBit(1)
            idList[entryList[i]] = id
            id += 1
          } else {
            // This is not a terminal node.
            terminalStream.pushBit(0)
          }
        }

        if i == entryList.count - 1
          || !Self.prefixEqual(word, wordList[entryList[i + 1]], depth)
        {
          // This is the last child (string) for the parent.
          trieStream.pushBit(0)
        }
      }

      // Remove all terminal strings.
      entryList.removeAll { wordList[$0].count < depth + 1 }
      depth += 1
    }

    // Set 32-bits alignment.
    trieStream.fillPadding32()
    terminalStream.fillPadding32()

    // Output
    pushInt32(trieStream.byteSize, &imageBytes)
    pushInt32(terminalStream.byteSize, &imageBytes)
    // The num bits of each character annotated to each edge.
    pushInt32(8, &imageBytes)
    pushInt32(edgeCharacter.count, &imageBytes)

    imageBytes.append(contentsOf: trieStream.image)
    imageBytes.append(contentsOf: terminalStream.image)
    imageBytes.append(contentsOf: edgeCharacter)

    built = true
  }

  /// Returns the binary image of the trie.
  public var image: [UInt8] {
    precondition(built)
    return imageBytes
  }

  /// Returns the key_id for the word (-1 if not found).
  /// Note: in Mozc, the key_id will be used to build additional data
  /// related to the built LoudsTrie.
  public func getId(_ word: [UInt8]) -> Int {
    precondition(built)

    // Binary search the word.
    var lo = 0
    var hi = wordList.count
    while lo < hi {
      let mid = (lo + hi) / 2
      if wordList[mid].lexicographicallyPrecedes(word) {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    if lo == wordList.count || wordList[lo] != word {
      // Not found.
      return -1
    }
    return idList[lo]
  }

  public func getId(_ word: some StringProtocol) -> Int {
    getId(Array(word.utf8))
  }

  /// `a.compare(0, n, b, 0, n) == 0`: the first (at most) n bytes are equal.
  private static func prefixEqual(_ a: [UInt8], _ b: [UInt8], _ n: Int) -> Bool {
    a.prefix(n).elementsEqual(b.prefix(n))
  }
}
