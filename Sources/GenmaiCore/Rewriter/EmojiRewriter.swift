// Port of mozc/src/rewriter/emoji_rewriter.{h,cc} (3.35.6354).
//
// EmojiRewriter:
// Converts HIRAGANA strings to emoji characters, if they are names of emojis.
//
// Deviations from C++:
// - `absl::Span<const EmojiData>` is `EmojiDataArray` (a view over the token
//   array) and sub-ranges are `Range<Int>`.
// - `absl::c_sort` of (value, description) string_view pairs compares the
//   UTF-8 bytes lexicographically, as in C++.

import GenmaiBase
import GenmaiProtocol

/// EmojiRewriter class adds UTF-8 emoji characters in converted candidates of
/// given segments, if each segment has a special key to convert.
/// Added emoji characters are chosen by Yomi (reading of it) registered in
/// a dictionary. If a segment has a key "えもじ", all emoji characters are
/// pushed to its candidate list.
public final class EmojiRewriter: RewriterInterface {
  private static let kEmoji = "絵文字"
  private static let kEmojiKey = "えもじ"
  // Where to insert emoji candidate by default.
  private static let kDefaultInsertPos = 6

  private let tokens: EmojiDataArray
  private var stringArray = SerializedStringArray()

  public init(_ tokenArrayData: DataView, _ stringArrayData: DataView) {
    tokens = EmojiDataArray(tokenArrayData)
    assert(SerializedStringArray.verifyData(stringArrayData))
    stringArray.set(stringArrayData)
  }

  /// `std::make_from_tuple<EmojiRewriter>(GetEmojiRewriterData())`.
  public convenience init(_ data: (tokenArray: DataView, stringArray: DataView)) {
    self.init(data.tokenArray, data.stringArray)
  }

  // MARK: - Helpers (anonymous namespace)

  private static func createCandidate(
    _ key: String, _ value: String, _ description: String, _ cost: Int32
  ) -> Candidate {
    let candidate = Candidate()
    // Fill 0 (BOS/EOS) pos code intentionally.
    candidate.lid = 0
    candidate.rid = 0
    candidate.cost = cost
    candidate.value = value
    candidate.contentValue = value
    candidate.key = key
    candidate.contentKey = key
    if description.isEmpty {
      candidate.description = kEmoji
    } else {
      candidate.description = kEmoji + " " + description
    }
    candidate.attributes |= Attribute.noVariantsExpansion
    candidate.attributes |= Attribute.contextSensitive
    candidate.category = .symbol

    return candidate
  }

  private static func getEmojiCost(_ segment: Segment) -> Int32 {
    // Use the first candidate's cost (or 0 if not available).
    segment.candidatesSize == 0 ? 0 : segment.candidate(0).cost
  }

  /// List of <emoji value, emoji description>.
  private typealias EmojiEntryList = [(value: String, description: String)]

  private static func gatherAllEmojiData(
    _ emojiData: EmojiDataArray, _ stringArray: SerializedStringArray
  ) -> EmojiEntryList {
    var utf8EmojiList: EmojiEntryList = []
    for token in emojiData {
      let utf8Emoji = stringArray[Int(token.emojiIndex)]
      if utf8Emoji.isEmpty {
        continue
      }
      utf8EmojiList.append((utf8Emoji, stringArray[Int(token.descriptionUtf8Index)]))
    }

    // absl::c_sort on std::pair<string_view, string_view> (bytewise).
    utf8EmojiList.sort { lhs, rhs in
      let c = lhs.value.compareBytes(rhs.value)
      if c != 0 { return c < 0 }
      return lhs.description.bytesLess(rhs.description)
    }
    return utf8EmojiList
  }

  private static func createAllEmojiData(
    _ key: String, _ cost: Int32, _ utf8EmojiList: EmojiEntryList
  ) -> [Candidate] {
    var candidates: [Candidate] = []
    candidates.reserveCapacity(utf8EmojiList.count)
    for (value, description) in utf8EmojiList {
      candidates.append(createCandidate(key, value, description, cost))
    }
    return candidates
  }

  private static func createEmojiData(
    _ key: String, _ cost: Int32, _ tokens: EmojiDataArray, _ range: Range<Int>,
    _ stringArray: SerializedStringArray
  ) -> [Candidate] {
    var candidates: [Candidate] = []
    candidates.reserveCapacity(range.count)
    for i in range {
      let token = tokens[i]
      let utf8Emoji = stringArray[Int(token.emojiIndex)]
      if utf8Emoji.isEmpty {
        continue
      }
      candidates.append(
        createCandidate(key, utf8Emoji, stringArray[Int(token.descriptionUtf8Index)], cost))
    }
    return candidates
  }

