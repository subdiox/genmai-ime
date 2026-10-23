// Port of mozc/src/dictionary/user_dictionary_test.cc (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

// Raw bytes because the C++ data contains invalid UTF-8.
private let kUserDictionary0: [UInt8] =
  Array(
    ("start\tstart\tverb\n" + "star\tstar\tnoun\n" + "starting\tstarting\tnoun\n"
      + "stamp\tstamp\tnoun\n" + "stand\tstand\tverb\n" + "smile\tsmile\tverb\n"
      + "smog\tsmog\tnoun\n").utf8)
  // invalid characters "あ\x81\x84う" in reading. "い" is "E3 81 84".
  + [0xE3, 0x81, 0x82, 0x81, 0x84, 0xE3, 0x81, 0x86] + Array("\tvalue\tnoun\n".utf8)
  + Array(
    (
      // This is also a valid entry. Key can contain any valid characters.
      "水雲\tvalue\tnoun\n"
      // Empty key
      + "\tvalue\tnoun\n"
      // Empty value
      + "start\t\tnoun\n"
      // Invalid POS
      + "star\tvalue\tpos\n"
      // Empty POS
      + "star\tvalue\t\n"
      // Duplicate entry
      + "start\tstart\tverb\n"
      // The following are for tests for LookupComment
      // No comment
      + "comment_key1\tcomment_value1\tnoun\n"
      // Has comment
      + "comment_key2\tcomment_value2\tnoun\tcomment\n"
      // Different POS
      + "comment_key3\tcomment_value3\tnoun\tcomment1\n"
      + "comment_key3\tcomment_value3\tverb\tcomment2\n"
      // White spaces comment
      + "comment_key4\tcomment_value4\tverb\t     \n").utf8)

private let kUserDictionary1: [UInt8] = Array("end\tend\tverb\n".utf8)

private func makeUserPosToken(_ key: String, _ value: String, _ id: UInt16) -> UserPos.Token {
  var token = UserPos.Token()
  token.key = key
  token.value = value
  token.id = id
  return token
}

/// This class is a mock class for writing unit tests of a class that
/// depends on POS. It accepts only two values for part-of-speech:
/// "noun" as words without inflection and "verb" as words with
/// inflection.
private final class UserPosMock: UserPosInterface {
  static let kNoun = Genmai_UserDictionary_UserDictionary.PosType.noun
  static let kVerb = Genmai_UserDictionary_UserDictionary.PosType.waGroup1Verb

  /// Given a verb, this method expands it to three different forms,
  /// i.e. base form (the word itself), "-ed" form and "-ing" form. For
  /// example, if the given word is "play", the method returns "play",
  /// "played" and "playing". When a noun is passed, it returns only
  /// base form. The method set lid and rid of the word as following:
  ///
  ///  POS              | lid | rid
  /// ------------------+-----+-----
  ///  noun             | 100 | 100
  ///  verb (base form) | 200 | 200
  ///  verb (-ed form)  | 210 | 210
  ///  verb (-ing form) | 220 | 220
  func getTokens(_ key: String, _ value: String, _ posType: UserPos.PosType) -> [UserPos.Token] {
    var tokens: [UserPos.Token] = []
    if key.isEmpty || value.isEmpty {
      return tokens
    }
    if posType == Self.kNoun {
      tokens.append(makeUserPosToken(key, value, 100))
    } else if posType == Self.kVerb {
      tokens.append(makeUserPosToken(key, value, 200))
      tokens.append(makeUserPosToken(key + "ed", value + "ed", 210))
      tokens.append(makeUserPosToken(key + "ing", value + "ing", 220))
    }
    return tokens
  }

  func getPosList() -> [String] { ["名詞"] }
}

private struct Entry: Equatable, Hashable, CustomStringConvertible {
  var key: String
  var value: String
  var lid: UInt16
  var rid: UInt16

  init(_ key: String, _ value: String, _ lid: UInt16, _ rid: UInt16) {
    self.key = key
    self.value = value
    self.lid = lid
    self.rid = rid
  }

  var description: String { "key = \(key), value = \(value), lid = \(lid), rid = \(rid)" }
}

private final class EntryCollector: DictionaryCallback {
  var entries: [Entry] = []

  func onToken(_ key: String, _ actualKey: String, _ token: Token) -> DictionaryCallbackResult {
    // Collect only user dictionary entries.
    if token.attributes & Token.Attribute.userDictionary != 0 {
      entries.append(Entry(token.key, token.value, token.lid, token.rid))
    }
    return .traverseContinue
  }
}

private func unordered(_ a: [Entry], _ b: [Entry]) -> Bool {
  a.count == b.count && a.sorted { $0.description < $1.description } == b.sorted { $0.description < $1.description }
}

