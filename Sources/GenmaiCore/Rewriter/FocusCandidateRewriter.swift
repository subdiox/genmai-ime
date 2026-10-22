// Port of mozc/src/rewriter/focus_candidate_rewriter.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - The initializer takes the counter suffix data as a `DataView` and keeps it
//   alive (the SerializedStringArray refers to it without copying).
// - `ParseNumberCandidate` returns the parsed parts as a tuple (nil = false).
// - `FindMatchingCandidates` returns -1 for a segment without candidates
//   (C++ reads `candidate(0)` unconditionally, which is undefined behavior).

import GenmaiBase

private let kNumber = 1
private let kSuffix = 2
private let kConnector = 4

// TODO(taku): See POS and increase the coverage.
private func isConnectorSegment(_ segment: Segment) -> Bool {
  segment.key.bytesEqual("と") || segment.key.bytesEqual("や")
}

// Finds value from the candidates list and move the candidate to the top.
private func rewriteCandidate(_ segment: Segment, _ value: some StringProtocol) -> Bool {
  for i in 0..<segment.candidatesSize where segment.candidate(i).contentValue.bytesEqual(value) {
    segment.moveCandidate(i, 0)  // move to top
    return true
  }
  // Find value from meta candidates.
  for i in 0..<segment.metaCandidatesSize
  where segment.metaCandidate(i).contentValue.bytesEqual(value) {
    segment.moveCandidate(-i - 1, 0)  // copy to top
    return true
  }
  return false
}

// Returns true if the segment is valid.
private func isValidSegment(_ segment: Segment) -> Bool {
  segment.segmentType == .free || segment.segmentType == .fixedBoundary
    || segment.segmentType == .fixedValue
}

private func isNumberCandidate(_ candidate: Candidate) -> Bool {
  candidate.style != .defaultStyle || Util.getScriptType(candidate.value) == .number
}

private func isNumberSegment(_ segment: Segment) -> Bool {
  segment.candidatesSize > 0 && isNumberCandidate(segment.candidate(0))
}

// Returns true if two candidates have the same number form.
private func isSameNumberType(_ candidate1: Candidate, _ candidate2: Candidate) -> Bool {
  if candidate1.style == candidate2.style {
    if candidate1.style == .defaultStyle {
      if isNumberCandidate(candidate1) && isNumberCandidate(candidate2)
        && Util.getFormType(candidate1.value) == Util.getFormType(candidate2.value)
      {
        return true
      }
    } else {
      return true
    }
  }
  return false
}

private func rewriteNumber(_ segment: Segment, _ candidate: Candidate) -> Bool {
  for i in 0..<segment.candidatesSize where isSameNumberType(candidate, segment.candidate(i)) {
    segment.moveCandidate(i, 0)  // move to top
    return true
  }

  // Find value from meta candidates.
  for i in 0..<segment.metaCandidatesSize
  where isSameNumberType(candidate, segment.metaCandidate(i)) {
    segment.moveCandidate(-i - 1, 0)  // copy to top
    return true
  }

  return false
}

public final class FocusCandidateRewriter: RewriterInterface, Sendable {
  private let suffixArray: SerializedStringArray
  private let posMatcher: PosMatcher
  // Keeps the memory referenced by `suffixArray` alive.
  private let counterSuffixData: DataView

  public init(_ counterSuffixData: DataView, _ posMatcher: PosMatcher) {
    self.posMatcher = posMatcher
    self.counterSuffixData = counterSuffixData
    var array = SerializedStringArray()
    // Data manager is responsible for providing a valid data.
    array.set(counterSuffixData)
    self.suffixArray = array
  }

