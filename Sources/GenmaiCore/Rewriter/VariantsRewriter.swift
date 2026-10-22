// Port of mozc/src/rewriter/variants_rewriter.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - The annotation constants are the non-Android values (this port targets
//   macOS).
// - `DescriptionType` / `RewriteType` are private integer constants / a private
//   enum; `AlternativeCandidateResult` is a private struct.
// - String comparisons that are bytewise in C++ use `bytesEqual` (Swift `==`
//   uses canonical equivalence).

import GenmaiBase
import GenmaiProtocol

public final class VariantsRewriter: RewriterInterface, Sendable {
  // Annotation constants.
  public static let kHiragana = "ひらがな"
  public static let kKatakana = "カタカナ"
  public static let kNumber = "数字"
  public static let kAlphabet = "アルファベット"
  public static let kKanji = "漢字"
  public static let kFullWidth = "[全]"
  public static let kHalfWidth = "[半]"
  public static let kYenKigou = "円記号"

  // 1) Full width / half width description
  // 2) CharForm (hiragana/katakana) description
  // 3) Zipcode description (XXX-XXXX)
  //     * note that this overrides other descriptions
  // (enum DescriptionType)
  private static let fullHalfWidth = 1  // automatically detect full/haflwidth.
  private static let deprecatedFullHalfWidthWithUnknown = 2  // Deprecated.
  // Set half/full width for symbols.
  // This flag must be used together with FULL_HALF_WIDTH.
  // If WITH_UNKNOWN is specified, assign FULL/HALF width annotation
  // more aggressively.
  private static let halfWidth = 4  // set half width description if applicable.
  // otherwise, no width description is set.
  private static let fullWidth = 8  // set full width description if applicable.
  // otherwise, no width description is set.
  private static let characterForm = 16  // Hiragana/Katakana..etc
  private static let deprecatedPlatformDependentCharacter = 32  // Deprecated. "機種依存文字"
  private static let zipcode = 64

  private enum RewriteType {
    case expandVariant  // Expand variants
    case selectVariant  // Select preferred form
  }

  // Returns an alternative candidate and information for the base candidate.
  private struct AlternativeCandidateResult {
    var isOriginalCandidatePrimary = false
    var originalCandidateDescriptionType = 0
    var alternativeCandidate: Candidate? = nil
  }

  private let posMatcher: PosMatcher

  public init(_ posMatcher: PosMatcher) {
    self.posMatcher = posMatcher
  }

  // MARK: - Static description helpers

  /// Used by UserSegmentHistoryRewriter.
  public static func setDescriptionForCandidate(_ posMatcher: PosMatcher, _ candidate: Candidate) {
    setDescription(posMatcher, fullHalfWidth | characterForm | zipcode, candidate)
  }

  public static func setDescriptionForTransliteration(
    _ posMatcher: PosMatcher, _ candidate: Candidate
  ) {
    setDescription(posMatcher, fullHalfWidth | characterForm, candidate)
  }

  public static func setDescriptionForPrediction(_ posMatcher: PosMatcher, _ candidate: Candidate) {
    setDescription(posMatcher, zipcode, candidate)
  }

