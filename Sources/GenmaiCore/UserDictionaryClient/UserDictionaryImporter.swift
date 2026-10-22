// Port of mozc/src/client/user_dictionary/user_dictionary_importer.{h,cc} (3.35.6354).
//
// Byte semantics: text lines and raw entries are UTF-8 *byte* arrays (C++
// std::string), so lines with invalid UTF-8 (e.g. a Shift_JIS file read as
// UTF-8) are rejected by entry validation exactly as in C++ instead of being
// silently repaired with U+FFFD.
//
// Errors: functions returning absl::Status in C++ throw the
// `UserDictionaryUtil.ExtendedErrorCode` stored in `status.raw_code()`.
// The dictionary passed `inout` keeps the entries added before the error
// (e.g. IMPORT_INVALID_ENTRIES still imports the valid entries).

import GenmaiBase
import GenmaiProtocol

// A raw entry to be read.
public struct RawEntry: Sendable, Equatable {
  public var key: [UInt8] = []
  public var value: [UInt8] = []
  /// Mozc extension: pos can encode locale. e.g. 名詞:en
  public var pos: [UInt8] = []
  public var comment: [UInt8] = []

  public init() {}

  public init(key: String, value: String, pos: String, comment: String = "") {
    self.key = Array(key.utf8)
    self.value = Array(value.utf8)
    self.pos = Array(pos.utf8)
    self.comment = Array(comment.utf8)
  }

  public mutating func clear() {
    key.removeAll()
    value.removeAll()
    pos.removeAll()
    comment.removeAll()
  }
}

/// An abstract class for representing an input device for user dictionary.
/// It runs over only valid lines which show entries in input.
public protocol InputIteratorInterface: AnyObject {
  /// Return true if the input iterator is available.
  var isAvailable: Bool { get }

  /// Return true if entry is read successfully.
  /// Next method doesn't have to convert the POS of entry.
  func next(_ rawEntry: inout RawEntry) -> Bool
}

/// An abstract class for reading a text file per line.  It runs over
/// all lines, e.g. comment lines.
/// As we'd like to use QTextFileStream to load UTF16 files, make an
/// interface class for reading text per line.
public protocol TextLineIteratorInterface: AnyObject {
  /// Return true text line iterator is available.
  var isAvailable: Bool { get }

  /// Read a line and convert its encoding to UTF-8.
  /// The TextLineIteratorInterface class takes a responsibility of character
  /// set conversion. The returned line must always be stored in UTF-8 bytes.
  /// Returns nil at the end.
  func next() -> [UInt8]?

  /// Reset the current position.
  func reset()
}

/// A wrapper for string. The string should contain utf-8 characters.
/// This class should resolve CR/LF issue.
public final class StringTextLineIterator: TextLineIteratorInterface {
  private let data: [UInt8]
  private var first = 0

  public init(bytes: some Collection<UInt8>) {
    data = Array(bytes)
  }

  public convenience init(_ data: String) {
    self.init(bytes: data.utf8)
  }

  public var isAvailable: Bool { data.count != first }

  public func next() -> [UInt8]? {
    if !isAvailable {
      return nil
    }

    var it = first
    while it < data.count {
      let c = data[it]
      if c == UInt8(ascii: "\n") || c == UInt8(ascii: "\r") {
        let line = Array(data[first..<it])
        // Handles CR/LF issue.
        if c == UInt8(ascii: "\r") && it + 1 < data.count && data[it + 1] == UInt8(ascii: "\n") {
          it += 1
        }
        it += 1
        first = it
        return line
      }
      it += 1
    }

    let line = Array(data[first...])
    first = data.count
    return line
  }

  public func reset() { first = 0 }
}

/// UserDictionaryImporter namespace (`mozc::user_dictionary` free functions).
public enum UserDictionaryImporter {
  public typealias UserDictionary = Genmai_UserDictionary_UserDictionary
  public typealias ExtendedErrorCode = UserDictionaryUtil.ExtendedErrorCode

  /// List of IMEs.
  public enum IMEType: Int, Sendable, CaseIterable {
    case imeAutoDetect = 0
    case google = 1
    case msime = 2
    case atok = 3
    case kotoeri = 4
    case gboardV1 = 5
    case numImes = 6
  }

  /// List of character encodings.
  public enum EncodingType: Int, Sendable, CaseIterable {
    case encodingAutoDetect = 0
    case utf8 = 1
    case utf16 = 2
    case shiftJIS = 3
    case numEncodings = 4
  }

  private struct EntryHashKey: Hashable {
    let key: String
    let value: String
    let pos: Int
  }

