// Port of mozc/src/converter/candidate_filter.{h,cc} (3.35.6354).
//
// This class is used to filter out generated candidate by its
// cost, structure and relation with previously added candidates.

import GenmaiBase

/// The part of `mozc::SuggestionFilter` (prediction/suggestion_filter.h) that
/// CandidateFilter uses. The prediction port's `SuggestionFilter` conforms to
/// this protocol.
public protocol SuggestionFilterProtocol: Sendable {
  func isBadSuggestion(_ text: String) -> Bool
}

/// `candidate_filter_internal::CandidateId`: ID of the candidate for filtering.
/// Equality and hashing are bytewise on `value` (C++ `std::string`).
public struct CandidateFilterCandidateId: Hashable {
  public let value: String
  public let lid: UInt16
  public let rid: UInt16

  public init(_ candidate: Candidate) {
    value = candidate.value
    lid = candidate.lid
    rid = candidate.rid
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    // Comparing the int values first for performance.
    lhs.lid == rhs.lid && lhs.rid == rhs.rid && lhs.value.bytesEqual(rhs.value)
  }

  public func hash(into hasher: inout Hasher) {
    for byte in value.utf8 {
      hasher.combine(byte)
    }
    hasher.combine(lid)
    hasher.combine(rid)
  }
}

public final class CandidateFilter {
  public enum ResultType: Sendable {
    case goodCandidate  // Can insert the candidate into the list
    case badCandidate  // Do not insert the candidate
    case stopEnumeration  // Do not insert and stop enumurations
  }

  private static let kSizeThresholdForWeakCompound = 10

  private static let kMaxCandidatesSize = 200  // how many candidates we expand

  // Currently, the cost (logprob) is calcurated as cost = -500 * log(prob).
  // Suppose having two candidates A and B and prob(A) = C * prob(B), where
  // C = 1000 (some constant variable). The word "A" appears 1000 times more
  // frequently than B.
  // In this case,
  // cost(B) - cost(A) = -500 * [log(prob(B)) - log (C * prob(B)) ]
  //                   = -500 * [-log(C) + log(prob(B)) - log(prob(B))]
  //                   = 500 * log(C)
  // This implies that it is more reasonable to filter candidates
  // by an absolute difference of costs between cost(B) and cost(A).
  //
  // Here's "C" and cost-diff relation:
  // C       cost diff: 500 * log(C)
  // 10      1151.29
  // 100     2302.58
  // 1000    3453.87
  // 10000   4605.17
  // 100000  5756.46
  // 1000000 6907.75
  private static let kMinCost = 100
  private static let kCostOffset = 6907
  private static let kStructureCostOffset = 3453
  private static let kMinStructureCostOffset = 1151
  private static let kStopEnumerationCacheSize = 30

  private static let kIntMax = Int(Int32.max)

  private let userDictionary: any UserDictionaryInterface
  private let posMatcher: PosMatcher
  private let suggestionFilter: any SuggestionFilterProtocol
  // cache the result of HasSuppressedEntries, because calling
  // IsSuppressedEntry() has some latency because of mutex lock even when
  // the entry is empty.
  private let hasSuppressedEntries: Bool

  private var seen: Set<CandidateFilterCandidateId> = []
  private var topCandidate: Candidate? = nil

  public init(
    _ userDictionary: any UserDictionaryInterface, _ posMatcher: PosMatcher,
    _ suggestionFilter: any SuggestionFilterProtocol
  ) {
    self.userDictionary = userDictionary
    self.posMatcher = posMatcher
    self.suggestionFilter = suggestionFilter
    self.hasSuppressedEntries = userDictionary.hasSuppressedEntries()
  }

  /// Resets the internal state.
  public func reset() {
    seen.removeAll()
    topCandidate = nil
  }

