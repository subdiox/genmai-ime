// Port of mozc/src/composer/table.{h,cc} (3.35.6354).
//
// Trie table for Romaji (or Kana) conversion.
//
// Notes:
// - `Entry` is a final class: the C++ code compares and returns `const Entry*`
//   pointers, so identity is kept.
// - `Table` is a final class shared by reference (std::shared_ptr<const Table>
//   in C++). It is mutated only while it is being built; afterwards it is used
//   read-only. Its state is kept in a `Mutex` so that it is `Sendable`.
// - TableManager's cache key is a struct of the four values that C++ hashes
//   with absl::HashOf.

import Foundation
import GenmaiBase
import GenmaiProtocol
import Synchronization

/// This is a bitmap representing Entry's additional attributes.
public struct TableAttributes: OptionSet, Sendable, Hashable, CustomStringConvertible {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  public static let noTableAttribute: TableAttributes = []
  /// When the typing is beginning, the rule with this attribute is
  /// executed even if the previous characters can be a part of other
  /// rules.
  public static let newChunk = TableAttributes(rawValue: 1)
  /// This flag suppresses any transliteration performed in CharChunk
  /// and treated as an as-is key event.
  public static let noTransliteration = TableAttributes(rawValue: 2)
  /// This flag indicates that the composition should be ended and committed.
  public static let directInput = TableAttributes(rawValue: 4)
  /// This flag treats the next typing as a new input.  This flag is
  /// used with the NEW_CHUNK flag.
  public static let endChunk = TableAttributes(rawValue: 8)

  public var description: String { String(rawValue) }
}

public final class Entry: Sendable {
  public let input: String
  public let result: String
  public let pending: String
  public let attributes: TableAttributes

  public init(
    _ input: String, _ result: String, _ pending: String, _ attributes: TableAttributes
  ) {
    self.input = input
    self.result = result
    self.pending = pending
    self.attributes = attributes
  }
}

private let kDefaultPreeditTableFile = "system://romanji-hiragana.tsv"
private let kRomajiPreeditTableFile = "system://romanji-hiragana.tsv"
// Table for Kana combinations like "か゛" → "が".
private let kKanaCombinationTableFile = "system://kana.tsv"

// Special tables for 12keys
private let k12keysHiraganaTableFile = "system://12keys-hiragana.tsv"
private let k12keysHiraganaIntuitiveTableFile = "system://12keys-hiragana_intuitive.tsv"
private let k12keysHalfwidthasciiTableFile = "system://12keys-halfwidthascii.tsv"
private let kFlickHiraganaTableFile = "system://flick-hiragana.tsv"
private let kFlickHalfwidthasciiIosTableFile = "system://flick-halfwidthascii_ios.tsv"
private let kFlickNumberTableFile = "system://flick-number.tsv"
private let kFlickHiraganaIntuitiveTableFile = "system://flick-hiragana_intuitive.tsv"
private let kFlickHalfwidthasciiTableFile = "system://flick-halfwidthascii.tsv"
private let kToggleFlickHiraganaTableFile = "system://toggle_flick-hiragana.tsv"
private let kToggleFlickHiraganaIntuitiveTableFile = "system://toggle_flick-hiragana_intuitive.tsv"
private let kToggleFlickHalfwidthasciiIosTableFile = "system://toggle_flick-halfwidthascii_ios.tsv"
private let kToggleFlickNumberTableFile = "system://toggle_flick-number.tsv"
private let kToggleFlickHalfwidthasciiTableFile = "system://toggle_flick-halfwidthascii.tsv"
// Special tables for QWERTY mobile
private let kQwertyMobileHiraganaTableFile = "system://qwerty_mobile-hiragana.tsv"
private let kQwertyMobileHalfwidthasciiTableFile = "system://qwerty_mobile-halfwidthascii.tsv"
// Special tables for Godan
private let kGodanHiraganaTableFile = "system://godan-hiragana.tsv"
private let kNotouchHiraganaTableFile = "system://notouch-hiragana.tsv"
// Reuse qwerty_mobile-halfwidthascii table
private let kNotouchHalfwidthasciiTableFile = "system://qwerty_mobile-halfwidthascii.tsv"
private let k50KeysHiraganaTableFile = "system://50keys-hiragana.tsv"

private let kNewChunkPrefix = "\t"

private let kKuten = "、"
private let kTouten = "。"
private let kComma = "，"
private let kPeriod = "．"
private let kCornerOpen = "「"
private let kCornerClose = "」"
private let kSlash = "／"
private let kSquareOpen = "["
private let kSquareClose = "]"
private let kMiddleDot = "・"

