// Port of mozc/src/rewriter/correction_rewriter.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - engine::Modules is not ported yet. The rewriter only uses
//   `modules.GetSupplementalModel().GetReadingAlignment(...)`, abstracted by
//   the `ReadingAlignmentSupplementalModel` protocol below (the engine's
//   SupplementalModelInterface should refine it). The initializer takes that
//   model instead of the modules; `nil` behaves like the
//   SupplementalModelInterface default (no alignment available).
// - The three serialized arrays are passed as `DataView`s
//   (`DataManager.getReadingCorrectionData()`).

import GenmaiBase
import GenmaiProtocol

/// The subset of engine::SupplementalModelInterface used by
/// CorrectionRewriter.
public protocol ReadingAlignmentSupplementalModel: AnyObject {
  /// Returns character-by-mora reading to surface alignment.
  /// {東,とう},{京,きょう} = GetReadingAlignment("東京", "とうきょう")
  /// Returns empty list when no alignment is available.
  func getReadingAlignment(_ surface: String, _ reading: String) -> [(String, String)]
}

public final class CorrectionRewriter: RewriterInterface {
  private struct ReadingCorrectionItem {
    // ex. (value, error, correction) = ("雰囲気", "ふいんき", "ふんいき")
    var value: String
    var error: String
    var correction: String
  }

  private var valueArray = SerializedStringArray()
  private var errorArray = SerializedStringArray()
  private var correctionArray = SerializedStringArray()
  private let supplementalModel: (any ReadingAlignmentSupplementalModel)?

  public init(
    supplementalModel: (any ReadingAlignmentSupplementalModel)?,
    valueArrayData: DataView, errorArrayData: DataView, correctionArrayData: DataView
  ) {
    self.supplementalModel = supplementalModel
    valueArray.set(valueArrayData.bytes, owner: valueArrayData.owner)
    errorArray.set(errorArrayData.bytes, owner: errorArrayData.owner)
    correctionArray.set(correctionArrayData.bytes, owner: correctionArrayData.owner)
    assert(valueArray.size == errorArray.size)
    assert(valueArray.size == correctionArray.size)
  }

  /// Convenience for `make_unique_from_tuples<CorrectionRewriter>(modules,
  /// data_manager.GetReadingCorrectionData())` in rewriter.cc.
  public convenience init(
    supplementalModel: (any ReadingAlignmentSupplementalModel)?, dataManager: DataManager
  ) {
    let data = dataManager.getReadingCorrectionData()
    self.init(
      supplementalModel: supplementalModel, valueArrayData: data.valueArray,
      errorArrayData: data.errorArray, correctionArrayData: data.correctionArray)
  }

  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType { .all }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    if !request.config().useSpellingCorrection {
      return false
    }

    var modified = false
    var results: [ReadingCorrectionItem] = []

    let capability = request.request().displayValueCapability

    for segment in segments.conversionSegments {
      if segment.candidatesSize == 0 {
        continue
      }

      for j in 0..<segment.candidatesSize {
        // Check if the existing candidate is a corrected candidate.
        // In this case, update the candidate description.
        let candidate = segment.candidate(j)

        // Handles the spelling correction defined in the system dictionary.
        // mostly they are Katakana to Katakana correction.
        if candidate.attributes & Attribute.spellingCorrection != 0 {
          // Sets empty correction item.
          setCandidate(
            ReadingCorrectionItem(value: "", error: "", correction: ""), capability,
            segment.mutableCandidate(j))
          continue
        }

        if !lookupCorrection(candidate.contentKey, candidate.contentValue, &results) {
          continue
        }

        precondition(results.count > 0)
        // results.size() should be 1, but we don't check it here.
        setCandidate(results[0], capability, segment.mutableCandidate(j))
        modified = true
      }

      // Add correction candidates that have the same key as the top candidate.
      //
      // TODO(taku): Want to calculate the position more accurately by
      // taking the emission cost into consideration.
      // The cost of mis-reading candidate can simply be obtained by adding
      // some constant penalty to the original emission cost.
      //
      // TODO(taku): In order to provide all miss reading corrections
      // defined in the tsv file, we want to add miss-read entries to
      // the system dictionary.
      let kInsertPosition = min(3, segment.candidatesSize)
      let topCandidate = segment.candidate(0)
      if !lookupCorrection(topCandidate.contentKey, "", &results) {
        continue
      }
      for result in results {
        let newCandidate = topCandidate.copy()
        newCandidate.key = result.error + topCandidate.functionalKey
        newCandidate.value = result.value + topCandidate.functionalValue
        newCandidate.innerSegmentBoundary = []
        setCandidate(result, capability, newCandidate)

        segment.insertCandidate(kInsertPosition, newCandidate)
        modified = true
      }
    }

