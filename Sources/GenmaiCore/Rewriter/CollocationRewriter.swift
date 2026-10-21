// Port of mozc/src/rewriter/collocation_rewriter.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - `collocation_rewriter_internal::{CollocationFilter, SuppressionFilter}`
//   are `CollocationRewriterInternal.{CollocationFilter, SuppressionFilter}`.
//   `Create(data)` takes the `DataView` of the data set and keeps it alive
//   (the ExistenceFilter refers to the memory-mapped bytes without copying);
//   it throws instead of returning `absl::StatusOr`.
// - `CollocationRewriter.create(...)` returns nil where C++ returns nullptr.
// - The DCHECKs (ParseCompound's concatenation check, VerifyNaturalContent)
//   are omitted.

import GenmaiBase
import GenmaiStorage

public enum CollocationRewriterInternal {
  public struct CollocationFilter: Sendable {
    private let filter: ExistenceFilter
    // Keeps the memory referenced by `filter` alive.
    private let data: DataView

    public init(_ filter: ExistenceFilter, data: DataView = .empty) {
      self.filter = filter
      self.data = data
    }

    public static func create(_ data: DataView) throws -> CollocationFilter {
      let filter = try ExistenceFilter.read(data.bytes)
      return CollocationFilter(filter, data: data)
    }

    public func exists(_ left: some StringProtocol, _ right: some StringProtocol) -> Bool {
      if left.isEmpty || right.isEmpty {
        return false
      }
      return filter.exists([String(left), String(right)])
    }
  }

  public struct SuppressionFilter: Sendable {
    private let filter: ExistenceFilter
    // Keeps the memory referenced by `filter` alive.
    private let data: DataView

    public init(_ filter: ExistenceFilter, data: DataView = .empty) {
      self.filter = filter
      self.data = data
    }

    public static func create(_ data: DataView) throws -> SuppressionFilter {
      let filter = try ExistenceFilter.read(data.bytes)
      return SuppressionFilter(filter, data: data)
    }

    public func exists(_ cand: Candidate) -> Bool {
      // TODO(noriyukit): We should share key generation rule with
      // gen_collocation_suppression_data_main.cc.
      filter.exists([cand.contentValue, "\t", cand.contentKey])
    }
  }
}

private let kCandidateSize = 12
private let kMaxCostDiff: Int32 = 3453  // -500*log(1/1000)

// For collocation, we use two segments.
private enum SegmentLookupType {
  case left
  case right
}

// returns true if the given string contains number including Kanji.
private func containsNumber(_ str: some StringProtocol) -> Bool {
  for scalar in str.unicodeScalars where CollocationUtil.isNumber(scalar.value) {
    return true
  }
  return false
}

// Returns true if value matches the pattern XXXPPPYYY, where XXX is a Kanji
// sequence, PPP is the given pattern, and YYY is a sequence containing at least
// one Kanji character. In the value matches the pattern, XXX and YYY are
// substituted to |first_content| and |second|, respectively. Returns false if
// the value isn't of the form XXXPPPYYY.
private func parseCompound(
  _ value: some StringProtocol, _ pattern: String
) -> (firstContent: Substring, second: Substring)? {
  // Find the |first_content| candidate and check if it consists of Kanji only.
  // (std::find over bytes for the first byte of |pattern|.)
  guard let patternFirst = pattern.utf8.first,
    let patternBegin = value.utf8.firstIndex(of: patternFirst)
  else {
    return nil
  }
  let firstContentSize = value.utf8.distance(from: value.utf8.startIndex, to: patternBegin)
  let firstContent = value.byteSubstring(from: 0, length: firstContentSize)
  if !Util.isScriptType(firstContent, .kanji) {
    return nil
  }

  // Check if the middle part matches |pattern|.
  let remainingValue = value.byteSubstring(from: firstContentSize)
  if !remainingValue.hasBytePrefix(pattern) {
    return nil
  }

  // Check if the last substring is eligible for |second|.
  let second = remainingValue.byteSubstring(from: pattern.utf8.count)
  if second.isEmpty || !Util.containsScriptType(second, .kanji) {
    return nil
  }
  return (Substring(firstContent), Substring(second))
}

