// Port of mozc/src/rewriter/english_variants_rewriter.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - The private helpers used by the test peer are `internal` so that the
//   tests can call them through `@testable import`.
// - `absl::flat_hash_set<std::string>` is `Set<[UInt8]>` (bytewise identity).

import GenmaiBase
import GenmaiProtocol

public final class EnglishVariantsRewriter: RewriterInterface {
  private let posMatcher: PosMatcher

  public init(_ posMatcher: PosMatcher) {
    self.posMatcher = posMatcher
  }

  // Add space-prefixed variants to enable Space-joined English words
  // conversion. 'Google Japan' consists of 'ぐーぐる': 'Google', and
  // 'じゃぱん': 'Japan' Therefore, when a user types 'ぐーぐるじゃぱん', it will
  // be 'GoogleJapan' instead. To avoid this, in non-first segments which follow
  // english word segments, add these space-prefixed candidates.
  func expandSpacePrefixedVariants(_ input: some StringProtocol, _ variants: inout [String]) -> Bool {
    if input.isEmpty {
      return false
    }
    if input.utf8.first == UInt8(ascii: " ") {
      return false
    }
    var spacePrefixedVariants: [String] = []
    spacePrefixedVariants.append(" " + input)
    for word in variants {
      if word.isEmpty {
        continue
      }
      if word.utf8.first != UInt8(ascii: " ") {
        spacePrefixedVariants.append(word)
        spacePrefixedVariants.append(" " + word)
      } else {
        spacePrefixedVariants.append(word)
      }
    }
    // replace the content of variants
    variants = spacePrefixedVariants
    return true
  }

  func expandEnglishVariants(_ input: some StringProtocol, _ variants: inout [String]) -> Bool {
    if input.isEmpty {
      return false
    }

    // multi-word
    if input.utf8.contains(UInt8(ascii: " ")) {
      return false
    }

    var lower = String(input)
    var upper = String(input)
    var capitalized = String(input)
    Util.lowerString(&lower)
    Util.upperString(&upper)
    Util.capitalizeString(&capitalized)

    if lower.bytesEqual(upper) {
      // given word is non-ascii.
      return false
    }

    variants.removeAll()
    // If |input| is non-standard expression, like "iMac", only
    // expand lowercase.
    if !input.bytesEqual(lower) && !input.bytesEqual(upper) && !input.bytesEqual(capitalized) {
      variants.append(lower)
      return true
    }

    if !input.bytesEqual(lower) {
      variants.append(lower)
    }
    if !input.bytesEqual(capitalized) {
      variants.append(capitalized)
    }
    if !input.bytesEqual(upper) {
      variants.append(upper)
    }

    return true
  }

  func isT13NCandidate(_ candidate: Candidate) -> Bool {
    Util.isEnglishTransliteration(candidate.contentValue)
      && Util.getScriptType(candidate.contentKey) == .hiragana
  }

  func isEnglishCandidate(_ candidate: Candidate) -> Bool {
    Util.isEnglishTransliteration(candidate.contentValue)
      && Util.getScriptType(candidate.contentKey) == .alphabet
  }

  func expandEnglishVariantsWithSegment(_ needSpacePrefix: Bool, _ seg: Segment) -> Bool {
    var modified = false
    var expandedT13nCandidates = Set<[UInt8]>()
    var originalCandidates = Set<[UInt8]>()

    for i in 0..<seg.candidatesSize {
      originalCandidates.insert(Array(seg.candidate(i).value.utf8))
    }

    var i = seg.candidatesSize - 1
    while i >= 0 {
      defer { i -= 1 }
      let originalCandidate = seg.mutableCandidate(i)

      // http://b/issue?id=5137299
      // If the entry is coming from user dictionary,
      // expand English variants.
      if (originalCandidate.attributes & Attribute.noVariantsExpansion) != 0
        && (originalCandidate.attributes & Attribute.userDictionary) == 0
      {
        continue
      }

      if isT13NCandidate(originalCandidate) {
        if (originalCandidate.attributes & Attribute.noVariantsExpansion) == 0 {
          modified = true
          originalCandidate.attributes |= Attribute.noVariantsExpansion
        }

        if expandedT13nCandidates.contains(Array(originalCandidate.value.utf8)) {
          continue
        }

        let isProperNoun =
          originalCandidate.lid == originalCandidate.rid
          && posMatcher.isUniqueNoun(originalCandidate.lid)
        if isProperNoun && Util.isUpperAscii(originalCandidate.value) {
          // We do not have to expand upper case proper nouns (ex. NASA).
          // Note:
          // It is very popular that some company or service name is written in
          // lower case, but their formal form is capital case (ex. google)
          // so we suppress expansion only for capital case here.
          continue
        }

        // Expand T13N candidate variants
        var variants: [String] = []
        var expanded = expandEnglishVariants(originalCandidate.contentValue, &variants)
        if needSpacePrefix {
          expanded =
            expandSpacePrefixedVariants(originalCandidate.contentValue, &variants) || expanded
        }
        if expanded {
          precondition(!variants.isEmpty)
          for variant in variants.reversed() {
            let newValue = variant + originalCandidate.functionalValue
            expandedT13nCandidates.insert(Array(newValue.utf8))
            if originalCandidates.contains(Array(newValue.utf8)) {
              continue
            }
            modified = true

            guard let newCandidate = seg.insertCandidate(i + 1) else { continue }
            newCandidate.value = newValue
            newCandidate.key = originalCandidate.key
            newCandidate.contentValue = variant
            newCandidate.contentKey = originalCandidate.contentKey
            newCandidate.cost = originalCandidate.cost
            newCandidate.wcost = originalCandidate.wcost
            newCandidate.structureCost = originalCandidate.structureCost
            newCandidate.lid = originalCandidate.lid
            newCandidate.rid = originalCandidate.rid
            newCandidate.attributes |= Attribute.noVariantsExpansion
            if (originalCandidate.attributes & Attribute.partiallyKeyConsumed) != 0 {
              newCandidate.attributes |= Attribute.partiallyKeyConsumed
              newCandidate.consumedKeySize = originalCandidate.consumedKeySize
            }
          }
        }
      } else if isEnglishCandidate(originalCandidate) {
        // Fix variants for English candidate
        modified = true
        originalCandidate.attributes |= Attribute.noVariantsExpansion
      }
    }

    return modified
  }

  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType {
    if request.request().mixedConversion {
      return .all
    }
    return .conversion
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    let params = request.request().decoderExperimentParams
    // 1: enable space insertion
    let enableSpaceInsersion = params.englishVariationSpaceInsertionMode == 1
    var modified = false
    var isPreviousCandidateEnglish = false
    for segment in segments.conversionSegments {
      // if the top candidate of previous segment is an english word,
      // need_space_prefix = true
      let needSpacePrefix = enableSpaceInsersion && isPreviousCandidateEnglish
      modified = expandEnglishVariantsWithSegment(needSpacePrefix, segment) || modified
      isPreviousCandidateEnglish =
        segment.candidatesSize > 0
        && Util.isScriptType(segment.candidate(0).value, .alphabet)
    }

    return modified
  }
}