  /// Checks if the candidate should be filtered out.
  ///
  /// topNodes: Node vector for the top candidate for the segment.
  /// nodes: Node vector for the target candidate
  public func filterCandidate(
    _ options: ConversionOptions, _ originalKey: some StringProtocol, _ candidate: Candidate,
    _ topNodes: [Node], _ nodes: [Node]
  ) -> ResultType {
    if options.requestType == .reverseConversion {
      // In reverse conversion, only remove duplicates because the filtering
      // criteria of FilterCandidateInternal() are completely designed for
      // (forward) conversion.
      let inserted = seen.insert(CandidateFilterCandidateId(candidate)).inserted
      return inserted ? .goodCandidate : .badCandidate
    } else {
      let result = filterCandidateInternal(options, originalKey, candidate, topNodes, nodes)
      if result != .goodCandidate {
        return result
      }
      seen.insert(CandidateFilterCandidateId(candidate))
      return result
    }
  }

  private func checkRequestType(
    _ options: ConversionOptions, _ originalKey: some StringProtocol, _ candidate: Candidate,
    _ nodes: [Node]
  ) -> ResultType {
    // Filtering by the suggestion filter, which is applied only for the
    // PREDICTION and SUGGESTION modes.
    var applySuggestionFilter = false
    switch options.requestType {
    case .prediction:
      // - For Mobile
      // (To be precise, in mixed_conversion mode;
      //  Mobile IME with physical keyboard can set mixed_conversion=false and
      //  act similar to the Desktop version)
      // Most users do not trigger conversion explicitly.
      // So we don't apply the suggestion filter when the input key is
      // exactly the same as candidate's.
      //
      // Note:
      // SUGGESTION command is not called when mixed_conversion=true

      // - For Desktop
      // In the PREDICTION mode, the suggestion filter is not applied and the
      // same filtering rule as the CONVERSION mode is used because the
      // PREDICTION is triggered by user action (hitting tab keys), i.e.,
      // prediction candidates are not automatically shown to users. On the
      // contrary, since a user hit tab keys to run prediction, even unfavorable
      // words might be what the user wants to type.  Therefore, filtering rule
      // is relaxed for the PREDICTION mode: we don't apply the suggestion
      // filter if the user input key is exactly the same as candidate's.
      applySuggestionFilter = !originalKey.bytesEqual(candidate.key)  // [[fallthrough]]
    case .suggestion:
      // - For Desktop
      // In contrast to the PREDICTION mode, the SUGGESTION is triggered without
      // any user actions, i.e., suggestion candidates are automatically
      // displayed to users.  Therefore, it's better to filter unfavorable words
      // in this mode.
      applySuggestionFilter = true
    default:
      break
    }
    if applySuggestionFilter {
      if suggestionFilter.isBadSuggestion(candidate.value) {
        candidate.dlog("IsBadsuggestion(candidate)")
        return .badCandidate
      }
      // TODO(noriyukit): In the implementation below, the possibility remains
      // that multiple nodes constitute bad candidates. For stronger filtering,
      // we may want to check all the possibilities.
      for node in nodes {
        if suggestionFilter.isBadSuggestion(node.value) {
          candidate.dlog("IsBadsuggestion(node)")
          return .badCandidate
        }
      }
    }
    return .goodCandidate
  }