// Handles compound such as "本を読む"(one segment)
// we want to rewrite using it as if it was "<本|を><読む>"
// so that we can use collocation data like "厚い本"
private func resolveCompoundSegment(
  _ topValue: String, _ value: String, _ type: SegmentLookupType, _ output: inout [String]
) {
  // see "http://ja.wikipedia.org/wiki/助詞"
  // "の" is excluded because it is not good for collocation.
  let kParticles = ["が", "を", "に", "へ", "と", "から", "より", "で"]

  for particle in kParticles {
    if parseCompound(topValue, particle) == nil {
      continue
    }
    if let (firstContent, second) = parseCompound(value, particle) {
      if type == .left {
        output.append(String(second))
        output.append(String(firstContent) + particle)
      } else {
        output.append(String(firstContent))
      }
      return
    }
  }
}

// Generates strings for looking up collocation target for |cand|.
// Returns true if |cand| is valid for collocation look up.
// strings in |output| will be normalized for look up method.
private func generateLookupTokens(
  _ cand: Candidate, _ topCand: Candidate, _ type: SegmentLookupType, _ output: inout [String]
) -> Bool {
  let content = cand.contentValue
  let value = cand.value
  let topContent = topCand.contentValue
  let topValue = topCand.value

  let topContentLen = Util.charsLen(topContent)
  let contentLen = Util.charsLen(content)
  let shouldRemoveNumber = (type == .left)

  func pushBackNormalizedString(_ str: some StringProtocol) {
    output.append(CollocationUtil.getNormalizedScript(str, shouldRemoveNumber))
  }

  if type == .right && !value.bytesEqual(topValue) && topContentLen >= 2 && contentLen == 1 {
    return false
  }

  if type == .left {
    pushBackNormalizedString(value)
  } else {
    output.append(content)
    // "舞って" workaround
    // V+"て" is often treated as one compound.
    let pattern = "て"
    if content.hasBytePrefix(pattern) {
      pushBackNormalizedString(Util.utf8SubString(content, 0, contentLen - 1))
    }
  }

  // we don't rewrite NUMBER to others and vice versa
  if containsNumber(value) != containsNumber(topValue) {
    return false
  }

  let topAuxValue = Util.utf8SubString(topValue, topContentLen)
  let topAuxValueLen = Util.charsLen(topAuxValue)
  let topValueScriptType = Util.getScriptType(topValue)

  // we don't rewrite KATAKANA segment
  // for example, we don't rewrite "コーヒー飲みます" to "珈琲飲みます"
  if type == .left && topAuxValueLen == 0 && !topValue.bytesEqual(value)
    && topValueScriptType == .katakana
  {
    return false
  }

  // special cases
  if topContentLen == 1 {
    let codepoint = Util.utf8ToCodepoint(topContent)
    switch codepoint {
    case 0x304a,  // "お"
      0x5fa1,  // "御"
      0x3054:  // "ご"
      return true
    default:
      break
    }
  }

  let auxValue = Util.utf8SubString(value, contentLen)

  do {
    // Remove number in normalization for the left segment.
    let auxNormalized = CollocationUtil.getNormalizedScript(auxValue, shouldRemoveNumber)
    let topAuxNormalized = CollocationUtil.getNormalizedScript(topAuxValue, shouldRemoveNumber)
    if !auxNormalized.isEmpty && !Util.isScriptType(auxNormalized, .hiragana) {
      if type == .right {
        return false
      }
      if !auxNormalized.bytesEqual(topAuxNormalized) {
        return false
      }
    }
  }

  resolveCompoundSegment(topValue, value, type, &output)

  let auxValueLen = Util.charsLen(auxValue)
  let valueLen = Util.charsLen(value)

  // "<XXいる|>" can be rewrote to "<YY|いる>" and vice versa
  do {
    let kSuffix = "いる"
    if topAuxValueLen == 0 && auxValueLen == 2 && topValue.hasByteSuffix(kSuffix)
      && auxValue.hasByteSuffix(kSuffix)
    {
      if type == .right {
        // "YYいる" in addition to "YY"
        pushBackNormalizedString(value)
      }
      return true
    }
    if auxValueLen == 0 && topAuxValueLen == 2 && value.hasByteSuffix(kSuffix)
      && topAuxValue.hasByteSuffix(kSuffix)
    {
      if type == .right {
        // "YY" in addition to "YYいる"
        pushBackNormalizedString(Util.utf8SubString(value, 0, valueLen - 2))
      }
      return true
    }
  }

  // "<XXせる|>" can be rewrote to "<YY|せる>" and vice versa
  do {
    let kSuffix = "せる"
    if topAuxValueLen == 0 && auxValueLen == 2 && topValue.hasByteSuffix(kSuffix)
      && auxValue.hasByteSuffix(kSuffix)
    {
      if type == .right {
        // "YYせる" in addition to "YY"
        pushBackNormalizedString(value)
      }
      return true
    }
    if auxValueLen == 0 && topAuxValueLen == 2 && value.hasByteSuffix(kSuffix)
      && topAuxValue.hasByteSuffix(kSuffix)
    {
      if type == .right {
        // "YY" in addition to "YYせる"
        pushBackNormalizedString(Util.utf8SubString(value, 0, valueLen - 2))
      }
      return true
    }
  }

  let contentScriptType = Util.getScriptType(content)

  // "<XX|する>" can be rewrote using "<XXす|る>" and "<XX|する>"
  // in "<XX|する>", XX must be single script type
  do {
    let kSuffix = "する"
    if auxValueLen == 2 && auxValue.hasByteSuffix(kSuffix) {
      if contentScriptType != .katakana && contentScriptType != .hiragana
        && contentScriptType != .kanji && contentScriptType != .alphabet
      {
        return false
      }
      if type == .right {
        // "YYす" in addition to "YY"
        pushBackNormalizedString(Util.utf8SubString(value, 0, valueLen - 1))
      }
      return true
    }
  }

  // "<XXる>" can be rewrote using "<XX|る>"
  // "まとめる", "衰える"
  do {
    let kSuffix = "る"
    if auxValueLen == 0 && value.hasByteSuffix(kSuffix) {
      if type == .right {
        // "YY" in addition to "YYる"
        pushBackNormalizedString(Util.utf8SubString(value, 0, valueLen - 1))
      }
      return true
    }
  }

  // "<XXす>" can be rewrote using "XXする"
  do {
    let kSuffix = "す"
    if value.hasByteSuffix(kSuffix)
      && Util.isScriptType(Util.utf8SubString(value, 0, valueLen - 1), .kanji)
    {
      if type == .right {
        let kRu = "る"
        // "YYする" in addition to "YY"
        pushBackNormalizedString(value + kRu)
      }
      return true
    }
  }

  // "<XXし|た>" can be rewrote using "<XX|した>"
  do {
    let kShi = "し"
    let kTa = "た"
    if content.hasByteSuffix(kShi) && auxValue.bytesEqual(kTa) && topContent.hasByteSuffix(kShi)
      && topAuxValue.bytesEqual(kTa)
    {
      if type == .right {
        let val = Util.utf8SubString(content, 0, contentLen - 1)
        // XX must be KANJI
        if Util.isScriptType(val, .kanji) {
          pushBackNormalizedString(val)
        }
      }
      return true
    }
  }

  let auxLen = valueLen - contentLen
  let topAuxLen = Util.charsLen(topValue) - topContentLen
  if auxLen != topAuxLen {
    return false
  }

  let topContentScriptType = Util.getScriptType(topContent)

  // we don't rewrite HIRAGANA to KATAKANA
  if topContentScriptType == .hiragana && contentScriptType == .katakana {
    return false
  }

  // we don't rewrite second KATAKANA
  // for example, we don't rewrite "このコーヒー" to "この珈琲"
  if type == .right && topContentScriptType == .katakana && !value.bytesEqual(topValue) {
    return false
  }

  if topContentLen == 1 && topContentScriptType == .hiragana {
    return false
  }

  // suppress "<身|ています>" etc.
  if topContentLen == 1 && contentLen == 1 && topAuxValueLen >= 2 && auxValueLen >= 2
    && topContentScriptType == .kanji && contentScriptType == .kanji
    && !topContent.bytesEqual(content)
  {
    return false
  }

  return true
}

