// Port of mozc/src/prediction/user_history_storage.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - Locking. C++ guards the dictionary with a RecursiveMutex and hands out
//   `internal::Snapshot<T>` objects (a pointer + a moved std::unique_lock)
//   that keep it locked while they live. Here no lock is held across scopes:
//   the dictionary lives in a `Mutex<State>` and every method touches it in
//   one short `withLock` section (never re-entered). Consequences:
//   - `EntrySnapshot` / `ConstEntrySnapshot` are handles holding the entry's
//     fingerprint. Each access of `entry` reads or writes the entry in its own
//     critical section (`modify(_:)` is an atomic read-modify-write). A null
//     snapshot (`operator bool() == false`) has `isNull` true; reading `entry`
//     on it traps (like dereferencing nullptr). `snapshot->foo()` becomes
//     `snapshot.entry.foo`, `*snapshot = e` becomes `snapshot.entry = e`, and
//     `snapshot.get() == other.get()` becomes `refersToSameEntry(as:)`.
//   - `forEach` / `forEachMutable` / `findIf` copy the entries in their
//     critical section and call the callback outside of it, so the callback
//     may use the storage (C++ relies on the lock being recursive).
//   - There is no `AcquireUniqueLock` (it only saved re-locking in C++).
//   - `IsSyncerInCriticalSection` is true while the syncer is running (the
//     C++ check "the mutex is not owned by this thread" is always true outside
//     the syncer).
// - The syncer is GenmaiBase `TaskManager` (an actor on a background thread;
//   scheduling never blocks; see Thread.swift for why it is not the
//   cooperative pool). Swift task-locals do not reach it, so the user profile
//   directory (used by PasswordManager for the encryption key) and the
//   CharacterFormManager are captured when a task is scheduled and
//   re-installed in it.
// - `wait()` is `async` (suspends until the syncer finishes). The syncer task
//   keeps the storage alive, so the destructor does not cancel and wait for
//   it.
// - `clear()` does not block: C++ cancels the syncer, waits for it, clears the
//   storage and saves it. When the syncer is idle, the same is done at once.
//   When it is running, `clear()` cancels it, clears the in-memory data at once
//   and schedules the save (which also resets the cancel flag) after the
//   canceled syncer task. A canceled load leaves the cleared data untouched.
// - The persisted file is byte compatible with C++ Mozc's `.history.db`
//   (EncryptedStringStorage + the serialized `UserHistory` proto, entries in
//   reverse LRU order). swift-protobuf rejects invalid UTF-8 in proto2 string
//   fields, which C++ accepts; when the whole message fails to parse, the
//   entries are parsed one by one from the wire format and the broken ones are
//   dropped (C++ drops entries whose *value* is invalid UTF-8; an entry with an
//   invalid *key* is dropped here as well, since a Swift String cannot hold
//   it).

import Foundation
import GenmaiBase
import GenmaiProtocol
import GenmaiStorage
import Synchronization

// Uses '\t' as a key/value delimiter
private let kDelimiter = "\t"

// On-memory LRU cache size.
// Typically memory/storage footprint becomes kLruCacheSize * 70 bytes.
// Note that actual entries serialized to the disk may be smaller
// than this size.
private let kLruCacheSize = 10000

// File name for the history
private let kFileName = "user://.history.db"

/// UserHistoryStorage is a class that encapsulates lookup, insertion, and
/// deletion of user history, as well as serialization to disk. All methods
/// are thread-safe. This class is introduced to abstract and hide
/// the storage implementation.
///
/// Lookup methods return a snapshot handle of the entry (see the header
/// comment; it holds no lock):
///
///     let snapshot = storage.lookup(fp)
///     print(snapshot.entry.key, snapshot.entry.value)
public final class UserHistoryStorage: Sendable {
  public typealias Entry = Genmai_UserHistoryPredictor_UserHistory.Entry
  typealias DicCache = LruCache<UInt64, Entry>

  private struct State {
    var dic = DicCache(kLruCacheSize)
  }

