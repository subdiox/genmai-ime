// Port of mozc/src/rewriter/user_segment_history_rewriter.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - `makeLearningSegmentsFromInnerSegments` (used by the test peer) is an
//   `internal` static method so that tests can call it via `@testable import`.
// - The bit-field value classes (`FeatureValue`, `KeyTriggerValue`) are
//   encoded explicitly as little-endian `UInt32`s with the same bit layout as
//   clang/gcc allocate them on little-endian targets (first declared field in
//   the least significant bits), so the persisted `segment.db` is byte
//   compatible with C++ Mozc:
//     FeatureValue    = feature_type(1 bit, always 1) | reserved(31)
//                       -> bytes 01 00 00 00
//     KeyTriggerValue = feature_type(1 bit, always 0) | reserved(23) |
//                       candidates_size(8)  -> bytes 00 00 00 <size>
// - `absl::btree_set<std::string>` (only used for membership) is
//   `Set<[UInt8]>` (bytewise identity).

import GenmaiBase
import GenmaiProtocol
import GenmaiStorage

private let kValueSize = 4
private let kLruSize = 20000
private let kSeedValue: UInt32 = 0xf28d_efe3
private let kMaxCandidatesSize: UInt32 = 255
// Size of candidates to be reranked to the top at one sorting operation.
// Note, if sorting operation is called twice, up to 10 (= 5 * 2) candidates
// could be reranked in total.
private let kMaxRerankSize = 5

private let kFileName = "user://segment.db"

private let kRevertCacheSize = 16

private func useInnerSegments(_ request: ConversionRequest) -> Bool {
  request.request().mixedConversion
}

/// `FeatureValue`: a 32-bit value whose lowest bit (feature_type) is 1.
private enum FeatureValue {
  static let bytes: [UInt8] = [0x01, 0x00, 0x00, 0x00]

  static func isValid(_ v: some Collection<UInt8>) -> Bool {
    guard let first = v.first else { return false }
    return (first & 0x01) == 1
  }
}

private func isPunctuationInternal(_ str: some StringProtocol) -> Bool {
  str.bytesEqual("。") || str.bytesEqual("｡") || str.bytesEqual("、") || str.bytesEqual("､")
    || str.bytesEqual("，") || str.bytesEqual(",") || str.bytesEqual("．")
    || str.bytesEqual(".")
}

/// `KeyTriggerValue`: feature_type (bit 0, always 0), reserved (bits 1-23),
/// candidates_size (bits 24-31).
private struct KeyTriggerValue {
  private var raw: UInt32 = 0

  init() {}

  /// Reads the little-endian value from the first 4 stored bytes.
  init(_ v: some Collection<UInt8>) {
    var value: UInt32 = 0
    for (i, b) in v.prefix(4).enumerated() {
      value |= UInt32(b) << (8 * UInt32(i))
    }
    raw = value
  }

  var isValid: Bool { (raw & 0x1) == 0 }

  var candidatesSize: UInt32 { raw >> 24 }

  mutating func setCandidatesSize(_ size: UInt32) {
    raw = (raw & 0x00FF_FFFF) | (min(size, kMaxCandidatesSize) << 24)
  }

  var bytes: [UInt8] {
    var bytes: [UInt8] = []
    bytes.appendLittleEndian(raw)
    return bytes
  }
}

// return the first candidate which has "BEST_CANDIDATE" attribute
@inline(__always)
private func getDefaultCandidateIndex(_ segment: Segment) -> Int {
  // Check up to kMaxRerankSize + 1 candidates because candidate with
  // BEST_CANDIDATE is highly possibly in that range (http://b/9992330).
  let size = min(segment.candidatesSize, kMaxRerankSize + 1)
  for i in 0..<size {
    if segment.candidate(i).attributes & Attribute.bestCandidate != 0 {
      return i
    }
  }
  return 0
}

private func strJoinWithTabs(_ strings: any StringProtocol...) -> String {
  var result = ""
  for (i, s) in strings.enumerated() {
    if i > 0 { result += "\t" }
    result += s
  }
  return result
}

@inline(__always)
private func normalizeValue(_ value: some StringProtocol) -> String {
  Japanese.fullWidthAsciiToHalfWidthAscii(value)
}

private struct FeatureKey {
  let segments: Segments
  let posMatcher: PosMatcher
  let index: Int

