// Port of mozc/src/config/character_form_manager.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - The C++ singleton (`GetCharacterFormManager()`) is kept. Because Swift
//   Testing runs tests in parallel and many tests mutate the manager, a
//   task-local instance can be installed with
//   `CharacterFormManager.withScopedManagerForTesting(_:)`; it takes
//   precedence over the singleton inside the scope.
// - All state is guarded by one lock (the C++ code only guards the storage;
//   the rule tables are not thread-safe there).
// - Swift strings cannot contain invalid UTF-8, so the `it.ok()` checks of the
//   C++ tokenizer are no-ops (invalid bytes become U+FFFD at decoding time).

import Foundation
import GenmaiBase
import GenmaiProtocol
import Synchronization

private typealias CharacterForm = Genmai_Config_Config.CharacterForm
private typealias CharacterFormHistory = Genmai_UserHistoryPredictor_UserHistory.CharacterFormHistory

// Thread-safety is provided by the owning CharacterFormManager's lock.
private struct CharacterFormStorage {
  var proto = CharacterFormHistory()
  var dirty = false

  func getCharacterForm(_ ucs2: UInt16) -> CharacterForm {
    guard let value = proto.characterFormMap[UInt32(ucs2)],
      let form = CharacterForm(rawValue: Int(value))
    else {
      return .fullWidth  // Return default setting
    }
    return form
  }

  mutating func setCharacterForm(_ ucs2List: [UInt16], _ form: CharacterForm) {
    for ucs2 in ucs2List {
      let key = UInt32(ucs2)
      if let existing = proto.characterFormMap[key] {
        if existing == UInt32(form.rawValue) {
          continue
        }
      }
      proto.characterFormMap[key] = UInt32(form.rawValue)
      dirty = true
    }
  }

  func getNumberStyle() -> CharacterFormManager.NumberFormStyle? {
    if !proto.hasLastNumberForm || !proto.hasLastNumberStyle {
      return nil
    }
    guard let form = CharacterForm(rawValue: Int(proto.lastNumberForm)) else {
      return nil
    }
    // C++ static_casts the stored integer; an unknown style falls back to the
    // default style here.
    let style =
      NumberUtil.NumberString.Style(rawValue: Int(proto.lastNumberStyle)) ?? .defaultStyle
    return CharacterFormManager.NumberFormStyle(form: form, style: style)
  }

  mutating func setNumberStyle(_ formStyle: CharacterFormManager.NumberFormStyle) {
    if proto.hasLastNumberForm && proto.hasLastNumberStyle
      && proto.lastNumberForm == UInt32(formStyle.form.rawValue)
      && proto.lastNumberStyle == UInt32(formStyle.style.rawValue)
    {
      return
    }
    proto.lastNumberForm = UInt32(formStyle.form.rawValue)
    proto.lastNumberStyle = UInt32(formStyle.style.rawValue)
    dirty = true
  }

  mutating func clear() {
    proto = CharacterFormHistory()
    dirty = false
  }

  mutating func load(_ history: Genmai_UserHistoryPredictor_UserHistory) {
    proto = history.characterFormHistory
    dirty = false
  }

  mutating func save(_ history: inout Genmai_UserHistoryPredictor_UserHistory) {
    let size = ((try? proto.serializedBytes() as [UInt8]) ?? []).count
    if size > 0 {
      history.characterFormHistory = proto
    } else {
      history.clearCharacterFormHistory()
    }
    dirty = false
  }
}

// Returns canonical/normalized UCS2 character for given string.
// Example:
// "インターネット" -> "ア"  (All katakana becomes "ア")
// "810124" -> "0"           (All numbers becomes "0")
// "Google" -> "A"           (All numbers becomes "A")
// "&" -> "&"                (Symbol is used as it is)
// "ほげほげ" -> 0x0000      (Unknown)
// "𠮟"       -> 0x0000      (Non BMP character is also Unknown)
private func getNormalizedCharacter(_ str: some StringProtocol) -> UInt16 {
  let type = Util.getScriptType(str)
  var ucs2: UInt16 = 0x0000
  switch type {
  case .katakana:
    ucs2 = 0x30A2  // return "ア"
  case .number:
    ucs2 = 0x0030  // return "0"
  case .alphabet:
    ucs2 = 0x0041  // return "A"
  case .kanji, .hiragana:
    ucs2 = 0x0000  // no conversion
  default:  // maybe symbol
    if Strings.atLeastCharsLen(str, 2) == 1 {  // must be 1 character
      // normalize it to half width
      let tmp = Japanese.halfWidthToFullWidth(str)
      if let codepoint = tmp.unicodeScalars.first?.value, codepoint <= 0xffff {
        ucs2 = UInt16(codepoint)
      } else {
        ucs2 = 0x0000  // no conversion as fall back
      }
    }
  }
  return ucs2
}

