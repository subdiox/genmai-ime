// Port of mozc/src/gui/tool/mozc_tool_libmain.cc, the *_libmain.cc of each dialog and
// gui/base/singleton_window_helper (3.35.6354).
//
// GenmaiTool.app hosts the SwiftUI dialogs of GenmaiGUI. The mode comes from `--mode=<mode>` (or the
// FLAGS_mode environment variable, like the C++ on macOS), the error type of the error dialog from
// `--error_type=` / FLAGS_error_type, and the word register defaults from the environment variables set by
// the IME. Only one window per mode and desktop runs at a time: a second instance asks the first one to come
// to the front and exits (SingletonWindowHelper).

import AppKit
import GenmaiBase
import GenmaiClient
import GenmaiGUI
import SwiftUI

/// Mirrors kWordRegisterEnvironmentReadingName (base/const.h).
let kWordRegisterEnvironmentReadingName = "default_reading_entry_of_word_register"
let kActivateNotificationName = Notification.Name("io.github.subdiox.genmai.inputmethod.Japanese.ActivateTool")

struct ToolOptions {
  var mode = ToolMode.aboutDialog.rawValue  // ABSL_FLAG(std::string, mode, "about_dialog", ...)
  var errorType = ""

  init(arguments: [String], environment: [String: String]) {
    // OSX's app won't accept command line flags.  Here we preset flags from
    // environment variables.
    if let mode = environment["FLAGS_mode"], !mode.isEmpty {
      self.mode = mode
    }
    if let errorType = environment["FLAGS_error_type"], !errorType.isEmpty {
      self.errorType = errorType
    }
    for argument in arguments.dropFirst() {
      if let value = argument.value(ofFlag: "mode") {
        mode = value
      } else if let value = argument.value(ofFlag: "error_type") {
        errorType = value
      }
    }
  }
}

extension String {
  fileprivate func value(ofFlag name: String) -> String? {
    for prefix in ["--\(name)=", "-\(name)="] where hasPrefix(prefix) {
      return String(dropFirst(prefix.count))
    }
    return nil
  }
}

