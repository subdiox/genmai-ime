// Port of mozc/src/rewriter/emoticon_rewriter.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - `std::sort` by cost is a (stable) Swift sort. libc++'s `std::sort` is not
//   stable for long ranges, so the relative order of emoticons with equal
//   cost may differ from C++ when the whole dictionary is expanded
//   ("かおもじ" / "かお"). Short per-key ranges (insertion sort in libc++)
//   match.
// - `absl::BitGen` is `SystemRandomNumberGenerator` (a secure generator, as
//   the C++ comment requires).

import GenmaiBase
import GenmaiProtocol

public final class EmoticonRewriter: RewriterInterface {
  private let dic: SerializedDictionary

  public init(_ tokenArrayData: DataView, _ stringArrayData: DataView) {
    dic = SerializedDictionary(tokenArray: tokenArrayData, stringArrayData: stringArrayData)
  }

  /// `std::make_from_tuple<EmoticonRewriter>(GetEmoticonRewriterData())`.
  public convenience init(_ data: (tokenArray: DataView, stringArray: DataView)) {
    self.init(data.tokenArray, data.stringArray)
  }

  // Insert Emoticon into the |segment|
  // Top |initial_insert_size| candidates are inserted from |initial_insert_pos|.
  // Remained candidates are added to the buttom.
  private static func insertCandidates(
    _ dic: SerializedDictionary, _ range: Range<Int>, _ initialInsertPos: Int,
    _ initialInsertSize: Int, _ isNoLearning: Bool, _ segment: Segment
  ) {
    if segment.candidatesSize == 0 {
      // LOG(WARNING) << "candidates_size is 0";
      return
    }

    let baseCandidate = segment.candidate(0)
    var offset = min(initialInsertPos, segment.candidatesSize)

    // Sort values by cost just in case
    var sortedValue: [SerializedDictionary.Entry] = range.map { dic[$0] }
    sortedValue.sort { $0.cost < $1.cost }

    // after sorting the values by |cost|, adjacent candidates
    // will have the same value. It is almost OK to use std::unique to
    // remove dup entries, it is not a perfect way though.
    var unique: [SerializedDictionary.Entry] = []
    unique.reserveCapacity(sortedValue.count)
    for entry in sortedValue {
      if let last = unique.last, last.value.bytesEqual(entry.value) {
        continue
      }
      unique.append(entry)
    }
    sortedValue = unique

    for i in 0..<sortedValue.count {
      let c: Candidate
      if i < initialInsertSize {
        guard let inserted = segment.insertCandidate(offset) else {
          // LOG(ERROR) << "cannot insert candidate at " << offset;
          continue
        }
        c = inserted
        offset += 1
      } else {
        c = segment.pushBackCandidate()
      }

      // TODO(taku): set an appropriate POS here.
      c.lid = sortedValue[i].lid
      c.rid = sortedValue[i].rid
      c.cost = baseCandidate.cost
      c.value = sortedValue[i].value
      c.contentValue = c.value
      c.key = baseCandidate.key
      c.contentKey = baseCandidate.contentKey
      // no full/half width normalizations
      c.attributes |= Attribute.noExtraDescription
      c.attributes |= Attribute.noVariantsExpansion
      c.attributes |= Attribute.contextSensitive
      if isNoLearning {
        c.attributes |= Attribute.noLearning
      }

      let kBaseEmoticonDescription = "顔文字"

      let description = sortedValue[i].description
      if description.isEmpty {
        c.description = kBaseEmoticonDescription
      } else {
        c.description = kBaseEmoticonDescription + " " + description
      }
      c.category = .symbol
    }
  }

  private func rewriteCandidate(_ segments: Segments) -> Bool {
    var modified = false
    for segment in segments.conversionSegments {
      let key = segment.key
      if key.isEmpty {
        // This case happens for zero query suggestion.
        continue
      }
      var isNoLearning = false
      var range: Range<Int> = dic.endIndex..<dic.endIndex
      var initialInsertSize = 0
      var initialInsertPos = 0

      // TODO(taku): Emoticon dictionary does not always include "facemark".
      // Displaying non-facemarks with "かおもじ" is not always correct.
      // We have to distinguish pure facemarks and other symbol marks.
      if key.bytesEqual("かおもじ") || key.bytesEqual("かお") {
        // When key is "かおもじ" or "かお", default candidate size should be
        // small enough. It is safe to expand all candidates at this time.
        precondition(!dic.isEmpty)
        range = dic.startIndex..<dic.endIndex
        // set large value(100) so that all candidates are pushed to the bottom
        initialInsertPos = RewriterUtil.calculateInsertPosition(segment, 100)
        initialInsertSize = dic.size
      } else if key.bytesEqual("ふくわらい") {
        // Choose one emoticon randomly from the dictionary.
        // TODO(taku): want to make it "generate" more funny emoticon.
        precondition(!dic.isEmpty)
        // use secure random not to predict the next emoticon.
        var bitgen = SystemRandomNumberGenerator()
        let begin = Int.random(in: 0..<dic.size, using: &bitgen)
        range = begin..<(begin + 1)
        initialInsertPos = RewriterUtil.calculateInsertPosition(segment, 4)
        initialInsertSize = 1
        isNoLearning = true  // do not learn this candidate.
      } else {
        range = dic.equalRange(key)
        if !range.isEmpty {
          initialInsertPos = RewriterUtil.calculateInsertPosition(segment, 6)
          initialInsertSize = range.count
        }
      }

      if range.isEmpty {
        continue
      }

      EmoticonRewriter.insertCandidates(
        dic, range, initialInsertPos, initialInsertSize, isNoLearning, segment)
      modified = true
    }

    return modified
  }

  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType {
    if request.request().mixedConversion {
      return .all
    }
    return .conversion
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    if !request.config().useEmoticonConversion {
      // MOZC_VLOG(2) << "no use_emoticon_conversion";
      return false
    }
    return rewriteCandidate(segments)
  }
}
