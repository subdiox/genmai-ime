// Port of mozc/src/converter/quality_regression_util_test.cc (3.35.6354).

import Testing

@testable import GenmaiCore

@Suite("QualityRegressionUtil")
struct QualityRegressionUtilTests {
  @Test func parseFromTSV() throws {
    do {
      var item = QualityRegressionUtil.TestItem()
      try item.parseFromTSV("label\tかたがこる\t肩が(こ|凝)る\tConversion Match")
      #expect(item.label == "label")
      #expect(item.key == "かたがこる")
      #expect(item.expectedValue == "肩が(こ|凝)る")
      #expect(item.command == "Conversion Match")
      #expect(item.expectedRank == 0)
    }
    do {
      var item = QualityRegressionUtil.TestItem()
      try item.parseFromTSV("label\tかたがこる\t.*型.*\tConversion Not Match")
      #expect(item.command == "Conversion Not Match")
      #expect(item.expectedRank == 0)
    }
  }

  private func parse(_ line: String) throws -> QualityRegressionUtil.TestItem {
    var item = QualityRegressionUtil.TestItem()
    try item.parseFromTSV(line)
    return item
  }

  @Test func convertAndTestMatchSingleSegment() throws {
    let mock = MockConverter()
    let util = QualityRegressionUtil(mock)

    let segments = Segments()
    let seg = segments.addSegment()
    seg.setKey("かたがこる")
    // Candidate 0: "型が凝る"
    seg.addCandidate().value = "型が凝る"

    mock.setStartConversion(segments, true)

    // Conversion Match: candidate 0 is "型が凝る", expected is "肩が(こ|凝)る"
    // -> fail
    do {
      let item = try parse("label\tかたがこる\t肩が(こ|凝)る\tConversion Match")
      var actualValue = ""
      let result = try util.convertAndTest(item, &actualValue)
      #expect(!result)
      #expect(actualValue == "型が凝る")
    }

    // Conversion Match: candidate 0 is "型が凝る", expected is ".*型.*" ->
    // succeed
    do {
      let item = try parse("label\tかたがこる\t.*型.*\tConversion Match")
      var actualValue = ""
      let result = try util.convertAndTest(item, &actualValue)
      #expect(result)
      #expect(actualValue == "型が凝る")
    }

    // Conversion Not Match: candidate 0 does not match ".*肩.*" -> succeed
    do {
      let item = try parse("label\tかたがこる\t.*肩.*\tConversion Not Match")
      var actualValue = ""
      #expect(try util.convertAndTest(item, &actualValue))
    }

    // Conversion Not Match: candidate 0 matches ".*型.*" -> fail
    do {
      let item = try parse("label\tかたがこる\t.*型.*\tConversion Not Match")
      var actualValue = ""
      #expect(try !util.convertAndTest(item, &actualValue))
    }

    // Conversion Match with invalid regex pattern
    do {
      let item = try parse("label\tかたがこる\t(\tConversion Match")
      var actualValue = ""
      #expect(throws: (any Error).self) { try util.convertAndTest(item, &actualValue) }
    }
  }

  @Test func convertAndTestMatchMultiSegment() throws {
    let mock = MockConverter()
    let util = QualityRegressionUtil(mock)

    let segments = Segments()
    // Segment 0
    let seg0 = segments.addSegment()
    seg0.setKey("かたが")
    seg0.addCandidate().value = "肩が"
    seg0.addCandidate().value = "型が"

    // Segment 1
    let seg1 = segments.addSegment()
    seg1.setKey("こる")
    seg1.addCandidate().value = "こる"
    seg1.addCandidate().value = "凝る"

    mock.setStartConversion(segments, true)

    // "肩が" + "こる" matches "肩が(こ|凝)る" at rank 0
    do {
      let item = try parse("label\tかたがこる\t肩が(こ|凝)る\tConversion Match")
      var actualValue = ""
      #expect(try util.convertAndTest(item, &actualValue))
      #expect(actualValue == "肩がこる")
    }

    // Substring match via ".*(こ|凝)る"
    do {
      let item = try parse("label\tかたがこる\t.*(こ|凝)る\tConversion Match")
      var actualValue = ""
      #expect(try util.convertAndTest(item, &actualValue))
    }
  }
}
