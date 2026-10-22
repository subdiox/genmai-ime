// Port of mozc/src/rewriter/small_letter_rewriter.{h,cc} (3.35.6354).
//
// The parser works on the UTF-8 bytes of the input, as in C++.

import GenmaiBase
import GenmaiProtocol

// Here std::map is used instead of char* or other collections. Because these
// mapping can be extended for other letters like '+' or 'a', implementation
// based on array will not work in the future. In order to avoid that,
// std::map is chosen.
private let kSuperscriptTable: [UInt8: String] = [
  UInt8(ascii: "0"): "⁰",
  UInt8(ascii: "1"): "¹",
  UInt8(ascii: "2"): "²",
  UInt8(ascii: "3"): "³",
  UInt8(ascii: "4"): "⁴",
  UInt8(ascii: "5"): "⁵",
  UInt8(ascii: "6"): "⁶",
  UInt8(ascii: "7"): "⁷",
  UInt8(ascii: "8"): "⁸",
  UInt8(ascii: "9"): "⁹",
  UInt8(ascii: "+"): "⁺",
  UInt8(ascii: "-"): "⁻",
  UInt8(ascii: "="): "⁼",
  UInt8(ascii: "("): "⁽",
  UInt8(ascii: ")"): "⁾",
]

private let kSubscriptTable: [UInt8: String] = [
  UInt8(ascii: "0"): "₀",
  UInt8(ascii: "1"): "₁",
  UInt8(ascii: "2"): "₂",
  UInt8(ascii: "3"): "₃",
  UInt8(ascii: "4"): "₄",
  UInt8(ascii: "5"): "₅",
  UInt8(ascii: "6"): "₆",
  UInt8(ascii: "7"): "₇",
  UInt8(ascii: "8"): "₈",
  UInt8(ascii: "9"): "₉",
  UInt8(ascii: "+"): "₊",
  UInt8(ascii: "-"): "₋",
  UInt8(ascii: "="): "₌",
  UInt8(ascii: "("): "₍",
  UInt8(ascii: ")"): "₎",
]

private enum ParserState {
  case defaultState
  case superscriptAll
  case subscriptAll
  case superscriptDigit
  case subscriptDigit
}

private func isDigit(_ c: UInt8) -> Bool { c >= 0x30 && c <= 0x39 }

/// Converts given input into sequence containing subscripts and superscripts
/// and returns it if it contains a transformed input. Otherwise returns nil.
/// These are examples of conversion.
///  * x^2 -> x²
///  * CH_3 -> CH₃
///  * C_6H_12O_6 -> C₆H₁₂O₆
///  * O^2^- -> O²⁻
///  * x^^2_3 -> x^^2₃
/// This function allows conversion of digits sequence. For example, _123 will
/// be converted into ₁₂₃. Other symbols requires prefix as `^+` or `_(` for
/// each occurrence. `^()` does not mean ⁽⁾ but means ⁽).
private func convertExpressions(_ input: String) -> [UInt8]? {
  // Check preconditions
  if input.isEmpty {
    return nil
  }

  var value: [UInt8] = []
  var state = ParserState.defaultState
  let caret = UInt8(ascii: "^")
  let underscore = UInt8(ascii: "_")

  // The interest of this loop is only ASCII characters, and they never appear
  // in two-or-more-byte characters. Therefore, here simply bytes are used.
  for c in input.utf8 {
    switch state {
    case .defaultState:
      if c == caret {
        state = .superscriptAll
      } else if c == underscore {
        state = .subscriptAll
      } else {
        value.append(c)
      }
    case .superscriptAll:
      if isDigit(c), let digit = kSuperscriptTable[c] {
        value.append(contentsOf: digit.utf8)
        state = .superscriptDigit
      } else if let s = kSuperscriptTable[c] {
        value.append(contentsOf: s.utf8)
        state = .defaultState
      } else {
        value.append(caret)
        value.append(c)
        state = .defaultState
      }
    case .subscriptAll:
      if isDigit(c), let digit = kSubscriptTable[c] {
        value.append(contentsOf: digit.utf8)
        state = .subscriptDigit
      } else if let s = kSubscriptTable[c] {
        value.append(contentsOf: s.utf8)
        state = .defaultState
      } else {
        value.append(underscore)
        value.append(c)
        state = .defaultState
      }
    case .superscriptDigit:
      if isDigit(c), let digit = kSuperscriptTable[c] {
        value.append(contentsOf: digit.utf8)
      } else if c == caret {
        state = .superscriptAll
      } else if c == underscore {
        state = .subscriptAll
      } else {
        value.append(c)
        state = .defaultState
      }
    case .subscriptDigit:
      if isDigit(c), let digit = kSubscriptTable[c] {
        value.append(contentsOf: digit.utf8)
      } else if c == caret {
        state = .superscriptAll
      } else if c == underscore {
        state = .subscriptAll
      } else {
        value.append(c)
        state = .defaultState
      }
    }
  }
  if state == .superscriptAll {
    value.append(caret)
  } else if state == .subscriptAll {
    value.append(underscore)
  }

  // If not has conversion, it should not be added as candidate.
  if input.utf8.elementsEqual(value) {
    return nil
  }
  return value
}

private func addCandidate(
  _ key: String, _ description: String, _ value: String, _ convertedSegmentCount: Int,
  _ index: Int, _ segment: Segment
) {
  var index = index
  if index < 0 || index > segment.candidatesSize {
    index = segment.candidatesSize
  }

  guard let candidate = segment.insertCandidate(index) else { return }

  candidate.key = key
  candidate.contentKey = key
  candidate.value = value
  candidate.contentValue = value
  candidate.convertedSegmentCount = UInt32(convertedSegmentCount)
  candidate.description = description
  candidate.attributes |= (Attribute.noLearning | Attribute.noVariantsExpansion)
}

private func getValue(_ key: String) -> String? {
  guard let value = convertExpressions(key) else {
    return nil
  }

  if value.isEmpty {
    return nil
  }
  return String(decoding: value, as: UTF8.self)
}

/// A rewriter which converts text to superscripts and subscripts.
public final class SmallLetterRewriter: RewriterInterface {
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
    if request.request().decoderExperimentParams.enableMultiSegmentCandidate {
      return nil
    }
    if segments.resized || segments.conversionSegmentsSize <= 1 {
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

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
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

    // Candidates from this function should not be on high position for
    // single-segment expressions (-1 will be overwritten with the last index
    // of candidates).
    // For multi-segment expressions (e.g. ^123, _123, x^2), boost to the top
    // (index 0) so that the candidate is immediately visible.
    let convertedSegmentCount = enableMultiSegment ? segmentsSize : 1
    let insertIndex = convertedSegmentCount > 1 ? 0 : -1
    addCandidate(key, "上下付き文字", value, convertedSegmentCount, insertIndex, segment)
    return true
  }
}
