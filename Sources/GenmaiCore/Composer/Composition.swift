// Port of mozc/src/composer/composition.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - `CharChunkList` (std::list<CharChunk>) is a Swift array and list
//   iterators are array indices (`chunks.count` == end()). Index bookkeeping
//   after insertions / erasures is done explicitly where C++ relies on list
//   iterator stability.
// - absl::btree_set<std::string> is a byte-ordered, unique `[String]`.

import GenmaiBase

public typealias CharChunkList = [CharChunk]

public enum TrimMode: Int, Sendable {
  case trim  // "かn" => "か"
  case asis  // "かn" => "かn"
  case fix  // "かn" => "かん"
}

public struct Composition: Sendable, Equatable, CustomStringConvertible {
  public private(set) var table: Table?
  public private(set) var chunks: CharChunkList = []
  public private(set) var inputT12r: Transliterators.Transliterator = .conversionString

  public init() {}

  public init(_ table: Table) {
    self.table = table
  }

  public static func == (lhs: Composition, rhs: Composition) -> Bool {
    lhs.table === rhs.table && lhs.chunks == rhs.chunks && lhs.inputT12r == rhs.inputT12r
  }

  public var description: String {
    let t = table.map { "\(ObjectIdentifier($0))" } ?? "nil"
    return "table = \(t), input transliterator = \(inputT12r), chunks = ["
      + chunks.map { $0.description }.joined(separator: ", ") + "]"
  }

  public var tableForTesting: Table? { table }

  public func getCharChunkList() -> CharChunkList { chunks }

  /// Mutable access to the chunks (C++ tests mutate chunks through the
  /// iterators returned by GetChunkAt()).
  public var mutableChunks: CharChunkList {
    get { chunks }
    set { chunks = newValue }
  }

  /// Clear all chunks.
  public mutating func erase() { chunks.removeAll() }

  public mutating func insertAt(_ pos: Int, _ input: String) -> Int {
    var compositionInput = CompositionInput()
    compositionInput.raw = input
    return insertInput(pos, compositionInput)
  }

  public mutating func insertKeyAndPreeditAt(_ pos: Int, _ key: String, _ preedit: String) -> Int {
    var compositionInput = CompositionInput()
    compositionInput.raw = key
    compositionInput.conversion = preedit
    return insertInput(pos, compositionInput)
  }

  /// Insert the given |input| to the composition at the given |position|
  /// and return the new position.
  public mutating func insertInput(_ pos: Int, _ inputArg: CompositionInput) -> Int {
    var input = inputArg
    if input.isEmpty {
      return pos
    }

    var rightChunk = maybeSplitChunkAt(pos)
    while rightChunk != chunks.count && chunks[rightChunk].getLength(inputT12r) == 0 {
      rightChunk += 1
    }

    var leftChunk = getInsertionChunk(rightChunk)
    if leftChunk == rightChunk {
      // A new chunk was inserted before |rightChunk|.
      rightChunk += 1
    }

    let removed = combinePendingChunks(leftChunk, input)
    leftChunk -= removed
    rightChunk -= removed

    while true {
      chunks[leftChunk].addCompositionInput(&input)
      if input.isEmpty {
        break
      }
      leftChunk = insertChunk(rightChunk)
      rightChunk += 1
      input.isNewInput = false
    }

    // If the chunk is empty as the result of AddCompositionInput above, removes
    // the empty chunk.
    if chunks[leftChunk].raw.isEmpty && chunks[leftChunk].conversion.isEmpty
      && chunks[leftChunk].pending.isEmpty
    {
      chunks.remove(at: leftChunk)
      if leftChunk < rightChunk {
        rightChunk -= 1
      }
    }

    return getPosition(.local, rightChunk)
  }

