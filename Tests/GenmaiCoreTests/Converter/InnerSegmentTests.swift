// Port of mozc/src/converter/inner_segment_test.cc (3.35.6354).

import Testing
@testable import GenmaiCore

@Suite struct InnerSegmentTests {
  private typealias SVList = [String]

  private func getSegments(_ innerSegments: InnerSegments) -> (
    keys: SVList, values: SVList, contentKeys: SVList, contentValues: SVList, functionalKeys: SVList,
    functionalValues: SVList
  ) {
    var r: (SVList, SVList, SVList, SVList, SVList, SVList) = ([], [], [], [], [], [])
    for iter in innerSegments {
      r.0.append(String(iter.key))
      r.1.append(String(iter.value))
      r.2.append(String(iter.contentKey))
      r.3.append(String(iter.contentValue))
      r.4.append(String(iter.functionalKey))
      r.5.append(String(iter.functionalValue))
    }
    return r
  }

  @Test func innerSegmentIterator() {
    let key = "testfoobar"
    let value = "redgreenblue"
    let boundary = buildInnerSegmentBoundary([(4, 3, 4, 3), (6, 9, 3, 5)], key, value)
    let innerSegments = InnerSegments(key: key, value: value, innerSegmentBoundary: boundary)
    #expect(innerSegments.size == 2)
    #expect(innerSegments.description == "<4,3,4,3><6,9,3,5>")

    let s = getSegments(innerSegments)
    #expect(s.keys == ["test", "foobar"])
    #expect(s.values == ["red", "greenblue"])
    #expect(s.contentKeys == ["test", "foo"])
    #expect(s.contentValues == ["red", "green"])
    #expect(s.functionalKeys == ["", "bar"])
    #expect(s.functionalValues == ["", "blue"])

    let merged = innerSegments.getMergedContentKeyAndValue()
    #expect(merged.key == "testfoo")
    #expect(merged.value == "redgreen")
  }

  @Test func innerSegmentIteratorBuilder() {
    var builder = InnerSegmentBoundaryBuilder()
    // 私の|名は
    builder.add(12, 6, 9, 6)
    builder.add(6, 6, 3, 3)
    let boundary = builder.build("私の", "名は")

    var builder2 = InnerSegmentBoundaryBuilder()
    for encoded in boundary {
      builder2.addEncoded(encoded)
    }
    let boundary2 = builder2.build("私の", "名は")
    #expect(boundary == boundary2)
  }

  // Swift-only: the encoding is persisted, so it must match the C++ bit field.
  @Test func encodeLengthsLayout() {
    #expect(encodeLengths(5, 6, 3, 4) == 0x0403_0605)
    #expect(encodeLengths(1, 2, 3, 4) == 0x0201_0201)
    #expect(encodeLengths(0, 2, 3, 4) == nil)
    #expect(encodeLengths(256, 2, 3, 4) == nil)
    // content lengths 0 or too long are fixed to full lengths.
    #expect(encodeLengths(5, 6, 0, 7) == 0x0605_0605)
    let d = decodeLengths(0x0403_0201)
    #expect(d == InnerSegmentLengthData(keyLen: 1, valueLen: 2, contentKeyLen: 3, contentValueLen: 4))
  }

  @Test func innerSegmentIteratorEmpty() {
    // boundary info is not specified.
    do {
      let inner = InnerSegments(key: "abc", value: "ABC", innerSegmentBoundary: [])
      #expect(inner.size == 1)
      let s = getSegments(inner)
      #expect(s.keys == ["abc"])
      #expect(s.values == ["ABC"])
      #expect(s.contentKeys == ["abc"])
      #expect(s.contentValues == ["ABC"])
      #expect(s.functionalKeys == [""])
      #expect(s.functionalValues == [""])
    }
    do {
      // Respects the length of content_key and content_value.
      let inner = InnerSegments(key: "abc", value: "ABC", contentKey: "ab", contentValue: "A", innerSegmentBoundary: [])
      #expect(inner.size == 1)
      let s = getSegments(inner)
      #expect(s.keys == ["abc"])
      #expect(s.values == ["ABC"])
      #expect(s.contentKeys == ["ab"])
      #expect(s.contentValues == ["A"])
      #expect(s.functionalKeys == ["c"])
      #expect(s.functionalValues == ["BC"])
    }
  }

