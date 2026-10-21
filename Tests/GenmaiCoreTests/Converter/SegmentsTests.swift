// Port of mozc/src/converter/segments_test.cc (3.35.6354).
//
// The object pool checks (SegmentsPoolAccessorTestPeer::released_size) are
// not ported: the Swift Segments has no object pool.

import Testing
@testable import GenmaiCore

@Suite struct SegmentsTests {
  private func toKeys(_ segments: [Segment]) -> [String] { segments.map(\.key) }

  @Test func basicTest() {
    let segments = Segments()
    #expect(segments.segmentsSize == 0)

    let kSegmentsSize = 5
    var seg: [Segment] = []
    for i in 0..<kSegmentsSize {
      #expect(segments.segmentsSize == i)
      seg.append(segments.pushBackSegment())
      #expect(segments.segmentsSize == i + 1)
    }

    #expect(!segments.debugString().isEmpty)

    #expect(!segments.resized)
    segments.setResized(true)
    #expect(segments.resized)
    segments.setResized(false)
    #expect(!segments.resized)

    segments.setMaxHistorySegmentsSize(10)
    #expect(segments.maxHistorySegmentsSize == 10)
    segments.setMaxHistorySegmentsSize(5)
    #expect(segments.maxHistorySegmentsSize == 5)

    for i in 0..<kSegmentsSize {
      #expect(segments.mutableSegment(i) === seg[i])
    }

    segments.popBackSegment()
    #expect(segments.mutableSegment(3) === seg[3])

    segments.popFrontSegment()
    #expect(segments.mutableSegment(0) === seg[1])

    segments.clear()
    #expect(segments.segmentsSize == 0)

    for i in 0..<kSegmentsSize {
      seg[i] = segments.pushBackSegment()
    }

    // erase
    segments.eraseSegment(1)
    #expect(segments.mutableSegment(0) === seg[0])
    #expect(segments.mutableSegment(1) === seg[2])

    segments.eraseSegments(1, 2)
    #expect(segments.mutableSegment(0) === seg[0])
    #expect(segments.mutableSegment(1) === seg[4])

    #expect(segments.segmentsSize == 2)

    segments.eraseSegments(0, 1)
    #expect(segments.segmentsSize == 1)
    #expect(segments.mutableSegment(0) === seg[4])

    // insert
    seg[1] = segments.insertSegment(1)
    #expect(segments.mutableSegment(1) === seg[1])

    segments.clear()
    for i in 0..<kSegmentsSize {
      seg[i] = segments.pushBackSegment()
      if i < 2 {
        seg[i].setSegmentType(.history)
      }
    }

    // history/conversion
    for i in 0..<3 {
      #expect(segments.mutableSegment(i + segments.historySegmentsSize) === segments.mutableConversionSegment(i))
    }

    #expect(segments.historySegmentsSize == 2)
    #expect(segments.conversionSegmentsSize == 3)

    #expect(segments.mutableConversionSegment(0) === seg[2])
    #expect(segments.mutableHistorySegment(0) === seg[0])

    segments.mutableHistorySegment(0).addCandidate().key = "a"
    segments.mutableHistorySegment(1).addCandidate().key = "b"

    #expect(segments.historyKey() == "ab")
    #expect(segments.historyKey(1) == "b")
    #expect(segments.historyKey(2) == "ab")
    #expect(segments.historyKey(3) == "ab")

    segments.mutableHistorySegment(0).mutableCandidate(0).value = "A"
    segments.mutableHistorySegment(1).mutableCandidate(0).value = "B"

    #expect(segments.historyValue() == "AB")
    #expect(segments.historyValue(1) == "B")
    #expect(segments.historyValue(2) == "AB")
    #expect(segments.historyValue(3) == "AB")

    segments.clearHistorySegments()
    #expect(segments.segmentsSize == 3)

    segments.clearConversionSegments()
    #expect(segments.segmentsSize == 0)
  }

