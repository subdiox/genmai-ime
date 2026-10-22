// Section-by-section comparison of two data set images (format: see
// mozc/src/data_manager/dataset.proto).  Not a Mozc port; a debugging aid for
// checking that genmai-datagen reproduces the Bazel outputs byte for byte.

import Foundation
import GenmaiBase
import GenmaiProtocol
import SwiftProtobuf

public enum DataSetDiff {
  public struct Section: Sendable, Equatable {
    public let name: String
    public let offset: Int
    public let size: Int
  }

  /// Parses the footer and metadata; returns the sections in file order.
  public static func sections(_ image: [UInt8]) throws -> [Section] {
    let footer = 36
    guard image.count >= footer else { throw DataGenError.invalidInput("data set too small") }
    func u64(_ at: Int) -> Int {
      var v: UInt64 = 0
      for k in 0..<8 { v = (v << 8) | UInt64(image[at + k]) }  // Util::SerializeUint64 is big-endian.
      return Int(v)
    }
    let metadataSize = u64(image.count - footer)
    let metadataStart = image.count - footer - metadataSize
    guard metadataSize > 0, metadataStart >= 0 else { throw DataGenError.invalidInput("broken metadata size") }
    let metadata = try Genmai_DataSetMetadata(serializedBytes: Array(image[metadataStart..<(image.count - footer)]))
    return metadata.entries.map { Section(name: $0.name, offset: Int($0.offset), size: Int($0.size)) }
  }

  /// A readable report of the differences between `actual` and `expected`
  /// (nil if identical).
  public static func report(actual: [UInt8], expected: [UInt8]) -> String? {
    if actual == expected { return nil }
    var lines: [String] = []
    lines.append("size: actual \(actual.count), expected \(expected.count)")
    let a: [Section]
    let e: [Section]
    do {
      a = try sections(actual)
      e = try sections(expected)
    } catch {
      lines.append("cannot parse: \(error)")
      return lines.joined(separator: "\n")
    }
    if a.map(\.name) != e.map(\.name) {
      lines.append("section names differ:\n  actual:   \(a.map(\.name))\n  expected: \(e.map(\.name))")
    }
    let firstA = a.first?.offset ?? 0
    let firstE = e.first?.offset ?? 0
    if firstA > 0, firstE > 0, actual[0..<min(firstA, actual.count)] != expected[0..<min(firstE, expected.count)] {
      lines.append("magic / header differs")
    }
    let byName = Dictionary(e.map { ($0.name, $0) }, uniquingKeysWith: { x, _ in x })
    var differing = 0
    for s in a {
      guard let t = byName[s.name] else {
        lines.append("  \(s.name): only in actual")
        continue
      }
      let x = actual[s.offset..<(s.offset + s.size)]
      let y = expected[t.offset..<(t.offset + t.size)]
      if x.elementsEqual(y) {
        if s.offset != t.offset { lines.append("  \(s.name): same bytes, offset \(s.offset) vs \(t.offset)") }
        continue
      }
      differing += 1
      let firstDiff = zip(x, y).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(x.count, y.count)
      lines.append(
        "  \(s.name): DIFFERS (size \(s.size) vs \(t.size), first difference at section offset \(firstDiff))"
          + hexContext(Array(x), Array(y), firstDiff))
    }
    for t in e where !a.contains(where: { $0.name == t.name }) {
      lines.append("  \(t.name): only in expected")
    }
    if differing == 0 { lines.append("all sections identical; metadata / footer differs") }
    return lines.joined(separator: "\n")
  }

  static func hexContext(_ x: [UInt8], _ y: [UInt8], _ at: Int) -> String {
    func hex(_ a: [UInt8]) -> String {
      let lo = max(0, at - 8)
      let hi = min(a.count, at + 24)
      guard lo < hi else { return "" }
      return a[lo..<hi].map { String(format: "%02x", $0) }.joined(separator: " ")
    }
    return "\n      actual:   \(hex(x))\n      expected: \(hex(y))"
  }

  /// Compares one section's bytes against a reference file (e.g. a Bazel
  /// intermediate under bazel-bin/data_manager/oss/).
  public static func compareBytes(_ actual: [UInt8], _ expected: [UInt8]) -> String? {
    if actual == expected { return nil }
    let firstDiff =
      zip(actual, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset
      ?? min(actual.count, expected.count)
    return "size \(actual.count) vs \(expected.count), first difference at \(firstDiff)"
      + hexContext(actual, expected, firstDiff)
  }
}
