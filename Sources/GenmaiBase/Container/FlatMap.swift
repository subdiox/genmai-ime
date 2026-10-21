// Port of mozc/src/base/container/flat_map.h (3.35.6354).

/// Read-only map that is backed by a sorted array.
///
/// For `String` keys, pass `Strings.byteLess` (or use `init(byteOrdered:)`)
/// to get the bytewise ordering of the C++ `absl::string_view` keys; Swift's
/// `String <` uses canonical equivalence.
public struct FlatMap<K, V> {
  private let entries: [(K, V)]
  private let cmpKey: (K, K) -> Bool

  public init(_ entries: [(K, V)], by cmpKey: @escaping (K, K) -> Bool) {
    var e = entries
    FlatInternal.sortAndVerifyUnique(&e) { cmpKey($0.0, $1.0) }
    self.entries = e
    self.cmpKey = cmpKey
  }

  /// Finds the value associated with the given key, or nil if not found.
  public func findOrNull(_ key: K) -> V? {
    let lb = FlatInternal.findFirst(entries) { !cmpKey($0.0, key) }
    return lb == entries.count || cmpKey(key, entries[lb].0) ? nil : entries[lb].1
  }
}

extension FlatMap where K: Comparable {
  public init(_ entries: [(K, V)]) {
    self.init(entries, by: { $0 < $1 })
  }
}

extension FlatMap where K: StringProtocol {
  /// Creates a map ordered bytewise by the UTF-8 of the keys.
  public init(byteOrdered entries: [(K, V)]) {
    self.init(entries, by: { $0.bytesLess($1) })
  }
}

// The comparator is a pure function, so the container is immutable and safe to
// share when the elements are Sendable.
extension FlatMap: @unchecked Sendable where K: Sendable, V: Sendable {}

extension Strings {
  /// Bytewise `<` for strings, usable as a comparator.
  public static func byteLess<A: StringProtocol, B: StringProtocol>(_ a: A, _ b: B) -> Bool {
    a.bytesLess(b)
  }
}
