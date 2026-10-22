// Port of mozc/src/converter/reverse_converter.{h,cc} (3.35.6354).

import GenmaiBase

/// Tries normalizing input text as a math expression, where full-width
/// numbers and math symbols are converted to their half-width equivalents
/// except for some special symbols, e.g., "×", "÷", and "・". Returns false if
/// the input string contains non-math characters.
func tryNormalizingKeyAsMathExpression(_ s: some StringProtocol, _ key: inout String) -> Bool {
  for c in Util.utf8ToUtf32(s) {
    // Half-width arabic numbers.
    if c >= 0x30 && c <= 0x39 {
      key.unicodeScalars.append(Unicode.Scalar(UInt8(c)))
      continue
    }
    // Full-width arabic numbers ("０" -- "９")
    if c >= 0xFF10 && c <= 0xFF19 {
      key.unicodeScalars.append(Unicode.Scalar(UInt8(c - 0xFF10 + 0x30)))
      continue
    }
    switch c {
    case 0x002B, 0xFF0B:  // "+", "＋"
      key.append("+")
    case 0x002D, 0x30FC:  // "-", "ー"
      key.append("-")
    case 0x002A, 0xFF0A, 0x00D7:  // "*", "＊", "×"
      key.append("*")
    case 0x002F, 0xFF0F, 0x30FB, 0x00F7:
      // "/",  "／", "・", "÷"
      key.append("/")
    case 0x0028, 0xFF08:  // "(", "（"
      key.append("(")
    case 0x0029, 0xFF09:  // ")", "）"
      key.append(")")
    case 0x003D, 0xFF1D:  // "=", "＝"
      key.append("=")
    default:
      return false
    }
  }
  return true
}

public final class ReverseConverter: Sendable {
  private let immutableConverter: any ImmutableConverterInterface

  public init(_ immutableConverter: any ImmutableConverterInterface) {
    self.immutableConverter = immutableConverter
  }

  public func reverseConvert(_ key: some StringProtocol, _ segments: Segments) -> Bool {
    // Check if |key| looks like a math expression.  In such case, there's no
    // chance to get the correct reading by the immutable converter.  Rather,
    // simply returns normalized value.
    do {
      var value = ""
      if tryNormalizingKeyAsMathExpression(key, &value) {
        let cand = segments.mutableSegment(0).pushBackCandidate()
        cand.key = String(key)
        cand.value = value
        return true
      }
    }

    var options = ConversionOptions()
    options.requestType = .reverseConversion
    let defaultRequest = ConversionRequestBuilder().setOptions(options).build()
    if !immutableConverter.convert(defaultRequest.options(), segments) {
      return false
    }
    if segments.segmentsSize == 0 {
      // LOG(WARNING) << "no segments from reverse conversion";
      return false
    }
    for seg in segments.all {
      if seg.candidatesSize == 0 || seg.candidate(0).value.isEmpty {
        segments.clear()
        // LOG(WARNING) << "got an empty segment from reverse conversion";
        return false
      }
    }
    return true
  }
}
