// Port of mozc/src/rewriter/version_rewriter.{h,cc} (3.35.6354).

import GenmaiBase

/// `kVersionRewriterVersionPrefix` (base/const.h): kProductPrefix "-" for the
/// OSS (MOZC_BUILD) branding.
private let kVersionRewriterVersionPrefix = GenmaiConst.kVersionRewriterVersionPrefix

private let kKeyCandList: [(key: String, baseCandidate: String)] = [
  ("う゛ぁーじょん", "ヴァージョン"),
  ("ゔぁーじょん", "ヴァージョン"),
  ("ばーじょん", "バージョン"),
  ("Version", "Version"),
]

public final class VersionRewriter: RewriterInterface {
  private struct VersionEntry {
    var baseCandidate: String
    var output: String
    var rank: Int
  }

  // Keyed by the UTF-8 bytes so that the lookup is bytewise as in C++ (Swift
  // String equality is canonical equivalence).
  private var entries: [[UInt8]: VersionEntry] = [:]

  public init(_ dataVersion: String) {
    let versionString = kVersionRewriterVersionPrefix + Version.getProductVersion() + "+" + dataVersion
    for (key, baseCandidate) in kKeyCandList where entries[Array(key.utf8)] == nil {
      entries[Array(key.utf8)] = VersionEntry(baseCandidate: baseCandidate, output: versionString, rank: 9)
    }
  }

  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType {
    if request.request().mixedConversion {
      return .all
    }
    return .conversion
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    var result = false
    for segment in segments.conversionSegments {
      guard let ent = entries[Array(segment.key.utf8)] else { continue }
      for j in 0..<segment.candidatesSize {
        let c = segment.candidate(j)
        if c.value.bytesEqual(ent.baseCandidate) {
          if let newCand = segment.insertCandidate(min(segment.candidatesSize, ent.rank)) {
            newCand.lid = c.lid
            newCand.rid = c.rid
            newCand.cost = c.cost
            newCand.value = ent.output
            newCand.contentValue = ent.output
            newCand.key = segment.key
            newCand.contentKey = segment.key
            // we don't learn version
            newCand.attributes |= Attribute.noLearning
            result = true
          }
          break
        }
      }
    }
    return result
  }
}
