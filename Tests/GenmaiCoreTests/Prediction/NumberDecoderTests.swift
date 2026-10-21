// Port of mozc/src/prediction/number_decoder_test.cc (3.35.6354).

import GenmaiBase
import Testing

@testable import GenmaiCore

private struct NumberDecoderTestParam: Sendable, CustomTestStringConvertible {
  let key: String
  let expected: [NumberDecoderResult]

  init(_ key: String, _ results: [(Int, String, Int)] = []) {
    self.key = key
    expected = results.map { NumberDecoderResult(UInt32($0.0), $0.1, $0.2) }
  }

  var testDescription: String { key }
}

private func allConsumed(_ key: String, _ results: [(String, Int)]) -> NumberDecoderTestParam {
  NumberDecoderTestParam(key, results.map { (key.utf8.count, $0.0, $0.1) })
}

private func unorderedEqual(_ a: [NumberDecoderResult], _ b: [NumberDecoderResult]) -> Bool {
  if a.count != b.count { return false }
  var rest = b
  for x in a {
    guard let i = rest.firstIndex(of: x) else { return false }
    rest.remove(at: i)
  }
  return true
}

private let kUnits: [NumberDecoderTestParam] = [
  allConsumed("ぜろ", [("0", 1)]),
  allConsumed("いち", [("1", 1)]),
  allConsumed("に", [("2", 1)]),
  allConsumed("さん", [("3", 1)]),
  allConsumed("し", [("4", 1)]),
  allConsumed("ご", [("5", 1)]),
  allConsumed("ろく", [("6", 1)]),
  allConsumed("なな", [("7", 1)]),
  allConsumed("はち", [("8", 1)]),
  allConsumed("きゅう", [("9", 1)]),
]

private let kSmallDigits: [NumberDecoderTestParam] = [
  allConsumed("じゅう", [("10", 2)]),
  allConsumed("ひゃく", [("100", 3)]),
  allConsumed("せん", [("1000", 4)]),
]

private let kBigDigits: [NumberDecoderTestParam] = [
  allConsumed("まん", []), allConsumed("おく", []),
  allConsumed("ちょう", []), allConsumed("けい", []),
  allConsumed("がい", []),
  allConsumed("いちまん", [("1万", 5)]),
  allConsumed("いちおく", [("1億", 9)]),
  NumberDecoderTestParam("いっちょう", [(6, "1", 1), (15, "1兆", 13)]),
  NumberDecoderTestParam("いっけい", [(6, "1", 1), (12, "1京", 17)]),
  allConsumed("いちがい", [("1垓", 21)]),
]

private let kSuffix: [NumberDecoderTestParam] = [
  NumberDecoderTestParam("にせんち", [(3, "2", 1)]),
  NumberDecoderTestParam("にちょうめ", [(3, "2", 1)]),
  NumberDecoderTestParam("さんちょうめ", [(6, "3", 1)]),
]

private let kOthers: [NumberDecoderTestParam] = [
  NumberDecoderTestParam("ぜろに", [(6, "0", 1)]), NumberDecoderTestParam("にいち", [(3, "2", 1)]),
  NumberDecoderTestParam("にぜろ", [(3, "2", 1)]), NumberDecoderTestParam("にこ", [(3, "2", 1)]),
  NumberDecoderTestParam("にこにこ", [(3, "2", 1)]),
  NumberDecoderTestParam("にさんじゅう", [(3, "2", 1)]),
  NumberDecoderTestParam("にさんひゃく", [(3, "2", 1)]),
  NumberDecoderTestParam("にじゅう", [(3, "2", 1), (12, "20", 2)]),
  NumberDecoderTestParam("にじゅうさん", [(18, "23", 2)]),
  NumberDecoderTestParam("にじゅうさんぜん", [(18, "23", 2)]),
  NumberDecoderTestParam("にせん", [(3, "2", 1), (9, "2000", 4)]),
  NumberDecoderTestParam("にせんの", [(3, "2", 1), (9, "2000", 4)]),
  NumberDecoderTestParam("にせんさん", [(15, "2003", 4)]),
  NumberDecoderTestParam("にせんさんせん", [(15, "2003", 4)]),
  NumberDecoderTestParam("いちまんにせん", [(15, "1万2", 5), (21, "1万2000", 5)]),
  NumberDecoderTestParam("いちまんにせんさん", [(27, "1万2003", 5)]),
  NumberDecoderTestParam("いちおくさんぜんまん", [(30, "1億3000万", 9)]),
  NumberDecoderTestParam("いちまんさんおく", [(18, "1万3", 5)]),
  NumberDecoderTestParam("いちまんさんまん", [(18, "1万3", 5)]),
  NumberDecoderTestParam("いちおくにせん", [(15, "1億2", 9), (21, "1億2000", 9)]),
  NumberDecoderTestParam("にちょう", [(3, "2", 1), (12, "2兆", 13)]),
  NumberDecoderTestParam("にちょうせ", [(3, "2", 1), (12, "2兆", 13)]),
  NumberDecoderTestParam("にちょうせん", [(12, "2兆", 13), (18, "2兆1000", 13)]),
  NumberDecoderTestParam("じゅうにちょう", [(12, "12", 2), (21, "12兆", 14)]),
  NumberDecoderTestParam("じゅうにちょうの", [(12, "12", 2), (21, "12兆", 14)]),
  NumberDecoderTestParam("じゅうにちょうでも", [(12, "12", 2), (21, "12兆", 14)]),
  NumberDecoderTestParam("じゅうにちょうめ", [(12, "12", 2)]),
  NumberDecoderTestParam("じゅうにちょうめの", [(12, "12", 2)]),
  NumberDecoderTestParam("にちゃん", [(3, "2", 1)]),
  NumberDecoderTestParam("にちゃんねる", [(3, "2", 1)]),
  NumberDecoderTestParam("じゅうにちゃん", [(12, "12", 2)]),
  NumberDecoderTestParam("ごごう", [(3, "5", 1)]),
  NumberDecoderTestParam("じゅうごう", [(9, "10", 2)]),
  NumberDecoderTestParam("じゅうさんちーむ", [(9, "10", 2), (15, "13", 2)]),
  NumberDecoderTestParam("にじゅうさんちーむ", [(12, "20", 2), (18, "23", 2)]),
  NumberDecoderTestParam("にじゅうまんさんぜん", [(30, "20万3000", 6), (24, "20万3", 6)]),
  NumberDecoderTestParam(
    "せんにひゃくおくさんぜんよんひゃくまんごせんろっぴゃく", [(27 * 3, "1200億3400万5600", 12)]),
]

