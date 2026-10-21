// Port of mozc/src/converter/gen_boundary_data.py (3.35.6354).
//
// Bounday data binary image is an array of uint16_t whose length is 2N, where
// N is the number of POS IDs including special POS: (prefix penalty, suffix
// penalty) for each POS ID.  See converter/segmenter.cc for how it's used.

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenBoundaryData {
  static func patternToRegexp(_ pattern: String) -> String {
    var regexp = "^" + pattern.replacingOccurrences(of: "*", with: "[^,]+")
    if !regexp.hasSuffix(",") {
      regexp += "(?:,|$)"
    }
    return regexp
  }

  static func loadPatterns(_ lines: [String]) throws -> (prefix: [(PyRegex, Int)], suffix: [(PyRegex, Int)]) {
    var prefix: [(PyRegex, Int)] = []
    var suffix: [(PyRegex, Int)] = []
    for line in lines {
      if line.unicodeScalars.count <= 1 || line.hasPrefix("#") { continue }
      let fields = Py.split(line)
      let label = fields[0]
      let feature = fields[1]
      guard let cost = Py.int(fields[2]), cost >= 0, cost <= 0xFFFF else {
        throw DataGenError.invalidInput("boundary.def: bad cost: \(line)")
      }
      if label == "PREFIX" {
        prefix.append((try PyRegex(patternToRegexp(feature)), cost))
      } else if label == "SUFFIX" {
        suffix.append((try PyRegex(patternToRegexp(feature)), cost))
      } else {
        throw DataGenError.invalidInput("format error \(line)")
      }
    }
    return (prefix, suffix)
  }

  static func getCost(_ patterns: [(PyRegex, Int)], _ feature: String) -> Int {
    for (pat, cost) in patterns where pat.match(feature) {
      return cost
    }
    return 0
  }

  static func loadFeatures(_ lines: [String]) -> [String] {
    lines.map { Py.split($0)[1] }
  }

  static func countSpecialPos(_ lines: [String]) -> Int {
    var count = 0
    for raw in lines {
      let line = Py.rstrip(raw)
      if line.isEmpty || line.hasPrefix("#") { continue }
      count += 1
    }
    return count
  }

  /// Generates boundary data binary image.
  public static func generateBoundaryData(
    boundaryDefLines: [String], idDefLines: [String], specialPosLines: [String]
  ) throws -> [UInt8] {
    let (prefix, suffix) = try loadPatterns(boundaryDefLines)
    let features = loadFeatures(idDefLines)
    let numSpecialPos = countSpecialPos(specialPosLines)
    var out: [UInt8] = []
    func put(_ v: Int) {
      out.append(UInt8(v & 0xFF))
      out.append(UInt8((v >> 8) & 0xFF))
    }
    for feature in features {
      put(getCost(prefix, feature))
      put(getCost(suffix, feature))
    }
    for _ in 0..<numSpecialPos {
      put(0)
      put(0)
    }
    return out
  }

  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    let s = ctx.sources
    return [
      "bdry": try generateBoundaryData(
        boundaryDefLines: try Py.readLines(s.boundaryDef), idDefLines: try Py.readLines(s.idDef),
        specialPosLines: try Py.readLines(s.specialPos))
    ]
  }
}
