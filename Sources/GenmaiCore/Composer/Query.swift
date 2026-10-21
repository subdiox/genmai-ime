// Port of mozc/src/composer/query.h (3.35.6354).

public struct TypeCorrectedQuery: Sendable, Equatable {
  /// Bit field of correction type.
  public struct CorrectionType: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let noCorrection: CorrectionType = []
    /// Normal typing correction.
    public static let correction = CorrectionType(rawValue: 1)
    /// complete the rest of words/phrases.
    public static let completion = CorrectionType(rawValue: 2)
    /// Pure katukou conversion.
    public static let kanaModifierInsentiveOnly = CorrectionType(rawValue: 4)
  }

  public var correction = ""

  public var type: CorrectionType = .noCorrection

  /// `score` is the score diff against identity score.
  /// score = hyp_score - identity_score.
  /// `score` can be used to determine the triggering condition.
  public var score: Float = 0.0

  /// `bias` is the score diff against the base score.
  /// bias = hyp_score - base_score.
  /// `bias` is used to calculate the penalty/bonus of the correction cost.
  /// base_score is usually the same as the identity_score, but  We consider that
  /// pure kana modifier insensitive correction is not an actual typing
  /// correction. So when the top is a pure kana modifier insensitive correction,
  /// uses the top score as the base score.
  public var bias: Float = 0.0

  public init() {}

  public init(correction: String, type: CorrectionType, score: Float, bias: Float) {
    self.correction = correction
    self.type = type
    self.score = score
    self.bias = bias
  }
}
