// Port of mozc/src/rewriter/t13n_promotion_rewriter.{h,cc} (3.35.6354).
//
// Rewriter to promote transliteration(T13N) candidates for mobile devices.
// For mobile, we do not provide the shortcut to input T13N candidates.
// This rewriter promotes T13N candidate so that users can find them
// at first glance.
//
// Deviations from C++:
// - The `absl::flat_hash_set<absl::string_view>` of seen values is a set of
//   UTF-8 byte arrays (bytewise equality as in C++).

import GenmaiBase
import GenmaiProtocol

// The insertion offset for T13N candidates.
// Only one of Latin T13n candidates (width, case variants for Latin character
// keys) and katakana T13n candidates (Katakana variants for other keys) will
// be promoted.
private let kLatinT13nOffset = 3

private func isLatinInputMode(_ request: ConversionRequest) -> Bool {
  request.composer().getInputMode() == .halfAscii
    || request.composer().getInputMode() == .fullAscii
}

private let kLatinT13nTypes: [TransliterationType] = [
  .halfAscii,
  .halfAsciiUpper,
  .halfAsciiLower,
  .halfAsciiCapitalized,
  .fullAscii,
  .fullAsciiUpper,
  .fullAsciiLower,
  .fullAsciiCapitalized,
]

private func maybeInsertLatinT13n(_ segment: Segment) -> Bool {
  if segment.metaCandidatesSize <= TransliterationType.fullAsciiCapitalized.rawValue {
    return false
  }

  let insertPos = RewriterUtil.calculateInsertPosition(segment, kLatinT13nOffset)

  var seen = Set<[UInt8]>()
  for i in 0..<insertPos {
    seen.insert(Array(segment.candidate(i).value.utf8))
  }

  var pos = insertPos
  for t13nType in kLatinT13nTypes {
    let t13nCandidate = segment.metaCandidate(t13nType.rawValue)
    if !seen.insert(Array(t13nCandidate.value.utf8)).inserted {
      continue
    }
    segment.insertCandidate(pos)?.assign(from: t13nCandidate)
    pos += 1
  }
  return pos != insertPos
}

// Inserts or promote Katakana candidate at `insert_pos`.
// promotes Katakana candidate if `segment` already contains Katakana.
// Katakana candidate is searched from `start_offset`.
// When no Katakana is found, `katakana_candidate` is inserted.
private func insertKatakana(
  _ startOffset: Int, _ insertPos: Int, _ katakanaCandidate: Candidate, _ segment: Segment
) {
  var katakanaIndex = -1
  var i = startOffset
  while i < segment.candidatesSize {
    if segment.candidate(i).value.bytesEqual(katakanaCandidate.value) {
      katakanaIndex = i
      break
    }
    i += 1
  }

  if katakanaIndex >= 0 {
    segment.moveCandidate(katakanaIndex, insertPos)
  } else {
    segment.insertCandidate(insertPos)?.assign(from: katakanaCandidate)
  }
}

private func maybePromoteKatakanaWithStaticOffset(
  _ params: Genmai_Commands_DecoderExperimentParams, _ katakanaCandidate: Candidate,
  _ segment: Segment
) -> Bool {
  if params.katakanaPromotionOffset < 0 {
    return false
  }

  let katakanaT13nOffset = Int(params.katakanaPromotionOffset)

  // Katakana candidate already appears at lower than katakana_t13n_offset.
  for i in 0..<min(segment.candidatesSize, katakanaT13nOffset) {
    // No need to promote or insert.
    if segment.candidate(i).value.bytesEqual(katakanaCandidate.value) {
      return false
    }
  }

  let insertPos = RewriterUtil.calculateInsertPosition(segment, katakanaT13nOffset)

  insertKatakana(katakanaT13nOffset, insertPos, katakanaCandidate, segment)

  return true
}

private func maybePromoteKatakana(_ request: ConversionRequest, _ segment: Segment) -> Bool {
  if segment.metaCandidatesSize <= TransliterationType.fullKatakana.rawValue {
    return false
  }

  let params = request.request().decoderExperimentParams
  let katakanaCandidate = segment.metaCandidate(TransliterationType.fullKatakana.rawValue)

  return maybePromoteKatakanaWithStaticOffset(params, katakanaCandidate, segment)
}

private func maybePromoteT13n(_ request: ConversionRequest, _ segment: Segment) -> Bool {
  if isLatinInputMode(request) || Util.isAscii(segment.key) {
    return maybeInsertLatinT13n(segment)
  }
  return maybePromoteKatakana(request, segment)
}

public final class T13nPromotionRewriter: RewriterInterface {
  public init() {}

  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType {
    if request.request().mixedConversion {  // For mobile
      return .all
    } else {
      return .notAvailable
    }
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    var modified = false
    for segment in segments.conversionSegments {
      modified = maybePromoteT13n(request, segment) || modified
    }
    return modified
  }
}