  init(_ segments: Segments, _ posMatcher: PosMatcher, _ index: Int) {
    self.segments = segments
    self.posMatcher = posMatcher
    self.index = index
  }

  // Feature "Left Right"
  func leftRight(_ baseKey: some StringProtocol, _ baseValue: some StringProtocol) -> String {
    if index + 1 >= segments.segmentsSize || index <= 0 {
      return ""
    }
    let j1 = getDefaultCandidateIndex(segments.segment(index - 1))
    let j2 = getDefaultCandidateIndex(segments.segment(index + 1))
    return strJoinWithTabs(
      "LR", baseKey,
      normalizeValue(segments.segment(index - 1).candidate(j1).value),
      normalizeValue(baseValue),
      normalizeValue(segments.segment(index + 1).candidate(j2).value))
  }

  // Feature "Left Left"
  func leftLeft(_ baseKey: some StringProtocol, _ baseValue: some StringProtocol) -> String {
    if index < 2 {
      return ""
    }
    let j1 = getDefaultCandidateIndex(segments.segment(index - 2))
    let j2 = getDefaultCandidateIndex(segments.segment(index - 1))
    return strJoinWithTabs(
      "LL", baseKey,
      normalizeValue(segments.segment(index - 2).candidate(j1).value),
      normalizeValue(segments.segment(index - 1).candidate(j2).value),
      normalizeValue(baseValue))
  }

  // Feature "Right Right"
  func rightRight(_ baseKey: some StringProtocol, _ baseValue: some StringProtocol) -> String {
    if index + 2 >= segments.segmentsSize {
      return ""
    }
    let j1 = getDefaultCandidateIndex(segments.segment(index + 1))
    let j2 = getDefaultCandidateIndex(segments.segment(index + 2))
    return strJoinWithTabs(
      "RR", baseKey, normalizeValue(baseValue),
      normalizeValue(segments.segment(index + 1).candidate(j1).value),
      normalizeValue(segments.segment(index + 2).candidate(j2).value))
  }

  // Feature "Left"
  func left(_ baseKey: some StringProtocol, _ baseValue: some StringProtocol) -> String {
    if index < 1 {
      return ""
    }
    let j = getDefaultCandidateIndex(segments.segment(index - 1))
    return strJoinWithTabs(
      "L", baseKey,
      normalizeValue(segments.segment(index - 1).candidate(j).value),
      normalizeValue(baseValue))
  }

  // Feature "Right"
  func right(_ baseKey: some StringProtocol, _ baseValue: some StringProtocol) -> String {
    if index + 1 >= segments.segmentsSize {
      return ""
    }
    let j = getDefaultCandidateIndex(segments.segment(index + 1))
    return strJoinWithTabs(
      "R", baseKey, normalizeValue(baseValue),
      normalizeValue(segments.segment(index + 1).candidate(j).value))
  }

  // Feature "Current"
  func current(_ baseKey: some StringProtocol, _ baseValue: some StringProtocol) -> String {
    strJoinWithTabs("C", baseKey, normalizeValue(baseValue))
  }

  // Feature "Single"
  func single(_ baseKey: some StringProtocol, _ baseValue: some StringProtocol) -> String {
    if segments.conversionSegmentsSize != 1 {
      return ""
    }
    return strJoinWithTabs("S", baseKey, normalizeValue(baseValue))
  }

  // Feature "Left Number"
  func leftNumber(_ baseKey: some StringProtocol, _ baseValue: some StringProtocol) -> String {
    if index < 1 {
      return ""
    }
    let j = getDefaultCandidateIndex(segments.segment(index - 1))
    let candidate = segments.segment(index - 1).candidate(j)
    if posMatcher.isNumber(candidate.rid) || posMatcher.isKanjiNumber(candidate.rid)
      || Util.getScriptType(candidate.value) == .number
    {
      return strJoinWithTabs("LN", baseKey, normalizeValue(baseValue))
    }
    return ""
  }

  // Feature "Right Number"
  func rightNumber(_ baseKey: some StringProtocol, _ baseValue: some StringProtocol) -> String {
    if index + 1 >= segments.segmentsSize {
      return ""
    }
    let j = getDefaultCandidateIndex(segments.segment(index + 1))
    let candidate = segments.segment(index + 1).candidate(j)
    if posMatcher.isNumber(candidate.lid) || posMatcher.isKanjiNumber(candidate.lid)
      || Util.getScriptType(candidate.value) == .number
    {
      return strJoinWithTabs("RN", baseKey, normalizeValue(baseValue))
    }
    return ""
  }
}

