// Port of mozc/src/dictionary/user_dictionary.{h,cc} (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiProtocol
import Synchronization

/// `mozc::dictionary::UserDictionary`.
///
/// Concurrency: the token index is an immutable snapshot swapped atomically
/// (C++ `AtomicSharedPtr<TokensIndex>`). `reload()` starts loading on the
/// background thread of a GenmaiBase `TaskManager` (C++ `TaskManager`);
/// `waitForReloader()` is `async` and suspends until it finishes. The reload
/// task keeps the dictionary alive until it finishes, so the C++ destructor's
/// "cancel and wait" step is not needed; `cancelReload()` exposes the cancel
/// signal.
public final class UserDictionary: UserDictionaryInterface, Sendable {
  /// `UserDictionary::RequestType`.
  public enum RequestType: Sendable {
    case prefix, predictive, exact
  }

  private enum ReloadState {
    case idle
    case running
    case runningWithPending
  }

  private struct State {
    var tokens: TokensIndex
    var modifiedAt: FileTimeStamp = 0
    var reloadState: ReloadState = .idle
  }

  private let userPos: UserPos
  private let posMatcher: PosMatcher
  private let state: Mutex<State>
  // Signal variable to cancel the dictionary loading.
  private let canceledSignal = Mutex(false)
  // user dictionary filename.
  private let filename: String
  private let taskManager = TaskManager()

  public convenience init(_ userPos: UserPos, _ posMatcher: PosMatcher) {
    self.init(userPos, posMatcher, UserDictionaryUtil.getUserDictionaryFileName())
  }

  /// Specify dictionary filename for testing.
  public init(_ userPos: UserPos, _ posMatcher: PosMatcher, _ filename: String) {
    assert(!filename.isEmpty)
    self.userPos = userPos
    self.posMatcher = posMatcher
    self.filename = filename
    self.state = Mutex(State(tokens: TokensIndex(userPos)))
    reload()
  }

  private func getTokens() -> TokensIndex {
    state.withLock { $0.tokens }
  }

  private func setTokens(_ tokens: TokensIndex) {
    state.withLock { $0.tokens = tokens }
  }

  public func hasKey(_ key: String) -> Bool {
    // TODO(noriyukit): Currently, we don't support HasKey() for user dictionary
    // because we need to search tokens linearly, which might be slow in extreme
    // cases where 100K entries exist.
    false
  }

  public func hasValue(_ value: String) -> Bool {
    // TODO(noriyukit): Currently, we don't support HasValue() for user dictionary
    // because we need to search tokens linearly, which might be slow in extreme
    // cases where 100K entries exist.  Note: HasValue() method is used only in
    // UserHistoryPredictor for privacy sensitivity check.
    false
  }

  // Lookup methods don't support kana modifier insensitive lookup, i.e.,
  // Callback::OnActualKey() is never called with num_expanded > 0.

  public func lookupPredictive(_ key: String, callback: any DictionaryCallback) {
    if key.isEmpty {
      return
    }

    let tokens = getTokens()

    if tokens.isEmpty {
      return
    }

    // Find the starting point of iteration over dictionary contents.
    for i in tokens.prefixEqualRange(key) {
      let userPosToken = tokens[i]
      let tokenKey = userPosToken.key
      switch callback.onKey(tokenKey) {
      case .traverseDone:
        return
      case .traverseNextKey, .traverseCull:
        continue
      default:
        break
      }
      // b/333613472: Make sure not to set the additional penalties.
      if callback.onActualKey(tokenKey, tokenKey, 0) == .traverseDone {
        return
      }
      let token = tokens.populateToken(userPosToken, .predictive, posMatcher)
      if callback.onToken(tokenKey, tokenKey, token) == .traverseDone {
        return
      }
    }
  }

