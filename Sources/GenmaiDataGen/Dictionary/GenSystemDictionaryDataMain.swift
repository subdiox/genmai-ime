// Port of mozc/src/dictionary/gen_system_dictionary_data_main.cc (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenSystemDictionaryDataMain {
  static let kReadingCorrectionFile = "reading_correction.tsv"

  /// Splits the inputs into system dictionary files and reading correction
  /// files, each joined by ",".
  static func getInputFileName(_ inputFiles: [String]) -> (String, String) {
    var systemDictionaryInputs: [String] = []
    var readingCorrectionInputs: [String] = []
    for field in inputFiles {
      if field.hasSuffix(kReadingCorrectionFile) {
        readingCorrectionInputs.append(field)
      } else {
        systemDictionaryInputs.append(field)
      }
    }
    return (systemDictionaryInputs.joined(separator: ","), readingCorrectionInputs.joined(separator: ","))
  }

  /// Data set sections produced by this generator (keys: dataset_writer_main names).
  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    ["dict": try generate(ctx.sources.dictionaryFiles, userPosManagerData: ctx.userPosManagerData)]
  }

  public static func generate(_ inputFiles: [String], userPosManagerData: [UInt8]) throws -> [UInt8] {
    let (systemDictionaryInput, readingCorrectionInput) = getInputFileName(inputFiles)

    // User POS manager data for build tools has no magic number.
    let dataManager = try DataManager.createUserPosManagerDataFromArray(
      DataView(copying: userPosManagerData), magic: [])
    let posMatcher = PosMatcher(dataManager.getPosMatcherData())

    let loader = TextDictionaryLoader(posMatcher)
    loader.load(systemDictionaryInput, readingCorrectionInput)

    let builder = SystemDictionaryBuilder()
    builder.buildFromTokens(loader.tokens)
    return builder.writeToBytes()
  }
}