    return modified
  }

  // Returns "アボ*カ*ド" from {content_key=あぼがど, content_value=アボカド}
  // It extracts the minimum span where the reading is different.
  private func getDisplayValueForKatakana(_ candidate: Candidate) -> String? {
    nil
  }

  // Returns "巣(そう)窟" from {"巣窟", "すくつ", "そうくつ"}
  // It extracts the minimum span where the reading is different.
  private func getDisplayValueForReadingCorrection(_ item: ReadingCorrectionItem) -> String? {
    let errorAlignment = supplementalModel?.getReadingAlignment(item.value, item.error) ?? []
    let correctionAlignment =
      supplementalModel?.getReadingAlignment(item.value, item.correction) ?? []

    func fallbackResult() -> String {
      item.value + "(" + item.correction + ")"
    }

    // reading aligner is not available.
    // TODO(taku): Consider using fallback result when reading aligner is not
    // available.
    if errorAlignment.isEmpty || correctionAlignment.isEmpty {
      return nil
    }

    if errorAlignment.count != correctionAlignment.count {
      return fallbackResult()
    }

    // The maximum range where the per-character-readings are different.
    var diffStart = errorAlignment.count
    var diffEnd = -1
    for i in 0..<errorAlignment.count
    where !errorAlignment[i].1.bytesEqual(correctionAlignment[i].1) {
      diffStart = min(diffStart, i)
      diffEnd = i
    }

    if diffEnd == -1 {
      return fallbackResult()
    }

    var result = ""

    // [0, diff_start) have the same value.
    for i in 0..<diffStart {
      result += correctionAlignment[i].0
    }

    do {
      // [diff_start, diff_end] are different.
      var diffValue = ""
      var diffKey = ""
      for i in diffStart...diffEnd {
        diffValue += correctionAlignment[i].0
        diffKey += correctionAlignment[i].1
      }
      result += diffValue + "(" + diffKey + ")"
    }

    // (diff_end, last) have the same value.
    for i in (diffEnd + 1)..<correctionAlignment.count {
      result += correctionAlignment[i].0
    }

    return result
  }

  // Sets `candidate` fields from `item`.
  private func setCandidate(
    _ item: ReadingCorrectionItem,
    _ capability: Genmai_Commands_Request.DisplayValueCapability, _ candidate: Candidate
  ) {
    candidate.attributes |= Attribute.spellingCorrection

    // Assigns display_value when the client supports it.
    if capability == .plainText {
      let displayValue: String?
      if !item.correction.isEmpty {
        displayValue = getDisplayValueForReadingCorrection(item)
      } else {
        displayValue = getDisplayValueForKatakana(candidate)
      }

      if let displayValue {
        candidate.displayValue = displayValue
        candidate.description = ""
        return
      }
    }

    // The legacy description-based annotation.
    let kDidYouMean = "もしかして"
    candidate.prefix = "→ "
    if item.correction.isEmpty {
      candidate.description = "<" + kDidYouMean + ">"
    } else {
      candidate.description = "<" + kDidYouMean + ": " + item.correction + ">"
    }
  }

  // Looks up corrections with key and value. Return true if at least
  // one correction is found in the internal dictionary.
  // If `value` is empty, looks up corrections only using the key.
  // The matched results are saved in `results`.
  // Return false if `results` is empty.
  private func lookupCorrection(
    _ key: String, _ value: String, _ results: inout [ReadingCorrectionItem]
  ) -> Bool {
    results.removeAll()

    // std::equal_range(error_array_.begin(), error_array_.end(), key)
    let first = errorArray.lowerBound(key)
    let last = errorArray.upperBound(key)
    for index in first..<max(first, last) {
      let v = valueArray[index]
      if value.isEmpty || value.bytesEqual(v) {
        results.append(
          ReadingCorrectionItem(
            value: v, error: errorArray[index], correction: correctionArray[index]))
      }
    }
    return !results.isEmpty
  }
}
