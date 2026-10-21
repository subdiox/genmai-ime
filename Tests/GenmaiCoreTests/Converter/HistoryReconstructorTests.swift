// Port of mozc/src/converter/history_reconstructor_test.cc (3.35.6354).

import GenmaiBase
import Testing

@testable import GenmaiCore

@Suite("HistoryReconstructor")
struct HistoryReconstructorTests {
  @Test func getLastConnectivePart() throws {
    let dataManager = try MockDataManager()
    let posMatcher = PosMatcher(dataManager.getPosMatcherData())
    let reconstructor = HistoryReconstructor(posMatcher)

    do {
      var key = ""
      var value = ""
      var id: UInt16 = 0
      #expect(!reconstructor.getLastConnectivePart("", &key, &value, &id))
      #expect(!reconstructor.getLastConnectivePart(" ", &key, &value, &id))
      #expect(!reconstructor.getLastConnectivePart("  ", &key, &value, &id))
    }

    do {
      var key = ""
      var value = ""
      var id: UInt16 = 0
      #expect(reconstructor.getLastConnectivePart("a", &key, &value, &id))
      #expect(key == "a")
      #expect(value == "a")
      #expect(id == posMatcher.getUniqueNounId())

      #expect(reconstructor.getLastConnectivePart("a ", &key, &value, &id))
      #expect(key == "a")
      #expect(value == "a")

      #expect(!reconstructor.getLastConnectivePart("a  ", &key, &value, &id))

      #expect(reconstructor.getLastConnectivePart("a ", &key, &value, &id))
      #expect(key == "a")
      #expect(value == "a")

      #expect(reconstructor.getLastConnectivePart("a10a", &key, &value, &id))
      #expect(key == "a")
      #expect(value == "a")

      #expect(reconstructor.getLastConnectivePart("ａ", &key, &value, &id))
      #expect(key == "a")
      #expect(value == "ａ")
    }

    do {
      var key = ""
      var value = ""
      var id: UInt16 = 0
      #expect(reconstructor.getLastConnectivePart("10", &key, &value, &id))
      #expect(key == "10")
      #expect(value == "10")
      #expect(id == posMatcher.getNumberId())

      #expect(reconstructor.getLastConnectivePart("10a10", &key, &value, &id))
      #expect(key == "10")
      #expect(value == "10")

      #expect(reconstructor.getLastConnectivePart("１０", &key, &value, &id))
      #expect(key == "10")
      #expect(value == "１０")
    }

    do {
      var key = ""
      var value = ""
      var id: UInt16 = 0
      #expect(!reconstructor.getLastConnectivePart("あ", &key, &value, &id))
    }
  }

  @Test func reconstructHistory() throws {
    let dataManager = try MockDataManager()
    let posMatcher = PosMatcher(dataManager.getPosMatcherData())
    let reconstructor = HistoryReconstructor(posMatcher)

    let kTen = "１０"

    let segments = Segments()
    #expect(reconstructor.reconstructHistory(kTen, segments))
    try #require(segments.segmentsSize == 1)
    let segment = segments.segment(0)
    #expect(segment.segmentType == .history)
    #expect(segment.key == "10")
    try #require(segment.candidatesSize == 1)
    let candidate = segment.candidate(0)
    #expect(candidate.attributes == Attribute.noLearning)
    #expect(candidate.contentKey == "10")
    #expect(candidate.key == "10")
    #expect(candidate.contentValue == kTen)
    #expect(candidate.value == kTen)
    #expect(candidate.lid != 0)
    #expect(candidate.rid != 0)
  }
}