// MARK: - Protobuf encoding helpers (raw bytes, so that invalid UTF-8 can be
// stored as in the C++ test).

private func appendVarint(_ v: UInt64, _ out: inout [UInt8]) {
  var v = v
  while v >= 0x80 {
    out.append(UInt8(v & 0x7F) | 0x80)
    v >>= 7
  }
  out.append(UInt8(v))
}

private func appendLengthDelimited(_ field: UInt64, _ payload: [UInt8], _ out: inout [UInt8]) {
  appendVarint((field << 3) | 2, &out)
  appendVarint(UInt64(payload.count), &out)
  out.append(contentsOf: payload)
}

/// `LoadFromString`: builds a serialized UserDictionaryStorage with one
/// dictionary from TSV lines (key, value, "verb"/"noun", [comment]).
private func loadFromString(_ contents: [UInt8]) -> [UInt8] {
  var dic: [UInt8] = []
  for line in contents.split(separator: 0x0A, omittingEmptySubsequences: false) {
    if line.isEmpty || line.first == UInt8(ascii: "#") {
      continue
    }
    let fields = line.split(separator: 0x09, omittingEmptySubsequences: false)
    #expect(fields.count >= 3)
    var entry: [UInt8] = []
    appendLengthDelimited(1, Array(fields[0]), &entry)
    appendLengthDelimited(2, Array(fields[1]), &entry)
    if fields.count >= 4 && !fields[3].isEmpty {
      appendLengthDelimited(4, Array(fields[3]), &entry)
    }
    if Array(fields[2]) == Array("verb".utf8) {
      appendVarint((5 << 3) | 0, &entry)
      appendVarint(UInt64(Genmai_UserDictionary_UserDictionary.PosType.waGroup1Verb.rawValue), &entry)
    } else if Array(fields[2]) == Array("noun".utf8) {
      appendVarint((5 << 3) | 0, &entry)
      appendVarint(UInt64(Genmai_UserDictionary_UserDictionary.PosType.noun.rawValue), &entry)
    }
    appendLengthDelimited(4, entry, &dic)
  }
  var storage: [UInt8] = []
  appendLengthDelimited(2, dic, &storage)
  return storage
}

@Suite(.serialized, .enabled(if: DictionaryTestSupport.hasMockData, DictionaryTestSupport.mockDataMissing))
struct UserDictionaryTests {
  typealias PB = Genmai_UserDictionary_UserDictionary

  let mockDataManager: DataManager

  init() throws {
    mockDataManager = try DictionaryTestSupport.mockDataManager()
  }

  var posMatcher: PosMatcher { PosMatcher(mockDataManager.getPosMatcherData()) }

  // Creates a user dictionary with mock pos data.
  func createDictionaryWithMockPos() -> UserDictionary {
    UserDictionary(UserPosMock(), posMatcher)
  }

  // Creates a user dictionary with actual pos data.
  func createDictionary() -> UserDictionary {
    let data = mockDataManager.getUserPosData()
    return UserDictionary(UserPos(data.tokenArray, data.stringArray), posMatcher)
  }

  func createDictionaryWithFilename(_ filename: String) -> UserDictionary {
    let data = mockDataManager.getUserPosData()
    return UserDictionary(UserPos(data.tokenArray, data.stringArray), posMatcher, filename)
  }

  fileprivate func lookupPredictive(_ key: String, _ dic: UserDictionary) -> [Entry] {
    let collector = EntryCollector()
    dic.lookupPredictive(key, callback: collector)
    return collector.entries
  }

  fileprivate func lookupPrefix(_ key: String, _ dic: UserDictionary) -> [Entry] {
    let collector = EntryCollector()
    dic.lookupPrefix(key, callback: collector)
    return collector.entries
  }

  fileprivate func lookupExact(_ key: String, _ dic: UserDictionary) -> [Entry] {
    let collector = EntryCollector()
    dic.lookupExact(key, callback: collector)
    return collector.entries
  }

  // Helper function to lookup comment string from `dic`.
  func lookupComment(_ dic: UserDictionary, _ key: String, _ value: String) -> String {
    dic.lookupComment(key, value) ?? ""
  }

  private static let invalidUtf8Key = String(decoding: [0xE3, 0x81, 0x82, 0x81, 0x84, 0xE3, 0x81, 0x86], as: UTF8.self)

