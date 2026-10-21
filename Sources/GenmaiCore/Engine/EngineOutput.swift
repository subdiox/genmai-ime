// Port of mozc/src/engine/engine_output.{h,cc} (3.35.6354).
//
// Class functions to be used for output by the Session class.
//
// Deviations from C++:
// - The `engine::output` namespace is the caseless enum `EngineOutput`.
// - `commands::X*` out-parameters are `inout`. C++ `mutable_x()` calls
//   materialize the sub-message even when nothing is written into it; the
//   Swift code passes the sub-message field `inout` (or assigns it back),
//   which has the same effect on `has_x()`.
// - The `#ifndef NDEBUG` debug log of CandidateWord (`set_log`) is not filled
//   (the port behaves like an NDEBUG build).
// - The platform-dependent delete instruction label is the Apple one
//   (this is a macOS port); `port::IsAndroid()` is false.

import GenmaiBase
import GenmaiProtocol

private func fillAnnotation(
  _ candidateValue: Candidate, _ annotation: inout Genmai_Commands_Annotation
) -> Bool {
  var isModified = false
  if !candidateValue.prefix.isEmpty {
    annotation.prefix = candidateValue.prefix
    isModified = true
  }
  if !candidateValue.suffix.isEmpty {
    annotation.suffix = candidateValue.suffix
    isModified = true
  }
  if !candidateValue.description.isEmpty {
    annotation.description_p = candidateValue.description
    isModified = true
  }
  if !candidateValue.a11yDescription.isEmpty {
    annotation.a11YDescription = candidateValue.a11yDescription
    isModified = true
  }
  if candidateValue.attributes & Attribute.userHistoryPrediction != 0
    && candidateValue.attributes & Attribute.noDeletable == 0
  {
    annotation.deletable = true
    isModified = true
  }
  if !candidateValue.displayValue.isEmpty {
    annotation.displayValue = candidateValue.displayValue
    isModified = true
  }
  return isModified
}

private func fillCandidateWord(
  _ segmentCandidate: Candidate, _ id: Int, _ index: Int, _ baseKey: some StringProtocol,
  _ candidateWordProto: inout Genmai_Commands_CandidateWord
) {
  candidateWordProto.id = Int32(truncatingIfNeeded: id)
  candidateWordProto.index = UInt32(truncatingIfNeeded: index)
  if String(baseKey) != segmentCandidate.contentKey {
    candidateWordProto.key = segmentCandidate.contentKey
  }
  candidateWordProto.value = segmentCandidate.value

  var annotation = Genmai_Commands_Annotation()
  if fillAnnotation(segmentCandidate, &annotation) {
    candidateWordProto.annotation = annotation
  }

  if segmentCandidate.attributes & Attribute.userDictionary != 0 {
    candidateWordProto.attributes.append(.userDictionary)
  }
  if segmentCandidate.attributes & Attribute.userHistoryPrediction != 0 {
    candidateWordProto.attributes.append(.userHistory)
    if segmentCandidate.attributes & Attribute.noDeletable == 0 {
      candidateWordProto.attributes.append(.deletable)
    }
  }
  if segmentCandidate.attributes & Attribute.spellingCorrection != 0 {
    candidateWordProto.attributes.append(.spellingCorrection)
  }
  if segmentCandidate.attributes & Attribute.typingCorrection != 0 {
    candidateWordProto.attributes.append(.typingCorrection)
  }

  // number of segments
  candidateWordProto.numSegmentsInCandidate = 1
  if !segmentCandidate.innerSegmentBoundary.isEmpty {
    candidateWordProto.numSegmentsInCandidate = Int32(
      truncatingIfNeeded: segmentCandidate.innerSegmentBoundary.count)
  }
}

