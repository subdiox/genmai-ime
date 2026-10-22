// Port of mozc/src/prediction/suggestion_filter.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - `absl::StatusOr` becomes `throws`; `CreateOrDie` traps on failure.
// - The filter keeps a reference to the owner of the data span (the memory
//   mapped data set) so that the view stays valid.

import GenmaiBase
import GenmaiStorage

/// An immutable view of the data set.
public final class SuggestionFilter: SuggestionFilterProtocol {
  private let filter: ExistenceFilter
  private let owner: AnyObject?

  public init() {
    filter = ExistenceFilter()
    owner = nil
  }

  public init(_ filter: ExistenceFilter, owner: AnyObject? = nil) {
    self.filter = filter
    self.owner = owner
  }

  public static func create(_ data: DataSpan<UInt32>) throws -> SuggestionFilter {
    do {
      let filter = try ExistenceFilter.read(UnsafeRawBufferPointer(data.buffer))
      return SuggestionFilter(filter, owner: data.owner)
    } catch {
      GenmaiLog.error("SuggestionFilterData is broken: \(error)")
      throw error
    }
  }

  public static func createOrDie(_ data: DataSpan<UInt32>) -> SuggestionFilter {
    do {
      return try create(data)
    } catch {
      fatalError("SuggestionFilterData is broken: \(error)")
    }
  }

  public func isBadSuggestion(_ text: String) -> Bool {
    var lowerText = text
    Util.lowerString(&lowerText)
    return filter.exists(lowerText)
  }
}
