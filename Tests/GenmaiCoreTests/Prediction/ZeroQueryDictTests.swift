// Port of mozc/src/prediction/zero_query_dict_test.cc (3.35.6354).

import GenmaiBase
import Testing

@testable import GenmaiCore

private let kTestTokenArray: [UInt8] = DataManagerTestSupport.cBytes(
  // The last two items must be 0x00, because they are now unused field.
  // {"あ", "", ZERO_QUERY_EMOJI, 0x00, 0x00}
  #"\x04\x00\x00\x00"# + #"\x00\x00\x00\x00"# + #"\x03\x00"# + #"\x00\x00"#
    + #"\x00\x00\x00\x00"#
    // {"あ", "❕", ZERO_QUERY_EMOJI, 0x00, 0x00},
    + #"\x04\x00\x00\x00"# + #"\x02\x00\x00\x00"# + #"\x03\x00"# + #"\x00\x00"#
    + #"\x00\x00\x00\x00"#
    // {"あ", "❣", ZERO_QUERY_NONE, 0x00, 0x00},
    + #"\x04\x00\x00\x00"# + #"\x03\x00\x00\x00"# + #"\x00\x00"# + #"\x00\x00"#
    + #"\x00\x00\x00\x00"#
    // {"ああ", "( •̀ㅁ•́;)", ZERO_QUERY_EMOTICON, 0x00, 0x00}
    + #"\x05\x00\x00\x00"# + #"\x01\x00\x00\x00"# + #"\x02\x00"# + #"\x00\x00"#
    + #"\x00\x00\x00\x00"#)

private let kTestStrings = ["", "( •̀ㅁ•́;)", "❕", "❣", "あ", "ああ"]

/// Initializes a ZeroQueryDict from the above test data.
private func initTestZeroQueryDict() -> ZeroQueryDict {
  let stringArrayData = SerializedStringArray.serializeToBuffer(kTestStrings)
  return ZeroQueryDict(DataView(copying: kTestTokenArray), DataView(copying: stringArrayData))
}

struct ZeroQueryDictTests {
  @Test func iterateForwardByPreIncrement() {
    let dict = initTestZeroQueryDict()
    let entries = dict.getZeroQueryEntries()
    #expect(entries.count == 4)

    #expect(entries[0].keyIndex == 4)  // Index to "あ"
    #expect(entries[0].valueIndex == 0)  // Index to ""
    #expect(entries[0].type == .emoji)
    #expect(dict.key(entries[0]) == "あ")
    #expect(dict.value(entries[0]) == "")

    #expect(entries[1].keyIndex == 4)  // Index to "あ"
    #expect(entries[1].valueIndex == 2)  // Index to "❕"
    #expect(entries[1].type == .emoji)
    #expect(dict.key(entries[1]) == "あ")
    #expect(dict.value(entries[1]) == "❕")

    #expect(entries[2].keyIndex == 4)  // Index to "あ"
    #expect(entries[2].valueIndex == 3)  // Index to "❣"
    #expect(entries[2].type == ZeroQueryType.none)
    #expect(dict.key(entries[2]) == "あ")
    #expect(dict.value(entries[2]) == "❣")

    #expect(entries[3].keyIndex == 5)  // Index to "ああ"
    #expect(entries[3].valueIndex == 1)  // Index to "( •̀ㅁ•́;)"
    #expect(entries[3].type == .emoticon)
    #expect(dict.key(entries[3]) == "ああ")
    #expect(dict.value(entries[3]) == "( •̀ㅁ•́;)")
  }

  @Test func equalRange() {
    let dict = initTestZeroQueryDict()

    #expect(dict.equalRange("あ").count == 3)
    #expect(dict.equalRange("ああ").count == 1)
    #expect(dict.equalRange("This key is not found").isEmpty)
  }

  @Test func uninitializedTest() {
    let dict = ZeroQueryDict()
    #expect(dict.getZeroQueryEntries().isEmpty)
    #expect(dict.equalRange("あ").isEmpty)
  }
}
