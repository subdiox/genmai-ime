// Port of mozc/src/converter/converter_util_test.cc (3.35.6354).

import GenmaiBase
import Testing

@testable import GenmaiCore

private typealias CU = ConverterUtil

private func addCandidate(
  _ segment: Segment, key: String, value: String, contentKey: String = "", contentValue: String = "",
  convertedSegmentCount: UInt32? = nil
) -> Candidate {
  let c = segment.addCandidate()
  c.key = key
  c.value = value
  c.contentKey = contentKey
  c.contentValue = contentValue
  if let convertedSegmentCount { c.convertedSegmentCount = convertedSegmentCount }
  return c
}

private func result(_ key: String, _ value: String, _ boundary: [(Int, Int, Int, Int)]? = nil)
  -> PredictionResult
{
  var r = PredictionResult()
  r.key = key
  r.value = value
  if let boundary {
    r.innerSegmentBoundary = buildInnerSegmentBoundary(boundary, key, value)
  }
  return r
}

private func valueResult(_ value: String, attributes: UInt32 = 0) -> PredictionResult {
  var r = PredictionResult()
  r.value = value
  r.attributes = attributes
  return r
}

@Suite("ConverterUtil")
struct ConverterUtilTests {
  @Test func conversionSegmentsToResultEmpty() {
    let segments = Segments()
    #expect(CU.conversionSegmentsToResult(segments.conversionSegments) == nil)
  }

  @Test func conversionSegmentsToResultMultiSegment() throws {
    let segments = Segments()
    for i in 0..<3 {
      let segment = segments.addSegment()
      let c = segment.addCandidate()
      c.key = "key\(i)_part"
      c.contentKey = "key\(i)"
      c.value = "val\(i)_suff"
      c.contentValue = "val\(i)"
      c.lid = UInt16(i + 1)
      c.rid = UInt16(i + 2)
      c.cost = Int32(10 * (i + 1))
      c.wcost = Int32(5 * (i + 1))
      c.attributes = 1 << UInt32(i)
    }

    let result = try #require(CU.conversionSegmentsToResult(segments.conversionSegments))
    #expect(result.key == "key0_partkey1_partkey2_part")
    #expect(result.value == "val0_suffval1_suffval2_suff")
    #expect(result.lid == 1)
    #expect(result.rid == 4)
    #expect(result.cost == 10 + 20 + 30)
    #expect(result.wcost == 5 + 10 + 15)
    #expect(result.attributes == 1 | 2 | 4)

    // Verify boundary information.
    try #require(result.innerSegments().size == 3)
    var i = 0
    for innerSegment in result.innerSegments() {
      #expect(innerSegment.getKey() == "key\(i)_part")
      #expect(innerSegment.getContentKey() == "key\(i)")
      #expect(innerSegment.getValue() == "val\(i)_suff")
      #expect(innerSegment.getContentValue() == "val\(i)")
      i += 1
    }
    #expect(i == 3)
  }

  @Test func conversionSegmentsToResultWithMultiSegmentSpan() throws {
    let segments = Segments()
    // Segment 0: multi-segment candidate covering segments 0 and 1.
    do {
      let segment = segments.addSegment()
      segment.setKey("ここでは")
      let c = segment.addCandidate()
      c.key = "ここではきものを"
      c.value = "ここで履物を"
      c.convertedSegmentCount = 2
      c.innerSegmentBoundary = buildInnerSegmentBoundary([(9, 9, 6, 6), (15, 9, 12, 6)], c.key, c.value)
      c.lid = 10
      c.rid = 20
      c.cost = 100
      c.wcost = 50
    }
    // Segment 1: covered trailing segment (not yet erased).
    do {
      let segment = segments.addSegment()
      segment.setKey("きものを")
      let c = segment.addCandidate()
      c.key = "きものを"
      c.value = "着物を"
      c.contentKey = "きもの"
      c.contentValue = "着物"
      c.lid = 30
      c.rid = 40
      c.cost = 200
      c.wcost = 80
    }
    // Segment 2: uncovered segment.
    do {
      let segment = segments.addSegment()
      segment.setKey("ぬぐ")
      let c = segment.addCandidate()
      c.key = "ぬぐ"
      c.value = "脱ぐ"
      c.contentKey = "ぬぐ"
      c.contentValue = "脱ぐ"
      c.lid = 50
      c.rid = 60
      c.cost = 150
      c.wcost = 60
    }

    let result = try #require(CU.conversionSegmentsToResult(segments.conversionSegments))
    #expect(result.key == "ここではきものをぬぐ")
    #expect(result.value == "ここで履物を脱ぐ")
    #expect(result.lid == 10)
    #expect(result.rid == 60)
    #expect(result.cost == 100 + 150)
    #expect(result.wcost == 50 + 60)

    try #require(result.innerSegments().size == 3)
    let inner = Array(result.innerSegments())
    #expect(inner[0].getKey() == "ここで")
    #expect(inner[0].getValue() == "ここで")
    #expect(inner[1].getKey() == "はきものを")
    #expect(inner[1].getValue() == "履物を")
    #expect(inner[2].getKey() == "ぬぐ")
    #expect(inner[2].getValue() == "脱ぐ")
  }

