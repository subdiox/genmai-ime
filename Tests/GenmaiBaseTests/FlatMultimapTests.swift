// Port of mozc/src/base/container/flat_multimap_test.cc (3.35.6354).

import Testing

@testable import GenmaiBase

@Suite struct FlatMultimapTest {
  private func values(_ span: ArraySlice<(Int, String)>, key: Int) -> Set<String> {
    for (k, _) in span {
      #expect(k == key)
    }
    return Set(span.map { $0.1 })
  }

  private func check(_ kMultimap: FlatMultimap<Int, String>) {
    #expect(kMultimap.equalSpan(0).isEmpty)
    #expect(kMultimap.equalSpan(1).count == 2)
    #expect(values(kMultimap.equalSpan(1), key: 1) == ["one", "ichi"])
    #expect(kMultimap.equalSpan(2).isEmpty)
    #expect(kMultimap.equalSpan(3).count == 2)
    #expect(values(kMultimap.equalSpan(3), key: 3) == ["three", "san"])
    #expect(kMultimap.equalSpan(4).isEmpty)
    #expect(kMultimap.equalSpan(5).count == 2)
    #expect(values(kMultimap.equalSpan(5), key: 5) == ["five", "go"])
    #expect(kMultimap.equalSpan(6).isEmpty)
  }

  static let kEntries: [(Int, String)] = [
    (1, "one"),
    (3, "three"),
    (5, "five"),
    (1, "ichi"),
    (3, "san"),
    (5, "go"),
  ]

  @Test func equalSpan() {
    check(FlatMultimap<Int, String>(Self.kEntries))
  }

  @Test func customCompare() {
    check(FlatMultimap<Int, String>(Self.kEntries, by: { $0 > $1 }))
  }
}
