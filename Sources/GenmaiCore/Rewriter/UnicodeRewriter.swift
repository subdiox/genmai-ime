// Port of mozc/src/rewriter/unicode_rewriter.{h,cc} (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiProtocol

private func isAsciiXDigit(_ b: UInt8) -> Bool {
  (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x46) || (b >= 0x61 && b <= 0x66)
}

/// Checks given string is codepoint expression or not.
private func isValidCodepointExpression(_ input: String) -> Bool {
  let bytes = Array(input.utf8)
  if bytes.count < 3 || bytes.count > 8 {
    return false
  }

  if !input.hasBytePrefix("U+") {
    return false
  }
  return bytes[2...].allSatisfy(isAsciiXDigit)
}

/// Converts given string to 32bit unsigned integer (absl::SimpleHexAtoi on
/// the part after "U+"; it is validated to be 1-6 hex digits).
private func ucs4ExpressionToInteger(_ input: String) -> UInt32? {
  UInt32(String(input.byteSubstring(from: 2)), radix: 16)
}

private func addCandidate(
  _ key: String, _ value: String, _ convertedSegmentCount: Int, _ index: Int, _ segment: Segment
) {
  var index = index
  if index > segment.candidatesSize {
    index = segment.candidatesSize
  }

  guard let candidate = segment.insertCandidate(index) else { return }

  candidate.key = key
  candidate.contentKey = key
  candidate.value = value
  candidate.contentValue = value
  candidate.convertedSegmentCount = UInt32(convertedSegmentCount)
  candidate.description = "Unicode 変換 (" + candidate.key + ")"
  // NO_MODIFICATION is required here, in order to escape
  // EnvironmentalFilterRewriter. Otherwise, some candidates from
  // UnicodeRewriter will be removed because they are unrenderable.
  candidate.attributes |=
    (Attribute.noLearning | Attribute.noVariantsExpansion | Attribute.noModification)
}

private func getValue(_ key: String) -> String? {
  if !isValidCodepointExpression(key) {
    return nil
  }

  guard let codepoint = ucs4ExpressionToInteger(key) else {
    return nil
  }

  if !Util.isAcceptableCharacterAsCandidate(codepoint) {
    return nil
  }

  let value = Util.codepointToUtf8(codepoint)
  if value.isEmpty {
    return nil
  }

  return value
}

public final class UnicodeRewriter: RewriterInterface {
  public init() {}

  /// If the key is a single unicode character, the corresponding
  /// Unicode "U+xxxx" format is added. (ex. "A" -> "U+0041").  This is
  /// triggered on reverse conversion only.
  private func rewriteToUnicodeCharFormat(_ request: ConversionRequest, _ segments: Segments)
    -> Bool
  {
    if request.composer().sourceText.isEmpty || segments.conversionSegmentsSize != 1 {
      return false
    }

    let sourceText = request.composer().sourceText
    let sourceTextSize = Util.charsLen(sourceText)
    if sourceTextSize != 1 {
      return false
    }

    let codepoint = Util.utf8ToCodepoint(sourceText)
    let value = String(format: "U+%04X", codepoint)

    let key = segments.conversionSegment(0).key
    let segment = segments.mutableConversionSegment(0)
    addCandidate(key, value, 1, 5, segment)
    return true
  }

  public func checkResizeSegmentsRequest(_ request: ConversionRequest, _ segments: Segments)
    -> Rewriter.ResizeSegmentsRequest?
  {
    if request.request().decoderExperimentParams.enableMultiSegmentCandidate {
      return nil
    }
    if segments.resized || segments.conversionSegmentsSize <= 1 {
      // The given segments are already resized.
      return nil
    }

    let key = request.key()
    let keyLen = Util.charsLen(key)
    if keyLen > Int(UInt8.max) {
      return nil
    }
    let segmentSize = UInt8(keyLen)

    if getValue(key) == nil {
      return nil
    }

    return Rewriter.ResizeSegmentsRequest(
      segmentIndex: 0, segmentSizes: [segmentSize, 0, 0, 0, 0, 0, 0, 0])
  }

  /// If the key is in the "U+xxxx" format, the corresponding Unicode
  /// character is added. (ex. "U+0041" -> "A").
  private func rewriteFromUnicodeCharFormat(_ request: ConversionRequest, _ segments: Segments)
    -> Bool
  {
    let segmentsSize = segments.conversionSegmentsSize
    if segmentsSize == 0 {
      return false
    }
    let enableMultiSegment = request.request().decoderExperimentParams
      .enableMultiSegmentCandidate
    if !enableMultiSegment && segmentsSize != 1 {
      return false
    }

    let key = request.key()
    guard let value = getValue(key) else {
      return false
    }

    let segment = segments.mutableConversionSegment(0)
    let convertedSegmentCount = enableMultiSegment ? segmentsSize : 1
    addCandidate(key, value, convertedSegmentCount, 0, segment)
    return true
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    // "A" -> "U+0041" (Reverse conversion only).
    if rewriteToUnicodeCharFormat(request, segments) {
      return true
    }

    // "U+0041" -> "A"
    if rewriteFromUnicodeCharFormat(request, segments) {
      return true
    }

    return false
  }
}
