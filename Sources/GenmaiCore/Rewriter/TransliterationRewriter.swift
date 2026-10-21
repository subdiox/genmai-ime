// Port of mozc/src/rewriter/transliteration_rewriter.{h,cc} (3.35.6354).

import GenmaiBase
import GenmaiProtocol

public final class TransliterationRewriter: RewriterInterface {
  private let unknownId: UInt16

  public init(_ posMatcher: PosMatcher) {
    unknownId = posMatcher.getUnknownId()
  }

  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType {
    // For mobile, mixed conversion is on.  In this case t13n rewrite should be
    // triggered anytime.
    if request.request().mixedConversion {
      return .all
    }

    // Otherwise t13n rewrite is triggered only on conversion.
    return .conversion
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    if request.options().skipSlowRewriters {
      return false
    }

    var modified = false
    if isComposerApplicable(request, segments) {
      modified = fillT13nsFromComposer(request, segments) || modified
    } else {
      modified = fillT13nsFromKey(segments) || modified
    }
    modified = addRawNumberT13nCandidates(request, segments) || modified

    return modified
  }

  private func fillT13nsFromComposer(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    // If the size of conversion_segments is one, and the cursor is at
    // the end of the composition, the key for t13n should be equal to
    // the composition string.
    if segments.conversionSegmentsSize == 1
      && request.composer().getLength() == request.composer().getCursor()
    {
      var t13ns: Transliterations = []
      request.composer().getTransliterations(&t13ns)
      let segment = segments.mutableConversionSegment(0)
      modifyT13ns(request, segment, &t13ns)
      let key = request.composer().getQueryForConversion()
      return setTransliterations(t13ns, key, segment)
    }

    var modified = false
    var compositionPos = 0
    for segment in segments.conversionSegments {
      let compositionLen = segment.keyLen
      if compositionLen == 0 {
        continue
      }
      var t13ns: Transliterations = []
      request.composer().getSubTransliterations(compositionPos, compositionLen, &t13ns)
      compositionPos += compositionLen

      modifyT13ns(request, segment, &t13ns)
      modified = setTransliterations(t13ns, segment.key, segment) || modified
    }
    return modified
  }

  // This function is used for a fail-safe.
  // Ambiguities of roman rule are ignored here.
  // ('n' or 'nn' for "ん", etc)
  private func fillT13nsFromKey(_ segments: Segments) -> Bool {
    var modified = false
    for segment in segments.conversionSegments {
      if segment.key.isEmpty {
        continue
      }
      let hiragana = segment.key
      let fullKatakana = Japanese.hiraganaToKatakana(hiragana)
      let ascii = Japanese.hiraganaToRomanji(hiragana)
      let halfAscii = Japanese.fullWidthAsciiToHalfWidthAscii(ascii)
      let fullAscii = Japanese.halfWidthAsciiToFullWidthAscii(halfAscii)
      let halfKatakana = Japanese.fullWidthToHalfWidth(fullKatakana)
      var halfAsciiUpper = halfAscii
      var halfAsciiLower = halfAscii
      var halfAsciiCapitalized = halfAscii
      Util.upperString(&halfAsciiUpper)
      Util.lowerString(&halfAsciiLower)
      Util.capitalizeString(&halfAsciiCapitalized)
      var fullAsciiUpper = fullAscii
      var fullAsciiLower = fullAscii
      var fullAsciiCapitalized = fullAscii
      Util.upperString(&fullAsciiUpper)
      Util.lowerString(&fullAsciiLower)
      Util.capitalizeString(&fullAsciiCapitalized)

      var t13ns = Transliterations(repeating: "", count: TransliterationType.numT13nTypes)
      t13ns[TransliterationType.hiragana.rawValue] = hiragana
      t13ns[TransliterationType.fullKatakana.rawValue] = fullKatakana
      t13ns[TransliterationType.halfKatakana.rawValue] = halfKatakana
      t13ns[TransliterationType.halfAscii.rawValue] = halfAscii
      t13ns[TransliterationType.halfAsciiUpper.rawValue] = halfAsciiUpper
      t13ns[TransliterationType.halfAsciiLower.rawValue] = halfAsciiLower
      t13ns[TransliterationType.halfAsciiCapitalized.rawValue] = halfAsciiCapitalized
      t13ns[TransliterationType.fullAscii.rawValue] = fullAscii
      t13ns[TransliterationType.fullAsciiUpper.rawValue] = fullAsciiUpper
      t13ns[TransliterationType.fullAsciiLower.rawValue] = fullAsciiLower
      t13ns[TransliterationType.fullAsciiCapitalized.rawValue] = fullAsciiCapitalized

      normalizeT13ns(&t13ns)
      modified = setTransliterations(t13ns, segment.key, segment) || modified
    }
    return modified
  }