  /// Mutable snapshot (C++ `EntrySnapshot`).
  public final class EntrySnapshot: Sendable {
    private let storage: UserHistoryStorage
    let fp: UInt64?

    init(_ storage: UserHistoryStorage, _ fp: UInt64?) {
      self.storage = storage
      self.fp = fp
    }

    /// `!snapshot`.
    public var isNull: Bool { fp == nil }

    /// The fingerprint of a non-null snapshot (dereferencing a null snapshot crashes in C++ too).
    private var nonNullFingerprint: UInt64 {
      guard let fp else { preconditionFailure("UserHistoryStorage: dereferencing a null EntrySnapshot") }
      return fp
    }

    /// `*snapshot`. Traps when the snapshot is null.
    public var entry: Entry {
      get { storage.readEntry(nonNullFingerprint) }
      set { storage.writeEntry(nonNullFingerprint) { $0 = newValue } }
    }

    /// Reads and writes the entry in one critical section.
    @discardableResult
    public func modify<R: Sendable>(_ body: (inout Entry) -> R) -> R {
      storage.writeEntry(nonNullFingerprint, body)
    }

    /// `snapshot.get() == other.get()`.
    public func refersToSameEntry(as other: EntrySnapshot) -> Bool {
      fp != nil && fp == other.fp
    }

    public func refersToSameEntry(as other: ConstEntrySnapshot) -> Bool {
      fp != nil && fp == other.fingerprint
    }
  }

  /// Immutable snapshot (C++ `ConstEntrySnapshot`).
  public final class ConstEntrySnapshot: Sendable {
    private let storage: UserHistoryStorage
    /// The fingerprint (LRU key) of the entry, nil when null.
    public let fingerprint: UInt64?

    init(_ storage: UserHistoryStorage, _ fp: UInt64?) {
      self.storage = storage
      self.fingerprint = fp
    }

    /// `!snapshot`.
    public var isNull: Bool { fingerprint == nil }

    /// `*snapshot`. Traps when the snapshot is null.
    public var entry: Entry {
      guard let fingerprint else {
        preconditionFailure("UserHistoryStorage: dereferencing a null ConstEntrySnapshot")
      }
      return storage.readEntry(fingerprint)
    }

    /// `snapshot.get() == other.get()`.
    public func refersToSameEntry(as other: ConstEntrySnapshot) -> Bool {
      fingerprint != nil && fingerprint == other.fingerprint
    }

    public func refersToSameEntry(as other: EntrySnapshot) -> Bool {
      fingerprint != nil && fingerprint == other.fp
    }
  }

  // Sets true if the internal data must be synced.
  private let needsSync = Mutex(false)

  // Sets true to cancel the syncer threads.
  private let canceled = Mutex(false)

  private let taskManager = TaskManager()

  private let state = Mutex(State())

  public let filename: String

  /// Loads/stores the dict from/to `filename`.
  public init(_ filename: String) {
    self.filename = filename
    asyncLoad()
  }

  /// Uses the default history filename.
  public convenience init() {
    self.init(ConfigFileStream.getFileName(kFileName))
  }

  deinit {
    // The syncer task holds the storage, so it is not running here (C++
    // cancels and waits for it).

    // Call Saves() just in case as the internal data may be updated while
    // syncer thread is running.
    save()
  }

  // MARK: - Entry access (one critical section each)

  // The value of an entry that disappeared after the snapshot was taken (C++
  // would read a dangling pointer): an empty entry; writes to it are dropped.
  fileprivate func readEntry(_ fp: UInt64) -> Entry {
    state.withLock { $0.dic.mutableLookupWithoutInsert(fp)?.value ?? Entry() }
  }

  fileprivate func writeEntry<R: Sendable>(_ fp: UInt64, _ body: (inout Entry) -> R) -> R {
    state.withLock { state in
      if let element = state.dic.mutableLookupWithoutInsert(fp) {
        return body(&element.value)
      }
      var removed = Entry()
      return body(&removed)
    }
  }

