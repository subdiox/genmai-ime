// Port of mozc/src/converter/converter_util.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - The functions live in the `ConverterUtil` namespace enum.
// - `Segments::const_range` is `[Segment]`.
// - `request.history_result()` is `any ConversionRequestHistoryResult`; it is
//   used as a `PredictionResult` when it is one (the default history result
//   is empty).

import GenmaiBase

public enum ConverterUtil {
  /// Converts the top candidate (candidate 0) of each segment in the given
  /// conversion segments to a single composite Result.
  ///
  /// Boundary handling:
  /// Aggregates the length information (key, value, content_key,
  /// content_value) of candidate(0) across all segments into
  /// `result.inner_segment_boundary` via InnerSegmentBoundaryBuilder.
  ///
  /// Returns nil if segments is empty or any segment has no candidates.
  public static func conversionSegmentsToResult(_ segments: [Segment])
    -> PredictionResult?
  {
    if segments.isEmpty {
      return nil
    }

    var result = PredictionResult()
    var builder = InnerSegmentBoundaryBuilder()
    var lastRid: UInt16 = 0
    var i = segments.startIndex
    while i < segments.endIndex {
      let segment = segments[i]
      if segment.candidatesSize == 0 {
        return nil
      }
      let candidate = segment.candidate(0)
      result.key += candidate.key
      result.value += candidate.value
      result.attributes |= candidate.attributes
      result.wcost += Int(candidate.wcost)
      result.cost += Int(candidate.cost)
      for data in candidate.innerSegments() {
        builder.add(data)
      }
      lastRid = candidate.rid
      i += Int(candidate.effectiveConvertedSegmentCount)
    }

    result.innerSegmentBoundary = builder.build(result.key, result.value)
    result.lid = segments.first!.candidate(0).lid
    result.rid = lastRid

    return result
  }

  /// Converts history segments to a single composite Result.
  ///
  /// Boundary handling:
  /// Aggregates the length information of candidate(0) from each HISTORY
  /// segment into `result.inner_segment_boundary` via
  /// InnerSegmentBoundaryBuilder, so that the history boundary information
  /// can be inspected via Result::inner_segments().
  ///
  /// Returns an empty Result if history_segments is empty.
  public static func historySegmentsToResult(_ historySegments: [Segment])
    -> PredictionResult
  {
    if historySegments.isEmpty {
      return PredictionResult()
    }

    var result = PredictionResult()
    var builder = InnerSegmentBoundaryBuilder()
    for segment in historySegments {
      if segment.candidatesSize == 0 {
        return PredictionResult.defaultResult
      }
      let candidate = segment.candidate(0)
      result.key += candidate.key
      result.value += candidate.value
      result.attributes |= candidate.attributes
      builder.add(
        candidate.key.utf8.count, candidate.value.utf8.count, candidate.contentKey.utf8.count,
        candidate.contentValue.utf8.count)
    }

    result.innerSegmentBoundary = builder.build(result.key, result.value)
    result.lid = historySegments.first!.candidate(0).lid
    result.rid = historySegments.last!.candidate(0).rid
    result.cost = Int(historySegments.last!.candidate(0).cost)

    return result
  }

  public static func historySegmentsToResult(_ segments: Segments) -> PredictionResult {
    historySegmentsToResult(segments.historySegments)
  }

  /// Converts conversion segments to a list of prediction::Result.
  /// - Single conversion segment: Returns up to `max_results` candidates as
  ///   individual Results via CandidateToResult.
  /// - Multiple conversion segments: Returns a single composite Result via
  ///   ConversionSegmentsToResult.
  public static func conversionSegmentsToResults(_ segments: Segments, _ maxResults: Int = 5)
    -> [PredictionResult]
  {
    if segments.conversionSegmentsSize == 0 {
      return []
    }

    // - segments_size = 1: Populates the nbest candidates to result.
    if segments.conversionSegmentsSize == 1 {
      var results: [PredictionResult] = []
      for candidate in segments.conversionSegment(0).candidates {
        results.append(candidateToResult(candidate))
        if results.count >= maxResults { break }
      }
      return results
    }

    // segments_size > 1: Populates the top candidate to result by
    //                    concatenating the segments.
    guard let result = conversionSegmentsToResult(segments.conversionSegments) else {
      return []
    }
    return [result]
  }

