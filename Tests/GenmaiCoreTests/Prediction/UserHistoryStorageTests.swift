// Port of mozc/src/prediction/user_history_storage_test.cc (3.35.6354).
//
// testing::TestWithTempUserProfile is the `.scopedConfigEnvironment` trait
// (temporary user profile + task-local ConfigHandler / CharacterFormManager).
// mozc::Thread is a child task (`runUserHistoryTestThreads`).
// UserHistoryStorage::Wait() is async (`await storage.wait()`), and Clear()
// writes the file in the background, so the tests await the syncer after it.

import Foundation
import GenmaiBase
import GenmaiProtocol
import GenmaiStorage
import Testing

@testable import GenmaiCore

private typealias Entry = UserHistoryStorage.Entry

private func makeEntry(_ i: Int) -> Entry {
  var entry = Entry()
  entry.key = "key\(i)"
  entry.value = "value\(i)"
  return entry
}

/// testing::MakeTempFileOrDie.
func makeUserHistoryTempFileOrDie() -> TempFile {
  do {
    return try TempDirectory.default().createTempFile()
  } catch {
    fatalError("Failed to create a temporary file: \(error)")
  }
}

/// Runs `body(i)` concurrently in `count` child tasks and waits for them.
func runUserHistoryTestThreads(_ count: Int, _ body: @escaping @Sendable (Int) -> Void) async {
  await withTaskGroup(of: Void.self) { group in
    for i in 0..<count {
      group.addTask { body(i) }
    }
  }
}

@Suite(.scopedConfigEnvironment) struct UserHistoryStorageTest {
  @Test func basicTest() async {
    let storage = UserHistoryStorage()

    #expect(storage.isEmpty())
    #expect(storage.head().isNull)
    #expect(storage.headNext().isNull)

    var entries: [Entry] = []

    // Insert new entries.
    for i in 0..<100 {
      let entry = makeEntry(i)
      entries.append(entry)
      storage.insert(entry)
    }

    #expect(!storage.isEmpty())

    // Serialization.
    storage.asyncSave()
    #expect(storage.isSyncerRunning())
    await storage.wait()
    #expect(!storage.isSyncerRunning())

    storage.asyncLoad()
    #expect(storage.isSyncerRunning())
    await storage.wait()
    #expect(!storage.isSyncerRunning())
    #expect(!storage.isEmpty())

    // immutable lookup. LRU order is not updated.
    for entry in entries {
      let fp = UserHistoryStorage.fingerprint(entry)
      #expect(storage.contains(fp))
      let snapshot = storage.lookup(fp)
      #expect(!snapshot.isNull)
      #expect(snapshot.entry.key == entry.key)
      #expect(snapshot.entry.value == entry.value)
    }

    // mutable lookup. LRU order is not updated.
    for entry in entries {
      let fp = UserHistoryStorage.fingerprint(entry)
      #expect(storage.contains(fp))
      let snapshot = storage.mutableLookup(fp)
      #expect(!snapshot.isNull)
      #expect(snapshot.entry.key == entry.key)
      #expect(snapshot.entry.value == entry.value)
      snapshot.entry.removed = true

      // const_snapshot refers to the same entry.
      let constSnapshot = storage.lookup(fp)
      #expect(constSnapshot.refersToSameEntry(as: snapshot))
      #expect(constSnapshot.entry.removed)
      snapshot.entry.removed = false
      #expect(!constSnapshot.entry.removed)
    }

    // Head
    do {
      let head = storage.head()
      #expect(!head.isNull)
      #expect(head.entry.key == "key99")
      #expect(head.entry.value == "value99")

      let headNext = storage.headNext()
      #expect(headNext.entry.key == "key98")
      #expect(headNext.entry.value == "value98")
    }

    // ForEach.
    do {
      var it = entries.reversed().makeIterator()
      storage.forEachEntry { fp, entry in
        #expect(storage.contains(fp))
        let snapshot = storage.mutableLookup(fp)
        guard let expected = it.next() else {
          Issue.record("more entries than inserted")
          return false
        }
        #expect(snapshot.entry.key == expected.key)
        #expect(snapshot.entry.value == expected.value)
        return true
      }

      var numIterations = 0
      storage.forEachEntry { fp, entry in
        #expect(storage.contains(fp))
        numIterations += 1
        return numIterations < 10
      }
      #expect(numIterations == 10)
    }

    // FindIf
    do {
      let kValue = "value95"
      let foundSnapshot = storage.findIf { fp, entry in entry.value == kValue }
      #expect(!foundSnapshot.isNull)
      #expect(foundSnapshot.refersToSameEntry(as: storage.lookup(foundSnapshot.entry)))
      #expect(foundSnapshot.entry.value == kValue)

      let notFoundSnapshot = storage.findIf { fp, entry in entry.value == "NOT_FOUND" }
      #expect(notFoundSnapshot.isNull)

      for size in 0..<10 {
        let snapshot = storage.findIf({ fp, entry in entry.value == kValue }, size)
        if size >= 5 {
          #expect(!snapshot.isNull)
          #expect(snapshot.refersToSameEntry(as: storage.lookup(snapshot.entry)))
          #expect(snapshot.entry.value == kValue)
        } else {
          #expect(snapshot.isNull)
        }
      }
    }

    // Insert new entry.
    do {
      let entry = makeEntry(10000)
      storage.insert(entry)
      let head = storage.head()
      #expect(entry.key == head.entry.key)
      #expect(entry.value == head.entry.value)
    }

    // Delete entries.
    do {
      var fps: [UInt64] = []
      for i in 0..<50 {
        let entry = makeEntry(i)
        fps.append(UserHistoryStorage.fingerprint(entry))
      }

      storage.erase(fps)

      for fp in fps {
        #expect(!storage.contains(fp))
      }

      for i in 50..<100 {
        #expect(storage.contains(makeEntry(i)))
      }
    }

    // Clears. empty data must be serialized.
    storage.clear()
    #expect(storage.isEmpty())
    await storage.wait()

    storage.asyncLoad()
    await storage.wait()
    #expect(storage.isEmpty())
  }