private func isNumberSegment(_ segment: Segment) -> Bool {
  if segment.key.isEmpty {
    return false
  }
  var isNumber = true
  for c in segment.key.utf8 {
    if !(c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9")) {
      isNumber = false
      break
    }
  }
  return isNumber
}

// Gets the candidate index which has same value as given candidate.
// This function returns nil if not found.
// When candidate is in meta candidate,
// returns meta candidate index, (-index-1).
private func getSameValueCandidatePosition(_ segment: Segment, _ candidate: Candidate) -> Int? {
  for i in 0..<segment.candidatesSize {
    if segment.candidate(i).value.bytesEqual(candidate.value) {
      return i
    }
  }
  for i in 0..<segment.metaCandidatesSize {
    if segment.metaCandidate(i).value.bytesEqual(candidate.value) {
      return -i - 1  // meta candidate index
    }
  }
  return nil
}

private func isT13NCandidate(_ cand: Candidate) -> Bool {
  // The cand with 0-id can be the transliterated candidate.
  cand.lid == 0 && cand.rid == 0
}

public final class UserSegmentHistoryRewriter: RewriterInterface {
  struct Score {
    var score: UInt32
    var lastAccessTime: UInt32

    mutating func update(_ other: Score) {
      score = max(score, other.score)
      lastAccessTime = max(lastAccessTime, other.lastAccessTime)
    }

    static func > (a: Score, b: Score) -> Bool {
      if a.score == b.score {
        return a.lastAccessTime > b.lastAccessTime
      }
      return a.score > b.score
    }
  }

  struct ScoreCandidate {
    var score: Score
    let candidate: Candidate
  }

  private var storage: LruStorage?
  private let posMatcher: PosMatcher
  private let posGroup: PosGroup

  // Internal LRU cache to store reverted key.
  private let revertCache = LruCache<UInt64, [String]>(kRevertCacheSize)

  public init(_ posMatcher: PosMatcher, _ posGroup: PosGroup) {
    self.storage = LruStorage()
    self.posMatcher = posMatcher
    self.posGroup = posGroup
    reload()
  }

  private func sortCandidates(_ sortedScores: [ScoreCandidate], _ segment: Segment) -> Bool {
    let topScore = sortedScores[0].score.score
    let kScoreGap: UInt32 = 20  // TODO(taku): no justification
    var seen = Set<[UInt8]>()

    var nextPos = 0
    var n = 0
    while n < sortedScores.count && nextPos < kMaxRerankSize {
      defer { n += 1 }
      // Move candidates when the score is close to the top score.
      // (uint32_t arithmetic: wraps like C++.)
      if kScoreGap < (topScore &- sortedScores[n].score.score) {
        break
      }
      let candidate = sortedScores[n].candidate
      guard let oldPosition = getSameValueCandidatePosition(segment, candidate) else {
        GenmaiLog.error("cannot find the candidate: \(sortedScores[0].candidate.value)")
        return false
      }

      let seenKey =
        (candidate.attributes & Attribute.noVariantsExpansion) != 0
        ? candidate.value : normalizeValue(candidate.value)
      if seen.insert(Array(seenKey.utf8)).inserted {
        segment.moveCandidate(oldPosition, nextPos)
        nextPos += 1
      }
    }
    return true
  }

