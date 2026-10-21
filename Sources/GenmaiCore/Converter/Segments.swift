// Port of mozc/src/converter/segments.{h,cc} (3.35.6354).

import GenmaiBase

/// `mozc::converter::Segment`.
///
/// A reference type: C++ hands out `Segment*` (`mutable_segment(i)`) and
/// callers mutate segments in place. The C++ copy constructor / assignment are
/// `copy()` / `init(copying:)` / `assign(from:)` (deep copies of the
/// candidates).
public final class Segment {
  public enum SegmentType: UInt8, Sendable {
    case free  // FULL automatic conversion.
    case fixedBoundary  // cannot consist of multiple segments.
    case fixedValue  // cannot consist of multiple segments.
    // and result is also fixed
    case submitted  // submitted node
    case history  // history node. It is hidden from user.
  }

  /// This is an alias for backward compatibility.
  public typealias Candidate = GenmaiCore.Candidate

  // LINT.IfChange
  // Note that |key_| is shorter than usual when partial suggestion is
  // performed.
  // For example if the preedit text is "しれ|ません", there is only a segment
  // whose |key_| is "しれ".
  // There is no way to detect by using only a segment whether this segment is
  // for partial suggestion or not.
  // You should detect that by using both Composer and Segments.
  public private(set) var key: String = ""
  /// The candidates (C++ `candidates()`, a `std::deque<Candidate*>`).
  public private(set) var candidates: [Candidate] = []
  /// Meta candidates (C++ `meta_candidates()` / `mutable_meta_candidates()`,
  /// a `std::vector<Candidate>` held by value). Assigning elements stores the
  /// given objects; copy them first when value semantics are needed.
  public var metaCandidates: [Candidate] = []
  /// Returns the length of the key in Unicode characters. (e.g. 1 for "あ")
  public private(set) var keyLen: Int = 0
  public var segmentType: SegmentType = .free
  // LINT.ThenChange(//converter/segments_matchers.h)

  /// For debug. Candidate words removed through conversion process.
  public var removedCandidatesForDebug: [Candidate] = []

  public init() {}

  /// C++ copy constructor.
  public convenience init(copying x: Segment) {
    self.init()
    assign(from: x)
  }

  /// C++ copy constructor.
  public func copy() -> Segment { Segment(copying: self) }

  /// C++ copy assignment: deep-copies the candidates and meta candidates.
  public func assign(from x: Segment) {
    if x === self { return }
    removedCandidatesForDebug = x.removedCandidatesForDebug.map { $0.copy() }
    segmentType = x.segmentType
    key = x.key
    keyLen = x.keyLen
    metaCandidates = x.metaCandidates.map { $0.copy() }

    clearCandidates()
    deepCopyCandidates(x.candidates)
  }

  public func setSegmentType(_ segmentType: SegmentType) {
    self.segmentType = segmentType
  }

  public func setKey(_ key: some StringProtocol) {
    self.key = String(key)
    keyLen = Util.charsLen(self.key)
  }

  /// check if the specified index is valid or not.
  public func isValidIndex(_ i: Int) -> Bool {
    if i < 0 {
      return -i - 1 < metaCandidates.count
    } else {
      return i < candidates.count
    }
  }

  // Candidate manipulations

  /// getter. Negative indices access meta candidates (-1 is the first one).
  public func candidate(_ i: Int) -> Candidate {
    if i < 0 {
      return metaCandidate(-i - 1)
    }
    return candidates[i]
  }

  /// setter. Same object as `candidate(i)`; kept for C++ readability.
  public func mutableCandidate(_ i: Int) -> Candidate {
    if i < 0 {
      return metaCandidates[-i - 1]
    }
    return candidates[i]
  }

  // push and insert candidates
  @discardableResult
  public func pushFrontCandidate() -> Candidate {
    let candidate = Candidate()
    candidates.insert(candidate, at: 0)
    return candidate
  }