private func fillAllCandidateWordsInternal(
  _ segment: Segment, _ candidateList: CandidateList, _ focusedId: Int,
  _ candidateListProto: inout Genmai_Commands_CandidateList
) {
  for i in 0..<candidateList.size {
    let candidate = candidateList.candidate(i)
    if candidate.hasSubcandidateList() {
      fillAllCandidateWordsInternal(
        segment, candidate.subcandidateList, focusedId, &candidateListProto)
      continue
    }

    candidateListProto.candidates.append(Genmai_Commands_CandidateWord())
    let index = candidateListProto.candidates.count - 1
    let id = candidate.id

    // check focused id
    if id == focusedId && candidateList.focused {
      candidateListProto.focusedIndex = UInt32(truncatingIfNeeded: index)
    }

    if !segment.isValidIndex(id) {
      GenmaiLog.error(
        "Inconsistency between segment and candidate_list was observed. candidate index: \(id) / \(candidateList.size), actual candidates size: \(segment.candidatesSize)"
      )
      return
    }
    let segmentCandidate = segment.candidate(id)
    fillCandidateWord(
      segmentCandidate, id, index, segment.key, &candidateListProto.candidates[index])
  }
}

private func getSegmentSpan(_ currentIndex: Int, _ focusedIndex: Int, _ candidate: Candidate)
  -> Int
{
  let count = Int(candidate.effectiveConvertedSegmentCount)
  if currentIndex < focusedIndex && currentIndex + count > focusedIndex {
    return focusedIndex - currentIndex
  }
  return count
}

private func getKey(_ segment: Segment, _ candidate: Candidate) -> String {
  (candidate.effectiveConvertedSegmentCount > 1 && !candidate.key.isEmpty)
    ? candidate.key : segment.key
}

public enum EngineOutput {
  /// `output::SegmentType`.
  public enum SegmentType {
    public static let preedit: UInt32 = 1
    public static let conversion: UInt32 = 2
    public static let focused: UInt32 = 4
  }

  /// Fill the CandidateWindow_Candidate protobuf with the contents of candidate.
  public static func fillCandidate(
    _ segment: Segment, _ candidate: CandidateList.Candidate,
    _ candidateProto: inout Genmai_Commands_CandidateWindow.Candidate
  ) {
    if candidate.hasSubcandidateList() {
      candidateProto.value = candidate.subcandidateList.name
      candidateProto.id = Int32(truncatingIfNeeded: candidate.subcandidateList.focusedId)
      return
    }

    let candidateValue = segment.candidate(candidate.id)
    candidateProto.value = candidateValue.value

    candidateProto.id = Int32(truncatingIfNeeded: candidate.id)
    // Set annotations
    var annotation = Genmai_Commands_Annotation()
    if fillAnnotation(candidateValue, &annotation) {
      candidateProto.annotation = annotation
    }

    if !candidateValue.usageTitle.isEmpty {
      candidateProto.informationID = candidateValue.usageId
    }
  }

  /// Fill the CandidateWindow protobuf with the contents of candidate_list.
  public static func fillCandidateWindow(
    _ segment: Segment, _ candidateList: CandidateList, _ position: Int,
    _ candidateWindowProto: inout Genmai_Commands_CandidateWindow
  ) {
    if candidateList.focused {
      candidateWindowProto.focusedIndex = UInt32(truncatingIfNeeded: candidateList.focusedIndex)
    }
    candidateWindowProto.size = UInt32(truncatingIfNeeded: candidateList.size)
    candidateWindowProto.pageSize = UInt32(truncatingIfNeeded: candidateList.pageSize)
    candidateWindowProto.position = UInt32(truncatingIfNeeded: position)

    let (cBegin, cEnd) = candidateList.getPageRange(candidateList.focusedIndex)

    // Store candidates.
    var i = cBegin
    while i < cEnd {
      let candidate = candidateList.candidate(i)
      if !segment.isValidIndex(candidate.id) {
        GenmaiLog.error(
          "Inconsistency between segment and candidate_list was observed. candidate index: \(candidate.id) / \(candidateList.size), actual candidates size: \(segment.candidatesSize)"
        )
        return
      }
      var candidateProto = Genmai_Commands_CandidateWindow.Candidate()
      candidateProto.index = UInt32(truncatingIfNeeded: i)
      fillCandidate(segment, candidate, &candidateProto)
      candidateWindowProto.candidate.append(candidateProto)
      i += 1
    }

    // Store sub_candidate_window.
    if candidateList.focusedCandidate.hasSubcandidateList() {
      fillCandidateWindow(
        segment, candidateList.focusedCandidate.subcandidateList, candidateList.focusedIndex,
        &candidateWindowProto.subCandidateWindow)
    }

    // Store usages.
    fillUsages(segment, candidateList, &candidateWindowProto)
  }

