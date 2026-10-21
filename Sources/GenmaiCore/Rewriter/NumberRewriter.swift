// Port of mozc/src/rewriter/number_rewriter.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - `converter::Candidate` is a reference type in Swift; the C++ value copies
//   (`info.candidate = c`, `*inserted = seg->candidate(1)`) are `copy()` /
//   `assign(from:)`.
// - Hash sets / maps keyed by strings use the UTF-8 bytes as keys so that
//   comparisons are bytewise (Swift `String` equality is canonical
//   equivalence).

import GenmaiBase
import GenmaiProtocol

private let kMaxLenForPhoneticNumber = 6  // "100000" (じゅうまん)

// Rewrite type
private enum RewriteType {
  case noRewrite
  case arabicFirst  // arabic candidates first ordering
  case kanjiFirst  // kanji candidates first ordering
}

private struct RewriteCandidateInfo {
  var type: RewriteType = .noRewrite
  var position: Int = 0  // Base (arabic number) candidate position
  var candidate = Candidate()  // Base candidate
}

@inline(__always)
private func bytesKey(_ s: some StringProtocol) -> [UInt8] { Array(s.utf8) }

/// `std::string(s, pos, n)` by byte offsets.
@inline(__always)
private func byteSuffix(_ value: String, from pos: Int) -> String {
  String(value.byteSubstring(from: pos))
}

// Returns RewriteCandidateInformation if available.
// base_candidate_pos: the index of the base candidate.
// *arabic_candidate: arabic candidate using numeric style conversion.
// POS information, cost, etc will be copied from base candidate.
private func getRewriteCandidateInfo(
  _ suffixArray: SerializedStringArray, _ seg: Segment, _ baseCandidatePos: Int,
  _ posMatcher: PosMatcher
) -> RewriteCandidateInfo? {
  let c = seg.candidate(baseCandidatePos)
  if !NumberCompoundUtil.isNumber(suffixArray, posMatcher, c) {
    return nil
  }
  if c.attributes & Attribute.noModification != 0 {
    return nil
  }
  // Do not rewrite hex/oct/bin number.
  if c.style == .numberHex || c.style == .numberOct || c.style == .numberBin {
    return nil
  }

  var info = RewriteCandidateInfo()
  info.position = baseCandidatePos

  if Util.getScriptType(c.contentValue) == .number {
    info.candidate = c.copy()
    info.candidate.innerSegmentBoundary.removeAll()
    if Util.getScriptType(c.contentKey) == .number
      || (c.attributes & Attribute.userDictionary) != 0
    {
      // ARABIC_FIRST when:
      // - a user types number key
      // - or, the entry came from the user dictionary
      info.type = .arabicFirst
    } else {
      info.type = .kanjiFirst
    }
    return info
  }

  let halfWidthNewContentValue = Japanese.fullWidthToHalfWidth(c.contentKey)
  // Try to get normalized kanji_number and arabic_number.
  // If it failed, do nothing.
  // Retain suffix for later use.
  var numberSuffix = ""
  var kanjiNumber = ""
  var arabicNumber = ""
  if !NumberUtil.normalizeNumbersWithSuffix(
    c.contentValue,
    false,  // trim_reading_zeros
    &kanjiNumber, &arabicNumber, &numberSuffix)
    || arabicNumber.bytesEqual(halfWidthNewContentValue)
  {
    return nil
  }
  let newContentValue = arabicNumber + numberSuffix
  if newContentValue.bytesEqual(halfWidthNewContentValue) {
    return nil
  }
  let suffix = byteSuffix(c.value, from: c.contentValue.utf8.count)
  info.candidate.clear()
  info.candidate.value = newContentValue + suffix
  info.candidate.contentValue = newContentValue
  info.candidate.key = c.key
  info.candidate.contentKey = c.contentKey
  info.candidate.consumedKeySize = c.consumedKeySize
  info.candidate.cost = c.cost
  info.candidate.structureCost = c.structureCost
  info.candidate.lid = c.lid
  info.candidate.rid = c.rid
  info.candidate.attributes |= c.attributes & Attribute.partiallyKeyConsumed

  info.type = .kanjiFirst
  return info
}

