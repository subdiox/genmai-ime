// Port of mozc/src/converter/connector_test.cc (3.35.6354), plus
// DataManagerTestBase::ConnectorTest_RandomValueCheck.
//
// The C++ test reads data_manager/testing/connection.data, which is generated
// by Bazel; the same matrix is the connector data of mock_genmai.data.

import Foundation
import GenmaiBase
import Testing

@testable import GenmaiCore

@Suite struct ConnectorTests {
  private struct ConnectionDataEntry {
    var rid: UInt16
    var lid: UInt16
    var cost: Int
  }

  @Test(.enabled(if: ConverterCoreTestSupport.hasMockData, ConverterCoreTestSupport.mockDataMissing))
  func compareWithRawData() throws {
    let connector = try Connector.create(try ConverterCoreTestSupport.mockDataManager().getConnectorData())
    #expect(connector.getResolution() == 1)

    let path = ConverterCoreTestSupport.sourcePath("data", "test", "dictionary", "connection_single_column.txt")
    var data: [ConnectionDataEntry] = []
    let reader = ConnectionFileReader(path)
    while !reader.done {
      data.append(
        ConnectionDataEntry(
          rid: UInt16(reader.ridOfLeftNode), lid: UInt16(reader.lidOfRightNode), cost: Int(reader.cost)))
      reader.next()
    }

    // All entries in order, then a random sample (the C++ test shuffles the
    // whole matrix three times; that is too slow for a debug build).
    var mismatches = 0
    for entry in data {
      if connector.getTransitionCost(entry.rid, entry.lid) != entry.cost { mismatches += 1 }
      // Cache hit case.
      if connector.getTransitionCost(entry.rid, entry.lid) != entry.cost { mismatches += 1 }
    }
    var rng = SystemRandomNumberGenerator()
    for _ in 0..<200_000 {
      let entry = data[Int.random(in: 0..<data.count, using: &rng)]
      if connector.getTransitionCost(entry.rid, entry.lid) != entry.cost { mismatches += 1 }
      if connector.getTransitionCost(entry.rid, entry.lid) != entry.cost { mismatches += 1 }
    }
    #expect(mismatches == 0)
  }

  @Test(.enabled(if: ConverterCoreTestSupport.hasMockData, ConverterCoreTestSupport.mockDataMissing))
  func brokenData() throws {
    let original = Array(try ConverterCoreTestSupport.mockDataManager().getConnectorData())

    // Invalid magic number.
    do {
      var data = original
      data[0] = 0
      data[1] = 0
      #expect(throws: (any Error).self) { try Connector.create(copying: data) }
    }
    // Not square.
    do {
      var data = original
      data[4] = 100
      data[5] = 0
      data[6] = 200
      data[7] = 0
      #expect(throws: (any Error).self) { try Connector.create(copying: data) }
    }
    // Incomplete data.
    for divider in [2, 3, 5, 7, 10, 100, 1000] {
      let size = original.count / divider
      #expect(throws: (any Error).self) { try Connector.create(copying: original[0..<size]) }
    }
    // Not aligned at 32-bit boundary.
    do {
      let buffer = DataView(copying: [0, 0] + original)
      let view = buffer.slice(2, original.count)
      #expect(throws: (any Error).self) { try Connector.create(view) }
    }
  }

  @Test func getTransitionCostOneByteCost() throws {
    // A 2x2 connection matrix with 1-byte costs (resolution 64):
    //   rid 0: lid 0 is the mode value 100, lid 1 is the invalid cost.
    //   rid 1: lid 0 is 10 * 64 = 640, lid 1 is the mode value 200.
    let kData: [UInt8] = [
      0xAB, 0xCD,  // magic
      0x40, 0x00,  // resolution = 64
      0x02, 0x00, 0x02, 0x00,  // rsize = 2, lsize = 2
      0x64, 0x00, 0xC8, 0x00,  // mode values: 100, 200
      // rid 0
      0x04, 0x00, 0x04, 0x00,  // compact_bits_size = 4, values_size = 4
      0x01, 0x00, 0x00, 0x00,  // chunk bits: chunk 0 has a value
      0x02, 0x00, 0x00, 0x00,  // compact bits: lid 1 has a value
      0xFF, 0x00, 0x00, 0x00,  // values: 255 = invalid cost
      // rid 1
      0x04, 0x00, 0x04, 0x00,  // compact_bits_size = 4, values_size = 4
      0x01, 0x00, 0x00, 0x00,  // chunk bits: chunk 0 has a value
      0x01, 0x00, 0x00, 0x00,  // compact bits: lid 0 has a value
      0x0A, 0x00, 0x00, 0x00,  // values: 10, i.e. 640 with resolution 64
    ]
    let connector = try Connector.create(copying: kData)
    #expect(connector.getResolution() == 64)
    #expect(connector.getTransitionCost(0, 1) == Int(Connector.kInvalidCost))
    #expect(connector.getTransitionCost(1, 0) == 640)
    #expect(connector.getTransitionCost(1, 1) == 200)
  }

