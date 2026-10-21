// Port of mozc/src/base/container/trie_test.cc (3.35.6354).

import Testing
@testable import GenmaiBase

@Suite struct TrieTest {
  @Test func trie() {
    let trie = Trie<String>()

    enum TestType {
      case lookup, add, remove
    }
    struct TestCase {
      let type: TestType
      let key: String
      let value: String
      let expectedFound: Bool
      let expectedValue: String
    }
    let testCases: [TestCase] = [
      TestCase(type: .add, key: "abc", value: "data_abc", expectedFound: true, expectedValue: "data_abc"),
      TestCase(type: .add, key: "abd", value: "data_abd", expectedFound: true, expectedValue: "data_abd"),
      TestCase(
        type: .add, key: "abcd", value: "data_abcd", expectedFound: true, expectedValue: "data_abcd"),
      TestCase(
        type: .add, key: "abc", value: "data_abc2", expectedFound: true, expectedValue: "data_abc2"),
      TestCase(type: .add, key: "bcd", value: "data_bcd", expectedFound: true, expectedValue: "data_bcd"),
      TestCase(type: .lookup, key: "abc", value: "", expectedFound: true, expectedValue: "data_abc2"),
      TestCase(type: .lookup, key: "abd", value: "", expectedFound: true, expectedValue: "data_abd"),
      TestCase(type: .lookup, key: "abcd", value: "", expectedFound: true, expectedValue: "data_abcd"),
      TestCase(type: .lookup, key: "bcd", value: "", expectedFound: true, expectedValue: "data_bcd"),
      TestCase(type: .lookup, key: "xyz", value: "", expectedFound: false, expectedValue: ""),
      TestCase(type: .lookup, key: "abcde", value: "", expectedFound: false, expectedValue: ""),
      TestCase(type: .remove, key: "bcd", value: "", expectedFound: false, expectedValue: ""),
      TestCase(type: .remove, key: "abd", value: "", expectedFound: false, expectedValue: ""),
      TestCase(type: .lookup, key: "abc", value: "", expectedFound: true, expectedValue: "data_abc2"),
      TestCase(type: .lookup, key: "abcd", value: "", expectedFound: true, expectedValue: "data_abcd"),
      TestCase(type: .remove, key: "abc", value: "", expectedFound: false, expectedValue: ""),
      TestCase(type: .lookup, key: "abcd", value: "", expectedFound: true, expectedValue: "data_abcd"),
      TestCase(type: .remove, key: "xyz", value: "", expectedFound: false, expectedValue: ""),
    ]
    for test in testCases {
      switch test.type {
      case .add:
        trie.addEntry(test.key, test.value)
      case .remove:
        trie.deleteEntry(test.key)
      case .lookup:
        // do nothing
        break
      }
      let other = Trie<String>()
      trie.swap(other)
      let data = other.lookUp(test.key)
      #expect((data != nil) == test.expectedFound)
      if let data {
        #expect(data == test.expectedValue)
      }
      #expect(trie.lookUp(test.key) == nil)
      trie.swap(other)
    }
  }

  @Test func longestMatch() {
    let trie = Trie<String>()
    trie.addEntry("abc", "[ABC]")
    trie.addEntry("abd", "[ABD]")
    trie.addEntry("a", "[A]")

    var value: String?
    var keyLength = 0
    #expect(trie.longestMatch("abc", &value, &keyLength))
    #expect(value == "[ABC]")
    #expect(keyLength == 3)

    value = nil
    keyLength = 0
    #expect(trie.longestMatch("abcd", &value, &keyLength))
    #expect(value == "[ABC]")
    #expect(keyLength == 3)

    value = nil
    keyLength = 0
    #expect(trie.longestMatch("abe", &value, &keyLength))
    #expect(value == "[A]")
    #expect(keyLength == 1)

    value = nil
    keyLength = 0
    #expect(trie.longestMatch("ac", &value, &keyLength))
    #expect(value == "[A]")
    #expect(keyLength == 1)

    value = nil
    keyLength = 0
    #expect(!trie.longestMatch("xyz", &value, &keyLength))
  }

