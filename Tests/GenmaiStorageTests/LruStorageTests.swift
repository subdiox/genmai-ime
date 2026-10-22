// Port of mozc/src/storage/lru_storage_test.cc (3.35.6354).

import Foundation
import GenmaiBase
import Testing

@testable import GenmaiStorage

private let kSeed: UInt32 = 0x76fef  // Seed for fingerprint.

private func makeTempFileOrDie() -> TempFile {
  do {
    return try TempDirectory.default().createTempFile()
  } catch {
    fatalError("Failed to create a temporary file: \(error)")
  }
}

private func loadUInt32(_ buf: UnsafeRawBufferPointer?) -> UInt32? {
  guard let buf else { return nil }
  return buf.loadUnaligned(as: UInt32.self)
}

private func uint32Bytes(_ v: UInt32) -> [UInt8] {
  withUnsafeBytes(of: v) { Array($0) }
}

private func runTest(_ storage: LruStorage, _ size: Int) throws {
  let cache = LruCache<String, UInt32>(size)
  var used = Set<String>()
  var values: [(String, UInt32)] = []
  var random = Random()
  for _ in 0..<(size * 2) {
    let key = random.utf8String(Int.random(in: 1...20, using: &random), 1, 0x20000)
    let value = UInt32.random(in: 0..<10_000_000, using: &random)
    if used.contains(key) {
      continue
    }
    used.insert(key)
    values.append((key, value))
    cache.insert(key, value)
    storage.insert(key, uint32Bytes(value))
  }

  values.reverse()

  let valueList = storage.getAllValues()

  var lastAccessTime: UInt32 = 0
  var failures: [String] = []
  for i in 0..<size {
    let v1 = cache.lookup(values[i].0)
    let v2 = loadUInt32(storage.lookup(values[i].0, lastAccessTime: &lastAccessTime))
    let v3 = valueList[i].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    if v1 != values[i].1 || v2 != values[i].1 || v3 != values[i].1 {
      failures.append("\(i): \(String(describing: v1)) \(String(describing: v2)) \(v3) != \(values[i].1)")
    }
  }

  for i in size..<values.count {
    let v1 = cache.lookup(values[i].0)
    let v2 = storage.lookup(values[i].0, lastAccessTime: &lastAccessTime)
    if v1 != nil || v2 != nil {
      failures.append("\(i) should be evicted")
    }
  }
  #expect(failures.isEmpty, "\(failures.prefix(10))")
}

private func getValuesInStorageOrder(_ storage: LruStorage) -> [[UInt8]] {
  var ret: [[UInt8]] = []
  for i in 0..<storage.usedSize {
    ret.append(storage.read(i).value)
  }
  return ret
}

@Suite struct LruStorageTest {
  @Test func lruStorageTest() throws {
    let kSize = [10, 100, 1000, 10000]
    for size in kSize {
      let file = makeTempFileOrDie()
      LruStorage.createStorageFile(file.path, 4, size, kSeed)
      let storage = LruStorage()
      #expect(storage.open(file.path))
      #expect(storage.filename == file.path)
      #expect(storage.size == size)
      #expect(storage.valueSize == 4)
      #expect(storage.seed == kSeed)
      try runTest(storage, size)
    }
  }

  @Test func readWriteTest() {
    let kSize = [10, 100, 1000, 10000]
    var gen = SystemRandomNumberGenerator()

    for size in kSize {
      let file = makeTempFileOrDie()
      LruStorage.createStorageFile(file.path, 4, size, kSeed)
      let storage = LruStorage()
      #expect(storage.open(file.path))
      #expect(storage.filename == file.path)
      #expect(storage.size == size)
      #expect(storage.valueSize == 4)
      #expect(storage.seed == kSeed)

      var entries: [(key: UInt64, lastAccessTime: UInt32, value: [UInt8])] = []

      for j in 0..<size {
        let key = UInt64.random(in: .min ... .max, using: &gen)
        let n = Int32.random(in: 0..<Int32.max, using: &gen)
        let value = withUnsafeBytes(of: n) { Array($0) }
        let lastAccessTime = UInt32.random(in: 0..<100000, using: &gen)
        entries.append((key, lastAccessTime, value))
        storage.write(j, key, value, lastAccessTime)
      }

      var mismatches = 0
      for j in 0..<size {
        let (key, value, lastAccessTime) = storage.read(j)
        if key != entries[j].key || value != entries[j].value
          || lastAccessTime != entries[j].lastAccessTime
        {
          mismatches += 1
        }
      }
      #expect(mismatches == 0)
    }
  }

