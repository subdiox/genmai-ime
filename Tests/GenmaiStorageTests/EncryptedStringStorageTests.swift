// Port of mozc/src/storage/encrypted_string_storage_test.cc (3.35.6354).
// The Android-only TestEncryptedStringStorage mock is not ported.

import GenmaiBase
import Testing

@testable import GenmaiStorage

@Suite struct EncryptedStringStorageTest {
  // Port of the fixture (TestWithTempUserProfile + SetUp).
  private func withStorage(_ body: (String, EncryptedStringStorage) throws -> Void) rethrows {
    try SystemUtil.withTempUserProfile { _ in
      let filename = FileUtil.joinPath(
        SystemUtil.getUserProfileDirectory(), "encrypted_string_storage_for_test.db")
      let storage = EncryptedStringStorage(filename)
      try body(filename, storage)
    }
  }

  @Test func saveAndLoad() throws {
    try withStorage { _, storage in
      let kData = "abcdefghijklmnopqrstuvwxyz"
      try #require(storage.save(kData))

      let output = try #require(storage.load())

      #expect(output == bytes(kData))
    }
  }

  @Test func encrypt() throws {
    try withStorage { filename, storage in
      let originalData = "abcdefghijklmnopqrstuvwxyz"
      try #require(storage.save(originalData))

      let ifs = InputFileStream(filename)
      let kBufSize = 128
      let buf = ifs.read(kBufSize)
      _ = ifs.peek()
      try #require(ifs.eof)
      let result = Array(buf)

      // Saved string is longer than original string since it has some data
      // used for encryption.
      #expect(originalData.utf8.count < result.count)
      #expect(!containsSubsequence(result, bytes(originalData)))
    }
  }
}

private func containsSubsequence(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
  if needle.isEmpty { return true }
  if haystack.count < needle.count { return false }
  for i in 0...(haystack.count - needle.count) where haystack[i..<(i + needle.count)].elementsEqual(needle) {
    return true
  }
  return false
}
