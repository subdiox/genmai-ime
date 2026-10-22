// Aligns a whole-sentence AI conversion with Mozc's segments and merges it into them (not part of Mozc).
//
// Reading alignment: the AI text is cut into units: kana / symbols / punctuation ("fixed" characters, which must
// equal one reading character after width folding and katakana → hiragana) and maximal runs of other characters
// (kanji, 々, ヶ, digits, Latin letters: "free" runs, which read as one or more reading characters). All possible
// alignments are enumerated with a forward / backward reachability DP, which gives the AI text positions possible
// at every Mozc segment boundary. A second DP picks one cut per boundary such that every piece reads as its
// segment key, preferring Mozc's segmentation, pieces that are Mozc candidates of the segment, and kana matched
// early. A boundary that cannot be cut (it falls inside a kanji run) is dropped, i.e. the adjacent Mozc segments
// are merged (Mozc re-converts the merged segment with `resizeSegments`, as its own
// `Converter::ResizeSegmentsByResult` does for supplemental-model results). If the text cannot be aligned at
// all, it becomes one segment covering the whole reading.
//
// Positions are Unicode scalar counts, like Mozc's `Segment::key_len()` / `Util::CharsLen`.

import Foundation
import GenmaiCore

public enum AIConversionAligner {
  /// Map of resolved boundaries: reading position → AI text position (both in Unicode scalars).
  public typealias Boundaries = [Int: Int]

  /// The fixed character a scalar must match, or nil if it belongs to a free run.
  static func fixedKey(_ s: Unicode.Scalar) -> Unicode.Scalar? {
    let v = s.value
    switch v {
    case 0x3041...0x3096, 0x309D, 0x309E:  // hiragana, ゝゞ
      return s
    case 0x30F5, 0x30F6:  // ヵ ヶ (read か / が / こ)
      return nil
    case 0x30A1...0x30F4, 0x30FD, 0x30FE:  // katakana → hiragana
      return Unicode.Scalar(v - 0x60)
    case 0x30FC, 0xFF70:  // ー, ｰ
      return Unicode.Scalar(0x30FC)
    default:
      break
    }
    if s.properties.isAlphabetic || s.properties.numericType != nil
      || s.properties.generalCategory == .nonspacingMark || s.properties.isVariationSelector
    {
      // Kanji, 々, 〆, digits, Latin / Greek letters, marks: free.
      return nil
    }
    // Symbols and punctuation: fold full-width / half-width forms.
    if let folded = String(s).applyingTransform(.fullwidthToHalfwidth, reverse: false)?.unicodeScalars.first,
      String(s).applyingTransform(.fullwidthToHalfwidth, reverse: false)?.unicodeScalars.count == 1
    {
      if (0xFF61...0xFF9F).contains(folded.value) {
        return s  // half-width katakana range: keep as is
      }
      return folded
    }
    return s
  }

  /// The reading character in the same normal form as `fixedKey` (reading characters are always "fixed").
  static func readingKey(_ s: Unicode.Scalar) -> Unicode.Scalar {
    if let k = fixedKey(s) {
      return k
    }
    // Digits / letters in the reading: fold width so that "１" matches "1".
    if let folded = String(s).applyingTransform(.fullwidthToHalfwidth, reverse: false)?.unicodeScalars,
      folded.count == 1, let f = folded.first
    {
      return f
    }
    return s
  }

  struct Unit {
    var start: Int
    var end: Int
    /// nil for a free run.
    var fixed: Unicode.Scalar?
  }

  static func units(_ surface: [Unicode.Scalar]) -> [Unit] {
    var units: [Unit] = []
    for (i, s) in surface.enumerated() {
      if let f = fixedKey(s) {
        units.append(Unit(start: i, end: i + 1, fixed: f))
      } else if let last = units.last, last.fixed == nil, last.end == i {
        units[units.count - 1].end = i + 1
      } else {
        units.append(Unit(start: i, end: i + 1, fixed: nil))
      }
    }
    return units
  }

  /// Maximum number of reading characters a free run of `length` characters may read as.
  static func maxReading(_ length: Int) -> Int { max(8, 8 * length) }