  private static func getDescription(
    _ posMatcher: PosMatcher, _ descriptionTypeIn: Int, _ candidate: Candidate
  ) -> String {
    var descriptionType = descriptionTypeIn
    var characterFormMessage = ""
    var pieces: [String] = []

    // Add Character form.
    if descriptionType & characterForm != 0 {
      let type = Util.getScriptTypeWithoutSymbols(candidate.value)
      switch type {
      case .hiragana:
        characterFormMessage = kHiragana
        // don't need to set full/half, because hiragana only has
        // full form
        descriptionType &= ~fullHalfWidth
      case .katakana:
        // character_form_message = "カタカナ";
        characterFormMessage = kKatakana
        // don't need to proactively set full, because katakana is mostly used
        // in full form.
        descriptionType &= ~fullHalfWidth
        descriptionType |= halfWidth
      case .number:
        // character_form_message = "数字";
        characterFormMessage = kNumber
        // don't need to proactively set half, because number is mostly used in
        // half form.
        descriptionType &= ~fullHalfWidth
        descriptionType |= fullWidth
      case .alphabet:
        // character_form_message = "アルファベット";
        characterFormMessage = kAlphabet
        // don't need to proactively set half, because alphabet is mostly used
        // in half form.
        descriptionType &= ~fullHalfWidth
        descriptionType |= fullWidth
      case .kanji, .emoji:
        // don't need to have full/half annotation for kanji and emoji,
        // since it's obvious
        descriptionType &= ~fullHalfWidth
      case .unknownScript:  // mixed character
        if hasCharacterFormDescription(candidate.value) {
          descriptionType |= fullHalfWidth
        } else if getVariableWidthFormType(candidate.value) != .unknownForm {
          // Follow the same policy as pure NUMBER/ALPHABET: suppress [半] on
          // standalone candidates (clearing FULL_HALF_WIDTH while setting
          // FULL_WIDTH), but retain explicit HALF_WIDTH when alternative
          // candidates are generated in RewriteSegment().
          descriptionType &= ~fullHalfWidth
          descriptionType |= fullWidth
        } else {
          descriptionType &= ~fullHalfWidth
        }
      default:
        // Do nothing
        break
      }
    }

    // If candidate already has a description, clear it.
    // Currently, character_form_message is treated as a "default"
    // description.
    if !candidate.description.isEmpty {
      characterFormMessage = ""
    }

    let form = getVariableWidthFormType(candidate.value)
    // full/half char description
    if descriptionType & fullHalfWidth != 0 {
      switch form {
      case .fullWidth:
        // description = "[全]";
        pieces.append(kFullWidth)
      case .halfWidth:
        // description = "[半]";
        pieces.append(kHalfWidth)
      default:
        break
      }
    } else if descriptionType & fullWidth != 0 && form == .fullWidth {
      // description = "[全]";
      pieces.append(kFullWidth)
    } else if descriptionType & halfWidth != 0 && form == .halfWidth {
      // description = "[半]";
      pieces.append(kHalfWidth)
    }

    // add character_form_message
    if !characterFormMessage.isEmpty {
      pieces.append(characterFormMessage)
    }

    // add main message
    let value = candidate.value
    if value.bytesEqual("\\") || value.bytesEqual("＼") {
      // if "\" (half-width backslash) or "＼" (full-width backslash)
      pieces.append("バックスラッシュ")
    } else if value.bytesEqual("¥") {
      // if "¥" (half-width Yen sign), append kYenKigou.
      pieces.append(kYenKigou)
    } else if value.bytesEqual("￥") {
      // if "￥" (full-width Yen sign), append only kYenKigou
      pieces.append(kYenKigou)
    } else if value.bytesEqual("~") {
      pieces.append("チルダ")
    } else if !candidate.description.isEmpty {
      pieces.append(candidate.description)
    }

    // The following description tries to overwrite existing description.
    // TODO(taku): reconsider this behavior.
    // Zipcode description
    if descriptionType & zipcode != 0 && posMatcher.isZipcode(candidate.lid)
      && candidate.lid == candidate.rid
    {
      if !candidate.contentKey.isEmpty {
        pieces = [candidate.contentKey]
      } else {
        pieces.removeAll()
      }
      // Append default description because it may contain extra description.
      if !candidate.description.isEmpty {
        pieces.append(candidate.description)
      }
    }

    return pieces.joined(separator: " ")
  }

  private static func setDescription(
    _ posMatcher: PosMatcher, _ descriptionType: Int, _ candidate: Candidate
  ) {
    // set new description
    candidate.description = getDescription(posMatcher, descriptionType, candidate)
    candidate.attributes |= Attribute.noExtraDescription
  }

  // MARK: - RewriterInterface

  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType {
    .all
  }

