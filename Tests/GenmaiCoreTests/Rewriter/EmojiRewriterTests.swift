// Port of mozc/src/rewriter/emoji_rewriter_test.cc (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import Testing
@testable import GenmaiCore

private let kEmoji = "えもじ"

/// Makes |segments| to have only a segment with a key-value paired candidate.
private func setSegment(_ key: String, _ value: String, _ segments: Segments) {
  segments.clear()
  let seg = segments.pushBackSegment()
  seg.setKey(key)
  let candidate = seg.addCandidate()
  candidate.value = key
  candidate.contentKey = key
  candidate.contentValue = value
}

/// Counts the number of enumerated emoji candidates in the segments.
private func countEmojiCandidates(_ segments: Segments) -> Int {
  var emojiSize = 0
  for segment in segments.all {
    for candidate in segment.candidates where EmojiRewriter.isEmojiCandidate(candidate) {
      emojiSize += 1
    }
  }
  return emojiSize
}

/// Checks if the first segment has a specific candidate.
private func hasExpectedCandidate(_ segments: Segments, _ expectValue: String) -> Bool {
  precondition(1 <= segments.segmentsSize)
  return segments.segment(0).candidates.contains { $0.value.bytesEqual(expectValue) }
}

private struct EmojiRewriterTestEntry {
  let key: String
  let unicode: String
  let unicodeVersion: EmojiVersion
  let descriptionUnicode: String
  let unusedField0: String
  let unusedField1: String
  let unusedField2: String

  init(
    _ key: String, _ unicode: String, _ unicodeVersion: EmojiVersion,
    _ descriptionUnicode: String, _ unusedField0: String, _ unusedField1: String,
    _ unusedField2: String
  ) {
    self.key = key
    self.unicode = unicode
    self.unicodeVersion = unicodeVersion
    self.descriptionUnicode = descriptionUnicode
    self.unusedField0 = unusedField0
    self.unusedField1 = unusedField1
    self.unusedField2 = unusedField2
  }
}

// Elements must be sorted lexicographically by key (first string).
private let kTestEmojiList: [EmojiRewriterTestEntry] = [
  // An actual emoji character
  .init("Emoji", "🐭", .e0_6, "nezumi picture", "", "", ""),

  // Meta candidates.
  .init("Inu", "DOG", .e0_6, "inu", "", "", ""),
  .init("Neko", "CAT", .e0_6, "neko", "", "", ""),
  .init("Nezumi", "MOUSE", .e0_6, "nezumi", "", "", ""),
  .init("Nezumi", "RAT", .e0_6, "nezumi", "", "", ""),
  .init("X", "COW", .e0_6, "ushi", "", "", ""),
  .init("X", "TIGER", .e0_6, "tora", "", "", ""),
  .init("X", "RABIT", .e0_6, "usagi", "", "", ""),
  .init("X", "DRAGON", .e0_6, "ryu", "", "", ""),
]

/// `TestEmojiData`: builds the token array and string array of
/// `kTestEmojiList`.
private func makeTestEmojiRewriterData() -> (tokenArray: DataView, stringArray: DataView) {
  // Collect all the strings (absl::btree_map<std::string, size_t>: bytewise
  // order).
  var unique: [[UInt8]: Int] = [:]
  var strings: [String] = []
  for data in kTestEmojiList {
    for s in [
      data.key, data.unicode, data.descriptionUnicode, data.unusedField0, data.unusedField1,
      data.unusedField2,
    ] where unique[Array(s.utf8)] == nil {
      unique[Array(s.utf8)] = 0
      strings.append(s)
    }
  }
  strings.sort(by: Strings.byteLess)
  // Set index.
  for (index, s) in strings.enumerated() {
    unique[Array(s.utf8)] = index
  }
  func index(_ s: String) -> UInt32 { UInt32(unique[Array(s.utf8)]!) }

  // Create token array.
  var tokenArray: [UInt32] = []
  for data in kTestEmojiList {
    tokenArray.append(index(data.key))
    tokenArray.append(index(data.unicode))
    tokenArray.append(data.unicodeVersion.rawValue)
    tokenArray.append(index(data.descriptionUnicode))
    tokenArray.append(index(data.unusedField0))
    tokenArray.append(index(data.unusedField1))
    tokenArray.append(index(data.unusedField2))
  }
  var tokenBytes: [UInt8] = []
  for v in tokenArray {
    withUnsafeBytes(of: v.littleEndian) { tokenBytes.append(contentsOf: $0) }
  }

  // Create string array.
  let stringArrayBytes = SerializedStringArray.serializeToBuffer(strings)
  return (DataView(copying: tokenBytes), DataView(copying: stringArrayBytes))
}

