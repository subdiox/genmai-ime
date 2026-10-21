// Port of mozc/src/composer/composer.{h,cc} (3.35.6354).
//
// Interactive composer from a Roman string to a Hiragana string
//
// Deviations from C++:
// - `Composer` and `ComposerData` are value types (the C++ classes are
//   copyable and movable). The shared_ptr<const Request/Config> members are
//   protobuf values (copy-on-write); the Table is shared by reference.
// - absl::btree_set<std::string> results are byte-ordered, unique `[String]`.
// - Output parameters (`std::string*`, `Transliterations*`) become return
//   values or `inout` parameters.

import Foundation
import GenmaiBase
import GenmaiProtocol


private func getTransliterator(_ compMode: TransliterationType) -> Transliterators.Transliterator {
  switch compMode {
  case .halfAscii, .halfAsciiUpper, .halfAsciiLower, .halfAsciiCapitalized:
    return .halfAscii

  case .fullAscii, .fullAsciiUpper, .fullAsciiLower, .fullAsciiCapitalized:
    return .fullAscii

  case .halfKatakana:
    return .halfKatakana

  case .fullKatakana:
    return .fullKatakana

  case .hiragana:
    return .hiragana
  }
}

private func getTransliterationType(
  _ transliterator: Transliterators.Transliterator, _ defaultType: TransliterationType
) -> TransliterationType {
  if transliterator == .hiragana {
    return .hiragana
  }
  if transliterator == .halfAscii {
    return .halfAscii
  }
  if transliterator == .fullAscii {
    return .fullAscii
  }
  if transliterator == .fullKatakana {
    return .fullKatakana
  }
  if transliterator == .halfKatakana {
    return .halfKatakana
  }
  return defaultType
}

private func transliterate(_ mode: TransliterationType, _ input: String) -> String {
  // When the mode is HALF_KATAKANA, Full width ASCII is also
  // transformed.
  if mode == .halfKatakana {
    let katakana = Japanese.hiraganaToKatakana(input)
    return Japanese.fullWidthToHalfWidth(katakana)
  }

  switch mode {
  case .halfAscii:
    return Japanese.fullWidthAsciiToHalfWidthAscii(input)
  case .halfAsciiUpper:
    var output = Japanese.fullWidthAsciiToHalfWidthAscii(input)
    Util.upperString(&output)
    return output
  case .halfAsciiLower:
    var output = Japanese.fullWidthAsciiToHalfWidthAscii(input)
    Util.lowerString(&output)
    return output
  case .halfAsciiCapitalized:
    var output = Japanese.fullWidthAsciiToHalfWidthAscii(input)
    Util.capitalizeString(&output)
    return output
  case .fullAscii:
    return Japanese.halfWidthAsciiToFullWidthAscii(input)
  case .fullAsciiUpper:
    var output = Japanese.halfWidthAsciiToFullWidthAscii(input)
    Util.upperString(&output)
    return output
  case .fullAsciiLower:
    var output = Japanese.halfWidthAsciiToFullWidthAscii(input)
    Util.lowerString(&output)
    return output
  case .fullAsciiCapitalized:
    var output = Japanese.halfWidthAsciiToFullWidthAscii(input)
    Util.capitalizeString(&output)
    return output
  case .fullKatakana:
    return Japanese.hiraganaToKatakana(input)
  case .hiragana:
    return input
  case .halfKatakana:
    return input  // handled above
  }
}

private func getTransliterationTypeFromCompositionMode(_ mode: Genmai_Commands_CompositionMode)
  -> TransliterationType
{
  switch mode {
  case .hiragana:
    return .hiragana
  case .fullKatakana:
    return .fullKatakana
  case .halfAscii:
    return .halfAscii
  case .fullAscii:
    return .fullAscii
  case .halfKatakana:
    return .halfKatakana
  default:
    // commands::DIRECT or invalid mode.
    GenmaiLog.error("Invalid CompositionMode: \(mode)")
    return .hiragana
  }
}

// A map used in `GetQueriesForPrediction()`. The key is a modified Hiragana
// and the values are its related Hiragana characters that can be cycled by
// hitting the modifier key. For instance, there's a modification cycle
// つ -> っ -> づ -> つ. For this cycle, the multimap contains:
//   っ: [つ, づ]
//   づ: [つ, っ]
// If the composition ends with a key in this map, its corresponding values
// are removed from the expansion produced by `GetQueryForPrediction()`,
// whereby we can suppress prediction from unmodified key when one modified a
// character explicitly (e.g., we don't want to suggest words starting with
// "さ" when one typed "ざ" with modified key).
private let kModifierRemovalMap: [(String, String)] = [
  ("ぁ", "あ"), ("ぃ", "い"), ("ぅ", "う"), ("ぅ", "ゔ"), ("ゔ", "う"),
  ("ゔ", "ぅ"), ("ぇ", "え"), ("ぉ", "お"), ("が", "か"), ("ぎ", "き"),
  ("ぐ", "く"), ("げ", "け"), ("ご", "こ"), ("ざ", "さ"), ("じ", "し"),
  ("ず", "す"), ("ぜ", "せ"), ("ぞ", "そ"), ("だ", "た"), ("ぢ", "ち"),
  ("づ", "つ"), ("づ", "っ"), ("っ", "つ"), ("っ", "づ"), ("で", "て"),
  ("ど", "と"), ("ば", "は"), ("ば", "ぱ"), ("ぱ", "は"), ("ぱ", "ば"),
  ("び", "ひ"), ("び", "ぴ"), ("ぴ", "ひ"), ("ぴ", "び"), ("ぶ", "ふ"),
  ("ぶ", "ぷ"), ("ぷ", "ふ"), ("ぷ", "ぶ"), ("べ", "へ"), ("べ", "ぺ"),
  ("ぺ", "へ"), ("ぺ", "べ"), ("ぼ", "ほ"), ("ぼ", "ぽ"), ("ぽ", "ほ"),
  ("ぽ", "ぼ"), ("ゃ", "や"), ("ゅ", "ゆ"), ("ょ", "よ"), ("ゎ", "わ"),
]