  @Test func historySegmentsToResult() throws {
    let segments = Segments()
    for i in 0..<3 {
      let segment = segments.addSegment()
      segment.setSegmentType(.history)
      let c = segment.addCandidate()
      c.key = "key\(i)_part"
      c.contentKey = "key\(i)"
      c.value = "val\(i)_suff"
      c.contentValue = "val\(i)"
      c.lid = UInt16(i)
      c.rid = UInt16(i + 1)
      c.cost = Int32(i)
    }

    let result = CU.historySegmentsToResult(segments.historySegments)
    #expect(result.key == "key0_partkey1_partkey2_part")
    #expect(result.value == "val0_suffval1_suffval2_suff")
    #expect(result.lid == 0)
    #expect(result.rid == 3)
    #expect(result.cost == 2)  // only the last cost

    // Verify boundary information.
    try #require(result.innerSegments().size == 3)
    var i = 0
    for innerSegment in result.innerSegments() {
      #expect(innerSegment.getKey() == "key\(i)_part")
      #expect(innerSegment.getContentKey() == "key\(i)")
      #expect(innerSegment.getValue() == "val\(i)_suff")
      #expect(innerSegment.getContentValue() == "val\(i)")
      i += 1
    }
    #expect(i == 3)
  }

  @Test func candidateAndResultRoundTripWithEmptyBoundary() throws {
    let candidate = Candidate()
    candidate.key = "とうきょうに"
    candidate.value = "東京に"
    candidate.contentKey = "とうきょう"
    candidate.contentValue = "東京"
    candidate.lid = 100
    candidate.rid = 200
    candidate.cost = 500
    candidate.wcost = 300
    candidate.attributes = 4
    candidate.consumedKeySize = 5

    // CandidateToResult synthesizes single-segment boundary from
    // content_key/value.
    let result = CU.candidateToResult(candidate)
    #expect(result.key == "とうきょうに")
    #expect(result.value == "東京に")
    #expect(result.lid == 100)
    #expect(result.rid == 200)
    #expect(result.cost == 500)
    #expect(result.wcost == 300)
    #expect(result.attributes == 4)
    #expect(result.consumedKeySize == 5)

    try #require(result.innerSegments().size == 1)
    let inner = Array(result.innerSegments())[0]
    #expect(inner.getKey() == "とうきょうに")
    #expect(inner.getValue() == "東京に")
    #expect(inner.getContentKey() == "とうきょう")
    #expect(inner.getContentValue() == "東京")

    let newCand = Candidate()
    CU.populateCandidateFromResult(result, newCand)
    #expect(newCand.key == candidate.key)
    #expect(newCand.value == candidate.value)
    #expect(newCand.contentKey == candidate.contentKey)
    #expect(newCand.contentValue == candidate.contentValue)
    #expect(newCand.lid == candidate.lid)
    #expect(newCand.rid == candidate.rid)
    #expect(newCand.cost == candidate.cost)
    #expect(newCand.wcost == candidate.wcost)
    #expect(newCand.attributes == candidate.attributes)
    #expect(newCand.consumedKeySize == candidate.consumedKeySize)
    #expect(newCand.innerSegmentBoundary == result.innerSegmentBoundary)
  }