  // MARK: - Syncer

  /// Non-blocking version of Save.
  public func asyncSave() {
    if (needsSync.withLock({ $0 }) || CharacterFormManager.getCharacterFormManager().isStorageDirty())
      && !isSyncerRunning()
    {
      schedule { $0.save() }
    }
  }

  /// Non-blocking version of Load.
  public func asyncLoad() {
    if !isSyncerRunning() {
      schedule { $0.load() }
    }
  }

  /// `Wait(); AsyncLoad();` without blocking: the load is scheduled after the
  /// running syncer task.
  public func asyncLoadAfterSyncer() {
    schedule { $0.load() }
  }

  // Schedules `body` on the syncer. The task-local state the syncer depends on
  // is captured here (see the header comment).
  private func schedule(_ body: @escaping @Sendable (UserHistoryStorage) -> Void) {
    let profileDirectory = SystemUtil.getUserProfileDirectory()
    let manager = CharacterFormManager.getCharacterFormManager()
    // The task holds the storage until it finishes.
    taskManager.schedule { [self] in
      SystemUtil.withUserProfileDirectory(profileDirectory) {
        CharacterFormManager.withScopedManagerForTesting(manager) {
          body(self)
        }
      }
    }
  }

  /// Waits until the syncer finishes.
  public func wait() async { await taskManager.wait() }

  /// Clears the storage and internal data. When the syncer is running, the
  /// in-memory data is cleared at once and the storage file is written by the
  /// syncer (see the header comment).
  public func clear() {
    if !isSyncerRunning() {
      // Nothing to cancel or wait for (C++ Wait() returns at once).
      clearMemory()
      save()
      return
    }
    canceled.withLock { $0 = true }
    clearMemory()
    schedule { storage in
      storage.canceled.withLock { $0 = false }
      // A canceled load may have reset the flag.
      storage.needsSync.withLock { $0 = true }
      storage.save()
    }
  }

  private func clearMemory() {
    state.withLock { state in
      state.dic = DicCache(kLruCacheSize)
      CharacterFormManager.getCharacterFormManager().clearHistory()
      needsSync.withLock { $0 = true }
    }
  }

  /// Returns true if the syncer is running.
  public func isSyncerRunning() -> Bool { taskManager.isRunning() }

  /// Returns true if the syncer is in the critical section.
  /// The Syncer handles both file IO and memory IO. The latter memory IO is the
  /// actual critical section, where exclusive operation is necessary. This
  /// method allows to prevent unintentional blocking. (True while the syncer
  /// is running; see the header comment.)
  public func isSyncerInCriticalSection() -> Bool {
    taskManager.isRunning()
  }

  /// Loads the user history from the local disk. This method is blocking.
  @discardableResult
  public func load() -> Bool {
    let storage = EncryptedStringStorage(filename)

    guard let input = storage.load() else {
      GenmaiLog.error("Can't load user history data.")
      return false
    }

    guard var proto = Self.parseUserHistory(input) else {
      GenmaiLog.error("ParseFromString failed. message looks broken")
      return false
    }

    Self.migrateNextEntries(&proto)

    return load(proto)
  }

  private func load(_ proto: Genmai_UserHistoryPredictor_UserHistory) -> Bool {
    // Enters syncer's critical section.
    state.withLock { state in
      // Not in C++: `clear()` does not wait for the syncer (see the header
      // comment), so a load canceled before it got the lock must not touch the
      // cleared data.
      if canceled.withLock({ $0 }) {
        GenmaiLog.error("Loading thread is canceled")
        return false
      }

      state.dic.clear()

      // 1) After loading `dic_` no need to sync.
      // 2) When AsyncLoad is canceled, `dic_` has incomplete data,
      //    so must not be synced.
      needsSync.withLock { $0 = false }

      for var entry in proto.entries {
        if canceled.withLock({ $0 }) {
          GenmaiLog.error("Loading thread is canceled")
          return false
        }

        if entry.value.utf8.isEmpty || entry.key.utf8.isEmpty {
          continue
        }
        // Workaround for b/116826494: Some garbled characters are suggested
        // from user history. This filters such entries.
        // (A Swift String is always valid UTF-8; broken entries are dropped by
        // parseUserHistory.)

        // conversion_freq is migrated to suggestion_freq.
        entry.suggestionFreq = max(entry.suggestionFreq, entry.conversionFreqDeprecated)
        entry.clearConversionFreqDeprecated()

        let fp = Self.fingerprint(entry)
        state.dic.insert(fp, entry)
      }

      CharacterFormManager.getCharacterFormManager().loadStorage(proto)

      return true
    }
  }

