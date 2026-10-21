// Port of mozc/src/converter/caching_connector.h (3.35.6354).

/// A wrapper for Connector to minimize calls of Connector.getTransitionCost()
/// in Viterbi algorithm. This way the performance of Viterbi algorithm improves
/// significantly in terms of time consumption because
/// Connector.getTransitionCost() is slow due to its compression format. This
/// class implements a cache strategy designed for the access pattern in Viterbi
/// algorithm.
///
/// In Viterbi algorithm, the connection matrix is looked up in a nested loop as
/// follows:
///
///     for each right node `r`:
///       for each left node `l`:
///         ...
///         transition cost = connector.getTransitionCost(l.rid, r.lid)
///         ...
///
/// Therefore, in the inner loop, `r.lid` is fixed. We cache the transition cost
/// for (l.rid, r.lid) in `cache[l.rid]`, tagged with `r.lid`. This tag-based
/// cache avoids clearing the entire cache array when `r.lid` changes, completely
/// eliminating memset overhead during Viterbi DP, while allowing cached entries
/// to be reused when the same `r.lid` appears again.
///
/// NOTE: This class is designed for Viterbi or A* search algorithms (which have
/// a similar nested loop access pattern) and won't work for other purposes.
///
/// This class also centrally manages the application of the experimental
/// transition cost bonus (e.g., for particle omission). While there are other
/// places in the decoder that directly call `Connector.getTransitionCost` (such
/// as personal name processing or compound splitting), they do not need to apply
/// this bonus because they only handle POS pairs where the bonus is never
/// applicable (e.g., noun-to-noun) or such transitions do not occur in practice.
/// Thus, applying the bonus only within this class is sufficient to maintain
/// cost consistency.
///
/// The C++ template parameter `kHasBonus` is the `hasBonus` constant here.
public final class CachingConnector {
  private static let kInvalidLid = UInt16.max
  private static let kCacheSize = 2048

  private let connector: Connector
  private let hasBonus: Bool
  private let particleOmissionTransitionCostBonus: Int
  private let posMatcher: PosMatcher
  private let cacheLid: UnsafeMutablePointer<UInt16>
  private let cacheCost: UnsafeMutablePointer<Int32>
  private var cacheLidValue: UInt16 = kInvalidLid
  private var isRightNodeTarget = false

  public init(
    hasBonus: Bool, _ connector: Connector, _ particleOmissionTransitionCostBonus: Int,
    _ posMatcher: PosMatcher
  ) {
    self.hasBonus = hasBonus
    self.connector = connector
    self.particleOmissionTransitionCostBonus = particleOmissionTransitionCostBonus
    self.posMatcher = posMatcher
    cacheLid = .allocate(capacity: Self.kCacheSize)
    cacheLid.initialize(repeating: Self.kInvalidLid, count: Self.kCacheSize)
    cacheCost = .allocate(capacity: Self.kCacheSize)
    cacheCost.initialize(repeating: 0, count: Self.kCacheSize)
  }

  deinit {
    cacheLid.deallocate()
    cacheCost.deallocate()
  }

  /// Prepares the cache for the inner loop where `rnodeLid` is fixed.
  /// When bonus is enabled, precomputes whether the right node is a bonus
  /// target.
  @inline(__always)
  public func resetCacheIfNecessary(_ rnodeLid: UInt16) {
    if cacheLidValue != rnodeLid {
      cacheLidValue = rnodeLid
      if hasBonus {
        isRightNodeTarget =
          particleOmissionTransitionCostBonus > 0 && posMatcher.isContentWordWithConjugation(rnodeLid)
      }
    }
  }

  @inline(__always)
  public func getTransitionCost(_ lnodeRid: UInt16, _ rnodeLid: UInt16) -> Int {
    // Values for rid >= kCacheSize cannot be cached. However, frequent PoSs
    // have smaller IDs, so caching only for rid in [0, kCacheSize) works well.
    if Int(lnodeRid) >= Self.kCacheSize {
      let cost = connector.getTransitionCost(lnodeRid, rnodeLid)
      return hasBonus ? applyBonus(cost, lnodeRid) : cost
    }

    let i = Int(lnodeRid)
    if cacheLid[i] == rnodeLid {
      return Int(cacheCost[i])
    }

    var cost = connector.getTransitionCost(lnodeRid, rnodeLid)
    if hasBonus {
      cost = applyBonus(cost, lnodeRid)
    }
    cacheLid[i] = rnodeLid
    cacheCost[i] = Int32(truncatingIfNeeded: cost)
    return cost
  }

  private func applyBonus(_ cost: Int, _ lnodeRid: UInt16) -> Int {
    if hasBonus {
      if isRightNodeTarget && (posMatcher.isContentNoun(lnodeRid) || posMatcher.isPronoun(lnodeRid)) {
        return max(0, cost - particleOmissionTransitionCostBonus)
      }
    }
    return cost
  }
}