private func removeExpandedCharsForModifier(
  _ asis: String, _ base: String, _ expanded: inout [String]
) {
  if !asis.hasBytePrefix(base) {
    GenmaiLog.error("base is not a prefix of asis.")
    return
  }

  let trailing = ComposerBytes.substr(asis, base.utf8.count)
  for (key, c) in kModifierRemovalMap where ComposerBytes.equal(key, trailing) {
    ComposerBytes.eraseSorted(&expanded, c)
  }
}

private let kMaxPreeditLength = 256

private enum Common {
  static func getStringForPreedit(
    _ composition: Composition, _ inputFieldType: Genmai_Commands_Context.InputFieldType
  ) -> String {
    var output = composition.getString()
    _ = Composer.transformCharactersForNumbers(&output)
    // If the input field type needs half ascii characters,
    // perform conversion here.
    // Note that this purpose is also achieved by the client by setting
    // input type as "half ascii".
    // But the architecture of Mozc expects the server to handle such character
    // width management.
    // In addition, we also think about PASSWORD field type.
    // we can prepare NUMBER and TEL keyboard layout, which has
    // "half ascii" composition mode. This works.
    // But we will not have PASSWORD only keyboard. We will share the basic
    // keyboard on usual and password mode
    // so such hacky code cannot be applicable.
    // TODO(matsuzakit): Move this logic to another appopriate location.
    // SetOutputMode() is not currently applicable but ideally it is
    // better location than here.
    if inputFieldType == .number || inputFieldType == .password || inputFieldType == .tel {
      output = Japanese.fullWidthAsciiToHalfWidthAscii(output)
    }
    return output
  }

  static func getQueryForConversion(_ composition: Composition) -> String {
    var baseOutput = composition.getStringWithTrimMode(.fix)
    _ = Composer.transformCharactersForNumbers(&baseOutput)
    return Japanese.fullWidthAsciiToHalfWidthAscii(baseOutput)
  }

  // Determine which query is suitable for a prediction query and return
  // its pointer.
  // Example:
  // = Romanji Input =
  // ("もz", "も") -> "も"  // a part of romanji should be trimed.
  // ("もzky", "もz") -> "もzky"  // a user might intentionally typed them.
  // ("z", "") -> "z"      // ditto.
  // = Kana Input =
  // ("か", "") -> "か"  // a part of kana (it can be "が") should not be trimed.
  // Returns true if asis_query should be used (false: trimed_query).
  static func useAsisQueryForPrediction(_ asisQuery: String, _ trimedQuery: String) -> Bool {
    // If the sizes are equal, there is no matter.
    if asisQuery.utf8.count == trimedQuery.utf8.count {
      return true
    }

    // Get the different part between asis_query and trimed_query.  For
    // example, "ky" is the different part where asis_query is "もzky"
    // and trimed_query is "もz".
    let asisTail = ComposerBytes.substr(asisQuery, trimedQuery.utf8.count)

    // If the different part is not an alphabet, asis_query is used.
    // This check is mainly used for Kana Input.
    let asisTailType = Util.getScriptType(asisTail)
    if asisTailType != .alphabet {
      return true
    }

    // If the trimed_query is empty and asis_query is alphabet, an asis
    // string is used because the query may be typed intentionally.
    if trimedQuery.isEmpty {  // alphabet???
      let asisType = Util.getScriptType(asisQuery)
      if asisType == .alphabet {
        return true
      } else {
        return false
      }
    }

    // Now there are two patterns: ("もzk", "もz") and ("もずk", "もず").
    // We assume "もzk" is user's intentional query, but "もずk" is not.
    // So our results are:
    // ("もzk", "もz") => "もzk" and ("もずk", "もず") => "もず".
    let trimedTail = Util.utf8SubString(trimedQuery, Util.charsLen(trimedQuery) - 1)
    let trimedTailType = Util.getScriptType(trimedTail)
    if trimedTailType == .alphabet {
      return true
    } else {
      return false
    }
  }

  static func getQueryForPrediction(
    _ composition: Composition, _ inputMode: TransliterationType
  ) -> String {
    let asisQuery = composition.getStringWithTrimMode(.asis)

    switch inputMode {
    case .halfAscii:
      return asisQuery
    case .fullAscii:
      return Japanese.fullWidthAsciiToHalfWidthAscii(asisQuery)
    default:
      break
    }

    let trimedQuery = composition.getStringWithTrimMode(.trim)

    // NOTE(komatsu): This is a hack to go around the difference
    // expectation between Romanji-Input and Kana-Input.  "かn" in
    // Romaji-Input should be "か" while "あか" in Kana-Input should be
    // "あか", although "かn" and "あか" have the same properties.  An
    // ideal solution is to expand the ambguity and pass all of them to
    // the converter. (e.g. "かn" -> ["かな",..."かの", "かん", ...] /
    // "あか" -> ["あか", "あが"])
    var baseQuery = useAsisQueryForPrediction(asisQuery, trimedQuery) ? asisQuery : trimedQuery
    _ = Composer.transformCharactersForNumbers(&baseQuery)
    return Japanese.fullWidthAsciiToHalfWidthAscii(baseQuery)
  }

  static func getQueriesForPrediction(
    _ composition: Composition, _ inputMode: TransliterationType
  ) -> (String, [String]) {
    // In case of the Latin input modes, we don't perform expansion.
    switch inputMode {
    case .halfAscii, .fullAscii:
      return (getQueryForPrediction(composition, inputMode), [])
    default:
      break
    }

    var (baseQuery, expanded) = composition.getExpandedStrings()

    // The above `GetExpandedStrings` generates expansion for modifier key as
    // well, e.g., if the composition is "ざ", `expanded` contains "さ" too.
    // However, "ざ" is usually composed by explicitly hitting the modifier key.
    // So we don't want to generate prediction from "さ" in this case. The
    // following code removes such unnecessary expansion.
    let asis = composition.getStringWithTrimMode(.asis)
    removeExpandedCharsForModifier(asis, baseQuery, &expanded)

    baseQuery = Japanese.fullWidthAsciiToHalfWidthAscii(baseQuery)
    return (baseQuery, expanded)
  }

