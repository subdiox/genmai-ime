// Port of mozc/src/gui/tool/mozc_tool_libmain.cc, the *_libmain.cc of each dialog and
// gui/base/singleton_window_helper (3.35.6354).
//
// GenmaiApp (installed as Genmai.app in Genmai.app/Contents/Resources) hosts the SwiftUI dialogs of GenmaiGUI
// (and the update and welcome windows, not in Mozc). The mode comes from `--mode=<mode>` (or the FLAGS_mode
// environment variable, like the C++ on macOS), the error type of the error dialog from `--error_type=` /
// FLAGS_error_type, and the word register defaults from the environment variables set by the IME. Only one window
// per mode and desktop runs at a time: a second instance asks the first one to come to the front and exits
// (SingletonWindowHelper).
//
// Unlike Mozc's Qt tool it is a SwiftUI app: the mode's window is a `Window` scene, so the windows get the system's
// own chrome (Liquid Glass sidebar and toolbar on macOS 26). Closing the window quits the app.

import AppKit
import GenmaiBase
import GenmaiClient
import GenmaiGUI
import SwiftUI

/// Mirrors kWordRegisterEnvironmentReadingName (base/const.h).
let kWordRegisterEnvironmentReadingName = "default_reading_entry_of_word_register"
let kActivateNotificationName = Notification.Name("io.github.subdiox.genmai.inputmethod.Japanese.ActivateApp")

struct AppOptions {
  var mode = AppScreen.aboutDialog.rawValue  // ABSL_FLAG(std::string, mode, "about_dialog", ...)
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

@main
struct GenmaiApplication: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  private let mode: AppScreen
  private let options: AppOptions

  init() {
    let options = AppOptions(arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment)
    if options.mode != "administration_dialog" && !RunLevel.isValidClientRunLevel() {
      exit(-1)
    }
    guard let mode = AppScreen(rawValue: options.mode) else {
      NSLog("GenmaiApp: Unknown mode: %@", options.mode)
      exit(0)
    }
    if mode == .welcome {
      // Once per user: the installer opens it after every installation, updates included.
      if GenmaiWelcome.wasShown() {
        exit(0)
      }
      GenmaiWelcome.markShown()
    }
    if mode == .errorMessageDialog && ErrorMessageDialog.message(forErrorType: options.errorType) == nil {
      exit(0)  // Show() does nothing for an unknown error type
    }
    if !AppSingleton.acquire(mode) {
      exit(0)
    }
    self.mode = mode
    self.options = options
  }

  var body: some Scene {
    // One id per mode: SwiftUI remembers the frame per id.
    Window(AppWindowContent.title(mode), id: mode.rawValue) {
      AppWindowContent(mode: mode, options: options)
    }
    .windowResizability(mode.isResizable ? .contentMinSize : .contentSize)
    .defaultSize(mode.defaultSize)
    .windowLevel(mode == .errorMessageDialog ? .floating : .automatic)  // Qt::WindowStaysOnTopHint
    .defaultPosition(.center)
  }
}

extension AppScreen {
  /// Windows without a visible title bar (the content has its own heading).
  var isCompact: Bool { self == .aboutDialog || self == .welcome }
  var isResizable: Bool { self == .configDialog || self == .dictionaryTool }
  /// The first size of the resizable windows (the others fit their content).
  var defaultSize: CGSize {
    switch self {
    case .configDialog: ConfigDialogView.idealSize
    case .dictionaryTool: CGSize(width: 860, height: 560)
    default: CGSize(width: 400, height: 300)
    }
  }
}

/// The window's content for the mode, with the close action of the dialogs.
struct AppWindowContent: View {
  let mode: AppScreen
  let options: AppOptions
  @Environment(\.dismissWindow) private var dismissWindow

  var body: some View {
    if mode.isCompact {
      // No title bar: the content has its own heading.
      dialog
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    } else {
      dialog
    }
  }

  private var dialog: some View {
    content
      .environment(\.closeDialog, CloseDialogAction { dismissWindow(id: mode.rawValue) })
  }

  @ViewBuilder private var content: some View {
    let openApp: @MainActor (String) -> Void = { GenmaiAppLauncher.launch(mode: $0) }
    switch mode {
    case .configDialog:
      ConfigDialogView(client: AppClient.shared, openApp: openApp)
    case .dictionaryTool:
      DictionaryToolView(client: AppClient.shared)
    case .wordRegisterDialog:
      let environment = ProcessInfo.processInfo.environment
      WordRegisterDialogView(
        client: AppClient.shared,
        initialWord: environment[kWordRegisterEnvironmentName].flatMap { $0.isEmpty ? nil : $0 },
        initialReading: environment[kWordRegisterEnvironmentReadingName].flatMap { $0.isEmpty ? nil : $0 },
        launchDictionaryTool: { openApp(AppScreen.dictionaryTool.rawValue) })
    case .aboutDialog:
      AboutDialogView()
    case .errorMessageDialog:
      ErrorMessageDialogView(message: ErrorMessageDialog.message(forErrorType: options.errorType) ?? "")
    case .updateDialog:
      UpdateDialogView()
    case .welcome:
      WelcomeView(client: AppClient.shared) { openApp(AppScreen.configDialog.rawValue) }
    }
  }

  static func title(_ mode: AppScreen) -> String {
    switch mode {
    case .configDialog: tr("Settings", "[ProductName] Settings")
    case .dictionaryTool: tr("DictionaryTool", "[ProductName] Dictionary Tool")
    case .wordRegisterDialog: tr("WordRegisterDialog", "[ProductName] Word Register Dialog")
    case .aboutDialog: tr("About", "About [ProductName]")
    case .errorMessageDialog: ErrorMessageDialog.title()
    case .updateDialog: UpdateStrings.text(.dialogTitle)
    case .welcome: WelcomeStrings.text(.windowTitle)
    }
  }
}

/// The client of the conversion server the dialogs talk to (one per process).
@MainActor
enum AppClient {
  static let shared = AppSessionBackend.makeClient()
}

/// SingletonWindowHelper: one window per "<mode>.<desktop name>".
@MainActor
enum AppSingleton {
  /// Held for the lifetime of the process.
  private static var mutex: ProcessMutex?

  /// False if another instance shows this mode already (it is asked to come to the front).
  static func acquire(_ mode: AppScreen) -> Bool {
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
    ) { _ in
      MainActor.assumeIsolated {
        NSApp.activate()
        NSApp.windows.first { $0.isVisible }?.makeKeyAndOrderFront(nil)
      }
    }
    return true
  }

  static func release() {
    _ = mutex?.unlock()
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.activate()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

  func applicationWillTerminate(_ notification: Notification) {
    MainActor.assumeIsolated { AppSingleton.release() }
  }
}

/// Launches another GenmaiApp mode from inside the app (e.g. "Edit user dictionary..." in the config dialog).
@MainActor
enum GenmaiAppLauncher {
  static func launch(mode: String) {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = ["--mode=\(mode)"]
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) {
      _, error in
      if let error {
        NSLog("GenmaiApp: failed to launch %@: %@", mode, error.localizedDescription)
      }
    }
  }
}
