// Port of mozc/src/engine/engine_converter_stress_test.cc (3.35.6354).
//
// --test_deterministic / --test_srand_seed: deterministic with seed 0 (the C++
// defaults); MOZC_TEST_SRAND_SEED overrides the seed.

import Foundation
import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

@Suite(.serialized, .enabled(if: DataManagerTestSupport.hasMockData, "mock_genmai.data is missing"))
struct EngineConverterStressTest {
  @Test func convertToHalfWidthForRandomAsciiInput() throws {
    let seed = ProcessInfo.processInfo.environment["MOZC_TEST_SRAND_SEED"].flatMap { UInt64($0) } ?? 0
    var random = Random(seed: seed)
    try SystemUtil.withTempUserProfile { _ in
      // ConvertToHalfWidth has to return the same string as the input.
      let testCases: [(min: UInt32, max: UInt32)] = [
        (0x20, 0x7E),  // All printable characters (' ' .. '~')
        (0x61, 0x7A),  // Alphabets ('a' .. 'z')
      ]
      let kRomajiHiraganaTable = "system://romanji-hiragana.tsv"
      let request = Genmai_Commands_Request()
      let config = ConfigHandler.defaultConfig()
      let engine = try MockDataEngineFactory.create()
      let sconverter = EngineConverter(engine.getConverter(), request, config)
      let table = Table()
      #expect(table.loadFromFile(kRomajiHiraganaTable))
      var composer = Composer(table, request, config)
      var output = Genmai_Commands_Output()
      for testCase in testCases {
        let kLoopLimit = 100
        for _ in 0..<kLoopLimit {
          composer.reset()
          sconverter.reset()
          output = Genmai_Commands_Output()
          // Limited by kMaxCharLength in immutable_converter.cc
          let kInputStringLength = 32
          let input = random.utf8String(kInputStringLength, testCase.min, testCase.max)
          composer.insertCharacterPreedit(input)
          sconverter.convertToTransliteration(composer, .halfAscii)
          sconverter.fillOutput(composer, &output)
          let conversion = output.preedit
          #expect(conversion.segment.first?.value == input, "\(input)")
        }
      }
    }
  }
}