  /// Saves the user history to the local disk. This method is blocking.
  @discardableResult
  public func save() -> Bool {
    let characterFormManager = CharacterFormManager.getCharacterFormManager()
    if !needsSync.withLock({ $0 }) && !characterFormManager.isStorageDirty() {
      return true
    }

    // Enters syncer's critical section.
    var proto = state.withLock { state in
      var proto = Genmai_UserHistoryPredictor_UserHistory()
      proto.entries.reserveCapacity(state.dic.size)

      for elm in state.dic {
        if proto.entries.count >= kLruCacheSize {
          break
        }
        proto.entries.append(elm.value)
      }

      characterFormManager.saveStorage(&proto)
      return proto
    }

    // Reverse the contents to keep the LRU order when loading.
    proto.entries.reverse()

    guard let output: [UInt8] = try? proto.serializedBytes() else {
      GenmaiLog.error("AppendToString failed")
      return false
    }

    // Remove the storage file when proto is empty because
    // storing empty file causes an error.
    if output.isEmpty {
      try? FileUtil.unlinkIfExists(filename)
      needsSync.withLock { $0 = false }
      return true
    }

    let storage = EncryptedStringStorage(filename)
    if !storage.save(output) {
      GenmaiLog.error("Can't save user history data.")
      return false
    }

    needsSync.withLock { $0 = false }

    return true
  }

  // MARK: - Entries

  // The entries in LRU order (at most `limit`), copied in one critical
  // section.
  private func copyEntries(_ limit: Int = Int.max) -> [(UInt64, Entry)] {
    state.withLock { state in
      var entries: [(UInt64, Entry)] = []
      entries.reserveCapacity(min(limit, state.dic.size))
      for elm in state.dic {
        if entries.count >= limit {
          break
        }
        entries.append((elm.key, elm.value))
      }
      return entries
    }
  }

  /// Iterates the all entries in LRU order.
  /// `func` is the callback. When `func` returns false, stops the iteration.
  /// The entries are copied first; `fn` may use the storage.
  public func forEachEntry(_ fn: (UInt64, Entry) -> Bool) {
    for (fp, entry) in copyEntries() {
      if !fn(fp, entry) {
        break
      }
    }
  }

  /// Iterates the all entries in LRU order. Mutable entries are passed; a
  /// changed entry is written back if it is still stored.
  public func forEachMutable(_ fn: (UInt64, inout Entry) -> Bool) {
    for (fp, original) in copyEntries() {
      var entry = original
      let next = fn(fp, &entry)
      if entry != original {
        let updated = entry
        writeEntry(fp) { $0 = updated }
      }
      if !next {
        break
      }
    }
  }

  /// Returns true if `fp` exists in the storage.
  public func contains(_ fp: UInt64) -> Bool { !lookup(fp).isNull }

  /// Inserts or updates the entry associated with `fp`.
  /// Returns the inserted or updated entry. LRU order is updated.
  /// NOTE (deviation): when `fp` is new, C++ returns an element that may be
  /// reused from the LRU free list and still holds the previous (erased or
  /// evicted) value. LruCache.Element does not expose whether it holds a
  /// value, so a new `fp` always gets an empty Entry here.
  @discardableResult
  public func insert(_ fp: UInt64) -> EntrySnapshot {
    state.withLock { state in
      needsSync.withLock { $0 = true }
      let hasFp = state.dic.hasKey(fp)
      let elm = state.dic.insert(fp)
      if !hasFp {
        elm.value = Entry()
      }
    }
    return EntrySnapshot(self, fp)
  }

