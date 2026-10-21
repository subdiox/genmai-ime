// Port of mozc/src/composer/char_chunk.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - CharChunk is a value type (struct); the table is shared by reference and
//   compared by identity, as the C++ shared_ptr comparison does.
// - The `local_length_cache_` of the C++ class (an atomic mutated from const
//   methods) is dropped; `getLength` always recomputes. The result is the same
//   because the C++ cache is invalidated on every mutation.
// - absl::btree_set<std::string> is represented by a byte-ordered, unique
//   `[String]`.

import GenmaiBase

// Max recursion count for looking up pending loop.
private let kMaxRecursion = 4

// Get from pending rules recursively
// The recursion will be stopped if recursion_count is 0.
// When returns false, the caller doesn't append result entries.
// If we have the rule,
// '1' -> '', 'あ'
// 'あ1' -> '', 'い'
// 'い1' -> '', 'う'
// 'う1' -> '', 'え'
// 'え1' -> '', 'お'
// 'お1' -> '', 'あ'
// 'あ*' -> '', '{*}ぁ'
// '{*}ぁ' -> '', '{*}あ'
// '{*}あ' -> '', '{*}ぁ'
// 'い*' -> '', '{*}ぃ'
// '{*}ぃ' -> '', '{*}い'
// '{*}い' -> '', '{*}ぃ'
// Here, we want to get '{*}あ' <-> '{*}ぁ' loop from the input, 'あ'
private func getFromPending(
  _ table: Table, _ key: String, _ recursionCount: Int, _ result: inout [String]
) -> Bool {
  if recursionCount == 0 {
    // Don't find the loop within the |recursion_count|.
    return false
  }
  if ComposerBytes.containsSorted(result, key) {
    // Found the entry that is already looked up.
    // Return true because we found the loop.
    return true
  }
  ComposerBytes.insertSorted(&result, key)

  var entries: [Entry] = []
  table.lookUpPredictiveAll(key, &entries)
  for entry in entries {
    if !entry.result.isEmpty {
      // skip rules with result, because this causes too many results.
      // for example, if we have
      //  'k' -> 'っ', 'k'
      //  'ka' -> 'か', ''
      // From the input 'k', this causes 'か', 'っ', 'っか', ...
      // So here we stop calling recursion.
      return false
    }
    if !getFromPending(table, entry.pending, recursionCount - 1, &result) {
      return false
    }
  }
  return true
}

/// This class contains a unit of composition string.  The unit consists of
/// conversion, pending and raw strings.  Every unit should be the shortest
/// size separated by the conversion table.  A sample units with normal
/// romaji-hiragana conversion table are {conversion: "か", pending: "", raw:
/// "ka"} and {conversion: "っ", pending: "t", raw: "tt"}.
public struct CharChunk: Sendable, Equatable, CustomStringConvertible {
  public private(set) var table: Table

  // There are four variables to represent a composing text:
  // `raw_`, `conversion_`, `pending_`, and `ambiguous_`.
  // In general, when the user types a key (e.g. "a"),
  // `raw_` contains the typed character (i.e. "a"), and
  // either or some of `conversion_`, `pending_`, and `ambiguous_` contains
  // converted characters. (e.g. "あ" to `converted_`).
  //
  // At least one of `conversion_`, `pending_`, and `ambiguous_` is not empty.

