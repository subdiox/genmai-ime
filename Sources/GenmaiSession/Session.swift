// Port of mozc/src/session/session.{h,cc} (3.35.6354).
//
// Session class of Mozc server.
//
// Swift notes: `commands::Command*` parameters are `inout Genmai_Commands_Command`.
// `std::unique_ptr<ImeContext>` is an `ImeContext` reference; the undo stack
// holds copies made by `ImeContext(copying:)` (which clones the converter).

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol

// Maximum size of multiple undo stack.
private let kMultipleUndoMaxSize = 10

public typealias Command = Genmai_Commands_Command
typealias KeyEvent = Genmai_Commands_KeyEvent

// Set input mode if the current input mode is not the given mode.
private func switchInputMode(_ mode: TransliterationType, _ composer: inout Composer) {
  if composer.getInputMode() != mode {
    composer.setInputMode(mode)
  }
  composer.setNewInput()
}

// Set input mode to the |composer| if the input mode of |composer| is not
// the given |mode|.
private func applyCompositionMode(_ mode: Genmai_Commands_CompositionMode, _ composer: inout Composer) {
  switch mode {
  case .hiragana:
    switchInputMode(.hiragana, &composer)
  case .fullKatakana:
    switchInputMode(.fullKatakana, &composer)
  case .halfKatakana:
    switchInputMode(.halfKatakana, &composer)
  case .fullAscii:
    switchInputMode(.fullAscii, &composer)
  case .halfAscii:
    switchInputMode(.halfAscii, &composer)
  default:
    GenmaiLog.error("ime on with invalid mode")
  }
}

// Return true if the specified key event consists of any modifier key only.
private func isPureModifierKeyEvent(_ key: KeyEvent) -> Bool {
  if key.hasKeyCode {
    return false
  }
  if key.hasSpecialKey {
    return false
  }
  if key.modifierKeys.isEmpty {
    return false
  }
  return true
}

private func isPureSpaceKey(_ key: KeyEvent) -> Bool {
  if key.hasKeyCode {
    return false
  }
  if !key.modifierKeys.isEmpty {
    return false
  }
  if !key.hasSpecialKey {
    return false
  }
  if key.specialKey != .space {
    return false
  }
  return true
}

// Set session state to the given state and also update related status.
private func setSessionState(_ state: ImeContext.State, _ context: ImeContext) {
  let prevState = context.state
  context.state = state
  switch state {
  case .direct, .precomposition:
    context.data.composer.reset()
  case .conversion:
    context.data.composer.resetInputMode()
  case .composition:
    if prevState == .precomposition {
      // Notify the start of composition to the converter so that internal
      // state can be refreshed by the client context (especially by
      // preceding text).
      context.converter.onStartComposition(context.clientContext)
    }
  default:
    // Do nothing.
    break
  }
}

private func setStateToPredompositionAndCancel(_ context: ImeContext) {
  setSessionState(.precomposition, context)
  // mutable_converter's internal state should be updated by calling Cancel().
  // Internal state contains:
  // - candidate list
  // - result text to commit
  if !context.converter.checkState(EngineConverterState.composition) {
    context.converter.cancel()
  }
}

private func toCompositionMode(_ type: TransliterationType) -> Genmai_Commands_CompositionMode {
  var mode = Genmai_Commands_CompositionMode.hiragana
  switch type {
  case .hiragana:
    mode = .hiragana
  case .fullKatakana:
    mode = .fullKatakana
  case .halfKatakana:
    mode = .halfKatakana
  case .fullAscii:
    mode = .fullAscii
  case .halfAscii:
    mode = .halfAscii
  default:
    GenmaiLog.error("Unknown input mode: \(type)")
  // use HIRAGANA as a default.
  }
  return mode
}

private func getEffectiveStateForTestSendKey(_ key: KeyEvent, _ state: ImeContext.State)
  -> ImeContext.State
{
  if !key.hasActivated {
    return state
  }
  if state == .direct && key.activated {
    // Indirect IME On found.
    return .precomposition
  }
  if state != .direct && !key.activated {
    // Indirect IME Off found.
    return .direct
  }
  return state
}

/// `context_->state() & (A | B ...)` in C++.
private func stateIn(_ state: ImeContext.State, _ states: ImeContext.State...) -> Bool {
  states.contains(state)
}

private func suppressSuggestion(_ input: Genmai_Commands_Input) -> Bool {
  if !input.hasContext {
    return false
  }
  if input.context.hasSuppressSuggestion && input.context.suppressSuggestion {
    return true
  }
  // If the target input field is in Chrome's Omnibox or Google
  // search box, the suggest window is hidden.
  for feature in input.context.experimentalFeatures {
    if feature == "chrome_omnibox" || feature == "google_search_box" {
      return true
    }
  }
  return false
}

// return
// ((key_code == static_cast<uint32_t>('.') ||
//       key_string == "." || key_string == "．" ||
//   key_string == "。" || key_string == "｡") &&
//  (config.auto_conversion_key() &
//   config::Config::AUTO_CONVERSION_KUTEN)) || ...
private func isValidKey(_ config: Genmai_Config_Config, _ keyCode: UInt32, _ keyString: Substring)
  -> Bool
{
  let autoConversionKey = config.autoConversionKey
  let kuten = UInt32(Genmai_Config_Config.AutoConversionKey.autoConversionKuten.rawValue)
  let touten = UInt32(Genmai_Config_Config.AutoConversionKey.autoConversionTouten.rawValue)
  let question = UInt32(Genmai_Config_Config.AutoConversionKey.autoConversionQuestionMark.rawValue)
  let exclamation = UInt32(
    Genmai_Config_Config.AutoConversionKey.autoConversionExclamationMark.rawValue)
  return
    (((keyCode == UInt32(UInt8(ascii: ".")) && keyString.isEmpty) || keyString == "."
    || keyString == "．" || keyString == "。" || keyString == "｡")
    && (autoConversionKey & kuten) != 0)
    || (((keyCode == UInt32(UInt8(ascii: ",")) && keyString.isEmpty) || keyString == ","
      || keyString == "，" || keyString == "、" || keyString == "､")
      && (autoConversionKey & touten) != 0)
    || (((keyCode == UInt32(UInt8(ascii: "?")) && keyString.isEmpty) || keyString == "?"
      || keyString == "？")
      && (autoConversionKey & question) != 0)
    || (((keyCode == UInt32(UInt8(ascii: "!")) && keyString.isEmpty) || keyString == "!"
      || keyString == "！")
      && (autoConversionKey & exclamation) != 0)
}

public final class Session {
  var contextImpl: ImeContext  // internal for SessionTestPeer

  // Undo stack. *begin is the oldest, and *back is the newest.
  var undoContexts: [ImeContext] = []  // internal for SessionTestPeer

  public init(_ engine: any EngineInterface) {
    contextImpl = Session.createContext(engine)
  }

  private static func createContext(_ engine: any EngineInterface) -> ImeContext {
    let context = ImeContext(engine.createEngineConverter())
    context.createTime = Clock.getAbslTime()

    // On Windows session is started with direct mode.
    // FIXME(toshiyuki): Ditto for Mac after verifying on Mac.
    context.state = .precomposition

    // TODO(team): Remove #if based behavior change for cascading window.
    // (iOS / Linux / wasm only: set_use_cascading_window(false).)
    #if os(iOS) || os(Linux)
      context.converter.setUseCascadingWindow(false)
    #endif

    return context
  }

  public var context: ImeContext { contextImpl }

  func pushUndoContext() {
    // Copy the current context and push it to the undo stack.
    undoContexts.append(ImeContext(copying: contextImpl))
    // If the stack size exceeds the limitation, purge the oldest entries.
    while undoContexts.count > kMultipleUndoMaxSize {
      undoContexts.removeFirst()
    }
  }

  private func popUndoContext() {
    if !hasUndoContext() {
      return
    }
    contextImpl = undoContexts.removeLast()
  }

  /// Clear the undo context.
  /// This should be called when the composer's preedit or cursor position
  /// is updated by non-undo related operations. This achieves intuitive
  /// behavior, which clears the undo context on the user's edit operation.
  private func clearUndoContext() { undoContexts.removeAll() }

  private func hasUndoContext() -> Bool { !undoContexts.isEmpty }

  /// Set command.output.status.undo_available to true if HasUndoContext()==true.
  /// Otherwise no-op.
  private func maybeSetUndoStatus(_ command: inout Command) {
    if hasUndoContext() {
      command.output.status.undoAvailable = true
    }
  }

  // ensure session status is not DIRECT.
  // if session status is DIRECT, set the status to PRECOMPOSITION.
  private func ensureIMEIsOn() {
    if context.state == .direct {
      setSessionState(.precomposition, context)
    }
  }

  /// Perform the SEND_COMMAND command defined commands.proto.
  @discardableResult
  public func sendCommand(_ command: inout Command) -> Bool {
    updateTime()
    updatePreferences(&command)
    if !command.input.hasCommand {
      return false
    }
    transformInput(&command.input)

    let sessionCommand = command.input.command
    var result = false
    if sessionCommand.type == .switchCompositionMode {
      if !sessionCommand.hasCompositionMode {
        return false
      }
      switch sessionCommand.compositionMode {
      case .direct:
        // TODO(komatsu): Implement here.
        break
      case .hiragana:
        result = compositionModeHiragana(&command)
      case .fullKatakana:
        result = compositionModeFullKatakana(&command)
      case .halfAscii:
        result = compositionModeHalfASCII(&command)
      case .fullAscii:
        result = compositionModeFullASCII(&command)
      case .halfKatakana:
        result = compositionModeHalfKatakana(&command)
      default:
        GenmaiLog.error("Unknown mode: \(sessionCommand.compositionMode)")
      }
      maybeSetUndoStatus(&command)
      return result
    }

    switch command.input.command.type {
    case .none:
      result = doNothing(&command)
    case .revert:
      result = revert(&command)
    case .submit:
      result = commit(&command)
    case .selectCandidate:
      result = selectCandidate(&command)
    case .submitCandidate:
      result = commitCandidate(&command)
    case .highlightCandidate:
      result = highlightCandidate(&command)
    case .getStatus:
      result = getStatus(&command)
    case .convertReverse:
      result = convertReverse(&command)
    case .undo:
      result = undo(&command)
    case .resetContext:
      result = resetContext(&command)
    case .moveCursor:
      result = moveCursorTo(&command)
    case .switchInputFieldType:
      result = switchInputFieldType(&command)
    case .undoOrRewind:
      result = undoOrRewind(&command)
    case .commitRawText:
      result = commitRawText(&command)
    case .convertPrevPage:
      result = convertPrevPage(&command)
    case .convertNextPage:
      result = convertNextPage(&command)
    case .turnOnIme:
      result = makeSureIMEOn(&command)
    case .turnOffIme:
      result = makeSureIMEOff(&command)
    case .deleteCandidateFromHistory:
      result = deleteCandidateFromHistory(&command)
    case .stopKeyToggling:
      result = stopKeyToggling(&command)
    case .updateComposition:
      result = updateComposition(&command)
    case .requestNwp:
      var conversionPreferences = context.converter.conversionPreferences
      conversionPreferences.requestSuggestion = command.input.requestSuggestion
      // Resets converter's state (e.g. previous segments).
      // NWP will be generated from surrounding text given by the client.
      context.converter.reset()
      result = context.converter.suggest(
        context.composer, command.input.context, conversionPreferences)
      if result {
        output(&command)
      }
    default:
      GenmaiLog.warning("Unknown command\(command)")
      result = doNothing(&command)
    }
    maybeSetUndoStatus(&command)
    return result
  }

