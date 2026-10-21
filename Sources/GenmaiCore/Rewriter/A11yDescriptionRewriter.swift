// Port of mozc/src/rewriter/a11y_description_rewriter.{h,cc} (3.35.6354).

import GenmaiBase
import GenmaiProtocol

private func inRange(_ codepoint: Char32, _ low: Char32, _ high: Char32) -> Bool {
  codepoint >= low && codepoint <= high
}

/// Unicode scalar value of a single-scalar string literal.
private func u(_ s: Unicode.Scalar) -> Char32 { Char32(s.value) }

public final class A11yDescriptionRewriter: RewriterInterface {
  enum CharacterType {
    case initialState
    case hiragana  // 'あ'
    case hiraganaSmallLetter  // 'ぁ'
    case katakana  // 'ア'
    case katakanaSmallLetter  // 'ァ'
    case halfWidthKatakana  // 'ｱ'
    case halfWidthKatakanaSmallLetter  // 'ｧ'
    case prolongedSoundMark  // 'ー'
    case halfAlphabetLower  // 'a' - 'z'
    case halfAlphabetUpper  // 'A' - 'Z'
    case fullAlphabetLower  // 'ａ' - 'ｚ'
    case fullAlphabetUpper  // 'Ａ' - 'Ｚ'
    case others  // '亜', number, symbol, alphabet...
  }

  private let smallLetterSet: Set<Char32>
  private let halfWidthSmallKatakanaToLargeKatakana: [Char32: Char32]
  private let descriptionMap: SerializedDictionary?

  public convenience init(_ data: (tokenArray: DataView, stringArray: DataView)) {
    self.init(data.tokenArray, data.stringArray)
  }

  public init(_ tokenArrayData: DataView, _ stringArrayData: DataView) {
    smallLetterSet = Set(
      [
        // Small hiragana
        "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "ゃ", "ゅ", "ょ", "っ", "ゎ",
        // Small katakana
        "ァ", "ィ", "ゥ", "ェ", "ォ", "ャ", "ュ", "ョ", "ッ", "ヮ",
        // Half-width small katakana
        "ｧ", "ｨ", "ｩ", "ｪ", "ｫ", "ｬ", "ｭ", "ｮ", "ｯ",
      ].map { (s: Unicode.Scalar) in u(s) })
    halfWidthSmallKatakanaToLargeKatakana = [
      u("ｧ"): u("ｱ"),
      u("ｨ"): u("ｲ"),
      u("ｩ"): u("ｳ"),
      u("ｪ"): u("ｴ"),
      u("ｫ"): u("ｵ"),
      u("ｬ"): u("ﾔ"),
      u("ｭ"): u("ﾕ"),
      u("ｮ"): u("ﾖ"),
      u("ｯ"): u("ﾂ"),
    ]
    if !tokenArrayData.isEmpty && !stringArrayData.isEmpty {
      descriptionMap = SerializedDictionary(
        tokenArray: tokenArrayData, stringArrayData: stringArrayData)
    } else {
      descriptionMap = nil
    }
  }

  func getCharacterType(_ codepoint: Char32) -> CharacterType {
    if inRange(codepoint, u("ぁ"), u("ん")) && codepoint != u("ゑ") && codepoint != u("ゐ") {
      // 'ゐ', 'ゑ' are excluded.
      if smallLetterSet.contains(codepoint) {
        return .hiraganaSmallLetter
      }
      return .hiragana
    }
    if inRange(codepoint, u("ァ"), u("ワ")) || codepoint == u("ヲ") || codepoint == u("ン") {
      // 'ヰ', 'ヱ', 'ヴ', 'ヵ', 'ヶ' are excluded.
      // codepoint order is "ワ,ヰ,ヱ,ヲ,ン,ヴ,ヵ,ヶ".
      if smallLetterSet.contains(codepoint) {
        return .katakanaSmallLetter
      }
      return .katakana
    }
    if inRange(codepoint, u("ｧ"), u("ﾟ")) || inRange(codepoint, u("ｦ"), u("ｯ")) {
      // 　'ｱ' - 'ﾝ', '゛', 'ﾟ', 'ｦ' - 'ｯ'
      if smallLetterSet.contains(codepoint) {
        return .halfWidthKatakanaSmallLetter
      }
      return .halfWidthKatakana
    }
    if codepoint == u("ー") {
      return .prolongedSoundMark
    }
    if inRange(codepoint, u("a"), u("z")) {
      return .halfAlphabetLower
    }
    if inRange(codepoint, u("A"), u("Z")) {
      return .halfAlphabetUpper
    }
    if inRange(codepoint, u("ａ"), u("ｚ")) {
      return .fullAlphabetLower
    }
    if inRange(codepoint, u("Ａ"), u("Ｚ")) {
      return .fullAlphabetUpper
    }
    return .others
  }