  @Test func lookUpPrefix() {
    let trie = Trie<String>()
    trie.addEntry("abc", "[ABC]")
    trie.addEntry("abd", "[ABD]")
    trie.addEntry("a", "[A]")

    var value: String?
    var keyLength = 0
    var hasSubtrie = false
    #expect(trie.lookUpPrefix("abc", &value, &keyLength, &hasSubtrie))
    #expect(value == "[ABC]")
    #expect(keyLength == 3)

    value = nil
    keyLength = 0
    #expect(trie.lookUpPrefix("abcd", &value, &keyLength, &hasSubtrie))
    #expect(value == "[ABC]")
    #expect(keyLength == 3)

    value = nil
    keyLength = 0
    #expect(!trie.lookUpPrefix("abe", &value, &keyLength, &hasSubtrie))

    value = nil
    keyLength = 0
    #expect(trie.lookUpPrefix("ac", &value, &keyLength, &hasSubtrie))
    #expect(value == "[A]")
    #expect(keyLength == 1)

    value = nil
    keyLength = 0
    #expect(!trie.lookUpPrefix("xyz", &value, &keyLength, &hasSubtrie))
  }

  @Test func empty() {
    let trie = Trie<String>()
    do {
      var values: [String] = []
      trie.lookUpPredictiveAll("a", &values)
      #expect(values.isEmpty)
    }
    do {
      var value: String?
      var keyLength = 0
      var hasSubtrie = false
      #expect(!trie.lookUpPrefix("a", &value, &keyLength, &hasSubtrie))
      #expect(value == nil)
      #expect(keyLength == 0)
    }
  }

  @Test func utf8LookUpPrefix() {
    let trie = Trie<String>()
    for key in ["きゃ", "きゅ", "きょ", "っ", "か", "き", "く", "け", "こ"] {
      trie.addEntry(key, "")
    }

    var value: String?
    var keyLength = 0
    var hasSubtrie = false
    for query in ["か", "きゅ", "くぁ", "っあ", "き", "かかかかかか", "きゅあああ", "きあああ"] {
      keyLength = 0
      #expect(trie.lookUpPrefix(query, &value, &keyLength, &hasSubtrie), "\(query)")
    }
    keyLength = 0
    #expect(!trie.lookUpPrefix("も", &value, &keyLength, &hasSubtrie))
  }

  @Test func utf8LongestMatch() {
    let trie = Trie<String>()
    trie.addEntry("あいう", "アイウ")
    trie.addEntry("あいえ", "アイエ")
    trie.addEntry("あ", "ア")

    var value: String?
    var keyLength = 0
    #expect(trie.longestMatch("あいう", &value, &keyLength))
    #expect(value == "アイウ")
    #expect(keyLength == "あいう".utf8.count)

    value = nil
    keyLength = 0
    #expect(trie.longestMatch("あいうえ", &value, &keyLength))
    #expect(value == "アイウ")
    #expect(keyLength == "あいう".utf8.count)

    value = nil
    keyLength = 0
    #expect(trie.longestMatch("あい", &value, &keyLength))
    #expect(value == "ア")
    #expect(keyLength == "あ".utf8.count)

    value = nil
    keyLength = 0
    #expect(trie.longestMatch("あお", &value, &keyLength))
    #expect(value == "ア")
    #expect(keyLength == "あ".utf8.count)

    value = nil
    keyLength = 0
    #expect(!trie.longestMatch("お", &value, &keyLength))
  }

  @Test func lookUpPredictiveAll() {
    let trie = Trie<String>()
    trie.addEntry("abc", "[ABC]")
    trie.addEntry("abd", "[ABD]")
    trie.addEntry("a", "[A]")

    func lookup(_ key: String) -> [String] {
      var values: [String] = []
      trie.lookUpPredictiveAll(key, &values)
      return values
    }
    #expect(Set(lookup("a")) == ["[ABC]", "[ABD]", "[A]"])
    #expect(lookup("a").count == 3)
    #expect(Set(lookup("ab")) == ["[ABC]", "[ABD]"])
    #expect(lookup("ab").count == 2)
    #expect(lookup("abc") == ["[ABC]"])
    #expect(Set(lookup("")) == ["[ABC]", "[ABD]", "[A]"])
    #expect(lookup("").count == 3)
    #expect(lookup("x").isEmpty)
  }

  @Test func hasSubTrie() {
    let trie = Trie<String>()
    trie.addEntry("abc", "[ABC]")
    #expect(trie.hasSubTrie("a"))
    #expect(trie.hasSubTrie("ab"))
    #expect(trie.hasSubTrie("abc"))
    #expect(!trie.hasSubTrie("abcd"))
    #expect(!trie.hasSubTrie("b"))
    #expect(!trie.hasSubTrie(""))
  }
}
