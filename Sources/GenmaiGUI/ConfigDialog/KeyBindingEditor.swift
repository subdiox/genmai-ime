// Port of mozc/src/gui/config_dialog/keybinding_editor.{h,cc,ui} and keybinding_editor_delegate.{h,cc}
// (3.35.6354).
//
// The Qt KeyBindingFilter observes QKeyEvents on a QLineEdit and builds a Mozc key string ("Ctrl Shift a",
// "Hiragana", ...). The Swift port keeps the filter as a pure value type fed with `KeyBindingInput`s (so it
// can be unit tested) and converts NSEvents into those inputs in `KeyBindingInput.init?(event:)`, which plays
// the role of Qt's key code translation on macOS (Qt::Key_Meta == Control, Qt::Key_Alt == Option; the
// Command key is ignored).

#if os(macOS)
  import AppKit
  import Carbon.HIToolbox
  import Observation
  import SwiftUI

  /// A key as the Qt filter sees it (the relevant part of QKeyEvent::key()).
  public enum KeyBindingInput: Equatable, Sendable {
    /// Qt::Key_Meta on macOS (the Control key).
    case control
    /// Qt::Key_Alt on macOS (the Option key).
    case option
    case shift
    /// A key of kQtKeyModifierNonRequiredTable, already translated ("Escape", "F1", "Hiragana", ...).
    case nonModifierRequired(String)
    /// Qt::Key_yen.
    case yen
    /// A printable Qt key code (0x21-0x60, 0x7B-0x7E; letters are uppercase 0x41-0x5A).
    case printable(UInt32)
    /// Anything else.
    case unknown(keyCode: UInt16)
  }

  /// Port of key_binding_editor_internal::KeyBindingFilter.
  public struct KeyBindingFilter: Equatable, Sendable {
    public enum KeyState: Equatable, Sendable {
      case denyKey
      case acceptKey
      case submitKey
    }

    private(set) var committed = false
    private var ctrlPressed = false
    private var altPressed = false
    private var shiftPressed = false
    private var modifierRequiredKey = ""
    private var modifierNonRequiredKey = ""
    private var unknownKey = ""

    public init() {
      reset()
    }

    /// Reset(). (The Qt version also disables the OK button; the caller tracks `okEnabled`.)
    public mutating func reset() {
      ctrlPressed = false
      altPressed = false
      shiftPressed = false
      modifierRequiredKey = ""
      modifierNonRequiredKey = ""
      unknownKey = ""
      committed = true
    }

    private static func isAlphabet(_ key: Character?) -> Bool {
      guard let key, let ascii = key.asciiValue else { return false }
      return ascii >= UInt8(ascii: "a") && ascii <= UInt8(ascii: "z")
    }

    /// Encode().
    public func encode() -> (KeyState, String) {
      // We don't accept any modifier keys for Hiragana, Eisu, Hankaku/Zenkaku keys.
      if ["Hiragana", "Katakana", "Eisu", "Hankaku/Zenkaku"].contains(modifierNonRequiredKey) {
        return (.submitKey, modifierNonRequiredKey)
      }

      var results: [String] = []
      if ctrlPressed {
        results.append("Ctrl")
      }
      if shiftPressed {
        results.append("Shift")
      }
      if altPressed {
        results.append("Option")
      }
      let hasModifier = !results.isEmpty
      if !modifierNonRequiredKey.isEmpty {
        results.append(modifierNonRequiredKey)
      }
      if !modifierRequiredKey.isEmpty {
        results.append(modifierRequiredKey)
      }
      // in release binary, unknown_key_ is hidden
      #if DEBUG
        if !unknownKey.isEmpty {
          results.append(unknownKey)
        }
      #endif

      var state = KeyState.acceptKey
      if !unknownKey.isEmpty {
        state = .denyKey
      }
      let key = modifierRequiredKey.first

      // Alt or Ctrl or these combinations
      if (altPressed || ctrlPressed) && modifierNonRequiredKey.isEmpty && modifierRequiredKey.isEmpty {
        state = .denyKey
      }
      // Don't support Shift only
      if shiftPressed && !ctrlPressed && !altPressed && modifierRequiredKey.isEmpty
        && modifierNonRequiredKey.isEmpty
      {
        state = .denyKey
      }
      // Don't support Shift + 'a' only
      if shiftPressed && !ctrlPressed && !altPressed && !modifierRequiredKey.isEmpty
        && Self.isAlphabet(key)
      {
        state = .denyKey
      }
      // Don't support Shift + Ctrl + '@'
      if shiftPressed && !modifierRequiredKey.isEmpty && !Self.isAlphabet(key) {
        state = .denyKey
      }
      // no modifier for modifier_required_key
      if !hasModifier && !modifierRequiredKey.isEmpty {
        state = .denyKey
      }
      // modifier_required_key and modifier_non_required_key cannot co-exist
      if !modifierRequiredKey.isEmpty && !modifierNonRequiredKey.isEmpty {
        state = .denyKey
      }
      // no valid key
      if results.isEmpty {
        state = .denyKey
      }
      return (state, results.joined(separator: " "))
    }

    /// AddKey().
    public mutating func addKey(_ input: KeyBindingInput) -> (KeyState, String) {
      switch input {
      case .control:
        ctrlPressed = true
      case .option:
        altPressed = true
      case .shift:
        shiftPressed = true
      case .nonModifierRequired(let name):
        modifierNonRequiredKey = name
      case .yen:
        // Japanese Yen mark, treat it as backslash for compatibility
        modifierNonRequiredKey = "\\"
      case .printable(let code):
        if code >= 0x41 && code <= 0x5A {
          modifierRequiredKey = String(UnicodeScalar(UInt8(code - 0x41 + 0x61)))
        } else if let scalar = UnicodeScalar(code) {
          modifierRequiredKey = String(scalar)
        }
      case .unknown:
        // The Qt code calls `unknown_key_.asprintf(...)`, which is a static QString factory in Qt 5.5+
        // and leaves unknown_key_ empty; unknown keys therefore never show up. Kept as is.
        break
      }
      return encode()
    }

    /// eventFilter(KeyPress): returns the new line edit text and whether OK is enabled.
    public mutating func keyPress(_ input: KeyBindingInput) -> (text: String, okEnabled: Bool) {
      // when the state is committed, reset the internal key binding
      if committed {
        reset()
      }
      committed = false
      let (state, result) = addKey(input)
      if state == .submitKey {
        committed = true
      }
      return (result, state != .denyKey)
    }

    /// eventFilter(KeyRelease): any release commits the current state.
    public mutating func keyRelease() {
      committed = true
    }
  }

  extension KeyBindingInput {
    /// The keys of kQtKeyModifierNonRequiredTable, by macOS virtual key code.
    static let nonModifierRequiredKeys: [Int: String] = [
      kVK_Escape: "Escape", kVK_Tab: "Tab", kVK_Delete: "Backspace", kVK_Return: "Enter",
      kVK_ANSI_KeypadEnter: "Enter", kVK_Help: "Insert", kVK_ForwardDelete: "Delete", kVK_Home: "Home",
      kVK_End: "End", kVK_LeftArrow: "Left", kVK_UpArrow: "Up", kVK_RightArrow: "Right",
      kVK_DownArrow: "Down", kVK_PageUp: "PageUp", kVK_PageDown: "PageDown", kVK_Space: "Space",
      kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
      kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
      kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19",
      kVK_F20: "F20",
      // Qt maps the JIS Eisu key to Key_Eisu_toggle and the Kana key to Key_Hiragana_Katakana-like keys;
      // Mozc's key names for them are "Eisu" and "Hiragana".
      kVK_JIS_Eisu: "Eisu", kVK_JIS_Kana: "Hiragana",
    ]

    /// Translates a keyDown event (`keyCode` + `charactersIgnoringModifiers`).
    public init(keyCode: UInt16, charactersIgnoringModifiers: String) {
      if let name = Self.nonModifierRequiredKeys[Int(keyCode)] {
        self = .nonModifierRequired(name)
        return
      }
      if Int(keyCode) == kVK_JIS_Yen {
        self = .yen
        return
      }
      guard let scalar = charactersIgnoringModifiers.unicodeScalars.first else {
        self = .unknown(keyCode: keyCode)
        return
      }
      if scalar == "\u{A5}" {
        self = .yen
        return
      }
      var code = scalar.value
      // Qt reports letters as upper case key codes.
      if code >= 0x61 && code <= 0x7A {
        code -= 0x20
      }
      if (code >= 0x21 && code <= 0x60) || (code >= 0x7B && code <= 0x7E) {
        self = .printable(code)
      } else {
        self = .unknown(keyCode: keyCode)
      }
    }

    /// Translates a flagsChanged event into a modifier press; nil for releases / other modifiers.
    public init?(modifierKeyCode keyCode: UInt16, flags: NSEvent.ModifierFlags) {
      switch Int(keyCode) {
      case kVK_Control, kVK_RightControl:
        guard flags.contains(.control) else { return nil }
        self = .control
      case kVK_Option, kVK_RightOption:
        guard flags.contains(.option) else { return nil }
        self = .option
      case kVK_Shift, kVK_RightShift:
        guard flags.contains(.shift) else { return nil }
        self = .shift
      default:
        return nil
      }
    }
  }

  // MARK: - KeyBindingEditor dialog

  @MainActor
  @Observable
  public final class KeyBindingEditorModel {
    public var binding: String
    public private(set) var okEnabled = false
    /// True once a key was pressed (the field then shows whether the combination can be assigned).
    public private(set) var hasPressedKey = false
    /// Whether the capture field has keyboard focus.
    var isCapturing = false
    private var filter = KeyBindingFilter()

    public init(binding: String) {
      self.binding = binding
    }

    public func keyPress(_ input: KeyBindingInput) {
      let (text, ok) = filter.keyPress(input)
      binding = text
      okEnabled = ok
      hasPressedKey = true
    }

    public func keyRelease() {
      filter.keyRelease()
    }

    /// The pressed combination cannot be assigned.
    public var isInvalid: Bool { hasPressedKey && !okEnabled && !binding.isEmpty }
  }

  /// The key binding editor sheet opened from a row of the keymap editor.
  struct KeyBindingEditorView: View {
    @State private var model: KeyBindingEditorModel
    let onFinish: (String?) -> Void

    init(binding: String, onFinish: @escaping (String?) -> Void) {
      _model = State(initialValue: KeyBindingEditorModel(binding: binding))
      self.onFinish = onFinish
    }

    var body: some View {
      // Return and Escape are keys that can be assigned, so OK is not the default button.
      EditorSheet(
        title: TableEditorStrings.text(.keyBindingTitle),
        message: TableEditorStrings.text(.keyBindingMessage),
        okEnabled: model.okEnabled,
        okIsDefault: false,
        onCancel: { onFinish(nil) },
        onOK: { onFinish(model.binding) }
      ) {
        KeyCaptureWell(model: model)
      }
      .frame(width: 360)
    }
  }

  /// The large field that shows the captured key, with a focus ring while it captures.
  struct KeyCaptureWell: View {
    let model: KeyBindingEditorModel

    var body: some View {
      VStack(spacing: 6) {
        ZStack {
          KeyCaptureField(model: model)
          KeyCaptureLabel(binding: model.binding)
            .allowsHitTesting(false)
        }
        .frame(height: 56)
        .background(.background, in: .rect(cornerRadius: 8))
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .strokeBorder(
              model.isCapturing ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
              lineWidth: model.isCapturing ? 2 : 1)
        }
        Text(verbatim: TableEditorStrings.text(.keyBindingInvalid))
          .font(.caption)
          .foregroundStyle(.secondary)
          .opacity(model.isInvalid ? 1 : 0)
          .accessibilityHidden(!model.isInvalid)
      }
    }
  }

  struct KeyCaptureLabel: View {
    let binding: String

    var body: some View {
      if binding.isEmpty {
        Text(verbatim: TableEditorStrings.text(.keyBindingPlaceholder))
          .font(.title3)
          .foregroundStyle(.tertiary)
      } else {
        Text(verbatim: KeyDisplayFormatter.display(binding))
          .font(.system(.title2, design: .rounded, weight: .medium))
          .help(binding)
      }
    }
  }

  /// A focused view that captures raw key events (the QLineEdit with the event filter installed).
  struct KeyCaptureField: NSViewRepresentable {
    let model: KeyBindingEditorModel

    func makeNSView(context: Context) -> KeyCaptureNSView {
      let view = KeyCaptureNSView()
      view.model = model
      return view
    }

    func updateNSView(_ view: KeyCaptureNSView, context: Context) {
      view.model = model
    }
  }

  final class KeyCaptureNSView: NSView {
    var model: KeyBindingEditorModel?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
      setCapturing(true)
      return true
    }

    override func resignFirstResponder() -> Bool {
      setCapturing(false)
      return true
    }

    /// Updates the model outside of the current view update (first responder changes happen during layout).
    private func setCapturing(_ capturing: Bool) {
      Task { @MainActor [weak self] in
        self?.model?.isCapturing = capturing
      }
    }

    override func mouseDown(with event: NSEvent) {
      window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
      // ignores auto key repeat. just eat the event
      if event.isARepeat {
        return
      }
      model?.keyPress(
        KeyBindingInput(
          keyCode: event.keyCode, charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? ""))
    }

    override func keyUp(with event: NSEvent) {
      model?.keyRelease()
    }

    override func flagsChanged(with event: NSEvent) {
      if let input = KeyBindingInput(modifierKeyCode: event.keyCode, flags: event.modifierFlags) {
        model?.keyPress(input)
      } else {
        model?.keyRelease()
      }
    }

    // Swallow Cmd-less key equivalents (Esc / Return) so they are captured instead of closing the sheet.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
      if window?.firstResponder === self, !event.modifierFlags.contains(.command) {
        keyDown(with: event)
        return true
      }
      return super.performKeyEquivalent(with: event)
    }

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .textField }

    override func accessibilityLabel() -> String? { TableEditorStrings.text(.keyBindingTitle) }

    override func accessibilityValue() -> Any? { model?.binding }
  }
#endif