private let kAttributeDelimiter: UInt8 = 0x20  // ' '

/// absl::StrSplit(input, delimiter, absl::AllowEmpty()) on bytes.
func splitAllowEmptyBytes(_ input: some StringProtocol, _ delimiter: UInt8) -> [String] {
  var result: [String] = []
  var current: [UInt8] = []
  for b in input.utf8 {
    if b == delimiter {
      result.append(String(decoding: current, as: UTF8.self))
      current.removeAll(keepingCapacity: true)
    } else {
      current.append(b)
    }
  }
  result.append(String(decoding: current, as: UTF8.self))
  return result
}

private func parseAttributes(_ input: String) -> TableAttributes {
  var attributes = TableAttributes.noTableAttribute

  let attributeStrings = splitAllowEmptyBytes(input, kAttributeDelimiter)

  for attributeString in attributeStrings {
    if attributeString == "NewChunk" {
      attributes.insert(.newChunk)
    } else if attributeString == "NoTransliteration" {
      attributes.insert(.noTransliteration)
    } else if attributeString == "DirectInput" {
      attributes.insert(.directInput)
    } else if attributeString == "EndChunk" {
      attributes.insert(.endChunk)
    }
  }
  return attributes
}

private func lowerAscii(_ input: some StringProtocol) -> String {
  var s = String(input)
  Util.lowerString(&s)
  return s
}

/// The mutable state of a `Table`, guarded by its lock.
private struct TableState {
  let entries = Trie<Entry>()
  var specialKeyMap = SpecialKeyMap()
  /// If false, input alphabet characters are normalized to lower
  /// characters.  The default value is false.
  var caseSensitive = false

  /// Return true if adding the input-pending pair makes a loop of
  /// conversion rules.
  func isLoopingEntry(_ input: some StringProtocol, _ pending: some StringProtocol) -> Bool {
    if input.isEmpty || pending.isEmpty {
      return false
    }

    var key = String(pending)
    repeat {
      // If input is a prefix of key, it should be looping.
      // (ex. input="a", pending="abc").
      if key.hasBytePrefix(input) {
        return true
      }

      var keyLength = 0
      var fixed = false
      guard let entry = lookUpPrefix(key, &keyLength, &fixed) else {
        return false
      }
      key = entry.pending + ComposerBytes.substr(key, keyLength)
    } while !key.isEmpty

    return false
  }

  /// Adds one rule (`AddRuleWithAttributes` without the `NEW_CHUNK` companion
  /// rule, which the caller adds first).
  mutating func addRule(
    _ escapedInput: some StringProtocol, _ output: some StringProtocol,
    _ escapedPending: some StringProtocol, _ attributes: TableAttributes
  ) -> Entry? {
    let kMaxSize = 300
    if escapedInput.utf8.count >= kMaxSize || output.utf8.count >= kMaxSize
      || escapedPending.utf8.count >= kMaxSize
    {
      GenmaiLog.error("Invalid input/output/pending")
      return nil
    }

    let input = specialKeyMap.register(escapedInput)
    let pending = specialKeyMap.register(escapedPending)
    if isLoopingEntry(input, pending) {
      GenmaiLog.warning(
        "Entry \(input) \(output) \(pending) is removed, since the rule is looping")
      return nil
    }

    let entry = Entry(input, String(output), pending, attributes)
    entries.addEntry(input, entry)

    // Check if the input has a large capital character.
    // Invisible character is exception.
    if !caseSensitive {
      let trimedInput = deleteSpecialKeys(input)
      for scalar in trimedInput.unicodeScalars {
        let codepoint = scalar.value
        if 0x41 <= codepoint && codepoint <= 0x5A {  // 'A' <= codepoint <= 'Z'
          caseSensitive = true
          break
        }
      }
    }
    return entry
  }

  /// `keyLength` is in bytes.
  func lookUpPrefix(_ input: some StringProtocol, _ keyLength: inout Int, _ fixed: inout Bool)
    -> Entry?
  {
    var entry: Entry? = nil
    if caseSensitive {
      _ = entries.lookUpPrefix(input, &entry, &keyLength, &fixed)
    } else {
      _ = entries.lookUpPrefix(lowerAscii(input), &entry, &keyLength, &fixed)
    }
    return entry
  }
}

public final class Table: Sendable {
  private let state: Mutex<TableState>

