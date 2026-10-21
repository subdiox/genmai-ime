// Port of mozc/src/data_manager/serialized_dictionary_test.cc (3.35.6354).

import GenmaiBase
import Testing
@testable import GenmaiCore

@Suite struct SerializedDictionaryTest {
  static let kTestInput =
    "key1\t10\t20\t3000\tvalue1\tdesc1\tadesc1\n"  // Entry 1
    + "key1\t50\t60\t2000\tvalue2\tdesc2\tadesc2\n"  // Entry 2
    + "key2\t50\t60\t2000\tvalue3\n"  // Entry 3

  let tokenArrayData: DataView
  let stringArrayData: DataView

  init() {
    let data = SerializedDictionary.compile(InputFileStream(string: Self.kTestInput))
    tokenArrayData = DataView(copying: data.tokenArray)
    stringArrayData = DataView(copying: data.stringArray)
  }

  @Test func compile() throws {
    // compile() is called in init()

    let stringArray = try #require(SerializedStringArray(stringArrayData))
    try #require(stringArray.size == 10)
    #expect(stringArray[0] == "")
    #expect(stringArray[1] == "adesc1")
    #expect(stringArray[2] == "adesc2")
    #expect(stringArray[3] == "desc1")
    #expect(stringArray[4] == "desc2")
    #expect(stringArray[5] == "key1")
    #expect(stringArray[6] == "key2")
    #expect(stringArray[7] == "value1")
    #expect(stringArray[8] == "value2")
    #expect(stringArray[9] == "value3")

    // Recall that entries are sorted first by key then by cost.
    let kExpectedTokenArray = DataManagerTestSupport.cBytes(
      // Entry 2
      #"\x05\x00\x00\x00"#  // key = "key1", index = 5
        + #"\x08\x00\x00\x00"#  // value = "value2", index = 8
        + #"\x04\x00\x00\x00"#  // description = "desc2", index = 4
        + #"\x02\x00\x00\x00"#  // additional_description = "adesc2", index = 2
        + #"\x32\x00"#  // lid = 50
        + #"\x3c\x00"#  // rid = 60
        + #"\xd0\x07"#  // cost = 2000
        + #"\x00\x00"#  // padding
        // Entry 1
        + #"\x05\x00\x00\x00"#  // key = "key1", index = 5
        + #"\x07\x00\x00\x00"#  // value = "value1", index = 7
        + #"\x03\x00\x00\x00"#  // description = "desc1", index = 3
        + #"\x01\x00\x00\x00"#  // additional_description = "adesc1", index = 1
        + #"\x0a\x00"#  // lid = 10
        + #"\x14\x00"#  // rid = 20
        + #"\xb8\x0b"#  // cost = 3000
        + #"\x00\x00"#  // padding
        // Entry 3
        + #"\x06\x00\x00\x00"#  // key = "key2", index = 6
        + #"\x09\x00\x00\x00"#  // value = "value3", index = 9
        + #"\x00\x00\x00\x00"#  // description = "", index = 0
        + #"\x00\x00\x00\x00"#  // additional_description = "", index = 0
        + #"\x32\x00"#  // lid = 50
        + #"\x3c\x00"#  // rid = 60
        + #"\xd0\x07"#  // cost = 2000
        + #"\x00\x00"#)  // padding
    #expect(tokenArrayData.array == kExpectedTokenArray)
  }

  @Test func iterator() throws {
    let dic = SerializedDictionary(tokenArray: tokenArrayData, stringArrayData: stringArrayData)
    var iter = dic.startIndex

    try #require(iter != dic.endIndex)
    #expect(dic[iter].key == "key1")
    #expect(dic[iter].value == "value2")
    #expect(dic[iter].description == "desc2")
    #expect(dic[iter].additionalDescription == "adesc2")
    #expect(dic[iter].lid == 50)
    #expect(dic[iter].rid == 60)
    #expect(dic[iter].cost == 2000)

    iter += 1
    try #require(iter != dic.endIndex)
    #expect(dic[iter].key == "key1")
    #expect(dic[iter].value == "value1")
    #expect(dic[iter].description == "desc1")
    #expect(dic[iter].additionalDescription == "adesc1")
    #expect(dic[iter].lid == 10)
    #expect(dic[iter].rid == 20)
    #expect(dic[iter].cost == 3000)

    iter += 1
    try #require(iter != dic.endIndex)
    #expect(dic[iter].key == "key2")
    #expect(dic[iter].value == "value3")
    #expect(dic[iter].description.isEmpty)
    #expect(dic[iter].additionalDescription.isEmpty)
    #expect(dic[iter].lid == 50)
    #expect(dic[iter].rid == 60)
    #expect(dic[iter].cost == 2000)

    iter += 1
    #expect(iter == dic.endIndex)
  }

  @Test func equalRange() throws {
    let dic = SerializedDictionary(tokenArray: tokenArrayData, stringArrayData: stringArrayData)
    do {
      var range = dic.equalRange("key1")
      try #require(!range.isEmpty)
      #expect(dic[range.lowerBound].key == "key1")
      #expect(dic[range.lowerBound].value == "value2")

      range = (range.lowerBound + 1)..<range.upperBound
      try #require(!range.isEmpty)
      #expect(dic[range.lowerBound].key == "key1")
      #expect(dic[range.lowerBound].value == "value1")

      range = (range.lowerBound + 1)..<range.upperBound
      #expect(range.isEmpty)
    }
    do {
      var range = dic.equalRange("key2")
      try #require(!range.isEmpty)
      #expect(dic[range.lowerBound].key == "key2")
      #expect(dic[range.lowerBound].value == "value3")

      range = (range.lowerBound + 1)..<range.upperBound
      #expect(range.isEmpty)
    }
    do {
      let range = dic.equalRange("mozc")
      #expect(range.isEmpty)
    }
  }

  // Swift-only: verifyData rejects out-of-range string indices and sizes that
  // are not a multiple of the token length.
  @Test func verifyData() {
    #expect(SerializedDictionary.verifyData(tokenArrayData, stringArrayData))
    #expect(!SerializedDictionary.verifyData(tokenArrayData.slice(0, 23), stringArrayData))
    var broken = tokenArrayData.array
    broken[0] = 10  // key index 10 >= string array size 10
    #expect(!SerializedDictionary.verifyData(DataView(copying: broken), stringArrayData))
  }
}