  private func filterCandidateInternal(
    _ options: ConversionOptions, _ originalKey: some StringProtocol, _ candidate: Candidate,
    _ topNodes: [Node], _ nodes: [Node]
  ) -> ResultType {
    let result = checkRequestType(options, originalKey, candidate, nodes)
    if result != .goodCandidate {
      return result
    }

    // In general, the cost of constrained node tends to be overestimated.
    // If the top candidate has constrained node, we skip the main body
    // of CandidateFilter, meaning that the node is not treated as the top
    // node for CandidateFilter.
    if candidate.attributes & Attribute.contextSensitive != 0 {
      return .goodCandidate
    }

    if RequestUtil.shouldFilterNoisyNumberCandidate(options) {
      if Self.isNoisyNumberCandidate(posMatcher, nodes) {
        return .badCandidate
      }
    }

    let candidateSize = seen.count
    let topCandidate: Candidate
    if let current = self.topCandidate, candidateSize != 0 {
      topCandidate = current
    } else {
      topCandidate = candidate
      self.topCandidate = candidate
    }

    // "短縮よみ" or "記号,一般" must have only 1 node.  Note that "顔文字" POS
    // from user dictionary is converted to "記号,一般" in Mozc engine.
    if nodes.count > 1 && Self.containsIsolatedWordOrGeneralSymbol(posMatcher, nodes) {
      candidate.dlog("ContainsIsolatedWordOrGeneralSymbol")
      return .badCandidate
    }
    // This case tests the case where the isolated word or general symbol is in
    // content word.
    if Self.isIsolatedWordOrGeneralSymbol(posMatcher, nodes[0].lid)
      && (Self.isNormalOrConstrainedNode(nodes[0].prev) || Self.isNormalOrConstrainedNode(nodes[0].next))
    {
      candidate.dlog("IsIsolatedWordOrGeneralSymbol")
      return .badCandidate
    }

    // Remove "抑制単語" just in case.
    if hasSuppressedEntries
      && (userDictionary.isSuppressedEntry(candidate.key, candidate.value)
        || (!candidate.key.bytesEqual(candidate.contentKey)
          && !candidate.value.bytesEqual(candidate.contentValue)
          && userDictionary.isSuppressedEntry(candidate.contentKey, candidate.contentValue)))
    {
      candidate.dlog("SuppressEntry")
      return .badCandidate
    }

    // Don't remove duplications if USER_DICTIONARY.
    if candidate.attributes & Attribute.userDictionary != 0 {
      return .goodCandidate
    }

    // too many candidates size
    if candidateSize + 1 >= Self.kMaxCandidatesSize {
      return .stopEnumeration
    }

    // The candidate is already seen.
    if seen.contains(CandidateFilterCandidateId(candidate)) {
      candidate.dlog("already seen")
      return .badCandidate
    }

    precondition(!nodes.isEmpty)

    // Suppress "書います", "書いすぎ", "買いて"
    // Basic idea:
    //  - WagyoRenyoConnectionVerb(= "動詞,*,*,*,五段・ワ行促音便,連用形",
    // "買い", "言い", "使い", etc) should not connect to TeSuffix(= "て",
    // "てる", "ちゃう", "とく", etc).
    //  - KagyoTaConnectionVerb(= 動詞,*,*,*,五段・カ行(促|イ)音便,連用タ接続",
    // "書い", "歩い", "言っ", etc) should not connect to verb suffix other
    // than TeSuffix
    if Util.getScriptType(nodes[0].value) != .hiragana {
      if nodes.count >= 2 {
        // For node sequence
        if posMatcher.isKagyoTaConnectionVerb(nodes[0].rid) && posMatcher.isVerbSuffix(nodes[1].lid)
          && !posMatcher.isTeSuffix(nodes[1].lid)
        {
          // "書い" | "ます", "過ぎ", etc
          candidate.dlog("IsKagyoTaConnectionVerb")
          return .badCandidate
        }
        if posMatcher.isWagyoRenyoConnectionVerb(nodes[0].rid) && posMatcher.isTeSuffix(nodes[1].lid) {
          // "買い" | "て"
          candidate.dlog("IsWagyoRenyoConnectionVerb")
          return .badCandidate
        }
      }
      if nodes[0].lid != nodes[0].rid {
        // For compound
        if posMatcher.isKagyoTaConnectionVerb(nodes[0].lid) && posMatcher.isVerbSuffix(nodes[0].rid)
          && !posMatcher.isTeSuffix(nodes[0].rid)
        {
          // "書い" | "ます", "過ぎ", etc
          candidate.dlog("IsKagyoTaConnectionVerb")
          return .badCandidate
        }
        if posMatcher.isWagyoRenyoConnectionVerb(nodes[0].lid) && posMatcher.isTeSuffix(nodes[0].rid) {
          // "買い" | "て"
          candidate.dlog("IsWagyoRenyoConnectionVerb")
          return .badCandidate
        }
      }
    }

    // The candidate consists of only one token
    if nodes.count == 1 {
      return .goodCandidate
    }

    // don't drop single character
    if Util.charsLen(candidate.value) == 1 {
      return .goodCandidate
    }

    // Remove noisy candidates from prefix.
    // For example, "お危機します" for "おききします".
    //
    // Basic idea:
    //   "weak compound": words consist from "prefix + content"
    //   "connected weak compound": noun prefix("名詞接続") + noun words("体言")
    //      or verb prefix("動詞接続") + verb words("用言")
    //   "noisy weak compound": types of prefix and content do not match.
    //   - We do not allow noisy weak compound except for the top result. Even for
    //     the top result, we will check other conditions for filtering.
    //   - We do not allow connected weak compound if the rank is low enough.
    let isNoisyWeakCompound = Self.isNoisyWeakCompound(nodes, posMatcher, candidate)
    let isConnectedWeakCompound = Self.isConnectedWeakCompound(nodes, posMatcher, candidate)

    if isNoisyWeakCompound && candidateSize >= 1 {
      candidate.dlog("is_noisy_weak_compound")
      return .badCandidate
    }

    if isConnectedWeakCompound && candidateSize >= Self.kSizeThresholdForWeakCompound {
      candidate.dlog("is_connected_weak_compound")
      return .badCandidate
    }

    // don't drop lid/rid are the same as those
    // of top candidate.
    // http://b/issue?id=4285213
    if !isNoisyWeakCompound && topCandidate.structureCost == 0 && candidate.lid == topCandidate.lid
      && candidate.rid == topCandidate.rid
    {
      return .goodCandidate
    }

    // "好かっ|たり" vs  "良かっ|たり" have same non_content_value.
    // "良かっ|たり" is also a good candidate but it is not the top candidate.
    // non_content_value ("たり") should be Hiragana.
    // Background:
    // 名詞,接尾 nodes ("済み", "損", etc) can also be non_content_value.
    let topNonContentValue = topCandidate.value.byteSubstring(from: topCandidate.contentValue.utf8.count)
    let nonContentValue = candidate.value.byteSubstring(from: candidate.contentValue.utf8.count)
    if !isNoisyWeakCompound && topCandidate !== candidate
      && !topCandidate.contentValue.bytesEqual(topCandidate.value)
      && Util.getScriptType(topNonContentValue) == .hiragana
      && topNonContentValue.bytesEqual(nonContentValue)
    {
      return .goodCandidate
    }

    // Check Katakana transliterations
    // Skip this check when the conversion mode is real-time;
    // otherwise this ruins the whole sentence
    // that starts with alphabets.
    if candidate.attributes & Attribute.realtimeConversion == 0 {
      let isTopEnglishT13n =
        Util.getScriptType(nodes[0].key) == .hiragana && Util.isEnglishTransliteration(nodes[0].value)
      for i in 1..<nodes.count {
        // EnglishT13N must be the prefix of the candidate.
        if Util.getScriptType(nodes[i].key) == .hiragana && Util.isEnglishTransliteration(nodes[i].value) {
          candidate.dlog("IsEnglishTransliteration")
          return .badCandidate
        }
        // nodes[1..] are non-functional candidates.
        // In other words, the node just after KatakanaT13n candidate should
        // be a functional word.
        if isTopEnglishT13n && !posMatcher.isFunctional(nodes[i].lid) {
          candidate.dlog("!IsFunctional")
          return .badCandidate
        }
      }
    }

    let topCost = max(Self.kMinCost, Int(topCandidate.cost))
    let topStructureCost = max(Self.kMinCost, Int(topCandidate.structureCost))

    // If candidate size < 3, don't filter candidate aggressively
    // TODO(taku): This is a tentative workaround for the case where
    // TOP candidate is compound and the structure cost for it is "0"
    // If 2nd or 3rd candidates are regular candidate but not having
    // non-zero cost, they might be removed. This hack removes such case.
    if Self.isCompoundCandidate(topNodes) && candidateSize < 3 && Int(candidate.cost) < topCost + 2302
      && candidate.structureCost < 6907
    {
      return .goodCandidate
    }

    // Don't drop personal names aggressively.
    // We have to show personal names even if they are too minor.
    // We basically ignores the cost threadshould. Filter candidate
    // only by structure cost.
    var costOffset = Self.kCostOffset
    if candidate.lid == posMatcher.getLastNameId() || candidate.lid == posMatcher.getFirstNameId() {
      costOffset = Self.kIntMax - topCost
    }

    // Filters out candidates with higher cost.
    if topCost + costOffset < Int(candidate.cost)
      && topStructureCost + Self.kMinStructureCostOffset < Int(candidate.structureCost)
    {
      // Stops candidates enumeration when we see sufficiently high cost
      // candidate.
      if candidateSize < Self.kStopEnumerationCacheSize {
        // Even when the current candidate is classified as bad candidate,
        // we don't return STOP_ENUMERATION here.
        // When the current candidate is removed only with the "structure_cost",
        // there might exist valid candidates just after the current candidate.
        // We don't want to miss them.
        candidate.dlog("invalid cost")
        return .badCandidate
      } else {
        return .stopEnumeration
      }
    }

    // Filters out candidates with higher cost structure.
    if topStructureCost + Self.kStructureCostOffset > Self.kIntMax
      || max(topStructureCost, Self.kMinStructureCostOffset) + Self.kStructureCostOffset
        < Int(candidate.structureCost)
    {
      // We don't stop enumeration here. Just drops high cost structure
      // looks enough.
      // |top_structure_cost| can be so small especially for compound or
      // web dictionary entries.
      // For avoiding over filtering, we use kMinStructureCostOffset if
      // |top_structure_cost| is small.
      candidate.dlog("structure cost is invalid")
      return .badCandidate
    }

    // Filters multiple number nodes.
    // "2|十三重"
    // "4|重|5|号室"
    // Note that we do not want to filter
    // "1|0|円"
    // "5|万" for the key, "5まん"
    if nodes.count >= 2 {
      var numberNodes = 0
      var prevLid: UInt16 = 0
      for node in nodes {
        if Util.isScriptType(node.key, .number) {
          continue
        }
        let value = node.value
        var mblen = 0
        let firstValueScriptType = Util.getFirstScriptType(value, &mblen)
        if firstValueScriptType == .number && prevLid != node.lid {
          numberNodes += 1
        } else if firstValueScriptType == .kanji {
          let firstKanji = value.byteSubstring(from: 0, length: mblen)
          let converted = NumberUtil.kanjiNumberToArabicNumber(firstKanji)
          if !firstKanji.bytesEqual(converted) && prevLid != node.lid {
            numberNodes += 1
          }
        }
        prevLid = node.lid
      }
      if numberNodes >= 2 {
        candidate.dlog("multile number node")
        return .badCandidate
      }
    }
    return .goodCandidate
  }

