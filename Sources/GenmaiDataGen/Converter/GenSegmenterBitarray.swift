// Port of mozc/src/converter/gen_segmenter_bitarray.{h,cc} (3.35.6354).
//
// Generates kCompressedLSize, kCompressedRSize, the compressed LID / RID
// tables and the segmenter bit array; returns them as the contents of the
// four output files instead of writing them.

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import SwiftProtobuf

public enum SegmenterBitarrayGenerator {
  final class StateTable {
    private var idarray: [[UInt8]]
    private var compressedTable: [UInt16] = []
    private(set) var compressedSize = 0

    init(_ size: Int) {
      idarray = [[UInt8]](repeating: [], count: size)
    }

    /// |str| is an 1-dimensional row (or column) represented in byte array.
    func add(_ id: Int, _ str: [UInt8]) {
      precondition(id < idarray.count)
      idarray[id] = str
    }

    func build() {
      compressedTable = [UInt16](repeating: 0, count: idarray.count)
      var id: UInt16 = 0
      var dup: [[UInt8]: UInt16] = [:]
      for i in 0..<idarray.count {
        if let v = dup[idarray[i]] {
          compressedTable[i] = v
        } else {
          compressedTable[i] = id
          dup[idarray[i]] = id
          id += 1
        }
      }
      compressedSize = dup.count
      precondition(compressedSize < idarray.count)
    }

    func id(_ id: Int) -> Int { Int(compressedTable[id]) }

    func output() -> [UInt8] {
      var out: [UInt8] = []
      out.reserveCapacity(compressedTable.count * 2)
      for v in compressedTable {
        out.append(UInt8(v & 0xFF))
        out.append(UInt8(v >> 8))
      }
      return out
    }
  }

  /// Returns (size_info, ltable, rtable, bitarray).
  public static func generateBitarray(
    _ lsize: Int, _ rsize: Int, _ isBoundary: (Int, Int) -> Bool
  ) throws -> (sizeInfo: [UInt8], ltable: [UInt8], rtable: [UInt8], bitarray: [UInt8]) {
    // Load the original matrix into an array
    var array = [UInt8](repeating: 0, count: (lsize + 1) * (rsize + 1))
    for rid in 0...lsize {
      for lid in 0...rsize {
        let index = rid + lsize * lid
        precondition(index < array.count)
        if rid == lsize || lid == rsize {
          array[index] = 1
          continue
        }
        array[index] = isBoundary(rid, lid) ? 1 : 0
      }
    }

    // Reduce left states (remove duplicate rows)
    let ltable = StateTable(lsize + 1)
    for rid in 0...lsize {
      var buf: [UInt8] = []
      buf.reserveCapacity(rsize + 1)
      for lid in 0...rsize {
        buf.append(array[rid + lsize * lid])
      }
      ltable.add(rid, buf)
    }

    // Reduce right states (remove duplicate columns)
    let rtable = StateTable(rsize + 1)
    for lid in 0...rsize {
      var buf: [UInt8] = []
      buf.reserveCapacity(lsize + 1)
      for rid in 0...lsize {
        buf.append(array[rid + lsize * lid])
      }
      rtable.add(lid, buf)
    }

    // make lookup table
    rtable.build()
    ltable.build()

    let compressedLSize = ltable.compressedSize
    let compressedRSize = rtable.compressedSize
    precondition(compressedLSize > 0 && compressedRSize > 0)

    // make bitarray
    var barray = BitArray(compressedLSize * compressedRSize)
    for rid in 0...lsize {
      for lid in 0...rsize {
        let index = rid + lsize * lid
        let cindex = ltable.id(rid) + compressedLSize * rtable.id(lid)
        if array[index] > 0 {
          barray.set(cindex)
        } else {
          barray.clear(cindex)
        }
      }
    }

    // verify the table
    for rid in 0...lsize {
      for lid in 0...rsize {
        let index = rid + lsize * lid
        let cindex = ltable.id(rid) + compressedLSize * rtable.id(lid)
        precondition(barray.get(cindex) == (array[index] != 0))
      }
    }

    var pb = Genmai_Converter_SegmenterDataSizeInfo()
    pb.compressedLsize = numericCast(compressedLSize)
    pb.compressedRsize = numericCast(compressedRSize)
    let sizeInfo: [UInt8] = try pb.serializedBytes()
    return (sizeInfo, ltable.output(), rtable.output(), barray.bytes)
  }
}