  func getKanaCharacterLabel(
    _ codepoint: Char32, _ currentType: CharacterType, _ previousType: CharacterType
  ) -> String {
    var codepoint = codepoint
    var buf = ""
    if previousType == currentType
      && (currentType != .hiraganaSmallLetter && currentType != .katakanaSmallLetter
        && currentType != .halfWidthKatakanaSmallLetter)
    {
      // The expected result of "あい" is "あい。 ヒラガナ あい",
      // thus the output of "い" should be "い" only rather than "ヒラガナ い".
      Util.codepointToUtf8Append(codepoint, &buf)
      return buf
    }
    buf += "。"
    switch currentType {
    case .hiragana:
      buf += "ヒラガナ "
    case .hiraganaSmallLetter:
      buf += "ヒラガナコモジ "
      codepoint += 1  // transform the character from small to normal
    case .katakana:
      buf += "カタカナ "
    case .katakanaSmallLetter:
      buf += "カタカナコモジ "
      codepoint += 1  // transform the character from small to normal
    case .halfWidthKatakana:
      buf += "ハンカクカタカナ "
    case .halfWidthKatakanaSmallLetter:
      buf += "ハンカクカタカナコモジ "
      codepoint = halfWidthSmallKatakanaToLargeKatakana[codepoint]!
    case .prolongedSoundMark:
      buf += "チョウオン "
    case .halfAlphabetLower:
      buf += "コモジ "
    case .halfAlphabetUpper:
      buf += "オオモジ "
    case .fullAlphabetLower:
      buf += "ゼンカクコモジ "
    case .fullAlphabetUpper:
      buf += "ゼンカクオオモジ "
    default:
      break
    }
    Util.codepointToUtf8Append(codepoint, &buf)
    return buf
  }

  func addA11yDescription(_ candidate: Candidate) {
    let value = candidate.value
    var buf = value
    var previousType = CharacterType.initialState
    var currentType = CharacterType.initialState
    let graphemes = Util.splitStringToUtf8Graphemes(value)
    for grapheme in graphemes {
      let codepoints = Util.utf8ToUtf32(grapheme)
      for codepoint in codepoints {
        previousType = currentType
        currentType = getCharacterType(codepoint)
        if currentType == .others {
          let key = Util.codepointToUtf8(codepoint)
          let range = descriptionMap!.equalRange(key)
          if !range.isEmpty {
            // Add a punctuation for better Talkback result.
            buf += "。" + descriptionMap![range.lowerBound].value
          }
          continue
        }
        if (currentType == .prolongedSoundMark || currentType == .hiraganaSmallLetter
          || currentType == .katakanaSmallLetter)
          && (previousType == .hiragana || previousType == .katakana)
        {
          currentType = previousType
        }
        buf += getKanaCharacterLabel(codepoint, currentType, previousType)
      }
    }
    candidate.a11yDescription = buf
  }

  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType {
    // Enable the rewriter when TalkBack is enabled or enable_a11y_description is
    // explicitly set to true.
    let enableA11yDescription =
      request.request().isA11YTalkbackEnabled || request.request().enableA11YDescription
    if descriptionMap != nil && enableA11yDescription {
      return .all
    }
    return .notAvailable
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    var modified = false
    for segment in segments.conversionSegments {
      for j in 0..<segment.candidatesSize {
        let candidate = segment.mutableCandidate(j)
        addA11yDescription(candidate)
        modified = true
      }
    }
    return modified
  }
}
