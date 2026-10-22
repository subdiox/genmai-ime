// Port of mozc/src/mac/mozc_imk_input_controller.{h,mm} (3.35.6354), the platform-independent part.
//
// `GenmaiInputController` holds all the logic of GenmaiImkInputController (key handling, preedit, candidate
// window, mode switching, reconversion / undo, surrounding text, app launching). The IMKInputController
// subclass (`GenmaiImkInputController` in GenmaiImkInputController.swift) only forwards InputMethodKit calls to
// it, which lets the C++ unit tests (mozc_imk_input_controller_test.mm) be ported without an IMKServer.
//
// Mapping of the C++ dependencies:
// - `[self client]` / the `sender` argument -> `any TextInputClient` (IMKTextInput proxy).
// - `genmaiClient_` -> `any GenmaiClientProtocol`; `genmaiRenderer_` -> `any RendererInterface`.
// - `MacProcess::LaunchGenmaiTool` -> `any AppLauncher`; `NSWorkspace openURL` -> `urlOpener`.
// - `-markForStyle:atRange:` -> `markAttributes` (IMKInputController provides the real attributes).
// - `performSelector:afterDelay:0` -> a main-actor Task (runs after the current event is handled).

import AppKit
import Carbon
import GenmaiBase
import GenmaiClient
import GenmaiMacObjC
import GenmaiProtocol
import GenmaiRenderer

/// The subset of IMKTextInput used by the controller.
@MainActor
public protocol TextInputClient: AnyObject {
  func bundleIdentifier() -> String?
  func insertText(_ text: String, replacementRange: NSRange)
  func setMarkedText(_ text: NSAttributedString, selectionRange: NSRange, replacementRange: NSRange)
  func selectedRange() -> NSRange
  func markedRange() -> NSRange
  func length() -> Int
  func attributedSubstring(from range: NSRange) -> NSAttributedString?
  func selectInputMode(_ modeIdentifier: String)
  func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String)
  /// `attributesForCharacterIndex:lineHeightRectangle:`; may raise an Objective-C exception in some apps.
  func attributes(forCharacterIndex index: Int, lineHeightRectangle: inout NSRect) -> [AnyHashable: Any]?
}

/// Mirrors the ControllerCallback protocol of mac/common.h (RendererReceiver -> controller).
@MainActor
public protocol ControllerCallback: AnyObject {
  func sendCommand(_ command: SessionCommand)
  func outputResult(_ output: Output)
}

// TODO(horo): This value should be get from system configuration.
//  DoubleClickInterval can be get from NSEvent (MacOSX ver >= 10.6)
let kDoubleTapInterval: TimeInterval = 0.5

let kMaxSurroundingLength = 20
/// Not in Mozc: the surrounding text length read for the AI conversion's left context.
let kMaxAISurroundingLength = 500
// In some apllications when the client's text length is large, getting the
// surrounding text takes too much time. So we set this limitation.
let kGetSurroundingTextClientLengthLimit = 1000

public let kRomanModeId = "com.apple.inputmethod.Roman"
public let kKatakanaModeId = "com.apple.inputmethod.Japanese.Katakana"
public let kHalfWidthKanaModeId = "com.apple.inputmethod.Japanese.HalfWidthKana"
public let kFullWidthRomanModeId = "com.apple.inputmethod.Japanese.FullWidthRoman"
public let kHiraganaModeId = "com.apple.inputmethod.Japanese"

public typealias CompositionMode = Genmai_Commands_CompositionMode

func getCompositionMode(_ modeID: String) -> CompositionMode {
  if modeID.isEmpty {
    GenmaiLog.error("mode_id is initialized.")
    return .direct
  }
  // The information for ID names was available at
  // HIToolbox.framework/Versions/A/Headers/TextServices.h
  // These IDs are also defined in Info.plist.
  switch modeID {
  case kRomanModeId: return .halfAscii
  case kKatakanaModeId: return .fullKatakana
  case kHalfWidthKanaModeId: return .halfKatakana
  case kFullWidthRomanModeId: return .fullAscii
  case kHiraganaModeId: return .hiragana
  default:
    GenmaiLog.error("The code should not reach here.")
    return .direct
  }
}

func getModeId(_ mode: CompositionMode) -> String {
  switch mode {
  case .direct, .halfAscii: return kRomanModeId
  case .fullKatakana: return kKatakanaModeId
  case .halfKatakana: return kHalfWidthKanaModeId
  case .fullAscii: return kFullWidthRomanModeId
  case .hiragana: return kHiraganaModeId
  default:
    GenmaiLog.error("The code should not reach here.")
    return kRomanModeId
  }
}

func canOpenLink(_ bundleID: String) -> Bool {
  // Should not open links during screensaver.
  bundleID != "com.apple.securityagent"
}