  /// Changed the focus of "segment_index"-th segment to be "candidate_index".
  /// The segments will be written according to pre-defined "actions".
  /// Currently, FocusSegmentValue() finds bracket/parentheses matching, e.g.,
  /// When user chooses "(" in some candidate, corresponding close bracket ")"
  /// is automatically placed at the top.
  public func focus(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int) -> Bool {
    if segmentIndex >= segments.segmentsSize {
      GenmaiLog.warning("Segment index out of range")
      return false
    }

    let seg = segments.segment(segmentIndex)

    // segment_type must be FREE or FIXED_BOUNDARY
    if !isValidSegment(seg) {
      GenmaiLog.warning("Segment is not valid")
      return false
    }

    // invalid candidate index
    if (candidateIndex < 0 && -candidateIndex - 1 >= seg.metaCandidatesSize)
      || candidateIndex >= seg.candidatesSize
    {
      GenmaiLog.warning("Candidate index out of range: \(candidateIndex) \(seg.candidatesSize)")
      return false
    }

    // left to right
    do {
      let leftValue = seg.candidate(candidateIndex).contentValue

      if let rightValue = Util.isOpenBracket(leftValue) {
        var numNest = 1
        for targetRightSeg in segments.all.drop(segmentIndex + 1) {
          if targetRightSeg.candidatesSize <= 0 {
            GenmaiLog.warning("target right seg is not valid")
            return false
          }
          if !isValidSegment(targetRightSeg) {
            continue
          }
          let targetRightValue = targetRightSeg.candidate(0).contentValue
          if Util.isOpenBracket(targetRightValue) != nil {
            numNest += 1
          } else if Util.isCloseBracket(targetRightValue) != nil {
            numNest -= 1
          }

          if numNest == 0 && rewriteCandidate(targetRightSeg, rightValue) {
            return true
          }
        }
        // could not find close bracket
        return false
      }
    }

    // right to left
    do {
      let rightValue = seg.candidate(candidateIndex).contentValue

      if let leftValue = Util.isCloseBracket(rightValue) {
        var numNest = 1
        var i = segmentIndex - 1
        while i >= 0 {
          defer { i -= 1 }
          let targetLeftSeg = segments.mutableSegment(i)
          if targetLeftSeg.candidatesSize <= 0 {
            GenmaiLog.warning("target left seg is not valid")
            return false
          }
          if !isValidSegment(targetLeftSeg) {
            continue
          }
          let targetLeftValue = targetLeftSeg.candidate(0).contentValue
          if Util.isCloseBracket(targetLeftValue) != nil {
            numNest += 1
          } else if Util.isOpenBracket(targetLeftValue) != nil {
            numNest -= 1
          }
          if numNest == 0 && rewriteCandidate(targetLeftSeg, leftValue) {
            return true
          }
        }
        // could not find open bracket
        return false
      }
    }

    do {
      if isNumberCandidate(seg.candidate(candidateIndex)) {
        var modified = false
        var distance = 0
        for targetRightSeg in segments.all.drop(segmentIndex + 1) {
          if targetRightSeg.candidatesSize <= 0 {
            GenmaiLog.warning("target right seg is not valid")
            return false
          }
          if !isValidSegment(targetRightSeg) {
            continue
          }

          // Make sure the first candidate of the segment is number.
          if isNumberSegment(targetRightSeg)
            && rewriteNumber(targetRightSeg, seg.candidate(candidateIndex))
          {
            modified = true
            distance = 0
          } else {
            distance += 1
          }
          // more than two segments between the target numbers
          if distance >= 2 {
            break
          }
        }
        return modified
      }
    }

    do {
      // <Number><Suffix><Connector>?<Number><Suffix><Connector>?
      if segmentIndex > 0 && isNumberSegment(segments.segment(segmentIndex - 1))
        && seg.candidatesSize > 0
        && seg.candidate(0).contentKey.bytesEqual(seg.candidate(candidateIndex).contentKey)
      {
        var nextStat = kConnector | kNumber
        var modified = false
        for segment in segments.all.drop(segmentIndex + 1) {
          if nextStat == (kConnector | kNumber) {
            if isConnectorSegment(segment) {
              nextStat = kNumber
            } else if isNumberSegment(segment) {
              nextStat = kSuffix
            } else {
              break
            }
          } else if nextStat == kNumber && isNumberSegment(segment) {
            nextStat = kSuffix
          } else if nextStat == kSuffix && segment.candidatesSize > 0
            && segment.candidate(0).contentKey.bytesEqual(seg.candidate(0).contentKey)
          {
            if !isValidSegment(segment) {
              continue
            }
            modified =
              rewriteCandidate(segment, seg.candidate(candidateIndex).contentValue) || modified
            nextStat = kConnector | kNumber
          } else {
            break
          }
        }
        return modified
      }
    }
    return rerankNumberCandidates(segments, segmentIndex, candidateIndex)
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    false
  }