@inline(__always) private func isKeyUnknown(_ seg: Segment) -> Bool {
  Util.isScriptType(seg.key, .unknownScript)
}

public final class CollocationRewriter: RewriterInterface, Sendable {
  public typealias CollocationFilter = CollocationRewriterInternal.CollocationFilter
  public typealias SuppressionFilter = CollocationRewriterInternal.SuppressionFilter

  private let posMatcher: PosMatcher
  private let firstNameId: UInt16
  private let lastNameId: UInt16

  // Used to test if pairs of strings are in collocation data. Since it's a
  // bloom filter, non-collocation words are sometimes mistakenly boosted,
  // although the possibility is very low (0.001% by default).
  private let collocationFilter: CollocationFilter

  // Used to test if pairs of content key and value are "ateji". Since it's a
  // bloom filter, non-ateji words are sometimes mistakenly classified as ateji,
  // resulting in passing on the right collocations, though the possibility is
  // very low (0.001% by default).
  private let suppressionFilter: SuppressionFilter

  public init(
    _ posMatcher: PosMatcher, _ collocationFilter: CollocationFilter,
    _ suppressionFilter: SuppressionFilter
  ) {
    self.posMatcher = posMatcher
    self.firstNameId = posMatcher.getFirstNameId()
    self.lastNameId = posMatcher.getLastNameId()
    self.collocationFilter = collocationFilter
    self.suppressionFilter = suppressionFilter
  }