  @Test func multiThreadsTest() async {
    let file = makeUserHistoryTempFileOrDie()
    let storage = UserHistoryStorage(file.path)

    let kNumThreads = 32

    // Access the storage from multiple threads.
    await runUserHistoryTestThreads(kNumThreads) { i in
      for _ in 0..<10 {
        storage.asyncSave()

        for n in 0..<100 {
          let entry = makeEntry(i * n)
          storage.insert(entry)
        }

        for n in 0..<100 {
          let entry = makeEntry(i * n)
          let fp = UserHistoryStorage.fingerprint(entry)
          if storage.contains(fp) {
            let snapshot = storage.lookup(fp)
            if !snapshot.isNull {
              #expect(entry.key == snapshot.entry.key)
              #expect(entry.value == snapshot.entry.value)
            }
          }
        }
      }

      storage.forEachEntry { fp, entry in
        #expect(storage.contains(fp))
        return true
      }
    }
    await storage.wait()
    withExtendedLifetime(file) {}
  }

  // The C++ test serializes the threads with AcquireUniqueLock(). There is no
  // unique lock here (no lock is held across scopes); the test checks instead
  // that concurrent read-modify-writes of one entry are serialized.
  @Test func uniqueLockTest() async {
    let file = makeUserHistoryTempFileOrDie()
    let storage = UserHistoryStorage(file.path)
    await storage.wait()
    storage.insert(makeEntry(0))
    let fp = UserHistoryStorage.fingerprint(makeEntry(0))

    let kNumThreads = 32

    // Access the storage from multiple threads.
    await runUserHistoryTestThreads(kNumThreads) { _ in
      for _ in 0..<1000 {
        storage.mutableLookup(fp).modify { $0.suggestionFreq += 1 }
      }
    }
    #expect(storage.lookup(fp).entry.suggestionFreq == UInt32(kNumThreads * 1000))
    await storage.wait()
    withExtendedLifetime(file) {}
  }

  @Test func syncTest() async {
    let file = makeUserHistoryTempFileOrDie()

    let storage = UserHistoryStorage(file.path)

    await storage.wait()
    storage.insert(makeEntry(0))
    storage.save()

    // Removes the file
    try? FileUtil.unlinkIfExists(file.path)

    storage.save()

    // File doesn't exist as no mutable operation is executed.
    #expect(!FileUtil.fileExistsOK(file.path))

    // File is created.
    storage.insert(makeEntry(1000))
    storage.save()
    #expect(FileUtil.fileExistsOK(file.path))

    // When cleared, file is removed.
    storage.clear()
    await storage.wait()
    #expect(!FileUtil.fileExistsOK(file.path))
  }