  /// `raw_`: Actual characters typed by the user (e.g "ka").
  /// In some situations through the user's text editing,
  /// it may contain synthesized data transliterated from `conversion_`.
  public var raw = ""
  /// `conversion_`: Converted character from `raw_` (e.g. "か").
  /// Conversion rules from `raw_` to `conversion_` are described in `table_`.
  public var conversion = ""
  /// `pending_`: Converted character from `raw_`.
  /// Conversion rules from `raw_` to `pending_` are described in `table_`.
  /// If no rules are matched with the input, it is also added to `pending_`.
  /// For example, if `raw_` is "tt", conversion_ is "っ" and pending_ is "t".
  /// This `pending_` is prepended to the user's input in the next time.
  public var pending = ""
  /// `ambiguous_`: Conversted character from `raw_`, but unlike `conversion_`,
  /// it is not yet determined (e.g. "ん").
  /// If the `raw_` is "n", it can be converted to "ん" at this moment.
  /// However it can be converted to "な", if the next input is "a".
  /// In this case, "ん" is stored to `ambiguous_` instead of `conversion_`.
  public var ambiguous = ""
  public private(set) var transliterator: Transliterators.Transliterator
  public var attributes: TableAttributes = .noTableAttribute

  /// LOCAL transliterator is not accepted.
  public init(_ transliterator: Transliterators.Transliterator, _ table: Table) {
    self.table = table
    self.transliterator = transliterator
  }

  /// This constructor is for testing.
  public init(_ transliterator: Transliterators.Transliterator) {
    self.init(transliterator, Table.getSharedDefaultTable())
  }

  public var tableForTesting: Table { table }

  public static func == (lhs: CharChunk, rhs: CharChunk) -> Bool {
    lhs.table === rhs.table && ComposerBytes.equal(lhs.raw, rhs.raw)
      && ComposerBytes.equal(lhs.conversion, rhs.conversion)
      && ComposerBytes.equal(lhs.pending, rhs.pending)
      && ComposerBytes.equal(lhs.ambiguous, rhs.ambiguous)
      && lhs.transliterator == rhs.transliterator && lhs.attributes == rhs.attributes
  }

  public var description: String {
    "table = \(ObjectIdentifier(table)), raw = \(raw), conversion = \(conversion), "
      + "pending = \(pending), ambiguous = \(ambiguous), transliterator = \(transliterator), "
      + "attributes = \(attributes)"
  }

  public mutating func clear() {
    raw = ""
    conversion = ""
    pending = ""
    ambiguous = ""
  }

  public func getLength(_ t12r: Transliterators.Transliterator) -> Int {
    let t13n = transliterate(t12r, deleteSpecialKeys(raw), deleteSpecialKeys(conversion + pending))
    return Util.charsLen(t13n)
  }

  /// Append the characters representing this CharChunk according to the
  /// transliterator.  If the transliterator is LOCAL, the local
  /// transliterator specified via SetTransliterator is used.
  public func appendResult(_ t12r: Transliterators.Transliterator, _ result: inout String) {
    let t13n = transliterate(t12r, deleteSpecialKeys(raw), deleteSpecialKeys(conversion + pending))
    result += t13n
  }

  public func appendTrimedResult(_ t12r: Transliterators.Transliterator, _ result: inout String) {
    // Only determined value (e.g. |conversion_| only) is added.
    var converted = conversion
    if !pending.isEmpty {
      var keyLength = 0
      var fixed = false
      if let entry = table.lookUpPrefix(pending, &keyLength, &fixed),
        ComposerBytes.equal(entry.input, entry.result)
      {
        converted += entry.result
      }
    }
    result += transliterate(t12r, deleteSpecialKeys(raw), deleteSpecialKeys(converted))
  }

  public func appendFixedResult(_ t12r: Transliterators.Transliterator, _ result: inout String) {
    var converted: String
    if !ambiguous.isEmpty {
      // Add the |ambiguous_| value as a fixed value.  |ambiguous_|
      // contains an undetermined result string like "ん" converted
      // from a single 'n'.
      converted = conversion + ambiguous
    } else {
      // If |pending_| exists but |ambiguous_| does not exist,
      // |pending_| is appended.  If |ambiguous_| exists, the value of
      // |pending_| is usually equal to |ambiguous_| so it is not
      // appended.
      converted = conversion + pending
    }
    result += transliterate(t12r, deleteSpecialKeys(raw), deleteSpecialKeys(converted))
  }

