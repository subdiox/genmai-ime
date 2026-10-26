// Port of mozc/src/ios/ios_engine_test.cc (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import Testing

@testable import GenmaiIOS

@MainActor
@Suite(.enabled(if: MockDataManager.defaultDataPath != nil, "mock_genmai.data is missing"))
struct IosEngineTests {
  @Test func importUserDictionary() throws {
    let dataFilePath = try #require(MockDataManager.defaultDataPath)
    try SystemUtil.withTempUserProfile { _ in
      try ConfigHandler.withScopedHandlerForTesting {
        let engine = IosEngine(dataFilePath: dataFilePath)

        var command = Genmai_Commands_Command()
        var config = Genmai_Config_Config()
        IosEngine.fillMobileConfig(&config)
        #expect(engine.setConfig(config, &command))
        #expect(engine.setMobileRequest("12KEYS", &command))
        try #require(engine.createSession(&command))

        let tsv =
          "かおもじ\t(^-^)\t顔文字\n"
          + "てすと\tテスト単語\t品詞なし\n"
          + "invalid_line\n"
          + "\t空キー\t品詞なし\n"
          + "てすと\t\t品詞なし\n"
        #expect(engine.importUserDictionary(tsv, &command))
        #expect(command.input.type == .reload)

        let dbFile = ConfigFileStream.getFileName("user://user_dictionary.db")
        let data = try #require(FileManager.default.contents(atPath: dbFile))
        let storage = try Genmai_UserDictionary_UserDictionaryStorage(serializedBytes: data)
        try #require(storage.dictionaries.count == 1)
        let dic = storage.dictionaries[0]
        #expect(dic.name == "iOS_system_dictionary")
        try #require(dic.entries.count == 2)
        #expect(dic.entries[0].key == "かおもじ")
        #expect(dic.entries[0].value == "(^-^)")
        #expect(dic.entries[0].pos == .emoticon)
        #expect(dic.entries[1].key == "てすと")
        #expect(dic.entries[1].value == "テスト単語")
        #expect(dic.entries[1].pos == .noPos)

        // Importing an empty TSV clears the user dictionary.
        #expect(engine.importUserDictionary("", &command))
        #expect(command.input.type == .reload)

        let emptyData = try #require(FileManager.default.contents(atPath: dbFile))
        let emptyStorage = try Genmai_UserDictionary_UserDictionaryStorage(serializedBytes: emptyData)
        #expect(emptyStorage.dictionaries.isEmpty)

        #expect(engine.deleteSession(&command))
      }
    }
  }
}