  @discardableResult
  public func pushBackCandidate() -> Candidate {
    let candidate = Candidate()
    candidates.append(candidate)
    return candidate
  }

  /// alias of pushBackCandidate()
  @discardableResult
  public func addCandidate() -> Candidate { pushBackCandidate() }

  /// Inserts a new candidate at `i`. Returns nil for a negative index (C++
  /// returns nullptr); an index past the end is clamped (LOG(DFATAL) in C++).
  @discardableResult
  public func insertCandidate(_ i: Int) -> Candidate? {
    if i < 0 {
      return nil
    }
    let i = min(i, candidates.count)
    let candidate = Candidate()
    candidates.insert(candidate, at: i)
    return candidate
  }

  /// Takes ownership of `candidate` (C++ `std::unique_ptr<Candidate>`).
  public func insertCandidate(_ i: Int, _ candidate: Candidate) {
    if i <= 0 {
      candidates.insert(candidate, at: 0)
    } else if i >= candidates.count {
      candidates.append(candidate)
    } else {
      candidates.insert(candidate, at: i)
    }
  }

  public func insertCandidates(_ i: Int, _ newCandidates: [Candidate]) {
    let i = max(0, min(i, candidates.count))
    candidates.insert(contentsOf: newCandidates, at: i)
  }

  /// get size of candidates
  public var candidatesSize: Int { candidates.count }

  // erase candidate
  public func popFrontCandidate() {
    if !candidates.isEmpty {
      candidates.removeFirst()
    }
  }

  public func popBackCandidate() {
    if !candidates.isEmpty {
      candidates.removeLast()
    }
  }

  public func eraseCandidate(_ i: Int) {
    if i < 0 || i >= candidatesSize {
      // LOG(WARNING) << "invalid index";
      return
    }
    candidates.remove(at: i)
  }

  public func eraseCandidates(_ i: Int, _ size: Int) {
    let end = i + size
    if i < 0 || i >= candidatesSize || end > candidatesSize {
      // LOG(WARNING) << "invalid index";
      return
    }
    candidates.removeSubrange(i..<end)
  }

  /// erase all candidates
  /// do not erase meta candidates
  public func clearCandidates() {
    candidates.removeAll(keepingCapacity: true)
  }

  // meta candidates
  // TODO(toshiyuki): Integrate meta candidates to candidate and delete these
  public var metaCandidatesSize: Int { metaCandidates.count }
  public func clearMetaCandidates() { metaCandidates.removeAll() }

  public func metaCandidate(_ i: Int) -> Candidate {
    var i = i
    if i >= metaCandidates.count {
      // LOG(ERROR) << "Invalid index number of meta_candidate: " << i;
      i = 0
    }
    return metaCandidates[i]
  }

  public func mutableMetaCandidate(_ i: Int) -> Candidate { metaCandidate(i) }

  @discardableResult
  public func addMetaCandidate() -> Candidate {
    let candidate = Candidate()
    metaCandidates.append(candidate)
    return candidate
  }

  /// move old_idx-th-candidate to new_index
  public func moveCandidate(_ oldIdx: Int, _ newIdx: Int) {
    // meta candidates
    if oldIdx < 0 {
      let metaIdx = -oldIdx - 1
      guard let c = insertCandidate(newIdx) else { return }
      c.assign(from: metaCandidates[metaIdx])
      return
    }

    // normal segment
    if oldIdx < 0 || oldIdx >= candidatesSize || newIdx >= candidatesSize || oldIdx == newIdx {
      // MOZC_VLOG(1) << "old_idx and new_idx are the same";
      return
    }
    if oldIdx > newIdx {  // promotion
      let c = candidates[oldIdx]
      var i = oldIdx
      while i >= newIdx + 1 {
        candidates[i] = candidates[i - 1]
        i -= 1
      }
      candidates[newIdx] = c
    } else {  // demotion
      let c = candidates[oldIdx]
      for i in oldIdx..<newIdx {
        candidates[i] = candidates[i + 1]
      }
      candidates[newIdx] = c
    }
  }

