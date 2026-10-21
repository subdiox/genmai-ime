// Port of mozc/src/rewriter/a11y_description_rewriter_test.cc (3.35.6354).

import Foundation
import GenmaiProtocol
import Testing
@testable import GenmaiCore

@Suite(.enabled(if: MockDataManager.defaultDataPath != nil, "mock_genmai.data is missing; run Tools/build_oracle.sh"))
struct A11yDescriptionRewriterTests {
  private let rewriter: A11yDescriptionRewriter
  private let rewriterWithoutData: A11yDescriptionRewriter

  init() throws {
    let mockDataManager = try MockDataManager()
    rewriter = A11yDescriptionRewriter(mockDataManager.getA11yDescriptionRewriterData())
    rewriterWithoutData = A11yDescriptionRewriter(DataView(), DataView())
  }

  private static func addCandidateWithValue(_ value: String, _ segment: Segment) {
    let candidate = segment.addCandidate()
    candidate.key = segment.key
    candidate.contentKey = segment.key
    candidate.value = value
    candidate.contentValue = value
  }

  private var getRewriter: any RewriterInterface { rewriter }
  private var getRewriterWithoutData: any RewriterInterface { rewriterWithoutData }

  @Test func withoutData() {
    var a11yRequest = Genmai_Commands_Request()
    a11yRequest.enableA11YDescription = true

    let a11yConvRequest = ConversionRequestBuilder().setRequest(a11yRequest).build()

    #expect(getRewriterWithoutData.capability(a11yConvRequest) == .notAvailable)
  }

  @Test func capability() {
    let requestDefault = ConversionRequest()

    var requestA11yDescription = Genmai_Commands_Request()
    requestA11yDescription.enableA11YDescription = true
    let convRequestA11yDescription =
      ConversionRequestBuilder().setRequest(requestA11yDescription).build()

    var requestTalkback = Genmai_Commands_Request()
    requestTalkback.isA11YTalkbackEnabled = true
    let convRequestTalkback = ConversionRequestBuilder().setRequest(requestTalkback).build()

    #expect(getRewriter.capability(requestDefault) == .notAvailable)
    #expect(getRewriter.capability(convRequestA11yDescription) == .all)
    #expect(getRewriter.capability(convRequestTalkback) == .all)
  }

  @Test func addA11yDescriptionForSingleCharacter() {
    let request = ConversionRequest()

    let segments = Segments()
    let segment = segments.pushBackSegment()
    for v in ["あ", "イ", "ｱ", "亜", "ぁ", "ｧ", "ー", "a", "B", "ｃ", "Ｄ"] {
      Self.addCandidateWithValue(v, segment)
    }

    #expect(getRewriter.rewrite(request, segments))
    #expect(segment.candidate(0).a11yDescription == "あ。ヒラガナ あ")
    #expect(segment.candidate(1).a11yDescription == "イ。カタカナ イ")
    #expect(segment.candidate(2).a11yDescription == "ｱ。ハンカクカタカナ ｱ")
    #expect(segment.candidate(3).a11yDescription == "亜。アネッタイ ノ ア")
    #expect(segment.candidate(4).a11yDescription == "ぁ。ヒラガナコモジ あ")
    #expect(segment.candidate(5).a11yDescription == "ｧ。ハンカクカタカナコモジ ｱ")
    #expect(segment.candidate(6).a11yDescription == "ー。チョウオン ー")
    #expect(segment.candidate(7).a11yDescription == "a。コモジ a")
    #expect(segment.candidate(8).a11yDescription == "B。オオモジ B")
    #expect(segment.candidate(9).a11yDescription == "ｃ。ゼンカクコモジ ｃ")
    #expect(segment.candidate(10).a11yDescription == "Ｄ。ゼンカクオオモジ Ｄ")
  }

