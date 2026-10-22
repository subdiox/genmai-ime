// Port of mozc/src/data_manager/gen_connection_data.py (3.35.6354).
//
// Generator for connection data (the --binary_output_file output; the C++
// header output is not needed).

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenConnectionData {
  static let invalidCost = 30000
  static let invalid1ByteCost = 255
  static let resolutionFor1Byte = 64
  static let fileMagic: [UInt8] = [0xAB, 0xCD]
  /// Python None in the compressed matrix.
  static let none = Int32.min

  /// Non-blank, non-comment lines (code_generator_util.SkipLineComment over
  /// codecs `splitlines`) of an ASCII file, as byte ranges with surrounding
  /// whitespace removed (the callers apply `int(x.rstrip())`, and `int()`
  /// ignores leading whitespace).
  static func contentLines(_ bytes: [UInt8]) -> [Range<Int>] {
    var result: [Range<Int>] = []
    var start = 0
    func isSpace(_ b: UInt8) -> Bool { b == 32 || (b >= 9 && b <= 13) || (b >= 0x1C && b <= 0x1F) }
    func flush(_ end: Int) {
      var a = start
      var b = end
      while a < b && isSpace(bytes[a]) { a += 1 }
      while b > a && isSpace(bytes[b - 1]) { b -= 1 }
      if a < b && bytes[a] != UInt8(ascii: "#") { result.append(a..<b) }
    }
    var i = 0
    while i < bytes.count {
      let c = bytes[i]
      // str.splitlines() boundaries within ASCII ("\r\n" is one boundary).
      if c == 10 || c == 13 || c == 11 || c == 12 || (c >= 0x1C && c <= 0x1E) {
        flush(i)
        if c == 13 && i + 1 < bytes.count && bytes[i + 1] == 10 { i += 1 }
        start = i + 1
      }
      i += 1
    }
    flush(bytes.count)
    return result
  }

  static func parseInt(_ bytes: [UInt8], _ r: Range<Int>) throws -> Int {
    var i = r.lowerBound
    var neg = false
    if i < r.upperBound && (bytes[i] == UInt8(ascii: "-") || bytes[i] == UInt8(ascii: "+")) {
      neg = bytes[i] == UInt8(ascii: "-")
      i += 1
    }
    guard i < r.upperBound else { throw DataGenError.invalidInput("connection: bad integer") }
    var v = 0
    while i < r.upperBound {
      let d = Int(bytes[i]) - 48
      guard d >= 0 && d <= 9 else {
        throw DataGenError.invalidInput("connection: bad integer \(String(decoding: bytes[r], as: UTF8.self))")
      }
      v = v * 10 + d
      i += 1
    }
    return neg ? -v : v
  }

  static func getPosSize(_ filepath: String) throws -> Int {
    // The pos-size should be equal to the number of lines.
    PosCodeGenUtil.skipLineComment(try Py.readLines(filepath, mode: .splitlines)).count
  }

  /// Returns the square matrix, row-major (matrix[rid * size + lid]).
  static func parseConnectionFile(_ textConnectionFile: String, _ posSize: Int, _ specialPosSize: Int) throws
    -> (matrix: [Int32], size: Int)
  {
    let matSize = posSize + specialPosSize
    var matrix = [Int32](repeating: 0, count: matSize * matSize)
    let bytes = try FileUtil.getContentBytes(textConnectionFile)
    let lines = contentLines(bytes)
    guard let first = lines.first else { throw DataGenError.invalidInput("connection: empty file") }
    // The first line contains the matrix column/row size.
    let size = try parseInt(bytes, first)
    guard size == posSize else { throw DataGenError.invalidInput("\(size) != \(posSize)") }
    for (arrayIndex, r) in lines.dropFirst().enumerated() {
      var cost = try parseInt(bytes, r)
      let rid = arrayIndex / posSize
      let lid = arrayIndex % posSize
      if rid == 0 && lid == 0 {
        cost = 0
      }
      matrix[rid * matSize + lid] = Int32(cost)
    }

    // Fill INVALID_COST in matrix elements for special POS.
    for rid in posSize..<matSize {
      for lid in 1..<matSize {  // Skip EOS
        matrix[rid * matSize + lid] = Int32(invalidCost)
      }
    }
    for lid in posSize..<matSize {
      for rid in 1..<matSize {  // Skip BOS
        matrix[rid * matSize + lid] = Int32(invalidCost)
      }
    }
    return (matrix, matSize)
  }

  /// Create a list of modes of each row.
  static func createModeValueList(_ matrix: [Int32], _ size: Int) throws -> [Int32] {
    var result: [Int32] = []
    result.reserveCapacity(size)
    for rid in 0..<size {
      // max(m.items(), key=count) over a dict: the first cost (in order of
      // first appearance) with the maximum count.
      var counts: [Int32: Int] = [:]
      var order: [Int32] = []
      for lid in 0..<size {
        let cost = matrix[rid * size + lid]
        if cost == Int32(invalidCost) {
          // Heuristically, we do not compress INVALID_COST.
          continue
        }
        if let c = counts[cost] {
          counts[cost] = c + 1
        } else {
          counts[cost] = 1
          order.append(cost)
        }
      }
      guard var best = order.first else { throw DataGenError.invalidInput("connection: empty row") }
      var bestCount = counts[best, default: 0]
      for cost in order.dropFirst() where counts[cost, default: 0] > bestCount {
        best = cost
        bestCount = counts[cost, default: 0]
      }
      result.append(best)
    }
    return result
  }

  static func compressMatrixByModeValue(_ matrix: inout [Int32], _ size: Int, _ modeValueList: [Int32]) {
    // To compress the data size, we hold mode values for each row in a
    // separate list, and fill None into the matrix if it equals to the
    // corresponding mode value.
    for rid in 0..<size {
      let mode = modeValueList[rid]
      for lid in 0..<size where matrix[rid * size + lid] == mode {
        matrix[rid * size + lid] = none
      }
    }
  }

  static func outputBitList(_ bitList: [Bool], _ stream: inout [UInt8]) {
    // Make sure that the bit list is aligned to the byte boundary.
    precondition(bitList.count % 8 == 0)
    var i = 0
    while i < bitList.count {
      var byte: UInt8 = 0
      for bitIndex in 0..<8 where bitList[i + bitIndex] {
        // Fill in LSB to MSB order.
        byte |= 1 << UInt8(bitIndex)
      }
      stream.append(byte)
      i += 8
    }
  }

  /// See gen_connection_data.py for the file format: header, mode values,
  /// then per row a two-level succinct bit vector (chunk bits, compact bits)
  /// followed by the non-mode values.
  static func buildBinaryData(_ matrix: [Int32], _ size: Int, _ modeValueList: [Int32], _ use1ByteCost: Bool) throws
    -> [UInt8]
  {
    let resolution = use1ByteCost ? resolutionFor1Byte : 1
    var stream: [UInt8] = []
    func put16(_ v: Int) {
      stream.append(UInt8(v & 0xFF))
      stream.append(UInt8((v >> 8) & 0xFF))
    }

    // Output header.
    stream.append(contentsOf: fileMagic)
    precondition(size >= 0 && size <= 65535)
    put16(resolution)
    put16(size)
    put16(size)

    // Output mode value list.
    for value in modeValueList {
      guard value >= 0 && value <= 65535 else { throw DataGenError.invalidInput("bad mode value \(value)") }
      put16(Int(value))
    }

    // 4 bytes alignment.
    if modeValueList.count % 2 != 0 {
      stream.append(contentsOf: [0, 0])
    }

    // Process each row:
    var chunkBits: [Bool] = []
    var compactBits: [Bool] = []
    var values: [Int] = []
    for rid in 0..<size {
      chunkBits.removeAll(keepingCapacity: true)
      compactBits.removeAll(keepingCapacity: true)
      values.removeAll(keepingCapacity: true)
      let row = rid * size
      var index = 0
      while index < size {
        let end = min(index + 8, size)
        var allNone = true
        for k in index..<end where matrix[row + k] != none {
          allNone = false
          break
        }
        if allNone {
          // All bits are 0, so output 0-chunk bit.
          chunkBits.append(false)
          index = end
          continue
        }
        chunkBits.append(true)
        for k in index..<end {
          let c = matrix[row + k]
          if c == none {
            compactBits.append(false)
          } else {
            compactBits.append(true)
            var cost = Int(c)
            if use1ByteCost {
              if cost == invalidCost {
                cost = invalid1ByteCost
              } else {
                // Python floor division.
                cost = Int((Double(cost) / Double(resolution)).rounded(.down))
                precondition(cost != invalid1ByteCost)
              }
            }
            values.append(cost)
          }
        }
        index = end
      }

      // 4 bytes alignment.
      while chunkBits.count % 32 != 0 { chunkBits.append(false) }
      while compactBits.count % 32 != 0 { compactBits.append(false) }
      let valuesSize: Int
      if use1ByteCost {
        while values.count % 4 != 0 { values.append(0) }
        valuesSize = values.count
      } else {
        while values.count % 2 != 0 { values.append(0) }
        valuesSize = values.count * 2
      }

      // Output the bits for a row.
      put16(compactBits.count / 8)
      put16(valuesSize)
      outputBitList(chunkBits, &stream)
      outputBitList(compactBits, &stream)
      if use1ByteCost {
        for value in values {
          guard value >= 0 && value <= 255 else { throw DataGenError.invalidInput("bad cost \(value)") }
          stream.append(UInt8(value))
        }
      } else {
        for value in values {
          guard value >= 0 && value <= 65535 else { throw DataGenError.invalidInput("bad cost \(value)") }
          put16(value)
        }
      }
    }
    return stream
  }

  public static func generate(
    textConnectionFile: String, idFile: String, specialPosFile: String, use1ByteCost: Bool
  ) throws -> [UInt8] {
    let posSize = try getPosSize(idFile)
    let specialPosSize = try getPosSize(specialPosFile)
    var (matrix, size) = try parseConnectionFile(textConnectionFile, posSize, specialPosSize)
    let modeValueList = try createModeValueList(matrix, size)
    compressMatrixByModeValue(&matrix, size, modeValueList)
    return try buildBinaryData(matrix, size, modeValueList, use1ByteCost)
  }

  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    let s = ctx.sources
    return [
      "conn": try generate(
        textConnectionFile: s.connectionSingleColumn, idFile: s.idDef, specialPosFile: s.specialPos,
        use1ByteCost: s.useOneByteCost)
    ]
  }
}