@Suite(
  .enabled(if: R2RewriterTestSupport.hasMockData, R2RewriterTestSupport.mockDataMissing),
  .scopedConfigEnvironment)
struct EmojiRewriterTests {
  let rewriter: EmojiRewriter
  let fullDataRewriter: EmojiRewriter
  var request = Genmai_Commands_Request()
  var config: Genmai_Config_Config

  init() throws {
    rewriter = EmojiRewriter(makeTestEmojiRewriterData())
    fullDataRewriter = EmojiRewriter(
      try R2RewriterTestSupport.mockDataManager().getEmojiRewriterData())
    // Enable emoji conversion
    config = ConfigHandler.defaultConfig()
    config.useEmojiConversion = true
  }

  private static func convReq(_ config: Genmai_Config_Config, _ request: Genmai_Commands_Request)
    -> ConversionRequest
  {
    ConversionRequestBuilder().setConfig(config).setRequest(request).build()
  }

  @Test mutating func capability() {
    let cases: [(Genmai_Commands_Request.RewriterCapability, Rewriter.CapabilityType)] = [
      (.notAvailable, .notAvailable),
      (.conversion, .conversion),
      (.prediction, .prediction),
      (.suggestion, .suggestion),
      (.all, .all),
    ]
    for (requestCapability, expected) in cases {
      request.emojiRewriterCapability = Int32(requestCapability.rawValue)
      let convreq = Self.convReq(config, request)
      #expect(rewriter.capability(convreq) == expected)
    }
  }

  @Test func convertedSegmentsHasEmoji() {
    // This test runs an EmojiRewriter with a few strings, and checks
    //   - no conversion occur with unknown string,
    //   - expected characters are added in a conversion with a string,
    //   - all emojis are added with a specific string.

    let segments = Segments()
    setSegment("neko", "test", segments)
    let convreq = Self.convReq(config, request)
    #expect(!rewriter.rewrite(convreq, segments))
    #expect(countEmojiCandidates(segments) == 0)

    setSegment("Neko", "test", segments)
    #expect(rewriter.rewrite(convreq, segments))
    #expect(countEmojiCandidates(segments) == 1)
    #expect(hasExpectedCandidate(segments, "CAT"))

    setSegment("Nezumi", "test", segments)
    #expect(rewriter.rewrite(convreq, segments))
    #expect(countEmojiCandidates(segments) == 2)
    #expect(hasExpectedCandidate(segments, "MOUSE"))
    #expect(hasExpectedCandidate(segments, "RAT"))

    setSegment(kEmoji, "test", segments)
    #expect(rewriter.rewrite(convreq, segments))
    #expect(countEmojiCandidates(segments) == 9)
  }

