// Port of mozc/src/dictionary/system/system_dictionary_builder.{h,cc}
// (3.35.6354).
//
// Swift notes:
// - The absl flags become instance properties:
//   `minKeyLengthToUseSmallCostEncoding` (FLAGS_min_key_length_to_use_small_cost_encoding,
//   default 6) and `preserveIntermediateDictionary`
//   (FLAGS_preserve_intermediate_dictionary, default false).
// - `WriteToStream` is `writeToBytes(intermediateOutputFileBasePath:)`.
// - Input tokens are taken by value (C++ takes `Token*`); the builder only reads
//   them.
// - All string comparisons / hash keys are bytewise as in C++.

import GenmaiBase
import GenmaiStorage

public final class SystemDictionaryBuilder {
  /// Represents words info for a certain key(=reading).
  public struct KeyInfo {
    /// id of the key(=reading) string in key trie
    public var idInKeyTrie = -1
    public var key = ""
    public var tokens: [TokenInfo] = []
  }

  typealias KeyInfoList = [KeyInfo]

  /// FLAGS_min_key_length_to_use_small_cost_encoding: minimum key length to use
  /// 1 byte cost encoding.
  public var minKeyLengthToUseSmallCostEncoding = 6
  /// FLAGS_preserve_intermediate_dictionary: preserve inetemediate dictionary
  /// file.
  public var preserveIntermediateDictionary = false

  private let valueTrieBuilder = LoudsTrieBuilder()
  private let keyTrieBuilder = LoudsTrieBuilder()
  private let tokenArrayBuilder = BitVectorBasedArrayBuilder()

  /// mapping from {left_id, right_id} to POS index (0--255)
  private var frequentPos: [UInt32: Int] = [:]

  private let codec: SystemDictionaryCodec
  private let fileCodec: DictionaryFileCodec

  public init(
    codec: SystemDictionaryCodec = SystemDictionaryCodec(), fileCodec: DictionaryFileCodec = DictionaryFileCodec()
  ) {
    self.codec = codec
    self.fileCodec = fileCodec
  }

  public func buildFromTokens(_ tokens: [Token]) {
    var keyInfoList = readTokens(tokens)

    buildFrequentPos(keyInfoList)
    buildValueTrie(keyInfoList)
    buildKeyTrie(keyInfoList)

    setIdForValue(&keyInfoList)
    setIdForKey(&keyInfoList)
    sortTokenInfo(&keyInfoList)
    setCostType(&keyInfoList)
    setPosType(&keyInfoList)
    setValueType(&keyInfoList)

    buildTokenArray(keyInfoList)
  }

  public func writeToFile(_ outputFile: String) throws {
    let image = writeToBytes(intermediateOutputFileBasePath: outputFile)
    try FileUtil.setContents(outputFile, image)
  }

  /// `WriteToStream`: returns the dictionary file image.
  public func writeToBytes(intermediateOutputFileBasePath: String = "") -> [UInt8] {
    // Memory images of each section
    var sections: [DictionaryFileSection] = []
    let valueTrieSection = DictionaryFileSection(
      image: DataView(copying: valueTrieBuilder.image),
      name: fileCodec.getSectionName(codec.getSectionNameForValue()))
    sections.append(valueTrieSection)

    let keyTrieSection = DictionaryFileSection(
      image: DataView(copying: keyTrieBuilder.image),
      name: fileCodec.getSectionName(codec.getSectionNameForKey()))
    sections.append(keyTrieSection)

    let tokenArraySection = DictionaryFileSection(
      image: DataView(copying: tokenArrayBuilder.image),
      name: fileCodec.getSectionName(codec.getSectionNameForTokens()))
    sections.append(tokenArraySection)

    var frequentPosArray = [UInt32](repeating: 0, count: 256)
    for (pos, index) in frequentPos {
      frequentPosArray[index] = pos
    }
    var frequentPosBytes: [UInt8] = []
    frequentPosBytes.reserveCapacity(256 * 4)
    for v in frequentPosArray {
      withUnsafeBytes(of: v.littleEndian) { frequentPosBytes.append(contentsOf: $0) }
    }
    let frequentPosSection = DictionaryFileSection(
      image: DataView(copying: frequentPosBytes),
      name: fileCodec.getSectionName(codec.getSectionNameForPos()))
    sections.append(frequentPosSection)

    if preserveIntermediateDictionary && !intermediateOutputFileBasePath.isEmpty {
      // Write out intermediate results to files.
      let basepath = intermediateOutputFileBasePath
      GenmaiLog.info("Writing intermediate files.")
      Self.writeSectionToFile(valueTrieSection, basepath + ".value")
      Self.writeSectionToFile(keyTrieSection, basepath + ".key")
      Self.writeSectionToFile(tokenArraySection, basepath + ".tokens")
      Self.writeSectionToFile(frequentPosSection, basepath + ".freq_pos")
    }

    GenmaiLog.info("Start writing dictionary file.")
    let image = fileCodec.writeSections(sections)
    GenmaiLog.info("Start writing dictionary file... done.")
    return image
  }

