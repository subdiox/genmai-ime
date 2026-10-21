// Port of mozc/src/converter/converter_mock.h (3.35.6354).
//
// gMock's MockConverter becomes a test double whose methods call optional
// handlers; unset handlers return false / do nothing (gMock's default
// action for bool / void).

@testable import GenmaiCore

final class MockConverter: ConverterInterface, @unchecked Sendable {
  var startConversionHandler: ((ConversionRequest, Segments) -> Bool)?
  var startReverseConversionHandler: ((Segments, String) -> Bool)?
  var startPredictionHandler: ((ConversionRequest, Segments) -> Bool)?
  var startPredictionWithPreviousSuggestionHandler: ((ConversionRequest, Segment, Segments) -> Bool)?
  var prependCandidatesHandler: ((ConversionRequest, Segment, Segments) -> Void)?
  var finishConversionHandler: ((ConversionRequest, Segments) -> Void)?
  var cancelConversionHandler: ((Segments) -> Void)?
  var resetConversionHandler: ((Segments) -> Void)?
  var revertConversionHandler: ((Segments) -> Void)?
  var deleteCandidateFromHistoryHandler: ((Segments, Int, Int) -> Bool)?
  var reconstructHistoryHandler: ((Segments, String) -> Bool)?
  var commitSegmentValueHandler: ((Segments, Int, Int) -> Bool)?
  var commitPartialSuggestionSegmentValueHandler: ((Segments, Int, Int, String, String) -> Bool)?
  var focusSegmentValueHandler: ((Segments, Int, Int) -> Bool)?
  var commitSegmentsHandler: ((Segments, [Int]) -> Bool)?
  var resizeSegmentHandler: ((Segments, ConversionRequest, Int, Int) -> Bool)?
  var resizeSegmentsHandler: ((Segments, ConversionRequest, Int, [UInt8]) -> Bool)?
  var commitContextHandler: ((ConversionRequest) -> Void)?

  /// `DoAll(SetArgPointee<1>(segments), Return(result))` for StartConversion.
  func setStartConversion(_ segments: Segments, _ result: Bool) {
    startConversionHandler = { _, out in
      out.assign(from: segments)
      return result
    }
  }

  func startConversion(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    startConversionHandler?(request, segments) ?? false
  }
  func startReverseConversion(_ segments: Segments, _ key: String) -> Bool {
    startReverseConversionHandler?(segments, key) ?? false
  }
  func startPrediction(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    startPredictionHandler?(request, segments) ?? false
  }
  func startPredictionWithPreviousSuggestion(
    _ request: ConversionRequest, _ previousSegment: Segment, _ segments: Segments
  ) -> Bool {
    startPredictionWithPreviousSuggestionHandler?(request, previousSegment, segments) ?? false
  }
  func prependCandidates(_ request: ConversionRequest, _ segment: Segment, _ segments: Segments) {
    prependCandidatesHandler?(request, segment, segments)
  }
  func finishConversion(_ request: ConversionRequest, _ segments: Segments) {
    finishConversionHandler?(request, segments)
  }
  func cancelConversion(_ segments: Segments) { cancelConversionHandler?(segments) }
  func resetConversion(_ segments: Segments) { resetConversionHandler?(segments) }
  func revertConversion(_ segments: Segments) { revertConversionHandler?(segments) }
  func deleteCandidateFromHistory(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int)
    -> Bool
  {
    deleteCandidateFromHistoryHandler?(segments, segmentIndex, candidateIndex) ?? false
  }
  func reconstructHistory(_ segments: Segments, _ precedingText: String) -> Bool {
    reconstructHistoryHandler?(segments, precedingText) ?? false
  }
  func commitSegmentValue(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int) -> Bool {
    commitSegmentValueHandler?(segments, segmentIndex, candidateIndex) ?? false
  }
  func commitPartialSuggestionSegmentValue(
    _ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int,
    _ currentSegmentKey: String, _ newSegmentKey: String
  ) -> Bool {
    commitPartialSuggestionSegmentValueHandler?(
      segments, segmentIndex, candidateIndex, currentSegmentKey, newSegmentKey) ?? false
  }
  func focusSegmentValue(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int) -> Bool {
    focusSegmentValueHandler?(segments, segmentIndex, candidateIndex) ?? false
  }
  func commitSegments(_ segments: Segments, _ candidateIndex: [Int]) -> Bool {
    commitSegmentsHandler?(segments, candidateIndex) ?? false
  }
  func resizeSegment(
    _ segments: Segments, _ request: ConversionRequest, _ segmentIndex: Int, _ offsetLength: Int
  ) -> Bool {
    resizeSegmentHandler?(segments, request, segmentIndex, offsetLength) ?? false
  }
  func resizeSegments(
    _ segments: Segments, _ request: ConversionRequest, _ startSegmentIndex: Int,
    _ newSizeArray: [UInt8]
  ) -> Bool {
    resizeSegmentsHandler?(segments, request, startSegmentIndex, newSizeArray) ?? false
  }
  func commitContext(_ request: ConversionRequest) { commitContextHandler?(request) }
}
