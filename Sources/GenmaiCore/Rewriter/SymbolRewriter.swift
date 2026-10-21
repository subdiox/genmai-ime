// Port of mozc/src/rewriter/symbol_rewriter.{h,cc} (3.35.6354).
//
// SymbolRewriter:
// 1. Update data/symbol/symbol.tsv
// 2. Run gen_symbol_rewriter_dictionary_main in this directory
// 3. Make sure symbol_rewriter_data.h is correct
//
// Deviations from C++:
// - `RewriteEntireCandidate` / `RewriteEachCandidate` are `internal` (the C++
//   test peer calls `RewriteEachCandidate`).
// - `SerializedDictionary::IterRange` is a `Range<Int>` of entry indices.

import GenmaiBase
import GenmaiProtocol

public final class SymbolRewriter: RewriterInterface {
  private let dictionary: SerializedDictionary

  public init(_ tokenArrayData: DataView, _ stringArrayData: DataView) {
    assert(SerializedDictionary.verifyData(tokenArrayData, stringArrayData))
    dictionary = SerializedDictionary(tokenArray: tokenArrayData, stringArrayData: stringArrayData)
  }

  /// `std::make_from_tuple<SymbolRewriter>(GetSymbolRewriterData())`.
  public convenience init(_ data: (tokenArray: DataView, stringArray: DataView)) {
    self.init(data.tokenArray, data.stringArray)
  }

  // MARK: - Helpers (anonymous namespace)

  private static let kOffsetForSymbolKey = 1

  private static func getOffset(_ request: ConversionRequest, _ key: some StringProtocol) -> Int {
    let isSymbolKey = Util.charsLen(key) == 1 && Util.isScriptType(key, .unknownScript)

    if request.request().mixedConversion && isSymbolKey {
      // Some software keyboard layouts have very limited space for candidates.
      // We want to show symbol variants as many as possible for symbol key
      // input. Without this hack, candidate list might be filled with
      // prediction results and users would not be able to find symbol
      // candidates.
      return kOffsetForSymbolKey
    }
    // size_t conversion of an int32 field: a negative value becomes a huge
    // offset (clamped to the end of the candidates by the callers).
    let position = Int(request.request().decoderExperimentParams.symbolRewriterCandidatePosition)
    return position >= 0 ? position : Int.max / 2
  }

  // Some characters may have different description for full/half width forms.
  // Here we just change the description in this function.
  // If the symbol has description and additional description,
  // Return merged description.
  // TODO(taku): allow us to define two descriptions in *.tsv file
  private static func getDescription(
    _ value: some StringProtocol, _ description: String, _ additionalDescription: String
  ) -> String {
    if description.isEmpty {
      return ""
    }
    // Merge description
    if additionalDescription.isEmpty {
      return description
    }
    return description + "(" + additionalDescription + ")"
  }

  // return true key has no-hiragana
  private static func isSymbol(_ key: some StringProtocol) -> Bool {
    for scalar in key.unicodeScalars {
      let codepoint = scalar.value
      if codepoint >= 0x3041 && codepoint <= 0x309F {  // hiragana
        return false
      }
    }
    return true
  }

  // Insert alternative form of space.
  private static func expandSpace(_ segment: Segment) {
    func insertCandidate(_ base: Int, _ value: String) {
      let c = Candidate(copying: segment.candidate(base))
      c.value = value
      c.contentValue = value
      // Boundary is invalidated and unnecessary for space.
      c.innerSegmentBoundary.removeAll()
      segment.insertCandidate(base + 1, c)
    }

    let kHalfWidthSpace = " "  // U+0020
    let kFullWidthSpace = "　"  // U+3000
    for i in 0..<segment.candidatesSize {
      if segment.candidate(i).value.bytesEqual(kHalfWidthSpace) {
        insertCandidate(i, kFullWidthSpace)
        return
      } else if segment.candidate(i).value.bytesEqual(kFullWidthSpace) {
        insertCandidate(i, kHalfWidthSpace)
        return
      }
    }
  }

  // Return true if two symbols are in same group
  private static func inSameSymbolGroup(
    _ lhs: SerializedDictionary.Entry, _ rhs: SerializedDictionary.Entry
  ) -> Bool {
    // "矢印記号", "矢印記号"
    // "ギリシャ(大文字)", "ギリシャ(小文字)"
    let lhsDescription = lhs.description
    let rhsDescription = rhs.description
    if lhsDescription.isEmpty || rhsDescription.isEmpty {
      return false
    }
    return lhsDescription.bytesEqual(rhsDescription)
  }