private struct CharToken {
  var cp: Char32
  var view: Substring
  var type: Util.ScriptType
  var form: Util.FormType
}

// Tokenizes |str| into unicode character tokens with their script type and form
// type.
//
// Contextual adjustment:
// Periods ('.', '．') and commas (',', '，') surrounded by numeric digits (e.g.
// '.' in "3.14" or ',' in "1,000") are reclassified as Util::NUMBER.
// Only '.' and ',' are reclassified because they represent internal decimal
// and thousands separators forming a single numeric entity. Other separators
// like '/' (dates: "2026/10/07") and ':' (times: "12:30") are not reclassified
// because they separate distinct numeric components, and are guarded against
// mixed-width artifacts by the run-based consistency check below.
// Reclassified separators adopt GetCharacterForm("0") so they follow the
// number rule instead of their own symbol group rule.
private func tokenizeStringForConversion(_ str: some StringProtocol) -> [CharToken] {
  var tokens: [CharToken] = []
  let sub = Substring(str)
  var i = sub.startIndex
  while i < sub.endIndex {
    let next = sub.unicodeScalars.index(after: i)
    let cp = sub.unicodeScalars[i].value
    tokens.append(
      CharToken(cp: cp, view: sub[i..<next], type: Util.getScriptType(cp), form: Util.getFormType(cp)))
    i = next
  }
  if tokens.count >= 3 {
    for i in 1..<(tokens.count - 1) {
      let cp = tokens[i].cp
      if (cp == 0x2E || cp == 0xFF0E || cp == 0x2C || cp == 0xFF0C)  // . ． , ，
        && tokens[i - 1].type == .number && tokens[i + 1].type == .number
      {
        tokens[i].type = .number
      }
    }
  }
  return tokens
}

// Returns true if the token acts as a delimiter between separate
// variable-width runs (e.g. kanji, hiragana, katakana, or fixed full-width
// Japanese punctuation/brackets in "Tシャツ", "3時", "「Tシャツ」", or
// "100。").
private func isVariableWidthRunDelimiter(_ token: CharToken) -> Bool {
  token.type == .kanji || token.type == .hiragana || token.type == .katakana
    || Util.isFullWidthSymbolInHalfWidthKatakana(token.view)
}

private func convertToAlternative(_ input: String, _ form: Util.FormType, _ type: Util.ScriptType)
  -> String
{
  switch form {
  case .fullWidth:
    if type == .katakana || Util.isFullWidthSymbolInHalfWidthKatakana(input) {
      return Japanese.halfWidthToFullWidth(input)
    } else {
      return Japanese.fullWidthToHalfWidth(input)
    }
  case .halfWidth:
    return Japanese.halfWidthToFullWidth(input)
  default:
    return input
  }
}

private struct CharacterFormManagerImpl {
  // store the setting of a character
  var conversionTable: [UInt16: CharacterForm] = [:]
  var groupTable: [UInt16: [UInt16]] = [:]
  // When this flag is true,
  // character form conversion requires that output has consistent forms.
  // i.e. output should consists by half-width only or full-width only.
  var requireConsistentConversion = false

  func getCharacterForm(_ str: some StringProtocol, _ storage: CharacterFormStorage)
    -> CharacterForm
  {
    let ucs2 = getNormalizedCharacter(str)
    if ucs2 == 0x0000 {
      return .noConversion
    }
    guard let form = conversionTable[ucs2] else {
      return .noConversion
    }
    if form == .lastForm {
      return storage.getCharacterForm(ucs2)
    }
    return form
  }

