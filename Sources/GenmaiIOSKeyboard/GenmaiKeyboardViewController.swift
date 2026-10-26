// The keyboard extension's principal class (not in Mozc). It owns the engine and the `KeyboardController`, hosts
// the SwiftUI `KeyboardView` and forwards the text field's events. The extension target in iOS/ only names this
// class in its Info.plist (NSExtensionPrincipalClass = GenmaiKeyboard.KeyboardViewController).

#if os(iOS)
  import GenmaiAIClient
  import GenmaiBase
  import GenmaiClient
  import GenmaiCore
  import GenmaiIOS
  import SwiftUI
  import UIKit

  open class GenmaiKeyboardViewController: UIInputViewController {
    private let state = KeyboardHostState()
    private var controller: KeyboardController?
    private var document: TextDocumentProxyAdapter?
    private var heightConstraint: NSLayoutConstraint?

    override open func viewDidLoad() {
      super.viewDidLoad()
      SharedContainer.useSharedProfile()
      // AI conversion (off by default; the Genmai app downloads the model into the shared profile and turns it on),
      // the same hook and Core ML decoder as on macOS
      let aiHook = AIConversionHook.makeGenmai(settings: AIConversionSettings.load())
      let controller = KeyboardController(
        engine: IosEngine(dataFilePath: OssDataManager.defaultDataPath, aiHook: aiHook))
      let document = TextDocumentProxyAdapter(viewController: self)
      controller.document = document
      self.controller = controller
      self.document = document

      let host = UIHostingController(
        rootView: KeyboardView(controller: controller, state: state, inputViewController: self))
      host.view.backgroundColor = .clear
      host.view.translatesAutoresizingMaskIntoConstraints = false
      addChild(host)
      view.addSubview(host.view)
      NSLayoutConstraint.activate([
        host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        host.view.topAnchor.constraint(equalTo: view.topAnchor),
        host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      ])
      host.didMove(toParent: self)

      let height = view.heightAnchor.constraint(equalToConstant: KeyboardMetrics.height(for: traitCollection))
      // below .required (the system's own constraints win while it sets the keyboard up), above its default height
      height.priority = UILayoutPriority(999)
      height.isActive = true
      heightConstraint = height
      registerForTraitChanges([UITraitVerticalSizeClass.self]) { (self: Self, _) in
        self.heightConstraint?.constant = KeyboardMetrics.height(for: self.traitCollection)
      }
    }

    override open func viewWillAppear(_ animated: Bool) {
      super.viewWillAppear(animated)
      updateState()
      guard let controller else { return }
      controller.activate(settings: KeyboardSettings.load())
      // Another field (or the same one later): the preceding text is not the context of the last commit.
      controller.documentChangedExternally()
      switch textDocumentProxy.keyboardType {
      case .numberPad, .decimalPad, .phonePad, .numbersAndPunctuation, .asciiCapableNumberPad:
        controller.perform(.inputMode(.digit))
      case .URL, .emailAddress, .asciiCapable, .webSearch, .twitter:
        controller.perform(.inputMode(.alphabet))
      default:
        controller.perform(.inputMode(.hiragana))
      }
    }

    override open func viewWillDisappear(_ animated: Bool) {
      super.viewWillDisappear(animated)
      guard let controller else { return }
      Task { await controller.deactivate() }
    }

    override open func textDidChange(_ textInput: (any UITextInput)?) {
      super.textDidChange(textInput)
      // Only the return key type and the like: whether UIKit also calls this after the keyboard's own edits is
      // not specified, so the composition is not touched here.
      updateState()
    }

    private func updateState() {
      state.returnKeyType = textDocumentProxy.returnKeyType ?? .default
      state.needsInputModeSwitchKey = needsInputModeSwitchKey
      state.hasFullAccess = hasFullAccess
    }
  }

  /// UITextDocumentProxy as the controller's text field.
  @MainActor
  final class TextDocumentProxyAdapter: KeyboardTextDocument {
    private unowned let viewController: UIInputViewController

    init(viewController: UIInputViewController) {
      self.viewController = viewController
    }

    private func edit(_ body: (any UITextDocumentProxy) -> Void) {
      body(viewController.textDocumentProxy)
    }

    func insertText(_ text: String) { edit { $0.insertText(text) } }
    func deleteBackward() { edit { $0.deleteBackward() } }
    func setMarkedText(_ text: String, selectedRange: NSRange) {
      edit { $0.setMarkedText(text, selectedRange: selectedRange) }
    }
    func unmarkText() { edit { $0.unmarkText() } }
    func adjustTextPosition(byCharacterOffset offset: Int) { edit { $0.adjustTextPosition(byCharacterOffset: offset) } }
    var precedingText: String? { viewController.textDocumentProxy.documentContextBeforeInput }
  }

  /// What the keyboard view needs to know about the text field and the extension.
  @MainActor
  @Observable
  final class KeyboardHostState {
    var returnKeyType: UIReturnKeyType = .default
    var needsInputModeSwitchKey = true
    var hasFullAccess = false
    /// The candidate bar is expanded to a grid over the keys.
    var showsAllCandidates = false
    /// A 12-key key is held long enough to show its guide: the other keys' labels dim.
    var showsFlickGuide = false
  }
#endif