  @Test func testLookupPredictiveCallback() async {
    await SystemUtil.withTempUserProfile { _ in
      let dic = createDictionaryWithMockPos()
      // Wait for async reload called from the constructor.
      await dic.waitForReloader()
      #expect(dic.load(bytes: loadFromString(kUserDictionary0)))

      let mockCallback = MockCallback()
      var onKeyStart = 0
      var onActualKeyStart = 0
      var onTokenStart = 0
      mockCallback.onKeyHandler = { key in
        if key == "start" { onKeyStart += 1 }
        return .traverseContinue
      }
      mockCallback.onActualKeyHandler = { key, actualKey, numExpanded in
        if key == "start" && actualKey == "start" && numExpanded == 0 { onActualKeyStart += 1 }
        return .traverseContinue
      }
      mockCallback.onTokenHandler = { key, actualKey, _ in
        if key == "start" && actualKey == "start" { onTokenStart += 1 }
        return .traverseContinue
      }
      dic.lookupPredictive("start", callback: mockCallback)
      #expect(onKeyStart == 1)
      #expect(onActualKeyStart == 1)
      #expect(onTokenStart == 1)
    }
  }

  @Test func testLookupExactCallback() async {
    await SystemUtil.withTempUserProfile { _ in
      let dic = createDictionaryWithMockPos()
      // Wait for async reload called from the constructor.
      await dic.waitForReloader()
      #expect(dic.load(bytes: loadFromString(kUserDictionary0)))

      let mockCallback = MockCallback()
      var keys: [String] = []
      var actualKeys: [String] = []
      var tokenKeys: [String] = []
      mockCallback.onKeyHandler = { key in
        keys.append(key)
        return .traverseContinue
      }
      mockCallback.onActualKeyHandler = { key, actualKey, numExpanded in
        #expect(numExpanded == 0)
        actualKeys.append(key + "/" + actualKey)
        return .traverseContinue
      }
      mockCallback.onTokenHandler = { key, actualKey, _ in
        tokenKeys.append(key + "/" + actualKey)
        return .traverseContinue
      }
      dic.lookupExact("start", callback: mockCallback)
      #expect(keys == ["start"])
      #expect(actualKeys == ["start/start"])
      #expect(tokenKeys == ["start/start"])
    }
  }

  @Test func testLookupPrefixCallback() async {
    await SystemUtil.withTempUserProfile { _ in
      let dic = createDictionaryWithMockPos()
      // Wait for async reload called from the constructor.
      await dic.waitForReloader()
      #expect(dic.load(bytes: loadFromString(kUserDictionary0)))

      let mockCallback = MockCallback()
      var onKeyStart = 0
      var onActualKeyStart = 0
      var onTokenStart = 0
      mockCallback.onKeyHandler = { key in
        if key == "start" { onKeyStart += 1 }
        return .traverseContinue
      }
      mockCallback.onActualKeyHandler = { key, actualKey, numExpanded in
        if key == "start" && actualKey == "start" && numExpanded == 0 { onActualKeyStart += 1 }
        return .traverseContinue
      }
      mockCallback.onTokenHandler = { key, actualKey, _ in
        if key == "start" && actualKey == "start" { onTokenStart += 1 }
        return .traverseContinue
      }
      dic.lookupPrefix("start", callback: mockCallback)
      #expect(onKeyStart == 1)
      #expect(onActualKeyStart == 1)
      #expect(onTokenStart == 1)
    }
  }

  @Test func testLookupPredictive() async {
    await SystemUtil.withTempUserProfile { _ in
      let dic = createDictionaryWithMockPos()
      // Wait for async reload called from the constructor.
      await dic.waitForReloader()
      #expect(dic.load(bytes: loadFromString(kUserDictionary0)))

      // A normal lookup operation.
      let kExpected0 = [
        Entry("start", "start", 200, 200),
        Entry("started", "started", 210, 210),
        Entry("starting", "starting", 100, 100),
        Entry("starting", "starting", 220, 220),
      ]
      #expect(unordered(lookupPredictive("start", dic), kExpected0))

      // Another normal lookup operation.
      let kExpected1 = [
        Entry("stamp", "stamp", 100, 100), Entry("stand", "stand", 200, 200),
        Entry("standed", "standed", 210, 210), Entry("standing", "standing", 220, 220),
        Entry("star", "star", 100, 100), Entry("start", "start", 200, 200),
        Entry("started", "started", 210, 210), Entry("starting", "starting", 100, 100),
        Entry("starting", "starting", 220, 220),
      ]
      #expect(unordered(lookupPredictive("st", dic), kExpected1))

      // Invalid input values should be just ignored.
      #expect(lookupPredictive("", dic).isEmpty)
      #expect(lookupPredictive(Self.invalidUtf8Key, dic).isEmpty)

      // Kanji is also a valid key chararcter.
      #expect(lookupPredictive("水雲", dic) == [Entry("水雲", "value", 100, 100)])

      // Make a change to the dictionary file and load it again.
      #expect(dic.load(bytes: loadFromString(kUserDictionary1)))

      // A normal lookup again.
      let kExpected3 = [
        Entry("end", "end", 200, 200),
        Entry("ended", "ended", 210, 210),
        Entry("ending", "ending", 220, 220),
      ]
      #expect(unordered(lookupPredictive("end", dic), kExpected3))

      // Entries in the dictionary before reloading cannot be looked up.
      #expect(lookupPredictive("start", dic).isEmpty)
      #expect(lookupPredictive("st", dic).isEmpty)
    }
  }