  /// Returns form types for given two pair of strings.
  /// This function tries to find the difference between
  /// |input1| and |input2| and find the place where the script
  /// form (halfwidth/fullwidth) is different. This function returns
  /// a pair of forms if input1 or input2 needs to have full/half width
  /// annotation.
  ///
  /// Example:
  ///  input1="ABCぐーぐる input2="ＡＢＣ"
  ///  form1=Half form2=Full
  ///
  /// If input1 and input2 have mixed form types and the result
  /// is ambiguous, this function returns {FULL_HALF_WIDTH, FULL_HALF_WIDTH}.
  ///
  /// Ambiguous case:
  ///  input1="ABC１２３" input2="ＡＢＣ123"
  ///  return {FULL_HALF_WIDTH, FULL_HALF_WIDTH}.
  public static func getFormTypesFromStringPair(
    _ input1: some StringProtocol, _ input2: some StringProtocol
  ) -> (Util.FormType, Util.FormType) {
    let kUnknownForm: (Util.FormType, Util.FormType) = (.unknownForm, .unknownForm)
    var outputForm1 = Util.FormType.unknownForm
    var outputForm2 = Util.FormType.unknownForm

    let chars1 = input1.unicodeScalars.map { $0.value }
    let chars2 = input2.unicodeScalars.map { $0.value }
    // Skip halfwidth voice/semi-voice sound mark as they are treated as one
    // character.
    func skipHalfWidthVoiceSoundMark(_ chars: [Char32], _ i: Int) -> Int {
      var i = i
      while i != chars.count && isHalfWidthVoiceSoundMark(chars[i]) {
        i += 1
      }
      return i
    }
    var it1 = 0
    var it2 = 0
    while it1 != chars1.count && it2 != chars2.count {
      defer {
        it1 += 1
        it2 += 1
      }
      it1 = skipHalfWidthVoiceSoundMark(chars1, it1)
      it2 = skipHalfWidthVoiceSoundMark(chars2, it2)
      if it1 == chars1.count || it2 == chars2.count {
        // `break` in C++ skips the ++ of the for statement.
        it1 -= 1
        it2 -= 1
        break
      }

      // TODO(taku): have to check that normalized w1 and w2 are identical
      if Util.getScriptType(chars1[it1]) != Util.getScriptType(chars2[it2]) {
        return kUnknownForm
      }

      let form1 = Util.getFormType(chars1[it1])
      let form2 = Util.getFormType(chars2[it2])

      // when having different forms, record the diff in the next step.
      if form1 == form2 {
        continue
      }

      let isConsistent =
        (outputForm1 == .unknownForm || outputForm1 == form1)
        && (outputForm2 == .unknownForm || outputForm2 == form2)
      if !isConsistent {
        // inconsistent with the previous forms.
        return kUnknownForm
      }

      outputForm1 = form1
      outputForm2 = form2
    }

    // length should be the same
    if it1 != chars1.count || it2 != chars2.count {
      return kUnknownForm
    }

    if outputForm1 == .unknownForm || outputForm2 == .unknownForm {
      return kUnknownForm
    }

    return (outputForm1, outputForm2)
  }

  private func createAlternativeCandidate(_ originalCandidate: Candidate)
    -> AlternativeCandidateResult
  {
    var result = AlternativeCandidateResult()
    guard let alt = generateAlternatives(originalCandidate) else {
      return result
    }

    let (primaryForm, secondaryForm) = Self.getFormTypesFromStringPair(
      alt.primaryValue, alt.secondaryValue)
    let isPrimaryHalfWidth = (primaryForm == .halfWidth)
    let isSecondaryHalfWidth = (secondaryForm == .halfWidth)

    func getDescriptionType(_ form: Util.FormType) -> Int {
      let kBaseTypes = Self.characterForm | Self.zipcode
      switch form {
      case .fullWidth:
        return Self.fullWidth | kBaseTypes
      case .halfWidth:
        return Self.halfWidth | kBaseTypes
      default:
        return Self.fullHalfWidth | kBaseTypes
      }
    }
    let primaryDescriptionType = getDescriptionType(primaryForm)
    let secondaryDescriptionType = getDescriptionType(secondaryForm)

    let newCandidate = originalCandidate.copy()

    if originalCandidate.value.bytesEqual(alt.primaryValue) {
      result.isOriginalCandidatePrimary = true
      result.originalCandidateDescriptionType = primaryDescriptionType

      newCandidate.value = alt.secondaryValue
      newCandidate.contentValue = alt.secondaryContentValue
      newCandidate.innerSegmentBoundary = alt.secondaryInnerSegmentBoundary
      newCandidate.style = getStyle(originalCandidate.style, isSecondaryHalfWidth)
      Self.setDescription(posMatcher, secondaryDescriptionType, newCandidate)
    } else {
      result.isOriginalCandidatePrimary = false
      result.originalCandidateDescriptionType = secondaryDescriptionType

      newCandidate.value = alt.primaryValue
      newCandidate.contentValue = alt.primaryContentValue
      newCandidate.innerSegmentBoundary = alt.primaryInnerSegmentBoundary
      newCandidate.style = getStyle(originalCandidate.style, isPrimaryHalfWidth)
      Self.setDescription(posMatcher, primaryDescriptionType, newCandidate)
    }
    result.alternativeCandidate = newCandidate
    return result
  }