  // If we have the rule (roman),
  // 1: 'ka' -> 'か', ''
  // 2: 'ki' -> 'き', ''
  // 3: 'ku' -> 'く', ''
  // 4: 'kk' -> 'っ', 'k'
  // From the input 'k', we want to correct 'k', 'か', 'き', 'く', 'っ'
  // We don't expand for next k for rule 4, because it causes
  // many useless looped results, like 'っか', 'っっか', 'っっ', etc
  //
  // If we have the input 'kk', we will get 'か', 'き', 'く', 'っ' from the
  // pending 'k' of rule 4.
  // With the result of AppendTrimedResult, 'っ', we can get
  // 'っか', 'っき', 'っく', 'っっ' from this input.
  //
  // If we have the rule (kana),
  // 'は゜' -> 'ぱ', ''
  // 'は゛' -> 'ば', ''
  // From the input 'は', we want 'は', 'ば', 'ぱ'
  //
  // For mobile rules,
  // If we have the rule,
  // '1' -> '', 'あ'
  // 'あ1' -> '', 'い'
  // 'い1' -> '', 'う'
  // 'う1' -> '', 'え'
  // 'え1' -> '', 'お'
  // 'お1' -> '', 'あ'
  // 'あ*' -> '', '{*}ぁ'
  // '{*}ぁ' -> '', '{*}あ'
  // '{*}あ' -> '', '{*}ぁ'
  // 'い*' -> '', '{*}ぃ'
  // '{*}ぃ' -> '', '{*}い'
  // '{*}い' -> '', '{*}ぃ'
  // From the input '1', we want 'あ', 'ぁ', not including 'い', 'ぃ', 'う', etc
  //
  // Actually, we don't need to recursive lookup for above two patterns.
  //
  // What we want to append here is the 'looped rule' in |kMaxRecursion| lookup.
  // Here, '{*}ぁ' -> '{*}あ' -> '{*}ぁ' is the loop.
  /// Get possible results from current chunk (a byte-ordered set).
  public func getExpandedResults() -> [String] {
    var results: [String] = []
    if pending.isEmpty {
      return results
    }
    // Append current pending string
    if conversion.isEmpty {
      ComposerBytes.insertSorted(&results, deleteSpecialKeys(pending))
    }
    var entries: [Entry] = []
    table.lookUpPredictiveAll(pending, &entries)
    for entry in entries {
      if !entry.result.isEmpty {
        ComposerBytes.insertSorted(&results, deleteSpecialKeys(entry.result))
      }
      if entry.pending.isEmpty {
        continue
      }
      var loopResult: [String] = []
      if !getFromPending(table, entry.pending, kMaxRecursion, &loopResult) {
        continue
      }
      for result in loopResult {
        ComposerBytes.insertSorted(&results, deleteSpecialKeys(result))
      }
    }
    return results
  }

  public func isFixed() -> Bool { pending.isEmpty }

  /// True if IsAppendable() is true and this object is fixed (|pending_|=="")
  /// when |input| is appended.
  public func isConvertible(
    _ t12r: Transliterators.Transliterator, _ table: Table, _ input: some StringProtocol
  ) -> Bool {
    if !isAppendable(t12r, table) {
      return false
    }

    var keyLength = 0
    var fixed = false
    let key = pending + input
    let entry = table.lookUpPrefix(key, &keyLength, &fixed)

    return entry != nil && (key.utf8.count == keyLength) && fixed
  }

  /// Combines all fields with |left_chunk|.
  /// [this chunk] := [left_chunk]+[this chunk]
  /// Note that after calling this method,
  /// the information contained in |left_chunk| duplicates.
  /// Deleting |left_chunk| would be preferable.
  public mutating func combine(_ leftChunk: CharChunk) {
    conversion = leftChunk.conversion + conversion
    raw = leftChunk.raw + raw
    // TODO(komatsu): This is a hacky way.  We should look up the
    // conversion table with the new |raw_| value.
    if leftChunk.ambiguous.isEmpty {
      ambiguous = ""
    } else {
      if ambiguous.isEmpty {
        ambiguous = leftChunk.ambiguous + pending
      } else {
        ambiguous = leftChunk.ambiguous + ambiguous
      }
    }
    pending = leftChunk.pending + pending
  }