  @Test func cancelTest() async {
    let file = makeUserHistoryTempFileOrDie()

    do {
      let storage = UserHistoryStorage(file.path)
      await storage.wait()
      for i in 0..<100 {
        let entry = makeEntry(i)
        storage.insert(entry)
      }
    }

    #expect(FileUtil.fileExistsOK(file.path))

    func checkSerializedData() async {
      let storage = UserHistoryStorage(file.path)
      await storage.wait()
      for i in 0..<100 {
        let entry = makeEntry(i)
        #expect(storage.contains(UserHistoryStorage.fingerprint(entry)))
      }
    }

    await checkSerializedData()

    do {
      // destructor is called immediately via cancel operation.
      // The file must be kept.
      _ = UserHistoryStorage(file.path)
    }

    #expect(FileUtil.fileExistsOK(file.path))

    await checkSerializedData()
  }

  @Test func migrateNextEntriesTest() async {
    var proto = Genmai_UserHistoryPredictor_UserHistory()

    for i in 0..<100 {
      var entry = makeEntry(i)
      var k = i + 1
      while k < i + 5 && k < 100 {
        let fp = UserHistoryStorage.fingerprintDepereated("key\(k)", "value\(k)")
        var next = Genmai_UserHistoryPredictor_UserHistory.NextEntry()
        next.entryFp = fp
        entry.nextEntriesDeprecated.append(next)
        k += 1
      }
      proto.entries.append(entry)
    }

    UserHistoryStorage.migrateNextEntries(&proto)

    for i in 0..<100 {
      let entry = proto.entries[i]
      #expect(entry.nextEntriesDeprecated.isEmpty)
      var s = 0
      var k = i + 1
      while k < i + 5 && k < 100 {
        let fp = UserHistoryStorage.fingerprint("key\(k)", "value\(k)")
        #expect(entry.nextEntryFps[s] == fp)
        s += 1
        k += 1
      }
      #expect(entry.nextEntryFps.count == s)
    }
  }

  @Test func userHistoryStorageContainingInvalidEntries() async {
    // Swift Strings cannot hold invalid UTF-8, so the serialized UserHistory
    // is written by hand (field 6 = entries, entry field 1 = key, 2 = value).
    func lengthDelimited(_ field: UInt8, _ payload: [UInt8]) -> [UInt8] {
      var out: [UInt8] = [field << 3 | 2]
      var len = payload.count
      repeat {
        var b = UInt8(len & 0x7f)
        len >>= 7
        if len > 0 { b |= 0x80 }
        out.append(b)
      } while len > 0
      return out + payload
    }

    var history: [UInt8] = []
    // Invalid UTF8.
    let values: [[UInt8]] = [
      Array("abc".utf8),  // valid
      [0xC2, 0xC2, 0x20],
      [0xE0, 0xE0, 0xE0, 0x20],
      [0xF0, 0xF0, 0xF0, 0xF0, 0x20],
      [0xFF, 0x20],
      [0xFE, 0x20],
      [0xC0, 0xAF],
      [0xE0, 0x80, 0xAF],
      // Real-world examples from b/116826494.
      [0xEF],
      [0xBC, 0x91, 0xE5],
    ]
    for value in values {
      let entry = lengthDelimited(1, Array("key".utf8)) + lengthDelimited(2, value)
      history += lengthDelimited(6, entry)
    }

    let file = makeUserHistoryTempFileOrDie()
    // Write directly to the file to keep invalid entries for testing.
    let fileStorage = EncryptedStringStorage(file.path)
    #expect(fileStorage.save(history))

    let storage = UserHistoryStorage(file.path)
    await storage.wait()

    var validNum = 0
    storage.forEachEntry { fp, entry in
      validNum += 1
      return true
    }

    #expect(validNum == 1)
  }

