// Port of mozc/src/prediction/suggestion_filter.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - `absl::StatusOr` becomes `throws`; `CreateOrDie` traps on failure.

import GenmaiBase
import GenmaiStorage

/// An immutable view of the data set.
public final class SuggestionFilter: SuggestionFilterProtocol {
  private let filter: ExistenceFilter

  public init() {
    filter = ExistenceFilter()
  }

  public init(_ filter: ExistenceFilter) {
    self.filter = filter
  }

  public static func create(_ data: DataSpan<UInt32>) throws -> SuggestionFilter {
    do {
      // The filter keeps a slice of the data (no copy).
      return SuggestionFilter(try ExistenceFilter.read(data.view.data))
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