  public func clear() {
    clearCandidates()
    key = ""
    keyLen = 0
    metaCandidates.removeAll()
    segmentType = .free
  }

  public func debugString() -> String {
    // C++ streams the uint8_t-based enum, which prints it as a raw char.
    var os = "[segtype=\(Character(Unicode.Scalar(segmentType.rawValue))) key=\(key)\n"
    let size = candidatesSize + metaCandidatesSize
    for l in 0..<size {
      let j = l < metaCandidatesSize ? -l - 1 : l - metaCandidatesSize
      os += "    cand \(j) \(candidate(j).debugString())"
    }
    os += "]\n"
    return os
  }

  private func deepCopyCandidates(_ source: [Candidate]) {
    candidates.reserveCapacity(source.count)
    for cand in source {
      candidates.append(cand.copy())
    }
  }
}

/// `mozc::converter::Segments`: basically an array of Segment.
///
/// Note that there are two types of Segment
/// a) History Segment (SegmentType == HISTORY OR SUBMITTED)
///    Segments user entered just before the transacton
/// b) Conversion Segment
///    Current segments user inputs
///
/// Array of segment is represented as an array as follows
/// segments_array[] = {HS_0,HS_1,...HS_N, CS0, CS1, CS2...}
///
/// * segment(i) and mutableSegment(i)
///  access segment regardless of History/Conversion distinctions
///
/// * historySegment(i) and mutableHistorySegment(i)
///  access only History Segment
///
/// conversionSegment(i) and mutableConversionSegment(i)
///  access only Conversion Segment
///  segment(i + historySegmentsSize) == conversionSegment(i)
///
/// The C++ iterator ranges (`all()`, `history_segments()`,
/// `conversion_segments()`) are `[Segment]` arrays here (the elements are the
/// same objects, so mutating them mutates the segments); `drop` / `take` /
/// `takeLast` / `subrange` are provided as array extensions. Indices of a
/// range are relative to the range, like C++ `Range::operator[]`.
public final class Segments {
  private static let kMaxHistorySize = 32

  // LINT.IfChange
  public private(set) var all: [Segment] = []
  /// Revert id.
  /// Client remembers the last finish operation with `revert_id`.
  /// TODO(taku): support multiple revert ids to support undo/redo.
  public var revertId: UInt64 = 0
  public private(set) var maxHistorySegmentsSize: Int = 0
  public var resized: Bool = false
  // LINT.ThenChange(//converter/segments_matchers.h)

  public init() {}

  /// C++ copy constructor.
  public convenience init(copying x: Segments) {
    self.init()
    assign(from: x)
  }

  /// C++ copy constructor.
  public func copy() -> Segments { Segments(copying: self) }

  /// C++ copy assignment: deep-copies the segments.
  public func assign(from x: Segments) {
    if x === self { return }
    clear()
    maxHistorySegmentsSize = x.maxHistorySegmentsSize
    resized = x.resized
    // Deep-copy segments.
    for segment in x.all {
      addSegment().assign(from: segment)
    }
    revertId = x.revertId
  }

  // ranges
  public var historySegments: [Segment] { Array(all[0..<historySegmentsEnd]) }
  public var conversionSegments: [Segment] { Array(all[historySegmentsEnd...]) }

  // getter
  public func segment(_ i: Int) -> Segment { all[i] }
  public func conversionSegment(_ i: Int) -> Segment { all[i + historySegmentsSize] }
  public func historySegment(_ i: Int) -> Segment { all[i] }

  // setter (same objects as the getters; kept for C++ readability)
  public func mutableSegment(_ i: Int) -> Segment { all[i] }
  public func mutableConversionSegment(_ i: Int) -> Segment { all[i + historySegmentsSize] }
  public func mutableHistorySegment(_ i: Int) -> Segment { all[i] }

  // push and insert segments
  @discardableResult
  public func pushFrontSegment() -> Segment {
    let segment = Segment()
    all.insert(segment, at: 0)
    return segment
  }

