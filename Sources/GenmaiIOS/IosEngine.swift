// Port of mozc/src/ios/ios_engine.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - The session handler is owned through GenmaiClient's `SessionHandlerBackend` (the macOS IME's in-process
//   server), so the keyboard extension shares its engine setup, SYNC_DATA, the watch dog, the reload commands
//   of the Genmai app and the optional AI conversion hook with the macOS IME. `evalCommandLockGuarded` sends
//   `command.input` to it and stores the output in `command.output`.
// - The class is `@MainActor` (the keyboard extension calls it from UIKit), so the C++ mutex is not needed:
//   `maybeCreateNewChunk` is called by a main-actor timer that cannot run while another command is evaluated,
//   which is what the C++ `try_lock` checks.
// - The C++ `InputConfig*` pointing into the tuple is an `InputModeKind` here.

import Foundation
import GenmaiBase
import GenmaiClient
import GenmaiCore
import GenmaiProtocol
import GenmaiSession

private let kIosSystemDictionaryName = "iOS_system_dictionary"

private func createMobileEngine(_ dataFilePath: String) -> Engine {
  let dataManager: DataManager
  do {
    dataManager = try DataManager.createFromFile(dataFilePath)
  } catch {
    GenmaiLog.error("Fallback to MinimalEngine due to data manager creation error: \(error)")
    return Engine.createEngine()
  }
  do {
    return try Engine.createEngine(dataManager)
  } catch {
    GenmaiLog.error("Failed to create an engine: \(error). Fallback to MinimalEngine")
    return Engine.createEngine()
  }
}

private func initMobileRequest(
  _ tableType: Genmai_Commands_Request.SpecialRomanjiTable, _ request: inout Genmai_Commands_Request
) {
  request.zeroQuerySuggestion = true
  request.mixedConversion = true
  request.updateInputModeFromSurroundingText = false
  request.specialRomanjiTable = tableType
  request.kanaModifierInsensitiveConversion = true
  request.autoPartialSuggestion = true
  request.languageAwareInput = .languageAwareSuggestion
  request.spaceOnAlphanumeric = .commit
}

/// Class to integrate Mozc engine and Gboard client.
/// This class has not been matured yet. It will be iteratively expanded more
/// or replaced with other modules.
@MainActor
public final class IosEngine {
  public enum InputMode: Sendable {
    case hiragana
    case alphabet
    case digit
  }

  /// A configuration of Mozc engine, which corresponds to each of input layout.
  struct InputConfig: Equatable {
    var romajiTable: Genmai_Commands_Request.SpecialRomanjiTable
    var compositionMode: Genmai_Commands_CompositionMode
  }

  /// A set of input configurations for one keyboard set (prime, symbol, and
  /// digit).
  struct InputConfigTuple: Equatable {
    var hiraganaConfig: InputConfig
    var alphabetConfig: InputConfig
    var digitConfig: InputConfig

    subscript(mode: InputMode) -> InputConfig {
      switch mode {
      case .hiragana: hiraganaConfig
      case .alphabet: alphabetConfig
      case .digit: digitConfig
      }
    }
  }

  /// The in-process server (engine + session handler).
  public let backend: SessionHandlerBackend
  public private(set) var sessionId: UInt64 = 0
  /// Not in Mozc: the text before the cursor, sent with the next key (`context.preceding_text`) and then cleared;
  /// the AI conversion hook takes it as the left context of the composition the key starts.
  public var precedingText: String?
  private var currentRequest = Genmai_Commands_Request()
  private var currentConfigTuple: InputConfigTuple
  private var currentInputMode: InputMode = .hiragana
  /// Command called just before. NONE is used as a n/a value.
  private var previousCommand: Genmai_Commands_SessionCommand.CommandType = .none

  /// Initializes the underlying engine instance with the specified data.  If it
  /// fails to load, falls back to the embedded (low quality) engine.
  public init(dataFilePath: String, aiHook: AIConversionHook? = nil) {
    backend = SessionHandlerBackend(engineFactory: { createMobileEngine(dataFilePath) }, aiHook: aiHook)
    currentConfigTuple = Self.getInputConfigTupleFromLayoutName("12KEYS")
  }