  // UserDictionary doesn't support kana modifier insensitive lookup.
  public func lookupPrefix(_ key: String, callback: any DictionaryCallback) {
    if key.isEmpty {
      GenmaiLog.warning("string of length zero is passed.")
      return
    }

    let tokens = getTokens()

    if tokens.isEmpty {
      return
    }

    // Find the starting point for iteration over dictionary contents.
    let firstChar = Strings.frontChar(key).0
    var i = tokens.lowerBound(firstChar)
    while i < tokens.count {
      defer { i += 1 }
      let userPosToken = tokens[i]
      let tokenKey = userPosToken.key
      if tokenKey.compareBytes(key) > 0 {
        break
      }
      if userPosToken.rawPosType == UInt8(UserPos.PosType.suggestionOnly.rawValue) {
        continue
      }
      if !key.hasBytePrefix(tokenKey) {
        continue
      }
      switch callback.onKey(tokenKey) {
      case .traverseDone:
        return
      case .traverseNextKey:
        continue
      case .traverseCull:
        fatalError("UserDictionary doesn't support culling.")
      default:
        break
      }
      if callback.onActualKey(tokenKey, tokenKey, 0) == .traverseDone {
        return
      }
      let token = tokens.populateToken(userPosToken, .prefix, posMatcher)
      switch callback.onToken(tokenKey, tokenKey, token) {
      case .traverseDone:
        return
      case .traverseCull:
        fatalError("UserDictionary doesn't support culling.")
      default:
        break
      }
    }
  }

  public func lookupExact(_ key: String, callback: any DictionaryCallback) {
    let tokens = getTokens()

    if key.isEmpty || tokens.isEmpty {
      return
    }
    let range = tokens.equalRange(key)
    if range.isEmpty {
      return
    }

    if callback.onKey(key) != .traverseContinue {
      return
    }
    if callback.onActualKey(key, key, 0) != .traverseContinue {
      return
    }

    for i in range {
      let userPosToken = tokens[i]
      if userPosToken.rawPosType == UInt8(UserPos.PosType.suggestionOnly.rawValue) {
        continue
      }
      let token = tokens.populateToken(userPosToken, .exact, posMatcher)
      if callback.onToken(key, key, token) != .traverseContinue {
        return
      }
    }
  }

  public func lookupReverse(_ str: String, callback: any DictionaryCallback) {}

  /// Looks up a user comment from a pair of key and value.  When (key, value)
  /// doesn't exist in this dictionary or user comment is empty, nil is
  /// returned.
  public func lookupComment(_ key: String, _ value: String) -> String? {
    if key.isEmpty {
      return nil
    }

    let tokens = getTokens()

    if tokens.isEmpty {
      return nil
    }

    // Set the comment that was found first.
    for i in tokens.equalRange(key) {
      let token = tokens[i]
      if token.value.bytesEqual(value) && !token.comment.isEmpty {
        return token.comment
      }
    }
    return nil
  }

  /// Returns true if the word is registered as a suppression word.
  public func isSuppressedEntry(_ key: String, _ value: String) -> Bool {
    getTokens().isSuppressedEntry(key, value)
  }

  public func hasSuppressedEntries() -> Bool {
    getTokens().hasSuppressedEntries()
  }

  /// Reloads dictionary asynchronously.
  @discardableResult
  public func reload() -> Bool {
    let modificationTime: FileTimeStamp
    do {
      modificationTime = try FileUtil.getModificationTime(filename)
    } catch {
      // If the file doesn't exist, return doing nothing.
      // Therefore if the file is deleted after first reload,
      // second reload does nothing so the content loaded by first reload
      // is kept as is.
      GenmaiLog.warning("Cannot get modification time of the user dictionary: \(error)")
      return true
    }

    let start: Bool? = state.withLock { s in
      if s.modifiedAt == modificationTime {
        return nil
      }
      s.modifiedAt = modificationTime
      let previous = s.reloadState
      s.reloadState = .runningWithPending
      return previous == .idle
    }
    guard let start else {
      GenmaiLog.info("MaybeStartReload() didn't start reloading")
      return true
    }
    if start {
      // Runs `reloadThreadMain()` in a background task.
      schedule()
    }
    return true
  }

  // TaskManager::Schedule.
  private func schedule() {
    taskManager.schedule { [self] in
      reloadThreadMain()
    }
  }

  /// Waits until reloader finishes.
  public func waitForReloader() async {
    await taskManager.wait()
  }

  /// Sets the cancel signal of the dictionary loading (C++ destructor).
  public func cancelReload() {
    canceledSignal.withLock { $0 = true }
  }

  private func reloadThreadMain() {
    while !canceledSignal.withLock({ $0 }) {
      state.withLock { $0.reloadState = .running }

      if let bytes = try? FileUtil.getContentBytes(filename) {
        if !load(bytes: bytes) {
          GenmaiLog.error("Failed to load the user dictionary: \(filename)")
        }
      } else {
        GenmaiLog.error("Failed to open the user dictionary: \(filename)")
      }

      let done = state.withLock { s in
        if s.reloadState == .running {
          s.reloadState = .idle
          return true
        }
        return false
      }
      if done {
        return
      }
    }
    state.withLock { $0.reloadState = .idle }
  }