  @Test func candidateTest() {
    let segment = Segment()

    let str = "this is a test"
    segment.setKey(str)
    #expect(segment.key == str)

    segment.setSegmentType(.fixedBoundary)
    #expect(segment.segmentType == .fixedBoundary)

    let kCandidatesSize = 5
    var cand: [Candidate] = []
    for i in 0..<kCandidatesSize {
      #expect(segment.candidatesSize == i)
      cand.append(segment.pushBackCandidate())
      #expect(segment.candidatesSize == i + 1)
    }

    for i in 0..<kCandidatesSize {
      #expect(segment.mutableCandidate(i) === cand[i])
    }

    for i in 0..<kCandidatesSize {
      #expect(segment.isValidIndex(i))
    }
    #expect(!segment.isValidIndex(kCandidatesSize))

    let kMetaCandidatesSize = segment.metaCandidatesSize
    for i in -kMetaCandidatesSize..<0 {
      #expect(segment.isValidIndex(i))
    }
    #expect(segment.isValidIndex(-kMetaCandidatesSize))
    #expect(!segment.isValidIndex(-kMetaCandidatesSize - 1))

    segment.popBackCandidate()
    #expect(segment.mutableCandidate(3) === cand[3])

    segment.popFrontCandidate()
    #expect(segment.mutableCandidate(0) === cand[1])

    // Pop functions against empty candidates should not raise a runtime error.
    segment.clear()
    segment.popBackCandidate()
    segment.popFrontCandidate()
    #expect(segment.candidatesSize == 0)

    for i in 0..<kCandidatesSize {
      cand[i] = segment.pushBackCandidate()
    }

    // erase
    segment.eraseCandidate(1)
    #expect(segment.mutableCandidate(0) === cand[0])
    #expect(segment.mutableCandidate(1) === cand[2])

    segment.eraseCandidates(1, 2)
    #expect(segment.mutableCandidate(0) === cand[0])
    #expect(segment.mutableCandidate(1) === cand[4])
    #expect(segment.candidatesSize == 2)

    // insert
    cand[1] = segment.insertCandidate(1)!
    #expect(segment.mutableCandidate(1) === cand[1])
    #expect(segment.mutableCandidate(2) === cand[4])

    // insert with a candidate
    let c0 = Candidate()
    c0.value = "c0"
    segment.insertCandidate(1, c0)
    #expect(segment.mutableCandidate(0) === cand[0])
    #expect(segment.candidate(1).value == "c0")
    #expect(segment.mutableCandidate(2) === cand[1])

    // insert multiple candidates
    cand[2] = Candidate()
    cand[3] = Candidate()
    segment.insertCandidates(2, [cand[2], cand[3]])
    #expect(segment.candidate(1).value == "c0")
    #expect(segment.mutableCandidate(2) === cand[2])
    #expect(segment.mutableCandidate(3) === cand[3])
    #expect(segment.mutableCandidate(4) === cand[1])
    #expect(segment.mutableCandidate(5) === cand[4])

    // insert candidate with index out of the range.
    segment.clear()
    #expect(segment.candidatesSize == 0)
    segment.insertCandidate(-1, Candidate())  // less than lower
    #expect(segment.candidatesSize == 1)
    segment.insertCandidate(5, Candidate())  // more than upper
    #expect(segment.candidatesSize == 2)

    // insert candidates with index out of the range.
    segment.clear()
    #expect(segment.candidatesSize == 0)
    segment.insertCandidates(-1, [Candidate(), Candidate()])  // less than lower
    #expect(segment.candidatesSize == 2)
    segment.insertCandidates(5, [Candidate(), Candidate(), Candidate()])  // more than upper
    #expect(segment.candidatesSize == 5)

    // move
    segment.clear()
    for i in 0..<kCandidatesSize {
      cand[i] = segment.pushBackCandidate()
    }

    segment.moveCandidate(2, 0)
    #expect(segment.mutableCandidate(0) === cand[2])
    #expect(segment.mutableCandidate(1) === cand[0])
    #expect(segment.mutableCandidate(2) === cand[1])
  }

  @Test func revertEntryTest() {
    let segments = Segments()
    #expect(segments.revertId == 0)
    segments.setRevertId(123)
    #expect(segments.revertId == 123)
    segments.clear()
    #expect(segments.revertId == 0)
  }