  @Test func addA11yDescriptionForMultiCharacters() {
    let request = ConversionRequest()

    let segments = Segments()
    let segment = segments.pushBackSegment()
    for v in ["あ亜", "ぁたし", "ぁぃ", "ｧｨ", "あぃ"] {
      Self.addCandidateWithValue(v, segment)
    }

    #expect(getRewriter.rewrite(request, segments))
    #expect(segment.candidate(0).a11yDescription == "あ亜。ヒラガナ あ。アネッタイ ノ ア")
    #expect(segment.candidate(1).a11yDescription == "ぁたし。ヒラガナコモジ あ。ヒラガナ たし")
    #expect(segment.candidate(2).a11yDescription == "ぁぃ。ヒラガナコモジ あ。ヒラガナコモジ い")
    #expect(
      segment.candidate(3).a11yDescription == "ｧｨ。ハンカクカタカナコモジ ｱ。ハンカクカタカナコモジ ｲ")
    #expect(segment.candidate(4).a11yDescription == "あぃ。ヒラガナ あぃ")
  }

  @Test func addA11yDescriptionForHiraganaCharacters() {
    let request = ConversionRequest()

    let segments = Segments()
    let segment = segments.pushBackSegment()
    Self.addCandidateWithValue("あい", segment)

    #expect(getRewriter.rewrite(request, segments))
    #expect(segment.candidate(0).a11yDescription == "あい。ヒラガナ あい")
  }

  @Test func addA11yDescriptionForUnsupportedCharacter() {
    let request = ConversionRequest()

    let segments = Segments()
    let segment = segments.pushBackSegment()
    Self.addCandidateWithValue("☺", segment)

    #expect(getRewriter.rewrite(request, segments))
    #expect(segment.candidate(0).a11yDescription == "☺")
  }

  @Test func addA11yDescriptionForLongSound() {
    let request = ConversionRequest()

    let segments = Segments()
    let segment = segments.pushBackSegment()
    for v in ["あー", "亜ー", "ーー", "しーずー", "シーズー", "ｼｰｽﾞｰ", "亜ー胃"] {
      Self.addCandidateWithValue(v, segment)
    }

    #expect(getRewriter.rewrite(request, segments))
    #expect(segment.candidate(0).a11yDescription == "あー。ヒラガナ あー")
    #expect(segment.candidate(1).a11yDescription == "亜ー。アネッタイ ノ ア。チョウオン ー")
    #expect(segment.candidate(2).a11yDescription == "ーー。チョウオン ーー")
    #expect(segment.candidate(3).a11yDescription == "しーずー。ヒラガナ しーずー")
    #expect(segment.candidate(4).a11yDescription == "シーズー。カタカナ シーズー")
    #expect(segment.candidate(5).a11yDescription == "ｼｰｽﾞｰ。ハンカクカタカナ ｼｰｽﾞｰ")
    #expect(
      segment.candidate(6).a11yDescription == "亜ー胃。アネッタイ ノ ア。チョウオン ー。イブクロ ノ イ")
  }

  @Test func addA11yDescriptionForAlphabetCharacters() {
    let request = ConversionRequest()

    let segments = Segments()
    let segment = segments.pushBackSegment()
    for v in ["abc", "Google", "ｘｙｚ", "Ｇｏｏｇｌｅ"] {
      Self.addCandidateWithValue(v, segment)
    }

    #expect(getRewriter.rewrite(request, segments))
    #expect(segment.candidate(0).a11yDescription == "abc。コモジ abc")
    #expect(segment.candidate(1).a11yDescription == "Google。オオモジ G。コモジ oogle")
    #expect(segment.candidate(2).a11yDescription == "ｘｙｚ。ゼンカクコモジ ｘｙｚ")
    #expect(
      segment.candidate(3).a11yDescription == "Ｇｏｏｇｌｅ。ゼンカクオオモジ Ｇ。ゼンカクコモジ ｏｏｇｌｅ")
  }

  @Test func candidateValue() {
    // Confirm the `value` is used rather than `content_value`.
    let segments = Segments()
    let segment = segments.pushBackSegment()
    segment.setKey("あを")
    let candidate = segment.addCandidate()
    candidate.key = "あを"
    candidate.contentKey = "あ"
    candidate.value = "亜を"
    candidate.contentValue = "亜"

    let request = ConversionRequest()
    #expect(getRewriter.rewrite(request, segments))
    #expect(segment.candidate(0).a11yDescription == "亜を。アネッタイ ノ ア。ヒラガナ を")
  }
}