  /// Loads dictionary from UserDictionaryStorage.
  /// mainly for unit testing
  @discardableResult
  public func load(_ storage: Genmai_UserDictionary_UserDictionaryStorage) -> Bool {
    // proto-based loading is mainly for unittesting, so not optimized.
    guard let bytes: [UInt8] = try? storage.serializedBytes() else {
      return false
    }
    return load(bytes: bytes)
  }

  /// Streams dictionary entries directly from the serialized
  /// UserDictionaryStorage (C++ `Load(std::istream&)`).
  @discardableResult
  public func load(bytes: [UInt8]) -> Bool {
    let size = getTokens().count

    let kVeryBigUserDictionarySize = 100000

    if size >= kVeryBigUserDictionarySize {
      setTokens(TokensIndex(userPos))
    }

    guard let tokens = TokensIndex.load(userPos, bytes, canceledSignal) else {
      return false
    }

    setTokens(tokens)
    return true
  }

  /// Gets the user POS list.
  public func getPosList() -> [String] {
    userPos.getPosList()
  }

  /// Populates Token from UserPos::Token for unit testing.
  /// This method sets the actual cost and rewrites POS id depending
  /// on the POS and attribute.
  public func populateTokenFromUserPosTokenForTesting(
    _ userPosToken: UserPos.Token, _ requestType: RequestType
  ) -> Token {
    let entry = TokensIndex.Entry(
      key: userPosToken.key, value: userPosToken.value, comment: "", id: userPosToken.id,
      rawPosType: userPosToken.rawPosType)
    return getTokens().populateToken(entry, requestType, posMatcher)
  }
}

// MARK: - TokensIndex