  private func expectSingle(_ inner: InnerSegments, _ key: String, _ value: String) {
    #expect(inner.size == 1)
    let s = getSegments(inner)
    #expect(s.keys == [key])
    #expect(s.values == [value])
    #expect(s.contentKeys == [key])
    #expect(s.contentValues == [value])
  }

  @Test func innerSegmentIteratorInvalid() {
    // Invalid boundary (total key length mismatches key.size()): ignored and
    // handled as a single segment.
    do {
      let boundary = buildInnerSegmentBoundary([(2, 3, 2, 3)], "ab", "ABC")
      #expect(boundary.count == 1)
      expectSingle(InnerSegments(key: "abc", value: "ABC", innerSegmentBoundary: boundary), "abc", "ABC")
    }
    // Boundary info is not enough: ignored and handled as a single segment.
    do {
      let boundary = buildInnerSegmentBoundary([(1, 1, 1, 1)], "a", "A")
      expectSingle(InnerSegments(key: "abc", value: "ABC", innerSegmentBoundary: boundary), "abc", "ABC")
    }
    // Too many boundaries: ignored and handled as a single segment.
    do {
      let boundary = buildInnerSegmentBoundary(
        [(1, 1, 1, 1), (1, 1, 1, 1), (1, 1, 1, 1), (1, 1, 1, 1), (1, 1, 1, 1)], "aaaaa", "AAAAA")
      expectSingle(InnerSegments(key: "abc", value: "ABC", innerSegmentBoundary: boundary), "abc", "ABC")
    }
    // Stale boundary from half-width "2日" (4 bytes) applied to full-width "２日"
    // (6 bytes): ignored instead of slicing in the middle of a UTF-8 character.
    do {
      let staleBoundary = buildInnerSegmentBoundary([(9, 4, 9, 4)], "ふつか", "2日")
      #expect(staleBoundary.count == 1)
      expectSingle(
        InnerSegments(
          key: "ふつか", value: "２日", contentKey: "ふつか", contentValue: "２日", innerSegmentBoundary: staleBoundary),
        "ふつか", "２日")
    }
    // Boundary whose total byte length matches key/value, but slices in the
    // middle of a multi-byte UTF-8 character (at byte 2 of "２日"): ignored.
    do {
      let midUtf8Boundary = buildInnerSegmentBoundary([(3, 2, 3, 2), (6, 4, 6, 4)], "ふつか", "２日")
      #expect(midUtf8Boundary.count == 2)
      expectSingle(
        InnerSegments(
          key: "ふつか", value: "２日", contentKey: "ふつか", contentValue: "２日",
          innerSegmentBoundary: midUtf8Boundary),
        "ふつか", "２日")
    }
    // empty key/value.
    do {
      let inner = InnerSegments(key: "", value: "", innerSegmentBoundary: [1])
      #expect(inner.size == 0)
      #expect(getSegments(inner).keys.isEmpty)
    }
    // empty key.  allows empty key as value is not empty.
    do {
      let inner = InnerSegments(key: "", value: "value", innerSegmentBoundary: [])
      #expect(inner.size == 1)
      let s = getSegments(inner)
      #expect(s.keys == [""])
      #expect(s.values == ["value"])
    }
  }

  private func makeThreeSegments() -> InnerSegments {
    var allKey = ""
    var allValue = ""
    var builder = InnerSegmentBoundaryBuilder()
    for i in 0..<3 {
      let key = "k\(i)"
      let value = "v\(i)"
      builder.add(key.utf8.count, value.utf8.count, key.utf8.count, value.utf8.count)
      allKey += key
      allValue += value
    }
    let boundary = builder.build(allKey, allValue)
    return InnerSegments(key: allKey, value: allValue, innerSegmentBoundary: boundary)
  }

