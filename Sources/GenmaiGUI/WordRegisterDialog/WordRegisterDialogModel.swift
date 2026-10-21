// Port of mozc/src/gui/word_register_dialog/word_register_dialog.{h,cc} (3.35.6354).
//
// GetEnv / SetDefaultEntryFromEnvironmentVariable are done by the host (GenmaiTool), which passes the trimmed
// entries as `initialWord` / `initialReading`. Clipboard fallback and EnableIME are Windows-only and omitted.

import Foundation
import GenmaiBase
import GenmaiClient
import GenmaiCore
import GenmaiProtocol
import Observation

private let kContext = "genmai::gui::WordRegisterDialog"

@MainActor
@Observable
public final class WordRegisterDialogModel {
  /// WordRegisterDialog::ErrorCode.
  public enum ErrorCode: Sendable, Equatable {
    case saveSuccess
    case saveFailure
    case invalidKey
    case invalidValue
    case emptyKey
    case emptyValue
    case fatalError
  }

  public enum Availability: Equatable, Sendable {
    case available
    case unavailable(String)
  }

  static let kMaxEditLength = 100
  static let kMaxReverseConversionLength = 30

  public private(set) var availability: Availability = .available
  public var word = "" {
    didSet { if word.utf16.count > Self.kMaxEditLength { word = Self.truncate(word) } }
  }
  public var reading = "" {
    didSet { if reading.utf16.count > Self.kMaxEditLength { reading = Self.truncate(reading) } }
  }
  public let posList: [String]
  public var posIndex: Int
  public private(set) var dictionaryNames: [String] = []
  public var dictionaryIndex = 0
  public var pendingMessage: GUIMessage?

  public let windowTitle = kProductNameInEnglish

  private let client: any GenmaiClientProtocol
  let storage: UserDictionaryStorage

  public init(
    client: any GenmaiClientProtocol,
    initialWord: String?,
    initialReading: String?,
    storage: UserDictionaryStorage = UserDictionaryStorage(),
    posListProvider: PosListProvider = PosListProvider()
  ) {
    self.client = client
    self.storage = storage
    posList = posListProvider.getPosList()
    // Set the default POS to "名詞".
    posIndex = posListProvider.getPosListDefaultIndex()

    setDefaultEntry(word: initialWord, reading: initialReading)

    do {
      try storage.load()
    } catch {
      GenmaiLog.warning("UserDictionaryStorage::Load() failed")
    }
    if !storage.lock() {
      availability = .unavailable(tr(kContext, "Close dictionary tool before using word register dialog."))
      return
    }

    // Create new dictionary if empty
    let exists = (try? storage.exists()) != nil
    if !exists || storage.dictionariesSize == 0 {
      let name = tr(kContext, "User Dictionary 1")
      do {
        _ = try storage.createDictionary(name)
      } catch {
        availability = .unavailable(tr(kContext, "Unexpected error occurs."))
        return
      }
    }

    // Load Dictionary List
    dictionaryNames = storage.proto.dictionaries.map(\.name)
  }

  /// SetDefaultEntryFromEnvironmentVariable (the values come from the host).
  private func setDefaultEntry(word initialWord: String?, reading initialReading: String?) {
    let entry = Self.trimValue(initialWord ?? "")
    if entry.isEmpty {
      return
    }
    word = entry
    var readingString = Self.trimValue(initialReading ?? "")
    if readingString.isEmpty {
      readingString = getReading(entry)
    }
    reading = readingString
  }

  /// TrimValue: trims spaces and removes CR/LF.
  static func trimValue(_ str: String) -> String {
    str.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\r", with: "")
      .replacingOccurrences(of: "\n", with: "")
  }

  private static func truncate(_ str: String) -> String {
    var result = ""
    for ch in str {
      if result.utf16.count + String(ch).utf16.count > kMaxEditLength { break }
      result.append(ch)
    }
    return result
  }