  static func getStringForTypeCorrection(_ composition: Composition) -> String {
    composition.getStringWithTrimMode(.asis)
  }

  static func getTransliteratedText(
    _ composition: Composition, _ t12r: Transliterators.Transliterator,
    _ position: Int, _ size: Int
  ) -> String {
    let fullBase = composition.getStringWithTransliterator(t12r)

    let t13nStart = composition.convertPosition(position, .local, t12r)
    let t13nEnd = composition.convertPosition(position + size, .local, t12r)
    let t13nSize = t13nEnd - t13nStart

    // size_t arithmetic in C++: a negative size wraps to npos (to the end).
    return String(Util.utf8SubString(fullBase, t13nStart, t13nSize < 0 ? Int.max : t13nSize))
  }

  static func getRawSubString(_ composition: Composition, _ position: Int, _ size: Int) -> String {
    getTransliteratedText(composition, .rawString, position, size)
  }

  static func getRawString(_ composition: Composition) -> String {
    getRawSubString(composition, 0, composition.getLength())
  }

  static func getSubTransliteration(
    _ composition: Composition, _ type: TransliterationType, _ position: Int, _ size: Int
  ) -> String {
    let t12r = getTransliterator(type)
    let result = getTransliteratedText(composition, t12r, position, size)
    return transliterate(type, result)
  }

  static func getSubTransliterations(
    _ composition: Composition, _ position: Int, _ size: Int,
    _ transliterations: inout Transliterations
  ) {
    for t13nType in transliterationTypeArray {
      let t13n = getSubTransliteration(composition, t13nType, position, size)
      transliterations.append(t13n)
    }
  }

  static func getTransliterations(_ composition: Composition, _ t13ns: inout Transliterations) {
    getSubTransliterations(composition, 0, composition.getLength(), &t13ns)
  }
}

private let kSharedDefaultRequest = Genmai_Commands_Request()

public func getSharedDefaultRequest() -> Genmai_Commands_Request {
  kSharedDefaultRequest
}

/// ComposerData is a data structure that represents the current state of the
/// composer. It is used by Converter, Predictor and Rewriters as a const
/// object.
public struct ComposerData: Sendable {
  /// Composition copied from the Composer as a snapshot.
  public private(set) var composition: Composition

  /// Cursor position.
  private var position = 0

  /// Input mode of IME (e.g. HIRAGANA, HALF_ASCII, etc.)
  private var inputMode: TransliterationType = .hiragana

  /// Type of the input field to input texts.
  private var inputFieldType: Genmai_Commands_Context.InputFieldType = .normal

  /// The original text for the composition.
  /// The value is usually empty, and used for reverse conversion.
  public private(set) var sourceText: String

  /// Example:
  ///   {{"かん字", 0.99}, {"かlv字", 0.01}}
  /// Please refer to commands.proto
  private var compositionsForHandwriting: [Genmai_Commands_SessionCommand.CompositionEvent]

  public init(
    _ composition: Composition, _ position: Int, _ inputMode: TransliterationType,
    _ inputFieldType: Genmai_Commands_Context.InputFieldType, _ sourceText: String,
    _ compositionsForHandwriting: [Genmai_Commands_SessionCommand.CompositionEvent]
  ) {
    self.composition = composition
    self.position = position
    self.inputMode = inputMode
    self.inputFieldType = inputFieldType
    self.sourceText = sourceText
    self.compositionsForHandwriting = compositionsForHandwriting
  }

  public func getInputMode() -> TransliterationType { inputMode }

  /// Returns a preedit string with user's preferences.
  public func getStringForPreedit() -> String {
    Common.getStringForPreedit(composition, inputFieldType)
  }

  /// Returns a conversion query normalized ascii characters in half width
  public func getQueryForConversion() -> String {
    Common.getQueryForConversion(composition)
  }

  /// Returns a prediction query trimmed the tail alphabet characters.
  public func getQueryForPrediction() -> String {
    Common.getQueryForPrediction(composition, inputMode)
  }

  /// Returns a expanded prediction query.
  public func getQueriesForPrediction() -> (String, [String]) {
    Common.getQueriesForPrediction(composition, inputMode)
  }

  /// Returns a string to be used for type correction.
  public func getStringForTypeCorrection() -> String {
    Common.getStringForTypeCorrection(composition)
  }

  public func getLength() -> Int { composition.getLength() }
  public func getCursor() -> Int { position }

  public func getHandwritingCompositions() -> [Genmai_Commands_SessionCommand.CompositionEvent] {
    compositionsForHandwriting
  }

  /// Returns raw input from a user.
  /// The main purpose is Transliteration.
  public func getRawString() -> String {
    Common.getRawString(composition)
  }

  /// Returns substring of raw input.  The position and size is based on the
  /// composed string.  For example, when [さ|sa][し|shi][み|mi] is the
  /// composition, GetRawSubString(0, 2) returns "sashi".
  public func getRawSubString(_ position: Int, _ size: Int) -> String {
    Common.getRawSubString(composition, position, size)
  }

  /// Generate transliterations.
  public func getTransliterations(_ t13ns: inout Transliterations) {
    Common.getTransliterations(composition, &t13ns)
  }

  /// Generate substrings of transliterations.
  public func getSubTransliterations(_ position: Int, _ size: Int, _ t13ns: inout Transliterations) {
    Common.getSubTransliterations(composition, position, size, &t13ns)
  }
}

private enum Script {
  case alphabet  // alphabet characters or symbols
  case number  // 0 - 9, "０" - "９"
  case jaHyphen  // "ー"
  case jaComma  // "、"
  case jaPeriod  // "。"
  case other
}

private func isAlphabetOrNumber(_ script: Script) -> Bool {
  script == .alphabet || script == .number
}