  /// If false, input alphabet characters are normalized to lower
  /// characters.  The default value is false.
  public var caseSensitive: Bool {
    get { state.withLock { $0.caseSensitive } }
    set { state.withLock { $0.caseSensitive = newValue } }
  }

  public init() {
    var initial = TableState()
    // Add predefined special keys.
    _ = initial.specialKeyMap.register("{?}")  // toggle
    _ = initial.specialKeyMap.register("{*}")  // internal state
    _ = initial.specialKeyMap.register("{<}")  // rewind
    _ = initial.specialKeyMap.register("{!}")  // timeout
    state = Mutex(initial)
  }

  /// `entry == nullptr || (entry->result() == result && entry->pending().empty())`.
  private static func isMissingOrSimpleRule(_ entry: Entry?, _ result: String) -> Bool {
    guard let entry else { return true }
    return entry.result == result && entry.pending.isEmpty
  }

  @discardableResult
  public func initializeWithRequestAndConfig(
    _ request: Genmai_Commands_Request, _ config: Genmai_Config_Config
  ) -> Bool {
    caseSensitive = false
    var result = false
    if request.specialRomanjiTable != .defaultTable {
      let tableFileName: String?
      switch request.specialRomanjiTable {
      case .twelveKeysToHiragana:
        tableFileName = k12keysHiraganaTableFile
      case .twelveKeysToHiraganaIntuitive:
        tableFileName = k12keysHiraganaIntuitiveTableFile
      case .twelveKeysToHalfwidthascii:
        tableFileName = k12keysHalfwidthasciiTableFile
      case .flickToHiragana:
        tableFileName = kFlickHiraganaTableFile
      case .flickToHiraganaIntuitive:
        tableFileName = kFlickHiraganaIntuitiveTableFile
      case .flickToHalfwidthasciiIos:
        tableFileName = kFlickHalfwidthasciiIosTableFile
      case .flickToHalfwidthascii:
        tableFileName = kFlickHalfwidthasciiTableFile
      case .flickToNumber:
        tableFileName = kFlickNumberTableFile
      case .toggleFlickToHiragana:
        tableFileName = kToggleFlickHiraganaTableFile
      case .toggleFlickToHiraganaIntuitive:
        tableFileName = kToggleFlickHiraganaIntuitiveTableFile
      case .toggleFlickToHalfwidthasciiIos:
        tableFileName = kToggleFlickHalfwidthasciiIosTableFile
      case .toggleFlickToNumber:
        tableFileName = kToggleFlickNumberTableFile
      case .toggleFlickToHalfwidthascii:
        tableFileName = kToggleFlickHalfwidthasciiTableFile
      case .qwertyMobileToHiragana:
        // This table is almost as same as "romaji-hiragana.tsv",
        // and the diff should be only the behavior of ','.
        // So probably we'd like to share the table, but we keep this way
        // for now, as this is still internal code.
        // TODO(hidehiko): refactor this code to clean up.
        tableFileName = kQwertyMobileHiraganaTableFile
      case .qwertyMobileToHalfwidthascii:
        tableFileName = kQwertyMobileHalfwidthasciiTableFile
      case .godanToHiragana:
        tableFileName = kGodanHiraganaTableFile
      case .notouchToHiragana:
        tableFileName = kNotouchHiraganaTableFile
      case .notouchToHalfwidthascii:
        tableFileName = kNotouchHalfwidthasciiTableFile
      case .fiftyKeysToHiragana:
        tableFileName = k50KeysHiraganaTableFile
      default:
        tableFileName = nil
      }
      if let tableFileName, loadFromFile(tableFileName) {
        return true
      }
    }
    switch config.preeditMethod {
    case .roman:
      result =
        (config.hasCustomRomanTable && !config.customRomanTable.isEmpty)
        ? loadFromString(String(decoding: config.customRomanTable, as: UTF8.self))
        : loadFromFile(kRomajiPreeditTableFile)
    case .kana:
      result = loadFromFile(kRomajiPreeditTableFile)
    }

    if !result {
      result = loadFromFile(kDefaultPreeditTableFile)
      if !result {
        return false
      }
    }

    // Initialize punctuations.
    let punctuationMethod = config.punctuationMethod
    var entry: Entry? = nil

    // Comma / Kuten
    entry = lookUp(",")
    if Self.isMissingOrSimpleRule(entry, kKuten) {
      if punctuationMethod == .commaPeriod || punctuationMethod == .commaKuten {
        addRule(",", kComma, "")
      } else {
        addRule(",", kKuten, "")
      }
    }

    // Period / Touten
    entry = lookUp(".")
    if Self.isMissingOrSimpleRule(entry, kTouten) {
      if punctuationMethod == .commaPeriod || punctuationMethod == .toutenPeriod {
        addRule(".", kPeriod, "")
      } else {
        addRule(".", kTouten, "")
      }
    }

    // Initialize symbols.
    let symbolMethod = config.symbolMethod

    // Slash / Middle dot
    entry = lookUp("/")
    if Self.isMissingOrSimpleRule(entry, kMiddleDot) {
      if symbolMethod == .squareBracketSlash || symbolMethod == .cornerBracketSlash {
        addRule("/", kSlash, "")
      } else {
        addRule("/", kMiddleDot, "")
      }
    }

    // Square open bracket / Corner open bracket
    entry = lookUp("[")
    if Self.isMissingOrSimpleRule(entry, kCornerOpen) {
      if symbolMethod == .cornerBracketMiddleDot || symbolMethod == .cornerBracketSlash {
        addRule("[", kCornerOpen, "")
      } else {
        addRule("[", kSquareOpen, "")
      }
    }

    // Square close bracket / Corner close bracket
    entry = lookUp("]")
    if Self.isMissingOrSimpleRule(entry, kCornerClose) {
      if symbolMethod == .cornerBracketMiddleDot || symbolMethod == .cornerBracketSlash {
        addRule("]", kCornerClose, "")
      } else {
        addRule("]", kSquareClose, "")
      }
    }

    // result should be true here.
    precondition(result)

    // Load Kana combination rules.
    result = loadFromFile(kKanaCombinationTableFile)
    return result
  }

