// Port of mozc/src/dictionary/pos_matcher.h (3.35.6354), including the
// pos_matcher_impl.inc that dictionary/gen_pos_matcher_code.py generates from
// data/rules/pos_matcher_rule.def.
//
// The rule methods between "BEGIN GENERATED" and "END GENERATED" were produced
// by running the following script from the repository root (it uses the same
// pos_util.PosMatcher as gen_pos_matcher_code.py, so the rule order is the
// order of the generated C++ header):
//
//   python3 - <<'PY'
//   import sys
//   sys.path.insert(0, 'Vendor/mozc/src')
//   from dictionary import pos_util
//   m = pos_util.PosMatcher(pos_util.PosDataBase())
//   m.Parse('Vendor/mozc/src/data/rules/pos_matcher_rule.def')
//   names = m.GetRuleNameList()
//   for i, n in enumerate(names):
//     print('  // %s "%s"' % (n, m.GetOriginalPattern(n)))
//     print('  @inline(__always) public func get%sId() -> UInt16 { data[%d] }' % (n, i))
//     print('  @inline(__always) public func is%s(_ id: UInt16) -> Bool { isRuleInTable(%d, id) }' % (n, i))
//   print()
//   print('  static let kLidTableSize = %d' % len(names))
//   PY

/// `mozc::dictionary::PosMatcher`.
///
/// The PosMatcher has two methods for each POS matching rule:
///
/// - getXXXId(): returns the POS ID for XXX.
/// - isXXX(_ id: UInt16): checks if the given POS ID is XXX or not.
///
/// where XXX is replaced by rule names; see data/rules/pos_matcher_rule.def.
///
/// PosMatcher is a view of a table managed by DataManager
/// (`DataManager.getPosMatcherData()`), so pass it by value.
///
/// Binary format
///
/// Suppose there are N matching rules.  Then, the first 2*N bytes is the array
/// of uint16_t that contains the results for GetXXXId() methods.  The next N
/// uint16_t values are the offsets (in uint16_t units) of the range tables.
/// Each range table contains the ranges of POS IDs for each IsXXX(uint16_t id)
/// method as (start, end) pairs (IsXXX should return true if id is in one of
/// the ranges), terminated by a sentinel element 0xFFFF.
public struct PosMatcher: Sendable {
  private let data: DataSpan<UInt16>

  public init(_ data: DataSpan<UInt16>) {
    self.data = data
  }

  // Used by the generated methods.
  @inline(__always)
  private func isRuleInTable(_ index: Int, _ id: UInt16) -> Bool {
    // kLidTableSize is defined in the generated part.
    var ptr = Int(data[PosMatcher.kLidTableSize + index])
    while data[ptr] != 0xFFFF {
      if id >= data[ptr] && id <= data[ptr + 1] {
        return true
      }
      ptr += 2
    }
    return false
  }

