// Port of mozc/src/rewriter/gen_emoticon_rewriter_data.cc (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenEmoticonRewriterData {
  typealias KeyList = [String]

  static func lookupCount(_ keyCount: [BStr: Int], _ key: String) -> Int {
    keyCount[BStr(key)] ?? 0
  }

  static func getDescription(_ keyList: KeyList, _ keyCount: [BStr: Int]) -> String {
    if keyList.count == 1 {
      return keyList[0]
    }
    // std::sort with a strict weak order; only equal strings tie, so the
    // (unstable) result is determined.
    let sorted = keyList.sorted { x, y in
      let xCount = lookupCount(keyCount, x)
      let yCount = lookupCount(keyCount, y)
      if xCount == yCount {
        return BStr(x) < BStr(y)
      }
      return xCount < yCount
    }
    guard let first = sorted.first, let last = sorted.last else { return "" }
    return "\(last) \(first)"
  }

  static func readEmoticonTsv(_ path: String) throws -> [String: SerializedDictionary.TokenList] {
    let ifs = InputFileStream(path)
    guard !ifs.fail else { throw DataGenError.invalidInput("cannot open \(path)") }
    _ = ifs.getline()  // Skip header

    var data: [(String, KeyList)] = []
    var keyCount: [BStr: Int] = [:]
    while let line = ifs.getline() {
      let fieldList = line.utf8.split(separator: UInt8(ascii: "\t"), omittingEmptySubsequences: true).map {
        String(decoding: $0, as: UTF8.self)
      }
      guard fieldList.count >= 2 else { throw DataGenError.invalidInput("Format error: \(line)") }
      // (The C++ computes a full-width-space-replaced copy but does not use it.)
      let keyList = fieldList[1].utf8.split(separator: UInt8(ascii: " "), omittingEmptySubsequences: true).map {
        String(decoding: $0, as: UTF8.self)
      }
      for key in keyList {
        keyCount[BStr(key), default: 0] += 1
      }
      data.append((fieldList[0], keyList))
    }

    var inputData: [String: SerializedDictionary.TokenList] = [:]
    // Swift Dictionary<String, _> merges canonically equivalent keys, which
    // std::map keeps apart; make sure that does not happen.
    var seenKeys: [String: String] = [:]
    var cost: Int16 = 10
    for (value, keyList) in data {
      let description = getDescription(keyList, keyCount)
      for key in keyList {
        if let k = seenKeys[key], !k.utf8.elementsEqual(key.utf8) {
          throw DataGenError.invalidInput("canonically equivalent keys: \(k) / \(key)")
        }
        seenKeys[key] = key
        inputData[key, default: []].append(
          SerializedDictionary.CompilerToken(value: value, description: description, lid: 0, rid: 0, cost: cost))
        cost &+= 10
      }
    }
    return inputData
  }

  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    let (tokenArray, stringArray) = SerializedDictionary.compile(try readEmoticonTsv(ctx.sources.emoticon))
    return ["emoticon_token": tokenArray, "emoticon_string": stringArray]
  }
}