  @Test func testLookupPrefix() async {
    await SystemUtil.withTempUserProfile { _ in
      let dic = createDictionaryWithMockPos()
      // Wait for async reload called from the constructor.
      await dic.waitForReloader()
      #expect(dic.load(bytes: loadFromString(kUserDictionary0)))

      // A normal lookup operation.
      let kExpected0 = [
        Entry("star", "star", 100, 100),
        Entry("start", "start", 200, 200),
        Entry("started", "started", 210, 210),
      ]
      #expect(unordered(lookupPrefix("started", dic), kExpected0))

      // Another normal lookup operation.
      let kExpected1 = [
        Entry("star", "star", 100, 100),
        Entry("start", "start", 200, 200),
        Entry("starting", "starting", 100, 100),
        Entry("starting", "starting", 220, 220),
      ]
      #expect(unordered(lookupPrefix("starting", dic), kExpected1))

      // Invalid input values should be just ignored.
      #expect(lookupPrefix("", dic).isEmpty)
      #expect(lookupPrefix(Self.invalidUtf8Key, dic).isEmpty)

      // Kanji is also a valid key chararcter.
      #expect(lookupPrefix("水雲", dic) == [Entry("水雲", "value", 100, 100)])

      // Make a change to the dictionary file and load it again.
      #expect(dic.load(bytes: loadFromString(kUserDictionary1)))

      // A normal lookup.
      let kExpected3 = [
        Entry("end", "end", 200, 200),
        Entry("ending", "ending", 220, 220),
      ]
      #expect(unordered(lookupPrefix("ending", dic), kExpected3))

      // Lookup for entries which are gone should returns empty result.
      #expect(lookupPrefix("started", dic).isEmpty)
      #expect(lookupPrefix("starting", dic).isEmpty)
    }
  }

  @Test func testLookupExact() async {
    await SystemUtil.withTempUserProfile { _ in
      let dic = createDictionaryWithMockPos()
      // Wait for async reload called from the constructor.
      await dic.waitForReloader()
      #expect(dic.load(bytes: loadFromString(kUserDictionary0)))

      // A normal lookup operation.
      #expect(lookupExact("start", dic) == [Entry("start", "start", 200, 200)])

      // Another normal lookup operation.
      let kExpected1 = [
        Entry("starting", "starting", 100, 100),
        Entry("starting", "starting", 220, 220),
      ]
      #expect(unordered(lookupExact("starting", dic), kExpected1))

      // Invalid input values should be just ignored.
      #expect(lookupExact("", dic).isEmpty)
      #expect(lookupExact(Self.invalidUtf8Key, dic).isEmpty)

      // Kanji is also a valid key chararcter.
      #expect(lookupExact("水雲", dic) == [Entry("水雲", "value", 100, 100)])
    }
  }

  @Test func testLookupExactWithSuggestionOnlyWords() async {
    await SystemUtil.withTempUserProfile { _ in
      let userDic = createDictionary()
      await userDic.waitForReloader()

      // Create dictionary
      var storage = Genmai_UserDictionary_UserDictionaryStorage()
      do {
        var dic = PB()
        // "名詞"
        var entry = PB.Entry()
        entry.key = "key"
        entry.value = "noun"
        entry.pos = .noun
        dic.entries.append(entry)
        // "サジェストのみ"
        entry = PB.Entry()
        entry.key = "key"
        entry.value = "suggest_only"
        entry.pos = .suggestionOnly
        dic.entries.append(entry)
        storage.dictionaries.append(dic)
        userDic.load(storage)
      }

      // "suggestion_only" should not be looked up.
      let kNounId = posMatcher.getGeneralNounId()
      #expect(lookupExact("key", userDic) == [Entry("key", "noun", kNounId, kNounId)])
    }
  }

