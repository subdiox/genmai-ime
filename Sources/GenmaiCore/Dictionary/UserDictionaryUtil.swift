// Port of mozc/src/dictionary/user_dictionary_util.{h,cc} (3.35.6354).

import GenmaiBase
import GenmaiProtocol

/// `mozc::user_dictionary` free functions (user_dictionary_util.h).
public enum UserDictionaryUtil {
  /// `ExtendedErrorCode`: extended error code. In C++ it is stored in
  /// absl::Status (`ToStatus`, read back via `status.raw_code()`); in Swift the
  /// code itself is thrown as the error.
  public enum ExtendedErrorCode: Int, Error, Sendable {
    case ok = 0

    // Migrated from UserDictionaryCommandStatus::Status.
    case unknownError = 100
    case fileNotFound
    case invalidFileFormat

    // Note: currently if we receive this error status,
    // the file is actually saved.
    case fileSizeLimitExceeded

    case dictionarySizeLimitExceeded
    case entrySizeLimitExceeded
    case unknownDictionaryId
    case entryIndexOutOfRange

    // Errors for dictionary names.
    case dictionaryNameEmpty
    case dictionaryNameTooLong
    case dictionaryNameContainsInvalidCharacter
    case dictionaryNameDuplicated

    // Errors for entry data.
    case readingEmpty
    case readingTooLong
    case readingContainsInvalidCharacter
    case wordEmpty
    case wordTooLong
    case wordContainsInvalidCharacter
    case invalidPosType
    case commentTooLong
    case commentContainsInvalidCharacter

    // Errors for importing.
    case importTooManyWords
    case importNotSupported
    case importInvalidEntries
    case importFatal
    case importUnknownError
  }

  // Maximum string length in UserDictionaryEntry's field
  static let kMaxStringSize = 300
  private static let kInvalidChars: [UInt8] = Array("\n\r\t".utf8)
  private static let kUserDictionaryFile = "user://user_dictionary.db"

  private static func internalValidateNormalizedReading(_ reading: String) -> Bool {
    func inRange(_ c: UInt32, _ lo: UInt32, _ hi: UInt32) -> Bool { lo <= c && c <= hi }
    for scalar in reading.unicodeScalars {
      let c = scalar.value
      if !inRange(c, 0x0021, 0x007E)  // Basic Latin (Ascii)
        && !inRange(c, 0x3041, 0x3096)  // Hiragana
        && !inRange(c, 0x309B, 0x309C)  // KATAKANA-HIRAGANA VOICED/SEMI-VOICED
        // SOUND MARK
        && !inRange(c, 0x30FB, 0x30FC)  // Nakaten, Prolonged sound mark
        && !inRange(c, 0x3001, 0x3002)  // Japanese punctuation marks
        && !inRange(c, 0x300C, 0x300F)  // Japanese brackets
        && !inRange(c, 0x301C, 0x301C)  // Japanese Wavedash
      {
        GenmaiLog.info("Invalid character in reading.")
        return false
      }
    }
    return true
  }

  private static func isTooLongString(_ str: some Collection<UInt8>) -> Bool {
    str.count > kMaxStringSize
  }

  private static func containsInvalidChars(_ str: some Collection<UInt8>) -> Bool {
    str.contains { kInvalidChars.contains($0) } || !Strings.isValidUtf8(str)
  }

  /// Returns true if all characters in the given string is a legitimate
  /// character for reading.
  public static func isValidReading(_ reading: String) -> Bool {
    internalValidateNormalizedReading(normalizeReading(reading))
  }

  /// Performs various kinds of character normalization such as
  /// katakana-> hiragana and full-width ascii -> half width
  /// ascii. Identity of reading of a word should be defined by the
  /// output of this function.
  public static func normalizeReading(_ input: some StringProtocol) -> String {
    let tmp1 = Japanese.fullWidthAsciiToHalfWidthAscii(input)
    let tmp2 = Japanese.halfWidthKatakanaToFullWidthKatakana(tmp1)
    return Japanese.katakanaToHiragana(tmp2)
  }