  // BEGIN GENERATED
  // Functional "^(助詞|助動詞|動詞,非自立|名詞,非自立|形容詞,非自立|動詞,接尾|名詞,接尾|形容詞,接尾)"
  @inline(__always) public func getFunctionalId() -> UInt16 { data[0] }
  @inline(__always) public func isFunctional(_ id: UInt16) -> Bool { isRuleInTable(0, id) }
  // Unknown "名詞,サ変接続"
  @inline(__always) public func getUnknownId() -> UInt16 { data[1] }
  @inline(__always) public func isUnknown(_ id: UInt16) -> Bool { isRuleInTable(1, id) }
  // FirstName "名詞,固有名詞,人名,名"
  @inline(__always) public func getFirstNameId() -> UInt16 { data[2] }
  @inline(__always) public func isFirstName(_ id: UInt16) -> Bool { isRuleInTable(2, id) }
  // LastName "名詞,固有名詞,人名,姓"
  @inline(__always) public func getLastNameId() -> UInt16 { data[3] }
  @inline(__always) public func isLastName(_ id: UInt16) -> Bool { isRuleInTable(3, id) }
  // Number "名詞,数,アラビア数字"
  @inline(__always) public func getNumberId() -> UInt16 { data[4] }
  @inline(__always) public func isNumber(_ id: UInt16) -> Bool { isRuleInTable(4, id) }
  // KanjiNumber "名詞,数,漢数字"
  @inline(__always) public func getKanjiNumberId() -> UInt16 { data[5] }
  @inline(__always) public func isKanjiNumber(_ id: UInt16) -> Bool { isRuleInTable(5, id) }
  // WeakCompoundNounPrefix "接頭詞,名詞接続,"
  @inline(__always) public func getWeakCompoundNounPrefixId() -> UInt16 { data[6] }
  @inline(__always) public func isWeakCompoundNounPrefix(_ id: UInt16) -> Bool { isRuleInTable(6, id) }
  // WeakCompoundVerbPrefix "接頭詞,動詞接続,"
  @inline(__always) public func getWeakCompoundVerbPrefixId() -> UInt16 { data[7] }
  @inline(__always) public func isWeakCompoundVerbPrefix(_ id: UInt16) -> Bool { isRuleInTable(7, id) }
  // WeakCompoundFillerPrefix "フィラー,"
  @inline(__always) public func getWeakCompoundFillerPrefixId() -> UInt16 { data[8] }
  @inline(__always) public func isWeakCompoundFillerPrefix(_ id: UInt16) -> Bool { isRuleInTable(8, id) }
  // WeakCompoundNounSuffix "^名詞,(サ変接続|ナイ形容詞語幹|一般|副詞可能|形容詞語幹)"
  @inline(__always) public func getWeakCompoundNounSuffixId() -> UInt16 { data[9] }
  @inline(__always) public func isWeakCompoundNounSuffix(_ id: UInt16) -> Bool { isRuleInTable(9, id) }
  // WeakCompoundVerbSuffix "動詞,自立"
  @inline(__always) public func getWeakCompoundVerbSuffixId() -> UInt16 { data[10] }
  @inline(__always) public func isWeakCompoundVerbSuffix(_ id: UInt16) -> Bool { isRuleInTable(10, id) }
  // AcceptableParticleAtBeginOfSegment "^助詞,*,*,*,*,*,(が|で|と|に|にて|の|へ|より|も|と|から|は|や)$"
  @inline(__always) public func getAcceptableParticleAtBeginOfSegmentId() -> UInt16 { data[11] }
  @inline(__always) public func isAcceptableParticleAtBeginOfSegment(_ id: UInt16) -> Bool { isRuleInTable(11, id) }
  // JapanesePunctuations "記号,(句点|読点)"
  @inline(__always) public func getJapanesePunctuationsId() -> UInt16 { data[12] }
  @inline(__always) public func isJapanesePunctuations(_ id: UInt16) -> Bool { isRuleInTable(12, id) }
  // OpenBracket "記号,括弧開"
  @inline(__always) public func getOpenBracketId() -> UInt16 { data[13] }
  @inline(__always) public func isOpenBracket(_ id: UInt16) -> Bool { isRuleInTable(13, id) }
  // CloseBracket "記号,括弧閉"
  @inline(__always) public func getCloseBracketId() -> UInt16 { data[14] }
  @inline(__always) public func isCloseBracket(_ id: UInt16) -> Bool { isRuleInTable(14, id) }
  // GeneralSymbol "記号,一般,"
  @inline(__always) public func getGeneralSymbolId() -> UInt16 { data[15] }
  @inline(__always) public func isGeneralSymbol(_ id: UInt16) -> Bool { isRuleInTable(15, id) }
  // Zipcode "特殊,郵便番号"
  @inline(__always) public func getZipcodeId() -> UInt16 { data[16] }
  @inline(__always) public func isZipcode(_ id: UInt16) -> Bool { isRuleInTable(16, id) }
  // IsolatedWord "特殊,短縮よみ"
  @inline(__always) public func getIsolatedWordId() -> UInt16 { data[17] }
  @inline(__always) public func isIsolatedWord(_ id: UInt16) -> Bool { isRuleInTable(17, id) }
  // SuggestOnlyWord "特殊,サジェストのみ"
  @inline(__always) public func getSuggestOnlyWordId() -> UInt16 { data[18] }
  @inline(__always) public func isSuggestOnlyWord(_ id: UInt16) -> Bool { isRuleInTable(18, id) }
  // ContentWordWithConjugation "^(動詞,自立,*,*,五段|動詞,自立,*,*,一段|形容詞,自立)"
  @inline(__always) public func getContentWordWithConjugationId() -> UInt16 { data[19] }
  @inline(__always) public func isContentWordWithConjugation(_ id: UInt16) -> Bool { isRuleInTable(19, id) }
  // SuffixWord "^(助詞|助動詞|動詞,非自立|動詞,接尾|形容詞,非自立|形容詞,接尾|動詞,自立,*,*,サ変・スル)"
  @inline(__always) public func getSuffixWordId() -> UInt16 { data[20] }
  @inline(__always) public func isSuffixWord(_ id: UInt16) -> Bool { isRuleInTable(20, id) }
  // CounterSuffixWord "名詞,接尾,助数詞"
  @inline(__always) public func getCounterSuffixWordId() -> UInt16 { data[21] }
  @inline(__always) public func isCounterSuffixWord(_ id: UInt16) -> Bool { isRuleInTable(21, id) }
  // UniqueNoun "^名詞,固有名詞"
  @inline(__always) public func getUniqueNounId() -> UInt16 { data[22] }
  @inline(__always) public func isUniqueNoun(_ id: UInt16) -> Bool { isRuleInTable(22, id) }
  // GeneralNoun "^名詞,一般,*,*,*,*,*$"
  @inline(__always) public func getGeneralNounId() -> UInt16 { data[23] }
  @inline(__always) public func isGeneralNoun(_ id: UInt16) -> Bool { isRuleInTable(23, id) }
  // Pronoun "^名詞,代名詞,"
  @inline(__always) public func getPronounId() -> UInt16 { data[24] }
  @inline(__always) public func isPronoun(_ id: UInt16) -> Bool { isRuleInTable(24, id) }
  // ContentNoun "^名詞,(一般|固有名詞|副詞可能|サ変接続),"
  @inline(__always) public func getContentNounId() -> UInt16 { data[25] }
  @inline(__always) public func isContentNoun(_ id: UInt16) -> Bool { isRuleInTable(25, id) }
  // NounPrefix "^接頭詞,名詞接続,"
  @inline(__always) public func getNounPrefixId() -> UInt16 { data[26] }
  @inline(__always) public func isNounPrefix(_ id: UInt16) -> Bool { isRuleInTable(26, id) }
  // EOSSymbol "^(記号,(句点|読点|アルファベット|一般|括弧開|括弧閉))|^(名詞,数,(アラビア数字|区切り文字))"
  @inline(__always) public func getEOSSymbolId() -> UInt16 { data[27] }
  @inline(__always) public func isEOSSymbol(_ id: UInt16) -> Bool { isRuleInTable(27, id) }
  // Adverb "^副詞,"
  @inline(__always) public func getAdverbId() -> UInt16 { data[28] }
  @inline(__always) public func isAdverb(_ id: UInt16) -> Bool { isRuleInTable(28, id) }
  // AdverbSegmentSuffix "^助詞,*,*,*,*,*,(から|で|と|に|にて|の|へ|を)$"
  @inline(__always) public func getAdverbSegmentSuffixId() -> UInt16 { data[29] }
  @inline(__always) public func isAdverbSegmentSuffix(_ id: UInt16) -> Bool { isRuleInTable(29, id) }
  // ParallelMarker "^助詞,並立助詞"
  @inline(__always) public func getParallelMarkerId() -> UInt16 { data[30] }
  @inline(__always) public func isParallelMarker(_ id: UInt16) -> Bool { isRuleInTable(30, id) }
  // TeSuffix "(助詞,接続助詞,*,*,*,*,(て|ちゃ)|助詞,並立助詞,*,*,*,*,たり|助詞,終助詞,*,*,*,*,てん|助動詞,*,*,*,特殊・タ,|動詞,非自立,*,*,一段,*,てる|助動詞,*,*,*,下二・タ行,連用形,つ|動詞,非自立,*,*,五段・カ行イ音便,*,とく|動詞,非自立,*,*,五段・カ行促音便,*,てく|動詞,非自立,*,*,五段・ラ行,*,(たる|とる)|動詞,非自立,*,*,五段・ワ行促音便,*,(ちゃう|ちまう)|動詞,非自立,*,*,一段,連用形,てる)"
  @inline(__always) public func getTeSuffixId() -> UInt16 { data[31] }
  @inline(__always) public func isTeSuffix(_ id: UInt16) -> Bool { isRuleInTable(31, id) }
  // VerbSuffix "(^動詞,非自立|^助詞,接続助詞|^助動詞)"
  @inline(__always) public func getVerbSuffixId() -> UInt16 { data[32] }
  @inline(__always) public func isVerbSuffix(_ id: UInt16) -> Bool { isRuleInTable(32, id) }
  // KagyoTaConnectionVerb "^動詞,(非自立|自立),*,*,五段・カ行(促音便|イ音便),連用タ接続"
  @inline(__always) public func getKagyoTaConnectionVerbId() -> UInt16 { data[33] }
  @inline(__always) public func isKagyoTaConnectionVerb(_ id: UInt16) -> Bool { isRuleInTable(33, id) }
  // WagyoRenyoConnectionVerb "^動詞,(非自立|自立),*,*,五段・ワ行促音便,連用形"
  @inline(__always) public func getWagyoRenyoConnectionVerbId() -> UInt16 { data[34] }
  @inline(__always) public func isWagyoRenyoConnectionVerb(_ id: UInt16) -> Bool { isRuleInTable(34, id) }

  static let kLidTableSize = 35
  // END GENERATED
}
