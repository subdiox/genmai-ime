// Port of mozc/src/base/japanese_util.h (3.35.6354).
//
// `mozc::japanese_util` only re-exports the functions of `mozc::japanese`
// (base/strings/japanese.h) and `ConvertUsingDoubleArray`.

public typealias JapaneseUtil = Japanese

extension Japanese {
  /// `japanese_util::ConvertUsingDoubleArray`.
  public static func convertUsingDoubleArray(_ rule: JapaneseRule, _ input: some StringProtocol)
    -> String
  {
    JapaneseInternal.convertUsingDoubleArray(rule, input)
  }
}