  // absl::HashOf(entry.key(), entry.value(), entry.pos()). The Swift port
  // compares the triple itself (no hash-collision false positives).
  private static func hashOf(_ entry: UserDictionary.Entry) -> EntryHashKey {
    EntryHashKey(key: entry.key, value: entry.value, pos: entry.pos.rawValue)
  }

  // Normalizes POS (removes full width ascii and half width katakana).
  private static func normalizePos(_ input: String) -> String {
    let tmp = Japanese.fullWidthAsciiToHalfWidthAscii(input)
    return Japanese.halfWidthKatakanaToFullWidthKatakana(tmp)
  }

  private static func splitPosAndLocale(_ pos: String) -> (Substring, Substring) {
    let bytes = pos.utf8
    if let colon = bytes.firstIndex(of: UInt8(ascii: ":")) {
      return (pos[..<colon], pos[bytes.index(after: colon)...])
    }
    return (pos[...], "")
  }

  private static func decodeUtf8(_ bytes: [UInt8]) -> String? {
    Strings.isValidUtf8(bytes) ? String(decoding: bytes, as: UTF8.self) : nil
  }

  /// Convert POS of a third party IME to that of Mozc using the given mapping.
  public static func convertEntry(_ from: RawEntry, _ to: inout UserDictionary.Entry) -> Bool {
    to = UserDictionary.Entry()

    if from.pos.isEmpty {
      return false
    }

    // A pos with invalid UTF-8 never matches the (valid UTF-8) map keys.
    guard let fromPos = decodeUtf8(from.pos) else {
      GenmaiLog.warning("Invalid POS is passed: \(String(decoding: from.pos, as: UTF8.self))")
      return false
    }
    let normalizedPos = normalizePos(fromPos)
    var (pos, locale) = splitPosAndLocale(normalizedPos)

    // ATOK's POS has a special marker for distinguishing auto-registered
    // words/manually-registered words. Remove the mark here.
    if pos.utf8.last == UInt8(ascii: "$") {
      pos = Substring(pos.utf8.dropLast())
    }
    if pos.utf8.last == UInt8(ascii: "*") {
      pos = Substring(pos.utf8.dropLast())
    }

    // Search for mapping for the given POS.
    guard let mapped = kPosMap[String(pos)] else {
      GenmaiLog.warning("Invalid POS is passed: \(fromPos)")
      return false
    }

    guard let posType = mapped else {
      return false
    }

    // Key / value / comment with invalid UTF-8 are rejected by ValidateEntry
    // in C++; Swift strings cannot hold them, so reject them here.
    guard let key = decodeUtf8(from.key), let value = decodeUtf8(from.value),
      let comment = decodeUtf8(from.comment)
    else {
      return false
    }

    to.key = UserDictionaryUtil.normalizeReading(key)
    to.value = value
    to.pos = posType

    // Copy comment.
    if !comment.isEmpty {
      to.comment = comment
    }

    // Sets locale field.
    if !locale.isEmpty {
      to.locale = String(locale)
    }

    // Validation.
    return UserDictionaryUtil.validateEntryCode(to) == .ok
  }

  /// Import a dictionary from InputIteratorInterface.
  /// This is the most generic interface.
  /// Throws the ExtendedErrorCode (C++ raw_code()).
  public static func importFromIterator(
    _ iter: (any InputIteratorInterface)?, _ userDic: inout UserDictionary
  ) throws(ExtendedErrorCode) {
    guard let iter else {
      GenmaiLog.error("iter or user_dic is nullptr")
      throw .importFatal
    }

    var ret = ExtendedErrorCode.ok

    var existentEntries = Set<EntryHashKey>()
    for entry in userDic.entries {
      existentEntries.insert(hashOf(entry))
    }

    var rawEntry = RawEntry()
    while iter.next(&rawEntry) {
      if UserDictionaryStorage.isDictionaryFull(userDic) {
        GenmaiLog.warning("Too many words in one dictionary")
        throw .importTooManyWords
      }

      if rawEntry.key.isEmpty && rawEntry.value.isEmpty && rawEntry.comment.isEmpty {
        // Empty entry is just skipped. It could be annoying if we show a
        // warning dialog when these empty candidates exist.
        continue
      }

      var entry = UserDictionary.Entry()
      if !convertEntry(rawEntry, &entry) {
        GenmaiLog.warning("Entry is not valid")
        ret = .importInvalidEntries
        continue
      }

      // Don't register words if it is already in the current dictionary.
      if !existentEntries.insert(hashOf(entry)).inserted {
        continue
      }

      userDic.entries.append(entry)
    }

    if ret != .ok {
      throw ret
    }
  }