private let kEmptyComposerData = ComposerData(
  Composition(Table.getSharedDefaultTable()), 0, .hiragana, .normal, "", [])

/// Composer is a class that manages the composing text. It provides methods to
/// edit the text by users. Composer creates ComposerData as the snapshot of
/// the current state of the composer.
public struct Composer: Sendable {
  /// Pseudo commands in composer.
  public enum InternalCommand: Sendable {
    case rewind
    case stopKeyToggling
  }

  private var position = 0
  private var inputMode: TransliterationType = .hiragana
  private var outputMode: TransliterationType = .hiragana
  // On reset, comeback_input_mode_ is used as the input mode.
  private var comebackInputMode: TransliterationType = .hiragana
  // Type of the input field to input texts.
  private var inputFieldType: Genmai_Commands_Context.InputFieldType = .normal

  public private(set) var shiftedSequenceCount = 0

  /// The original text for the composition.  The value is usually
  /// empty, and used for reverse conversion.
  public var sourceText = ""

  public var maxLength = kMaxPreeditLength

  private var request: Genmai_Commands_Request
  private var config: Genmai_Config_Config

  // Though we would like to avoid shared object, Table is not copyable so
  // there is no other way to share them at this moment.
  private var table: Table

  private var composition: Composition

  // Timestamp of last modified.
  private var timestampMsec: Int64 = 0

  /// If the duration between key inputs is more than timeout_threadhols_msec_,
  /// the STOP_KEY_TOGGLING event is sent before the next key input.
  /// If the value is 0, STOP_KEY_TOGGLING is not sent.
  public var timeoutThresholdMsec: Int32 = 0

  // Whether the next insertion is the beginning of typing after an
  // editing command like SetInputMode or not.  Some conversion rules
  // refer this state.  Assuming the input events are
  // "abc<left-cursor>d", when "a" or "d" is typed, this value should
  // be true.  When "b" or "c" is typed, the value should be false.
  public private(set) var isNewInput = true

  // Example:
  //   {{"かん字", 0.99}, {"かlv字", 0.01}}
  // Please refer to commands.proto
  private var compositionsForHandwriting: [Genmai_Commands_SessionCommand.CompositionEvent] = []

  public init() {
    self.init(
      Table.getSharedDefaultTable(), getSharedDefaultRequest(),
      ConfigHandler.getSharedDefaultConfig())
  }

  /// This constructor is for testing.
  public init(_ request: Genmai_Commands_Request, _ config: Genmai_Config_Config) {
    self.init(Table.getSharedDefaultTable(), request, config)
  }

  public init(_ table: Table, _ request: Genmai_Commands_Request, _ config: Genmai_Config_Config) {
    self.request = request
    self.config = config
    self.table = table
    self.composition = Composition(table)
    setInputMode(.hiragana)
    reset()
  }

  /// Returns a reference of empty ComposerData used for placeholder.
  public static func emptyComposerData() -> ComposerData {
    kEmptyComposerData
  }

  /// Return a ComposerData with the current state of the composer.
  public func createComposerData() -> ComposerData {
    ComposerData(
      composition, position, inputMode, inputFieldType, sourceText, compositionsForHandwriting)
  }

  /// Reset all composing data except table.
  public mutating func reset() {
    editErase()
    resetInputMode()
    setOutputMode(.hiragana)
    sourceText = ""
    timeoutThresholdMsec = config.composingTimeoutThresholdMsec
    compositionsForHandwriting.removeAll()
  }

  /// Reset input mode.  When the current input mode is
  /// HalfAlphanumeric by pressing shifted alphabet, this function
  /// revert the input mode from HalfAlphanumeric to the previous input
  /// mode.
  public mutating func resetInputMode() { setInputMode(comebackInputMode) }

  /// Reload the configuration.
  public mutating func reloadConfig() {
    // Do nothing at this moment.
  }

  /// Check the preedit string is empty or not.
  public func isEmpty() -> Bool { getLength() == 0 }

  public mutating func setTable(_ table: Table) {
    self.table = table
    composition.setTable(table)
  }

  public mutating func setRequest(_ request: Genmai_Commands_Request) {
    self.request = request
  }

  public mutating func setConfig(_ config: Genmai_Config_Config) {
    self.config = config
  }

  public mutating func setInputMode(_ mode: TransliterationType) {
    comebackInputMode = mode
    inputMode = mode
    shiftedSequenceCount = 0
    isNewInput = true
    composition.setInputMode(getTransliterator(mode))
  }

  public mutating func setTemporaryInputMode(_ mode: TransliterationType) {
    // Set comeback_input_mode_ to revert back the current input mode.
    comebackInputMode = inputMode
    inputMode = mode
    shiftedSequenceCount = 0
    isNewInput = true
    composition.setInputMode(getTransliterator(mode))
  }

  public mutating func setInputFieldType(_ type: Genmai_Commands_Context.InputFieldType) {
    inputFieldType = type
  }

  public func getInputFieldType() -> Genmai_Commands_Context.InputFieldType { inputFieldType }

  /// Update the input mode considering the input modes of the
  /// surrounding characters.
  /// If the input mode should not be changed based on the surrounding text,
  /// do not call this method (e.g. CursorToEnd, CursorToBeginning).
  public mutating func updateInputMode() {
    if position != 0 && request.updateInputModeFromSurroundingText {
      let currentT12r = composition.getTransliterator(position)
      if position == composition.getLength()
        || currentT12r == composition.getTransliterator(position + 1)
      {
        // - The cursor is at the tail of composition.
        //   Use last character's transliterator as the input mode.
        // - If the current cursor is between the same character type like
        //   "A|B" and "あ|い", the input mode follows the character type.
        inputMode = getTransliterationType(currentT12r, comebackInputMode)
        shiftedSequenceCount = 0
        isNewInput = true
        composition.setInputMode(getTransliterator(inputMode))
        return
      }
    }

    // Set the default input mode.
    setInputMode(comebackInputMode)
  }