  /// Return true if this char chunk accepts additional characters with
  /// the specified transliterator and the table.
  public func isAppendable(_ t12r: Transliterators.Transliterator, _ table: Table) -> Bool {
    !pending.isEmpty && (t12r == .local || t12r == transliterator) && table === self.table
  }

  /// Splits this CharChunk at |position| and returns the left chunk. Returns
  /// nil on failure (absl::InvalidArgumentError in C++).
  public mutating func splitChunk(_ t12r: Transliterators.Transliterator, _ position: Int)
    -> CharChunk?
  {
    if position <= 0 || position >= getLength(t12r) {
      GenmaiLog.warning("Invalid position: \(position)")
      return nil
    }

    let s = Transliterators.getTransliterator(getTransliterator(t12r))
      .split(position, deleteSpecialKeys(raw), deleteSpecialKeys(conversion + pending))

    var leftNewChunk = CharChunk(transliterator, table)
    leftNewChunk.raw = s.rawLhs
    raw = s.rawRhs

    if s.convertedLhs.utf8.count > conversion.utf8.count {
      // [ conversion | pending ] => [ conv | pend#1 ] [ pend#2 ]
      let pendingLhs = ComposerBytes.substr(s.convertedLhs, conversion.utf8.count)
      leftNewChunk.conversion = conversion
      leftNewChunk.pending = pendingLhs

      conversion = ""
      pending = s.convertedRhs
      ambiguous = ""
    } else {
      // [ conversion | pending ] => [ conv#1 ] [ conv#2 | pending ]
      leftNewChunk.conversion = s.convertedLhs
      // left_new_chunk->set_pending("");
      let pendingPos = s.convertedRhs.utf8.count - pending.utf8.count
      conversion = ComposerBytes.substr(s.convertedRhs, 0, pendingPos)
      // pending_ = pending_;
    }
    return leftNewChunk
  }

  /// Return true if this chunk should be committed immediately.  This
  /// function refers DIRECT_INPUT attribute.
  public func shouldCommit() -> Bool {
    attributes.contains(.directInput) && pending.isEmpty
  }

  public func shouldInsertNewChunk(_ input: CompositionInput) -> Bool {
    if raw.isEmpty && conversion.isEmpty && pending.isEmpty {
      return false
    }

    let isNewInput =
      input.isNewInput || (attributes.contains(.endChunk) && pending.isEmpty)

    if isNewInput && (table.hasNewChunkEntry(input.raw) || !table.hasSubRules(input.raw)) {
      // Such input which is not on the table is treated as NewChunk entry.
      return true
    }
    return false
  }

