// Port of mozc/src/rewriter/rewriter_util.{h,cc} (3.35.6354).

public enum RewriterUtil {
  /// Calculates the inserting position so that we can keep the candidates from
  /// user history predictor.
  /// Note:
  /// Rewriters can be called not only after converter, but also after
  /// predictors.
  public static func calculateInsertPosition(_ segment: Segment, _ offset: Int) -> Int {
    var existingHistoryCandidatesNum = 0
    for i in 0..<segment.candidatesSize {
      // Assume that the user history prediction candidates are inserted
      // sequentially from top.
      if segment.candidate(i).attributes & Attribute.userHistoryPrediction != 0 {
        existingHistoryCandidatesNum += 1
      } else if existingHistoryCandidatesNum > 0 {
        break
      }
    }
    return min(offset + existingHistoryCandidatesNum, segment.candidatesSize)
  }
}
