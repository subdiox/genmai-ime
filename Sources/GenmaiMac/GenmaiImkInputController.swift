// Port of mozc/src/mac/mozc_imk_input_controller.{h,mm} (3.35.6354), the InputMethodKit part.
//
// GenmaiImkInputController is a subclass of IMKInputController, which holds a connection from a client
// application to the converter. All logic lives in `GenmaiInputController`; this class adapts the IMK calls.
// It is exported to Objective-C under the same class name as the C++ (Info.plist:
// InputMethodServerControllerClass = GenmaiImkInputController).
//
// InputMethodKit always calls the controller on the main thread, so the overrides assume main-actor
// isolation.

import AppKit
import GenmaiBase
import GenmaiClient
import GenmaiCore
import GenmaiProtocol
import GenmaiRenderer
@preconcurrency import InputMethodKit

/// Wraps the IMKTextInput proxy object that IMK passes as `sender` / returns from `client()`.
@MainActor
final class IMKTextInputClient: TextInputClient {
  let client: any IMKTextInput & NSObjectProtocol

  init?(_ object: Any?) {
    guard let client = object as? (any IMKTextInput & NSObjectProtocol) else { return nil }
    self.client = client
  }

  func bundleIdentifier() -> String? { client.bundleIdentifier() }

  func insertText(_ text: String, replacementRange: NSRange) {
    client.insertText(text, replacementRange: replacementRange)
  }

  func setMarkedText(_ text: NSAttributedString, selectionRange: NSRange, replacementRange: NSRange) {
    client.setMarkedText(text, selectionRange: selectionRange, replacementRange: replacementRange)
  }

  func selectedRange() -> NSRange { client.selectedRange() }
  func markedRange() -> NSRange { client.markedRange() }
  func length() -> Int { client.length() }

  func attributedSubstring(from range: NSRange) -> NSAttributedString? {
    client.attributedSubstring(from: range)
  }

  func selectInputMode(_ modeIdentifier: String) { client.selectMode(modeIdentifier) }

  func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String) {
    client.overrideKeyboard(withKeyboardNamed: keyboardUniqueName)
  }

  func attributes(forCharacterIndex index: Int, lineHeightRectangle: inout NSRect) -> [AnyHashable: Any]? {
    var rect = NSRect.zero
    let result = withUnsafeMutablePointer(to: &rect) { pointer in
      client.attributes(forCharacterIndex: index, lineHeightRectangle: pointer)
    }
    lineHeightRectangle = rect
    return result
  }
}

/// Process-wide objects shared by all controllers (gRendererReceiver, the renderer, the app launcher,
/// and the in-process conversion server).
///
/// The C++ IME talks to one mozc_server process; here one `SessionHandlerBackend` (Engine + SessionHandler)
/// lives on the main actor and every controller gets an `InProcessClient` with its own session on it.
@MainActor
public final class GenmaiIMEEnvironment {
  public static let shared = GenmaiIMEEnvironment()

  /// The conversion server. Created on first use (`start()` creates it at launch).
  public private(set) lazy var backend: any SessionBackend = backendFactory()

  /// Creates the server; replaceable before first use (tests / UI previews can install FakeSessionBackend).
  /// GenmaiIME installs one with the AI conversion hook (`SessionHandlerBackend(aiHook:)`).
  public var backendFactory: @MainActor () -> any SessionBackend = { SessionHandlerBackend() }

  /// The AI conversion hook of the backend, if any (not in Mozc).
  public var aiHook: AIConversionHook? { (backend as? SessionHandlerBackend)?.aiHook }

  /// Creates the converter client of a new controller.
  public lazy var clientFactory: @MainActor (any AppLauncher) -> any GenmaiClientProtocol = { [unowned self] launcher in
    InProcessClient.make(backend: self.backend, toolLauncher: launcher)
  }