  private func getScore(
    _ request: ConversionRequest, _ segments: Segments, _ segmentIndex: Int,
    _ candidateIndex: Int
  ) -> Score {
    let segmentsSize = segments.conversionSegmentsSize
    let topCandidate = segments.segment(segmentIndex).candidate(0)
    let candidate = segments.segment(segmentIndex).candidate(candidateIndex)
    let allValue = candidate.value
    let contentValue = candidate.contentValue
    let allKey = segments.segment(segmentIndex).key
    let contentKey = candidate.contentKey
    // if the segments are resized by user OR
    // either top/target candidate has CONTEXT_SENSITIVE flags,
    // don't apply UNIGRAM model
    let contextSensitive =
      segments.resized || (candidate.attributes & Attribute.contextSensitive) != 0
      || (segments.segment(segmentIndex).candidate(0).attributes & Attribute.contextSensitive)
        != 0

    let trigramWeight: UInt32 = (segmentsSize == 3) ? 180 : 30
    let bigramWeight: UInt32 = (segmentsSize == 2) ? 60 : 10
    let bigramNumberWeight: UInt32 = (segmentsSize == 2) ? 50 : 8
    let unigramWeight: UInt32 = (segmentsSize == 1) ? 36 : 6
    let singleWeight: UInt32 = (segmentsSize == 1) ? 90 : 15

    var score = Score(score: 0, lastAccessTime: 0)
    let fkey = FeatureKey(segments, posMatcher, segmentIndex)
    score.update(fetch(fkey.leftRight(allKey, allValue), trigramWeight))
    score.update(fetch(fkey.leftLeft(allKey, allValue), trigramWeight))
    score.update(fetch(fkey.rightRight(allKey, allValue), trigramWeight))
    score.update(fetch(fkey.left(allKey, allValue), bigramWeight))
    score.update(fetch(fkey.right(allKey, allValue), bigramWeight))
    score.update(fetch(fkey.single(allKey, allValue), singleWeight))
    score.update(fetch(fkey.leftNumber(contentKey, contentValue), bigramNumberWeight))
    score.update(fetch(fkey.rightNumber(contentKey, contentValue), bigramNumberWeight))

    let isReplaceable = replaceable(request, topCandidate, candidate)
    if !contextSensitive && isReplaceable {
      score.update(fetch(fkey.current(allKey, allValue), unigramWeight))
    }

    if !isReplaceable {
      return score
    }

    score.update(fetch(fkey.leftRight(contentKey, contentValue), trigramWeight / 2))
    score.update(fetch(fkey.leftLeft(contentKey, contentValue), trigramWeight / 2))
    score.update(fetch(fkey.rightRight(contentKey, contentValue), trigramWeight / 2))
    score.update(fetch(fkey.left(contentKey, contentValue), bigramWeight / 2))
    score.update(fetch(fkey.right(contentKey, contentValue), bigramWeight / 2))
    score.update(fetch(fkey.single(contentKey, contentValue), singleWeight / 2))
    score.update(fetch(fkey.leftNumber(contentKey, contentValue), bigramNumberWeight / 2))
    score.update(fetch(fkey.rightNumber(contentKey, contentValue), bigramNumberWeight / 2))

    if !contextSensitive {
      score.update(fetch(fkey.current(contentKey, contentValue), unigramWeight / 2))
    }

    return score
  }

  // Returns true if |best_candidate| can be replaceable with
  // |target_candidate|. Here, "best candidate" means the candidate from
  // converter before applying personalization.
  private func replaceable(
    _ request: ConversionRequest, _ bestCandidate: Candidate, _ targetCandidate: Candidate
  ) -> Bool {
    let sameFunctionalValue = bestCandidate.functionalValue.bytesEqual(
      targetCandidate.functionalValue)
    let samePosGroup =
      posGroup.getPosGroup(bestCandidate.lid) == posGroup.getPosGroup(targetCandidate.lid)
    return sameFunctionalValue
      && (samePosGroup || isT13NCandidate(bestCandidate) || isT13NCandidate(targetCandidate))
  }