  private func rewriteTopCandidateForSuggestion(_ seg: Segment) -> Bool {
    if seg.candidatesSize == 0 {
      return false
    }
    let topCandidate = seg.mutableCandidate(0)
    if topCandidate.attributes & Attribute.realtimeConversion == 0 {
      return false
    }

    guard let alt = generateAlternatives(topCandidate),
      !topCandidate.value.bytesEqual(alt.primaryValue)
    else {
      return false
    }

    // If NumberRewriter has already inserted a modified top candidate (marked
    // with NO_EXTRA_DESCRIPTION), update top_candidate in-place so that both
    // Kanji number conversion and character form normalization are combined into
    // a single best candidate at index 0 (e.g. "ｗｉｋｉｐｅｄｉａを三年使う"),
    // preserving the plain fallback at index 1 ("wikipediaを3年使う").
    //
    // Otherwise, insert a new candidate at index 0.
    var target = topCandidate
    if topCandidate.attributes & Attribute.noExtraDescription == 0 {
      target = Candidate()
      seg.insertCandidate(0, target)
      target.assign(from: seg.candidate(1))
      let fallback = seg.mutableCandidate(1)
      Self.setDescriptionForCandidate(posMatcher, fallback)
      // Clear NO_VARIANTS_EXPANSION so that Finish() can learn the character form
      // when the fallback variant is committed. It has NO_EXTRA_DESCRIPTION, so
      // RewriteSegment() will not re-expand it.
      fallback.attributes &= ~Attribute.noVariantsExpansion
    }
    target.value = alt.primaryValue
    target.innerSegmentBoundary = alt.primaryInnerSegmentBoundary
    let merged = target.innerSegments().getMergedContentKeyAndValue()
    target.contentKey = String(merged.key)
    target.contentValue = String(merged.value)
    // Clear NO_VARIANTS_EXPANSION so that Finish() can learn the character form
    // when the primary variant is committed, including when `target` is updated
    // in-place. It has NO_EXTRA_DESCRIPTION, so RewriteSegment() will not
    // re-expand it.
    target.attributes &= ~Attribute.noVariantsExpansion
    target.attributes |= Attribute.noExtraDescription
    return true
  }

  private func rewriteSegment(_ type: RewriteType, _ seg: Segment) -> Bool {
    var modified = false

    // Meta Candidate
    for candidate in seg.metaCandidates {
      if candidate.attributes & Attribute.noExtraDescription != 0 {
        continue
      }
      Self.setDescriptionForTransliteration(posMatcher, candidate)
    }

    // Regular Candidate
    var i = 0
    while i < seg.candidatesSize {
      defer { i += 1 }
      let originalCandidate = seg.mutableCandidate(i)

      if originalCandidate.attributes & Attribute.noExtraDescription != 0 {
        continue
      }

      if originalCandidate.attributes & Attribute.noVariantsExpansion != 0 {
        Self.setDescriptionForCandidate(posMatcher, originalCandidate)
        // MOZC_VLOG(1) << "Candidate has NO_NORMALIZATION node";
        continue
      }

      let result = createAlternativeCandidate(originalCandidate)
      guard let alternativeCandidate = result.alternativeCandidate else {
        Self.setDescriptionForCandidate(posMatcher, originalCandidate)
        continue
      }

      if originalCandidate.description.isEmpty
        && originalCandidate.attributes & Attribute.userHistoryPrediction != 0
      {
        Self.setDescriptionForPrediction(posMatcher, originalCandidate)
        continue
      }

      Self.setDescription(posMatcher, result.originalCandidateDescriptionType, originalCandidate)
      if type == .expandVariant {
        // If the original candidate is the primary candidate, insert alternative
        // candidate after the original candidate as the secondary candidate.
        let index = result.isOriginalCandidatePrimary ? i + 1 : i
        seg.insertCandidate(index, alternativeCandidate)
        i += 1  // skip inserted candidate
      } else if !result.isOriginalCandidatePrimary {
        // If the original candidate is not the primary candidate, remove it and
        // insert the alternative candidate as a replacement.
        seg.eraseCandidate(i)
        seg.insertCandidate(i, alternativeCandidate)
      }
      modified = true
    }
    return modified
  }