  /// forward[k][j]: the first k units can read exactly reading[0..<j].
  static func forwardTable(_ us: [Unit], _ r: [Unicode.Scalar]) -> [[Bool]] {
    let n = r.count
    var forward = [[Bool]](repeating: [Bool](repeating: false, count: n + 1), count: us.count + 1)
    forward[0][0] = true
    for k in 0..<us.count {
      let u = us[k]
      for j in 0...n where forward[k][j] {
        if let f = u.fixed {
          if j < n && r[j] == f {
            forward[k + 1][j + 1] = true
          }
        } else {
          let maxLen = min(maxReading(u.end - u.start), n - j)
          if maxLen >= 1 {
            for len in 1...maxLen {
              forward[k + 1][j + len] = true
            }
          }
        }
      }
    }
    return forward
  }

  /// True if `surface` can read as `reading` (already normalized with `readingKey`).
  static func aligns(_ surface: ArraySlice<Unicode.Scalar>, _ reading: ArraySlice<Unicode.Scalar>) -> Bool {
    if surface.isEmpty || reading.isEmpty {
      return surface.isEmpty && reading.isEmpty
    }
    let us = units(Array(surface))
    return forwardTable(us, Array(reading))[us.count][reading.count]
  }

  /// For every reading position j, the AI text positions that are a unit boundary at reading position j in at
  /// least one complete alignment (ascending). nil if `surface` cannot read as `reading` at all.
  public static func positions(surface: String, reading: String) -> [[Int]]? {
    let s = Array(surface.unicodeScalars)
    let r = Array(reading.unicodeScalars).map(readingKey)
    let n = r.count
    if s.isEmpty || n == 0 {
      return nil
    }
    let us = units(s)
    let m = us.count
    let forward = forwardTable(us, r)
    if !forward[m][n] {
      return nil
    }
    // backward[k][j]: units k..<m can read exactly reading[j..<n].
    var backward = [[Bool]](repeating: [Bool](repeating: false, count: n + 1), count: m + 1)
    backward[m][n] = true
    for k in stride(from: m - 1, through: 0, by: -1) {
      let u = us[k]
      for j in 0...n {
        if let f = u.fixed {
          backward[k][j] = j < n && r[j] == f && backward[k + 1][j + 1]
        } else {
          let maxLen = min(maxReading(u.end - u.start), n - j)
          if maxLen >= 1 {
            for len in 1...maxLen where backward[k + 1][j + len] {
              backward[k][j] = true
              break
            }
          }
        }
      }
    }
    var result = [[Int]](repeating: [], count: n + 1)
    for k in 0...m {
      let sp = k < m ? us[k].start : s.count
      for j in 0...n where forward[k][j] && backward[k][j] {
        result[j].append(sp)
      }
    }
    return result
  }

  /// The boundaries every alignment agrees on: reading position → AI text position. nil if no alignment.
  public static func align(surface: String, reading: String) -> Boundaries? {
    guard let positions = positions(surface: surface, reading: reading) else {
      return nil
    }
    var result: Boundaries = [:]
    for (j, ps) in positions.enumerated() where ps.count == 1 {
      result[j] = ps[0]
    }
    return result
  }

  /// A group of consecutive Mozc segments and the AI text for them.
  public struct Group: Equatable, Sendable {
    public var segments: Range<Int>
    public var text: String
    public init(segments: Range<Int>, text: String) {
      self.segments = segments
      self.text = text
    }
  }

