// Segmenter tests: port of DataManagerTestBase::SegmenterTest_{LNode,RNode,
// Node,Particle}Test (data_manager/data_manager_test_base.cc, 3.35.6354) for
// the mock data set (sampled). The full checks, including
// SegmenterTest_SameAsInternal, run in DataManager/DataManagerTestBase.swift.

import Testing

@testable import GenmaiCore

@Suite(.enabled(if: ConverterCoreTestSupport.hasMockData, ConverterCoreTestSupport.mockDataMissing))
struct SegmenterTests {
  private func makeSegmenter() throws -> (Segmenter, Int) {
    let dm = try ConverterCoreTestSupport.mockDataManager()
    let reader = ConnectionFileReader(
      ConverterCoreTestSupport.sourcePath("data", "test", "dictionary", "connection_single_column.txt"))
    return (Segmenter(dataManager: dm), reader.leftSize)
  }

  @Test func lNodeTest() throws {
    let (segmenter, size) = try makeSegmenter()
    // lnode is BOS
    let lnode = Node()
    let rnode = Node()
    lnode.nodeType = .bosNode
    rnode.nodeType = .norNode
    var ok = true
    for rid in stride(from: 0, to: size, by: 7) {
      for lid in 0..<size {
        lnode.rid = UInt16(rid)
        lnode.lid = UInt16(lid)
        ok = ok && segmenter.isBoundary(lnode, rnode, false) && segmenter.isBoundary(lnode, rnode, true)
      }
    }
    #expect(ok)
  }

  @Test func rNodeTest() throws {
    let (segmenter, size) = try makeSegmenter()
    // rnode is EOS
    let lnode = Node()
    let rnode = Node()
    lnode.nodeType = .norNode
    rnode.nodeType = .eosNode
    var ok = true
    for rid in stride(from: 0, to: size, by: 7) {
      for lid in 0..<size {
        lnode.rid = UInt16(rid)
        lnode.lid = UInt16(lid)
        ok = ok && segmenter.isBoundary(lnode, rnode, false) && segmenter.isBoundary(lnode, rnode, true)
      }
    }
    #expect(ok)
  }

  @Test func nodeTest() throws {
    let (segmenter, size) = try makeSegmenter()
    let lnode = Node()
    let rnode = Node()
    lnode.nodeType = .norNode
    rnode.nodeType = .norNode
    var ok = true
    var boundaries = 0
    for rid in 0..<size {
      for lid in 0..<size {
        lnode.rid = UInt16(rid)
        rnode.lid = UInt16(lid)
        let b = segmenter.isBoundary(UInt16(rid), UInt16(lid))
        if b { boundaries += 1 }
        ok = ok && b == segmenter.isBoundary(lnode, rnode, false) && !segmenter.isBoundary(lnode, rnode, true)
      }
    }
    #expect(ok)
    #expect(boundaries > 0 && boundaries < size * size)
  }

  @Test func particleTest() throws {
    let (segmenter, _) = try makeSegmenter()
    let posMatcher = try ConverterCoreTestSupport.mockPosMatcher()
    let lnode = Node()
    let rnode = Node()
    lnode.nodeType = .norNode
    rnode.nodeType = .norNode
    // "助詞"
    lnode.rid = posMatcher.getAcceptableParticleAtBeginOfSegmentId()
    // "名詞,サ変".
    rnode.lid = posMatcher.getUnknownId()
    #expect(segmenter.isBoundary(lnode, rnode, false))

    lnode.attributes |= Node.Attribute.startsWithParticle
    #expect(!segmenter.isBoundary(lnode, rnode, false))
  }

  @Test func penalties() throws {
    let (segmenter, size) = try makeSegmenter()
    let dm = try ConverterCoreTestSupport.mockDataManager()
    let boundary = dm.getSegmenterData().boundaryData
    for id in [0, 1, size / 2, size - 1] {
      #expect(segmenter.getPrefixPenalty(UInt16(id)) == Int32(boundary[2 * id]))
      #expect(segmenter.getSuffixPenalty(UInt16(id)) == Int32(boundary[2 * id + 1]))
    }
  }
}