  /// Fill the CandidateList protobuf with the contents of
  /// candidate_list.  Candidates in the candidate_list are flatten
  /// even if the candidate_list contains sub-candidate lists.
  public static func fillAllCandidateWords(
    _ segment: Segment, _ candidateList: CandidateList, _ category: Genmai_Commands_Category,
    _ candidateListProto: inout Genmai_Commands_CandidateList
  ) {
    candidateListProto.category = category
    fillAllCandidateWordsInternal(
      segment, candidateList, candidateList.focusedId, &candidateListProto)
  }

  /// For debug. Fill the CandidateList protobuf with the
  /// removed_candidates_for_debug in the segment.
  public static func fillRemovedCandidates(
    _ segment: Segment, _ candidateListProto: inout Genmai_Commands_CandidateList
  ) {
    var index = 1000
    for candidate in segment.removedCandidatesForDebug {
      var candidateWordProto = Genmai_Commands_CandidateWord()
      fillCandidateWord(candidate, index, index, "", &candidateWordProto)
      candidateListProto.candidates.append(candidateWordProto)
      index += 1
    }
  }

  /// Check if the usages should be rendered on the current CandidateList status.
  public static func shouldShowUsages(_ segment: Segment, _ candList: CandidateList) -> Bool {
    // Check if the shown candidate have the usage data.
    for candidatePtr in candList.focusedPage {
      if candidatePtr.hasSubcandidateList() {
        continue
      }
      if !segment.candidate(candidatePtr.id).usageTitle.isEmpty {
        return true
      }
    }
    return false
  }

  /// Fill the usages of Candidates protobuf with the contents of candidate_list.
  public static func fillUsages(
    _ segment: Segment, _ candList: CandidateList,
    _ candidateWindowProto: inout Genmai_Commands_CandidateWindow
  ) {
    if !shouldShowUsages(segment, candList) {
      return
    }

    var usages = candidateWindowProto.usages

    // usage id -> index of the information.
    var usageidInformationMap: [Int32: Int] = [:]
    // Store usages.
    for candidatePtr in candList.focusedPage {
      if candidatePtr.hasSubcandidateList() {
        continue
      }
      let candidate = segment.candidate(candidatePtr.id)
      if candidate.usageTitle.isEmpty {
        continue
      }

      let index: Int
      if let found = usageidInformationMap[candidate.usageId] {
        index = found
        usages.information[index].candidateID.append(Int32(truncatingIfNeeded: candidatePtr.id))
      } else {
        index = usages.information.count
        var info = Genmai_Commands_Information()
        info.id = candidate.usageId
        info.title = candidate.usageTitle
        info.description_p = candidate.usageDescription
        info.candidateID.append(Int32(truncatingIfNeeded: candidatePtr.id))
        usages.information.append(info)
        usageidInformationMap[candidate.usageId] = index
      }
      if candidatePtr.id == candList.focusedId {
        usages.focusedIndex = UInt32(truncatingIfNeeded: index)
      }
    }
    candidateWindowProto.usages = usages
  }