  func guessAndSetCharacterForm(_ str: String, _ storage: inout CharacterFormStorage) {
    var prevType = Util.ScriptType.unknownScript
    var chunkStart: String.Index? = nil
    var chunkEnd = str.startIndex
    let strSize = str.utf8.count

    func flushChunk(_ start: String.Index?, _ end: String.Index, _ type: Util.ScriptType) {
      guard let start, start < end else {
        return
      }
      let target = str[start..<end]
      // Ignore symbol chunks embedded in a larger string (e.g. ',' in "1,000")
      // so they do not overwrite symbol group preferences, while still learning
      // when the entire committed string is a symbol (e.g. "[").
      if type == .unknownScript && target.utf8.count != strSize {
        return
      }
      let form = Util.getFormType(target)
      if form == .fullWidth {
        setCharacterForm(target, .fullWidth, &storage)
      } else if form == .halfWidth {
        setCharacterForm(target, .halfWidth, &storage)
      }
    }

    var i = str.startIndex
    while i < str.endIndex {
      let next = str.unicodeScalars.index(after: i)
      let cp = str.unicodeScalars[i].value
      var type = Util.getScriptType(cp)
      if cp == 0x30FB {  // "・"
        // Treat full-width middle dot as UNKNOWN_SCRIPT (matching
        // GetNormalizedCharacter("・")) so embedded middle dots (e.g. in
        // "東京・大阪" or "ｱ・ｲ") are ignored like other symbols.
        type = .unknownScript
      }
      if chunkStart != nil && type != prevType {
        flushChunk(chunkStart, chunkEnd, prevType)
        chunkStart = i
        chunkEnd = next
      } else if chunkStart == nil {
        chunkStart = i
        chunkEnd = next
      } else {
        chunkEnd = next
      }
      prevType = type
      i = next
    }
    flushChunk(chunkStart, chunkEnd, prevType)
  }

  func setCharacterForm(
    _ str: some StringProtocol, _ form: CharacterForm, _ storage: inout CharacterFormStorage
  ) {
    let ucs2 = getNormalizedCharacter(str)
    if ucs2 == 0x0000 {
      return
    }
    guard let entry = conversionTable[ucs2] else {
      return
    }
    if entry == .lastForm {
      saveCharacterFormToStorage(ucs2, form, &storage)
      return
    }
  }

  func saveCharacterFormToStorage(
    _ ucs2: UInt16, _ form: CharacterForm, _ storage: inout CharacterFormStorage
  ) {
    if form != .fullWidth && form != .halfWidth {
      return
    }
    if let group = groupTable[ucs2] {
      // Update values in the same group.
      storage.setCharacterForm(group, form)
    } else {
      storage.setCharacterForm([ucs2], form)
    }
  }

  func convertString(_ str: some StringProtocol, _ storage: CharacterFormStorage) -> String {
    convertStringWithAlternative(str, storage, wantAlternative: false).output
  }

  // Returns true if input string will be consistent character form after
  // conversion.
  // For example:
  //  input = "3.14"
  //  preference for numbers = FULL_WIDTH
  //             for period = HALF_WIDTH
  //  this will be "３.１４" and it is not consistent
  //  so this function will return false
  func tryConvertStringWithPreference(
    _ str: some StringProtocol, _ output: inout String, _ storage: CharacterFormStorage
  ) -> Bool {
    let tokens = tokenizeStringForConversion(str)
    if tokens.isEmpty {
      return true
    }

    var runTargetForm = CharacterForm.noConversion
    var prevForm = CharacterForm.noConversion
    var prevType = Util.ScriptType.unknownScript
    var ret = true

    var buf = ""
    for (i, token) in tokens.enumerated() {
      let type = token.type

      // Cache previous ScriptType to reduce to call GetCharacterForm()
      var form = prevForm
      if type == .number {
        if prevType != .number {
          form = getCharacterForm("0", storage)
        }
      } else if type == .unknownScript {
        form = getCharacterForm(token.view, storage)
      } else if type == .katakana && prevType != .katakana {
        form = getCharacterForm(token.view, storage)
      } else if type == .alphabet && prevType != .alphabet {
        form = getCharacterForm(token.view, storage)
      } else if type == .kanji || type == .hiragana {
        form = .noConversion
      }

      // Cache previous Form to reduce to call ConvertWidth
      if i > 0 && prevForm != form {
        output += CharacterFormManager.convertWidth(buf, prevForm)
        buf = ""
      }

      if isVariableWidthRunDelimiter(token) {
        // Delimiters (kanji, hiragana, katakana, and fixed Japanese punctuation/
        // brackets) delimit separate variable-width runs, allowing e.g. "Tシャツ"
        // or "3時" to convert consistently without being blocked by mixed
        // scripts.
        runTargetForm = .noConversion
      } else {
        if runTargetForm == .noConversion {
          runTargetForm = form
        } else if form != .noConversion && form != runTargetForm {
          ret = false
        }
      }
      buf += token.view
      prevType = type
      prevForm = form
    }

    if !buf.isEmpty {
      output += CharacterFormManager.convertWidth(buf, prevForm)
    }

    return ret
  }