  // MARK: - Helpers

  /// Returns true if the given node sequence is noisy weak compound.
  /// Please refer to the comment in FilterCandidateInternal for the idea.
  private static func isNoisyWeakCompound(_ nodes: [Node], _ posMatcher: PosMatcher, _ candidate: Candidate)
    -> Bool
  {
    if nodes.count <= 1 {
      return false
    }
    if nodes[0].lid != nodes[0].rid {
      // nodes[0] is COMPOUND entry in dictionary.
      return false
    }
    if posMatcher.isWeakCompoundFillerPrefix(nodes[0].lid) {
      // Word that starts with 'filler' is always noisy.
      candidate.dlog("Noise: Word that starts with 'filler'")
      return true
    }
    if nodes[1].lid != nodes[1].rid {
      // If the second node is a compound word (i.e. lid != rid),
      // it is basically filtered.
      // However, the second node is an anti_phrase word (e.g. とともに),
      // the node is not filtered. Since there is no direct way
      // to determine the anti_phrase word, we use the following heuristic.
      let isPossibleAntiPhraseConnection =
        posMatcher.isContentNoun(nodes[0].rid) && posMatcher.isAcceptableParticleAtBeginOfSegment(nodes[1].lid)
      if !isPossibleAntiPhraseConnection {
        // Some node +  COMPOUND node may be noisy.
        candidate.dlog("Noise: Some node + COMPOUND node")
        return true
      }
    }
    if posMatcher.isWeakCompoundNounPrefix(nodes[0].lid) && !posMatcher.isWeakCompoundNounSuffix(nodes[1].lid) {
      // Noun prefix + not noun
      candidate.dlog("Noise: Noun prefix + not noun")
      return true
    }
    if posMatcher.isWeakCompoundVerbPrefix(nodes[0].lid) && !posMatcher.isWeakCompoundVerbSuffix(nodes[1].lid) {
      // Verb prefix + not verb
      candidate.dlog("Noise: Verb prefix + not verb")
      return true
    }
    return false
  }