  /// Fill the access key of Candidates protobuf with the sequence of shortcuts.
  public static func fillShortcuts(
    _ shortcuts: some StringProtocol, _ candidateWindowProto: inout Genmai_Commands_CandidateWindow
  ) {
    let bytes = Array(shortcuts.utf8)
    let numLoop = min(candidateWindowProto.candidate.count, bytes.count)
    for i in 0..<numLoop {
      candidateWindowProto.candidate[i].annotation.shortcut = String(
        decoding: bytes[i..<(i + 1)], as: UTF8.self)
    }
  }

  /// Fill the sub_label of footer_proto.  This function should be
  /// called on dev_channel and unittest.
  public static func fillSubLabel(_ footer: inout Genmai_Commands_Footer) {
    // Delete the label because sub_label will be drawn on the same
    // place for the label.
    footer.clearLabel()

    // Append third number of the version to sub_label.
    let version = Version.getGenmaiVersion()
    let versionNumbers = version.split(separator: ".", omittingEmptySubsequences: true)
    if versionNumbers.count > 2 {
      var subLabel = "build "
      subLabel.append(contentsOf: versionNumbers[2])
      footer.subLabel = subLabel
    } else {
      GenmaiLog.error("Unkonwn version format: \(version)")
    }
  }

  /// Fill the footer contents of Candidates protobuf.  If category is
  /// modified, true is returned.  Otherwise false is returned.
  @discardableResult
  public static func fillFooter(
    _ category: Genmai_Commands_Category, _ candidateWindow: inout Genmai_Commands_CandidateWindow
  ) -> Bool {
    if category != .suggestion && category != .prediction && category != .conversion {
      return false
    }

    var footer = candidateWindow.footer
    if category == .suggestion {
      // TODO(komatsu): Enable to localized the message.
      let kLabel = "Tabキーで選択"
      // TODO(komatsu): Need to check if Tab is not changed to other key binding.
      footer.label = kLabel
    } else {
      // category is commands::PREDICTION or commands::CONVERSION.
      footer.indexVisible = true
      footer.logoVisible = true

      // If the selected candidate is a user prediction history, tell the user
      // that it can be removed by Ctrl-Delete.
      if candidateWindow.hasFocusedIndex {
        for cand in candidateWindow.candidate {
          if cand.index != candidateWindow.focusedIndex {
            continue
          }
          if cand.hasAnnotation && cand.annotation.deletable {
            // TODO(noriyukit): Change the message depending on user's keymap.
            // port::IsAppleBase() is true for this port.
            let kDeleteInstruction = "control+fn+deleteで履歴から削除"
            footer.label = kDeleteInstruction
          }
          break
        }
      }
    }

    // Show the build number on the footer label for debugging when the build
    // configuration is official dev channel.
    // (CHANNEL_DEV && GOOGLE_JAPANESE_INPUT_BUILD is never defined here.)
    candidateWindow.footer = footer
    return true
  }

  /// Add a Preedit::Segment protobuf to the Preedit protobuf with key
  /// and value.  Return true iff. new segment is added to preedit.
  @discardableResult
  public static func addSegment(
    _ key: some StringProtocol, _ value: some StringProtocol, _ segmentTypeMask: UInt32,
    _ preedit: inout Genmai_Commands_Preedit
  ) -> Bool {
    // Key is always normalized as a preedit text.
    let normalizedKey = TextNormalizer.normalizeText(key)

    let normalizedValue: String
    if segmentTypeMask & SegmentType.preedit != 0 {
      normalizedValue = TextNormalizer.normalizeText(value)
    } else if segmentTypeMask & SegmentType.conversion != 0 {
      normalizedValue = String(value)
    } else {
      GenmaiLog.warning("Unknown segment type\(segmentTypeMask)")
      normalizedValue = String(value)
    }

    if normalizedValue.isEmpty {
      return false
    }

    var segment = Genmai_Commands_Preedit.Segment()
    segment.key = normalizedKey
    segment.valueLength = UInt32(truncatingIfNeeded: Util.charsLen(normalizedValue))
    segment.value = normalizedValue
    segment.annotation = .underline
    if segmentTypeMask & SegmentType.conversion != 0 && segmentTypeMask & SegmentType.focused != 0 {
      segment.annotation = .highlight
    } else {
      segment.annotation = .underline
    }
    preedit.segment.append(segment)
    return true
  }