  /// Deletes a right-hand character of the composition at the position.
  /// e.g.
  /// "012".DeleteAt(0) -> "12"
  /// "{0}12".DeleteAt(0) -> "2"  // {0} is an invisible character.
  ///
  /// Correctly speaking, DeleteAt removes char-chunks ranged between
  /// * the left-point where the length is `position`
  /// * the right-point where the length is `position + 1`
  ///
  /// If the char-chunks are ["a", "b", "c"], DeleteAt(1) removes "b" because
  /// the range of length 1 and 2 is ["a", < "b" >, "c"].
  /// If the char-chunks are ["a", "bc", "d"], DeleteAt(1) removes "b" too.
  /// The char-chunks are split if necessary first (e.g.["a", "b", "c", "d"]).
  /// Then it becomes ["a", < "b" > , "c", "d"].
  ///
  /// The same thing is applied to invisible characters.
  /// If the char-chunks are ["a", "{b}", "c", "d"],
  /// DeleteAt(1) removes both "{b}" and "c",
  /// because the range is ["a", < "{b}", "c", > "d"],
  ///
  /// Note, if the last removed char-chunk has trailing invisible characters,
  /// they are also removed.
  /// If the char-chunks are ["a", "{b}", "c{d}", "e"],
  /// DeleteAt(1) removes both "{b}" and "c{d}".
  ///
  /// Examples:
  ///   ["a", "{b}c", "d"].DeleteAt(0) -> ["{b}c", "d"]
  ///   ["a", "{b}c", "d"].DeleteAt(1) -> ["a", "d"]
  ///   ["a{b}", "c", "d"].DeleteAt(0) -> ["c", "d"]
  ///   ["a{b}", "c", "d"].DeleteAt(1) -> ["a{b}", "d"]
  ///   ["a", "{b}", "c"].DeleteAt(0) -> ["{b}, "c"]
  ///   ["a", "{b}", "c"].DeleteAt(1) -> ["a"]
  @discardableResult
  public mutating func deleteAt(_ position: Int) -> Int {
    let originalSize = getLength()
    var newPosition = position
    // We have to perform deletion repeatedly because there might be 0-length
    // chunk.
    // For example,
    // chunk0 : '{a}'  (invisible character only == 0-length)
    // chunk1 : 'b'
    // And DeleteAt(0) is invoked, we have to delete both chunks.
    while !chunks.isEmpty && getLength() == originalSize {
      let chunkIt = maybeSplitChunkAt(position)
      newPosition = getPosition(.local, chunkIt)
      if chunkIt == chunks.count {
        break
      }

      // We have to consider 0-length chunk.
      // If a chunk contains only invisible characters,
      // the result of GetLength is 0.
      if chunks[chunkIt].getLength(.local) <= 1 {
        chunks.remove(at: chunkIt)
        continue
      }

      if chunks[chunkIt].splitChunk(.local, 1) == nil {
        GenmaiLog.warning("SplitChunk failed")
      }
    }
    return newPosition
  }

  /// Get the position on mode_to from position_from on mode_from.
  public func convertPosition(
    _ positionFrom: Int, _ transliteratorFrom: Transliterators.Transliterator,
    _ transliteratorTo: Transliterators.Transliterator
  ) -> Int {
    // TODO(komatsu) This is a hacky way.
    if transliteratorFrom == transliteratorTo {
      return positionFrom
    }

    var innerPositionFrom = 0
    let chunkIt = getChunkAt(positionFrom, transliteratorFrom, &innerPositionFrom)

    // No chunk was found, return 0 as a fallback.
    if chunkIt == chunks.count {
      return 0
    }

    let chunkLengthFrom = chunks[chunkIt].getLength(transliteratorFrom)

    precondition(innerPositionFrom <= chunkLengthFrom)

    let positionTo = getPosition(transliteratorTo, chunkIt)

    if innerPositionFrom == 0 {
      return positionTo
    }

    let chunkLengthTo = chunks[chunkIt].getLength(transliteratorTo)
    if innerPositionFrom == chunkLengthFrom {
      // If the inner_position_from is the end of the chunk (ex. "ka|"
      // vs "か"), the converted position should be the end of the
      // chunk too (ie. "か|").
      return positionTo + chunkLengthTo
    }

    if innerPositionFrom > chunkLengthTo {
      // When inner_position_from is greater than chunk_length_to
      // (ex. "ts|u" vs "つ", inner_position_from is 2 and
      // chunk_length_to is 1), the converted position should be the end
      // of the chunk (ie. "つ|").
      return positionTo + chunkLengthTo
    }

    // When inner_position_from is less than or equal to chunk_length_to
    // (ex. "っ|と" vs "tto", inner_position_from is 1 and
    // chunk_length_to is 2), the converted position is adjusted from
    // the beginning of the chunk (ie. "t|to").
    return positionTo + innerPositionFrom
  }

  // TODO(komatsu): To be deleted.
  @discardableResult
  public mutating func setDisplayMode(
    _ position: Int, _ transliterator: Transliterators.Transliterator
  ) -> Int {
    setTransliterator(0, getLength(), transliterator)
    setInputMode(transliterator)
    return getLength()
  }