  /// Converts a single Candidate to a prediction::Result.
  ///
  /// Boundary handling:
  /// If candidate.inner_segment_boundary is already populated, it is copied
  /// as-is. If candidate.inner_segment_boundary is empty, a single-segment
  /// fallback boundary is automatically synthesized from the candidate's key,
  /// value, content_key, and content_value lengths.
  public static func candidateToResult(_ candidate: Candidate) -> PredictionResult {
    var result = PredictionResult()
    result.key = candidate.key
    result.value = candidate.value
    result.description = candidate.description
    result.displayValue = candidate.displayValue
    result.lid = candidate.lid
    result.rid = candidate.rid
    result.wcost = Int(candidate.wcost)
    result.cost = Int(candidate.cost)
    result.attributes = candidate.attributes
    result.consumedKeySize = candidate.consumedKeySize
    result.innerSegmentBoundary = candidate.innerSegmentBoundary
    if result.innerSegmentBoundary.isEmpty {
      result.innerSegmentBoundary = buildInnerSegmentBoundary(
        [
          (
            candidate.key.utf8.count, candidate.value.utf8.count, candidate.contentKey.utf8.count,
            candidate.contentValue.utf8.count
          )
        ], result.key, result.value)
    }
    return result
  }

  /// Populates Candidate fields from a prediction::Result.
  ///
  /// Boundary handling:
  /// - Moves result.inner_segment_boundary directly to
  ///   candidate->inner_segment_boundary.
  /// - Automatically updates candidate->content_key and
  ///   candidate->content_value from
  ///   result.inner_segments().GetMergedContentKeyAndValue().
  ///
  /// Note: This function only updates fields present in Result (key, value,
  /// content_key/value, cost, wcost, lid, rid, attributes, consumed_key_size,
  /// inner_segment_boundary, description, display_value). Pre-existing
  /// Candidate metadata (such as category, command, usage_id, prefix, suffix)
  /// is preserved.
  public static func populateCandidateFromResult(_ result: PredictionResult, _ candidate: Candidate) {
    // Note: Compute content_key and content_value from inner_segments before
    // moving result.key, result.value, and result.inner_segment_boundary.
    let (contentKey, contentValue) = result.innerSegments().getMergedContentKeyAndValue()
    candidate.contentKey = String(contentKey)
    candidate.contentValue = String(contentValue)
    candidate.key = result.key
    candidate.value = result.value
    candidate.description = result.description
    candidate.displayValue = result.displayValue
    candidate.lid = result.lid
    candidate.rid = result.rid
    candidate.wcost = Int32(truncatingIfNeeded: result.wcost)
    candidate.cost = Int32(truncatingIfNeeded: result.cost)
    candidate.attributes = result.attributes
    candidate.consumedKeySize = result.consumedKeySize
    candidate.innerSegmentBoundary = result.innerSegmentBoundary
  }

  /// Prepares Segments containing HISTORY segments and a new conversion
  /// segment for request.key().
  ///
  /// Boundary handling:
  /// Iterates through request.history_result().inner_segments() to unpack
  /// each inner segment into an independent HISTORY Segment with its
  /// respective key, value, content_key, and content_value.
  public static func prepareSegmentsFromRequest(_ request: ConversionRequest) -> Segments {
    let segments = Segments()
    let result =
      (request.historyResult() as? PredictionResult) ?? PredictionResult.defaultResult

    func addHistorySegment(
      _ key: Substring, _ value: Substring, _ contentKey: Substring, _ contentValue: Substring
    ) {
      let seg = segments.addSegment()
      seg.setKey(key)
      seg.setSegmentType(.history)
      let candidate = seg.addCandidate()
      candidate.key = String(key)
      candidate.value = String(value)
      candidate.contentKey = String(contentKey)
      candidate.contentValue = String(contentValue)
    }

    for iter in result.innerSegments() {
      addHistorySegment(
        iter.getKey(), iter.getValue(), iter.getContentKey(), iter.getContentValue())
    }

    let historySize = segments.historySegmentsSize
    if historySize > 0 {
      let candidate = segments.mutableHistorySegment(historySize - 1).mutableCandidate(0)
      candidate.cost = Int32(truncatingIfNeeded: result.cost)
      candidate.rid = result.rid
    }

    segments.addSegment().setKey(request.key())

    return segments
  }

