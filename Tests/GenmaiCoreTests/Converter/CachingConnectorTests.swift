// Port of mozc/src/converter/caching_connector_test.cc (3.35.6354).

import Testing

@testable import GenmaiCore

@Suite(.enabled(if: ConverterCoreTestSupport.hasMockData, ConverterCoreTestSupport.mockDataMissing))
struct CachingConnectorTests {
  @Test func basicCacheWithoutBonus() throws {
    let connector = try ConverterCoreTestSupport.mockConnector()
    let conn = CachingConnector(hasBonus: false, connector, 0, try ConverterCoreTestSupport.mockPosMatcher())

    let kLid1: UInt16 = 10
    let kLid2: UInt16 = 20
    let kRid1: UInt16 = 5
    let kRid2: UInt16 = 15

    conn.resetCacheIfNecessary(kLid1)
    let cost1 = conn.getTransitionCost(kRid1, kLid1)
    #expect(cost1 == connector.getTransitionCost(kRid1, kLid1))

    // Cache hit.
    #expect(conn.getTransitionCost(kRid1, kLid1) == cost1)

    let cost2 = conn.getTransitionCost(kRid2, kLid1)
    #expect(cost2 == connector.getTransitionCost(kRid2, kLid1))
    #expect(conn.getTransitionCost(kRid2, kLid1) == cost2)

    // Switch right node LID.
    conn.resetCacheIfNecessary(kLid2)
    let costLid2 = conn.getTransitionCost(kRid1, kLid2)
    #expect(costLid2 == connector.getTransitionCost(kRid1, kLid2))

    // Switch back to LID1: rid2 is still cached for kLid1!
    conn.resetCacheIfNecessary(kLid1)
    #expect(conn.getTransitionCost(kRid2, kLid1) == cost2)
    // rid1 was overwritten with kLid2, so it misses and updates for kLid1.
    #expect(conn.getTransitionCost(kRid1, kLid1) == cost1)
  }

  @Test func largeRidBeyondCacheSize() throws {
    let connector = try ConverterCoreTestSupport.mockConnector()
    let conn = CachingConnector(hasBonus: false, connector, 0, try ConverterCoreTestSupport.mockPosMatcher())

    let kLargeRid: UInt16 = 2048  // Equal to kCacheSize
    let kLid: UInt16 = 10

    conn.resetCacheIfNecessary(kLid)
    let expected = connector.getTransitionCost(kLargeRid, kLid)
    #expect(conn.getTransitionCost(kLargeRid, kLid) == expected)
    // Call again: should still return expected without error.
    #expect(conn.getTransitionCost(kLargeRid, kLid) == expected)
  }

  @Test func withBonus() throws {
    let kBonus = 500
    let connector = try ConverterCoreTestSupport.mockConnector()
    let posMatcher = try ConverterCoreTestSupport.mockPosMatcher()
    let conn = CachingConnector(hasBonus: true, connector, kBonus, posMatcher)

    // Find a target LID and RID pair where the bonus applies.
    var targetLid: UInt16 = 0
    var foundLid = false
    var lid: UInt16 = 0
    while Int(lid) < connector.getResolution() {
      if posMatcher.isContentWordWithConjugation(lid) {
        targetLid = lid
        foundLid = true
        break
      }
      lid += 1
    }

    var targetRid: UInt16 = 0
    var foundRid = false
    for rid in UInt16(0)..<2048 where posMatcher.isContentNoun(rid) || posMatcher.isPronoun(rid) {
      targetRid = rid
      foundRid = true
      break
    }

    if foundLid && foundRid {
      conn.resetCacheIfNecessary(targetLid)
      let rawCost = connector.getTransitionCost(targetRid, targetLid)
      let expectedCost = max(0, rawCost - kBonus)
      #expect(conn.getTransitionCost(targetRid, targetLid) == expectedCost)

      // Verify cache hit returns the bonused cost.
      #expect(conn.getTransitionCost(targetRid, targetLid) == expectedCost)
    }
  }
}
