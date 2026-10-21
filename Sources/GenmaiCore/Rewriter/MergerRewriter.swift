// Port of mozc/src/rewriter/merger_rewriter.h (3.35.6354).
//
// Deviations from C++:
// - A non-final class (RewriterImpl, the port of mozc::Rewriter, derives from
//   it). It implements every RewriterInterface requirement itself, so the
//   protocol extension defaults are never used through `any RewriterInterface`
//   (see the dispatch pitfall in CLAUDE.md).

public class MergerRewriter: RewriterInterface {
  private var rewriters: [any RewriterInterface] = []

  public init() {}

  public func addRewriter(_ rewriter: any RewriterInterface) {
    rewriters.append(rewriter)
  }

  /// RewriterInterface::capability() default (MergerRewriter does not
  /// override it in C++).
  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType { .conversion }

  public func checkResizeSegmentsRequest(_ request: ConversionRequest, _ segments: Segments)
    -> Rewriter.ResizeSegmentsRequest?
  {
    if segments.resized {
      return nil
    }

    for rewriter in rewriters {
      if let resizeRequest = rewriter.checkResizeSegmentsRequest(request, segments) {
        return resizeRequest
      }
    }
    return nil
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    let capabilityType: Rewriter.CapabilityType
    switch request.requestType() {
    case .conversion:
      capabilityType = .conversion
    case .prediction, .partialPrediction:
      capabilityType = .prediction
    case .suggestion, .partialSuggestion:
      capabilityType = .suggestion
    case .reverseConversion:
      capabilityType = .notAvailable
    }

    var isUpdated = false
    for rewriter in rewriters {
      if !rewriter.capability(request).intersection(capabilityType).isEmpty {
        isUpdated = rewriter.rewrite(request, segments) || isUpdated
      }
    }

    if request.requestType() == .suggestion && segments.conversionSegmentsSize == 1
      && !request.request().mixedConversion
    {
      let maxSuggestions = Int(request.config().suggestionsSize)
      let segment = segments.mutableConversionSegment(0)
      let candidateSize = segment.candidatesSize
      if candidateSize > maxSuggestions {
        segment.eraseCandidates(maxSuggestions, candidateSize - maxSuggestions)
      }
    }
    return isUpdated
  }

  /// This method is mainly called when user puts SPACE key
  /// and changes the focused candidate.
  /// In this method, Converter will find bracketing matching.
  /// e.g., when user selects "「",  corresponding closing bracket "」"
  /// is chosen in the preedit.
  public func focus(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int) -> Bool {
    var result = false
    for rewriter in rewriters {
      result = rewriter.focus(segments, segmentIndex, candidateIndex) || result
    }
    return result
  }

  /// Hook(s) for all mutable operations
  public func finish(_ request: ConversionRequest, _ segments: Segments) {
    for rewriter in rewriters {
      rewriter.finish(request, segments)
    }
  }

  public func revert(_ segments: Segments) {
    for rewriter in rewriters {
      rewriter.revert(segments)
    }
  }

  public func clearHistoryEntry(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int)
    -> Bool
  {
    var result = false
    for rewriter in rewriters {
      result = rewriter.clearHistoryEntry(segments, segmentIndex, candidateIndex) || result
    }
    return result
  }

  /// Syncs internal data to local file system.
  @discardableResult public func sync() -> Bool {
    var result = false
    for rewriter in rewriters {
      result = rewriter.sync() || result
    }
    return result
  }

  /// Reloads internal data from local file system.
  @discardableResult public func reload() -> Bool {
    var result = false
    for rewriter in rewriters {
      result = rewriter.reload() || result
    }
    return result
  }

  /// Clears internal data
  public func clear() {
    for rewriter in rewriters {
      rewriter.clear()
    }
  }
}