func canSelectedRange(_ bundleID: String) -> Bool {
  // Do not call selectedRange: method for the following
  // applications because it could lead to application crash.
  bundleID != "com.microsoft.Excel" && bundleID != "com.microsoft.Powerpoint"
    && bundleID != "com.microsoft.Word"
}

func canDisplayModeSwitch(_ bundleID: String) -> Bool {
  // Do not call selectInputMode: method for the following
  // applications because it could cause some unexpected behavior.
  // MS-Word: When the display mode goes to ASCII but there is no
  // compositions, it goes to direct input mode instead of Half-ASCII
  // mode.  When the first composition character is alphanumeric (such
  // like pressing Shift-A at first), that character is directly
  // inserted into application instead of composition starting "A".
  bundleID != "com.microsoft.Word"
}

func canSurroundingText(_ bundleID: String) -> Bool {
  // Disables the surrounding text feature for the following application
  // because calling attributedSubstringFromRange to it is very heavy.
  bundleID != "com.evernote.Evernote"
}

private let kNotFoundRange = NSRange(location: NSNotFound, length: 0)

@MainActor
public final class GenmaiInputController: ControllerCallback {
  /// stores the current preedit text
  public private(set) var composedString = NSMutableAttributedString()
  /// stores original key strokes.
  public private(set) var originalString = ""
  /// The position of cursor in the preedit.  If no cursor is found, its value should be -1.
  private var cursorPosition = -1
  /// stores the current input mode (Direct or conversion).
  public var mode: CompositionMode = .direct
  /// holds the character for the YEN_SIGN key in JIS keyboard.  This config is
  /// separated from |keyCodeMap_| because it is for DIRECT mode.
  public private(set) var yenSignCharacter: Genmai_Config_Config.YenSignCharacter = .yenSign
  /// indicates whether to suppress the suggestion.
  private var suppressSuggestion = false
  /// manages the mapping between Mac key code and mozc key events.
  public var keyCodeMap = KeyCodeMap()
  /// the Bundle ID of the client application which the controller communicates with.
  public private(set) var clientBundle = ""
  public var replacementRange = NSRange(location: NSNotFound, length: 0)
  /// used to handle double tapping.
  private var lastKeyDownTime: TimeInterval = 0
  private var lastKeyCode: UInt16 = 0
  /// controls the candidate windows.
  public var renderer: (any RendererInterface)?
  /// stores the command sent to |genmaiRenderer_|
  public private(set) var rendererCommand = RendererCommand()
  /// manages connection to the mozc server.
  public var genmaiClient: any GenmaiClientProtocol

  /// Not in Mozc: receives up to `kMaxAISurroundingLength` characters before the insertion point whenever the
  /// surrounding context is filled (the AI conversion's left context; Mozc's own preceding_text stays 20).
  public var aiSurroundingTextObserver: (@MainActor (String) -> Void)?

  /// Not in Mozc: for a conversion key whose AI result is still being computed, a task to await before the key
  /// is sent (`AIConversionHook.conversionWait`, bounded by its timeout). Meanwhile this key and the keys after
  /// it are queued (reported as handled) and sent in order when the wait is over, so no thread ever blocks.
  /// Any other request to the converter (mode switch, commit, commands, candidate clicks) first sends the queued
  /// keys without waiting.
  public var aiConversionGate: (@MainActor (KeyEvent) -> Task<Void, Never>?)?

  /// Not in Mozc: after a key was answered with a suggestion window, a task that finishes when the AI conversion
  /// of that composition arrives (`AIConversionHook.suggestionUpdate`; true = it has a new top-1). The controller
  /// then re-requests the suggestion for the unchanged composition (MOVE_CURSOR to the current cursor position)
  /// and updates only the candidate window, unless anything happened meanwhile (another output, queued keys, the
  /// suggestion window closed).
  public var aiSuggestionUpdate: (@MainActor () -> Task<Bool, Never>?)?

  /// Incremented by every `processOutput`: an AI suggestion refresh scheduled before is stale.
  private var outputGeneration = 0
  /// The pending AI suggestion refresh (tests).
  private var pendingSuggestionRefresh: Task<Void, Never>?

  private struct QueuedKey {
    var key: KeyEvent
    var context: Context
    var sender: (any TextInputClient)?
  }

  private var queuedKeys: [QueuedKey] = []
  private var queueGeneration = 0

  private let currentClient: @MainActor () -> (any TextInputClient)?
  private let toolLauncher: (any AppLauncher)?
  private let urlOpener: @MainActor (URL) -> Void
  private let markAttributes: @MainActor (Int32) -> [NSAttributedString.Key: Any]
  private let selectionRangeFallback: @MainActor () -> NSRange
  private let now: @MainActor () -> TimeInterval
  private let frontmostWindow: @MainActor () -> (name: String, owner: String)?
  private var pendingCandidateUpdates: [Task<Void, Never>] = []