  private static func writeSectionToFile(_ section: DictionaryFileSection, _ filename: String) {
    do {
      try FileUtil.setContents(filename, section.image.array)
    } catch {
      GenmaiLog.error("Cannot write a section to \(filename)")
    }
  }

  // MARK: - Helpers

  @inline(__always)
  private static func getCombinedPos(_ lid: UInt16, _ rid: UInt16) -> UInt32 {
    (UInt32(lid) << 16) | UInt32(rid)
  }

  private static func getValueType(_ token: Token) -> TokenInfo.ValueType {
    if token.value.bytesEqual(token.key) {
      return .asIsHiragana
    }
    let katakana = Japanese.hiraganaToKatakana(token.key)
    if token.value.bytesEqual(katakana) {
      return .asIsKatakana
    }
    return .defaultValue
  }

  private static func hasHomonymsInSamePos(_ keyInfo: KeyInfo) -> Bool {
    // Early exit path mainly for performance.
    if keyInfo.tokens.count == 1 {
      return false
    }

    var seen = Set<UInt32>()
    for tokenInfo in keyInfo.tokens {
      let token = tokenInfo.token
      let pos = getCombinedPos(token.lid, token.rid)
      if !seen.insert(pos).inserted {
        // Insertion failed, which means we already have |pos|.
        return true
      }
    }
    return false
  }

  private static func hasHeterophones(_ keyInfo: KeyInfo, _ heteronymValues: Set<[UInt8]>) -> Bool {
    for tokenInfo in keyInfo.tokens where heteronymValues.contains(Array(tokenInfo.token.value.utf8)) {
      return true
    }
    return false
  }

  /// std::stable_sort with a strict weak ordering.
  private static func stableSorted<T>(_ items: [T], by less: (T, T) -> Bool) -> [T] {
    let order = items.indices.sorted { a, b in
      if less(items[a], items[b]) { return true }
      if less(items[b], items[a]) { return false }
      return a < b
    }
    return order.map { items[$0] }
  }

  // MARK: - Steps

  private func readTokens(_ tokens: [Token]) -> KeyInfoList {
    // Check if all the key values are nonempty.
    for token in tokens {
      precondition(!token.key.isEmpty, "empty key string in input")
      precondition(!token.value.isEmpty, "empty value string in input")
    }

    // Create KeyInfoList in two steps.
    // 1. Create an array of Token with (stably) sorting Token::key.
    //    [Token 1(key:aaa)][Token 2(key:aaa)][Token 3(key:abc)][...]
    // 2. Group Token(s) by Token::Key and convert them into KeyInfo.
    //    [KeyInfo(key:aaa)[Token 1][Token 2]][KeyInfo(key:abc)[Token 3]][...]

    // Step 1.
    let sorted = Self.stableSorted(tokens) { l, r in l.key.bytesLess(r.key) }

    // Step 2.
    var keyInfoList: KeyInfoList = []
    guard let first = sorted.first else {
      return keyInfoList
    }
    var lastKeyInfo = KeyInfo()
    lastKeyInfo.key = first.key
    for token in sorted {
      if !lastKeyInfo.key.bytesEqual(token.key) {
        keyInfoList.append(lastKeyInfo)
        lastKeyInfo = KeyInfo()
        lastKeyInfo.key = token.key
      }
      var tokenInfo = TokenInfo(token)
      tokenInfo.valueType = Self.getValueType(token)
      lastKeyInfo.tokens.append(tokenInfo)
    }
    keyInfoList.append(lastKeyInfo)
    return keyInfoList
  }

