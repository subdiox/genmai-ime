// Port of mozc/src/prediction/predictor_interface.h (3.35.6354).
//
// Deviations from C++:
// - `prediction::Result` is `PredictionResult` (see Result.swift).
// - Virtual methods with a default body are protocol requirements with a
//   default in an extension. NOTE (protocol default dispatch pitfall, see
//   CLAUDE.md): a class hierarchy of predictors must implement every
//   requirement it customizes in the base class and `override` it in
//   subclasses; otherwise the extension default is called through
//   `any PredictorInterface`.

public protocol PredictorInterface: AnyObject {
  /// Returns suggestions.
  /// You may need to change the behavior according to the
  /// Segments::request_type flag
  /// SUGGESTION: automatic suggestions
  /// PREDICTION: invoked only when user pushes "tab" key.
  /// less aggressive than SUGGESTION mode.
  func predict(_ request: ConversionRequest) -> [PredictionResult]

  /// Returns conversions.
  /// Almost the same as Prediction, but it returns exact-match results only.
  /// Note: Convert method is not fully supported and still experimental
  /// feature. Do not use it in production.
  func convert(_ request: ConversionRequest) -> [PredictionResult]

  /// Finish the conversion. Stores the history for penalization.
  /// results[0] stores the committed result.
  /// We can revert the Finish operation with the revert_id and Revert method.
  func finish(_ request: ConversionRequest, _ results: [PredictionResult], _ revertId: UInt32)

  /// Reverts the last Finish operation.
  func revert(_ revertId: UInt32)

  /// Syncs user-modified context.
  func commitContext(_ request: ConversionRequest)

  /// Clears all history data of UserHistoryPredictor.
  @discardableResult func clearAllHistory() -> Bool

  /// Clears a specific history data of UserHistoryPredictor.
  @discardableResult func clearHistoryEntry(_ key: String, _ value: String) -> Bool

  @discardableResult func addHistoryEntry(_ key: String, _ value: String) -> Bool

  /// Syncs user history to local disk.
  @discardableResult func sync() -> Bool

  /// Reloads user history data from local disk.
  @discardableResult func reload() -> Bool

  /// Waits for syncer thread to complete (suspends; no thread is blocked).
  @discardableResult func wait() async -> Bool

  func getPredictorName() -> String
}

extension PredictorInterface {
  public func convert(_ request: ConversionRequest) -> [PredictionResult] { [] }
  public func finish(_ request: ConversionRequest, _ results: [PredictionResult], _ revertId: UInt32) {}
  public func revert(_ revertId: UInt32) {}
  public func commitContext(_ request: ConversionRequest) {}
  public func clearAllHistory() -> Bool { true }
  public func clearHistoryEntry(_ key: String, _ value: String) -> Bool { true }
  public func addHistoryEntry(_ key: String, _ value: String) -> Bool { true }
  public func sync() -> Bool { true }
  public func reload() -> Bool { true }
  public func wait() async -> Bool { true }
}