  public let rendererReceiver = RendererReceiver()
  public let toolLauncher = MacAppLauncher()
  public private(set) lazy var renderer: CandidateController = {
    let controller = CandidateController()
    controller.setSendCommandInterface(rendererReceiver)
    return controller
  }()

  private var clients: [WeakClient] = []
  private var observers: [any NSObjectProtocol] = []
  private var errorDialogShown = false
  private var lastSyncTime: ContinuousClock.Instant?

  /// Minimum interval between two SYNC_DATA sent on deactivation (the watch dog's CLEANUP syncs anyway).
  static let kDeactivateSyncInterval: Duration = .seconds(10)

  private struct WeakClient {
    weak var client: (any GenmaiClientProtocol)?
  }

  private init() {}

  /// Loads the engine, starts the watch dog, observes GenmaiApp notifications and defers the application's
  /// termination until the learning data is written (`applicationDelegate`).
  public func start() {
    if let server = backend as? SessionHandlerBackend {
      if let aiHook = server.aiHook {
        NSLog("Genmai: AI conversion %@", aiHook.isEnabled ? "enabled" : "disabled")
      }
      if server.isAvailable {
        NSLog("Genmai: conversion engine loaded in %@ (data %@)", "\(server.engineLoadTime)", server.dataVersion)
        server.startWatchDog()
      } else {
        NSLog("Genmai: conversion engine is not available: %@", "\(server.loadError.map { "\($0)" } ?? "unknown")")
      }
    }
    startObservingToolNotifications()
    if NSApplication.shared.delegate == nil {
      NSApplication.shared.delegate = applicationDelegate
    }
  }

  /// The application delegate installed by `start()` (NSApplication holds its delegate weakly).
  public let applicationDelegate = GenmaiApplicationDelegate()

  func makeClient() -> any GenmaiClientProtocol {
    let client = clientFactory(toolLauncher)
    clients.removeAll { $0.client == nil }
    clients.append(WeakClient(client: client))
    if let server = backend as? SessionHandlerBackend, !server.isAvailable, !errorDialogShown {
      // The data set failed to load: keys pass through to the application. Tell the user once.
      errorDialogShown = true
      toolLauncher.launchErrorMessageDialog("server_fatal")
    }
    return client
  }

  /// SYNC_DATA on deactivation (throttled). Returns at once: the learning data is written in the background.
  public func syncData(force: Bool = false) {
    guard let server = backend as? SessionHandlerBackend, server.isAvailable else { return }
    let now = ContinuousClock.now
    if !force, let lastSyncTime, now - lastSyncTime < Self.kDeactivateSyncInterval {
      return
    }
    lastSyncTime = now
    Task { await server.syncData() }
  }

  /// SYNC_DATA before termination: suspends until the learning data is written.
  public func syncDataAndWait() async {
    guard let server = backend as? SessionHandlerBackend, server.isAvailable else { return }
    lastSyncTime = ContinuousClock.now
    await server.syncData()
  }

  /// Observes the reload requests from GenmaiApp (config / user dictionary changes).
  public func startObservingToolNotifications() {
    guard observers.isEmpty else { return }
    let observer = DistributedNotificationCenter.default().addObserver(
      forName: kReloadNotificationName, object: nil, queue: .main
    ) { notification in
      let command = notification.object as? String ?? "reload"
      MainActor.assumeIsolated {
        GenmaiIMEEnvironment.shared.handleToolNotification(command)
      }
    }
    observers.append(observer)
  }

  func handleToolNotification(_ command: String) {
    if let server = backend as? SessionHandlerBackend {
      switch command {
      case "clear_user_history": server.clearUserHistory()
      case "clear_user_prediction": server.clearUserPrediction()
      default: server.reload()
      }
    } else {
      // Another backend (tests): route the command through one client.
      guard let client = clients.lazy.compactMap(\.client).first else { return }
      switch command {
      case "clear_user_history": client.clearUserHistory()
      case "clear_user_prediction": client.clearUserPrediction()
      default: client.reload()
      }
    }
    if command == "reload" {
      // The keymap may have changed: refresh the direct mode keys of every client.
      let config = ConfigHandler.getCopiedConfig()
      for entry in clients {
        (entry.client as? InProcessClient)?.updateDirectModeKeys(config)
      }
    }
  }
}