  @Test func candidateAndResultRoundTripWithMultiSegmentBoundary() throws {
    let candidate = Candidate()
    candidate.key = "とうきょうにいきました"
    candidate.value = "東京に行きました"
    candidate.innerSegmentBoundary = buildInnerSegmentBoundary(
      [(15, 6, 15, 6), (3, 3, 0, 0), (15, 15, 6, 3)], candidate.key, candidate.value)
    try #require(!candidate.innerSegmentBoundary.isEmpty)
    candidate.lid = 10
    candidate.rid = 20
    candidate.cost = 1000
    candidate.wcost = 600

    let result = CU.candidateToResult(candidate)
    #expect(result.innerSegmentBoundary == candidate.innerSegmentBoundary)
    try #require(result.innerSegments().size == 3)

    let newCand = Candidate()
    CU.populateCandidateFromResult(result, newCand)
    #expect(newCand.innerSegmentBoundary == candidate.innerSegmentBoundary)
    #expect(newCand.key == candidate.key)
    #expect(newCand.value == candidate.value)
    #expect(newCand.lid == candidate.lid)
    #expect(newCand.rid == candidate.rid)
    #expect(newCand.cost == candidate.cost)
    #expect(newCand.wcost == candidate.wcost)
  }

  @Test func prepareSegmentsFromRequest() throws {
    let historySegs = Segments()
    // History segment 0: "きょうは" -> "今日は" (content: "きょう" -> "今日")
    do {
      let hSeg = historySegs.addSegment()
      hSeg.setSegmentType(.history)
      let hCand = hSeg.addCandidate()
      hCand.key = "きょうは"
      hCand.value = "今日は"
      hCand.contentKey = "きょう"
      hCand.contentValue = "今日"
      hCand.lid = 10
      hCand.rid = 20
      hCand.cost = 50
    }
    // History segment 1: "とうきょうへ" -> "東京へ" (content: "とうきょう" ->
    // "東京")
    do {
      let hSeg = historySegs.addSegment()
      hSeg.setSegmentType(.history)
      let hCand = hSeg.addCandidate()
      hCand.key = "とうきょうへ"
      hCand.value = "東京へ"
      hCand.contentKey = "とうきょう"
      hCand.contentValue = "東京"
      hCand.lid = 11
      hCand.rid = 21
      hCand.cost = 100
    }

    let historyResult = CU.historySegmentsToResult(historySegs.historySegments)

    let request = ConversionRequestBuilder()
      .setHistoryResultView(historyResult)
      .setKey("はれ")
      .build()

    let reconstructed = CU.prepareSegmentsFromRequest(request)
    try #require(reconstructed.historySegmentsSize == 2)
    #expect(reconstructed.historySegment(0).key == "きょうは")
    #expect(reconstructed.historySegment(0).candidate(0).value == "今日は")
    #expect(reconstructed.historySegment(0).candidate(0).contentKey == "きょう")
    #expect(reconstructed.historySegment(0).candidate(0).contentValue == "今日")

    #expect(reconstructed.historySegment(1).key == "とうきょうへ")
    #expect(reconstructed.historySegment(1).candidate(0).value == "東京へ")
    #expect(reconstructed.historySegment(1).candidate(0).contentKey == "とうきょう")
    #expect(reconstructed.historySegment(1).candidate(0).contentValue == "東京")

    // The last history segment candidate should have the history cost and
    // rid.
    #expect(reconstructed.historySegment(1).candidate(0).rid == 21)
    #expect(reconstructed.historySegment(1).candidate(0).cost == 100)

    try #require(reconstructed.conversionSegmentsSize == 1)
    #expect(reconstructed.conversionSegment(0).key == "はれ")
  }

