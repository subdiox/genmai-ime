// Port of mozc/src/rewriter/environmental_filter_rewriter_test.cc (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

@Suite struct EnvironmentalFilterRewriterTests {
  private static let kKanaSupplement6Dot0 = "\u{1B001}"
  private static let kKanaSupplement10Dot0 = "\u{1B002}"
  private static let kKanaExtendedA14Dot0 = "\u{1B122}"

  private static func addSegment(_ key: String, _ value: String, _ segments: Segments) {
    segments.clear()
    let seg = segments.pushBackSegment()
    seg.setKey(key)
    let candidate = seg.addCandidate()
    candidate.value = value
    candidate.contentValue = value
  }

  private static func addSegment(_ key: String, _ values: [String], _ segments: Segments) {
    let seg = segments.addSegment()
    seg.setKey(key)
    for value in values {
      let candidate = seg.addCandidate()
      candidate.contentKey = key
      candidate.value = value
      candidate.contentValue = value
    }
  }

  // Elements must be sorted lexicographically by key (first string).
  private static let kTestEmojiList: [(emoji: String, unicodeVersion: EmojiVersion)] = [
    // Emoji 12.1 Example
    ("🧑‍✈", .e12_1),  // 1F9D1 200D 2708
    ("🧑‍⚖", .e12_1),  // 1F9D1 200D 2696
    ("🧑‍🏭", .e12_1),  // 1F9D1 200D 1F527
    ("🧑‍💻", .e12_1),  // 1F9D1 200D 1F4BB
    ("🧑‍🏫", .e12_1),  // 1F9D1 200D 1F3EB
    ("🧑‍🌾", .e12_1),  // 1F9D1 200D 1F33E
    ("🧑‍🦼", .e12_1),  // 1F9D1 200D 1F9BC
    ("🧑‍🦽", .e12_1),  // 1F9D1 200D 1F9BD

    // Emoji 13.0 Example
    ("🛻", .e13_0),  // 1F6FB
    ("🛼", .e13_0),  // 1F6FC
    ("🤵‍♀", .e13_0),  // 1F935 200D 2640
    ("🤵‍♂", .e13_0),  // 1F935 200D 2642
    ("🥲", .e13_0),  // 1F972
    ("🥷", .e13_0),  // 1F977
    ("🥸", .e13_0),  // 1F978
    ("🧑‍🎄", .e13_0),  // 1F9D1 200D 1F384

    // Emoji 14.0 Example
    ("🩻", .e14_0),  // 1FA7B
    ("🩼", .e14_0),  // 1FA7C
    ("🪩", .e14_0),  // 1FAA9
    ("🪪", .e14_0),  // 1FAAA
    ("🪫", .e14_0),  // 1FAAB
    ("🪬", .e14_0),  // 1FAAC
    ("🫃", .e14_0),  // 1FAC3
    ("🫠", .e14_0),  // 1FAE0

    // Emoji 16.0 Example
    ("🪏", .e16_0),  // 1FA8F
    ("🫆", .e16_0),  // 1FAC6
    ("🫟", .e16_0),  // 1FADF

    // Emoji 17.0 Example
    ("🛘", .e17_0),  // 1F6D8 LANDSLIDE
    ("🫍", .e17_0),  // 1FACD ORCA
    ("🫯", .e17_0),  // 1FAEF FIGHT_CLOUD

    // Emoji 18.0 Example
    ("🛙", .e18_0),  // 1F6D9 LIGHTHOUSE
    ("🫌", .e18_0),  // 1FACC MONARCH_BUTTERFLY
    ("🫝", .e18_0),  // 1FADD PICKLE
  ]

  /// TestEmojiData::GetEmojiRewriterData().
  private static func testEmojiRewriterData() -> (tokenArray: DataView, stringArray: DataView) {
    // Collect all the strings (absl::btree_map: bytewise order).
    var strings: [String] = []
    for data in kTestEmojiList where !strings.contains(where: { $0.bytesEqual(data.emoji) }) {
      strings.append(data.emoji)
    }
    strings.sort { $0.bytesLess($1) }
    func stringIndex(_ s: String) -> UInt32 {
      guard let index = strings.firstIndex(where: { $0.bytesEqual(s) }) else {
        Issue.record("\(s) is not in the string array")
        return 0
      }
      return UInt32(index)
    }

    // Create token array.
    var tokenArray: [UInt32] = []
    for data in kTestEmojiList {
      tokenArray.append(0)
      tokenArray.append(stringIndex(data.emoji))
      tokenArray.append(data.unicodeVersion.rawValue)
      tokenArray.append(0)
      tokenArray.append(0)
      tokenArray.append(0)
      tokenArray.append(0)
    }
    var tokenBytes: [UInt8] = []
    for v in tokenArray {
      tokenBytes.appendLittleEndian(v)
    }

    // Create string array.
    let stringArrayData = SerializedStringArray.serializeToBuffer(strings)
    return (DataView(copying: tokenBytes), DataView(copying: stringArrayData))
  }