  @Test func copyTest() {
    let src = Segments()
    src.setMaxHistorySegmentsSize(1)
    src.setResized(true)

    let kSegmentsSize = 3
    let kCandidatesSize = 2
    for i in 0..<kSegmentsSize {
      let segment = src.addSegment()
      segment.setKey("segment_\(i)")
      for _ in 0..<kCandidatesSize {
        segment.addCandidate().key = "candidate_\(i)"
      }
    }
    #expect(src.segmentsSize == kSegmentsSize)
    #expect(src.segment(0).candidatesSize == kCandidatesSize)

    let dest = src.copy()
    #expect(dest.maxHistorySegmentsSize == src.maxHistorySegmentsSize)
    #expect(dest.resized == src.resized)
    #expect(dest.segmentsSize == kSegmentsSize)
    #expect(dest.segment(0).candidatesSize == kCandidatesSize)

    for i in 0..<kSegmentsSize {
      #expect(dest.segment(i).key == src.segment(i).key)
      #expect(dest.segment(i) !== src.segment(i))
      for j in 0..<kCandidatesSize {
        #expect(src.segment(i).candidate(j).key == dest.segment(i).candidate(j).key)
        #expect(src.segment(i).candidate(j) !== dest.segment(i).candidate(j))
      }
    }
    #expect(equalsSegments(dest, src) == nil)
  }

  @Test func initForConvert() {
    let segments = Segments()
    segments.initForConvert("first")
    #expect(segments.conversionSegmentsSize == 1)
    #expect(segments.conversionSegment(0).key == "first")
    #expect(segments.conversionSegment(0).segmentType == .free)
    #expect(segments.conversionSegment(0).candidatesSize == 0)

    let segment = segments.addSegment()
    segment.setKey("second")
    #expect(segments.conversionSegmentsSize == 2)

    segments.initForConvert("update")
    #expect(segments.conversionSegmentsSize == 1)
    #expect(segments.conversionSegment(0).key == "update")
    #expect(segments.conversionSegment(0).segmentType == .free)
  }

  @Test func initForCommit() throws {
    let segments = Segments()
    segments.initForCommit("key", "value")
    #expect(segments.conversionSegmentsSize == 1)
    let segment = segments.conversionSegment(0)
    #expect(segment.key == "key")
    #expect(segment.segmentType == .fixedValue)
    try #require(segment.candidatesSize == 1)
    #expect(segment.candidate(0).key == "key")
    #expect(segment.candidate(0).value == "value")
    #expect(segment.candidate(0).contentKey == "key")
    #expect(segment.candidate(0).contentValue == "value")
  }

  @Test func prependCandidates() {
    let segments = Segments()
    segments.initForConvert("key")
    #expect(segments.conversionSegmentsSize == 1)
    #expect(segments.conversionSegment(0).key == "key")
    #expect(segments.conversionSegment(0).segmentType == .free)
    #expect(segments.conversionSegment(0).candidatesSize == 0)
    #expect(segments.conversionSegment(0).metaCandidatesSize == 0)

    let candidate = segments.mutableConversionSegment(0).addCandidate()
    candidate.key = "key"
    candidate.value = "base"

    let metaCandidate = Candidate()
    metaCandidate.key = "key"
    metaCandidate.value = "meta"
    segments.mutableConversionSegment(0).metaCandidates.append(metaCandidate)

    #expect(segments.conversionSegment(0).candidatesSize == 1)
    #expect(segments.conversionSegment(0).metaCandidatesSize == 1)

    let prependedSegment = Segment()
    do {
      prependedSegment.setKey("key2")
      let candidate1 = prependedSegment.addCandidate()
      candidate1.key = "key2"
      candidate1.value = "prepended1"
      let candidate2 = prependedSegment.addCandidate()
      candidate2.key = "key2"
      candidate2.value = "prepended2"

      let metaCandidate = Candidate()
      metaCandidate.key = "key2"
      metaCandidate.value = "prepended_meta"
      prependedSegment.metaCandidates.append(metaCandidate)
    }

    segments.prependCandidates(prependedSegment)
    #expect(segments.conversionSegmentsSize == 1)
    #expect(segments.conversionSegment(0).key == "key")
    #expect(segments.conversionSegment(0).candidatesSize == 3)
    #expect(segments.conversionSegment(0).candidate(0).value == "prepended1")
    #expect(segments.conversionSegment(0).candidate(1).value == "prepended2")
    #expect(segments.conversionSegment(0).candidate(2).value == "base")

    #expect(segments.conversionSegment(0).metaCandidatesSize == 1)
    #expect(segments.conversionSegment(0).metaCandidate(0).value == "prepended_meta")
  }