  /// Returns the input config tuple that corresponds to the given keyboard layout.
  static func getInputConfigTupleFromLayoutName(_ layout: String) -> InputConfigTuple {
    switch layout {
    case "12KEYS":
      return InputConfigTuple(
        hiraganaConfig: InputConfig(romajiTable: .toggleFlickToHiraganaIntuitive, compositionMode: .hiragana),
        alphabetConfig: InputConfig(romajiTable: .toggleFlickToHalfwidthasciiIos, compositionMode: .halfAscii),
        digitConfig: InputConfig(romajiTable: .toggleFlickToNumber, compositionMode: .halfAscii))
    case "12KEYS_QWERTY":
      return InputConfigTuple(
        hiraganaConfig: InputConfig(romajiTable: .toggleFlickToHiraganaIntuitive, compositionMode: .hiragana),
        alphabetConfig: InputConfig(romajiTable: .qwertyMobileToHalfwidthascii, compositionMode: .halfAscii),
        digitConfig: InputConfig(romajiTable: .qwertyMobileToHalfwidthascii, compositionMode: .halfAscii))
    case "12KEYS_FLICKONLY":
      return InputConfigTuple(
        hiraganaConfig: InputConfig(romajiTable: .flickToHiraganaIntuitive, compositionMode: .hiragana),
        alphabetConfig: InputConfig(romajiTable: .flickToHalfwidthasciiIos, compositionMode: .halfAscii),
        digitConfig: InputConfig(romajiTable: .flickToNumber, compositionMode: .halfAscii))
    case "12KEYS_FLICKONLY_QWERTY":
      return InputConfigTuple(
        hiraganaConfig: InputConfig(romajiTable: .flickToHiraganaIntuitive, compositionMode: .hiragana),
        alphabetConfig: InputConfig(romajiTable: .qwertyMobileToHalfwidthascii, compositionMode: .halfAscii),
        digitConfig: InputConfig(romajiTable: .qwertyMobileToHalfwidthascii, compositionMode: .halfAscii))
    case "QWERTY_JA":
      return InputConfigTuple(
        hiraganaConfig: InputConfig(romajiTable: .qwertyMobileToHiragana, compositionMode: .hiragana),
        alphabetConfig: InputConfig(romajiTable: .qwertyMobileToHalfwidthascii, compositionMode: .halfAscii),
        digitConfig: InputConfig(romajiTable: .qwertyMobileToHalfwidthascii, compositionMode: .halfAscii))
    case "GODAN":
      return InputConfigTuple(
        hiraganaConfig: InputConfig(romajiTable: .godanToHiragana, compositionMode: .hiragana),
        alphabetConfig: InputConfig(romajiTable: .qwertyMobileToHalfwidthascii, compositionMode: .halfAscii),
        digitConfig: InputConfig(romajiTable: .qwertyMobileToHalfwidthascii, compositionMode: .halfAscii))
    default:
      GenmaiLog.error("Unexpected keyboard layout: \(layout). The same config as 12KEYS is used")
      return InputConfigTuple(
        hiraganaConfig: InputConfig(romajiTable: .toggleFlickToHiraganaIntuitive, compositionMode: .hiragana),
        alphabetConfig: InputConfig(romajiTable: .twelveKeysToHalfwidthascii, compositionMode: .halfAscii),
        digitConfig: InputConfig(romajiTable: .qwertyMobileToHalfwidthascii, compositionMode: .halfAscii))
    }
  }

  // The following methods are helpers to populate command proto and send it
  // to the session handler.  Input to and output from the session handler are
  // recorded in `command`.  The return value is the return value of
  // SessionHandler::EvalCommand.

  /// Sets request to mobile spec.  Acceptable `keyboardLayout` are:
  /// "12KEYS", "QWERTY_JA".
  @discardableResult
  public func setMobileRequest(_ keyboardLayout: String, _ command: inout Genmai_Commands_Command) -> Bool {
    command = Genmai_Commands_Command()
    command.input.type = .setRequest
    currentConfigTuple = Self.getInputConfigTupleFromLayoutName(keyboardLayout)
    initMobileRequest(currentConfigTuple.hiraganaConfig.romajiTable, &command.input.request)
    currentRequest = command.input.request
    currentInputMode = .hiragana
    return evalCommandLockGuarded(&command)
  }

  /// Fills mobile settings to config.
  public static func fillMobileConfig(_ config: inout Genmai_Config_Config) {
    config = ConfigHandler.getCopiedConfig()
    config.sessionKeymap = .mobile
    config.useKanaModifierInsensitiveConversion = true
    config.spaceCharacterForm = .fundamentalHalfWidth
  }

