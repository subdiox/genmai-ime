// Port of mozc/src/prediction/user_history_predictor.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - engine::Modules is not ported yet. The predictor only uses the parts of it
//   abstracted by `UserHistoryPredictorModules` below (engine::Modules should
//   conform to it). engine::SupplementalModelInterface is abstracted by
//   `UserHistorySupplementalModel` (the engine's SupplementalModelInterface
//   should refine it); its accessor is named
//   `getUserHistorySupplementalModel()` so that one modules class can also
//   conform to `ConverterModules` (whose `getSupplementalModel()` returns a
//   different protocol).
// - RealtimeDecoder (prediction/realtime_decoder.h) is abstracted by
//   `UserHistoryRealtimeDecoder` (only `DecodeSuffix` is used); RealtimeDecoder
//   should conform to it.
// - Entry pointers (`const Entry*`) are value copies (`Entry?`); the entries of
//   `EntryPriorityQueue` live in its pool and are addressed by index. The C++
//   priority queue breaks score ties by the Entry pointer (arena address); the
//   pool index (allocation order) is used instead, which matches C++ as long
//   as the arena returns increasing addresses.
// - `absl::HashOf(entry.value())` (dedup in EntryPriorityQueue) is the 64-bit
//   CityFingerprint of the value bytes.
// - `request.history_result()` is `any ConversionRequestHistoryResult`; it is
//   read as a PredictionResult (`PredictionResult`, or a view conforming to
//   `PredictionHistoryResultConvertible`), else the default result.
// - All string comparisons, prefixes and hash keys are bytewise.

import Foundation
import GenmaiBase
import GenmaiProtocol
import Synchronization

/// The subset of engine::SupplementalModelInterface used by
/// UserHistoryPredictor.
public protocol UserHistorySupplementalModel: ReadingAlignmentSupplementalModel {
  /// Performs typing correction. Returns nil when typing correction is not
  /// enabled/available.
  func correctComposition(_ request: ConversionRequest) -> [TypeCorrectedQuery]?
}

/// engine::SupplementalModelInterface default (stub) implementation.
public final class UserHistorySupplementalModelStub: UserHistorySupplementalModel,
  @unchecked Sendable
{
  public init() {}
  public func correctComposition(_ request: ConversionRequest) -> [TypeCorrectedQuery]? { nil }
  public func getReadingAlignment(_ surface: String, _ reading: String) -> [(String, String)] { [] }
}

/// The subset of engine::Modules used by UserHistoryPredictor.
public protocol UserHistoryPredictorModules: AnyObject {
  func getPosMatcher() -> PosMatcher
  func getUserDictionary() -> any UserDictionaryInterface
  func getUserHistoryStorage() -> UserHistoryStorage
  func getUserHistorySupplementalModel() -> any UserHistorySupplementalModel
  func getSegmenter() -> Segmenter
  func getConnector() -> Connector
  func getDictionary() -> any DictionaryInterface
}

/// The subset of prediction::RealtimeDecoder used by UserHistoryPredictor.
public protocol UserHistoryRealtimeDecoder: AnyObject {
  func decodeSuffix(_ request: ConversionRequest, _ prefixRid: UInt16, _ suffix: String)
    -> PredictionResult?
}

/// A history result (ConversionRequest::history_result()) that is a view of a
/// PredictionResult held elsewhere (C++ `SetHistoryResultView`).
public protocol PredictionHistoryResultConvertible {
  var historyPredictionResult: PredictionResult { get }
}

// Finds suffix matches of history_segments from the most recent 500 histories
// in LRU.
private let kMaxPrevValueTrial = 500

// Don't save key/value that are
// longer than kMaxCandidateSize to avoid memory explosion
private let kMaxStringLength = 256

// Maximum size of next_entries
private let kMaxNextEntriesSize = 6

private let kEmojiDescription = "絵文字"

// Spaces added as a prefix of NWP.
private let kPrefixFullSpace = "　"  // full width
private let kPrefixHalfSpace = " "  // half width.
private let kPrefixDisplaySpace = "␣"

// Zero width space is added as an alternative character of space-prefix
// to identify that the histories are handled as a special case of NWP.
private let kPrefixZeroSpace = "\u{200b}"  // Zero-width space.

private let kRevertCacheSize = 16

private let kPunctuations = ["。", ".", "、", ",", "？", "?", "！", "!", "，", "．"]

// Mixed conversion is enabled mainly on mobile device.
private func isMixedConversionEnabled(_ request: ConversionRequest) -> Bool {
  request.request().mixedConversion
}

private func isZeroQuerySuggestionEnabled(_ request: ConversionRequest) -> Bool {
  request.request().zeroQuerySuggestion
}

// TODO(peria, hidehiko): Unify this checker and IsEmojiCandidate in
//     EmojiRewriter.  If you make similar functions before the merging in
//     case, put a similar note to avoid twisted dependency.
private func isEmojiEntry(_ entry: UserHistoryPredictor.Entry) -> Bool {
  entry.hasDescription_p && byteContains(entry.description_p, kEmojiDescription)
}

// Full sentence entry with low frequency should not be suggested.
private func isLowFreqFullSentenceEntry(
  _ request: ConversionRequest, _ entry: UserHistoryPredictor.Entry
) -> Bool {
  isMixedConversionEnabled(request) && entry.innerSegmentBoundary.count >= 2
    && entry.suggestionFreq <= 1
}

// http://unicode.org/~scherer/emoji4unicode/snapshot/full.html
private let kUtf8MinGooglePuaEmoji: [UInt8] = [0xf3, 0xbe, 0x80, 0x80]
private let kUtf8MaxGooglePuaEmoji: [UInt8] = [0xf3, 0xbe, 0xba, 0xa0]

private func isAndroidPuaEmoji(_ s: String) -> Bool {
  let bytes = Array(s.utf8)
  return bytes.count == 4 && Strings.compareBytes(kUtf8MinGooglePuaEmoji, bytes) <= 0
    && Strings.compareBytes(bytes, kUtf8MaxGooglePuaEmoji) <= 0
}

private func startsWithPunctuation(_ value: some StringProtocol) -> Bool {
  kPunctuations.contains { value.hasBytePrefix($0) }
}

private func endsWithPunctuation(_ value: some StringProtocol) -> Bool {
  kPunctuations.contains { value.hasByteSuffix($0) }
}

// Returns romanaized string.
private func toRoman(_ str: some StringProtocol) -> String {
  Japanese.hiraganaToRomanji(str)
}

// Returns true if value looks like a content word.
// Currently, just checks the script type.
private func isContentWord(_ value: some StringProtocol) -> Bool {
  Util.charsLen(value) > 1 || Util.getScriptType(value) != .unknownScript
}

// Returns true if `value` starts with a valid letter character.
private func startsWithValidLetter(_ value: some StringProtocol) -> Bool {
  let type = Util.getFirstScriptType(value)
  return type == .kanji || type == .hiragana || type == .katakana || type == .alphabet
}

// Returns true if the preceding history in converter context is a number.
private func isPrecedingNumber(_ request: ConversionRequest) -> Bool {
  Util.getScriptType(request.converterHistoryValue(1)) == .number
}

// Returns candidate description.
// If candidate is spelling correction, typing correction
// or auto partial suggestion,
// don't use the description, since "did you mean" like description must be
// provided at an appropriate timing and context.
private func getDescription(_ result: PredictionResult) -> String {
  if result.attributes
    & (Attribute.spellingCorrection | Attribute.typingCorrection | Attribute.autoPartialSuggestion)
    != 0
  {
    return ""
  }
  return result.description
}

// Populate `inner_segment_boundary` to the new `entry`.
private func maybePopulateInnerSegmentBoundary(
  _ request: ConversionRequest, _ innerSegmentBoundary: InnerSegmentBoundary,
  _ entry: inout UserHistoryPredictor.Entry
) {
  // We only populate inner_segment_boundary when
  // non-empty inner_segment_boundary is passed.
  if innerSegmentBoundary.isEmpty { return }

  entry.innerSegmentBoundary = innerSegmentBoundary
}

// Add the inner_segment_boundary information in `entry` via `builder`.
private func appendInnerBoundary(
  _ request: ConversionRequest, _ builder: inout InnerSegmentBoundaryBuilder,
  _ entry: UserHistoryPredictor.Entry
) {
  if !entry.innerSegmentBoundary.isEmpty {
    // Directly copies the raw encoded value.
    for encoded in entry.innerSegmentBoundary {
      builder.addEncoded(encoded)
    }
  } else {
    // Encode the length assuming one key/value.
    builder.add(
      entry.key.utf8.count, entry.value.utf8.count, entry.key.utf8.count, entry.value.utf8.count)
  }
}

private func setAttribute(_ entry: inout UserHistoryPredictor.Entry, _ v: UInt32) {
  entry.attributes = entry.attributes | v
}

private func removeAttribute(_ entry: inout UserHistoryPredictor.Entry, _ v: UInt32) {
  entry.attributes = entry.attributes & ~v
}

// MARK: - Byte string helpers

private func isAsciiWhitespace(_ b: UInt8) -> Bool {
  b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0B || b == 0x0C || b == 0x0D
}

/// absl::StripAsciiWhitespace.
private func stripAsciiWhitespace(_ s: some StringProtocol) -> Substring {
  let sub = Substring(s)
  let u = sub.utf8
  var begin = u.startIndex
  var end = u.endIndex
  while begin < end && isAsciiWhitespace(u[begin]) { begin = u.index(after: begin) }
  while end > begin && isAsciiWhitespace(u[u.index(before: end)]) { end = u.index(before: end) }
  return sub[begin..<end]
}

/// absl::StripTrailingAsciiWhitespace.
private func stripTrailingAsciiWhitespace(_ s: some StringProtocol) -> Substring {
  let sub = Substring(s)
  let u = sub.utf8
  var end = u.endIndex
  while end > u.startIndex && isAsciiWhitespace(u[u.index(before: end)]) {
    end = u.index(before: end)
  }
  return sub[sub.startIndex..<end]
}

/// absl::StrContains (bytewise).
private func byteContains(_ s: some StringProtocol, _ needle: some StringProtocol) -> Bool {
  byteFind(s, needle) != nil
}

/// absl::string_view::find (bytewise). Returns the byte offset.
private func byteFind(_ s: some StringProtocol, _ needle: some StringProtocol) -> Int? {
  let h = Array(s.utf8)
  let n = Array(needle.utf8)
  if n.isEmpty { return 0 }
  if n.count > h.count { return nil }
  var i = 0
  while i + n.count <= h.count {
    if h[i] == n[0] && h[i..<(i + n.count)].elementsEqual(n) {
      return i
    }
    i += 1
  }
  return nil
}

/// A bytewise hashable key for (key, value) pairs.
private struct BytePair: Hashable {
  let key: [UInt8]
  let value: [UInt8]
  init(_ key: some StringProtocol, _ value: some StringProtocol) {
    self.key = Array(key.utf8)
    self.value = Array(value.utf8)
  }
}

/// `mozc::prediction::UserHistoryPredictor`.
public final class UserHistoryPredictor: PredictorInterface, @unchecked Sendable {
  // @unchecked Sendable: the storage, the revert cache and
  // `lastCommittedEntries` are thread-safe; the rest is immutable.

  public typealias Entry = UserHistoryStorage.Entry
  public typealias EntrySnapshot = UserHistoryStorage.EntrySnapshot
  public typealias ConstEntrySnapshot = UserHistoryStorage.ConstEntrySnapshot

  /// This field is going to be serialized to storage.
  public enum EntryFlag {
    public static let none: UInt32 = 0
    /// Set when this entry was committed following a number (e.g. 階, 回, 人).
    /// Corresponds to legacy UserSegmentHistoryRewriter's "LN" (Left Number)
    /// feature.
    public static let leftNumber: UInt32 = 1 << 0
  }

  struct SegmentForLearning {
    // The string byte offset of key and value on result.(key|value).
    var keyBegin: Int32 = 0
    var valueBegin: Int32 = 0
    var key = ""
    var value = ""
    var contentKey = ""
    var contentValue = ""
    var description = ""
  }

  // Fingerprint of key/value.
  static func learningSegmentFingerprint(_ learningSegment: SegmentForLearning) -> UInt64 {
    UserHistoryStorage.fingerprint(learningSegment.key, learningSegment.value)
  }

  struct SegmentsForLearning {
    var conversionSegmentsKey = ""
    var conversionSegmentsValue = ""
    var innerSegmentBoundary: InnerSegmentBoundary = []

    var historySegments: [SegmentForLearning] = []
    var conversionSegments: [SegmentForLearning] = []

    // whether the there is a space between history_segments.back() and
    // conversion_segments.front(), e.g., ラーメン_渋谷. We heuristically
    // identify the existence of the space using the surrounding context and the
    // head segment in the LRU cache.
    var hasSpacePrefix = false

    // Allows partial match training on the content_value of the first segment.
    // Partial match is allowed when the token seems to be a proper noun.
    var allowPartialMatch = false
  }

  enum MatchType {
    case noMatch  // no match
    case leftPrefixMatch  // left string is a prefix of right string
    case rightPrefixMatch  // right string is a prefix of left string
    case leftEmptyMatch  // left string is empty (for zero_query_suggestion)
    case exactMatch  // right string == left string
  }

  enum Attribute {
    // Bigram entry. Should have special bonus.
    static let bigramBoost: UInt32 = 1

    // Needs to populate spelling correction information from Entry to Result.
    static let spellingCorrection: UInt32 = 2

    // This candidate should be placed below the default top candidate.
    // Its confidence score is low.
    static let weakCandidate: UInt32 = 4

    // Force to populate inner segment boundary from Entry to Result.
    // By default, boundary information is not passed to the Result. For
    // candidates that have never been input before, e.g. partial match
    // candidates, they are treated as standard conversions and their boundary
    // information is populated to the Result.
    static let populateInnerSegmentBoundary: UInt32 = 8

    // Set when an older user history entry lacks inner boundary information.
    // This attribute conveys that the original user history had no inner
    // boundary. Special care is needed when a single segment placeholder
    // is used as the inner boundary for such entries.
    static let emptyInnerSegmentBoundary: UInt32 = 16
  }

  /// Priority Queue class for entry. New item is sorted by
  /// |score| internally. By calling Pop() in sequence, you
  /// can obtain the list of entry sorted by |score|.
  /// Entries are addressed by their index in `pool` (C++ `Entry*`).
  final class EntryPriorityQueue {
    // Default object pool size for EntryPriorityQueue
    static let kEntryPoolSize = 16

