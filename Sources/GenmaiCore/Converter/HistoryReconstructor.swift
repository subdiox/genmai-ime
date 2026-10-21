// Port of mozc/src/converter/history_reconstructor.{h,cc} (3.35.6354).

import GenmaiBase

/// Extracts the last substring that consists of the same script type.
/// Returns true if the last substring is successfully extracted.
///   Examples:
///   - "" -> false
///   - "x " -> "x" / ALPHABET
///   - "x  " -> false
///   - "C60" -> "60" / NUMBER
///   - "200x" -> "x" / ALPHABET
///   (currently only NUMBER and ALPHABET are supported)
private func extractLastTokenWithScriptType(
  _ text: some StringProtocol, _ lastToken: inout String, _ lastScriptType: inout Util.ScriptType
) -> Bool {
  lastToken = ""
  lastScriptType = .scriptTypeSize

  let chars = Util.utf8ToUtf32(text)
  var i = chars.count - 1  // reverse iterator
  if i < 0 {
    return false
  }

  // Allow one whitespace at the end.
  if chars[i] == 0x20 {
    i -= 1
    if i < 0 {
      return false
    }
    if chars[i] == 0x20 {
      return false
    }
  }

  var reverseLastToken: [Char32] = []
  let lastScriptTypeFound = Util.getScriptType(chars[i])
  while i >= 0 {
    let codepoint = chars[i]
    if codepoint == 0x20 || Util.getScriptType(codepoint) != lastScriptTypeFound {
      break
    }
    reverseLastToken.append(codepoint)
    i -= 1
  }

  lastScriptType = lastScriptTypeFound
  for c in reverseLastToken.reversed() {
    Util.codepointToUtf8Append(c, &lastToken)
  }
  return true
}

public final class HistoryReconstructor: Sendable {
  private let posMatcher: PosMatcher

  public init(_ posMatcher: PosMatcher) {
    self.posMatcher = posMatcher
  }

  public func reconstructHistory(_ precedingText: some StringProtocol, _ segments: Segments) -> Bool
  {
    var key = ""
    var value = ""
    var id: UInt16 = 0
    if !getLastConnectivePart(precedingText, &key, &value, &id) {
      return false
    }

    let segment = segments.addSegment()
    segment.setKey(key)
    segment.setSegmentType(.history)
    let candidate = segment.pushBackCandidate()
    candidate.rid = id
    candidate.lid = id
    candidate.contentKey = key
    candidate.key = key
    candidate.contentValue = value
    candidate.value = value
    candidate.attributes = Attribute.noLearning
    return true
  }

  /// Returns the substring of |str|. This substring consists of similar
  /// script type and you can use it as preceding text for conversion.
  /// (private in C++; internal for the test peer)
  func getLastConnectivePart(
    _ precedingText: some StringProtocol, _ key: inout String, _ value: inout String,
    _ id: inout UInt16
  ) -> Bool {
    key = ""
    value = ""
    id = posMatcher.getGeneralNounId()

    var lastScriptType = Util.ScriptType.scriptTypeSize
    var lastToken = ""
    if !extractLastTokenWithScriptType(precedingText, &lastToken, &lastScriptType) {
      return false
    }

    // Currently only NUMBER and ALPHABET are supported.
    switch lastScriptType {
    case .number:
      key = JapaneseUtil.fullWidthAsciiToHalfWidthAscii(lastToken)
      value = lastToken
      id = posMatcher.getNumberId()
      return true
    case .alphabet:
      key = JapaneseUtil.fullWidthAsciiToHalfWidthAscii(lastToken)
      value = lastToken
      id = posMatcher.getUniqueNounId()
      return true
    default:
      return false
    }
  }
}
