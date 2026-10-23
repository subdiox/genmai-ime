import Foundation
import GenmaiCore
import Testing

@testable import GenmaiClient

/// One checker for all tests (building the reverse lookup index takes a moment).
private let sharedChecker: AIReadingChecker? = {
  guard FileManager.default.fileExists(atPath: OssDataManager.defaultDataPath) else { return nil }
  return try? AIReadingChecker(dataManager: OssDataManager.create())
}()

@Suite struct AIReadingCheckerFoldTests {
  @Test func fold() {
    func f(_ s: String) -> String { String(String.UnicodeScalarView(AIReadingChecker.fold(s))) }
    #expect(f("ガッコウ") == "かつこう")
    #expect(f("さんぼん") == "さんほん")
    #expect(f("コーヒー〜～") == "こひ")
    #expect(f("ヴァイオリン") == "うあいおりん")
    #expect(f("１２ＡＢ　ｃ") == "12ABc")
    #expect(f("ぱぴぷぺぽ") == "はひふへほ")
  }
}

@Suite(.enabled(if: sharedChecker != nil, "Data/genmai.data is missing (run Tools/build_data.sh)"))
struct AIReadingCheckerTests {
  let checker: AIReadingChecker

  init() throws {
    checker = try #require(sharedChecker)
  }

  /// The cases of the reference implementation (genmai experiments/reading_check.py).
  static let cases: [(text: String, reading: String, readable: Bool)] = [
    ("母は歯が痛いらしい", "ははははがいたいらしい", true),
    ("母は歯痒いらしい", "ははははがいたいらしい", false),
    // the reading matches; the wrong meaning is not caught by this check
    ("ハハハハが痛いらしい", "ははははがいたいらしい", true),
    // one にわ is missing
    ("庭には鶏がいる", "にわにはにわにわとりがいる", false),
    ("3時に2階の会議室で", "3じに2かいのかいぎしつで", true),
    ("三本の矢", "さんぼんのや", true),
    ("コーヒーを飲む", "こーひーをのむ", true),
    ("日本の首都", "にっぽんのしゅと", true),
    ("東京に行く", "とうきょうにいく", true),
    ("彼らが闇の仕置人であると見当をつけた", "かれらがやみのしおきじんであるとけんとうをつけた", true),
    ("ぜひ御社の歓送迎会でも", "ぜひおんしゃのかんそうげいかいでも", true),
    ("週末に鶴岡八幡宮とか回ってきた", "しゅうまつにつるがおかはちまんぐうとかまわってきた", true),
    ("１日に会議は何回必要か。", "いちにちにかいぎはなんかいひつようか。", true),
    ("ていたが1991年に大改修を施し", "ていたがせんきゅうひゃくきゅうじゅういちねんにだいかいしゅうをほどこし", true),
    ("診査付けんを出し", "しんさつけんをだした", false),
    ("肩を持んでもらった", "かたをもんでもらった", false),
  ]

  @Test(arguments: cases.indices)
  func readable(_ i: Int) {
    let c = Self.cases[i]
    #expect(checker.isReadable(c.text, reading: c.reading) == c.readable, "\(c.text) / \(c.reading)")
  }

  @Test func moreReadings() {
    #expect(checker.isReadable("溢れ落ちる", reading: "こぼれおちる"))
    #expect(checker.isReadable("１日", reading: "ついたち"))
    #expect(checker.isReadable("MI6の", reading: "えむあいしっくすの"))
    #expect(checker.isReadable("5cmの", reading: "5せんちの"))
    #expect(checker.isReadable("今日は早めに帰ります", reading: "きょうははやめにかえります"))
    #expect(!checker.isReadable("今日は早めに帰ります", reading: "きょうははやめにかえりました"))
  }

  @Test func filterKeepsOrderAndTheFirstWhenNothingIsReadable() {
    let r = "ははははがいたいらしい"
    #expect(
      checker.filter(["母は歯が痛いらしい", "母は歯痒いらしい", "ハハハハが痛いらしい"], reading: r)
        == ["母は歯が痛いらしい", "ハハハハが痛いらしい"])
    #expect(checker.filter(["全然違う", "まったく別"], reading: r) == ["全然違う"])
  }

  /// The check runs on the main thread at the conversion key: it must stay well below a millisecond per candidate.
  @Test func speed() {
    let start = ContinuousClock.now
    var n = 0
    for _ in 0..<5 {
      for c in Self.cases {
        _ = checker.isReadable(c.text, reading: c.reading)
        n += 1
      }
    }
    let perCandidate = (ContinuousClock.now - start) / n
    print("reading check: \(perCandidate) per candidate")
    // Release: ~0.2 ms (M4 Pro). The test runs in parallel with the other suites, ~10x slower on the CI runner
    // (debug: ~15 ms there; debug builds are ~8x slower), so the bounds only catch gross regressions.
    #if DEBUG
      #expect(perCandidate < .milliseconds(50))
    #else
      #expect(perCandidate < .milliseconds(5))
    #endif
  }
}