  public func getInputMode() -> TransliterationType { inputMode }
  public func getComebackInputMode() -> TransliterationType { comebackInputMode }

  public mutating func toggleInputMode() {
    if inputMode == .hiragana {
      // TODO(komatsu): Refer user's preference.
      setInputMode(.halfAscii)
    } else {
      setInputMode(.hiragana)
    }
  }

  public func getOutputMode() -> TransliterationType { outputMode }

  public mutating func setOutputMode(_ mode: TransliterationType) {
    outputMode = mode
    composition.setTransliterator(0, composition.getLength(), getTransliterator(mode))
    position = composition.getLength()
  }

  // Change input mode temporarily according to the current context and
  // the given input character.
  // This function have a bug when key has characters input with Preedit.
  // Expected behavior: InsertPreedit("A") + InsertKey("a") -> "Aあ"
  // Actual behavior:   InsertPreedit("A") + InsertKey("a") -> "Aa"
  private mutating func applyTemporaryInputMode(_ input: String, _ capsLocked: Bool) {
    let switchMode = config.shiftKeyModeSwitch

    // When input is not an ASCII code, reset the input mode to the one before
    // temporary input mode.
    guard let first = input.utf8.first, Strings.oneCharLen(first) == 1 else {
      // Call SetInputMode() only when the current input mode is temporary, which
      // is detected by the if-condition below.  Without this check,
      // SetInputMode() is called always for multi-byte charactesrs.  This causes
      // a bug that multi-byte characters is inserted to a new chunk because
      // |is_new_input_| is set to true in SetInputMode(); see b/31444698.
      if comebackInputMode != inputMode {
        setInputMode(comebackInputMode)
      }
      return
    }

    // Input is an ASCII code.
    // we use first character to determine temporary input mode.
    let key = first
    let isUpperKey = 0x41 <= key && key <= 0x5A  // 'A' <= key <= 'Z'
    let isLowerKey = 0x61 <= key && key <= 0x7A  // 'a' <= key <= 'z'
    let alphaWithShift = (!capsLocked && isUpperKey) || (capsLocked && isLowerKey)
    let alphaWithoutShift = (capsLocked && isUpperKey) || (!capsLocked && isLowerKey)

    if alphaWithShift {
      if switchMode == .asciiInputMode {
        if inputMode == .halfAscii || inputMode == .fullAscii {
          // Do nothing.
        } else {
          setTemporaryInputMode(.halfAscii)
        }
      } else if switchMode == .katakanaInputMode {
        if inputMode == .hiragana {
          setTemporaryInputMode(.fullKatakana)
        } else {
          // Do nothing.
        }
      }
      shiftedSequenceCount += 1
    } else if alphaWithoutShift {
      // When shifted input continues, the next lower input is the end
      // of temporary half-width Ascii input.
      if shiftedSequenceCount > 1 && switchMode == .asciiInputMode {
        setInputMode(comebackInputMode)
      }
      if switchMode == .katakanaInputMode {
        setInputMode(comebackInputMode)
      }
      shiftedSequenceCount = 0
    } else {
      // If the key is not an alphabet, reset shifted_sequence_count_
      // because "Continuous shifted input" feature should be reset
      // when the input meets non-alphabet character.
      shiftedSequenceCount = 0
    }
  }

  @discardableResult
  private mutating func processCompositionInput(_ input: CompositionInput) -> Bool {
    if !enableInsert() {
      return false
    }

    position = composition.insertInput(position, input)
    isNewInput = false
    return true
  }

  public mutating func insertCharacter(_ key: String) {
    var input = CompositionInput()
    input.initFromRaw(key, isNewInput)
    processCompositionInput(input)
  }

  public mutating func insertCommandCharacter(_ internalCommand: InternalCommand) {
    var input = CompositionInput()
    switch internalCommand {
    case .rewind:
      input.initFromRaw(table.parseSpecialKey("{<}"), isNewInput)
      processCompositionInput(input)
    case .stopKeyToggling:
      input.initFromRaw(table.parseSpecialKey("{!}"), isNewInput)
      processCompositionInput(input)
    }
  }

  /// Set preedit text to composer.
  ///
  /// If you want to set preedit text for testing
  /// (to convert from HIRAGANA string rather than key input),
  /// you should use SetPreeditTextForTestOnly().
  /// With the current implementation, prediction queries can be transliterated
  /// and you will not be able to get right candidates.
  public mutating func insertCharacterPreedit(_ input: some StringProtocol) {
    for character in Utf8AsChars(input) {
      if !insertCharacterKeyAndPreedit(character, character) {
        return
      }
    }
  }

  /// TEST ONLY: Set preedit text to composer.
  ///
  /// The |input| will be used in as-is form for GetStringForPreedit()
  /// and GetStringForSubmission().
  /// For GetQueryForConversion() and GetQueryForPrediction(), |input| will be
  /// used as normalized ascii characters in half width.
  ///
  /// For example, when the |input| will be set as "mo", suggestion will be
  /// triggered by "mo", rather than "も", or "ｍｏ", etc.
  ///
  /// If the input is ascii characters, input mode will be set as HALF_ASCII.
  /// This is useful to test the behavior of alphabet keyboard.
  public mutating func setPreeditTextForTestOnly(_ input: some StringProtocol) {
    composition.setInputMode(.rawString)

    for c in Utf8AsChars(input) {
      var compositionInput = CompositionInput()
      compositionInput.raw = String(c)
      compositionInput.isNewInput = isNewInput
      position = composition.insertInput(position, compositionInput)
      isNewInput = false
    }

    var lowerInput = String(input)
    Util.lowerString(&lowerInput)
    if Util.isLowerAscii(lowerInput) {
      // Fake input mode.
      // This is useful to test the behavior of alphabet keyboard.
      setTemporaryInputMode(.halfAscii)
    }
  }

