// Generated Swift equivalent of mozc/src/dictionary/pos_cost_map.inc
// (3.35.6354), which dictionary/gen_pos_cost_map.py produces from
// data/rules/user_pos.def. Regenerate from the repository root with:
//
//   python3 - <<'PY'
//   import sys
//   sys.path.insert(0, 'Vendor/mozc/src')
//   from dictionary import gen_pos_cost_map as g
//   for i, (pos, enum_value, cost) in enumerate(g.ParseUserPos('Vendor/mozc/src/data/rules/user_pos.def')):
//     print('  ("%s", %s),  // %s = %d' % (pos, cost, enum_value, i))
//   PY

/// `kPosTypeStringTable`: (POS name, cost) indexed by
/// `Genmai_UserDictionary_UserDictionary.PosType.rawValue`.
let kPosTypeStringTable: [(String, UInt16)] = [
  ("品詞なし", 2500),  // NO_POS = 0
  ("名詞", 2500),  // NOUN = 1
  ("短縮よみ", 200),  // ABBREVIATION = 2
  ("サジェストのみ", 2500),  // SUGGESTION_ONLY = 3
  ("固有名詞", 1500),  // PROPER_NOUN = 4
  ("人名", 1500),  // PERSONAL_NAME = 5
  ("姓", 2500),  // FAMILY_NAME = 6
  ("名", 2500),  // FIRST_NAME = 7
  ("組織", 2000),  // ORGANIZATION_NAME = 8
  ("地名", 2000),  // PLACE_NAME = 9
  ("名詞サ変", 2500),  // SA_IRREGULAR_CONJUGATION_NOUN = 10
  ("名詞形動", 1500),  // ADJECTIVE_VERBAL_NOUN = 11
  ("数", 1000),  // NUMBER = 12
  ("アルファベット", 2500),  // ALPHABET = 13
  ("記号", 2000),  // SYMBOL = 14
  ("顔文字", 2000),  // EMOTICON = 15
  ("副詞", 1500),  // ADVERB = 16
  ("連体詞", 1000),  // PRENOUN_ADJECTIVAL = 17
  ("接続詞", 1000),  // CONJUNCTION = 18
  ("感動詞", 1000),  // INTERJECTION = 19
  ("接頭語", 1500),  // PREFIX = 20
  ("助数詞", 1000),  // COUNTER_SUFFIX = 21
  ("接尾一般", 1500),  // GENERIC_SUFFIX = 22
  ("接尾人名", 1000),  // PERSON_NAME_SUFFIX = 23
  ("接尾地名", 1000),  // PLACE_NAME_SUFFIX = 24
  ("動詞ワ行五段", 0),  // WA_GROUP1_VERB = 25
  ("動詞カ行五段", 0),  // KA_GROUP1_VERB = 26
  ("動詞サ行五段", 0),  // SA_GROUP1_VERB = 27
  ("動詞タ行五段", 0),  // TA_GROUP1_VERB = 28
  ("動詞ナ行五段", 0),  // NA_GROUP1_VERB = 29
  ("動詞マ行五段", 0),  // MA_GROUP1_VERB = 30
  ("動詞ラ行五段", 0),  // RA_GROUP1_VERB = 31
  ("動詞ガ行五段", 0),  // GA_GROUP1_VERB = 32
  ("動詞バ行五段", 0),  // BA_GROUP1_VERB = 33
  ("動詞ハ行四段", 0),  // HA_GROUP1_VERB = 34
  ("動詞一段", 0),  // GROUP2_VERB = 35
  ("動詞カ変", 0),  // KURU_GROUP3_VERB = 36
  ("動詞サ変", 0),  // SURU_GROUP3_VERB = 37
  ("動詞ザ変", 0),  // ZURU_GROUP3_VERB = 38
  ("動詞ラ変", 0),  // RU_GROUP3_VERB = 39
  ("形容詞", 0),  // ADJECTIVE = 40
  ("終助詞", 100),  // SENTENCE_ENDING_PARTICLE = 41
  ("句読点", 500),  // PUNCTUATION = 42
  ("独立語", 2000),  // FREE_STANDING_WORD = 43
  ("抑制単語", 1000),  // SUPPRESSION_WORD = 44
]