  private let rewriter = EnvironmentalFilterRewriter(Self.testEmojiRewriterData())

  private static func u32(_ s: String) -> [Char32] { Util.utf8ToUtf32(s) }

  @Test func characterGroupFinderTest() {
    // Test for CharacterGroupFinder, with meaningless filtering target rather
    // than Emoji data. As Emoji sometimes contains un-displayed characters,
    // this test can be more explicit than using actual filtering target.
    do {
      var finder = CharacterGroupFinder()
      finder.initialize([
        [0x1B001],
        [0x1B002],
        [0x1B122],
        [0x1B223],
        [0x1B224],
        [0x1B225],
        [0x1B229],
        [0x1F000],
        [0x1F001],
        [0x1B111, 0x200D, 0x1B183],
        [0x1B111, 0x200D, 0x1B142, 0x200D, 0x1B924],
        [0x1B111, 0x3009],
        [0x1B142, 0x200D, 0x3009, 0x1B924],
        [0x1B924, 0x200D, 0x1B183],
      ])
      #expect(finder.findMatch([0x1B001]))
      #expect(finder.findMatch([0x1B002]))
      #expect(finder.findMatch([0x1B223]))
      #expect(finder.findMatch([0x1B111, 0x200D, 0x1B142, 0x200D, 0x1B924]))
      #expect(finder.findMatch([0x1B111, 0x3009]))
      #expect(!finder.findMatch([0x1B111, 0x200D, 0x1B182]))
    }
    // Test CharacterGroupFinder with Emoji data. This is also necessary to
    // express how this finder should work.
    do {
      var finder = CharacterGroupFinder()
      finder.initialize([
        Self.u32("❤"),
        Self.u32("😊"),
        Self.u32("😋"),
        Self.u32("🇺🇸"),
        Self.u32("🫱🏻"),
        Self.u32("❤️‍🔥"),
        Self.u32("👬🏿"),
      ])
      #expect(finder.findMatch(Self.u32("これは❤です")))
      #expect(finder.findMatch(Self.u32("これは🫱🏻です")))
      #expect(finder.findMatch(Self.u32("これは😊です")))
      #expect(finder.findMatch(Self.u32("これは😋です")))
      #expect(!finder.findMatch(Self.u32("これは😌（U+1F60C）です")))
      #expect(finder.findMatch(Self.u32("😋これは最初です")))
      #expect(finder.findMatch(Self.u32("これは最後です😋")))
      #expect(!finder.findMatch(Self.u32("これは🫱です")))
      #expect(finder.findMatch(Self.u32("これは👬🏿です")))
      #expect(finder.findMatch(Self.u32("👬🏿最初です")))
      #expect(finder.findMatch(Self.u32("❤️‍🔥")))
      #expect(finder.findMatch(Self.u32("最後です👬🏿")))
      #expect(finder.findMatch(Self.u32("👬👬🏿")))
      #expect(!finder.findMatch(Self.u32("これは👬です")))
      // This is expecting to find 🇺🇸 (US). Because flag Emojis use regional
      // indicators, and they lack ZWJ between, ambiguity is inevitable. The
      // input is AUSE in regional indicators, and therefore US is found
      // between the two flags.
      #expect(finder.findMatch(Self.u32("🇦🇺🇸🇪")))
    }
    do {
      // Test with more than 16 chars.
      var finder = CharacterGroupFinder()
      finder.initialize([Self.u32("01234567890abcdefghij")])
      #expect(!finder.findMatch(Self.u32("01234567890abcdefghXYZ")))
    }
    do {
      // Test with empty finder.
      var finder = CharacterGroupFinder()
      finder.initialize([])
      #expect(!finder.findMatch(Self.u32("Empty finder should find nothing")))
    }
  }

  private static func request(_ groups: [Genmai_Commands_Request.AdditionalRenderableCharacterGroup])
    -> ConversionRequest
  {
    var request = Genmai_Commands_Request()
    request.additionalRenderableCharacterGroups = groups
    return ConversionRequestBuilder().setRequest(request).build()
  }

