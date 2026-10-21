// Port of mozc/src/rewriter/ivs_variants_rewriter.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - The `absl::flat_hash_map` keyed by (content_key, content_value) is a
//   Swift `Dictionary` keyed by the UTF-8 bytes of both strings, so that the
//   lookup is bytewise like the C++ one (Swift `String` equality is
//   canonical-equivalence based).

import GenmaiBase

private struct IvsExpansionKey: Hashable {
  let reading: [UInt8]
  let baseSurface: [UInt8]
}

private struct ExpansionValue {
  let ivsSurface: String
  let additionalDescription: String
}

// {"reading", "base surface"}, {"IVS surface", "additional description"}},
private let kIvsExpansionEntries: [((String, String), (String, String))] = [
  (("かつらぎし", "葛城市"), ("葛\u{E0100}城市", "正式字体")),
  (("ぎおん", "祇園"), ("祇\u{E0100}園", "礻")),
  (("つじのぞみ", "辻希美"), ("辻\u{E0100}希美", "「辻󠄀」")),
  (("つじもときよみ", "辻元清美"), ("辻\u{E0100}元清美", "「辻󠄀」")),
  (("つじよしなり", "辻よしなり"), ("辻\u{E0100}よしなり", "「辻󠄀」")),
  (("つじしんぱち", "辻親八"), ("辻\u{E0100}新八", "「辻󠄀」")),
  (("つじもとけんと", "辻本賢人"), ("辻\u{E0100}本賢人", "「辻󠄀」")),
  (("つじあゆみ", "辻あゆみ"), ("辻\u{E0100}あゆみ", "「辻󠄀」")),
  (("つじかおり", "辻香緒里"), ("辻\u{E0100}香緒里", "「辻󠄀」")),
  (("つじかおり", "辻香織"), ("辻\u{E0100}香織", "「辻󠄀」")),
  (("つじもとたつのり", "辻本達規"), ("辻\u{E0100}本達規", "「辻󠄀」")),
  (("つじもととおり", "辻本通"), ("辻\u{E0100}本通", "「辻󠄀」")),
  (("つじしんご", "辻慎吾"), ("辻\u{E0100}慎吾", "「辻󠄀」")),
  (("つじせいめい", "辻清明"), ("辻\u{E0100}清明", "「辻󠄀」")),
  (("つじなかゆたか", "辻中豊"), ("辻\u{E0100}中豊", "「辻󠄀」")),
  (("つじもとともひこ", "辻本知彦"), ("辻\u{E0100}本知彦", "「辻󠄀」")),
  (("つじいのぶゆき", "辻井伸行"), ("辻\u{E0100}井伸行", "「辻󠄀」")),
  (("さかきいちろう", "榊一郎"), ("榊\u{E0100}一郎", "「榊󠄀」")),
  (("さかきばらいくえ", "榊原郁恵"), ("榊\u{E0100}原郁恵", "「榊󠄀」")),
  (("さかきひでお", "榊英雄"), ("榊\u{E0100}英雄", "「榊󠄀」")),
  (("さかきひろゆき", "榊裕之"), ("榊\u{E0100}裕之", "「榊󠄀」")),
  (("さかきよしゆき", "榊佳之"), ("榊\u{E0100}佳之", "「榊󠄀」")),
  (("さかきばらまさくに", "榊原政邦"), ("榊\u{E0100}原政邦", "「榊󠄀」")),
  (("さかきいずみ", "榊いずみ"), ("榊\u{E0100}いずみ", "「榊󠄀」")),
  (("さかきりょうざぶろう", "榊亮三郎"), ("榊\u{E0100}亮三郎", "「榊󠄀」")),
  (("さかきばらなおこ", "榊原菜緒子"), ("榊\u{E0100}原菜緒子", "「榊󠄀」")),
  (("きりもとたくや", "桐本琢也"), ("桐本琢\u{E0100}也", "「琢󠄀」")),
  (("ふるたちいちろう", "古舘伊知郎"), ("古舘\u{E0101}伊知郎", "正式字体")),
  (("ひろたこうき", "廣田弘毅"), ("廣\u{E0101}田弘毅", "「廣󠄁」")),
  (("こばやしけん", "小林劍"), ("小林劍\u{E0101}", "「劍」")),
  (("きりやまれん", "桐山漣"), ("桐山漣\u{E0101}", "「漣󠄁」")),
  (("しばりょうたろう", "司馬遼太郎"), ("司馬遼\u{E0101}太郎", "正式字体")),
  (("ほうらいだいすけ", "蓬莱大輔"), ("蓬\u{E0100}莱大輔", "「蓬󠄀」")),
  (("かまどねずこ", "竈門禰豆子"), ("竈門禰\u{E0100}豆子", "正式字体")),
  (("きぶつじむざん", "鬼舞辻無惨"), ("鬼舞辻\u{E0100}無惨", "正式字体")),
  (("れんごくきょうじゅろう", "煉獄杏寿郎"), ("煉\u{E0101}獄杏寿郎", "正式字体")),
  (("れんごくるか", "煉獄瑠火"), ("煉\u{E0101}獄瑠火", "正式字体")),
  (("れんごくしんじゅろう", "煉獄槇寿郎"), ("煉\u{E0101}獄槇寿郎", "正式字体")),
  (("れんごくせんじゅろう", "煉獄千寿郎"), ("煉\u{E0101}獄千寿郎", "正式字体")),
  (("れんごく", "煉獄"), ("煉\u{E0101}獄", "「煉󠄁」")),
  (("ねずこ", "禰豆子"), ("禰\u{E0100}豆子", "正式字体")),
  (("みそ", "味噌"), ("味噌\u{E0100}", "「噌󠄀」")),
  (("きぶつじ", "鬼舞辻"), ("鬼舞辻\u{E0100}", "「辻󠄀」")),
  (("つじ", "辻"), ("辻\u{E0100}", "一点しんにょう")),
  (("つじもと", "辻本"), ("辻\u{E0100}本", "一点しんにょう")),
  (("つじもと", "辻元"), ("辻\u{E0100}元", "一点しんにょう")),
  (("つじなか", "辻中"), ("辻\u{E0100}中", "一点しんにょう")),
  (("つじい", "辻井"), ("辻\u{E0100}井", "一点しんにょう")),
  (("さかき", "榊"), ("榊\u{E0100}", "")),
  (("さかきばら", "榊原"), ("榊\u{E0100}原", "「榊」")),
]