  func convertStringAlternative(_ str: some StringProtocol, _ output: inout String) {
    let tokens = tokenizeStringForConversion(str)
    if tokens.isEmpty {
      return
    }

    var prevForm = Util.FormType.unknownForm
    var prevType = Util.ScriptType.unknownScript

    var buf = ""
    for (i, token) in tokens.enumerated() {
      let type = token.type

      var form = prevForm
      if type == .unknownScript || (type == .katakana && prevType != .katakana)
        || (type == .number && prevType != .number)
        || (type == .alphabet && prevType != .alphabet)
      {
        form = token.form
      } else if type == .kanji || type == .hiragana {
        form = .unknownForm
      }

      // Flush when form or script type changes.
      if i > 0 && (prevForm != form || prevType != type) {
        output += convertToAlternative(buf, prevForm, prevType)
        buf = ""
      }

      buf += token.view
      prevType = type
      prevForm = form
    }

    if !buf.isEmpty {
      output += convertToAlternative(buf, prevForm, prevType)
    }
  }

  /// Returns (output, alternative_output, result). `alternative` is nil when
  /// `wantAlternative` is false (alternative_output == nullptr in C++).
  func convertStringWithAlternative(
    _ str: some StringProtocol, _ storage: CharacterFormStorage, wantAlternative: Bool
  ) -> (output: String, alternative: String?, result: Bool) {
    var output = ""
    let isConsistent = tryConvertStringWithPreference(str, &output, storage)
    if !isConsistent && requireConsistentConversion {
      output = String(str)
    }

    guard wantAlternative else {
      return (output, nil, false)
    }
    var alternativeOutput = ""
    convertStringAlternative(output, &alternativeOutput)
    // return true if alternative_output and output are different
    return (output, alternativeOutput, alternativeOutput != output)
  }

  // clear setting
  mutating func clear() {
    conversionTable.removeAll()
    groupTable.removeAll()
  }

  // Note that rule is MERGED.
  // Call Clear() first if you want to set rule from scratch
  mutating func addRule(_ key: some StringProtocol, _ form: CharacterForm) {
    var group: [UInt16] = []
    for ch in Utf8AsChars(key) {
      let ucs2 = getNormalizedCharacter(ch)
      if ucs2 != 0x0000 {
        group.append(ucs2)
      }
    }

    if group.isEmpty {
      return
    }

    let kMaxGroupSize = 128
    if group.count > kMaxGroupSize {
      GenmaiLog.warning("Too long rule. skipped")
      return
    }

    let kMaxTableSize = 256
    if conversionTable.count + group.count > kMaxTableSize
      || groupTable.count + group.count > kMaxTableSize
    {
      GenmaiLog.warning("conversion_table becomes too big. skipped")
      return
    }

    // sort + unique
    group.sort()
    var unique: [UInt16] = []
    for c in group where unique.last != c {
      unique.append(c)
    }
    group = unique

    for ucs2 in group {
      conversionTable[ucs2] = form  // overwrite
      if group.count > 1 {
        // add to group table
        // the key "UCS2" and other UCS2 in group are treated as the same way.
        groupTable[ucs2] = group  // overwrite
      }
    }
  }

  mutating func setPreeditDefaultRule() {
    clear()
    // AddRule("ア", Config::FULL_WIDTH);
    addRule("ア", .fullWidth)
    addRule("A", .fullWidth)
    addRule("0", .fullWidth)
    addRule("(){}[]", .fullWidth)
    addRule(".,", .fullWidth)
    // AddRule("。、", Config::FULL_WIDTH);  // don't like half-width
    // AddRule("・「」", Config::FULL_WIDTH);  // don't like half-width
    addRule("。、", .fullWidth)
    addRule("・「」", .fullWidth)
    addRule("\"'", .fullWidth)
    addRule(":;", .fullWidth)
    addRule("#%&@$^_|`\\", .fullWidth)
    addRule("~", .fullWidth)
    addRule("<>=+-/*", .fullWidth)
    addRule("?!", .fullWidth)

    requireConsistentConversion = false
  }

