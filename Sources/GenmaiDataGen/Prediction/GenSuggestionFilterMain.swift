// Port of mozc/src/prediction/gen_suggestion_filter_main.cc (3.35.6354).
// Only the raw bloom filter output (--header=false) is ported.

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiStorage

public enum GenSuggestionFilterMain {
  /// Data set sections produced by this generator (keys: dataset_writer_main names).
  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    ["sugg": try generate(ctx.sources.suggestionFilter, safeListFiles: ctx.sources.suggestionFilterSafeDefs)]
  }

  static func lowered(_ line: String) -> String {
    var s = line
    Util.lowerString(&s)
    return s
  }

  static func readWords(_ name: String) throws -> [String] {
    var words: [String] = []
    for line in CodeGenUtil.getlines(try FileUtil.getContentBytes(name)) {
      if line.isEmpty || line.utf8.first == UInt8(ascii: "#") { continue }
      words.append(lowered(line))
    }
    return words
  }

  static func readSafeWords(_ safeListFiles: [String]) throws -> [String] {
    var safeWordList: [String] = []
    for file in safeListFiles {
      // InputMultiFile::ReadLine (std::getline over each file in turn).
      for line in CodeGenUtil.getlines(try FileUtil.getContentBytes(file)) {
        if line.isEmpty || line.utf8.first == UInt8(ascii: "#") { continue }
        safeWordList.append(lowered(line))
      }
    }
    return safeWordList
  }

  static let kMinimumFilterBytes = 100 * 1000

  static func getFilter(_ numBytes: Int, _ wordList: [String]) -> ExistenceFilterBuilder {
    GenmaiLog.info("num_bytes: \(numBytes)")
    var filter = ExistenceFilterBuilder.createOptimal(numBytes, UInt32(wordList.count))
    for word in wordList {
      filter.insert(word)
    }
    return filter
  }

  static func testFilter(_ builder: ExistenceFilterBuilder, _ safeWordList: [String]) -> Bool {
    let filter = builder.build()
    for word in safeWordList where filter.exists(word) {
      GenmaiLog.warning("Safe word, \(word) is determined as bad suggestion.")
      return false
    }
    return true
  }

  static func setupFilter(_ numBytes: Int, _ wordList: [String], _ safeWordList: [String]) throws
    -> ExistenceFilterBuilder
  {
    let kNumRetryMax = 10
    let kSizeOffset = 8
    // Prevent filtering of common words by false positive.
    for i in 0..<kNumRetryMax {
      let filter = getFilter(numBytes + i * kSizeOffset, wordList)
      if testFilter(filter, safeWordList) {
        return filter
      }
    }
    throw DataGenError.invalidInput("Gave up retrying suggestion filter generation.")
  }

  public static func generate(_ input: String, safeListFiles: [String]) throws -> [UInt8] {
    let wordList = try readWords(input)
    GenmaiLog.info("\(wordList.count) words found")

    let kErrorRate: Float = 0.00001
    let numBytes = max(
      ExistenceFilterBuilder.minFilterSizeInBytesForErrorRate(kErrorRate, wordList.count), kMinimumFilterBytes)
    let safeWordList = try readSafeWords(safeListFiles)
    let filter = try setupFilter(numBytes, wordList, safeWordList)
    return filter.serializeAsString()
  }
}