  /// Values for primary and secondary candidates generated by
  /// `generateAlternatives`.
  ///
  /// There are two orthogonal categories for two candidates.
  ///
  /// * {primary, secondary}: The primary candidate ranked higher than secondary.
  ///   If the user has configured half-width value as primary, full-width value
  ///   will be secondary.
  /// * {original, alternative}: Original is the candidate that already exists in
  ///   the segment before this rewriter. The original candidate is used as the
  ///   input to this rewriter. Alternative is the candidate that is generated
  ///   from the original candidate.
  ///
  /// original can be either primary or secondary. alternative will be the
  /// opposite of original.
  private struct Alternatives {
    var primaryValue = ""
    var secondaryValue = ""
    var primaryContentValue = ""
    var secondaryContentValue = ""
    var primaryInnerSegmentBoundary: InnerSegmentBoundary = []
    var secondaryInnerSegmentBoundary: InnerSegmentBoundary = []
  }

  /// Try generating default and alternative character forms.  Inner segment
  /// boundary is taken into account.  When no rewrite happens, nil is returned
  /// (C++: returns false).
  private func generateAlternatives(_ original: Candidate) -> Alternatives? {
    var out = Alternatives()
    let manager = CharacterFormManager.getCharacterFormManager()

    // When inner segment boundary is present, rewrite each inner segment.  If at
    // least one inner segment is rewritten, the whole segment is considered
    // rewritten.
    var atLeastOneModified = false
    var innerPrimaryValue = ""
    var innerSecondaryValue = ""
    var innerPrimaryContentValue = ""
    var innerSecondaryContentValue = ""
    var primaryBuilder = InnerSegmentBoundaryBuilder()
    var secondaryBuilder = InnerSegmentBoundaryBuilder()

    for iter in original.innerSegments() {
      innerPrimaryValue = ""
      innerSecondaryValue = ""
      if !manager.convertConversionStringWithAlternative(
        iter.value, &innerPrimaryValue, &innerSecondaryValue)
      {
        innerPrimaryValue = String(iter.value)
        innerSecondaryValue = String(iter.value)
      } else {
        atLeastOneModified = true
      }
      if !iter.value.bytesEqual(iter.contentValue) {
        innerPrimaryContentValue = ""
        innerSecondaryContentValue = ""
        _ = manager.convertConversionStringWithAlternative(
          iter.contentValue, &innerPrimaryContentValue, &innerSecondaryContentValue)
      } else {
        innerPrimaryContentValue = innerPrimaryValue
        innerSecondaryContentValue = innerSecondaryValue
      }
      out.primaryValue += innerPrimaryValue
      out.secondaryValue += innerSecondaryValue
      out.primaryContentValue += innerPrimaryContentValue
      out.secondaryContentValue += innerSecondaryContentValue
      primaryBuilder.add(
        iter.key.utf8.count, innerPrimaryValue.utf8.count, iter.contentKey.utf8.count,
        innerPrimaryContentValue.utf8.count)
      secondaryBuilder.add(
        iter.key.utf8.count, innerSecondaryValue.utf8.count, iter.contentKey.utf8.count,
        innerSecondaryContentValue.utf8.count)
    }

    out.primaryInnerSegmentBoundary = primaryBuilder.build(original.key, out.primaryValue)
    out.secondaryInnerSegmentBoundary = secondaryBuilder.build(original.key, out.secondaryValue)
    return atLeastOneModified ? out : nil
  }