  /// Sets the config to the engine.
  @discardableResult
  public func setConfig(_ config: Genmai_Config_Config, _ command: inout Genmai_Commands_Command) -> Bool {
    command = Genmai_Commands_Command()
    command.input.type = .setConfig
    command.input.config = config
    return evalCommandLockGuarded(&command)
  }

  /// Creates a session.  If there's already a created session, it is deleted.
  /// The created session is managed by this instance.
  @discardableResult
  public func createSession(_ command: inout Genmai_Commands_Command) -> Bool {
    if !deleteSession(&command) {
      return false
    }
    command = Genmai_Commands_Command()
    command.input.type = .createSession
    if !evalCommandLockGuarded(&command) {
      return false
    }
    sessionId = command.output.id
    return true
  }

  /// Deletes the session currently managed.
  @discardableResult
  public func deleteSession(_ command: inout Genmai_Commands_Command) -> Bool {
    if sessionId == 0 {
      return true
    }
    command = Genmai_Commands_Command()
    command.input.type = .deleteSession
    command.input.id = sessionId
    if !evalCommandLockGuarded(&command) {
      return false
    }
    sessionId = 0
    return true
  }

  /// Resets the current context.  If the reset is already done before,
  /// nothing happens and false is returned. false is returned on error too.
  @discardableResult
  public func resetContext(_ command: inout Genmai_Commands_Command) -> Bool {
    if previousCommand == .resetContext {
      return false
    }
    command = Genmai_Commands_Command()
    command.input.id = sessionId
    command.input.type = .sendCommand
    command.input.command.type = .resetContext
    return evalCommandLockGuarded(&command)
  }

  /// Sends a special key event (e.g., backspace, arrows).
  @discardableResult
  public func sendSpecialKey(
    _ specialKey: Genmai_Commands_KeyEvent.SpecialKey, _ command: inout Genmai_Commands_Command
  ) -> Bool {
    command = Genmai_Commands_Command()
    command.input.id = sessionId
    command.input.type = .sendKey
    command.input.key.specialKey = specialKey
    attachPrecedingText(&command)
    return evalCommandLockGuarded(&command)
  }

  /// Sends a normal key event.  The first code point of `character` is sent as
  /// key_code.
  @discardableResult
  public func sendKey(_ character: String, _ command: inout Genmai_Commands_Command) -> Bool {
    command = Genmai_Commands_Command()
    command.input.id = sessionId
    command.input.type = .sendKey
    command.input.key.keyCode = Util.utf8ToCodepoint(character)
    command.input.key.mode = currentConfigTuple[currentInputMode].compositionMode
    let kNoModifiers: UInt32 = 0
    command.input.key.modifiers = kNoModifiers
    attachPrecedingText(&command)
    return evalCommandLockGuarded(&command)
  }

  private func attachPrecedingText(_ command: inout Genmai_Commands_Command) {
    if let text = precedingText {
      command.input.context.precedingText = text
      precedingText = nil
    }
  }

  /// Maybe creates a new chunk by sending STOP_KEY_TOGGLING command. This method
  /// is intended to be used by a timer to exit toggle state in 12-key
  /// toggle flick layout.  Thus, this method fails if the current Romaji table is
  /// not a toggle table.
  @discardableResult
  public func maybeCreateNewChunk(_ command: inout Genmai_Commands_Command) -> Bool {
    switch currentRequest.specialRomanjiTable {
    case .toggleFlickToHalfwidthasciiIos, .toggleFlickToHiraganaIntuitive, .toggleFlickToNumber,
      .twelveKeysToHalfwidthascii:
      break
    default:
      return false
    }
    command = Genmai_Commands_Command()
    command.input.id = sessionId
    command.input.type = .sendCommand
    command.input.command.type = .stopKeyToggling
    // The C++ evaluates without updating previous_command_.
    guard let output = backend.evalCommand(command.input) else { return false }
    command.output = output
    return true
  }

  /// Sends a session command.
  @discardableResult
  /// Not in Mozc: re-runs the suggestion without changing the composition (`SessionHandlerBackend.refreshSuggestion`;
  /// the last kana keeps toggling).
  public func refreshSuggestion(cursor: UInt32) -> Genmai_Commands_Output? {
    previousCommand = .moveCursor
    return backend.refreshSuggestion(id: sessionId, cursor: cursor)
  }

  public func sendSessionCommand(
    _ sessionCommand: Genmai_Commands_SessionCommand, _ command: inout Genmai_Commands_Command
  ) -> Bool {
    command = Genmai_Commands_Command()
    command.input.id = sessionId
    command.input.type = .sendCommand
    command.input.command = sessionCommand
    return evalCommandLockGuarded(&command)
  }

