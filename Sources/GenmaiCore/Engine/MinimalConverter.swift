// Port of mozc/src/engine/minimal_converter.{h,cc} (3.35.6354).
//
// A converter that returns the input as-is. Engine uses it until the real
// converter is initialized (Engine.createEngine() without modules).

private func addAsIsCandidate(_ key: String, _ segments: Segments) -> Bool {
  if key.isEmpty {
    return false
  }
  segments.clear()
  let segment = segments.addSegment()

  let candidate = segment.pushBackCandidate()
  candidate.contentKey = key
  candidate.contentValue = key
  candidate.key = key
  candidate.value = key
  candidate.lid = 0
  candidate.rid = 0
  candidate.wcost = 0
  candidate.cost = 0
  candidate.attributes = Attribute.defaultAttribute

  return true
}

private func addAsIsCandidate(_ request: ConversionRequest, _ segments: Segments) -> Bool {
  addAsIsCandidate(request.key(), segments)
}

private final class MinimalConverter: ConverterInterface {
  func startConversion(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    addAsIsCandidate(request, segments)
  }

  func startReverseConversion(_ segments: Segments, _ key: String) -> Bool { false }

  func startPrediction(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    addAsIsCandidate(request, segments)
  }

  func startPredictionWithPreviousSuggestion(
    _ request: ConversionRequest, _ previousSegment: Segment, _ segments: Segments
  ) -> Bool {
    addAsIsCandidate(request, segments)
  }

  func prependCandidates(_ request: ConversionRequest, _ segment: Segment, _ segments: Segments) {
    segments.prependCandidates(segment)
  }

  func finishConversion(_ request: ConversionRequest, _ segments: Segments) {}

  func cancelConversion(_ segments: Segments) {}

  func resetConversion(_ segments: Segments) {}

  func revertConversion(_ segments: Segments) {}

  func deleteCandidateFromHistory(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int)
    -> Bool
  { true }

  func reconstructHistory(_ segments: Segments, _ precedingText: String) -> Bool { true }

  func commitSegmentValue(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int) -> Bool {
    true
  }

  func commitPartialSuggestionSegmentValue(
    _ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int,
    _ currentSegmentKey: String, _ newSegmentKey: String
  ) -> Bool { true }

  func focusSegmentValue(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int) -> Bool {
    true
  }

  func commitSegments(_ segments: Segments, _ candidateIndex: [Int]) -> Bool { true }

  func resizeSegment(
    _ segments: Segments, _ request: ConversionRequest, _ segmentIndex: Int, _ offsetLength: Int
  ) -> Bool { true }

  func resizeSegments(
    _ segments: Segments, _ request: ConversionRequest, _ startSegmentIndex: Int,
    _ newSizeArray: [UInt8]
  ) -> Bool { true }

  func commitContext(_ request: ConversionRequest) {}
}

public func createMinimalConverter() -> any ConverterInterface {
  MinimalConverter()
}