  /// Inserts new `entry` and update LRU order.
  public func insert(_ entry: Entry) {
    let fp = Self.fingerprint(entry)
    state.withLock { state in
      needsSync.withLock { $0 = true }
      state.dic.insert(fp, entry)
    }
  }

  /// Lookup the immutable entry associated with `fp`.
  /// LRU order is not updated.
  public func lookup(_ fp: UInt64) -> ConstEntrySnapshot {
    let found = state.withLock { $0.dic.mutableLookupWithoutInsert(fp) != nil }
    return ConstEntrySnapshot(self, found ? fp : nil)
  }

  /// Lookup the mutable entry associated with `fp`.
  /// LRU order is not updated.
  public func mutableLookup(_ fp: UInt64) -> EntrySnapshot {
    let found = state.withLock { state in
      needsSync.withLock { $0 = true }
      return state.dic.mutableLookupWithoutInsert(fp) != nil
    }
    return EntrySnapshot(self, found ? fp : nil)
  }

  // Wrappers of Contains/Lookup/MutableLookup (DEFINE_FP_WRAPPER).
  public func contains(_ key: some StringProtocol, _ value: some StringProtocol) -> Bool {
    contains(Self.fingerprint(key, value))
  }
  public func contains(_ entry: Entry) -> Bool { contains(Self.fingerprint(entry)) }
  public func lookup(_ key: some StringProtocol, _ value: some StringProtocol) -> ConstEntrySnapshot {
    lookup(Self.fingerprint(key, value))
  }
  public func lookup(_ entry: Entry) -> ConstEntrySnapshot { lookup(Self.fingerprint(entry)) }
  public func mutableLookup(_ key: some StringProtocol, _ value: some StringProtocol) -> EntrySnapshot {
    mutableLookup(Self.fingerprint(key, value))
  }
  public func mutableLookup(_ entry: Entry) -> EntrySnapshot { mutableLookup(Self.fingerprint(entry)) }

  /// Returns the LRU-head entry.
  public func head() -> ConstEntrySnapshot {
    ConstEntrySnapshot(self, state.withLock { $0.dic.head?.key })
  }

  /// Returns the head->next entry.
  public func headNext() -> ConstEntrySnapshot {
    ConstEntrySnapshot(self, state.withLock { $0.dic.head?.next?.key })
  }

  /// Returns null entry.
  /// Useful to initialize snapshot with null variable.
  public func nullEntry() -> ConstEntrySnapshot {
    ConstEntrySnapshot(self, nil)
  }

  /// Finds the entry with linear search. Only top `size` elements are
  /// searched. When the size is -1 (default) search all entries.
  public func findIf(_ fn: (UInt64, Entry) -> Bool, _ size: Int = -1) -> ConstEntrySnapshot {
    for (fp, entry) in copyEntries(size < 0 ? Int.max : size) where fn(fp, entry) {
      return ConstEntrySnapshot(self, fp)
    }
    return ConstEntrySnapshot(self, nil)
  }

  /// Erases `fps` from the storage.
  public func erase(_ fps: [UInt64]) {
    if fps.isEmpty {
      return
    }

    state.withLock { state in
      needsSync.withLock { $0 = true }
      for fp in fps {
        state.dic.erase(fp)
      }
    }
  }

  /// Returns true if the storage is empty.
  public func isEmpty() -> Bool {
    state.withLock { $0.dic.isEmpty }
  }

  /// Returns fingerprints from various object.
  public static func fingerprint(_ key: some StringProtocol, _ value: some StringProtocol) -> UInt64 {
    cityFingerprint(String(key) + kDelimiter + String(value))
  }

