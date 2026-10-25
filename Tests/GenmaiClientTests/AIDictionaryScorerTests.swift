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

/// A user dictionary with one word.
private final class OneWordDictionary: DictionaryInterface {
  let token: Token
  init(_ token: Token) { self.token = token }
  func lookupPrefix(_ key: String, callback: any DictionaryCallback) {
    if key.hasPrefix(token.key) { _ = callback.onToken(token.key, token.key, token) }
  }
  func lookupPrefix(_ key: String, options: ConversionOptions, callback: any DictionaryCallback) {
    lookupPrefix(key, callback: callback)
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

  @Test func bestPath() throws {
    let path = try #require(scorer.bestPath("くさかべちょうにいきました"))
    #expect(path.text == "日下部町に行きました")
    #expect(path.properNouns.map(\.surface).contains("日下部町"))
    #expect(scorer.bestPath("") == nil)
  }

  @Test func proposals() {
    let reading = "くさかべちょうにいきました"
    // the dictionary's text, and the top with the name written for its kana
    #expect(
      scorer.propose(reading: reading, texts: ["クサカベチョウにいきました", "日下部町に行きました"])
        == ["日下部町に行きました", "日下部町にいきました"])
    // the top already has the name: nothing to propose
    #expect(scorer.propose(reading: reading, texts: ["日下部町に行きました"]).isEmpty)
    // no proper noun on the dictionary's path
    #expect(scorer.propose(reading: "きょうはいいてんきですね", texts: ["今日はいい天気ですね"]).isEmpty)
  }

  /// A user dictionary word is proposed like a proper noun, whatever its part of speech.
  @Test func userDictionaryWordsAreProposed() throws {
    let word = Token(
      key: "ぽにょまる", value: "穂仁与丸", cost: 5000, lid: 1851, rid: 1851, attributes: Token.Attribute.userDictionary)
    let scorer = try AIDictionaryScorer(
      dataManager: OssDataManager.create(), userDictionary: OneWordDictionary(word))
    let reading = "ぽにょまるさんがきた"
    let path = try #require(scorer.bestPath(reading))
    #expect(path.text.hasPrefix("穂仁与丸"))
    #expect(path.properNouns.contains { $0.surface == "穂仁与丸" && $0.user })
    #expect(scorer.propose(reading: reading, texts: ["ポニョマルさんが来た"]).contains("穂仁与丸さんが来た"))
    #expect(scorer.cost("穂仁与丸さんが来た", reading: reading) != nil)
    // without it, nothing to propose for this name
    #expect(!self.scorer.propose(reading: reading, texts: ["ポニョマルさんが来た"]).contains("穂仁与丸さんが来た"))
  }

  /// The name is put in for the part of the AI's text that reads as it, kana or other kanji; the rest stays.
  @Test func proposalsKeepTheRestOfTheTop() {
    let proposals = scorer.propose(reading: "にしかんきにいってきました", texts: ["西換気に行って来ました"])
    #expect(proposals.contains("西神吉に行って来ました"))
  }

  /// The words the user committed (the prediction history) are proposed like user dictionary words, until the
  /// history is cleared.
  @Test func learnedWordsAreProposed() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "ai-history-\(UUID())")
    defer { try? FileManager.default.removeItem(at: file) }
    let storage = UserHistoryStorage(file.path)
    await storage.wait()
    var name = UserHistoryStorage.Entry()
    name.key = "ぽにょまる"
    name.value = "穂仁与丸"
    storage.insert(name)
    var kana = UserHistoryStorage.Entry()
    kana.key = "ねこ"
    kana.value = "ねこ"
    storage.insert(kana)
    let learned = AILearnedWords(storage: storage, posID: 1851)
    let scorer = try AIDictionaryScorer(dataManager: OssDataManager.create(), learnedWords: learned)
    let reading = "ぽにょまるさんがきた"
    #expect(scorer.propose(reading: reading, texts: ["ポニョマルさんが来た"]).contains("穂仁与丸さんが来た"))
    #expect(scorer.cost("穂仁与丸さんが来た", reading: reading) != nil)
    storage.clear()
    learned.invalidate()
    #expect(!scorer.propose(reading: reading, texts: ["ポニョマルさんが来た"]).contains("穂仁与丸さんが来た"))
    #expect(scorer.cost("穂仁与丸さんが来た", reading: reading) == nil)
    await storage.wait()
  }

  @Test func proposalsCompeteWhateverTheirKana() {
    let reading = "くさかべちょうにいきました"
    let texts = ["クサカベチョウに行きました", "草壁町に行きました", "日下部町に行きました"]
    // a proposal competes whatever its kana, with its own weight
    let proposals = ["日下部町に行きました"]
    #expect(
      scorer.rerank(texts, scores: [-3, -3.5, -6], reading: reading, weight: 1, proposals: proposals).first
        == "日下部町に行きました")
    #expect(
      scorer.rerank(
        texts, scores: [-3, -3.5, -6], reading: reading, weight: 1, proposals: proposals, proposalWeight: 0
      ).first == "クサカベチョウに行きました")
    // not as an ordinary candidate
    #expect(
      scorer.rerank(texts, scores: [-3, -3.5, -6], reading: reading, weight: 1).first != "日下部町に行きました")
  }
}
