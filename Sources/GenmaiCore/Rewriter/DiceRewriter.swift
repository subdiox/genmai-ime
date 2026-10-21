// Port of mozc/src/rewriter/dice_rewriter.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - The C++ code draws the face with a local absl::BitGen. The random source
//   is injectable here (`init(faceGenerator:)`) so that tests can make the
//   result deterministic; the default uses the system random generator.

private let kDiceFaces = 6
private let kLastCandidateIndex = 8

private func insertCandidate(_ topFaceNumber: Int, _ insertPos: Int, _ segment: Segment) -> Bool {
  if segment.candidatesSize == 0 {
    // LOG(WARNING) << "candidates_size is 0";
    return false
  }

  let baseCandidate = segment.candidate(0)
  let offset = min(insertPos, segment.candidatesSize)

  guard let c = segment.insertCandidate(offset) else {
    // LOG(ERROR) << "cannot insert candidate at " << offset;
    return false
  }
  let triggerC = segment.candidate(offset - 1)

  c.lid = triggerC.lid
  c.rid = triggerC.rid
  c.cost = triggerC.cost
  c.value = String(topFaceNumber)
  c.contentValue = c.value
  c.key = baseCandidate.key
  c.contentKey = baseCandidate.contentKey
  c.attributes |= Attribute.noLearning
  c.attributes |= Attribute.noVariantsExpansion
  c.description = "出た目の数"
  return true
}

public final class DiceRewriter: RewriterInterface {
  /// Returns a number in [1, kDiceFaces].
  public typealias FaceGenerator = @Sendable () -> Int

  private let faceGenerator: FaceGenerator

  public init() {
    faceGenerator = { Int.random(in: 1...kDiceFaces) }
  }

  /// For tests: `faceGenerator` returns the top face in [1, 6].
  public init(faceGenerator: @escaping FaceGenerator) {
    self.faceGenerator = faceGenerator
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    if segments.conversionSegmentsSize != 1 {
      return false
    }

    let segment = segments.conversionSegment(0)
    let key = segment.key
    if key.isEmpty {
      // LOG(ERROR) << "key is empty";
      return false
    }
    if !key.bytesEqual("さいころ") {
      return false
    }

    // Insert position is the last of first page or the last of candidates
    let insertPos = min(kLastCandidateIndex, segment.candidatesSize)

    // Get a random number whose range is [1, kDiceFaces]
    // Insert the number at |insert_pos|
    return insertCandidate(faceGenerator(), insertPos, segments.mutableConversionSegment(0))
  }
}
