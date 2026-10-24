import Foundation
import GenmaiCore
import Testing

@testable import GenmaiClient

private let sharedScorer: AIDictionaryScorer? = {
  guard FileManager.default.fileExists(atPath: OssDataManager.defaultDataPath) else { return nil }
  return try? AIDictionaryScorer(dataManager: OssDataManager.create())
}()

@Suite struct AIDictionaryScorerSkeletonTests {
  @Test func kanaSkeleton() {
    #expect(AIDictionaryScorer.kanaSkeleton("西神吉に行ってきました。") == "にってきました。")
    #expect(AIDictionaryScorer.kanaSkeleton("晩ご飯") != AIDictionaryScorer.kanaSkeleton("晩ごはん"))
  }
}

@Suite(.enabled(if: sharedScorer != nil, "Data/genmai.data is missing (run Tools/build_data.sh)"))
struct AIDictionaryScorerTests {
  let scorer: AIDictionaryScorer

  init() throws {
    scorer = try #require(sharedScorer)
  }

  @Test func costs() throws {
    // a word of the dictionary is cheaper than an invented spelling of the same reading
    let known = try #require(scorer.cost("日下部町", reading: "くさかべちょう"))
    let invented = try #require(scorer.cost("草壁町", reading: "くさかべちょう"))
    #expect(known < invented)
    #expect(scorer.cost("今日は", reading: "きょうは") != nil)
    #expect(scorer.cost("今日は", reading: "あしたは") == nil)
  }

  @Test func rerank() {
    let reading = "くさかべちょうにいきました"
    let texts = ["草壁町に行きました", "日下部町に行きました", "くさかべ町に行きました"]
    let scores = [-1.0, -1.5, -4.0]
    #expect(scorer.rerank(texts, scores: scores, reading: reading, weight: 0) == texts)
    #expect(scorer.rerank(texts, scores: scores, reading: reading, weight: 1).first == "日下部町に行きました")
    // only texts that differ in kanji compete: the kana spelling keeps its place
    #expect(scorer.rerank(texts, scores: scores, reading: reading, weight: 1).last == "くさかべ町に行きました")
  }
}