  private func buildFrequentPos(_ keyInfoList: KeyInfoList) {
    // Calculate the frequency of each POS.
    // TODO(toshiyuki): It might be better to count frequency
    // with considering same_as_prev_pos.
    var posMap: [UInt32: Int] = [:]
    for keyInfo in keyInfoList {
      for tokenInfo in keyInfo.tokens {
        let token = tokenInfo.token
        posMap[Self.getCombinedPos(token.lid, token.rid), default: 0] += 1
      }
    }

    // Get histgram of frequency.
    var freqMap: [Int: Int] = [:]
    for (_, freq) in posMap {
      freqMap[freq, default: 0] += 1
    }

    // Compute the lower threshold of frequency.
    var numFreqPos = 0
    var freqThreshold = Int(Int32.max)
    for freq in freqMap.keys.sorted(by: >) {
      let count = freqMap[freq]!
      if numFreqPos + count > 255 {
        break
      }
      freqThreshold = freq
      numFreqPos += count
    }

    // Collect high frequent pos.
    var freqPosIdx = 0
    for combinedPos in posMap.keys.sorted() {
      let freq = posMap[combinedPos]!
      if freq >= freqThreshold {
        frequentPos[combinedPos] = freqPosIdx
        freqPosIdx += 1
      }
    }
    precondition(freqPosIdx == numFreqPos, "inconsistent result to find frequent pos")
  }

  private func buildValueTrie(_ keyInfoList: KeyInfoList) {
    for keyInfo in keyInfoList {
      for tokenInfo in keyInfo.tokens {
        if tokenInfo.valueType == .asIsHiragana || tokenInfo.valueType == .asIsKatakana {
          // These values will be stored in token array as flags
          continue
        }
        valueTrieBuilder.add(codec.encodeValue(tokenInfo.token.value))
      }
    }
    valueTrieBuilder.build()
  }

  private func setIdForValue(_ keyInfoList: inout KeyInfoList) {
    for i in keyInfoList.indices {
      for j in keyInfoList[i].tokens.indices {
        let valueStr = codec.encodeValue(keyInfoList[i].tokens[j].token.value)
        keyInfoList[i].tokens[j].idInValueTrie = valueTrieBuilder.getId(valueStr)
      }
    }
  }

  private func sortTokenInfo(_ keyInfoList: inout KeyInfoList) {
    for i in keyInfoList.indices {
      keyInfoList[i].tokens = Self.stableSorted(keyInfoList[i].tokens) { lhs, rhs in
        // Note lid/rid: the order is swapped.
        // std::tie(rhs.lid, rhs.rid, lhs.id_in_value_trie, lhs.attributes) <
        // std::tie(lhs.lid, lhs.rid, rhs.id_in_value_trie, rhs.attributes)
        if rhs.token.lid != lhs.token.lid { return rhs.token.lid < lhs.token.lid }
        if rhs.token.rid != lhs.token.rid { return rhs.token.rid < lhs.token.rid }
        if lhs.idInValueTrie != rhs.idInValueTrie { return lhs.idInValueTrie < rhs.idInValueTrie }
        return lhs.token.attributes < rhs.token.attributes
      }
    }
  }

