// Port of mozc/src/base/container/flat_internal.h (3.35.6354).

enum FlatInternal {
  /// Finds the first element satisfying the given predicate, or `count` if
  /// none exists.
  ///
  /// `pred` must be non-decreasing in `span`: if `l <= r`, then
  /// `pred(span[l]) <= pred(span[r])`, where `false < true`.
  static func findFirst<T>(_ span: [T], _ pred: (T) -> Bool) -> Int {
    if span.isEmpty { return span.count }
    if pred(span[0]) { return 0 }

    // Invariant: `pred(span[l])` is false and `pred(span[r])` is true
    // (virtually assuming `pred(span[span.size()])` is true).
    var l = 0
    var r = span.count
    while r - l > 1 {
      let mid = l + (r - l) / 2
      if pred(span[mid]) {
        r = mid
      } else {
        l = mid
      }
    }
    return r
  }

  /// Sorts the given array in place, and verifies that the elements are unique
  /// according to `cmp`.
  ///
  /// Note: the C++ uses `std::sort` (not stable); since elements are unique,
  /// the result does not depend on the sort algorithm.
  static func sortAndVerifyUnique<T>(_ span: inout [T], _ cmp: (T, T) -> Bool) {
    span.sort(by: cmp)
    var i = 0
    while i + 1 < span.count {
      if !cmp(span[i], span[i + 1]) && !cmp(span[i + 1], span[i]) {
        fatalError("Duplicate entry found")
      }
      i += 1
    }
  }
}
