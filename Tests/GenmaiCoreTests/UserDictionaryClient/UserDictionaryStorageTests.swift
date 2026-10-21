// Port of mozc/src/client/user_dictionary/user_dictionary_storage_test.cc (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

@Suite struct UserDictionaryStorageTests {
  typealias UserDictionary = Genmai_UserDictionary_UserDictionary
  typealias ExtendedErrorCode = UserDictionaryUtil.ExtendedErrorCode

  // TestWithTempUserProfile.
  private func withTempProfile(_ body: () throws -> Void) rethrows {
    try SystemUtil.withTempUserProfile { _ in try body() }
  }

  private func getUserDictionaryFile() -> String {
    FileUtil.joinPath(SystemUtil.getUserProfileDirectory(), "test.db")
  }

  private func isOk(_ body: () throws -> Void) -> Bool {
    do {
      try body()
      return true
    } catch {
      return false
    }
  }

  private func extendedCode(_ body: () throws -> Void) -> ExtendedErrorCode? {
    do {
      try body()
      return .ok
    } catch {
      return UserDictionaryStorage.extendedErrorCode(of: error)
    }
  }

  @Test func fileTest() {
    withTempProfile {
      let storage = UserDictionaryStorage(getUserDictionaryFile())
      #expect(getUserDictionaryFile() == storage.filename)
      #expect(!isOk { try storage.exists() })
    }
  }

  @Test func lockTest() {
    withTempProfile {
      let storage1 = UserDictionaryStorage(getUserDictionaryFile())
      let storage2 = UserDictionaryStorage(getUserDictionaryFile())

      #expect(!isOk { try storage1.save() })
      #expect(!isOk { try storage2.save() })

      #expect(storage1.lock())
      #expect(!storage2.lock())
      #expect(isOk { try storage1.save() })
      #expect(!isOk { try storage2.save() })

      #expect(storage1.unlock())
      #expect(!isOk { try storage1.save() })
      #expect(!isOk { try storage2.save() })

      #expect(storage2.lock())
      #expect(!isOk { try storage1.save() })
      #expect(isOk { try storage2.save() })
    }
  }