  /// Check if the input key event will be consumed by the session.
  @discardableResult
  public func testSendKey(_ command: inout Command) -> Bool {
    updateTime()
    updatePreferences(&command)
    transformInput(&command.input)

    if context.state == .none {
      // This must be an error.
      GenmaiLog.error("Invalid state: NONE")
      return false
    }

    let key = command.input.key

    // To support indirect IME on/off by using KeyEvent::activated, use effective
    // state instead of directly using context_->state().
    let state = getEffectiveStateForTestSendKey(key, context.state)

    let keymap = context.getKeyMapManager()

    // Direct input
    if state == .direct {
      guard let keyCommand = keymap.getCommandDirect(key), keyCommand != .none else {
        return echoBack(&command)
      }
      return doNothing(&command)
    }

    // Precomposition
    if state == .precomposition {
      let isSuggestion = context.converter.checkState(EngineConverterState.suggestion)
      let keyCommand =
        isSuggestion
        ? keymap.getCommandZeroQuerySuggestion(key) : keymap.getCommandPrecomposition(key)
      guard let keyCommand, keyCommand != .none else {
        // Clear undo context just in case. b/5529702.
        // Note that the undo context will not be cleared in
        // EchoBackAndClearUndoContext if the key event consists of modifier keys
        // only.
        return echoBackAndClearUndoContext(&command)
      }
      // If the input_style is DIRECT_INPUT, KeyEvent is not consumed
      // and done echo back.  It works only when key_string is equal to
      // key_code.  We should fix this limitation when the as_is flag is
      // used for rather than numpad characters.
      if keyCommand == .insertCharacter && key.inputStyle == .directInput {
        return echoBack(&command)
      }

      // TODO(komatsu): This is a hack to work around the problem with
      // the inconsistency between TestSendKey and SendKey.
      switch keyCommand {
      case .insertSpace:
        if !isFullWidthInsertSpace(command.input) && isPureSpaceKey(key) {
          return echoBackAndClearUndoContext(&command)
        }
        return doNothing(&command)
      case .insertAlternateSpace:
        if isFullWidthInsertSpace(command.input) && isPureSpaceKey(key) {
          return echoBackAndClearUndoContext(&command)
        }
        return doNothing(&command)
      case .insertHalfSpace:
        if isPureSpaceKey(key) {
          return echoBackAndClearUndoContext(&command)
        }
        return doNothing(&command)
      case .insertFullSpace:
        return doNothing(&command)
      default:
        // Do nothing.
        break
      }

      if keyCommand == .revert {
        return revert(&command)
      }

      // If undo context is empty, echoes back the key event so that it can be
      // handled by the application. b/5553298
      if keyCommand == .undo && !hasUndoContext() {
        return echoBack(&command)
      }

      return doNothing(&command)
    }

    // Do nothing.
    return doNothing(&command)
  }

  @discardableResult
  public func sendKey(_ command: inout Command) -> Bool {
    updateTime()
    updatePreferences(&command)
    transformInput(&command.input)
    // To support indirect IME on/off by using KeyEvent::activated, use effective
    // state instead of directly using context_->state().
    _ = handleIndirectImeOnOff(&command)

    var result = false
    switch context.state {
    case .direct:
      result = sendKeyDirectInputState(&command)
    case .precomposition:
      result = sendKeyPrecompositionState(&command)
    case .composition:
      result = sendKeyCompositionState(&command)
    case .conversion:
      result = sendKeyConversionState(&command)
    case .none:
      result = false
    }

    maybeSetUndoStatus(&command)
    return result
  }

  @discardableResult
  public func updateCompositionInternal(_ command: inout Command) -> Bool {
    command.output.consumed = true

    context.data.composer.reset()
    // Use the top entry for now.
    context.data.composer.setCompositionsForHandwriting(command.input.command.compositionEvents)
    clearUndoContext()
    setSessionState(.composition, context)

    if suggest(command.input) {
      output(&command)
      return true
    }

    outputComposition(&command)
    return true
  }

  @discardableResult
  public func updateComposition(_ command: inout Command) -> Bool {
    var result = false
    switch context.state {
    case .direct:
      result = echoBackAndClearUndoContext(&command)
    case .precomposition, .composition:
      result = updateCompositionInternal(&command)
    case .conversion:
      result = false
    case .none:
      result = false
    }
    return result
  }

  private func sendKeyDirectInputState(_ command: inout Command) -> Bool {
    let keymap = context.getKeyMapManager()
    guard let keyCommand = keymap.getCommandDirect(command.input.key) else {
      return echoBackAndClearUndoContext(&command)
    }

    switch keyCommand {
    case .imeOn:
      return imeOn(&command)
    case .compositionModeHiragana:
      return compositionModeHiragana(&command)
    case .compositionModeFullKatakana:
      return compositionModeFullKatakana(&command)
    case .compositionModeHalfKatakana:
      return compositionModeHalfKatakana(&command)
    case .compositionModeFullAlphanumeric:
      return compositionModeFullASCII(&command)
    case .compositionModeHalfAlphanumeric:
      return compositionModeHalfASCII(&command)
    case .none:
      return echoBackAndClearUndoContext(&command)
    case .reconvert:
      return requestConvertReverse(&command)
    }
  }

  private func sendKeyPrecompositionState(_ command: inout Command) -> Bool {
    let keymap = context.getKeyMapManager()
    let result =
      context.converter.checkState(EngineConverterState.suggestion)
      ? keymap.getCommandZeroQuerySuggestion(command.input.key)
      : keymap.getCommandPrecomposition(command.input.key)

    guard let keyCommand = result else {
      return echoBackAndClearUndoContext(&command)
    }

    // Update the client context (if any) for later use. Note that the client
    // context is updated only here. In other words, we will stop updating the
    // client context once a conversion starts (mainly for performance reasons).
    if command.hasInput && command.input.hasContext {
      context.clientContext = command.input.context
    } else {
      context.clientContext = Genmai_Commands_Context()
    }

    switch keyCommand {
    case .insertCharacter:
      return insertCharacter(&command)
    case .insertSpace:
      return insertSpace(&command)
    case .insertAlternateSpace:
      return insertSpaceToggled(&command)
    case .insertHalfSpace:
      return insertSpaceHalfWidth(&command)
    case .insertFullSpace:
      return insertSpaceFullWidth(&command)
    case .toggleAlphanumericMode:
      return toggleAlphanumericMode(&command)
    case .revert:
      return revert(&command)
    case .undo:
      return requestUndo(&command)
    case .imeOff:
      return imeOff(&command)
    case .imeOn:
      return doNothing(&command)

    case .compositionModeHiragana:
      return compositionModeHiragana(&command)
    case .compositionModeFullKatakana:
      return compositionModeFullKatakana(&command)
    case .compositionModeHalfKatakana:
      return compositionModeHalfKatakana(&command)
    case .compositionModeFullAlphanumeric:
      return compositionModeFullASCII(&command)
    case .compositionModeHalfAlphanumeric:
      return compositionModeHalfASCII(&command)
    case .compositionModeSwitchKanaType:
      return compositionModeSwitchKanaType(&command)

    case .launchConfigDialog:
      return launchConfigDialog(&command)
    case .launchDictionaryTool:
      return launchDictionaryTool(&command)
    case .launchWordRegisterDialog:
      return launchWordRegisterDialog(&command)

    // For zero query suggestion
    case .cancel:
      // It is a little kind of abuse of the EditCancel command.  It
      // would be nice to make a new command when EditCancel is
      // extended or the requirement of this command is added.
      return editCancel(&command)
    case .cancelAndImeOff:
      // The same to keymap::PrecompositionState::CANCEL.
      return editCancelAndIMEOff(&command)
    // For zero query suggestion
    case .commitFirstSuggestion:
      return commitFirstSuggestion(&command)
    // For zero query suggestion
    case .predictAndConvert:
      return predictAndConvert(&command)

    case .none:
      return echoBackAndClearUndoContext(&command)
    case .reconvert:
      return requestConvertReverse(&command)

    case .imeAction:
      return imeAction(&command)
    }
  }