  // This test aims to check the ability using EnvironmentalFilterRewriter to
  // filter Emoji.
  @Test func emojiFilterTest() {
    // Emoji after Unicode 12.1 should be all filtered if no additional
    // renderable character group is specified.
    do {
      let segments = Segments()
      let request = ConversionRequest()

      segments.clear()
      Self.addSegment("a", ["🛻", "🤵‍♀", "🥸", "🧑‍🌾", "🧑‍🏭"], segments)

      #expect(rewriter.rewrite(request, segments))
      #expect(segments.conversionSegment(0).candidatesSize == 0)
    }

    // Emoji in Unicode 13.0 should be allowed in this case.
    do {
      let conversionRequest = Self.request([.emoji130])
      let segments = Segments()

      segments.clear()
      Self.addSegment("a", ["🛻", "🤵‍♀", "🥸"], segments)

      #expect(!rewriter.rewrite(conversionRequest, segments))
      #expect(segments.conversionSegment(0).candidatesSize == 3)
    }
  }

  @Test func emojiFilterE160Test() {
    // Emoji 16.0 characters are filtered by default.
    do {
      let segments = Segments()
      let request = ConversionRequest()

      segments.clear()
      Self.addSegment("えもじ", ["🪏", "🫆", "🫟"], segments)

      #expect(rewriter.rewrite(request, segments))
      #expect(segments.conversionSegment(0).candidatesSize == 0)
    }

    // Emoji 16.0 characters are added when they are renderable.
    do {
      let segments = Segments()
      let conversionRequest = Self.request([.emoji160])

      segments.clear()
      Self.addSegment("えもじ", ["🪏", "🫆", "🫟"], segments)

      #expect(!rewriter.rewrite(conversionRequest, segments))
      #expect(segments.conversionSegment(0).candidatesSize == 3)
    }
  }

  @Test func emojiFilterE180Test() {
    // Emoji 18.0 characters are filtered by default.
    do {
      let segments = Segments()
      let request = ConversionRequest()

      segments.clear()
      Self.addSegment("えもじ", ["🛙", "🫌", "🫝"], segments)

      #expect(rewriter.rewrite(request, segments))
      #expect(segments.conversionSegment(0).candidatesSize == 0)
    }

    // Emoji 18.0 characters are added when they are renderable.
    do {
      let segments = Segments()
      let conversionRequest = Self.request([.emoji180])

      segments.clear()
      Self.addSegment("えもじ", ["🛙", "🫌", "🫝"], segments)

      #expect(!rewriter.rewrite(conversionRequest, segments))
      #expect(segments.conversionSegment(0).candidatesSize == 3)
    }
  }

  @Test func removeTest() {
    let segments = Segments()
    let request = ConversionRequest()

    segments.clear()
    Self.addSegment("a", ["a\t1", "a\n2", "a\n\r3"], segments)

    #expect(rewriter.rewrite(request, segments))
    #expect(segments.conversionSegment(0).candidatesSize == 0)
  }

  @Test func noRemoveTest() {
    let segments = Segments()
    Self.addSegment("a", ["aa1", "a.a", "a-a"], segments)

    let request = ConversionRequest()
    #expect(!rewriter.rewrite(request, segments))
    #expect(segments.conversionSegment(0).candidatesSize == 3)
  }