  private func addRawNumberT13nCandidates(_ request: ConversionRequest, _ segments: Segments)
    -> Bool
  {
    if segments.conversionSegmentsSize != 1 {
      // This method rewrites a segment only when the segments has only
      // one conversion segment.
      // This is spec matter.
      // Rewriting multiple segments will not make users happier.
      return false
    }
    let composer = request.composer()
    let segment = segments.mutableConversionSegment(0)
    // Get the half_ascii T13n text (nearly equal Raw input).
    // Note that only one segment is in the Segments, but sometimes like
    // on partial conversion, segment.key() is different from the size of
    // the whole composition.
    let raw = composer.getRawSubString(0, segment.keyLen)
    if raw.isEmpty {
      return false
    }
    if !NumberUtil.isArabicNumber(raw) {
      return false
    }
    // half_ascii is arabic number. So let's append additional candidates.
    let ids = getIds(segment)

    // Append half_ascii as normal candidate.
    // If half_ascii is equal to meta candidate's HALF_ASCII candidate, skip.
    if segment.metaCandidatesSize < TransliterationType.halfAscii.rawValue
      || segment.metaCandidate(TransliterationType.halfAscii.rawValue).value.bytesEqual(raw) == false
    {
      let halfCandidate = segment.addCandidate()
      initT13nCandidate(raw, raw, ids.asciiLid, ids.asciiRid, halfCandidate)
      // Keep the character form.
      // Without this attribute the form will be changed by VariantsRewriter.
      halfCandidate.attributes |= Attribute.noVariantsExpansion
    }

    // Do the same thing on full form.
    let fullRaw = Japanese.halfWidthAsciiToFullWidthAscii(raw)
    if segment.metaCandidatesSize < TransliterationType.fullAscii.rawValue
      || segment.metaCandidate(TransliterationType.fullAscii.rawValue).value.bytesEqual(fullRaw) == false
    {
      let fullCandidate = segment.addCandidate()
      initT13nCandidate(raw, fullRaw, ids.asciiLid, ids.asciiRid, fullCandidate)
      fullCandidate.attributes |= Attribute.noVariantsExpansion
    }
    return true
  }

  private func initT13nCandidate(
    _ key: String, _ value: String, _ lid: UInt16, _ rid: UInt16, _ cand: Candidate
  ) {
    cand.value = value
    cand.key = key
    cand.contentValue = value
    cand.contentKey = key
    cand.lid = (lid != 0) ? lid : unknownId
    cand.rid = (rid != 0) ? rid : unknownId
  }