  @Test func merge() {
    let file1 = makeTempFileOrDie()
    let file2 = makeTempFileOrDie()

    // Can merge
    do {
      LruStorage.createStorageFile(file1.path, 4, 100, kSeed)
      LruStorage.createStorageFile(file2.path, 4, 100, kSeed)
      let storage = LruStorage()
      #expect(storage.open(file1.path))
      #expect(storage.merge(file2.path))
    }

    // different entry size
    do {
      LruStorage.createStorageFile(file1.path, 4, 100, kSeed)
      LruStorage.createStorageFile(file2.path, 4, 200, kSeed)
      let storage = LruStorage()
      #expect(storage.open(file1.path))
      #expect(storage.merge(file2.path))
    }

    // seed is different
    do {
      LruStorage.createStorageFile(file1.path, 4, 100, kSeed)
      LruStorage.createStorageFile(file2.path, 4, 200, 0x76fee)
      let storage = LruStorage()
      #expect(storage.open(file1.path))
      #expect(!storage.merge(file2.path))
    }

    // value size is different
    do {
      LruStorage.createStorageFile(file1.path, 4, 100, kSeed)
      LruStorage.createStorageFile(file2.path, 8, 200, kSeed)
      let storage = LruStorage()
      #expect(storage.open(file1.path))
      #expect(!storage.merge(file2.path))
    }

    // Need to mock clock because old entries are removed on Open.  The
    // maximum timestamp set below is 50, so set the current time to 100.
    withScopedClockMock(Date(unixSeconds: 100)) { _ in
      LruStorage.createStorageFile(file1.path, 4, 8, kSeed)
      LruStorage.createStorageFile(file2.path, 4, 4, kSeed)
      let storage1 = LruStorage()
      #expect(storage1.open(file1.path))
      storage1.write(0, 0, "test", 1)
      storage1.write(1, 1, "test", 10)
      storage1.write(2, 2, "test", 20)
      storage1.write(3, 3, "test", 30)

      let storage2 = LruStorage()
      #expect(storage2.open(file2.path))
      storage2.write(0, 4, "test", 2)
      storage2.write(1, 5, "test", 50)

      #expect(storage1.merge(storage2))

      var r = storage1.read(0)
      #expect(r.fp == 5)
      #expect(r.lastAccessTime == 50)

      r = storage1.read(1)
      #expect(r.fp == 3)
      #expect(r.lastAccessTime == 30)

      r = storage1.read(2)
      #expect(r.fp == 2)
      #expect(r.lastAccessTime == 20)

      r = storage1.read(3)
      #expect(r.fp == 1)
      #expect(r.lastAccessTime == 10)
    }

    // same FP
    withScopedClockMock(Date(unixSeconds: 100)) { _ in
      LruStorage.createStorageFile(file1.path, 4, 8, kSeed)
      LruStorage.createStorageFile(file2.path, 4, 4, kSeed)
      let storage1 = LruStorage()
      #expect(storage1.open(file1.path))
      storage1.write(0, 0, "test", 0)
      storage1.write(1, 1, "test", 10)
      storage1.write(2, 2, "test", 20)
      storage1.write(3, 3, "test", 30)

      let storage2 = LruStorage()
      #expect(storage2.open(file2.path))
      storage2.write(0, 2, "new1", 0)
      storage2.write(1, 3, "new2", 50)

      #expect(storage1.merge(storage2))

      var r = storage1.read(0)
      #expect(r.fp == 3)
      #expect(r.lastAccessTime == 50)
      #expect(r.value == bytes("new2"))

      r = storage1.read(1)
      #expect(r.fp == 2)
      #expect(r.lastAccessTime == 20)
      #expect(r.value == bytes("test"))

      r = storage1.read(2)
      #expect(r.fp == 1)
      #expect(r.lastAccessTime == 10)

      r = storage1.read(3)
      #expect(r.fp == 0)
      #expect(r.lastAccessTime == 0)
    }
  }

  @Test func invalidFileOpenTest() {
    let storage = LruStorage()
    #expect(!storage.insert("test", nil as UnsafeRawBufferPointer?))

    let file = makeTempFileOrDie()

    // cannot open
    #expect(!storage.open(file.path))
    #expect(!storage.insert("test", nil as UnsafeRawBufferPointer?))
  }