private let kInvalidSequences: [NumberDecoderTestParam] = [
  NumberDecoderTestParam("よせん"),
  NumberDecoderTestParam("しけい"),
  NumberDecoderTestParam("しせん"),
  NumberDecoderTestParam("くせん"),
  NumberDecoderTestParam("しがいせん"),
]

@Suite(.enabled(if: predictionMockDataAvailable, "mock_genmai.data is missing"))
struct NumberDecoderTests {
  let posMatcher: PosMatcher

  init() throws {
    posMatcher = try PredictionTestModules.mock().getPosMatcher()
  }

  private func check(_ param: NumberDecoderTestParam) {
    let decoder = NumberDecoder(posMatcher)
    let actual = decoder.decode(param.key)
    #expect(unorderedEqual(actual, param.expected), "\(param.key): \(actual)")
  }

  @Test(arguments: kUnits) private func decodeUnits(_ param: NumberDecoderTestParam) {
    check(param)
  }

  @Test(arguments: kSmallDigits) private func decodeSmallDigits(_ param: NumberDecoderTestParam) {
    check(param)
  }

  @Test(arguments: kBigDigits) private func decodeBigDigits(_ param: NumberDecoderTestParam) {
    check(param)
  }

  @Test(arguments: kSuffix) private func decodeSuffix(_ param: NumberDecoderTestParam) {
    check(param)
  }

  @Test(arguments: kOthers) private func decodeOthers(_ param: NumberDecoderTestParam) {
    check(param)
  }

  @Test(arguments: kInvalidSequences)
  private func decodeInvalidSequences(_ param: NumberDecoderTestParam) {
    check(param)
  }

  @Test func random() {
    let kKeys = [
      "ぜろ", "いち", "いっ", "に", "さん", "し",
      "よん", "ご", "ろく", "ろっ", "なな", "しち",
      "はち", "はっ", "きゅう", "きゅー", "く", "じゅう",
      "じゅー", "じゅっ", "ひゃく", "ひゃっ", "びゃく", "びゃっ",
      "ぴゃく", "ぴゃっ", "せん", "ぜん", "まん", "おく",
      "おっ", "ちょう", "けい", "がい", "にちょう", "にちょうめ",
      "にちゃん", "さんちーむ",
    ]

    let kTestSize = 1000
    let kKeySize = 10
    let decoder = NumberDecoder(posMatcher)
    var gen = SystemRandomNumberGenerator()
    for _ in 0..<kTestSize {
      var key = ""
      for _ in 0..<kKeySize {
        key += kKeys[Int.random(in: 0..<kKeys.count, using: &gen)]
      }
      // Check the key does not cause any failure.
      _ = decoder.decode(key)

      let request = ConversionRequestBuilder().setKey(key).build()
      for result in decoder.decode(request) {
        #expect(key.hasBytePrefix(result.key))
        if result.key.utf8.count < key.utf8.count {
          #expect((result.attributes & Attribute.partiallyKeyConsumed) != 0)
          #expect(Int(result.consumedKeySize) == Util.charsLen(result.key))
          #expect(result.wcost >= 1000)
          #expect(result.lid != 0)
          #expect(result.rid != 0)
        }
      }
    }
  }
}