  private func sendKeyCompositionState(_ command: inout Command) -> Bool {
    let keymap = context.getKeyMapManager()
    let result =
      context.converter.checkState(EngineConverterState.suggestion)
      ? keymap.getCommandSuggestion(command.input.key)
      : keymap.getCommandComposition(command.input.key)

    guard let keyCommand = result else {
      return doNothing(&command)
    }

    switch keyCommand {
    case .insertCharacter:
      return insertCharacter(&command)
    case .commit:
      return commit(&command)
    case .commitFirstSuggestion:
      return commitFirstSuggestion(&command)
    case .convert:
      return convert(&command)
    case .convertWithoutHistory:
      return convertWithoutHistory(&command)
    case .predictAndConvert:
      return predictAndConvert(&command)
    case .del:
      return delete(&command)
    case .backspace:
      return backspace(&command)
    case .insertSpace:
      return insertSpace(&command)
    case .insertAlternateSpace:
      return insertSpaceToggled(&command)
    case .insertHalfSpace:
      return insertSpaceHalfWidth(&command)
    case .insertFullSpace:
      return insertSpaceFullWidth(&command)
    case .moveCursorLeft:
      return moveCursorLeft(&command)
    case .moveCursorRight:
      return moveCursorRight(&command)
    case .moveCursorToBeginning:
      return moveCursorToBeginning(&command)
    case .moveMoveCursorToEnd:
      return moveCursorToEnd(&command)
    case .cancel:
      return editCancel(&command)
    case .cancelAndImeOff:
      return editCancelAndIMEOff(&command)
    case .undo:
      return requestUndo(&command)
    case .imeOff:
      return imeOff(&command)
    case .imeOn:
      return doNothing(&command)
    case .convertToHiragana:
      return convertToHiragana(&command)
    case .convertToFullKatakana:
      return convertToFullKatakana(&command)
    case .convertToHalfKatakana:
      return convertToHalfKatakana(&command)
    case .convertToHalfWidth:
      return convertToHalfWidth(&command)
    case .convertToFullAlphanumeric:
      return convertToFullASCII(&command)
    case .convertToHalfAlphanumeric:
      return convertToHalfASCII(&command)
    case .switchKanaType:
      return switchKanaType(&command)
    case .displayAsHiragana:
      return displayAsHiragana(&command)
    case .displayAsFullKatakana:
      return displayAsFullKatakana(&command)
    case .displayAsHalfKatakana:
      return displayAsHalfKatakana(&command)
    case .translateHalfWidth:
      return translateHalfWidth(&command)
    case .translateFullAscii:
      return translateFullASCII(&command)
    case .translateHalfAscii:
      return translateHalfASCII(&command)
    case .toggleAlphanumericMode:
      return toggleAlphanumericMode(&command)
    case .compositionModeHiragana:
      return compositionModeHiragana(&command)
    case .compositionModeFullKatakana:
      return compositionModeFullKatakana(&command)
    case .compositionModeHalfKatakana:
      return compositionModeHalfKatakana(&command)
    case .compositionModeFullAlphanumeric:
      return compositionModeFullASCII(&command)
    case .compositionModeHalfAlphanumeric:
      return compositionModeHalfASCII(&command)
    case .none:
      return doNothing(&command)
    }
  }

  private func sendKeyConversionState(_ command: inout Command) -> Bool {
    let keymap = context.getKeyMapManager()
    let result =
      context.converter.checkState(EngineConverterState.prediction)
      ? keymap.getCommandPrediction(command.input.key)
      : keymap.getCommandConversion(command.input.key)

    guard let keyCommand = result else {
      return doNothing(&command)
    }

    switch keyCommand {
    case .insertCharacter:
      return insertCharacter(&command)
    case .insertSpace:
      return insertSpace(&command)
    case .insertAlternateSpace:
      return insertSpaceToggled(&command)
    case .insertHalfSpace:
      return insertSpaceHalfWidth(&command)
    case .insertFullSpace:
      return insertSpaceFullWidth(&command)
    case .commit:
      return commit(&command)
    case .commitSegment:
      return commitSegment(&command)
    case .convertNext:
      return convertNext(&command)
    case .convertPrev:
      return convertPrev(&command)
    case .convertNextPage:
      return convertNextPage(&command)
    case .convertPrevPage:
      return convertPrevPage(&command)
    case .predictAndConvert:
      return predictAndConvert(&command)
    case .segmentFocusLeft:
      return segmentFocusLeft(&command)
    case .segmentFocusRight:
      return segmentFocusRight(&command)
    case .segmentFocusFirst:
      return segmentFocusLeftEdge(&command)
    case .segmentFocusLast:
      return segmentFocusLast(&command)
    case .segmentWidthExpand:
      return segmentWidthExpand(&command)
    case .segmentWidthShrink:
      return segmentWidthShrink(&command)
    case .cancel:
      return convertCancel(&command)
    case .cancelAndImeOff:
      return editCancelAndIMEOff(&command)
    case .undo:
      return requestUndo(&command)
    case .imeOff:
      return imeOff(&command)
    case .imeOn:
      return doNothing(&command)
    case .convertToHiragana:
      return convertToHiragana(&command)
    case .convertToFullKatakana:
      return convertToFullKatakana(&command)
    case .convertToHalfKatakana:
      return convertToHalfKatakana(&command)
    case .convertToHalfWidth:
      return convertToHalfWidth(&command)
    case .convertToFullAlphanumeric:
      return convertToFullASCII(&command)
    case .convertToHalfAlphanumeric:
      return convertToHalfASCII(&command)
    case .switchKanaType:
      return switchKanaType(&command)
    case .displayAsHiragana:
      return displayAsHiragana(&command)
    case .displayAsFullKatakana:
      return displayAsFullKatakana(&command)
    case .displayAsHalfKatakana:
      return displayAsHalfKatakana(&command)
    case .translateHalfWidth:
      return translateHalfWidth(&command)
    case .translateFullAscii:
      return translateFullASCII(&command)
    case .translateHalfAscii:
      return translateHalfASCII(&command)
    case .toggleAlphanumericMode:
      return toggleAlphanumericMode(&command)
    case .compositionModeHiragana:
      return compositionModeHiragana(&command)
    case .compositionModeFullKatakana:
      return compositionModeFullKatakana(&command)
    case .compositionModeHalfKatakana:
      return compositionModeHalfKatakana(&command)
    case .compositionModeFullAlphanumeric:
      return compositionModeFullASCII(&command)
    case .compositionModeHalfAlphanumeric:
      return compositionModeHalfASCII(&command)
    case .reportBug:
      return reportBug(&command)
    case .deleteSelectedCandidate:
      return deleteCandidateFromHistory(&command)
    case .none:
      return doNothing(&command)
    }
  }

  /// update preferences only affecting this session.
  private func updatePreferences(_ command: inout Command) {
    let config = command.input.config
    if command.input.hasCapability {
      context.clientCapability = command.input.capability
    }

    // Update config values modified temporarily.
    // TODO(team): Stop using config for temporary modification.
    if config.hasSelectionShortcut {
      context.converter.setSelectionShortcut(config.selectionShortcut)
    }

    #if os(iOS) || os(Linux)
      context.converter.setUseCascadingWindow(false)
    #else
      if config.hasUseCascadingWindow {
        context.converter.setUseCascadingWindow(config.useCascadingWindow)
      }
    #endif
  }

  /// Turn on IME. Do nothing (but the keyevent is consumed) when IME is already
  /// turned on.
  @discardableResult
  public func imeOn(_ command: inout Command) -> Bool {
    command.output.consumed = true
    clearUndoContext()

    setSessionState(.precomposition, context)
    if command.input.hasKey && command.input.key.hasMode {
      applyCompositionMode(command.input.key.mode, &context.data.composer)
    }
    outputMode(&command)
    return true
  }

  /// Turn off IME. Do nothing (but the keyevent is consumed) when IME is already
  /// turned off.
  @discardableResult
  public func imeOff(_ command: inout Command) -> Bool {
    command.output.consumed = true
    clearUndoContext()

    commit(&command)

    // Reset the context.
    context.converter.reset()

    setSessionState(.direct, context)
    outputMode(&command)
    return true
  }

  /// Unlike IMEOn/IMEOff, these commands 1) can update composition mode, and
  /// 2) are functional even when IME is already turned on/off.
  /// TODO(team): Merge these into IMEOn/Off once b/10250883 is fixed.
  @discardableResult
  public func makeSureIMEOn(_ command: inout Command) -> Bool {
    if command.input.hasCommand && command.input.command.hasCompositionMode
      && command.input.command.compositionMode == .direct
    {
      // This is invalid and unsupported usage.
      return false
    }

    command.output.consumed = true
    if context.state == .direct {
      clearUndoContext()
      setSessionState(.precomposition, context)
    }
    if command.input.hasCommand && command.input.command.hasCompositionMode {
      applyCompositionMode(command.input.command.compositionMode, &context.data.composer)
    }
    outputMode(&command)
    return true
  }

  @discardableResult
  public func makeSureIMEOff(_ command: inout Command) -> Bool {
    if command.input.hasCommand && command.input.command.hasCompositionMode
      && command.input.command.compositionMode == .direct
    {
      // This is invalid and unsupported usage.
      return false
    }

    command.output.consumed = true
    if context.state != .direct {
      clearUndoContext()
      commit(&command)
      // Reset the context.
      context.converter.reset()
      setSessionState(.direct, context)
    }
    if command.input.hasCommand && command.input.command.hasCompositionMode {
      applyCompositionMode(command.input.command.compositionMode, &context.data.composer)
    }
    outputMode(&command)
    return true
  }

  @discardableResult
  public func echoBack(_ command: inout Command) -> Bool {
    command.output.consumed = false
    context.converter.reset()
    outputKey(&command)
    return true
  }

  @discardableResult
  public func echoBackAndClearUndoContext(_ command: inout Command) -> Bool {
    command.output.consumed = false

    // Don't clear undo context when KeyEvent has a modifier key only.
    // TODO(hsumita): A modifier key may be assigned to another functions.
    //                ex) InsertSpace
    //                We need to check it outside of this function.
    let keyEvent = command.input.key
    if !isPureModifierKeyEvent(keyEvent) {
      clearUndoContext()
    }

    return echoBack(&command)
  }

  @discardableResult
  public func doNothing(_ command: inout Command) -> Bool {
    command.output.consumed = true
    // Quick hack for zero query suggestion.
    // Caveats: Resetting converter causes b/8703702 on Windows.
    // Basically we should not *do* something in DoNothing.
    // TODO(komatsu): Fix this.
    if context.getRequest().zeroQuerySuggestion && context.converter.isActive()
      && context.state == .precomposition
    {
      context.converter.reset()
      output(&command)
    }
    if stateIn(context.state, .composition, .conversion) {
      output(&command)
    }
    return true
  }

  /// Resets the composer and clear conversion segments.
  /// History segments will not be cleared.
  /// Therefore if a user commits "風"(かぜ) and Revert method is called,
  /// preedit "ひいた"  will be converted into "邪引いた".
  @discardableResult
  public func revert(_ command: inout Command) -> Bool {
    if context.state == .precomposition {
      context.converter.revert()
      return echoBackAndClearUndoContext(&command)
    }

    if !stateIn(context.state, .composition, .conversion) {
      return doNothing(&command)
    }

    command.output.consumed = true
    clearUndoContext()

    setStateToPredompositionAndCancel(context)
    output(&command)
    return true
  }

