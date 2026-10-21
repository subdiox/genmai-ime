// Port of mozc/src/base/container/flat_concurrent_cache_test.cc (3.35.6354).
//
// LifetimeTracking: the C++ test counts copy/move constructions of a value
// type. Swift class instances are shared, not copied, so the Swift test
// tracks live instances (deinit) instead: the counts differ from C++ only by
// the copy that C++ keeps in the cache for an lvalue insert.

import Foundation
import GenmaiBase
import Synchronization
import Testing

@testable import GenmaiCore

private final class FCCInstanceCounter: Sendable {
  private let activeCount = Mutex(0)  // constructions - destructions
  func constructed() { activeCount.withLock { $0 += 1 } }
  func destructed() { activeCount.withLock { $0 -= 1 } }
  var activeInstances: Int { activeCount.withLock { $0 } }
}

private final class FCCTrackedObject: Sendable {
  let id: Int
  private let counter: FCCInstanceCounter?

  init(_ id: Int, _ counter: FCCInstanceCounter?) {
    self.id = id
    self.counter = counter
    counter?.constructed()
  }

  deinit {
    counter?.destructed()
  }
}

private typealias TestCache = FlatConcurrentCache<String, Int>

struct FlatConcurrentCacheTest {
  @Test func basicPutAndGet() {
    let cache = TestCache(10)

    // Accept boths lvalue and rvalue.
    let val1 = 100
    cache.insert("key1", val1)
    cache.insert("key2", 200)

    #expect(cache.lookup("key1") == 100)

    #expect(cache.lookup("key2") == 200)

    #expect(cache.lookup("unknown") == nil)
  }

  @Test func overwriteExistingKey() {
    let cache = TestCache(10)

    cache.insert("key1", 100)
    cache.insert("key1", 999)  // Update with the same key.

    #expect(cache.lookup("key1") == 999)
  }

  @Test func evictionPolicy() {
    // Force to use the bucket of size 1.
    let smallCache = FlatConcurrentCache<Int, Int>(1, groupSize: 4)

    // Inserts 4 items.
    for i in 0..<4 { smallCache.insert(i, i * 10) }

    // Access the item 0 so increase access_clock.
    for _ in 0..<10 {
      #expect(smallCache.lookup(0) != nil)
    }

    // Insert next item.
    smallCache.insert(100, 1000)

    // The item 0 should be survived.
    #expect(smallCache.lookup(0) == 0)
  }

  @Test func clearCache() {
    let cache = TestCache(100)
    cache.insert("a", 1)
    cache.insert("b", 2)
    cache.clear()

    #expect(cache.lookup("a") == nil)
    #expect(cache.lookup("b") == nil)
    #expect(cache.lookup("c") == nil)
  }

  @Test func concurrencyStressTest() async {
    let kNumThreads = 8
    let kOpsPerThread = 10000
    let cache = TestCache(1000)

    await runUserHistoryTestThreads(kNumThreads) { t in
      for i in 0..<kOpsPerThread {
        let key = "key_\(i % 100)"  // Conflicts
        if i % 2 == 0 {
          cache.insert(key, i + t)
        } else {
          _ = cache.lookup(key)
        }
      }
    }
  }

  @Test func lifetimeTracking() {
    let counter = FCCInstanceCounter()
    do {
      let cache = FlatConcurrentCache<Int, FCCTrackedObject>(1, groupSize: 4)

      #expect(counter.activeInstances == 0)

      // Insert 1st item
      cache.insert(1, FCCTrackedObject(100, counter))
      #expect(counter.activeInstances == 1)

      // Insert 2nd item (lvalue). The cache shares the instance (C++: 3).
      let obj2 = FCCTrackedObject(200, counter)
      cache.insert(2, obj2)
      #expect(counter.activeInstances == 2)

      // Insert 3rd item
      cache.insert(3, FCCTrackedObject(300, counter))
      #expect(counter.activeInstances == 3)

      // Insert 4th item
      cache.insert(4, FCCTrackedObject(400, counter))
      #expect(counter.activeInstances == 4)

      // Now bucket is full (group size 4).
      // Next insert will trigger eviction.
      // Let's access item 1 to make it survive eviction.
      do {
        let val = cache.lookup(1)
        #expect(val?.id == 100)
      }

      // Insert 5th item -> triggers eviction.
      // It should evict one of 2, 3, 4 (since 1 was accessed).
      cache.insert(5, FCCTrackedObject(500, counter))
      #expect(cache.lookup(1)?.id == 100)

      // Active instances: 4 cached (+ obj2 if it was not the evicted one;
      // obj2 is alive in scope either way) (C++: 5).
      #expect(counter.activeInstances == (cache.lookup(2) == nil ? 5 : 4))

      // Now let's clear the cache. All 4 remaining items should be destructed.
      cache.clear()
      #expect(counter.activeInstances == 1)  // only obj2 in scope

      // Insert some more
      cache.insert(6, FCCTrackedObject(600, counter))
      cache.insert(7, FCCTrackedObject(700, counter))
      #expect(counter.activeInstances == 3)  // obj2 in scope + 6 and 7 in cache
      withExtendedLifetime(obj2) {}
    }
    // Cache is now out of scope and destroyed.
    // All remaining items (6 and 7) should be destructed.
    #expect(counter.activeInstances == 0)
  }
}