  /// Set compositions from handwriting recognition results.
  /// The composition may contain Kana-Kanji mixed string. (ex. "かん字")
  /// Handwriting engine can generate multiple candidates.
  public mutating func setCompositionsForHandwriting(
    _ compositions: [Genmai_Commands_SessionCommand.CompositionEvent]
  ) {
    reset()
    compositionsForHandwriting = compositions

    if compositionsForHandwriting.isEmpty {
      return
    }
    composition.setInputMode(.rawString)

    for c in Utf8AsChars(compositionsForHandwriting[0].compositionString) {
      var compositionInput = CompositionInput()
      compositionInput.raw = String(c)
      compositionInput.isNewInput = isNewInput
      position = composition.insertInput(position, compositionInput)
      isNewInput = false
    }
  }

  public func getHandwritingCompositions() -> [Genmai_Commands_SessionCommand.CompositionEvent] {
    compositionsForHandwriting
  }

  @discardableResult
  public mutating func insertCharacterKeyAndPreedit(
    _ key: some StringProtocol, _ preedit: some StringProtocol
  ) -> Bool {
    var input = CompositionInput()
    input.initFromRawAndConv(String(key), String(preedit), isNewInput)
    return processCompositionInput(input)
  }

  @discardableResult
  public mutating func insertCharacterKeyEvent(_ key: Genmai_Commands_KeyEvent) -> Bool {
    if !enableInsert() {
      return false
    }

    // Check timeout.
    // If the duration from the previous input is over than the threshold,
    // A STOP_KEY_TOGGLING command is sent before the key input.
    if timeoutThresholdMsec > 0 {
      let currentMsec: Int64 =
        key.hasTimestampMsec
        ? key.timestampMsec
        : Int64((Clock.getAbslTime().timeIntervalSince1970 * 1000).rounded(.down))
      if timestampMsec > 0 && currentMsec - timestampMsec >= Int64(timeoutThresholdMsec) {
        insertCommandCharacter(.stopKeyToggling)
      }
      timestampMsec = currentMsec
    }

    if key.hasMode {
      let newInputMode = getTransliterationTypeFromCompositionMode(key.mode)
      if newInputMode != inputMode {
        // Only when the new input mode is different from the current
        // input mode, SetInputMode is called.  Otherwise the value of
        // comeback_input_mode_ is lost.
        setInputMode(newInputMode)
      }
    }

    // If only SHIFT is pressed, this is used to revert back to the
    // previous input mode.
    if !key.hasKeyCode {
      // NOTE: the C++ loop condition is `key.modifier_keys_size()` (not
      // `i < size`), which reads out of range when no SHIFT is found. All
      // modifier keys are checked here instead.
      for modifierKey in key.modifierKeys where modifierKey == .shift {
        // TODO(komatsu): Enable to customize the behavior.
        setInputMode(comebackInputMode)
        return true
      }
    }

    var input = CompositionInput()
    if !input.initialize(table, key, isNewInput) {
      return false
    }

    if !input.conversion.isEmpty {
      if input.isAsis {
        composition.setInputMode(.conversionString)
        // Disable typing correction mainly for Android. b/258369101
        processCompositionInput(input)
        setInputMode(comebackInputMode)
      } else {
        // Kana input usually has conversion. Note that, the existence of
        // key_string never determine if the input mode is Kana or Romaji.
        processCompositionInput(input)
      }
    } else {
      // Romaji input usually does not has conversion. Note that, the
      // existence of key_string never determines if the input mode is
      // Kana or Romaji.
      let modifiers = KeyEventUtil.getModifiers(key)
      applyTemporaryInputMode(input.raw, KeyEventUtil.hasCaps(modifiers))
      processCompositionInput(input)
    }

    if comebackInputMode == inputMode {
      autoSwitchMode()
    }
    return true
  }

  /// Deletes a character at specified position.
  public mutating func deleteAt(_ pos: Int) {
    composition.deleteAt(pos)
    // Adjust cursor position for composition mode.
    if position > pos {
      position -= 1
    }
  }

  public mutating func delete() {
    position = composition.deleteAt(position)
    updateInputMode()
  }

  /// Delete multiple characters beginning at specified position.
  public mutating func deleteRange(_ pos: Int, _ length: Int) {
    var i = 0
    while i < length && pos < composition.getLength() {
      deleteAt(pos)
      i += 1
    }
  }

  public mutating func editErase() {
    composition.erase()
    position = 0
    setInputMode(comebackInputMode)
  }

  public mutating func backspace() {
    if position == 0 {
      return
    }

    // In the view point of updating input mode,
    // backspace is special case because new input mode is based on both
    // new current character and *character to be deleted*.

    // At first, move to left.
    // Now the cursor is between 'new current character'
    // and 'character to be deleted'.
    position -= 1

    // Update input mode based on both 'new current character' and
    // 'character to be deleted'.
    updateInputMode()

    // Delete 'character to be deleted'
    position = composition.deleteAt(position)
  }

  public mutating func moveCursorLeft() {
    if position > 0 {
      position -= 1
    }
    updateInputMode()
  }

  public mutating func moveCursorRight() {
    if position < composition.getLength() {
      position += 1
    }
    updateInputMode()
  }

  public mutating func moveCursorToBeginning() {
    position = 0
    setInputMode(comebackInputMode)
  }

  public mutating func moveCursorToEnd() {
    position = composition.getLength()
    // Behavior between MoveCursorToEnd and MoveCursorToRight is different.
    // MoveCursorToEnd always makes current input mode default.
    setInputMode(comebackInputMode)
  }

  public mutating func moveCursorTo(_ newPosition: UInt32) {
    if Int(newPosition) <= composition.getLength() {
      position = Int(newPosition)
      updateInputMode()
    }
  }

  /// Returns preedit strings
  public func getPreedit(_ left: inout String, _ focused: inout String, _ right: inout String) {
    composition.getPreedit(position, &left, &focused, &right)

    // TODO(komatsu): This function can be obsolete.
    var preedit = left + focused + right
    if Composer.transformCharactersForNumbers(&preedit) {
      let leftSize = Util.charsLen(left)
      let focusedSize = Util.charsLen(focused)
      left = String(Util.utf8SubString(preedit, 0, leftSize))
      focused = String(Util.utf8SubString(preedit, leftSize, focusedSize))
      right = String(Util.utf8SubString(preedit, leftSize + focusedSize))
    }
  }

