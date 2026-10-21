// Port of mozc/src/rewriter/zipcode_rewriter.{h,cc} (3.35.6354).

public final class ZipcodeRewriter: RewriterInterface {
  private let posMatcher: PosMatcher

  public init(_ posMatcher: PosMatcher) {
    self.posMatcher = posMatcher
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    if segments.conversionSegmentsSize != 1 {
      return false
    }

    let segment = segments.conversionSegment(0)
    let key = segment.key
    if key.isEmpty {
      // LOG(ERROR) << "Key is empty";
      return false
    }

    guard let (zipcode, address, insertPos) = getZipcodeCandidatePositions(segment) else {
      return false
    }

    return insertCandidate(
      insertPos, zipcode, address, request, segments.mutableConversionSegment(0))
  }

  private func getZipcodeCandidatePositions(_ seg: Segment)
    -> (zipcode: String, address: String, insertPos: Int)?
  {
    for i in 0..<seg.candidatesSize {
      let c = seg.candidate(i)
      if !posMatcher.isZipcode(c.lid) || !posMatcher.isZipcode(c.rid) {
        continue
      }
      return (c.contentKey, c.contentValue, i + 1)
    }
    return nil
  }

  private func insertCandidate(
    _ insertPos: Int, _ zipcode: String, _ address: String, _ request: ConversionRequest,
    _ segment: Segment
  ) -> Bool {
    if segment.candidatesSize == 0 {
      // LOG(WARNING) << "candidates_size is 0";
      return false
    }

    var isFullWidth = true
    switch request.config().spaceCharacterForm {
    case .fundamentalInputMode:
      isFullWidth = true
    case .fundamentalFullWidth:
      isFullWidth = true
    case .fundamentalHalfWidth:
      isFullWidth = false
    // (The C++ default branch for unknown values is unreachable: the Swift
    // proto2 enum has no unrecognized case.)
    }

    let space = isFullWidth ? "　" : " "  // "　" (full-width space)
    let value = zipcode + space + address

    let offset = min(insertPos, segment.candidatesSize)
    guard let candidate = segment.insertCandidate(offset) else {
      // LOG(ERROR) << "cannot insert candidate at " << offset;
      return false
    }
    assert(offset >= 1)
    let baseCandidate = segment.candidate(offset - 1)
    candidate.lid = posMatcher.getZipcodeId()
    candidate.rid = posMatcher.getZipcodeId()
    candidate.cost = baseCandidate.cost
    candidate.value = value
    candidate.contentValue = value
    candidate.key = zipcode
    candidate.contentKey = zipcode
    candidate.attributes |= Attribute.noVariantsExpansion
    candidate.attributes |= Attribute.noLearning
    candidate.description = "郵便番号と住所"
    return true
  }
}