  /// Sets transliteration values into segment.  If t13ns is invalid,
  /// false is returned.
  private func setTransliterations(_ t13ns: [String], _ key: String, _ segment: Segment) -> Bool {
    if t13ns.count != TransliterationType.numT13nTypes || !isTransliterated(t13ns) {
      return false
    }

    segment.clearMetaCandidates()

    let ids = getIds(segment)

    // meta_candidates->resize(NUM_T13N_TYPES)
    let metaCandidates = (0..<TransliterationType.numT13nTypes).map { _ in Candidate() }
    segment.metaCandidates = metaCandidates

    func meta(_ type: TransliterationType) -> Candidate { metaCandidates[type.rawValue] }
    func t13n(_ type: TransliterationType) -> String { t13ns[type.rawValue] }

    initT13nCandidate(
      key, t13n(.hiragana), ids.hiraganaLid, ids.hiraganaRid, meta(.hiragana))
    initT13nCandidate(
      key, t13n(.fullKatakana), ids.katakanaLid, ids.katakanaRid, meta(.fullKatakana))
    initT13nCandidate(key, t13n(.halfAscii), ids.asciiLid, ids.asciiRid, meta(.halfAscii))
    initT13nCandidate(
      key, t13n(.halfAsciiUpper), ids.asciiLid, ids.asciiRid, meta(.halfAsciiUpper))
    initT13nCandidate(
      key, t13n(.halfAsciiLower), ids.asciiLid, ids.asciiRid, meta(.halfAsciiLower))
    initT13nCandidate(
      key, t13n(.halfAsciiCapitalized), ids.asciiLid, ids.asciiRid, meta(.halfAsciiCapitalized))
    initT13nCandidate(key, t13n(.fullAscii), ids.asciiLid, ids.asciiRid, meta(.fullAscii))
    initT13nCandidate(
      key, t13n(.fullAsciiUpper), ids.asciiLid, ids.asciiRid, meta(.fullAsciiUpper))
    initT13nCandidate(
      key, t13n(.fullAsciiLower), ids.asciiLid, ids.asciiRid, meta(.fullAsciiLower))
    initT13nCandidate(
      key, t13n(.fullAsciiCapitalized), ids.asciiLid, ids.asciiRid, meta(.fullAsciiCapitalized))
    initT13nCandidate(
      key, t13n(.halfKatakana), ids.katakanaLid, ids.katakanaRid, meta(.halfKatakana))
    return true
  }
}

private func isComposerApplicable(_ request: ConversionRequest, _ segments: Segments) -> Bool {
  var segmentsKey = ""
  for segment in segments.conversionSegments {
    segmentsKey.append(segment.key)
  }
  if request.key().bytesEqual(segmentsKey) {
    return true
  }
  return false
}

private func normalizeT13ns(_ t13ns: inout [String]) {
  for i in 0..<t13ns.count {
    t13ns[i] = TextNormalizer.normalizeText(t13ns[i])
  }
}

private let kKeycodeToT13nMap: [String?] = [
  nil, nil, nil, nil, nil, nil, nil, nil,
  nil, nil, nil, nil, nil, nil, nil, nil,
  nil, nil, nil, nil, nil, nil, nil, nil,
  nil, nil, nil, nil, nil, nil, nil, nil,
  nil, nil, "", "ya", "axtu", "ixtu", "uxtu", "",
  nil, nil, nil, "xi", nil, nil, nil, nil,
  nil, nil, nil, nil, nil, nil, nil, nil,
  nil, nil, nil, "", "ann", "extu", "inn", nil,
  "oxtu", nil, nil, nil, nil, nil, nil, nil,
  nil, nil, nil, nil, nil, nil, nil, nil,
  nil, nil, nil, nil, nil, nil, nil, nil,
  nil, nil, nil, nil, "nn", nil, "yu", "xe",
  "", nil, nil, nil, nil, nil, nil, nil,
  nil, nil, nil, nil, nil, nil, nil, nil,
  nil, nil, nil, nil, nil, nil, nil, nil,
  nil, nil, nil, "unn", "yo", "enn", "onn", nil,
]

