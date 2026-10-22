// Port of mozc/src/engine/candidate_list.{h,cc} (3.35.6354).
//
// CandidateList and Candidate classes to be used with Session class.
//
// Deviations from C++:
// - The engine-level `Candidate` and `Attribute` names collide with the
//   converter's `GenmaiCore.Candidate` / `GenmaiCore.Attribute`, so they are
//   nested: `CandidateList.Candidate`, `CandidateList.Attribute` and
//   `CandidateList.Attributes` (= uint32_t).
// - `CandidateList` is a final class (the C++ object is owned by
//   unique_ptr / by value and never copied except for the "minimum copy
//   operator", which copies only `rotate`). `Candidate` is a struct holding
//   its sub-candidate list by reference (the unique_ptr).
// - size_t indices are `Int`. `last_index()` of an empty list is -1 (C++
//   wraps to SIZE_MAX); accessing a candidate of an empty list traps (C++ UB).

import GenmaiBase

public final class CandidateList {
  /// Attribute is added to candidates for annotating additional
  /// information to the candidates.  This is used for toggling ASCII
  /// transliterations at this moment.  Multiple attributes can be used
  /// to one candidates.
  public enum Attribute {
    public static let noAttributes: Attributes = 0
    public static let halfWidth: Attributes = 1
    public static let fullWidth: Attributes = 2
    public static let ascii: Attributes = 4
    public static let hiragana: Attributes = 8
    public static let katakana: Attributes = 16
    public static let upper: Attributes = 32
    public static let lower: Attributes = 64
    public static let capitalized: Attributes = 128
    public static let asis: Attributes = 256
  }

  public typealias Attributes = UInt32

  public struct Candidate {
    public private(set) var id: Int = 0
    public private(set) var attributes: Attributes = Attribute.noAttributes
    fileprivate var subcandidateListStorage: CandidateList?

    public init() {}

    public mutating func clear() {
      id = 0
      attributes = Attribute.noAttributes
      subcandidateListStorage = nil
    }

    public func hasSubcandidateList() -> Bool { subcandidateListStorage != nil }

    public mutating func setId(_ id: Int) { self.id = id }

    public mutating func addAttributes(_ attributes: Attributes) { self.attributes |= attributes }
    public mutating func setAttributes(_ attributes: Attributes) { self.attributes = attributes }
    public func hasAttributes(_ attributes: Attributes) -> Bool {
      (self.attributes & attributes) == attributes
    }

    public var subcandidateList: CandidateList {
      guard let subcandidateListStorage else {
        preconditionFailure("the entry has no subcandidate list")
      }
      return subcandidateListStorage
    }

    public mutating func mutableSubcandidateList() -> CandidateList {
      if let subcandidateListStorage {
        return subcandidateListStorage
      }
      let list = CandidateList()
      subcandidateListStorage = list
      return list
    }
  }

  private static let kDefaultPageSize = 9

  public var pageSize: Int
  public private(set) var focusedIndex: Int
  public var name: String = ""
  private var candidates: [Candidate] = []

  // Map marking added candidate values.  The keys are fingerprints of
  // the candidate values, the values of the map are candidate ids.
  private var addedCandidates: [UInt64: Int] = [:]

  // Id-to-id map.  The key and value ids have the same candidate
  // value.  (ex. {id:0, value:"kanji"} and {id:-5, value:"kanji"}).
  // The key ids are not directly stored in candidates, so accessing
  // these ids, they should be converted with this map.
  private var alternativeIds: [Int: Int] = [:]

  private var nextAvailableIdValue: Int
  public var rotate: Bool
  public var focused: Bool

  public init(rotate: Bool = false) {
    pageSize = Self.kDefaultPageSize
    focusedIndex = 0
    nextAvailableIdValue = 0
    self.rotate = rotate
    focused = false
  }

  /// Minimum copy operator.
  /// TODO(all): Support full copy operation of CandidateList as EngineConverter
  /// is currently copyable. Since the CandidateList contractor is
  /// initialized with `rotate`, `rotate_` is copied in the copy operator.
  public func assign(from candidateList: CandidateList) {
    rotate = candidateList.rotate
  }

  public func clear() {
    candidates.removeAll()
    focusedIndex = 0
    focused = false
    nextAvailableIdValue = 0
    addedCandidates.removeAll()
    alternativeIds.removeAll()
  }