  @Test func conversionSegmentsToResults() throws {
    // Empty segments.
    do {
      let segments = Segments()
      #expect(CU.conversionSegmentsToResults(segments).isEmpty)
    }

    // Single segment and multiple candidates.
    do {
      let segments = Segments()
      let segment = segments.addSegment()
      for i in 0..<10 {
        let c = segment.addCandidate()
        c.key = "k\(i)"
        c.contentKey = "k"
        c.value = "v\(i)"
        c.contentValue = "v"
        c.description = "description"
        c.displayValue = "display_value"
        c.lid = UInt16(i)
        c.rid = UInt16(i + 1)
        c.cost = Int32(i + 2)
        c.wcost = Int32(10 * i)
      }

      let results = CU.conversionSegmentsToResults(segments)
      #expect(results.count == 5)
      for i in 0..<results.count {
        let c = segment.candidate(i)
        let result = results[i]
        #expect(c.key == result.key)
        #expect(c.value == result.value)
        #expect(c.description == result.description)
        #expect(c.displayValue == result.displayValue)
        #expect(c.lid == result.lid)
        #expect(c.rid == result.rid)
        #expect(Int(c.cost) == result.cost)
        #expect(Int(c.wcost) == result.wcost)

        try #require(result.innerSegments().size == 1)
        for iter in result.innerSegments() {
          #expect(iter.getKey() == c.key)
          #expect(iter.getContentKey() == c.contentKey)
          #expect(iter.getValue() == c.value)
          #expect(iter.getContentValue() == c.contentValue)
        }
      }

      // Custom max_results parameter.
      let resultsCustom = CU.conversionSegmentsToResults(segments, 8)
      #expect(resultsCustom.count == 8)
    }

    // Multiple segments.
    do {
      let segments = Segments()
      for i in 0..<3 {
        let segment = segments.addSegment()
        let c = segment.addCandidate()
        c.key = "k\(i)"
        c.contentKey = "k"
        c.value = "v\(i)"
        c.contentValue = "v"
        c.lid = UInt16(i)
        c.rid = UInt16(i + 1)
        c.cost = Int32(i)
        c.wcost = Int32(10 * i)
      }

      let results = CU.conversionSegmentsToResults(segments)
      try #require(results.count == 1)

      let result = results[0]
      #expect(result.key == "k0k1k2")
      #expect(result.value == "v0v1v2")
      #expect(result.lid == segments.segment(0).candidate(0).lid)
      #expect(result.rid == segments.segment(2).candidate(0).rid)
      #expect(result.cost == 0 + 1 + 2)
      #expect(result.wcost == 0 + 10 + 20)

      // Verify boundary iteration across multiple segments.
      try #require(result.innerSegments().size == 3)
      var n = 0
      for iter in result.innerSegments() {
        let c = segments.segment(n).candidate(0)
        #expect(iter.getKey() == c.key)
        #expect(iter.getContentKey() == c.contentKey)
        #expect(iter.getValue() == c.value)
        #expect(iter.getContentValue() == c.contentValue)
        n += 1
      }
      #expect(n == 3)
    }
  }

  @Test func applyResultToSegmentsMultiSegment() throws {
    // Conversion segments: "ここで"(9B) | "はきものを"(15B) | "ぬぐ"(6B)
    let segments = Segments()
    let s0 = segments.addSegment()
    s0.setKey("ここで")
    _ = addCandidate(s0, key: "ここで", value: "ここで", contentKey: "ここで", contentValue: "ここで")

    let s1 = segments.addSegment()
    s1.setKey("はきものを")
    _ = addCandidate(s1, key: "はきものを", value: "履物を", contentKey: "はきもの", contentValue: "履物")

    let s2 = segments.addSegment()
    s2.setKey("ぬぐ")
    _ = addCandidate(s2, key: "ぬぐ", value: "塗ぐ", contentKey: "ぬぐ", contentValue: "塗ぐ")
    _ = addCandidate(s2, key: "ぬぐ", value: "脱ぐ", contentKey: "ぬぐ", contentValue: "脱ぐ")

    // Result 0: "ここでは"(12B) | "着物を"(9B, key: "きものを" 12B) | "脱ぐ"(6B,
    // key: "ぬぐ" 6B)
    let predResult0 = result(
      "ここではきものをぬぐ", "ここでは着物を脱ぐ", [(12, 12, 9, 9), (12, 9, 9, 6), (6, 6, 6, 6)])

    // Result 1: "此処では"(12B) | "着物を"(9B, key: "きものを" 12B) | "脱ぐ"(6B,
    // key: "ぬぐ" 6B)
    let predResult1 = result(
      "ここではきものをぬぐ", "此処では着物を脱ぐ", [(12, 12, 9, 9), (12, 9, 9, 6), (6, 6, 6, 6)])

    // Apply result 0 at target_pos = 0.
    CU.applyResultToSegmentsMultiSegment(predResult0, 0, segments)

    // Segments structure is preserved.
    try #require(segments.conversionSegmentsSize == 3)
    #expect(segments.conversionSegment(0).key == "ここで")
    #expect(segments.conversionSegment(1).key == "はきものを")
    #expect(segments.conversionSegment(2).key == "ぬぐ")

    // Segment 0 contains multi-segment candidate "ここでは着物を" with
    // converted_segment_count = 2 at pos 0.
    let seg0 = segments.conversionSegment(0)
    try #require(seg0.candidatesSize > 0)
    #expect(seg0.candidate(0).value == "ここでは着物を")
    #expect(seg0.candidate(0).key == "ここではきものを")
    #expect(seg0.candidate(0).contentValue == "ここでは着物")
    #expect(seg0.candidate(0).contentKey == "ここではきもの")
    #expect(seg0.candidate(0).convertedSegmentCount == 2)
    #expect(seg0.candidate(0).innerSegmentBoundary.count == 2)

    // Segment 2 top candidate is moved to "脱ぐ".
    let seg2 = segments.conversionSegment(2)
    try #require(seg2.candidatesSize >= 2)
    #expect(seg2.candidate(0).value == "脱ぐ")
    #expect(seg2.candidate(0).innerSegmentBoundary.count == 1)
    #expect(seg2.candidate(1).value == "塗ぐ")

    // Apply result 1 at target_pos = 1.
    CU.applyResultToSegmentsMultiSegment(predResult1, 1, segments)

    // Segment 0 now contains "ここでは着物を" at pos 0 and "此処では着物を"
    // at pos 1.
    try #require(seg0.candidatesSize >= 2)
    #expect(seg0.candidate(0).value == "ここでは着物を")
    #expect(seg0.candidate(0).convertedSegmentCount == 2)
    #expect(seg0.candidate(1).value == "此処では着物を")
    #expect(seg0.candidate(1).convertedSegmentCount == 2)

    // Segment 2 top candidate "脱ぐ" was NOT demoted to pos 1.
    #expect(seg2.candidate(0).value == "脱ぐ")
    #expect(seg2.candidate(1).value == "塗ぐ")
  }