@MainActor
final class ToolAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  let options: ToolOptions
  private var window: NSWindow?
  private var mutex: ProcessMutex?
  private let client = ToolSessionBackend.makeClient()

  init(options: ToolOptions) {
    self.options = options
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard let mode = ToolMode(rawValue: options.mode) else {
      NSLog("GenmaiTool: Unknown mode: %@", options.mode)
      NSApp.terminate(nil)
      return
    }
    if !acquireSingleton(mode) {
      NSApp.terminate(nil)
      return
    }
    guard let rootView = makeRootView(mode) else {
      NSApp.terminate(nil)
      return
    }
    let hosting = NSHostingController(rootView: rootView)
    hosting.sizingOptions = [.preferredContentSize]
    let window = NSWindow(contentViewController: hosting)
    window.styleMask = mode == .configDialog || mode == .dictionaryTool
      ? [.titled, .closable, .miniaturizable, .resizable] : [.titled, .closable]
    window.title = windowTitle(mode)
    window.delegate = self
    if mode == .errorMessageDialog {
      window.level = .floating  // Qt::WindowStaysOnTopHint
    }
    window.center()
    self.window = window
    window.makeKeyAndOrderFront(nil)
    NSApp.activate()
  }

  private func makeRootView(_ mode: ToolMode) -> AnyView? {
    let close = CloseDialogAction { [weak self] in self?.window?.performClose(nil) }
    let launchTool: @MainActor (String) -> Void = { mode in
      GenmaiToolLauncher.launch(mode: mode)
    }
    let view: AnyView
    switch mode {
    case .configDialog:
      view = AnyView(ConfigDialogView(client: client, launchTool: launchTool))
    case .dictionaryTool:
      view = AnyView(DictionaryToolView(client: client))
    case .wordRegisterDialog:
      let environment = ProcessInfo.processInfo.environment
      view = AnyView(
        WordRegisterDialogView(
          client: client,
          initialWord: environment[kWordRegisterEnvironmentName].flatMap { $0.isEmpty ? nil : $0 },
          initialReading: environment[kWordRegisterEnvironmentReadingName].flatMap {
            $0.isEmpty ? nil : $0
          },
          launchDictionaryTool: { launchTool(ToolMode.dictionaryTool.rawValue) }))
    case .aboutDialog:
      view = AnyView(AboutDialogView())
    case .errorMessageDialog:
      guard let message = ErrorMessageDialog.message(forErrorType: options.errorType) else {
        return nil
      }
      view = AnyView(ErrorMessageDialogView(message: message))
    }
    return AnyView(view.environment(\.closeDialog, close))
  }

  private func windowTitle(_ mode: ToolMode) -> String {
    switch mode {
    case .configDialog: tr("ConfigDialog", "[ProductName] Settings")
    case .dictionaryTool: tr("DictionaryTool", "[ProductName] Dictionary Tool")
    case .wordRegisterDialog: tr("WordRegisterDialog", "[ProductName] Word Register Dialog")
    case .aboutDialog: tr("AboutDialog", "About [ProductName]")
    case .errorMessageDialog: ErrorMessageDialog.title()
    }
  }

  /// SingletonWindowHelper: one window per "<mode>.<desktop name>".
  private func acquireSingleton(_ mode: ToolMode) -> Bool {
    if mode == .errorMessageDialog {
      return true
    }
    let name = "\(mode.rawValue).\(SystemUtil.getDesktopNameAsString())"
    let mutex = ProcessMutex(name)
    if !mutex.lockAndWrite(String(ProcessInfo.processInfo.processIdentifier)) {
      // already running: ActivatePreviousWindow
      DistributedNotificationCenter.default().postNotificationName(
        kActivateNotificationName, object: name, userInfo: nil, deliverImmediately: true)
      return false
    }
    self.mutex = mutex
    DistributedNotificationCenter.default().addObserver(
      forName: kActivateNotificationName, object: name, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        NSApp.activate()
        self?.window?.makeKeyAndOrderFront(nil)
      }
    }
    return true
  }

  func windowWillClose(_ notification: Notification) {
    // Let SwiftUI run onDisappear (the dictionary tool saves there), then quit.
    window?.contentViewController = nil
    Task { @MainActor in
      _ = mutex?.unlock()
      NSApp.terminate(nil)
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Launches another GenmaiTool mode from inside the tool (e.g. "Edit user dictionary..." in the config dialog).
@MainActor
enum GenmaiToolLauncher {
  static func launch(mode: String) {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = ["--mode=\(mode)"]
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) {
      _, error in
      if let error {
        NSLog("GenmaiTool: failed to launch %@: %@", mode, error.localizedDescription)
      }
    }
  }
}

@main
@MainActor
enum GenmaiToolMain {
  static func main() {
    let options = ToolOptions(
      arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment)
    if options.mode != "administration_dialog" && !RunLevel.isValidClientRunLevel() {
      exit(-1)
    }
    let app = NSApplication.shared
    let delegate = ToolAppDelegate(options: options)
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.mainMenu = makeMainMenu()
    app.run()
  }

  /// A minimal menu so that Cmd+Q / Cmd+W / copy & paste work in the dialogs.
  static func makeMainMenu() -> NSMenu {
    let mainMenu = NSMenu()
    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(
      withTitle: "Quit \(kProductNameInEnglish)", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    appItem.submenu = appMenu
    mainMenu.addItem(appItem)

    let editItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(
      withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = editMenu
    mainMenu.addItem(editItem)

    let windowItem = NSMenuItem()
    let windowMenu = NSMenu(title: "Window")
    windowMenu.addItem(
      withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    windowItem.submenu = windowMenu
    mainMenu.addItem(windowItem)
    return mainMenu
  }
}