  /// Fill the Preedit protobuf with the contents of composer as a preedit.
  public static func fillPreedit(_ composer: Composer, _ preedit: inout Genmai_Commands_Preedit) {
    let output = composer.getStringForPreedit()

    let kBaseType = SegmentType.preedit
    addSegment(output, output, kBaseType, &preedit)
    preedit.cursor = UInt32(truncatingIfNeeded: composer.getCursor())
    preedit.isToggleable = composer.isToggleable()
  }

  /// Fill the Preedit protobuf with the contents of segments as a conversion.
  public static func fillConversion(
    _ segments: Segments, _ segmentIndex: Int, _ candidateId: Int,
    _ preedit: inout Genmai_Commands_Preedit
  ) {
    let kBaseType = SegmentType.conversion
    // Cursor position in conversion state should be the end of the preedit.
    var cursor = 0
    let conversionSegments = segments.conversionSegments
    if conversionSegments.isEmpty {
      return
    }
    let focusedSegmentIndex = min(segmentIndex, conversionSegments.count - 1)

    var i = 0
    while i < conversionSegments.count {
      let segment = conversionSegments[i]
      if i == focusedSegmentIndex {
        let candidate = segment.candidate(candidateId)
        if addSegment(
          getKey(segment, candidate), candidate.value, kBaseType | SegmentType.focused, &preedit)
          && !preedit.hasHighlightedPosition
        {
          preedit.highlightedPosition = UInt32(truncatingIfNeeded: cursor)
        }
        cursor += Util.charsLen(candidate.value)
        i += getSegmentSpan(i, focusedSegmentIndex, candidate)
      } else {
        let candidate = segment.candidate(0)
        addSegment(getKey(segment, candidate), candidate.value, kBaseType, &preedit)
        cursor += Util.charsLen(candidate.value)
        i += getSegmentSpan(i, focusedSegmentIndex, candidate)
      }
    }
    preedit.cursor = UInt32(truncatingIfNeeded: cursor)
  }

  /// Fill the Result protobuf with the key and result strings
  /// for a conversion result without any text normalization.
  public static func fillConversionResultWithoutNormalization(
    _ key: String, _ result: String, _ resultProto: inout Genmai_Commands_Result
  ) {
    resultProto.type = .string
    resultProto.key = key
    resultProto.value = result
  }

  /// Fill the Result protobuf with the key and result strings
  /// normalizing the string for a conversion result.
  public static func fillConversionResult(
    _ key: some StringProtocol, _ result: String, _ resultProto: inout Genmai_Commands_Result
  ) {
    // Key should be normalized as a preedit text.
    let normalizedKey = TextNormalizer.normalizeText(key)

    // value is already normalized by converter.
    fillConversionResultWithoutNormalization(normalizedKey, result, &resultProto)
  }

  /// Fill the Result protobuf with the preedit string normalizing the
  /// string for a preedit result.
  public static func fillPreeditResult(
    _ preedit: some StringProtocol, _ resultProto: inout Genmai_Commands_Result
  ) {
    let normalizedPreedit = TextNormalizer.normalizeText(preedit)
    fillConversionResultWithoutNormalization(normalizedPreedit, normalizedPreedit, &resultProto)
  }

  /// Fill the Result protobuf with cursor offset.
  public static func fillCursorOffsetResult(
    _ cursorOffset: Int32, _ resultProto: inout Genmai_Commands_Result
  ) {
    resultProto.cursorOffset = cursorOffset
  }
}