  public func getDeepestFocusedCandidate() -> Candidate {
    if focusedCandidate.hasSubcandidateList() {
      return focusedCandidate.subcandidateList.getDeepestFocusedCandidate()
    }
    return focusedCandidate
  }

  public func addCandidate(_ id: Int, _ value: some StringProtocol) {
    addCandidateWithAttributes(id, value, Attribute.noAttributes)
  }

  public func addCandidateWithAttributes(
    _ id: Int, _ value: some StringProtocol, _ attributes: Attributes
  ) {
    if id >= 0 {
      // If id is not for T13N candidate, update |last_added_id_|.
      nextAvailableIdValue = id + 1
    }

    // If the value has already been stored in the candidate list, reuse it and
    // update the alternative_ids_.
    let fp = cityFingerprint(value)

    if let altId = addedCandidates[fp] {  // insertion was failed.
      alternativeIds[id] = altId

      // Add attributes to the existing candidate.
      for i in 0..<size where candidate(i).id == altId {
        candidates[i].addAttributes(attributes)
      }
      return
    }
    addedCandidates[fp] = id

    var newCandidate = Candidate()
    newCandidate.setId(id)
    newCandidate.setAttributes(attributes)
    candidates.append(newCandidate)
  }

  @discardableResult
  public func addSubCandidateList() -> CandidateList {
    var candidate = Candidate()
    let list = candidate.mutableSubcandidateList()
    candidates.append(candidate)
    return list
  }

  // Accessors
  public var size: Int { candidates.count }
  public var lastIndex: Int { size - 1 }
  public func candidate(_ index: Int) -> Candidate { candidates[index] }
  public var focusedCandidate: Candidate { candidate(focusedIndex) }

  public var focusedId: Int {
    // If the list does not have any candidate, 0 will be returned.
    if size == 0 {
      return 0
    }
    if focusedCandidate.hasSubcandidateList() {
      return focusedCandidate.subcandidateList.focusedId
    }
    return focusedCandidate.id
  }

  public var nextAvailableId: Int {
    var result = nextAvailableIdValue
    for i in 0..<candidates.count where candidate(i).hasSubcandidateList() {
      let subAvailableId = candidate(i).subcandidateList.nextAvailableId
      if result < subAvailableId {
        result = subAvailableId
      }
    }
    return result
  }

  /// Returns a pair of the page index as [begin, end).
  public func getPageRange(_ index: Int) -> (begin: Int, end: Int) {
    let begin = index - (index % pageSize)
    return (begin, min(size, begin + pageSize))
  }

  /// Returns the page at index.
  public func page(_ index: Int) -> ArraySlice<Candidate> {
    let (begin, end) = getPageRange(index)
    return candidates[begin..<end]
  }
  public var focusedPage: ArraySlice<Candidate> { page(focusedIndex) }

  // Operations
  public func moveFirst() { focusedIndex = 0 }
  public func moveLast() { focusedIndex = lastIndex }

  @discardableResult
  public func moveNext() -> Bool {
    // If the current candidate points to subcandidate list, the focused
    // candidate in the subcandidate list will be operated.
    if focusedCandidate.hasSubcandidateList() && mutableFocusedSubcandidateList().moveNext() {
      return true
    }

    if isLast(focusedIndex) {
      moveFirst()
      if !rotate {
        // If this candidate list does not rotate, the focused candidate
        // is moved to the parent candidate list.
        return false
      }
    } else {
      focusedIndex += 1
    }

    // If the new current candidate points to subcandidate list, the
    // focused candidate in the subcandidate list should be the first
    // candidate.
    if focusedCandidate.hasSubcandidateList() {
      mutableFocusedSubcandidateList().moveFirst()
    }
    return true
  }

  @discardableResult
  public func movePrev() -> Bool {
    // If the current candidate points to subcandidate list, the focused
    // candidate in the subcandidate list will be operated.
    if focusedCandidate.hasSubcandidateList() && mutableFocusedSubcandidateList().movePrev() {
      return true
    }

    if Self.isFirst(focusedIndex) {
      moveLast()
      if !rotate {
        // If this candidate list does not rotate, the focused candidate
        // is moved to the parent candidate list.
        return false
      }
    } else {
      focusedIndex -= 1
    }

    // If the new current candidate points to subcandidate list, the
    // focused candidate in the subcandidate list should be the first
    // candidate.
    if focusedCandidate.hasSubcandidateList() {
      mutableFocusedSubcandidateList().moveLast()
    }
    return true
  }

