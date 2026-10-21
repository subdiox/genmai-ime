// Port of mozc/src/rewriter/single_kanji_rewriter.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - The rewriter holds the `PosMatcher` (a value type) and a reference to the
//   `SingleKanjiDictionary` instead of C++ references.

import GenmaiBase
import GenmaiProtocol

public final class SingleKanjiRewriter: RewriterInterface {
  private let posMatcher: PosMatcher
  private let singleKanjiDictionary: SingleKanjiDictionary

  public init(_ posMatcher: PosMatcher, _ singleKanjiDictionary: SingleKanjiDictionary) {
    self.posMatcher = posMatcher
    self.singleKanjiDictionary = singleKanjiDictionary
  }

  private static func insertNounPrefix(
    _ posMatcher: PosMatcher, _ segment: Segment, _ entries: Slice<SerializedDictionary>
  ) {
    assert(!entries.isEmpty)

    if segment.candidatesSize == 0 {
      // LOG(WARNING) << "candidates_size is 0";
      return
    }

    if segment.segmentType == .fixedValue {
      return
    }

    let candidateKey = !segment.key.isEmpty ? segment.key : segment.candidate(0).key
    for entry in entries {
      // Note:
      // The entry "cost" of noun_prefix_dictionary is "0" or "1".
      // Please refer to: mozc/rewriter/gen_single_kanji_noun_prefix_data.cc
      //
      // NOTE: faithful to the C++ operator precedence, the expression is
      // `(cost + (attributes & CONTEXT_SENSITIVE)) ? 1 : 0`.
      let sum = Int(entry.cost) + Int(segment.candidate(0).attributes & Attribute.contextSensitive)
      let insertPos = RewriterUtil.calculateInsertPosition(segment, sum != 0 ? 1 : 0)
      let c = segment.insertCandidate(insertPos)!
      c.lid = posMatcher.getNounPrefixId()
      c.rid = posMatcher.getNounPrefixId()
      c.cost = 5000
      c.contentValue = entry.value
      c.key = candidateKey
      c.contentKey = candidateKey
      c.value = entry.value
      c.attributes |= Attribute.contextSensitive
      c.attributes |= Attribute.noVariantsExpansion
    }
  }

  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType {
    if request.request().mixedConversion {
      return .all
    }
    return .conversion
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    if !request.config().useSingleKanjiConversion {
      // MOZC_VLOG(2) << "no use_single_kanji_conversion";
      return false
    }
    if request.request().mixedConversion && request.requestType() != .conversion {
      // MOZC_VLOG(2) << "single kanji prediction is enabled";
      // Single kanji entries are populated in the predictor when mixed
      // conversion mode, so we only sets the description of single kanji.
      for segment in segments.conversionSegments {
        addDescriptionForExistingCandidates(segment)
      }
      return true
    }

    var modified = false
    let conversionSegments = segments.conversionSegments
    let segmentsSize = conversionSegments.count
    let isSingleSegment = (segmentsSize == 1)
    let useSvs =
      (request.request().decoderExperimentParams.variationCharacterTypes
        & UInt32(Genmai_Commands_DecoderExperimentParams.VariationCharacterType.svsJapanese.rawValue))
      != 0
    for segment in conversionSegments {
      addDescriptionForExistingCandidates(segment)

      let kanjiList = singleKanjiDictionary.lookupKanjiEntries(segment.key, useSvs)
      if kanjiList.isEmpty {
        continue
      }
      modified =
        insertCandidate(isSingleSegment, posMatcher.getGeneralSymbolId(), kanjiList, segment)
        || modified
    }

    // Tweak for noun prefix.
    // TODO(team): Ideally, this issue can be fixed via the language model
    // and dictionary generation.
    var i = 0
    while i < segmentsSize {
      defer { i += 1 }
      let segment = conversionSegments[i]
      if segment.candidatesSize == 0 {
        continue
      }

      if i + 1 < segmentsSize {
        let rightCandidate = conversionSegments[i + 1].candidate(0)
        // right segment must be a noun.
        if !posMatcher.isContentNoun(rightCandidate.lid) {
          continue
        }
      } else if segmentsSize != 1 {  // also apply if segments_size == 1.
        continue
      }

      let key = segment.key
      let range = singleKanjiDictionary.lookupNounPrefixEntries(key)
      if range.isEmpty {
        continue
      }
      SingleKanjiRewriter.insertNounPrefix(posMatcher, segment, range)
      // Ignore the next noun content word.
      i += 1
      modified = true
    }

    return modified
  }

  // Add single kanji variants description to existing candidates,
  // because if we have candidates with same value, the lower ranked candidate
  // will be removed.
  private func addDescriptionForExistingCandidates(_ segment: Segment) {
    for i in 0..<segment.candidatesSize {
      let cand = segment.mutableCandidate(i)
      if !cand.description.isEmpty {
        continue
      }
      if let description = singleKanjiDictionary.generateDescription(cand.value) {
        cand.description = description
      }
    }
  }

  // Insert SingleKanji into segment.
  private func insertCandidate(
    _ isSingleSegment: Bool, _ singleKanjiId: UInt16, _ kanjiList: [String], _ segment: Segment
  ) -> Bool {
    assert(!kanjiList.isEmpty)
    if segment.candidatesSize == 0 {
      // LOG(WARNING) << "candidates_size is 0";
      return false
    }

    let candidateKey = !segment.key.isEmpty ? segment.key : segment.candidate(0).key

    // Adding 8000 to the single kanji cost
    // Note that this cost does not make no effect.
    // Here we set the cost just in case.
    let kOffsetCost = 8000

    // Append single-kanji
    for i in 0..<kanjiList.count {
      let c = segment.pushBackCandidate()
      fillCandidate(candidateKey, kanjiList[i], kOffsetCost + i, singleKanjiId, c)
    }
    return true
  }

  private func fillCandidate(
    _ key: String, _ value: String, _ cost: Int, _ singleKanjiId: UInt16, _ cand: Candidate
  ) {
    cand.lid = singleKanjiId
    cand.rid = singleKanjiId
    cand.cost = Int32(truncatingIfNeeded: cost)
    cand.contentKey = key
    cand.contentValue = value
    cand.key = key
    cand.value = value
    cand.attributes |= Attribute.contextSensitive
    cand.attributes |= Attribute.noVariantsExpansion
    if let description = singleKanjiDictionary.generateDescription(value) {
      cand.description = description
    }
  }
}
