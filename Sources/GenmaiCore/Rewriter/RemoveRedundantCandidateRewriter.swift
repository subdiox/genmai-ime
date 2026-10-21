// Port of mozc/src/rewriter/remove_redundant_candidate_rewriter.{h,cc} (3.35.6354).

public final class RemoveRedundantCandidateRewriter: RewriterInterface {
  public init() {}

  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType {
    if request.request().mixedConversion {
      return .all
    }
    return .notAvailable
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    // For mobile, we don't return the single result that is same as a preedit.
    // However we want to have T13N candidates if we have T13N candidates.
    // http://b/5389342
    if segments.conversionSegmentsSize == 1
      && segments.conversionSegment(0).candidatesSize == 1
      && segments.conversionSegment(0).candidate(0).value.bytesEqual(
        segments.conversionSegment(0).key)
    {
      segments.mutableConversionSegment(0).clearCandidates()
      return true
    } else {
      return false
    }
  }
}