  @Test func testLookupWithNoPos() async {
    await SystemUtil.withTempUserProfile { _ in
      let userDic = createDictionary()
      await userDic.waitForReloader()

      // Create dictionary
      var storage = Genmai_UserDictionary_UserDictionaryStorage()
      do {
        // Creates the shortcut dictionary (from Gboard Android).
        var dic = PB()
        dic.name = "__auto_imported_android_shortcuts_dictionary"
        // "名詞"
        var entry = PB.Entry()
        entry.key = "key"
        entry.value = "noun"
        entry.pos = .noun
        dic.entries.append(entry)
        // SUGGESTION ONLY word is handled as NO_POS word.
        entry = PB.Entry()
        entry.key = "key"
        entry.value = "suggest_only"
        entry.pos = .suggestionOnly
        dic.entries.append(entry)
        // NO POS word is handled as NO_POS word.
        entry = PB.Entry()
        entry.key = "key"
        entry.value = "no_pos"
        entry.pos = .noPos
        dic.entries.append(entry)
        storage.dictionaries.append(dic)
        userDic.load(storage)
      }

      // NO_POS words are looked up.
      let kNounId = posMatcher.getGeneralNounId()
      let kUnknownId = posMatcher.getUnknownId()
      let kExpected2 = [
        Entry("key", "noun", kNounId, kNounId),
        Entry("key", "no_pos", kUnknownId, kUnknownId),
      ]
      let kExpectedPrediction = [
        Entry("key", "noun", kNounId, kNounId),
        Entry("key", "no_pos", kUnknownId, kUnknownId),
        Entry("key", "suggest_only", kUnknownId, kUnknownId),
      ]
      #expect(unordered(lookupExact("key", userDic), kExpected2))
      #expect(unordered(lookupPredictive("ke", userDic), kExpectedPrediction))
      #expect(unordered(lookupPrefix("key", userDic), kExpected2))
    }
  }

  @Test func testKeyNormalization() async {
    await SystemUtil.withTempUserProfile { _ in
      let userDic = createDictionary()
      await userDic.waitForReloader()

      // Create dictionary
      var storage = Genmai_UserDictionary_UserDictionaryStorage()
      do {
        var dic = PB()
        // "名詞"(NOUN)
        // Full width will be normalized to half width.
        var entry = PB.Entry()
        entry.key = "１％"
        entry.value = "１％"
        entry.pos = .noun
        dic.entries.append(entry)
        // Half width katakana will be normalized to full width hiragana.
        entry = PB.Entry()
        entry.key = "ｸﾞｰｸﾞﾙ"
        entry.value = "Google"
        entry.pos = .noun
        dic.entries.append(entry)
        // NO POS word is handled as NO_POS word.
        // voiced sound mark in「う゛」 will be normalized to be 「ゔ」.
        entry = PB.Entry()
        entry.key = "う゛ぃくとりー"
        entry.value = "ヴィクトリー"
        entry.pos = .noPos
        dic.entries.append(entry)
        // Katakana will be normalized to hiragana.
        entry = PB.Entry()
        entry.key = "ジーボード"
        entry.value = "Gboard"
        entry.pos = .noPos
        dic.entries.append(entry)
        storage.dictionaries.append(dic)
        userDic.load(storage)
      }

      #expect(lookupExact("1%", userDic).count == 1)
      #expect(lookupExact("１％", userDic).count == 0)
      #expect(lookupExact("ぐーぐる", userDic).count == 1)
      #expect(lookupExact("グーグル", userDic).count == 0)
      #expect(lookupExact("ｸﾞｰｸﾞﾙ", userDic).count == 0)
      #expect(lookupExact("ゔぃくとりー", userDic).count == 1)
      #expect(lookupExact("う゛ぃくとりー", userDic).count == 0)
      #expect(lookupExact("ヴィクトリー", userDic).count == 0)
      #expect(lookupExact("じーぼーど", userDic).count == 1)
      #expect(lookupExact("ジーボード", userDic).count == 0)
    }
  }

  @Test func asyncLoadTest() async throws {
    try await SystemUtil.withTempUserProfile { _ in
      let tempDir = makeTempDirectoryOrDie()
      defer { withExtendedLifetime(tempDir) {} }
      let filename = FileUtil.joinPath(tempDir.path, "async_load_test.db")
      var random = Random()

      // Create dictionary
      var keys: [String] = []
      do {
        var storage = Genmai_UserDictionary_UserDictionaryStorage()
        var dic = PB()
        for _ in 0..<10000 {
          var entry = PB.Entry()
          entry.key = random.utf8StringRandomLen(10, 0x61, 0x7A)
          entry.value = random.utf8StringRandomLen(10, 0x61, 0x7A)
          entry.pos = .noun
          entry.comment = random.utf8StringRandomLen(10, 0x61, 0x7A)
          keys.append(entry.key)
          dic.entries.append(entry)
        }
        storage.dictionaries.append(dic)
        let bytes: [UInt8] = try storage.serializedBytes()
        try FileUtil.setContents(filename, bytes)
      }

      do {
        let dic = createDictionaryWithFilename(filename)
        // Wait for async reload called from the constructor.
        await dic.waitForReloader()

        for _ in 0..<32 {
          keys.shuffle(using: &random)
          dic.reload()
          for i in 0..<1000 {
            let callback = CollectTokenCallback()
            dic.lookupPrefix(keys[i], callback: callback)
            #expect(!callback.tokens.isEmpty)
          }
        }
        await dic.waitForReloader()
      }

      // Fix b//341758719. Waits the reload inside the destructor.
      do {
        let dic = createDictionaryWithFilename(filename)
        dic.reload()
        await dic.waitForReloader()
      }
      withExtendedLifetime(tempDir) {}
    }
  }

