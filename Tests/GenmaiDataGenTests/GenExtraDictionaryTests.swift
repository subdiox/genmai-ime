// Tests of the extended data set's extra dictionary (not part of Mozc).

import Foundation
import Testing

@testable import GenmaiDataGen

@Suite struct GenExtraDictionaryTests {
  @Test func addresses() {
    for s in ["静岡県磐田市", "紫波郡紫波町", "札幌市中央区", "磯子区杉田", "川俣町上桜", "北海道札幌"] {
      #expect(GenExtraDictionary.isAddress(s), "\(s)")
    }
    for s in ["磐田市", "比布町", "本町通", "北七条西", "旭ケ丘", "日下部町"] {
      #expect(!GenExtraDictionary.isAddress(s), "\(s)")
    }
  }

  @Test func townNames() {
    #expect(GenExtraDictionary.townName("以下に掲載がない場合", reading: "ｲｶﾆｹｲｻｲｶﾞﾅｲﾊﾞｱｲ") == nil)
    #expect(GenExtraDictionary.townName("大通東", reading: "ｵｵﾄﾞｵﾘﾋｶﾞｼ")?.surface == "大通東")
    let t = GenExtraDictionary.townName("大通西（１～１９丁目）", reading: "ｵｵﾄﾞｵﾘﾆｼ(1-19ﾁｮｳﾒ)")
    #expect(t?.surface == "大通西" && t?.reading == "ｵｵﾄﾞｵﾘﾆｼ")
    #expect(GenExtraDictionary.townName("赤坂、青山", reading: "ｱｶｻｶ､ｱｵﾔﾏ") == nil)
  }

  @Test func entries() {
    let e = GenExtraDictionary.entry(surface: "日下部町", reading: "ｸｻｶﾍﾞﾁｮｳ", posName: GenExtraDictionary.placeName)
    #expect(e?.reading == "くさかべちょう" && e?.surface == "日下部町")
    // kana only, ASCII, digits, an address
    #expect(GenExtraDictionary.entry(surface: "あいう", reading: "アイウ", posName: GenExtraDictionary.properNoun) == nil)
    #expect(
      GenExtraDictionary.entry(surface: "JR線", reading: "ジェイアールセン", posName: GenExtraDictionary.properNoun) == nil)
    #expect(GenExtraDictionary.entry(surface: "第3区", reading: "ダイサンク", posName: GenExtraDictionary.properNoun) == nil)
    #expect(
      GenExtraDictionary.entry(surface: "磐田市見付", reading: "イワタシミツケ", posName: GenExtraDictionary.placeName)
        == nil)
  }

  @Test func csvFields() {
    #expect(GenExtraDictionary.csvFields("a,b,,c") == ["a", "b", "", "c"])
    #expect(GenExtraDictionary.csvFields(#""a,b",c,"d""e""#) == ["a,b", "c", #"d"e"#])
  }

  @Test func generate() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "extra-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let idDef = dir.appending(path: "id.def")
    try "1920 名詞,固有名詞,一般,*,*,*,*\n1924 名詞,固有名詞,地域,一般,*,*,*\n".write(to: idDef, atomically: true, encoding: .utf8)
    let base = dir.appending(path: "dictionary00.txt")
    try "ひだか\t1924\t1924\t6000\t日高\nあ\t1924\t1924\t7000\t亜\n".write(to: base, atomically: true, encoding: .utf8)
    let sudachi = dir.appending(path: "core_lex.csv")
    try """
    日高,1,1,100,日高,名詞,固有名詞,地名,一般,*,*,ヒダカ,日高,*,A,*,*,*,*
    日下部町,1,1,100,日下部町,名詞,固有名詞,地名,一般,*,*,クサカベチョウ,日下部町,*,A,*,*,*,*
    山田,1,1,100,山田,名詞,固有名詞,人名,姓,*,*,ヤマダ,山田,*,A,*,*,*,*
    走る,1,1,100,走る,動詞,一般,*,*,五段-ラ行,終止形-一般,ハシル,走る,*,A,*,*,*,*

    """.write(to: sudachi, atomically: true, encoding: .utf8)
    let text = try GenExtraDictionary.generate(
      idDef: idDef.path, baseDictionaries: [base.path], kenAll: nil, sudachiSmall: nil, sudachiCore: sudachi.path)
    // 日高 is in the base dictionary; person names come from small_lex only; the cost is the base's 90th
    // percentile for the id
    #expect(text == "くさかべちょう\t1924\t1924\t7000\t日下部町\n")
  }
}