/// Not in Mozc (mozc_server syncs on SHUTDOWN): the in-process server must finish writing the learning data
/// before the process exits, and the write is asynchronous, so termination is deferred until it is done
/// (`.terminateLater`) instead of blocking the main thread.
@MainActor
public final class GenmaiApplicationDelegate: NSObject, NSApplicationDelegate {
  public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Task {
      await GenmaiIMEEnvironment.shared.syncDataAndWait()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}

@objc(GenmaiImkInputController)
@MainActor
open class GenmaiImkInputController: IMKInputController {
  /// The logic.
  private var core: GenmaiInputController!
  private var imkMenu: NSMenu?

  public nonisolated override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
    super.init(server: server, delegate: delegate, client: inputClient)
    onMain(inputClient) { this, inputClient in this.setUp(inputClient) }
  }

  private func setUp(_ inputClient: Any?) {
    let environment = GenmaiIMEEnvironment.shared
    core = GenmaiInputController(
      genmaiClient: environment.makeClient(),
      renderer: environment.renderer,
      currentClient: { [weak self] in IMKTextInputClient(self?.client()) },
      toolLauncher: environment.toolLauncher,
      markAttributes: { [weak self] style in
        let attributes = self?.mark(forStyle: Int(style), at: NSRange(location: NSNotFound, length: 0))
        return (attributes as? [NSAttributedString.Key: Any])
          ?? GenmaiInputController.defaultMarkAttributes(style)
      },
      selectionRangeFallback: { [weak self] in
        guard let self else { return NSRange(location: NSNotFound, length: 0) }
        return self.superSelectionRange()
      })
    if let aiHook = environment.aiHook {
      core.aiSurroundingTextObserver = { [weak aiHook] text in aiHook?.noteSurroundingText(text) }
      core.aiConversionGate = { [weak aiHook] key in aiHook?.conversionWait(for: key) }
      core.aiSuggestionUpdate = { [weak aiHook] in aiHook?.suggestionUpdate() }
    }
    // The C++ also sets up the client bundle from |inputClient| at init.
    core.setupClientBundle(IMKTextInputClient(inputClient))
    core.setupCapability()
    imkMenu = makeMenu()
  }

  private func superSelectionRange() -> NSRange { super.selectionRange() }

  /// Runs `body` on the main actor; InputMethodKit calls the controller on the main thread.
  private nonisolated func onMain<T>(
    _ sender: Any?, _ body: @MainActor (GenmaiImkInputController, Any?) -> T
  ) -> T {
    nonisolated(unsafe) let sender = sender
    nonisolated(unsafe) let this = self
    return MainActor.assumeIsolated { UncheckedBox(value: body(this, sender)) }.value
  }

  // MARK: IMKStateSetting Protocol

  open nonisolated override func activateServer(_ sender: Any!) {
    super.activateServer(sender)
    onMain(sender) { this, sender in
      this.core.activateServer(IMKTextInputClient(sender))
      // Sets this controller as the active controller to receive messages from the renderer.
      GenmaiIMEEnvironment.shared.rendererReceiver.setCurrentController(this.core)
    }
  }

  open nonisolated override func deactivateServer(_ sender: Any!) {
    onMain(sender) { this, sender in
      this.core.deactivateServer(IMKTextInputClient(sender))
      // mozc_server syncs the learning data periodically; the in-process server also syncs when the user
      // leaves the application.
      GenmaiIMEEnvironment.shared.syncData()
    }
    super.deactivateServer(sender)
  }

