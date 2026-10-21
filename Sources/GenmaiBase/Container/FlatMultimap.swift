// Port of mozc/src/base/container/flat_multimap.h (3.35.6354).

/// Read-only multimap that is backed by a sorted array.
public struct FlatMultimap<K, V> {
  private let entries: [(K, V)]
  private let cmpKey: (K, K) -> Bool

  public init(_ entries: [(K, V)], by cmpKey: @escaping (K, K) -> Bool) {
    // The C++ uses std::sort, which is not stable. A stable sort is used here;
    // EqualSpan does not guarantee the order of entries anyway.
    var e = entries
    e.sort { cmpKey($0.0, $1.0) }
    self.entries = e
    self.cmpKey = cmpKey
  }

  /// Returns the entries with the given key.
  ///
  /// IMPORTANT: The order of the returned entries is not guaranteed to be the
  /// same as the order of the entries given when the map was created.
  public func equalSpan(_ key: K) -> ArraySlice<(K, V)> {
    let lb = FlatInternal.findFirst(entries) { !cmpKey($0.0, key) }
    let ub = FlatInternal.findFirst(entries) { cmpKey(key, $0.0) }
    return entries[lb..<ub]
  }
}

extension FlatMultimap where K: Comparable {
  public init(_ entries: [(K, V)]) {
    self.init(entries, by: { $0 < $1 })
  }
}

extension FlatMultimap where K: StringProtocol {
  /// Creates a multimap ordered bytewise by the UTF-8 of the keys.
  public init(byteOrdered entries: [(K, V)]) {
    self.init(entries, by: { $0.bytesLess($1) })
  }
}

// The comparator is a pure function, so the container is immutable and safe to
// share when the elements are Sendable.
extension FlatMultimap: @unchecked Sendable where K: Sendable, V: Sendable {}