    private(set) var pool: [Entry] = []
    // Binary max-heap of (score, pool index).
    private var agenda: [(UInt64, Int)] = []
    private var seen = Set<UInt64>()
    private var partialEntryCount: [[UInt8]: (Int, Int)] = [:]

    init() {
      pool.reserveCapacity(Self.kEntryPoolSize)
    }

    var size: Int { agenda.count }

    /// `Entry*` -> the entry in the pool.
    subscript(_ index: Int) -> Entry {
      get { pool[index] }
      set { pool[index] = newValue }
      _modify { yield &pool[index] }
    }

    @discardableResult
    func push(_ index: Int) -> Bool {
      if !seen.insert(cityFingerprint(pool[index].value)).inserted {
        return false
      }
      let score = UInt64(UserHistoryPredictor.getScore(pool[index]))
      heapPush((score, index))
      return true
    }

    func pop() -> Int? {
      if agenda.isEmpty {
        return nil
      }
      return heapPop().1
    }

    func newEntry() -> Int {
      pool.append(Entry())
      return pool.count - 1
    }

    /// During the linear-search on LRU entries, keep track of the
    /// partially-matched entry.
    func recordPartialEntry(_ entry: Entry) {
      let key = Array(entry.key.utf8)
      var count = partialEntryCount[key] ?? (0, 0)
      if entry.allowPartialMatch {
        count.1 += 1
      } else {
        count.0 += 1
      }
      partialEntryCount[key] = count
    }

    /// Returns the counts of partially-matched entry so far.
    /// Returns [disallowed_count, allowed_count].
    /// When disallowed_count > 0,  we do not push new partial entry via Push(),
    /// The user has recently entered a partial match candidate, but the model is
    /// simply not displaying it.
    func getPartialCount(_ partialKey: some StringProtocol) -> (Int, Int) {
      partialEntryCount[Array(partialKey.utf8)] ?? (0, 0)
    }

    // std::priority_queue<std::pair<uint64_t, Entry*>> ordering.
    private static func less(_ a: (UInt64, Int), _ b: (UInt64, Int)) -> Bool {
      a.0 != b.0 ? a.0 < b.0 : a.1 < b.1
    }

    private func heapPush(_ e: (UInt64, Int)) {
      agenda.append(e)
      var i = agenda.count - 1
      while i > 0 {
        let parent = (i - 1) / 2
        if !Self.less(agenda[parent], agenda[i]) { break }
        agenda.swapAt(parent, i)
        i = parent
      }
    }

    private func heapPop() -> (UInt64, Int) {
      let top = agenda[0]
      let last = agenda.removeLast()
      if !agenda.isEmpty {
        agenda[0] = last
        var i = 0
        let n = agenda.count
        while true {
          let l = 2 * i + 1
          let r = l + 1
          var largest = i
          if l < n && Self.less(agenda[largest], agenda[l]) { largest = l }
          if r < n && Self.less(agenda[largest], agenda[r]) { largest = r }
          if largest == i { break }
          agenda.swapAt(i, largest)
          i = largest
        }
      }
      return top
    }
  }

  struct RevertEntries: Sendable {
    // The result committed.
    var result = PredictionResult()

    // History entry (previous context).
    // The chain link from history entry to the first entries are reverted.
    var historyEntry: Entry?

    // Actual primitive entries associated with the last commit operation.
    // vector of [key_begin, value_begin, revert_entry].
    // `revert_entry` is stored in the LRU cache.
    // entry.key/value() starts from the result.key/value[key/value_begin].
    var entries: [(Int32, Int32, Entry)] = []
  }

  private let userDictionary: any UserDictionaryInterface
  private let modules: any UserHistoryPredictorModules

  // Initialized via modules_.
  let storage: UserHistoryStorage

  // Internal LRU cache to store dic_key/Entry to be reverted.
  private let revertCache = FlatConcurrentCache<UInt32, RevertEntries>(kRevertCacheSize)

  // `last_committed_entries_` stores the entries to be re-committed
  // after Revert().  Note that `last_committed_entries_` is not associated with
  // revert_id and shared across different context (text view).
  private let lastCommittedEntries = Mutex<RevertEntries?>(nil)

  private let decoder: any UserHistoryRealtimeDecoder

  public init(
    _ modules: any UserHistoryPredictorModules, _ realtimeDecoder: any UserHistoryRealtimeDecoder
  ) {
    self.userDictionary = modules.getUserDictionary()
    self.modules = modules
    self.storage = modules.getUserHistoryStorage()
    self.decoder = realtimeDecoder
  }

  // MARK: - PredictorInterface

  @discardableResult
  public func wait() async -> Bool {
    await storage.wait()
    return true
  }

  @discardableResult
  public func sync() -> Bool {
    storage.asyncSave()
    return true
  }

  @discardableResult
  public func reload() -> Bool {
    // storage_->Wait(); storage_->AsyncLoad(); (the load is scheduled after
    // the running syncer task instead of blocking until it finishes).
    storage.asyncLoadAfterSyncer()
    return true
  }

  @discardableResult
  public func clearAllHistory() -> Bool {
    storage.clear()  // Clears the memory at once; the file is written by the syncer.
    return true
  }

  public func getPredictorName() -> String { "UserHistoryPredictor" }

  // MARK: - Implementation

  /// Returns true if the input first candidate seems to be a privacy sensitive
  /// such like password.
  func isPrivacySensitive(_ results: [PredictionResult]) -> Bool {
    let kNonSensitive = false
    let kSensitive = true

    guard let front = results.first else {
      return kNonSensitive
    }

    // Skips privacy sensitive check if |segments| consists of multiple conversion
    // segment. That is, segments like "パスワードは|x7LAGhaR" where '|'
    // represents segment boundary is not considered to be privacy sensitive.
    // TODO(team): Revisit this rule if necessary.
    if front.innerSegmentBoundary.count > 1 {
      return kNonSensitive
    }

    // Hereafter, we must have only one conversion segment.
    let key = front.key

    // The top candidate, which is about to be committed.
    let candidateValue = front.value

    // If |candidate_value| contains any non-ASCII character, do not treat
    // it as privacy sensitive information.
    // TODO(team): Improve the following rule. For example,
    //     "0000－0000－0000－0000" is not treated as privacy sensitive
    //     because of this rule. When a user commits his password in
    //     full-width form by mistake, like "ｘ７ＬＡＧｈａＲ", it is not
    //     treated as privacy sensitive too.
    if !Util.isAscii(candidateValue) {
      return kNonSensitive
    }

    // Hereafter, |candidate_value| consists of ASCII characters only.

    // Note: if the key looks like hiragana, the candidate might be Katakana to
    // English transliteration. Don't suppress transliterated candidates.
    // http://b/4394325

    // If the key consists of number characters only, treat it as privacy
    // sensitive.
    if Util.getScriptType(key) == .number {
      return kSensitive
    }

    return kNonSensitive
  }

  /// Erases all the next_entries whose entry_fp field equals |fp|.
  static func eraseNextEntries(_ fp: UInt64, _ entry: inout Entry) {
    entry.nextEntryFps.removeAll { $0 == fp }
  }

  // Returns value of RemoveNgramChain() method. See the comments in
  // implementation.
  private enum RemoveNgramChainResult {
    case done
    case tail
    case notFound
  }

  /// Recursively finds the Ngram history that produces |target_key| and
  /// |target_value| and removes the last link. For example, if there exists a
  /// chain like
  ///    ("aaa", "AAA") -- ("bbb", "BBB") -- ("ccc", "CCC"),
  /// and if target_key == "aaabbbccc" and target_value == "AAABBBCCC", the link
  /// from ("bbb", "BBB") to ("ccc", "CCC") is removed.
  /// return true if a link was removed.
  ///
  /// `entry` is a mutable snapshot (C++ `Entry&`); the chain may link back to
  /// the same entry, so it is accessed through snapshots rather than `inout`.
  func removeNgramChain(_ targetKey: String, _ targetValue: String, _ entry: EntrySnapshot)
    -> Bool
  {
    if !targetKey.hasBytePrefix(entry.entry.key) || !targetValue.hasBytePrefix(entry.entry.value)
    {
      return false
    }

    var keyNgrams: [String] = []
    var valueNgrams: [String] = []
    keyNgrams.reserveCapacity(8)
    valueNgrams.reserveCapacity(8)
    let targetKeySize = targetKey.utf8.count
    let targetValueSize = targetValue.utf8.count

    func removeNgramChainInternal(
      _ entry: EntrySnapshot, _ keyNgramsLen: Int, _ valueNgramsLen: Int
    ) -> RemoveNgramChainResult {
      let current = entry.entry
      // Updates the lengths with the current entry node.
      let keyNgramsLen = keyNgramsLen + current.key.utf8.count
      let valueNgramsLen = valueNgramsLen + current.value.utf8.count

      // This is the case where ngram key and value are shorter than the target
      // key and value, respectively. In this case, we need to find further
      // entries to concatenate in order to make |target_key| and |target_value|.
      if keyNgramsLen < targetKeySize && valueNgramsLen < targetValueSize {
        keyNgrams.append(current.key)
        valueNgrams.append(current.value)
        for fp in current.nextEntryFps {
          let e = storage.mutableLookup(fp)
          if e.isNull {
            continue
          }
          switch removeNgramChainInternal(e, keyNgramsLen, valueNgramsLen) {
          case .done:
            return .done
          case .tail:
            // |entry| is the second-to-the-last node. So cut the link to the
            // child entry.
            Self.eraseNextEntries(fp, &entry.entry)
            return .done
          default:
            break
          }
        }
        // Recovers the state.
        keyNgrams.removeLast()
        valueNgrams.removeLast()
        return .notFound
      }

      // This is the case where the current ngram key and value have the same
      // lengths as those of |target_key| and |target_value|, respectively.
      if keyNgramsLen == targetKeySize && valueNgramsLen == targetValueSize {
        keyNgrams.append(current.key)
        valueNgrams.append(current.value)
        let ngramKey = keyNgrams.joined()
        let ngramValue = valueNgrams.joined()
        if ngramKey.bytesEqual(targetKey) && ngramValue.bytesEqual(targetValue) {
          // |entry| is the last node. So return TAIL to tell the caller so that
          // it can remove the link to this last node.
          return .tail
        }
        keyNgrams.removeLast()
        valueNgrams.removeLast()
        return .notFound
      }

      return .notFound
    }

    return removeNgramChainInternal(entry, 0, 0) == .done
  }

  /// Removes entry when key/value are the prefix of entry with
  /// the inner boundary constraint. entry->removed() gets true when removed.
  static func removeEntryWithInnerSegment(_ key: String, _ value: String, _ entry: inout Entry)
    -> Bool
  {
    if entry.innerSegmentBoundary.isEmpty {
      return false
    }

    // TODO(taku): Support multiple matches.

    // Checks from value as value is less likely matched.
    guard let valueStart = byteFind(entry.value, value) else { return false }

    guard let keyStart = byteFind(entry.key, key) else { return false }

    let innerSegments = InnerSegments(
      key: entry.key, value: entry.value, innerSegmentBoundary: entry.innerSegmentBoundary)

    let keyEnd = keyStart + key.utf8.count
    let valueEnd = valueStart + value.utf8.count

    var keyLen = 0
    var valueLen = 0
    var startMatch = false

    for it in innerSegments {
      if keyLen == keyStart && valueLen == valueStart {
        startMatch = true
      }

      // Ends at the key/value or content_key/value boundary.
      if (keyLen + it.key.utf8.count == keyEnd && valueLen + it.value.utf8.count == valueEnd)
        || (keyLen + it.contentKey.utf8.count == keyEnd
          && valueLen + it.contentValue.utf8.count == valueEnd)
      {
        if startMatch {
          entry.suggestionFreq = 0
          entry.shownFreq = 0
          entry.removed = true
          return true
        }
        return false
      }

      keyLen += it.key.utf8.count
      valueLen += it.value.utf8.count

      // Exceeds the boundary.
      if !startMatch && (keyLen > keyStart || valueLen > valueStart) {
        return false
      }
    }

    return false
  }

  @discardableResult
  public func clearHistoryEntry(_ key: String, _ value: String) -> Bool {
    var deleted = false

    // The stored data uses the kPrefixZeroSpace for the prefix space, so
    // we replace the prefix space with kPrefixZeroSpace.
    func maybeNormalizePrefixSpace(_ str: String) -> String {
      for space in [kPrefixFullSpace, kPrefixHalfSpace] {
        if str.hasBytePrefix(space) {
          return kPrefixZeroSpace + String(str.byteSubstring(from: space.utf8.count))
        }
      }
      return str
    }

    let key = maybeNormalizePrefixSpace(key)
    let value = maybeNormalizePrefixSpace(value)

    do {
      // Finds the history entry that has the exactly same key and value and has
      // not been removed yet. If exists, remove it.
      let entry = storage.mutableLookup(key, value)
      if !entry.isNull && !entry.entry.removed {
        entry.entry.suggestionFreq = 0
        entry.entry.shownFreq = 0
        entry.entry.removed = true
        // We don't clear entry->next_entries() so that we can generate prediction
        // by chaining.
        deleted = true
      }
    }

    do {
      // Two case
      // 1) Finds a chain of history entries that produces key and value.
      //   If exists, remove the link so that N-gram history prediction never
      //   generates this key value pair.
      // 2) key/value are the substring of entry.
      // (C++ ForEach with mutable entries. The entries are visited in LRU
      // order through snapshots, as RemoveNgramChain may revisit the
      // iterated entry; mutable lookups don't change the LRU order.)
      do {
        var fps: [UInt64] = []
        storage.forEach { fp, _ in
          fps.append(fp)
          return true
        }
        for fp in fps {
          let entry = storage.mutableLookup(fp)
          if entry.isNull { continue }
          if removeNgramChain(key, value, entry) {
            deleted = true
            continue
          }
          var e = entry.entry
          if Self.removeEntryWithInnerSegment(key, value, &e) {
            entry.entry = e
            deleted = true
          }
        }
      }
    }

    return deleted
  }

