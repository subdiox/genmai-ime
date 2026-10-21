// Port of mozc/src/converter/converter_interface.h (3.35.6354).
//
// `Segments*` is the reference type `Segments`; `absl::Span<const uint8_t>`
// is `[UInt8]`.

public protocol ConverterInterface: AnyObject, Sendable {
  /// Starts conversion for given request.
  func startConversion(_ request: ConversionRequest, _ segments: Segments) -> Bool

  /// Start reverse conversion with key.
  func startReverseConversion(_ segments: Segments, _ key: String) -> Bool

  /// Starts prediction for given request.
  func startPrediction(_ request: ConversionRequest, _ segments: Segments) -> Bool

  /// Starts prediction with previous suggestion.
  /// This method is used for expanding the candidates while keeping the
  /// previous suggestion.
  func startPredictionWithPreviousSuggestion(
    _ request: ConversionRequest, _ previousSegment: Segment, _ segments: Segments
  ) -> Bool

  /// Builds segments from the given segment.
  /// This method also applies the converter's post processing such as
  /// rewriters.
  func prependCandidates(_ request: ConversionRequest, _ segment: Segment, _ segments: Segments)

  /// Finish conversion.
  /// Segments are cleared. Context is not cleared
  func finishConversion(_ request: ConversionRequest, _ segments: Segments)

  /// Clear segments and keep the context
  func cancelConversion(_ segments: Segments)

  /// Reset segments and context
  func resetConversion(_ segments: Segments)

  /// Revert last Finish operation
  func revertConversion(_ segments: Segments)

  /// Delete candidate from user input history.
  /// Returns false if the candidate was not found or deletion failed.
  /// Note: |segment_index| is the index for all segments, not the index of
  /// conversion_segments.
  func deleteCandidateFromHistory(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int)
    -> Bool

  /// Reconstruct history segments from given preceding text.
  func reconstructHistory(_ segments: Segments, _ precedingText: String) -> Bool

  /// Commit candidate
  func commitSegmentValue(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int) -> Bool

  /// Commit candidate for partial suggestion.
  /// current_segment_key : key for submitted segment.
  /// new_segment_key : key for newly inserted segment.
  /// Example:
  ///   If the preedit is "いれた|てのおちゃ",
  ///   |current_segment_key| is "いれた" and
  ///   |new_segment_key| is "てのおちゃ".
  ///   After calling this method, the segments will contain following
  ///   segments.
  ///   - {key_ : "いれた",  segment_type_ : SUBMITTED}
  ///   - {key_ : "てのおちゃ", segment_type_ : FREE}
  func commitPartialSuggestionSegmentValue(
    _ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int,
    _ currentSegmentKey: String, _ newSegmentKey: String
  ) -> Bool

  /// Focus the candidate.
  /// This method is mainly called when user puts SPACE key
  /// and changes the focused candidate.
  /// In this method, Converter will find bracketing matching.
  /// e.g., when user selects "「",  corresponding closing bracket "」"
  /// is chosen in the preedit.
  func focusSegmentValue(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int) -> Bool

  /// Commit segments of which the range is [0, candidate_index.size()]
  /// and move the candidates into history segment temporally.
  /// Session can use this method for PartialCommit.
  /// |candidate_index| is a vector containing candidate index.
  /// candidate_index[0] corresponds to the index of the candidate of
  /// 1st segment.
  func commitSegments(_ segments: Segments, _ candidateIndex: [Int]) -> Bool

  /// Resize segment_index-th segment by offset_length.
  /// offset_length can be negative.
  func resizeSegment(
    _ segments: Segments, _ request: ConversionRequest, _ segmentIndex: Int, _ offsetLength: Int
  ) -> Bool

  /// Resize [start_segment_index, start_segment_index + segment_size]
  /// segments with the new size in new_size_array.
  func resizeSegments(
    _ segments: Segments, _ request: ConversionRequest, _ startSegmentIndex: Int,
    _ newSizeArray: [UInt8]
  ) -> Bool

  /// Syncs user-modified context.
  func commitContext(_ request: ConversionRequest)
}