  @Test func basicOperationsTest() throws {
    try withTempProfile {
      let storage = UserDictionaryStorage(getUserDictionaryFile())
      #expect(!isOk { try storage.load() })

      let kDictionariesSize = 3
      var id = [UInt64](repeating: 0, count: kDictionariesSize)

      let dictSize = storage.proto.dictionaries.count

      for i in 0..<kDictionariesSize {
        id[i] = try storage.createDictionary("test\(i)")
        #expect(storage.proto.dictionaries.count == i + 1 + dictSize)
      }

      for i in 0..<kDictionariesSize {
        #expect(storage.getUserDictionaryIndex(id[i]) == i + dictSize)
        #expect(storage.getUserDictionaryIndex(id[i] &+ 1) == -1)
      }

      for i in 0..<kDictionariesSize {
        #expect(storage.getUserDictionary(id[i]) == storage.proto.dictionaries[i + dictSize])
        #expect(storage.getUserDictionary(id[i] &+ 1) == nil)
      }

      // empty
      #expect(!isOk { try storage.renameDictionary(id[0], "") })

      // duplicated
      #expect(extendedCode { try storage.createDictionary("test0") } == .dictionaryNameDuplicated)

      // invalid id
      #expect(!isOk { try storage.renameDictionary(0, "") })

      // duplicated
      #expect(
        extendedCode { try storage.renameDictionary(id[0], "test1") } == .dictionaryNameDuplicated)

      // no name
      #expect(isOk { try storage.renameDictionary(id[0], "test0") })

      #expect(isOk { try storage.renameDictionary(id[0], "renamed0") })
      #expect(storage.getUserDictionary(id[0])?.name == "renamed0")

      // invalid id
      #expect(!isOk { try storage.deleteDictionary(0) })

      #expect(isOk { try storage.deleteDictionary(id[1]) })
      #expect(storage.proto.dictionaries.count == kDictionariesSize + dictSize - 1)
    }
  }

  @Test func deleteTest() throws {
    try withTempProfile {
      let storage = UserDictionaryStorage(getUserDictionaryFile())
      #expect(!isOk { try storage.load() })

      // repeat 10 times
      for _ in 0..<10 {
        storage.proto = Genmai_UserDictionary_UserDictionaryStorage()
        var ids = [UInt64](repeating: 0, count: 100)
        for i in 0..<ids.count {
          ids[i] = try storage.createDictionary("test\(i)")
        }

        var alive: [UInt64] = []
        for i in 0..<ids.count {
          if Double.random(in: 0..<1) < 1.0 / 3 {  // 33%
            #expect(isOk { try storage.deleteDictionary(ids[i]) })
            continue
          }
          alive.append(ids[i])
        }

        #expect(storage.proto.dictionaries.count == alive.count)

        for i in 0..<alive.count {
          #expect(storage.proto.dictionaries[i].id == alive[i])
        }
      }
    }
  }

  @Test func exportTest() throws {
    try withTempProfile {
      let storage = UserDictionaryStorage(getUserDictionaryFile())
      let id = try storage.createDictionary("test")

      let found: Void? = storage.withUserDictionary(id) { dic in
        for i in 0..<1000 {
          var entry = UserDictionary.Entry()
          let prefix = String(UInt32(i))
          // set empty fields randomly
          entry.key = prefix + "key"
          entry.value = prefix + "value"
          // "名詞"
          entry.pos = .noun
          entry.comment = prefix + "comment"
          dic.entries.append(entry)
        }
      }
      #expect(found != nil)

      let tempDir = makeTempDirectoryOrDie()
      let exportFile = FileUtil.joinPath(tempDir.path, "export.txt")

      #expect(!isOk { try storage.exportDictionary(id &+ 1, exportFile) })
      #expect(isOk { try storage.exportDictionary(id, exportFile) })

      // Copy whole contents of the file into |file_string|.
      let fileString = try FileUtil.getContentBytes(exportFile)
      let iter = StringTextLineIterator(bytes: fileString)

      var dic2 = UserDictionary()
      #expect(isOk { try UserDictionaryImporter.importFromTextLineIterator(.google, iter, &dic2) })

      dic2.id = id
      dic2.name = "test"

      #expect(storage.getUserDictionary(id) == dic2)
    }
  }

  @Test func serializeTest() throws {
    try withTempProfile {
      // Repeat 20 times
      let filepath = getUserDictionaryFile()
      var random = Random()
      for n in 0..<20 {
        try FileUtil.unlinkIfExists(filepath)
        let storage1 = UserDictionaryStorage(filepath)

        do {
          #expect(!isOk { try storage1.load() }, "n = \(n)")
          let dicSize = Int.random(in: 1...50, using: &random)

          for i in 0..<dicSize {
            #expect(isOk { try storage1.createDictionary("test\(i)") })
            let entrySize = Int.random(in: 1...100, using: &random)
            for _ in 0..<entrySize {
              let lo = UInt32(UInt8(ascii: " "))
              let hi = UInt32(UInt8(ascii: "~"))
              var entry = UserDictionary.Entry()
              entry.key = random.utf8StringRandomLen(10, lo, hi)
              entry.value = random.utf8StringRandomLen(10, lo, hi)
              entry.pos = .noun
              entry.comment = random.utf8StringRandomLen(10, lo, hi)
              storage1.proto.dictionaries[i].entries.append(entry)
            }
          }

          #expect(storage1.lock(), "n = \(n)")
          #expect(isOk { try storage1.save() }, "n = \(n)")
          #expect(storage1.unlock(), "n = \(n)")
        }

        let storage2 = UserDictionaryStorage(getUserDictionaryFile())
        #expect(isOk { try storage2.load() }, "n = \(n)")

        #expect(storage2.proto == storage1.proto, "n = \(n)")
      }
    }
  }

  @Test func getUserDictionaryIdTest() throws {
    try withTempProfile {
      let storage = UserDictionaryStorage(getUserDictionaryFile())
      #expect(!isOk { try storage.load() })

      let id0 = try storage.createDictionary("testA")
      let id1 = try storage.createDictionary("testB")

      let retId0 = try storage.getUserDictionaryId("testA")
      let retId1 = try storage.getUserDictionaryId("testB")
      #expect(!isOk { _ = try storage.getUserDictionaryId("testC") })

      #expect(retId0 == id0)
      #expect(retId1 == id1)
    }
  }

  @Test func isStorageFull() {
    withTempProfile {
      let storage = UserDictionaryStorage()
      storage.proto = Genmai_UserDictionary_UserDictionaryStorage()
      for _ in 0..<UserDictionaryStorage.maxDictionarySize() {
        #expect(!storage.isStorageFull())
        storage.proto.dictionaries.append(UserDictionary())
      }

      #expect(storage.isStorageFull())
    }
  }

  @Test func isDictionaryFull() {
    var dictionary = UserDictionary()
    var allNotFull = true
    for _ in 0..<UserDictionaryStorage.maxEntrySize() {
      allNotFull = allNotFull && !UserDictionaryStorage.isDictionaryFull(dictionary)
      dictionary.entries.append(UserDictionary.Entry())
    }
    #expect(allNotFull)

    #expect(UserDictionaryStorage.isDictionaryFull(dictionary))
  }

  @Test func getUserDictionary() {
    withTempProfile {
      let storage = UserDictionaryStorage()
      var d1 = UserDictionary()
      d1.id = 1
      var d2 = UserDictionary()
      d2.id = 2
      storage.proto.dictionaries.append(d1)
      storage.proto.dictionaries.append(d2)

      #expect(storage.getUserDictionary(1) == storage.dictionaries(0))
      #expect(storage.getUserDictionary(2) == storage.dictionaries(1))
      #expect(storage.getUserDictionary(UInt64.max) == nil)
      // In-place mutation (the C++ returns a mutable pointer).
      storage.withUserDictionary(2) { $0.name = "two" }
      #expect(storage.dictionaries(1).name == "two")
      #expect(storage.withUserDictionary(3) { _ in 0 } == nil)
    }
  }

  @Test func getUserDictionaryIndexById() {
    withTempProfile {
      let storage = UserDictionaryStorage()
      var d1 = UserDictionary()
      d1.id = 1
      var d2 = UserDictionary()
      d2.id = 2
      storage.proto.dictionaries.append(d1)
      storage.proto.dictionaries.append(d2)

      #expect(storage.getUserDictionaryIndex(1) == 0)
      #expect(storage.getUserDictionaryIndex(2) == 1)

      // Return -1 for a failing case.
      #expect(storage.getUserDictionaryIndex(100) == -1)
    }
  }

  @Test func createDictionary() throws {
    try withTempProfile {
      let storage = UserDictionaryStorage()

      // Check dictionary validity.
      #expect(extendedCode { try storage.createDictionary("") } == .dictionaryNameEmpty)

      // Check the limit of the number of dictionaries.
      storage.proto = Genmai_UserDictionary_UserDictionaryStorage()
      for _ in 0..<UserDictionaryStorage.maxDictionarySize() {
        storage.proto.dictionaries.append(UserDictionary())
      }

      #expect(
        extendedCode { try storage.createDictionary("new dictionary") }
          == .dictionarySizeLimitExceeded)

      storage.proto = Genmai_UserDictionary_UserDictionaryStorage()
      let dictionaryId = try storage.createDictionary("new dictionary")

      // EXPECT_PROTO_PEQ("dictionaries < name: \"new dictionary\" >")
      #expect(storage.proto.dictionaries.count == 1)
      #expect(storage.proto.dictionaries[0].name == "new dictionary")
      #expect(storage.dictionaries(0).id == dictionaryId)
    }
  }

  @Test func deleteDictionary() throws {
    try withTempProfile {
      let storage = UserDictionaryStorage()
      func reset() {
        storage.proto = Genmai_UserDictionary_UserDictionaryStorage()
        var d1 = UserDictionary()
        d1.id = 1
        var d2 = UserDictionary()
        d2.id = 2
        storage.proto.dictionaries.append(d1)
        storage.proto.dictionaries.append(d2)
      }
      reset()

      // Simplest deleting case.
      try storage.deleteDictionary(1)
      try #require(storage.dictionariesSize == 1)
      #expect(storage.dictionaries(0).id == 2)

      // Deletion for unknown dictionary should fail.
      reset()
      #expect(!isOk { try storage.deleteDictionary(100) })
    }
  }

  @Test func export() throws {
    try withTempProfile {
      let kDummyDictionaryId: UInt64 = 10
      let tempDir = makeTempDirectoryOrDie()
      let kPath = FileUtil.joinPath(tempDir.path, "exported_file")

      do {
        let storage = UserDictionaryStorage(getUserDictionaryFile())
        do {
          var dictionary = UserDictionary()
          dictionary.id = kDummyDictionaryId
          var entry = UserDictionary.Entry()
          entry.key = "key"
          entry.value = "value"
          entry.pos = .noun
          entry.comment = "comment"
          dictionary.entries.append(entry)
          storage.proto.dictionaries.append(dictionary)
        }
        #expect(isOk { try storage.exportDictionary(kDummyDictionaryId, kPath) })
      }

      let mappedData = try FileUtil.getContentBytes(kPath)

      // Make sure the exported format, especially that the pos is exported in
      // Japanese.
      #expect(mappedData == Array("key\tvalue\t名詞\tcomment\n".utf8))
    }
  }

  // Swift-only: the on-disk format is the plain serialized
  // UserDictionaryStorage message (byte-compatible with C++), the lock file
  // is <profile>/.<basename>.lock, and dictionaries with id 0 get a new id.
  @Test func fileFormatAndZeroIdTest() throws {
    try withTempProfile {
      var proto = Genmai_UserDictionary_UserDictionaryStorage()
      var dic = UserDictionary()
      dic.name = "zero"
      var entry = UserDictionary.Entry()
      entry.key = "a"
      entry.value = "b"
      entry.pos = .noun
      dic.entries.append(entry)
      proto.dictionaries.append(dic)
      // Field 2 (dictionaries) { 3: "zero", 4: { 1: "a", 2: "b", 5: 1 } }
      let expected: [UInt8] = [
        0x12, 0x10, 0x1A, 0x04, 0x7A, 0x65, 0x72, 0x6F, 0x22, 0x08, 0x0A, 0x01, 0x61, 0x12,
        0x01, 0x62, 0x28, 0x01,
      ]
      try FileUtil.setContents(getUserDictionaryFile(), expected)

      let storage = UserDictionaryStorage(getUserDictionaryFile())
      try storage.load()
      #expect(storage.dictionariesSize == 1)
      #expect(storage.dictionaries(0).id != 0)
      #expect(storage.dictionaries(0).entries == [entry])

      storage.proto.dictionaries[0].clearID()
      #expect(storage.lock())
      #expect(
        FileUtil.fileExistsOK(
          FileUtil.joinPath(SystemUtil.getUserProfileDirectory(), ".test.db.lock")))
      try storage.save()
      #expect(try FileUtil.getContentBytes(getUserDictionaryFile()) == expected)
      #expect(!FileUtil.fileExistsOK(getUserDictionaryFile() + ".tmp"))

      // A broken file.
      try FileUtil.setContents(getUserDictionaryFile(), [0xFF, 0xFF])
      let broken = UserDictionaryStorage(getUserDictionaryFile())
      #expect(throws: StatusError.self) { try broken.load() }
      do {
        try broken.load()
      } catch {
        #expect(error.statusCode == .dataLoss)
      }
    }
  }
}