private func getRewriteCandidateInfos(
  _ suffixArray: SerializedStringArray, _ seg: Segment, _ posMatcher: PosMatcher
) -> [RewriteCandidateInfo] {
  var rewriteCandidateInfo: [RewriteCandidateInfo] = []

  // Use the higher ranked candidate for deciding the insertion position.
  var seen = Set<[UInt8]>()
  for i in 0..<seg.candidatesSize {
    guard let info = getRewriteCandidateInfo(suffixArray, seg, i, posMatcher) else {
      continue
    }

    // Skip expanding number variation for large number for phonetic number
    // candidates. Generating "100000000" for the key "いちおく" would be noisy.
    let isBasePhonetic = Util.getFirstScriptType(info.candidate.key) != .number
    if isBasePhonetic && Util.charsLen(info.candidate.value) > kMaxLenForPhoneticNumber {
      continue
    }

    if seen.insert(bytesKey(info.candidate.value)).inserted {
      rewriteCandidateInfo.append(info)
    }
  }
  return rewriteCandidateInfo
}

// If top candidate is Kanji numeric, we want to expand at least
// 5 candidates apart from base candidate.
// http://b/issue?id=2872048
private let kArabicNumericOffset = 5

private func getInsertOffset(_ type: RewriteType) -> Int {
  // +2 for arabic half_width full_width expansion
  type == .arabicFirst ? 2 : kArabicNumericOffset
}

private func pushBackCandidate(
  _ value: String, _ desc: String, _ style: NumberUtil.NumberString.Style,
  _ results: inout [Candidate]
) {
  var found = false
  for it in results where it.value.bytesEqual(value) {
    found = true
    break
  }
  if !found {
    let cand = Candidate()
    cand.value = value
    cand.description = desc
    cand.style = style
    results.append(cand)
  }
}

private func setCandidatesInfo(_ arabicCand: Candidate, _ candidates: [Candidate]) {
  let suffix = byteSuffix(arabicCand.value, from: arabicCand.contentValue.utf8.count)

  for it in candidates {
    it.contentValue = it.value
    it.value += suffix
  }
}

// Note:
// Some number characters such as superscript (¹) is out of target of
// number styles.
private func isNumberCandidate(_ candidate: Candidate, _ posMatcher: PosMatcher) -> Bool {
  if candidate.lid != candidate.rid {
    return false
  }
  let hasNumberStyle = candidate.style != .defaultStyle
  // Support number candidate with the default POS.
  // For example, transliteration rewriter can generate number
  // candidate with the unknown_id.
  let isUnknownNumberCandidate =
    posMatcher.isUnknown(candidate.lid) && Util.isScriptType(candidate.value, .number)
  return posMatcher.isNumber(candidate.lid) || posMatcher.isKanjiNumber(candidate.lid)
    || hasNumberStyle || isUnknownNumberCandidate
}

private func setNumberInfoToExistingCandidates(
  _ numbers: [NumberUtil.NumberString], _ posMatcher: PosMatcher, _ segment: Segment
) {
  var numberMap: [[UInt8]: NumberUtil.NumberString] = [:]
  // Different number style can have the same surface
  // ex. (123, NUMBER_SEPARATED_ARABIC_HALFWIDTH) and (123, DEFAULT_STYLE)
  for entry in numbers {
    let key = bytesKey(entry.value)
    if numberMap[key] == nil {  // emplace: the first one wins.
      numberMap[key] = entry
    }
  }

  for i in 0..<segment.candidatesSize {
    let candidate = segment.mutableCandidate(i)
    guard let itr = numberMap[bytesKey(candidate.value)] else {
      continue
    }
    if !isNumberCandidate(candidate, posMatcher) {
      continue
    }

    candidate.style = itr.style
    if candidate.description.isEmpty {
      candidate.description = itr.description
    }
  }
}