  open nonisolated override func recognizedEvents(_ sender: Any!) -> Int {
    Int(GenmaiInputController.recognizedEvents.rawValue)
  }

  /// This method is called when a user changes the input mode.
  open nonisolated override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
    nonisolated(unsafe) let value = value
    onMain(sender) { this, sender in this.core.setValue(value, client: IMKTextInputClient(sender)) }
    super.setValue(value, forTag: tag, client: sender)
  }

  open nonisolated override func menu() -> NSMenu! {
    onMain(nil) { this, _ in this.imkMenu }
  }

  // MARK: IMKServerInput Protocol
  // Currently GenmaiImkInputController uses handleEvent:client: method to handle key events.

  open nonisolated override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
    guard let event else { return false }
    let isCursorUpdate = event.type == .cursorUpdate
    // Copy what KeyCodeMap needs (NSEvent is not Sendable).
    let data = isCursorUpdate ? nil : KeyEventData(event)
    return onMain(sender) { this, sender in
      if isCursorUpdate {
        this.core.handleCursorUpdate()
        return false
      }
      return this.core.handleEvent(data, client: IMKTextInputClient(sender))
    }
  }

  open nonisolated override func originalString(_ sender: Any!) -> NSAttributedString! {
    onMain(sender) { this, _ in NSAttributedString(string: this.core.originalString) }
  }

  open nonisolated override func composedString(_ sender: Any!) -> Any! {
    onMain(sender) { this, _ in this.core.composedString }
  }

  open nonisolated override func commitComposition(_ sender: Any!) {
    onMain(sender) { this, sender in this.core.commitComposition(IMKTextInputClient(sender)) }
  }

  open nonisolated override func selectionRange() -> NSRange {
    onMain(nil) { this, _ in this.core.selectionRange() }
  }

  // MARK: callbacks (menu items of mac/*.lproj/Config.xib)

  @objc open func reconversionClicked(_ sender: Any?) { core.reconversionClicked() }
  @objc open func configClicked(_ sender: Any?) { core.configClicked() }
  @objc open func dictionaryToolClicked(_ sender: Any?) { core.dictionaryToolClicked() }
  @objc open func registerWordClicked(_ sender: Any?) { core.registerWordClicked() }
  @objc open func aboutDialogClicked(_ sender: Any?) { core.aboutDialogClicked() }

  private func makeMenu() -> NSMenu {
    let menu = NSMenu(title: kProductNameInMenu)
    let items: [(MenuString, Selector)] = [
      (.reconversion, #selector(reconversionClicked(_:))),
      (.preferences, #selector(configClicked(_:))),
      (.addWord, #selector(registerWordClicked(_:))),
      (.dictionaryTool, #selector(dictionaryToolClicked(_:))),
      (.about, #selector(aboutDialogClicked(_:))),
    ]
    for (title, action) in items {
      let item = NSMenuItem(title: title.localized, action: action, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    return menu
  }
}

private struct UncheckedBox<T>: @unchecked Sendable {
  let value: T
}

let kProductNameInMenu = "Genmai"

/// The menu titles of mac/English.lproj/Config.xib and mac/Japanese.lproj/Config.xib.
enum MenuString: CaseIterable {
  case reconversion
  case preferences
  case addWord
  case dictionaryTool
  case about

  var english: String {
    switch self {
    case .reconversion: "Reconversion"
    case .preferences: "Preferences..."
    case .addWord: "Add a word"
    case .dictionaryTool: "Dictionary Tool..."
    case .about: "About Genmai"
    }
  }

  var japanese: String {
    switch self {
    case .reconversion: "再変換"
    case .preferences: "環境設定..."
    case .addWord: "単語登録..."
    case .dictionaryTool: "辞書ツール..."
    case .about: "Genmaiについて"
    }
  }

  var localized: String {
    (Locale.preferredLanguages.first ?? "en").hasPrefix("ja") ? japanese : english
  }
}