  /// Groups the Mozc segments with keys `segmentKeys` and cuts `surface` accordingly, so that the text of every
  /// group reads as the group's key. Among the possible cuts it prefers (1) keeping Mozc's segments, (2) pieces
  /// that are candidates Mozc has for that segment (`candidates[i]`), (3) matching kana as early as possible
  /// ("今日は|早めに", not "今日|は早めに"). Groups span at most `maxMerge` segments; if no such grouping exists
  /// the whole text becomes one group. Returns nil if `surface` cannot read as the reading at all.
  public static func plan(
    surface: String, segmentKeys: [String], candidates: [[String]] = [], maxMerge: Int = 8,
    allowMerge: Bool = true
  ) -> [Group]? {
    let reading = segmentKeys.joined()
    guard let positions = positions(surface: surface, reading: reading) else {
      return nil
    }
    let s = Array(surface.unicodeScalars)
    let r = Array(reading.unicodeScalars).map(readingKey)
    let n = segmentKeys.count
    var bounds = [0]
    var bound = 0
    for key in segmentKeys {
      bound += key.unicodeScalars.count
      bounds.append(bound)
    }
    // Possible AI text positions at each Mozc boundary.
    var nodes: [[Int]] = (0...n).map { positions[bounds[$0]] }
    nodes[0] = [0]
    nodes[n] = [s.count]

    struct Best {
      var score: Int
      var tie: Int
      var previous: (Int, Int)?
    }
    var best: [[Int: Best]] = Array(repeating: [:], count: n + 1)
    best[0][0] = Best(score: 0, tie: 0, previous: nil)
    for i in 0..<n {
      for (sp, b) in best[i] {
        let lastJ = allowMerge ? min(n, i + maxMerge) : i + 1
        for j in (i + 1)...lastJ {
          for tp in nodes[j] where tp > sp {
            guard aligns(s[sp..<tp], r[bounds[i]..<bounds[j]]) else { continue }
            var w = 0
            if j == i + 1 {
              w += 1
              let piece = String(String.UnicodeScalarView(s[sp..<tp]))
              if i < candidates.count && candidates[i].contains(piece) {
                w += 3
              }
            }
            let candidate = Best(score: b.score + w, tie: b.tie + tp, previous: (i, sp))
            if let current = best[j][tp],
              (current.score, current.tie) >= (candidate.score, candidate.tie)
            {
              continue
            }
            best[j][tp] = candidate
          }
        }
      }
    }
    guard best[n][s.count] != nil else {
      return allowMerge ? [Group(segments: 0..<n, text: surface)] : nil
    }
    var groups: [Group] = []
    var node = (n, s.count)
    while let previous = best[node.0][node.1]?.previous {
      groups.append(
        Group(
          segments: previous.0..<node.0, text: String(String.UnicodeScalarView(s[previous.1..<node.1]))))
      node = previous
    }
    return groups.reversed()
  }

  /// Cuts `surface` into pieces that read as the consecutive reading parts `readingLengths` (scalar lengths of
  /// `reading`), preferring pieces in `candidates`. Returns nil if that is not possible.
  public static func split(
    surface: String, readingLengths: [Int], reading: String, candidates: [[String]] = []
  ) -> [String]? {
    var keys: [String] = []
    var rest = Substring.UnicodeScalarView(reading.unicodeScalars)
    for len in readingLengths {
      guard rest.count >= len else { return nil }
      keys.append(String(String.UnicodeScalarView(rest.prefix(len))))
      rest = rest.dropFirst(len)
    }
    guard rest.isEmpty,
      let groups = plan(surface: surface, segmentKeys: keys, candidates: candidates, allowMerge: false)
    else {
      return nil
    }
    return groups.map(\.text)
  }
}

/// Merges AI conversions into Mozc's conversion segments.
public enum AIConversionMerger {
  /// The description shown in the candidate window for candidates the AI put there.
  public static let description = "AI"

  public struct Outcome: Equatable, Sendable {
    /// The AI top-1 is now the top of the conversion (it differed from Mozc's).
    public var replacedTop = false
    /// Segments were merged / resized to fit the AI text.
    public var resized = false
    /// The AI text could not be aligned and became one segment.
    public var wholeSentence = false
    /// Number of AI alternatives added (n-best 2...).
    public var alternatives = 0
    /// Segments where Mozc's top was kept because the user rejected the AI's text for them before.
    public var keptLearned = 0
    /// AI pieces not used because they would replace a word of the user dictionary (the word stays on top).
    public var keptUserWords = 0
    /// The segments that got the AI's text on top (key → value), for `AIConversionHook` to see whether the user
    /// commits them or chooses something else.
    public var aiSegments: [Piece] = []
    public init() {}
  }

  public struct Piece: Equatable, Hashable, Sendable {
    public var key: String
    public var value: String
    public init(key: String, value: String) {
      self.key = key
      self.value = value
    }
  }