// If we have the candidates to be inserted before the base candidate,
// delete them.
private func findEraseCandidates(
  _ results: [Candidate], _ baseCandidatePos: Int, _ type: RewriteType, _ seg: Segment,
  _ erasePositions: inout Set<Int>
) {
  // Remember base candidate value
  let startPos = min(baseCandidatePos + getInsertOffset(type), seg.candidatesSize - 1)
  var pos = startPos
  while pos >= 0 {
    defer { pos -= 1 }
    if pos == baseCandidatePos {
      continue
    }
    if seg.candidate(pos).attributes & Attribute.noModification != 0 {
      continue
    }

    // Simple liner search. |results| size is small. (at most 10 or so)
    for cand in results where cand.value.bytesEqual(seg.candidate(pos).value) {
      erasePositions.insert(pos)
      break
    }
  }
}

// This is a utility function for InsertCandidate and UpdateCandidate.
// Do not use this function directly.
private func mergeCandidateInfoInternal(
  _ baseCand: Candidate, _ resultCand: Candidate, _ cand: Candidate
) {
  cand.key = baseCand.key
  cand.value = resultCand.value
  cand.contentKey = baseCand.contentKey
  cand.contentValue = resultCand.contentValue
  cand.consumedKeySize = baseCand.consumedKeySize
  cand.cost = baseCand.cost
  cand.lid = baseCand.lid
  cand.rid = baseCand.rid
  cand.style = resultCand.style
  cand.description = resultCand.description
  cand.innerSegmentBoundary = baseCand.innerSegmentBoundary

  // Don't want to have FULL_WIDTH form for Hex/Oct/BIN..etc.
  if cand.style == .numberHex || cand.style == .numberOct || cand.style == .numberBin {
    cand.attributes |= Attribute.noVariantsExpansion
  }
  cand.attributes |= baseCand.attributes & (Attribute.partiallyKeyConsumed | Attribute.noLearning)
  cand.attributes |= resultCand.attributes & Attribute.noVariantsExpansion
}

private func insertCandidate(
  _ segment: Segment, _ insertPosition: Int, _ baseCand: Candidate, _ resultCand: Candidate
) {
  guard let c = segment.insertCandidate(insertPosition) else { return }
  mergeCandidateInfoInternal(baseCand, resultCand, c)
}

private func updateCandidate(
  _ segment: Segment, _ updatePosition: Int, _ baseCand: Candidate, _ resultCand: Candidate
) {
  let c = segment.mutableCandidate(updatePosition)
  // Do not call |c->Init()| for an existing candidate.
  // There are two major reasons.
  // 1) Future design change may introduce another field into
  //    converter::Candidate. In such situation, simply calling |c->Init()|
  //    for an existing candidate may result in unexpeced data loss.
  // 2) In order to preserve existing attribute information such as
  //    converter::Attribute::USER_DICTIONARY bit in |c|, we cannot call
  //    |c->Init()|. Note that neither |base_cand| nor |result[0]| has
  //    valid value in its |attributes|.
  mergeCandidateInfoInternal(baseCand, resultCand, c)
}

private func insertConvertedCandidates(
  _ results: [Candidate], _ baseCand: Candidate, _ baseCandidatePos: Int, _ insertPos: Int,
  _ seg: Segment
) {
  if results.isEmpty {
    return
  }
  if baseCandidatePos >= seg.candidatesSize {
    GenmaiLog.warning("Invalid base candidate pos")
    return
  }
  var insertPos = insertPos
  // First, insert top candidate
  // If we find the base candidate is equal to the converted
  // special form candidates, we will rewrite it.
  // Otherwise, we will insert top candidate just below the base.
  // Sometimes original base candidate is different from converted candidate
  // For example, "千万" v.s. "一千万", or "一二三" v.s. "百二十三".
  // We don't want to rewrite "千万" to "一千万".
  do {
    let baseValue = seg.candidate(baseCandidatePos).value
    if let itr = results.first(where: { $0.value.bytesEqual(baseValue) }),
      itr.style != .numberKanji, itr.style != .numberKanjiArabic
    {
      // Update existing base candidate
      updateCandidate(seg, baseCandidatePos, baseCand, results[0])
    } else {
      // Insert candidate just below the base candidate
      insertCandidate(seg, baseCandidatePos + 1, baseCand, results[0])
      insertPos += 1
    }
  }

  // Insert others
  for i in 1..<results.count {
    insertCandidate(seg, insertPos, baseCand, results[i])
    insertPos += 1
  }
}