  @Test func applyResultToSegmentsMultiSegmentEmptyInnerSegmentBoundary() throws {
    do {
      // Multi-segment fallback when inner_segment_boundary is empty.
      let segments = Segments()
      let s0 = segments.addSegment()
      s0.setKey("わたしの")
      _ = addCandidate(s0, key: "わたしの", value: "私の", contentKey: "わたしの", contentValue: "私の")

      let s1 = segments.addSegment()
      s1.setKey("なまえ")
      _ = addCandidate(s1, key: "なまえ", value: "名前", contentKey: "なまえ", contentValue: "名前")

      var predResult = result("わたしのなまえ", "僕の名字")
      predResult.attributes =
        Attribute.userHistoryPrediction | Attribute.userHistoryEmptyInnerSegmentBoundary

      CU.applyResultToSegmentsMultiSegment(predResult, 0, segments)

      try #require(segments.conversionSegmentsSize == 2)
      let seg0 = segments.conversionSegment(0)
      try #require(seg0.candidatesSize > 0)
      #expect(seg0.candidate(0).value == "僕の名字")
      #expect(seg0.candidate(0).key == "わたしのなまえ")
      #expect(seg0.candidate(0).convertedSegmentCount == 2)
      #expect(seg0.candidate(0).attributes & Attribute.userHistoryPrediction != 0)
    }

    do {
      // Single-segment fallback when inner_segment_boundary is empty.
      let segments = Segments()
      let s0 = segments.addSegment()
      s0.setKey("あめ")
      _ = addCandidate(s0, key: "あめ", value: "飴", contentKey: "あめ", contentValue: "飴")

      let predResult = result("あめ", "雨")

      CU.applyResultToSegmentsMultiSegment(predResult, 0, segments)

      try #require(segments.conversionSegmentsSize == 1)
      let seg0 = segments.conversionSegment(0)
      try #require(seg0.candidatesSize > 0)
      #expect(seg0.candidate(0).value == "雨")
      #expect(seg0.candidate(0).key == "あめ")
      #expect(seg0.candidate(0).convertedSegmentCount == 1)
      #expect(seg0.candidate(0).innerSegmentBoundary.isEmpty)
    }
  }