  // MARK: - EmojiRewriter

  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType {
    // The capability of the EmojiRewriter is up to the client's request.
    // Note that the bit representation of RewriterInterface::CapabilityType
    // and Request::RewriterCapability should exactly same, so it is ok
    // to just return the value as is.
    Rewriter.CapabilityType(rawValue: Int(request.request().emojiRewriterCapability))
  }

  /// Returns true if emoji candidates are added.  When user settings are set
  /// not to use EmojiRewriter, does nothing other than returning false.
  /// Otherwise, main process are done in ReriteCandidates().
  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    if !request.config().useEmojiConversion {
      // MOZC_VLOG(2) << "no use_emoji_conversion";
      return false
    }

    return rewriteCandidates(segments)
  }

  /// Returns true if the given candidate includes emoji characters.
  /// TODO(peria, hidehiko): Unify this checker and IsEmojiEntry defined in
  ///     predictor/user_history_predictor.cc.  If you make similar functions
  ///     before the merging in case, put a same note to avoid twisted
  ///     dependency.
  public static func isEmojiCandidate(_ candidate: Candidate) -> Bool {
    // absl::StrContains (bytewise).
    let haystack = Array(candidate.description.utf8)
    let needle = Array(kEmoji.utf8)
    if needle.count > haystack.count { return false }
    for start in 0...(haystack.count - needle.count)
    where haystack[start..<(start + needle.count)].elementsEqual(needle) {
      return true
    }
    return false
  }

  private func lookUpToken(_ key: String) -> Range<Int> {
    // Search string array for key (std::equal_range, bytewise).
    let keyBytes = Array(key.utf8)
    // lower_bound
    var lo = tokens.startIndex
    var count = tokens.count
    while count > 0 {
      let half = count / 2
      if stringArray.compare(at: Int(tokens[lo + half].keyIndex), bytes: keyBytes) < 0 {
        lo += half + 1
        count -= half + 1
      } else {
        count = half
      }
    }
    // upper_bound
    var hi = lo
    count = tokens.endIndex - lo
    while count > 0 {
      let half = count / 2
      if stringArray.compare(at: Int(tokens[hi + half].keyIndex), bytes: keyBytes) > 0 {
        count = half
      } else {
        hi += half + 1
        count -= half + 1
      }
    }
    return lo..<hi
  }

  /// Adds emoji candidates on each segment of given segments, if it has a
  /// specific string as a key based on a dictionary.  If a segment's value is
  /// "えもじ", adds all emoji candidates.
  /// Returns true if emoji candidates are added in any segment.
  private func rewriteCandidates(_ segments: Segments) -> Bool {
    var modified = false

    func insertCandidates(_ cands: [Candidate], _ segment: Segment) -> Bool {
      if cands.isEmpty {
        return false
      }
      let insertPosition = RewriterUtil.calculateInsertPosition(
        segment, EmojiRewriter.kDefaultInsertPos)
      segment.insertCandidates(insertPosition, cands)
      return true
    }

    for segment in segments.conversionSegments {
      let reading = JapaneseUtil.fullWidthAsciiToHalfWidthAscii(segment.key)
      if reading.isEmpty {
        continue
      }

      if reading.bytesEqual(EmojiRewriter.kEmojiKey) {
        // When key is "えもじ", we expect to expand all Emoji characters.
        let utf8EmojiList = EmojiRewriter.gatherAllEmojiData(tokens, stringArray)
        if utf8EmojiList.isEmpty {
          continue
        }

        let cost = EmojiRewriter.getEmojiCost(segment)
        let candidates = EmojiRewriter.createAllEmojiData(reading, cost, utf8EmojiList)
        modified = insertCandidates(candidates, segment) || modified
        continue
      }

      let range = lookUpToken(reading)
      if range.isEmpty {
        // MOZC_VLOG(2) << "Token not found: " << reading;
        continue
      }

      let cost = EmojiRewriter.getEmojiCost(segment)
      let candidates = EmojiRewriter.createEmojiData(reading, cost, tokens, range, stringArray)
      modified = insertCandidates(candidates, segment) || modified
    }
    return modified
  }
}