  @discardableResult
  private func addSegment(_ key: String, _ type: Segment.SegmentType, _ segments: Segments) -> Segment {
    let segment = segments.addSegment()
    segment.setKey(key)
    segment.setSegmentType(type)
    return segment
  }

  private func pushBackCandidate(_ text: String, _ segment: Segment) {
    let cand = segment.pushBackCandidate()
    cand.key = text
    cand.contentKey = text
    cand.value = text
    cand.contentValue = text
  }

  @Test func resize() throws {
    do {
      // Resize {"あいうえ"} to {"あいう", "え"}
      let segments = Segments()
      addSegment("あいうえ", .free, segments)
      #expect(segments.conversionSegmentsSize == 1)
      #expect(segments.resize(0, [3, 1]))
      try #require(segments.conversionSegmentsSize == 2)
      #expect(toKeys(segments.conversionSegments) == ["あいう", "え"])
      #expect(segments.conversionSegments.map(\.segmentType) == [.fixedBoundary, .fixedBoundary])
    }
    do {
      // Empty resizes
      let segments = Segments()
      addSegment("あいうえ", .free, segments)
      #expect(!segments.resize(0, []))
      try #require(segments.conversionSegmentsSize == 1)
      #expect(segments.conversionSegment(0).key == "あいうえ")
      #expect(segments.conversionSegment(0).segmentType == .free)
    }
    do {
      // Resize {"あいうえ"} to {"あいう", "え"} with history segments.
      // Even if segments has histroy segments, arguments for ResizeSegment is not
      // changed.
      let segments = Segments()
      pushBackCandidate("ヤユヨ", addSegment("やゆよ", .history, segments))
      pushBackCandidate("ワヲン", addSegment("わをん", .history, segments))
      addSegment("あいうえ", .free, segments)
      // start_segment_index should skip history segments.
      #expect(segments.conversionSegmentsSize == 1)
      #expect(segments.resize(2, [3, 1]))
      try #require(segments.conversionSegmentsSize == 2)
      #expect(toKeys(segments.conversionSegments) == ["あいう", "え"])
      #expect(segments.conversionSegments.map(\.segmentType) == [.fixedBoundary, .fixedBoundary])
    }
    do {
      // Resize {"あいうえ"} to {"あいう", "え"} where size_array contains 0
      // values.
      let segments = Segments()
      addSegment("あいうえ", .free, segments)
      #expect(segments.resize(0, [3, 1, 0, 0, 0, 0, 0, 0]))
      try #require(segments.conversionSegmentsSize == 2)
      #expect(toKeys(segments.conversionSegments) == ["あいう", "え"])
      #expect(segments.conversionSegments.map(\.segmentType) == [.fixedBoundary, .fixedBoundary])
    }
    do {
      // Resize {"あいうえおかきくけ"} to {"あい", "うえ", "お", "かき", "くけ"}
      let segments = Segments()
      addSegment("あいうえおかきくけ", .free, segments)
      #expect(segments.resize(0, [2, 2, 1, 2, 2]))
      try #require(segments.conversionSegmentsSize == 5)
      #expect(toKeys(segments.conversionSegments) == ["あい", "うえ", "お", "かき", "くけ"])
      #expect(segments.conversionSegments.allSatisfy { $0.segmentType == .fixedBoundary })
    }
    do {
      // Resize {"あいう", "えお", "かき", "くけ"} to
      // {"あいうえ", "お", "かきくけ"}
      let segments = Segments()
      for key in ["あいう", "えお", "かき", "くけ"] { addSegment(key, .free, segments) }
      #expect(segments.conversionSegmentsSize == 4)
      #expect(segments.resize(0, [4, 1, 4]))
      try #require(segments.conversionSegmentsSize == 3)
      #expect(toKeys(segments.conversionSegments) == ["あいうえ", "お", "かきくけ"])
      #expect(segments.conversionSegments.allSatisfy { $0.segmentType == .fixedBoundary })
    }
    do {
      // Resize {"あいう", "えお", "かき", "くけ"} to
      // {"あいうえ", "お"} and keeping {"かき", "くけ"} as-is.
      let segments = Segments()
      for key in ["あいう", "えお", "かき", "くけ"] { addSegment(key, .free, segments) }
      #expect(segments.resize(0, [4, 1]))
      try #require(segments.conversionSegmentsSize == 4)
      #expect(toKeys(segments.conversionSegments) == ["あいうえ", "お", "かき", "くけ"])
      #expect(segments.conversionSegments.map(\.segmentType) == [.fixedBoundary, .fixedBoundary, .free, .free])
    }
    do {
      // Resize {"あいうえ"} to {"あいう"} and keeping {"え"} as-is.
      let segments = Segments()
      addSegment("あいうえ", .free, segments)
      #expect(segments.resize(0, [3]))
      try #require(segments.conversionSegmentsSize == 2)
      #expect(toKeys(segments.conversionSegments) == ["あいう", "え"])
      // Non specified segment (i.e. "え") is FREE to keep the consistency
      // with ResizeSegment.
      #expect(segments.conversionSegments.map(\.segmentType) == [.fixedBoundary, .free])
    }
    do {
      // Resize {"あいう", "えお", "かき", "くけ"} to {"かきくけ"} while
      // {"あいう", "えお"} are free to be modified.
      let segments = Segments()
      for key in ["あいう", "えお", "かき", "くけ"] { addSegment(key, .free, segments) }
      #expect(segments.resize(2, [4]))
      let resizedSize = segments.conversionSegmentsSize
      let lastSegment = segments.conversionSegment(resizedSize - 1)
      #expect(lastSegment.key == "かきくけ")
      #expect(lastSegment.segmentType == .fixedBoundary)
    }
  }