private func modifyT13nsForGodan(_ key: String, _ t13ns: inout [String]) {
  let src = t13ns[TransliterationType.halfAscii.rawValue]
  var dst: [UInt8] = []
  for c in src.utf8 {
    // c >= 0 && c < size (signed char semantics: bytes >= 0x80 are negative).
    if c < 0x80, Int(c) < kKeycodeToT13nMap.count, let mapped = kKeycodeToT13nMap[Int(c)] {
      dst.append(contentsOf: mapped.utf8)
    } else {
      dst.append(c)
    }
  }

  // Hack: Because of the t13n implementation on upper layer, we cannot
  //   "erase" an element because the number of t13n entries is fixed.
  //   Also, just clearing it (i.e. make it an empty string) doesn't work.
  //   Thus, as a work around, we set the original key, so that it'll be
  //   removed in the later phase of de-dupping.
  let halfAscii = dst.isEmpty ? key : String(decoding: dst, as: UTF8.self)
  let fullAscii = Japanese.halfWidthAsciiToFullWidthAscii(halfAscii)
  var halfAsciiUpper = halfAscii
  var halfAsciiLower = halfAscii
  var halfAsciiCapitalized = halfAscii
  Util.upperString(&halfAsciiUpper)
  Util.lowerString(&halfAsciiLower)
  Util.capitalizeString(&halfAsciiCapitalized)
  var fullAsciiUpper = fullAscii
  var fullAsciiLower = fullAscii
  var fullAsciiCapitalized = fullAscii
  Util.upperString(&fullAsciiUpper)
  Util.lowerString(&fullAsciiLower)
  Util.capitalizeString(&fullAsciiCapitalized)

  t13ns[TransliterationType.halfAscii.rawValue] = halfAscii
  t13ns[TransliterationType.halfAsciiUpper.rawValue] = halfAsciiUpper
  t13ns[TransliterationType.halfAsciiLower.rawValue] = halfAsciiLower
  t13ns[TransliterationType.halfAsciiCapitalized.rawValue] = halfAsciiCapitalized
  t13ns[TransliterationType.fullAscii.rawValue] = fullAscii
  t13ns[TransliterationType.fullAsciiUpper.rawValue] = fullAsciiUpper
  t13ns[TransliterationType.fullAsciiLower.rawValue] = fullAsciiLower
  t13ns[TransliterationType.fullAsciiCapitalized.rawValue] = fullAsciiCapitalized
}

private func isTransliterated(_ t13ns: [String]) -> Bool {
  if t13ns.isEmpty || t13ns[0].isEmpty {
    return false
  }

  let baseCandidate = t13ns[0]
  for i in 1..<t13ns.count where !t13ns[i].bytesEqual(baseCandidate) {
    return true
  }
  return false
}

private struct T13nIds {
  var hiraganaLid: UInt16 = 0
  var hiraganaRid: UInt16 = 0
  var katakanaLid: UInt16 = 0
  var katakanaRid: UInt16 = 0
  var asciiLid: UInt16 = 0
  var asciiRid: UInt16 = 0
}

// Get T13n candidate ids from existing candidates.
private func getIds(_ segment: Segment) -> T13nIds {
  var ids = T13nIds()
  // reverse loop to use the highest rank results for each type
  for i in stride(from: segment.candidatesSize - 1, through: 0, by: -1) {
    let candidate = segment.candidate(i)
    let type = Util.getScriptType(candidate.value)
    if type == .hiragana {
      ids.hiraganaLid = candidate.lid
      ids.hiraganaRid = candidate.rid
    } else if type == .katakana {
      ids.katakanaLid = candidate.lid
      ids.katakanaRid = candidate.rid
    } else if type == .alphabet {
      ids.asciiLid = candidate.lid
      ids.asciiRid = candidate.rid
    }
  }
  return ids
}

private func modifyT13ns(_ request: ConversionRequest, _ segment: Segment, _ t13ns: inout [String]) {
  let specialRomanjiTable = request.request().specialRomanjiTable
  if specialRomanjiTable == .godanToHiragana {
    modifyT13nsForGodan(segment.key, &t13ns)
  }

  normalizeT13ns(&t13ns)
}
