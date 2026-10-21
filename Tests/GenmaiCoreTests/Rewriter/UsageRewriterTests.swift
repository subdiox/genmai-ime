// Port of mozc/src/rewriter/usage_rewriter_test.cc (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiProtocol
import Testing
@testable import GenmaiCore

@Suite(
  .enabled(if: R2RewriterTestSupport.hasMockData, R2RewriterTestSupport.mockDataMissing),
  .scopedConfigEnvironment)
struct UsageRewriterTests {
  /// The C++ fixture (`UsageRewriterTest`). Created inside each test so that
  /// the user dictionary lives in the test's temporary user profile.
  private final class Fixture {
    let request = Genmai_Commands_Request()
    var config = ConfigHandler.defaultConfig()
    let posMatcher: PosMatcher
    let userDictionary: UserDictionary
    let dataManager: MockDataManager

    init() async throws {
      dataManager = try R2RewriterTestSupport.mockDataManager()
      posMatcher = PosMatcher(dataManager.getPosMatcherData())
      let userPosData = dataManager.getUserPosData()
      userDictionary = UserDictionary(
        UserPos(userPosData.tokenArray, userPosData.stringArray), posMatcher)
      await userDictionary.waitForReloader()
    }

    func createUsageRewriter() -> UsageRewriter {
      UsageRewriter(dataManager.getUsageRewriterData(), userDictionary, posMatcher)
    }

    func convReq() -> ConversionRequest {
      ConversionRequestBuilder().setConfig(config).setRequest(request).build()
    }
  }

  private static func addCandidate(
    _ key: String, _ value: String, _ contentKey: String, _ contentValue: String,
    _ segment: Segment
  ) {
    let candidate = segment.addCandidate()
    candidate.key = key
    candidate.value = value
    candidate.contentKey = contentKey
    candidate.contentValue = contentValue
  }

  @Test func capabilityTest() async throws {
    let f = try await Fixture()
    let rewriter = f.createUsageRewriter()
    #expect(rewriter.capability(f.convReq()) == [.conversion, .prediction])
  }

  @Test func conjugationTest() async throws {
    let f = try await Fixture()
    let segments = Segments()
    let rewriter = f.createUsageRewriter()

    segments.clear()
    let seg = segments.pushBackSegment()
    seg.setKey("うたえば")
    Self.addCandidate("うたえば", "歌えば", "うたえ", "歌え", seg)
    Self.addCandidate("うたえば", "唱えば", "うたえ", "唄え", seg)
    #expect(rewriter.rewrite(f.convReq(), segments))
    #expect(segments.conversionSegment(0).candidate(0).usageTitle == "歌う")
    #expect(segments.conversionSegment(0).candidate(0).usageDescription != "")
    #expect(segments.conversionSegment(0).candidate(1).usageTitle == "唄う")
    #expect(segments.conversionSegment(0).candidate(1).usageDescription != "")
  }

  @Test func singleSegmentSingleCandidateTest() async throws {
    let f = try await Fixture()
    let segments = Segments()
    let rewriter = f.createUsageRewriter()
    let convreq = f.convReq()

    segments.clear()
    var seg = segments.pushBackSegment()
    seg.setKey("あおい")
    Self.addCandidate("あおい", "青い", "あおい", "青い", seg)
    #expect(rewriter.rewrite(convreq, segments))
    #expect(segments.conversionSegment(0).candidate(0).usageTitle == "青い")
    #expect(segments.conversionSegment(0).candidate(0).usageDescription != "")

    segments.clear()
    seg = segments.pushBackSegment()
    seg.setKey("あおい")
    Self.addCandidate("あおい", "あああ", "あおい", "あああ", seg)
    #expect(!rewriter.rewrite(convreq, segments))
    #expect(segments.conversionSegment(0).candidate(0).usageTitle == "")
    #expect(segments.conversionSegment(0).candidate(0).usageDescription == "")
  }