  @Test func keyLength() {
    let segment = Segment()
    segment.setKey("test")
    #expect(segment.keyLen == 4)
    segment.setKey("あいう")
    #expect(segment.keyLen == 3)
  }

  @Test func copy() {
    let src = Segment()
    src.setKey("key")
    src.setSegmentType(.fixedValue)
    src.addCandidate().key = "candidate1->key"
    src.addCandidate().key = "candidate2->key"
    src.addMetaCandidate().key = "meta_candidate->key"

    // Test copy constructor.
    let dest = Segment(copying: src)
    #expect(dest.key == src.key)
    #expect(dest.keyLen == src.keyLen)
    #expect(dest.segmentType == src.segmentType)
    #expect(dest.candidate(0).key == src.candidate(0).key)
    #expect(dest.candidate(1).key == src.candidate(1).key)
    #expect(dest.metaCandidate(0).key == src.metaCandidate(0).key)
    #expect(dest.metaCandidate(0) !== src.metaCandidate(0))

    // Test copy assignment.
    dest.addCandidate().key = "placeholder"
    dest.addCandidate().key = "placeholder"
    dest.assign(from: src)
    #expect(dest.key == src.key)
    #expect(dest.keyLen == src.keyLen)
    #expect(dest.segmentType == src.segmentType)
    #expect(dest.candidatesSize == 2)
    #expect(dest.candidate(0).key == src.candidate(0).key)
    #expect(dest.candidate(1).key == src.candidate(1).key)
    #expect(dest.metaCandidate(0).key == src.metaCandidate(0).key)
  }

  @Test func metaCandidateTest() {
    let segment = Segment()
    #expect(segment.metaCandidatesSize == 0)

    let kCandidatesSize = 5
    let values = (0..<kCandidatesSize).map { String(UnicodeScalar(UInt8(ascii: "a") + UInt8($0))) }

    // add_meta_candidate()
    for i in 0..<kCandidatesSize {
      #expect(segment.metaCandidatesSize == i)
      segment.addMetaCandidate().value = values[i]
      #expect(segment.metaCandidatesSize == i + 1)
    }

    // mutable_candidate()
    for i in 0..<kCandidatesSize {
      #expect(segment.mutableCandidate(-i - 1).value == values[i])
    }
    // mutable_meta_candidate()
    for i in 0..<kCandidatesSize {
      #expect(segment.mutableMetaCandidate(i).value == values[i])
    }
    // candidate()
    for i in 0..<kCandidatesSize {
      #expect(segment.candidate(-i - 1).value == values[i])
    }
    // meta_candidate()
    for i in 0..<kCandidatesSize {
      #expect(segment.metaCandidate(i).value == values[i])
    }

    // mutable_meta_candidates
    do {
      #expect(segment.metaCandidates.count == kCandidatesSize)
      let cand = Candidate()
      cand.value = "Test"
      segment.metaCandidates.append(cand)
    }
    // meta_candidates
    do {
      let metaCandidates = segment.metaCandidates
      #expect(metaCandidates.count == kCandidatesSize + 1)
      for i in 0..<kCandidatesSize {
        #expect(metaCandidates[i].value == values[i])
      }
      #expect(metaCandidates[kCandidatesSize].value == "Test")
    }
    // clear
    segment.clearMetaCandidates()
    #expect(segment.metaCandidatesSize == 0)
  }