private func getInsertPos(_ basePos: Int, _ segment: Segment, _ type: RewriteType) -> Int {
  min(basePos + getInsertOffset(type), segment.candidatesSize)
}

private func insertHalfArabic(_ halfArabic: String, _ output: inout [NumberUtil.NumberString]) {
  output.append(NumberUtil.NumberString(halfArabic, "", .defaultStyle))
}

private func getNumbersInDefaultOrder(
  _ type: RewriteType, _ execRadixConversion: Bool, _ arabicContentValue: String
) -> [NumberUtil.NumberString] {
  var output: [NumberUtil.NumberString] = []
  if type == .arabicFirst {
    insertHalfArabic(arabicContentValue, &output)
    NumberUtil.arabicToWideArabic(arabicContentValue, &output)
    NumberUtil.arabicToSeparatedArabic(arabicContentValue, &output)
    NumberUtil.arabicToKanji(arabicContentValue, &output)
    NumberUtil.arabicToOtherForms(arabicContentValue, &output)
  } else if type == .kanjiFirst {
    NumberUtil.arabicToKanji(arabicContentValue, &output)
    insertHalfArabic(arabicContentValue, &output)
    NumberUtil.arabicToWideArabic(arabicContentValue, &output)
    NumberUtil.arabicToSeparatedArabic(arabicContentValue, &output)
    NumberUtil.arabicToOtherForms(arabicContentValue, &output)
  }

  if execRadixConversion {
    NumberUtil.arabicToOtherRadixes(arabicContentValue, &output)
  }
  return output
}

// Rewrites an Arabic number + counter suffix (e.g., "3年") in an inner segment
// to Kanji ("三年").
//
// TODO(taku): Because `inner_segment_boundary` only stores byte lengths and
// does not preserve POS IDs (`lid`/`rid`), native kun-yomi expressions
// (e.g., "みっか" -> "3日", "ふたつ" -> "2つ") and calendar months
// ("さんがつ" -> "3月") cannot currently be distinguished from Sino-Japanese
// number + counter compounds ("さんねん" -> "三年") without POS or
// content/functional boundary refinements in
// `NBestGenerator::FillInnerSegmentInfo`.
private func rewriteInnerContentToKanji(
  _ suffixArray: SerializedStringArray, _ key: Substring, _ contentValue: String
) -> String? {
  if Util.getFirstScriptType(key) == .number
    || Util.getFirstScriptType(contentValue) != .number
  {
    return nil
  }
  guard
    let (parsedNumber, parsedSuffix, _) =
      NumberCompoundUtil.splitStringIntoNumberAndCounterSuffix(suffixArray, contentValue),
    !parsedNumber.isEmpty
  else {
    return nil
  }
  var kanjiNumber = ""
  var arabicNumber = ""
  if !NumberUtil.normalizeNumbers(parsedNumber, false, &kanjiNumber, &arabicNumber)
    || kanjiNumber.isEmpty
    || Util.charsLen(arabicNumber) > kMaxLenForPhoneticNumber
  {
    return nil
  }
  return kanjiNumber + parsedSuffix
}

private func isAlreadyUpdated(_ numberCandidates: [Candidate], _ seg: Segment) -> Bool {
  var values = Set<[UInt8]>()
  for i in 0..<seg.candidatesSize {
    values.insert(bytesKey(seg.candidate(i).value))
  }

  for candidate in numberCandidates where !values.contains(bytesKey(candidate.value)) {
    return false
  }
  return true
}

