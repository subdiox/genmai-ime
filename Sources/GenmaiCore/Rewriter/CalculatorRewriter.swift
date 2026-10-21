// Port of mozc/src/rewriter/calculator_rewriter.{h,cc} (3.35.6354).

import GenmaiBase
import GenmaiProtocol

private let kDescription = "計算結果"

/// absl::StrReplaceAll for non-overlapping single-pattern replacement, bytewise.
private func replaceAllBytes(_ s: String, _ replacements: [(String, String)]) -> String {
  let src = Array(s.utf8)
  let pats = replacements.map { (Array($0.0.utf8), Array($0.1.utf8)) }
  var out: [UInt8] = []
  out.reserveCapacity(src.count)
  var i = 0
  outer: while i < src.count {
    for (from, to) in pats where !from.isEmpty && i + from.count <= src.count {
      if src[i..<(i + from.count)].elementsEqual(from) {
        out.append(contentsOf: to)
        i += from.count
        continue outer
      }
    }
    out.append(src[i])
    i += 1
  }
  return String(decoding: out, as: UTF8.self)
}

public final class CalculatorRewriter: RewriterInterface {
  private let calculator = Calculator()

  public init() {}

  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType {
    if request.request().mixedConversion {
      return .all
    }
    return .conversion
  }

  public func checkResizeSegmentsRequest(_ request: ConversionRequest, _ segments: Segments)
    -> Rewriter.ResizeSegmentsRequest?
  {
    if !request.config().useCalculator {
      return nil
    }

    if request.request().decoderExperimentParams.enableMultiSegmentCandidate {
      return nil
    }

    let segmentsSize = segments.conversionSegmentsSize
    if segmentsSize <= 1 {
      return nil
    }

    // Merge keys of all conversion segments and try calculation.
    var mergedKey = ""
    for segment in segments.conversionSegments {
      mergedKey += segment.key
    }
    // The decision to calculate and calculation itself are both done by the
    // calculator.
    if calculator.calculateString(mergedKey) == nil {
      return nil
    }

    // Merge all conversion segments.
    let keySize = UInt8(truncatingIfNeeded: Util.charsLen(mergedKey))
    return Rewriter.ResizeSegmentsRequest(
      segmentIndex: 0, segmentSizes: [keySize, 0, 0, 0, 0, 0, 0, 0])
  }

  /// Rewrites candidates when conversion segments of |segments| represents an
  /// expression that can be calculated.
  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    if !request.config().useCalculator {
      return false
    }

    let segmentsSize = segments.conversionSegmentsSize
    if segmentsSize == 0 {
      return false
    }

    let enableMultiSegment = request.request().decoderExperimentParams
      .enableMultiSegmentCandidate
    if !enableMultiSegment && segmentsSize != 1 {
      return false
    }

    let key = enableMultiSegment ? request.key() : segments.conversionSegment(0).key
    if key.isEmpty {
      return false
    }

    guard let result = calculator.calculateString(key) else {
      return false
    }

    let convertedSegmentCount = enableMultiSegment ? segmentsSize : 1
    // Insert the result into segment 0 covering all conversion segments.
    if !insertCandidate(
      key, result, convertedSegmentCount, 0, segments.mutableConversionSegment(0))
    {
      return false
    }

    return true
  }

  /// Inserts a candidate with the string into the |segment|.
  /// Position of insertion is indicated by |insert_pos|. It returns false if
  /// insertion is failed.
  func insertCandidate(
    _ key: String, _ value: String, _ convertedSegmentCount: Int, _ insertPos: Int,
    _ segment: Segment
  ) -> Bool {
    if segment.candidatesSize == 0 {
      // LOG(WARNING) << "candidates_size is 0";
      return false
    }

    // Normalize the expression, used in description.
    let expression = replaceAllBytes(
      Japanese.fullWidthAsciiToHalfWidthAscii(key), [("・", "/"), ("ー", "-")])  // "ー", onbiki

    let offset = min(insertPos, segment.candidatesSize)

    // Inserts up to 3 candidate variations:
    // n = 0: Calculated result only (e.g., "1").
    // n = 1: Expression with result (e.g., "(1+2*3)/7=1" or "2=1+1").
    // n = 2: Normalized half-width expression only (e.g., "(1+2*3)/7=").
    // Note: n = 2 is required because multi-segment expressions are no longer
    // merged via segment resizing, so the transliterated full expression
    // candidate is generated here explicitly.
    let numCandidates = convertedSegmentCount > 1 ? 3 : 2
    for n in 0..<numCandidates {
      let currentOffset = offset + n
      guard let candidate = segment.insertCandidate(currentOffset) else {
        // LOG(ERROR) << "cannot insert candidate at " << current_offset;
        return false
      }

      // Simply sets some member variables of the new candidate to ones of the
      // existing candidate next to it.
      var referenceIndex = currentOffset + 1
      if referenceIndex >= segment.candidatesSize {
        referenceIndex = currentOffset - 1
      }
      let referenceCandidate = segment.candidate(referenceIndex)

      candidate.lid = referenceCandidate.lid
      candidate.rid = referenceCandidate.rid
      candidate.cost = referenceCandidate.cost
      candidate.key = key
      candidate.contentKey = key
      candidate.convertedSegmentCount = UInt32(convertedSegmentCount)
      candidate.attributes |= Attribute.noVariantsExpansion
      candidate.attributes |= Attribute.noLearning

      if n == 0 {  // Result only (e.g., "1")
        candidate.value = value
        candidate.contentValue = value
        candidate.description = kDescription
      } else if n == 1 {  // Expression + result (e.g., "(1+2*3)/7=1")
        assert(!expression.isEmpty)
        if expression.utf8.first == UInt8(ascii: "=") {
          // Expression starts with '='.
          // Appends value to the left of expression.
          candidate.value = value + expression
          candidate.contentValue = value + expression
        } else {
          // Expression ends with '='.
          // Appends value to the right of expression.
          candidate.value = expression + value
          candidate.contentValue = expression + value
        }
        candidate.description = kDescription
      } else {  // Expression only (e.g., "(1+2*3)/7=")
        candidate.value = expression
        candidate.contentValue = expression
      }
    }

    return true
  }
}