  public func finish(_ request: ConversionRequest, _ segments: Segments) {
    if request.incognitoMode() {
      // MOZC_VLOG(2) << "incognito mode";
      return
    }
    if request.config().historyLearningLevel != .defaultHistory {
      // MOZC_VLOG(2) << "history_learning_level is not DEFAULT_HISTORY";
      return
    }

    let manager = CharacterFormManager.getCharacterFormManager()
    // save character form
    for segment in segments.conversionSegments {
      if segment.candidatesSize <= 0 || segment.segmentType != .fixedValue
        || segment.candidate(0).attributes & Attribute.noHistoryLearning != 0
      {
        continue
      }

      let candidate = segment.candidate(0)
      switch candidate.style {
      case .numberSeparatedArabicHalfwidth, .numberArabicAndKanjiHalfwidth:
        // treat as half_width num
        manager.setCharacterForm("0", .halfWidth)
        continue
      case .numberSeparatedArabicFullwidth, .numberArabicAndKanjiFullwidth:
        // treat as full_width num
        manager.setCharacterForm("0", .fullWidth)
        continue
      default:
        break
      }

      if candidate.attributes & (Attribute.noVariantsExpansion | Attribute.userDictionary) != 0 {
        continue
      }
      // Special handling for number compounds like 3時 that have a character
      // width annotation in the description.  Otherwise,
      // GuessAndSetCharacterForm() below guesses the character form per script
      // chunk from |candidate.value|.
      if Util.getFirstScriptType(candidate.value) == .number {
        if bytesContains(candidate.description, Self.kHalfWidth) {
          manager.setCharacterForm("0", .halfWidth)
          continue
        }
        if bytesContains(candidate.description, Self.kFullWidth) {
          manager.setCharacterForm("0", .fullWidth)
          continue
        }
      }
      manager.guessAndSetCharacterForm(stripTrailingAsciiWhitespace(candidate.value))
    }
  }

  public func clear() {
    CharacterFormManager.getCharacterFormManager().clearHistory()
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    var modified = false

    // NOTE:
    // 1. In realtime conversion, conversion segments are already aggregated into
    //    a single segment (with inner_segments) by the time post-correction
    //    rewriters are applied.
    // 2. This is a workaround to make variant rewriting work properly for such
    //    realtime conversion results (e.g. full-width / half-width character
    //    form normalization) using inner_segments.
    // 3. This is a transitional implementation; ideally, this logic should be
    //    refactored and placed in a cleaner, more appropriate layer.
    if request.requestType() != .partialSuggestion
      && request.requestType() != .partialPrediction
      && request.request().decoderExperimentParams.suppressRealtimeConversionWithConverter
    {
      if segments.conversionSegmentsSize > 0 {
        modified =
          rewriteTopCandidateForSuggestion(segments.mutableConversionSegment(0)) || modified
      }
    }

    let type: RewriteType
    if request.request().mixedConversion {  // For mobile.
      type = .expandVariant
    } else if request.requestType() == .suggestion {
      type = .selectVariant
    } else {
      type = .expandVariant
    }

    for segment in segments.conversionSegments {
      modified = rewriteSegment(type, segment) || modified
    }

    return modified
  }
}

// MARK: - File-local helpers

// Returns true if |full| has the corresponding half width form.
private func isConvertibleToHalfWidthForm(_ full: some StringProtocol) -> Bool {
  // TODO(b/209357879): remove this line once FullWidthToHalfWidth() itself will
  // support the conversion.
  var tmp = String.UnicodeScalarView()
  for scalar in full.unicodeScalars {
    switch scalar {
    case "＼": tmp.append("\\")
    case "￥": tmp.append("¥")
    default: tmp.append(scalar)
    }
  }
  let half = Japanese.fullWidthToHalfWidth(String(tmp))
  return !full.bytesEqual(half)
}