  // Convenient aliases for SendSessionCommand.

  @discardableResult
  public func submit(_ command: inout Genmai_Commands_Command) -> Bool {
    var sessionCommand = Genmai_Commands_SessionCommand()
    sessionCommand.type = .submit
    return sendSessionCommand(sessionCommand, &command)
  }

  @discardableResult
  public func submitCandidate(_ index: Int32, _ command: inout Genmai_Commands_Command) -> Bool {
    var sessionCommand = Genmai_Commands_SessionCommand()
    sessionCommand.type = .submitCandidate
    sessionCommand.id = index
    return sendSessionCommand(sessionCommand, &command)
  }

  @discardableResult
  public func undoOrRewind(_ command: inout Genmai_Commands_Command) -> Bool {
    var sessionCommand = Genmai_Commands_SessionCommand()
    sessionCommand.type = .undoOrRewind
    return sendSessionCommand(sessionCommand, &command)
  }

  private func evalCommandLockGuarded(_ command: inout Genmai_Commands_Command) -> Bool {
    if command.input.hasCommand {
      previousCommand = command.input.command.type
    } else {
      previousCommand = .none
    }
    guard let output = backend.evalCommand(command.input) else { return false }
    command.output = output
    return true
  }

  /// Switches input mode by configuring Mozc engine.
  @discardableResult
  public func switchInputMode(_ mode: InputMode) -> Bool {
    if currentInputMode == mode {
      return true
    }
    if !setSpecialRomajiTable(currentConfigTuple[mode].romajiTable) {
      return false
    }
    currentInputMode = mode
    return true
  }

  /// The input mode set by `switchInputMode` (hiragana after `setMobileRequest`).
  public var inputMode: InputMode { currentInputMode }

  private func setSpecialRomajiTable(_ table: Genmai_Commands_Request.SpecialRomanjiTable) -> Bool {
    var command = Genmai_Commands_Command()
    command.input.type = .setRequest
    command.input.request = currentRequest
    command.input.request.specialRomanjiTable = table
    if !evalCommandLockGuarded(&command) {
      return false
    }
    currentRequest = command.input.request
    return true
  }

  /// Imports a dictionary of TSV format as a user dictionary, where each line
  /// should be formatted as: READING<tab>WORD<tab>POS.  If the content is empty,
  /// it deletes the user dictionary.  This method is intended to be used for iOS
  /// system dictionary.
  @discardableResult
  public func importUserDictionary(_ tsvContent: String, _ command: inout Genmai_Commands_Command) -> Bool {
    var storage = Genmai_UserDictionary_UserDictionaryStorage()
    if !tsvContent.isEmpty {
      var dic = Genmai_UserDictionary_UserDictionary()
      dic.name = kIosSystemDictionaryName
      for line in tsvContent.split(separator: "\n", omittingEmptySubsequences: true) {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        if fields.count < 3 || fields[0].isEmpty || fields[1].isEmpty {
          continue
        }
        var entry = Genmai_UserDictionary_UserDictionary.Entry()
        entry.key = String(fields[0])
        entry.value = String(fields[1])
        if fields[2] == "顔文字" {
          entry.pos = .emoticon
        } else {
          entry.pos = .noPos
        }
        dic.entries.append(entry)
      }
      storage.dictionaries.append(dic)
    }
    let kUserDictionaryFile = "user://user_dictionary.db"
    let serialized: [UInt8]
    do {
      serialized = try storage.serializedBytes()
    } catch {
      GenmaiLog.error("Cannot serialize the user dictionary: \(error)")
      return false
    }
    return ConfigFileStream.atomicUpdate(kUserDictionaryFile, serialized) && reload(&command)
  }

  /// Clear user input history of both conversion and prediction from storage.
  @discardableResult
  public func clearUserHistory(_ command: inout Genmai_Commands_Command) -> Bool {
    command = Genmai_Commands_Command()
    command.input.id = sessionId
    command.input.type = .clearUserHistory
    if !evalCommandLockGuarded(&command) {
      return false
    }

    command = Genmai_Commands_Command()
    command.input.id = sessionId
    command.input.type = .clearUserPrediction
    if !evalCommandLockGuarded(&command) {
      return false
    }

    return true
  }

  private func reload(_ command: inout Genmai_Commands_Command) -> Bool {
    command = Genmai_Commands_Command()
    command.input.id = sessionId
    command.input.type = .reload
    return evalCommandLockGuarded(&command)
  }
}