  @Test func consecutiveReloadTest() async throws {
    try await SystemUtil.withTempUserProfile { _ in
      let tempDir = makeTempDirectoryOrDie()
      defer { withExtendedLifetime(tempDir) {} }
      let filename = FileUtil.joinPath(tempDir.path, "consecutive_reload_test.db")
      let dic = createDictionaryWithFilename(filename)
      await dic.waitForReloader()

      let kNumUpdates = 10
      var storage = Genmai_UserDictionary_UserDictionaryStorage()
      for i in 0..<kNumUpdates {
        var userDic = PB()
        userDic.name = "dic_\(i)"
        for j in 0..<500 {
          var entry = PB.Entry()
          entry.key = "key_\(i)_\(j)"
          entry.value = "value_\(i)_\(j)"
          entry.pos = .noun
          userDic.entries.append(entry)
        }
        storage.dictionaries.append(userDic)
        let tmpFilename = filename + ".tmp"
        let bytes: [UInt8] = try storage.serializedBytes()
        try FileUtil.setContents(tmpFilename, bytes)
        try FileUtil.atomicRename(tmpFilename, filename)
        // Trigger reload() immediately without waiting for the previous reload to
        // finish.
        #expect(dic.reload())
      }
      await dic.waitForReloader()

      for i in 0..<kNumUpdates {
        #expect(!lookupExact("key_\(i)_0", dic).isEmpty)
      }
      withExtendedLifetime(tempDir) {}
    }
  }

  @Test func testSuppressionDictionary() async {
    await SystemUtil.withTempUserProfile { _ in
      let userDic = createDictionaryWithMockPos()
      await userDic.waitForReloader()

      var storage = Genmai_UserDictionary_UserDictionaryStorage()

      // Create dictionary
      do {
        var dic = PB()
        for j in 0..<10000 {
          var entry = PB.Entry()
          entry.key = "no_suppress_key\(j)"
          entry.value = "no_suppress_value\(j)"
          entry.pos = .noun
          dic.entries.append(entry)
        }
        for j in 0..<10 {
          var entry = PB.Entry()
          entry.key = "suppress_key\(j)"
          entry.value = "suppress_value\(j)"
          // entry->set_pos("抑制単語");
          entry.pos = .suppressionWord
          dic.entries.append(entry)
        }
        storage.dictionaries.append(dic)
        userDic.load(storage)

        for j in 0..<10 {
          #expect(userDic.isSuppressedEntry("suppress_key\(j)", "suppress_value\(j)"))
        }
      }

      // Remove suppression entry
      do {
        storage = Genmai_UserDictionary_UserDictionaryStorage()
        var dic = PB()
        for j in 0..<10000 {
          var entry = PB.Entry()
          entry.key = "no_suppress_key\(j)"
          entry.value = "no_suppress_value\(j)"
          entry.pos = .noun
          dic.entries.append(entry)
        }
        storage.dictionaries.append(dic)
        userDic.load(storage)
        for j in 0..<10 {
          #expect(!userDic.isSuppressedEntry("suppress_key\(j)", "suppress_value\(j)"))
        }
      }
    }
  }

  @Test func testSuggestionOnlyWord() async {
    await SystemUtil.withTempUserProfile { _ in
      let userDic = createDictionary()
      await userDic.waitForReloader()

      var storage = Genmai_UserDictionary_UserDictionaryStorage()

      // Create dictionary
      do {
        var dic = PB()
        for j in 0..<10 {
          var entry = PB.Entry()
          entry.key = "key\(j)"
          entry.value = "default"
          // "名詞"
          entry.pos = .noun
          dic.entries.append(entry)
        }
        for j in 0..<10 {
          var entry = PB.Entry()
          entry.key = "key\(j)"
          entry.value = "suggest_only"
          // "サジェストのみ"
          entry.pos = .suggestionOnly
          dic.entries.append(entry)
        }
        storage.dictionaries.append(dic)
        userDic.load(storage)
      }

      do {
        let kKey = "key0123"
        let callback = CollectTokenCallback()
        userDic.lookupPrefix(kKey, callback: callback)
        #expect(callback.tokens.allSatisfy { $0.value == "default" })
      }
      do {
        let kKey = "key"
        let callback = CollectTokenCallback()
        userDic.lookupPredictive(kKey, callback: callback)
        #expect(callback.tokens.allSatisfy { $0.value == "suggest_only" || $0.value == "default" })
      }
    }
  }