  // |revert_entries| will be stored to Segments and used to revert last
  // Finish() operation in Revert().
  private func rememberFirstCandidate(
    _ request: ConversionRequest, _ segments: Segments, _ segmentIndex: Int,
    _ revertEntries: inout [String]
  ) {
    let seg = segments.segment(segmentIndex)
    let candidate = seg.candidate(0)

    // http://b/issue?id=3156109
    // Do not remember the preference of Punctuations
    if isPunctuation(seg, candidate) {
      return
    }

    let contextSensitive =
      segments.resized || (candidate.attributes & Attribute.contextSensitive) != 0
    let allValue = candidate.value
    let contentValue = candidate.contentValue
    let allKey = seg.key
    let contentKey = candidate.contentKey

    // even if the candidate was the top (default) candidate,
    // ERANKED will be set when user changes the ranking
    let forceInsert = (candidate.attributes & Attribute.reranked) != 0

    // Compare the POS group and Functional value.
    // if "is_replaceable_with_top" is true, it means that  the target candidate
    // can "SAFELY" be replaceable with the top candidate.
    let topIndex = getDefaultCandidateIndex(seg)
    let isReplaceableWithTop =
      (topIndex == 0) || replaceable(request, seg.candidate(topIndex), candidate)
    let fkey = FeatureKey(segments, posMatcher, segmentIndex)
    insert(fkey.leftRight(allKey, allValue), forceInsert, &revertEntries)
    insert(fkey.leftLeft(allKey, allValue), forceInsert, &revertEntries)
    insert(fkey.rightRight(allKey, allValue), forceInsert, &revertEntries)
    insert(fkey.left(allKey, allValue), forceInsert, &revertEntries)
    insert(fkey.right(allKey, allValue), forceInsert, &revertEntries)
    insert(fkey.leftNumber(allKey, allValue), forceInsert, &revertEntries)
    insert(fkey.rightNumber(allKey, allValue), forceInsert, &revertEntries)
    insert(fkey.single(allKey, allValue), forceInsert, &revertEntries)

    if !contextSensitive && isReplaceableWithTop {
      insert(fkey.current(allKey, allValue), forceInsert, &revertEntries)
    }

    // save content value
    if !allValue.bytesEqual(contentValue) && !allKey.bytesEqual(contentKey)
      && isReplaceableWithTop
    {
      insert(fkey.leftRight(contentKey, contentValue), forceInsert, &revertEntries)
      insert(fkey.leftLeft(contentKey, contentValue), forceInsert, &revertEntries)
      insert(fkey.rightRight(contentKey, contentValue), forceInsert, &revertEntries)
      insert(fkey.left(contentKey, contentValue), forceInsert, &revertEntries)
      insert(fkey.right(contentKey, contentValue), forceInsert, &revertEntries)
      insert(fkey.leftNumber(contentKey, contentValue), forceInsert, &revertEntries)
      insert(fkey.rightNumber(contentKey, contentValue), forceInsert, &revertEntries)
      insert(fkey.single(contentKey, contentValue), forceInsert, &revertEntries)
      if !contextSensitive {
        insert(fkey.current(contentKey, contentValue), forceInsert, &revertEntries)
      }
    }

    // learn CloseBracket when OpenBracket is fixed.
    if let closeBracketKey = Util.isOpenBracket(contentKey),
      let closeBracketValue = Util.isOpenBracket(contentValue)
    {
      insert(fkey.single(closeBracketKey, closeBracketValue), forceInsert, &revertEntries)
      if !contextSensitive {
        insert(fkey.current(closeBracketKey, closeBracketValue), forceInsert, &revertEntries)
      }
    }
  }

  private func isAvailable(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    if request.incognitoMode() {
      return false
    }

    if !request.options().enableUserHistoryForConversion {
      return false
    }

    if storage == nil {
      return false
    }

    // check that all segments have candidate
    for segment in segments.all {
      if segment.candidatesSize == 0 {
        GenmaiLog.error("candidate size is 0")
        return false
      }
    }

    if Rewriter.disableLaegacyRewriterInMixedConversion(
      request, Rewriter.LegacyRewriterType.disableUserSegmentHistory)
      || Rewriter.disableLegacyRewriter(
        request, Rewriter.LegacyRewriterType.disableUserSegmentHistory)
    {
      return false
    }

    return true
  }

  // Returns segments for learning.
  // Inner segments boundary will be expanded.
  static func makeLearningSegmentsFromInnerSegments(
    _ request: ConversionRequest, _ segments: Segments
  ) -> Segments {
    let ret = Segments()
    for segment in segments.all {
      let candidate = segment.candidate(0)
      if candidate.innerSegmentBoundary.isEmpty {
        // No inner segment info
        let seg = ret.addSegment()
        seg.assign(from: segment)
        continue
      }
      var index = 0
      let innerSegments = candidate.innerSegments()
      let innerSize = innerSegments.size
      for iter in innerSegments {
        let key = iter.getKey()
        let seg = ret.addSegment()
        seg.setSegmentType(segment.segmentType)
        seg.setKey(key)
        seg.clearCandidates()

        let cand = seg.addCandidate()
        cand.attributes = candidate.attributes
        cand.key = String(key)
        cand.contentKey = String(iter.getContentKey())
        cand.value = String(iter.getValue())
        cand.contentValue = String(iter.getContentValue())
        // Fill IDs for the first and last inner segment.
        if index == 0 {
          cand.lid = candidate.lid
          cand.rid = candidate.lid
        } else if index == innerSize - 1 {
          cand.lid = candidate.rid
          cand.rid = candidate.rid
        }
        index += 1
      }
    }
    return ret
  }