  /// Applies `texts` (AI n-best, best first) to `segments` (just converted by Mozc with `request`).
  /// `converter` is the Mozc converter (used to resize segments).
  @discardableResult
  public static func apply(
    _ texts: [String], to segments: Segments, request: ConversionRequest, converter: any ConverterInterface,
    maxCandidates: Int, rejected: (Piece) -> Bool = { _ in false }
  ) -> Outcome {
    var outcome = Outcome()
    guard let aiTop = texts.first, !aiTop.isEmpty, maxCandidates >= 1 else {
      return outcome
    }
    let size = segments.conversionSegmentsSize
    guard size > 0 else {
      return outcome
    }
    for i in 0..<size {
      let segment = segments.conversionSegment(i)
      if segment.candidatesSize == 0 || segment.candidate(0).effectiveConvertedSegmentCount > 1 {
        // Multi-segment candidates (not used on desktop): leave Mozc's result alone.
        return outcome
      }
    }
    let keys = (0..<size).map { segments.conversionSegment($0).key }
    let tops = (0..<size).map { segments.conversionSegment($0).candidate(0).value }
    let engineTop = tops.joined()

    // 1. The top: group segments so that the AI text can be cut at the group boundaries.
    var groups: [AIConversionAligner.Group]
    var aiGroups: [Bool]
    if aiTop == engineTop {
      groups = (0..<size).map { AIConversionAligner.Group(segments: $0..<($0 + 1), text: tops[$0]) }
      aiGroups = Array(repeating: false, count: size)
    } else if let planned = AIConversionAligner.plan(
      surface: aiTop, segmentKeys: keys, candidates: (0..<size).map { candidateValues(segments.conversionSegment($0)) })
    {
      groups = []
      aiGroups = []
      for g in planned {
        let engineText = tops[g.segments].joined()
        // The AI's whole-sentence choice wins over Mozc's learned tops (user segment history), which stay right
        // below it; only an AI text the user replaced after this very conversion before is not proposed again.
        // Words the user registered win over the AI: a piece that drops one keeps Mozc's segments, with the
        // user's word on top (names such as 陽稀 for はるき, which the model would write the common way).
        let dropsUserWord =
          g.text != engineText && !Self.userWords(in: g.segments, of: segments, coveredBy: g.text)
        if g.text != engineText && (dropsUserWord || rejected(Piece(key: keys[g.segments].joined(), value: g.text))) {
          for i in g.segments {
            let segment = segments.conversionSegment(i)
            groups.append(AIConversionAligner.Group(segments: i..<(i + 1), text: Self.userWord(segment) ?? tops[i]))
            aiGroups.append(false)
          }
          if dropsUserWord {
            outcome.keptUserWords += 1
          } else {
            outcome.keptLearned += 1
          }
        } else {
          groups.append(g)
          aiGroups.append(g.text != engineText)
        }
      }
    } else {
      if !Self.userWords(in: 0..<size, of: segments, coveredBy: aiTop) {
        outcome.keptUserWords += 1
        return outcome
      }
      if rejected(Piece(key: keys.joined(), value: aiTop)) {
        outcome.keptLearned += 1
        return outcome
      }
      groups = [AIConversionAligner.Group(segments: 0..<size, text: aiTop)]
      aiGroups = [true]
    }
    outcome.wholeSentence = size > 1 && groups.count == 1 && aiGroups[0]

    // 2. Resize (merge) the segments if needed; Mozc re-converts the merged ones.
    let groupKeys = groups.map { keys[$0.segments].joined() }
    if groups.count != size {
      let sizes = groupKeys.map { $0.unicodeScalars.count }
      guard sizes.allSatisfy({ $0 > 0 && $0 <= Int(UInt8.max) }) else {
        return outcome
      }
      let wasResized = segments.resized
      guard converter.resizeSegments(segments, request, 0, sizes.map { UInt8($0) }),
        segments.conversionSegmentsSize == groups.count
      else {
        return outcome
      }
      // Not a user resize: keep UserBoundaryHistoryRewriter from learning the AI's boundaries.
      segments.setResized(wasResized)
      outcome.resized = true
    }

    // 3. Put the AI text of each group first. Groups where the AI agrees with Mozc keep Mozc's top (restored if
    // the re-conversion of a resize changed it).
    var inserted = [Int](repeating: 0, count: groups.count)
    for (i, g) in groups.enumerated() {
      let segment = segments.mutableConversionSegment(i)
      if segment.candidatesSize > 0 && segment.candidate(0).value == g.text {
        continue
      }
      promote(g.text, in: segment, to: 0, markAsAI: aiGroups[i])
      if aiGroups[i] {
        // The AI's choice differs from Mozc's default: like a user reranking, so that committing it teaches
        // Mozc (UserSegmentHistoryRewriter force-inserts RERANKED candidates) and Mozc alone converts the same
        // way next time (e.g. on a timeout).
        segment.mutableCandidate(0).attributes |= Attribute.reranked
        inserted[i] = 1
        outcome.replacedTop = true
        outcome.aiSegments.append(Piece(key: segment.key, value: g.text))
      }
    }

    // 4. The AI alternatives, cut at the final segment boundaries.
    let readingLengths = groupKeys.map { $0.unicodeScalars.count }
    let reading = groupKeys.joined()
    var seen: Set<String> = [aiTop]
    for text in texts.dropFirst() where !text.isEmpty && seen.insert(text).inserted {
      guard
        let pieces = AIConversionAligner.split(
          surface: text, readingLengths: readingLengths, reading: reading,
          candidates: (0..<groups.count).map { candidateValues(segments.conversionSegment($0)) })
      else {
        continue
      }
      for (i, piece) in pieces.enumerated() {
        let segment = segments.mutableConversionSegment(i)
        let limit = min(maxCandidates, segment.candidatesSize + 1)
        // Already among the AI candidates / the current top of this segment.
        let head = max(inserted[i], 1)
        if (0..<min(head, segment.candidatesSize)).contains(where: { segment.candidate($0).value == piece }) {
          continue
        }
        if head >= limit {
          continue
        }
        promote(piece, in: segment, to: head)
        inserted[i] = head + 1
        outcome.alternatives += 1
      }
    }
    return outcome
  }

