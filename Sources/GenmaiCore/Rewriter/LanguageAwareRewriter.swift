// Port of mozc/src/rewriter/language_aware_rewriter.{h,cc} (3.35.6354).

import GenmaiBase
import GenmaiProtocol

private func isMobileRequest(_ request: ConversionRequest) -> Bool {
  request.request().zeroQuerySuggestion && request.request().mixedConversion
}

private func isRomanHiraganaInput(_ request: ConversionRequest) -> Bool {
  let table = request.request().specialRomanjiTable
  switch table {
  case .defaultTable:
    return request.config().preeditMethod == .roman
  case .qwertyMobileToHiragana:
    return true
  default:
    return false
  }
}

private func isEnabled(_ request: ConversionRequest) -> Bool {
  let mode = request.request().languageAwareInput
  if mode == .noLanguageAwareInput {
    return false
  }
  if mode == .languageAwareSuggestion {
    return isRomanHiraganaInput(request)
  }
  assert(mode == .defaultLanguageAwareBehavior)
  return request.config().useSpellingCorrection
}

private func isRawQuery(
  _ composer: ComposerData, _ dictionary: any DictionaryInterface, _ rank: inout Int
) -> Bool {
  let rawText = composer.getRawString()

  // Check if the length of text is less than or equal to three.
  // For example, "cat" is not treated as a raw query so far to avoid
  // false negative cases.
  if rawText.utf8.count <= 3 {
    return false
  }

  // If the composition string is same with the raw_text, there is no
  // need to add the candidate to suggestions.
  let composition = composer.getStringForPreedit()
  if composition.bytesEqual(rawText) {
    return false
  }

  // If the composition string is the full width form of the raw_text,
  // there is no need to add the candidate to suggestions.
  let compositionInHalfWidthAscii = Japanese.fullWidthAsciiToHalfWidthAscii(composition)
  if compositionInHalfWidthAscii.bytesEqual(rawText) {
    return false
  }

  // If alphabet characters are in the middle of the composition, it is
  // probably a raw query.  For example, "えぁｍｐぇ" (example) contains
  // "m" and "p" in the middle.  So it is treated as a raw query.  On the
  // other hand, "くえｒｙ" (query) contains alphabet characters, but they
  // are at the end of the string, so it cannot be determined here.
  //
  // Note, GetQueryForPrediction omits the trailing alphabet characters of
  // the composition string and returns it.
  let key = composer.getQueryForPrediction()
  if Util.containsScriptType(key, .alphabet) {
    rank = 0
    return true
  }

  // If the composition is storead as a key in the dictionary like
  // "はな" (hana), "たけ" (take), the query is not handled as a raw query.
  // It is a little conservative, but a safer way.
  if dictionary.hasKey(key) {
    return false
  }

  // If the input text is stored in the dictionary, it is perhaps a raw query.
  // For example, the input characters of "れもヴぇ" (remove) is in the
  // dictionary, so it is treated as a raw text.
  if dictionary.hasValue(rawText) {
    rank = 2
    return true
  }

  return false
}

// Get T13n candidate ids from existing candidates.
private func getAlphabetIds(_ segment: Segment, _ lid: inout UInt16, _ rid: inout UInt16) {
  for i in 0..<segment.candidatesSize {
    let candidate = segment.candidate(i)
    let type = Util.getScriptType(candidate.value)
    if type == .alphabet {
      lid = candidate.lid
      rid = candidate.rid
      return
    }
  }
}

public final class LanguageAwareRewriter: RewriterInterface {
  private let unknownId: UInt16
  private let dictionary: any DictionaryInterface

  public init(_ posMatcher: PosMatcher, _ dictionary: any DictionaryInterface) {
    unknownId = posMatcher.getUnknownId()
    self.dictionary = dictionary
  }

  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType {
    // Language aware input is performed only on suggestion or prediction.
    if !isEnabled(request) {
      return .notAvailable
    }

    return [.suggestion, .prediction]
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    if !isEnabled(request) {
      return false
    }
    return fillRawText(request, segments)
  }

  // Note: This function seemed slow, but the benchmark tests
  // resulted that it was only less than 0.1% point penalty.
  // = session_handler_benchmark_test
  // BM_PerformanceForRandomKeyEvents: 891944807 -> 892740748 (1.00089)
  // = converter_benchmark_test
  // BM_DesktopAnthyCorpusConversion 25062440090 -> 25101542382 (1.002)
  // BM_DesktopStationPredictionCorpusPrediction 8695341697 -> 8672187681 (0.997)
  // BM_DesktopStationPredictionCorpusSuggestion 6149502840 -> 6152393270 (1.000)
  /// Fills the raw text if the query does not look like Japanese.
  private func fillRawText(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    if segments.conversionSegmentsSize != 1 {
      return false
    }

    var rank = 0
    if !isRawQuery(request.composer(), dictionary, &rank) {
      return false
    }

    let segment = segments.mutableConversionSegment(0)

    // Language aware candidates are useful on desktop as users may forget
    // switching the IME. However, on mobile software keyboard, such mistakes do
    // rarely occur, so we can fix the position for the sake of consistency.
    if isMobileRequest(request) {
      rank = 2
      // Do no insert the new candidate over the typing corrections.
      while rank < segment.candidatesSize {
        if segment.candidate(rank).attributes & Attribute.typingCorrection == 0 {
          break
        }
        rank += 1
      }
    }

    let rawString = request.composer().getRawString()

    var lid = unknownId
    var rid = unknownId
    getAlphabetIds(segment, &lid, &rid)

    // Create a candidate.
    if rank > segment.candidatesSize {
      rank = segment.candidatesSize
    }
    guard let candidate = segment.insertCandidate(rank) else { return false }
    candidate.value = rawString
    candidate.key = rawString
    candidate.contentValue = rawString
    candidate.contentKey = rawString
    candidate.lid = lid
    candidate.rid = rid

    candidate.attributes |= (Attribute.noVariantsExpansion | Attribute.noExtraDescription)

    return true
  }
}