private func getConfiguredNumberCharacterForm(_ request: ConversionRequest)
  -> Genmai_Config_Config.CharacterForm
{
  for rule in request.config().characterFormRules where rule.group == "0" {
    return rule.conversionCharacterForm
  }
  return .lastForm
}

/// A rewriter to expand number styles (NumberUtil::NumberString::Style)
public final class NumberRewriter: RewriterInterface {
  private var suffixArray = SerializedStringArray()
  private let posMatcher: PosMatcher

  public init(_ counterSuffixData: DataView, _ posMatcher: PosMatcher) {
    self.posMatcher = posMatcher
    assert(SerializedStringArray.verifyData(counterSuffixData))
    suffixArray.set(counterSuffixData)
    _ = reload()
  }

  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType {
    if request.request().mixedConversion {
      return .all
    }
    return .conversion
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    if !request.config().useNumberConversion {
      // no use_number_conversion
      return false
    }

    var modified = false

    for segment in segments.conversionSegments {
      modified = rewriteOneSegment(request, segment, segments) || modified
    }

    // NOTE:
    // 1. In realtime conversion, conversion segments are already aggregated
    //    into a single segment (with inner_segments) by the time
    //    post-correction rewriters are applied.
    // 2. This is a workaround to make number rewriting work properly for such
    //    realtime conversion results (e.g. Kanji number conversion for
    //    phonetic number + counter compounds) using inner_segments.
    // 3. This is a transitional implementation; ideally, this logic should be
    //    refactored and placed in a cleaner, more appropriate layer.
    if request.requestType() != .partialSuggestion
      && request.requestType() != .partialPrediction
      && request.request().decoderExperimentParams.suppressRealtimeConversionWithConverter
    {
      if segments.conversionSegmentsSize > 0 {
        modified =
          rewriteTopCandidateForSuggestion(segments.mutableConversionSegment(0)) || modified
      }
    }

    return modified
  }

  public func finish(_ request: ConversionRequest, _ segments: Segments) {
    if request.incognitoMode() {
      // incognito_mode
      return
    }

    if request.config().historyLearningLevel != .defaultHistory {
      // history_learning_level is not DEFAULT_HISTORY
      return
    }

    for segment in segments.conversionSegments {
      if segment.candidatesSize <= 0 || segment.segmentType != .fixedValue
        || segment.candidate(0).attributes & Attribute.noHistoryLearning != 0
      {
        continue
      }
      if segment.candidatesSize == 0 {
        continue
      }
      if !isNumberCandidate(segment.candidate(0), posMatcher) {
        continue
      }
      rememberNumberStyle(segment.candidate(0))
    }
  }

  private func rewriteTopCandidateForSuggestion(_ seg: Segment?) -> Bool {
    guard let seg, seg.candidatesSize != 0 else {
      return false
    }
    // Only inspect index 0 (top_candidate).
    //
    // NumberRewriter runs before VariantsRewriter in the rewriter pipeline.
    // When a Kanji number candidate is inserted at index 0, it is marked with
    // NO_EXTRA_DESCRIPTION so that if VariantsRewriter subsequently applies
    // character form normalization (e.g., full-width alphabet in
    // "wikipediaを3年使う" -> "ｗｉｋｉｐｅｄｉａを三年使う"), VariantsRewriter
    // updates index 0 in-place rather than inserting a third intermediate
    // candidate, keeping the total suggestion count to at most 2:
    //   [0] best composite candidate
    //   [1] plain half-width fallback
    let topCandidate = seg.candidate(0)
    if topCandidate.attributes & Attribute.realtimeConversion == 0
      || topCandidate.attributes & Attribute.userDictionary != 0
    {
      return false
    }

    var modified = false
    var newValue = ""
    var boundaryBuilder = InnerSegmentBoundaryBuilder()
    for iter in topCandidate.innerSegments() {
      var contentValue = String(iter.getContentValue())
      var value = String(iter.getValue())
      if let kanjiContent = rewriteInnerContentToKanji(suffixArray, iter.getKey(), contentValue),
        !kanjiContent.bytesEqual(contentValue)
      {
        contentValue = kanjiContent
        value = contentValue + iter.getFunctionalValue()
        modified = true
      }
      newValue += value
      boundaryBuilder.add(
        iter.getKey().utf8.count, value.utf8.count, iter.getContentKey().utf8.count,
        contentValue.utf8.count)
    }
    if !modified {
      return false
    }

    guard let inserted = seg.insertCandidate(0) else { return false }
    inserted.assign(from: seg.candidate(1))  // Copy from original top candidate
    inserted.value = newValue
    inserted.innerSegmentBoundary = boundaryBuilder.build(inserted.key, inserted.value)
    let merged = inserted.innerSegments().getMergedContentKeyAndValue()
    (inserted.contentKey, inserted.contentValue) = (String(merged.key), String(merged.value))
    inserted.attributes |= Attribute.noExtraDescription
    return true
  }