private let kIvsExpansionTable: [IvsExpansionKey: ExpansionValue] = {
  var table: [IvsExpansionKey: ExpansionValue] = [:]
  for ((reading, base), (ivs, description)) in kIvsExpansionEntries {
    table[IvsExpansionKey(reading: Array(reading.utf8), baseSurface: Array(base.utf8))] =
      ExpansionValue(ivsSurface: ivs, additionalDescription: description)
  }
  return table
}()

private let kIvsVariantDescription = "環境依存(IVS)"

private func expandIvsVariantsWithSegment(_ seg: Segment) -> Bool {
  var modified = false
  var i = seg.candidatesSize - 1
  while i >= 0 {
    defer { i -= 1 }
    let originalCandidate = seg.candidate(i)
    guard
      let value = kIvsExpansionTable[
        IvsExpansionKey(
          reading: Array(originalCandidate.contentKey.utf8),
          baseSurface: Array(originalCandidate.contentValue.utf8))]
    else {
      continue
    }
    modified = true

    let newCandidate = originalCandidate.copy()
    // "は" for "葛城市は"
    let nonContentValue = originalCandidate.value.byteSubstring(
      from: originalCandidate.contentValue.utf8.count)
    newCandidate.value = value.ivsSurface + nonContentValue
    newCandidate.contentValue = value.ivsSurface
    newCandidate.description =
      value.additionalDescription.isEmpty
      ? kIvsVariantDescription
      : kIvsVariantDescription + " " + value.additionalDescription
    seg.insertCandidate(i + 1, newCandidate)
  }
  return modified
}

public final class IvsVariantsRewriter: RewriterInterface {
  public init() {}

  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType {
    .all
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    var modified = false
    for segment in segments.conversionSegments {
      modified = expandIvsVariantsWithSegment(segment) || modified
    }
    return modified
  }
}