  /// Performs reranking of number candidates to make numbers consistent across
  /// multiple segments.
  private func rerankNumberCandidates(
    _ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int
  ) -> Bool {
    // Check if the focused candidate is a number compound.
    let seg = segments.segment(segmentIndex)
    guard let (number, suffix, numberScriptType) = parseNumberCandidate(seg.candidate(candidateIndex))
    else {
      return false
    }
    if number.isEmpty {
      return false
    }

    // Try reranking top candidates of subsequent segments using the number
    // compound style of the focused candidate.
    var modified = false
    var distance = 0
    for seg in segments.all.drop(segmentIndex + 1) {
      let index = findMatchingCandidates(seg, numberScriptType, suffix)
      if index == -1 {
        // If there's no appropriate candidate having the same style, we increment
        // the distance not to modify segments far from the focused one.
        distance += 1
        if distance > 2 {
          break
        }
        continue
      }
      // Move the target candidate to the top.  We don't need to move if the
      // target is already at top (i.g., the case where index == 0).
      if index > 0 {
        seg.moveCandidate(index, 0)
        modified = true
        distance = 0
      }
    }
    return modified
  }

  /// Finds an index of candidate in |seg| that matches the given number script
  /// type and suffix.  Returns -1 if there's no candidate matching the
  /// condition.
  private func findMatchingCandidates(
    _ seg: Segment, _ refScriptType: UInt32, _ refSuffix: Substring
  ) -> Int {
    // Only segments whose top candidate is a number compound are target of
    // reranking.
    guard seg.candidatesSize > 0,
      let (_, suffix, scriptType) = parseNumberCandidate(seg.candidate(0))
    else {
      return -1
    }

    // Top candidate matches the style.
    if scriptType == refScriptType && suffix.bytesEqual(refSuffix) {
      return 0
    }

    // Check only top 10 candidates because, when the top candidate is a number
    // candidate, other number compounds likely to appear near the top candidate.
    let maxSize = min(seg.candidatesSize, 10)
    var i = 1
    while i < maxSize {
      defer { i += 1 }
      guard let (_, suffix, scriptType) = parseNumberCandidate(seg.candidate(i)) else {
        continue
      }
      if scriptType == refScriptType && suffix.bytesEqual(refSuffix) {
        return i
      }
    }
    return -1
  }

  /// Parses the value of a candidate into number and counter suffix.
  /// Simultaneously checks the script type of number.  Here, number candidate
  /// is defined to be the following pattern:
  ///   * [数][助数詞][並立助詞]?  (e.g., 一階, 二回, ３階や, etc.)
  /// Returns nil if the value of candidate doesn't match the pattern.
  private func parseNumberCandidate(_ cand: Candidate)
    -> (number: Substring, suffix: Substring, scriptType: UInt32)?
  {
    // If the lengths of content value and value are different, particles may
    // be appended to value.  In such cases, we only accept parallel markers.
    // Otherwise, the following wrong rewrite will occur.
    // Example: "一階へは | 二回 | 行った -> 一階へは | 二階 | 行った"
    if cand.contentValue.utf8.count != cand.value.utf8.count {
      if !posMatcher.isParallelMarker(cand.rid) {
        return nil
      }
    }
    guard
      let r = NumberCompoundUtil.splitStringIntoNumberAndCounterSuffix(
        suffixArray, cand.contentValue)
    else {
      return nil
    }
    return (r.number, r.counterSuffix, r.scriptType)
  }
}