  // NOTE(komatsu) Kind of SetDisplayMode.
  public mutating func setTransliterator(
    _ positionFrom: Int, _ positionTo: Int, _ transliterator: Transliterators.Transliterator
  ) {
    if positionFrom > positionTo {
      GenmaiLog.error("position_from should not be greater than position_to.")
      return
    }

    if chunks.isEmpty {
      return
    }

    var innerPositionFrom = 0
    var chunkIt = getChunkAt(positionFrom, .local, &innerPositionFrom)

    var innerPositionTo = 0
    let endIt = getChunkAt(positionTo, .local, &innerPositionTo)

    // chunk_it and end_it can be the same iterator from the beginning.
    while chunkIt != endIt {
      chunks[chunkIt].setTransliterator(transliterator)
      chunkIt += 1
    }
    chunks[endIt].setTransliterator(transliterator)
  }

  public func getTransliterator(_ position: Int) -> Transliterators.Transliterator {
    var innerPosition = 0
    let chunkIt = getChunkAt(position, .local, &innerPosition)
    // C++ dereferences end() here when the composition is empty (DCHECK).
    guard chunkIt < chunks.count else {
      return inputT12r
    }
    return chunks[chunkIt].getTransliterator(.local)
  }

  public func getLength() -> Int {
    getPosition(.local, chunks.count)
  }

  private func getStringWithModes(
    _ transliterator: Transliterators.Transliterator, _ trimMode: TrimMode
  ) -> String {
    if chunks.isEmpty {
      // This is not an error. For example, the composition should be empty for
      // the first keydown event after turning on the IME.
      return ""
    }

    var composition = ""
    for chunk in chunks.dropLast() {
      chunk.appendResult(transliterator, &composition)
    }

    let last = chunks[chunks.count - 1]
    switch trimMode {
    case .trim:
      last.appendTrimedResult(transliterator, &composition)
    case .asis:
      last.appendResult(transliterator, &composition)
    case .fix:
      last.appendFixedResult(transliterator, &composition)
    }
    return composition
  }

  /// Get string with consideration for ambiguity from pending input
  public func getExpandedStrings() -> (String, [String]) {
    let transliterator = Transliterators.Transliterator.local
    if chunks.isEmpty {
      return ("", [])
    }

    var base = ""
    for chunk in chunks.dropLast() {
      chunk.appendResult(transliterator, &base)
    }

    chunks[chunks.count - 1].appendTrimedResult(transliterator, &base)
    // Get expanded from the last chunk
    let expanded = chunks[chunks.count - 1].getExpandedResults()
    return (base, expanded)
  }

  public func getString() -> String {
    if chunks.isEmpty {
      return ""
    }

    var composition = ""
    for chunk in chunks {
      chunk.appendResult(.local, &composition)
    }
    return composition
  }

  public func getStringWithTransliterator(_ transliterator: Transliterators.Transliterator) -> String {
    getStringWithModes(transliterator, .fix)
  }

  public func getStringWithTrimMode(_ trimMode: TrimMode) -> String {
    getStringWithModes(.local, trimMode)
  }

  public func getPreedit(
    _ position: Int, _ left: inout String, _ focused: inout String, _ right: inout String
  ) {
    let composition = getString()
    left = String(Util.utf8SubString(composition, 0, position))
    focused = String(Util.utf8SubString(composition, position, 1))
    right = String(Util.utf8SubString(composition, position + 1))
  }

  public mutating func setInputMode(_ transliterator: Transliterators.Transliterator) {
    inputT12r = transliterator
  }

  /// Return true if the composition is advised to be committed immediately.
  public func shouldCommit() -> Bool {
    chunks.allSatisfy { $0.shouldCommit() }
  }

  public mutating func setTable(_ table: Table) {
    self.table = table
  }

  public func isToggleable(_ position: Int) -> Bool {
    var innerPosition = 0
    let it = getChunkAt(position, .local, &innerPosition)
    if it == chunks.count {
      return false
    }
    return chunks[it].pending.hasBytePrefix(table!.parseSpecialKey("{?}"))
  }

  // Following methods are declared as public for unit test.