  /// Import a dictionary from TextLineIterator.
  public static func importFromTextLineIterator(
    _ imeType: IMEType, _ iter: any TextLineIteratorInterface, _ userDic: inout UserDictionary
  ) throws(ExtendedErrorCode) {
    let textIter = TextInputIterator(imeType, iter)
    if textIter.imeType == .numImes {
      throw .importNotSupported
    }

    try importFromIterator(textIter, &userDic)
  }

  /// Guess IME type from the first line of IME file.
  /// Return "NUM_IMES" if the format is unknown.
  public static func guessIMEType(_ line: some Collection<UInt8>) -> IMEType {
    let line = Array(line)
    if line.isEmpty {
      return .numImes
    }

    // Util::LowerString on the (possibly invalid) UTF-8 line: only ASCII
    // matters for the prefixes below.
    var lowerString = String(decoding: line, as: UTF8.self)
    Util.lowerString(&lowerString)
    let lower = Array(lowerString.utf8)

    if lower.starts(with: "!microsoft ime".utf8) {
      return .msime
    }

    // Old ATOK format (!!DICUT10) is not supported for now
    // http://b/2455897
    if lower.starts(with: "!!dicut".utf8) && lower.count > 7 {
      let version = String(decoding: lower[7...], as: UTF8.self)
      if NumberUtil.simpleAtoi(version) >= 11 {
        return .atok
      } else {
        return .numImes
      }
    }

    if lower.starts(with: "!!atok_tango_text_header".utf8) {
      return .atok
    }

    let tab = UInt8(ascii: "\t")
    if line.first == UInt8(ascii: "\"") && line.last == UInt8(ascii: "\"") && !line.contains(tab) {
      return .kotoeri
    }

    if lower.starts(with: "# gboard dictionary version:1".utf8) {
      return .gboardV1
    }

    if line.first == UInt8(ascii: "#") || line.contains(tab) {
      return .google
    }

    return .numImes
  }

  public static func guessIMEType(_ line: String) -> IMEType {
    guessIMEType(line.utf8)
  }

  /// Return the final IME type from user_ime_type and guessed_ime_type.
  public static func determineFinalIMEType(_ userImeType: IMEType, _ guessedImeType: IMEType)
    -> IMEType
  {
    var resultImeType = IMEType.numImes

    if userImeType == .imeAutoDetect {
      // Trust guessed type.
      resultImeType = guessedImeType
    } else if userImeType == .google {
      // MOZC is compatible with MS-IME and ATOK.
      // Even if the auto detection failed, try to use Mozc format.
      if guessedImeType != .kotoeri {
        resultImeType = userImeType
      }
    } else {
      // ATOK, MS-IME and Kotoeri can be detected with 100% accuracy.
      if guessedImeType == userImeType {
        resultImeType = userImeType
      }
    }

    return resultImeType
  }

  /// Guess encoding type of a string.
  public static func guessEncodingType(_ str: some Collection<UInt8>) -> EncodingType {
    let str = Array(str)
    // Unicode BOM.
    if str.count >= 2 && ((str[0] == 0xFF && str[1] == 0xFE) || (str[0] == 0xFE && str[1] == 0xFF)) {
      return .utf16
    }

    // UTF-8 BOM.
    if str.count >= 3 && str[0] == 0xEF && str[1] == 0xBB && str[2] == 0xBF {
      return .utf8
    }

    // Count valid UTF8 characters.
    // TODO(taku): Improve the accuracy by making a DFA.
    var validUtf8 = 0
    var validScript = 0
    var i = 0
    while i < str.count {
      let dr = Utf8Internal.decode(str, from: i)
      if !dr.ok {
        break
      }
      validUtf8 += dr.bytesSeen

      // "\n\r\t " or Japanese code point
      let codepoint = dr.codePoint
      if codepoint == 0x000A || codepoint == 0x000D || codepoint == 0x0020 || codepoint == 0x0009
        || Util.getScriptType(codepoint) != .unknownScript
      {
        validScript += dr.bytesSeen
      }
      i += dr.bytesSeen
    }

    // TODO(taku): No theoretical justification for these parameters.
    // (An empty string gives NaN in C++, so both comparisons are false.)
    let size = Double(str.count)
    if 1.0 * Double(validUtf8) / size >= 0.9 && 1.0 * Double(validScript) / size >= 0.5 {
      return .utf8
    }

    return .shiftJIS
  }

  public static func guessEncodingType(_ str: String) -> EncodingType {
    guessEncodingType(str.utf8)
  }

