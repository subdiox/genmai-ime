// Port of mozc/src/rewriter/user_dictionary_rewriter.{h,cc} (3.35.6354).

/// A special rewriter that tweaks the ranking of user dictionary candidates.
public final class UserDictionaryRewriter: RewriterInterface {
  public init() {}

  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType {
    [.conversion, .prediction]
  }

  // User-dictionary candidates are not always placed at the top.
  // Since user expects that user-dictionary candidates may appear
  // on the top, we simply move user-dictionary-candidate just
  // "after" the top candidate.
  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    var modified = false
    for segment in segments.conversionSegments {
      // final destination of the user dictionary candidate.
      var moveToStart = 1

      var moveFrom = 2
      while moveFrom < segment.candidatesSize {
        defer { moveFrom += 1 }
        if segment.candidate(moveFrom).attributes & Attribute.userDictionary == 0 {
          continue
        }

        // find the final destination of user dictionary
        // from [move_to_start .. move_from).
        var moveTo = -1
        var j = moveToStart
        while j < moveFrom {
          if segment.candidate(j).attributes & Attribute.userDictionary == 0 {
            moveTo = j
            break
          }
          j += 1
        }

        // if move_to is not nil, move the candidate.
        if moveTo == -1 {
          moveToStart = moveFrom + 1
        } else {
          segment.moveCandidate(moveFrom, moveTo)
          modified = true
          moveToStart = moveTo + 1
        }
      }
    }

    return modified
  }
}