  /// Return true if adding the input-pending pair makes a loop of
  /// conversion rules.
  public func isLoopingEntry(_ input: some StringProtocol, _ pending: some StringProtocol) -> Bool {
    // (The lock's region checking needs `Sendable` arguments.)
    let input = String(input)
    let pending = String(pending)
    return state.withLock { $0.isLoopingEntry(input, pending) }
  }

  @discardableResult
  public func addRule(
    _ input: some StringProtocol, _ output: some StringProtocol, _ pending: some StringProtocol
  ) -> Entry? {
    addRuleWithAttributes(input, output, pending, .noTableAttribute)
  }

  @discardableResult
  public func addRuleWithAttributes(
    _ escapedInput: some StringProtocol, _ output: some StringProtocol,
    _ escapedPending: some StringProtocol, _ attributes: TableAttributes
  ) -> Entry? {
    if attributes.contains(.newChunk) {
      // TODO(komatsu): Make a new trie tree for checking the new chunk
      // attribute rather than reusing the conversion trie.
      let additionalInput = kNewChunkPrefix + escapedInput
      addRuleWithAttributes(additionalInput, output, escapedPending, .noTableAttribute)
    }

    let escapedInput = String(escapedInput)
    let output = String(output)
    let escapedPending = String(escapedPending)
    return state.withLock { $0.addRule(escapedInput, output, escapedPending, attributes) }
  }

  public func deleteRule(_ input: some StringProtocol) {
    // NOTE : If this method is called and an entry is deleted,
    //     case_sensitive_ turns to be invalid
    //     because it is not updated.
    //     Currently updating logic is omitted because;
    //     - Updating needs some complex implementation.
    //     - This method is not used.
    //     - This method has no tests.
    //     - This method is private scope.
    let input = String(input)
    state.withLock { _ = $0.entries.deleteEntry(input) }
  }

  @discardableResult
  public func loadFromString(_ str: some StringProtocol) -> Bool {
    loadFromStream(InputFileStream(string: String(str)))
  }

  @discardableResult
  public func loadFromFile(_ filepath: String) -> Bool {
    guard let ifs = ConfigFileStream.legacyOpen(filepath) else {
      return false
    }
    return loadFromStream(ifs)
  }

  private func loadFromStream(_ stream: InputFileStream) -> Bool {
    while var line = stream.getline() {
      _ = Util.chopReturns(&line)
      if line.isEmpty {
        continue
      }

      let rules = splitAllowEmptyBytes(line, 0x09)  // '\t'
      if rules.count == 4 {
        let attributes = parseAttributes(rules[3])
        addRuleWithAttributes(rules[0], rules[1], rules[2], attributes)
      } else if rules.count == 3 {
        addRule(rules[0], rules[1], rules[2])
      } else if rules.count == 2 {
        addRule(rules[0], rules[1], "")
      } else {
        if line.utf8.first != UInt8(ascii: "#") {
          GenmaiLog.error("Format error: \(line)")
        }
        continue
      }
    }

    return true
  }

