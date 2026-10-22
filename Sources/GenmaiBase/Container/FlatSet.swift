// Port of mozc/src/base/container/flat_set.h (3.35.6354).

/// Read-only set that is backed by a sorted array.
public struct FlatSet<T> {
  private let elements: [T]
  private let cmp: @Sendable (T, T) -> Bool

  public init(_ elements: [T], by cmp: @escaping @Sendable (T, T) -> Bool) {
    var e = elements
    FlatInternal.sortAndVerifyUnique(&e, cmp)
    self.elements = e
    self.cmp = cmp
  }

  /// Returns if the given element is in the set.
  public func contains(_ x: T) -> Bool {
    let lb = FlatInternal.findFirst(elements) { !cmp($0, x) }
    return lb != elements.count && !cmp(x, elements[lb])
  }
}

extension FlatSet where T: Comparable & SendableMetatype {
  public init(_ elements: [T]) {
    self.init(elements, by: { $0 < $1 })
  }
}

extension FlatSet where T: StringProtocol & SendableMetatype {
  /// Creates a set ordered bytewise by the UTF-8 of the elements.
  public init(byteOrdered elements: [T]) {
    self.init(elements, by: { $0.bytesLess($1) })
  }
}

// The comparator is a pure function, so the container is immutable and safe to
// share when the elements are Sendable.
extension FlatSet: Sendable where T: Sendable {}