  @Test func candidateFilterTest() {
    let kanaValues = [Self.kKanaSupplement6Dot0, Self.kKanaSupplement10Dot0, Self.kKanaExtendedA14Dot0]
    do {
      let conversionRequest = ConversionRequest()

      let segments = Segments()
      segments.clear()
      // All should not be allowed.
      Self.addSegment("a", kanaValues, segments)

      #expect(rewriter.rewrite(conversionRequest, segments))
      #expect(segments.conversionSegment(0).candidatesSize == 0)
    }

    do {
      let conversionRequest = ConversionRequest()

      let segments = Segments()
      segments.clear()
      // The second candidate that comes from the user dictionary is not
      // filtered.
      Self.addSegment("a", kanaValues, segments)
      #expect(segments.conversionSegment(0).candidatesSize == 3)
      segments.mutableConversionSegment(0).mutableCandidate(1).attributes =
        Attribute.userDictionary

      #expect(rewriter.rewrite(conversionRequest, segments))
      #expect(segments.conversionSegment(0).candidatesSize == 1)
      #expect(segments.conversionSegment(0).candidate(0).value == Self.kKanaSupplement10Dot0)
    }

    do {
      let conversionRequest = Self.request([.empty])

      let segments = Segments()
      segments.clear()
      // All should not be allowed.
      Self.addSegment("a", kanaValues, segments)

      #expect(rewriter.rewrite(conversionRequest, segments))
      #expect(segments.conversionSegment(0).candidatesSize == 0)
    }

    do {
      let conversionRequest = Self.request([.kanaSupplement60])

      let segments = Segments()
      segments.clear()
      // Only first one should be allowed.
      Self.addSegment("a", kanaValues, segments)

      #expect(rewriter.rewrite(conversionRequest, segments))
      #expect(segments.conversionSegment(0).candidatesSize == 1)
    }

    do {
      let conversionRequest = Self.request([
        .kanaSupplement60, .kanaSupplementAndKanaExtendedA100,
      ])

      let segments = Segments()
      segments.clear()
      // First and second one should be allowed.
      Self.addSegment("a", kanaValues, segments)

      #expect(rewriter.rewrite(conversionRequest, segments))
      #expect(segments.conversionSegment(0).candidatesSize == 2)
    }

    do {
      let conversionRequest = Self.request([
        .kanaSupplement60, .kanaSupplementAndKanaExtendedA100, .kanaExtendedA140,
      ])

      let segments = Segments()
      segments.clear()
      // All should be allowed.
      Self.addSegment("a", kanaValues, segments)

      #expect(!rewriter.rewrite(conversionRequest, segments))
      #expect(segments.conversionSegment(0).candidatesSize == 3)
    }
  }

  @Test func normalizationTest() {
    let rewriter = EnvironmentalFilterRewriter(Self.testEmojiRewriterData())
    let segments = Segments()
    let request = ConversionRequest()

    segments.clear()
    Self.addSegment("test", "test", segments)
    #expect(!rewriter.rewrite(request, segments))
    #expect(segments.segment(0).candidate(0).value == "test")

    segments.clear()
    Self.addSegment("きょうと", "京都", segments)
    #expect(!rewriter.rewrite(request, segments))
    #expect(segments.segment(0).candidate(0).value == "京都")

    // Wave dash (U+301C) per platform
    segments.clear()
    Self.addSegment("なみ", "〜", segments)
    let description = "[全]波ダッシュ"
    segments.mutableSegment(0).mutableCandidate(0).description = description
    // Not _WIN32.
    #expect(!rewriter.rewrite(request, segments))
    // U+301C
    #expect(segments.segment(0).candidate(0).value.bytesEqual("\u{301C}"))
    #expect(segments.segment(0).candidate(0).description == description)

    // Wave dash (U+301C) w/ normalization
    segments.clear()
    Self.addSegment("なみ", "〜", segments)
    segments.mutableSegment(0).mutableCandidate(0).description = description

    rewriter.setNormalizationFlag(.kAll)
    #expect(rewriter.rewrite(request, segments))
    // U+FF5E
    #expect(segments.segment(0).candidate(0).value.bytesEqual("\u{FF5E}"))
    #expect(segments.segment(0).candidate(0).description.isEmpty)

    // Wave dash (U+301C) w/o normalization
    segments.clear()
    Self.addSegment("なみ", "〜", segments)
    segments.mutableSegment(0).mutableCandidate(0).description = description

    rewriter.setNormalizationFlag(.kNone)
    #expect(!rewriter.rewrite(request, segments))
    // U+301C
    #expect(segments.segment(0).candidate(0).value.bytesEqual("\u{301C}"))
    #expect(segments.segment(0).candidate(0).description == description)

    // not normalized.
    segments.clear()
    // U+301C
    Self.addSegment("なみ", "〜", segments)
    segments.mutableSegment(0).mutableCandidate(0).attributes |= Attribute.userDictionary
    #expect(!rewriter.rewrite(request, segments))
    // U+301C
    #expect(segments.segment(0).candidate(0).value.bytesEqual("\u{301C}"))

    // not normalized.
    segments.clear()
    // U+301C
    Self.addSegment("なみ", "〜", segments)
    segments.mutableSegment(0).mutableCandidate(0).attributes |= Attribute.noModification
    #expect(!rewriter.rewrite(request, segments))
    // U+301C
    #expect(segments.segment(0).candidate(0).value.bytesEqual("\u{301C}"))
  }
}