extension UserDictionary {
  /// Stores user dictionary tokens sorted by `(key, id)`. Suppression words
  /// (`SUPPRESSION_WORD`) are stored as 64-bit fingerprints in
  /// `suppressionSet`.
  ///
  /// Deviation: the C++ keeps the tokens in a flat SerializedStringArray image
  /// (id, raw_pos_type, key_len, value_len, key, value, comment); here they are
  /// an array of `Entry` values with the same fields and order.
  ///
  /// Immutable (built by `load`), so it can be shared across threads.
  fileprivate final class TokensIndex: Sendable {
    // 512MByte
    // We expand the limit of serialized message from 64MB(default) to 512MB.
    static let kDefaultTotalBytesLimit = 512 << 20

    struct Entry {
      var key: String
      var value: String
      var comment: String
      var id: UInt16
      var rawPosType: UInt8

      var posType: UserPos.PosType? { UserPos.PosType(rawValue: Int(rawPosType)) }
    }

    private let userPos: UserPos
    private let tokens: [Entry]
    private let suppressionSet: Set<UInt64>
    private let costPenalty: Int

    convenience init(_ userPos: UserPos) {
      self.init(userPos, tokens: [], suppressionSet: [], costPenalty: 0)
    }

    private init(_ userPos: UserPos, tokens: [Entry], suppressionSet: Set<UInt64>, costPenalty: Int) {
      self.userPos = userPos
      self.tokens = tokens
      self.suppressionSet = suppressionSet
      self.costPenalty = costPenalty
    }

    var isEmpty: Bool { tokens.isEmpty }
    var count: Int { tokens.count }

    subscript(i: Int) -> Entry { tokens[i] }

    // std::lower_bound with OrderByKey.
    func lowerBound(_ key: some StringProtocol) -> Int {
      var lo = 0
      var n = tokens.count
      while n > 0 {
        let half = n / 2
        if tokens[lo + half].key.compareBytes(key) < 0 {
          lo += half + 1
          n -= half + 1
        } else {
          n = half
        }
      }
      return lo
    }

    // std::upper_bound with OrderByKey.
    private func upperBound(_ key: some StringProtocol) -> Int {
      var lo = 0
      var n = tokens.count
      while n > 0 {
        let half = n / 2
        if !(key.compareBytes(tokens[lo + half].key) < 0) {
          lo += half + 1
          n -= half + 1
        } else {
          n = half
        }
      }
      return lo
    }

    func equalRange(_ key: some StringProtocol) -> Range<Int> {
      lowerBound(key)..<upperBound(key)
    }

    // std::equal_range with OrderByKeyPrefix.
    func prefixEqualRange(_ prefix: String) -> Range<Int> {
      let prefixLen = prefix.utf8.count
      func cmp(_ tokenKey: String) -> Int {
        Strings.compareBytes(tokenKey.utf8.prefix(prefixLen), prefix.utf8)
      }
      var lo = 0
      var n = tokens.count
      while n > 0 {
        let half = n / 2
        if cmp(tokens[lo + half].key) < 0 {
          lo += half + 1
          n -= half + 1
        } else {
          n = half
        }
      }
      var hi = lo
      n = tokens.count - lo
      while n > 0 {
        let half = n / 2
        if !(cmp(tokens[hi + half].key) > 0) {
          hi += half + 1
          n -= half + 1
        } else {
          n = half
        }
      }
      return lo..<hi
    }

    func populateToken(
      _ userPosToken: Entry, _ requestType: RequestType, _ posMatcher: PosMatcher
    ) -> Token {
      var token = Token()
      token.key = userPosToken.key
      token.value = userPosToken.value
      token.lid = userPosToken.id
      token.rid = userPosToken.id
      token.attributes = Token.Attribute.userDictionary

      let posType = userPosToken.posType ?? .noPos

      // * Overwrites POS ids.
      // Actual pos id of suggestion-only candidates are 名詞-サ変.
      // TODO(taku): We would like to change the POS to 名詞-サ変 in user-pos.def,
      // because SUGGESTION_ONLY is not POS.
      if posType == .suggestionOnly {
        token.lid = posMatcher.getUnknownId()
        token.rid = token.lid
      }

      // * Overwrites costs.
      token.cost = Int(UserPos.getCostFromPosType(posType, costPenalty))
      assert(token.cost > 0)

      // The treatment for the words with default POS (NO_POS).
      // Shorter keys have more penalty so that they are not shown in the context.
      // TODO(taku): Better to apply this cost for all user defined words?
      if posType == .noPos && (requestType == .prefix || requestType == .exact) {
        let keyLength = Strings.atLeastCharsLen(token.key, 4)
        token.cost += (4 - keyLength) * 2000
      }
      return token
    }

    /// Reads the serialized UserDictionaryStorage; nil when it is broken.
    static func load(
      _ userPos: UserPos, _ bytes: [UInt8], _ canceledSignal: borrowing Mutex<Bool>
    ) -> TokensIndex? {
      var suppressionSet = Set<UInt64>()
      var decoder = WireDecoder(bytes)

      // MakeTag(UserDictionaryStorage::kDictionariesFieldNumber, LENGTH_DELIMITED)
      let kDictionariesTag: UInt32 = (2 << 3) | 2
      // MakeTag(UserDictionary::kEntriesFieldNumber, LENGTH_DELIMITED)
      let kEntriesTag: UInt32 = (4 << 3) | 2

      var serializedTokens: [Entry] = []
      var seen = Set<UInt64>()

      while true {
        let tag = decoder.readTag()
        if tag == 0 {
          break
        }
        if canceledSignal.withLock({ $0 }) {
          GenmaiLog.info("User dictionary loading is canceled")
          return TokensIndex(userPos, tokens: [], suppressionSet: suppressionSet, costPenalty: 0)
        }
        if tag == kDictionariesTag {
          // Read only the byte-length prefix of the UserDictionary submessage
          // (without skipping its payload) so subsequent readTag() calls in this
          // loop read the fields inside UserDictionary directly.
          guard decoder.readVarint32() != nil else {
            return nil
          }
        } else if tag == kEntriesTag {
          guard let len = decoder.readVarint32(),
            let payload = decoder.readBytes(Int(len)),
            let entry = Self.parseEntry(payload)
          else {
            return nil
          }
          addEntry(userPos, entry, &seen, &serializedTokens, &suppressionSet)
        } else if !decoder.skipField(tag) {
          return nil
        }
      }
      if !decoder.consumedEntireMessage {
        return nil
      }

      var tokens: [Entry] = []

      if !serializedTokens.isEmpty {
        // Deviation: the C++ uses absl::c_sort (std::sort, not stable). Swift's
        // sort is stable; entries with the same (key, id) keep their input
        // order, which is also what std::sort produces for short arrays
        // (insertion sort).
        let order = serializedTokens.indices.sorted { l, r in
          let lhs = serializedTokens[l]
          let rhs = serializedTokens[r]
          let c = lhs.key.compareBytes(rhs.key)
          if c != 0 { return c < 0 }
          if lhs.id != rhs.id { return lhs.id < rhs.id }
          return l < r
        }
        tokens = order.map { serializedTokens[$0] }
      }

      // Adds cost penalty based on dictionary entry count N: 500 * log(N + 1).
      //
      // Background:
      // User dictionary entries default to static minimum costs defined in
      // user_pos.def. When users carelessly or unconsciously import large
      // 3rd-party dictionaries, low-quality entries over-trigger and overpower
      // standard system candidates.
      //
      // Theoretical Justification:
      // Assuming a uniform prior probability P = 1/N across N entries, the
      // self-information penalty in Mozc cost scaling (approx. 500 * (-ln P)) is
      // 500 * ln(N + 1). Using N + 1 generalizes to 0 penalty when N = 0.
      let costPenalty = Int(500.0 * Foundation.log(Double(tokens.count + 1)))

      return TokensIndex(userPos, tokens: tokens, suppressionSet: suppressionSet, costPenalty: costPenalty)
    }

    func isSuppressedEntry(_ key: String, _ value: String) -> Bool {
      if !hasSuppressedEntries() {
        return false
      }
      return suppressionSet.contains(Self.suppressedEntryFingerprint(key, value))
    }

    func hasSuppressedEntries() -> Bool { !suppressionSet.isEmpty }

    /// A decoded `UserDictionary.Entry`. Strings are kept as raw bytes so that
    /// invalid UTF-8 is rejected by validation (as in C++) instead of by the
    /// protobuf decoder.
    struct RawEntry {
      var key: [UInt8] = []
      var value: [UInt8] = []
      var comment: [UInt8] = []
      var pos: Int? = nil  // nil: not set (or an unknown enum value)
    }

    // UserDictionary::Entry::MergeFromCodedStream for a fresh entry.
    static func parseEntry(_ bytes: ArraySlice<UInt8>) -> RawEntry? {
      var d = WireDecoder(bytes)
      var entry = RawEntry()
      while true {
        let tag = d.readTag()
        if tag == 0 {
          break
        }
        switch tag {
        case (1 << 3) | 2, (2 << 3) | 2, (4 << 3) | 2:
          guard let len = d.readVarint32(), let s = d.readBytes(Int(len)) else { return nil }
          switch tag >> 3 {
          case 1: entry.key = Array(s)
          case 2: entry.value = Array(s)
          default: entry.comment = Array(s)
          }
        case (5 << 3) | 0:
          guard let v = d.readVarint64() else { return nil }
          // Unknown enum values go to the unknown fields (proto2).
          let i = Int(Int32(truncatingIfNeeded: v))
          if UserPos.PosType(rawValue: i) != nil {
            entry.pos = i
          }
        default:
          if !d.skipField(tag) { return nil }
        }
      }
      if !d.consumedEntireMessage {
        return nil
      }
      return entry
    }

    private static func addEntry(
      _ userPos: UserPos, _ raw: RawEntry, _ seen: inout Set<UInt64>, _ serializedTokens: inout [Entry],
      _ suppressionSet: inout Set<UInt64>
    ) {
      guard let entry = Self.makeValidEntry(raw) else {
        return
      }
      let pos = entry.pos

      // We cannot call NormalizeVoiceSoundMark inside NormalizeReading,
      // because the normalization is user-visible.
      // http://b/2480844
      let reading = Japanese.normalizeVoicedSoundMark(UserDictionaryUtil.normalizeReading(entry.key))

      let posTypeAsChar = String(UnicodeScalar(UInt8(pos.rawValue)))
      let fp = cityFingerprint(reading + "\t" + entry.value + "\t" + posTypeAsChar)
      if !seen.insert(fp).inserted {
        return
      }

      if pos == .suppressionWord {
        // "抑制単語"
        suppressionSet.insert(Self.suppressedEntryFingerprint(reading, entry.value))
      } else {
        let comment = stripAsciiWhitespace(entry.comment)
        for token in userPos.getTokens(reading, entry.value, pos) {
          assert(token.key.utf8.count <= Int(UInt16.max))
          assert(token.value.utf8.count <= Int(UInt16.max))
          serializedTokens.append(
            Entry(
              key: token.key, value: token.value, comment: comment, id: token.id,
              rawPosType: token.rawPosType))
        }
      }
    }

    // ValidateEntry on the raw bytes, then builds a proto Entry.
    private static func makeValidEntry(_ raw: RawEntry) -> Genmai_UserDictionary_UserDictionary.Entry? {
      if UserDictionaryUtil.validateEntry(
        key: raw.key, value: raw.value, comment: raw.comment, hasPos: raw.pos != nil) != .ok
      {
        return nil
      }
      var entry = Genmai_UserDictionary_UserDictionary.Entry()
      entry.key = String(decoding: raw.key, as: UTF8.self)
      entry.value = String(decoding: raw.value, as: UTF8.self)
      entry.comment = String(decoding: raw.comment, as: UTF8.self)
      if let pos = raw.pos, let posType = UserPos.PosType(rawValue: pos) {
        entry.pos = posType
      }
      return entry
    }

    private static func stripAsciiWhitespace(_ s: String) -> String {
      func isSpace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0B || b == 0x0C || b == 0x0D
      }
      let bytes = Array(s.utf8)
      var begin = 0
      var end = bytes.count
      while begin < end && isSpace(bytes[begin]) { begin += 1 }
      while end > begin && isSpace(bytes[end - 1]) { end -= 1 }
      if begin == 0 && end == bytes.count { return s }
      return String(decoding: bytes[begin..<end], as: UTF8.self)
    }