  private func rewriteOneSegment(
    _ request: ConversionRequest, _ seg: Segment, _ segments: Segments
  ) -> Bool {
    // Radix conversion is done only for conversion mode.
    // Showing radix candidates is annoying for a user.
    let execRadixConversion =
      segments.conversionSegmentsSize == 1 && request.requestType() == .conversion
    let shouldRerank = shouldRerankCandidates(request, segments)

    let infos = getRewriteCandidateInfos(suffixArray, seg, posMatcher)

    var modified = false
    var erasePositions = Set<Int>()  // Erased in descending order below.
    for info in infos.reversed() {
      if info.candidate.contentValue.utf8.count > info.candidate.value.utf8.count {
        GenmaiLog.error("Invalid content_value/value: ")
        break
      }

      let arabicContentValue = Japanese.fullWidthToHalfWidth(info.candidate.contentValue)
      if Util.getScriptType(arabicContentValue) != .number {
        if Util.getFirstScriptType(arabicContentValue) == .number {
          // Rewrite for number suffix
          if isAlreadyUpdated([info.candidate], seg) {
            continue
          }
          let insertPos = min(info.position + 1, seg.candidatesSize)
          insertCandidate(seg, insertPos, info.candidate, info.candidate)
          modified = true
          continue
        }
        GenmaiLog.error("arabic_content_value is not number: \(arabicContentValue)")
        break
      }
      let output = getNumbersInDefaultOrder(info.type, execRadixConversion, arabicContentValue)
      setNumberInfoToExistingCandidates(output, posMatcher, seg)

      let numberCandidates = generateCandidatesToInsert(
        request, info.candidate, output, shouldRerank)

      // If all the candidates are already in the segment, do nothing.
      if isAlreadyUpdated(numberCandidates, seg) {
        continue
      }

      findEraseCandidates(numberCandidates, info.position, info.type, seg, &erasePositions)
      let insertPos = getInsertPos(info.position, seg, info.type)
      assert(info.position < insertPos)
      insertConvertedCandidates(numberCandidates, info.candidate, info.position, insertPos, seg)
      modified = true
    }

    for pos in erasePositions.sorted(by: >) {
      seg.eraseCandidate(pos)
    }

    return modified
  }

  private func rememberNumberStyle(_ candidate: Candidate) {
    let content = candidate.contentValue.isEmpty ? candidate.value : candidate.contentValue
    let form = Util.getFormType(content)
    if candidate.style == .defaultStyle {
      if Util.getScriptType(content) != .number || (form != .halfWidth && form != .fullWidth) {
        return
      }
    } else {
      let key = candidate.contentKey.isEmpty ? candidate.key : candidate.contentKey
      if Util.getScriptType(content) != .number && Util.getScriptType(key) != .number {
        return
      }
    }
    let isHalfWidth = form == .halfWidth || candidate.style == .numberArabicAndKanjiHalfwidth
    let entry = CharacterFormManager.NumberFormStyle(
      form: isHalfWidth ? .halfWidth : .fullWidth, style: candidate.style)
    CharacterFormManager.getCharacterFormManager().setLastNumberStyle(entry)
  }

