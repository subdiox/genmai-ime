// Port of mozc/src/rewriter/gen_single_kanji_noun_prefix_data.cc (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenSingleKanjiNounPrefixData {
  struct NounPrefix {
    let key: String
    let value: String
    let rank: Int16
  }

  static let kNounPrefixList: [NounPrefix] = [
    .init(key: "お", value: "お", rank: 1),
    .init(key: "ご", value: "ご", rank: 1),
    // {"ご", "誤"},    // don't register it as 誤 isn't in the ipadic.
    // {"み", "み"},    // seems to be rare.
    .init(key: "もと", value: "もと", rank: 1),
    .init(key: "だい", value: "代", rank: 1),
    .init(key: "てい", value: "低", rank: 0),
    .init(key: "もと", value: "元", rank: 1),
    .init(key: "ぜん", value: "全", rank: 0),
    .init(key: "さい", value: "再", rank: 0),
    .init(key: "しょ", value: "初", rank: 1),
    .init(key: "はつ", value: "初", rank: 0),
    .init(key: "ぜん", value: "前", rank: 1),
    .init(key: "かく", value: "各", rank: 1),
    .init(key: "どう", value: "同", rank: 1),
    .init(key: "だい", value: "大", rank: 1),
    .init(key: "おお", value: "大", rank: 1),
    .init(key: "とう", value: "当", rank: 1),
    .init(key: "ご", value: "御", rank: 1),
    .init(key: "お", value: "御", rank: 1),
    .init(key: "しん", value: "新", rank: 1),
    .init(key: "さい", value: "最", rank: 1),
    .init(key: "み", value: "未", rank: 0),
    .init(key: "ほん", value: "本", rank: 1),
    .init(key: "む", value: "無", rank: 0),
    .init(key: "だい", value: "第", rank: 1),
    .init(key: "とう", value: "等", rank: 1),
    .init(key: "やく", value: "約", rank: 1),
    .init(key: "ひ", value: "被", rank: 1),
    .init(key: "ちょう", value: "超", rank: 1),
    .init(key: "ちょう", value: "長", rank: 1),
    .init(key: "なが", value: "長", rank: 1),
    .init(key: "ひ", value: "非", rank: 1),
    .init(key: "こう", value: "高", rank: 1),
  ]

  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    // std::map<std::string, TokenList>; compile() iterates keys bytewise.
    var tokens: [String: SerializedDictionary.TokenList] = [:]
    for entry in kNounPrefixList {
      tokens[entry.key, default: []].append(
        SerializedDictionary.CompilerToken(value: entry.value, lid: 0, rid: 0, cost: entry.rank))
    }
    let (tokenArray, stringArray) = SerializedDictionary.compile(tokens)
    return ["single_kanji_noun_prefix_token": tokenArray, "single_kanji_noun_prefix_string": stringArray]
  }
}
