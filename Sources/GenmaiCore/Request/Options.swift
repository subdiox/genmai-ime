// Port of mozc/src/request/options.h (3.35.6354).

public let kMaxConversionCandidatesSize = 200

public enum RequestType: Int, Sendable, CustomStringConvertible {
  case conversion  // normal conversion
  case reverseConversion  // reverse conversion
  case prediction  // show prediction with user tab key
  case suggestion  // show prediction automatically
  case partialPrediction  // show prediction using the text before cursor
  case partialSuggestion  // show suggestion using the text before cursor

  /// operator<< prints the integer value.
  public var description: String { String(rawValue) }
}

public enum ComposerKeySelection: Int, Sendable {
  /// Use Composer::GetQueryForConversion() to generate conversion key. This
  /// option uses the exact composition which user sees, e.g., "とうk".
  case conversionKey

  /// Use Composer::GetQueryForPrediction() to generate conversion key. This
  /// option trims the trailing unresolved romaji. For example, if composition
  /// is "とうk", the conversion key becomes "とう". This option is mainly used
  /// in dictionary_predictor.cc for realtime conversion.
  case predictionKey

  // TODO(team): We may want to implement other options. For instance,
  // Composer::GetQueriesForPrediction() expands the trailing romaji to a set
  // of possible hiragana.
}

/// Options must be trivially copyable to get hash value directly.
/// Since it is small (~40 bytes), passing and returning by value is preferred
/// to avoid reference lifetime issues.
public struct ConversionOptions: Sendable, Hashable {
  public var requestType: RequestType = .conversion

  /// Which composer's method to use for conversion key; see the comment around
  /// the definition of ComposerKeySelection above.
  public var composerKeySelection: ComposerKeySelection = .conversionKey

  public var maxConversionCandidatesSize: Int = kMaxConversionCandidatesSize
  public var maxUserHistoryPredictionCandidatesSize: Int = 3
  public var maxUserHistoryPredictionCandidatesSizeForZeroQuery: Int = 4
  public var maxDictionaryPredictionCandidatesSize: Int = 20

  /// If true, insert a top candidate from the actual (non-immutable) converter
  /// to realtime conversion results. Note that setting this true causes a big
  /// performance loss (3 times slower).
  public var useActualConverterForRealtimeConversion = false

  /// Don't use this flag directly. This flag is used by DictionaryPredictor to
  /// skip some heavy rewriters, such as UserBoundaryHistoryRewriter and
  /// TransliterationRewriter.
  /// TODO(noriyukit): Fix such a hacky handling for realtime conversion.
  public var skipSlowRewriters = false

  /// If true, partial candidates are created on prediction/suggestion.
  /// For example, "私の" is created from composition "わたしのなまえ".
  public var createPartialCandidates = false

  /// If false, stop using user history for conversion.
  /// This is used for supporting CONVERT_WITHOUT_HISTORY command.
  /// Please refer to session/internal/keymap.h
  public var enableUserHistoryForConversion = true

  /// If true, enable kana modifier insensitive conversion.
  public var kanaModifierInsensitiveConversion = true

  /// If true, use conversion_segment(0).key() instead of ComposerData.
  /// TODO(b/365909808): Create a new string field to store the key.
  public var useAlreadyTypingCorrectedKey = false

  /// Transition cost bonus for particle omission.
  public var particleOmissionTransitionCostBonus: Int = 0

  /// Input mode for key corrector.
  public enum InputMode: Int, Sendable {
    case roman
    case kana
  }
  public var inputMode: InputMode = .roman

  /// Spelling correction. Populated from Config.
  public var useSpellingCorrection = true

  /// Zip code conversion. Populated from Config.
  public var useZipCodeConversion = true

  /// T13N conversion. Populated from Config.
  public var useT13nConversion = true

  /// Enables incognito mode even when Config.incognito_mode() or
  /// Request.is_incognito_mode() is false. Use this flag to dynamically change
  /// the incognito_mode per client request.
  public var incognitoMode = false

  /// Overrides the bos_id to a specific POS id to specify the context
  /// information. Note that the bos_id must be in the valid range.
  /// POS id 0 is reserved for the default BOS/EOS.
  public var bosId: UInt16 = 0

  /// Disables to add prefix penalty.
  /// Used to calculate the cost of a suffix of a word.
  public var disablePrefixPenalty = false

  /// This conversion request is called by predictor for realtime conversion.
  public var usedInPredictorRealtimeConversion = false

  public init() {}
}