  @Test func configTest() async throws {
    let f = try await Fixture()
    let segments = Segments()
    let rewriter = f.createUsageRewriter()

    // Default setting
    do {
      segments.clear()
      let seg = segments.pushBackSegment()
      seg.setKey("あおい")
      Self.addCandidate("あおい", "青い", "あおい", "青い", seg)
      #expect(rewriter.rewrite(f.convReq(), segments))
    }

    do {
      f.config.informationListConfig.useLocalUsageDictionary = false

      segments.clear()
      let seg = segments.pushBackSegment()
      seg.setKey("あおい")
      Self.addCandidate("あおい", "青い", "あおい", "青い", seg)
      #expect(!rewriter.rewrite(f.convReq(), segments))
    }

    do {
      f.config.informationListConfig.useLocalUsageDictionary = true

      segments.clear()
      let seg = segments.pushBackSegment()
      seg.setKey("あおい")
      Self.addCandidate("あおい", "青い", "あおい", "青い", seg)
      #expect(rewriter.rewrite(f.convReq(), segments))
    }
  }

  @Test func singleSegmentMultiCandidatesTest() async throws {
    let f = try await Fixture()
    let segments = Segments()
    let rewriter = f.createUsageRewriter()
    let convreq = f.convReq()

    func setUp(_ values: [String]) {
      segments.clear()
      let seg = segments.pushBackSegment()
      seg.setKey("あおい")
      for value in values {
        Self.addCandidate("あおい", value, "あおい", value, seg)
      }
    }
    func cand(_ i: Int) -> Candidate { segments.conversionSegment(0).candidate(i) }

    setUp(["青い", "蒼い"])
    #expect(rewriter.rewrite(convreq, segments))
    #expect(cand(0).usageTitle == "青い")
    #expect(cand(0).usageDescription != "")
    #expect(cand(1).usageTitle == "蒼い")
    #expect(cand(1).usageDescription != "")

    setUp(["青い", "あああ"])
    #expect(rewriter.rewrite(convreq, segments))
    #expect(cand(0).usageTitle == "青い")
    #expect(cand(0).usageDescription != "")
    #expect(cand(1).usageTitle == "")
    #expect(cand(1).usageDescription == "")

    setUp(["あああ", "青い"])
    #expect(rewriter.rewrite(convreq, segments))
    #expect(cand(0).usageTitle == "")
    #expect(cand(0).usageDescription == "")
    #expect(cand(1).usageTitle == "青い")
    #expect(cand(1).usageDescription != "")

    setUp(["あああ", "いいい"])
    #expect(!rewriter.rewrite(convreq, segments))
    #expect(cand(0).usageTitle == "")
    #expect(cand(0).usageDescription == "")
    #expect(cand(1).usageTitle == "")
    #expect(cand(1).usageDescription == "")
  }

  @Test func multiSegmentsTest() async throws {
    let f = try await Fixture()
    let segments = Segments()
    let rewriter = f.createUsageRewriter()
    let convreq = f.convReq()

    segments.clear()
    var seg = segments.pushBackSegment()
    seg.setKey("あおく")
    Self.addCandidate("あおく", "青く", "あおく", "青く", seg)
    Self.addCandidate("あおく", "蒼く", "あおく", "蒼く", seg)
    Self.addCandidate("あおく", "アオク", "あおく", "アオク", seg)
    seg = segments.pushBackSegment()
    seg.setKey("うたえば")
    Self.addCandidate("うたえば", "歌えば", "うたえ", "歌え", seg)
    Self.addCandidate("うたえば", "唱えば", "うたえ", "唄え", seg)
    #expect(rewriter.rewrite(convreq, segments))
    let s0 = segments.conversionSegment(0)
    let s1 = segments.conversionSegment(1)
    #expect(s0.candidate(0).usageTitle == "青い")
    #expect(s0.candidate(0).usageDescription != "")
    #expect(s0.candidate(1).usageTitle == "蒼い")
    #expect(s0.candidate(1).usageDescription != "")
    #expect(s0.candidate(2).usageTitle == "")
    #expect(s0.candidate(2).usageDescription == "")
    #expect(s1.candidate(0).usageTitle == "歌う")
    #expect(s1.candidate(0).usageDescription != "")
    #expect(s1.candidate(1).usageTitle == "唄う")
    #expect(s1.candidate(1).usageDescription != "")
  }