  @discardableResult
  public func moveNextPage() -> Bool {
    if focusedCandidate.hasSubcandidateList() && mutableFocusedSubcandidateList().moveNextPage() {
      return true
    }

    if isLastPage(focusedIndex) {
      if !rotate {
        // If the current candidate is the last candidate and rotation
        // should not be performed, this function does nothing and
        // returns false.
        return false
      }
      moveFirst()
    } else {
      focusedIndex += pageSize
    }
    // Move the forcused index to the beginning of the page.
    focusedIndex -= (focusedIndex % pageSize)

    // If the new current candidate points to subcandidate list, the
    // focused candidate in the subcandidate list should be the first
    // candidate.
    if focusedCandidate.hasSubcandidateList() {
      mutableFocusedSubcandidateList().moveFirst()
    }
    return true
  }

  @discardableResult
  public func movePrevPage() -> Bool {
    if focusedCandidate.hasSubcandidateList() && mutableFocusedSubcandidateList().movePrevPage() {
      return true
    }

    if isFirstPage(focusedIndex) {
      if !rotate {
        // If the current candidate is on the first page and rotation
        // should not be performed, this function does nothing and
        // returns false.
        return false
      }
      moveLast()
    } else {
      // The focused index in not on the first page, so the value of
      // (focused_index_ - page_size_) must be a positive value.
      focusedIndex -= pageSize
    }
    // Move the forcused index to the beginning of the page.
    focusedIndex -= (focusedIndex % pageSize)

    // If the new current candidate points to subcandidate list, the
    // focused candidate in the subcandidate list should be the first
    // candidate.  Note the forcused index will be moved to the
    // beginning of the page on page moves.
    if focusedCandidate.hasSubcandidateList() {
      mutableFocusedSubcandidateList().moveFirst()
    }
    return true
  }

  @discardableResult
  public func moveNextAttributes(_ attributes: Attributes) -> Bool {
    // Move one candidate.
    moveNext()
    return moveToAttributes(attributes)
  }

  @discardableResult
  public func moveToAttributes(_ attributes: Attributes) -> Bool {
    let candSize = size
    for i in 0..<candSize {
      // Shift the index to make the first index focused_index_.
      let index = (focusedIndex + i) % candSize

      // If the candidate is a subcandidate list, the subcandidate list is
      // traversed recursively.
      if candidates[index].hasSubcandidateList()
        && candidates[index].mutableSubcandidateList().moveToAttributes(attributes)
      {
        focusedIndex = index
        return true
      } else if candidates[index].hasAttributes(attributes) {
        focusedIndex = index
        return true
      }
    }

    return false
  }

  @discardableResult
  public func moveToId(_ baseId: Int) -> Bool {
    var id = baseId

    // If an alternative id for the base_id found, use it to avoid
    // duplicated candidates.
    if let alt = alternativeIds[id] {
      id = alt
    }

    // NOTE(komatsu): Although this function's order is O(N), The size
    // of N is less than kMaxCandidateSize (= 200).  So it would not be
    // a problem.
    for i in 0..<size {
      // If the candidate is a subcandidate list, the subcandidate list is
      // traversed recursively.
      if candidates[i].hasSubcandidateList()
        && candidates[i].mutableSubcandidateList().moveToId(id)
      {
        focusedIndex = i
        return true
      } else if candidates[i].id == id {
        focusedIndex = i
        return true
      }
    }
    return false
  }

  /// Move the focus to the index from the beginning of the current
  /// page.  This is a function for shortcut key operation.
  @discardableResult
  public func moveToPageIndex(_ pageIndex: Int) -> Bool {
    let (begin, end) = getPageRange(focusedIndex)
    // Note: |end| is exclusive, i.e. the valid index range is [begin, end).
    if pageIndex < 0 || begin + pageIndex >= end {
      return false
    }
    focusedIndex = begin + pageIndex
    if focusedCandidate.hasSubcandidateList() {
      mutableFocusedSubcandidateList().moveFirst()
    }
    return true
  }

  private func mutableFocusedSubcandidateList() -> CandidateList {
    precondition(focusedCandidate.hasSubcandidateList())
    return candidates[focusedIndex].mutableSubcandidateList()
  }

  private static func isFirst(_ index: Int) -> Bool { index == 0 }
  private func isLast(_ index: Int) -> Bool { index == size - 1 }
  private func isFirstPage(_ index: Int) -> Bool { index < pageSize }
  private func isLastPage(_ index: Int) -> Bool {
    let (_, end) = getPageRange(index)
    return end == size
  }
}