  public func lookUp(_ input: some StringProtocol) -> Entry? {
    let input = String(input)
    return state.withLock { state in
      if state.caseSensitive {
        return state.entries.lookUp(input)
      } else {
        return state.entries.lookUp(lowerAscii(input))
      }
    }
  }

  /// `keyLength` is in bytes.
  public func lookUpPrefix(_ input: some StringProtocol, _ keyLength: inout Int, _ fixed: inout Bool)
    -> Entry?
  {
    let input = String(input)
    return state.withLock { $0.lookUpPrefix(input, &keyLength, &fixed) }
  }

  public func lookUpPredictiveAll(_ input: some StringProtocol, _ results: inout [Entry]) {
    let input = String(input)
    state.withLock { state in
      if state.caseSensitive {
        state.entries.lookUpPredictiveAll(input, &results)
      } else {
        state.entries.lookUpPredictiveAll(lowerAscii(input), &results)
      }
    }
  }

  // TODO(komatsu): Delete this function.
  public func hasSubRules(_ input: some StringProtocol) -> Bool {
    let input = String(input)
    return state.withLock { state in
      if state.caseSensitive {
        return state.entries.hasSubTrie(input)
      } else {
        return state.entries.hasSubTrie(lowerAscii(input))
      }
    }
  }

  public func hasNewChunkEntry(_ input: some StringProtocol) -> Bool {
    if input.isEmpty {
      return false
    }

    let key = kNewChunkPrefix + input
    var keyLength = 0
    var fixed = false
    _ = lookUpPrefix(key, &keyLength, &fixed)
    if keyLength > 1 {
      return true
    }

    return false
  }

  public func setCaseSensitive(_ caseSensitive: Bool) {
    self.caseSensitive = caseSensitive
  }

  /// Parses special key strings escaped with the pair of "{" and "}"
  /// and returns the parsed string.
  public func parseSpecialKey(_ input: some StringProtocol) -> String {
    state.withLock { $0.specialKeyMap.parse(input) }
  }

  /// Return the default table.
  public static func getDefaultTable() -> Table {
    sharedDefault
  }

  /// Return the default shared table.
  public static func getSharedDefaultTable() -> Table {
    sharedDefault
  }

  private static let sharedDefault = Table()
}

public final class TableManager {
  /// Cache key: calculated from
  ///  commands::Request::SpecialRomanjiTable
  ///  config::Config::PreeditMethod
  ///  config::Config::PunctuationMethod
  ///  config::Config::SymbolMethod
  private struct Key: Hashable {
    var specialRomanjiTable: Int
    var preeditMethod: Int
    var punctuationMethod: Int
    var symbolMethod: Int
  }

  // Table caches.
  private var tableMap: [Key: Table] = [:]
  // Fingerprint for Config::custom_roman_table;
  private var customRomanTableFingerprint: UInt64

  public init() {
    customRomanTableFingerprint = cityFingerprint("")
  }

  /// Return Table for the request and the config
  /// Return nil when no Table is available.
  public func getTable(_ request: Genmai_Commands_Request, _ config: Genmai_Config_Config) -> Table? {
    // calculate the hash depending on the request and the config
    let hash = Key(
      specialRomanjiTable: request.specialRomanjiTable.rawValue,
      preeditMethod: config.preeditMethod.rawValue,
      punctuationMethod: config.punctuationMethod.rawValue,
      symbolMethod: config.symbolMethod.rawValue)

    // When custom_roman_table is set, force to create new table.
    var updateCustomRomanTable = false
    if config.preeditMethod == .roman && config.hasCustomRomanTable
      && !config.customRomanTable.isEmpty
    {
      let fingerprint = config.customRomanTable.withUnsafeBytes { cityFingerprint(bytes: $0) }
      if fingerprint != customRomanTableFingerprint {
        updateCustomRomanTable = true
        customRomanTableFingerprint = fingerprint
      }
    }

    if let table = tableMap[hash] {
      if updateCustomRomanTable {
        // Delete the previous table to update the table.
        tableMap.removeValue(forKey: hash)
      } else {
        return table
      }
    }

    let table = Table()
    if !table.initializeWithRequestAndConfig(request, config) {
      return nil
    }

    tableMap[hash] = table
    return table
  }

  public func clearCaches() {
    tableMap.removeAll()
  }
}