  /// Merges user history prediction results and post-correction (supplemental
  /// model) results into a single list with deduplication.
  ///
  /// Ordering rules:
  /// - Default: Prioritizes user history results over post-correction
  ///   results.
  /// - Weak history: If the top user history candidate is weak (has
  ///   Attribute::WEAK_USER_HISTORY_PREDICTION), the top
  ///   post-correction/default result is prioritized at position 0 to prevent
  ///   low-confidence history from overriding Viterbi/PostCorrect, and history
  ///   candidates are demoted to subsequent positions (consistent with
  ///   Predictor::DemoteWeakUserHistory).
  /// - Deduplication: Candidates with duplicate values (spellings) are
  ///   skipped.
  public static func mergePredictionResults(
    _ userHistoryResults: [PredictionResult], _ pcResults: [PredictionResult]
  ) -> [PredictionResult] {
    var results: [PredictionResult] = []
    let isWeakHistory =
      !userHistoryResults.isEmpty
      && (userHistoryResults[0].attributes & Attribute.weakUserHistoryPrediction) != 0

    func appendUnique(_ res: PredictionResult, _ dst: inout [PredictionResult]) {
      if !dst.contains(where: { $0.value.bytesEqual(res.value) }) {
        dst.append(res)
      }
    }

    if isWeakHistory && !pcResults.isEmpty {
      // When the top history candidate is weak, prevent it from becoming the
      // top candidate by prioritizing pc_results.front() (default conversion
      // or post-corrected result) at position 0 and demoting history
      // candidates to subsequent positions (consistent with
      // Predictor::DemoteWeakUserHistory).
      results.append(pcResults[0])
      for res in userHistoryResults {
        appendUnique(res, &results)
      }
      for i in 1..<pcResults.count {
        appendUnique(pcResults[i], &results)
      }
    } else {
      // Normal history: user history results followed by post-correction
      // results.
      results = userHistoryResults
      for res in pcResults {
        appendUnique(res, &results)
      }
    }
    return results
  }

