// Port of mozc/src/storage/lru_cache_test.cc (3.35.6354).

import Testing

@testable import GenmaiStorage

private func sizeOfFreeList<K, V>(_ cache: LruCache<K, V>) -> Int {
  var size = 0
  var e = cache.freeListForTesting
  while let element = e {
    size += 1
    e = element.next
  }
  return size
}

private func getOrderedKeys<K, V>(_ cache: LruCache<K, V>) -> [K] {
  var keys: [K] = []
  keys.reserveCapacity(cache.size)
  for elem in cache {
    keys.append(elem.key)
  }
  return keys
}

@Suite struct LruCacheTest {
  @Test func insert() {
    let cache = LruCache<Int, Int>(3)
    #expect(cache.size == 0)

    cache.insert(0, 0)
    #expect(getOrderedKeys(cache) == [0])
    cache.insert(1, 1)
    #expect(getOrderedKeys(cache) == [1, 0])
    cache.insert(2, 2)
    #expect(getOrderedKeys(cache) == [2, 1, 0])
    cache.insert(3, 3)
    #expect(getOrderedKeys(cache) == [3, 2, 1])
    cache.insert(4, 4)
    #expect(getOrderedKeys(cache) == [4, 3, 2])
    cache.insert(5, 5)
    #expect(getOrderedKeys(cache) == [5, 4, 3])
  }

  @Test func lookup() {
    let cache = LruCache<Int, Int>(5)
    for i in 0..<3 {
      cache.insert(i, i)
    }
    #expect(getOrderedKeys(cache) == [2, 1, 0])

    // Looked up elements are moved to the head.
    #expect(cache.lookup(0) != nil)
    #expect(getOrderedKeys(cache) == [0, 2, 1])
    #expect(cache.lookup(1) != nil)
    #expect(getOrderedKeys(cache) == [1, 0, 2])

    #expect(cache.lookup(-1) == nil)
    #expect(cache.lookup(3) == nil)
  }

  @Test func lookupWithoutInsert() {
    let cache = LruCache<Int, Int>(5)
    for i in 0..<3 {
      cache.insert(i, i)
    }
    #expect(getOrderedKeys(cache) == [2, 1, 0])

    // Unlike Lookup, LRU order shouldn't change.
    for i in 0..<3 {
      #expect(cache.lookupWithoutInsert(i) != nil)
      #expect(getOrderedKeys(cache) == [2, 1, 0])
    }
    #expect(cache.lookupWithoutInsert(-1) == nil)
    #expect(cache.lookupWithoutInsert(3) == nil)
  }

  @Test func erase() {
    let cache = LruCache<Int, Int>(5)
    for i in 0..<3 {
      cache.insert(i, i)
    }
    #expect(getOrderedKeys(cache) == [2, 1, 0])

    #expect(!cache.erase(-1))
    #expect(!cache.erase(5))

    #expect(getOrderedKeys(cache) == [2, 1, 0])
    #expect(cache.erase(1))
    #expect(getOrderedKeys(cache) == [2, 0])
    #expect(cache.erase(0))
    #expect(getOrderedKeys(cache) == [2])
    #expect(cache.erase(2))
    #expect(cache.size == 0)
  }

  @Test func clear() {
    let cache = LruCache<Int, Int>(5)
    for i in 0..<3 {
      cache.insert(i, i)
    }
    #expect(getOrderedKeys(cache) == [2, 1, 0])
    #expect(sizeOfFreeList(cache) == 2)
    cache.clear()
    #expect(cache.size == 0)
    #expect(sizeOfFreeList(cache) == 5)
  }

  @Test func largeCapacity() {
    let kCapacity = 1_000_000
    let cache = LruCache<Int, Int>(kCapacity)
    var ok = true
    for i in 0..<(3 * kCapacity) {
      cache.insert(i, i)
      // Aggregated to keep the number of recorded expectations small.
      ok = ok && cache.hasKey(i) && cache.head?.key == i && kCapacity >= cache.size
    }
    #expect(ok)
  }
}