  @discardableResult
  public func addHistoryEntry(_ key: String, _ value: String) -> Bool {
    let key = stripAsciiWhitespace(key)
    let value = stripAsciiWhitespace(value)

    if !Util.isValidUtf8(key) || !Util.isValidUtf8(value) || key.utf8.isEmpty
      || value.utf8.isEmpty || key.utf8.count > kMaxStringLength
      || value.utf8.count > kMaxStringLength || !startsWithValidLetter(value)
      || endsWithPunctuation(value)
    {
      return false
    }

    let entry = storage.insert(UserHistoryStorage.fingerprint(key, value))
    if entry.isNull {
      return false
    }

    entry.entry.key = String(key)
    entry.entry.value = String(value)
    entry.entry.removed = false
    entry.entry.suggestionFreq = entry.entry.suggestionFreq + 1

    let lastAccessTime = UInt64(Clock.getUnixSeconds())
    entry.entry.lastAccessTime = lastAccessTime

    return true
  }

  /// Returns the LUR order of the next_fp links from `prev_entry` to `entry`.
  /// Returns a larger value if the connection from prev_entry to entry was made
  /// more recently. The return value must be [0, kMaxNextEntriesSize).
  static func getBigramEntryLruOrder(_ entry: Entry, _ prevEntry: Entry) -> Int? {
    let fp = UserHistoryStorage.fingerprint(entry)
    return prevEntry.nextEntryFps.firstIndex(of: fp)
  }

  /// Returns true if prev_entry has a next_fp link to entry,
  /// or entry is a counter suffix following a number in request.
  static func hasBigramEntry(_ request: ConversionRequest, _ entry: Entry, _ prevEntry: Entry?)
    -> Bool
  {
    if let prevEntry, getBigramEntryLruOrder(entry, prevEntry) != nil {
      return true
    }
    return (entry.entryFlags & EntryFlag.leftNumber) != 0 && isPrecedingNumber(request)
  }

  /// Returns romanized preedit string if the preedit looks
  /// misspelled. It first tries to get the preedit string with
  /// composer() if composer is available. If not, use the key
  /// directory. It also use MaybeRomanMisspelledKey() defined
  /// below to check the preedit looks misspelled or not.
  static func getRomanMisspelledKey(_ request: ConversionRequest) -> String {
    if request.config().preeditMethod != .roman {
      return ""
    }

    let preedit = request.key()
    // TODO(team): Use composer if it is available.
    // segments.composer()->GetQueryForConversion(&preedit);
    // Since ConverterInterface doesn't have StartPredictionWithComposer,
    // we cannot use composer currently.
    if !preedit.utf8.isEmpty && maybeRomanMisspelledKey(preedit) {
      return toRoman(preedit)
    }

    return ""
  }

  /// Returns the typing corrected queries.
  func getTypingCorrectedQueries(_ request: ConversionRequest) -> [TypeCorrectedQuery] {
    let size = Int(
      request.request().decoderExperimentParams.typingCorrectionApplyUserHistorySize)
    if size == 0 || !request.config().useTypingCorrection { return [] }

    guard
      var result = modules.getUserHistorySupplementalModel().correctComposition(request)
    else { return [] }

    if size > 0 && size < result.count { result.removeSubrange(size...) }

    return result
  }

  /// Returns true if |key| may contain miss spelling.
  /// Currently, this function returns true if
  /// 1) key contains only one alphabet.
  /// 2) other characters of key are all hiragana.
  static func maybeRomanMisspelledKey(_ key: some StringProtocol) -> Bool {
    var numAlpha = 0
    var numHiragana = 0
    var numUnknown = 0
    for codepoint in ConstChar32Iterator(key) {
      let type = Util.getScriptType(codepoint)
      if type == .hiragana || codepoint == 0x30FC {  // "ー".
        numHiragana += 1
        continue
      }
      if type == .unknownScript && numUnknown <= 0 {
        numUnknown += 1
        continue
      }
      if type == .alphabet && numAlpha <= 0 {
        numAlpha += 1
        continue
      }
      return false
    }

    return numHiragana > 0
      && ((numAlpha == 1 && numUnknown == 0) || (numAlpha == 0 && numUnknown == 1))
  }