  /// Returns a preedit string with user's preferences.
  public func getStringForPreedit() -> String {
    Common.getStringForPreedit(composition, inputFieldType)
  }

  /// Returns a submit string with user's preferences.  The difference
  /// from the preedit string is the handling of the last 'n'.
  public func getStringForSubmission() -> String {
    // TODO(komatsu): We should make sure if we can integrate this
    // function to GetStringForPreedit after a while.
    getStringForPreedit()
  }

  /// Returns a conversion query normalized ascii characters in half width
  public func getQueryForConversion() -> String {
    Common.getQueryForConversion(composition)
  }

  /// Returns a prediction query trimmed the tail alphabet characters.
  public func getQueryForPrediction() -> String {
    Common.getQueryForPrediction(composition, inputMode)
  }

  /// Returns a expanded prediction query.
  public func getQueriesForPrediction() -> (String, [String]) {
    Common.getQueriesForPrediction(composition, inputMode)
  }

  /// Returns a string to be used for type correction.
  public func getStringForTypeCorrection() -> String {
    Common.getStringForTypeCorrection(composition)
  }

  public func getLength() -> Int { composition.getLength() }
  public func getCursor() -> Int { position }

  /// Generate transliterated substrings.
  private func getTransliteratedText(
    _ t12r: Transliterators.Transliterator, _ position: Int, _ size: Int
  ) -> String {
    Common.getTransliteratedText(composition, t12r, position, size)
  }

  /// Returns raw input from a user.
  /// The main purpose is Transliteration.
  public func getRawString() -> String {
    Common.getRawString(composition)
  }

  /// Returns substring of raw input.  The position and size is based on the
  /// composed string.  For example, when [さ|sa][し|shi][み|mi] is the
  /// composition, GetRawSubString(0, 2) returns "sashi".
  public func getRawSubString(_ position: Int, _ size: Int) -> String {
    Common.getRawSubString(composition, position, size)
  }

  /// Generate transliterations.
  public func getTransliterations(_ t13ns: inout Transliterations) {
    Common.getTransliterations(composition, &t13ns)
  }

  /// Generate substrings of specified transliteration.
  public func getSubTransliteration(_ type: TransliterationType, _ position: Int, _ size: Int)
    -> String
  {
    Common.getSubTransliteration(composition, type, position, size)
  }

  /// Generate substrings of transliterations.
  public func getSubTransliterations(_ position: Int, _ size: Int, _ t13ns: inout Transliterations) {
    Common.getSubTransliterations(composition, position, size, &t13ns)
  }

  /// Check if the preedit is can be modified.
  public func enableInsert() -> Bool {
    if getLength() >= maxLength {
      // do not accept long chars to prevent DOS attack.
      GenmaiLog.warning("The length is too long.")
      return false
    }
    return true
  }

  /// Automatically switch the composition mode according to the current
  /// status and user's settings.
  public mutating func autoSwitchMode() {
    if !config.autoSwitchCompositionMode {
      return
    }

    // AutoSwitchMode is only available on Roma input
    if config.preeditMethod != .roman {
      return
    }

    // Key should be in half-width alphanumeric.
    let key = composition.getStringWithTransliterator(getTransliterator(.halfAscii))

    let modeSwitching = ModeSwitchingHandler.getModeSwitchingRule(key)

    // |display_mode| affects the existing composition the user typed.
    switch modeSwitching.displayMode {
    case .noChange:
      // Do nothing.
      break
    case .revertToPreviousMode:
      // Invalid value for display_mode
      GenmaiLog.error("REVERT_TO_PREVIOUS_MODE is an invalid value for display_mode.")
    case .preferredAlphanumeric:
      if inputMode == .fullAscii {
        setOutputMode(.fullAscii)
      } else {
        setOutputMode(.halfAscii)
      }
    case .halfAlphanumeric:
      setOutputMode(.halfAscii)
    case .fullAlphanumeric:
      setOutputMode(.fullAscii)
    }

    // |input_mode| affects the current input mode used for the user's
    // new typing.
    switch modeSwitching.inputMode {
    case .noChange:
      // Do nothing.
      break
    case .revertToPreviousMode:
      setInputMode(comebackInputMode)
    case .preferredAlphanumeric:
      if inputMode != .halfAscii && inputMode != .fullAscii {
        setTemporaryInputMode(.halfAscii)
      }
    case .halfAlphanumeric:
      if inputMode != .halfAscii {
        setTemporaryInputMode(.halfAscii)
      }
    case .fullAlphanumeric:
      if inputMode != .fullAscii {
        setTemporaryInputMode(.fullAscii)
      }
    }
  }

  /// Return true if the composition is advised to be committed immediately.
  public func shouldCommit() -> Bool { composition.shouldCommit() }

  /// Returns true if characters at the head of the preedit should be committed
  /// immediately.
  /// This is used for implementing password input mode in Android.
  /// We cannot use direct input mode because it cannot deal with toggle input.
  /// In password mode, first character in composition should be committed
  /// when another letter is generated in composition.
  public func shouldCommitHead(_ lengthToCommit: inout Int) -> Bool {
    let maxRemainingCompositionLength: Int
    switch getInputFieldType() {
    case .password:
      maxRemainingCompositionLength = 1
    case .tel, .number:
      maxRemainingCompositionLength = 0
    default:
      // No need to commit. Return here.
      return false
    }
    if getLength() > maxRemainingCompositionLength {
      lengthToCommit = getLength() - maxRemainingCompositionLength
      return true
    }
    return false
  }

