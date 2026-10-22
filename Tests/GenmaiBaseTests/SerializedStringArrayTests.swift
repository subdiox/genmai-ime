// Port of mozc/src/base/container/serialized_string_array_test.cc (3.35.6354).

import Foundation
import Testing

@testable import GenmaiBase

@Suite struct SerializedStringArrayTest {
  @Test func defaultConstructor() {
    let a = SerializedStringArray()
    #expect(a.isEmpty)
    #expect(a.size == 0)
  }

  @Test func emptyArray() throws {
    let kData: [UInt8] = [0, 0, 0, 0]
    #expect(SerializedStringArray.verifyData(kData))

    let a = try #require(SerializedStringArray(bytes: kData))
    #expect(a.isEmpty)
    #expect(a.size == 0)
  }

  static let kTestData: [UInt8] = cBytes(
    #"\x03\x00\x00\x00"#  // Array size = 3
      + #"\x1c\x00\x00\x00\x05\x00\x00\x00"#  // (28, 5)
      + #"\x22\x00\x00\x00\x04\x00\x00\x00"#  // (34, 4)
      + #"\x27\x00\x00\x00\x06\x00\x00\x00"#  // (39, 6)
      + #"Hello\x00"#  // offset = 28, len = 5
      + #"Mozc\x00"#  // offset = 34, len = 4
      + #"google\x00"#)  // offset = 39, len = 6

  @Test func serializeToBuffer() {
    #expect(SerializedStringArray.serializeToBuffer(["Hello", "Mozc", "google"]) == Self.kTestData)
    let strs: [Substring] = ["Hello", "Mozc", "google"]
    #expect(SerializedStringArray.serializeToBuffer(strs) == Self.kTestData)
  }

  @Test func basic() {
    #expect(SerializedStringArray.verifyData(Self.kTestData))

    guard let a0 = SerializedStringArray(bytes: Self.kTestData) else {
      Issue.record("Init failed")
      return
    }
    var a = a0
    #expect(a.size == 3)
    #expect(a[0] == "Hello")
    #expect(a[1] == "Mozc")
    #expect(a[2] == "google")

    var b = SerializedStringArray()
    b.set(a.data)
    #expect(b.size == 3)
    #expect(b[0] == "Hello")
    #expect(b[1] == "Mozc")
    #expect(b[2] == "google")

    var empty = SerializedStringArray()
    b.swap(&empty)
    #expect(b.isEmpty)
    #expect(empty[0] == "Hello")

    a.clear()
    #expect(a.isEmpty)
    #expect(a.size == 0)
  }

  @Test func initFromData() {
    // A slice that does not start at index 0.
    let data = (Data([0xff]) + Data(Self.kTestData)).dropFirst()
    var a = SerializedStringArray()
    let ok = a.initialize(data)
    #expect(ok)
    #expect(Array(a) == ["Hello", "Mozc", "google"])
    #expect(a.utf8(at: 1) == Array("Mozc".utf8))
    #expect(Array(a.data(at: 2)) == Array("google".utf8))
    #expect(a.utf8(at: 1) == Array("Mozc".utf8))
    #expect(a.compare(at: 1, bytes: Array("Mozc".utf8)) == 0)
    #expect(a.compare(at: 1, bytes: Array("Moz".utf8)) == 1)
    #expect(a.compare(at: 1, bytes: Array("Mozd".utf8)) == -1)
    #expect(a.comparePrefix(at: 1, bytes: Array("Moz".utf8)) == 0)
    #expect(a.equals(at: 1, bytes: Array("Mozc".utf8)))
    #expect(!a.equals(at: 1, bytes: Array("Moz".utf8)))
    // Invalid data.
    var broken = Self.kTestData
    broken[broken.count - 1] = 0x41  // not null-terminated
    #expect(!SerializedStringArray.verifyData(broken))
    #expect(SerializedStringArray(bytes: broken) == nil)
    #expect(!SerializedStringArray.verifyData([0, 0, 0]))
    #expect(!SerializedStringArray.verifyData([1, 0, 0, 0]))
  }

  @Test func iterator() throws {
    #expect(SerializedStringArray.verifyData(Self.kTestData))

    let a = try #require(SerializedStringArray(bytes: Self.kTestData))
    do {
      var iter = a.startIndex
      #expect(a.endIndex != iter)
      #expect(a[iter] == "Hello")
      iter += 1
      #expect(a.endIndex != iter)
      #expect(a[iter] == "Mozc")
      iter += 1
      #expect(a.endIndex != iter)
      #expect(a[iter] == "google")
      iter += 1
      #expect(iter == a.endIndex)
    }
    #expect(a.binarySearch("Hello"))
    #expect(a.binarySearch("Mozc"))
    #expect(a.binarySearch("google"))
    #expect(!a.binarySearch("Japan"))
    #expect(a.lowerBound("Japan") == 1)
    #expect(a.upperBound("Mozc") == 2)
  }
}