  @Test func openOrCreateTest() throws {
    let file = makeTempFileOrDie()
    try FileUtil.setContents(file.path, "test")

    do {
      let storage = LruStorage()
      #expect(!storage.open(file.path), "Corrupted file should be detected as an error.")
    }

    do {
      let storage = LruStorage()
      #expect(
        storage.openOrCreate(file.path, 4, 10, kSeed),
        "Corrupted file should be replaced with new one.")
      let v: UInt32 = 823
      storage.insert("test", uint32Bytes(v))
      let result = loadUInt32(storage.lookup("test"))
      #expect(result == v)
    }
  }

  @Test func delete() throws {
    try withScopedClockMock(Date(unixSeconds: 1)) { clock in
      clock.autoAdvance(.seconds(1))

      let kValueSize = 4
      let kNumElements = 4
      let storage = LruStorage()
      let file = makeTempFileOrDie()
      try #require(storage.openOrCreate(file.path, kValueSize, kNumElements, kSeed))

      #expect(storage.delete("nothing to delete"))

      let kElements: [(key: String, value: String)] = [
        // Elements are inserted into the storage in this order.
        ("0000", "aaaa"),
        ("1111", "bbbb"),
        ("2222", "cccc"),
        ("3333", "dddd"),
      ]
      for kv in kElements {
        #expect(storage.insert(kv.key, kv.value))
      }

      // Test the case where the element to be deleted is at the last slot of
      // mmapped region.
      #expect(storage.delete("3333"))
      var expected = ["aaaa", "bbbb", "cccc"].map(bytes)
      #expect(getValuesInStorageOrder(storage) == expected)
      #expect(storage.usedSize == 3)
      #expect(storage.lookupAsString("0000") == bytes("aaaa"))
      #expect(storage.lookupAsString("1111") == bytes("bbbb"))
      #expect(storage.lookupAsString("2222") == bytes("cccc"))
      #expect(storage.lookup("3333") == nil)

      // Remove the element ("1111", "bbbb") in the middle.  The current
      // last element, ("2222", "cccc") should be moved to keep contiguity.
      #expect(storage.delete("1111"))
      #expect(storage.usedSize == 2)
      #expect(storage.lookupAsString("0000") == bytes("aaaa"))
      #expect(storage.lookupAsString("2222") == bytes("cccc"))
      #expect(storage.lookup("1111") == nil)
      #expect(storage.lookup("3333") == nil)
      expected = ["aaaa", "cccc"].map(bytes)
      #expect(getValuesInStorageOrder(storage) == expected)

      // Insert a new element ("4444", "eeee").
      #expect(storage.insert("4444", "eeee"))
      #expect(storage.usedSize == 3)
      #expect(storage.lookupAsString("0000") == bytes("aaaa"))
      #expect(storage.lookupAsString("2222") == bytes("cccc"))
      #expect(storage.lookupAsString("4444") == bytes("eeee"))
      #expect(storage.lookup("1111") == nil)
      #expect(storage.lookup("3333") == nil)
      expected = ["aaaa", "cccc", "eeee"].map(bytes)
      #expect(getValuesInStorageOrder(storage) == expected)

      // Remove the beginning ("0000", "aaaa").
      #expect(storage.delete("0000"))
      #expect(storage.usedSize == 2)
      #expect(storage.lookupAsString("2222") == bytes("cccc"))
      #expect(storage.lookupAsString("4444") == bytes("eeee"))
      #expect(storage.lookup("0000") == nil)
      #expect(storage.lookup("1111") == nil)
      #expect(storage.lookup("3333") == nil)
      expected = ["eeee", "cccc"].map(bytes)  // "eeee" was moved to the position of "aaaa".
      #expect(getValuesInStorageOrder(storage) == expected)

      // Remove ("4444", "eeee")
      #expect(storage.delete("4444"))
      #expect(storage.usedSize == 1)
      #expect(storage.lookup("0000") == nil)
      #expect(storage.lookup("1111") == nil)
      #expect(storage.lookup("3333") == nil)
      #expect(storage.lookup("4444") == nil)
      expected = ["cccc"].map(bytes)
      #expect(getValuesInStorageOrder(storage) == expected)

      #expect(storage.delete("2222"))
      #expect(storage.usedSize == 0)
      #expect(storage.lookup("0000") == nil)
      #expect(storage.lookup("1111") == nil)
      #expect(storage.lookup("2222") == nil)
      #expect(storage.lookup("3333") == nil)
      #expect(storage.lookup("4444") == nil)
    }
  }

  @Test func deleteElementsBefore() throws {
    try withScopedClockMock(Date(unixSeconds: 1)) { clock in
      let kValueSize = 4
      let kNumElements = 4
      let storage = LruStorage()
      let file = makeTempFileOrDie()
      try #require(storage.openOrCreate(file.path, kValueSize, kNumElements, kSeed))

      // Auto advance clock after opening the file; otherwise OpenOrCreate()
      // advances the clock.
      clock.autoAdvance(.seconds(1))

      let kElements: [(key: String, value: String)] = [
        // Elements are inserted into the storage in this order.  The above
        // clock mock gives timestamps 1 to 4.
        ("1111", "aaaa"),  // Timestamp 1
        ("2222", "bbbb"),  // Timestamp 2
        ("3333", "cccc"),  // Timestamp 3
        ("4444", "dddd"),  // Timestamp 4
      ]
      for kv in kElements {
        storage.insert(kv.key, kv.value)
      }

      var values = storage.getAllValues()
      let kExpectedAfterInsert = ["dddd", "cccc", "bbbb", "aaaa"].map(bytes)
      #expect(values == kExpectedAfterInsert)

      // Should remove "1111" and "2222".
      #expect(storage.deleteElementsBefore(3) == 2)

      values = storage.getAllValues()
      let kExpectedAfterDelete = ["dddd", "cccc"].map(bytes)
      #expect(values == kExpectedAfterDelete)
    }
  }
}