  private func generateCandidatesToInsert(
    _ request: ConversionRequest, _ arabicCandidate: Candidate,
    _ numbers: [NumberUtil.NumberString], _ shouldRerank: Bool
  ) -> [Candidate] {
    var convertedNumbers: [Candidate] = []
    for numberString in numbers {
      pushBackCandidate(
        numberString.value, numberString.description, numberString.style, &convertedNumbers)
    }
    setCandidatesInfo(arabicCandidate, convertedNumbers)
    if shouldRerank {
      rerankCandidates(request, &convertedNumbers)
    }
    return convertedNumbers
  }

  private func shouldRerankCandidates(_ request: ConversionRequest, _ segments: Segments)
    -> Bool
  {
    if request.incognitoMode() {
      // incognito mode
      return false
    }
    if request.config().historyLearningLevel == .noHistory {
      // history learning level is NO_HISTORY
      return false
    }
    if !request.config().useHistorySuggest && request.requestType() == .suggestion {
      // no history suggest
      return false
    }
    if segments.conversionSegmentsSize != 1 {
      // Rewriting "2|階" to "弐|階" using the history would be noisy.
      // do not apply to the multiple segments.
      return false
    }
    return true
  }

  private func rerankCandidates(_ request: ConversionRequest, _ candidates: inout [Candidate]) {
    guard
      let storedEntry = CharacterFormManager.getCharacterFormManager().getLastNumberStyle()
    else {
      return
    }
    var style = storedEntry.style
    var form = storedEntry.form

    // If an explicit character form rule (HALF_WIDTH or FULL_WIDTH) is
    // configured for numbers, adapt form and width-dependent styles
    // accordingly.
    let configForm = getConfiguredNumberCharacterForm(request)
    if configForm == .halfWidth || configForm == .fullWidth {
      form = configForm
      if style == .numberSeparatedArabicHalfwidth || style == .numberSeparatedArabicFullwidth {
        style =
          (configForm == .halfWidth)
          ? .numberSeparatedArabicHalfwidth : .numberSeparatedArabicFullwidth
      } else if style == .numberArabicAndKanjiHalfwidth
        || style == .numberArabicAndKanjiFullwidth
      {
        style =
          (configForm == .halfWidth)
          ? .numberArabicAndKanjiHalfwidth : .numberArabicAndKanjiFullwidth
      }
    }

    func findCandidate(_ targetStyle: NumberUtil.NumberString.Style) -> Int? {
      for (i, itr) in candidates.enumerated() {
        if itr.style != targetStyle {
          continue
        }
        let content = itr.contentValue.isEmpty ? itr.value : itr.contentValue
        if targetStyle == .defaultStyle
          && ((Util.getFormType(content) == .halfWidth) != (form == .halfWidth))
        {
          continue
        }
        return i
      }
      return nil
    }

    var topNumberEntry = findCandidate(style)
    // Short numbers (e.g., "123") do not have distinct separated or
    // Arabic+Kanji candidates because their surfaces match the plain
    // DEFAULT_STYLE candidates. Fall back to DEFAULT_STYLE with the stored
    // character form.
    if topNumberEntry == nil
      && (style == .numberSeparatedArabicHalfwidth || style == .numberSeparatedArabicFullwidth
        || style == .numberArabicAndKanjiHalfwidth || style == .numberArabicAndKanjiFullwidth)
    {
      topNumberEntry = findCandidate(.defaultStyle)
    }
    guard let top = topNumberEntry else {
      return
    }

    // Rerank `top_number_entry` to top.
    let moved = candidates.remove(at: top)
    candidates.insert(moved, at: 0)
    candidates[0].attributes |= Attribute.noVariantsExpansion
  }
}