  @Test func lookupCommentTest() async {
    await SystemUtil.withTempUserProfile { _ in
      let dic = createDictionaryWithMockPos()
      // Wait for async reload called from the constructor.
      await dic.waitForReloader()
      #expect(dic.load(bytes: loadFromString(kUserDictionary0)))

      // Entry is in user dictionary but has no comment.
      #expect(dic.lookupComment("comment_key1", "comment_value2") == nil)

      // Usual case: single key-value pair with comment.
      #expect(dic.lookupComment("comment_key2", "comment_value2") == "comment")

      // There exist two entries having the same key, value and POS.  Since POS is
      // irrelevant to comment lookup, the first nonempty comment should be found.
      #expect(dic.lookupComment("comment_key3", "comment_value3") == "comment1")

      // White-space only comments should be cleared.
      #expect(dic.lookupComment("comment_key4", "comment_value4") == nil)

      // Comment should be found iff key and value match.
      #expect(lookupComment(dic, "comment_key", "mismatching_value").isEmpty)
      #expect(lookupComment(dic, "comment_key1", "mismatching_value").isEmpty)
      #expect(lookupComment(dic, "comment_key2", "mismatching_value").isEmpty)
      #expect(lookupComment(dic, "comment_key3", "mismatching_value").isEmpty)
      #expect(lookupComment(dic, "comment_key4", "mismatching_value").isEmpty)
      #expect(lookupComment(dic, "mismatching_key", "comment_value").isEmpty)
      #expect(lookupComment(dic, "mismatching_key", "comment_value1").isEmpty)
      #expect(lookupComment(dic, "mismatching_key", "comment_value2").isEmpty)
      #expect(lookupComment(dic, "mismatching_key", "comment_value3").isEmpty)
      #expect(lookupComment(dic, "mismatching_key", "comment_value4").isEmpty)
    }
  }

  @Test func testPopulateTokenFromUserPosToken() async {
    await SystemUtil.withTempUserProfile { _ in
      let dic = createDictionaryWithMockPos()
      await dic.waitForReloader()

      var userToken = makeUserPosToken("key", "value", 10)
      userToken.setPosType(.saIrregularConjugationNoun)  // 名詞サ変
      let expectedCost = Int(UserPos.getCostFromPosType(.saIrregularConjugationNoun))

      var token = dic.populateTokenFromUserPosTokenForTesting(userToken, .prefix)
      #expect(token.key == "key")
      #expect(token.value == "value")
      #expect(token.lid == 10)
      #expect(token.rid == 10)
      #expect(token.cost == expectedCost)
      #expect(token.attributes == Token.Attribute.userDictionary)

      userToken.setPosType(.abbreviation)
      token = dic.populateTokenFromUserPosTokenForTesting(userToken, .prefix)
      #expect(token.cost == 200)

      userToken.setPosType(.suggestionOnly)
      token = dic.populateTokenFromUserPosTokenForTesting(userToken, .prefix)
      #expect(token.lid == posMatcher.getUnknownId())
      #expect(token.rid == posMatcher.getUnknownId())
      #expect(token.cost == expectedCost)

      userToken.setPosType(.noPos)
      token = dic.populateTokenFromUserPosTokenForTesting(userToken, .predictive)
      // NO_POS id is set via user_pos.def.
      #expect(token.cost == expectedCost)

      userToken.setPosType(.noPos)
      userToken.key = "a"  // one char
      token = dic.populateTokenFromUserPosTokenForTesting(userToken, .prefix)
      #expect(token.cost == expectedCost + 2000 * 3)

      userToken.key = "aa"
      token = dic.populateTokenFromUserPosTokenForTesting(userToken, .prefix)
      #expect(token.cost == expectedCost + 2000 * 2)

      userToken.key = "aaa"
      token = dic.populateTokenFromUserPosTokenForTesting(userToken, .prefix)
      #expect(token.cost == expectedCost + 2000)

      userToken.key = "aaaa"
      token = dic.populateTokenFromUserPosTokenForTesting(userToken, .prefix)
      #expect(token.cost == expectedCost)

      userToken.key = "aaaaaaa"
      token = dic.populateTokenFromUserPosTokenForTesting(userToken, .prefix)
      #expect(token.cost == expectedCost)
    }
  }