  /// Returns true if the given node sequence is connected weak compound.
  /// Please refer to the comment in FilterCandidateInternal for the idea.
  private static func isConnectedWeakCompound(
    _ nodes: [Node], _ posMatcher: PosMatcher, _ candidate: Candidate
  ) -> Bool {
    if nodes.count <= 1 {
      return false
    }
    if nodes[0].lid != nodes[0].rid || nodes[1].lid != nodes[1].rid {
      // nodes[0/1] is COMPOUND entry in dictionary.
      return false
    }
    if posMatcher.isWeakCompoundNounPrefix(nodes[0].lid) && posMatcher.isWeakCompoundNounSuffix(nodes[1].lid) {
      // Noun prefix + noun
      candidate.dlog("Connected: Noun prefix + noun")
      return true
    }
    if posMatcher.isWeakCompoundVerbPrefix(nodes[0].lid) && posMatcher.isWeakCompoundVerbSuffix(nodes[1].lid) {
      // Verb prefix + verb
      candidate.dlog("Connected: Verb prefix + verb")
      return true
    }
    return false
  }

  private static func isIsolatedWordOrGeneralSymbol(_ posMatcher: PosMatcher, _ posId: UInt16) -> Bool {
    posMatcher.isIsolatedWord(posId) || posMatcher.isGeneralSymbol(posId)
  }