  /// Transform characters for preferred number format.  If any
  /// characters are transformed true is returned.
  /// For example, if the query is "ー１、０００。５", it should be
  /// transformed to "−１，０００．５".  and true is returned.
  ///
  /// Rules:
  /// ー (U+30FC) is transformed to − (U+2212) if either of:
  ///   * the previous character is an alphanumeric,
  ///   * the previous characters are sequence of "-" started with an alphanumeric
  ///     (ex. 0------),
  ///   * the previous character is empty and the next character is an
  ///     alphanumeric.
  /// 、 (U+3001) is transformed to ， (U+FF0C) if:
  ///   * the previous character and the next character are both alphanumerics.
  /// 。 (U+3002) is transformed to ． (U+FF0E) if:
  ///   * the previous character and the next character are both alphanumerics.
  @discardableResult
  public static func transformCharactersForNumbers(_ query: inout String) -> Bool {
    // Create a vector of scripts of query characters to avoid
    // processing query string many times.
    let charsLen = Util.charsLen(query)
    var charScripts: [Script] = []
    charScripts.reserveCapacity(charsLen)

    // flags to determine whether continue to the next step.
    var hasSymbols = false
    var hasAlphanumerics = false
    for scalar in query.unicodeScalars {
      let oneChar = scalar.value
      switch oneChar {
      case 0x30FC:  // "ー"
        hasSymbols = true
        charScripts.append(.jaHyphen)
      case 0x3001:  // "、"
        hasSymbols = true
        charScripts.append(.jaComma)
      case 0x3002:  // "。"
        hasSymbols = true
        charScripts.append(.jaPeriod)
      case 0x2B, 0x2A, 0x2F, 0x3D, 0x28, 0x29, 0x3C, 0x3E,  // + * / = ( ) < >
        0xFF0B,  // "＋"
        0xFF0A,  // "＊"
        0xFF0F,  // "／"
        0xFF1D,  // "＝"
        0xFF08,  // "（"
        0xFF09,  // "）"
        0xFF1C,  // "＜"
        0xFF1E:  // "＞"
        charScripts.append(.alphabet)
      default:
        let scriptType = Util.getScriptType(oneChar)
        if scriptType == .number {
          hasAlphanumerics = true
          charScripts.append(.number)
        } else if scriptType == .alphabet {
          hasAlphanumerics = true
          charScripts.append(.alphabet)
        } else {
          charScripts.append(.other)
        }
      }
    }

    if !hasAlphanumerics || !hasSymbols {
      return false
    }

    var transformedQuery = ""
    var transformed = false
    for (i, scalar) in query.unicodeScalars.enumerated() {
      var appendChar = ""
      switch charScripts[i] {
      case .jaHyphen:
        // JA_HYPHEN(s) "ー" is/are transformed to "−" if:
        // (i) query has one and only one leading JA_HYPHEN followed by a
        //     number,
        // (ii) JA_HYPHEN(s) follow(s) after an alphanumeric (ex. 0-, 0----,
        //     etc).
        // Note that rule (i) implies that if query starts with more than
        // one JA_HYPHENs, those JA_HYPHENs are not transformed.
        var check = false
        if i == 0 && charsLen > 1 {
          check = (charScripts[1] == .number)
        } else {
          var j = i
          while j > 0 {
            if charScripts[j - 1] == .jaHyphen {
              j -= 1
              continue
            }
            check = isAlphabetOrNumber(charScripts[j - 1])
            break
          }
        }

        // JA_HYPHEN should be transformed to MINUS.
        if check {
          appendChar = CharacterFormManager.getCharacterFormManager().convertPreeditString(
            "−")  // U+2212
        }

      case .jaComma:
        // "、" should be "，" if the previous character is alphanumerics.
        // character are both alphanumerics.
        // Previous char should exist and be a number.
        let lhsCheck = (i > 0 && isAlphabetOrNumber(charScripts[i - 1]))
        // JA_COMMA should be transformed to COMMA.
        if lhsCheck {
          appendChar = CharacterFormManager.getCharacterFormManager().convertPreeditString("，")
        }

      case .jaPeriod:
        // "。" should be "．" if the previous character and the next
        // character are both alphanumerics.
        // Previous char should exist and be a number.
        let lhsCheck = (i > 0 && isAlphabetOrNumber(charScripts[i - 1]))
        // JA_PERIOD should be transformed to PERIOD.
        if lhsCheck {
          appendChar = CharacterFormManager.getCharacterFormManager().convertPreeditString("．")
        }

      default:
        // Do nothing.
        break
      }

      if appendChar.isEmpty {
        // Append one character.
        transformedQuery.unicodeScalars.append(scalar)
      } else {
        // Append the transformed character.
        transformedQuery += appendChar
        transformed = true
      }
    }
    if !transformed {
      return false
    }

    // It is possible that the query's size in byte differs from the
    // orig_query's size in byte.
    query = transformedQuery
    return true
  }

  /// Set new input flag.
  /// By calling this method, next inserted character will introduce
  /// new chunk if the character has NewChunk attribute.
  public mutating func setNewInput() { isNewInput = true }

  /// Returns true when the current character at cursor position is toggleable.
  public func isToggleable() -> Bool {
    // When |is_new_input_| is true, a new chunk is always created and, hence, key
    // toggling never happens regardless of the composition state.
    !isNewInput && composition.isToggleable(position)
  }

  public mutating func setSourceText(_ sourceText: some StringProtocol) {
    self.sourceText = String(sourceText)
  }

  // MARK: - Test peer (ComposerTestPeer in C++)

  /// Accessors used by tests (the C++ tests use a friend ComposerTestPeer).
  public var compositionForTesting: Composition {
    get { composition }
    set { composition = newValue }
  }

  /// ComposerTestPeer::ApplyTemporaryInputMode.
  public mutating func applyTemporaryInputModeForTesting(_ input: String, _ capsLocked: Bool) {
    applyTemporaryInputMode(input, capsLocked)
  }

  public var tableForTesting: Table { table }
  public var requestForTesting: Genmai_Commands_Request { request }
  public var configForTesting: Genmai_Config_Config { config }
  public var positionForTesting: Int {
    get { position }
    set { position = newValue }
  }
}
