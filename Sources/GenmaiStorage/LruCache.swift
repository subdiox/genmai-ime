// Port of mozc/src/storage/lru_cache.h (3.35.6354).
//
// Elements are reference types (C++ `Element*`), allocated in blocks exactly
// like the C++ code so that the free-list behavior is the same. The blocks own
// the elements; the list links are unowned(unsafe) references.
//
// API mapping:
// - Lookup / LookupWithoutInsert return a copy of the value (Value?).
// - MutableLookup / MutableLookupWithoutInsert return the Element, whose
//   `value` can be mutated in place (C++ returns Value*).
// - insert(key) returns the Element; the caller must set `value`.
// - Iteration (for-in) yields the Elements from the head (most recently used).

/// Note: this type keeps some resources inside of the Key/Value, even if
/// such a entry is erased. Be careful to use for such types.
public final class LruCache<Key: Hashable, Value>: Sequence {
  /// Every Element is either on the free list or the lru list.  The
  /// free list is singly-linked and only uses the next pointer, while
  /// the LRU list is doubly-linked and uses both next and prev.
  public final class Element {
    public internal(set) unowned(unsafe) var next: Element?
    public internal(set) unowned(unsafe) var prev: Element?
    public internal(set) var key: Key!
    var storedValue: Value?

    init() {}

    /// The value. Must be set after `insert(key)` before it is read.
    public var value: Value {
      get { storedValue! }
      set { storedValue = newValue }
      _modify { yield &storedValue! }
    }
  }

  public struct Iterator: IteratorProtocol {
    private var current: Element?
    private var nextElement: Element?

    init(_ element: Element?) {
      current = element
      nextElement = element?.next
    }

    public mutating func next() -> Element? {
      guard let result = current else { return nil }
      current = nextElement
      // Capture `next` for when it's changed before the next increment.
      nextElement = current?.next
      return result
    }
  }

  private static var kMaxBlocks: Int { 10 }

  private var table: [Key: Element] = [:]
  private unowned(unsafe) var freeList: Element? = nil  // singly linked list of Element
  private unowned(unsafe) var lruHead: Element? = nil  // head of doubly linked list of Element
  private unowned(unsafe) var lruTail: Element? = nil  // tail of doubly linked list of Element
  // blocks of Element, with each block being twice as big as the previous
  // block.  This allows the cache to use a small amount of memory when it
  // contains few items, but still have low malloc overhead per insert.  The
  // number of blocks is arbitrary, but 10 blocks allows the largest block to
  // be 2^10 times as large as the smallest block, which seems like more than
  // enough.
  private var blocks: [[Element]] = []
  private var blockCapacity = 0  // num elements the current blocks can hold
  private var nextBlockSize = 0  // size of the next block to allocate
  private let maxElements: Int  // maximum elements to hold

  /// Constructs a new LruCache that can hold at most max_elements
  public init(_ maxElements: Int) {
    self.maxElements = maxElements
    if maxElements <= 128 {
      nextBlockSize = maxElements
    } else {
      nextBlockSize = 64
      let numBlocks = Self.kMaxBlocks
      // The default starting block size is 64, which is 2^6.  Every block is
      // twice as big as the previous (see addBlock()), so the size of the last
      // block would be 2^(6 + num_blocks) if the first block was of size 64.
      // If max_elements is large enough that 64 is too low of a starting
      // size, figure that out here.
      while (nextBlockSize << numBlocks) < maxElements {
        nextBlockSize = nextBlockSize << 1
      }
    }
  }

  // Iterators
  public func makeIterator() -> Iterator { Iterator(lruHead) }

  /// Adds the specified key/value pair into the cache, putting it at the head
  /// of the LRU list.
  public func insert(_ key: Key, _ value: Value) {
    let e = insert(key)
    e.value = value
  }

  /// Adds the specified key and return the Element added to the cache.
  /// Caller needs to set the value
  @discardableResult
  public func insert(_ key: Key) -> Element {
    var e = lookupInternal(key)
    if let found = e {
      let erased = evict(found)
      precondition(erased)
    }

    e = nextFreeElement()
    if e == nil {
      // no free elements, I have to replace an existing element
      let erased = evict(lruTail)
      precondition(erased)
      e = nextFreeElement()
      precondition(e != nil)
    }
    let element = e!
    element.key = key
    table[key] = element
    pushLRUHead(element)

    return element
  }

  /// Returns the cached value associated with the key, or nil if the cache
  /// does not contain an entry for that key.  Moves the entry to the head.
  public func lookup(_ key: Key) -> Value? {
    mutableLookup(key)?.value
  }

