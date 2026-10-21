// Port of mozc/src/engine/engine_converter_interface.h (3.35.6354).
//
// A class handling the converter on the session layer.
//
// Swift notes:
// - `std::shared_ptr<const commands::Request>` / `config::Config` are passed
//   as protobuf values (value semantics).
// - `size_t* committed_key_size` out-parameters are `inout Int`.
// - `commands::Output*` / `commands::Preedit*` out-parameters are `inout`.
// - The C++ convenience overloads of Convert / Suggest / Predict (default
//   context and/or preferences) are protocol-extension methods (they are not
//   requirements, so there is no dynamic-dispatch pitfall).
// - `Clone()` returns a new, independent instance.

import GenmaiProtocol

public struct ConversionPreferences: Sendable, Equatable {
  public var useHistory: Bool

  // This is a flag to check if the converter should return the suggestion
  // or not. Indeed, the design is actually twisted, because clients should
  // be able to avoid the invocation of EngineConverter::Suggest, if they'd
  // like. However, The current EngineConverter's architecture is too
  // complicated and has too many limitations to ensure the full state
  // transition. In order to support "skipping suggestion" for the performance
  // without current client's breakage in short period, this flag is
  // introduced.
  // TODO(hidehiko,komatsu): Remove this flag, when the full EngineConverter
  //   refactoring is done and gets safer for future development/extensions.
  public var requestSuggestion: Bool

  public init(useHistory: Bool = false, requestSuggestion: Bool = false) {
    self.useHistory = useHistory
    self.requestSuggestion = requestSuggestion
  }
}

/// `EngineConverterInterface::States` (bitmap of `State`).
public typealias EngineConverterStates = Int

/// `EngineConverterInterface::State`.
public enum EngineConverterState {
  public static let noState: EngineConverterStates = 0
  public static let composition: EngineConverterStates = 1
  public static let suggestion: EngineConverterStates = 2
  public static let prediction: EngineConverterStates = 4
  public static let conversion: EngineConverterStates = 8
}

/// Class handling ConverterInterface with a session state.  This class
/// support stateful operations related with the converter.
public protocol EngineConverterInterface: AnyObject {
  /// Check if the current state is in the state bitmap.
  func checkState(_ states: EngineConverterStates) -> Bool

  /// Indicate if the conversion session is active or not.  In general,
  /// Convert functions make it active and Cancel, Reset and Commit
  /// functions make it deactive.
  func isActive() -> Bool

  /// Return the default conversion preferences to be used for custom
  /// conversion.
  var conversionPreferences: ConversionPreferences { get }

  /// Sends a conversion request to the converter.
  func convert(
    _ composer: Composer, _ context: Genmai_Commands_Context, _ preferences: ConversionPreferences
  ) -> Bool

  /// Get reading text (e.g. from "猫" to "ねこ").
  func getReadingText(_ str: String, _ reading: inout String) -> Bool

  /// Send a transliteration request to the converter.
  func convertToTransliteration(_ composer: Composer, _ type: TransliterationType) -> Bool

  /// Convert the current composition to half-width characters.
  /// NOTE(komatsu): This function might be merged to ConvertToTransliteration.
  func convertToHalfWidth(_ composer: Composer) -> Bool

  /// Switch the composition to Hiragana, full-width Katakana or
  /// half-width Katakana by rotation.
  func switchKanaType(_ composer: Composer) -> Bool

  /// Sends a suggestion request to the converter.
  func suggest(
    _ composer: Composer, _ context: Genmai_Commands_Context, _ preferences: ConversionPreferences
  ) -> Bool

  /// Sends a prediction request to the converter.
  func predict(
    _ composer: Composer, _ context: Genmai_Commands_Context, _ preferences: ConversionPreferences
  ) -> Bool

  /// Clear conversion segments, but keep the context.
  func cancel()

  /// Clear conversion segments and the context.
  func reset()

  /// Fix the conversion with the current status.
  func commit(_ composer: Composer, _ context: Genmai_Commands_Context)

  /// Commit the current context and update the converter's state.
  /// Used for synchronizing context updates with the converter whenever the user
  /// performs an edit (e.g., via Backspace).
  func commitContext(_ composer: Composer, _ context: Genmai_Commands_Context)

  /// Fix the suggestion candidate.  True is returned if the selected
  /// candidate is successfully committed.
  func commitSuggestionByIndex(
    _ index: Int, _ composer: Composer, _ context: Genmai_Commands_Context,
    _ committedKeySize: inout Int
  ) -> Bool

  /// Select a candidate and commit the selected candidate.  True is
  /// returned if the selected candidate is successfully committed.
  func commitSuggestionById(
    _ id: Int, _ composer: Composer, _ context: Genmai_Commands_Context,
    _ committedKeySize: inout Int
  ) -> Bool