  @Test mutating func noConversionWithDisabledSettings() {
    // This test checks no emoji conversion occur if emoji conversion is
    // disabled in settings. Same segments are tested with
    // ConvertedSegmentsHasEmoji test.

    // Disable emoji conversion in settings
    config.useEmojiConversion = false

    let segments = Segments()
    setSegment("test", "test", segments)
    let convreq = Self.convReq(config, request)
    #expect(!rewriter.rewrite(convreq, segments))
    #expect(countEmojiCandidates(segments) == 0)

    setSegment("Neko", "test", segments)
    #expect(!rewriter.rewrite(convreq, segments))
    #expect(countEmojiCandidates(segments) == 0)
    #expect(!hasExpectedCandidate(segments, "CAT"))

    setSegment("Nezumi", "test", segments)
    #expect(!rewriter.rewrite(convreq, segments))
    #expect(countEmojiCandidates(segments) == 0)
    #expect(!hasExpectedCandidate(segments, "MOUSE"))
    #expect(!hasExpectedCandidate(segments, "RAT"))

    setSegment(kEmoji, "test", segments)
    #expect(!rewriter.rewrite(convreq, segments))
    #expect(countEmojiCandidates(segments) == 0)
  }

  @Test func checkDescription() throws {
    let dataManager = try R2RewriterTestSupport.mockDataManager()
    let segments = Segments()
    let variantsRewriter = VariantsRewriter(PosMatcher(dataManager.getPosMatcherData()))

    setSegment("Emoji", "test", segments)
    let convreq = Self.convReq(config, request)
    #expect(rewriter.rewrite(convreq, segments))
    #expect(variantsRewriter.rewrite(convreq, segments))
    try #require(0 < countEmojiCandidates(segments))
    let segment = segments.segment(0)
    for candidate in segment.candidates {
      let description = candidate.description
      // Skip non emoji candidates.
      if !EmojiRewriter.isEmojiCandidate(candidate) {
        continue
      }
      #expect(
        !description.contains("[全]"),
        "for \"\(candidate.value)\" : \"\(description)\"")
    }
  }

  @Test func checkInsertPosition() throws {
    // This test checks if emoji candidates are inserted into the expected
    // position.

    // |kExpectPosition| has the same number with |kDefaultInsertPos| defined
    // in emoji_rewriter.cc.
    let kExpectPosition = 6

    let segments = Segments()
    do {
      let segment = segments.pushBackSegment()
      segment.setKey("Neko")
      for i in 0..<(kExpectPosition * 2) {
        let value = "candidate\(i)"
        let candidate = segment.addCandidate()
        candidate.value = value
        candidate.contentKey = "Neko"
        candidate.contentValue = value
      }
    }
    let convreq = Self.convReq(config, request)
    #expect(rewriter.rewrite(convreq, segments))

    try #require(segments.segmentsSize == 1)
    let segment = segments.segment(0)
    try #require(kExpectPosition <= segment.candidatesSize)
    for i in 0..<kExpectPosition {
      #expect(!EmojiRewriter.isEmojiCandidate(segment.candidate(i)))
    }
    let candidate = segment.candidate(kExpectPosition)
    #expect(EmojiRewriter.isEmojiCandidate(candidate))
    #expect(candidate.value == "CAT")
  }

  @Test func queryNormalization() {
    for (key, value) in [("Ｎｅｋｏ", "Neko"), ("Neko", "Neko")] {
      let segments = Segments()
      setSegment(key, value, segments)
      let convreq = Self.convReq(config, request)
      #expect(rewriter.rewrite(convreq, segments), "\(key)")
    }
  }

  @Test func fullDataTest() {
    let cases: [(String, String)] = [
      // U+1F646 (FACE WITH OK GESTURE)
      ("ＯＫ", "OK"), ("OK", "OK"),
      // U+2795 (HEAVY PLUS SIGN)
      ("＋", "+"), ("+", "+"),
      // U+1F522 (INPUT SYMBOL FOR NUMBERS)
      ("１２３４", "1234"), ("1234", "1234"),
      // U+1F552 (CLOCK FACE THREE OCLOCK)
      ("３じ", "3ji"), ("3じ", "3ji"),
      // U+31 U+FE0F U+20E3 (KEYCAP 1)
      ("１", "1"), ("1", "1"),
    ]
    for (key, value) in cases {
      let segments = Segments()
      setSegment(key, value, segments)
      let convreq = Self.convReq(config, request)
      #expect(fullDataRewriter.rewrite(convreq, segments), "\(key)")
    }
  }
}