  /// The OK button is enabled only when both fields are filled (UpdateUIStatus).
  public var isOKEnabled: Bool { !reading.isEmpty && !word.isEmpty }

  /// Whether the reading field should get the initial focus.
  public var focusesReadingInitially: Bool { !word.isEmpty }

  /// CompleteReading: fills the reading from the word when it is empty (editingFinished on the word field).
  public func completeReading() {
    if reading.isEmpty {
      reading = getReading(word)
    }
  }

  /// GetReading: reverse conversion through the session (CONVERT_REVERSE + REVERT).
  func getReading(_ str: String) -> String {
    if str.isEmpty {
      return ""
    }
    if str.utf16.count >= Self.kMaxReverseConversionLength {
      return ""
    }
    var key = ""
    var reverseConversionAvailable = false
    do {
      var keyEvent = KeyEvent()
      keyEvent.specialKey = .on
      if client.sendKey(keyEvent) != nil {
        var command = SessionCommand()
        command.type = .convertReverse
        command.text = str
        if let output = client.sendCommand(command) {
          command.type = .revert
          _ = client.sendCommand(command)
          if output.hasPreedit {
            reverseConversionAvailable = true
            for segment in output.preedit.segment {
              if !segment.hasKey {
                reverseConversionAvailable = false
                key = ""
                break
              }
              key += segment.key
            }
          }
        }
      }
    }
    if !reverseConversionAvailable {
      GenmaiLog.warning("Reverse conversion is not available")
      return ""
    }
    if key.isEmpty || !UserDictionaryUtil.isValidReading(key) {
      GenmaiLog.warning("containing invalid characters")
      return ""
    }
    return key
  }

  /// SaveEntry.
  public func saveEntry() -> ErrorCode {
    let key = reading
    let value = word
    if key.isEmpty {
      return .emptyKey
    }
    if value.isEmpty {
      return .emptyValue
    }
    if !UserDictionaryUtil.isValidReading(key) {
      return .invalidKey
    }
    guard posList.indices.contains(posIndex), let pos = UserPos.toPosType(posList[posIndex]) else {
      return .fatalError
    }
    let index = dictionaryIndex
    if index < 0 || index >= storage.dictionariesSize {
      return .fatalError
    }
    if storage.proto.dictionaries[index].name != dictionaryNames[index] {
      return .fatalError
    }
    var entry = Genmai_UserDictionary_UserDictionary.Entry()
    entry.key = key
    entry.value = value
    entry.pos = pos
    storage.proto.dictionaries[index].entries.append(entry)

    do {
      try storage.save()
    } catch {
      return .saveFailure
    }
    if !client.pingServer() {
      return .saveSuccess
    }
    // CheckVersionOrRestartServer is skipped on macOS in the C++.
    _ = client.reload()
    return .saveSuccess
  }

  /// The OK button (Clicked with AcceptRole). Returns true when the dialog should close.
  public func accept() -> Bool {
    switch saveEntry() {
    case .emptyKey, .emptyValue:
      // key/value is empty. This case will never occur (the OK button is disabled).
      return false
    case .invalidKey:
      showWarning(tr(kContext, "Reading part contains invalid characters."))
      return false
    case .invalidValue:
      showWarning(tr(kContext, "Word part contains invalid characters."))
      return false
    case .fatalError:
      showWarning(tr(kContext, "Unexpected error occurs."))
    case .saveFailure:
      showWarning(tr(kContext, "Failed to update user dictionary."))
    case .saveSuccess:
      break
    }
    storage.unlock()
    return true
  }

  /// Cancel / window closed.
  public func reject() {
    storage.unlock()
  }

  /// LaunchDictionaryTool: releases the lock so that the dictionary tool can open the storage.
  public func prepareLaunchDictionaryTool() {
    storage.unlock()
  }

  private func showWarning(_ text: String) {
    pendingMessage = GUIMessage(kind: .warning, title: windowTitle, text: text)
  }
}