// Returns true if |value| meets all the following 1) ~ 3) conditions.
// 1) all charcters in |value| are UNKNOWN_SCRIPT
// 2) FormType of |value| are consistent, e.g. all fullwith or all halfwidth
// 3) if they're all fullwidth characters, they're potentially convertible to
//    their corresponding halfwidth form, e.g. '／' => '/'
// Example:
// "&-()" => true (all symbol and all half)
// "／" => true (all symbol, all full and convertible to the corresponding half)
// "&-（）" => false (all symbol but contains both full/half width)
// "google" => false (not symbol)
// "㌫" => false (all symbol, all full but not convertible to the corresponding
// half)
private func hasCharacterFormDescription(_ value: String) -> Bool {
  if value.isEmpty {
    return false
  }
  var prev = Util.FormType.unknownForm

  for scalar in value.unicodeScalars {
    let codepoint = scalar.value
    let type = Util.getFormType(codepoint)
    if prev != .unknownForm && prev != type {
      return false
    }
    if Util.getScriptType(codepoint) != .unknownScript {
      return false
    }
    prev = type
  }

  if prev == .halfWidth {
    return true
  }

  // returns false here only if all the characters are fullwidth and they're not
  // convertible to their corresponding halfwidth forms.
  return isConvertibleToHalfWidthForm(value)
}

// Determines the form (FULL_WIDTH / HALF_WIDTH) based on the variable-width
// scripts (alphabet, number, symbol, and half-width katakana) in |value|,
// ignoring fixed scripts like kanji, hiragana, and full-width katakana.
private func getVariableWidthFormType(_ value: String) -> Util.FormType {
  var resultForm = Util.FormType.unknownForm
  // Swift strings are always valid UTF-8, so `it.ok()` is always true.
  for scalar in value.unicodeScalars {
    let c = scalar.value
    let script = Util.getScriptType(c)
    if script == .kanji || script == .hiragana {
      continue
    }
    let form = Util.getFormType(c)
    if script == .katakana && form == .fullWidth {
      continue
    }
    if script == .unknownScript && form == .fullWidth
      && !isConvertibleToHalfWidthForm(String(scalar))
    {
      continue
    }
    if form == .unknownForm {
      continue
    }
    if resultForm == .unknownForm {
      resultForm = form
    } else if resultForm != form {
      return .unknownForm
    }
  }
  return resultForm
}

// Returns NumberString::Style corresponding to the given form
private func getStyle(
  _ originalStyle: NumberUtil.NumberString.Style, _ isHalfWidthForm: Bool
) -> NumberUtil.NumberString.Style {
  switch originalStyle {
  case .numberSeparatedArabicHalfwidth, .numberSeparatedArabicFullwidth:
    return isHalfWidthForm ? .numberSeparatedArabicHalfwidth : .numberSeparatedArabicFullwidth
  case .numberArabicAndKanjiHalfwidth, .numberArabicAndKanjiFullwidth:
    return isHalfWidthForm ? .numberArabicAndKanjiHalfwidth : .numberArabicAndKanjiFullwidth
  default:
    return originalStyle
  }
}

private func isHalfWidthVoiceSoundMark(_ ch: Char32) -> Bool {
  // 0xFF9E: Halfwidth voice sound mark
  // 0xFF9F: Halfwidth semi-voice sound mark
  ch == 0xFF9E || ch == 0xFF9F
}

/// Bytewise `absl::StrContains`.
private func bytesContains(_ haystack: String, _ needle: String) -> Bool {
  let h = Array(haystack.utf8)
  let n = Array(needle.utf8)
  if n.isEmpty { return true }
  if n.count > h.count { return false }
  for start in 0...(h.count - n.count) where h[start..<(start + n.count)].elementsEqual(n) {
    return true
  }
  return false
}

/// `absl::StripTrailingAsciiWhitespace`.
private func stripTrailingAsciiWhitespace(_ s: String) -> Substring {
  var end = s.utf8.endIndex
  while end > s.utf8.startIndex {
    let prev = s.utf8.index(before: end)
    switch s.utf8[prev] {
    case 0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D:
      end = prev
    default:
      return s[s.startIndex..<end]
    }
  }
  return s[s.startIndex..<end]
}
