// Port of mozc/src/rewriter/correction_rewriter_test.cc (3.35.6354).
//
// engine::Modules / engine::MockSupplementalModel are not ported; the
// rewriter takes a `ReadingAlignmentSupplementalModel` directly, and the gmock
// mock becomes `CorrectionRewriterMockSupplementalModel` below whose
// alignment function can be replaced (EXPECT_CALL(...).WillRepeatedly).
// The RewriteTest built Modules with the default (stub) supplemental model;
// that is `nil` here.

import GenmaiBase
import GenmaiProtocol
import Testing
@testable import GenmaiCore

private func addSegment(_ key: String, _ segments: Segments) -> Segment {
  let segment = segments.pushBackSegment()
  segment.setKey(key)
  return segment
}

@discardableResult
private func addCandidate(
  _ key: String, _ value: String, _ contentKey: String, _ contentValue: String,
  _ segment: Segment
) -> Candidate {
  let candidate = segment.addCandidate()
  candidate.key = key
  candidate.value = value
  candidate.contentKey = contentKey
  candidate.contentValue = contentValue
  return candidate
}

private final class CorrectionRewriterMockSupplementalModel: ReadingAlignmentSupplementalModel {
  var alignment: (String, String) -> [(String, String)] = { _, _ in [] }
  func getReadingAlignment(_ surface: String, _ reading: String) -> [(String, String)] {
    alignment(surface, reading)
  }
}

private func convReq(_ config: Genmai_Config_Config) -> ConversionRequest {
  ConversionRequestBuilder().setConfig(config).build()
}

private func convReq(_ config: Genmai_Config_Config, _ request: Genmai_Commands_Request)
  -> ConversionRequest
{
  ConversionRequestBuilder().setConfig(config).setRequest(request).build()
}

private func createRewriter(
  _ model: (any ReadingAlignmentSupplementalModel)?, _ values: [String], _ errors: [String],
  _ corrections: [String]
) -> CorrectionRewriter {
  CorrectionRewriter(
    supplementalModel: model,
    valueArrayData: DataView(copying: SerializedStringArray.serializeToBuffer(values)),
    errorArrayData: DataView(copying: SerializedStringArray.serializeToBuffer(errors)),
    correctionArrayData: DataView(copying: SerializedStringArray.serializeToBuffer(corrections)))
}

@Suite struct CorrectionRewriterTests {
  @Test func rewriteTest() {
    let rewriter = createRewriter(nil, ["TSUKIGIME"], ["gekkyoku"], ["tsukigime"])

    var config = Genmai_Config_Config()
    ConfigHandler.getDefaultConfig(&config)
    config.useSpellingCorrection = true

    #expect(rewriter.capability(convReq(config)) == .all)

    let segments = Segments()
    let segment = addSegment("gekkyokuwo", segments)
    let candidate = addCandidate(
      "gekkyokuwo", "TSUKIGIMEwo", "gekkyoku", "TSUKIGIME", segment)
    candidate.attributes |= Attribute.reranked

    addCandidate("gekkyokuwo", "GEKKYOKUwo", "gekkyoku", "GEKKYOKU", segment)
    let candidate2 = addCandidate("かびばら", "かびばら", "カピバラ", "カピバラ", segment)
    candidate2.attributes |= Attribute.spellingCorrection

    config.useSpellingCorrection = false

    let convreq1 = convReq(config)
    #expect(!rewriter.rewrite(convreq1, segments))

    config.useSpellingCorrection = true
    let convreq2 = convReq(config)
    #expect(rewriter.rewrite(convreq2, segments))

    // candidate 0
    #expect(
      segments.conversionSegment(0).candidate(0).attributes
        == (Attribute.reranked | Attribute.spellingCorrection))
    #expect(segments.conversionSegment(0).candidate(0).description == "<もしかして: tsukigime>")

    // candidate 1
    #expect(segments.conversionSegment(0).candidate(1).attributes == Attribute.defaultAttribute)
    #expect(segments.conversionSegment(0).candidate(1).description.isEmpty)

    // candidate 2
    #expect(segments.conversionSegment(0).candidate(2).attributes == Attribute.spellingCorrection)
    #expect(segments.conversionSegment(0).candidate(2).description == "<もしかして>")
  }

  @Test func rewriteWithDisplayValueForReadlingCorrectionTest() {
    let mock = CorrectionRewriterMockSupplementalModel()

    // key -> aligner result
    let kReadingAlingerData: [String: [(String, String)]] = [
      "すくつ": [("巣", "す"), ("窟", "くつ")],
      "そうくつ": [("巣", "そう"), ("窟", "くつ")],
      "ふいんき": [("雰", "ふ"), ("囲", "い"), ("気", "んき")],
      "ふんいき": [("雰", "ふん"), ("囲", "い"), ("気", "き")],
      // incomplete alignment.
      "ぼんれい": [("凡例", "ぼんれい")],
      "はんれい": [("凡", "はん"), ("例", "れい")],
    ]

    // Emulates reading aligner.
    mock.alignment = { _, reading in kReadingAlingerData[reading] ?? [] }

    let rewriter = createRewriter(
      mock, ["巣窟", "雰囲気", "凡例"], ["すくつ", "ふいんき", "ぼんれい"],
      ["そうくつ", "ふんいき", "はんれい"])

    var config = Genmai_Config_Config()
    ConfigHandler.getDefaultConfig(&config)
    config.useSpellingCorrection = true

    func rewrite(
      _ key: String, _ value: String,
      _ capability: Genmai_Commands_Request.DisplayValueCapability
    ) -> Candidate {
      let segments = Segments()
      let segment = addSegment(key, segments)
      addCandidate(key, value, key, value, segment)
      var request = Genmai_Commands_Request()
      request.displayValueCapability = capability
      _ = rewriter.rewrite(convReq(config, request), segments)
      return segments.conversionSegment(0).candidate(0)
    }

    do {
      let candidate = rewrite("すくつ", "巣窟", .notSupported)
      #expect(candidate.description == "<もしかして: そうくつ>")
      #expect(candidate.displayValue.isEmpty)
    }

    do {
      let candidate = rewrite("すくつ", "巣窟", .plainText)
      #expect(candidate.description.isEmpty)
      #expect(candidate.displayValue == "巣(そう)窟")
    }

    do {
      let candidate = rewrite("ふいんき", "雰囲気", .plainText)
      #expect(candidate.description.isEmpty)
      #expect(candidate.displayValue == "雰囲気(ふんいき)")
    }

    do {
      // fallback result is returned when the alignment is broken.
      let candidate = rewrite("ぼんれい", "凡例", .plainText)
      #expect(candidate.description.isEmpty)
      #expect(candidate.displayValue == "凡例(はんれい)")
    }

    // reading aligner is not available. the same as the legacy description.
    mock.alignment = { _, _ in [] }

    do {
      let candidate = rewrite("すくつ", "巣窟", .plainText)
      #expect(candidate.description == "<もしかして: そうくつ>")
      #expect(candidate.displayValue.isEmpty)
    }

    do {
      let candidate = rewrite("ふいんき", "雰囲気", .plainText)
      #expect(candidate.description == "<もしかして: ふんいき>")
      #expect(candidate.displayValue.isEmpty)
    }
  }

  @Test func rewriteWithDisplayValueForKatakanaTest() {}
}