  /// bool = should loop
  /// Substring = rest of the input
  public mutating func addInputInternal(_ inputArg: Substring) -> (Bool, Substring) {
    let kLoop = true
    let kNoLoop = false
    var input = inputArg

    var usedKeyLength = 0
    var fixed = false
    let key = pending + input
    let entryOpt = table.lookUpPrefix(key, &usedKeyLength, &fixed)

    guard let entry = entryOpt else {
      if usedKeyLength == 0 {
        // If `input` starts with a special key, erases it and keeps the loop.
        // For example, if `input` is "{!}ab{?}", `input` becomes "ab{?}".
        let trimmed = trimLeadingSpecialKey(input)
        if trimmed.utf8.count < input.utf8.count {
          return (kLoop, trimmed)
        }

        // The prefix characters are not contained in the table, fallback
        // operation is performed.
        if pending.isEmpty {
          // Conversion data was not found. Add one character to the chunk.
          let (front, rest) = Strings.frontChar(input)
          raw += front
          conversion += front
          input = rest
        }
        return (kNoLoop, input)
      }

      if usedKeyLength == pending.utf8.count {
        // If the `input` starts with a special key (e.g. "{!}"),
        // and it is not used for this chunk and the next chunk,
        // that special key is removed.
        var usedLength = 0
        var nextFixed = false
        let nextEntry = table.lookUpPrefix(input, &usedLength, &nextFixed)
        let noEntry = (nextEntry == nil && usedLength == 0)
        let trimmed = trimLeadingSpecialKey(input)
        if noEntry && trimmed.utf8.count < input.utf8.count {
          return (kLoop, trimmed)
        }
        return (kNoLoop, input)
      }

      if usedKeyLength < pending.utf8.count {
        // Do not modify this char_chunk, all key characters will be used
        // by the next char_chunk.
        return (kNoLoop, input)
      }

      // Some prefix character is contained in the table, but not
      // reached any conversion result (like "t" with "ta->た").
      // Conversion data had only pending.

      // Move used input characters to CharChunk data.
      let usedInputLength = usedKeyLength - pending.utf8.count
      let usedInputChars = input.byteSubstring(from: 0, length: usedInputLength)
      raw += usedInputChars
      pending += usedInputChars
      ambiguous = ""
      return (kNoLoop, input.byteSubstring(from: usedInputLength))
    }

    // The prefix of key reached a conversion result, thus entry is not nullptr.

    // Check if this CharChunk does not contain a conversion result before.
    let isFirstEntry =
      conversion.isEmpty
      && (raw.isEmpty || pending.isEmpty || ComposerBytes.equal(raw, pending))
    // If this entry is the first entry, the attributes are applied to this chunk.
    if isFirstEntry {
      attributes = entry.attributes
    }

    // Move used input characters to raw_.
    let usedInputLength = usedKeyLength - pending.utf8.count
    raw += input.byteSubstring(from: 0, length: usedInputLength)
    input = input.byteSubstring(from: usedInputLength)

    if fixed || key.utf8.count > usedKeyLength {
      // A result was found. Ambiguity is resolved because `fixed` is true or
      // the key still remains. e.g. If the key is "nk", "n" is used for "ん"
      // because the next remaining character "k" is not used with "n".
      conversion += entry.result
      pending = entry.pending
      ambiguous = ""
    } else {
      // A result was found, but it is still ambiguous.
      // e.g. "n" with "n->ん and na->な".
      pending = key
      ambiguous = entry.result
    }

    // If the lookup is deterministically done (e.g. fixed is true and input is
    // empty) but the output is empty and the raw input is not used (e.g.
    // NO_TRANSLITERATION), raw_ is also cleared to make an empty chunk to be
    // removed by the caller (see: Composition::InsertInput).
    if fixed && input.isEmpty && conversion.isEmpty && pending.isEmpty
      && attributes.contains(.noTransliteration)
    {
      raw = ""
      return (kNoLoop, input)
    }

    if input.isEmpty || pending.isEmpty {
      // If the remaining input character or pending character is empty,
      // there is no reason to continue the looping.
      return (kNoLoop, input)
    }

    return (kLoop, input)
  }

  public mutating func addInput(_ input: inout String) {
    var tmp = input[...]
    var loop = true
    while loop {
      (loop, tmp) = addInputInternal(tmp)
    }
    input = String(tmp)
  }