  @discardableResult
  public func pushBackSegment() -> Segment {
    let segment = Segment()
    all.append(segment)
    return segment
  }

  /// alias of pushBackSegment()
  @discardableResult
  public func addSegment() -> Segment { pushBackSegment() }

  @discardableResult
  public func insertSegment(_ i: Int) -> Segment {
    let segment = Segment()
    all.insert(segment, at: i)
    return segment
  }

  // get size of segments
  public var segmentsSize: Int { all.count }

  /// Returns the end index of history segments.
  private var historySegmentsEnd: Int {
    var it = 0
    while it < all.count {
      let type = all[it].segmentType
      if type != .history && type != .submitted {
        break
      }
      it += 1
    }
    return it
  }

  public var historySegmentsSize: Int { historySegmentsEnd }
  public var conversionSegmentsSize: Int { segmentsSize - historySegmentsSize }

  // erase segment
  public func popFrontSegment() {
    if !all.isEmpty {
      all.removeFirst()
    }
  }

  public func popBackSegment() {
    if !all.isEmpty {
      all.removeLast()
    }
  }

  public func eraseSegment(_ i: Int) {
    if i < 0 || i >= segmentsSize {
      return
    }
    all.remove(at: i)
  }

  public func eraseSegments(_ i: Int, _ size: Int) {
    let end = i + size
    if i < 0 || i >= segmentsSize || end > segmentsSize {
      return
    }
    all.removeSubrange(i..<end)
  }

  /// Iterator-range erase (`erase_segments(first, last)`).
  public func eraseSegments(_ range: Range<Int>) {
    all.removeSubrange(range)
  }

  // erase all segments
  public func clearHistorySegments() {
    while let seg = all.first {
      if seg.segmentType != .history && seg.segmentType != .submitted {
        break
      }
      popFrontSegment()
    }
  }

  public func clearConversionSegments() {
    resized = false
    all.removeSubrange(historySegmentsEnd...)
  }

  public func clearSegments() {
    resized = false
    all.removeAll()
  }

  public func setMaxHistorySegmentsSize(_ maxHistorySegmentsSize: Int) {
    self.maxHistorySegmentsSize = max(0, min(maxHistorySegmentsSize, Self.kMaxHistorySize))
  }

  public func setResized(_ resized: Bool) { self.resized = resized }
  public func setRevertId(_ revertId: UInt64) { self.revertId = revertId }

  /// Returns history key of `size` segments.
  /// Returns all history key when size == -1.
  public func historyKey(_ size: Int = -1) -> String {
    var segments = historySegments
    if size != -1 {
      segments = segments.takeLast(size)
    }
    var historyKey = ""
    for seg in segments {
      if seg.candidatesSize == 0 { continue }
      historyKey += seg.candidate(0).key
    }
    return historyKey
  }

  /// Returns history value of `size` segments.
  /// Returns all history value when size == -1.
  public func historyValue(_ size: Int = -1) -> String {
    var segments = historySegments
    if size != -1 {
      segments = segments.takeLast(size)
    }
    var historyValue = ""
    for seg in segments {
      if seg.candidatesSize == 0 { continue }
      historyValue += seg.candidate(0).value
    }
    return historyValue
  }

  /// Initializes the segments with the given key as a preparation of conversion.
  public func initForConvert(_ key: some StringProtocol) {
    setMaxHistorySegmentsSize(4)
    clearConversionSegments()

    let segment = addSegment()
    segment.setKey(key)
    segment.segmentType = .free
  }

  /// Initializes the segments with the given key and value as a preparation of
  /// committing the value.
  public func initForCommit(_ key: some StringProtocol, _ value: some StringProtocol) {
    clearConversionSegments()

    let segment = addSegment()
    segment.setKey(key)
    segment.segmentType = .fixedValue

    let candidate = segment.addCandidate()
    candidate.key = String(key)
    candidate.contentKey = String(key)
    candidate.value = String(value)
    candidate.contentValue = String(value)
  }