  public static func create(
    _ posMatcher: PosMatcher, _ collocationData: DataView, _ collocationSuppressionData: DataView
  ) -> CollocationRewriter? {
    let collocationFilter: CollocationFilter
    do {
      collocationFilter = try CollocationFilter.create(collocationData)
    } catch {
      GenmaiLog.error("\(error)")
      return nil
    }

    let suppressionFilter: SuppressionFilter
    do {
      suppressionFilter = try SuppressionFilter.create(collocationSuppressionData)
    } catch {
      GenmaiLog.error("\(error)")
      return nil
    }

    return CollocationRewriter(posMatcher, collocationFilter, suppressionFilter)
  }

  /// `apply_from_tuples(CollocationRewriter::Create, pos_matcher,
  /// data_manager.GetCollocationData())`.
  public static func create(
    _ posMatcher: PosMatcher,
    _ collocationData: (collocation: DataView, collocationSuppression: DataView)
  ) -> CollocationRewriter? {
    create(posMatcher, collocationData.collocation, collocationData.collocationSuppression)
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    if Rewriter.disableLaegacyRewriterInMixedConversion(
      request, Rewriter.LegacyRewriterType.disableCollocation)
      || Rewriter.disableLegacyRewriter(request, Rewriter.LegacyRewriterType.disableCollocation)
    {
      return false
    }

    return rewriteCollocation(segments)
  }

  private func isName(_ cand: Candidate) -> Bool {
    cand.lid == lastNameId || cand.lid == firstNameId
  }

  private func rewriteFromPrevSegment(_ prevCand: Candidate, _ seg: Segment) -> Bool {
    let prev = CollocationUtil.getNormalizedScript(prevCand.value, true)

    let iMax = min(seg.candidatesSize, kCandidateSize)

    // Reuse |curs| in the loop as this method is performance critical.
    var curs: [String] = []
    for i in 0..<iMax {
      if seg.candidate(i).cost > seg.candidate(0).cost + kMaxCostDiff {
        continue
      }
      if isName(seg.candidate(i)) {
        continue
      }
      if suppressionFilter.exists(seg.candidate(i)) {
        continue
      }
      curs.removeAll(keepingCapacity: true)
      if !generateLookupTokens(seg.candidate(i), seg.candidate(0), .right, &curs) {
        continue
      }

      for cur in curs {
        if collocationFilter.exists(prev, cur) {
          seg.moveCandidate(i, 0)
          seg.mutableCandidate(0).attributes |= Attribute.contextSensitive
          return true
        }
      }
    }
    return false
  }