  /// Returns the element (whose value can be mutated) and moves it to the
  /// head.
  public func mutableLookup(_ key: Key) -> Element? {
    if let e = lookupInternal(key) {
      pushLRUHead(e)
      return e
    }
    return nil
  }

  /// lookupWithoutInsert/mutableLookupWithoutInsert don't change the LRU
  /// order.
  public func lookupWithoutInsert(_ key: Key) -> Value? {
    lookupInternal(key)?.value
  }

  /// Returns the element (whose value can be mutated) without changing the
  /// LRU order.
  public func mutableLookupWithoutInsert(_ key: Key) -> Element? {
    lookupInternal(key)
  }

  /// Removes the cache entry specified by key.  Returns true if the entry was
  /// in the cache, otherwise returns false.
  @discardableResult
  public func erase(_ key: Key) -> Bool {
    evict(lookupInternal(key))
  }

  /// Removes all entries from the cache.  Note that this does not release the
  /// memory associates with the blocks, but just pushes all the elements onto
  /// the free list.
  public func clear() {
    table.removeAll()
    for e in self {
      pushFreeList(e)
    }
    lruHead = nil
    lruTail = nil
  }

  /// Returns the number of entries currently in the cache.
  public var size: Int { table.count }
  public var isEmpty: Bool { lruHead == nil }

  public func hasKey(_ key: Key) -> Bool { table[key] != nil }

  /// Returns the head of LRU list
  public var head: Element? { lruHead }
  /// Returns the tail of LRU list
  public var tail: Element? { lruTail }

  /// Expose the free list only for testing purposes.
  public var freeListForTesting: Element? { freeList }

  // MARK: - Private

  /// Allocates a new block containing next_block_size_ elements, updates
  /// next_block_size_ appropriately, and pushes the elements in the new block
  /// onto the free list.
  private func addBlock() {
    let maxBlocks = Self.kMaxBlocks
    if blocks.count < maxBlocks && blockCapacity < maxElements {
      var block: [Element] = []
      block.reserveCapacity(nextBlockSize)
      for _ in 0..<nextBlockSize {
        block.append(Element())
      }
      blocks.append(block)
      blockCapacity += nextBlockSize
      // Add new elements to free list
      for e in block {
        e.prev = nil  // free list is not doubly linked
        e.next = freeList
        freeList = e
      }
      let blocksRemaining = maxBlocks - blocks.count
      if blocksRemaining > 0 {
        nextBlockSize = nextBlockSize << 1
        let elementsRemaining = maxElements - blockCapacity
        if nextBlockSize > (elementsRemaining / blocksRemaining) {
          nextBlockSize = elementsRemaining / blocksRemaining
        }
        if blockCapacity + nextBlockSize > maxElements {
          nextBlockSize = maxElements - blockCapacity
        }
      }
    }
  }

  /// Pushes an element onto the head of the free list.
  private func pushFreeList(_ element: Element) {
    element.prev = nil
    element.next = freeList
    freeList = element
  }

  /// Pops an element from the head of the free list.
  private func popFreeList() -> Element? {
    let r = freeList
    if let r {
      precondition(r.prev == nil)
      freeList = r.next
      if let f = freeList {
        f.prev = nil
      }
      r.next = nil
    }
    return r
  }

  /// Returns a free element, popping from the free list if possible, or
  /// allocating a new element if the free list is empty.  If there are
  /// already max_elements_ in use this will return nil.
  private func nextFreeElement() -> Element? {
    var r = popFreeList()
    if r == nil {
      addBlock()
      r = popFreeList()
    }
    return r
  }

  /// Returns the Element associated with key, or nil if no element with this
  /// key is found.
  private func lookupInternal(_ key: Key) -> Element? {
    table[key]
  }

  /// Removes the specified element from the LRU list.
  private func removeFromLRU(_ element: Element) {
    if lruHead === element {
      lruHead = element.next
    }
    if lruTail === element {
      lruTail = element.prev
    }
    if let prev = element.prev {
      prev.next = element.next
    }
    if let next = element.next {
      next.prev = element.prev
    }
    element.prev = nil
    element.next = nil
  }

  /// Adds the specified element to the head of the LRU list.
  private func pushLRUHead(_ element: Element) {
    if lruHead === element {
      // element is already at head, so do nothing.
      return
    }
    removeFromLRU(element)
    element.next = lruHead
    lruHead = element
    if let next = element.next {
      next.prev = element
    }
    if lruTail == nil {
      lruTail = element
    }
  }

  /// Evict is similar to Erase, except that it takes an element so that
  /// another lookup is not necessary.
  private func evict(_ e: Element?) -> Bool {
    if let e {
      let erased = table.removeValue(forKey: e.key) != nil
      precondition(erased)
      removeFromLRU(e)
      pushFreeList(e)
      return true
    }
    return false
  }
}
