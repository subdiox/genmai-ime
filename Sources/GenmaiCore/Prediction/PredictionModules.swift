// Abstractions of mozc/src/engine/modules.h and
// mozc/src/engine/supplemental_model_interface.h for the prediction port
// (3.35.6354).
//
// engine::Modules and engine::SupplementalModelInterface are not part of the
// prediction port. The prediction code only needs the members below:
// - `PredictionModules` is the subset of engine::Modules used by the decoders,
//   DictionaryPredictor and Predictor. engine::Modules should conform to it.
// - `PredictionSupplementalModel` is the subset of
//   engine::SupplementalModelInterface used by the prediction code. It refines
//   the subsets used by the converter (ConverterSupplementalModel), the user
//   history predictor (UserHistorySupplementalModel) and CorrectionRewriter
//   (ReadingAlignmentSupplementalModel), so the engine's
//   SupplementalModelInterface should refine it. Modules return their
//   supplemental model through `ConverterModules.getSupplementalModel()`;
//   `predictionSupplementalModel()` downcasts it and falls back to a no-op
//   stub (like engine::SupplementalModelStub) when it does not conform.
//
// NOTE (protocol default dispatch pitfall, see CLAUDE.md): the requirements
// have no-op defaults. A class hierarchy must implement every requirement in
// its base class and `override` it in subclasses.

import GenmaiBase

/// The subset of engine::SupplementalModelInterface used by the prediction
/// code (PostCorrect and IsAvailable come from ConverterSupplementalModel,
/// CorrectComposition from UserHistorySupplementalModel and
/// GetReadingAlignment from ReadingAlignmentSupplementalModel).
public protocol PredictionSupplementalModel: ConverterSupplementalModel,
  UserHistorySupplementalModel
{
  /// Populates the typing correction penalty and attribute to `results`.
  /// (`absl::Span<Result>`: the number of results must not be changed.)
  func populateTypeCorrectedQuery(_ request: ConversionRequest, _ results: inout [PredictionResult])

  /// Performs rescoring for `results` given the context `results`.
  /// (`absl::Span<Result>`: the number of results must not be changed.)
  func rescoreResults(_ request: ConversionRequest, _ results: inout [PredictionResult])

  /// Performs next word/phrase prediction given the context in `request`.
  /// Results are appended to `results`. Returns true if prediction was
  /// performed.
  @discardableResult
  func predict(_ request: ConversionRequest, _ results: inout [PredictionResult]) -> Bool

  @discardableResult
  func decodeEnglish(_ request: ConversionRequest, _ results: inout [PredictionResult]) -> Bool
}

extension PredictionSupplementalModel {
  public func correctComposition(_ request: ConversionRequest) -> [TypeCorrectedQuery]? { nil }
  public func populateTypeCorrectedQuery(
    _ request: ConversionRequest, _ results: inout [PredictionResult]
  ) {}
  public func rescoreResults(_ request: ConversionRequest, _ results: inout [PredictionResult]) {}
  @discardableResult
  public func predict(_ request: ConversionRequest, _ results: inout [PredictionResult]) -> Bool {
    false
  }
  public func getReadingAlignment(_ surface: String, _ reading: String) -> [(String, String)] {
    []
  }
  @discardableResult
  public func decodeEnglish(_ request: ConversionRequest, _ results: inout [PredictionResult])
    -> Bool
  { false }
}

/// No-op supplemental model (engine::SupplementalModelStub).
public final class PredictionSupplementalModelStub: PredictionSupplementalModel, Sendable {
  public static let shared = PredictionSupplementalModelStub()
  public init() {}
  public func isAvailable() -> Bool { false }
  public func postCorrect(_ request: ConversionRequest, _ results: inout [PredictionResult]) {}
}

/// The subset of engine::Modules used by the prediction code.
public protocol PredictionModules: ConverterModules {
  func getDataManager() -> DataManager
  func getConnector() -> Connector
  func getSegmenter() -> Segmenter
  func getDictionary() -> any DictionaryInterface
  func getSuffixDictionary() -> any DictionaryInterface
  func getSuggestionFilter() -> SuggestionFilter
  func getSingleKanjiDictionary() -> SingleKanjiDictionary
  func getZeroQueryDict() -> ZeroQueryDict
  func getZeroQueryNumberDict() -> ZeroQueryDict
}

extension PredictionModules {
  /// `GetSupplementalModel()` as the prediction-side interface.
  public func predictionSupplementalModel() -> any PredictionSupplementalModel {
    (getSupplementalModel() as? any PredictionSupplementalModel)
      ?? PredictionSupplementalModelStub.shared
  }
}