  @Test func applyResultToSegmentsMultiSegmentKeyLengthMismatch() throws {
    do {
      // Conversion segments key is shorter than prediction result key.
      let segments = Segments()
      let s0 = segments.addSegment()
      s0.setKey("ここで")
      _ = addCandidate(s0, key: "ここで", value: "ここで")

      let predResult = result(
        "ここではきものをぬぐ", "ここでは着物を脱ぐ", [(12, 12, 9, 9), (12, 9, 9, 6), (6, 6, 6, 6)])

      CU.applyResultToSegmentsMultiSegment(predResult, 0, segments)

      try #require(segments.conversionSegmentsSize == 1)
      let seg0 = segments.conversionSegment(0)
      #expect(seg0.candidatesSize == 1)
      #expect(seg0.candidate(0).value == "ここで")
    }

    do {
      // Prediction result key is shorter than conversion segments key.
      let segments = Segments()
      let s0 = segments.addSegment()
      s0.setKey("ここで")
      _ = addCandidate(s0, key: "ここで", value: "ここで")

      let s1 = segments.addSegment()
      s1.setKey("はきものを")
      _ = addCandidate(s1, key: "はきものを", value: "履物を")

      let predResult = result("ここで", "此処で", [(9, 9, 9, 9)])

      CU.applyResultToSegmentsMultiSegment(predResult, 0, segments)

      try #require(segments.conversionSegmentsSize == 2)
      // Segment 0 matches and gets updated/promoted.
      #expect(segments.conversionSegment(0).candidate(0).value == "此処で")
      // Segment 1 is untouched.
      #expect(segments.conversionSegment(1).candidate(0).value == "履物を")
    }
  }

  @Test func applyResultToSegmentsMultiSegmentSingleVsMultiSegmentCandidateMatching() throws {
    let segments = Segments()
    let s0 = segments.addSegment()
    s0.setKey("とう")
    _ = addCandidate(s0, key: "とう", value: "東京", convertedSegmentCount: 1)
    _ = addCandidate(s0, key: "とう", value: "党", convertedSegmentCount: 1)

    let s1 = segments.addSegment()
    s1.setKey("きょう")
    _ = addCandidate(s1, key: "きょう", value: "京", convertedSegmentCount: 1)

    let predResultMulti = result("とうきょう", "東京", [(9, 3, 9, 3), (6, 3, 6, 3)])

    // 1. Apply multi-segment result (num_segs = 2).
    // Existing single-segment candidate "東京" (converted_segment_count = 1)
    // must NOT match. A new multi-segment candidate (converted_segment_count
    // = 2) is inserted at pos 0.
    CU.applyResultToSegmentsMultiSegment(predResultMulti, 0, segments)

    let seg0 = segments.mutableConversionSegment(0)
    try #require(seg0.candidatesSize == 3)
    #expect(seg0.candidate(0).value == "東京")
    #expect(seg0.candidate(0).convertedSegmentCount == 2)
    #expect(seg0.candidate(1).value == "東京")
    #expect(seg0.candidate(1).convertedSegmentCount == 1)
    #expect(seg0.candidate(2).value == "党")

    // 2. Apply multi-segment result again at target_pos = 0.
    // This time it matches existing candidate 0 (converted_segment_count =
    // 2), updating in place without inserting a new candidate.
    CU.applyResultToSegmentsMultiSegment(predResultMulti, 0, segments)
    try #require(seg0.candidatesSize == 3)
    #expect(seg0.candidate(0).value == "東京")
    #expect(seg0.candidate(0).convertedSegmentCount == 2)

    // 3. Apply single-segment result for "とう" -> "党".
    // Matches existing single-segment candidate "党" and moves it to pos 0.
    let predResultSingle = result("とう", "党", [(6, 6, 3, 3)])

    let singleSegSegments = Segments()
    let ss0 = singleSegSegments.addSegment()
    ss0.setKey("とう")
    _ = addCandidate(ss0, key: "とう", value: "東京", convertedSegmentCount: 2)  // multi-segment
    _ = addCandidate(ss0, key: "とう", value: "党", convertedSegmentCount: 1)

    CU.applyResultToSegmentsMultiSegment(predResultSingle, 0, singleSegSegments)

    let ssSeg0 = singleSegSegments.conversionSegment(0)
    try #require(ssSeg0.candidatesSize == 2)
    #expect(ssSeg0.candidate(0).value == "党")
    #expect(ssSeg0.candidate(0).convertedSegmentCount == 1)
    #expect(ssSeg0.candidate(1).value == "東京")
    #expect(ssSeg0.candidate(1).convertedSegmentCount == 2)
  }