  // Add symbol desc to existing candidates
  private static func addDescForCurrentCandidates(
    _ dictionary: SerializedDictionary, _ range: Range<Int>, _ segment: Segment
  ) {
    for i in 0..<segment.candidatesSize {
      let candidate = segment.mutableCandidate(i)
      let fullWidthValue = JapaneseUtil.halfWidthToFullWidth(candidate.value)
      let halfWidthValue = JapaneseUtil.fullWidthToHalfWidth(candidate.value)

      for j in range {
        let entry = dictionary[j]
        let value = entry.value
        if candidate.value.bytesEqual(value) || fullWidthValue.bytesEqual(value)
          || halfWidthValue.bytesEqual(value)
        {
          candidate.description = getDescription(
            candidate.value, entry.description, entry.additionalDescription)
          break
        }
      }
    }
  }

  private static let kSpecialKanaVariants = ["変体仮名", "濁点付き仮名", "鼻濁音", "アイヌ語カナ"]

  private static func isRareSymbolForDemotion(
    _ key: some StringProtocol, _ entry: SerializedDictionary.Entry
  ) -> Bool {
    // Special Kana variants are rarely used and should always be the bottom
    // not to be shown over the single kanji.
    // TODO(taku): Consider demoting other rare symbols.

    let description = entry.description
    // Demote Hieroglyphs symbols when user doesn't explicitly want
    // Hieroglyphs.
    if containsBytes(description, "ヒエログリフ") && !key.bytesEqual("ひえろぐりふ") {
      return true
    }

    return kSpecialKanaVariants.contains { containsBytes(description, $0) }
  }

  /// `absl::StrContains` (bytewise).
  private static func containsBytes(_ haystack: String, _ needle: String) -> Bool {
    let h = Array(haystack.utf8)
    let n = Array(needle.utf8)
    if n.isEmpty { return true }
    if n.count > h.count { return false }
    for start in 0...(h.count - n.count) where h[start] == n[0] {
      if h[start..<(start + n.count)].elementsEqual(n) {
        return true
      }
    }
    return false
  }

  // Insert Symbol into segment.
  private static func insertCandidates(
    _ candidateKey: String, _ convertedSegmentCount: Int, _ defaultOffset: Int,
    _ promotionSize: Int32, _ dictionary: SerializedDictionary, _ range: Range<Int>,
    _ contextSensitive: Bool, _ segment: Segment
  ) {
    if segment.candidatesSize == 0 {
      // LOG(WARNING) << "candidates_size is 0";
      return
    }

    // work around for space.
    // space is not expanded in ExpandAlternative because it is not registered
    // in CharacterFormManager.
    // We do not want to make the form of spaces configurable, so we do not
    // register space to CharacterFormManager.
    expandSpace(segment)

    // If the original candidates given by ImmutableConverter already
    // include the target symbols, do assign description to these candidates.
    addDescForCurrentCandidates(dictionary, range, segment)

    var offset = 0

    // If the key is "かおもじ", set the insert position at the bottom,
    // giving priority to emoticons inserted by EmoticonRewriter.
    if candidateKey.bytesEqual("かおもじ") {
      offset = segment.candidatesSize
    } else if convertedSegmentCount > 1 {
      // Multi-segment symbol (e.g. ->, <->, !=, ー>) should be boosted directly
      // to default_offset (0) without skipping single-character candidates.
      offset = defaultOffset
    } else {
      // Find the position where we start to insert the symbols
      // We want to skip the single-kanji we inserted by single-kanji rewriter.
      // We also skip transliterated key candidates.
      offset = RewriterUtil.calculateInsertPosition(segment, defaultOffset)
      var i = offset
      while i < segment.candidatesSize {
        let targetValue = segment.candidate(i).value
        if (Util.charsLen(targetValue) == 1 && Util.isScriptType(targetValue, .kanji))
          || Util.isScriptType(targetValue, .hiragana)
          || Util.isScriptType(targetValue, .katakana)
        {
          offset += 1
        } else {
          break
        }
        i += 1
      }
    }

    let baseCandidate = segment.candidate(0)
    func createCandidate(_ entry: SerializedDictionary.Entry) -> Candidate {
      let candidate = Candidate()
      candidate.lid = entry.lid
      candidate.rid = entry.rid
      candidate.cost = baseCandidate.cost
      candidate.structureCost = baseCandidate.structureCost
      candidate.value = entry.value
      candidate.contentValue = candidate.value
      candidate.key = candidateKey
      candidate.contentKey = candidateKey
      candidate.convertedSegmentCount = UInt32(truncatingIfNeeded: convertedSegmentCount)

      if contextSensitive {
        candidate.attributes |= Attribute.contextSensitive
      }

      // The first two consist of two characters but the one of characters
      // doesn't have alternative character.
      if candidate.value.bytesEqual("“”") || candidate.value.bytesEqual("‘’")
        || candidate.value.bytesEqual("w") || candidate.value.bytesEqual("www")
      {
        candidate.attributes |= Attribute.noVariantsExpansion
      }
      candidate.category = .symbol

      candidate.description = getDescription(
        candidate.value, entry.description, entry.additionalDescription)
      return candidate
    }

    let rangeSize = range.count
    var candidates: [Candidate] = []
    candidates.reserveCapacity(rangeSize)
    var iter = range.lowerBound
    while iter != range.upperBound {
      let entry = dictionary[iter]
      // The `range` is ordered by the preference, once the `iter` is
      // categorized as a rare symbol, the rest of candidates are also handled
      // as rare symbols
      if isRareSymbolForDemotion(candidateKey, entry) {
        break
      }

      candidates.append(createCandidate(entry))

      let insertedCount = candidates.count
      if insertedCount < Int(promotionSize)
        // If number of rest symbols is small, insert current position.
        // (size_t arithmetic: never negative here since inserted_count <=
        // range_size.)
        || rangeSize - insertedCount < 5
      {
        iter += 1
        continue
      }

      // Do not divide symbols which seem to be in the same group.
      let next = iter + 1
      if next != range.upperBound && inSameSymbolGroup(entry, dictionary[next]) {
        iter += 1
        continue
      }

      break
    }
    segment.insertCandidates(offset, candidates)
    if iter == range.upperBound {
      return
    }

    // Insert to latter position
    candidates.removeAll()
    while iter != range.upperBound {
      candidates.append(createCandidate(dictionary[iter]))
      iter += 1
    }
    segment.insertCandidates(segment.candidatesSize, candidates)
  }