  /// Reset the composer and clear all the segments (including history segments).
  /// Therefore preedit "ひいた"  will *not* be converted into "邪引いた"
  /// on the situation described above.
  @discardableResult
  public func resetContext(_ command: inout Command) -> Bool {
    if context.state == .precomposition {
      context.converter.reset()
      return echoBackAndClearUndoContext(&command)
    }

    command.output.consumed = true
    clearUndoContext()

    context.converter.reset()

    setStateToPredompositionAndCancel(context)
    output(&command)
    return true
  }

  public func setTable(_ table: Table?) {
    guard let table else {
      return
    }
    clearUndoContext()
    context.data.composer.setTable(table)
  }

  public func setConfig(_ config: Genmai_Config_Config) {
    clearUndoContext()
    context.setConfig(config)
  }

  public func setRequest(_ request: Genmai_Commands_Request) {
    clearUndoContext()
    context.setRequest(request)
  }

  public func setKeyMapManager(_ keyMapManager: KeyMapManager) {
    context.setKeyMapManager(keyMapManager)
  }

  /// Returns the current status such as a composition string, input mode, etc.
  @discardableResult
  public func getStatus(_ command: inout Command) -> Bool {
    outputMode(&command)
    return true
  }

  /// Fills Output::Callback with the CONVERT_REVERSE SessionCommand to
  /// ask the client to send back the SessionCommand to the server.
  /// This function is called when the key event representing the
  /// ConvertReverse keybinding is called.
  @discardableResult
  public func requestConvertReverse(_ command: inout Command) -> Bool {
    if context.state != .precomposition && context.state != .direct {
      return doNothing(&command)
    }
    command.output.consumed = true
    output(&command)

    // Fill callback message.
    command.output.callback.sessionCommand.type = .convertReverse
    return true
  }

  /// Begins reverse conversion for the given session.  This function
  /// is called when the CONVERT_REVERSE SessionCommand is called.
  @discardableResult
  public func convertReverse(_ command: inout Command) -> Bool {
    if context.state != .precomposition && context.state != .direct {
      return doNothing(&command)
    }

    let composition = command.input.command.text

    // Validate before requesting reverse conversion
    if !Util.isValidUtf8(composition) {
      return doNothing(&command)
    }
    for scalar in composition.unicodeScalars {
      if !Util.isAcceptableCharacterAsCandidate(scalar.value) {
        return doNothing(&command)
      }
    }

    var reading = ""
    if !context.converter.getReadingText(composition, &reading) {
      GenmaiLog.error("Failed to get reading text")
      return doNothing(&command)
    }

    context.data.composer.reset()
    clearUndoContext()
    context.data.composer.insertCharacterPreedit(reading)
    context.data.composer.setSourceText(composition)
    // start conversion here.
    if !context.converter.convert(context.composer) {
      GenmaiLog.error("Failed to start conversion for reverse conversion")
      return false
    }

    command.output.consumed = true

    setSessionState(.conversion, context)
    context.converter.setCandidateListVisible(true)
    output(&command)
    return true
  }

  /// Fills Output::Callback with the Undo SessionCommand to ask the
  /// client to send back the SessionCommand to the server.
  /// This function is called when the key event representing the
  /// Undo keybinding is called.
  @discardableResult
  public func requestUndo(_ command: inout Command) -> Bool {
    if !stateIn(context.state, .precomposition, .conversion, .composition) {
      return doNothing(&command)
    }

    // If undo context is empty, echoes back the key event so that it can be
    // handled by the application. b/5553298
    if context.state == .precomposition && !hasUndoContext() {
      return echoBack(&command)
    }

    command.output.consumed = true
    output(&command)

    // Fill callback message.
    command.output.callback.sessionCommand.type = .undo
    return true
  }

  /// Undos the commitment.  This function is called when the
  /// UNDO SessionCommand is called.
  @discardableResult
  public func undo(_ command: inout Command) -> Bool {
    if !stateIn(context.state, .precomposition, .conversion, .composition) {
      return doNothing(&command)
    }
    command.output.consumed = true

    // Check the undo context
    if !hasUndoContext() {
      return doNothing(&command)
    }

    // Rollback the last user history.
    context.converter.revert()

    var resultSize = 0
    var cursorOffset: Int32 = 0
    if context.output.hasResult {
      // Check the client's capability
      if (context.clientCapability.textDeletion.rawValue
        & Genmai_Commands_Capability.TextDeletionCapabilityType.deletePrecedingText.rawValue) == 0
      {
        return doNothing(&command)
      }
      resultSize = Util.charsLen(context.output.result.value)
      cursorOffset = context.output.result.cursorOffset
    }

    popUndoContext()

    if resultSize > 0 {
      command.output.deletionRange.offset = -(Int32(resultSize) + cursorOffset)
      command.output.deletionRange.length = Int32(resultSize)
    }

    output(&command)
    return true
  }

  /// The internal implementation of both SelectCandidate and HighlightCandidate.
  private func selectCandidateInternal(_ command: inout Command) -> Bool {
    // If the current state is not conversion, composition or
    // precomposition, the candidate window should not be shown.  (On
    // composition or precomposition, the window is able to be shown as
    // a suggestion window).
    if !stateIn(context.state, .conversion, .composition, .precomposition) {
      return false
    }
    if !command.input.hasCommand || !command.input.command.hasID {
      GenmaiLog.warning("input.command or input.command.id did not exist.")
      return false
    }
    if !context.converter.isActive() {
      GenmaiLog.warning("converter is not active. (no candidates)")
      return false
    }

    command.output.consumed = true

    context.converter.candidateMoveToId(Int(command.input.command.id), context.composer)
    setSessionState(.conversion, context)

    return true
  }

  /// Select a candidate located by input.command.id.  This command
  /// would not be used from SendKey but used from SendCommand because
  /// it requires the argument id.
  private func selectCandidate(_ command: inout Command) -> Bool {
    if !selectCandidateInternal(&command) {
      return doNothing(&command)
    }
    output(&command)
    return true
  }

  /// Select a candidate located by input.command.id and commit.
  @discardableResult
  public func commitCandidate(_ command: inout Command) -> Bool {
    if !stateIn(context.state, .composition, .conversion, .precomposition) {
      return false
    }
    let input = command.input
    if !input.hasCommand || !input.command.hasID {
      GenmaiLog.warning("input.command or input.command.id did not exist.")
      return false
    }
    if !context.converter.isActive() {
      GenmaiLog.warning("converter is not active. (no candidates)")
      return false
    }
    command.output.consumed = true

    pushUndoContext()

    if context.state == .conversion {
      // There is a focused candidate so just select a candidate based on
      // input message and commit first segment.
      context.converter.candidateMoveToId(Int(input.command.id), context.composer)
      commitHeadToFocusedSegmentsInternal(command.input.context)
    } else {
      // No candidate is focused.
      var consumedKeySize = 0
      if context.converter.commitSuggestionById(
        Int(input.command.id), context.composer, command.input.context, &consumedKeySize)
      {
        if consumedKeySize < context.composer.getLength() {
          // partial suggestion was committed.
          context.data.composer.deleteRange(0, consumedKeySize)
          // Don't clear the undo context, which we've just updated.
          moveCursorToEndInternal(&command, false)
          // Copy the previous output for Undo.
          context.output = command.output
          return true
        }
      }
    }

    if !context.converter.isActive() {
      // If the converter is not active (ie. the segment size was one.),
      // the state should be switched to precomposition.
      setSessionState(.precomposition, context)

      // Get suggestion if zero_query_suggestion is set.
      // zero_query_suggestion is usually set where the client is a
      // mobile.
      if context.getRequest().zeroQuerySuggestion {
        _ = suggest(command.input)
      }
    }
    output(&command)
    // Copy the previous output for Undo.
    context.output = command.output
    return true
  }

  /// Set the focus to the candidate located by input.command.id.  This
  /// command would not be used from SendKey but used from SendCommand
  /// because it requires the argument id.  The difference from
  /// SelectCandidate is that HighlightCandidate does not close the
  /// candidate window while SelectCandidate closes the candidate
  /// window.
  private func highlightCandidate(_ command: inout Command) -> Bool {
    if !selectCandidateInternal(&command) {
      return false
    }
    context.converter.setCandidateListVisible(true)
    output(&command)
    return true
  }

  /// If the command is a shortcut to select a candidate from a list,
  /// Process it and return true, otherwise return false.
  private func maybeSelectCandidate(_ command: inout Command) -> Bool {
    if context.state != .conversion {
      return false
    }
    // When using special romaji table (== The key event is from a virtual
    // keyboard), don't consume it as a shortcut selection operation.
    if context.getRequest().specialRomanjiTable != .defaultTable {
      return false
    }

    // Note that SHORTCUT_ASDFGHJKL should be handled even when the CapsLock is
    // enabled. This is why we need to normalize the key event here.
    // See b/5655743.
    var normalizedKeyevent = KeyEvent()
    KeyEventUtil.normalizeModifiers(command.input.key, &normalizedKeyevent)

    // Check if the input character is in the shortcut.
    // TODO(komatsu): Support non ASCII characters such as Unicode and
    // special keys.
    let shortcut = UInt8(truncatingIfNeeded: normalizedKeyevent.keyCode)
    return context.converter.candidateMoveToShortcut(shortcut)
  }

  /// Set client capability for this session.  Used by unittest.
  public func setClientCapability(_ capability: Genmai_Commands_Capability) {
    context.clientCapability = capability
  }

  /// Set application information for this session.
  public func setApplicationInfo(_ applicationInfo: Genmai_Commands_ApplicationInfo) {
    context.applicationInfo = applicationInfo
  }

  /// Get application information
  public var applicationInfo: Genmai_Commands_ApplicationInfo { context.applicationInfo }

  /// Return the time when this instance was created.
  public var createSessionTime: Date { context.createTime }

  /// return 0 (default value) if no command is executed in this session.
  public var lastCommandTime: Date { context.lastCommandTime }