  mutating func setConversionDefaultRule() {
    clear()
    // AddRule("ア", Config::FULL_WIDTH);
    // don't like half-width
    addRule("ア", .fullWidth)
    addRule("A", .lastForm)
    addRule("0", .lastForm)
    addRule("(){}[]", .lastForm)
    addRule(".,", .lastForm)
    // AddRule("。、", Config::FULL_WIDTH);  // don't like half-width
    // AddRule("・「」", Config::FULL_WIDTH);  // don't like half-width
    addRule("。、", .fullWidth)
    addRule("・「」", .fullWidth)
    addRule("\"'", .lastForm)
    addRule(":;", .lastForm)
    addRule("#%&@$^_|`\\", .lastForm)
    addRule("~", .lastForm)
    addRule("<>=+-/*", .lastForm)
    addRule("?!", .lastForm)

    requireConsistentConversion = true
  }
}

// TODO(hidehiko): Move some methods which don't depend on "config" to the
//   mozc::Util class.
public final class CharacterFormManager: @unchecked Sendable {
  public struct NumberFormStyle: Sendable, Equatable {
    public var form: Genmai_Config_Config.CharacterForm
    public var style: NumberUtil.NumberString.Style

    public init(form: Genmai_Config_Config.CharacterForm, style: NumberUtil.NumberString.Style) {
      self.form = form
      self.style = style
    }
  }

  private struct Data {
    var preedit = CharacterFormManagerImpl()
    var conversion = CharacterFormManagerImpl()
    var storage = CharacterFormStorage()

    init() {
      preedit.setPreeditDefaultRule()
      conversion.setConversionDefaultRule()
    }
  }

  private let data = Mutex(Data())

  /// Creates a manager initialized from the current config
  /// (ConfigHandler::GetSharedConfig()). The C++ constructor is private; it is
  /// public here so that tests can create isolated instances.
  public init() {
    reloadConfig(ConfigHandler.getSharedConfig())
  }

  private func withData<R>(_ body: (inout Data) -> R) -> R {
    data.withLock { body(&$0) }
  }

  // MARK: - Singleton

  private static let shared = CharacterFormManager()

  @TaskLocal static var taskLocalManager: CharacterFormManager?

  /// Returns the singleton instance (or the task-local test instance).
  public static func getCharacterFormManager() -> CharacterFormManager {
    taskLocalManager ?? shared
  }

  /// TESTONLY: installs `manager` as the result of `getCharacterFormManager()`
  /// for the current task while running `body`.
  public static func withScopedManagerForTesting<R>(
    _ manager: CharacterFormManager = CharacterFormManager(), _ body: () throws -> R
  ) rethrows -> R {
    try $taskLocalManager.withValue(manager, operation: body)
  }

  nonisolated(nonsending) public static func withScopedManagerForTesting<R>(
    _ manager: CharacterFormManager = CharacterFormManager(),
    _ body: nonisolated(nonsending) () async throws -> R
  ) async rethrows -> R {
    try await $taskLocalManager.withValue(manager, operation: body)
  }

  // MARK: - API

  /// Returns the preference of character form.
  /// This method cannot return the preference,
  /// if str has two set of string groups having different preferences.
  /// e.g., GetPreeditCharacterForm("グーグル012") returns NO_CONVERSION
  public func getPreeditCharacterForm(_ input: some StringProtocol) -> Genmai_Config_Config.CharacterForm {
    withData { $0.preedit.getCharacterForm(input, $0.storage) }
  }

  public func getConversionCharacterForm(_ input: some StringProtocol)
    -> Genmai_Config_Config.CharacterForm
  {
    withData { $0.conversion.getCharacterForm(input, $0.storage) }
  }

  /// Converts string according to the config rules.
  public func convertPreeditString(_ input: some StringProtocol, _ output: inout String) {
    output = convertPreeditString(input)
  }

  public func convertConversionString(_ input: some StringProtocol, _ output: inout String) {
    output = convertConversionString(input)
  }

  public func convertPreeditString(_ input: some StringProtocol) -> String {
    withData { $0.preedit.convertString(input, $0.storage) }
  }

  public func convertConversionString(_ input: some StringProtocol) -> String {
    withData { $0.conversion.convertString(input, $0.storage) }
  }