  public static func fingerprint(_ entry: Entry) -> UInt64 {
    fingerprint(entry.key, entry.value)
  }

  // MARK: - Internal (UserHistoryStorageTestPeer)

  /// Migrate old 32bit Fingerprint to 64bit Fingerprint.
  static func fingerprintDepereated(_ key: some StringProtocol, _ value: some StringProtocol) -> UInt32 {
    legacyFingerprint32(String(key) + kDelimiter + String(value))
  }

  static func migrateNextEntries(_ proto: inout Genmai_UserHistoryPredictor_UserHistory) {
    var migrated = true
    for entry in proto.entries where !entry.nextEntriesDeprecated.isEmpty {
      migrated = false
      break
    }

    if migrated {
      return
    }

    var old2newFp: [UInt32: UInt64] = [:]
    for entry in proto.entries {
      let oldFp = fingerprintDepereated(entry.key, entry.value)
      let newFp = fingerprint(entry.key, entry.value)
      old2newFp[oldFp] = newFp
    }

    for i in proto.entries.indices {
      for nextEntry in proto.entries[i].nextEntriesDeprecated {
        if let fp = old2newFp[nextEntry.entryFp] {
          proto.entries[i].nextEntryFps.append(fp)
        }
      }
      proto.entries[i].nextEntriesDeprecated.removeAll()
    }
  }

  /// `proto.ParseFromString(input)`. See the header comment for the fallback
  /// on invalid UTF-8.
  static func parseUserHistory(_ input: [UInt8]) -> Genmai_UserHistoryPredictor_UserHistory? {
    if let proto = try? Genmai_UserHistoryPredictor_UserHistory(serializedBytes: input) {
      return proto
    }
    return parseUserHistoryLeniently(input)
  }

  // Walks the wire format of `UserHistory` and parses each `entries` element
  // (field 6) individually, dropping the ones swift-protobuf rejects. Other
  // fields are parsed as a message of their own. Returns nil when the wire
  // format itself is broken.
  private static func parseUserHistoryLeniently(
    _ input: [UInt8]
  ) -> Genmai_UserHistoryPredictor_UserHistory? {
    var proto = Genmai_UserHistoryPredictor_UserHistory()
    var rest: [UInt8] = []  // fields other than entries
    var pos = 0

    func readVarint() -> UInt64? {
      var result: UInt64 = 0
      var shift: UInt64 = 0
      while pos < input.count {
        let b = input[pos]
        pos += 1
        if shift >= 64 { return nil }
        result |= UInt64(b & 0x7f) << shift
        if b & 0x80 == 0 { return result }
        shift += 7
      }
      return nil
    }

    while pos < input.count {
      let fieldStart = pos
      guard let tag = readVarint() else { return nil }
      let fieldNumber = tag >> 3
      let wireType = tag & 7
      switch wireType {
      case 0:
        guard readVarint() != nil else { return nil }
      case 1:
        pos += 8
      case 5:
        pos += 4
      case 2:
        guard let len = readVarint(), len <= UInt64(input.count - pos) else { return nil }
        let payload = Array(input[pos..<(pos + Int(len))])
        pos += Int(len)
        if fieldNumber == 6 {
          if let entry = try? Genmai_UserHistoryPredictor_UserHistory.Entry(serializedBytes: payload) {
            proto.entries.append(entry)
          } else {
            GenmaiLog.error("Invalid UTF8 found in user history")
          }
          continue
        }
      default:
        return nil
      }
      if pos > input.count { return nil }
      rest.append(contentsOf: input[fieldStart..<pos])
    }

    if !rest.isEmpty {
      guard let other = try? Genmai_UserHistoryPredictor_UserHistory(serializedBytes: rest) else {
        return nil
      }
      let entries = proto.entries
      proto = other
      proto.entries = entries + other.entries
    }
    return proto
  }

  // TESTONLY: the number of elements (for tests).
  var sizeForTesting: Int {
    state.withLock { $0.dic.size }
  }
}