  private static func containsIsolatedWordOrGeneralSymbol(_ posMatcher: PosMatcher, _ nodes: [Node]) -> Bool {
    for node in nodes {
      if isIsolatedWordOrGeneralSymbol(posMatcher, node.lid) {
        return true
      }
    }
    return false
  }

  private static func isNormalOrConstrainedNode(_ node: Node?) -> Bool {
    guard let node else { return false }
    return node.nodeType == .norNode || node.nodeType == .conNode
  }

  private static func isCompoundCandidate(_ nodes: [Node]) -> Bool {
    nodes.count == 1 && nodes[0].lid != nodes[0].rid
  }

  /// Returns true if there is a number node that does not follow the
  private static func isNoisyNumberCandidate(_ posMatcher: PosMatcher, _ nodes: [Node]) -> Bool {
    func isConvertedNumber(_ node: Node) -> Bool {
      if node.lid != node.rid {
        return false
      }
      if !Util.isScriptType(node.key, .hiragana) {
        return false
      }
      return posMatcher.isNumber(node.lid) || posMatcher.isKanjiNumber(node.rid)
    }
    for i in 0..<nodes.count {
      if !isConvertedNumber(nodes[i]) {
        continue
      }
      if i + 1 < nodes.count && !isConvertedNumber(nodes[i + 1])
        && !posMatcher.isCounterSuffixWord(nodes[i + 1].lid)
      {
        // "にいく": "2行く"
        return true
      }
      if i - 1 >= 0 && posMatcher.isUniqueNoun(nodes[i - 1].rid) {
        // "しんじゅくに": "新宿2"
        return true
      }
    }
    return false
  }
}