  /// - Parameters:
  ///   - currentClient: `[self client]`.
  ///   - markAttributes: `-markForStyle:atRange:` for kTSMHiliteSelectedConvertedText / kTSMHiliteConvertedText.
  ///   - selectionRangeFallback: `[super selectionRange]`.
  public init(
    genmaiClient: any GenmaiClientProtocol,
    renderer: (any RendererInterface)?,
    currentClient: @escaping @MainActor () -> (any TextInputClient)?,
    toolLauncher: (any AppLauncher)?,
    urlOpener: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
    markAttributes: @escaping @MainActor (Int32) -> [NSAttributedString.Key: Any] =
      GenmaiInputController.defaultMarkAttributes,
    selectionRangeFallback: @escaping @MainActor () -> NSRange = { NSRange(location: NSNotFound, length: 0) },
    now: @escaping @MainActor () -> TimeInterval = { Date().timeIntervalSince1970 },
    frontmostWindow: @escaping @MainActor () -> (name: String, owner: String)? = {
      MacWindowUtil.getFrontmostWindowNameAndOwner()
    }
  ) {
    self.genmaiClient = genmaiClient
    self.renderer = renderer
    self.currentClient = currentClient
    self.toolLauncher = toolLauncher
    self.urlOpener = urlOpener
    self.markAttributes = markAttributes
    self.selectionRangeFallback = selectionRangeFallback
    self.now = now
    self.frontmostWindow = frontmostWindow

    if let renderer, !renderer.activate() {
      GenmaiLog.error("Cannot activate renderer")
      self.renderer = nil
    }
    setupClientBundle(currentClient())
    setupCapability()
    rendererCommand.applicationInfo.processID = UInt32(ProcessInfo.processInfo.processIdentifier)
    // thread_id and receiver_handle are not used currently in Mac but
    // set some values to prevent warning.
    rendererCommand.applicationInfo.threadID = 0
    rendererCommand.applicationInfo.receiverHandle = 0
  }

  /// The attributes IMKInputController returns for the two highlight styles (used when no IMK server).
  public static func defaultMarkAttributes(_ style: Int32) -> [NSAttributedString.Key: Any] {
    let thick = style == Int32(kTSMHiliteSelectedConvertedText)
    return [
      .underlineStyle: thick ? NSUnderlineStyle.thick.rawValue : NSUnderlineStyle.single.rawValue,
      .markedClauseSegment: 0,
    ]
  }

  private var client: (any TextInputClient)? { currentClient() }

  // MARK: - IMKStateSetting Protocol

  public func activateServer(_ sender: (any TextInputClient)?) {
    // Not in Mozc: a newly focused client starts with an empty AI left context (until the surrounding text is
    // read at the next composition).
    aiSurroundingTextObserver?("")
    setupClientBundle(sender)
    if rendererCommand.visible, let renderer {
      renderer.execCommand(rendererCommand)
    }
    handleConfig()

    if let (windowName, windowOwner) = frontmostWindow() {
      suppressSuggestion = MacWindowUtil.isSuppressSuggestionWindow(windowName, windowOwner)
    }
  }

  public func deactivateServer(_ sender: (any TextInputClient)?) {
    flushQueuedKeys()
    var clearCommand = RendererCommand()
    clearCommand.type = .update
    clearCommand.visible = false
    clearCommand.clearOutput()
    renderer?.execCommand(clearCommand)
  }