  /// Returns true if |prefix| is a fuzzy-prefix of |str|.
  /// 'Fuzzy' means that
  /// 1) Allows one character deletion in the |prefix|.
  /// 2) Allows one character swap in the |prefix|.
  static func romanFuzzyPrefixMatch(_ strIn: some StringProtocol, _ prefixIn: some StringProtocol)
    -> Bool
  {
    let str = Array(strIn.utf8)
    let prefix = Array(prefixIn.utf8)
    if prefix.isEmpty || prefix.count > str.count {
      return false
    }

    func isAlnum(_ c: UInt8) -> Bool {
      (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
    }

    // 1. Allows one character delete in Romanji sequence.
    // 2. Allows one swap in Romanji sequence.
    for i in 0..<prefix.count {
      if prefix[i] == str[i] {
        continue
      }

      if str[i] == UInt8(ascii: "-") {
        // '-' voice sound mark can be matched to any
        // non-alphanum character.
        if !isAlnum(prefix[i]) {
          var replacedPrefix = prefix
          replacedPrefix[i] = str[i]
          if str.starts(with: replacedPrefix) {
            return true
          }
        }
      } else {
        // deletion.
        var insertedPrefix = prefix
        insertedPrefix.insert(str[i], at: i)
        if str.starts(with: insertedPrefix) {
          return true
        }

        // swap.
        if i + 1 < prefix.count {
          var swappedPrefix = prefix
          swappedPrefix.swapAt(i, i + 1)
          if str.starts(with: swappedPrefix) {
            return true
          }
        }
      }

      return false
    }

    // |prefix| is an exact suffix of |str|.
    return false
  }

  /// if `prev_entry` is the prefix of `entry`, add the suffix part as
  /// zero-query suggestion.
  func zeroQueryLookupEntry(
    _ request: ConversionRequest, _ requestKey: String, _ entry: Entry, _ prevEntry: Entry?,
    _ entryQueue: EntryPriorityQueue
  ) -> Bool {
    // - request_key is empty,
    // - prev_entry(history) = 東京
    // - entry in LRU = 東京で
    //   Then we suggest で as zero query suggestion.

    // when `perv_entry` is not null, it is guaranteed that
    // the history segment is in the LRU cache.
    if let prevEntry, isZeroQuerySuggestionEnabled(request), requestKey.utf8.isEmpty,
      entry.key.utf8.count > prevEntry.key.utf8.count,
      entry.value.utf8.count > prevEntry.value.utf8.count,
      entry.key.hasBytePrefix(prevEntry.key), entry.value.hasBytePrefix(prevEntry.value)
    {
      // suffix must starts with Japanese characters.
      let key = String(entry.key.byteSubstring(from: prevEntry.key.utf8.count))
      let value = String(entry.value.byteSubstring(from: prevEntry.value.utf8.count))
      if !startsWithValidLetter(value) {
        return false
      }
      let result = entryQueue.newEntry()
      // Copy timestamp from `entry`
      entryQueue[result] = entry
      entryQueue[result].key = key
      entryQueue[result].value = value
      setAttribute(&entryQueue[result], Attribute.bigramBoost)
      entryQueue.push(result)
      return true
    }

    return false
  }

  /// If roman_request_key can be a target key of entry->key(), creat a new
  /// result and insert it to |entry_queue|.
  /// This method adds a new result entry with score, pair<score, entry>, to
  /// |entry_queue|.
  func romanFuzzyLookupEntry(
    _ romanRequestKey: String, _ entry: Entry, _ entryQueue: EntryPriorityQueue
  ) -> Bool {
    if romanRequestKey.utf8.isEmpty {
      return false
    }

    if !Self.romanFuzzyPrefixMatch(toRoman(entry.key), romanRequestKey) {
      return false
    }

    let result = entryQueue.newEntry()
    entryQueue[result] = entry
    setAttribute(&entryQueue[result], Attribute.spellingCorrection)
    entryQueue.push(result)

    return true
  }

  /// Adds an entry to a priority queue.
  private func addEntry(_ entry: Entry, _ entryQueue: EntryPriorityQueue) -> Int {
    // We add an entry even if it was marked as removed so that it can be used to
    // generate prediction by entry chaining. The deleted entry itself is never
    // shown in the final prediction result as it is filtered finally.
    let newEntry = entryQueue.newEntry()
    entryQueue[newEntry] = entry
    if entryQueue[newEntry].innerSegmentBoundary.isEmpty {
      entryQueue[newEntry].attributes =
        entryQueue[newEntry].attributes | Attribute.emptyInnerSegmentBoundary
    }
    return newEntry
  }

  /// Adds the entry whose key and value are modified to a priority queue.
  private func addEntryWithNewKeyValue(
    _ request: ConversionRequest, _ key: String, _ value: String,
    _ innerSegmentBoundary: InnerSegmentBoundary, _ entry: Entry,
    _ entryQueue: EntryPriorityQueue
  ) -> Int {
    let newEntry = addEntry(entry, entryQueue)
    entryQueue[newEntry].key = key
    entryQueue[newEntry].value = value
    maybePopulateInnerSegmentBoundary(request, innerSegmentBoundary, &entryQueue[newEntry])

    // Sets removed field true if the new key and value were removed.
    let e = storage.lookup(entryQueue[newEntry])
    entryQueue[newEntry].removed = !e.isNull && e.entry.removed

    return newEntry
  }

  /// For the EXACT and RIGHT_PREFIX match, we will generate joined
  /// candidates by looking up the history link.
  /// Gets key value pair and assigns them to |result_key| and |result_value|
  /// for prediction result. The last entry which was joined
  /// will be assigned to |result_last_entry|.
  /// Returns false if we don't have the result for this match.
  /// |left_last_access_time| and |left_most_last_access_time| will be updated
  /// according to the entry lookup.
  /// If exact match results exist, return them first when |prefer_exact_match|
  /// is true.
  private func getKeyValueForExactAndRightPrefixMatch(
    _ request: ConversionRequest, _ requestKey: String, _ preferExactMatch: Bool,
    _ entry: Entry, _ resultLastEntry: inout Entry?, _ leftLastAccessTime: inout UInt64,
    _ leftMostLastAccessTime: inout UInt64, _ resultKey: inout String,
    _ resultValue: inout String, _ resultInnerSegmentBoundary: inout InnerSegmentBoundary
  ) -> Bool {
    var key = entry.key
    var value = entry.value
    var innerSegmentBoundaryBuilder = InnerSegmentBoundaryBuilder()
    appendInnerBoundary(request, &innerSegmentBoundaryBuilder, entry)

    var currentEntry = entry
    var seen = Set<BytePair>()
    seen.insert(BytePair(currentEntry.key, currentEntry.value))
    let requestKeySize = requestKey.utf8.count
    // Until target entry gets longer than request_key.
    while key.utf8.count <= requestKeySize {
      if preferExactMatch && key.utf8.count == requestKeySize {
        break
      }
      var latestEntry: Entry? = nil
      var leftSameTimestampEntry: Entry? = nil
      var leftMostSameTimestampEntry: Entry? = nil
      for fp in currentEntry.nextEntryFps {
        let tmpNextEntrySnapshot = storage.lookup(fp)
        if tmpNextEntrySnapshot.isNull || tmpNextEntrySnapshot.entry.key.utf8.isEmpty {
          continue
        }
        let tmpNextEntry = tmpNextEntrySnapshot.entry
        let mtypeJoined = Self.getMatchType(key + tmpNextEntry.key, requestKey)
        if mtypeJoined == .noMatch || mtypeJoined == .leftEmptyMatch {
          continue
        }
        if latestEntry == nil || latestEntry!.lastAccessTime < tmpNextEntry.lastAccessTime {
          latestEntry = tmpNextEntry
        }
        if tmpNextEntry.lastAccessTime == leftLastAccessTime {
          leftSameTimestampEntry = tmpNextEntry
        }
        if tmpNextEntry.lastAccessTime == leftMostLastAccessTime {
          leftMostSameTimestampEntry = tmpNextEntry
        }
      }

      // Prefer bigrams which are generated at the same time.
      // When last_access_time are the same, these two bigrams were
      // input together.
      // The preferences:
      // (1). The current entry's time stamp is equal to that of
      //      left most content word
      // (2). The current entry's time stamp is equal to that of
      //      left closest content word
      // (3). The current entry is the latest
      let nextEntry = leftMostSameTimestampEntry ?? leftSameTimestampEntry ?? latestEntry

      // Don't predict the next phrase if it starts with punctuation.
      guard let nextEntry, !nextEntry.key.utf8.isEmpty, !startsWithPunctuation(nextEntry.value)
      else {
        break
      }

      // If duplicate entry is found, don't expand more.
      // This is because an entry only has one timestamp.
      // we cannot trust the timestamp if there are duplicate values
      // in one input.
      if !seen.insert(BytePair(nextEntry.key, nextEntry.value)).inserted {
        break
      }

      key += nextEntry.key
      value += nextEntry.value
      appendInnerBoundary(request, &innerSegmentBoundaryBuilder, nextEntry)
      currentEntry = nextEntry
      resultLastEntry = nextEntry

      // Don't update left_access_time if the current entry is
      // not a content word.
      // The time-stamp of non-content-word will be updated frequently.
      // The time-stamp of the previous candidate is more trustful.
      // It partially fixes the bug http://b/2843371.
      let isContentWordValue = isContentWord(currentEntry.value)

      if isContentWordValue {
        leftLastAccessTime = currentEntry.lastAccessTime
      }

      // If left_most entry is a functional word (symbols/punctuations),
      // we don't take it as a canonical candidate.
      if leftMostLastAccessTime == 0 && isContentWordValue {
        leftMostLastAccessTime = currentEntry.lastAccessTime
      }
    }

    if key.utf8.count < requestKeySize {
      return false
    }

    resultInnerSegmentBoundary = innerSegmentBoundaryBuilder.build(key, value)
    resultKey = key
    resultValue = value
    return true
  }

  /// For the RIGHT_PREFIX match, we will generate a candidate with partially
  /// matching prefixes using a realtime_decoder.
  /// |entry_queue| is passed to keep track of other prefix match candidates.
  /// Prefix matching is only allowed when the prefix is a proper noun.
  /// When a non-proper-noun is more recent in LRU, we demote the current
  /// prefix matches in order to follow the LRU principle.
  /// |result_attribute| is passed to set various configurations of the
  /// result as it have different behaviors.
  private func getKeyValueForPartialMatch(
    _ request: ConversionRequest, _ requestKey: String, _ entry: Entry,
    _ resultKey: inout String, _ resultValue: inout String, _ resultAttribute: inout UInt32,
    _ resultInnerSegmentBoundary: inout InnerSegmentBoundary, _ entryQueue: EntryPriorityQueue
  ) -> Bool {
    if !requestKey.hasBytePrefix(entry.key) || entry.key.utf8.count >= requestKey.utf8.count {
      return false
    }

    // Records all partial match entries to keep track of LRU order of
    // partial matches.
    entryQueue.recordPartialEntry(entry)

    if !entry.allowPartialMatch {
      return false
    }

    let suffix = String(requestKey.byteSubstring(from: entry.key.utf8.count))

    // Do not allow too long suffix.
    let kMaxSuffixLen = 10
    if Util.charsLen(suffix) > kMaxSuffixLen {
      return false
    }

    // disallowed_count: partial match, but not a proper noun.
    //    allowed_count: partial match, proper noun.
    let (disallowedCount, allowedCount) = entryQueue.getPartialCount(entry.key)

    // Do not allow too many partial matches to reduce the call of DecodeSuffix.
    let kPartialMatchSize = 3
    if allowedCount > kPartialMatchSize {
      return false
    }

    // To follow the LRU principle, avoid promoting partial match candidates
    // if there is partial matches of general nouns.
    if disallowedCount > 0 {
      resultAttribute |= Attribute.weakCandidate
    }

    // Safe to assume that the suffix is personal name.
    // Adding personal name suffix to general proper noun is generally safe.
    // e.g., Adding "氏" rather than "市".
    let posMatcher = modules.getPosMatcher()
    let firstNameId = posMatcher.getFirstNameId()

    // Uses PREDICTION mode to call decoder_.
    var options = ConversionRequest.Options()
    options.maxConversionCandidatesSize = 1
    options.useActualConverterForRealtimeConversion = false
    options.requestType = .prediction
    let decoderRequest = ConversionRequestBuilder().setOptions(options).build()

    let fullResultOpt = decoder.decodeSuffix(decoderRequest, 0, requestKey)
    let suffixResultOpt = decoder.decodeSuffix(decoderRequest, firstNameId, suffix)

    // Failed to decode suffix.
    guard let fullResult = fullResultOpt, var suffixResult = suffixResultOpt else {
      return false
    }

    // Full result include the prefix-penalty cost and transition cost from BOS.
    // Adds them to the suffix_result.
    suffixResult.cost += Int(modules.getSegmenter().getPrefixPenalty(firstNameId))
    suffixResult.cost += modules.getConnector().getTransitionCost(0, firstNameId)

    // Returns true if the suffix_result.value ends at the boundary between
    // content word and functional word in full_result, and remaining
    // suffix is exactly the same.
    // e.g.,
    // [full=量|が, prefix=涼, suffix=が] => OK
    // [full=携帯,  prefix=慶太, suffix=い] => NG
    // [full=量|が行った,  prefix=涼, suffix=が言った] => NG (suffix is different)
    func isValidSuffix() -> Bool {
      var value = Substring(fullResult.value)
      for iter in fullResult.innerSegments() {
        value = value.byteSubstring(from: iter.contentValue.utf8.count)
        if value.utf8.isEmpty { return false }
        if value.bytesEqual(suffixResult.value) { return true }
        value = value.byteSubstring(from: iter.functionalValue.utf8.count)
      }
      return false
    }

    let params = request.request().decoderExperimentParams
    let prefixWcost = Int(params.userHistoryPartialPrefixWcost)
    let weakPrefixWcost = Int(params.userHistoryPartialWeakPrefixWcost)

    if suffixResult.cost + prefixWcost <= fullResult.cost || isValidSuffix() {
      // OK to use this candidate.
    } else if suffixResult.cost + weakPrefixWcost <= fullResult.cost {
      // OK, but ranked lower.
      resultAttribute |= Attribute.weakCandidate
    } else {
      return false
    }

    resultKey = entry.key + suffixResult.key
    resultValue = entry.value + suffixResult.value
    resultAttribute |= Attribute.populateInnerSegmentBoundary

    // For candidates that have never been input before, e.g. partial match
    // candidates, they are treated as standard conversions and their boundary
    // information is populated to the Result.
    resultInnerSegmentBoundary = {
      var innerSegmentBoundaryBuilder = InnerSegmentBoundaryBuilder()
      var isFirst = true
      for iter in suffixResult.innerSegments() {
        if isFirst {
          isFirst = false
          if posMatcher.isFunctional(suffixResult.lid) && iter.functionalKey.utf8.isEmpty
            && iter.functionalValue.utf8.isEmpty
          {
            // If the first element is a functional word, merge it into `entry`.
            innerSegmentBoundaryBuilder.add(
              entry.key.utf8.count + iter.key.utf8.count,
              entry.value.utf8.count + iter.value.utf8.count, entry.key.utf8.count,
              entry.value.utf8.count)
          } else {
            // If the first element is a content word, treat `entry` and this
            // element as independent segments.
            innerSegmentBoundaryBuilder.add(
              entry.key.utf8.count, entry.value.utf8.count, entry.key.utf8.count,
              entry.value.utf8.count)
            innerSegmentBoundaryBuilder.add(iter)
          }
        } else {
          innerSegmentBoundaryBuilder.add(iter)
        }
      }

      return innerSegmentBoundaryBuilder.build(resultKey, resultValue)
    }()

    return true
  }

  /// Returns true if the low frequency full sentence entry can be
  /// suggested.
  static func allowLowFreqFullSentenceEntryMatch(
    _ request: ConversionRequest, _ requestKey: String, _ mtype: MatchType, _ entry: Entry
  ) -> Bool {
    // exact match.
    if mtype == .exactMatch {
      return true
    }

    // prefix match.
    if mtype == .leftPrefixMatch {
      let innerSegments = InnerSegments(
        key: entry.key, value: entry.value, innerSegmentBoundary: entry.innerSegmentBoundary)
      // Returns true only when request_key reaches the key of the last segment.
      // key="わたしのな", entry="わたしの|なまえ" => OK
      // key="わたしの",   entry="わたしの|なまえ" => NG
      return innerSegments.getPrefixKeyAndValue(entry.innerSegmentBoundary.count - 1).key.utf8.count
        < requestKey.utf8.count
    }

    // partial match for compound nouns / proper nouns.
    // - key="たなかしょうてんは", entry="田中|商店"
    //   (allow_partial_match=true) => OK
    // - key="きのうはおつかれさまでしたけど", entry="昨日|は|お疲れ様|でした"
    //   (allow_partial_match=false) => NG
    if mtype == .rightPrefixMatch && entry.allowPartialMatch {
      return true
    }

    return false
  }

  /// If |entry| is the target of prediction,
  /// create a new result and insert it to |entry_queue|.
  /// Can set |prev_entry| if there is a history segment just before
  /// |request_key|. |prev_entry| is an optional field. If set nullptr, this
  /// field is just ignored. This method adds a new result entry with score,
  /// pair<score, entry>, to |entry_queue|.
  func lookupEntry(
    _ request: ConversionRequest, _ requestKey: String, _ keyBase: String,
    _ keyExpanded: Trie<String>?, _ entry: Entry, _ prevEntry: Entry?, _ exactMatchOnly: Bool,
    _ entryQueue: EntryPriorityQueue
  ) -> Bool {
    var result: Int? = nil

    var lastEntry: Entry? = nil

    // last_access_time of the left-closest content word.
    var leftLastAccessTime: UInt64 = 0

    // last_access_time of the left-most content word.
    var leftMostLastAccessTime: UInt64 = 0

    // Example: [a|B|c|D]
    // a,c: functional word
    // B,D: content word
    // left_last_access_time:   timestamp of D
    // left_most_last_access_time:   timestamp of B

    // |request_key| is a query user is now typing.
    // |entry->key()| is a target value saved in the database.
    //  const string request_key = key_base;

    let mtype = Self.getMatchTypeFromInput(requestKey, keyBase, keyExpanded, entry.key)

    if mtype == .noMatch {
      return false
    }

    // `exact_match_only` is called on the conversion that only requires exact
    // match result.
    // RIGHT_PREFIX_MATCH automatically fills the remaining suffix with
    // the logic of partial match.
    if exactMatchOnly && mtype != .rightPrefixMatch && mtype != .exactMatch {
      return false
    }

    // Full sentence with low frequency is suppressed unless
    // AllowLowFreqFullSentenceEntryMatch() returns true.
    if !exactMatchOnly && isLowFreqFullSentenceEntry(request, entry)
      && !Self.allowLowFreqFullSentenceEntryMatch(request, requestKey, mtype, entry)
    {
      return false
    }

    // For mobile, prefer exact match.
    let preferExactMatch = isMixedConversionEnabled(request) || exactMatchOnly

    leftLastAccessTime = entry.lastAccessTime
    leftMostLastAccessTime = isContentWord(entry.value) ? leftLastAccessTime : 0

    switch mtype {
    case .noMatch:
      // Should not reach here.
      return false
    case .leftEmptyMatch:
      // zero-query-suggestion
      // if |request_key| is empty, the |prev_entry| and |entry| must
      // have bigram relation.
      if Self.hasBigramEntry(request, entry, prevEntry) {
        result = addEntry(entry, entryQueue)
        lastEntry = entry
      }
    case .leftPrefixMatch:
      // |request_key| is shorter than |entry.key()|
      // This scenario is a simple prefix match.
      // e.g., |request_key|="foo", |entry.key()|="foobar"
      result = addEntry(entry, entryQueue)
      lastEntry = entry
    case .rightPrefixMatch:
      // |request_key| is longer than |entry.key()|.
      // In this case, recursively traverse "next_entries" until
      // target entry gets longer than request_key.
      // e.g., |request_key|="foobar", |entry.key()|="foo"
      var key = ""
      var value = ""
      var resultAttribute: UInt32 = 0
      var innerSegmentBoundary: InnerSegmentBoundary = []

      if !exactMatchOnly
        && getKeyValueForExactAndRightPrefixMatch(
          request, requestKey, preferExactMatch, entry, &lastEntry, &leftLastAccessTime,
          &leftMostLastAccessTime, &key, &value, &innerSegmentBoundary)
      {
        let r = addEntryWithNewKeyValue(
          request, key, value, innerSegmentBoundary, entry, entryQueue)
        setAttribute(&entryQueue[r], resultAttribute)
        result = r
      } else if getKeyValueForPartialMatch(
        request, requestKey, entry, &key, &value, &resultAttribute, &innerSegmentBoundary,
        entryQueue)
      {
        let r = addEntryWithNewKeyValue(
          request, key, value, innerSegmentBoundary, entry, entryQueue)
        setAttribute(&entryQueue[r], resultAttribute)
        result = r
      }
    case .exactMatch:
      // |request_key| is the same as |entry.key()|.
      if preferExactMatch {
        // For mobile, we don't generate joined result.
        result = addEntry(entry, entryQueue)
        lastEntry = entry
      } else {
        // In this case, recursively traverse "next_entries" until
        // target entry gets longer than request_key.
        // e.g., |request_key|="foobar", |entry.key()|="foo"
        var key = ""
        var value = ""
        var innerSegmentBoundary: InnerSegmentBoundary = []
        if getKeyValueForExactAndRightPrefixMatch(
          request, requestKey, preferExactMatch, entry, &lastEntry, &leftLastAccessTime,
          &leftMostLastAccessTime, &key, &value, &innerSegmentBoundary)
        {
          result = addEntryWithNewKeyValue(
            request, key, value, innerSegmentBoundary, entry, entryQueue)
        }
      }
    }

    guard let result else {
      return false
    }

    // If prev entry is not nullptr, check whether there is a bigram
    // from |prev_entry| to |entry|.
    removeAttribute(&entryQueue[result], Attribute.bigramBoost)

    if let prevEntry, mtype == .leftEmptyMatch {
      // When zero query suggestion, prev_entry and entry might not always typed
      // at the same time. Instead of using the unigram timestamp of prev_entry
      // and entry, we simply use the actual time of the bigram was generated.
      // GetBigramEntryLruOrder returns a larger value if the connection from
      // prev_entry to entry was made more recently.
      // (prev_entry->last_access_time() + 10 *GetBigramEntryLruOrder()) purely
      // prioritizes bigrams that were recently generated.
      //
      // Sets "prev_entry->last_access_time()" as the base time to compare
      // the preference with the entry typed prev_entry+current_entry as one
      // word. Suppose the case when there are two histories "東京駅"  and
      // 東京|大学", and NWP for 東京. We want to compare the timestamp of
      // "東京駅" and "東京大学" to decide the NWP, "駅" or "大学".
      if let order = Self.getBigramEntryLruOrder(entry, prevEntry) {
        let kBigramLinkAsTime: UInt32 = 10
        entryQueue[result].lastAccessTime =
          prevEntry.lastAccessTime &+ UInt64(kBigramLinkAsTime &* UInt32(order))
        // Attribute::BIGRAM_BOOST is set by HasBigramEntry() below.
      }
    }

    // Sets bigram_boost flag so that this entry is boosted against LRU policy.
    if Self.hasBigramEntry(request, entry, prevEntry) {
      setAttribute(&entryQueue[result], Attribute.bigramBoost)
    }

    // result with zero frequency is generated via revert operation.
    // zero frequency entry is suggested and the frequency is incremented
    // in Finish method.
    if !entryQueue[result].removed && entryQueue[result].suggestionFreq > 0 {
      entryQueue.push(result)
    }

    // For mobile or conversion mode, we don't generate joined result.
    if isMixedConversionEnabled(request) || exactMatchOnly {
      return true
    }

    // Generates joined result using |last_entry|.
    if let lastEntry, Util.charsLen(entryQueue[result].key) >= 1,
      2 * Util.charsLen(requestKey) >= Util.charsLen(entryQueue[result].key)
    {
      var latestEntry: Entry? = nil
      var leftSameTimestampEntry: Entry? = nil
      var leftMostSameTimestampEntry: Entry? = nil
      for fp in lastEntry.nextEntryFps {
        let tmpEntrySnapshot = storage.lookup(fp)
        if tmpEntrySnapshot.isNull || tmpEntrySnapshot.entry.key.utf8.isEmpty {
          continue
        }
        let tmpEntry = tmpEntrySnapshot.entry
        if latestEntry == nil || latestEntry!.lastAccessTime < tmpEntry.lastAccessTime {
          latestEntry = tmpEntry
        }
        if tmpEntry.lastAccessTime == leftLastAccessTime {
          leftSameTimestampEntry = tmpEntry
        }
        if tmpEntry.lastAccessTime == leftMostLastAccessTime {
          leftMostSameTimestampEntry = tmpEntry
        }
      }

      let nextEntry = leftMostSameTimestampEntry ?? leftSameTimestampEntry ?? latestEntry

      // The new entry was input within 10 seconds.
      // TODO(taku): This is a simple heuristics.
      if let nextEntry, !nextEntry.key.utf8.isEmpty,
        abs(Int32(truncatingIfNeeded: nextEntry.lastAccessTime &- lastEntry.lastAccessTime)) <= 10,
        !startsWithPunctuation(nextEntry.value), isContentWord(nextEntry.value)
      {
        var innerSegmentBoundaryBuilder = InnerSegmentBoundaryBuilder()
        appendInnerBoundary(request, &innerSegmentBoundaryBuilder, entryQueue[result])
        appendInnerBoundary(request, &innerSegmentBoundaryBuilder, nextEntry)
        let key = entryQueue[result].key + nextEntry.key
        let value = entryQueue[result].value + nextEntry.value
        let innerSegmentBoundary = innerSegmentBoundaryBuilder.build(key, value)
        let result2 = addEntryWithNewKeyValue(
          request, key, value, innerSegmentBoundary, entryQueue[result], entryQueue)
        if !entryQueue[result2].removed {
          entryQueue.push(result2)
        }
      }
    }

    return true
  }

  public func predict(_ request: ConversionRequest) -> [PredictionResult] {
    let isEmptyInput = request.key().utf8.isEmpty
    // Workaround for b/499745591
    // Predict() may be triggered when BS key is pressed, which is not expected.
    // Need to call MaybeProcessPartialRevertEntry when the new input has started.
    if !isEmptyInput {
      maybeProcessPartialRevertEntry(request)
    }

    if !shouldPredict(request) {
      return []
    }

    let prevEntrySnapshot = lookupPrevEntry(request)
    let prevEntry = prevEntrySnapshot.isNull ? nil : prevEntrySnapshot.entry
    let hasPrevContext = prevEntry != nil || isPrecedingNumber(request)
    if isEmptyInput && !hasPrevContext {
      return []
    }

    let params = request.request().decoderExperimentParams

    let isZeroQuery = isZeroQuerySuggestionEnabled(request) && isEmptyInput
    var maxPredictionSize = request.options().maxUserHistoryPredictionCandidatesSize
    let maxPredictionCharCoverage = Int(params.userHistoryPredictionMaxCharCoverage)

    if isZeroQuery {
      maxPredictionSize = request.options().maxUserHistoryPredictionCandidatesSizeForZeroQuery
    } else if maxPredictionCharCoverage > 0 {
      // When char coverage feature is enabled,
      // set a fixed value so that we can enumerate enough candidates.
      maxPredictionSize = 3
    }

    let entryQueue = createEntryQueueFromHistoryForPrediction(
      request, prevEntry, maxPredictionSize * 5)
    withExtendedLifetime(prevEntrySnapshot) {}

    if entryQueue.size == 0 {
      return []
    }

    return makeResults(request, maxPredictionSize, maxPredictionCharCoverage, entryQueue)
  }

  // TODO(taku): Make it a virtual method of PredictorInterface.
  public func convert(_ request: ConversionRequest) -> [PredictionResult] {
    if !shouldPredict(request) {
      return []
    }

    let prevEntrySnapshot = lookupPrevEntry(request)
    let prevEntry = prevEntrySnapshot.isNull ? nil : prevEntrySnapshot.entry

    let kMaxCandidatesSize = 5

    let entryQueue = createEntryQueueFromHistoryForConversion(
      request, prevEntry, kMaxCandidatesSize)
    withExtendedLifetime(prevEntrySnapshot) {}

    if entryQueue.size == 0 {
      return []
    }

    return makeResults(request, kMaxCandidatesSize, 0 /* max_prediction_char_coverage */, entryQueue)
  }

  /// Returns true if this predictor should return results for the input.
  /// TODO(taku): better to rename this function as it is used both for
  /// prediction and conversion.
  func shouldPredict(_ request: ConversionRequest) -> Bool {
    if storage.isSyncerInCriticalSection() {
      return false
    }

    if storage.isEmpty() {
      return false
    }

    if request.incognitoMode() {
      return false
    }

    if request.config().historyLearningLevel == .noHistory {
      return false
    }

    let requestKey = request.key()

    // Prediction/suggestion specific rules.
    let requestType = request.requestType()
    if requestType == .suggestion || requestType == .prediction
      || requestType == .partialSuggestion || requestType == .partialPrediction
    {
      if requestKey.utf8.isEmpty && !isZeroQuerySuggestionEnabled(request) {
        return false
      }

      if !request.config().useHistorySuggest {
        return false
      }

      if startsWithPunctuation(requestKey) {
        return false
      }
    } else if requestType == .conversion {
      if requestKey.utf8.isEmpty {
        return false
      }
    }

    return true
  }

  func lookupPrevEntry(_ request: ConversionRequest) -> ConstEntrySnapshot {
    var prevEntry = storage.nullEntry()

    // When there are non-zero history segments, lookup an entry
    // from the LRU dictionary, which is corresponding to the last
    // history segment.
    if request.converterHistorySize() == 0 {
      return prevEntry
    }

    // Finds the prev_entry from the longest context.
    // Even when the original value is split into content_value and suffix,
    // longest context information is used.
    var size = request.converterHistorySize()
    while size >= 1 {
      let suffixKey = request.converterHistoryKey(size)
      let suffixValue = request.converterHistoryValue(size)
      let entry = storage.lookup(suffixKey, suffixValue)
      if !entry.isNull {
        prevEntry = entry
        break
      }
      size -= 1
    }

    // When |prev_entry| is nullptr or |prev_entry| has no valid next_entries,
    // do linear-search over the LRU.
    if prevEntry.isNull || prevEntry.entry.nextEntryFps.isEmpty {
      let prevValue = prevEntry.isNull ? request.converterHistoryValue(1) : prevEntry.entry.value
      let prevFp = prevEntry.fingerprint

      let lruPrevEntry = storage.findIf(
        { fp, entry in
          // entry.value() equals to the prev_value or
          // entry.value() is a SUFFIX of prev_value.
          // length of entry.value() must be >= 2, as single-length
          // match would be noisy.
          return isValidEntry(entry) && fp != prevFp && !entry.nextEntryFps.isEmpty
            && Util.charsLen(entry.value) >= 2
            && (entry.value.bytesEqual(prevValue) || prevValue.hasByteSuffix(entry.value))
        }, kMaxPrevValueTrial)

      if !lruPrevEntry.isNull {
        prevEntry = lruPrevEntry
      }
    }

    return prevEntry
  }

  /// Creates entry queue from request and history storage on prediction mode.
  func createEntryQueueFromHistoryForPrediction(
    _ request: ConversionRequest, _ prevEntry: Entry?, _ maxEntryQueueSize: Int
  ) -> EntryPriorityQueue {
    // Gets romanized input key if the given preedit looks misspelled.
    let romanRequestKey = Self.getRomanMisspelledKey(request)

    let corrected = getTypingCorrectedQueries(request)

    // If we have ambiguity for the input, get expanded key.
    // Example1 roman input: for "あk", we will get |base|, "あ" and |expanded|,
    // "か", "き", etc
    // Example2 kana input: for "あか", we will get |base|, "あ" and |expanded|,
    // "か", and "が".

    // |base_key| and |request_key| could be different
    // For kana-input, we will expand the ambiguity for "゛".
    // When we input "もす",
    // |base_key|: "も"
    // |expanded|: "す", "ず"
    // |request_key|: "もす"
    // In this case, we want to show candidates for "もす" as EXACT match,
    // and candidates for "もず" as LEFT_PREFIX_MATCH
    //
    // For roman-input, when we input "あｋ",
    // |request_key| is "あｋ" and |base_key| is "あ"
    let (requestKey, baseKey, expanded) = Self.getInputKeyFromRequest(request)

    let entryQueue = EntryPriorityQueue()

    storage.forEach { fp, entry in
      // already found enough entry_queue.
      if entryQueue.size >= maxEntryQueueSize {
        return false
      }

      if !isValidEntryIgnoringRemovedField(entry) {
        return true
      }

      let kDisableExactMatchOnly = false

      // Lookup key from elm_value and prev_entry.
      // If a new entry is found, the entry is pushed to the entry_queue.
      if lookupEntry(
        request, requestKey, baseKey, expanded, entry, prevEntry, kDisableExactMatchOnly,
        entryQueue)
      {
        return true
      }

      // Full sentence entry is not reused in non-standard lookup, e.g.
      // RomanFuzzy, ZeroQuery, and Typing correction.
      if isLowFreqFullSentenceEntry(request, entry) {
        return true
      }

      // Non-standard lookup.
      if romanFuzzyLookupEntry(romanRequestKey, entry, entryQueue)
        || zeroQueryLookupEntry(request, requestKey, entry, prevEntry, entryQueue)
      {
        return true
      }

      // Lookup typing corrected keys when the original `request_key` doesn't
      // match. Since dic_ is sorted in LRU, typing corrected queries are ranked
      // lower than the original key.
      for c in corrected {
        // Only apply when score > 0. When score < 0, we trigger literal-on-top
        // in dictionary predictor.
        if c.score > 0.0
          && lookupEntry(
            request, c.correction, c.correction, nil, entry, prevEntry, kDisableExactMatchOnly,
            entryQueue)
        {
          break
        }
      }

      return true
    }

    return entryQueue
  }

  /// Creates entry queue from request and history storage on conversion mode.
  func createEntryQueueFromHistoryForConversion(
    _ request: ConversionRequest, _ prevEntry: Entry?, _ maxEntryQueueSize: Int
  ) -> EntryPriorityQueue {
    let requestKey = request.composer().getQueryForConversion()
    let entryQueue = EntryPriorityQueue()

    storage.forEach { fp, entry in
      // already found enough entry_queue.
      if entryQueue.size >= maxEntryQueueSize {
        return false
      }

      if !isValidEntryIgnoringRemovedField(entry) {
        return true
      }

      let kEnableExactMatchOnly = true

      if lookupEntry(
        request, requestKey, requestKey, nil, entry, prevEntry, kEnableExactMatchOnly, entryQueue)
      {
        return true
      }

      return true
    }

    return entryQueue
  }

  /// Gets input data from segments.
  /// These input data include ambiguities.
  /// return [request_key, base, expanded]
  static func getInputKeyFromRequest(_ request: ConversionRequest) -> (
    String, String, Trie<String>?
  ) {
    let requestKey = request.composer().getStringForPreedit()
    let (queryBase, expandedSet) = request.composer().getQueriesForPrediction()
    var expanded: Trie<String>? = nil
    if !expandedSet.isEmpty {
      let trie = Trie<String>()
      for expandedKey in expandedSet {
        // For getting matched key, insert values
        trie.addEntry(expandedKey, expandedKey)
      }
      expanded = trie
    }

    return (requestKey, queryBase, expanded)
  }

  /// Rewrite the prefix white spaces in result.(value|key) to
  /// full or half width form depending on the config.
  /// If display_value capability is available, sets result.display_value.
  static func maybeRewritePrefixSpace(_ request: ConversionRequest, _ result: inout PredictionResult)
  {
    // The space prefix in `result`. This prefix may be modified to
    // the actual `output_space_prefix`.
    var resultSpacePrefix = ""

    // We had added kPrefixFullSpace in the old code as a placeholder.
    // Serialized entry uses kPrefixZeroSpace to normalize the space.
    for prefix in [kPrefixZeroSpace, kPrefixFullSpace, kPrefixHalfSpace] {
      if result.key.hasBytePrefix(prefix) && result.value.hasBytePrefix(prefix) {
        resultSpacePrefix = prefix
        break
      }
    }

    if resultSpacePrefix.utf8.isEmpty { return }

    // Clears inner_segment_boundary because the prefix space may break the
    // internal offsets.
    result.innerSegmentBoundary.removeAll()

    let prefixSize = resultSpacePrefix.utf8.count

    // Replaces the space in display_value: " ラーメン" -> "␣ラーメン"
    if request.request().displayValueCapability == .plainText {
      result.displayValue = kPrefixDisplaySpace + String(result.value.byteSubstring(from: prefixSize))
    }

    // Uses the half-width space in half-width-Latin mode.
    let isLatinMode = request.composer().getInputMode() == .halfAscii
    let cform = request.config().spaceCharacterForm
    let outputSpacePrefix =
      (cform == .fundamentalHalfWidth || isLatinMode) ? kPrefixHalfSpace : kPrefixFullSpace
    if !resultSpacePrefix.bytesEqual(outputSpacePrefix) {
      result.key = outputSpacePrefix + String(result.key.byteSubstring(from: prefixSize))
      result.value = outputSpacePrefix + String(result.value.byteSubstring(from: prefixSize))
    }
  }

  func makeResults(
    _ request: ConversionRequest, _ maxPredictionSize: Int, _ maxPredictionCharCoverage: Int,
    _ entryQueue: EntryPriorityQueue
  ) -> [PredictionResult] {
    var insertedCharCoverage = 0

    var entries: [Int] = []
    entries.reserveCapacity(entryQueue.size)

    // Current LRU-based candidates = ["東京"]
    //  target="東京は" -> Remove.   (target is longer)
    //  target="東"     -> Keep.     (target is shorter)
    // Current LRU-based candidates = ["東京は"]
    //   target="東京" -> Replace "東京は" and "東京"

    func startsWith(_ text: String, _ prefix: String) -> Bool {
      text.hasBytePrefix(prefix)
        && Util.isScriptType(text.byteSubstring(from: prefix.utf8.count), .hiragana)
    }

    func isRedandant(_ target: String, _ inserted: String) -> Bool {
      startsWith(target, inserted)
    }

    func isRedandantEntry(_ entry: Entry) -> Bool {
      entries.contains { insertedEntry in
        isRedandant(entry.value, entryQueue[insertedEntry].value)
      }
    }

    // Replace `entry` with the one entry in `entries`.
    func maybeReplaceEntry(_ entry: Int) -> Bool {
      guard
        let it = entries.firstIndex(where: { insertedEntry in
          startsWith(entryQueue[insertedEntry].value, entryQueue[entry].value)
        })
      else {
        return false
      }
      insertedCharCoverage -= Util.charsLen(entryQueue[entries[it]].value)
      insertedCharCoverage += Util.charsLen(entryQueue[entry].value)
      entries[it] = entry

      return true
    }

    while entries.count < maxPredictionSize {
      // |entry_queue| is a priority queue where the element
      // in the queue is sorted by the score defined in GetScore().
      guard let resultEntry = entryQueue.pop() else {
        // Pop() returns nullptr when no more valid entry exists.
        break
      }

      // Suppress broken utf8 string just in case.
      if !Util.isValidUtf8(entryQueue[resultEntry].value) {
        continue
      }

      // Check candidate redundancy.
      if isRedandantEntry(entryQueue[resultEntry]) || maybeReplaceEntry(resultEntry) {
        continue
      }

      // Break when the accumulated character length exceeds the
      // `max_prediction_char_coverage`. Allows to add at least one candidate.
      let valueLen = Util.charsLen(entryQueue[resultEntry].value)
      if maxPredictionCharCoverage > 0 && !entries.isEmpty
        && insertedCharCoverage + valueLen > maxPredictionCharCoverage
      {
        break
      }

      entries.append(resultEntry)
      insertedCharCoverage += valueLen
    }

    var results: [PredictionResult] = []
    results.reserveCapacity(entries.count)

    for index in entries {
      let resultEntry = entryQueue[index]
      var result = PredictionResult()
      result.key = resultEntry.key
      result.value = resultEntry.value
      result.attributes |=
        GenmaiCore.Attribute.userHistoryPrediction | GenmaiCore.Attribute.noVariantsExpansion
      if resultEntry.innerSegmentBoundary.isEmpty
        || (resultEntry.attributes & Attribute.emptyInnerSegmentBoundary) != 0
      {
        result.attributes |= GenmaiCore.Attribute.userHistoryEmptyInnerSegmentBoundary
      }
      // Do not populate inner segment information from entry to result for
      // prediction, as this information may introduce unexpected side-effect
      // during training. Inner segment information should be populated for
      // conversion requests or when explicitly requested by
      // POPULATE_INNER_SEGMENT_BOUNDARY (e.g. from realtime decoder).
      if request.requestType() == .conversion
        || (resultEntry.attributes & Attribute.populateInnerSegmentBoundary) != 0
      {
        // POPULATE_INNER_SEGMENT_BOUNDARY is set when the `result_entry` is
        // `generated` by the decoder.
        result.innerSegmentBoundary = resultEntry.innerSegmentBoundary
      }
      if (resultEntry.attributes & Attribute.spellingCorrection) != 0 {
        result.attributes |= GenmaiCore.Attribute.spellingCorrection
      }
      if (resultEntry.attributes & Attribute.weakCandidate) != 0 {
        result.attributes |= GenmaiCore.Attribute.weakUserHistoryPrediction
      } else if isMixedConversionEnabled(request) && !request.key().utf8.isEmpty
        && resultEntry.innerSegmentBoundary.count > 1
      {
        // b/555130585: In mobile mixed conversion, demote multi-segment prefix
        // history candidates when input has not reached the last segment (e.g.,
        // "きょうは" for "今日は行った", or "きょうはえきに" for
        // "今日は駅に行った") to prevent displacing shorter single-segment
        // candidates from the limited mobile suggestion strip.
        //
        // Background: Previously, this ranking behavior was not explicitly
        // designed, but occurred as an unintended side effect of invoking
        // UserSegmentHistoryRewriter twice:
        // 1) First inside RealtimeDecoder::Decode when generating conversion
        //    candidates.
        // 2) Second in Converter::ApplyPostProcessing after Predictor merged
        //    UserHistoryPredictor and DictionaryPredictor candidates.
        // In the second pass, UserSegmentHistoryRewriter assigned score > 0 only
        // to exact-match candidates (key == request.key()) and score == 0 to
        // predictive candidates (both multi-segment prefix history and dictionary
        // prefix completions), implicitly promoting exact-match candidates above
        // multi-segment prefix history.
        //
        // TODO(taku): This WEAK_USER_HISTORY_PREDICTION tagging and
        // desktop/mobile branching exist as a workaround to reproduce the legacy
        // 2-pass rewriter side effect without regressions. Once the
        // UserSegmentHistoryRewriter migration is complete, refactor and simplify
        // the scoring/ranking pipeline so that exact-match vs. predictive
        // candidate priority is handled cleanly without multi-bucket demotion or
        // platform-specific workarounds.
        let innerSegments = InnerSegments(
          key: resultEntry.key, value: resultEntry.value,
          innerSegmentBoundary: resultEntry.innerSegmentBoundary)
        let prefixBeforeLastSegmentLen = innerSegments.getPrefixKeyAndValue(
          resultEntry.innerSegmentBoundary.count - 1
        ).key.utf8.count
        if request.key().utf8.count <= prefixBeforeLastSegmentLen {
          result.attributes |= GenmaiCore.Attribute.weakUserHistoryPrediction
        }
      }
      if (resultEntry.attributes & Attribute.bigramBoost) != 0 {
        result.attributes |= GenmaiCore.Attribute.bigram
      }

      let description = resultEntry.description_p
      // If we have stored description, set it exactly.
      if !description.utf8.isEmpty {
        result.description = description
        result.attributes |= GenmaiCore.Attribute.noExtraDescription
      }

      // Normalize character form based on CharacterFormManager preferences
      // (b/554421471).
      // TODO(taku): This is a transitional workaround to resolve the mobile
      // toggle-show-more regression caused by the UserSegmentHistoryRewriter
      // migration.
      //
      // Root cause and architectural flaw:
      // User history prediction candidates unconditionally have
      // `Attribute::NO_VARIANTS_EXPANSION` attached (set above). While the
      // original intent was to prevent downstream VariantsRewriter from polluting
      // candidate lists with unwanted full/half-width variant expansions
      // (EXPAND), VariantsRewriter treats NO_VARIANTS_EXPANSION as a hard bypass
      // for BOTH expansion and dynamic normalization (SELECT). As a result, user
      // history candidates are never normalized by VariantsRewriter according to
      // current CharacterFormManager preferences.
      //
      // A fundamental architectural redesign is required:
      // 1. Separate candidate expansion (generating alternative variant entries)
      //    from character form normalization (aligning rank-0 candidates to
      //    user preferences).
      // 2. Unify all variant and character form processing (normalization,
      //    expansion, deduplication, and commit learning) cleanly inside
      //    VariantsRewriter across all candidate sources, rather than having
      //    UserHistoryPredictor, NumberRewriter, and VariantsRewriter perform
      //    fragmented, localized normalization.
      if Util.getScriptType(result.value) == .number {
        let manager = CharacterFormManager.getCharacterFormManager()
        rewriteCandidateValues({ s in manager.convertConversionString(s) }, &result)
      }

      Self.maybeRewritePrefixSpace(request, &result)

      results.append(result)
    }

    return results
  }

  /// Inserts a new |fp| into |entry|.
  /// it makes a bigram connection from entry to next_entry.
  static func insertNextEntry(_ fp: UInt64, _ entry: inout Entry) {
    if fp == 0 {
      return
    }

    // Emulates LRU. next_fps.back() is the latest fp.
    // Here we remove all elements equal to `fp` to de-dup the next_fps.
    entry.nextEntryFps.removeAll { $0 == fp }
    entry.nextEntryFps.append(fp)  // always push to the last.

    // Removes the older items when the size exceeds the capacity.
    // The top elements are older.
    if entry.nextEntryFps.count > kMaxNextEntriesSize {
      entry.nextEntryFps.removeFirst(entry.nextEntryFps.count - kMaxNextEntriesSize)
    }
  }

  /// Returns true if entry is DEFAULT_ENTRY, satisfies certain conditions, and
  /// doesn't have removed flag.
  func isValidEntry(_ entry: Entry) -> Bool {
    !entry.removed && isValidEntryIgnoringRemovedField(entry)
  }

  /// The same as IsValidEntry except that removed field is ignored.
  func isValidEntryIgnoringRemovedField(_ entry: Entry) -> Bool {
    if userDictionary.isSuppressedEntry(entry.key, entry.value) {
      return false
    }

    if isEmojiEntry(entry) && isAndroidPuaEmoji(entry.value) {
      return false
    }

    if entry.key.hasByteSuffix(" ") {
      // Invalid user history entry from alphanumeric input.
      return false
    }

    return true
  }

  /// Inserts |key,value,description| to the internal dictionary database.
  /// |inner_segment_boundary| inner segment boundary information.
  /// |key_begin,value_begin|: string byte offset on result.(key|value).
  /// |next_fp|: fingerprints of the next segment.
  /// |allow_partial_match|: allow key/value to be a content_key/value.
  /// |last_access_time|: the time when this entry was created.
  /// Entry's contents and request_type will be checked before insertion.
  func insert(
    _ request: ConversionRequest, _ keyBegin: Int32, _ valueBegin: Int32, _ key: String,
    _ value: String, _ description: String, _ innerSegmentBoundary: InnerSegmentBoundary,
    _ nextFps: [UInt64], _ allowPartialMatch: Bool, _ lastAccessTime: UInt64,
    _ revertEntries: inout RevertEntries, _ entryFlags: UInt32 = 0
  ) {
    // b/279560433: Preprocess key value
    // (key|value)_begin don't change after StripTrailingAsciiWhitespace.
    let key = stripTrailingAsciiWhitespace(key)
    let value = stripTrailingAsciiWhitespace(value)

    if !Util.isValidUtf8(key) || !Util.isValidUtf8(value) {
      return
    }

    if key.utf8.isEmpty || value.utf8.isEmpty || key.utf8.count > kMaxStringLength
      || value.utf8.count > kMaxStringLength || description.utf8.count > kMaxStringLength
    {
      return
    }

    // Do not remember text that ends with a punctuation.
    // This case happens when user type "よろしく。" or "hello," directly via
    // composer.
    if startsWithValidLetter(value) && endsWithPunctuation(value) {
      return
    }

    // Okay ready to insert.
    let fp = UserHistoryStorage.fingerprint(key, value)

    let hasFp = storage.contains(fp)
    let entry = storage.insert(fp)
    if entry.isNull {
      return
    }

    // `entry` might be reused from the heap, so explicitly clear.
    if !hasFp {
      entry.entry = Entry()
    }

    entry.entry.key = String(key)
    entry.entry.value = String(value)
    entry.entry.removed = false
    entry.entry.clearAttributes()
    if entryFlags != 0 {
      entry.entry.entryFlags = entry.entry.entryFlags | entryFlags
    }

    if allowPartialMatch { entry.entry.allowPartialMatch = true }

    if description.utf8.isEmpty {
      entry.entry.clearDescription_p()
    } else {
      entry.entry.description_p = description
    }

    maybePopulateInnerSegmentBoundary(request, innerSegmentBoundary, &entry.entry)

    revertEntries.entries.append((keyBegin, valueBegin, entry.entry))

    entry.entry.lastAccessTime = lastAccessTime
    entry.entry.suggestionFreq = entry.entry.suggestionFreq + 1

    // Inserts next_fp to the entry
    for nextFp in nextFps {
      Self.insertNextEntry(nextFp, &entry.entry)
    }
  }

  /// Removes history entries when the selected ratio is under the threshold.
  /// Selected ratio:
  ///  (# of candidate committed) / (# of candidate shown on commit event)
  func maybeRemoveUnselectedHistory(
    _ results: [PredictionResult], _ revertEntries: inout RevertEntries
  ) {
    let kMaxHistorySize = 5
    let kMinSelectedRatio: Float = 0.05

    for i in 0..<min(results.count, kMaxHistorySize) {
      let entry = storage.mutableLookup(results[i].key, results[i].value)
      if entry.isNull {
        continue
      }
      // Note(b/339742825): For now shown freq is only used here and it's OK to
      // increment the value here.
      entry.entry.shownFreq = entry.entry.shownFreq + 1

      let selectedRatio = Float(
        1.0 * Double(entry.entry.suggestionFreq) / Double(entry.entry.shownFreq))

      if selectedRatio < kMinSelectedRatio {
        var revertEntry = entry.entry
        revertEntry.shownFreq = UInt32(max(0, Int(entry.entry.shownFreq) - 1))
        revertEntries.entries.append((0, 0, revertEntry))

        entry.entry.suggestionFreq = 0
        entry.entry.shownFreq = 0
        entry.entry.removed = true
        continue
      }
    }
  }

  /// Hook(s) for all mutable operations.
  public func finish(_ request: ConversionRequest, _ results: [PredictionResult], _ revertId: UInt32)
  {
    if request.incognitoMode() {
      return
    }

    if request.config().historyLearningLevel != .defaultHistory {
      return
    }

    if !request.config().useHistorySuggest {
      return
    }

    if storage.isSyncerInCriticalSection() {
      return
    }

    lastCommittedEntries.withLock { $0 = nil }

    guard let front = results.first, (front.attributes & GenmaiCore.Attribute.noSuggestLearning) == 0
    else {
      return
    }

    if isPrivacySensitive(results) {
      return
    }

    var revertEntries = RevertEntries()

    let learningSegments = makeLearningSegments(request, results)

    insertHistory(request, learningSegments, &revertEntries)

    maybeRemoveUnselectedHistory(results, &revertEntries)

    if !revertEntries.entries.isEmpty {
      revertEntries.result = front
      revertCache.insert(revertId, revertEntries)
    }
  }

  /// `request.history_result()` as a PredictionResult.
  static func historyResult(_ request: ConversionRequest) -> PredictionResult {
    let history = request.historyResult()
    if let result = history as? PredictionResult {
      return result
    }
    if let view = history as? any PredictionHistoryResultConvertible {
      return view.historyPredictionResult
    }
    return PredictionResult.defaultResult
  }

  func makeLearningSegments(_ request: ConversionRequest, _ results: [PredictionResult])
    -> SegmentsForLearning
  {
    var learningSegments = SegmentsForLearning()

    guard let result = results.first else { return learningSegments }

    func getSpacePrefix() -> String {
      let precedingText = request.context().precedingText
      for spaceChar in [kPrefixHalfSpace, kPrefixFullSpace] {
        if precedingText.hasByteSuffix(spaceChar) {
          return spaceChar
        }
      }
      return ""
    }

    func makeLearningSegments(_ result: PredictionResult) -> [SegmentForLearning] {
      var segments: [SegmentForLearning] = []
      let innerSegments = result.innerSegments()
      segments.reserveCapacity(innerSegments.size)

      // Note: History predictions are currently learned as single segments
      // even if they have boundaries in storage. This is because
      // `result.inner_segment_boundary` is not populated for
      // `USER_HISTORY_PREDICTION` results in `MakeResults`.
      let isSingleSegment = innerSegments.size <= 1
      // TODO(taku): result.(key|value) may start with kPrefixZeroSpace.
      // It would be better to remove them to increase the coverage
      // of bigram-prediction.
      for iter in innerSegments {
        let keyBegin = iter.key.base.utf8.distance(
          from: iter.key.base.startIndex, to: iter.key.startIndex)
        let valueBegin = iter.value.base.utf8.distance(
          from: iter.value.base.startIndex, to: iter.value.startIndex)
        segments.append(
          SegmentForLearning(
            keyBegin: Int32(keyBegin), valueBegin: Int32(valueBegin), key: String(iter.key),
            value: String(iter.value), contentKey: String(iter.contentKey),
            contentValue: String(iter.contentValue),
            description: isSingleSegment ? getDescription(result) : ""))
      }

      return segments
    }

    // Returns [Segments, whether_contains_space_prefix]
    func makeHistoryLearningSegments(_ result: PredictionResult) -> ([SegmentForLearning], Bool) {
      let kHasPrefixSpace = true

      let segments = makeLearningSegments(result)

      let spacePrefix = getSpacePrefix()
      if !segments.isEmpty || spacePrefix.utf8.isEmpty {
        return (segments, !spacePrefix.utf8.isEmpty)
      }

      let fullPrecedingText = request.context().precedingText
      let precedingText = fullPrecedingText.byteSubstring(
        from: 0, length: fullPrecedingText.utf8.count - spacePrefix.utf8.count)

      let headEntry = storage.head()
      if headEntry.isNull || !precedingText.hasByteSuffix(headEntry.entry.value) {
        return (segments, !kHasPrefixSpace)
      }

      // When `head` has functional value, head->next may store the context_value.
      // We only suggest space-prefixed suggestion only when noun to noun case.
      // TODO(taku): Better to use inner boundary information.
      let headNextEntry = storage.headNext()
      if !headNextEntry.isNull && headEntry.entry.value.hasBytePrefix(headNextEntry.entry.value) {
        return (segments, !kHasPrefixSpace)
      }

      let head = headEntry.entry
      var newSegments = segments
      newSegments.append(
        SegmentForLearning(
          keyBegin: 0, valueBegin: 0, key: head.key, value: head.value, contentKey: head.key,
          contentValue: head.value))

      return (newSegments, kHasPrefixSpace)
    }

    learningSegments.conversionSegmentsKey = result.key
    learningSegments.conversionSegmentsValue = result.value
    (learningSegments.historySegments, learningSegments.hasSpacePrefix) =
      makeHistoryLearningSegments(Self.historyResult(request))
    learningSegments.conversionSegments = makeLearningSegments(result)
    learningSegments.innerSegmentBoundary = result.innerSegmentBoundary
    learningSegments.allowPartialMatch = shouldAllowPartialMatch(
      request, result, learningSegments)

    return learningSegments
  }

  func insertHistory(
    _ request: ConversionRequest, _ learningSegments: SegmentsForLearning,
    _ revertEntries: inout RevertEntries
  ) {
    let lastAccessTime = UInt64(Clock.getUnixSeconds())

    insertHistoryForConversionSegments(request, lastAccessTime, learningSegments, &revertEntries)
    insertHistoryForHistorySegments(request, lastAccessTime, learningSegments, &revertEntries)
  }

  func insertHistoryForHistorySegments(
    _ request: ConversionRequest, _ lastAccessTime: UInt64,
    _ learningSegments: SegmentsForLearning, _ revertEntries: inout RevertEntries
  ) {
    // Makes a link from the last history_segment to the first conversion
    // segment or to the entire user input.
    guard let historySegment = learningSegments.historySegments.last,
      let conversionSegment = learningSegments.conversionSegments.first
    else {
      return
    }
    let historyValue = historySegment.value
    if historyValue.utf8.isEmpty || conversionSegment.value.utf8.isEmpty {
      return
    }

    let endsWithPunctuationValue = endsWithPunctuation(historyValue)

    // 1) Don't learn a link from a history which ends with punctuation.
    if endsWithPunctuationValue {
      return
    }

    let startsWithPunctuationValue = startsWithPunctuation(conversionSegment.value)

    // 2) Don't learn a link to a punctuation.
    // Exception: For zero query suggestion, we learn a link to a single
    //            punctuation segment.
    // Example: "よろしく|。" -> OK
    //          "よろしく|。でも" -> NG
    //          "よろしく|。。" -> NG
    // In the suggestion phase, we do not allow the bigram connection where
    // right-hand-side words start with a punctuation mark. The prediction
    // of punctuation marks is only triggered on zero-query suggestions.
    if Util.charsLen(conversionSegment.value) > 1 && startsWithPunctuationValue {
      return
    }

    // When there is a space between the history and current token,
    // do not allow the punctuation.
    if learningSegments.hasSpacePrefix && (startsWithPunctuationValue || endsWithPunctuationValue) {
      return
    }

    let historyEntry = storage.mutableLookup(Self.learningSegmentFingerprint(historySegment))
    if historyEntry.isNull {
      return
    }

    revertEntries.historyEntry = historyEntry.entry

    if learningSegments.hasSpacePrefix {
      // Space is mainly used to make a search query, e.g. ラーメン_渋谷.
      // So the next word would mainly be a noun. We only predict space-prefixed
      // word when the next word has no functional word.
      if conversionSegment.key.bytesEqual(conversionSegment.contentKey)
        && conversionSegment.value.bytesEqual(conversionSegment.contentValue)
      {
        // Uses zero-width space as an internal representation of prefix-space.
        let key = kPrefixZeroSpace + conversionSegment.key
        let value = kPrefixZeroSpace + conversionSegment.value
        // NOTE: faithful to C++, which passes `last_access_time, false` in the
        // (allow_partial_match, last_access_time) positions: the entry gets
        // allow_partial_match = (last_access_time != 0) and
        // last_access_time = 0.
        insert(
          request, 0, 0, key, value, "", [], [], lastAccessTime != 0,
          0 /* false, allow_partial_match in the C++ comment */, &revertEntries)
        Self.insertNextEntry(UserHistoryStorage.fingerprint(key, value), &historyEntry.entry)
      }
    } else {
      for nextFp in learningSegmentFingerprints(conversionSegment) {
        Self.insertNextEntry(nextFp, &historyEntry.entry)
      }
    }
  }

  func insertHistoryForConversionSegments(
    _ request: ConversionRequest, _ lastAccessTime: UInt64,
    _ learningSegments: SegmentsForLearning, _ revertEntries: inout RevertEntries
  ) {
    // Inserts all_key/all_value.
    // We don't insert it for mobile.
    if learningSegments.conversionSegments.count > 1 {
      insert(
        request, 0, 0, learningSegments.conversionSegmentsKey,
        learningSegments.conversionSegmentsValue, "", learningSegments.innerSegmentBoundary, [],
        learningSegments.allowPartialMatch, /* allow_partial_match */
        lastAccessTime, &revertEntries)
    }

    var seen = Set<[UInt64]>()
    var thisWasSeen = false
    var prevValue = learningSegments.historySegments.last?.value ?? ""
    let conversionSegments = learningSegments.conversionSegments
    for i in 0..<conversionSegments.count {
      let segment = conversionSegments[i]
      var nextFps: [UInt64] = []
      if i + 1 < conversionSegments.count {
        nextFps = learningSegmentFingerprints(conversionSegments[i + 1])
      }
      // remember the first segment
      if i == 0 {
        seen.insert(learningSegmentFingerprints(segment))
      }
      var nextFpsToSet = nextFps
      // If two duplicate segments exist, kills the link
      // TO/FROM the second one to prevent loops.
      // Only killing "TO" link caused bug #2982886:
      // after converting "らいおん（もうじゅう）とぞうりむし（びせいぶつ）"
      // and typing "ぞうりむし", "ゾウリムシ（猛獣" was suggested.
      if thisWasSeen {
        nextFpsToSet.removeAll()
      }
      if !seen.insert(nextFps).inserted {
        nextFpsToSet.removeAll()
        thisWasSeen = true
      } else {
        thisWasSeen = false
      }

      let hasContentKv =
        !segment.contentKey.bytesEqual(segment.key) && !segment.contentValue.bytesEqual(segment.value)

      let entryFlags =
        (Util.getScriptType(prevValue) == .number) ? EntryFlag.leftNumber : EntryFlag.none

      var innerSegmentBoundary: InnerSegmentBoundary = []
      if hasContentKv {
        let allowPartialMatch = (i == 0 && learningSegments.allowPartialMatch)
        innerSegmentBoundary = buildInnerSegmentBoundary(
          [
            (
              segment.key.utf8.count, segment.value.utf8.count, segment.contentKey.utf8.count,
              segment.contentValue.utf8.count
            )
          ], segment.key, segment.value)
        insert(
          request, segment.keyBegin, segment.valueBegin, segment.contentKey, segment.contentValue,
          segment.description, [], [], allowPartialMatch, lastAccessTime, &revertEntries,
          entryFlags)
      }

      let allowPartialMatch = (i == 0 && learningSegments.allowPartialMatch && !hasContentKv)
      insert(
        request, segment.keyBegin, segment.valueBegin, segment.key, segment.value,
        segment.description, innerSegmentBoundary, nextFpsToSet, allowPartialMatch,
        lastAccessTime, &revertEntries, entryFlags)

      // Learn CloseBracket when OpenBracket is committed.
      if let closeBracketKey = Util.isOpenBracket(segment.key),
        let closeBracketValue = Util.isOpenBracket(segment.value)
      {
        insert(
          request, 0, 0, String(closeBracketKey), String(closeBracketValue), segment.description,
          [], [], /*allow_partial_match=*/ false, lastAccessTime, &revertEntries)
      } else if hasContentKv, let closeBracketKey = Util.isOpenBracket(segment.contentKey),
        let closeBracketValue = Util.isOpenBracket(segment.contentValue)
      {
        insert(
          request, 0, 0, String(closeBracketKey), String(closeBracketValue), segment.description,
          [], [], /*allow_partial_match=*/ false, lastAccessTime, &revertEntries)
      }

      prevValue = segment.value
    }
  }

  /// Reverts the last Finish operation.
  public func revert(_ revertId: UInt32) {
    if storage.isSyncerInCriticalSection() {
      return
    }

    guard let revertEntries = revertCache.lookup(revertId) else {
      return
    }

    // `last_committed_entries` keeps the original entries before Revert.
    var lastCommittedEntries = RevertEntries()

    // `revert_entries.entries` store the entries before the commit,
    // while `last_committed_entries->entries` will store the entries after the
    // commit.
    lastCommittedEntries.result = revertEntries.result

    for (keyBegin, valueBegin, revertEntry) in revertEntries.entries {
      // We do not explicitly remove the entry from the `dic_`, but simply
      // rollback to the previous entry. This behavior is consistent with the
      // partial-revert operation. Entry with zero frequency is not suggested in
      // the first place.
      // Currently, dic_ stores the committed entries, but wants to rollback
      // to them to reverted entries..
      let committedEntry = storage.mutableLookup(revertEntry)
      if !committedEntry.isNull {
        // Stores the entries after the commit so we can redo the commit
        // operations after Revert().
        lastCommittedEntries.entries.append((keyBegin, valueBegin, committedEntry.entry))
        // Performs the actual revert operation. dic_ will store the
        // reverted entries.
        committedEntry.entry = revertEntry
      }
    }

    // History entry may have the next_entry link.
    // We have to revert these links.
    if let revertHistoryEntry = revertEntries.historyEntry {
      let committedHistoryEntry = storage.mutableLookup(revertHistoryEntry)
      if !committedHistoryEntry.isNull {
        lastCommittedEntries.historyEntry = committedHistoryEntry.entry
        committedHistoryEntry.entry = revertHistoryEntry
      }
    }

    self.lastCommittedEntries.withLock { [lastCommittedEntries] in $0 = lastCommittedEntries }
  }

  /// Syncs user-modified context.
  public func commitContext(_ request: ConversionRequest) {
    maybeProcessPartialRevertEntry(request)
  }

  /// Gets match type from two strings
  static func getMatchType(_ lstr: some StringProtocol, _ rstr: some StringProtocol) -> MatchType {
    let l = lstr.utf8
    let r = rstr.utf8
    if l.isEmpty && !r.isEmpty {
      return .leftEmptyMatch
    }

    let lsize = l.count
    let rsize = r.count
    let size = min(lsize, rsize)
    if size == 0 {
      return .noMatch
    }

    if !l.prefix(size).elementsEqual(r.prefix(size)) {
      return .noMatch
    }

    if lsize == rsize {
      return .exactMatch
    } else if lsize < rsize {
      return .leftPrefixMatch
    } else {
      return .rightPrefixMatch
    }
  }

  /// Gets match type with ambiguity expansion
  static func getMatchTypeFromInput(
    _ requestKey: String, _ keyBase: String, _ keyExpanded: Trie<String>?, _ target: String
  ) -> MatchType {
    guard let keyExpanded else {
      // |request_key| and |key_base| can be different by composer modification.
      // For example, |request_key|, "８，＋", and |base| "８、＋".
      return getMatchType(keyBase, target)
    }

    // We can assume key_expanded != nullptr from here.
    if keyBase.utf8.isEmpty {
      var value: String? = nil
      var keyLength = 0
      var hasSubtrie = false
      if !keyExpanded.lookUpPrefix(target, &value, &keyLength, &hasSubtrie) {
        return .noMatch
      } else if let value, value.bytesEqual(target) && value.bytesEqual(requestKey) {
        return .exactMatch
      } else {
        return .leftPrefixMatch
      }
    } else {
      let size = min(keyBase.utf8.count, target.utf8.count)
      if size == 0 {
        return .noMatch
      }
      if !keyBase.utf8.prefix(size).elementsEqual(target.utf8.prefix(size)) {
        return .noMatch
      }
      if target.utf8.count <= keyBase.utf8.count {
        return .rightPrefixMatch
      }
      var value: String? = nil
      var keyLength = 0
      var hasSubtrie = false
      if !keyExpanded.lookUpPrefix(
        target.byteSubstring(from: keyBase.utf8.count), &value, &keyLength, &hasSubtrie)
      {
        return .noMatch
      }
      let matched = keyBase + (value ?? "")
      if matched.bytesEqual(target) && matched.bytesEqual(requestKey) {
        return .exactMatch
      } else {
        return .leftPrefixMatch
      }
    }
  }

  /// Fingerprints of key/value and content_key/content_value.
  func learningSegmentFingerprints(_ segment: SegmentForLearning) -> [UInt64] {
    var fps: [UInt64] = []
    fps.reserveCapacity(2)
    fps.append(UserHistoryStorage.fingerprint(segment.key, segment.value))
    if !segment.key.bytesEqual(segment.contentKey) {
      fps.append(UserHistoryStorage.fingerprint(segment.contentKey, segment.contentValue))
    }
    return fps
  }

  /// Returns "tweaked" score of result_entry.
  /// the score is basically determined by "last_access_time", (a.k.a,
  /// LRU policy), but we want to slightly change the score
  /// with different signals, including the length of value and/or
  /// bigram_boost flags.
  /// 1) sort by last_access_time, which is basically the same as LRU policy.
  /// 2) boost shorter candidate, if having the same last_access_time.
  /// 3) add a bigram boost as a special bonus.
  /// TODO(taku): better to take "frequency" into consideration
  static func getScore(_ entry: Entry) -> UInt32 {
    let kBigramBoostAsTime: UInt64 = 7 * 24 * 60 * 60  // 1 week.
    let score =
      entry.lastAccessTime &- UInt64(Util.charsLen(entry.value))
      &+ ((entry.attributes & Attribute.bigramBoost) != 0 ? kBigramBoostAsTime : 0)
    return UInt32(truncatingIfNeeded: score)
  }

  /// Returns the value string byte offset on `reverted_value` with the context
  /// information populated from the client. When all characters in
  /// `reverted_value` are removed, returns 0.
  /// Example:
  ///  - reverted_value: 東京駅
  ///  - left_context:   ここは東京
  ///   -> returns 6.  (only '駅' is removed, and '東京' is kept.).
  /// User may type "ここは" -> "東京駅" -> backspace -> ...
  ///
  /// This function returns the position in best-effort-basis as context
  /// information is not always accurate. Returns 0 when failing to detect
  /// the position, which leads to revert the entire value, same as the
  /// previous behavior.
  static func guessRevertedValueOffset(_ revertedValue: String, _ leftContextIn: String) -> Int32 {
    if revertedValue.utf8.isEmpty || leftContextIn.utf8.isEmpty {
      return 0
    }

    var leftContext = Substring(leftContextIn)

    // Removes specified suffixes which may be inserted directly.
    while true {
      var removed = false
      // Includes full width whitespace.
      for suffix in ["\r", "\n", "\t", " ", "　"] {
        if leftContext.hasByteSuffix(suffix) {
          leftContext = leftContext.byteSubstring(
            from: 0, length: leftContext.utf8.count - suffix.utf8.count)
          removed = true
          break
        }
      }
      if !removed { break }
    }

    var value = Substring(revertedValue)

    // Strip the last character one-by-one, emulating the backspace key.
    while let (remain, _) = Util.splitLastChar32(value) {
      if leftContext.hasByteSuffix(value) {
        return Int32(value.utf8.count)
      }
      value = remain
    }

    return 0
  }

  func isProperNoun(_ request: ConversionRequest, _ result: PredictionResult) -> Bool {
    // Too short input.
    if Util.charsLen(result.key) <= 1 { return false }

    let posMatcher = modules.getPosMatcher()

    // Returns true if there is proper noun entry with `request_key`.
    func isProperNounKeyInDic(_ requestKey: String) -> Bool {
      var found = false
      let cb = InlineCallback()
      cb.onToken { key, value, token in
        if posMatcher.isUniqueNoun(token.lid) || posMatcher.isUniqueNoun(token.rid) {
          found = true
          return .traverseDone
        }
        return .traverseContinue
      }
      modules.getDictionary().lookupExact(requestKey, options: request.options(), callback: cb)
      return found
    }

    let stype = Util.getScriptType(result.value)
    // Heuristically detect whether the prefix value is a proper noun.
    return stype == .katakana || stype == .number || stype == .alphabet  // Unusual script type
      // Single kanji
      || (result.attributes & GenmaiCore.Attribute.singleKanji) != 0
      // Number
      || (result.attributes & GenmaiCore.Attribute.number) != 0
      || posMatcher.isUniqueNoun(result.lid)  // proper noun POS
      || posMatcher.isUniqueNoun(result.rid)
      || (stype == .kanji && isProperNounKeyInDic(result.key))
  }

  func shouldAllowPartialMatch(
    _ request: ConversionRequest, _ result: PredictionResult,
    _ learningSegments: SegmentsForLearning
  ) -> Bool {
    if isProperNoun(request, result) {
      return true
    }

    if !request.request().decoderExperimentParams.userHistoryEnableCompoundNounPartialMatch {
      return false
    }

    if learningSegments.conversionSegments.count <= 1 {
      return false
    }

    // 1. Ensure no functional words (particles) in any conversion segment.
    for seg in learningSegments.conversionSegments {
      if (!seg.contentKey.utf8.isEmpty && !seg.key.bytesEqual(seg.contentKey))
        || (!seg.contentValue.utf8.isEmpty && !seg.value.bytesEqual(seg.contentValue))
      {
        return false
      }
    }

    // 2. Ensure the last segment ends with a noun POS or default.
    let posMatcher = modules.getPosMatcher()
    if result.rid != 0 && !posMatcher.isContentNoun(result.rid)
      && !posMatcher.isGeneralNoun(result.rid) && !posMatcher.isUniqueNoun(result.rid)
    {
      return false
    }

    return true
  }

  /// Re-commits the reverted entries using the left context information.
  /// Users may use the backspace key just to remove the last few characters.
  ///
  /// Example
  /// 1) Commit "東京駅|に".
  ///    1-1) Remembers {東京駅, 東京駅に} in `revert_entries`.
  ///    1-2) Increments the frequency of entries and updates the LRU.
  /// 2) Revert.
  ///    2-1) Remembers the entries in dic_ in `last_committed_entries`.
  ///    2-1) Rollback the entries in dic_ to `revert_entries`.
  /// 3) Erase "に" with backspace.
  /// 4) Type new characters
  ///    `MaybeProcessPartialRevertEntry` is called in the step 4).
  ///    4-1) "東京駅" is the suffix of the left-context ->
  ///          re-commits the entries by inserting `last_committed_entries`
  ///          to dic_.
  ///    4-2) "東京駅に" exceeds the left-context-boundary, so do nothing.
  ///
  ///    Note that step 4) may generate the entries which are not in the
  ///    revert_entries depending on the cursor position. e.g. "東京".
  ///    In this case, creates a new entry and insert it to dic_.
  func maybeProcessPartialRevertEntry(_ request: ConversionRequest) {
    guard let lastCommittedEntries = self.lastCommittedEntries.withLock({ $0 }) else {
      return
    }

    self.lastCommittedEntries.withLock { $0 = nil }

    // Gets the actual cursor position after committing the result.
    let actualValueEnd = Self.guessRevertedValueOffset(
      lastCommittedEntries.result.value, request.context().precedingText)

    // actual_value_end == 0 means that all characters are removed.
    // There are no entries to rollback.
    if actualValueEnd == 0 {
      return
    }

    // Update chain link from prev_entry to `new_entry`.
    // prev_entry ends at `new_entry_key_begin`.
    func updateChain(_ newEntryKeyBegin: Int32, _ newEntry: Entry) {
      var prevEntryFp: UInt64 = 0

      if newEntryKeyBegin == 0 {
        if let historyEntry = lastCommittedEntries.historyEntry {
          prevEntryFp = UserHistoryStorage.fingerprint(historyEntry)
        }
      } else {
        for (keyBegin, _, committedEntry) in lastCommittedEntries.entries {
          if Int(newEntryKeyBegin) == Int(keyBegin) + committedEntry.key.utf8.count {
            prevEntryFp = UserHistoryStorage.fingerprint(committedEntry)
            break
          }
        }
      }

      if prevEntryFp == 0 { return }

      let prevEntry = storage.mutableLookup(prevEntryFp)
      if !prevEntry.isNull {
        let nextEntryFp = UserHistoryStorage.fingerprint(newEntry)
        Self.insertNextEntry(nextEntryFp, &prevEntry.entry)
      }
    }

    func insertEntry(_ newEntry: Entry) {
      let entry = storage.mutableLookup(newEntry)
      if !entry.isNull {
        entry.entry = newEntry
      }
    }

    func forceInsertEntry(_ newEntry: Entry) {
      let fp = UserHistoryStorage.fingerprint(newEntry)
      let hasFp = storage.contains(fp)
      let entry = storage.insert(fp)
      if entry.isNull { return }

      if hasFp {
        // reuse key, value, description and other fields.
        entry.entry.suggestionFreq = entry.entry.suggestionFreq + 1
      } else {
        entry.entry = newEntry  // copy key and value
        entry.entry.suggestionFreq = 1
      }
      entry.entry.lastAccessTime = newEntry.lastAccessTime
    }

    var valueToKeyEndMap: [Int32: Int32] = [:]
    struct Range: Hashable {
      let begin: Int32
      let end: Int32
    }
    var rangeMap = Set<Range>()

    func maybeInitializeMap() {
      if !valueToKeyEndMap.isEmpty && !rangeMap.isEmpty { return }
      for (keyBegin, valueBegin, committedEntry) in lastCommittedEntries.entries {
        let keyEnd = keyBegin + Int32(committedEntry.key.utf8.count)
        let valueEnd = valueBegin + Int32(committedEntry.value.utf8.count)
        if valueToKeyEndMap[valueEnd] == nil {
          valueToKeyEndMap[valueEnd] = keyEnd
        }
        rangeMap.insert(Range(begin: valueBegin, end: valueEnd))
      }
    }

    // Returns the key_end corresponding to `value_end`.
    func getKeyEnd(_ valueEnd: Int32) -> Int32 {
      maybeInitializeMap()
      if let v = valueToKeyEndMap[valueEnd] { return v }
      valueToKeyEndMap[valueEnd] = 0  // operator[] inserts the default.
      return 0
    }

    // Returns true if there is an entry at [value_begin, value_end).
    func hasEntryIn(_ valueBegin: Int32, _ valueEnd: Int32) -> Bool {
      maybeInitializeMap()
      return rangeMap.contains(Range(begin: valueBegin, end: valueEnd))
    }

    // Utility functions to obtain the prefix/suffix after
    // removing n- last characters.
    func getSuffix(_ str: String, _ n: Int32) -> Substring {
      str.byteSubstring(from: str.utf8.count - Int(n), length: Int(n))
    }
    func getPrefix(_ str: String, _ n: Int32) -> Substring {
      str.byteSubstring(from: 0, length: str.utf8.count - Int(n))
    }

    for (keyBegin, valueBegin, committedEntry) in lastCommittedEntries.entries {
      let cvalue = committedEntry.value
      let ckey = committedEntry.key
      // temporal workaround for b/450398740
      // (A Swift String is always valid UTF-8.)
      let valueEnd = valueBegin + Int32(cvalue.utf8.count)
      let keyEnd = keyBegin + Int32(ckey.utf8.count)

      if valueEnd <= actualValueEnd {
        // `committed_entry` exists in the remained context.
        // safely rollback the `committed_entry`.
        insertEntry(committedEntry)
      } else if valueBegin < actualValueEnd && actualValueEnd < valueEnd {
        // Cursor is at the middle of the `committed_entry.value()`.
        // Heuristically obtain the prefix key (= ckey_prefix).
        let cvalueSuffixLen = valueEnd - actualValueEnd
        let cvalueSuffix = getSuffix(cvalue, cvalueSuffixLen)
        let cvaluePrefix = getPrefix(cvalue, cvalueSuffixLen)
        var ckeyPrefix: Substring = ""  // unknown here.
        if hasEntryIn(valueBegin, actualValueEnd) {
          // There is an another entry in [value_begin, actual_value_end).
        } else if case let actualKeyEnd = getKeyEnd(actualValueEnd), actualKeyEnd > 0,
          actualKeyEnd > keyBegin, actualKeyEnd < keyEnd
        {
          // Reuses the boundary of other entries ending at `actual_key_end`.
          ckeyPrefix = getPrefix(ckey, keyEnd - actualKeyEnd)
        } else if Int(cvalueSuffixLen) < ckey.utf8.count
          && cvalueSuffix.bytesEqual(getSuffix(ckey, cvalueSuffixLen))
          && Util.getScriptType(cvalueSuffix) == .hiragana
        {
          // suffix value/key are same and script type is HIRAGANA.
          ckeyPrefix = getPrefix(ckey, cvalueSuffixLen)
        } else {
          // Uses the aligner to get the ckey_prefix.
          // GetReadingAlignment returns the per-char alignment, e.g.
          // {東京駅, とうきょうえき} -> {{東, とう},{京, きょう}, {駅, えき}}
          var keyConsumed = 0
          var valueConsumed = 0
          let cvaluePrefixSize = cvaluePrefix.utf8.count
          for (surface, reading) in modules.getUserHistorySupplementalModel().getReadingAlignment(
            cvalue, ckey)
          {
            if valueConsumed > cvaluePrefixSize { break }
            if valueConsumed == cvaluePrefixSize {
              ckeyPrefix = ckey.byteSubstring(from: 0, length: keyConsumed)
              break
            }
            keyConsumed += reading.utf8.count
            valueConsumed += surface.utf8.count
          }
        }

        if !ckeyPrefix.utf8.isEmpty && !cvaluePrefix.utf8.isEmpty {
          var prefixEntry = committedEntry
          prefixEntry.key = String(ckeyPrefix)
          prefixEntry.value = String(cvaluePrefix)
          forceInsertEntry(prefixEntry)
          updateChain(keyBegin, prefixEntry)
        }
      }
    }
  }
}