  @Test func getSuffixKeyAndValue() {
    do {
      let inner = makeThreeSegments()
      #expect(inner.size == 3)
      #expect(inner.getSuffixKeyAndValue().key == "k0k1k2")
      #expect(inner.getSuffixKeyAndValue().value == "v0v1v2")
      let expected: [(Int, String, String)] = [
        (-1, "k0k1k2", "v0v1v2"), (10, "k0k1k2", "v0v1v2"), (0, "", ""), (1, "k2", "v2"),
        (2, "k1k2", "v1v2"), (3, "k0k1k2", "v0v1v2"), (4, "k0k1k2", "v0v1v2"),
      ]
      for (size, k, v) in expected {
        #expect(inner.getSuffixKeyAndValue(size).key == k[...])
        #expect(inner.getSuffixKeyAndValue(size).value == v[...])
      }
    }
    do {
      let inner = InnerSegments(key: "", value: "", innerSegmentBoundary: [])
      #expect(inner.size == 0)
      for size in [-1, 10, 0, 2, 1] {
        #expect(inner.getSuffixKeyAndValue(size).key == "")
        #expect(inner.getSuffixKeyAndValue(size).value == "")
      }
    }
    do {
      let inner = InnerSegments(key: "key", value: "value", innerSegmentBoundary: [])
      #expect(inner.size == 1)
      for size in [-1, 1, 2] {
        #expect(inner.getSuffixKeyAndValue(size).key == "key")
        #expect(inner.getSuffixKeyAndValue(size).value == "value")
      }
    }
  }

  @Test func getPrefixKeyAndValue() {
    do {
      let inner = makeThreeSegments()
      #expect(inner.size == 3)
      #expect(inner.getPrefixKeyAndValue().key == "k0k1k2")
      #expect(inner.getPrefixKeyAndValue().value == "v0v1v2")
      let expected: [(Int, String, String)] = [
        (-1, "k0k1k2", "v0v1v2"), (10, "k0k1k2", "v0v1v2"), (0, "", ""), (1, "k0", "v0"),
        (2, "k0k1", "v0v1"), (3, "k0k1k2", "v0v1v2"), (4, "k0k1k2", "v0v1v2"),
      ]
      for (size, k, v) in expected {
        #expect(inner.getPrefixKeyAndValue(size).key == k[...])
        #expect(inner.getPrefixKeyAndValue(size).value == v[...])
      }
    }
    do {
      let inner = InnerSegments(key: "", value: "", innerSegmentBoundary: [])
      #expect(inner.size == 0)
      for size in [-1, 10, 0, 2, 1] {
        #expect(inner.getPrefixKeyAndValue(size).key == "")
        #expect(inner.getPrefixKeyAndValue(size).value == "")
      }
    }
    do {
      let inner = InnerSegments(key: "key", value: "value", innerSegmentBoundary: [])
      #expect(inner.size == 1)
      for size in [-1, 1, 2] {
        #expect(inner.getPrefixKeyAndValue(size).key == "key")
        #expect(inner.getPrefixKeyAndValue(size).value == "value")
      }
    }
  }

  private struct DummyResult: InnerSegmentValueRewritable {
    var key: String
    var value: String
    var innerSegmentBoundary: InnerSegmentBoundary = []
    func innerSegments() -> InnerSegments {
      InnerSegments(key: key, value: value, innerSegmentBoundary: innerSegmentBoundary)
    }
    static var hasContentValue: Bool { false }
    var rewritableContentValue: String {
      get { "" }
      set {}
    }
  }

  @Test func rewriteCandidateValuesTest() {
    // Without inner_segment_boundary.
    do {
      var result = DummyResult(key: "key", value: "val")
      rewriteCandidateValues({ $0 + "!" }, &result)
      #expect(result.value == "val!")
      #expect(result.innerSegmentBoundary.isEmpty)
    }
    // With inner_segment_boundary and content_value.
    do {
      var candidate = Candidate()
      candidate.key = "k1k2f"
      candidate.value = "v1v2f"
      candidate.contentKey = "k1k2"
      candidate.contentValue = "v1v2"
      candidate.innerSegmentBoundary = buildInnerSegmentBoundary([(2, 2, 2, 2), (3, 3, 2, 2)], "k1k2f", "v1v2f")
      rewriteCandidateValues({ String($0) + String($0) }, &candidate)
      #expect(candidate.value == "v1v1v2fv2f")
      #expect(candidate.contentValue == "v1v2v1v2")
      #expect(
        candidate.innerSegmentBoundary
          == buildInnerSegmentBoundary([(2, 4, 2, 4), (3, 6, 2, 4)], "k1k2f", "v1v1v2fv2f"))
    }
  }
}