  /// Because we want to handle single Shift key pressing later, now I
  /// turned on NSFlagsChanged also.
  public nonisolated static let recognizedEvents: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]

  /// This method is called when a user changes the input mode.
  public func setValue(_ value: Any?, client sender: (any TextInputClient)?) {
    flushQueuedKeys()
    var newMode: CompositionMode = .direct
    if let value = value as? String {
      newMode = getCompositionMode(value)
    }
    if newMode == .halfAscii && composedString.length == 0 {
      newMode = .direct
    }
    switchMode(newMode, client: sender)
    handleConfig()
  }

  // MARK: - internal methods

  /// Obtains the current configuration from the server and update client-specific configurations.
  public func handleConfig() {
    // Get the config and set client-side behaviors
    guard let config = genmaiClient.getConfig() else {
      GenmaiLog.error("Cannot obtain the current config")
      return
    }
    var inputMode: InputMode = .ascii
    if config.preeditMethod == .kana {
      inputMode = .kana
    }
    keyCodeMap.inputMode = inputMode
    yenSignCharacter = config.yenSignCharacter

    if config.useJapaneseLayout {
      // Apple does not have "Japanese" layout actually -- here sets
      // "US" layout, which means US-ASCII layout or JIS layout
      // depending on which type of keyboard is actually connected.
      client?.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.US")
    }
  }

  public func setupClientBundle(_ sender: (any TextInputClient)?) {
    if let bundleIdentifier = sender?.bundleIdentifier(), !bundleIdentifier.isEmpty {
      clientBundle = bundleIdentifier
    }
  }

  public func setupCapability() {
    var capability = Capability()
    if canSelectedRange(clientBundle) {
      capability.textDeletion = .deletePrecedingText
    } else {
      capability.textDeletion = .noTextDeletionCapability
    }
    genmaiClient.setClientCapability(capability)
  }

  /// Switches to a new mode and sync the current mode with the converter.
  public func switchMode(_ newMode: CompositionMode, client sender: (any TextInputClient)?) {
    flushQueuedKeys()
    if mode == newMode {
      return
    }

    if newMode == .direct {
      // Turn off the IME and commit the composing text.
      var keyEvent = KeyEvent()
      keyEvent.specialKey = .off
      if let output = genmaiClient.sendKey(keyEvent), output.hasResult {
        commitText(output.result.value, client: sender)
      }
      if composedString.length > 0 {
        updateComposedString(nil)
        clearCandidates()
      }
      mode = .direct
      return
    }

    if mode == .direct {
      // Turn on the IME as the mode is changed from DIRECT to an active mode.
      var keyEvent = KeyEvent()
      keyEvent.specialKey = .on
      _ = genmaiClient.sendKey(keyEvent)
    }

    // Switch composition mode.
    var command = SessionCommand()
    command.type = .switchCompositionMode
    command.compositionMode = newMode
    _ = genmaiClient.sendCommand(command)
    mode = newMode
  }

  /// Switches the mode icon in the task bar according to |mode_|.
  public func switchDisplayMode() {
    if !canDisplayModeSwitch(clientBundle) {
      return
    }
    client?.selectInputMode(getModeId(mode))
  }

  /// Commits the specified text to the current client.
  public func commitText(_ text: String?, client sender: (any TextInputClient)?) {
    guard let text else { return }
    sender?.insertText(text, replacementRange: replacementRange)
    replacementRange = kNotFoundRange
  }

  /// Launches the word register tool with the current selection range.
  public func launchWordRegisterTool(_ client: (any TextInputClient)?) {
    var environment = [kWordRegisterEnvironmentName: ""]
    if canSelectedRange(clientBundle), let client {
      let selectedRange = client.selectedRange()
      if selectedRange.location != NSNotFound && selectedRange.length != NSNotFound
        && selectedRange.length > 0
      {
        if let text = client.attributedSubstring(from: selectedRange)?.string {
          environment[kWordRegisterEnvironmentName] = text
        }
      }
    }
    toolLauncher?.openApp(
      mode: AppScreen.wordRegisterDialog.rawValue, extraArg: "", environment: environment)
  }

  /// Conducts the reconvert event.  It could have several tricks such like invoking UNDO instead if
  /// nothing is selected.
  public func invokeReconvert(_ command: SessionCommand, client sender: (any TextInputClient)?) {
    flushQueuedKeys()
    if !canSelectedRange(clientBundle) {
      return
    }
    guard let sender else { return }
    let selectedRange = sender.selectedRange()
    if selectedRange.location == NSNotFound || selectedRange.length == NSNotFound {
      // the application does not support reconversion.
      return
    }

    var sendingCommand = command
    if selectedRange.length == 0 {
      // Currently no range is selected for reconversion.  Tries to
      // invoke UNDO instead.
      invokeUndo(sender)
      return
    }

    if !sendingCommand.hasText {
      guard let text = sender.attributedSubstring(from: selectedRange)?.string else {
        return
      }
      sendingCommand.text = text
    }

    if let output = genmaiClient.sendCommand(sendingCommand) {
      replacementRange = selectedRange
      processOutput(output, client: sender)
    }
  }

  /// Conducts the undo command.
  public func invokeUndo(_ sender: (any TextInputClient)?) {
    flushQueuedKeys()
    if !canSelectedRange(clientBundle) {
      return
    }
    guard let sender else { return }
    let selectedRange = sender.selectedRange()
    if selectedRange.location == NSNotFound || selectedRange.length == NSNotFound
      // Some applications such like iTunes does not return NSNotFound
      // range but (0, 0).  However, the range starting with negative
      // location has to be invalid, then we can reject such apps.
      || selectedRange.location == 0
    {
      return
    }

    var command = SessionCommand()
    command.type = .undo
    if let output = genmaiClient.sendCommand(command) {
      processOutput(output, client: sender)
    }
  }

  /// Processes output fields such as preedit, output text, candidates, and modes.
  public func processOutput(_ output: Output?, client sender: (any TextInputClient)?) {
    guard let output else { return }
    if !output.consumed {
      return
    }
    outputGeneration += 1

    if output.hasURL, let url = URL(string: output.url) {
      openLink(url)
    }

    if output.hasResult {
      commitText(output.result.value, client: sender)
    }

    // Handles deletion range.  We do not even handle it for some
    // applications to prevent application crashes.
    if output.hasDeletionRange && canSelectedRange(clientBundle) {
      if composedString.length == 0 && replacementRange.location == NSNotFound, let sender {
        var selectedRange = sender.selectedRange()
        let deletionRange = output.deletionRange
        if selectedRange.location != NSNotFound || selectedRange.length != NSNotFound
          || selectedRange.location + Int(deletionRange.offset) > 0
        {
          // The offset is a negative value.  See protocol/commands.proto for
          // the details.
          selectedRange.location += Int(deletionRange.offset)
          selectedRange.length += Int(deletionRange.length)
          replacementRange = selectedRange
        }
      } else {
        // We have to consider the case that there is already
        // composition and/or we already set the position of the
        // composition by replacementRange_.  We do nothing here at this
        // time because we already found that it will involve several
        // buggy behaviors with Carbon apps and MS Office.
      }
    }

    updateComposedString(output.preedit)
    updateCandidates(output)

    if output.hasMode {
      var newMode = output.mode
      // Do not allow HALF_ASCII with empty composition.  This should be
      // handled in the converter, but just in case.
      if newMode == .halfAscii && (!output.hasPreedit || output.preedit.segment.isEmpty) {
        newMode = .direct
        switchMode(newMode, client: sender)
      }
      if newMode != mode {
        mode = newMode
        switchDisplayMode()
      }
    }

    if output.hasLaunchToolMode {
      switch output.launchToolMode {
      case .configDialog:
        toolLauncher?.openApp(mode: AppScreen.configDialog.rawValue, extraArg: "", environment: [:])
      case .dictionaryTool:
        toolLauncher?.openApp(mode: AppScreen.dictionaryTool.rawValue, extraArg: "", environment: [:])
      case .wordRegisterDialog:
        launchWordRegisterTool(sender)
      default:
        // do nothing
        break
      }
    }

    // Handle callbacks.
    if output.hasCallback && output.callback.hasSessionCommand {
      let callbackCommand = output.callback.sessionCommand
      if callbackCommand.type == .convertReverse {
        invokeReconvert(callbackCommand, client: sender)
      } else if callbackCommand.type == .undo {
        invokeUndo(sender)
      } else if let outputForCallback = genmaiClient.sendCommand(callbackCommand) {
        processOutput(outputForCallback, client: sender)
      }
    }
  }

  // MARK: - IMKServerInput Protocol

  /// Updates |composedString_| from the result of a key event and puts the updated composed string to
  /// the client application.
  public func updateComposedString(_ preedit: Genmai_Commands_Preedit?) {
    // If the last and the current composed string length is 0,
    // we don't update the composition.
    if composedString.length == 0 && (preedit == nil || preedit!.segment.isEmpty) {
      return
    }

    composedString.deleteCharacters(in: NSRange(location: 0, length: composedString.length))
    cursorPosition = -1
    if let preedit {
      cursorPosition = Int(preedit.cursor)
      for segment in preedit.segment {
        let highlightAttributes = markAttributes(Int32(kTSMHiliteSelectedConvertedText))
        let underlineAttributes = markAttributes(Int32(kTSMHiliteConvertedText))
        let attributes = segment.annotation == .highlight ? highlightAttributes : underlineAttributes
        composedString.append(NSAttributedString(string: segment.value, attributes: attributes))
      }
    }
    if composedString.length == 0 {
      originalString = ""
      replacementRange = kNotFoundRange
    }

    // Update the composed string of the client applications.
    client?.setMarkedText(
      composedString, selectionRange: selectionRange(), replacementRange: replacementRange)
  }

  public func commitComposition(_ sender: (any TextInputClient)?) {
    flushQueuedKeys()
    if composedString.length == 0 {
      return
    }
    commitText(composedString.string, client: sender)

    var command = SessionCommand()
    command.type = .submit
    _ = genmaiClient.sendCommand(command)
    clearCandidates()
    updateComposedString(nil)
  }

  /// Clears all candidate data in |candidates_|.
  public func clearCandidates() {
    rendererCommand.type = .update
    rendererCommand.visible = false
    rendererCommand.clearOutput()
    renderer?.execCommand(rendererCommand)
  }

  /// |selecrionRange| method is defined at IMKInputController class and
  /// means the position of cursor actually.
  public func selectionRange() -> NSRange {
    cursorPosition == -1
      ? selectionRangeFallback()  // default behavior defined at super class
      : NSRange(location: cursorPosition, length: 0)
  }

  func delayedUpdateCandidates() {
    guard let renderer else { return }

    // If there is no candidate, the candidate window is closed.
    if rendererCommand.output.candidateWindow.candidate.isEmpty {
      rendererCommand.visible = false
      renderer.execCommand(rendererCommand)
      return
    }

    // The candidate window position is not recalculated if the
    // candidate already appears on the screen.  Therefore, if a user
    // moves client application window by mouse, candidate window won't
    // follow the move of window.  This is done because:
    //  - some applications like Emacs or Google Chrome don't return the
    //    cursor position correctly.  The candidate window moves
    //    frequently with those application, which irritates users.
    //  - Kotoeri does this too.
    if rendererCommand.visible {
      // Call ExecCommand anyway to update other information like candidate words.
      renderer.execCommand(rendererCommand)
      return
    }

    rendererCommand.visible = true

    var preeditRect = NSRect.zero
    let position = Int(rendererCommand.output.candidateWindow.position)
    // Some applications throws error when we call attributesForCharacterIndex.
    if let client {
      var clientData: [AnyHashable: Any]?
      let exception = GenmaiTryObjC {
        clientData = client.attributes(forCharacterIndex: position, lineHeightRectangle: &preeditRect)
      }
      if let exception {
        GenmaiLog.error(
          "Exception from [\(clientBundle)] \(exception.name.rawValue),\(exception.reason ?? "")")
      } else {
        // IMKBaseline: Left-bottom of the composition.
        let baseline = (clientData?["IMKBaseline"] as? NSValue)?.pointValue ?? .zero
        // IMKTextOrientation: 0: vertical writing, 1: horizontal writing.
        // IMKLineHeight: Height of the composition (in horizontal writing).
        let rightOffset = Int32(preeditRect.size.width)
        let topOffset = Int32(-preeditRect.size.height)
        rendererCommand.preeditRectangle.left = Int32(baseline.x)
        rendererCommand.preeditRectangle.right = Int32(baseline.x) + rightOffset
        rendererCommand.preeditRectangle.top = Int32(baseline.y) + topOffset
        rendererCommand.preeditRectangle.bottom = Int32(baseline.y)
      }
    }

    renderer.execCommand(rendererCommand)
  }

  /// Updates |candidates_| from the result of a key event.
  public func updateCandidates(_ output: Output?) {
    guard let output else {
      clearCandidates()
      return
    }
    rendererCommand.type = .update
    rendererCommand.output = output

    // Runs delayedUpdateCandidates in the next event loop.
    // This is because some applications like Google Docs with Chrome returns
    // incorrect cursor position if we call attributesForCharacterIndex here.
    let task = Task { @MainActor [weak self] () -> Void in
      self?.delayedUpdateCandidates()
    }
    pendingCandidateUpdates.append(task)
  }

  /// Waits until the scheduled `delayedUpdateCandidates` calls have run (tests).
  public func waitForPendingCandidateUpdates() async {
    let tasks = pendingCandidateUpdates
    pendingCandidateUpdates.removeAll()
    for task in tasks {
      await task.value
    }
  }

  /// Opens a link specified by the URL.
  public func openLink(_ url: URL) {
    // Open a link specified by |url|.  Any opening link behavior should
    // call this method because it checks the capability of application.
    // On some application like login window of screensaver, opening
    // link behavior should not happen because it can cause some
    // security issues.
    if canOpenLink(clientBundle) {
      urlOpener(url)
    }
  }

  /// Fills the surrounding context (preceding_text). Returns false if fails to get
  /// the surrounding context from the client.
  @discardableResult
  public func fillSurroundingContext(_ context: inout Context, client: any TextInputClient) -> Bool {
    let totalLength = client.length()
    if totalLength == 0 || totalLength == NSNotFound || totalLength > kGetSurroundingTextClientLengthLimit {
      return false
    }
    let selectedRange = client.selectedRange()
    if selectedRange.location == NSNotFound || selectedRange.length == NSNotFound {
      return false
    }
    var precedingRange = NSRange(location: 0, length: selectedRange.location)
    if selectedRange.location > kMaxSurroundingLength {
      precedingRange = NSRange(
        location: selectedRange.location - kMaxSurroundingLength, length: kMaxSurroundingLength)
    }
    if let precedingString = client.attributedSubstring(from: precedingRange)?.string {
      context.precedingText = precedingString
    }
    if let aiSurroundingTextObserver {
      let length = min(selectedRange.location, kMaxAISurroundingLength)
      let range = NSRange(location: selectedRange.location - length, length: length)
      aiSurroundingTextObserver(client.attributedSubstring(from: range)?.string ?? "")
    }
    return true
  }

  /// `-handleEvent:client:`.
  public func handleEvent(_ event: KeyEventData?, client sender: (any TextInputClient)?) -> Bool {
    guard let event else { return false }
    if event.type != .keyDown && event.type != .flagsChanged {
      return false
    }

    // Handle KANA key and EISU key.  We explicitly handles this here
    // for mode switch because some text area such like iPhoto person
    // name editor does not call setValue:forTag:client: method.
    if event.type == .keyDown {
      let currentTime = now()
      let elapsedTime = currentTime - lastKeyDownTime
      let isDoubleTap = event.keyCode == lastKeyCode && elapsedTime < kDoubleTapInterval
      lastKeyDownTime = currentTime
      lastKeyCode = event.keyCode

      // these calling of switchMode: can be duplicated if the
      // application sends the setValue:forTag:client: and handleEvent:
      // at the same key event, but that's okay because switchMode:
      // method does nothing if the new mode is same as the current
      // mode.
      if Int(event.keyCode) == kVK_JIS_Kana {
        switchMode(.hiragana, client: sender)
        switchDisplayMode()
        if isDoubleTap {
          var command = SessionCommand()
          command.type = .convertReverse
          invokeReconvert(command, client: sender)
        }
      } else if Int(event.keyCode) == kVK_JIS_Eisu {
        if isDoubleTap {
          var command = SessionCommand()
          command.type = .commitRawText
          sendCommand(command)
        }
        let newMode: CompositionMode = composedString.length == 0 ? .direct : .halfAscii
        switchMode(newMode, client: sender)
        switchDisplayMode()
      }
    }

    if keyCodeMap.isModeSwitchingKey(event) {
      // Special hack for Eisu/Kana keys.  Sometimes those key events
      // come to this method but we should ignore them because some
      // applications like PhotoShop is stuck.
      return true
    }

    // Get the Mozc key event
    guard var keyEvent = keyCodeMap.getGenmaiKeyEvent(event) else {
      // Modifier flags change (not submitted to the server yet), or
      // unsupported key pressed.
      return false
    }

    // If the key event is turn on event, the key event has to be sent
    // to the server anyway.
    if mode == .direct && !genmaiClient.isDirectModeCommand(keyEvent) {
      // Yen sign special hack: although the current mode is DIRECT,
      // backslash is sent instead of yen sign for JIS yen key with no
      // modifiers.  This behavior is based on the configuration.
      if Int(event.keyCode) == kVK_JIS_Yen && event.modifierFlags.isEmpty
        && yenSignCharacter == .backslash
      {
        commitText("\\", client: sender)
        return true
      }
      return false
    }

    // Send the key event to the server actually
    if keyEvent.hasKeyCode && isPrint(keyEvent.keyCode), let scalar = UnicodeScalar(keyEvent.keyCode) {
      originalString.unicodeScalars.append(scalar)
    }

    var context = Context()
    if suppressSuggestion {
      // TODO(komatsu, horo): Support Google Omnibox too.
      context.experimentalFeatures.append("google_search_box")
    }
    keyEvent.mode = mode

    if composedString.length == 0 && canSelectedRange(clientBundle) && canSurroundingText(clientBundle),
      let sender
    {
      fillSurroundingContext(&context, client: sender)
    }
    if !queuedKeys.isEmpty {
      queuedKeys.append(QueuedKey(key: keyEvent, context: context, sender: sender))
      return true
    }
    if let wait = aiConversionGate?(keyEvent) {
      queuedKeys.append(QueuedKey(key: keyEvent, context: context, sender: sender))
      let generation = queueGeneration
      Task { [weak self] in
        await wait.value
        self?.drainQueuedKeys(generation, waited: true)
      }
      return true
    }
    guard let output = genmaiClient.sendKey(keyEvent, context: context) else {
      return false
    }

    processOutput(output, client: sender)
    scheduleAISuggestionRefresh(output, client: sender)
    return output.consumed
  }

  // MARK: - AI suggestion refresh (not in Mozc)

  /// A composition with Mozc's suggestion window (desktop suggestion, cursor at the end, no temporary input mode:
  /// MOVE_CURSOR to the end then changes nothing but the suggestion).
  static func canRefreshSuggestion(_ output: Output) -> Bool {
    guard output.consumed, !output.hasResult, output.hasPreedit, !output.preedit.segment.isEmpty,
      output.hasCandidateWindow, output.candidateWindow.category == .suggestion,
      !output.candidateWindow.candidate.isEmpty, output.status.mode == output.status.comebackMode
    else {
      return false
    }
    let length = output.preedit.segment.reduce(0) { $0 + $1.value.unicodeScalars.count }
    return Int(output.preedit.cursor) == length
  }

  private func scheduleAISuggestionRefresh(_ output: Output, client sender: (any TextInputClient)?) {
    guard let aiSuggestionUpdate, Self.canRefreshSuggestion(output), let update = aiSuggestionUpdate() else {
      return
    }
    let generation = outputGeneration
    let preedit = output.preedit
    pendingSuggestionRefresh = Task { [weak self] in
      guard await update.value else { return }
      self?.refreshAISuggestion(generation, preedit: preedit, client: sender)
    }
  }

  private func refreshAISuggestion(
    _ generation: Int, preedit: Genmai_Commands_Preedit, client sender: (any TextInputClient)?
  ) {
    // Stale: another output since (keys, commands, conversion), keys waiting for the AI, the window replaced.
    guard generation == outputGeneration, queuedKeys.isEmpty, rendererCommand.output.preedit == preedit,
      Self.canRefreshSuggestion(rendererCommand.output)
    else {
      return
    }
    var command = SessionCommand()
    command.type = .moveCursor
    command.cursorPosition = preedit.cursor
    guard let output = genmaiClient.sendCommand(command) else { return }
    guard output.consumed, !output.hasResult, output.preedit == preedit else {
      // Not expected (the composition is unchanged): show whatever Mozc answered.
      processOutput(output, client: sender)
      return
    }
    outputGeneration += 1
    if output.candidateWindow != rendererCommand.output.candidateWindow {
      updateCandidates(output)
    }
    // The exact (refined) conversion may still replace the fast one after a typing pause.
    scheduleAISuggestionRefresh(output, client: sender)
  }

  /// Waits for the scheduled AI suggestion refreshes (tests).
  public func waitForAISuggestionRefresh() async {
    while let task = pendingSuggestionRefresh {
      pendingSuggestionRefresh = nil
      await task.value
    }
  }

  /// Sends the queued keys in order after the AI wait of the first one; stops at a later key that needs its
  /// own wait (e.g. more kana and SPACE typed during the wait).
  private func drainQueuedKeys(_ generation: Int, waited: Bool) {
    guard generation == queueGeneration else { return }  // flushed meanwhile
    var skipGate = waited
    while let next = queuedKeys.first {
      if !skipGate, let wait = aiConversionGate?(next.key) {
        Task { [weak self] in
          await wait.value
          self?.drainQueuedKeys(generation, waited: true)
        }
        return
      }
      skipGate = false
      queuedKeys.removeFirst()
      sendQueued(next)
    }
  }

  /// Sends all queued keys now, without waiting (before any other request to the converter).
  public func flushQueuedKeys() {
    guard !queuedKeys.isEmpty else { return }
    queueGeneration += 1
    let keys = queuedKeys
    queuedKeys = []
    keys.forEach(sendQueued)
  }

  /// A queued key that Mozc does not consume cannot be passed back to the application any more; during a
  /// composition (the only time keys are queued) Mozc consumes practically every key.
  private func sendQueued(_ queued: QueuedKey) {
    guard let output = genmaiClient.sendKey(queued.key, context: queued.context) else { return }
    processOutput(output, client: queued.sender)
    scheduleAISuggestionRefresh(output, client: queued.sender)
  }

  /// `-handleEvent:` for NSEventTypeCursorUpdate: re-sends the marked text.
  public func handleCursorUpdate() {
    client?.setMarkedText(
      composedString, selectionRange: selectionRange(), replacementRange: replacementRange)
  }

  // MARK: - ControllerCallback

  public func sendCommand(_ command: SessionCommand) {
    flushQueuedKeys()
    guard let output = genmaiClient.sendCommand(command) else {
      return
    }
    processOutput(output, client: client)
  }

  public func outputResult(_ output: Output) {
    if !output.hasResult {
      return
    }
    commitText(output.result.value, client: client)
  }

  // MARK: - callbacks (menu items)

  /// "Reconversion" menu item.
  public func reconversionClicked() {
    var command = SessionCommand()
    command.type = .convertReverse
    invokeReconvert(command, client: client)
  }

  /// "Configure Mozc..." menu item.
  public func configClicked() {
    toolLauncher?.openApp(mode: AppScreen.configDialog.rawValue, extraArg: "", environment: [:])
  }

  /// "Dictionary Tool..." menu item.
  public func dictionaryToolClicked() {
    toolLauncher?.openApp(mode: AppScreen.dictionaryTool.rawValue, extraArg: "", environment: [:])
  }

  /// "Add a word..." menu item.
  public func registerWordClicked() {
    launchWordRegisterTool(client)
  }

  /// "About Mozc..." menu item.
  public func aboutDialogClicked() {
    toolLauncher?.openApp(mode: AppScreen.aboutDialog.rawValue, extraArg: "", environment: [:])
  }
}