  private func rewriteUsingNextSegment(_ nextSeg: Segment, _ seg: Segment) -> Bool {
    let iMax = min(seg.candidatesSize, kCandidateSize)
    let jMax = min(nextSeg.candidatesSize, kCandidateSize)

    // Cache the results for the next segment
    var nextSegOk = [Bool](repeating: false, count: jMax)
    var nexts = [[String]](repeating: [], count: jMax)
    for j in 0..<jMax {
      nextSegOk[j] = false

      if isName(nextSeg.candidate(j)) {
        continue
      }
      if suppressionFilter.exists(nextSeg.candidate(j)) {
        continue
      }
      if !generateLookupTokens(nextSeg.candidate(j), nextSeg.candidate(0), .right, &nexts[j]) {
        continue
      }

      nextSegOk[j] = true
    }

    // Reuse |curs| in the loop as this method is performance critical.
    var curs: [String] = []
    for i in 0..<iMax {
      if seg.candidate(i).cost > seg.candidate(0).cost + kMaxCostDiff {
        continue
      }
      if isName(seg.candidate(i)) {
        continue
      }
      if suppressionFilter.exists(seg.candidate(i)) {
        continue
      }
      curs.removeAll(keepingCapacity: true)
      if !generateLookupTokens(seg.candidate(i), seg.candidate(0), .left, &curs) {
        continue
      }

      for cur in curs {
        for j in 0..<jMax {
          if nextSeg.candidate(j).cost > nextSeg.candidate(0).cost + kMaxCostDiff {
            continue
          }
          if !nextSegOk[j] {
            continue
          }

          for next in nexts[j] {
            if collocationFilter.exists(cur, next) {
              seg.moveCandidate(i, 0)
              seg.mutableCandidate(0).attributes |= Attribute.contextSensitive
              nextSeg.moveCandidate(j, 0)
              nextSeg.mutableCandidate(0).attributes |= Attribute.contextSensitive
              return true
            }
          }
        }
      }
    }
    return false
  }

  private func rewriteCollocation(_ segments: Segments) -> Bool {
    // Return false if at least one segment is fixed or at least one segment
    // contains no candidates.
    for seg in segments.conversionSegments {
      if seg.segmentType == .fixedValue || seg.candidatesSize == 0 {
        return false
      }
    }

    var segsChanged = [Bool](repeating: false, count: segments.segmentsSize)
    var changed = false

    var i = segments.historySegmentsSize
    while i < segments.segmentsSize {
      defer { i += 1 }
      var rewroteNext = false

      if isKeyUnknown(segments.segment(i)) {
        continue
      }

      if i + 1 < segments.segmentsSize
        && rewriteUsingNextSegment(segments.mutableSegment(i + 1), segments.mutableSegment(i))
      {
        changed = true
        rewroteNext = true
        segsChanged[i] = true
        segsChanged[i + 1] = true
      }

      if !segsChanged[i] && !rewroteNext && i > 0
        && rewriteFromPrevSegment(segments.segment(i - 1).candidate(0), segments.mutableSegment(i))
      {
        changed = true
        segsChanged[i - 1] = true
        segsChanged[i] = true
      }

      let cand = segments.segment(i).candidate(0)
      if i >= 2
        // Cross over only adverbs
        // Segment is adverb if;
        //  1) lid and rid is adverb.
        //  2) or rid is adverb suffix.
        && ((posMatcher.isAdverb(segments.segment(i - 1).candidate(0).lid)
          && posMatcher.isAdverb(segments.segment(i - 1).candidate(0).rid))
          || posMatcher.isAdverbSegmentSuffix(segments.segment(i - 1).candidate(0).rid))
        && (!cand.contentValue.bytesEqual(cand.value) || !cand.value.bytesEqual("・"))
      {  // "・" workaround
        if !segsChanged[i - 2] && !segsChanged[i]
          && rewriteUsingNextSegment(segments.mutableSegment(i), segments.mutableSegment(i - 2))
        {
          changed = true
          segsChanged[i] = true
          segsChanged[i - 2] = true
        } else if !segsChanged[i]
          && rewriteFromPrevSegment(
            segments.segment(i - 2).candidate(0), segments.mutableSegment(i))
        {
          changed = true
          segsChanged[i] = true
          segsChanged[i - 2] = true
        }
      }
    }

    return changed
  }
}