  private mutating func addInputAndConvertedChar(_ input: inout CompositionInput) {
    if input.isAsis {
      if raw.isEmpty && pending.isEmpty && conversion.isEmpty {
        raw = input.raw
        conversion = input.conversion
        input.clear()
      }
      return
    }

    // If this chunk is empty, the raw and conversion are simply copied.
    if raw.isEmpty && pending.isEmpty && conversion.isEmpty {
      raw = input.raw
      input.clearRaw()
      pending = input.conversion
      // TODO(komatsu): We should check if the `conversion` is
      // really ambiguous or not, otherwise the last character of the
      // preedit on Kana input is always dropped.
      ambiguous = input.conversion
      input.clearConversion()

      // If this entry is the first entry, the table attributes are
      // applied to this chunk.
      if let entry = table.lookUp(pending) {
        attributes = entry.attributes
      }
      return
    }

    let keyInput = pending + input.conversion
    var keyLength = 0
    var fixed = false
    guard let entry = table.lookUpPrefix(keyInput, &keyLength, &fixed) else {
      // Do not modify this char_chunk, all `raw` and `conversion`
      // values of `input` will be used by the next char_chunk.
      return
    }

    // The whole input string was used.
    if keyLength == keyInput.utf8.count {
      raw += input.raw
      if fixed {
        conversion += entry.result
        pending = entry.pending
        ambiguous = ""
      } else {  // !fixed
        // |conversion_| remains the current value.
        pending = entry.result
        ambiguous = entry.result
      }
      input.clearRaw()
      input.clearConversion()
      return
    }

    // The following key_length == pending_.size() means the new `raw` and
    // and `conversion` of `input` does not affect at all.  Do not any thing here
    // and a new char_chunk will be made for `input`.
    if keyLength == pending.utf8.count {
      return
    }

    // The `input` is partially used.
    raw += input.raw
    conversion += entry.result
    pending = entry.pending
    // While the whole `raw` is used in this char_chunk, the
    // `conversion` is separated to this char_chunk and the next
    // char_chunk.  This is not a preferred behavior, but there is no
    // better way to work around this limitation.
    input.clearRaw()
    input.conversion = ComposerBytes.substr(keyInput, keyLength)
  }

  public mutating func addCompositionInput(_ input: inout CompositionInput) {
    if !input.conversion.isEmpty {
      addInputAndConvertedChar(&input)
      return
    }

    if shouldInsertNewChunk(input) {
      return
    }
    addInput(&input.raw)
  }

  public mutating func setTransliterator(_ transliterator: Transliterators.Transliterator) {
    if transliterator == .local {
      // LOCAL transliterator shouldn't be set as local transliterator.
      // Just ignore.
      return
    }
    self.transliterator = transliterator
  }

  /// Gets a transliterator basing on the given |transliterator|.
  /// - If |transliterator| is |Transliterators::LOCAL|, the local transliterator
  ///   is returned. But if NO_TRANSLITERATION attribute is set,
  ///   |Transliterators::CONVERSION_STRING| is returned.
  ///   This behavior is for mobile. Without this behavior, raw string is used
  ///   on unexpected situation. For example, on 12keys-toggle-alphabet mode,
  ///   a user types "2223" to get "cd". In this case local transliterator is
  ///   HALF_ASCII and HALF_ASCII transliterator uses raw string
  ///   so withtout NO_TRANSLITERATION a user will get "2223" as preedit.
  /// - If |transliterator| is not LOCAL, given |transliterator| is returned.
  ///   But if NO_TRANSLITERATION attribute is set and |transliterator| is
  ///   HALF_ASCII or FULL_ASCII, |Transliterators::CONVERSION_STRING|
  ///   is returned.
  ///   NO_TRANSLITERATION means that raw input is (basically) meaningless
  ///   so HALF_ASCII and FULL_ASCII, which uses raw input, should not be used.
  public func getTransliterator(_ transliterator: Transliterators.Transliterator)
    -> Transliterators.Transliterator
  {
    if attributes.contains(.noTransliteration) {
      if transliterator == .local || transliterator == .halfAscii || transliterator == .fullAscii {
        return .conversionString
      }
      return transliterator
    }
    if transliterator == .local {
      return self.transliterator
    }
    return transliterator
  }

  public func transliterate(
    _ transliterator: Transliterators.Transliterator, _ raw: String, _ converted: String
  ) -> String {
    Transliterators.getTransliterator(getTransliterator(transliterator))
      .transliterate(raw, converted)
  }
}