  /// Guess encoding type of a file.
  public static func guessFileEncodingType(_ filename: String) -> EncodingType {
    let mmap: Mmap
    do {
      mmap = try Mmap.map(filename, .readOnly)
    } catch {
      GenmaiLog.error("cannot open: \(filename): \(error)")
      return .numEncodings
    }
    let kMaxCheckSize = 1024
    return guessEncodingType(mmap.data.prefix(kMaxCheckSize))
  }
}

/// A special input iterator to read entries from TextLineIteratorInterface.
public final class TextInputIterator: InputIteratorInterface {
  public typealias IMEType = UserDictionaryImporter.IMEType

  public private(set) var imeType: IMEType
  private let iter: any TextLineIteratorInterface

  public init(_ imeType: IMEType, _ iter: any TextLineIteratorInterface) {
    self.imeType = .numImes
    self.iter = iter
    if !iter.isAvailable {
      return
    }

    var guessedType = IMEType.numImes
    if let line = iter.next() {
      guessedType = UserDictionaryImporter.guessIMEType(line)
      iter.reset()
    }

    self.imeType = UserDictionaryImporter.determineFinalIMEType(imeType, guessedType)

    GenmaiLog.info("Setting type to: \(self.imeType.rawValue)")
  }

  public var isAvailable: Bool {
    iter.isAvailable && imeType != .imeAutoDetect && imeType != .numImes
  }

  public func next(_ entry: inout RawEntry) -> Bool {
    if !isAvailable {
      GenmaiLog.error("iterator is not available")
      return false
    }

    entry.clear()

    while var line = iter.next() {
      // Util::ChopReturns.
      while let last = line.last, last == UInt8(ascii: "\r") || last == UInt8(ascii: "\n") {
        line.removeLast()
      }
      // Skip empty lines.
      if line.isEmpty {
        continue
      }
      // Skip comment lines.
      if ((imeType == .msime || imeType == .atok) && line[0] == UInt8(ascii: "!"))
        || ((imeType == .google || imeType == .gboardV1) && line[0] == UInt8(ascii: "#"))
        || (imeType == .kotoeri && line.starts(with: "//".utf8))
      {
        continue
      }

      var values: [[UInt8]]
      switch imeType {
      case .msime, .atok, .google, .gboardV1:
        values = line.split(separator: UInt8(ascii: "\t"), omittingEmptySubsequences: false)
          .map(Array.init)
        if values.count < 3 {
          continue  // Ignore this line.
        }
        entry.key = values[0]
        entry.value = values[1]
        if imeType == .gboardV1 {
          // values[2] specifies locale, not POS.
          // Use NO_POS as a default value.
          // pos = "品詞なし" + ":" + locale
          entry.pos = Array("品詞なし:".utf8) + values[2]
        } else {
          entry.pos = values[2]
        }
        if values.count >= 4 {
          entry.comment = values[3]
        }
        return true
      case .kotoeri:
        values = TextInputIterator.splitCSV(line)
        if values.count < 3 {
          continue  // Ignore this line.
        }
        entry.key = values[0]
        entry.value = values[1]
        entry.pos = values[2]
        return true
      default:
        GenmaiLog.error("Unknown format: \(imeType.rawValue)")
        return false
      }
    }

    return false
  }

  // Util::SplitCSV on bytes (GenmaiBase's Util.splitCSV takes a String and
  // would repair invalid UTF-8). Same algorithm.
  private static func splitCSV(_ input: [UInt8]) -> [[UInt8]] {
    // A mutable copy with the terminating '\0' of std::string.
    var buf = input
    let eos = buf.count
    buf.append(0)
    var str = 0
    var start = 0
    var end = 0
    var output: [[UInt8]] = []

    while str < eos {
      while buf[str] == 0x20 || buf[str] == 0x09 {
        str += 1
      }

      if buf[str] == 0x22 {  // '"'
        str += 1
        start = str
        end = start
        while str < eos {
          if buf[str] == 0x22 {
            str += 1
            if buf[str] != 0x22 { break }
          }
          buf[end] = buf[str]
          end += 1
          str += 1
        }
        str = buf[str..<eos].firstIndex(of: 0x2C) ?? eos
      } else {
        start = str
        str = buf[str..<eos].firstIndex(of: 0x2C) ?? eos
        end = str
      }
      var endIsEmpty = false
      if buf[end] == 0x2C && end == eos - 1 {
        endIsEmpty = true
      }
      output.append(Array(buf[start..<end]))
      if endIsEmpty {
        output.append([])
      }

      str += 1
    }
    return output
  }
}