  /// Fix only the conversion of the first segment, and keep the rest.
  /// The caller should delete characters from composer based on returned
  /// |committed_key_size|.
  func commitFirstSegment(
    _ composer: Composer, _ context: Genmai_Commands_Context, _ committedKeySize: inout Int)

  /// Fix only the [0, focused] conversion segments, and keep the rest.
  /// The caller should delete characters from composer based on returned
  /// |committed_key_size|.
  func commitHeadToFocusedSegments(
    _ composer: Composer, _ context: Genmai_Commands_Context, _ committedKeySize: inout Int)

  /// Commit the preedit string represented by Composer.
  func commitPreedit(_ composer: Composer, _ context: Genmai_Commands_Context)

  /// Commit prefix of the preedit string represented by Composer.
  /// The caller should delete characters from composer based on returned
  /// |committed_size|.
  func commitHead(_ count: Int, _ composer: Composer, _ committedSize: inout Int)

  /// Revert the last "Commit" operation
  func revert()

  /// Delete candidate from user input history.
  /// Try to delete the current selected candidate if |id| is not specified.
  /// Returns false if the candidate was not found or deletion failed.
  func deleteCandidateFromHistory(_ id: Int?) -> Bool

  /// Move the focus of segments.
  func segmentFocusRight()
  func segmentFocusLast()
  func segmentFocusLeft()
  func segmentFocusLeftEdge()

  /// Resize the focused segment.
  func segmentWidthExpand(_ composer: Composer)
  func segmentWidthShrink(_ composer: Composer)

  /// Move the focus of candidates.
  func candidateNext(_ composer: Composer)
  func candidateNextPage()
  func candidatePrev()
  func candidatePrevPage()
  /// Move the focus to the candidate represented by the id.
  func candidateMoveToId(_ id: Int, _ composer: Composer)
  /// Move the focus to the index from the beginning of the current page.
  func candidateMoveToPageIndex(_ index: Int)
  /// Move the focus to the candidate represented by the shortcut.  If
  /// the shortcut is not bound with any candidate, false is returned.
  /// (`char` is a single byte; pass its ASCII value.)
  func candidateMoveToShortcut(_ shortcut: UInt8) -> Bool

  /// Operation for the candidate list.
  func setCandidateListVisible(_ visible: Bool)

  /// Fill protocol buffers and update internal status.
  func popOutput(_ composer: Composer, _ output: inout Genmai_Commands_Output)

  /// Fill preedit
  func fillPreedit(_ composer: Composer, _ preedit: inout Genmai_Commands_Preedit)

  /// Fill protocol buffers
  func fillOutput(_ composer: Composer, _ output: inout Genmai_Commands_Output)

  /// Set setting by the request.
  /// Currently this is especially for EngineConverter.
  func setRequest(_ request: Genmai_Commands_Request)

  /// Set setting by the config.
  /// Currently this is especially for EngineConverter.
  func setConfig(_ config: Genmai_Config_Config)

  /// Update the internal state by the context.
  func onStartComposition(_ context: Genmai_Commands_Context)

  /// Clone instance.
  func clone() -> any EngineConverterInterface

  func setSelectionShortcut(_ selectionShortcut: Genmai_Config_Config.SelectionShortcut)

  func setUseCascadingWindow(_ useCascadingWindow: Bool)
}

extension EngineConverterInterface {
  public func convert(_ composer: Composer, _ context: Genmai_Commands_Context) -> Bool {
    convert(composer, context, conversionPreferences)
  }
  public func convert(_ composer: Composer, _ preferences: ConversionPreferences) -> Bool {
    convert(composer, Genmai_Commands_Context(), preferences)
  }
  public func convert(_ composer: Composer) -> Bool {
    convert(composer, Genmai_Commands_Context(), conversionPreferences)
  }

  public func suggest(_ composer: Composer, _ context: Genmai_Commands_Context) -> Bool {
    suggest(composer, context, conversionPreferences)
  }
  public func suggest(_ composer: Composer, _ preferences: ConversionPreferences) -> Bool {
    suggest(composer, Genmai_Commands_Context(), preferences)
  }
  public func suggest(_ composer: Composer) -> Bool {
    suggest(composer, Genmai_Commands_Context(), conversionPreferences)
  }

  public func predict(_ composer: Composer, _ context: Genmai_Commands_Context) -> Bool {
    predict(composer, context, conversionPreferences)
  }
  public func predict(_ composer: Composer, _ preferences: ConversionPreferences) -> Bool {
    predict(composer, Genmai_Commands_Context(), preferences)
  }
  public func predict(_ composer: Composer) -> Bool {
    predict(composer, Genmai_Commands_Context(), conversionPreferences)
  }
}