  @Test func characterFormStorageTest() async {
    let file = makeUserHistoryTempFileOrDie()
    let manager = CharacterFormManager.getCharacterFormManager()
    manager.setDefaultRule()
    manager.clearHistory()

    do {
      let storage = UserHistoryStorage(file.path)
      await storage.wait()

      manager.setCharacterForm("012", .halfWidth)
      manager.setCharacterForm("ABC", .halfWidth)
      manager.setLastNumberStyle(.init(form: .halfWidth, style: .numberCircled))
      #expect(manager.isStorageDirty())

      // Even when `storage` has no prediction entries, Save() persists
      // CharacterFormManager state.
      #expect(storage.save())
      #expect(!manager.isStorageDirty())
    }

    #expect(FileUtil.fileExistsOK(file.path))

    // Reset in-memory state and reload from disk via UserHistoryStorage.
    manager.clearHistory()
    #expect(manager.getConversionCharacterForm("012") == .fullWidth)
    #expect(manager.getLastNumberStyle() == nil)

    do {
      let storage = UserHistoryStorage(file.path)
      await storage.wait()

      #expect(manager.getConversionCharacterForm("012") == .halfWidth)
      #expect(manager.getConversionCharacterForm("ABC") == .halfWidth)
      let numberStyle = manager.getLastNumberStyle()
      #expect(numberStyle != nil)
      #expect(numberStyle?.form == .halfWidth)
      #expect(numberStyle?.style == .numberCircled)

      // Clearing UserHistoryStorage also clears CharacterFormManager history.
      storage.clear()
      #expect(manager.getConversionCharacterForm("012") == .fullWidth)
      #expect(manager.getLastNumberStyle() == nil)
      await storage.wait()
      #expect(!FileUtil.fileExistsOK(file.path))
    }
  }

  @Test func clearWhileAsyncLoadAndSaveTest() async {
    let file = makeUserHistoryTempFileOrDie()
    let storage = UserHistoryStorage(file.path)
    await storage.wait()

    for i in 0..<1000 {
      storage.insert(makeEntry(i))
    }
    #expect(storage.save())
    #expect(FileUtil.fileExistsOK(file.path))

    // Clear() while AsyncLoad() is in flight must cancel the background task
    // and leave both memory and disk cleared.
    storage.asyncLoad()
    storage.clear()
    await storage.wait()
    #expect(storage.isEmpty())
    #expect(!FileUtil.fileExistsOK(file.path))

    // Clear() while AsyncSave() is in flight must not allow the old snapshot to
    // be written back to disk.
    for i in 0..<1000 {
      storage.insert(makeEntry(i))
    }
    storage.asyncSave()
    storage.clear()
    await storage.wait()
    #expect(storage.isEmpty())
    #expect(!FileUtil.fileExistsOK(file.path))
  }

  // Swift-only: the serialized `.history.db` payload (after decryption) is
  // the C++ wire format: entries in reverse LRU order, fields in field-number
  // order, packed fixed64 next_entry_fps and unpacked fixed32
  // inner_segment_boundary.
  @Test func serializedFormatIsCompatible() async throws {
    let file = makeUserHistoryTempFileOrDie()
    do {
      let storage = UserHistoryStorage(file.path)
      await storage.wait()
      var e1 = Entry()
      e1.key = "a"
      e1.value = "A"
      e1.suggestionFreq = 1
      e1.lastAccessTime = 2
      e1.nextEntryFps = [0x0102_0304_0506_0708]
      e1.innerSegmentBoundary = [0x0101_0101]
      storage.insert(e1)
      var e2 = Entry()
      e2.key = "b"
      e2.value = "B"
      e2.removed = false
      storage.insert(e2)
      #expect(storage.save())
    }
    let payload = try #require(EncryptedStringStorage(file.path).load())
    let expected: [UInt8] =
      // entries[0] = e1 (oldest first)
      [0x32, 0x1b]
      + [0x0a, 0x01, 0x61]  // key
      + [0x12, 0x01, 0x41]  // value
      + [0x18, 0x01]  // suggestion_freq
      + [0x20, 0x02]  // last_access_time
      + [0xba, 0x01, 0x08, 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01]  // next_entry_fps (23, packed)
      + [0xc5, 0x01, 0x01, 0x01, 0x01, 0x01]  // inner_segment_boundary (24, fixed32)
      // entries[1] = e2
      + [0x32, 0x08]
      + [0x0a, 0x01, 0x62]
      + [0x12, 0x01, 0x42]
      + [0x40, 0x00]  // removed (explicitly set)
    #expect(payload == expected)
  }
}