  /// Converts string according to the config rules.
  /// if alternate output, which should be shown next to
  /// the output, is defined, it is stored into alternative_output.
  /// e.g., output = "@" alternative_output = "＠"
  /// return true if both output and alternative_output are defined.
  public func convertPreeditStringWithAlternative(
    _ input: some StringProtocol, _ output: inout String, _ alternativeOutput: inout String
  ) -> Bool {
    let r = withData { $0.preedit.convertStringWithAlternative(input, $0.storage, wantAlternative: true) }
    output = r.output
    alternativeOutput = r.alternative ?? ""
    return r.result
  }

  public func convertConversionStringWithAlternative(
    _ input: some StringProtocol, _ output: inout String, _ alternativeOutput: inout String
  ) -> Bool {
    let r = withData { $0.conversion.convertStringWithAlternative(input, $0.storage, wantAlternative: true) }
    output = r.output
    alternativeOutput = r.alternative ?? ""
    return r.result
  }

  /// Calls this method after user fixed the final result.
  /// If a character has "LAST_FORM" preference in the config,
  /// SetCharacterForm() stores the last character form into local file.
  /// Next time user calls GetPreeditCharacterForm() or
  /// GetConversionCharacterForm(), the preference is restored.
  public func setCharacterForm(_ input: some StringProtocol, _ form: Genmai_Config_Config.CharacterForm) {
    // no need to call Preedit, as storage is shared
    // GetPreeditManager()->SetCharacterForm(input, form);
    withData { $0.conversion.setCharacterForm(input, form, &$0.storage) }
  }

  /// Guesses the character form of str and call
  /// SetCharacterForm with this result.
  /// Call this method after user fixed the final result.
  public func guessAndSetCharacterForm(_ input: some StringProtocol) {
    // no need to call Preedit, as storage is shared
    let str = String(input)
    withData { $0.conversion.guessAndSetCharacterForm(str, &$0.storage) }
  }

  public func setLastNumberStyle(_ formStyle: NumberFormStyle) {
    withData { $0.storage.setNumberStyle(formStyle) }
  }

  public func getLastNumberStyle() -> NumberFormStyle? {
    withData { $0.storage.getNumberStyle() }
  }

  /// Clears history data. This method does not clear config data.
  public func clearHistory() {
    // no need to call, as storage is shared
    // GetPreeditManager()->ClearHistory();
    withData { $0.storage.clear() }
  }

  /// Loads/saves character form and number style history from/to UserHistory.
  public func loadStorage(_ history: Genmai_UserHistoryPredictor_UserHistory) {
    withData { $0.storage.load(history) }
  }

  public func saveStorage(_ history: inout Genmai_UserHistoryPredictor_UserHistory) {
    withData { $0.storage.save(&history) }
  }

  /// Returns true if the in-memory character form or number style history has
  /// been modified since the last LoadStorage(), SaveStorage(), or
  /// ClearHistory() call.
  public func isStorageDirty() -> Bool {
    withData { $0.storage.dirty }
  }

  /// Clears internal rules.
  public func clear() {
    withData {
      $0.conversion.clear()
      $0.preedit.clear()
    }
  }

  /// Adds a rule.
  /// Example:
  /// AddPreeditRule("[]{}()", config::Config::LAST_FORM);
  /// AddPreeditRule("+=", config::Config::HALF_WIDTH);
  /// The all characters in str are treated as the same group.
  public func addPreeditRule(_ input: some StringProtocol, _ form: Genmai_Config_Config.CharacterForm) {
    withData { $0.preedit.addRule(input, form) }
  }

  public func addConversionRule(_ input: some StringProtocol, _ form: Genmai_Config_Config.CharacterForm) {
    withData { $0.conversion.addRule(input, form) }
  }

  /// Loads Default rules.
  public func setDefaultRule() {
    withData {
      $0.preedit.setPreeditDefaultRule()
      $0.conversion.setConversionDefaultRule()
    }
  }

  /// Reload config explicitly.
  public func reloadConfig(_ config: Genmai_Config_Config) {
    clear()
    if !config.characterFormRules.isEmpty {
      for rule in config.characterFormRules {
        addPreeditRule(rule.group, rule.preeditCharacterForm)
        addConversionRule(rule.group, rule.conversionCharacterForm)
      }
    } else {
      setDefaultRule()
    }
  }

  /// Utility function: pass character form.
  public static func convertWidth(_ input: String, _ form: Genmai_Config_Config.CharacterForm) -> String {
    switch form {
    case .fullWidth:
      return Japanese.halfWidthToFullWidth(input)
    case .halfWidth:
      return Japanese.fullWidthToHalfWidth(input)
    default:
      return input
    }
  }
}