  private func setCostType(_ keyInfoList: inout KeyInfoList) {
    // Values that have multiple keys.
    var heterophoneValues = Set<[UInt8]>()
    do {
      // value → reading
      var seenReadingMap: [[UInt8]: [UInt8]] = [:]
      for keyInfo in keyInfoList {
        for tokenInfo in keyInfo.tokens {
          let token = tokenInfo.token
          let value = Array(token.value.utf8)
          if heterophoneValues.contains(value) {
            continue
          }
          let key = Array(token.key.utf8)
          guard let seen = seenReadingMap[value] else {
            seenReadingMap[value] = key
            continue
          }
          if seen == key {
            continue
          }
          heterophoneValues.insert(value)
        }
      }
    }

    let minKeyLen = minKeyLengthToUseSmallCostEncoding
    for i in keyInfoList.indices {
      if Strings.charsLen(keyInfoList[i].key) < minKeyLen {
        // Do not use small cost encoding for short keys.
        continue
      }
      if Self.hasHomonymsInSamePos(keyInfoList[i]) {
        continue
      }
      if Self.hasHeterophones(keyInfoList[i], heterophoneValues) {
        // We want to keep the cost order for LookupReverse().
        continue
      }

      for j in keyInfoList[i].tokens.indices {
        if keyInfoList[i].tokens[j].token.cost < 0x100 {
          // Small cost encoding ignores lower 8 bits.
          continue
        }
        keyInfoList[i].tokens[j].costType = .canUseSmallEncoding
      }
    }
  }

  private func setPosType(_ keyInfoList: inout KeyInfoList) {
    for i in keyInfoList.indices {
      for j in keyInfoList[i].tokens.indices {
        let token = keyInfoList[i].tokens[j].token
        let pos = Self.getCombinedPos(token.lid, token.rid)
        if let id = frequentPos[pos] {
          keyInfoList[i].tokens[j].posType = .frequentPos
          keyInfoList[i].tokens[j].idInFrequentPosMap = id
        }
        if j >= 1 {
          let prevToken = keyInfoList[i].tokens[j - 1].token
          let prevPos = Self.getCombinedPos(prevToken.lid, prevToken.rid)
          if prevPos == pos {
            // we can overwrite FREQUENT_POS
            keyInfoList[i].tokens[j].posType = .sameAsPrevPos
          }
        }
      }
    }
  }

  private func setValueType(_ keyInfoList: inout KeyInfoList) {
    for i in keyInfoList.indices {
      var j = 1
      while j < keyInfoList[i].tokens.count {
        let prevTokenInfo = keyInfoList[i].tokens[j - 1]
        let tokenInfo = keyInfoList[i].tokens[j]
        if tokenInfo.valueType != .asIsHiragana && tokenInfo.valueType != .asIsKatakana
          && tokenInfo.token.value.bytesEqual(prevTokenInfo.token.value)
        {
          keyInfoList[i].tokens[j].valueType = .sameAsPrevValue
        }
        j += 1
      }
    }
  }

  private func buildKeyTrie(_ keyInfoList: KeyInfoList) {
    for keyInfo in keyInfoList {
      keyTrieBuilder.add(codec.encodeKey(keyInfo.key))
    }
    keyTrieBuilder.build()
  }

  private func setIdForKey(_ keyInfoList: inout KeyInfoList) {
    for i in keyInfoList.indices {
      keyInfoList[i].idInKeyTrie = keyTrieBuilder.getId(codec.encodeKey(keyInfoList[i].key))
    }
  }

  private func buildTokenArray(_ keyInfoList: KeyInfoList) {
    // Here we make a reverse lookup table as follows:
    //   |key_info_list[X].id_in_key_trie| -> |key_info_list[X]|
    // assuming |key_info_list[X].id_in_key_trie| is unique and successive.
    do {
      var idToKeyinfoTable = [Int](repeating: -1, count: keyInfoList.count)
      for (i, keyInfo) in keyInfoList.enumerated() {
        idToKeyinfoTable[keyInfo.idInKeyTrie] = i
      }

      for i in idToKeyinfoTable {
        tokenArrayBuilder.add(codec.encodeTokens(keyInfoList[i].tokens))
      }
    }

    tokenArrayBuilder.add([codec.getTokensTerminationFlag()])
    tokenArrayBuilder.build()
  }
}