  @discardableResult
  public func insertCharacter(_ command: inout Command) -> Bool {
    if !command.input.hasKey {
      GenmaiLog.error("No key event: \(command.input)")
      return false
    }

    let key = command.input.key

    if key.inputStyle == .directInput && context.state == .precomposition {
      // If the key event represents a half width ascii character (ie.
      // key_code is equal to key_string), that key event is not
      // consumed and done echo back.
      // We must not call |EchoBackAndClearUndoContext| for a half-width space
      // here because it should be done in Session::TestSendKey or
      // Session::InsertSpaceHalfWidth. Note that the |key| comes from
      // Session::InsertSpaceHalfWidth and Session::InsertSpaceFullWidth is
      // different from the original key event.
      // For example, when the client sends a key command like
      //   {key.special_key(): HENKAN, key.modifier_keys(): [SHIFT]},
      // Session::InsertSpaceHalfWidth replaces it with
      //   {key.key_string(): " ", key.key_code(): ' '}
      // when you assign [Shift+HENKAN] to [InsertSpaceHalfWidth].
      // So |key.key_code() == ' '| does not always mean that the original key is
      // a space key w/o any modifier.
      // This is why we cannot call |EchoBackAndClearUndoContext| when
      // |key.key_code() == ' '|. This issue was found in b/5872031.
      let keyStringBytes = Array(key.keyString.utf8)
      // C++ compares the uint32 key_code with a (signed) char.
      if keyStringBytes.count == 1 && key.keyCode == UInt32(bitPattern: Int32(Int8(bitPattern: keyStringBytes[0])))
        && key.keyCode != UInt32(UInt8(ascii: " "))
      {
        return echoBackAndClearUndoContext(&command)
      }

      _ = context.data.composer.insertCharacterKeyEvent(key)
      commitCompositionDirectly(&command)
      clearUndoContext()  // UndoContext must be invalidated.
      return true
    }

    command.output.consumed = true

    // Handle shortcut keys selecting a candidate from a list.
    if maybeSelectCandidate(&command) {
      output(&command)
      return true
    }

    let composition = context.composer.getQueryForConversion()
    var shouldCommit = (context.state == .conversion)

    if context.getRequest().spaceOnAlphanumeric == .spaceOrConvertCommittingComposition
      && context.state == .composition
      // TODO(komatsu): Support FullWidthSpace
      && composition.utf8.last == UInt8(ascii: " ")
    {
      shouldCommit = true
    }

    if shouldCommit {
      commitNotTriggeringZeroQuerySuggest(&command)
      if key.inputStyle == .directInput {
        // Do ClearUndoContext() because it is a direct input.
        clearUndoContext()
        _ = context.data.composer.insertCharacterKeyEvent(key)
        commitCompositionDirectly(&command)
        return true
      }
    }

    _ = context.data.composer.insertCharacterKeyEvent(key)
    clearUndoContext()
    if context.composer.shouldCommit() {
      commitCompositionDirectly(&command)
      return true
    }
    var lengthToCommit = 0
    if context.composer.shouldCommitHead(&lengthToCommit) {
      return commitHead(lengthToCommit, &command)
    }

    setSessionState(.composition, context)
    if canStartAutoConversion(key) {
      return convert(&command)
    }

    if suggest(command.input) {
      output(&command)
      return true
    }

    outputComposition(&command)
    return true
  }

  /// Return true if full width space is preferred in the given new input
  /// state than half width space. When |input| does not have new input mode,
  /// the current mode will be considered.
  func isFullWidthInsertSpace(_ input: Genmai_Commands_Input) -> Bool {
    // If IME is off, any space has to be half-width.
    if context.state == .direct {
      return false
    }

    // In this method, we should not update the actual input mode stored in
    // the composer even when |input| has a new input mode. Note that this
    // method can be called from TestSendKey, where internal input mode is
    // is not expected to be changed. This is one of the reasons why this
    // method is a const method.
    // On the other hand, this method should behave as if the new input mode
    // in |input| was applied. For example, this method should behave as if
    // the current input mode was HALF_KATAKANA in the following situation.
    //   composer's input mode: HIRAGANA
    //   input.key().mode()   : HALF_KATAKANA
    // To achieve this, we create a temporary composer object to which the
    // new input mode will be stored when |input| has a new input mode.
    let getInputMode = { () -> TransliterationType in
      let hasMode = input.hasKey && input.key.hasMode
      if !hasMode {
        return self.context.composer.getInputMode()
      }

      // Copy the current composer state just in case.
      var temporaryComposer = self.context.composer
      applyCompositionMode(input.key.mode, &temporaryComposer)
      // Refer to this temporary composer in this method.
      return temporaryComposer.getInputMode()
    }

    // Check the current config and the current input status.
    var isFullWidth = false
    switch context.getConfig().spaceCharacterForm {
    case .fundamentalInputMode:
      let inputMode = getInputMode()
      if T13n.isInHalfAsciiTypes(inputMode) || T13n.isInHalfKatakanaTypes(inputMode) {
        isFullWidth = false
      } else {
        isFullWidth = true
      }
    case .fundamentalFullWidth:
      isFullWidth = true
    case .fundamentalHalfWidth:
      isFullWidth = false
    @unknown default:
      GenmaiLog.warning("Unknown input mode")
      isFullWidth = false
    }

    return isFullWidth
  }

  @discardableResult
  public func insertSpace(_ command: inout Command) -> Bool {
    if isFullWidthInsertSpace(command.input) {
      return insertSpaceFullWidth(&command)
    } else {
      return insertSpaceHalfWidth(&command)
    }
  }

  @discardableResult
  public func insertSpaceToggled(_ command: inout Command) -> Bool {
    if isFullWidthInsertSpace(command.input) {
      return insertSpaceHalfWidth(&command)
    } else {
      return insertSpaceFullWidth(&command)
    }
  }

  @discardableResult
  public func insertSpaceHalfWidth(_ command: inout Command) -> Bool {
    if !stateIn(context.state, .precomposition, .composition, .conversion) {
      return doNothing(&command)
    }

    if context.state == .precomposition {
      // TODO(komatsu): This is a hack to work around the problem with
      // the inconsistency between TestSendKey and SendKey.
      if isPureSpaceKey(command.input.key) {
        return echoBackAndClearUndoContext(&command)
      }
      // UndoContext will be cleared in |InsertCharacter| in this case.
    }

    let hasMode = command.input.key.hasMode
    let mode = command.input.key.mode
    command.input.clearKey()
    command.input.key.keyCode = UInt32(UInt8(ascii: " "))
    command.input.key.keyString = " "
    command.input.key.inputStyle = .directInput
    if hasMode {
      command.input.key.mode = mode
    }
    return insertCharacter(&command)
  }

  @discardableResult
  public func insertSpaceFullWidth(_ command: inout Command) -> Bool {
    if !stateIn(context.state, .precomposition, .composition, .conversion) {
      return doNothing(&command)
    }

    if context.state == .precomposition {
      // UndoContext will be cleared in |InsertCharacter| in this case.

      // TODO(komatsu): make sure if
      // |context_->mutable_converter()->Reset()| is necessary here.
      context.converter.reset()
    }

    let hasMode = command.input.key.hasMode
    let mode = command.input.key.mode
    command.input.clearKey()
    command.input.key.keyCode = UInt32(UInt8(ascii: " "))
    command.input.key.keyString = "　"  // full-width space
    command.input.key.inputStyle = .directInput
    if hasMode {
      command.input.key.mode = mode
    }
    return insertCharacter(&command)
  }

  /// Commands like EditCancel should restore the original string used for
  /// the reverse conversion without any modification.
  /// Returns true if the |source_text| is committed to cancel reconversion.
  /// Returns false if this function has nothing to do.
  @discardableResult
  private func tryCancelConvertReverse(_ command: inout Command) -> Bool {
    // If source_text is set, it usually means this session started by a
    // reverse conversion.
    if context.composer.sourceText.isEmpty {
      return false
    }
    commitSourceTextDirectly(&command)
    return true
  }

  private func editCancelOnPasswordField(_ command: inout Command) -> Bool {
    if context.composer.getInputFieldType() != .password {
      return false
    }

    // In password mode, we should commit preedit and close keyboard
    // on Android.
    // TODO(matsuzakit): Remove this trick. b/5955618
    if context.composer.sourceText.isEmpty {
      commitCompositionDirectly(&command)
    } else {
      // Commits original text of reverse conversion.
      commitSourceTextDirectly(&command)
    }
    // Passes the key event through to GenmaiService.java
    // to continue the processes which are invoked by cancel operation.
    command.output.consumed = false

    return true
  }

  @discardableResult
  public func editCancel(_ command: inout Command) -> Bool {
    if editCancelOnPasswordField(&command) {
      return true
    }

    command.output.consumed = true

    tryCancelConvertReverse(&command)

    setStateToPredompositionAndCancel(context)
    output(&command)
    return true
  }

  @discardableResult
  public func editCancelAndIMEOff(_ command: inout Command) -> Bool {
    if editCancelOnPasswordField(&command) {
      return true
    }

    if !stateIn(context.state, .precomposition, .composition, .conversion) {
      return doNothing(&command)
    }

    command.output.consumed = true

    tryCancelConvertReverse(&command)

    clearUndoContext()

    // Reset the context.
    context.converter.reset()

    setSessionState(.direct, context)
    output(&command)
    return true
  }

  private func commitInternal(_ command: inout Command, _ triggerZeroQuerySuggest: Bool) -> Bool {
    if !stateIn(context.state, .composition, .conversion) {
      return doNothing(&command)
    }
    command.output.consumed = true

    pushUndoContext()

    if context.state == .composition {
      context.converter.commitPreedit(context.composer, command.input.context)
    } else {  // ImeContext::CONVERSION
      context.converter.commit(context.composer, command.input.context)
    }

    setSessionState(.precomposition, context)

    if triggerZeroQuerySuggest {
      _ = suggest(command.input)
    }

    output(&command)
    // Copy the previous output for Undo.
    context.output = command.output
    return true
  }

  /// Note: Commit() also triggers zero query suggestion.
  /// TODO(team): Rename this method to CommitWithZeroQuerySuggest.
  @discardableResult
  public func commit(_ command: inout Command) -> Bool {
    commitInternal(&command, context.getRequest().zeroQuerySuggestion)
  }

  @discardableResult
  public func commitNotTriggeringZeroQuerySuggest(_ command: inout Command) -> Bool {
    commitInternal(&command, false)
  }

  /// Commits some characters at the head of the preedit.
  @discardableResult
  public func commitHead(_ count: Int, _ command: inout Command) -> Bool {
    if !stateIn(context.state, .composition, .precomposition) {
      return doNothing(&command)
    }
    command.output.consumed = true

    // TODO(yamaguchi): Support undo feature.
    clearUndoContext()

    var committedSize = 0
    context.converter.commitHead(count, context.composer, &committedSize)
    context.data.composer.deleteRange(0, committedSize)
    output(&command)
    return true
  }