    private static func suppressedEntryFingerprint(_ key: String, _ value: String) -> UInt64 {
      cityFingerprintWithSeed(value, cityFingerprint(key))
    }
  }
}

// MARK: - Protobuf wire decoding

/// Minimal port of the parts of protobuf's CodedInputStream /
/// WireFormatLite::SkipField that UserDictionary uses to stream the storage
/// file.
private struct WireDecoder {
  private let bytes: ArraySlice<UInt8>
  private var pos: Int
  /// False when parsing stopped at an explicit 0 tag or an END_GROUP tag
  /// (CodedInputStream::ConsumedEntireMessage()).
  private(set) var consumedEntireMessage = true

  init(_ bytes: [UInt8]) {
    self.init(bytes[...])
  }

  init(_ bytes: ArraySlice<UInt8>) {
    self.bytes = bytes
    self.pos = bytes.startIndex
  }

  var atEnd: Bool { pos >= bytes.endIndex }

  mutating func readVarint64() -> UInt64? {
    var result: UInt64 = 0
    var shift: UInt64 = 0
    for _ in 0..<10 {
      guard pos < bytes.endIndex else { return nil }
      let b = bytes[pos]
      pos += 1
      result |= UInt64(b & 0x7F) << shift
      if b < 0x80 {
        return result
      }
      shift += 7
    }
    return nil  // malformed varint
  }