  /// Validates the given entry; throws the `ExtendedErrorCode` on failure.
  /// The validation process is as follows:
  /// - Checks the reading
  ///   - if it isn't empty
  ///   - if it doesn't exceed the max length
  ///   - if it doesn't contain invalid character
  /// - Checks the word
  ///   - if it isn't empty
  ///   - if it doesn't exceed the max length
  ///   - if it doesn't contain invalid character
  /// - Checks the comment
  ///   - if it isn't exceed the max length
  ///   - if it doesn't contain invalid character
  /// - Checks if a valid pos type is set.
  public static func validateEntry(_ entry: Genmai_UserDictionary_UserDictionary.Entry) throws(
    ExtendedErrorCode
  ) {
    let code = validateEntry(
      key: entry.key.utf8, value: entry.value.utf8, comment: entry.comment.utf8,
      hasPos: entry.hasPos)
    if code != .ok {
      throw code
    }
  }

  /// ValidateEntry on raw UTF-8 bytes. Swift `String`s cannot hold invalid
  /// UTF-8, so the user dictionary loader validates the undecoded protobuf
  /// fields with this function (as C++ does with `std::string`).
  /// `hasPos` is false when the pos field is unset or holds an unknown enum
  /// value (PosType_IsValid).
  static func validateEntry(
    key reading: some Collection<UInt8>, value word: some Collection<UInt8>,
    comment: some Collection<UInt8>, hasPos: Bool
  ) -> ExtendedErrorCode {
    // Validate reading.
    if reading.isEmpty {
      return .readingEmpty
    }
    if isTooLongString(reading) {
      return .readingTooLong
    }
    if containsInvalidChars(reading) {
      return .readingContainsInvalidCharacter
    }

    // Validate word.
    if word.isEmpty {
      return .wordEmpty
    }
    if isTooLongString(word) {
      return .wordTooLong
    }
    if containsInvalidChars(word) {
      return .wordContainsInvalidCharacter
    }

    // Validate comment.
    if isTooLongString(comment) {
      return .commentTooLong
    }
    if containsInvalidChars(comment) {
      return .commentContainsInvalidCharacter
    }

    // Validate pos.
    if !hasPos {
      return .invalidPosType
    }
    return .ok
  }

  /// Non-throwing variant of `validateEntry`: returns `.ok` on success.
  public static func validateEntryCode(_ entry: Genmai_UserDictionary_UserDictionary.Entry)
    -> ExtendedErrorCode
  {
    do {
      try validateEntry(entry)
      return .ok
    } catch {
      return error
    }
  }

  /// Sanitizes a dictionary entry so that it's acceptable to the
  /// class. A user of the class may want this function to make sure an
  /// error want happen before calling AddEntry() and other
  /// methods. Return true if the entry is changed.
  @discardableResult
  public static func sanitizeEntry(_ entry: inout Genmai_UserDictionary_UserDictionary.Entry) -> Bool {
    func sanitizeField(_ field: inout String) -> Bool {
      if let sanitized = TextNormalizer.sanitizeText(field, kMaxStringSize) {
        field = sanitized
        return true
      }
      return false
    }

    var modified = false
    modified = sanitizeField(&entry.key) || modified
    modified = sanitizeField(&entry.value) || modified
    modified = sanitizeField(&entry.comment) || modified
    // PosType_IsValid(entry->pos()) is always true for the Swift enum (an
    // unset field reads as the default NOUN, as in C++).
    return modified
  }

  /// Validates the given dictionary name; throws the `ExtendedErrorCode` on
  /// failure.
  public static func validateDictionaryName(_ dictionaryName: String) throws(ExtendedErrorCode) {
    if dictionaryName.isEmpty {
      throw .dictionaryNameEmpty
    }
    if isTooLongString(dictionaryName.utf8) {
      throw .dictionaryNameTooLong
    }
    if containsInvalidChars(dictionaryName.utf8) {
      throw .dictionaryNameContainsInvalidCharacter
    }
  }

  /// Returns the file name of UserDictionary.
  public static func getUserDictionaryFileName() -> String {
    ConfigFileStream.getFileName(kUserDictionaryFile)
  }
}