  /// clear segments
  public func clear() {
    clearSegments()
    revertId = 0
  }

  /// Dump Segments structure
  public func debugString() -> String {
    var os = "{\n"
    for i in 0..<segmentsSize {
      os += "  seg \(i) \(segment(i).debugString())"
    }
    os += "}\n"
    return os
  }

  /// Prepend the candidates of `previousSegment` to the first conversion
  /// segment. This is used to merge the previous suggestion results to the
  /// prediction results.
  public func prependCandidates(_ previousSegment: Segment) {
    if conversionSegmentsSize == 0 {
      clearConversionSegments()
      let segment = addSegment()
      segment.setKey(previousSegment.key)
    }

    let segment = mutableConversionSegment(0)

    let candsSize = previousSegment.candidatesSize
    for i in 0..<candsSize {
      let candidate = segment.insertCandidate(i)!
      candidate.assign(from: previousSegment.candidate(i))
    }
    segment.metaCandidates = previousSegment.metaCandidates.map { $0.copy() }
  }

  /// Resize the segments starting from `startIndex` with the given `newSizes`.
  /// Returns true if the segments are resized.
  @discardableResult
  public func resize(_ startIndex: Int, _ newSizes: [UInt8]) -> Bool {
    let totalSize = newSizes.reduce(0) { $0 + Int($1) }
    if totalSize == 0 {
      return false
    }

    var key = ""
    var keyLen = 0
    var modifiedSegmentsSize = 0
    for segment in all.dropFirst(startIndex) {
      key += segment.key
      keyLen += segment.keyLen
      modifiedSegmentsSize += 1
      if keyLen >= totalSize {
        break
      }
    }

    // If key is empty or less than the total size of new segments, return false.
    if keyLen == 0 || keyLen < totalSize {
      return false
    }

    var consumed = 0
    var newKeys: [String] = []
    newKeys.reserveCapacity(newSizes.count)

    for newSize in newSizes {
      if newSize != 0 && consumed < keyLen {
        newKeys.append(String(Util.utf8SubString(key, consumed, Int(newSize))))
        consumed += Int(newSize)
      }
    }

    eraseSegments(startIndex, modifiedSegmentsSize)

    for i in 0..<newKeys.count {
      let seg = insertSegment(startIndex + i)
      seg.segmentType = .fixedBoundary
      seg.setKey(newKeys[i])
    }

    // If there is a remaining key, replace the next segment with the new key
    // prepending the remaining key to the next segment as a FREE type.
    if consumed < keyLen {
      var nextSegmentKey = String(Util.utf8SubString(key, consumed, keyLen - consumed))
      let nextSegmentIndex = startIndex + newKeys.count
      if nextSegmentIndex < segmentsSize {
        nextSegmentKey += segment(nextSegmentIndex).key
        eraseSegment(nextSegmentIndex)
      }
      let seg = insertSegment(nextSegmentIndex)
      seg.segmentType = .free
      seg.setKey(nextSegmentKey)
    }

    resized = true
    return true
  }
}

/// `Segments::Range` operations.
extension Array where Element == Segment {
  /// Skip first `count` elements, similar to `std::ranges::views::drop`.
  public func drop(_ count: Int) -> [Segment] {
    precondition(count >= 0)
    return Array(dropFirst(count))
  }

  /// Take first `count` elements, similar to `std::ranges::views::take`.
  public func take(_ count: Int) -> [Segment] {
    precondition(count >= 0)
    return Array(prefix(count))
  }

  /// Take `count` segments from the end.
  public func takeLast(_ count: Int) -> [Segment] {
    precondition(count >= 0)
    return drop(Swift.max(0, self.count - count))
  }

  /// Same as `drop(dropCount).take(count)`.
  public func subrange(_ index: Int, _ count: Int) -> [Segment] {
    drop(index).take(count)
  }
}