  public func finish(_ request: ConversionRequest, _ segments: Segments) {
    if request.requestType() != .conversion {
      return
    }

    if !isAvailable(request, segments) {
      return
    }

    if request.config().historyLearningLevel != .defaultHistory {
      return
    }

    let targetSegments =
      useInnerSegments(request)
      ? Self.makeLearningSegmentsFromInnerSegments(request, segments) : segments
    var revertEntries: [String] = []
    for i in targetSegments.historySegmentsSize..<targetSegments.segmentsSize {
      let segment = targetSegments.segment(i)
      if segment.candidatesSize <= 0 || segment.segmentType != .fixedValue
        || segment.candidate(0).attributes & Attribute.noHistoryLearning != 0
      {
        continue
      }
      if isNumberSegment(segment) {
        continue
      }
      insertTriggerKey(segment)
      rememberFirstCandidate(request, targetSegments, i, &revertEntries)
    }

    revertCache.insert(segments.revertId, revertEntries)
  }

  @discardableResult
  public func sync() -> Bool { true }

  @discardableResult
  public func reload() -> Bool {
    let filename = ConfigFileStream.getFileName(kFileName)
    guard let storage else { return false }
    if !storage.openOrCreate(filename, kValueSize, kLruSize, kSeedValue) {
      GenmaiLog.warning("cannot initialize UserSegmentHistoryRewriter")
      self.storage = nil
      return false
    }

    let kFileSuffix = ".merge_pending"
    let mergePendingFile = filename + kFileSuffix

    // merge pending file does not always exist.
    if FileUtil.fileExistsOK(mergePendingFile) {
      _ = storage.merge(mergePendingFile)
      FileUtil.unlinkOrLogError(mergePendingFile)
    }

    return true
  }

  private func shouldRewrite(_ segment: Segment) -> Int? {
    if segment.candidatesSize == 0 {
      GenmaiLog.error("candidate size is 0")
      return nil
    }

    guard let storage else { return nil }
    let v1 = storage.lookup(segment.key).map { KeyTriggerValue($0) }

    var v2: KeyTriggerValue? = nil
    if !segment.key.bytesEqual(segment.candidate(0).contentKey) {
      v2 = storage.lookup(segment.candidate(0).contentKey).map { KeyTriggerValue($0) }
    }

    let v1Size = v1.map { $0.isValid ? Int($0.candidatesSize) : 0 } ?? 0
    let v2Size = v2.map { $0.isValid ? Int($0.candidatesSize) : 0 } ?? 0

    let maxCandidatesSize = max(v1Size, v2Size)
    return maxCandidatesSize > 0 ? maxCandidatesSize : nil
  }

  private func insertTriggerKey(_ segment: Segment) {
    if segment.candidate(0).attributes & Attribute.reranked == 0 {
      return
    }

    guard let storage else { return }

    var v = KeyTriggerValue()

    // TODO(taku): saving segment.candidate_size() might be too heavy and
    // increases the chance of hash collisions.
    v.setCandidatesSize(UInt32(truncatingIfNeeded: segment.candidatesSize))

    let bytes = v.bytes
    storage.insert(segment.key, bytes)
    if !segment.key.bytesEqual(segment.candidate(0).contentKey) {
      storage.insert(segment.candidate(0).contentKey, bytes)
    }

    if let closeBracketKey = Util.isOpenBracket(segment.key) {
      storage.insert(String(closeBracketKey), bytes)
    }
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    if !isAvailable(request, segments) {
      return false
    }

    if request.config().historyLearningLevel == .noHistory {
      return false
    }

    // set BEST_CANDIDATE marker in advance
    for segment in segments.all {
      segment.mutableCandidate(0).attributes |= Attribute.bestCandidate
    }

    var modified = false
    for i in segments.historySegmentsSize..<segments.segmentsSize {
      let segment = segments.mutableSegment(i)

      if segment.segmentType == .fixedValue {
        continue
      }

      if isPunctuation(segment, segment.candidate(0)) {
        continue
      }

      if isNumberSegment(segment) {
        continue
      }

      guard shouldRewrite(segment) != nil else {
        continue
      }

      // for each all candidates expanded
      var scores: [ScoreCandidate] = []
      for l in 0..<segment.candidatesSize {
        let score = getScore(request, segments, i, l)
        if score.score > 0 {
          scores.append(ScoreCandidate(score: score, candidate: segment.candidate(l)))
        }
      }
      for k in 0..<segment.metaCandidatesSize {
        let j = -k - 1
        let score = getScore(request, segments, i, j)
        if score.score > 0 {
          scores.append(ScoreCandidate(score: score, candidate: segment.candidate(j)))
        }
      }

      if scores.isEmpty {
        continue
      }

      // absl::c_stable_sort(scores, std::greater<ScoreCandidate>())
      scores = stableSorted(scores) { $0.score > $1.score }
      modified = sortCandidates(scores, segment) || modified
      if segment.candidate(0).attributes & Attribute.bestCandidate == 0 {
        segment.mutableCandidate(0).attributes |= Attribute.userSegmentHistoryRewriter
      }
    }
    return modified
  }