  /// Return the focused CharChunk index at the `position`,
  /// and fill `inner_position` as the position inside the returned CharChunk.
  /// ["a", "bc", "e"].GetChunkAt(2) returns "bc" and fills inner_position to 1,
  /// as "c" is the focused character.
  public func getChunkAt(
    _ position: Int, _ transliterator: Transliterators.Transliterator, _ innerPosition: inout Int
  ) -> Int {
    if chunks.isEmpty {
      innerPosition = 0
      return 0
    }

    var chunkOffset = 0
    var chunkLength = 0
    for (i, chunk) in chunks.enumerated() {
      chunkLength = chunk.getLength(transliterator)
      if chunkOffset + chunkLength < position {
        chunkOffset += chunkLength
        continue
      }
      innerPosition = position - chunkOffset
      return i
    }
    // Inner position here is the end of the last chunk.
    innerPosition = chunkLength
    return chunks.count - 1
  }

  public func getPosition(_ transliterator: Transliterators.Transliterator, _ curIt: Int) -> Int {
    var position = 0
    for i in 0..<curIt {
      position += chunks[i].getLength(transliterator)
    }
    return position
  }

  /// Return CharChunk to be inserted a new character.
  /// The argument `it` is the focused CharChunk by the cursor.
  /// If a new chunk is inserted, the returned index equals `it` (and the
  /// chunk formerly at `it` moves to `it + 1`).
  public mutating func getInsertionChunk(_ it: Int) -> Int {
    if it == 0 {
      return insertChunk(it)
    }

    let leftIt = it - 1
    if chunks[leftIt].isAppendable(inputT12r, table!) {
      return leftIt
    }
    return insertChunk(it)
  }

  /// Insert a chunk to the prev of it.
  public mutating func insertChunk(_ it: Int) -> Int {
    chunks.insert(CharChunk(inputT12r, table!), at: it)
    return it
  }

  /// Return the index of the right side CharChunk at the `position`.
  /// If the `position` is in the middle of a CharChunk, that CharChunk is split.
  ///
  /// examples
  /// # typical cases
  /// chunks: ["a", "bc", "d"], pos: 0 -> "a" (= begin)
  /// chunks: ["a", "bc", "d"], pos: 1 -> "bc"
  /// chunks: ["a", "bc", "d"], pos: 2 -> "c", chunks become ["a", "b", "c", "d"]
  /// chunks: ["a", "bc", "d"], pos: 3 -> "d"
  /// chunks: ["a", "bc", "d"], pos: 4 -> end
  /// # {b} is an invisible character
  /// chunks: ["a", "{b}c", "d"], pos: 1 -> "{b}c"
  /// chunks: ["a", "{b}c", "d"], pos: 2 -> "d"
  /// chunks: ["a", "{b}c", "d"], pos: 3 -> end
  /// # {c} is an invisible character
  /// chunks: ["a", "b{c}", "d"], pos: 1 -> "b{c}"
  /// chunks: ["a", "b{c}", "d"], pos: 2 -> "d"
  /// chunks: ["a", "b{c}", "d"], pos: 3 -> end
  public mutating func maybeSplitChunkAt(_ position: Int) -> Int {
    var innerPosition = 0
    let it = getChunkAt(position, .local, &innerPosition)
    if it == 0 && innerPosition == 0 {
      return it
    }

    if innerPosition == chunks[it].getLength(.local) {
      return it + 1
    }

    if let leftChunk = chunks[it].splitChunk(.local, innerPosition) {
      chunks.insert(leftChunk, at: it)
      return it + 1
    }
    return it
  }

  /// Combine |input| and chunks from |it| to left direction,
  /// which have pending data and can be combined.
  /// e.g. [pending='q']+[pending='k']+[pending='y']+[input='o'] are combined
  ///      into [pending='q']+[pending='ky'] because [pending='ky']+[input='o']
  ///      can turn to be a fixed chunk.
  /// e.g. [pending='k']+[pending='y']+[input='q'] are not combined.
  /// Returns the number of chunks removed on the left of `it` (the index of
  /// the combined chunk becomes `it - removed`).
  @discardableResult
  public mutating func combinePendingChunks(_ itArg: Int, _ input: CompositionInput) -> Int {
    // If the input is asis, pending chunks are not related with this input.
    if input.isAsis {
      return 0
    }
    var it = itArg
    var removed = 0
    // Combine |**it| and |**(--it)| into |**it| as long as possible.
    let nextInput = input.conversion.isEmpty ? input.raw : input.conversion

    while it != 0 {
      let leftIt = it - 1
      if !chunks[leftIt].isConvertible(inputT12r, table!, chunks[it].pending + nextInput) {
        return removed
      }

      let left = chunks[leftIt]
      chunks[it].combine(left)
      chunks.remove(at: leftIt)
      it -= 1
      removed += 1
    }
    return removed
  }
}