  mutating func readVarint32() -> UInt32? {
    readVarint64().map { UInt32(truncatingIfNeeded: $0) }
  }

  /// Returns 0 at the end of the input or on a malformed / zero tag.
  mutating func readTag() -> UInt32 {
    if atEnd {
      consumedEntireMessage = true
      return 0
    }
    guard let tag = readVarint32(), tag != 0 else {
      consumedEntireMessage = false
      return 0
    }
    consumedEntireMessage = true
    return tag
  }

  mutating func readBytes(_ n: Int) -> ArraySlice<UInt8>? {
    guard n >= 0, bytes.endIndex - pos >= n else { return nil }
    let s = bytes[pos..<(pos + n)]
    pos += n
    return s
  }

  /// WireFormatLite::SkipField.
  mutating func skipField(_ tag: UInt32) -> Bool {
    switch tag & 7 {
    case 0:  // VARINT
      return readVarint64() != nil
    case 1:  // FIXED64
      return readBytes(8) != nil
    case 2:  // LENGTH_DELIMITED
      guard let len = readVarint32() else { return false }
      return readBytes(Int(Int32(bitPattern: len))) != nil
    case 3:  // START_GROUP
      // SkipMessage until the matching END_GROUP.
      while true {
        let t = readTag()
        if t == 0 {
          return false
        }
        if t & 7 == 4 {
          return (t >> 3) == (tag >> 3)
        }
        if !skipField(t) {
          return false
        }
      }
    case 4:  // END_GROUP
      return false
    case 5:  // FIXED32
      return readBytes(4) != nil
    default:
      return false
    }
  }
}