  @Test func getTransitionCostTwoByteCost() throws {
    // The same 2x2 connection matrix as above with 2-byte costs (resolution 1).
    let kData: [UInt8] = [
      0xAB, 0xCD,  // magic
      0x01, 0x00,  // resolution = 1
      0x02, 0x00, 0x02, 0x00,  // rsize = 2, lsize = 2
      0x64, 0x00, 0xC8, 0x00,  // mode values: 100, 200
      // rid 0
      0x04, 0x00, 0x04, 0x00,  // compact_bits_size = 4, values_size = 4
      0x01, 0x00, 0x00, 0x00,  // chunk bits: chunk 0 has a value
      0x02, 0x00, 0x00, 0x00,  // compact bits: lid 1 has a value
      0x30, 0x75, 0x00, 0x00,  // values: 30000 = invalid cost
      // rid 1
      0x04, 0x00, 0x04, 0x00,  // compact_bits_size = 4, values_size = 4
      0x01, 0x00, 0x00, 0x00,  // chunk bits: chunk 0 has a value
      0x01, 0x00, 0x00, 0x00,  // compact bits: lid 0 has a value
      0x80, 0x02, 0x00, 0x00,  // values: 640
    ]
    let connector = try Connector.create(copying: kData)
    #expect(connector.getResolution() == 1)
    #expect(connector.getTransitionCost(0, 1) == Int(Connector.kInvalidCost))
    #expect(connector.getTransitionCost(1, 0) == 640)
    #expect(connector.getTransitionCost(1, 1) == 200)
    // Swift-only: an untouched cache bucket is a hit for (0, 0) with cost 0,
    // exactly like the C++ cache (zero-initialized atomics).
    #expect(connector.getTransitionCost(0, 0) == 0)
  }

  /// DataManagerTestBase::ConnectorTest_RandomValueCheck for the OSS data set.
  @Test(.enabled(if: OssDataManagerAvailability.available, "genmai.data is missing; run Tools/build_oracle.sh"))
  func ossRandomValueCheck() throws {
    let dm = try OssDataManager.create()
    let connector = try Connector.create(dm.getConnectorData())
    let path = ConverterCoreTestSupport.sourcePath(
      "data", "dictionary_oss", "connection_single_column.txt")
    let reader = ConnectionFileReader(path)
    let resolution = connector.getResolution()
    var count = 0
    var mismatches = 0
    var rng = SystemRandomNumberGenerator()
    while !reader.done {
      // Randomly sample test entries because connection data have several
      // millions of entries.
      if UInt32.random(in: 0..<2000, using: &rng) == 0 {
        let cost = Int(reader.cost)
        let actual = connector.getTransitionCost(UInt16(reader.ridOfLeftNode), UInt16(reader.lidOfRightNode))
        if cost == Int(Connector.kInvalidCost) {
          if actual != cost { mismatches += 1 }
        } else if !(cost == actual || cost - cost % resolution == actual) {
          mismatches += 1
        }
        count += 1
      }
      reader.next()
    }
    #expect(count > 0)
    #expect(mismatches == 0)
  }
}

enum OssDataManagerAvailability {
  static var available: Bool {
    FileManager.default.fileExists(atPath: OssDataManager.defaultDataPath)
      && FileManager.default.fileExists(
        atPath: upstreamSourceFile(["data", "dictionary_oss", "connection_single_column.txt"]))
  }
}