  @Test func iterator() {
    let kHistorySize = 2
    let kConversionSize = 3
    let segments = Segments()
    var segmentList: [Segment] = []
    for _ in 0..<kHistorySize {
      let segment = segments.pushBackSegment()
      segment.setSegmentType(.history)
      segmentList.append(segment)
    }
    for _ in 0..<kConversionSize {
      let segment = segments.pushBackSegment()
      segment.setSegmentType(.fixedValue)
      segmentList.append(segment)
    }

    var i = 0
    for segment in segments.all {
      #expect(segment === segmentList[i])
      i += 1
    }
    #expect(i == kHistorySize + kConversionSize)

    i = 0
    for segment in segments.historySegments {
      #expect(segment === segmentList[i])
      i += 1
    }
    #expect(i == kHistorySize)
    #expect(segments.historySegmentsSize == kHistorySize)
    #expect(segments.historySegments.count == kHistorySize)

    for segment in segments.conversionSegments {
      #expect(segment === segmentList[i])
      i += 1
    }
    #expect(i == kHistorySize + kConversionSize)
    #expect(segments.conversionSegmentsSize == kConversionSize)
    #expect(segments.conversionSegments.count == kConversionSize)
  }

  @Test func iteratorRange() {
    let segments = Segments()
    for i in 0..<5 {
      let segment = segments.pushBackSegment()
      segment.setSegmentType(.fixedValue)
      segment.setKey(String(i))
    }

    let all = segments.all
    #expect(toKeys(all) == ["0", "1", "2", "3", "4"])

    // Test simple cases.
    #expect(toKeys(all.drop(2)) == ["2", "3", "4"])
    #expect(toKeys(all.drop(4)) == ["4"])
    #expect(toKeys(all.take(2)) == ["0", "1"])
    #expect(toKeys(all.take(4)) == ["0", "1", "2", "3"])
    #expect(toKeys(all.subrange(2, 2)) == ["2", "3"])

    // Test when `count` is 0.
    #expect(toKeys(all.drop(0)) == ["0", "1", "2", "3", "4"])
    #expect(toKeys(all.take(0)) == [])
    #expect(toKeys(all.subrange(0, 0)) == [])
    #expect(toKeys(all.subrange(1, 0)) == [])

    // Test when `count` is equal to `size()`.
    #expect(toKeys(all.drop(5)) == [])
    #expect(toKeys(all.take(5)) == ["0", "1", "2", "3", "4"])
    #expect(toKeys(all.subrange(3, 2)) == ["3", "4"])

    // Test when `count` exceeds `size()`.
    #expect(toKeys(all.drop(6)) == [])
    #expect(toKeys(all.take(6)) == ["0", "1", "2", "3", "4"])
    #expect(toKeys(all.subrange(4, 2)) == ["4"])
    #expect(toKeys(all.subrange(5, 2)) == [])
    #expect(toKeys(all.subrange(6, 2)) == [])
    #expect(toKeys(all.takeLast(2)) == ["3", "4"])
  }

  // Swift-only: DebugString prints the segment type as a raw byte like C++.
  @Test func debugStringFormat() {
    let segment = Segment()
    segment.setKey("k")
    segment.setSegmentType(.fixedValue)
    segment.addCandidate().value = "v"
    #expect(segment.debugString().hasPrefix("[segtype=\u{02} key=k\n    cand 0 (key= ckey= val=v"))
  }
}