  /// Applies prediction `result` across conversion `segments` without
  /// resizing segment boundaries.
  ///
  /// Key boundaries between `segments` (conversion segment sequence) and
  /// `result.inner_segments()` (prediction inner segment sequence) are
  /// synchronized from front to back using a two-pointer walk.
  ///
  /// For each synchronized interval:
  /// - If the interval covers N > 1 conversion segments:
  ///     Inner segments in the interval are concatenated into a combined
  ///     value, and inserted/promoted in the start conversion segment as a
  ///     multi-segment candidate with `converted_segment_count = N`.
  /// - If the interval covers N == 1 conversion segment:
  ///     The inner segment candidate is inserted or promoted to `target_pos`.
  ///     To prevent higher-priority prediction candidates (e.g. from result 0)
  ///     from being demoted by subsequent lower-priority results, existing
  ///     candidates are only moved forward when `existing_index > target_pos`.
  /// (See converter_util.h for a worked example.)
  public static func applyResultToSegmentsMultiSegment(
    _ result: PredictionResult, _ targetPos: Int, _ segments: Segments
  ) {
    if result.key.isEmpty || result.value.isEmpty {
      return
    }

    // -------------------------------------------------------------------------
    // Step 1: Collect inner segment views from the prediction result.
    // Converts the inner segment iterator into a random-access vector.
    // -------------------------------------------------------------------------
    struct InnerSegView {
      var key: Substring
      var value: Substring
      var functionalKeySize: Int
      var functionalValueSize: Int
    }

    var innerSegs: [InnerSegView] = []
    for iter in result.innerSegments() {
      innerSegs.append(
        InnerSegView(
          key: iter.getKey(), value: iter.getValue(),
          functionalKeySize: iter.getFunctionalKey().utf8.count,
          functionalValueSize: iter.getFunctionalValue().utf8.count))
    }

    var segIdx = 0
    var innerIdx = 0
    let numConversionSegments = segments.conversionSegmentsSize
    let numInnerSegments = innerSegs.count

    // -------------------------------------------------------------------------
    // Step 2: Two-pointer boundary synchronization walk.
    // Walk through conversion segments and inner segments simultaneously from
    // front to back, finding intervals where cumulative key byte lengths
    // match.
    // -------------------------------------------------------------------------
    while segIdx < numConversionSegments && innerIdx < numInnerSegments {
      let startSeg = segIdx
      let startInner = innerIdx

      // Start with the first segment and inner segment in the current
      // interval.
      var segSpanBytes = segments.conversionSegment(segIdx).key.utf8.count
      var innerSpanBytes = innerSegs[innerIdx].key.utf8.count

      segIdx += 1
      innerIdx += 1

      // Advance whichever pointer has accumulated fewer key bytes until both
      // spans cover the exact same key byte length.
      while segSpanBytes != innerSpanBytes {
        if segSpanBytes < innerSpanBytes {
          if segIdx >= numConversionSegments { break }
          segSpanBytes += segments.conversionSegment(segIdx).key.utf8.count
          segIdx += 1
        } else {
          if innerIdx >= numInnerSegments { break }
          innerSpanBytes += innerSegs[innerIdx].key.utf8.count
          innerIdx += 1
        }
      }

      if segSpanBytes != innerSpanBytes {
        // LOG(WARNING) << "Key lengths mismatch between segments and result";
        break
      }

      // -----------------------------------------------------------------------
      // Step 3: Combine inner segments covered by the synchronized interval.
      // `num_segs` is the number of conversion segments spanned by this
      // interval. Since all inner segments are contiguous slices of
      // `result.key` and `result.value`, the combined key and value are
      // contiguous slices.
      // -----------------------------------------------------------------------
      let numSegs = segIdx - startSeg
      let firstInner = innerSegs[startInner]
      let lastInner = innerSegs[innerIdx - 1]

      let combinedKey = firstInner.key.base[firstInner.key.startIndex..<lastInner.key.endIndex]
      let combinedValue = firstInner.value.base[firstInner.value.startIndex..<lastInner.value.endIndex]

      let combinedContentKey = combinedKey.byteSubstring(
        from: 0, length: combinedKey.utf8.count - lastInner.functionalKeySize)
      let combinedContentValue = combinedValue.byteSubstring(
        from: 0, length: combinedValue.utf8.count - lastInner.functionalValueSize)

      // Target the first conversion segment in the interval.
      let targetSegment = segments.mutableConversionSegment(startSeg)

      // -----------------------------------------------------------------------
      // Step 4: Search for an existing candidate in the target segment.
      // Match by value and segment count (single vs multi-segment).
      // -----------------------------------------------------------------------
      var existingIndex = -1
      for i in 0..<targetSegment.candidatesSize {
        let cand = targetSegment.candidate(i)
        if cand.value.bytesEqual(combinedValue)
          && max(1, Int(cand.convertedSegmentCount)) == numSegs
        {
          existingIndex = i
          break
        }
      }

      // -----------------------------------------------------------------------
      // Step 5: Update / Promote existing candidate or insert new candidate.
      // -----------------------------------------------------------------------
      if existingIndex >= 0 {
        // Case A: Existing candidate found.
        // Move candidate forward if it is currently positioned after
        // target_pos. Do NOT demote if it is already positioned ahead of
        // target_pos (e.g. placed at pos 0 by a higher-ranked prediction
        // result).
        if existingIndex > targetPos {
          let pos = min(targetPos, targetSegment.candidatesSize - 1)
          targetSegment.moveCandidate(existingIndex, pos)
          existingIndex = pos
        }
        let cand = targetSegment.mutableCandidate(existingIndex)
        cand.cost = min(cand.cost, Int32(truncatingIfNeeded: result.cost))
        cand.wcost = min(cand.wcost, Int32(truncatingIfNeeded: result.wcost))
        cand.attributes |= result.attributes
        if result.innerSegmentBoundary.count >= innerIdx {
          cand.innerSegmentBoundary = Array(result.innerSegmentBoundary[startInner..<innerIdx])
        }
      } else {
        // Case B: Candidate not present. Insert a new candidate.
        // - If num_segs > 1: inserted as a multi-segment candidate.
        // - If num_segs == 1: inserted as a standard single-segment candidate.
        let pos = min(targetPos, targetSegment.candidatesSize)
        let cand =
          (pos == 0 && targetSegment.candidatesSize > 0)
          ? targetSegment.pushFrontCandidate()
          : targetSegment.insertCandidate(pos)!
        cand.key = String(combinedKey)
        cand.value = String(combinedValue)
        cand.contentKey = String(combinedContentKey)
        cand.contentValue = String(combinedContentValue)
        cand.convertedSegmentCount = UInt32(numSegs)
        cand.lid = result.lid
        cand.rid = result.rid
        cand.wcost = Int32(truncatingIfNeeded: result.wcost)
        cand.cost = Int32(truncatingIfNeeded: result.cost)
        cand.attributes = result.attributes
        cand.consumedKeySize = result.consumedKeySize
        if result.innerSegmentBoundary.count >= innerIdx {
          cand.innerSegmentBoundary = Array(result.innerSegmentBoundary[startInner..<innerIdx])
        }
      }
    }
  }
}
