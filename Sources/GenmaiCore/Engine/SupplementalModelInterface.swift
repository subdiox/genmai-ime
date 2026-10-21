// Port of mozc/src/engine/supplemental_model_interface.h (3.35.6354).
//
// Deviations from C++:
// - The lower layers abstract the parts of this interface they use as partial
//   protocols (ConverterSupplementalModel, ReadingAlignmentSupplementalModel,
//   UserHistorySupplementalModel, PredictionSupplementalModel).
//   `SupplementalModelInterface` refines all of them (through
//   PredictionSupplementalModel) and adds the loading functions, so one
//   supplemental model object serves every layer.
// - The C++ default implementations live in `SupplementalModelStub`, an open
//   base class that implements every requirement. Custom models subclass it
//   and `override` (see the protocol default dispatch pitfall in CLAUDE.md:
//   requirements defaulted only in a protocol extension would not dispatch to
//   subclass methods through `any SupplementalModelInterface`).
// - `absl::Span<Result>` parameters are `inout [PredictionResult]` (the number
//   of results must not be changed).

import GenmaiBase
import GenmaiProtocol

/// Abstract interface of supplemental model.
public protocol SupplementalModelInterface: PredictionSupplementalModel {
  /// Loads supplemental model asynchronously defined in the `request`.
  /// Returns false if the LoadAsync is already running.
  @discardableResult
  func loadAsync(_ request: Genmai_EngineReloadRequest) -> Bool

  /// Loads supplemental model defined in the `request`.
  @discardableResult
  func load(_ request: Genmai_EngineReloadRequest) -> Genmai_EngineReloadResponse

  /// Destroys old models that were replaced during reload.
  func clearOldModels()
}

/// engine::SupplementalModelStub: the default (no-op) implementation of every
/// SupplementalModelInterface function. Subclass it to implement a model.
open class SupplementalModelStub: SupplementalModelInterface, @unchecked Sendable {
  // @unchecked Sendable: the stub has no state; subclasses are responsible for
  // their own synchronization.

  public init() {}

  open func loadAsync(_ request: Genmai_EngineReloadRequest) -> Bool { false }

  open func load(_ request: Genmai_EngineReloadRequest) -> Genmai_EngineReloadResponse {
    Genmai_EngineReloadResponse()
  }

  open func clearOldModels() {}

  /// Returns true if supplemental model is available.
  /// Useful to run intensive operations before using supplemental model.
  open func isAvailable() -> Bool { false }

  /// Performs spelling correction for composition (pre-edit) Hiragana
  /// sequence. Returns empty result when no correction is required.
  /// Returns nil when the composition spellchecker is not enabled/available.
  open func correctComposition(_ request: ConversionRequest) -> [TypeCorrectedQuery]? { nil }

  /// Populates the typing correction penalty and attribute to `results`.
  open func populateTypeCorrectedQuery(
    _ request: ConversionRequest, _ results: inout [PredictionResult]
  ) {}

  /// Performs general post correction on `results`.
  open func postCorrect(_ request: ConversionRequest, _ results: inout [PredictionResult]) {}

  /// Performs rescoring for `results` given the context `results`.
  open func rescoreResults(_ request: ConversionRequest, _ results: inout [PredictionResult]) {}

  /// Performs next word/phrase prediction given the context in `request`.
  /// Results are appended to `results`. Returns true if prediction was
  /// performed.
  @discardableResult
  open func predict(_ request: ConversionRequest, _ results: inout [PredictionResult]) -> Bool {
    false
  }

  /// Returns character-by-mora reading to surface alignment.
  /// {東,とう},{京,きょう} = GetReadingAlignment("東京", "とうきょう")
  /// Returns empty list when no alignment is available.
  open func getReadingAlignment(_ surface: String, _ reading: String) -> [(String, String)] { [] }

  @discardableResult
  open func decodeEnglish(_ request: ConversionRequest, _ results: inout [PredictionResult])
    -> Bool
  { false }
}