  @Test func sameUsageTest() async throws {
    let f = try await Fixture()
    let segments = Segments()
    let rewriter = f.createUsageRewriter()
    let convreq = f.convReq()

    let seg = segments.pushBackSegment()
    seg.setKey("うたえば")
    Self.addCandidate("うたえば", "歌えば", "うたえ", "歌え", seg)
    Self.addCandidate("うたえば", "唱えば", "うたえ", "唄え", seg)
    Self.addCandidate("うたえば", "唱エバ", "うたえ", "唄え", seg)
    #expect(rewriter.rewrite(convreq, segments))
    let s0 = segments.conversionSegment(0)
    #expect(s0.candidate(0).usageTitle == "歌う")
    #expect(s0.candidate(0).usageDescription != "")
    #expect(s0.candidate(1).usageTitle == "唄う")
    #expect(s0.candidate(1).usageDescription != "")
    #expect(s0.candidate(2).usageTitle == "唄う")
    #expect(s0.candidate(2).usageDescription != "")
    #expect(s0.candidate(0).usageId != s0.candidate(1).usageId)
    #expect(s0.candidate(1).usageId == s0.candidate(2).usageId)
  }

  @Test func getKanjiPrefixAndOneHiragana() async {
    #expect(UsageRewriter.getKanjiPrefixAndOneHiragana("合わせる") == "合わ")
    #expect(UsageRewriter.getKanjiPrefixAndOneHiragana("合う") == "合う")
    #expect(UsageRewriter.getKanjiPrefixAndOneHiragana("合合わせる") == "合合わ")
    #expect(UsageRewriter.getKanjiPrefixAndOneHiragana("合") == "")
    #expect(UsageRewriter.getKanjiPrefixAndOneHiragana("京都") == "")
    #expect(UsageRewriter.getKanjiPrefixAndOneHiragana("合合合わせる") == "")
    #expect(UsageRewriter.getKanjiPrefixAndOneHiragana("カタカナ") == "")
    #expect(UsageRewriter.getKanjiPrefixAndOneHiragana("abc") == "")
    #expect(UsageRewriter.getKanjiPrefixAndOneHiragana("あ合わせる") == "")
  }

  @Test func commentFromUserDictionary() async throws {
    let f = try await Fixture()
    // Load mock data
    do {
      var storage = Genmai_UserDictionary_UserDictionaryStorage()
      var dic = Genmai_UserDictionary_UserDictionary()

      var entry = Genmai_UserDictionary_UserDictionary.Entry()
      entry.key = "うま"
      entry.value = "アルパカ"
      entry.pos = .noun
      entry.comment = "アルパカコメント"
      dic.entries.append(entry)
      storage.dictionaries.append(dic)

      f.userDictionary.load(storage)
    }

    // Emulates the conversion of key="うま".
    let segments = Segments()
    segments.clear()
    let seg = segments.pushBackSegment()
    seg.setKey("うま")
    Self.addCandidate("うま", "Horse", "うま", "Horse", seg)
    Self.addCandidate("うま", "アルパカ", "うま", "アルパカ", seg)

    let rewriter = f.createUsageRewriter()
    #expect(rewriter.rewrite(f.convReq(), segments))

    // Result of ("うま", "Horse"). No comment is expected.
    let cand0 = segments.conversionSegment(0).candidate(0)
    #expect(cand0.usageTitle.isEmpty)
    #expect(cand0.usageDescription.isEmpty)

    // Result of ("うま", "アルパカ"). Comment from user dictionary is expected.
    let cand1 = segments.conversionSegment(0).candidate(1)
    #expect(cand1.usageTitle == "アルパカ")
    #expect(cand1.usageDescription == "アルパカコメント")
  }
}
