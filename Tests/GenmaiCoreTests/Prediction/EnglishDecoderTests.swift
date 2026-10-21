// Port of mozc/src/prediction/english_decoder_test.cc (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private struct EnglishPredictionTestEntry: Sendable, CustomTestStringConvertible {
  let name: String
  let inputMode: TransliterationType
  let key: String
  let expectedPrefix: String
  let expectedValues: [String]
  var testDescription: String { name }
}

private let kEnglishPredictionTestEntries: [EnglishPredictionTestEntry] = [
  EnglishPredictionTestEntry(
    name: "HALF_ASCII_lower_case", inputMode: .halfAscii, key: "conv", expectedPrefix: "conv",
    expectedValues: ["converge", "converged", "convergent"]),
  EnglishPredictionTestEntry(
    name: "HALF_ASCII_upper_case", inputMode: .halfAscii, key: "CONV", expectedPrefix: "CONV",
    expectedValues: ["CONVERGE", "CONVERGED", "CONVERGENT"]),
  EnglishPredictionTestEntry(
    name: "HALF_ASCII_capitalized", inputMode: .halfAscii, key: "Conv", expectedPrefix: "Conv",
    expectedValues: ["Converge", "Converged", "Convergent"]),
  EnglishPredictionTestEntry(
    name: "FULL_ASCII_lower_case", inputMode: .fullAscii, key: "conv", expectedPrefix: "ｃｏｎｖ",
    expectedValues: ["ｃｏｎｖｅｒｇｅ", "ｃｏｎｖｅｒｇｅｄ", "ｃｏｎｖｅｒｇｅｎｔ"]),
  EnglishPredictionTestEntry(
    name: "FULL_ASCII_upper_case", inputMode: .fullAscii, key: "CONV", expectedPrefix: "ＣＯＮＶ",
    expectedValues: ["ＣＯＮＶＥＲＧＥ", "ＣＯＮＶＥＲＧＥＤ", "ＣＯＮＶＥＲＧＥＮＴ"]),
  EnglishPredictionTestEntry(
    name: "FULL_ASCII_capitalized", inputMode: .fullAscii, key: "Conv", expectedPrefix: "Ｃｏｎｖ",
    expectedValues: ["Ｃｏｎｖｅｒｇｅ", "Ｃｏｎｖｅｒｇｅｄ", "Ｃｏｎｖｅｒｇｅｎｔ"]),
]

@Suite(.enabled(if: predictionMockDataAvailable, "mock_genmai.data is missing"))
struct EnglishDecoderTests {
  let dict = KeyedMockDictionary()
  let modules: PredictionTestModules
  let decoder: EnglishDecoder
  let config = PT.config()
  let request = Genmai_Commands_Request()
  var composer: Composer

  init() throws {
    dict.predictive.on(
      "conv",
      kv: [
        ("converge", "converge"),
        ("converged", "converged"),
        ("convergent", "convergent"),
      ])
    dict.predictive.on(
      "con",
      kv: [
        ("contraction", "contraction"),
        ("control", "control"),
      ])
    dict.predictive.on("hel", kv: [("hello", "hello")])

    modules = try PredictionTestModules.mock(dictionary: dict.mock)
    decoder = EnglishDecoder(modules)
    composer = Composer(PT.tableFromFile("system://romanji-hiragana.tsv"), request, config)
  }

  private func createPredictionRequest() -> ConversionRequest {
    ConversionRequestBuilder().setComposer(composer).setRequestType(.prediction).build()
  }

  @Test func emptyRequestReturnsEmpty() {
    let request = ConversionRequest()
    #expect(decoder.decode(request).isEmpty)
  }

  @Test(arguments: kEnglishPredictionTestEntries)
  private mutating func aggregateEnglishPrediction(_ entry: EnglishPredictionTestEntry) {
    composer.reset()
    composer.setInputMode(entry.inputMode)
    PT.insertInputSequence(entry.key, &composer)

    let results = decoder.decode(createPredictionRequest())

    var values = Set<String>()
    for result in results {
      #expect((result.attributes & Attribute.english) != 0)
      #expect(
        result.value.hasBytePrefix(entry.expectedPrefix),
        "\(result.value) doesn't start with \(entry.expectedPrefix)")
      values.insert(result.value)
    }
    for expectedValue in entry.expectedValues {
      #expect(values.contains(expectedValue), "\(expectedValue) isn't in the results")
    }
  }
}