  @discardableResult
  public func commitFirstSuggestion(_ command: inout Command) -> Bool {
    if !(context.state == .composition || context.state == .precomposition) {
      return doNothing(&command)
    }
    if !context.converter.isActive() {
      return doNothing(&command)
    }
    command.output.consumed = true

    pushUndoContext()

    let kFirstIndex = 0
    var committedKeySize = 0
    _ = context.converter.commitSuggestionByIndex(
      kFirstIndex, context.composer, command.input.context, &committedKeySize)

    setSessionState(.precomposition, context)

    // Get suggestion if zero_query_suggestion is set.
    // zero_query_suggestion is usually set where the client is a mobile.
    if context.getRequest().zeroQuerySuggestion {
      _ = suggest(command.input)
    }

    output(&command)
    // Copy the previous output for Undo.
    context.output = command.output
    return true
  }

  /// Commits only the first segment.
  @discardableResult
  public func commitSegment(_ command: inout Command) -> Bool {
    if context.state != .conversion {
      return doNothing(&command)
    }
    command.output.consumed = true

    pushUndoContext()

    var size = 0
    context.converter.commitFirstSegment(context.composer, command.input.context, &size)
    if size > 0 {
      // Delete the key characters of the first segment from the preedit.
      context.data.composer.deleteRange(0, size)
      // The number of segments should be more than one.
    }

    if !context.converter.isActive() {
      // If the converter is not active (ie. the segment size was one.),
      // the state should be switched to precomposition.
      setSessionState(.precomposition, context)

      // Get suggestion if zero_query_suggestion is set.
      // zero_query_suggestion is usually set where the client is a mobile.
      if context.getRequest().zeroQuerySuggestion {
        _ = suggest(command.input)
      }
    }
    output(&command)
    // Copy the previous output for Undo.
    context.output = command.output
    return true
  }

  /// Calls EngineConverter::ConmmitHeadToFocusedSegments()
  /// and deletes characters from the composer.
  private func commitHeadToFocusedSegmentsInternal(_ clientContext: Genmai_Commands_Context) {
    var size = 0
    context.converter.commitHeadToFocusedSegments(context.composer, clientContext, &size)
    if size > 0 {
      // Delete the key characters of the first segment from the preedit.
      context.data.composer.deleteRange(0, size)
      // The number of segments should be more than one.
    }
  }

  /// Commits without EngineConverter.
  private func commitCompositionDirectly(_ command: inout Command) {
    let composition = context.composer.getQueryForConversion()
    let conversion = context.composer.getStringForSubmission()
    commitStringDirectly(composition, conversion, &command)
  }

  private func commitSourceTextDirectly(_ command: inout Command) {
    // We cannot use a reference since composer will be cleared on
    // CommitStringDirectly.
    let copiedSourceText = context.composer.sourceText
    commitStringDirectly(copiedSourceText, copiedSourceText, &command)
  }

  private func commitRawTextDirectly(_ command: inout Command) {
    let rawText = context.composer.getRawString()
    commitStringDirectly(rawText, rawText, &command)
  }

  private func commitStringDirectly(_ key: String, _ preedit: String, _ command: inout Command) {
    if key.isEmpty || preedit.isEmpty {
      return
    }

    command.output.consumed = true
    context.converter.reset()

    command.output.result.type = .string
    command.output.result.key += key
    command.output.result.value += preedit
    setSessionState(.precomposition, context)

    // Get suggestion if zero_query_suggestion is set.
    // zero_query_suggestion is usually set where the client is a mobile.
    if context.getRequest().zeroQuerySuggestion {
      _ = suggest(command.input)
    }

    output(&command)
  }

  /// Calls EngineConverter::Suggest if the condition is applicable to
  /// call it.  True is returned when EngineConverter::Suggest is
  /// called and results exist.  False is returned when
  /// EngineConverter::Suggest is not called or no results exist.
  private func suggest(_ input: Genmai_Commands_Input) -> Bool {
    if suppressSuggestion(input) {
      return false
    }

    // |request_suggestion| is not supposed to always ensure suppressing
    // suggestion since this field is used for performance improvement
    // by skipping interim suggestions.  However, the implementation of
    // EngineConverter::Suggest does not perform suggest
    // whenever this flag is on.  So the caller should consider whether
    // this flag should be set or not.  Because the original logic was
    // implemented in Session::InserCharacter, we check the input.type()
    // is SEND_KEY assuming SEND_KEY results InsertCharacter (in most
    // cases).
    //
    // TODO(komatsu): Move the logic into EngineConverter.
    if input.hasRequestSuggestion && input.type == .sendKey {
      var conversionPreferences = context.converter.conversionPreferences
      conversionPreferences.requestSuggestion = input.requestSuggestion
      return context.converter.suggest(context.composer, input.context, conversionPreferences)
    }

    return context.converter.suggest(context.composer, input.context)
  }

  private func convertToTransliteration(_ command: inout Command, _ type: TransliterationType)
    -> Bool
  {
    if !stateIn(context.state, .conversion, .composition) {
      return doNothing(&command)
    }
    command.output.consumed = true

    if !context.converter.convertToTransliteration(context.composer, type) {
      return false
    }
    setSessionState(.conversion, context)
    output(&command)
    return true
  }

  /// Selects the transliteration candidate.  If the current state is
  /// composition, candidates will be generated with only translitaration
  /// candidates.
  @discardableResult
  public func convertToHiragana(_ command: inout Command) -> Bool {
    convertToTransliteration(&command, .hiragana)
  }

  @discardableResult
  public func convertToFullKatakana(_ command: inout Command) -> Bool {
    convertToTransliteration(&command, .fullKatakana)
  }

  @discardableResult
  public func convertToHalfKatakana(_ command: inout Command) -> Bool {
    convertToTransliteration(&command, .halfKatakana)
  }

  @discardableResult
  public func convertToFullASCII(_ command: inout Command) -> Bool {
    convertToTransliteration(&command, .fullAscii)
  }

  @discardableResult
  public func convertToHalfASCII(_ command: inout Command) -> Bool {
    convertToTransliteration(&command, .halfAscii)
  }

  /// Switch the composition to Hiragana, full-width Katakana or
  /// half-width Katakana by rotation.
  @discardableResult
  public func switchKanaType(_ command: inout Command) -> Bool {
    if !stateIn(context.state, .conversion, .composition) {
      return doNothing(&command)
    }
    command.output.consumed = true

    if !context.converter.switchKanaType(context.composer) {
      return false
    }
    setSessionState(.conversion, context)
    output(&command)
    return true
  }

  /// Select the transliteration candidate if the current status is
  /// conversion.  This is same with the above ConvertTo functions.  If
  /// the current state is composition, the display mode is changed to the
  /// transliteration and the composition state still remains.
  @discardableResult
  public func displayAsHiragana(_ command: inout Command) -> Bool {
    command.output.consumed = true
    if context.state == .conversion {
      return convertToHiragana(&command)
    } else {  // context_->state() == ImeContext::COMPOSITION
      context.data.composer.setOutputMode(.hiragana)
      outputComposition(&command)
      return true
    }
  }

  @discardableResult
  public func displayAsFullKatakana(_ command: inout Command) -> Bool {
    command.output.consumed = true
    if context.state == .conversion {
      return convertToFullKatakana(&command)
    } else {  // context_->state() == ImeContext::COMPOSITION
      context.data.composer.setOutputMode(.fullKatakana)
      outputComposition(&command)
      return true
    }
  }

  @discardableResult
  public func displayAsHalfKatakana(_ command: inout Command) -> Bool {
    command.output.consumed = true
    if context.state == .conversion {
      return convertToHalfKatakana(&command)
    } else {  // context_->state() == ImeContext::COMPOSITION
      context.data.composer.setOutputMode(.halfKatakana)
      outputComposition(&command)
      return true
    }
  }

  @discardableResult
  public func translateFullASCII(_ command: inout Command) -> Bool {
    command.output.consumed = true
    if context.state == .conversion {
      return convertToFullASCII(&command)
    } else {  // context_->state() == ImeContext::COMPOSITION
      context.data.composer.setOutputMode(
        T13n.toggleFullAsciiTypes(context.composer.getOutputMode()))
      outputComposition(&command)
      return true
    }
  }

  @discardableResult
  public func translateHalfASCII(_ command: inout Command) -> Bool {
    command.output.consumed = true
    if context.state == .conversion {
      return convertToHalfASCII(&command)
    } else {  // context_->state() == ImeContext::COMPOSITION
      context.data.composer.setOutputMode(
        T13n.toggleHalfAsciiTypes(context.composer.getOutputMode()))
      outputComposition(&command)
      return true
    }
  }

  /// Switch the composition mode.
  @discardableResult
  public func compositionModeHiragana(_ command: inout Command) -> Bool {
    command.output.consumed = true
    ensureIMEIsOn()
    // The temporary mode should not be overridden.
    switchInputMode(.hiragana, &context.data.composer)
    outputFromState(&command)
    return true
  }

  @discardableResult
  public func compositionModeFullKatakana(_ command: inout Command) -> Bool {
    command.output.consumed = true
    ensureIMEIsOn()
    // The temporary mode should not be overridden.
    switchInputMode(.fullKatakana, &context.data.composer)
    outputFromState(&command)
    return true
  }

  @discardableResult
  public func compositionModeHalfKatakana(_ command: inout Command) -> Bool {
    command.output.consumed = true
    ensureIMEIsOn()
    // The temporary mode should not be overridden.
    switchInputMode(.halfKatakana, &context.data.composer)
    outputFromState(&command)
    return true
  }

  @discardableResult
  public func compositionModeFullASCII(_ command: inout Command) -> Bool {
    command.output.consumed = true
    ensureIMEIsOn()
    // The temporary mode should not be overridden.
    switchInputMode(.fullAscii, &context.data.composer)
    outputFromState(&command)
    return true
  }

  @discardableResult
  public func compositionModeHalfASCII(_ command: inout Command) -> Bool {
    command.output.consumed = true
    ensureIMEIsOn()
    // The temporary mode should not be overridden.
    switchInputMode(.halfAscii, &context.data.composer)
    outputFromState(&command)
    return true
  }