  /// Whether `text` keeps every user dictionary word of the segments `range` (true if they have none): one of the
  /// segment's user dictionary candidates must appear in it (as its content word, without the particle).
  static func userWords(in range: Range<Int>, of segments: Segments, coveredBy text: String) -> Bool {
    range.allSatisfy { i in
      let words = userDictionaryCandidates(segments.conversionSegment(i))
      return words.isEmpty || words.contains { !$0.contentValue.isEmpty && text.contains($0.contentValue) }
    }
  }

  /// The candidates of `segment` that come from the user dictionary, best first.
  static func userDictionaryCandidates(_ segment: Segment) -> [Candidate] {
    (0..<min(segment.candidatesSize, 50)).map { segment.candidate($0) }
      .filter { $0.attributes & Attribute.userDictionary != 0 }
  }

  /// The user dictionary word to show on top of `segment` when Mozc's top is not one (nil: keep Mozc's top).
  static func userWord(_ segment: Segment) -> String? {
    guard segment.candidatesSize > 0, segment.candidate(0).attributes & Attribute.userDictionary == 0 else {
      return nil
    }
    return userDictionaryCandidates(segment).first?.value
  }

  static func candidateValues(_ segment: Segment) -> [String] {
    (0..<min(segment.candidatesSize, 50)).map { segment.candidate($0).value }
  }

  /// Moves the candidate with value `text` to `position`, or inserts a new one built from a Mozc candidate of the
  /// segment (POS ids, content key / functional suffix), so that committing it feeds Mozc's learning normally.
  static func promote(_ text: String, in segment: Segment, to position: Int, markAsAI: Bool = true) {
    if let index = (0..<segment.candidatesSize).first(where: { segment.candidate($0).value == text }) {
      if index != position {
        segment.moveCandidate(index, position)
      }
      if markAsAI {
        markAI(segment.mutableCandidate(min(position, segment.candidatesSize - 1)))
      }
      return
    }
    let candidate = makeCandidate(text, segment)
    if !markAsAI {
      candidate.description = ""
    }
    segment.insertCandidate(position, candidate)
  }

  static func markAI(_ candidate: Candidate) {
    if candidate.description.isEmpty {
      candidate.description = description
    } else if !candidate.description.hasPrefix(description) {
      candidate.description = description + " " + candidate.description
    }
  }

  static func makeCandidate(_ text: String, _ segment: Segment) -> Candidate {
    let key = segment.key
    // A Mozc candidate with the same functional suffix (e.g. "京は" for "今日は"): reuse its POS and content key.
    var template: Candidate?
    for i in 0..<segment.candidatesSize {
      let c = segment.candidate(i)
      guard c.key == key else { continue }
      let functional = String(c.functionalValue)
      if text.hasSuffix(functional) && text.utf8.count > functional.utf8.count {
        template = c
        break
      }
    }
    let candidate = Candidate()
    candidate.key = key
    candidate.value = text
    if let template {
      let functional = String(template.functionalValue)
      candidate.contentKey = template.contentKey
      candidate.contentValue = String(text.utf8.dropLast(functional.utf8.count)) ?? text
      candidate.lid = template.lid
      candidate.rid = template.rid
      candidate.cost = template.cost
      candidate.wcost = template.wcost
      candidate.structureCost = template.structureCost
    } else {
      candidate.contentKey = key
      candidate.contentValue = text
      if segment.candidatesSize > 0 {
        let top = segment.candidate(0)
        candidate.lid = top.lid
        candidate.rid = top.rid
        candidate.cost = top.cost
        candidate.wcost = top.wcost
      }
    }
    candidate.description = description
    return candidate
  }
}