  public func clear() {
    if let storage {
      _ = storage.clear()
    }
  }

  public func revert(_ segments: Segments) {
    guard let revertEntries = revertCache.lookupWithoutInsert(segments.revertId) else {
      return
    }
    for key in revertEntries {
      storage?.delete(key)
    }
  }

  public func clearHistoryEntry(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int)
    -> Bool
  {
    let segment = segments.segment(segmentIndex)
    let candidate = segment.candidate(0)
    let key = candidate.key
    let value = candidate.value

    let fkey = FeatureKey(segments, posMatcher, segmentIndex)
    var result = false
    result = deleteEntry(fkey.leftRight(key, value)) || result
    result = deleteEntry(fkey.leftLeft(key, value)) || result
    result = deleteEntry(fkey.rightRight(key, value)) || result
    result = deleteEntry(fkey.left(key, value)) || result
    result = deleteEntry(fkey.right(key, value)) || result
    result = deleteEntry(fkey.leftNumber(key, value)) || result
    result = deleteEntry(fkey.rightNumber(key, value)) || result
    result = deleteEntry(fkey.single(key, value)) || result
    result = deleteEntry(fkey.current(key, value)) || result
    return result
  }

  private func isPunctuation(_ seg: Segment, _ candidate: Candidate) -> Bool {
    posMatcher.isJapanesePunctuations(candidate.lid) && candidate.lid == candidate.rid
      && isPunctuationInternal(seg.key) && isPunctuationInternal(candidate.value)
  }

  private func fetch(_ key: String, _ weight: UInt32) -> Score {
    if !key.isEmpty, let storage {
      var atime: UInt32 = 0
      if let v = storage.lookup(key, lastAccessTime: &atime), FeatureValue.isValid(v) {
        return Score(score: weight, lastAccessTime: atime)
      }
    }
    return Score(score: 0, lastAccessTime: 0)
  }

  private func insert(_ key: String, _ force: Bool, _ revertEntries: inout [String]) {
    if key.isEmpty {
      return
    }
    guard let storage else { return }

    maybeInsertRevertEntry(key, &revertEntries)

    if force {
      storage.insert(key, FeatureValue.bytes)
    } else {
      storage.tryInsert(key, FeatureValue.bytes)
    }
  }

  private func maybeInsertRevertEntry(_ key: String, _ revertEntries: inout [String]) {
    if storage?.lookup(key) != nil {
      return
    }

    revertEntries.append(key)
  }

  // Returns true if deletion succeeded.
  private func deleteEntry(_ key: String) -> Bool {
    guard let storage, storage.lookup(key) != nil else {
      return false
    }
    storage.delete(key)
    return true
  }
}

/// `absl::c_stable_sort` with a strict-weak-ordering predicate.
private func stableSorted<T>(_ array: [T], by areInIncreasingOrder: (T, T) -> Bool) -> [T] {
  // Swift's `sort` is stable (introsort was replaced by a stable merge sort
  // in Swift 5), but make the stability explicit by tie-breaking on index.
  array.enumerated().sorted { a, b in
    if areInIncreasingOrder(a.element, b.element) { return true }
    if areInIncreasingOrder(b.element, a.element) { return false }
    return a.offset < b.offset
  }.map(\.element)
}