  @discardableResult
  public func compositionModeSwitchKanaType(_ command: inout Command) -> Bool {
    if context.state != .precomposition {
      return doNothing(&command)
    }

    command.output.consumed = true

    let currentType = context.composer.getInputMode()
    var nextType: TransliterationType

    switch currentType {
    case .hiragana:
      nextType = .fullKatakana
    case .fullKatakana:
      nextType = .halfKatakana
    case .halfKatakana:
      nextType = .hiragana
    case .halfAscii, .fullAscii:
      nextType = currentType
    default:
      GenmaiLog.error("Unknown input mode: \(currentType)")
      // don't change input mode
      nextType = currentType
    }

    // The temporary mode should not be overridden.
    switchInputMode(nextType, &context.data.composer)
    outputFromState(&command)
    return true
  }

  @discardableResult
  public func convertToHalfWidth(_ command: inout Command) -> Bool {
    if !stateIn(context.state, .conversion, .composition) {
      return doNothing(&command)
    }
    command.output.consumed = true

    if !context.converter.convertToHalfWidth(context.composer) {
      return false
    }
    setSessionState(.conversion, context)
    output(&command)
    return true
  }

  @discardableResult
  public func translateHalfWidth(_ command: inout Command) -> Bool {
    command.output.consumed = true
    if context.state == .conversion {
      return convertToHalfWidth(&command)
    } else {  // context_->state() == ImeContext::COMPOSITION
      let type = context.composer.getOutputMode()
      if type == .hiragana || type == .fullKatakana || type == .halfKatakana {
        context.data.composer.setOutputMode(.halfKatakana)
      } else if type == .fullAscii {
        context.data.composer.setOutputMode(.halfAscii)
      } else if type == .fullAsciiUpper {
        context.data.composer.setOutputMode(.halfAsciiUpper)
      } else if type == .fullAsciiLower {
        context.data.composer.setOutputMode(.halfAsciiLower)
      } else if type == .fullAsciiCapitalized {
        context.data.composer.setOutputMode(.halfAsciiCapitalized)
      } else {
        // transliteration::HALF_ASCII_something
        return translateHalfASCII(&command)
      }
      outputComposition(&command)
      return true
    }
  }

  /// Let client launch config dialog
  @discardableResult
  public func launchConfigDialog(_ command: inout Command) -> Bool {
    command.output.launchToolMode = .configDialog
    return doNothing(&command)
  }

  /// Let client launch dictionary tool
  @discardableResult
  public func launchDictionaryTool(_ command: inout Command) -> Bool {
    command.output.launchToolMode = .dictionaryTool
    return doNothing(&command)
  }

  /// Let client launch word register dialog
  @discardableResult
  public func launchWordRegisterDialog(_ command: inout Command) -> Bool {
    command.output.launchToolMode = .wordRegisterDialog
    return doNothing(&command)
  }

  /// Undo if pre-composition is empty. Rewind KANA cycle otherwise.
  @discardableResult
  public func undoOrRewind(_ command: inout Command) -> Bool {
    // Undo is prioritized over rewind otherwise the undo operation for
    // partial commit doesn't work (rewind always consumes the event).
    if hasUndoContext() {
      return undo(&command)
    }

    // Rewind if the state is in composition.
    if context.state != .composition {
      // Mozc decoder doesn't do anything for UNDO_OR_REWIND.
      // Echo back the event to the client to give it a chance to delegate
      // undo operation to the app.
      return echoBack(&command)
    }

    command.output.consumed = true
    context.data.composer.insertCommandCharacter(.rewind)
    clearUndoContext()

    // InsertCommandCharacter method updates the preedit text
    // so we need to update suggest candidates.
    if suggest(command.input) {
      output(&command)
      return true
    }
    outputComposition(&command)
    return true
  }

  /// Stops key toggling in the composer.
  @discardableResult
  public func stopKeyToggling(_ command: inout Command) -> Bool {
    if context.state != .composition {
      return doNothing(&command)
    }

    command.output.consumed = true
    context.data.composer.insertCommandCharacter(.stopKeyToggling)
    clearUndoContext()

    // Since the output should not be changed on STOP_KEY_TOGGLING,
    // The last output is used instead of calling the converter operations.
    output(&command)
    return true
  }

  @discardableResult
  public func toggleAlphanumericMode(_ command: inout Command) -> Bool {
    command.output.consumed = true
    context.data.composer.toggleInputMode()

    outputFromState(&command)
    return true
  }

  /// Tries deleting the specified candidate from the user prediction history.
  /// The candidate is determined by command.input.command.id, or the current
  /// focused candidate if that ....command.id is not specified. If
  /// that candidate, as a key value pair, doesn't exist in the user history,
  /// nothing happens. Regardless of the result of internal history deletion,
  /// invoking this method has the same effect as ConvertCancel() from the
  /// viewpoint of session, meaning that the session state gets back to
  /// composition.
  @discardableResult
  public func deleteCandidateFromHistory(_ command: inout Command) -> Bool {
    var id: Int? = nil
    if command.input.hasCommand && command.input.command.hasID {
      id = Int(command.input.command.id)
    }
    if !context.converter.deleteCandidateFromHistory(id) {
      return doNothing(&command)
    }
    return convertCancel(&command)
  }

  @discardableResult
  public func convert(_ command: inout Command) -> Bool {
    command.output.consumed = true
    let composition = context.composer.getQueryForConversion()

    // TODO(komatsu): Make a function like ConvertOrSpace.
    // Handle a space key on the ASCII composition mode.
    if context.state == .composition
      && (context.composer.getInputMode() == .halfAscii
        || context.composer.getInputMode() == .fullAscii)
      && command.input.key.hasSpecialKey && command.input.key.specialKey == .space
    {
      // TODO(komatsu): Consider FullWidth Space too.
      if composition.utf8.last != UInt8(ascii: " ")
        || context.composer.getLength() != context.composer.getCursor()
      {
        if context.getRequest().spaceOnAlphanumeric == .commit {
          // Space is committed with the composition
          context.data.composer.insertCharacterPreedit(" ")
          // Don't push the context to the undo context here.
          // It'll be done in Commit() below.
          return commit(&command)
        } else {
          // SPACE_OR_CONVERT_KEEPING_COMPOSITION or
          // SPACE_OR_CONVERT_COMMITTING_COMPOSITION.

          // If the last character is not space, space is inserted to the
          // composition.
          command.input.key.keyCode = UInt32(UInt8(ascii: " "))
          return insertCharacter(&command)
        }
      }

      if !composition.isEmpty {
        // Delete the last space.
        context.data.composer.backspace()
        clearUndoContext()
      }
    }

    if !context.converter.convert(context.composer, context.clientContext) {
      GenmaiLog.error("Conversion failed for some reasons.")
      outputComposition(&command)
      return true
    }

    setSessionState(.conversion, context)
    output(&command)
    return true
  }

  /// Starts conversion not using user history.  This is used for debugging.
  @discardableResult
  public func convertWithoutHistory(_ command: inout Command) -> Bool {
    command.output.consumed = true

    var preferences = context.converter.conversionPreferences
    preferences.useHistory = false
    if !context.converter.convert(context.composer, context.clientContext, preferences) {
      GenmaiLog.error("Conversion failed for some reasons.")
      outputComposition(&command)
      return true
    }

    setSessionState(.conversion, context)
    output(&command)
    return true
  }

  /// Commits preedit if in password mode.
  @discardableResult
  public func commitIfPassword(_ command: inout Command) -> Bool {
    if context.composer.getInputFieldType() == .password {
      commitCompositionDirectly(&command)
      return true
    }
    return false
  }

  @discardableResult
  public func moveCursorRight(_ command: inout Command) -> Bool {
    // In future, we may want to change the strategy of committing, to support
    // more flexible behavior.
    // - If the composing text has some "pending toggling character(s) at the
    //   end", we'd like to "fix" the toggling state, but not to commit.
    // - Otherwise (i.e. if there is no such character(s)), we'd like to commit
    //   (considering the use cases, probably we'd like to apply it only for
    //   alphabet mode).
    // Before supporting it, we'll need to support auto fixing by waiting
    // a period. Also, it is necessary to support displaying the current toggling
    // state (otherwise, users would be confused).
    // So, to keep users out from such confusion, we only commit if the current
    // composing mode doesn't has toggling state. Clients has the responsibility
    // to check if the keyboard has toggling state or not. Note that the server
    // should know the current table has toggling state or not. However,
    // a client may NOT want to auto committing even if the composition mode
    // doesn't have the toggling state, so the server just relies on the flag
    // passed from the client.
    // TODO(hidehiko): Support it, when it is prioritized.
    if context.getRequest().crossingEdgeBehavior == .commitWithoutConsuming
      && context.composer.getLength() == context.composer.getCursor()
    {
      commit(&command)

      // Do not consume.
      command.output.consumed = false
      return true
    }

    command.output.consumed = true
    if commitIfPassword(&command) {
      return true
    }
    context.data.composer.moveCursorRight()
    clearUndoContext()
    if suggest(command.input) {
      output(&command)
      return true
    }
    outputComposition(&command)
    return true
  }

  @discardableResult
  public func moveCursorLeft(_ command: inout Command) -> Bool {
    if context.getRequest().crossingEdgeBehavior == .commitWithoutConsuming
      && context.composer.getCursor() == 0
    {
      commitNotTriggeringZeroQuerySuggest(&command)

      // Move the cursor to the beginning of the values.
      command.output.result.cursorOffset = -Int32(Util.charsLen(command.output.result.value))

      // Do not consume.
      command.output.consumed = false
      return true
    }

    command.output.consumed = true
    if commitIfPassword(&command) {
      return true
    }
    context.data.composer.moveCursorLeft()
    clearUndoContext()
    if suggest(command.input) {
      output(&command)
      return true
    }
    outputComposition(&command)
    return true
  }

  @discardableResult
  public func moveCursorToEnd(_ command: inout Command) -> Bool {
    moveCursorToEndInternal(&command, true)
  }

  @discardableResult
  private func moveCursorToEndInternal(_ command: inout Command, _ clearUndo: Bool) -> Bool {
    command.output.consumed = true
    if commitIfPassword(&command) {
      return true
    }
    context.data.composer.moveCursorToEnd()
    if clearUndo {
      clearUndoContext()
    }
    if suggest(command.input) {
      output(&command)
      return true
    }
    outputComposition(&command)
    return true
  }