  @Test func applyResultToSegmentsMultiSegmentBoundaryAndPositionVariations() throws {
    do {
      // Single-segment new candidate insertion with non-empty boundary on
      // empty candidate list (push_front_candidate path).
      let segments = Segments()
      segments.addSegment().setKey("あめ")

      let predResult = result("あめ", "雨", [(6, 3, 6, 3)])
      CU.applyResultToSegmentsMultiSegment(predResult, 0, segments)

      let seg0 = segments.conversionSegment(0)
      try #require(seg0.candidatesSize == 1)
      #expect(seg0.candidate(0).value == "雨")
      #expect(seg0.candidate(0).convertedSegmentCount == 1)
      #expect(!seg0.candidate(0).innerSegmentBoundary.isEmpty)
    }

    do {
      // Single-segment existing candidate update with non-empty boundary.
      let segments = Segments()
      let s0 = segments.addSegment()
      s0.setKey("あめ")
      _ = addCandidate(s0, key: "あめ", value: "雨", convertedSegmentCount: 1)

      let predResult = result("あめ", "雨", [(6, 3, 6, 3)])
      CU.applyResultToSegmentsMultiSegment(predResult, 0, segments)

      let seg0 = segments.conversionSegment(0)
      try #require(seg0.candidatesSize == 1)
      #expect(!seg0.candidate(0).innerSegmentBoundary.isEmpty)
    }

    do {
      // Multi-segment existing candidate update sets sliced
      // inner_segment_boundary.
      let segments = Segments()
      let s0 = segments.addSegment()
      s0.setKey("とう")
      _ = addCandidate(s0, key: "とうきょう", value: "東京", convertedSegmentCount: 2)
      segments.addSegment().setKey("きょう")

      let predResult = result("とうきょう", "東京", [(9, 3, 9, 3), (6, 3, 6, 3)])
      CU.applyResultToSegmentsMultiSegment(predResult, 0, segments)

      let seg0 = segments.conversionSegment(0)
      try #require(seg0.candidatesSize == 1)
      #expect(seg0.candidate(0).innerSegmentBoundary.count == 2)
    }

    do {
      // Target pos beyond candidate list size inserts at end.
      let segments = Segments()
      let s0 = segments.addSegment()
      s0.setKey("あめ")
      _ = addCandidate(s0, key: "あめ", value: "飴", convertedSegmentCount: 1)

      let predResult = result("あめ", "雨")
      CU.applyResultToSegmentsMultiSegment(predResult, 10, segments)

      let seg0 = segments.conversionSegment(0)
      try #require(seg0.candidatesSize == 2)
      #expect(seg0.candidate(0).value == "飴")
      #expect(seg0.candidate(1).value == "雨")
    }
  }

  @Test func mergePredictionResultsNormalHistory() throws {
    let h0 = valueResult("history0")
    let h1 = valueResult("history1")
    let pc0 = valueResult("pc0")
    let pc1 = valueResult("history0")  // duplicate with h0

    let merged = CU.mergePredictionResults([h0, h1], [pc0, pc1])
    try #require(merged.count == 3)
    #expect(merged[0].value == "history0")
    #expect(merged[1].value == "history1")
    #expect(merged[2].value == "pc0")
  }

  @Test func mergePredictionResultsWeakHistory() throws {
    let h0 = valueResult("weak_history0", attributes: Attribute.weakUserHistoryPrediction)
    let h1 = valueResult("weak_history1")
    let pc0 = valueResult("pc0")
    let pc1 = valueResult("pc1")

    let merged = CU.mergePredictionResults([h0, h1], [pc0, pc1])
    try #require(merged.count == 4)
    // pc0 is placed at position 0, history follows, then remaining pc results.
    #expect(merged[0].value == "pc0")
    #expect(merged[1].value == "weak_history0")
    #expect(merged[2].value == "weak_history1")
    #expect(merged[3].value == "pc1")
  }

  @Test func mergePredictionResultsEmptyInputs() throws {
    let r0 = valueResult("value0")

    #expect(CU.mergePredictionResults([], []).isEmpty)

    let onlyHistory = CU.mergePredictionResults([r0], [])
    try #require(onlyHistory.count == 1)
    #expect(onlyHistory[0].value == "value0")

    let onlyPc = CU.mergePredictionResults([], [r0])
    try #require(onlyPc.count == 1)
    #expect(onlyPc[0].value == "value0")
  }
}
