// A non-optional URL for string literals (not part of Mozc).

import Foundation

extension URL {
  /// The URL of a literal written in the source. `URL(string:)` fails only for malformed strings, so a failure here
  /// is a typo in the literal (a programming error), not a runtime condition.
  public init(validLiteral string: StaticString) {
    guard let url = URL(string: "\(string)") else {
      preconditionFailure("Malformed URL literal: \(string)")
    }
    self = url
  }
}