  @discardableResult
  public func moveCursorTo(_ command: inout Command) -> Bool {
    // This method moves the cursor *inside* the composition text.
    // Therefore on PRECOMPOSITION state, where there is no composition text,
    // this method shouldn't consume the event but send back it to the client.
    if context.state == .precomposition {
      return echoBack(&command)
    }
    if context.state != .composition {
      return doNothing(&command)
    }
    command.output.consumed = true
    if commitIfPassword(&command) {
      return true
    }
    context.data.composer.moveCursorTo(command.input.command.cursorPosition)
    clearUndoContext()
    if suggest(command.input) {
      output(&command)
      return true
    }
    outputComposition(&command)
    return true
  }

  @discardableResult
  public func moveCursorToBeginning(_ command: inout Command) -> Bool {
    command.output.consumed = true
    if commitIfPassword(&command) {
      return true
    }
    context.data.composer.moveCursorToBeginning()
    clearUndoContext()
    if suggest(command.input) {
      output(&command)
      return true
    }
    outputComposition(&command)
    return true
  }

  @discardableResult
  public func delete(_ command: inout Command) -> Bool {
    command.output.consumed = true
    context.data.composer.delete()
    clearUndoContext()
    if context.composer.isEmpty() {
      setStateToPredompositionAndCancel(context)
      output(&command)
    } else if suggest(command.input) {
      output(&command)
    } else {
      outputComposition(&command)
    }
    return true
  }

  @discardableResult
  public func backspace(_ command: inout Command) -> Bool {
    command.output.consumed = true
    context.data.composer.backspace()
    clearUndoContext()
    if context.composer.isEmpty() {
      setStateToPredompositionAndCancel(context)
      output(&command)
    } else if suggest(command.input) {
      output(&command)
    } else {
      outputComposition(&command)
    }
    return true
  }

  @discardableResult
  public func segmentFocusRight(_ command: inout Command) -> Bool {
    if context.state != .conversion {
      return doNothing(&command)
    }
    command.output.consumed = true
    context.converter.segmentFocusRight()
    output(&command)
    return true
  }

  @discardableResult
  public func segmentFocusLast(_ command: inout Command) -> Bool {
    if context.state != .conversion {
      return doNothing(&command)
    }
    command.output.consumed = true
    context.converter.segmentFocusLast()
    output(&command)
    return true
  }

  @discardableResult
  public func segmentFocusLeft(_ command: inout Command) -> Bool {
    if context.state != .conversion {
      return doNothing(&command)
    }
    command.output.consumed = true
    context.converter.segmentFocusLeft()
    output(&command)
    return true
  }

  @discardableResult
  public func segmentFocusLeftEdge(_ command: inout Command) -> Bool {
    if context.state != .conversion {
      return doNothing(&command)
    }
    command.output.consumed = true
    context.converter.segmentFocusLeftEdge()
    output(&command)
    return true
  }

  @discardableResult
  public func segmentWidthExpand(_ command: inout Command) -> Bool {
    if context.state != .conversion {
      return doNothing(&command)
    }
    command.output.consumed = true
    context.converter.segmentWidthExpand(context.composer)
    output(&command)
    return true
  }

  @discardableResult
  public func segmentWidthShrink(_ command: inout Command) -> Bool {
    if context.state != .conversion {
      return doNothing(&command)
    }
    command.output.consumed = true
    context.converter.segmentWidthShrink(context.composer)
    output(&command)
    return true
  }

  @discardableResult
  public func reportBug(_ command: inout Command) -> Bool {
    doNothing(&command)
  }

  @discardableResult
  public func convertNext(_ command: inout Command) -> Bool {
    command.output.consumed = true
    context.converter.candidateNext(context.composer)
    output(&command)
    return true
  }

  /// Shows the next page of candidates.
  @discardableResult
  public func convertNextPage(_ command: inout Command) -> Bool {
    if context.state != .conversion {
      return doNothing(&command)
    }
    command.output.consumed = true
    context.converter.candidateNextPage()
    output(&command)
    return true
  }

  @discardableResult
  public func convertPrev(_ command: inout Command) -> Bool {
    command.output.consumed = true
    context.converter.candidatePrev()
    output(&command)
    return true
  }

  /// Shows the previous page of candidates.
  @discardableResult
  public func convertPrevPage(_ command: inout Command) -> Bool {
    if context.state != .conversion {
      return doNothing(&command)
    }
    command.output.consumed = true
    context.converter.candidatePrevPage()
    output(&command)
    return true
  }

  @discardableResult
  public func convertCancel(_ command: inout Command) -> Bool {
    command.output.consumed = true

    setSessionState(.composition, context)
    context.converter.cancel()
    if suggest(command.input) {
      output(&command)
    } else {
      outputComposition(&command)
    }
    return true
  }

  @discardableResult
  public func predictAndConvert(_ command: inout Command) -> Bool {
    if context.state == .conversion {
      return convertNext(&command)
    }

    command.output.consumed = true
    if context.converter.predict(context.composer, context.clientContext) {
      setSessionState(.conversion, context)
      output(&command)
    } else {
      outputComposition(&command)
    }
    return true
  }

  /// Fill command's output according to the current state.
  private func outputFromState(_ command: inout Command) {
    if context.state == .direct {
      outputMode(&command)
      return
    }
    output(&command)
  }

  private func output(_ command: inout Command) {
    outputMode(&command)
    context.converter.popOutput(context.composer, &command.output)
  }

  private func outputMode(_ command: inout Command) {
    let mode = toCompositionMode(context.composer.getInputMode())
    let comebackMode = toCompositionMode(context.composer.getComebackInputMode())

    if context.state == .direct {
      command.output.mode = .direct
      command.output.status.activated = false
    } else {
      command.output.mode = mode
      command.output.status.activated = true
    }
    command.output.status.mode = mode
    command.output.status.comebackMode = comebackMode
  }

  private func outputComposition(_ command: inout Command) {
    outputMode(&command)
    context.converter.fillPreedit(context.composer, &command.output.preedit)
  }

  private func outputKey(_ command: inout Command) {
    outputMode(&command)
    command.output.key = command.input.key
  }

  /// return true if |key_event| is a triggering key_event of
  /// AutoIMEConversion.
  private func canStartAutoConversion(_ keyEvent: KeyEvent) -> Bool {
    if !context.getConfig().useAutoConversion {
      return false
    }

    // Disable if the input comes from non-standard user keyboards, like numpad.
    // http://b/issue?id=2932067
    if keyEvent.inputStyle != .followMode {
      return false
    }

    // This is a tentative workaround for the bug http://b/issue?id=2932028
    // When user types <Shift Down>O<Shift Up>racle<Shift Down>!<Shift Up>,
    // The final "!" must be half-width, however, due to the limitation
    // of converter interface, we don't have a good way to change it halfwidth, as
    // the default preference of "!" is fullwidth. Basically, the converter is
    // not composition-mode-aware.
    // We simply disable the auto conversion feature if the mode is ASCII.
    // We conclude that disabling this feature is better in this situation.
    // TODO(taku): fix the behavior. Converter module needs to be fixed.
    if keyEvent.mode == .halfAscii || keyEvent.mode == .fullAscii {
      return false
    }

    // We should NOT check key_string. http://b/issue?id=3217992

    // Auto conversion is not triggered if the composition is empty or
    // only one character, or the cursor is not in the end of the
    // composition.
    let length = context.composer.getLength()
    if length <= 1 || length != context.composer.getCursor() {
      return false
    }

    let keyCode = keyEvent.keyCode

    let preedit = context.composer.getStringForPreedit()
    let lastChar = Util.utf8SubString(preedit, length - 1, 1)
    if lastChar.isEmpty {
      return false
    }

    // Check last character as user may change romaji table,
    // For instance, if user assigns "." as "foo", we don't
    // want to invoke auto_conversion.
    if !isValidKey(context.getConfig(), keyCode, lastChar) {
      return false
    }

    // Check the previous character of last_character.
    // when |last_prev_char| is number, we don't invoke auto_conversion
    // if the same invoke key is repeated, do not conversion.
    // http://b/issue?id=2932118
    let lastPrevChar = Util.utf8SubString(preedit, length - 2, 1)
    if lastPrevChar.isEmpty || lastPrevChar == lastChar
      || Util.getScriptType(lastPrevChar) == .number
    {
      return false
    }

    return true
  }

  /// update last_command_time;
  private func updateTime() {
    context.lastCommandTime = Clock.getAbslTime()
  }

  /// Modify input of SendKey, TestSendKey, and SendCommand.
  private func transformInput(_ input: inout Genmai_Commands_Input) {
    if input.hasKey {
      context.keyEventTransformer.transformKeyEvent(&input.key)
    }
  }

  /// Specify the input field type.
  @discardableResult
  public func switchInputFieldType(_ command: inout Command) -> Bool {
    command.output.consumed = true
    context.data.composer.setInputFieldType(command.input.context.inputFieldType)
    output(&command)
    return true
  }

  /// Handles KeyEvent::activated to support indirect IME on/off.
  private func handleIndirectImeOnOff(_ command: inout Command) -> Bool {
    let key = command.input.key
    if !key.hasActivated {
      return true
    }
    let state = context.state
    if state == .direct && key.activated {
      // Indirect IME On found.
      var onCommand = command
      if !imeOn(&onCommand) {
        return false
      }
    } else if state != .direct && !key.activated {
      // Indirect IME Off found.
      var offCommand = command
      if !imeOff(&offCommand) {
        return false
      }
    }
    return true
  }

  /// Special IME action key on mobile, such as Search, Send, Go, and Next
  /// keys.
  @discardableResult
  public func imeAction(_ command: inout Command) -> Bool {
    if context.state != .precomposition || context.composer.getInputFieldType() != .normal {
      return false
    }

    // ImeAction is triggered when the mobile-specific IME action buttons such as
    // Search, Go, or Next, are tapped. After a user finishes an IME session, they
    // might still perform manual edits using the Backspace key. To sync these
    // edits with the converter, we call CommitContext. Typical use case is the
    // partial-revert on user history training.
    context.converter.commitContext(context.composer, command.input.context)

    return true
  }

  /// Commits the raw text of the composition.
  @discardableResult
  public func commitRawText(_ command: inout Command) -> Bool {
    if context.composer.getLength() == 0 {
      return false
    }
    commitRawTextDirectly(&command)
    return true
  }

  // TODO(komatsu): delete this function.
  // For unittest only
  public func withInternalComposerOnlyForUnittest<R>(_ body: (inout Composer) throws -> R)
    rethrows -> R
  {
    try body(&contextImpl.data.composer)
  }

  public var internalComposerOnlyForUnittest: Composer {
    get { contextImpl.data.composer }
    set { contextImpl.data.composer = newValue }
  }

}