  @Test func testPopulateTokenFromUserPosTokenWithEntryPenalty() async {
    SystemUtil.withTempUserProfile { _ in
      let dic = createDictionaryWithMockPos()
      var storage = Genmai_UserDictionary_UserDictionaryStorage()
      var userDic = PB()
      for i in 0..<10 {
        var entry = PB.Entry()
        entry.key = "key\(i)"
        entry.value = "value\(i)"
        entry.pos = .noun
        userDic.entries.append(entry)
      }
      storage.dictionaries = [userDic]
      dic.load(storage)

      var userToken = makeUserPosToken("key0", "value0", 10)
      userToken.setPosType(.noun)
      var token = dic.populateTokenFromUserPosTokenForTesting(userToken, .prefix)
      let baseCost = Int(UserPos.getCostFromPosType(.noun))
      let expectedPenalty = Int(500.0 * Foundation.log(11.0))  // N = 10
      #expect(token.cost == baseCost + expectedPenalty)

      // POS type with cost 0 in user_pos.def (e.g. WA_GROUP1_VERB) uses default
      // cost (5000) without penalty.
      userToken.setPosType(.waGroup1Verb)
      token = dic.populateTokenFromUserPosTokenForTesting(userToken, .prefix)
      #expect(token.cost == 5000)

      // ABBREVIATION always uses fixed cost (200) without penalty.
      userToken.setPosType(.abbreviation)
      token = dic.populateTokenFromUserPosTokenForTesting(userToken, .prefix)
      #expect(token.cost == 200)

      // At N = 148, cost_penalty is Int(500 * log(149)) = 2501 >=
      // 2500, so the per-POS discount is fully phased out and all standard POS
      // types scale as 2500 + cost_penalty.
      for i in 10..<148 {
        var entry = PB.Entry()
        entry.key = "key\(i)"
        entry.value = "value\(i)"
        entry.pos = .noun
        userDic.entries.append(entry)
      }
      storage.dictionaries = [userDic]
      dic.load(storage)
      let penalty148 = Int(500.0 * Foundation.log(149.0))  // 2501
      for posType: PB.PosType in [.noun, .personalName, .symbol] {
        userToken.setPosType(posType)
        token = dic.populateTokenFromUserPosTokenForTesting(userToken, .prefix)
        #expect(token.cost == 2500 + penalty148)
      }
      userToken.setPosType(.abbreviation)
      token = dic.populateTokenFromUserPosTokenForTesting(userToken, .prefix)
      #expect(token.cost == 200)
    }
  }

  @Test func loadFromStreamTest() async throws {
    try await SystemUtil.withTempUserProfile { _ in
      let dic = createDictionaryWithMockPos()
      await dic.waitForReloader()

      var storage = Genmai_UserDictionary_UserDictionaryStorage()
      storage.version = 1
      var userDic = PB()
      userDic.id = 12345
      userDic.name = "test_dic"
      do {
        var entry = PB.Entry()
        entry.key = "start"
        entry.value = "start_val"
        entry.pos = .noun
        entry.comment = "test_comment"
        userDic.entries.append(entry)
      }
      do {
        var entry = PB.Entry()
        entry.key = "suppress_key"
        entry.value = "suppress_val"
        entry.pos = .suppressionWord
        userDic.entries.append(entry)
      }
      storage.dictionaries.append(userDic)

      var serialized: [UInt8] = try storage.serializedBytes()
      // Append unknown Fixed64 (tag = (15 << 3) | 1 = 0x79) and Fixed32
      // (tag = (15 << 3) | 5 = 0x7d) fields to verify SkipField handling.
      serialized += [0x79, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
      serialized += [0x7d, 0x01, 0x02, 0x03, 0x04]
      #expect(dic.load(bytes: serialized))

      #expect(lookupExact("start", dic) == [Entry("start", "start_val", 100, 100)])
      #expect(lookupComment(dic, "start", "start_val") == "test_comment")
      #expect(dic.isSuppressedEntry("suppress_key", "suppress_val"))

      // Corrupted streams (truncated length varint or Entry message) should fail
      // and keep existing tokens intact.
      #expect(!dic.load(bytes: [0x12]))
      #expect(!dic.load(bytes: [0x22]))
      #expect(!dic.load(bytes: [0x22, 0x05] + Array("xyz".utf8)))
      // Invalid wire type (wire type 6: tag = (15 << 3) | 6 = 0x7e) should fail.
      #expect(!dic.load(bytes: [0x7e]))

      #expect(lookupExact("start", dic) == [Entry("start", "start_val", 100, 100)])
    }
  }
}
