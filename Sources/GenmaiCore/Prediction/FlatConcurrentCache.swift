// Port of mozc/src/base/container/flat_concurrent_cache.h (3.35.6354).
//
// NOTE: base/container/flat_concurrent_cache is not part of the GenmaiBase port
// yet. It is ported here (inside Prediction, owned by the user-history port)
// because UserHistoryPredictor (revert cache) and RealtimeDecoder (suffix
// cache) need it. Move it to GenmaiBase/Container when GenmaiBase gets it.
//
// Deviations from C++:
// - absl::Hash is replaced by Swift's `Hasher` (`hashValue`). Both are seeded
//   per process, so the bucket assignment is not reproducible in either
//   implementation; only the eviction policy within a bucket is the same.
// - The per-bucket absl SpinLock is a `Mutex` guarding the bucket.
// - `lookup(_:)` returns `Value?` instead of filling an out-parameter.
// - The template parameter `kGroupSize` (default 9) is an initializer
//   argument; custom Hash/Equal parameters are not supported (Hashable).
// - Keys and values must be Sendable (they are shared across threads).

import Foundation
import Synchronization

/// A memory-efficient, thread-safe, fixed-capacity associative cache designed
/// for low-latency lookups and inserts.
/// - Data is organized into independent buckets to minimize lock contention.
/// - Bucket-Level Locking to provide thread safety.
/// - Pseudo-LRU Eviction: Each bucket manages its own eviction independently
///   using a 1-byte aging clock mechanism. When a bucket is full, the entry with
///   the smallest clock value is evicted to make room.
public final class FlatConcurrentCache<Key: Hashable & Sendable, Value: Sendable>: Sendable {
  // All mutable state lives in the buckets, each guarded by its own mutex.

  /// The default bucket size (C++ kGroupSize).
  public static var defaultGroupSize: Int { 9 }

  private struct Bucket {
    var subhash: [UInt8] = []
    var accessClock: [UInt8] = []
    var accessClockVal: UInt8 = 0
    var key: [Key] = []
    var value: [Value] = []

    var num: Int { key.count }

    mutating func clear() {
      subhash.removeAll()
      accessClock.removeAll()
      key.removeAll()
      value.removeAll()
      accessClockVal = 0
    }

    func findIndex(_ k: Key, _ hash: UInt8) -> Int {
      for i in 0..<num {
        if subhash[i] == hash && k == key[i] { return i }
      }
      return -1
    }

    mutating func updateClock(_ index: Int) {
      // Halve all the access_clock values
      accessClockVal &+= 1
      if accessClockVal == 255 {
        accessClockVal = 128
        for i in 0..<num { accessClock[i] >>= 1 }
      }
      accessClock[index] = accessClockVal
    }

    /// Returns the index to construct the new element at. When the bucket is
    /// not full, returns `num` (the caller appends).
    func evictIndex(_ groupSize: Int) -> Int {
      if num < groupSize {
        return num
      }
      // finds the index with the lowest access_clock.
      var minIdx = 0
      for i in 1..<num where accessClock[i] < accessClock[minIdx] {
        minIdx = i
      }
      return minIdx
    }
  }

  private final class LockedBucket: Sendable {
    let bucket = Mutex(Bucket())
  }

  private let groupSize: Int
  private let numBuckets: Int
  private let mask: Int
  private let buckets: [LockedBucket]

  public init(_ n: Int, groupSize: Int = FlatConcurrentCache.defaultGroupSize) {
    precondition(groupSize > 0 && groupSize < 256)
    self.groupSize = groupSize
    numBuckets = Self.calculateBuckets(n, groupSize)
    mask = numBuckets - 1
    buckets = (0..<numBuckets).map { _ in LockedBucket() }
  }

  public func lookup(_ key: Key) -> Value? {
    let (hash, bucket) = getBucket(key)
    return buckets[bucket].bucket.withLock { b -> Value? in
      let i = b.findIndex(key, hash)
      if i != -1 {
        let v = b.value[i]
        b.updateClock(i)
        return v
      }
      return nil
    }
  }

  public func insert(_ key: Key, _ value: Value) {
    let (hash, bucket) = getBucket(key)
    buckets[bucket].bucket.withLock { b in
      // Update the value when key is found.
      let i = b.findIndex(key, hash)
      if i != -1 {
        b.value[i] = value
        b.updateClock(i)
        return
      }

      // Evicts the oldest value and insert new value.
      let index = b.evictIndex(groupSize)
      if index == b.num {
        b.subhash.append(hash)
        b.key.append(key)
        b.value.append(value)
        b.accessClock.append(b.accessClockVal)
      } else {
        b.subhash[index] = hash
        b.key[index] = key
        b.value[index] = value
        b.accessClock[index] = b.accessClockVal
      }
    }
  }

  public func clear() {
    for bucket in buckets {
      bucket.bucket.withLock { $0.clear() }
    }
  }

  public func forEach(_ functor: (Key, Value) -> Void) {
    for bucket in buckets {
      bucket.bucket.withLock { b in
        for j in 0..<b.num {
          functor(b.key[j], b.value[j])
        }
      }
    }
  }

  /// Determines the optimal number of buckets based on the requested capacity.
  /// This function rounds the initial bucket count up to the nearest power of
  /// two.
  private static func calculateBuckets(_ n: Int, _ groupSize: Int) -> Int {
    let target = (n + groupSize - 1) / groupSize
    if target <= 1 { return 1 }
    var pow2 = 1
    while pow2 < target {
      pow2 <<= 1
    }
    return pow2
  }

  private func getBucket(_ key: Key) -> (UInt8, Int) {
    let hash = UInt(bitPattern: key.hashValue)
    let subhash = UInt8(truncatingIfNeeded: hash & 0xff)
    let rotated = (hash >> 8) | (hash << (UInt(UInt.bitWidth) - 8))
    return (subhash, Int(rotated & UInt(mask)))
  }
}