  private static func lookup(_ dictionary: SerializedDictionary, _ key: some StringProtocol)
    -> Range<Int>
  {
    // Normalize the key to half-width and lowercase.
    var normalizedKey = Japanese.fullWidthAsciiToHalfWidthAscii(key)
    Util.lowerString(&normalizedKey)
    return dictionary.equalRange(normalizedKey)
  }

  // MARK: - SymbolRewriter

  // Insert symbols using single segment.
  func rewriteEachCandidate(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    var modified = false
    let promotionSize = request.request().decoderExperimentParams.symbolRewriterPromotionSize
    for segment in segments.conversionSegments {
      let key = segment.key
      let range = SymbolRewriter.lookup(dictionary, key)
      if range.isEmpty {
        continue
      }

      // if key is symbol, no need to see the context
      let contextSensitive = !SymbolRewriter.isSymbol(key)

      SymbolRewriter.insertCandidates(
        key, 1, SymbolRewriter.getOffset(request, key), promotionSize, dictionary, range,
        contextSensitive, segment)

      modified = true
    }

    return modified
  }

  // Insert symbols using connected all segments.
  func rewriteEntireCandidate(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    let segmentsSize = segments.conversionSegmentsSize
    if segmentsSize == 0 {
      return false
    }

    let enableMultiSegment = request.request().decoderExperimentParams.enableMultiSegmentCandidate
    if !enableMultiSegment && segmentsSize != 1 {
      return false
    }

    let key = enableMultiSegment ? request.key() : segments.conversionSegment(0).key
    let range = SymbolRewriter.lookup(dictionary, key)
    if range.isEmpty {
      return false
    }

    let promotionSize = request.request().decoderExperimentParams.symbolRewriterPromotionSize
    let convertedSegmentCount = enableMultiSegment ? segmentsSize : 1
    // Multi-segment symbols (e.g., "->", "!=") should be boosted to the top
    // (offset 0) so that the candidate is immediately visible. For
    // single-segment symbols, use the default offset to avoid demoting regular
    // candidates.
    let offset = convertedSegmentCount > 1 ? 0 : SymbolRewriter.getOffset(request, key)
    SymbolRewriter.insertCandidates(
      key, convertedSegmentCount, offset, promotionSize, dictionary, range,
      false,  // not context sensitive
      segments.mutableConversionSegment(0))
    return true
  }

  public func checkResizeSegmentsRequest(_ request: ConversionRequest, _ segments: Segments)
    -> Rewriter.ResizeSegmentsRequest?
  {
    if request.request().decoderExperimentParams.enableMultiSegmentCandidate {
      return nil
    }

    if segments.conversionSegmentsSize <= 1 {
      return nil
    }

    if segments.resized {
      // The given segments are resized by user so don't modify anymore.
      return nil
    }

    var key = ""
    for segment in segments.conversionSegments {
      key += segment.key
    }

    let keyLen = Util.charsLen(key)
    if keyLen > Int(UInt8.max) {
      return nil
    }
    let segmentSize = UInt8(keyLen)

    let range = SymbolRewriter.lookup(dictionary, key)
    if range.isEmpty {
      return nil
    }

    return Rewriter.ResizeSegmentsRequest(
      segmentIndex: 0, segmentSizes: [segmentSize, 0, 0, 0, 0, 0, 0, 0])
  }

  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType {
    if request.request().mixedConversion {
      return .all
    }
    return .conversion
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    if !request.config().useSymbolConversion {
      // MOZC_VLOG(2) << "no use_symbol_conversion";
      return false
    }

    // apply entire candidate first, as we want to
    // find character combinations first, e.g.,
    // "－＞" -> "→"
    return rewriteEntireCandidate(request, segments) || rewriteEachCandidate(request, segments)
  }
}
