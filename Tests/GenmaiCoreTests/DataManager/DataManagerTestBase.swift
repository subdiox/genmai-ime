// Port of mozc/src/data_manager/data_manager_test_base.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - IsBoundaryFunc (the generated segmenter_inl.inc IsBoundaryInternal) is a
//   closure; the data-set tests evaluate the segmenter rule files with
//   SegmenterInternal (same algorithm as gen_segmenter_code.py).
// - ConnectorTest_RandomValueCheck samples with probability 1/100000 like the
//   C++ (with a seeded generator for reproducibility).

import Foundation
import GenmaiBase
import Testing

@testable import GenmaiCore

struct DataManagerTestBase {
  typealias IsBoundaryFunc = (Int, Int) -> Bool

  let dataManager: DataManager
  // The following three are used in segmenter test.
  let lsize: Int
  let rsize: Int
  let isBoundary: IsBoundaryFunc
  // The following two are used in connector test.
  let connectionTxtFile: String
  let expectedResolution: Int
  // The following two are used in suggestion filter test.
  let dictionaryFiles: [String]
  let suggestionFilterFiles: [String]

  private var segmenter: Segmenter { Segmenter(dataManager: dataManager) }

  /// This test verifies that a segmenter created by the data manager provides
  /// the expected boundary rule.
  func segmenterTestSameAsInternal() {
    let segmenter = self.segmenter
    var mismatches: [String] = []
    for rid in 0..<lsize {
      for lid in 0..<rsize where isBoundary(rid, lid) != segmenter.isBoundary(UInt16(rid), UInt16(lid)) {
        if mismatches.count < 10 { mismatches.append("\(rid) \(lid)") }
      }
    }
    #expect(mismatches.isEmpty, "\(mismatches)")
  }

  func segmenterTestLNodeTest() {
    let segmenter = self.segmenter
    // lnode is BOS
    let lnode = Node()
    let rnode = Node()
    lnode.nodeType = .bosNode
    rnode.nodeType = .norNode
    var ok = true
    for rid in 0..<lsize {
      for lid in 0..<rsize {
        lnode.rid = UInt16(rid)
        lnode.lid = UInt16(lid)
        ok = ok && segmenter.isBoundary(lnode, rnode, false) && segmenter.isBoundary(lnode, rnode, true)
      }
    }
    #expect(ok)
  }

  func segmenterTestRNodeTest() {
    let segmenter = self.segmenter
    // rnode is EOS
    let lnode = Node()
    let rnode = Node()
    lnode.nodeType = .norNode
    rnode.nodeType = .eosNode
    var ok = true
    for rid in 0..<lsize {
      for lid in 0..<rsize {
        lnode.rid = UInt16(rid)
        lnode.lid = UInt16(lid)
        ok = ok && segmenter.isBoundary(lnode, rnode, false) && segmenter.isBoundary(lnode, rnode, true)
      }
    }
    #expect(ok)
  }

  func segmenterTestNodeTest() {
    let segmenter = self.segmenter
    let lnode = Node()
    let rnode = Node()
    lnode.nodeType = .norNode
    rnode.nodeType = .norNode
    var ok = true
    for rid in 0..<lsize {
      for lid in 0..<rsize {
        lnode.rid = UInt16(rid)
        rnode.lid = UInt16(lid)
        ok =
          ok
          && segmenter.isBoundary(UInt16(rid), UInt16(lid)) == segmenter.isBoundary(lnode, rnode, false)
          && !segmenter.isBoundary(lnode, rnode, true)
      }
    }
    #expect(ok)
  }

  func segmenterTestParticleTest() {
    let segmenter = self.segmenter
    let posMatcher = PosMatcher(dataManager.getPosMatcherData())
    let lnode = Node()
    let rnode = Node()
    lnode.initialize()
    rnode.initialize()
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

  func connectorTestRandomValueCheck() throws {
    let connector = try Connector.create(dataManager.getConnectorData())
    #expect(connector.getResolution() == expectedResolution)
    var gen = Random(seed: 0)
    let reader = ConnectionFileReader(connectionTxtFile)
    while !reader.done {
      defer { reader.next() }
      // Randomly sample test entries because connection data have several
      // millions of entries.
      if !(Double.random(in: 0..<1, using: &gen) < 1.0 / 100000) {
        continue
      }
      let cost = Int(reader.cost)
      #expect(cost >= 0)
      let actualCost = connector.getTransitionCost(
        UInt16(reader.ridOfLeftNode), UInt16(reader.lidOfRightNode))
      if cost == Int(Connector.kInvalidCost) {
        #expect(actualCost == cost)
      } else {
        #expect(
          cost == actualCost || (cost - cost % expectedResolution) == actualCost,
          "cost: \(cost), actual_cost: \(actualCost)")
      }
    }
  }

  func suggestionFilterTestIsBadSuggestion() throws {
    let kErrorRatio = 0.0001

    // Load embedded suggestion filter (bloom filter)
    let suggestionFilter = SuggestionFilter.createOrDie(dataManager.getSuggestionFilterData())

    // Load the original suggestion filter from file.
    var suggestionFilterSet = Set<String>()
    for file in suggestionFilterFiles {
      for raw in try String(contentsOfFile: file, encoding: .utf8).split(separator: "\n") {
        var line = String(raw)
        if line.isEmpty || line.hasPrefix("#") { continue }
        Util.lowerString(&line)
        suggestionFilterSet.insert(line)
      }
    }

    var falsePositives = 0
    var numWords = 0
    var falseNegatives: [String] = []
    for file in dictionaryFiles {
      for line in try String(contentsOfFile: file, encoding: .utf8).split(separator: "\n") {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: true)
        try #require(fields.count >= 5)
        var value = String(fields[4])
        Util.lowerString(&value)

        let trueResult = suggestionFilterSet.contains(value)
        let bloomFilterResult = suggestionFilter.isBadSuggestion(value)

        // never emits false negative
        if trueResult {
          if !bloomFilterResult { falseNegatives.append(value) }
        } else if bloomFilterResult {
          falsePositives += 1
        }
        numWords += 1
      }
    }
    #expect(falseNegatives.isEmpty, "\(falseNegatives.prefix(10))")
    #expect(numWords > 0)
    let errorRatio = Float(1.0 * Double(falsePositives) / Double(numWords))
    #expect(Double(errorRatio) < kErrorRatio, "False positive ratio is \(errorRatio)")
  }

  func counterSuffixTestValidateTest() throws {
    let suffixArray = try #require(SerializedStringArray(dataManager.getCounterSuffixSortedArray()))

    // Check if the array is sorted in ascending order.
    var prevSuffix: [UInt8] = []  // The smallest string.
    for i in 0..<suffixArray.size {
      let suffix = suffixArray.utf8(at: i)
      #expect(!suffix.lexicographicallyPrecedes(prevSuffix), "\(suffixArray[i])")
      prevSuffix = suffix
    }
  }

  func posIdMapTestLoad() {
    #expect(!dataManager.getPosIdMapData().isEmpty)
  }

  func runAllTests() throws {
    try connectorTestRandomValueCheck()
    segmenterTestLNodeTest()
    segmenterTestNodeTest()
    segmenterTestParticleTest()
    segmenterTestRNodeTest()
    segmenterTestSameAsInternal()
    try suggestionFilterTestIsBadSuggestion()
    try counterSuffixTestValidateTest()
    posIdMapTestLoad()
  }
}
