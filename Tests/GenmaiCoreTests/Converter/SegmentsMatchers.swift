// Port of mozc/src/converter/segments_matchers.h (3.35.6354).
//
// gMock matchers become functions returning nil on a match or a reason
// string on a mismatch (so `#expect(equalsCandidate(a, b) == nil)` shows which
// field differs), plus Bool predicates for the candidate-list matchers.
// Strings are compared bytewise like C++ std::string.

@testable import GenmaiCore

/// Checks if a candidate exactly matches the given candidate except for `log`
/// field. Returns nil if equal, or the name of the different field.
func equalsCandidate(_ arg: Candidate, _ candidate: Candidate) -> String? {
  func differs(_ name: String) -> String { "where the field '\(name)' is different" }
  if !arg.key.bytesEqual(candidate.key) { return differs("key") }
  if !arg.value.bytesEqual(candidate.value) { return differs("value") }
  if !arg.contentKey.bytesEqual(candidate.contentKey) { return differs("content_key") }
  if !arg.contentValue.bytesEqual(candidate.contentValue) { return differs("content_value") }
  if arg.consumedKeySize != candidate.consumedKeySize { return differs("consumed_key_size") }
  if arg.convertedSegmentCount != candidate.convertedSegmentCount { return differs("converted_segment_count") }
  if !arg.prefix.bytesEqual(candidate.prefix) { return differs("prefix") }
  if !arg.suffix.bytesEqual(candidate.suffix) { return differs("suffix") }
  if !arg.description.bytesEqual(candidate.description) { return differs("description") }
  if !arg.a11yDescription.bytesEqual(candidate.a11yDescription) { return differs("a11y_description") }
  if !arg.displayValue.bytesEqual(candidate.displayValue) { return differs("display_value") }
  if arg.usageId != candidate.usageId { return differs("usage_id") }
  if !arg.usageTitle.bytesEqual(candidate.usageTitle) { return differs("usage_title") }
  if !arg.usageDescription.bytesEqual(candidate.usageDescription) { return differs("usage_description") }
  if arg.cost != candidate.cost { return differs("cost") }
  if arg.wcost != candidate.wcost { return differs("wcost") }
  if arg.structureCost != candidate.structureCost { return differs("structure_cost") }
  if arg.lid != candidate.lid { return differs("lid") }
  if arg.rid != candidate.rid { return differs("rid") }
  if arg.attributes != candidate.attributes { return differs("attributes") }
  if arg.category != candidate.category { return differs("category") }
  if arg.style != candidate.style { return differs("style") }
  if arg.command != candidate.command { return differs("command") }
  if arg.innerSegmentBoundary != candidate.innerSegmentBoundary { return differs("inner_segment_boundary") }
  return nil
}

/// Checks if a segment exactly matches the given segment except for
/// removed_candidates_for_debug_. Returns nil if equal.
func equalsSegment(_ arg: Segment, _ segment: Segment) -> String? {
  if arg.segmentType != segment.segmentType { return "where the property 'segment_type' is different" }
  if !arg.key.bytesEqual(segment.key) { return "where the property 'key' is different" }
  if arg.keyLen != segment.keyLen { return "where the property 'key_len' is different" }

  // Compare candidates.
  let commonCandidateSize = min(arg.candidatesSize, segment.candidatesSize)
  for i in 0..<commonCandidateSize {
    if let reason = equalsCandidate(arg.candidate(i), segment.candidate(i)) {
      return "\(reason) for the \(i)-th candidate"
    }
  }
  if arg.candidatesSize != segment.candidatesSize {
    return
      "where the actual has more or less candidates than the expected: \(arg.candidatesSize) vs \(segment.candidatesSize)"
  }

  // Compare meta candidates.
  let commonMetaCandidateSize = min(arg.metaCandidatesSize, segment.metaCandidatesSize)
  for i in 0..<commonMetaCandidateSize {
    if let reason = equalsCandidate(arg.metaCandidate(i), segment.metaCandidate(i)) {
      return "\(reason) for the \(i)-th meta candidate"
    }
  }
  if arg.metaCandidatesSize != segment.metaCandidatesSize {
    return
      "where the actual has more or less meta candidates than the expected: \(arg.metaCandidatesSize) vs \(segment.metaCandidatesSize)"
  }
  return nil
}

/// Checks if a segment contains a candidate list that matches the given
/// predicates in the given order (`CandidatesAreArray`).
func candidatesAreArray(_ segment: Segment, _ matchers: [(Candidate) -> Bool]) -> Bool {
  if segment.candidatesSize != matchers.count { return false }
  for (i, matcher) in matchers.enumerated() where !matcher(segment.candidate(i)) {
    return false
  }
  return true
}

/// Checks if a segment contains one and only one candidate that matches the
/// given predicate.
func hasSingleCandidate(_ segment: Segment, _ matcher: (Candidate) -> Bool) -> Bool {
  segment.candidatesSize == 1 && matcher(segment.candidate(0))
}

/// Checks if a segment contains a candidate that matches the given predicate.
func containsCandidate(_ segment: Segment, _ matcher: (Candidate) -> Bool) -> Bool {
  segment.candidates.contains(where: matcher)
}

/// Checks if a segments exactly matches the given segments. Returns nil if
/// equal.
func equalsSegments(_ arg: Segments, _ segments: Segments) -> String? {
  if arg.maxHistorySegmentsSize != segments.maxHistorySegmentsSize {
    return "where the property 'max_history_segments_size' is different"
  }
  if arg.resized != segments.resized { return "where the property 'resized' is different" }

  let commonSegmentsSize = min(arg.segmentsSize, segments.segmentsSize)
  for i in 0..<commonSegmentsSize {
    if let reason = equalsSegment(arg.segment(i), segments.segment(i)) {
      return "\(reason) of the \(i)-th segment"
    }
  }
  if arg.segmentsSize != segments.segmentsSize {
    return
      "where the actual has more or less segments than the expected: \(arg.segmentsSize) vs \(segments.segmentsSize)"
  }
  return nil
}

/// Predicate helpers (`Field(&Candidate::value, "v")`).
func valueIs(_ value: String) -> (Candidate) -> Bool { { $0.value.bytesEqual(value) } }
func keyIs(_ key: String) -> (Candidate) -> Bool { { $0.key.bytesEqual(key) } }
func keyAndValueAre(_ key: String, _ value: String) -> (Candidate) -> Bool {
  { $0.key.bytesEqual(key) && $0.value.bytesEqual(value) }
}
